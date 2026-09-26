using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Taskly.Models;
using Taskly.ViewModels;

namespace Taskly.Views;

public sealed partial class TaskPane : UserControl
{
    public MainViewModel? Vm { get; set; }
    private MainViewModel? _subscribedVm;
    private bool _searchChangedByProgram;

    public TaskPane()
    {
        InitializeComponent();
    }

    public void SetViewModel(MainViewModel vm)
    {
        if (_subscribedVm is not null)
        {
            _subscribedVm.CountsChanged -= RefreshEmptyState;
            _subscribedVm.CalendarScrollRequested -= ScrollCalendarTo;
            _subscribedVm.CalendarCountsChanged -= RenderMonthGrid;
            _subscribedVm.CalendarRows.CollectionChanged -= OnCalendarRowsChanged;
            _subscribedVm.PropertyChanged -= OnViewModelPropertyChanged;
        }

        Vm = vm;
        TasksList.ItemsSource = vm?.TaskItems;
        CalendarList.ItemsSource = vm?.CalendarRows;
        _subscribedVm = vm;
        if (vm is not null)
        {
            vm.CountsChanged += RefreshEmptyState;
            vm.TaskItems.CollectionChanged += (_, _) => RefreshEmptyState();
            vm.CalendarRows.CollectionChanged += OnCalendarRowsChanged;
            vm.CalendarCountsChanged += RenderMonthGrid;
            vm.CalendarScrollRequested += ScrollCalendarTo;
            vm.PropertyChanged += OnViewModelPropertyChanged;
        }

        ApplyLanguage();
        RefreshEmptyState();
    }

    public void ApplyLanguage()
    {
        if (Vm is null)
        {
            return;
        }

        ToolTipService.SetToolTip(SidebarToggle,
            Vm.IsSidebarVisible ? Vm.T("sidebarHide") : Vm.T("sidebarShow"));
        ShowCompletedToggle.Content = Vm.ShowCompletedTasks
            ? Vm.T("hideCompletedToggle")
            : Vm.T("showCompletedToggle");
        SearchBox.PlaceholderText = Vm.T("searchHint");
        QuickAddBox.PlaceholderText = Vm.IsConnected
            ? Vm.T("taskListInputHint")
            : Vm.T("taskListInputHintNoDb");

        UpdateCalendarHeader();
        RefreshWeekdayHeader();
        RenderMonthGrid();
        RefreshTitleAndEmpty();
    }

    private void RefreshTitleAndEmpty()
    {
        if (Vm is null)
        {
            return;
        }

        TitleText.Text = Vm.CurrentTitle;
        RefreshEmptyState();
    }

    private void RefreshEmptyState()
    {
        if (Vm is null)
        {
            return;
        }

        // Connection completes asynchronously after ApplyLanguage ran, so the
        // quick-add hint must follow every connection-state change, not just
        // language changes.
        QuickAddBox.PlaceholderText = Vm.IsConnected
            ? Vm.T("taskListInputHint")
            : Vm.T("taskListInputHintNoDb");

        TitleText.Text = Vm.CurrentTitle;

        if (!Vm.IsConnected)
        {
            EmptyIcon.Text = "📂";
            EmptyText.Text = Vm.T("taskListEmptyHint");
            EmptyState.Visibility = Visibility.Visible;
            TasksList.Visibility = Visibility.Collapsed;
            CalendarArea.Visibility = Visibility.Collapsed;
            InputArea.Visibility = Visibility.Collapsed;
        }
        else if (Vm.IsCalendarView)
        {
            EmptyState.Visibility = Visibility.Collapsed;
            TasksList.Visibility = Visibility.Collapsed;
            CalendarArea.Visibility = Visibility.Visible;
            InputArea.Visibility = Visibility.Visible;
            UpdateCalendarHeader();
            RefreshWeekdayHeader();
            RenderMonthGrid();
        }
        else if (Vm.TaskItems.Count == 0)
        {
            EmptyIcon.Text = "✓";
            EmptyText.Text = Vm.T("taskListEmpty");
            EmptyState.Visibility = Visibility.Visible;
            TasksList.Visibility = Visibility.Visible;
            CalendarArea.Visibility = Visibility.Collapsed;
            InputArea.Visibility = Visibility.Visible;
        }
        else
        {
            EmptyState.Visibility = Visibility.Collapsed;
            TasksList.Visibility = Visibility.Visible;
            CalendarArea.Visibility = Visibility.Collapsed;
            InputArea.Visibility = Visibility.Visible;
        }
    }

    // ---------------- calendar view (PRODUCT-SPEC §4b) ----------------

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (Vm is null)
        {
            return;
        }

