import AppKit
import SwiftUI
import RivetEmbedding
import RivetRuntime

enum SmartView: Hashable {
    case today
    case planned
    case all
    case completed
    case list(Int64)

    var titleKey: String {
        switch self {
        case .today: return "navToday"
        case .planned: return "navPlanned"
        case .all: return "navAll"
        case .completed: return "navCompleted"
        case .list: return ""
        }
    }

    /// Backend view string (racket/taskly/service.rkt normalize-view);
    /// list views filter through the separate list_id argument.
    var backendView: String {
        switch self {
        case .today: return "today"
        case .planned: return "planned"
        case .all, .list: return "all"
        case .completed: return "completed"
        }
    }

    var listId: Int64? {
        if case .list(let id) = self { return id }
        return nil
    }
}

/// Application state: embedded-backend lifecycle, settings, lists, current
/// view, tasks, status line. All data flows through the typed RivetAPI;
/// every backend mutation publishes `changed`, which re-reads the snapshot.
@Observable
@MainActor
final class AppModel {
    let i18n = I18nService.shared
    let theme = ThemeState()
    /// Active theme setting ("system" | "light" | "dark") for the menu check.
    private(set) var themeValue = "system"

    private var backend: EmbeddedRacketBackend?
    private var api: RivetAPI?
    private var started = false
    /// Monotonic token; stale async snapshot responses are dropped.
    private var reloadSequence = 0
    private var previewSequence = 0

    // Data
    var lists: [TodoList] = []
    var tasks: [Task] = []
    var counts = SmartCounts(today: 0, planned: 0, all: 0, completed: 0)
    var currentView: SmartView = .all
    var showCompleted = false
    var isConnected = false

    // UI state
    /// Selected rows (Reminders-style: click selects, ⌘ toggles, ⇧ extends).
    var selectedTaskIDs: Set<Int64> = []
    /// Anchor for ⇧-extend navigation.
    var selectionAnchorIndex: Int?
    /// Row expanded inline for detail editing (Reminders-style ⓘ).
    var expandedTaskID: Int64?
    var searchText = ""
    var quickAddText = ""
    /// Live quick-add schedule preview (canonical parse via parse_due RPC).
    var quickAddPreview: String?
    /// Incremented by View menu → New Task; TaskPaneView focuses the
    /// quick-add field on change.
    var quickAddFocusToken = 0
    /// Incremented by View menu → Find; TaskPaneView focuses the search
    /// field on change.
    var searchFocusToken = 0
    var isSidebarVisible = true
    var statusMessage = ""
    var languageChangedToken = 0
    /// Completed section collapsed (hidden rows are skipped by ↑/↓).
    var completedCollapsed = false
    /// Last keyboard modifiers (flagsChanged) — click gestures read this to
    /// apply ⌘-toggle / ⇧-extend, since SpatialTapGesture carries none.
    var lastModifierFlags: NSEvent.ModifierFlags = []

    // Sheets / dialogs
    var listEditSheet: ListEditContext?
    var confirmContext: ConfirmContext?
    var aboutVisible = false

    /// Transient delete banner with a one-step undo (Reminders-style).
    var undoBannerText: String?
    var undoBannerAction: (() -> Void)?
    @ObservationIgnored private var undoBannerTask: Swift.Task<Void, Never>?
    @ObservationIgnored private var transientDeadline: Swift.Task<Void, Never>?
    @ObservationIgnored private var appearanceObserver: NSKeyValueObservation?

    init() {
        statusMessage = i18n.t("statusDatabaseNotConnected")

        i18n.onLanguageChanged = { [weak self] in
            Swift.Task { @MainActor [weak self] in
                self?.languageChangedToken += 1
                self?.refreshStatusPersistent()
            }
        }

        // Live-follow macOS appearance changes (initial fire sets it too).
        // light/dark config themes override through NSApp.appearance, and the
        // effective appearance reflects that override.
        appearanceObserver = NSApplication.shared.observe(
            \.effectiveAppearance, options: [.initial, .new]
        ) { [weak self] _, _ in
            Swift.Task { @MainActor [weak self] in
                self?.theme.isDark = Self.systemAppearanceIsDark
            }
        }
    }

