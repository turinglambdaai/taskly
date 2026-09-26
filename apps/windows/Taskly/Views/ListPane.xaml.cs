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
                _subscribedVm.PropertyChanged -= OnViewModelPropertyChanged;
                ListsList.ItemClick -= OnListItemClick;
                ListsList.RightTapped -= OnListRightTapped;
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
            }

            WireTileHover(TileToday);
            WireTileHover(TilePlanned);
            WireTileHover(TileAll);
            WireTileHover(TileCompleted);
            WireTileHover(TileCalendar);

            ApplyLanguage();
        }

        // Hover = a slight lift (never gray): plain surfaces keep the fill.
        private void WireTileHover(Border tile)
        {
            // Hover eases an unselected tile toward full saturation; the
            // selected tile stays at full.
            tile.PointerEntered += (_, _) =>
                tile.Opacity = tile.BorderThickness.Left > 0 ? 1.0 : 0.88;
            tile.PointerExited += (_, _) =>
                tile.Opacity = tile.BorderThickness.Left > 0 ? 1.0 : 0.72;
        }

        private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(MainViewModel.CurrentView))
            {
                RefreshTileSelection();
            }
        }

        /// <summary>Active view's tile gets a white inset ring (DESIGN-TOKENS).</summary>
        private void RefreshTileSelection()
        {
            if (Vm is null)
            {
                return;
            }

            SetSelected(TileToday, Vm.CurrentView == TaskViewType.Today);
            SetSelected(TilePlanned, Vm.CurrentView == TaskViewType.Planned);
            SetSelected(TileAll, Vm.CurrentView == TaskViewType.All);
            SetSelected(TileCompleted, Vm.CurrentView == TaskViewType.Completed);
            SetSelected(TileCalendar, Vm.CurrentView == TaskViewType.Calendar);
        }

        private static void SetSelected(Border tile, bool selected)
        {
            tile.BorderThickness = selected ? new Thickness(2) : new Thickness(0);
            tile.BorderBrush = selected
                ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White)
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
            tile.Padding = selected ? new Thickness(10, 8, 10, 8) : new Thickness(12, 10, 12, 10);
            // The active view pops to full saturation; the rest recede.
            tile.Opacity = selected ? 1.0 : 0.72;
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
            TileCalendarIcon.Text = "\uE8BF";
            TileCalendarLabel.Text = Vm.T("navCalendar");
            MyListsHeader.Text = Vm.T("sectionMyLists");
            RefreshTileSelection();
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

    private async void OnTileToday(object sender, TappedRoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Today);

    private async void OnTilePlanned(object sender, TappedRoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Planned);

    private async void OnTileAll(object sender, TappedRoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.All);

    private async void OnTileCompleted(object sender, TappedRoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Completed);

    private async void OnTileCalendar(object sender, TappedRoutedEventArgs e) =>
        await Vm.SelectViewAsync(TaskViewType.Calendar);

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
