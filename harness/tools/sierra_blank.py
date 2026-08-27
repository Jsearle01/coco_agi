#!/usr/bin/env python3
"""harness/tools/sierra_blank.py -- T-P0-016 / AC-2: does Sierra blank the display?

Consumes a sierra_live.lua run that carries the GIME tap columns and reports, for every room
change the SAME instrument found (sierra_rooms.py), what each display-affecting register did
through it.

★★ There is no GIME video-enable bit [ref: GIME-RM §2 Register Map Summary; §3 INIT0;
§6 VMODE/VRES], so "does it blank" is answered by watching every route to a blank at once:

  INIT0  bit 7 COCO   -> CoCo1/2 mode
  VMODE  bit 7 BP     -> alphanumeric; a graphics screen becomes text
  VRES   LPF = 10     -> "Reserved" [GIME-RM §6]; zero/infinite lines, i.e. all border
  BORDER              -> what such a blank would show
  VOFFSET / VSCROLL / HOFFSET -> point the scanner elsewhere
  MMU $FFA0-$FFAF     -> remap the displayed blocks (T-P0-015 §3.10's hypothesis)
  PALETTE $FFB0-$FFBF -> all sixteen to one colour: a blank with no video register at all

★★★ A LATCHED REGISTER THAT NEVER CHANGES VALUE CANNOT BE HOW ANYTHING BLANKS. That is the
form of the negative result, and it is stronger than "we saw no blanking": the registers are
write-only, a write tap sees every write, and the values are carried frame by frame.

★ AC-3: --sweep re-runs the whole answer across the coalescing gap, so the conclusion is
reported as robust or not rather than asserted at one setting.
"""
import argparse
import csv
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sierra_rooms import find_transitions  # noqa: E402

REGS = ("init0", "vmode", "vres", "border")


def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        rd = csv.DictReader(f)
        if "init0" not in (rd.fieldnames or []):
            sys.exit(f"{path} has no GIME columns -- it predates the tap. "
                     "Re-run with the current sierra_live.lua.")
        for d in rd:
            rows.append({
                "frame": int(d["frame"]), "t": float(d["time_s"]),
                "changed": int(d["changed"]), "fdc": int(d["fdc"]),
                "voffset": int(d["voffset"]), "total": int(d["total"]),
                "n_mmu": int(d["n_mmu"]), "n_pal": int(d["n_pal"]),
                "n_vid": int(d["n_vid"]),
                **{k: int(d[k]) for k in REGS},
            })
    return rows


def decode(name, v):
    if v < 0:
        return "never written"
    if name == "init0":
        return f"${v:02X} COCO={1 if v & 0x80 else 0}"
    if name == "vmode":
        return f"${v:02X} BP={1 if v & 0x80 else 0}"
    if name == "vres":
        lpf = (v >> 5) & 3
        return f"${v:02X} LPF={lpf}" + ("  ZERO-LINES" if lpf == 2 else "")
    return f"${v:02X}"


