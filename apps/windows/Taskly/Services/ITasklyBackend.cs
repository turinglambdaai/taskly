using Taskly.Models;

namespace Taskly.Services;

/// <summary>
/// Platform UI boundary for Taskly application data and behavior.
///
/// The WinUI layer depends on this port rather than SQLite/repositories or a
/// Rivet transport. The current native implementation and the Racket/Rivet
/// implementation must satisfy the same contract so migration remains
/// reversible and testable.
/// </summary>
public interface ITasklyBackend : IAsyncDisposable
{
    bool IsConnected { get; }

    Task<TasklySnapshot> OpenAsync(string path, CancellationToken cancellationToken = default);
    Task CloseAsync(CancellationToken cancellationToken = default);

    Task<TasklySnapshot> LoadSnapshotAsync(
        TaskViewType view,
        int? listId,
        bool showCompleted,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<TaskItem>> SearchTasksAsync(
        string keyword,
        CancellationToken cancellationToken = default);

    Task<TaskItem> AddTaskAsync(TaskItem task, CancellationToken cancellationToken = default);
    Task<TaskItem> UpdateTaskAsync(TaskItem task, CancellationToken cancellationToken = default);
    Task<TaskItem> SetCompletedAsync(int id, bool completed, CancellationToken cancellationToken = default);
    Task<bool> DeleteTaskAsync(int id, CancellationToken cancellationToken = default);

    Task<TodoList> CreateListAsync(
        string name,
        string? icon,
        int? color,
        CancellationToken cancellationToken = default);
    Task<TodoList> UpdateListAsync(TodoList list, CancellationToken cancellationToken = default);
    Task<bool> DeleteListAsync(int id, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<TaskItem>> GetDueTasksAsync(CancellationToken cancellationToken = default);
}

public sealed record TasklyCounts(int Today, int Planned, int All, int Completed);

public sealed record TasklySnapshot(
    IReadOnlyList<TodoList> Lists,
    IReadOnlyList<TaskItem> Tasks,
    TasklyCounts Counts);
