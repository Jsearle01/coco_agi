# harness/tools/p3b_show.ps1 -- §4A's EYE GATE, with a recorded invocation. [T-P0-060 AC-1]
#
# ★★★★★ THIS RUNNER DID NOT EXIST, AND THE EYE GATE IS THE GATE THAT DECIDES DELIVERY.
# p3b_show.lua reads P3B_PROG, P3B_STAGE and P3B_SYMBOLS from the environment, and
# build/p3b/symbols.txt was produced by a hand-typed vm_symbols.py line that is in no file. That
# is the L-45 defect on the one gate whose result is a human's judgement -- and §2U.2 excludes
# this gate from -nothrottle precisely because a person has to watch it, so it is also the gate
# that costs the most to re-run from a guess.
# ★★★ Same disease this project has now named five times (res 74-vs-1,264, cel 1-title-vs-6, pic
# without picgate, the VM's nine titles in an env var, and this). **The scope and the invocation
# of a gate are part of its definition.**
#
# ★★★★ IT DELIBERATELY DOES NOT PASS -nothrottle [§2U.2]. An eye gate nobody can watch at 2869%
# is not an eye gate.
#
# usage:
#   powershell -File harness/tools/p3b_show.ps1 [-Title Kingquest1] [-Cycles 160] [-WithInput]
param(
  [string]$Title  = $(if ($env:P3B_TITLE)  { $env:P3B_TITLE }  else { "Kingquest1" }),
  [int]   $Cycles = $(if ($env:P3B_NCYC)   { [int]$env:P3B_NCYC } else { 120 }),
  # ★ NOT -Input. `$Input` is a PowerShell AUTOMATIC VARIABLE (the pipeline enumerator), so a
  # parameter of that name is bound to a PipelineReader and the script dies on a cast error
  # before it runs a line. Caught by running it, which is the only way this one shows up.
  [switch]$WithInput,
  # ★★★★ -Headless: the SAME build, symbols and staging, driven by p3b_run.lua with no display.
  # ★★★ It shares the whole preamble deliberately (§2F). The eye gate and the headless integration
  # run differ in exactly two things -- which Lua drives it, and whether MAME gets a screen -- and
  # duplicating the build/stage into a second script is how the two would drift into testing
  # different programs. ★★ Headless also gets -nothrottle (§2U); the eye gate never does (§2U.2).
  [switch]$Headless,
  # ★★ The text-gate configuration and its fault arm; see the flag block below.
  [switch]$Text,
  [switch]$Fault,
  [switch]$DecodeFault,
  [switch]$NoTick,
  [double]$Hold   = 3.0
)
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$GAMES = if ($env:VM_GAMES_ROOT) { $env:VM_GAMES_ROOT } else { "C:\Projects\agi-games\pc" }
$stage = "build\vm_stage\$Title"
$LW    = "C:\WIN_LWTools\lwasm.exe"

