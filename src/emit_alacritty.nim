## Alacritty emitter. Splices a THRAWK marker block into alacritty.toml
## containing `[colors.*]` tables. Markers are TOML comments so alacritty
## parses the block transparently. With live_config_reload (default true)
## alacritty picks up changes the moment the file is rewritten.

import std/[strutils, os, times]
import theme, splice

proc alacrittyConfigPath*(): string =
  getHomeDir() / ".config" / "alacritty" / "alacritty.toml"

proc q(c: uint32): string = "\"" & hex6(c) & "\""

proc genAlacrittyBlock*(p: Palette): string =
  ## Marker block (with BEGIN/END lines, trailing newline) ready to splice.
  ## ANSI mapping uses our palette best-fits: blue ← accent (we don't carry
  ## a true blue), cyan ← code_return_type, magenta ← code_keyword. Themes
  ## that need different ANSI choices should add per-channel overrides later.
  let lines = @[
    beginMarker,
    "[colors.primary]",
    "background = " & q(p.bg),
    "foreground = " & q(p.fg),
    "",
    "[colors.cursor]",
    "text   = " & q(p.bg),
    "cursor = " & q(p.accent),
    "",
    "[colors.selection]",
    "text       = " & q(p.fg),
    "background = " & q(p.separator),
    "",
    "[colors.normal]",
    "black   = " & q(p.borderDark),
    "red     = " & q(p.urgent),
    "green   = " & q(p.codeType),
    "yellow  = " & q(p.codeString),
    "blue    = " & q(p.accent),
    "magenta = " & q(p.codeKeyword),
    "cyan    = " & q(p.codeReturnType),
    "white   = " & q(p.fg),
    "",
    "[colors.bright]",
    "black   = " & q(p.borderLight),
    "red     = " & q(p.urgent),
    "green   = " & q(p.codeType),
    "yellow  = " & q(p.codeOperator),
    "blue    = " & q(effectiveAccentDim(p)),
    "magenta = " & q(p.codeKeyword),
    "cyan    = " & q(p.codeReturnType),
    "white   = " & q(p.fg),
    endMarker,
    "",
  ]
  lines.join("\n")

proc spliceAlacritty*(configPath: string, p: Palette): SpliceError =
  spliceMarkerBlock(configPath, genAlacrittyBlock(p))

# ── bootstrap ────────────────────────────────────────────────────────────

type InitResult* = object
  ok*: bool
  message*: string
  backupPath*: string

proc stripColorSections(content: string): string =
  ## Drops every `[colors.*]` table from a TOML document — header line plus
  ## all following lines up to the next `[…]` header or EOF. Preserves
  ## non-color tables verbatim. Naive single-pass scan; nested inline-table
  ## values aren't affected because we only look at section headers.
  var lines: seq[string]
  var skipping = false
  for raw in content.splitLines():
    let s = raw.strip()
    if s.startsWith("["):
      skipping = s.startsWith("[colors.") or s == "[colors]"
    if not skipping:
      lines.add(raw)
  lines.join("\n")

proc initAlacritty*(configPath: string, p: Palette): InitResult =
  ## Bootstraps alacritty.toml: strips pre-existing `[colors.*]` tables,
  ## appends the THRAWK marker block at end of file, with timestamped backup.
  ## Idempotent: refuses if markers are already present. Creates the file
  ## if missing (alacritty's default is an empty config).
  var body = ""
  if fileExists(configPath):
    try: body = readFile(configPath)
    except IOError:
      return InitResult(ok: false, message: "could not read " & configPath)

  if "# THRAWK:BEGIN" in body:
    return InitResult(ok: false,
      message: "THRAWK markers already present in alacritty.toml — refusing to re-init")

  var backup = ""
  if body.len > 0:
    let stamp = now().format("yyyyMMdd-HHmmss")
    backup = configPath & ".Thrawk-bak." & stamp
    try: writeFile(backup, body)
    except IOError:
      return InitResult(ok: false, message: "could not write backup: " & backup)

  var stripped = stripColorSections(body)
  if stripped.len > 0 and not stripped.endsWith("\n"):
    stripped.add("\n")
  let final = stripped & genAlacrittyBlock(p)
  if not atomicWrite(configPath, final):
    return InitResult(ok: false, message: "could not write " & configPath)
  InitResult(ok: true, message: "initialized", backupPath: backup)
