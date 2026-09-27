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
            // One silent online-update check per session, after first paint.
            if (_databaseOpened
                && args.WindowActivationState != WindowActivationState.Deactivated
                && !_updateChecked)
            {
                _updateChecked = true;
                await RunUpdateCheckAsync(silent: true);
            }
        };
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

    // ---------------- online updates (Velopack over GitHub Releases) ----------------

    private bool _updateChecked;

    private async void OnCheckUpdates(object sender, RoutedEventArgs e) =>
        await RunUpdateCheckAsync(silent: false);

    /// <summary>Checks GitHub Releases via Velopack. Silent mode swallows all
    /// failures (offline, portable copy, rate limit); manual mode reports.
    /// Only a Velopack-managed install can update — portable zips get a
    /// re-download hint.</summary>
    private async Task RunUpdateCheckAsync(bool silent)
    {
        Microsoft.UI.Xaml.Controls.ContentDialog? dialog;
        try
        {
            var source = new Velopack.Sources.GithubSource(
                "https://github.com/turinglambdaai/taskly", null, false);
            Velopack.UpdateManager? mgr = null;
            try
            {
                mgr = new Velopack.UpdateManager(source);
            }
            catch
            {
                // Not a Velopack-managed install (portable zip extract).
            }

            if (mgr is null || !mgr.IsInstalled)
            {
                if (!silent)
                {
                    dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
                    {
                        Title = Vm.T("menuCheckUpdates"),
                        Content = Vm.T("updatePortable"),
                        CloseButtonText = Vm.T("dialogConfirm"),
                        XamlRoot = RootGrid.XamlRoot,
                    };
                    await dialog.ShowAsync();
                }

                return;
            }

            var info = await mgr.CheckForUpdatesAsync();
            if (info is not null && !info.IsDowngrade
                && info.TargetFullRelease.Version > mgr.CurrentVersion)
            {
                dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
                {
                    Title = Vm.T("updateAvailableTitle"),
                    Content = string.Format(
                        System.Globalization.CultureInfo.InvariantCulture,
                        Vm.T("updateAvailableBody"), info.TargetFullRelease.Version),
                    PrimaryButtonText = Vm.T("updateRestart"),
                    CloseButtonText = Vm.T("dialogCancel"),
                    XamlRoot = RootGrid.XamlRoot,
                };
                if (await dialog.ShowAsync() == Microsoft.UI.Xaml.Controls.ContentDialogResult.Primary)
                {
                    mgr.ApplyUpdatesAndRestart(info.TargetFullRelease);
                }
            }
            else if (!silent)
            {
                dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
                {
                    Title = Vm.T("menuCheckUpdates"),
                    Content = Vm.T("updateUpToDate"),
                    CloseButtonText = Vm.T("dialogConfirm"),
                    XamlRoot = RootGrid.XamlRoot,
                };
                await dialog.ShowAsync();
            }
        }
        catch (Exception ex)
        {
            if (!silent)
            {
                dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
                {
                    Title = Vm.T("menuCheckUpdates"),
                    Content = string.Format(
                        System.Globalization.CultureInfo.InvariantCulture,
                        Vm.T("updateCheckFailed"), ex.Message),
                    CloseButtonText = Vm.T("dialogConfirm"),
                    XamlRoot = RootGrid.XamlRoot,
                };
                await dialog.ShowAsync();
            }
        }
    }

    private void OnSidebarToggleRequested()
    {
        var collapsing = SidebarColumn.Width.Value != 0;
        // MinWidth would clamp the 0-width collapse; release it while hidden.
        SidebarColumn.MinWidth = collapsing ? 0 : 200;
        SidebarColumn.Width = collapsing ? new GridLength(0) : new GridLength(280);
    }

    private void ApplyLanguage()
    {
        MenuFile.Title = Vm.T("menuFile");
        MenuNewDatabase.Text = Vm.T("menuNewDatabase");
        MenuOpenDatabase.Text = Vm.T("menuOpenDatabase");
        MenuCloseDatabase.Text = Vm.T("menuCloseDatabase");
        MenuExit.Text = Vm.T("menuExit");

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

    // ---------------- window accelerators (no menu items needed) ----------------

    private async void OnAccViewToday(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        await Vm.SelectViewAsync(TaskViewType.Today);
    }

    private async void OnAccViewPlanned(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        await Vm.SelectViewAsync(TaskViewType.Planned);
    }

    private async void OnAccViewAll(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        await Vm.SelectViewAsync(TaskViewType.All);
    }

    private async void OnAccViewCompleted(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        await Vm.SelectViewAsync(TaskViewType.Completed);
    }

    private void OnAccNewTask(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        Pane.FocusQuickAdd();
    }

    private void OnAccFind(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        Sidebar.FocusSearch();
    }

    private async void OnAccToggleCompleted(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        await Vm.ToggleShowCompletedAsync();
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
