import Foundation
import SQLite3

public enum DatabaseError: LocalizedError, Sendable {
    case openFailed(String)
    case sqlFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(path): return "Failed to open database at \(path)"
        case let .sqlFailed(sql, message): return "SQL failed: \(message) — \(sql)"
        }
    }
}

/// Bound SQL parameter.
public enum SQLValue: Sendable {
    case int(Int64)
    case text(String)
    case null
}

/// One result row with by-name column access (mirrors the reference
/// implementation's dictionary rows, including LEFT JOIN columns).
public struct Row {
    fileprivate let stmt: OpaquePointer
    private let indexByName: [String: Int32]

    fileprivate init(stmt: OpaquePointer) {
        self.stmt = stmt
        var map: [String: Int32] = [:]
        let count = sqlite3_column_count(stmt)
        for i in 0..<count {
            if let name = sqlite3_column_name(stmt, i) {
                map[String(cString: name)] = i
            }
        }
        self.indexByName = map
    }

    public subscript(_ column: String) -> SQLValue? {
        guard let i = indexByName[column] else { return nil }
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_NULL: return .null
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(stmt, i))
        default:
            if let cString = sqlite3_column_text(stmt, i) {
                return .text(String(cString: cString))
            }
            return .null
        }
    }

    public func text(_ column: String) -> String? {
        if case let .text(value)? = self[column] { return value }
        return nil
    }

    public func int(_ column: String) -> Int? {
        if case let .int(value)? = self[column] { return Int(value) }
        return nil
    }

    public func isNull(_ column: String) -> Bool {
        if case .null? = self[column] { return true }
        return false
    }
}

/// SQLite database service. Contract source: shared/spec/DATA-FORMAT.md and
/// the frozen reference implementation. Table layout, column names, migration
/// version (4), default "工作" list, and every query's WHERE/ORDER BY are kept
/// byte-compatible so existing .db files open in place.
///
/// All access is serialized on an internal queue; the class is safe to share.
public final class SQLiteDatabase: @unchecked Sendable {
    /// Schema version pragma; migrations run in lockstep across platforms.
    public static let databaseVersion: Int32 = 4

    private let queue = DispatchQueue(label: "app.taskly.sqlite")
    private var handle: OpaquePointer?
    private var customPath: String?

    public init() {}

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    // MARK: - Connection

    public func setDatabasePath(_ path: String) {
        queue.sync {
            customPath = path
            closeLocked()
        }
    }

    public func getDatabasePath() -> String {
        queue.sync { customPath ?? PathUtils.defaultDatabasePath }
    }

    /// Opens (creating and migrating as needed) the database connection.
    public func ensureConnected() throws {
        try queue.sync {
            if handle != nil { return }
            try openLocked()
        }
    }

    public func close() {
        queue.sync { closeLocked() }
    }

    private func closeLocked() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    private func openLocked() throws {
        let dbPath = customPath ?? PathUtils.defaultDatabasePath
        let dir = (dbPath as NSString).deletingLastPathComponent
        if !dir.isEmpty && !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            throw DatabaseError.openFailed(dbPath)
        }
        handle = db

        // WAL: safer when the .db lives in a cloud-synced folder; persistent
        // once set, harmless to re-issue on every connection.
        try execLocked("PRAGMA journal_mode=WAL;")

