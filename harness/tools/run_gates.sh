#!/bin/sh
# harness/tools/run_gates.sh -- ALL FIVE gates, in one place.
#
# ★★★ THIRD SCRIPT WRITTEN FOR THE L-45 REASON, and by now the pattern is the finding rather
# than the incident. T-P0-030 wrote build_comp.sh and run_comp_sweep.sh because the assemble
# and launch lines lived only in a shell history. **The four GATE invocations were in the same
# state** -- the renderer, resource, VM and cel gates are the project's primary evidence, cited
# by number in every report since P4, and the commands that produce those numbers were not on
# disk anywhere.
#
# ★★ A gate whose invocation is unrecorded cannot be re-run by a reader, which means every
# "45/45" in the report history is a claim about a command nobody can inspect. That is the
# same defect as an unsaved analysis script and it sits on more load-bearing numbers.
#
# usage:  sh harness/tools/run_gates.sh [pic|res|cel|comp|p3b|all]
#
# ★ Each gate is headless MAME driving its probe through a handshake. -seconds_to_run is
# EMULATED seconds, not wall clock. Expected results, for comparison:
#     pic   45/45 pictures, both planes      res   1,264/1,264 fetches (10 volumes)
#     cel   9,193/9,193 cels, 6 titles       comp  124/124 frames, 6 corpora [T-P0-061]
#     p3b   160 cycles, no stall, err 0      [T-P0-060: a HEALTH gate, not a byte gate]
#
# ★★★★★ AND -seconds_to_run IS A CLOCK CHARGED TO THE WHOLE BATCH, WHICH THE LINE BELOW USED TO
# CALL "a safety net rather than a budget that is always spent". T-P0-060 MEASURED it: the pic
# gate spends **308 of its 900 emulated seconds** for 45 pictures, ~6.8 s each, so the budget
# covers about 131 -- and the corpus is under pressure to widen [AD-113]. Past that the session
# is cut mid-sweep with no diagnostic at all, which is quieter than the stall detector that
# started the sweep [P6.3 §3.C]. ★★★ harness/tools/gate_budget_check.sh is the instrument that
# measures the headroom AND proves the gate notices a cut session, in both directions.
#
# ★★★★★ ONLY `pic` IS DRIVEN FROM THIS FILE, AND THE OTHER THREE LINES USED TO PRETEND TO BE.
# Every sweep .lua drives exactly ONE stage. This script launched each of them once, against its
# default stage, and printed the partial result with exit 0 -- `res` reported "74 fetches
# complete" under a header claiming 1,264. **A successful-looking run of the wrong scope reads
# exactly like a pass.** So res and cel now delegate to the drivers that actually loop, and comp
# requires its stage arguments rather than silently using one title's leftovers.
#
# ★★★ AND THE cel NUMBER IN THAT HEADER WAS A FOSSIL. Aggregating the six staged titles gives
# 9,193, not 6,782 -- and 9,193 less PoliceQuest1's 2,411 is exactly 6,782. PoliceQuest1 was
# staged after the figure was written and the figure was never updated, so the gate had been
# covering more than it claimed. ★★ The error was benign in direction and total in kind: the
# published number could not be reproduced by any command, including the one printed beside it.
set -e
MAME=${MAME:-/c/mame/mame.exe}
WHICH=${1:-all}

LWASM=${LWASM:-/c/WIN_LWTools/lwasm.exe}

