#!/bin/sh
# harness/tools/text_run.sh -- the TEXT GATE over its whole declared corpus. [P6.18 AC-7]
#
# ★★★★★ P6.17 GATED ONE TITLE AND REPORTED "596". L-85 is the standing lesson that the corpus is
# part of the claim, and 596 turned out to be 4% of the staged messages -- 14,944 across the nine
# v2 titles (harness/tools/text_census.py). This declares the corpus the way comp_run.sh declares
# its six and res_aggregate.py declares its ten volumes: **a directory appearing in oracle/dumps/
# cannot join the gate by being present.**
#
# ★★★★ IT EXITS NON-ZERO ON ANY FAILURE, INCLUDING A MISSING DUMP [L-72]. A runner that exits 0 on
# a partial run asserts more than it tested, and that is precisely how two segfaulting titles sat
# in a capture directory looking like results.
#
# ★★★ Re-capture with:  sh harness/tools/text_capture.sh
#
# usage:  sh harness/tools/text_run.sh [extra text_gate.py args...]
set -e
cd /c/Users/jayse/DEV/coco_agi
GAMES=/c/Projects/agi-games/pc

TITLES="Kingquest1 Kingquest2 Kingquest3 SpaceQuest-1 SpaceQuest-2 PoliceQuest1 larry1 BlackCauldron MixedUpMotherGoose"

FAILED=""
RAN=0
for t in $TITLES; do
    log="oracle/dumps/text-$t/text_events.txt"
    if [ ! -f "$log" ]; then
        echo "★★★ $t : NO ORACLE DUMP at $log -- capture it before believing this gate"
        FAILED="$FAILED $t(nodump)"
        continue
    fi
    RAN=$((RAN + 1))
    python harness/tools/text_gate.py "$GAMES/$t" "$log" "$@" || FAILED="$FAILED $t"
done

echo "═══════════════════════════════════════════════════════════════════════"
if [ -n "$FAILED" ]; then
    echo "★★★ TEXT GATE FAILED:$FAILED   ($RAN of 9 titles gated)"
    exit 1
fi
echo "★ TEXT GATE PASS over all $RAN titles"
exit 0
