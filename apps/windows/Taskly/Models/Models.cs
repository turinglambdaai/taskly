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

    public static Windows.UI.Color Tertiary => IsDark
        ? Windows.UI.Color.FromArgb(0xFF, 0x6B, 0x6B, 0x72)
        : Windows.UI.Color.FromArgb(0xFF, 0xB0, 0xB0, 0xB5);

    public static Windows.UI.Color OnSurface => IsDark
        ? Windows.UI.Color.FromArgb(0xFF, 0xF5, 0xF5, 0xF7)
        : Windows.UI.Color.FromArgb(0xFF, 0x1D, 0x1D, 0x1F);
}

/// <summary>Task model; mirrors the tasks table (DATA-FORMAT.md, schema v4).</summary>
public sealed class TaskItem : ObservableObject
{
    private int _id;
    private int _listId;
    private string _text = "";
    private string _createdAt = "";
    private string? _dueDate;
    private string? _dueTime;
    private bool _completed;
    private string? _notes;
    private string? _listName;

    public int Id
    {
        get => _id;
        set => SetProperty(ref _id, value);
    }

    public int ListId
    {
        get => _listId;
        set => SetProperty(ref _listId, value);
    }

    public string Text
    {
        get => _text;
        set => SetProperty(ref _text, value);
    }

    /// <summary>ISO-8601 round-trip local timestamp (compat with .NET "o").</summary>
    public string CreatedAt
    {
        get => _createdAt;
        set => SetProperty(ref _createdAt, value);
    }

    /// <summary>"yyyy-MM-dd" or null.</summary>
    public string? DueDate
    {
        get => _dueDate;
        set => SetProperty(ref _dueDate, value);
    }

    /// <summary>"HH:mm" or null.</summary>
    public string? DueTime
    {
        get => _dueTime;
        set => SetProperty(ref _dueTime, value);
    }

    public bool Completed
    {
        get => _completed;
        set => SetProperty(ref _completed, value);
    }

    public string? Notes
    {
        get => _notes;
        set => SetProperty(ref _notes, value);
    }

    /// <summary>Join artifact (LEFT JOIN lists); never persisted.</summary>
    public string? ListName
    {
        get => _listName;
        set => SetProperty(ref _listName, value);
    }

    public TaskItem() { }

    public TaskItem(int id, int listId, string text, string createdAt,
        string? dueDate = null, string? dueTime = null, bool completed = false,
        string? notes = null, string? listName = null)
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
    }

    // UI projections for the task-row data template (classic {Binding}).

    public Windows.UI.Color RingColor => Completed ? UiTheme.Accent : UiTheme.Tertiary;
    public Windows.UI.Color RingFill => Completed ? UiTheme.Accent : Microsoft.UI.Colors.Transparent;

    public Microsoft.UI.Xaml.Media.Brush TextBrush =>
        new Microsoft.UI.Xaml.Media.SolidColorBrush(
            Completed ? UiTheme.Tertiary : UiTheme.OnSurface);

    public Windows.UI.Text.TextDecorations Decorations => Completed
        ? Windows.UI.Text.TextDecorations.Strikethrough
        : Windows.UI.Text.TextDecorations.None;

    public string DueText => DueDate is null
        ? ""
        : "🗓 " + DueDate + (string.IsNullOrEmpty(DueTime) ? "" : "  🕐 " + DueTime);

    public Microsoft.UI.Xaml.Visibility MetaVisibility => DueDate is null
        ? Microsoft.UI.Xaml.Visibility.Collapsed
        : Microsoft.UI.Xaml.Visibility.Visible;

    public string NotesText => Notes ?? "";

    public Microsoft.UI.Xaml.Visibility NotesVisibility => string.IsNullOrEmpty(Notes)
        ? Microsoft.UI.Xaml.Visibility.Collapsed
        : Microsoft.UI.Xaml.Visibility.Visible;

    public TaskItem With(int? id = null, int? listId = null, string? text = null,
        string? dueDate = null, string? dueTime = null, bool? completed = null,
        string? notes = null, bool clearDueDate = false, bool clearDueTime = false,
        bool clearNotes = false)
    {
        return new TaskItem(
            id ?? Id, listId ?? ListId, text ?? Text, CreatedAt,
            clearDueDate ? null : (dueDate ?? DueDate),
            clearDueTime ? null : (dueTime ?? DueTime),
            completed ?? Completed,
            clearNotes ? null : (notes ?? Notes),
            ListName);
    }
}

/// <summary>Task list; color is a signed ARGB int as stored in the DB.</summary>
public sealed class TodoList : ObservableObject
{
    public const string DefaultIcon = "📋";
    /// <summary>System blue, ARGB 0xFF007AFF, as a signed 32-bit int.</summary>
    public const int DefaultColor = unchecked((int)0xFF007AFF);

    private int _id;
    private string _name = "";
    private string? _icon;
    private int? _color;
    private int _pendingCount;

    public int Id
    {
        get => _id;
        set => SetProperty(ref _id, value);
    }

    public string Name
    {
        get => _name;
        set => SetProperty(ref _name, value);
    }

    public string? Icon
    {
        get => _icon;
        set => SetProperty(ref _icon, value);
    }

    public int? Color
    {
        get => _color;
        set => SetProperty(ref _color, value);
    }

    /// <summary>Unfinished count, UI-only.</summary>
    public int PendingCount
    {
        get => _pendingCount;
        set => SetProperty(ref _pendingCount, value);
    }

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
            var hex = unchecked((uint)(Color ?? DefaultColor));
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
