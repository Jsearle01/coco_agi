#!/usr/bin/env python3
"""harness/tools/print_reach_census.py -- which ROOM logics print on entry? [T-P0-086 §4A]

★★★★★ THE QUESTION THAT DECIDES WHETHER THE WAIT LOOP CAN BE GATED AT ALL. P6.29c measured that
no title executes print ($65/$66) from its intro: NEVER at 3,000 cycles, and 0 of 59 synthesisable
said() lines. The blocking window, and the -DTEXT_FAULT_NOTICK arm built to falsify it, are
therefore unexercised assertions [§2W].

★★★★ EVERY EARLIER MEASUREMENT RAN IN THE INTRO ROOM. p3b_room.lua can jump rooms through the
game's own dispatch, so the cheap question -- never asked -- is whether some ROOM prints on entry.
This answers it STATICALLY, before anything is jumped: a dynamic sweep over every room of nine
titles is expensive, and a static census turns it into a handful of ranked candidates.

★★★ THREE COLUMNS, AND THE SECOND IS THE ONE THAT MATTERS:
  1. does the room's logic contain $65/$66 at all?
  2. is any of them on the ENTRY PATH -- i.e. NOT behind a said() guard? A print behind said() is
     another playthrough problem wearing a different hat.
  3. does an opcode the reference does not implement sit on that path BEFORE the print? PoliceQuest1
     is the warning: its gameplay-shaped patterns reach command opcode 75 and raise. A room that
     raises before it prints is not a candidate.

★★★★★ THIS IS A RANKING INSTRUMENT, NOT A VERDICT, AND THE OVER-APPROXIMATION IS DELIBERATE.
"not behind said()" is weaker than "executes on entry": a print guarded by `if (isset(<flag>))` is
counted here and may not fire on a cold jump. **So the census proposes and §4B disposes** -- every
candidate is confirmed dynamically before it is believed. Reporting a candidate that fails
confirmation is cheap; excluding a real one by over-tight static reasoning is not.

★★ §2P: logic numbers, addresses, opcode numbers and counts. No message text, ever.

usage:
  python harness/tools/print_reach_census.py [--titles A,B] [--games-root DIR] [--max-rooms N]
"""
import argparse
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "harness" / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from agivm import cycle as cycle_mod            # noqa: E402
from volread import logic as logic_mod, resource  # noqa: E402

import agidis                                   # noqa: E402

DEFAULT_TITLES = ("Kingquest1", "Kingquest2", "Kingquest3", "SpaceQuest-1", "SpaceQuest-2",
                  "PoliceQuest1", "larry1", "BlackCauldron", "MixedUpMotherGoose")
PRINT_NAMES = ("print(", "print.v(")


def unimplemented_commands(game):
    """The command opcodes the REFERENCE does not implement -- read from the table, not a list.

    ★★★ A hard-coded set would go stale the moment an opcode lands, and would do it silently: the
    census would keep excluding a room that had become reachable. Asking the table costs one Vm.
    """
    vm = cycle_mod.Vm(game, 0x2917)
    bad = set()
    for num, op in enumerate(vm.table.commands):
        if op is None or getattr(op, "handler", None) is None:
            bad.add(num)
    return bad, vm


def has_picture(game, nr):
    """Does a PICTURE exist for this room number?

    ★★★★★ THE COLUMN THE FIRST CENSUS LACKED, AND IT COST A CONFIRMED-LOOKING CANDIDATE.
    PoliceQuest1 room 97 is `print.v(v131); return()` -- unconditional, prints 112 times in the
    offline reference, jump lands and dispatches. **On the 6809 probe it gives res_err 1 =
    RES_E_EMPTY**, the DIR slot is FF FF FF: there is no PICTURE 97. It is a message-only logic
    called by other logics, not a room anything can be IN.
    ★★★★ The offline reference never noticed because it does not RENDER; p3b does, every cycle.
    **So "the reference prints here" is not sufficient for a jump target on the integration probe**
    -- the two legs ask different things of a room number, and only one of them draws it.
    ★★★★★ AND THE FIRST VERSION OF THIS FUNCTION COULD NOT FAIL [§2W]. It asked `game.entry(...)`
    and returned `e is not None` -- but entry() returns a row for an EMPTY slot too; emptiness is
    detected in load(), which raises "%s %d is an empty slot" (resource.py:92). So the column read
    True for all 476 candidates, including PoliceQuest1 97 whose PICTURE the probe had just
    reported as RES_E_EMPTY. **A column that agrees with every row is not a filter.**
    ★★★ Asking load() reuses the reference's own emptiness test rather than reimplementing the
    FF FF FF check here [§2F]. It costs a resource read per room; the census runs in seconds.
    """
    try:
        game.load("PICTURE", nr)
    except Exception:                                   # noqa: BLE001
        return False
    return True


