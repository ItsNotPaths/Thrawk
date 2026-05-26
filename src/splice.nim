## Shared marker-block splice helpers. Every Thrawk emitter that edits a
## user-owned config uses the same `# THRAWK:BEGIN`/`# THRAWK:END` markers
## and the same atomic write strategy; per-app modules just supply the
## content of the block between markers.

import std/[strutils, os]

const
  beginMarker* = "# THRAWK:BEGIN  (managed by Thrawk — do not edit; regenerated on theme change)"
  endMarker*   = "# THRAWK:END"

type SpliceError* = enum
  spOk, spMissingMarkers, spOnlyOneMarker, spOutOfOrder, spIoError, spNoConfig

proc atomicWrite*(path, content: string): bool =
  ## Write to path.tmp then rename. Creates parent dirs as needed.
  let tmp = path & ".tmp"
  try:
    createDir(parentDir(path))
    writeFile(tmp, content)
    moveFile(tmp, path)
    return true
  except OSError, IOError:
    try: removeFile(tmp) except: discard
    return false

proc findRegion*(content: string): tuple[ok: SpliceError, b, e: int] =
  ## Returns byte offsets of the BEGIN line start and the END line start.
  let bi = content.find("# THRAWK:BEGIN")
  let ei = content.find("# THRAWK:END")
  if bi < 0 and ei < 0: return (spMissingMarkers, -1, -1)
  if bi < 0 or ei < 0:  return (spOnlyOneMarker, -1, -1)
  if ei < bi:           return (spOutOfOrder, -1, -1)
  (spOk, bi, ei)

proc spliceMarkerBlock*(configPath, blockContent: string): SpliceError =
  ## Atomically replaces the existing THRAWK region in configPath with
  ## blockContent. blockContent must include both marker lines.
  if not fileExists(configPath): return spNoConfig
  var body: string
  try: body = readFile(configPath)
  except IOError: return spIoError
  let (ok, b, e) = findRegion(body)
  if ok != spOk: return ok
  var eEnd = e
  while eEnd < body.len and body[eEnd] != '\n': inc eEnd
  if eEnd < body.len: inc eEnd
  let newBody = body[0 ..< b] & blockContent & body[eEnd .. ^1]
  if not atomicWrite(configPath, newBody): return spIoError
  spOk

proc errorMessage*(e: SpliceError, app: string): string =
  case e
  of spOk:             ""
  of spMissingMarkers: "no THRAWK markers in " & app & " config — run `Thrawk --init-" & app & "` first"
  of spOnlyOneMarker:  app & " config has only one THRAWK marker (corrupted state — refusing to splice)"
  of spOutOfOrder:     app & " config THRAWK markers are out of order"
  of spIoError:        "could not read/write " & app & " config"
  of spNoConfig:       app & " config not found (skipped)"

proc hex6*(c: uint32): string = "#" & toHex(BiggestInt(c), 6).toLowerAscii
