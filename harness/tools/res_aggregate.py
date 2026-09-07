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


def expected_requests(stage_root, tag):
    """How many fetches the STAGER asked for, from its own request list.

    ★★★★★ THE PINNED LIST PROTECTS THE SET; NOTHING PROTECTED THE COUNT [T-P0-061 AC-2].
    This script iterated the ten pinned volumes -- which stops a glob dragging in scratch dirs --
    and then reported whatever each sweep happened to contain. A sweep that fetched 74 of its 132
    resources reports `ident == req` and prints 100.00%, because both numbers come from the same
    truncated run. **The total drops and the percentage does not**, and the percentage is the
    line people read.

    ★★★★ THAT IS THE SHAPE THAT LET THE RENDERER GATE REPORT "45 PASS ... (of 45)" ON EIGHT
    PICTURES, one task ago. picgate.py was immune because it drives from a REQUIRED set; this
    had a required set of VOLUMES and no required set of FETCHES.

    ★★★ THE PRODUCER IS res_stage.py's requests.txt, not a constant. 1,264 is the corpus's
    current total and hard-coding it would be a number with no producer -- the cel gate's 6,782
    fossil, which was wrong for a task because a title was staged after the figure was written.
    One producer (the stager), two consumers (the guest, and this).
    ★★ Returns None when the stage directory is absent, which is reported rather than defaulted:
    "I cannot check this" and "this is fine" are different answers [§2W].
    """
    p = ROOT / stage_root / tag / "requests.txt"
    if not p.exists():
        return None
    return sum(1 for ln in p.read_text(encoding="ascii").splitlines() if ln.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep", default="build/res_sweep")
    ap.add_argument("--stage", default="build/res_stage",
                    help="where res_stage.py wrote requests.txt -- the expected-count producer")
    ap.add_argument("--games", default="C:/Projects/agi-games/pc")
    a = ap.parse_args()

    tot = {"req": 0, "ident": 0, "mism": 0, "fail": 0, "want": 0}
    bad = []
    short = []
    unchecked = []
    print("%-20s %8s %8s %10s %8s %10s"
          % ("volume", "expected", "requests", "identical", "mismat", "guestfail"))
    print("-" * 72)
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
        want = expected_requests(a.stage, tag)
        tot["req"] += req; tot["ident"] += ident; tot["mism"] += mism; tot["fail"] += fail
        if want is None:
            unchecked.append(tag)
            wtxt = "?"
        else:
            tot["want"] += want
            wtxt = str(want)
            # ★★★ THE ASSERTION. A sweep that fetched fewer than the stager asked for is a
            # TRUNCATED run, and it is invisible in the percentage because both sides of the
            # ratio shrink together.
            if req != want:
                short.append((tag, req, want))
        if mism or fail:
            bad.append(tag)
        print("%-20s %8s %8d %10d %8d %10d" % (tag, wtxt, req, ident, mism, fail))

    print("-" * 72)
    print("%-20s %8d %8d %10d %8d %10d"
          % ("TOTAL", tot["want"], tot["req"], tot["ident"], tot["mism"], tot["fail"]))
    pct = 100.0 * tot["ident"] / tot["req"] if tot["req"] else 0.0
    print()
    print("resources byte-identical to tools/volread/: %d / %d requested (%.2f%%)"
          % (tot["ident"], tot["req"], pct))
    # ★★★★ AND THE COUNT, BESIDE THE PERCENTAGE, because the percentage cannot express this.
    print("fetches requested vs STAGED-FOR: %d / %d%s"
          % (tot["req"], tot["want"],
             "" if not short else "   ★★★ SHORT -- this run did not fetch what it was staged for"))
    for tag, req, want in short:
        print("    ★★★ %-20s fetched %d of %d -- the sweep was cut short or the stage moved"
              % (tag, req, want))
    if unchecked:
        print("★★★ NO requests.txt for: %s" % " ".join(unchecked))
        print("    The expected count has no producer for those volumes. Re-run res_stage.py;")
        print("    an unchecked count is not a passing count [§2W].")
    if bad:
        print("★★★ volumes with mismatches or guest failures: %s" % " ".join(bad))
    return 1 if (tot["mism"] or tot["fail"] or bad or short or unchecked) else 0


if __name__ == "__main__":
    sys.exit(main())
