#!/usr/bin/env python3
"""sierra_writes.py -- IS A ROOM CHANGE A RENDER OR A COPY? [T-P0-150 SS4A]

THE TEST IS T-P0-015's, WRITTEN DOWN IN sierra_live.lua's BANNER 61 TASKS AGO AND NEVER RUN:

    "So: count writes across the WHOLE map, bucketed by 4 KB.  A COPY shows ~27 K writes in a
     tight burst concentrated in one or two blocks.  An opcode-driven RENDER shows far more
     writes, spread over many more frames."

The census it asked for was BUILT -- sierra_live.lua's frames.csv carries `total` plus sixteen
4 KB buckets b0..bF -- and two recordings already contain it.  This file is the analysis half.

WHAT DECIDES IT, stated before any number is quoted:
  * A COPY of a 160x168 visual plane is ~26,880 byte writes, plus ~13,440 for a priority plane.
    It is bounded, concentrated in the one or two 4 KB buckets that hold the destination, and
    fast -- a 6809 block move is a handful of cycles per byte.
  * A RENDER walks picture opcodes and flood-fills.  It writes MORE than the pixel count (fills
    revisit), spreads over many frames, and touches the interpreter's own working storage as
    well as the destination.
  * ** THE DISCRIMINATOR THAT NEEDS NO THRESHOLD: a first visit versus a RE-ENTRY to the same
    room.  If re-entry is dramatically cheaper, something was kept. **  Absolute write counts
    need a model; a ratio does not.

SS2W -- WHAT THIS INSTRUMENT CANNOT DO, AND THE REPORT MUST SAY SO:
  * The buckets are 4 KB of a 64 KB CPU-visible map.  The CoCo3 pages 512 KB through eight 8 KB
    slots, so two different physical blocks visible at different times land in the SAME bucket.
    ** A bucket is an APERTURE, not a destination. **
  * Writes are counted, not attributed.  This says how many and where in the map, never what.
  * It cannot see a copy performed by hardware, or one that never crosses the CPU bus.

SS2P: reads a recording of a machine running.  No game file is opened, nothing is written into
the emulated machine, and NO INSTRUCTION OF THE OBSERVED PROGRAM IS READ OR INTERPRETED -- this
counts bus activity, which is watching a machine, not reading a program [T-P0-150 SS6].
"""
import argparse
import csv
import sys

BUCKETS = ["b0", "b1", "b2", "b3", "b4", "b5", "b6", "b7",
           "b8", "b9", "bA", "bB", "bC", "bD", "bE", "bF"]


def load(path):
    out = []
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            out.append({
                "frame": int(r["frame"]), "t": float(r["time_s"]),
                "fdc": int(r["fdc"]), "total": int(r["total"]),
                "changed": int(r["changed"]),
                "b": [int(r[k]) for k in BUCKETS],
            })
    return out


def profile(rows, lo, hi, label):
    win = [r for r in rows if lo <= r["frame"] < hi]
    if not win:
        print("%-34s -- no frames" % label)
        return None
    tot = sum(r["total"] for r in win)
    fdc = sum(r["fdc"] for r in win)
    secs = len(win) / 60.0
    bsum = [sum(r["b"][i] for r in win) for i in range(16)]
    order = sorted(range(16), key=lambda i: -bsum[i])
    top = order[:3]
    conc = 100.0 * sum(bsum[i] for i in top[:2]) / tot if tot else 0
    print("%-34s %5.2f s %4d fr  writes %9d  fdc %7d  top buckets %s  top2 %.0f%%"
          % (label, secs, len(win), tot, fdc,
             " ".join("%s:%d" % (BUCKETS[i], bsum[i]) for i in top), conc))
    return {"writes": tot, "fdc": fdc, "frames": len(win), "secs": secs, "b": bsum}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--at", action="append", default=[], metavar="LO:HI:LABEL",
                    help="frame window to profile; repeatable")
    ap.add_argument("--bursts", type=int, default=0, metavar="N",
                    help="find the N heaviest write bursts automatically")
    ap.add_argument("--burst-frames", type=int, default=30,
                    help="window width in frames for --bursts (default 30 = 0.5 s)")
    a = ap.parse_args()

    rows = load(a.csv)
    print("%s: %d frames, %.2f..%.2f s, %d writes total"
          % (a.csv, len(rows), rows[0]["t"], rows[-1]["t"], sum(r["total"] for r in rows)))

    for spec in a.at:
        p = spec.split(":")
        profile(rows, int(p[0]), int(p[1]), p[2] if len(p) > 2 else spec)

    if a.bursts:
        # ★ Sliding window over `burst_frames`, non-overlapping picks, heaviest first. A room
        # render and a room copy are both bursts; what separates them is width and concentration.
        w = a.burst_frames
        sums = []
        base = rows[0]["frame"]
        for i in range(0, len(rows) - w, w // 2 or 1):
            sums.append((sum(r["total"] for r in rows[i:i + w]), rows[i]["frame"]))
        sums.sort(reverse=True)
        picked, used = [], []
        for tot, f in sums:
            if any(abs(f - g) < w for g in used):
                continue
            picked.append((tot, f))
            used.append(f)
            if len(picked) >= a.bursts:
                break
        print("\n★ the %d heaviest %d-frame write bursts:" % (len(picked), w))
        for tot, f in sorted(picked, key=lambda p: p[1]):
            profile(rows, f, f + w, "f%d (t=%.1f s)" % (f, f / 60.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
