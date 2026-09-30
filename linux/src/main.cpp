// Taskly Linux host — GTK4 window over one embedded Racket CS backend.
// Mirrors the WinUI/SwiftUI hosts: boot the runtime off the UI thread, drive
// the product through the generated typed client (rivet_app::API), and
// dispatch every completion/event back to the main loop before touching
// widgets.
#include <gtk/gtk.h>

#include <atomic>
#include <cstdint>
#include <ctime>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "GeneratedBackend.hpp"

namespace {

// ---- i18n (values byte-identical to shared/i18n/{zh,en}.json) ----

struct Strings {
  const char* nav_today;
  const char* nav_planned;
  const char* nav_all;
  const char* nav_completed;
  const char* section_my_lists;
  const char* quick_add_hint;
  const char* task_empty;
  const char* show_completed;
  const char* hide_completed;
  const char* subtitle_open;      // {0} open
  const char* subtitle_completed; // {0} completed
  const char* status_today;
  const char* status_planned;
  const char* status_all;
  const char* status_completed_view;
  const char* delete_confirm_title;
  const char* delete_confirm_body;
  const char* task_deleted;
  const char* task_added;
  const char* task_delete;
  const char* dialog_cancel;
};

constexpr Strings kZh{
    "今天", "计划", "全部", "完成",
    "我的列表",
    "+ 添加任务",
    "暂无任务",
    "显示已完成", "隐藏已完成",
    "{0} 个未完成", "{0} 个已完成",
    "今天的任务", "计划中的任务", "全部任务", "已完成的任务",
    "确认删除", "确定要删除这个任务吗？此操作无法撤销。",
    "任务已删除", "任务已添加",
    "删除", "取消",
};

constexpr Strings kEn{
    "Today", "Planned", "All", "Completed",
    "My Lists",
    "+ Add Task",
    "No tasks",
    "Show Completed", "Hide Completed",
    "{0} open", "{0} completed",
    "Today's tasks", "Planned tasks", "All tasks", "Completed tasks",
    "Confirm Delete", "Are you sure you want to delete this task? This action cannot be undone.",
    "Task deleted", "Task added",
    "Delete", "Cancel",
};

Strings const& strings_for(std::string const& language) {
  return language.rfind("zh", 0) == 0 ? kZh : kEn;
}

std::string format_count(std::string const& pattern, std::int64_t n) {
  auto const pos = pattern.find("{0}");
  if (pos == std::string::npos) return pattern;
  return pattern.substr(0, pos) + std::to_string(n) + pattern.substr(pos + 3);
}

// ---- view model ----

enum class ViewKind { Today, Planned, All, Completed, List };

struct ViewKey {
  ViewKind kind{ViewKind::Today};
  std::int64_t list_id{0};

  bool operator==(ViewKey const&) const = default;
};

struct AppState {
  GtkWindow* window{nullptr};
  GtkLabel* subtitle{nullptr};
  GtkToggleButton* show_completed_toggle{nullptr};
  GtkListBox* sidebar{nullptr};
  GtkListBox* task_list{nullptr};
  GtkStack* main_stack{nullptr};
  GtkLabel* empty_label{nullptr};
  GtkEntry* quick_add{nullptr};

  std::unique_ptr<rivet::linux_runtime::Backend> backend;
  std::unique_ptr<rivet_app::API> api;
  std::mutex startup_mutex;
  std::thread startup_thread;
  std::unique_ptr<rivet::linux_runtime::Backend> startup_backend;
  std::string startup_error;
  std::atomic<bool> shutting_down{false};

  Strings const* i18n{&kEn};
  std::string language{"en"};
  ViewKey view{};
  bool show_completed{false};
  rivet_app::Snapshot snapshot;
  bool rebuilding_sidebar{false};
  bool loaded{false};

  void set_subtitle(std::string const& text) {
    gtk_label_set_text(subtitle, text.c_str());
  }

