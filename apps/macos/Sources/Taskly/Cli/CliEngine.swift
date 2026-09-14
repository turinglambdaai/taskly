import Foundation

/// Taskly CLI engine. Any launch with arguments routes here before any GUI
/// toolkit initialization (headless-safe). Contract: shared/spec/CLI-SPEC.md.
public enum CliEngine {
    public static let version = AppVersion.short

    /// Entry point; returns the process exit code.
    @discardableResult
    public static func run(_ args: [String]) -> Int32 {
        // Global flags may appear anywhere (recursive options).
        var json = false
        var quiet = false
        var dbPath: String?
        var rest: [String] = []
        var error: AppError?

        var index = 0
        while index < args.count, error == nil {
            let token = args[index]
            switch token {
            case "--json": json = true
            case "--quiet", "-q": quiet = true
            case "--db":
                if index + 1 < args.count {
                    dbPath = args[index + 1]
                    index += 1
                } else {
                    error = AppError("Missing value for --db", .validation)
                }
            default:
                rest.append(token)
            }
            index += 1
        }

        guard error == nil, let command = rest.first else {
            let message = error?.message
                ?? "Usage: taskly <command> [options]\nCommands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli"
            return fail(message, error?.exitCode ?? 1)
        }

        do {
            let ctx = try CliContext.create(command: command, dbPath: dbPath, json: json, quiet: quiet)
            defer { ctx.db.close() }
            switch command {
            case "list": return try cmdList(ctx, Array(rest.dropFirst()))
            case "lists": return try cmdLists(ctx)
            case "add": return try cmdAdd(ctx, Array(rest.dropFirst()))
            case "update": return try cmdUpdate(ctx, Array(rest.dropFirst()))
            case "done": return try cmdDone(ctx, Array(rest.dropFirst()), completed: true)
            case "undone": return try cmdDone(ctx, Array(rest.dropFirst()), completed: false)
            case "rm": return try cmdRm(ctx, Array(rest.dropFirst()))
            case "search": return try cmdSearch(ctx, Array(rest.dropFirst()))
            case "mklist": return try cmdMkList(ctx, Array(rest.dropFirst()))
            case "rmlist": return try cmdRmList(ctx, Array(rest.dropFirst()))
            case "install-cli": return try CliInstaller.install()
            case "uninstall-cli": return try CliInstaller.uninstall()
            case "--help", "-h", "help":
                print("Taskly — task manager command-line interface (for AI agents & scripting)")
                print("Commands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli")
                print("Global options: --json, --db <path>, --quiet (-q)")
                return 0
            default:
                return fail("Unknown command: \"\(command)\"", 1)
            }
        } catch let appError as AppError {
            return fail(appError.message, appError.exitCode)
        } catch let dbError as DatabaseError {
            return fail("Database error: \(dbError.localizedDescription)", 4)
        } catch {
            return fail("\(error)", 1)
        }
    }

    static func fail(_ message: String, _ code: Int32) -> Int32 {
        FileHandle.standardError.write(
            (CliJson.render(.errorObject(message, code)) + "\n").data(using: .utf8)!)
        return code
    }

    // MARK: - Options parsing

    struct Options {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var positionals: [String] = []

        func value(_ name: String) -> String? { values[name] }
        func has(_ name: String) -> Bool { flags.contains(name) }
    }

    private static let valueOptions: Set<String> = [
        "--list", "--view", "--status", "--limit", "--due", "--time",
        "--notes", "--icon", "--color", "--text",
    ]
    private static let flagOptions: Set<String> = [
        "--clear-due", "--clear-time", "--clear-notes",
    ]

    static func parseOptions(_ args: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < args.count {
            let token = args[index]
            if token == "--" {
                options.positionals.append(contentsOf: args[(index + 1)...])
                break
            }
            if token.hasPrefix("--") {
                let (name, inlineValue) = splitOption(token)
                if valueOptions.contains(name) {
                    let value: String
                    if let inlineValue {
                        value = inlineValue
                    } else if index + 1 < args.count {
                        index += 1
                        value = args[index]
                    } else {
                        throw AppError("Missing value for \(name)", .validation)
                    }
                    options.values[name] = value
                } else if flagOptions.contains(name) {
                    options.flags.insert(name)
                } else {
                    throw AppError("Unknown option: \(name)", .validation)
                }
            } else if token.hasPrefix("-"), token.count > 1 {
                throw AppError("Unknown option: \(token)", .validation)
            } else {
                options.positionals.append(token)
            }
            index += 1
        }
        return options
    }

    private static func splitOption(_ token: String) -> (name: String, value: String?) {
        guard let eq = token.firstIndex(of: "=") else { return (token, nil) }
        return (String(token[..<eq]), String(token[token.index(after: eq)...]))
    }

