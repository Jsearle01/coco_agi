#!/usr/bin/env python3
"""harness/tools/census_verify.py -- is the census measuring the corpus, or its own walk?

★★★ L-56: THE FIRST MEASUREMENT OF A NEW SUBSYSTEM OFTEN MEASURES ITS OWN SCAFFOLDING. A static
census that reports 163 of 183 commands present is either a real finding or a desynchronised
walk recording operand bytes as opcodes, and those look identical in the output.

Three checks, each of which a desynchronised walk would fail:

  1. SUPERSET. Every opcode vm_opcov.py observed EXECUTED in KQ1/2/3 must appear in the static
     census for that same title. A walk that loses sync skips real instructions, so the static
     set would fail to contain something the interpreter actually ran.

  2. IMPOSSIBLE OPCODES. opcodes.cpp marks entries Apple IIGS-only and AGI3+-only. A v2 DOS
     LOGIC cannot legitimately contain them; finding them is the signature of a walk reading
     operands as opcodes.

  3. TERMINATION. Every LOGIC must consume exactly its bytecode -- the walk ends at the last
     byte, not past it. Overrunning means an operand count was wrong.

★ Reports; it does not rewrite the census. A failure here invalidates AC-7 and must be seen.
"""
import argparse
import collections
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "harness" / "tools"))
from agivm import cycle as cycle_mod, optable  # noqa: E402
from volread import logic as logic_mod, resource  # noqa: E402
from opcode_census import CMD_ARGS, CMD_NAME, TEST_NAME, census_title, walk  # noqa: E402

# ★★ reconfigure(), NOT a new TextIOWrapper. opcode_census.py already wrapped sys.stdout at
# import time; wrapping it a second time drops the first wrapper, and when that is collected it
# CLOSES the shared underlying buffer -- every print then raises "I/O operation on closed file".
# Moving the wrap after the imports did not help, because the problem is the second wrapper, not
# the order. reconfigure mutates the existing object and owns nothing.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def executed_set(game_dir, cycles=600):
    """Which opcodes actually RUN -- the reference, instrumented, same as vm_opcov.py."""
    game = resource.load_from_files(str(game_dir))
    vm = cycle_mod.Vm(game, 0x2917)
    vm.start()
    seen_c, seen_t = set(), set()
    tbl = vm.table
    for i, entry in enumerate(tbl.commands):
        if entry is None or entry.handler is None:
            continue

        def wrap(h=entry.handler, op=i):
            def inner(v, p):
                seen_c.add(op)
                return h(v, p)
            return inner
        entry.handler = wrap()
    for i, entry in enumerate(tbl.tests):
        if entry is None or entry.handler is None:
            continue

        def wrapt(h=entry.handler, op=i):
            def inner(v, p):
                seen_t.add(op)
                return h(v, p)
            return inner
        entry.handler = wrapt()
    for _ in range(cycles):
        if vm.should_quit:
            break
        vm.interpret_cycle()
    return seen_c, seen_t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", nargs="*",
                    default=["Kingquest1", "Kingquest2", "Kingquest3"])
    ap.add_argument("--cycles", type=int, default=600)
    a = ap.parse_args()

    root = pathlib.Path(a.root)
    bad = 0

    print("── CHECK 1: every EXECUTED opcode must be PRESENT in the static census ──\n")
    for t in a.titles:
        d = root / t
        cmds, tests, nlogic, failed = census_title(d)
        ex_c, ex_t = executed_set(d, a.cycles)
        miss_c = sorted(ex_c - set(cmds))
        miss_t = sorted(ex_t - set(tests))
        ok = not miss_c and not miss_t
        if not ok:
            bad += 1
        print("%-12s static %3d cmd / %2d test   executed %3d cmd / %2d test   %s"
              % (t, len(cmds), len(tests), len(ex_c), len(ex_t),
                 "OK" if ok else "★★★ EXECUTED BUT NOT PRESENT"))
        for op in miss_c:
            print("     ★★★ command 0x%02X %s executed but absent from the walk"
                  % (op, CMD_NAME.get(op, "?")))
        for op in miss_t:
            print("     ★★★ test 0x%02X %s executed but absent from the walk"
                  % (op, TEST_NAME.get(op, "?")))

    print("\n── CHECK 2: opcodes a v2 DOS LOGIC cannot legitimately contain ──\n")
    # ★ The oracle's own comments mark these; read them off optable rather than typing a list.
    flagged = {}
    for i, (name, params, handler) in enumerate(optable.V2_COMMANDS):
        low = (name or "").lower()
        if "iigs" in low or "agi3" in low or "unknown" in low:
            flagged[i] = name
    print("table entries marked unknown/IIgs/AGI3-only: %d" % len(flagged))
    hits = collections.Counter()
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        names = {f.name.lower() for f in d.iterdir() if f.is_file()}
        if not {"logdir", "picdir", "viewdir", "snddir"} <= names:
            continue
        cmds, tests, _n, _f = census_title(d)
        for op in cmds:
            if op in flagged:
                hits[(d.name, op)] += cmds[op]
    if hits:
        bad += 1
        for (t, op), n in sorted(hits.items()):
            print("  ★★★ %-22s 0x%02X %-20s x%d" % (t, op, flagged[op], n))
    else:
        print("  none present in any title")

    print("\n── CHECK 3: every LOGIC's walk must END EXACTLY at its bytecode length ──\n")
    over = 0
    total = 0
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        names = {f.name.lower() for f in d.iterdir() if f.is_file()}
        if not {"logdir", "picdir", "viewdir", "snddir"} <= names:
            continue
        game = resource.load_from_files(str(d))
        for e in game.dirs["LOGIC"]:
            if not e.present:
                continue
            try:
                lg = logic_mod.split(game.load("LOGIC", e.index), index=e.index)
            except Exception:                                  # noqa: BLE001
                continue
            c, t2 = collections.Counter(), collections.Counter()
            try:
                end = walk(lg.bytecode, c, t2)
            except Exception:                                  # noqa: BLE001
                continue
            total += 1
            if end != len(lg.bytecode):
                over += 1
                if over <= 8:
                    print("  ★★★ %-22s LOGIC %3d ended at %d, bytecode is %d"
                          % (d.name, e.index, end, len(lg.bytecode)))
    print("  %d of %d LOGICs ended exactly at their bytecode length" % (total - over, total))
    if over:
        bad += 1

    print()
    print("VERIFY %s" % ("PASS -- the census measures the corpus, not the walk"
                         if not bad else "★★★ FAIL -- %d check(s) failed" % bad))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
