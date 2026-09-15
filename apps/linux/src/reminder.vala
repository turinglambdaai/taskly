// Taskly — due-task reminders (PRODUCT-SPEC §9): startup check + 60 s poll
// on the main loop, per-session dedupe, ≤3 individual / >3 aggregated.
// Transport = libnotify (the freedesktop notification API). Any failure
// disables notifications for the session — never crash.

namespace Taskly {

public class ReminderService : Object {
    private SQLiteDatabase db;
    private I18n i18n;
    private GLib.HashTable<string, bool> notified_ids;
    private bool native_disabled = false;
    private bool notify_initialized = false;

    public ReminderService(SQLiteDatabase db, I18n i18n) {
        this.db = db;
        this.i18n = i18n;
        notified_ids = new GLib.HashTable<string, bool>(str_hash, str_equal);
    }

    public void reset_notified() {
        notified_ids.remove_all();
        native_disabled = false;
    }

    /// Startup check + 60 s recurring check on the GLib main loop.
    public void start() {
        check_now();
        Timeout.add_seconds(60, () => {
            check_now();
            return Source.CONTINUE;
        });
    }

    public void check_now() {
        if (native_disabled) {
            return;
        }

        GLib.List<TaskItem> due = new GLib.List<TaskItem>();
        try {
            foreach (var task in db.get_all_incomplete_tasks_with_due_date()) {
                if (!is_due(task)) {
                    continue;
                }
                if (notified_ids.lookup(task.id.to_string())) {
                    continue;
                }
                notified_ids[task.id.to_string()] = true;
                due.append(task);
            }
        } catch (GLib.Error e) {
            return;
        }

        var count = due.length();
        if (count == 0) {
            return;
        }

        if (count > 3) {
            notify(i18n.t("reminderTitle"),
                i18n.format("reminderStartupSummary", count.to_string()));
        } else {
            foreach (var task in due) {
                var due_line = task.due_date ?? "";
                if (task.due_time != null && task.due_time.length > 0) {
                    due_line += " " + task.due_time;
                }
                notify(i18n.t("reminderTitle"),
                    "%s\n%s: %s".printf(task.text, i18n.t("reminderDueAt"), due_line));
            }
        }
    }

    private new void notify(string title, string body) {
        if (native_disabled) {
            return;
        }

        try {
            if (!notify_initialized) {
                if (!Notify.is_initted()) {
                    Notify.init("Taskly");
                }
                notify_initialized = true;
            }
            var notification = new Notify.Notification(title, body, null);
            notification.show();
        } catch (GLib.Error e) {
            // No notification daemon/permission: stay silent this session.
            native_disabled = true;
        }
    }

    private bool is_due(TaskItem task) {
        if (task.due_date == null) {
            return false;
        }
        var combined = DateParser.combine_datetime(task.due_date, task.due_time);
        var date = DateParser.parse_full_datetime(combined);
        if (date == null) {
            return false;
        }
        return date.compare(new DateTime.now_local()) <= 0;
    }
}

}
