import SwiftUI

/// Task pane: header, search + quick add, task list, empty states.
struct TaskPaneView: View {
    @Environment(AppState.self) private var state

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
                        icon: "📂", opacity: 0.4,
                        text: state.t("taskListEmptyHint"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(state.theme.background)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    state.isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: state.isSidebarVisible ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(state.isSidebarVisible ? state.t("sidebarHide") : state.t("sidebarShow"))

            Text(state.currentTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(state.theme.onSurface)
                .lineLimit(1)

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
            // Native addition: search field (0.6.4 shipped search via CLI only).
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(state.theme.tertiaryText)
                    .font(.system(size: 12))
                TextField(state.t("searchHint"), text: Binding(
                    get: { state.searchText },
                    set: { state.searchText = $0; state.refresh(); state.refreshStatusPersistent() }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                if !state.searchText.isEmpty {
                    Button {
                        state.searchText = ""
                        state.refresh()
                        state.refreshStatusPersistent()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(state.theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(state.theme.inputBorder, lineWidth: 1))

            // Quick add
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
            .frame(height: 38)
            .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(state.theme.inputBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var taskList: some View {
        Group {
            if state.tasks.isEmpty {
                emptyState(icon: "✓", opacity: 0.3, text: state.t("taskListEmpty"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.tasks) { task in
                            TaskRowView(task: task)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func emptyState(icon: String, opacity: Double, text: String) -> some View {
        VStack(spacing: 10) {
            Text(icon)
                .font(.system(size: 48))
                .opacity(opacity)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(state.theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
