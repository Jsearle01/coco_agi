#!/bin/sh
# harness/tools/run_comp_sweep.sh -- drive comp_sweep.lua under MAME, headless.
#
# ★★★ SECOND FILE WRITTEN FOR THE SAME REASON AS build_comp.sh. The gate that produced every
# composite figure in P5.2 and P5.3 was launched from a command line that exists in NO file, so
# re-running AC-8 this task meant reconstructing it from the idioms doc. **L-45: an unsaved
# command cannot be audited.** A gate whose invocation is not on disk is not reproducible, and
# "the gate passed" is a claim about a command nobody can inspect.
#
# usage:  sh harness/tools/run_comp_sweep.sh <stage-dir> <frames-dir> [prog.bin]
#
# ★★ -video none -sound none -seconds_to_run: headless. `-seconds_to_run` is EMULATED seconds,
# not wall clock [idioms]. execution_state is left to the script; a headless -debug run HANGS
# without it, which is the gotcha this wrapper exists to keep from being rediscovered.
set -e
STAGE=${1:?stage dir, e.g. build/comp_stage/SpaceQuest-1}
FRAMES=${2:?frames dir, e.g. oracle/dumps/frames-SpaceQuest-1}
PROG=${3:-build/comp_probe.bin}
MAME=${MAME:-/c/mame/mame.exe}

export COMP_STAGE="$STAGE" COMP_FRAMES="$FRAMES" COMP_PROG="$PROG"
export COMP_OUT="${COMP_OUT:-build/comp_sweep}"

"$MAME" coco3 -rompath C:/mame/roms \
    -video none -sound none -window -nomaximize \
    -seconds_to_run "${SECS:-400}" \
    -autoboot_script harness/tools/comp_sweep.lua 2>&1 | tail -40
