#!/bin/sh
# harness/tools/run_gates.sh -- the four gates, in one place.
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
# usage:  sh harness/tools/run_gates.sh [pic|res|cel|comp|all]
#
# ★ Each gate is headless MAME driving its probe through a handshake. -seconds_to_run is
# EMULATED seconds, not wall clock. Expected results, for comparison:
#     pic   45/45 pictures, both planes      res   1,264/1,264 fetches (10 volumes)
#     cel   9,193/9,193 cels, 6 titles       comp  20/20 SpaceQuest-1, 80/80 gameplay
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
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -seconds_to_run "$secs" -autoboot_script "$script" 2>&1 | tail -"${TAIL:-6}"
    echo
}

M=-DHAL_GFX_MODE_SERVICE
F=-DHAL_SYS_FAST_CLOCK

# ★★★ pic's SWEEP is whole -- PIC_LIST/order.txt names all 45 pictures, so one launch covers the
# set -- but the sweep only WRITES framebuffers. picgate.py is what compares them and prints
# 45/45, and this script never called it. **The renderer gate's headline number had no producer
# here either**, which is the same defect as res and cel wearing different clothes: the launch
# was recorded and the ADJUDICATION was not. ★★ A sweep that exits 0 having written 90 .bin files
# looks exactly like a gate that passed.
if [ "$WHICH" = "pic" ] || [ "$WHICH" = "all" ]; then
    run "renderer (45 pictures)" harness/tools/pic_sweep.lua 900 src/harness/pic_probe.s build/pic_probe.bin $M
    python harness/tools/picgate.py build/sweep build/picset/picset.json
    echo
fi

# ★★ res: ten (title, volume) pairs, one MAME launch each. res_run.ps1 owns the loop, assembles
# its own probe, and res_aggregate.py computes the 1,264 -- which previously had no producer.
if [ "$WHICH" = "res" ] || [ "$WHICH" = "all" ]; then
    echo "═══ resources (1,264 fetches, 10 volumes) ═══"
    powershell -NoProfile -ExecutionPolicy Bypass -File harness/tools/res_run.ps1 >/dev/null 2>&1
    python harness/tools/res_aggregate.py
    echo
fi

# ★★ cel: six staged titles. cel_run.sh did not exist until T-P0-039; 9,193 came from a hand
# loop nobody wrote down.
if [ "$WHICH" = "cel" ] || [ "$WHICH" = "all" ]; then
    sh harness/tools/cel_run.sh
    echo
fi

# ★★★ comp takes a STAGE and a FRAMES dir and there is no default worth trusting: build/comp_stage
# holds twelve directories, most of them scratch from past experiments (KQ2-r1, PQ1gate2, one78).
# Falling back to one of them silently is how a gate reports on a sample nobody chose.
if [ "$WHICH" = "comp" ] || [ "$WHICH" = "all" ]; then
    echo "═══ compositing ═══"
    echo "★ run explicitly, e.g.:"
    echo "    sh harness/tools/run_comp_sweep.sh build/comp_stage/SpaceQuest-1 oracle/dumps/frames-SpaceQuest-1"
    echo "  (the default stage is NOT the gate -- see this file's header)"
    echo
fi
exit 0
