#!/bin/sh
# harness/tools/cel_run.sh -- THE CEL GATE. 6,782 cels across the staged titles, on the 6809.
#
# ★★★★★ THIS RUNNER DID NOT EXIST. The cel gate's "6,782 cels across 5 titles" has been cited by
# number in every report since P4, and the command that produces it was in NO FILE ANYWHERE --
# not a .sh, not a .ps1, not the idioms doc. cel_sweep.lua drives exactly ONE stage (its default
# is build/cel_stage/Kingquest1), so 6,782 came from a hand-typed loop over six stage directories
# that nobody wrote down.
#
# ★★★★ THAT IS THE L-45 DEFECT, AND run_gates.sh WAS WRITTEN TO FIX IT AND DID NOT. run_gates.sh
# claims in its own header that `cel` produces "6,782 cels across 5 titles", beside a line that
# launches cel_sweep.lua ONCE against the default stage. **The header records the number; the
# command underneath it cannot produce that number.** A partial result printed with exit 0 reads
# as a pass, which is why this survived: the gate never announced that it had run one title.
#
# ★★ Staleness was the smaller half of this audit. A stale binary tests the wrong CODE; an
# unrecorded invocation means the published number cannot be reproduced by anyone, including its
# author. The second is worse and it was found only by running the runner and counting.
#
# usage:  sh harness/tools/cel_run.sh [stage-root]
set -e
STAGEROOT=${1:-build/cel_stage}
MAME=${MAME:-/c/mame/mame.exe}
LWASM=${LWASM:-/c/WIN_LWTools/lwasm.exe}

# ★ Flags from gates.manifest's cel row -- MODE_SERVICE+FAST_CLOCK, recovered by size-match
# against the shipped 1,436-byte artifact. A blanket MODE_SERVICE alone builds 1,432 and is a
# different program.
$LWASM --raw -I. -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -o build/cel_probe.bin src/harness/cel_probe.s
echo "cel_probe: $(stat -c %s build/cel_probe.bin) bytes (assembled by this script)"
echo "  [source-tree $(python harness/tools/gate_audit.py --hash src/harness/cel_probe.s)]"

TITLES=""
for d in "$STAGEROOT"/*/; do
    [ -d "$d" ] || continue
    t=$(basename "$d")
    TITLES="$TITLES $t"
    echo "═══ $t ═══"
    CEL_STAGE="$d" CEL_OUT="build/cel_sweep/$t" CEL_PROG=build/cel_probe.bin \
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -seconds_to_run "${SECS:-900}" -autoboot_script harness/tools/cel_sweep.lua 2>&1 | tail -"${TAIL:-4}"
done

echo
echo "═══ gate over:$TITLES ═══"
# ★ celgate.py takes the titles positionally and aggregates against oracle/dumps. THIS is where
# 6,782 comes from -- the per-title runs only produce the sweeps it reads.
python harness/tools/celgate.py $TITLES --sweep build/cel_sweep
