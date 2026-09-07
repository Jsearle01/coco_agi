#!/bin/sh
# harness/tools/gate_budget_check.sh -- is a gate's SESSION budget charged to the batch, and can
# the gate tell when it is spent? [T-P0-060 AC-3]
#
# ★★★★★ THIS SCRIPT EXISTS BECAUSE ITS OUTPUT WAS PUBLISHED WITHOUT IT. T-P0-060 §5 quotes both
# measurements below as verdict-time evidence, and both came from files in a scratch directory
# that no reader could run. **That is the L-45 defect on the evidence for a finding about
# instruments**, which is about as pointed as it gets, and Jay caught it.
#
# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★ WHAT IT ASKS. `-seconds_to_run` bounds a whole MAME session in EMULATED seconds, and every
# gate in this harness runs its whole corpus inside ONE session -- so that bound is a clock
# charged to a BATCH by construction, the shape that declared four working titles stalled in
# P6.3. run_gates.sh:92 calls it "a safety net rather than a budget that is always spent", which
# was true when written and which nothing re-checks.
#
# Two questions, two arms:
#
#   headroom   how much of the budget does the corpus actually spend? MAME prints
#              "Average speed: N% (S seconds)" at exit and S is EMULATED seconds, so this needs
#              no change to any gate. Measured for pic: 308 of 900 for 45 pictures, ~6.8 s each
#              -> the budget covers about 131, and the corpus is under pressure to widen [AD-113].
#
#   truncate   cut the session deliberately and ask the ADJUDICATOR what it says. Before the
#              L-92 fix, pic_sweep.lua never cleared build/sweep and picgate.py -- which
#              correctly drives from the manifest -- graded the previous run's files:
#              **45 PASS, 0 FAIL, 0 with no output (of 45), exit 0, on a run that rendered 8.**
#              ★★★ Both directions are run, because a cleanup that also breaks the good case
#              gets reverted and the gate goes back to grading history [§2W.1].
#
# ★★ -nothrottle throughout (§2U): nothing here measures wall clock. The figure is MAME's own
# emulated-second count and the comparison is the adjudicator's exit code.
#
# usage:  sh harness/tools/gate_budget_check.sh [headroom|truncate|all]
set -e
cd "$(dirname "$0")/../.." || exit 1
MAME=${MAME:-/c/mame/mame.exe}
WHICH=${1:-all}
OUT=${GBC_OUT:-build/gate_budget}
mkdir -p "$OUT"

# ★ The gate under test. Only pic is wired: it is the one whose corpus is one session, whose
# adjudicator is separate, and whose headline number is cited in every report since P4. Adding a
# row here means naming its budget, its sweep and its adjudicator -- deliberately, not by pattern.
PIC_BUDGET=${PIC_BUDGET:-900}
PIC_SHORT=${PIC_SHORT:-60}

mame_run() {   # mame_run <seconds> <logfile>
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -nothrottle -seconds_to_run "$1" -skip_gameinfo \
        -autoboot_script harness/tools/pic_sweep.lua > "$2" 2>&1 || true
    grep -E "Average speed" "$2" || echo "(no speed line -- did MAME start?)"
}

rendered() {   # how many pictures did the LAST run actually render, from its own timing.csv
    expr "$(wc -l < build/sweep/timing.csv)" - 1
}

if [ "$WHICH" = "headroom" ] || [ "$WHICH" = "all" ]; then
    echo "═══ headroom: how much of pic's ${PIC_BUDGET}s session budget does the corpus spend? ═══"
    mame_run "$PIC_BUDGET" "$OUT/headroom.log"
    n=$(rendered)
    echo "  pictures rendered this run : $n"
    echo "  ★ compare the emulated seconds above against the ${PIC_BUDGET}s budget."
    echo "    The per-picture cost is what says how far the corpus can widen before the"
    echo "    session is cut with no diagnostic at all."
    echo
fi

if [ "$WHICH" = "truncate" ] || [ "$WHICH" = "all" ]; then
    echo "═══ truncate: does the gate NOTICE a session cut short? (§2W, both directions) ═══"
    echo "-- DIRECTION 1: ${PIC_SHORT}s of the ${PIC_BUDGET}s -- the gate MUST fail --"
    mame_run "$PIC_SHORT" "$OUT/d1.log"
    grep -E "^cleared" build/sweep/run.log || echo "  (no clear line -- pic_sweep.lua is not clearing!)"
    echo "  pictures this run rendered : $(rendered)"
    echo "  .fb.bin files present      : $(ls build/sweep/*.fb.bin 2>/dev/null | wc -l)"
    set +e
    python harness/tools/picgate.py build/sweep build/picset/picset.json > "$OUT/d1.gate" 2>&1
    D1=$?
    set -e
    grep -E "per-picture:" "$OUT/d1.gate"
    echo "  picgate exit: $D1   (must be NON-ZERO)"
    echo

    echo "-- DIRECTION 2: the real ${PIC_BUDGET}s -- the gate MUST pass --"
    mame_run "$PIC_BUDGET" "$OUT/d2.log"
    grep -E "^cleared" build/sweep/run.log || true
    echo "  pictures this run rendered : $(rendered)"
    set +e
    python harness/tools/picgate.py build/sweep build/picset/picset.json > "$OUT/d2.gate" 2>&1
    D2=$?
    set -e
    grep -E "per-picture:|games covered:" "$OUT/d2.gate"
    echo "  picgate exit: $D2   (must be ZERO)"
    echo

    echo "═══ VERDICT ═══"
    if [ "$D1" -ne 0 ] && [ "$D2" -eq 0 ]; then
        echo "★ two-sided: the gate FAILS a truncated run and PASSES a complete one."
    else
        echo "★★★ NOT two-sided -- d1=$D1 d2=$D2. Do not believe this gate's 45/45."
        exit 1
    fi
fi
