import SwiftUI

/// Full task editor (ⓘ button). Save / Delete (confirm) / Cancel.
struct TaskDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let original: TaskItem
    @State private var text: String
    @State private var notes: String
    @State private var dueDate: String?
    @State private var dueTime: String?
    @State private var confirmDelete = false

    init(task: TaskItem) {
        original = task
        _text = State(initialValue: task.text)
        _notes = State(initialValue: task.notes ?? "")
        _dueDate = State(initialValue: task.dueDate)
        _dueTime = State(initialValue: task.dueTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.t("dialogTaskDetail"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.theme.onSurface)

            // Task text
            VStack(alignment: .leading, spacing: 4) {
                Text(state.t("labelTask"))
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.secondaryText)
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(state.theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(state.theme.inputBorder))
            }

            // Notes
            VStack(alignment: .leading, spacing: 4) {
                Text(state.t("labelNotes"))
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.secondaryText)
                TextEditor(text: $notes)
                    .font(.system(size: 13))
                    .frame(height: 72)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(state.theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(state.theme.inputBorder))
            }

            // Date + time
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.t("labelDate"))
                        .font(.system(size: 12))
                        .foregroundStyle(state.theme.secondaryText)
                    HStack {
                        DatePicker(
                            "",
                            selection: dateBinding,
                            in: dateRange,
                            displayedComponents: .date)
                        .labelsHidden()
                        if dueDate != nil {
                            Button(state.t("dialogClear")) { dueDate = nil }
                                .buttonStyle(.link)
                                .font(.system(size: 12))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.t("labelTime"))
                        .font(.system(size: 12))
                        .foregroundStyle(state.theme.secondaryText)
                    HStack {
                        if dueDate != nil {
                            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Button(state.t("dialogClear")) { dueTime = nil }
                                .buttonStyle(.link)
                                .font(.system(size: 12))
                        } else {
                            Text(state.t("labelAddTime"))
                                .font(.system(size: 12))
                                .foregroundStyle(state.theme.tertiaryText)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Buttons
            HStack {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text(state.t("taskDelete"))
                        .foregroundStyle(Palette.danger)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                Spacer()
                Button(state.t("dialogCancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(state.t("dialogSave")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(state.theme.accent)
            }
        }
        .padding(20)
        .frame(width: 450)
        .background(state.theme.background)
        .confirmationDialog(
            state.t("taskDeleteConfirm"),
            isPresented: $confirmDelete,
            titleVisibility: .visible) {
            Button(state.t("taskDelete"), role: .destructive) {
                state.deleteTask(original)
                dismiss()
            }
            Button(state.t("dialogCancel"), role: .cancel) {}
        } message: {
            Text(state.t("taskDeleteConfirmContent"))
        }

    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = original
        updated.text = trimmed
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        updated.dueDate = dueDate
        updated.dueTime = dueTime
        state.saveTask(updated)
        dismiss()
    }

    private var dateRange: ClosedRange<Date> {
        Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!
            ... Calendar.current.date(from: DateComponents(year: 2100, month: 12, day: 31))!
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { DateParser.asDate(dueDate) },
            set: { dueDate = DateParser.string(from: $0, format: "yyyy-MM-dd") })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { DateParser.asTime(dueTime) },
            set: { dueTime = DateParser.string(from: $0, format: "HH:mm") })
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing ? state.t("dialogEditList") : state.t("dialogCreateList"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.theme.onSurface)

            TextField(state.t("dialogInputListName"), text: $name)
                .font(.system(size: 14))
                .textFieldStyle(.roundedBorder)

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
                                .buttonStyle(.link)
                                .font(.system(size: 12))
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
                                .buttonStyle(.link)
                                .font(.system(size: 12))
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(state.t("dialogCancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(state.t("dialogConfirm")) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(state.theme.accent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        }
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