# ★★ THE FLAG SET IS gates.manifest's p3b ROW, NOT A GUESS. PLANE_WIN_MMU comes from the SOURCE
# (p3b_probe.s:65) and passing it here is a multiply-defined error [gates.manifest].
$FLAGS = @("-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK","-DPLANE_WINDOWED","-DPRI_PACKED")
# ★★★★★ -Text builds the TEXT-GATE configuration [T-P0-084d]: cel/composite stripped so
# MAP_RESERVED can hold src/engine/text.s, and the nine text opcodes wired.
# ★★★★ -Fault adds -DTEXT_MODELLED, which aliases all nine handler labels back to
# vm_op_modelled. **That is AC-2's validator and it is a BUILD, not a reconstruction** -- the
# table entries resolve to the same address the pre-wiring probe used, so a black panel here is
# the behaviour that existed before the wiring rather than an imitation of it [L-113].
# ★★★★ -DHAL_KEYBOARD SELECTS EXISTING HAL CODE; IT IS NOT A HAL CHANGE [T-P0-085c §6]. print now
# blocks until ENTER or ESC, so the text configuration needs HAL_key_scan -- ~318 B [P6.24] into
# 624 of headroom. **It re-baselines p3b_text's binary and gates.manifest records that; `p3b` is
# untouched and gains nothing.**
if ($Text)  { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD") }
if ($Fault) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_MODELLED") }
# ★★★★★ -DecodeFault IS AC-4's ARM AND ITS CONSUMER IS NOW vm_run.s [T-P0-084h]. The decode moved
# off res_open's miss path to the LOGIC bind, so the fault moved with it: -DRES_FAULT_DECODE_HIT
# drops the `bcs vbl_nodec`, and the decode then runs on EVERY bind including cached ones.
# ★★★★ res_decode XORs IN PLACE, so a cached resource is re-encrypted on every re-bind: the first
# bind is right and every later one is garbage. L-66 measured 3.01 binds per cycle.
# ★★★ It exists so the fresh-open placement can be FALSIFIED rather than trusted, and it is RUN in
# both directions: clean 16 of 16 printable (DECODED), fault NOT DECODED [§2W, L-62 -- re-shown on
# the build that shipped].
if ($DecodeFault) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DRES_FAULT_DECODE_HIT") }
# ★★★★★ -NoTick IS AC-8's FAULT ARM AND IT IS ONE OMITTED `jsr vm_step_clock` [§2W.1]. print's wait
# loop measures var 21 as a mark on the GAME clock, exactly as the oracle does [text.cpp:395-409,
# cycle.cpp:558], so a loop that does not tick that clock can never reach the mark and the box hangs
# forever. **The headless watchdog is the instrument under test and it must FIRE** -- a green
# headless run is evidence only once this arm has been seen to go red.
# ★★★★ The arm is 3 bytes smaller than the clean build, which is the `jsr` and nothing else. A fault
# arm that hung by some other route would prove the watchdog works and nothing about this loop.
if ($NoTick) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_FAULT_NOTICK") }
& $LW --format=raw --output=build/p3b_probe_pk_fresh.bin --map=build/p3b_probe_pk.map -I. @FLAGS src/harness/p3b_probe.s
if ($LASTEXITCODE -ne 0) { throw "p3b assemble failed" }
"p3b_probe: $((Get-Item build\p3b_probe_pk_fresh.bin).Length) bytes"
"  [source-tree $(& python harness\tools\gate_audit.py --hash src/harness/p3b_probe.s)]"

# ★★★ SYMBOLS FROM THE BUILD'S MAP. P3_INBUF is an INTERIOR address -- it follows parser.s
# inside MAP_RESERVED and moves whenever either grows -- so p3b_run.lua refuses to stage input
# without it rather than falling back to a literal [P6.3 §3.F.2].
New-Item -ItemType Directory -Force build\p3b | Out-Null
$WANT = @("res_volbase","res_slicebase","res_curblk","vm_quit","vm_badop","vm_cycle","vm_tdelay",
          "res_err","ph_blk_fb","ph_blk_pri","par_vocab","P3_INBUF","P3_FEED","P3_VOCAB_BAD","P3_VOCAB","P3_VOCAB_END","P3_CODE_END","P3_PARSER_BASE","P3_PARSER_TOTAL")
# ★★★ MAP_FONT only exists in the text configuration, and vm_symbols.py fails on a missing name,
# so it is appended rather than added to the list every build shares.
if ($Text -or $Fault -or $DecodeFault -or $NoTick) { $WANT += @("P3_FONT","P3_PBUF") }
# ★★★★ WIRED BUILDS ONLY. -DTEXT_MODELLED keeps TEXT_WIRED undefined (p3b_probe.s:1004), so the nine
# handlers become `equ vm_op_modelled` and **the whole body -- tx_wt_key included -- is never
# assembled**. Asking for it in the -Fault arm fails the symbol extraction, which is why this is a
# second line rather than three more names on the one above.
# ★ vm_vms and vm_passed exist in every build; they are here because only these arms read them.
if ($Text -or $DecodeFault -or $NoTick) { $WANT += @("vm_vms","vm_passed","tx_wt_key") }
python harness\tools\vm_symbols.py build\p3b_probe_pk.map --out build\p3b\symbols.txt --want @WANT
if ($LASTEXITCODE -ne 0) { throw "symbols missing" }

# ★★★★ THE SAME TWO FILES THE BYTE GATE READS. vm_stage.py writes words.tok and input.txt into
# the stage directory from the game and from vm_input_script.py; nothing here synthesises text,
# so what Jay watches and what vm_diff.py compares cannot drift apart (§2O.1, applied to input).
# ★★ Cleared first [L-92]: a script left behind by another title would feed the WRONG game's
# words into this one, and the screen would be wrong for a reason nobody would look for here.
Remove-Item -Force -ErrorAction SilentlyContinue "$stage\input.txt", "$stage\words.tok", "$stage\input.gen.txt"
$stageArgs = @((Join-Path $GAMES $Title), "--out", $stage, "--cycles", "$Cycles")
# ★★★★★ THE STAGE MUST KNOW ABOUT THE JUMP [T-P0-086 §4B]. vm_stage.py picks which volumes to
# stage by asking the reference which ones its run touches; a run that jumps to a room touches
# resources a no-jump run never does. Staging without it gave PoliceQuest1 volumes [0,1] and the
# guest reported `err 1` in room 97. **One environment variable feeds both legs**, so the stage and
# the run cannot disagree about where the guest is going [§2F, §2O.1].
if ($env:P3B_ROOM -and [int]$env:P3B_ROOM -gt 0) {
  $stageArgs += @("--room", "$($env:P3B_ROOM)", "--room-at", "$(if ($env:P3B_ROOM_AT) { $env:P3B_ROOM_AT } else { 8 })")
}
if ($WithInput) {
  # ★★★★ --eye, NOT the byte gate's schedule. It keeps only lines whose said() branch produces
  # a change a PERSON can see -- measured per line against the reference, not assumed -- and it
  # starts a quarter of the way in so Jay has a baseline before the first command. It also
  # reports which lines reach an opcode this VM does not implement, which is this task's least
  # expected finding and belongs in the operator's view, not only in a report.
  python harness\tools\vm_input_script.py (Join-Path $GAMES $Title) --out "$stage\input.gen.txt" --cycles $Cycles --eye --max-lines 3
  if ($LASTEXITCODE -ne 0) { throw "no verified input lines for $Title" }
  $stageArgs += @("--input", "$stage\input.gen.txt")
}
python harness\tools\vm_stage.py @stageArgs
if ($LASTEXITCODE -ne 0) { throw "staging did not fit" }

$env:P3B_PROG = "build\p3b_probe_pk_fresh.bin"
$env:P3B_STAGE = $stage
$env:P3B_SYMBOLS = "build\p3b\symbols.txt"
$env:P3B_CYCLES = "$Cycles"
$env:P3B_HOLD = "$Hold"
$env:P3B_OUT = if ($Headless) { "build\p3b_headless" } else { "build\p3b_eye" }

if ($Headless) {
  # ═══════════════════════════════════════════════════════════════════════════════════════
  # ★★★★ THE HEADLESS INTEGRATION RUN. p3b_run.lua directly -- no display script, so no room
  # jump and no palette assertion from the host: the guest on its own, five subsystems, one
  # machine. This is the arm that says whether the probe is HEALTHY, and it had no recorded
  # invocation at all; every run of it in T-P0-060 was a hand-typed MAME line.
  # ★★★ -seconds_to_run is a SESSION budget and therefore a clock charged to the whole run
  # [idiom 43a's neighbour; gate_budget_check.sh measures the class]. 900 against a 160-cycle
  # run that spends ~85 emulated seconds in a populated room is ~10x headroom, and the figure
  # is stated here rather than left as a number nobody has weighed.
  # ★★ -nothrottle: nothing in this arm is a human judgement (§2U); the eye-gate arm below
  # never gets it (§2U.2).
  $secs = if ($env:P3B_SECONDS) { $env:P3B_SECONDS } else { "900" }
  C:\mame\mame.exe coco3 -video none -sound none -window -nomaximize -skip_gameinfo -nothrottle `
    -seconds_to_run $secs `
    -rompath C:/mame/roms -cfg_directory harness\mame-cfg `
    -autoboot_script C:/Projects/coco_agi/harness/tools/p3b_run.lua -autoboot_delay 0 | Out-Null

  # ★★★★★ ADJUDICATE, DO NOT JUST LAUNCH. run_gates.sh's own header: "a sweep that exits 0
  # having written 90 .bin files looks exactly like a gate that passed." The run's own log is
  # the adjudicator here -- a STUCK line, a non-zero err, or a missing completion line is a
  # failure, and the exit code carries it so a caller can chain on it.
  $log = "$($env:P3B_OUT)\run.log"
  if (-not (Test-Path $log)) { "★★★ p3b: no run.log -- the launch produced nothing"; exit 1 }
  $stuck = Select-String -Path $log -Pattern '★★★ STUCK|★★★ STUCK' -Quiet
  $done  = Select-String -Path $log -Pattern 'cycles complete|cycles in ' -Quiet
  # ★★★ P3_PBUF IS IN THE PATTERN BECAUSE IT IS A VERDICT LINE. An allowlist filter drops what it
  # does not name, and what it does not name is always the newest thing -- here AC-3's whole
  # observable printed to the log and never to the console [the same shape as the star-in-a-pattern
  # loss two tasks ago: the filter kept every table and removed the conclusion].
  Select-String -Path $log -Pattern 'OK prompt|program \d+ bytes|vocabulary |par_vocab written|COMMAND TYPED|STUCK|cycles in|final room|P3_PBUF' |
    ForEach-Object { $_.Line }
  if ($stuck) { "★★★ p3b FAILED -- the watchdog fired"; exit 1 }
  if (-not $done) { "★★★ p3b FAILED -- no completion line; the run did not reach $Cycles cycles"; exit 1 }
  "★ p3b headless: $Cycles cycles, no stall"
  exit 0
}

# ★★★★★ NO -nothrottle. §2U.2: "an eye gate nobody can watch at 2869% is not an eye gate", and
# p3b_show.lua carries the same standing note. RGB, screen_config=1, per §4's monitor rule.
C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo `
  -rompath C:/mame/roms -cfg_directory harness\mame-cfg `
  -autoboot_script C:/Projects/coco_agi/harness/tools/p3b_show.lua -autoboot_delay 0
