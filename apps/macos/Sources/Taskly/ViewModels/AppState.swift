import SwiftUI

enum SmartView: Hashable {
    case today
    case planned
    case all
    case completed
    case list(Int)
    case calendar

    var titleKey: String {
        switch self {
        case .today: return "navToday"
        case .planned: return "navPlanned"
        case .all: return "navAll"
        case .completed: return "navCompleted"
        case .list: return ""
        case .calendar: return "navCalendar"
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
        case .calendar: return .calendar
        }
    }
}

/// Group header inside the calendar time line (PRODUCT-SPEC §4b).
struct CalendarSectionHeader: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let count: Int
    let isToday: Bool
    let isOverdue: Bool
    /// "yyyy-MM-dd" of the group's day; nil for the overdue group.
    let dateKey: String?
}

/// One rendered row of the calendar time line: a day header or a task.
enum CalendarRow: Identifiable {
    case header(CalendarSectionHeader)
    case task(TaskItem)

    var id: String {
        switch self {
        case .header(let h): return "header-\(h.id.uuidString)"
        case .task(let t): return "task-\(t.id)"
        }
    }

    var header: CalendarSectionHeader? {
        if case .header(let h) = self { return h }
        return nil
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

    // Calendar view state (PRODUCT-SPEC §4b)
    var calendarYear = 0
    /// 1–12; month the calendar grid shows.
    var calendarMonth = 0
    /// "yyyy-MM-dd" of the highlighted day cell.
    var calendarSelectedDate: String?
    /// due date → incomplete count, for the month grid day dots.
    var calendarDayCounts: [String: Int] = [:]
    /// Overdue tail + displayed-month day groups, rendered in order.
    var calendarRows: [CalendarRow] = []

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

    /// Calendar pane visible only in the calendar view without a search
    /// (search shows flat results, as in every view).
    var isCalendarView: Bool {
        currentView == .calendar && searchText.isEmpty
    }

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
        case .calendar: return i18n.t("statusShowCalendar")
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
        case .calendar: return i18n.t("navCalendar")
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
        calendarRows = []
        calendarDayCounts = [:]
        calendarYear = 0
        calendarSelectedDate = nil
        currentView = .all
        refreshCounts()
        refreshStatusPersistent()
        flashStatus(i18n.t("statusDatabaseClosed"))
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
            calendarRows = []
            return
        }
        do {
            if isCalendarView {
                try refreshCalendar()
                return
            }

            calendarRows = []
            if !searchText.isEmpty {
                tasks = try tasksRepository.searchTasks(searchText)
            } else {
                tasks = try tasksRepository.getTasksByView(
                    currentView.taskView, showCompleted: showCompleted)
            }
        } catch {
            tasks = []
            calendarRows = []
        }
    }

    /// Calendar view data: overdue tail + displayed-month day groups, plus
    /// the day-dot counts (PRODUCT-SPEC §4b).
    private func refreshCalendar() throws {
        let cal = Calendar.current
        let now = Date()
        let todayKey = DateParser.string(from: now, format: "yyyy-MM-dd")
        let beforeTodayKey = DateParser.string(
            from: cal.date(byAdding: .day, value: -1, to: now) ?? now, format: "yyyy-MM-dd")
        let monthStartDate = makeCalendarDate(year: calendarYear, month: calendarMonth, day: 1)
        let monthStartKey = DateParser.string(from: monthStartDate, format: "yyyy-MM-dd")
        let monthEndDate = cal.date(byAdding: .day, value: -1,
            to: cal.date(byAdding: .month, value: 1, to: monthStartDate) ?? monthStartDate) ?? monthStartDate
        let monthEndKey = DateParser.string(from: monthEndDate, format: "yyyy-MM-dd")

        let overdue = try tasksRepository.getTasksInRange(
            startDate: "1900-01-01", endDate: beforeTodayKey, includeCompleted: showCompleted)
        let monthTasks = try tasksRepository.getTasksInRange(
            startDate: monthStartKey, endDate: monthEndKey, includeCompleted: showCompleted)
        let counts = try tasksRepository.getDueDayCounts(startDate: monthStartKey, endDate: monthEndKey)

        calendarDayCounts = Dictionary(uniqueKeysWithValues: counts.map { ($0.date, $0.count) })

        var rows: [CalendarRow] = []
        if !overdue.isEmpty {
            rows.append(.header(CalendarSectionHeader(
                text: i18n.t("calOverdue"), count: overdue.count,
                isToday: false, isOverdue: true, dateKey: nil)))
            overdue.forEach { rows.append(.task($0)) }
        }
        let groups = Dictionary(grouping: monthTasks, by: { $0.dueDate ?? "" })
        for dateKey in groups.keys.sorted() where !dateKey.isEmpty {
            let group = groups[dateKey] ?? []
            rows.append(.header(CalendarSectionHeader(
                text: formatDayHeader(dateKey), count: group.count,
                isToday: dateKey == todayKey, isOverdue: false, dateKey: dateKey)))
            group.forEach { rows.append(.task($0)) }
        }
        calendarRows = rows
    }

    private func makeCalendarDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Calendar interactions (PRODUCT-SPEC §4b)

    func navigateCalendarMonth(_ delta: Int) {
        guard calendarYear != 0 else { return }
        let first = makeCalendarDate(year: calendarYear, month: calendarMonth, day: 1)
        let target = Calendar.current.date(byAdding: .month, value: delta, to: first) ?? first
        let comps = Calendar.current.dateComponents([.year, .month], from: target)
        calendarYear = comps.year ?? calendarYear
        calendarMonth = comps.month ?? calendarMonth
        calendarSelectedDate = DateParser.string(
            from: makeCalendarDate(year: calendarYear, month: calendarMonth, day: 1), format: "yyyy-MM-dd")
        refresh()
    }

    func goCalendarToday() {
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        calendarYear = comps.year ?? calendarYear
        calendarMonth = comps.month ?? calendarMonth
        calendarSelectedDate = DateParser.string(from: now, format: "yyyy-MM-dd")
        refresh()
    }

    /// Day-cell click from the month grid; adjacent-month cells switch the
    /// displayed month first (§4b).
    func selectCalendarDate(_ dateKey: String) {
        guard let date = parseDateKey(dateKey) else { return }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        if comps.year != calendarYear || comps.month != calendarMonth {
            calendarYear = comps.year ?? calendarYear
            calendarMonth = comps.month ?? calendarMonth
            calendarSelectedDate = dateKey
            refresh()
        } else {
            calendarSelectedDate = dateKey
        }
    }

    /// Month-grid title: `2026年9月` / `September 2026`.
    var calendarMonthTitle: String {
        i18n.format("calMonthTitle", String(calendarYear), i18n.t("calMonth\(calendarMonth)"))
    }

    /// Weekday short-name row ordered by the language's week start
    /// (zh Monday-first, en Sunday-first); key index 1 = Monday.
    var calendarWeekdayHeader: [String] {
        let names = (1...7).map { i18n.t("calWeekdayShort\($0)") }
        return config.language == "zh"
            ? names
            : [names[6], names[0], names[1], names[2], names[3], names[4], names[5]]
    }

    /// Group header text: `9月26日 · 周五` / `Friday, September 26`;
    /// today/tomorrow/yesterday replace the weekday slot (§4b).
    func formatDayHeader(_ dateKey: String) -> String {
        guard let date = parseDateKey(dateKey) else { return dateKey }
        let cal = Calendar.current
        let monthName = i18n.t("calMonth\(cal.component(.month, from: date))")
        let weekday = relativeDayLabel(dateKey)
            ?? i18n.t("calWeekday\((cal.component(.weekday, from: date) + 5) % 7 + 1)")
        return i18n.format("calDayHeader", monthName, cal.component(.day, from: date), weekday)
    }

    /// navToday / dateTomorrow / dateYesterday when the key is one of those
    /// three days relative to now; nil otherwise.
    func relativeDayLabel(_ dateKey: String) -> String? {
        guard let date = parseDateKey(dateKey) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        if day == today { return i18n.t("navToday") }
        if day == cal.date(byAdding: .day, value: 1, to: today) { return i18n.t("dateTomorrow") }
        if day == cal.date(byAdding: .day, value: -1, to: today) { return i18n.t("dateYesterday") }
        return nil
    }

    /// Strict "yyyy-MM-dd" parse (asDate falls back to now, which the
    /// calendar must not do for malformed keys).
    @ObservationIgnored private lazy var dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func parseDateKey(_ key: String) -> Date? {
        dayKeyFormatter.date(from: key)
    }

    // MARK: - Selection

    func select(_ view: SmartView) {
        guard isConnected else { return }
        currentView = view
        if case .list(let id) = view {
            config.lastSelectedListId = id
            config.save()
        }
        if view == .calendar {
            let now = Date()
            let comps = Calendar.current.dateComponents([.year, .month], from: now)
            let entering = calendarYear == 0
            if entering || calendarYear != comps.year || calendarMonth != comps.month {
                calendarYear = comps.year ?? 0
                calendarMonth = comps.month ?? 0
            }
            if entering || calendarSelectedDate == nil {
                calendarSelectedDate = DateParser.string(from: now, format: "yyyy-MM-dd")
            }
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
