using Taskly.Models;

namespace Taskly.Services;

/// <summary>Bridge from headless toast activation to the live window.</summary>
public static class ToastActivationBridge
{
    /// <summary> Fires on the UI thread when the visible window should
    /// reflect a toast action (complete/snooze). action: "complete"/"snooze".</summary>
    public static event Action<string, int>? UiActionRequested;

    public static void NotifyUi(string action, int taskId) =>
        UiActionRequested?.Invoke(action, taskId);
}
