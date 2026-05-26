## Reload IPC for live-config tools. Sway and qutebrowser both expose a
## one-shot reload command; alacritty hot-reloads on file change; helix has
## no IPC and is skipped. All calls are best-effort and detached — failures
## (binary missing, daemon not running) just return false.

import std/[osproc]

proc reloadSway*(): bool =
  try:
    discard startProcess("swaymsg", args = ["reload"], options = {poUsePath, poDaemon})
    true
  except OSError:
    false

proc reloadQute*(): bool =
  ## `qutebrowser :config-source` re-executes config.py in the running
  ## instance. No-op (returns false) if qutebrowser isn't running.
  try:
    discard startProcess("qutebrowser", args = [":config-source"], options = {poUsePath, poDaemon})
    true
  except OSError:
    false
