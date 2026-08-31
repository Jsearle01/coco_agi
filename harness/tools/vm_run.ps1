# harness/tools/vm_run.ps1 -- AC-2: build the VM probe, stage each title, sweep, diff.
#
# ★ One MAME launch per title. Symbols come from the LISTING, into build/vm_stage/symbols.txt,
# and vm_sweep.lua reads them from there -- never from a copy beside a fixture (§2F; P1.3 lost
# a session to a stale one).
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$GAMES  = if ($env:VM_GAMES_ROOT) { $env:VM_GAMES_ROOT } else { "C:\Projects\agi-games\pc" }
$CFG    = if ($env:VM_MAME_CFG)   { $env:VM_MAME_CFG }   else { "harness\mame-cfg" }
# ★★★★ THE DEFAULT WAS THREE TITLES AND THE GATE IS NINE. "the VM gate, nine titles" is cited by
# that name across reports, and the nine were supplied through $env:VM_TITLES from a command line
# that exists in no file -- so running the recorded script reproduced a THIRD of the gate and
# printed "=== AC-2 SUMMARY === 3 PASS", which reads exactly like a pass.
# ★★★ Fourth instance of one disease in this audit (res 74-vs-1,264, cel 1-title-vs-6, pic sweep
# without picgate, this). **The scope of a gate is part of its definition and it kept living in
# an environment variable.** Now it is the default, and VM_TITLES narrows it for a spot-check
# rather than being required to widen it to the real thing.
# ★★ THE NINE, RECOVERED BY STAGING EVERY TITLE IN THE GAME DIR AND KEEPING THE ONES THAT ARE v2.
# Kingquest4, GoldRush and ManhunterNewYork all fail staging with "detected unknown; v2 only this
# phase" (design §11.1) -- they are v3 and are NOT gate titles. MixedUpMotherGoose is v2 and is
# the ninth. ★ This is a §2Q binding ("the game set is pinned, not a preference") that was living
# in an environment variable; it is evidence now, not memory.
$VM_GATE_TITLES = @("Kingquest1","Kingquest2","Kingquest3",
                    "SpaceQuest-1","SpaceQuest-2","PoliceQuest1",
                    "larry1","BlackCauldron","MixedUpMotherGoose")
$TITLES = if ($env:VM_TITLES) { $env:VM_TITLES -split "," } else { $VM_GATE_TITLES }
$CYCLES = if ($env:VM_CYCLES) { $env:VM_CYCLES } else { "600" }

$ASMARGS = @("--format=raw","--output=build/vm_probe.bin","--list=build/vm_probe.lst",
             "--map=build/vm_probe.map","-I.","-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK")
if ($env:VM_TRACE) { $ASMARGS += "-DVM_TRACE" }
# ★★ AC-3: build with a deliberate one-boundary error in vm_check_step, to show the gate can
# fail. A gate that has never failed is an assertion about the harness, not about the VM.
if ($env:VM_FAULT) { $ASMARGS += "-DVM_FAULT"; "FAULT INJECTED (-DVM_FAULT) -- this build is EXPECTED to fail AC-2" }
if ($env:VM_PACEONLY) { $ASMARGS += "-DVM_PACEONLY"; "PACE-ONLY build (AC-7 split): interpret_cycle is not called" }
& C:\WIN_LWTools\lwasm.exe @ASMARGS src/harness/vm_probe.s
if ($LASTEXITCODE -ne 0) { throw "assemble failed" }
"vm_probe: $((Get-Item build\vm_probe.bin).Length) bytes"
# ★★ AC-3's stamp -- see res_run.ps1. vm_load.ps1 deliberately does NOT build (concurrent MAME
# instances would race on this file), so it checks staleness instead; this is the producer whose
# identity that check is against.
"  [source-tree $(& python harness\tools\gate_audit.py --hash src/harness/vm_probe.s)]"

New-Item -ItemType Directory -Force build\vm_stage | Out-Null
# ★★★ SYMBOLS COME FROM lwasm's --map, NEVER from the listing. The listing scrape matched an
# instruction whose COMMENT named the symbol and returned res_volbase = $2156 against a real
# $2170; every fetch then failed its signature check and the symptom pointed at the resource
# layer rather than at the scraper. vm_symbols.py reads the symbol table itself.
"symbols:"
$WANT = @("res_volbase","res_slicebase","res_curblk","vm_icguard","res_depth","res_top",
          "vm_exitall","vm_quit","res_err","vm_curlogic","vm_badop","vm_badlogic","vm_seed","vm_acc","vm_rndmax","vm_rndlo","vm_divisor","vm_gfxmode")
if ($env:VM_TRACE) { $WANT += @("vmtr_buf","vmtr_idx","vmtr_from","vmtr_logic","vmtr_seen") }
python harness\tools\vm_symbols.py build\vm_probe.map --out build\vm_stage\symbols.txt --want @WANT
if ($LASTEXITCODE -ne 0) { throw "symbols missing" }

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