  void set_status_error(std::string const& error) {
    set_subtitle("⚠ " + error);
  }
};

AppState g_state;

// ---- UI dispatch (completions/events arrive on the backend reader thread) ----

struct UiTask {
  std::function<void()> run;
};

int run_ui_task(gpointer user_data) {
  auto* task = static_cast<UiTask*>(user_data);
  task->run();
  delete task;
  return G_SOURCE_REMOVE;
}

void dispatch_ui(std::function<void()> run) {
  g_idle_add(run_ui_task, new UiTask{std::move(run)});
}

template <typename T, typename Then>
void on_result(rivet_app::Result<T> result, Then then) {
  dispatch_ui([result = std::move(result), then = std::move(then)]() mutable {
    if (!result.succeeded()) {
      try {
        std::rethrow_exception(result.error);
      } catch (std::exception const& e) {
        g_state.set_status_error(e.what());
      }
      return;
    }
    try {
      then(result.get());
    } catch (std::exception const& e) {
      g_state.set_status_error(e.what());
    }
  });
}

// ---- rendering ----

void reload_snapshot();

std::string due_label(rivet_app::Task const& task) {
  std::string text;
  if (task.due_date.has_value()) text += *task.due_date;
  if (task.due_time.has_value()) {
    if (!text.empty()) text += ' ';
    text += *task.due_time;
  }
  return text;
}

void on_task_check_toggled(GtkCheckButton* button, gpointer) {
  if (g_state.api == nullptr) return;
  auto const id = static_cast<std::int64_t>(
      GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "task-id")));
  auto const active = gtk_check_button_get_active(button);
  g_state.api->set_completed_async(
      id, active, [](rivet_app::Result<rivet_app::Task> result) {
        on_result(std::move(result),
                  [](rivet_app::Task const&) { reload_snapshot(); });
      });
}

void on_task_delete_clicked(GtkButton* button, gpointer) {
  if (g_state.api == nullptr) return;
  auto const id = static_cast<std::int64_t>(
      GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "task-id")));
  auto* dialog =
      gtk_alert_dialog_new("%s", g_state.i18n->delete_confirm_title);
  gtk_alert_dialog_set_detail(dialog, g_state.i18n->delete_confirm_body);
  g_object_set_data(G_OBJECT(dialog), "task-id",
                    GINT_TO_POINTER(static_cast<gint>(id)));
  const char* buttons[] = {g_state.i18n->dialog_cancel,
                           g_state.i18n->task_delete, nullptr};
  gtk_alert_dialog_set_buttons(dialog, buttons);
  gtk_alert_dialog_set_cancel_button(dialog, 0);
  gtk_alert_dialog_choose(
      dialog, GTK_WINDOW(g_state.window), nullptr,
      +[](GObject* source, GAsyncResult* result, gpointer) {
        auto* alert = GTK_ALERT_DIALOG(source);
        auto const choice =
            gtk_alert_dialog_choose_finish(alert, result, nullptr);
        auto const id = static_cast<std::int64_t>(GPOINTER_TO_INT(
            g_object_get_data(G_OBJECT(alert), "task-id")));
        if (choice == 1 && g_state.api != nullptr) {
          g_state.api->delete_task_async(
              id, [](rivet_app::Result<bool> delete_result) {
                on_result(std::move(delete_result),
                          [](bool const&) { reload_snapshot(); });
              });
        }
        g_object_unref(alert);
      },
      nullptr);
}

