## Reload IPC for live-config tools. Sway and qutebrowser both expose a
## one-shot reload command; alacritty hot-reloads on file change; helix has
## no IPC and is skipped. All calls are best-effort and detached — failures
## (binary missing, daemon not running) just return false.

import std/[os, osproc, strutils]

proc reloadSway*(): bool =
  try:
    discard startProcess("swaymsg", args = ["reload"], options = {poUsePath, poDaemon})
    true
  except OSError:
    false

proc qutebrowserIpcSocketExists(): bool =
  ## True iff $XDG_RUNTIME_DIR/qutebrowser/ contains an `ipc-*` entry —
  ## qutebrowser writes one Unix socket per running instance there. Used
  ## as a cheap proxy for "is qutebrowser running" so we can skip the
  ## reload when it isn't (see reloadQute).
  let runtime = getEnv("XDG_RUNTIME_DIR")
  if runtime.len == 0: return false
  let ipcDir = runtime / "qutebrowser"
  if not dirExists(ipcDir): return false
  for kind, path in walkDir(ipcDir, relative = true):
    if path.startsWith("ipc-"): return true
  false

proc reloadQute*(): bool =
  ## `qutebrowser :config-source` re-executes config.py in the running
  ## instance — but only if one exists. Qt's CLI semantics are
  ## "send-via-IPC if a live server answers it, else start a fresh
  ## qutebrowser with the command queued at startup"; there is no
  ## pure no-op path. Without the gate below, calling reloadQute when
  ## no instance is running spawns a second qutebrowser window, and
  ## calling it while an instance is mid-startup races the socket
  ## handoff (the new process can't connect to the not-yet-listening
  ## server, tries to remove the "stale" socket the first process
  ## still owns, surfaces "error while removing server …" in a Qt
  ## dialog, then falls back to launching a duplicate anyway).
  ##
  ## Gate: only fire when the IPC socket file is already present.
  ## That doesn't eliminate the mid-startup race in theory, but in
  ## practice Thrawk applies happen in response to a user picking a
  ## theme — by then the existing qutebrowser has finished booting
  ## and is listening. False when qutebrowser isn't running.
  if not qutebrowserIpcSocketExists(): return false
  try:
    discard startProcess("qutebrowser", args = [":config-source"], options = {poUsePath, poDaemon})
    true
  except OSError:
    false
