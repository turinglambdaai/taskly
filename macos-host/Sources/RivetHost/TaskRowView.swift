import SwiftUI

/// One task row. Interactions mirror macOS Reminders:
/// - hover: quiet row fill + quick-schedule chips (今天/明天) + info reveal
/// - click selects (⌘ toggles, ⇧ extends — see AppModel.clickSelectTask)
/// - ⓘ (or Return / double-click) expands the row in place for editing —
///   no modal sheet; edits commit when the row collapses
/// - context menu: complete · schedule · details · custom date · move · delete
struct TaskRowView: View {
    @Environment(AppModel.self) private var model
    let task: Task
    /// Position in the current view — the ⇧-range and ↑/↓ anchor.
    let index: Int

    @State private var isHovering = false
    // Inline-expansion buffers; committed when the row collapses.
    @State private var expandedText = ""
    @State private var expandedNotes: String?
    @State private var expandedDueDate: String?
    @State private var expandedDueTime: String?
    @State private var showDatePopover = false
    @State private var showTimePopover = false
    @FocusState private var titleFocused: Bool

    private var isExpanded: Bool { model.expandedTaskID == task.id }
    private var isSelected: Bool { model.selectedTaskIDs.contains(task.id) }
    private var listAccent: Color { model.listColor(for: task) }

