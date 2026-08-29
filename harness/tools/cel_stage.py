#!/usr/bin/env python3
"""harness/tools/cel_stage.py -- stage VIEW resources and a work list for cel_sweep.lua.

★★ THE WORK LIST COMES FROM THE ORACLE'S OWN MANIFEST, not from our idea of which cels exist.
oracle/dumps/cels-<title>/cels.txt records every (view, loop, cel) the instrumented oracle
decoded, in the order it decoded them, with the width/height/clearKey/mirrored it produced. The
6809 is asked for exactly that set, so "we decoded 814 cels and they all matched" cannot quietly
mean "we decoded the 700 easy ones".

★ §2P: VIEW resources are copyrighted game content. Everything written here lands under build/,
which is not tracked, and the report carries counts and hashes only.
"""
import argparse
import collections
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from volread import resource  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--dump", required=True, help="oracle/dumps/cels-<title>")
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-view", type=int, default=8192,
                    help="CP_VIEW window; a larger VIEW is reported, never truncated")
    a = ap.parse_args()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    game = resource.load_from_files(a.game_dir)

    manifest = pathlib.Path(a.dump) / "cels.txt"
    rows = []
    for line in manifest.read_text(errors="replace").splitlines():
        f = line.split()
        if len(f) >= 8:
            rows.append(tuple(int(x) for x in f[:8]))   # view loop cel w h key mirrored offset

    views = sorted({r[0] for r in rows})
    staged, skipped = [], []
    for vn in views:
        try:
            data = game.load("VIEW", vn)
        except Exception as e:                                   # noqa: BLE001
            skipped.append((vn, str(e)[:40]))
            continue
        if len(data) > a.max_view:
            # ★ REPORTED, not truncated. A silently clipped resource decodes to plausible
            # garbage and the gate would attribute it to the decoder.
            skipped.append((vn, "%d bytes > CP_VIEW window" % len(data)))
            continue
        (out / ("view%03d.bin" % vn)).write_bytes(data)
        staged.append((vn, len(data)))

    ok = {v for v, _ in staged}
    work = [r for r in rows if r[0] in ok]
    # ★★★ INTERLEAVED: each `view` line is immediately followed by ITS cels. The first version
    # emitted every view line and then every cel line, so the guest decoded all 814 cels against
    # whichever VIEW happened to be staged last -- and reported a constant 8x33 header for every
    # one of them. The symptom looked exactly like a broken 6809 header parse; the parse was
    # right and it was being handed the wrong resource.
    # ★ The sweep relies on this ordering, so it is stated here rather than assumed there.
    bylen = dict(staged)
    order = collections.OrderedDict()
    for r in work:
        order.setdefault(r[0], []).append(r)
    with (out / "work.txt").open("w", encoding="ascii", newline="\n") as f:
        for vn, cels in order.items():
            f.write("view %d %d\n" % (vn, bylen[vn]))
            for r in cels:
                f.write("cel %d %d %d\n" % (r[0], r[1], r[2]))

    print("  %-14s views staged %3d   cels queued %5d   largest VIEW %5d B"
          % (pathlib.Path(a.game_dir).name, len(staged), len(work),
             max((n for _, n in staged), default=0)))
    if skipped:
        print("      ★ %d view(s) NOT staged:" % len(skipped))
        for vn, why in skipped[:6]:
            print("          view %-4d %s" % (vn, why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
