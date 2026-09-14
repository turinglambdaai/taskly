using System.Globalization;
using System.Text.RegularExpressions;

namespace Taskly.Services;

/// <summary>
/// Natural-language date/time parser (CLI-SPEC.md §--due). Port of the
/// proven 0.6.x implementation — grammar is a cross-platform contract:
///   +10m, +2h, +1d, +1w, +1M (30 days; case-sensitive m/M, digits optional)
///   @now, @10am, @10:30am, @22:30, optional tomorrow/tmw/mon..sun modifier
///   absolute: yyyy-MM-dd / yyyy/MM/dd / MM/dd/yyyy / dd/MM/yyyy (1900-2100)
/// Results: 'yyyy-MM-dd HH:mm:ss' or date-only 'yyyy-MM-dd'.
/// </summary>
public sealed class DateParser
{
    private static readonly Regex RelativeDateRegex = new(
        @"^(\d*)([mhdwM])$",
        RegexOptions.CultureInvariant);

    private static readonly Regex TimeRegex = new(
        @"^(\d{1,2})(?::(\d{2}))?(am|pm)?$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    private static readonly Regex ExtractRelativeRegex = new(
        @"(?:^|\s)(\+\d+[mhdwM])(?:\s|$)",
        RegexOptions.CultureInvariant);

    private static readonly Regex ExtractAtRegex = new(
        @"@(?:now|\d{1,2}(?::\d{2})?(?:am|pm)?)(?:\s+(?:tomorrow|tmw|mon|tue|wed|thu|fri|sat|sun))?$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public string? Parse(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return null;
        }

        var s = input.Trim();

        if (s.StartsWith('+'))
        {
            return ParseRelativeDate(s);
        }

        if (s.StartsWith('@'))
        {
            return ParseAtTime(s[1..]);
        }

