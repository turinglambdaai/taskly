using Taskly.Data;
using Taskly.Models;
using Taskly.Services;

namespace Taskly.Repositories;

/// <summary>
/// Repositories above SQLiteDatabase: validation + view dispatch.
/// (ListPalette moved here from the legacy ListRepository file.)
/// </summary>
public sealed class TaskRepository
{
    private readonly SQLiteDatabase _db;
    private readonly I18nService _i18n;

    public TaskRepository(SQLiteDatabase db, I18nService i18n)
    {
        _db = db;
        _i18n = i18n;
    }

    /// <summary>View dispatch; 'all' with showCompleted=false = incomplete only.</summary>
    public async Task<List<TaskItem>> GetTasksByViewAsync(
        TaskViewType viewType, int? listId = null,
        int limit = 1000, int offset = 0, bool showCompleted = false)
    {
        return viewType switch
        {
            TaskViewType.Today => showCompleted
                ? await _db.GetTodayTasksIncludingCompletedAsync(limit, offset)
                : await _db.GetTodayTasksAsync(limit, offset),
            TaskViewType.Planned => showCompleted
                ? await _db.GetPlannedTasksIncludingCompletedAsync(limit, offset)
                : await _db.GetPlannedTasksAsync(limit, offset),
            TaskViewType.All => showCompleted
                ? await _db.GetAllTasksIncludingCompletedAsync(limit, offset)
                : await _db.GetIncompleteTasksAsync(limit, offset),
            TaskViewType.Completed => await _db.GetCompletedTasksAsync(limit, offset),
            TaskViewType.List when listId is not null => showCompleted
                ? await _db.GetTasksByListIncludingCompletedAsync(listId.Value, limit, offset)
                : await _db.GetTasksByListAsync(listId.Value, limit, offset),
            _ => await _db.GetIncompleteTasksAsync(limit, offset),
        };
    }

    public async Task<int> AddTaskAsync(TaskItem task)
    {
        var error = ValidationHelper.ValidateTaskText(task.Text, _i18n);
        if (error is not null)
        {
            throw new ArgumentException(error.Message);
        }

        return await _db.AddTaskAsync(task);
    }

    public async Task<int> UpdateTaskAsync(TaskItem task)
    {
        var error = ValidationHelper.ValidateTaskText(task.Text, _i18n);
        if (error is not null)
        {
            throw new ArgumentException(error.Message);
        }

        return await _db.UpdateTaskAsync(task);
    }

    public Task<int> ToggleTaskCompletedAsync(int id) => _db.ToggleTaskCompletedAsync(id);
    public Task<int> SetTaskCompletedAsync(int id, bool completed) => _db.SetTaskCompletedAsync(id, completed);
    public Task<int> DeleteTaskAsync(int id) => _db.DeleteTaskAsync(id);

    public async Task<List<TaskItem>> SearchTasksAsync(string keyword)
    {
        if (string.IsNullOrWhiteSpace(keyword))
        {
            return new List<TaskItem>();
        }

        return await _db.SearchTasksAsync(keyword.Trim());
    }

    /// <summary>Calendar view data (PRODUCT-SPEC §4b); the view groups and
    /// renders client-side.</summary>
    public Task<List<TaskItem>> GetTasksInRangeAsync(string startDate, string endDate, bool includeCompleted = false) =>
        _db.GetTasksInRangeAsync(startDate, endDate, includeCompleted);

    public Task<List<DueDayCount>> GetDueDayCountsAsync(string startDate, string endDate) =>
        _db.GetDueDayCountsAsync(startDate, endDate);

    public Task<TaskItem?> GetTaskByIdAsync(int id) => _db.GetTaskByIdAsync(id);

    public Task<int> GetTaskCountByListAsync(int listId) => _db.GetTaskCountByListAsync(listId);
    public Task<int> GetIncompleteTaskCountAsync() => _db.GetIncompleteTaskCountAsync();
    public Task<int> GetCompletedTaskCountAsync() => _db.GetCompletedTaskCountAsync();
    public Task<int> GetTodayTaskCountAsync() => _db.GetTodayTaskCountAsync();
    public Task<int> GetPlannedTaskCountAsync() => _db.GetPlannedTaskCountAsync();
}

public sealed class ListRepository
{
    private readonly SQLiteDatabase _db;
    private readonly I18nService _i18n;

    public ListRepository(SQLiteDatabase db, I18nService i18n)
    {
        _db = db;
        _i18n = i18n;
    }

    public Task<List<TodoList>> GetAllListsAsync() => _db.GetAllListsAsync();
    public Task<TodoList?> GetListByIdAsync(int id) => _db.GetListByIdAsync(id);
    public Task<TodoList?> GetListByNameAsync(string name) => _db.GetListByNameAsync(name);

    public async Task<int> AddListAsync(string name, string? icon = null, int? color = null)
    {
        var error = ValidationHelper.ValidateListName(name, _i18n);
        if (error is not null)
        {
            throw new ArgumentException(error.Message);
        }

        return await _db.AddListAsync(name.Trim(), icon, color);
    }

    public async Task<int> UpdateListAsync(int id, string name, string? icon = null, int? color = null,
        bool clearIcon = false, bool clearColor = false)
    {
        var error = ValidationHelper.ValidateListName(name, _i18n);
        if (error is not null)
        {
            throw new ArgumentException(error.Message);
        }

        return await _db.UpdateListAsync(id, name.Trim(), icon, color, clearIcon, clearColor);
    }

    public async Task<int> DeleteListAsync(int id) => await _db.DeleteListAsync(id);

    /// <summary>Default list = the first one.</summary>
    public async Task<TodoList?> GetDefaultListAsync()
    {
        var lists = await GetAllListsAsync();
        return lists.Count > 0 ? lists[0] : null;
    }
}

/// <summary>Preset palette + emoji categories (fixed order, contract).</summary>
public static class ListPalette
{
    public static readonly string[] Colors =
    {
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00", "#4CD964",
        "#5AC8FA", "#5856D6", "#FF2D55", "#8E8E93", "#C7C7CC",
    };

    public static readonly string[][] EmojiCategories =
    {
        new[] { "📋", "📝", "✅", "🎯", "💡", "📌", "🔖", "📎" },
        new[] { "🏠", "🏢", "💼", "📱", "💻", "🎨", "📚", "🎓" },
        new[] { "❤️", "⭐", "🌟", "🔥", "💪", "🎉", "🎊", "🏆" },
        new[] { "🛒", "🛍️", "🍔", "☕", "🍕", "🥤", "🎮", "🎬" },
        new[] { "✈️", "🚗", "🚴", "🏃", "⚽", "🏀", "🎸", "🎵" },
        new[] { "💰", "💳", "📊", "📈", "💼", "📧", "📅", "⏰" },
    };
}
