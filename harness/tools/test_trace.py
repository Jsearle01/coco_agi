"""test_trace.py -- log every TEST the reference evaluates in one cycle. [T-P0-098]

★★★★★ WHY TESTS AND NOT STATE. P6.42 closed the state question: the port and the reference agree on
every one of the 288 bytes going into the divergent cycle, and two of the five bytes an earlier task
named were sampling artefacts. **If the state going in is identical and the decision differs, the
disagreement is inside a test's evaluation** -- and a cycle's test results are a far shorter and
sharper sequence than its state.

★★★★★ AND IT SIDESTEPS THE SEAM. A test result is produced DURING the body, so it does not depend on
where either side samples its state block -- which is exactly what cost T-P0-096 its conclusion
[P6.42 §1.1].

★★★★ tools/agivm/ IS NOT EDITED. The reference is the oracle's client and §2D/§2O.1 keep its body out
of a measurement's hands. This wraps `tests.test_if_code` and each bound test handler at RUNTIME, so
the logged program is byte-for-byte the one vm_stage.py runs.

★★★ THE SCENARIO IS vm_stage.py's, COPIED: same Vm construction, same vocabulary, same input script,
same jump. A trace of a different run would be a fact about a different run [§2O.1].

★ §2P: prints opcodes, operand bytes, boolean results and cycle numbers. No game text.

usage:
    python harness/tools/test_trace.py <game_dir> --cycles 400 --room 1 --room-at 8 \\
        --input build/eye_script.txt --at 100 [--logic 0]
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from agivm import cycle as cycle_mod        # noqa: E402
from agivm import tests as tests_mod        # noqa: E402
from volread import resource                # noqa: E402
from volread import words as words_mod      # noqa: E402


def main():
    a_ = argparse.ArgumentParser()
    a_.add_argument("game_dir")
    a_.add_argument("--cycles", type=int, default=400)
    a_.add_argument("--room", type=int, default=0)
    a_.add_argument("--room-at", type=int, default=8)
    a_.add_argument("--input")
    a_.add_argument("--at", type=int, required=True, help="the cycle to log")
    a_.add_argument("--logic", type=int, default=None,
                    help="only this logic number (default: all)")
    a = a_.parse_args()

    game = resource.load_from_files(a.game_dir)
    vm = cycle_mod.Vm(game, 0x2917)

    if a.input:
        script = {}
        for raw in pathlib.Path(a.input).read_text().splitlines():
            raw = raw.strip()
            if not raw or raw.startswith("#"):
                continue
            cyc, _sep, text = raw.partition(" ")
            script[int(cyc)] = text
        wt = (pathlib.Path(a.game_dir) / "WORDS.TOK").read_bytes()
        vm.load_vocabulary(words_mod.parse(wt).words)
        vm.input_script = script
        print("input script : %d line(s) at cycles %s" % (len(script), sorted(script)))

    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ THE WRAPPERS. `armed` is set from the cycle counter each time the expression
    # evaluator is entered, so a handler only logs while the cycle of interest is running --
    # and the counter is read from the VM rather than tracked here, because a second counter is
    # a second thing to get wrong.
    rows = []
    armed = {"on": False, "depth": 0}

    orig_if = tests_mod.test_if_code

    def wrapped_if(vm_):
        st = vm_.state
        on = (vm_.cycle_nr == a.at
              and (a.logic is None or st.cur_logic_nr == a.logic))
        prev = armed["on"]
        armed["on"] = on
        ip0 = st.ip
        res = orig_if(vm_)
        if on:
            rows.append(("EXPR", st.cur_logic_nr, ip0, None, res))
        armed["on"] = prev
        return res

    tests_mod.test_if_code = wrapped_if

    vm.start()

    # ★★★ THE HANDLERS ARE WRAPPED AFTER start(), because bind() happens during construction and
    # the table holds bound references. Wrapping the module functions instead would miss them.
    for op, entry in enumerate(vm.table.tests):
        if entry is None or entry.handler is None:
            continue

        def make(op_, entry_, h):
            def wrapper(vm_, p):
                st = vm_.state
                ip0 = st.ip
                h(vm_, p)
                if armed["on"]:
                    n = entry_.params if isinstance(entry_.params, int) else 0
                    args = list(p[:n]) if n else []
                    rows.append((entry_.name, st.cur_logic_nr, ip0, (op_, args),
                                 bool(st.test_result)))
            return wrapper
        entry.handler = make(op, entry, entry.handler)

    if a.room:
        vm.run(max_cycles=min(a.room_at, a.cycles))
        vm.set_var(0, a.room)
        vm.state.set_flag(5, True)
        print("room jump    : var0 <- %d, flag 5 set, at cycle %d" % (a.room, a.room_at))
    vm.run(max_cycles=a.cycles)

    print("\ntests evaluated at cycle %d%s : %d row(s)"
          % (a.at, "" if a.logic is None else " in logic %d" % a.logic, len(rows)))
    print("  %-18s %-6s %-6s %-22s %s" % ("test", "logic", "ip", "opcode(args)", "result"))
    for name, lg, ip, opargs, res in rows:
        oa = "" if opargs is None else "%02X(%s)" % (opargs[0],
                                                     ",".join(str(x) for x in opargs[1]))
        print("  %-18s %-6d $%04X %-22s %s" % (name, lg, ip, oa, res))


if __name__ == "__main__":
    main()
