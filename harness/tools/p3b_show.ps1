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
  # ★★★★★ -NoCount IS T-P0-101's ABLATION. VM_OPSEEN ($6400) and VM_TESTSEEN ($6300) sit INSIDE the
  # residency arena's window ($6000-$A000), so every dispatched opcode increments a byte of whatever
  # resource the arena has mapped there. -DVM_NOCOUNT removes both counters and nothing else, which
  # is the one-variable arm [L-73] that turns "the counters are writing into logic 102" from an
  # address coincidence into a measurement. It composes with any arm above.
  [switch]$NoCount,
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
if ($NoCount) { $FLAGS += "-DVM_NOCOUNT" }

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
$Wired  = $Text -or $DecodeFault -or $NoTick -or $Diag -or $NoMap -or $Win3
$Linked = $Wired -or $Fault -or $FlatVocab -or $SaidDiag -or $Var0Diag -or $IfDiag -or $ResCheck
# ★★ Each diagnostic's own symbols, only where its flag defines them.
if ($SaidDiag -or $IfDiag) { $WANT += @("vm_sd_at","vm_sd_n","vm_sd_buf") }
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
if (-not $Linked) { $WANT += @("vc_err","vc_w","vc_h","vc_src","vc_srcend","vc_view","co_tested") }
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
if ($Linked) { $WANT += @("txt_bgx","txt_bgy","txt_bgw","txt_bgh","txb_yoff","txt_winactive","txt_restore","P3_RBTRACE","p3rb_tn","P3_CODE_SPLIT","P3_TABLES_BASE","P3_TABLES_END") }
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
  Select-String -Path $log -Pattern 'OK prompt|program \d+ bytes|vocabulary |window discrimination|par_vocab written|COMMAND TYPED|parse at cycle|TYPING |TYPED LINE|prompt: enabled|row 22|NO KEYS REACHED|NEVER REACHED|STUCK|cycles in|final room|P3_PBUF' |
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
