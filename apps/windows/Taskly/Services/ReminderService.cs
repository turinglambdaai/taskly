using System.Globalization;
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
    private readonly ITasklyBackend _backend;
    private readonly I18nService _i18n;
    private System.Threading.Timer? _timer;
    private bool _notificationsDisabled;

    public ReminderService(ITasklyBackend backend, I18nService i18n)
    {
        _backend = backend;
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
            var tasks = _backend.GetDueTasksAsync().GetAwaiter().GetResult();
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
                        $"{task.Text}\n{_i18n.T("reminderDueAt")}: {dueLine}");
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

    private void Notify(string title, string body)
    {
        if (_notificationsDisabled)
        {
            return;
        }

        try
        {
            new ToastContentBuilder()
                .AddText(title)
                .AddText(body)
                .Show();
        }
        catch
        {
            // No notification permission/transport: stay silent this session.
            _notificationsDisabled = true;
        }
    }

    public void Dispose()
    {
        _timer?.Dispose();
    }
}
