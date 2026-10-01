import AppKit
import SwiftUI

/// Task pane: header (title, search, completed toggle), quick add, task
/// list, empty states. Owns the keyboard flow (↑/↓ select · ⇧↑/⇧↓ extend ·
/// Return expands · Esc collapses/clears) and the delete-undo banner.
struct TaskPaneView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var quickAddFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider().overlay(model.theme.divider)

            if model.isConnected {
                inputArea
            }
            Divider().overlay(model.theme.divider)

            ZStack {
                if model.isConnected {
                    taskList
                } else {
                    emptyState(
                        icon: "tray", opacity: 0.4,
                        text: model.t("taskListEmptyHint"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(model.theme.background)
            .overlay(alignment: .bottom) {
                undoBanner
            }
        }
        // View menu focus requests (New Task ⌘N / Find ⌘F).
        .onChange(of: model.quickAddFocusToken) { _, _ in
            quickAddFocused = true
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(alignment: .center, spacing: 10) {
            // Sidebar toggle centers against the whole title block; the
            // subtitle aligns under the title text (Reminders layout).
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(model.isSidebarVisible ? model.t("sidebarHide") : model.t("sidebarShow"))

            // Large title + secondary subtitle line (DESIGN-TOKENS view header).
            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(model.theme.onSurface)
                    .lineLimit(1)
                let subtitle = model.currentSubtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(model.theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            // Search lives in the header toolbar, left of the completed
            // toggle (PRODUCT-SPEC §2).
            if model.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(model.theme.tertiaryText)
                        .font(.system(size: 12))
                    TextField(model.t("searchHint"), text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                            model.searchChanged()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(model.theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: 200, height: 28)
                .background(model.theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(model.theme.inputBorder, lineWidth: 1))
                .onChange(of: model.searchFocusToken) { _, _ in
                    // Focus lands via the field's own FocusState below.
                    searchFocused = true
                }

                Button(model.showCompleted ? model.t("hideCompletedToggle") : model.t("showCompletedToggle")) {
                    model.showCompleted.toggle()
                    model.reload()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(model.theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @FocusState private var searchFocused: Bool

    private var inputArea: some View {
        @Bindable var model = model
        return VStack(spacing: 8) {
            // Quick add — accent plus button, focus-highlighted border, and
            // a live preview chip whenever the text parses to a schedule.
            HStack(spacing: 10) {
                Button {
                    model.quickAdd(model.quickAddText)
                } label: {
                    ZStack {
                        Circle().fill(model.theme.accent)
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 22, height: 22)
                    .opacity(model.quickAddText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .help(model.t("taskListInputHint"))

                TextField(model.t("taskListInputHint"), text: $model.quickAddText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($quickAddFocused)
                    .onSubmit {
                        model.quickAdd(model.quickAddText)
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
                    .foregroundStyle(model.theme.accent)
                    .background(model.theme.accent.opacity(0.08), in: Capsule())
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(model.theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        quickAddFocused ? model.theme.accent : model.theme.inputBorder,
                        lineWidth: quickAddFocused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.12), value: quickAddFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Live parse of the quick-add text (same grammar as model.quickAdd):
    /// "买牛奶 @10am" → 今天 10:00, "买菜 +1d" → 明天. Nil when no schedule.
    private var schedulePreview: String? {
        let raw = model.quickAddText
        guard !raw.isEmpty else { return nil }
        let parser = DateParser()
        let (_, command) = parser.extractTimeCommand(raw)
        guard let command, let parsed = parser.parseDueExpression(command) else { return nil }

        var label = Self.previewDateText(
            parsed.dueDate,
            todayLabel: model.t("navToday"),
            tomorrowLabel: model.t("dateTomorrow"),
            yesterdayLabel: model.t("dateYesterday"))
        if let dueTime = parsed.dueTime {
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
            if model.tasks.isEmpty {
                emptyState(icon: "checkmark.circle", opacity: 0.3, text: model.t("taskListEmpty"))
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
        let incomplete = model.tasks.filter { !$0.completed }
        let completed = model.tasks.filter { $0.completed }
        ForEach(Array(incomplete.enumerated()), id: \.element.id) { index, task in
            TaskRowView(task: task, index: index)
        }

        // Collapsible completed section (Reminders: quiet header + count).
        if !completed.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.completedCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.completedCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.theme.secondaryText)
                    Text(model.t("subtitleCompleted", completed.count))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.theme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            if !model.completedCollapsed {
                ForEach(Array(completed.enumerated()), id: \.element.id) { index, task in
                    TaskRowView(task: task, index: incomplete.count + index)
                }
            }
        }
    }

    /// Floating delete-undo banner (Reminders-style) at the pane bottom.
    @ViewBuilder
    private var undoBanner: some View {
        if let bannerText = model.undoBannerText {
            HStack(spacing: 12) {
                Text(bannerText)
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.onSurface)
                    .lineLimit(1)
                Button(model.t("bannerUndo")) {
                    model.undoBannerAction?()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.theme.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(model.theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(model.theme.divider, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Keyboard flow (Reminders parity)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                model.lastModifierFlags = event.modifierFlags
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
        guard model.isConnected, !model.tasks.isEmpty else { return event }
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSText || responder is NSTextView {
            return event
        }

        switch event.keyCode {
        case 125: // ↓
            model.keyboardMoveSelection(1, extend: event.modifierFlags.contains(.shift))
            return nil
        case 126: // ↑
            model.keyboardMoveSelection(-1, extend: event.modifierFlags.contains(.shift))
            return nil
        case 36: // Return — expand the selected row / collapse
            if model.expandedTaskID != nil {
                model.expandedTaskID = nil
            } else if let first = selectedInOrder().first,
                      let index = model.tasks.firstIndex(where: { $0.id == first }) {
                model.clickSelectTask(first, index: index, command: false, shift: false)
                model.expandedTaskID = first
            }
            return nil
        case 53: // Esc — collapse, then clear selection
            if model.expandedTaskID != nil {
                model.expandedTaskID = nil
                return nil
            }
            if !model.selectedTaskIDs.isEmpty {
                model.clearTaskSelection()
                return nil
            }
            return event
        default:
            return event
        }
    }

    /// Selected ids in the current view's order (the set itself is unordered).
    private func selectedInOrder() -> [Int64] {
        model.tasks.map(\.id).filter { model.selectedTaskIDs.contains($0) }
    }

    private func emptyState(icon: String, opacity: Double, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(model.theme.tertiaryText)
                .opacity(opacity)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(model.theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
