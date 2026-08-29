# harness/tools/vm_run.ps1 -- AC-2: build the VM probe, stage each title, sweep, diff.
#
# ★ One MAME launch per title. Symbols come from the LISTING, into build/vm_stage/symbols.txt,
# and vm_sweep.lua reads them from there -- never from a copy beside a fixture (§2F; P1.3 lost
# a session to a stale one).
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$GAMES  = if ($env:VM_GAMES_ROOT) { $env:VM_GAMES_ROOT } else { "C:\Projects\agi-games\pc" }
$CFG    = if ($env:VM_MAME_CFG)   { $env:VM_MAME_CFG }   else { "harness\mame-cfg" }
$TITLES = if ($env:VM_TITLES) { $env:VM_TITLES -split "," } else { @("Kingquest1","Kingquest2","Kingquest3") }
$CYCLES = if ($env:VM_CYCLES) { $env:VM_CYCLES } else { "600" }

& C:\WIN_LWTools\lwasm.exe --format=raw --output=build/vm_probe.bin --list=build/vm_probe.lst `
    -I. -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK src/harness/vm_probe.s
if ($LASTEXITCODE -ne 0) { throw "assemble failed" }
"vm_probe: $((Get-Item build\vm_probe.bin).Length) bytes"

New-Item -ItemType Directory -Force build\vm_stage | Out-Null
$want = @("res_volbase","res_slicebase","res_curblk")
$lines = Get-Content build\vm_probe.lst
$out = @()
foreach ($w in $want) {
  $m = $lines | Where-Object { $_ -match "^([0-9A-F]{4})\s" -and $_ -match "\b$([regex]::Escape($w))\b" } | Select-Object -First 1
  if ($m -and $m -match "^([0-9A-F]{4})\s") { $out += "$w $($Matches[1])" } else { "  ! $w not found" }
}
$out | Set-Content -Encoding ascii "build\vm_stage\symbols.txt"
"symbols:"; $out | ForEach-Object { "   $_" }

$summary = @()
foreach ($t in $TITLES) {
  $stage = "build\vm_stage\$t"
  $sweep = "build\vm_sweep\$t"
  New-Item -ItemType Directory -Force $stage, $sweep | Out-Null

  python harness\tools\vm_stage.py (Join-Path $GAMES $t) --out $stage --cycles $CYCLES | Out-Null
  if ($LASTEXITCODE -ne 0) { "★★★ $t : staging did not fit"; continue }

  $env:VM_OUT = $sweep; $env:VM_STAGE = $stage; $env:VM_PROG = "build\vm_probe.bin"
  $env:VM_CYCLES = $CYCLES; $env:VM_SYMBOLS = "build\vm_stage\symbols.txt"
  # ★ -video none: nothing here is a 25.3 gate, and ten unattended launches should not take
  # over the desktop (the P1.3 lesson, applied without being told twice).
  C:\mame\mame.exe coco3 -video none -seconds_to_run 100000 -skip_gameinfo -nothrottle `
    -rompath C:/mame/roms -cfg_directory $CFG `
    -autoboot_script C:/Projects/coco_agi/harness/tools/vm_sweep.lua -autoboot_delay 0 | Out-Null

  $d = python harness\tools\vm_diff.py --oracle "$stage\oracle.bin" --guest "$sweep\guest.bin" --title $t 2>&1
  $code = $LASTEXITCODE
  $d | Select-Object -Last 22
  $summary += [pscustomobject]@{ title = $t; exit = $code }
  ""
}

"=== AC-2 SUMMARY ==="
$summary | ForEach-Object { "{0,-12} {1}" -f $_.title, $(if ($_.exit -eq 0) { "PASS" } else { "FAIL" }) }
