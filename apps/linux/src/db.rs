//! SQLite database (contract: DATA-FORMAT.md, schema v4). Every query's
//! WHERE/ORDER BY matches the reference implementation so existing .db files
//! open in place. Serialized behind a Mutex.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use chrono::Local;
use rusqlite::{params, Connection, OptionalExtension};

use crate::config;
use crate::date_parser::{today_string, DateParser, DATE_FORMAT, TIME_FORMAT};
use crate::i18n::I18n;
use crate::models::validation;
use crate::models::{AppError, AppErrorType, AppResult, TaskItem, TaskViewType, TodoList, DEFAULT_LIST_COLOR, DEFAULT_LIST_ICON};

pub const DATABASE_VERSION: i32 = 4;

const TASK_SELECT_BASE: &str = "SELECT t.*, l.name AS list_name FROM tasks t LEFT JOIN lists l ON t.list_id = l.id";

fn to_db_err(err: rusqlite::Error) -> AppError {
    AppError::new(format!("Database error: {err}"), AppErrorType::Database)
}

pub struct SQLiteDatabase {
    connection: Mutex<Option<Connection>>,
    custom_path: Mutex<Option<PathBuf>>,
}

impl SQLiteDatabase {
    pub fn new() -> Self {
        Self {
            connection: Mutex::new(None),
            custom_path: Mutex::new(None),
        }
    }

    pub fn set_database_path(&self, path: impl Into<PathBuf>) {
        *self.custom_path.lock().expect("db lock") = Some(path.into());
        *self.connection.lock().expect("db lock") = None;
    }

    pub fn database_path(&self) -> PathBuf {
        self.custom_path
            .lock()
            .expect("db lock")
            .clone()
            .unwrap_or_else(config::default_database_path)
    }

    pub fn ensure_connected(&self) -> AppResult<()> {
        let mut guard = self.connection.lock().expect("db lock");
        if guard.is_some() {
            return Ok(());
        }

        let db_path = self.database_path();
        if let Some(dir) = db_path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }

