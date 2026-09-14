import Foundation

/// A single task. Mirrors the `tasks` table in DATA-FORMAT.md (schema v4).
/// `dueDate` is "yyyy-MM-dd", `dueTime` is "HH:mm", `createdAt` is ISO-8601.
/// `listName` is a join artifact (never persisted).
public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public var id: Int
    public var listId: Int
    public var text: String
    public var createdAt: String
    public var dueDate: String?
    public var dueTime: String?
    public var completed: Bool
    public var notes: String?
    public var listName: String?

    public init(
        id: Int,
        listId: Int,
        text: String,
        createdAt: String,
        dueDate: String? = nil,
        dueTime: String? = nil,
        completed: Bool = false,
        notes: String? = nil,
        listName: String? = nil
    ) {
        self.id = id
        self.listId = listId
        self.text = text
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.completed = completed
        self.notes = notes
        self.listName = listName
    }

    /// JSON representation used by the CLI (--json). Field names are a stable
    /// agent-facing contract (CLI-SPEC.md): id, listId, text, completed,
    /// dueDate, dueTime, notes, createdAt.
    public struct CLIJSON: Codable, Sendable {
        public let id: Int
        public let listId: Int
        public let text: String
        public let completed: Bool
        public let dueDate: String?
        public let dueTime: String?
        public let notes: String?
        public let createdAt: String
    }

    public var cliJSON: CLIJSON {
        CLIJSON(
            id: id, listId: listId, text: text, completed: completed,
            dueDate: dueDate, dueTime: dueTime, notes: notes, createdAt: createdAt)
    }
}

/// A task list. `color` is an ARGB int exactly as stored in the DB `color`
/// column (nullable). `icon` is an emoji string.
public struct TodoList: Identifiable, Hashable, Codable, Sendable {
    public static let defaultIcon = "📋"
    /// Crail terracotta, ARGB 0xFFC15F3C, stored as a signed 32-bit int.
    public static let defaultColor = ARGB.from(hex: 0xFFC1_5F3C)

    public var id: Int
    public var name: String
    public var icon: String?
    public var color: Int?
    /// Unfinished-task count, UI-only (never persisted).
    public var pendingCount: Int

    public init(id: Int, name: String, icon: String? = nil, color: Int? = nil, pendingCount: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.pendingCount = pendingCount
    }
}

/// ARGB ↔ Color helpers. The DB stores list colors as signed 32-bit ARGB ints.
public enum ARGB {
    public static func from(hex: UInt32) -> Int {
        Int(Int32(bitPattern: hex))
    }

    public static func hexValue(_ value: Int) -> UInt32 {
        UInt32(bitPattern: Int32(truncatingIfNeeded: value))
    }

    /// Non-optional view for rendering (transparent black when nil).
    public static func components(_ value: Int?) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let value else { return (0, 0, 0, 0) }
        let hex = hexValue(value)
        return (
            r: Double((hex >> 16) & 0xFF) / 255.0,
            g: Double((hex >> 8) & 0xFF) / 255.0,
            b: Double(hex & 0xFF) / 255.0,
            a: Double((hex >> 24) & 0xFF) / 255.0
        )
    }
}
