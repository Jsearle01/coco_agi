#!/usr/bin/env python3
"""harness/tools/print_first_cycle.py -- at which cycle does a title first execute print? [T-P0-085c]

★★★★★ THE QUESTION AC-4..AC-8 TURNS OUT TO REST ON, AND IT HAD NO INSTRUMENT. `print` now BLOCKS,
so every acceptance criterion about the blocking window needs a run that actually reaches opcode
$65/$66. **vm_opcov.py says neither is reached by ANY of the nine gated titles in 600 cycles** --
without input an AGI game sits in attract mode, and the intro text is display ($67/$68).

★★★★ AND FEEDING A COMMAND DOES NOT FIX IT. vm_input_script.py --wants-print measured every line
its said() census can synthesise, across six titles: **zero reach print.** Those patterns are the
meta-commands the input handler tests (the speed words, restart, restore), not "look at the rock".

★★★ So the remaining question is simply WHEN, with no input at all -- does the intro eventually
put up a message box, and at what cycle? A number here turns "the gate needs a different title"
into a gate parameter. A `None` is equally a result: it says the blocking path cannot be reached
from attract mode and the gate must be driven another way [§8: a negative result is a result].

★★ §2P: cycle numbers and counts only. No message text, ever.

usage:
  python harness/tools/print_first_cycle.py [--titles A,B] [--cycles 3000] [--games-root DIR]
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod        # noqa: E402
from volread import resource                # noqa: E402

DEFAULT_TITLES = ("Kingquest1", "Kingquest2", "Kingquest3", "SpaceQuest-1", "SpaceQuest-2",
                  "PoliceQuest1", "larry1", "BlackCauldron", "MixedUpMotherGoose")
PRINT_OPS = (0x65, 0x66)


def first_print(game_dir, max_cycles):
    """-> (first_cycle_or_None, total_hits, final_room, cycles_run, error_or_None)"""
    game = resource.load_from_files(game_dir)
    vm = cycle_mod.Vm(game, 0x2917)
    seen = {"first": None, "hits": 0}
    saved = {}

    # ★★ Restore the handlers afterwards: the optable may be shared between Vm instances, and a
    # wrapper left in place would follow the next title into its own measurement.
    for num in PRINT_OPS:
        op = vm.table.commands[num]
        if op is None or op.handler is None:
            continue
        saved[num] = op.handler

        def make(h=op.handler):
            def wrapped(*args, **kw):
                seen["hits"] += 1
                if seen["first"] is None:
                    # ★ vm.cycle_nr is incremented by interpret_cycle() before the body runs, so
                    # the BODY number -- the one a feed schedule and p3b_run.lua both use -- is
                    # one less. Same convention as vm_input_script.py's census.
                    seen["first"] = max(0, getattr(vm, "cycle_nr", 0) - 1)
                return h(*args, **kw)
            return wrapped
        op.handler = make()

    err = None
    try:
        vm.start()
        vm.run(max_cycles=max_cycles)
    except Exception as exc:                            # noqa: BLE001
        err = str(exc).split("(")[0].strip()
    finally:
        for num, h in saved.items():
            vm.table.commands[num].handler = h
    return seen["first"], seen["hits"], vm.get_var(0), getattr(vm, "cycle_nr", 0), err


def main():
    ap_ = argparse.ArgumentParser()
    ap_.add_argument("--games-root", default="C:/Projects/agi-games/pc")
    ap_.add_argument("--titles", default=",".join(DEFAULT_TITLES))
    ap_.add_argument("--cycles", type=int, default=3000)
    a = ap_.parse_args()

    root = pathlib.Path(a.games_root)
    titles = [t.strip() for t in a.titles.split(",") if t.strip()]
    print("first print ($65/$66) with NO INPUT, %d cycles max" % a.cycles)
    print("%-22s %10s %8s %6s %8s  %s" % ("title", "first", "hits", "room", "ran", "note"))
    found = 0
    for t in titles:
        d = root / t
        if not d.is_dir():
            print("%-22s %10s" % (t, "no dir"))
            continue
        first, hits, room, ran, err = first_print(str(d), a.cycles)
        if first is not None:
            found += 1
        print("%-22s %10s %8d %6d %8d  %s"
              % (t, "cycle %d" % first if first is not None else "NEVER",
                 hits, room, ran, err or ""))
    print("")
    if not found:
        print("★★★ NO TITLE REACHES print FROM ATTRACT MODE in %d cycles." % a.cycles)
        print("    The blocking window cannot be exercised by running a title from its start;")
        print("    the gate needs a driven path, and that is a dispatch-level decision.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
