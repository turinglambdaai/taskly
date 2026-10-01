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
`#FF2D55` `#8E8E93` `#C7C7CC` `#A2845E` `#00C7BE`

## Emoji categories (fixed order, 8 × 12)

The catalog is single-sourced in `shared/emoji.json` (category id, display
order, emojis; synced to platform copies by `scripts/sync-i18n.sh`).
Category ids in display order: `frequent`, `people`, `nature`, `food`,
`activity`, `travel`, `objects`, `symbols` — localized names via i18n
`emojiCat_<id>`.

## Geometry & type

| Token | Value |
|---|---|
| window default | 1280×880 (min 760×520 logical) |
| sidebar collapse | toggle sets the column width to 0 (releasing MinWidth) — a fixed MinWidth must not clamp the collapsed state |
| sidebar width | 280 (200…420) |
| menu bar / status bar height | 32 / 28 |
| smart-list chip | 2×2 grid of 34px chips (radius 8, 8px gaps): neutral surface fill + 1px divider, horizontal content = colored glyph (14px, view semantic color) + 13px label + quiet 12px count right; checked = quiet selection fill (VSM), hover = hover fill; saturated color never fills the chip — color lives on the glyph (macOS Reminders language) |
| list row | card: surface fill + 1px divider border, radius 8, padding 8,5; 20px round color dot with the emoji inside (11px), name 13px, gray count right — compact, aligned with the sidebar icon column |
| checkbox size | 20px ring in the task's list color (accent fallback); completed = list-color fill with a white check |
| task row | 44px min height, padding 16,9; text 14px; meta 12px with the owning list name (list-colored dot + name) shown in multi-list views; info button at 45% opacity, full on row hover |
| corner radius (rows/cards) | 8 / 10 / 12 |
| content padding | 16, 8; sidebar item 12, 10 |
| task text | 14px; list name 13px |
| view header | large title 22px semibold (view name) + 13px secondary subtitle line beneath (today view → full weekday date, calendar → month with task count, list/all → N open tasks); the show-completed toggle stays top-right |
| due-date semantics | due dates render localized (今天/明天/昨天/8月31日); overdue incomplete → `#FF3B30`, due today → accent, otherwise text/secondary; a leading clock glyph only when a time is set |
| input fields | search 30px, quick add 36px, radius 10, 1px input-border |
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
