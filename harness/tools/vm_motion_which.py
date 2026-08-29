#!/usr/bin/env python3
"""harness/tools/vm_motion_which.py -- WHICH part of a subsystem does the gate actually need?

★★ vm_motion_impact.py establishes THAT a cycle step is observable to AC-2. This asks HOW MUCH
of it -- because "motion is required" and "one motion branch is required" are very different
amounts of work, and the difference decides whether the gate is reachable inside the dispatch.

★★★ §2H CHECK 1 APPLIED TO MY OWN SCOPING: neither check_all_motions nor update_screen_obj_table
is one mechanism. The first dispatches on motionType (normal / ego / wander / follow.ego /
move.obj); the second runs the cel cycler, the position update and the border check. Reporting
"motion is needed" without saying which branch fires would be the first-mechanism error in the
other direction -- treating a dispatcher as a monolith.

Counts calls per entry point over the gated window, per title. Counts only (§2P).
"""
import argparse
import collections
import importlib
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod  # noqa: E402
from volread import resource  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", nargs="*", default=["Kingquest1", "Kingquest2", "Kingquest3"])
    ap.add_argument("--cycles", type=int, default=600)
    ap.add_argument("--module", default="motion", help="agivm submodule to census")
    a = ap.parse_args()

    mod = importlib.import_module("agivm." + a.module)
    # Discovered, not typed, so a branch added to the reference cannot escape this census.
    names = [n for n in dir(mod)
             if callable(getattr(mod, n)) and not n.startswith("_")
             and getattr(getattr(mod, n), "__module__", "") == mod.__name__]

    print("agivm.%s entry points: %s" % (a.module, ", ".join(sorted(names))))
    print()
    for t in a.titles:
        counts = collections.Counter()
        originals = {}
        for n in names:
            fn = getattr(mod, n)

            def wrap(fn=fn, n=n):
                def inner(*args, **kw):
                    counts[n] += 1
                    return fn(*args, **kw)
                return inner
            originals[n] = fn
            setattr(mod, n, wrap())
        try:
            game = resource.load_from_files(str(pathlib.Path(a.games_root) / t))
            vm = cycle_mod.Vm(game, 0x2917)
            vm.start()
            for _ in range(a.cycles):
                if vm.should_quit:
                    break
                vm.interpret_cycle()
        finally:
            for n, fn in originals.items():
                setattr(mod, n, fn)

        print("%-12s %s" % (t, " ".join("%s=%d" % (k, v) for k, v in counts.most_common())
                            or "(none)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
