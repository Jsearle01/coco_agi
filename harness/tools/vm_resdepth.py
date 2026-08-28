#!/usr/bin/env python3
"""harness/tools/vm_resdepth.py -- how many LOGICs must be resident AT ONCE?

★★★ AC-5's residency policy hangs on this and the dispatch leaves the choice to me, with
trigger 4 saying to pick the simplest absent a clear winner. ★★ But "simplest" is only
knowable against the workload, and there IS a workload: `cmdCall` runs another logic INSIDE the
current one and restores afterwards, so a single-slot buffer is wrong if calls nest at all.

★ So measure the nesting depth and the working set before choosing, rather than assuming
design §4.2's "current LOGIC" singular covers it -- that phrase describes the room's logic, and
`call` is a different question.
"""
import argparse
import collections
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm.cycle import Vm            # noqa: E402
from agivm.dispatch import OpcodeError  # noqa: E402
from volread import resource          # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", default="Kingquest1,Kingquest2,Kingquest3")
    ap.add_argument("--cycles", type=int, default=600)
    a = ap.parse_args()

    print(f"{'title':<12} {'max depth':>9} {'distinct logics':>16} {'max resident bytes':>19} "
          f"{'largest':>8}")
    for title in a.titles.split(","):
        g = ROOT and pathlib.Path(a.games_root) / title
        if not g.is_dir():
            print(f"{title:<12} MISSING")
            continue
        game = resource.load_from_files(str(g))
        vm = Vm(game, 0x2917, platform="dos", game_id="", seed=12345)

        stack = []
        max_depth = 0
        max_bytes = 0
        seen = set()
        sizes = {}

        orig = vm.run_logic

        def traced(nr, _orig=orig):
            nonlocal max_depth, max_bytes
            lg = vm.load_logic(nr)
            sizes[nr] = len(lg.bytecode)
            seen.add(nr)
            stack.append(nr)
            max_depth = max(max_depth, len(stack))
            # ★ the working set is the DISTINCT logics on the stack: a recursive call to the
            # same logic needs one buffer, not two.
            max_bytes = max(max_bytes, sum(sizes[n] for n in set(stack)))
            try:
                return _orig(nr)
            finally:
                stack.pop()

        vm.run_logic = traced
        vm.start()
        try:
            vm.run(max_cycles=a.cycles)
        except OpcodeError:
            pass
        print(f"{title:<12} {max_depth:>9} {len(seen):>16} {max_bytes:>19} "
              f"{max(sizes.values()) if sizes else 0:>8}")

    print("\n★ max depth is the number of logics live on the call stack simultaneously.")
    print("★ max resident bytes is the DISTINCT bytes those logics occupy at the deepest point")
    print("  -- that is the minimum a residency policy must hold without evicting a caller.")


if __name__ == "__main__":
    main()
