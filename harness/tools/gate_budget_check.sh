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
    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ EVERY GATE, NOT JUST pic [T-P0-061 AC-6]. T-P0-060 measured pic at 308 of 900 and
    # measured nothing else, so four of five bounds were unweighed -- and an unweighed bound is
    # the assumption this whole instrument exists to replace.
    # ★★★★ THE UNIT IS ONE SESSION, because that is what -seconds_to_run bounds. pic and p3b run
    # their whole corpus in one; res, cel, comp and vm launch MAME per item, so their bound
    # applies to the LARGEST single item and the figure below is that item, not the total.
    # ★★★ Every number comes from MAME's own "Average speed: N% (S seconds)" line at exit. No
    # gate is modified and no timing is host-side [L-78].
    echo "═══ headroom: emulated seconds used vs -seconds_to_run, per gate ═══"
    echo
    printf '%-8s %-34s %8s %8s %7s\n' gate "unit the bound applies to" budget used pct
    printf -- '---------------------------------------------------------------------\n'

    row() {   # row <gate> <unit> <budget> <logfile-or-glob>
        used=$(grep -hoE "Average speed: [0-9.]+% \([0-9]+ seconds\)" $4 2>/dev/null |
               grep -oE "\([0-9]+ " | tr -d '( ' | sort -n | tail -1)
        [ -z "$used" ] && used=0
        pct=$(awk "BEGIN{printf \"%.0f\", 100*$used/$3}")
        printf '%-8s %-34s %8s %8s %6s%%\n' "$1" "$2" "$3" "$used" "$pct"
    }

    # pic -- one session, the whole 45-picture corpus
    mame_run "$PIC_BUDGET" "$OUT/hr_pic.log" >/dev/null
    row pic "45 pictures, ONE session" "$PIC_BUDGET" "$OUT/hr_pic.log"

    # cel -- one session per title; the bound applies to the largest (PoliceQuest1, 2,411 cels)
    sh harness/tools/cel_run.sh > "$OUT/hr_cel.log" 2>&1 || true
    row cel "largest title (PoliceQuest1)" 900 "$OUT/hr_cel.log"

    # comp -- one session per corpus; largest is KQ1ego1 at 24 frames.
    # ★★★★ THE LOGS ARE PER-CORPUS, NOT ON STDOUT. comp_run.sh redirects each launch to
    # build/comp_run_<title>.log, so grepping its stdout finds no speed line and prints **0** --
    # which is what the first version of this row did, and a 0 in a headroom table reads as
    # "uses nothing" rather than "measured nothing". ★★★ A zero from a missing input is the same
    # defect this instrument exists to find, one file along [§2W]. The glob is the fix, and
    # `row` takes the MAX across the six so the figure is the largest single session.
    sh harness/tools/comp_run.sh > "$OUT/hr_comp.log" 2>&1 || true
    row comp "largest corpus (KQ1ego1, 24)" 400 "build/comp_run_*.log"

    # res -- one session per (title, volume); largest is Kingquest3-v2 at 132 requests
    RES_OUT=build/res_sweep/Kingquest3-v2 RES_STAGE=build/res_stage/Kingquest3-v2 \
    RES_PROG=build/res_probe.bin \
    "$MAME" coco3 -video none -seconds_to_run 3000 -skip_gameinfo -nothrottle \
        -rompath C:/mame/roms -cfg_directory harness/mame-cfg \
        -autoboot_script C:/Projects/coco_agi/harness/tools/res_sweep.lua -autoboot_delay 0 \
        > "$OUT/hr_res.log" 2>&1 || true
    row res "largest volume (KQ3-v2, 132)" 3000 "$OUT/hr_res.log"

    # p3b -- one session, N cycles
    P3B_PROG=build/p3b_probe_pk_fresh.bin P3B_STAGE=build/vm_stage/Kingquest1 \
    P3B_SYMBOLS=build/p3b/symbols.txt P3B_CYCLES=160 P3B_OUT=build/p3b_headless P3B_HOLD=0 \
    "$MAME" coco3 -video none -sound none -window -nomaximize -skip_gameinfo -nothrottle \
        -seconds_to_run 900 -rompath C:/mame/roms -cfg_directory harness/mame-cfg \
        -autoboot_script C:/Projects/coco_agi/harness/tools/p3b_run.lua -autoboot_delay 0 \
        > "$OUT/hr_p3b.log" 2>&1 || true
    row p3b "160 cycles, ONE session" 900 "$OUT/hr_p3b.log"

    echo
    echo "★ vm is bounded at 100000 emulated seconds per title -- two orders above any observed"
    echo "  use, so it is not a bound in any practical sense and is reported as such rather than"
    echo "  measured against."
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
