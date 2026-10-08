// Taskly Linux host — GTK4 window over one embedded Racket CS backend.
//
// Interaction contract mirrors the newest first-party hosts (macOS M4 /
// Windows M3) element for element: shared/i18n single-source strings, the
// DESIGN-TOKENS system palette, quick-add through the backend's
// parse_quick_add RPC with a live parse preview, undo-banner task deletion,
// confirmed list deletion, and in-place row/list editors. Only the widget
// toolkit is platform-native.
//
// Threading: boot the runtime off the UI thread; every completion/event is
// dispatched back to the main loop (g_idle_add) before touching widgets.
#include <gtk/gtk.h>
#include <json-glib/json-glib.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "GeneratedBackend.hpp"
#include "system_services.hpp"

namespace {

// ---------------------------------------------------------------------------
// i18n — shared/i18n single source (byte-identical copies staged beside the
// binary or in the dev tree), with an embedded fallback table. Lookup is
// current language → the other language → the key itself (macOS M4 rule).
// ---------------------------------------------------------------------------

std::unordered_map<std::string, std::string> g_i18n[2];  // 0 = zh, 1 = en
int g_active_lang = 0;  // 0 = zh, 1 = en

char const* kFallbackZhKeys[] = {
    "menuFile",               "文件",
    "menuSettings",           "设置",
    "menuHelp",               "帮助",
    "menuNewDatabase",        "新建数据库",
    "menuOpenDatabase",       "打开数据库",
    "menuCloseDatabase",      "关闭数据库",
    "menuExit",               "退出",
    "menuLanguage",           "语言",
    "menuTheme",              "主题",
    "menuAbout",              "关于",
    "menuLangZh",             "简体中文",
    "menuLangEn",             "English",
    "themeFollowSystem",      "跟随系统",
    "themeLight",             "浅色",
    "themeDark",              "深色",
    "navToday",               "今天",
    "navPlanned",             "计划",
    "navAll",                 "全部",
    "navCompleted",           "完成",
    "sectionMyLists",         "我的列表",
    "sidebarHide",            "隐藏侧边栏",
    "sidebarShow",            "显示侧边栏",
    "searchHint",             "搜索任务",
    "taskListInputHint",      "+ 添加任务",
    "taskListInputHintNoDb",  "请先创建或打开数据库",
    "showCompletedToggle",    "显示已完成",
    "hideCompletedToggle",    "隐藏已完成",
    "dialogCancel",           "取消",
    "dialogConfirm",          "确定",
    "dialogClear",            "清除",
    "dialogSave",             "保存",
    "dialogCreateList",       "创建列表",
    "dialogEditList",         "编辑列表",
    "dialogListName",         "列表名称",
    "dialogInputListName",    "请输入列表名称",
    "dialogSelectDate",       "选择日期",
    "labelTask",              "任务:",
    "labelNotes",             "备注:",
    "labelDate",              "日期:",
    "labelTime",              "时间:",
    "hintAddNotes",           "添加备注信息...",
    "taskDelete",             "删除",
    "tooltipDoubleClickEdit", "双击编辑",
    "listDeleteConfirm",      "确认删除列表",
    "listDeleteConfirmContent",
    "确定要删除这个列表吗？列表下的所有任务也会被删除，此操作无法撤销。",
    "listDelete",             "删除列表",
    "bannerTaskDeleted",      "已删除”{0}“",
    "bannerUndo",             "撤销",
    "contextMenuDetails",     "详细信息",
    "contextMenuCustomDate",  "自定日期…",
    "dateTomorrow",           "明天",
    "dateYesterday",          "昨天",
    "reminderTitle",          "⏰ 任务到期",
    "reminderDueAt",          "到期时间",
    "reminderStartupSummary", "{0} 个任务已过期",
    "taskCreateListFirst",    "请先创建一个任务列表",
    "sectionOverdue",         "逾期",
    "sectionThisWeek",        "本周",
    "sectionLater",           "以后",
    "statusShowToday",        "今天的任务",
    "statusShowPlanned",      "计划中的任务",
    "statusShowAll",          "全部任务",
    "statusShowCompleted",    "已完成的任务",
    "statusTaskAdded",        "任务已添加",
    "statusTaskDeleted",      "任务已删除",
    "subtitleToday",          "{0}年{1}{2}日 {3}",
    "subtitleOpenTasks",      "{0} 个未完成",
    "subtitleCompleted",      "{0} 个已完成",
    "aboutContent",
    "一款专注高效的个人任务管理工具\n帮助您轻松规划、组织和完成各项任务",
    nullptr,
};

char const* kFallbackEnKeys[] = {
    "menuFile",               "File",
    "menuSettings",           "Settings",
    "menuHelp",               "Help",
    "menuNewDatabase",        "New Database",
    "menuOpenDatabase",       "Open Database",
    "menuCloseDatabase",      "Close Database",
    "menuExit",               "Exit",
    "menuLanguage",           "Language",
    "menuTheme",              "Theme",
    "menuAbout",              "About",
    "menuLangZh",             "Simplified Chinese",
    "menuLangEn",             "English",
    "themeFollowSystem",      "Follow system",
    "themeLight",             "Light",
    "themeDark",              "Dark",
    "navToday",               "Today",
    "navPlanned",             "Planned",
    "navAll",                 "All",
    "navCompleted",           "Completed",
    "sectionMyLists",         "My Lists",
    "sidebarHide",            "Hide Sidebar",
    "sidebarShow",            "Show Sidebar",
    "searchHint",             "Search tasks",
    "taskListInputHint",      "+ Add Task",
    "taskListInputHintNoDb",  "Please create or open database first",
    "showCompletedToggle",    "Show Completed",
    "hideCompletedToggle",    "Hide Completed",
    "dialogCancel",           "Cancel",
    "dialogConfirm",          "OK",
    "dialogClear",            "Clear",
    "dialogSave",             "Save",
    "dialogCreateList",       "Create List",
    "dialogEditList",         "Edit List",
    "dialogListName",         "List Name",
    "dialogInputListName",    "Please enter list name",
    "dialogSelectDate",       "Select Date",
    "labelTask",              "Task:",
    "labelNotes",             "Notes:",
    "labelDate",              "Date:",
    "labelTime",              "Time:",
    "hintAddNotes",           "Add notes...",
    "taskDelete",             "Delete",
    "tooltipDoubleClickEdit", "Double-click to edit",
    "listDeleteConfirm",      "Confirm Delete List",
    "listDeleteConfirmContent",
    "Are you sure you want to delete this list? All tasks in it will be "
    "deleted. This action cannot be undone.",
    "listDelete",             "Delete List",
    "bannerTaskDeleted",      "Deleted “{0}”",
    "bannerUndo",             "Undo",
    "contextMenuDetails",     "Details",
    "contextMenuCustomDate",  "Custom Date…",
    "dateTomorrow",           "Tomorrow",
    "dateYesterday",          "Yesterday",
    "reminderTitle",          "⏰ Task Due",
    "reminderDueAt",          "Due at",
    "reminderStartupSummary", "{0} task(s) overdue",
    "taskCreateListFirst",    "Please create a task list first",
    "sectionOverdue",         "Overdue",
    "sectionThisWeek",        "This Week",
    "sectionLater",           "Later",
    "statusShowToday",        "Today's tasks",
    "statusShowPlanned",      "Planned tasks",
    "statusShowAll",          "All tasks",
    "statusShowCompleted",    "Completed tasks",
    "statusTaskAdded",        "Task added",
    "statusTaskDeleted",      "Task deleted",
    "subtitleToday",          "{3}, {1} {2}, {0}",
    "subtitleOpenTasks",      "{0} open",
    "subtitleCompleted",      "{0} completed",
    "aboutContent",
    "A focused and efficient personal task management tool\nHelping you "
    "plan, organize and complete tasks easily",
    nullptr,
};

void load_fallback_i18n() {
  for (int lang = 0; lang < 2; ++lang) {
    auto& table = g_i18n[lang];
    table.clear();
    char const** entries = lang == 0 ? kFallbackZhKeys : kFallbackEnKeys;
    for (int i = 0; entries[i] != nullptr; i += 2) {
      table[entries[i]] = entries[i + 1];
    }
  }
}

bool load_i18n_file(char const* path, int lang) {
  auto* parser = json_parser_new();
  GError* error = nullptr;
  json_parser_load_from_file(parser, path, &error);
  if (error != nullptr) {
    g_error_free(error);
    g_object_unref(parser);
    return false;
  }
  JsonNode* root = json_parser_get_root(parser);
  if (root == nullptr || !JSON_NODE_HOLDS_OBJECT(root)) {
    g_object_unref(parser);
    return false;
  }
  JsonObject* object = json_node_get_object(root);
  bool loaded_any = false;
  for (GList* member = json_object_get_members(object); member != nullptr;
       member = member->next) {
    auto const* key = static_cast<char const*>(member->data);
    JsonNode* value = json_object_get_member(object, key);
    if (value == nullptr || !JSON_NODE_HOLDS_VALUE(value)) continue;
    auto const* text = json_node_get_string(value);
    if (text == nullptr) continue;
    g_i18n[lang][key] = text;
    loaded_any = true;
  }
  g_object_unref(parser);
  return loaded_any;
}

void load_i18n(std::filesystem::path const& exe_dir) {
  load_fallback_i18n();
  std::filesystem::path const candidates[] = {
      exe_dir / "res" / "i18n",
      exe_dir / ".." / ".." / "shared" / "i18n",  // dev tree: .rivet/stage
  };
  char const* names[] = {"zh.json", "en.json"};
  for (int lang = 0; lang < 2; ++lang) {
    for (auto const& dir : candidates) {
      auto path = dir / names[lang];
      std::error_code ec;
      if (!std::filesystem::exists(path, ec)) continue;
      if (load_i18n_file(path.c_str(), lang)) break;
    }
  }
}

std::string tr(char const* key) {
  auto const& table = g_i18n[g_active_lang];
  auto it = table.find(key);
  if (it != table.end()) return it->second;
  auto const& other = g_i18n[g_active_lang == 0 ? 1 : 0];
  auto other_it = other.find(key);
  if (other_it != other.end()) return other_it->second;
  return key;
}

std::string format_positional(std::string const& pattern,
                              std::string const& a,
                              std::string const& b = "",
                              std::string const& c = "",
                              std::string const& d = "") {
  std::string out = pattern;
  auto replace = [&out](char const* token, std::string const& value) {
    auto const pos = out.find(token);
    if (pos != std::string::npos) {
      out.replace(pos, std::strlen(token), value);
    }
  };
  replace("{0}", a);
  replace("{1}", b);
  replace("{2}", c);
  replace("{3}", d);
  return out;
}

// ---------------------------------------------------------------------------
// Theme palettes — DESIGN-TOKENS (Apple system palette, light + dark).
// ---------------------------------------------------------------------------

struct Palette {
  char const* background;
  char const* sidebar;
  char const* accent;
  char const* secondary;
  char const* muted;
  char const* divider;
  char const* input_border;
  char const* surface;
  char const* hover;
  char const* selected;
  char const* overdue;
  char const* planned;
};

// Values mirror macos-host Theme.swift exactly (incl. alpha-based
// selection/hover fills).
constexpr Palette kLight{
    "#FFFFFF", "#F2F2F2", "#007AFF", "#8E8E93", "#B0B0B5",
    "#E3E3E8", "#C7C7CC", "#FFFFFF", "rgba(0,0,0,0.05)",
    "rgba(0,0,0,0.08)", "#FF3B30", "#FF3B30",
};

constexpr Palette kDark{
    "#1E1E1E", "#2A2A2C", "#0A84FF", "#98989E", "#6B6B72",
    "#3F3F44", "#4A4A50", "#323234", "rgba(255,255,255,0.07)",
    "rgba(255,255,255,0.12)", "#FF3B30", "#FF3B30",
};

Palette const& system_palette();

// ---------------------------------------------------------------------------
// View model + widgets
// ---------------------------------------------------------------------------

enum class ViewKind { Today, Planned, All, Completed, List };

struct AppState {
  GtkWindow* window{nullptr};
  GtkBox* menubar_box{nullptr};
  GtkWidget* chips[4]{nullptr, nullptr, nullptr, nullptr};
  GtkLabel* my_lists_caption{nullptr};
  GtkListBox* user_list{nullptr};
  GtkButton* new_list_button{nullptr};
  GtkLabel* pane_title{nullptr};
  GtkLabel* pane_subtitle{nullptr};
  GtkSearchEntry* search_box{nullptr};
  GtkToggleButton* show_completed_toggle{nullptr};
  GtkEntry* quick_add{nullptr};
  GtkLabel* quick_add_preview{nullptr};
  GtkButton* quick_plus{nullptr};
  GtkListBox* task_list{nullptr};
  GtkStack* list_stack{nullptr};
  GtkLabel* empty_icon{nullptr};
  GtkLabel* empty_text{nullptr};
  GtkWidget* sidebar_widget{nullptr};
  GtkButton* sidebar_toggle{nullptr};
  GtkBox* banner_box{nullptr};
  GtkLabel* status_text{nullptr};

  std::unique_ptr<rivet::linux_runtime::Backend> backend;
  std::unique_ptr<rivet_app::API> api;
  std::mutex startup_mutex;
  std::thread startup_thread;
  std::unique_ptr<rivet::linux_runtime::Backend> startup_backend;
  std::string startup_error;
  std::atomic<bool> shutting_down{false};

  rivet_app::Settings settings;
  rivet_app::SmartCounts current_counts;
  std::vector<rivet_app::TodoList> lists;
  std::vector<rivet_app::Task> tasks;
  std::string current_search;
  std::string language{"zh"};
  std::uint64_t preview_sequence{0};

  ViewKind view{ViewKind::Today};
  std::int64_t view_list_id{0};
  bool show_completed{false};
  bool completed_section_expanded{true};
  bool suppress_selection{false};
  std::atomic<bool> reload_in_flight{false};
  std::int64_t open_editor_id{-1};

