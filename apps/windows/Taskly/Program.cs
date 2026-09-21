using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using System.Globalization;
using System.Runtime.InteropServices;
using Velopack;
#if TASKLY_RIVET
using Taskly.Models;
using Taskly.Services;
#endif

namespace Taskly;

/// <summary>
/// Custom entry point (DisableXamlGeneratedMain). Contract parity with the
/// macOS/Linux ports: normal arguments route to the CLI before any GUI runtime
/// initialization (headless-safe); no arguments opens the WinUI 3 window.
/// Experimental Rivet builds also expose an internal CI-only runtime smoke.
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

#if TASKLY_RIVET
        if (args.Length > 0 && string.Equals(args[0], "__rivet-smoke", StringComparison.Ordinal))
        {
            AttachConsole(-1);
            var exitCode = RunRivetSmokeAsync(args.Skip(1).FirstOrDefault())
                .GetAwaiter()
                .GetResult();
            System.Console.Out.Flush();
            System.Console.Error.Flush();

            // Do not call Environment.Exit here. The smoke owns an embedded
            // Racket runtime and has already awaited its disposal; returning
            // normally lets native/Racket thread teardown finish before the
            // Windows process terminates.
            Environment.ExitCode = exitCode;
            return;
        }
#endif

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

#if TASKLY_RIVET
    private static async Task<int> RunRivetSmokeAsync(string? databasePath)
    {
        var deleteDatabase = string.IsNullOrWhiteSpace(databasePath);
        var path = deleteDatabase
            ? Path.Combine(Path.GetTempPath(), $"taskly-rivet-{Guid.NewGuid():N}.db")
            : Path.GetFullPath(databasePath!);

        try
        {
            await using var backend = new RivetTasklyBackend();
            var opened = await backend.OpenAsync(path);
            var list = opened.Lists.FirstOrDefault()
                ?? throw new InvalidOperationException("Rivet smoke opened a database without a default list.");

            var marker = $"rivet-smoke-{Guid.NewGuid():N}";
            await backend.AddTaskAsync(new TaskItem(
                0,
                list.Id,
                marker,
                DateTime.Now.ToString("o", CultureInfo.InvariantCulture)));

            var snapshot = await backend.LoadSnapshotAsync(TaskViewType.All, null, true);
            if (!snapshot.Tasks.Any(task => string.Equals(task.Text, marker, StringComparison.Ordinal)))
            {
                throw new InvalidOperationException("Rivet smoke task did not round-trip through Racket/SQLite.");
            }

            await backend.CloseAsync();
            System.Console.WriteLine("Taskly embedded Rivet smoke: OK");
            return 0;
        }
        catch (Exception ex)
        {
            System.Console.Error.WriteLine($"Taskly embedded Rivet smoke failed: {ex}");
            return 1;
        }
        finally
        {
            if (deleteDatabase)
            {
                TryDelete(path);
                TryDelete(path + "-wal");
                TryDelete(path + "-shm");
            }
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // A smoke cleanup failure must not hide the runtime result.
        }
    }
#endif
}
