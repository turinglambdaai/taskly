// Taskly — bilingual string service. Tables load from flat single-level
// {"key":"value"} JSON files that are byte-identical copies of shared/i18n
// (CI-verified). Lookup: current language → zh fallback → key itself.
// A restricted parser (this exact file format) avoids a json-glib dependency.

namespace Taskly {

public class I18n : Object {
    private GLib.HashTable<string, string> zh_table;
    private GLib.HashTable<string, string> en_table;
    private string current = "zh";

    public string language { get { return current; } }

    public I18n(string lang = "zh") {
        zh_table = load_table("zh");
        en_table = load_table("en");
        set_language(lang);
    }

    public void set_language(string lang) {
        current = (lang.down() == "en") ? "en" : "zh";
    }

    public string t(string key) {
        var table = (current == "en") ? en_table : zh_table;
        var v = table.lookup(key);
        if (v != null) {
            return v;
        }
        v = zh_table.lookup(key);
        if (v != null) {
            return v;
        }
        return key;
    }

    /// Positional {0}, {1} … placeholders.
    public string format(string key, ...) {
        var list = va_list();
        var text = t(key);
        for (var index = 0;; index++) {
            string? arg = list.arg();
            if (arg == null) {
                break;
            }
            text = text.replace("{%d}".printf(index), arg);
        }
        return text;
    }

    // ---- flat-JSON loading ----

    private static GLib.HashTable<string, string> load_table(string lang) {
        var table = new GLib.HashTable<string, string>(str_hash, str_equal);
        string[] candidates = {
            Path.build_filename(Environment.get_variable("TASKLY_I18N_DIR") ?? "", lang + ".json"),
            Path.build_filename(Environment.get_current_dir(), "resources", "i18n", lang + ".json"),
            Path.build_filename(Config.app_directory(), "i18n", lang + ".json"),
        };
        foreach (var path in candidates) {
            if (path.length == 0) {
                continue;
            }
            string content;
            try {
                FileUtils.get_contents(path, out content);
            } catch (Error e) {
                continue;
            }
            parse_flat_json(content, table);
            if (table.size() > 0) {
                break;
            }
        }
        return table;
    }

    /// Parses exactly: { "key": "value", "key2": "value2" } (whitespace-free
    /// tolerance), handling \" \\ \n \r \t and \uXXXX escapes in values.
    internal static void parse_flat_json(string content, GLib.HashTable<string, string> out_table) {
        var i = 0;
        var n = content.length;

        skip_ws(content, ref i);
        if (i >= n || content[i] != '{') {
            return;
        }
        i++;

        while (i < n) {
            skip_ws(content, ref i);
            if (i >= n) {
                break;
            }
            if (content[i] == '}') {
                break;
            }
            if (content[i] == ',') {
                i++;
                continue;
            }

            var key = parse_string(content, ref i);
            if (key == null) {
                return;
            }
            skip_ws(content, ref i);
            if (i >= n || content[i] != ':') {
                return;
            }
            i++;
            skip_ws(content, ref i);
            var value = parse_string(content, ref i);
            if (value == null) {
                return;
            }
            out_table[key] = value;
        }
    }

    private static void skip_ws(string s, ref int i) {
        while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) {
            i++;
        }
    }

    private static string? parse_string(string s, ref int i) {
        var n = s.length;
        skip_ws(s, ref i);
        if (i >= n || s[i] != '"') {
            return null;
        }
        i++;
        var sb = new StringBuilder();
        while (i < n) {
            var c = s[i];
            if (c == '"') {
                i++;
                return sb.str;
            }
            if (c == '\\') {
                i++;
                if (i >= n) {
                    return null;
                }
                switch (s[i]) {
                    case '"': sb.append_c('"'); break;
                    case '\\': sb.append_c('\\'); break;
                    case '/': sb.append_c('/'); break;
                    case 'n': sb.append_c('\n'); break;
                    case 'r': sb.append_c('\r'); break;
                    case 't': sb.append_c('\t'); break;
                    case 'b': sb.append_c('\b'); break;
                    case 'f': sb.append_c('\f'); break;
                    case 'u':
                        if (i + 4 >= n) {
                            return null;
                        }
                        var hex = s.substring(i + 1, 4);
                        var code = (unichar) (uint32) strtoul_for_hex(hex);
                        sb.append_unichar(code);
                        i += 4;
                        break;
                    default:
                        return null;
                }
                i++;
                continue;
            }
            sb.append_c(c);
            i++;
        }
        return null;
    }

    private static uint32 strtoul_for_hex(string hex) {
        uint32 value = 0;
        for (int i = 0; i < hex.length; i++) {
            var c = hex[i];
            value <<= 4;
            if (c >= '0' && c <= '9') {
                value += c - '0';
            } else if (c >= 'a' && c <= 'f') {
                value += c - 'a' + 10;
            } else if (c >= 'A' && c <= 'F') {
                value += c - 'A' + 10;
            } else {
                return value >> 4;
            }
        }
        return value;
    }
}

}
