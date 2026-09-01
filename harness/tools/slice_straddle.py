#!/usr/bin/env python3
"""harness/tools/slice_straddle.py -- how often does a plane walk cross a slice boundary?

★★★★ THE QUESTION THE DESIGN TURNS ON. Dispatch §3 offers per-pixel, per-span and per-row as
shapes for the boundary check. Which is right is not a preference -- it follows from how often a
boundary actually falls inside the working set of each loop, and that is arithmetic.

★★★★★ AND THERE IS A CONSTRAINT §3 DOES NOT NAME. pic_fill.s's inner loop holds THREE
SIMULTANEOUS row pointers -- X = current row, U = row above, Y = row below -- advanced together
with three LEAs per pixel. That is what P3.3 bought when it took the fill from 11.102 s to
2.746 s. **One 8 KB window cannot serve three pointers when a slice boundary falls between
them**, because only one slice is mapped at a time. So the fill's question is not "does this
pixel cross a boundary" but "does this ROW's three-row neighbourhood contain one".

★★★ The compositor has the same shape at co_checkctrl, which walks DOWN by +160 until it finds a
priority > 2 -- an unbounded descent that can cross any number of boundaries.

usage:  python harness/tools/slice_straddle.py
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

SLICE = 8192
W, H = 160, 168


def rows_containing_boundary(stride, height, size):
    """Rows whose [r*stride, r*stride+stride) span contains a slice boundary."""
    out = []
    b = SLICE
    while b < size:
        r = b // stride
        if r < height:
            out.append((r, b, b - r * stride))
        b += SLICE
    return out


def report(name, stride, height):
    size = stride * height
    slices = -(-size // SLICE)
    bounds = rows_containing_boundary(stride, height, size)
    print(f"── {name}: {size:,} B, stride {stride}, {height} rows, "
          f"{slices} slices of {SLICE:,} ──")
    print(f"   rows containing a boundary: {len(bounds)} of {height} "
          f"({100.0*len(bounds)/height:.1f}%)")
    for r, b, within in bounds:
        print(f"     row {r:>3}  boundary at flat {b:>6}  = {within} bytes into the row")

    # ★★ The three-pointer neighbourhood: a fill at row y touches rows y-1, y, y+1.
    hot = set()
    for r, _, _ in bounds:
        for y in (r - 1, r, r + 1):
            if 0 <= y < height:
                hot.add(y)
    print(f"   ★★ rows whose 3-row neighbourhood (y-1,y,y+1) straddles: {len(hot)} of {height} "
          f"({100.0*len(hot)/height:.1f}%)  -> {sorted(hot)}")

    # ★ Per-span: a run is at most 255 bytes (ff_runn is a byte), so it crosses at most one
    # boundary and the split is always into exactly two flat runs.
    print(f"   ★ a 255-byte run crosses at most {255 // SLICE + 1} boundary "
          f"-> per-span split is always 2 runs, inner loop untouched")
    print()
    return len(hot), height


def main():
    print("★★★ SLICE STRADDLE CENSUS -- 8,192-byte window\n")
    hv, nv = report("visual  (1 B/px)", W, H)
    hp, np_ = report("priority (4 bpp, packed)", W // 2, H)

    print("★★★★ WHAT THIS DECIDES")
    print(f"  ff_store (fill runs)   PER SPAN.  A run is <=255 B and a slice is 8,192, so it")
    print(f"                         crosses at most one boundary: store, remap, store the rest.")
    print(f"                         **The 11-cycle inner loop never sees a test.**")
    print(f"  fill row walk          PER ROW.  Only {hv} of {nv} visual rows have a straddling")
    print(f"                         3-row neighbourhood ({100.0*hv/nv:.1f}%), so {nv-hv} rows keep")
    print(f"                         P3.3's three-pointer walk EXACTLY as it is.")
    print(f"  co_rowset              PER ROW, already -- it computes a row base once per row.")
    print(f"  put_pixel              PER PIXEL with a cached slice. Random access; nothing to")
    print(f"                         hoist. Compare-and-branch in the common case.")
    print()
    print("★★ The per-row figure is the load-bearing one: it is why windowing the fill does not")
    print("   cost what a per-pixel test would. A per-pixel check in ff_store's walk would add a")
    print("   test to every one of the ~1.19 M pixels the gate counts; the per-row split adds one")
    print(f"   test per row (168) and a slow path on {hv}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
