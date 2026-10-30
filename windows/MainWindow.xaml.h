#pragma once

#include <set>

#include "pch.h"
#include "GeneratedBackend.hpp"
#include "MainWindow.g.h"
#include "system_services.hpp"
#include "winui_window.hpp"

namespace winrt::RivetHost::implementation {

// Host-wide UI strings, keyed exactly like shared/i18n/*.json (the single
// source of truth). Tables load from <exe_dir>/app/shared/i18n/{zh,en}.json
// (rivet.rktd `resources`) with an embedded fallback; a missing key degrades
// to the key itself, never a crash. Defined in MainWindow.xaml.cpp.
std::wstring t(char const* key);
std::wstring tf(char const* key, std::wstring const& arg0);

// Host helpers shared with MainWindow.Update.cpp (payback's HostHelpers
// pattern): executable path and UTF conversion.
std::filesystem::path executable_path();
std::string utf8(std::filesystem::path const& path);
std::wstring wide(std::string const& text);

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
  void OnCheckUpdates(winrt::Windows::Foundation::IInspectable const&,
                      Microsoft::UI::Xaml::RoutedEventArgs const&);
  winrt::fire_and_forget OnAbout(
      winrt::Windows::Foundation::IInspectable const&,
      Microsoft::UI::Xaml::RoutedEventArgs const&);

