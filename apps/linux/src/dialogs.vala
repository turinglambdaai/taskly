// Taskly — modal editing dialogs: task detail (text/notes/due date+time/
// move list/delete) and list create/edit (name/icon/color).

namespace Taskly {

public class TaskDetailDialog : Object {

    private TaskDetailDialog() {
    }

    public static void present(AppContext ctx, TaskItem task) {
        var i18n = ctx.i18n;

        var window = new Gtk.Window();
        window.title = i18n.t("dialogTaskDetail");
        window.modal = true;
        window.transient_for = ctx.window;
        window.default_width = 440;
        window.hide_on_close = true;

        var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        content.margin_top = 16;
        content.margin_bottom = 16;
        content.margin_start = 16;
        content.margin_end = 16;

        var task_label = new Gtk.Label(i18n.t("labelTask"));
        task_label.halign = Gtk.Align.START;
        var text_view = new Gtk.TextView();
        text_view.buffer.text = task.text;
        text_view.height_request = 64;
        text_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;

        var notes_label = new Gtk.Label(i18n.t("labelNotes"));
        notes_label.halign = Gtk.Align.START;
        var notes_view = new Gtk.TextView();
        notes_view.buffer.text = task.notes ?? "";
        notes_view.height_request = 72;
        notes_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;

        var date_label = new Gtk.Label(i18n.t("labelDate"));
        date_label.halign = Gtk.Align.START;
        var date_entry = new Gtk.Entry();
        date_entry.placeholder_text = "yyyy-MM-dd";
        if (task.due_date != null) {
            date_entry.text = task.due_date;
        }

        var time_label = new Gtk.Label(i18n.t("labelTime"));
        time_label.halign = Gtk.Align.START;
        var time_entry = new Gtk.Entry();
        time_entry.placeholder_text = "HH:mm";
        time_entry.sensitive = task.due_date != null;
        if (task.due_time != null) {
            time_entry.text = task.due_time;
        }

        var date_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        date_box.append(date_label);
        date_box.append(date_entry);
        var time_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        time_box.append(time_label);
        time_box.append(time_entry);
        var date_time_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        date_entry.hexpand = true;
        time_entry.hexpand = true;
        date_time_row.append(date_box);
        date_time_row.append(time_box);

        // Move to list
        var move_label = new Gtk.Label(i18n.t("menuMoveToList"));
        move_label.halign = Gtk.Align.START;
        var combo = new Gtk.ComboBoxText();
        var selected_active = "0";
        try {
            foreach (var list in ctx.db.get_all_lists()) {
                var id_str = list.id.to_string();
                combo.append(id_str, "%s %s".printf(list.icon_or_default(), list.name));
                if (list.id == task.list_id) {
                    selected_active = id_str;
                }
            }
        } catch (GLib.Error e) {
            // Empty combo; save keeps the original list.
        }
        combo.active_id = selected_active;

        content.append(task_label);
        content.append(text_view);
        content.append(notes_label);
        content.append(notes_view);
        content.append(date_time_row);
        content.append(move_label);
        content.append(combo);

        var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var delete_button = new Gtk.Button.with_label(i18n.t("taskDelete"));
        var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        spacer.hexpand = true;
        var cancel_button = new Gtk.Button.with_label(i18n.t("dialogCancel"));
        var save_button = new Gtk.Button.with_label(i18n.t("dialogSave"));
        save_button.add_css_class("suggested-action");
        buttons.append(delete_button);
        buttons.append(spacer);
        buttons.append(cancel_button);
        buttons.append(save_button);
        content.append(buttons);

        window.child = content;

        // Date/time clearing buttons (small "clear" behavior: empty entry).
        delete_button.clicked.connect(() => {
            var confirm = new Gtk.MessageDialog(window, Gtk.DialogFlags.MODAL,
                Gtk.MessageType.QUESTION, Gtk.ButtonsType.OK_CANCEL,
                "%s", i18n.t("taskDeleteConfirmContent"));
            confirm.response.connect((dialog, response) => {
                dialog.destroy();
                if (response == Gtk.ResponseType.OK) {
                    try {
                        ctx.db.delete_task(task.id);
                        ctx.reminder.reset_notified();
                    } catch (GLib.Error e) {
                        // ignore
                    }
                    (ctx.ui_ref()).refresh_all();
                    ctx.flash_status(i18n.t("statusTaskDeleted"));
                    window.destroy();
                }
            });
            confirm.present();
        });

        cancel_button.clicked.connect(() => window.destroy());

        save_button.clicked.connect(() => {
            var start = Gtk.TextIter();
            var end = Gtk.TextIter();
            text_view.buffer.get_bounds(out start, out end);
            var text = text_view.buffer.get_text(start, end, true).strip();
            if (text.length == 0) {
                return; // blank text silently keeps the dialog open
            }

            var n_start = Gtk.TextIter();
            var n_end = Gtk.TextIter();
            notes_view.buffer.get_bounds(out n_start, out n_end);
            var notes_raw = notes_view.buffer.get_text(n_start, n_end, true).strip();

            var date_raw = date_entry.text.strip();
            var time_raw = time_entry.text.strip();
            var parser = new DateParser();

            string? due_date = null;
            if (date_raw.length > 0) {
                var parsed = parser.parse(date_raw);
                due_date = parsed != null ? DateParser.extract_date_only(parsed) : normalize_date(date_raw);
            }
            string? due_time = null;
            if (date_raw.length > 0 && time_raw.length > 0) {
                due_time = normalize_time(time_raw);
            }

            var updated = task.clone();
            updated.text = text;
            updated.notes = notes_raw.length > 0 ? notes_raw : null;
            updated.due_date = due_date;
            updated.due_time = due_time;
            updated.list_id = combo.active_id != null
                ? int64.parse(combo.active_id)
                : task.list_id;
            if (updated.created_at.length == 0) {
                updated.created_at = DateParser.created_at_now();
            }

            try {
                Validation.validate_task_text(updated.text, i18n);
                ctx.db.update_task(updated);
                ctx.reminder.reset_notified();
                (ctx.ui_ref()).refresh_all();
                ctx.flash_status(i18n.t("statusTaskUpdated"));
                window.destroy();
            } catch (GLib.Error e) {
                ctx.flash_status(e.message);
            }
        });

        window.present();
    }

