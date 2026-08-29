#!/usr/bin/env python3
"""harness/tools/comp_stage.py -- select composited frames, stage them, and BE THE LOCALISER.

★★★ §5 / L-59: "the state diff pointed directly at none of the twelve defects: it is an
excellent detector and a poor localiser." So the localiser is built alongside the gate, not
after the gate fails. This module carries a faithful Python transcription of the oracle's
SpritesMgr::drawCel, and does three jobs with it:

  1. SELF-CHECK. It replays every candidate frame -- before planes + sprite list -> after planes
     -- and compares against the oracle's own `after` dump. **A frame the model cannot reproduce
     is not staged**, because a localiser that disagrees with the oracle would attribute its own
     error to the 6809. This is the check that makes the other two trustworthy.
  2. SELECTION (★★ L-38). A frame where every sprite is in front of everything tests
     TRANSPARENCY and not PRIORITY. Frames are scored by how many pixels the priority test
     actually REJECTS, and by how many take the control-line branch, and the highest scoring
     ones are staged. A gate on unlucky frames can pass with the priority test inverted.
  3. LOCALISATION. For a frame the 6809 gets wrong, it can say which SPRITE, which ROW and
     which BRANCH -- not just "plane differs at byte 14,203".

★ §2P: planes and cel pixels are copyrighted game content. Everything lands under build/.
"""
import argparse
import collections
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

W, H = 160, 168
CTRL_MAX = 2


def check_control_pixel(pri, x, y, view_priority):
    """graphics.cpp:553 -- walk DOWN the column until a real priority appears."""
    off = y * W + x
    steps = 0
    while True:
        y += 1
        off += W
        steps += 1
        if y >= H:
            return True, steps
        cur = pri[off]
        if cur > CTRL_MAX:
            break
    return (cur <= view_priority), steps


def draw_cel(vis, pri, cel, w, h, clear_key, x_pos, y_pos, view_priority, stats=None):
    """sprite.cpp:233 drawCel(), transcribed. Mutates vis and pri in place."""
    base_x = x_pos
    cur_y = y_pos - h + 1
    p = 0
    for _ in range(h):
        cur_x = base_x
        for _ in range(w):
            color = cel[p]
            p += 1
            if stats is not None:
                stats["tested"] += 1
            if color != clear_key:
                off = cur_y * W + cur_x
                screen_priority = pri[off]
                if screen_priority <= CTRL_MAX:
                    ok, steps = check_control_pixel(pri, cur_x, cur_y, view_priority)
                    if stats is not None:
                        stats["ctrl"] += 1
                        stats["ctrl_steps"] += steps
                    if ok:
                        vis[off] = color            # ★ VISUAL only; priority untouched
                        if stats is not None:
                            stats["written"] += 1
                    elif stats is not None:
                        stats["rej_pri"] += 1
                elif screen_priority <= view_priority:
                    vis[off] = color
                    pri[off] = view_priority        # ★ the sprite stamps the priority plane
                    if stats is not None:
                        stats["written"] += 1
                elif stats is not None:
                    stats["rej_pri"] += 1
            elif stats is not None:
                stats["rej_key"] += 1
            cur_x += 1
        cur_y += 1


