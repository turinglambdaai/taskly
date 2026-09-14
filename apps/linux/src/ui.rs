//! GTK4/libadwaita UI. Conservative, idiomatic gtk4-rs: header bar + paned
//! (sidebar | task pane) + status bar. Editing happens in modal dialogs
//! (dialogs.rs). DB access is synchronous on the main thread (local SQLite).

use std::rc::Rc;
use std::sync::{Arc, Mutex};

use adw::prelude::*;
use gtk::Orientation;

use crate::config::Config;
use crate::db::{created_at_now, ListRepository, SQLiteDatabase, TaskRepository};
use crate::date_parser::DateParser;
use crate::i18n::I18n;
use crate::models::{TaskItem, TaskViewType, TodoList, DEFAULT_LIST_ICON};
use crate::reminder::ReminderService;

/// Warm palette (DESIGN-TOKENS.md) applied as CSS; widgets stay native libadwaita.
const APP_CSS: &str = "
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
";

pub struct AppState {
    pub db: Arc<SQLiteDatabase>,
    pub tasks: TaskRepository,
    pub lists: ListRepository,
    pub i18n: Arc<I18n>,
    pub config: Mutex<Config>,
    pub parser: DateParser,
    pub current_view: Mutex<TaskViewType>,
    pub show_completed: std::cell::Cell<bool>,
    pub reminder: ReminderService,
}

pub struct Ui {
    pub state: Arc<AppState>,
    pub window: adw::ApplicationWindow,
    pub title_label: gtk::Label,
    pub status_label: gtk::Label,
    pub lists_box: gtk::Box,
    pub tiles: Vec<(TaskViewType, gtk::Label)>,
    pub tasks_box: gtk::Box,
    pub quick_add: gtk::Entry,
    pub search: gtk::Entry,
    pub show_completed_button: gtk::Button,
    pub input_area: gtk::Box,
}

pub type SharedUi = Rc<Ui>;
pub type SharedState = Arc<AppState>;

pub fn run() {
    let app = adw::Application::builder()
        .application_id("app.taskly.Taskly")
        .build();
    app.connect_activate(build_ui);
    app.run();
}

