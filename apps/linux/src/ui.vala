// Taskly — GTK4/libadwaita UI: header bar + paned (sidebar | task pane) +
// status bar, warm palette via CSS. All state on the main loop; DB access
// is synchronous (local SQLite).

namespace Taskly {

public class AppContext : Object {
    public SQLiteDatabase db;
    public I18n i18n;
    public Config config;
    public DateParser parser = new DateParser();
    public ReminderService reminder;
    public TaskViewType current_view = TaskViewType.ALL;
    public int64 current_list_id = 0;
    public bool show_completed = false;
    public Gtk.Window window; // transient parent for dialogs
    public TasklyUi? ui = null; // set after the window is built

    public AppContext(SQLiteDatabase db, I18n i18n, Config config) {
        this.db = db;
        this.i18n = i18n;
        this.config = config;
        this.reminder = new ReminderService(db, i18n);
    }

    public string t(string key) {
        return i18n.t(key);
    }

    /// Used by dialogs to refresh the main view after commits.
    public TasklyUi? ui_ref() {
        return ui;
    }

    public void flash_status(string message) {
        if (ui != null) {
            ui.flash(message);
        }
    }

    public string view_title() {
        switch (current_view) {
            case TaskViewType.TODAY: return t("navToday");
            case TaskViewType.PLANNED: return t("navPlanned");
            case TaskViewType.COMPLETED: return t("navCompleted");
            case TaskViewType.LIST: return list_name_or_placeholder();
            default: return t("navAll");
        }
    }

    public string list_name_or_placeholder() {
        try {
            var list = db.get_list_by_id(current_list_id);
            return list != null ? list.name : "List %lld".printf(current_list_id);
        } catch (GLib.Error e) {
            return "List %lld".printf(current_list_id);
        }
    }
}

public class TasklyUi : Object {
    private AppContext ctx;

    private Gtk.Label title_label;
    private Gtk.Label status_label;
    private Gtk.Button show_completed_button;
    private Gtk.Box lists_box;
    private Gtk.Box tasks_box;
    private Gtk.Entry quick_add;
    private Gtk.Entry search;
    private Gtk.Box input_area;
    private GLib.HashTable<TaskViewType, Gtk.Label> tile_counts;
    private GLib.HashTable<Gtk.Button, TaskViewType> tile_buttons;
    private uint flash_source = 0;

    public TasklyUi(AppContext ctx) {
        this.ctx = ctx;
        tile_counts = new GLib.HashTable<TaskViewType, Gtk.Label>(int_hash, int_equal);
        tile_buttons = new GLib.HashTable<Gtk.Button, TaskViewType>(direct_hash, direct_equal);
    }

    public const string APP_CSS = """
window.taskly-root { background-color: #F4F3EE; }
.sidebar { background-color: #ECEAE3; border-right: 1px solid #D9D6CE; }
.smart-tile { color: white; border-radius: 12px; padding: 8px 10px; }
.smart-tile.today { background-color: #C15F3C; }
.smart-tile.planned { background-color: #B5543A; }
.smart-tile.all { background-color: #8E887E; }
.smart-tile.completed { background-color: #6B8E5A; }
.smart-tile .title { font-weight: 600; }
.smart-tile .count { opacity: 0.85; font-size: 11px; }
.task-row { border-radius: 10px; padding: 8px 12px; }
.task-row.completed .task-text { color: #9B9890; text-decoration: line-through; }
.task-meta { color: #6B6862; font-size: 12px; }
.section-header { color: #6B6862; font-weight: 600; }
.statusbar { background-color: #ECEAE3; border-top: 1px solid #D9D6CE; }
""";

