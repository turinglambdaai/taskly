import Foundation

/// JSON writer that byte-matches the reference CLI's System.Text.Json output:
/// 2-space indent, declaration field order, null fields omitted, non-ASCII
/// escaped as \uXXXX (C# JavaScriptEncoder.Default behavior).
public enum CliJson {
    public indirect enum Value {
        case int(Int)
        case bool(Bool)
        case string(String)
        case null
        case array([Value])
        case object([(String, Value)])
    }

    public static func render(_ value: Value) -> String {
        var out = ""
        write(value, indent: 0, into: &out)
        return out
    }

    private static func write(_ value: Value, indent: Int, into out: inout String) {
        let pad = String(repeating: " ", count: indent)
        let padInner = String(repeating: " ", count: indent + 2)
        switch value {
        case let .int(v):
            out += String(v)
        case let .bool(v):
            out += v ? "true" : "false"
        case .null:
            out += "null"
        case let .string(s):
            out += escape(s)
        case let .array(items):
            if items.isEmpty {
                out += "[]"
                return
            }
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += padInner
                write(item, indent: indent + 2, into: &out)
                out += index < items.count - 1 ? ",\n" : "\n"
            }
            out += pad + "]"
        case let .object(pairs):
            if pairs.isEmpty {
                out += "{}"
                return
            }
            out += "{\n"
            for (index, pair) in pairs.enumerated() {
                out += padInner + escape(pair.0) + ": "
                write(pair.1, indent: indent + 2, into: &out)
                out += index < pairs.count - 1 ? ",\n" : "\n"
            }
            out += pad + "}"
        }
    }

    /// C#-style string escaping: control chars, quotes, backslash, and all
    /// non-ASCII as \uXXXX (astral chars as surrogate pairs).
    static func escape(_ s: String) -> String {
        var out = "\""
        for unit in s.utf16 {
            switch unit {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            default:
                if unit < 0x20 {
                    out += String(format: "\\u%04x", unit)
                } else if unit < 0x7F {
                    out += String(UnicodeScalar(unit)!)
                } else {
                    out += String(format: "\\u%04x", unit)
                }
            }
        }
        out += "\""
        return out
    }

    // MARK: - Contract projections (field order fixed by CLI-SPEC.md; null
    // fields omitted, mirroring WhenWritingNull)

    public static func taskObject(_ t: TaskItem) -> Value {
        .object(omitNull([
            ("id", .int(t.id)),
            ("listId", .int(t.listId)),
            ("listName", t.listName.map { .string($0) } ?? .null),
            ("text", .string(t.text)),
            ("completed", .bool(t.completed)),
            ("dueDate", t.dueDate.map { .string($0) } ?? .null),
            ("dueTime", t.dueTime.map { .string($0) } ?? .null),
            ("notes", t.notes.map { .string($0) } ?? .null),
            ("createdAt", .string(t.createdAt)),
        ]))
    }

    public static func listObject(_ l: TodoList, pendingCount: Int = 0) -> Value {
        .object(omitNull([
            ("id", .int(l.id)),
            ("name", .string(l.name)),
            ("icon", l.icon.map { .string($0) } ?? .null),
            ("color", l.color.map { .int($0) } ?? .null),
            ("pendingCount", .int(pendingCount)),
        ]))
    }

    private static func omitNull(_ pairs: [(String, Value)]) -> [(String, Value)] {
        pairs.filter {
            if case .null = $0.1 { return false }
            return true
        }
    }

    public static func errorObject(_ message: String, _ exitCode: Int32) -> Value {
        .object([
            ("ok", .bool(false)),
            ("error", .string(message)),
            ("exitCode", .int(Int(exitCode))),
        ])
    }
}

/// Convenience: lets call sites write `.taskObject(t)` inside `.array(...)`.
public extension CliJson.Value {
    static func taskObject(_ t: TaskItem) -> CliJson.Value { CliJson.taskObject(t) }
    static func listObject(_ l: TodoList, pendingCount: Int = 0) -> CliJson.Value {
        CliJson.listObject(l, pendingCount: pendingCount)
    }
    static func errorObject(_ message: String, _ exitCode: Int32) -> CliJson.Value {
        CliJson.errorObject(message, exitCode)
    }
}
