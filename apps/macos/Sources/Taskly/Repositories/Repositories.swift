import Foundation

/// Smart-view types. `List` renders one user list (`listId`).
public enum TaskViewType: Sendable, Hashable {
    case all
    case today
    case planned
    case completed
    case list(Int)
}

/// Repository above SQLiteDatabase: validation + view dispatch + grouping.
public struct TaskRepository: Sendable {
    let db: SQLiteDatabase
    let i18n: I18nService

    public init(db: SQLiteDatabase, i18n: I18nService) {
        self.db = db
        self.i18n = i18n
    }

    /// View dispatch. Note: `all` with showCompleted=false returns only
    /// incomplete tasks (reference behavior).
    public func getTasksByView(
        _ viewType: TaskViewType, listId: Int? = nil, limit: Int = 1000, offset: Int = 0,
        showCompleted: Bool = false
    ) throws -> [TaskItem] {
        switch viewType {
        case .today:
            return showCompleted ? try db.getTodayTasksIncludingCompleted(limit: limit, offset: offset)
                : try db.getTodayTasks(limit: limit, offset: offset)
        case .planned:
            return showCompleted ? try db.getPlannedTasksIncludingCompleted(limit: limit, offset: offset)
                : try db.getPlannedTasks(limit: limit, offset: offset)
        case .all:
            return showCompleted ? try db.getAllTasksIncludingCompleted(limit: limit, offset: offset)
                : try db.getIncompleteTasks(limit: limit, offset: offset)
        case .completed:
            return try db.getCompletedTasks(limit: limit, offset: offset)
        case .list(let id):
            return showCompleted
                ? try db.getTasksByListIncludingCompleted(id, limit: limit, offset: offset)
                : try db.getTasksByList(id, limit: limit, offset: offset)
        }
    }

    @discardableResult
    public func addTask(_ task: TaskItem) throws -> Int {
        if let error = ValidationHelper.validateTaskText(task.text, i18n) {
            throw error
        }
        return try db.addTask(task)
    }

    @discardableResult
    public func updateTask(_ task: TaskItem) throws -> Int {
        if let error = ValidationHelper.validateTaskText(task.text, i18n) {
            throw error
        }
        return try db.updateTask(task)
    }

    @discardableResult
    public func toggleTaskCompleted(_ id: Int) throws -> Int {
        try db.toggleTaskCompleted(id)
    }

    @discardableResult
    public func setTaskCompleted(_ id: Int, _ completed: Bool) throws -> Int {
        try db.setTaskCompleted(id, completed)
    }

    @discardableResult
    public func deleteTask(_ id: Int) throws -> Int {
        try db.deleteTask(id)
    }

    public func searchTasks(_ keyword: String) throws -> [TaskItem] {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return try db.searchTasks(keyword.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func getTaskById(_ id: Int) throws -> TaskItem? {
        try db.getTaskById(id)
    }

    /// Group tasks by listId preserving encounter order.
    public func groupTasksByList(_ tasks: [TaskItem]) -> [(listId: Int, tasks: [TaskItem])] {
        var order: [Int] = []
        var groups: [Int: [TaskItem]] = [:]
        for task in tasks {
            if groups[task.listId] == nil {
                order.append(task.listId)
            }
            groups[task.listId, default: []].append(task)
        }
        return order.map { ($0, groups[$0]!) }
    }

    public func getTaskCountByList(_ listId: Int) throws -> Int { try db.getTaskCountByList(listId) }
    public func getIncompleteTaskCount() throws -> Int { try db.getIncompleteTaskCount() }
    public func getCompletedTaskCount() throws -> Int { try db.getCompletedTaskCount() }
    public func getTodayTaskCount() throws -> Int { try db.getTodayTaskCount() }
    public func getPlannedTaskCount() throws -> Int { try db.getPlannedTaskCount() }
}

/// List repository: validation + business helpers above SQLiteDatabase.
public struct ListRepository: Sendable {
    let db: SQLiteDatabase
    let i18n: I18nService

    public init(db: SQLiteDatabase, i18n: I18nService) {
        self.db = db
        self.i18n = i18n
    }

    public func getAllLists() throws -> [TodoList] { try db.getAllLists() }
    public func getListById(_ id: Int) throws -> TodoList? { try db.getListById(id) }
    public func getListByName(_ name: String) throws -> TodoList? { try db.getListByName(name) }

    @discardableResult
    public func addList(_ name: String, icon: String? = nil, color: Int? = nil) throws -> Int {
        if let error = ValidationHelper.validateListName(name, i18n) {
            throw error
        }
        return try db.addList(name: name.trimmingCharacters(in: .whitespaces), icon: icon, color: color)
    }

    @discardableResult
    public func updateList(_ id: Int, _ name: String, icon: String? = nil, color: Int? = nil,
                           clearIcon: Bool = false, clearColor: Bool = false) throws -> Int {
        if let error = ValidationHelper.validateListName(name, i18n) {
            throw error
        }
        return try db.updateList(
            id: id, name: name.trimmingCharacters(in: .whitespaces),
            icon: icon, color: color, clearIcon: clearIcon, clearColor: clearColor)
    }

    @discardableResult
    public func updateListIcon(_ id: Int, _ icon: String) throws -> Int {
        guard let list = try getListById(id) else {
            throw AppError("List not found", .validation)
        }
        return try db.updateList(id: id, name: list.name, icon: icon, color: list.color)
    }

    @discardableResult
    public func updateListColor(_ id: Int, _ color: Int) throws -> Int {
        guard let list = try getListById(id) else {
            throw AppError("List not found", .validation)
        }
        return try db.updateList(id: id, name: list.name, icon: list.icon, color: color)
    }

    @discardableResult
    public func deleteList(_ id: Int) throws -> Int { try db.deleteList(id: id) }

    /// Default list = the first one.
    public func getDefaultList() throws -> TodoList? {
        try getAllLists().first
    }
}
