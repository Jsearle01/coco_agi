#!/bin/sh
# harness/tools/text_port_run.sh -- the PORT gate over its declared nine-title corpus.
# [T-P0-075 AC-3 / AC-4]
#
# ★★★★★ THE SAME NINE TITLES THE REFERENCE IS GATED ON, DECLARED HERE RATHER THAN DISCOVERED.
# text_run.sh gates the Python against the oracle at 4,594 rectangles and 293,648 glyphs; this
# gates the 6809 against the Python at the same messages. **A directory appearing in build/ cannot
# join the gate by being present** [L-85, and comp_run.sh's six corpora are the precedent].
#
# ★★★★ IT EXITS NON-ZERO ON ANY FAILURE [L-72]. A runner that exits 0 on a partial run asserts
# more than it tested.
#
# ★★★ ARMS. Three builds, and the two faulted ones are the §2W evidence that this gate can go red:
#     (default)         the port as it ships                     -- must PASS on all nine
#     --fault-wrap      TXT_FAULT_WRAP: the wrap test >= becomes > -- must FAIL on all nine
#     --fault-printf    TXT_FAULT_PRINTF: %v's zero-strip dropped  -- must FAIL on all nine
# ★★ The faults live in src/engine/text.s, not in this script and not in the comparator, so the
# gate cannot manufacture its own failure -- and they are the SAME two faults text.py carries, so
# both legs fail the same way for the same reason.
set -e
cd /c/Users/jayse/DEV/coco_agi
GAMES=/c/Projects/agi-games/pc
MAME=${MAME:-/c/mame/mame.exe}
LWASM=${LWASM:-/c/WIN_LWTools/lwasm.exe}

# ★★★★★ THE FAULT GOES IN ONE LEG ONLY, AND THE FIRST VERSION PUT IT IN BOTH.
# It passed -DTXT_FAULT_WRAP to the assembler AND --fault-wrap to the comparator, so the 6809 and
# the Python were faulted identically, agreed with each other, and the arm printed **PORT GATE
# PASS over all 9 titles** -- from a build whose whole purpose was to fail.
# ★★★★ That is L-73 exactly: an ablation that moves the same variable in both arms exonerates
# nothing. And it is the §2W failure in its most embarrassing form -- the instrument written to
# prove the gate can go red was the thing that could not.
# ★★★ So EXPECT_FAIL builds the faulted port and checks it against the CORRECT reference. The arm
# now inverts the verdict: a PASS here is the failure.
EXPECT_FAIL=""
FLAG=""
case "$1" in
    --fault-wrap)   EXPECT_FAIL="wrap"   ; FLAG="-DTXT_FAULT_WRAP"   ; shift ;;
    --fault-printf) EXPECT_FAIL="printf" ; FLAG="-DTXT_FAULT_PRINTF" ; shift ;;
esac

TITLES=${TITLES:-"Kingquest1 Kingquest2 Kingquest3 SpaceQuest-1 SpaceQuest-2 PoliceQuest1 larry1 BlackCauldron MixedUpMotherGoose"}

# ★★★★ BUILD WHAT WE TEST. run_gates.sh's header records what a runner that supplies no program
# costs: the resource gate reported on a pre-cache binary for two tasks [L-70]. The map goes with
# it, because text_port_gate.lua reads symbols from the map and refuses a map older than the .bin.
mkdir -p build
echo "═══ build ═══"
# shellcheck disable=SC2086
"$LWASM" --raw -I. $FLAG --map=build/text_probe.map -o build/text_probe.bin \
        src/harness/text_probe.s
printf '  text_probe.bin %s bytes%s\n' "$(wc -c < build/text_probe.bin)" \
       "$([ -n "$FLAG" ] && echo "   ARM: $FLAG")"

FAILED=""
RAN=0
for t in $TITLES; do
    [ -d "$GAMES/$t" ] || { echo "★★★ $t : no game dir"; FAILED="$FAILED $t(nodir)"; continue; }
    python harness/tools/text_port_gate.py --emit "$GAMES/$t" \
           build/text_cases.bin build/text_table.bin
    rm -f build/text_6809_results.bin
    TXP_CASES=build/text_cases.bin TXP_TABLE=build/text_table.bin \
    TXP_OUT=build/text_6809_results.bin \
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -nothrottle -seconds_to_run "${TXP_SECS:-900}" \
        -autoboot_script harness/tools/text_port_gate.lua 2>&1 | tail -"${TAIL:-3}"
    if [ ! -s build/text_6809_results.bin ]; then
        echo "★★★ $t : the probe produced NO records -- treated as a failure, not a skip"
        FAILED="$FAILED $t(norun)"
        continue
    fi
    RAN=$((RAN + 1))
    if python harness/tools/text_port_gate.py --check "$GAMES/$t" \
              build/text_6809_results.bin; then
        # ★★ On a fault arm a PASS is the failure: the faulted port agreed with the correct
        # reference, which means the gate cannot see this stage at all.
        [ -n "$EXPECT_FAIL" ] && FAILED="$FAILED $t(FAULT-NOT-CAUGHT)"
    else
        [ -z "$EXPECT_FAIL" ] && FAILED="$FAILED $t"
    fi
done

echo "═══════════════════════════════════════════════════════════════════════"
if [ -n "$EXPECT_FAIL" ]; then
    if [ -n "$FAILED" ]; then
        echo "★★★ $EXPECT_FAIL FAULT NOT CAUGHT on:$FAILED -- the gate is blind to this stage"
        exit 1
    fi
    echo "★ $EXPECT_FAIL fault CAUGHT on all $RAN titles -- the gate can go red on this stage"
    exit 0
fi
if [ -n "$FAILED" ]; then
    echo "★★★ PORT GATE FAILED:$FAILED   ($RAN of 9 titles gated)"
    exit 1
fi
echo "★ PORT GATE PASS over all $RAN titles"
exit 0
