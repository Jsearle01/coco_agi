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
# ★★★★★ VM_OBJ_SCAN IS RETIRED [P6.11]. It was P6.10's ablation knob and the loops no longer read
# it -- they are bounded by vm_objtop, which the interpreter maintains. ★★★★ It is REMOVED rather
# than left inert: a build flag that silently does nothing is the defect class this project has
# now found eight times, and this one would have been passed on a command line and believed.
# ★★ To reproduce P6.10's ablation, build that revision.
if ($env:VM_OBJ_SCAN) { throw "VM_OBJ_SCAN is retired (P6.11): the loops are bounded by vm_objtop. Build the P6.10 revision to reproduce that ablation." }
# ★★★★★ P6.11 AC-7: the object census. Records the highest slot ever seen ACTIVE, per title, in
# the GUEST and on the loop the bound governs. Measurement only -- the gate build is unchanged.
if ($env:VM_OBJCENSUS) { $ASMARGS += "-DVM_OBJCENSUS"; "★ OBJECT CENSUS (-DVM_OBJCENSUS): reporting the highest ACTIVE slot per title" }
# ★★★★★ P6.11 AC-4: THE BOUND'S FAULT. Disables the RAISING of vm_objtop (it does not clamp the
# value -- clamping would not stick, because the first vm_objflags_set would lift it again and the
# fault build would behave like the good one). The mark stays at slot 0, so the PREDICTION IS
# SPECIFIC: Kingquest1 and PoliceQuest1, whose census max is 0, must still PASS; the other seven
# must FAIL. ★★★ A bound that cannot be broken has not been tested [L-62, §2W].
if ($env:VM_OBJBOUND_FAULT) { $ASMARGS += "-DVM_OBJBOUND_FAULT"; "★★★ BOUND FAULT INJECTED (-DVM_OBJBOUND_FAULT): vm_objtop never rises -- 7 of 9 titles are EXPECTED to FAIL" }
# ★★★★★ P6.11 AC-5: the TIGHT bound. Raises vm_objtop only when a flag write leaves the object
# ACTIVE, instead of on any flag write at all. ★★★★ Measured reason it exists: the conservative
# hook pins the mark at slot 255 in Kingquest1's attract mode -- zero active objects, and the whole
# gain lost -- because something there writes flags on a high slot. Rooms 1/2 sit at 13, room 3 at
# 3. ★★★ It must earn the same 9/9 the conservative default already has before it can replace it.
if ($env:VM_OBJBOUND_TIGHT) { throw "VM_OBJBOUND_TIGHT is retired (P6.11): raising only on ACTIVE-making writes is now the shipped default, gate-proven 9/9. There is no loose variant to select." }
# ★★★★★ P6.12 AC-8: the fault for the VMOP_MODELLED_LO branch. The corpus executes exactly ONE of
# the 14 opcodes that branch serves (AD, once), so a passing gate is nearly no evidence about it
# [L-86]. This drops the boundary to $A0 -- executed 8 times, with a real handler -- so the misroute
# is something the diff can see. EXPECTED to FAIL.
if ($env:VM_MODELLED_FAULT) { $ASMARGS += "-DVM_MODELLED_FAULT"; "★★★ FAULT INJECTED (-DVM_MODELLED_FAULT): VMOP_MODELLED_LO dropped to \$A0 -- this build is EXPECTED to FAIL" }
# ★★★★★ THE VBL CLOCK ARM [Jay's ruling AD-138]. VM_VBLCLOCK=1 runs VAR_SECONDS off the CoCo3's
# real 59.92 Hz vertical-sync interrupt instead of the cycle-derived virtual counter. Unset,
# nothing changes and the nine-title gate is HEAD's gate exactly -- which is the arm L-79 requires
# to exist, and the reason the default is off is that the arm currently CRASHES the probe before
# its first park (see vm_probe.s at the ifdef). ★★★ The clock SOURCE is not in doubt:
# vbl_probe.s takes 300 of 300 VBLs at 59.9227 Hz with CC.I at 0.0%.
if ($env:VM_VBLCLOCK) { $ASMARGS += "-DVM_VBLCLOCK"; "★★★ VBL CLOCK ARM (-DVM_VBLCLOCK): VAR_SECONDS runs off real vertical sync -- known to crash before the first park" }
# ★★ AC-3: build with a deliberate one-boundary error in vm_check_step, to show the gate can
# fail. A gate that has never failed is an assertion about the harness, not about the VM.
if ($env:VM_FAULT) { $ASMARGS += "-DVM_FAULT"; "FAULT INJECTED (-DVM_FAULT) -- this build is EXPECTED to fail AC-2" }
if ($env:VM_PACEONLY) { $ASMARGS += "-DVM_PACEONLY"; "PACE-ONLY build (AC-7 split): interpret_cycle is not called" }
# ★★★★ T-P0-060 AC-5: the WIRING's own fault. said() evaluated but its side effect not published,
# so every later said() in the same cycle passes a guard that should have rejected it. This
# build is EXPECTED to fail the state diff on any title whose script makes a line match.
if ($env:VM_FAULT_SAID_PURE) { $ASMARGS += "-DVM_FAULT_SAID_PURE"; "★★★ FAULT INJECTED (-DVM_FAULT_SAID_PURE): said() treated as PURE -- this build is EXPECTED to FAIL" }
# ★★★★★ VM_PROG_PREBUILT -- run a binary this script did NOT assemble [P6.11 AC-5]. The gain has
# to be measured against a build of the PREVIOUS REVISION, because the knob that used to express
# the before-state is retired: the loops read vm_objtop now, so "before" is a different program,
# not a different flag. ★★★★ Its map must come with it, because symbols move between revisions and
# a stale symbol file is the P1.3 defect exactly -- vm_symbols.py reads the map named here.
# ★★★ It refuses a binary older than its map rather than guessing, and it prints what it is running
# so no report can quote a figure without saying which build produced it.
if ($env:VM_PROG_PREBUILT) {
    if (-not (Test-Path $env:VM_PROG_PREBUILT)) { throw "VM_PROG_PREBUILT not found: $($env:VM_PROG_PREBUILT)" }
    $preMap = "$($env:VM_PROG_PREBUILT).map"
    if (-not (Test-Path $preMap)) { throw "VM_PROG_PREBUILT needs its map beside it: $preMap" }
    Copy-Item $env:VM_PROG_PREBUILT build\vm_probe.bin -Force
    Copy-Item $preMap               build\vm_probe.map -Force
    "★ PREBUILT: $($env:VM_PROG_PREBUILT) ($((Get-Item build\vm_probe.bin).Length) bytes) -- NOT assembled by this script"
} else {
& C:\WIN_LWTools\lwasm.exe @ASMARGS src/harness/vm_probe.s
if ($LASTEXITCODE -ne 0) { throw "assemble failed" }
"vm_probe: $((Get-Item build\vm_probe.bin).Length) bytes"
}
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
          "par_vocab","vm_saidn","vm_saidm","vm_fedn",
          # ★★★★★ P6.10 AC-3: the MEASURED object count. vm_update_objs increments vm_changecnt
          # once per ACTIVE object every cycle, so it is the scaling curve's x-axis -- and reading
          # it is what stops "room 1 has four objects" being an assumption carried into a graph.
          "vm_changecnt")
# ★★★★★ P6.11 AC-7: the census pointer, REQUESTED ONLY ON THE CENSUS ARM. vm_symbols.py treats a
# missing want as fatal, so listing it unconditionally broke the AC-5 before-arm -- a build of an
# earlier revision that predates the symbol. ★★★ That is the right failure (a symbol file must
# match its binary [P1.3]) and the wrong request: a symbol that exists only under a build flag
# belongs behind the same flag.
if ($env:VM_OBJCENSUS) { $WANT += "vm_objhighp" }
# ★★★★★ P6.11 AC-5: the bound itself, so the gain can be explained by the mark rather than by a
# story about it. Absent from the AC-5 before-arm, which predates it, so it is requested only when
# the build defines it -- gate_audit's --hash is not a substitute for asking the map.
if (Test-Path build\vm_probe.map) { if (Select-String -Path build\vm_probe.map -Pattern "Symbol: vm_objtop " -Quiet) { $WANT += "vm_objtop" } }
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