        let conn = Connection::open(&db_path).map_err(to_db_err)?;
        conn.execute_batch("PRAGMA journal_mode=WAL;").map_err(to_db_err)?;
        self.create_or_upgrade(&conn)?;
        // Belt-and-braces column check (matches reference behavior).
        let _ = Self::ensure_column(&conn, "lists", "icon", "TEXT");
        let _ = Self::ensure_column(&conn, "lists", "color", "INTEGER");
        *guard = Some(conn);
        Ok(())
    }

    pub fn close(&self) {
        *self.connection.lock().expect("db lock") = None;
    }

    fn create_or_upgrade(&self, conn: &Connection) -> AppResult<()> {
        let old_version: i32 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap_or(0);

        if old_version == 0 {
            conn.execute_batch(
                "BEGIN;
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
                 COMMIT;",
            )
            .map_err(to_db_err)?;
            // Default seeded list (byte-compatible; intentionally not localized).
            conn.execute(
                "INSERT INTO lists (name, icon, color, created_at) VALUES (?1, ?2, ?3, ?4)",
                params!["工作", DEFAULT_LIST_ICON, DEFAULT_LIST_COLOR, created_at_now()],
            )
            .map_err(to_db_err)?;
        } else {
            if old_version < 2 {
                Self::create_indexes(conn)?;
            }
            if old_version < 3 {
                Self::ensure_column(conn, "lists", "icon", "TEXT")?;
                Self::ensure_column(conn, "lists", "color", "INTEGER")?;
            }
            if old_version < 4 {
                Self::ensure_column(conn, "tasks", "due_time", "TEXT")?;
                Self::ensure_column(conn, "tasks", "notes", "TEXT")?;
            }
        }

        // user_version must be set outside a transaction.
        conn.execute_batch(&format!("PRAGMA user_version = {DATABASE_VERSION};"))
            .map_err(to_db_err)?;
        Ok(())
    }

    fn create_indexes(conn: &Connection) -> AppResult<()> {
        conn.execute_batch(
            "CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id);
             CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed);
             CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);",
        )
        .map_err(to_db_err)
    }

    fn ensure_column(conn: &Connection, table: &str, column: &str, col_type: &str) -> AppResult<()> {
        let exists = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM pragma_table_info({table}) WHERE name = ?1"),
                params![column],
                |row| row.get::<_, i64>(0),
            )
            .map(|n| n > 0)
            .unwrap_or(true);
        if !exists {
            conn.execute_batch(&format!("ALTER TABLE {table} ADD COLUMN {column} {col_type};"))
                .map_err(to_db_err)?;
        }
        Ok(())
    }

    fn with_connection<T>(&self, f: impl FnOnce(&Connection) -> AppResult<T>) -> AppResult<T> {
        self.ensure_connected()?;
        let guard = self.connection.lock().expect("db lock");
        let conn = guard.as_ref().expect("connected");
        f(conn)
    }

    // ---------------- row mapping ----------------

    fn task_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskItem> {
        Ok(TaskItem {
            id: row.get("id")?,
            list_id: row.get("list_id")?,
            text: row.get("text")?,
            created_at: row.get("created_at")?,
            due_date: row.get("due_date")?,
            due_time: row.get("due_time")?,
            completed: row.get::<_, Option<i64>>("completed")?.unwrap_or(0) == 1,
            notes: row.get("notes")?,
            list_name: row.get("list_name")?,
        })
    }

    fn list_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TodoList> {
        Ok(TodoList {
            id: row.get("id")?,
            name: row.get("name")?,
            icon: row.get("icon")?,
            color: row.get("color")?,
            pending_count: 0,
        })
    }

    // ---------------- lists ----------------

    pub fn get_all_lists(&self) -> AppResult<Vec<TodoList>> {
        self.with_connection(|conn| {
            let mut stmt = conn.prepare("SELECT * FROM lists").map_err(to_db_err)?;
            let rows = stmt
                .query_map([], Self::list_from_row)
                .map_err(to_db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(to_db_err)?;
            Ok(rows)
        })
    }

    pub fn get_list_by_id(&self, id: i64) -> AppResult<Option<TodoList>> {
        self.with_connection(|conn| {
            conn.query_row("SELECT * FROM lists WHERE id = ?1", params![id], Self::list_from_row)
                .optional()
                .map_err(to_db_err)
        })
    }

    /// Case-sensitive exact match; None when absent.
    pub fn get_list_by_name(&self, name: &str) -> AppResult<Option<TodoList>> {
        self.with_connection(|conn| {
            conn.query_row(
                "SELECT * FROM lists WHERE name = ?1 LIMIT 1",
                params![name],
                Self::list_from_row,
            )
            .optional()
            .map_err(to_db_err)
        })
    }

    /// Default icon/color filled when not provided.
    pub fn add_list(&self, name: &str, icon: Option<&str>, color: Option<i32>) -> AppResult<i64> {
        self.with_connection(|conn| {
            conn.execute(
                "INSERT INTO lists (name, created_at, icon, color) VALUES (?1, ?2, ?3, ?4)",
                params![
                    name,
                    created_at_now(),
                    icon.unwrap_or(DEFAULT_LIST_ICON),
                    color.unwrap_or(DEFAULT_LIST_COLOR),
                ],
            )
            .map_err(to_db_err)?;
            Ok(conn.last_insert_rowid())
        })
    }

    pub fn update_list(
        &self,
        id: i64,
        name: &str,
        icon: Option<&str>,
        color: Option<i32>,
        clear_icon: bool,
        clear_color: bool,
    ) -> AppResult<usize> {
        self.with_connection(|conn| {
            let mut sql = String::from("UPDATE lists SET name = ?1");
            let mut binds: Vec<Box<dyn rusqlite::ToSql>> = vec![Box::new(name.to_string())];
            if clear_icon {
                sql.push_str(", icon = NULL");
            } else if let Some(i) = icon {
                sql.push_str(&format!(", icon = ?{}", binds.len() + 1));
                binds.push(Box::new(i.to_string()));
            }
            if clear_color {
                sql.push_str(", color = NULL");
            } else if let Some(c) = color {
                sql.push_str(&format!(", color = ?{}", binds.len() + 1));
                binds.push(Box::new(*c));
            }
            sql.push_str(&format!(" WHERE id = ?{}", binds.len() + 1));
            binds.push(Box::new(id));

            let refs: Vec<&dyn rusqlite::ToSql> = binds.iter().map(|b| b.as_ref()).collect();
            let mut stmt = conn.prepare(&sql).map_err(to_db_err)?;
            stmt.execute(refs.as_slice()).map_err(to_db_err)
        })
    }

    /// Deletes the list's tasks first, then the list.
    pub fn delete_list(&self, id: i64) -> AppResult<usize> {
        self.with_connection(|conn| {
            conn.execute("DELETE FROM tasks WHERE list_id = ?1", params![id]).map_err(to_db_err)?;
            conn.execute("DELETE FROM lists WHERE id = ?1", params![id]).map_err(to_db_err)
        })
    }

    // ---------------- tasks: queries ----------------

    fn query_tasks(&self, where_clause: &str, params: &[&dyn rusqlite::ToSql]) -> AppResult<Vec<TaskItem>> {
        let sql = format!("{TASK_SELECT_BASE} {where_clause}");
        self.with_connection(|conn| {
            let mut stmt = conn.prepare(&sql).map_err(to_db_err)?;
            let rows = stmt
                .query_map(params, Self::task_from_row)
                .map_err(to_db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(to_db_err)?;
            Ok(rows)
        })
    }

    pub fn get_all_tasks(&self) -> AppResult<Vec<TaskItem>> {
        self.query_tasks("", &[])
    }

    /// All incomplete tasks with a due date (reminder source).
    pub fn get_all_incomplete_tasks_with_due_date(&self) -> AppResult<Vec<TaskItem>> {
        self.query_tasks("WHERE t.completed = 0 AND t.due_date IS NOT NULL", &[])
    }

    pub fn get_tasks_by_list(&self, list_id: i64, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        self.query_tasks(
            "WHERE t.list_id = ?1 AND t.completed = 0 ORDER BY t.id DESC LIMIT ?2 OFFSET ?3",
            &[&list_id, &limit, &offset],
        )
    }

    pub fn get_tasks_by_list_including_completed(&self, list_id: i64, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        self.query_tasks(
            "WHERE t.list_id = ?1 ORDER BY t.completed ASC, t.id DESC LIMIT ?2 OFFSET ?3",
            &[&list_id, &limit, &offset],
        )
    }

    pub fn get_all_tasks_including_completed(&self, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        self.query_tasks(
            "ORDER BY t.completed ASC, t.id DESC LIMIT ?1 OFFSET ?2",
            &[&limit, &offset],
        )
    }

    pub fn get_today_tasks(&self, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        let today = today_string();
        self.query_tasks(
            "WHERE date(t.due_date) = ?1 AND t.completed = 0 ORDER BY t.id DESC LIMIT ?2 OFFSET ?3",
            &[&today, &limit, &offset],
        )
    }

    pub fn get_today_tasks_including_completed(&self, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        let today = today_string();
        self.query_tasks(
            "WHERE date(t.due_date) = ?1 ORDER BY t.completed ASC, t.id DESC LIMIT ?2 OFFSET ?3",
            &[&today, &limit, &offset],
        )
    }

    pub fn get_planned_tasks(&self, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        self.query_tasks(
            "WHERE t.due_date IS NOT NULL AND t.completed = 0 ORDER BY t.due_date ASC LIMIT ?1 OFFSET ?2",
            &[&limit, &offset],
        )
    }

    pub fn get_planned_tasks_including_completed(&self, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        self.query_tasks(
            "WHERE t.due_date IS NOT NULL ORDER BY t.completed ASC, t.due_date ASC LIMIT ?1 OFFSET ?2",
            &[&limit, &offset],
        )
    }

    pub fn get_incomplete_tasks(&self, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        self.query_tasks(
            "WHERE t.completed = 0 ORDER BY t.id DESC LIMIT ?1 OFFSET ?2",
            &[&limit, &offset],
        )
    }

    pub fn get_completed_tasks(&self, limit: i64, offset: i64) -> AppResult<Vec<TaskItem>> {
        self.query_tasks("WHERE t.completed = 1 LIMIT ?1 OFFSET ?2", &[&limit, &offset])
    }

    /// SQL LIKE %keyword% (matches reference "fuzzy" search).
    pub fn search_tasks(&self, keyword: &str) -> AppResult<Vec<TaskItem>> {
        let pattern = format!("%{keyword}%");
        self.query_tasks("WHERE t.text LIKE ?1", &[&pattern])
    }

    pub fn get_task_by_id(&self, id: i64) -> AppResult<Option<TaskItem>> {
        let sql = format!("{TASK_SELECT_BASE} WHERE t.id = ?1");
        self.with_connection(|conn| {
            conn.query_row(&sql, params![id], Self::task_from_row)
                .optional()
                .map_err(to_db_err)
        })
    }

    // ---------------- tasks: counts ----------------

    fn scalar(&self, sql: &str, params: &[&dyn rusqlite::ToSql]) -> AppResult<i64> {
        self.with_connection(|conn| {
            conn.query_row(sql, params, |row| row.get(0)).map_err(to_db_err)
        })
    }

    pub fn get_task_count_by_list(&self, list_id: i64) -> AppResult<i64> {
        self.scalar(
            "SELECT COUNT(*) FROM tasks WHERE list_id = ?1 AND completed = 0",
            &[&list_id],
        )
    }

    pub fn get_incomplete_task_count(&self) -> AppResult<i64> {
        self.scalar("SELECT COUNT(*) FROM tasks WHERE completed = 0", &[])
    }

    pub fn get_completed_task_count(&self) -> AppResult<i64> {
        self.scalar("SELECT COUNT(*) FROM tasks WHERE completed = 1", &[])
    }

    pub fn get_today_task_count(&self) -> AppResult<i64> {
        let today = today_string();
        self.scalar(
            "SELECT COUNT(*) FROM tasks WHERE date(due_date) = ?1 AND completed = 0",
            &[&today],
        )
    }

    pub fn get_planned_task_count(&self) -> AppResult<i64> {
        self.scalar("SELECT COUNT(*) FROM tasks WHERE due_date IS NOT NULL AND completed = 0", &[])
    }

    // ---------------- tasks: writes ----------------

    pub fn add_task(&self, task: &TaskItem) -> AppResult<i64> {
        self.with_connection(|conn| {
            conn.execute(
                "INSERT INTO tasks (list_id, text, due_date, due_time, completed, created_at, notes)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    task.list_id,
                    task.text,
                    task.due_date,
                    task.due_time,
                    task.completed as i64,
                    task.created_at,
                    task.notes,
                ],
            )
            .map_err(to_db_err)?;
            Ok(conn.last_insert_rowid())
        })
    }

    pub fn update_task(&self, task: &TaskItem) -> AppResult<usize> {
        self.with_connection(|conn| {
            conn.execute(
                "UPDATE tasks SET list_id = ?1, text = ?2, due_date = ?3, due_time = ?4, completed = ?5, notes = ?6 WHERE id = ?7",
                params![
                    task.list_id,
                    task.text,
                    task.due_date,
                    task.due_time,
                    task.completed as i64,
                    task.notes,
                    task.id,
                ],
            )
            .map_err(to_db_err)
        })
    }

    /// Read-then-flip toggle (reference semantics).
    pub fn toggle_task_completed(&self, id: i64) -> AppResult<usize> {
        self.with_connection(|conn| {
            let current: Option<i64> = conn
                .query_row(
                    "SELECT completed FROM tasks WHERE id = ?1",
                    params![id],
                    |row| row.get(0),
                )
                .optional()
                .map_err(to_db_err)?;
            match current {
                None => Ok(0),
                Some(value) => conn
                    .execute(
                        "UPDATE tasks SET completed = ?1 WHERE id = ?2",
                        params![if value == 1 { 0 } else { 1 }, id],
                    )
                    .map_err(to_db_err),
            }
        })
    }

    /// Idempotent completion set; affected rows (0 = missing).
    pub fn set_task_completed(&self, id: i64, completed: bool) -> AppResult<usize> {
        self.with_connection(|conn| {
            conn.execute(
                "UPDATE tasks SET completed = ?1 WHERE id = ?2",
                params![completed as i64, id],
            )
            .map_err(to_db_err)
        })
    }

    pub fn delete_task(&self, id: i64) -> AppResult<usize> {
        self.with_connection(|conn| {
            conn.execute("DELETE FROM tasks WHERE id = ?1", params![id]).map_err(to_db_err)
        })
    }
}

