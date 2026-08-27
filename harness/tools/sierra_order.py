#!/usr/bin/env python3
"""harness/tools/sierra_order.py -- T-P0-017 / AC-4: is the on-screen write order a LINEAR COPY
or VECTOR INTERPRETATION?

★★★ THE DISCRIMINATOR. An AGI picture is vector commands -- lines, strokes and floods in
resource order, i.e. arbitrary spatial order. A memory-to-memory blit walks addresses upward
one byte at a time. sierra_shadow.lua classifies every CPU write against its predecessor:

    seq  : addr == prev + 1     <- what a copy does, for its entire length
    asc  : addr  > prev         <- weaker: a downward-drawing renderer also ascends
    other: addr <= prev         <- vector interpretation jumps backwards constantly

and records the LONGEST RUN of consecutive +1 writes per frame.

★★ A 26,880-byte blit cannot hide from this. Even split across frames it must produce runs of
thousands, because the copy loop's whole job is to walk memory in order. A flood fill cannot
produce them: it moves along a scanline, then jumps to the next seed.

★ AC-3 / L-46: --sweep varies the run threshold, so the conclusion is reported as robust to it
or not, rather than asserted at one cutoff.
"""
import argparse
import csv
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sierra_rooms import find_transitions  # noqa: E402


def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        rd = csv.DictReader(f)
        need = {"w_seq", "w_asc", "w_other", "w_maxrun"}
        if not need <= set(rd.fieldnames or []):
            sys.exit(f"{path} lacks the write-order columns -- re-run with sierra_shadow.lua")
        for d in rd:
            rows.append({
                "frame": int(d["frame"]), "t": float(d["time_s"]),
                "changed": int(d["changed"]), "fdc": int(d["fdc"]),
                "voffset": int(d["voffset"]), "total": int(d["total"]),
                "seq": int(d["w_seq"]), "asc": int(d["w_asc"]),
                "oth": int(d["w_other"]), "maxrun": int(d["w_maxrun"]),
                "lo": int(d["w_lo"]), "hi": int(d["w_hi"]),
            })
    return rows


def phases(rows, tr, pad):
    """-> (index, label, frames) for each transition's disk phase and draw phase."""
    out = []
    for k, r in enumerate(tr, 1):
        t0, t1 = r["start_s"], r["start_s"] + r["disk_s"]
        t2 = t1 + r["draw_s"]
        out.append((k, "disk", [x for x in rows if t0 <= x["t"] <= t1]))
        out.append((k, "draw", [x for x in rows if t1 < x["t"] <= t2 + pad]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csvfile")
    ap.add_argument("--gap", type=float, default=0.5)
    ap.add_argument("--settle", type=float, default=1.0)
    ap.add_argument("--min-lat", type=int, default=30)
    ap.add_argument("--min-fdc", type=int, default=2000)
    ap.add_argument("--pad", type=float, default=0.5,
                    help="seconds after the settle still counted as the draw phase")
    ap.add_argument("--run-threshold", type=int, default=1024,
                    help="a 'long sequential run' -- the copy signature (default 1024)")
    ap.add_argument("--sweep", action="store_true")
    a = ap.parse_args()

    rows = load(a.csvfile)
    tr = find_transitions(rows, a.gap, a.settle, a.min_lat, a.min_fdc)
    print(f"{a.csvfile}: {len(rows)} frames, {rows[0]['t']:.2f}..{rows[-1]['t']:.2f} s")
    print(f"transitions: {len(tr)}   run threshold {a.run_threshold} bytes\n")

    print(f"{'#':>2} {'phase':>5} {'frames':>7} {'writes':>10} {'seq%':>6} {'asc%':>6} "
          f"{'other%':>7} {'MAXRUN':>7} {'frames>=thr':>12}")
    for k, lbl, win in phases(rows, tr, a.pad):
        if not win:
            continue
        s = sum(x["seq"] for x in win)
        c = sum(x["asc"] for x in win)
        o = sum(x["oth"] for x in win)
        n = s + c + o
        mr = max(x["maxrun"] for x in win)
        nb = sum(1 for x in win if x["maxrun"] >= a.run_threshold)
        print(f"{k:>2} {lbl:>5} {len(win):>7} {n:>10} {100*s/max(n,1):>5.1f}% "
              f"{100*c/max(n,1):>5.1f}% {100*o/max(n,1):>6.1f}% {mr:>7} {nb:>12}")

    # ── calibration: what DOES a linear walk look like on this machine? ──────────────────
    # ★★ L-47 again: a negative is only meaningful if the instrument can register a positive.
    allmax = max(x["maxrun"] for x in rows)
    top = sorted(rows, key=lambda x: -x["maxrun"])[:8]
    print("\n★★ CALIBRATION -- the longest sequential runs anywhere in the session:")
    for x in top:
        print(f"   f{x['frame']:<6} t={x['t']:>8.3f}s  run {x['maxrun']:>6} bytes  "
              f"(${x['lo']:04X}-${x['hi']:04X})")
    print(f"   ★ the instrument CAN see a linear walk: it found {allmax} consecutive bytes.")

    draw_frames = [x for k, lbl, win in phases(rows, tr, a.pad) if lbl == "draw" for x in win]
    if draw_frames:
        dmax = max(x["maxrun"] for x in draw_frames)
        dmed = statistics.median(x["maxrun"] for x in draw_frames)
        print(f"\n{'=' * 78}")
        print(f"★★★ LONGEST SEQUENTIAL RUN IN ANY TRANSITION'S DRAW PHASE: {dmax} bytes")
        print(f"    (median per frame {dmed:.0f}; a rendered AGI room is 26,880 bytes)")
        if dmax < a.run_threshold:
            print("    ★★★ NO COPY SIGNATURE. The repaint is NOT a linear blit.")
        else:
            print("    ★★★ A COPY SIGNATURE IS PRESENT -- see the table.")
        print("=" * 78)

        if a.sweep:
            print("\n★ AC-3 / L-46 -- is the answer robust to the run threshold?")
            print(f"{'thr':>6} {'draw frames at/above it':>26}")
            for thr in (32, 64, 128, 256, 512, 1024, 2048, 4096):
                n = sum(1 for x in draw_frames if x["maxrun"] >= thr)
                print(f"{thr:>6} {n:>26}")
            print("  ★ a count of 0 from a threshold far below 26,880 upward means no copy of a")
            print("    picture-sized region happened, whatever cutoff you prefer.")


if __name__ == "__main__":
    main()
