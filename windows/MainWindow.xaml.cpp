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
#include <set>
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

// Bootstrap only the visual preferences before Window.Activate(), rather
// than painting the default light theme while the Racket backend starts.
// The backend remains the source of truth and refreshes these settings once
// get_settings completes. Keep this parser consistent with DATA-FORMAT §7.
struct StartupPreferences {
  std::string language{"zh"};
  std::string theme{"system"};
};

std::string ascii_trim(std::string value) {
  auto const first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return {};
  auto const last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

std::string ascii_lower(std::string value) {
  for (auto& c : value) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  }
  return value;
}

StartupPreferences read_startup_preferences() {
  StartupPreferences result;
  std::wstring home;
  // Same Windows home precedence as racket/taskly/paths.rkt.
  for (auto const* variable : {L"USERPROFILE", L"HOME"}) {
    auto const required = ::GetEnvironmentVariableW(variable, nullptr, 0);
    if (required <= 1) continue;
    std::wstring value(required, L'\0');
    auto const length =
        ::GetEnvironmentVariableW(variable, value.data(), required);
    if (length == 0 || length >= required) continue;
    value.resize(length);
    home = std::move(value);
    break;
  }
  if (home.empty()) return result;

  try {
    std::ifstream config(std::filesystem::path(home) / L".taskly" /
                         L"config.ini", std::ios::binary);
    std::string line;
    while (std::getline(config, line)) {
      line = ascii_trim(std::move(line));
      if (line.empty() || line.front() == '#' || line.front() == ';') continue;
      auto const separator = line.find('=');
      if (separator == std::string::npos) continue;
      auto const key = ascii_lower(ascii_trim(line.substr(0, separator)));
      auto const value = ascii_lower(ascii_trim(line.substr(separator + 1)));
      // Match config-language/config-theme: last occurrence wins, and an
      // invalid value falls back to that setting's documented default.
      if (key == "language") {
        result.language = (value == "zh" || value == "en") ? value : "zh";
      } else if (key == "theme") {
        result.theme = (value == "system" || value == "light" ||
                        value == "dark") ? value : "system";
      }
    }
  } catch (std::exception const&) {
    // Missing/unreadable config should never delay or prevent a GUI launch.
  }
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

std::optional<winrt::Windows::Foundation::DateTime> date_time_from_iso(
    std::wstring const& value) {
  int year = 0;
  int month = 0;
  int day = 0;
  if (swscanf_s(value.c_str(), L"%d-%d-%d", &year, &month, &day) != 3 ||
      year < 1900 || year > 2100 || month < 1 || month > 12 || day < 1 ||
      day > 31) {
    return std::nullopt;
  }
  try {
    winrt::Windows::Globalization::Calendar calendar;
    calendar.ChangeCalendarSystem(L"GregorianCalendar");
    // Normalize the current calendar before moving across shorter months.
    calendar.Day(1);
    calendar.Month(1);
    calendar.Year(year);
    calendar.Month(month);
    calendar.Day(day);
    calendar.Hour(12);
    calendar.Minute(0);
    calendar.Second(0);
    calendar.Nanosecond(0);
    return calendar.GetDateTime();
  } catch (...) {
    return std::nullopt;
  }
}

std::wstring iso_from_date_time(
    winrt::Windows::Foundation::DateTime const& value) {
  winrt::Windows::Globalization::Calendar calendar;
  calendar.ChangeCalendarSystem(L"GregorianCalendar");
  calendar.SetDateTime(value);
  wchar_t buffer[11]{};
  swprintf_s(buffer, L"%04d-%02d-%02d", calendar.Year(), calendar.Month(),
             calendar.Day());
  return buffer;
}

int days_until_weekend() {
  SYSTEMTIME local{};
  ::GetLocalTime(&local);
  // Saturday and Sunday both mean the current weekend; weekdays lead to
  // the coming Saturday, matching the product contract.
  if (local.wDayOfWeek == 0 || local.wDayOfWeek == 6) return 0;
  return 6 - static_cast<int>(local.wDayOfWeek);
}

// Lexicographic YYYY-MM-DD compare; malformed dates sort after any date.
// Quick-add stores "yyyy-MM-dd HH:mm:ss" — only the day part compares.
int date_compare(std::string const& due, std::wstring const& today) {
  if (due.size() < 10) {
    return 1;
  }
  return wide(due.substr(0, 10)).compare(today);
}

std::wstring due_tail(std::string const& due) {
  if (due.size() < 10) {
    return wide(due);
  }
  return wide(due.substr(5, 5));
}

std::wstring trim_wide(std::wstring text) {
  auto const first = text.find_first_not_of(L" \t\r\n");
  if (first == std::wstring::npos) return {};
  auto const last = text.find_last_not_of(L" \t\r\n");
  return text.substr(first, last - first + 1);
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
    {"subtitleCompleted", "{0} 个已完成", "{0} completed"},
    {"taskListEmpty", "暂无任务", "No tasks"},
    {"taskListEmptyFirstRun", "在上方添加第一项任务，例如“明天评审计划”",
     "Add your first task above — try “Plan tomorrow”"},
    {"sidebarHide", "隐藏侧边栏", "Hide Sidebar"},
    {"sidebarShow", "显示侧边栏", "Show Sidebar"},
    {"dateTomorrow", "明天", "Tomorrow"},
    {"dateYesterday", "昨天", "Yesterday"},
    {"dialogConfirm", "确定", "OK"},
    {"dialogCancel", "取消", "Cancel"},
    {"dialogClear", "清除", "Clear"},
    {"dialogCreateList", "创建列表", "Create List"},
    {"dialogEditList", "编辑列表", "Edit List"},
    {"dialogInputListName", "请输入列表名称", "Please enter list name"},
    {"dialogTaskDetail", "任务详情", "Task Detail"},
    {"labelDate", "日期", "Date"},
    {"labelTime", "时间", "Time"},
    {"labelAddDate", "添加日期", "Add Date"},
    {"contextMenuDetails", "详细信息", "Details"},
    {"taskDelete", "删除", "Delete"},
    {"listDelete", "删除列表", "Delete List"},
    {"listDeleteConfirm", "确认删除列表", "Confirm Delete List"},
    {"listDeleteConfirmContent", "确定要删除这个列表吗？列表下的所有任务也会被删除，此操作无法撤销。", "Are you sure you want to delete this list? All tasks in it will be deleted. This action cannot be undone."},
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
    {"aboutLicense", "以 GNU AGPL-3.0 授权发布",
     "Released under the GNU AGPL-3.0"},
    {"aboutWebsite", "访问官网", "Website"},
    {"aboutReportIssue", "问题反馈", "Report an Issue"},
    {"updateCopyError", "复制错误信息", "Copy error"},
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
  // PRODUCT-SPEC §2: prefer 1024×768 logical, but keep the whole window
  // inside the current monitor's work area. A literal 1024×768 resize on a
  // 1024×768 desktop extends below the taskbar and Windows may also place the
  // right edge off-screen. That makes header actions inaccessible on a valid,
  // supported display before the user can resize the window.
  auto const window_native = try_as<::IWindowNative>();
  HWND hwnd = nullptr;
  winrt::check_hresult(window_native->get_WindowHandle(&hwnd));
  auto const dpi = ::GetDpiForWindow(hwnd);
  auto const preferred_width =
      1024 * static_cast<std::int32_t>(dpi) / 96;
  auto const preferred_height =
      768 * static_cast<std::int32_t>(dpi) / 96;
  MONITORINFO monitor_info{sizeof(MONITORINFO)};
  auto const monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (monitor != nullptr && ::GetMonitorInfoW(monitor, &monitor_info)) {
    auto const work_width = static_cast<std::int32_t>(
        monitor_info.rcWork.right - monitor_info.rcWork.left);
    auto const work_height = static_cast<std::int32_t>(
        monitor_info.rcWork.bottom - monitor_info.rcWork.top);
    auto const width = (std::min)(preferred_width, work_width);
    auto const height = (std::min)(preferred_height, work_height);
    auto const x = monitor_info.rcWork.left + (work_width - width) / 2;
    auto const y = monitor_info.rcWork.top + (work_height - height) / 2;
    AppWindow().MoveAndResize({x, y, width, height});
  } else {
    AppWindow().Resize({preferred_width, preferred_height});
  }
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
  // Read only language/theme synchronously: the window is not activated
  // yet, so dark-mode users never see a white/English startup frame.
  // Full settings still load via the backend's get_settings_async RPC.
  auto const initial = read_startup_preferences();
  settings_.language = initial.language;
  settings_.theme = initial.theme;
  set_i18n_language(settings_.language);
  SetStatus(t("statusDatabaseNotConnected"));
  ApplyLanguage();
  // Hand-built rows take their brushes from code at build time, so a theme
  // flip must re-render them; the title bar colors ride the same event.
  // Apply the persisted theme before subscribing to theme-change events.
  // RequestedTheme may synchronously trigger ActualThemeChanged; if the
  // handler runs during construction, it re-renders rows before activation.
  // The initial UI already has its XAML controls and language applied.
  ApplyTheme(settings_.theme);
  // Do not reference a resource defined in the same Grid's
  // ThemeDictionaries from the Grid's own XAML attribute: on a cold
  // WinUI launch the forward ThemeResource lookup can surface as an
  // unhandled XAML load exception before the window is created.
  // Resolve the brush only after InitializeComponent + RequestedTheme.
  RootGrid().Background(ThemeBrush(L"TasklySurfaceBrush"));
  RootGrid().ActualThemeChanged(
      [weak = get_weak()](auto&&, auto&&) {
        if (auto window = weak.get()) {
          window->OnEffectiveThemeChanged();
        }
      });
  try {
    // Shell_NotifyIcon is Rivet's first-party notification surface for this
    // unpackaged WinUI host. Failure/denial disables reminders, never startup.
    notification_icon_ = std::make_unique<rivet::system::TrayIcon>(
        hwnd, 2, WM_APP + 43, L"Taskly", ::LoadIconW(nullptr, IDI_APPLICATION));
  } catch (...) {
    notifications_disabled_ = true;
  }
  InstallAppAccelerators();
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

          window->reminder_timer_ = mx::DispatcherTimer();
          window->reminder_timer_.Interval(std::chrono::seconds{60});
          window->reminder_timer_.Tick(
              [window_weak = window->get_weak()](auto&&, auto&&) {
                if (auto current = window_weak.get()) {
                  current->CheckReminders(false);
                }
              });
          window->reminder_timer_.Start();

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
                      // Stamp the install shape so the backend downloads the
                      // matching update flavor (UPDATE.md): MSI installs
                      // upgrade through msiexec, portable zips swap in place.
                      current->SaveSettingAsync(
                          "install-flavor",
                          current->IsMsiInstall() ? "msi" : "zip");
                      // A previous update run may have left a failure report
                      // (shared/spec/UPDATE.md); surface it once, then start
                      // the throttled silent check.
                      current->HandleInstallMarkers();
                      current->OpenDefaultDatabaseAsync();
                      current->LoadAutoCheckUpdatesSetting();
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
// Reminders — shared-core decisions, native Windows delivery
// ---------------------------------------------------------------------------

void MainWindow::CheckReminders(bool startup) {
  if (!database_connected_ || notifications_disabled_ ||
      notification_icon_ == nullptr || backend_ == nullptr ||
      !backend_->running()) {
    return;
  }
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  rivet_app::API api(*backend_);
  (void)api.reminder_decisions_async(
      startup,
      [dispatcher, weak](
          rivet_app::Result<std::vector<rivet_app::ReminderDecision>> result) {
        try {
          auto decisions = result.get();
          dispatcher.TryEnqueue(
              [weak, decisions = std::move(decisions)]() mutable {
                if (auto window = weak.get()) {
                  for (auto& decision : decisions) {
                    window->DeliverReminder(std::move(decision));
                  }
                }
              });
        } catch (...) {
          // A transient backend decision failure does not disable transport.
        }
      });
}

void MainWindow::DeliverReminder(rivet_app::ReminderDecision decision) {
  if (backend_ == nullptr || !backend_->running()) return;
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  rivet_app::API api(*backend_);
  (void)api.acknowledge_reminder_async(
      decision.token, "attempted",
      [dispatcher, weak, decision = std::move(decision)](
          rivet_app::Result<bool> result) mutable {
        bool accepted = false;
        try {
          accepted = result.get();
        } catch (...) {
          return;
        }
        dispatcher.TryEnqueue(
            [weak, accepted, decision = std::move(decision)]() mutable {
              auto window = weak.get();
              if (!window || !accepted || window->backend_ == nullptr) {
                return; // stale decision after a database switch
              }

              std::string outcome{"failed"};
              if (!window->notifications_disabled_ &&
                  window->notification_icon_ != nullptr) {
                try {
                  std::wstring body;
                  if (decision.kind == "summary") {
                    body = tf("reminderStartupSummary",
                              std::to_wstring(decision.count));
                  } else if (decision.task.has_value() &&
                             decision.task->due_date.has_value()) {
                    auto const& task = *decision.task;
                    auto when = wide(*task.due_date);
                    if (task.due_time.has_value()) {
                      when += L" " + wide(*task.due_time);
                    }
                    body = wide(task.text) + L"\n" + t("reminderDueAt") +
                           L": " + when;
                  } else {
                    throw std::runtime_error("malformed reminder decision");
                  }
                  window->notification_icon_->Notify(t("reminderTitle"), body);
                  outcome = "delivered";
                } catch (...) {
                  window->notifications_disabled_ = true;
                }
              }

              rivet_app::API current_api(*window->backend_);
              (void)current_api.acknowledge_reminder_async(
                  decision.token, outcome,
                  [](rivet_app::Result<bool>) {});
            });
      });
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
  // Hint-only: the actual accelerators are installed window-wide in
  // InstallAppAccelerators (these two also have on-menu hints because
  // the File menu rows exist to carry them).
  MenuNewDatabase().KeyboardAcceleratorTextOverride(L"Ctrl+Shift+N");
  MenuOpenDatabase().KeyboardAcceleratorTextOverride(L"Ctrl+O");
  MenuCloseDatabase().Text(t("menuCloseDatabase"));
  MenuExit().Text(t("menuExit"));
  MenuLangZh().Text(t("menuLangZh"));
  MenuLangEn().Text(t("menuLangEn"));
  MenuTheme().Text(t("menuTheme"));
  MenuThemeSystem().Text(t("themeFollowSystem"));
  MenuThemeLight().Text(t("themeLight"));
  MenuThemeDark().Text(t("themeDark"));
  MenuAutoCheckUpdates().Text(t("settingsAutoCheckUpdates"));
  MenuAutoCheckUpdates().IsChecked(auto_check_updates_);
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
  BulkCompleteButton().Content(winrt::box_value(t("bulkComplete")));
  BulkMoveButton().Content(winrt::box_value(t("menuMoveToList")));
  BulkScheduleButton().Content(winrt::box_value(t("bulkSchedule")));
  BulkDeleteButton().Content(winrt::box_value(t("listDelete")));
  UndoDeleteButton().Content(winrt::box_value(t("bannerUndo")));
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
  ApplyTitleBarTheme();
}

// The native title bar follows the app theme using the TasklySidebarBrush
// palette (PRODUCT-SPEC §3 surface), so the frame reads as part of the
// window instead of a stock light strip over a dark UI.
void MainWindow::ApplyTitleBarTheme() {
  auto const dark = RootGrid().ActualTheme() == mx::ElementTheme::Dark;
  auto const background = dark ? winrt::Windows::UI::Color{0xFF, 0x27, 0x24, 0x24}
                               : winrt::Windows::UI::Color{0xFF, 0xF3, 0xF2, 0xF1};
  auto const foreground = dark ? winrt::Windows::UI::Color{0xFF, 0xFF, 0xFF, 0xFF}
                               : winrt::Windows::UI::Color{0xFF, 0x1B, 0x1B, 0x1B};
  auto const muted = dark ? winrt::Windows::UI::Color{0xFF, 0xA8, 0xA5, 0xA3}
                          : winrt::Windows::UI::Color{0xFF, 0x79, 0x77, 0x75};
  auto titleBar = AppWindow().TitleBar();
  // The default title-bar icon renders as a blank placeholder glyph for
  // this MSI install (the exe icon resource is never picked up), which
  // reads as broken. macOS keeps its title bar free of an app icon, so
  // hide the icon and its click-menu for a matching look. Taskbar and
  // Alt-Tab still show the real app icon from the exe resource. On
  // Windows builds older than the IconShowOptions support this is
  // simply ignored.
  titleBar.IconShowOptions(
      winrt::Microsoft::UI::Windowing::IconShowOptions::HideIconAndSystemMenu);
  titleBar.BackgroundColor(background);
  titleBar.ForegroundColor(foreground);
  titleBar.InactiveBackgroundColor(background);
  titleBar.InactiveForegroundColor(muted);
  titleBar.ButtonBackgroundColor(background);
  titleBar.ButtonForegroundColor(foreground);
  titleBar.ButtonInactiveBackgroundColor(background);
  titleBar.ButtonInactiveForegroundColor(muted);
  titleBar.ButtonHoverBackgroundColor(dark ? winrt::Windows::UI::Color{0xFF, 0x33, 0x2F, 0x2F}
                                           : winrt::Windows::UI::Color{0xFF, 0xEB, 0xE9, 0xE7});
}

// Theme flips (OS appearance while following system, or the settings menu)
// must repaint everything whose brushes were fetched from code at build
// time — XAML ThemeResource bindings update themselves, hand-built rows do
// not.
void MainWindow::OnEffectiveThemeChanged() {
  RootGrid().Background(ThemeBrush(L"TasklySurfaceBrush"));
  ApplyTitleBarTheme();
  RenderSidebar();
  RenderTasks();
}

mx::Media::Brush MainWindow::ThemeBrush(wchar_t const* key) {
  return RootGrid().Resources().Lookup(winrt::box_value(key))
      .as<mx::Media::Brush>();
}

// Smart-view chips: refresh glyph/title/count and the checked fill. Per
// DESIGN-TOKENS the saturated view color only ever sits on the glyph; the
// chip itself is neutral surface (+1px divider from XAML) with a quiet
// selection fill while its view is current. Counts always render, including
// zero, so the four-tile grid remains visually balanced.
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
    chip.count.Text(std::to_wstring(chip.value));
    chip.count.Visibility(mx::Visibility::Visible);
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
    // WinUI exposes TextBlock peers to UIA; the surrounding Grid is not
    // reliably in ControlView. Test/assistive clients can find this label.
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        text, L"list-name-" + std::to_wstring(list.id));
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
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        row, L"list-" + std::to_wstring(list.id));
    UserList().Items().Append(row);
    if (view_ == ViewKind::List && view_list_id_ == list.id) {
      UserList().SelectedIndex(UserList().Items().Size() - 1);
    }
  }
}

