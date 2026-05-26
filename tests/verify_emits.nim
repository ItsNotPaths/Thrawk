## Standalone verifier for the alacritty / helix / qute emitters. No
## wayluigi dependency. Sandboxes each target config in /tmp, runs
## init→splice→re-splice, and prints the resulting files. Run with:
##   nim c -r --path:src tests/verify_emits.nim
import std/[os, strutils, options]
import ../src/theme, ../src/splice
import ../src/emit_alacritty, ../src/emit_helix, ../src/emit_qute

const sandbox = "/tmp/Thrawk-emits"

proc loadFirstTheme(themesDir: string): Palette =
  let pOpt = loadPaletteFile(themesDir / "pathsgruv.theme")
  if pOpt.isNone:
    quit "FAIL: pathsgruv.theme not found in " & themesDir, 1
  pOpt.get()

proc loadSecondTheme(themesDir: string): Palette =
  let pOpt = loadPaletteFile(themesDir / "dracula.theme")
  if pOpt.isNone:
    quit "FAIL: dracula.theme not found in " & themesDir, 1
  pOpt.get()

proc dumpFile(path: string) =
  if not fileExists(path):
    echo "(missing) ", path; return
  echo "─── ", path, " ────────────────────────────────────"
  echo readFile(path)

proc verifyAlacritty(p, p2: Palette, sb: string) =
  echo "\n========== ALACRITTY =========="
  let cfg = sb / "alacritty.toml"
  # Pre-seed with a stub that has [colors.primary] (should be stripped).
  writeFile(cfg, """
[window]
opacity = 0.95

[colors.primary]
background = "#000000"
foreground = "#ffffff"

[font]
size = 10
""")
  echo "--- init (pathsgruv) ---"
  let r = initAlacritty(cfg, p)
  echo "ok=", r.ok, " msg=", r.message, " backup=", r.backupPath
  dumpFile(cfg)
  echo "--- re-splice (dracula) ---"
  let sp = spliceAlacritty(cfg, p2)
  echo "splice=", sp
  dumpFile(cfg)
  echo "--- second init (should refuse) ---"
  let r2 = initAlacritty(cfg, p)
  echo "ok=", r2.ok, " msg=", r2.message

proc verifyHelix(p, p2: Palette, sb: string) =
  echo "\n========== HELIX =========="
  let cfg = sb / "helix-config.toml"
  let theme = sb / "helix-themes" / "thrawk.toml"
  # Pre-seed with a config that has a `theme = "..."` line (should be stripped).
  writeFile(cfg, """
theme = "base16_default_dark"

[editor]
line-number = "relative"
""")
  # Redirect helix paths into sandbox by monkey-patching env: not viable
  # since the emit_helix module uses absolute getHomeDir() paths internally.
  # So we call spliceMarkerBlock / writeFile directly with sandbox paths.
  echo "--- init (pathsgruv) via direct calls ---"
  # initHelix() always writes to ~/.config/helix — for the sandboxed test,
  # just exercise the splice and theme-file generation primitives.
  if not atomicWrite(theme, genHelixTheme(p)):
    echo "FAIL: write theme file"; return
  echo "wrote theme: ", theme
  # Manually strip + append (mimicking initHelix without touching $HOME).
  var body = readFile(cfg)
  # Strip existing top-level theme= line.
  var kept: seq[string]
  for raw in body.splitLines():
    let s = raw.strip()
    if s.startsWith("theme") and s.find('=') > 0 and not s.startsWith("["):
      continue
    kept.add(raw)
  body = kept.join("\n")
  if not body.endsWith("\n"): body.add("\n")
  writeFile(cfg, body & genHelixConfigBlock())
  dumpFile(cfg)
  dumpFile(theme)
  echo "--- re-splice config (dracula) — content same since theme name is constant ---"
  let sp = spliceHelix(cfg)
  echo "splice=", sp
  echo "--- regen theme file (dracula) ---"
  discard atomicWrite(theme, genHelixTheme(p2))
  dumpFile(theme)

proc verifyQute(p, p2: Palette, sb: string) =
  echo "\n========== QUTEBROWSER =========="
  let cfg = sb / "qute-config.py"
  writeFile(cfg, """
config.load_autoconfig()

c.tabs.position = "top"
""")
  echo "--- init (pathsgruv) ---"
  let r = initQute(cfg, p)
  echo "ok=", r.ok, " msg=", r.message, " backup=", r.backupPath
  dumpFile(cfg)
  echo "--- re-splice (dracula) ---"
  let sp = spliceQute(cfg, p2)
  echo "splice=", sp
  dumpFile(cfg)
  echo "--- second init (should refuse) ---"
  let r2 = initQute(cfg, p)
  echo "ok=", r2.ok, " msg=", r2.message

proc main() =
  let repoRoot = currentSourcePath().parentDir.parentDir
  let themesDir = repoRoot / "themes"
  let p  = loadFirstTheme(themesDir)
  let p2 = loadSecondTheme(themesDir)

  removeDir(sandbox)
  createDir(sandbox)
  createDir(sandbox / "helix-themes")

  verifyAlacritty(p, p2, sandbox)
  verifyHelix(p, p2, sandbox)
  verifyQute(p, p2, sandbox)

when isMainModule: main()
