using System.Collections.ObjectModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Xaml;
using Taskly.Data;
using Taskly.Models;
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

    private string? _searchKeyword;
    private string? _persistentStatus;
    private DispatcherTimer? _statusTimer;

    public event Action? CountsChanged;
    public event Action? LanguageChanged;

    public int TodayCount { get; private set; }
    public int PlannedCount { get; private set; }
    public int AllCount { get; private set; }
    public int CompletedCount { get; private set; }

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
        CurrentView = TaskViewType.All;
        CurrentListId = null;
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
            return;
        }

        try
        {
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
            () => _i18n.Current == "zh" ? "明天" : "Tomorrow",
            () => _i18n.Current == "zh" ? "昨天" : "Yesterday");
    }
}
