using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Taskly.Models;
using Taskly.ViewModels;

namespace Taskly.Views;

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
                ListsList.ItemClick -= OnListItemClick;
                ListsList.RightTapped -= OnListRightTapped;
            }

            Vm = vm;
            ListsList.ItemsSource = vm?.ListCollection;
            _subscribedVm = vm;
            if (vm is not null)
            {
                vm.CountsChanged += RefreshCounts;
                ListsList.ItemClick += OnListItemClick;
                ListsList.RightTapped += OnListRightTapped;
            }

            ApplyLanguage();
        }

        public void ApplyLanguage()
        {
            if (Vm is null)
            {
                return;
            }

            // Monochrome Segoe Fluent glyphs (E787 calendar, E823 clock,
            // E8FD list, E73E checkmark) — quieter than emoji, matches the
            // Reminders-style sidebar.
            TileTodayIcon.Text = "\uE787";
            TileTodayLabel.Text = Vm.T("navToday");
            TilePlannedIcon.Text = "\uE823";
            TilePlannedLabel.Text = Vm.T("navPlanned");
            TileAllIcon.Text = "\uE8FD";
            TileAllLabel.Text = Vm.T("navAll");
            TileCompletedIcon.Text = "\uE73E";
            TileCompletedLabel.Text = Vm.T("navCompleted");
            MyListsHeader.Text = Vm.T("sectionMyLists");
            RefreshCounts();
        }

    public void ShowStatus(string message) => Vm?.ShowTransientStatus(message);

    private void RefreshCounts()
    {
        if (Vm is null)
        {
            return;
        }

        TileTodayCount.Text = Vm.TodayCount > 0 ? Vm.TodayCount.ToString() : "";
        TilePlannedCount.Text = Vm.PlannedCount > 0 ? Vm.PlannedCount.ToString() : "";
        TileAllCount.Text = Vm.AllCount > 0 ? Vm.AllCount.ToString() : "";
        TileCompletedCount.Text = Vm.CompletedCount > 0 ? Vm.CompletedCount.ToString() : "";
    }

    private async void OnTileToday(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Today);

    private async void OnTilePlanned(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Planned);

    private async void OnTileAll(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.All);

    private async void OnTileCompleted(object sender, RoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Completed);

    private async void OnListItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is TodoList list)
        {
            await Vm.SelectViewAsync(TaskViewType.List, list.Id);
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
