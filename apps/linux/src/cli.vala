// Taskly — CLI engine (contract: shared/spec/CLI-SPEC.md). Same argv
// contract, JSON shapes, and exit codes as the macOS/Windows ports. Runs
// before any GTK initialization (headless-safe).

namespace Taskly {

public class CliEngine : Object {

    public static int run(string[] args) {
        bool json = false;
        bool quiet = false;
        string? db_path = null;
        string[] rest = {};
        GLib.Error? parse_error = null;

        for (var i = 0; i < args.length; i++) {
            var token = args[i];
            if (token == "--json") {
                json = true;
            } else if (token == "--quiet" || token == "-q") {
                quiet = true;
            } else if (token == "--db") {
                if (i + 1 < args.length) {
                    db_path = args[++i];
                } else {
                    parse_error = app_error("Missing value for --db", AppErrorType.VALIDATION);
                }
            } else {
                rest += token;
            }
        }

        if (parse_error != null) {
            return fail(parse_error.message, parse_error.code);
        }
        if (rest.length == 0) {
            return fail(
                "Usage: taskly <command> [options]\nCommands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli",
                1);
        }

        var command = rest[0];
        string[] tail = rest[1:rest.length];

        try {
            switch (command) {
                case "list":
                    return cmd_list(tail, db_path, json, quiet);
                case "lists":
                    return cmd_lists(db_path, json, quiet);
                case "add":
                    return cmd_add(tail, db_path, json, quiet);
                case "update":
                    return cmd_update(tail, db_path, json, quiet);
                case "done":
                    return cmd_done(tail, db_path, json, quiet, true);
                case "undone":
                    return cmd_done(tail, db_path, json, quiet, false);
                case "rm":
                    return cmd_rm(tail, db_path, json, quiet);
                case "search":
                    return cmd_search(tail, db_path, json, quiet);
                case "mklist":
                    return cmd_mklist(tail, db_path, json, quiet);
                case "rmlist":
                    return cmd_rmlist(tail, db_path, json, quiet);
                case "install-cli":
                    return CliInstaller.install();
                case "uninstall-cli":
                    return CliInstaller.uninstall();
                case "--help":
                case "-h":
                case "help":
                    print("Taskly — task manager command-line interface (for AI agents & scripting)\n");
                    print("Commands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli\n");
                    print("Global options: --json, --db <path>, --quiet (-q)\n");
                    return 0;
                default:
                    return fail("Unknown command: \"%s\"".printf(command), 1);
            }
        } catch (GLib.Error e) {
            // `code` carries the contract exit code (see app_error).
            return fail(e.message, e.code);
        }
    }

    private static int fail(string message, int exit_code) {
        stderr.printf("%s\n", CliJson.error_object(message, exit_code));
        return exit_code;
    }

    // ---------------- options parsing ----------------

    private const string[] VALUE_OPTIONS = {
        "--list", "--view", "--status", "--limit", "--due", "--time",
        "--notes", "--icon", "--color", "--text",
    };
    private const string[] FLAG_OPTIONS = { "--clear-due", "--clear-time", "--clear-notes" };

    internal class Options : Object {
        public GLib.HashTable<string, string> values =
            new GLib.HashTable<string, string>(str_hash, str_equal);
        public GLib.HashTable<string, bool> flags =
            new GLib.HashTable<string, bool>(str_hash, str_equal);
        public string[] positionals = {};

        public string? value(string name) {
            return values.lookup(name);
        }

        public bool has(string name) {
            return flags.lookup(name);
        }
    }

