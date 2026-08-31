#!/usr/bin/env python3
"""harness/tools/res_aggregate.py -- roll res_gate.py up across the ten pinned volumes.

★★★★ WHY THIS IS A FILE. res_run.ps1 prints a per-volume block and the aggregate lived only in
whoever was reading the scrollback -- so "1,264/1,264 clean" was a number nobody could recompute
without re-running ten MAME launches. **The gate's headline figure had no producer.** That is the
same L-45 defect the rest of this task is about, one level up: not an unrecorded COMMAND but an
unrecorded SUM.

★★★ It also makes the sweep dir the unit of record. build/res_sweep/ accumulates scratch dirs from
past experiments (dangle, fastclk, stack, cen-*, f_*, t-*, t2-*); aggregating over `*` silently
mixes them into the total. The pinned set is the ten (title, volume) pairs and nothing else.

usage:  python harness/tools/res_aggregate.py [--sweep build/res_sweep] [--games <dir>]
"""
import argparse
import io
import pathlib
import re
import subprocess
import sys

# ★ cp1252 is the default console codec here and the star glyphs are not in it; without this the
# script computes the whole aggregate correctly and then dies on the last print.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

# ★ The pinned set (2Q): three titles, their volumes. Explicit, because a glob is what let the
# scratch dirs in.
PINNED = ["Kingquest1-v0", "Kingquest1-v1", "Kingquest1-v2",
          "Kingquest2-v0", "Kingquest2-v1", "Kingquest2-v2",
          "Kingquest3-v0", "Kingquest3-v1", "Kingquest3-v2", "Kingquest3-v3"]

IDENT = re.compile(r"byte-identical vs tools/volread/ *: *(\d+)")
MISM = re.compile(r"mismatched *: *(\d+)")
FAIL = re.compile(r"guest-reported failures: *(\d+)")
REQ = re.compile(r"requests *: *(\d+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep", default="build/res_sweep")
    ap.add_argument("--games", default="C:/Projects/agi-games/pc")
    a = ap.parse_args()

    tot = {"req": 0, "ident": 0, "mism": 0, "fail": 0}
    bad = []
    print("%-20s %8s %10s %8s %10s" % ("volume", "requests", "identical", "mismat", "guestfail"))
    print("-" * 62)
    for tag in PINNED:
        d = ROOT / a.sweep / tag
        if not d.exists():
            print("%-20s  MISSING sweep -- not run" % tag)
            bad.append(tag)
            continue
        game = re.sub(r"-v\d+$", "", tag)
        r = subprocess.run([sys.executable, str(ROOT / "harness" / "tools" / "res_gate.py"),
                            f"{a.games}/{game}", "--sweep", str(d)],
                           cwd=ROOT, capture_output=True, text=True)
        o = r.stdout + r.stderr

        def g(rx):
            m = rx.search(o)
            return int(m.group(1)) if m else 0

        req, ident, mism, fail = g(REQ), g(IDENT), g(MISM), g(FAIL)
        tot["req"] += req; tot["ident"] += ident; tot["mism"] += mism; tot["fail"] += fail
        if mism or fail:
            bad.append(tag)
        print("%-20s %8d %10d %8d %10d" % (tag, req, ident, mism, fail))

    print("-" * 62)
    print("%-20s %8d %10d %8d %10d" % ("TOTAL", tot["req"], tot["ident"], tot["mism"], tot["fail"]))
    pct = 100.0 * tot["ident"] / tot["req"] if tot["req"] else 0.0
    print()
    print("resources byte-identical to tools/volread/: %d / %d requested (%.2f%%)"
          % (tot["ident"], tot["req"], pct))
    if bad:
        print("★★★ volumes with mismatches or guest failures: %s" % " ".join(bad))
    return 1 if (tot["mism"] or tot["fail"] or len(bad)) else 0


if __name__ == "__main__":
    sys.exit(main())
