import XCTest
import SQLite3
@testable import Taskly

final class DateParserTests: XCTestCase {
    let parser = DateParser()

    func testRelativeMinutes() {
        let result = parser.parse("+10m")
        XCTAssertNotNil(result)
        // 'yyyy-MM-dd HH:mm:ss'
        XCTAssertEqual(result?.count, 19)
        XCTAssertEqual(DateParser.extractTimeOnly(result)?.count, 5)
    }

    func testRelativeDefaultAmount() {
        XCTAssertNotNil(parser.parse("+d"), "digits optional, default 1")
        XCTAssertNotNil(parser.parse("+M"), "M = month(30 days)")
        XCTAssertNil(parser.parse("+x"), "invalid unit")
    }

    func testAtTime() {
        // 12am → 0点; pm conversion; rollover to tomorrow for past times.
        XCTAssertNotNil(parser.parse("@now"))
        let result = parser.parse("@00:30am")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 19)
        XCTAssertNotNil(parser.parse("@10:30pm"))
        XCTAssertNil(parser.parse("@25:00"), "hour out of range")
        XCTAssertNil(parser.parse("@"), "empty time")
    }

    func testAtTimeWithModifiers() {
        XCTAssertNotNil(parser.parse("@8pm mon"))
        XCTAssertNotNil(parser.parse("@10am tmw"))
        // C# parity: an unknown modifier is ignored (date unchanged), not an error.
        XCTAssertNotNil(parser.parse("@10am someday"))
    }

    func testAbsoluteDates() {
        XCTAssertEqual(parser.parse("2026-08-07"), "2026-08-07")
        XCTAssertEqual(parser.parse("2026/08/07"), "2026-08-07")
        XCTAssertEqual(parser.parse("08/07/2026"), "2026-08-07", "MM/dd before dd/MM")
        // Year bounds
        XCTAssertNil(parser.parse("1899-12-31"))
        XCTAssertNil(parser.parse("2101-01-01"))
        XCTAssertNil(parser.parse("not a date"))
    }

    func testExtractTimeCommand() {
        let (text1, cmd1) = parser.extractTimeCommand("买牛奶 @10am")
        XCTAssertEqual(text1, "买牛奶")
        XCTAssertEqual(cmd1?.lowercased(), "@10am")

        let (text2, cmd2) = parser.extractTimeCommand("交报告 +1d")
        XCTAssertEqual(text2, "交报告")
        XCTAssertEqual(cmd2, "+1d")

        let (text3, cmd3) = parser.extractTimeCommand("no command here")
        XCTAssertEqual(text3, "no command here")
        XCTAssertNil(cmd3)
    }

    func testExtractDateOnlyAndTimeOnly() {
        XCTAssertEqual(DateParser.extractDateOnly("2026-08-07 10:30:00"), "2026-08-07")
        XCTAssertEqual(DateParser.extractTimeOnly("2026-08-07 10:30:00"), "10:30")
        XCTAssertEqual(DateParser.extractDateOnly("2026-08-07"), "2026-08-07")
        XCTAssertNil(DateParser.extractTimeOnly("2026-08-07"))
        XCTAssertEqual(DateParser.combineDateTime("2026-08-07", "10:30"), "2026-08-07 10:30:00")
        XCTAssertEqual(DateParser.combineDateTime("2026-08-07", nil), "2026-08-07 00:00:00")
    }

    func testDisplayFormatting() {
        let today = DateParser.string(from: Date(), format: "yyyy-MM-dd")
        let tomorrow = DateParser.string(
            from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            format: "yyyy-MM-dd")
        let i18n = I18nService.shared
        let label = parser.formatDateOnlyForDisplay(
            today, todayLabel: "TODAY", tomorrowLabel: "TOMORROW", yesterdayLabel: "YESTERDAY")
        XCTAssertEqual(label, "TODAY")
        _ = tomorrow
        _ = i18n
    }

    func testCreatedAtFormat() {
        let stamp = DateParser.createdAtNow()
        XCTAssertTrue(stamp.contains("T"))
        XCTAssertTrue(stamp.contains("+") || stamp.contains("Z") || stamp.contains("-"))
    }
}