    private static Options parse_options(string[] args) throws GLib.Error {
        var options = new Options();
        var i = 0;
        while (i < args.length) {
            var token = args[i];
            if (token == "--") {
                for (var j = i + 1; j < args.length; j++) {
                    options.positionals += args[j];
                }
                break;
            }
            if (token.has_prefix("--")) {
                var name = token;
                string? inline_value = null;
                var eq = token.index_of("=");
                if (eq > 0) {
                    name = token.substring(0, eq);
                    inline_value = token.substring(eq + 1);
                }
                if (contains(VALUE_OPTIONS, name)) {
                    if (inline_value != null) {
                        options.values[name] = inline_value;
                    } else if (i + 1 < args.length) {
                        options.values[name] = args[++i];
                    } else {
                        throw app_error("Missing value for %s".printf(name), AppErrorType.VALIDATION);
                    }
                } else if (contains(FLAG_OPTIONS, name)) {
                    options.flags[name] = true;
                } else {
                    throw app_error("Unknown option: %s".printf(name), AppErrorType.VALIDATION);
                }
            } else if (token.has_prefix("-") && token.length > 1) {
                throw app_error("Unknown option: %s".printf(token), AppErrorType.VALIDATION);
            } else {
                options.positionals += token;
            }
            i++;
        }
        return options;
    }

    private static bool contains(string[] haystack, string needle) {
        foreach (var item in haystack) {
            if (item == needle) {
                return true;
            }
        }
        return false;
    }

    private static string require_positional(Options options, int index, string what) throws GLib.Error {
        if (index >= options.positionals.length) {
            throw app_error("Missing required argument: <%s>".printf(what), AppErrorType.VALIDATION);
        }
        return options.positionals[index];
    }

    private static int64 parse_int(string s, string what) throws GLib.Error {
        var value = int64.parse(s);
        if (value == 0 && s != "0") {
            throw app_error("Invalid %s: \"%s\"".printf(what, s), AppErrorType.VALIDATION);
        }
        return value;
    }

    private static int64 resolve_list_id(SQLiteDatabase db, string list) throws GLib.Error {
        if (is_numeric(list)) {
            return int64.parse(list);
        }
        var found = db.get_list_by_name(list);
        if (found == null) {
            throw app_error("List not found by name: \"%s\"".printf(list), AppErrorType.NOT_FOUND);
        }
        return found.id;
    }

    private static bool is_numeric(string s) {
        if (s.length == 0) {
            return false;
        }
        foreach (var c in s.data) {
            if (c < '0' || c > '9') {
                return false;
            }
        }
        return true;
    }

    private static int32 parse_color(string color) throws GLib.Error {
        if (is_numeric(color)) {
            return (int32) int64.parse(color);
        }
        if (!color.has_prefix("#")) {
            throw app_error("Invalid color: \"%s\". Use #RRGGBB hex or ARGB int".printf(color),
                AppErrorType.VALIDATION);
        }
        var hex = color.substring(1);
        if (hex.length == 6) {
            var rgb = (uint32) strtoul_hex(hex);
            return (int32) (0xFF000000u | rgb);
        }
        if (hex.length == 8) {
            return (int32) strtoul_hex(hex);
        }
        throw app_error("Invalid hex color: \"%s\". Use #RRGGBB (6) or #AARRGGBB (8)".printf(color),
            AppErrorType.VALIDATION);
    }

    private static uint32 strtoul_hex(string hex) throws GLib.Error {
        uint32 value = 0;
        foreach (var c in hex.data) {
            value <<= 4;
            if (c >= '0' && c <= '9') {
                value += c - '0';
            } else if (c >= 'a' && c <= 'f') {
                value += c - 'a' + 10;
            } else if (c >= 'A' && c <= 'F') {
                value += c - 'A' + 10;
            } else {
                throw app_error("Invalid hex color: \"%s\". Use #RRGGBB (6) or #AARRGGBB (8)".printf(hex),
                    AppErrorType.VALIDATION);
            }
        }
        return value;
    }

    // ---------------- output ----------------

    private static void print_json(string rendered) {
        print("%s\n", rendered);
    }

    private static string human_task_line(TaskItem t) {
        var mark = t.completed ? "[x]" : "[ ]";
        var due = "";
        if (t.due_date != null && t.due_date.length > 0) {
            due = "  🗓 " + t.due_date;
            if (t.due_time != null && t.due_time.length > 0) {
                due += " " + t.due_time;
            }
        }
        return "  %5lld  %s  %s%s".printf(t.id, mark, t.text, due);
    }

