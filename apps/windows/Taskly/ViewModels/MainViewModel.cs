using System.Collections.ObjectModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Xaml;
using Taskly.Data;
using Taskly.Models;
using Taskly.Repositories;
using Taskly.Services;

namespace Taskly.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly SQLiteDatabase _db = new();
    private readonly ConfigService _config = new();
    private readonly I18nService _i18n = I18nService.Instance;
    private DateParser DateParser { get; } = new();

    public TaskRepository Tasks { get; private set; }
    public ListRepository Lists { get; private set; }
    public ReminderService Reminder { get; }

    public ObservableCollection<TodoList> ListCollection { get; } = new();
    public ObservableCollection<TaskItem> TaskItems { get; } = new();

    /// <summary>Calendar time-line rows: CalendarSectionHeader and TaskItem
    /// intermixed (PRODUCT-SPEC §4b).</summary>
    public ObservableCollection<object> CalendarRows { get; } = new();

    /// <summary>due date → incomplete count for the displayed month's day dots.</summary>
    public Dictionary<string, int> CalendarDayCounts { get; } = new();

    [ObservableProperty]
    private TaskViewType _currentView = TaskViewType.All;

    [ObservableProperty]
    private int? _currentListId;

    [ObservableProperty]
    private bool _isConnected;

    [ObservableProperty]
    private bool _showCompletedTasks;

    [ObservableProperty]
    private string _statusMessage = "";

    [ObservableProperty]
    private string _currentTitle = "";

    [ObservableProperty]
    private bool _isSidebarVisible = true;

    [ObservableProperty]
    private int _calendarYear;

    /// <summary>1–12; month the calendar grid shows.</summary>
    [ObservableProperty]
    private int _calendarMonth;

    /// <summary>"yyyy-MM-dd" of the highlighted day cell, null when not in
    /// the calendar view.</summary>
    [ObservableProperty]
    private string? _selectedCalendarDate;

    /// <summary>Raised with a due-date key when a day cell is picked; the
    /// pane scrolls its time line to that group.</summary>
    public event Action<string?>? CalendarScrollRequested;

    /// <summary>Raised when day-dot counts changed (month switched, data edited).</summary>
    public event Action? CalendarCountsChanged;

    private string? _searchKeyword;
    private string? _persistentStatus;
    private DispatcherTimer? _statusTimer;

    public event Action? CountsChanged;
    public event Action? LanguageChanged;

    public int TodayCount { get; private set; }
    public int PlannedCount { get; private set; }
    public int AllCount { get; private set; }
    public int CompletedCount { get; private set; }

    /// <summary>Calendar pane visible only when the calendar view is active
    /// and not searching (search shows flat results, as in every view).</summary>
    public bool IsCalendarView =>
        CurrentView == TaskViewType.Calendar && string.IsNullOrEmpty(_searchKeyword);

    public MainViewModel()
    {
        _config.Load();
        _i18n.SetLanguage(_config.Language);
        _i18n.LanguageChanged += () =>
        {
            RefreshPersistentStatus();
            LanguageChanged?.Invoke();
        };

        Tasks = new TaskRepository(_db, _i18n);
        Lists = new ListRepository(_db, _i18n);
        Reminder = new ReminderService(_db, _i18n);

        StatusMessage = T("statusDatabaseNotConnected");
    }

    public string T(string key) => _i18n.T(key);

    public void SaveLanguage(string language)
    {
        _config.Language = language;
        _config.Save();
    }

    // ---------------- database lifecycle ----------------

    public async Task OpenOrCreateDatabaseAsync(string path)
    {
        _db.Close();
        _db.SetDatabasePath(path);
        Tasks = new TaskRepository(_db, _i18n);
        Lists = new ListRepository(_db, _i18n);

        try
        {
            await _db.EnsureConnectedAsync();
        }
        catch (Exception ex)
        {
            IsConnected = false;
            ShowTransientStatus(ex.Message);
            return;
        }

        IsConnected = true;
        Reminder.ResetNotified();

        _config.LastDbPath = path;
        _config.Save();

        await ReloadListsAsync();
        RestoreSelection();
        await RefreshCountsAsync();
        await RefreshAsync();
        RefreshPersistentStatus();
        ShowTransientStatus(T("statusDatabaseConnected"));
        Reminder.Start();
    }

    public async Task OpenDefaultDatabaseAsync()
    {
        var path = !string.IsNullOrEmpty(_config.LastDbPath)
            ? _config.LastDbPath
            : PathUtils.GetDefaultDatabasePath();
        await OpenOrCreateDatabaseAsync(path);
    }

    public async Task CloseDatabaseAsync()
    {
        await _db.CloseAsync();
        IsConnected = false;
        ListCollection.Clear();
        TaskItems.Clear();
        CalendarRows.Clear();
        CalendarDayCounts.Clear();
        CurrentView = TaskViewType.All;
        CurrentListId = null;
        CalendarYear = 0;
        SelectedCalendarDate = null;
        RefreshPersistentStatus();
        ShowTransientStatus(T("statusDatabaseClosed"));
    }

    private void RestoreSelection()
    {
        var lastId = _config.LastSelectedListId;
        var list = ListCollection.FirstOrDefault(l => l.Id == lastId);
        if (lastId != 0 && list is not null)
        {
            CurrentView = TaskViewType.List;
            CurrentListId = lastId;
        }
        else
        {
            CurrentView = TaskViewType.All;
            CurrentListId = null;
        }
    }

    // ---------------- refresh ----------------

    public async Task ReloadListsAsync()
    {
        var lists = await Lists.GetAllListsAsync();
        ListCollection.Clear();
        foreach (var l in lists)
        {
            ListCollection.Add(l);
        }
    }

    public async Task RefreshCountsAsync()
    {
        TodayCount = await Tasks.GetTodayTaskCountAsync();
        PlannedCount = await Tasks.GetPlannedTaskCountAsync();
        AllCount = await Tasks.GetIncompleteTaskCountAsync();
        CompletedCount = await Tasks.GetCompletedTaskCountAsync();
        foreach (var l in ListCollection)
        {
            l.PendingCount = await Tasks.GetTaskCountByListAsync(l.Id);
        }

        CountsChanged?.Invoke();
    }

    public async Task RefreshAsync()
    {
        if (!IsConnected)
        {
            TaskItems.Clear();
            CalendarRows.Clear();
            return;
        }

        try
        {
            if (IsCalendarView)
            {
                await RefreshCalendarAsync();
                UpdateTitle();
                return;
            }

            CalendarRows.Clear();

            List<TaskItem> tasks;
            if (!string.IsNullOrEmpty(_searchKeyword))
            {
                tasks = await Tasks.SearchTasksAsync(_searchKeyword);
            }
            else
            {
                tasks = await Tasks.GetTasksByViewAsync(CurrentView, CurrentListId, showCompleted: ShowCompletedTasks);
            }

            TaskItems.Clear();
            foreach (var t in tasks)
            {
                TaskItems.Add(t);
            }
        }
        catch
        {
            TaskItems.Clear();
        }

        UpdateTitle();
    }

    /// <summary>Calendar view data: overdue tail + displayed-month groups,
    /// plus the day-dot counts (PRODUCT-SPEC §4b).</summary>
    private async Task RefreshCalendarAsync()
    {
        var today = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var beforeToday = DateTime.Now.Date.AddDays(-1).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var (start, end) = MonthRange(CalendarYear, CalendarMonth);

        var overdue = await Tasks.GetTasksInRangeAsync("1900-01-01", beforeToday, ShowCompletedTasks);
        var monthTasks = await Tasks.GetTasksInRangeAsync(start, end, ShowCompletedTasks);
        var counts = await Tasks.GetDueDayCountsAsync(start, end);

        CalendarDayCounts.Clear();
        foreach (var c in counts)
        {
            CalendarDayCounts[c.Date] = c.Count;
        }

        CalendarRows.Clear();
        if (overdue.Count > 0)
        {
            CalendarRows.Add(new CalendarSectionHeader(T("calOverdue"), overdue.Count,
                IsToday: false, IsOverdue: true, DateKey: null));
            foreach (var t in overdue)
            {
                CalendarRows.Add(t);
            }
        }

        var todayDate = DateTime.Now.Date;
        foreach (var group in monthTasks.Where(t => t.DueDate is not null).GroupBy(t => t.DueDate!))
        {
            var isToday = group.Key == today;
            CalendarRows.Add(new CalendarSectionHeader(FormatDayHeader(group.Key),
                group.Count(), IsToday: isToday, IsOverdue: false, DateKey: group.Key));
            foreach (var t in group)
            {
                CalendarRows.Add(t);
            }
        }

        CalendarCountsChanged?.Invoke();
    }

    private static (string Start, string End) MonthRange(int year, int month)
    {
        var first = new DateTime(year, month, 1);
        var last = first.AddMonths(1).AddDays(-1);
        return (first.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            last.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
    }

    /// <summary>Group header text: `9月26日 · 周五` / `Friday, September 26`;
    /// today/tomorrow/yesterday replace the weekday slot (§4b).</summary>
    public string FormatDayHeader(string dateKey)
    {
        var date = DateTime.ParseExact(dateKey, "yyyy-MM-dd", CultureInfo.InvariantCulture);
        var monthName = T($"calMonth{date.Month}");
        var relative = RelativeDayLabel(dateKey);
        var weekday = relative ?? T($"calWeekday{((int)date.DayOfWeek + 6) % 7 + 1}");
        return string.Format(CultureInfo.InvariantCulture, T("calDayHeader"), monthName, date.Day, weekday);
    }

    /// <summary>navToday / dateTomorrow / dateYesterday when the key is one of
    /// those three days relative to now; null otherwise.</summary>
    public string? RelativeDayLabel(string dateKey)
    {
        var today = DateTime.Now.Date;
        var date = DateTime.ParseExact(dateKey, "yyyy-MM-dd", CultureInfo.InvariantCulture).Date;
        if (date == today)
        {
            return T("navToday");
        }

        if (date == today.AddDays(1))
        {
            return T("dateTomorrow");
        }

        if (date == today.AddDays(-1))
        {
            return T("dateYesterday");
        }

        return null;
    }

    /// <summary>Month-grid title: `2026年9月` / `September 2026`.</summary>
    public string CalendarMonthTitle =>
        string.Format(CultureInfo.InvariantCulture, T("calMonthTitle"), CalendarYear, T($"calMonth{CalendarMonth}"));

    /// <summary>Weekday short-name row for the grid, ordered by the language's
    /// week start (zh Monday-first, en Sunday-first); index 1 = Monday.</summary>
    public List<string> CalendarWeekdayHeader
    {
        get
        {
            var names = Enumerable.Range(1, 7).Select(i => T($"calWeekdayShort{i}")).ToList();
            return _i18n.Current == "zh"
                ? names
                : new List<string> { names[6], names[0], names[1], names[2], names[3], names[4], names[5] };
        }
    }

    // ---------------- calendar interactions ----------------

    public async Task NavigateCalendarMonthAsync(int delta)
    {
        var first = new DateTime(CalendarYear, CalendarMonth, 1).AddMonths(delta);
        CalendarYear = first.Year;
        CalendarMonth = first.Month;
        SelectedCalendarDate = new DateTime(first.Year, first.Month, 1).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        await RefreshAsync();
        CalendarScrollRequested?.Invoke(SelectedCalendarDate);
    }

    public async Task GoCalendarTodayAsync()
    {
        var now = DateTime.Now;
        CalendarYear = now.Year;
        CalendarMonth = now.Month;
        SelectedCalendarDate = now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        await RefreshAsync();
        CalendarScrollRequested?.Invoke(SelectedCalendarDate);
    }

    public void SelectCalendarDate(string dateKey)
    {
        SelectedCalendarDate = dateKey;
        CalendarScrollRequested?.Invoke(dateKey);
    }

    /// <summary>Day-cell click from the month grid: adjacent-month cells
    /// switch the displayed month first (§4b).</summary>
    public async Task SelectCalendarDateFromGridAsync(string dateKey)
    {
        var date = DateTime.ParseExact(dateKey, "yyyy-MM-dd", CultureInfo.InvariantCulture);
        if (date.Year != CalendarYear || date.Month != CalendarMonth)
        {
            CalendarYear = date.Year;
            CalendarMonth = date.Month;
            SelectedCalendarDate = dateKey;
            await RefreshAsync();
        }
        else
        {
            SelectCalendarDate(dateKey);
        }

        CalendarScrollRequested?.Invoke(dateKey);
    }

    private void UpdateTitle()
    {
        if (!string.IsNullOrEmpty(_searchKeyword))
        {
            CurrentTitle = $"{T("searchHint")}: {_searchKeyword}";
            return;
        }

        CurrentTitle = CurrentView switch
        {
            TaskViewType.Today => T("navToday"),
            TaskViewType.Planned => T("navPlanned"),
            TaskViewType.All => T("navAll"),
            TaskViewType.Completed => T("navCompleted"),
            TaskViewType.Calendar => T("navCalendar"),
            TaskViewType.List => ListCollection.FirstOrDefault(l => l.Id == CurrentListId)?.Name
                ?? $"List {CurrentListId}",
            _ => "",
        };
    }

    // ---------------- status line ----------------

    private void RefreshPersistentStatus()
    {
        if (!IsConnected)
        {
            _persistentStatus = T("statusDatabaseNotConnected");
        }
        else
        {
            _persistentStatus = CurrentView switch
            {
                TaskViewType.Today => T("statusShowToday"),
                TaskViewType.Planned => T("statusShowPlanned"),
                TaskViewType.All => T("statusShowAll"),
                TaskViewType.Completed => T("statusShowCompleted"),
                TaskViewType.Calendar => T("statusShowCalendar"),
                TaskViewType.List => string.Format(
                    CultureInfo.InvariantCulture, T("statusSwitchList"),
                    ListCollection.FirstOrDefault(l => l.Id == CurrentListId)?.Name ?? $"{CurrentListId}"),
                _ => "",
            };
        }

        StatusMessage = _persistentStatus;
        UpdateTitle();
    }

    public void ShowTransientStatus(string message)
    {
        StatusMessage = message;
        _statusTimer?.Stop();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            RefreshPersistentStatus();
        };
        timer.Start();
        _statusTimer = timer;
    }

    // ---------------- selection ----------------

    public async Task SelectViewAsync(TaskViewType view, int? listId = null)
    {
        if (!IsConnected)
        {
            return;
        }

        CurrentView = view;
        CurrentListId = listId;
        if (view == TaskViewType.List && listId is not null)
        {
            _config.LastSelectedListId = listId.Value;
            _config.Save();
        }

        if (view == TaskViewType.Calendar)
        {
            var now = DateTime.Now;
            var entering = CalendarYear == 0;
            if (entering || CalendarYear != now.Year || CalendarMonth != now.Month)
            {
                CalendarYear = now.Year;
                CalendarMonth = now.Month;
            }

            var today = now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            if (entering || SelectedCalendarDate is null)
            {
                SelectedCalendarDate = today;
            }
        }

        await RefreshAsync();
        RefreshPersistentStatus();
    }

    public async Task SetSearchAsync(string? keyword)
    {
        _searchKeyword = string.IsNullOrWhiteSpace(keyword) ? null : keyword;
        await RefreshAsync();
        RefreshPersistentStatus();
    }

    public async Task ToggleShowCompletedAsync()
    {
        ShowCompletedTasks = !ShowCompletedTasks;
        await RefreshAsync();
    }

    // ---------------- task operations ----------------

    /// <summary>Quick add: extracts a trailing date/time command (CLI semantics:
    /// pure-date intent clears the time — the 0.6.x GUI quirk is fixed).</summary>
    public async Task QuickAddAsync(string rawText)
    {
        if (!IsConnected)
        {
            return;
        }

        var trimmed = rawText.Trim();
        if (trimmed.Length == 0)
        {
            return;
        }

        var (text, timeCommand) = DateParser.ExtractTimeCommand(trimmed);
        string? dueDate = null;
        string? dueTime = null;
        if (timeCommand is not null)
        {
            var parsed = DateParser.Parse(timeCommand);
            if (parsed is not null)
            {
                var isDateOnly = !timeCommand.StartsWith('@')
                    && timeCommand.Length > 0
                    && timeCommand[^1] is 'd' or 'w' or 'M';
                dueDate = DateParser.ExtractDateOnly(parsed);
                if (!isDateOnly)
                {
                    dueTime = DateParser.ExtractTimeOnly(parsed);
                }
            }
        }

        int listId;
        if (CurrentView == TaskViewType.List && CurrentListId is not null)
        {
            listId = CurrentListId.Value;
        }
        else
        {
            var first = ListCollection.FirstOrDefault();
            if (first is null)
            {
                ShowTransientStatus(T("taskCreateListFirst"));
                return;
            }

            listId = first.Id;
        }

        var task = new TaskItem(0, listId, text.Length > 0 ? text : trimmed,
            DateTime.Now.ToString("o", CultureInfo.InvariantCulture), dueDate, dueTime);
        try
        {
            await Tasks.AddTaskAsync(task);
            await RefreshCountsAsync();
            await RefreshAsync();
            ShowTransientStatus(T("statusTaskAdded"));
        }
        catch (ArgumentException ex)
        {
            ShowTransientStatus(ex.Message);
        }
    }

    public async Task ToggleCompletedAsync(TaskItem task)
    {
        await Tasks.ToggleTaskCompletedAsync(task.Id);
        await RefreshCountsAsync();
        await RefreshAsync();
        ShowTransientStatus(T("statusUpdateTaskState"));
    }

    public async Task UpdateTaskAsync(TaskItem task)
    {
        try
        {
            await Tasks.UpdateTaskAsync(task);
            await RefreshCountsAsync();
            await RefreshAsync();
            ShowTransientStatus(T("statusTaskUpdated"));
        }
        catch (ArgumentException ex)
        {
            ShowTransientStatus(string.Format(CultureInfo.InvariantCulture, T("taskUpdateFailed"), ex.Message));
        }
    }

    public async Task DeleteTaskAsync(TaskItem task)
    {
        await Tasks.DeleteTaskAsync(task.Id);
        await RefreshCountsAsync();
        await RefreshAsync();
        ShowTransientStatus(T("statusTaskDeleted"));
    }

    public async Task MoveTaskToListAsync(TaskItem task, TodoList list)
    {
        task.ListId = list.Id;
        await Tasks.UpdateTaskAsync(task);
        await RefreshCountsAsync();
        await RefreshAsync();
        ShowTransientStatus(string.Format(CultureInfo.InvariantCulture, T("statusTaskMoved"), list.Name));
    }

    // ---------------- list operations ----------------

    public async Task CreateListAsync(string name, string? icon, int? color)
    {
        try
        {
            var id = await Lists.AddListAsync(name, icon, color);
            await ReloadListsAsync();
            await RefreshCountsAsync();
            await SelectViewAsync(TaskViewType.List, id);
            ShowTransientStatus(string.Format(CultureInfo.InvariantCulture, T("statusCreateList"), name.Trim()));
        }
        catch (ArgumentException ex)
        {
            ShowTransientStatus(ex.Message);
        }
    }

    public async Task UpdateListAsync(int id, string name, string? icon, int? color,
        bool clearIcon, bool clearColor)
    {
        try
        {
            await Lists.UpdateListAsync(id, name, icon, color, clearIcon, clearColor);
            await ReloadListsAsync();
            await RefreshCountsAsync();
            await RefreshAsync();
        }
        catch (ArgumentException ex)
        {
            ShowTransientStatus(ex.Message);
        }
    }

    public async Task DeleteListAsync(TodoList list)
    {
        await Lists.DeleteListAsync(list.Id);
        await ReloadListsAsync();
        await RefreshCountsAsync();
        if (CurrentView == TaskViewType.List && CurrentListId == list.Id)
        {
            await SelectViewAsync(TaskViewType.All);
        }
        else
        {
            await RefreshAsync();
        }

        ShowTransientStatus(T("statusDeleteList"));
    }

    // ---------------- display formatting ----------------

    public string FormatDateOnly(string? dueDate)
    {
        return DateParser.FormatDateOnlyForDisplay(
            dueDate,
            () => T("navToday"),
            () => T("dateTomorrow"),
            () => T("dateYesterday"));
    }
}
