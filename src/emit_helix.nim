## Helix emitter. Two write targets:
##   1. ~/.config/helix/themes/thrawk.toml — full theme file, whole-file
##      overwrite (Thrawk owns it; no markers needed).
##   2. ~/.config/helix/config.toml — marker block holding the single line
##      `theme = "thrawk"` so helix picks up our theme.
## Helix doesn't expose an IPC reload — user must `:config-reload` manually.

import std/[strutils, os, times]
import theme, splice

proc helixConfigPath*(): string =
  getHomeDir() / ".config" / "helix" / "config.toml"

proc helixThemePath*(): string =
  getHomeDir() / ".config" / "helix" / "themes" / "thrawk.toml"

proc genHelixTheme*(p: Palette): string =
  ## Generates a full helix theme. UI mappings reference [palette] names.
  ## Keep the palette names hyphenated to match helix's convention and to
  ## avoid colliding with helix-builtin color names like "red"/"blue".
  let bg          = hex6(p.bg)
  let fg          = hex6(p.fg)
  let accent      = hex6(p.accent)
  let accentDim   = hex6(effectiveAccentDim(p))
  let muted       = hex6(p.muted)
  let urgent      = hex6(p.urgent)
  let warn        = hex6(effectiveWarn(p))
  let borderLight = hex6(p.borderLight)
  let borderDark  = hex6(p.borderDark)
  let separator   = hex6(p.separator)
  let keyword     = hex6(p.codeKeyword)
  let str         = hex6(p.codeString)
  let comment     = hex6(p.codeComment)
  let number      = hex6(p.codeNumber)
  let operator    = hex6(p.codeOperator)
  let typeC       = hex6(p.codeType)
  let retType     = hex6(p.codeReturnType)
  let body = """
# Thrawk-generated helix theme. Regenerated on theme change — do not edit.

"ui.background"            = { bg = "bg" }
"ui.text"                  = { fg = "fg" }
"ui.text.focus"            = { fg = "fg" }
"ui.cursor"                = { bg = "accent", fg = "bg" }
"ui.cursor.primary"        = { bg = "accent", fg = "bg" }
"ui.cursor.match"          = { bg = "separator", fg = "warn" }
"ui.selection"             = { bg = "separator" }
"ui.selection.primary"     = { bg = "separator" }
"ui.linenr"                = { fg = "muted" }
"ui.linenr.selected"       = { fg = "fg" }
"ui.statusline"            = { fg = "fg", bg = "border-dark" }
"ui.statusline.inactive"   = { fg = "muted", bg = "border-dark" }
"ui.statusline.normal"     = { fg = "bg", bg = "accent" }
"ui.statusline.insert"     = { fg = "bg", bg = "return-type" }
"ui.statusline.select"     = { fg = "bg", bg = "warn" }
"ui.popup"                 = { bg = "border-dark", fg = "fg" }
"ui.window"                = { fg = "border-light" }
"ui.help"                  = { bg = "border-dark", fg = "fg" }
"ui.menu"                  = { bg = "border-dark", fg = "fg" }
"ui.menu.selected"         = { bg = "accent", fg = "bg" }
"ui.virtual.whitespace"    = { fg = "border-light" }
"ui.virtual.ruler"         = { bg = "border-light" }
"ui.virtual.indent-guide"  = { fg = "border-light" }
"ui.virtual.inlay-hint"    = { fg = "muted" }
"ui.bufferline"            = { fg = "muted", bg = "border-dark" }
"ui.bufferline.active"     = { fg = "fg", bg = "bg" }
"ui.bufferline.background" = { bg = "border-dark" }

"comment"                  = { fg = "comment", modifiers = ["italic"] }
"keyword"                  = "keyword"
"keyword.control"          = "keyword"
"keyword.control.import"   = "keyword"
"keyword.control.return"   = "keyword"
"keyword.directive"        = "operator"
"keyword.function"         = "keyword"
"keyword.operator"         = "operator"
"keyword.storage"          = "keyword"
"string"                   = "str"
"string.regexp"            = "str"
"string.special"           = "operator"
"constant"                 = "number"
"constant.numeric"         = "number"
"constant.builtin"         = "keyword"
"constant.character.escape" = "operator"
"operator"                 = "operator"
"punctuation"              = { fg = "muted" }
"punctuation.delimiter"    = { fg = "muted" }
"punctuation.bracket"      = { fg = "fg" }
"type"                     = "type-color"
"type.builtin"             = "type-color"
"type.parameter"           = "type-color"
"function"                 = "return-type"
"function.method"          = "return-type"
"function.macro"           = "operator"
"function.builtin"         = "return-type"
"function.special"         = "operator"
"variable"                 = { fg = "fg" }
"variable.parameter"       = { fg = "fg" }
"variable.builtin"         = "keyword"
"variable.other.member"    = { fg = "fg" }
"namespace"                = "type-color"
"attribute"                = "operator"
"tag"                      = "keyword"
"label"                    = "operator"

"diagnostic.error"         = { underline = { color = "urgent", style = "curl" } }
"diagnostic.warning"       = { underline = { color = "warn", style = "curl" } }
"diagnostic.info"          = { underline = { color = "return-type", style = "curl" } }
"diagnostic.hint"          = { underline = { color = "muted", style = "curl" } }
"error"                    = { fg = "urgent" }
"warning"                  = { fg = "warn" }
"info"                     = { fg = "return-type" }
"hint"                     = { fg = "muted" }

"diff.plus"                = { fg = "type-color" }
"diff.minus"               = { fg = "urgent" }
"diff.delta"               = { fg = "operator" }

"markup.heading"           = { fg = "keyword", modifiers = ["bold"] }
"markup.heading.1"         = { fg = "keyword", modifiers = ["bold"] }
"markup.heading.marker"    = { fg = "muted" }
"markup.list"              = "operator"
"markup.bold"              = { modifiers = ["bold"] }
"markup.italic"            = { modifiers = ["italic"] }
"markup.strikethrough"     = { modifiers = ["crossed_out"] }
"markup.link.url"          = { fg = "accent", modifiers = ["underlined"] }
"markup.link.text"         = "return-type"
"markup.link.label"        = "return-type"
"markup.quote"             = { fg = "muted", modifiers = ["italic"] }
"markup.raw"               = "str"

[palette]
bg            = "$BG$"
fg            = "$FG$"
accent        = "$ACCENT$"
accent-dim    = "$ACCENT_DIM$"
muted         = "$MUTED$"
urgent        = "$URGENT$"
warn          = "$WARN$"
border-light  = "$BORDER_LIGHT$"
border-dark   = "$BORDER_DARK$"
separator     = "$SEPARATOR$"
keyword       = "$KEYWORD$"
str           = "$STRING$"
comment       = "$COMMENT$"
number        = "$NUMBER$"
operator      = "$OPERATOR$"
type-color    = "$TYPE$"
return-type   = "$RETURN_TYPE$"
"""
  body
    .replace("$BG$", bg)
    .replace("$FG$", fg)
    .replace("$ACCENT_DIM$", accentDim)
    .replace("$ACCENT$", accent)
    .replace("$MUTED$", muted)
    .replace("$URGENT$", urgent)
    .replace("$WARN$", warn)
    .replace("$BORDER_LIGHT$", borderLight)
    .replace("$BORDER_DARK$", borderDark)
    .replace("$SEPARATOR$", separator)
    .replace("$KEYWORD$", keyword)
    .replace("$STRING$", str)
    .replace("$COMMENT$", comment)
    .replace("$NUMBER$", number)
    .replace("$OPERATOR$", operator)
    .replace("$TYPE$", typeC)
    .replace("$RETURN_TYPE$", retType)

