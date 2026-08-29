#!/usr/bin/env python3
"""harness/tools/comp_pick.py -- AC-9: rank frames by how much OCCLUSION they actually contain.

★★★ THE SELECTION IS THE WHOLE ASK. AC-4 found two titles where the byte gate would pass with
the priority test INVERTED, because their sample frames contain no occlusion at all -- every
sprite stands in front of everything. A frame like that exercises transparency and nothing else,
so showing it to a human proves nothing about depth.

★★ The score is the number of sprite pixels the priority test REJECTS: pixels the sprite wanted
to draw and the scenery refused. A frame with zero rejections is not a candidate for an eye gate
however good it looks. ★ Ranked descending, and the count is printed so the choice is auditable
rather than a judgement call.

★ §2P: prints counts and frame numbers. No pixels.
"""
import argparse
import collections
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from comp_stage import W, H, draw_cel, load_cels  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("titles", nargs="+")
    ap.add_argument("--top", type=int, default=10)
    a = ap.parse_args()

    rows = []
    for t in a.titles:
        fdir = pathlib.Path("oracle/dumps/frames-" + t)
        cdir = pathlib.Path("build/cel_sweep") / t
        if not fdir.is_dir() or not (cdir / "cels.txt").exists():
            print("  %-14s no frames or no decoded cels -- skipped" % t)
            continue
        cels = load_cels(cdir)
        for spr in sorted(fdir.glob("frame*.sprites.txt")):
            n = spr.name[5:8]
            try:
                vis = bytearray((fdir / ("frame%s.before.visual.bin" % n)).read_bytes())
                pri = bytearray((fdir / ("frame%s.before.priority.bin" % n)).read_bytes())
                want_v = (fdir / ("frame%s.after.visual.bin" % n)).read_bytes()
                want_p = (fdir / ("frame%s.after.priority.bin" % n)).read_bytes()
            except FileNotFoundError:
                continue
            if len(vis) != W * H:
                continue
            sprites, ok = [], True
            for line in spr.read_text(errors="replace").splitlines():
                f = line.split()
                if len(f) < 11:
                    continue
                obj, view, loop, cel, x, y, prio, w, h, key, mir = (int(v) for v in f[:11])
                got = cels.get((view, loop, cel))
                if got is None:
                    ok = False
                    break
                sprites.append((x, y, prio, got))
            if not ok or not sprites:
                continue
            # ★★★ SCORED PER SPRITE, NOT PER FRAME, AND THE DIFFERENCE MATTERED. The first
            # version summed the counters over every sprite in the frame and ranked on the
            # total. SpaceQuest-1 frame 029 came top: 575 rejected, 564 written. But those are
            # DIFFERENT SPRITES -- one entirely hidden, one entirely in front. **No single
            # sprite in it is partly occluded**, which is the one thing the eye gate has to
            # show. A per-frame total cannot distinguish "half of a sprite is behind scenery"
            # from "one sprite is behind and another is in front", and only the first is a
            # demonstration of the priority test.
            # ★ So each sprite is drawn with its own counter and the frame's score is the BEST
            # single sprite's min(rejected, written).
            st = collections.Counter()
            best = 0
            for x, y, prio, (w, h, key, px) in sprites:
                one = collections.Counter()
                draw_cel(vis, pri, px, w, h, key, x, y, prio, one)
                st.update(one)
                best = max(best, min(one["rej_pri"], one["written"]))
            # ★ the model must reproduce the oracle or the frame is not a candidate
            if bytes(vis) != want_v or bytes(pri) != want_p:
                continue
            rows.append((best, st["rej_pri"], st["written"],
                         st["ctrl"], len(sprites), t, n))

    rows.sort(reverse=True)
    print("%-14s %6s %9s %10s %10s %8s %9s" %
          ("title", "frame", "BEST spr", "REJECTED", "written", "sprites", "control"))
    print("-" * 62)
    for sc, rej, wr, ctrl, ns, t, n in rows[:a.top]:
        print("%-14s %6s %9d %10d %10d %8d %9d" % (t, n, sc, rej, wr, ns, ctrl))
    print("-" * 62)
    z = sum(1 for r in rows if r[1] == 0)
    partial = sum(1 for r in rows if r[0] > 0)
    print("%d frames scored; %d show PARTIAL occlusion (both drawn and refused)"
          % (len(rows), partial))
    print("%d frames scored; %d have ZERO priority rejections (%.0f%%)"
          % (len(rows), z, 100.0 * z / max(1, len(rows))))
    if rows and rows[0][1] == 0:
        print("★★★ NO FRAME IN THIS WINDOW CONTAINS OCCLUSION -- that is the finding, and the")
        print("    ~45-second capture window is too short (§7.8).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
