#pragma once

#include "pch.h"
#include "GeneratedBackend.hpp"
#include "MainWindow.g.h"

namespace winrt::RivetHost::implementation {

// UI strings for the two supported languages. The backend owns the
// authoritative config; hosts only render what get_settings returns.
struct Strings {
  std::wstring search_placeholder;
  std::wstring smart_lists;
  std::wstring my_lists;
  std::wstring new_list;
  std::wstring today;
  std::wstring planned;
  std::wstring all;
  std::wstring completed;
  std::wstring new_task_placeholder;
  std::wstring show_completed;
  std::wstring due_today;
  std::wstring due_tomorrow;
  std::wstring due_clear;
  std::wstring delete_task;
  std::wstring rename_list;
  std::wstring delete_list;
  std::wstring new_list_dialog_title;
  std::wstring new_list_dialog_placeholder;
  std::wstring rename_list_dialog_title;
  std::wstring edit_task_dialog_title;
  std::wstring ok;
  std::wstring cancel;
  std::wstring menu_file;
  std::wstring menu_settings;
  std::wstring menu_help;
  std::wstring menu_new_db;
  std::wstring menu_open_db;
  std::wstring menu_close_db;
  std::wstring menu_exit;
  std::wstring menu_lang_zh;
  std::wstring menu_lang_en;
  std::wstring menu_theme_system;
  std::wstring menu_theme_light;
  std::wstring menu_theme_dark;
  std::wstring menu_about;
  std::wstring about_title;
  std::wstring about_body;
  std::wstring status_starting;
  std::wstring status_ready;
  std::wstring status_error;
  std::wstring count_suffix;
};

Strings const& S(std::string const& lang);

struct MainWindow : MainWindowT<MainWindow> {
  MainWindow();

  // Menu handlers
  void OnNewDatabase(winrt::Windows::Foundation::IInspectable const&,
                     Microsoft::UI::Xaml::RoutedEventArgs const&);
  winrt::fire_and_forget OnOpenDatabase(
      winrt::Windows::Foundation::IInspectable const&,
      Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnCloseDatabase(winrt::Windows::Foundation::IInspectable const&,
                       Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnExit(winrt::Windows::Foundation::IInspectable const&,
              Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnLangZh(winrt::Windows::Foundation::IInspectable const&,
                Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnLangEn(winrt::Windows::Foundation::IInspectable const&,
                Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnThemeSystem(winrt::Windows::Foundation::IInspectable const&,
                     Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnThemeLight(winrt::Windows::Foundation::IInspectable const&,
                    Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnThemeDark(winrt::Windows::Foundation::IInspectable const&,
                   Microsoft::UI::Xaml::RoutedEventArgs const&);
  winrt::fire_and_forget OnAbout(
      winrt::Windows::Foundation::IInspectable const&,
      Microsoft::UI::Xaml::RoutedEventArgs const&);

  // Sidebar handlers
  void OnSearchTextChanged(winrt::Windows::Foundation::IInspectable const&,
                           Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&);
  void OnSmartListSelectionChanged(winrt::Windows::Foundation::IInspectable const&,
                                   Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnUserListSelectionChanged(winrt::Windows::Foundation::IInspectable const&,
                                  Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnNewList(winrt::Windows::Foundation::IInspectable const&,
                 Microsoft::UI::Xaml::RoutedEventArgs const&);

  // Task pane handlers
  void OnShowCompletedChanged(winrt::Windows::Foundation::IInspectable const&,
                              Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnNewTaskKeyDown(winrt::Windows::Foundation::IInspectable const&,
                        Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const&);

private:
  enum class ViewKind { Today, Planned, All, Completed, List };

  static std::string ViewStringFor(ViewKind kind);

  winrt::fire_and_forget InitializeBackendAsync();

  void ApplyLanguage();
  void ApplyTheme(std::string const& theme);
  void RenderSidebar();
  void RenderTasks();
  void RenderSearchResults();
  winrt::Microsoft::UI::Xaml::Media::Brush ThemeBrush(wchar_t const* key);
  winrt::Microsoft::UI::Xaml::Controls::Grid MakeTaskRow(
      rivet_app::Task const& task);
  winrt::hstring DueLabel(std::string const& due_date) const;
  std::wstring view_title() const;
  void SetStatus(std::wstring const& message);
  void SetError(std::string const& message);
  winrt::fire_and_forget PromptAsync(
      std::wstring const& title, std::wstring const& placeholder,
      std::wstring const& initial,
      std::function<void(std::wstring const&)> on_ok);

  winrt::fire_and_forget ReloadTasksAsync();
  winrt::fire_and_forget OpenDefaultDatabaseAsync();
  winrt::fire_and_forget OpenDatabaseAsync(std::wstring const& path);
  winrt::fire_and_forget AddTaskAsync(std::wstring const& text);
  winrt::fire_and_forget ToggleTaskAsync(std::int64_t id, bool completed);
  winrt::fire_and_forget RenameTaskAsync(std::int64_t id, std::wstring const& text);
  winrt::fire_and_forget SetTaskDueAsync(std::int64_t id, std::wstring const& due_date);
  winrt::fire_and_forget DeleteTaskAsync(std::int64_t id);
  winrt::fire_and_forget CreateListAsync(std::wstring const& name);
  winrt::fire_and_forget RenameListAsync(std::int64_t id, std::wstring const& name);
  winrt::fire_and_forget DeleteListAsync(std::int64_t id);
  winrt::fire_and_forget SaveSettingAsync(std::string const& key, std::string const& value);
  winrt::fire_and_forget RunSearchAsync(std::wstring const& keyword);

  // Row context-menu handlers
  void OnRenameList(winrt::Windows::Foundation::IInspectable const&,
                    Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnDeleteList(winrt::Windows::Foundation::IInspectable const&,
                    Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnTaskCheckChanged(winrt::Windows::Foundation::IInspectable const&,
                          Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnDueToday(winrt::Windows::Foundation::IInspectable const&,
                  Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnDueTomorrow(winrt::Windows::Foundation::IInspectable const&,
                     Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnDueClear(winrt::Windows::Foundation::IInspectable const&,
                  Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnEditTask(winrt::Windows::Foundation::IInspectable const&,
                  Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnDeleteTask(winrt::Windows::Foundation::IInspectable const&,
                    Microsoft::UI::Xaml::RoutedEventArgs const&);

  std::shared_ptr<rivet::windows::Backend> backend_;
  rivet_app::Settings settings_{};
  rivet_app::SmartCounts current_counts_{};
  std::vector<rivet_app::TodoList> lists_;
  std::vector<rivet_app::Task> tasks_;
  std::vector<rivet_app::Task> search_results_;
  std::wstring current_search_;
  ViewKind view_{ViewKind::All};
  std::int64_t view_list_id_{0};
  bool show_completed_{false};
  bool suppress_selection_{false};
  std::atomic<bool> reload_in_flight_{false};
  winrt::Microsoft::UI::Xaml::DispatcherTimer poll_timer_{nullptr};
};

}  // namespace winrt::RivetHost::implementation

namespace winrt::RivetHost::factory_implementation {

struct MainWindow : MainWindowT<MainWindow, implementation::MainWindow> {};

}  // namespace winrt::RivetHost::factory_implementation