    // MARK: - Startup

    func start() {
        guard !started else { return }
        started = true

        do {
            let config = try Self.runtimeConfiguration()
            let backend = EmbeddedRacketBackend(configuration: config)
            self.backend = backend
            try backend.start(onEvent: { [weak self] name, value in
                guard let event = try? RivetEvent.decode(name: name, value: value),
                      case .changed = event else { return }
                Swift.Task { @MainActor [weak self] in
                    self?.reload()
                }
            })
            api = RivetAPI(client: backend.client)
            Swift.Task { await bootstrap() }
        } catch {
            statusMessage = "Backend error: \(error)"
        }
    }

    /// Settings → open default database → restore selection.
    private func bootstrap() async {
        guard let api else { return }
        do {
            let settings = try await api.get_settings()
            i18n.setLanguage(settings.language)
            applyTheme(settings.theme)
            refreshStatusPersistent()

            let path = try await api.default_database()
            let snapshot = try await api.open_database(path: path)
            isConnected = true
            absorb(snapshot)
            restoreSelection(settings.last_selected_list_id)
            refreshStatusPersistent()
            flashStatus(i18n.t("statusDatabaseConnected"))
        } catch {
            statusMessage = "\(error)"
        }
    }

    /// Restore last-selected list, falling back to the All view.
    private func restoreSelection(_ lastId: Int64) {
        if lastId != 0, lists.contains(where: { $0.id == lastId }) {
            currentView = .list(lastId)
        } else {
            currentView = .all
        }
        reload()
    }

    // MARK: - Settings