    static func requirePositional(_ options: Options, _ index: Int, _ what: String) throws -> String {
        guard index < options.positionals.count else {
            throw AppError("Missing required argument: <\(what)>", .validation)
        }
        return options.positionals[index]
    }

    static func parseInt(_ s: String, _ what: String) throws -> Int {
        guard let v = Int(s) else {
            throw AppError("Invalid \(what): \"\(s)\"", .validation)
        }
        return v
    }

    // MARK: - Shared helpers

    /// --list resolution: numeric → id, else case-sensitive exact name.
    static func resolveListId(_ ctx: CliContext, _ list: String) throws -> Int {
        if let id = Int(list) {
            return id
        }
        guard let found = try ctx.lists.getListByName(list) else {
            throw AppError("List not found by name: \"\(list)\"", .notFound)
        }
        return found.id
    }

    /// CLI --due wrapper: bare-word pre-mapping + DateParser + date-only intent.
    static func parseDue(_ ctx: CliContext, _ due: String) throws -> (date: String?, time: String?) {
        let original = due.trimmingCharacters(in: .whitespaces)
        let lower = original.lowercased()
        let normalized: String
        switch lower {
        case "today": normalized = "+0d"
        case "tomorrow", "tmw": normalized = "+1d"
        case "tonight": normalized = "@20:00"
        default: normalized = original
        }

        guard let parsed = ctx.dateParser.parse(normalized) else {
            throw AppError(
                "Cannot parse date/time: \"\(due)\". "
                    + "Supported: +10m, +2h, +1d, +1w, @10am, @10:30pm, today, tomorrow, yyyy-MM-dd",
                .validation)
        }

        var date = DateParser.extractDateOnly(parsed)
        var time = DateParser.extractTimeOnly(parsed)

        // Date-only intent: bare words, +Nd/+Nw/+NM, or a 10-char absolute result.
        let isDateOnly = lower == "today" || lower == "tomorrow" || lower == "tmw"
            || (normalized.hasPrefix("+") && !normalized.isEmpty
                && ["d", "w", "M"].contains(String(normalized.suffix(1))))
            || parsed.count == 10

        if isDateOnly {
            time = nil
        }
        return (date, time)
    }

    static func parseColor(_ color: String) throws -> Int {
        if let argb = Int(color) {
            return argb
        }
        guard color.hasPrefix("#") else {
            throw AppError("Invalid color: \"\(color)\". Use #RRGGBB hex or ARGB int", .validation)
        }
        let hex = String(color.dropFirst())
        switch hex.count {
        case 6:
            guard let rgb = UInt32(hex, radix: 16) else {
                throw AppError(
                    "Invalid hex color: \"\(color)\". Use #RRGGBB (6) or #AARRGGBB (8)", .validation)
            }
            return ARGB.from(hex: 0xFF00_0000 | rgb)
        case 8:
            guard let argb = UInt32(hex, radix: 16) else {
                throw AppError(
                    "Invalid hex color: \"\(color)\". Use #RRGGBB (6) or #AARRGGBB (8)", .validation)
            }
            return ARGB.from(hex: argb)
        default:
            throw AppError(
                "Invalid hex color: \"\(color)\". Use #RRGGBB (6) or #AARRGGBB (8)", .validation)
        }
    }

    // MARK: - Output helpers

    static func printTask(_ ctx: CliContext, _ t: TaskItem) {
        if ctx.json {
            print(CliJson.render(.taskObject(t)))
            return
        }
        if ctx.quiet {
            print(t.id)
            return
        }
        print(humanTaskLine(t))
    }

    static func humanTaskLine(_ t: TaskItem) -> String {
        let mark = t.completed ? "[x]" : "[ ]"
        var due = ""
        if let dueDate = t.dueDate, !dueDate.isEmpty {
            due = "  🗓 \(dueDate)"
            if let dueTime = t.dueTime, !dueTime.isEmpty {
                due += " \(dueTime)"
            }
        }
        return String(format: "  %5d  %@  %@%@", t.id, mark, t.text, due)
    }

    static func printTasks(_ ctx: CliContext, _ tasks: [TaskItem]) {
        if ctx.json {
            print(CliJson.render(.array(tasks.map { .taskObject($0) })))
            return
        }
        if tasks.isEmpty {
            if !ctx.quiet {
                print("(no tasks)")
            }
            return
        }
        for t in tasks {
            printTask(ctx, t)
        }
    }

    static func printLists(_ ctx: CliContext, _ lists: [TodoList]) {
        if ctx.json {
            print(CliJson.render(.array(lists.map { .listObject($0) })))
            return
        }
        for l in lists {
            let icon = (l.icon?.isEmpty ?? true) ? "" : "\(l.icon!) "
            print(String(format: "  %5d  %@%@  (%d)", l.id, icon, l.name, l.pendingCount))
        }
    }

