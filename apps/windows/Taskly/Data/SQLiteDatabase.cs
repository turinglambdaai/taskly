using System.Globalization;
using Microsoft.Data.Sqlite;
using Taskly.Models;

namespace Taskly.Data;

/// <summary>
/// SQLite database service (DATA-FORMAT.md, schema v4). Port of the proven
/// 0.6.x implementation — table layout, migrations, and every query's
/// WHERE/ORDER BY are unchanged so existing .db files open in place.
/// </summary>
public sealed class SQLiteDatabase : IDisposable
{
    /// <summary>Schema version pragma; migrations run in lockstep across platforms.</summary>
    private const int DatabaseVersion = 4;

    private const string TableLists = "lists";
    private const string TableTasks = "tasks";

    private SqliteConnection? _connection;
    private string? _customDatabasePath;

    public bool IsConnected => _connection is not null;

    public void SetDatabasePath(string path)
    {
        _customDatabasePath = path;
        Close();
    }

    public string GetDatabasePath() => _customDatabasePath ?? PathUtils.GetDefaultDatabasePath();

    public async Task EnsureConnectedAsync()
    {
        if (_connection is not null)
        {
            return;
        }

        var dbPath = GetDatabasePath();
        var dir = Path.GetDirectoryName(dbPath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        var connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = dbPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
        }.ToString();

        _connection = new SqliteConnection(connectionString);
        await _connection.OpenAsync();

        // WAL: safer when the .db lives in a cloud-synced folder; persistent.
        await using (var pragmaCmd = _connection.CreateCommand())
        {
            pragmaCmd.CommandText = "PRAGMA journal_mode=WAL;";
            await pragmaCmd.ExecuteNonQueryAsync();
        }

        await CreateOrUpgradeAsync(_connection);
        await EnsureColumnsExistAsync(_connection);
    }

    private async Task CreateAllAsync(SqliteConnection db, SqliteTransaction? transaction = null)
    {
        await ExecuteAsync(db, $"""
            CREATE TABLE {TableLists} (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                icon TEXT,
                color INTEGER,
                created_at TEXT NOT NULL
            )
            """, null, transaction);

        await ExecuteAsync(db, $"""
            CREATE TABLE {TableTasks} (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                list_id INTEGER,
                text TEXT NOT NULL,
                due_date TEXT,
                due_time TEXT,
                completed INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                notes TEXT,
                FOREIGN KEY (list_id) REFERENCES {TableLists} (id)
            )
            """, null, transaction);

        await CreateIndexesAsync(db, transaction);

        // Default seeded list (byte-compatible; name is intentionally not localized).
        await ExecuteAsync(db,
            $"INSERT INTO {TableLists} (name, icon, color, created_at) VALUES (@name, @icon, @color, @createdAt)",
            new Dictionary<string, object?>
            {
                ["name"] = "工作",
                ["icon"] = Models.TodoList.DefaultIcon,
                ["color"] = Models.TodoList.DefaultColor,
                ["createdAt"] = DateTime.Now.ToString("o", CultureInfo.InvariantCulture),
            }, transaction);
    }

    private async Task CreateIndexesAsync(SqliteConnection db, SqliteTransaction? transaction = null)
    {
        await ExecuteAsync(db, $"CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON {TableTasks}(list_id)", null, transaction);
        await ExecuteAsync(db, $"CREATE INDEX IF NOT EXISTS idx_tasks_completed ON {TableTasks}(completed)", null, transaction);
        await ExecuteAsync(db, $"CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON {TableTasks}(due_date)", null, transaction);
    }

    private async Task CreateOrUpgradeAsync(SqliteConnection db)
    {
        var oldVersion = await GetUserVersionAsync(db);

        await using (var transaction = db.BeginTransaction())
        {
            try
            {
                if (oldVersion == 0)
                {
                    await CreateAllAsync(db, transaction);
                }
                else
                {
                    if (oldVersion < 2)
                    {
                        await CreateIndexesAsync(db, transaction);
                    }

                    if (oldVersion < 3)
                    {
                        await EnsureColumnAsync(db, TableLists, "icon", "TEXT", transaction);
                        await EnsureColumnAsync(db, TableLists, "color", "INTEGER", transaction);
                    }

                    if (oldVersion < 4)
                    {
                        await EnsureColumnAsync(db, TableTasks, "due_time", "TEXT", transaction);
                        await EnsureColumnAsync(db, TableTasks, "notes", "TEXT", transaction);
                    }
                }

                await transaction.CommitAsync();
            }
            catch
            {
                await transaction.RollbackAsync();
                throw;
            }
        }

        // user_version must be set outside a transaction (no-op inside one).
        await using (var verCmd = db.CreateCommand())
        {
            verCmd.CommandText = $"PRAGMA user_version = {DatabaseVersion}";
            await verCmd.ExecuteNonQueryAsync();
        }
    }

