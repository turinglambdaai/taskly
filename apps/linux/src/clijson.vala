// Taskly — CLI JSON writer that byte-matches the reference CLI's
// System.Text.Json output: 2-space indent, declaration field order, null
// fields omitted, non-ASCII escaped as \uXXXX (surrogate pairs for astral).

namespace Taskly {

namespace CliJson {

    public string escape_string(string s) {
        var sb = new StringBuilder("\"");
        var text = s.data;
        for (var i = 0; i < text.length;) {
            var c = text[i];
            if (c < 0x80) {
                switch (c) {
                    case '"': sb.append("\\\""); break;
                    case '\\': sb.append("\\\\"); break;
                    case '\b': sb.append("\\b"); break;
                    case '\f': sb.append("\\f"); break;
                    case '\n': sb.append("\\n"); break;
                    case '\r': sb.append("\\r"); break;
                    case '\t': sb.append("\\t"); break;
                    default:
                        if (c < 0x20 || c == 0x7F) {
                            sb.append_printf("\\u%04x", c);
                        } else {
                            sb.append_c((char) c);
                        }
                        break;
                }
                i++;
            } else {
                // Decode UTF-8 → scalar → \uXXXX (surrogate pair if astral).
                var seq_len = (int) utf8_seq_len(text[i]);
                var code = (uint32) string_from_bytes(text, i).get_char();
                if (code > 0xFFFF) {
                    code -= 0x10000;
                    sb.append_printf("\\u%04x", 0xD800 + (code >> 10));
                    sb.append_printf("\\u%04x", 0xDC00 + (code & 0x3FF));
                } else {
                    sb.append_printf("\\u%04x", code);
                }
                i += seq_len;
            }
        }
        sb.append("\"");
        return sb.str;
    }

    private string string_from_bytes(uint8[] text, int offset) {
        // Re-decode one UTF-8 sequence starting at offset.
        var len = (int) utf8_seq_len(text[offset]);
        var buf = new uint8[len + 1];
        for (var j = 0; j < len; j++) {
            buf[j] = text[offset + j];
        }
        buf[len] = 0;
        return (string) buf;
    }

    private size_t utf8_seq_len(uint8 first) {
        if (first < 0x80) return 1;
        if ((first & 0xE0) == 0xC0) return 2;
        if ((first & 0xF0) == 0xE0) return 3;
        return 4;
    }

    // ---- ordered builders ----

    public class Obj : Object {
        private string[] keys = new string[0];
        private string[] rendered = new string[0];

        public void str(string key, string? value) {
            if (value == null) return; // WhenWritingNull
            keys += key;
            rendered += escape_string(value);
        }

        public void int64(string key, int64 value) {
            keys += key;
            rendered += value.to_string();
        }

        public void boolean(string key, bool value) {
            keys += key;
            rendered += value ? "true" : "false";
        }

        public string render() {
            if (keys.length == 0) {
                return "{}";
            }
            var sb = new StringBuilder("{\n");
            for (var i = 0; i < keys.length; i++) {
                sb.append("  ");
                sb.append(escape_string(keys[i]));
                sb.append(": ");
                sb.append(rendered[i]);
                sb.append(i < keys.length - 1 ? ",\n" : "\n");
            }
            sb.append("}");
            return sb.str;
        }
    }

    public string render_array(string[] items) {
        if (items.length == 0) {
            return "[]";
        }
        var sb = new StringBuilder("[\n");
        for (var i = 0; i < items.length; i++) {
            sb.append("  ");
            sb.append(items[i]);
            sb.append(i < items.length - 1 ? ",\n" : "\n");
        }
        sb.append("]");
        return sb.str;
    }

    public string task_object(TaskItem t) {
        var obj = new Obj();
        obj.int64("id", t.id);
        obj.int64("listId", t.list_id);
        obj.str("listName", t.list_name);
        obj.str("text", t.text);
        obj.boolean("completed", t.completed);
        obj.str("dueDate", t.due_date);
        obj.str("dueTime", t.due_time);
        obj.str("notes", t.notes);
        obj.str("createdAt", t.created_at);
        return obj.render();
    }

    public string list_object(TodoList l) {
        var obj = new Obj();
        obj.int64("id", l.id);
        obj.str("name", l.name);
        obj.str("icon", l.icon);
        if (l.color != null) {
            obj.int64("color", l.color);
        }
        obj.int64("pendingCount", l.pending_count);
        return obj.render();
    }

    public string error_object(string message, int exit_code) {
        var obj = new Obj();
        obj.boolean("ok", false);
        obj.str("error", message);
        obj.int64("exitCode", exit_code);
        return obj.render();
    }
}

}
