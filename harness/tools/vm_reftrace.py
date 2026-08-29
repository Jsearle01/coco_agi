#!/usr/bin/env python3
"""harness/tools/vm_reftrace.py -- the REFERENCE's instruction trace, in the guest's format.

★★★ THE POINT IS A DIFFABLE PAIR. The 6809 emits (ip, opcode, kind) per step; this emits the
same thing from tools/agivm for the same cycles, so the two can be compared line by line and the
FIRST line where they part company is the defect's location -- rather than a state difference
observed hundreds of instructions downstream [L-36: if you can bisect against the reference, the
cause is not ambiguous].

★★ It instruments run_logic and test_if_code by wrapping, not by editing them: the reference is
oracle-gated and must not be modified to be observed.

★ §2P: emits instruction pointers and opcode numbers. No game text, no resource bytes.
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod, tests as tests_mod  # noqa: E402
from volread import resource  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=r"C:\Projects\agi-games\pc\Kingquest1")
    ap.add_argument("--cycles", type=int, default=1)
    ap.add_argument("--logic", type=int, default=0, help="only trace this logic number")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    game = resource.load_from_files(a.game)
    vm = cycle_mod.Vm(game, 0x2917)
    vm.start()

    steps = []

    # ── the outer interpreter loop: kind 0 ──────────────────────────────────────────────
    orig_run = cycle_mod.Vm.run_logic

    def run_logic(self, nr):
        st = self.state
        lg = self.load_logic(nr)
        st.cur_logic_nr = nr
        st.code = lg.bytecode
        st.ip = 0
        while st.ip < len(st.code) and not self.should_quit:
            op = st.code[st.ip]
            if nr == a.logic:
                steps.append((st.ip, op, 0))
            st.ip += 1
            if op == 0xFF:
                tests_mod.test_if_code(self)
                continue
            if op == 0xFE:
                off = int.from_bytes(st.code[st.ip:st.ip + 2], "little", signed=True)
                st.ip += 2 + off
                continue
            if op == 0x00:
                return 1
            entry = self.table.commands[op]
            p = st.code[st.ip:st.ip + entry.size]
            entry.handler(self, p)
            st.ip += entry.size
            if st.exit_all_logics:
                break
        return 0

    cycle_mod.Vm.run_logic = run_logic

    # ── the evaluator: kind 1 per test opcode, kind 2 at expression end ──────────────────
    orig_tic = tests_mod.test_if_code

    def test_if_code(vm_):
        st = vm_.state
        not_mode = or_mode = False
        end_test = False
        result = True
        while not end_test:
            op = st.code[st.ip]
            st.ip += 1
            if st.cur_logic_nr == a.logic:
                steps.append((st.ip, op, 1))
            if op == 0xFC:
                if or_mode:
                    tests_mod.skip_instructions_until(vm_, 0xFF)
                    result = False
                    end_test = True
                else:
                    or_mode = True
                continue
            if op == 0xFD:
                not_mode = True
                continue
            if op in (0x00, 0xFF):
                end_test = True
                continue
            entry = vm_.table.tests[op]
            p = st.code[st.ip:st.ip + 16]
            entry.handler(vm_, p)
            if st.exit_all_logics:
                return True
            tests_mod.skip_instruction(vm_, op)
            if not_mode:
                st.test_result = not st.test_result
            not_mode = False
            if or_mode:
                if st.test_result:
                    tests_mod.skip_instructions_until(vm_, 0xFC)
                    or_mode = False
                    continue
            else:
                result = result and st.test_result
                if not result:
                    tests_mod.skip_instructions_until(vm_, 0xFF)
                    end_test = True
                    continue
        if st.cur_logic_nr == a.logic:
            steps.append((st.ip, 1 if result else 0, 2))
        if result:
            st.ip += 2
        else:
            st.ip += int.from_bytes(st.code[st.ip:st.ip + 2], "little") + 2
        return result

    tests_mod.test_if_code = test_if_code

    # ★★ vm.run(), for the same reason vm_stage.py uses it: a bare interpret_cycle() loop skips
    # the 25 ms clock, the TIME_DELAY pacing gate and the post-cycle resets, so the traced run is
    # not the run the oracle records and the two can part company over pacing alone.
    vm.run(max_cycles=a.cycles)

    lines = ["%5d %02X %d" % s for s in steps]
    if a.out:
        pathlib.Path(a.out).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
        print("wrote %d steps -> %s" % (len(steps), a.out))
    else:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