void MainWindow::RenderTasks() {
  if (inline_task_id_.has_value() && !inline_task_in_search_) {
    CaptureInlineTaskDraft();
    inline_title_box_ = nullptr;
    inline_notes_box_ = nullptr;
    inline_date_box_ = nullptr;
    inline_time_box_ = nullptr;
    inline_list_button_ = nullptr;
  }
  rebuilding_task_rows_ = true;
  struct TaskRowRestore {
    MainWindow* window;
    ~TaskRowRestore() { window->rebuilding_task_rows_ = false; }
  } restore{this};
  PaneTitle().Text(view_title());
  PaneSubtitle().Text(view_subtitle());

  // Preserve selection across changed-event and poll snapshot rebuilds.
  // Selection is by task identity, never by its list index (order can shift).
  std::set<std::int64_t> selected_ids;
  for (auto const& selected : TaskList().SelectedItems()) {
    if (auto row = selected.try_as<mxc::Grid>()) {
      selected_ids.insert(winrt::unbox_value<std::int64_t>(row.Tag()));
    }
  }
  TaskList().Items().Clear();
  for (auto const& task : tasks_) {
    if (suppressed_deleted_task_ids_.count(task.id) != 0) continue;
    auto row = MakeTaskRow(task);
    TaskList().Items().Append(row);
    if (selected_ids.count(task.id) != 0) {
      TaskList().SelectedItems().Append(row);
    }
  }

  // While a search is live its pane replaces the normal one; otherwise the
  // normal pane is the only pane, with the connected-empty state when the
  // view has no rows (PRODUCT-SPEC §5: ✓ + taskListEmpty).
  auto const searching = !current_search_.empty();
  NormalPane().Visibility(searching ? mx::Visibility::Collapsed
                                    : mx::Visibility::Visible);
  SearchPane().Visibility(searching ? mx::Visibility::Visible
                                    : mx::Visibility::Collapsed);
  auto const empty = !searching && TaskList().Items().Size() == 0;
  EmptyState().Visibility(empty ? mx::Visibility::Visible
                                : mx::Visibility::Collapsed);
  if (empty) {
    EmptyStateIcon().Text(L"\u2713");
    EmptyStateText().Text(t("taskListEmptyFirstRun"));
  }
  RefreshBulkActionBar();
}