  // Reminders (PRODUCT-SPEC §9): one notification per task per session, a
  // dedupe set that resets when the database changes, and a disable-on-failure
  // rule — a missing notification service must never crash the host.
  std::unordered_set<std::int64_t> notified_tasks;
  std::string notified_db_path;
  bool notifications_disabled{false};
};

AppState g_state;
Palette const* g_state_palette = &kLight;

// Forward declarations.
GtkWidget* make_task_row(rivet_app::Task const& task);
void rebuild_sidebar();
void rebuild_task_list();
void reload_snapshot();
void save_setting(char const* key, std::string const& value);
void apply_language();
void apply_theme(std::string const& theme);
void open_database_at(std::string const& path);
void set_status(char const* message);
void set_status_error(std::string const& message);
void flash_status(std::string const& message);
void show_undo_banner(rivet_app::Task const& deleted);
void refresh_persistent_status();
void set_view(ViewKind kind);

// ---------------------------------------------------------------------------
// UI dispatch (completions/events arrive on the backend reader thread)
// ---------------------------------------------------------------------------

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
  dispatch_ui([result = std::move(result),
               then = std::move(then)]() mutable {
    if (!result.succeeded()) {
      try {
        std::rethrow_exception(result.error);
      } catch (std::exception const& e) {
        set_status_error(e.what());
      } catch (...) {
        set_status_error("unknown backend failure");
      }
      return;
    }
    try {
      if constexpr (std::is_void_v<T>) {
        then();
      } else {
        then(result.get());
      }
    } catch (std::exception const& e) {
      set_status_error(e.what());
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

std::filesystem::path executable_path() {
  return std::filesystem::read_symlink("/proc/self/exe");
}

template <typename T>
T const* find_by_id(std::vector<T> const& items, std::int64_t id) {
  for (auto const& item : items) {
    if (item.id == id) return &item;
  }
  return nullptr;
}

// Local calendar date as YYYY-MM-DD, `offset_days` from today.
std::string date_string(int offset_days) {
  auto const now = std::time(nullptr) +
                   static_cast<std::time_t>(offset_days) * 24 * 60 * 60;
  std::tm local{};
  localtime_r(&now, &local);
  char buffer[11];
  std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02d", local.tm_year + 1900,
                local.tm_mon + 1, local.tm_mday);
  return buffer;
}

// Lexicographic YYYY-MM-DD compare; malformed dates sort after any date.
int date_compare(std::string const& due, std::string const& today) {
  if (due.size() != 10) return 1;
  return due.compare(today);
}

// Due chip: overdue red, today accent, otherwise secondary; a clock glyph
// only when a time is set (DESIGN-TOKENS).
char const* due_color_class(std::string const& due_date, bool completed) {
  if (completed) return "meta-text";
  auto const compare = date_compare(due_date, date_string(0));
  if (compare < 0) return "due-overdue";
  if (compare == 0) return "due-today";
  return "meta-text";
}

// Localized absolute day label: 今天/明天/昨天 by name, otherwise
// `8月31日` (zh) or `Aug 31` (en) — locale-independent on purpose.
std::string format_day_label(std::string const& due) {
  if (due.size() == 10 && due[4] == '-' && due[7] == '-') {
    auto const month = std::atoi(due.substr(5, 2).c_str());
    auto const day = std::atoi(due.substr(8, 2).c_str());
    if (g_state.language == "en") {
      static char const* months[] = {"Jan",  "Feb",       "Mar", "Apr",
                                     "May",  "Jun",       "Jul", "Aug",
                                     "Sep",  "Oct",       "Nov", "Dec"};
      if (month >= 1 && month <= 12) {
        return std::string(months[month - 1]) + " " + std::to_string(day);
      }
    } else {
      return std::to_string(month) + "月" + std::to_string(day) + "日";
    }
  }
  return due;
}

std::string due_chip_text(rivet_app::Task const& task) {
  if (!task.due_date.has_value()) return "";
  std::string text = *task.due_date;
  auto const compare = date_compare(*task.due_date, date_string(0));
  if (compare == 0) {
    text = tr("navToday");
  } else if (compare == -1) {
    text = tr("dateYesterday");
  } else if (date_compare(*task.due_date, date_string(1)) == 0) {
    text = tr("dateTomorrow");
  } else {
    text = format_day_label(*task.due_date);
  }
  if (task.due_time.has_value()) {
    text = "⏰ " + text + " " + *task.due_time;
  }
  return text;
}

std::string view_string_for(ViewKind kind) {
  switch (kind) {
    case ViewKind::Today: return "today";
    case ViewKind::Planned: return "planned";
    case ViewKind::Completed: return "completed";
    case ViewKind::List:
    case ViewKind::All:
    default: return "all";
  }
}

std::string view_title() {
  switch (g_state.view) {
    case ViewKind::Today: return tr("navToday");
    case ViewKind::Planned: return tr("navPlanned");
    case ViewKind::Completed: return tr("navCompleted");
    case ViewKind::List:
      if (auto const* list = find_by_id(g_state.lists, g_state.view_list_id)) {
        return list->name;
      }
      return tr("navAll");
    case ViewKind::All:
    default: return tr("navAll");
  }
}

// Pane subtitle (macOS M4 semantics): the Today view shows the full
// localized date; other views show open/completed counts.
std::string view_subtitle() {
  if (g_state.view == ViewKind::Today) {
    auto const now = std::time(nullptr);
    std::tm local{};
    localtime_r(&now, &local);
    static char const* weekdays_zh[] = {"周日", "周一", "周二",
                                        "周三", "周四", "周五", "周六"};
    static char const* weekdays_en[] = {"Sunday",   "Monday", "Tuesday",
                                        "Wednesday", "Thursday", "Friday",
                                        "Saturday"};
    auto const weekday =
        g_state.language == "en" ? weekdays_en[local.tm_wday]
                                 : weekdays_zh[local.tm_wday];
    return format_positional(
        tr("subtitleToday"), std::to_string(local.tm_year + 1900),
        std::to_string(local.tm_mon + 1), std::to_string(local.tm_mday),
        weekday);
  }
  std::int64_t open = 0;
  std::int64_t completed = 0;
  for (auto const& task : g_state.tasks) {
    if (task.completed) {
      ++completed;
    } else {
      ++open;
    }
  }
  auto subtitle =
      format_positional(tr("subtitleOpenTasks"), std::to_string(open));
  if (completed > 0) {
    subtitle += " · " + format_positional(tr("subtitleCompleted"),
                                          std::to_string(completed));
  }
  return subtitle;
}

// Signed ARGB int → #RRGGBB for CSS.
std::string argb_to_hex(std::int64_t color) {
  auto const rgb = static_cast<unsigned long long>(color) & 0xFFFFFFULL;
  char buffer[8];
  std::snprintf(buffer, sizeof(buffer), "#%06llX", rgb);
  return buffer;
}

void set_status(char const* message) {
  gtk_label_set_text(g_state.status_text, message);
}

void set_status_error(std::string const& message) {
  set_status(message.c_str());
}

// Persistent status priority (PRODUCT-SPEC §2): search term > view
// description > list name. Flashes override for 3 seconds.
guint g_status_flash_source = 0;

void refresh_persistent_status() {
  if (!g_state.current_search.empty()) {
    set_status((tr("searchHint") + ": " + g_state.current_search).c_str());
    return;
  }
  char const* key = "statusShowAll";
  switch (g_state.view) {
    case ViewKind::Today: key = "statusShowToday"; break;
    case ViewKind::Planned: key = "statusShowPlanned"; break;
    case ViewKind::Completed: key = "statusShowCompleted"; break;
    case ViewKind::List:
    case ViewKind::All: key = "statusShowAll"; break;
  }
  set_status(tr(key).c_str());
}

int on_flash_expired(gpointer) {
  g_status_flash_source = 0;
  refresh_persistent_status();
  return G_SOURCE_REMOVE;
}

void flash_status(std::string const& message) {
  set_status(message.c_str());
  if (g_status_flash_source != 0) {
    g_source_remove(g_status_flash_source);
  }
  g_status_flash_source = g_timeout_add_seconds(3, on_flash_expired, nullptr);
}

// ---------------------------------------------------------------------------
// CSS — regenerated per palette (DESIGN-TOKENS light/dark).
// ---------------------------------------------------------------------------

void apply_css(Palette const& p) {
  auto* provider = gtk_css_provider_new();
  std::string css = ""
      ".taskly-sidebar { background: " + std::string(p.sidebar) + "; }\n"
      ".taskly-divider { background: " + p.divider + "; min-width: 1px; }\n"
      ".taskly-statusbar { background: " + p.sidebar +
          "; min-height: 28px; }\n"
      ".taskly-statusbar label { color: " + p.secondary +
          "; font-size: 12px; }\n"
      ".section-caption { color: " + p.muted +
          "; font-size: 12px; font-weight: 600; }\n"
      ".section-header { color: " + p.secondary +
          "; font-size: 13px; font-weight: 600; padding: 0 16px; }\n"
      ".count-badge { color: " + p.secondary + "; font-size: 12px; }\n"
      ".meta-text { color: " + p.secondary + "; font-size: 12px; }\n"
      ".pane-title { font-size: 22px; font-weight: 700; }\n"
      ".pane-subtitle { font-size: 13px; color: " + p.secondary + "; }\n"
      ".task-text { font-size: 14px; }\n"
      ".task-done { color: " + p.muted +
          "; text-decoration: line-through; }\n"
      ".row-dot { border-radius: 4px; min-width: 8px; min-height: 8px; }\n"
      ".due-chip { font-size: 12px; }\n"
      ".due-today { color: " + p.accent + "; }\n"
      ".due-overdue { color: " + p.overdue + "; }\n"
      "listbox.task-row-list > row { min-height: 44px; padding: 9px 16px; "
          "background: " + std::string(p.surface) + "; }\n"
      "listbox.sidebar-list > row { min-height: 34px; border-radius: 8px; "
          "margin: 1px 4px; padding: 5px 8px; background: " +
          std::string(p.surface) + "; border: 1px solid " + p.divider + "; }\n"
      "listbox.sidebar-list > row:hover { background: " +
          std::string(p.hover) + "; }\n"
      "listbox.sidebar-list > row:selected { background: " +
          std::string(p.selected) + "; }\n"
      "button.chip { min-height: 34px; border-radius: 8px; background: " +
          std::string(p.surface) + "; border: 1px solid " + p.divider + "; }\n"
      "button.chip-selected { background: " + std::string(p.selected) +
          "; border: 1px solid " + p.divider + "; }\n"
      ".chip-glyph-today { color: " + p.accent + "; }\n"
      ".chip-glyph-planned { color: " + p.planned + "; }\n"
      ".chip-glyph-all { color: " + p.secondary + "; }\n"
      ".chip-glyph-completed { color: " + p.secondary + "; }\n"
      "button.accent-toggle { color: " + p.accent + "; font-size: 13px; }\n"
      ".quick-add-box { border-radius: 12px; border: 1px solid " +
          std::string(p.input_border) + "; }\n"
      ".quick-add-box:focus-within { border: 2px solid " + p.accent + "; }\n"
      "entry.quick-add { min-height: 36px; border: none; background: none; "
          "box-shadow: none; }\n"
      "button.quick-add-plus { background: " + p.accent +
          "; color: #FFFFFF; border-radius: 11px; min-width: 22px; "
          "min-height: 22px; }\n"
      ".preview-capsule { font-size: 12px; color: " + p.accent +
          "; background: " + p.selected + "; border-radius: 9px; "
          "padding: 2px 8px; }\n"
      "box.banner-card { border-radius: 10px; border: 1px solid " +
          std::string(p.divider) + "; background: " + p.surface + "; }\n"
      ".section-header { color: " + p.secondary +
          "; font-size: 13px; font-weight: 600; padding: 0 16px; }\n"
      ".empty-icon { font-size: 48px; }\n"
      ".list-dot { border-radius: 10px; min-width: 20px; min-height: 20px; "
          "font-size: 11px; }\n"
      ".dot-neutral { background: " + std::string(p.divider) + "; }\n";
  gtk_css_provider_load_from_string(provider, css.c_str());
  gtk_style_context_add_provider_for_display(
      gdk_display_get_default(), GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(provider);
}

// The WinUI/SwiftUI hosts resolve "system" through the OS; on GNOME the
// closest equivalent is the desktop color-scheme setting. Forcing "light"
// cannot override a dark system theme without libadwaita — accepted delta.
Palette const& system_palette() {
  GSettingsSchemaSource* source = g_settings_schema_source_get_default();
  GSettingsSchema* schema = nullptr;
  if (source != nullptr) {
    schema = g_settings_schema_source_lookup(
        source, "org.gnome.desktop.interface", TRUE);
  }
  if (schema == nullptr) return kLight;
  GSettings* settings = g_settings_new_full(schema, nullptr, nullptr);
  gchar* scheme = g_settings_get_string(settings, "color-scheme");
  bool const dark = scheme != nullptr && std::string(scheme) == "prefer-dark";
  g_free(scheme);
  g_object_unref(settings);
  g_settings_schema_unref(schema);
  if (dark) return kDark;
  // Without libadwaita, GTK4 picks its light/dark variant from the theme
  // NAME, not the portal: a "-dark" theme forces dark widgets regardless.
  gchar* theme_name = nullptr;
  g_object_get(gtk_settings_get_default(), "gtk-theme-name", &theme_name,
               nullptr);
  bool const dark_widgets =
      theme_name != nullptr && std::strstr(theme_name, "-dark") != nullptr;
  g_free(theme_name);
  return dark_widgets ? kDark : kLight;
}

void apply_theme(std::string const& theme) {
  bool const dark_pref = theme == "dark";
  Palette const& palette = dark_pref          ? kDark
                           : theme == "light" ? kLight
                                              : system_palette();
  g_state_palette = &palette;
  apply_css(palette);
  gboolean prefer_dark = FALSE;
  if (theme == "dark" || (theme == "system" && &palette == &kDark)) {
    prefer_dark = TRUE;
  }
  g_object_set(gtk_settings_get_default(),
               "gtk-application-prefer-dark-theme", prefer_dark, nullptr);
  // This desktop's XSetting ships a dark widget variant while the
  // color-scheme says light — pin the widget theme to the chosen palette
  // (strip or append the "-dark" suffix of the current theme name).
  gchar* theme_name = nullptr;
  g_object_get(gtk_settings_get_default(), "gtk-theme-name", &theme_name,
               nullptr);
  std::string base = theme_name != nullptr ? theme_name : "Adwaita";
  g_free(theme_name);
  if (base.size() > 5 && base.substr(base.size() - 5) == "-dark") {
    base.erase(base.size() - 5);
  }
  base += dark_pref ? "-dark" : "";
  g_object_set(gtk_settings_get_default(), "gtk-theme-name",
               base.c_str(), nullptr);
}

// ---------------------------------------------------------------------------
// Data operations (the changed event / 2s poll provide the authoritative
// reload; completions only surface failures)
// ---------------------------------------------------------------------------

void save_setting(char const* key, std::string const& value) {
  if (g_state.api == nullptr) return;
  g_state.api->set_setting_async(
      key, value, [](rivet_app::Result<rivet_app::Settings> result) {
        on_result(std::move(result),
                  [](rivet_app::Settings const& settings) {
                    g_state.settings = settings;
                  });
      });
}

void add_task_full(rivet_app::Task const& task) {
  if (g_state.api == nullptr) return;
  g_state.api->add_task_async(
      task.text, task.list_id, task.due_date, task.due_time, task.notes,
      [](rivet_app::Result<rivet_app::Task> result) {
        on_result(std::move(result), [](rivet_app::Task const&) {});
      });
}

void toggle_task(std::int64_t id, bool completed) {
  if (g_state.api == nullptr) return;
  g_state.api->set_completed_async(
      id, completed, [](rivet_app::Result<rivet_app::Task> result) {
        on_result(std::move(result), [](rivet_app::Task const&) {});
      });
}

void delete_task_by_id(std::int64_t id) {
  if (g_state.api == nullptr) return;
  g_state.api->delete_task_async(
      id, [](rivet_app::Result<bool> result) {
        on_result(std::move(result), [](bool const&) {});
      });
}

void delete_list_by_id(std::int64_t id) {
  if (g_state.api == nullptr) return;
  if (g_state.view == ViewKind::List && g_state.view_list_id == id) {
    g_state.view = ViewKind::All;
    g_state.view_list_id = 0;
  }
  g_state.api->delete_list_async(
      id, [](rivet_app::Result<bool> result) {
        on_result(std::move(result), [](bool const&) {});
      });
}

void create_list_full(std::string const& name, std::optional<std::string> icon,
                      std::optional<std::int64_t> color) {
  if (g_state.api == nullptr || name.empty()) return;
  g_state.api->create_list_async(
      name, icon, color, [](rivet_app::Result<rivet_app::TodoList> result) {
        on_result(std::move(result), [](rivet_app::TodoList const&) {});
      });
}

void update_list_full(rivet_app::TodoList list) {
  if (g_state.api == nullptr) return;
  g_state.api->update_list_async(
      list, [](rivet_app::Result<rivet_app::TodoList> result) {
        on_result(std::move(result), [](rivet_app::TodoList const&) {});
      });
}

void save_task_edits(rivet_app::Task updated) {
  if (g_state.api == nullptr) return;
  g_state.api->update_task_async(
      updated, [](rivet_app::Result<rivet_app::Task> result) {
        on_result(std::move(result), [](rivet_app::Task const&) {});
      });
}

void run_search(std::string const& keyword) {
  if (g_state.api == nullptr) return;
  g_state.api->search_tasks_async(
      keyword,
      [keyword](rivet_app::Result<std::vector<rivet_app::Task>> result) {
        on_result(
            std::move(result),
            [keyword](std::vector<rivet_app::Task> const& results) {
              // Drop stale completions: only the newest keyword renders.
              if (g_state.current_search != keyword) return;
              gtk_list_box_remove_all(g_state.task_list);
              for (auto const& task : results) {
                gtk_list_box_insert(g_state.task_list, make_task_row(task),
                                    -1);
              }
            });
      });
}

void reload_snapshot() {
  if (g_state.api == nullptr) return;
  auto expected = false;
  if (!g_state.reload_in_flight.compare_exchange_strong(
          expected, true, std::memory_order_release,
          std::memory_order_acquire)) {
    return;
  }
  auto const view_kind = g_state.view;
  auto const list_id = g_state.view_list_id;
  auto const include_completed = g_state.show_completed;
  g_state.api->load_snapshot_async(
      view_string_for(view_kind),
      view_kind == ViewKind::List
          ? std::optional<std::int64_t>(list_id)
          : std::nullopt,
      include_completed,
      [](rivet_app::Result<rivet_app::Snapshot> result) {
        // Release the reload gate on every terminal path so later polls and
        // `changed` events are not swallowed.
        dispatch_ui([] {
          g_state.reload_in_flight.store(false, std::memory_order_release);
        });
        on_result(std::move(result),
                  [](rivet_app::Snapshot const& snapshot) {
                    g_state.current_counts = snapshot.counts;
                    g_state.lists = snapshot.lists;
                    g_state.tasks = snapshot.tasks;
                    rebuild_sidebar();
                    // An active search owns the task list; refreshing the
                    // snapshot must not overwrite the results.
                    if (!g_state.current_search.empty()) {
                      run_search(g_state.current_search);
                    } else {
                      rebuild_task_list();
                    }
                  });
      });
}

// ---------------------------------------------------------------------------
// Reminders (PRODUCT-SPEC §9) — check every 60 s while a DB is connected,
// plus one check at startup. Due = incomplete ∧ has due_date ∧
// combine(due_date, due_time|00:00) ≤ now. Each task notifies at most once
// per session (dedupe set, reset when the DB changes). Startup: ≤3 overdue →
// one notification each; >3 → one summary, and everything seen is marked
// notified. The check runs against a full-database snapshot (not the current
// view). Never crash: capability probe + swallow-everything disables
// reminders for the session.
// ---------------------------------------------------------------------------

// Local "now" as YYYY-MM-DD HH:MM:SS for lexicographic due compares.
std::string now_stamp() {
  auto const now = std::time(nullptr);
  std::tm local{};
  localtime_r(&now, &local);
  char buffer[20];
  std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02d %02d:%02d:%02d",
                local.tm_year + 1900, local.tm_mon + 1, local.tm_mday,
                local.tm_hour, local.tm_min, local.tm_sec);
  return buffer;
}

bool is_task_due(rivet_app::Task const& task, std::string const& now) {
  if (task.completed || !task.due_date.has_value()) return false;
  auto combined = *task.due_date + " " +
                  task.due_time.value_or("00:00") + ":00";
  if (combined.size() == 16) combined += ":00";  // "yyyy-MM-dd HH:mm"
  return combined <= now;
}

void notify_task_due(rivet_app::Task const& task) {
  auto body = task.text + "\n" + tr("reminderDueAt") + ": " +
              *task.due_date;
  if (task.due_time.has_value()) {
    body += " " + *task.due_time;
  }
  rivet::system::Notifications::Notify(
      "Taskly", "taskly-reminder-" + std::to_string(task.id),
      tr("reminderTitle"), body);
}

void check_reminders(bool startup) {
  if (g_state.notifications_disabled || g_state.api == nullptr) return;
  try {
    if (!rivet::system::Notifications::available()) {
      g_state.notifications_disabled = true;
      return;
    }
  } catch (...) {
    g_state.notifications_disabled = true;
    return;
  }
  // The due set must cover the whole database, not the visible view. Errors
  // are swallowed: a failed reminder snapshot must not touch the UI status.
  g_state.api->load_snapshot_async(
      "all", std::nullopt, false,
      [startup](rivet_app::Result<rivet_app::Snapshot> result) {
        dispatch_ui([result = std::move(result), startup]() mutable {
          if (g_state.notifications_disabled) return;
          try {
            auto const snapshot = result.get();
            auto const now = now_stamp();
            std::vector<rivet_app::Task const*> due;
            for (auto const& task : snapshot.tasks) {
              if (g_state.notified_tasks.count(task.id) > 0) continue;
              if (is_task_due(task, now)) {
                due.push_back(&task);
              }
            }
            if (due.empty()) return;
            if (startup && due.size() > 3) {
              rivet::system::Notifications::Notify(
                  "Taskly", "taskly-reminder-summary",
                  tr("reminderTitle"),
                  format_positional(tr("reminderStartupSummary"),
                                    std::to_string(due.size())));
            } else {
              for (auto const* task : due) {
                notify_task_due(*task);
              }
            }
            for (auto const* task : due) {
              g_state.notified_tasks.insert(task->id);
            }
          } catch (std::exception const&) {
            g_state.notifications_disabled = true;
          } catch (...) {
            g_state.notifications_disabled = true;
          }
        });
      });
}

int on_reminder_timer(gpointer) {
  check_reminders(false);
  return G_SOURCE_CONTINUE;
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

void prompt_dialog(char const* title, char const* placeholder,
                   std::string const& initial,
                   std::function<void(std::string const&)> on_ok) {
  auto* dialog = gtk_dialog_new_with_buttons(
      title, g_state.window,
      static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT),
      tr("dialogCancel").c_str(), GTK_RESPONSE_CANCEL,
      tr("dialogConfirm").c_str(), GTK_RESPONSE_ACCEPT, nullptr);
  auto* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
  auto* entry = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(entry), placeholder);
  gtk_editable_set_text(GTK_EDITABLE(entry), initial.c_str());
  gtk_widget_set_margin_top(entry, 12);
  gtk_widget_set_margin_bottom(entry, 6);
  gtk_widget_set_margin_start(entry, 12);
  gtk_widget_set_margin_end(entry, 12);
  gtk_box_append(GTK_BOX(content), entry);
  g_object_set_data(G_OBJECT(dialog), "prompt-entry", entry);
  auto* const callback =
      new std::function<void(std::string const&)>(std::move(on_ok));
  g_object_set_data_full(
      G_OBJECT(dialog), "prompt-on-ok", callback,
      +[](gpointer data) {
        delete static_cast<std::function<void(std::string const&)>*>(data);
      });
  g_signal_connect(
      dialog, "response",
      G_CALLBACK(+[](GtkDialog* dialog, gint response, gpointer) {
        if (response == GTK_RESPONSE_ACCEPT) {
          auto* entry =
              GTK_ENTRY(g_object_get_data(G_OBJECT(dialog), "prompt-entry"));
          auto const* on_ok = static_cast<std::function<void(
              std::string const&)>*>(g_object_get_data(G_OBJECT(dialog),
                                                       "prompt-on-ok"));
          (*on_ok)(gtk_editable_get_text(GTK_EDITABLE(entry)));
        }
        gtk_window_destroy(GTK_WINDOW(dialog));
      }),
      nullptr);
  g_signal_connect(
      entry, "activate",
      G_CALLBACK(+[](GtkEntry* entry, gpointer) {
        auto* dialog = GTK_DIALOG(
            gtk_widget_get_ancestor(GTK_WIDGET(entry), GTK_TYPE_DIALOG));
        gtk_dialog_response(dialog, GTK_RESPONSE_ACCEPT);
      }),
      nullptr);
  gtk_window_present(GTK_WINDOW(dialog));
}

void confirm_dialog(char const* title, char const* body,
                    std::function<void()> on_ok) {
  auto* dialog = gtk_dialog_new_with_buttons(
      title, g_state.window,
      static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT),
      tr("dialogCancel").c_str(), GTK_RESPONSE_CANCEL,
      tr("listDelete").c_str(), GTK_RESPONSE_ACCEPT, nullptr);
  auto* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
  auto* label = gtk_label_new(body);
  gtk_label_set_wrap(GTK_LABEL(label), TRUE);
  gtk_widget_set_margin_top(label, 12);
  gtk_widget_set_margin_bottom(label, 6);
  gtk_widget_set_margin_start(label, 12);
  gtk_widget_set_margin_end(label, 12);
  gtk_box_append(GTK_BOX(content), label);
  auto* const callback = new std::function<void()>(std::move(on_ok));
  g_object_set_data_full(
      G_OBJECT(dialog), "confirm-on-ok", callback,
      +[](gpointer data) { delete static_cast<std::function<void()>*>(data); });
  g_signal_connect(
      dialog, "response",
      G_CALLBACK(+[](GtkDialog* dialog, gint response, gpointer) {
        if (response == GTK_RESPONSE_ACCEPT) {
          auto const* on_ok = static_cast<std::function<void()>*>(
              g_object_get_data(G_OBJECT(dialog), "confirm-on-ok"));
          (*on_ok)();
        }
        gtk_window_destroy(GTK_WINDOW(dialog));
      }),
      nullptr);
  gtk_window_present(GTK_WINDOW(dialog));
}

void show_about_dialog() {
  auto* dialog = gtk_about_dialog_new();
  gtk_about_dialog_set_program_name(GTK_ABOUT_DIALOG(dialog), "Taskly");
  gtk_about_dialog_set_comments(GTK_ABOUT_DIALOG(dialog),
                                tr("aboutContent").c_str());
  gtk_window_set_transient_for(GTK_WINDOW(dialog), g_state.window);
  gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
  gtk_window_present(GTK_WINDOW(dialog));
}

// ---------------------------------------------------------------------------
// List editor dialog (name + emoji picker + 12-color swatch row)
// ---------------------------------------------------------------------------

constexpr char const* kListEmojis[] = {
    "📋", "🏠", "💼", "⭐", "❤️", "🎯", "📚", "🛒",
    "✈️", "🎵", "💪", "🌱", "🍳", "💡", "🏷", "🔖",
};

constexpr char const* kListColors[] = {
    "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
    "#4CD964", "#5AC8FA", "#5856D6", "#FF2D55",
    "#8E8E93", "#C7C7CC", "#A2845E", "#00C7BE",
};

struct ListEditor {
  GtkEntry* name{nullptr};
  std::string icon;
  std::optional<std::int64_t> color;
  std::function<void(std::string const&, std::optional<std::string>,
                     std::optional<std::int64_t>)>
      on_ok;
};

void on_editor_icon_chosen(GtkButton* button, gpointer user_data) {
  auto* editor = static_cast<ListEditor*>(user_data);
  editor->icon = gtk_button_get_label(button);
}

void on_editor_color_chosen(GtkButton* button, gpointer user_data) {
  auto* editor = static_cast<ListEditor*>(user_data);
  auto const* hex = static_cast<char const*>(
      g_object_get_data(G_OBJECT(button), "color-hex"));
  auto const rgb = static_cast<std::int64_t>(
      g_ascii_strtoll(hex + 1, nullptr, 16));
  // Signed ARGB (alpha 0xFF) — negative when the top bit is set.
  auto const argb =
      static_cast<std::int64_t>(0xFF000000LL | rgb) - INT64_C(0x100000000);
  editor->color = argb;
}

GtkWidget* editor_field_row(char const* caption, GtkWidget* field) {
  auto* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  auto* label = gtk_label_new(caption);
  gtk_label_set_xalign(GTK_LABEL(label), 1.0f);
  gtk_widget_set_size_request(label, 48, -1);
  gtk_box_append(GTK_BOX(row), label);
  gtk_widget_set_hexpand(field, TRUE);
  gtk_box_append(GTK_BOX(row), field);
  return row;
}

void open_list_editor(
    char const* title, rivet_app::TodoList const* existing,
    std::function<void(std::string const&, std::optional<std::string>,
                       std::optional<std::int64_t>)>
        on_ok) {
  auto* editor = new ListEditor();
  editor->on_ok = std::move(on_ok);
  editor->icon = existing != nullptr && existing->icon.has_value()
                     ? *existing->icon
                     : "📋";
  editor->color = existing != nullptr ? existing->color : std::nullopt;

  auto* dialog = gtk_dialog_new_with_buttons(
      title, g_state.window,
      static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT),
      tr("dialogCancel").c_str(), GTK_RESPONSE_CANCEL,
      tr("dialogSave").c_str(), GTK_RESPONSE_ACCEPT, nullptr);
  auto* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));

  auto* name = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(name),
                                 tr("dialogInputListName").c_str());
  if (existing != nullptr) {
    gtk_editable_set_text(GTK_EDITABLE(name), existing->name.c_str());
  }
  g_object_set_data(G_OBJECT(dialog), "editor-name", name);
  gtk_box_append(GTK_BOX(content),
                 editor_field_row(tr("dialogListName").c_str(), name));

  // Icon picker: one row of emoji buttons.
  auto* icon_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  for (auto const* emoji : kListEmojis) {
    auto* button = gtk_button_new_with_label(emoji);
    gtk_widget_add_css_class(button, "flat");
    g_signal_connect(button, "clicked",
                     G_CALLBACK(on_editor_icon_chosen), editor);
    gtk_box_append(GTK_BOX(icon_row), button);
  }
  gtk_box_append(GTK_BOX(content), icon_row);

  // Color picker: 12 swatches.
  auto* color_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  for (auto const* hex : kListColors) {
    auto* button = gtk_button_new();
    gtk_widget_add_css_class(button, "flat");
    gtk_widget_set_size_request(button, 24, 24);
    g_object_set_data_full(G_OBJECT(button), "color-hex", g_strdup(hex),
                           g_free);
    g_signal_connect(button, "clicked",
                     G_CALLBACK(on_editor_color_chosen), editor);
    auto* provider = gtk_css_provider_new();
    std::string const css =
        std::string("button { background: ") + hex + "; border-radius: 12px; }";
    gtk_css_provider_load_from_string(provider, css.c_str());
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(button), GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
    gtk_box_append(GTK_BOX(color_row), button);
  }
  gtk_box_append(GTK_BOX(content), color_row);

  g_object_set_data_full(
      G_OBJECT(dialog), "editor-ctx", editor,
      +[](gpointer data) { delete static_cast<ListEditor*>(data); });
  g_signal_connect(
      dialog, "response",
      G_CALLBACK(+[](GtkDialog* dialog, gint response, gpointer) {
        if (response == GTK_RESPONSE_ACCEPT) {
          auto* editor = static_cast<ListEditor*>(
              g_object_get_data(G_OBJECT(dialog), "editor-ctx"));
          auto* name = GTK_ENTRY(g_object_get_data(G_OBJECT(dialog),
                                                   "editor-name"));
          auto const text =
              std::string(gtk_editable_get_text(GTK_EDITABLE(name)));
          if (!text.empty()) {
            editor->on_ok(text, editor->icon, editor->color);
          }
        }
        gtk_window_destroy(GTK_WINDOW(dialog));
      }),
      nullptr);
  gtk_window_present(GTK_WINDOW(dialog));
}

