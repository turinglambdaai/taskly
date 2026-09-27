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

        var toggle = new MenuFlyoutItem { Text = Vm.T("menuToggleCompleted") };
        toggle.Click += async (_, _) => await Vm.ToggleCompletedAsync(task);
        menu.Items.Add(toggle);

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
