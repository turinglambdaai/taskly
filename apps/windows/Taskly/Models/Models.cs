using CommunityToolkit.Mvvm.ComponentModel;

namespace Taskly.Models;

/// <summary>
/// Theme-dependent UI colors as plain values, consumed by data-template
/// projections. Values mirror DESIGN-TOKENS.md (light/dark).
/// </summary>
public static class UiTheme
{
    public static bool IsDark;

    public static Windows.UI.Color Accent => IsDark
        ? Windows.UI.Color.FromArgb(0xFF, 0x0A, 0x84, 0xFF)
        : Windows.UI.Color.FromArgb(0xFF, 0x00, 0x7A, 0xFF);

    public static Windows.UI.Color Secondary => IsDark
        ? Windows.UI.Color.FromArgb(0xFF, 0x98, 0x98, 0x9E)
        : Windows.UI.Color.FromArgb(0xFF, 0x8E, 0x8E, 0x93);

    public static Windows.UI.Color Tertiary => IsDark
        ? Windows.UI.Color.FromArgb(0xFF, 0x6B, 0x6B, 0x72)
        : Windows.UI.Color.FromArgb(0xFF, 0xB0, 0xB0, 0xB5);

    public static Windows.UI.Color OnSurface => IsDark
        ? Windows.UI.Color.FromArgb(0xFF, 0xF5, 0xF5, 0xF7)
        : Windows.UI.Color.FromArgb(0xFF, 0x1D, 0x1D, 0x1F);

    public static Microsoft.UI.Xaml.Media.SolidColorBrush BrushOf(Windows.UI.Color color) =>
        new(color);

    public static Windows.UI.Color WithAlpha(Windows.UI.Color color, byte alpha) =>
        Windows.UI.Color.FromArgb(alpha, color.R, color.G, color.B);
}

/// <summary>Task model; mirrors the tasks table (DATA-FORMAT.md, schema v4).</summary>
public partial class TaskItem : ObservableObject
{
    [ObservableProperty]
    private int _id;

    [ObservableProperty]
    private int _listId;

    [ObservableProperty]
    private string _text = "";

    /// <summary>ISO-8601 round-trip local timestamp (compat with .NET "o").</summary>
    [ObservableProperty]
    private string _createdAt = "";

    /// <summary>"yyyy-MM-dd" or null.</summary>
    [ObservableProperty]
    private string? _dueDate;

    /// <summary>"HH:mm" or null.</summary>
    [ObservableProperty]
    private string? _dueTime;

    [ObservableProperty]
    private bool _completed;

    [ObservableProperty]
    private string? _notes;

    /// <summary>Join artifact (LEFT JOIN lists); never persisted.</summary>
    [ObservableProperty]
    private string? _listName;

    /// <summary>Join artifact (lists.color, signed ARGB); never persisted.
    /// Drives the checkbox ring color (Reminders-style list identity).</summary>
    [ObservableProperty]
    private int? _listColor;

    public TaskItem() { }

    public TaskItem(int id, int listId, string text, string createdAt,
        string? dueDate = null, string? dueTime = null, bool completed = false,
        string? notes = null, string? listName = null, int? listColor = null)
    {
        Id = id;
        ListId = listId;
        Text = text;
        CreatedAt = createdAt;
        DueDate = dueDate;
        DueTime = dueTime;
        Completed = completed;
        Notes = notes;
        ListName = listName;
        ListColor = listColor;
    }

    // UI projections for the task-row data template (classic {Binding}).

    private Windows.UI.Color ListAccent =>
        ListColor is null ? UiTheme.Accent : FromArgbInt(ListColor.Value);

    private static Windows.UI.Color FromArgbInt(int argb)
    {
        var hex = unchecked((uint)argb);
        return Windows.UI.Color.FromArgb(
            (byte)((hex >> 24) & 0xFF),
            (byte)((hex >> 16) & 0xFF),
            (byte)((hex >> 8) & 0xFF),
            (byte)(hex & 0xFF));
    }

    public Windows.UI.Color RingColor => Completed ? UiTheme.Tertiary : ListAccent;
    public Windows.UI.Color RingFill => Completed ? UiTheme.Tertiary : Microsoft.UI.Colors.Transparent;

    public Microsoft.UI.Xaml.Media.Brush TextBrush =>
        new Microsoft.UI.Xaml.Media.SolidColorBrush(
            Completed ? UiTheme.Tertiary : UiTheme.OnSurface);

    public Windows.UI.Text.TextDecorations Decorations => Completed
        ? Windows.UI.Text.TextDecorations.Strikethrough
        : Windows.UI.Text.TextDecorations.None;

    /// <summary>Localized due display: 今天/明天/昨天 → `9月26日` / `September 26`
    /// (DESIGN-TOKENS due-date semantics); cross-year falls back to ISO.</summary>
    public string DueText
    {
        get
        {
            if (DueDate is null)
            {
                return "";
            }

            var i18n = Services.I18nService.Instance;
            var dateText = DueDate;
            if (DateTime.TryParseExact(DueDate, "yyyy-MM-dd",
                    System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None, out var date))
            {
                var today = DateTime.Now.Date;
                if (date == today)
                {
                    dateText = i18n.T("navToday");
                }
                else if (date == today.AddDays(1))
                {
                    dateText = i18n.T("dateTomorrow");
                }
                else if (date == today.AddDays(-1))
                {
                    dateText = i18n.T("dateYesterday");
                }
                else if (date.Year == today.Year)
                {
                    var monthName = i18n.T($"calMonthShort{date.Month}");
                    dateText = i18n.Current == "zh"
                        ? $"{monthName}{date.Day}日"
                        : $"{monthName} {date.Day}";
                }
            }

            return string.IsNullOrEmpty(DueTime) ? dateText : $"{dateText}  {DueTime}";
        }
    }