        try createOrUpgradeLocked()
        // Belt-and-braces column check (matches reference behavior).
        try ensureColumnLocked(table: "lists", column: "icon", type: "TEXT")
        try ensureColumnLocked(table: "lists", column: "color", type: "INTEGER")
    }

    // MARK: - Schema

    private func createOrUpgradeLocked() throws {
        let oldVersion = userVersionLocked()

        if oldVersion == 0 {
            try createAllLocked()
        } else {
            if oldVersion < 2 { try createIndexesLocked() }
            if oldVersion < 3 {
                try ensureColumnLocked(table: "lists", column: "icon", type: "TEXT")
                try ensureColumnLocked(table: "lists", column: "color", type: "INTEGER")
            }
            if oldVersion < 4 {
                try ensureColumnLocked(table: "tasks", column: "due_time", type: "TEXT")
                try ensureColumnLocked(table: "tasks", column: "notes", type: "TEXT")
            }
        }

        // user_version is a schema pragma; must be set outside a transaction.
        try execLocked("PRAGMA user_version = \(SQLiteDatabase.databaseVersion)")
    }

    private func userVersionLocked() -> Int32 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }

    private func createAllLocked() throws {
        try execLocked("""
            CREATE TABLE lists (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                icon TEXT,
                color INTEGER,
                created_at TEXT NOT NULL
            )
            """)
        try execLocked("""
            CREATE TABLE tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                list_id INTEGER,
                text TEXT NOT NULL,
                due_date TEXT,
                due_time TEXT,
                completed INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                notes TEXT,
                FOREIGN KEY (list_id) REFERENCES lists (id)
            )
            """)
        try createIndexesLocked()

        // Default "工作" list, byte-compatible with the reference impl.
        try execLocked(
            "INSERT INTO lists (name, icon, color, created_at) VALUES (?, ?, ?, ?)",
            [.text("工作"), .text(TodoList.defaultIcon), .int(Int64(TodoList.defaultColor)),
             .text(DateParser.createdAtNow())])
    }

    private func createIndexesLocked() throws {
        try execLocked("CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id)")
        try execLocked("CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed)")
        try execLocked("CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date)")
    }

    private func ensureColumnLocked(table: String, column: String, type: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
            throw lastErrorLocked(sql: "PRAGMA table_info(\(table))")
        }
        defer { sqlite3_finalize(stmt) }
        var exists = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 1),
               String(cString: namePtr) == column {
                exists = true
                break
            }
        }
        if !exists {
            try execLocked("ALTER TABLE \(table) ADD COLUMN \(column) \(type)")
        }
    }

    // MARK: - Lists

    public func getAllLists() throws -> [TodoList] {
        try ensureConnected()
        return try queue.sync {
            try queryRows("SELECT * FROM lists") { row in
                TodoList(
                    id: row.int("id") ?? 0,
                    name: row.text("name") ?? "",
                    icon: row.text("icon"),
                    color: row.int("color"))
            }
        }
    }

    public func getListById(_ id: Int) throws -> TodoList? {
        try ensureConnected()
        return try queue.sync {
            try queryRows("SELECT * FROM lists WHERE id = ?", [.int(Int64(id))] as [SQLValue?]) { row in
                TodoList(
                    id: row.int("id") ?? 0,
                    name: row.text("name") ?? "",
                    icon: row.text("icon"),
                    color: row.int("color"))
            }.first
        }
    }

    /// Case-sensitive exact match; nil when absent.
    public func getListByName(_ name: String) throws -> TodoList? {
        try ensureConnected()
        return try queue.sync {
            try queryRows("SELECT * FROM lists WHERE name = ? LIMIT 1", [.text(name)] as [SQLValue?]) { row in
                TodoList(
                    id: row.int("id") ?? 0,
                    name: row.text("name") ?? "",
                    icon: row.text("icon"),
                    color: row.int("color"))
            }.first
        }
    }

    /// Default icon/color filled in macOS-Reminders style when not provided.
    @discardableResult
    public func addList(name: String, icon: String? = nil, color: Int? = nil) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            let icon = icon ?? TodoList.defaultIcon
            let color = color ?? TodoList.defaultColor
            try execLocked(
                "INSERT INTO lists (name, created_at, icon, color) VALUES (?, ?, ?, ?)",
                [.text(name), .text(DateParser.createdAtNow()), .text(icon), .int(Int64(color))])
            return lastInsertRowIdLocked()
        }
    }

    @discardableResult
    public func updateList(id: Int, name: String, icon: String? = nil, color: Int? = nil,
                           clearIcon: Bool = false, clearColor: Bool = false) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            var sql = "UPDATE lists SET name = ?"
            var binds: [SQLValue?] = [.text(name)]
            if clearIcon {
                sql += ", icon = NULL"
            } else if let icon {
                sql += ", icon = ?"
                binds.append(.text(icon))
            }
            if clearColor {
                sql += ", color = NULL"
            } else if let color {
                sql += ", color = ?"
                binds.append(.int(Int64(color)))
            }
            sql += " WHERE id = ?"
            binds.append(.int(Int64(id)))
            return try execLocked(sql, binds)
        }
    }

    /// Deletes the list's tasks first, then the list (reference behavior).
    @discardableResult
    public func deleteList(id: Int) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            _ = try execLocked("DELETE FROM tasks WHERE list_id = ?", [.int(Int64(id))])
            return try execLocked("DELETE FROM lists WHERE id = ?", [.int(Int64(id))])
        }
    }

    // MARK: - Tasks (queries)

    private static let taskSelectBase = """
        SELECT t.*, l.name AS list_name
        FROM tasks t
        LEFT JOIN lists l ON t.list_id = l.id
        """

    private func task(from row: Row) -> TaskItem {
        let completed: Bool
        if case let .int(value)? = row["completed"] {
            completed = value == 1
        } else {
            completed = false
        }
        return TaskItem(
            id: row.int("id") ?? 0,
            listId: row.int("list_id") ?? 0,
            text: row.text("text") ?? "",
            createdAt: row.text("created_at") ?? "",
            dueDate: row.text("due_date"),
            dueTime: row.text("due_time"),
            completed: completed,
            notes: row.text("notes"),
            listName: row.text("list_name"))
    }

    public func getAllTasks() throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(SQLiteDatabase.taskSelectBase) { [weak self] row in
                self!.task(from: row)
            }
        }
    }

    /// All incomplete tasks with a due date (reminder scheduling source).
    public func getAllIncompleteTasksWithDueDate() throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.completed = 0 AND t.due_date IS NOT NULL"
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getTasksByList(_ listId: Int, limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.list_id = ? AND t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?",
                [.int(Int64(listId)), .int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getCompletedTasksByList(_ listId: Int, limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.list_id = ? AND t.completed = 1 LIMIT ? OFFSET ?",
                [.int(Int64(listId)), .int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getTasksByListIncludingCompleted(_ listId: Int, limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.list_id = ? ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?",
                [.int(Int64(listId)), .int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getAllTasksIncludingCompleted(limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?",
                [.int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getTodayTasks(limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            let today = DateParser.string(from: Date(), format: "yyyy-MM-dd")
            return try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE date(t.due_date) = ? AND t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?",
                [.text(today), .int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getTodayTasksIncludingCompleted(limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            let today = DateParser.string(from: Date(), format: "yyyy-MM-dd")
            return try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE date(t.due_date) = ? ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?",
                [.text(today), .int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getPlannedTasks(limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.due_date IS NOT NULL AND t.completed = 0 ORDER BY t.due_date ASC LIMIT ? OFFSET ?",
                [.int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getPlannedTasksIncludingCompleted(limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.due_date IS NOT NULL ORDER BY t.completed ASC, t.due_date ASC LIMIT ? OFFSET ?",
                [.int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    /// Dated tasks with due_date in [startDate, endDate] inclusive
    /// (yyyy-MM-dd strings; the calendar view queries months and the overdue
    /// tail with this — PRODUCT-SPEC §4b).
    public func getTasksInRange(startDate: String, endDate: String, includeCompleted: Bool = false,
                                limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            let completedFilter = includeCompleted ? "" : " AND t.completed = 0"
            return try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.due_date IS NOT NULL AND date(t.due_date) >= ? AND date(t.due_date) <= ?"
                    + completedFilter + " ORDER BY t.due_date ASC, t.id DESC LIMIT ? OFFSET ?",
                [.text(startDate), .text(endDate), .int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    /// Incomplete-task count per due date in [startDate, endDate] inclusive —
    /// the calendar month-grid day dots.
    public func getDueDayCounts(startDate: String, endDate: String) throws -> [(date: String, count: Int)] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "SELECT date(due_date) AS d, COUNT(*) AS c FROM tasks WHERE due_date IS NOT NULL AND completed = 0"
                    + " AND date(due_date) >= ? AND date(due_date) <= ? GROUP BY d",
                [.text(startDate), .text(endDate)]
            ) { row in (date: row.text("d") ?? "", count: row.int("c") ?? 0) }
        }
    }

    public func getIncompleteTasks(limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?",
                [.int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getCompletedTasks(limit: Int = 1000, offset: Int = 0) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.completed = 1 LIMIT ? OFFSET ?",
                [.int(Int64(limit)), .int(Int64(offset))]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    /// SQL LIKE %keyword% (matches the reference "fuzzy" search).
    public func searchTasks(_ keyword: String) throws -> [TaskItem] {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.text LIKE ?",
                [.text("%\(keyword)%")]
            ) { [weak self] row in self!.task(from: row) }
        }
    }

    public func getTaskById(_ id: Int) throws -> TaskItem? {
        try ensureConnected()
        return try queue.sync {
            try queryRows(
                "\(SQLiteDatabase.taskSelectBase) WHERE t.id = ?",
                [.int(Int64(id))]
            ) { [weak self] row in self!.task(from: row) }.first
        }
    }

    // MARK: - Tasks (counts)

    public func getTaskCountByList(_ listId: Int) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            scalar("SELECT COUNT(*) FROM tasks WHERE list_id = ? AND completed = 0", [.int(Int64(listId))])
        }
    }

    public func getIncompleteTaskCount() throws -> Int {
        try ensureConnected()
        return queue.sync { scalar("SELECT COUNT(*) FROM tasks WHERE completed = 0") }
    }

    public func getCompletedTaskCount() throws -> Int {
        try ensureConnected()
        return queue.sync { scalar("SELECT COUNT(*) FROM tasks WHERE completed = 1") }
    }

    public func getTodayTaskCount() throws -> Int {
        try ensureConnected()
        return try queue.sync {
            let today = DateParser.string(from: Date(), format: "yyyy-MM-dd")
            return scalar("SELECT COUNT(*) FROM tasks WHERE date(due_date) = ? AND completed = 0", [.text(today)])
        }
    }

    public func getPlannedTaskCount() throws -> Int {
        try ensureConnected()
        return try queue.sync {
            scalar("SELECT COUNT(*) FROM tasks WHERE due_date IS NOT NULL AND completed = 0")
        }
    }

    // MARK: - Tasks (writes)

    @discardableResult
    public func addTask(_ task: TaskItem) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            try execLocked(
                "INSERT INTO tasks (list_id, text, due_date, due_time, completed, created_at, notes) VALUES (?, ?, ?, ?, ?, ?, ?)",
                taskBinds(task, includeId: false))
            return lastInsertRowIdLocked()
        }
    }

    @discardableResult
    public func updateTask(_ task: TaskItem) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            try execLocked(
                """
                UPDATE tasks
                SET list_id = ?, text = ?, due_date = ?, due_time = ?, completed = ?, notes = ?
                WHERE id = ?
                """,
                [.int(Int64(task.listId)), .text(task.text),
                 task.dueDate.map { SQLValue.text($0) } ?? .null,
                 task.dueTime.map { SQLValue.text($0) } ?? .null,
                 .int(task.completed ? 1 : 0),
                 task.notes.map { SQLValue.text($0) } ?? .null,
                 .int(Int64(task.id))])
        }
    }

    /// Read-then-flip toggle (reference toggleTaskCompleted semantics).
    @discardableResult
    public func toggleTaskCompleted(_ id: Int) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            let rows = try queryRows("SELECT completed FROM tasks WHERE id = ?", [.int(Int64(id))]) { row in
                row.int("completed") ?? 0
            }
            guard let current = rows.first else { return 0 }
            return try execLocked(
                "UPDATE tasks SET completed = ? WHERE id = ?",
                [.int(current == 1 ? 0 : 1), .int(Int64(id))])
        }
    }

    /// Idempotent completion set (unlike toggle). Returns affected rows
    /// (0 = task not found).
    @discardableResult
    public func setTaskCompleted(_ id: Int, _ completed: Bool) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            try execLocked(
                "UPDATE tasks SET completed = ? WHERE id = ?",
                [.int(completed ? 1 : 0), .int(Int64(id))])
        }
    }

    @discardableResult
    public func deleteTask(_ id: Int) throws -> Int {
        try ensureConnected()
        return try queue.sync {
            try execLocked("DELETE FROM tasks WHERE id = ?", [.int(Int64(id))])
        }
    }

    private func taskBinds(_ task: TaskItem, includeId: Bool) -> [SQLValue?] {
        [
            .int(Int64(task.listId)),
            .text(task.text),
            task.dueDate.map { SQLValue.text($0) } ?? .null,
            task.dueTime.map { SQLValue.text($0) } ?? .null,
            .int(task.completed ? 1 : 0),
            .text(task.createdAt),
            task.notes.map { SQLValue.text($0) } ?? .null,
        ]
    }

    // MARK: - Low-level helpers (call on queue)

    @discardableResult
    private func execLocked(_ sql: String, _ binds: [SQLValue?] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastErrorLocked(sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        try bindValues(stmt, binds)

        // Row-returning statements (e.g. `PRAGMA journal_mode=WAL`) step to
        // SQLITE_ROW first; consume rows until DONE.
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_DONE:
                return Int(sqlite3_changes(handle))
            case SQLITE_ROW:
                continue
            default:
                throw lastErrorLocked(sql: sql)
            }
        }
    }

    private func queryRows<RowValue>(_ sql: String, _ binds: [SQLValue?] = [],
                                     _ map: (Row) -> RowValue) throws -> [RowValue] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastErrorLocked(sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        try bindValues(stmt, binds)

        var results: [RowValue] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(map(Row(stmt: stmt!)))
        }
        return results
    }

    private func scalar(_ sql: String, _ binds: [SQLValue?] = []) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        try? bindValues(stmt, binds)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func bindValues(_ stmt: OpaquePointer?, _ binds: [SQLValue?]) throws {
        for (offset, value) in binds.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .none, .null:
                sqlite3_bind_null(stmt, index)
            case let .int(v):
                sqlite3_bind_int64(stmt, index, v)
            case let .text(v):
                sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT)
            }
        }
    }

    private func lastInsertRowIdLocked() -> Int {
        Int(sqlite3_last_insert_rowid(handle))
    }

    private func lastErrorLocked(sql: String) -> DatabaseError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return .sqlFailed(sql, message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