    var body: some View {
        Group {
            if isExpanded {
                expandedContent
            } else {
                displayContent
            }
        }
        // Completion transition: strikethrough/color crossfade with the
        // checkbox pop (parity with the Windows AddDelete/pop pair).
        .animation(.easeOut(duration: 0.15), value: task.completed)
        // Padding first so the 44pt bound is the row's TOTAL height
        // (DESIGN-TOKENS task row) — a single-line task stays Reminders-dense.
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(minHeight: 44, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowFill))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) {
            expand()
        }
        .simultaneousGesture(SpatialTapGesture().onEnded { _ in
            // SpatialTapGesture carries no modifier info; the flagsChanged
            // monitor keeps the live state on AppModel instead.
            let flags = model.lastModifierFlags
            model.clickSelectTask(
                task.id, index: index,
                command: flags.contains(.command),
                shift: flags.contains(.shift))
        })
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu { contextMenu }
    }

    /// Selection fill first, hover fill only when not selected.
    private var rowFill: Color {
        if isSelected { return model.theme.selection }
        if isHovering { return model.theme.hover }
        return Color.clear
    }

    // MARK: - Display mode

    private var displayContent: some View {
        HStack(alignment: .center, spacing: 12) {
            checkbox

            VStack(alignment: .leading, spacing: 4) {
                Text(task.text)
                    .font(.system(size: 14))
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? model.theme.tertiaryText : model.theme.onSurface)
                    .lineLimit(3)

                if hasMeta {
                    metaLine
                }
            }

            Spacer(minLength: 8)

            // Quick-schedule chips surface on hover (Reminders signature).
            if isHovering && !task.completed {
                scheduleChips
            }

            Button {
                expand()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(model.theme.tertiaryText)
                    // 45% at rest, full on row hover (DESIGN-TOKENS task row).
                    .opacity(isHovering ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .help(model.t("contextMenuDetails"))
        }
    }

    /// 今天 / 明天 one-click rescheduling, revealed on hover.
    private var scheduleChips: some View {
        HStack(spacing: 4) {
            quickChip(model.t("navToday")) {
                setDue(Date())
            }
            quickChip(model.t("dateTomorrow")) {
                setDue(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
            }
        }
        .transition(.opacity)
    }

    private func quickChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(model.theme.secondaryText)
                .background(model.theme.hover, in: Capsule())
                .overlay(Capsule().strokeBorder(model.theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var hasMeta: Bool {
        task.due_date != nil || (task.notes?.isEmpty == false)
    }

    /// In views spanning several lists (today / planned / all / completed),
    /// the meta line leads with the owning list (list-colored dot + name).
    private var showsListName: Bool {
        model.currentView.listId == nil
    }

    private var metaLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                if showsListName, let listName = task.list_name, !listName.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(listAccent)
                            .frame(width: 7, height: 7)
                        Text(listName)
                            .font(.system(size: 12))
                            .foregroundStyle(model.theme.secondaryText)
                    }
                }
                if task.due_date != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text(displayDate)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(dueDateColor)
                }
                if let time = task.due_time, !time.isEmpty {
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
                    .foregroundStyle(model.theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var displayDate: String {
        guard let dateOnly = DateParser.extractDateOnly(task.due_date), !dateOnly.isEmpty else {
            return ""
        }
        // Relative word (今天/明天/昨天) first.
        let relative = DateParser().formatDateOnlyForDisplay(
            task.due_date,
            todayLabel: model.t("navToday"),
            tomorrowLabel: model.t("dateTomorrow"),
            yesterdayLabel: model.t("dateYesterday"))
        if relative != dateOnly {
            return relative
        }
        // Same-year dates render as "9月30日" / "Sep 30" (short month names);
        // cross-year falls back to the ISO key.
        guard let date = DateParser.strictDate(from: dateOnly) else { return dateOnly }
        let cal = Calendar.current
        guard cal.component(.year, from: date) == cal.component(.year, from: Date()) else {
            return dateOnly
        }
        let day = cal.component(.day, from: date)
        if model.i18n.language == "zh" {
            return "\(cal.component(.month, from: date))月\(day)日"
        }
        // en: "Sep 27" via a cached locale formatter.
        let formatter = Self.shortMonthFormatter
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }

    private var checkbox: some View {
        Button {
            model.toggleCompleted(task)
        } label: {
            ZStack {
                // 20px ring in the task's list color; completed = list-color
                // fill with a white check (DESIGN-TOKENS checkbox size).
                Circle()
                    .fill(task.completed ? listAccent : Color.clear)
                    .frame(width: 20, height: 20)
                    .animation(.easeOut(duration: 0.15), value: task.completed)
                Circle()
                    .strokeBorder(listAccent, lineWidth: 1.5)
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
            return model.theme.secondaryText
        }
        guard let day = dueDay else {
            return model.theme.secondaryText
        }
        let today = Calendar.current.startOfDay(for: Date())
        if day < today { return Palette.danger }
        if day == today { return model.theme.accent }
        return model.theme.secondaryText
    }

    /// Start-of-day of the task's due date, or nil when absent/unparseable.
    private var dueDay: Date? {
        guard let dateOnly = DateParser.extractDateOnly(task.due_date),
              !dateOnly.isEmpty,
              let date = DateParser.strictDate(from: dateOnly)
        else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    @MainActor private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Reschedule: setting a date keeps the existing time; clearing the
    /// date clears the time with it.
    private func setDue(_ date: Date?, on target: Task? = nil) {
        let base = target ?? task
        model.saveTask(withSchedule(
            base,
            date: date.map { DateParser.string(from: $0, format: "yyyy-MM-dd") },
            time: (date == nil) ? nil : base.due_time))
    }

    private func withSchedule(_ base: Task, date: String?, time: String?) -> Task {
        Task(
            id: base.id, list_id: base.list_id, list_name: base.list_name, text: base.text,
            completed: base.completed, due_date: date, due_time: time,
            notes: base.notes, created_at: base.created_at)
    }

    // MARK: - Inline expansion (ⓘ / Return / double-click)

    private func expand() {
        model.expandedTaskID = task.id
        model.selectedTaskIDs = [task.id]
        model.selectionAnchorIndex = index
    }

    /// Writes buffered edits back. Collapse (click elsewhere / Esc / Return)
    /// and disappear both route here, so edits are never lost.
    private func commitExpansion() {
        guard isExpanded else { return }
        let trimmed = expandedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = Task(
            id: task.id, list_id: task.list_id, list_name: task.list_name,
            text: trimmed.isEmpty ? task.text : trimmed,
            completed: task.completed,
            due_date: expandedDueDate,
            due_time: (expandedDueDate == nil) ? nil : expandedDueTime,
            notes: (expandedNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
                ? nil : expandedNotes,
            created_at: task.created_at)
        if updated != task {
            model.saveTask(updated)
        }
    }

    private func collapse() {
        commitExpansion()
        model.expandedTaskID = nil
        titleFocused = false
    }

    private var expandedContent: some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox

            VStack(alignment: .leading, spacing: 10) {
                // The task text is the title: 15px semibold, borderless.
                TextField("", text: $expandedText, axis: .vertical)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.theme.onSurface)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit { collapse() }

                // Date + time chips (accent border when set, hollow when empty).
                HStack(spacing: 8) {
                    expandedDateChip
                    if expandedDueDate != nil {
                        expandedTimeChip
                    }
                }

                Divider().overlay(model.theme.divider)

                // Notes: 13px borderless multiline, tertiary placeholder.
                TextField(
                    model.t("hintAddNotes"),
                    text: Binding(
                        get: { expandedNotes ?? "" },
                        set: { expandedNotes = $0.isEmpty ? nil : $0 }),
                    axis: .vertical)
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.onSurface)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)
            }

            Spacer(minLength: 8)

            Button {
                collapse()
            } label: {
                Image(systemName: "chevron.up.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(model.theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .help(model.t("contextMenuDetails"))
        }
        .padding(.vertical, 2)
        .onAppear {
            // Buffer init lives here (not in expand()) so every entry path —
            // ⓘ, Return, double-click — starts from the task's real values.
            expandedText = task.text
            expandedNotes = task.notes
            expandedDueDate = task.due_date
            expandedDueTime = task.due_time
            titleFocused = true
        }
        .onDisappear {
            commitExpansion()
        }
    }

    private var expandedDateChip: some View {
        EditChip(
            icon: "calendar",
            label: expandedDueDate.map { Self.dateText($0) } ?? "+ \(model.t("labelAddDate"))",
            active: expandedDueDate != nil,
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
                    Button(model.t("dialogClear")) {
                        expandedDueDate = nil
                        expandedDueTime = nil
                        showDatePopover = false
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(model.theme.secondaryText)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var expandedTimeChip: some View {
        EditChip(
            icon: "clock",
            label: expandedDueTime ?? "+ \(model.t("labelAddTime"))",
            active: expandedDueTime != nil,
            isActive: $showTimePopover) {
            showDatePopover = false
        } content: {
            VStack(spacing: 10) {
                TimePickerControl(selection: timeBinding)
                HStack {
                    Spacer()
                    Button(model.t("dialogClear")) {
                        expandedDueTime = nil
                        showTimePopover = false
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(model.theme.secondaryText)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { DateParser.asDate(expandedDueDate) },
            set: { expandedDueDate = DateParser.string(from: $0, format: "yyyy-MM-dd") })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                if let expandedDueTime {
                    return DateParser.asTime(expandedDueTime)
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
            set: { expandedDueTime = DateParser.string(from: $0, format: "HH:mm") })
    }

    static let dateRange: ClosedRange<Date> = {
        Calendar.current.date(from: DateComponents(year: DateParser.minYear, month: 1, day: 1))!
            ... Calendar.current.date(from: DateComponents(year: DateParser.maxYear, month: 12, day: 31))!
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

    // MARK: - Context menu

    /// Right-clicked a row inside the active selection → the action applies
    /// to the whole selection; otherwise just this row.
    private var actionTargets: [Task] {
        model.selectedTaskIDs.contains(task.id)
            ? model.tasks.filter { model.selectedTaskIDs.contains($0.id) }
            : [task]
    }

    @ViewBuilder
    private var contextMenu: some View {
        let targets = actionTargets

        Button(model.t("menuToggleCompleted")) {
            for target in targets { model.toggleCompleted(target) }
        }

        // Date quick actions: reschedule in one click.
        Button(model.t("navToday")) {
            for target in targets { setDue(Date(), on: target) }
        }
        Button(model.t("dateTomorrow")) {
            for target in targets {
                setDue(Calendar.current.date(byAdding: .day, value: 1, to: Date()), on: target)
            }
        }
        Button(model.t("contextMenuCustomDate")) {
            expand()
        }
        Button(model.t("dialogClear")) {
            for target in targets {
                model.saveTask(withSchedule(target, date: nil, time: nil))
            }
        }

        Divider()

        Button(model.t("contextMenuDetails")) {
            expand()
        }

        Divider()

        Button(model.t("taskDelete"), role: .destructive) {
            model.deleteTasks(targets)
        }

        let otherLists = model.lists.filter { $0.id != task.list_id }
        if !otherLists.isEmpty {
            Menu(model.t("menuMoveToList")) {
                ForEach(otherLists, id: \.id) { list in
                    Button("\(list.icon ?? "📁") \(list.name)") {
                        for target in targets { model.moveTask(target, to: list) }
                    }
                }
            }
        }
    }
}

/// Rounded chip: hollow (divider border, tertiary text) when unset;
/// accent border + tint when set. Clicking toggles a popover.
struct EditChip<PopoverContent: View>: View {
    @Environment(AppModel.self) private var model
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
            .foregroundStyle(active ? model.theme.accent : model.theme.tertiaryText)
            .background(
                active ? model.theme.accent.opacity(0.08) : Color.clear,
                in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    active ? model.theme.accent : model.theme.divider,
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
struct TimePickerControl: View {
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
