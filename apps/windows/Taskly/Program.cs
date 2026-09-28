using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;
using Velopack;

namespace Taskly;

/// <summary>
/// Custom entry point (DisableXamlGeneratedMain). Contract parity with the
/// macOS/Linux ports: ANY argument routes to the CLI before any GUI runtime
/// initialization (headless-safe); no arguments opens the WinUI 3 window.
/// </summary>
public static class Program
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AttachConsole(int dwProcessId);

    [STAThread]
    public static void Main(string[] args)
    {
        // Auto-update hooks (Velopack). Must run before anything else.
        VelopackApp.Build().Run();

        // Toast button actions (完成/稍后提醒). Runs headless when the
        // process was launched by the click from a dismissed toast.
        Microsoft.Toolkit.Uwp.Notifications.ToastNotificationManagerCompat.OnActivated +=
            e =>
            {
                // ToastNotificationActivatedEventArgsCompat exposes the
                // argument string; parse key=value pairs from it.
                var action = (string?)null;
                var idRaw = (string?)null;
                foreach (var part in (e.Argument ?? string.Empty).Split(';'))
                {
                    var kv = part.Split('=', 2);
                    if (kv.Length == 2 && kv[0] == "action") { action = kv[1]; }
                    if (kv.Length == 2 && kv[0] == "taskId") { idRaw = kv[1]; }
                }
                if (action is null || !int.TryParse(idRaw, out var id))
                {
                    return;
                }

                var db = new Taskly.Data.SQLiteDatabase();
                var config = new Taskly.Data.ConfigService();
                config.Load();
                if (!string.IsNullOrEmpty(config.LastDbPath))
                {
                    db.SetDatabasePath(config.LastDbPath);
                    db.EnsureConnectedAsync().GetAwaiter().GetResult();
                    var reminders = new Taskly.Services.ReminderService(db, Taskly.Services.I18nService.Instance);
                    if (action == "complete")
                    {
                        reminders.CompleteTask(id);
                    }
                    else if (action == "snooze")
                    {
                        reminders.SnoozeOneHour(id);
                    }
                }

                Taskly.Services.ToastActivationBridge.NotifyUi(action, id);
            };

        if (args.Length > 0)
        {
            // WinExe has no console; attach to the parent terminal for CLI IO.
            AttachConsole(-1);
            int exitCode = Cli.CliEngine.Run(args);
            // Flush before detaching, then exit with the contract code.
            System.Console.Out.Flush();
            System.Console.Error.Flush();
            Environment.Exit(exitCode);
        }

        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(p =>
        {
            var context = new DispatcherQueueSynchronizationContext(
                DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            _ = new App();
        });
    }
}