fn build_ui(app: &adw::Application) {
    let provider = gtk::CssProvider::new();
    provider.load_from_string(APP_CSS);
    if let Some(display) = gtk::gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    let config = Config::load();
    let i18n = Arc::new(I18n::from_language(&config.language()));
    let db = Arc::new(SQLiteDatabase::new());

    let path = config
        .last_db_path()
        .unwrap_or_else(|| crate::config::default_database_path().to_string_lossy().to_string());
    db.set_database_path(path);
    let _ = db.ensure_connected();

    let tasks = TaskRepository::new(Arc::clone(&db), Arc::clone(&i18n));
    let lists = ListRepository::new(Arc::clone(&db), Arc::clone(&i18n));
    let reminder = ReminderService::new(Arc::clone(&db), Arc::clone(&i18n));

    let state: Arc<AppState> = Arc::new(AppState {
        db: Arc::clone(&db),
        tasks,
        lists,
        i18n,
        config: Mutex::new(config),
        parser: DateParser::new(),
        current_view: Mutex::new(TaskViewType::All),
        show_completed: std::cell::Cell::new(false),
        reminder,
    });

    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("Taskly")
        .default_width(1024)
        .default_height(768)
        .build();
    window.add_css_class("taskly-root");

    // Header
    let title_label = gtk::Label::new(Some(&state.i18n.t("navAll")));
    title_label.add_css_class("title");
    title_label.add_css_class("header-title");

    let status_label = gtk::Label::new(Some(&state.i18n.t("statusDatabaseConnected")));
    status_label.set_halign(gtk::Align::Start);
    status_label.set_margin_start(12);

    let sidebar_button = gtk::ToggleButton::builder()
        .icon_name("sidebar-show-symbolic")
        .active(true)
        .build();

    let show_completed_button = gtk::Button::new();
    show_completed_button.add_css_class("flat");

    let menu_button = gtk::MenuButton::builder().icon_name("open-menu-symbolic").build();
    menu_button.set_menu_model(Some(&build_app_menu(&state)));

    let header = adw::HeaderBar::new();
    header.set_title_widget(Some(&title_label));
    header.pack_start(&sidebar_button);
    header.pack_end(&menu_button);
    header.pack_end(&show_completed_button);

    // Sidebar
    let sidebar = gtk::Box::new(Orientation::Vertical, 12);
    sidebar.add_css_class("sidebar");
    sidebar.set_margin_top(12);
    sidebar.set_margin_bottom(12);
    sidebar.set_margin_start(12);
    sidebar.set_margin_end(12);
    sidebar.set_width_request(200);

    let tiles_grid = gtk::Grid::new();
    tiles_grid.set_column_spacing(8);
    tiles_grid.set_row_spacing(8);

    let defs: [(&str, &str, &str, TaskViewType, i32, i32); 4] = [
        ("navToday", "🗓", "today", TaskViewType::Today, 0, 0),
        ("navPlanned", "📅", "planned", TaskViewType::Planned, 0, 1),
        ("navAll", "≡", "all", TaskViewType::All, 1, 0),
        ("navCompleted", "✓", "completed", TaskViewType::Completed, 1, 1),
    ];

    let mut tiles: Vec<(TaskViewType, gtk::Label)> = vec![];
    for (key, icon, css, view, row, col) in defs {
        let button = gtk::Button::new();
        button.add_css_class("smart-tile");
        button.add_css_class(css);
        button.set_hexpand(true);

        let tile_box = gtk::Box::new(Orientation::Vertical, 2);
        let count_label = gtk::Label::new(None);
        count_label.add_css_class("count");
        count_label.set_halign(gtk::Align::End);
        let title = gtk::Label::new(Some(&format!("{icon} {}", state.i18n.t(key))));
        title.add_css_class("title");
        title.set_halign(gtk::Align::Start);
        title.set_hexpand(true);
        tile_box.append(&count_label);
        tile_box.append(&title);
        button.set_child(Some(&tile_box));

        tiles_grid.attach(&button, col, row, 1, 1);
        tiles.push((view, count_label));
    }
    sidebar.append(&tiles_grid);

    let lists_label = gtk::Label::new(Some(&state.i18n.t("sectionMyLists")));
    lists_label.add_css_class("section-header");
    lists_label.set_halign(gtk::Align::Start);

    let add_list_button = gtk::Button::from_icon_name("list-add-symbolic");
    add_list_button.add_css_class("flat");
    add_list_button.set_tooltip_text(Some(&state.i18n.t("dialogCreateList")));

    let lists_header = gtk::Box::new(Orientation::Horizontal, 8);
    lists_label.set_hexpand(true);
    lists_header.append(&lists_label);
    lists_header.append(&add_list_button);
    sidebar.append(&lists_header);

    let lists_box = gtk::Box::new(Orientation::Vertical, 4);
    sidebar.append(&lists_box);

    // Task pane
    let task_pane = gtk::Box::new(Orientation::Vertical, 8);
    task_pane.set_margin_top(8);
    task_pane.set_margin_bottom(8);
    task_pane.set_margin_start(12);
    task_pane.set_margin_end(12);
    task_pane.set_hexpand(true);

    let search = gtk::Entry::new();
    search.set_placeholder_text(Some(&state.i18n.t("searchHint")));

    let quick_add = gtk::Entry::new();
    quick_add.set_placeholder_text(Some(&state.i18n.t("taskListInputHint")));
    quick_add.set_hexpand(true);

    let input_area = gtk::Box::new(Orientation::Vertical, 8);
    input_area.append(&search);
    input_area.append(&quick_add);
    task_pane.append(&input_area);

    let tasks_scroll = gtk::ScrolledWindow::new();
    tasks_scroll.set_vexpand(true);
    tasks_scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    let tasks_box = gtk::Box::new(Orientation::Vertical, 4);
    tasks_scroll.set_child(Some(&tasks_box));
    task_pane.append(&tasks_scroll);

    // Layout
    let paned = gtk::Paned::new(Orientation::Horizontal);
    paned.set_position(280);
    paned.set_start_child(Some(&sidebar));
    paned.set_end_child(Some(&task_pane));
    paned.set_vexpand(true);
    paned.set_hexpand(true);

    let statusbar = gtk::Box::new(Orientation::Horizontal, 0);
    statusbar.add_css_class("statusbar");
    statusbar.set_height_request(28);
    statusbar.append(&status_label);

    let root = gtk::Box::new(Orientation::Vertical, 0);
    root.append(&header);
    root.append(&paned);
    root.append(&statusbar);
    window.set_content(Some(&root));

    let ui: SharedUi = Rc::new(Ui {
        state: Arc::clone(&state),
        window: window.clone(),
        title_label,
        status_label,
        lists_box,
        tiles,
        tasks_box,
        quick_add,
        search,
        show_completed_button,
        input_area,
    });
    crate::ui_ref::set(Rc::clone(&ui));

    // Signals
    {
        let paned_clone = paned.clone();
        sidebar_button.connect_toggled(move |button| {
            paned_clone.set_position(if button.is_active() { 280 } else { 0 });
        });
    }
    for (view, button) in tiles_buttons_of(&ui) {
        let ui_weak = Rc::downgrade(&ui);
        button.connect_clicked(move |_| {
            if let Some(ui) = ui_weak.upgrade() {
                ui.select_view(view);
            }
        });
    }
    {
        let ui_weak = Rc::downgrade(&ui);
        add_list_button.connect_clicked(move |_| {
            if let Some(ui) = ui_weak.upgrade() {
                crate::dialogs::ListEditDialog::open(Rc::clone(&ui), None);
            }
        });
    }
    {
        let ui_weak = Rc::downgrade(&ui);
        ui.quick_add.connect_activate(move |entry| {
            if let Some(ui) = ui_weak.upgrade() {
                let text = entry.text().to_string();
                ui.quick_add(&text);
            }
        });
    }
    {
        let ui_weak = Rc::downgrade(&ui);
        ui.search.connect_changed(move |_| {
            if let Some(ui) = ui_weak.upgrade() {
                ui.refresh_all();
            }
        });
    }
    {
        let ui_weak = Rc::downgrade(&ui);
        ui.show_completed_button.connect_clicked(move |_| {
            if let Some(ui) = ui_weak.upgrade() {
                let next = !ui.state.show_completed.get();
                ui.state.show_completed.set(next);
                ui.refresh_all();
            }
        });
    }

    // Reminders: startup check + 60 s poll on a background thread.
    {
        let state_bg = Arc::clone(&state);
        std::thread::spawn(move || {
            state_bg.reminder.check_now();
            loop {
                std::thread::sleep(std::time::Duration::from_secs(60));
                state_bg.reminder.check_now();
            }
        });
    }

    ui.refresh_all();
    window.present();
}

