import SwiftUI

/// Create / edit a list: name, emoji, color.
struct ListEditSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let context: ListEditContext
    @State private var name = ""
    @State private var icon: String?
    @State private var color: Int?
    @State private var emojiPickerVisible = false
    @State private var colorPickerVisible = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing ? state.t("dialogEditList") : state.t("dialogCreateList"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.theme.onSurface)

            // Quiet input: surface fill + 1px input border (quick-add language).
            TextField(state.t("dialogInputListName"), text: $name)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(state.theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(state.theme.inputBorder, lineWidth: 1))
                .focused($nameFocused)
                .onExitCommand { dismiss() }

            HStack(spacing: 24) {
                // Icon
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.t("dialogListIcon"))
                        .font(.system(size: 12))
                        .foregroundStyle(state.theme.secondaryText)
                    HStack(spacing: 6) {
                        Button {
                            emojiPickerVisible.toggle()
                        } label: {
                            ZStack {
                                Circle().fill(state.theme.accent)
                                Text(icon ?? "✚")
                                    .font(.system(size: 18))
                            }
                            .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $emojiPickerVisible) {
                            EmojiPickerGrid(selection: $icon)
                        }
                        if icon != nil {
                            Button(state.t("dialogClearIcon")) { icon = nil }
                                .font(.system(size: 12))
                                .foregroundStyle(state.theme.secondaryText)
                                .buttonStyle(.plain)
                        }
                    }
                }

                // Color
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.t("dialogListColor"))
                        .font(.system(size: 12))
                        .foregroundStyle(state.theme.secondaryText)
                    HStack(spacing: 6) {
                        Button {
                            colorPickerVisible.toggle()
                        } label: {
                            ZStack {
                                Circle().fill(Color(argb: color))
                                if color == nil {
                                    Image(systemName: "paintpalette")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $colorPickerVisible) {
                            ColorSwatchGrid(selection: $color)
                        }
                        if color != nil {
                            Button(state.t("dialogClearColor")) { color = nil }
                                .font(.system(size: 12))
                                .foregroundStyle(state.theme.secondaryText)
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(state.t("dialogCancel"))
                        .font(.system(size: 13))
                        .foregroundStyle(state.theme.secondaryText)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    commit()
                } label: {
                    Text(state.t("dialogConfirm"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(state.theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(state.theme.background)
        .onAppear {
            if case let .edit(list) = context.mode {
                name = list.name
                icon = list.icon
                color = list.color
            }
            nameFocused = true
        }
        .onExitCommand { dismiss() }
    }

    private var editing: Bool {
        if case .edit = context.mode { return true }
        return false
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch context.mode {
        case .create:
            state.createList(name: trimmed, icon: icon, color: color)
        case .edit(let list):
            state.updateList(
                list, name: trimmed, icon: icon, color: color,
                clearIcon: icon == nil && list.icon != nil,
                clearColor: color == nil && list.color != nil)
        }
        dismiss()
    }
}

private struct EmojiPickerGrid: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(Palette.emojiCategories.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { emoji in
                        Button {
                            selection = emoji
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 20))
                                .frame(width: 34, height: 34)
                                .background(
                                    selection == emoji
                                        ? Color.accentColor.opacity(0.25)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
    }
}

private struct ColorSwatchGrid: View {
    @Binding var selection: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Palette.listColors.enumerated()), id: \.offset) { index, color in
                Button {
                    selection = ARGB.from(hex: Palette.listColorsHex[index])
                    dismiss()
                } label: {
                    ZStack {
                        Circle().fill(color)
                        if selection == ARGB.from(hex: Palette.listColorsHex[index]) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

/// About box (Help ▸ About).
struct AboutSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 44))
                .foregroundStyle(state.theme.accent)
            Text("Taskly v\(AppVersion.current)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.theme.onSurface)
            Text("© 2026 Taskly Team")
                .font(.system(size: 12))
                .foregroundStyle(state.theme.secondaryText)
            Text(state.t("aboutContent"))
                .font(.system(size: 12))
                .foregroundStyle(state.theme.secondaryText)
                .multilineTextAlignment(.center)
            Button(state.t("dialogConfirm")) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(state.theme.accent)
        }
        .padding(28)
        .frame(width: 320)
        .background(state.theme.background)
    }
}
