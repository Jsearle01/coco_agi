# poc/s01_hres/s01.ps1 -- assemble and run Spike S-01 rev B.
#
# ★★★★★ STAGE 0 IS THE DEFAULT AND THAT IS DELIBERATE [§2]. `-Stage 1` is available but a stage-1
# result means nothing until stage 0 has passed on the same build, so the stage-0 run is what an
# unqualified invocation does.
#
# ★★★ NOT A GATE. No oracle, no src/ dependency, nothing shared -- this assembles one 134-byte
# standalone binary from poc/s01_hres/s01.s and runs it in a DECB machine [§6].
#
# ★★ -nothrottle, per §2U: every output of this spike is a number read from the host, not a human
# judgement, so there is no reason to pace it to real time. The snapshot is a still and is unaffected.
param(
  [int]   $Stage   = 0,
  [string]$Sweep   = "",
  [int]   $Settle  = 8,
  [int]   $Samples = 4,
  [int]   $ColA    = 63,
  [int]   $ColB    = 9,
  [int]   $Seconds = 240,
  # ★★★★★ -Eye: a REAL WINDOW at NORMAL SPEED, holding one delay, no sweep [§2U.2]. Every other
  # output of this spike is a number and runs unthrottled; this one is Jay's judgement and must not.
  [switch]$Eye,
  [int]   $Dly     = 2400,   # ★ boundary at y=123 -- mid-screen, measured in the stage-0 sweep
  [int]   $FillM   = 0,
  [int]   $FillB   = 85,     # $55 = a flat field of palette index 1
  # ★★★★ The mode pair, host-poked so the 16-colour pair ($1E / $16) needs no reassembly.
  # -Stage 2 is the STATIC reference and uses VresB alone: run it at $15 and at $0D to get the two
  # endpoint profiles before any mid-frame result can be read.
  [int]   $VresT   = 0x15,
  [int]   $VresB   = 0x0D,
  # ★★★★★ -VSweep sweeps VOFFSET instead of the delay, to FIND the right value rather than derive it
  # a third time. Use with -Stage 2 and a constant fill: the correct VOFFSET is the only one whose
  # self-check passes. -Voff sets it for every other run.
  [switch]$VSweep,
  [int]   $Voff    = 0xE800,
  # ★★★★★ -Render: drop `-video none`. The static sweep produced row counts that were IDENTICAL
  # across all eight video modes at the top of the screen and mode-dependent lower down, which is
  # what a partially-rendered bitmap looks like -- and every run shares the same prior content (DECB's
  # text screen), which is why the stale part was identical. **If MAME does not rasterise a screen it
  # is not displaying, scr:pixel() reads something that is not the emulated frame.** This is the arm
  # that tests it, and it is a one-switch experiment rather than a theory.
  [switch]$Render,
  # ★★★★★ -RowMap: S-02. Calibrates colour->index, then reads the row-number fill back and reports
  # which SOURCE ROW arrives on each displayed scanline -- §3.2's address-counter question.
  [switch]$RowMap,
  [int]   $Dly2    = 0,
  [int]   $Dly3    = 0,
  # ★★★★★ -Big: the 16-colour buffer (30,720 B) via a moving window -- S-03 §4A.
  [switch]$Big,
  # ★★★★★ -RowBase: S-04 §4A(1). Shifts the row numbering to separate a value artefact from a
  # position artefact. 0 is the S-03 baseline.
  [int]   $RowBase = 0,
  # ★★★★★ -Stab N: S-04 §4B(1). Sample the boundary every frame for N frames and report the
  # distribution. 3600 frames = 60 emulated seconds.
  [int]   $Stab    = 0,
  # ★★★★★ S-05: route an interrupt to FIRQ. Bit and vector slot are swept, not assumed.
  [switch]$Firq,
  [int]   $FirqBit = 0x10,
  [int]   $FVec    = 0x010F,
  # ★★★★★ -HTab "line:vres,line:vres,...": the raster program mode 3's handler walks.
  [string]$HTab    = "",
  # ★★★★★ -BXor 0 disables the border flip -- the 30 Hz flash Jay's eye caught.
  [int]   $BXor    = 0x3F,
  # ★★★★★ -BSet writes $FF9A ONCE at init, to -BCol. Without it the register is never written at all
  # and holds whatever DECB left -- which is how every stage up to here has run.
  [switch]$BSet,
  [int]   $BCol    = 0x24,
  # ★★★★★ -FullDump: every row of the 239, four consecutive frames, run-length encoded.
  [switch]$FullDump,
  # ★★★★★ -M3Own: the raster table owns $FF98/$FF99; mode 3's loop never writes them.
  [switch]$M3Own
)
$ErrorActionPreference = "Stop"
$env:PATH = "C:\Users\jayse\DEV\cmd;C:\Users\jayse\DEV\mingw64\opt\bin;" + $env:PATH
Set-Location C:\Users\jayse\DEV\coco_agi
$LW = "C:\WIN_LWTools\lwasm.exe"

