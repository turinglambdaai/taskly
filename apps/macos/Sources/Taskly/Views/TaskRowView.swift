import SwiftUI

/// One task row: circular checkbox, text (+meta), info button.
/// Double-click enters inline edit; context menu toggles/deletes/moves.
struct TaskRowView: View {
    @Environment(AppState.self) private var state
    let task: TaskItem

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editingContent
            } else {
                displayContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.clear))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu { contextMenu }
    }

    // MARK: - Display mode

    private var displayContent: some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox

            VStack(alignment: .leading, spacing: 4) {
                Text(task.text)
                    .font(.system(size: 14))
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? state.theme.tertiaryText : state.theme.onSurface)
                    .lineLimit(3)

                if hasMeta {
                    metaLine
                }
            }

            Spacer(minLength: 8)

            Button {
                state.taskDetailContext = task
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(state.theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .help(state.t("tooltipTaskEdit"))
        }
        .onTapGesture(count: 2) {
            beginEditing()
        }
    }

    private var hasMeta: Bool {
        task.dueDate != nil || (task.notes?.isEmpty == false)
    }

    private var metaLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            if task.dueDate != nil {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("🗓").font(.system(size: 11))
                        Text(displayDate)
                            .font(.system(size: 12))
                    }
                    if let time = task.dueTime, !time.isEmpty {
                        HStack(spacing: 4) {
                            Text("🕐").font(.system(size: 11))
                            Text(time).font(.system(size: 12))
                        }
                    }
                }
                .foregroundStyle(state.theme.secondaryText)
            }
            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var displayDate: String {
        let parser = DateParser()
        return parser.formatDateOnlyForDisplay(
            task.dueDate,
            todayLabel: state.t("navToday"),
            tomorrowLabel: state.t("navPlanned") == "计划" ? "明天" : "Tomorrow",
            yesterdayLabel: state.t("navPlanned") == "计划" ? "昨天" : "Yesterday")
    }

    private var checkbox: some View {
        Button {
            state.toggleCompleted(task)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(
                        task.completed ? state.theme.accent : state.theme.tertiaryText,
                        lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if task.completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(state.theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit mode

    private var editingContent: some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox
            VStack(alignment: .leading, spacing: 8) {
                TextField("", text: $editText)
                    .font(.system(size: 14))
                    .focused($editFocused)
                    .onSubmit(saveEditing)
                    .onExitCommand(perform: cancelEditing)
                    .textFieldStyle(.plain)

                HStack(spacing: 12) {
                    // Native additions: inline date/time steppers (write-through).
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { dateBindingValue },
                            set: { newValue in
                                var updated = task
                                updated.dueDate = DateParser.string(from: newValue, format: "yyyy-MM-dd")
                                state.saveTask(updated)
                            }),
                        in: Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!
                            ... Calendar.current.date(from: DateComponents(year: 2100, month: 12, day: 31))!,
                        displayedComponents: .date)
                    .labelsHidden()
                    .font(.system(size: 12))

                    if task.dueDate != nil {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { timeBindingValue },
                                set: { newValue in
                                    var updated = task
                                    updated.dueTime = DateParser.string(from: newValue, format: "HH:mm")
                                    state.saveTask(updated)
                                }),
                            displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .font(.system(size: 12))

                        Button(state.t("dialogClear")) {
                            var updated = task
                            updated.dueTime = nil
                            state.saveTask(updated)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.link)
                    } else {
                        Button(state.t("labelAddDate")) {
                            var updated = task
                            updated.dueDate = DateParser.string(from: Date(), format: "yyyy-MM-dd")
                            state.saveTask(updated)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.link)
                    }
                }

                TextField(
                    state.t("hintAddNotes"),
                    text: Binding(
                        get: { task.notes ?? "" },
                        set: { newValue in
                            var updated = task
                            updated.notes = newValue.isEmpty ? nil : newValue
                            // Notes write through on submit only; keep local.
                            editNotes = newValue.isEmpty ? nil : newValue
                        }))
                    .font(.system(size: 12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveEditing() }
            }
            Spacer(minLength: 8)
        }
        .onAppear {
            editText = task.text
            editNotes = task.notes
            editFocused = true
        }
        .onDisappear {
            saveEditing()
        }
    }

    @State private var editNotes: String?

    private var dateBindingValue: Date {
        if let dueDate = task.dueDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dueDate) {
                return date
            }
        }
        return Date()
    }

    private var timeBindingValue: Date {
        let calendar = Calendar.current
        let now = Date()
        if let dueTime = task.dueTime {
            let parts = dueTime.split(separator: ":")
            if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
                return calendar.date(
                    bySettingHour: min(hour, 23), minute: min(minute, 59), second: 0, of: now) ?? now
            }
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
    }

    private func beginEditing() {
        editText = task.text
        editNotes = task.notes
        isEditing = true
    }

    private func saveEditing() {
        guard isEditing else { return }
        isEditing = false
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        let notesChanged = (editNotes ?? "") != (task.notes ?? "")
        if trimmed.isEmpty || (trimmed == task.text && !notesChanged) {
            return
        }
        var updated = task
        updated.text = trimmed
        updated.notes = (editNotes?.isEmpty ?? true) ? nil : editNotes
        state.saveTask(updated)
    }

    private func cancelEditing() {
        isEditing = false
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button(state.t("menuToggleCompleted")) {
            state.toggleCompleted(task)
        }
        Button(state.t("taskDelete"), role: .destructive) {
            state.deleteTask(task)
        }

        let otherLists = state.lists.filter { $0.id != task.listId }
        if !otherLists.isEmpty {
            Menu(state.t("menuMoveToList")) {
                ForEach(otherLists) { list in
                    Button("\((list.icon ?? "📁")) \(list.name)") {
                        state.moveTask(task, to: list)
                    }
                }
            }
        }
    }
}
