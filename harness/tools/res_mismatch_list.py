#!/usr/bin/env python3
"""harness/tools/res_mismatch_list.py -- itemise WHICH resources mismatch, per arm.

★★★★ WHY: the aggregate says "28 mismatched" and that is not a lead. The dispatch's question is
which LOGICs, in which titles, and which of them survive eviction being compiled out -- because
the nine that survive -DABL_NOEVICT cannot be an eviction, starvation or lifecycle bug. They are
the cache's core behaviour being wrong, and they have the fewest moving parts.

★★★ It prints the SET INTERSECTION across arms, which is the actual instrument: a resource that
mismatches in both the eviction arm and the no-evict arm is eviction-independent by construction.

usage:  python harness/tools/res_mismatch_list.py --sweep build/res_sweep_evict [--label evict]
        python harness/tools/res_mismatch_list.py --compare build/res_sweep_evict build/res_sweep
"""
import argparse
import io
import pathlib
import re
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

PINNED = ["Kingquest1-v0", "Kingquest1-v1", "Kingquest1-v2",
          "Kingquest2-v0", "Kingquest2-v1", "Kingquest2-v2",
          "Kingquest3-v0", "Kingquest3-v1", "Kingquest3-v2", "Kingquest3-v3"]

# res_gate.py's per-failure line:  "  ! LOGIC     6  5060 bytes, first difference at +1725"
FAIL = re.compile(r"!\s+(\w+)\s+(\d+)\s+(\d+) bytes, first difference at \+(\d+)")


def collect(sweep, games="C:/Projects/agi-games/pc"):
    """{(volume, type, index): (length, first_diff)} for one arm."""
    out = {}
    for tag in PINNED:
        d = ROOT / sweep / tag
        if not d.exists():
            continue
        game = re.sub(r"-v\d+$", "", tag)
        r = subprocess.run([sys.executable, str(ROOT / "harness" / "tools" / "res_gate.py"),
                            f"{games}/{game}", "--sweep", str(d)],
                           cwd=ROOT, capture_output=True, text=True)
        for m in FAIL.finditer(r.stdout + r.stderr):
            out[(tag, m.group(1), int(m.group(2)))] = (int(m.group(3)), int(m.group(4)))
    return out


def show(label, s):
    print(f"── {label}: {len(s)} mismatches ──")
    print(f"{'volume':<16} {'type':<8} {'idx':>5} {'len':>7} {'firstdiff':>10} {'diff/len':>9}")
    for k in sorted(s):
        ln, off = s[k]
        print(f"{k[0]:<16} {k[1]:<8} {k[2]:>5} {ln:>7} {off:>10} {off / ln:>9.3f}")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep")
    ap.add_argument("--label", default="arm")
    ap.add_argument("--compare", nargs=2, metavar=("EVICT_ARM", "NOEVICT_ARM"))
    a = ap.parse_args()

    if a.compare:
        ev, ne = collect(a.compare[0]), collect(a.compare[1])
        show(f"A: {a.compare[0]} (cache on, eviction on)", ev)
        show(f"B: {a.compare[1]} (cache on, eviction COMPILED OUT)", ne)
        both = set(ev) & set(ne)
        onlya = set(ev) - set(ne)
        print(f"★★★ IN BOTH ({len(both)}) -- eviction-independent, the cache's core behaviour:")
        for k in sorted(both):
            print(f"    {k[0]:<16} {k[1]} {k[2]:<5} len={ev[k][0]:<6} diff@+{ev[k][1]}")
        print()
        print(f"★★ ONLY IN THE EVICTION ARM ({len(onlya)}):")
        for k in sorted(onlya):
            print(f"    {k[0]:<16} {k[1]} {k[2]:<5} len={ev[k][0]:<6} diff@+{ev[k][1]}")
        # ★ B minus A matters too: a resource that mismatches ONLY without eviction is one the
        # no-evict arm never reached in the eviction arm (it starved first), not a second defect.
        onlyb = set(ne) - set(ev)
        print()
        print(f"★ ONLY IN THE NO-EVICT ARM ({len(onlyb)}) -- note that arm halts early, so absence "
              f"from A can mean 'not reached', not 'correct':")
        for k in sorted(onlyb):
            print(f"    {k[0]:<16} {k[1]} {k[2]:<5} len={ne[k][0]:<6} diff@+{ne[k][1]}")
        return 0

    show(a.label, collect(a.sweep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
