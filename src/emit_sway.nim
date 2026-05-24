## Sway emitter. Produces and splices the THRAWK marker block, which holds
## sway `set $tw_*` variable definitions plus the wallpaper line. The user's
## main sway config references these variables in `client.*` and
## `bar.colors`; Thrawk rewrites variable values only, never structural
## directives. The `set $menu` line is unmanaged — the user owns the
## launcher invocation.

import std/[strutils, os, options]
import theme

const
  beginMarker* = "# THRAWK:BEGIN  (managed by Thrawk — do not edit; regenerated on theme change)"
  endMarker*   = "# THRAWK:END"

proc hex(c: uint32): string = "#" & toHex(BiggestInt(c), 6).toLowerAscii

proc wallpaperLine(p: Palette): string =
  if p.wallpaper.isSome:
    "set $tw_wallpaper       " & p.wallpaper.get() & " fill"
  else:
    "set $tw_wallpaper       " & hex(p.bg) & " solid_color"

proc genMarkerBlock*(p: Palette): string =
  ## Returns the contents (including marker lines) for the THRAWK region.
  ## Trailing newline included so callers can splice with simple string ops.
  let lines = @[
    beginMarker,
    "set $tw_bg              " & hex(p.bg),
    "set $tw_fg              " & hex(p.fg),
    "set $tw_accent          " & hex(p.accent),
    "set $tw_accent_dim      " & hex(effectiveAccentDim(p)),
    "set $tw_muted           " & hex(p.muted),
    "set $tw_urgent          " & hex(p.urgent),
    "set $tw_border_light    " & hex(p.borderLight),
    "set $tw_border_dark     " & hex(p.borderDark),
    "set $tw_separator       " & hex(p.separator),
    "set $tw_warn            " & hex(effectiveWarn(p)),
    wallpaperLine(p),
    "output * bg $tw_wallpaper",
    # Force Thrawk's own window to float, centered, small. wayluigi doesn't
    # set app_id, so we match by xdg_toplevel title (set unconditionally by
    # luigi). Re-applied on each reload — harmless if no Thrawk is running.
    "for_window [title=\"^Thrawk$\"] floating enable, resize set width 480 height 230, move position center",
    endMarker,
    "",
  ]
  lines.join("\n")

type SpliceError* = enum
  spOk, spMissingMarkers, spOnlyOneMarker, spOutOfOrder, spIoError

proc atomicWrite(path, content: string): bool =
  ## Write to path.tmp then rename. Returns false on any IO failure.
  let tmp = path & ".tmp"
  try:
    writeFile(tmp, content)
    moveFile(tmp, path)
    return true
  except OSError, IOError:
    try: removeFile(tmp) except: discard
    return false

proc findRegion(content: string): tuple[ok: SpliceError, b, e: int] =
  ## Returns (ok, beginLineStart, endLineStart) — byte offsets of the
  ## beginning of the BEGIN line and the beginning of the END line.
  let bi = content.find("# THRAWK:BEGIN")
  let ei = content.find("# THRAWK:END")
  if bi < 0 and ei < 0: return (spMissingMarkers, -1, -1)
  if bi < 0 or ei < 0:  return (spOnlyOneMarker, -1, -1)
  if ei < bi:           return (spOutOfOrder, -1, -1)
  (spOk, bi, ei)

proc spliceBlock*(configPath: string, p: Palette): SpliceError =
  ## Atomically replaces the existing THRAWK marker block with one for `p`.
  ## Returns spOk on success, or a specific error code on failure.
  if not fileExists(configPath): return spIoError
  var body: string
  try: body = readFile(configPath)
  except IOError: return spIoError
  let (ok, b, e) = findRegion(body)
  if ok != spOk: return ok
  # Extend `e` to end of the END marker line (one past final '\n').
  var eEnd = e
  while eEnd < body.len and body[eEnd] != '\n': inc eEnd
  if eEnd < body.len: inc eEnd  # consume the newline
  let newBody = body[0 ..< b] & genMarkerBlock(p) & body[eEnd .. ^1]
  if not atomicWrite(configPath, newBody): return spIoError
  spOk

proc errorMessage*(e: SpliceError): string =
  case e
  of spOk:             ""
  of spMissingMarkers: "no THRAWK markers in sway config — run `Thrawk --init-sway` first"
  of spOnlyOneMarker:  "sway config has only one THRAWK marker (corrupted state — refusing to splice)"
  of spOutOfOrder:     "sway config THRAWK markers are out of order"
  of spIoError:        "could not read/write sway config"