GtkWidget* make_task_row(rivet_app::Task const& task) {
  auto* row = gtk_list_box_row_new();
  auto* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
  gtk_widget_set_margin_top(box, 6);
  gtk_widget_set_margin_bottom(box, 6);
  gtk_widget_set_margin_start(box, 10);
  gtk_widget_set_margin_end(box, 10);

  auto* check = gtk_check_button_new();
  gtk_check_button_set_active(GTK_CHECK_BUTTON(check), task.completed);
  gtk_widget_set_valign(check, GTK_ALIGN_CENTER);
  g_object_set_data(G_OBJECT(check), "task-id",
                    GINT_TO_POINTER(static_cast<gint>(task.id)));
  g_signal_connect(check, "toggled",
                   G_CALLBACK(on_task_check_toggled), nullptr);
  gtk_box_append(GTK_BOX(box), check);

  auto* text = gtk_label_new(task.text.c_str());
  gtk_label_set_ellipsize(GTK_LABEL(text), PANGO_ELLIPSIZE_END);
  gtk_label_set_xalign(GTK_LABEL(text), 0.0f);
  gtk_widget_set_hexpand(text, TRUE);
  if (task.completed) {
    gtk_widget_add_css_class(text, "task-done");
  }
  gtk_box_append(GTK_BOX(box), text);

  auto const due = due_label(task);
  if (!due.empty()) {
    auto* due_label_widget = gtk_label_new(due.c_str());
    gtk_widget_add_css_class(due_label_widget, "dim-label");
    gtk_widget_add_css_class(due_label_widget, "caption");
    gtk_widget_set_valign(due_label_widget, GTK_ALIGN_CENTER);
    gtk_box_append(GTK_BOX(box), due_label_widget);
  }

  auto* delete_button = gtk_button_new_from_icon_name("user-trash-symbolic");
  gtk_widget_add_css_class(delete_button, "flat");
  gtk_widget_add_css_class(delete_button, "circular");
  gtk_widget_set_valign(delete_button, GTK_ALIGN_CENTER);
  gtk_widget_set_tooltip_text(delete_button, g_state.i18n->task_delete);
  g_object_set_data(G_OBJECT(delete_button), "task-id",
                    GINT_TO_POINTER(static_cast<gint>(task.id)));
  g_signal_connect(delete_button, "clicked",
                   G_CALLBACK(on_task_delete_clicked), nullptr);
  gtk_box_append(GTK_BOX(box), delete_button);

  gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
  return row;
}

GtkWidget* make_sidebar_row(std::string const& label,
                            std::optional<std::string> const& icon,
                            std::optional<std::int64_t> const& count) {
  auto* row = gtk_list_box_row_new();
  auto* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_widget_set_margin_top(box, 4);
  gtk_widget_set_margin_bottom(box, 4);
  gtk_widget_set_margin_start(box, 8);
  gtk_widget_set_margin_end(box, 8);

  auto* text = gtk_label_new((icon.value_or("") + " " + label).c_str());
  gtk_label_set_xalign(GTK_LABEL(text), 0.0f);
  gtk_widget_set_hexpand(text, TRUE);
  gtk_box_append(GTK_BOX(box), text);

  if (count.has_value() && *count > 0) {
    auto* badge = gtk_label_new(std::to_string(*count).c_str());
    gtk_widget_add_css_class(badge, "dim-label");
    gtk_widget_add_css_class(badge, "caption");
    gtk_box_append(GTK_BOX(box), badge);
  }

  gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
  return row;
}

struct SidebarEntry {
  ViewKey key;
  std::string label;
  std::optional<std::string> icon;
  std::optional<std::int64_t> count;
  bool header{false};
};

std::vector<SidebarEntry> sidebar_entries() {
  Strings const& s = *g_state.i18n;
  auto const& counts = g_state.snapshot.counts;
  std::vector<SidebarEntry> entries{
      {ViewKey{ViewKind::Today, 0}, s.nav_today, "📅", counts.today, false},
      {ViewKey{ViewKind::Planned, 0}, s.nav_planned, "🗓", counts.planned, false},
      {ViewKey{ViewKind::All, 0}, s.nav_all, "🗂", counts.all, false},
      {ViewKey{ViewKind::Completed, 0}, s.nav_completed, "✅", counts.completed, false},
  };
  bool first_list = true;
  for (auto const& list : g_state.snapshot.lists) {
    if (first_list) {
      entries.push_back({ViewKey{}, s.section_my_lists, std::nullopt,
                         std::nullopt, true});
      first_list = false;
    }
    entries.push_back({ViewKey{ViewKind::List, list.id}, list.name, list.icon,
                       list.pending_count, false});
  }
  return entries;
}

