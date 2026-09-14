import SwiftUI

enum SmartView: Hashable {
    case today
    case planned
    case all
    case completed
    case list(Int)

    var titleKey: String {
        switch self {
        case .today: return "navToday"
        case .planned: return "navPlanned"
        case .all: return "navAll"
        case .completed: return "navCompleted"
        case .list: return ""
        }
    }

    /// Repository-layer view type (same cases, different type).
    var taskView: TaskViewType {
        switch self {
        case .today: return .today
        case .planned: return .planned
        case .all: return .all
        case .completed: return .completed
        case .list(let id): return .list(id)
        }
    }
}

/// Application state: database lifecycle, lists, current view, tasks,
/// status line. The GUI talks only to repositories (never raw SQL).
@Observable
@MainActor
public final class AppState {
    // Services
    let config = ConfigService()
    let i18n: I18nService
    let theme = ThemeState()

    var db = SQLiteDatabase()
    /// Repositories are cheap structs rebuilt on access (they wrap the
    /// current db reference).
    var tasksRepository: TaskRepository { TaskRepository(db: db, i18n: i18n) }
    var listsRepository: ListRepository { ListRepository(db: db, i18n: i18n) }

    // Data
    var lists: [TodoList] = []
    var tasks: [TaskItem] = []
    var currentView: SmartView = .all
    var showCompleted = false
    var isConnected = false
    var currentDbPath: String = ""

    // UI state
    var searchText = ""
    var quickAddText = ""
    var isSidebarVisible = true
    var statusMessage: String = ""
    @ObservationIgnored private var transientDeadline: Task<Void, Never>?
    var languageChangedToken = 0

    // Sheets / dialogs
    var listEditSheet: ListEditContext?
    var taskDetailContext: TaskItem?
    var confirmContext: ConfirmContext?
    var aboutVisible = false

    let reminder: ReminderService

    // Counts
    var todayCount = 0
    var plannedCount = 0
    var allCount = 0
    var completedCount = 0