void MainWindow::RenderSearchResults() {
  if (inline_task_id_.has_value() && inline_task_in_search_) {
    CaptureInlineTaskDraft();
    inline_title_box_ = nullptr;
    inline_notes_box_ = nullptr;
    inline_date_box_ = nullptr;
    inline_time_box_ = nullptr;
    inline_list_button_ = nullptr;
  }
  rebuilding_task_rows_ = true;
  struct SearchRowRestore {
    MainWindow* window;
    ~SearchRowRestore() { window->rebuilding_task_rows_ = false; }
  } restore{this};
  std::set<std::int64_t> selected_ids;
  for (auto const& selected : SearchResults().SelectedItems()) {
    if (auto row = selected.try_as<mxc::Grid>()) {
      selected_ids.insert(winrt::unbox_value<std::int64_t>(row.Tag()));
    }
  }
  SearchResults().Items().Clear();
  for (auto const& task : search_results_) {
    if (suppressed_deleted_task_ids_.count(task.id) != 0) continue;
    auto row = MakeTaskRow(task, /*search_result=*/true);
    SearchResults().Items().Append(row);
    if (selected_ids.count(task.id) != 0) {
      SearchResults().SelectedItems().Append(row);
    }
  }
  RefreshBulkActionBar();
}

mxc::Grid MainWindow::MakeTaskRow(rivet_app::Task const& task,
                                   bool search_result) {
  auto const expanded_here =
      inline_task_id_.has_value() && *inline_task_id_ == task.id &&
      inline_task_in_search_ == search_result;
  auto row = mxc::Grid{};
  row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
  row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
  row.ColumnDefinitions().Append(mxc::ColumnDefinition{});
  row.ColumnDefinitions().GetAt(0).Width(mx::GridLength{0, mx::GridUnitType::Auto});
  row.ColumnDefinitions().GetAt(1).Width(
      mx::GridLength{1, mx::GridUnitType::Star});
  row.ColumnDefinitions().GetAt(2).Width(
      mx::GridLength{0, mx::GridUnitType::Auto});
  // The checkbox and title must be centered in the SAME first row. Metadata
  // and notes (when present) occupy a second row under the title only.
  row.RowDefinitions().Append(mxc::RowDefinition{});
  row.RowDefinitions().Append(mxc::RowDefinition{});
  row.RowDefinitions().Append(mxc::RowDefinition{});
  row.Padding(mx::ThicknessHelper::FromLengths(4, 4, 4, 4));
  row.Tag(winrt::box_value<std::int64_t>(task.id));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
      row, L"task-row-" + std::to_wstring(task.id));

  auto check = mxc::CheckBox{};
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
      check, L"task-complete-" + std::to_wstring(task.id));
  check.IsChecked(task.completed);
  check.MinWidth(0);
  check.VerticalAlignment(mx::VerticalAlignment::Center);
  check.Checked({this, &MainWindow::OnTaskCheckChanged});
  check.Unchecked({this, &MainWindow::OnTaskCheckChanged});
  check.Tag(winrt::box_value<std::int64_t>(task.id));
  mxc::Grid::SetColumn(check, 0);
  mxc::Grid::SetRow(check, 0);
  row.Children().Append(check);

  auto text = mxc::TextBlock{};
  text.Text(wide(task.text));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
      text, L"task-title-" + std::to_wstring(task.id));
  text.FontSize(14);
  text.TextTrimming(mx::TextTrimming::CharacterEllipsis);
  text.Margin(mx::ThicknessHelper::FromLengths(8, 0, 0, 0));
  text.VerticalAlignment(mx::VerticalAlignment::Center);
  mxc::Grid::SetColumn(text, 1);
  mxc::Grid::SetRow(text, 0);
  if (task.completed) {
    text.Foreground(ThemeBrush(L"TasklyMutedTextBrush"));
    text.TextDecorations(
        winrt::Windows::UI::Text::TextDecorations::Strikethrough);
  }
  if (!expanded_here) row.Children().Append(text);

  auto info = mxc::Button{};
  auto info_icon = mxc::FontIcon{};
  info_icon.Glyph(L"\uE946");
  info_icon.FontSize(13);
  info.Content(info_icon);
  info.Padding(mx::ThicknessHelper::FromLengths(6, 2, 6, 2));
  info.MinWidth(28);
  info.Opacity(expanded_here ? 1.0 : 0.55);
  info.VerticalAlignment(mx::VerticalAlignment::Center);
  info.Tag(winrt::box_value<std::int64_t>(task.id));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
      info, L"task-info-" + std::to_wstring(task.id));
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
      info, t("contextMenuDetails"));
  info.Click([weak = get_weak(), id = task.id](auto const&, auto const&) {
    if (auto window = weak.get()) window->OpenInlineTaskEditor(id);
  });
  row.PointerEntered([info](auto const&, auto const&) { info.Opacity(1.0); });
  row.PointerExited([info, expanded_here](auto const&, auto const&) {
    info.Opacity(expanded_here ? 1.0 : 0.55);
  });
  mxc::Grid::SetColumn(info, 2);
  mxc::Grid::SetRow(info, 0);
  row.Children().Append(info);

  auto details = mxc::StackPanel{};
  details.Margin(mx::ThicknessHelper::FromLengths(8, 0, 0, 0));
  details.Spacing(2);
  mxc::Grid::SetColumn(details, 1);
  mxc::Grid::SetRow(details, 1);
  mxc::Grid::SetColumnSpan(details, 2);

  // Meta line (PRODUCT-SPEC §5, DESIGN-TOKENS task row): owning list name
  // with its color dot in the smart views, then the due chip; the notes
  // preview sits beneath.
  auto meta = mxc::StackPanel{};
  meta.Orientation(mxc::Orientation::Horizontal);
  meta.Spacing(8);
  // A search can return tasks from ANY list, even when the sidebar has a
  // named list selected. Show ownership on all search rows to avoid
  // implying a result belongs to the active list.
  if ((search_result || view_ != ViewKind::List) &&
      task.list_name.has_value() && !task.list_name->empty()) {
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
    if (search_result) {
      winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
          list_text, L"task-owner-" + std::to_wstring(task.id));
    }
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
    // Completed dates go quiet on every host; overdue red and the today
    // accent apply to open tasks only, and they are the only two tints —
    // no tomorrow-specific color (mac/Linux don't have one either).
    wchar_t const* brush_key = L"TasklySecondaryTextBrush";
    if (!task.completed) {
      if (compare < 0) {
        brush_key = L"TasklyOverdueBrush";
      } else if (compare == 0) {
        brush_key = L"TasklyDueTodayBrush";
      }
    }
    chip_text.Foreground(ThemeBrush(brush_key));
    meta.Children().Append(chip_text);
  }
  if (meta.Children().Size() > 0) {
    details.Children().Append(meta);
  }

  // Notes preview: single line, ellipsized, muted (PRODUCT-SPEC §5).
  if (task.notes.has_value() && !task.notes->empty()) {
    auto notes_line = mxc::TextBlock{};
    notes_line.Text(wide(*task.notes));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        notes_line, L"task-notes-" + std::to_wstring(task.id));
    notes_line.FontSize(12);
    notes_line.TextTrimming(mx::TextTrimming::CharacterEllipsis);
    notes_line.Foreground(ThemeBrush(L"TasklyMutedTextBrush"));
    details.Children().Append(notes_line);
  }

  if (!expanded_here && details.Children().Size() > 0) {
    row.Children().Append(details);
  }

  if (expanded_here) {
    if (!inline_task_draft_.has_value() ||
        inline_task_draft_->id != task.id) {
      inline_task_draft_ = task;
    }
    auto const& draft = *inline_task_draft_;
    auto editor = mxc::StackPanel{};
    editor.Spacing(2);
    editor.Margin(mx::ThicknessHelper::FromLengths(8, 0, 8, 6));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        editor, L"inline-task-editor-" + std::to_wstring(task.id));
    mxc::Grid::SetColumn(editor, 1);
    mxc::Grid::SetRow(editor, 0);
    mxc::Grid::SetRowSpan(editor, 3);

    auto const transparent = mx::Media::SolidColorBrush{
        winrt::Windows::UI::Color{0x00, 0x00, 0x00, 0x00}};
    auto handle_editor_key =
        [weak = get_weak()](auto const&, auto const& args) {
          if (auto window = weak.get()) {
            if (args.Key() == Windows::System::VirtualKey::Enter) {
              args.Handled(true);
              window->CommitInlineTaskEditor();
            } else if (args.Key() == Windows::System::VirtualKey::Escape) {
              args.Handled(true);
              window->CancelInlineTaskEditor();
            }
          }
        };

    inline_title_box_ = mxc::TextBox{};
    inline_title_box_.Text(wide(draft.text));
    inline_title_box_.FontSize(15);
    inline_title_box_.FontWeight(
        winrt::Microsoft::UI::Text::FontWeights::SemiBold());
    inline_title_box_.AcceptsReturn(false);
    inline_title_box_.TextWrapping(mx::TextWrapping::Wrap);
    inline_title_box_.MaxHeight(72);
    inline_title_box_.Padding(mx::ThicknessHelper::FromLengths(0, 3, 0, 3));
    inline_title_box_.Background(transparent);
    inline_title_box_.BorderBrush(transparent);
    inline_title_box_.BorderThickness(
        mx::ThicknessHelper::FromLengths(0, 0, 0, 0));
    inline_title_box_.UseSystemFocusVisuals(true);
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        inline_title_box_, L"inline-task-title-" + std::to_wstring(task.id));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        inline_title_box_, t("dialogTaskDetail"));
    inline_title_box_.KeyDown(handle_editor_key);
    editor.Children().Append(inline_title_box_);

    inline_notes_box_ = mxc::TextBox{};
    inline_notes_box_.Text(
        draft.notes.has_value() ? wide(*draft.notes) : L"");
    inline_notes_box_.PlaceholderText(t("hintAddNotes"));
    inline_notes_box_.AcceptsReturn(true);
    inline_notes_box_.TextWrapping(mx::TextWrapping::Wrap);
    inline_notes_box_.FontSize(13);
    inline_notes_box_.MinHeight(36);
    inline_notes_box_.MaxHeight(74);
    inline_notes_box_.Padding(mx::ThicknessHelper::FromLengths(0, 2, 0, 2));
    inline_notes_box_.Background(transparent);
    inline_notes_box_.BorderBrush(transparent);
    inline_notes_box_.BorderThickness(
        mx::ThicknessHelper::FromLengths(0, 0, 0, 0));
    inline_notes_box_.UseSystemFocusVisuals(true);
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        inline_notes_box_, L"inline-task-notes-" + std::to_wstring(task.id));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        inline_notes_box_, t("hintAddNotes"));
    inline_notes_box_.KeyDown(handle_editor_key);
    editor.Children().Append(inline_notes_box_);

    // Secondary details stay on one compact action line. Native controls keep
    // their theme/high-contrast visuals; only the title and notes are
    // intentionally borderless to preserve the row's visual hierarchy.
    auto schedule = mxc::Grid{};
    schedule.Margin(mx::ThicknessHelper::FromLengths(0, 4, 0, 0));
    schedule.ColumnSpacing(6);
    for (int index = 0; index < 3; ++index) {
      auto column = mxc::ColumnDefinition{};
      column.Width(mx::GridLength{0, mx::GridUnitType::Auto});
      schedule.ColumnDefinitions().Append(column);
    }
    auto list_column = mxc::ColumnDefinition{};
    list_column.Width(mx::GridLength{1, mx::GridUnitType::Star});
    schedule.ColumnDefinitions().Append(list_column);

    auto date_menu_button = mxc::Button{};
    date_menu_button.Width(32);
    date_menu_button.Height(30);
    date_menu_button.Padding(mx::ThicknessHelper::FromLengths(0, 0, 0, 0));
    auto calendar_icon = mxc::FontIcon{};
    calendar_icon.Glyph(L"\uE787");
    calendar_icon.FontSize(13);
    date_menu_button.Content(calendar_icon);
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        date_menu_button,
        L"inline-task-date-menu-" + std::to_wstring(task.id));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        date_menu_button, t("labelAddDate"));
    auto date_flyout = mxc::Flyout{};
    auto date_panel = mxc::StackPanel{};
    date_panel.Spacing(8);
    date_panel.Padding(mx::ThicknessHelper::FromLengths(10, 10, 10, 10));

    auto quick_dates = mxc::StackPanel{};
    quick_dates.Orientation(mxc::Orientation::Horizontal);
    quick_dates.Spacing(6);
    auto add_quick_date = [&](char const* key, std::wstring value,
                              wchar_t const* automation_suffix) {
      auto option = mxc::Button{};
      option.Content(winrt::box_value(t(key)));
      option.Padding(mx::ThicknessHelper::FromLengths(9, 3, 9, 3));
      winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
          option, L"inline-task-date-" + std::wstring(automation_suffix) +
                      L"-" + std::to_wstring(task.id));
      option.Click([weak = get_weak(), value = std::move(value), date_flyout](
                       auto const&, auto const&) {
        if (auto window = weak.get()) {
          window->inline_date_box_.Text(value);
          date_flyout.Hide();
        }
      });
      quick_dates.Children().Append(option);
    };
    add_quick_date("navToday", date_string(0), L"today");
    add_quick_date("dateTomorrow", date_string(1), L"tomorrow");
    add_quick_date("dateThisWeekend", date_string(days_until_weekend()),
                   L"weekend");
    date_panel.Children().Append(quick_dates);

    auto calendar = mxc::CalendarView{};
    calendar.SelectionMode(mxc::CalendarViewSelectionMode::Single);
    calendar.IsTodayHighlighted(true);
    calendar.MinDate(*date_time_from_iso(L"1900-01-01"));
    calendar.MaxDate(*date_time_from_iso(L"2100-12-31"));
    if (draft.due_date.has_value()) {
      if (auto selected = date_time_from_iso(wide(*draft.due_date))) {
        calendar.SelectedDates().Append(*selected);
      }
    }
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        calendar, L"inline-task-calendar-" + std::to_wstring(task.id));
    calendar.SelectedDatesChanged(
        [weak = get_weak(), date_flyout](
            auto const& sender,
            mxc::CalendarViewSelectedDatesChangedEventArgs const& args) {
          if (args.AddedDates().Size() == 0) return;
          if (auto window = weak.get()) {
            window->inline_date_box_.Text(
                iso_from_date_time(args.AddedDates().GetAt(0)));
            date_flyout.Hide();
          }
        });
    date_panel.Children().Append(calendar);

    auto clear_date = mxc::Button{};
    clear_date.Content(winrt::box_value(t("dialogClear")));
    clear_date.HorizontalAlignment(mx::HorizontalAlignment::Right);
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        clear_date, L"inline-task-date-clear-" + std::to_wstring(task.id));
    clear_date.Click([weak = get_weak(), date_flyout](auto const&, auto const&) {
      if (auto window = weak.get()) {
        window->inline_date_box_.Text(L"");
        window->inline_time_box_.Text(L"");
        date_flyout.Hide();
      }
    });
    date_panel.Children().Append(clear_date);
    date_flyout.Content(date_panel);
    date_menu_button.Flyout(date_flyout);
    mxc::Grid::SetColumn(date_menu_button, 0);
    schedule.Children().Append(date_menu_button);

    inline_date_box_ = mxc::TextBox{};
    inline_date_box_.Width(112);
    inline_date_box_.Height(30);
    inline_date_box_.FontSize(12);
    inline_date_box_.Padding(mx::ThicknessHelper::FromLengths(8, 2, 8, 2));
    inline_date_box_.PlaceholderText(L"yyyy-MM-dd");
    inline_date_box_.Text(draft.due_date.has_value()
                              ? wide(*draft.due_date).substr(0, 10)
                              : L"");
    inline_date_box_.UseSystemFocusVisuals(true);
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        inline_date_box_, L"inline-task-date-" + std::to_wstring(task.id));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        inline_date_box_, t("labelDate"));
    inline_date_box_.KeyDown(handle_editor_key);
    mxc::Grid::SetColumn(inline_date_box_, 1);
    schedule.Children().Append(inline_date_box_);

    inline_time_box_ = mxc::TextBox{};
    inline_time_box_.Width(72);
    inline_time_box_.Height(30);
    inline_time_box_.FontSize(12);
    inline_time_box_.Padding(mx::ThicknessHelper::FromLengths(8, 2, 8, 2));
    inline_time_box_.PlaceholderText(L"HH:mm");
    inline_time_box_.Text(draft.due_time.has_value()
                              ? wide(*draft.due_time).substr(0, 5)
                              : L"");
    inline_time_box_.UseSystemFocusVisuals(true);
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        inline_time_box_, L"inline-task-time-" + std::to_wstring(task.id));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        inline_time_box_, t("labelTime"));
    inline_time_box_.KeyDown(handle_editor_key);
    mxc::Grid::SetColumn(inline_time_box_, 2);
    schedule.Children().Append(inline_time_box_);

    inline_list_button_ = mxc::Button{};
    inline_list_button_.Height(30);
    inline_list_button_.MinWidth(96);
    inline_list_button_.MaxWidth(180);
    inline_list_button_.HorizontalAlignment(mx::HorizontalAlignment::Stretch);
    inline_list_button_.HorizontalContentAlignment(
        mx::HorizontalAlignment::Left);
    inline_list_button_.Padding(
        mx::ThicknessHelper::FromLengths(9, 2, 9, 2));
    auto list_caption = [&](rivet_app::TodoList const* list) {
      if (list == nullptr) {
        return draft.list_name.has_value() ? wide(*draft.list_name)
                                           : std::wstring(
                                                 t("menuMoveToList").c_str());
      }
      auto caption = wide(list->name);
      if (list->icon.has_value() && !list->icon->empty()) {
        caption = wide(*list->icon) + L"  " + caption;
      }
      return caption;
    };
    inline_list_button_.Content(winrt::box_value(
        list_caption(find_by_id(lists_, draft.list_id))));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        inline_list_button_,
        L"inline-task-list-" + std::to_wstring(task.id));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        inline_list_button_, t("menuMoveToList"));
    auto list_menu = mxc::MenuFlyout{};
    for (auto const& list : lists_) {
      auto option = mxc::MenuFlyoutItem{};
      auto const caption = list_caption(&list);
      option.Text(caption);
      auto const target_id = list.id;
      auto const target_name = list.name;
      option.Click([weak = get_weak(), target_id, target_name, caption](
                       auto const&, auto const&) {
        if (auto window = weak.get();
            window && window->inline_task_draft_.has_value()) {
          window->inline_task_draft_->list_id = target_id;
          window->inline_task_draft_->list_name = target_name;
          if (window->inline_list_button_) {
            window->inline_list_button_.Content(winrt::box_value(caption));
          }
        }
      });
      list_menu.Items().Append(option);
    }
    inline_list_button_.Flyout(list_menu);
    mxc::Grid::SetColumn(inline_list_button_, 3);
    schedule.Children().Append(inline_list_button_);

    editor.Children().Append(schedule);

    // Keep Return/Escape and click-away, while making the primary commit and
    // cancel actions visible after a user changes the date.
    auto actions = mxc::StackPanel{};
    actions.Orientation(mxc::Orientation::Horizontal);
    actions.Spacing(8);
    actions.HorizontalAlignment(mx::HorizontalAlignment::Right);
    actions.Margin(mx::ThicknessHelper::FromLengths(0, 6, 0, 0));

    auto cancel_edit = mxc::Button{};
    cancel_edit.Content(winrt::box_value(t("dialogCancel")));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        cancel_edit, L"inline-task-cancel-" + std::to_wstring(task.id));
    cancel_edit.Click([weak = get_weak()](auto const&, auto const&) {
      if (auto window = weak.get()) window->CancelInlineTaskEditor();
    });
    actions.Children().Append(cancel_edit);

    auto save_edit = mxc::Button{};
    save_edit.Content(winrt::box_value(t("dialogSave")));
    winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
        save_edit, L"inline-task-save-" + std::to_wstring(task.id));
    save_edit.Click([weak = get_weak()](auto const&, auto const&) {
      if (auto window = weak.get()) window->CommitInlineTaskEditor();
    });
    actions.Children().Append(save_edit);
    editor.Children().Append(actions);
    row.Children().Append(editor);
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

  // The same Move to List operation is available on macOS. It also lets
  // users correct tasks created by older Windows builds that incorrectly
  // defaulted every quick add to the first list.
  if (lists_.size() > 1) {
    auto move_to = mxc::MenuFlyoutSubItem{};
    move_to.Text(t("menuMoveToList"));
    for (auto const& list : lists_) {
      if (list.id == task.list_id) continue;
      auto target = mxc::MenuFlyoutItem{};
      target.Text(wide(list.icon.value_or("")) + L" " + wide(list.name));
      auto const task_id = task.id;
      auto const target_id = list.id;
      target.Click(
          [weak = get_weak(), task_id, target_id](
              winrt::Windows::Foundation::IInspectable const&,
              Microsoft::UI::Xaml::RoutedEventArgs const&) {
            if (auto window = weak.get()) {
              window->MoveTaskToListAsync(task_id, target_id);
            }
          });
      move_to.Items().Append(target);
    }
    menu.Items().Append(move_to);
  }
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

