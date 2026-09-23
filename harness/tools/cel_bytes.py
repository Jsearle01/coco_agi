#!/usr/bin/env python3
"""How many bytes does ONE cel's compressed data occupy, across the pinned corpus?

★★★★★ T-P0-136 §4A ASKS THREE THINGS AND THIS ANSWERS THE SIZE ONE. The compositor copies a
sprite's WHOLE VIEW into the arena -- every loop, every cel -- to decode the one cel it is about
to draw. The copy is what starves the LOGIC cache [T-P0-133]. Whether the fix can be "copy the
CEL instead" rather than "read the VIEW in place" turns entirely on how big a single cel is and
whether that size has a BOUND or only a corpus maximum.

★★★★ THE DISTINCTION IS L-85's AND IT IS LOAD-BEARING HERE. A corpus maximum is a fact about the
games measured; a format bound is a fact about AGI. VC_ROW_MAX is a bound -- "a cel width is a
BYTE; this cannot be exceeded" [view_cel.s] -- and that is why it is trusted. A cel's COMPRESSED
length has no such field: it is implied by where the next cel starts, so the only honest answer is
a measured maximum plus an explicit refusal path for anything larger.

Cel data layout [view.cpp at the pin, and view_cel.s's own header]:
    VIEW payload: u8 unknown, u8 unknown, u8 numLoops, u16 descOfs, then numLoops u16 loop offsets
    loop:         u8 numCels, then numCels u16 cel offsets (relative to the LOOP's offset)
    cel:          u8 width, u8 height, u8 transparency/mirror, then RLE chunks, row-terminated

★★★ A CEL'S LENGTH IS NOT STORED. It runs to the next cel's offset, or -- for the last cel of the
last loop -- to the end of the resource. Both are derivable here and neither is a field, which is
itself the reason a bounded scratch needs a refusal path rather than an assertion.

Usage:
    python harness/tools/cel_bytes.py [titles ...] [--games DIR] [--top N]
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import resource   # noqa: E402

PINNED = ["Kingquest1", "Kingquest2", "Kingquest3",
          "PoliceQuest1", "SpaceQuest-1", "larry1"]


def le16(b, i):
    return b[i] | (b[i + 1] << 8)


def cel_spans(payload):
    """-> [(loop, cel, start, length)] for every cel in this VIEW, by construction."""
    if len(payload) < 5:
        return []
    nloops = payload[2]
    starts = []
    for lp in range(nloops):
        off = 5 + lp * 2
        if off + 1 >= len(payload):
            continue
        lo = le16(payload, off)
        if lo >= len(payload):
            continue
        ncels = payload[lo]
        for c in range(ncels):
            co = lo + 1 + c * 2
            if co + 1 >= len(payload):
                continue
            starts.append((lp, c, lo + le16(payload, co)))
    # ★★★ The length is the distance to the NEXT cel start anywhere in the resource, not to the
    # next cel in THIS loop: loops share cels and the offsets are not monotonic per loop.
    edges = sorted({s for _, _, s in starts} | {len(payload)})
    out = []
    for lp, c, s in starts:
        nxt = next((e for e in edges if e > s), len(payload))
        out.append((lp, c, s, nxt - s))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("titles", nargs="*", default=None)
    ap.add_argument("--games", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--top", type=int, default=8)
    # ★★★★ --view NR: every cel span in ONE view, with a marker on the ones that cross an 8 KB
    # boundary. T-P0-136 AC-4 needs a cel whose STREAM straddles, and view_straddle.py --construct
    # reports the boundary's payload offset without saying which cel owns it.
    ap.add_argument("--view", type=int, default=None)
    ap.add_argument("--boundary", type=int, default=None,
                    help="payload offset of the block boundary, from view_straddle --construct")
    a = ap.parse_args()

    if a.view is not None:
        for t in (a.titles or PINNED):
            d = pathlib.Path(a.games) / t
            if not d.is_dir():
                continue
            g = resource.load_from_files(d)
            try:
                payload = g.load(resource.VIEW, a.view)
            except Exception:
                continue
            print(f"{t} view {a.view}: payload {len(payload)} B")
            for lp, c, s, ln in sorted(cel_spans(payload)):
                mark = ""
                if a.boundary is not None and s <= a.boundary < s + ln:
                    mark = "   ★★★ CROSSES the boundary"
                print(f"    loop {lp} cel {c}: +{s} .. +{s + ln} ({ln} B){mark}")
        return

    titles = a.titles or PINNED
    games = pathlib.Path(a.games)
    allcels = []
    print(f"{'title':<14} {'views':>6} {'cels':>7} {'max cel B':>10} {'max VIEW B':>11}")
    print("-" * 54)
    for t in titles:
        d = games / t
        if not d.is_dir():
            print(f"{t:<14} -- not found")
            continue
        ncel = 0
        mx = 0
        mxview = 0
        g = resource.load_from_files(d)
        for e in g.iter_present(resource.VIEW):
            try:
                payload = g.load(resource.VIEW, e.index)
            except Exception:
                continue
            if not payload:
                continue
            mxview = max(mxview, len(payload))
            for lp, c, s, ln in cel_spans(payload):
                ncel += 1
                mx = max(mx, ln)
                allcels.append((ln, t, e.index, lp, c, len(payload)))
        nviews = len({x[2] for x in allcels if x[1] == t})
        print(f"{t:<14} {nviews:>6} {ncel:>7} {mx:>10} {mxview:>11}")

    allcels.sort(reverse=True)
    print()
    print(f"★ the {a.top} largest cels in the corpus:")
    for ln, t, idx, lp, c, vl in allcels[:a.top]:
        print(f"    {ln:>6} B   {t} view {idx} loop {lp} cel {c}   (VIEW is {vl} B)")
    if allcels:
        mx = allcels[0][0]
        mxview = max(x[5] for x in allcels)
        print()
        print(f"★★★ corpus maximum CEL  {mx} B")
        print(f"★★★ corpus maximum VIEW {mxview} B")
        print(f"★★★ ratio: one cel is {100.0 * mx / mxview:.1f}% of the largest VIEW")


if __name__ == "__main__":
    main()