    private static void print_task(bool json, bool quiet, TaskItem t) {
        if (json) {
            print_json(CliJson.task_object(t));
        } else if (quiet) {
            print("%lld\n", t.id);
        } else {
            print("%s\n", human_task_line(t));
        }
    }

    private static void print_tasks(bool json, bool quiet, GLib.List<TaskItem> tasks) {
        if (json) {
            string[] rendered = {};
            foreach (var t in tasks) {
                rendered += CliJson.task_object(t);
            }
            print_json(CliJson.render_array(rendered));
            return;
        }
        if (tasks.length() == 0) {
            if (!quiet) {
                print("(no tasks)\n");
            }
            return;
        }
        foreach (var t in tasks) {
            print_task(json, quiet, t);
        }
    }

    private static void print_lists(bool json, GLib.List<TodoList> lists) {
        if (json) {
            string[] rendered = {};
            foreach (var l in lists) {
                rendered += CliJson.list_object(l);
            }
            print_json(CliJson.render_array(rendered));
            return;
        }
        foreach (var l in lists) {
            var icon = (l.icon != null && l.icon.length > 0) ? l.icon + " " : "";
            print("  %5lld  %s%s  (%lld)\n", l.id, icon, l.name, l.pending_count);
        }
    }

    // ---------------- context ----------------

    private static SQLiteDatabase open_db(string? db_path) throws GLib.Error {
        var db = new SQLiteDatabase();
        if (db_path != null) {
            db.set_database_path(db_path);
        } else {
            var config = new Config();
            var last = config.last_db_path();
            if (last != null) {
                db.set_database_path(last);
            }
        }
        try {
            db.ensure_connected();
        } catch (GLib.Error e) {
            throw app_error(
                "Cannot open database: %s (%s)".printf(db.database_path(), e.message),
                AppErrorType.DATABASE);
        }
        return db;
    }

    // ---------------- commands ----------------

    private static int cmd_list(string[] args, string? db_path, bool json, bool quiet) throws GLib.Error {
        var options = parse_options(args);
        var list_arg = options.value("--list");
        var view_arg = options.value("--view");
        var status_arg = options.value("--status") ?? "incomplete";
        var limit = parse_int(options.value("--limit") ?? "1000", "--limit");

        var db = open_db(db_path);
        if (list_arg != null && list_arg.length > 0) {
            var list_id = resolve_list_id(db, list_arg);
            // valac: a ternary would duplicate the GLib.List; branch instead
            // so the returned list transfers ownership directly.
            GLib.List<TaskItem> tasks;
            if (status_shows_completed(status_arg)) {
                tasks = db.get_tasks_by_list_including_completed(list_id, limit);
            } else {
                tasks = db.get_tasks_by_list(list_id, limit);
            }
            print_tasks(json, quiet, tasks);
            return 0;
        }
        TaskViewType view;
        if (view_arg == null || view_arg.length == 0) {
            view = TaskViewType.ALL;
        } else {
            switch (view_arg.down()) {
                case "today": view = TaskViewType.TODAY; break;
                case "planned":
                case "scheduled": view = TaskViewType.PLANNED; break;
                case "all": view = TaskViewType.ALL; break;
                case "completed": view = TaskViewType.COMPLETED; break;
                default:
                    return fail("Invalid --view: \"%s\". Use today | planned | all | completed".printf(view_arg), 2);
            }
        }

        var show_completed = status_shows_completed(status_arg);
        GLib.List<TaskItem> result;
        switch (view) {
            case TaskViewType.TODAY:
                if (show_completed) {
                    result = db.get_today_tasks_including_completed(limit);
                } else {
                    result = db.get_today_tasks(limit);
                }
                break;
            case TaskViewType.PLANNED:
                if (show_completed) {
                    result = db.get_planned_tasks_including_completed(limit);
                } else {
                    result = db.get_planned_tasks(limit);
                }
                break;
            case TaskViewType.COMPLETED:
                result = db.get_completed_tasks(limit);
                break;
            default:
                if (show_completed) {
                    result = db.get_all_tasks_including_completed(limit);
                } else {
                    result = db.get_incomplete_tasks(limit);
                }
                break;
        }
        print_tasks(json, quiet, result);
        return 0;
    }

