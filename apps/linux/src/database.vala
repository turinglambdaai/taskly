// Taskly — SQLite database (contract: DATA-FORMAT.md, schema v4). Port of the
// proven 0.6.x implementation: identical schema, migrations, and every
// query's WHERE/ORDER BY so existing .db files open in place. Uses the
// system libsqlite3 (same strategy as the macOS app).

namespace Taskly {

public class SQLiteDatabase : Object {
    public const int DATABASE_VERSION = 4;

    private Sqlite.Database? db = null;
    private string? custom_path = null;

    public void set_database_path(string path) {
        custom_path = path;
        close();
    }

    public string database_path() {
        return custom_path ?? Config.default_database_path();
    }

    public void ensure_connected() throws GLib.Error {
        if (db != null) {
            return;
        }

        var path = database_path();
        var dir = Path.get_dirname(path);
        if (dir.length > 0) {
            DirUtils.create_with_parents(dir, 0755);
        }

        int rc = Sqlite.Database.open(path, out db);
        if (rc != Sqlite.OK) {
            var message = "Failed to open database: %s".printf(path);
            db = null;
            throw app_error(message, AppErrorType.DATABASE);
        }

        // WAL: safer when the .db lives in a cloud-synced folder; persistent.
        exec("PRAGMA journal_mode=WAL;");

        create_or_upgrade();

        // Belt-and-braces column check (matches reference behavior).
        ensure_column("lists", "icon", "TEXT");
        ensure_column("lists", "color", "INTEGER");
    }

    public void close() {
        db = null; // Sqlite.Database closes on finalize
    }

    public bool is_connected() {
        return db != null;
    }

    /// Live `PRAGMA user_version` probe (conformance tests + CLI).
    public int schema_version() {
        return query_scalar_int("PRAGMA user_version");
    }

    private void create_or_upgrade() throws GLib.Error {
        int old_version = query_scalar_int("PRAGMA user_version");

        if (old_version == 0) {
            exec("""
                CREATE TABLE lists (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    icon TEXT,
                    color INTEGER,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE tasks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    list_id INTEGER,
                    text TEXT NOT NULL,
                    due_date TEXT,
                    due_time TEXT,
                    completed INTEGER DEFAULT 0,
                    created_at TEXT NOT NULL,
                    notes TEXT,
                    FOREIGN KEY (list_id) REFERENCES lists (id)
                );
                CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id);
                CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed);
                CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
            """);
            // Default seeded list (byte-compatible; name intentionally not localized).
            exec("INSERT INTO lists (name, icon, color, created_at) VALUES ('工作', '"
                + DEFAULT_LIST_ICON + "', " + DEFAULT_LIST_COLOR.to_string() + ", '"
                + DateParser.created_at_now() + "')");
        } else {
            if (old_version < 2) {
                exec("""
                    CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id);
                    CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed);
                    CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
                """);
            }
            if (old_version < 3) {
                exec("ALTER TABLE lists ADD COLUMN icon TEXT");
                exec("ALTER TABLE lists ADD COLUMN color INTEGER");
            }
            if (old_version < 4) {
                exec("ALTER TABLE tasks ADD COLUMN due_time TEXT");
                exec("ALTER TABLE tasks ADD COLUMN notes TEXT");
            }
        }

        // user_version must be set outside a transaction.
        exec("PRAGMA user_version = %d".printf(DATABASE_VERSION));
    }

    private void ensure_column(string table, string column, string col_type) {
        var exists = false;
        try {
            exec_scalar("SELECT COUNT(*) FROM pragma_table_info(%s) WHERE name = '%s'"
                .printf(table, column), (row) => {
                exists = row > 0;
            });
        } catch (GLib.Error e) {
            return;
        }
        if (!exists) {
            try {
                exec("ALTER TABLE %s ADD COLUMN %s %s".printf(table, column, col_type));
            } catch (GLib.Error e) {
                // Belt-and-braces only.
            }
        }
    }

