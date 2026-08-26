#!/usr/bin/env python3
"""Disassemble an AGI LOGIC resource using the generated opcode table.

Exists to answer "what wrote variable N?" when the state diff reports a divergence. Reading
the bytecode is the only way to distinguish "our opcode is wrong" from "we never executed that
instruction", and those need different fixes.

★ The decoder here is the SAME table the VM dispatches on, so a disassembly that desynchronises
is evidence the VM would desynchronise too -- it is not an independent reimplementation, and
that is deliberate.

Usage:
    python harness/tools/agidis.py <game-dir> <logic-nr> [--grep-var N] [--grep-flag N]
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from agivm import optable                      # noqa: E402
from volread import logic as logic_mod, resource  # noqa: E402


def disassemble(code):
    """Yield (addr, kind, text, params) for each instruction."""
    ip = 0
    n = len(code)
    while ip < n:
        addr = ip
        op = code[ip]
        ip += 1
        if op == 0xFF:
            ops, ip = _decode_condition(code, ip)
            size = int.from_bytes(code[ip:ip + 2], "little")
            ip += 2
            yield addr, "if", "if (%s) goto +%d" % (" ".join(ops), size), ()
            continue
        if op == 0xFE:
            off = int.from_bytes(code[ip:ip + 2], "little", signed=True)
            ip += 2
            yield addr, "goto", "goto %04X" % (ip + off), ()
            continue
        if op == 0x00:
            yield addr, "return", "return()", ()
            continue
        entry = optable.V2_COMMANDS[op] if op < len(optable.V2_COMMANDS) else None
        if entry is None:
            yield addr, "bad", "<illegal %02X>" % op, ()
            return
        name, params, _ = entry
        args = tuple(code[ip:ip + len(params)])
        ip += len(params)
        yield addr, "cmd", "%s(%s)" % (name, ", ".join(
            ("v%d" % a) if t == "v" else str(a) for t, a in zip(params, args))), args


def _decode_condition(code, ip):
    """Decode a test expression up to its terminating 0xFF. Returns (tokens, new_ip)."""
    out = []
    while True:
        op = code[ip]
        ip += 1
        if op == 0xFF:
            return out, ip
        if op == 0xFC:
            out.append("||")
            continue
        if op == 0xFD:
            out.append("!")
            continue
        entry = optable.V2_TESTS[op] if op < len(optable.V2_TESTS) else None
        if entry is None:
            out.append("<illegal %02X>" % op)
            return out, ip
        name, params, _ = entry
        if op == optable.SAID_TEST_OPCODE:
            cnt = code[ip]
            ip += 1
            words = [int.from_bytes(code[ip + 2 * i:ip + 2 * i + 2], "little")
                     for i in range(cnt)]
            ip += cnt * 2
            out.append("said(%s)" % ",".join(str(w) for w in words))
            continue
        args = tuple(code[ip:ip + len(params)])
        ip += len(params)
        out.append("%s(%s)" % (name, ",".join(
            ("v%d" % a) if t == "v" else str(a) for t, a in zip(params, args))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("logic_nr", type=int)
    ap.add_argument("--grep-var", type=int, default=None,
                    help="only show instructions mentioning this variable number")
    ap.add_argument("--grep-flag", type=int, default=None)
    args = ap.parse_args()

    game = resource.load_from_files(args.game_dir)
    lg = logic_mod.split(game.load("LOGIC", args.logic_nr), index=args.logic_nr)
    print("logic %d: %d bytes of bytecode, %d messages"
          % (args.logic_nr, len(lg.bytecode), len(lg.messages)))
    print()

    want = args.grep_var if args.grep_var is not None else args.grep_flag
    shown = 0
    for addr, kind, text, argvals in disassemble(lg.bytecode):
        if want is not None:
            # match the variable/flag number appearing as an operand or inside a condition
            hit = (want in argvals) or ("v%d" % want in text) or ("(%d" % want in text) \
                or (",%d" % want in text) or (" %d" % want in text)
            if not hit:
                continue
        print("  %04X  %s" % (addr, text))
        shown += 1
    if want is not None:
        print()
        print("  %d instruction(s) mentioning %d" % (shown, want))
    return 0


if __name__ == "__main__":
    sys.exit(main())
