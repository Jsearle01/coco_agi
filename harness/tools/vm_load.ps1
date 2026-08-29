# harness/tools/vm_load.ps1 -- AC-8: is the gate's output deterministic, and is it deterministic
# when several MAME instances run at once?
#
# ★★★ IT DOES NOT BUILD. vm_run.ps1 reassembles vm_probe.bin on every invocation, so launching it
# N times concurrently would have N processes writing one binary while others read it. That is
# the exact shape of the withdrawn probe.dmk measurement in T-P0-024: a hash taken from a tree a
# second build was writing. **This script takes the binary as an input and never writes build/.**
#
# ★★ Each instance gets its own VM_OUT, because vm_sweep.lua writes guest.bin/run.log there and
# two instances sharing a directory would prove nothing except that they collide.
#
# ★ Staging is read-only per title and shared; MAME opens the game files not at all (the host
# reads them in vm_stage.py, which has already run).
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$TITLES = if ($env:VM_TITLES) { $env:VM_TITLES -split "," } else { @("Kingquest1","Kingquest2","Kingquest3") }
$CYCLES = if ($env:VM_CYCLES) { $env:VM_CYCLES } else { "500" }
$TAG    = if ($env:VM_TAG)    { $env:VM_TAG }    else { "load" }
$CFG    = if ($env:VM_MAME_CFG) { $env:VM_MAME_CFG } else { "harness\mame-cfg" }

if (-not (Test-Path build\vm_probe.bin)) { throw "build/vm_probe.bin missing -- run vm_run.ps1 first" }
"using build\vm_probe.bin ($((Get-Item build\vm_probe.bin).Length) bytes), NOT rebuilding"

$jobs = @()
foreach ($t in $TITLES) {
  $sweep = "build\vm_sweep_$TAG\$t"
  New-Item -ItemType Directory -Force $sweep | Out-Null
  $jobs += Start-Job -ScriptBlock {
    param($t, $sweep, $cycles, $cfg)
    Set-Location C:\Projects\coco_agi
    $env:VM_OUT = $sweep
    $env:VM_STAGE = "build\vm_stage\$t"
    $env:VM_PROG = "build\vm_probe.bin"
    $env:VM_CYCLES = $cycles
    $env:VM_SYMBOLS = "build\vm_stage\symbols.txt"
    & C:\mame\mame.exe coco3 -video none -seconds_to_run 100000 -skip_gameinfo -nothrottle `
      -rompath C:/mame/roms -cfg_directory $cfg `
      -autoboot_script C:/Projects/coco_agi/harness/tools/vm_sweep.lua -autoboot_delay 0 | Out-Null
  } -ArgumentList $t, $sweep, $CYCLES, $CFG
}
"launched $($jobs.Count) concurrent MAME instances"
$jobs | Wait-Job | Out-Null
$jobs | Remove-Job

"`n=== AC-8: concurrent vs sequential ==="
foreach ($t in $TITLES) {
  $a = "build\vm_sweep\$t\guest.bin"
  $b = "build\vm_sweep_$TAG\$t\guest.bin"
  if ((Test-Path $a) -and (Test-Path $b)) {
    $ha = (Get-FileHash $a -Algorithm SHA256).Hash.Substring(0,16)
    $hb = (Get-FileHash $b -Algorithm SHA256).Hash.Substring(0,16)
    "{0,-20} sequential {1}  concurrent {2}  {3}" -f $t, $ha, $hb, $(if ($ha -eq $hb) { "IDENTICAL" } else { "*** DIFFER ***" })
  } else {
    "{0,-20} missing output" -f $t
  }
}
