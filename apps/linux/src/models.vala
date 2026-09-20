// Taskly — data model mirroring the tasks/lists tables (DATA-FORMAT.md, schema v4).

namespace Taskly {

public const string DEFAULT_LIST_ICON = "📋";
// ARGB 0xFF007AFF (system blue) as a signed 32-bit int.
public const int32 DEFAULT_LIST_COLOR = (int32) 0xFF007AFF;

public class TaskItem : Object {
    public int64 id { get; set; default = 0; }
    public int64 list_id { get; set; default = 0; }
    public string text { get; set; default = ""; }
    // ISO-8601 local timestamp (compat with .NET "o").
    public string created_at { get; set; default = ""; }
    // "yyyy-MM-dd" or null.
    public string? due_date { get; set; default = null; }
    // "HH:mm" or null.
    public string? due_time { get; set; default = null; }
    public bool completed { get; set; default = false; }
    public string? notes { get; set; default = null; }
    // Join artifact (LEFT JOIN lists); never persisted.
    public string? list_name { get; set; default = null; }

    public TaskItem clone() {
        var copy = new TaskItem();
        copy.id = id;
        copy.list_id = list_id;
        copy.text = text;
        copy.created_at = created_at;
        copy.due_date = due_date;
        copy.due_time = due_time;
        copy.completed = completed;
        copy.notes = notes;
        copy.list_name = list_name;
        return copy;
    }
}

public class TodoList : Object {
    public int64 id { get; set; default = 0; }
    public string name { get; set; default = ""; }
    public string? icon { get; set; default = null; }
    // Signed ARGB int or null (plain field: nullable value types cannot be
    // GObject properties).
    public int32? color;
    // Unfinished count, UI-only.
    public int64 pending_count { get; set; default = 0; }

    public string icon_or_default() {
        return icon ?? DEFAULT_LIST_ICON;
    }
}

public enum TaskViewType {
    ALL,
    TODAY,
    PLANNED,
    COMPLETED,
    LIST;
}

public enum AppErrorType {
    GENERIC,     // exit code 1
    VALIDATION,  // exit code 2
    NOT_FOUND,   // exit code 3
    DATABASE;    // exit code 4

    public int exit_code() {
        switch (this) {
            case VALIDATION: return 2;
            case NOT_FOUND: return 3;
            case DATABASE: return 4;
            default: return 1;
        }
    }
}

// Error construction: GLib.Error instances whose `code` carries the CLI
// exit code (1 generic / 2 validation / 3 not-found / 4 database).
public const string ERROR_DOMAIN = "taskly-error";

public GLib.Error app_error(string message, AppErrorType type = AppErrorType.GENERIC) {
    return new GLib.Error(GLib.Quark.from_string(ERROR_DOMAIN), type.exit_code(), "%s", message);
}

public class Validation {
    public const int MAX_TASK_TEXT_LENGTH = 1000;
    public const int MAX_LIST_NAME_LENGTH = 100;
    public const int MAX_SEARCH_KEYWORD_LENGTH = 200;
    public const int MIN_YEAR = 1900;
    public const int MAX_YEAR = 2100;

    public static void validate_task_text(string text, I18n i18n) throws GLib.Error {
        if (text.strip().length == 0) {
            throw app_error(i18n.t("errorEnterTaskDesc"), AppErrorType.VALIDATION);
        }
        if (text.char_count() > MAX_TASK_TEXT_LENGTH) {
            throw app_error(
                i18n.format("errorTaskDescTooLong", MAX_TASK_TEXT_LENGTH.to_string()),
                AppErrorType.VALIDATION);
        }
    }

    public static void validate_list_name(string name, I18n i18n) throws GLib.Error {
        if (name.strip().length == 0) {
            throw app_error(i18n.t("errorEnterListName"), AppErrorType.VALIDATION);
        }
        if (name.char_count() > MAX_LIST_NAME_LENGTH) {
            throw app_error(
                i18n.format("errorListNameTooLong", MAX_LIST_NAME_LENGTH.to_string()),
                AppErrorType.VALIDATION);
        }
    }
}

}