void reload_sidebar() {
  g_state.rebuilding_sidebar = true;
  gtk_list_box_remove_all(g_state.sidebar);

  auto position = 0;
  auto selected_row = static_cast<GtkListBoxRow*>(nullptr);
  for (auto const& entry : sidebar_entries()) {
    auto* row = entry.header
                    ? make_sidebar_row(entry.label, std::nullopt, std::nullopt)
                    : make_sidebar_row(entry.label, entry.icon, entry.count);
    if (entry.header) {
      gtk_widget_add_css_class(GTK_WIDGET(row), "sidebar-header");
      gtk_list_box_row_set_selectable(GTK_LIST_BOX_ROW(row), FALSE);
    } else {
      auto* const key = new ViewKey(entry.key);
      g_object_set_data_full(G_OBJECT(row), "view-key", key,
                             +[](gpointer data) { delete static_cast<ViewKey*>(data); });
      if (entry.key == g_state.view) {
        selected_row = GTK_LIST_BOX_ROW(row);
      }
    }
    gtk_list_box_insert(g_state.sidebar, GTK_WIDGET(row), position++);
  }
  if (selected_row != nullptr) {
    gtk_list_box_select_row(g_state.sidebar, selected_row);
  }
  g_state.rebuilding_sidebar = false;
}

void reload_task_list() {
  gtk_list_box_remove_all(g_state.task_list);

  auto const& tasks = g_state.snapshot.tasks;
  gtk_stack_set_visible_child_name(
      g_state.main_stack, tasks.empty() ? "empty" : "tasks");
  if (tasks.empty()) {
    gtk_label_set_text(g_state.empty_label, g_state.i18n->task_empty);
    return;
  }
  auto position = 0;
  for (auto const& task : tasks) {
    gtk_list_box_insert(g_state.task_list, make_task_row(task), position++);
  }
}

void refresh_subtitle() {
  Strings const& s = *g_state.i18n;
  std::string subtitle;
  std::int64_t pending = 0;
  for (auto const& task : g_state.snapshot.tasks) {
    if (!task.completed) ++pending;
  }
  auto const completed_total = g_state.snapshot.counts.completed;
  switch (g_state.view.kind) {
    case ViewKind::Today:
      subtitle = s.status_today;
      break;
    case ViewKind::Planned:
      subtitle = s.status_planned;
      break;
    case ViewKind::All:
      subtitle = s.status_all;
      break;
    case ViewKind::Completed:
      subtitle = s.status_completed_view;
      break;
    case ViewKind::List:
      for (auto const& list : g_state.snapshot.lists) {
        if (list.id == g_state.view.list_id) {
          subtitle = list.name;
          break;
        }
      }
      break;
  }
  auto const extra = g_state.view.kind == ViewKind::Completed
                         ? format_count(s.subtitle_completed, completed_total)
                         : format_count(s.subtitle_open, pending);
  if (!subtitle.empty()) subtitle += " · ";
  g_state.set_subtitle(subtitle + extra);
}

void reload_snapshot() {
  if (g_state.api == nullptr) return;
  std::optional<std::int64_t> list_id;
  std::string view;
  switch (g_state.view.kind) {
    case ViewKind::Today: view = "today"; break;
    case ViewKind::Planned: view = "planned"; break;
    case ViewKind::All: view = "all"; break;
    case ViewKind::Completed: view = "completed"; break;
    case ViewKind::List:
      view = "list";
      list_id = g_state.view.list_id;
      break;
  }
  g_state.api->load_snapshot_async(
      view, list_id, g_state.show_completed,
      [](rivet_app::Result<rivet_app::Snapshot> result) {
        on_result(std::move(result), [](rivet_app::Snapshot const& snapshot) {
          g_state.snapshot = snapshot;
          reload_sidebar();
          reload_task_list();
          refresh_subtitle();
          g_state.loaded = true;
        });
      });
}

// ---- actions ----

