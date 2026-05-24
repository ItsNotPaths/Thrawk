## The drum-roll picker. Centered vertical "Tekken 3 mode select" widget:
## 3–5 themes visible, center enlarged + bordered with swatches, neighbors
## progressively faded above/below. Up/Down/j/k rotates; wheel scrolls;
## click on a neighbor jumps it to center. Wraps around at both ends.

import std/[strutils]
import rawk_luigi, theme

const
  visibleHalf  = 2              # center ± visibleHalf slots
  slotSpacing  = 38             # vertical gap between slots, px
  bandHeight   = 30             # height of the center striped band, px
  bandWidth    = 320            # width of the band's horizontal extent, px
  bandSlant    = 16             # x-shear from top to bottom of band, px

type
  OnChangeProc* = proc(p: Palette) {.closure.}
  RescanProc*   = proc() {.closure.}

  Drum* = object
    e*: Element
    themes*: ref seq[Palette]   # shared with main so Ctrl+R can mutate
    centerIdx*: int
    onChange*: OnChangeProc
    onRescan*: RescanProc

# u32 ARGB <-> components.
proc rgbParts(c: uint32): (int, int, int) =
  (int((c shr 16) and 0xFF), int((c shr 8) and 0xFF), int(c and 0xFF))

proc packRGB(r, g, b: int): uint32 =
  uint32(0xFF000000'u32) or (uint32(r and 0xFF) shl 16) or
    (uint32(g and 0xFF) shl 8) or uint32(b and 0xFF)

proc mixColor(a, b: uint32, t: float): uint32 =
  ## Linearly blends a→b by t. t=0 returns a, t=1 returns b.
  let (ar, ag, ab) = rgbParts(a)
  let (br, bg, bb) = rgbParts(b)
  let s = 1.0 - t
  packRGB(int(float(ar)*s + float(br)*t),
          int(float(ag)*s + float(bg)*t),
          int(float(ab)*s + float(bb)*t))

proc currentTheme*(d: ptr Drum): Palette =
  if d.themes[].len == 0: defaultPalette
  else: d.themes[][d.centerIdx mod d.themes[].len]

proc rotate*(d: ptr Drum, delta: int) =
  let n = d.themes[].len
  if n == 0: return
  d.centerIdx = ((d.centerIdx + delta) mod n + n) mod n
  if d.onChange != nil:
    d.onChange(d.themes[][d.centerIdx])
  if d.e.window != nil:
    elementRepaint(addr d.e, nil)

proc themeAt(d: ptr Drum, offset: int): Palette =
  ## Wrap-around indexing relative to centerIdx.
  let n = d.themes[].len
  let idx = ((d.centerIdx + offset) mod n + n) mod n
  d.themes[][idx]

proc drawPatternedBg(p: ptr Painter, area: Rectangle, pal: Palette) =
  ## 45°-rotated checker of two darkenings of `bg` (the centered band stripe).
  ## Both checker cells are darker than the bg stripe itself, so the centered
  ## stripe always reads brighter than the background no matter the theme.
  const cellSize = 14
  let colorA = mixColor(pal.bg, 0'u32, 0.25)
  let colorB = mixColor(pal.bg, 0'u32, 0.45)
  let pix = painterPixels(p)
  let pw  = p.width
  # Big offset keeps u/v positive across the window for `div`-based cells.
  const offset = 100_000
  for y in area.t ..< area.b:
    if y < p.clip.t or y >= p.clip.b: continue
    for x in area.l ..< area.r:
      if x < p.clip.l or x >= p.clip.r: continue
      let u = int(x) + int(y) + offset
      let v = int(x) - int(y) + offset
      let cell = ((u div cellSize) + (v div cellSize)) and 1
      pix[int(y) * int(pw) + int(x)] = if cell == 0: colorA else: colorB

proc bandStripeColors(pal: Palette): array[5, uint32] =
  ## Band stripes (left → right): warn, accent, bg (center), urgent, fg.
  [effectiveWarn(pal), pal.accent, pal.bg, pal.urgent, pal.fg]

proc luminance(c: uint32): float =
  let (r, g, b) = rgbParts(c)
  0.2126 * float(r) + 0.7152 * float(g) + 0.0722 * float(b)

proc textForBg(bg: uint32): uint32 =
  ## Grayscale text color = luminance-inverted bg, with extra push toward the
  ## nearest extreme when bg sits in the mid-tone band. Without the push, a bg
  ## near luminance 127 would invert to ~127 (same brightness, no contrast);
  ## the push exaggerates the inversion proportional to mid-distance.
  let L = luminance(bg)
  var inv = 255.0 - L
  let midDist = abs(inv - 127.5)
  if midDist < 60.0:
    let push = (60.0 - midDist) * 2.2  # up to ~130 extra brightness shift
    if inv > 127.5: inv = min(255.0, inv + push)
    else:           inv = max(0.0,   inv - push)
  let g = clamp(int(inv), 0, 255)
  packRGB(g, g, g)

proc drawSlantedBand(p: ptr Painter, cx, cy: cint,
                     colors: array[5, uint32]) =
  ## Sheared parallelogram of colored stripes, centered on (cx, cy). Writes
  ## directly to the painter pixel buffer — drawBlock is rectangle-only and
  ## can't express the slant. Stripe boundaries follow the shear so the band
  ## reads as one slanted shape made up of these colors.
  let pix = painterPixels(p)
  let pw  = p.width
  let h   = bandHeight
  let w   = bandWidth
  let n   = colors.len
  let half = float(h) / 2.0
  let leftSrc = cx - cint(w div 2)
  let topSrc  = cy - cint(h div 2)

  for yi in 0 ..< h:
    let y = topSrc + cint(yi)
    if y < p.clip.t or y >= p.clip.b: continue
    let shift = (float(bandSlant) * (float(yi) - half)) / half
    for xi in 0 ..< w:
      let dxf = float(xi) + shift
      let x = leftSrc + cint(int(dxf))
      if x < p.clip.l or x >= p.clip.r: continue
      let stripe = clamp((xi * n) div w, 0, n - 1)
      pix[int(y) * int(pw) + int(x)] = colors[stripe]

proc paintCenter(p: ptr Painter, area: Rectangle, baseY: cint, pal: Palette) =
  let centerX = (area.l + area.r) div 2
  drawSlantedBand(p, centerX, baseY, bandStripeColors(pal))
  # Text sits over the centered `bg` stripe, so contrast against that. Shadow
  # = bg, drawn 1px offset — invisible over the bg stripe (clean) and a
  # 1px contrast outline against any other stripe the text overlaps.
  let textColor   = textForBg(pal.bg)
  let shadowColor = pal.bg
  let label = pal.name.toUpperAscii
  let labelW = cint(label.len * 9 + 24)
  let txtRect = Rectangle(
    l: centerX - labelW div 2, r: centerX + labelW div 2,
    t: baseY - 9, b: baseY + 9)
  let shadowRect = Rectangle(
    l: txtRect.l + 1, r: txtRect.r + 1,
    t: txtRect.t + 1, b: txtRect.b + 1)
  drawString(p, shadowRect, label.cstring, label.len,
             shadowColor, cint(ALIGN_CENTER), nil)
  drawString(p, txtRect, label.cstring, label.len,
             textColor, cint(ALIGN_CENTER), nil)

proc paintSlot(p: ptr Painter, d: ptr Drum, offset: int,
               area: Rectangle, baseY: cint) =
  let n = d.themes[].len
  if n == 0: return
  if n <= visibleHalf and abs(offset) > 0 and (abs(offset) >= n):
    return

  let pal = themeAt(d, offset)
  let centerX = (area.l + area.r) div 2
  let y = baseY + cint(offset) * slotSpacing

  if offset == 0:
    paintCenter(p, area, y, pal)
    return

  let bg = ui.theme.panel1
  let fg = ui.theme.text
  let dimT = float(abs(offset)) * 0.30
  let color = mixColor(fg, bg, dimT)
  let nameLen = pal.name.len
  let approxWidth = cint(nameLen * 9 + 40)
  let txtRect = Rectangle(
    l: centerX - approxWidth div 2,
    r: centerX + approxWidth div 2,
    t: y - 10, b: y + 10)
  drawString(p, txtRect, pal.name.cstring, pal.name.len,
             color, cint(ALIGN_CENTER), nil)

proc slotIndexAtY(d: ptr Drum, area: Rectangle, py: cint): int =
  ## Returns the visible-slot offset (–2..+2) under cursor y, or out-of-range.
  let baseY = (area.t + area.b) div 2
  let dy = py - baseY
  # Pick the offset whose slot center is closest to dy.
  var best = 999
  var bestAbs = 99999
  for off in -visibleHalf .. visibleHalf:
    let slotY = cint(off) * slotSpacing
    let dist = abs(int(dy - slotY))
    if dist < bestAbs:
      bestAbs = dist
      best = off
  # Only count clicks within half-slot of a slot's center.
  if bestAbs > slotSpacing div 2: 999 else: best

proc drumMessage(element: ptr Element, message: Message,
                 di: cint, dp: pointer): cint {.cdecl.} =
  let d = cast[ptr Drum](element)

  if message == msgPaint:
    let p = cast[ptr Painter](dp)
    if d.themes[].len > 0:
      drawPatternedBg(p, element.bounds, currentTheme(d))
    else:
      drawBlock(p, element.bounds, ui.theme.panel1)
    let baseY = (element.bounds.t + element.bounds.b) div 2
    # Paint outer-to-inner so center overlaps neighbors cleanly.
    for off in [-2, 2, -1, 1, 0]:
      paintSlot(p, d, off, element.bounds, baseY)
    # Footer hint along the bottom. ASCII only — luigi's bundled font lacks
    # arrow/middle-dot glyphs and renders missing chars as ?-tofu. Kept short
    # to fit a 480px window; focus-on-reload caveat documented in README.
    let hint = "Up/Dn rotate    Ctrl+R rescan"
    let fr = Rectangle(l: element.bounds.l, r: element.bounds.r,
                       t: element.bounds.b - 20, b: element.bounds.b - 4)
    drawString(p, fr, hint.cstring, hint.len, ui.theme.textDisabled,
               cint(ALIGN_CENTER), nil)
    return 1

  elif message == msgKeyTyped:
    let k = cast[ptr KeyTyped](dp)
    let w = element.window
    let ctrl  = (w != nil and w.ctrl)
    let code = k.code

    if ctrl and code == KEYCODE_LETTER('R'):
      if d.onRescan != nil: d.onRescan()
      elementRepaint(element, nil)
      return 1

    if code == int(KEYCODE_DOWN) or code == KEYCODE_LETTER('J'):
      rotate(d, +1); return 1
    if code == int(KEYCODE_UP) or code == KEYCODE_LETTER('K'):
      rotate(d, -1); return 1
    if code == int(KEYCODE_ENTER):
      # No-op; selection is already applied on each rotation.
      return 1
    return 0

  elif message == msgMouseWheel:
    # luigi convention: di > 0 = wheel up. Wheel up = previous theme.
    if di > 0:    rotate(d, -1)
    elif di < 0:  rotate(d, +1)
    return 1

  elif message == msgLeftDown:
    elementFocus(element)
    let w = element.window
    if w != nil:
      let off = slotIndexAtY(d, element.bounds, w.cursorY)
      if off != 999 and off != 0:
        rotate(d, off)
    return 1

  return 0

proc drumCreate*(parent: ptr Element; themes: ref seq[Palette];
                 onChange: OnChangeProc; onRescan: RescanProc): ptr Drum =
  let e = elementCreate(csize_t(sizeof(Drum)), parent,
                        ELEMENT_V_FILL or ELEMENT_H_FILL or ELEMENT_TAB_STOP,
                        drumMessage, "ThrawkDrum")
  let d = cast[ptr Drum](e)
  d.themes = themes
  d.centerIdx = 0
  d.onChange = onChange
  d.onRescan = onRescan
  d
