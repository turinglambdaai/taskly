#include "pch.h"
#include "MainWindow.xaml.h"
#if __has_include("MainWindow.g.cpp")
#include "MainWindow.g.cpp"
#endif
#include "GeneratedBackend.hpp"

#include <functional>
#include <shobjidl_core.h>
#include <stdexcept>

namespace winrt::RivetHost::implementation {
namespace {

namespace mx = winrt::Microsoft::UI::Xaml;
namespace mxc = winrt::Microsoft::UI::Xaml::Controls;

std::filesystem::path executable_path() {
  std::wstring buffer(32768, L'\0');
  auto const length = ::GetModuleFileNameW(nullptr, buffer.data(),
                                          static_cast<DWORD>(buffer.size()));
  if (length == 0 || length == buffer.size()) {
    throw std::runtime_error("GetModuleFileNameW failed");
  }
  buffer.resize(length);
  return std::filesystem::path(buffer);
}

std::string utf8(std::filesystem::path const& path) {
  auto const wide = path.wstring();
  if (wide.empty()) {
    return {};
  }
  auto const size = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                          wide.data(),
                                          static_cast<int>(wide.size()),
                                          nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    throw std::runtime_error("WideCharToMultiByte failed");
  }
  std::string result(static_cast<std::size_t>(size), '\0');
  if (::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                            wide.data(), static_cast<int>(wide.size()),
                            result.data(), size, nullptr, nullptr) != size) {
    throw std::runtime_error("WideCharToMultiByte failed");
  }
  return result;
}

std::wstring wide(std::string const& text) {
  if (text.empty()) {
    return {};
  }
  auto const size = ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                          static_cast<int>(text.size()),
                                          nullptr, 0);
  if (size <= 0) {
    return {};
  }
  std::wstring result(static_cast<std::size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                        static_cast<int>(text.size()), result.data(), size);
  return result;
}

rivet::windows::RacketRuntimeConfig runtime_config() {
  auto const exe = executable_path();
  auto const root = exe.parent_path();
  auto const runtime = root / L"runtime";

  rivet::windows::RacketRuntimeConfig config;
  config.executable_path = utf8(exe);
  config.petite_boot = utf8(runtime / L"petite.boot");
  config.scheme_boot = utf8(runtime / L"scheme.boot");
  config.racket_boot = utf8(runtime / L"racket.boot");
  config.backend_bundle = utf8(root / L"res" / L"core.zo");
  config.module_name = rivet_app::kModuleName;
  config.entry_symbol = rivet_app::kEntryName;
  config.dll_dir = runtime.wstring();
  return config;
}

// Local calendar date as YYYY-MM-DD, `offset_days` from today.
std::wstring date_string(int offset_days) {
  FILETIME now{};
  ::GetSystemTimeAsFileTime(&now);
  ULARGE_INTEGER instant{};
  instant.LowPart = now.dwLowDateTime;
  instant.HighPart = now.dwHighDateTime;
  instant.QuadPart += static_cast<ULONGLONG>(offset_days) * 24 * 60 * 60 *
                      10000000ULL;
  FILETIME shifted{};
  shifted.dwLowDateTime = instant.LowPart;
  shifted.dwHighDateTime = instant.HighPart;
  SYSTEMTIME utc{};
  ::FileTimeToSystemTime(&shifted, &utc);
  SYSTEMTIME local{};
  ::SystemTimeToTzSpecificLocalTime(nullptr, &utc, &local);
  wchar_t buffer[11]{};
  swprintf_s(buffer, L"%04d-%02d-%02d", local.wYear, local.wMonth,
             local.wDay);
  return buffer;
}

// Lexicographic YYYY-MM-DD compare; malformed dates sort after any date.
int date_compare(std::string const& due, std::wstring const& today) {
  if (due.size() != 10) {
    return 1;
  }
  return wide(due).compare(today);
}

std::wstring due_tail(std::string const& due) {
  if (due.size() != 10) {
    return wide(due);
  }
  return wide(due.substr(5));
}

template <typename T>
T const* find_by_id(std::vector<T> const& items, std::int64_t id) {
  for (auto const& item : items) {
    if (item.id == id) {
      return &item;
    }
  }
  return nullptr;
}

}  // namespace