    public void build(Adw.Application app) {
        load_css();

        var win = new Adw.ApplicationWindow(app);
        win.title = "Taskly";
        win.default_width = 1024;
        win.default_height = 768;
        win.add_css_class("taskly-root");
        ctx.window = win;

        title_label = new Gtk.Label(null);
        title_label.add_css_class("title");
        title_label.add_css_class("header-title");

        status_label = new Gtk.Label(ctx.t("statusDatabaseConnected"));
        status_label.halign = Gtk.Align.START;
        status_label.margin_start = 12;

        var sidebar_button = new Gtk.ToggleButton();
        sidebar_button.icon_name = "sidebar-show-symbolic";
        sidebar_button.active = true;

        show_completed_button = new Gtk.Button();
        show_completed_button.add_css_class("flat");
        show_completed_button.clicked.connect(() => {
            ctx.show_completed = !ctx.show_completed;
            refresh_all();
        });

        // App menu: language + CLI installer
        var menu_button = new Gtk.MenuButton();
        menu_button.icon_name = "open-menu-symbolic";
        menu_button.menu_model = build_menu(win);

        var header = new Adw.HeaderBar();
        header.set_title_widget(title_label);
        header.pack_start(sidebar_button);
        header.pack_end(menu_button);
        header.pack_end(show_completed_button);

        // Sidebar
        var sidebar = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        sidebar.add_css_class("sidebar");
        sidebar.margin_top = 12;
        sidebar.margin_bottom = 12;
        sidebar.margin_start = 12;
        sidebar.margin_end = 12;
        sidebar.width_request = 200;

        var tiles_grid = new Gtk.Grid();
        tiles_grid.column_spacing = 8;
        tiles_grid.row_spacing = 8;

        add_tile(tiles_grid, "navToday", "🗓", "today", TaskViewType.TODAY, 0, 0);
        add_tile(tiles_grid, "navPlanned", "📅", "planned", TaskViewType.PLANNED, 0, 1);
        add_tile(tiles_grid, "navAll", "≡", "all", TaskViewType.ALL, 1, 0);
        add_tile(tiles_grid, "navCompleted", "✓", "completed", TaskViewType.COMPLETED, 1, 1);
        sidebar.append(tiles_grid);

        var lists_header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var lists_label = new Gtk.Label(ctx.t("sectionMyLists"));
        lists_label.add_css_class("section-header");
        lists_label.halign = Gtk.Align.START;
        lists_label.hexpand = true;
        var add_list_button = new Gtk.Button.from_icon_name("list-add-symbolic");
        add_list_button.add_css_class("flat");
        add_list_button.tooltip_text = ctx.t("dialogCreateList");
        add_list_button.clicked.connect(() => {
            ListEditDialog.present(ctx, null);
        });
        lists_header.append(lists_label);
        lists_header.append(add_list_button);
        sidebar.append(lists_header);

        lists_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        sidebar.append(lists_box);

        // Task pane
        var task_pane = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        task_pane.margin_top = 8;
        task_pane.margin_bottom = 8;
        task_pane.margin_start = 12;
        task_pane.margin_end = 12;
        task_pane.hexpand = true;

        search = new Gtk.Entry();
        search.placeholder_text = ctx.t("searchHint");
        search.changed.connect(() => refresh_all());

        quick_add = new Gtk.Entry();
        quick_add.placeholder_text = ctx.t("taskListInputHint");
        quick_add.hexpand = true;
        quick_add.activate.connect(() => {
            var text = quick_add.text;
            quick_add.set_text("");
            submit_quick_add(text);
        });

        input_area = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        input_area.append(search);
        input_area.append(quick_add);
        task_pane.append(input_area);

        var tasks_scroll = new Gtk.ScrolledWindow();
        tasks_scroll.vexpand = true;
        tasks_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        tasks_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        tasks_scroll.child = tasks_box;
        task_pane.append(tasks_scroll);

        // Layout
        var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
        paned.position = 280;
        paned.set_start_child(sidebar);
        paned.set_end_child(task_pane);
        paned.vexpand = true;
        paned.hexpand = true;

        var statusbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        statusbar.add_css_class("statusbar");
        statusbar.height_request = 28;
        statusbar.append(status_label);

        var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        root.append(header);
        root.append(paned);
        root.append(statusbar);
        win.set_content(root);

        ctx.ui = this;

        sidebar_button.toggled.connect(() => {
            paned.position = sidebar_button.active ? 280 : 0;
        });

        win.present();

        // Reminders: startup check + 60 s poll on the main loop.
        ctx.reminder.start();

        refresh_all();
    }

