# harness/tools/objscan_sweep.ps1 -- P6.10 AC-2/AC-3/AC-4: what does the 255-slot walk cost?
#
# ★★★★★ THE ABLATION IS BEHAVIOUR-NEUTRAL AND THAT IS PROVED, NOT ASSUMED. vm_check_all_motions
# and vm_update_objs both open `ldx #VM_OBJ / ldb #VM_OBJ_MAX` and walk ALL 255 SLOTS every cycle,
# testing a flag and skipping the inactive ones. VM_OBJ_SCAN lowers only that bound. With every
# active object below the bound the 288-byte state diff must stay byte-identical -- and it does:
# the nine-title gate is 9/9 PASS at VM_OBJ_SCAN=16 [T-P0-066 AC-4]. **So the timing delta between
# two arms is the traversal and nothing else** [L-73: name every variable a toggle moves; this one
# moves exactly one, and the gate is the evidence].
#
# ★★★★ IT IS MEASURED PER ROOM, BECAUSE THE WHOLE POINT IS THE OBJECT COUNT. Room 83 (attract) has
# ZERO active objects and room 1 has four, and P6.9's +431% came from comparing them. If the walk
# is a constant it costs the SAME in both, and its SHARE collapses as real work appears -- which is
# a different finding from "the per-object work is expensive" and points somewhere else entirely.
#
# ★★★ THE CLOCK IS MEASURED IN-SESSION, NEVER ASSUMED [L-78, AD-100]. vm_sweep.lua closes its
# calibration bracket at the guest's own VP_MARK writes and prints the implied MHz; a run whose
# clock line is absent or slow is discarded rather than divided by 1.7898.
#
# usage:  harness/tools/objscan_sweep.ps1   [-Title Kingquest1] [-Cycles 200]
param(
    [string]$Title  = "Kingquest1",
    [int]   $Cycles = 200,
    [int[]] $Scans  = @(255, 16),
    [string[]] $Rooms = @("", "1")      # "" = no jump (room 83, attract, zero objects)
)

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Users\jayse\DEV\cmd;C:\Users\jayse\DEV\mingw64\opt\bin;" + $env:PATH
Set-Location C:\Users\jayse\DEV\coco_agi