    // MARK: - Commands

    static func cmdList(_ ctx: CliContext, _ args: [String]) throws -> Int32 {
        let options = try parseOptions(args)
        let listArg = options.value("--list")
        let viewArg = options.value("--view")
        let statusArg = options.value("--status") ?? "incomplete"
        let limit = try parseInt(options.value("--limit") ?? "1000", "--limit")

        let view: TaskViewType
        var listId: Int?
        if let listArg, !listArg.isEmpty {
            view = .list(0)
            listId = try resolveListId(ctx, listArg)
        } else if viewArg == nil || viewArg!.isEmpty {
            view = .all
        } else {
            switch viewArg!.lowercased() {
            case "today": view = .today
            case "planned", "scheduled": view = .planned
            case "all": view = .all
            case "completed": view = .completed
            default:
                throw AppError(
                    "Invalid --view: \"\(viewArg!)\". Use today | planned | all | completed",
                    .validation)
            }
        }

        let showCompleted: Bool
        switch statusArg.lowercased() {
        case "all": showCompleted = true
        case "incomplete", "open", "pending": showCompleted = false
        case "completed", "done": showCompleted = true
        default:
            throw AppError(
                "Invalid --status: \"\(statusArg)\". Use all | incomplete | completed", .validation)
        }

        let effectiveView = listId.map { TaskViewType.list($0) } ?? view
        let tasks = try ctx.tasks.getTasksByView(effectiveView, limit: limit, showCompleted: showCompleted)
        printTasks(ctx, tasks)
        return 0
    }

    static func cmdLists(_ ctx: CliContext) throws -> Int32 {
        var lists = try ctx.lists.getAllLists()
        for i in lists.indices {
            lists[i].pendingCount = (try? ctx.tasks.getTaskCountByList(lists[i].id)) ?? 0
        }
        printLists(ctx, lists)
        return 0
    }

    static func cmdAdd(_ ctx: CliContext, _ args: [String]) throws -> Int32 {
        let options = try parseOptions(args)
        let text = try requirePositional(options, 0, "text")
        let listArg = options.value("--list")

        let listId: Int
        if let listArg, !listArg.isEmpty {
            listId = try resolveListId(ctx, listArg)
        } else if let defaultList = try ctx.lists.getDefaultList() {
            listId = defaultList.id
        } else {
            throw AppError(
                "No lists exist yet. Create one with `taskly mklist` first.", .notFound)
        }

        var dueDate: String?
        var dueTime: String?
        if let dueArg = options.value("--due"), !dueArg.isEmpty {
            (dueDate, dueTime) = try parseDue(ctx, dueArg)
        }
        if let timeArg = options.value("--time"), !timeArg.isEmpty {
            dueTime = timeArg
        }

        var task = TaskItem(
            id: 0, listId: listId, text: text, createdAt: DateParser.createdAtNow(),
            dueDate: dueDate, dueTime: dueTime, completed: false,
            notes: options.value("--notes"))
        task.id = try ctx.tasks.addTask(task)
        printTask(ctx, task)
        return 0
    }

    static func cmdUpdate(_ ctx: CliContext, _ args: [String]) throws -> Int32 {
        let options = try parseOptions(args)
        let idString = try requirePositional(options, 0, "id")
        let id = try parseInt(idString, "id")

        guard var task = try ctx.tasks.getTaskById(id) else {
            throw AppError("Task not found: \(id)", .notFound)
        }

        if let text = options.value("--text") {
            task.text = text
        }

        if options.has("--clear-due") {
            task.dueDate = nil
        } else if let dueArg = options.value("--due") {
            let (date, time) = try parseDue(ctx, dueArg)
            task.dueDate = date
            if let time {
                task.dueTime = time
            }
        }

        if options.has("--clear-time") {
            task.dueTime = nil
        } else if let timeArg = options.value("--time") {
            task.dueTime = timeArg
        }

        if let listArg = options.value("--list") {
            task.listId = try resolveListId(ctx, listArg)
        }

        if options.has("--clear-notes") {
            task.notes = nil
        } else if let notes = options.value("--notes") {
            task.notes = notes
        }

        try ctx.tasks.updateTask(task)
        printTask(ctx, task)
        return 0
    }