// ---------------------------------------------------------------------------
// Task rows — 44px total, checkbox, text, due meta, in-place editor,
// context menu (今天/明天/自定日期/清除日期/详情/删除), double-click expands.
// ---------------------------------------------------------------------------

void on_task_check_toggled(GtkCheckButton* button, gpointer) {
  if (g_state.api == nullptr) return;
  auto const id = static_cast<std::int64_t>(
      GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "task-id")));
  toggle_task(id, gtk_check_button_get_active(button));
}

struct TaskEditor {
  GtkEntry* text{nullptr};
  GtkEntry* notes{nullptr};
  GtkEntry* date{nullptr};
  GtkEntry* time{nullptr};
  std::int64_t task_id{0};
};

void on_editor_save_clicked(GtkButton*, gpointer user_data) {
  auto* editor = static_cast<TaskEditor*>(user_data);
  auto const* stored = find_by_id(g_state.tasks, editor->task_id);
  if (stored == nullptr) return;
  auto updated = *stored;
  updated.text = gtk_editable_get_text(GTK_EDITABLE(editor->text));
  auto const notes = std::string(
      gtk_editable_get_text(GTK_EDITABLE(editor->notes)));
  updated.notes =
      notes.empty() ? std::nullopt : std::optional<std::string>(notes);
  auto const date = std::string(
      gtk_editable_get_text(GTK_EDITABLE(editor->date)));
  updated.due_date =
      date.empty() ? std::nullopt : std::optional<std::string>(date);
  auto const time = std::string(
      gtk_editable_get_text(GTK_EDITABLE(editor->time)));
  updated.due_time =
      time.empty() ? std::nullopt : std::optional<std::string>(time);
  save_task_edits(updated);
}