    // ---------------- low-level helpers ----------------

    private void exec(string sql) throws GLib.Error {
        ensure_connected();
        string errmsg = "";
        int rc = db.exec(sql, null, out errmsg);
        if (rc != Sqlite.OK) {
            throw app_error(
                "SQL failed: %s — %s".printf(sql, errmsg),
                AppErrorType.DATABASE);
        }
    }

    public delegate void RowCallback(int64 value);

    private void exec_scalar(string sql, RowCallback callback) throws GLib.Error {
        ensure_connected();
        Sqlite.Statement stmt;
        int rc = db.prepare_v2(sql, sql.length, out stmt);
        if (rc != Sqlite.OK) {
            throw sql_error(sql);
        }
        rc = stmt.step();
        if (rc == Sqlite.ROW) {
            callback(stmt.column_int64(0));
        }
        stmt.reset();
    }

    private int query_scalar_int(string sql) {
        try {
            int result = 0;
            exec_scalar(sql, (value) => {
                result = (int) value;
            });
            return result;
        } catch (GLib.Error e) {
            return 0;
        }
    }

    private GLib.Error sql_error(string sql) {
        return app_error(
            "SQL failed: %s — %s".printf(sql, db.errmsg()),
            AppErrorType.DATABASE);
    }

    // Prepared-statement binds: null entries store SQL NULL (never "" — the
    // planned view's `due_date IS NOT NULL` depends on real NULLs).

    private void bind_args(Sqlite.Statement stmt, string?[]? binds) throws GLib.Error {
        if (binds == null) {
            return;
        }
        for (int i = 0; i < binds.length; i++) {
            if (binds[i] == null) {
                stmt.bind_null(i + 1);
            } else {
                stmt.bind_text(i + 1, binds[i]);
            }
        }
    }

    // ---------------- generic row mapping ----------------

    public delegate T MapRow<T>(Sqlite.Statement stmt);

    private GLib.List<T> query<T>(string sql, string?[]? binds, MapRow<T> map) throws GLib.Error {
        ensure_connected();
        Sqlite.Statement stmt;
        int rc = db.prepare_v2(sql, sql.length, out stmt);
        if (rc != Sqlite.OK) {
            throw sql_error(sql);
        }
        bind_args(stmt, binds);

        var results = new GLib.List<T>();
        while ((rc = stmt.step()) == Sqlite.ROW) {
            results.append(map(stmt));
        }
        if (rc != Sqlite.DONE) {
            stmt.reset();
            throw sql_error(sql);
        }
        stmt.reset();
        return results;
    }

    private int column_index(Sqlite.Statement stmt, string name) {
        for (int i = 0; i < stmt.column_count(); i++) {
            if (stmt.column_name(i) == name) {
                return i;
            }
        }
        return -1;
    }

    // ---------------- lists ----------------

    private TodoList list_from_row(Sqlite.Statement stmt) {
        var list = new TodoList();
        list.id = stmt.column_int64(column_index(stmt, "id"));
        list.name = stmt.column_text(column_index(stmt, "name")) ?? "";
        list.icon = stmt.column_text(column_index(stmt, "icon"));
        if (stmt.column_type(column_index(stmt, "color")) != Sqlite.NULL) {
            list.color = (int32) stmt.column_int64(column_index(stmt, "color"));
        }
        return list;
    }

    private TaskItem task_from_row(Sqlite.Statement stmt) {
        var task = new TaskItem();
        task.id = stmt.column_int64(column_index(stmt, "id"));
        task.list_id = stmt.column_int64(column_index(stmt, "list_id"));
        task.text = stmt.column_text(column_index(stmt, "text")) ?? "";
        task.created_at = stmt.column_text(column_index(stmt, "created_at")) ?? "";
        task.due_date = stmt.column_text(column_index(stmt, "due_date"));
        task.due_time = stmt.column_text(column_index(stmt, "due_time"));
        task.completed = stmt.column_int64(column_index(stmt, "completed")) == 1;
        task.notes = stmt.column_text(column_index(stmt, "notes"));
        task.list_name = stmt.column_text(column_index(stmt, "list_name"));
        if (stmt.column_type(column_index(stmt, "list_color")) != Sqlite.NULL) {
            task.list_color = (int32) stmt.column_int64(column_index(stmt, "list_color"));
        }
        return task;
    }

