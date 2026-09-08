# harness/tools/p3b_gain.ps1 -- P6.12 AC-9: what did the object bound do to the INTEGRATED cycle?
#
# ★★★★★ WHAT THIS IS NOT. AD-135's T3 is "2.22 cycles/s AT 4 SPRITES", measured in room 1. The
# headless p3b arm does NO ROOM JUMP -- p3b_show.ps1's own comment says so -- so it stays in room
# 83, attract mode, ZERO sprites. **A figure from this arm is not T3 and must not be labelled T3.**
# The first attempt at AC-9 produced 14.98 cycles/s here and the number is real; it is just a
# number about a different thing, and reporting it as T3 would be P6.10's room jump again.
#
# ★★★★ SO THIS MEASURES THE COMPARISON THAT *IS* AVAILABLE: the same room, the same sprite count,
# the same harness, before and after the object bound. Attract mode against attract mode.
#
# ★★★ THE BEFORE SIDE IS BUILT, NOT CITED. There is an attract-mode figure in an existing
# build/p3b_headless/run.log, but its provenance is a run at an unknown ref -- §2T allows a
# citation only when the inputs are verified unchanged, and the inputs are exactly what changed.
# So the previous revision is assembled and run through the same Lua.
#
# ★★ The two arms are asserted DISTINCT before either is reported: vm_objtop is absent from the
# before map and present in the after [the check objbound_gain.ps1 needed after its first sweep
# measured the same binary twice].
param(
    [string]$Before = "da2e5e4",     # P6.8b -- the last revision before the object bound
    [int]   $Cycles = 120
)
$ErrorActionPreference = "Stop"
$env:PATH = "C:\Users\jayse\DEV\cmd;C:\Users\jayse\DEV\mingw64\opt\bin;" + $env:PATH
Set-Location C:\Users\jayse\DEV\coco_agi
$LW = "C:\WIN_LWTools\lwasm.exe"
$FLAGS = @("-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK","-DPLANE_WINDOWED","-DPRI_PACKED")

# ── the before tree ─────────────────────────────────────────────────────────────────────────
# ★★ bash for the extraction: PowerShell's `>` writes a UTF-8 BOM that lwasm rejects on line 1.
$B = "build/p3b_gain_before"
& C:\Users\jayse\DEV\bin\bash.exe -c "cd /c/Users/jayse/DEV/coco_agi && rm -rf $B && mkdir -p $B && git archive $Before src | tar -x -C $B"

function Build-P3b($root, $out) {
    # ★★★ -I<root> FIRST so the extracted revision's own includes win; -I. after, for the HAL and
    # src/engine, which this task did not touch and which both arms therefore share. Putting -I.
    # first is what made objbound_gain.ps1 measure the same binary twice.
    & $LW --format=raw --output=$out --map="$out.map" "-I$root" -I. @FLAGS "$root/src/harness/p3b_probe.s"
    if ($LASTEXITCODE -ne 0) { throw "p3b assemble failed for $out" }
    (Get-Item $out).Length
}
$szB = Build-P3b $B      "build/p3b_before.bin"
$szA = Build-P3b "."     "build/p3b_after.bin"
"before $szB bytes   after $szA bytes"
$hasB = Select-String -Path "build/p3b_before.bin.map" -Pattern 'Symbol: vm_objtop ' -Quiet
$hasA = Select-String -Path "build/p3b_after.bin.map"  -Pattern 'Symbol: vm_objtop ' -Quiet
if ($hasB) { throw "BEFORE build defines vm_objtop -- the extracted tree did not take effect" }
if (-not $hasA) { throw "AFTER build lacks vm_objtop -- the bound is not in this build" }
"★ arms verified distinct: vm_objtop absent in before, present in after"

$stage = "build\vm_stage\Kingquest1"
foreach ($arm in @(@{n="before"; p="build\p3b_before.bin"; m="build\p3b_before.bin.map"},
                   @{n="after "; p="build\p3b_after.bin";  m="build\p3b_after.bin.map"})) {
    $out = "build\p3b_gain_$($arm.n.Trim())"
    New-Item -ItemType Directory -Force $out | Out-Null
    # ★★ Clear the log first: an adjudicator that CAN read a previous run's artifacts WILL [L-92].
    # This exact trap fired earlier in P6.12 -- a failed build left a stale run.log that read like
    # a fresh result.
    Remove-Item "$out\run.log" -ErrorAction SilentlyContinue
    $WANT = @("res_volbase","res_slicebase","res_curblk","vm_quit","vm_badop","vm_cycle","vm_tdelay",
              "res_err","ph_blk_fb","ph_blk_pri","par_vocab","P3_INBUF","P3_FEED","P3_VOCAB_BAD",
              "P3_VOCAB","P3_VOCAB_END","P3_CODE_END","P3_PARSER_BASE","P3_PARSER_TOTAL")
    python harness\tools\vm_symbols.py $arm.m --out "$out\symbols.txt" --want @WANT | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "symbols missing for $($arm.n)" }
    $env:P3B_PROG = $arm.p; $env:P3B_STAGE = $stage; $env:P3B_SYMBOLS = "$out\symbols.txt"
    $env:P3B_CYCLES = "$Cycles"; $env:P3B_OUT = $out
    C:\mame\mame.exe coco3 -video none -sound none -window -nomaximize -skip_gameinfo -nothrottle `
        -seconds_to_run 900 -rompath C:/mame/roms -cfg_directory harness\mame-cfg `
        -autoboot_script C:/Projects/coco_agi/harness/tools/p3b_run.lua -autoboot_delay 0 | Out-Null
    $log = Get-Content "$out\run.log" -ErrorAction SilentlyContinue
    if (-not $log) { "  $($arm.n): ★★★ no run.log -- VOID"; continue }
    "=== $($arm.n) ==="
    ($log | Select-String 'cycles in |median |clock MEASURED|final room|interpret |roomcheck ') |
        ForEach-Object { "    $($_.Line.Trim())" }
}