  // Sidebar handlers
  void OnSidebarToggle(winrt::Windows::Foundation::IInspectable const&,
                       Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnSearchTextChanged(winrt::Windows::Foundation::IInspectable const&,
                           Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&);
  void OnSmartTileClick(winrt::Windows::Foundation::IInspectable const&,
                        Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnUserListSelectionChanged(winrt::Windows::Foundation::IInspectable const&,
                                  Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnNewList(winrt::Windows::Foundation::IInspectable const&,
                 Microsoft::UI::Xaml::RoutedEventArgs const&);

  // Quick add
  void OnQuickAddCommit(winrt::Windows::Foundation::IInspectable const&,
                        Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnNewTaskTextChanged(winrt::Windows::Foundation::IInspectable const&,
                            Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&);
  void OnNewTaskFocusChanged(winrt::Windows::Foundation::IInspectable const&,
                             Microsoft::UI::Xaml::RoutedEventArgs const&);

  // Task pane handlers
  void OnShowCompletedChanged(winrt::Windows::Foundation::IInspectable const&,
                              Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnNewTaskKeyDown(winrt::Windows::Foundation::IInspectable const&,
                        Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const&);
  void OnTaskListKeyDown(winrt::Windows::Foundation::IInspectable const&,
                         Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const&);
  void OnTaskSelectionChanged(
      winrt::Windows::Foundation::IInspectable const&,
      Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnBulkCompleteClicked(winrt::Windows::Foundation::IInspectable const&,
                             Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnBulkMoveClicked(winrt::Windows::Foundation::IInspectable const&,
                         Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnBulkScheduleClicked(winrt::Windows::Foundation::IInspectable const&,
                             Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnBulkDeleteClicked(winrt::Windows::Foundation::IInspectable const&,
                           Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnUndoDeleteClicked(winrt::Windows::Foundation::IInspectable const&,
                           Microsoft::UI::Xaml::RoutedEventArgs const&);

  // Update download action wired from XAML; event handlers must be public
  // because generated Connect() binds them through MainWindowT.
  void OnCancelUpdateDownload(
      winrt::Windows::Foundation::IInspectable const&,
      Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnAutoCheckUpdatesToggled(
      winrt::Windows::Foundation::IInspectable const&,
      Microsoft::UI::Xaml::RoutedEventArgs const&);
  void LoadAutoCheckUpdatesSetting();

private:
  enum class ViewKind { Today, Planned, All, Completed, List };

  // PRODUCT-SPEC §8 app accelerators (Ctrl+1…4 / Ctrl+N / Ctrl+F /
  // Ctrl+Shift+C / Ctrl+Shift+N / Ctrl+O). They reuse the command paths
  // of the tiles and menu items; Windows has no View menu, so the
  // accelerators are installed on the root element in code.
  void InstallAppAccelerators();
  void SwitchSmartView(ViewKind kind);
  void ToggleShowCompleted();
  void CheckReminders(bool startup);
  void DeliverReminder(rivet_app::ReminderDecision decision);

  static std::string ViewStringFor(ViewKind kind);

  winrt::fire_and_forget InitializeBackendAsync();

  void ApplyLanguage();
  void ApplyTheme(std::string const& theme);
  void RefreshSmartTiles();
  bool ApplySnapshot(rivet_app::Snapshot const& snapshot, bool force);
  void RenderSidebar();
  void RenderTasks();
  void RenderSearchResults();
  winrt::Microsoft::UI::Xaml::Media::Brush ThemeBrush(wchar_t const* key);
  winrt::Microsoft::UI::Xaml::Media::Brush ListBrush(
      rivet_app::TodoList const& list);
  winrt::Microsoft::UI::Xaml::Controls::Grid MakeTaskRow(
      rivet_app::Task const& task, bool search_result = false);
  rivet_app::Task const* FindTaskForAction(std::int64_t id) const;
  void RefreshSearchIfActive();
  winrt::hstring DueLabel(std::string const& due_date) const;
  std::wstring view_title() const;
  winrt::hstring view_subtitle() const;
  std::wstring full_date_today() const;
  void CommitQuickAdd();
  void RefreshBulkActionBar();
  std::vector<std::int64_t> SelectedTaskIds();
  void MoveSelectedTasks(std::vector<std::int64_t> const& ids,
                         std::int64_t target_list_id);
  void ScheduleSelectedTasks(std::vector<std::int64_t> const& ids,
                             std::wstring const& due);
  void StageTaskDeletion(std::vector<std::int64_t> const& ids);
  void CommitPendingDeletion();
  void UndoPendingDeletion();
  void OpenInlineTaskEditor(std::int64_t id);
  void CaptureInlineTaskDraft();
  void CommitInlineTaskEditor();
  void CancelInlineTaskEditor();
  void ResetInlineTaskEditor();
  void RefreshQuickAddPreview();
  void ApplyTitleBarTheme();
  void OnEffectiveThemeChanged();
  void SetStatus(std::wstring const& message);
  void SetError(std::string const& message);
  winrt::fire_and_forget PromptAsync(
      std::wstring const& title, std::wstring const& placeholder,
      std::wstring const& initial,
      std::function<void(std::wstring const&)> on_ok);

  winrt::fire_and_forget ReloadTasksAsync();
  winrt::fire_and_forget OpenDefaultDatabaseAsync();
  winrt::fire_and_forget OpenDatabaseAsync(std::wstring const& path);
  winrt::fire_and_forget AddTaskAsync(std::wstring const& text,
                                       std::int64_t target_list_id);
  winrt::fire_and_forget ToggleTaskAsync(std::int64_t id, bool completed);
  winrt::fire_and_forget RenameTaskAsync(std::int64_t id, std::wstring const& text);
  winrt::fire_and_forget SetTaskDueAsync(std::int64_t id, std::wstring const& due_date);
  winrt::fire_and_forget UpdateTaskAsync(
      rivet_app::Task task,
      std::optional<rivet_app::Task> restore_on_failure = std::nullopt);
  winrt::fire_and_forget DeleteTaskAsync(std::int64_t id);
  winrt::fire_and_forget MoveTaskToListAsync(
      std::int64_t id, std::int64_t target_list_id);
  winrt::fire_and_forget CreateListAsync(std::wstring const& name);
  winrt::fire_and_forget RenameListAsync(std::int64_t id, std::wstring const& name);
  winrt::fire_and_forget DeleteListAsync(std::int64_t id);
  winrt::fire_and_forget ConfirmDeleteListAsync(std::int64_t id);
  winrt::fire_and_forget SaveSettingAsync(std::string const& key, std::string const& value);
  winrt::fire_and_forget RunSearchAsync(std::wstring const& keyword);
  winrt::fire_and_forget RunQuickAddPreview(std::wstring const& text);

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

  // Updates (shared/spec/UPDATE.md; flow lives in MainWindow.Update.cpp)
  winrt::fire_and_forget AutoCheckUpdatesAsync();
  void RunSilentUpdateCheck();
  void RunUpdateCheck(bool silent);
  void ContinueUpdateCheck(bool silent);
  void HandleUpdateCheckResult(bool ok, rivet_app::UpdateCheck const& check,
                               std::string const& failure, bool silent);
  void RecordUpdateCheck();
  void StartDownload();
  void PollUpdateState(
      std::shared_ptr<rivet::windows::Backend> const& backend);
  void HandleUpdatePoll(rivet_app::Result<rivet_app::UpdateState> const& result);
  void FailDownload(std::string const& message);
  winrt::fire_and_forget ShowInstallConsent(std::wstring const& path);
  void InstallDownloadedUpdate(std::wstring const& update_path);
  void HandleInstallMarkers();
  bool IsDevCopy();
  bool IsMsiInstall();
  // copy_button: when non-empty, a secondary button copies the dialog body
  // (the failure message) to the clipboard — update errors must leave the
  // screen with the user (family rule: error text is always copyable).
  winrt::fire_and_forget ShowUpdateDialog(
      std::wstring const& title, std::wstring const& body,
      std::wstring const& primary_button, std::wstring const& close_button,
      std::function<void()> on_primary,
      std::wstring const& copy_button = L"");

  std::shared_ptr<rivet::windows::Backend> backend_;
  std::unique_ptr<rivet::system::TrayIcon> notification_icon_;
  rivet_app::Settings settings_{};
  // Host-owned (like last-update-check): UPDATE.md auto-check toggle.
  bool auto_check_updates_{true};
  rivet_app::SmartCounts current_counts_{};
  std::vector<rivet_app::TodoList> lists_;
  std::vector<rivet_app::Task> tasks_;
  std::vector<rivet_app::Task> search_results_;
  // Deletions are staged for six seconds, retaining original task IDs.
  std::set<std::int64_t> suppressed_deleted_task_ids_;
  std::vector<std::int64_t> pending_delete_ids_;
  Microsoft::UI::Dispatching::DispatcherQueueTimer delete_undo_timer_{nullptr};
  // Exactly one task can be expanded inline. Draft values live outside the
  // visual tree so a changed-event rebuild cannot discard in-progress edits.
  std::optional<std::int64_t> inline_task_id_;
  std::optional<rivet_app::Task> inline_task_draft_;
  bool inline_task_in_search_{false};
  bool rebuilding_task_rows_{false};
  winrt::Microsoft::UI::Xaml::Controls::TextBox inline_title_box_{nullptr};
  winrt::Microsoft::UI::Xaml::Controls::TextBox inline_notes_box_{nullptr};
  winrt::Microsoft::UI::Xaml::Controls::TextBox inline_date_box_{nullptr};
  winrt::Microsoft::UI::Xaml::Controls::TextBox inline_time_box_{nullptr};
  winrt::Microsoft::UI::Xaml::Controls::Button inline_list_button_{nullptr};
  std::wstring current_search_;
  ViewKind view_{ViewKind::All};
  std::int64_t view_list_id_{0};
  bool show_completed_{false};
  bool suppress_selection_{false};
  bool sidebar_visible_{true};
  std::uint64_t preview_seq_{0};
  // Snapshot de-duplication: polls and `changed` events re-deliver identical
  // data; only a different fingerprint re-renders the sidebar/task tree.
  bool has_applied_snapshot_{false};
  std::string applied_snapshot_;
  std::atomic<bool> reload_in_flight_{false};
  winrt::Microsoft::UI::Xaml::DispatcherTimer poll_timer_{nullptr};
  winrt::Microsoft::UI::Xaml::DispatcherTimer reminder_timer_{nullptr};
  winrt::Microsoft::UI::Xaml::DispatcherTimer update_timer_{nullptr};
  winrt::Microsoft::UI::Dispatching::DispatcherQueueTimer preview_timer_{nullptr};
  bool update_downloading_{false};
  // Wall-clock start of the active download; a poll past the total limit
  // fails the download even if the backend state machine went quiet.
  std::int64_t update_download_start_{0};
  bool database_connected_{false};
  bool notifications_disabled_{false};
};

}  // namespace winrt::RivetHost::implementation

namespace winrt::RivetHost::factory_implementation {

struct MainWindow : MainWindowT<MainWindow, implementation::MainWindow> {};

}  // namespace winrt::RivetHost::factory_implementation
