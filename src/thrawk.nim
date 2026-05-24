## thrawk — themer for the unrawk void overlay.
##
## CLI:
##   thrawk                       launch GUI drum picker
##   thrawk --init-sway [<name>]  one-shot bootstrap of ~/.config/sway/config
##   thrawk --emit-sway <name>    print the THRAWK marker block to stdout
##   thrawk --emit-active <name>  write ~/.config/unrawk/active.theme
##   thrawk --apply <name>        splice sway + write active + reload
##   thrawk --list                list discovered themes by name
##   thrawk --themes-dir <path>   override default search (for testing)
##
## Default theme for --init-sway is "pathsgruv" if present, else first
## discovered.

import std/[os, strutils, parseopt, options, osproc]
import rawk_luigi
import theme, emit_sway, init_sway, emit_unrawk, refresh, themelist

const usage = """
thrawk — themer for the unrawk void overlay

Usage:
  thrawk                       launch GUI drum picker
  thrawk --init-sway [<name>]  bootstrap ~/.config/sway/config (one-shot)
  thrawk --emit-sway <name>    print THRAWK marker block for <name> to stdout
  thrawk --emit-active <name>  write ~/.config/unrawk/active.theme
  thrawk --apply <name>        splice sway + write active + swaymsg reload
  thrawk --list                list discovered themes
  thrawk --help                this message

Discovery: themes/ next to binary, then /etc/xdg/Xrawk/thrawk/themes/, then
~/.config/thrawk/themes/. First match wins on name collision.
"""

proc themeSearchDirs(override: string = ""): seq[string] =
  if override.len > 0: return @[override]
  @[
    getAppDir() / "themes",
    "/etc/xdg/Xrawk/thrawk/themes",
    getHomeDir() / ".config" / "thrawk" / "themes",
  ]

proc swayConfigPath(): string =
  getHomeDir() / ".config" / "sway" / "config"

proc findTheme(themes: seq[Palette], name: string): Option[Palette] =
  for t in themes:
    if t.name == name: return some(t)
  none(Palette)

proc preferred(themes: seq[Palette], name: string): Option[Palette] =
  let direct = findTheme(themes, name)
  if direct.isSome: return direct
  if themes.len > 0: return some(themes[0])
  none(Palette)

proc applyAll(p: Palette): tuple[ok: bool, msg: string] =
  let sp = spliceBlock(swayConfigPath(), p)
  if sp != spOk:
    return (false, errorMessage(sp))
  if not writeActive(p):
    return (false, "could not write " & activeThemePath())
  discard reloadSway()
  (true, "applied " & p.name)

# ─── CLI subcommands ─────────────────────────────────────────────────────

proc cmdList(themes: seq[Palette]) =
  if themes.len == 0:
    quit "no themes found in " & themeSearchDirs().join(", "), 1
  for t in themes: echo t.name

proc cmdEmitSway(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  stdout.write(genMarkerBlock(p.get()))

proc cmdEmitActive(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  if not writeActive(p.get()):
    quit "could not write " & activeThemePath(), 1
  echo "wrote ", activeThemePath()

proc cmdInitSway(themes: seq[Palette], name: string) =
  let p = preferred(themes, if name.len > 0: name else: "pathsgruv")
  if p.isNone: quit "no themes available", 1
  let r = initSwayConfig(swayConfigPath(), p.get())
  if not r.ok: quit r.message, 1
  echo "initialized sway config; backup at ", r.backupPath
  discard writeActive(p.get())
  discard reloadSway()

proc cmdApply(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  let r = applyAll(p.get())
  if not r.ok: quit r.msg, 1
  echo r.msg

# ─── GUI ─────────────────────────────────────────────────────────────────

var
  gThemes:     ref seq[Palette]
  gSearchDirs: seq[string]
  gDrum:       ptr Drum

proc applyForGui(p: Palette) =
  let r = applyAll(p)
  if not r.ok:
    stderr.writeLine "thrawk: " & r.msg

proc rescanForGui() =
  let currentName =
    if gDrum != nil and gThemes[].len > 0:
      gThemes[][gDrum.centerIdx mod gThemes[].len].name
    else: ""
  gThemes[] = discoverThemes(gSearchDirs)
  if gDrum != nil:
    var newIdx = 0
    for i, t in gThemes[]:
      if t.name == currentName:
        newIdx = i; break
    gDrum.centerIdx = newIdx

proc selfFloat() =
  ## Tell sway to float + center our own window via IPC, matched by PID.
  ## Works whether or not the user has run --init-sway (the marker-block
  ## `for_window` rule is the same thing baked declaratively). Delayed in a
  ## child shell so sway has time to register the wayland surface before
  ## the IPC command lands; without the delay the pid lookup misses.
  let pid = $getCurrentProcessId()
  let cmd = "(sleep 0.15 && swaymsg \"[pid=" & pid &
    "] floating enable, resize set width 480 height 230, move position center\" >/dev/null 2>&1) &"
  discard execShellCmd(cmd)

proc runGui(themes: seq[Palette], searchDirs: seq[string]): int =
  gSearchDirs = searchDirs
  gThemes = new(seq[Palette])
  gThemes[] = themes

  initialise()
  # 480×230 matches the `for_window [title="^thrawk$"]` rule in the marker
  # block (and the swaymsg in selfFloat) so sway doesn't tile + resize the
  # window after it appears.
  let win = windowCreate(nil, 0, "thrawk", 480, 230)
  let panel = panelCreate(addr win.e, PANEL_GRAY or ELEMENT_V_FILL or ELEMENT_H_FILL)
  gDrum = drumCreate(addr panel.e, gThemes, applyForGui, rescanForGui)
  elementFocus(addr gDrum.e)

  selfFloat()

  if gThemes[].len > 0:
    applyForGui(gThemes[][gDrum.centerIdx])

  return int(messageLoop())

# ─── entry ───────────────────────────────────────────────────────────────

proc main() =
  var
    initSway = false
    emitSway = ""
    emitActive = ""
    apply = ""
    list = false
    themesDirOverride = ""
    positional: seq[string]

  # Track which value-taking flags want to swallow the next positional.
  var pending = ""

  var op = initOptParser()
  for kind, key, val in op.getopt():
    case kind
    of cmdArgument:
      if pending.len > 0:
        case pending
        of "emit-sway":   emitSway = key
        of "emit-active": emitActive = key
        of "apply":       apply = key
        of "themes-dir":  themesDirOverride = key
        else: discard
        pending = ""
      else:
        positional.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": echo usage; return
      of "init-sway": initSway = true
      of "list": list = true
      of "emit-sway", "emit-active", "apply", "themes-dir":
        if val.len > 0:
          case key
          of "emit-sway":   emitSway = val
          of "emit-active": emitActive = val
          of "apply":       apply = val
          of "themes-dir":  themesDirOverride = val
          else: discard
        else:
          pending = key
      else: quit "unknown option: --" & key, 1
    of cmdEnd: discard

  let searchDirs = themeSearchDirs(themesDirOverride)
  let themes = discoverThemes(searchDirs)

  if list:
    cmdList(themes); return
  if emitSway.len > 0:
    cmdEmitSway(themes, emitSway); return
  if emitActive.len > 0:
    cmdEmitActive(themes, emitActive); return
  if apply.len > 0:
    cmdApply(themes, apply); return
  if initSway:
    let name = if positional.len > 0: positional[0] else: ""
    cmdInitSway(themes, name); return

  # No subcommand: GUI.
  if themes.len == 0:
    quit "no themes found in " & searchDirs.join(", "), 1
  quit runGui(themes, searchDirs)

when isMainModule: main()
