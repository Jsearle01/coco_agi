#!/usr/bin/env python3
"""harness/tools/window_cost.py -- price the two fill-windowing designs from measured counts.

★★★★★ THE METHOD, AND WHY IT IS NOT A GUESS. Each design's cost is
(how often the expensive thing happens) x (what it costs each time). The first factor is a
CONTENT property -- which rows the corpus's fills touch, and how often a span writes a second
plane -- and is measured by the -DPIC_STRADDLE census in pic_fill.s over the same 45 pictures the
renderer gate uses. The second is an ISA property and is arithmetic on 6809 cycle counts.

★★★★ So the uncertain half is measured and the certain half is computed, rather than both being
estimated. **The alternative -- building both designs and timing them -- costs two
implementations of the project's most tuned loop to answer a question the counts already
settle**, and P3.3's 11.102 -> 2.746 s lives in that loop.

★★★ WHAT IS ASSUMED AND WHAT IS MEASURED is marked per line below, because a cost model whose
inputs are indistinguishable is the shape L-73 warns about.

  DESIGN A  single-slice + fallback
     per span, always : compute the neighbourhood's slice and compare with the cached one
     per straddling span : a slower per-access path for the up/down reads
  DESIGN B  dual-slot 16 KB window ($A000-$DFFF contiguous)
     no straddle is possible -- the neighbourhood always fits
     per flush that writes a SECOND plane : slot 5 leaves priority and comes back

usage:  python harness/tools/window_cost.py --csv build/sweep_straddle/timing.csv
"""
import argparse
import csv
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

CLOCK = 1_789_390.0

# ── per-occurrence costs, 6809 cycles. ASSUMED (counted from the instruction sequences). ──
# A: y-1 and y+1 row products, two 5-shift chains, a compare, a branch. Two `mul` at 11 each
#    dominate. Hoisting the lo/hi slice per ROW rather than per span would cut this; costed per
#    span here because that is where the span's row is known.
A_PER_SPAN = 62
# A: the fallback replaces `lda ,u` (5) with a bounds test, a remap and a windowed load.
#    Charged per PIXEL of a straddling span, for the two neighbour reads.
A_PER_STRADDLE_PIXEL = 34
# B: sta $FFA6 (5) x2 plus reloading the two block numbers and the base. Charged per flush that
#    writes a second plane.
B_PER_SEC_FLUSH = 26
# B: the walk's pointers must be biased by which of the two slots holds the row. Per span.
B_PER_SPAN = 18


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="build/sweep_straddle/timing.csv")
    ap.add_argument("--baseline-total", type=float, default=125.2916,
                    help="flat -DPIC_NOCOUNT total render seconds, 45 pictures (T-P0-041)")
    a = ap.parse_args()

    rows = list(csv.DictReader((ROOT / a.csv).open()))
    if not rows:
        print("no rows"); return 1

    def s(k):
        return sum(int(r[k]) for r in rows if r.get(k))

    seeds, pixels = s("spans"), s("pixels")
    strspan, strpix, secflush = s("str_span"), s("str_pix"), s("sec_flush")
    # ★★★ THE DENOMINATOR IS FLUSHES, NOT SEEDS. The CSV's "spans" column is CNT_SPAN, which
    # counts seed points PUSHED; a run is flushed once per completed span and the two differ by
    # a large factor. Dividing by seeds would overstate both designs' per-occurrence frequency.
    flushes = s("flushes")
    print(f"MEASURED over {len(rows)} pictures (-DPIC_STRADDLE census):")
    print(f"  seeds pushed (CNT_SPAN)     {seeds:>10,}   <- NOT the multiplier")
    print(f"  runs flushed                {flushes:>10,}   <- the multiplier")
    print(f"  pixels                      {pixels:>10,}")
    print(f"  flushes on straddling rows  {strspan:>10,}  "
          f"({100.0*strspan/flushes if flushes else 0:.2f}% of flushes)")
    print(f"  pixels in those flushes     {strpix:>10,}  "
          f"({100.0*strpix/pixels if pixels else 0:.2f}% of pixels)")
    print(f"  flushes writing 2nd plane   {secflush:>10,}  "
          f"({100.0*secflush/flushes if flushes else 0:.2f}% of flushes)")
    # ★★ A sanity relation that must hold: a flush counted as straddling wrote >= 1 pixel, so
    # strspan <= strpix. The first census run violated it (18,978 vs 1,355) because the counters
    # were never zeroed -- reported here so the violation cannot pass silently a second time.
    if strspan > strpix:
        print(f"  ★★★ IMPOSSIBLE: {strspan:,} straddling flushes but only {strpix:,} pixels in "
              f"them -- counters are not being zeroed. Figures below are meaningless.")
    print()
    spans = flushes

    a_cy = spans * A_PER_SPAN + strpix * A_PER_STRADDLE_PIXEL
    b_cy = spans * B_PER_SPAN + secflush * B_PER_SEC_FLUSH
    base_cy = a.baseline_total * CLOCK

    print("COMPUTED (per-occurrence costs are ASSUMED; see the header):")
    for name, cy, detail in (
            ("A  single-slice + fallback", a_cy,
             f"{spans:,} x {A_PER_SPAN} + {strpix:,} x {A_PER_STRADDLE_PIXEL}"),
            ("B  dual-slot 16 KB window", b_cy,
             f"{spans:,} x {B_PER_SPAN} + {secflush:,} x {B_PER_SEC_FLUSH}")):
        print(f"  {name:<28} {cy:>12,.0f} cy  = {cy/CLOCK:>7.3f} s over 45 pictures"
              f"  = {100.0*cy/base_cy:>5.2f}% of the {a.baseline_total:.2f} s baseline")
        print(f"  {'':<28} {detail}")
    print()
    win = "A" if a_cy < b_cy else "B"
    print(f"★ cheaper by this model: {win}  (ratio {max(a_cy,b_cy)/min(a_cy,b_cy):.2f}x)")
    print("★★ The per-occurrence costs are the soft half. The counts are not, and if the two")
    print("   designs land within ~2x of each other the model does not settle it -- build both.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