    /// <summary>Meta-line color: overdue incomplete = danger red, due today =
    /// accent, otherwise secondary (DESIGN-TOKENS due-date semantics).</summary>
    public Microsoft.UI.Xaml.Media.Brush DueBrush
    {
        get
        {
            Windows.UI.Color color;
            if (Completed || DueDate is null)
            {
                color = UiTheme.Secondary;
            }
            else if (DateTime.TryParseExact(DueDate, "yyyy-MM-dd",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out var date))
            {
                var today = DateTime.Now.Date;
                color = date < today ? Windows.UI.Color.FromArgb(0xFF, 0xFF, 0x3B, 0x30)
                    : date == today ? UiTheme.Accent
                    : UiTheme.Secondary;
            }
            else
            {
                color = UiTheme.Secondary;
            }

            return new Microsoft.UI.Xaml.Media.SolidColorBrush(color);
        }
    }

    public Microsoft.UI.Xaml.Visibility MetaVisibility => DueDate is null
        ? Microsoft.UI.Xaml.Visibility.Collapsed
        : Microsoft.UI.Xaml.Visibility.Visible;

    public Microsoft.UI.Xaml.Visibility CheckVisibility => Completed
        ? Microsoft.UI.Xaml.Visibility.Visible
        : Microsoft.UI.Xaml.Visibility.Collapsed;

    public string NotesText => Notes ?? "";

    public Microsoft.UI.Xaml.Visibility NotesVisibility => string.IsNullOrEmpty(Notes)
        ? Microsoft.UI.Xaml.Visibility.Collapsed
        : Microsoft.UI.Xaml.Visibility.Visible;

    public Models.TaskItem With(int? id = null, int? listId = null, string? text = null,
        string? dueDate = null, string? dueTime = null, bool? completed = null,
        string? notes = null, bool clearDueDate = false, bool clearDueTime = false,
        bool clearNotes = false)
    {
        return new Models.TaskItem(
            id ?? Id, listId ?? ListId, text ?? Text, CreatedAt,
            clearDueDate ? null : (dueDate ?? DueDate),
            clearDueTime ? null : (dueTime ?? DueTime),
            completed ?? Completed,
            clearNotes ? null : (notes ?? Notes),
            ListName);
    }
}

/// <summary>Task list; color is a signed ARGB int as stored in the DB.</summary>
public partial class TodoList : ObservableObject
{
    public const string DefaultIcon = "📋";
    /// <summary>System blue, ARGB 0xFF007AFF, as a signed 32-bit int.</summary>
    public const int DefaultColor = unchecked((int)0xFF007AFF);

    [ObservableProperty]
    private int _id;

    [ObservableProperty]
    private string _name = "";

    [ObservableProperty]
    private string? _icon;

    [ObservableProperty]
    private int? _color;

    /// <summary>Unfinished count, UI-only.</summary>
    [ObservableProperty]
    private int _pendingCount;

    public TodoList(int id, string name, string? icon = null, int? color = null)
    {
        Id = id;
        Name = name;
        Icon = icon;
        Color = color;
    }

    // UI helpers (display projections; used by list-row bindings).

    public Windows.UI.Color RowColor
    {
        get
        {
            var hex = unchecked((uint)(Color ?? Models.TodoList.DefaultColor));
            return Windows.UI.Color.FromArgb(
                (byte)((hex >> 24) & 0xFF),
                (byte)((hex >> 16) & 0xFF),
                (byte)((hex >> 8) & 0xFF),
                (byte)(hex & 0xFF));
        }
    }

    public string IconText => (Icon ?? DefaultIcon) + " ";

    public string PendingText => PendingCount > 0 ? PendingCount.ToString() : "";
}

public enum TaskViewType
{
    All,
    Today,
    Planned,
    Completed,
    List,
    Calendar,
}

/// <summary>Incomplete-task count per due date, for calendar day dots
/// (PRODUCT-SPEC §4b).</summary>
public record DueDayCount(string Date, int Count);

/// <summary>Group header row inside the calendar time line; intermixed with
/// TaskItem rows in the calendar list (PRODUCT-SPEC §4b).</summary>
public sealed record CalendarSectionHeader(
    string HeaderText,
    int Count,
    bool IsToday,
    bool IsOverdue,
    string? DateKey)
{
    public string CountText => Count > 0 ? Count.ToString() : "";

    /// <summary>Today's header in accent, overdue in danger red (§4b); WinUI
    /// has no data triggers, so the brush is a projected property.</summary>
    public Microsoft.UI.Xaml.Media.Brush HeaderBrush =>
        new Microsoft.UI.Xaml.Media.SolidColorBrush(
            IsOverdue ? Windows.UI.Color.FromArgb(0xFF, 0xFF, 0x3B, 0x30)
            : IsToday ? UiTheme.Accent
            : UiTheme.OnSurface);
}

/// <summary>Error with a user-facing message and a category; the category
/// maps to the CLI exit codes (validation→2, notFound→3, database→4).</summary>
public record AppError(string Message, AppErrorType Type = AppErrorType.Generic)
{
    public int ExitCode => Type switch
    {
        AppErrorType.Validation => 2,
        AppErrorType.NotFound => 3,
        AppErrorType.Database => 4,
        _ => 1,
    };
}

public enum AppErrorType
{
    Generic,
    Validation,
    NotFound,
    Database,
}