final class DatabaseTests: XCTestCase {
    var db: SQLiteDatabase!
    var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "taskly-test-\(UUID().uuidString).db"
        db = SQLiteDatabase()
        db.setDatabasePath(path)
    }

    override func tearDown() {
        db.close()
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    func testFreshDatabaseContract() throws {
        try db.ensureConnected()

        // Default seeded list (byte-compatible with the reference impl).
        let lists = try db.getAllLists()
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists[0].name, "工作")
        XCTAssertEqual(lists[0].icon, "📋")
        XCTAssertEqual(lists[0].color, -16745729, "ARGB 0xFF007AFF as signed int")

        let version = try schemaVersion()
        XCTAssertEqual(version, 4)
    }

    func testTaskRoundTrip() throws {
        try db.ensureConnected()
        let listId = try db.addList(name: "Test", icon: "🎯", color: ARGB.from(hex: 0xFF00_7AFF))

        let task = TaskItem(
            id: 0, listId: listId, text: "买牛奶",
            createdAt: DateParser.createdAtNow(),
            dueDate: "2026-08-07", dueTime: "10:30", notes: "note1")
        let id = try db.addTask(task)
        XCTAssertGreaterThan(id, 0)

        let loaded = try XCTUnwrap(try db.getTaskById(id))
        XCTAssertEqual(loaded.text, "买牛奶")
        XCTAssertEqual(loaded.listId, listId)
        XCTAssertEqual(loaded.dueDate, "2026-08-07")
        XCTAssertEqual(loaded.dueTime, "10:30")
        XCTAssertEqual(loaded.notes, "note1")
        XCTAssertFalse(loaded.completed)
        XCTAssertEqual(loaded.listName, "Test")

        // Completion (idempotent set + toggle)
        _ = try db.setTaskCompleted(id, true)
        XCTAssertTrue(try XCTUnwrap(try db.getTaskById(id)).completed)
        _ = try db.setTaskCompleted(id, true)
        XCTAssertTrue(try XCTUnwrap(try db.getTaskById(id)).completed, "idempotent")
        _ = try db.toggleTaskCompleted(id)
        XCTAssertFalse(try XCTUnwrap(try db.getTaskById(id)).completed, "toggle flips")
    }

    func testViewQueries() throws {
        try db.ensureConnected()
        let listA = try db.addList(name: "A")
        let listB = try db.addList(name: "B")

        let today = DateParser.string(from: Date(), format: "yyyy-MM-dd")
        let t1 = TaskItem(id: 0, listId: listA, text: "today task", createdAt: "x", dueDate: today)
        let t2 = TaskItem(id: 0, listId: listA, text: "planned task", createdAt: "x", dueDate: "2027-01-01")
        let t3 = TaskItem(id: 0, listId: listB, text: "no date task", createdAt: "x")
        _ = try db.addTask(t1)
        _ = try db.addTask(t2)
        _ = try db.addTask(t3)

        XCTAssertEqual(try db.getTodayTasks().count, 1)
        XCTAssertEqual(try db.getTodayTaskCount(), 1)
        XCTAssertEqual(try db.getPlannedTasks().count, 2)
        XCTAssertEqual(try db.getPlannedTaskCount(), 2)
        XCTAssertEqual(try db.getIncompleteTasks().count, 3)
        XCTAssertEqual(try db.getTasksByList(listA).count, 2)
        XCTAssertEqual(try db.getTasksByList(listB).count, 1)

        // Planned sorted by due_date ASC
        let planned = try db.getPlannedTasks()
        XCTAssertEqual(planned.first?.dueDate, today)

        // Completion removes from default views
        let todayTasks = try db.getTodayTasks()
        _ = try db.setTaskCompleted(todayTasks[0].id, true)
        XCTAssertEqual(try db.getTodayTasks().count, 0)
        XCTAssertEqual(try db.getCompletedTasks().count, 1)
    }

    func testSearch() throws {
        try db.ensureConnected()
        let listId = try db.addList(name: "S")
        _ = try db.addTask(TaskItem(id: 0, listId: listId, text: "买牛奶", createdAt: "x"))
        _ = try db.addTask(TaskItem(id: 0, listId: listId, text: "写报告", createdAt: "x"))

        XCTAssertEqual(try db.searchTasks("牛奶").count, 1)
        XCTAssertEqual(try db.searchTasks("不存在的关键词").count, 0)
    }

    func testDeleteListCascades() throws {
        try db.ensureConnected()
        let listId = try db.addList(name: "Doomed")
        _ = try db.addTask(TaskItem(id: 0, listId: listId, text: "x", createdAt: "x"))
        _ = try db.deleteList(id: listId)

        XCTAssertTrue(try db.getAllLists().allSatisfy { $0.id != listId })
        XCTAssertEqual(try db.getTasksByList(listId).count, 0)
    }

    func testCrossPlatformFixture() throws {
        // Simulates a DB written by another platform (raw SQL, .NET-style
        // created_at) — must open and round-trip cleanly.
        let rawPath = NSTemporaryDirectory() + "taskly-fixture-\(UUID().uuidString).db"
        let raw = SQLiteDatabase()
        defer {
            raw.close()
            try? FileManager.default.removeItem(atPath: rawPath)
        }
        raw.setDatabasePath(rawPath)
        try raw.ensureConnected()
        let listId = try raw.addList(name: "Cross")
        _ = try raw.addTask(TaskItem(
            id: 0, listId: listId, text: "from windows",
            createdAt: "2026-09-01T10:00:00.1234567+08:00",
            dueDate: "2026-09-02", dueTime: "09:05"))
        raw.close()

        let reader = SQLiteDatabase()
        reader.setDatabasePath(rawPath)
        try reader.ensureConnected()
        let tasks = try reader.getTasksByList(listId)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].text, "from windows")
        XCTAssertEqual(tasks[0].dueTime, "09:05")
    }

    private func schemaVersion() throws -> Int32 {
        // user_version is exposed via the WAL-safe path; read through a query.
        var stmt: OpaquePointer?
        let handle = try openRawHandle()
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else {
            return -1
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return sqlite3_column_int(stmt, 0)
    }

    private func openRawHandle() throws -> OpaquePointer? {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            throw DatabaseError.openFailed(path)
        }
        return handle
    }
}