void on_editor_clear_due_clicked(GtkButton*, gpointer user_data) {
  auto* editor = static_cast<TaskEditor*>(user_data);
  gtk_editable_set_text(GTK_EDITABLE(editor->date), "");
  gtk_editable_set_text(GTK_EDITABLE(editor->time), "");
}

void on_editor_calendar_day_selected(GtkCalendar* calendar,
                                     gpointer user_data) {
  auto* editor = static_cast<TaskEditor*>(user_data);
  GDateTime* date = gtk_calendar_get_date(calendar);
  gchar* iso = g_date_time_format(date, "%Y-%m-%d");
  gtk_editable_set_text(GTK_EDITABLE(editor->date), iso);
  g_free(iso);
  g_date_time_unref(date);
}

// Expand (or collapse) the in-place editor underneath the row. When
// `restore` is given, the fields are seeded from saved in-progress text
// instead of the stored task (see rebuild_task_list's editor carry-over).
void set_task_editor_expanded(GtkListBoxRow* row, std::int64_t id,
                              bool expand, bool focus_date,
                              rivet_app::Task const* restore) {
  auto* revealer = GTK_REVEALER(
      g_object_get_data(G_OBJECT(row), "task-editor-revealer"));
  if (revealer == nullptr) {
    auto* editor = new TaskEditor();
    editor->task_id = id;
    auto const* task = find_by_id(g_state.tasks, id);

    editor->text = GTK_ENTRY(gtk_entry_new());
    editor->notes = GTK_ENTRY(gtk_entry_new());
    editor->date = GTK_ENTRY(gtk_entry_new());
    editor->time = GTK_ENTRY(gtk_entry_new());
    gtk_entry_set_placeholder_text(editor->notes, tr("hintAddNotes").c_str());
    gtk_entry_set_placeholder_text(editor->date, "yyyy-MM-dd");
    gtk_entry_set_placeholder_text(editor->time, "HH:mm");
    auto const* seed = restore != nullptr ? restore : task;
    if (seed != nullptr) {
      gtk_editable_set_text(GTK_EDITABLE(editor->text), seed->text.c_str());
      if (seed->notes.has_value()) {
        gtk_editable_set_text(GTK_EDITABLE(editor->notes),
                              seed->notes->c_str());
      }
      if (seed->due_date.has_value()) {
        gtk_editable_set_text(GTK_EDITABLE(editor->date),
                              seed->due_date->c_str());
      }
      if (seed->due_time.has_value()) {
        gtk_editable_set_text(GTK_EDITABLE(editor->time),
                              seed->due_time->c_str());
      }
    }

    auto* grid = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_widget_set_margin_start(grid, 28);
    gtk_widget_set_margin_end(grid, 4);
    gtk_widget_set_margin_bottom(grid, 6);
    gtk_box_append(GTK_BOX(grid), editor_field_row(tr("labelTask").c_str(),
                                                   GTK_WIDGET(editor->text)));
    gtk_box_append(GTK_BOX(grid), editor_field_row(tr("labelNotes").c_str(),
                                                   GTK_WIDGET(editor->notes)));

    auto* date_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_box_append(GTK_BOX(date_row), GTK_WIDGET(editor->date));
    auto* calendar_button =
        gtk_button_new_from_icon_name("x-office-calendar-symbolic");
    gtk_widget_add_css_class(calendar_button, "flat");
    auto* date_popover = gtk_popover_new();
    auto* calendar = gtk_calendar_new();
    gtk_popover_set_child(GTK_POPOVER(date_popover), calendar);
    g_signal_connect(calendar, "day-selected",
                     G_CALLBACK(on_editor_calendar_day_selected), editor);
    g_signal_connect_swapped(
        calendar, "day-selected",
        G_CALLBACK(+[](GtkWidget* popover) { gtk_popover_popdown(
            GTK_POPOVER(popover)); }),
        date_popover);
    g_signal_connect_swapped(
        calendar_button, "clicked",
        G_CALLBACK(+[](GtkWidget* popover) { gtk_popover_popup(
            GTK_POPOVER(popover)); }),
        date_popover);
    gtk_box_append(GTK_BOX(date_row), calendar_button);
    gtk_box_append(GTK_BOX(grid),
                   editor_field_row(tr("labelDate").c_str(), date_row));
    gtk_box_append(GTK_BOX(grid), editor_field_row(tr("labelTime").c_str(),
                                                   GTK_WIDGET(editor->time)));

    auto* buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    auto* save = gtk_button_new_with_label(tr("dialogSave").c_str());
    gtk_widget_add_css_class(save, "suggested-action");
    g_signal_connect(save, "clicked", G_CALLBACK(on_editor_save_clicked),
                     editor);
    gtk_box_append(GTK_BOX(buttons), save);
    auto* clear = gtk_button_new_with_label(tr("dialogClear").c_str());
    g_signal_connect(clear, "clicked",
                     G_CALLBACK(on_editor_clear_due_clicked), editor);
    gtk_box_append(GTK_BOX(buttons), clear);
    gtk_box_append(GTK_BOX(grid), buttons);

    revealer = GTK_REVEALER(gtk_revealer_new());
    gtk_revealer_set_child(revealer, grid);
    g_object_set_data_full(G_OBJECT(row), "task-editor", editor,
                           +[](gpointer data) {
                             delete static_cast<TaskEditor*>(data);
                           });
    g_object_set_data(G_OBJECT(row), "task-editor-revealer", revealer);

    // Move the row content into a vertical box with the editor underneath.
    auto* current = gtk_list_box_row_get_child(row);
    auto* stack = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    g_object_ref(current);
    gtk_list_box_row_set_child(row, stack);
    gtk_box_append(GTK_BOX(stack), current);
    g_object_unref(current);
    gtk_box_append(GTK_BOX(stack), GTK_WIDGET(revealer));
  }
  gtk_revealer_set_reveal_child(revealer, expand);
  g_state.open_editor_id = expand ? id : -1;
  if (expand && focus_date) {
    auto* editor = static_cast<TaskEditor*>(
        g_object_get_data(G_OBJECT(row), "task-editor"));
    gtk_widget_grab_focus(GTK_WIDGET(editor->date));
  }
}

void toggle_task_editor(GtkListBoxRow* row, std::int64_t id, bool focus_date) {
  auto* revealer = GTK_REVEALER(
      g_object_get_data(G_OBJECT(row), "task-editor-revealer"));
  auto const expanded = revealer != nullptr &&
                        gtk_revealer_get_reveal_child(revealer);
  set_task_editor_expanded(row, id, !expanded, focus_date, nullptr);
}

// Find the visible row for a task id and expand its editor.
void open_task_editor(std::int64_t id, bool focus_date) {
  for (GtkWidget* child = gtk_widget_get_first_child(GTK_WIDGET(
           g_state.task_list));
       child != nullptr;
       child = gtk_widget_get_next_sibling(child)) {
    if (!GTK_IS_LIST_BOX_ROW(child)) continue;
    auto const row_id = static_cast<std::int64_t>(GPOINTER_TO_INT(
        g_object_get_data(G_OBJECT(child), "task-id")));
    if (row_id == id) {
      set_task_editor_expanded(GTK_LIST_BOX_ROW(child), id, true,
                               focus_date, nullptr);
      return;
    }
  }
}

void collapse_open_editor() {
  if (g_state.open_editor_id < 0) return;
  for (GtkWidget* child = gtk_widget_get_first_child(GTK_WIDGET(
           g_state.task_list));
       child != nullptr;
       child = gtk_widget_get_next_sibling(child)) {
    if (!GTK_IS_LIST_BOX_ROW(child)) continue;
    auto const row_id = static_cast<std::int64_t>(GPOINTER_TO_INT(
        g_object_get_data(G_OBJECT(child), "task-id")));
    if (row_id == g_state.open_editor_id) {
      set_task_editor_expanded(GTK_LIST_BOX_ROW(child), row_id, false,
                               false, nullptr);
      return;
    }
  }
  g_state.open_editor_id = -1;
}

void show_task_menu(GtkWidget* row, gdouble x, gdouble y, bool user_list) {
  auto* menu = g_menu_new();
  if (user_list) {
    auto const list_id = static_cast<std::int64_t>(GPOINTER_TO_INT(
        g_object_get_data(G_OBJECT(row), "list-id")));
    auto* section = g_menu_new();
    g_menu_append(section, tr("dialogEditList").c_str(),
                  ("win.list-edit::" + std::to_string(list_id)).c_str());
    g_menu_append(section, tr("listDelete").c_str(),
                  ("win.list-delete::" + std::to_string(list_id)).c_str());
    g_menu_append_section(menu, nullptr, G_MENU_MODEL(section));
    g_object_unref(section);
  } else {
    auto const task_id = static_cast<std::int64_t>(GPOINTER_TO_INT(
        g_object_get_data(G_OBJECT(row), "task-id")));
    auto* due_section = g_menu_new();
    g_menu_append(due_section, tr("navToday").c_str(),
                  ("win.task-due-today::" + std::to_string(task_id)).c_str());
    g_menu_append(
        due_section, tr("dateTomorrow").c_str(),
        ("win.task-due-tomorrow::" + std::to_string(task_id)).c_str());
    g_menu_append(
        due_section, tr("contextMenuCustomDate").c_str(),
        ("win.task-due-custom::" + std::to_string(task_id)).c_str());
    g_menu_append(
        due_section, tr("dialogClear").c_str(),
        ("win.task-due-clear::" + std::to_string(task_id)).c_str());
    g_menu_append_section(menu, nullptr, G_MENU_MODEL(due_section));
    g_object_unref(due_section);
    auto* task_section = g_menu_new();
    g_menu_append(task_section, tr("contextMenuDetails").c_str(),
                  ("win.task-edit::" + std::to_string(task_id)).c_str());
    g_menu_append(task_section, tr("taskDelete").c_str(),
                  ("win.task-delete::" + std::to_string(task_id)).c_str());
    g_menu_append_section(menu, nullptr, G_MENU_MODEL(task_section));
    g_object_unref(task_section);
  }

  auto* popover = gtk_popover_menu_new_from_model(G_MENU_MODEL(menu));
  g_object_unref(menu);
  gtk_widget_set_parent(popover, row);
  GdkRectangle point{static_cast<int>(x), static_cast<int>(y), 1, 1};
  gtk_popover_set_pointing_to(GTK_POPOVER(popover), &point);
  g_signal_connect(popover, "closed",
                   G_CALLBACK(+[](GtkPopover* popover, gpointer) {
                     gtk_widget_unparent(GTK_WIDGET(popover));
                   }),
                   nullptr);
  gtk_popover_popup(GTK_POPOVER(popover));
}

