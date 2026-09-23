#!/usr/bin/env python3
"""Count a PICTURE's drawing primitives, so a render cost has a denominator. [T-P0-139 §4B]

★★★★★ WHY. T-P0-138 measured the castle's render at 4.8957 s and T-P0-139 decomposed it: the
FILL subsystem is 63.6% of it. A total is not a cost model -- "3.11 s of fill" says nothing about
whether the fill is slow or whether the picture simply contains a great many of them, and those
two lead to different tasks.

★★★★ AND IT ANSWERS THE OTHER HALF: is the castle TYPICAL? The renderer gate runs 45 pictures and
reports 45/45; if the room this project has profiled for six tasks is an outlier, a fix aimed at
it would not generalise [L-85's shape -- a fixed sample that always passes is evidence about the
sample first].

Opcodes [pic_core.s pr_table, and view.cpp at the pin]:
    F0 set_visual   F1 dis_visual   F2 set_pri      F3 dis_pri
    F4 y_corner     F5 x_corner     F6 abs_line     F7 rel_line
    F8 fill         F9 set_pattern  FA pattern_brush        FF end

★★★ A "primitive" here is an OPCODE OCCURRENCE, not a pixel: one F8 may seed many spans and one
F6 may draw many segments. That distinction is why the fill count and the fill's SEED count are
reported separately -- the second is the one that scales with work [pic_probe's CNT_SPAN note].

§2P: game files are opened read-only; prints counts only.

Usage:
    python harness/tools/pic_census.py [titles ...] [--pic N] [--games DIR] [--top N]
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import resource   # noqa: E402

PINNED = ["Kingquest1", "Kingquest2", "Kingquest3"]
NAMES = {0xF0: "set_visual", 0xF1: "dis_visual", 0xF2: "set_pri", 0xF3: "dis_pri",
         0xF4: "y_corner", 0xF5: "x_corner", 0xF6: "abs_line", 0xF7: "rel_line",
         0xF8: "fill", 0xF9: "set_pattern", 0xFA: "pattern_brush"}


def census(data):
    """-> (counts by opcode, fill SEEDS, line POINTS, bytes consumed)."""
    n = {k: 0 for k in NAMES}
    seeds = 0
    pts = 0
    i = 0
    L = len(data)
    while i < L:
        op = data[i]
        i += 1
        if op == 0xFF:
            break
        if op not in NAMES:
            continue                      # a parameter where an opcode was expected
        n[op] += 1
        if op in (0xF0, 0xF2):            # one colour argument
            i += 1
        elif op in (0xF1, 0xF3, 0xF9, 0xFA):
            pass
        elif op == 0xF8:                  # fill: (x,y) pairs until the next opcode
            while i + 1 < L and data[i] < 0xF0:
                seeds += 1
                i += 2
        elif op == 0xF6:                  # abs_line: (x,y) pairs
            while i + 1 < L and data[i] < 0xF0:
                pts += 1
                i += 2
        elif op == 0xF7:                  # rel_line: x,y then packed nibble deltas
            if i + 1 < L:
                i += 2
                pts += 1
            while i < L and data[i] < 0xF0:
                pts += 1
                i += 1
        elif op in (0xF4, 0xF5):          # corner: x,y then alternating single coords
            if i + 1 < L:
                i += 2
                pts += 1
            while i < L and data[i] < 0xF0:
                pts += 1
                i += 1
    return n, seeds, pts, i


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("titles", nargs="*", default=None)
    ap.add_argument("--games", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--pic", type=int, default=None, help="census this picture only")
    ap.add_argument("--top", type=int, default=6)
    a = ap.parse_args()

    rows = []
    for t in (a.titles or PINNED):
        d = pathlib.Path(a.games) / t
        if not d.is_dir():
            continue
        g = resource.load_from_files(d)
        for e in g.iter_present(resource.PICTURE):
            if a.pic is not None and e.index != a.pic:
                continue
            try:
                data = g.load(resource.PICTURE, e.index)
            except Exception:
                continue
            n, seeds, pts, used = census(data)
            rows.append((t, e.index, len(data), n, seeds, pts))

    if a.pic is not None:
        for t, idx, ln, n, seeds, pts in rows:
            print(f"{t} picture {idx}: {ln} payload bytes")
            for op in sorted(NAMES):
                if n[op]:
                    print(f"    {NAMES[op]:<14} {n[op]:>5}")
            print(f"    ★ fill SEEDS   {seeds:>5}      line POINTS {pts:>5}")
        return 0

    print(f"{'title':<12} {'pics':>5} {'median fills':>13} {'median seeds':>13} "
          f"{'max fills':>10} {'max seeds':>10}")
    print("-" * 68)
    allf, alls = [], []
    for t in (a.titles or PINNED):
        sel = [r for r in rows if r[0] == t]
        if not sel:
            continue
        f = sorted(r[3][0xF8] for r in sel)
        s = sorted(r[4] for r in sel)
        allf += f
        alls += s
        print(f"{t:<12} {len(sel):>5} {f[len(f)//2]:>13} {s[len(s)//2]:>13} "
              f"{f[-1]:>10} {s[-1]:>10}")
    if allf:
        allf.sort(); alls.sort()
        print()
        print(f"★ corpus: {len(allf)} pictures  median fills {allf[len(allf)//2]}  "
              f"median seeds {alls[len(alls)//2]}  max fills {allf[-1]}  max seeds {alls[-1]}")
        # ★ where does a named picture sit in that distribution?
        for t, idx, ln, n, seeds, pts in rows:
            if t == "Kingquest1" and idx == 1:
                rf = sum(1 for x in allf if x < n[0xF8])
                rs = sum(1 for x in alls if x < seeds)
                print(f"★★ Kingquest1 picture 1 (the castle): {n[0xF8]} fills "
                      f"({100*rf/len(allf):.0f}th percentile), {seeds} seeds "
                      f"({100*rs/len(alls):.0f}th percentile), {ln} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
