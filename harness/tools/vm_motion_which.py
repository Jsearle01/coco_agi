#!/usr/bin/env python3
"""harness/tools/vm_motion_which.py -- WHICH part of motion does the gate actually need?

★★ vm_motion_impact.py established THAT motion is observable to AC-2 (KQ2 diverges at cycle 49).
This asks HOW MUCH of it -- because "motion is required" and "one motion type is required" are
very different amounts of work, and the difference decides whether the gate is reachable.

★★★ §2H CHECK 1 APPLIED TO MY OWN SCOPING: check_all_motions is not one mechanism. It dispatches
on motionType (normal / ego / wander / follow.ego / move.obj) and separately runs the cycler.
Reporting "motion is needed" without saying which branch fires would be the first-mechanism
error in the other direction -- treating a dispatcher as a monolith.

Counts calls per motion branch over the gated window, per title. Counts only (§2P).
"""
import argparse
import collections
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod, motion as motion_mod  # noqa: E402
from volread import resource  # noqa: E402

# Every public entry point in motion.py -- discovered, not typed, so a branch added to the
# reference later cannot silently escape this census.
NAMES = [n for n in dir(motion_mod)
         if callable(getattr(motion_mod, n)) and not n.startswith("_")
         and getattr(getattr(motion_mod, n), "__module__", "") == motion_mod.__name__]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", nargs="*", default=["Kingquest1", "Kingquest2", "Kingquest3"])
    ap.add_argument("--cycles", type=int, default=600)
    a = ap.parse_args()

    print("motion.py entry points: %s" % ", ".join(sorted(NAMES)))
    print()
    for t in a.titles:
        counts = collections.Counter()
        originals = {}
        for n in NAMES:
            fn = getattr(motion_mod, n)

            def wrap(fn=fn, n=n):
                def inner(*args, **kw):
                    counts[n] += 1
                    return fn(*args, **kw)
                return inner
            originals[n] = fn
            setattr(motion_mod, n, wrap())
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
                setattr(motion_mod, n, fn)

        print("%-12s %s" % (t, " ".join("%s=%d" % (k, v) for k, v in counts.most_common())
                            or "(none)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