    private static string? normalize_date(string s) {
        return DateParser.parse_absolute_public(s);
    }

    private static string? normalize_time(string s) {
        if (s.length != 5 || s[2] != ':') {
            return null;
        }
        var hour = int.parse(s.substring(0, 2));
        var minute = int.parse(s.substring(3, 2));
        if (hour > 23 || minute > 59 || !all_digits(s.substring(0, 2)) || !all_digits(s.substring(3, 2))) {
            return null;
        }
        return s;
    }

    private static bool all_digits(string s) {
        foreach (var c in s.data) {
            if (c < '0' || c > '9') {
                return false;
            }
        }
        return true;
    }
}

public class ListEditDialog : Object {

    private ListEditDialog() {
    }

    public static void present(AppContext ctx, TodoList? existing) {
        var i18n = ctx.i18n;
        var creating = existing == null;

        var window = new Gtk.Window();
        window.title = creating ? i18n.t("dialogCreateList") : i18n.t("dialogEditList");
        window.modal = true;
        window.transient_for = ctx.window;
        window.default_width = 380;
        window.hide_on_close = true;

        var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        content.margin_top = 16;
        content.margin_bottom = 16;
        content.margin_start = 16;
        content.margin_end = 16;

        var name_entry = new Gtk.Entry();
        name_entry.placeholder_text = i18n.t("dialogInputListName");
        if (existing != null) {
            name_entry.text = existing.name;
        }

        var icon_label = new Gtk.Label(i18n.t("dialogListIcon"));
        icon_label.halign = Gtk.Align.START;
        var icon_combo = new Gtk.ComboBoxText();
        string? current_icon = existing != null ? existing.icon : null;
        var icon_active = "";
        foreach (var emoji in EMOJI_ALL) {
            icon_combo.append(emoji, emoji);
            if (current_icon != null && current_icon == emoji) {
                icon_active = emoji;
            }
        }
        icon_combo.append("", i18n.t("dialogClearIcon"));
        icon_combo.active_id = icon_active.length > 0 ? icon_active : "";

        var color_label = new Gtk.Label(i18n.t("dialogListColor"));
        color_label.halign = Gtk.Align.START;
        var color_combo = new Gtk.ComboBoxText();
        var current_color = existing != null && existing.color != null
            ? (uint32) existing.color : 0xFF000000u | 0xC15F3C;
        var color_active = "";
        foreach (var rgb in LIST_COLORS_RGB) {
            var id_str = "FF" + rgb;
            var value = 0xFF000000u | strtoul_hex32(rgb);
            color_combo.append(id_str, "#" + rgb);
            if (current_color == value) {
                color_active = id_str;
            }
        }
        color_combo.append("", i18n.t("dialogClearColor"));
        color_combo.active_id = color_active.length > 0 ? color_active : "";

        content.append(name_entry);
        content.append(icon_label);
        content.append(icon_combo);
        content.append(color_label);
        content.append(color_combo);

        var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        spacer.hexpand = true;
        var cancel_button = new Gtk.Button.with_label(i18n.t("dialogCancel"));
        var save_button = new Gtk.Button.with_label(i18n.t("dialogConfirm"));
        save_button.add_css_class("suggested-action");
        buttons.append(spacer);
        buttons.append(cancel_button);
        buttons.append(save_button);
        content.append(buttons);

        window.child = content;

        cancel_button.clicked.connect(() => window.destroy());

        save_button.clicked.connect(() => {
            var name = name_entry.text.strip();
            if (name.length == 0) {
                return; // blank name keeps the dialog open (reference behavior)
            }

            var icon_id = icon_combo.active_id;
            string? icon = (icon_id != null && icon_id.length > 0) ? icon_id : null;
            var color_id = color_combo.active_id;
            int32? color = null;
            if (color_id != null && color_id.length > 0) {
                color = (int32) strtoul_hex32(color_id);
            }
            try {
                if (creating) {
                    var id = ctx.db.add_list(name, icon, color);
                    ctx.flash_status(i18n.format("statusCreateList", name));
                    select_created(ctx, id);
                } else {
                    var list = existing;
                    var clear_icon = icon == null && list.icon != null;
                    var clear_color = color == null && list.color != null;
                    ctx.db.update_list(list.id, name, icon, color, clear_icon, clear_color);
                }
                (ctx.ui_ref()).refresh_all();
                window.destroy();
            } catch (GLib.Error e) {
                ctx.flash_status(e.message);
            }
        });

        window.present();
    }

    private static void select_created(AppContext ctx, int64 id) {
        // Jump to the freshly created list, mirroring the reference behavior.
        ctx.current_list_id = id;
        ctx.current_view = TaskViewType.LIST;
        ctx.config.set_last_selected_list_id(id);
    }

    private static uint32 strtoul_hex32(string hex) {
        uint32 value = 0;
        for (var i = 0; i < hex.length; i++) {
            var c = hex[i];
            value <<= 4;
            if (c >= '0' && c <= '9') {
                value += c - '0';
            } else if (c >= 'a' && c <= 'f') {
                value += c - 'a' + 10;
            } else if (c >= 'A' && c <= 'F') {
                value += c - 'A' + 10;
            }
        }
        return value;
    }
}

}
