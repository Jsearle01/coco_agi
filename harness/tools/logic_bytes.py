#!/usr/bin/env python3
"""Hex-dump a window of one LOGIC's bytecode, beside agidis.py's decode of the same range.

★★★★★ WHY THE BYTES AND NOT ONLY THE DISASSEMBLY [T-P0-101]. agidis.py decodes with the VM's own
table, which is deliberate -- a disassembly that desynchronises is evidence the VM would too. But
that shared table is exactly what makes it useless for the question "did the port read the operand
correctly": both sides would read it the same way, and neither would show the raw byte.

★★★★ The measurement this exists for is a `goto` whose 16-bit little-endian offset the port and the
reference appear to resolve differently. **The offset bytes themselves are the only thing that
settles it**, and no tool in the tree printed them.

Usage:
    python harness/tools/logic_bytes.py <game-dir> <logic-nr> [--from 0] [--len 64]
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "harness" / "tools"))

from agivm import optable                          # noqa: E402
from volread import logic as logic_mod, resource    # noqa: E402
import agidis                                       # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("logic_nr", type=int)
    ap.add_argument("--from", dest="start", type=lambda s: int(s, 0), default=0)
    ap.add_argument("--len", dest="length", type=lambda s: int(s, 0), default=64)
    args = ap.parse_args()

    game = resource.load_from_files(args.game_dir)
    lg = logic_mod.split(game.load("LOGIC", args.logic_nr), index=args.logic_nr)
    code = lg.bytecode
    print("logic %d: %d bytes of bytecode, %d messages"
          % (args.logic_nr, len(code), len(lg.messages)))
    print()

    end = min(len(code), args.start + args.length)
    for base in range(args.start & ~0xF, end, 16):
        row = code[base:base + 16]
        hexs = " ".join("%02X" % b for b in row)
        print("  %04X  %-47s" % (base, hexs))
    print()
    for addr, kind, text, _ in agidis.disassemble(code):
        if addr < args.start:
            continue
        if addr >= end:
            break
        print("  %04X  %s" % (addr, text))


if __name__ == "__main__":
    main()