/// The grid buttons are stored indirectly (tile labels carry the counts);
/// this collects the buttons by walking the grid for signal wiring.
fn tiles_buttons_of(ui: &Ui) -> Vec<(TaskViewType, gtk::Button)> {
    let mut result = vec![];
    for (view, label) in &ui.tiles {
        if let Some(parent) = label.parent() {
            if let Some(tile_box) = parent.downcast_ref::<gtk::Box>() {
                if let Some(grandparent) = tile_box.parent() {
                    if let Some(button) = grandparent.downcast_ref::<gtk::Button>() {
                        result.push((*view, button.clone()));
                    }
                }
            }
        }
    }
    result
}

fn build_app_menu(state: &SharedState) -> gtk::gio::Menu {
    let menu = gtk::gio::Menu::new();
    let lang_section = gtk::gio::Menu::new();
    lang_section.append(Some("简体中文"), Some("win.lang-zh"));
    lang_section.append(Some("English"), Some("win.lang-en"));
    menu.append_section(Some(&state.i18n.t("menuLanguage")), &lang_section);
    menu.append(Some(&state.i18n.t("menuInstallCli")), Some("win.install-cli"));
    menu.append(Some(&state.i18n.t("menuUninstallCli")), Some("win.uninstall-cli"));
    menu
}

impl Ui {
    fn i18n(&self) -> &I18n {
        &self.state.i18n
    }

    pub fn select_view(&self, view: TaskViewType) {
        *self.state.current_view.lock().expect("view lock") = view;
        if let TaskViewType::List(id) = view {
            if let Ok(mut config) = self.state.config.lock() {
                config.set("last-selected-list-id", id.to_string());
                config.save();
            }
        }
        self.refresh_all();
    }

