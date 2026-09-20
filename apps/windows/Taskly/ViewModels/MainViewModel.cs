using System.Collections.ObjectModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Xaml;
using Taskly.Models;
using Taskly.Services;

namespace Taskly.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly ITasklyBackend _backend;
    private readonly ConfigService _config = new();
    private readonly I18nService _i18n = I18nService.Instance;
    private DateParser DateParser { get; } = new();

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
        : this(new NativeTasklyBackend(I18nService.Instance))
    {
    }

    public MainViewModel(ITasklyBackend backend)
    {
        _backend = backend ?? throw new ArgumentNullException(nameof(backend));
        _config.Load();
        _i18n.SetLanguage(_config.Language);
        _i18n.LanguageChanged += () =>
        {
            RefreshPersistentStatus();
            LanguageChanged?.Invoke();
        };

        Reminder = new ReminderService(_backend, _i18n);
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
        try
        {
            var snapshot = await _backend.OpenAsync(path);
            IsConnected = _backend.IsConnected;
            Reminder.ResetNotified();

            _config.LastDbPath = path;
            _config.Save();

            ApplySnapshot(snapshot, replaceTasks: true);
            RestoreSelection();
            await RefreshAsync();
            RefreshPersistentStatus();
            ShowTransientStatus(T("statusDatabaseConnected"));
            Reminder.Start();
        }
        catch (Exception ex)
        {
            IsConnected = false;
            ShowTransientStatus(ex.Message);
        }
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
        await _backend.CloseAsync();
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

    private void ApplySnapshot(TasklySnapshot snapshot, bool replaceTasks)
    {
        ListCollection.Clear();
        foreach (var list in snapshot.Lists)
        {
            ListCollection.Add(list);
        }

        TodayCount = snapshot.Counts.Today;
        PlannedCount = snapshot.Counts.Planned;
        AllCount = snapshot.Counts.All;
        CompletedCount = snapshot.Counts.Completed;
        CountsChanged?.Invoke();

        if (replaceTasks)
        {
            TaskItems.Clear();
            foreach (var task in snapshot.Tasks)
            {
                TaskItems.Add(task);
            }
        }
    }

    public async Task ReloadListsAsync()
    {
        if (!IsConnected)
        {
            ListCollection.Clear();
            return;
        }

        var snapshot = await _backend.LoadSnapshotAsync(CurrentView, CurrentListId, ShowCompletedTasks);
        ApplySnapshot(snapshot, replaceTasks: false);
    }

    public async Task RefreshCountsAsync()
    {
        if (!IsConnected)
        {
            TodayCount = 0;
            PlannedCount = 0;
            AllCount = 0;
            CompletedCount = 0;
            CountsChanged?.Invoke();
            return;
        }

        var snapshot = await _backend.LoadSnapshotAsync(CurrentView, CurrentListId, ShowCompletedTasks);
        ApplySnapshot(snapshot, replaceTasks: false);
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
            if (!string.IsNullOrEmpty(_searchKeyword))
            {
                var snapshot = await _backend.LoadSnapshotAsync(CurrentView, CurrentListId, ShowCompletedTasks);
                ApplySnapshot(snapshot, replaceTasks: false);
                var tasks = await _backend.SearchTasksAsync(_searchKeyword);
                TaskItems.Clear();
                foreach (var task in tasks)
                {
                    TaskItems.Add(task);
                }
            }
            else
            {
                var snapshot = await _backend.LoadSnapshotAsync(CurrentView, CurrentListId, ShowCompletedTasks);
                ApplySnapshot(snapshot, replaceTasks: true);
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
            await _backend.AddTaskAsync(task);
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
        await _backend.SetCompletedAsync(task.Id, !task.Completed);
        await RefreshAsync();
        ShowTransientStatus(T("statusUpdateTaskState"));
    }

    public async Task UpdateTaskAsync(TaskItem task)
    {
        try
        {
            await _backend.UpdateTaskAsync(task);
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
        await _backend.DeleteTaskAsync(task.Id);
        await RefreshAsync();
        ShowTransientStatus(T("statusTaskDeleted"));
    }

    public async Task MoveTaskToListAsync(TaskItem task, TodoList list)
    {
        task.ListId = list.Id;
        await _backend.UpdateTaskAsync(task);
        await RefreshAsync();
        ShowTransientStatus(string.Format(CultureInfo.InvariantCulture, T("statusTaskMoved"), list.Name));
    }

    // ---------------- list operations ----------------

    public async Task CreateListAsync(string name, string? icon, int? color)
    {
        try
        {
            var created = await _backend.CreateListAsync(name, icon, color);
            await SelectViewAsync(TaskViewType.List, created.Id);
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
            var existing = ListCollection.FirstOrDefault(list => list.Id == id)
                ?? throw new ArgumentException($"List not found: {id}");
            var replacement = new TodoList(
                id,
                name,
                clearIcon ? null : icon ?? existing.Icon,
                clearColor ? null : color ?? existing.Color);
            await _backend.UpdateListAsync(replacement);
            await RefreshAsync();
        }
        catch (ArgumentException ex)
        {
            ShowTransientStatus(ex.Message);
        }
    }

    public async Task DeleteListAsync(TodoList list)
    {
        await _backend.DeleteListAsync(list.Id);
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