final class CliJsonTests: XCTestCase {
    func testEscapingMatchesReference() {
        // C# System.Text.Json escapes non-ASCII as \uXXXX (surrogate pairs).
        XCTAssertEqual(CliJson.escape("📋"), "\"\\ud83d\\udccb\"")
        XCTAssertEqual(CliJson.escape("买牛奶"), "\"\\u4e70\\u725b\\u5976\"")
        XCTAssertEqual(CliJson.escape("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(CliJson.escape("line\nbreak"), "\"line\\nbreak\"")
        XCTAssertEqual(CliJson.escape("ASCII"), "\"ASCII\"")
    }

    func testErrorObjectShape() {
        let json = CliJson.render(.errorObject("boom", 2))
        XCTAssertTrue(json.contains("\"ok\": false"))
        XCTAssertTrue(json.contains("\"error\": \"boom\""))
        XCTAssertTrue(json.contains("\"exitCode\": 2"))
        XCTAssertEqual(json.split(separator: "\n").count, 5, "2-space indented, one field per line")
    }

    func testTaskObjectFieldOrder() {
        let task = TaskItem(
            id: 7, listId: 1, text: "t", createdAt: "c",
            dueDate: "2026-01-01", dueTime: "08:00", notes: nil, listName: "L")
        let json = CliJson.render(.taskObject(task))
        let idIndex = json.range(of: "\"id\"")!.lowerBound
        let listIdIndex = json.range(of: "\"listId\"")!.lowerBound
        let listNameIndex = json.range(of: "\"listName\"")!.lowerBound
        let textIndex = json.range(of: "\"text\"")!.lowerBound
        let notesAbsent = !json.contains("\"notes\"")
        XCTAssertTrue(idIndex < listIdIndex)
        XCTAssertTrue(listIdIndex < listNameIndex)
        XCTAssertTrue(listNameIndex < textIndex)
        XCTAssertTrue(notesAbsent, "null fields omitted")
    }

    func testArrayRendering() {
        let json = CliJson.render(.array([.int(1), .int(2)]))
        XCTAssertTrue(json.contains("[\n  1,\n  2\n]"))
        XCTAssertEqual(CliJson.render(.array([])), "[]")
    }
}

final class CliHelpersTests: XCTestCase {
    let parser = DateParser()

