using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Rivet.Runtime;
using Taskly.RivetGenerated;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: Taskly.RivetSmoke <taskly-repo-root>");
            return 2;
        }

        var root = Path.GetFullPath(args[0]);
        var backend = Path.Combine(root, "racket", "taskly", "backend.rkt");
        if (!File.Exists(backend))
        {
            throw new FileNotFoundException("Taskly Rivet backend was not found.", backend);
        }

        var temp = Path.Combine(Path.GetTempPath(), $"taskly-rivet-smoke-{Guid.NewGuid():N}");
        Directory.CreateDirectory(temp);
        var database = Path.Combine(temp, "taskly.db");

        try
        {
            var startInfo = new ProcessStartInfo("racket");
            startInfo.ArgumentList.Add(backend);

            await using var client = await ProcessRivetClient.StartAsync(startInfo);
            var api = new RivetAPI(client);

            var initial = await api.OpenDatabaseAsync(database);
            if (initial.Lists.Count != 1)
            {
                throw new InvalidOperationException($"Expected one default list, received {initial.Lists.Count}.");
            }
            if (initial.Tasks.Count != 0 || initial.Counts.All != 0)
            {
                throw new InvalidOperationException("Fresh database snapshot is not empty.");
            }

            var created = await api.AddTaskAsync("managed smoke", null, null, null, "rivet");
            if (created.Text != "managed smoke" || created.Completed)
            {
                throw new InvalidOperationException("Created task did not round-trip through Rivet.");
            }

            var snapshot = await api.LoadSnapshotAsync("all", null, false);
            if (snapshot.Tasks.Count != 1 || snapshot.Counts.All != 1)
            {
                throw new InvalidOperationException("Snapshot did not include the created task.");
            }
            if (!snapshot.Tasks.Any(item => item.Id == created.Id && item.Notes == "rivet"))
            {
                throw new InvalidOperationException("Typed Task DTO did not preserve fields.");
            }

            var completed = await api.SetCompletedAsync(created.Id, true);
            if (!completed.Completed)
            {
                throw new InvalidOperationException("Completion update did not round-trip.");
            }

            Console.WriteLine("Taskly managed Rivet smoke passed.");
            return 0;
        }
        finally
        {
            try
            {
                Directory.Delete(temp, recursive: true);
            }
            catch
            {
                // Best-effort cleanup on CI runners; process disposal may briefly
                // leave SQLite sidecar handles visible to the filesystem.
            }
        }
    }
}
