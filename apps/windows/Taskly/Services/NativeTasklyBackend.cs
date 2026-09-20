using Taskly.Data;
using Taskly.Models;
using Taskly.Repositories;

namespace Taskly.Services;

/// <summary>
/// Transitional adapter around the existing C#/SQLite implementation.
/// It preserves current shipping behavior while MainViewModel is decoupled
/// from storage details. RivetTasklyBackend will implement the same port.
/// </summary>
public sealed class NativeTasklyBackend : ITasklyBackend
{
    private readonly SQLiteDatabase _db = new();
    private readonly TaskRepository _tasks;
    private readonly ListRepository _lists;

    public NativeTasklyBackend(I18nService i18n)
    {
        _tasks = new TaskRepository(_db, i18n);
        _lists = new ListRepository(_db, i18n);
    }

    public bool IsConnected => _db.IsConnected;

    public async Task<TasklySnapshot> OpenAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _db.Close();
        _db.SetDatabasePath(path);
        await _db.EnsureConnectedAsync();
        return await LoadSnapshotAsync(TaskViewType.All, null, false, cancellationToken);
    }

    public async Task CloseAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await _db.CloseAsync();
    }

    public async Task<TasklySnapshot> LoadSnapshotAsync(
        TaskViewType view,
        int? listId,
        bool showCompleted,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var lists = await _lists.GetAllListsAsync();
        foreach (var list in lists)
        {
            cancellationToken.ThrowIfCancellationRequested();
            list.PendingCount = await _tasks.GetTaskCountByListAsync(list.Id);
        }

        var tasks = await _tasks.GetTasksByViewAsync(
            view,
            listId,
            showCompleted: showCompleted);
        var counts = new TasklyCounts(
            await _tasks.GetTodayTaskCountAsync(),
            await _tasks.GetPlannedTaskCountAsync(),
            await _tasks.GetIncompleteTaskCountAsync(),
            await _tasks.GetCompletedTaskCountAsync());
        return new TasklySnapshot(lists, tasks, counts);
    }

    public async Task<IReadOnlyList<TaskItem>> SearchTasksAsync(
        string keyword,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return await _tasks.SearchTasksAsync(keyword);
    }

    public async Task<TaskItem> AddTaskAsync(
        TaskItem task,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var id = await _tasks.AddTaskAsync(task);
        return await RequireTaskAsync(id);
    }

    public async Task<TaskItem> UpdateTaskAsync(
        TaskItem task,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await _tasks.UpdateTaskAsync(task);
        return await RequireTaskAsync(task.Id);
    }

    public async Task<TaskItem> SetCompletedAsync(
        int id,
        bool completed,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await _tasks.SetTaskCompletedAsync(id, completed);
        return await RequireTaskAsync(id);
    }

    public async Task<bool> DeleteTaskAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return await _tasks.DeleteTaskAsync(id) > 0;
    }

    public async Task<TodoList> CreateListAsync(
        string name,
        string? icon,
        int? color,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var id = await _lists.AddListAsync(name, icon, color);
        return await RequireListAsync(id);
    }

    public async Task<TodoList> UpdateListAsync(
        TodoList list,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await _lists.UpdateListAsync(
            list.Id,
            list.Name,
            list.Icon,
            list.Color,
            clearIcon: list.Icon is null,
            clearColor: list.Color is null);
        return await RequireListAsync(list.Id);
    }

    public async Task<bool> DeleteListAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return await _lists.DeleteListAsync(id) > 0;
    }

    public async Task<IReadOnlyList<TaskItem>> GetDueTasksAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return await _db.GetAllIncompleteTasksWithDueDateAsync();
    }

    private async Task<TaskItem> RequireTaskAsync(int id)
    {
        return await _tasks.GetTaskByIdAsync(id)
            ?? throw new InvalidOperationException($"Task {id} was not found after mutation.");
    }

    private async Task<TodoList> RequireListAsync(int id)
    {
        return await _lists.GetListByIdAsync(id)
            ?? throw new InvalidOperationException($"List {id} was not found after mutation.");
    }

    public async ValueTask DisposeAsync()
    {
        await _db.CloseAsync();
    }
}
