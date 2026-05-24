## --init-sway bootstrap. Rewrites a virgin sway config so that color-bearing
## directives reference Thrawk's `$tw_*` variables, and inserts the THRAWK
## marker block above the first reference site. Idempotent: refuses to run
## if markers are already present. Always writes a timestamped backup first.

import std/[os, strutils, times, tables]
import theme, emit_sway

type InitResult* = object
  ok*: bool
  message*: string
  backupPath*: string

# client.<class> position → $tw_* variable mapping. List length matches the
# number of color slots that class accepts (5 for most, 1 for background).
# Runtime `let` rather than `const` because Tables can't be const in Nim.
let clientMap = {
  "focused":          @["$tw_accent",      "$tw_accent",      "$tw_fg",          "$tw_accent",      "$tw_accent"],
  "focused_inactive": @["$tw_separator",   "$tw_separator",   "$tw_fg",          "$tw_separator",   "$tw_separator"],
  "focused_tab_title": @["$tw_separator",  "$tw_separator",   "$tw_fg"],
  "unfocused":        @["$tw_bg",          "$tw_bg",          "$tw_muted",       "$tw_bg",          "$tw_bg"],
  "urgent":           @["$tw_urgent",      "$tw_urgent",      "$tw_border_dark", "$tw_urgent",      "$tw_urgent"],
  "placeholder":      @["$tw_border_dark", "$tw_border_dark", "$tw_fg",          "$tw_border_dark", "$tw_border_dark"],
  "background":       @["$tw_border_dark"],
}.toTable

let barSingle = {
  "background": "$tw_border_dark",
  "statusline": "$tw_fg",
  "separator":  "$tw_separator",
}.toTable

let barTriple = {
  "focused_workspace":  @["$tw_accent",     "$tw_accent",     "$tw_border_dark"],
  "active_workspace":   @["$tw_accent_dim", "$tw_accent_dim", "$tw_fg"],
  "inactive_workspace": @["$tw_bg",         "$tw_bg",         "$tw_muted"],
  "urgent_workspace":   @["$tw_urgent",     "$tw_urgent",     "$tw_border_dark"],
  "binding_mode":       @["$tw_warn",       "$tw_warn",       "$tw_border_dark"],
}.toTable

proc rewriteClient(line: string): string =
  ## Replaces values on a `client.<class>` line by position.
  let stripped = line.strip()
  if not stripped.startsWith("client."): return line
  # Split off leading indent for preservation.
  var leadLen = 0
  while leadLen < line.len and line[leadLen] in {' ', '\t'}: inc leadLen
  let indent = line[0 ..< leadLen]
  let body = line[leadLen .. ^1]
  # Trailing-comment handling intentionally skipped: client.* lines don't
  # legitimately carry inline comments, and a stray `#` would only show up
  # in hex values which we tokenize past via splitWhitespace.
  let parts = body.splitWhitespace()
  if parts.len < 2: return line
  let className = parts[0][len("client.") .. ^1]
  if className notin clientMap: return line
  let repl = clientMap[className]
  if parts.len - 1 != repl.len: return line  # arity mismatch — leave alone
  var newParts = @[parts[0]]
  newParts.add(repl)
  result = indent & newParts.join(" ")

type BarState = enum
  bsOutside, bsInBar, bsInColors

proc rewriteLines(content: string): string =
  ## Walks the config line-by-line, applying client/bar/output rewrites
  ## and stripping the existing `output * bg ...` directive (marker block
  ## emits a managed replacement).
  var lines: seq[string]
  var state = bsOutside
  for raw in content.splitLines():
    let stripped = raw.strip()

    # Drop the existing wallpaper directive(s); managed by marker block.
    if stripped.startsWith("output") and " bg " in stripped:
      continue

    # State machine for `bar { ... colors { ... } }`. Naive but sufficient
    # for typical configs: we look for `bar {`, then `colors {`, then `}`.
    case state
    of bsOutside:
      if stripped.startsWith("bar") and ("{" in stripped or stripped == "bar"):
        state = bsInBar
    of bsInBar:
      if stripped.startsWith("colors") and "{" in stripped:
        state = bsInColors
      elif stripped == "}":
        state = bsOutside
    of bsInColors:
      if stripped == "}":
        state = bsInBar
      else:
        # Rewrite color-bearing keys inside bar.colors.
        var leadLen = 0
        while leadLen < raw.len and raw[leadLen] in {' ', '\t'}: inc leadLen
        let indent = raw[0 ..< leadLen]
        let body = raw[leadLen .. ^1]
        let parts = body.splitWhitespace()
        if parts.len >= 2:
          let key = parts[0]
          if key in barSingle:
            lines.add(indent & key & " " & barSingle[key])
            continue
          if key in barTriple:
            let repl = barTriple[key]
            var newParts = @[key]
            newParts.add(repl)
            lines.add(indent & newParts.join(" "))
            continue

    # client.<class> lines.
    if stripped.startsWith("client."):
      lines.add(rewriteClient(raw))
      continue

    lines.add(raw)

  result = lines.join("\n")

proc findInsertionPoint(content: string): int =
  ## Byte offset at which to splice in the THRAWK marker block. We insert
  ## immediately before the first line whose stripped form starts with one
  ## of: `set $menu`, `client.`, `bar`, `output`. Falls back to end-of-file
  ## (effectively a no-op insertion).
  var pos = 0
  while pos < content.len:
    var eol = pos
    while eol < content.len and content[eol] != '\n': inc eol
    let line = content[pos ..< eol].strip()
    if line.startsWith("set $menu") or line.startsWith("client.") or
       line.startsWith("bar") or
       (line.startsWith("output") and " bg " in line):
      return pos
    pos = eol + 1
  content.len

proc initSwayConfig*(configPath: string, p: Palette): InitResult =
  ## Bootstrap a sway config. Returns {ok=false, message} if markers are
  ## already present or the file can't be read. On success, backupPath is
  ## populated with the timestamped backup file path.
  if not fileExists(configPath):
    return InitResult(ok: false, message: "sway config not found: " & configPath)

  var body: string
  try: body = readFile(configPath)
  except IOError:
    return InitResult(ok: false, message: "could not read " & configPath)

  if "# THRAWK:BEGIN" in body:
    return InitResult(ok: false,
      message: "THRAWK markers already present — refusing to re-init")

  # Backup first. Bail before any writes if the backup fails.
  let stamp = now().format("yyyyMMdd-HHmmss")
  let backup = configPath & ".Thrawk-bak." & stamp
  try: writeFile(backup, body)
  except IOError:
    return InitResult(ok: false, message: "could not write backup: " & backup)

  let rewritten = rewriteLines(body)
  let insertAt = findInsertionPoint(rewritten)
  let withMarkers =
    rewritten[0 ..< insertAt] & genMarkerBlock(p) & rewritten[insertAt .. ^1]

  # Atomic write of the transformed config.
  let tmp = configPath & ".tmp"
  try:
    writeFile(tmp, withMarkers)
    moveFile(tmp, configPath)
  except OSError, IOError:
    try: removeFile(tmp) except: discard
    return InitResult(ok: false, message: "could not write " & configPath)

  InitResult(ok: true, message: "initialized", backupPath: backup)