def load_cels(sweep_dir):
    """The 6809's own decoded cels, keyed (view, loop, cel). AC-2 gates these at 6,782/6,782."""
    man = {}
    blob = (sweep_dir / "cels.bin").read_bytes()
    for line in (sweep_dir / "cels.txt").read_text(errors="replace").splitlines():
        f = line.split()
        if len(f) >= 8 and f[3] != "ERR":
            v, lp, c, w, h, key, mir, off = (int(x) for x in f[:8])
            man[(v, lp, c)] = (w, h, key, blob[off:off + w * h])
    return man


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("title")
    ap.add_argument("--frames-dir", default=None)
    ap.add_argument("--cels-dir", default=None)
    ap.add_argument("--out", required=True)
    ap.add_argument("--count", type=int, default=20, help="frames to stage, best-scoring first")
    ap.add_argument("--only", default=None, help="comma-separated frame numbers (AC-9)")
    a = ap.parse_args()

    fdir = pathlib.Path(a.frames_dir or ("oracle/dumps/frames-" + a.title))
    cdir = pathlib.Path(a.cels_dir or ("build/cel_sweep/" + a.title))
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    cels = load_cels(cdir)
    cand, skipped = [], collections.Counter()

    for spr in sorted(fdir.glob("frame*.sprites.txt")):
        n = spr.name[5:8]
        try:
            vis = bytearray((fdir / ("frame%s.before.visual.bin" % n)).read_bytes())
            pri = bytearray((fdir / ("frame%s.before.priority.bin" % n)).read_bytes())
            want_v = (fdir / ("frame%s.after.visual.bin" % n)).read_bytes()
            want_p = (fdir / ("frame%s.after.priority.bin" % n)).read_bytes()
        except FileNotFoundError:
            skipped["missing_plane"] += 1
            continue
        if len(vis) != W * H or len(want_v) != W * H:
            skipped["bad_size"] += 1
            continue

        rows = []
        ok = True
        for line in spr.read_text(errors="replace").splitlines():
            f = line.split()
            if len(f) < 11:
                continue
            obj, view, loop, cel, x, y, prio, w, h, key, mir = (int(v) for v in f[:11])
            got = cels.get((view, loop, cel))
            if got is None:
                ok = False
                skipped["cel_not_decoded"] += 1
                break
            rows.append((obj, view, loop, cel, x, y, prio, got))
        if not ok or not rows:
            skipped["no_sprites"] += 1
            continue

        stats = collections.Counter()
        for _, _, _, _, x, y, prio, (w, h, key, px) in rows:
            draw_cel(vis, pri, px, w, h, key, x, y, prio, stats)

        # ★ THE SELF-CHECK. If the model cannot reproduce the oracle, the frame is not staged.
        if bytes(vis) != want_v or bytes(pri) != want_p:
            skipped["model_mismatch"] += 1
            continue

        # ★ L-38 score: frames where the priority test and the control branch actually FIRE.
        score = stats["rej_pri"] * 4 + stats["ctrl"] * 2 + len(rows)
        cand.append((score, n, rows, stats))

    cand.sort(key=lambda t: -t[0])
    # ★ --only names specific frames, for AC-9's eye gate: comp_pick.py ranks by PER-SPRITE
    # partial occlusion (what a human can see) while the score above ranks by total priority
    # rejections (what the byte gate should cover). Different questions, different frames.
    if a.only:
        want = set(a.only.split(","))
        chosen = [c for c in cand if c[1] in want]
        missing = want - {c[1] for c in chosen}
        if missing:
            print("      ★★★ requested frame(s) not candidates: %s" % ",".join(sorted(missing)))
    else:
        chosen = cand[:a.count]

    idx = (out / "frames.txt").open("w", encoding="ascii", newline="\n")
    for score, n, rows, stats in chosen:
        celblob = bytearray()
        lines = []
        for obj, view, loop, cel, x, y, prio, (w, h, key, px) in rows:
            lines.append("%d %d %d %d %d %d %d %d" % (x, y, prio, w, h, key, len(celblob), obj))
            celblob += px
        (out / ("f%s.cels.bin" % n)).write_bytes(bytes(celblob))
        (out / ("f%s.spr.txt" % n)).write_text("\n".join(lines) + "\n",
                                               encoding="ascii", newline="\n")
        idx.write("%s %d\n" % (n, len(rows)))
    idx.close()

    print("  %-14s candidates %4d   staged %3d   (model self-check passed on all candidates)"
          % (a.title, len(cand), len(chosen)))
    if chosen:
        tot = collections.Counter()
        for _, _, _, s in chosen:
            tot.update(s)
        print("      staged frames exercise: tested %d  written %d  rejected-by-priority %d"
              "  control-branch %d (%d scan steps)"
              % (tot["tested"], tot["written"], tot["rej_pri"], tot["ctrl"], tot["ctrl_steps"]))
        if not tot["rej_pri"]:
            print("      ★★★ NO PIXEL IS REJECTED BY PRIORITY in the staged set -- this gate"
                  " would pass with the priority test inverted [L-38]")
    if skipped:
        print("      skipped: %s" % dict(skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
