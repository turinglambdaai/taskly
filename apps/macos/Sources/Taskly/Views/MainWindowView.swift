import AppKit
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
            // The CommandGroup replacements above empty some system-injected
            // groups but leave their menu shells behind (an empty View menu,
            // trailing separators). SwiftUI exposes no placement to delete a
            // menu, so drop all-separator submenus on the AppKit level once
            // the menu bar is built.
            DispatchQueue.main.async { Self.pruneEmptyMenus() }
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

    /// Remove submenus whose items are only separators (system shells left
    /// empty by CommandGroup replacements) and trailing separators/hidden
    /// stub items left by replaced groups.
    @MainActor static func pruneEmptyMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            while let last = submenu.items.last,
                  last.isSeparatorItem || last.isHidden
                  || (last.title.isEmpty && last.submenu == nil) {
                submenu.removeItem(last)
            }
            let visible = submenu.items.filter { !$0.isHidden }
            if visible.allSatisfy(\.isSeparatorItem) {
                mainMenu.removeItem(item)
            }
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
                // Search sits inside the sidebar, above the four filter
                // tiles — macOS Reminders placement.
                SidebarSearchField()
                smartTiles
                myLists
            }
            .padding(12)
        }
        .background(state.theme.sidebar)
    }

    private var smartTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            SmartChip(view: .today, icon: "calendar", titleKey: "navToday",
                      color: Palette.today, count: state.todayCount)
            SmartChip(view: .planned, icon: "calendar.badge.clock", titleKey: "navPlanned",
                      color: Palette.planned, count: state.plannedCount)
            SmartChip(view: .all, icon: "tray.full", titleKey: "navAll",
                      color: Palette.all, count: state.allCount)
            SmartChip(view: .completed, icon: "checkmark.circle", titleKey: "navCompleted",
                      color: Palette.all, count: state.completedCount)
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

/// Sidebar search bound to the global searchText (Reminders placement:
/// above the smart-list tiles). The View menu's Ctrl+F focuses it via the
/// searchFocusToken.
private struct SidebarSearchField: View {
    @Environment(AppState.self) private var state
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(state.theme.tertiaryText)
                .font(.system(size: 12))
            TextField(state.t("searchHint"), text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onChange(of: state.searchText) { _, _ in
                    state.refresh()
                }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(state.theme.inputBorder, lineWidth: 1))
        .onChange(of: state.searchFocusToken) { _, _ in
            isFocused = true
        }
    }
}

/// Smart-view chip (DESIGN-TOKENS: 34px neutral chip, radius 8, 8px gaps;
/// colored 14px SF Symbol glyph + 13px label + quiet 12px count right;
/// checked = quiet selection fill, hover = hover fill — saturated color
/// never fills the chip, it lives on the glyph).
private struct SmartChip: View {
    @Environment(AppState.self) private var state
    let view: SmartView
    let icon: String
    let titleKey: String
    let color: Color
    let count: Int

    @State private var isHovering = false

    private var isSelected: Bool {
        state.currentView == view
    }

    var body: some View {
        Button {
            state.select(view)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(state.t(titleKey))
                    .font(.system(size: 13))
                    .foregroundStyle(state.theme.onSurface)
                    .lineLimit(1)
                    // The label compresses last: Spacer and count yield first.
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(state.theme.secondaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: Palette.smartChipHeight)
            // First background = top layer: the quiet tint composites over
            // the surface fill; border sits outside both.
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? state.theme.selection : (isHovering ? state.theme.hover : .clear)))
            .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(state.theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!state.isConnected)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
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
                .frame(width: 20, height: 20)
                .overlay(
                    Text(list.icon ?? TodoList.defaultIcon)
                        .font(.system(size: 11))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // First background = top layer: selection tint over the surface card.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? state.theme.selection : Color.clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(state.theme.surface)
        )
        .overlay(
            // Checked = quiet selection fill; the divider border never
            // changes color (DESIGN-TOKENS list row).
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(state.theme.divider, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            state.select(.list(list.id))
        }
        .onTapGesture(count: 2) {
            // Reminders: double-click a list renames it in place.
            state.listEditSheet = ListEditContext(mode: .edit(list))
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
