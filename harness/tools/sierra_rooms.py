#!/usr/bin/env python3
"""harness/tools/sierra_rooms.py -- find and time ROOM CHANGES in a sierra_live.lua run.

★★★ THIS IS THE INSTRUMENT THE P3.6 NUMBERS COME FROM. The live Lua detector inside
sierra_live.lua is a convenience that prints candidates while you play; it is NOT the
measurement, and it does not agree with this script (see sierra_live.lua's banner).
Anything quoted as a finding comes from HERE, offline, over the recorded frames.csv.

★★ WHY OFFLINE. A live detector must decide at the instant it sees a frame. This one can
look at the whole run, which is what makes the two hard parts tractable:

  1. COALESCING. A room load is not one disk burst -- it is a cluster of them with short
     quiet gaps inside it. Live, you cannot tell "the load is still going" from "the load
     finished" until later. Offline you can.
  2. CONFIRMATION. ★★★ The event is only a room change if THE SCREEN ACTUALLY CHANGED.
     This is the correction that the first filing of P3.6 lacked: it inferred a room change
     from "disk burst, then quiet", and a MENU satisfies that exactly as well. Four menu
     events were reported as room changes and the operator caught it from the stills.

★★ AND THE SCREEN TEST MUST BE CUMULATIVE, NOT PER-FRAME. Sierra draws a room
PROGRESSIVELY: across the seven confirmed changes the per-frame lattice maximum was 16/160
while the cumulative change per transition was 47-103. A per-frame threshold reports
"no room change" through every one of them.

Usage:  python harness/tools/sierra_rooms.py build/sierra_nojoy/frames.csv [--gap 0.5] ...
"""
import argparse
import csv
import io
import statistics
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

FPS = 59.92  # CoCo3 NTSC field rate as MAME runs it; used only to convert frame counts


def find_transitions(rows, gap_s, settle_s, min_lat, min_fdc):
    """Return the room changes in a recorded run.

    A transition is:  [disk cluster] -> [draw] -> [screen settles], with the draw phase
    moving at least `min_lat` lattice points CUMULATIVELY.
    """
    gap_f = max(1, round(gap_s * FPS))
    settle_f = max(1, round(settle_s * FPS))
    out = []

    i, n = 0, len(rows)
    while i < n:
        if rows[i]["fdc"] == 0:
            i += 1
            continue

        # --- 1. coalesce the disk cluster -------------------------------------------
        start_i = i
        acc = 0
        last_active = i
        while i < n:
            if rows[i]["fdc"] > 0:
                acc += rows[i]["fdc"]
                last_active = i
            elif i - last_active >= gap_f:
                break
            i += 1
        disk_t0 = rows[start_i]["t"]
        disk_t1 = rows[last_active]["t"]

        # --- 2. the draw phase: accumulate until the screen holds still --------------
        j = last_active + 1
        lat = 0
        quiet = 0
        draw_end = None
        while j < n:
            if rows[j]["fdc"] > 0:
                break                      # the disk came back -- not a completed draw
            lat += rows[j]["changed"]
            if rows[j]["changed"] == 0:
                quiet += 1
                if quiet >= settle_f:
                    draw_end = j - settle_f + 1
                    break
            else:
                quiet = 0
            j += 1

        # --- 3. confirm ---------------------------------------------------------------
        if draw_end is not None and lat >= min_lat and acc >= min_fdc:
            out.append({
                "start_s": disk_t0,
                "disk_s": disk_t1 - disk_t0,
                "draw_s": rows[draw_end]["t"] - disk_t1,
                "fdc": acc,
                "lat": lat,
                "voff": sum(r["voffset"] for r in rows[start_i:draw_end + 1]),
                "peak_frame_lat": max(r["changed"] for r in rows[last_active + 1:draw_end + 1]),
            })
            i = max(i, draw_end + 1)
        # else: fall through -- i already sits past the cluster
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csvfile")
    ap.add_argument("--gap", type=float, default=0.5,
                    help="quiet seconds that END a disk cluster (default 0.5)")
    ap.add_argument("--settle", type=float, default=1.0,
                    help="quiet seconds that END the draw phase (default 1.0)")
    ap.add_argument("--min-lat", type=int, default=30,
                    help="CUMULATIVE lattice points that must move, of 160 (default 30)")
    ap.add_argument("--min-fdc", type=int, default=2000,
                    help="minimum FDC accesses in the cluster (default 2000)")
    a = ap.parse_args()

    rows = []
    with open(a.csvfile, encoding="utf-8", errors="replace") as f:
        for d in csv.DictReader(f):
            rows.append({
                "frame": int(d["frame"]), "t": float(d["time_s"]),
                "changed": int(d["changed"]), "fdc": int(d["fdc"]),
                "voffset": int(d["voffset"]),
            })
    print(f"{a.csvfile}: {len(rows)} frames, {rows[0]['t']:.2f}..{rows[-1]['t']:.2f} s")
    print(f"params: gap={a.gap}s settle={a.settle}s min_lat={a.min_lat}/160 min_fdc={a.min_fdc}\n")

    tr = find_transitions(rows, a.gap, a.settle, a.min_lat, a.min_fdc)
    print(f"{'#':>2} {'start_s':>8} {'disk_s':>8} {'draw_s':>8} {'TOTAL_s':>8} "
          f"{'fdc':>7} {'lat':>5} {'pk/frm':>7} {'voff':>5}")
    for k, r in enumerate(tr, 1):
        print(f"{k:>2} {r['start_s']:>8.2f} {r['disk_s']:>8.3f} {r['draw_s']:>8.3f} "
              f"{r['disk_s'] + r['draw_s']:>8.3f} {r['fdc']:>7} {r['lat']:>5} "
              f"{r['peak_frame_lat']:>7} {r['voff']:>5}")
    if not tr:
        print("(none)")
        return

    def stat(key, extra=0.0):
        v = sorted(x[key] + (x["draw_s"] if extra else 0) for x in tr)
        return min(v), statistics.median(v), max(v)

    tot = sorted(x["disk_s"] + x["draw_s"] for x in tr)
    dsk = sorted(x["disk_s"] for x in tr)
    drw = sorted(x["draw_s"] for x in tr)
    med_t = statistics.median(tot)
    print(f"\nn = {len(tr)}")
    print(f"  TOTAL  min {tot[0]:.2f}  median {med_t:.2f}  max {tot[-1]:.2f} s")
    print(f"  DISK   min {dsk[0]:.2f}  median {statistics.median(dsk):.2f}  max {dsk[-1]:.2f} s"
          f"   <- {100 * statistics.median(dsk) / med_t:.0f}% of the median total")
    print(f"  DRAW   min {drw[0]:.2f}  median {statistics.median(drw):.2f}  max {drw[-1]:.2f} s"
          f"   <- {100 * statistics.median(drw) / med_t:.0f}%")
    print(f"  VOFFSET writes across all transitions: {sum(x['voff'] for x in tr)}"
          "   <- a room change is NOT a page flip")
    print(f"  peak PER-FRAME lattice change: {max(x['peak_frame_lat'] for x in tr)}/160"
          "   <- why a per-frame detector is blind to this")


if __name__ == "__main__":
    main()
