import SwiftUI

/// Design tokens (shared/spec/DESIGN-TOKENS.md). macOS Reminders neutral palette.
enum Palette {
    // Semantic (theme-independent)
    static let today = Color(hex: 0x007AFF)
    static let todayDark = Color(hex: 0x0A84FF)
    static let planned = Color(hex: 0xFF3B30)
    static let all = Color(hex: 0x8E8E93)
    static let completed = Color(hex: 0x8E8E93)
    static let calendar = Color(hex: 0x5856D6)
    static let flagged = Color(hex: 0xFF9500)
    static let danger = Color(hex: 0xFF3B30)

    static let accentLight = today
    static let accentDark = todayDark

    // Light theme
    static let lightBackground = Color(hex: 0xFFFFFF)
    static let lightSidebar = Color(hex: 0xF2F2F2)
    static let lightSurface = Color(hex: 0xFFFFFF)
    static let lightDivider = Color(hex: 0xE3E3E8)
    static let lightOnSurface = Color(hex: 0x1D1D1F)
    static let lightSecondaryText = Color(hex: 0x8E8E93)
    static let lightTertiaryText = Color(hex: 0xB0B0B5)
    static let lightSelection = Color(hex: 0x000000, alpha: 0x14 / 255.0)
    static let lightHover = Color(hex: 0x000000, alpha: 0x0D / 255.0)
    static let lightInputBorder = Color(hex: 0xC7C7CC)
    static let lightBadgeBackground = Color(hex: 0xE9E9EE)
    static let lightBadgeText = Color(hex: 0x58585D)

    // Dark theme (layered grays)
    static let darkBackground = Color(hex: 0x1E1E1E)
    static let darkSidebar = Color(hex: 0x2A2A2C)
    static let darkSurface = Color(hex: 0x323234)
    static let darkDivider = Color(hex: 0x3F3F44)
    static let darkOnSurface = Color(hex: 0xF5F5F7)
    static let darkSecondaryText = Color(hex: 0x98989E)
    static let darkTertiaryText = Color(hex: 0x6B6B72)
    static let darkSelection = Color(hex: 0xFFFFFF, alpha: 0x1F / 255.0)
    static let darkHover = Color(hex: 0xFFFFFF, alpha: 0x12 / 255.0)
    static let darkInputBorder = Color(hex: 0x4A4A50)
    static let darkBadgeBackground = Color(hex: 0x3F3F44)
    static let darkBadgeText = Color(hex: 0xE9E9EE)

    /// List-color presets (fixed order, iOS system colors).
    static let listColorsHex: [UInt32] = [
        0x007AFF, 0xFF3B30, 0xFF9500, 0xFFCC00, 0x4CD964, 0x5AC8FA,
        0x5856D6, 0xFF2D55, 0x8E8E93, 0xC7C7CC, 0xA2845E, 0x00C7BE,
    ]
    static let listColors: [Color] = listColorsHex.map { Color(hex: $0) }

    /// Emoji catalog ids in display order (names via i18n emojiCat_<id>;
    /// emoji data loads from the synced shared/emoji.json bundle resource).
    static let emojiCategoryIds: [String] = [
        "frequent", "people", "nature", "food",
        "activity", "travel", "objects", "symbols",
    ]

    /// [categoryId → emojis], parsed once from shared/emoji.json.
    static let emojiCategories: [String: [String]] = {
        var map: [String: [String]] = [:]
        if let url = HostResources.locateEmoji(),
           let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let categories = root["categories"] as? [[String: Any]] {
            for category in categories {
                if let id = category["id"] as? String,
                   let emojis = category["emojis"] as? [String] {
                    map[id] = emojis
                }
            }
        }
        if map.isEmpty {
            // Catalog missing → legacy flat set as one category.
            map["frequent"] = [
                "📋", "📝", "✅", "🎯", "💡", "📌", "🔖", "📎",
                "🏠", "🏢", "💼", "📱", "💻", "🎨", "📚", "🎓",
            ]
        }
        return map
    }()

    // Geometry
    static let sidebarWidth: CGFloat = 280
    static let statusHeight: CGFloat = 28
    static let smartChipHeight: CGFloat = 34
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha)
    }

    /// From a signed ARGB int as stored in the DB color column.
    init(argb: Int64?) {
        guard let argb else {
            self = Palette.today // accent fallback for colorless lists
            return
        }
        let hex = UInt32(bitPattern: Int32(truncatingIfNeeded: argb))
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: Double((hex >> 24) & 0xFF) / 255.0)
    }
}

/// View-model theme switch. `isDark` mirrors the effective appearance:
/// system theme tracks macOS live; light/dark settings override through
/// NSApp.appearance and the effective appearance follows.
@Observable
final class ThemeState {
    var isDark: Bool = false

    init() {}

    var background: Color { isDark ? Palette.darkBackground : Palette.lightBackground }
    var sidebar: Color { isDark ? Palette.darkSidebar : Palette.lightSidebar }
    var surface: Color { isDark ? Palette.darkSurface : Palette.lightSurface }
    var divider: Color { isDark ? Palette.darkDivider : Palette.lightDivider }
    var onSurface: Color { isDark ? Palette.darkOnSurface : Palette.lightOnSurface }
    var secondaryText: Color { isDark ? Palette.darkSecondaryText : Palette.lightSecondaryText }
    var tertiaryText: Color { isDark ? Palette.darkTertiaryText : Palette.lightTertiaryText }
    var selection: Color { isDark ? Palette.darkSelection : Palette.lightSelection }
    var hover: Color { isDark ? Palette.darkHover : Palette.lightHover }
    var inputBorder: Color { isDark ? Palette.darkInputBorder : Palette.lightInputBorder }
    var badgeBackground: Color { isDark ? Palette.darkBadgeBackground : Palette.lightBadgeBackground }
    var badgeText: Color { isDark ? Palette.darkBadgeText : Palette.lightBadgeText }
    var accent: Color { isDark ? Palette.accentDark : Palette.accentLight }
}
