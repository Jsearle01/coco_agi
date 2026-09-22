#!/usr/bin/env python3
"""res_sizes.py -- how big are the resources a room's cycle actually uses? [T-P0-133 §4A(2)]

★★★★ P6.79 put the resource layer at 62% of a castle cycle and P6.80 found the cache emptied by
STARVATION about once per cycle. The question that decides policy-versus-size is arithmetic: the
BYTE TOTAL of the working set against the arena. This prints it from the game's own files -- the
whole record as res_fetch copies it (payload, i.e. post-header), which is what res_len holds.

★★ It runs the oracle-gated reference [tools/agivm] for the same scene so the set is the one the
game asks for, not one I chose: every LOGIC invoked and every VIEW read, per cycle, with sizes.

§2P: sizes and numbers only; no resource bytes, no message text.

usage: python harness/tools/res_sizes.py --room 1 --room-at 8 --from 12 --to 40
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import objects                        # noqa: E402
from agivm.cycle import Vm                       # noqa: E402
from volread import resource                     # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=r"C:\Projects\agi-games\pc\Kingquest1")
    ap.add_argument("--room", type=int, default=1)
    ap.add_argument("--room-at", type=int, default=8)
    ap.add_argument("--from", dest="lo", type=int, default=12)
    ap.add_argument("--to", type=int, default=40)
    ap.add_argument("--arena", type=int, default=16384)
    a = ap.parse_args()

    game = resource.load_from_files(a.game)
    size = {}

    def res_size(kind, nr):
        key = (kind, nr)
        if key not in size:
            size[key] = len(game.load(kind, nr))
        return size[key]

    vm = Vm(game, 0x2917, seed=12345)
    per_cycle = {}

    # ★★★ WRAP THE REFERENCE'S OWN ENTRY POINTS, so the set is what the interpreter asks for:
    # run_logic is one invocation (the port's res_open of a LOGIC), load_view one VIEW read.
    orig_run_logic, orig_load_view = Vm.run_logic, Vm.load_view

    def run_logic(self, nr):
        per_cycle.setdefault(self.cycle_nr, set()).add(("LOGIC", nr))
        return orig_run_logic(self, nr)

    def load_view(self, nr):
        per_cycle.setdefault(self.cycle_nr, set()).add(("VIEW", nr))
        return orig_load_view(self, nr)

    Vm.run_logic, Vm.load_view = run_logic, load_view

    vm.start()
    vm.run(max_cycles=a.room_at)
    vm.set_var(0, a.room)
    vm.state.set_flag(5, True)
    vm.run(max_cycles=a.to)

    rows, union = [], set()
    for c in range(a.lo, a.to + 1):
        s = per_cycle.get(c, set())
        union |= s
        b = sum(res_size(k, n) for k, n in s)
        rows.append((c, len([x for x in s if x[0] == "LOGIC"]),
                     len([x for x in s if x[0] == "VIEW"]), b))
    print("cycle  LOGICs  VIEWs  bytes")
    for c, nl, nv, b in rows:
        print("%5d  %6d  %5d  %6d" % (c, nl, nv, b))
    if rows:
        peak = max(rows, key=lambda r: r[3])
        print("\npeak cycle %d: %d LOGIC(s) + %d VIEW(s) = %d bytes" % (peak[0], peak[1], peak[2], peak[3]))
    ub = sum(res_size(k, n) for k, n in union)
    print("union over cycles %d-%d: %d resources, %d bytes  (arena %d B -> %s)"
          % (a.lo, a.to, len(union), ub, a.arena,
             "FITS" if ub <= a.arena else "DOES NOT FIT, over by %d B" % (ub - a.arena)))
    for k, n in sorted(union):
        print("   %-7s %3d  %6d B" % (k, n, res_size(k, n)))


if __name__ == "__main__":
    main()
