using System.Globalization;
using Taskly.Data;
using Taskly.Models;
using Microsoft.Toolkit.Uwp.Notifications;

namespace Taskly.Services;

/// <summary>
/// Due-task reminders (PRODUCT-SPEC §9): 60 s poll while connected + a
/// startup check, per-session dedupe, ≤3 individual / >3 aggregated.
/// Transport failures disable notifications for the session — never crash
/// (the 0.6.1 macOS incident is the permanent regression test).
/// </summary>
public sealed class ReminderService : IDisposable
{
    private readonly HashSet<int> _notifiedIds = new();
    private readonly SQLiteDatabase _db;
    private readonly I18nService _i18n;
    private System.Threading.Timer? _timer;
    private bool _notificationsDisabled;

    public ReminderService(SQLiteDatabase db, I18nService i18n)
    {
        _db = db;
        _i18n = i18n;
    }

    /// <summary>Startup check + 60 s recurring check. Call once, after open.</summary>
    public void Start()
    {
        CheckNow();
        _timer ??= new System.Threading.Timer(
            _ => CheckNow(), null, TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(1));
    }

    /// <summary>Called when the active database changes (dedupe is per session).</summary>
    public void ResetNotified()
    {
        _notifiedIds.Clear();
        _notificationsDisabled = false;
    }

    public void CheckNow()
    {
        List<TaskItem> due;
        try
        {
            var tasks = _db.GetAllIncompleteTasksWithDueDateAsync().GetAwaiter().GetResult();
            due = tasks.Where(IsDue).Where(t => _notifiedIds.Add(t.Id)).ToList();
        }
        catch
        {
            return;
        }

        if (due.Count == 0)
        {
            return;
        }

        try
        {
            if (due.Count > 3)
            {
                Notify(
                    _i18n.T("reminderTitle"),
                    _i18n.Format("reminderStartupSummary", due.Count));
            }
            else
            {
                foreach (var task in due)
                {
                    var dueLine = task.DueDate + (string.IsNullOrEmpty(task.DueTime) ? "" : " " + task.DueTime);
                    Notify(
                        _i18n.T("reminderTitle"),
                        $"{task.Text}\n{_i18n.T("reminderDueAt")}: {dueLine}",
                        task.Id);
                }
            }
        }
        catch
        {
            _notificationsDisabled = true;
        }
    }

    private static bool IsDue(TaskItem task)
    {
        if (task.DueDate is null)
        {
            return false;
        }

        var combined = DateParser.CombineDateTime(task.DueDate, task.DueTime);
        if (!DateTime.TryParseExact(combined, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out var due))
        {
            return false;
        }

        return due <= DateTime.Now;
    }

    private void Notify(string title, string body, int taskId = 0)
    {
        if (_notificationsDisabled)
        {
            return;
        }

        try
        {
            var builder = new ToastContentBuilder()
                .AddText(title)
                .AddText(body);

            if (taskId > 0)
            {
                // TickTick/Todoist-style quick actions: complete or snooze
                // without opening the app (activation routes through
                // Program.OnToastActivated).
                builder.AddButton(new ToastButton()
                    .SetContent(_i18n.T("toastComplete"))
                    .AddArgument("action", "complete")
                    .AddArgument("taskId", taskId.ToString()));
                builder.AddButton(new ToastButton()
                    .SetContent(_i18n.T("toastSnooze"))
                    .AddArgument("action", "snooze")
                    .AddArgument("taskId", taskId.ToString()));
            }

            builder.Show();
        }
        catch
        {
            // No notification permission/transport: stay silent this session.
            _notificationsDisabled = true;
        }
    }

    /// <summary>Re-arms a snoozed task's reminder (the notified set would
    /// otherwise swallow the rescheduled due time).</summary>
    public void ClearNotified(int taskId) => _notifiedIds.Remove(taskId);

    /// <summary>Snooze: push the due time one hour forward (adds a time to
    /// date-only tasks). Returns false when the task vanished.</summary>
    public bool SnoozeOneHour(int taskId)
    {
        try
        {
            var task = _db.GetTaskByIdAsync(taskId).GetAwaiter().GetResult();
            if (task is null)
            {
                return false;
            }

            var target = DateTime.Now.AddHours(1);
            task.DueDate = target.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            task.DueTime = target.ToString("HH:mm", CultureInfo.InvariantCulture);
            _db.UpdateTaskAsync(task).GetAwaiter().GetResult();
            ClearNotified(taskId);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Mark a task completed (toast action; UI refreshes through the
    /// normal channels when visible).</summary>
    public bool CompleteTask(int taskId)
    {
        try
        {
            _db.SetTaskCompletedAsync(taskId, true).GetAwaiter().GetResult();
            ClearNotified(taskId);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public void Dispose()
    {
        _timer?.Dispose();
    }
}
