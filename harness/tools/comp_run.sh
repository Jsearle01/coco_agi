#!/bin/sh
# harness/tools/comp_run.sh -- THE COMP GATE. Every declared corpus, one launch each. [T-P0-061 AC-4]
#
# ★★★★★ run_gates.sh REFUSED TO DRIVE comp, AND THE REFUSAL WAS RIGHT AT THE TIME. Its comp block
# printed "run explicitly, e.g. ..." because build/comp_stage holds twelve directories, most of
# them scratch from past experiments (KQ2-r1, PQ1gate2, one78), and "falling back to one of them
# silently is how a gate reports on a sample nobody chose."
#
# ★★★★ THAT WAS AN ARGUMENT AGAINST A DEFAULT, NOT AGAINST A GATE. The fix is the one
# res_aggregate.py already uses for exactly the same problem: **declare the corpus.** A glob is
# what let the scratch dirs in; an explicit list is what keeps them out. So the six pairs below
# are the gate, and adding one is an edit to this line rather than a directory appearing.
# ★★★ A gate outside the suite is a gate that does not run [T-P0-060 §7.6] -- the same class as
# p3b having no row, which T-P0-060 closed. This is the last of them.
#
# ★★ EACH PAIR IS A STAGE AND ITS ORACLE FRAMES DIR, and they must correspond: comp_sweep.lua
# reads the before-planes and the expected after-planes from the FRAMES dir and the sprite records
# from the STAGE. Crossing them compares one title's composite against another's oracle, which
# reports a divergence in the renderer for a wiring mistake.
#
# usage:  sh harness/tools/comp_run.sh [stage-root]
set -e
cd "$(dirname "$0")/../.." || exit 1
MAME=${MAME:-/c/mame/mame.exe}

# ★ The declared corpus. `frames-<name>` under oracle/dumps must exist for each.
CORPORA="Kingquest2 Kingquest3 KQ1ego1 larry1 PoliceQuest1 SpaceQuest-1"

TOTF=0; TOTP=0; TOTD=0; BAD=""
for t in $CORPORA; do
    stage="build/comp_stage/$t"
    frames="oracle/dumps/frames-$t"
    echo "═══ $t ═══"
    if [ ! -f "$stage/frames.txt" ]; then
        echo "★★★ no $stage/frames.txt -- run comp_stage.py for $t"; BAD="$BAD $t"; continue
    fi
    if [ ! -d "$frames" ]; then
        echo "★★★ no $frames -- the oracle dump for $t is missing"; BAD="$BAD $t"; continue
    fi
    want=$(grep -c . "$stage/frames.txt")

    COMP_OUT="build/comp_sweep/$t" \
    sh harness/tools/run_comp_sweep.sh "$stage" "$frames" > "build/comp_run_$t.log" 2>&1 || true

    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ ADJUDICATE ON THE SUMMARY, AND TREAT ITS ABSENCE AS A FAILURE.
    # comp_sweep.lua prints "★ N frames: P identical, D divergent" only when it reaches the end
    # of its list. A session cut short by -seconds_to_run never prints it -- so a MISSING summary
    # is a truncated run, and reading only the per-frame lines that did appear would report a
    # smaller corpus at 100%. That is res_aggregate.py's defect [T-P0-061 AC-2] and the renderer
    # gate's [T-P0-060], and this is where comp would have grown it.
    # ★★ The frame COUNT is checked against the stage's own frames.txt as well, so a summary that
    # reports fewer frames than were staged is caught even if it does print.
    line=$(grep -oE "[0-9]+ frames: [0-9]+ identical, [0-9]+ divergent" "build/comp_run_$t.log" | tail -1)
    if [ -z "$line" ]; then
        echo "★★★ $t: NO SUMMARY LINE -- the sweep did not finish (session cut short?)"
        tail -3 "build/comp_run_$t.log"
        BAD="$BAD $t"; continue
    fi
    n=$(echo "$line" | awk '{print $1}')
    p=$(echo "$line" | awk '{print $3}')
    d=$(echo "$line" | awk '{print $5}')
    echo "  $line   (staged for $want)"
    # ★★ `if`, NOT `[ ... ] && ...`. Under `set -e` a bare test-and-and whose test is FALSE is a
    # failing last command, and whether that aborts the loop depends on the shell -- so the green
    # path is the one at risk, silently, on a construct that reads as a one-line guard.
    if [ "$n" -ne "$want" ]; then
        echo "★★★ $t: $n frames compared, $want staged"; BAD="$BAD $t"
    fi
    if [ "$d" -ne 0 ]; then BAD="$BAD $t"; fi
    TOTF=$((TOTF + n)); TOTP=$((TOTP + p)); TOTD=$((TOTD + d))
done

echo
echo "═══ comp gate over:$CORPORA ═══"
printf 'frames %d   identical %d   divergent %d\n' "$TOTF" "$TOTP" "$TOTD"
if [ -n "$BAD" ]; then
    echo "★★★ COMP FAILED:$BAD"
    exit 1
fi
echo "★ composites byte-identical on both planes: $TOTP / $TOTF frames (100.00%)"
