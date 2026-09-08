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

# ★ ScummVM reads its config from the process working directory, which is this one. Writing the
# key here is how patch 0006's sweep is switched on without inventing a command-line option.
# When CEL_DUMP is off we write NOTHING, so a baseline run is bit-for-bit the run it was before
# patch 0006 existed.
# ★ Defaults BEFORE the test that reads them. They were set 40 lines below the `if`, which
# worked only because an unset variable compares false -- a fragility, not a design.
CEL_DUMP=${CEL_DUMP:-0}
SPRITE_DUMP=${SPRITE_DUMP:-0}
# ★★★★★ P6.15, patch 0010: the TEXT DECISION LOG. AC-3 needs an oracle for text and none existed
# -- the reference has no display buffer and every text opcode is a declared no-op on both legs,
# so a 6809 text renderer could not have been gated against anything [P6.14].
# ★★★★ IT LOGS CALLS, NOT PIXELS. oracleDumpScreens' own note rules out diffing a rendering
# ("would put ScummVM's upscaler inside our baseline"), and that argument transfers to text: a
# 320x200 dump would carry the upscaler, the font file and translateFontPosToDisplayScreen into
# the comparison. The glyph draws and the restore rectangle are the DECISIONS a reference must
# reproduce, and they are free of all three.
# ★★ Stale log removed before the run [L-92]: text_events.txt is APPENDED to, so one left behind
# would silently prepend a previous game's text to this one's and the diff would point at the
# reference.
TEXT_DUMP=${TEXT_DUMP:-0}
rm -f scummvm.ini text_events.txt text_events.txt.tmp
if [ "$CEL_DUMP" = "1" ] || [ "$SPRITE_DUMP" = "1" ] || [ "$TEXT_DUMP" = "1" ] || [ -n "$ROOM" ]; then
    printf '[scummvm]\n' > scummvm.ini
    if [ "$TEXT_DUMP" = "1" ]; then
        printf 'coco_text_dump=true\n' >> scummvm.ini
        echo "text     : ON  -- text_events.txt (G row col char fg bg | R x y w h)"
    fi
    if [ "$CEL_DUMP" = "1" ]; then
        printf 'coco_view_sweep=true\n' >> scummvm.ini
        echo "cel dump : ON  -- ★ this run's vmstate.txt is NOT a valid baseline"
    fi
    # ★★ P5.2, patch 0007: the composited-frame dump. AC-3 needs a REFERENCE for a composited
    # frame and none existed -- tools/agivm/blit.py is a cost model whose own header says
    # "pixels WRITTEN: NOT COMPUTED". So the oracle is asked, per CLAUDE.md §2O.1.
    #
    # ★ VERIFIED INERT WHEN OFF, which patch 0006 taught us not to assume: with the switch
    # off, the new binary's picture dumps are byte-identical to the old binary's and the
    # vmstate common prefix hashes the same. (vmstate LENGTH varies run to run because this
    # script kills the run on WALL CLOCK -- that is the timeout, not the engine.)
    if [ "$SPRITE_DUMP" = "1" ]; then
        printf 'coco_sprite_dump=true\n' >> scummvm.ini
        echo "sprite   : ON  -- frameNNN.{before,after}.{visual,priority}.bin + sprites.txt"
    fi
    # ★★★ P5.3, patch 0008: the ROOM JUMP. Without it an AGI game sits in its credits for the
    # whole window and the EGO is never composited -- measured at T-P0-028 as 0 of 1,680
    # frames. ROOM=<n> calls the engine's own newRoom(), the same entry the AGI debug console's
    # `room` command uses.
    # ★ A jumped run PERTURBS the engine and its vmstate.txt is NOT a valid baseline.
    if [ -n "$ROOM" ]; then
        printf 'coco_room=%s\n' "$ROOM" >> scummvm.ini
        [ -n "$ROOM_AFTER" ] && printf 'coco_room_after=%s\n' "$ROOM_AFTER" >> scummvm.ini
        [ -n "$EGO_X" ] && printf 'coco_ego_x=%s\ncoco_ego_y=%s\n' "$EGO_X" "$EGO_Y" >> scummvm.ini
        [ -n "$EGO_AFTER" ] && printf 'coco_ego_after=%s\n' "$EGO_AFTER" >> scummvm.ini
        echo "room     : JUMP to $ROOM  -- ★ this run's vmstate.txt is NOT a valid baseline"
    fi
else
    echo "cel dump : off (CEL_DUMP=1 to enable; that run's vmstate is not a baseline)"
    echo "sprite   : off (SPRITE_DUMP=1 to enable)"
fi

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

# ★★ CEL_DUMP=1 enables patch 0006's VIEW sweep, which decodes every view so the cel dump is a
# complete sample. IT CHANGES THE GAME -- measured at P5.1, Kingquest1's flag 20 completes one
# cycle earlier because the sweep tears down resource state patch 0004 established.
#
# So a cel-dump run is a SEPARATE run and its vmstate.txt IS NOT A VALID BASELINE. The oracle
# is what everything else is diffed against (CLAUDE.md §2O.1); an instrumentation switch that
# perturbs it must never be on for a run whose state anyone consumes.
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
# ★ P5.1: cels.txt/cels.bin join the list for exactly the reason the other two are here --
# Common::DumpFile renames on close, and a timeout-killed process never closes. Forgetting to
# add a new dump to this list does not error; it silently produces no artifact, which is how
# the first cel-dump run appeared to succeed while writing nothing.
for t in vmstate.txt row24.txt cels.txt cels.bin; do
    if [ -f "$t.tmp" ]; then mv "$t.tmp" "$t"; fi
done || true

echo
# ★★★★★ RENAME THE HELD-OPEN LOGS. Common::DumpFile writes to "<name>.tmp" and renames on close;
# a log held open for the process lifetime -- patch 0002's s_vmLog pattern, which patch 0009's
# said dump and P6.15's text log both follow -- is NEVER closed, because the run is killed on a
# wall-clock timeout. So the data is complete and correct and sits under a name nothing looks for.
# ★★★★ THAT IS WHY THE TEXT LOG READ AS "NOT PRODUCED" THROUGH FOUR REBUILDS. The file existed the
# whole time at 673,270 bytes; every check was for `text_events.txt` and every write went to
# `text_events.txt.tmp`. ★★★ It is also PRE-EXISTING: oracle_said.txt.tmp sits beside it and
# NOTHING IN THE HARNESS READS oracle_said.txt, so patch 0009's artifact has been in the same state
# since it was written.
# ★★ Renamed here rather than in the patches: the engine cannot know when the run ends, and the
# runner does.
for t in *.tmp; do
    [ -e "$t" ] || continue
    mv -f "$t" "${t%.tmp}"
    echo "renamed  : ${t%.tmp}  (Common::DumpFile leaves .tmp when the handle is never closed)"
done

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