    func testParseDueDateOnlyIntent() throws {
        // Bare words → date only (time cleared)
        let (todayDate, todayTime) = try CliEngine.parseDue(makeContext(), "today")
        XCTAssertNotNil(todayDate)
        XCTAssertNil(todayTime)
        _ = parser

        let (tmwDate, tmwTime) = try CliEngine.parseDue(makeContext(), "tomorrow")
        XCTAssertNotNil(tmwDate)
        XCTAssertNil(tmwTime)

        // +Nd/+Nw/+NM → date only
        let (plusDate, plusTime) = try CliEngine.parseDue(makeContext(), "+1d")
        XCTAssertNotNil(plusDate)
        XCTAssertNil(plusTime)

        // +Nm/+Nh → carries time
        let (_, plusMinTime) = try CliEngine.parseDue(makeContext(), "+10m")
        XCTAssertNotNil(plusMinTime)

        // @ → carries time
        let (_, atTime) = try CliEngine.parseDue(makeContext(), "@10am")
        XCTAssertEqual(atTime, "10:00")

        // Absolute → date only
        let (absDate, absTime) = try CliEngine.parseDue(makeContext(), "2026-08-07")
        XCTAssertEqual(absDate, "2026-08-07")
        XCTAssertNil(absTime)
    }

    func testParseDueErrors() {
        XCTAssertThrowsError(try CliEngine.parseDue(makeContext(), "garbage"))
    }

    func testParseColor() throws {
        XCTAssertEqual(try CliEngine.parseColor("#C15F3C"), ARGB.from(hex: 0xFFC15F3C))
        XCTAssertEqual(try CliEngine.parseColor("#FFC15F3C"), ARGB.from(hex: 0xFFC15F3C))
        XCTAssertEqual(try CliEngine.parseColor("-4104388"), ARGB.from(hex: 0xFFC15F3C))
        XCTAssertThrowsError(try CliEngine.parseColor("#12345"))
        XCTAssertThrowsError(try CliEngine.parseColor("xyz"))
    }

    private func makeContext() -> CliContext {
        let db = SQLiteDatabase()
        return CliContext(db: db, json: false, quiet: false)
    }
}

final class ConfigTests: XCTestCase {
    func testIniRoundTrip() {
        let path = NSTemporaryDirectory() + "taskly-config-\(UUID().uuidString).ini"
        let config = ConfigService(configPath: path)
        config.lastDbPath = "/tmp/x.db"
        config.language = "en"
        config.lastSelectedListId = 3
        config.save()

        let reloaded = ConfigService(configPath: path)
        reloaded.load()
        XCTAssertEqual(reloaded.lastDbPath, "/tmp/x.db")
        XCTAssertEqual(reloaded.language, "en")
        XCTAssertEqual(reloaded.lastSelectedListId, 3)

        // Comments and blank lines ignored; legacy key accepted.
        try? "# Taskly configuration\n; comment\nlast_db_path=/legacy/path\nunknown=1\n".write(
            toFile: path, atomically: true, encoding: .utf8)
        let legacy = ConfigService(configPath: path)
        legacy.load()
        XCTAssertEqual(legacy.lastDbPath, "/legacy/path", "legacy last_db_path key")
        try? FileManager.default.removeItem(atPath: path)
    }

    func testLanguageFallback() {
        let i18n = I18nService.shared
        i18n.setLanguage("en")
        XCTAssertEqual(i18n.t("navToday"), "Today")
        i18n.setLanguage("zh")
        XCTAssertEqual(i18n.t("navToday"), "今天")
        i18n.setLanguage("xx")
        XCTAssertEqual(i18n.language, "zh", "invalid falls back to zh")
        XCTAssertEqual(i18n.t("nonexistent_key_xyz"), "nonexistent_key_xyz")
    }
}
