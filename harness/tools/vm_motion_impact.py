#!/usr/bin/env python3
"""harness/tools/vm_motion_impact.py -- is an out-of-scope cycle step observable to AC-2?

★★★ THE QUESTION, AND WHY IT IS ASKED BEFORE ANY 6809 IS WRITTEN. T-P0-025 puts motion out of
scope, and AC-2 requires 256 vars + 256 flags byte-identical against tools/agivm every cycle
with an EMPTY exclusion set. But interpret_cycle() calls motion.check_all_motions() BEFORE
running logic.0, and get.posn -- 3,625 executions in the gated set -- copies object x/y into
variables. If motion moves an object that a logic then reads back, the move reaches the diff.

★★ SO THE TWO REQUIREMENTS MAY BE INCOMPATIBLE, and the cheap way to find out is to run the
REFERENCE against ITSELF with the step suppressed. That measures the exact contribution to
diffable state, in cycles, without writing a line of assembly.

★★★ THE CYCLE MAKES TWO OUT-OF-SCOPE CALLS, NOT ONE. check_all_motions is the obvious one;
objects.update_screen_obj_table runs at the END of every cycle when gfx_mode is set (start()
sets it) and writes VM_VAR_BORDER_*. Measuring only the first would answer half the question
and leave the other half to be found by a failing gate -- §2H check 1 turned on my own scoping:
ask what the OTHER kind of thing does.

★ L-56 in advance: this measures the REFERENCE, so whatever it reports is a property of the
thing the port must match, not of the port's scaffolding.

Prints the first divergent cycle per title and how many cycles differ. No game data, no text:
cycle numbers, variable numbers and counts only (§2P).
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod, motion as motion_mod, objects as objects_mod  # noqa: E402
from volread import resource  # noqa: E402

SUPPRESS = {
    "motion":  [(motion_mod, "check_all_motions")],
    "objects": [(objects_mod, "update_screen_obj_table")],
    "both":    [(motion_mod, "check_all_motions"),
                (objects_mod, "update_screen_obj_table")],
}


class Recorder:
    """Stands in for the trace sink: keeps (flags, vars) per cycle."""

    def __init__(self):
        self.rows = []

    def emit(self, cycle_nr, flags, vars_):
        self.rows.append((bytes(flags), bytes(vars_)))


def run(game_dir, cycles, suppress):
    game = resource.load_from_files(game_dir)
    rec = Recorder()
    vm = cycle_mod.Vm(game, 0x2917, trace=rec)
    vm.start()

    saved = []
    if suppress:
        # ★ Patched on the module, then restored, so the two runs differ in exactly one thing.
        # Monkeypatching is acceptable here because this script's whole purpose is an A/B on
        # the reference; nothing it produces is a gate.
        for mod, name in SUPPRESS[suppress]:
            saved.append((mod, name, getattr(mod, name)))
            setattr(mod, name, lambda *a, **k: None)
    try:
        for _ in range(cycles):
            if vm.should_quit:
                break
            vm.interpret_cycle()
    finally:
        for mod, name, fn in saved:
            setattr(mod, name, fn)
    return rec.rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", nargs="*", default=["Kingquest1", "Kingquest2", "Kingquest3"])
    ap.add_argument("--cycles", type=int, default=600)
    ap.add_argument("--suppress", choices=list(SUPPRESS), default="motion")
    a = ap.parse_args()

    print("Suppressing %s -- does it change what AC-2 compares?  (%d cycles/title)"
          % (a.suppress, a.cycles))
    print()
    any_diff = False
    for t in a.titles:
        d = str(pathlib.Path(a.games_root) / t)
        base = run(d, a.cycles, None)
        cut = run(d, a.cycles, a.suppress)
        n = min(len(base), len(cut))

        first, ndiff = None, 0
        varset, flagset = set(), set()
        for i in range(n):
            fa, va = base[i]
            fb, vb = cut[i]
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
        print("★★★ %s IS OBSERVABLE TO THE DIFF. A VM without it cannot satisfy AC-2's"
              % a.suppress.upper())
        print("    empty exclusion set; the affected variables above are the whole cost.")
    else:
        print("★ %s changes nothing the diff compares over this window -- AC-2 is" % a.suppress)
        print("  satisfiable without it, and that is a measured result, not an assumption.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