        return ParseAbsoluteDate(s);
    }

    /// <summary>Pulls a trailing time command out of text.</summary>
    public (string Text, string? TimeCommand) ExtractTimeCommand(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return (input ?? string.Empty, null);
        }

        var text = input;
        string? command = null;

        var atMatch = ExtractAtRegex.Match(text);
        if (atMatch.Success)
        {
            var atIndex = text.IndexOf('@');
            command = text[atIndex..].Trim();
            text = text[..atIndex].TrimEnd();
        }

        var relMatch = ExtractRelativeRegex.Match(text);
        if (relMatch.Success)
        {
            command = relMatch.Groups[1].Value;
            text = text.Remove(relMatch.Index, relMatch.Length).Trim();
        }

        return (text.Trim(), command);
    }

    private string? ParseRelativeDate(string input)
    {
        var body = input[1..];
        var match = RelativeDateRegex.Match(body);
        if (!match.Success)
        {
            return null;
        }

        var num = match.Groups[1].Value;
        var amount = string.IsNullOrEmpty(num) ? 1 : int.Parse(num, CultureInfo.InvariantCulture);
        var unit = match.Groups[2].Value;

        var now = DateTime.Now;
        var result = unit switch
        {
            "m" => now.AddMinutes(amount),
            "h" => now.AddHours(amount),
            "d" => now.AddDays(amount),
            "w" => now.AddDays(amount * 7),
            "M" => now.AddDays(amount * 30),
            _ => (DateTime?)null,
        };

        return result?.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
    }

    private string? ParseAtTime(string input)
    {
        var trimmed = input.Trim();

        if (trimmed.Equals("now", StringComparison.OrdinalIgnoreCase))
        {
            return DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
        }

        var parts = trimmed.Split(new[] { ' ' }, 2, StringSplitOptions.RemoveEmptyEntries);
        var timePart = parts[0];
        var modifier = parts.Length > 1 ? parts[1] : null;

        var match = TimeRegex.Match(timePart);
        if (!match.Success)
        {
            return null;
        }

        var hour = int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
        var min = match.Groups[2].Success ? int.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture) : 0;
        var ampm = match.Groups[3].Success ? match.Groups[3].Value.ToLowerInvariant() : null;

        if (ampm == "am")
        {
            if (hour == 12)
            {
                hour = 0;
            }
        }
        else if (ampm == "pm")
        {
            if (hour < 12)
            {
                hour += 12;
            }
        }

        if (hour is < 0 or > 23 || min is < 0 or > 59)
        {
            return null;
        }

        var today = DateTime.Now;
        var date = new DateTime(today.Year, today.Month, today.Day, hour, min, 0);

        if (!string.IsNullOrEmpty(modifier))
        {
            date = ApplyDayModifier(date, modifier!);
        }
        else if (date < DateTime.Now)
        {
            date = date.AddDays(1);
        }

        return date.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
    }

    private DateTime ApplyDayModifier(DateTime date, string modifier)
    {
        var m = modifier.ToLowerInvariant();
        if (m is "tomorrow" or "tmw")
        {
            return date.AddDays(1);
        }

        var targetDay = m switch
        {
            "sun" => DayOfWeek.Sunday,
            "mon" => DayOfWeek.Monday,
            "tue" => DayOfWeek.Tuesday,
            "wed" => DayOfWeek.Wednesday,
            "thu" => DayOfWeek.Thursday,
            "fri" => DayOfWeek.Friday,
            "sat" => DayOfWeek.Saturday,
            _ => (DayOfWeek?)null,
        };

        if (targetDay is { } td)
        {
            var diff = ((int)td - (int)date.DayOfWeek + 7) % 7;
            if (diff <= 0)
            {
                diff += 7;
            }

            return date.AddDays(diff);
        }

        return date;
    }

    private string? ParseAbsoluteDate(string input)
    {
        var s = input.Trim();

        string[]? formats =
        {
            "yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "dd/MM/yyyy",
        };

        foreach (var fmt in formats)
        {
            if (DateTime.TryParseExact(s, fmt, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
            {
                if (date.Year < ValidationHelper.MinYear || date.Year > ValidationHelper.MaxYear)
                {
                    return null;
                }

                return date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            }
        }

        return null;
    }

    // ---------------- display helpers ----------------

    public static string? ExtractDateOnly(string? dateTimeStr)
    {
        if (string.IsNullOrEmpty(dateTimeStr))
        {
            return null;
        }

        return dateTimeStr!.Length >= 10 ? dateTimeStr[..10] : dateTimeStr;
    }

    public static string? ExtractTimeOnly(string? dateTimeStr)
    {
        if (string.IsNullOrEmpty(dateTimeStr) || dateTimeStr!.Length < 16)
        {
            return null;
        }

        return dateTimeStr[11..16];
    }

    public static string CombineDateTime(string? dateStr, string? timeStr)
    {
        var date = ExtractDateOnly(dateStr) ?? DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var time = !string.IsNullOrEmpty(timeStr) ? timeStr : "00:00";
        return $"{date} {time}:00";
    }

    public string FormatDateOnlyForDisplay(string? dateStr, Func<string> todayLabel,
        Func<string> tomorrowLabel, Func<string> yesterdayLabel)
    {
        var dateOnly = ExtractDateOnly(dateStr);
        if (string.IsNullOrEmpty(dateOnly))
        {
            return string.Empty;
        }

        if (DateTime.TryParseExact(dateOnly, "yyyy-MM-dd", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out var date))
        {
            var today = DateTime.Today;
            if (date.Date == today)
            {
                return todayLabel();
            }

            if (date.Date == today.AddDays(1))
            {
                return tomorrowLabel();
            }

            if (date.Date == today.AddDays(-1))
            {
                return yesterdayLabel();
            }
        }

        return dateOnly!;
    }

    public string FormatDateTimeForDisplay(string? dateTimeStr, Func<string> todayLabel,
        Func<string> tomorrowLabel, Func<string> yesterdayLabel)
    {
        if (string.IsNullOrEmpty(dateTimeStr))
        {
            return string.Empty;
        }

        var dateOnly = ExtractDateOnly(dateTimeStr);
        var timeOnly = ExtractTimeOnly(dateTimeStr);
        var dateLabel = FormatDateOnlyForDisplay(dateOnly, todayLabel, tomorrowLabel, yesterdayLabel);

        return string.IsNullOrEmpty(timeOnly)
            ? dateLabel
            : $"{dateLabel} {timeOnly}";
    }
}
