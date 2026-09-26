// Taskly — calendar view (PRODUCT-SPEC 4b): compact month grid on top,
// tasks grouped by day below. Seeing and jumping, not editing — rows are
// the standard task rows built through the injected row builder.

namespace Taskly {

public delegate Gtk.Widget TaskRowBuilder(TaskItem task);

public class CalendarView : Object {
    private AppContext ctx;
    private Gtk.Box container;
    private Gtk.ScrolledWindow scroll;
    private unowned TaskRowBuilder build_task_row;
    // Day-group time line column, rebuilt on every render.
    private Gtk.Box timeline_box;
    private GLib.HashTable<string, Gtk.Widget> day_headers =
        new GLib.HashTable<string, Gtk.Widget>(str_hash, str_equal);

    public CalendarView(AppContext ctx, Gtk.Box container, Gtk.ScrolledWindow scroll,
                        TaskRowBuilder builder) {
        this.ctx = ctx;
        this.container = container;
        this.scroll = scroll;
        this.build_task_row = builder;
    }

    public void render() {
        day_headers.remove_all();

        // Two-pane layout (DESIGN-TOKENS calendar time line): fixed-width
        // month column + hairline divider + day-group time line column.
        var month_pane = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        month_pane.width_request = 320;
        month_pane.append(build_nav_row());
        month_pane.append(build_weekday_row());
        month_pane.append(build_month_grid());

        timeline_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        timeline_box.vexpand = true;
        try {
            append_timeline();
        } catch (GLib.Error e) {
            var error_label = new Gtk.Label(e.message);
            error_label.add_css_class("dim-label");
            timeline_box.append(error_label);
        }

        var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        layout.append(month_pane);
        layout.append(new Gtk.Separator(Gtk.Orientation.VERTICAL));
        layout.append(timeline_box);
        container.append(layout);

        var empty_label = new Gtk.Label(ctx.t("taskListEmpty"));
        empty_label.vexpand = true;
        empty_label.add_css_class("dim-label");
        empty_label.visible = day_headers.size() == 0;
        container.append(empty_label);
    }

    // ---------------- month navigation ----------------

    private Gtk.Widget build_nav_row() {
        var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);

        var prev = new Gtk.Button.from_icon_name("go-previous-symbolic");
        prev.add_css_class("flat");
        prev.clicked.connect(() => navigate(-1));

        var title = new Gtk.Label(month_title());
        title.add_css_class("cal-title");
        title.hexpand = true;

        var today_button = new Gtk.Button.with_label(ctx.t("calTodayButton"));
        today_button.add_css_class("flat");
        today_button.clicked.connect(() => {
            go_today();
        });

        var next = new Gtk.Button.from_icon_name("go-next-symbolic");
        next.add_css_class("flat");
        next.clicked.connect(() => navigate(1));

        row.append(prev);
        row.append(title);
        row.append(today_button);
        row.append(next);
        return row;
    }

    /// `{0}年{1}` full-month title, also reused as the calendar subtitle.
    public string month_title() {
        return ctx.i18n.format("calMonthTitle", ctx.calendar_year.to_string(),
            ctx.t("calMonth%d".printf(ctx.calendar_month)));
    }

    private void navigate(int delta) {
        var first = new DateTime.local(ctx.calendar_year, ctx.calendar_month, 1, 0, 0, 0.0);
        var target = first.add_months(delta);
        ctx.calendar_year = target.get_year();
        ctx.calendar_month = target.get_month();
        ctx.calendar_selected_date = "%04d-%02d-01".printf(target.get_year(), target.get_month());
        rerender();
    }

    private void go_today() {
        var now = new DateTime.now_local();
        ctx.calendar_year = now.get_year();
        ctx.calendar_month = now.get_month();
        ctx.calendar_selected_date = now.format("%Y-%m-%d");
        rerender();
    }

    private void rerender() {
        clear_container();
        render();
    }

    private void clear_container() {
        for (var child = container.get_first_child(); child != null;) {
            var next = child.get_next_sibling();
            container.remove(child);
            child = next;
        }
    }

    // ---------------- month grid ----------------

