#!/usr/bin/env python3
"""harness/tools/timedelay_census.py -- AC-6: what cycle rate does the CORPUS actually ask for?

★★★★ THE QUESTION AND WHY IT IS NOT RHETORICAL. Every budget in this project is measured
against 200 ms per cycle, which is AGI's ~5 cycles/second. **That figure is
VM_VAR_TIME_DELAY's DEFAULT, not a law** -- var 10 is an ordinary game variable and LOGIC
writes to it. If the shipped titles routinely ask for a SLOWER cycle, the 200 ms budget is an
assumption about AGI rather than a requirement of it, and both of P3b's overruns shrink.

★★★ STATIC, FROM tools/volread/, AND THAT IS A LIMITATION WORTH STATING. This counts what the
bytecode CAN write, not what a playthrough DOES write: a `assignn v10, 8` inside a branch that
never runs still counts here. **So the output is an upper bound on variety and says nothing
about frequency in play.** The observed alternative -- instrumenting the reference and playing
-- would answer a different and better question, and is named as follow-up rather than faked.

★★ WHAT COUNTS AS A WRITE TO var 10. Four opcodes, from tools/agivm/optable.py:
    0x01 increment v      0x02 decrement v
    0x03 assignn  v, n    (the one that carries a VALUE)
    0x04 assignv  v1, v2  (value not statically known)
Plus 0x05/0x06 addn/addv and 0x07/0x08 subn/subv, which adjust rather than set.
★ Only assignn yields a literal, so the VALUE histogram is assignn's; the others are counted
as "written, value not static" and reported separately rather than dropped.

★ The game directory is opened READ-ONLY (CLAUDE.md §2P).
"""
import argparse
import collections
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from volread import resource                    # noqa: E402
from volread import logic as logic_mod          # noqa: E402

sys.path.insert(0, str(ROOT / "harness" / "tools"))
from agidis import disassemble                  # noqa: E402

# ★★★★ THE FIRST VERSION OF THIS SCANNER RETURNED ZERO WRITES ACROSS ALL NINE TITLES AND THAT
# WAS THE INSTRUMENT, NOT THE CORPUS [L-56]. It walked the command stream linearly and stopped
# at the first `if` (0xFF) or `goto` (0xFE) because their operand shape differs from an ordinary
# command's -- and in AGI logic the first conditional arrives within a few dozen bytes, so it
# was scanning the prologue of each LOGIC and nothing else.
# ★★★ A clean, plausible, total zero. **It read as "the corpus never sets the time delay",
# which is exactly the answer that would have made this AC trivial and would have been wrong.**
# The disproof took one command: `agidis.py Kingquest1 0 --grep-var 10` prints
# `001A  assignv(v10, v88)` -- a write my scanner had walked straight past.
# ★★ So this now uses the project's OWN disassembler, which decodes conditionals properly and
# is the parser the VM gate is built on. **Reusing the gated parser beats writing a second one**
# -- the second one is where the divergence lives.

VAR_TIME_DELAY = 10

# ★ (opcode, operand-count, kind). Kind 'set-literal' is the only one with a knowable value.
WRITERS = {
    0x01: (1, "increment"),
    0x02: (1, "decrement"),
    0x03: (2, "set-literal"),
    0x04: (2, "set-from-var"),
    0x05: (2, "add-literal"),
    0x06: (2, "add-from-var"),
    0x07: (2, "sub-literal"),
    0x08: (2, "sub-from-var"),
}


NAMES = {"increment": "increment", "decrement": "decrement",
         "assignn": "set-literal", "assignv": "set-from-var",
         "addn": "add-literal", "addv": "add-from-var",
         "subn": "sub-literal", "subv": "sub-from-var"}


