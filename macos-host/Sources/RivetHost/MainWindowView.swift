import AppKit
import SwiftUI

/// Root window: [sidebar | task pane] + status bar (PRODUCT-SPEC §2).
struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.isSidebarVisible {
                    SidebarView()
                        .frame(width: Palette.sidebarWidth)
                    Divider()
                        .overlay(model.theme.divider)
                }
                TaskPaneView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(model.theme.divider)
            statusBar
        }
        .background(model.theme.background)
        .frame(minWidth: 760, minHeight: 520)
        .sheet(item: Binding(
            get: { model.listEditSheet },
            set: { model.listEditSheet = $0 })) { context in
            ListEditSheet(context: context)
        }
        .sheet(isPresented: Binding(
            get: { model.aboutVisible },
            set: { model.aboutVisible = $0 })) {
            AboutSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.updateSheetVisible },
            set: { newValue in
                model.updateSheetVisible = newValue
                if !newValue { model.dismissUpdateSheet() }
            })) {
            UpdateSheet()
        }
        .confirmationDialog(
            model.confirmContext?.title ?? "",
            isPresented: Binding(
                get: { model.confirmContext != nil },
                set: { if !$0 { model.confirmContext = nil } }),
            titleVisibility: .visible
        ) {
            Button(model.t("dialogConfirm"), role: .destructive) {
                model.confirmContext?.onConfirm()
                model.confirmContext = nil
            }
            Button(model.t("dialogCancel"), role: .cancel) {
                model.confirmContext = nil
            }
        } message: {
            Text(model.confirmContext?.message ?? "")
        }
    }

    private var statusBar: some View {
        HStack {
            Text(model.statusMessage)
                .font(.system(size: 12))
                .foregroundStyle(model.theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: Palette.statusHeight)
        .background(model.theme.sidebar)
    }
}

/// 2×2 smart-view tiles + My Lists section (PRODUCT-SPEC §3).
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                smartTiles
                myLists
            }
            .padding(12)
        }
        .background(model.theme.sidebar)
    }

    private var smartTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            SmartChip(view: .today, icon: "calendar", titleKey: "navToday",
                      color: Palette.today, count: Int(model.counts.today))
            SmartChip(view: .planned, icon: "calendar.badge.clock", titleKey: "navPlanned",
                      color: Palette.planned, count: Int(model.counts.planned))
            SmartChip(view: .all, icon: "tray.full", titleKey: "navAll",
                      color: Palette.all, count: Int(model.counts.all))
            SmartChip(view: .completed, icon: "checkmark.circle", titleKey: "navCompleted",
                      color: Palette.all, count: Int(model.counts.completed))
        }
    }

    private var myLists: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.t("sectionMyLists"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.theme.secondaryText)
                Spacer()
                Button {
                    model.listEditSheet = ListEditContext(mode: .create)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(model.theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(!model.isConnected)
                .help(model.t("dialogCreateList"))
            }
            .padding(.horizontal, 4)

            ForEach(model.lists, id: \.id) { list in
                ListRowView(list: list)
            }
        }
    }
}

/// Smart-view chip (DESIGN-TOKENS: 34px neutral chip, radius 8, 8px gaps;
/// colored 14px SF Symbol glyph + 13px label + quiet 12px count right;
/// checked = quiet selection fill, hover = hover fill — saturated color
/// never fills the chip, it lives on the glyph).
private struct SmartChip: View {
    @Environment(AppModel.self) private var model
    let view: SmartView
    let icon: String
    let titleKey: String
    let color: Color
    let count: Int

    @State private var isHovering = false

    private var isSelected: Bool {
        model.currentView == view
    }

    var body: some View {
        Button {
            model.select(view)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(model.t(titleKey))
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.onSurface)
                    .lineLimit(1)
                    // The label compresses last: Spacer and count yield first.
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(model.theme.secondaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: Palette.smartChipHeight)
            // First background = top layer: the quiet tint composites over
            // the surface fill; border sits outside both.
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? model.theme.selection : (isHovering ? model.theme.hover : .clear)))
            .background(model.theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(model.theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!model.isConnected)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ListRowView: View {
    @Environment(AppModel.self) private var model
    let list: TodoList

    private var isSelected: Bool {
        model.currentView.listId == list.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(argb: list.color))
                .frame(width: 20, height: 20)
                .overlay(
                    Text(list.icon ?? list.defaultIcon)
                        .font(.system(size: 11))
                        .clipShape(Circle())
                )
            Text(list.name)
                .font(.system(size: 13))
                .foregroundStyle(model.theme.onSurface)
                .lineLimit(1)
            Spacer()
            if list.pending_count > 0 {
                Text("\(list.pending_count)")
                    .font(.system(size: 11))
                    .foregroundStyle(model.theme.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // First background = top layer: selection tint over the surface card.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? model.theme.selection : Color.clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(model.theme.surface)
        )
        .overlay(
            // Checked = quiet selection fill; the divider border never
            // changes color (DESIGN-TOKENS list row).
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(model.theme.divider, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            model.select(.list(list.id))
        }
        .onTapGesture(count: 2) {
            // Reminders: double-click a list renames it in place.
            model.listEditSheet = ListEditContext(mode: .edit(list))
        }
        .contextMenu {
            Button(model.t("dialogEditList")) {
                model.listEditSheet = ListEditContext(mode: .edit(list))
            }
            Button(model.t("listDelete"), role: .destructive) {
                model.confirmContext = ConfirmContext(
                    title: model.t("listDeleteConfirm"),
                    message: model.t("listDeleteConfirmContent"),
                    onConfirm: { model.deleteList(list) })
            }
        }
    }
}