    private static bool status_shows_completed(string status) throws GLib.Error {
        switch (status.down()) {
            case "all": return true;
            case "incomplete":
            case "open":
            case "pending": return false;
            case "completed":
            case "done": return true;
            default:
                throw app_error(
                    "Invalid --status: \"%s\". Use all | incomplete | completed".printf(status),
                    AppErrorType.VALIDATION);
        }
    }

    private static int cmd_lists(string? db_path, bool json, bool quiet) throws GLib.Error {
        var db = open_db(db_path);
        var lists = db.get_all_lists();
        foreach (var l in lists) {
            l.pending_count = db.get_task_count_by_list(l.id);
        }
        print_lists(json, lists);
        return 0;
    }

    private static int cmd_add(string[] args, string? db_path, bool json, bool quiet) throws GLib.Error {
        var options = parse_options(args);
        var text = require_positional(options, 0, "text");
        var list_arg = options.value("--list");

        var db = open_db(db_path);

        int64 list_id;
        if (list_arg != null && list_arg.length > 0) {
            list_id = resolve_list_id(db, list_arg);
        } else {
            var lists = db.get_all_lists();
            if (lists.length() == 0) {
                throw app_error(
                    "No lists exist yet. Create one with `taskly mklist` first.",
                    AppErrorType.NOT_FOUND);
            }
            list_id = lists.nth_data(0).id;
        }

        string? due_date = null;
        string? due_time = null;
        var due_arg = options.value("--due");
        if (due_arg != null && due_arg.length > 0) {
            var parsed = parse_due(new DateParser(), due_arg);
            due_date = parsed.date;
            due_time = parsed.time;
        }
        var time_arg = options.value("--time");
        if (time_arg != null && time_arg.length > 0) {
            due_time = time_arg;
        }

        var task = new TaskItem();
        task.list_id = list_id;
        task.text = text;
        task.created_at = DateParser.created_at_now();
        task.due_date = due_date;
        task.due_time = due_time;
        task.notes = options.value("--notes");

        // Same validation rule as the repositories layer (exit 2 on failure).
        Validation.validate_task_text(task.text, new I18n("zh"));

        var id = db.add_task(task);
        task.id = id;
        print_task(json, quiet, task);
        return 0;
    }

    private static int cmd_update(string[] args, string? db_path, bool json, bool quiet) throws GLib.Error {
        var options = parse_options(args);
        var id_string = require_positional(options, 0, "id");
        var id = parse_int(id_string, "id");

        var db = open_db(db_path);
        var task = db.get_task_by_id(id);
        if (task == null) {
            return fail("Task not found: %lld".printf(id), 3);
        }

        var text = options.value("--text");
        if (text != null) {
            task.text = text;
        }

        if (options.has("--clear-due")) {
            task.due_date = null;
        } else {
            var due_arg = options.value("--due");
            if (due_arg != null) {
                var parsed = parse_due(new DateParser(), due_arg);
                task.due_date = parsed.date;
                if (parsed.time != null) {
                    task.due_time = parsed.time;
                }
            }
        }

        if (options.has("--clear-time")) {
            task.due_time = null;
        } else {
            var time_arg = options.value("--time");
            if (time_arg != null) {
                task.due_time = time_arg;
            }
        }

        var list_arg = options.value("--list");
        if (list_arg != null) {
            task.list_id = resolve_list_id(db, list_arg);
        }

        if (options.has("--clear-notes")) {
            task.notes = null;
        } else {
            var notes = options.value("--notes");
            if (notes != null) {
                task.notes = notes;
            }
        }

        db.update_task(task);
        print_task(json, quiet, task);
        return 0;
    }

