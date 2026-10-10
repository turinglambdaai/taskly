#include "pch.h"
#include "MainWindow.xaml.h"
#if __has_include("MainWindow.g.cpp")
#include "MainWindow.g.cpp"
#endif
#include "GeneratedBackend.hpp"

#include <fstream>
#include <functional>
#include <iterator>
#include <map>
#include <shobjidl_core.h>
#include <stdexcept>

namespace winrt::RivetHost::implementation {

namespace mx = winrt::Microsoft::UI::Xaml;
namespace mxc = winrt::Microsoft::UI::Xaml::Controls;

// ---------------------------------------------------------------------------
// Host helpers shared with MainWindow.Update.cpp (payback's HostHelpers
// pattern): executable path and UTF conversion.
// ---------------------------------------------------------------------------

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
  auto const wide_path = path.wstring();
  if (wide_path.empty()) {
    return {};
  }
  auto const size = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                          wide_path.data(),
                                          static_cast<int>(wide_path.size()),
                                          nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    throw std::runtime_error("WideCharToMultiByte failed");
  }
  std::string result(static_cast<std::size_t>(size), '\0');
  if (::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                            wide_path.data(), static_cast<int>(wide_path.size()),
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

namespace {

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

std::wstring replace_all(std::wstring text, std::wstring const& from,
                         std::wstring const& to) {
  std::size_t position = 0;
  while ((position = text.find(from, position)) != std::wstring::npos) {
    text.replace(position, from.size(), to);
    position += to.size();
  }
  return text;
}

}  // namespace

// ---------------------------------------------------------------------------
// i18n — strings load from <exe_dir>/app/shared/i18n/{zh,en}.json, byte
// copies of shared/i18n/*.json (the single source of truth; flat
// string→string JSON, UTF-8 without BOM, machine-generated with indent=2 so
// a line-based parser is enough). rivet.rktd declares shared/i18n under
// `resources`, so packages carry it at <dir>/app/shared/i18n. An embedded
// fallback table mirrors every key the host uses; lookup order: active
// language → other language → the key itself.
// ---------------------------------------------------------------------------

namespace {

struct I18nEntry {
  char const* key;
  char const* zh;
  char const* en;
};

constexpr I18nEntry kI18nFallback[] = {
    {"menuFile", "文件", "File"},
    {"menuSettings", "设置", "Settings"},
    {"menuHelp", "帮助", "Help"},
    {"menuNewDatabase", "新建数据库", "New Database"},
    {"menuOpenDatabase", "打开数据库", "Open Database"},
    {"menuCloseDatabase", "关闭数据库", "Close Database"},
    {"menuExit", "退出", "Exit"},
    {"menuLangZh", "简体中文", "Simplified Chinese"},
    {"menuLangEn", "English", "English"},
    {"menuTheme", "主题", "Theme"},
    {"themeFollowSystem", "跟随系统", "Follow system"},
    {"themeLight", "浅色", "Light"},
    {"themeDark", "深色", "Dark"},
    {"menuAbout", "关于", "About"},
    {"aboutContent",
     "一款专注高效的个人任务管理工具\n帮助您轻松规划、组织和完成各项任务",
     "A focused and efficient personal task management tool\nHelping you "
     "plan, organize and complete tasks easily"},
    {"navToday", "今天", "Today"},
    {"navPlanned", "计划", "Planned"},
    {"navAll", "全部", "All"},
    {"navCompleted", "完成", "Completed"},
    {"sectionMyLists", "我的列表", "My Lists"},
    {"searchHint", "搜索任务", "Search tasks"},
    {"taskListInputHint", "+ 添加任务", "+ Add Task"},
    {"showCompletedToggle", "显示已完成", "Show Completed"},
    {"dateTomorrow", "明天", "Tomorrow"},
    {"dialogConfirm", "确定", "OK"},
    {"dialogCancel", "取消", "Cancel"},
    {"dialogClear", "清除", "Clear"},
    {"dialogCreateList", "创建列表", "Create List"},
    {"dialogEditList", "编辑列表", "Edit List"},
    {"dialogInputListName", "请输入列表名称", "Please enter list name"},
    {"dialogTaskDetail", "任务详情", "Task Detail"},
    {"contextMenuDetails", "详细信息", "Details"},
    {"taskDelete", "删除", "Delete"},
    {"listDelete", "删除列表", "Delete List"},
    {"statusDatabaseNotConnected", "未连接数据库", "Database Not Connected"},
    {"statusDatabaseConnected", "数据库已连接", "Database Connected"},
    {"subtitleOpenTasks", "{0} 个未完成", "{0} open"},
    {"updateCheckNow", "检查更新…", "Check for Updates…"},
    {"updateChecking", "正在检查更新…", "Checking for updates…"},
    {"updateUpToDate", "当前已是最新版本", "You're up to date"},
    {"updateAvailableTitle", "发现新版本", "Update available"},
    {"updateAvailableBody", "新版本 {0} 可用，是否立即安装并重启？",
     "Version {0} is available. Install and restart now?"},
    {"updateRestart", "立即更新", "Update and restart"},
    {"updateCheckFailed", "检查更新失败：{0}", "Update check failed: {0}"},
    {"updateDownloading", "正在下载新版本…", "Downloading the new version…"},
    {"updateDownloadPercent", "正在下载新版本… {0}%",
     "Downloading the new version… {0}%"},
    {"updateDownloaded", "更新已下载", "Update downloaded"},
    {"updateQuitAndInstall", "退出并安装", "Quit and install"},
    {"updateReadyBody", "新版本已就绪，将重启应用完成安装。",
     "The new version is ready — Taskly will restart to install it."},
    {"updateInstallFailed", "安装更新失败：{0}。当前版本未受影响。",
     "Installing the update failed: {0}. Your current version is unaffected."},
    {"updateNotInstalled", "当前为开发副本，自动更新不可用。",
     "This is a development copy — auto-update is unavailable."},
    {"updateMsiInstalled",
     "当前副本通过 MSI 安装器安装，暂不支持应用内更新，请到发布页下载新的安装包。",
     "This copy was installed via the MSI installer — in-app update isn't "
     "available for it. Grab the new installer from the releases page."},
    {"updatePortable",
     "当前为便携版，不支持自动更新，请从发布页重新下载。",
     "This portable copy can't auto-update — please re-download from the "
     "releases page."},
    {"updateOpenReleases", "打开发布页", "Open releases page"},
};

using I18nTable = std::map<std::string, std::wstring>;

I18nTable g_i18n[2];    // 0 = zh, 1 = en
int g_i18n_active = 1;  // "en" until get_settings reports the user's choice

std::string narrow(std::wstring const& text) {
  if (text.empty()) {
    return {};
  }
  auto const size = ::WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                          static_cast<int>(text.size()),
                                          nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return {};
  }
  std::string result(static_cast<std::size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), size, nullptr, nullptr);
  return result;
}