    private async Task EnsureColumnsExistAsync(SqliteConnection db)
    {
        try
        {
            await EnsureColumnAsync(db, TableLists, "icon", "TEXT");
            await EnsureColumnAsync(db, TableLists, "color", "INTEGER");
        }
        catch
        {
            // Belt-and-braces check; never fatal.
        }
    }

    private async Task EnsureColumnAsync(SqliteConnection db, string table, string column, string type, SqliteTransaction? transaction = null)
    {
        var columns = await QueryAsync(db, $"PRAGMA table_info({table})", null);
        var hasColumn = columns.Any(r => r.TryGetValue("name", out var v) && v?.ToString() == column);
        if (!hasColumn)
        {
            await ExecuteAsync(db, $"ALTER TABLE {table} ADD COLUMN {column} {type}", null, transaction);
        }
    }

    private static async Task<int> GetUserVersionAsync(SqliteConnection db)
    {
        await using var cmd = db.CreateCommand();
        cmd.CommandText = "PRAGMA user_version";
        var result = await cmd.ExecuteScalarAsync();
        return result is long l ? (int)l : 0;
    }

    // ------------------------
    // Lists
    // ------------------------

    public async Task<List<TodoList>> GetAllListsAsync()
    {
        await EnsureConnectedAsync();
        var rows = await QueryAsync(_connection!, $"SELECT * FROM {TableLists}", null);
        return rows.Select(TodoListFromRow).ToList();
    }

    public async Task<TodoList?> GetListByIdAsync(int id)
    {
        await EnsureConnectedAsync();
        var rows = await QueryAsync(_connection!,
            $"SELECT * FROM {TableLists} WHERE id = @id",
            new Dictionary<string, object?> { ["id"] = id });
        return rows.Count > 0 ? TodoListFromRow(rows[0]) : null;
    }

    /// <summary>Case-sensitive exact match; null when absent.</summary>
    public async Task<TodoList?> GetListByNameAsync(string name)
    {
        await EnsureConnectedAsync();
        var rows = await QueryAsync(_connection!,
            $"SELECT * FROM {TableLists} WHERE name = @name LIMIT 1",
            new Dictionary<string, object?> { ["name"] = name });
        return rows.Count > 0 ? TodoListFromRow(rows[0]) : null;
    }

    public async Task<int> AddListAsync(string name, string? icon = null, int? color = null)
    {
        await EnsureConnectedAsync();
        icon ??= Models.TodoList.DefaultIcon;
        color ??= Models.TodoList.DefaultColor;

        var createdAt = DateTime.Now.ToString("o", CultureInfo.InvariantCulture);
        return await InsertAndReturnIdAsync(_connection!,
            $"INSERT INTO {TableLists} (name, created_at, icon, color) VALUES (@name, @createdAt, @icon, @color)",
            new Dictionary<string, object?>
            {
                ["name"] = name,
                ["createdAt"] = createdAt,
                ["icon"] = icon,
                ["color"] = color,
            });
    }

    public async Task<int> UpdateListAsync(
        int id,
        string name,
        string? icon = null,
        int? color = null,
        bool clearIcon = false,
        bool clearColor = false)
    {
        await EnsureConnectedAsync();
        var sb = new System.Text.StringBuilder();
        sb.Append("UPDATE ").Append(TableLists).Append(" SET name = @name");

        if (clearIcon)
        {
            sb.Append(", icon = NULL");
        }
        else if (icon is not null)
        {
            sb.Append(", icon = @icon");
        }

        if (clearColor)
        {
            sb.Append(", color = NULL");
        }
        else if (color is not null)
        {
            sb.Append(", color = @color");
        }

        sb.Append(" WHERE id = @id");

        var p = new Dictionary<string, object?> { ["name"] = name, ["id"] = id };
        if (!clearIcon && icon is not null)
        {
            p["icon"] = icon;
        }

        if (!clearColor && color is not null)
        {
            p["color"] = color;
        }

        return await ExecuteAsync(_connection!, sb.ToString(), p);
    }