    public GLib.List<TodoList> get_all_lists() throws GLib.Error {
        var result = new GLib.List<TodoList>();
        foreach (var list in query<TodoList>("SELECT * FROM lists", null, list_from_row)) {
            result.append(list);
        }
        return result;
    }

    public TodoList? get_list_by_id(int64 id) throws GLib.Error {
        var rows = query<TodoList>("SELECT * FROM lists WHERE id = ?", { id.to_string() }, list_from_row);
        return rows.length() > 0 ? rows.nth_data(0) : null;
    }

    /// Case-sensitive exact match; null when absent.
    public TodoList? get_list_by_name(string name) throws GLib.Error {
        var rows = query<TodoList>("SELECT * FROM lists WHERE name = ? LIMIT 1", { name }, list_from_row);
        return rows.length() > 0 ? rows.nth_data(0) : null;
    }

    /// Default icon/color filled when not provided.
    public int64 add_list(string name, string? icon, int32? color) throws GLib.Error {
        exec_with_binds(
            "INSERT INTO lists (name, created_at, icon, color) VALUES (?, ?, ?, ?)",
            { name, DateParser.created_at_now(),
              icon ?? DEFAULT_LIST_ICON,
              (color ?? DEFAULT_LIST_COLOR).to_string() });
        return db.last_insert_rowid();
    }

    public int update_list(int64 id, string name, string? icon, int32? color,
                           bool clear_icon, bool clear_color) throws GLib.Error {
        var sql = new StringBuilder("UPDATE lists SET name = ?");
        string?[] binds = { name };
        if (clear_icon) {
            sql.append(", icon = NULL");
        } else if (icon != null) {
            sql.append(", icon = ?");
            binds += icon;
        }
        if (clear_color) {
            sql.append(", color = NULL");
        } else if (color != null) {
            sql.append(", color = ?");
            binds += color.to_string();
        }
        sql.append(" WHERE id = ?");
        binds += id.to_string();
        return exec_with_binds(sql.str, binds);
    }

    /// Deletes the list's tasks first, then the list.
    public int delete_list(int64 id) throws GLib.Error {
        exec_with_binds("DELETE FROM tasks WHERE list_id = ?", { id.to_string() });
        return exec_with_binds("DELETE FROM lists WHERE id = ?", { id.to_string() });
    }

    // ---------------- tasks: queries ----------------

    private const string TASK_SELECT_BASE =
        "SELECT t.*, l.name AS list_name, l.color AS list_color FROM tasks t LEFT JOIN lists l ON t.list_id = l.id";

    public GLib.List<TaskItem> get_all_tasks() throws GLib.Error {
        return task_list("%s".printf(TASK_SELECT_BASE), {});
    }

    /// All incomplete tasks with a due date (reminder source).
    public GLib.List<TaskItem> get_all_incomplete_tasks_with_due_date() throws GLib.Error {
        return task_list(TASK_SELECT_BASE + " WHERE t.completed = 0 AND t.due_date IS NOT NULL", {});
    }

    public GLib.List<TaskItem> get_tasks_by_list(int64 list_id, int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE t.list_id = ? AND t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?",
            { list_id.to_string(), limit.to_string(), offset.to_string() });
    }

