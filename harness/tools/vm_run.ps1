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
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ THE PARSER ARM HAS ITS OWN TITLE SET, AND IT IS DECLARED HERE RATHER THAN TYPED.
# T-P0-060's AC-4 ran three titles and the choice lived on a command line -- which is the exact
# defect the block above is about, freshly minted one task later: "the scope of a gate is part of
# its definition and it kept living in an environment variable."
# ★★★★ WHY THESE THREE AND NOT THE NINE. Kingquest3 is EXCLUDED and the reason is a measurement:
# fed a line, the REFERENCE raises on `restart.game`, which dispatch.py declines to implement
# because it re-enters the whole game loop and would silently restart the state diff mid-run.
# Kingquest1 also reaches `save.game` ($7D) and `restore.game` ($7E) on other lines.
# ★★★ **Without input an AGI game sits in attract mode and never takes those branches**, so the
# nine-title gate has never executed them. The parser is the door to a part of the command space
# no gate has covered -- an open item (T-P0-060 §7.4), not a reason to hide the titles.
# ★★ The remaining five are simply not yet measured with input; widening this list is T-P0-060
# §8.5 and should be done by RUNNING them, not by assuming they behave like these three.
$VM_PARSER_TITLES = @("Kingquest1","Kingquest2","SpaceQuest-1")
$TITLES = if ($env:VM_TITLES) { $env:VM_TITLES -split "," }
          elseif ($env:VM_INPUT) { $VM_PARSER_TITLES }
          else { $VM_GATE_TITLES }
if ($env:VM_INPUT -and -not $env:VM_TITLES) {
  "★ parser arm: $($VM_PARSER_TITLES -join ', ')  (Kingquest3 excluded -- the reference raises on restart.game when fed)"
}
$CYCLES = if ($env:VM_CYCLES) { $env:VM_CYCLES } else { "600" }

$ASMARGS = @("--format=raw","--output=build/vm_probe.bin","--list=build/vm_probe.lst",
             "--map=build/vm_probe.map","-I.","-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK")
if ($env:VM_TRACE) { $ASMARGS += "-DVM_TRACE" }
# ★★ AC-3: build with a deliberate one-boundary error in vm_check_step, to show the gate can
# fail. A gate that has never failed is an assertion about the harness, not about the VM.
if ($env:VM_FAULT) { $ASMARGS += "-DVM_FAULT"; "FAULT INJECTED (-DVM_FAULT) -- this build is EXPECTED to fail AC-2" }
if ($env:VM_PACEONLY) { $ASMARGS += "-DVM_PACEONLY"; "PACE-ONLY build (AC-7 split): interpret_cycle is not called" }
# ★★★★ T-P0-060 AC-5: the WIRING's own fault. said() evaluated but its side effect not published,
# so every later said() in the same cycle passes a guard that should have rejected it. This
# build is EXPECTED to fail the state diff on any title whose script makes a line match.
if ($env:VM_FAULT_SAID_PURE) { $ASMARGS += "-DVM_FAULT_SAID_PURE"; "★★★ FAULT INJECTED (-DVM_FAULT_SAID_PURE): said() treated as PURE -- this build is EXPECTED to FAIL" }
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
          "vm_exitall","vm_quit","res_err","vm_curlogic","vm_badop","vm_badlogic","vm_seed","vm_acc","vm_rndmax","vm_rndlo","vm_divisor","vm_gfxmode",
          # ★★★ T-P0-060: the parser's own addresses. par_vocab is what makes the port live;
          # the three counters are the wiring's coverage. From the MAP, never a literal.
          "par_vocab","vm_saidn","vm_saidm","vm_fedn")
if ($env:VM_TRACE) { $WANT += @("vmtr_buf","vmtr_idx","vmtr_from","vmtr_logic","vmtr_seen") }
python harness\tools\vm_symbols.py build\vm_probe.map --out build\vm_stage\symbols.txt --want @WANT
if ($LASTEXITCODE -ne 0) { throw "symbols missing" }

$summary = @()
foreach ($t in $TITLES) {
  $stage = "build\vm_stage\$t"
  $sweep = "build\vm_sweep\$t"
  New-Item -ItemType Directory -Force $stage, $sweep | Out-Null

  # ═══════════════════════════════════════════════════════════════════════════════════════
  # ★★★★ T-P0-060 AC-4: THE SCRIPTED INPUT ARM. VM_INPUT=1 derives a script from THIS title's
  # own said() census, stages it, and feeds both legs from it. Unset, nothing here changes and
  # the nine-title gate runs exactly as before -- which is the arm L-79 requires to exist.
  # ★★★ The script is REGENERATED per run rather than kept beside the fixture: a script file
  # that outlives the game or the reference is the stale-symbols defect wearing a new hat
  # [P1.3, P6.3 §3.F.2]. It costs one reference run, which vm_stage.py does anyway.
  # ★★ Stale scripts from a previous title/run are removed first [L-92, §2W.2]: input.txt and
  # words.tok are what make the parser live, and one left behind would feed the WRONG game's
  # words into this one -- a divergence that points at parser.s.
  Remove-Item -Force -ErrorAction SilentlyContinue "$stage\input.txt", "$stage\words.tok"
  $stageArgs = @((Join-Path $GAMES $t), "--out", $stage, "--cycles", $CYCLES)
  if ($env:VM_INPUT) {
    python harness\tools\vm_input_script.py (Join-Path $GAMES $t) --out "$stage\input.gen.txt" --cycles $CYCLES
    if ($LASTEXITCODE -ne 0) { "★★★ $t : no verified input lines -- running WITHOUT input"; }
    else { $stageArgs += @("--input", "$stage\input.gen.txt") }
  }
  python harness\tools\vm_stage.py @stageArgs | Out-Null
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