void on_row_gesture_pressed(GtkGestureClick* gesture, gint n_press,
                            gdouble x, gdouble y, gpointer user_data) {
  auto* widget =
      gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  auto* row = gtk_widget_get_ancestor(widget, GTK_TYPE_LIST_BOX_ROW);
  if (row == nullptr) return;
  auto const button =
      gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
  auto const is_user_list = user_data != nullptr;
  if (button == 3 && n_press == 1) {
    show_task_menu(row, x, y, is_user_list);
  } else if (button == 1 && n_press == 2) {
    if (is_user_list) {
      // Double-click on a list row jumps to the edit dialog (macOS M4).
      auto const id = static_cast<std::int64_t>(GPOINTER_TO_INT(
          g_object_get_data(G_OBJECT(row), "list-id")));
      auto* parameter = g_variant_new_string(std::to_string(id).c_str());
      g_action_group_activate_action(
          G_ACTION_GROUP(g_state.window), "list-edit", parameter);
    } else {
      auto const id = static_cast<std::int64_t>(GPOINTER_TO_INT(
          g_object_get_data(G_OBJECT(row), "task-id")));
      toggle_task_editor(GTK_LIST_BOX_ROW(row), id, false);
    }
  }
}

void attach_row_gestures(GtkWidget* row, bool user_list) {
  auto* gesture = gtk_gesture_click_new();
  gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture), 0);
  g_signal_connect(gesture, "pressed", G_CALLBACK(on_row_gesture_pressed),
                   user_list ? reinterpret_cast<gpointer>(1) : nullptr);
  gtk_widget_add_controller(row, GTK_EVENT_CONTROLLER(gesture));
}

GtkWidget* make_task_row(rivet_app::Task const& task) {
  auto* row = gtk_list_box_row_new();
  gtk_widget_set_tooltip_text(row, tr("tooltipDoubleClickEdit").c_str());

  auto* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);

  // Linux platform idiom (PRODUCT-SPEC §5): the stock CheckButton carries no
  // recolorable ring, so an 8px list-color dot precedes the row instead.
  auto const* list = find_by_id(g_state.lists, task.list_id);
  auto* row_dot = gtk_label_new("");
  gtk_widget_add_css_class(row_dot, "row-dot");
  gtk_widget_set_valign(row_dot, GTK_ALIGN_CENTER);
  {
    auto const hex = list != nullptr && list->color.has_value()
                         ? argb_to_hex(*list->color)
                         : std::string(g_state_palette->accent);
    auto* provider = gtk_css_provider_new();
    std::string const css =
        std::string(".row-dot { background: ") + hex + "; }";
    gtk_css_provider_load_from_string(provider, css.c_str());
    gtk_style_context_add_provider(gtk_widget_get_style_context(row_dot),
                                   GTK_STYLE_PROVIDER(provider),
                                   GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
  }
  gtk_box_append(GTK_BOX(box), row_dot);

  auto* check = gtk_check_button_new();
  gtk_check_button_set_active(GTK_CHECK_BUTTON(check), task.completed);
  gtk_widget_set_valign(check, GTK_ALIGN_CENTER);
  g_object_set_data(G_OBJECT(check), "task-id",
                    GINT_TO_POINTER(static_cast<gint>(task.id)));
  g_signal_connect(check, "toggled", G_CALLBACK(on_task_check_toggled),
                   nullptr);
  gtk_box_append(GTK_BOX(box), check);

  auto* content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  gtk_widget_set_valign(content, GTK_ALIGN_CENTER);
  gtk_widget_set_hexpand(content, TRUE);

  auto* text = gtk_label_new(task.text.c_str());
  gtk_label_set_ellipsize(GTK_LABEL(text), PANGO_ELLIPSIZE_END);
  gtk_label_set_xalign(GTK_LABEL(text), 0.0f);
  gtk_widget_add_css_class(text, "task-text");
  if (task.completed) {
    gtk_widget_add_css_class(text, "task-done");
  }
  gtk_box_append(GTK_BOX(content), text);

  // Meta line: owning list in multi-list views + due chip + notes preview.
  std::string meta;
  if (g_state.view != ViewKind::List && task.list_name.has_value()) {
    meta = *task.list_name;
  }
  auto const due = due_chip_text(task);
  if (!due.empty()) {
    if (!meta.empty()) meta += "  ·  ";
    meta += due;
  }
  if (task.notes.has_value() && !task.notes->empty()) {
    auto const first_line = task.notes->substr(0, task.notes->find('\n'));
    if (!first_line.empty()) {
      if (!meta.empty()) meta += "  ·  ";
      meta += first_line;
    }
  }
  if (!meta.empty()) {
    auto* meta_label = gtk_label_new(meta.c_str());
    gtk_label_set_xalign(GTK_LABEL(meta_label), 0.0f);
    gtk_widget_add_css_class(meta_label, "due-chip");
    if (task.due_date.has_value()) {
      gtk_widget_add_css_class(
          meta_label, due_color_class(*task.due_date, task.completed));
    } else {
      gtk_widget_add_css_class(meta_label, "meta-text");
    }
    gtk_box_append(GTK_BOX(content), meta_label);
  }
  gtk_box_append(GTK_BOX(box), content);

  gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
  g_object_set_data(G_OBJECT(row), "task-id",
                    GINT_TO_POINTER(static_cast<gint>(task.id)));
  attach_row_gestures(row, false);
  return row;
}

// ---------------------------------------------------------------------------
// Sidebar — smart-view chips (2×2) + user lists (color dot + emoji + name +
// pending count) + new-list button.
// ---------------------------------------------------------------------------

GtkWidget* make_section_caption(char const* text) {
  auto* label = gtk_label_new(text);
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_widget_add_css_class(label, "section-caption");
  gtk_widget_set_margin_start(label, 16);
  gtk_widget_set_margin_top(label, 8);
  gtk_widget_set_margin_bottom(label, 4);
  return label;
}

struct ChipSpec {
  ViewKind kind;
  char const* glyph;
  char const* key;
};

constexpr ChipSpec kChips[] = {
    {ViewKind::Today, "📅", "navToday"},
    {ViewKind::Planned, "🗓", "navPlanned"},
    {ViewKind::All, "🗂", "navAll"},
    {ViewKind::Completed, "✅", "navCompleted"},
};

void on_chip_clicked(GtkButton*, gpointer user_data) {
  auto const index = GPOINTER_TO_INT(user_data);
  set_view(kChips[index].kind);
}

// Shared smart-view switch (chips, keyboard accelerators). Switching views
// clears an active search — the term belongs to the view it was typed in.
void set_view(ViewKind kind) {
  if (!g_state.current_search.empty()) {
    gtk_editable_set_text(GTK_EDITABLE(g_state.search_box), "");
  }
  if (g_state.view == kind && g_state.view != ViewKind::List) return;
  g_state.view = kind;
  g_state.view_list_id = 0;
  g_state.suppress_selection = true;
  gtk_list_box_unselect_all(g_state.user_list);
  g_state.suppress_selection = false;
  rebuild_task_list();
  refresh_persistent_status();
  reload_snapshot();
}

void on_action_view_today(GSimpleAction*, GVariant*, gpointer) {
  set_view(ViewKind::Today);
}

void on_action_view_planned(GSimpleAction*, GVariant*, gpointer) {
  set_view(ViewKind::Planned);
}

void on_action_view_all(GSimpleAction*, GVariant*, gpointer) {
  set_view(ViewKind::All);
}

void on_action_view_completed(GSimpleAction*, GVariant*, gpointer) {
  set_view(ViewKind::Completed);
}

void on_action_new_task(GSimpleAction*, GVariant*, gpointer) {
  gtk_widget_grab_focus(GTK_WIDGET(g_state.quick_add));
}

void on_action_focus_search(GSimpleAction*, GVariant*, gpointer) {
  gtk_widget_grab_focus(GTK_WIDGET(g_state.search_box));
}

void on_action_toggle_completed(GSimpleAction*, GVariant*, gpointer) {
  gtk_toggle_button_set_active(g_state.show_completed_toggle,
                               !g_state.show_completed);
}

void on_sidebar_toggle_clicked(GtkButton* button, gpointer) {
  auto* sidebar = g_state.sidebar_widget;
  auto const visible = gtk_widget_get_visible(sidebar);
  gtk_widget_set_visible(sidebar, !visible);
  gtk_button_set_icon_name(
      button, visible ? "sidebar-show-symbolic" : "sidebar-hide-symbolic");
}

GtkWidget* make_chip(int index) {
  auto const& spec = kChips[index];
  auto* button = gtk_button_new();
  gtk_widget_add_css_class(button, "chip");
  auto* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
  gtk_widget_set_hexpand(box, TRUE);
  gtk_widget_set_valign(box, GTK_ALIGN_CENTER);
  auto* glyph = gtk_label_new(spec.glyph);
  // macOS M4: each chip's glyph carries a semantic color (today accent,
  // planned danger red, all/completed secondary); the fill stays neutral.
  static char const* const glyph_classes[] = {
      "chip-glyph-today", "chip-glyph-planned", "chip-glyph-all",
      "chip-glyph-completed"};
  gtk_widget_add_css_class(glyph, glyph_classes[index]);
  gtk_box_append(GTK_BOX(box), glyph);
  auto* label = gtk_label_new(tr(spec.key).c_str());
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_widget_set_hexpand(label, TRUE);
  gtk_box_append(GTK_BOX(box), label);
  auto* count = gtk_label_new("0");
  gtk_widget_add_css_class(count, "count-badge");
  gtk_box_append(GTK_BOX(box), count);
  g_object_set_data(G_OBJECT(button), "chip-count", count);
  g_object_set_data(G_OBJECT(button), "chip-label", label);
  gtk_widget_set_hexpand(button, TRUE);
  gtk_button_set_child(GTK_BUTTON(button), box);
  g_signal_connect(button, "clicked", G_CALLBACK(on_chip_clicked),
                   GINT_TO_POINTER(index));
  return button;
}

GtkWidget* make_user_list_row(rivet_app::TodoList const& list) {
  auto* row = gtk_list_box_row_new();
  auto* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);

  auto* dot = gtk_label_new(list.icon.value_or(" ").c_str());
  gtk_widget_set_valign(dot, GTK_ALIGN_CENTER);
  if (list.color.has_value()) {
    auto const hex = argb_to_hex(*list.color);
    auto* provider = gtk_css_provider_new();
    std::string const css = std::string(
        ".list-dot { color: transparent; background: " + hex + "; }");
    gtk_css_provider_load_from_string(provider, css.c_str());
    gtk_style_context_add_provider(gtk_widget_get_style_context(dot),
                                   GTK_STYLE_PROVIDER(provider),
                                   GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
    // Emoji overlay on the color dot (DESIGN-TOKENS: 20px dot, 11px emoji).
    auto* emoji = gtk_label_new(list.icon.value_or("•").c_str());
    gtk_widget_add_css_class(emoji, "list-dot-emoji");
    auto* overlay = gtk_overlay_new();
    gtk_overlay_set_child(GTK_OVERLAY(overlay), dot);
    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), emoji);
    gtk_box_append(GTK_BOX(box), overlay);
  } else {
    gtk_widget_add_css_class(dot, "dot-neutral");
    gtk_box_append(GTK_BOX(box), dot);
  }

  auto* text = gtk_label_new(list.name.c_str());
  gtk_label_set_ellipsize(GTK_LABEL(text), PANGO_ELLIPSIZE_END);
  gtk_label_set_xalign(GTK_LABEL(text), 0.0f);
  gtk_widget_set_hexpand(text, TRUE);
  gtk_box_append(GTK_BOX(box), text);

  auto* badge = gtk_label_new(std::to_string(list.pending_count).c_str());
  gtk_widget_add_css_class(badge, "count-badge");
  gtk_box_append(GTK_BOX(box), badge);

  gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
  g_object_set_data(G_OBJECT(row), "list-id",
                    GINT_TO_POINTER(static_cast<gint>(list.id)));
  attach_row_gestures(row, true);
  return row;
}

void rebuild_sidebar() {
  g_state.suppress_selection = true;

  std::int64_t const counts[4] = {
      g_state.current_counts.today, g_state.current_counts.planned,
      g_state.current_counts.all, g_state.current_counts.completed};
  for (int i = 0; i < 4; ++i) {
    auto* count = GTK_LABEL(
        g_object_get_data(G_OBJECT(g_state.chips[i]), "chip-count"));
    gtk_label_set_text(count, std::to_string(counts[i]).c_str());
    auto const active =
        g_state.view != ViewKind::List && g_state.view == kChips[i].kind;
    auto* widget = GTK_WIDGET(g_state.chips[i]);
    gtk_widget_remove_css_class(widget, "chip");
    gtk_widget_remove_css_class(widget, "chip-selected");
    gtk_widget_add_css_class(widget, active ? "chip-selected" : "chip");
  }

  gtk_label_set_text(g_state.my_lists_caption,
                     tr("sectionMyLists").c_str());
  gtk_list_box_remove_all(g_state.user_list);
  for (auto const& list : g_state.lists) {
    auto* row = make_user_list_row(list);
    gtk_list_box_insert(g_state.user_list, row, -1);
    if (g_state.view == ViewKind::List && g_state.view_list_id == list.id) {
      gtk_list_box_select_row(g_state.user_list, GTK_LIST_BOX_ROW(row));
    }
  }

  g_state.suppress_selection = false;
}

void refresh_pane_header() {
  gtk_label_set_text(g_state.pane_title, view_title().c_str());
  gtk_label_set_text(g_state.pane_subtitle, view_subtitle().c_str());
}