void MainWindow::RefreshSearchIfActive() {
  if (!current_search_.empty()) RunSearchAsync(current_search_);
}

rivet_app::Task const* MainWindow::FindTaskForAction(
    std::int64_t id) const {
  // The search pane has an independent, global result set. Its tasks may
  // not be part of the currently selected list's filtered snapshot.
  if (!current_search_.empty()) {
    if (auto const* task = find_by_id(search_results_, id)) return task;
  }
  return find_by_id(tasks_, id);
}

void MainWindow::CaptureInlineTaskDraft() {
  if (!inline_task_draft_.has_value() || !inline_title_box_) return;
  auto& draft = *inline_task_draft_;
  draft.text = winrt::to_string(trim_wide(std::wstring(inline_title_box_.Text())));
  auto const notes = trim_wide(std::wstring(inline_notes_box_.Text()));
  draft.notes = notes.empty()
                    ? std::nullopt
                    : std::optional<std::string>(winrt::to_string(notes));
  auto const date = trim_wide(std::wstring(inline_date_box_.Text()));
  auto const time = trim_wide(std::wstring(inline_time_box_.Text()));
  draft.due_date = date.empty()
                       ? std::nullopt
                       : std::optional<std::string>(winrt::to_string(date));
  draft.due_time = date.empty() || time.empty()
                       ? std::nullopt
                       : std::optional<std::string>(winrt::to_string(time));
}

