## Thrawk — themer for the unrawk void overlay.
##
## CLI:
##   Thrawk                              launch GUI drum picker
##   Thrawk --init-sway       [<name>]   one-shot bootstrap of sway config
##   Thrawk --init-alacritty  [<name>]   one-shot bootstrap of alacritty.toml
##   Thrawk --init-helix      [<name>]   one-shot bootstrap of helix config
##   Thrawk --init-qute       [<name>]   one-shot bootstrap of qutebrowser config.py
##   Thrawk --init-all        [<name>]   bootstrap every supported target
##   Thrawk --emit-sway       <name>     print sway marker block
##   Thrawk --emit-alacritty  <name>     print alacritty marker block
##   Thrawk --emit-helix      <name>     print helix theme file
##   Thrawk --emit-qute       <name>     print qutebrowser marker block
##   Thrawk --emit-active     <name>     write ~/.config/unrawk/active.theme
##   Thrawk --apply           <name>     re-splice every target + reload daemons
##   Thrawk --list                       list discovered themes by name
##   Thrawk --themes-dir <path>          override default search (for testing)
##
## Default theme for --init-* is "pathsgruv" if present, else first discovered.

import std/[os, strutils, parseopt, options]
import rawk_luigi
import theme, emit_sway, init_sway, emit_unrawk, refresh, themelist, splice
import emit_alacritty, emit_helix, emit_qute

const usage = """
Thrawk — themer for the unrawk void overlay

Usage:
  Thrawk                              launch GUI drum picker
  Thrawk --init-sway       [<name>]   bootstrap ~/.config/sway/config
  Thrawk --init-alacritty  [<name>]   bootstrap ~/.config/alacritty/alacritty.toml
  Thrawk --init-helix      [<name>]   bootstrap ~/.config/helix/config.toml
  Thrawk --init-qute       [<name>]   bootstrap ~/.config/qutebrowser/config.py
  Thrawk --init-all        [<name>]   bootstrap every supported target
  Thrawk --emit-sway       <name>     print sway marker block
  Thrawk --emit-alacritty  <name>     print alacritty marker block
  Thrawk --emit-helix      <name>     print helix theme file content
  Thrawk --emit-qute       <name>     print qutebrowser marker block
  Thrawk --emit-active     <name>     write ~/.config/unrawk/active.theme
  Thrawk --apply           <name>     splice all configs + reload running daemons
  Thrawk --list                       list discovered themes
  Thrawk --help                       this message

Discovery: themes/ next to binary, then /etc/xdg/Xrawk/Thrawk/themes/, then
~/.config/Thrawk/themes/. First match wins on name collision.
"""

