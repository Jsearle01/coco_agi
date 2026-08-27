# harness/tools/roomshots.ps1 -- capture rendered rooms for the AC-9 eye-gate.
#
# ★★ §2P: A RENDERED ROOM IS COPYRIGHTED CONTENT. Nothing this writes goes into the repo.
# Captures land in C:\karateka-capture\agi_captures\ (Jay's, outside the working tree).
#
# ★★★ THREE THINGS THIS ASSERTS RATHER THAN INHERITS, each of which was a rejected capture once:
#   -DPIC_PRESENT      HAL_gfx_swap, NOT HAL_gfx_present. The HAL has two flips; the legacy one
#                      points VOFFSET at physical $78000, 352 KB from the pixels (idiom 19j).
#   Monitor Type = RGB pic_sweep.lua sets it from Lua and LOGS it. MAME's coco3 defaults to
#                      COMPOSITE, and the AGI palette is undefined there (idiom 11l, design §2.2).
#   -snapview auto     the default is 'native' = SQUARE pixels: 640x239, ratio 2.678 against a
#   -snapsize 640x480  CoCo3's 4:3. Every capture was stretched ~2x until this was set
#   -keepaspect        (idiom 19k). The PNG's IHDR is read back below to verify, not assumed.
#
# ★ -cfg_directory points at scratch: MAME rewrites <machine>.cfg on exit and would strip the
#   authored comment block out of dist/mame-cfg/rgb/coco3.cfg (idiom 19i).
#
# Usage:  roomshots.ps1 [-Tag p3.5] [-Rooms Kingquest1-080,Kingquest2-094,Kingquest3-074]
param(
  [string]   $Tag   = "manual",
  [string[]] $Rooms = @("Kingquest1-080", "Kingquest2-094", "Kingquest3-074"),
  [string]   $Dest  = "C:\karateka-capture\agi_captures"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $repo

$scratch = Join-Path $env:TEMP "coco_agi_shots"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratch "cfg") -Force | Out-Null
Remove-Item (Join-Path $scratch "shots\coco3\*.png") -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $Dest -Force | Out-Null

& C:\WIN_LWTools\lwasm.exe --format=raw --output=build/pic_snap.bin `
    -I. -DHAL_GFX_MODE_SERVICE -DPIC_PRESENT src/harness/pic_probe.s
if ($LASTEXITCODE -ne 0) { throw "assemble failed" }

$Rooms | Set-Content build\picset\rooms.txt
$env:PIC_OUT = "build/roomshots"; $env:PIC_LIST = "build/picset/rooms.txt"
$env:PIC_RESDIR = "build/picset"; $env:PIC_PROG = "build/pic_snap.bin"
$env:PIC_PLANES = "0"; $env:PIC_SNAP = "1"
Remove-Item Env:PIC_FAULT_ON -ErrorAction SilentlyContinue

C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo -nothrottle -seconds_to_run 300 `
  -rompath C:/mame/roms -cfg_directory (Join-Path $scratch "cfg") `
  -snapshot_directory (Join-Path $scratch "shots") `
  -snapview auto -snapsize 640x480 -keepaspect `
  -autoboot_script (Join-Path $repo "harness/tools/pic_sweep.lua") -autoboot_delay 0 | Out-Null
Remove-Item Env:PIC_SNAP

# MAME numbers snapshots 0000, 0001, ... in the order they were taken, which is $Rooms order.
$png = Get-ChildItem (Join-Path $scratch "shots\coco3") -Filter *.png | Sort-Object Name
if ($png.Count -ne $Rooms.Count) {
  throw "expected $($Rooms.Count) snapshots, got $($png.Count) -- check build/roomshots/run.log"
}
for ($i = 0; $i -lt $png.Count; $i++) {
  $out = Join-Path $Dest ("agi-{0}-{1}-RGB-4x3.png" -f $Tag, $Rooms[$i])
  Copy-Item $png[$i].FullName $out -Force
  # ★ verify the DELIVERED file's aspect from its IHDR rather than trusting the flags
  $b = [System.IO.File]::ReadAllBytes($out)
  $w = [int]$b[16]*16777216 + [int]$b[17]*65536 + [int]$b[18]*256 + [int]$b[19]
  $h = [int]$b[20]*16777216 + [int]$b[21]*65536 + [int]$b[22]*256 + [int]$b[23]
  $r = [math]::Round($w / $h, 3)
  "{0,-46} {1}x{2}  ratio {3} {4}" -f (Split-Path $out -Leaf), $w, $h, $r, `
    $(if ([math]::Abs($r - 1.333) -lt 0.01) { "" } else { "  ★ NOT 4:3" })
}
"captures -> $Dest"
