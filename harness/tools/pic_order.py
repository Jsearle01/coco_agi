#!/usr/bin/env python3
"""harness/tools/pic_order.py -- WHEN does the game order its own screen? [T-P0-121 / P6.67]

★★★★★ THIS ANSWERS §4C, AND IT IS A QUESTION ABOUT THE GAME, NOT ABOUT THE PORT. "Does the
copyright draw before or after the picture appears" is a property of the title's LOGIC, so the
offline reference can answer it without building a single byte of 6809. The port's job is then to
reproduce an ordering that was measured rather than one that was assumed.

★★★★ IT WRAPS HANDLERS, NOT THE INTERPRETER LOOP. vm_reftrace.py had to copy run_logic's body to
observe it, which means the copy can silently drift from the original and mis-trace. Here each
watched opcode's `handler` is replaced by a recorder that delegates, so the interpreter that runs
is the interpreter under test [§2O.1 -- one producer].

★★★ EVERY WATCHED OPCODE IS NAMED, NEVER NUMBERED, and the numbers come from optable.py, which is
generated from the pinned oracle [L-29; P4.4 is the cautionary tale -- two hand-typed constants
cost a gate]. A name this table does not contain is a hard error, so a typo cannot quietly watch
the wrong opcode.

★★ AND A WATCHED OPCODE THAT COULD NOT BE WRAPPED IS REPORTED, not skipped in silence -- an
instrument whose coverage is smaller than it claims is the defect §2W exists to catch [L-88].

★ §2P: emits cycle numbers, logic numbers, opcode names and operand BYTES (variable numbers and
message numbers). No message text, no resource bytes.

usage:
    python harness/tools/pic_order.py --cycles 40
    python harness/tools/pic_order.py --game <dir> --cycles 200 --watch load.pic,draw.pic,show.pic
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import optable                          # noqa: E402
from agivm.cycle import Vm                         # noqa: E402
from agivm.dispatch import OpcodeError             # noqa: E402
from volread import resource                       # noqa: E402

# ★★ The presentation set: everything that decides WHAT IS ON THE SCREEN and WHEN. The three
# this task implements, the two text opcodes already real in the port, and the geometry and
# input opcodes that bracket them on a title screen.
DEFAULT_WATCH = ("load.pic,draw.pic,show.pic,discard.pic,overlay.pic,"
                 "configure.screen,status.line.on,status.line.off,"
                 "display,display.v,print,print.v,clear.lines,"
                 "text.screen,graphics,new.room,new.room.v,"
                 "prevent.input,accept.input")

# VM_FLAG_OUTPUT_MODE [agi.h:297]. show.pic clears it; TextMgr::messageBox consumes it
# [text.cpp:373]. Nothing in the engine ever SETS it -- the game does. Sampled at each show.pic
# because clearing an already-clear flag is the case that makes the nine-title gate immovable.
FLAG_OUTPUT_MODE = 15


def resolve(names):
    """name -> opcode number, from the generated table. Unknown names are fatal."""
    by_name = {}
    for num, (name, _params, _handler) in enumerate(optable.V2_COMMANDS):
        by_name.setdefault(name, num)
    out, bad = [], []
    for n in names:
        if n in by_name:
            out.append((by_name[n], n))
        else:
            bad.append(n)
    if bad:
        print("★★★ not opcode names in the pinned V2 command table: %s" % ", ".join(bad))
        sys.exit(2)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=r"C:\Projects\agi-games\pc\Kingquest1")
    ap.add_argument("--version", default="0x2917")
    ap.add_argument("--cycles", type=int, default=40)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--watch", default=DEFAULT_WATCH)
    a = ap.parse_args()

    names = [s.strip() for s in a.watch.split(",") if s.strip()]
    watch = resolve(names)

    game = resource.load_from_files(a.game)
    vm = Vm(game, int(a.version, 0), seed=a.seed)

    events = []          # (cycle, logic, name, operands, room, flag15_before)
    unwrapped = []

    def wrap(op, fn, name):
        # ★★★★ THE OPERAND BYTES ARE NOT THE VALUES. display.v is "vvv" -- three VARIABLE
        # NUMBERS -- so printing the raw bytes reports v36 as though it were row 36, which is
        # off the bottom of a 25-row screen and would look like a defect that is not there.
        # Resolving through the param string is what turns this trace into a census of the rows
        # the game actually writes.
        params = op.params

        def recorder(vm_, p):
            shown = []
            for i, b in enumerate(p):
                kind = params[i] if i < len(params) else "?"
                if kind == "v":
                    shown.append("v%d=%d" % (b, vm_.state.vars[b]))
                else:
                    shown.append("%d" % b)
            events.append((vm_.cycle_nr, vm_.state.cur_logic_nr, name, bytes(p),
                           " ".join(shown), vm_.state.vars[0],
                           vm_.state.get_flag(FLAG_OUTPUT_MODE)))
            return fn(vm_, p)
        return recorder

    for num, name in watch:
        op = vm.table.commands[num]
        if op is None or op.handler is None:
            unwrapped.append((num, name))
            continue
        op.handler = wrap(op, op.handler, name)

    print("game    : %s" % a.game)
    print("watching: %d opcodes over %d cycles" % (len(watch) - len(unwrapped), a.cycles))
    if unwrapped:
        # ★★ Named, not silent: these are opcodes the run CANNOT report on.
        print("★★★ NOT WRAPPED (no handler bound -- this run is blind to them): %s"
              % ", ".join("%s($%02X)" % (n, v) for v, n in unwrapped))

    vm.start()
    status = 0
    try:
        vm.run(max_cycles=a.cycles)
    except OpcodeError as exc:
        print("HALTED: %s" % exc)
        status = 2

    print()
    print("cycle  logic  room  opcode              operands   resolved")
    print("-----  -----  ----  ------------------  ---------  --------------------------")
    prev_cycle = None
    for cyc, lg, name, p, resolved, room, _f15 in events:
        if prev_cycle is not None and cyc != prev_cycle:
            print("       ---- cycle boundary ----")
        prev_cycle = cyc
        ops = " ".join("%02X" % b for b in p) if p else "-"
        print("%5d  %5d  %4d  %-18s  %-9s  %s" % (cyc, lg, room, name, ops, resolved))

    print()
    counts = {}
    for _c, _l, name, _p, _res, _r, _f in events:
        counts[name] = counts.get(name, 0) + 1
    print("totals over %d cycles:" % a.cycles)
    for name in sorted(counts, key=lambda k: -counts[k]):
        print("    %-18s %d" % (name, counts[name]))
    if not counts:
        print("    (none of the watched opcodes executed)")

    # ── §6: can implementing show.pic's flag-15 clear move the nine-title gate? ──
    shows = [e for e in events if e[2] == "show.pic"]
    print()
    print("§6 -- show.pic executions: %d" % len(shows))
    if shows:
        set_at = [e for e in shows if e[6]]
        print("     flag 15 already CLEAR at show.pic: %d of %d" % (len(shows) - len(set_at),
                                                                    len(shows)))
        print("     flag 15 SET at show.pic (a real change): %d" % len(set_at))
        for e in set_at:
            print("       cycle %d logic %d" % (e[0], e[1]))
    else:
        print("     ★★ no show.pic in this window -- this run is EVIDENCE OF NOTHING about the")
        print("        flag-15 clear, and must not be cited as though it were [§2W].")
    sys.exit(status)


if __name__ == "__main__":
    main()
