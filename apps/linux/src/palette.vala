// Taskly — preset palette (contract: DESIGN-TOKENS.md, fixed order).

namespace Taskly {

/// iOS system colors, RGB hex (alpha is always FF). 12 presets.
public const string[] LIST_COLORS_RGB = {
    "007AFF", "FF3B30", "FF9500", "FFCC00", "4CD964",
    "5AC8FA", "5856D6", "FF2D55", "8E8E93", "C7C7CC",
    "A2845E", "00C7BE",
};

/// Emoji category ids in display order (names via i18n emojiCat_<id>).
public const string[] EMOJI_CATEGORY_IDS = {
    "frequent", "people", "nature", "food",
    "activity", "travel", "objects", "symbols",
};

/// Dev runs read the source dir; installed builds read share/taskly.
private string? locate_emoji_json() {
    var candidates = new string[] {
        "resources/emoji.json",
        "/usr/local/share/taskly/emoji.json",
        "/usr/share/taskly/emoji.json",
    };
    foreach (var candidate in candidates) {
        if (FileUtils.test(candidate, FileTest.EXISTS)) {
            return candidate;
        }
    }
    return null;
}

/// Per-category emoji joined with '\n' (Vala generics reject arrays);
/// parsed once from the synced resources/emoji.json.
private GLib.HashTable<string, string>? emoji_catalog_joined = null;

/// Emoji list for a category id, or null when the catalog is unavailable.
public string[]? load_emoji_category(string category_id) {
    if (emoji_catalog_joined == null) {
        emoji_catalog_joined = new GLib.HashTable<string, string>(str_hash, str_equal);
        try {
            var path = locate_emoji_json();
            if (path != null) {
                var parser = new Json.Parser();
                parser.load_from_file(path);
                foreach (var node in parser.get_root()
                    .get_object()
                    .get_array_member("categories")
                    .get_elements()) {
                    var obj = node.get_object();
                    var joined = new StringBuilder();
                    foreach (var e in obj.get_array_member("emojis").get_elements()) {
                        joined.append(e.get_string());
                        joined.append("\n");
                    }
                    emoji_catalog_joined[obj.get_string_member("id")] = joined.str;
                }
            }
        } catch (Error e) {
            // Missing/corrupt catalog → callers use their fallbacks.
        }
    }
    var joined = emoji_catalog_joined[category_id];
    return joined != null ? joined.split("\n") : null;
}

/// Seeds a category (used by the legacy-flat-set fallback).
public void seed_emoji_category(string category_id, string[] emojis) {
    if (emoji_catalog_joined == null) {
        emoji_catalog_joined = new GLib.HashTable<string, string>(str_hash, str_equal);
    }
    var joined = new StringBuilder();
    foreach (var emoji in emojis) {
        joined.append(emoji);
        joined.append("\n");
    }
    emoji_catalog_joined[category_id] = joined.str;
}

/// Flat fallback (the legacy 6 × 8 set) for when the catalog is missing.
public const string[] EMOJI_ALL = {
    "📋", "📝", "✅", "🎯", "💡", "📌", "🔖", "📎",
    "🏠", "🏢", "💼", "📱", "💻", "🎨", "📚", "🎓",
    "❤️", "⭐", "🌟", "🔥", "💪", "🎉", "🎊", "🏆",
    "🛒", "🛍️", "🍔", "☕", "🍕", "🥤", "🎮", "🎬",
    "✈️", "🚗", "🚴", "🏃", "⚽", "🏀", "🎸", "🎵",
    "💰", "💳", "📊", "📈", "💼", "📧", "📅", "⏰",
};

}
