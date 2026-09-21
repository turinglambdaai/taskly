using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Taskly.Models;
using Taskly.ViewModels;

namespace Taskly.Views;

public sealed partial class ListPane : UserControl
{
    public MainViewModel? Vm { get; set; }
    private MainViewModel? _subscribedVm;

    public ListPane()
    {
        InitializeComponent();
    }

    public void SetViewModel(MainViewModel vm)
    {
        if (_subscribedVm is not null)
        {
            _subscribedVm.CountsChanged -= RefreshCounts;
            ListsList.ItemClick -= OnListItemClick;
            ListsList.RightTapped -= OnListRightTapped;
        }

        Vm = vm;
        ListsList.ItemsSource = vm.ListCollection;
        _subscribedVm = vm;
        vm.CountsChanged += RefreshCounts;
        ListsList.ItemClick += OnListItemClick;
        ListsList.RightTapped += OnListRightTapped;

        ApplyLanguage();
    }

    public void ApplyLanguage()
    {
        var vm = Vm;
        if (vm is null)
        {
            return;
        }

        // Monochrome Segoe Fluent glyphs (E787 calendar, E823 clock,
        // E8FD list, E73E checkmark) — quieter than emoji, matches the
        // Reminders-style sidebar.
        TileTodayIcon.Text = "\uE787";
        TileTodayLabel.Text = vm.T("navToday");
        TilePlannedIcon.Text = "\uE823";
        TilePlannedLabel.Text = vm.T("navPlanned");
        TileAllIcon.Text = "\uE8FD";
        TileAllLabel.Text = vm.T("navAll");
        TileCompletedIcon.Text = "\uE73E";
        TileCompletedLabel.Text = vm.T("navCompleted");
        MyListsHeader.Text = vm.T("sectionMyLists");
        RefreshCounts();
    }

    public void ShowStatus(string message) => Vm?.ShowTransientStatus(message);

    private void RefreshCounts()
    {
        var vm = Vm;
        if (vm is null)
        {
            return;
        }

        TileTodayCount.Text = vm.TodayCount > 0 ? vm.TodayCount.ToString() : "";
        TilePlannedCount.Text = vm.PlannedCount > 0 ? vm.PlannedCount.ToString() : "";
        TileAllCount.Text = vm.AllCount > 0 ? vm.AllCount.ToString() : "";
        TileCompletedCount.Text = vm.CompletedCount > 0 ? vm.CompletedCount.ToString() : "";
    }

    private async void OnTileToday(object sender, RoutedEventArgs e)
    {
        if (Vm is { } vm)
        {
            await vm.SelectViewAsync(TaskViewType.Today);
        }
    }

    private async void OnTilePlanned(object sender, RoutedEventArgs e)
    {
        if (Vm is { } vm)
        {
            await vm.SelectViewAsync(TaskViewType.Planned);
        }
    }

    private async void OnTileAll(object sender, RoutedEventArgs e)
    {
        if (Vm is { } vm)
        {
            await vm.SelectViewAsync(TaskViewType.All);
        }
    }

    private async void OnTileCompleted(object sender, RoutedEventArgs e)
    {
        if (Vm is { } vm)
        {
            await vm.SelectViewAsync(TaskViewType.Completed);
        }
    }

    private async void OnListItemClick(object sender, ItemClickEventArgs e)
    {
        if (Vm is { } vm && e.ClickedItem is TodoList list)
        {
            await vm.SelectViewAsync(TaskViewType.List, list.Id);
        }
    }

    // Right-tap → edit list (double-tap opens the editor as well).
    private async void OnListRightTapped(object sender, RightTappedRoutedEventArgs e)
    {
        if (FrameworkElementAncestor(e.OriginalSource) is not { } container)
        {
            return;
        }

        var list = ListsList.ItemFromContainer(container) as TodoList;
        if (list is null || Vm is not { } vm)
        {
            return;
        }

        var dialog = new Dialogs.ListEditDialog(vm, list);
        dialog.XamlRoot = XamlRoot;
        await dialog.ShowAsync();
    }

    private static FrameworkElement? FrameworkElementAncestor(object? source)
    {
        var dep = source as DependencyObject;
        while (dep is not null)
        {
            if (dep is FrameworkElement fe && fe.DataContext is TodoList)
            {
                return fe;
            }

            dep = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(dep);
        }

        return null;
    }

    private async void OnAddList(object sender, RoutedEventArgs e)
    {
        if (Vm is not { IsConnected: true } vm)
        {
            return;
        }

        var dialog = new Dialogs.ListEditDialog(vm, existing: null);
        dialog.XamlRoot = XamlRoot;
        await dialog.ShowAsync();
    }
}
