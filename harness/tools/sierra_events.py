#!/usr/bin/env python3
"""sierra_events.py -- SCREEN-CHANGE EVENTS PER SECOND from a sierra_live.lua frames.csv.

WHY THIS FILE EXISTS, AND IT IS A DEBT BEING PAID [T-P0-148 SS3(3)].
P6.91 published ">=5.87 events/second" for Sierra's walking ego and "0.00-0.40" for its idle
rooms, and BOTH CAME FROM AN UNSAVED SCRATCHPAD SCRIPT.  sierra_rooms.py measures room
transitions and nothing else; no tool in the tree computed the events figure.  That is L-45
exactly -- "an unsaved analysis script cannot be audited, and the act of saving it is itself a
check" -- and T-P0-015's withdrawn 88%-disk figure is the precedent.

T-P0-148 compares Sierra's busy room against ours, so the two rates must be THE SAME
MEASUREMENT.  This file is that measurement, written down, and it is validated by re-deriving
P6.91's own published number from P6.91's own frames.csv (--selftest).  If it cannot reproduce
5.87 on that data, the definitions differ and no comparison may be quoted [SS2W].

THE DEFINITION, exactly as P6.91's report SS5 records it:
  * the instrument is sierra_live.lua's 16x10 LATTICE: 160 sample points over the 640x239
    screen, and `changed` is how many of them differ from the previous frame;
  * a frame COUNTS when changed > 0;
  * CONSECUTIVE counting frames COALESCE into ONE EVENT -- a visual update that spans three
    frames is one event, not three.  This is what makes it a rate of updates rather than of
    frames;
  * the window must have the DISK QUIET (fdc == 0 unless --allow-disk), because OS-9's RBF
    driver polls and a disk burst moves the screen for reasons that are not animation;
  * rate = events / (frames / 60).

★★★★★ AND THE WARNING BELOW WAS IGNORED FOR EIGHT DISPATCHES [T-P0-155].  This header has said
"a lower bound on anything per-object" since T-P0-148, and P6.91's report said the figure "must
never be quoted as an equality".  The Orchestrator then used 5.23 and 5.87 as Sierra's per-second
rate in eight consecutive dispatches, and P6.94's "~3x more sensitive per object" is a ratio
against that floor.  Jay's eye caught it: "the ego animates and moves MUCH faster than the
difference would suggest."

★★★★★ THE FIX IS NOT A BETTER EVENT RATE, IT IS A DIFFERENT OBSERVABLE: the MODAL INTERVAL between
event STARTS, in frames.  Coalescing can only LENGTHEN a gap, so the mode is an upper bound on the
update interval and a LOWER bound on the rate.  Measured 3-4 frames across five windows in three
recordings = 15-20 updates/second, against the 5.23 this rate reported for the same window.
★★★ Use `--window` and take the modal gap when you need a RATE.  This file's events/second is for
comparing one window with another under the SAME instrument, and for nothing else.

WHAT IT IS NOT, AND THE REPORT MUST SAY SO.
  ** A LOWER BOUND ON ANYTHING PER-OBJECT. **  A 16x10 lattice undersamples: a small sprite can
move several pixels and trip no sample point at all, and two objects updating in the same frame
are ONE event.  So this counts SCREEN UPDATES, not cels, not steps, not cycles.  It may only be
compared with another figure produced the same way -- which is the whole reason it is a file.

SS2V: this is host-side analysis and is never ported; no 6809 form is implied.
SS2P: reads a recording; opens no game file.
"""
import argparse
import csv
import sys


def load(path):
    with open(path, newline="", encoding="utf-8") as f:
        return [
            {"frame": int(r["frame"]), "t": float(r["time_s"]),
             "changed": int(r["changed"]), "fdc": int(r["fdc"])}
            for r in csv.DictReader(f)
        ]


