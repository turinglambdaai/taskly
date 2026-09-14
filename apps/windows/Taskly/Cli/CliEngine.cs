using System.Globalization;
using Taskly.Models;

namespace Taskly.Cli;

/// <summary>
/// CLI engine. Contract: shared/spec/CLI-SPEC.md. Any launch with arguments
/// routes here (before GUI init); exit codes 0/1/2/3/4; errors as JSON on
/// stderr; data as JSON on stdout.
/// </summary>
public static class CliEngine
{
    public static int Run(string[] args)
    {
        var json = false;
        var quiet = false;
        string? dbPath = null;
        var rest = new List<string>();
        CliException? parseError = null;

        for (var i = 0; i < args.Length && parseError is null; i++)
        {
            switch (args[i])
            {
                case "--json":
                    json = true;
                    break;
                case "--quiet" or "-q":
                    quiet = true;
                    break;
                case "--db":
                    if (i + 1 < args.Length)
                    {
                        dbPath = args[++i];
                    }
                    else
                    {
                        parseError = new CliException("Missing value for --db", 2);
                    }

                    break;
                default:
                    rest.Add(args[i]);
                    break;
            }
        }

        if (parseError is not null || rest.Count == 0)
        {
            return Fail(
                parseError?.Message
                ?? "Usage: taskly <command> [options]\nCommands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli",
                parseError?.ExitCode ?? 1);
        }

        var command = rest[0];

        try
        {
            using var ctx = CliContext.Create(command, dbPath, json, quiet);
            var tail = rest.Skip(1).ToArray();
            return command switch
            {
                "list" => CmdList(ctx, tail),
                "lists" => CmdLists(ctx),
                "add" => CmdAdd(ctx, tail),
                "update" => CmdUpdate(ctx, tail),
                "done" => CmdDone(ctx, tail, completed: true),
                "undone" => CmdDone(ctx, tail, completed: false),
                "rm" => CmdRm(ctx, tail),
                "search" => CmdSearch(ctx, tail),
                "mklist" => CmdMkList(ctx, tail),
                "rmlist" => CmdRmList(ctx, tail),
                "install-cli" => CliInstaller.Install(),
                "uninstall-cli" => CliInstaller.Uninstall(),
                "--help" or "-h" or "help" => PrintHelp(),
                _ => Fail($"Unknown command: \"{command}\"", 1),
            };
        }
        catch (CliException ex)
        {
            return Fail(ex.Message, ex.ExitCode);
        }
        catch (ArgumentException ex)
        {
            return Fail(ex.Message, 2);
        }
        catch (Microsoft.Data.Sqlite.SqliteException ex)
        {
            return Fail($"Database error: {ex.Message}", 4);
        }
        catch (Exception ex)
        {
            return Fail(ex.Message, 1);
        }
    }

    private static int PrintHelp()
    {
        Console.WriteLine("Taskly — task manager command-line interface (for AI agents & scripting)");
        Console.WriteLine("Commands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli");
        Console.WriteLine("Global options: --json, --db <path>, --quiet (-q)");
        return 0;
    }

    private static int Fail(string message, int exitCode)
    {
        Console.Error.WriteLine(JsonSerializer.Serialize(
            JsonOutput.ErrorObject(message, exitCode),
            new JsonSerializerOptions { WriteIndented = true }));
        return exitCode;
    }

    // ---------------- options parsing ----------------

    private static readonly HashSet<string> ValueOptions = new()
    {
        "--list", "--view", "--status", "--limit", "--due", "--time",
        "--notes", "--icon", "--color", "--text",
    };

    private static readonly HashSet<string> FlagOptions = new()
    {
        "--clear-due", "--clear-time", "--clear-notes",
    };

    internal sealed class Options
    {
        public Dictionary<string, string?> Values { get; } = new();
        public HashSet<string> Flags { get; } = new();
        public List<string> Positionals { get; } = new();

        public string? Value(string name) => Values.TryGetValue(name, out var v) ? v : null;
        public bool Has(string name) => Flags.Contains(name);
    }

    private static Options ParseOptions(string[] args)
    {
        var options = new Options();
        for (var i = 0; i < args.Length; i++)
        {
            var token = args[i];
            if (token == "--")
            {
                options.Positionals.AddRange(args[(i + 1)..]);
                break;
            }

            if (token.StartsWith("--"))
            {
                var name = token;
                string? inline = null;
                var eq = token.IndexOf('=');
                if (eq > 0)
                {
                    name = token[..eq];
                    inline = token[(eq + 1)..];
                }

                if (ValueOptions.Contains(name))
                {
                    if (inline is not null)
                    {
                        options.Values[name] = inline;
                    }
                    else if (i + 1 < args.Length)
                    {
                        options.Values[name] = args[++i];
                    }
                    else
                    {
                        throw new CliException($"Missing value for {name}", 2);
                    }
                }
                else if (FlagOptions.Contains(name))
                {
                    options.Flags.Add(name);
                }
                else
                {
                    throw new CliException($"Unknown option: {name}", 2);
                }
            }
            else if (token.StartsWith('-') && token.Length > 1)
            {
                throw new CliException($"Unknown option: {token}", 2);
            }
            else
            {
                options.Positionals.Add(token);
            }
        }

        return options;
    }

