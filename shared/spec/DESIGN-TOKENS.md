# Taskly Design Tokens (Contract)

> macOS Reminders neutral palette: white content ground, light-gray sidebar,
> system-blue accent. Quiet, content-first, generous whitespace. Every
> platform implements these as named constants; smart-tile colors are
> theme-independent.

## Semantic colors (theme-independent)

| Token | Hex | Use |
|---|---|---|
| `accent/today` | `#007AFF` | Today tile, default list color, light-mode accent |
| `accent/today-dark` | `#0A84FF` | Dark-mode accent |
| `tile/planned` | `#FF3B30` | Planned tile |
| `tile/all` | `#8E8E93` | All tile |
| `tile/completed` | `#8E8E93` | Completed tile |
| `flag` (reserved) | `#FF9500` | Flagged (unused) |
| `danger` | `#FF3B30` | Destructive buttons |

## Light theme

| Token | Hex |
|---|---|
| `background` | `#FFFFFF` |
| `sidebar` | `#F2F2F2` |
| `surface` | `#FFFFFF` |
| `divider` | `#E3E3E8` |
| `text/primary` | `#1D1D1F` |
| `text/secondary` | `#8E8E93` |
| `text/tertiary` | `#B0B0B5` |
| `selection` | `#14000000` (black @ 8%) |
| `hover` | `#0D000000` (black @ 5%) |
| `input-border` | `#C7C7CC` |
| `badge/background` | `#E9E9EE` |
| `badge/text` | `#58585D` |

## Dark theme (layered grays, never pure black)

| Token | Hex |
|---|---|
| `background` | `#1E1E1E` |
| `sidebar` | `#2A2A2C` (one step lighter than content) |
| `surface` | `#323234` |
| `divider` | `#3F3F44` |
| `text/primary` | `#F5F5F7` |
| `text/secondary` | `#98989E` |
| `text/tertiary` | `#6B6B72` |
| `selection` | `#1FFFFFFF` (white @ 12%) |
| `hover` | `#12FFFFFF` (white @ 7%) |
| `input-border` | `#4A4A50` |
| `badge/background` | `#3F3F44` |
| `badge/text` | `#E9E9EE` |

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
| window default | 1280×880 (min 760×520 logical) |
| sidebar width | 280 (200…420) |
| menu bar / status bar height | 32 / 28 |
| smart view tile | 2×2 grid of 68px color fills (radius 12), two rows: top row = white glyph left (20px) + bold white count right (16px), bottom row = semibold white label left (14px); tiles carry a subtle top-light gradient (white @ 10% → transparent) for depth; plain surface (no button chrome), hover lifts to 88% opacity, active view = full saturation + 2px white inset ring |
| list row | card: surface fill + 1px divider border, radius 8, padding 10,8; 32px round color dot with the emoji inside (17px), name 13px, gray count right |
| list icon size | 32 (round) |
| checkbox size | 20px ring in the task's list color (accent fallback); completed = list-color fill with a white check |
| task row | 48px min height, padding 16,14; text 14px; meta 12px with the owning list name (list-colored dot + name) shown in multi-list views; info button at 45% opacity, full on row hover |
| corner radius (rows/cards) | 8 / 10 / 12 |
| content padding | 16, 8; sidebar item 12, 10 |
| task text | 14px; list name 13px |
| view header | large title 24px semibold (view name) + 13px secondary subtitle line beneath (today view → full weekday date, calendar → month with task count, list/all → N open tasks); the show-completed toggle stays top-right |
| due-date semantics | due dates render localized (今天/明天/昨天/8月31日); overdue incomplete → `#FF3B30`, due today → accent, otherwise text/secondary; a leading clock glyph only when a time is set |
| input fields | search 36px, quick add 40px, radius 10, 1px input-border |
| font stack | system UI font of the platform (`-apple-system` / Segoe UI / GNOME default), CJK fallback PingFang SC / Microsoft YaHei / Noto Sans CJK SC |

Tile glyphs are monochrome platform icon fonts (Windows: Segoe Fluent Icons;
macOS: SF Symbols; Linux: symbolic icons), not emoji — mixed emoji/text runs
render fallback debris on some stacks.

## Task detail dialog (immersive editor, Things-style)

480px wide, radius 12. No dialog title — the task text *is* the title:
18px semibold borderless multiline input. Notes: 13px borderless multiline
with tertiary placeholder. Date and time render as rounded chips (accent
border when set, hollow "Add" chips when empty). Bottom row: Delete as a
red text button on the left, spacer, Cancel as plain text, Save as an
accent-filled white-text rounded button. No chrome field borders anywhere.

## App icon

White rounded square (macOS-squircle radius ≈ 22.5%) with a quiet checklist
mark: one system-blue rounded bar over two neutral (`#CECED3`) bars, staggered
widths. Monochrome, no gradients — must read on light and dark docks alike.
