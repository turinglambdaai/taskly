//! Modal editing dialogs: task detail (text/notes/due date+time/move list/
//! delete) and list create/edit (name/icon/color). Plain gtk::Window with
//! entries — deliberately conservative for reviewability.

use std::rc::Rc;

use adw::prelude::*;
use gtk::Orientation;

use crate::db::created_at_now;
use crate::date_parser::{DateParser, DATE_FORMAT, TIME_FORMAT};
use crate::models::{TaskItem, TodoList, DEFAULT_LIST_COLOR, DEFAULT_LIST_ICON};
use crate::repositories_palette::{EMOJI_CATEGORIES, LIST_COLORS_HEX};
use crate::ui::{SharedUi, Ui};

/// Task detail: edit text/notes/due date/due time, move to list, delete.
pub struct TaskDetailDialog {
    window: gtk::Window,
}

impl TaskDetailDialog {
    pub fn open(ui: SharedUi, task: TaskItem) {
        let i18n = ui.state.i18n.clone();

        let window = gtk::Window::builder()
            .title(&i18n.t("dialogTaskDetail"))
            .modal(true)
            .transient_for(&ui.window)
            .default_width(440)
            .hide_on_close(true)
            .build();

        let content = gtk::Box::new(Orientation::Vertical, 12);
        content.set_margin_top(16);
        content.set_margin_bottom(16);
        content.set_margin_start(16);
        content.set_margin_end(16);

        let task_label = gtk::Label::new(Some(&i18n.t("labelTask")));
        task_label.set_halign(gtk::Align::Start);
        let text_view = gtk::TextView::new();
        text_view.get_buffer().set_text(&task.text);
        text_view.set_height_request(64);

        let notes_label = gtk::Label::new(Some(&i18n.t("labelNotes")));
        notes_label.set_halign(gtk::Align::Start);
        let notes_view = gtk::TextView::new();
        notes_view.get_buffer().set_text(task.notes.as_deref().unwrap_or(""));
        notes_view.set_height_request(72);

        let date_label = gtk::Label::new(Some(&i18n.t("labelDate")));
        date_label.set_halign(gtk::Align::Start);
        let date_entry = gtk::Entry::new();
        date_entry.set_placeholder_text(Some("yyyy-MM-dd"));
        if let Some(due) = &task.due_date {
            date_entry.set_text(due);
        }

        let time_label = gtk::Label::new(Some(&i18n.t("labelTime")));
        time_label.set_halign(gtk::Align::Start);
        let time_entry = gtk::Entry::new();
        time_entry.set_placeholder_text(Some("HH:mm"));
        time_entry.set_sensitive(task.due_date.is_some());
        if let Some(time) = &task.due_time {
            time_entry.set_text(time);
        }

        let date_box = gtk::Box::new(Orientation::Vertical, 4);
        date_box.append(&date_label);
        date_box.append(&date_entry);
        let time_box = gtk::Box::new(Orientation::Vertical, 4);
        time_box.append(&time_label);
        time_box.append(&time_entry);
        let date_time_row = gtk::Box::new(Orientation::Horizontal, 12);
        date_entry.set_hexpand(true);
        time_entry.set_hexpand(true);
        date_time_row.append(&date_box);
        date_time_row.append(&time_box);

        // Move to list
        let move_label = gtk::Label::new(Some(&i18n.t("menuMoveToList")));
        move_label.set_halign(gtk::Align::Start);
        let combo = gtk::ComboBoxText::new();
        let lists = ui.state.db.get_all_lists().unwrap_or_default();
        let mut selected = 0usize;
        for (index, list) in lists.iter().enumerate() {
            combo.append(Some(&list.id.to_string()), &format!(
                "{} {}",
                list.icon.clone().unwrap_or_else(|| DEFAULT_LIST_ICON.to_string()),
                list.name
            ));
            if list.id == task.list_id {
                selected = index;
            }
        }
        combo.set_active(Some(selected as u32));

        content.append(&task_label);
        content.append(&text_view);
        content.append(&notes_label);
        content.append(&notes_view);
        content.append(&date_time_row);
        content.append(&move_label);
        content.append(&combo);

        // Buttons
        let buttons = gtk::Box::new(Orientation::Horizontal, 8);
        let delete_button = gtk::Button::with_label(&i18n.t("taskDelete"));
        let spacer = gtk::Box::new(Orientation::Horizontal, 0);
        spacer.set_hexpand(true);
        let cancel_button = gtk::Button::with_label(&i18n.t("dialogCancel"));
        let save_button = gtk::Button::with_label(&i18n.t("dialogSave"));
        save_button.add_css_class("suggested-action");
        buttons.append(&delete_button);
        buttons.append(&spacer);
        buttons.append(&cancel_button);
        buttons.append(&save_button);
        content.append(&buttons);

        window.set_child(Some(&content));

        // Delete: confirm, then delete + refresh + close.
        {
            let window = window.clone();
            let ui = Rc::clone(&ui);
            let i18n = i18n.clone();
            let task_id = task.id;
            delete_button.connect_clicked(move |_| {
                let confirm = gtk::MessageDialog::new(
                    Some(&window),
                    gtk::DialogFlags::MODAL,
                    gtk::MessageType::Question,
                    gtk::ButtonsType::OkCancel,
                    &i18n.t("taskDeleteConfirmContent"),
                );
                let ui = Rc::clone(&ui);
                let window = window.clone();
                confirm.connect_response(move |dialog, response| {
                    dialog.close();
                    if response == gtk::ResponseType::Ok {
                        let _ = ui.state.db.delete_task(task_id);
                        ui.refresh_all();
                        ui.flash(&ui.state.i18n.t("statusTaskDeleted"));
                        window.close();
                    }
                });
                confirm.show();
            });
        }

        {
            let window = window.clone();
            cancel_button.connect_clicked(move |button| {
                let _ = button;
                window.close();
            });
        }

        {
            let window = window.clone();
            let ui = Rc::clone(&ui);
            let date_entry = date_entry.clone();
            let time_entry = time_entry.clone();
            let text_view = text_view.clone();
            let notes_view = notes_view.clone();
            save_button.connect_clicked(move |button| {
                let _ = button;
                let buffer = text_view.buffer();
                let text = buffer.text(&buffer.start_iter(), &buffer.end_iter(), true).trim().to_string();
                if text.is_empty() {
                    return; // blank text silently keeps the dialog open
                }

                let notes_buffer = notes_view.buffer();
                let notes_raw = notes_buffer
                    .text(&notes_buffer.start_iter(), &notes_buffer.end_iter(), true)
                    .trim()
                    .to_string();

                let date_raw = date_entry.text().trim().to_string();
                let time_raw = time_entry.text().trim().to_string();
                let parser = DateParser::new();
                let due_date = if date_raw.is_empty() {
                    None
                } else {
                    parser.parse(&date_raw).as_deref().and_then(DateParser::extract_date_only)
                        .or_else(|| valid_date(&date_raw))
                };
                let due_time = if date_raw.is_empty() {
                    None
                } else if time_raw.is_empty() {
                    None
                } else {
                    valid_time(&time_raw)
                };

                let list_id = combo
                    .active_id()
                    .and_then(|id| id.parse::<i64>().ok())
                    .unwrap_or(task.list_id);

                let mut updated = task.clone();
                updated.text = text;
                updated.notes = if notes_raw.is_empty() { None } else { Some(notes_raw) };
                updated.due_date = due_date;
                updated.due_time = due_time;
                updated.list_id = list_id;
                updated.created_at = if updated.created_at.is_empty() {
                    created_at_now()
                } else {
                    updated.created_at.clone()
                };

                match ui.state.tasks.update_task(&updated) {
                    Ok(_) => {
                        ui.refresh_all();
                        ui.flash(&ui.state.i18n.t("statusTaskUpdated"));
                        window.close();
                    }
                    Err(err) => ui.flash(&err.message),
                }
            });
        }

        // Keep a reference alive while shown.
        window.show();
        std::mem::forget(TaskDetailDialog { window });
    }
}