// Index of the closing quote for the JSON string starting at `start`
// (which points at '"'), honoring backslash escapes.
std::size_t i18n_string_end(std::wstring const& line, std::size_t start) {
  for (std::size_t i = start + 1; i < line.size(); ++i) {
    if (line[i] == L'\\') {
      ++i;
      continue;
    }
    if (line[i] == L'"') {
      return i;
    }
  }
  return std::wstring::npos;
}

std::wstring i18n_unescape(std::wstring const& raw) {
  std::wstring out;
  out.reserve(raw.size());
  for (std::size_t i = 0; i < raw.size(); ++i) {
    if (raw[i] != L'\\') {
      out.push_back(raw[i]);
      continue;
    }
    if (++i >= raw.size()) {
      break;
    }
    switch (raw[i]) {
      case L'"':
        out.push_back(L'"');
        break;
      case L'\\':
        out.push_back(L'\\');
        break;
      case L'/':
        out.push_back(L'/');
        break;
      case L'n':
        out.push_back(L'\n');
        break;
      case L't':
        out.push_back(L'\t');
        break;
      case L'r':
        out.push_back(L'\r');
        break;
      case L'b':
        out.push_back(L'\b');
        break;
      case L'f':
        out.push_back(L'\f');
        break;
      case L'u': {
        if (i + 4 >= raw.size()) {
          i = raw.size();
          break;
        }
        unsigned int code = 0;
        bool valid = true;
        for (int digit = 1; digit <= 4; ++digit) {
          wchar_t const h = raw[i + digit];
          code <<= 4;
          if (h >= L'0' && h <= L'9') {
            code += static_cast<unsigned int>(h - L'0');
          } else if (h >= L'a' && h <= L'f') {
            code += static_cast<unsigned int>(h - L'a') + 10;
          } else if (h >= L'A' && h <= L'F') {
            code += static_cast<unsigned int>(h - L'A') + 10;
          } else {
            valid = false;
            break;
          }
        }
        if (!valid) {
          i = raw.size();
          break;
        }
        i += 4;
        // Consecutive \uXXXX escapes concatenate into (surrogate) pairs.
        out.push_back(static_cast<wchar_t>(code));
        break;
      }
      default:
        out.push_back(raw[i]);
        break;
    }
  }
  return out;
}

// Tolerant loader for the flat "key": "value" table. Returns true when at
// least one entry was read; a malformed line is skipped, never fatal.
bool load_i18n_file(std::filesystem::path const& path, int lang) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    return false;
  }
  std::string bytes((std::istreambuf_iterator<char>(file)),
                    std::istreambuf_iterator<char>());
  if (bytes.size() >= 3 && bytes[0] == '\xEF' && bytes[1] == '\xBB' &&
      bytes[2] == '\xBF') {
    bytes.erase(0, 3);  // tolerate a BOM; the generator does not emit one
  }
  if (bytes.empty()) {
    return false;
  }
  auto const size = ::MultiByteToWideChar(CP_UTF8, 0, bytes.data(),
                                          static_cast<int>(bytes.size()),
                                          nullptr, 0);
  if (size <= 0) {
    return false;
  }
  std::wstring text(static_cast<std::size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()),
                        text.data(), size);

  auto& table = g_i18n[lang];
  bool loaded_any = false;
  std::size_t begin = 0;
  while (begin < text.size()) {
    auto end = text.find(L'\n', begin);
    if (end == std::wstring::npos) {
      end = text.size();
    }
    auto line = text.substr(begin, end - begin);
    begin = end + 1;
    if (!line.empty() && line.back() == L'\r') {
      line.pop_back();
    }

    auto const key_start = line.find(L'"');
    if (key_start == std::wstring::npos) {
      continue;
    }
    auto const key_end = i18n_string_end(line, key_start);
    if (key_end == std::wstring::npos) {
      continue;
    }
    auto const colon = line.find(L':', key_end);
    if (colon == std::wstring::npos) {
      continue;
    }
    auto const value_start = line.find(L'"', colon + 1);
    if (value_start == std::wstring::npos) {
      continue;
    }
    auto const value_end = i18n_string_end(line, value_start);
    if (value_end == std::wstring::npos) {
      continue;
    }
    table[narrow(line.substr(key_start + 1, key_end - key_start - 1))] =
        i18n_unescape(line.substr(value_start + 1,
                                  value_end - value_start - 1));
    loaded_any = true;
  }
  return loaded_any;
}

