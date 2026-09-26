import SwiftUI

/// Calendar view (PRODUCT-SPEC §4b): compact month grid on top, tasks
/// grouped by day below. Seeing and jumping, not editing — rows are the
/// standard §5 rows.
struct CalendarPaneView: View {
    @Environment(AppState.self) private var state

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            monthNav
            weekdayHeader
            monthGrid
            Divider().overlay(state.theme.divider)
            timeLine
        }
    }

    // MARK: - Month navigation

    private var monthNav: some View {
        HStack(spacing: 8) {
            Button {
                state.navigateCalendarMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.theme.secondaryText)
            }
            .buttonStyle(.plain)

            Text(state.calendarMonthTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(state.theme.onSurface)
                .frame(maxWidth: .infinity)

            Button(state.t("calTodayButton")) {
                state.goCalendarToday()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(state.theme.accent)

            Button {
                state.navigateCalendarMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(state.calendarWeekdayHeader.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Month grid (6 rows, adjacent-month cells clickable)

    private var monthGrid: some View {
        let first = firstOfMonth
        let dow = Calendar.current.component(.weekday, from: first)
        // Week start follows the language (§4b): zh Monday-first, en
        // Sunday-first. weekday: Sunday=1 … Saturday=7.
        let mondayFirst = state.config.language == "zh"
        let col = mondayFirst ? (dow + 5) % 7 : dow - 1
        let start = Calendar.current.date(byAdding: .day, value: -col, to: first) ?? first
        let todayKey = DateParser.string(from: Date(), format: "yyyy-MM-dd")

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<42, id: \.self) { index in
                let day = Calendar.current.date(byAdding: .day, value: index, to: start) ?? start
                DayCell(day: day, todayKey: todayKey)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var firstOfMonth: Date {
        var components = DateComponents()
        components.year = state.calendarYear
        components.month = state.calendarMonth
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Day-group time line

    private var timeLine: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if state.calendarRows.isEmpty {
                    VStack(spacing: 8) {
                        Text("✓")
                            .font(.system(size: 36))
                            .opacity(0.35)
                        Text(state.t("taskListEmpty"))
                            .font(.system(size: 14))
                            .foregroundStyle(state.theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(state.calendarRows) { row in
                            switch row {
                            case .header(let header):
                                CalendarHeaderView(header: header)
                                    .id(row.id)
                            case .task(let task):
                                TaskRowView(task: task)
                                    .id(row.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: state.calendarSelectedDate) { _, newValue in
                guard let key = newValue,
                      let row = state.calendarRows.first(where: { $0.header?.dateKey == key })
                else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(row.id, anchor: .top)
                }
            }
        }
    }
}

/// Day header: `9月26日 · 周五` / `Friday, September 26`, count right,
/// today's header in accent (§4b).
private struct CalendarHeaderView: View {
    @Environment(AppState.self) private var state
    let header: CalendarSectionHeader

    var body: some View {
        HStack {
            Text(header.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(header.isToday ? state.theme.accent : state.theme.onSurface)
                .lineLimit(1)
            Spacer()
            if header.count > 0 {
                Text("\(header.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.secondaryText)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }
}

/// One month-grid day cell: day number, up to three accent dots for
/// incomplete tasks, today in accent, selected day in an accent ring (§4b).
private struct DayCell: View {
    @Environment(AppState.self) private var state
    let day: Date
    let todayKey: String

    var body: some View {
        let key = DateParser.string(from: day, format: "yyyy-MM-dd")
        let inMonth = Calendar.current.component(.month, from: day) == state.calendarMonth
        let isToday = key == todayKey
        let isSelected = state.calendarSelectedDate == key
        let dots = min(state.calendarDayCounts[key] ?? 0, 3)

        Button {
            state.selectCalendarDate(key)
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(
                        isToday ? state.theme.accent
                            : (inMonth ? state.theme.onSurface : state.theme.tertiaryText))
                HStack(spacing: 3) {
                    ForEach(0..<dots, id: \.self) { _ in
                        Circle()
                            .fill(state.theme.accent)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? state.theme.selection : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? state.theme.accent : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
