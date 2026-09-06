#!/usr/bin/env python3
"""harness/tools/plane_sweep.py -- both-plane divergence across a whole corpus sweep. [T-P0-055 AC-5]

★★★★★ WHY IT IMPORTS RATHER THAN REIMPLEMENTS. The comparison logic -- per-plane encoding
detection, the nibble convention, the kind split -- lives once, in plane_pair_diff.py, and this
calls it. **A sweep summariser that re-derived the comparison is exactly how a corpus-wide figure
comes to mean something different from the per-picture figure it is supposed to aggregate.**

★★★★ AND IT REPORTS BOTH PLANES PER PICTURE [L-88]. The predecessor of this table reported one
plane for seven pictures across four tasks, and the priority plane -- which was the broken one --
sat unread on disk beside it the whole time.

★★★ A picture counts as PASS only when BOTH planes are 0. A row that passes visual and fails
priority is a FAIL and is printed as one, because that is the exact shape the old instrument
could not see.

★ §2P: reads plane dumps and prints counts.

usage: python harness/tools/plane_sweep.py <build-dir> <oracle-dir> [--prefix p3b_sw]
"""
import argparse
import pathlib
import re
import sys

import plane_pair_diff as ppd


def quiet_compare(guest, ref, clear):
    """The same comparison plane_pair_diff makes, without the narration."""
    unpaired = sum(1 for g in guest if (g >> 4) != (g & 0x0F))
    doubled = unpaired < len(guest) // 2
    shift = 4 if doubled else 0
    diff = under = 0
    for i, r in enumerate(ref):
        gv = (guest[i] >> shift) & 0x0F
        rv = r & 0x0F
        if gv != rv:
            diff += 1
            if gv == clear and rv != clear:
                under += 1
    return diff, under


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build_dir")
    ap.add_argument("oracle_dir")
    ap.add_argument("--prefix", default="p3b_sw")
    a = ap.parse_args()

    bd, od = pathlib.Path(a.build_dir), pathlib.Path(a.oracle_dir)
    rows, excluded = [], []
    for d in sorted(bd.glob(a.prefix + "*")):
        if not (d / "guest.visual.bin").exists():
            continue
        num = int(d.name[len(a.prefix):])
        # ★★★★★ DID THIS RUN ACTUALLY RENDER THIS PICTURE? A dump exists either way, and comparing
        # one that does not is how a HARNESS failure gets reported as a RENDERER failure. Two
        # real cases, both found in the first full sweep:
        #   * the room jump missed -- sw020 ended on room 83, sw054 on room 53, so a title-screen
        #     render was about to be scored against picture 20's reference at 93.8% divergence;
        #   * res_open failed (err 2) -- pictures in volumes this harness does not stage never
        #     rendered at all, and the plane still held the PREVIOUS room.
        # ★★★ Neither is evidence about the renderer, and both look exactly like catastrophic
        # divergence. The run log is the artifact that distinguishes them, so it is read [L-88].
        log = d / "run.log"
        if log.exists():
            txt = log.read_text(encoding="utf-8", errors="replace")
            m = re.search(r"final room\s+(\d+),\s+sprites\s+(\d+),\s+err\s+(\d+)", txt)
            if m:
                room, err = int(m.group(1)), int(m.group(3))
                if room != num:
                    excluded.append((num, "room jump missed -- rendered room %d" % room))
                    continue
                if err:
                    excluded.append((num, "err %d -- resource not loaded, no render" % err))
                    continue
        ov = od / ("pic%03d.visual.bin" % num)
        op = od / ("pic%03d.priority.bin" % num)
        if not ov.exists() or not op.exists():
            print("  pic%03d: NO ORACLE REFERENCE -- skipped" % num)
            continue
        gv = (d / "guest.visual.bin").read_bytes()
        gp = (d / "guest.priority.bin").read_bytes()
        vd, vu = quiet_compare(gv, ov.read_bytes(), 15)
        pd, pu = quiet_compare(gp, op.read_bytes(), 4)
        rows.append((num, vd, vu, pd, pu))

    print("%-6s %10s %10s %10s %10s  %s"
          % ("pic", "visual", "vis-under", "priority", "pri-under", "verdict"))
    print("-" * 72)
    npass = 0
    fails = []
    for num, vd, vu, pd, pu in rows:
        ok = (vd == 0 and pd == 0)
        if ok:
            npass += 1
        else:
            fails.append(num)
        print("%-6d %10d %10d %10d %10d  %s"
              % (num, vd, vu, pd, pu, "PASS" if ok else "**FAIL**"))
    print("-" * 72)
    print("★ %d of %d RENDERED pictures byte-identical on BOTH planes (%.1f%%)"
          % (npass, len(rows), 100.0 * npass / len(rows) if rows else 0.0))
    if fails:
        print("★★ FAILING: %s" % ", ".join(str(f) for f in fails))
    if excluded:
        print("★★★ EXCLUDED (the run did not render this picture -- harness, not renderer): %d"
              % len(excluded))
        for num, why in excluded:
            print("      pic%03d  %s" % (num, why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
