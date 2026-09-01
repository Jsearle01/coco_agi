#!/usr/bin/env python3
"""harness/tools/pic_counters.py -- the renderer gate's counters and render-time distribution.

★★★★ WHY SAVED [L-45]: AC-6 asks whether three counters are unchanged TO THE UNIT -- boundary
tests 3,666,862, pixels 1,188,430, seed peak 74 B -- and AC-5 compares a render median against
2.832 s. Those are four numbers summed out of a 45-row CSV, and an inline one-liner that produces
them cannot be audited or re-run. T-P0-015's withdrawn "88% disk" figure came from exactly that.

★★ The seed peak is a MAX, not a sum -- it is the high-water mark of the fill's seed stack across
the corpus, and summing it would produce a number that looks plausible and means nothing.

usage:  python harness/tools/pic_counters.py [--csv build/sweep/timing.csv]
"""
import argparse
import csv
import io
import pathlib
import statistics
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="build/sweep/timing.csv")
    a = ap.parse_args()

    rows = list(csv.DictReader((ROOT / a.csv).open()))
    if not rows:
        print("no rows")
        return 1

    def isum(k):
        return sum(int(r[k]) for r in rows)

    checks = isum("checks")
    pixels = isum("pixels")
    peak = max(int(r["sp_peak_bytes"]) for r in rows)
    fills = isum("fills")
    spans = isum("spans")
    times = sorted(float(r["render_s"]) for r in rows)
    bad = [r["name"] for r in rows if int(r["bad_op"]) != 0]

    print(f"pictures            {len(rows)}")
    print(f"boundary tests      {checks:,}")
    print(f"pixels              {pixels:,}")
    print(f"seed peak (MAX)     {peak} B")
    print(f"fills / spans       {fills:,} / {spans:,}")
    print(f"bad_op != 0         {bad if bad else 'none'}")
    print()
    print(f"render_s  median    {statistics.median(times):.4f} s")
    print(f"          mean      {statistics.mean(times):.4f} s")
    print(f"          min/max   {times[0]:.4f} / {times[-1]:.4f} s")
    print(f"          total     {sum(times):.4f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
