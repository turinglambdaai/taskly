// Taskly — natural-language date/time parser (contract: CLI-SPEC.md §--due).
// Faithful port of DateParser.cs:
//   +N{m|h|d|w|M}  (case-sensitive m/M; digits optional = 1; M = 30 days)
//   @now | @H[:MM][am|pm] [tomorrow|tmw|mon..sun]  (past time → tomorrow)
//   yyyy-MM-dd / yyyy/MM/dd / MM/dd/yyyy / dd/MM/yyyy  (1900..=2100)

namespace Taskly {

public class DateParser : Object {

    public DateParser() {
    }

    // Parses into "%Y-%m-%d %H:%M:%S" (relative/at) or "%Y-%m-%d" (absolute).
    public string? parse(string input) {
        var s = input.strip();
        if (s.length == 0) {
            return null;
        }
        if (s.has_prefix("+")) {
            return parse_relative(s.substring(1));
        }
        if (s.has_prefix("@")) {
            return parse_at(s.substring(1));
        }
        return parse_absolute(s);
    }

    private string? parse_relative(string body) {
        // ^(\d*)([mhdwM])$ — last char is the unit, rest is digits.
        if (body.length == 0) {
            return null;
        }
        var unit = body.substring(body.length - 1);
        var digits = body.substring(0, body.length - 1);
        int64 amount = 1;
        if (digits.length > 0) {
            if (!is_digits(digits)) {
                return null;
            }
            amount = int64.parse(digits);
        }

        var now = new DateTime.now_local();
        switch (unit) {
            case "m": return now.add_minutes((int) amount).format("%Y-%m-%d %H:%M:%S");
            case "h": return now.add_hours((int) amount).format("%Y-%m-%d %H:%M:%S");
            case "d": return now.add_days((int) amount).format("%Y-%m-%d %H:%M:%S");
            case "w": return now.add_days((int) (amount * 7)).format("%Y-%m-%d %H:%M:%S");
            case "M": return now.add_days((int) (amount * 30)).format("%Y-%m-%d %H:%M:%S");
            default: return null;
        }
    }

    private string? parse_at(string body) {
        var trimmed = body.strip();
        if (trimmed.down() == "now") {
            return new DateTime.now_local().format("%Y-%m-%d %H:%M:%S");
        }

        string time_part = trimmed;
        string? modifier = null;
        var space = trimmed.index_of(" ");
        if (space > 0) {
            time_part = trimmed.substring(0, space);
            modifier = trimmed.substring(space + 1).strip();
            if (modifier.length == 0) {
                modifier = null;
            }
        }

        // ^(\d{1,2})(?::(\d{2}))?(am|pm)?$ (case-insensitive)
        var lower = time_part.down();
        bool is_pm = false;
        string core = lower;
        if (lower.has_suffix("am")) {
            core = lower.substring(0, lower.length - 2);
        } else if (lower.has_suffix("pm")) {
            core = lower.substring(0, lower.length - 2);
            is_pm = true;
        }

        var hour_str = core;
        var minute_str = "0";
        var colon = core.index_of(":");
        if (colon > 0) {
            hour_str = core.substring(0, colon);
            minute_str = core.substring(colon + 1);
        }

        if (hour_str.length < 1 || hour_str.length > 2 || !is_digits(hour_str)) {
            return null;
        }
        if (!is_digits(minute_str) || minute_str.length > 2) {
            return null;
        }

        int hour = int.parse(hour_str);
        int minute = minute_str.length > 0 ? int.parse(minute_str) : 0;

        if (lower.has_suffix("am") && hour == 12) {
            hour = 0;
        } else if (is_pm && hour < 12) {
            hour += 12;
        }

        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            return null;
        }

        var now = new DateTime.now_local();
        var date = new DateTime.local(
            now.get_year(), now.get_month(), now.get_day_of_month(), hour, minute, 0);

        if (modifier != null) {
            date = apply_day_modifier(date, modifier);
        } else if (date.compare(now) < 0) {
            date = date.add_days(1);
        }

        return date.format("%Y-%m-%d %H:%M:%S");
    }

