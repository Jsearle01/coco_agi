# harness/tools/objbound_gain.ps1 -- P6.11 AC-5: what did bounding the object scan actually buy?
#
# ★★★★★ THE "BEFORE" IS A BUILD OF THE PREVIOUS REVISION, NOT A KNOB. P6.10 measured the fixed
# 255-slot walk with a VM_OBJ_SCAN ablation bound; that knob is retired because the loops now read
# vm_objtop instead. Keeping it alive purely to re-enact a superseded measurement would be a second
# home for the fact [§2F] -- so the before-side is assembled from the git revision that had the
# fixed walk. ★★★ The same control pattern found P6.8b's vector-page defect in one run after four
# wrong attributions: **build the old program and put it through the same instrument.**
#
# ★★★★ IT MEASURES BOTH SIDES FRESH. A gain quoted as "9.881 ms, from the last report" would be
# comparing a number taken from a different binary against one taken today [§2T's after-build rule:
# a baseline taken after the change proves nothing, and a cited one must have unchanged inputs --
# the inputs here CHANGED, which is the whole point].
#
# ★★★ THE CLOCK IS MEASURED IN-SESSION IN EVERY ARM [L-78, AD-100], and an arm whose run.log
# carries no clock line is VOID rather than divided by a literal.
# ★★ Room arms must prove their jump landed [P6.10: two "different" rooms once agreed to six
# decimal places because VM_ROOM silently did nothing in a free-run].
#
# usage:  harness/tools/objbound_gain.ps1 [-Before <git-rev>] [-Title Kingquest1] [-Cycles 200]
param(
    [string]$Before = "da2e5e4",             # P6.8b -- the last revision with the fixed 255-slot walk
    [string]$Title  = "Kingquest1",
    [int]   $Cycles = 200,
    [string[]] $Rooms = @("", "1", "2", "3")
)

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Users\jayse\DEV\cmd;C:\Users\jayse\DEV\mingw64\opt\bin;" + $env:PATH
Set-Location C:\Users\jayse\DEV\coco_agi

$LWASM = "C:\WIN_LWTools\lwasm.exe"
$rows  = @()

# ── the BEFORE tree, extracted to build/objbound_before/ ────────────────────────────────────
# ★★ bash for the extraction: PowerShell's `>` writes a UTF-8 BOM and lwasm rejects it with
# "Bad symbol" on line 1 -- learned in P6.8b, recorded here so it is not rediscovered. §2J: no
# heredocs; this is a plain redirect inside bash -c.
$BEFORE_DIR = "build/objbound_before"
New-Item -ItemType Directory -Force $BEFORE_DIR, "$BEFORE_DIR/src/harness" | Out-Null
$files = & git ls-tree -r --name-only $Before src/harness
foreach ($f in $files) {
    $dst = "$BEFORE_DIR/$f"
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    & C:\Users\jayse\DEV\bin\bash.exe -c "cd /c/Users/jayse/DEV/coco_agi && git show ${Before}:$f > $dst"
}
"before tree: $($files.Count) files from $Before -> $BEFORE_DIR"

function Build-Arm($srcRoot, $out) {
    # ★★★★★ THE EXTRACTED TREE MUST COME FIRST ON THE INCLUDE PATH, AND THE FIRST VERSION OF THIS
    # SCRIPT PUT `-I.` FIRST. vm_probe.s is passed by path from the before-tree, but every
    # `include "src/harness/*.s"` inside it resolved against the CURRENT tree, so the "before"
    # binary was built from today's sources and the two arms were the same program. ★★★★ The
    # symptom was the one this project now recognises: before and after identical to three decimal
    # places in all four rooms [P6.10's room jump, same shape, same day].
    # ★★★ `-I.` stays, AFTER, so the HAL, src/engine and hal.inc -- none of which this task
    # touched -- resolve against the current tree and are shared by both arms. That is what keeps
    # the object-loop bound the ONLY difference between the binaries.
    $args = @("--format=raw", "--output=$out", "--map=$out.map", "-I$srcRoot", "-I.",
              "-DHAL_GFX_MODE_SERVICE", "-DHAL_SYS_FAST_CLOCK")
    & $LWASM @args "$srcRoot/src/harness/vm_probe.s"
    if ($LASTEXITCODE -ne 0) { throw "assemble failed for $out" }
    return (Get-Item $out).Length
}

$szBefore = Build-Arm $BEFORE_DIR "build/vm_probe_before.bin"
$szAfter  = Build-Arm "."         "build/vm_probe_after.bin"
"before $szBefore bytes   after $szAfter bytes   delta $($szAfter - $szBefore)"

# ★★★★★ THE ARMS MUST BE PROVABLY DIFFERENT PROGRAMS, AND THE PROOF IS SEMANTIC, NOT A SIZE.
# `vm_objtop` is the whole subject of this change: the after-build defines it and the before-build
# cannot. Checking the maps says the treatment was applied; comparing byte counts would only say
# something moved. ★★★ A sweep that cannot tell its arms apart reports "no effect" as a finding
# [L-98 candidate: verify the treatment was applied, not just that the run completed].
$hasBefore = (Select-String -Path "build/vm_probe_before.bin.map" -Pattern 'Symbol: vm_objtop ' -Quiet)
$hasAfter  = (Select-String -Path "build/vm_probe_after.bin.map"  -Pattern 'Symbol: vm_objtop ' -Quiet)
if ($hasBefore) { throw "BEFORE build defines vm_objtop -- the extracted tree did not take effect; the arms are the same program." }
if (-not $hasAfter) { throw "AFTER build does not define vm_objtop -- the bound is not in this build." }
"★ arms verified distinct: vm_objtop absent in before, present in after"

