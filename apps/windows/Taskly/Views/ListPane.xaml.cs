using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Taskly.Models;
using Taskly.ViewModels;

namespace Taskly.Views;

/// <summary>Sidebar: search, smart-list chips (2×2, Reminders style), and
/// My Lists. Chips are ToggleButtons — checked = the active view, with
/// hover/checked visuals VSM-driven so keyboard and UIA work.</summary>
public sealed partial class ListPane : UserControl
{
    public MainViewModel? Vm { get; set; }

    public ListPane()
    {
        InitializeComponent();
    }

    private MainViewModel? _subscribedVm;

    public void SetViewModel(MainViewModel vm)
    {
        if (_subscribedVm is not null)
        {
            _subscribedVm.CountsChanged -= RefreshCounts;
            _subscribedVm.PropertyChanged -= OnViewModelPropertyChanged;
            ListsList.ItemClick -= OnListItemClick;
            ListsList.RightTapped -= OnListRightTapped;
            SearchBox.KeyDown -= OnSearchKeyDown;
            SearchBox.TextChanged -= OnSearchTextChanged;
        }

        Vm = vm;
        ListsList.ItemsSource = vm?.ListCollection;
        _subscribedVm = vm;
        if (vm is not null)
        {
            vm.CountsChanged += RefreshCounts;
            vm.PropertyChanged += OnViewModelPropertyChanged;
            ListsList.ItemClick += OnListItemClick;
            ListsList.RightTapped += OnListRightTapped;
            SearchBox.KeyDown += OnSearchKeyDown;
            SearchBox.TextChanged += OnSearchTextChanged;
        }

        ApplyLanguage();
    }

    /// <summary>Quiet highlight on the active list's row (mirrors the chip
    /// selection language).</summary>
    private void SyncListSelection()
    {
        if (Vm is null)
        {
            return;
        }

        foreach (var list in Vm.ListCollection)
        {
            list.IsSelected = Vm.CurrentView == TaskViewType.List
                && list.Id == Vm.CurrentListId;
        }
    }

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainViewModel.CurrentView)
            || e.PropertyName == nameof(MainViewModel.CurrentListId))
        {
            SyncChipSelection();
            SyncListSelection();
        }
        else if (e.PropertyName == nameof(MainViewModel.IsConnected))
        {
            // Search lives in the sidebar; only meaningful when connected.
            SearchArea.Visibility = Vm is not null && Vm.IsConnected
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
    }

    // ---------------- search (sidebar, Reminders placement) ----------------

    private bool _searchChangedByProgram;

    /// <summary>Ctrl+F landing spot.</summary>
    public void FocusSearch()
    {
        SearchBox.Focus(FocusState.Keyboard);
    }

    private async void OnSearchKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter && Vm is not null)
        {
            await Vm.SetSearchAsync(SearchBox.Text);
        }
    }

    private async void OnSearchTextChanged(object sender, Microsoft.UI.Xaml.Controls.TextChangedEventArgs args)
    {
        if (_searchChangedByProgram || Vm is null)
        {
            return;
        }

        await Vm.SetSearchAsync(SearchBox.Text);
    }

    public void ApplyLanguage()
    {
        if (Vm is null)
        {
            return;
        }

        ChipTodayLabel.Text = Vm.T("navToday");
        ChipPlannedLabel.Text = Vm.T("navPlanned");
        ChipAllLabel.Text = Vm.T("navAll");
        ChipCompletedLabel.Text = Vm.T("navCompleted");
        MyListsHeader.Text = Vm.T("sectionMyLists");
        SearchBox.PlaceholderText = Vm.T("searchHint");
        SearchArea.Visibility = Vm.IsConnected ? Visibility.Visible : Visibility.Collapsed;
        SyncChipSelection();
        RefreshCounts();
    }

    public void ShowStatus(string message) => Vm?.ShowTransientStatus(message);

    private void RefreshCounts()
    {
        if (Vm is null)
        {
            return;
        }

        ChipTodayCount.Text = Vm.TodayCount > 0 ? Vm.TodayCount.ToString() : "";
        ChipPlannedCount.Text = Vm.PlannedCount > 0 ? Vm.PlannedCount.ToString() : "";
        ChipAllCount.Text = Vm.AllCount > 0 ? Vm.AllCount.ToString() : "";
        ChipCompletedCount.Text = Vm.CompletedCount > 0 ? Vm.CompletedCount.ToString() : "";
        SyncListSelection();
    }

    /// <summary>Checked chip = the active view (quiet fill via the VSM
    /// Checked state).</summary>
    private void SyncChipSelection()
    {
        if (Vm is null)
        {
            return;
        }

        ChipToday.IsChecked = Vm.CurrentView == TaskViewType.Today;
        ChipPlanned.IsChecked = Vm.CurrentView == TaskViewType.Planned;
        ChipAll.IsChecked = Vm.CurrentView == TaskViewType.All;
        ChipCompleted.IsChecked = Vm.CurrentView == TaskViewType.Completed;
    }

    private async void OnChipToday(object sender, RoutedEventArgs e) =>
        await ChipSelected(TaskViewType.Today, ChipToday);

    private async void OnChipPlanned(object sender, RoutedEventArgs e) =>
        await ChipSelected(TaskViewType.Planned, ChipPlanned);

    private async void OnChipAll(object sender, RoutedEventArgs e) =>
        await ChipSelected(TaskViewType.All, ChipAll);

    private async void OnChipCompleted(object sender, RoutedEventArgs e) =>
        await ChipSelected(TaskViewType.Completed, ChipCompleted);

    private async Task ChipSelected(TaskViewType view, ToggleButton chip)
    {
        if (Vm is null)
        {
            chip.IsChecked = false;
            return;
        }

        await Vm.SelectViewAsync(view);
        // Clicking the active chip unchecks it visually; the view is still
        // active, so restore the check.
        chip.IsChecked = true;
    }

    // Row hover fills the rounded card itself (the ListViewItem container
    // renders a square highlight that misses the card's 8px corners).
    private void OnListCardPointerEntered(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Border { DataContext: TodoList } card)
        {
            card.Background = Models.UiTheme.IsDark
                ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(0x14, 0xFF, 0xFF, 0xFF))
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(0x0D, 0x00, 0x00, 0x00));
        }
    }

    private void OnListCardPointerExited(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Border { DataContext: TodoList list } card)
        {
            card.Background = list.CardBrush;
        }
    }

    private async void OnListItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is TodoList list)
        {
            await Vm.SelectViewAsync(TaskViewType.List, list.Id);
        }
    }

    // Right-tap → edit list.
    private async void OnListRightTapped(object sender, RightTappedRoutedEventArgs e)
    {
        if (FrameworkElementAncestor(e.OriginalSource) is not { } container)
        {
            return;
        }

        var list = ListsList.ItemFromContainer(container) as TodoList;
        if (list is null || Vm is null)
        {
            return;
        }

        var dialog = new Dialogs.ListEditDialog(Vm, list);
        dialog.XamlRoot = XamlRoot;
        await dialog.ShowAsync();
    }

    private static FrameworkElement? FrameworkElementAncestor(object? source)
    {
        var dep = source as Microsoft.UI.Xaml.DependencyObject;
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
        if (Vm is null || !Vm.IsConnected)
        {
            return;
        }

        var dialog = new Dialogs.ListEditDialog(Vm, existing: null);
        dialog.XamlRoot = XamlRoot;
        await dialog.ShowAsync();
    }
}