void load_i18n(std::filesystem::path const& exe_dir) {
  char const* names[] = {"zh.json", "en.json"};
  for (int lang = 0; lang < 2; ++lang) {
    auto& table = g_i18n[lang];
    table.clear();
    for (auto const& entry : kI18nFallback) {
      table.emplace(entry.key, wide(lang == 0 ? entry.zh : entry.en));
    }
    // Staged product resources: rivet.rktd declares shared/i18n under
    // `resources`, so packages carry it at <dir>/app/shared/i18n; the dev
    // tree wins for `raco rivet dev` runs where nothing is packaged yet.
    std::filesystem::path const candidates[] = {
        exe_dir / L"app" / L"shared" / L"i18n",
        exe_dir / L".." / L".." / L"shared" / L"i18n",  // dev: .rivet/stage
    };
    for (auto const& dir : candidates) {
      auto const path = dir / names[lang];
      std::error_code ec;
      if (!std::filesystem::exists(path, ec)) {
        continue;
      }
      if (load_i18n_file(path, lang)) {
        break;
      }
    }
  }
}

void set_i18n_language(std::string const& lang) {
  g_i18n_active = (lang == "en") ? 1 : 0;
}

}  // namespace

std::wstring t(char const* key) {
  std::string const needle(key);
  for (int attempt = 0; attempt < 2; ++attempt) {
    auto const& table = g_i18n[(g_i18n_active + attempt) % 2];
    auto const it = table.find(needle);
    if (it != table.end()) {
      return it->second;
    }
  }
  return wide(key);  // unknown key: render the key itself, never crash
}

std::wstring tf(char const* key, std::wstring const& arg0) {
  return replace_all(t(key), L"{0}", arg0);
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
  // PRODUCT-SPEC §2: default 1024×768 logical, scaled by the monitor DPI.
  auto const window_native = try_as<::IWindowNative>();
  HWND hwnd = nullptr;
  winrt::check_hresult(window_native->get_WindowHandle(&hwnd));
  auto const dpi = ::GetDpiForWindow(hwnd);
  AppWindow().Resize(
      {1024 * static_cast<std::int32_t>(dpi) / 96,
       768 * static_cast<std::int32_t>(dpi) / 96});
  // PRODUCT-SPEC §2: minimum 760×520 logical.
  auto const presenter =
      AppWindow().Presenter().as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>();
  presenter.PreferredMinimumWidth(760 * static_cast<std::int32_t>(dpi) / 96);
  presenter.PreferredMinimumHeight(520 * static_cast<std::int32_t>(dpi) / 96);
  try {
    load_i18n(executable_path().parent_path());
  } catch (...) {
    // The fallback tables stay usable even if the exe path fails.
  }
  set_i18n_language("en");  // corrected once get_settings reports
  SetStatus(t("statusDatabaseNotConnected"));
  // ApplyLanguage is the single source for every built-in string: the first
  // paint is uniformly English (no XAML-default or blank elements), and the
  // get_settings landing (OnLangZh/OnLangEn too) re-runs it wholesale so the
  // final state always matches the user's language — never a mix.
  ApplyLanguage();
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
                      // A previous update run may have left a failure report
                      // (shared/spec/UPDATE.md); surface it once, then start
                      // the throttled silent check.
                      current->HandleInstallMarkers();
                      current->OpenDefaultDatabaseAsync();
                      current->AutoCheckUpdatesAsync();
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
  set_i18n_language(settings_.language);
  MenuFile().Title(t("menuFile"));
  MenuSettings().Title(t("menuSettings"));
  MenuHelp().Title(t("menuHelp"));
  MenuNewDatabase().Text(t("menuNewDatabase"));
  MenuOpenDatabase().Text(t("menuOpenDatabase"));
  MenuCloseDatabase().Text(t("menuCloseDatabase"));
  MenuExit().Text(t("menuExit"));
  MenuLangZh().Text(t("menuLangZh"));
  MenuLangEn().Text(t("menuLangEn"));
  MenuTheme().Text(t("menuTheme"));
  MenuThemeSystem().Text(t("themeFollowSystem"));
  MenuThemeLight().Text(t("themeLight"));
  MenuThemeDark().Text(t("themeDark"));
  MenuCheckUpdates().Text(t("updateCheckNow"));
  MenuAbout().Text(t("menuAbout"));
  SearchBox().PlaceholderText(t("searchHint"));
  MyListsHeader().Text(t("sectionMyLists"));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
      NewListButton(), t("dialogCreateList"));
  NewTaskBox().PlaceholderText(t("taskListInputHint"));
  mxc::ToolTipService::SetToolTip(
      SidebarToggle(),
      winrt::box_value(t(sidebar_visible_ ? "sidebarHide" : "sidebarShow")));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
      SidebarToggle(),
      t(sidebar_visible_ ? "sidebarHide" : "sidebarShow"));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
      QuickAddButton(), t("taskListInputHint"));
  ShowCompletedCheck().Content(winrt::box_value(t("showCompletedToggle")));
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