void MainWindow::ResetInlineTaskEditor() {
  inline_task_id_.reset();
  inline_task_draft_.reset();
  inline_task_in_search_ = false;
  inline_title_box_ = nullptr;
  inline_notes_box_ = nullptr;
  inline_date_box_ = nullptr;
  inline_time_box_ = nullptr;
  inline_list_button_ = nullptr;
}

void MainWindow::OpenInlineTaskEditor(std::int64_t id) {
  if (inline_task_id_.has_value() && *inline_task_id_ == id) {
    CommitInlineTaskEditor();
    return;
  }
  if (inline_task_id_.has_value()) CommitInlineTaskEditor();
  auto const* task = FindTaskForAction(id);
  if (task == nullptr) return;
  inline_task_id_ = id;
  inline_task_draft_ = *task;
  inline_task_in_search_ = !current_search_.empty();
  RenderTasks();
  RenderSearchResults();
  if (inline_title_box_) {
    inline_title_box_.Focus(mx::FocusState::Programmatic);
    inline_title_box_.SelectAll();
  }
}

void MainWindow::CommitInlineTaskEditor() {
  if (!inline_task_id_.has_value() || !inline_task_draft_.has_value()) return;
  CaptureInlineTaskDraft();
  auto updated = *inline_task_draft_;
  auto const* stored = FindTaskForAction(updated.id);
  if (trim_wide(wide(updated.text)).empty() && stored != nullptr) {
    updated.text = stored->text;
  }
  auto const changed =
      stored == nullptr || updated.text != stored->text ||
      updated.notes != stored->notes || updated.due_date != stored->due_date ||
      updated.due_time != stored->due_time ||
      updated.list_id != stored->list_id;
  ResetInlineTaskEditor();
  RenderTasks();
  RenderSearchResults();
  if (changed) {
    SetStatus(t("statusTaskSaving"));
    // Retain the whole draft until the backend acknowledges persistence.
    // A failed save reopens the editor instead of discarding user input.
    UpdateTaskAsync(updated, updated);
  }
}

void MainWindow::CancelInlineTaskEditor() {
  if (!inline_task_id_.has_value()) return;
  ResetInlineTaskEditor();
  RenderTasks();
  RenderSearchResults();
  SetStatus(t("statusTaskEditCancelled"));
}

