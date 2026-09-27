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
            _subscribedVm.SubtitleChanged -= RefreshSubtitle;
            _subscribedVm.PropertyChanged -= OnViewModelPropertyChanged;
        }

        Vm = vm;
        TasksList.ItemsSource = vm?.TaskItems;
        _subscribedVm = vm;
        if (vm is not null)
        {
            vm.CountsChanged += RefreshEmptyState;
            vm.SubtitleChanged += RefreshSubtitle;
            vm.TaskItems.CollectionChanged += (_, _) => RefreshEmptyState();
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
        QuickAddBox.PlaceholderText = Vm.IsConnected
            ? Vm.T("taskListInputHint")
            : Vm.T("taskListInputHintNoDb");

        RefreshTitleAndEmpty();
    }

    private void RefreshTitleAndEmpty()
    {
        if (Vm is null)
        {
            return;
        }

        TitleText.Text = Vm.CurrentTitle;
        SubtitleText.Text = Vm.CurrentSubtitle;
        RefreshEmptyState();
    }

    private void RefreshSubtitle()
    {
        if (Vm is not null)
        {
            // UpdateTitle raises this after the collections already fired,
            // so this is the one place the title reliably catches up too.
            TitleText.Text = Vm.CurrentTitle;
            SubtitleText.Text = Vm.CurrentSubtitle;
        }
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
        SubtitleText.Text = Vm.CurrentSubtitle;

        if (!Vm.IsConnected)
        {
            EmptyIcon.Text = "📂";
            EmptyText.Text = Vm.T("taskListEmptyHint");
            EmptyState.Visibility = Visibility.Visible;
            TasksList.Visibility = Visibility.Collapsed;
            InputArea.Visibility = Visibility.Collapsed;
        }
        else if (Vm.TaskItems.Count == 0)
        {
            EmptyIcon.Text = "✓";
            EmptyText.Text = Vm.T("taskListEmpty");
            EmptyState.Visibility = Visibility.Visible;
            TasksList.Visibility = Visibility.Visible;
            InputArea.Visibility = Visibility.Visible;
        }
        else
        {
            EmptyState.Visibility = Visibility.Collapsed;
            TasksList.Visibility = Visibility.Visible;
            InputArea.Visibility = Visibility.Visible;
        }
    }

    /// <summary>Ctrl+N landing spot (menu accelerator); Ctrl+F focuses the
    /// sidebar search.</summary>
    public void FocusQuickAdd()
    {
        QuickAddBox.Focus(FocusState.Keyboard);
    }

    /// <summary>Keeps the header toggle label in step with the accelerator
    /// and the button itself (either can flip the state).</summary>
    public void SyncShowCompletedLabel()
    {
        if (Vm is not null)
        {
            ShowCompletedToggle.Content = Vm.ShowCompletedTasks
                ? Vm.T("hideCompletedToggle")
                : Vm.T("showCompletedToggle");
        }
    }

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.CurrentView) or nameof(MainViewModel.IsConnected))
        {
            RefreshEmptyState();
        }
    }

    // Row hover lifts the info button to full opacity (it rests at 45%
    // so the list stays quiet; Reminders reveals row actions on hover).
    private void OnTaskPointerEntered(object sender, PointerRoutedEventArgs e)
    {
        SetInfoOpacity(sender, 1.0);
    }

    private void OnTaskPointerExited(object sender, PointerRoutedEventArgs e)
    {
        SetInfoOpacity(sender, 0.45);
    }

    private static void SetInfoOpacity(object sender, double opacity)
    {
        if ((sender as Grid)?.Children.OfType<Button>().LastOrDefault() is { } button)
        {
            button.Opacity = opacity;
        }
    }

    // Right-click row menu (spec §5): toggle completed, delete (no confirm
    // from the row), move to list ▸.
    private void OnTaskContextRequested(object sender, RoutedEventArgs e)
    {
        if (Vm is null || TaskFromElement(sender) is not { } task)
        {
            return;
        }

        var menu = new MenuFlyout();

        var detail = new MenuFlyoutItem { Text = Vm.T("tooltipTaskEdit") };
        detail.Click += async (_, _) =>
        {
            var fresh = await Vm.Tasks.GetTaskByIdAsync(task.Id);
            if (fresh is not null)
            {
                var dialog = new Dialogs.TaskDetailDialog(Vm, fresh);
                dialog.XamlRoot = XamlRoot;
                await dialog.ShowAsync();
            }
        };
        menu.Items.Add(detail);

        menu.Items.Add(new MenuFlyoutSeparator());

        var toggle = new MenuFlyoutItem { Text = Vm.T("menuToggleCompleted") };
        toggle.Click += async (_, _) => await Vm.ToggleCompletedAsync(task);
        menu.Items.Add(toggle);

        // Date quick actions: reschedule in one click (the most frequent
        // task operation after completion).
        var todayItem = new MenuFlyoutItem { Text = Vm.RelativeDueLabel(0) };
        todayItem.Click += async (_, _) =>
        {
            await Vm.UpdateTaskAsync(task.With(
                dueDate: DateTime.Now.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture)));
        };
        menu.Items.Add(todayItem);

        var tomorrowItem = new MenuFlyoutItem { Text = Vm.RelativeDueLabel(1) };
        tomorrowItem.Click += async (_, _) =>
        {
            await Vm.UpdateTaskAsync(task.With(
                dueDate: DateTime.Now.AddDays(1).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture)));
        };
        menu.Items.Add(tomorrowItem);

        var clearItem = new MenuFlyoutItem { Text = Vm.T("dialogClear") };
        clearItem.Click += async (_, _) =>
        {
            await Vm.UpdateTaskAsync(task.With(clearDueDate: true, clearDueTime: true));
        };
        menu.Items.Add(clearItem);

        menu.Items.Add(new MenuFlyoutSeparator());

        var delete = new MenuFlyoutItem { Text = Vm.T("taskDelete") };
        delete.Click += async (_, _) => await Vm.DeleteTaskAsync(task);
        menu.Items.Add(delete);

        var others = Vm.ListCollection.Where(l => l.Id != task.ListId).ToList();
        if (others.Count > 0)
        {
            var move = new MenuFlyoutSubItem { Text = Vm.T("menuMoveToList") };
            foreach (var list in others)
            {
                var item = new MenuFlyoutItem { Text = $"{list.Icon ?? Models.TodoList.DefaultIcon} {list.Name}" };
                var target = list;
                item.Click += async (_, _) => await Vm.MoveTaskToListAsync(task, target);
                move.Items.Add(item);
            }

            menu.Items.Add(move);
        }

        menu.ShowAt((FrameworkElement)sender);
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
        if (Vm is null)
        {
            return;
        }

        if ((sender as Button)?.Content is Grid checkbox)
        {
            AnimateCheckPop(checkbox);
        }

        if (TaskFromElement(sender) is { } task)
        {
            await Vm.ToggleCompletedAsync(task);
        }
    }

    /// <summary>200 ms pop on the checkbox — the completion micro-interaction.
    /// Pure XAML storyboard (composition animations race XAML state here).</summary>
    private static void AnimateCheckPop(Grid checkbox)
    {
        if (checkbox.RenderTransform is not ScaleTransform scale)
        {
            return;
        }

        var easing = new Microsoft.UI.Xaml.Media.Animation.CircleEase { EasingMode = Microsoft.UI.Xaml.Media.Animation.EasingMode.EaseOut };
        var growX = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation { From = 1, To = 1.28, AutoReverse = true,
            Duration = new Duration(TimeSpan.FromMilliseconds(200)), EasingFunction = easing };
        var growY = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation { From = 1, To = 1.28, AutoReverse = true,
            Duration = new Duration(TimeSpan.FromMilliseconds(200)), EasingFunction = easing };
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(growX, checkbox);
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(growY, checkbox);
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(growX, "(UIElement.RenderTransform).(ScaleTransform.ScaleX)");
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(growY, "(UIElement.RenderTransform).(ScaleTransform.ScaleY)");
        var board = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
        board.Children.Add(growX);
        board.Children.Add(growY);
        board.Begin();
    }

    // ---------------- inline edit (double-click, spec §5) ----------------

    private string? _inlineOriginal;

    private async void OnTaskDoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (Vm is null || TaskFromElement(e.OriginalSource) is not { } task)
        {
            return;
        }

        if (task.IsEditing)
        {
            return;
        }

        _inlineOriginal = task.Text;
        task.IsEditing = true;

        // Focus once the template swap has materialized.
        await Task.Delay(30);
        var row = RowFromElement(e.OriginalSource);
        if (row is not null)
        {
            var box = FindDescendants(row).OfType<TextBox>().FirstOrDefault();
            if (box is not null)
            {
                box.Focus(FocusState.Keyboard);
                box.SelectAll();
            }
        }
    }

    /// <summary>The row root (the template Grid carrying the TaskItem).</summary>
    private static FrameworkElement? RowFromElement(object? source)
    {
        var dep = source as DependencyObject;
        while (dep is not null)
        {
            if (dep is FrameworkElement { DataContext: TaskItem } fe)
            {
                return fe;
            }

            dep = VisualTreeHelper.GetParent(dep);
        }

        return null;
    }

    private static IEnumerable<DependencyObject> FindDescendants(DependencyObject root)
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            yield return child;
            foreach (var nested in FindDescendants(child))
            {
                yield return nested;
            }
        }
    }

    private async void OnInlineEditKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
    {
        if (sender is not TextBox box || box.DataContext is not TaskItem task)
        {
            return;
        }

        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            e.Handled = true;
            await CommitInlineEdit(task, box);
        }
        else if (e.Key == Windows.System.VirtualKey.Escape)
        {
            e.Handled = true;
            task.Text = _inlineOriginal ?? task.Text;
            task.IsEditing = false;
        }
    }

    private async void OnInlineEditLostFocus(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox box && box.DataContext is TaskItem { IsEditing: true } task)
        {
            await CommitInlineEdit(task, box);
        }
    }

    private async Task CommitInlineEdit(TaskItem task, TextBox box)
    {
        var trimmed = box.Text.Trim();
        if (trimmed.Length == 0)
        {
            task.Text = _inlineOriginal ?? task.Text; // blank silently reverts
            task.IsEditing = false;
            return;
        }

        task.IsEditing = false;
        if (Vm is not null && trimmed != task.Text)
        {
            await Vm.UpdateTaskAsync(task.With(text: trimmed));
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

}