        switch (e.PropertyName)
        {
            case nameof(MainViewModel.CalendarYear):
            case nameof(MainViewModel.CalendarMonth):
                UpdateCalendarHeader();
                RefreshWeekdayHeader();
                RenderMonthGrid();
                break;
            case nameof(MainViewModel.SelectedCalendarDate):
                RenderMonthGrid();
                break;
            case nameof(MainViewModel.CurrentView):
            case nameof(MainViewModel.IsConnected):
                RefreshEmptyState();
                break;
        }
    }

    private void OnCalendarRowsChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        if (Vm is null)
        {
            return;
        }

        // Re-entering the calendar pane (e.g. search cleared) rides on this
        // notification: IsCalendarView is not observable on its own.
        RefreshEmptyState();

        CalEmptyState.Visibility = Vm.CalendarRows.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        CalEmptyText.Text = Vm.T("taskListEmpty");
    }

    private void UpdateCalendarHeader()
    {
        if (Vm is null)
        {
            return;
        }

        CalMonthTitle.Text = Vm.CalendarMonthTitle;
        CalTodayButton.Content = Vm.T("calTodayButton");
    }

    private void RefreshWeekdayHeader()
    {
        if (Vm is null)
        {
            return;
        }

        WeekdayHeader.Children.Clear();
        var names = Vm.CalendarWeekdayHeader;
        var secondary = Models.UiTheme.BrushOf(Models.UiTheme.Secondary);
        for (var i = 0; i < names.Count && i < 7; i++)
        {
            var label = new TextBlock
            {
                Text = names[i],
                FontSize = 12,
                Foreground = secondary,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 2, 0, 4),
            };
            Grid.SetColumn(label, i);
            WeekdayHeader.Children.Add(label);
        }
    }

    private void RenderMonthGrid()
    {
        // The year-then-month assignment order means PropertyChanged can
        // fire while month is still 0; DateTime would throw on that state.
        if (Vm is null || !Vm.IsConnected || !Vm.IsCalendarView || Vm.CalendarYear == 0
            || Vm.CalendarMonth is < 1 or > 12)
        {
            MonthGrid.Children.Clear();
            return;
        }

        MonthGrid.Children.Clear();
        var todayKey = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var first = new DateTime(Vm.CalendarYear, Vm.CalendarMonth, 1);
        // Column of the 1st under the language's week start (§4b): Monday
        // first for zh, Sunday first for en.
        var mondayFirst = Vm.CalendarWeekdayHeader.Count > 0
            && Vm.CalendarWeekdayHeader[0] == Vm.T("calWeekdayShort1");
        var col = mondayFirst ? ((int)first.DayOfWeek + 6) % 7 : (int)first.DayOfWeek;
        var gridStart = first.AddDays(-col);

        for (var i = 0; i < 42; i++)
        {
            var day = gridStart.AddDays(i);
            var cell = BuildDayCell(day, todayKey);
            Grid.SetRow(cell, i / 7);
            Grid.SetColumn(cell, i % 7);
            MonthGrid.Children.Add(cell);
        }
    }

    private Button BuildDayCell(DateTime day, string todayKey)
    {
        var dayKey = day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var isCurrentMonth = day.Year == Vm!.CalendarYear && day.Month == Vm.CalendarMonth;
        var isToday = dayKey == todayKey;
        var isSelected = Vm.SelectedCalendarDate == dayKey;

        // Static theme projection (same mechanism as the task-row brushes) —
        // ResourceDictionary indexer lookups cannot see ThemeDictionaries.
        var onSurface = Models.UiTheme.BrushOf(Models.UiTheme.OnSurface);
        var tertiary = Models.UiTheme.BrushOf(Models.UiTheme.Tertiary);
        var accent = Models.UiTheme.BrushOf(Models.UiTheme.Accent);
        var numberColor = isToday ? accent : (isCurrentMonth ? onSurface : tertiary);
        var transparent = new SolidColorBrush(Microsoft.UI.Colors.Transparent);

        var dots = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Center,
            Spacing = 3,
            Margin = new Thickness(0, 0, 0, 4),
        };
        if (Vm.CalendarDayCounts.TryGetValue(dayKey, out var count))
        {
            for (var i = 0; i < Math.Min(count, 3); i++)
            {
                dots.Children.Add(new Ellipse
                {
                    Width = 4,
                    Height = 4,
                    Fill = accent,
                });
            }
        }

        var content = new Grid { MinHeight = 40 };
        content.Children.Add(new TextBlock
        {
            Text = day.Day.ToString(CultureInfo.InvariantCulture),
            FontSize = 13,
            FontWeight = isToday ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
            Foreground = numberColor,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 6, 0, 0),
        });
        content.Children.Add(dots);

        var button = new Button
        {
            Content = content,
            MinHeight = 44,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Padding = new Thickness(0),
            BorderThickness = isSelected ? new Thickness(1) : new Thickness(0),
            CornerRadius = new CornerRadius(8),
            Background = transparent,
            BorderBrush = isSelected ? accent : transparent,
            Tag = dayKey,
        };
        button.Click += OnDayCellClick;
        return button;
    }

    private async void OnDayCellClick(object sender, RoutedEventArgs e)
    {
        if (Vm is null || (sender as FrameworkElement)?.Tag is not string dayKey)
        {
            return;
        }

        await Vm.SelectCalendarDateFromGridAsync(dayKey);
    }

    private async void OnCalPrevMonth(object sender, RoutedEventArgs e)
    {
        if (Vm is not null)
        {
            await Vm.NavigateCalendarMonthAsync(-1);
        }
    }

    private async void OnCalNextMonth(object sender, RoutedEventArgs e)
    {
        if (Vm is not null)
        {
            await Vm.NavigateCalendarMonthAsync(1);
        }
    }

    private async void OnCalToday(object sender, RoutedEventArgs e)
    {
        if (Vm is not null)
        {
            await Vm.GoCalendarTodayAsync();
        }
    }

    private void ScrollCalendarTo(string? dateKey)
    {
        if (dateKey is null)
        {
            return;
        }

        var header = Vm?.CalendarRows.OfType<CalendarSectionHeader>()
            .FirstOrDefault(h => h.DateKey == dateKey);
        if (header is not null)
        {
            CalendarList.ScrollIntoView(header);
        }
    }

    private void OnToggleSidebar(object sender, RoutedEventArgs e)
    {
        if (Vm is null)
        {
            return;
        }

        SidebarToggleRequested?.Invoke();
    }

    /// <summary>Raised when the user wants the sidebar shown/hidden.</summary>
    public event Action? SidebarToggleRequested;

    /// <summary>Row controls bind TaskItem as DataContext; walk up from the
    /// tapped element (double-tap lands deep inside the template).</summary>
    private static TaskItem? TaskFromElement(object? source)
    {
        var dep = source as DependencyObject;
        while (dep is not null)
        {
            if (dep is FrameworkElement { DataContext: TaskItem task })
            {
                return task;
            }

            dep = VisualTreeHelper.GetParent(dep);
        }

        return null;
    }

    private async void OnToggleCompleted(object sender, RoutedEventArgs e)
    {
        if (Vm is not null && TaskFromElement(sender) is { } task)
        {
            await Vm.ToggleCompletedAsync(task);
        }
    }

    private async void OnOpenDetail(object sender, RoutedEventArgs e)
    {
        if (Vm is null || TaskFromElement(sender) is not { } task)
        {
            return;
        }

        var dialog = new Dialogs.TaskDetailDialog(Vm, task);
        dialog.XamlRoot = XamlRoot;
        await dialog.ShowAsync();
    }

    private async Task OpenDetailFor(TaskItem? task)
    {
        if (Vm is null || task is null)
        {
            return;
        }

        var dialog = new Dialogs.TaskDetailDialog(Vm, task);
        dialog.XamlRoot = XamlRoot;
        await dialog.ShowAsync();
    }

    private async void OnTaskDoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        await OpenDetailFor(TaskFromElement(e.OriginalSource));
    }

    private async void OnCalendarDoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        await OpenDetailFor(TaskFromElement(e.OriginalSource));
    }

    private async void OnToggleShowCompleted(object sender, RoutedEventArgs e)
    {
        if (Vm is null)
        {
            return;
        }

        await Vm.ToggleShowCompletedAsync();
        ShowCompletedToggle.Content = Vm.ShowCompletedTasks
            ? Vm.T("hideCompletedToggle")
            : Vm.T("showCompletedToggle");
    }

    private async void OnQuickAddKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter && Vm is not null)
        {
            var text = QuickAddBox.Text;
            QuickAddBox.Text = "";
            await Vm.QuickAddAsync(text);
        }
    }

    private async void OnSearchKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter && Vm is not null)
        {
            await Vm.SetSearchAsync(SearchBox.Text);
        }
    }

    private async void OnSearchTextChanged(object sender, TextChangedEventArgs args)
    {
        if (_searchChangedByProgram || Vm is null)
        {
            return;
        }

        await Vm.SetSearchAsync(SearchBox.Text);
    }
}
