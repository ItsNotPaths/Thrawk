## Standalone verifier — no wayluigi dependency. Loads pathsgruv.theme,
## prints the marker block, bootstraps a sandboxed copy of the live sway
## config, and prints a diff. Run with:
##   nim c -r --path:src tests/verify_sway.nim
import std/[os, strutils, osproc, options]
import ../src/theme, ../src/emit_sway, ../src/init_sway

const sandbox = "/tmp/thrawk-verify"

proc main() =
  let repoRoot = currentSourcePath().parentDir.parentDir
  let themesDir = repoRoot / "themes"
  let liveSway  = getHomeDir() / ".config" / "sway" / "config"

  echo "=== loading pathsgruv.theme ==="
  let pOpt = loadPaletteFile(themesDir / "pathsgruv.theme")
  if pOpt.isNone:
    quit "FAIL: could not load pathsgruv.theme", 1
  let p = pOpt.get()
  echo "name=", p.name, " source=", p.source
  echo "bg=", toHex(BiggestInt(p.bg), 6), " accent=", toHex(BiggestInt(p.accent), 6)

  echo "\n=== marker block (genMarkerBlock) ==="
  echo genMarkerBlock(p)

  echo "=== bootstrap dry-run against ", liveSway, " ==="
  if not fileExists(liveSway):
    quit "FAIL: live sway config not found", 1
  removeDir(sandbox)
  createDir(sandbox)
  let copy = sandbox / "config"
  copyFile(liveSway, copy)
  let res = initSwayConfig(copy, p)
  if not res.ok:
    quit "FAIL: initSwayConfig: " & res.message, 1
  echo "ok; backup=", res.backupPath

  echo "\n=== diff (live -> rewritten) ==="
  let (dout, _) = execCmdEx("diff -u " & liveSway & " " & copy)
  echo dout

  echo "\n=== second init (should refuse) ==="
  let res2 = initSwayConfig(copy, p)
  echo "ok=", res2.ok, " msg=", res2.message

  echo "\n=== splice with gruvbox-material (should swap accent) ==="
  let p2 = loadPaletteFile(themesDir / "gruvbox-material.theme").get()
  let sp = spliceBlock(copy, p2)
  echo "splice=", sp
  let (gout, _) = execCmdEx("grep '$tw_accent ' " & copy)
  echo gout

when isMainModule: main()
