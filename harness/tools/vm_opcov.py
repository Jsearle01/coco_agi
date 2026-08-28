#!/usr/bin/env python3
"""harness/tools/vm_opcov.py -- which opcodes does the gated set actually EXECUTE?

★★★ AC-5 scopes the port to "what the gate exercises", so that set has to be measured before
anything is written, not guessed from the 203-entry table. This runs tools/agivm/ over the
titles with the dispatch table instrumented and reports every opcode executed, with counts,
plus the ones never reached.

★ It counts EXECUTIONS, not static occurrences: an opcode present in a LOGIC that is never
reached is not exercised, and implementing it would be work the gate cannot check.
"""
import argparse
import collections
import io
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1].parent / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm.cycle import Vm                            # noqa: E402
from agivm.dispatch import OpcodeError                # noqa: E402
from volread import resource                          # noqa: E402


def instrument(vm, cmd_hits, test_hits):
    """Wrap every bound handler so execution is counted at the dispatch itself."""
    for tbl, hits in ((vm.table.commands, cmd_hits), (vm.table.tests, test_hits)):
        for num, op in enumerate(tbl):
            if op is None or op.handler is None:
                continue
            h, n, nm = op.handler, num, op.name

            def make(h=h, n=n, nm=nm, hits=hits):
                def wrapped(*a, **k):
                    hits[(n, nm)] += 1
                    return h(*a, **k)
                return wrapped
            op.handler = make()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default=r"C:\Projects\agi-games\pc")
    ap.add_argument("--titles", default="Kingquest1,Kingquest2,Kingquest3")
    ap.add_argument("--cycles", type=int, default=600)
    ap.add_argument("--version", default="0x2917")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    root = pathlib.Path(a.games_root)
    cmd_hits, test_hits = collections.Counter(), collections.Counter()
    status = {}

    for title in a.titles.split(","):
        g = root / title
        if not g.is_dir():
            print(f"  {title}: MISSING at {g}")
            continue
        game = resource.load_from_files(str(g))
        vm = Vm(game, int(a.version, 0), platform="dos", game_id="", seed=12345)
        for tbl, kind in ((vm.table.commands, "cmd"), (vm.table.tests, "test")):
            for num, op in enumerate(tbl):
                if op is not None:
                    status[(kind, num)] = (op.name, op.status)
        instrument(vm, cmd_hits, test_hits)
        vm.start()
        try:
            vm.run(max_cycles=a.cycles)
        except OpcodeError as exc:
            print(f"  {title}: HALTED {exc}")
        print(f"  {title}: {a.cycles} cycles")

    print(f"\n{'='*74}")
    print("★★★ OPCODES EXECUTED BY THE GATED SET (this is the port's scope)")
    for label, hits, kind in (("COMMANDS", cmd_hits, "cmd"), ("TESTS", test_hits, "test")):
        print(f"\n{label}: {len(hits)} distinct executed")
        for (num, name), n in sorted(hits.items(), key=lambda kv: -kv[1]):
            st = status.get((kind, num), ("?", "?"))[1]
            print(f"   0x{num:02X} {name:<24} x{n:<8} {st}")

    # ── what is NOT reached: named, not counted (AC-5) ──────────────────────────────────
    print(f"\n{'='*74}")
    for label, hits, kind in (("COMMANDS", cmd_hits, "cmd"), ("TESTS", test_hits, "test")):
        reached = {n for n, _ in hits}
        missing = sorted(num for (k, num) in status if k == kind and num not in reached)
        print(f"\n{label} NOT reached: {len(missing)}")
        line = []
        for num in missing:
            line.append(f"0x{num:02X} {status[(kind,num)][0]}")
        for i in range(0, len(line), 4):
            print("   " + "  ".join(f"{s:<26}" for s in line[i:i+4]))

    if a.out:
        p = pathlib.Path(a.out)
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("w", encoding="utf-8") as f:
            f.write("kind,opcode,name,status,executions\n")
            for kind, hits in (("cmd", cmd_hits), ("test", test_hits)):
                for (num, name), n in sorted(hits.items()):
                    st = status.get((kind, num), ("?", "?"))[1]
                    f.write(f"{kind},{num},{name},{st},{n}\n")
        print(f"\nwrote {p}")


if __name__ == "__main__":
    main()
