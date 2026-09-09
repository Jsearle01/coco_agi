#!/bin/sh
# harness/tools/gs_run.sh -- the get.string gate over its declared corpus. [P6.23 AC-3]
#
# ★★★★ THE SAME NINE TITLES the text and port gates run, declared rather than discovered [L-85].
# ★★★ IT EXITS NON-ZERO ON ANY FAILURE, including a probe that produced no records [L-72].
#
# ★★★★★ ARMS. The fault lives in the REFERENCE for this gate rather than in the port, and that is
# a deliberate difference from text_port_run.sh: what needs proving here is that the gate can see
# a one-byte error in the buffer-full test, and the cheapest expression of that is to hand the
# reference one extra byte. **A correct port must then FAIL.** The runner inverts the verdict.
# ★★ Only ONE leg moves -- text_port_run.sh's first version moved both and printed a full pass
# from a build whose purpose was to fail [L-73].
set -e
cd /c/Users/jayse/DEV/coco_agi
GAMES=/c/Projects/agi-games/pc
MAME=${MAME:-/c/mame/mame.exe}
LWASM=${LWASM:-/c/WIN_LWTools/lwasm.exe}

ARM=""
EXPECT_FAIL=""
case "$1" in
    --fault-maxlen) ARM="--fault-maxlen"; EXPECT_FAIL="maxlen"; shift ;;
esac

TITLES=${TITLES:-"Kingquest1 Kingquest2 Kingquest3 SpaceQuest-1 SpaceQuest-2 PoliceQuest1 larry1 BlackCauldron MixedUpMotherGoose"}

mkdir -p build
echo "═══ build ═══"
"$LWASM" --raw -I. --map=build/gs_probe.map -o build/gs_probe.bin src/harness/gs_probe.s
printf '  gs_probe.bin %s bytes\n' "$(wc -c < build/gs_probe.bin)"

FAILED=""
RAN=0
for t in $TITLES; do
    [ -d "$GAMES/$t" ] || { echo "★★★ $t : no game dir"; FAILED="$FAILED $t(nodir)"; continue; }
    python harness/tools/gs_gate.py --emit "$GAMES/$t" build/gs_cases.bin build/gs_table.bin
    rm -f build/gs_6809_results.bin
    GS_CASES=build/gs_cases.bin GS_TABLE=build/gs_table.bin \
    GS_OUT=build/gs_6809_results.bin \
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -nothrottle -seconds_to_run "${GS_SECS:-600}" \
        -autoboot_script harness/tools/gs_gate.lua 2>&1 | tail -"${TAIL:-2}"
    if [ ! -s build/gs_6809_results.bin ]; then
        echo "★★★ $t : the probe produced NO records -- a failure, not a skip"
        FAILED="$FAILED $t(norun)"
        continue
    fi
    RAN=$((RAN + 1))
    # shellcheck disable=SC2086
    if python harness/tools/gs_gate.py --check "$GAMES/$t" build/gs_6809_results.bin $ARM; then
        [ -n "$EXPECT_FAIL" ] && FAILED="$FAILED $t(FAULT-NOT-CAUGHT)"
    else
        [ -z "$EXPECT_FAIL" ] && FAILED="$FAILED $t"
    fi
done

echo "═══════════════════════════════════════════════════════════════════════"
if [ -n "$EXPECT_FAIL" ]; then
    if [ -n "$FAILED" ]; then
        echo "★★★ $EXPECT_FAIL FAULT NOT CAUGHT on:$FAILED -- the gate is blind to it"
        exit 1
    fi
    echo "★ $EXPECT_FAIL fault CAUGHT on all $RAN titles -- the gate can go red"
    exit 0
fi
if [ -n "$FAILED" ]; then
    echo "★★★ GET.STRING GATE FAILED:$FAILED   ($RAN of 9 titles gated)"
    exit 1
fi
echo "★ GET.STRING GATE PASS over all $RAN titles"
exit 0