    /// <summary>Deletes the list's tasks first, then the list.</summary>
    public async Task<int> DeleteListAsync(int id)
    {
        await EnsureConnectedAsync();
        await ExecuteAsync(_connection!,
            $"DELETE FROM {TableTasks} WHERE list_id = @id",
            new Dictionary<string, object?> { ["id"] = id });
        return await ExecuteAsync(_connection!,
            $"DELETE FROM {TableLists} WHERE id = @id",
            new Dictionary<string, object?> { ["id"] = id });
    }

    // ------------------------
    // Tasks (queries)
    // ------------------------

    private const string TaskSelectBase = $"""
        SELECT t.*, l.name AS list_name
        FROM {TableTasks} t
        LEFT JOIN {TableLists} l ON t.list_id = l.id
        """;

    public async Task<List<TaskItem>> GetAllTasksAsync()
    {
        await EnsureConnectedAsync();
        var rows = await QueryAsync(_connection!, $"{TaskSelectBase}", null);
        return rows.Select(TaskFromRow).ToList();
    }

    /// <summary>All incomplete tasks with a due date (reminder source).</summary>
    public async Task<List<TaskItem>> GetAllIncompleteTasksWithDueDateAsync()
    {
        await EnsureConnectedAsync();
        var rows = await QueryAsync(_connection!,
            $"{TaskSelectBase} WHERE t.completed = 0 AND t.due_date IS NOT NULL", null);
        return rows.Select(TaskFromRow).ToList();
    }

