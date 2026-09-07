# harness/tools/p3b_show.ps1 -- Â§4A's EYE GATE, with a recorded invocation. [T-P0-060 AC-1]
#
# â˜…â˜…â˜…â˜…â˜… THIS RUNNER DID NOT EXIST, AND THE EYE GATE IS THE GATE THAT DECIDES DELIVERY.
# p3b_show.lua reads P3B_PROG, P3B_STAGE and P3B_SYMBOLS from the environment, and
# build/p3b/symbols.txt was produced by a hand-typed vm_symbols.py line that is in no file. That
# is the L-45 defect on the one gate whose result is a human's judgement -- and Â§2U.2 excludes
# this gate from -nothrottle precisely because a person has to watch it, so it is also the gate
# that costs the most to re-run from a guess.
# â˜…â˜…â˜… Same disease this project has now named five times (res 74-vs-1,264, cel 1-title-vs-6, pic
# without picgate, the VM's nine titles in an env var, and this). **The scope and the invocation
# of a gate are part of its definition.**
#
# â˜…â˜…â˜…â˜… IT DELIBERATELY DOES NOT PASS -nothrottle [Â§2U.2]. An eye gate nobody can watch at 2869%
# is not an eye gate.
#
# usage:
#   powershell -File harness/tools/p3b_show.ps1 [-Title Kingquest1] [-Cycles 160] [-WithInput]
param(
  [string]$Title  = $(if ($env:P3B_TITLE)  { $env:P3B_TITLE }  else { "Kingquest1" }),
  [int]   $Cycles = $(if ($env:P3B_NCYC)   { [int]$env:P3B_NCYC } else { 120 }),
  # â˜… NOT -Input. `$Input` is a PowerShell AUTOMATIC VARIABLE (the pipeline enumerator), so a
  # parameter of that name is bound to a PipelineReader and the script dies on a cast error
  # before it runs a line. Caught by running it, which is the only way this one shows up.
  [switch]$WithInput,
  # ★★★★ -Headless: the SAME build, symbols and staging, driven by p3b_run.lua with no display.
  # ★★★ It shares the whole preamble deliberately (§2F). The eye gate and the headless integration
  # run differ in exactly two things -- which Lua drives it, and whether MAME gets a screen -- and
  # duplicating the build/stage into a second script is how the two would drift into testing
  # different programs. ★★ Headless also gets -nothrottle (§2U); the eye gate never does (§2U.2).
  [switch]$Headless,
  [double]$Hold   = 3.0
)
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$GAMES = if ($env:VM_GAMES_ROOT) { $env:VM_GAMES_ROOT } else { "C:\Projects\agi-games\pc" }
$stage = "build\vm_stage\$Title"
$LW    = "C:\WIN_LWTools\lwasm.exe"

# â˜…â˜… THE FLAG SET IS gates.manifest's p3b ROW, NOT A GUESS. PLANE_WIN_MMU comes from the SOURCE
# (p3b_probe.s:65) and passing it here is a multiply-defined error [gates.manifest].
$FLAGS = @("-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK","-DPLANE_WINDOWED","-DPRI_PACKED")
& $LW --format=raw --output=build/p3b_probe_pk_fresh.bin --map=build/p3b_probe_pk.map -I. @FLAGS src/harness/p3b_probe.s
if ($LASTEXITCODE -ne 0) { throw "p3b assemble failed" }
"p3b_probe: $((Get-Item build\p3b_probe_pk_fresh.bin).Length) bytes"
"  [source-tree $(& python harness\tools\gate_audit.py --hash src/harness/p3b_probe.s)]"

# â˜…â˜…â˜… SYMBOLS FROM THE BUILD'S MAP. P3_INBUF is an INTERIOR address -- it follows parser.s
# inside MAP_RESERVED and moves whenever either grows -- so p3b_run.lua refuses to stage input
# without it rather than falling back to a literal [P6.3 Â§3.F.2].
New-Item -ItemType Directory -Force build\p3b | Out-Null
$WANT = @("res_volbase","res_slicebase","res_curblk","vm_quit","vm_badop","vm_cycle","vm_tdelay",
          "res_err","ph_blk_fb","ph_blk_pri","par_vocab","P3_INBUF","P3_FEED","P3_VOCAB_BAD","P3_VOCAB","P3_VOCAB_END","P3_CODE_END","P3_PARSER_BASE","P3_PARSER_TOTAL")
python harness\tools\vm_symbols.py build\p3b_probe_pk.map --out build\p3b\symbols.txt --want @WANT
if ($LASTEXITCODE -ne 0) { throw "symbols missing" }

# â˜…â˜…â˜…â˜… THE SAME TWO FILES THE BYTE GATE READS. vm_stage.py writes words.tok and input.txt into
# the stage directory from the game and from vm_input_script.py; nothing here synthesises text,
# so what Jay watches and what vm_diff.py compares cannot drift apart (Â§2O.1, applied to input).
# â˜…â˜… Cleared first [L-92]: a script left behind by another title would feed the WRONG game's
# words into this one, and the screen would be wrong for a reason nobody would look for here.
Remove-Item -Force -ErrorAction SilentlyContinue "$stage\input.txt", "$stage\words.tok", "$stage\input.gen.txt"
$stageArgs = @((Join-Path $GAMES $Title), "--out", $stage, "--cycles", "$Cycles")
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
  $stuck = Select-String -Path $log -Pattern '★★★ STUCK|â˜…â˜…â˜… STUCK' -Quiet
  $done  = Select-String -Path $log -Pattern 'cycles complete|cycles in ' -Quiet
  Select-String -Path $log -Pattern 'OK prompt|program \d+ bytes|vocabulary |par_vocab written|COMMAND TYPED|STUCK|cycles in|final room' |
    ForEach-Object { $_.Line }
  if ($stuck) { "★★★ p3b FAILED -- the watchdog fired"; exit 1 }
  if (-not $done) { "★★★ p3b FAILED -- no completion line; the run did not reach $Cycles cycles"; exit 1 }
  "★ p3b headless: $Cycles cycles, no stall"
  exit 0
}

# â˜…â˜…â˜…â˜…â˜… NO -nothrottle. Â§2U.2: "an eye gate nobody can watch at 2869% is not an eye gate", and
# p3b_show.lua carries the same standing note. RGB, screen_config=1, per Â§4's monitor rule.
C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo `
  -rompath C:/mame/roms -cfg_directory harness\mame-cfg `
  -autoboot_script C:/Projects/coco_agi/harness/tools/p3b_show.lua -autoboot_delay 0
