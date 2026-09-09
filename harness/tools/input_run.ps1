# harness/tools/input_run.ps1 -- the input-line gate, with a recorded invocation. [P6.25 AC-1]
#
# ★★★★★ THIS RUNNER DID NOT EXIST EITHER, AND THAT IS THE SIXTH INSTANCE. p3b_show.ps1's header
# names five (res 74-vs-1,264, cel 1-title-vs-6, pic without picgate, the VM's nine titles in an
# env var, and p3b's own eye gate). This gate was run eight times across three sessions from a
# hand-typed MAME line and a hand-typed lwasm line, neither of which is in any file -- so both had
# to be reconstructed from a report, and one reconstruction was WRONG in a way that changed a
# result. **The scope and the invocation of a gate are part of its definition** [L-45].
#
# ★★★★ THE WRONG RECONSTRUCTION IS WHY THE VOCABULARY IS NAMED HERE. Staging
# build/parser/<title>/oracle_words.bin instead of build/vm_stage/<title>/words.tok does not fail:
# it parses, and returns `egon=1 words=0` where the correct blob returns `egon=2 words=2,37`. A
# plausible wrong answer from a wrong input, with nothing in the log to say which blob was read.
#
# ★★★ TWO ARMS, ONE PREAMBLE, DELIBERATELY (§2F). They differ in exactly two things -- who supplies
# the keys, and whether MAME is throttled -- and duplicating the build into a second script is how
# the arm a person watches and the arm that gates would drift into testing different programs.
#
# usage:
#   powershell -File harness/tools/input_run.ps1                      # Jay types (eye gate)
#   powershell -File harness/tools/input_run.ps1 -Post                # scripted, headless
#   powershell -File harness/tools/input_run.ps1 -Post -Text "get rock"
param(
  # ★★★★ -Post, NOT -Interactive. The eye gate is the DEFAULT because §4A puts it first on an
  # integration task, and a default that has to be asked for is a default that gets skipped.
  [switch]$Post,
  # ★★★★ -Repro: the P6.26 arm. Drives CLEAR by ioport field assertion, which is the ONLY way to
  # script AGI's backspace -- natkeyboard posts characters and CLEAR has no character mapping, so
  # the line that diverged under Jay's hands could not be produced by any instrument until now.
  [switch]$Repro,
  # ★★★★ -Rollover: the P6.27 arm. Closes TWO matrix fields at once -- the one difference P6.26
  # left uncontrolled between a typed line and a scripted one -- and dumps IP_INBUF as the GUEST
  # sees it at `jsr par_parse`, not as the host sees it frames later on the far side of the doubt.
  [switch]$Rollover,
  [string]$Title = $(if ($env:IP_TITLE) { $env:IP_TITLE } else { "Kingquest1" }),
  [string]$Text  = "look at rock"
)
$ErrorActionPreference = "Stop"
Set-Location C:\Projects\coco_agi

$LW    = "C:\WIN_LWTools\lwasm.exe"
$stage = "build\vm_stage\$Title"
$GAMES = if ($env:VM_GAMES_ROOT) { $env:VM_GAMES_ROOT } else { "C:\Projects\agi-games\pc" }

# ★★★★ -DHAL_KEYBOARD=1 IS LOAD-BEARING AND IS IN NO OTHER FILE. Without it HAL_key_scan, the
# hal_kb_* tables and HAL_KEY_ALT are all guarded out and the assemble dies on four undefined
# symbols. ★ The guard is NOT named HAL_KEY_SCAN: lwasm matches that against the label
# HAL_key_scan and reports "Multiply defined symbol" [P6.22].
& $LW --6809 -f raw -DHAL_KEYBOARD=1 -o build/input_probe.bin --map=build/input_probe.map -I. src/harness/input_probe.s
if ($LASTEXITCODE -ne 0) { throw "input_probe assemble failed" }
"input_probe: $((Get-Item build\input_probe.bin).Length) bytes"

# ★★★★★ THE VOCABULARY IS THE GAME'S WORDS.TOK, VERBATIM. Not an oracle dump and not a
# parser-gate artifact -- see the header. It is staged into an 8,192-byte window; every WORDS.TOK
# in the corpus fits [parser.s §3].
#
# ★★★★ COPIED, NOT RE-STAGED, AND THAT IS A CORRECTION. The first version called
# `vm_stage.py --out $stage` to produce it, which RE-DERIVED THE WHOLE STAGE DIRECTORY and did not
# write words.tok at all -- vm_stage.py emits it only alongside an --input script -- so a runner
# written to guarantee the file present is what deleted it. **A repair step that rebuilds more
# than the thing it is repairing can destroy its own precondition.**
# ★★★ §2P: the game directory is opened READ-ONLY and the bytes land in build/, which is
# untracked. Nothing here writes to the game.
$vocab = "$stage\words.tok"
if (-not (Test-Path $vocab)) {
  $src = Join-Path (Join-Path $GAMES $Title) "WORDS.TOK"
  if (-not (Test-Path $src)) { throw "no WORDS.TOK for $Title at $src" }
  New-Item -ItemType Directory -Force $stage | Out-Null
  Copy-Item $src $vocab
}
"vocabulary: $vocab ($((Get-Item $vocab).Length) bytes)"

