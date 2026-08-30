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
#     pic   45/45 pictures, both planes      res   1,264/1,264 fetches
#     cel   6,782 cels across 5 titles       comp  20/20 SpaceQuest-1, 80/80 gameplay
set -e
MAME=${MAME:-/c/mame/mame.exe}
WHICH=${1:-all}

run() {   # run <name> <script> <seconds>
    echo "═══ $1 ═══"
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -seconds_to_run "$3" -autoboot_script "$2" 2>&1 | tail -"${TAIL:-6}"
    echo
}

[ "$WHICH" = "pic"  ] || [ "$WHICH" = "all" ] && run "renderer (45 pictures)"  harness/tools/pic_sweep.lua 900
[ "$WHICH" = "res"  ] || [ "$WHICH" = "all" ] && run "resources (1,264 fetches)" harness/tools/res_sweep.lua 900
[ "$WHICH" = "cel"  ] || [ "$WHICH" = "all" ] && run "cels (6,782)"            harness/tools/cel_sweep.lua 900
[ "$WHICH" = "comp" ] || [ "$WHICH" = "all" ] && run "compositing"             harness/tools/comp_sweep.lua 600
exit 0
