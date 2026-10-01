import Foundation

/// Natural-language date/time parser. Faithful port of the canonical
/// grammar in racket/taskly/date-parser.rkt (CLI-SPEC `--due`).
///
/// Supported shorthands:
///   +10m (10 min), +2h, +1d, +1w, +1M (1 month = 30 days)
///   @now, @10am, @2pm, @10:30am, @22:30, @10am tomorrow/tmw, @8pm mon..sun
///   absolute: yyyy-MM-dd / yyyy/MM/dd / MM/dd/yyyy / dd/MM/yyyy
///   words: today → +0d, tomorrow/tmw → +1d, tonight → @20:00
///   extractTimeCommand: pulls a trailing time command out of text
///     ("买牛奶 @10am" → ("买牛奶", "@10am"))
///
/// Parse results are 'yyyy-MM-dd HH:mm:ss'; date-only results 'yyyy-MM-dd'.
/// NOTE: unit case matters — m = minutes, M = month(30 days).
/// MainActor-confined: every call site (quick-add, previews, rows) is UI,
/// and the cached DateFormatter requires it.
@MainActor
struct DateParser {
    init() {}

    // Validation bounds (PRODUCT-SPEC §10).
    static let minYear = 1900
    static let maxYear = 2100

    // Relative: +digits + unit (digits optional, default 1)
    private static let relativeRegex = try! NSRegularExpression(pattern: #"^(\d*)([mhdwM])$"#)
    // Time: @now / @10 / @10am / @10:30 / @10:30am / @22:30 / @22:30pm
    private static let timeRegex = try! NSRegularExpression(
        pattern: #"^(\d{1,2})(?::(\d{2}))?(am|pm)?$"#,
        options: [.caseInsensitive])
    // Trailing relative command: +10m / +2h …
    private static let extractRelativeRegex = try! NSRegularExpression(
        pattern: #"(?:^|\s)(\+\d+[mhdwM])(?:\s|$)"#)
    // Trailing @ command (with optional day-modifier suffix)
    private static let extractAtRegex = try! NSRegularExpression(
        pattern: #"@(?:now|\d{1,2}(?::\d{2})?(?:am|pm)?)(?:\s+(?:tomorrow|tmw|mon|tue|wed|thu|fri|sat|sun))?$"#,
        options: [.caseInsensitive])

    /// Parses input into 'yyyy-MM-dd HH:mm:ss' (or 'yyyy-MM-dd' for absolute
    /// dates). Returns nil when unparseable.
    func parse(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if s.hasPrefix("+") { return parseRelativeDate(s) }
        if s.hasPrefix("@") { return parseAtTime(String(s.dropFirst())) }
        return parseAbsoluteDate(s)
    }

    /// CLI-facing shape: canonical due_date plus due_time, where a
    /// pure-date intent (+Nd/+Nw/+NM, absolute dates, today/tomorrow)
    /// intentionally returns a nil time. Nil when unparseable.
    func parseDueExpression(_ input: String) -> (dueDate: String, dueTime: String?)? {
        let original = input.trimmingCharacters(in: .whitespaces)
        let normalized: String
        if original.caseInsensitiveCompare("today") == .orderedSame {
            normalized = "+0d"
        } else if original.caseInsensitiveCompare("tomorrow") == .orderedSame
            || original.caseInsensitiveCompare("tmw") == .orderedSame {
            normalized = "+1d"
        } else if original.caseInsensitiveCompare("tonight") == .orderedSame {
            normalized = "@20:00"
        } else {
            normalized = original
        }

        guard let parsed = parse(normalized) else { return nil }
        let dateOnly = DateParser.extractDateOnly(parsed) ?? parsed
        let isPureDate = ["today", "tomorrow", "tmw"].contains(original.lowercased())
            || (normalized.hasPrefix("+") && ["d", "w", "M"].contains(String(normalized.dropFirst().suffix(1))))
            || parsed.count == 10
        return (dateOnly, isPureDate ? nil : DateParser.extractTimeOnly(parsed))
    }

    /// Extracts a trailing time command from text. `timeCommand` is nil when
    /// nothing was extracted.
    func extractTimeCommand(_ input: String) -> (text: String, timeCommand: String?) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (input, nil)
        }

        var text = input
        var command: String?

        // Trailing @ command first
        if Self.extractAtRegex.firstMatch(in: text, range: text.fullRange) != nil {
            if let atIndex = text.firstIndex(of: "@") {
                command = String(text[atIndex...]).trimmingCharacters(in: .whitespaces)
                text = String(text[..<atIndex]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r"))
            }
        }

        // Then trailing relative command
        if let m = Self.extractRelativeRegex.firstMatch(in: text, range: text.fullRange) {
            command = String(text[Range(m.range(at: 1), in: text)!])
            text = text.replacingCharacters(in: Range(m.range, in: text)!, with: "")
                .trimmingCharacters(in: .whitespaces)
        }

        return (text.trimmingCharacters(in: .whitespaces), command)
    }

    // ---------------- relative +N<unit> ----------------

    private func parseRelativeDate(_ input: String) -> String? {
        let body = String(input.dropFirst())
        guard let m = Self.relativeRegex.firstMatch(in: body, range: body.fullRange) else {
            return nil
        }

        let numStr = String(body[Range(m.range(at: 1), in: body)!])
        let amount = numStr.isEmpty ? 1 : (Int(numStr) ?? 0)
        let unit = String(body[Range(m.range(at: 2), in: body)!])

        let now = Date()
        let calendar = Calendar.current
        let result: Date?
        switch unit {
        case "m": result = calendar.date(byAdding: .minute, value: amount, to: now)
        case "h": result = calendar.date(byAdding: .hour, value: amount, to: now)
        case "d": result = calendar.date(byAdding: .day, value: amount, to: now)
        case "w": result = calendar.date(byAdding: .day, value: amount * 7, to: now)
        case "M": result = calendar.date(byAdding: .day, value: amount * 30, to: now)
        default: result = nil
        }

        return result.map { Self.formatFull($0) }
    }

    // ---------------- @time ----------------

    private func parseAtTime(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased() == "now" {
            return Self.formatFull(Date())
        }

        // Split time body from optional day modifier (tomorrow/tmw/weekday)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let timePart = parts.count > 0 ? String(parts[0]) : ""
        let modifier = parts.count > 1 ? String(parts[1]) : nil

        guard let m = Self.timeRegex.firstMatch(in: timePart, range: timePart.fullRange) else {
            return nil
        }

        var hour = Int(timePart[Range(m.range(at: 1), in: timePart)!]) ?? 0
        let min = m.range(at: 2).location != NSNotFound
            ? (Int(timePart[Range(m.range(at: 2), in: timePart)!]) ?? 0) : 0
        let ampm = m.range(at: 3).location != NSNotFound
            ? timePart[Range(m.range(at: 3), in: timePart)!].lowercased() : nil

        if ampm == "am" {
            if hour == 12 { hour = 0 }
        } else if ampm == "pm" {
            if hour < 12 { hour += 12 }
        }

        guard (0...23).contains(hour), (0...59).contains(min) else { return nil }

        let calendar = Calendar.current
        let now = Date()
        var date = calendar.startOfDay(for: now)
            .addingTimeInterval(TimeInterval(hour * 3600 + min * 60))

        if let modifier, !modifier.isEmpty {
            date = applyDayModifier(date, modifier)
        } else if date < now {
            // Past time with no modifier rolls over to tomorrow.
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return Self.formatFull(date)
    }

    private func applyDayModifier(_ date: Date, _ modifier: String) -> Date {
        let m = modifier.lowercased()
        if m == "tomorrow" || m == "tmw" {
            return Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }

        // Weekday: next occurrence (next week if today or already passed).
        let targetDay: Int?
        switch m {
        case "sun": targetDay = 1
        case "mon": targetDay = 2
        case "tue": targetDay = 3
        case "wed": targetDay = 4
        case "thu": targetDay = 5
        case "fri": targetDay = 6
        case "sat": targetDay = 7
        default: targetDay = nil
        }

        if let td = targetDay {
            let current = Calendar.current.component(.weekday, from: date)
            var diff = (td - current + 7) % 7
            if diff <= 0 { diff += 7 }
            return Calendar.current.date(byAdding: .day, value: diff, to: date) ?? date
        }

        return date
    }

    // ---------------- absolute dates ----------------

    private func parseAbsoluteDate(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespaces)
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "dd/MM/yyyy"]

        for fmt in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = fmt
            formatter.isLenient = false
            if let date = formatter.date(from: s) {
                let year = Calendar.current.component(.year, from: date)
                if year < Self.minYear || year > Self.maxYear {
                    return nil
                }
                return Self.string(from: date, format: "yyyy-MM-dd")
            }
        }

