import Foundation
import RivetSystem

/// Native scheduling and OS delivery for shared-core reminder decisions.
/// Eligibility, startup summarization, per-database de-duplication and
/// acknowledgement state live in the Racket application service.
@MainActor
final class ReminderService {
    private weak var model: AppModel?
    private var timer: Timer?
    private var authorized = false
    private var started = false
    /// The first check after launch asks the core for summary semantics.
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
            self.scheduleTimer()
            self.checkNow()
        }
    }

    /// `open_database` created a fresh shared-core reminder session.
    func resetSession() {
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
            guard let decisions = try? await model.reminderDecisions(startup: startup) else {
                return
            }
            await self.deliver(decisions, model: model)
        }
    }

    private func deliver(_ decisions: [RivetTypes.ReminderDecision], model: AppModel) async {
        for decision in decisions {
            guard authorized else {
                _ = await model.acknowledgeReminder(token: decision.token, phase: "failed")
                continue
            }
            guard await model.acknowledgeReminder(
                token: decision.token, phase: "attempted") else {
                continue // stale decision after a database switch
            }

            let body: String
            if decision.kind == "summary" {
                body = model.t("reminderStartupSummary", Int(decision.count))
            } else if let task = decision.task {
                body = Self.body(task, dueAtLabel: model.t("reminderDueAt"))
            } else {
                _ = await model.acknowledgeReminder(token: decision.token, phase: "failed")
                continue
            }

            do {
                try await RivetNotifications.show(
                    title: model.t("reminderTitle"), body: body)
                _ = await model.acknowledgeReminder(
                    token: decision.token, phase: "delivered")
            } catch {
                // A rejected/unavailable transport disables this app session.
                authorized = false
                _ = await model.acknowledgeReminder(
                    token: decision.token, phase: "failed")
            }
        }
    }

    /// "<text>\n<reminderDueAt>: <dueDate[ dueTime]>" (PRODUCT-SPEC §9).
    static func body(_ task: RivetTypes.Task, dueAtLabel: String) -> String {
        var when = task.due_date ?? ""
        if let time = task.due_time, !time.isEmpty {
            when += " \(time)"
        }
        return "\(task.text)\n\(dueAtLabel): \(when)"
    }
}