impl Default for SQLiteDatabase {
    fn default() -> Self {
        Self::new()
    }
}

/// ISO-8601 local timestamp (compat with .NET "o" created_at).
pub fn created_at_now() -> String {
    Local::now().format("%Y-%m-%dT%H:%M:%S%.6f%:z").to_string()
}

// ---------------- repositories ----------------

pub struct TaskRepository {
    pub db: std::sync::Arc<SQLiteDatabase>,
    pub i18n: std::sync::Arc<I18n>,
}

impl TaskRepository {
    pub fn new(db: std::sync::Arc<SQLiteDatabase>, i18n: std::sync::Arc<I18n>) -> Self {
        Self { db, i18n }
    }

    /// View dispatch; 'all' with show_completed=false = incomplete only.
    pub fn get_tasks_by_view(
        &self,
        view: TaskViewType,
        limit: i64,
        offset: i64,
        show_completed: bool,
    ) -> AppResult<Vec<TaskItem>> {
        match view {
            TaskViewType::Today => {
                if show_completed {
                    self.db.get_today_tasks_including_completed(limit, offset)
                } else {
                    self.db.get_today_tasks(limit, offset)
                }
            }
            TaskViewType::Planned => {
                if show_completed {
                    self.db.get_planned_tasks_including_completed(limit, offset)
                } else {
                    self.db.get_planned_tasks(limit, offset)
                }
            }
            TaskViewType::All => {
                if show_completed {
                    self.db.get_all_tasks_including_completed(limit, offset)
                } else {
                    self.db.get_incomplete_tasks(limit, offset)
                }
            }
            TaskViewType::Completed => self.db.get_completed_tasks(limit, offset),
            TaskViewType::List(id) => {
                if show_completed {
                    self.db.get_tasks_by_list_including_completed(id, limit, offset)
                } else {
                    self.db.get_tasks_by_list(id, limit, offset)
                }
            }
        }
    }