    public async Task<List<TaskItem>> GetTasksByListAsync(int listId, int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.list_id = @listId AND t.completed = 0 ORDER BY t.id DESC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["listId"] = listId, ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> GetCompletedTasksByListAsync(int listId, int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.list_id = @listId AND t.completed = 1 LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["listId"] = listId, ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> GetTasksByListIncludingCompletedAsync(int listId, int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.list_id = @listId ORDER BY t.completed ASC, t.id DESC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["listId"] = listId, ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> GetAllTasksIncludingCompletedAsync(int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} ORDER BY t.completed ASC, t.id DESC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> GetTodayTasksAsync(int limit = 1000, int offset = 0)
    {
        var today = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return await QueryTasksAsync(
            $"{TaskSelectBase} WHERE date(t.due_date) = @today AND t.completed = 0 ORDER BY t.id DESC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["today"] = today, ["limit"] = limit, ["offset"] = offset });
    }

    public async Task<List<TaskItem>> GetTodayTasksIncludingCompletedAsync(int limit = 1000, int offset = 0)
    {
        var today = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return await QueryTasksAsync(
            $"{TaskSelectBase} WHERE date(t.due_date) = @today ORDER BY t.completed ASC, t.id DESC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["today"] = today, ["limit"] = limit, ["offset"] = offset });
    }

    public async Task<List<TaskItem>> GetPlannedTasksAsync(int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.due_date IS NOT NULL AND t.completed = 0 ORDER BY t.due_date ASC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> GetPlannedTasksIncludingCompletedAsync(int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.due_date IS NOT NULL ORDER BY t.completed ASC, t.due_date ASC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> GetIncompleteTasksAsync(int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.completed = 0 ORDER BY t.id DESC LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> GetCompletedTasksAsync(int limit = 1000, int offset = 0) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.completed = 1 LIMIT @limit OFFSET @offset",
            new Dictionary<string, object?> { ["limit"] = limit, ["offset"] = offset });

    public async Task<List<TaskItem>> SearchTasksAsync(string keyword) =>
        await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.text LIKE @keyword",
            new Dictionary<string, object?> { ["keyword"] = $"%{keyword}%" });

    public async Task<TaskItem?> GetTaskByIdAsync(int id)
    {
        await EnsureConnectedAsync();
        var rows = await QueryTasksAsync(
            $"{TaskSelectBase} WHERE t.id = @id",
            new Dictionary<string, object?> { ["id"] = id });
        return rows.Count > 0 ? rows[0] : null;
    }

    // ------------------------
    // Tasks (counts)
    // ------------------------

    public async Task<int> GetTaskCountByListAsync(int listId)
    {
        await EnsureConnectedAsync();
        return await CountAsync(_connection!,
            $"SELECT COUNT(*) FROM {TableTasks} WHERE list_id = @listId AND completed = 0",
            new Dictionary<string, object?> { ["listId"] = listId });
    }

    public async Task<int> GetIncompleteTaskCountAsync()
    {
        await EnsureConnectedAsync();
        return await CountAsync(_connection!, $"SELECT COUNT(*) FROM {TableTasks} WHERE completed = 0", null);
    }

    public async Task<int> GetCompletedTaskCountAsync()
    {
        await EnsureConnectedAsync();
        return await CountAsync(_connection!, $"SELECT COUNT(*) FROM {TableTasks} WHERE completed = 1", null);
    }

    public async Task<int> GetTodayTaskCountAsync()
    {
        await EnsureConnectedAsync();
        var today = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return await CountAsync(_connection!,
            $"SELECT COUNT(*) FROM {TableTasks} WHERE date(due_date) = @today AND completed = 0",
            new Dictionary<string, object?> { ["today"] = today });
    }

    public async Task<int> GetPlannedTaskCountAsync()
    {
        await EnsureConnectedAsync();
        return await CountAsync(_connection!,
            $"SELECT COUNT(*) FROM {TableTasks} WHERE due_date IS NOT NULL AND completed = 0", null);
    }

    // ------------------------
    // Tasks (writes)
    // ------------------------

    public async Task<int> AddTaskAsync(TaskItem task)
    {
        await EnsureConnectedAsync();
        return await InsertAndReturnIdAsync(_connection!,
            $"INSERT INTO {TableTasks} (list_id, text, due_date, due_time, completed, created_at, notes) " +
            "VALUES (@listId, @text, @dueDate, @dueTime, @completed, @createdAt, @notes)",
            new Dictionary<string, object?>
            {
                ["listId"] = task.ListId,
                ["text"] = task.Text,
                ["dueDate"] = (object?)task.DueDate ?? DBNull.Value,
                ["dueTime"] = (object?)task.DueTime ?? DBNull.Value,
                ["completed"] = task.Completed ? 1 : 0,
                ["createdAt"] = task.CreatedAt,
                ["notes"] = (object?)task.Notes ?? DBNull.Value,
            });
    }

    public async Task<int> UpdateTaskAsync(TaskItem task)
    {
        await EnsureConnectedAsync();
        return await ExecuteAsync(_connection!, $"""
            UPDATE {TableTasks}
            SET list_id = @listId, text = @text, due_date = @dueDate, due_time = @dueTime,
                completed = @completed, notes = @notes
            WHERE id = @id
            """, new Dictionary<string, object?>
        {
            ["listId"] = task.ListId,
            ["text"] = task.Text,
            ["dueDate"] = (object?)task.DueDate ?? DBNull.Value,
            ["dueTime"] = (object?)task.DueTime ?? DBNull.Value,
            ["completed"] = task.Completed ? 1 : 0,
            ["notes"] = (object?)task.Notes ?? DBNull.Value,
            ["id"] = task.Id,
        });
    }

    /// <summary>Read-then-flip toggle (reference semantics).</summary>
    public async Task<int> ToggleTaskCompletedAsync(int id)
    {
        await EnsureConnectedAsync();
        var rows = await QueryAsync(_connection!,
            $"SELECT completed FROM {TableTasks} WHERE id = @id",
            new Dictionary<string, object?> { ["id"] = id });
        if (rows.Count == 0)
        {
            return 0;
        }

        var current = Convert.ToInt32(rows[0]["completed"], CultureInfo.InvariantCulture);
        return await ExecuteAsync(_connection!,
            $"UPDATE {TableTasks} SET completed = @value WHERE id = @id",
            new Dictionary<string, object?> { ["value"] = current == 1 ? 0 : 1, ["id"] = id });
    }

    /// <summary>Idempotent completion set; returns affected rows (0 = missing).</summary>
    public async Task<int> SetTaskCompletedAsync(int id, bool completed)
    {
        await EnsureConnectedAsync();
        return await ExecuteAsync(_connection!,
            $"UPDATE {TableTasks} SET completed = @value WHERE id = @id",
            new Dictionary<string, object?>
            {
                ["value"] = completed ? 1 : 0,
                ["id"] = id,
            });
    }

    public async Task<int> DeleteTaskAsync(int id)
    {
        await EnsureConnectedAsync();
        return await ExecuteAsync(_connection!,
            $"DELETE FROM {TableTasks} WHERE id = @id",
            new Dictionary<string, object?> { ["id"] = id });
    }

    // ------------------------
    // Connection management
    // ------------------------

    public async Task CloseAsync()
    {
        if (_connection is not null)
        {
            await _connection.CloseAsync();
            await _connection.DisposeAsync();
            _connection = null;
        }
    }

    public void Close() => CloseAsync().GetAwaiter().GetResult();

    public void Dispose()
    {
        _connection?.Dispose();
        _connection = null;
    }

    // ------------------------
    // Internals
    // ------------------------

    private async Task<List<TaskItem>> QueryTasksAsync(string sql, Dictionary<string, object?>? parameters)
    {
        await EnsureConnectedAsync();
        var rows = await QueryAsync(_connection!, sql, parameters);
        return rows.Select(TaskFromRow).ToList();
    }

    private async Task<int> ExecuteAsync(SqliteConnection db, string sql, Dictionary<string, object?>? parameters = null, SqliteTransaction? transaction = null)
    {
        await using var cmd = db.CreateCommand();
        cmd.CommandText = sql;
        if (transaction is not null)
        {
            cmd.Transaction = transaction;
        }

        AddParameters(cmd, parameters);
        return await cmd.ExecuteNonQueryAsync();
    }

    private async Task<int> CountAsync(SqliteConnection db, string sql, Dictionary<string, object?>? parameters)
    {
        await using var cmd = db.CreateCommand();
        cmd.CommandText = sql;
        AddParameters(cmd, parameters);
        var result = await cmd.ExecuteScalarAsync();
        return result is long l ? (int)l : 0;
    }

    private async Task<int> InsertAndReturnIdAsync(SqliteConnection db, string sql, Dictionary<string, object?> parameters)
    {
        await ExecuteAsync(db, sql, parameters);
        await using var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT last_insert_rowid()";
        var result = await cmd.ExecuteScalarAsync();
        return result is long l ? (int)l : 0;
    }

    private async Task<List<Dictionary<string, object?>>> QueryAsync(
        SqliteConnection db, string sql, Dictionary<string, object?>? parameters)
    {
        await using var cmd = db.CreateCommand();
        cmd.CommandText = sql;
        AddParameters(cmd, parameters);

        var results = new List<Dictionary<string, object?>>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < reader.FieldCount; i++)
            {
                var name = reader.GetName(i);
                row[name] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            }

            results.Add(row);
        }

        return results;
    }

    private static void AddParameters(SqliteCommand cmd, Dictionary<string, object?>? parameters)
    {
        if (parameters is null)
        {
            return;
        }

        foreach (var kv in parameters)
        {
            cmd.Parameters.AddWithValue(kv.Key, kv.Value ?? DBNull.Value);
        }
    }

    private static TodoList TodoListFromRow(Dictionary<string, object?> row)
    {
        var id = Convert.ToInt32(row["id"], CultureInfo.InvariantCulture);
        var name = Convert.ToString(row["name"], CultureInfo.InvariantCulture)!;
        string? icon = row.TryGetValue("icon", out var iv) && iv is not null ? Convert.ToString(iv, CultureInfo.InvariantCulture) : null;
        int? color = null;
        if (row.TryGetValue("color", out var cv) && cv is not null && cv != DBNull.Value)
        {
            color = Convert.ToInt32(cv, CultureInfo.InvariantCulture);
        }

        return new TodoList(id, name, icon, color);
    }

    private static TaskItem TaskFromRow(Dictionary<string, object?> row)
    {
        var id = Convert.ToInt32(row["id"], CultureInfo.InvariantCulture);
        var listId = Convert.ToInt32(row["list_id"], CultureInfo.InvariantCulture);
        var text = Convert.ToString(row["text"], CultureInfo.InvariantCulture)!;
        var createdAt = Convert.ToString(row["created_at"], CultureInfo.InvariantCulture)!;

        string? GetOpt(string key) =>
            row.TryGetValue(key, out var v) && v is not null && v != DBNull.Value
                ? Convert.ToString(v, CultureInfo.InvariantCulture)
                : null;

        var dueDate = GetOpt("due_date");
        var dueTime = GetOpt("due_time");
        var notes = GetOpt("notes");
        var listName = GetOpt("list_name");
        var completed = row.TryGetValue("completed", out var cv) && cv is not null &&
                        Convert.ToInt32(cv, CultureInfo.InvariantCulture) == 1;

        return new TaskItem(id, listId, text, createdAt, dueDate, dueTime, completed, notes, listName);
    }
}
