#!/usr/bin/env python3
"""harness/tools/comp_overlay.py -- AC-9: show the DECISION, not just the depth map.

★★★ WHY THE PRIORITY IMAGE ALONE WAS NOT ENOUGH. It renders the priority screen after
compositing, which is the depth map the sprite was tested against -- correct, and nearly
illegible for the question being asked. On the chosen frame the sprite is 297 pixels of 26,880
(1.1%), and the 620 pixels where the priority test REFUSED it are not in the image at all,
because refusing means nothing was drawn. **The one thing the eye gate exists to show is the
part the picture cannot contain.**

★★ So this renders the OUTCOME of every sprite pixel, over a dimmed depth map:

    GREEN   drawn      -- the priority test allowed it (scenery is behind)
    RED     refused    -- the priority test rejected it (scenery is in front)
    (none)  transparent -- the cel's clear key; not a decision

★ The boundary between green and red IS the occlusion edge. If the priority test were inverted,
green and red would swap -- which is visible instantly and is exactly what AC-4 showed a byte
gate can miss on two of five titles.

★★ §2P. This is a two-colour DECISION MASK plus our own band map: it carries the sprite's
silhouette but none of its art -- no game colours, no cel pixels. That sits inside Jay's ruling
that the priority visualisation is ours (the depth map is more game-derived than this is), but
it is a step further, so it is stated here rather than assumed. The composited frames themselves
remain game content and stay in build/.

★★★ §3: this tool WRITES an image and never reads one. Every number it prints comes from the
plane buffers and the cel, not from a rendered PNG.
"""
import argparse
import collections
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from comp_stage import W, H, CTRL_MAX, check_control_pixel, load_cels   # noqa: E402
from comp_render import write_png, SCALE                                # noqa: E402

DRAWN = (0x00, 0xF0, 0x30)
REFUSED = (0xF0, 0x10, 0x10)
CONTROL = (0xFF, 0xC0, 0x00)


def band_grey(v):
    """The depth map, dimmed to a grey ramp so the overlay reads on top of it.

    ★ Nearer is lighter. Deliberately monochrome: any second hue here would compete with the
    green/red decision, which is the thing being looked at.
    """
    g = 24 + int(v * 8)
    return (g, g, g + 8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", required=True)
    ap.add_argument("--frame", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--sprite", type=int, default=None,
                    help="index into the frame's sprite list; default = every sprite")
    a = ap.parse_args()

    fdir = pathlib.Path("oracle/dumps/frames-" + a.title)
    cels = load_cels(pathlib.Path("build/cel_sweep") / a.title)

    vis = bytearray((fdir / ("frame%s.before.visual.bin" % a.frame)).read_bytes())
    pri = bytearray((fdir / ("frame%s.before.priority.bin" % a.frame)).read_bytes())
    before_pri = bytes(pri)

    sprites = []
    for line in (fdir / ("frame%s.sprites.txt" % a.frame)).read_text().splitlines():
        f = line.split()
        if len(f) < 11:
            continue
        obj, view, loop, cel, x, y, prio, w, h, key, mir = (int(v) for v in f[:11])
        got = cels.get((view, loop, cel))
        if got is not None:
            sprites.append((obj, x, y, prio, got))

    # outcome[offset] = 1 drawn, 2 refused, 3 control-branch drawn
    outcome = bytearray(W * H)
    stats = collections.Counter()
    box = {}

    for idx, (obj, x_pos, y_pos, view_priority, (w, h, key, cel)) in enumerate(sprites):
        if a.sprite is not None and idx != a.sprite:
            # still draw it, so the plane state is right for later sprites, but do not mark it
            mark = False
        else:
            mark = True
        cur_y = y_pos - h + 1
        p = 0
        xs, ys = [], []
        for _ in range(h):
            cur_x = x_pos
            for _ in range(w):
                color = cel[p]
                p += 1
                if color != key:
                    off = cur_y * W + cur_x
                    sp = pri[off]
                    if sp <= CTRL_MAX:
                        ok, _st = check_control_pixel(pri, cur_x, cur_y, view_priority)
                        if ok:
                            vis[off] = color
                            if mark:
                                outcome[off] = 3
                                stats["control"] += 1
                        elif mark:
                            outcome[off] = 2
                            stats["refused"] += 1
                    elif sp <= view_priority:
                        vis[off] = color
                        pri[off] = view_priority
                        if mark:
                            outcome[off] = 1
                            stats["drawn"] += 1
                    elif mark:
                        outcome[off] = 2
                        stats["refused"] += 1
                    if mark:
                        xs.append(cur_x)
                        ys.append(cur_y)
                cur_x += 1
            cur_y += 1
        if mark and xs:
            box[idx] = (min(xs), min(ys), max(xs), max(ys), obj, view_priority)

    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(W):
            o = outcome[y * W + x]
            if o == 1:
                c = DRAWN
            elif o == 2:
                c = REFUSED
            elif o == 3:
                c = CONTROL
            else:
                c = band_grey(before_pri[y * W + x] & 0x0F)
            row += bytes(c) * SCALE
        for _ in range(SCALE):
            rows.append(row)
    write_png(a.out, W * SCALE, H * SCALE, rows)

    print("frame %s of %s -- sprite outcome overlay" % (a.frame, a.title))
    print("  GREEN  drawn   : %5d   the priority test ALLOWED it (scenery behind)" % stats["drawn"])
    print("  RED    refused : %5d   the priority test REFUSED it (scenery in front)"
          % stats["refused"])
    if stats["control"]:
        print("  AMBER  control : %5d   drawn via the control-line branch" % stats["control"])
    print("  grey background: the depth map BEFORE compositing, nearer = lighter")
    print()
    for idx, (x0, y0, x1, y1, obj, prio) in box.items():
        print("  sprite %d (object %d, priority %d): rows %d-%d, columns %d-%d"
              % (idx, obj, prio, y0, y1, x0, x1))
    print()
    print("  ★ the GREEN/RED boundary is the occlusion edge. An inverted priority test swaps")
    print("    the two colours, which is what a byte gate can miss (AC-4).")
    print("  -> %s" % a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