void on_quick_add_activate(GtkEntry* entry, gpointer) {
  if (g_state.api == nullptr) return;
  auto const text = gtk_editable_get_text(GTK_EDITABLE(entry));
  std::string const trimmed(text);
  if (trimmed.empty()) return;

  std::optional<std::int64_t> list_id;
  if (g_state.view.kind == ViewKind::List) list_id = g_state.view.list_id;
  gtk_editable_set_text(GTK_EDITABLE(entry), "");
  g_state.api->add_task_async(
      trimmed, list_id, std::nullopt, std::nullopt, std::nullopt,
      [](rivet_app::Result<rivet_app::Task> result) {
        on_result(std::move(result),
                  [](rivet_app::Task const&) { g_state.set_subtitle(g_state.i18n->task_added); reload_snapshot(); });
      });
}

void on_sidebar_row_selected(GtkListBox*, GtkListBoxRow* row, gpointer) {
  if (g_state.rebuilding_sidebar || row == nullptr || g_state.api == nullptr) {
    return;
  }
  auto* key = static_cast<ViewKey*>(g_object_get_data(G_OBJECT(row), "view-key"));
  if (key == nullptr) return;
  g_state.view = *key;
  reload_snapshot();
}

void on_show_completed_toggled(GtkToggleButton* toggle, gpointer) {
  g_state.show_completed = gtk_toggle_button_get_active(toggle);
  reload_snapshot();
}

void subscribe_to_events() {
  g_state.backend->set_event_handler(
      [](std::string const& name, rivet::Value const&) {
        if (name != "changed") return;
        dispatch_ui([] { reload_snapshot(); });
      });
}

// ---- startup (same contract as the Rivet template) ----

std::filesystem::path executable_path() {
  return std::filesystem::read_symlink("/proc/self/exe");
}

// Rivet keeps runtime/res beside the executable in development and packages.
struct RuntimeLayout {
  std::filesystem::path petite_boot;
  std::filesystem::path scheme_boot;
  std::filesystem::path racket_boot;
  std::filesystem::path core;
};

std::optional<RuntimeLayout> discover_runtime_layout() {
  std::filesystem::path const exe = executable_path();
  std::filesystem::path const roots[] = {exe.parent_path()};
  for (auto const& root : roots) {
    RuntimeLayout layout{
        root / "runtime" / "petite.boot",
        root / "runtime" / "scheme.boot",
        root / "runtime" / "racket.boot",
        root / "res" / "core.zo",
    };
    if (std::filesystem::exists(layout.petite_boot) &&
        std::filesystem::exists(layout.scheme_boot) &&
        std::filesystem::exists(layout.racket_boot) &&
        std::filesystem::exists(layout.core)) {
      return layout;
    }
  }
  return std::nullopt;
}

void apply_settings(rivet_app::Settings const& settings) {
  g_state.language = settings.language;
  g_state.i18n = &strings_for(settings.language);
  gtk_entry_set_placeholder_text(g_state.quick_add,
                                 g_state.i18n->quick_add_hint);
  gtk_button_set_label(GTK_BUTTON(g_state.show_completed_toggle),
                       g_state.show_completed ? g_state.i18n->hide_completed
                                              : g_state.i18n->show_completed);
}

