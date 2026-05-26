## Qutebrowser emitter. Splices a THRAWK marker block of direct
## `c.colors.* = "#rrggbb"` assignments into ~/.config/qutebrowser/config.py.
## Python's `#` comment syntax means the markers are valid Python comments;
## the block executes in the user's config-eval scope, so it relies on the
## conventional `c = config` binding that qutebrowser's stub creates.
##
## Reload is best-effort via `qutebrowser :config-source` IPC (see refresh.nim).

import std/[strutils, os, times]
import theme, splice

proc quteConfigPath*(): string =
  getHomeDir() / ".config" / "qutebrowser" / "config.py"

proc q(c: uint32): string = "\"" & hex6(c) & "\""

proc genQuteBlock*(p: Palette): string =
  ## Returns marker block (with BEGIN/END lines, trailing newline) ready to
  ## splice into qutebrowser's config.py. We aim for parity with dracula.draw
  ## — every visible chrome surface gets an explicit mapping so theme changes
  ## are total (no leftover defaults bleeding through).
  let bg          = q(p.bg)
  let fg          = q(p.fg)
  let accent      = q(p.accent)
  let accentDim   = q(effectiveAccentDim(p))
  let muted       = q(p.muted)
  let urgent      = q(p.urgent)
  let warn        = q(effectiveWarn(p))
  let borderLight = q(p.borderLight)
  let borderDark  = q(p.borderDark)
  let codeString  = q(p.codeString)
  let codeRet     = q(p.codeReturnType)
  let lines = @[
    beginMarker,
    "# tabs",
    "c.colors.tabs.bar.bg                    = " & borderDark,
    "c.colors.tabs.even.bg                   = " & borderDark,
    "c.colors.tabs.even.fg                   = " & muted,
    "c.colors.tabs.odd.bg                    = " & borderDark,
    "c.colors.tabs.odd.fg                    = " & muted,
    "c.colors.tabs.selected.even.bg          = " & accent,
    "c.colors.tabs.selected.even.fg          = " & bg,
    "c.colors.tabs.selected.odd.bg           = " & accent,
    "c.colors.tabs.selected.odd.fg           = " & bg,
    "c.colors.tabs.indicator.start           = " & accentDim,
    "c.colors.tabs.indicator.stop            = " & accent,
    "c.colors.tabs.indicator.error           = " & urgent,
    "c.colors.tabs.pinned.even.bg            = " & borderLight,
    "c.colors.tabs.pinned.even.fg            = " & fg,
    "c.colors.tabs.pinned.odd.bg             = " & borderLight,
    "c.colors.tabs.pinned.odd.fg             = " & fg,
    "c.colors.tabs.pinned.selected.even.bg   = " & accent,
    "c.colors.tabs.pinned.selected.even.fg   = " & bg,
    "c.colors.tabs.pinned.selected.odd.bg    = " & accent,
    "c.colors.tabs.pinned.selected.odd.fg    = " & bg,
    "# statusbar",
    "c.colors.statusbar.normal.bg            = " & bg,
    "c.colors.statusbar.normal.fg            = " & fg,
    "c.colors.statusbar.insert.bg            = " & codeRet,
    "c.colors.statusbar.insert.fg            = " & bg,
    "c.colors.statusbar.command.bg           = " & bg,
    "c.colors.statusbar.command.fg           = " & fg,
    "c.colors.statusbar.command.private.bg   = " & borderDark,
    "c.colors.statusbar.command.private.fg   = " & accent,
    "c.colors.statusbar.private.bg           = " & borderDark,
    "c.colors.statusbar.private.fg           = " & accent,
    "c.colors.statusbar.caret.bg             = " & warn,
    "c.colors.statusbar.caret.fg             = " & bg,
    "c.colors.statusbar.caret.selection.bg   = " & accent,
    "c.colors.statusbar.caret.selection.fg   = " & bg,
    "c.colors.statusbar.progress.bg          = " & accent,
    "c.colors.statusbar.url.fg               = " & accent,
    "c.colors.statusbar.url.error.fg         = " & urgent,
    "c.colors.statusbar.url.hover.fg         = " & accent,
    "c.colors.statusbar.url.success.http.fg  = " & fg,
    "c.colors.statusbar.url.success.https.fg = " & fg,
    "c.colors.statusbar.url.warn.fg          = " & warn,
    "# completion",
    "c.colors.completion.fg                          = " & fg,
    "c.colors.completion.even.bg                     = " & bg,
    "c.colors.completion.odd.bg                      = " & borderDark,
    "c.colors.completion.category.bg                 = " & borderDark,
    "c.colors.completion.category.fg                 = " & accent,
    "c.colors.completion.category.border.top         = " & borderDark,
    "c.colors.completion.category.border.bottom      = " & borderDark,
    "c.colors.completion.item.selected.bg            = " & accent,
    "c.colors.completion.item.selected.fg            = " & bg,
    "c.colors.completion.item.selected.border.top    = " & accent,
    "c.colors.completion.item.selected.border.bottom = " & accent,
    "c.colors.completion.item.selected.match.fg      = " & fg,
    "c.colors.completion.match.fg                    = " & codeString,
    "c.colors.completion.scrollbar.bg                = " & bg,
    "c.colors.completion.scrollbar.fg                = " & accent,
    "# downloads",
    "c.colors.downloads.bar.bg               = " & bg,
    "c.colors.downloads.start.bg             = " & accentDim,
    "c.colors.downloads.start.fg             = " & bg,
    "c.colors.downloads.stop.bg              = " & accent,
    "c.colors.downloads.stop.fg              = " & bg,
    "c.colors.downloads.error.bg             = " & urgent,
    "c.colors.downloads.error.fg             = " & bg,
    "# hints",
    "c.colors.hints.bg                       = " & warn,
    "c.colors.hints.fg                       = " & bg,
    "c.colors.hints.match.fg                 = " & urgent,
    "# keyhint",
    "c.colors.keyhint.bg                     = " & borderDark,
    "c.colors.keyhint.fg                     = " & fg,
    "c.colors.keyhint.suffix.fg              = " & warn,
    "# messages",
    "c.colors.messages.error.bg              = " & urgent,
    "c.colors.messages.error.fg              = " & bg,
    "c.colors.messages.error.border          = " & urgent,
    "c.colors.messages.warning.bg            = " & warn,
    "c.colors.messages.warning.fg            = " & bg,
    "c.colors.messages.warning.border        = " & warn,
    "c.colors.messages.info.bg               = " & borderDark,
    "c.colors.messages.info.fg               = " & fg,
    "c.colors.messages.info.border           = " & borderLight,
    "# prompts",
    "c.colors.prompts.bg                     = " & borderDark,
    "c.colors.prompts.fg                     = " & fg,
    "c.colors.prompts.border                 = " & borderLight,
    "c.colors.prompts.selected.bg            = " & accent,
    "c.colors.prompts.selected.fg            = " & bg,
    "# context menu",
    "c.colors.contextmenu.menu.bg            = " & borderDark,
    "c.colors.contextmenu.menu.fg            = " & fg,
    "c.colors.contextmenu.selected.bg        = " & accent,
    "c.colors.contextmenu.selected.fg        = " & bg,
    "c.colors.contextmenu.disabled.bg        = " & borderDark,
    "c.colors.contextmenu.disabled.fg        = " & muted,
    "# webpage",
    "c.colors.webpage.bg                     = " & bg,
    endMarker,
    "",
  ]
  lines.join("\n")