    private Gtk.Widget build_weekday_row() {
        var grid = new Gtk.Grid();
        grid.column_spacing = 2;
        var names = weekday_names();
        for (var i = 0; i < 7; i++) {
            var label = new Gtk.Label(names[i]);
            label.add_css_class("cal-weekday");
            label.hexpand = true;
            grid.attach(label, i, 0, 1, 1);
        }
        return grid;
    }

    private string[] weekday_names() {
        string[] ordered = {};
        if (ctx.config.language() == "zh") {
            for (var i = 1; i <= 7; i++) {
                ordered += ctx.t("calWeekdayShort%d".printf(i));
            }
        } else {
            // en renders Sunday-first; key index 1 = Monday (4b).
            ordered += ctx.t("calWeekdayShort7");
            for (var i = 1; i <= 6; i++) {
                ordered += ctx.t("calWeekdayShort%d".printf(i));
            }
        }
        return ordered;
    }

    private Gtk.Widget build_month_grid() {
        var grid = new Gtk.Grid();
        grid.column_spacing = 2;
        grid.row_spacing = 2;

        var first = new DateTime.local(ctx.calendar_year, ctx.calendar_month, 1, 0, 0, 0.0);
        // GLib day_of_week: 1=Monday … 7=Sunday. Week start follows the
        // language (4b): zh Monday-first, en Sunday-first.
        var monday_first = ctx.config.language() == "zh";
        var dow = first.get_day_of_week();
        var col = monday_first ? dow - 1 : dow % 7;

        // Dynamic row count: pad only to the weeks the month actually
        // occupies (a 6-row grid only when the month needs it).
        var days_in_month = first.add_months(1).add_days(-1).get_day_of_month();
        var cells_needed = col + days_in_month;
        var row_count = (cells_needed + 6) / 7;

        var start = first.add_days(-col);
        var today_key = new DateTime.now_local().format("%Y-%m-%d");

        var dots = load_day_dots();

        for (var i = 0; i < row_count * 7; i++) {
            var day = start.add_days(i);
            var key = day.format("%Y-%m-%d");
            var in_month = day.get_year() == ctx.calendar_year && day.get_month() == ctx.calendar_month;
            grid.attach(build_day_cell(day, key, in_month, key == today_key,
                (int) (dots.lookup(key) ?? 0)), i % 7, i / 7, 1, 1);
        }
        return grid;
    }

    private GLib.HashTable<string, int64?> load_day_dots() {
        var dots = new GLib.HashTable<string, int64?>(str_hash, str_equal);
        try {
            var last = month_end_key();
            foreach (var item in ctx.db.get_due_day_counts(month_start_key(), last)) {
                dots.insert(item.date, item.count);
            }
        } catch (GLib.Error e) {
            // Day dots are decorative; the timeline still renders.
        }
        return dots;
    }

    private string month_start_key() {
        return "%04d-%02d-01".printf(ctx.calendar_year, ctx.calendar_month);
    }

    private string month_end_key() {
        var first = new DateTime.local(ctx.calendar_year, ctx.calendar_month, 1, 0, 0, 0.0);
        var end = first.add_months(1).add_days(-1);
        return end.format("%Y-%m-%d");
    }

    private Gtk.Widget build_day_cell(DateTime day, string key, bool in_month,
                                       bool is_today, int dot_count) {
        var cell = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        cell.add_css_class("cal-cell");
        if (ctx.calendar_selected_date == key) {
            cell.add_css_class("selected");
        }

        var number = new Gtk.Label(day.get_day_of_month().to_string());
        number.add_css_class("day");
        if (is_today) {
            number.add_css_class("today");
        } else if (!in_month) {
            number.add_css_class("out");
        }

        var dots_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
        dots_box.set_halign(Gtk.Align.CENTER);
        for (var i = 0; i < int.min(dot_count, 3); i++) {
            var dot = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            dot.add_css_class("cal-dot");
            dot.width_request = 4;
            dot.height_request = 4;
            dots_box.append(dot);
        }

        cell.append(number);
        cell.append(dots_box);

        var button = new Gtk.Button();
        button.add_css_class("flat");
        button.child = cell;
        var day_key = key;
        button.clicked.connect(() => select_day(day_key));
        return button;
    }

