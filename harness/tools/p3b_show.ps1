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
  [switch]$Diag,
  [switch]$NoMap,
  [switch]$Win3,
  [switch]$FlatVocab,
  [switch]$SaidDiag,
  [switch]$Var0Diag,
  [switch]$IfDiag,
  # ★★★★★ -ResCheck IS T-P0-103's INSTRUMENT: do the resident resource bytes still match what was
  # loaded? Baseline at the LOGIC bind (after the decode, the seam the res gate is aligned to),
  # verify on every later bind, on a VIEW before it is released, and in an end-of-run sweep.
  # ★★★ -CovFault is its fault arm and needs three flags together: the counters back in the arena
  # (-DP3B_FAULT_COV_ARENA), the counters actually built (-DP3B_COVERAGE), and the P6.47 assertion
  # deliberately bypassed (-DP3B_ACCEPT_COV_ARENA). **The assertion is not weakened; it is told, by
  # name, that this one caller means it.**
  [switch]$ResCheck,
  [switch]$CelCheck,
  [switch]$CovFault,
  # ★★★★ -RawVis IS T-P0-109's FAULT ARM: co_put_visual stores the raw colour index instead of
  # doubling it into both nibbles. **That is exactly the behaviour this task replaced**, so its
  # red is a state the project has already seen on a screen rather than an invention [§2W].
  [switch]$RawVis,
  # ★★★★★ -NoCount IS T-P0-101's ABLATION. VM_OPSEEN ($6400) and VM_TESTSEEN ($6300) sit INSIDE the
  # residency arena's window ($6000-$A000), so every dispatched opcode increments a byte of whatever
  # resource the arena has mapped there. -DVM_NOCOUNT removes both counters and nothing else, which
  # is the one-variable arm [L-73] that turns "the counters are writing into logic 102" from an
  # address coincidence into a measurement. It composes with any arm above.
  [switch]$NoCount,
  # ★★★★★ -NoRestore IS T-P0-112's FAULT ARM, AND IT IS A KNOWN-GOOD RED [§2W]. It removes the
  # single `jsr p3_restore_prev` and nothing else (-3 B, measured), so sprite rectangles are never
  # put back and an animating sprite accumulates the union of its cels as a filled rectangle
  # behind itself. ★★★★ THAT IS NOT AN INVENTED FAULT: it is exactly what every build before
  # T-P0-112 did, and what Jay reported at the first side-by-side -- "the port still shows a
  # squarish background while the oracle shows that area as transparent". ★★★ A fault arm whose
  # red the project has already seen on a screen is the strongest kind there is.
  [switch]$NoRestore,
  # ★★★★ -AlwaysRestore IS T-P0-114's FAULT ARM. It forces the changed/unchanged test TRUE, so
  # every recorded rectangle is erased and repainted -- which is exactly P6.58's behaviour and
  # therefore a KNOWN-GOOD RED: Jay has already watched it blink. ★★★ Differencing it against the
  # clean arm is also AC-2's census, because the two builds differ in one variable and the gap in
  # p3_restbytes IS the bytes not touched for unchanged sprites.
  [switch]$AlwaysRestore,
  # ★★★★ -NoJoin IS T-P0-115's FAULT ARM: p3_poll_dir returns immediately, so a key is scanned by
  # nothing and VAR_EGO_DIRECTION is never written. ★★★ A KNOWN-GOOD RED -- it is every build
  # before this task, and Jay has already reported it: "he doesn't move and i can't move him".
  [switch]$NoJoin,
  # ★★★★ -PresentAll IS T-P0-116's FAULT ARM: p3_present copies all four apertures again instead
  # of stopping at the game screen, so the picture clear's white lands on the text area. ★★★ A
  # KNOWN-GOOD RED -- it is every build before this task, and Jay reported it at the side-by-side:
  # "the text area is white again. we had it changed to black as it should be."
  [switch]$PresentAll,
  # ★★★★★ -NoShowPic IS T-P0-121's FAULT ARM: show.pic stays `vm_op_modelled` and NOTHING ELSE
  # changes. draw.pic still renders the room into the shadow, so every byte gate that reads the
  # shadow still passes and the screen never shows the picture. ★★★★ It is the §4A.1 shape in
  # miniature -- a plane that is right and is never presented, which is AD-114 exactly -- and it
  # is the arm that proves §1.2's ruling: if the picture still appears, something other than
  # show.pic is presenting it. ★★★ Expect `draw.pic drew=1  show.pic shown=0` in the summary.
  [switch]$NoShowPic,
  # ★★★★★ -NoCloseWindow IS T-P0-122's FAULT ARM AND IT IS A KNOWN-GOOD RED: it removes the single
  # `jsr txt_close` from show.pic and nothing else, which is EVERY BUILD BEFORE THIS TASK. ★★★★ Jay
  # has already reported its red, in his own words: "i see a 'press a key to continue' in the text
  # area which doesn't appear in the oracle". ★★★ A fault whose red the operator has already
  # described is the strongest kind there is [the -NoRestore precedent, same reasoning].
  [switch]$NoCloseWindow,
  # ★★★★★ -NoRoomJump TURNS OFF THE EYE GATE'S DEFAULT ROOM JUMP [T-P0-122]. p3b_room.lua reads
  # `os.getenv("P3B_ROOM") or "1"`, so the LIVE path jumps to room 1 at cycle 8 unless told not
  # to, while the HEADLESS path defaults to no jump at all. **Without this switch there was no way
  # to show Jay the title screen past cycle 8**, which is where the credits scroll, and three
  # tasks' worth of "the text doesn't scroll" were reports about a run that had left the title
  # screen. ★★★ It sets P3B_ROOM=0, which p3b_run.lua already understands as "no jump".
  [switch]$NoRoomJump,
  # ★★★★★ -NoVarKey IS T-P0-124's FAULT ARM: p3_poll_dir stops publishing VAR 19 on a
  # non-direction key, and nothing else changes. That is EVERY BUILD BEFORE THIS TASK, and its red
  # is one Jay has already described three times -- the title screen never advances, the
  # 'press a key to continue' line never goes, and the alligators never draw [P6.69, P6.70].
  # ★★★ Expect draw 0, set.view 0, clear.lines 0 and the room unchanged, against 4/3/1 with it in.
  [switch]$NoVarKey,
  [switch]$NoClearLines,
  # ★★★★ -SprStats records WHY a staged sprite is dropped before the blit: p3_composite_all's
  # res_open failure path has always skipped silently [T-P0-127]. Flag-guarded, so every shipped
  # arm stays byte-identical; the three bytes and four instructions exist only in this arm.
  [switch]$SprStats,
  # ★★★★★ -NoVblKeys IS T-P0-128's FAULT ARM: the combined arm goes back to scanning the matrix once
  # per interpreter cycle, at LEVELS. That is every build before this task and a known-good red in
  # Jay's own words: "i was not able to control graham reliably."
  [switch]$NoVblKeys,
  # ★★★★★ -VblKeys IS NOW A NO-OP, KEPT SO OLD COMMAND LINES STILL RUN [T-P0-132]. The latch SHIPS
  # in the combined arm: what it was judged on at T-P0-128 was P6.78's data corruption, not the
  # latch [p3b_probe.s's note]. -NoVblKeys is the fault arm.
  [switch]$VblKeys,
  # ★★★★ -RoomDrive IS THE COMPARISON ARM, NOT A FAULT: it restores the retired p3_room_check
  # driver, so the picture is rendered and presented by room DETECTION as it was before this
  # task. **The claim "the game now drives the render" needs an arm where it does not** [§2W].
  [switch]$RoomDrive,
  # ★★★★★ -Combined IS T-P0-120's THIRD SHAPE: the text engine AND the cel/composite path in one
  # binary, which no build has ever had. text.s is `org`ed into slot 7's hole above the font
  # ($EBBA), because region A cannot hold both halves -- P6.64 measured that at 513 B over.
  # ★★★ It is not a fault arm and not a variant of -Text: P3B_NO_CEL keeps its own meaning and the
  # six text arms stay byte-identical. This adds a shape rather than changing one.
  [switch]$Combined,
  # ★★★★★ -Count IS T-P0-130's COUNTING ARM. The shipped combined arm no longer counts pixels
  # (COMP_NOCOUNT, p3b_probe.s's flag block); -Count puts the four compositor counters back for the
  # readouts that need them -- P3B_SPRITES' "compositor:" line and the rectangle census's co_* rows.
  # ★★★ Without it those readouts say the counters are OFF rather than printing zeros, because a
  # zero reads as "nothing composited" [P6.74's silent drop is the precedent].
  [switch]$Count,
  # ★★★★ -ViewHdrTest / -ViewFaultOneMap: T-P0-130 AC-8. The first runs set.view on P3B_VIEWTEST's
  # view once, in the VM phase, and publishes what the in-place header read produced; the second
  # makes that read's two-byte fields map the window ONCE, which is wrong exactly at a straddle.
  [switch]$ViewHdrTest,
  # ★★★★ -LevelKeys IS T-P0-131's FAULT ARM: p3_key_edge returns the matrix LEVEL again, which is
  # every build before this task. A known-good red in Jay's words: "the new build didnt move him".
  [switch]$LevelKeys,
  # ★★★★ -IfRec: the `if` recorder (-DVM_IFDIAG -DVM_SAIDDIAG) added to WHATEVER configuration is
  # being built, not only -IfDiag's text arm [T-P0-131]. The combined arm diverges from the reference
  # where the text arm does not, so the recorder is needed where the divergence is.
  [switch]$IfRec,
  # ★★★★★ -NoPlaneReset IS T-P0-131's SECOND FAULT ARM: p3_composite_all stops invalidating
  # plane_win's slice cache after the VIEW fetch, so co_put_visual writes sprite pixels into the
  # staged volume. Every build before this task; a known-good red (logic 1 corrupted by cycle 18).
  [switch]$NoPlaneReset,
  [switch]$ViewFaultOneMap,
  [switch]$NoIrq,
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
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ -DP3B_IRQ IS NOW PART OF THE TEXT CONFIGURATION, NOT AN OPT-IN [Jay's ruling].
# print's wait loop paces off hal_frame, and no probe had ever advanced it because the CoCo3's
# vector chain has two hops and this probe's MMU remap destroys the first [a07895e]. Without
# interrupts the loop cannot exit, so a text build without them cannot run the code it exists to
# test. **It belongs in the configuration, not behind a switch nobody remembers to pass.**
# ★★★★ EVERY TEXT ARM GETS IT, SO EACH FAULT ARM DIFFERS FROM THE CLEAN ARM BY EXACTLY ONE
# VARIABLE. Adding it to -Text alone would have left -NoTick differing by two things, which is
# L-73's ablation defect: an arm that moves two variables cannot exonerate either.
# ★★★ -NoIrq still turns it off, so the loop remains runnable in BOTH directions -- IRQs off is
# the measured hang [P6.31], IRQs on is the fix. §2W needs that to stay reachable.
# ★★ `p3b` never gets it: that row is purpose=timing and an interrupt every 16.667 ms would move
# every figure in it. The cel build stays byte-identical at 58AD3C27.
$IRQ = if ($NoIrq) { @() } else { @("-DP3B_IRQ") }
if ($Text)  { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD") + $IRQ }
if ($Fault) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_MODELLED") + $IRQ }
# ★★★★★ -DecodeFault IS AC-4's ARM AND ITS CONSUMER IS NOW vm_run.s [T-P0-084h]. The decode moved
# off res_open's miss path to the LOGIC bind, so the fault moved with it: -DRES_FAULT_DECODE_HIT
# drops the `bcs vbl_nodec`, and the decode then runs on EVERY bind including cached ones.
# ★★★★ res_decode XORs IN PLACE, so a cached resource is re-encrypted on every re-bind: the first
# bind is right and every later one is garbage. L-66 measured 3.01 binds per cycle.
# ★★★ It exists so the fresh-open placement can be FALSIFIED rather than trusted, and it is RUN in
# both directions: clean 16 of 16 printable (DECODED), fault NOT DECODED [§2W, L-62 -- re-shown on
# the build that shipped].
if ($DecodeFault) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DRES_FAULT_DECODE_HIT") + $IRQ }
# ★★★★★ -NoTick IS AC-8's FAULT ARM AND IT IS ONE OMITTED `jsr vm_step_clock` [§2W.1]. print's wait
# loop measures var 21 as a mark on the GAME clock, exactly as the oracle does [text.cpp:395-409,
# cycle.cpp:558], so a loop that does not tick that clock can never reach the mark and the box hangs
# forever. **The headless watchdog is the instrument under test and it must FIRE** -- a green
# headless run is evidence only once this arm has been seen to go red.
# ★★★★ The arm is 3 bytes smaller than the clean build, which is the `jsr` and nothing else. A fault
# arm that hung by some other route would prove the watchdog works and nothing about this loop.
if ($NoTick) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_FAULT_NOTICK") + $IRQ }
# ★★★★★ -Diag IS §4A's DIFFERENTIAL ARM [T-P0-087]. tx_msgptr is one routine with two callers;
# display substitutes and print does not, so it records both callers' INPUTS in one run rather than
# auditing arithmetic that is identical either way. Records live in MAP_INPUT's tail, not the code
# region. ★★ Diagnostic only -- not in the clean build, not in any gate row.
if ($Diag) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTX_MSGDIAG") + $IRQ }
# ★★★★★ -NoMap IS THE VOCABULARY WINDOW's FAULT ARM [T-P0-091, §2W]. -DP3B_VOCAB_NOMAP drops ONE
# `jsr phase_vocab_in` from p3_feed -- 3 bytes, and nothing else differs from the clean arm [L-73].
# ★★★★ par_find then computes `vocab + letter*2` from $A000 while slot 5 still holds the VM OBJECT
# TABLE, so every word comes back unknown and p3b_run.lua's parse readback reports 0 words.
# ★★★ IT EXISTS BECAUSE THE CLEAN ARM'S GREEN IS OTHERWISE UNEARNED. A dictionary read through a
# window that was never opened still reads SOMETHING; the run does not crash and the box still
# draws. **The only way to know the window is load-bearing is to shut it and watch the parse fail.**
if ($NoMap) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DP3B_VOCAB_NOMAP") + $IRQ }
# ★★★★★ -Win3 IS THE TEXT WINDOW's FAULT ARM [T-P0-093, §2W]. -DTEXT_WIN3 changes ONE constant --
# the number of character rows text.s is told the window holds, 25 back to 19 -- and nothing else.
# ★★★★ THAT REPRODUCES P6.37's GEOMETRY EXACTLY: txt_blit refuses `crow >= txt_fbrows` and
# tx_boxfill's yhi is fbrows*8, so rows 0-18 draw and row 22 is declined in silence. The box still
# draws, the parse still fires, the run still completes -- **the command line simply is not there**,
# which is the defect this task fixed, reproduced rather than reconstructed.
# ★★★ IT DOES NOT CHANGE THE MAPPING. An arm that mapped three slots would put an MMU write back
# into vm_text_ops.s, which is the thing this task removed -- the fault would have re-created the
# defect it is meant to detect [AC-2], and it would move two variables instead of one [L-73].
if ($Win3) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_WIN3") + $IRQ }
# ★★★★★ -FlatVocab IS T-P0-095's ONE-VARIABLE ARM. P6.39 showed the restart absent in the CEL build,
# whose dictionary is flat -- but cel and text differ in five things, so "the window" was one
# candidate of five. -DTEXT_VOCAB_FLAT removes ONLY the window: the text build keeps its relocated
# tables, its seed stack, its font address, its input.s and its four-slot text window.
# ★★★★ IT CARRIES -DTEXT_MODELLED ITSELF rather than being combined with -Fault, and that is the
# whole point: **P6.39's arm B is -Fault with the jump and the input, and this must differ from it
# by exactly one flag.** Composing two switches would also pass -DP3B_NO_CEL twice, which lwasm
# rejects -- so the arm is spelled out once, here, and cannot drift from its control.
# ★★ Measurement only: it holds one title's dictionary and is in no gate row [p3b_probe.s].
if ($FlatVocab) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_MODELLED","-DTEXT_VOCAB_FLAT") + $IRQ }
# ★★★★★ -SaidDiag RECORDS ONE ROW PER said() IN ONE CYCLE [T-P0-098 §1.3]. The reference's side of
# this question is answered by test_trace.py and needs no emulator; the PORT's needs the guest to
# publish, because MAME's write tap cannot see a direct-page store [P6.42 §4C].
# ★★★★ It carries -DTEXT_MODELLED so it differs from P6.39's arm B by exactly one flag, the same
# discipline the flat-vocabulary arm follows.
# ★★ Diagnostic only: in no gate row, and every shipped artifact is byte-identical without it.
if ($SaidDiag) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_MODELLED","-DVM_SAIDDIAG") + $IRQ }
# ★★★★★ -Var0Diag RECORDS EVERY WRITER OF VAR 0 IN ONE CYCLE, WITH ITS CALLER. P6.43 ended with
# every predicate agreeing and the room changing anyway, so the next instrument is keyed on the
# EFFECT rather than on the three commands I would have guessed [T-P0-098 §8.1].
# ★★ Same discipline as the other diagnostic arms: -DTEXT_MODELLED so it differs from P6.39's arm B
# by one flag, and every shipped artifact is byte-identical without it.
if ($Var0Diag) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_MODELLED","-DVM_VAR0DIAG") + $IRQ }
# ★★★★★ -IfDiag RECORDS EVERY `if` IN ONE LOGIC AND THE ARM IT TOOK [T-P0-101 §4A]. P6.45 read flag
# 4 at a variable write deep inside logic 102's body and found it SET -- which is equally consistent
# with "the guard saw it clear and the body set it" and "the guard never ran". Only an instrument
# keyed on the INSTRUCTION separates those, because a guard that never ran leaves no row.
# ★★★★ IT CARRIES -DVM_SAIDDIAG TOO, and that is deliberate rather than convenient: hypothesis one
# is that logic 102's own said() chain sets flag 4, and confirming or killing it needs both tables
# **from the same run and the same cycle**. Two runs would be two scenarios [L-82].
# ★★ Same discipline as the other diagnostic arms: -DTEXT_MODELLED so it differs from P6.39's arm B
# by one flag, and every shipped artifact is byte-identical without it.
if ($IfDiag) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_MODELLED","-DVM_IFDIAG","-DVM_SAIDDIAG") + $IRQ }

# ★★★★ -ResCheck is a TEXT-configuration arm and cannot be a cel one [T-P0-103 §4D]. The cel arm's
# region A ends at $52F8 with CP_CEL at $5300 -- EIGHT bytes -- and the instrument's code needs 518.
# Its tables are already out of the image, in MAP_COVERAGE; the code cannot be.
if ($ResCheck) { $FLAGS += @("-DP3B_NO_CEL","-DHAL_KEYBOARD","-DTEXT_MODELLED","-DRES_CHECKSUM") + $IRQ }
# ★★★★★ -CelCheck IS THE ARM T-P0-103 COULD NOT BUILD [P6.48 §6.2]. The checksum needs 518 bytes of
# region A and the cel arm had EIGHT, because CP_CEL started at $5300. With the buffer down to one
# row the ceiling is $5F00 and there is room -- **so the cel path can finally be watched by the
# instrument that would have caught the defect this task just fixed.**
# ★★★ It is the CEL configuration deliberately: -ResCheck carries -DP3B_NO_CEL and therefore never
# decodes a cel, which is exactly the coverage hole.
if ($CelCheck) { $FLAGS += @("-DRES_CHECKSUM") }
# ★★★★ -DP3B_ACCEPT_CEL_ARENA WAS HERE AND IS RETIRED [T-P0-105 §4D]. It accepted CP_CEL's
# 1,456-byte overlap with RES_ARENA for exactly one task, while the shape was Jay's ruling. The
# buffer is one ROW now and the assertion passes on its own terms, so the flag is deleted rather
# than left unused -- **an acceptance flag that outlives its defect is how a known defect becomes
# invisible**, and an unused one reads as a configuration somebody might still want.
# ★ Appended last so they compose with every arm above rather than being spelled into each one.
if ($CovFault) { $FLAGS += @("-DP3B_COVERAGE","-DP3B_FAULT_COV_ARENA","-DP3B_ACCEPT_COV_ARENA") }
if ($RawVis)   { $FLAGS += "-DCOMP_FAULT_RAW_VIS" }
if ($NoCount) { $FLAGS += "-DVM_NOCOUNT" }
if ($NoRestore) { $FLAGS += "-DP3B_FAULT_NORESTORE" }
if ($AlwaysRestore) { $FLAGS += "-DP3B_FAULT_ALWAYSRESTORE" }
if ($NoJoin) { $FLAGS += "-DP3B_FAULT_NOJOIN" }
if ($PresentAll) { $FLAGS += "-DP3B_FAULT_PRESENT_ALL" }
if ($NoShowPic) { $FLAGS += "-DP3B_FAULT_SHOWPIC" }
if ($NoCloseWindow) { $FLAGS += "-DP3B_FAULT_NOCLOSEWIN" }
# ★★★ HERE, not beside -NoRoomJump. $FLAGS is consumed by the assemble step a few lines below;
# -NoRoomJump sets an ENVIRONMENT variable read at run time and can be set late, but a -D added
# after the assembly has already run changes nothing. **Same class as the banner P6.68 put inside
# the headless branch: correct code, placed where it cannot take effect.**
if ($NoVarKey) { $FLAGS += "-DP3B_FAULT_NOVARKEY" }
# ★★★★★ -NoClearLines IS T-P0-125's FAULT ARM: vmop_clear_lines goes back to a bare rts. Today's
# behaviour, and a known-good red in Jay's own words -- "the press a key to continue stays on the
# title screen and transfers to the castle screen." ★★★ Expect the text strip to stay at 715
# non-black bytes across the advance instead of dropping to its cleared value.
if ($NoClearLines) { $FLAGS += "-DP3B_FAULT_NOCLEARLINES" }
if ($SprStats) { $FLAGS += "-DP3B_SPRSTATS" }
if ($NoVblKeys) { $FLAGS += "-DP3B_FAULT_NOVBLKEYS" }
if ($VblKeys) { "  ★ -VblKeys is the default since T-P0-132; the switch is a no-op" }
if ($RoomDrive) { $FLAGS += "-DP3B_ROOMDRIVE" }
# ★★★ -Combined needs P3B_IRQ as the text arms do: the text engine's print path blocks on a key,
# and the vector stubs at $FEF0 are what P3_REGIONB_END reserves for.
if ($Combined) { $FLAGS += @("-DP3B_COMBINED") + $IRQ }
if ($Count) { $FLAGS += "-DP3B_COUNT" }
if ($ViewHdrTest) { $FLAGS += "-DP3B_VIEWHDR_TEST" }
if ($LevelKeys) { $FLAGS += "-DP3B_FAULT_LEVELKEYS" }
if ($IfRec) { $FLAGS += @("-DVM_IFDIAG","-DVM_SAIDDIAG") }
if ($NoPlaneReset) { $FLAGS += "-DP3B_FAULT_NOPLANERESET" }
if ($ViewFaultOneMap) { $FLAGS += "-DVM_VIEW_FAULT_ONEMAP" }
# ★★★★★ THE CEL ARM GETS THE KEYBOARD TOO [T-P0-115]. Tested on the absence of -DP3B_NO_CEL rather
# than on a list of the twelve text switches, because that list is the thing this file has already
# been bitten by five times -- "a list repeated five times is a list that will be edited four
# times". The text arms add -DHAL_KEYBOARD themselves above; passing it twice is what this guard
# avoids. ★★ Selecting existing HAL code is not a HAL change [T-P0-085c §6].
if ($FLAGS -notcontains "-DP3B_NO_CEL") { $FLAGS += "-DHAL_KEYBOARD" }

& $LW --format=raw --output=build/p3b_probe_pk_fresh.bin --map=build/p3b_probe_pk.map -I. @FLAGS src/harness/p3b_probe.s
if ($LASTEXITCODE -ne 0) { throw "p3b assemble failed" }
"p3b_probe: $((Get-Item build\p3b_probe_pk_fresh.bin).Length) bytes"
"  [source-tree $(& python harness\tools\gate_audit.py --hash src/harness/p3b_probe.s)]"

# ★★★ SYMBOLS FROM THE BUILD'S MAP. P3_INBUF is an INTERIOR address -- it follows parser.s
# inside MAP_RESERVED and moves whenever either grows -- so p3b_run.lua refuses to stage input
# without it rather than falling back to a literal [P6.3 §3.F.2].
New-Item -ItemType Directory -Force build\p3b | Out-Null
# ★★★ par_egon/par_ego/par_notfound/par_cli ARE THE PARSE READBACK [T-P0-091]. They exist in
# every build that links parser.s, which is both configurations, so they belong on the shared
# line. Without them a fed command produced no host-visible result at all and the vocabulary
# window had no observable to be gated on.
$WANT = @("res_volbase","res_slicebase","res_curblk","vm_quit","vm_badop","vm_cycle","vm_tdelay",
          "res_err","ph_blk_fb","ph_blk_pri","par_vocab","P3_INBUF","P3_FEED","P3_VOCAB_BAD","P3_VOCAB","P3_VOCAB_END","P3_CODE_END","P3_PARSER_BASE","P3_PARSER_TOTAL",
          "par_egon","par_ego","par_notfound","par_cli",
          "vm_badlogic","res_depth","hal_frame_hi",
          # ★★★ res_top and res_ccur are the arena's TWO allocators, growing toward each other
          # [T-P0-104 §3(3)]. res_top was already read by vm_run.ps1 and not by this one, and
          # res_ccur by nothing at all -- so arena occupancy had no producer.
          "res_top","res_ccur",
          # ★★★★★ THE CACHE'S OWN COUNTERS, WHICH NOTHING HAS EVER READ [T-P0-133]. res_core.s has
          # kept hits, misses and starvation evictions since the cache landed -- res_chits was added
          # as "AC-5 evidence the cache is actually hitting" -- and no host has published them. P6.79
          # measured the resource layer at 62% of a castle cycle; these six bytes say whether that is
          # the cache missing, the table filling, or the arena starving.
          "res_cn","res_chits","res_cmiss","res_cevict","res_ckey","res_clen",
          # ★★★★★ vc_err IS PUBLISHED BECAUSE NOTHING HAS EVER READ IT IN THIS PROBE [T-P0-105].
          # p3_composite_all skips a sprite whenever the decode sets it, silently -- and CP_BLITS
          # measured ZERO composites across 60 cycles with four sprites staged, so every one of
          # them was being skipped and no instrument said why.
          # ★★★ vm_curlogic NAMES THE LOGIC THAT WAS INTERPRETING when a room changed [T-P0-094].
          # It exists in every build and was in vm_run.ps1's list and not this one, so p3b's room
          # trajectory could say WHEN and never WHICH.
          "vm_curlogic",
          # ★★★★★ vm_restart IS THE BYTE restart.game SETS, AND P6.39 READ THE WRONG ONE. That
          # report said "restart.game did not execute -- vm_quit and vm_badop are 0", and
          # vm_probe.s:440-443 says in as many words that **badop stays 0 for both, so this byte is
          # the only discriminator**. The claim was made from two bytes that cannot answer it.
          "vm_restart")
# ★★★ MAP_FONT only exists in the text configuration, and vm_symbols.py fails on a missing name,
# so it is appended rather than added to the list every build shares.
# ★★★★ ph_blk_vocab / ph_blk_slot5 EXIST ONLY WHERE -DPHASE_VOCAB DOES, which p3b_probe.s defines
# under P3B_NO_CEL -- i.e. exactly the text arms. The host uses their PRESENCE to decide whether
# the dictionary is windowed, so listing them for the cel build would both fail the extraction and
# make a flat build claim a window it does not have.
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ TWO PREDICATES, NOT FIVE COPIES OF THE SAME `-or` CHAIN [T-P0-093]. This file carried the
# arm list five times over, and adding -Win3 meant editing all five. **A list repeated five times
# is a list that will be edited four times** -- which is the same defect shape as a constant with
# five homes [memmap.inc's MAP_DIR_STRIDE, found at 0/9 on the fifth].
#   $Linked  text.s is LINKED (the -Fault arm links it and declines to call it)
#   $Wired   the nine opcodes are wired, so tx_wt_* and the prompt symbols exist
# ★ -FlatVocab is a MODELLED arm, so it belongs with $Fault in $Linked and not in $Wired: it links
#   text.s and leaves TEXT_WIRED undefined, exactly as -Fault does.
# ★★★★★ -Combined IS A WIRED TEXT BUILD AND MUST BE IN THIS PREDICATE [T-P0-120]. The source
# defines TEXT_WIRED under P3B_TEXT_LINK (= P3B_NO_CEL or P3B_COMBINED) with TEXT_MODELLED
# undefined -- so the combined arm has every symbol a wired text arm has, INCLUDING P3_FONT.
# ★★★★★ LEAVING IT OUT COST THIS TASK ITS EYE GATE. The host stages the font only when it
# extracted P3_FONT/P3_FONT_BYTES, those are on the $Linked line, $Linked derives from $Wired,
# and -Combined was in neither -- so no font was staged and txt_blit fetched glyphs from cold RAM.
# Jay: "the text is garbled."
# ★★★★ **This is the same defect as P6.64 §3.5 and the rule is the one written beside the split
# symbols above: the want-line's condition must be the SAME condition as the symbol's
# definition.** It was written in this file, in this task, and then not applied one screen below.
$Wired  = $Text -or $DecodeFault -or $NoTick -or $Diag -or $NoMap -or $Win3 -or $Combined
$Linked = $Wired -or $Fault -or $FlatVocab -or $SaidDiag -or $Var0Diag -or $IfDiag -or $ResCheck
# ★★ Each diagnostic's own symbols, only where its flag defines them.
if ($SaidDiag -or $IfDiag -or $IfRec) { $WANT += @("vm_sd_at","vm_sd_n","vm_sd_buf") }
if ($IfRec) { $WANT += @("vm_if_at","vm_if_logic","vm_if_n","vm_if_buf","vm_if_code","vm_if_clen","vm_if_snap") }
if ($Var0Diag) { $WANT += @("vm_v0_at","vm_v0_n","vm_v0_buf") }
if ($IfDiag) { $WANT += @("vm_if_at","vm_if_logic","vm_if_n","vm_if_buf","vm_if_code","vm_if_clen","vm_if_snap") }
# ★★ rck_seen and rck_noted are NOT optional extras: they are what tells a green run from a run
# where the checker never executed [§2W]. The host prints them whether or not anything went wrong.
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ THE CEL PATH'S SYMBOLS, AND ONLY WHERE THE CEL PATH IS LINKED [T-P0-106].
# vc_srcend is the bound VC_E_TRUNC tests [view_cel.s:268]; vc_view/vc_src are the pointer it
# refused; co_tested is how many cel pixels the compositor actually examined. **Published because
# p3b had never set vc_srcend and every cel truncated on its first byte.**
# ★★★★★ -DP3B_NO_CEL STRIPS view_cel.s AND composite.s, so these do not exist in any text arm, and
# **vm_symbols.py fails the whole run on a missing name.** I put them on the shared line first and
# it broke p3b_text, p3b_box, p3b_parse and p3b_row22 in one go -- the exact trap this file already
# warns about three times, for MAP_FONT, for P3_TXDIAG and for tx_wt_*.
# ★★★★★ GATED ON THE CEL LINK, NOT ON `-not $Linked` [T-P0-120]. Those were the same predicate only
# while text and cels were mutually exclusive. The combined arm has BOTH, so `-not $Linked` is now
# false for an arm that owns every symbol on this line.
# ★★★★★ AND THIS IS THE THIRD INSTANCE OF ONE PATTERN IN ONE TASK. The rule is written twice above
# -- the want-line's condition must be the SAME condition as the symbol's definition -- and it was
# still broken here, and in the font line below, after being written. **Found by grepping for the
# pattern rather than for the instance**, which is the only thing that caught it.
# ★★★ The source condition is `ifdef P3B_CEL_LINK`, which is "this arm did not ask for
# -DP3B_NO_CEL". Spelled from $FLAGS so it cannot drift from the flag that actually selects it.
$CelLink = ($FLAGS -notcontains "-DP3B_NO_CEL")
# ★★★★★ THE FOUR COUNTERS ONLY WHERE THEY COUNT [T-P0-130]. The symbols exist in every cel-linked
# build (composite.s reserves them unconditionally), so asking for them never fails -- and that is
# the hazard: in the shipped combined arm they would be read as ZEROS and printed as a result.
# **Condition = the source's**: p3b_probe.s sets COMP_NOCOUNT under P3B_COMBINED and not P3B_COUNT.
# Absent from the symbol file, p3b_run.lua says the counters are off instead of quoting them.
$Counting = $CelLink -and (-not $Combined -or $Count)
# ★★ T-P0-130 AC-8's two symbols exist only under -DP3B_VIEWHDR_TEST -- the same condition.
if ($ViewHdrTest) { $WANT += @("p3_vh_view","p3_vh_loop","p3_vh_cel","p3_vh_out","p3_vh_off","p3_vh_le") }
if ($CelLink) { $WANT += @("vc_err","vc_w","vc_h","vc_src","vc_srcend","vc_view",
                               $(if ($Counting) { "co_tested","co_written","co_rejkey","co_rejpri" }),
                               "p3_spr","p3_nspr",
# ★★★★★ T-P0-124's two bytes belong HERE and not on the shared line. p3_poll_dir is nested inside
# `ifdef P3B_CEL_LINK` AND `ifdef HAL_KEYBOARD` [p3b_probe.s:1359-1360], so p3_varkey/p3_nvarkey do
# not exist in the five P3B_NO_CEL arms and asking for them there fails the whole run.
# ★★★ THE RULE, for the third task running: the want-line's condition must be the SAME condition
# as the symbol's DEFINITION. I put these on the shared line first and caught it by reading the
# nesting rather than by a failed build.
                               "p3_varkey","p3_nvarkey",
# ★★★★ T-P0-113: the restore's two observables. CEL ARM ONLY, on this line and not the shared
# one, for the reason the comment above gives -- vm_symbols.py fails the whole run on a missing
# name, and p3_restbytes/p3_prevn live inside `ifndef P3B_NO_CEL`. Putting them on the shared
# line would break p3b_text, p3b_box, p3b_parse and p3b_row22 in one go, which is the trap this
# file has now warned about four times.
                               "p3_restbytes","p3_prevn","p3_prev",
# ★★★ Gated on the FLAG that defines them, not on $CelLink alone -- P6.66's rule, and these three
# exist only under -DP3B_SPRSTATS.
                               $(if ($SprStats) { "p3_droperr","p3_dropview","p3_ndrop" }),
# ★★★★ The VBL key queue exists exactly when P3B_VBL_KEYS does: -Combined and NOT -NoVblKeys
# [p3b_probe.s, the flag block]. The SAME condition as the definition, spelled from the switches.
                               $(if ($Combined -and -not $NoVblKeys) {
                                   "P3_KQ_NIN","P3_KQ_NDROP","P3_KQ_NOUT","P3_KQ_LAST" }),
# ★★ T-P0-115's two: also cel-arm only, and also inside `ifdef HAL_KEYBOARD` -- but the cel arm
# is the only arm that gets both, so this line is still the right home for them.
                               "p3_ndirs","p3_newdir") }
# ═══════════════════════════════════════════════════════════════════════════════════════════
if ($ResCheck -or $CelCheck) { $WANT += @("rck_n","rck_bad","rck_ring","rck_seen","rck_noted","rck_skipped","rck_full",
                            "rck_type","rck_idx","rck_live","rck_base","rck_len","rck_sum") }
if ($Linked) { $WANT += @("P3_FONT","P3_FONT_BYTES","P3_PBUF","ph_blk_vocab","ph_blk_slot5") }
# ★★★★ THE COMMAND LINE's SYMBOLS [T-P0-092]. They exist wherever TEXT_PROMPT does, which
# p3b_probe.s conditions exactly as TEXT_WIRED -- so every wired text arm has them and the
# -Fault arm (TEXT_MODELLED) does not. Asking for them there would fail the extraction.
if ($Wired) { $WANT += @("txt_penab","txt_ppos","txt_prow","P3_KEY","P3_NKEY","p3_keybuf","txt_fg","txt_bg") }
# ★★★★ WIRED BUILDS ONLY. -DTEXT_MODELLED keeps TEXT_WIRED undefined (p3b_probe.s:1004), so the nine
# handlers become `equ vm_op_modelled` and **the whole body -- tx_wt_key included -- is never
# assembled**. Asking for it in the -Fault arm fails the symbol extraction, which is why this is a
# second line rather than three more names on the one above.
# ★ vm_vms and vm_passed exist in every build; they are here because only these arms read them.
if ($Wired) { $WANT += @("vm_vms","vm_passed","tx_wt_key","tx_wt_nwait") }
# * P3_TXDIAG exists only in the -Diag build; vm_symbols.py fails on a missing name.
# * text.s symbols exist in EVERY P3B_NO_CEL build, -Fault included: that arm links the engine and
#   only declines to call the nine handlers. Kept off the line above because tx_wt_* need
#   TEXT_WIRED, which -Fault deliberately leaves undefined.
if ($Linked) { $WANT += @("txt_bgx","txt_bgy","txt_bgw","txt_bgh","txb_yoff","txt_winactive","txt_restore","P3_RBTRACE","p3rb_tn") }
# ★★★★★ THE RELOCATION SYMBOLS MOVED TO THE SHARED LINE [T-P0-118]. vm_tables.s is now relocated
# in EVERY arm, not only the P3B_NO_CEL ones, so the host must see the split in every arm too.
# ★★★★★ LEAVING THEM HERE COST THIS TASK A GREEN-LOOKING FAILURE: p3b_run.lua keys on the PRESENCE
# of these three [p3b_run.lua:702] and silently fell back to a single run, so a four-run image was
# poked linearly from $2000 -- the tables landed in the code and the code after the split landed
# 626 bytes low. The guest still reported "160 of 160 cycles"; only the completion line was
# missing. **A host that describes the image wrongly produces a run that looks almost right.**
$WANT += @("P3_CODE_SPLIT","P3_TABLES_BASE","P3_TABLES_END")
# ★★★★★ T-P0-121: p3_drew and p3_shown are the OPCODES' OWN RECEIPT. draw.pic sets p3_drew and
# clears p3_shown; show.pic sets p3_shown [op_cmd.cpp:1210,1218]. Reading both is what makes the
# -DP3B_FAULT_SHOWPIC arm a BYTE result -- drew=1 shown=0 -- rather than only something to look at.
# ★★★★ SHARED LINE BECAUSE THE DEFINITION IS UNCONDITIONAL. Both bytes are declared outside every
# ifdef in p3b_probe.s, so the want-line's condition must be "always" too [P6.66's rule, which this
# file states four lines down and which I broke in the task that wrote it].
$WANT += @("p3_drew","p3_shown","p3_errpic","p3_errtop","p3_errdepth","res_depth","vm_objtop",
           "p3_drawtop","p3_drawdepth","res_top","p3_nfall","p3_drawccur","res_ccur",
           "p3_errccur")
# ★★★★★ T-P0-120's THREE CANNOT GO ON THE SHARED LINE, AND THE REASON REFINES P6.64'S LESSON.
# They exist only under -DP3B_COMBINED, and vm_symbols.py FAILS THE WHOLE RUN on a name it cannot
# find -- so asking for them in the cel and text arms would break both, which is the trap this
# file has warned about five times.
# ★★★★★ P6.64's BUG WAS NOT "a per-configuration line". It was a per-configuration line whose
# CONDITION DIFFERED FROM THE ONE THAT CREATES THE SYMBOLS: the relocation became universal while
# the want-line still said `$Linked`. **The rule is that the want-line's condition must be the
# SAME condition as the symbol's definition**, not merely a related one -- and here it is exactly
# $Combined, the flag that emits the `org`.
if ($Combined) { $WANT += @("P3_TEXT_SPLIT","P3_TEXTB_BASE","P3_TEXTB_END") }
if ($Diag) { $WANT += @("P3_TXDIAG","tx_diag_n1","tx_diag_n2") }
# * tx_wt_* exist in every wired build; the stall dump reads them to separate the three shapes a
#   hang inside the wait loop can have.
if ($Wired) { $WANT += @("tx_wt_end","tx_wt_timed") }
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
# ★★★ P3B_ALSO_VOLS stages volumes the reference run does not touch -- T-P0-130 AC-8 reads VIEWs
# (MUMG 85 in vol 2, PQ1 233 in vol 3) that no early cycle reaches. Absent, staging is unchanged.
if ($env:P3B_ALSO_VOLS) { $stageArgs += @("--also-vols", $env:P3B_ALSO_VOLS) }
python harness\tools\vm_stage.py @stageArgs
if ($LASTEXITCODE -ne 0) { throw "staging did not fit" }

$env:P3B_PROG = "build\p3b_probe_pk_fresh.bin"
$env:P3B_STAGE = $stage
$env:P3B_SYMBOLS = "build\p3b\symbols.txt"
$env:P3B_CYCLES = "$Cycles"
$env:P3B_HOLD = "$Hold"
$env:P3B_OUT = if ($Headless) { "build\p3b_headless" } else { "build\p3b_eye" }
# ★★★ Set BEFORE the verdict below reads it, so the banner describes the run that will happen.
if ($NoRoomJump) { $env:P3B_ROOM = "0" }

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ SAY WHETHER THE TITLE SEQUENCE SURVIVED -- BEFORE THE RUN, AND FOR EVERY RUN [T-P0-122].
# A room jump ENDS the title screen, and the title screen is where the credits scroll, the
# copyright draws and the picture is revealed. P6.67's eye gate ran with a jump inherited from an
# earlier run's staging; the runner reported it as a trace line, I read it, and I filed it as a
# caveat. **Jay then answered "no scroll" about a run in which the scroll never happened.**
#
# ★★★★★ AND THE FIRST VERSION OF THIS WARNING WAS WRONG TWICE, IN ONE TASK, IN THE SAME GUARD.
#   (1) It was inside `if ($Headless)`. An eye gate is never headless, so it could not fire on the
#       run it exists to protect -- P6.3's defect exactly [§2W].
#   (2) It keyed on $env:P3B_ROOM being SET. ★★★★★ THE EYE GATE JUMPS WHEN IT IS UNSET:
#       p3b_room.lua:25 is `tonumber(os.getenv("P3B_ROOM") or "1")` -- **the default is 1, not
#       none** -- and p3b_room.lua:59-61 says so in as many words, handing that default to
#       p3b_run.lua, "whose own default is 0, meaning no jump". **So the two gates run DIFFERENT
#       PROGRAMS by default**, and the guard printed "title sequence intact" for precisely the
#       runs that cut it.
# ★★★★ THAT IS THE DEFECT THIS WHOLE TASK CHASED: every eye gate in this arc jumped to room 1 at
# cycle 8, the first credit appears at cycle 5, and Jay has therefore never seen more than one.
# **"The text doesn't scroll", reported three times, was an accurate report of the run he was shown.**
$effRoom = if ($env:P3B_ROOM) { [int]$env:P3B_ROOM } elseif ($Headless) { 0 } else { 1 }
$effAt   = if ($env:P3B_ROOM_AT) { [int]$env:P3B_ROOM_AT } else { 8 }
if ($effRoom -gt 0) {
  "★★★ TITLE SEQUENCE CUT: a room jump to $effRoom fires at cycle $effAt" +
  $(if (-not $env:P3B_ROOM) { " (the EYE GATE's DEFAULT -- p3b_room.lua:25)" } else { "" }) +
  ". The credits scroll from cycle 5 at one line per 5 cycles, so this run shows at most" +
  " $([math]::Floor($effAt / 5)) of them. Do NOT judge the title screen from this run;" +
  " pass -NoRoomJump."
} else {
  "★ title sequence intact (no room jump): credits scroll from cycle 5, one line per 5 cycles"
}
# ★★★★★ SAY THAT THE RUN ENDS, BECAUSE A CYCLE BUDGET LOOKS LIKE A CRASH [T-P0-125's eye gate].
# The probe executes exactly -Cycles cycles and then FREEZES the display for -Hold seconds so it
# can be looked at. Jay, interacting with a 180-cycle run: **"graham started walking and then the
# game froze."** The log recorded `cycle 180 ... err 0` and `holding the display` -- no stall, no
# watchdog. **The run had simply finished.**
# ★★★ Same class as the room-jump default: the operator is judging the GATE's shape and reading it
# as the PROGRAM's behaviour, and only the gate can tell him which it is.
if (-not $Headless) {
  "★ this run executes $Cycles cycle(s) and then FREEZES for $Hold s so you can look at it --" +
  " the stop at the end is the budget running out, not the game crashing"
}

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
  # ═══════════════════════════════════════════════════════════════════════════════════════
  # ★★★★★ -video none AND natkeyboard DO NOT MIX, AND THAT COST FOUR WRONG DIAGNOSES [T-P0-092].
  # A typed run posted 180 characters, natkeyboard reported its queue drained after every one, and
  # the guest saw ZERO. Throttling, a missing HAL_input_init, the post rate and a one-deep key
  # latch were each tried and each was not the cause. **MAME's natural keyboard needs a video
  # target**; with `-video none` the posts are accepted and never delivered to the machine.
  # ★★★★ input_gate.lua's posting arm has always used `-resolution 640x480` and its READBACK arms
  # use `-video none` -- the distinction was already in the tree, in the file that posts keys, and
  # it reads as a resolution preference rather than as a precondition [input_run.ps1:127].
  # ★★★ SO THE TYPED ARM GETS A RENDERER AND EVERY OTHER ARM DOES NOT. It is still unattended and
  # still -nothrottle: §2U.2 excludes gates whose output is a HUMAN JUDGEMENT, and this one's
  # output is a word count.
  $secs = if ($env:P3B_SECONDS) { $env:P3B_SECONDS } else { "900" }
  $vid = if ($env:P3B_TYPE) { @("-resolution","640x480") } else { @("-video","none") }
  C:\mame\mame.exe coco3 @vid -sound none -window -nomaximize -skip_gameinfo -nothrottle `
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
  # ★★★★★ AND A FED COMMAND THAT MATCHED NOTHING IS A FAILURE [T-P0-091]. A parse against an
  # unmapped, unstaged or wrongly-blocked dictionary returns zero words WITHOUT stalling, so the
  # two conditions above would both be satisfied and the row would be green. **The vocabulary
  # window had no adjudicated observable at all before this line**; p3b_run.lua now prints the
  # word count and this is what makes it a verdict rather than a log entry.
  # ★★ Silent when no command is fed: the pattern cannot match a run that never parsed.
  $nowords = Select-String -Path $log -Pattern 'NO WORDS MATCHED' -Quiet
  # ★★★★★ AND THE TYPED PATH's TWO FAILURES [T-P0-092]. Both finish the run normally -- a prompt
  # that never receives a key and a line that never parses are quiet, not fatal -- so neither the
  # watchdog nor the completion check can see them. This is what makes p3b_type a gate.
  $nokeys  = Select-String -Path $log -Pattern 'NO KEYS REACHED THE EDITOR' -Quiet
  $noparse = Select-String -Path $log -Pattern 'TYPED LINE NOT PARSED' -Quiet
  # ★★★★★ AC-3 [T-P0-093]: keys arrived and row 22 stayed blank. That is P6.37's defect exactly,
  # and it completes the run silently -- no stall, no error, a green suite. It is the only thing
  # that distinguishes the four-slot window from the three-slot one on a live machine.
  $noink   = Select-String -Path $log -Pattern 'NOTHING IS DRAWN ON ROW 22' -Quiet
  # ★★★ P3_PBUF IS IN THE PATTERN BECAUSE IT IS A VERDICT LINE. An allowlist filter drops what it
  # does not name, and what it does not name is always the newest thing -- here AC-3's whole
  # observable printed to the log and never to the console [the same shape as the star-in-a-pattern
  # loss two tasks ago: the filter kept every table and removed the conclusion].
  # ★★★★ `restore \d+ bytes` ADDED T-P0-114, and this comment is the reason the line above warns
  # about allowlists: the restore figure was owed by two tasks, was being computed correctly by
  # the guest the whole time, and was invisible because no pattern here named it.
  Select-String -Path $log -Pattern 'OK prompt|program \d+ bytes|vocabulary |window discrimination|par_vocab written|COMMAND TYPED|parse at cycle|TYPING |TYPED LINE|prompt: enabled|row 22|NO KEYS REACHED|NEVER REACHED|STUCK|cycles in|final room|restore \d+ bytes|ego: x=|text area rows|picture: draw\.pic|REFUSED at draw\.pic|LOGIC CACHE had taken|arena at draw\.pic|rendered AFTER the logic|VAR 19|VBL key queue|stack low-water|staged sprites|^ +\[\d+\] x=|compositor: tested|\[obj\] cycle|rect x=\d|sprites dropped before the blit|composited this frame|^ +rect\[\d|DROPPED BEFORE THE BLIT|scroll band|char row|TOTAL \d+ bytes drawn|NEVER WRITTEN|P3_PBUF' |
    ForEach-Object { $_.Line }
  if ($stuck) { "★★★ p3b FAILED -- the watchdog fired"; exit 1 }
  if ($nowords) { "★★★ p3b FAILED -- a fed command matched no dictionary words"; exit 1 }
  if ($nokeys)  { "★★★ p3b FAILED -- posted keys never reached the command line"; exit 1 }
  if ($noparse) { "★★★ p3b FAILED -- a typed line did not reach the parser"; exit 1 }
  if ($noink)   { "★★★ p3b FAILED -- keys reached the editor and nothing was drawn on row 22"; exit 1 }
  if (-not $done) { "★★★ p3b FAILED -- no completion line; the run did not reach $Cycles cycles"; exit 1 }
  "★ p3b headless: $Cycles cycles, no stall"
  exit 0
}

# ★★★★★ NO -nothrottle. §2U.2: "an eye gate nobody can watch at 2869% is not an eye gate", and
# p3b_show.lua carries the same standing note. RGB, screen_config=1, per §4's monitor rule.
C:\mame\mame.exe coco3 -window -nomaximize -skip_gameinfo `
  -rompath C:/mame/roms -cfg_directory harness\mame-cfg `
  -autoboot_script C:/Projects/coco_agi/harness/tools/p3b_show.lua -autoboot_delay 0

