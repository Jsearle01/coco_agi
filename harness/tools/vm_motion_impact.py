#!/usr/bin/env python3
"""harness/tools/vm_motion_impact.py -- is motion observable to AC-2's state diff?

★★★ THE QUESTION, AND WHY IT IS ASKED BEFORE ANY 6809 IS WRITTEN. T-P0-025 puts motion out of
scope, and AC-2 requires 256 vars + 256 flags byte-identical against tools/agivm every cycle
with an EMPTY exclusion set. But interpret_cycle() calls motion.check_all_motions() BEFORE
running logic.0, and get.posn -- 3,625 executions in the gated set -- copies object x/y into
variables. If motion moves an object that a logic then reads back, the move reaches the diff.

★★ SO THE TWO REQUIREMENTS MAY BE INCOMPATIBLE, and the cheap way to find out is to run the
REFERENCE against ITSELF with motion suppressed. That measures the exact contribution of
motion to the diffable state, in cycles, without writing a line of assembly.

★ L-56 in advance: this measures the REFERENCE, so whatever it reports is a property of the
thing the port must match, not of the port's scaffolding.

Prints the first divergent cycle per title and how many of the 600 cycles differ. No game data,
no text: cycle numbers, variable numbers and counts only (§2P).
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod, motion as motion_mod  # noqa: E402
from volread import resource  # noqa: E402


class Recorder:
    """Stands in for the trace sink: keeps (flags, vars) per cycle."""

    def __init__(self):
        self.rows = []

    def emit(self, cycle_nr, flags, vars_):
        self.rows.append((bytes(flags), bytes(vars_)))


def run(game_dir, cycles, suppress_motion):
    game = resource.load_from_files(game_dir)
    rec = Recorder()
    vm = cycle_mod.Vm(game, 0x2917, trace=rec)
    vm.start()

    if suppress_motion:
        # ★ Patched on the INSTANCE's module reference, then restored, so the two runs differ in
        # exactly one thing. Monkeypatching is acceptable here because this script's whole
        # purpose is an A/B on the reference; nothing it produces is a gate.
        saved = motion_mod.check_all_motions
        motion_mod.check_all_motions = lambda vm_: None
    try:
        for _ in range(cycles):
            if vm.should_quit:
                break
            vm.interpret_cycle()
    finally:
        if suppress_motion:
            motion_mod.check_all_motions = saved
    return rec.rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", nargs="*", default=["Kingquest1", "Kingquest2", "Kingquest3"])
    ap.add_argument("--cycles", type=int, default=600)
    a = ap.parse_args()

    print("Does suppressing motion change what AC-2 compares?  (%d cycles/title)" % a.cycles)
    print()
    any_diff = False
    for t in a.titles:
        d = str(pathlib.Path(a.games_root) / t)
        with_m = run(d, a.cycles, False)
        without = run(d, a.cycles, True)
        n = min(len(with_m), len(without))

        first = None
        ndiff = 0
        varset = set()
        flagset = set()
        for i in range(n):
            fa, va = with_m[i]
            fb, vb = without[i]
            if fa != fb or va != vb:
                ndiff += 1
                if first is None:
                    first = i
                for k in range(len(va)):
                    if va[k] != vb[k]:
                        varset.add(k)
                for k in range(len(fa)):
                    if fa[k] != fb[k]:
                        for b in range(8):
                            if (fa[k] ^ fb[k]) & (1 << b):
                                flagset.add(k * 8 + b)
        if ndiff:
            any_diff = True
        print("%-12s cycles compared %4d   divergent %4d   first at cycle %s"
              % (t, n, ndiff, first if first is not None else "-"))
        if varset:
            print("             vars affected : %s" % sorted(varset))
        if flagset:
            print("             flags affected: %s" % sorted(flagset))
    print()
    if any_diff:
        print("★★★ MOTION IS OBSERVABLE TO THE DIFF. A VM without it cannot satisfy AC-2's")
        print("    empty exclusion set; the affected variables above are the whole cost.")
    else:
        print("★ Motion changes nothing the diff compares over this window -- AC-2 is")
        print("  satisfiable without it, and that is a measured result, not an assumption.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