    pub fn refresh_all(&self) {
        let i18n = self.i18n();
        let search = self.search.text().to_string();

        let view = *self.state.current_view.lock().expect("view lock");

        // Title
        let title = if !search.is_empty() {
            format!("{}: {search}", i18n.t("searchHint"))
        } else {
            match view {
                TaskViewType::Today => i18n.t("navToday"),
                TaskViewType::Planned => i18n.t("navPlanned"),
                TaskViewType::All => i18n.t("navAll"),
                TaskViewType::Completed => i18n.t("navCompleted"),
                TaskViewType::List(id) => self
                    .state
                    .db
                    .get_list_by_id(id)
                    .ok()
                    .flatten()
                    .map(|l| l.name)
                    .unwrap_or_else(|| format!("List {id}")),
            }
        };
        self.title_label.set_text(&title);

        // Show/hide completed toggle
        let toggle_text = if self.state.show_completed.get() {
            i18n.t("hideCompletedToggle")
        } else {
            i18n.t("showCompletedToggle")
        };
        self.show_completed_button.set_label(&toggle_text);

        // Counts
        let today = self.state.db.get_today_task_count().unwrap_or(0);
        let planned = self.state.db.get_planned_task_count().unwrap_or(0);
        let all = self.state.db.get_incomplete_task_count().unwrap_or(0);
        let completed = self.state.db.get_completed_task_count().unwrap_or(0);
        for (v, label) in &self.tiles {
            let count = match v {
                TaskViewType::Today => today,
                TaskViewType::Planned => planned,
                TaskViewType::All => all,
                TaskViewType::Completed => completed,
                TaskViewType::List(_) => 0,
            };
            label.set_text(if count > 0 { count.to_string().as_str() } else { "" });
        }

        self.rebuild_lists();
        self.rebuild_tasks(&search);

        // Status
        let status = if !search.is_empty() {
            format!("{}: {search}", i18n.t("searchHint"))
        } else {
            match view {
                TaskViewType::Today => i18n.t("statusShowToday"),
                TaskViewType::Planned => i18n.t("statusShowPlanned"),
                TaskViewType::All => i18n.t("statusShowAll"),
                TaskViewType::Completed => i18n.t("statusShowCompleted"),
                TaskViewType::List(id) => {
                    let name = self
                        .state
                        .db
                        .get_list_by_id(id)
                        .ok()
                        .flatten()
                        .map(|l| l.name)
                        .unwrap_or_else(|| format!("List {id}"));
                    i18n.format("statusSwitchList", &[&name])
                }
            }
        };
        self.status_label.set_text(&status);
    }

    pub fn flash(&self, message: &str) {
        self.status_label.set_text(message);
        glib::timeout_add_seconds_local(3, {
            let ui = Rc::downgrade(self);
            move || {
                if let Some(ui) = ui.upgrade() {
                    ui.refresh_all();
                }
                glib::ControlFlow::Remove
            }
        });
    }

    fn rebuild_lists(&self) {
        // Remove existing rows.
        while let Some(child) = self.lists_box.first_child() {
            self.lists_box.remove(&child);
        }

        let mut lists = self.state.db.get_all_lists().unwrap_or_default();
        for list in lists.iter_mut() {
            list.pending_count = self.state.db.get_task_count_by_list(list.id).unwrap_or(0);
        }

        for list in lists {
            let row = gtk::Box::new(Orientation::Horizontal, 8);
            row.set_margin_top(4);
            row.set_margin_bottom(4);

            let icon_label = gtk::Label::new(Some(list.icon.as_deref().unwrap_or(DEFAULT_LIST_ICON)));
            let name_label = gtk::Label::new(Some(&list.name));
            name_label.set_halign(gtk::Align::Start);
            name_label.set_hexpand(true);
            name_label.set_ellipsize(gtk::pango::EllipsizeMode::End);
            let pending_label = gtk::Label::new(Some(if list.pending_count > 0 {
                list.pending_count.to_string().as_str()
            } else {
                ""
            }));
            pending_label.add_css_class("dim-label");

            let edit_button = gtk::Button::from_icon_name("document-edit-symbolic");
            edit_button.add_css_class("flat");
            edit_button.set_tooltip_text(Some(&self.i18n().t("dialogEditList")));

            row.append(&icon_label);
            row.append(&name_label);
            row.append(&pending_label);
            row.append(&edit_button);

            let button_row = gtk::Button::new();
            button_row.add_css_class("flat");
            button_row.set_child(Some(&row));

            let list_id = list.id;
            let ui_weak = Rc::downgrade(self);
            button_row.connect_clicked(move |_| {
                if let Some(ui) = ui_weak.upgrade() {
                    ui.select_view(TaskViewType::List(list_id));
                }
            });
            {
                let ui_weak = Rc::downgrade(self);
                edit_button.connect_clicked(move |_| {
                    if let Some(ui) = ui_weak.upgrade() {
                        if let Ok(Some(list)) = ui.state.db.get_list_by_id(list_id) {
                            crate::dialogs::ListEditDialog::open(Rc::clone(&ui), Some(list));
                        }
                    }
                });
            }

            self.lists_box.append(&button_row);
        }
    }

