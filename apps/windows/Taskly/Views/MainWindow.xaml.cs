using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Taskly.Models;
using Taskly.Services;
using Taskly.ViewModels;
using Windows.Graphics;
using Windows.Storage.Pickers;

namespace Taskly.Views;

public sealed partial class MainWindow : Window
{
    public MainViewModel Vm { get; } = new();
    private bool _databaseOpened;

    public MainWindow()
    {
        InitializeComponent();

        Title = "Taskly";
        AppWindow.Resize(new SizeInt32(1280, 880));
        // Unpackaged WinUI shows the default icon unless told otherwise.
        AppWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "taskly.ico"));

        Sidebar.SetViewModel(Vm);
        Pane.SetViewModel(Vm);
        Pane.SidebarToggleRequested += OnSidebarToggleRequested;

        ApplyLanguage();
        Vm.LanguageChanged += ApplyLanguage;

        Closed += (_, _) => Vm.Reminder.Dispose();
        Activated += async (_, args) =>
        {
            // Open the default DB once, after the window is live (XamlRoot ready).
            if (!_databaseOpened
                && args.WindowActivationState != WindowActivationState.Deactivated)
            {
                _databaseOpened = true;
                await Vm.OpenDefaultDatabaseAsync();
            }
        };
    }

    private void OnSidebarToggleRequested()
    {
        SidebarColumn.Width = SidebarColumn.Width.Value == 0
            ? new GridLength(280)
            : new GridLength(0);
    }

    private void ApplyLanguage()
    {
        MenuFile.Title = Vm.T("menuFile");
        MenuNewDatabase.Text = Vm.T("menuNewDatabase");
        MenuOpenDatabase.Text = Vm.T("menuOpenDatabase");
        MenuCloseDatabase.Text = Vm.T("menuCloseDatabase");
        MenuExit.Text = Vm.T("menuExit");

        MenuView.Title = Vm.T("menuView");
        MenuViewToday.Text = Vm.T("navToday");
        MenuViewPlanned.Text = Vm.T("navPlanned");
        MenuViewAll.Text = Vm.T("navAll");
        MenuViewCompleted.Text = Vm.T("navCompleted");
        MenuViewCalendar.Text = Vm.T("navCalendar");
        MenuNewTask.Text = Vm.T("taskListInputHint").TrimStart('+', ' ');
        MenuFind.Text = Vm.T("searchHint");
        MenuShowCompleted.Text = Vm.ShowCompletedTasks
            ? Vm.T("hideCompletedToggle")
            : Vm.T("showCompletedToggle");
        MenuShowCompleted.IsChecked = Vm.ShowCompletedTasks;

        MenuTools.Title = Vm.T("menuTools");
        MenuInstallCli.Text = Vm.T("menuInstallCli");
        MenuUninstallCli.Text = Vm.T("menuUninstallCli");

        MenuSettings.Title = Vm.T("menuSettings");
        MenuLangZh.Text = Vm.T("menuLangZh");
        MenuLangEn.Text = Vm.T("menuLangEn");
        MenuDarkMode.Text = Vm.T("menuDarkMode");

        MenuHelp.Title = Vm.T("menuHelp");
        MenuAbout.Text = Vm.T("menuAbout");

        Sidebar.ApplyLanguage();
        Pane.ApplyLanguage();
    }

    // ---------------- view menu / accelerators ----------------

    private async void OnViewToday(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Today);

    private async void OnViewPlanned(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Planned);

    private async void OnViewAll(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.All);

    private async void OnViewCompleted(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Completed);

    private async void OnViewCalendar(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Calendar);

    private void OnNewTaskFocus(object sender, RoutedEventArgs e) => Pane.FocusQuickAdd();

    private void OnFindFocus(object sender, RoutedEventArgs e) => Pane.FocusSearch();

    private async void OnToggleShowCompletedMenu(object sender, RoutedEventArgs e)
    {
        await Vm.ToggleShowCompletedAsync();
        MenuShowCompleted.IsChecked = Vm.ShowCompletedTasks;
        Pane.SyncShowCompletedLabel();
    }

    // ---------------- file menu ----------------

    private async void OnNewDatabase(object sender, RoutedEventArgs e)
    {
        var picker = new FileSavePicker { SuggestedFileName = "tasks" };
        picker.FileTypeChoices.Add("Taskly Database", new List<string> { ".db" });
        WinRT.Interop.InitializeWithWindow.Initialize(picker,
            WinRT.Interop.WindowNative.GetWindowHandle(this));
        var file = await picker.PickSaveFileAsync();
        if (file is not null)
        {
            await Vm.OpenOrCreateDatabaseAsync(file.Path);
        }
    }

    private async void OnOpenDatabase(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".db");
        WinRT.Interop.InitializeWithWindow.Initialize(picker,
            WinRT.Interop.WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            await Vm.OpenOrCreateDatabaseAsync(file.Path);
        }
    }

    private async void OnCloseDatabase(object sender, RoutedEventArgs e)
    {
        var dialog = new Dialogs.ConfirmDialog(
            Vm.T("dialogConfirmCloseDb"), Vm.T("dialogConfirmCloseDbContent"), Vm.T("dialogConfirm"), Vm.T("dialogCancel"));
        dialog.XamlRoot = RootGrid.XamlRoot;
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await Vm.CloseDatabaseAsync();
        }
    }

    private void OnExit(object sender, RoutedEventArgs e) => Close();

    // ---------------- settings menu ----------------

    private void OnLangZh(object sender, RoutedEventArgs e)
    {
        I18nService.Instance.SetLanguage("zh");
        Vm.SaveLanguage("zh");
    }

    private void OnLangEn(object sender, RoutedEventArgs e)
    {
        I18nService.Instance.SetLanguage("en");
        Vm.SaveLanguage("en");
    }

    private async void OnToggleDarkMode(object sender, RoutedEventArgs e)
    {
        var toggle = (ToggleMenuFlyoutItem)sender;
        RootGrid.RequestedTheme = toggle.IsChecked ? ElementTheme.Dark : ElementTheme.Light;

        // Row projections (brushes per task item) read this flag.
        Models.UiTheme.IsDark = toggle.IsChecked;
        await Vm.RefreshAsync();
    }

    private void OnInstallCli(object sender, RoutedEventArgs e)
    {
        var result = Cli.CliInstaller.Install();
        Sidebar.ShowStatus(result == 0 ? "taskly installed" : "taskly install failed");
    }

    private void OnUninstallCli(object sender, RoutedEventArgs e)
    {
        var result = Cli.CliInstaller.Uninstall();
        Sidebar.ShowStatus(result == 0 ? "taskly removed" : "taskly remove failed");
    }

    private async void OnAbout(object sender, RoutedEventArgs e)
    {
        var version = AppVersion.Current;
        var dialog = new Dialogs.AboutDialog(
            $"Taskly v{version}\n© 2026 Taskly Team\n\n{Vm.T("aboutContent")}", Vm.T("dialogConfirm"));
        dialog.XamlRoot = RootGrid.XamlRoot;
        await dialog.ShowAsync();
    }
}

internal static class AppVersion
{
    public const string Current = "1.0.0";
}