int on_backend_finished(gpointer) {
  if (g_state.startup_thread.joinable()) {
    g_state.startup_thread.join();
  }

  std::unique_ptr<rivet::linux_runtime::Backend> backend;
  std::string error;
  {
    std::lock_guard lock(g_state.startup_mutex);
    backend = std::move(g_state.startup_backend);
    error = std::move(g_state.startup_error);
  }

  if (g_state.shutting_down.load(std::memory_order_acquire)) {
    if (backend != nullptr) {
      backend->stop();
    }
    return G_SOURCE_REMOVE;
  }

  if (!error.empty()) {
    g_state.set_status_error("Backend error: " + error);
    return G_SOURCE_REMOVE;
  }
  if (backend == nullptr) {
    g_state.set_status_error("Backend error: startup completed without a backend");
    return G_SOURCE_REMOVE;
  }

  g_state.backend = std::move(backend);
  g_state.api = std::make_unique<rivet_app::API>(*g_state.backend);
  subscribe_to_events();

  g_state.api->get_settings_async(
      [](rivet_app::Result<rivet_app::Settings> result) {
        on_result(
            std::move(result), [](rivet_app::Settings const& settings) {
              apply_settings(settings);
              g_state.api->default_database_async(
                  [](rivet_app::Result<std::string> db_result) {
                    on_result(std::move(db_result),
                              [](std::string const& path) {
                                g_state.api->open_database_async(
                                    path,
                                    [](rivet_app::Result<
                                        rivet_app::Snapshot>
                                        open_result) {
                                      on_result(
                                          std::move(open_result),
                                          [](rivet_app::Snapshot const&) {
                                            reload_snapshot();
                                          });
                                    });
                              });
                  });
            });
      });
  return G_SOURCE_REMOVE;
}

void start_backend() {
  auto layout = discover_runtime_layout();
  if (!layout.has_value()) {
    g_state.set_status_error(
        "Missing Rivet runtime layout (runtime/*.boot, res/core.zo) next to "
        "the executable. Build with raco rivet build/dev.");
    return;
  }

  rivet::linux_runtime::RacketRuntimeConfig config;
  config.executable_path = executable_path().string();
  config.petite_boot = layout->petite_boot.string();
  config.scheme_boot = layout->scheme_boot.string();
  config.racket_boot = layout->racket_boot.string();
  config.backend_bundle = layout->core.string();
  config.module_name = rivet_app::kModuleName;
  config.entry_symbol = rivet_app::kEntryName;

  // Booting the embedded runtime blocks on file I/O; only startup runs off
  // the main loop. Everything after completion dispatches back through
  // g_idle_add.
  g_state.startup_thread = std::thread([config = std::move(config)]() mutable {
    auto backend =
        std::make_unique<rivet::linux_runtime::Backend>(std::move(config));
    try {
      backend->start();
      {
        std::lock_guard lock(g_state.startup_mutex);
        g_state.startup_backend = std::move(backend);
      }
    } catch (std::exception const& e) {
      std::lock_guard lock(g_state.startup_mutex);
      g_state.startup_error = e.what();
    }
    g_idle_add(on_backend_finished, nullptr);
  });
}

// ---- window ----