Strings const& S(std::string const& lang) {
  static Strings const zh = [] {
    Strings s;
    s.search_placeholder = L"搜索任务";
    s.smart_lists = L"智能清单";
    s.my_lists = L"我的清单";
    s.new_list = L"＋ 新建清单";
    s.today = L"今天";
    s.planned = L"已计划";
    s.all = L"全部";
    s.completed = L"已完成";
    s.new_task_placeholder = L"新提醒";
    s.show_completed = L"显示已完成";
    s.due_today = L"今天";
    s.due_tomorrow = L"明天";
    s.due_clear = L"清除日期";
    s.delete_task = L"删除提醒";
    s.rename_list = L"重命名清单";
    s.delete_list = L"删除清单";
    s.new_list_dialog_title = L"新建清单";
    s.new_list_dialog_placeholder = L"清单名称";
    s.rename_list_dialog_title = L"重命名清单";
    s.edit_task_dialog_title = L"编辑提醒";
    s.ok = L"确定";
    s.cancel = L"取消";
    s.menu_file = L"文件";
    s.menu_settings = L"设置";
    s.menu_help = L"帮助";
    s.menu_new_db = L"新建数据库…";
    s.menu_open_db = L"打开数据库…";
    s.menu_close_db = L"关闭数据库";
    s.menu_exit = L"退出";
    s.menu_lang_zh = L"中文";
    s.menu_lang_en = L"English";
    s.menu_theme_system = L"主题：跟随系统";
    s.menu_theme_light = L"主题：浅色";
    s.menu_theme_dark = L"主题：深色";
    s.menu_about = L"关于 Taskly";
    s.about_title = L"Taskly";
    s.about_body =
        L"Taskly — 跨平台待办事项\n由 Rivet 驱动：Racket 后端 + 原生界面";
    s.status_starting = L"正在启动嵌入式 Racket…";
    s.status_ready = L"就绪";
    s.status_error = L"错误";
    s.count_suffix = L" 项";
    return s;
  }();
  static Strings const en = [] {
    Strings s;
    s.search_placeholder = L"Search tasks";
    s.smart_lists = L"Smart lists";
    s.my_lists = L"My lists";
    s.new_list = L"＋ New list";
    s.today = L"Today";
    s.planned = L"Planned";
    s.all = L"All";
    s.completed = L"Completed";
    s.new_task_placeholder = L"New reminder";
    s.show_completed = L"Show completed";
    s.due_today = L"Today";
    s.due_tomorrow = L"Tomorrow";
    s.due_clear = L"Clear date";
    s.delete_task = L"Delete reminder";
    s.rename_list = L"Rename list";
    s.delete_list = L"Delete list";
    s.new_list_dialog_title = L"New list";
    s.new_list_dialog_placeholder = L"List name";
    s.rename_list_dialog_title = L"Rename list";
    s.edit_task_dialog_title = L"Edit reminder";
    s.ok = L"OK";
    s.cancel = L"Cancel";
    s.menu_file = L"File";
    s.menu_settings = L"Settings";
    s.menu_help = L"Help";
    s.menu_new_db = L"New database…";
    s.menu_open_db = L"Open database…";
    s.menu_close_db = L"Close database";
    s.menu_exit = L"Exit";
    s.menu_lang_zh = L"中文";
    s.menu_lang_en = L"English";
    s.menu_theme_system = L"Theme: Follow system";
    s.menu_theme_light = L"Theme: Light";
    s.menu_theme_dark = L"Theme: Dark";
    s.menu_about = L"About Taskly";
    s.about_title = L"Taskly";
    s.about_body =
        L"Taskly — cross-platform reminders\nPowered by Rivet: a Racket backend with a native UI";
    s.status_starting = L"Starting embedded Racket…";
    s.status_ready = L"Ready";
    s.status_error = L"Error";
    s.count_suffix = L" items";
    return s;
  }();
  return lang == "en" ? en : zh;
}

std::string MainWindow::ViewStringFor(ViewKind kind) {
  switch (kind) {
    case ViewKind::Today:
      return "today";
    case ViewKind::Planned:
      return "planned";
    case ViewKind::Completed:
      return "completed";
    case ViewKind::List:
    case ViewKind::All:
    default:
      return "all";
  }
}

MainWindow::MainWindow() {
  InitializeComponent();
  Title(L"Taskly");
  SetStatus(S("zh").status_starting);
  InitializeBackendAsync();
}

// ---------------------------------------------------------------------------
// Startup
// ---------------------------------------------------------------------------