$rows = @()
foreach ($room in $Rooms) {
    foreach ($scan in $Scans) {
        # ★ Clear every VM_* the runner reads, so an arm cannot inherit the previous arm's
        # environment -- the defect vm_run.ps1's own header describes at $VM_TITLES [L-92].
        Remove-Item Env:\VM_INPUT, Env:\VM_VBLCLOCK, Env:\VM_OUT, Env:\VM_STAGE, Env:\VM_PROG,
                    Env:\VM_SYMBOLS, Env:\VM_ROOM, Env:\VM_OBJ_SCAN `
                    -ErrorAction SilentlyContinue
        $env:VM_TITLES = $Title
        $env:VM_CYCLES = "$Cycles"
        $env:VM_TIMED  = "$Cycles"
        if ($scan -ne 255) { $env:VM_OBJ_SCAN = "$scan" }
        if ($room -ne "")  { $env:VM_ROOM = $room }

        $label = "room $(if ($room -eq '') { '83 (attract, 0 obj)' } else { "$room (4 obj)" })  scan=$scan"
        "=== $label ==="
        & harness\tools\vm_run.ps1 2>&1 | Out-Null
        # ★★★★ THE TIMING LINES ARE IN run.log, NOT ON STDOUT. vm_sweep.lua's w() writes both, but
        # the Lua runs inside MAME and its stdout is swallowed by the runner's `| Out-Null`. Parsing
        # stdout found nothing and the first version of this script died on a null match -- which is
        # the right failure: a missing clock line must VOID the arm, never fall back to a literal
        # 1.7898 [L-78, AD-100]. ★★ In VM_TIMED mode the probe free-runs and publishes no per-cycle
        # state, so vm_diff.py reports "guest 0 cycles / FAIL" -- expected for a timing arm and not
        # a gate result. The gate arm is the separate VM_OBJ_SCAN=16 run that scored 9/9.
        $log = Get-Content "build\vm_sweep\$Title\run.log" -ErrorAction SilentlyContinue
        $free = $log | Select-String 'AC-7 free-run|ms/cycle|clock MEASURED|opcount=|SLOW CLOCK'
        $free | ForEach-Object { "    $($_.Line.Trim())" }

        $mhzM  = $log | Select-String 'clock MEASURED ([\d.]+) MHz'
        $mspcM = $log | Select-String '([\d.]+) ms/cycle'
        $opcM  = $log | Select-String 'opcount=(\d+)'
        $objM  = $log | Select-String 'active objects .*= (\d+)'
        if (-not ($mhzM -and $mspcM -and $opcM)) {
            "    ★★★ ARM VOID -- run.log has no clock/timing line. Not reported as a number."
            continue
        }
        # ★★★★★ THE ARM MUST PROVE IT DID THE THING IT IS NAMED FOR [§2W]. VM_ROOM was keyed to the
        # PACED cycle counter, which a free-run never advances -- so the jump silently did nothing
        # and two "different rooms" reported 67.802 ms and opcount 2950 IDENTICALLY. A scaling
        # sweep whose independent variable never moved would have reported a flat curve as a
        # finding. Now a room arm without its jump line is VOID, not a number.
        if ($room -ne "" -and -not ($log | Select-String 'room jump BEFORE free-run')) {
            "    ★★★ ARM VOID -- room $room requested but no jump line in run.log."
            continue
        }
        $mhz  = $mhzM.Matches.Groups[1].Value
        $mspc = $mspcM.Matches.Groups[1].Value
        $opc  = $opcM.Matches.Groups[1].Value
        $obj  = if ($objM) { $objM.Matches.Groups[1].Value } else { "?" }
        $rows += [pscustomobject]@{
            room = $(if ($room -eq "") { "83" } else { $room })
            scan = $scan; objects = $obj; ms_per_cycle = $mspc; opcount = $opc; MHz = $mhz
        }
        ""
    }
}

"=== P6.10 OBJECT-SCAN SWEEP ==="
$rows | Format-Table -AutoSize

# ★★★★★ THE DELTA IS THE FINDING. Same room, same opcount, same clock -- the only difference is
# how many empty slots were walked, so the difference in ms/cycle is the traversal's price.
"=== traversal cost, per room ==="
foreach ($r in ($rows | Select-Object -ExpandProperty room -Unique)) {
    $a = $rows | Where-Object { $_.room -eq $r -and $_.scan -eq 255 }
    $b = $rows | Where-Object { $_.room -eq $r -and $_.scan -eq 16 }
    if ($a -and $b -and $a.ms_per_cycle -and $b.ms_per_cycle) {
        $d = [double]$a.ms_per_cycle - [double]$b.ms_per_cycle
        $pct = 100.0 * $d / [double]$a.ms_per_cycle
        "  room {0,-3}  255 slots {1,8} ms   16 slots {2,8} ms   delta {3,7:N3} ms = {4,5:N1}% of the cycle" -f `
            $r, $a.ms_per_cycle, $b.ms_per_cycle, $d, $pct
        # ★ per-slot cost, from the delta over the 239 slots removed
        "         => {0:N1} CPU cycles per skipped slot (at {1} MHz), over 239 slots removed" -f `
            (($d / 1000.0) * [double]$a.MHz * 1e6 / 239.0), $a.MHz
        # ★★ opcount MUST match between arms; if it does not, the arms ran different programs
        if ($a.opcount -ne $b.opcount) {
            "         ★★★ opcount DIFFERS ({0} vs {1}) -- the arms are not comparable [L-79]" -f $a.opcount, $b.opcount
        }
    }
}
