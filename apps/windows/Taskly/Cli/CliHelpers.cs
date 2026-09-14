using System.Globalization;
using Taskly.Data;
using Taskly.Models;
using Taskly.Services;

namespace Taskly.Cli;

/// <summary>Shared CLI helpers: list resolution, --due parsing, colors, output.</summary>
public static class CliHelpers
{
    public static async Task<int> ResolveListIdAsync(CliContext ctx, string list)
    {
        if (int.TryParse(list, CultureInfo.InvariantCulture, out var id))
        {
            return id;
        }

        var found = await ctx.Lists.GetListByNameAsync(list)
            ?? throw new CliException($"List not found by name: \"{list}\"", 3);
        return found.Id;
    }

    /// <summary>CLI --due wrapper (CLI-SPEC.md): bare-word pre-mapping,
    /// DateParser, and the date-only-intent rule that clears dueTime.</summary>
    public static (string? date, string? time) ParseDue(CliContext ctx, string due)
    {
        var original = due.Trim();
        var lower = original.ToLowerInvariant();
        var normalized = lower switch
        {
            "today" => "+0d",
            "tomorrow" or "tmw" => "+1d",
            "tonight" => "@20:00",
            _ => original,
        };

        var parsed = ctx.DateParser.Parse(normalized)
            ?? throw new CliException(
                $"Cannot parse date/time: \"{due}\". " +
                "Supported: +10m, +2h, +1d, +1w, @10am, @10:30pm, today, tomorrow, yyyy-MM-dd",
                2);

        var date = DateParser.ExtractDateOnly(parsed);
        var time = DateParser.ExtractTimeOnly(parsed);

        var isDateOnly = lower is "today" or "tomorrow" or "tmw"
            || (normalized.StartsWith('+')
                && normalized.Length > 0
                && normalized[^1] is 'd' or 'w' or 'M')
            || (parsed.Length == 10);

        if (isDateOnly)
        {
            time = null;
        }

        return (date, time);
    }

    public static int ParseColor(string color)
    {
        if (int.TryParse(color, CultureInfo.InvariantCulture, out var argb))
        {
            return argb;
        }

        if (!color.StartsWith('#'))
        {
            throw new CliException(
                $"Invalid color: \"{color}\". Use #RRGGBB hex or ARGB int", 2);
        }

        var hex = color[1..];
        return hex.Length switch
        {
            6 => unchecked((int)(0xFF000000u | Convert.ToUInt32(hex, 16))),
            8 => unchecked((int)Convert.ToUInt32(hex, 16)),
            _ => throw new CliException(
                $"Invalid hex color: \"{color}\". Use #RRGGBB (6) or #AARRGGBB (8)", 2),
        };
    }

    public static void PrintTask(CliContext ctx, TaskItem t)
    {
        if (ctx.Json)
        {
            JsonOutput.Write(JsonOutput.TaskObject(t));
            return;
        }

        if (ctx.Quiet)
        {
            Console.WriteLine(t.Id);
            return;
        }

        var mark = t.Completed ? "[x]" : "[ ]";
        var due = string.IsNullOrEmpty(t.DueDate) ? "" : $"  🗓 {t.DueDate}{(string.IsNullOrEmpty(t.DueTime) ? "" : " " + t.DueTime)}";
        Console.WriteLine($"  {t.Id,5}  {mark}  {t.Text}{due}");
    }

    public static void PrintTasks(CliContext ctx, IReadOnlyList<TaskItem> tasks)
    {
        if (ctx.Json)
        {
            JsonOutput.Write(tasks.Select(JsonOutput.TaskObject).ToList());
            return;
        }

        if (tasks.Count == 0)
        {
            if (!ctx.Quiet)
            {
                Console.WriteLine("(no tasks)");
            }

            return;
        }

        foreach (var t in tasks)
        {
            PrintTask(ctx, t);
        }
    }

    public static void PrintLists(CliContext ctx, IReadOnlyList<TodoList> lists)
    {
        if (ctx.Json)
        {
            JsonOutput.Write(lists.Select(JsonOutput.ListObject).ToList());
            return;
        }

        foreach (var l in lists)
        {
            var icon = string.IsNullOrEmpty(l.Icon) ? "" : $"{l.Icon} ";
            Console.WriteLine($"  {l.Id,5}  {icon}{l.Name}  ({l.PendingCount})");
        }
    }
}

/// <summary>CLI error carrying a contract exit code.</summary>
public class CliException : Exception
{
    public int ExitCode { get; }

    public CliException(string message, int exitCode) : base(message)
    {
        ExitCode = exitCode;
    }
}

/// <summary>Per-invocation context: opened DB + repositories.</summary>
public sealed class CliContext : IDisposable
{
    public SQLiteDatabase Db { get; }
    public TaskRepository Tasks { get; }
    public ListRepository Lists { get; }
    public DateParser DateParser { get; } = new();
    public bool Json { get; }
    public bool Quiet { get; }

    private CliContext(SQLiteDatabase db, bool json, bool quiet)
    {
        Db = db;
        Tasks = new TaskRepository(db, I18nService.Instance);
        Lists = new ListRepository(db, I18nService.Instance);
        Json = json;
        Quiet = quiet;
    }

    public static CliContext Create(string command, string? dbPath, bool json, bool quiet)
    {
        if (command is "install-cli" or "uninstall-cli" or "--help" or "-h" or "help")
        {
            return new CliContext(new SQLiteDatabase(), json, quiet);
        }

        var db = new SQLiteDatabase();
        if (!string.IsNullOrEmpty(dbPath))
        {
            db.SetDatabasePath(dbPath);
        }
        else
        {
            var config = new ConfigService();
            config.Load();
            if (!string.IsNullOrEmpty(config.LastDbPath))
            {
                db.SetDatabasePath(config.LastDbPath);
            }
        }

        try
        {
            db.EnsureConnectedAsync().GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            throw new CliException(
                $"Cannot open database: {db.GetDatabasePath()} ({ex.Message})", 4);
        }

        return new CliContext(db, json, quiet);
    }

    public void Dispose() => Db.Close();
}