def walk(code):
    """agidis' decoder, plus the branch target and the opcode number it does not expose.

    ★★ REUSING agidis.disassemble RATHER THAN RE-DECODING [§2F]. Its own header says the decoder is
    deliberately the same table the VM dispatches on, so a second walk here would be a second thing
    to keep in step. What it does not yield is the `if` TARGET (its text carries `+size`) or the raw
    opcode byte -- both recoverable: the target is the NEXT instruction's address plus size, and the
    opcode is code[addr].
    """
    instrs = list(agidis.disassemble(code))
    out = []
    for i, (addr, kind, text, args) in enumerate(instrs):
        target = None
        if kind == "if":
            size = int(text.rsplit("+", 1)[1].rstrip(")")) if "+" in text else 0
            nxt = instrs[i + 1][0] if i + 1 < len(instrs) else len(code)
            target = nxt + size
        out.append((addr, kind, text, args, target, code[addr] if addr < len(code) else None))
    return out


def analyse(code, bad_ops):
    """-> dict with the three columns for one logic.

    ★★★ GUARDS BY A NESTING STACK. AGI emits `if (cond) goto +size` with the body in
    [next_addr, next_addr+size), and the bodies nest. Walking linearly and popping the stack when
    an address passes a recorded end gives, for every instruction, the list of conditions guarding
    it -- which is exactly what "behind a said()" needs.
    ★★ The `else` arm is a trailing goto inside the body and does not break the nesting for this
    purpose; it can only make a guard list LONGER, never drop a said(). Over-approximation again in
    the safe direction.
    """
    res = {"prints": [], "entry_prints": [], "bad_seen": [], "decode_stopped": False,
           "first_entry_print": None, "blocked_by": None}
    stack = []
    for addr, kind, text, _args, target, opnum in walk(code):
        while stack and addr >= stack[-1][0]:
            stack.pop()
        if kind == "bad":
            res["decode_stopped"] = True
            break
        if kind == "if":
            if target is not None and target > addr:
                stack.append((target, text))
            continue
        if kind != "cmd":
            continue
        guards = [c for _e, c in stack]
        on_entry = not any("said(" in g for g in guards)
        if any(text.startswith(p) for p in PRINT_NAMES):
            res["prints"].append(addr)
            if on_entry:
                res["entry_prints"].append(addr)
                if res["first_entry_print"] is None:
                    res["first_entry_print"] = addr
        elif opnum in bad_ops and on_entry:
            # ★ only counts if it sits BEFORE the first entry print: an unimplemented opcode
            # after the box has already been drawn cannot stop the box being drawn.
            if res["first_entry_print"] is None:
                res["bad_seen"].append((addr, opnum))
    if res["first_entry_print"] is not None and res["bad_seen"]:
        res["blocked_by"] = res["bad_seen"][0][1]
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--games-root", default="C:/Projects/agi-games/pc")
    ap.add_argument("--titles", default=",".join(DEFAULT_TITLES))
    ap.add_argument("--max-rooms", type=int, default=0, help="0 = every LOGIC present")
    ap.add_argument("--top", type=int, default=8, help="candidates to print per title")
    a = ap.parse_args()

    root = pathlib.Path(a.games_root)
    all_candidates = []
    for title in [t.strip() for t in a.titles.split(",") if t.strip()]:
        d = root / title
        if not d.is_dir():
            print("%-20s  no directory" % title)
            continue
        game = resource.load_from_files(str(d))
        bad_ops, _vm = unimplemented_commands(game)
        rows, scanned, failed = [], 0, 0
        for nr in range(256):
            if a.max_rooms and scanned >= a.max_rooms:
                break
            try:
                raw = game.load("LOGIC", nr)
            except Exception:                               # noqa: BLE001
                continue
            if raw is None:
                continue
            scanned += 1
            try:
                lg = logic_mod.split(raw, index=nr)
                r = analyse(lg.bytecode, bad_ops)
            except Exception:                               # noqa: BLE001
                failed += 1
                continue
            # ★ logic 0 is the GLOBAL handler, not a room. It is scanned and reported but never
            # offered as a jump target: jumping "to room 0" is not a thing.
            if r["prints"]:
                rows.append((nr, r))
        print("═══ %s ═══  %d LOGIC resources, %d undecodable, "
              "%d unimplemented command opcodes in the reference"
              % (title, scanned, failed, len(bad_ops)))
        pre = [(nr, r) for nr, r in rows
               if nr != 0 and r["entry_prints"] and not r["blocked_by"]]
        # ★★★★ A ROOM THE PROBE CAN ACTUALLY BE IN. Without a PICTURE the integration probe's
        # room render reports RES_E_EMPTY and the run never reaches print -- see has_picture().
        cands = [(nr, r) for nr, r in pre if has_picture(game, nr)]
        cands.sort(key=lambda t: (t[1]["first_entry_print"], t[0]))
        print("  logics containing print      : %d" % len(rows))
        print("  ... with a print on the ENTRY path (not behind said()) : %d"
              % len([1 for nr, r in rows if r["entry_prints"]]))
        print("  ... blocked by an unimplemented opcode first           : %d"
              % len([1 for nr, r in rows if r["entry_prints"] and r["blocked_by"]]))
        print("  ... with NO PICTURE (message-only logic, not a room)   : %d"
              % (len(pre) - len(cands)))
        print("  CANDIDATE rooms (entry print, opcode-clean, HAS a picture): %d" % len(cands))
        if cands:
            print("    %-6s %-8s %-8s %-9s %s" % ("room", "prints", "entry", "first@", "note"))
            for nr, r in cands[:a.top]:
                print("    %-6d %-8d %-8d $%04X     %s"
                      % (nr, len(r["prints"]), len(r["entry_prints"]), r["first_entry_print"],
                         "decode stopped early" if r["decode_stopped"] else ""))
            for nr, r in cands:
                all_candidates.append((title, nr, r["first_entry_print"], len(r["entry_prints"])))
        blocked = [(nr, r) for nr, r in rows if r["entry_prints"] and r["blocked_by"]]
        if blocked:
            ops = sorted({r["blocked_by"] for _nr, r in blocked})
            print("    blocked rooms reach unimplemented command opcode(s): %s"
                  % ", ".join(str(o) for o in ops))
        print()

    print("═══ RANKED ACROSS ALL TITLES (earliest entry print first) ═══")
    if not all_candidates:
        print("★★★ CENSUS EMPTY -- no room in any title prints on its entry path.")
        print("    That retires the room-jump option on evidence. A trigger would need a")
        print("    scripted playthrough, which is a dispatch-level decision [T-P0-086 §6].")
        return 1
    all_candidates.sort(key=lambda t: (t[2], t[0], t[1]))
    print("  %-20s %-6s %-9s %s" % ("title", "room", "first@", "entry prints"))
    for title, nr, first, cnt in all_candidates[:25]:
        print("  %-20s %-6d $%04X     %d" % (title, nr, first, cnt))
    print("")
    print("★ %d candidate room(s) across %d title(s). §4B confirms these dynamically;"
          % (len(all_candidates), len({c[0] for c in all_candidates})))
    print("  the census RANKS, it does not decide [see this file's header].")
    return 0


if __name__ == "__main__":
    sys.exit(main())
