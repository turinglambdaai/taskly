import SwiftUI

/// Design tokens (shared/spec/DESIGN-TOKENS.md). Anthropic-warm palette.
public enum Palette {
    // Semantic (theme-independent)
    public static let today = Color(hex: 0xC15F3C)
    public static let todayDark = Color(hex: 0xD47757)
    public static let planned = Color(hex: 0xB5543A)
    public static let all = Color(hex: 0x8E887E)
    public static let completed = Color(hex: 0x6B8E5A)
    public static let flagged = Color(hex: 0xC98642)
    public static let danger = Color(hex: 0xFF3B30)

    public static let accentLight = today
    public static let accentDark = todayDark

    // Light theme
    public static let lightBackground = Color(hex: 0xF4F3EE)
    public static let lightSidebar = Color(hex: 0xECEAE3)
    public static let lightSurface = Color(hex: 0xFAF9F5)
    public static let lightDivider = Color(hex: 0xD9D6CE)
    public static let lightOnSurface = Color(hex: 0x2B2825)
    public static let lightSecondaryText = Color(hex: 0x6B6862)
    public static let lightTertiaryText = Color(hex: 0x9B9890)
    public static let lightSelection = Color(hex: 0xC15F3C, alpha: 0x38 / 255.0)
    public static let lightHover = Color(hex: 0x2B2825, alpha: 0x14 / 255.0)
    public static let lightInputBorder = lightDivider
    public static let lightBadgeBackground = Color(hex: 0xE0DDD4)
    public static let lightBadgeText = Color(hex: 0x3C3934)

    // Dark theme (warm)
    public static let darkBackground = Color(hex: 0x1F1C19)
    public static let darkSidebar = Color(hex: 0x282421)
    public static let darkSurface = Color(hex: 0x332F2B)
    public static let darkDivider = Color(hex: 0x3D3935)
    public static let darkOnSurface = Color(hex: 0xF4F3EE)
    public static let darkSecondaryText = Color(hex: 0xA8A39B)
    public static let darkTertiaryText = Color(hex: 0x76726B)
    public static let darkSelection = Color(hex: 0xD47757, alpha: 0x4D / 255.0)
    public static let darkHover = Color(hex: 0xFFFFFF, alpha: 0x24 / 255.0)
    public static let darkInputBorder = Color(hex: 0x4A4540)
    public static let darkBadgeBackground = Color(hex: 0x4A4540)
    public static let darkBadgeText = Color(hex: 0xF4F3EE)

    /// List-color presets (fixed order, iOS system colors).
    public static let listColorsHex: [UInt32] = [
        0x007AFF, 0xFF3B30, 0xFF9500, 0xFFCC00, 0x4CD964, 0x5AC8FA,
        0x5856D6, 0xFF2D55, 0x8E8E93, 0xC7C7CC,
    ]
    public static let listColors: [Color] = listColorsHex.map { Color(hex: $0) }

    /// Emoji picker categories (fixed order, 6 × 8).
    public static let emojiCategories: [[String]] = [
        ["📋", "📝", "✅", "🎯", "💡", "📌", "🔖", "📎"],
        ["🏠", "🏢", "💼", "📱", "💻", "🎨", "📚", "🎓"],
        ["❤️", "⭐", "🌟", "🔥", "💪", "🎉", "🎊", "🏆"],
        ["🛒", "🛍️", "🍔", "☕", "🍕", "🥤", "🎮", "🎬"],
        ["✈️", "🚗", "🚴", "🏃", "⚽", "🏀", "🎸", "🎵"],
        ["💰", "💳", "📊", "📈", "💼", "📧", "📅", "⏰"],
    ]

    // Geometry
    public static let sidebarWidth: CGFloat = 280
    public static let statusHeight: CGFloat = 28
    public static let tileHeight: CGFloat = 68
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha)
    }

    /// From a signed ARGB int as stored in the DB color column.
    init(argb: Int?) {
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

/// View-model theme switch (dark mode is a session toggle, not persisted —
/// PRODUCT-SPEC §8; the window still follows a live palette refresh).
@Observable
public final class ThemeState {
    public var isDark: Bool = false

    public init() {}

    public var background: Color { isDark ? Palette.darkBackground : Palette.lightBackground }
    public var sidebar: Color { isDark ? Palette.darkSidebar : Palette.lightSidebar }
    public var surface: Color { isDark ? Palette.darkSurface : Palette.lightSurface }
    public var divider: Color { isDark ? Palette.darkDivider : Palette.lightDivider }
    public var onSurface: Color { isDark ? Palette.darkOnSurface : Palette.lightOnSurface }
    public var secondaryText: Color { isDark ? Palette.darkSecondaryText : Palette.lightSecondaryText }
    public var tertiaryText: Color { isDark ? Palette.darkTertiaryText : Palette.lightTertiaryText }
    public var selection: Color { isDark ? Palette.darkSelection : Palette.lightSelection }
    public var hover: Color { isDark ? Palette.darkHover : Palette.lightHover }
    public var inputBorder: Color { isDark ? Palette.darkInputBorder : Palette.lightInputBorder }
    public var badgeBackground: Color { isDark ? Palette.darkBadgeBackground : Palette.lightBadgeBackground }
    public var badgeText: Color { isDark ? Palette.darkBadgeText : Palette.lightBadgeText }
    public var accent: Color { isDark ? Palette.accentDark : Palette.accentLight }
}
