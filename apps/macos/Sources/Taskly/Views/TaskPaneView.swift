import SwiftUI

/// Task pane: header, search + quick add, task list, empty states.
struct TaskPaneView: View {
    @Environment(AppState.self) private var state
    @FocusState private var quickAddFocused: Bool

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
        }
        // View menu focus requests (New Task ⌘N / Find ⌘F).
        .onChange(of: state.quickAddFocusToken) { _, _ in
            quickAddFocused = true
        }
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
                        ForEach(state.tasks) { task in
                            TaskRowView(task: task)
                        }
                    }
                    // Rows carry their own 16pt horizontal padding
                    // (DESIGN-TOKENS task row); the list only spaces vertically.
                    .padding(.vertical, 8)
                }
            }
        }
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
