#!/bin/sh
# harness/tools/pic_seedfault.sh -- P6.13 AC-6: can the renderer gate FAIL on a seed-stack overflow?
#
# ★★★★★ THE CLAIM UNDER TEST IS pic_fill.s's "STACK OVERFLOW HALTS", and until now it was an
# assertion. Every picture in the gate corpus peaks at 37 seed entries against a 384-entry stack
# -- the halt sits 10x away from anything the gate reaches, so a green run says nothing about it
# [L-62, §2W: a gate must be able to fail on the path it claims to cover].
#
# ★★★★ -DPIC_SEEDFAULT drops the ceiling to 20 entries, below the corpus maximum of 37
# (Kingquest1-009, 74 bytes). The DEEP pictures must go red and the SHALLOW ones must stay green:
# a fault that broke all 45 would prove only that the binary changed, and a fault that broke none
# would prove the halt is unreachable. **The split is the evidence.**
#
# ★★★ It mirrors run_gates.sh's own pic invocation rather than inventing one -- same lua, same
# 900 emulated seconds, same -nothrottle, same picgate.py adjudication -- so the only difference
# between this arm and the gate is the one flag [L-56: the first measurement often measures the
# scaffolding].
#
# ★★ It restores the good binary at the end. A fault build left in build/pic_probe.bin would be
# picked up by the next gate run as if it were the real thing [L-92's shape].
#
# usage:  sh harness/tools/pic_seedfault.sh
set -e
cd /c/Users/jayse/DEV/coco_agi
LW=/c/WIN_LWTools/lwasm.exe
MAME=/c/mame/mame.exe

echo "=== building the SEED-FAULT arm (20-entry ceiling) ==="
"$LW" --format=raw --output=build/pic_probe.bin --map=build/pic_probe.map -I. \
      -DHAL_GFX_MODE_SERVICE -DPIC_SEEDFAULT src/harness/pic_probe.s
echo "  pic_probe (fault): $(stat -c%s build/pic_probe.bin) bytes"

"$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
    -nothrottle -seconds_to_run 900 \
    -autoboot_script harness/tools/pic_sweep.lua 2>&1 | tail -4

echo "=== adjudicating with the gate's own tool ==="
python harness/tools/picgate.py build/sweep build/picset/picset.json || echo "★ picgate reported FAILURES -- which is what this arm is for"

echo "=== restoring the good build ==="
"$LW" --format=raw --output=build/pic_probe.bin --map=build/pic_probe.map -I. \
      -DHAL_GFX_MODE_SERVICE src/harness/pic_probe.s
echo "  pic_probe (normal): $(stat -c%s build/pic_probe.bin) bytes"