    private static string RequirePositional(Options options, int index, string what)
    {
        if (index >= options.Positionals.Count)
        {
            throw new CliException($"Missing required argument: <{what}>", 2);
        }

        return options.Positionals[index];
    }

    private static int ParseInt(string s, string what)
    {
        if (!int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v))
        {
            throw new CliException($"Invalid {what}: \"{s}\"", 2);
        }

        return v;
    }

    // ---------------- commands ----------------

    private static int CmdList(CliContext ctx, string[] args)
    {
        var options = ParseOptions(args);
        var listArg = options.Value("--list");
        var viewArg = options.Value("--view");
        var statusArg = options.Value("--status") ?? "incomplete";
        var limit = ParseInt(options.Value("--limit") ?? "1000", "--limit");

        TaskViewType view;
        int? listId = null;
        if (!string.IsNullOrEmpty(listArg))
        {
            view = TaskViewType.List;
            listId = CliHelpers.ResolveListIdAsync(ctx, listArg!).GetAwaiter().GetResult();
        }
        else if (string.IsNullOrEmpty(viewArg))
        {
            view = TaskViewType.All;
        }
        else
        {
            view = viewArg.ToLowerInvariant() switch
            {
                "today" => TaskViewType.Today,
                "planned" or "scheduled" => TaskViewType.Planned,
                "all" => TaskViewType.All,
                "completed" => TaskViewType.Completed,
                _ => throw new CliException(
                    $"Invalid --view: \"{viewArg}\". Use today | planned | all | completed", 2),
            };
        }

        var showCompleted = statusArg.ToLowerInvariant() switch
        {
            "all" => true,
            "incomplete" or "open" or "pending" => false,
            "completed" or "done" => true,
            _ => throw new CliException(
                $"Invalid --status: \"{statusArg}\". Use all | incomplete | completed", 2),
        };

        var tasks = ctx.Tasks.GetTasksByViewAsync(view, listId, limit: limit, showCompleted: showCompleted)
            .GetAwaiter().GetResult();
        CliHelpers.PrintTasks(ctx, tasks);
        return 0;
    }

    private static int CmdLists(CliContext ctx)
    {
        var lists = ctx.Lists.GetAllListsAsync().GetAwaiter().GetResult();
        foreach (var l in lists)
        {
            l.PendingCount = ctx.Tasks.GetTaskCountByListAsync(l.Id).GetAwaiter().GetResult();
        }

        CliHelpers.PrintLists(ctx, lists);
        return 0;
    }

    private static int CmdAdd(CliContext ctx, string[] args)
    {
        var options = ParseOptions(args);
        var text = RequirePositional(options, 0, "text");
        var listArg = options.Value("--list");

        int listId;
        if (!string.IsNullOrEmpty(listArg))
        {
            listId = CliHelpers.ResolveListIdAsync(ctx, listArg!).GetAwaiter().GetResult();
        }
        else
        {
            var defaultList = ctx.Lists.GetDefaultListAsync().GetAwaiter().GetResult()
                ?? throw new CliException(
                    "No lists exist yet. Create one with `taskly mklist` first.", 3);
            listId = defaultList.Id;
        }

        string? dueDate = null;
        string? dueTime = null;
        var dueArg = options.Value("--due");
        if (!string.IsNullOrEmpty(dueArg))
        {
            (dueDate, dueTime) = CliHelpers.ParseDue(ctx, dueArg!);
        }

        var timeArg = options.Value("--time");
        if (!string.IsNullOrEmpty(timeArg))
        {
            dueTime = timeArg;
        }

        var task = new TaskItem(0, listId, text, DateTime.Now.ToString("o", CultureInfo.InvariantCulture),
            dueDate, dueTime, completed: false, notes: options.Value("--notes"));
        try
        {
            task.Id = ctx.Tasks.AddTaskAsync(task).GetAwaiter().GetResult();
        }
        catch (ArgumentException ex)
        {
            throw new CliException(ex.Message, 2);
        }

        CliHelpers.PrintTask(ctx, task);
        return 0;
    }

    private static int CmdUpdate(CliContext ctx, string[] args)
    {
        var options = ParseOptions(args);
        var idString = RequirePositional(options, 0, "id");
        var id = ParseInt(idString, "id");

        var task = ctx.Tasks.GetTaskByIdAsync(id).GetAwaiter().GetResult()
            ?? throw new CliException($"Task not found: {id}", 3);

        var text = options.Value("--text");
        if (text is not null)
        {
            task.Text = text;
        }

        if (options.Has("--clear-due"))
        {
            task.DueDate = null;
        }
        else
        {
            var dueArg = options.Value("--due");
            if (dueArg is not null)
            {
                var (d, t) = CliHelpers.ParseDue(ctx, dueArg);
                task.DueDate = d;
                if (t is not null)
                {
                    task.DueTime = t;
                }
            }
        }

        if (options.Has("--clear-time"))
        {
            task.DueTime = null;
        }
        else
        {
            var timeArg = options.Value("--time");
            if (timeArg is not null)
            {
                task.DueTime = timeArg;
            }
        }

        var listArg = options.Value("--list");
        if (listArg is not null)
        {
            task.ListId = CliHelpers.ResolveListIdAsync(ctx, listArg).GetAwaiter().GetResult();
        }

        if (options.Has("--clear-notes"))
        {
            task.Notes = null;
        }
        else
        {
            var notes = options.Value("--notes");
            if (notes is not null)
            {
                task.Notes = notes;
            }
        }

        try
        {
            ctx.Tasks.UpdateTaskAsync(task).GetAwaiter().GetResult();
        }
        catch (ArgumentException ex)
        {
            throw new CliException(ex.Message, 2);
        }

        CliHelpers.PrintTask(ctx, task);
        return 0;
    }

    private static int CmdDone(CliContext ctx, string[] args, bool completed)
    {
        var options = ParseOptions(args);
        var idString = RequirePositional(options, 0, "id");
        var id = ParseInt(idString, "id");

        var affected = ctx.Tasks.SetTaskCompletedAsync(id, completed).GetAwaiter().GetResult();
        if (affected == 0)
        {
            throw new CliException($"Task not found: {id}", 3);
        }

        if (ctx.Json)
        {
            if (ctx.Quiet)
            {
                JsonOutput.Write(new { ok = true, id, completed });
            }
            else
            {
                var task = ctx.Tasks.GetTaskByIdAsync(id).GetAwaiter().GetResult();
                if (task is not null)
                {
                    JsonOutput.Write(JsonOutput.TaskObject(task));
                }
            }
        }
        else if (!ctx.Quiet)
        {
            var task = ctx.Tasks.GetTaskByIdAsync(id).GetAwaiter().GetResult();
            if (task is not null)
            {
                CliHelpers.PrintTask(ctx, task);
            }
        }

        return 0;
    }

    private static int CmdRm(CliContext ctx, string[] args)
    {
        var options = ParseOptions(args);
        var idString = RequirePositional(options, 0, "id");
        var id = ParseInt(idString, "id");

        var deleted = false;
        try
        {
            deleted = ctx.Tasks.DeleteTaskAsync(id).GetAwaiter().GetResult() > 0;
        }
        catch (Microsoft.Data.Sqlite.SqliteException)
        {
            deleted = false;
        }

        if (ctx.Json)
        {
            JsonOutput.Write(new { ok = true, id, deleted });
        }
        else if (!ctx.Quiet)
        {
            Console.WriteLine(deleted ? $"Deleted task {id}" : $"Task {id} did not exist");
        }

        return 0;
    }

    private static int CmdSearch(CliContext ctx, string[] args)
    {
        var options = ParseOptions(args);
        var keyword = RequirePositional(options, 0, "keyword");
        var limit = ParseInt(options.Value("--limit") ?? "100", "--limit");

        var results = ctx.Tasks.SearchTasksAsync(keyword).GetAwaiter().GetResult();
        CliHelpers.PrintTasks(ctx, results.Take(limit).ToList());
        return 0;
    }

    private static int CmdMkList(CliContext ctx, string[] args)
    {
        var options = ParseOptions(args);
        var name = RequirePositional(options, 0, "name");
        var icon = options.Value("--icon");
        var colorHex = options.Value("--color");
        int? color = colorHex is null ? null : CliHelpers.ParseColor(colorHex);

        int id;
        try
        {
            id = ctx.Lists.AddListAsync(name, icon, color).GetAwaiter().GetResult();
        }
        catch (ArgumentException ex)
        {
            throw new CliException(ex.Message, 2);
        }

        var created = ctx.Lists.GetListByIdAsync(id).GetAwaiter().GetResult()
            ?? new TodoList(id, name, icon, color);

        if (ctx.Json)
        {
            JsonOutput.Write(JsonOutput.ListObject(created));
        }
        else if (ctx.Quiet)
        {
            Console.WriteLine(id);
        }
        else
        {
            var iconText = string.IsNullOrEmpty(created.Icon) ? "" : $"{created.Icon} ";
            Console.WriteLine($"  {created.Id,5}  {iconText}{created.Name}  (0)");
        }

        return 0;
    }

    private static int CmdRmList(CliContext ctx, string[] args)
    {
        var options = ParseOptions(args);
        var idString = RequirePositional(options, 0, "id");
        var id = ParseInt(idString, "id");

        var deleted = false;
        try
        {
            deleted = ctx.Lists.DeleteListAsync(id).GetAwaiter().GetResult() > 0;
        }
        catch (Microsoft.Data.Sqlite.SqliteException)
        {
            deleted = false;
        }

        if (ctx.Json)
        {
            JsonOutput.Write(new { ok = true, id, deleted });
        }
        else if (!ctx.Quiet)
        {
            Console.WriteLine(deleted ? $"Deleted list {id} (and its tasks)" : $"List {id} did not exist");
        }

        return 0;
    }
}