def scan_logic(code):
    """Every write to var 10, via the project's own disassembler.

    ★ A write is an instruction from NAMES whose FIRST operand is var 10. Only `assignn` and
    the other -literal forms carry a value; the rest are counted by kind and reported without
    one rather than guessed at.
    """
    out = []
    for _addr, kind, text, args in disassemble(code):
        if kind != "cmd" or not args or args[0] != VAR_TIME_DELAY:
            continue
        name = text.split("(", 1)[0]
        if name not in NAMES:
            continue
        k = NAMES[name]
        val = args[1] if (k.endswith("literal") and len(args) > 1) else None
        out.append((k, val, text))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("games_root")
    ap.add_argument("--titles", default="Kingquest1,Kingquest2,Kingquest3,PoliceQuest1,"
                                        "SpaceQuest-1,SpaceQuest-2,larry1,"
                                        "MixedUpMotherGoose,BlackCauldron")
    args = ap.parse_args()

    grand_vals = collections.Counter()
    grand_kinds = collections.Counter()
    print(f"{'title':<22} {'logics':>7} {'writes':>7}  values written to var 10 (assignn)")
    print("-" * 78)
    for t in args.titles.split(","):
        d = pathlib.Path(args.games_root) / t
        try:
            game = resource.load_from_files(str(d))
        except Exception as exc:                             # noqa: BLE001
            print(f"{t:<22} {'--':>7} {'--':>7}  SKIPPED: {type(exc).__name__}")
            continue
        vals = collections.Counter()
        kinds = collections.Counter()
        nlog = 0
        for idx in range(256):
            try:
                raw = game.load("LOGIC", idx)
            except Exception:                                # noqa: BLE001
                continue
            nlog += 1
            # ★★★★ NO BARE `except: continue` HERE, AND THAT IS THE SECOND FALSE ZERO THIS FILE
            # PRODUCED. The attribute is `lg.bytecode`; I wrote `lg.code`, and the surrounding
            # try/except swallowed the AttributeError on every LOGIC of every title -- **90
            # silent failures presented as "Kingquest1: 0 writes".**
            # ★★★ Identical in shape to the pool's `absent-tool-with-suppressed-stderr-emits-a-
            # false-zero`: the error path and the legitimate empty result were made
            # indistinguishable by the handler. A parse failure must be COUNTED, not skipped.
            lg = logic_mod.split(raw, index=idx)
            for kind, val, _txt in scan_logic(lg.bytecode):
                kinds[kind] += 1
                if val is not None:
                    vals[val] += 1
        grand_vals.update(vals)
        grand_kinds.update(kinds)
        shown = "  ".join(f"{v}x{c}" for v, c in sorted(vals.items())) or "(none)"
        print(f"{t:<22} {nlog:>7} {sum(kinds.values()):>7}  {shown}")

    print("-" * 78)
    print("\n★ value histogram across the corpus (assignn v10, n):")
    tot = sum(grand_vals.values())
    for v, c in sorted(grand_vals.items()):
        # ★★★★ THE MODEL DOUBLES THE DELAY, AND MISSING THAT HALVED EVERY RATE HERE.
        # tools/agivm/cycle.py run() is explicit:
        #     self.virtual_ms += 25 ; passed += 1
        #     time_delay = self.get_var(VM_VAR_TIME_DELAY) * 2
        #     if not time_delay: time_delay = 1
        #     if passed >= time_delay: interpret_cycle()
        # ★★★ So a cycle runs every max(1, 2*v10) steps of 25 ms -- and v10 = 4 gives exactly
        # 200 ms, which is where the dispatch's "AGI's ~5 cycles per second" comes from. That
        # correspondence is the check that this arithmetic is now right: the model has to
        # reproduce the known default, and the first version (1000/(25*v)) did not.
        steps = max(1, 2 * v)
        ms = 25.0 * steps
        print(f"    v10 = {v:>3}   {c:>4} site(s)  {100.0*c/tot:5.1f}%"
              f"   -> {ms:6.0f} ms/cycle = {1000.0/ms:5.1f} cyc/s")
    print("\n★ write kinds (a write whose value is not a literal cannot be histogrammed):")
    for k, c in grand_kinds.most_common():
        print(f"    {k:<16} {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
