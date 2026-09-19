#!/usr/bin/env python3
"""How far does a decoded cel reach from CP_CEL, and does it reach RES_ARENA? [T-P0-103 AC-4]

★★★★★ THE QUESTION. In `p3b`'s cel configuration the decoded-cel staging buffer is
`CP_CEL equ MAP_RESERVED` = $5300, and the arena window begins at $6000 -- so the buffer has
**3,328 bytes before it runs into the arena**, and its declared corpus maximum is 4,784. The
overlap is arithmetic; whether it BITES depends on how big the decoded cels actually are.

★★★★★ AND IT IS NOT HYPOTHETICAL AT THE OTHER END. p3_composite_all fetches the VIEW **from the
arena**, in the same phase, and `res_top` starts at RES_ARENA -- so the first transient on the
arena stack lands at $6000 exactly. A cel wider than the margin therefore overwrites **the VIEW it
is decoding from**, not merely some unrelated resident resource.

★★★ Offline, from the game files, because the guest instrument that would measure it does not fit
in that arm: the cel configuration's region A ends at $52F8 with CP_CEL at $5300, which is EIGHT
free bytes [res_check.s].

Usage:
    python harness/tools/cel_extent.py <game-dir> [<game-dir> ...]
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import resource  # noqa: E402

CP_CEL = 0x5300
RES_ARENA = 0x6000
MARGIN = RES_ARENA - CP_CEL             # 3,328


def cel_sizes(game):
    """Yield (view_nr, loop, cel, width*height) for every cel in the game.

    ★★ A decoded cel is width x height BYTES, one per pixel -- the shape the probes deliberately
    use ("the SAME shape as the oracle's. No transform, no place for a transform error to hide").
    So the decoded extent is the product, and no decompression has to be modelled to get it.
    """
    dirs = game.dirs["VIEW"] if hasattr(game, "dirs") else None
    count = len(dirs) if dirs else 256
    for nr in range(count):
        try:
            raw = game.load("VIEW", nr)
        except Exception:
            continue
        if not raw or len(raw) < 3:
            continue
        nloops = raw[2]
        for lp in range(nloops):
            off = 5 + lp * 2
            if off + 1 >= len(raw):
                break
            lo = raw[off] | (raw[off + 1] << 8)
            if lo + 1 >= len(raw):
                continue
            ncels = raw[lo]
            for ce in range(ncels):
                co = lo + 1 + ce * 2
                if co + 1 >= len(raw):
                    break
                cel = lo + (raw[co] | (raw[co + 1] << 8))
                if cel + 1 >= len(raw):
                    continue
                yield nr, lp, ce, raw[cel] * raw[cel + 1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("games", nargs="+")
    args = ap.parse_args()

    print("CP_CEL $%04X, RES_ARENA $%04X -- margin %d bytes before a decoded cel reaches the arena"
          % (CP_CEL, RES_ARENA, MARGIN))
    print()
    worst = 0
    worst_who = None
    for g in args.games:
        game = resource.load_from_files(g)
        biggest, who, over = 0, None, 0
        for nr, lp, ce, size in cel_sizes(game):
            if size > biggest:
                biggest, who = size, (nr, lp, ce)
            if size > MARGIN:
                over += 1
        name = pathlib.Path(g).name
        flag = "★★★ REACHES THE ARENA" if biggest > MARGIN else "does not reach"
        print("  %-16s largest cel %6d B  (view %s)  cels over the margin: %-4d  %s"
              % (name, biggest, who, over, flag))
        if biggest > worst:
            worst, worst_who = biggest, (name, who)
    print()
    print("  worst across the set: %d bytes (%s) -- %+d against the margin"
          % (worst, worst_who, worst - MARGIN))
    return 0


if __name__ == "__main__":
    sys.exit(main())