// Smart-view chips: refresh glyph/title/count and the checked fill. Per
// DESIGN-TOKENS the saturated view color only ever sits on the glyph; the
// chip itself is neutral surface (+1px divider from XAML) with a quiet
// selection fill while its view is current. Zero counts stay hidden.
void MainWindow::RefreshSmartTiles() {
  struct Chip {
    ViewKind kind;
    mxc::Button tile;
    mxc::FontIcon glyph;
    mxc::TextBlock label;
    mxc::TextBlock count;
    wchar_t const* glyph_code;
    wchar_t const* color_key;
    char const* title_key;
    std::int64_t value;
  };
  Chip const chips[] = {
      {ViewKind::Today, TileToday(), TileTodayGlyph(), TileTodayLabel(),
       TileTodayCount(), L"\uE787", L"TasklyTileTodayBrush", "navToday",
       current_counts_.today},
      {ViewKind::Planned, TilePlanned(), TilePlannedGlyph(), TilePlannedLabel(),
       TilePlannedCount(), L"\uE8BF", L"TasklyTilePlannedBrush", "navPlanned",
       current_counts_.planned},
      {ViewKind::All, TileAll(), TileAllGlyph(), TileAllLabel(), TileAllCount(),
       L"\uE7EB", L"TasklyTileAllBrush", "navAll", current_counts_.all},
      {ViewKind::Completed, TileCompleted(), TileCompletedGlyph(),
       TileCompletedLabel(), TileCompletedCount(), L"\uE930",
       L"TasklyTileCompletedBrush", "navCompleted", current_counts_.completed},
  };
  for (auto const& chip : chips) {
    chip.tile.Tag(winrt::box_value(static_cast<std::int32_t>(chip.kind)));
    chip.glyph.Glyph(chip.glyph_code);
    chip.glyph.Foreground(ThemeBrush(chip.color_key));
    chip.label.Text(t(chip.title_key));
    chip.tile.Background(ThemeBrush(view_ == chip.kind
                                        ? L"TasklySelectionBrush"
                                        : L"TasklySurfaceBrush"));
    if (chip.value > 0) {
      chip.count.Text(std::to_wstring(chip.value));
      chip.count.Visibility(mx::Visibility::Visible);
    } else {
      chip.count.Visibility(mx::Visibility::Collapsed);
    }
  }
}

mx::Media::Brush MainWindow::ListBrush(rivet_app::TodoList const& list) {
  // Signed 32-bit ARGB (DATA-FORMAT); accent fallback = Today blue.
  std::uint32_t const argb =
      static_cast<std::uint32_t>(list.color.value_or(0xFF007AFF));
  winrt::Windows::UI::Color color{};
  color.A = static_cast<std::uint8_t>((argb >> 24) & 0xFF);
  color.R = static_cast<std::uint8_t>((argb >> 16) & 0xFF);
  color.G = static_cast<std::uint8_t>((argb >> 8) & 0xFF);
  color.B = static_cast<std::uint8_t>(argb & 0xFF);
  mx::Media::SolidColorBrush brush{};
  brush.Color(color);
  return brush;
}