New-Item -ItemType Directory -Force build\s01 | Out-Null
& $LW --format=raw --output=build/s01/s01.bin --map=build/s01/s01.map --list=build/s01/s01.lst `
      poc/s01_hres/s01.s
if ($LASTEXITCODE -ne 0) { throw "s01 assemble failed" }
"s01.bin $((Get-Item build\s01\s01.bin).Length) bytes"

# ★★ Clear the stage's output first: an adjudicator that CAN read a previous run's artifacts WILL
# [L-92]. A stale s01_stage0.txt reads exactly like a fresh pass.
$res = "build\s01\s01_stage$Stage.txt"
if (Test-Path $res) { [IO.File]::Delete((Resolve-Path $res)) }

$env:S01_BIN = "build/s01/s01.bin"
$env:S01_MAP = "build/s01/s01.map"
$env:S01_OUT = "build/s01"
$env:S01_MODE = "$Stage"
$env:S01_COLA = "$ColA"
$env:S01_COLB = "$ColB"
$env:S01_SETTLE = "$Settle"
$env:S01_SAMPLES = "$Samples"
$env:S01_FILLM = "$FillM"
$env:S01_FILLB = "$FillB"
$env:S01_VREST = "$VresT"
$env:S01_VRESB = "$VresB"
$env:S01_VOFF  = "$Voff"
$env:S01_DLY2  = "$Dly2"
$env:S01_DLY3  = "$Dly3"
$env:S01_BIG   = $(if ($Big) { "1" } else { "0" })
$env:S01_ROWBASE = "$RowBase"
$env:S01_STAB  = "$Stab"
$env:S01_FIRQON = $(if ($Firq) { "1" } else { "0" })
$env:S01_FIRQBIT = "$FirqBit"
$env:S01_FVEC  = "$FVec"
$env:S01_HTAB  = $HTab
$env:S01_BSET  = if ($BSet) { "1" } else { "0" }
$env:S01_BCOL  = [string]$BCol
if ($FullDump) { $env:S01_FULLDUMP = "1" } else { Remove-Item env:S01_FULLDUMP -ErrorAction SilentlyContinue }
$env:S01_M3OWN = if ($M3Own) { "1" } else { "0" }
$env:S01_BXOR  = "$BXor"
if ($VSweep) { $env:S01_VSWEEP = "1" } else { Remove-Item env:S01_VSWEEP -ErrorAction SilentlyContinue }
if ($RowMap) { $env:S01_ROWMAP = "1" } else { Remove-Item env:S01_ROWMAP -ErrorAction SilentlyContinue }
if ($Eye) { $env:S01_EYE = "1"; $env:S01_SWEEP = "$Dly" }
else      { Remove-Item env:S01_EYE -ErrorAction SilentlyContinue
            if ($Sweep) { $env:S01_SWEEP = $Sweep }
            else { Remove-Item env:S01_SWEEP -ErrorAction SilentlyContinue } }

if ($Eye) {
    # ★★★ NO -nothrottle and a REAL video window. §2U.2: "an eye gate nobody can watch at 2869% is
    # not an eye gate." Screen mode is the harness default (RGB, screen_config=1) via -cfg_directory.
    "eye run: stage $Stage, dly=$Dly, NORMAL SPEED, RGB. Close the window when you have seen it."
    C:\mame\mame.exe coco3 -sound none -window -nomaximize -skip_gameinfo `
        -rompath C:/mame/roms -cfg_directory harness\mame-cfg `
        -autoboot_script C:/Users/jayse/DEV/coco_agi/poc/s01_hres/s01_run.lua -autoboot_delay 0
    $eyef = "build\s01\s01_eye$Stage.txt"
    if (Test-Path $eyef) { ""; Get-Content $eyef }
    exit 0
}

$vid = if ($Render) { @() } else { @("-video", "none") }
C:\mame\mame.exe coco3 @vid -sound none -window -nomaximize -skip_gameinfo -nothrottle `
    -seconds_to_run $Seconds -rompath C:/mame/roms -cfg_directory harness\mame-cfg `
    -autoboot_script C:/Users/jayse/DEV/coco_agi/poc/s01_hres/s01_run.lua -autoboot_delay 0

if (-not (Test-Path $res)) { "★★★ no result file -- the run produced nothing"; exit 1 }
""
Get-Content $res
