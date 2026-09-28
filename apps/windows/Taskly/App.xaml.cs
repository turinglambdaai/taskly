using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Taskly;

public partial class App : Application
{
    public static Window? MainWindow { get; private set; }

    public App()
    {
        InitializeComponent();

        // Crash telemetry floor: unhandled XAML-thread exceptions land in
        // ~/.taskly/crash.log (opt-in Sentry replaces this later).
        UnhandledException += (_, args) =>
        {
            try
            {
                var dir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".taskly");
                Directory.CreateDirectory(dir);
                File.AppendAllText(
                    Path.Combine(dir, "crash.log"),
                    $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {args.Message}\n{args.Exception}\n\n");
            }
            catch
            {
                // Last-resort handler must never throw.
            }
        };
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        MainWindow = new Views.MainWindow();
        MainWindow.Activate();
    }
}
