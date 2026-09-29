import SwiftUI

/// One task row: circular checkbox, text (+meta), info button.
/// Double-click enters inline edit; context menu toggles/deletes/moves.
struct TaskRowView: View {
    @Environment(AppState.self) private var state
    let task: TaskItem

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovering = false
    @FocusState private var editFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editingContent
            } else {
                displayContent
            }
        }
        // Completion transition: strikethrough/color crossfade with the
        // checkbox pop (parity with the Windows AddDelete/pop pair).
        .animation(.easeOut(duration: 0.15), value: task.completed)
        .frame(minHeight: 44, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(state.selectedTaskID == task.id
                    ? state.theme.selection
                    : Color.clear))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            state.selectedTaskID = task.id
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu { contextMenu }
    }

    // MARK: - Display mode

    private var displayContent: some View {
        HStack(alignment: .center, spacing: 12) {
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
                    // 45% at rest, full on row hover (DESIGN-TOKENS task row).
                    .opacity(isHovering ? 1 : 0.45)
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

    /// In views spanning several lists (today / planned / all / completed),
    /// the meta line leads with the owning list (list-colored dot + name).
    private var showsListName: Bool {
        if case .list = state.currentView { return false }
        return true
    }

    private var metaLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                if showsListName, let listName = task.listName, !listName.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(task.listAccentColor)
                            .frame(width: 7, height: 7)
                        Text(listName)
                            .font(.system(size: 12))
                            .foregroundStyle(state.theme.secondaryText)
                    }
                }
                if task.dueDate != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text(displayDate)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(dueDateColor)
                }
                if let time = task.dueTime, !time.isEmpty {
                    // A leading clock glyph only when a time is set.
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(time).font(.system(size: 12))
                    }
                    .foregroundStyle(dueDateColor)
                }
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
        guard let dateOnly = DateParser.extractDateOnly(task.dueDate), !dateOnly.isEmpty else {
            return ""
        }
        // Relative word (今天/明天/昨天) first, mirroring
        // formatDateOnlyForDisplay's logic.
        let relative = DateParser().formatDateOnlyForDisplay(
            task.dueDate,
            todayLabel: state.t("navToday"),
            tomorrowLabel: state.t("dateTomorrow"),
            yesterdayLabel: state.t("dateYesterday"))
        if relative != dateOnly {
            return relative
        }
        // Same-year dates render as "9月30日" / "Sep 30" (short month names);
        // cross-year falls back to the ISO key.
        guard let date = strictDate(from: dateOnly) else { return dateOnly }
        let cal = Calendar.current
        guard cal.component(.year, from: date) == cal.component(.year, from: Date()) else {
            return dateOnly
        }
        let day = cal.component(.day, from: date)
        if state.config.language == "zh" {
            return "\(cal.component(.month, from: date))月\(day)日"
        }
        // en: "Sep 27" via a cached locale formatter.
        let formatter = Self.shortMonthFormatter
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }

    private var checkbox: some View {
        Button {
            state.toggleCompleted(task)
        } label: {
            ZStack {
                // 20px ring in the task's list color; completed = list-color
                // fill with a white check (DESIGN-TOKENS checkbox size).
                Circle()
                    .fill(task.completed ? task.listAccentColor : Color.clear)
                    .frame(width: 20, height: 20)
                    .animation(.easeOut(duration: 0.15), value: task.completed)
                Circle()
                    .strokeBorder(task.listAccentColor, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                if task.completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        // Bounce pops on completion (macOS 14 symbol effect).
                        .symbolEffect(.bounce, value: task.completed)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Due-date semantics (DESIGN-TOKENS)

    /// Meta-line color: overdue incomplete = danger red, due today = accent,
    /// otherwise (or completed) secondary.
    private var dueDateColor: Color {
        if task.completed {
            return state.theme.secondaryText
        }
        guard let day = dueDay else {
            return state.theme.secondaryText
        }
        let today = Calendar.current.startOfDay(for: Date())
        if day < today { return Palette.danger }
        if day == today { return state.theme.accent }
        return state.theme.secondaryText
    }

    /// Start-of-day of the task's due date, or nil when absent/unparseable.
    private var dueDay: Date? {
        guard let dateOnly = DateParser.extractDateOnly(task.dueDate),
              !dateOnly.isEmpty,
              let date = strictDate(from: dateOnly)
        else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    /// "yyyy-MM-dd" parse, cached: this sits on the body evaluation path of
    /// every row (DateFormatter construction is expensive; AppState keeps the
    /// same cached-formatter precedent). MainActor-confined like the view.
    @MainActor private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @MainActor private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private func setDue(_ date: Date?) {
        var updated = task
        updated.dueDate = date.map { DateParser.string(from: $0, format: "yyyy-MM-dd") }
        state.saveTask(updated)
    }

    private func strictDate(from dateOnly: String) -> Date? {
        Self.dayFormatter.date(from: dateOnly)
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

        // Date quick actions: reschedule in one click.
        Button(state.t("navToday")) {
            setDue(Date())
        }
        Button(state.t("dateTomorrow")) {
            setDue(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        }
        Button(state.t("dialogClear")) {
            var cleared = task
            cleared.dueDate = nil
            cleared.dueTime = nil
            state.saveTask(cleared)
        }

        Divider()

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