def events(rows, lo, hi, allow_disk):
    """-> (n_events, n_changed_frames, n_frames, fdc_total, magnitudes)"""
    win = [r for r in rows if lo <= r["frame"] < hi]
    if not win:
        return None
    hits = [r["frame"] for r in win if r["changed"] > 0]
    mags = [r["changed"] for r in win if r["changed"] > 0]
    # ★ Coalesce runs of CONSECUTIVE frames into one event.
    n_ev, prev = 0, None
    for f in hits:
        if prev is None or f != prev + 1:
            n_ev += 1
        prev = f
    return n_ev, len(hits), len(win), sum(r["fdc"] for r in win), mags


def report(rows, lo, hi, label, allow_disk):
    e = events(rows, lo, hi, allow_disk)
    if e is None:
        print("%-30s -- no frames in [%d,%d)" % (label, lo, hi))
        return None
    n_ev, n_hit, n_fr, fdc, mags = e
    secs = n_fr / 60.0
    warn = ""
    if fdc > 0 and not allow_disk:
        warn = "   ★★★ DISK ACTIVE (%d) -- not a clean animation window" % fdc
    print("%-30s %6.1f s  events %4d = %5.2f/s   (changed frames %4d, mean lat %4.1f/160, max %d)%s"
          % (label, secs, n_ev, n_ev / secs if secs else 0, n_hit,
             sum(mags) / len(mags) if mags else 0, max(mags) if mags else 0, warn))
    return n_ev / secs if secs else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", nargs="?")
    ap.add_argument("--window", action="append", default=[],
                    help="LO:HI:label -- a frame range to report; repeatable")
    ap.add_argument("--allow-disk", action="store_true",
                    help="do not warn when the disk is active in the window")
    ap.add_argument("--quiet-windows", type=int, default=0, metavar="N",
                    help="auto-find the N longest disk-quiet runs and report each")
    ap.add_argument("--selftest", action="store_true",
                    help="re-derive P6.91's published 5.87/s and 0.00-0.40/s from its own csv")
    a = ap.parse_args()

    if a.selftest:
        # ★★★★★ §2W: the tool must reproduce the figure it is standing in for, on the data that
        # produced it, BEFORE it is used on anything new. The windows are P6.91's report §5.
        path = a.csv or r"build\sierra_bench_live\frames.csv"
        rows = load(path)
        print("SELFTEST against %s -- P6.91's own recording" % path)
        got = report(rows, 7200, 7660, "MOVING (keys 120.6-127.4 s)", a.allow_disk)
        report(rows, 7660, 7980, "idle after that burst", True)
        report(rows, 6300, 6900, "idle before room change 3", True)
        if got is None:
            print("★★★ FAILED: window empty"); return 1
        ok = abs(got - 5.87) < 0.05
        print("\nP6.91 published 5.87/s for the moving window; this tool computes %.2f/s -- %s"
              % (got, "MATCH, the definitions are identical" if ok else
                 "★★★ MISMATCH -- the definitions differ and no comparison may be quoted"))
        return 0 if ok else 1

    if not a.csv:
        ap.error("a csv is required unless --selftest")
    rows = load(a.csv)
    print("%s: %d frames, %.2f..%.2f s" % (a.csv, len(rows), rows[0]["t"], rows[-1]["t"]))

    for w in a.window:
        parts = w.split(":")
        lo, hi = int(parts[0]), int(parts[1])
        report(rows, lo, hi, parts[2] if len(parts) > 2 else "f%d-%d" % (lo, hi), a.allow_disk)

    if a.quiet_windows:
        # ★★★ Disk-quiet runs, longest first: the operator cannot be asked to note frame numbers,
        # so the tool finds the windows where animation is the only thing moving the screen.
        runs, cur = [], None
        for r in rows:
            if r["fdc"] == 0:
                if cur is None:
                    cur = [r["frame"], r["frame"]]
                else:
                    cur[1] = r["frame"]
            else:
                if cur and cur[1] - cur[0] >= 120:
                    runs.append(tuple(cur))
                cur = None
        if cur and cur[1] - cur[0] >= 120:
            runs.append(tuple(cur))
        runs.sort(key=lambda p: p[0] - p[1])
        print("\n★ the %d longest disk-quiet windows (>= 2 s), longest first:" % a.quiet_windows)
        for lo, hi in runs[:a.quiet_windows]:
            report(rows, lo, hi + 1, "f%d-%d" % (lo, hi), True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
