#!/bin/sh
# oracle_dump.sh -- drive the pinned, instrumented ScummVM and capture the oracle dumps.
#
# ★★ WHAT THIS PRODUCES IS THE BASELINE EVERYTHING ELSE IS DIFFED AGAINST (design §10), so
# read CLAUDE.md §2O.1 before changing it: NOTHING WE WRITE MAY PARTICIPATE IN PRODUCING IT.
# This script SELECTS and COPIES; it does not transform. The bytes come out of ScummVM's own
# _gameScreen / _priorityScreen / flags[] / vars[] and are moved, never converted. If a
# conversion is ever needed it belongs in a SEPARATE tool with a separate name, so that "raw
# oracle output" and "something we computed" can never be confused for one another.
#
# ★ BLOCKED AS OF P0.2: this script cannot be exercised yet. There is no AGI game data on this
# machine and the game set is Jay's to pin (§2Q, oracle/scummvm.pin [game-set]). Everything
# below is written and reviewable; it runs the moment a game directory exists.
#
# Usage:
#   sh harness/tools/oracle_dump.sh <game-dir> <out-dir> [scummvm-binary]
#
# ★ THE GAME DIRECTORY IS OPENED READ-ONLY, ALWAYS (§2P). VOL and DIR files are the user's
# game. This script never writes into <game-dir> -- ScummVM is run with its working directory
# set to <out-dir>, which is where the instrumentation drops its files, and the game is
# reached by path. A tool that opens a game file for writing is a bug.
set -e

GAME_DIR=${1:?usage: oracle_dump.sh <game-dir> <out-dir> [scummvm-binary]}
OUT_DIR=${2:?usage: oracle_dump.sh <game-dir> <out-dir> [scummvm-binary]}
SCUMMVM=${3:-$HOME/scummvm/scummvm}

[ -d "$GAME_DIR" ] || { echo "no such game dir: $GAME_DIR" >&2; exit 2; }
[ -x "$SCUMMVM" ]  || { echo "no scummvm binary: $SCUMMVM" >&2; exit 2; }

GAME_ABS=$(cd "$GAME_DIR" && pwd)
mkdir -p "$OUT_DIR"
OUT_ABS=$(cd "$OUT_DIR" && pwd)

echo "oracle   : $SCUMMVM"
echo "game     : $GAME_ABS   (READ-ONLY)"
echo "out      : $OUT_ABS"

# ★ The instrumentation writes into the PROCESS WORKING DIRECTORY (see the patches: ScummVM's
# forbidden-symbol policy rules out getenv/fopen, so Common::DumpFile writes relative paths).
# Running from $OUT_ABS is therefore what places the dumps, and it is also what keeps them out
# of the game directory.
cd "$OUT_ABS"

# --auto-detect finds the game in the CWD, so point it at the game by path instead and let
# ScummVM detect there without us naming a target id we have not pinned yet.
"$SCUMMVM" \
    --path="$GAME_ABS" \
    --auto-detect \
    --no-console \
    2>&1 | tail -20 || true

echo
echo "=== dumps produced ==="
ls -la pic*.visual.bin pic*.priority.bin vmstate.txt 2>/dev/null || echo "(none -- see above)"

echo
echo "=== sizes: each screen must be exactly 26880 bytes (160 x 168) ==="
for f in pic*.visual.bin pic*.priority.bin; do
    [ -e "$f" ] || continue
    sz=$(wc -c < "$f")
    if [ "$sz" -eq 26880 ]; then echo "  OK   $f  $sz"; else echo "  WRONG $f  $sz (expected 26880)"; fi
done

echo
echo "=== sha256 (this is the AC-7 evidence; run twice and compare) ==="
sha256sum pic*.visual.bin pic*.priority.bin vmstate.txt 2>/dev/null || true
