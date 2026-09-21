#if TASKLY_RIVET
using Rivet.Runtime;
using Taskly.Models;
using Taskly.RivetGenerated;
using GeneratedList = Taskly.RivetGenerated.TodoList;
using GeneratedTask = Taskly.RivetGenerated.Task;
using ModelList = Taskly.Models.TodoList;
using ModelTask = Taskly.Models.TaskItem;
using AsyncTask = System.Threading.Tasks.Task;

namespace Taskly.Services;

/// <summary>
/// Product backend powered by the shared Racket Taskly service through an
/// in-process Rivet runtime. Native WinUI models remain presentation models;
/// generated Rivet DTOs never leak into XAML/ViewModel code.
/// </summary>
public sealed class RivetTasklyBackend : ITasklyBackend
{
    private readonly string _runtimeRoot;
    private readonly SemaphoreSlim _startupGate = new(1, 1);
    private EmbeddedRivetClient? _client;
    private RivetAPI? _api;
    private bool _connected;
    private bool _disposed;

    public RivetTasklyBackend(string? runtimeRoot = null)
    {
        _runtimeRoot = runtimeRoot ?? Path.Combine(AppContext.BaseDirectory, "rivet");
    }

    public bool IsConnected => _connected;

    public async Task<TasklySnapshot> OpenAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        var api = await GetApiAsync(cancellationToken);
        try
        {
            var snapshot = await api.OpenDatabaseAsync(path, cancellationToken);
            _connected = true;
            return ToModel(snapshot);
        }
        catch
        {
            _connected = false;
            throw;
        }
    }

    public async AsyncTask CloseAsync(CancellationToken cancellationToken = default)
    {
        if (_api is not null && _connected)
        {
            await _api.CloseDatabaseAsync(cancellationToken);
        }
        _connected = false;
    }

    public async Task<TasklySnapshot> LoadSnapshotAsync(
        TaskViewType view,
        int? listId,
        bool showCompleted,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        var snapshot = await api.LoadSnapshotAsync(
            ViewName(view),
            listId,
            showCompleted,
            cancellationToken);
        return ToModel(snapshot);
    }

    public async Task<IReadOnlyList<ModelTask>> SearchTasksAsync(
        string keyword,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        var tasks = await api.SearchTasksAsync(keyword, cancellationToken);
        return tasks.Select(ToModel).ToArray();
    }

    public async Task<ModelTask> AddTaskAsync(
        ModelTask task,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        try
        {
            var created = await api.AddTaskAsync(
                task.Text,
                task.ListId == 0 ? null : task.ListId,
                task.DueDate,
                task.DueTime,
                task.Notes,
                cancellationToken);
            return ToModel(created);
        }
        catch (RivetRemoteException ex)
        {
            throw new ArgumentException(ex.Message, nameof(task), ex);
        }
    }

    public async Task<ModelTask> UpdateTaskAsync(
        ModelTask task,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        try
        {
            var updated = await api.UpdateTaskAsync(ToGenerated(task), cancellationToken);
            return ToModel(updated);
        }
        catch (RivetRemoteException ex)
        {
            throw new ArgumentException(ex.Message, nameof(task), ex);
        }
    }

    public async Task<ModelTask> SetCompletedAsync(
        int id,
        bool completed,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        var task = await api.SetCompletedAsync(id, completed, cancellationToken);
        return ToModel(task);
    }

    public async Task<bool> DeleteTaskAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        return await api.DeleteTaskAsync(id, cancellationToken);
    }

    public async Task<ModelList> CreateListAsync(
        string name,
        string? icon,
        int? color,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        try
        {
            var list = await api.CreateListAsync(name, icon, color, cancellationToken);
            return ToModel(list);
        }
        catch (RivetRemoteException ex)
        {
            throw new ArgumentException(ex.Message, nameof(name), ex);
        }
    }

    public async Task<ModelList> UpdateListAsync(
        ModelList list,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        try
        {
            var updated = await api.UpdateListAsync(ToGenerated(list), cancellationToken);
            return ToModel(updated);
        }
        catch (RivetRemoteException ex)
        {
            throw new ArgumentException(ex.Message, nameof(list), ex);
        }
    }

    public async Task<bool> DeleteListAsync(
        int id,
        CancellationToken cancellationToken = default)
    {
        var api = await RequireConnectedApiAsync(cancellationToken);
        return await api.DeleteListAsync(id, cancellationToken);
    }

    public async Task<IReadOnlyList<ModelTask>> GetDueTasksAsync(
        CancellationToken cancellationToken = default)
    {
        // Planned is exactly the set ReminderService needs to filter against the
        // local wall clock; keeping the final "is due" decision in that service
        // preserves existing notification semantics during migration.
        var api = await RequireConnectedApiAsync(cancellationToken);
        var snapshot = await api.LoadSnapshotAsync("planned", null, false, cancellationToken);
        return snapshot.Tasks.Select(ToModel).ToArray();
    }

    private async Task<RivetAPI> GetApiAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_api is not null)
        {
            return _api;
        }

        await _startupGate.WaitAsync(cancellationToken);
        try
        {
            if (_api is not null)
            {
                return _api;
            }
            _client = await EmbeddedRivetClient.StartAsync(
                new EmbeddedRivetOptions(_runtimeRoot, "backend", "start"),
                cancellationToken);
            _api = new RivetAPI(_client);
            return _api;
        }
        finally
        {
            _startupGate.Release();
        }
    }

    private async Task<RivetAPI> RequireConnectedApiAsync(CancellationToken cancellationToken)
    {
        var api = await GetApiAsync(cancellationToken);
        if (!_connected)
        {
            throw new InvalidOperationException("Taskly database is not open.");
        }
        return api;
    }

    private static string ViewName(TaskViewType view) => view switch
    {
        TaskViewType.Today => "today",
        TaskViewType.Planned => "planned",
        TaskViewType.Completed => "completed",
        _ => "all",
    };

    private static TasklySnapshot ToModel(Snapshot snapshot) => new(
        snapshot.Lists.Select(ToModel).ToArray(),
        snapshot.Tasks.Select(ToModel).ToArray(),
        new TasklyCounts(
            checked((int)snapshot.Counts.Today),
            checked((int)snapshot.Counts.Planned),
            checked((int)snapshot.Counts.All),
            checked((int)snapshot.Counts.Completed)));

    private static ModelTask ToModel(GeneratedTask task) => new(
        checked((int)task.Id),
        checked((int)task.ListId),
        task.Text,
        task.CreatedAt,
        task.DueDate,
        task.DueTime,
        task.Completed,
        task.Notes,
        task.ListName);

    private static GeneratedTask ToGenerated(ModelTask task) => new(
        task.Id,
        task.ListId,
        task.ListName,
        task.Text,
        task.Completed,
        task.DueDate,
        task.DueTime,
        task.Notes,
        task.CreatedAt);

    private static ModelList ToModel(GeneratedList list)
    {
        var model = new ModelList(
            checked((int)list.Id),
            list.Name,
            list.Icon,
            list.Color is null ? null : unchecked((int)list.Color.Value));
        model.PendingCount = checked((int)list.PendingCount);
        return model;
    }

    private static GeneratedList ToGenerated(ModelList list) => new(
        list.Id,
        list.Name,
        list.Icon,
        list.Color,
        list.PendingCount);

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        try
        {
            if (_api is not null && _connected)
            {
                await _api.CloseDatabaseAsync();
            }
        }
        catch
        {
            // Backend shutdown below is authoritative.
        }
        _connected = false;
        if (_client is not null)
        {
            await _client.DisposeAsync();
            _client = null;
            _api = null;
        }
        _startupGate.Dispose();
    }
}
#endif