# ★★★★★ BUILD WHAT WE TEST, AND STAMP THE RESULT. THIS SCRIPT NAMED NO ARTIFACT AT ALL AND WAS
# THEREFORE INVISIBLE TO A FIRST AUDIT PASS -- but every driver it launches has a DEFAULT:
# pic_sweep.lua falls back to build/pic_probe.bin, res_sweep.lua to build/res_probe.bin, and so
# on. **A runner that supplies no program silently runs whatever is on disk**, which is how the
# resource gate reported on a pre-cache binary for two tasks [L-70].
# ★★★ build/pic_probe.bin was a FULL DAY stale when this was written (assembled 08-29 21:38
# against a source tree last touched 08-30 18:03).
# ★★ The stamp is a hash of the source's whole include tree, printed beside the verdict, so a
# future result carries the identity of the code that produced it. A stamp on the BINARY would
# not have helped -- the binary was fine, it was just old.
# ★★★★★ EACH GATE HAS ITS OWN FLAG SET AND THEY ARE ALL DIFFERENT. The first version of this fix
# passed one blanket -DHAL_GFX_MODE_SERVICE to all four, which would have built comp at 1,373
# bytes instead of 967 and cel at 1,432 instead of 1,436 -- **a DIFFERENT PROGRAM from the one
# each gate's numbers were established against.** The repair for "testing a stale binary" was one
# step from introducing "testing the wrong binary": the same error class, freshly minted.
# ★★★ The flag sets below were not chosen, they were RECOVERED, by rebuilding each probe under
# every candidate combination and matching the byte size of the shipped artifact:
#     pic 2642 = MODE_SERVICE            res 1969 = MODE_SERVICE   [matches res_run.ps1]
#     cel 1436 = MODE_SERVICE+FAST_CLOCK comp 967 = no flags       [matches build_comp.sh]
# ★★ res and comp corroborate against their existing runners' documented lines; pic and cel had
# NO recorded build line anywhere in the tree, so size-matching is the only evidence for them and
# it is evidence about FLAGS, not about currency -- pic matched at 2642 while a full day stale.
build_and_stamp() {   # build_and_stamp <src> <out> [flags...]
    src="$1"; out="$2"; shift 2
    "$LWASM" --raw -I. "$@" -o "$out" "$src" || {
        echo "★★★ assemble FAILED for $src"; return 1; }
    printf '  built %s from %s  [source-tree %s]\n' \
        "$out" "$src" "$(python harness/tools/gate_audit.py --hash "$src")"
}

run() {   # run <name> <script> <seconds> <src> <out> [flags...]
    echo "═══ $1 ═══"
    name="$1"; script="$2"; secs="$3"; shift 3
    build_and_stamp "$@" || { echo "★★★ $name SKIPPED -- could not build"; echo; return 1; }
    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ -nothrottle: MEASURED, NOT ASSUMED [T-P0-058]. MAME paces to emulated real time by
    # default, so a gate that emulates 308 seconds took 308 seconds of Jay's day.
    #     pic gate  THROTTLED  312.7 s at 99.98%     UNTHROTTLED  16.5 s at 2869%   -- 19x
    # **45/45 PASS both ways, every per-picture hash identical**, and the same held for cel
    # (9,193/9,193 with all six per-title counts unchanged), comp (9 corpora x 20/20) and p3b
    # (pictures 22/1/3/83 at 0.0% on both planes).
    # ★★★★ WHY IT CANNOT CHANGE A RESULT HERE, which is the part worth writing down: emulation is
    # deterministic and throttle only paces the HOST. Nothing in this harness measures wall clock
    # -- every timing call in every sweep is `m.time:as_double()`, which is EMULATED time. That is
    # not luck: L-78/AD-100 moved this project off host-side intervals after one was found to be
    # the wrong instrument, and VP_MARK exists for the same reason.
    # ★★★ res_run.ps1 and vm_run.ps1 had ALREADY been passing -nothrottle for many tasks, so two
    # of the gates had been validating this quietly the whole time and nobody had noticed the
    # suite was half-paced.
    # ★★ TO RESTORE PACING: MAME_EXTRA=-throttle. MAME_EXTRA is also how any other flag is added
    # without editing this file, so the flag a measurement was taken under is visible in the
    # environment rather than in a shell history [L-45, applied to the launch step].
    # ★ -seconds_to_run is EMULATED seconds, and the sweeps already call machine:exit() on
    # completion, so it is a safety net rather than a budget that is always spent.
    # ★★★★★ JAY'S VISUAL GATE STAYS THROTTLED -- see the note in p3b_show.lua. A human watching a
    # room appear needs it to appear at the speed the machine would.
    # shellcheck disable=SC2086
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -nothrottle ${MAME_EXTRA:-} -seconds_to_run "$secs" \
        -autoboot_script "$script" 2>&1 | tail -"${TAIL:-6}"
    echo
}

M=-DHAL_GFX_MODE_SERVICE
F=-DHAL_SYS_FAST_CLOCK

