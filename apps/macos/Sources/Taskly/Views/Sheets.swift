import AppKit
import SwiftUI

/// Immersive task editor (DESIGN-TOKENS "Task detail dialog"): no dialog
/// title — the task text is the title; borderless fields; date/time as
/// rounded chips (accent border when set, hollow "add" chips when empty);
/// bottom row = red text Delete · spacer · plain Cancel · accent-filled Save.
struct TaskDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let original: TaskItem
    @State private var text: String
    @State private var notes: String
    @State private var dueDate: String?
    @State private var dueTime: String?
    @State private var confirmDelete = false
    @State private var showDatePopover = false
    @State private var showTimePopover = false
    @FocusState private var titleFocused: Bool

    init(task: TaskItem) {
        original = task
        _text = State(initialValue: task.text)
        _notes = State(initialValue: task.notes ?? "")
        _dueDate = State(initialValue: task.dueDate)
        _dueTime = State(initialValue: task.dueTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The task text is the title: 18px semibold, borderless.
            TextField("", text: $text, axis: .vertical)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(state.theme.onSurface)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused($titleFocused)

            // Date + time chips (accent border when set, hollow when empty).
            HStack(spacing: 8) {
                dateChip
                if dueDate != nil {
                    timeChip
                }
            }

            Divider().overlay(state.theme.divider)

            // Notes: 13px borderless multiline, tertiary placeholder.
            TextField(state.t("hintAddNotes"), text: $notes, axis: .vertical)
                .font(.system(size: 13))
                .foregroundStyle(state.theme.onSurface)
                .lineLimit(2...6)
                .textFieldStyle(.plain)

            Spacer(minLength: 0)

            // Bottom row: red text delete · spacer · plain cancel · filled save.
            HStack(spacing: 12) {
                Button {
                    confirmDelete = true
                } label: {
                    Text(state.t("taskDelete"))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.danger)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: [.command])

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
                    save()
                } label: {
                    Text(state.t("dialogSave"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(state.theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(state.theme.background)
        .onAppear { titleFocused = true }
        .onExitCommand { dismiss() }
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

    // MARK: - Chips

    private var dateChip: some View {
        EditChip(
            icon: "calendar",
            label: dueDate.map { Self.dateText($0) } ?? "+ \(state.t("labelAddDate"))",
            active: dueDate != nil,
            isActive: $showDatePopover) {
            showTimePopover = false
        } content: {
            VStack(spacing: 10) {
                DatePicker(
                    "", selection: dateBinding,
                    in: Self.dateRange,
                    displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 300)
                HStack {
                    Spacer()
                    Button(state.t("dialogClear")) {
                        // Clearing the date clears the time with it.
                        dueDate = nil
                        dueTime = nil
                        showDatePopover = false
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.secondaryText)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var timeChip: some View {
        EditChip(
            icon: "clock",
            label: dueTime.map { $0 } ?? "+ \(state.t("labelAddTime"))",
            active: dueTime != nil,
            isActive: $showTimePopover) {
            showDatePopover = false
        } content: {
            VStack(spacing: 10) {
                TimePickerControl(selection: timeBinding)
                HStack {
                    Spacer()
                    Button(state.t("dialogClear")) {
                        dueTime = nil
                        showTimePopover = false
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.secondaryText)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = original
        updated.text = trimmed
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        updated.dueDate = dueDate
        // A time without a date is not representable; drop it with the date.
        updated.dueTime = (dueDate == nil) ? nil : dueTime
        state.saveTask(updated)
        dismiss()
    }

    // MARK: - Bindings / formatting

    private var dateBinding: Binding<Date> {
        Binding(
            get: { DateParser.asDate(dueDate) },
            set: { dueDate = DateParser.string(from: $0, format: "yyyy-MM-dd") })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                if let dueTime {
                    return DateParser.asTime(dueTime)
                }
                // Adding a time: start at the current minute rounded to the
                // nearest 5 (PRODUCT-SPEC §7).
                let now = Date()
                let calendar = Calendar.current
                let minute = calendar.component(.minute, from: now)
                let rounded = min(((minute + 2) / 5) * 5, 55)
                return calendar.date(
                    bySettingHour: calendar.component(.hour, from: now),
                    minute: rounded, second: 0, of: now) ?? now
            },
            set: { dueTime = DateParser.string(from: $0, format: "HH:mm") })
    }

    static let dateRange: ClosedRange<Date> = {
        Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!
            ... Calendar.current.date(from: DateComponents(year: 2100, month: 12, day: 31))!
    }()

    /// "M月d日" (zh) / "MMM d" (en) for the chip label.
    static func dateText(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let out = DateFormatter()
        out.locale = Locale.current
        out.setLocalizedDateFormatFromTemplate("MMMd")
        return out.string(from: date)
    }
}

/// Rounded chip used by the editor: hollow (divider border, tertiary text)
/// when unset; accent border + tint when set. Clicking toggles a popover.
private struct EditChip<PopoverContent: View>: View {
    @Environment(AppState.self) private var state
    let icon: String
    let label: String
    let active: Bool
    @Binding var isActive: Bool
    /// Opens with this chip, closing any sibling popover.
    let onOpen: () -> Void
    @ViewBuilder let content: PopoverContent

    var body: some View {
        Button {
            if isActive {
                isActive = false
            } else {
                onOpen()
                isActive = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(active ? state.theme.accent : state.theme.tertiaryText)
            .background(
                active ? state.theme.accent.opacity(0.08) : Color.clear,
                in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    active ? state.theme.accent : state.theme.divider,
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isActive, arrowEdge: .bottom) {
            content
        }
    }
}

/// HH:mm picker with the contract's 5-minute steps (PRODUCT-SPEC §7):
/// hour 00-23 dropdown + minute 00/05/…/55 dropdown.
private struct TimePickerControl: View {
    @Binding var selection: Date
    @State private var hour: Int
    @State private var minute: Int

    init(selection: Binding<Date>) {
        _selection = selection
        let calendar = Calendar.current
        _hour = State(initialValue: calendar.component(.hour, from: selection.wrappedValue))
        let rawMinute = calendar.component(.minute, from: selection.wrappedValue)
        _minute = State(initialValue: (rawMinute / 5) * 5)
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $hour) {
                ForEach(0..<24, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 78)

            Text(":")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Picker("", selection: $minute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 78)
        }
        .onChange(of: hour) { _, _ in commit() }
        .onChange(of: minute) { _, _ in commit() }
    }

    private func commit() {
        selection = Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: selection) ?? selection
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
