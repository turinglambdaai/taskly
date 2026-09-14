using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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
        }

        Vm = vm;
        TasksList.ItemsSource = vm?.TaskItems;
        _subscribedVm = vm;
        if (vm is not null)
        {
            vm.CountsChanged += RefreshEmptyState;
            vm.TaskItems.CollectionChanged += (_, _) => RefreshEmptyState();
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

    private TaskItem? TaskFromContext(object? sender)
    {
        return (sender as FrameworkElement)?.DataContext as TaskItem
            ?? (sender as FrameworkElement)?.Tag as TaskItem;
    }

    private async void OnToggleCompleted(object sender, RoutedEventArgs e)
    {
        if (Vm is not null && TaskFromContext(sender) is { } task)
        {
            await Vm.ToggleCompletedAsync(task);
        }
    }

    private async void OnOpenDetail(object sender, RoutedEventArgs e)
    {
        if (Vm is null || TaskFromContext(sender) is not { } task)
        {
            return;
        }

        var dialog = new Dialogs.TaskDetailDialog(Vm, task);
        await dialog.ShowAsync(XamlRoot);
    }

    private async void OnTaskDoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (Vm is null || TasksList.SelectedItem is not TaskItem task)
        {
            return;
        }

        var dialog = new Dialogs.TaskDetailDialog(Vm, task);
        await dialog.ShowAsync(XamlRoot);
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

    public void SetSearchTextProgrammatic(string text)
    {
        _searchChangedByProgram = true;
        SearchBox.Text = text;
        _searchChangedByProgram = false;
    }
}