$env:IP_PROG  = "build/input_probe.bin"
$env:IP_MAP   = "build/input_probe.map"
$env:IP_VOCAB = ($vocab -replace '\\','/')
$env:IP_WATCH = "1"
$env:IP_LOOP  = "1"

if ($Rollover) {
  # ═══════════════════════════════════════════════════════════════════════════════════════
  # ★★★★ P6.27. Two matrix fields closed at once -- the one difference P6.26 left between the
  # line a person typed and the line an instrument typed -- plus IP_SNAP, the guest's own copy
  # of IP_INBUF taken at `jsr par_parse`. ★★ -nothrottle: every output is a byte comparison.
  Remove-Item Env:IP_NOPOST -ErrorAction SilentlyContinue
  C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo -nothrottle `
    -video none -sound none -seconds_to_run 180 `
    -rompath C:/mame/roms `
    -autoboot_script harness/tools/rollover_probe.lua -autoboot_delay 0 2>$null |
    # ★★★★ ASCII ANCHORS ONLY, AND THAT IS NOT A STYLE CHOICE. Windows PowerShell 5.1 parses a
    # UTF-8 .ps1 without a BOM as ANSI, so a star inside a -Pattern here is mojibake by the time
    # Select-String sees it and matches nothing. The first run of this arm silently dropped the
    # driver's dropped-key report AND the final verdict -- the two lines that decide the task --
    # while printing every table around them, which reads exactly like a run that had no verdict.
    Select-String -Pattern @('===','vocabulary','IP_SNAP','driver','dropped','ignature',
                             'snapshot','SNAPSHOT','negative','trigger','FAULT arm',
                             'keys=','both down','A released','step \d','^\s+[0-9A-F][0-9A-F] ',
                             '^\s+(snap|after)\s+\|','^(F|B\d|S\d|P) ') |
    ForEach-Object { $_.Line }
  exit 0
}

if ($Repro) {
  # ═══════════════════════════════════════════════════════════════════════════════════════
  # ★★★★ -nothrottle: every output of this arm is a byte comparison, not a human judgement
  # (§2U). ★★ IP_NOPOST is irrelevant here -- backspace_repro.lua never touches natkeyboard,
  # it asserts matrix fields directly, so nothing can own the port and clear the other.
  Remove-Item Env:IP_NOPOST -ErrorAction SilentlyContinue
  C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo -nothrottle `
    -video none -sound none -seconds_to_run 120 `
    -rompath C:/mame/roms `
    -autoboot_script harness/tools/backspace_repro.lua -autoboot_delay 0 2>$null |
    Select-String -Pattern 'arm|===|vocabulary|plain|backsp|FAULT|inbuf|parse |★|^\s+[0-9A-F][0-9A-F] ' |
    ForEach-Object { $_.Line }
  exit 0
}

if ($Post) {
  # ═══════════════════════════════════════════════════════════════════════════════════════
  # ★★★★★ THE SCRIPTED ARM, AND IT IS THE CONTROL THAT SETTLED P6.25. natkeyboard posts exactly
  # the characters given and exactly one Enter -- a control a human at the keys CANNOT produce,
  # which is what separated a real second Enter from an invented one after three sessions of
  # instrumenting the key path. Keep it: the value is in being able to script an exact event
  # count, not in the convenience.
  # ★★ -nothrottle: nothing here is a human judgement (§2U). The eye-gate arm below never gets it.
  Remove-Item Env:IP_NOPOST -ErrorAction SilentlyContinue
  $env:IP_TEXT = $Text
  C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo -nothrottle `
    -resolution 640x480 -seconds_to_run 14 `
    -rompath C:/mame/roms `
    -autoboot_script harness/tools/input_gate.lua -autoboot_delay 0 2>$null |
    Select-String -Pattern 'line \d|staged|run complete|no progress|★★★' | ForEach-Object { $_.Line }
  exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ IP_NOPOST=1 IS A FLAG AND NOT AN EMPTY IP_TEXT, BECAUSE **POWERSHELL DELETES AN
# ENVIRONMENT VARIABLE ASSIGNED THE EMPTY STRING**. `$env:IP_TEXT=""` made os.getenv return nil,
# the Lua's `or` fell through to its default, and the probe scripted a line into what was supposed
# to be a live keyboard -- twice, reproducing byte for byte (17 keys, egon=2, words 2,37), which is
# the only reason it was caught: a human typing twice does not produce identical counts.
$env:IP_NOPOST = "1"
Remove-Item Env:IP_TEXT -ErrorAction SilentlyContinue

# ★★★★★ NO -nothrottle. §2U.2: an eye gate nobody can watch at 2869% is not an eye gate.
# ★★★ The gate also rebinds host Backspace onto CoCo3 CLEAR for this arm only (input_gate.lua):
# the CoCo3 has no Backspace key, AGI's backspace is CLEAR, and MAME binds the PC's Backspace to
# the LEFT ARROW -- which the input line correctly discards as a movement key, so a working
# backspace looks broken. Arrows stay movement keys because AGI walks ego with them.
"the input line is yours -- type, Backspace corrects, Enter submits; close the window when done"
C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo `
  -resolution 1280x960 `
  -rompath C:/mame/roms `
  -autoboot_script harness/tools/input_gate.lua -autoboot_delay 0 2>$null |
  Select-String -Pattern 'line \d|DECB|taking|staged|LIVE|Backspace|rebind|run complete|★★★' | ForEach-Object { $_.Line }
