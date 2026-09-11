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
# ★★ The room-jump pair, named rather than inlined, and matching p3b_room.lua:11-13 and :49-51.
VAR_CURRENT_ROOM = 0
FLAG_NEW_ROOM_EXEC = 5


def parse_set_vars(s):
    """'17=1,20=3' -> [(17, 1), (20, 3)]"""
    out = []
    for part in [p.strip() for p in s.split(",") if p.strip()]:
        k, _, v = part.partition("=")
        out.append((int(k), int(v)))
    return out


def first_print(game_dir, max_cycles, room=None, room_at=8, game=None, set_vars=()):
    """-> dict: first print cycle, hits, rooms, and the room jump's LANDING evidence.

    ★★★★★ THE ROOM JUMP IS THE GAME'S OWN DISPATCH, NOT A NEW MECHANISM [AD-99, T-P0-048 B].
    AGI routes a room change through VAR_CURRENT_ROOM (var 0) and FLAG_NEW_ROOM_EXEC (flag 5), and
    logic.0 tests flag 5 every cycle -- so setting both makes the game dispatch the room itself.
    ★★★ Deliberately the SAME two writes p3b_room.lua makes (`harness/tools/p3b_room.lua:49-51`),
    so the offline confirmation and the MAME arm jump identically [§2F].

    ★★★★★ AND IT IS VERIFIED TO HAVE LANDED, IN BOTH DIRECTIONS [L-56]. p3b_room.lua's own header
    records the precedent: a jump written to the wrong address reported "the room jump does nothing"
    and read as a negative result. Two checks here:
      wrote_ok   -- var 0 and flag 5 read back as written, immediately (the write took)
      dispatched -- flag 5 was CLEARED by the time the run ended (logic.0 SAW it and dispatched)
    ★★★★ The second is the one that matters. A write that lands in the right byte and is never
    looked at is indistinguishable from a jump that worked, until you ask whether anything consumed
    it. **A landing check that only confirms its own write cannot fail** [§2W.3].
    """
    if game is None:
        game = resource.load_from_files(game_dir)
    vm = cycle_mod.Vm(game, 0x2917)
    seen = {"first": None, "hits": 0, "flag15_at_first": None}
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
                # ★★★★★ WHICH BRANCH DOES messageBox TAKE? [T-P0-086 §4C]. text.cpp:373 tests
                # VM_FLAG_OUTPUT_MODE (flag 15, agi.h:297) ABOVE the wait: set -> draw the box,
                # consume the flag, return WITHOUT blocking. So "print executed" and "print
                # blocked" are different facts, and only the second can turn the fault arm red.
                # ★★★★ Recorded at the FIRST hit, because the handler consumes the flag -- reading
                # it afterwards cannot distinguish "was never set" from "was set and used".
                if seen["flag15_at_first"] is None:
                    try:
                        seen["flag15_at_first"] = bool(vm.state.get_flag(15))
                    except Exception:                   # noqa: BLE001
                        pass
                if seen["first"] is None:
                    # ★ vm.cycle_nr is incremented by interpret_cycle() before the body runs, so
                    # the BODY number -- the one a feed schedule and p3b_run.lua both use -- is
                    # one less. Same convention as vm_input_script.py's census.
                    seen["first"] = max(0, getattr(vm, "cycle_nr", 0) - 1)
                return h(*args, **kw)
            return wrapped
        op.handler = make()

    err = None
    jump = {"asked": room, "at": room_at, "room_before": None,
            "wrote_ok": None, "dispatched": None}
    try:
        vm.start()
        if room is None:
            vm.run(max_cycles=max_cycles)
        else:
            # ── run up to the jump point, poke, verify, continue ──
            vm.run(max_cycles=room_at)
            jump["room_before"] = vm.get_var(0)
            vm.set_var(VAR_CURRENT_ROOM, room)
            vm.state.set_flag(FLAG_NEW_ROOM_EXEC, True)
            # ★★★★★ THE ERROR ROOM NEEDS ITS ERROR CODE, OR IT PRINTS NOTHING [T-P0-086 §4C].
            # The reachable rooms are all `print.v(v17); quit(1)` -- AGI's error room -- and
            # commands.py:902 resolves that to get_message(logic, var17 - 1). Cold-jumped, var 17
            # is 0 and the index is -1: the handler runs, so a census counting HANDLER ENTRIES sees
            # a print, and no box is drawn. **"print executed" and "a message box was drawn" are
            # different facts and the first does not imply the second** -- which is why the port
            # reached `quit` (vm_quit=1) with var 21 untouched.
            # ★★★ So the trigger sets var 17 as well, which is what the GAME does before sending
            # itself here. Same class of poke as var 0 and flag 5: the game's own state, written by
            # the host, dispatched by the game [AD-99].
            for vn, vv in set_vars:
                vm.set_var(vn, vv)
            jump["wrote_ok"] = (vm.get_var(VAR_CURRENT_ROOM) == room
                                and bool(vm.state.get_flag(FLAG_NEW_ROOM_EXEC)))
            vm.run(max_cycles=max_cycles)
            jump["dispatched"] = not bool(vm.state.get_flag(FLAG_NEW_ROOM_EXEC))
    except Exception as exc:                            # noqa: BLE001
        err = str(exc).split("(")[0].strip()
        if room is not None and jump["dispatched"] is None:
            try:
                jump["dispatched"] = not bool(vm.state.get_flag(FLAG_NEW_ROOM_EXEC))
            except Exception:                           # noqa: BLE001
                pass
    finally:
        for num, h in saved.items():
            vm.table.commands[num].handler = h
    return {"first": seen["first"], "hits": seen["hits"], "room": vm.get_var(0),
            "flag15": seen["flag15_at_first"], "var21": vm.get_var(21),
            "ran": getattr(vm, "cycle_nr", 0), "err": err, "jump": jump}


