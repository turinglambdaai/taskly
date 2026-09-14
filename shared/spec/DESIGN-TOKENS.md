# Taskly Design Tokens (Contract)

> Anthropic-warm palette: Pampas warm beige ground, Crail terracotta accent.
> Restrained, low-saturation, generous whitespace. Every platform implements
> these as named constants; semantic colors are theme-independent.

## Semantic colors (theme-independent)

| Token | Hex | Use |
|---|---|---|
| `accent/today` | `#C15F3C` | Today tile, default list color, light-mode accent |
| `accent/today-dark` | `#D47757` | Dark-mode accent |
| `tile/planned` | `#B5543A` | Planned tile |
| `tile/all` | `#8E887E` | All tile |
| `tile/completed` | `#6B8E5A` | Completed tile |
| `flag` (reserved) | `#C98642` | Flagged (unused) |
| `danger` | `#FF3B30` | Destructive buttons |

## Light theme

| Token | Hex |
|---|---|
| `background` | `#F4F3EE` (Pampas) |
| `sidebar` | `#ECEAE3` |
| `surface` | `#FAF9F5` |
| `divider` | `#D9D6CE` |
| `text/primary` | `#2B2825` |
| `text/secondary` | `#6B6862` |
| `text/tertiary` | `#9B9890` |
| `selection` | `#38C15F3C` (Crail @ ~22%) |
| `hover` | `#142B2825` (ink @ ~8%) |
| `input-border` | `= divider` |
| `badge/background` | `#E0DDD4` |
| `badge/text` | `#3C3934` |

## Dark theme (warm, never cold black)

| Token | Hex |
|---|---|
| `background` | `#1F1C19` |
| `sidebar` | `#282421` |
| `surface` | `#332F2B` |
| `divider` | `#3D3935` |
| `text/primary` | `#F4F3EE` |
| `text/secondary` | `#A8A39B` |
| `text/tertiary` | `#76726B` |
| `selection` | `#4DD47757` (terracotta @ ~30%) |
| `hover` | `#24FFFFFF` (white @ ~14%) |
| `input-border` | `#4A4540` |
| `badge/background` | `#4A4540` |
| `badge/text` | `#F4F3EE` |

## List-palette presets (fixed order, iOS system colors)

`#007AFF` `#FF3B30` `#FF9500` `#FFCC00` `#4CD964` `#5AC8FA` `#5856D6`
`#FF2D55` `#8E8E93` `#C7C7CC`

## Emoji categories (fixed order, 6 × 8)

1. 📋 📝 ✅ 🎯 💡 📌 🔖 📎
2. 🏠 🏢 💼 📱 💻 🎨 📚 🎓
3. ❤️ ⭐ 🌟 🔥 💪 🎉 🎊 🏆
4. 🛒 🛍️ 🍔 ☕ 🍕 🥤 🎮 🎬
5. ✈️ 🚗 🚴 🏃 ⚽ 🏀 🎸 🎵
6. 💰 💳 📊 📈 💼 📧 📅 ⏰

## Geometry & type

| Token | Value |
|---|---|
| window default | 1024×768 (min 760×520) |
| sidebar width | 280 (200…420) |
| menu bar / status bar height | 32 / 28 |
| smart tile height / corner | 68 / 12 |
| list icon size | 32 (round) |
| checkbox size | 18–22 (round) |
| corner radius (rows/cards) | 8 / 10 / 12 |
| content padding | 16, 8; sidebar item 12, 10 |
| task text | 14px; list name 13px |
| font stack | system UI font of the platform (`-apple-system` / Segoe UI / GNOME default), CJK fallback PingFang SC / Microsoft YaHei / Noto Sans CJK SC |
