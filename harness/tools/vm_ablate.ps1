# harness/tools/vm_ablate.ps1 -- AC-4: decompose the VM's per-cycle cost by ABLATION.
#
# ★★★★ WHY A SCRIPT AND NOT A LOOP IN THE SHELL. The first attempt at this measurement built
# three ablation binaries, ran them against ONE symbol table, and produced a silent non-result:
# -DVM_NOCOUNT is 28 bytes smaller than baseline, so every symbol shifted, and the harness
# staged the game's volumes to addresses belonging to a different build. The run reached its
# gate, staged into the wrong place, and never completed a cycle -- **no error, no output, and
# it looked like the ablation had simply failed to matter.**
# ★★★ L-56 in its exact form: the first measurement measured the scaffolding. **Every ablation
# gets its own --map and its own symbols.txt**, and that is the whole reason this file exists.
#
# ★★ ABLATION, NOT REGRESSION-ATTRIBUTION [L-43]. Each variant removes one thing and the delta
# against baseline is that thing's cost. ★ The constraint in a VM is that removing real work
# diverges control flow, so only ablations that CANNOT change what executes are honest here:
#   VM_NOCOUNT   -- the interpreter's own opcode/test counters. Removing a counter cannot
#                   change a branch. Safe.
#   VM_PACEONLY  -- interpret_cycle is never called; measures the harness + pacing FLOOR.
#   ABL_NOCOPY   -- the resource copy's byte-moving loop, skipped on a REPEAT fetch only.
#
# ★★★★ T-P0-033 SAID THE COPY COULD NOT BE HONESTLY ABLATED AND T-P0-035 MADE IT POSSIBLE.
# The objection was real: deleting the copy leaves stale bytes and the dispatch then executes a
# different program, so the measurement would not be "the same program minus a part" [L-43].
# ★★★ AC-3 removed the objection by experiment rather than by argument -- suppressing the
# re-fetch in the REFERENCE and diffing against the unsuppressed reference gave byte-identical
# 288-byte state on all 300 cycles across six titles [L-58]. **A repeat fetch cannot change what
# executes, so skipping one is a true ablation.** 99.7% of copied bytes are repeats.
# ★★ ABL_NOCOPY therefore skips ONLY repeats, keyed by arena depth, and leaves every piece of
# bookkeeping intact. It is a measurement build and is never shipped.
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$TITLE  = if ($env:ABL_TITLE)  { $env:ABL_TITLE }  else { "Kingquest1" }
$TIMED  = if ($env:ABL_TIMED)  { $env:ABL_TIMED }  else { "200" }
$VARIANTS = @("baseline", "VM_NOCOUNT", "VM_PACEONLY", "ABL_NOCOPY", "ABL_NOFETCH")

$WANT = @("res_volbase","res_slicebase","res_curblk","vm_icguard","res_depth","res_top",
          "vm_code","vm_codelen","vm_ip","vm_curlogic")

foreach ($v in $VARIANTS) {
    $flag = if ($v -eq "baseline") { @() } else { @("-D$v") }
    $bin  = "build/vm_abl_$v.bin"
    $map  = "build/vm_abl_$v.map"
    $sym  = "build/vm_stage/symbols_$v.txt"

    $args = @("--format=raw","--output=$bin","--map=$map","-I.",
              "-DHAL_GFX_MODE_SERVICE","-DHAL_SYS_FAST_CLOCK") + $flag + @("src/harness/vm_probe.s")
    & C:\WIN_LWTools\lwasm.exe @args
    if ($LASTEXITCODE -ne 0) { throw "assemble failed for $v" }

    # ★★★ THE STEP THAT WAS MISSING. Symbols come from THIS variant's map, never a shared one.
    python harness\tools\vm_symbols.py $map --out $sym --want @WANT
    if ($LASTEXITCODE -ne 0) { throw "symbols missing for $v" }

    "=== $v  ($((Get-Item $bin).Length) bytes) ==="
    $env:VM_TITLES = $TITLE
    $env:VM_TIMED  = $TIMED
    $env:VM_PROG   = $bin
    $env:VM_SYMBOLS = $sym
    $env:VM_OUT    = "build/vm_abl_out_$v"
    & C:\mame\mame.exe coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize `
        -seconds_to_run 400 -autoboot_script harness/tools/vm_sweep.lua 2>&1 |
        Select-String "free-run|ms/cycle|opcount|HALT|bad" | Select-Object -First 4
}