def main():
    ap_ = argparse.ArgumentParser()
    ap_.add_argument("--games-root", default="C:/Projects/agi-games/pc")
    ap_.add_argument("--titles", default=",".join(DEFAULT_TITLES))
    ap_.add_argument("--cycles", type=int, default=3000)
    # ★★★ --rooms: confirm §4A's static candidates dynamically. The census RANKS by "contains a
    # print not behind said()", which is an over-approximation on purpose; this is what decides.
    ap_.add_argument("--rooms", default="", help="comma-separated rooms to jump to, one run each")
    ap_.add_argument("--room-at", type=int, default=8, help="cycle to jump at (p3b_room.lua's 8)")
    ap_.add_argument("--repeat", type=int, default=1,
                     help="runs per room -- ★ a trigger that fires once is not a gate [§4B]")
    ap_.add_argument("--set-var", default="",
                     help="'17=1' -- game state to write with the jump; see first_print()")
    a = ap_.parse_args()
    set_vars = parse_set_vars(a.set_var)

    root = pathlib.Path(a.games_root)
    titles = [t.strip() for t in a.titles.split(",") if t.strip()]
    rooms = [int(r) for r in a.rooms.split(",") if r.strip()]

    if not rooms:
        print("first print ($65/$66) with NO INPUT, %d cycles max" % a.cycles)
        print("%-22s %10s %8s %6s %8s  %s" % ("title", "first", "hits", "room", "ran", "note"))
        found = 0
        for t in titles:
            d = root / t
            if not d.is_dir():
                print("%-22s %10s" % (t, "no dir"))
                continue
            r = first_print(str(d), a.cycles)
            if r["first"] is not None:
                found += 1
            print("%-22s %10s %8d %6d %8d  %s"
                  % (t, "cycle %d" % r["first"] if r["first"] is not None else "NEVER",
                     r["hits"], r["room"], r["ran"], r["err"] or ""))
        print("")
        if not found:
            print("★★★ NO TITLE REACHES print FROM ATTRACT MODE in %d cycles." % a.cycles)
            print("    The blocking window cannot be exercised by running a title from its start;")
            print("    the gate needs a driven path, and that is a dispatch-level decision.")
            return 1
        return 0

    # ── room-jump confirmation ──────────────────────────────────────────────────────────
    print("room-jump confirmation: jump at cycle %d, %d cycles max, %d run(s) each"
          % (a.room_at, a.cycles, a.repeat))
    print("★ landing evidence per run: wrote = var0/flag5 read back as written;")
    print("  dispatched = flag 5 CLEARED by the run's end, i.e. logic.0 consumed it [L-56]")
    print("")
    print("%-20s %5s %4s %10s %7s %6s %6s %7s  %s"
          % ("title", "room", "run", "first", "hits", "wrote", "disp", "f15", "note"))
    good = 0
    for t in titles:
        d = root / t
        if not d.is_dir():
            continue
        # ★ Loaded ONCE per title: resource.load_from_files is the expensive half and the Vm is
        # rebuilt per run anyway, so each run still starts from a clean interpreter state.
        game = resource.load_from_files(str(d))
        for room in rooms:
            for run_i in range(1, a.repeat + 1):
                r = first_print(str(d), a.cycles, room=room, room_at=a.room_at, game=game,
                                set_vars=set_vars)
                j = r["jump"]
                ok = r["first"] is not None and j["wrote_ok"] and j["dispatched"]
                if ok:
                    good += 1
                # ★★★ f15 = VM_FLAG_OUTPUT_MODE at the FIRST print. "set" means the oracle takes
                # text.cpp:375's non-blocking branch -- the box is drawn and NOT waited on -- so
                # such a room cannot turn the fault arm red however many times it prints.
                print("%-20s %5d %4d %10s %7d %6s %6s %7s  %s"
                      % (t, room, run_i,
                         "cycle %d" % r["first"] if r["first"] is not None else "NEVER",
                         r["hits"],
                         "yes" if j["wrote_ok"] else "★★★NO",
                         "yes" if j["dispatched"] else "★★★NO",
                         "-" if r["flag15"] is None else ("SET" if r["flag15"] else "clear"),
                         r["err"] or ("room %d" % r["room"])))
    print("")
    if not good:
        print("★★★ NO CANDIDATE ROOM PRODUCED A print WITH A LANDED JUMP.")
        print("    Either the jump did not take (check `wrote`/`disp`) or the static census")
        print("    over-approximated. Report which, per §4B; do not tune.")
        return 1
    print("★ %d confirmed run(s): jump landed, was dispatched, and print executed." % good)
    return 0


if __name__ == "__main__":
    sys.exit(main())