    private static int cmd_done(string[] args, string? db_path, bool json, bool quiet, bool completed) throws GLib.Error {
        var options = parse_options(args);
        var id_string = require_positional(options, 0, "id");
        var id = parse_int(id_string, "id");

        var db = open_db(db_path);
        var affected = db.set_task_completed(id, completed);
        if (affected == 0) {
            return fail("Task not found: %lld".printf(id), 3);
        }

        if (json) {
            if (quiet) {
                var obj = new CliJson.Obj();
                obj.boolean("ok", true);
                obj.int64("id", id);
                obj.boolean("completed", completed);
                print_json(obj.render());
            } else {
                var task = db.get_task_by_id(id);
                if (task != null) {
                    print_json(CliJson.task_object(task));
                }
            }
        } else if (!quiet) {
            var task = db.get_task_by_id(id);
            if (task != null) {
                print("%s\n", human_task_line(task));
            }
        }
        return 0;
    }

    private static int cmd_rm(string[] args, string? db_path, bool json, bool quiet) throws GLib.Error {
        var options = parse_options(args);
        var id_string = require_positional(options, 0, "id");
        var id = parse_int(id_string, "id");

        var db = open_db(db_path);
        bool deleted = false;
        try {
            deleted = db.delete_task(id) > 0;
        } catch (GLib.Error e) {
            deleted = false;
        }

        if (json) {
            var obj = new CliJson.Obj();
            obj.boolean("ok", true);
            obj.int64("id", id);
            obj.boolean("deleted", deleted);
            print_json(obj.render());
        } else if (!quiet) {
            print("%s\n", deleted ? "Deleted task %lld".printf(id) : "Task %lld did not exist".printf(id));
        }
        return 0;
    }

    private static int cmd_search(string[] args, string? db_path, bool json, bool quiet) throws GLib.Error {
        var options = parse_options(args);
        var keyword = require_positional(options, 0, "keyword");
        var limit = (int) parse_int(options.value("--limit") ?? "100", "--limit");

        var db = open_db(db_path);
        var results = db.search_tasks(keyword);

        var taken = new GLib.List<TaskItem>();
        var count = 0;
        foreach (var t in results) {
            if (count >= limit) {
                break;
            }
            taken.append(t);
            count++;
        }
        print_tasks(json, quiet, taken);
        return 0;
    }

    private static int cmd_mklist(string[] args, string? db_path, bool json, bool quiet) throws GLib.Error {
        var options = parse_options(args);
        var name = require_positional(options, 0, "name");
        var icon = options.value("--icon");
        var color_hex = options.value("--color");

        var db = open_db(db_path);

        int32? color = null;
        if (color_hex != null) {
            color = parse_color(color_hex);
        }

        // Validate via the same rule as the repositories layer.
        var i18n = new I18n("zh");
        Validation.validate_list_name(name, i18n);

        var id = db.add_list(name.strip(), icon, color);
        var created = db.get_list_by_id(id);

        if (json) {
            if (created != null) {
                print_json(CliJson.list_object(created));
            }
        } else if (quiet) {
            print("%lld\n", id);
        } else {
            var c = created ?? new TodoList();
            if (created == null) {
                c.id = id;
                c.name = name;
                c.icon = icon;
                c.color = color;
            }
            var icon_text = (c.icon != null && c.icon.length > 0) ? c.icon + " " : "";
            print("  %5lld  %s%s  (0)\n", c.id, icon_text, c.name);
        }
        return 0;
    }

    private static int cmd_rmlist(string[] args, string? db_path, bool json, bool quiet) throws GLib.Error {
        var options = parse_options(args);
        var id_string = require_positional(options, 0, "id");
        var id = parse_int(id_string, "id");

        var db = open_db(db_path);
        bool deleted = false;
        try {
            deleted = db.delete_list(id) > 0;
        } catch (GLib.Error e) {
            deleted = false;
        }

        if (json) {
            var obj = new CliJson.Obj();
            obj.boolean("ok", true);
            obj.int64("id", id);
            obj.boolean("deleted", deleted);
            print_json(obj.render());
        } else if (!quiet) {
            print("%s\n", deleted
                ? "Deleted list %lld (and its tasks)".printf(id)
                : "List %lld did not exist".printf(id));
        }
        return 0;
    }
}

}