foreach ($arm in @(@{n = "before(255 fixed)"; p = "build\vm_probe_before.bin" },
                   @{n = "after (vm_objtop)"; p = "build\vm_probe_after.bin" })) {
    foreach ($room in $Rooms) {
        Remove-Item Env:\VM_INPUT, Env:\VM_VBLCLOCK, Env:\VM_OUT, Env:\VM_STAGE, Env:\VM_SYMBOLS,
                    Env:\VM_ROOM, Env:\VM_OBJCENSUS, Env:\VM_OBJBOUND_FAULT `
                    -ErrorAction SilentlyContinue
        $env:VM_TITLES = $Title; $env:VM_CYCLES = "$Cycles"; $env:VM_TIMED = "$Cycles"
        $env:VM_PROG_PREBUILT = $arm.p
        if ($room -ne "") { $env:VM_ROOM = $room }

        $label = "$($arm.n)  room $(if ($room -eq '') { '83 (0 obj)' } else { $room })"
        "=== $label ==="
        & harness\tools\vm_run.ps1 2>&1 | Out-Null
        $log = Get-Content "build\vm_sweep\$Title\run.log" -ErrorAction SilentlyContinue
        # ★★★ vm_objtop IS PART OF THE RESULT, NOT A DETAIL. The gain came out at 10.06 ms in rooms
        # with objects and 1.269 ms in attract mode -- the opposite way round -- and the mark is
        # what explains it. The first version of this filter omitted the line, so the number sat in
        # run.log and not in the table anybody reads.
        ($log | Select-String 'AC-7 free-run|ms/cycle|clock MEASURED|vm_objtop = slot|active objects') |
            ForEach-Object { "    $($_.Line.Trim())" }

        $mspcM = $log | Select-String '([\d.]+) ms/cycle'
        $mhzM  = $log | Select-String 'clock MEASURED ([\d.]+) MHz'
        $opcM  = $log | Select-String 'opcount=(\d+)'
        if (-not ($mspcM -and $mhzM -and $opcM)) { "    ★★★ ARM VOID -- no clock/timing line."; continue }
        if ($room -ne "" -and -not ($log | Select-String 'room jump BEFORE free-run')) {
            "    ★★★ ARM VOID -- room $room requested, no jump line."; continue
        }
        $topM = $log | Select-String 'vm_objtop = slot (\d+)'
        $objM = $log | Select-String 'active objects .*= (\d+)'
        $rows += [pscustomobject]@{
            arm  = $arm.n; room = $(if ($room -eq "") { "83" } else { $room })
            objs = $(if ($objM) { $objM.Matches.Groups[1].Value } else { "?" })
            slots_walked = $(if ($topM) { $topM.Matches.Groups[1].Value } else { "255" })
            ms   = $mspcM.Matches.Groups[1].Value
            opcount = $opcM.Matches.Groups[1].Value; MHz = $mhzM.Matches.Groups[1].Value
        }
        ""
    }
}

"=== P6.11 AC-5: THE GAIN ==="
$rows | Format-Table -AutoSize
"=== per room ==="
foreach ($r in ($rows | Select-Object -ExpandProperty room -Unique)) {
    $b = $rows | Where-Object { $_.room -eq $r -and $_.arm -like "before*" }
    $a = $rows | Where-Object { $_.room -eq $r -and $_.arm -like "after*" }
    if ($b -and $a) {
        $d = [double]$b.ms - [double]$a.ms
        "  room {0,-3}  before {1,8} ms   after {2,8} ms   saved {3,7:N3} ms = {4,5:N1}%   ({5,5:N1}% of a 50 ms AGI tick)" -f `
            $r, $b.ms, $a.ms, $d, (100.0 * $d / [double]$b.ms), (100.0 * $d / 50.0)
        "         cycles/s {0:N2} -> {1:N2}" -f (1000.0 / [double]$b.ms), (1000.0 / [double]$a.ms)
        if ($b.opcount -ne $a.opcount) { "         ★★★ opcount DIFFERS ({0} vs {1}) -- arms not comparable [L-79]" -f $b.opcount, $a.opcount }
    }
}
# ★★★ AC-6: does bounding the scan change the rooms 1-vs-2 residual? [AD-141 -- 6.5 ms at equal
# object count and opcounts within 0.16%]. Report; do not chase [§3].
"=== AC-6: the rooms 1 vs 2 residual ==="
foreach ($armName in ($rows | Select-Object -ExpandProperty arm -Unique)) {
    $r1 = $rows | Where-Object { $_.arm -eq $armName -and $_.room -eq "1" }
    $r2 = $rows | Where-Object { $_.arm -eq $armName -and $_.room -eq "2" }
    if ($r1 -and $r2) {
        "  {0}  room1 {1} ms   room2 {2} ms   residual {3:N3} ms" -f `
            $armName, $r1.ms, $r2.ms, ([double]$r2.ms - [double]$r1.ms)
    }
}
