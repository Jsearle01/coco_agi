#!/bin/sh
# harness/tools/text_show.sh -- AC-1's eye gate. Jay watches this. [T-P0-075]
#
# ★★★★★ NO -nothrottle. §2U.2: every gate whose output is a byte comparison runs unthrottled and
# every gate whose output is a HUMAN JUDGEMENT does not. A message box that appears and vanishes
# at 2869% is not something anyone can assess.
#
# ★★★★ WHAT TO LOOK FOR, so the gate is a question rather than an impression:
#   1. A WHITE BOX with BLACK lettering, centred horizontally, on a black screen.
#   2. The text WRAPPED -- lines break between words, not mid-word, and the box is only as wide
#      as its longest line.
#   3. Successive messages produce boxes of DIFFERENT sizes and positions, because the box is
#      sized from its own text and centred vertically from its own height.
#   4. Letters that are LETTERS. The port gate proves every glyph is in the right place with the
#      right colours and the right identity-hash; it cannot prove the blitter draws the shape.
#
# ★★★ LAUNCH PATH: poke (§4). The program is written into RAM and the PC set, which HIDES load
# and launch bugs -- record it as `poke`, never as an unqualified pass.
#
# usage:  sh harness/tools/text_show.sh [title] [n-messages]
set -e
cd /c/Users/jayse/DEV/coco_agi
MAME=${MAME:-/c/mame/mame.exe}
LWASM=${LWASM:-/c/WIN_LWTools/lwasm.exe}
TITLE=${1:-Kingquest1}
NMSG=${2:-12}

mkdir -p build
"$LWASM" --raw -I. --map=build/text_show.map -o build/text_show.bin src/harness/text_show.s
printf '  text_show.bin %s bytes\n' "$(wc -c < build/text_show.bin)"

python harness/tools/text_font_stage.py build/text_font.bin
python harness/tools/text_port_gate.py --emit "/c/Projects/agi-games/pc/$TITLE" \
       build/text_cases.bin build/text_table.bin

# ★★★★ TS_VERIFY=1 runs the same probe HEADLESS and reports non-black bytes per character row --
# a framebuffer readback, which is structured text and therefore Clyde's to evaluate, unlike a
# screenshot (§3). It is what makes "the eye gate is ready" a measurement instead of a claim, and
# it is deliberately NOT a substitute for the gate: it cannot tell a letter from a smudge.
if [ "$TS_VERIFY" = "1" ]; then
    TS_NMSG="$NMSG" TS_HOLD="${TS_HOLD:-2}" TS_VERIFY=1 \
    "$MAME" coco3 -rompath C:/mame/roms -video none -sound none -window -nomaximize \
        -nothrottle -seconds_to_run "${TS_SECS:-20}" \
        -autoboot_script harness/tools/text_show.lua
    exit $?
fi

TS_NMSG="$NMSG" TS_HOLD="${TS_HOLD:-90}" \
"$MAME" coco3 -rompath C:/mame/roms -window -nomaximize \
    -seconds_to_run "${TS_SECS:-40}" \
    -autoboot_script harness/tools/text_show.lua