void rebuild_task_list() {
  refresh_pane_header();

  // Carry an open in-place editor across the rebuild: snapshot its
  // in-progress field values, then re-open it on the fresh row (the 2 s
  // poll must not destroy what the user is typing).
  rivet_app::Task editor_snapshot{};
  bool editor_carry = false;
  if (g_state.open_editor_id >= 0) {
    for (GtkWidget* child = gtk_widget_get_first_child(GTK_WIDGET(
             g_state.task_list));
         child != nullptr;
         child = gtk_widget_get_next_sibling(child)) {
      if (!GTK_IS_LIST_BOX_ROW(child)) continue;
      auto const row_id = static_cast<std::int64_t>(GPOINTER_TO_INT(
          g_object_get_data(G_OBJECT(child), "task-id")));
      if (row_id != g_state.open_editor_id) continue;
      auto* editor = static_cast<TaskEditor*>(
          g_object_get_data(G_OBJECT(child), "task-editor"));
      if (editor != nullptr) {
        editor_snapshot.id = row_id;
        editor_snapshot.text =
            gtk_editable_get_text(GTK_EDITABLE(editor->text));
        auto const notes =
            std::string(gtk_editable_get_text(GTK_EDITABLE(editor->notes)));
        editor_snapshot.notes =
            notes.empty() ? std::nullopt : std::optional<std::string>(notes);
        auto const date =
            std::string(gtk_editable_get_text(GTK_EDITABLE(editor->date)));
        editor_snapshot.due_date =
            date.empty() ? std::nullopt : std::optional<std::string>(date);
        auto const time =
            std::string(gtk_editable_get_text(GTK_EDITABLE(editor->time)));
        editor_snapshot.due_time =
            time.empty() ? std::nullopt : std::optional<std::string>(time);
        editor_carry = true;
      }
      break;
    }
  }

  gtk_list_box_remove_all(g_state.task_list);

  // Empty states (PRODUCT-SPEC §4): disconnected → hint; connected and
  // empty → checkmark.
  char const* page = "list";
  if (g_state.api == nullptr) page = "empty";
  if (g_state.tasks.empty()) page = "empty";
  gtk_stack_set_visible_child_name(g_state.list_stack, page);
  if (page == "empty") {
    gtk_label_set_text(g_state.empty_icon,
                       g_state.api == nullptr ? "📂" : "✓");
    gtk_label_set_text(
        g_state.empty_text,
        g_state.api == nullptr ? tr("taskListEmptyHint").c_str()
                               : tr("taskListEmpty").c_str());
    gtk_entry_set_placeholder_text(
        g_state.quick_add,
        (g_state.api == nullptr ? tr("taskListInputHintNoDb")
                                : tr("taskListInputHint"))
            .c_str());
    g_state.open_editor_id = -1;
    return;
  }

  auto insert_row = [&](rivet_app::Task const& task) {
    auto* row = make_task_row(task);
    gtk_list_box_insert(g_state.task_list, row, -1);
    if (editor_carry && task.id == g_state.open_editor_id) {
      set_task_editor_expanded(GTK_LIST_BOX_ROW(row), task.id, true,
                               false, &editor_snapshot);
    }
  };

  // macOS M4 contract: incomplete rows first, then a collapsible completed
  // section (chevron + count) — no date grouping.
  std::int64_t completed_visible = 0;
  for (auto const& task : g_state.tasks) {
    if (!task.completed) {
      insert_row(task);
    } else {
      ++completed_visible;
    }
  }
  if (completed_visible > 0) {
    auto* header = gtk_list_box_row_new();
    gtk_list_box_row_set_selectable(GTK_LIST_BOX_ROW(header), FALSE);
    gtk_widget_set_focusable(header, FALSE);
    auto* toggle = gtk_button_new();
    gtk_widget_add_css_class(toggle, "flat");
    auto* toggle_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    auto* chevron = gtk_label_new(g_state.completed_section_expanded ? "▾"
                                                                     : "▸");
    gtk_widget_add_css_class(chevron, "section-header");
    gtk_box_append(GTK_BOX(toggle_box), chevron);
    auto* count_label = gtk_label_new(
        format_positional(tr("subtitleCompleted"),
                          std::to_string(completed_visible))
            .c_str());
    gtk_widget_add_css_class(count_label, "section-header");
    gtk_box_append(GTK_BOX(toggle_box), count_label);
    gtk_button_set_child(GTK_BUTTON(toggle), toggle_box);
    g_signal_connect(toggle, "clicked",
                     G_CALLBACK(+[](GtkButton*, gpointer) {
                       g_state.completed_section_expanded =
                           !g_state.completed_section_expanded;
                       rebuild_task_list();
                     }),
                     nullptr);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(header), toggle);
    gtk_list_box_insert(g_state.task_list, header, -1);
    if (g_state.completed_section_expanded) {
      for (auto const& task : g_state.tasks) {
        if (task.completed) {
          insert_row(task);
        }
      }
    }
  }

  // The edited task left the view (completed, deleted, filtered): drop it.
  if (editor_carry &&
      find_by_id(g_state.tasks, g_state.open_editor_id) == nullptr) {
    g_state.open_editor_id = -1;
  }
}

// ---------------------------------------------------------------------------
// Undo banner — task deletion is a 6-second undoable operation (macOS M4);
// undo re-adds the task with its original fields (new id).
// ---------------------------------------------------------------------------

gpointer banner_task() {
  return g_object_get_data(G_OBJECT(g_state.banner_box), "banner-task");
}

guint banner_timeout() {
  return GPOINTER_TO_UINT(
      g_object_get_data(G_OBJECT(g_state.banner_box), "banner-timeout"));
}

void clear_banner(guint timeout) {
  if (timeout != 0) {
    g_source_remove(timeout);
  }
  g_object_set_data(G_OBJECT(g_state.banner_box), "banner-task", nullptr);
  g_object_set_data(G_OBJECT(g_state.banner_box), "banner-timeout",
                    GUINT_TO_POINTER(0));
  gtk_revealer_set_reveal_child(
      GTK_REVEALER(g_object_get_data(G_OBJECT(g_state.banner_box),
                                     "banner-revealer")),
      FALSE);
}

int on_undo_timeout(gpointer) {
  auto* task = static_cast<rivet_app::Task*>(banner_task());
  delete task;
  clear_banner(0);
  return G_SOURCE_REMOVE;
}

void show_undo_banner(rivet_app::Task const& deleted) {
  auto const previous_task = banner_task();
  auto const previous_timeout = banner_timeout();
  if (previous_task != nullptr) {
    delete static_cast<rivet_app::Task*>(previous_task);
  }
  if (previous_timeout != 0) {
    g_source_remove(previous_timeout);  // the old banner never fires again
  }

  auto* revealer = GTK_REVEALER(
      g_object_get_data(G_OBJECT(g_state.banner_box), "banner-revealer"));
  auto* card = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
  gtk_widget_add_css_class(card, "banner-card");
  gtk_widget_set_margin_start(card, 12);
  gtk_widget_set_margin_end(card, 12);
  gtk_widget_set_margin_top(card, 8);
  gtk_widget_set_margin_bottom(card, 8);
  auto* message =
      gtk_label_new(format_positional(tr("bannerTaskDeleted"), deleted.text)
                        .c_str());
  gtk_label_set_ellipsize(GTK_LABEL(message), PANGO_ELLIPSIZE_END);
  gtk_widget_set_hexpand(message, TRUE);
  gtk_box_append(GTK_BOX(card), message);
  auto* undo = gtk_button_new_with_label(tr("bannerUndo").c_str());
  gtk_widget_add_css_class(undo, "flat");
  gtk_widget_add_css_class(undo, "accent-toggle");
  gtk_box_append(GTK_BOX(card), undo);
  auto* close = gtk_button_new_from_icon_name("window-close-symbolic");
  gtk_widget_add_css_class(close, "flat");
  gtk_box_append(GTK_BOX(card), close);

  auto* task_copy = new rivet_app::Task(deleted);
  g_signal_connect(
      undo, "clicked",
      G_CALLBACK(+[](GtkButton*, gpointer user_data) {
        auto* task = static_cast<rivet_app::Task*>(user_data);
        auto const timeout = banner_timeout();
        add_task_full(*task);
        delete task;
        clear_banner(timeout);
        flash_status(tr("statusTaskAdded"));
      }),
      task_copy);
  g_signal_connect(
      close, "clicked",
      G_CALLBACK(+[](GtkButton*, gpointer user_data) {
        auto* task = static_cast<rivet_app::Task*>(user_data);
        auto const timeout = banner_timeout();
        delete task;
        clear_banner(timeout);
      }),
      task_copy);
  gtk_revealer_set_child(revealer, card);
  gtk_revealer_set_reveal_child(revealer, TRUE);

  g_object_set_data(G_OBJECT(g_state.banner_box), "banner-task", task_copy);
  auto const timeout = g_timeout_add_seconds(6, on_undo_timeout, task_copy);
  g_object_set_data(G_OBJECT(g_state.banner_box), "banner-timeout",
                    GUINT_TO_POINTER(timeout));
}

// ---------------------------------------------------------------------------
// Window actions + menu bar
// ---------------------------------------------------------------------------

std::int64_t action_id(GVariant* parameter) {
  auto const id = static_cast<std::int64_t>(
      g_ascii_strtoll(g_variant_get_string(parameter, nullptr), nullptr, 10));
  g_variant_unref(parameter);
  return id;
}

void on_action_task_due_today(GSimpleAction*, GVariant* parameter, gpointer) {
  auto const id = action_id(parameter);
  if (auto const* task = find_by_id(g_state.tasks, id)) {
    auto updated = *task;
    updated.due_date = date_string(0);
    save_task_edits(updated);
  }
}

void on_action_task_due_tomorrow(GSimpleAction*, GVariant* parameter,
                                 gpointer) {
  auto const id = action_id(parameter);
  if (auto const* task = find_by_id(g_state.tasks, id)) {
    auto updated = *task;
    updated.due_date = date_string(1);
    save_task_edits(updated);
  }
}

void on_action_task_due_clear(GSimpleAction*, GVariant* parameter, gpointer) {
  auto const id = action_id(parameter);
  if (auto const* task = find_by_id(g_state.tasks, id)) {
    auto updated = *task;
    updated.due_date = std::nullopt;
    updated.due_time = std::nullopt;
    save_task_edits(updated);
  }
}

void on_action_task_due_custom(GSimpleAction*, GVariant* parameter,
                               gpointer) {
  open_task_editor(action_id(parameter), true);
}

void on_action_task_edit(GSimpleAction*, GVariant* parameter, gpointer) {
  open_task_editor(action_id(parameter), false);
}

void on_action_task_delete(GSimpleAction*, GVariant* parameter, gpointer) {
  auto const id = action_id(parameter);
  auto const* task = find_by_id(g_state.tasks, id);
  if (task == nullptr) return;
  show_undo_banner(*task);
  flash_status(tr("statusTaskDeleted"));
  delete_task_by_id(id);
}

void on_action_list_delete(GSimpleAction*, GVariant* parameter, gpointer) {
  auto const id = action_id(parameter);
  confirm_dialog(tr("listDeleteConfirm").c_str(),
                 tr("listDeleteConfirmContent").c_str(),
                 [id] { delete_list_by_id(id); });
}

void on_action_list_edit(GSimpleAction*, GVariant* parameter, gpointer) {
  auto const id = action_id(parameter);
  auto const* list = find_by_id(g_state.lists, id);
  if (list == nullptr) return;
  rivet_app::TodoList const snapshot = *list;
  open_list_editor(
      tr("dialogEditList").c_str(), &snapshot,
      [id](std::string const& name, std::optional<std::string> icon,
           std::optional<std::int64_t> color) {
        auto const* stored = find_by_id(g_state.lists, id);
        if (stored == nullptr) return;
        auto updated = *stored;
        updated.name = name;
        updated.icon = icon;
        updated.color = color;
        update_list_full(updated);
      });
}

void on_menu_new_database(GSimpleAction*, GVariant*, gpointer) {
  prompt_dialog(tr("menuNewDatabase").c_str(),
                tr("dialogInputListName").c_str(), "",
                [](std::string const& path) {
                  if (!path.empty()) open_database_at(path);
                });
}

void on_menu_open_database(GSimpleAction*, GVariant*, gpointer) {
  auto* chooser = gtk_file_chooser_native_new(
      tr("menuOpenDatabase").c_str(), g_state.window,
      GTK_FILE_CHOOSER_ACTION_OPEN, tr("dialogConfirm").c_str(),
      tr("dialogCancel").c_str());
  auto* filter = gtk_file_filter_new();
  gtk_file_filter_add_pattern(filter, "*.db");
  gtk_file_filter_add_pattern(filter, "*.sqlite");
  gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(chooser), filter);
  g_object_unref(filter);
  g_signal_connect(
      chooser, "response",
      G_CALLBACK(+[](GtkNativeDialog* native, gint response, gpointer) {
        if (response == GTK_RESPONSE_ACCEPT) {
          auto* file = gtk_file_chooser_get_file(GTK_FILE_CHOOSER(native));
          if (file != nullptr) {
            gchar* path = g_file_get_path(file);
            if (path != nullptr) {
              open_database_at(path);
              g_free(path);
            }
            g_object_unref(file);
          }
        }
        g_object_unref(native);
      }),
      nullptr);
  gtk_native_dialog_show(GTK_NATIVE_DIALOG(chooser));
}

void on_menu_close_database(GSimpleAction*, GVariant*, gpointer) {
  if (g_state.api == nullptr) return;
  g_state.api->close_database_async([](rivet_app::Result<void> result) {
    on_result(std::move(result), [] {
      g_state.lists.clear();
      g_state.tasks.clear();
      g_state.current_counts = {};
      g_state.view = ViewKind::Today;
      g_state.view_list_id = 0;
      rebuild_sidebar();
      rebuild_task_list();
      refresh_persistent_status();
      set_status(tr("statusDatabaseClosed").c_str());
    });
  });
}

void on_menu_exit(GSimpleAction*, GVariant*, gpointer) {
  gtk_window_destroy(g_state.window);
}

void on_menu_lang_zh(GSimpleAction*, GVariant*, gpointer) {
  g_state.language = "zh";
  g_active_lang = 0;
  apply_language();
  save_setting("language", "zh");
}

void on_menu_lang_en(GSimpleAction*, GVariant*, gpointer) {
  g_state.language = "en";
  g_active_lang = 1;
  apply_language();
  save_setting("language", "en");
}

void on_menu_theme_system(GSimpleAction*, GVariant*, gpointer) {
  apply_theme("system");
  save_setting("theme", "system");
}

void on_menu_theme_light(GSimpleAction*, GVariant*, gpointer) {
  apply_theme("light");
  save_setting("theme", "light");
}

void on_menu_theme_dark(GSimpleAction*, GVariant*, gpointer) {
  apply_theme("dark");
  save_setting("theme", "dark");
}

void on_menu_about(GSimpleAction*, GVariant*, gpointer) {
  show_about_dialog();
}

void add_window_action(GtkApplicationWindow* window, char const* name,
                       void (*handler)(GSimpleAction*, GVariant*, gpointer),
                       bool parameterized) {
  auto* action = g_simple_action_new(
      name, parameterized ? G_VARIANT_TYPE_STRING : nullptr);
  g_signal_connect(action, "activate", G_CALLBACK(handler), nullptr);
  g_action_map_add_action(G_ACTION_MAP(window), G_ACTION(action));
  g_object_unref(action);
}