    private void load_css() {
        var provider = new Gtk.CssProvider();
        try {
            provider.load_from_string(APP_CSS);
        } catch (Error e) {
            // Styling failure is non-fatal (native Adwaita look remains).
        }
        var display = Gdk.Display.get_default();
        if (display != null) {
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
    }

    private GLib.Menu build_menu(Gtk.ApplicationWindow win) {
        var lang_zh = new GLib.SimpleAction("lang-zh", null);
        lang_zh.activate.connect(() => set_language("zh"));
        win.add_action(lang_zh);

        var lang_en = new GLib.SimpleAction("lang-en", null);
        lang_en.activate.connect(() => set_language("en"));
        win.add_action(lang_en);

        var install_action = new GLib.SimpleAction("install-cli", null);
        install_action.activate.connect(() => {
            var code = CliInstaller.install();
            flash(code == 0 ? "taskly installed" : "taskly install failed");
        });
        win.add_action(install_action);

        var uninstall_action = new GLib.SimpleAction("uninstall-cli", null);
        uninstall_action.activate.connect(() => {
            var code = CliInstaller.uninstall();
            flash(code == 0 ? "taskly removed" : "taskly remove failed");
        });
        win.add_action(uninstall_action);

        var menu = new GLib.Menu();
        var lang_section = new GLib.Menu();
        lang_section.append("简体中文", "win.lang-zh");
        lang_section.append("English", "win.lang-en");
        menu.append_section(ctx.t("menuLanguage"), lang_section);
        menu.append(ctx.t("menuInstallCli"), "win.install-cli");
        menu.append(ctx.t("menuUninstallCli"), "win.uninstall-cli");
        return menu;
    }

    private void set_language(string lang) {
        ctx.i18n.set_language(lang);
        ctx.config.set_value("language", lang);
        ctx.config.save();
        refresh_all();
    }

    private void add_tile(Gtk.Grid grid, string key, string icon, string css,
                          TaskViewType view, int row, int col) {
        var button = new Gtk.Button();
        button.add_css_class("smart-tile");
        button.add_css_class(css);
        button.hexpand = true;

        var tile_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        var count_label = new Gtk.Label(null);
        count_label.add_css_class("count");
        count_label.halign = Gtk.Align.END;
        var title = new Gtk.Label("%s %s".printf(icon, ctx.t(key)));
        title.add_css_class("title");
        title.halign = Gtk.Align.START;
        title.hexpand = true;
        tile_box.append(count_label);
        tile_box.append(title);
        button.child = tile_box;

        grid.attach(button, col, row, 1, 1);
        tile_counts[view] = count_label;
        tile_buttons[button] = view;
        button.clicked.connect(() => select_view(view));
    }

    // ---------------- actions ----------------

    private void select_view(TaskViewType view) {
        ctx.current_view = view;
        refresh_all();
    }

    public void submit_quick_add(string raw) {
        var trimmed = raw.strip();
        if (trimmed.length == 0) {
            return;
        }

        var extracted = ctx.parser.extract_time_command(trimmed);
        string? due_date = null;
        string? due_time = null;
        if (extracted.command != null) {
            var parsed = ctx.parser.parse(extracted.command);
            if (parsed != null) {
                var last = extracted.command.substring(extracted.command.length - 1);
                var is_date_only = !extracted.command.has_prefix("@")
                    && (last == "d" || last == "w" || last == "M");
                due_date = DateParser.extract_date_only(parsed);
                if (!is_date_only) {
                    due_time = DateParser.extract_time_only(parsed);
                }
            }
        }

        int64 list_id;
        if (ctx.current_view == TaskViewType.LIST && ctx.current_list_id > 0) {
            list_id = ctx.current_list_id;
        } else {
            try {
                var lists = ctx.db.get_all_lists();
                if (lists.length() == 0) {
                    flash(ctx.t("taskCreateListFirst"));
                    return;
                }
                list_id = lists.nth_data(0).id;
            } catch (GLib.Error e) {
                flash(e.message);
                return;
            }
        }

        var task = new TaskItem();
        task.list_id = list_id;
        task.text = extracted.text.length > 0 ? extracted.text : trimmed;
        task.created_at = DateParser.created_at_now();
        task.due_date = due_date;
        task.due_time = due_time;

        try {
            Validation.validate_task_text(task.text, ctx.i18n);
            task.id = ctx.db.add_task(task);
            refresh_all();
            flash(ctx.t("statusTaskAdded"));
        } catch (GLib.Error e) {
            flash(e.message);
        }
    }

    public void flash(string message) {
        status_label.label = message;
        if (flash_source != 0) {
            Source.remove(flash_source);
        }
        flash_source = Timeout.add_seconds(3, () => {
            flash_source = 0;
            refresh_all();
            return Source.REMOVE;
        });
    }

    // ---------------- refresh ----------------

    public void refresh_all() {
        var i18n = ctx.i18n;
        var search_text = search.text;
        var view = ctx.current_view;

        // Title + status
        string title;
        string status;
        if (search_text.length > 0) {
            title = "%s: %s".printf(i18n.t("searchHint"), search_text);
            status = title;
        } else {
            title = ctx.view_title();
            status = view_status();
        }
        title_label.label = title;

        // Completed toggle
        show_completed_button.label = ctx.show_completed
            ? i18n.t("hideCompletedToggle")
            : i18n.t("showCompletedToggle");

        // Counts
        try {
            var today = ctx.db.get_today_task_count();
            var planned = ctx.db.get_planned_task_count();
            var all = ctx.db.get_incomplete_task_count();
            var completed = ctx.db.get_completed_task_count();
            set_count(TaskViewType.TODAY, today);
            set_count(TaskViewType.PLANNED, planned);
            set_count(TaskViewType.ALL, all);
            set_count(TaskViewType.COMPLETED, completed);
        } catch (GLib.Error e) {
            // Count refresh failure: leave previous values.
        }

        rebuild_lists();
        rebuild_tasks(search_text);
        status_label.label = status;
        quick_add.placeholder_text = ctx.t("taskListInputHint");
        search.placeholder_text = ctx.t("searchHint");
    }

    private string view_status() {
        switch (ctx.current_view) {
            case TaskViewType.TODAY: return ctx.t("statusShowToday");
            case TaskViewType.PLANNED: return ctx.t("statusShowPlanned");
            case TaskViewType.COMPLETED: return ctx.t("statusShowCompleted");
            case TaskViewType.LIST:
                return ctx.t("statusSwitchList").replace("{0}", ctx.list_name_or_placeholder());
            default: return ctx.t("statusShowAll");
        }
    }

    private void set_count(TaskViewType view, int64 count) {
        var label = tile_counts.lookup(view);
        if (label != null) {
            label.label = count > 0 ? count.to_string() : "";
        }
    }

    private void rebuild_lists() {
        for (var child = lists_box.get_first_child(); child != null;) {
            var next = child.get_next_sibling();
            lists_box.remove(child);
            child = next;
        }

        GLib.List<TodoList> lists = new GLib.List<TodoList>();
        try {
            lists = ctx.db.get_all_lists();
        } catch (GLib.Error e) {
            return;
        }

        foreach (var list in lists) {
            try {
                list.pending_count = ctx.db.get_task_count_by_list(list.id);
            } catch (GLib.Error e) {
                list.pending_count = 0;
            }
            append_list_row(list);
        }
    }

    private void append_list_row(TodoList list) {
        var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        row.margin_top = 4;
        row.margin_bottom = 4;

        var icon_label = new Gtk.Label(list.icon_or_default());
        var name_label = new Gtk.Label(list.name);
        name_label.halign = Gtk.Align.START;
        name_label.hexpand = true;
        name_label.ellipsize = Pango.EllipsizeMode.END;
        var pending_label = new Gtk.Label(list.pending_count > 0 ? list.pending_count.to_string() : "");
        pending_label.add_css_class("dim-label");

        var edit_button = new Gtk.Button.from_icon_name("document-edit-symbolic");
        edit_button.add_css_class("flat");
        edit_button.tooltip_text = ctx.t("dialogEditList");

        row.append(icon_label);
        row.append(name_label);
        row.append(pending_label);
        row.append(edit_button);

        var row_button = new Gtk.Button();
        row_button.add_css_class("flat");
        row_button.child = row;

        var list_id = list.id;
        var current_list_id = list_id;
        row_button.clicked.connect(() => {
            select_list(current_list_id);
        });
        edit_button.clicked.connect(() => {
            try {
                var fresh = ctx.db.get_list_by_id(list_id);
                if (fresh != null) {
                    ListEditDialog.present(ctx, fresh);
                }
            } catch (GLib.Error e) {
                flash(e.message);
            }
        });

        lists_box.append(row_button);
    }

    private void select_list(int64 list_id) {
        ctx.current_list_id = list_id;
        ctx.current_view = TaskViewType.LIST;
        ctx.config.set_last_selected_list_id(list_id);
        refresh_all();
    }

    private void rebuild_tasks(string search_text) {
        for (var child = tasks_box.get_first_child(); child != null;) {
            var next = child.get_next_sibling();
            tasks_box.remove(child);
            child = next;
        }

        GLib.List<TaskItem> tasks = new GLib.List<TaskItem>();
        try {
            if (search_text.length > 0) {
                tasks = ctx.db.search_tasks(search_text);
            } else {
                tasks = tasks_for_view();
            }
        } catch (GLib.Error e) {
            // fall through with empty list
        }

        if (tasks.length() == 0) {
            var empty = new Gtk.Label(ctx.t("taskListEmpty"));
            empty.vexpand = true;
            empty.add_css_class("dim-label");
            tasks_box.append(empty);
            return;
        }

        foreach (var task in tasks) {
            tasks_box.append(build_task_row(task));
        }
    }

    private GLib.List<TaskItem> tasks_for_view() throws GLib.Error {
        switch (ctx.current_view) {
            case TaskViewType.TODAY:
                return ctx.show_completed ? ctx.db.get_today_tasks_including_completed()
                                          : ctx.db.get_today_tasks();
            case TaskViewType.PLANNED:
                return ctx.show_completed ? ctx.db.get_planned_tasks_including_completed()
                                          : ctx.db.get_planned_tasks();
            case TaskViewType.COMPLETED:
                return ctx.db.get_completed_tasks();
            case TaskViewType.LIST:
                return ctx.show_completed
                    ? ctx.db.get_tasks_by_list_including_completed(ctx.current_list_id)
                    : ctx.db.get_tasks_by_list(ctx.current_list_id);
            default:
                return ctx.show_completed ? ctx.db.get_all_tasks_including_completed()
                                          : ctx.db.get_incomplete_tasks();
        }
    }

    private Gtk.Widget build_task_row(TaskItem task) {
        var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        row.add_css_class("task-row");
        if (task.completed) {
            row.add_css_class("completed");
        }

        var checkbox = new Gtk.CheckButton();
        checkbox.active = task.completed;

        var text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        text_box.hexpand = true;

        var text_label = new Gtk.Label(task.text);
        text_label.add_css_class("task-text");
        text_label.halign = Gtk.Align.START;
        text_label.wrap = true;
        text_label.xalign = 0.0f;
        text_box.append(text_label);

        var due_display = format_due_display(task);
        if (due_display.length > 0) {
            var meta = new Gtk.Label("🗓 " + due_display);
            meta.add_css_class("task-meta");
            meta.halign = Gtk.Align.START;
            meta.xalign = 0.0f;
            text_box.append(meta);
        }
        if (task.notes != null && task.notes.length > 0) {
            var notes_label = new Gtk.Label(task.notes);
            notes_label.add_css_class("task-meta");
            notes_label.halign = Gtk.Align.START;
            notes_label.xalign = 0.0f;
            notes_label.ellipsize = Pango.EllipsizeMode.END;
            text_box.append(notes_label);
        }

        var detail_button = new Gtk.Button.from_icon_name("dialog-information-symbolic");
        detail_button.add_css_class("flat");
        detail_button.tooltip_text = ctx.t("tooltipTaskEdit");

        row.append(checkbox);
        row.append(text_box);
        row.append(detail_button);

        var task_id = task.id;
        checkbox.toggled.connect(() => {
            try {
                ctx.db.set_task_completed(task_id, checkbox.active);
                refresh_all();
            } catch (GLib.Error e) {
                flash(e.message);
            }
        });
        detail_button.clicked.connect(() => {
            try {
                var fresh = ctx.db.get_task_by_id(task_id);
                if (fresh != null) {
                    TaskDetailDialog.present(ctx, fresh);
                }
            } catch (GLib.Error e) {
                flash(e.message);
            }
        });

        return row;
    }

    private string format_due_display(TaskItem task) {
        var date_only = DateParser.extract_date_only(task.due_date);
        if (date_only == null) {
            return "";
        }
        var now = new DateTime.now_local();
        var label = date_only;
        if (date_only == now.format("%Y-%m-%d")) {
            label = ctx.t("navToday");
        } else if (date_only == now.add_days(1).format("%Y-%m-%d")) {
            label = ctx.i18n.t("dateTomorrow");
        } else if (date_only == now.add_days(-1).format("%Y-%m-%d")) {
            label = ctx.i18n.t("dateYesterday");
        }
        if (task.due_time != null && task.due_time.length > 0) {
            return "%s %s".printf(label, task.due_time);
        }
        return label;
    }
}

}
