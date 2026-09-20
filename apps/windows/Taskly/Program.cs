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
