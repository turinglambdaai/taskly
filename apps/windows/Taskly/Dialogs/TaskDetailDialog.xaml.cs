using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Taskly.Models;
using Taskly.ViewModels;

namespace Taskly.Dialogs;

/// <summary>Full task editor (ⓘ). Save / Delete (confirm) / Cancel.</summary>
public sealed partial class TaskDetailDialog : ContentDialog
{
    private readonly MainViewModel _vm;
    private readonly TaskItem _original;
    private string? _dueDate;
    private string? _dueTime;

    public TaskDetailDialog(MainViewModel vm, TaskItem task)
    {
        InitializeComponent();
        _vm = vm;
        _original = task;
        _dueDate = task.DueDate;
        _dueTime = task.DueTime;

        ApplyLanguage();

        TaskTextBox.Text = task.Text;
        NotesBox.Text = task.Notes ?? "";
        SyncPickersFromState();

        PrimaryButtonClick += async (_, args) =>
        {
            var trimmed = TaskTextBox.Text.Trim();
            if (trimmed.Length == 0)
            {
                args.Cancel = true; // blank text silently keeps the dialog open
                return;
            }

            var updated = _original.With(
                text: trimmed,
                notes: string.IsNullOrWhiteSpace(NotesBox.Text) ? null : NotesBox.Text,
                dueDate: _dueDate, dueTime: _dueTime,
                clearDueDate: _dueDate is null,
                clearDueTime: _dueTime is null,
                clearNotes: string.IsNullOrWhiteSpace(NotesBox.Text));
            await _vm.UpdateTaskAsync(updated);
        };
    }

    private void ApplyLanguage()
    {
        Title = _vm.T("dialogTaskDetail");
        PrimaryButtonText = _vm.T("dialogSave");
        CloseButtonText = _vm.T("dialogCancel");
        TaskLabel.Text = _vm.T("labelTask");
        NotesLabel.Text = _vm.T("labelNotes");
        DateLabel.Text = _vm.T("labelDate");
        TimeLabel.Text = _vm.T("labelTime");
        ClearDateButton.Content = _vm.T("dialogClear");
        ClearTimeButton.Content = _vm.T("dialogClear");
    }

    private bool _syncing;

    private void SyncPickersFromState()
    {
        _syncing = true;
        if (_dueDate is not null
            && DateTimeOffset.TryParseExact(_dueDate, "yyyy-MM-dd",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out var date))
        {
            DatePicker.Date = date;
        }
        else
        {
            DatePicker.Date = DateTimeOffset.Now;
        }

        ClearDateButton.Visibility = _dueDate is null ? Visibility.Collapsed : Visibility.Visible;

        if (_dueTime is not null
            && TimeSpan.TryParseExact(_dueTime, @"hh\:mm",
                System.Globalization.CultureInfo.InvariantCulture, out var time))
        {
            TimePicker.Time = time;
        }
        else
        {
            TimePicker.Time = new TimeSpan(9, 0, 0);
        }

        TimePicker.IsEnabled = _dueDate is not null;
        ClearTimeButton.Visibility = _dueTime is null ? Visibility.Collapsed : Visibility.Visible;
        _syncing = false;
    }

    private void OnDateChanged(object sender, DatePickerValueChangedEventArgs args)
    {
        if (_syncing)
        {
            return;
        }

        _dueDate = args.NewDate.ToString("yyyy-MM-dd");
        SyncPickersFromState();
    }

    private void OnTimeChanged(object sender, TimePickerValueChangedEventArgs args)
    {
        if (_syncing || _dueDate is null)
        {
            return;
        }

        _dueTime = args.NewTime.ToString(@"hh\:mm");
    }

    private void OnClearDate(object sender, RoutedEventArgs e)
    {
        _dueDate = null;
        _dueTime = null;
        SyncPickersFromState();
    }

    private void OnClearTime(object sender, RoutedEventArgs e)
    {
        _dueTime = null;
        SyncPickersFromState();
    }
}