void MainWindow::RenderSidebar() {
  suppress_selection_ = true;
  struct Restore {
    MainWindow* window;
    ~Restore() { window->suppress_selection_ = false; }
  } restore{this};

  // 2×2 smart-view chips (PRODUCT-SPEC §3, DESIGN-TOKENS smart-list chip).
  RefreshSmartTiles();

  UserList().Items().Clear();
  for (auto const& list : lists_) {
    auto row = mxc::Grid{};
    row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
    row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
    row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
    row.ColumnDefinitions().GetAt(0).Width(
        mx::GridLength{0, mx::GridUnitType::Auto});
    row.ColumnDefinitions().GetAt(1).Width(
        mx::GridLength{1, mx::GridUnitType::Star});
    row.ColumnDefinitions().GetAt(2).Width(
        mx::GridLength{0, mx::GridUnitType::Auto});

    // 20px round swatch in the list color (accent fallback) with the emoji
    // inside (PRODUCT-SPEC §3 list row).
    auto swatch = mxc::Grid{};
    swatch.Margin(mx::ThicknessHelper::FromLengths(0, 0, 8, 0));
    auto dot = mx::Shapes::Ellipse{};
    dot.Width(20);
    dot.Height(20);
    dot.Fill(ListBrush(list));
    swatch.Children().Append(dot);
    auto emoji = mxc::TextBlock{};
    emoji.Text(wide(list.icon.value_or("\xF0\x9F\x8F\x8B")));
    emoji.FontSize(11);
    emoji.HorizontalAlignment(mx::HorizontalAlignment::Center);
    emoji.VerticalAlignment(mx::VerticalAlignment::Center);
    swatch.Children().Append(emoji);
    mxc::Grid::SetColumn(swatch, 0);
    row.Children().Append(swatch);

    auto text = mxc::TextBlock{};
    text.Text(wide(list.name));
    text.TextTrimming(mx::TextTrimming::CharacterEllipsis);
    text.VerticalAlignment(mx::VerticalAlignment::Center);
    mxc::Grid::SetColumn(text, 1);
    row.Children().Append(text);

    if (list.pending_count > 0) {
      auto badge = mxc::TextBlock{};
      badge.Text(std::to_wstring(list.pending_count));
      badge.Foreground(ThemeBrush(L"TasklySecondaryTextBrush"));
      badge.VerticalAlignment(mx::VerticalAlignment::Center);
      mxc::Grid::SetColumn(badge, 2);
      row.Children().Append(badge);
    }

    auto menu = mxc::MenuFlyout{};
    auto rename = mxc::MenuFlyoutItem{};
    rename.Text(t("dialogEditList"));
    rename.Tag(winrt::box_value<std::int64_t>(list.id));
    rename.Click({this, &MainWindow::OnRenameList});
    menu.Items().Append(rename);
    auto remove = mxc::MenuFlyoutItem{};
    remove.Text(t("listDelete"));
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
  PaneTitle().Text(view_title());
  PaneSubtitle().Text(view_subtitle());

  TaskList().Items().Clear();
  for (auto const& task : tasks_) {
    TaskList().Items().Append(MakeTaskRow(task));
  }

  // While a search is live its pane replaces the normal one; otherwise the
  // normal pane is the only pane, with the connected-empty state when the
  // view has no rows (PRODUCT-SPEC §5: ✓ + taskListEmpty).
  auto const searching = !current_search_.empty();
  NormalPane().Visibility(searching ? mx::Visibility::Collapsed
                                    : mx::Visibility::Visible);
  SearchPane().Visibility(searching ? mx::Visibility::Visible
                                    : mx::Visibility::Collapsed);
  auto const empty = !searching && tasks_.empty();
  EmptyState().Visibility(empty ? mx::Visibility::Visible
                                : mx::Visibility::Collapsed);
  if (empty) {
    EmptyStateIcon().Text(L"\u2713");
    EmptyStateText().Text(t("taskListEmpty"));
  }
}

void MainWindow::RenderSearchResults() {
  SearchResults().Items().Clear();
  for (auto const& task : search_results_) {
    SearchResults().Items().Append(MakeTaskRow(task));
  }
}

mxc::Grid MainWindow::MakeTaskRow(rivet_app::Task const& task) {
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
  text.FontSize(14);
  text.TextTrimming(mx::TextTrimming::CharacterEllipsis);
  if (task.completed) {
    text.Foreground(ThemeBrush(L"TasklyMutedTextBrush"));
    text.TextDecorations(
        winrt::Windows::UI::Text::TextDecorations::Strikethrough);
  }
  content.Children().Append(text);

  // Meta line (PRODUCT-SPEC §5, DESIGN-TOKENS task row): owning list name
  // with its color dot in the smart views, then the due chip; the notes
  // preview sits beneath.
  auto meta = mxc::StackPanel{};
  meta.Orientation(mxc::Orientation::Horizontal);
  meta.Spacing(8);
  if (view_ != ViewKind::List && task.list_name.has_value() &&
      !task.list_name->empty()) {
    auto list_label = mxc::StackPanel{};
    list_label.Orientation(mxc::Orientation::Horizontal);
    list_label.Spacing(4);
    list_label.VerticalAlignment(mx::VerticalAlignment::Center);
    auto dot = mx::Shapes::Ellipse{};
    dot.Width(7);
    dot.Height(7);
    auto const* list = find_by_id(lists_, task.list_id);
    dot.Fill(list ? ListBrush(*list) : ThemeBrush(L"TasklyAccentBrush"));
    list_label.Children().Append(dot);
    auto list_text = mxc::TextBlock{};
    list_text.Text(wide(*task.list_name));
    list_text.FontSize(12);
    list_text.Foreground(ThemeBrush(L"TasklySecondaryTextBrush"));
    list_text.VerticalAlignment(mx::VerticalAlignment::Center);
    list_label.Children().Append(list_text);
    meta.Children().Append(list_label);
  }

  // Due chip: colored for today/tomorrow, red when overdue, muted otherwise.
  // The time rides the same chip when set (PRODUCT-SPEC §5 meta line).
  if (task.due_date.has_value()) {
    std::wstring chip{DueLabel(*task.due_date)};
    if (task.due_time.has_value() && !task.due_time->empty()) {
      chip += L" \u00B7 " + wide(*task.due_time);
    }
    auto chip_text = mxc::TextBlock{};
    chip_text.Text(chip);
    chip_text.FontSize(12);
    chip_text.VerticalAlignment(mx::VerticalAlignment::Center);
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
    meta.Children().Append(chip_text);
  }
  if (meta.Children().Size() > 0) {
    content.Children().Append(meta);
  }

  // Notes preview: single line, ellipsized, muted (PRODUCT-SPEC §5).
  if (task.notes.has_value() && !task.notes->empty()) {
    auto notes_line = mxc::TextBlock{};
    notes_line.Text(wide(*task.notes));
    notes_line.FontSize(12);
    notes_line.TextTrimming(mx::TextTrimming::CharacterEllipsis);
    notes_line.Foreground(ThemeBrush(L"TasklyMutedTextBrush"));
    content.Children().Append(notes_line);
  }

  auto menu = mxc::MenuFlyout{};
  auto due_today = mxc::MenuFlyoutItem{};
  due_today.Text(t("navToday"));
  due_today.Tag(winrt::box_value<std::int64_t>(task.id));
  due_today.Click({this, &MainWindow::OnDueToday});
  menu.Items().Append(due_today);
  auto due_tomorrow = mxc::MenuFlyoutItem{};
  due_tomorrow.Text(t("dateTomorrow"));
  due_tomorrow.Tag(winrt::box_value<std::int64_t>(task.id));
  due_tomorrow.Click({this, &MainWindow::OnDueTomorrow});
  menu.Items().Append(due_tomorrow);
  auto due_clear = mxc::MenuFlyoutItem{};
  due_clear.Text(t("dialogClear"));
  due_clear.Tag(winrt::box_value<std::int64_t>(task.id));
  due_clear.Click({this, &MainWindow::OnDueClear});
  menu.Items().Append(due_clear);
  menu.Items().Append(mxc::MenuFlyoutSeparator{});
  auto edit = mxc::MenuFlyoutItem{};
  edit.Text(t("contextMenuDetails"));
  edit.Tag(winrt::box_value<std::int64_t>(task.id));
  edit.Click({this, &MainWindow::OnEditTask});
  menu.Items().Append(edit);
  auto remove = mxc::MenuFlyoutItem{};
  remove.Text(t("taskDelete"));
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
  if (compare == 0) {
    return winrt::hstring(t("navToday"));
  }
  if (compare < 0) {
    return winrt::hstring(due_tail(due_date));
  }
  if (date_compare(due_date, date_string(1)) == 0) {
    return winrt::hstring(t("dateTomorrow"));
  }
  return winrt::hstring(due_tail(due_date));
}

std::wstring MainWindow::view_title() const {
  switch (view_) {
    case ViewKind::Today:
      return t("navToday");
    case ViewKind::Planned:
      return t("navPlanned");
    case ViewKind::Completed:
      return t("navCompleted");
    case ViewKind::List: {
      if (auto const* list = find_by_id(lists_, view_list_id_)) {
        return wide(list->name);
      }
      return t("navAll");
    }
    case ViewKind::All:
    default:
      return t("navAll");
  }
}

winrt::hstring MainWindow::view_subtitle() const {
  // DESIGN-TOKENS view header: hidden while searching; today shows the full
  // locale date, the other views show open/completed counts.
  if (!current_search_.empty()) {
    return winrt::hstring{};
  }
  switch (view_) {
    case ViewKind::Today:
      return winrt::hstring(full_date_today());
    case ViewKind::Planned:
      return winrt::hstring(
          tf("subtitleOpenTasks", std::to_wstring(current_counts_.planned)));
    case ViewKind::Completed:
      return winrt::hstring(
          tf("subtitleCompleted", std::to_wstring(current_counts_.completed)));
    case ViewKind::List: {
      auto const* list = find_by_id(lists_, view_list_id_);
      return winrt::hstring(tf(
          "subtitleOpenTasks",
          std::to_wstring(list ? list->pending_count : 0)));
    }
    case ViewKind::All:
    default:
      return winrt::hstring(
          tf("subtitleOpenTasks", std::to_wstring(current_counts_.all)));
  }
}

std::wstring MainWindow::full_date_today() const {
  // Date shapes come from the platform locale, not copy (PRODUCT-SPEC §11).
  std::time_t const now = std::time(nullptr);
  std::tm local{};
  localtime_s(&local, &now);
  static wchar_t const* const en_months[]{
      L"January", L"February", L"March",     L"April",   L"May",      L"June",
      L"July",    L"August",   L"September", L"October", L"November", L"December"};
  static wchar_t const* const en_days[]{L"Sunday",    L"Monday",   L"Tuesday",
                                        L"Wednesday", L"Thursday", L"Friday",
                                        L"Saturday"};
  static wchar_t const* const zh_days[]{L"星期日", L"星期一", L"星期二",
                                        L"星期三", L"星期四", L"星期五",
                                        L"星期六"};
  if (g_i18n_active == 0) {
    std::wstring text = std::to_wstring(local.tm_year + 1900);
    text += L"年" + std::to_wstring(local.tm_mon + 1) + L"月" +
            std::to_wstring(local.tm_mday) + L"日 " + zh_days[local.tm_wday];
    return text;
  }
  return std::wstring(en_days[local.tm_wday]) + L", " +
         en_months[local.tm_mon] + L" " + std::to_wstring(local.tm_mday) +
         L", " + std::to_wstring(local.tm_year + 1900);
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------

void MainWindow::SetStatus(std::wstring const& message) {
  StatusText().Text(message);
}

void MainWindow::SetError(std::string const& message) {
  SetStatus(wide(message));
}

winrt::fire_and_forget MainWindow::PromptAsync(
    std::wstring const& title, std::wstring const& placeholder,
    std::wstring const& initial,
    std::function<void(std::wstring const&)> on_ok) {
  auto input = mxc::TextBox{};
  input.PlaceholderText(placeholder);
  input.Text(initial);

  auto dialog = mxc::ContentDialog{};
  dialog.Title(winrt::box_value(title));
  dialog.Content(input);
  dialog.PrimaryButtonText(t("dialogConfirm"));
  dialog.CloseButtonText(t("dialogCancel"));
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

namespace {

// One serialized snapshot field. Strings are length-prefixed so adjacent
// values can never blend into an equal serialization of different data.
void FingerprintField(std::string& out, std::string const& value) {
  out += std::to_string(value.size());
  out += ':';
  out += value;
  out += ';';
}

void FingerprintField(std::string& out, std::int64_t value) {
  out += std::to_string(value);
  out += ';';
}

void FingerprintField(std::string& out, bool value) {
  out += (value ? '1' : '0');
  out += ';';
}

void FingerprintField(std::string& out,
                      std::optional<std::string> const& value) {
  if (value.has_value()) {
    out += 's';
    FingerprintField(out, *value);
  } else {
    out += "n;";
  }
}

void FingerprintField(std::string& out,
                      std::optional<std::int64_t> const& value) {
  if (value.has_value()) {
    out += 'i';
    FingerprintField(out, *value);
  } else {
    out += "n;";
  }
}

// Everything the snapshot render pass reads (smart-tile counts, sidebar list
// rows, visible task rows), in the fixed field order of the structs in
// GeneratedBackend.hpp. Stable across polls, so an unchanged backend reply
// yields an equal string and the UI stays untouched.
std::string SnapshotFingerprint(rivet_app::Snapshot const& snapshot) {
  std::string fp;
  FingerprintField(fp, snapshot.counts.today);
  FingerprintField(fp, snapshot.counts.planned);
  FingerprintField(fp, snapshot.counts.all);
  FingerprintField(fp, snapshot.counts.completed);
  for (auto const& list : snapshot.lists) {
    FingerprintField(fp, list.id);
    FingerprintField(fp, list.name);
    FingerprintField(fp, list.icon);
    FingerprintField(fp, list.color);
    FingerprintField(fp, list.pending_count);
  }
  for (auto const& task : snapshot.tasks) {
    FingerprintField(fp, task.id);
    FingerprintField(fp, task.list_id);
    FingerprintField(fp, task.list_name);
    FingerprintField(fp, task.text);
    FingerprintField(fp, task.completed);
    FingerprintField(fp, task.due_date);
    FingerprintField(fp, task.due_time);
    FingerprintField(fp, task.notes);
    FingerprintField(fp, task.created_at);
  }
  return fp;
}

}  // namespace

// Applies a freshly loaded snapshot to the window. The poll timer and every
// `changed` event re-deliver a full snapshot; rebuilding the sidebar and task
// rows on each pass — even when nothing changed — makes the UI visibly
// jitter. Identical snapshots (same fingerprint) therefore leave the tree
// untouched. `force` bypasses the check for paths that changed state outside
// the snapshot (e.g. a new database was opened). Returns true when the
// render pass ran.
bool MainWindow::ApplySnapshot(rivet_app::Snapshot const& snapshot,
                               bool force) {
  auto const fingerprint = SnapshotFingerprint(snapshot);
  if (!force && has_applied_snapshot_ && fingerprint == applied_snapshot_) {
    return false;
  }
  has_applied_snapshot_ = true;
  applied_snapshot_ = fingerprint;
  current_counts_ = snapshot.counts;
  lists_ = snapshot.lists;
  tasks_ = snapshot.tasks;
  RenderSidebar();
  RenderTasks();
  return true;
}

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
        [dispatcher, weak](rivet_app::Result<rivet_app::Snapshot> result) {
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
            dispatcher.TryEnqueue([weak, snapshot] {
              if (auto window = weak.get()) {
                window->ApplySnapshot(snapshot, /*force=*/false);
                // An in-flight download owns the status line.
                if (!window->update_downloading_) {
                  window->SetStatus(t("statusDatabaseConnected"));
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
                // Restore the last-selected list when it still exists —
                // checked against the incoming snapshot because ApplySnapshot
                // owns the render pass.
                auto const restored = window->settings_.last_selected_list_id;
                if (restored > 0 &&
                    find_by_id(snapshot.lists, restored) != nullptr) {
                  window->view_ = MainWindow::ViewKind::List;
                  window->view_list_id_ = restored;
                }
                // A different database was just opened: always render, even
                // if its content matches the previous one byte for byte.
                window->ApplySnapshot(snapshot, /*force=*/true);
                // An in-flight download owns the status line.
                if (!window->update_downloading_) {
                  window->SetStatus(t("statusDatabaseConnected"));
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
  auto const weak = get_weak();
  PromptAsync(t("menuNewDatabase"), t("dialogInputListName"), L"",
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
              // The next snapshot must render even if it matches the one the
              // closed database ended with.
              window->has_applied_snapshot_ = false;
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
  auto dialog = mxc::ContentDialog{};
  dialog.Title(winrt::box_value(L"Taskly"));
  dialog.Content(winrt::box_value(t("aboutContent")));
  dialog.CloseButtonText(t("dialogConfirm"));
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
  NormalPane().Visibility(mx::Visibility::Collapsed);
  SearchPane().Visibility(mx::Visibility::Visible);
  RunSearchAsync(keyword);
}

void MainWindow::OnSmartTileClick(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const tag = sender.as<mxc::Button>().Tag();
  auto const kind =
      static_cast<ViewKind>(winrt::unbox_value<std::int32_t>(tag));
  if (view_ == kind) {
    return;
  }
  view_ = kind;
  suppress_selection_ = true;
  UserList().SelectedIndex(-1);
  suppress_selection_ = false;
  RefreshSmartTiles();
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
  suppress_selection_ = false;
  RefreshSmartTiles();
  RenderTasks();
  ReloadTasksAsync();
}

void MainWindow::OnNewList(winrt::Windows::Foundation::IInspectable const&,
                           Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const weak = get_weak();
  PromptAsync(t("dialogCreateList"), t("dialogInputListName"), L"",
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
  auto const weak = get_weak();
  PromptAsync(t("dialogEditList"), t("dialogInputListName"),
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
    CommitQuickAdd();
  }
}

void MainWindow::CommitQuickAdd() {
  auto const text = std::wstring(NewTaskBox().Text());
  NewTaskBox().Text(L"");
  AddTaskAsync(text);
}

void MainWindow::OnQuickAddCommit(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  CommitQuickAdd();
}

void MainWindow::OnNewTaskTextChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&) {
  if (NewTaskBox().Text().empty()) {
    QuickAddPreview().Visibility(mx::Visibility::Collapsed);
    if (preview_timer_) {
      preview_timer_.Stop();
    }
    return;
  }
  RefreshQuickAddPreview();
}

void MainWindow::RefreshQuickAddPreview() {
  // Debounce the parse RPC: one run per 250 ms pause in typing.
  if (!preview_timer_) {
    preview_timer_ = DispatcherQueue().CreateTimer();
    preview_timer_.Interval(std::chrono::milliseconds{250});
    preview_timer_.IsRepeating(false);
    preview_timer_.Tick([weak = get_weak()](auto&&, auto&&) {
      if (auto window = weak.get()) {
        auto const text = std::wstring(window->NewTaskBox().Text());
        if (!text.empty()) {
          window->RunQuickAddPreview(text);
        }
      }
    });
  }
  preview_timer_.Stop();
  preview_timer_.Start();
}

void MainWindow::OnNewTaskFocusChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  QuickAddCard().BorderBrush(ThemeBrush(
      NewTaskBox().FocusState() != mx::FocusState::Unfocused
          ? L"TasklyAccentBrush"
          : L"TasklyDividerBrush"));
}

winrt::fire_and_forget MainWindow::RunQuickAddPreview(std::wstring const& text) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.parse_quick_add_async(
        winrt::to_string(text),
        [dispatcher, weak, text](
            rivet_app::Result<rivet_app::QuickAddParse> result) {
          dispatcher.TryEnqueue([weak, text, result] {
            if (auto window = weak.get()) {
              // Drop stale completions: only the newest text renders.
              if (window->NewTaskBox().Text() != winrt::hstring(text)) {
                return;
              }
              std::wstring label;
              try {
                auto const parse = result.get();
                if (parse.due_date) {
                  label = window->DueLabel(*parse.due_date);
                  if (parse.due_time && !parse.due_time->empty()) {
                    label += L" \u00B7 " + wide(*parse.due_time);
                  }
                }
              } catch (...) {
                label.clear();
              }
              if (label.empty()) {
                window->QuickAddPreview().Visibility(mx::Visibility::Collapsed);
              } else {
                window->QuickAddPreviewText().Text(label);
                window->QuickAddPreview().Visibility(mx::Visibility::Visible);
              }
            }
          });
        });
  } catch (std::exception const&) {
    // Preview is best-effort; commit still parses authoritatively.
  }
}

void MainWindow::OnSidebarToggle(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  sidebar_visible_ = !sidebar_visible_;
  auto const collapsed = !sidebar_visible_;
  auto const columns = BodyGrid().ColumnDefinitions();
  // DESIGN-TOKENS: collapsing releases the column MinWidth too.
  columns.GetAt(0).Width(
      mx::GridLength{collapsed ? 0.0 : 280.0, mx::GridUnitType::Pixel});
  columns.GetAt(0).MinWidth(collapsed ? 0.0 : 200.0);
  SidebarPane().Visibility(collapsed ? mx::Visibility::Collapsed
                                     : mx::Visibility::Visible);
  SidebarDivider().Visibility(collapsed ? mx::Visibility::Collapsed
                                        : mx::Visibility::Visible);
  SidebarToggleGlyph().Glyph(collapsed ? L"\uE76C" : L"\uE76B");
  mxc::ToolTipService::SetToolTip(
      SidebarToggle(),
      winrt::box_value(t(collapsed ? "sidebarShow" : "sidebarHide")));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
      SidebarToggle(), t(collapsed ? "sidebarShow" : "sidebarHide"));
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
  auto const weak = get_weak();
  PromptAsync(t("dialogTaskDetail"), L"", wide(task->text),
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