proc spliceQute*(configPath: string, p: Palette): SpliceError =
  spliceMarkerBlock(configPath, genQuteBlock(p))

# ── bootstrap ────────────────────────────────────────────────────────────

type InitResult* = object
  ok*: bool
  message*: string
  backupPath*: string

proc initQute*(configPath: string, p: Palette): InitResult =
  ## Bootstraps qutebrowser config.py: appends the marker block. Unlike
  ## alacritty/helix we don't strip pre-existing c.colors.* lines — Python
  ## is last-write-wins, and we run after `config.load_autoconfig()` so our
  ## values take precedence. Idempotent: refuses if markers already present.
  ## Creates the file with a minimal stub if missing.
  var body = ""
  if fileExists(configPath):
    try: body = readFile(configPath)
    except IOError:
      return InitResult(ok: false, message: "could not read " & configPath)
  else:
    body = "config.load_autoconfig()\n"

  if "# THRAWK:BEGIN" in body:
    return InitResult(ok: false,
      message: "THRAWK markers already present in qutebrowser config.py — refusing to re-init")

  var backup = ""
  if fileExists(configPath):
    let stamp = now().format("yyyyMMdd-HHmmss")
    backup = configPath & ".Thrawk-bak." & stamp
    try: writeFile(backup, body)
    except IOError:
      return InitResult(ok: false, message: "could not write backup: " & backup)

  if body.len > 0 and not body.endsWith("\n"):
    body.add("\n")
  let final = body & genQuteBlock(p)
  if not atomicWrite(configPath, final):
    return InitResult(ok: false, message: "could not write " & configPath)
  InitResult(ok: true, message: "initialized", backupPath: backup)
