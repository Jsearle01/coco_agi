# harness/tools/res_run.ps1 -- AC-2's sweep: every volume of every pinned title, on the 6809.
#
# One MAME launch per (title, volume): the whole volume is staged into physical blocks 8..63 and
# every resource the DIR tables place inside it is fetched and diffed against tools/volread/.
#
# ★★ 512 KB IS THE TARGET MACHINE (CLAUDE.md 2K), and it is also what makes whole-volume staging
# possible: 64 blocks less the 8 the CPU map occupies leaves 458,752 bytes, against a largest
# volume of 247,952. ★ The staging budget is a HARNESS property, not the interpreter's -- the
# shipped path streams from disk and holds one 8 KB window, which is what AC-8 measures.
#
# ★ 2P: everything written lands under build/, which is not tracked.
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$GAMES  = if ($env:RES_GAMES_ROOT) { $env:RES_GAMES_ROOT } else { "C:\Projects\agi-games\pc" }
$CFG    = if ($env:RES_MAME_CFG)   { $env:RES_MAME_CFG }   else { "harness\mame-cfg" }
$TITLES = @("Kingquest1", "Kingquest2", "Kingquest3")
$BLOCKS = 56          # physical blocks 8..63 on a 512 KB machine
$VOLBASE= 8

$summary = @()
foreach ($t in $TITLES) {
  $vols = Get-ChildItem (Join-Path $GAMES $t) -Filter "vol.*" | ForEach-Object {
            [int]($_.Name -replace '^vol\.', '') } | Sort-Object
  foreach ($v in $vols) {
    $tag   = "$t-v$v"
    $stage = "build\res_stage\$tag"
    $out   = "build\res_sweep\$tag"
    # ★ No symbols.txt copy here: res_sweep.lua reads it from the build (§2F, one home per fact).
    # A per-stage copy went stale the moment the probe was rebuilt and poked res_volbase at the
    # wrong address, which presents as bad-signature on every fetch rather than as a stale file.
    New-Item -ItemType Directory -Force $stage, $out | Out-Null

    python harness\tools\res_stage.py (Join-Path $GAMES $t) --out $stage `
        --volume $v --blocks $BLOCKS --volbase $VOLBASE | Out-Null

    $env:RES_OUT = $out; $env:RES_STAGE = $stage; $env:RES_PROG = "build\res_probe.bin"
    # ★ -video none: this loop launches MAME ten times unattended and a window per launch
    # takes over the desktop. Nothing here is a 25.3 gate -- the gate runs windowed, by Jay.
    C:\mame\mame.exe coco3 -video none -seconds_to_run 3000 -skip_gameinfo -nothrottle `
      -rompath C:/mame/roms -cfg_directory $CFG `
      -autoboot_script C:/Projects/coco_agi/harness/tools/res_sweep.lua -autoboot_delay 0 | Out-Null

    $g = python harness\tools\res_gate.py (Join-Path $GAMES $t) --sweep $out 2>&1
    $code = $LASTEXITCODE
    $ok   = ($g | Select-String "byte-identical") -replace '.*: *', ''
    $bad  = ($g | Select-String "^mismatched")
    "$tag  ok=$ok  $bad  exit=$code"
    $summary += [pscustomobject]@{ tag = $tag; ok = [int]$ok; exit = $code; text = ($g -join "`n") }
  }
}

"";"=== TOTAL ==="
$tot = ($summary | Measure-Object ok -Sum).Sum
$fail = @($summary | Where-Object { $_.exit -ne 0 })
"byte-identical resources: $tot across $($summary.Count) (title, volume) sweeps"
if ($fail.Count) { "FAILING SWEEPS:"; $fail | ForEach-Object { $_.text } } else { "all sweeps clean" }
$summary | Select-Object tag, ok, exit | Format-Table | Out-String | Set-Content -Encoding utf8 "build\res_sweep\summary.txt"
