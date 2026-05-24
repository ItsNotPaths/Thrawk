## Active-theme dump. Writes ~/.config/unrawk/active.theme as a verbatim
## copy of the chosen palette file plus a header naming the source. Other
## rawk binaries read this single well-known path to pick up the current
## theme without depending on thrawk being installed.

import std/[os, strformat, times, strutils]
import theme

proc activeThemePath*(): string =
  getHomeDir() / ".config" / "unrawk" / "active.theme"

proc atomicWrite(path, content: string): bool =
  let tmp = path & ".tmp"
  try:
    createDir(parentDir(path))
    writeFile(tmp, content)
    moveFile(tmp, path)
    return true
  except OSError, IOError:
    try: removeFile(tmp) except: discard
    return false

proc writeActive*(p: Palette): bool =
  ## Reads the original .theme file at p.source and rewrites it to the
  ## active-theme location with a header. Returns false on any IO failure.
  ## Falls back to a synthesized minimal palette dump if the source file
  ## cannot be read (e.g. for a built-in palette without a backing file).
  let header = &"# active theme — written by thrawk on {now()}\n# source: {p.name} ({p.source})\n"
  var body: string
  if p.source.len > 0 and fileExists(p.source):
    try: body = readFile(p.source)
    except IOError: body = ""
  if body.len == 0:
    # Minimal fallback dump. Keeps the same key: #RRGGBB format Prawk parses.
    proc hex(c: uint32): string = "#" & toHex(BiggestInt(c), 6).toLowerAscii
    body = (
      &"bg:            {hex(p.bg)}\n" &
      &"fg:            {hex(p.fg)}\n" &
      &"accent:        {hex(p.accent)}\n" &
      &"muted:         {hex(p.muted)}\n" &
      &"urgent:        {hex(p.urgent)}\n" &
      &"border_light:  {hex(p.borderLight)}\n" &
      &"border_dark:   {hex(p.borderDark)}\n" &
      &"separator:     {hex(p.separator)}\n" &
      &"code_keyword:  {hex(p.codeKeyword)}\n" &
      &"code_string:   {hex(p.codeString)}\n" &
      &"code_comment:  {hex(p.codeComment)}\n" &
      &"code_number:   {hex(p.codeNumber)}\n" &
      &"code_operator: {hex(p.codeOperator)}\n" &
      &"code_type:        {hex(p.codeType)}\n" &
      &"code_return_type: {hex(p.codeReturnType)}\n" &
      &"cl_inject:        {hex(p.clInject)}\n")
  atomicWrite(activeThemePath(), header & body)