    private void select_day(string day_key) {
        var parts = day_key.split("-");
        if (parts.length != 3) {
            return;
        }
        var year = int.parse(parts[0]);
        var month = int.parse(parts[1]);
        if (year != ctx.calendar_year || month != ctx.calendar_month) {
            // Adjacent-month cell: switch the displayed month first (4b).
            ctx.calendar_year = year;
            ctx.calendar_month = month;
            ctx.calendar_selected_date = day_key;
            rerender();
        } else {
            ctx.calendar_selected_date = day_key;
            // Re-render keeps the month data; highlight only.
            rerender();
        }
        scroll_to_day(day_key);
    }

    private void scroll_to_day(string day_key) {
        var target = day_headers.lookup(day_key);
        if (target == null) {
            return;
        }
        Idle.add(() => {
            Gtk.Allocation alloc;
            target.get_allocation(out alloc);
            scroll.vadjustment.value = alloc.y;
            return Source.REMOVE;
        });
    }

    // ---------------- day-group time line ----------------

    private void append_timeline() throws GLib.Error {
        var now = new DateTime.now_local();
        var today_key = now.format("%Y-%m-%d");
        var before_today = now.add_days(-1).format("%Y-%m-%d");

        var overdue = ctx.db.get_tasks_in_range("1900-01-01", before_today, ctx.show_completed);
        if (overdue.length() > 0) {
            append_group_header(ctx.t("calOverdue"), (int) overdue.length(), false, null);
            foreach (var task in overdue) {
                timeline_box.append(build_task_row(task));
            }
        }

        var month_tasks = ctx.db.get_tasks_in_range(month_start_key(), month_end_key(), ctx.show_completed);
        string? current_key = null;
        GLib.List<TaskItem> current_group = new GLib.List<TaskItem>();
        foreach (var task in month_tasks) {
            var key = task.due_date ?? "";
            if (key != current_key) {
                flush_group(current_key, current_group, today_key);
                current_key = key;
                current_group = new GLib.List<TaskItem>();
            }
            current_group.append(task);
        }
        flush_group(current_key, current_group, today_key);
    }

    private void flush_group(string? key, GLib.List<TaskItem> group, string today_key) {
        if (key == null || key.length == 0 || group.length() == 0) {
            return;
        }
        append_group_header(format_day_header(key), (int) group.length(), key == today_key, key);
        foreach (var task in group) {
            timeline_box.append(build_task_row(task));
        }
    }

    private void append_group_header(string text, int count, bool is_today, string? date_key) {
        var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        row.add_css_class("cal-header");
        if (is_today) {
            row.add_css_class("today-h");
        }
        var label = new Gtk.Label(text);
        label.halign = Gtk.Align.START;
        label.hexpand = true;
        var count_label = new Gtk.Label(count > 0 ? count.to_string() : "");
        count_label.add_css_class("cal-header-count");
        row.append(label);
        row.append(count_label);
        timeline_box.append(row);

        if (date_key != null) {
            day_headers.insert(date_key, row);
        }
    }

    /// Group header text: `9月26日 · 周五` / `Fri, Sep 26`;
    /// today/tomorrow/yesterday replace the weekday slot (4b).
    private string format_day_header(string date_key) {
        var date = parse_date_key(date_key);
        if (date == null) {
            return date_key;
        }
        var now = new DateTime.now_local();
        string weekday_label;
        if (date_key == now.format("%Y-%m-%d")) {
            weekday_label = ctx.t("navToday");
        } else if (date_key == now.add_days(1).format("%Y-%m-%d")) {
            weekday_label = ctx.t("dateTomorrow");
        } else if (date_key == now.add_days(-1).format("%Y-%m-%d")) {
            weekday_label = ctx.t("dateYesterday");
        } else {
            // GLib day_of_week 1..7 maps directly onto calWeekday1..7.
            weekday_label = ctx.t("calWeekday%d".printf(date.get_day_of_week()));
        }
        var month_name = ctx.t("calMonthShort%d".printf(date.get_month()));
        return ctx.i18n.format("calDayHeader", month_name,
            date.get_day_of_month().to_string(), weekday_label);
    }

    private DateTime? parse_date_key(string key) {
        var parts = key.split("-");
        if (parts.length != 3) {
            return null;
        }
        return new DateTime.local(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), 0, 0, 0.0);
    }
}

}
