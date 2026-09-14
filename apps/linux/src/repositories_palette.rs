//! Preset palette (contract: DESIGN-TOKENS.md, fixed order).

pub const LIST_COLORS_HEX: [u32; 10] = [
    0x007AFF, 0xFF3B30, 0xFF9500, 0xFFCC00, 0x4CD964,
    0x5AC8FA, 0x5856D6, 0xFF2D55, 0x8E8E93, 0xC7C7CC,
];

pub const EMOJI_CATEGORIES: [[&str; 8]; 6] = [
    ["📋", "📝", "✅", "🎯", "💡", "📌", "🔖", "📎"],
    ["🏠", "🏢", "💼", "📱", "💻", "🎨", "📚", "🎓"],
    ["❤️", "⭐", "🌟", "🔥", "💪", "🎉", "🎊", "🏆"],
    ["🛒", "🛍️", "🍔", "☕", "🍕", "🥤", "🎮", "🎬"],
    ["✈️", "🚗", "🚴", "🏃", "⚽", "🏀", "🎸", "🎵"],
    ["💰", "💳", "📊", "📈", "💼", "📧", "📅", "⏰"],
];
