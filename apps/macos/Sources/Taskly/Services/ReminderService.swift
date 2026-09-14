import Foundation
@preconcurrency import UserNotifications

/// Due-task reminders (PRODUCT-SPEC §9). Checks every 60 s while connected,
/// plus once at startup. Per-session dedupe; notification-transport failures
/// disable notifications for the session instead of crashing.
@MainActor
public final class ReminderService: ObservableObject {
    private var notifiedIds: Set<Int> = []
    private var timer: Timer?
    private weak var state: AppState?
    private var nativeDisabled = false
    private var authorizationRequested = false

    init() {}

    /// Wire-up after the owner finishes initializing (avoids self-in-init).
    func attach(_ state: AppState) {
        self.state = state
    }

    public func start() {
        checkNow()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the active database changes (dedupe set is per-DB session).
    public func resetNotified() {
        notifiedIds.removeAll()
        nativeDisabled = false
    }

    func checkNow() {
        guard let state, state.isConnected else { return }
        let tasks: [TaskItem]
        do {
            tasks = try state.db.getAllIncompleteTasksWithDueDate()
        } catch {
            return
        }

        var due: [TaskItem] = []
        for task in tasks where isDue(task) {
            guard !notifiedIds.contains(task.id) else { continue }
            notifiedIds.insert(task.id)
            due.append(task)
        }

        guard !due.isEmpty else { return }

        if due.count > 3 {
            notify(
                title: I18nService.shared.t("reminderTitle"),
                body: I18nService.shared.format("reminderStartupSummary", due.count))
        } else {
            for task in due {
                notify(
                    title: I18nService.shared.t("reminderTitle"),
                    body: task.text + "\n"
                        + I18nService.shared.t("reminderDueAt") + ": " + dueLine(task))
            }
        }
    }

    private func dueLine(_ task: TaskItem) -> String {
        var line = task.dueDate ?? ""
        if let time = task.dueTime, !time.isEmpty {
            line += " \(time)"
        }
        return line
    }

    /// due = incomplete ∧ has date ∧ combine(date, time|00:00) ≤ now (local).
    func isDue(_ task: TaskItem) -> Bool {
        guard task.dueDate != nil else { return false }
        let combined = DateParser.combineDateTime(task.dueDate, task.dueTime)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let due = formatter.date(from: combined) else { return false }
        return due <= Date()
    }

    /// UNUserNotificationCenter.current() raises an ObjC exception (uncatchable
    /// in Swift) when the process has no real .app bundle — this crashed the
    /// 0.6.1 dev/CLI launches. Preflight the bundle before touching it.
    private var notificationCenterAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Fire-and-forget local notification; failures flip `nativeDisabled`.
    private func notify(title: String, body: String) {
        guard !nativeDisabled else { return }
        guard notificationCenterAvailable else {
            nativeDisabled = true
            return
        }
        let center = UNUserNotificationCenter.current()

        if authorizationRequested {
            post(center, title: title, body: body)
            return
        }

        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if granted {
                    self.nativeDisabled = false
                    self.post(center, title: title, body: body)
                } else {
                    // Permission denied: stay silent this session (never crash).
                    self.nativeDisabled = true
                }
            }
        }
    }

    private func post(_ center: UNUserNotificationCenter, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { [weak self] error in
            if error != nil {
                Task { @MainActor [weak self] in
                    self?.nativeDisabled = true
                }
            }
        }
    }
}