    public GLib.List<TaskItem> get_tasks_by_list_including_completed(int64 list_id, int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE t.list_id = ? ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?",
            { list_id.to_string(), limit.to_string(), offset.to_string() });
    }

    public GLib.List<TaskItem> get_all_tasks_including_completed(int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?",
            { limit.to_string(), offset.to_string() });
    }

    public GLib.List<TaskItem> get_today_tasks(int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE date(t.due_date) = ? AND t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?",
            { DateParser.today_string(), limit.to_string(), offset.to_string() });
    }

    public GLib.List<TaskItem> get_today_tasks_including_completed(int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE date(t.due_date) = ? ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?",
            { DateParser.today_string(), limit.to_string(), offset.to_string() });
    }

    public GLib.List<TaskItem> get_planned_tasks(int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE t.due_date IS NOT NULL AND t.completed = 0 ORDER BY t.due_date ASC LIMIT ? OFFSET ?",
            { limit.to_string(), offset.to_string() });
    }

    public GLib.List<TaskItem> get_planned_tasks_including_completed(int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE t.due_date IS NOT NULL ORDER BY t.completed ASC, t.due_date ASC LIMIT ? OFFSET ?",
            { limit.to_string(), offset.to_string() });
    }

    // Dated tasks with due_date in [start_date, end_date] inclusive
    // (yyyy-MM-dd strings; the calendar view queries months and the overdue
    // tail with this -- PRODUCT-SPEC 4b).
    public GLib.List<TaskItem> get_tasks_in_range(string start_date, string end_date,
                                                  bool include_completed = false,
                                                  int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        var completed_filter = include_completed ? "" : " AND t.completed = 0";
        return task_list(
            TASK_SELECT_BASE + " WHERE t.due_date IS NOT NULL AND date(t.due_date) >= ? AND date(t.due_date) <= ?"
            + completed_filter + " ORDER BY t.due_date ASC, t.id DESC LIMIT ? OFFSET ?",
            { start_date, end_date, limit.to_string(), offset.to_string() });
    }

    // Incomplete-task count per due date in [start_date, end_date] inclusive
    // -- the calendar month-grid day dots.
    public GLib.List<DueDayCount> get_due_day_counts(string start_date, string end_date) throws GLib.Error {
        return query<DueDayCount>(
            "SELECT date(due_date) AS d, COUNT(*) AS c FROM tasks WHERE due_date IS NOT NULL AND completed = 0"
            + " AND date(due_date) >= ? AND date(due_date) <= ? GROUP BY d",
            { start_date, end_date },
            (stmt) => {
                var item = new DueDayCount();
                item.date = stmt.column_text(column_index(stmt, "d")) ?? "";
                item.count = (int64) stmt.column_int64(column_index(stmt, "c"));
                return item;
            });
    }

    public GLib.List<TaskItem> get_incomplete_tasks(int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?",
            { limit.to_string(), offset.to_string() });
    }

    public GLib.List<TaskItem> get_completed_tasks(int64 limit = 1000, int64 offset = 0) throws GLib.Error {
        return task_list(
            TASK_SELECT_BASE + " WHERE t.completed = 1 LIMIT ? OFFSET ?",
            { limit.to_string(), offset.to_string() });
    }

    /// SQL LIKE %keyword% (matches reference "fuzzy" search).
    public GLib.List<TaskItem> search_tasks(string keyword) throws GLib.Error {
        return task_list(TASK_SELECT_BASE + " WHERE t.text LIKE ?",
            { "%%%s%%".printf(keyword) });
    }

    public TaskItem? get_task_by_id(int64 id) throws GLib.Error {
        var rows = task_list(TASK_SELECT_BASE + " WHERE t.id = ?", { id.to_string() });
        return rows.length() > 0 ? rows.nth_data(0) : null;
    }

    private GLib.List<TaskItem> task_list(string sql, string[] binds) throws GLib.Error {
        var result = new GLib.List<TaskItem>();
        foreach (var task in query<TaskItem>(sql, binds, task_from_row)) {
            result.append(task);
        }
        return result;
    }

    // ---------------- tasks: counts ----------------

    public int64 get_task_count_by_list(int64 list_id) throws GLib.Error {
        return scalar_int64("SELECT COUNT(*) FROM tasks WHERE list_id = ? AND completed = 0",
            { list_id.to_string() });
    }

    public int64 get_incomplete_task_count() throws GLib.Error {
        return scalar_int64("SELECT COUNT(*) FROM tasks WHERE completed = 0", {});
    }

    public int64 get_completed_task_count() throws GLib.Error {
        return scalar_int64("SELECT COUNT(*) FROM tasks WHERE completed = 1", {});
    }

    public int64 get_today_task_count() throws GLib.Error {
        return scalar_int64("SELECT COUNT(*) FROM tasks WHERE date(due_date) = ? AND completed = 0",
            { DateParser.today_string() });
    }

    public int64 get_planned_task_count() throws GLib.Error {
        return scalar_int64("SELECT COUNT(*) FROM tasks WHERE due_date IS NOT NULL AND completed = 0", {});
    }

    // ---------------- tasks: writes ----------------

    public int64 add_task(TaskItem task) throws GLib.Error {
        exec_with_binds(
            "INSERT INTO tasks (list_id, text, due_date, due_time, completed, created_at, notes) VALUES (?, ?, ?, ?, ?, ?, ?)",
            { task.list_id.to_string(), task.text,
              task.due_date, task.due_time,
              task.completed ? "1" : "0", task.created_at, task.notes });
        return db.last_insert_rowid();
    }

    public int update_task(TaskItem task) throws GLib.Error {
        return exec_with_binds(
            "UPDATE tasks SET list_id = ?, text = ?, due_date = ?, due_time = ?, completed = ?, notes = ? WHERE id = ?",
            { task.list_id.to_string(), task.text,
              task.due_date, task.due_time,
              task.completed ? "1" : "0", task.notes, task.id.to_string() });
    }

    /// Read-then-flip toggle (reference semantics).
    public int toggle_task_completed(int64 id) throws GLib.Error {
        int64 current = -1;
        ensure_connected();
        Sqlite.Statement stmt;
        int rc = db.prepare_v2("SELECT completed FROM tasks WHERE id = ?", -1, out stmt);
        if (rc != Sqlite.OK) {
            throw sql_error("SELECT completed");
        }
        stmt.bind_text(1, id.to_string());
        while ((rc = stmt.step()) == Sqlite.ROW) {
            current = stmt.column_int64(0);
        }
        stmt.reset();
        if (current < 0) {
            return 0;
        }
        var new_value = current == 1 ? "0" : "1";
        return exec_with_binds("UPDATE tasks SET completed = ? WHERE id = ?",
            { new_value, id.to_string() });
    }

    /// Idempotent completion set; affected rows (0 = missing).
    public int set_task_completed(int64 id, bool completed) throws GLib.Error {
        return exec_with_binds("UPDATE tasks SET completed = ? WHERE id = ?",
            { completed ? "1" : "0", id.to_string() });
    }

    public int delete_task(int64 id) throws GLib.Error {
        return exec_with_binds("DELETE FROM tasks WHERE id = ?", { id.to_string() });
    }

    // ---------------- write/scalar helpers ----------------

    private int exec_with_binds(string sql, string?[] binds) throws GLib.Error {
        ensure_connected();
        Sqlite.Statement stmt;
        int rc = db.prepare_v2(sql, sql.length, out stmt);
        if (rc != Sqlite.OK) {
            throw sql_error(sql);
        }
        bind_args(stmt, binds);
        rc = stmt.step();
        if (rc != Sqlite.DONE) {
            stmt.reset();
            throw sql_error(sql);
        }
        stmt.reset();
        return db.changes();
    }

    private int64 scalar_int64(string sql, string?[] binds) throws GLib.Error {
        ensure_connected();
        Sqlite.Statement stmt;
        int rc = db.prepare_v2(sql, sql.length, out stmt);
        if (rc != Sqlite.OK) {
            throw sql_error(sql);
        }
        bind_args(stmt, binds);
        int64 result = 0;
        rc = stmt.step();
        if (rc == Sqlite.ROW) {
            result = stmt.column_int64(0);
        }
        stmt.reset();
        return result;
    }
}

}