    /// "system" follows macOS live; "light"/"dark" pin the appearance.
    func applyTheme(_ value: String) {
        themeValue = ["light", "dark"].contains(value) ? value : "system"
        switch themeValue {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func setTheme(_ value: String) {
        applyTheme(value)
        guard let api else { return }
        Swift.Task {
            _ = try? await api.set_setting(key: "theme", value: value)
        }
    }

    func setLanguage(_ language: String) {
        i18n.setLanguage(language)
        guard let api else { return }
        Swift.Task {
            _ = try? await api.set_setting(key: "language", value: language)
        }
    }

    // MARK: - Database lifecycle (File menu)

    /// Open (creating when absent) a database file in place.
    func openDatabase(path: String) {
        guard let api else { return }
        Swift.Task {
            do {
                let snapshot = try await api.open_database(path: path)
                isConnected = true
                absorb(snapshot)
                let settings = try? await api.get_settings()
                restoreSelection(settings?.last_selected_list_id ?? 0)
                refreshStatusPersistent()
                flashStatus(i18n.t("statusDatabaseConnected"))
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    func closeDatabase() {
        guard let api else { return }
        Swift.Task {
            _ = try? await api.close_database()
            isConnected = false
            lists = []
            tasks = []
            counts = SmartCounts(today: 0, planned: 0, all: 0, completed: 0)
            currentView = .all
            clearTaskSelection()
            expandedTaskID = nil
            refreshStatusPersistent()
            flashStatus(i18n.t("statusDatabaseClosed"))
        }
    }

    // MARK: - Runtime layout

    private static func runtimeConfiguration() throws -> EmbeddedRacketConfiguration {
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL

        // Packaged apps keep Racket data in Contents/Resources. `raco rivet
        // dev` runs the staged executable directly, where runtime/res live next
        // to the executable. Pick the first complete layout so both paths use
        // exactly the same host binary.
        let roots = [
            Bundle.main.resourceURL,
            executable.deletingLastPathComponent()
        ].compactMap { $0 }

        for root in roots {
            let runtime = root.appendingPathComponent("runtime", isDirectory: true)
            let core = root.appendingPathComponent("res/core.zo")
            let required = [
                runtime.appendingPathComponent("petite.boot"),
                runtime.appendingPathComponent("scheme.boot"),
                runtime.appendingPathComponent("racket.boot"),
                core
            ]
            if required.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                return EmbeddedRacketConfiguration(
                    executable: executable,
                    petiteBoot: required[0],
                    schemeBoot: required[1],
                    racketBoot: required[2],
                    core: core,
                    moduleName: RivetGeneratedConfig.moduleName,
                    entryName: RivetGeneratedConfig.entryName
                )
            }
        }

        throw HostError.missingRuntimeLayout(
            roots.map(\.path).joined(separator: ", "))
    }

    // MARK: - Localization / status

    /// Locale-aware lookup that also registers the language-change token as
    /// an observation dependency, so switching languages re-renders views.
    func t(_ key: String) -> String {
        _ = languageChangedToken
        return i18n.t(key)
    }

    func t(_ key: String, _ args: Any...) -> String {
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
            return i18n.format("statusSwitchList", name)
        }
    }

    func refreshStatusPersistent() {
        statusMessage = persistentStatus
    }

    /// True when macOS is currently in Dark Mode (main-thread read).
    static var systemAppearanceIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Transient status message; reverts to persistent after 3 s.
    func flashStatus(_ text: String) {
        transientDeadline?.cancel()
        statusMessage = text
        transientDeadline = Swift.Task { [weak self] in
            try? await Swift.Task.sleep(nanoseconds: 3_000_000_000)
            guard !Swift.Task.isCancelled else { return }
            self?.transientDeadline = nil
            self?.refreshStatusPersistent()
        }
    }

    // MARK: - Header model

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

    /// Secondary header line (DESIGN-TOKENS view header): full date under
    /// Today shows the full date via locale; other views show open or
    /// completed counts. Empty while disconnected or searching.
    var currentSubtitle: String {
        _ = languageChangedToken
        if !isConnected || !searchText.isEmpty {
            return ""
        }
        switch currentView {
        case .today:
            // Date shapes come from the platform locale, not copy (§11).
            let locale = Locale(identifier: i18n.language == "zh" ? "zh_CN" : "en_US")
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            return formatter.string(from: Date())
        case .planned:
            return i18n.format("subtitleOpenTasks", counts.planned)
        case .completed:
            return i18n.format("subtitleCompleted", counts.completed)
        case .list(let id):
            let pending = lists.first { $0.id == id }?.pending_count ?? 0
            return i18n.format("subtitleOpenTasks", pending)
        case .all:
            return i18n.format("subtitleOpenTasks", counts.all)
        }
    }

    // MARK: - Refresh

    /// Absorb a backend snapshot into the observable state.
    private func absorb(_ snapshot: Snapshot) {
        counts = snapshot.counts
        lists = snapshot.lists
        withAnimation(.easeOut(duration: 0.15)) {
            tasks = snapshot.tasks
        }
    }

    /// Full task-pane refresh for the current view. Multiple overlapping
    /// calls are fine: only the latest issued response is applied.
    func reload() {
        guard let api, isConnected else {
            tasks = []
            return
        }
        reloadSequence += 1
        let seq = reloadSequence
        let view = currentView.backendView
        let listId = currentView.listId
        let show = showCompleted
        Swift.Task { [weak self] in
            guard let snapshot = try? await api.load_snapshot(
                view: view, list_id: listId, show_completed: show) else { return }
            guard let self, seq == self.reloadSequence else { return }
            self.absorb(snapshot)
        }
    }

    /// Search results replace the pane (spec §4: search term drives the view).
    private func reloadSearch() {
        guard let api, isConnected else { return }
        let keyword = searchText
        reloadSequence += 1
        let seq = reloadSequence
        Swift.Task { [weak self] in
            guard let results = try? await api.search_tasks(keyword: keyword) else { return }
            guard let self, seq == self.reloadSequence else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                self.tasks = results
            }
        }
    }

    func searchChanged() {
        clearTaskSelection()
        expandedTaskID = nil
        refreshStatusPersistent()
        if searchText.isEmpty {
            reload()
        } else {
            reloadSearch()
        }
    }

    // MARK: - View selection

    func select(_ view: SmartView) {
        guard isConnected else { return }
        currentView = view
        clearTaskSelection()
        expandedTaskID = nil
        if case .list(let id) = view {
            persistLastSelectedList(id)
        }
        refreshStatusPersistent()
        reload()
    }

    private func persistLastSelectedList(_ id: Int64) {
        guard let api else { return }
        Swift.Task {
            // The backend clamps unknown ids on read, so a stale id is
            // harmless: the next launch falls back to All.
            _ = try? await api.set_setting(
                key: "last-selected-list-id", value: String(id))
        }
    }

    // MARK: - Task operations

    /// Quick add: the trailing date/time command is parsed canonically by
    /// the backend `parse_due` RPC — one grammar on every platform
    /// (pure-date intent clears the time).
    func quickAdd(_ rawText: String) {
        guard isConnected, let api else { return }
        let trimmed = rawText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let listId: Int64
        if let id = currentView.listId {
            listId = id
        } else if let first = lists.first {
            listId = first.id
        } else {
            flashStatus(i18n.t("taskCreateListFirst"))
            return
        }

        Swift.Task {
            do {
                // One quick-add grammar on every platform: the backend
                // splits text + due (parse_quick_add), we just store it.
                let parsed = try await api.parse_quick_add(text: trimmed)
                _ = try await api.add_task(
                    text: parsed.text,
                    list_id: listId,
                    due_date: parsed.due_date,
                    due_time: parsed.due_time,
                    notes: nil)
                await MainActor.run {
                    quickAddText = ""
                    quickAddPreview = nil
                    flashStatus(i18n.t("statusTaskAdded"))
                    reload()
                }
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    /// Keystroke-driven preview: the same parse_quick_add RPC the commit
    /// path uses, stale responses dropped by sequence.
    func quickAddTextChanged() {
        previewSequence += 1
        let seq = previewSequence
        let raw = quickAddText
        guard !raw.isEmpty, let api else {
            quickAddPreview = nil
            return
        }
        Swift.Task { [weak self] in
            guard let self, seq == self.previewSequence else { return }
            guard let parsed = try? await api.parse_quick_add(text: raw),
                  let dueDate = parsed.due_date else {
                self.quickAddPreview = nil
                return
            }
            await MainActor.run {
                guard seq == self.previewSequence else { return }
                var label = Self.previewDateText(
                    dueDate,
                    todayLabel: self.t("navToday"),
                    tomorrowLabel: self.t("dateTomorrow"),
                    yesterdayLabel: self.t("dateYesterday"))
                if let dueTime = parsed.due_time {
                    label += label.isEmpty ? dueTime : " " + dueTime
                }
                self.quickAddPreview = label
            }
        }
    }

    /// Relative word when adjacent-day, localized short date otherwise.
    private static func previewDateText(
        _ isoDate: String, todayLabel: String, tomorrowLabel: String,
        yesterdayLabel: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)
        if day == today { return todayLabel }
        if day == calendar.date(byAdding: .day, value: 1, to: today) { return tomorrowLabel }
        if day == calendar.date(byAdding: .day, value: -1, to: today) { return yesterdayLabel }
        let out = DateFormatter()
        out.locale = Locale.current
        out.setLocalizedDateFormatFromTemplate("MMMd")
        return out.string(from: date)
    }

    func toggleCompleted(_ task: Task) {
        guard let api else { return }
        Swift.Task {
            do {
                _ = try await api.set_completed(id: task.id, completed: !task.completed)
                flashStatus(i18n.t("statusUpdateTaskState"))
                reload()
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    func saveTask(_ task: Task) {
        guard let api else { return }
        Swift.Task {
            do {
                _ = try await api.update_task(task: task)
                flashStatus(i18n.t("statusTaskUpdated"))
                reload()
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    func deleteTask(_ task: Task) {
        deleteTasks([task])
    }

    /// Batch delete with one combined undo banner. When the deleted row is
    /// part of the active selection, the whole selection is the target.
    func deleteTasks(_ tasks: [Task]) {
        guard !tasks.isEmpty, let api else { return }
        let targets = tasks
        Swift.Task {
            do {
                for task in targets {
                    _ = try await api.delete_task(id: task.id)
                }
                for task in targets {
                    selectedTaskIDs.remove(task.id)
                    if expandedTaskID == task.id {
                        expandedTaskID = nil
                    }
                }
                let text = targets.count == 1
                    ? i18n.format("bannerTaskDeleted", targets[0].text)
                    : i18n.format("bannerTasksDeleted", targets.count)
                showUndoBanner(text) { [weak self] in
                    self?.restoreTasks(targets)
                }
                reload()
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    /// One-step undo for delete: re-adds the tasks (each receives a new
    /// id — position/order follows the current view's sort).
    private func restoreTasks(_ tasks: [Task]) {
        guard let api else { return }
        Swift.Task {
            do {
                for task in tasks {
                    _ = try await api.add_task(
                        text: task.text,
                        list_id: task.list_id,
                        due_date: task.due_date,
                        due_time: task.due_time,
                        notes: task.notes)
                }
                reload()
            } catch {
                flashStatus("\(error)")
            }
            dismissUndoBanner()
        }
    }

    func moveTask(_ task: Task, to list: TodoList) {
        guard let api else { return }
        let updated = Task(
            id: task.id, list_id: list.id, list_name: list.name, text: task.text,
            completed: task.completed, due_date: task.due_date, due_time: task.due_time,
            notes: task.notes, created_at: task.created_at)
        Swift.Task {
            do {
                _ = try await api.update_task(task: updated)
                flashStatus(i18n.format("statusTaskMoved", list.name))
                reload()
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    // MARK: - Row selection (Reminders-style multi-select)

    /// Click: plain selects one row, ⌘ toggles membership, ⇧ extends the
    /// range from the anchor. Any click collapses an expanded row.
    func clickSelectTask(_ id: Int64, index: Int, command: Bool, shift: Bool) {
        // Reminders behavior: clicking a row dismisses text-field focus
        // (search / quick add) so the keyboard flow takes over immediately.
        NSApp.keyWindow?.makeFirstResponder(nil)
        expandedTaskID = nil
        if command {
            if selectedTaskIDs.contains(id) {
                selectedTaskIDs.remove(id)
            } else {
                selectedTaskIDs.insert(id)
            }
            selectionAnchorIndex = index
        } else if shift, let anchor = selectionAnchorIndex,
                  tasks.indices.contains(anchor), tasks.indices.contains(index) {
            let lo = min(anchor, index)
            let hi = max(anchor, index)
            selectedTaskIDs = Set(tasks[lo...hi].map(\.id))
        } else {
            selectedTaskIDs = [id]
            selectionAnchorIndex = index
        }
    }

    /// ↑/↓ from the keyboard monitor. Plain moves the single selection;
    /// ⇧ extends the range from the anchor.
    func keyboardMoveSelection(_ delta: Int, extend: Bool) {
        guard !tasks.isEmpty else { return }
        let anchorOption = selectionAnchorIndex
            ?? tasks.firstIndex(where: { selectedTaskIDs.contains($0.id) })
        let anchor = anchorOption ?? (delta > 0 ? -1 : tasks.count)
        var target = max(0, min(tasks.count - 1, anchor + delta))
        // Hidden rows (collapsed completed section) are not navigable:
        // clamp to the last/first visible (incomplete) row instead.
        if completedCollapsed, tasks[target].completed {
            let incomplete = tasks.enumerated().filter { !$0.element.completed }
            guard let visible = (delta > 0
                ? incomplete.last.map(\.offset)
                : incomplete.first.map(\.offset))
            else { return }
            target = visible
        }
        let id = tasks[target].id
        if extend, let anchorOption {
            let lo = min(anchorOption, target)
            let hi = max(anchorOption, target)
            selectedTaskIDs = Set(tasks[lo...hi].map(\.id))
        } else {
            selectedTaskIDs = [id]
        }
        selectionAnchorIndex = target
    }

    func clearTaskSelection() {
        selectedTaskIDs = []
        selectionAnchorIndex = nil
    }

    func showUndoBanner(_ text: String, undo: @escaping () -> Void) {
        undoBannerTask?.cancel()
        undoBannerText = text
        undoBannerAction = undo
        undoBannerTask = Swift.Task { [weak self] in
            try? await Swift.Task.sleep(nanoseconds: 6_000_000_000)
            guard !Swift.Task.isCancelled else { return }
            self?.dismissUndoBanner()
        }
    }

    func dismissUndoBanner() {
        undoBannerTask?.cancel()
        undoBannerText = nil
        undoBannerAction = nil
    }

    // MARK: - List operations

    func createList(name: String, icon: String?, color: Int64?) {
        guard let api else { return }
        Swift.Task {
            do {
                let list = try await api.create_list(name: name, icon: icon, color: color)
                listEditSheet = nil
                flashStatus(i18n.format("statusCreateList", name.trimmingCharacters(in: .whitespaces)))
                reload()
                select(.list(list.id))
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    func updateList(_ list: TodoList, name: String, icon: String?, color: Int64?) {
        guard let api else { return }
        let updated = TodoList(
            id: list.id, name: name, icon: icon, color: color,
            pending_count: list.pending_count)
        Swift.Task {
            do {
                _ = try await api.update_list(item: updated)
                listEditSheet = nil
                reload()
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    func deleteList(_ list: TodoList) {
        guard let api else { return }
        Swift.Task {
            do {
                _ = try await api.delete_list(id: list.id)
                if currentView.listId == list.id {
                    select(.all)
                } else {
                    reload()
                }
                flashStatus(i18n.t("statusDeleteList"))
            } catch {
                flashStatus("\(error)")
            }
        }
    }

    // MARK: - Lookups for views

    /// The list-color ring/dot for a task (accent fallback when the list is
    /// missing or colorless — spec §5 / DESIGN-TOKENS).
    func listColor(for task: Task) -> Color {
        Color(argb: lists.first { $0.id == task.list_id }?.color)
    }
}

// MARK: - DTO helpers

// The generated DTOs are plain structs; equality is needed for edit-commit
// diffs. Synthesis cannot cross files, so compare fields by hand.
extension Task: Equatable {
    public static func == (lhs: Task, rhs: Task) -> Bool {
        lhs.id == rhs.id && lhs.list_id == rhs.list_id && lhs.list_name == rhs.list_name
            && lhs.text == rhs.text && lhs.completed == rhs.completed
            && lhs.due_date == rhs.due_date && lhs.due_time == rhs.due_time
            && lhs.notes == rhs.notes && lhs.created_at == rhs.created_at
    }
}

extension TodoList: Equatable {
    public static func == (lhs: TodoList, rhs: TodoList) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.icon == rhs.icon
            && lhs.color == rhs.color && lhs.pending_count == rhs.pending_count
    }
}

extension TodoList {
    var defaultIcon: String { "📋" }
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

enum HostError: Error, CustomStringConvertible {
    case missingRuntimeLayout(String)

    var description: String {
        switch self {
        case .missingRuntimeLayout(let roots):
            return "missing Rivet runtime/res layout under: \(roots)"
        }
    }
}