def report(rows, gap, settle, min_lat, min_fdc, pad, verbose=True):
    tr = find_transitions(rows, gap, settle, min_lat, min_fdc)
    if verbose:
        print(f"\nroom changes found: {len(tr)}   (gap={gap}s settle={settle}s "
              f"min_lat={min_lat} min_fdc={min_fdc}; window padded {pad}s each side)")
        print(f"\n{'#':>2} {'start_s':>8} {'total_s':>8} {'lat':>5} | "
              f"{'INIT0':>16} {'VMODE':>14} {'VRES':>18} {'BORDER':>7} | "
              f"{'VOFF':>5} {'MMU':>7} {'PAL':>5}")
    blanked = 0
    for k, r in enumerate(tr, 1):
        t0 = r["start_s"] - pad
        t1 = r["start_s"] + r["disk_s"] + r["draw_s"] + pad
        win = [x for x in rows if t0 <= x["t"] <= t1]
        vals = {n: sorted({x[n] for x in win}) for n in REGS}
        moved = [n for n in REGS if len(vals[n]) > 1]
        voff = sum(x["voffset"] for x in win)
        mmu = sum(x["n_mmu"] for x in win)
        pal = sum(x["n_pal"] for x in win)
        if moved or voff or pal:
            blanked += 1
        if verbose:
            def cell(n):
                s = "/".join(decode(n, v) for v in vals[n])
                return s + ("  <<< CHANGED" if len(vals[n]) > 1 else "")
            print(f"{k:>2} {r['start_s']:>8.2f} {r['disk_s'] + r['draw_s']:>8.3f} "
                  f"{r['lat']:>5} | {cell('init0'):>16} {cell('vmode'):>14} "
                  f"{cell('vres'):>18} {cell('border'):>7} | {voff:>5} {mmu:>7} {pal:>5}")
    return tr, blanked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csvfile")
    ap.add_argument("--gap", type=float, default=0.5)
    ap.add_argument("--settle", type=float, default=1.0)
    ap.add_argument("--min-lat", type=int, default=30)
    ap.add_argument("--min-fdc", type=int, default=2000)
    ap.add_argument("--pad", type=float, default=1.0,
                    help="seconds of margin each side of the transition window")
    ap.add_argument("--sweep", action="store_true",
                    help="AC-3: re-run the answer across the coalescing gap")
    a = ap.parse_args()

    rows = load(a.csvfile)
    print(f"{a.csvfile}: {len(rows)} frames, {rows[0]['t']:.2f}..{rows[-1]['t']:.2f} s")

    tr, blanked = report(rows, a.gap, a.settle, a.min_lat, a.min_fdc, a.pad)

    print(f"\n{'=' * 78}")
    if not tr:
        print("NO ROOM CHANGES FOUND -- nothing to conclude.")
    elif blanked == 0:
        print("★★★ ANSWER: NO. Sierra does NOT blank the display during a room change.")
        print(f"    Across {len(tr)} transitions, INIT0, VMODE, VRES and BORDER never changed")
        print("    value, and VOFFSET and the palette were never written.")
        print("    ★★ THE MMU IS THE EXCEPTION AND IT IS NOT AN EXCEPTION: OS-9 task-switches")
        print("    constantly, so $FFA0-$FFAF is written throughout. See the MMU RATE test")
        print("    below -- a remap-driven buffer swap would be a BURST, not a background rate.")
    else:
        print(f"★★★ ANSWER: YES, in {blanked} of {len(tr)} transitions something moved. "
              "See the CHANGED / non-zero columns above.")
    print("=" * 78)

    # ── the whole run, not just the transitions ──────────────────────────────────────────
    after = [x for x in rows if x["vmode"] & 0x80]        # once graphics mode is on
    if after:
        print(f"\nWHOLE RUN once graphics mode is entered (t={after[0]['t']:.2f}s onward, "
              f"{len(after)} frames):")
        for n in REGS:
            v = sorted({x[n] for x in after})
            print(f"   {n:>7}: {[decode(n, x) for x in v]}"
                  f"{'   <<< CHANGED' if len(v) > 1 else '   (constant)'}")
        print(f"   VOFFSET writes {sum(x['voffset'] for x in after)}   "
              f"palette writes {sum(x['n_pal'] for x in after)}   "
              f"MMU writes {sum(x['n_mmu'] for x in after)}")

    # ── ★★ T-P0-015 §3.10's HYPOTHESIS, TESTED RATHER THAN WAVED AWAY ────────────────────
    # That report proposed the picture might be made visible by REMAPPING MMU SLOTS, since the
    # previous run's write tap covered $0000-$FEFF and the MMU sits above it. It is now tapped.
    # But OS-9 task-switches constantly, so a raw count proves nothing -- the question is
    # whether the rate is ELEVATED when the screen changes. A buffer swap is one burst of a
    # few writes at one instant; task switching is a steady background rate.
    if tr:
        spans = [(r["start_s"] - a.pad,
                  r["start_s"] + r["disk_s"] + r["draw_s"] + a.pad) for r in tr]
        gfx = [x for x in rows if x["vmode"] & 0x80]
        inw = [x for x in gfx if any(lo <= x["t"] <= hi for lo, hi in spans)]
        out = [x for x in gfx if not any(lo - 3 <= x["t"] <= hi + 3 for lo, hi in spans)]
        if inw and out:
            ri = sum(x["n_mmu"] for x in inw) / len(inw)
            ro = sum(x["n_mmu"] for x in out) / len(out)
            pk = max(x["n_mmu"] for x in gfx)
            print(f"\n★★ MMU REMAP TEST ($FFA0-$FFAF) -- T-P0-015 §3.10's hypothesis")
            print(f"   during transitions : {ri:8.1f} writes/frame  ({len(inw)} frames)")
            print(f"   idle in-game       : {ro:8.1f} writes/frame  ({len(out)} frames)")
            print(f"   ratio              : {ri / max(ro, 1e-9):8.2f}x")
            print(f"   peak in any single frame: {pk}")
            if ri <= ro * 1.5:
                print("   ★★★ NOT ELEVATED -- consistent with OS-9 task switching and NOT with")
                print("       a remap-driven buffer swap. The §3.10 hypothesis is NOT supported.")
            else:
                print("   ★★★ ELEVATED -- worth a per-write dump of $FFA0-$FFAF next.")

    if a.sweep:
        print("\n★ AC-3 -- is the answer robust to the free parameter?")
        print(f"{'gap_s':>6} {'n':>4} {'transitions with ANY display change':>38}")
        for g in (0.25, 0.5, 1.0, 1.5, 2.0, 3.0):
            t2, b2 = report(rows, g, a.settle, a.min_lat, a.min_fdc, a.pad, verbose=False)
            print(f"{g:>6.2f} {len(t2):>4} {b2:>38}")
        print("  ★ the answer is the right-hand column; if it is 0 throughout, the conclusion")
        print("    does not depend on the parameter that invalidated T-P0-015's disk split.")


if __name__ == "__main__":
    main()
