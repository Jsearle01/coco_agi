#!/usr/bin/env python3
"""harness/tools/vm_condcov.py -- AC-6: how much of the CONDITION BLOCK does the gate exercise?

★★★ THE STATE DIFF ALONE CANNOT ANSWER THIS. AC-2 says 256 vars and 256 flags match for 500
cycles across 9 titles; it does not say the OR path ever ran. An evaluator that mishandled
or_mode would pass a gate whose corpus never used or_mode, and the pass would mean nothing about
the branch that was never taken -- the same shape as 2H's "measured absence is an absence in the
thing measured", which cost this task a halt on BlackCauldron's kMotionWander.

★★ So this counts, on the REFERENCE side, every structural feature of test_if_code that the
gated run reaches:

  blocks        -- condition blocks entered
  or_mode       -- $FC seen (an OR group opened)
  or_short      -- an OR group satisfied early, skip_instructions_until($FC)
  not_mode      -- $FD seen
  and_short     -- an AND chain failed, skip_instructions_until($FF)
  said          -- test $0E, the one VARIABLE-LENGTH test operand
  true / false  -- how each block resolved

★ Paired with AC-2's byte-identical result, a non-zero count on a row is evidence that path both
RAN and AGREED. A zero row is a hole, stated as one. **The tool's job is to make the zeros
visible**, because those are the branches AC-2's pass says nothing about.

★ 2P: counts, cycle numbers and opcode numbers only. No game text, no resource bytes.
"""
import argparse
import collections
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod, tests as tests_mod   # noqa: E402
from volread import resource                               # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", nargs="*", default=[
        "BlackCauldron", "Kingquest1", "Kingquest2", "Kingquest3", "larry1",
        "SpaceQuest-1", "SpaceQuest-2", "PoliceQuest1", "MixedUpMotherGoose"])
    ap.add_argument("--cycles", type=int, default=500)
    a = ap.parse_args()

    total = collections.Counter()
    rows = []

    for title in a.titles:
        c = collections.Counter()
        game = resource.load_from_files(str(pathlib.Path(a.games_root) / title))
        vm = cycle_mod.Vm(game, 0x2917)
        vm.start()

        orig_until = tests_mod.skip_instructions_until

        def skip_until(vm_, target, _c=c, _o=orig_until):
            _c["or_short" if target == 0xFC else "and_short"] += 1
            return _o(vm_, target)

        tests_mod.skip_instructions_until = skip_until
        orig_tic = tests_mod.test_if_code

        def test_if_code(vm_, _c=c, _o=orig_tic):
            st = vm_.state
            ip0 = st.ip
            # ★ read the block's tokens WITHOUT evaluating: the evaluator itself is the thing
            # under measurement, so counting inside it would couple the two.
            j = ip0
            code = st.code
            while j < len(code):
                op = code[j]
                if op == 0xFC:
                    _c["or_mode"] += 1
                elif op == 0xFD:
                    _c["not_mode"] += 1
                elif op in (0x00, 0xFF):
                    break
                elif op == 0x0E:
                    _c["said"] += 1
                    j += 1 + code[j + 1] * 2 + 1
                    continue
                else:
                    j += 1 + tests_mod.TEST_ARGS[op] if hasattr(tests_mod, "TEST_ARGS") else j + 1
                    continue
                j += 1
            _c["blocks"] += 1
            r = _o(vm_)
            _c["true" if r else "false"] += 1
            return r

        tests_mod.test_if_code = test_if_code
        try:
            vm.run(max_cycles=a.cycles)
        finally:
            tests_mod.test_if_code = orig_tic
            tests_mod.skip_instructions_until = orig_until

        rows.append((title, c))
        total.update(c)

    keys = ["blocks", "true", "false", "or_mode", "or_short", "not_mode", "and_short", "said"]
    print("%-20s %s" % ("title", " ".join("%9s" % k for k in keys)))
    print("-" * (20 + 10 * len(keys)))
    for title, c in rows:
        print("%-20s %s" % (title, " ".join("%9d" % c[k] for k in keys)))
    print("-" * (20 + 10 * len(keys)))
    print("%-20s %s" % ("TOTAL", " ".join("%9d" % total[k] for k in keys)))

    zeros = [k for k in keys if not total[k]]
    print()
    if zeros:
        print("★★★ NOT EXERCISED by this run: %s" % ", ".join(zeros))
        print("    AC-2's pass says nothing about these paths.")
    else:
        print("★ Every structural path of test_if_code is exercised by this run, and AC-2")
        print("  reports the resulting state byte-identical -- so each one RAN and AGREED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
