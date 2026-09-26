#!/usr/bin/env python3
"""opcount_ref.py -- HOW MANY OPCODES DOES A CYCLE REQUIRE? [T-P0-156]

THE QUESTION.  P6.101 found the port's `interpret` stage is 156,784 CPU cycles per game cycle --
more than Sierra's ENTIRE cycle (89,489-119,318) -- and P6.102's profile put 42.5% of that stage
in the if-condition machinery, at an estimated ~215 test opcodes per cycle.  That estimate came
from dividing a sampled share by a hand-counted instruction cost, which is two approximations
multiplied together.

** SO: COUNT THEM.  And count them on the REFERENCE, because that says how many opcodes the
LOGIC REQUIRES rather than how many our 6809 leg happens to run. **  If the two agree, the volume
is necessary and the target is per-opcode cost.  If the port runs more, we are executing logic we
need not, and that is a different and much larger fix.

WHAT IS COUNTED.  cycle.py already increments `instruction_counter` once per opcode byte fetched
in run_logic, and carries `_cycle_instr0` so a per-cycle delta is available.  This file reads that
delta, and separately classifies each cycle's opcodes into TESTS and COMMANDS by walking the same
dispatch tables optable.py exports -- so the split can be compared with the port's own
VM_TESTSEEN / VM_OPSEEN counters.

SS2W -- WHAT THIS IS NOT.
  * It is the REFERENCE's opcode count, not the port's.  The port's own counters are behind
    -DP3B_COVERAGE and are the other half of the comparison; this file cannot speak for them.
  * `instruction_counter` counts opcode FETCHES in run_logic.  A test opcode consumed inside
    vm_test_if_code's evaluator is NOT a run_logic fetch, so the raw counter UNDERSTATES the
    total work; the test walk below is what accounts for those.
  * A cycle that calls no logic still costs the port a cycle.  Zero here is not zero there.

SS2V: host-side analysis; no 6809 form is implied.
SS2P: opens the game read-only through volread, prints counts only.
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import resource                        # noqa: E402
from agivm.cycle import Vm                          # noqa: E402
from agivm import tests as tests_mod                # noqa: E402

# ★★★★★ COUNT THE EVALUATOR'S ITERATIONS BY WRAPPING IT, NOT BY EDITING IT. `instruction_counter`
# counts run_logic fetches; the opcode bytes consumed INSIDE test_if_code's while-loop are not
# among them, and those are exactly what the port's vm_tic_loop spends 83 cycles each on.
# ★★★ The wrapper re-reads ip before and after, so it measures BYTES CONSUMED by the expression --
# the same population vm_tic_loop fetches -- rather than trusting a count of its own.
#
# ★★★★★ AND THE ip DELTA IS THE WRONG STATISTIC -- MY FIRST CUT REPORTED 4,883 AND IT WAS WRONG.
# test_if_code calls `skip_instructions_until` on a false expression, which advances ip past the
# WHOLE FALSE BRANCH. So an ip delta counts SKIPPED BODY BYTES as if they were evaluated test
# opcodes, and 4,883 per cycle was that. ★★★★ The exact count is the number of TEST HANDLER
# DISPATCHES -- `entry.handler(vm, p)` in tests.py -- so every handler in the table is wrapped.
# ★★★ Both are reported: `evaluated` is the population vm_tic_loop fetches, `ip_span` is what a
# naive delta would have claimed, kept so the difference is visible rather than quietly corrected.
#
# ★★★★★ AND THE THIRD COUNT IS THE ONE THAT MATTERS: HOW MUCH CODE IS SKIPPED, AND HOW OFTEN.
# `skip_instructions_until` walks a false branch ONE OPCODE AT A TIME -- the port's vm_su_lp, 51
# cycles per test. ★★★★ The skip distance from a given ip is INVARIANT, because the logic is
# static: the same walk is repeated every cycle over unchanging bytes. **That is the cel cache's
# shape in the interpreter**, and it is only worth anything if the walked volume is large.
_STATS = {"calls": 0, "ip_span": 0, "evaluated": 0, "skips": 0, "skip_bytes": 0}
_orig_tic = tests_mod.test_if_code
_orig_skip = tests_mod.skip_instructions_until


def _counting_skip(vm, marker):
    ip0 = vm.state.ip
    r = _orig_skip(vm, marker)
    _STATS["skips"] += 1
    _STATS["skip_bytes"] += vm.state.ip - ip0
    return r


tests_mod.skip_instructions_until = _counting_skip


def _counting_tic(vm):
    ip0 = vm.state.ip
    r = _orig_tic(vm)
    _STATS["calls"] += 1
    _STATS["ip_span"] += vm.state.ip - ip0
    return r


tests_mod.test_if_code = _counting_tic
# ★★ cycle.py may have bound the original at import time; rebind there too if so.
try:
    from agivm import cycle as _cycle_mod
    if getattr(_cycle_mod, "test_if_code", None) is _orig_tic:
        _cycle_mod.test_if_code = _counting_tic
except Exception:
    pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=r"C:\Projects\agi-games\pc\Kingquest1")
    ap.add_argument("--room", type=int, default=1)
    ap.add_argument("--room-at", type=int, default=8, dest="room_at")
    ap.add_argument("--from-cycle", type=int, default=11, dest="frm")
    ap.add_argument("--to", type=int, default=120)
    a = ap.parse_args()

    vm = Vm(resource.load_from_files(a.game), 0x2917, seed=12345)

    # ★★★★ Wrap every test handler in the VM's own table: one increment per EVALUATED test opcode.
    # Done after construction because the table belongs to the Vm instance.
    for _op, _e in enumerate(vm.table.tests):
        if _e is None or getattr(_e, "handler", None) is None:
            continue

        def _mk(h):
            def _w(vm_, p):
                _STATS["evaluated"] += 1
                return h(vm_, p)
            return _w
        _e.handler = _mk(_e.handler)

    vm.start()
    vm.run(max_cycles=a.room_at)
    vm.set_var(0, a.room)
    vm.state.set_flag(5, True)

    per = []
    prev = vm.instruction_counter
    pcalls, pspan, peval = _STATS["calls"], _STATS["ip_span"], _STATS["evaluated"]
    pskips, psb = _STATS["skips"], _STATS["skip_bytes"]
    for c in range(a.room_at + 1, a.to + 1):
        vm.run(max_cycles=c)
        now = vm.instruction_counter
        per.append((c, now - prev, _STATS["calls"] - pcalls,
                    _STATS["evaluated"] - peval, _STATS["ip_span"] - pspan,
                    _STATS["skips"] - pskips, _STATS["skip_bytes"] - psb))
        prev, pcalls, pspan, peval = (now, _STATS["calls"],
                                      _STATS["ip_span"], _STATS["evaluated"])
        pskips, psb = _STATS["skips"], _STATS["skip_bytes"]

    rows = [r for r in per if r[0] >= a.frm]
    if not rows:
        print("no cycles in window")
        return 1
    win = [r[1] for r in rows]
    tcalls = [r[2] for r in rows]
    tevals = [r[3] for r in rows]
    tbytes = [r[4] for r in rows]
    skips = [r[5] for r in rows]
    skipb = [r[6] for r in rows]
    win_sorted = sorted(win)
    n = len(win)
    print("%s room %d, cycles %d..%d (%d cycles)" % (a.game, a.room, a.frm, a.to, n))
    print("  run_logic opcode FETCHES per cycle:")
    print("     mean %7.1f   median %5d   min %5d   max %5d   total %d"
          % (sum(win) / n, win_sorted[n // 2], win_sorted[0], win_sorted[-1], sum(win)))
    # ★ The distribution matters: a mean over a window containing a room render is the mistake
    # P6.84 spent a task correcting, so print the shape as well as the centre.
    print("  deciles: " + " ".join("%d" % win_sorted[min(n - 1, i * n // 10)] for i in range(10)))
    print()
    print("  if-expression evaluations (test_if_code CALLS) per cycle:")
    print("     mean %7.1f   min %5d   max %5d   total %d"
          % (sum(tcalls) / n, min(tcalls), max(tcalls), sum(tcalls)))
    print("  TEST OPCODES EVALUATED per cycle (handler dispatches -- the exact count):")
    print("     mean %7.1f   min %5d   max %5d   total %d"
          % (sum(tevals) / n, min(tevals), max(tevals), sum(tevals)))
    print("  ip SPAN across those expressions per cycle (INCLUDES skipped branches -- NOT a count):")
    print("     mean %7.1f   -- a naive delta would report this as the opcode count and be wrong"
          % (sum(tbytes) / n))
    print()
    print("  ★ TOTAL opcodes the LOGIC requires per cycle: %.1f run_logic + %.1f tests = %.1f"
          % (sum(win) / n, sum(tevals) / n, (sum(win) + sum(tevals)) / n))
    print()
    print("  ★★★ BRANCH SKIPPING -- skip_instructions_until, the port's vm_su_lp:")
    print("     calls per cycle %6.1f   BYTES WALKED per cycle %8.1f   mean per call %6.1f"
          % (sum(skips) / n, sum(skipb) / n, sum(skipb) / max(1, sum(skips))))
    print("     ★ the skip DISTANCE from a given ip is INVARIANT (the logic is static), so this"
          " walk repeats identically every cycle -- a cacheable computation.")
    return 0
    print("  ★ THE PORT'S ESTIMATE TO BEAT: ~215 test-opcode fetches per cycle in vm_tic_loop")
    print("    [P6.102, from a sampled share divided by a hand-counted 83-cycle loop cost].")
    print("    Compare against the IN-EXPRESSION figure, which is the same population.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
