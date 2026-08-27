# harness/tools/sierra_live.ps1 -- launch Sierra's own 1988 CoCo3 AGI interpreter under
# observation, for an OPERATOR to drive. One command; nothing to re-derive.
#
#   powershell -File harness\tools\sierra_live.ps1
#   powershell -File harness\tools\sierra_live.ps1 -Out build\my_run -Game LSL
#
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★ WHAT YOU HAVE TO TYPE. The Lua sends NO input -- it cannot, by design (see the header
# of sierra_live.lua: ioport_field:set_value() is a PERMANENT override and steals CTRL from
# you for the whole session). So the boot is yours, and it is two steps:
#
#     1. At the DECB prompt:            DOS   then ENTER
#     2. Wait ~25 s. /d0/Startup asks which display you are using. Answer:
#                                       R     (CAPITAL -- shift+r)   then ENTER
#        ★ Do NOT answer early. The prompt is not up for roughly 25 seconds, and input sent
#          before it exists lands in the shell, runs Startup off the end of its input, and
#          OS-9 prints EOF at a repeating prompt. Waiting for the CPU to look idle does NOT
#          work either -- it idles during disk waits too.
#     3. Play. Movement is CTRL + a letter. Ctrl+BREAK is mapped to CTRL+DELETE (see below).
#
# ★★ CONTROLLER PORTS. The Lua sets both :ctrl_sel ports to Unconnected on startup. Both
# default to "Joystick" and the interpreter polls the joystick, so with the default every key
# arrives correctly on the CoCo3 matrix and NOTHING RESPONDS. This looks exactly like a wrong
# keyboard mapping and is not one.
#
# ★ KEYS THAT DO NOT WORK, measured live on :row6, not assumed:
#     End, Insert   -- never arrive; MAME's UI takes them
#     Left Alt      -- reaches MAME, but Windows grabs it (you get a system beep)
#   BREAK is therefore bound to DELETE in the tracked cfg.
# ═══════════════════════════════════════════════════════════════════════════════════════════
#
# ★★ AFTERWARDS, THE MEASUREMENT IS OFFLINE:
#     python harness\tools\sierra_rooms.py <Out>\frames.csv
#   The ROOM CHANGE lines the Lua prints while you play are CANDIDATES. The offline tool is
#   the instrument -- it can see the whole run, which is what coalescing a fragmented disk
#   cluster needs, and it is what any quoted figure must come from.

param(
    [string]$Out   = "build\sierra_live",
    [string]$Game  = "KQ3",
    [string]$Mame  = "C:\mame\mame.exe",
    [string]$Roms  = "C:\mame\roms",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repo

# --- media -----------------------------------------------------------------------------
# ★★ §2P: the corpus disk is the user's game and is NEVER mounted directly -- MAME opens
# floppies READ-WRITE. A fresh copy is made every run, so a session that writes to the disk
# cannot reach the original and cannot accumulate across runs either.
$corpus = @{
    "KQ3" = "C:\Projects\agi-games\coco3\King's Quest III (Sierra On-Line) (OS-9) (Coco 3)\Floppy 360K\kq3-1.dsk"
    "LSL" = "C:\Projects\agi-games\coco3\Leisure Suit Larry (Sierra On-Line) (OS-9) (Coco 3)\Floppy 360K\lsl-1.dsk"
}
if (-not $corpus.ContainsKey($Game)) { throw "unknown -Game '$Game'; known: $($corpus.Keys -join ', ')" }
$src = $corpus[$Game]
if (-not (Test-Path -LiteralPath $src)) { throw "corpus media not found: $src" }

# ★ KQ3 'Original' is NOT usable single-drive: KQ3-1-1.DSK carries the AGI DIRECTORY files
# and ZERO vol.* -- it can name every resource and load none. 'Floppy 360K' has boot plus
# vol.0,1,2,3,12 on one image. This is a deliberate deviation and it costs resource
# authenticity, not interpreter authenticity.
$known = @{ "KQ3" = "20EA31A82087DA90" }        # sha256[0..15] of the image P3.6 measured
$h = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.Substring(0, 16)
if ($known.ContainsKey($Game) -and $h -ne $known[$Game]) {
    Write-Warning "media hash $h != the $($known[$Game]) P3.6 measured -- figures may not compare"
} else {
    Write-Host "media OK  $Game  sha256[0:16]=$h"
}

$work = Join-Path $env:TEMP "sierra_media"
New-Item -ItemType Directory -Force $work | Out-Null
$disk = Join-Path $work "live.dsk"
Copy-Item -LiteralPath $src -Destination $disk -Force

# --- cfg -------------------------------------------------------------------------------
# ★★ MAME REWRITES ITS CFG DIRECTORY ON EXIT. Pointing -cfg_directory at the repo would let
# a run edit its own tracked inputs -- silently, and only visible as a later diff. So the
# tracked cfg is a SEED: copied out to a temp directory, and MAME's write-back lands there.
$cfgSeed = Join-Path $repo "harness\mame-cfg\sierra-live\coco3.cfg"
if (-not (Test-Path -LiteralPath $cfgSeed)) { throw "missing tracked cfg seed: $cfgSeed" }
$cfgDir = Join-Path $env:TEMP "sierra_cfg"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
Copy-Item -LiteralPath $cfgSeed -Destination (Join-Path $cfgDir "coco3.cfg") -Force

$shots = Join-Path $repo "$Out\shots"
New-Item -ItemType Directory -Force $shots | Out-Null
$env:SIERRA_OUT = $Out

# --- syntax check before handing the machine over --------------------------------------
# ★ A Lua syntax error kills a run several minutes in, after the operator has already booted
# OS-9 and started playing. Two emulated seconds headless costs nothing and catches it.
Write-Host "checking sierra_live.lua loads..."
$chk = & $Mame coco3 -window -skip_gameinfo -nothrottle -seconds_to_run 2 `
    -rompath $Roms -cfg_directory $cfgDir `
    -autoboot_script (Join-Path $repo "harness\tools\sierra_live.lua") -autoboot_delay 0 2>&1
$bad = $chk | Select-String -Pattern "lua|error|Fatal" -CaseSensitive:$false
if ($bad) { $bad | ForEach-Object { Write-Host $_ }; throw "sierra_live.lua did not load -- not launching" }
Write-Host "  OK"
if ($CheckOnly) { return }

# --- launch ----------------------------------------------------------------------------
# ★ -snapview auto -snapsize 640x480 -keepaspect: the DEFAULT (-snapview native) writes
# SQUARE pixels, 640x239, and every still comes out stretched ~2x horizontally.
Write-Host ""
Write-Host "LAUNCHING. Type:  DOS <ENTER>   ...wait ~25 s...   R <ENTER>   (capital R)"
Write-Host "Ctrl+BREAK = CTRL+DELETE.  Movement = CTRL + letter.  Log: $Out\run.log"
Write-Host ""
& $Mame coco3 -ext fdc -flop1 $disk `
    -window -nomaximize -skip_gameinfo `
    -rompath $Roms -cfg_directory $cfgDir -snapshot_directory $shots `
    -snapview auto -snapsize 640x480 -keepaspect `
    -autoboot_script (Join-Path $repo "harness\tools\sierra_live.lua") -autoboot_delay 0

Write-Host ""
Write-Host "run finished. THE MEASUREMENT IS OFFLINE:"
Write-Host "    python harness\tools\sierra_rooms.py $Out\frames.csv"
