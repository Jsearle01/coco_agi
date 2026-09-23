#!/usr/bin/env python3
"""Per-cycle wall-time distribution from a p3b run log's [cyc] lines. [T-P0-137 §4A]

★★★★★ WHY THIS EXISTS. Every s/cycle figure this project has published is a MEAN over the whole
run, and a p3b run's window contains two cycles that are not steady-state work at all: the boot
cycle and the room render. Measured at T-P0-137: **c1 7.66 s and c9 9.55 s, two cycles of forty
holding 62.6% of the run's cycle time**, against a median of 0.300.

★★★★ So "0.679 s/cycle" was a true mean of a window whose shape nobody had looked at -- not a
wrong number, but an answer to a question nobody was asking. The steady castle cycle is the
number Jay is judging, and it needs the window stated.

★★★ --from N excludes everything before cycle N, which is how a steady window is declared
explicitly rather than by hoping the average washes it out.

Usage:
    python harness/tools/cyc_dist.py <run.log> [--from N] [--to N] [--bins N]
"""
import argparse
import pathlib
import re
import sys

ROW = re.compile(r"^\s*\[cyc\]\s+(\d+)\s+([0-9.]+)\s*$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--from", dest="lo", type=int, default=1)
    ap.add_argument("--to", dest="hi", type=int, default=10**9)
    ap.add_argument("--bins", type=int, default=10)
    a = ap.parse_args()

    rows = []
    for line in pathlib.Path(a.log).read_text(encoding="utf-8", errors="replace").splitlines():
        m = ROW.match(line)
        if m:
            rows.append((int(m.group(1)), float(m.group(2))))
    if not rows:
        print(f"no [cyc] rows in {a.log} -- run with P3B_CYCDIST=1")
        return 1

    sel = [(n, t) for n, t in rows if a.lo <= n <= a.hi]
    if not sel:
        print("no cycles in range")
        return 1
    ts = sorted(t for _, t in sel)
    tot = sum(ts)
    n = len(ts)

    def q(f):
        i = min(int(n * f), n - 1)
        return ts[i]

    med = q(0.5)
    print(f"{a.log}   cycles {a.lo}..{min(a.hi, rows[-1][0])}   n={n}")
    print(f"  sum {tot:.4f} s    mean {tot/n:.4f}    median {med:.4f}")
    print(f"  min {ts[0]:.4f}  p25 {q(0.25):.4f}  p75 {q(0.75):.4f}  "
          f"p90 {q(0.90):.4f}  max {ts[-1]:.4f}")
    big = [(x, y) for x, y in sel if y > 2 * med]
    sb = sum(y for _, y in big)
    print(f"  above 2x median ({2*med:.4f}): {len(big)} of {n}, "
          f"holding {sb:.4f} s ({100*sb/tot:.1f}%)")
    if big:
        print("    " + "  ".join(f"c{x}:{y:.3f}" for x, y in sorted(big, key=lambda r: -r[1])[:12]))
    # ★ a coarse histogram, so the SHAPE is visible and not only the quantiles
    lo, hi = ts[0], ts[-1]
    if hi > lo:
        w = (hi - lo) / a.bins
        print(f"  histogram ({a.bins} bins of {w:.4f} s):")
        for b in range(a.bins):
            b0, b1 = lo + b * w, lo + (b + 1) * w
            c = sum(1 for t in ts if (t >= b0 and (t < b1 or b == a.bins - 1)))
            if c:
                print(f"    {b0:7.4f}..{b1:7.4f}  {c:4d}  {'#' * min(60, c)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
