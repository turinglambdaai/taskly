import SwiftUI

/// Root window: [sidebar | task pane] + status bar.
struct MainWindowView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if state.isSidebarVisible {
                    SidebarView()
                        .frame(width: Palette.sidebarWidth)
                    Divider()
                        .overlay(state.theme.divider)
                }
                TaskPaneView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(state.theme.divider)
            statusBar
        }
        .background(state.theme.background)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            state.openDefaultDatabaseIfNeeded()
        }
        .sheet(item: Binding(
            get: { state.taskDetailContext },
            set: { state.taskDetailContext = $0 })) { task in
            TaskDetailSheet(task: task)
        }
        .sheet(item: Binding(
            get: { state.listEditSheet },
            set: { state.listEditSheet = $0 })) { context in
            ListEditSheet(context: context)
        }
        .sheet(isPresented: Binding(
            get: { state.aboutVisible },
            set: { state.aboutVisible = $0 })) {
            AboutSheet()
        }
        .confirmationDialog(
            Binding(get: { state.confirmContext?.title ?? "" }, set: { _ in }).wrappedValue.isEmpty
                ? "" : (state.confirmContext?.title ?? ""),
            isPresented: Binding(
                get: { state.confirmContext != nil },
                set: { if !$0 { state.confirmContext = nil } }),
            titleVisibility: .visible
        ) {
            Button(state.t("dialogConfirm"), role: .destructive) {
                state.confirmContext?.onConfirm()
                state.confirmContext = nil
            }
            Button(state.t("dialogCancel"), role: .cancel) {
                state.confirmContext = nil
            }
        } message: {
            Text(state.confirmContext?.message ?? "")
        }
    }

    private var statusBar: some View {
        HStack {
            Text(state.statusMessage)
                .font(.system(size: 12))
                .foregroundStyle(state.theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: Palette.statusHeight)
        .background(state.theme.sidebar)
    }
}

/// 2×2 smart-view tiles + My Lists section.
struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                smartTiles
                myLists
            }
            .padding(12)
        }
        .background(state.theme.sidebar)
    }

    private var smartTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            SmartTile(view: .today, icon: "🗓", titleKey: "navToday",
                      color: Palette.today, count: state.todayCount)
            SmartTile(view: .planned, icon: "📅", titleKey: "navPlanned",
                      color: Palette.planned, count: state.plannedCount)
            SmartTile(view: .all, icon: "≡", titleKey: "navAll",
                      color: Palette.all, count: state.allCount)
            SmartTile(view: .completed, icon: "✓", titleKey: "navCompleted",
                      color: Palette.completed, count: state.completedCount)
        }
    }

    private var myLists: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(state.t("sectionMyLists"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.theme.secondaryText)
                Spacer()
                Button {
                    state.listEditSheet = ListEditContext(mode: .create)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(state.theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(!state.isConnected)
                .help(state.t("dialogCreateList"))
            }
            .padding(.horizontal, 4)

            ForEach(state.lists) { list in
                ListRowView(list: list)
            }
        }
    }
}

private struct SmartTile: View {
    @Environment(AppState.self) private var state
    let view: SmartView
    let icon: String
    let titleKey: String
    let color: Color
    let count: Int

    var body: some View {
        Button {
            state.select(view)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading) {
                    Spacer()
                    HStack(spacing: 6) {
                        Text(icon)
                            .font(.system(size: 15))
                        Text(state.t(titleKey))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    Spacer().frame(height: 0)
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.18), in: Capsule())
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Palette.tileHeight)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!state.isConnected)
    }
}

private struct ListRowView: View {
    @Environment(AppState.self) private var state
    let list: TodoList

    private var isSelected: Bool {
        if case .list(let id) = state.currentView { return id == list.id }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(argb: list.color))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(list.icon ?? TodoList.defaultIcon)
                        .font(.system(size: 14))
                        .clipShape(Circle())
                )
            Text(list.name)
                .font(.system(size: 13))
                .foregroundStyle(state.theme.onSurface)
                .lineLimit(1)
            Spacer()
            if list.pendingCount > 0 {
                Text("\(list.pendingCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(state.theme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? state.theme.selection : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? state.theme.accent : state.theme.divider, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            state.select(.list(list.id))
        }
        .contextMenu {
            Button(state.t("dialogEditList")) {
                state.listEditSheet = ListEditContext(mode: .edit(list))
            }
            Button(state.t("listDelete"), role: .destructive) {
                state.confirmContext = ConfirmContext(
                    title: state.t("listDeleteConfirm"),
                    message: state.t("listDeleteConfirmContent"),
                    onConfirm: { state.deleteList(list) })
            }
        }
    }
}