void apply_css() {
  auto* provider = gtk_css_provider_new();
  gtk_css_provider_load_from_string(provider, R"CSS(
    .sidebar list row.sidebar-header {
      background: none;
      font-weight: 700;
      opacity: 0.6;
    }
    .task-done {
      text-decoration: line-through;
      opacity: 0.55;
    }
    checkbutton:checked {
      color: #c15f3c;
    }
  )CSS");
  gtk_style_context_add_provider_for_display(
      gtk_widget_get_display(GTK_WIDGET(g_state.window)),
      GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(provider);
}

void on_activate(GtkApplication* app, gpointer) {
  if (g_state.window != nullptr) {
    gtk_window_present(g_state.window);
    return;
  }

  auto* window = gtk_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(window), "Taskly");
  gtk_window_set_default_size(GTK_WINDOW(window), 960, 640);

  auto* header = gtk_header_bar_new();
  auto* subtitle = gtk_label_new("…");
  gtk_widget_add_css_class(subtitle, "dim-label");
  gtk_header_bar_set_title_widget(GTK_HEADER_BAR(header), subtitle);

  auto* show_completed = gtk_toggle_button_new_with_label("Show Completed");
  gtk_widget_add_css_class(show_completed, "flat");
  gtk_header_bar_pack_end(GTK_HEADER_BAR(header), show_completed);
  gtk_window_set_titlebar(GTK_WINDOW(window), header);

  auto* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

  auto* paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_widget_set_vexpand(paned, TRUE);

  auto* sidebar_scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sidebar_scroll),
                                 GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_widget_set_size_request(sidebar_scroll, 210, -1);
  auto* sidebar = gtk_list_box_new();
  gtk_widget_add_css_class(GTK_WIDGET(sidebar), "navigation-sidebar");
  gtk_widget_add_css_class(GTK_WIDGET(sidebar), "sidebar");
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(sidebar_scroll), sidebar);
  gtk_paned_set_start_child(GTK_PANED(paned), sidebar_scroll);

  auto* main_stack = gtk_stack_new();
  auto* main_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

  auto* task_scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(task_scroll),
                                 GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  auto* task_list = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(task_list), GTK_SELECTION_NONE);
  gtk_widget_add_css_class(GTK_WIDGET(task_list), "boxed-list");
  gtk_widget_set_valign(GTK_WIDGET(task_list), GTK_ALIGN_START);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(task_scroll), task_list);

  auto* empty_label = gtk_label_new("No tasks");
  gtk_widget_add_css_class(empty_label, "dim-label");
  gtk_widget_set_valign(empty_label, GTK_ALIGN_CENTER);
  gtk_widget_set_vexpand(empty_label, TRUE);

  gtk_stack_add_named(GTK_STACK(main_stack), GTK_WIDGET(task_scroll), "tasks");
  gtk_stack_add_named(GTK_STACK(main_stack), empty_label, "empty");
  gtk_stack_set_visible_child_name(GTK_STACK(main_stack), "empty");

  auto* quick_add = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(quick_add), "+ Add Task");
  gtk_widget_set_margin_top(quick_add, 8);
  gtk_widget_set_margin_bottom(quick_add, 8);
  gtk_widget_set_margin_start(quick_add, 12);
  gtk_widget_set_margin_end(quick_add, 12);
  gtk_box_append(GTK_BOX(main_box), GTK_WIDGET(main_stack));
  gtk_box_append(GTK_BOX(main_box), quick_add);
  gtk_widget_set_vexpand(GTK_WIDGET(main_stack), TRUE);
  gtk_paned_set_end_child(GTK_PANED(paned), main_box);

  gtk_box_append(GTK_BOX(root), paned);
  gtk_window_set_child(GTK_WINDOW(window), root);

  g_state.window = GTK_WINDOW(window);
  g_state.subtitle = GTK_LABEL(subtitle);
  g_state.show_completed_toggle = GTK_TOGGLE_BUTTON(show_completed);
  g_state.sidebar = GTK_LIST_BOX(sidebar);
  g_state.task_list = GTK_LIST_BOX(task_list);
  g_state.main_stack = GTK_STACK(main_stack);
  g_state.empty_label = GTK_LABEL(empty_label);
  g_state.quick_add = GTK_ENTRY(quick_add);

  g_signal_connect(sidebar, "row-selected",
                   G_CALLBACK(on_sidebar_row_selected), nullptr);
  g_signal_connect(quick_add, "activate",
                   G_CALLBACK(on_quick_add_activate), nullptr);
  g_signal_connect(show_completed, "toggled",
                   G_CALLBACK(on_show_completed_toggled), nullptr);
  apply_css();

  gtk_window_present(GTK_WINDOW(window));
  start_backend();
}

void on_shutdown(GApplication*, gpointer) {
  g_state.shutting_down.store(true, std::memory_order_release);
  if (g_state.startup_thread.joinable()) {
    g_state.startup_thread.join();
  }

  std::unique_ptr<rivet::linux_runtime::Backend> startup_backend;
  {
    std::lock_guard lock(g_state.startup_mutex);
    startup_backend = std::move(g_state.startup_backend);
  }
  if (startup_backend != nullptr) {
    startup_backend->stop();
  }
  if (g_state.backend != nullptr) {
    g_state.backend->stop();
  }
}

}  // namespace

int main(int argc, char** argv) {
  auto* app = gtk_application_new("app.taskly.Taskly",
                                  G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(on_activate), nullptr);
  g_signal_connect(app, "shutdown", G_CALLBACK(on_shutdown), nullptr);
  int const status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);
  return status;
}