    fn rebuild_tasks(&self, search: &str) {
        while let Some(child) = self.tasks_box.first_child() {
            self.tasks_box.remove(&child);
        }

        let tasks = if !search.is_empty() {
            self.state.tasks.search_tasks(search).unwrap_or_default()
        } else {
            self.state
                .tasks
                .get_tasks_by_view(
                    *self.state.current_view.lock().expect("view lock"),
                    1000,
                    0,
                    self.state.show_completed.get(),
                )
                .unwrap_or_default()
        };

        if tasks.is_empty() {
            let empty = gtk::Label::new(Some(&self.i18n().t("taskListEmpty")));
            empty.set_vexpand(true);
            empty.add_css_class("dim-label");
            self.tasks_box.append(&empty);
            return;
        }

        for task in tasks {
            let row = self.build_task_row(&task);
            self.tasks_box.append(&row);
        }
    }

    fn build_task_row(&self, task: &TaskItem) -> gtk::Box {
        let row = gtk::Box::new(Orientation::Horizontal, 12);
        row.add_css_class("task-row");
        if task.completed {
            row.add_css_class("completed");
        }

        let checkbox = gtk::CheckButton::new();
        checkbox.set_active(task.completed);

        let text_box = gtk::Box::new(Orientation::Vertical, 2);
        text_box.set_hexpand(true);

        let text_label = gtk::Label::new(Some(&task.text));
        text_label.add_css_class("task-text");
        text_label.set_halign(gtk::Align::Start);
        text_label.set_wrap(true);
        text_label.set_xalign(0.0);
        text_box.append(&text_label);

        let due_display = crate::db::format_due_display(&self.state.parser, task, &self.state.i18n);
        if !due_display.is_empty() {
            let meta = gtk::Label::new(Some(&format!("🗓 {due_display}")));
            meta.add_css_class("task-meta");
            meta.set_halign(gtk::Align::Start);
            meta.set_xalign(0.0);
            text_box.append(&meta);
        }
        if let Some(notes) = &task.notes {
            if !notes.is_empty() {
                let notes_label = gtk::Label::new(Some(notes));
                notes_label.add_css_class("task-meta");
                notes_label.set_halign(gtk::Align::Start);
                notes_label.set_xalign(0.0);
                notes_label.set_ellipsize(gtk::pango::EllipsizeMode::End);
                text_box.append(&notes_label);
            }
        }

        let detail_button = gtk::Button::from_icon_name("dialog-information-symbolic");
        detail_button.add_css_class("flat");
        detail_button.set_tooltip_text(Some(&self.i18n().t("tooltipTaskEdit")));

        row.append(&checkbox);
        row.append(&text_box);
        row.append(&detail_button);

        {
            let ui_weak = Rc::downgrade(self);
            let task_id = task.id;
            checkbox.connect_toggled(move |check| {
                if let Some(ui) = ui_weak.upgrade() {
                    let _ = ui.state.db.set_task_completed(task_id, check.is_active());
                    ui.refresh_all();
                }
            });
        }
        {
            let ui_weak = Rc::downgrade(self);
            let task_id = task.id;
            detail_button.connect_clicked(move |_| {
                if let Some(ui) = ui_weak.upgrade() {
                    if let Ok(Some(task)) = ui.state.db.get_task_by_id(task_id) {
                        crate::dialogs::TaskDetailDialog::open(Rc::clone(&ui), task);
                    }
                }
            });
        }

        row
    }

    pub fn quick_add(&self, raw: &str) {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return;
        }

        let (text, time_command) = self.state.parser.extract_time_command(trimmed);
        let mut due_date: Option<String> = None;
        let mut due_time: Option<String> = None;
        if let Some(command) = time_command {
            if let Some(parsed) = self.state.parser.parse(&command) {
                let is_date_only = !command.starts_with('@')
                    && matches!(command.chars().last(), Some('d') | Some('w') | Some('M'));
                due_date = DateParser::extract_date_only(Some(&parsed));
                if !is_date_only {
                    due_time = DateParser::extract_time_only(Some(&parsed));
                }
            }
        }

        let list_id = match *self.state.current_view.lock().expect("view lock") {
            TaskViewType::List(id) => id,
            _ => match self.state.lists.get_default_list().ok().flatten() {
                Some(list) => list.id,
                None => {
                    self.flash(&self.i18n().t("taskCreateListFirst"));
                    return;
                }
            },
        };

        let task = TaskItem {
            id: 0,
            list_id,
            text: if text.is_empty() { trimmed.to_string() } else { text },
            created_at: created_at_now(),
            due_date,
            due_time,
            completed: false,
            notes: None,
            list_name: None,
        };
        match self.state.tasks.add_task(&task) {
            Ok(_) => {
                self.quick_add.set_text("");
                self.refresh_all();
                self.flash(&self.i18n().t("statusTaskAdded"));
            }
            Err(err) => self.flash(&err.message),
        }
    }
}
