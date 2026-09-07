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
# ★★★★★ IT IS NOW THE SAME NINE [T-P0-061 AC-9]. T-P0-060 ran three because Kingquest3 was
# BLOCKED: fed a line it reaches `restart.game`, which dispatch.py raised on. AC-8 implemented
# that opcode from the oracle -- it sets RESTART_GAME and signals; the outer loop is what
# restarts, and this VM halts there rather than re-initialising mid-diff -- so the block is gone.
# `save.game` and `restore.game`, which Kingquest1 reaches, are modelled as the CANCELLED dialog,
# which is a real AGI path and observably nothing.
# ★★★★ THE ARM AND THE GATE NOW COVER THE SAME CORPUS, which is what makes "the parser changes
# nothing it should not" a claim about the whole gated set rather than a third of it.
# ★★★ **Without input an AGI game sits in attract mode and never takes those branches**, so the
# no-input gate had never executed any of the three. The parser is the door to that part of the
# command space [T-P0-060 §7.4], and AC-9 is the first run that walks through it on every title.
$VM_PARSER_TITLES = $VM_GATE_TITLES
$TITLES = if ($env:VM_TITLES) { $env:VM_TITLES -split "," }
          elseif ($env:VM_INPUT) { $VM_PARSER_TITLES }
          else { $VM_GATE_TITLES }
if ($env:VM_INPUT -and -not $env:VM_TITLES) {
  "★ parser arm: all $($VM_PARSER_TITLES.Count) gate titles (T-P0-061 AC-9; Kingquest3 unblocked by AC-8's restart.game)"
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
  $fed = $false
  if ($env:VM_INPUT) {
    python harness\tools\vm_input_script.py (Join-Path $GAMES $t) --out "$stage\input.gen.txt" --cycles $CYCLES
    if ($LASTEXITCODE -ne 0) { "★★★ $t : no verified input lines -- running WITHOUT input"; }
    else { $stageArgs += @("--input", "$stage\input.gen.txt"); $fed = $true }
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
  $summary += [pscustomobject]@{ title = $t; exit = $code; fed = $fed }
  ""
}

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ THE SUMMARY MUST SAY WHICH TITLES WERE ACTUALLY FED [T-P0-061 AC-9].
# The parser arm's first nine-title run printed nine PASSes. **Six titles were fed and three
# were not** -- SpaceQuest-2's candidates all reach get.string, and BlackCauldron and
# MixedUpMotherGoose call said() ZERO times in the gated window, so all three fell back to the
# no-input path and their traces are bit-identical to the plain gate's.
# ★★★★ Nine PASSes for a six-title arm is res_aggregate.py's defect exactly -- "100% of a
# smaller number" -- reproduced in the AC that was written to widen coverage, in the same task
# that fixed it elsewhere. **A gate must report the corpus it actually covered** [L-85].
# ★★★ NOT-FED is not a failure and is not hidden: it is a fact about the TITLE, and for two of
# the three it is the strongest fact available -- a v2 game whose first 600 cycles never test
# the parser cannot be covered by any input script.
"=== AC-2 SUMMARY ==="
$summary | ForEach-Object {
  "{0,-20} {1,-5} {2}" -f $_.title,
    $(if ($_.exit -eq 0) { "PASS" } else { "FAIL" }),
    $(if ($env:VM_INPUT) { if ($_.fed) { "input fed" } else { "★ NO INPUT -- not covered by this arm" } } else { "" })
}
if ($env:VM_INPUT) {
  $nf = ($summary | Where-Object { -not $_.fed }).Count
  "";  "★ parser arm covered {0} of {1} titles with input; {2} ran without and are the plain gate." -f ($summary.Count - $nf), $summary.Count, $nf
}