/// List create/edit: name, icon (emoji cycling through presets), color.
pub struct ListEditDialog {
    window: gtk::Window,
}

impl ListEditDialog {
    pub fn open(ui: SharedUi, existing: Option<TodoList>) {
        let i18n = ui.state.i18n.clone();
        let creating = existing.is_none();

        let window = gtk::Window::builder()
            .title(if creating { i18n.t("dialogCreateList") } else { i18n.t("dialogEditList") })
            .modal(true)
            .transient_for(&ui.window)
            .default_width(380)
            .hide_on_close(true)
            .build();

        let content = gtk::Box::new(Orientation::Vertical, 12);
        content.set_margin_top(16);
        content.set_margin_bottom(16);
        content.set_margin_start(16);
        content.set_margin_end(16);

        let name_entry = gtk::Entry::new();
        name_entry.set_placeholder_text(Some(&i18n.t("dialogInputListName")));
        if let Some(list) = &existing {
            name_entry.set_text(&list.name);
        }

        let icon_label = gtk::Label::new(Some(&i18n.t("dialogListIcon")));
        icon_label.set_halign(gtk::Align::Start);
        let icon_combo = gtk::ComboBoxText::new();
        {
            let mut current_found = false;
            for category in EMOJI_CATEGORIES {
                for emoji in category {
                    icon_combo.append(Some(emoji), emoji);
                    if let Some(list) = &existing {
                        if list.icon.as_deref() == Some(emoji.as_str()) {
                            current_found = true;
                        }
                    }
                }
            }
            icon_combo.append(Some(""), &i18n.t("dialogClearIcon"));
            let active = if current_found {
                existing.as_ref().and_then(|l| l.icon.clone()).unwrap_or_default()
            } else {
                String::new()
            };
            let index = EMOJI_CATEGORIES
                .iter()
                .flatten()
                .chain(std::iter::once(&String::new()))
                .position(|e| *e == active)
                .unwrap_or(0);
            icon_combo.set_active(Some(index as u32));
        }

        let color_label = gtk::Label::new(Some(&i18n.t("dialogListColor")));
        color_label.set_halign(gtk::Align::Start);
        let color_combo = gtk::ComboBoxText::new();
        {
            let current = existing.as_ref().and_then(|l| l.color).unwrap_or(DEFAULT_LIST_COLOR);
            let mut index = LIST_COLORS_HEX.len();
            for (i, hex) in LIST_COLORS_HEX.iter().enumerate() {
                let name = format!("#{hex:06X}");
                color_combo.append(Some(&format!("{:08X}", 0xFF00_0000u32 | *hex)), &name);
                if crate::models::argb::from_hex(0xFF00_0000 | *hex) == current {
                    index = i;
                }
            }
            color_combo.append(Some(""), &i18n.t("dialogClearColor"));
            color_combo.set_active(Some(index as u32));
        }

        content.append(&name_entry);
        content.append(&icon_label);
        content.append(&icon_combo);
        content.append(&color_label);
        content.append(&color_combo);

        let buttons = gtk::Box::new(Orientation::Horizontal, 8);
        let spacer = gtk::Box::new(Orientation::Horizontal, 0);
        spacer.set_hexpand(true);
        let cancel_button = gtk::Button::with_label(&i18n.t("dialogCancel"));
        let save_button = gtk::Button::with_label(&i18n.t("dialogConfirm"));
        save_button.add_css_class("suggested-action");
        buttons.append(&spacer);
        buttons.append(&cancel_button);
        buttons.append(&save_button);
        content.append(&buttons);

        window.set_child(Some(&content));

        {
            let window = window.clone();
            cancel_button.connect_clicked(move |_| window.close());
        }

        {
            let window = window.clone();
            let ui = Rc::clone(&ui);
            let existing = existing.clone();
            save_button.connect_clicked(move |button| {
                let _ = button;
                let name = name_entry.text().trim().to_string();
                if name.is_empty() {
                    return; // blank name keeps the dialog open (reference behavior)
                }

                let icon = icon_combo
                    .active_id()
                    .map(|id| if id.is_empty() { None } else { Some(id.to_string()) })
                    .flatten();
                let color = color_combo
                    .active_id()
                    .and_then(|id| if id.is_empty() { None } else { u32::from_str_radix(&id, 16).ok() })
                    .map(crate::models::argb::from_hex);

                let result = match &existing {
                    None => ui
                        .state
                        .lists
                        .add_list(&name, icon.as_deref(), color)
                        .map(|id| {
                            ui.flash(&ui.state.i18n.format(
                                "statusCreateList",
                                &[&name],
                            ));
                            id
                        }),
                    Some(list) => ui.state.lists.update_list(
                        list.id,
                        &name,
                        icon.as_deref(),
                        color,
                        icon.is_none() && list.icon.is_some(),
                        color.is_none() && list.color.is_some(),
                    ),
                };

                match result {
                    Ok(_) => {
                        if let Err(err) = ui.state.db.get_all_lists() {
                            ui.flash(&err.message);
                        }
                        ui.refresh_all();
                        window.close();
                    }
                    Err(err) => ui.flash(&err.message),
                }
            });
        }

        window.show();
        std::mem::forget(ListEditDialog { window });
    }
}

fn valid_date(s: &str) -> Option<String> {
    chrono::NaiveDate::parse_from_str(s, DATE_FORMAT).ok().map(|d| d.format(DATE_FORMAT).to_string())
}

fn valid_time(s: &str) -> Option<String> {
    chrono::NaiveTime::parse_from_str(s, TIME_FORMAT).ok().map(|t| t.format(TIME_FORMAT).to_string())
}
