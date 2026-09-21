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
#if TASKLY_RIVET
        SmokeLog("main:entered");
#endif
        // Auto-update hooks (Velopack). Must run before normal app startup.
        VelopackApp.Build().Run();
#if TASKLY_RIVET
        SmokeLog("main:velopack-ready");

        if (args.Length > 0 && string.Equals(args[0], "__rivet-smoke", StringComparison.Ordinal))
        {
            AttachConsole(-1);
            SmokeLog("main:smoke-dispatch");
            var exitCode = RunRivetSmokeAsync(args.Skip(1).FirstOrDefault())
                .GetAwaiter()
                .GetResult();
            SmokeLog($"main:smoke-return:{exitCode}");
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
        RivetTasklyBackend? backend = null;

        try
        {
            SmokeLog($"smoke:begin:{Environment.ProcessId}:x64={Environment.Is64BitProcess}");
            SmokeLog($"smoke:base:{AppContext.BaseDirectory}");
            backend = new RivetTasklyBackend();
            SmokeLog("smoke:backend-created");

            SmokeLog("smoke:open:start");
            var opened = await backend.OpenAsync(path);
            SmokeLog("smoke:open:done");
            var list = opened.Lists.FirstOrDefault()
                ?? throw new InvalidOperationException("Rivet smoke opened a database without a default list.");

            var marker = $"rivet-smoke-{Guid.NewGuid():N}";
            SmokeLog("smoke:add:start");
            await backend.AddTaskAsync(new TaskItem(
                0,
                list.Id,
                marker,
                DateTime.Now.ToString("o", CultureInfo.InvariantCulture)));
            SmokeLog("smoke:add:done");

            SmokeLog("smoke:snapshot:start");
            var snapshot = await backend.LoadSnapshotAsync(TaskViewType.All, null, true);
            SmokeLog("smoke:snapshot:done");
            if (!snapshot.Tasks.Any(task => string.Equals(task.Text, marker, StringComparison.Ordinal)))
            {
                throw new InvalidOperationException("Rivet smoke task did not round-trip through Racket/SQLite.");
            }

            SmokeLog("smoke:close:start");
            await backend.CloseAsync();
            SmokeLog("smoke:close:done");
            System.Console.WriteLine("Taskly embedded Rivet smoke: OK");
            return 0;
        }
        catch (Exception ex)
        {
            SmokeLog($"smoke:managed-error:{ex.GetType().FullName}:{ex.Message}");
            System.Console.Error.WriteLine($"Taskly embedded Rivet smoke failed: {ex}");
            return 1;
        }
        finally
        {
            if (backend is not null)
            {
                SmokeLog("smoke:dispose:start");
                try
                {
                    await backend.DisposeAsync();
                    SmokeLog("smoke:dispose:done");
                }
                catch (Exception ex)
                {
                    SmokeLog($"smoke:dispose-error:{ex.GetType().FullName}:{ex.Message}");
                }
            }

            if (deleteDatabase)
            {
                TryDelete(path);
                TryDelete(path + "-wal");
                TryDelete(path + "-shm");
            }
            SmokeLog("smoke:finally:done");
        }
    }

    private static void SmokeLog(string message)
    {
        var path = Environment.GetEnvironmentVariable("TASKLY_RIVET_SMOKE_LOG");
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        try
        {
            File.AppendAllText(
                path,
                $"{DateTimeOffset.UtcNow:O} {message}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostics must never alter product behavior.
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
