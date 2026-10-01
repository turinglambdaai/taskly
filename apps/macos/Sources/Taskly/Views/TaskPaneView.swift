import AppKit
import SwiftUI

/// Task pane: header, search + quick add, task list, empty states.
/// Owns the keyboard flow (↑/↓ select · ⇧↑/⇧↓ extend · Return expands ·
/// Esc collapses/clears) and the delete-undo banner.
struct TaskPaneView: View {
    @Environment(AppState.self) private var state
    @FocusState private var quickAddFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            header
            Divider().overlay(state.theme.divider)

            if state.isConnected {
                inputArea
            }
            Divider().overlay(state.theme.divider)

            ZStack {
            if state.isConnected {
                taskList
            } else {
                emptyState(
                    icon: "tray", opacity: 0.4,
                    text: state.t("taskListEmptyHint"))
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(state.theme.background)
            .overlay(alignment: .bottom) {
                undoBanner
            }
        }
        // View menu focus requests (New Task ⌘N / Find ⌘F).
        .onChange(of: state.quickAddFocusToken) { _, _ in
            quickAddFocused = true
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private var header: some View {
        @Bindable var state = state
        return HStack(alignment: .center, spacing: 10) {
            // Sidebar toggle centers against the whole title block; the
            // subtitle aligns under the title text (Reminders layout).
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    state.isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(state.isSidebarVisible ? state.t("sidebarHide") : state.t("sidebarShow"))

            // Large title + secondary subtitle line (DESIGN-TOKENS view header).
            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(state.theme.onSurface)
                    .lineLimit(1)
                let subtitle = state.currentSubtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(state.theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if state.isConnected {
                Button(state.showCompleted ? state.t("hideCompletedToggle") : state.t("showCompletedToggle")) {
                    state.showCompleted.toggle()
                    state.refresh()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(state.theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var inputArea: some View {
        @Bindable var state = state
        return VStack(spacing: 8) {
            // Quick add — accent plus button, focus-highlighted border, and
            // a live preview chip whenever the text parses to a schedule.
            HStack(spacing: 10) {
                Button {
                    state.quickAdd(state.quickAddText)
                } label: {
                    ZStack {
                        Circle().fill(state.theme.accent)
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 22, height: 22)
                    .opacity(state.quickAddText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .help(state.t("taskListInputHint"))

                TextField(state.t("taskListInputHint"), text: $state.quickAddText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($quickAddFocused)
                    .onSubmit {
                        state.quickAdd(state.quickAddText)
                    }

                if let preview = schedulePreview {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(preview)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(state.theme.accent)
                    .background(state.theme.accent.opacity(0.08), in: Capsule())
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        quickAddFocused ? state.theme.accent : state.theme.inputBorder,
                        lineWidth: quickAddFocused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.12), value: quickAddFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Live parse of the quick-add text (same grammar as state.quickAdd):
    /// "明天买菜" → 明天, "练习 @10am" → 今天 10:00. Nil when no schedule.
    private var schedulePreview: String? {
        let raw = state.quickAddText
        guard !raw.isEmpty else { return nil }
        let parser = DateParser()
        let (_, command) = parser.extractTimeCommand(raw)
        guard let command, let parsed = parser.parse(command) else { return nil }
        let isDateOnly = !command.hasPrefix("@")
            && ["d", "w", "M"].contains(String(command.suffix(1)))
        let dueDate = DateParser.extractDateOnly(parsed)
        let dueTime = isDateOnly ? nil : DateParser.extractTimeOnly(parsed)
        guard dueDate != nil || dueTime != nil else { return nil }

        var label = ""
        if let dueDate {
            label = Self.previewDateText(
                dueDate,
                todayLabel: state.t("navToday"),
                tomorrowLabel: state.t("dateTomorrow"),
                yesterdayLabel: state.t("dateYesterday"))
        }
        if let dueTime {
            label += label.isEmpty ? dueTime : " " + dueTime
        }
        return label.isEmpty ? nil : label
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

    private var taskList: some View {
        Group {
            if state.tasks.isEmpty {
                emptyState(icon: "checkmark.circle", opacity: 0.3, text: state.t("taskListEmpty"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        rowsWithCompletedSection
                    }
                    // Rows carry their own 16pt horizontal padding
                    // (DESIGN-TOKENS task row); the list only spaces vertically.
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var rowsWithCompletedSection: some View {
        let incomplete = state.tasks.filter { !$0.completed }
        let completed = state.tasks.filter { $0.completed }
        ForEach(Array(incomplete.enumerated()), id: \.element.id) { index, task in
            TaskRowView(task: task, index: index)
        }

        // Collapsible completed section (Reminders: quiet header + count).
        if !completed.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    state.completedCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.completedCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.theme.secondaryText)
                    Text(state.t("subtitleCompleted").replaceCompletions(completed.count))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.theme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            if !state.completedCollapsed {
                ForEach(Array(completed.enumerated()), id: \.element.id) { index, task in
                    TaskRowView(task: task, index: incomplete.count + index)
                }
            }
        }
    }

    /// Floating delete-undo banner (Reminders-style) at the pane bottom.
    @ViewBuilder
    private var undoBanner: some View {
        if let bannerText = state.undoBannerText {
            HStack(spacing: 12) {
                Text(bannerText)
                    .font(.system(size: 13))
                    .foregroundStyle(state.theme.onSurface)
                    .lineLimit(1)
                Button(state.t("bannerUndo")) {
                    state.undoBannerAction?()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.theme.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(state.theme.divider, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Keyboard flow (Reminders parity)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                state.lastModifierFlags = event.modifierFlags
                return event
            }
            return handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Consumes navigation keys only when the user is NOT typing — while a
    /// text field has the field editor (NSText first responder), every key
    /// passes through untouched.
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard state.isConnected, !state.tasks.isEmpty else { return event }
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSText || responder is NSTextView {
            return event
        }

        switch event.keyCode {
        case 125: // ↓
            state.keyboardMoveSelection(1, extend: event.modifierFlags.contains(.shift))
            return nil
        case 126: // ↑
            state.keyboardMoveSelection(-1, extend: event.modifierFlags.contains(.shift))
            return nil
        case 36: // Return — expand the selected row / collapse with commit
            if state.expandedTaskID != nil {
                state.expandedTaskID = nil
            } else if let first = selectedInOrder().first, let index = state.tasks.firstIndex(where: { $0.id == first }) {
                state.clickSelectTask(first, index: index, command: false, shift: false)
                state.expandedTaskID = first
            }
            return nil
        case 53: // Esc — collapse, then clear selection
            if state.expandedTaskID != nil {
                state.expandedTaskID = nil
                return nil
            }
            if !state.selectedTaskIDs.isEmpty {
                state.clearTaskSelection()
                return nil
            }
            return event
        default:
            return event
        }
    }

    /// Selected ids in the current view's order (the set itself is unordered).
    private func selectedInOrder() -> [Int] {
        state.tasks.map(\.id).filter { state.selectedTaskIDs.contains($0) }
    }

    private func emptyState(icon: String, opacity: Double, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(state.theme.tertiaryText)
                .opacity(opacity)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(state.theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension String {
    /// subtitleCompleted uses "{0} 个已完成" — positional fill for the header.
    func replaceCompletions(_ count: Int) -> String {
        replacingOccurrences(of: "{0}", with: String(count))
    }
}