# ★★★★★ L-72: A RUNNER THAT EXITS 0 ON A PARTIAL RUN ASSERTS MORE THAN IT TESTED. This script
# ended in a bare `exit 0` and every gate's verdict was thrown away -- picgate.py's exit code,
# res_aggregate.py's, celgate.py's. **A gate whose adjudicator reports FAIL and whose runner
# exits 0 is worse than no runner**, because a CI step or a `&&` chain reads it as a pass.
# ★★ FAILED accumulates the names; the exit code is the count. A build that could not assemble
# counts too -- "skipped" is not "passed".
FAILED=""
note_fail() { FAILED="$FAILED $1"; }

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ SOURCE INTEGRITY, BEFORE ANY GATE RUNS [T-P0-087 §7.5, Jay's ruling].
# PowerShell 5.1's `Get-Content -Raw` reads a BOM-less UTF-8 file using the ANSI codepage and
# `Set-Content -Encoding utf8` writes a BOM back, so ANY read-modify-write of a tracked file
# through PowerShell double-encodes every non-ASCII character. The damage is comment-only and
# every affected script still runs, which is exactly why it survives commits unnoticed:
# T-P0-061 did it to six files, four already pushed; T-P0-086 to 34 runs; T-P0-087 to 59.
#
# ★★★★ THE RULE EXISTED AND DID NOT HOLD, WHICH IS A FACT ABOUT ITS PLACEMENT. It lived only in
# an agent's memory -- the weakest slot available -- and was broken twice in two tasks. The rule
# belongs in CLAUDE.md beside §2J's heredoc ban (same failure shape: a shell construct that
# corrupts silently and produces something that LOOKS PLAUSIBLE AND IS WRONG). **This is the
# mechanical half**: §2J's own text is that a ban needs more than an intention to be careful.
#
# ★★★ IT RUNS FIRST AND ON EVERY INVOCATION, including `run_gates.sh pic`. Corruption in a file
# this sweep never builds is still corruption, and the point is that it cannot survive a task --
# the suite runs every task, so this is the cheapest enforcement point that covers the whole
# tree rather than one gate's inputs.
# ★★ fix_mojibake.py --check writes nothing and exits non-zero on any double-encoded run. It has
# existed since T-P0-061 and was wired to nothing at all.
# ★★★★★ ONE ALLOWLISTED FILE, BY EXPLICIT NAME -- never by pattern, so adding one is a visible
# act [§2N's rule for harness probes, applied here]. P3.2's report DOCUMENTS this very defect and
# spells the damaged forms out literally -- U+2605 shown as the three characters it decays to --
# so it is byte-identical to the thing being detected.
# ★★★★★ AND THIS COMMENT HAD TO BE REWRITTEN FOR THE SAME REASON, ONE MINUTE LATER. Its first
# draft quoted the damaged sequence to explain the exclusion, so run_gates.sh flagged ITSELF on
# the next run. **Describe the corruption in codepoints; never paste it.**
# ★★★★ fix_mojibake.py's own header records the identical trap: it once flagged
# its OWN docstring, and "running the repair over the tree would have fixed the illustration and
# destroyed the one place the defect is recorded." The tool's answer was to spell examples in
# codepoints; that report predates the convention and is left exactly as it is.
# ★★★ THE EXCLUSION EXISTS SO THE CHECK CAN STAY ON. A gate that is permanently red for a
# legitimate reason gets switched off, and then enforces nothing [§2M.8's graceful-skip lesson].
# ★★ Found by running it: the first version of this block failed the suite on a clean tree.
MOJI_ALLOW='reports/20260826-030000-p3-2-sync-entry-and-first-pixels.md'
echo "═══ source integrity (mojibake) ═══"
MOJI_FILES=$(git ls-files '*.s' '*.inc' '*.py' '*.lua' '*.sh' '*.ps1' '*.md' '*.manifest' 2>/dev/null \
             | grep -v -F -x "$MOJI_ALLOW")
if [ -z "$MOJI_FILES" ]; then
    echo "★★★ could not list tracked files -- NOT treating that as clean"
    note_fail mojibake
else
    # shellcheck disable=SC2086
    if python harness/tools/fix_mojibake.py --check $MOJI_FILES; then
        echo "★ source integrity: clean"
    else
        echo "★★★ DOUBLE-ENCODED SOURCE -- repair with: python harness/tools/fix_mojibake.py <file>"
        note_fail mojibake
    fi
fi
echo

# ★★★ pic's SWEEP is whole -- PIC_LIST/order.txt names all 45 pictures, so one launch covers the
# set -- but the sweep only WRITES framebuffers. picgate.py is what compares them and prints
# 45/45, and this script never called it. **The renderer gate's headline number had no producer
# here either**, which is the same defect as res and cel wearing different clothes: the launch
# was recorded and the ADJUDICATION was not. ★★ A sweep that exits 0 having written 90 .bin files
# looks exactly like a gate that passed.
if [ "$WHICH" = "pic" ] || [ "$WHICH" = "all" ]; then
    if run "renderer (45 pictures)" harness/tools/pic_sweep.lua 900 src/harness/pic_probe.s build/pic_probe.bin $M; then
        python harness/tools/picgate.py build/sweep build/picset/picset.json || note_fail pic
    else
        note_fail pic
    fi
    echo
fi

# ★★ res: ten (title, volume) pairs, one MAME launch each. res_run.ps1 owns the loop, assembles
# its own probe, and res_aggregate.py computes the 1,264 -- which previously had no producer.
if [ "$WHICH" = "res" ] || [ "$WHICH" = "all" ]; then
    echo "═══ resources (1,264 fetches, 10 volumes) ═══"
    powershell -NoProfile -ExecutionPolicy Bypass -File harness/tools/res_run.ps1 >/dev/null 2>&1
    python harness/tools/res_aggregate.py || note_fail res
    echo
fi

# ★★ cel: six staged titles. cel_run.sh did not exist until T-P0-039; 9,193 came from a hand
# loop nobody wrote down.
if [ "$WHICH" = "cel" ] || [ "$WHICH" = "all" ]; then
    sh harness/tools/cel_run.sh || note_fail cel
    echo
fi

# ★★★★★ comp IS DRIVEN FROM HERE NOW [T-P0-061 AC-4], and the objection that kept it out is MET
# rather than overruled. The note below is preserved because it was right: build/comp_stage holds
# twelve directories, most of them scratch from past experiments (KQ2-r1, PQ1gate2, one78), and
# **falling back to one of them silently is how a gate reports on a sample nobody chose.**
# ★★★★ THAT IS AN ARGUMENT AGAINST A DEFAULT, NOT AGAINST A GATE. comp_run.sh DECLARES its six
# corpora, exactly as res_aggregate.py declares its ten volumes -- so a scratch directory
# appearing cannot join the gate [L-85: the corpus is part of the claim]. ★★★ A gate outside the
# suite is a gate that does not run; this was the last one.
# ★★ It fails on a MISSING summary line too, which is what a session cut short leaves behind.
if [ "$WHICH" = "comp" ] || [ "$WHICH" = "all" ]; then
    sh harness/tools/comp_run.sh || note_fail comp
    echo
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ p3b: THE INTEGRATION PROBE, WHICH THIS SUITE DID NOT RUN. gates.manifest's own note says
# it "was the one probe this file did not list ... 48,537 bytes of source and sixteen p3_*
# routines built by no gate at all", and T-P0-054 fixed the MANIFEST while leaving the SUITE
# alone -- so it was still assembled by nothing here.
# ★★★★ AND IT IS THE ROW THAT EARNS ITS PLACE. Every defect of the last several tasks lived in
# this probe, and T-P0-060 added four more: an org gap, a status-block collision, a reservation
# that already had an occupant, and a takeover before DECB was ready [idiom 43]. **None of them
# was reachable from pic, res, cel or comp** -- they live in the glue between subsystems that are
# each independently gated (§4A.1), which is exactly what an integration probe is for.
# ★★★ It is a HEALTH gate, not a byte gate: it builds, boots on the real path (waits for DECB's
# OK prompt), stages a title, runs N cycles and fails on a watchdog stall, a non-zero err, or a
# missing completion line. The plane comparison is plane_pair_diff.py and needs P3B_DUMP and an
# oracle dump per picture, so it stays an explicit run like comp.
# ★★ P3B_CYCLES narrows it for a spot-check; the default is the gate.
if [ "$WHICH" = "p3b" ] || [ "$WHICH" = "all" ]; then
    echo "═══ p3b (integration probe: boot, stage, ${P3B_CYCLES:-160} cycles) ═══"
    powershell -NoProfile -ExecutionPolicy Bypass -File harness/tools/p3b_show.ps1 \
        -Title "${P3B_TITLE:-Kingquest1}" -Cycles "${P3B_CYCLES:-160}" -Headless || note_fail p3b
    echo
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ p3b_text: THE CORRECTNESS CONFIGURATION OF THE SAME PROBE [ruling C; run from T-P0-084h].
# ★★★★ TWO ROWS, NOT ONE CHANGED ROW. `p3b` is purpose=timing and keeps its flags; this row strips
# cel/composite so MAP_RESERVED can hold the text engine and wires the nine text opcodes.
# **Both must be green; neither substitutes for the other.**
# ★★★ HELD OUT OF THE SUITE FOR TWO TASKS, DELIBERATELY: until the decode landed this row would
# have gated HEALTH over a build whose messages were ciphertext -- green for the wrong reason. It
# runs now because the thing it gates is finally correct [AD-187].
# ★★ Same driver and the same health criteria as `p3b`: a stall, a non-zero err or a missing
# completion line fails it. It differs only in the flag set, which is what this suite makes visible.
if [ "$WHICH" = "p3b_text" ] || [ "$WHICH" = "all" ]; then
    echo "═══ p3b_text (correctness probe: text opcodes, no cel, ${P3B_CYCLES:-120} cycles) ═══"
    powershell -NoProfile -ExecutionPolicy Bypass -File harness/tools/p3b_show.ps1 \
        -Title "${P3B_TITLE:-Kingquest1}" -Cycles "${P3B_CYCLES:-120}" -Text -Headless \
        || note_fail p3b_text
    echo
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ p3b_box -- THE BLOCKING MESSAGE WINDOW. Same binary as p3b_text; what differs is the
# TRIGGER, and the trigger is the part that was missing for four tasks.
# ★★★★ IT IS A SEPARATE ROW BECAUSE p3b_text CANNOT REACH IT. That row runs Kingquest1 at room 83,
# and no title in the pinned set executes print from its intro -- measured three ways
# [vm_opcov.py, print_first_cycle.py, vm_input_script.py --wants-print]. **The scope and the
# invocation of a gate are part of its definition** [§2F; this project has recorded that five
# times], so the corpus difference gets a row rather than a flag.
# ★★★ WHY THIS ROOM, MEASURED NOT CHOSEN [P6.30 §4A/§4B]: SpaceQuest-2 logic 101 is
# `print.v(v17); quit(1)` -- unconditional, HAS a picture so the probe can be in it, does not halt
# the VM, and reaches print at cycle 8 identically across runs. P3B_SETVAR is not optional: var 17
# selects the message and at its cold value of 0 the index resolves to -1 and print draws nothing.
# ★★ P3B_VAR21=2 auto-closes the box after 2 * 30 ticks so the run completes unattended. The eye
# gate drops it and waits for a key instead.
# ★★★★★ AND THE EARLIER WORRY WAS WRONG, SO IT IS RECORDED RATHER THAN REPEATED: this row was held
# out on the grounds that quit(1) would end the run early and the completion check would read that
# as a failure. **Measured: the probe keeps cycling after vm_quit, reaches its full count and
# exits 0.** The claim was never tested when it was made.
if [ "$WHICH" = "p3b_box" ] || [ "$WHICH" = "all" ]; then
    echo "═══ p3b_box (blocking message window: SpaceQuest-2 room 101, 40 cycles) ═══"
    P3B_ROOM=101 P3B_ROOM_AT=8 P3B_SETVAR=17=1 P3B_VAR21=2 \
    powershell -NoProfile -ExecutionPolicy Bypass -File harness/tools/p3b_show.ps1 \
        -Title SpaceQuest-2 -Cycles 40 -Text -Headless \
        || note_fail p3b_box
    echo
fi

if [ -n "$FAILED" ]; then
    echo "★★★ GATES FAILED:$FAILED"
    exit 1
fi
echo "★ gates run:$([ "$WHICH" = "all" ] && echo " pic res cel comp p3b p3b_text p3b_box" || echo " $WHICH")  -- all green"
exit 0
