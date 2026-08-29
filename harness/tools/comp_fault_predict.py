#!/usr/bin/env python3
"""harness/tools/comp_fault_predict.py -- AC-4: predict where the injected fault must show.

★★★ A GATE THAT FAILS SOMEWHERE IS WEAKER EVIDENCE THAN A GATE THAT FAILS WHERE THE MODEL SAID.
-DCOMP_FAULT changes the depth test from `screenPriority <= viewPriority` to `<`, so exactly
the pixels at EQUAL priority stop being drawn. This replays each staged frame twice with the
localiser's model -- once correct, once faulted -- and reports, per frame, how many bytes must
differ and the row and column of the first one. comp_sweep.lua then runs the faulted 6809 and
the two are compared.

★ If a frame is predicted to be UNAFFECTED, that is reported too: a fault that changes nothing
on some frames is the normal case, and a gate whose staged set happens to contain only those
frames would pass a faulted build [L-38 again, one level up].
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from comp_stage import W, H, CTRL_MAX, check_control_pixel, load_cels  # noqa: E402


def draw_cel_faulted(vis, pri, cel, w, h, clear_key, x_pos, y_pos, view_priority):
    """The same walk with the depth test's boundary moved by one -- see composite.s."""
    base_x = x_pos
    cur_y = y_pos - h + 1
    p = 0
    for _ in range(h):
        cur_x = base_x
        for _ in range(w):
            color = cel[p]
            p += 1
            if color != clear_key:
                off = cur_y * W + cur_x
                sp = pri[off]
                if sp <= CTRL_MAX:
                    ok, _ = check_control_pixel(pri, cur_x, cur_y, view_priority)
                    if ok:
                        vis[off] = color
                elif sp < view_priority:            # ★ INJECTED: `<=` in the correct model
                    vis[off] = color
                    pri[off] = view_priority
            cur_x += 1
        cur_y += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("title")
    ap.add_argument("--stage", default=None)
    ap.add_argument("--frames-dir", default=None)
    a = ap.parse_args()

    stage = pathlib.Path(a.stage or ("build/comp_stage/" + a.title))
    fdir = pathlib.Path(a.frames_dir or ("oracle/dumps/frames-" + a.title))
    cels = load_cels(pathlib.Path("build/cel_sweep") / a.title)

    total_bad, affected, unaffected = 0, 0, 0
    print("%-8s %9s %9s  %s" % ("frame", "bytes", "first", "location"))
    print("-" * 52)
    for line in (stage / "frames.txt").read_text().splitlines():
        n = line.split()[0]
        vis = bytearray((fdir / ("frame%s.before.visual.bin" % n)).read_bytes())
        pri = bytearray((fdir / ("frame%s.before.priority.bin" % n)).read_bytes())
        want_v = (fdir / ("frame%s.after.visual.bin" % n)).read_bytes()
        want_p = (fdir / ("frame%s.after.priority.bin" % n)).read_bytes()
        for sl in (stage / ("f%s.spr.txt" % n)).read_text().splitlines():
            t = [int(v) for v in sl.split()]
            if len(t) < 8:
                continue
            x, y, prio, w, h, key, off, obj = t[:8]
            blob = (stage / ("f%s.cels.bin" % n)).read_bytes()
            draw_cel_faulted(vis, pri, blob[off:off + w * h], w, h, key, x, y, prio)

        bad, first = 0, -1
        for i in range(W * H):
            if vis[i] != want_v[i]:
                bad += 1
                if first < 0:
                    first, plane = i, "visual"
        for i in range(W * H):
            if pri[i] != want_p[i]:
                bad += 1
                if first < 0:
                    first, plane = i, "priority"
        total_bad += bad
        if bad:
            affected += 1
            print("%-8s %9d %9d  %s row %d col %d"
                  % (n, bad, first, plane, first // W, first % W))
        else:
            unaffected += 1
            print("%-8s %9d %9s  ★ UNAFFECTED by the fault" % (n, 0, "-"))
    print("-" * 52)
    print("%d frame(s) must differ, %d must not; %d bytes total"
          % (affected, unaffected, total_bad))
    if not affected:
        print("★★★ THE FAULT CHANGES NOTHING ON THIS STAGED SET -- the gate cannot detect it here")
    return 0


if __name__ == "__main__":
    sys.exit(main())
