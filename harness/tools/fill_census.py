#!/usr/bin/env python3
"""harness/tools/fill_census.py -- WHICH KIND of fill does each picture ask for? [T-P0-054 AC-5]

★★★★★ THE QUESTION, AND WHY FILL COUNT IS NOT IT. p3b's divergence against the oracle does not
track a picture's fill TOTAL: picture 3 has the FEWEST fills of the diverging set (17) and the WORST
divergence (71.5%); picture 53 has the most (26) and is middling (23.9%); picture 80 has 2 and is the
only clean one [AD-120, and Jay's eye: "the castle appears to have more intricate fills required"].

★★★★ SO THE CANDIDATE IS THE FILL'S *CASE*, NOT ITS COUNT. pic_fill.s selects the test plane ONCE
PER SPAN and gets a different loop for each:

    FC_VISUAL    test visual == 15    70.3% of calls   -- the flat byte-pointer walk
    FC_PRIORITY  test priority == 4    6.4% of calls   -- the NIBBLE walk under -DPRI_PACKED
    FC_NEVER     always false          the rest

★★★★★ AND THE PRIORITY WALK IS THE ONE NO GATE REACHES. pic_probe forces PLANE_PRI_FLAT whenever
windowing is on, so "the priority walk's windowing is still exercised only by p3b"
[pic_probe.s:86-89, the file's own words]. **If divergence tracks a picture's FC_PRIORITY share, that
names the defect's home.** If it does not, the candidate is refuted and that is worth recording.

★★★ WHAT DECIDES THE CASE IS THE PICTURE'S OWN ENABLE STATE, which is why this is a static read of
the resource and needs no emulator: a fill is FC_VISUAL when the visual plane is enabled, and takes
the priority path when visual is disabled and priority is not.

★★ AGI picture opcodes [AGI Specs §7; the same set picset.py censuses]:
    F0 set_visual(c)  F1 disable_visual   F2 set_priority(c)  F3 disable_priority
    F4 y_corner  F5 x_corner  F6 abs_line  F7 rel_line
    F8 fill  F9 set_pattern(n)  FA pattern_fill  FF end
★ Opcodes take coordinate lists that run until the next byte >= $F0, which is how the walk finds the
next instruction without a length field.

★ §2P: reads resources, prints counts. No pixels, no game data written.

usage: python harness/tools/fill_census.py <resdir> [--only 001,003,022,053,080]
"""
import argparse
import pathlib
import re
import sys

OP_SET_VIS, OP_DIS_VIS = 0xF0, 0xF1
OP_SET_PRI, OP_DIS_PRI = 0xF2, 0xF3
OP_FILL, OP_SET_PAT, OP_PAT_FILL, OP_END = 0xF8, 0xF9, 0xFA, 0xFF


def census(data):
    """Walk one picture resource, counting fills by the plane state in force."""
    i, n = 0, len(data)
    vis_on = pri_on = False
    r = {"fill_ops": 0, "fill_pts": 0, "vis_pts": 0, "pri_pts": 0,
         "pri_only_pts": 0, "both_pts": 0, "pat_ops": 0, "pat_pts": 0,
         "unknown": 0}
    while i < n:
        b = data[i]
        i += 1
        if b == OP_END:
            break
        if b == OP_SET_VIS:
            vis_on = True
            i += 1
        elif b == OP_DIS_VIS:
            vis_on = False
        elif b == OP_SET_PRI:
            pri_on = True
            i += 1
        elif b == OP_DIS_PRI:
            pri_on = False
        elif b in (OP_FILL, OP_PAT_FILL):
            if b == OP_PAT_FILL:
                r["pat_ops"] += 1
            else:
                r["fill_ops"] += 1
            # ★ the coordinate list: pairs until the next opcode byte
            pts = 0
            while i + 1 < n and data[i] < 0xF0 and data[i + 1] < 0xF0:
                i += 2
                pts += 1
            if b == OP_PAT_FILL:
                r["pat_pts"] += pts
            else:
                r["fill_pts"] += pts
            # ★★ Attribute each seed point to the plane state IN FORCE at that fill.
            if vis_on:
                r["vis_pts"] += pts
            if pri_on:
                r["pri_pts"] += pts
            if pri_on and not vis_on:
                r["pri_only_pts"] += pts
            if pri_on and vis_on:
                r["both_pts"] += pts
        elif b == OP_SET_PAT:
            i += 1
        elif b >= 0xF0:
            # a drawing opcode; skip its coordinate list
            while i < n and data[i] < 0xF0:
                i += 1
        else:
            r["unknown"] += 1
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("resdir")
    ap.add_argument("--only", default="")
    # ★★ A TITLE IS REQUIRED, NOT OPTIONAL POLISH. The staged set holds all three games and the
    # picture NUMBER is not unique across them -- the first run of this tool printed picture 1
    # three times (KQ1, KQ2, KQ3) and the rows only looked like noise because I knew the sample.
    ap.add_argument("--title", default="Kingquest1",
                    help="game prefix; picture numbers repeat across titles")
    a = ap.parse_args()

    want = set(x.strip().lstrip("0") or "0" for x in a.only.split(",") if x.strip())
    rows = []
    for p in sorted(pathlib.Path(a.resdir).glob(a.title + "-*.res")):
        m = re.search(r"-(\d+)\.res$", p.name)
        if not m:
            continue
        num = m.group(1).lstrip("0") or "0"
        if want and num not in want:
            continue
        rows.append((int(num), p.name, census(p.read_bytes())))

    print("%-5s %7s %7s %8s %8s %9s %8s" %
          ("pic", "fillOp", "seeds", "visSeed", "priSeed", "PRI-ONLY", "patOp"))
    print("-" * 60)
    for num, name, r in rows:
        print("%-5d %7d %7d %8d %8d %9d %8d" %
              (num, r["fill_ops"], r["fill_pts"], r["vis_pts"], r["pri_pts"],
               r["pri_only_pts"], r["pat_ops"]))
    if not rows:
        print("no .res files matched")
        return 1
    tot_pat = sum(r["pat_ops"] for _, _, r in rows)
    print("-" * 60)
    print("★ pattern-fill ops across this set: %d" % tot_pat)

    # ★★★★★ THE SEPARATOR, MEASURED OVER THE WHOLE SET [T-P0-054 AC-5/AC-7].
    # priSeed is the count of fill seed points issued while the PRIORITY plane is enabled -- i.e.
    # fills that must WRITE the priority plane. Picture 80, the only picture measured clean in p3b,
    # is the only one of the seven sampled with priSeed == 0; all six that diverge have priSeed > 0.
    # ★★★ So this reports how much of the corpus shares picture 80's exemption. **A small number
    # here means the clean sample was not representative** -- which is the charge P3b.17 laid
    # against picture 80 on fill COUNT, restated on the axis that actually separates.
    zero = [n for n, _, r in rows if r["pri_pts"] == 0]
    print("★★ pictures with priSeed == 0 (no fill writes the priority plane): %d of %d (%.1f%%)"
          % (len(zero), len(rows), 100.0 * len(zero) / len(rows)))
    if zero:
        print("   %s" % ", ".join(str(n) for n in zero[:40]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