winrt::hstring MainWindow::DueLabel(std::string const& due_date) const {
  auto const today = date_string(0);
  auto const compare = date_compare(due_date, today);
  if (compare == 0) {
    return winrt::hstring(t("navToday"));
  }
  if (compare < 0) {
    // Only the adjacent day gets the relative word; older dates fall
    // through to the short date (mac parity).
    if (date_compare(due_date, date_string(-1)) == 0) {
      return winrt::hstring(t("dateYesterday"));
    }
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
  winrt::Microsoft::UI::Xaml::Automation::AutomationProperties::SetAutomationId(
      input, L"prompt-input");
  input.PlaceholderText(placeholder);
  input.Text(initial);
  // The system focus indicator (blue outline + white inner frame) clashes
  // with the card-style inputs; the focused border does the talking.
  input.UseSystemFocusVisuals(false);

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
        [dispatcher, weak, view_kind, list_id, include_completed](
            rivet_app::Result<rivet_app::Snapshot> result) {
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
            dispatcher.TryEnqueue(
                [weak, snapshot, view_kind, list_id, include_completed] {
              if (auto window = weak.get()) {
                // The user may switch lists while this RPC is in flight:
                // never paint a Work snapshot under the Life heading.
                if (window->view_ != view_kind ||
                    window->view_list_id_ != list_id ||
                    window->show_completed_ != include_completed) {
                  window->ReloadTasksAsync();
                  return;
                }
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
  // Pending deletions must never commit against another database that
  // happens to contain the same numeric task IDs.
  if (!pending_delete_ids_.empty()) UndoPendingDeletion();
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
                window->suppressed_deleted_task_ids_.clear();
                // Restore the last-selected list when it still exists —
                // checked against the incoming snapshot because ApplySnapshot
                // owns the render pass.
                auto const restored = window->settings_.last_selected_list_id;
                if (restored > 0 &&
                    find_by_id(snapshot.lists, restored) != nullptr) {
                  window->view_ = MainWindow::ViewKind::List;
                  window->view_list_id_ = restored;
                } else {
                  window->view_ = MainWindow::ViewKind::All;
                  window->view_list_id_ = 0;
                }
                // open_database returns an ALL-view snapshot. Never show
                // those rows under a restored named-list heading: wait for
                // the filtered list snapshot instead.
                if (window->view_ == MainWindow::ViewKind::List) {
                  window->has_applied_snapshot_ = false;
                  window->current_counts_ = snapshot.counts;
                  window->lists_ = snapshot.lists;
                  window->tasks_.clear();
                  window->RenderSidebar();
                  window->RenderTasks();
                  window->ReloadTasksAsync();
                } else {
                  // Opening another DB invalidates the previous fingerprint.
                  window->ApplySnapshot(snapshot, /*force=*/true);
                }
                window->database_connected_ = true;
                window->CheckReminders(true);
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

winrt::fire_and_forget MainWindow::AddTaskAsync(std::wstring const& text,
                                               std::int64_t target_list_id) {
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
        [dispatcher, weak, backend, text, target_list_id](rivet_app::Result<rivet_app::QuickAddParse> parsed) {
          try {
            auto const parse = parsed.get();
            rivet_app::API api(*backend);
            // `changed` triggers the authoritative reload; the completion
            // only surfaces failures.
            (void)api.add_task_async(
                parse.text, std::optional<std::int64_t>(target_list_id),
                parse.due_date, parse.due_time, std::nullopt,
                [dispatcher, weak, text](rivet_app::Result<rivet_app::Task> result) {
                  try {
                    result.get();
                  } catch (std::exception const& e) {
                    auto message = std::string(e.what());
                    dispatcher.TryEnqueue([weak, text, message = std::move(message)] {
                      if (auto window = weak.get()) {
                        // Never replace a newer draft typed while the RPC ran.
                        if (window->NewTaskBox().Text().empty()) {
                          window->NewTaskBox().Text(text);
                        }
                        window->SetError(message);
                      }
                    });
                  }
                });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, text, message = std::move(message)] {
              if (auto window = weak.get()) {
                if (window->NewTaskBox().Text().empty()) {
                  window->NewTaskBox().Text(text);
                }
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    if (NewTaskBox().Text().empty()) {
      NewTaskBox().Text(text);
    }
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
            dispatcher.TryEnqueue([weak] {
              if (auto window = weak.get()) window->RefreshSearchIfActive();
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
            dispatcher.TryEnqueue([weak] {
              if (auto window = weak.get()) window->RefreshSearchIfActive();
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

winrt::fire_and_forget MainWindow::SetTaskDueAsync(std::int64_t id,
                                                   std::wstring const& due) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  // Start from the stored task so untouched fields survive update_task.
  auto const* stored = FindTaskForAction(id);
  if (stored == nullptr) {
    co_return;
  }
  auto updated = *stored;
  updated.due_date =
      due.empty() ? std::nullopt
                  : std::optional<std::string>(winrt::to_string(due));
  // A date-less task cannot retain an invisible due time. Match Linux
  // date-clear semantics and the shared "clear schedule" contract.
  if (due.empty()) updated.due_time = std::nullopt;
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.update_task_async(
        updated, [dispatcher, weak](rivet_app::Result<rivet_app::Task> result) {
          try {
            result.get();
            dispatcher.TryEnqueue([weak] {
              if (auto window = weak.get()) window->RefreshSearchIfActive();
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

winrt::fire_and_forget MainWindow::UpdateTaskAsync(
    rivet_app::Task task,
    std::optional<rivet_app::Task> restore_on_failure) {
  if (backend_ == nullptr || !backend_->running()) co_return;
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.update_task_async(
        std::move(task),
        [dispatcher, weak,
         restore_on_failure = std::move(restore_on_failure)](
            rivet_app::Result<rivet_app::Task> result) {
          try {
            result.get();
            dispatcher.TryEnqueue([weak] {
              if (auto window = weak.get()) {
                window->SetStatus(t("statusTaskUpdated"));
                window->RefreshSearchIfActive();
              }
            });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, message = std::move(message),
                                   restore_on_failure]() mutable {
              if (auto window = weak.get()) {
                if (restore_on_failure.has_value() &&
                    !window->inline_task_id_.has_value()) {
                  window->inline_task_id_ = restore_on_failure->id;
                  window->inline_task_draft_ = *restore_on_failure;
                  window->inline_task_in_search_ =
                      !window->current_search_.empty();
                  window->RenderTasks();
                  window->RenderSearchResults();
                  if (window->inline_title_box_) {
                    window->inline_title_box_.Focus(
                        mx::FocusState::Programmatic);
                  }
                }
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    SetError(e.what());
  }
}

winrt::fire_and_forget MainWindow::MoveTaskToListAsync(
    std::int64_t id, std::int64_t target_list_id) {
  if (backend_ == nullptr || !backend_->running()) {
    co_return;
  }
  auto const* stored = FindTaskForAction(id);
  auto const* destination = find_by_id(lists_, target_list_id);
  if (stored == nullptr || destination == nullptr ||
      stored->list_id == target_list_id) {
    co_return;
  }
  // Keep title, due date, time, completed state and notes unchanged.
  auto updated = *stored;
  updated.list_id = target_list_id;
  auto const list_name = wide(destination->name);
  auto const dispatcher = DispatcherQueue();
  auto const weak = get_weak();
  auto backend = backend_;
  try {
    rivet_app::API api(*backend);
    (void)api.update_task_async(
        updated, [dispatcher, weak, list_name](
                     rivet_app::Result<rivet_app::Task> result) {
          try {
            result.get();
            dispatcher.TryEnqueue([weak, list_name] {
              if (auto window = weak.get()) {
                window->SetStatus(tf("statusTaskMoved", list_name));
                window->RefreshSearchIfActive();
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
        id, [dispatcher, weak, id](rivet_app::Result<bool> result) {
          try {
            if (!result.get()) {
              throw std::runtime_error("task deletion was not acknowledged");
            }
            dispatcher.TryEnqueue([weak] {
              if (auto window = weak.get()) window->RefreshSearchIfActive();
            });
          } catch (std::exception const& e) {
            auto message = std::string(e.what());
            dispatcher.TryEnqueue([weak, id, message = std::move(message)] {
              if (auto window = weak.get()) {
                window->suppressed_deleted_task_ids_.erase(id);
                window->RenderTasks();
                window->RenderSearchResults();
                window->SetError(message);
              }
            });
          }
        });
  } catch (std::exception const& e) {
    suppressed_deleted_task_ids_.erase(id);
    RenderTasks();
    RenderSearchResults();
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
            // SaveSettingAsync is a persistence acknowledgement, not a fresh
            // snapshot of the UI's current intent. Each caller already
            // updates its own language/theme/selected-list state before the
            // RPC, and another setting may change while this call is running.
            // Applying the whole returned struct here can roll those newer
            // values back when callbacks arrive out of order.
            (void)result.get();
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
  if (!pending_delete_ids_.empty()) UndoPendingDeletion();
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
              window->suppressed_deleted_task_ids_.clear();
              window->current_counts_ = {};
              // The next snapshot must render even if it matches the one the
              // closed database ended with.
              window->has_applied_snapshot_ = false;
              window->database_connected_ = false;
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
  auto panel = mxc::StackPanel{};
  panel.Spacing(4);
  auto copyright = mxc::TextBlock{};
  copyright.Text(L"© 2026 Taskly Team");
  copyright.TextAlignment(mx::TextAlignment::Center);
  copyright.FontSize(12);
  copyright.Opacity(0.75);
  panel.Children().Append(copyright);
  auto tagline = mxc::TextBlock{};
  tagline.Text(t("aboutContent"));
  tagline.TextAlignment(mx::TextAlignment::Center);
  tagline.Margin({0, 0, 0, 8});
  auto license = mxc::TextBlock{};
  license.Text(t("aboutLicense"));
  license.TextAlignment(mx::TextAlignment::Center);
  license.FontSize(12);
  license.Opacity(0.75);
  auto website = mxc::HyperlinkButton{};
  website.Content(winrt::box_value(t("aboutWebsite")));
  website.NavigateUri(winrt::Windows::Foundation::Uri{
      L"https://taskly.jrtx.site"});
  website.HorizontalAlignment(mx::HorizontalAlignment::Center);
  website.Padding({0, 0, 0, 0});
  auto manual = mxc::HyperlinkButton{};
  manual.Content(winrt::box_value(t("aboutManual")));
  manual.NavigateUri(winrt::Windows::Foundation::Uri{
      L"https://taskly.jrtx.site/manual.html"});
  manual.HorizontalAlignment(mx::HorizontalAlignment::Center);
  manual.Padding({0, 0, 0, 0});
  auto changelog = mxc::HyperlinkButton{};
  changelog.Content(winrt::box_value(t("aboutChangelog")));
  changelog.NavigateUri(winrt::Windows::Foundation::Uri{
      L"https://github.com/turinglambdaai/taskly/blob/main/CHANGELOG.md"});
  changelog.HorizontalAlignment(mx::HorizontalAlignment::Center);
  changelog.Padding({0, 0, 0, 0});
  auto issue = mxc::HyperlinkButton{};
  issue.Content(winrt::box_value(t("aboutReportIssue")));
  issue.NavigateUri(winrt::Windows::Foundation::Uri{
      L"https://github.com/turinglambdaai/taskly/issues"});
  issue.HorizontalAlignment(mx::HorizontalAlignment::Center);
  issue.Padding({0, 0, 0, 0});
  // Diagnostics block (PRODUCT-SPEC §8): the release identity and the
  // ~/.taskly contract paths a bug report starts from. Labels are English
  // fixed strings — machine-oriented like the CLI's --json.
  std::wstring profile;
  wchar_t profile_buf[MAX_PATH];
  const DWORD profile_len = GetEnvironmentVariableW(
      L"USERPROFILE", profile_buf, MAX_PATH);
  if (profile_len > 0 && profile_len < MAX_PATH) {
    profile.assign(profile_buf, profile_len);
  }
  const std::wstring diagnostics =
      std::wstring(L"Taskly v") + wide(rivet_app::kVersion) +
      L" (Windows, x64)\nDatabase: " + profile + L"\\.taskly\\tasks.db" +
      L"\nConfig: " + profile + L"\\.taskly\\config.ini";
  auto diagnostics_text = mxc::TextBlock{};
  diagnostics_text.Text(diagnostics);
  diagnostics_text.FontFamily(mx::Media::FontFamily{L"Consolas"});
  diagnostics_text.FontSize(11);
  diagnostics_text.Margin({0, 8, 0, 0});
  diagnostics_text.IsTextSelectionEnabled(true);
  auto copy_diagnostics = mxc::Button{};
  copy_diagnostics.Content(winrt::box_value(t("aboutCopyDiagnostics")));
  copy_diagnostics.HorizontalAlignment(mx::HorizontalAlignment::Center);
  copy_diagnostics.Padding({12, 4, 12, 4});
  copy_diagnostics.Click(
      [text = winrt::weak_ref<mxc::Button>(copy_diagnostics), diagnostics](
          auto&&, auto&&) {
        auto package =
            winrt::Windows::ApplicationModel::DataTransfer::DataPackage{};
        package.RequestedOperation(
            winrt::Windows::ApplicationModel::DataTransfer::
                DataPackageOperation::Copy);
        package.SetText(diagnostics);
        winrt::Windows::ApplicationModel::DataTransfer::Clipboard::SetContent(
            package);
        if (auto button = text.get()) {
          button.Content(winrt::box_value(t("statusDiagnosticsCopied")));
          auto restore = mx::DispatcherTimer();
          restore.Interval(std::chrono::milliseconds{2500});
          restore.Tick([restore, text](auto&&, auto&&) {
            if (auto b = text.get()) {
              b.Content(winrt::box_value(t("aboutCopyDiagnostics")));
            }
            restore.Stop();
          });
          restore.Start();
        }
      });
  panel.Children().Append(tagline);
  panel.Children().Append(license);
  panel.Children().Append(website);
  panel.Children().Append(manual);
  panel.Children().Append(changelog);
  panel.Children().Append(issue);
  panel.Children().Append(diagnostics_text);
  panel.Children().Append(copy_diagnostics);

  auto dialog = mxc::ContentDialog{};
  dialog.Title(winrt::box_value(L"Taskly v" + wide(rivet_app::kVersion)));
  dialog.Content(winrt::box_value(panel));
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
  if (inline_task_id_.has_value() && keyword != current_search_) {
    CommitInlineTaskEditor();
  }
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
  SwitchSmartView(kind);
}

void MainWindow::SwitchSmartView(ViewKind kind) {
  if (view_ == kind) {
    return;
  }
  if (inline_task_id_.has_value()) CommitInlineTaskEditor();
  view_ = kind;
  suppress_selection_ = true;
  UserList().SelectedIndex(-1);
  suppress_selection_ = false;
  RefreshSmartTiles();
  RenderTasks();
  ReloadTasksAsync();
}

// Ctrl+Shift+C mirrors the checkbox without double-firing its handler:
// a programmatic IsChecked change raises Checked/Unchecked in WinUI, so
// the handler applies the state first and this only finishes the job if
// the event never ran.
void MainWindow::ToggleShowCompleted() {
  auto const boxed = ShowCompletedCheck().IsChecked();
  bool const on = !(boxed != nullptr && boxed.Value());
  ShowCompletedCheck().IsChecked(on);
  if (show_completed_ == on) return;
  show_completed_ = on;
  ReloadTasksAsync();
}

// PRODUCT-SPEC §8: the accelerators work window-wide without opening the
// menu. KeyboardAccelerators are scoped to the attached element's
// XamlRoot, so RootGrid covers the whole window; each accelerator calls
// the same code path its on-screen control uses.
void MainWindow::InstallAppAccelerators() {
  using winrt::Microsoft::UI::Xaml::Input::KeyboardAccelerator;
  using winrt::Windows::System::VirtualKey;
  auto const control = winrt::Windows::System::VirtualKeyModifiers::Control;
  auto const control_shift =
      control | winrt::Windows::System::VirtualKeyModifiers::Shift;
  auto attach = [&](VirtualKey key,
                    winrt::Windows::System::VirtualKeyModifiers mods,
                    auto&& invoked) {
    KeyboardAccelerator acc{};
    acc.Modifiers(mods);
    acc.Key(key);
    acc.Invoked([invoked](auto const&,
                          winrt::Microsoft::UI::Xaml::Input::
                              KeyboardAcceleratorInvokedEventArgs const&
                                  args) {
      args.Handled(true);
      invoked();
    });
    RootGrid().KeyboardAccelerators().Append(acc);
  };
  attach(VirtualKey::Number1, control,
         [this] { SwitchSmartView(ViewKind::Today); });
  attach(VirtualKey::Number2, control,
         [this] { SwitchSmartView(ViewKind::Planned); });
  attach(VirtualKey::Number3, control,
         [this] { SwitchSmartView(ViewKind::All); });
  attach(VirtualKey::Number4, control,
         [this] { SwitchSmartView(ViewKind::Completed); });
  attach(VirtualKey::N, control, [this] {
    if (inline_task_id_.has_value()) CommitInlineTaskEditor();
    NewTaskBox().Focus(winrt::Microsoft::UI::Xaml::FocusState::Keyboard);
  });
  attach(VirtualKey::F, control,
         [this] { SearchBox().Focus(winrt::Microsoft::UI::Xaml::FocusState::Keyboard); });
  attach(VirtualKey::C, control_shift, [this] { ToggleShowCompleted(); });
  attach(VirtualKey::N, control_shift, [this] {
    Microsoft::UI::Xaml::RoutedEventArgs args;
    OnNewDatabase(nullptr, args);
  });
  attach(VirtualKey::O, control, [this] {
    Microsoft::UI::Xaml::RoutedEventArgs args;
    OnOpenDatabase(nullptr, args);
  });
}

void MainWindow::OnUserListSelectionChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
  if (suppress_selection_ || UserList().SelectedIndex() < 0) {
    return;
  }
  if (inline_task_id_.has_value()) CommitInlineTaskEditor();
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
  ConfirmDeleteListAsync(id);
}

// Deleting a list cascades to every task in it with no undo — macOS and
// Linux both confirm first; Windows must too (the audit's only P0).
winrt::fire_and_forget MainWindow::ConfirmDeleteListAsync(std::int64_t id) {
  auto dialog = mxc::ContentDialog{};
  dialog.Title(winrt::box_value(t("listDeleteConfirm")));
  dialog.Content(winrt::box_value(t("listDeleteConfirmContent")));
  dialog.PrimaryButtonText(t("dialogConfirm"));
  dialog.CloseButtonText(t("dialogCancel"));
  // Safe default: closing the dialog must never mean "delete".
  dialog.DefaultButton(mxc::ContentDialogButton::Close);
  dialog.XamlRoot(Content().XamlRoot());

  auto const result = co_await dialog.ShowAsync();
  if (result != mxc::ContentDialogResult::Primary) {
    co_return;
  }
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

std::vector<std::int64_t> MainWindow::SelectedTaskIds() {
  // Capture task identity before starting any asynchronous mutations:
  // a changed event may re-render the view before the final RPC completes.
  auto list = current_search_.empty() ? TaskList() : SearchResults();
  std::vector<std::int64_t> ids;
  for (auto const& selected : list.SelectedItems()) {
    if (auto row = selected.try_as<mxc::Grid>()) {
      ids.push_back(winrt::unbox_value<std::int64_t>(row.Tag()));
    }
  }
  return ids;
}

void MainWindow::RefreshBulkActionBar() {
  auto const ids = SelectedTaskIds();
  BulkActionBar().Visibility(
      ids.size() > 1 ? mx::Visibility::Visible : mx::Visibility::Collapsed);
  if (ids.size() > 1) {
    BulkSelectionCount().Text(tf("bulkSelectedCount",
                                 std::to_wstring(ids.size())));
    BulkMoveButton().IsEnabled(lists_.size() > 1);
  }
}

void MainWindow::OnTaskSelectionChanged(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const& args) {
  if (rebuilding_task_rows_) return;
  if (inline_task_id_.has_value()) {
    for (auto const& added : args.AddedItems()) {
      if (auto row = added.try_as<mxc::Grid>()) {
        auto const id = winrt::unbox_value<std::int64_t>(row.Tag());
        if (id != *inline_task_id_) {
          CommitInlineTaskEditor();
          break;
        }
      }
    }
  }
  RefreshBulkActionBar();
}

void MainWindow::OnBulkCompleteClicked(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  for (auto id : SelectedTaskIds()) {
    if (auto const* task = FindTaskForAction(id)) {
      if (!task->completed) ToggleTaskAsync(id, true);
    }
  }
}

void MainWindow::MoveSelectedTasks(std::vector<std::int64_t> const& ids,
                                   std::int64_t target_list_id) {
  for (auto const id : ids) {
    if (auto const* task = FindTaskForAction(id)) {
      if (task->list_id != target_list_id) {
        MoveTaskToListAsync(id, target_list_id);
      }
    }
  }
}

void MainWindow::OnBulkMoveClicked(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const ids = SelectedTaskIds();
  if (ids.size() < 2) return;
  auto menu = mxc::MenuFlyout{};
  for (auto const& list : lists_) {
    auto target = mxc::MenuFlyoutItem{};
    target.Text(wide(list.icon.value_or("")) + L" " + wide(list.name));
    auto const id = list.id;
    target.Click([weak = get_weak(), id, ids](
                     winrt::Windows::Foundation::IInspectable const&,
                     Microsoft::UI::Xaml::RoutedEventArgs const&) {
      if (auto window = weak.get()) window->MoveSelectedTasks(ids, id);
    });
    menu.Items().Append(target);
  }
  menu.ShowAt(BulkMoveButton());
}

void MainWindow::ScheduleSelectedTasks(
    std::vector<std::int64_t> const& ids, std::wstring const& due) {
  // Freeze the selection when opening the flyout, not when an asynchronous
  // view refresh eventually invokes a menu callback.
  for (auto const id : ids) {
    if (FindTaskForAction(id) != nullptr) {
      SetTaskDueAsync(id, due);
    }
  }
}

void MainWindow::OnBulkScheduleClicked(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const ids = SelectedTaskIds();
  if (ids.size() < 2) return;
  auto menu = mxc::MenuFlyout{};
  auto const weak = get_weak();
  auto add_option = [&](std::wstring const& text,
                        std::wstring const& due) {
    auto option = mxc::MenuFlyoutItem{};
    option.Text(text);
    option.Click([weak, ids, due](
                     winrt::Windows::Foundation::IInspectable const&,
                     Microsoft::UI::Xaml::RoutedEventArgs const&) {
      if (auto window = weak.get()) {
        window->ScheduleSelectedTasks(ids, due);
      }
    });
    menu.Items().Append(option);
  };
  add_option(t("navToday"), date_string(0));
  add_option(t("dateTomorrow"), date_string(1));
  add_option(t("dialogClear"), L"");
  menu.ShowAt(BulkScheduleButton());
}

void MainWindow::StageTaskDeletion(
    std::vector<std::int64_t> const& ids) {
  if (backend_ == nullptr || !backend_->running()) return;
  // Only one undo batch at a time. Starting another deletion commits
  // the previous one and opens a fresh six-second window.
  if (!pending_delete_ids_.empty()) CommitPendingDeletion();
  for (auto const id : ids) {
    if (FindTaskForAction(id) == nullptr) continue;
    if (suppressed_deleted_task_ids_.insert(id).second) {
      pending_delete_ids_.push_back(id);
    }
  }
  if (pending_delete_ids_.empty()) return;
  if (!delete_undo_timer_) {
    delete_undo_timer_ = DispatcherQueue().CreateTimer();
    delete_undo_timer_.Interval(std::chrono::seconds{6});
    delete_undo_timer_.IsRepeating(false);
    delete_undo_timer_.Tick([weak = get_weak()](auto&&, auto&&) {
      if (auto window = weak.get()) window->CommitPendingDeletion();
    });
  }
  delete_undo_timer_.Stop();
  delete_undo_timer_.Start();
  UndoDeleteButton().Visibility(mx::Visibility::Visible);
  SetStatus(tf("bannerTasksDeleted",
               std::to_wstring(pending_delete_ids_.size())));
  RenderTasks();
  RenderSearchResults();
}

void MainWindow::CommitPendingDeletion() {
  if (delete_undo_timer_) delete_undo_timer_.Stop();
  if (backend_ == nullptr || !backend_->running()) {
    // Deletion has not been persisted, so restore every staged row.
    UndoPendingDeletion();
    SetStatus(t("taskListEmptyHint"));
    return;
  }
  auto const ids = std::move(pending_delete_ids_);
  pending_delete_ids_.clear();
  UndoDeleteButton().Visibility(mx::Visibility::Collapsed);
  for (auto const id : ids) {
    // Keep rows visually hidden while their deletion RPCs complete.
    // A failure removes suppression and makes the task visible again.
    DeleteTaskAsync(id);
  }
}

void MainWindow::UndoPendingDeletion() {
  if (delete_undo_timer_) delete_undo_timer_.Stop();
  for (auto const id : pending_delete_ids_) {
    suppressed_deleted_task_ids_.erase(id);
  }
  pending_delete_ids_.clear();
  UndoDeleteButton().Visibility(mx::Visibility::Collapsed);
  SetStatus(t("bannerUndo"));
  RenderTasks();
  RenderSearchResults();
}

void MainWindow::OnUndoDeleteClicked(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  UndoPendingDeletion();
}

void MainWindow::OnBulkDeleteClicked(
    winrt::Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  StageTaskDeletion(SelectedTaskIds());
}

void MainWindow::OnTaskListKeyDown(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args) {
  // Text fields and editable task controls retain their normal shortcuts.
  if (args.OriginalSource().try_as<mxc::TextBox>()) return;

  auto list = sender.try_as<mxc::ListView>();
  if (!list) return;
  if (args.Key() == Windows::System::VirtualKey::Escape) {
    if (inline_task_id_.has_value()) {
      CancelInlineTaskEditor();
      args.Handled(true);
      return;
    }
    if (!list.SelectedItems().Size()) return;
    list.SelectedItems().Clear();
    args.Handled(true);
    return;
  }
  if (args.Key() != Windows::System::VirtualKey::Enter ||
      list.SelectedItems().Size() != 1) {
    // WinUI natively handles Up/Down, Ctrl-click and Shift-click/ranges
    // in Extended mode. Do not swallow its keyboard navigation.
    return;
  }

  auto row = list.SelectedItems().GetAt(0).try_as<mxc::Grid>();
  if (!row) return;
  auto const id = winrt::unbox_value<std::int64_t>(row.Tag());
  args.Handled(true);
  OpenInlineTaskEditor(id);
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
  // Keep unsent input when the backend is unavailable; otherwise the
  // user loses their draft before AddTaskAsync can reject the request.
  if (text.find_first_not_of(L" \t\r\n") == std::wstring::npos ||
      backend_ == nullptr || !backend_->running()) {
    return;
  }
  // Match macOS/Linux: a named list owns new tasks; smart views use the
  // first list only as an explicit fallback. Capture the target BEFORE the
  // async parser runs, so switching views cannot redirect an in-flight add.
  std::optional<std::int64_t> target_list_id;
  if (view_ == ViewKind::List) {
    if (find_by_id(lists_, view_list_id_) != nullptr) {
      target_list_id = view_list_id_;
    }
  } else if (!lists_.empty()) {
    target_list_id = lists_.front().id;
  }
  if (!target_list_id.has_value()) {
    SetStatus(t("taskCreateListFirst"));
    return;  // Keep the user's draft until a valid destination exists.
  }
  NewTaskBox().Text(L"");
  AddTaskAsync(text, *target_list_id);
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
  OpenInlineTaskEditor(id);
}

void MainWindow::OnDeleteTask(
    winrt::Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
  auto const id = winrt::unbox_value<std::int64_t>(
      sender.as<mxc::MenuFlyoutItem>().Tag());
  StageTaskDeletion({id});
}

}  // namespace winrt::RivetHost::implementation
