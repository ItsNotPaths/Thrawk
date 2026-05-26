## Sway emitter. Produces and splices the THRAWK marker block, which holds
## sway `set $tw_*` variable definitions, the wallpaper line, the launcher
## (`set $menu` pointing at Drawk with `--theme global`), and float rules
## for Thrawk's and Drawk's own windows. The user's main sway config
## references these variables in `client.*` and `bar.colors`; Thrawk
## rewrites variable values only, never structural directives.

import std/[options, strutils]
import theme, splice
export splice.SpliceError, splice.beginMarker, splice.endMarker

proc wallpaperLine(p: Palette): string =
  if p.wallpaper.isSome:
    "set $tw_wallpaper       " & p.wallpaper.get() & " fill"
  else:
    "set $tw_wallpaper       " & hex6(p.bg) & " solid_color"

proc genMarkerBlock*(p: Palette): string =
  ## Returns the contents (including marker lines) for the THRAWK region.
  ## Trailing newline included so callers can splice with simple string ops.
  let lines = @[
    beginMarker,
    "set $tw_bg              " & hex6(p.bg),
    "set $tw_fg              " & hex6(p.fg),
    "set $tw_accent          " & hex6(p.accent),
    "set $tw_accent_dim      " & hex6(effectiveAccentDim(p)),
    "set $tw_muted           " & hex6(p.muted),
    "set $tw_urgent          " & hex6(p.urgent),
    "set $tw_border_light    " & hex6(p.borderLight),
    "set $tw_border_dark     " & hex6(p.borderDark),
    "set $tw_separator       " & hex6(p.separator),
    "set $tw_warn            " & hex6(effectiveWarn(p)),
    wallpaperLine(p),
    "output * bg $tw_wallpaper",
    # Drawk is dmenu-style (reads stdin, writes selection to stdout), so we
    # wrap it in the canonical sway launcher pipeline. `--theme global` makes
    # Drawk follow whatever palette Thrawk last wrote to active.theme.
    "set $menu dmenu_path | /opt/Drawk/Drawk --theme global | xargs swaymsg exec --",
    # Float Thrawk and Drawk centered. wayluigi doesn't set app_id, so we
    # match on xdg_toplevel title (set unconditionally by luigi). Re-applied
    # on each reload — harmless if neither is running.
    "for_window [title=\"^Thrawk$\"] floating enable, resize set width 480 height 230, move position center",
    "for_window [title=\"^Drawk$\"]  floating enable, resize set width 480 height 304, move position center",
    endMarker,
    "",
  ]
  lines.join("\n")

proc spliceBlock*(configPath: string, p: Palette): SpliceError =
  spliceMarkerBlock(configPath, genMarkerBlock(p))

proc errorMessage*(e: SpliceError): string =
  ## Back-compat sway-flavored wrapper for older call sites.
  splice.errorMessage(e, "sway")
