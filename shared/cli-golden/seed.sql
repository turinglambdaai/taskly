-- Taskly golden-CLI seed database (schema v4, see shared/spec/DATA-FORMAT.md).
-- Applied with `sqlite3 case.db < seed.sql`, then copied fresh per case so
-- every case starts from identical state. Static dates only: cases that need
-- "today"/"tomorrow" rows run them as unasserted setup commands (cases.json).
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

INSERT INTO lists (id, name, icon, color, created_at) VALUES
  (1, '工作', '📋', -16745729, '2026-09-01T08:00:00.0000000+08:00'),
  (2, 'Personal', '🏠', -13318311, '2026-09-01T08:00:00.0000000+08:00');

INSERT INTO tasks (id, list_id, text, due_date, due_time, completed, created_at, notes) VALUES
  (1, 1, '买牛奶', '2026-12-01', '10:00', 0, '2026-09-15T09:00:00.0000000+08:00', NULL),
  (2, 1, '写周报', NULL, NULL, 0, '2026-09-15T09:00:00.0000000+08:00', NULL),
  (3, 1, '已完成的历史任务', '2026-09-10', NULL, 1, '2026-09-15T09:00:00.0000000+08:00', NULL),
  (4, 2, 'Prepare demo', '2026-12-15', '14:30', 0, '2026-09-15T09:00:00.0000000+08:00', 'rehearse twice'),
  (5, 1, '带伞', '2026-11-30', NULL, 0, '2026-09-15T09:00:00.0000000+08:00', NULL);
