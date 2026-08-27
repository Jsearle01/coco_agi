#!/usr/bin/env python3
"""harness/tools/sierra_cost.py -- T-P0-018 / AC-4: what does Sierra's draw cost per screen pixel?

★★★ THE COMPARISON THE THREAD HAS BEEN FOR. Ours, from T-P0-013/014's recorded counters:
      7.473 s per picture / 26,409 pixels written x 1.79 MHz  =  ~506 cycles per pixel
      of which the boundary test is 3.09 tests/pixel x 86 cycles = ~266.

Theirs is derived the same way, from the live trace:
      draw-phase seconds x 1.79 MHz / writes that LAND ON THE DISPLAY.

★★ Writes are resolved to physical addresses through the MMU tracked in sierra_pc.lua, so
"lands on the display" means physical address within [VOFFSET, VOFFSET+30720) -- not a guess
about which CPU block happens to be the screen, which is what T-P0-017 could not do.

★★ THIS IS A CEILING ON THEIR FILL, NOT A MEASUREMENT OF IT. The draw phase contains
everything between the last disk access and the screen settling -- LOGIC, view setup, whatever
else -- so the true per-pixel fill cost is LOWER than this number. It is stated as a bound and
compared as one.

★ L-24: KQ3, Floppy 360K variant, one operator session.
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sierra_rooms import find_transitions  # noqa: E402

CLOCK = 1_789_773.0      # CoCo3 6809 at ~1.79 MHz
OUR_SECONDS = 7.473      # T-P0-014 median, one picture, no disk
OUR_PIXELS = 26_409      # T-P0-014: 1,188,430 put_pixel writes / 45 pictures
OUR_TESTS_PER_PX = 3.09  # T-P0-016 §6, from recorded counters
OUR_TEST_CYCLES = 86     # T-P0-013


def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        rd = csv.DictReader(f)
        if "scr_w" not in (rd.fieldnames or []):
            sys.exit(f"{path} lacks scr_w -- re-run with sierra_pc.lua")
        for d in rd:
            rows.append({
                "frame": int(d["frame"]), "t": float(d["time_s"]),
                "changed": int(d["changed"]), "fdc": int(d["fdc"]),
                "voffset": int(d["voffset"]), "total": int(d["total"]),
                "maxrun": int(d["w_maxrun"]), "seq": int(d["w_seq"]),
                "scr_w": int(d["scr_w"]), "unres": int(d["unres"]),
                "pcsamp": int(d["pcsamp"]),
            })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csvfile")
    ap.add_argument("--gap", type=float, default=0.5)
    ap.add_argument("--settle", type=float, default=1.0)
    ap.add_argument("--min-lat", type=int, default=30)
    ap.add_argument("--min-fdc", type=int, default=2000)
    ap.add_argument("--pad", type=float, default=0.0,
                    help="extra seconds of draw phase to include (default 0)")
    ap.add_argument("--sweep", action="store_true")
    a = ap.parse_args()

    rows = load(a.csvfile)
    tr = find_transitions(rows, a.gap, a.settle, a.min_lat, a.min_fdc)
    print(f"{a.csvfile}: {len(rows)} frames, {rows[0]['t']:.2f}..{rows[-1]['t']:.2f} s")
    print(f"transitions: {len(tr)}\n")

    # ★ the resolver's own health: what fraction of writes could not be placed?
    gfx = [x for x in rows if x["t"] > 48]
    tw = sum(x["total"] for x in gfx)
    tu = sum(x["unres"] for x in gfx)
    print(f"★ MMU resolver: {tu} of {tw} writes unresolved after graphics mode "
          f"({100*tu/max(tw,1):.2f}%) -- unresolved writes are never counted as screen writes\n")

    print(f"{'#':>2} {'draw_s':>7} {'frames':>7} {'ALL writes':>11} {'ON SCREEN':>10} "
          f"{'screenfuls':>11} {'cycles':>10} {'cyc/px':>8} {'PC hits':>8}")
    percpx = []
    for k, r in enumerate(tr, 1):
        t1 = r["start_s"] + r["disk_s"]
        win = [x for x in rows if t1 < x["t"] <= t1 + r["draw_s"] + a.pad]
        if not win:
            continue
        allw = sum(x["total"] for x in win)
        sw = sum(x["scr_w"] for x in win)
        pcs = sum(x["pcsamp"] for x in win)
        secs = r["draw_s"] + a.pad
        cyc = secs * CLOCK
        cpp = cyc / max(sw, 1)
        percpx.append(cpp)
        print(f"{k:>2} {secs:>7.3f} {len(win):>7} {allw:>11} {sw:>10} "
              f"{sw/26880:>11.2f} {cyc:>10.0f} {cpp:>8.1f} {pcs:>8}")

    if not percpx:
        print("no transitions")
        return
    percpx.sort()
    med = percpx[len(percpx) // 2]
    our_cpp = OUR_SECONDS * CLOCK / OUR_PIXELS

    print(f"\n{'=' * 78}")
    print("★★★ CYCLES PER SCREEN PIXEL WRITTEN")
    print(f"    SIERRA  min {percpx[0]:.1f}  median {med:.1f}  max {percpx[-1]:.1f}"
          "   <- a CEILING: the draw phase includes their non-fill work")
    print(f"    OURS    {our_cpp:.1f}   ({OUR_SECONDS} s / {OUR_PIXELS} px, no disk at all)")
    print(f"    ★ ratio {our_cpp/med:.1f}x   -- and the true ratio is LARGER, "
          "because theirs is a ceiling")
    print(f"    ★ our boundary test alone: {OUR_TESTS_PER_PX} tests/px x {OUR_TEST_CYCLES} cy "
          f"= {OUR_TESTS_PER_PX*OUR_TEST_CYCLES:.0f} cy/px"
          f"  -- {'MORE' if OUR_TESTS_PER_PX*OUR_TEST_CYCLES > med else 'less'} than "
          "Sierra's ENTIRE per-pixel budget")
    print("=" * 78)

    if a.sweep:
        print("\n★ L-46 -- is the ratio robust to how the draw phase is bounded?")
        print(f"{'pad_s':>7} {'n':>3} {'median cyc/px':>15} {'ratio vs ours':>15}")
        for pad in (0.0, 0.25, 0.5, 1.0):
            vals = []
            for r in tr:
                t1 = r["start_s"] + r["disk_s"]
                win = [x for x in rows if t1 < x["t"] <= t1 + r["draw_s"] + pad]
                sw = sum(x["scr_w"] for x in win)
                if sw:
                    vals.append((r["draw_s"] + pad) * CLOCK / sw)
            if vals:
                vals.sort()
                mv = vals[len(vals) // 2]
                print(f"{pad:>7.2f} {len(vals):>3} {mv:>15.1f} {our_cpp/mv:>14.1f}x")


if __name__ == "__main__":
    main()
