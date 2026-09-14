using System.Text.Json;
using System.Text.Json.Serialization;
using Taskly.Models;

namespace Taskly.Cli;

/// <summary>
/// JSON output. System.Text.Json defaults (WriteIndented, WhenWritingNull)
/// byte-match the 0.6.x CLI and the Swift port's hand-rolled writer.
/// </summary>
public static class JsonOutput
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static void Write(object? value)
    {
        var json = JsonSerializer.Serialize(value, Options);
        Console.WriteLine(json);
    }

    public static object TaskObject(TaskItem t) => new
    {
        id = t.Id,
        listId = t.ListId,
        listName = t.ListName,
        text = t.Text,
        completed = t.Completed,
        dueDate = t.DueDate,
        dueTime = t.DueTime,
        notes = t.Notes,
        createdAt = t.CreatedAt,
    };

    public static object ListObject(TodoList l) => new
    {
        id = l.Id,
        name = l.Name,
        icon = l.Icon,
        color = l.Color,
        pendingCount = l.PendingCount,
    };

    public static object ErrorObject(string message, int exitCode) => new
    {
        ok = false,
        error = message,
        exitCode = exitCode,
    };
}
