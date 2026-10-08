import Foundation
import RivetSystem

/// Due-task reminders (PRODUCT-SPEC §9). Checks every 60 s while a database
/// is connected plus once at startup. Every task notifies at most once per
/// session; the startup check summarizes when more than three tasks are due.
/// Notification transport failures are swallowed for the session — this
/// crashed on macOS once (0.6.1 regression), never again.
@MainActor
final class ReminderService {
    private weak var model: AppModel?
    private var timer: Timer?
    private var notifiedIDs: Set<Int64> = []
    private var authorized = false
    private var started = false
    /// The first check after launch summarizes instead of spamming.
    private var startupCheckPending = true

    init(model: AppModel) {
        self.model = model
    }

    /// Authorization + timer + the startup check. Safe to call once.
    func start() {
        guard !started else { return }
        started = true
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            // Unavailable (no .app bundle, e.g. `raco rivet dev` runs) or
            // denied both mean the same thing: stay silent all session.
            self.authorized = (try? await RivetNotifications.requestAuthorization()) ?? false
            guard self.authorized else { return }
            await MainActor.run {
                self.scheduleTimer()
                self.checkNow()
            }
        }
    }

    /// Database changed underneath us (File ▸ Open): forget what we showed.
    func resetSession() {
        notifiedIDs.removeAll()
        startupCheckPending = true
        if authorized {
            checkNow()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkNow() {
        guard authorized, let model, model.isConnected else { return }
        let startup = startupCheckPending
        startupCheckPending = false
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            guard let snapshot = try? await model.currentSnapshotForReminders() else { return }
            await MainActor.run {
                self.process(snapshot.tasks, startup: startup, model: model)
            }
        }
    }

    private func process(_ tasks: [Task], startup: Bool, model: AppModel) {
        let due = tasks.filter { isDue($0) && !notifiedIDs.contains($0.id) }
        // Everything seen now is marked notified, even the summarized ones.
        for task in due {
            notifiedIDs.insert(task.id)
        }
        guard !due.isEmpty else { return }

        if startup && due.count > 3 {
            show(
                title: model.t("reminderTitle"),
                body: model.t("reminderStartupSummary", due.count))
            return
        }
        for task in due {
            show(
                title: model.t("reminderTitle"),
                body: Self.body(task, dueAtLabel: model.t("reminderDueAt")))
        }
    }

    /// "<text>\n<reminderDueAt>: <dueDate[ dueTime]>" (PRODUCT-SPEC §9).
    static func body(_ task: Task, dueAtLabel: String) -> String {
        var when = task.due_date ?? ""
        if let time = task.due_time, !time.isEmpty {
            when += " \(time)"
        }
        return "\(task.text)\n\(dueAtLabel): \(when)"
    }

    /// Due = incomplete ∧ has due_date ∧ combine(due_date, due_time|00:00) ≤ now
    /// (overdue included, however old).
    private func isDue(_ task: Task) -> Bool {
        guard !task.completed, let dateOnly = task.due_date, !dateOnly.isEmpty else {
            return false
        }
        guard var date = DateParser.strictDate(from: dateOnly) else { return false }
        if let time = task.due_time, !time.isEmpty {
            let parts = time.split(separator: ":")
            if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
                date = Calendar.current.date(
                    bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
            }
        }
        return date <= Date()
    }

    /// A failing transport must never take the app down: swallow for the
    /// session (PRODUCT-SPEC §9).
    private func show(title: String, body: String) {
        _Concurrency.Task {
            try? await RivetNotifications.show(title: title, body: body)
        }
    }
}