winrt::fire_and_forget MainWindow::InitializeBackendAsync() {
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = std::make_shared<rivet::windows::Backend>(runtime_config());

  try {
    // Booting the embedded runtime can block on file I/O, so only startup is
    // moved off the UI thread. RPC traffic below is completion-driven.
    co_await winrt::resume_background();
    backend->start();

    dispatcher.TryEnqueue([weak, backend = std::move(backend)]() mutable {
      if (auto window = weak.get()) {
        window->backend_ = std::move(backend);
        try {
          auto& backend_ref = *window->backend_;
          auto const event_dispatcher = window->DispatcherQueue();
          auto const event_weak = window->get_weak();
          // The backend publishes `changed` after every mutation (including
          // ones made through the shared CLI). Reload the visible view.
          backend_ref.set_event_handler(
              [event_dispatcher, event_weak](std::string const& name,
                                             rivet::Value const&) {
                if (name == "changed") {
                  event_dispatcher.TryEnqueue([event_weak] {
                    if (auto current = event_weak.get()) {
                      current->ReloadTasksAsync();
                    }
                  });
                }
              });

          // CLI and GUI share the database; cross-process writes cannot
          // emit `changed`, so poll the snapshot instead.
          window->poll_timer_ = mx::DispatcherTimer();
          window->poll_timer_.Interval(std::chrono::milliseconds{2000});
          window->poll_timer_.Tick([window_weak = window->get_weak()](
                                        auto&&, auto&&) {
            if (auto current = window_weak.get()) {
              current->ReloadTasksAsync();
            }
          });
          window->poll_timer_.Start();

          rivet_app::API api(backend_ref);
          auto const settings_dispatcher = window->DispatcherQueue();
          auto const settings_weak = window->get_weak();
          (void)api.get_settings_async(
              [settings_dispatcher, settings_weak](
                  rivet_app::Result<rivet_app::Settings> result) {
                try {
                  auto const settings = result.get();
                  settings_dispatcher.TryEnqueue([settings_weak, settings] {
                    if (auto current = settings_weak.get()) {
                      current->settings_ = settings;
                      current->ApplyTheme(settings.theme);
                      current->ApplyLanguage();
                      current->OpenDefaultDatabaseAsync();
                    }
                  });
                } catch (std::exception const& e) {
                  auto message = std::string(e.what());
                  settings_dispatcher.TryEnqueue(
                      [settings_weak, message = std::move(message)] {
                        if (auto current = settings_weak.get()) {
                          current->SetError(message);
                        }
                      });
                }
              });
        } catch (std::exception const& e) {
          window->SetError(e.what());
        }
      } else {
        // Never destroy the last Backend reference on its own reader thread.
        std::thread([backend = std::move(backend)]() mutable {
          backend->stop();
        }).detach();
      }
    });
  } catch (std::exception const& e) {
    auto message = std::string(e.what());
    dispatcher.TryEnqueue([weak, message = std::move(message)] {
      if (auto window = weak.get()) {
        window->SetError(message);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

void MainWindow::ApplyLanguage() {
  auto const& s = S(settings_.language);
  MenuFile().Title(s.menu_file);
  MenuSettings().Title(s.menu_settings);
  MenuHelp().Title(s.menu_help);
  MenuNewDatabase().Text(s.menu_new_db);
  MenuOpenDatabase().Text(s.menu_open_db);
  MenuCloseDatabase().Text(s.menu_close_db);
  MenuExit().Text(s.menu_exit);
  MenuLangZh().Text(s.menu_lang_zh);
  MenuLangEn().Text(s.menu_lang_en);
  MenuThemeSystem().Text(s.menu_theme_system);
  MenuThemeLight().Text(s.menu_theme_light);
  MenuThemeDark().Text(s.menu_theme_dark);
  MenuAbout().Text(s.menu_about);
  SearchBox().PlaceholderText(s.search_placeholder);
  SmartListsHeader().Text(s.smart_lists);
  MyListsHeader().Text(s.my_lists);
  NewListButton().Content(winrt::box_value(s.new_list));
  NewTaskBox().PlaceholderText(s.new_task_placeholder);
  ShowCompletedCheck().Content(winrt::box_value(s.show_completed));
  RenderSidebar();
  RenderTasks();
}

void MainWindow::ApplyTheme(std::string const& theme) {
  if (theme == "light") {
    RootGrid().RequestedTheme(mx::ElementTheme::Light);
  } else if (theme == "dark") {
    RootGrid().RequestedTheme(mx::ElementTheme::Dark);
  } else {
    RootGrid().RequestedTheme(mx::ElementTheme::Default);
  }
}

mx::Media::Brush MainWindow::ThemeBrush(wchar_t const* key) {
  return RootGrid().Resources().Lookup(winrt::box_value(key))
      .as<mx::Media::Brush>();
}

void MainWindow::RenderSidebar() {
  auto const& s = S(settings_.language);

  suppress_selection_ = true;
  struct Restore {
    MainWindow* window;
    ~Restore() { window->suppress_selection_ = false; }
  } restore{this};

  struct SmartEntry {
    ViewKind kind;
    wchar_t const* glyph;
    std::wstring title;
    std::int64_t count;
  };
  SmartEntry const entries[] = {
      {ViewKind::Today, L"\uE8BF", s.today, current_counts_.today},
      {ViewKind::Planned, L"\uE787", s.planned, current_counts_.planned},
      {ViewKind::All, L"\uE8A9", s.all, current_counts_.all},
      {ViewKind::Completed, L"\uE73E", s.completed,
       current_counts_.completed},
  };

  SmartList().Items().Clear();
  for (auto const& entry : entries) {
    auto row = mxc::Grid{};
    row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
    row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
    row.ColumnDefinitions().GetAt(0).Width(
        mx::GridLength{1, mx::GridUnitType::Star});
    row.ColumnDefinitions().GetAt(1).Width(mx::GridLength{0, mx::GridUnitType::Auto});

    auto label = mxc::StackPanel{};
    label.Orientation(mxc::Orientation::Horizontal);
    label.Spacing(10);
    auto glyph = mxc::FontIcon{};
    glyph.Glyph(winrt::hstring(entry.glyph));
    glyph.FontSize(16);
    label.Children().Append(glyph);
    auto text = mxc::TextBlock{};
    text.Text(entry.title);
    label.Children().Append(text);
    mxc::Grid::SetColumn(label, 0);
    row.Children().Append(label);

    auto badge = mxc::TextBlock{};
    badge.Text(std::to_wstring(entry.count));
    badge.Foreground(ThemeBrush(L"TasklySecondaryTextBrush"));
    mxc::Grid::SetColumn(badge, 1);
    row.Children().Append(badge);

    row.Tag(winrt::box_value(static_cast<std::int32_t>(entry.kind)));
    SmartList().Items().Append(row);
    if (view_ != ViewKind::List && view_ == entry.kind) {
      SmartList().SelectedIndex(SmartList().Items().Size() - 1);
    }
  }

  UserList().Items().Clear();
  for (auto const& list : lists_) {
    auto row = mxc::Grid{};
    row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
    row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
    row.ColumnDefinitions().GetAt(0).Width(
        mx::GridLength{1, mx::GridUnitType::Star});
    row.ColumnDefinitions().GetAt(1).Width(mx::GridLength{0, mx::GridUnitType::Auto});

    auto text = mxc::TextBlock{};
    text.Text(wide(list.name));
    text.TextTrimming(mx::TextTrimming::CharacterEllipsis);
    mxc::Grid::SetColumn(text, 0);
    row.Children().Append(text);

    auto badge = mxc::TextBlock{};
    badge.Text(std::to_wstring(list.pending_count));
    badge.Foreground(ThemeBrush(L"TasklySecondaryTextBrush"));
    mxc::Grid::SetColumn(badge, 1);
    row.Children().Append(badge);

    auto menu = mxc::MenuFlyout{};
    auto rename = mxc::MenuFlyoutItem{};
    rename.Text(s.rename_list);
    rename.Tag(winrt::box_value<std::int64_t>(list.id));
    rename.Click({this, &MainWindow::OnRenameList});
    menu.Items().Append(rename);
    auto remove = mxc::MenuFlyoutItem{};
    remove.Text(s.delete_list);
    remove.Tag(winrt::box_value<std::int64_t>(list.id));
    remove.Click({this, &MainWindow::OnDeleteList});
    menu.Items().Append(remove);
    row.ContextFlyout(menu);

    row.Tag(winrt::box_value<std::int64_t>(list.id));
    UserList().Items().Append(row);
    if (view_ == ViewKind::List && view_list_id_ == list.id) {
      UserList().SelectedIndex(UserList().Items().Size() - 1);
    }
  }
}

void MainWindow::RenderTasks() {
  auto const& s = S(settings_.language);
  PaneTitle().Text(view_title());
  PaneCount().Text(std::to_wstring(tasks_.size()) + s.count_suffix);

  TaskList().Items().Clear();
  for (auto const& task : tasks_) {
    TaskList().Items().Append(MakeTaskRow(task));
  }
}

void MainWindow::RenderSearchResults() {
  SearchResults().Items().Clear();
  for (auto const& task : search_results_) {
    SearchResults().Items().Append(MakeTaskRow(task));
  }
}

mxc::Grid MainWindow::MakeTaskRow(rivet_app::Task const& task) {
  auto const& s = S(settings_.language);

  auto row = mxc::Grid{};
  row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
  row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
  row.ColumnDefinitions().GetAt(0).Width(mx::GridLength{0, mx::GridUnitType::Auto});
  row.ColumnDefinitions().GetAt(1).Width(
      mx::GridLength{1, mx::GridUnitType::Star});
  row.Padding(mx::ThicknessHelper::FromLengths(4, 4, 4, 4));
  row.Tag(winrt::box_value<std::int64_t>(task.id));

  auto check = mxc::CheckBox{};
  check.IsChecked(task.completed);
  check.MinWidth(0);
  check.Checked({this, &MainWindow::OnTaskCheckChanged});
  check.Unchecked({this, &MainWindow::OnTaskCheckChanged});
  check.Tag(winrt::box_value<std::int64_t>(task.id));
  mxc::Grid::SetColumn(check, 0);
  row.Children().Append(check);

  auto content = mxc::StackPanel{};
  content.Margin(mx::ThicknessHelper::FromLengths(8, 0, 0, 0));
  content.Spacing(2);
  mxc::Grid::SetColumn(content, 1);
  row.Children().Append(content);

  auto text = mxc::TextBlock{};
  text.Text(wide(task.text));
  text.TextTrimming(mx::TextTrimming::CharacterEllipsis);
  if (task.completed) {
    text.Foreground(ThemeBrush(L"TasklyMutedTextBrush"));
  }
  content.Children().Append(text);

  // Due chip: colored for today/tomorrow, red when overdue, muted otherwise.
  if (task.due_date.has_value()) {
    auto chip_text = mxc::TextBlock{};
    chip_text.Text(DueLabel(*task.due_date));
    chip_text.FontSize(12);
    auto const today = date_string(0);
    auto const compare = date_compare(*task.due_date, today);
    wchar_t const* brush_key = L"TasklySecondaryTextBrush";
    if (compare < 0) {
      brush_key = L"TasklyOverdueBrush";
    } else if (compare == 0) {
      brush_key = L"TasklyDueTodayBrush";
    } else if (date_compare(*task.due_date, date_string(1)) == 0) {
      brush_key = L"TasklyDueTomorrowBrush";
    }
    chip_text.Foreground(ThemeBrush(brush_key));
    content.Children().Append(chip_text);
  }

  auto menu = mxc::MenuFlyout{};
  auto due_today = mxc::MenuFlyoutItem{};
  due_today.Text(s.due_today);
  due_today.Tag(winrt::box_value<std::int64_t>(task.id));
  due_today.Click({this, &MainWindow::OnDueToday});
  menu.Items().Append(due_today);
  auto due_tomorrow = mxc::MenuFlyoutItem{};
  due_tomorrow.Text(s.due_tomorrow);
  due_tomorrow.Tag(winrt::box_value<std::int64_t>(task.id));
  due_tomorrow.Click({this, &MainWindow::OnDueTomorrow});
  menu.Items().Append(due_tomorrow);
  auto due_clear = mxc::MenuFlyoutItem{};
  due_clear.Text(s.due_clear);
  due_clear.Tag(winrt::box_value<std::int64_t>(task.id));
  due_clear.Click({this, &MainWindow::OnDueClear});
  menu.Items().Append(due_clear);
  menu.Items().Append(mxc::MenuFlyoutSeparator{});
  auto edit = mxc::MenuFlyoutItem{};
  edit.Text(s.edit_task_dialog_title);
  edit.Tag(winrt::box_value<std::int64_t>(task.id));
  edit.Click({this, &MainWindow::OnEditTask});
  menu.Items().Append(edit);
  auto remove = mxc::MenuFlyoutItem{};
  remove.Text(s.delete_task);
  remove.Tag(winrt::box_value<std::int64_t>(task.id));
  remove.Click({this, &MainWindow::OnDeleteTask});
  menu.Items().Append(remove);
  row.ContextFlyout(menu);

  // Double-click edits the text.
  row.DoubleTapped({this, &MainWindow::OnEditTask});
  return row;
}

winrt::hstring MainWindow::DueLabel(std::string const& due_date) const {
  auto const today = date_string(0);
  auto const compare = date_compare(due_date, today);
  auto const& s = S(settings_.language);
  if (compare == 0) {
    return winrt::hstring(s.due_today);
  }
  if (compare < 0) {
    return winrt::hstring(due_tail(due_date));
  }
  if (date_compare(due_date, date_string(1)) == 0) {
    return winrt::hstring(s.due_tomorrow);
  }
  return winrt::hstring(due_tail(due_date));
}

std::wstring MainWindow::view_title() const {
  auto const& s = S(settings_.language);
  switch (view_) {
    case ViewKind::Today:
      return s.today;
    case ViewKind::Planned:
      return s.planned;
    case ViewKind::Completed:
      return s.completed;
    case ViewKind::List: {
      if (auto const* list = find_by_id(lists_, view_list_id_)) {
        return wide(list->name);
      }
      return s.all;
    }
    case ViewKind::All:
    default:
      return s.all;
  }
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------

void MainWindow::SetStatus(std::wstring const& message) {
  StatusText().Text(message);
}

void MainWindow::SetError(std::string const& message) {
  SetStatus(S(settings_.language).status_error + L": " + wide(message));
}

winrt::fire_and_forget MainWindow::PromptAsync(
    std::wstring const& title, std::wstring const& placeholder,
    std::wstring const& initial,
    std::function<void(std::wstring const&)> on_ok) {
  auto input = mxc::TextBox{};
  input.PlaceholderText(placeholder);
  input.Text(initial);

  auto const& s = S(settings_.language);
  auto dialog = mxc::ContentDialog{};
  dialog.Title(winrt::box_value(title));
  dialog.Content(input);
  dialog.PrimaryButtonText(s.ok);
  dialog.CloseButtonText(s.cancel);
  dialog.DefaultButton(mxc::ContentDialogButton::Primary);
  dialog.XamlRoot(Content().XamlRoot());

  auto const result = co_await dialog.ShowAsync();
  if (result == mxc::ContentDialogResult::Primary) {
    on_ok(std::wstring(input.Text()));
  }
}

// ---------------------------------------------------------------------------
// Data flow
// ---------------------------------------------------------------------------

winrt::fire_and_forget MainWindow::ReloadTasksAsync() {
  if (backend_ == nullptr || !backend_->running() ||
      reload_in_flight_.load(std::memory_order_acquire)) {
    co_return;
  }
  reload_in_flight_.store(true, std::memory_order_release);

  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto const view_kind = view_;
  auto const list_id = view_list_id_;
  auto const include_completed = show_completed_;
  auto const lang = settings_.language;
  auto backend = backend_;

  bool started = false;
  try {
    rivet_app::API api(*backend);
    (void)api.load_snapshot_async(
        ViewStringFor(view_kind),
        view_kind == ViewKind::List
            ? std::optional<std::int64_t>(list_id)
            : std::nullopt,
        include_completed,
        [dispatcher, weak,
         lang](rivet_app::Result<rivet_app::Snapshot> result) {
          // Release the reload gate on every terminal path so later
          // polls and `changed` events are not swallowed.
          dispatcher.TryEnqueue([weak] {
            if (auto window = weak.get()) {
              window->reload_in_flight_.store(false,
                                              std::memory_order_release);
            }
          });
          try {
            auto const snapshot = result.get();
            dispatcher.TryEnqueue([weak, snapshot, lang] {
              if (auto window = weak.get()) {
                window->current_counts_ = snapshot.counts;
                window->lists_ = snapshot.lists;
                window->tasks_ = snapshot.tasks;
                window->RenderSidebar();
                window->RenderTasks();
                window->SetStatus(S(lang).status_ready);
              }
            });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
    started = true;
  } catch (std::exception const& e) {
    SetError(e.what());
  }
  if (!started) {
    reload_in_flight_.store(false, std::memory_order_release);
  }
}

winrt::fire_and_forget MainWindow::OpenDefaultDatabaseAsync() {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.default_database_async(
        [dispatcher, weak](rivet_app::Result<std::string> result) {
          try {
            auto const path = result.get();
            dispatcher.TryEnqueue([weak, path] {
              if (auto window = weak.get()) {
                window->settings_.database_path = path;
                window->OpenDatabaseAsync(std::wstring(winrt::to_hstring(path)));
              }
            });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}
winrt::fire_and_forget MainWindow::OpenDatabaseAsync(std::wstring const& path) {
  if (backend_ == nullptr || !backend_->running() || path.empty()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.open_database_async(
        winrt::to_string(path),
        [dispatcher, weak](rivet_app::Result<rivet_app::Snapshot> result) {
          try {
            auto const snapshot = result.get();
            dispatcher.TryEnqueue([weak, snapshot] {
              if (auto window = weak.get()) {
                window->current_counts_ = snapshot.counts;
                window->lists_ = snapshot.lists;
                window->tasks_ = snapshot.tasks;
                // Restore the last-selected list when it still exists.
                auto const restored = window->settings_.last_selected_list_id;
                if (restored > 0 &&
                    find_by_id(window->lists_, restored) != nullptr) {
                  window->view_ = MainWindow::ViewKind::List;
                  window->view_list_id_ = restored;
                }
                window->RenderSidebar();
                window->RenderTasks();
                window->SetStatus(S(window->settings_.language).status_ready);
              }
            });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::AddTaskAsync(std::wstring const& text) {
  if (backend_ == nullptr || !backend_->running() || text.empty()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    // One quick-add grammar on every platform: the backend splits text +
    // due (parse_quick_add); this host only forwards the result.
    (void)api.parse_quick_add_async(
        winrt::to_string(text),
        [dispatcher, weak, backend](rivet_app::Result<rivet_app::QuickAddParse> parsed) {
          try {
            auto const parse = parsed.get();
            rivet_app::API api(*backend);
            // `changed` triggers the authoritative reload; the completion
            // only surfaces failures.
            (void)api.add_task_async(
                parse.text, std::nullopt, parse.due_date, parse.due_time,
                std::nullopt,
                [dispatcher, weak](rivet_app::Result<rivet_app::Task> result) {
                  try {
                    result.get();
                  } catch (std::exception const& e) {
                    auto message = std::string(e.what());
                    dispatcher.TryEnqueue([weak, message = std::move(message)] {
                      if (auto window = weak.get()) {
                        window->SetError(message);
                      }
                    });
                  }
                });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::ToggleTaskAsync(std::int64_t id,
                                                   bool completed) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.set_completed_async(
        id, completed,
        [dispatcher, weak](rivet_app::Result<rivet_app::Task> result) {
          try {
            result.get();
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::RenameTaskAsync(std::int64_t id,
                                                   std::wstring const& text) {
  if (backend_ == nullptr || !backend_->running() || text.empty()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.update_task_text_async(
        id, winrt::to_string(text),
        [dispatcher, weak](rivet_app::Result<rivet_app::Task> result) {
          try {
            result.get();
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::SetTaskDueAsync(std::int64_t id,
                                                   std::wstring const& due) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  // Start from the stored task so untouched fields survive update_task.
  auto const* stored = find_by_id(tasks_, id);
  if (stored == nullptr) {
    co_return;
  }
  auto updated = *stored;
  updated.due_date =
      due.empty() ? std::nullopt
                  : std::optional<std::string>(winrt::to_string(due));
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.update_task_async(
        updated, [dispatcher, weak](rivet_app::Result<rivet_app::Task> result) {
          try {
            result.get();
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::DeleteTaskAsync(std::int64_t id) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.delete_task_async(
        id, [dispatcher, weak](rivet_app::Result<bool> result) {
          try {
            result.get();
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::CreateListAsync(std::wstring const& name) {
  if (backend_ == nullptr || !backend_->running() || name.empty()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.create_list_async(
        winrt::to_string(name), std::nullopt, std::nullopt,
        [dispatcher, weak](rivet_app::Result<rivet_app::TodoList> result) {
          try {
            result.get();
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::RenameListAsync(std::int64_t id,
                                                   std::wstring const& name) {
  if (backend_ == nullptr || !backend_->running() || name.empty()) {
    co_return;
  }
  auto const* stored = find_by_id(lists_, id);
  if (stored == nullptr) {
    co_return;
  }
  auto updated = *stored;
  updated.name = winrt::to_string(name);
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.update_list_async(
        updated,
        [dispatcher, weak](rivet_app::Result<rivet_app::TodoList> result) {
          try {
            result.get();
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::DeleteListAsync(std::int64_t id) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.delete_list_async(
        id, [dispatcher, weak](rivet_app::Result<bool> result) {
          try {
            result.get();
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::SaveSettingAsync(std::string const& key,
                                                    std::string const& value) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.set_setting_async(
        key, value,
        [dispatcher, weak](rivet_app::Result<rivet_app::Settings> result) {
          try {
            auto const settings = result.get();
            dispatcher.TryEnqueue([weak, settings] {
              if (auto window = weak.get()) {
                window->settings_ = settings;
              }
            });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::RunSearchAsync(std::wstring const& keyword) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.search_tasks_async(
        winrt::to_string(keyword),
        [dispatcher, weak,
         keyword](rivet_app::Result<std::vector<rivet_app::Task>> result) {
          try {
            auto const results = result.get();
            dispatcher.TryEnqueue([weak, results, keyword] {
              if (auto window = weak.get()) {
                // Drop stale completions: only the newest keyword renders.
                if (window->current_search_ == keyword) {
                  window->search_results_ = results;
                  window->RenderSearchResults();
                }
              }
            });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

// ---------------------------------------------------------------------------
// Menu handlers
// ---------------------------------------------------------------------------

void MainWindow::OnNewDatabase(winrt::Windows::Foundation::IInspectable const&,
                               Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const& s = S(settings_.language);
  auto const weak = get_weak();
  PromptAsync(s.menu_new_db, s.new_list_dialog_placeholder, L"",
              [weak](std::wstring const& path) {
                if (auto window = weak.get()) {
                  window->OpenDatabaseAsync(path);
                }
              });
}

winrt::fire_and_forget MainWindow::OnOpenDatabase(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto picker = winrt::Windows::Storage::Pickers::FileOpenPicker{};
  auto window_native = try_as<::IWindowNative>();
  if (window_native) {
    HWND hwnd = nullptr;
    if (SUCCEEDED(window_native->get_WindowHandle(&hwnd))) {
      if (auto initializer = picker.try_as<::IInitializeWithWindow>()) {
        initializer->Initialize(hwnd);
      }
    }
  }
  picker.FileTypeFilter().Append(L".db");
  picker.FileTypeFilter().Append(L".sqlite");
  auto const file = co_await picker.PickSingleFileAsync();
  if (file != nullptr) {
    OpenDatabaseAsync(std::wstring(file.Path()));
  }
}

void MainWindow::OnCloseDatabase(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  if (backend_ == nullptr || !backend_->running()) {
    return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  rivet_app::API api(*backend);
  (void)api.close_database_async(
      [dispatcher, weak](rivet_app::Result<void> result) {
        try {
          result.get();
          dispatcher.TryEnqueue([weak] {
            if (auto window = weak.get()) {
              window->lists_.clear();
              window->tasks_.clear();
              window->current_counts_ = {};
              window->RenderSidebar();
              window->RenderTasks();
              window->SetStatus(L"");
            }
          });
        } catch (std::exception const& e) {
          auto message = std::string(e.what());
          dispatcher.TryEnqueue([weak, message = std::move(message)] {
            if (auto window = weak.get()) {
              window->SetError(message);
            }
          });
        }
      });
}

void MainWindow::OnExit(winrt::Windows::Foundation::IInspectable const&,
                        Microsoft::UI::Xaml::RoutedEventArgs const&) {
  Close();
}

void MainWindow::OnLangZh(winrt::Windows::Foundation::IInspectable const&,
                          Microsoft::UI::Xaml::RoutedEventArgs const&) {
  settings_.language = "zh";
  ApplyLanguage();
  SaveSettingAsync("language", "zh");
}

void MainWindow::OnLangEn(winrt::Windows::Foundation::IInspectable const&,
                          Microsoft::UI::Xaml::RoutedEventArgs const&) {
  settings_.language = "en";
  ApplyLanguage();
  SaveSettingAsync("language", "en");
}

void MainWindow::OnThemeSystem(winrt::Windows::Foundation::IInspectable const&,
                               Microsoft::UI::Xaml::RoutedEventArgs const&) {
  ApplyTheme("system");
  SaveSettingAsync("theme", "system");
}

void MainWindow::OnThemeLight(winrt::Windows::Foundation::IInspectable const&,
                              Microsoft::UI::Xaml::RoutedEventArgs const&) {
  ApplyTheme("light");
  SaveSettingAsync("theme", "light");
}

void MainWindow::OnThemeDark(winrt::Windows::Foundation::IInspectable const&,
                             Microsoft::UI::Xaml::RoutedEventArgs const&) {
  ApplyTheme("dark");
  SaveSettingAsync("theme", "dark");
}

winrt::fire_and_forget MainWindow::OnAbout(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const& s = S(settings_.language);
  auto dialog = mxc::ContentDialog{};
  dialog.Title(winrt::box_value(s.about_title));
  dialog.Content(winrt::box_value(s.about_body));
  dialog.CloseButtonText(s.ok);
  dialog.XamlRoot(Content().XamlRoot());
  co_await dialog.ShowAsync();
}

// ---------------------------------------------------------------------------
// Sidebar handlers
// ---------------------------------------------------------------------------

void MainWindow::OnSearchTextChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&) {
  auto const keyword = std::wstring(SearchBox().Text());
  if (keyword.empty()) {
    current_search_.clear();
    SearchPane().Visibility(mx::Visibility::Collapsed);
    RenderTasks();
    return;
  }
  current_search_ = keyword;
  RunSearchAsync(keyword);
}

void MainWindow::OnSmartListSelectionChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
  if (suppress_selection_ || SmartList().SelectedIndex() < 0) {
    return;
  }
  auto const tag =
      SmartList()
          .Items()
          .GetAt(static_cast<std::uint32_t>(SmartList().SelectedIndex()))
          .as<mxc::Grid>()
          .Tag();
  view_ = static_cast<ViewKind>(winrt::unbox_value<std::int32_t>(tag));
  suppress_selection_ = true;
  UserList().SelectedIndex(-1);
  suppress_selection_ = false;
  RenderTasks();
  ReloadTasksAsync();
}

void MainWindow::OnUserListSelectionChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
  if (suppress_selection_ || UserList().SelectedIndex() < 0) {
    return;
  }
  auto const tag =
      UserList()
          .Items()
          .GetAt(static_cast<std::uint32_t>(UserList().SelectedIndex()))
          .as<mxc::Grid>()
          .Tag();
  view_ = ViewKind::List;
  view_list_id_ = winrt::unbox_value<std::int64_t>(tag);
  if (settings_.last_selected_list_id != view_list_id_) {
    settings_.last_selected_list_id = view_list_id_;
    SaveSettingAsync("last-selected-list-id", std::to_string(view_list_id_));
  }
  suppress_selection_ = true;
  SmartList().SelectedIndex(-1);
  suppress_selection_ = false;
  RenderTasks();
  ReloadTasksAsync();
}

void MainWindow::OnNewList(winrt::Windows::Foundation::IInspectable const&,
                           Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const& s = S(settings_.language);
  auto const weak = get_weak();
  PromptAsync(s.new_list_dialog_title, s.new_list_dialog_placeholder, L"",
              [weak](std::wstring const& name) {
                if (auto window = weak.get()) {
                  window->CreateListAsync(name);
                }
              });
}

void MainWindow::OnRenameList(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const id = winrt::unbox_value<std::int64_t>(
      sender.as<mxc::MenuFlyoutItem>().Tag());
  auto const* list = find_by_id(lists_, id);
  if (list == nullptr) {
    return;
  }
  auto const& s = S(settings_.language);
  auto const weak = get_weak();
  PromptAsync(s.rename_list_dialog_title, s.new_list_dialog_placeholder,
              wide(list->name), [weak, id](std::wstring const& name) {
                if (auto window = weak.get()) {
                  window->RenameListAsync(id, name);
                }
              });
}

void MainWindow::OnDeleteList(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const id = winrt::unbox_value<std::int64_t>(
      sender.as<mxc::MenuFlyoutItem>().Tag());
  if (view_ == ViewKind::List && view_list_id_ == id) {
    view_ = ViewKind::All;
    view_list_id_ = 0;
  }
  DeleteListAsync(id);
}

// ---------------------------------------------------------------------------
// Task pane handlers
// ---------------------------------------------------------------------------

void MainWindow::OnShowCompletedChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const checked = ShowCompletedCheck().IsChecked();
  show_completed_ = checked != nullptr && checked.Value();
  ReloadTasksAsync();
}

void MainWindow::OnNewTaskKeyDown(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args) {
  if (args.Key() == Windows::System::VirtualKey::Enter) {
    auto const text = std::wstring(NewTaskBox().Text());
    NewTaskBox().Text(L"");
    AddTaskAsync(text);
  }
}

void MainWindow::OnTaskCheckChanged(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const check = sender.as<mxc::CheckBox>();
  auto const id = winrt::unbox_value<std::int64_t>(check.Tag());
  auto const completed = check.IsChecked().GetBoolean();
  ToggleTaskAsync(id, completed);
}

void MainWindow::OnDueToday(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const id = winrt::unbox_value<std::int64_t>(
      sender.as<mxc::MenuFlyoutItem>().Tag());
  SetTaskDueAsync(id, date_string(0));
}

void MainWindow::OnDueTomorrow(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const id = winrt::unbox_value<std::int64_t>(
      sender.as<mxc::MenuFlyoutItem>().Tag());
  SetTaskDueAsync(id, date_string(1));
}

void MainWindow::OnDueClear(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const id = winrt::unbox_value<std::int64_t>(
      sender.as<mxc::MenuFlyoutItem>().Tag());
  SetTaskDueAsync(id, L"");
}

void MainWindow::OnEditTask(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  std::int64_t id = 0;
  if (auto const item = sender.try_as<mxc::MenuFlyoutItem>()) {
    id = winrt::unbox_value<std::int64_t>(item.Tag());
  } else if (auto const row = sender.try_as<mxc::Grid>()) {
    id = winrt::unbox_value<std::int64_t>(row.Tag());
  } else {
    return;
  }
  auto const* task = find_by_id(tasks_, id);
  if (task == nullptr) {
    return;
  }
  auto const& s = S(settings_.language);
  auto const weak = get_weak();
  PromptAsync(s.edit_task_dialog_title, L"", wide(task->text),
              [weak, id](std::wstring const& text) {
                if (auto window = weak.get()) {
                  window->RenameTaskAsync(id, text);
                }
              });
}

void MainWindow::OnDeleteTask(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const id = winrt::unbox_value<std::int64_t>(
      sender.as<mxc::MenuFlyoutItem>().Tag());
  DeleteTaskAsync(id);
}

}  // namespace winrt::RivetHost::implementation