    static func cmdDone(_ ctx: CliContext, _ args: [String], completed: Bool) throws -> Int32 {
        let options = try parseOptions(args)
        let idString = try requirePositional(options, 0, "id")
        let id = try parseInt(idString, "id")

        let affected = try ctx.tasks.setTaskCompleted(id, completed)
        if affected == 0 {
            throw AppError("Task not found: \(id)", .notFound)
        }

        if ctx.json {
            if ctx.quiet {
                print(CliJson.render(.object([
                    ("ok", .bool(true)), ("id", .int(id)), ("completed", .bool(completed)),
                ])))
            } else if let task = try ctx.tasks.getTaskById(id) {
                print(CliJson.render(.taskObject(task)))
            }
        } else if !ctx.quiet, let task = try ctx.tasks.getTaskById(id) {
            print(humanTaskLine(task))
        }
        return 0
    }

    static func cmdRm(_ ctx: CliContext, _ args: [String]) throws -> Int32 {
        let options = try parseOptions(args)
        let idString = try requirePositional(options, 0, "id")
        let id = try parseInt(idString, "id")

        let deleted = (try? ctx.tasks.deleteTask(id)).map { $0 > 0 } ?? false

        if ctx.json {
            print(CliJson.render(.object([
                ("ok", .bool(true)), ("id", .int(id)), ("deleted", .bool(deleted)),
            ])))
        } else if !ctx.quiet {
            print(deleted ? "Deleted task \(id)" : "Task \(id) did not exist")
        }
        return 0
    }

    static func cmdSearch(_ ctx: CliContext, _ args: [String]) throws -> Int32 {
        let options = try parseOptions(args)
        let keyword = try requirePositional(options, 0, "keyword")
        let limit = try parseInt(options.value("--limit") ?? "100", "--limit")

        let results = try ctx.tasks.searchTasks(keyword)
        printTasks(ctx, Array(results.prefix(limit)))
        return 0
    }

    static func cmdMkList(_ ctx: CliContext, _ args: [String]) throws -> Int32 {
        let options = try parseOptions(args)
        let name = try requirePositional(options, 0, "name")
        let icon = options.value("--icon")
        let color: Int?
        if let colorHex = options.value("--color") {
            color = try parseColor(colorHex)
        } else {
            color = nil
        }

        let id: Int
        do {
            id = try ctx.lists.addList(name, icon: icon, color: color)
        } catch let appError as AppError where appError.type == .validation {
            throw appError
        }

        let created = (try? ctx.lists.getListById(id)) ?? TodoList(id: id, name: name, icon: icon, color: color)

        if ctx.json {
            print(CliJson.render(.listObject(created)))
        } else if ctx.quiet {
            print(id)
        } else {
            let iconText = (created.icon?.isEmpty ?? true) ? "" : "\(created.icon!) "
            print(String(format: "  %5d  %@%@  (%d)", created.id, iconText, created.name, 0))
        }
        return 0
    }

    static func cmdRmList(_ ctx: CliContext, _ args: [String]) throws -> Int32 {
        let options = try parseOptions(args)
        let idString = try requirePositional(options, 0, "id")
        let id = try parseInt(idString, "id")

        let deleted = (try? ctx.lists.deleteList(id)).map { $0 > 0 } ?? false

        if ctx.json {
            print(CliJson.render(.object([
                ("ok", .bool(true)), ("id", .int(id)), ("deleted", .bool(deleted)),
            ])))
        } else if !ctx.quiet {
            print(deleted ? "Deleted list \(id) (and its tasks)" : "List \(id) did not exist")
        }
        return 0
    }
}

/// Per-invocation context: opened DB + repositories.
final class CliContext {
    let db: SQLiteDatabase
    let tasks: TaskRepository
    let lists: ListRepository
    let dateParser = DateParser()
    let json: Bool
    let quiet: Bool

    init(db: SQLiteDatabase, json: Bool, quiet: Bool) {
        self.db = db
        let i18n = I18nService.shared
        self.tasks = TaskRepository(db: db, i18n: i18n)
        self.lists = ListRepository(db: db, i18n: i18n)
        self.json = json
        self.quiet = quiet
    }

    static func create(command: String, dbPath: String?, json: Bool, quiet: Bool) throws -> CliContext {
        // install-cli/uninstall-cli never touch the database.
        if command == "install-cli" || command == "uninstall-cli"
            || command == "--help" || command == "-h" || command == "help" {
            return CliContext(db: SQLiteDatabase(), json: json, quiet: quiet)
        }

        let db = SQLiteDatabase()
        if let dbPath {
            db.setDatabasePath(dbPath)
        } else {
            let config = ConfigService()
            config.load()
            if !config.lastDbPath.isEmpty {
                db.setDatabasePath(config.lastDbPath)
            }
        }

        do {
            try db.ensureConnected()
        } catch {
            throw AppError(
                "Cannot open database: \(db.getDatabasePath()) (\(error.localizedDescription))",
                .database)
        }
        return CliContext(db: db, json: json, quiet: quiet)
    }
}

public enum AppVersion {
    /// Marketing version (major.minor.patch).
    public static let current = "1.0.0"
    public static let short = current
}