        return nil
    }

    // ---------------- display helpers ----------------

    /// Date part of 'yyyy-MM-dd HH:mm:ss' or 'yyyy-MM-dd' → 'yyyy-MM-dd'.
    static func extractDateOnly(_ dateTimeStr: String?) -> String? {
        guard let dateTimeStr, !dateTimeStr.isEmpty else { return nil }
        return dateTimeStr.count >= 10 ? String(dateTimeStr.prefix(10)) : dateTimeStr
    }

    /// Time part 'HH:mm' of 'yyyy-MM-dd HH:mm:ss'. nil when absent.
    static func extractTimeOnly(_ dateTimeStr: String?) -> String? {
        guard let dateTimeStr, !dateTimeStr.isEmpty, dateTimeStr.count >= 16 else { return nil }
        return String(dateTimeStr.dropFirst(11).prefix(5))
    }

    /// Date-only display (Today/Tomorrow/Yesterday/yyyy-MM-dd).
    func formatDateOnlyForDisplay(
        _ dateStr: String?, todayLabel: String, tomorrowLabel: String, yesterdayLabel: String
    ) -> String {
        guard let dateOnly = Self.extractDateOnly(dateStr), !dateOnly.isEmpty else { return "" }

        if let date = Self.strictDate(from: dateOnly) {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let target = calendar.startOfDay(for: date)
            if target == today { return todayLabel }
            if target == calendar.date(byAdding: .day, value: 1, to: today) { return tomorrowLabel }
            if target == calendar.date(byAdding: .day, value: -1, to: today) { return yesterdayLabel }
        }

        return dateOnly
    }

    /// "yyyy-MM-dd" → Date (today when nil/unparseable), for date pickers.
    static func asDate(_ string: String?) -> Date {
        if let string, let date = strictDate(from: string) {
            return date
        }
        return Date()
    }

    static func strictDate(from dateOnly: String) -> Date? {
        dayFormatter.date(from: dateOnly)
    }

    /// "HH:mm" → Date (09:00 when nil/unparseable), for time pickers.
    static func asTime(_ string: String?) -> Date {
        let calendar = Calendar.current
        let now = Date()
        if let string {
            let parts = string.split(separator: ":")
            if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
               (0...23).contains(hour), (0...59).contains(minute) {
                return calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
            }
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
    }

    // ---------------- formatting utilities ----------------

    /// 'yyyy-MM-dd HH:mm:ss' in the local time zone (parser contract format).
    static func formatFull(_ date: Date) -> String {
        string(from: date, format: "yyyy-MM-dd HH:mm:ss")
    }

    static func string(from date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "yyyy-MM-dd" parse, cached: this sits on the body evaluation path of
    /// every row (DateFormatter construction is expensive).
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension String {
    var fullRange: NSRange { NSRange(startIndex..., in: self) }
}
