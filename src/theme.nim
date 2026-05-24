## Palette parser for Thrawk. Shares the `key: #RRGGBB` format used by
## Prawk/Edrawk/Exrawk so a single .theme file restyles all of them — Thrawk
## treats those apps' fields as primary and adds two sway-specific extras
## (`accent_dim`, `warn`). Unknown keys are ignored on parse so older theme
## files stay forward-compatible.

import std/[os, strutils, algorithm, options]

type Palette* = object
  name*: string                       # filename stem, e.g. "pathsgruv"
  source*: string                     # absolute path the palette was loaded from

  # Shared with Prawk/Edrawk (apps key off these).
  bg*, fg*, accent*, muted*, urgent*: uint32
  borderLight*, borderDark*, separator*: uint32
  codeKeyword*, codeString*, codeComment*, codeNumber*, codeOperator*: uint32
  codeType*, codeReturnType*: uint32
  clInject*: uint32

  # Thrawk-specific extras for sway. Optional; fallbacks at apply-time.
  accentDim*: Option[uint32]          # workspace.active bg (dimmer accent)
  warn*: Option[uint32]               # binding_mode bg (yellow-ish)
  wallpaper*: Option[string]          # absolute path; if absent, solid bg

const defaultPalette* = Palette(
  name: "default",
  bg: 0x292828'u32, fg: 0xd4be98'u32, accent: 0x9253be'u32,
  muted: 0x928374'u32, urgent: 0xea6962'u32,
  borderLight: 0x504945'u32, borderDark: 0x32302f'u32, separator: 0x45403d'u32,
  codeKeyword: 0xd3869b'u32, codeString: 0xd8a657'u32,
  codeComment: 0x928374'u32, codeNumber: 0xd3869b'u32,
  codeOperator: 0xe78a4e'u32,
  codeType: 0xa9b665'u32, codeReturnType: 0x89b482'u32,
  clInject: 0xff0000'u32,
)

proc parseHex(s: string): uint32 =
  let t = s.strip().strip(chars = {'#'})
  # Only 6-digit hex; alpha-channel variants in pathsgruv.txt are ignored.
  if t.len == 6:
    result = uint32(parseHexInt(t))

proc parsePalette*(content: string, p: var Palette): bool =
  ## Returns true if at least one key parsed. Unknown keys silently ignored.
  if content.len == 0: return false
  var hit = false
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith('#'): continue
    let colon = line.find(':')
    if colon <= 0: continue
    let key = line[0 ..< colon].strip()
    let rawVal = line[colon+1 .. ^1].strip()
    # String-valued fields (currently just wallpaper) bypass hex parsing.
    if key == "wallpaper":
      if rawVal.len > 0: p.wallpaper = some(rawVal)
      hit = true
      continue
    let val = parseHex(rawVal)
    hit = true
    case key
    of "bg":            p.bg = val
    of "fg":            p.fg = val
    of "accent":        p.accent = val
    of "muted":         p.muted = val
    of "urgent":        p.urgent = val
    of "border_light":  p.borderLight = val
    of "border_dark":   p.borderDark = val
    of "separator":     p.separator = val
    of "code_keyword":  p.codeKeyword = val
    of "code_string":   p.codeString = val
    of "code_comment":  p.codeComment = val
    of "code_number":   p.codeNumber = val
    of "code_operator": p.codeOperator = val
    of "code_type":     p.codeType = val
    of "code_return_type": p.codeReturnType = val
    of "cl_inject":     p.clInject = val
    of "accent_dim":    p.accentDim = some(val)
    of "warn":          p.warn = some(val)
    else: discard
  hit

proc loadPaletteFile*(path: string): Option[Palette] =
  if not fileExists(path): return
  var body: string
  try: body = readFile(path)
  except IOError: return
  var p = defaultPalette
  p.source = path
  let (_, name, _) = splitFile(path)
  p.name = name
  if not parsePalette(body, p): return
  some(p)

proc discoverThemes*(searchDirs: openArray[string]): seq[Palette] =
  ## Returns palettes from every .theme file in any of `searchDirs`. Earlier
  ## entries shadow later ones by name (binary-adjacent > XDG > user).
  var seen: seq[string]
  for dir in searchDirs:
    if not dirExists(dir): continue
    for kind, path in walkDir(dir, relative = false):
      if kind != pcFile: continue
      let (_, n, ext) = splitFile(path)
      if ext != ".theme" or n.len == 0: continue
      if n in seen: continue
      let p = loadPaletteFile(path)
      if p.isSome:
        result.add(p.get())
        seen.add(n)
  result.sort(proc (a, b: Palette): int = cmp(a.name, b.name))

proc effectiveAccentDim*(p: Palette): uint32 =
  if p.accentDim.isSome: p.accentDim.get() else: p.accent

proc effectiveWarn*(p: Palette): uint32 =
  if p.warn.isSome: p.warn.get() else: p.codeString