void build_menubar() {
  // Rebuild from scratch so a language switch retranslates every label.
  for (GtkWidget* child = gtk_widget_get_first_child(
           GTK_WIDGET(g_state.menubar_box));
       child != nullptr;) {
    GtkWidget* next = gtk_widget_get_next_sibling(child);
    gtk_box_remove(g_state.menubar_box, child);
    child = next;
  }
  auto* menu = g_menu_new();
  auto* file_menu = g_menu_new();
  g_menu_append(file_menu, tr("menuNewDatabase").c_str(),
                "win.new-database");
  g_menu_append(file_menu, tr("menuOpenDatabase").c_str(),
                "win.open-database");
  g_menu_append(file_menu, tr("menuCloseDatabase").c_str(),
                "win.close-database");
  g_menu_append(file_menu, tr("menuExit").c_str(), "win.exit");
  g_menu_append_submenu(menu, tr("menuFile").c_str(),
                        G_MENU_MODEL(file_menu));
  g_object_unref(file_menu);

  auto* settings_menu = g_menu_new();
  auto* lang_section = g_menu_new();
  g_menu_append(lang_section, tr("menuLangZh").c_str(), "win.lang-zh");
  g_menu_append(lang_section, tr("menuLangEn").c_str(), "win.lang-en");
  g_menu_append_section(settings_menu, nullptr, G_MENU_MODEL(lang_section));
  g_object_unref(lang_section);
  auto* theme_section = g_menu_new();
  g_menu_append(theme_section, tr("themeFollowSystem").c_str(),
                "win.theme-system");
  g_menu_append(theme_section, tr("themeLight").c_str(), "win.theme-light");
  g_menu_append(theme_section, tr("themeDark").c_str(), "win.theme-dark");
  g_menu_append_section(settings_menu, nullptr, G_MENU_MODEL(theme_section));
  g_object_unref(theme_section);
  g_menu_append_submenu(menu, tr("menuSettings").c_str(),
                        G_MENU_MODEL(settings_menu));
  g_object_unref(settings_menu);

  auto* help_menu = g_menu_new();
  g_menu_append(help_menu, tr("menuAbout").c_str(), "win.about");
  g_menu_append_submenu(menu, tr("menuHelp").c_str(), G_MENU_MODEL(help_menu));
  g_object_unref(help_menu);

  gtk_box_append(g_state.menubar_box,
                 gtk_popover_menu_bar_new_from_model(G_MENU_MODEL(menu)));
  g_object_unref(menu);
}

void apply_language() {
  g_active_lang = g_state.language == "en" ? 1 : 0;
  build_menubar();
  gtk_label_set_text(g_state.my_lists_caption,
                     tr("sectionMyLists").c_str());
  gtk_entry_set_placeholder_text(GTK_ENTRY(g_state.search_box),
                                 tr("searchHint").c_str());
  gtk_entry_set_placeholder_text(g_state.quick_add,
                                 tr("taskListInputHint").c_str());
  gtk_button_set_label(
      GTK_BUTTON(g_state.show_completed_toggle),
      (g_state.show_completed ? tr("hideCompletedToggle")
                              : tr("showCompletedToggle"))
          .c_str());
  for (int i = 0; i < 4; ++i) {
    auto* label = GTK_LABEL(
        g_object_get_data(G_OBJECT(g_state.chips[i]), "chip-label"));
    gtk_label_set_text(label, tr(kChips[i].key).c_str());
  }
  gtk_widget_set_tooltip_text(
      GTK_WIDGET(g_state.sidebar_toggle),
      (gtk_widget_get_visible(g_state.sidebar_widget)
           ? tr("sidebarHide")
           : tr("sidebarShow"))
          .c_str());
  rebuild_sidebar();
  rebuild_task_list();
  refresh_persistent_status();
}

// ---------------------------------------------------------------------------
// Sidebar / pane handlers
// ---------------------------------------------------------------------------

void on_user_row_selected(GtkListBox*, GtkListBoxRow* row, gpointer) {
  if (g_state.suppress_selection || row == nullptr) return;
  if (!g_state.current_search.empty()) {
    gtk_editable_set_text(GTK_EDITABLE(g_state.search_box), "");
  }
  auto const id = static_cast<std::int64_t>(GPOINTER_TO_INT(
      g_object_get_data(G_OBJECT(row), "list-id")));
  g_state.view = ViewKind::List;
  g_state.view_list_id = id;
  if (g_state.settings.last_selected_list_id != id) {
    g_state.settings.last_selected_list_id = id;
    save_setting("last-selected-list-id", std::to_string(id));
  }
  rebuild_task_list();
  refresh_persistent_status();
  reload_snapshot();
}

void on_new_list_clicked(GtkButton*, gpointer) {
  open_list_editor(
      tr("dialogCreateList").c_str(), nullptr,
      [](std::string const& name, std::optional<std::string> icon,
         std::optional<std::int64_t> color) {
        create_list_full(name, icon, color);
      });
}

void on_show_completed_toggled(GtkToggleButton* toggle, gpointer) {
  g_state.show_completed = gtk_toggle_button_get_active(toggle);
  gtk_button_set_label(
      GTK_BUTTON(toggle),
      (g_state.show_completed ? tr("hideCompletedToggle")
                              : tr("showCompletedToggle"))
          .c_str());
  reload_snapshot();
}

void on_quick_add_changed(GtkEditable* editable, gpointer) {
  auto const text =
      std::string(gtk_editable_get_text(editable));
  auto const sequence = ++g_state.preview_sequence;
  gtk_widget_set_opacity(GTK_WIDGET(g_state.quick_plus),
                         text.empty() ? 0.45 : 1.0);
  if (text.empty() || g_state.api == nullptr) {
    gtk_label_set_text(g_state.quick_add_preview, "");
    gtk_widget_set_visible(GTK_WIDGET(g_state.quick_add_preview), FALSE);
    return;
  }
  // One quick-add grammar on every platform: the backend splits text + due
  // (parse_quick_add); this host only previews the result.
  g_state.api->parse_quick_add_async(
      text,
      [sequence](rivet_app::Result<rivet_app::QuickAddParse> result) {
        on_result(
            std::move(result),
            [sequence](rivet_app::QuickAddParse const& parse) {
              if (sequence != g_state.preview_sequence) return;  // stale
              std::string preview;
              if (parse.due_date.has_value()) {
                preview = "📅 " + *parse.due_date;
                if (parse.due_time.has_value()) {
                  preview += " " + *parse.due_time;
                }
              }
              gtk_label_set_text(g_state.quick_add_preview, preview.c_str());
              gtk_widget_set_visible(GTK_WIDGET(g_state.quick_add_preview),
                                     !preview.empty());
            });
      });
}

void on_quick_add_activate(GtkEntry* entry, gpointer);
void on_quick_plus_clicked(GtkButton*, gpointer) {
  on_quick_add_activate(g_state.quick_add, nullptr);
}

// Quick-add target list: the selected list, else the first list
// (PRODUCT-SPEC §4); none → taskCreateListFirst error.
std::optional<std::int64_t> quick_add_target_list() {
  if (g_state.view == ViewKind::List) return g_state.view_list_id;
  if (!g_state.lists.empty()) return g_state.lists.front().id;
  return std::nullopt;
}

void on_quick_add_activate(GtkEntry* entry, gpointer) {
  auto const text = std::string(gtk_editable_get_text(GTK_EDITABLE(entry)));
  if (text.empty() || g_state.api == nullptr) return;
  auto const target = quick_add_target_list();
  if (!target.has_value()) {
    flash_status(tr("taskCreateListFirst"));
    return;
  }
  gtk_editable_set_text(GTK_EDITABLE(entry), "");
  gtk_label_set_text(g_state.quick_add_preview, "");
  // One quick-add grammar on every platform: the backend splits text + due
  // (parse_quick_add); this host only forwards the result.
  g_state.api->parse_quick_add_async(
      text, [target](rivet_app::Result<rivet_app::QuickAddParse> result) {
        on_result(
            std::move(result),
            [target](rivet_app::QuickAddParse const& parse) {
              rivet_app::Task seed{};
              seed.text = parse.text;
              seed.list_id = *target;
              seed.due_date = parse.due_date;
              seed.due_time = parse.due_time;
              add_task_full(seed);
              flash_status(tr("statusTaskAdded"));
            });
      });
}

void on_search_changed(GtkSearchEntry* entry, gpointer) {
  auto const keyword =
      std::string(gtk_editable_get_text(GTK_EDITABLE(entry)));
  if (keyword.empty()) {
    g_state.current_search.clear();
    rebuild_task_list();
    return;
  }
  g_state.current_search = keyword;
  // Search term takes over the pane title (PRODUCT-SPEC §4).
  gtk_label_set_text(
      g_state.pane_title,
      (tr("searchHint") + ": " + keyword).c_str());
  run_search(keyword);
}

void on_search_stopped(GtkSearchEntry* entry, gpointer) {
  gtk_editable_set_text(GTK_EDITABLE(entry), "");
}

// Esc: collapse the open editor first, else clear an active search —
// the Things escape ladder.
gboolean on_window_key_pressed(GtkEventControllerKey*, guint keyval,
                               guint, GdkModifierType, gpointer) {
  if (keyval != GDK_KEY_Escape) return FALSE;
  if (g_state.open_editor_id >= 0) {
    collapse_open_editor();
    return TRUE;
  }
  if (!g_state.current_search.empty()) {
    gtk_editable_set_text(GTK_EDITABLE(g_state.search_box), "");
    return TRUE;
  }
  return FALSE;
}

// ---------------------------------------------------------------------------
// Data flow
// ---------------------------------------------------------------------------

void open_database_at(std::string const& path) {
  if (g_state.api == nullptr || path.empty()) return;
  g_state.api->open_database_async(
      path, [path](rivet_app::Result<rivet_app::Snapshot> result) {
        on_result(std::move(result),
                  [path](rivet_app::Snapshot const& snapshot) {
                    g_state.current_counts = snapshot.counts;
                    g_state.lists = snapshot.lists;
                    g_state.tasks = snapshot.tasks;
                    // Restore the last-selected list when it still exists;
                    // stale settings fall back to the All view (macOS M4).
                    auto const restored =
                        g_state.settings.last_selected_list_id;
                    if (restored > 0 &&
                        find_by_id(g_state.lists, restored) != nullptr) {
                      g_state.view = ViewKind::List;
                      g_state.view_list_id = restored;
                    } else {
                      g_state.view = ViewKind::All;
                      g_state.view_list_id = 0;
                    }
                    rebuild_sidebar();
                    rebuild_task_list();
                    refresh_persistent_status();
                    // Reminders: a different database resets the per-session
                    // dedupe set; every open runs the startup check.
                    if (g_state.notified_db_path != path) {
                      g_state.notified_tasks.clear();
                      g_state.notified_db_path = path;
                    }
                    check_reminders(true);
                  });
      });
}

void open_default_database() {
  if (g_state.api == nullptr) return;
  g_state.api->default_database_async(
      [](rivet_app::Result<std::string> result) {
        on_result(std::move(result), [](std::string const& path) {
          g_state.settings.database_path = path;
          open_database_at(path);
        });
      });
}

int on_poll_timer(gpointer) {
  reload_snapshot();
  return G_SOURCE_CONTINUE;
}

void subscribe_to_events() {
  // The backend publishes `changed` after every mutation (including ones
  // made through the shared CLI). Reload the visible view.
  g_state.backend->set_event_handler(
      [](std::string const& name, rivet::Value const&) {
        if (name != "changed") return;
        dispatch_ui([] { reload_snapshot(); });
      });
}

// ---------------------------------------------------------------------------
// Startup (same contract as the Rivet template)
// ---------------------------------------------------------------------------

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
    set_status_error("Backend error: " + error);
    return G_SOURCE_REMOVE;
  }
  if (backend == nullptr) {
    set_status_error("Backend error: startup completed without a backend");
    return G_SOURCE_REMOVE;
  }

  g_state.backend = std::move(backend);
  g_state.api = std::make_unique<rivet_app::API>(*g_state.backend);
  subscribe_to_events();

  // CLI and GUI share the database; cross-process writes cannot emit
  // `changed`, so poll the snapshot instead.
  g_timeout_add_seconds(2, on_poll_timer, nullptr);
  // Reminders: one check at startup (after the DB opens) + every 60 s.
  g_timeout_add_seconds(60, on_reminder_timer, nullptr);

  g_state.api->get_settings_async(
      [](rivet_app::Result<rivet_app::Settings> result) {
        on_result(
            std::move(result), [](rivet_app::Settings const& settings) {
              g_state.settings = settings;
              g_state.language = settings.language == "en" ? "en" : "zh";
              apply_theme(settings.theme.empty() ? "system"
                                                 : settings.theme);
              apply_language();
              open_default_database();
            });
      });
  return G_SOURCE_REMOVE;
}