proc themeSearchDirs(override: string = ""): seq[string] =
  if override.len > 0: return @[override]
  @[
    getAppDir() / "themes",
    "/etc/xdg/Xrawk/Thrawk/themes",
    getHomeDir() / ".config" / "Thrawk" / "themes",
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

# ── apply ────────────────────────────────────────────────────────────────

proc softSplice(label: string, r: SpliceError) =
  ## Apply-time splice handler for non-sway targets: missing markers or a
  ## missing config file are normal (user doesn't run that app) — log and
  ## continue. Anything else gets a louder warning, still non-fatal.
  if r == spOk or r == spMissingMarkers or r == spNoConfig:
    return
  stderr.writeLine "Thrawk: " & splice.errorMessage(r, label)

proc applyAll(p: Palette): tuple[ok: bool, msg: string] =
  # Sway is the critical target: client.* lines reference $tw_* variables
  # so a missing splice would leave sway with undefined symbols. Hard fail.
  let sp = spliceBlock(swayConfigPath(), p)
  if sp != spOk:
    return (false, splice.errorMessage(sp, "sway"))

  # Optional targets: soft-fail so a user without (say) helix installed
  # can still re-theme sway+alacritty+qute.
  softSplice("alacritty",   spliceAlacritty(alacrittyConfigPath(), p))
  softSplice("qutebrowser", spliceQute(quteConfigPath(), p))
  softSplice("helix",       spliceHelix(helixConfigPath()))
  # Helix theme file is whole-file Thrawk-owned — write unconditionally.
  discard writeHelixTheme(p)

  if not writeActive(p):
    return (false, "could not write " & activeThemePath())
  discard reloadSway()
  discard reloadQute()  # best-effort: no-op if qutebrowser isn't running
  (true, "applied " & p.name)

# ── CLI subcommands ──────────────────────────────────────────────────────

proc cmdList(themes: seq[Palette]) =
  if themes.len == 0:
    quit "no themes found in " & themeSearchDirs().join(", "), 1
  for t in themes: echo t.name

proc cmdEmitSway(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  stdout.write(genMarkerBlock(p.get()))

proc cmdEmitAlacritty(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  stdout.write(genAlacrittyBlock(p.get()))

proc cmdEmitHelix(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  stdout.write(genHelixTheme(p.get()))

proc cmdEmitQute(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  stdout.write(genQuteBlock(p.get()))

proc cmdEmitActive(themes: seq[Palette], name: string) =
  let p = findTheme(themes, name)
  if p.isNone: quit "no such theme: " & name, 1
  if not writeActive(p.get()):
    quit "could not write " & activeThemePath(), 1
  echo "wrote ", activeThemePath()

proc pickInitTheme(themes: seq[Palette], name: string): Palette =
  let p = preferred(themes, if name.len > 0: name else: "pathsgruv")
  if p.isNone: quit "no themes available", 1
  p.get()

proc cmdInitSway(themes: seq[Palette], name: string) =
  let p = pickInitTheme(themes, name)
  let r = initSwayConfig(swayConfigPath(), p)
  if not r.ok: quit r.message, 1
  echo "sway: initialized; backup at ", r.backupPath
  discard writeActive(p)
  discard reloadSway()

proc cmdInitAlacritty(themes: seq[Palette], name: string) =
  let p = pickInitTheme(themes, name)
  let r = initAlacritty(alacrittyConfigPath(), p)
  if not r.ok: quit r.message, 1
  if r.backupPath.len > 0:
    echo "alacritty: initialized; backup at ", r.backupPath
  else:
    echo "alacritty: initialized (no prior config)"

proc cmdInitHelix(themes: seq[Palette], name: string) =
  let p = pickInitTheme(themes, name)
  let r = initHelix(helixConfigPath(), p)
  if not r.ok: quit r.message, 1
  if r.backupPath.len > 0:
    echo "helix: initialized; backup at ", r.backupPath
  else:
    echo "helix: initialized (no prior config)"
  echo "helix: theme written to ", helixThemePath()

proc cmdInitQute(themes: seq[Palette], name: string) =
  let p = pickInitTheme(themes, name)
  let r = initQute(quteConfigPath(), p)
  if not r.ok: quit r.message, 1
  if r.backupPath.len > 0:
    echo "qutebrowser: initialized; backup at ", r.backupPath
  else:
    echo "qutebrowser: initialized (no prior config)"

proc cmdInitAll(themes: seq[Palette], name: string) =
  ## Best-effort sequential bootstrap. Each step prints its own status;
  ## failures don't abort later steps so the user gets full visibility.
  let p = pickInitTheme(themes, name)
  block sway:
    let r = initSwayConfig(swayConfigPath(), p)
    if r.ok: echo "sway:        initialized; backup at ", r.backupPath
    else:    stderr.writeLine "sway:        " & r.message
  block ala:
    let r = initAlacritty(alacrittyConfigPath(), p)
    if r.ok: echo "alacritty:   initialized" & (if r.backupPath.len > 0: "; backup at " & r.backupPath else: "")
    else:    stderr.writeLine "alacritty:   " & r.message
  block hel:
    let r = initHelix(helixConfigPath(), p)
    if r.ok: echo "helix:       initialized" & (if r.backupPath.len > 0: "; backup at " & r.backupPath else: "")
    else:    stderr.writeLine "helix:       " & r.message
  block qute:
    let r = initQute(quteConfigPath(), p)
    if r.ok: echo "qutebrowser: initialized" & (if r.backupPath.len > 0: "; backup at " & r.backupPath else: "")
    else:    stderr.writeLine "qutebrowser: " & r.message
  discard writeActive(p)
  discard reloadSway()
  discard reloadQute()

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
    stderr.writeLine "Thrawk: " & r.msg

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
  # 480×230 matches the `for_window [title="^Thrawk$"]` rule in the marker
  # block (and the swaymsg in selfFloat) so sway doesn't tile + resize the
  # window after it appears.
  let win = windowCreate(nil, 0, "Thrawk", 480, 230)
  let panel = panelCreate(addr win.e, PANEL_GRAY or ELEMENT_V_FILL or ELEMENT_H_FILL)
  gDrum = drumCreate(addr panel.e, gThemes, applyForGui, rescanForGui)
  elementFocus(addr gDrum.e)

  # Start the drum on whatever theme is currently active so we don't
  # silently re-apply a different one on launch. If active.theme is missing
  # or names something not in the discovered set, fall back to index 0.
  let activeName = readActiveThemeName()
  if activeName.len > 0:
    for i, t in gThemes[]:
      if t.name == activeName:
        gDrum.centerIdx = i
        break

  selfFloat()

  return int(messageLoop())

# ─── entry ───────────────────────────────────────────────────────────────

proc main() =
  var
    initSway = false
    initAla  = false
    initHel  = false
    initQut  = false
    initAll  = false
    emitSway = ""
    emitAla  = ""
    emitHel  = ""
    emitQut  = ""
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
        of "emit-sway":      emitSway   = key
        of "emit-alacritty": emitAla    = key
        of "emit-helix":     emitHel    = key
        of "emit-qute":      emitQut    = key
        of "emit-active":    emitActive = key
        of "apply":          apply      = key
        of "themes-dir":     themesDirOverride = key
        else: discard
        pending = ""
      else:
        positional.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": echo usage; return
      of "init-sway":      initSway = true
      of "init-alacritty": initAla  = true
      of "init-helix":     initHel  = true
      of "init-qute":      initQut  = true
      of "init-all":       initAll  = true
      of "list": list = true
      of "emit-sway", "emit-alacritty", "emit-helix", "emit-qute",
         "emit-active", "apply", "themes-dir":
        if val.len > 0:
          case key
          of "emit-sway":      emitSway   = val
          of "emit-alacritty": emitAla    = val
          of "emit-helix":     emitHel    = val
          of "emit-qute":      emitQut    = val
          of "emit-active":    emitActive = val
          of "apply":          apply      = val
          of "themes-dir":     themesDirOverride = val
          else: discard
        else:
          pending = key
      else: quit "unknown option: --" & key, 1
    of cmdEnd: discard

  let searchDirs = themeSearchDirs(themesDirOverride)
  let themes = discoverThemes(searchDirs)

  if list:
    cmdList(themes); return
  if emitSway.len > 0:    cmdEmitSway(themes, emitSway); return
  if emitAla.len > 0:     cmdEmitAlacritty(themes, emitAla); return
  if emitHel.len > 0:     cmdEmitHelix(themes, emitHel); return
  if emitQut.len > 0:     cmdEmitQute(themes, emitQut); return
  if emitActive.len > 0:  cmdEmitActive(themes, emitActive); return
  if apply.len > 0:       cmdApply(themes, apply); return

  let posName = if positional.len > 0: positional[0] else: ""
  if initAll:  cmdInitAll(themes, posName); return
  if initSway: cmdInitSway(themes, posName); return
  if initAla:  cmdInitAlacritty(themes, posName); return
  if initHel:  cmdInitHelix(themes, posName); return
  if initQut:  cmdInitQute(themes, posName); return

  # No subcommand: GUI.
  if themes.len == 0:
    quit "no themes found in " & searchDirs.join(", "), 1
  quit runGui(themes, searchDirs)

when isMainModule: main()