    pub fn add_task(&self, task: &TaskItem) -> AppResult<i64> {
        validation::validate_task_text(&task.text, &self.i18n)?;
        self.db.add_task(task)
    }

    pub fn update_task(&self, task: &TaskItem) -> AppResult<usize> {
        validation::validate_task_text(&task.text, &self.i18n)?;
        self.db.update_task(task)
    }

    pub fn search_tasks(&self, keyword: &str) -> AppResult<Vec<TaskItem>> {
        if keyword.trim().is_empty() {
            return Ok(vec![]);
        }
        self.db.search_tasks(keyword.trim())
    }
}

pub struct ListRepository {
    pub db: std::sync::Arc<SQLiteDatabase>,
    pub i18n: std::sync::Arc<I18n>,
}

impl ListRepository {
    pub fn new(db: std::sync::Arc<SQLiteDatabase>, i18n: std::sync::Arc<I18n>) -> Self {
        Self { db, i18n }
    }

    pub fn add_list(&self, name: &str, icon: Option<&str>, color: Option<i32>) -> AppResult<i64> {
        validation::validate_list_name(name, &self.i18n)?;
        self.db.add_list(name.trim(), icon, color)
    }

    pub fn update_list(
        &self,
        id: i64,
        name: &str,
        icon: Option<&str>,
        color: Option<i32>,
        clear_icon: bool,
        clear_color: bool,
    ) -> AppResult<usize> {
        validation::validate_list_name(name, &self.i18n)?;
        self.db.update_list(id, name.trim(), icon, color, clear_icon, clear_color)
    }