    private DateTime apply_day_modifier(DateTime date, string modifier) {
        var m = modifier.down();
        if (m == "tomorrow" || m == "tmw") {
            return date.add_days(1);
        }

        // GLib: Monday=1..Sunday=7. Contract: sun..sat, next occurrence.
        int target;
        switch (m) {
            case "sun": target = 7; break;
            case "mon": target = 1; break;
            case "tue": target = 2; break;
            case "wed": target = 3; break;
            case "thu": target = 4; break;
            case "fri": target = 5; break;
            case "sat": target = 6; break;
            default: return date;
        }

        int current = date.get_day_of_week();
        int diff = (target - current + 7) % 7;
        if (diff <= 0) {
            diff += 7;
        }
        return date.add_days(diff);
    }

    private string? parse_absolute(string input) {
        var s = input.strip();

        // Single separator of '-' or '/', three parts, strict digit counts —
        // tried in the same order as the C# reference:
        //   yyyy-MM-dd, yyyy/MM/dd, MM/dd/yyyy, dd/MM/yyyy
        string sep = s.contains("-") ? "-" : (s.contains("/") ? "/" : "");
        if (sep.length == 0) {
            return null;
        }
        var parts = s.split(sep);
        if (parts.length != 3) {
            return null;
        }
        foreach (var part in parts) {
            if (!is_digits(part)) {
                return null;
            }
        }

        int year, month, day;
        if (parts[0].length == 4 && parts[1].length == 2 && parts[2].length == 2) {
            year = int.parse(parts[0]);
            month = int.parse(parts[1]);
            day = int.parse(parts[2]);
        } else if (parts[0].length == 2 && parts[1].length == 2 && parts[2].length == 4) {
            // MM/dd tried before dd/MM (reference order) — US format wins.
            month = int.parse(parts[0]);
            day = int.parse(parts[1]);
            year = int.parse(parts[2]);
        } else {
            return null;
        }

        if (year < Validation.MIN_YEAR || year > Validation.MAX_YEAR) {
            return null;
        }
        if (month < 1 || month > 12 || day < 1) {
            return null;
        }
        if (day > days_in_month(year, month)) {
            return null;
        }
        return "%04d-%02d-%02d".printf(year, month, day);
    }

    private static bool is_leap_year(int year) {
        return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    }

    private static int days_in_month(int year, int month) {
        int[] days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (month == 2 && is_leap_year(year)) {
            return 29;
        }
        return days[month - 1];
    }

    /// Strict "yyyy-MM-dd HH:mm:ss" parser (local time), null on mismatch.
    public static DateTime? parse_full_datetime(string s) {
        var space = s.index_of(" ");
        if (space != 10) {
            return null;
        }
        var date = parse_absolute_public(s.substring(0, 10));
        if (date == null) {
            return null;
        }
        var time_part = s.substring(11);
        var segments = time_part.split(":");
        if (segments.length != 3) {
            return null;
        }
        foreach (var segment in segments) {
            if (segment.length != 2 || !all_digits_check(segment)) {
                return null;
            }
        }
        int hour = int.parse(segments[0]);
        int minute = int.parse(segments[1]);
        int second = int.parse(segments[2]);
        if (hour > 23 || minute > 59 || second > 59) {
            return null;
        }
        var y = int.parse(date.substring(0, 4));
        var m = int.parse(date.substring(5, 2));
        var d = int.parse(date.substring(8, 2));
        return new DateTime.local(y, m, d, hour, minute, second);
    }

    private static bool is_digits(string s) {
        if (s.length == 0) {
            return false;
        }
        for (int i = 0; i < s.length; i++) {
            if (s[i] < '0' || s[i] > '9') {
                return false;
            }
        }
        return true;
    }

