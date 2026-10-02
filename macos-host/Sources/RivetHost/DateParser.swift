import Foundation

/// Date display/picker helpers shared by the views. Quick-add text
/// splitting and expression parsing live behind the backend
/// parse_quick_add RPC — one grammar on every platform.
/// MainActor-confined: every call site (quick-add, previews, rows) is UI,
/// and the cached DateFormatter requires it.
@MainActor
struct DateParser {
    init() {}

    // Validation bounds (PRODUCT-SPEC §10).
    static let minYear = 1900
    static let maxYear = 2100

    // Relative: +digits + unit (digits optional, default 1)

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
