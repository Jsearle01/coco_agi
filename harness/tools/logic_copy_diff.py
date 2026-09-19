#!/usr/bin/env python3
"""Diff the PORT's resident copy of a LOGIC (snapshotted into p3b's run log) against the game file.

★★★★★ WHY IT IS A SCRIPT AND NOT AN EYE [T-P0-101 §4D, L-45]. The first pass over these two hex
dumps was done by reading them side by side and it found seven differing offsets. A script found
the same seven and is the thing that can be re-run when the snapshot widens -- which it already
did once, from 64 bytes to 256.

★★★ IT PRINTS THE XOR of each differing pair as well as the values, because the first hypothesis
for a damaged AGI resource is always the "Avis Durgan" message XOR and the cheapest way to kill it
is to look at the deltas [2P: the key is the interpreter's, the data is the user's].

Usage:
    python harness/tools/logic_copy_diff.py <run.log> <game-dir> <logic-nr>
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import logic as logic_mod, resource    # noqa: E402

KEY = b"Avis Durgan"
ROW = re.compile(r"^\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2} ){15}[0-9A-F]{2})\s*$")


def parse_snapshot(log_path):
    """Read the hex rows that follow the 'copy at' line."""
    out = {}
    seen_header = False
    for line in pathlib.Path(log_path).read_text(encoding="utf-8", errors="replace").splitlines():
        if "copy at" in line:
            seen_header = True
            continue
        if not seen_header:
            continue
        m = ROW.match(line)
        if not m:
            if out:
                break
            continue
        base = int(m.group(1), 16)
        for i, b in enumerate(m.group(2).split()):
            out[base + i] = int(b, 16)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_log")
    ap.add_argument("game_dir")
    ap.add_argument("logic_nr", type=int)
    args = ap.parse_args()

    snap = parse_snapshot(args.run_log)
    if not snap:
        print("no snapshot rows found in", args.run_log)
        return 1

    game = resource.load_from_files(args.game_dir)
    lg = logic_mod.split(game.load("LOGIC", args.logic_nr), index=args.logic_nr)
    code = lg.bytecode

    print("logic %d: file %d bytes, snapshot %d bytes"
          % (args.logic_nr, len(code), len(snap)))
    diffs = [(o, code[o], snap[o]) for o in sorted(snap) if o < len(code) and code[o] != snap[o]]
    print("differing offsets: %d of %d compared" % (len(diffs), len(snap)))
    print()
    print("  offset  file  port   xor   key[off%%11]  file^key")
    for off, f, p in diffs:
        k = KEY[off % len(KEY)]
        print("  $%04X    %02X    %02X    %02X      %02X ('%s')   %02X"
              % (off, f, p, f ^ p, k, chr(k), f ^ k))
    print()
    if diffs:
        gaps = [b[0] - a[0] for a, b in zip(diffs, diffs[1:])]
        print("  gaps between differing offsets:", gaps)
    return 0


if __name__ == "__main__":
    sys.exit(main())
