#!/usr/bin/env python3
"""harness/tools/comp_cost.py -- AC-5/AC-6: the composite's cost, fitted and reported.

★★ FITTED, NOT DIVIDED. Dividing total cycles by total pixels gives one number that hides which
of the three mechanisms is paying: the transparency test runs on EVERY source pixel, the write
runs only on survivors, and the control branch runs a column scan. A least-squares fit against
(tested, written, ctrl_steps) separates them and -- with many more observations than parameters
-- can be CONTRADICTED, which a single ratio never can.

★★★ AND THE HARNESS IS SUBTRACTED, NOT IGNORED [L-56]. The per-call intercept is the free-run
loop plus cp_composite's prologue; it is reported separately so the per-pixel figures are the
composite's own.

★ CLOCK: stated, and measured by SLOPE rather than from a single block -- see the note in
cel_probe.s. Two figures are on record for this machine and the lower one is scaffolding.
"""
import argparse
import csv
import pathlib
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CLOCK = 1_789_390.0     # ★ measured: 5-point slope fit, 0.021% from 14.31818/8 = 1,789,772


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csvs", nargs="+")
    ap.add_argument("--clock", type=float, default=CLOCK)
    ap.add_argument("--nocount", default=None,
                    help="cost.csv from a -DCOMP_NOCOUNT build; its SECONDS are used")
    a = ap.parse_args()

    def read(p):
        out = {}
        with open(p, newline="") as f:
            for r in csv.DictReader(f):
                rec = {k: (float(v) if k == "seconds" else
                           (v if k == "frame" else int(v))) for k, v in r.items()}
                out[(rec["frame"], rec["sprite"])] = rec
        return out

    counted = read(a.csvs[0])
    rows = list(counted.values())

    # ★★★ TIMING FROM THE NO-COUNT BUILD, COUNTS FROM THE COUNTED ONE, joined per (frame,
    # sprite). The counters are four `jsr co_inc32` calls per pixel at ~40 cycles each -- on
    # SpaceQuest-1 they were 51% of the measured time (12.95 s counted vs 6.39 s not). Reporting
    # the counted build's seconds would have made the composite look twice its cost and fired
    # the dispatch's own §8 trigger 2 on an artifact [L-56, and P3.3's -DPIC_NOCOUNT precedent].
    if a.nocount:
        nc = read(a.nocount)
        joined, missing = [], 0
        for k, rec in counted.items():
            if k in nc:
                rec = dict(rec)
                rec["counted_seconds"] = rec["seconds"]
                rec["seconds"] = nc[k]["seconds"]
                joined.append(rec)
            else:
                missing += 1
        rows = joined
        overhead = sum(r["counted_seconds"] for r in rows) / max(1e-9, sum(r["seconds"]
                                                                          for r in rows))
        print("★ timing from the NO-COUNT build; counts from the counted build.")
        print("  instrument overhead: the counted build took %.2fx as long (%d joined, %d "
              "unmatched)" % (overhead, len(rows), missing))
    if not rows:
        print("no samples")
        return 1

    print("samples: %d from %d file(s)" % (len(rows), len(a.csvs)))
    print("clock  : %.4f MHz  (measured by slope; the hardware constant is %.4f)"
          % (a.clock / 1e6, 14.31818e6 / 8 / 1e6))
    print()

    # cycles for the whole timed run of REPS composites
    cyc = np.array([r["seconds"] * a.clock for r in rows])
    tested = np.array([r["tested"] for r in rows], dtype=float)
    written = np.array([r["written"] for r in rows], dtype=float)
    steps = np.array([r["ctrlstep"] for r in rows], dtype=float)
    reps = np.array([r["reps"] for r in rows], dtype=float)

    cols, names = [tested, written], ["per source pixel TESTED", "per pixel WRITTEN"]
    if steps.any():
        cols.append(steps)
        names.append("per control-scan STEP")
    cols.append(reps)
    names.append("per composite CALL (harness + prologue)")
    A = np.vstack(cols).T
    sol, *_ = np.linalg.lstsq(A, cyc, rcond=None)
    pred = A @ sol
    resid = (pred - cyc) / cyc * 100.0

    print("least-squares fit, cycles =")
    for n, v in zip(names, sol):
        print("    %-42s %8.2f" % (n, v))
    print()
    print("residuals: min %+.1f%%  max %+.1f%%  mean |%.1f|%%"
          % (resid.min(), resid.max(), np.abs(resid).mean()))
    if steps.any() == 0:
        print("★ control-scan steps are ZERO in every sample -- that branch is UNMEASURED here,")
        print("  and its cost is not in the figures above.")
    print()

    # ── per-composite and per-frame figures ────────────────────────────────────────────
    per_call = cyc / reps
    tested_pc = tested / reps
    print("per composite (one sprite drawn once):")
    print("    source pixels tested   min %6.0f  median %6.0f  max %6.0f"
          % (tested_pc.min(), np.median(tested_pc), tested_pc.max()))
    print("    cycles                 min %6.0f  median %6.0f  max %6.0f"
          % (per_call.min(), np.median(per_call), per_call.max()))
    print("    ms at %.4f MHz       min %6.3f  median %6.3f  max %6.3f"
          % (a.clock / 1e6, per_call.min() / a.clock * 1e3,
             np.median(per_call) / a.clock * 1e3, per_call.max() / a.clock * 1e3))
    print()

    med = float(np.median(per_call))
    print("AC-6 -- the standing tax, against the ~5 cycles/second AGI runs at:")
    print("    %-10s %12s %12s %12s" % ("sprites", "cycles", "ms/frame", "% of a second"))
    for n in (2, 4, 6):
        c = med * n
        ms = c / a.clock * 1e3
        # ★ 5 interpreter cycles per second is the dispatch's figure for AGI's pace.
        pct = ms * 5 / 1000.0 * 100.0
        print("    %-10d %12.0f %12.2f %12.1f%%" % (n, c, ms, pct))
    print()
    print("★ 'per cent of a second' = cost of compositing N sprites, five times a second.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
