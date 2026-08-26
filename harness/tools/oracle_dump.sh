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
# ★ UNBLOCKED AT P0.3. The corpus is pinned at lanceewing/agile-gdx@81c42ba (150 titles) and
# this script has been exercised against it. See oracle/scummvm.pin [game-set].
#
# ★★ DETERMINISM WAS VERIFIED BEFORE ANY DUMP WAS USED (P0.3 AC-3): two separate invocations
# over the same game produce byte-identical visual and priority buffers. Do not build anything
# on a dump from a modified oracle until that check has been re-run.
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
# ★ P4.2: the oracle is now built NATIVELY on Windows and this script runs under Git Bash,
# which is itself MINGW64_NT with full coreutils (timeout, sha256sum, diff, mv). WSL is not
# required for any part of this project. See oracle/scummvm.pin [build-native].
#
# The default is the native build; pass $3 to override. The former WSL path
# ($HOME/scummvm/scummvm) still works if given explicitly, and the two binaries were verified
# to produce byte-identical dumps — but nothing depends on WSL any more.
SCUMMVM=${3:-/c/Projects/scummvm/scummvm.exe}

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
# ★ DETERMINISM CONTROLS (P4.1). Both are required for a state diff to mean anything; see
# oracle/scummvm.pin [determinism].
#   --random-seed  pins Common::RandomSource, which otherwise seeds from the time of day.
#                  Costs nothing for a game that never calls random, and is the difference
#                  between reproducible and not for one that does.
#   patch 0005     replaces the wall-clock in-game timer with a virtual clock. WITHOUT IT the
#                  dump is host-speed dependent and vars 11/72/73 drift under load -- and the
#                  drift is INVISIBLE on an idle machine, so its absence is not reassurance.
SECS=${SECS:-30}
SEED=${SEED:-12345}
timeout "$SECS" "$SCUMMVM" \
    --path="$GAME_ABS" \
    --auto-detect \
    --random-seed="$SEED" \
    > scummvm.log 2>&1 || RC=$?
RC=${RC:-0}
# ★★ `|| RC=$?` IS LOAD-BEARING, NOT DEFENSIVE NOISE. This script runs under `set -e` and the
# EXPECTED exit code here is 124 (timeout) -- an AGI game does not end by itself. Without the
# guard, set -e aborted the script the instant ScummVM was killed, so the rename below never
# ran and every long-lived dump was left as a .tmp file. Measured at P4.1 on Kingquest1: the
# script printed its three header lines and stopped, and vmstate.txt.tmp sat there unrenamed.
echo "scummvm exit=$RC  (124 = timeout, which is NORMAL: an AGI game does not end by itself)"
tail -4 scummvm.log

# ★ ScummVM's Common::DumpFile writes ATOMICALLY: backends/fs/stdiostream.cpp appends ".tmp"
# and renames on close. `timeout` SIGTERMs the process, so the long-lived logs never close and
# stay as <name>.tmp. The picture dumps DO finalize, because oracleDumpScreens closes each file
# explicitly. What follows is the rename close() would have performed.
#
# ★ A RENAME IS NOT A TRANSFORMATION. No byte is read, altered or recomputed here, so §2O.1 is
# untouched -- this remains ScummVM's output, moved, not ours.
# ★ The `|| true` matters for the same reason: under `set -e` a missing .tmp made the test
# return 1 and killed the script. row24.txt is only produced by patch 0003's probe, so its
# absence is the NORMAL case and it was aborting the rename of vmstate.txt behind it.
for t in vmstate.txt row24.txt; do
    if [ -f "$t.tmp" ]; then mv "$t.tmp" "$t"; fi
done || true

echo
echo "=== dumps produced ==="
ls -la pic*.visual.bin pic*.priority.bin vmstate.txt row24.txt 2>/dev/null || echo "(none -- see above)"

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
