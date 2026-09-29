-- Taskly golden-CLI seed: schema v4 with NO lists. Used by the
-- "add with no lists" case (exit 3 per shared/spec/CLI-SPEC.md).
PRAGMA journal_mode = WAL;
PRAGMA user_version = 4;

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
