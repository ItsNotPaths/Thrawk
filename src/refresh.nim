## `swaymsg reload` driver. Fires immediately on every call — wayluigi's
## blocking event loop has no built-in timer hook, so a trailing-edge
## debounce would require driving msgAnimate ticks. Reload is fast (~100 ms,
## bar repaints once) so for v1 we just spawn detached and let the user
## throttle by feel. The subprocess is not awaited.

import std/[osproc]

proc reloadSway*(): bool =
  try:
    discard startProcess("swaymsg", args = ["reload"], options = {poUsePath, poDaemon})
    true
  except OSError:
    false
