import AppKit
import SwiftUI

/// Task pane: header, search + quick add, task list, empty states.
/// Owns the keyboard flow (↑/↓ select · ⇧↑/⇧↓ extend · Return expands ·
/// Esc collapses/clears) and the delete-undo banner.
struct TaskPaneView: View {
    @Environment(AppState.self) private var state
    @FocusState private var quickAddFocused: Bool
    @State private var completedCollapsed = false
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
            // Quick add — the pane's single, prominent input
            HStack {
                TextField(state.t("taskListInputHint"), text: $state.quickAddText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        state.quickAdd(state.quickAddText)
                    }
                if !state.quickAddText.isEmpty {
                    Text("↩")
                        .font(.system(size: 12))
                        .foregroundStyle(state.theme.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(state.theme.inputBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                    completedCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: completedCollapsed ? "chevron.right" : "chevron.down")
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

            if !completedCollapsed {
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
