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
    # ★★★★★ P6.21's arm: the substitution buffer is now sized from a census (576 B against a
    # measured maximum of 490), and **a buffer sized from a census needs the arm that proves the
    # census bounds it.** This shrinks it to 256 -- below the corpus maximum -- so long messages
    # truncate at txt_put and every downstream number moves. If the gate stays green here, the
    # census is unfalsifiable and the 576 is a number nobody checked [§2W, trigger 3].
    --fault-pbuf)   EXPECT_FAIL="pbuf"   ; FLAG="-DTXT_FAULT_PBUF"   ; shift ;;
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
    # ★★★★★ THE pbuf ARM PREDICTS PER TITLE, AND A PASS THERE IS CORRECT RATHER THAN BLIND.
    # Shrinking the buffer to 256 can only change a title whose longest SUBSTITUTED message
    # exceeds 256; Kingquest1's swept maximum is 203 and Kingquest2's is 248, so those two must
    # still agree and a "fault not caught" verdict on them would be the RUNNER being wrong.
    # ★★★★ So this arm asserts the exact set, from harness/tools/text_bufmax.py's per-title
    # figures: 203 248 458 334 274 275 490 222 55 against a faulted bound of 256.
    # **An arm that merely "fails somewhere" would pass even if it failed for the wrong reason**;
    # this one fails if a title diverges that should not, or agrees when it should not.
    want_fail=""
    if [ "$EXPECT_FAIL" = "pbuf" ]; then
        case "$t" in
            Kingquest3|SpaceQuest-1|SpaceQuest-2|PoliceQuest1|larry1) want_fail=yes ;;
            *) want_fail=no ;;
        esac
    elif [ -n "$EXPECT_FAIL" ]; then
        want_fail=yes
    else
        want_fail=no
    fi

    if python harness/tools/text_port_gate.py --check "$GAMES/$t" \
              build/text_6809_results.bin; then
        [ "$want_fail" = "yes" ] && FAILED="$FAILED $t(FAULT-NOT-CAUGHT)"
    else
        [ "$want_fail" = "no" ] && FAILED="$FAILED $t(UNEXPECTED-DIVERGENCE)"
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