void start_backend() {
  auto layout = discover_runtime_layout();
  if (!layout.has_value()) {
    set_status(
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

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

void on_activate(GtkApplication* app, gpointer) {
  if (g_state.window != nullptr) {
    gtk_window_present(g_state.window);
    return;
  }

  auto* window = gtk_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(window), "Taskly");
  gtk_window_set_default_size(GTK_WINDOW(window), 1000, 680);
  gtk_widget_set_size_request(window, 760, 520);

  load_i18n(executable_path().parent_path());

  auto* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  auto* menubar_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_box_append(GTK_BOX(root), menubar_box);

  // Sidebar is user-resizable: 200–420 px via the paned handle (PRODUCT-SPEC
  // §2); the position is clamped while dragging.
  auto* body = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_widget_set_vexpand(body, TRUE);
  g_signal_connect(body, "notify::position",
                   G_CALLBACK(+[](GObject* obj, gpointer) {
                     auto* paned = GTK_PANED(obj);
                     auto const pos = gtk_paned_get_position(paned);
                     if (pos > 420) {
                       gtk_paned_set_position(paned, 420);
                     } else if (pos < 200) {
                       gtk_paned_set_position(paned, 200);
                     }
                   }),
                   nullptr);

  // Sidebar: smart-view chips (2×2) + my lists + new-list button.
  auto* sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_add_css_class(sidebar, "taskly-sidebar");
  gtk_widget_set_size_request(sidebar, 200, -1);
  g_state.sidebar_widget = sidebar;

  auto* chip_grid = gtk_grid_new();
  gtk_grid_set_row_spacing(GTK_GRID(chip_grid), 8);
  gtk_grid_set_column_spacing(GTK_GRID(chip_grid), 8);
  gtk_widget_set_margin_top(chip_grid, 12);
  gtk_widget_set_margin_start(chip_grid, 12);
  gtk_widget_set_margin_end(chip_grid, 12);
  for (int i = 0; i < 4; ++i) {
    g_state.chips[i] = make_chip(i);
    gtk_grid_attach(GTK_GRID(chip_grid), g_state.chips[i], i % 2, i / 2, 1,
                    1);
  }
  gtk_box_append(GTK_BOX(sidebar), chip_grid);

  // My Lists header row: caption + plus button (macOS M4 puts the add
  // action in the section header, not at the sidebar's bottom).
  auto* my_lists_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  auto* my_lists_caption = make_section_caption("");
  gtk_widget_set_hexpand(my_lists_caption, TRUE);
  gtk_widget_set_margin_top(my_lists_caption, 12);
  gtk_box_append(GTK_BOX(my_lists_row), my_lists_caption);
  auto* new_list_button = gtk_button_new_from_icon_name("list-add-symbolic");
  gtk_widget_add_css_class(new_list_button, "flat");
  gtk_widget_add_css_class(new_list_button, "accent-toggle");
  gtk_widget_set_valign(new_list_button, GTK_ALIGN_CENTER);
  g_signal_connect(new_list_button, "clicked",
                   G_CALLBACK(on_new_list_clicked), nullptr);
  gtk_box_append(GTK_BOX(my_lists_row), new_list_button);
  gtk_box_append(GTK_BOX(sidebar), my_lists_row);

  auto* lists_scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(lists_scroll),
                                 GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_widget_set_vexpand(lists_scroll, TRUE);
  auto* user_list = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(user_list),
                                  GTK_SELECTION_SINGLE);
  gtk_widget_add_css_class(user_list, "sidebar-list");
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(lists_scroll),
                                user_list);
  gtk_box_append(GTK_BOX(sidebar), lists_scroll);

  gtk_paned_set_start_child(GTK_PANED(body), sidebar);

  // Task pane: header (toggle + title/subtitle + search + show-completed),
  // quick-add capsule with live parse preview, then the task list with the
  // floating undo banner on top (macOS M4 layout).
  auto* pane = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_hexpand(pane, TRUE);

  auto* header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
  gtk_widget_set_margin_top(header, 10);
  gtk_widget_set_margin_bottom(header, 10);
  gtk_widget_set_margin_start(header, 16);
  gtk_widget_set_margin_end(header, 16);
  auto* sidebar_toggle =
      gtk_button_new_from_icon_name("sidebar-hide-symbolic");
  gtk_widget_add_css_class(sidebar_toggle, "flat");
  gtk_widget_set_valign(sidebar_toggle, GTK_ALIGN_CENTER);
  gtk_widget_set_tooltip_text(sidebar_toggle, tr("sidebarHide").c_str());
  g_signal_connect(sidebar_toggle, "clicked",
                   G_CALLBACK(on_sidebar_toggle_clicked), nullptr);
  gtk_box_append(GTK_BOX(header), sidebar_toggle);
  auto* title_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  gtk_widget_set_hexpand(title_box, TRUE);
  auto* pane_title = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(pane_title), 0.0f);
  gtk_widget_add_css_class(pane_title, "pane-title");
  gtk_box_append(GTK_BOX(title_box), pane_title);
  auto* pane_subtitle = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(pane_subtitle), 0.0f);
  gtk_widget_add_css_class(pane_subtitle, "pane-subtitle");
  gtk_box_append(GTK_BOX(title_box), pane_subtitle);
  gtk_box_append(GTK_BOX(header), title_box);
  auto* search = gtk_search_entry_new();
  gtk_widget_set_valign(search, GTK_ALIGN_CENTER);
  gtk_widget_set_size_request(search, 200, 28);
  gtk_box_append(GTK_BOX(header), search);
  auto* show_completed = gtk_toggle_button_new_with_label("");
  gtk_widget_add_css_class(show_completed, "flat");
  gtk_widget_add_css_class(show_completed, "accent-toggle");
  gtk_widget_set_valign(show_completed, GTK_ALIGN_CENTER);
  gtk_box_append(GTK_BOX(header), show_completed);
  gtk_box_append(GTK_BOX(pane), header);
  auto* header_divider = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_widget_add_css_class(header_divider, "taskly-divider");
  gtk_box_append(GTK_BOX(pane), header_divider);

  // Quick-add capsule: circular accent plus + entry + live preview chip;
  // the capsule border turns accent while focused.
  auto* quick_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_margin_top(quick_row, 10);
  gtk_widget_set_margin_bottom(quick_row, 10);
  gtk_widget_set_margin_start(quick_row, 16);
  gtk_widget_set_margin_end(quick_row, 16);
  auto* quick_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_add_css_class(quick_box, "quick-add-box");
  gtk_widget_set_hexpand(quick_box, TRUE);
  auto* quick_plus = gtk_button_new_with_label("＋");
  gtk_widget_add_css_class(quick_plus, "quick-add-plus");
  gtk_widget_set_valign(quick_plus, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_start(quick_plus, 7);
  gtk_widget_set_opacity(quick_plus, 0.45);
  gtk_box_append(GTK_BOX(quick_box), quick_plus);
  auto* quick_add = gtk_entry_new();
  gtk_widget_add_css_class(quick_add, "quick-add");
  gtk_widget_set_hexpand(quick_add, TRUE);
  gtk_box_append(GTK_BOX(quick_box), quick_add);
  auto* preview = gtk_label_new("");
  gtk_widget_add_css_class(preview, "preview-capsule");
  gtk_widget_set_valign(preview, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_end(preview, 8);
  gtk_widget_set_visible(preview, FALSE);
  gtk_box_append(GTK_BOX(quick_box), preview);
  gtk_box_append(GTK_BOX(quick_row), quick_box);
  gtk_box_append(GTK_BOX(pane), quick_row);
  auto* quick_divider = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_widget_add_css_class(quick_divider, "taskly-divider");
  gtk_box_append(GTK_BOX(pane), quick_divider);

  auto* task_scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(task_scroll),
                                 GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_widget_set_vexpand(task_scroll, TRUE);
  auto* task_list = gtk_list_box_new();
  gtk_list_box_set_selection_mode(GTK_LIST_BOX(task_list),
                                  GTK_SELECTION_NONE);
  gtk_widget_add_css_class(task_list, "task-row-list");
  gtk_widget_set_valign(GTK_WIDGET(task_list), GTK_ALIGN_START);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(task_scroll), task_list);

  // Empty states: 📂 + hint when no database, ✓ when the view is empty.
  auto* list_stack = gtk_stack_new();
  gtk_widget_set_vexpand(list_stack, TRUE);
  gtk_stack_add_named(GTK_STACK(list_stack), task_scroll, "list");
  auto* empty_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_widget_set_valign(empty_box, GTK_ALIGN_CENTER);
  gtk_widget_set_halign(empty_box, GTK_ALIGN_CENTER);
  auto* empty_icon = gtk_label_new("📂");
  gtk_widget_add_css_class(empty_icon, "empty-icon");
  gtk_box_append(GTK_BOX(empty_box), empty_icon);
  auto* empty_text = gtk_label_new("");
  gtk_widget_add_css_class(empty_text, "pane-subtitle");
  gtk_box_append(GTK_BOX(empty_box), empty_text);
  gtk_stack_add_named(GTK_STACK(list_stack), empty_box, "empty");
  gtk_stack_set_visible_child_name(GTK_STACK(list_stack), "empty");

  // Task list + floating undo banner (macOS M4 floats the banner over the
  // list's bottom edge).
  auto* list_overlay = gtk_overlay_new();
  gtk_overlay_set_child(GTK_OVERLAY(list_overlay), list_stack);
  auto* banner_revealer = gtk_revealer_new();
  gtk_revealer_set_transition_type(GTK_REVEALER(banner_revealer),
                                   GTK_REVEALER_TRANSITION_TYPE_CROSSFADE);
  auto* banner_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_revealer_set_child(GTK_REVEALER(banner_revealer), banner_box);
  gtk_widget_set_halign(banner_revealer, GTK_ALIGN_END);
  gtk_widget_set_valign(banner_revealer, GTK_ALIGN_END);
  gtk_widget_set_margin_bottom(banner_revealer, 12);
  gtk_widget_set_margin_start(banner_revealer, 12);
  gtk_widget_set_margin_end(banner_revealer, 12);
  gtk_overlay_add_overlay(GTK_OVERLAY(list_overlay), banner_revealer);
  g_object_set_data(G_OBJECT(banner_box), "banner-revealer", banner_revealer);
  gtk_box_append(GTK_BOX(pane), list_overlay);
  gtk_paned_set_end_child(GTK_PANED(body), pane);
  gtk_paned_set_position(GTK_PANED(body), 280);
  gtk_box_append(GTK_BOX(root), body);

  // Status bar (28px): persistent view status with 3s flashes.
  auto* statusbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(statusbar, "taskly-statusbar");
  auto* status_text = gtk_label_new("");
  gtk_label_set_ellipsize(GTK_LABEL(status_text), PANGO_ELLIPSIZE_END);
  gtk_label_set_xalign(GTK_LABEL(status_text), 0.0f);
  gtk_widget_set_margin_top(status_text, 4);
  gtk_widget_set_margin_bottom(status_text, 4);
  gtk_widget_set_margin_start(status_text, 12);
  gtk_widget_set_margin_end(status_text, 12);
  gtk_box_append(GTK_BOX(statusbar), status_text);
  gtk_box_append(GTK_BOX(root), statusbar);

  gtk_window_set_child(GTK_WINDOW(window), root);

  g_state.window = GTK_WINDOW(window);
  g_state.menubar_box = GTK_BOX(menubar_box);
  g_state.my_lists_caption = GTK_LABEL(my_lists_caption);
  g_state.user_list = GTK_LIST_BOX(user_list);
  g_state.new_list_button = GTK_BUTTON(new_list_button);
  g_state.pane_title = GTK_LABEL(pane_title);
  g_state.pane_subtitle = GTK_LABEL(pane_subtitle);
  g_state.search_box = GTK_SEARCH_ENTRY(search);
  g_state.show_completed_toggle = GTK_TOGGLE_BUTTON(show_completed);
  g_state.quick_add = GTK_ENTRY(quick_add);
  g_state.quick_add_preview = GTK_LABEL(preview);
  g_state.quick_plus = GTK_BUTTON(quick_plus);
  g_state.task_list = GTK_LIST_BOX(task_list);
  g_state.list_stack = GTK_STACK(list_stack);
  g_state.empty_icon = GTK_LABEL(empty_icon);
  g_state.empty_text = GTK_LABEL(empty_text);
  g_state.sidebar_toggle = GTK_BUTTON(sidebar_toggle);
  g_state.banner_box = GTK_BOX(banner_box);
  g_state.status_text = GTK_LABEL(status_text);

  add_window_action(GTK_APPLICATION_WINDOW(window), "task-due-today",
                    on_action_task_due_today, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "task-due-tomorrow",
                    on_action_task_due_tomorrow, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "task-due-clear",
                    on_action_task_due_clear, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "task-due-custom",
                    on_action_task_due_custom, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "task-edit",
                    on_action_task_edit, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "task-delete",
                    on_action_task_delete, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "list-delete",
                    on_action_list_delete, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "list-edit",
                    on_action_list_edit, true);
  add_window_action(GTK_APPLICATION_WINDOW(window), "new-database",
                    on_menu_new_database, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "open-database",
                    on_menu_open_database, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "close-database",
                    on_menu_close_database, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "exit", on_menu_exit,
                    false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "lang-zh",
                    on_menu_lang_zh, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "lang-en",
                    on_menu_lang_en, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "theme-system",
                    on_menu_theme_system, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "theme-light",
                    on_menu_theme_light, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "theme-dark",
                    on_menu_theme_dark, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "about", on_menu_about,
                    false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "view-today",
                    on_action_view_today, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "view-planned",
                    on_action_view_planned, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "view-all",
                    on_action_view_all, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "view-completed",
                    on_action_view_completed, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "new-task",
                    on_action_new_task, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "focus-search",
                    on_action_focus_search, false);
  add_window_action(GTK_APPLICATION_WINDOW(window), "toggle-completed",
                    on_action_toggle_completed, false);

  // Window-wide accelerators (PRODUCT-SPEC §8; Things-style keyboard-first).
  static char const* const accels_today[] = {"<Primary>1", nullptr};
  static char const* const accels_planned[] = {"<Primary>2", nullptr};
  static char const* const accels_all[] = {"<Primary>3", nullptr};
  static char const* const accels_completed[] = {"<Primary>4", nullptr};
  static char const* const accels_new_task[] = {"<Primary>n", nullptr};
  static char const* const accels_search[] = {"<Primary>f", nullptr};
  static char const* const accels_toggle_completed[] = {"<Primary><Shift>c",
                                                        nullptr};
  gtk_application_set_accels_for_action(app, "win.view-today", accels_today);
  gtk_application_set_accels_for_action(app, "win.view-planned",
                                        accels_planned);
  gtk_application_set_accels_for_action(app, "win.view-all", accels_all);
  gtk_application_set_accels_for_action(app, "win.view-completed",
                                        accels_completed);
  gtk_application_set_accels_for_action(app, "win.new-task", accels_new_task);
  gtk_application_set_accels_for_action(app, "win.focus-search",
                                        accels_search);
  gtk_application_set_accels_for_action(app, "win.toggle-completed",
                                        accels_toggle_completed);

  g_signal_connect(user_list, "row-selected",
                   G_CALLBACK(on_user_row_selected), nullptr);
  g_signal_connect(new_list_button, "clicked",
                   G_CALLBACK(on_new_list_clicked), nullptr);
  g_signal_connect(show_completed, "toggled",
                   G_CALLBACK(on_show_completed_toggled), nullptr);
  g_signal_connect(quick_add, "activate",
                   G_CALLBACK(on_quick_add_activate), nullptr);
  g_signal_connect(quick_plus, "clicked",
                   G_CALLBACK(on_quick_plus_clicked), nullptr);
  g_signal_connect(quick_add, "changed", G_CALLBACK(on_quick_add_changed),
                   nullptr);
  g_signal_connect(search, "search-changed",
                   G_CALLBACK(on_search_changed), nullptr);
  g_signal_connect(search, "stop-search", G_CALLBACK(on_search_stopped),
                   nullptr);

  // Esc ladder: editor → search → nothing.
  auto* window_keys = gtk_event_controller_key_new();
  g_signal_connect(window_keys, "key-pressed",
                   G_CALLBACK(on_window_key_pressed), nullptr);
  gtk_widget_add_controller(GTK_WIDGET(window), window_keys);

  apply_theme("system");
  apply_language();
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
  auto* app =
      gtk_application_new("app.taskly.Taskly", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(on_activate), nullptr);
  g_signal_connect(app, "shutdown", G_CALLBACK(on_shutdown), nullptr);
  int const status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);
  return status;
}