    /// Default list = the first one.
    pub fn get_default_list(&self) -> AppResult<Option<TodoList>> {
        Ok(self.db.get_all_lists()?.into_iter().next())
    }
}

/// Date + time helpers used by the UI layer.
pub fn format_due_display(parser: &DateParser, task: &TaskItem, i18n: &I18n) -> String {
    let date_only = DateParser::extract_date_only(task.due_date.as_ref());
    let Some(date_only) = date_only else { return String::new() };

    let today = today_string();
    let tomorrow = (Local::now().naive_local().date() + chrono::Duration::days(1))
        .format(DATE_FORMAT)
        .to_string();
    let yesterday = (Local::now().naive_local().date() - chrono::Duration::days(1))
        .format(DATE_FORMAT)
        .to_string();

    let label = if date_only == today {
        i18n.t("navToday")
    } else if date_only == tomorrow {
        if i18n.language() == "zh" { "明天".into() } else { "Tomorrow".into() }
    } else if date_only == yesterday {
        if i18n.language() == "zh" { "昨天".into() } else { "Yesterday".into() }
    } else {
        date_only.clone()
    };

    match &task.due_time {
        Some(time) if !time.is_empty() => format!("{label} {time}"),
        _ => label,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> SQLiteDatabase {
        let dir = tempfile::tempdir().expect("tmp");
        let db = SQLiteDatabase::new();
        db.set_database_path(dir.path().join("test.db"));
        // Keep the tempdir alive via leak in tests (small).
        std::mem::forget(dir);
        db
    }

    #[test]
    fn fresh_database_contract() {
        let db = fresh_db();
        db.ensure_connected().expect("connect");
        let lists = db.get_all_lists().expect("lists");
        assert_eq!(lists.len(), 1);
        assert_eq!(lists[0].name, "工作");
        assert_eq!(lists[0].icon.as_deref(), Some("📋"));
        assert_eq!(lists[0].color, Some(DEFAULT_LIST_COLOR));
    }

    #[test]
    fn task_round_trip() {
        let db = fresh_db();
        let list_id = db.add_list("Test", Some("🎯"), Some(argb::from_hex(0xFF00_7AFF))).expect("add list");
        let task = TaskItem {
            id: 0,
            list_id,
            text: "买牛奶".into(),
            created_at: created_at_now(),
            due_date: Some("2026-08-07".into()),
            due_time: Some("10:30".into()),
            completed: false,
            notes: Some("note1".into()),
            list_name: None,
        };
        let id = db.add_task(&task).expect("add");
        let loaded = db.get_task_by_id(id).expect("get").expect("exists");
        assert_eq!(loaded.text, "买牛奶");
        assert_eq!(loaded.due_date.as_deref(), Some("2026-08-07"));
        assert_eq!(loaded.due_time.as_deref(), Some("10:30"));

        db.set_task_completed(id, true).expect("set");
        assert!(db.get_task_by_id(id).expect("get").expect("exists").completed);
        db.toggle_task_completed(id).expect("toggle");
        assert!(!db.get_task_by_id(id).expect("get").expect("exists").completed);
    }

    #[test]
    fn view_queries() {
        let db = fresh_db();
        let list_a = db.add_list("A", None, None).expect("a");
        let list_b = db.add_list("B", None, None).expect("b");
        let today = today_string();
        let mk = |text: &str, list: i64, due: Option<&str>| TaskItem {
            id: 0,
            list_id: list,
            text: text.into(),
            created_at: "x".into(),
            due_date: due.map(String::from),
            due_time: None,
            completed: false,
            notes: None,
            list_name: None,
        };
        let t1 = mk("today task", list_a, Some(&today));
        let t2 = mk("planned task", list_a, Some("2027-01-01"));
        let t3 = mk("no date task", list_b, None);
        db.add_task(&t1).expect("t1");
        db.add_task(&t2).expect("t2");
        db.add_task(&t3).expect("t3");

        assert_eq!(db.get_today_tasks(1000, 0).expect("today").len(), 1);
        assert_eq!(db.get_planned_tasks(1000, 0).expect("planned").len(), 2);
        assert_eq!(db.get_incomplete_tasks(1000, 0).expect("all").len(), 3);
        assert_eq!(db.get_tasks_by_list(list_a, 1000, 0).expect("listA").len(), 2);
    }

    #[test]
    fn delete_list_cascades() {
        let db = fresh_db();
        let list_id = db.add_list("Doomed", None, None).expect("list");
        db.add_task(&TaskItem {
            id: 0, list_id, text: "x".into(), created_at: "x".into(),
            due_date: None, due_time: None, completed: false, notes: None, list_name: None,
        })
        .expect("task");
        db.delete_list(list_id).expect("delete");
        assert!(db.get_all_lists().expect("lists").iter().all(|l| l.id != list_id));
        assert!(db.get_tasks_by_list(list_id, 1000, 0).expect("tasks").is_empty());
    }
}