    /// Trailing @ command, then trailing relative command.
    public ExtractedCommand extract_time_command(string input) {
        var result = new ExtractedCommand();
        result.text = input;
        if (input.strip().length == 0) {
            return result;
        }

        var text = input;
        string? command = null;

        // Trailing @ command (CI): @(now|H[:MM][am|pm])( tomorrow|tmw|mon..sun)?
        try {
            var at_re = new GLib.Regex(
                "@(?:now|\\d{1,2}(?::\\d{2})?(?:am|pm)?)(?:\\s+(?:tomorrow|tmw|mon|tue|wed|thu|fri|sat|sun))?$",
                GLib.RegexCompileFlags.CASELESS);
            if (at_re.match(text, 0)) {
                var at_index = text.index_of("@");
                if (at_index >= 0) {
                    command = text.substring(at_index).strip();
                    text = text.substring(0, at_index).strip();
                }
            }
        } catch (Error e) {
            // Regex construction failure: skip @ extraction.
        }

        // Trailing relative: (?:^|\s)(\+\d+[mhdwM])(?:\s|$)
        try {
            var rel_re = new GLib.Regex("(?:^|\\s)(\\+\\d+[mhdwM])(?:\\s|$)");
            MatchInfo info;
            if (rel_re.match(text, 0, out info)) {
                command = info.fetch(1);
                int start = info.fetch(0).length > 0 ? text.index_of(info.fetch(0)) : -1;
                if (start >= 0) {
                    int end = start + info.fetch(0).length;
                    text = text.substring(0, start) + text.substring(end);
                    text = text.strip();
                }
            }
        } catch (Error e) {
            // Skip relative extraction.
        }

        result.text = text.strip();
        result.command = command;
        return result;
    }

    /// Public strict absolute-date parse ("yyyy-MM-dd" in, same out).
    public static string? parse_absolute_public(string s) {
        var parser = new DateParser();
        return parser.parse_absolute(s);
    }

    internal static bool all_digits_check(string s) {
        return is_digits(s);
    }

    /// First 10 chars ("yyyy-MM-dd").
    public static string? extract_date_only(string? s) {
        if (s == null || s.length == 0) {
            return null;
        }
        return s.length >= 10 ? s.substring(0, 10) : s;
    }

    /// chars [11..16] ("HH:mm") when present.
    public static string? extract_time_only(string? s) {
        if (s == null || s.length < 16) {
            return null;
        }
        return s.substring(11, 5);
    }

    /// date + time → "yyyy-MM-dd HH:mm:00" (defaults: today / 00:00).
    public static string combine_datetime(string? date_str, string? time_str) {
        var date = extract_date_only(date_str)
            ?? new DateTime.now_local().format("%Y-%m-%d");
        var time = (time_str != null && time_str.length > 0) ? time_str : "00:00";
        return "%s %s:00".printf(date, time);
    }

    /// ISO-8601 with local offset (compat with .NET "o" created_at).
    public static string created_at_now() {
        return new DateTime.now_local().format_iso8601();
    }

    public static string today_string() {
        return new DateTime.now_local().format("%Y-%m-%d");
    }
}

/// CLI --due result: date ("yyyy-MM-dd") + optional time ("HH:mm").
public class ParsedDue : Object {
    public string? date;
    public string? time;
}

/// ExtractedCommand result: remaining text + the trailing time command.
public class ExtractedCommand : Object {
    public string text = "";
    public string? command;
}

/// CLI --due wrapper: bare-word mapping + date-only intent rule.
public ParsedDue parse_due(DateParser parser, string due) throws GLib.Error {
    var original = due.strip();
    var lower = original.down();
    string normalized;
    switch (lower) {
        case "today": normalized = "+0d"; break;
        case "tomorrow":
        case "tmw": normalized = "+1d"; break;
        case "tonight": normalized = "@20:00"; break;
        default: normalized = original; break;
    }

    var parsed = parser.parse(normalized);
    if (parsed == null) {
        throw app_error(
            "Cannot parse date/time: \"%s\". Supported: +10m, +2h, +1d, +1w, @10am, @10:30pm, today, tomorrow, yyyy-MM-dd".printf(due),
            AppErrorType.VALIDATION);
    }

    var date = DateParser.extract_date_only(parsed);
    var time = DateParser.extract_time_only(parsed);

    // Date-only intent: bare words, +Nd/+Nw/+NM, or a 10-char absolute result.
    var last_char = normalized.length > 0 ? normalized.substring(normalized.length - 1) : "";
    var is_date_only = (lower == "today" || lower == "tomorrow" || lower == "tmw")
        || (normalized.has_prefix("+") && (last_char == "d" || last_char == "w" || last_char == "M"))
        || (parsed.length == 10);

    if (is_date_only) {
        time = null;
    }
    var result = new ParsedDue();
    result.date = date;
    result.time = time;
    return result;
}

}
