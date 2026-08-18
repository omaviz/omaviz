# THEME_PALETTE.md — omaviz color reference

Active Omarchy theme: **Matte Black** (`/usr/share/omarchy/themes/matte-black/colors.toml`).

These are the **canonical** hex values that all omaviz visualization color
sourcing must align to. The plugin never invents its own colors; when a visual
needs a gradient (theme color sync), it uses `themeBottom -> themeTop`, which
default to the Matte Black accent/bright-blue pair below.

## Matte Black palette (verbatim from colors.toml)

| Role | Key | Hex |
|------|-----|-----|
| accent | accent | `#e68e0d` |
| selection | selection | `#2a2a2a` |
| muted | muted | `#333333` |
| background | background | `#121212` |
| dark_background | dark_background | `#0d0d0d` |
| darker_background | darker_background | `#090909` |
| lighter_background | lighter_background | `#1e1e1e` |
| foreground | foreground | `#bebebe` |
| dark_foreground | dark_foreground | `#555555` |
| light_foreground | light_foreground | `#8a8a8d` |
| bright_foreground | bright_foreground | `#bebebe` |
| red | red | `#D35F5F` |
| yellow | yellow | `#b91c1c` |
| orange | orange | `#c63d3d` |
| green | green | `#FFC107` |
| cyan | cyan | `#bebebe` |
| blue | blue | `#e68e0d` |
| magenta | magenta | `#D35F5F` |
| brown | brown | `#631e1e` |
| bright_red | bright_red | `#B91C1C` |
| bright_yellow | bright_yellow | `#b90a0a` |
| bright_green | bright_green | `#FFC107` |
| bright_cyan | bright_cyan | `#eaeaea` |
| bright_blue | bright_blue | `#f59e0b` |
| bright_magenta | bright_magenta | `#B91C1C` |

## Mapping onto omaviz

- **`themeBottom` (gradient start)** → `accent` = `#e68e0d`
- **`themeTop` (gradient end)** → `bright_blue` = `#f59e0b`
- **`customColor` default** → `#5ec8ff` (unchanged legacy default; user-overridable)
- **Canvas-2D `VisualCanvas.qml` scheme 0 (theme)** → `#e68e0d` → `#f59e0b` stop ramp.
- **Bar-widget color-sync fallback** already uses `#e68e0d` / `#f59e0b`.

> The previous hardcoded `#19e0d4` / `#a45cff` (cyan/purple) did NOT match
> Matte Black and were replaced by the values above in v7.2 (TASK #2).

## Source of truth
`/usr/share/omarchy/themes/matte-black/colors.toml` — if the active theme
changes, regenerate this file from that path.