proc writeHelixTheme*(p: Palette): bool =
  atomicWrite(helixThemePath(), genHelixTheme(p))

proc genHelixConfigBlock*(): string =
  ## The block we splice into helix's config.toml. Content doesn't depend
  ## on the palette (theme name is constant), but we still re-splice on
  ## every apply for shape consistency with sway/alacritty/qute.
  let lines = @[
    beginMarker,
    "theme = \"thrawk\"",
    endMarker,
    "",
  ]
  lines.join("\n")

proc spliceHelix*(configPath: string): SpliceError =
  spliceMarkerBlock(configPath, genHelixConfigBlock())

# ── bootstrap ────────────────────────────────────────────────────────────

type InitResult* = object
  ok*: bool
  message*: string
  backupPath*: string

proc stripTopLevelTheme(content: string): string =
  ## Drops any top-level `theme = ...` line so our marker-block setting is
  ## the only one. A `theme` key nested inside a `[…]` section is left alone
  ## (helix only honors the top-level form anyway).
  var lines: seq[string]
  var inSection = false
  for raw in content.splitLines():
    let s = raw.strip()
    if s.startsWith("["):
      inSection = true
    if (not inSection) and s.startsWith("theme") and s.find('=') > 0:
      continue
    lines.add(raw)
  lines.join("\n")

proc initHelix*(configPath: string, p: Palette): InitResult =
  ## Bootstraps helix config.toml: strips any top-level `theme = …` line,
  ## appends the THRAWK marker block, writes the standalone theme file.
  ## Idempotent: refuses if markers are already present in config.toml.
  if not writeHelixTheme(p):
    return InitResult(ok: false, message: "could not write " & helixThemePath())

  var body = ""
  if fileExists(configPath):
    try: body = readFile(configPath)
    except IOError:
      return InitResult(ok: false, message: "could not read " & configPath)

  if "# THRAWK:BEGIN" in body:
    return InitResult(ok: false,
      message: "THRAWK markers already present in helix config.toml — refusing to re-init")

  var backup = ""
  if body.len > 0:
    let stamp = now().format("yyyyMMdd-HHmmss")
    backup = configPath & ".Thrawk-bak." & stamp
    try: writeFile(backup, body)
    except IOError:
      return InitResult(ok: false, message: "could not write backup: " & backup)

  var stripped = stripTopLevelTheme(body)
  if stripped.len > 0 and not stripped.endsWith("\n"):
    stripped.add("\n")
  let final = stripped & genHelixConfigBlock()
  if not atomicWrite(configPath, final):
    return InitResult(ok: false, message: "could not write " & configPath)
  InitResult(ok: true, message: "initialized", backupPath: backup)