    init() {
        config.load()
        i18n = I18nService.shared
        i18n.setLanguage(config.language)
        theme.isDark = false
        statusMessage = i18n.t("statusDatabaseNotConnected")

        reminder = ReminderService()
        reminder.attach(self)

        // Safe: self is fully initialized here.
        i18n.onLanguageChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.languageChangedToken += 1
                self?.refreshStatusPersistent()
            }
        }
    }

    // MARK: - Status line

    /// Locale-aware lookup that also registers the language-change token as
    /// an observation dependency, so switching languages re-renders views.
    public func t(_ key: String) -> String {
        _ = languageChangedToken
        return i18n.t(key)
    }

    public func t(_ key: String, _ args: Any...) -> String {
        _ = languageChangedToken
        return i18n.format(key, args)
    }

    var persistentStatus: String {
        if !isConnected {
            return i18n.t("statusDatabaseNotConnected")
        }
        if !searchText.isEmpty {
            return "\(i18n.t("searchHint")): \(searchText)"
        }
        switch currentView {
        case .today: return i18n.t("statusShowToday")
        case .planned: return i18n.t("statusShowPlanned")
        case .all: return i18n.t("statusShowAll")
        case .completed: return i18n.t("statusShowCompleted")
        case .list(let id):
            let name = lists.first { $0.id == id }?.name ?? "List \(id)"
            return "\(i18n.t("statusSwitchList"))".replacingOccurrences(of: "{0}", with: name)
        }
    }

    func refreshStatusPersistent() {
        statusMessage = persistentStatus
    }

    /// Transient status message; reverts to persistent after 3 s.
    func flashStatus(_ text: String) {
        transientDeadline?.cancel()
        statusMessage = text
        transientDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.transientDeadline = nil
            self?.refreshStatusPersistent()
        }
    }

    // MARK: - Database lifecycle

    var currentTitle: String {
        if !searchText.isEmpty {
            return "\(i18n.t("searchHint")): \(searchText)"
        }
        switch currentView {
        case .today: return i18n.t("navToday")
        case .planned: return i18n.t("navPlanned")
        case .all: return i18n.t("navAll")
        case .completed: return i18n.t("navCompleted")
        case .list(let id): return lists.first { $0.id == id }?.name ?? "List \(id)"
        }
    }

    func newDatabase(at url: URL) {
        let path = url.path
        do {
            db.close()
            db.setDatabasePath(path)
            try db.ensureConnected()
            config.lastDbPath = path
            config.save()
            onConnected()
        } catch {
            db.close()
            db = SQLiteDatabase()
            flashStatus("\(error.localizedDescription)")
        }
    }

    func openDatabase(at url: URL) {
        newDatabase(at: url)
    }

    func openDefaultDatabaseIfNeeded() {
        let resolved: String
        if !config.lastDbPath.isEmpty {
            resolved = config.lastDbPath
        } else {
            resolved = PathUtils.defaultDatabasePath
        }
        newDatabase(at: URL(fileURLWithPath: resolved))
        reminder.start()
    }

    func closeDatabase() {
        db.close()
        isConnected = false
        lists = []
        tasks = []
        currentView = .all
        refreshCounts()
        refreshStatusPersistent()
        flashStatus(i18n.t("statusDatabaseClosed"))
    }

    private func reconnectRepositories() {
        // Repositories are computed properties over `db`; nothing to do.
    }

    private func onConnected() {
        isConnected = true
        reminder.resetNotified()
        reloadLists()
        restoreSelection()
        refreshCounts()
        refresh()
        refreshStatusPersistent()
        flashStatus(i18n.t("statusDatabaseConnected"))
    }

    /// Restore last-selected list, falling back to the All view.
    private func restoreSelection() {
        let lastId = config.lastSelectedListId
        if lastId != 0, lists.contains(where: { $0.id == lastId }) {
            currentView = .list(lastId)
        } else {
            currentView = .all
        }
    }

    // MARK: - Refresh

    func reloadLists() {
        lists = (try? listsRepository.getAllLists()) ?? []
    }

    func refreshCounts() {
        todayCount = (try? tasksRepository.getTodayTaskCount()) ?? 0
        plannedCount = (try? tasksRepository.getPlannedTaskCount()) ?? 0
        allCount = (try? tasksRepository.getIncompleteTaskCount()) ?? 0
        completedCount = (try? tasksRepository.getCompletedTaskCount()) ?? 0
        for index in lists.indices {
            lists[index].pendingCount = (try? tasksRepository.getTaskCountByList(lists[index].id)) ?? 0
        }
    }

    /// Full task-pane refresh (re-filters the current view).
    func refresh() {
        guard isConnected else {
            tasks = []
            return
        }
        do {
            if !searchText.isEmpty {
                tasks = try tasksRepository.searchTasks(searchText)
            } else {
                tasks = try tasksRepository.getTasksByView(
                    currentView.taskView, showCompleted: showCompleted)
            }
        } catch {
            tasks = []
        }
    }

    // MARK: - Selection

    func select(_ view: SmartView) {
        guard isConnected else { return }
        currentView = view
        if case .list(let id) = view {
            config.lastSelectedListId = id
            config.save()
        }
        refresh()
        refreshStatusPersistent()
    }

    // MARK: - Task operations

    /// Quick add: extracts a trailing date/time command from the text
    /// (CLI semantics: pure-date intent clears the time).
    func quickAdd(_ rawText: String) {
        guard isConnected else { return }
        let trimmed = rawText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let parser = DateParser()
        let (text, timeCommand) = parser.extractTimeCommand(trimmed)
        var dueDate: String?
        var dueTime: String?
        if let command = timeCommand {
            if command.hasPrefix("+") || command.hasPrefix("@") {
                if let parsed = parser.parse(command) {
                    // Date-only intent for +N d/w/M (GUI adopts CLI semantics).
                    let isDateOnly = command.hasPrefix("@") == false
                        && ["d", "w", "M"].contains(String(command.suffix(1)))
                    dueDate = DateParser.extractDateOnly(parsed)
                    if !isDateOnly {
                        dueTime = DateParser.extractTimeOnly(parsed)
                    }
                }
            }
        }

        let listId: Int
        switch currentView {
        case .list(let id): listId = id
        default:
            guard let first = lists.first else {
                flashStatus(i18n.t("taskCreateListFirst"))
                return
            }
            listId = first.id
        }

        let task = TaskItem(
            id: 0, listId: listId, text: text.isEmpty ? trimmed : text,
            createdAt: DateParser.createdAtNow(), dueDate: dueDate, dueTime: dueTime)
        do {
            _ = try tasksRepository.addTask(task)
            quickAddText = ""
            refreshCounts()
            refresh()
            flashStatus(i18n.t("statusTaskAdded"))
        } catch let appError as AppError {
            flashStatus(appError.message)
        } catch {
            flashStatus(error.localizedDescription)
        }
    }

    func toggleCompleted(_ task: TaskItem) {
        _ = try? tasksRepository.toggleTaskCompleted(task.id)
        refreshCounts()
        refresh()
        flashStatus(i18n.t("statusUpdateTaskState"))
    }

    func saveTask(_ task: TaskItem) {
        do {
            _ = try tasksRepository.updateTask(task)
            refreshCounts()
            refresh()
            flashStatus(i18n.t("statusTaskUpdated"))
        } catch let appError as AppError {
            flashStatus(appError.message)
        } catch {
            flashStatus(error.localizedDescription)
        }
    }

    func deleteTask(_ task: TaskItem) {
        _ = try? tasksRepository.deleteTask(task.id)
        refreshCounts()
        refresh()
        flashStatus(i18n.t("statusTaskDeleted"))
    }

    func moveTask(_ task: TaskItem, to list: TodoList) {
        var updated = task
        updated.listId = list.id
        do {
            _ = try tasksRepository.updateTask(updated)
            refreshCounts()
            refresh()
            flashStatus(i18n.format("statusTaskMoved", list.name))
        } catch {
            flashStatus(error.localizedDescription)
        }
    }

    // MARK: - List operations

    func createList(name: String, icon: String?, color: Int?) {
        do {
            let id = try listsRepository.addList(name, icon: icon, color: color)
            reloadLists()
            refreshCounts()
            select(.list(id))
            flashStatus(i18n.format("statusCreateList", name.trimmingCharacters(in: .whitespaces)))
        } catch let appError as AppError {
            flashStatus(appError.message)
        } catch {
            flashStatus(error.localizedDescription)
        }
    }

    func updateList(_ list: TodoList, name: String, icon: String?, color: Int?,
                    clearIcon: Bool, clearColor: Bool) {
        do {
            _ = try listsRepository.updateList(
                list.id, name, icon: icon, color: color,
                clearIcon: clearIcon, clearColor: clearColor)
            reloadLists()
            refreshCounts()
            refresh()
        } catch let appError as AppError {
            flashStatus(appError.message)
        } catch {
            flashStatus(error.localizedDescription)
        }
    }

    func deleteList(_ list: TodoList) {
        _ = try? listsRepository.deleteList(list.id)
        reloadLists()
        refreshCounts()
        if case .list(let id) = currentView, id == list.id {
            select(.all)
        } else {
            refresh()
        }
        flashStatus(i18n.t("statusDeleteList"))
    }

    // MARK: - CLI installer (menu actions)

    func installCli() {
        do {
            _ = try CliInstaller.install()
        } catch {
            flashStatus("\(error)")
        }
    }

    func uninstallCli() {
        do {
            _ = try CliInstaller.uninstall()
        } catch {
            flashStatus("\(error)")
        }
    }
}

/// Sheet payload for create/edit list.
struct ListEditContext: Identifiable {
    enum Mode {
        case create
        case edit(TodoList)
    }

    let id = UUID()
    let mode: Mode
}

/// Confirmation dialog payload.
struct ConfirmContext: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var onConfirm: () -> Void
}
