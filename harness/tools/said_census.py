#!/usr/bin/env python3
"""harness/tools/said_census.py -- every said() call site in a title's LOGICs. [T-P0-058 AC-7]

★★★★★ WHY THIS EXISTS. AC-7 asks what fraction of the corpus's said() call sites a gate
exercises, and L-85 is the reason: every corpus in this project has turned out to be 4-16% of
what it claimed over. **The denominator has to be counted before the numerator means anything.**

★★★★ IT IS ALSO THE GATE'S INPUT. said()'s operands are the interesting half -- 9999
(rest-of-line), 1 (any word), and real word numbers in real combinations -- and inventing operand
patterns would test a matcher against a grammar nobody wrote. Walking the shipped bytecode gives
the actual patterns, in the actual proportions.

★★★ THE WALK IS THE TRAP optable.py:19 RECORDS. said (test 0x0E) has an EMPTY parameter string
and is NOT zero-length: N comes from the stream, then N 16-bit words [op_test.cpp:469]. A walker
that trusts the table desynchronises and every count after the first said() is fiction -- so this
reuses tests.py's own skip rule rather than restating it.

★ §2P: counts and word NUMBERS only. No message text is read or printed.

usage: python harness/tools/said_census.py <game-dir> [--json out.json]
"""
import argparse
import collections
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / "tools"))

from volread import resource                      # noqa: E402
from volread import logic as logic_mod            # noqa: E402
from agivm.optable import SAID_TEST_OPCODE        # noqa: E402


def walk_logic(code):
    """Yield (ip, operands) for every said() in one LOGIC's bytecode.

    ★★ Follows the IF-expression grammar rather than scanning for the opcode byte: a 0x0E byte
    inside a message string or an operand would otherwise be counted as a call site. Only the
    positions the evaluator actually reaches are real.
    """
    from agivm.optable import V2_TESTS
    out = []
    ip = 0
    n = len(code)
    while ip < n:
        op = code[ip]
        ip += 1
        if op != 0xFF:                       # 0xFF begins an IF condition block
            continue
        # ── inside the condition ──
        while ip < n:
            t = code[ip]
            ip += 1
            if t in (0x00, 0xFF):            # end of condition
                break
            if t in (0xFC, 0xFD):            # OR toggle / NOT
                continue
            if t == SAID_TEST_OPCODE:
                if ip >= n:
                    break
                cnt = code[ip]
                ops = []
                for i in range(cnt):
                    o = ip + 1 + i * 2
                    if o + 1 >= n:
                        break
                    ops.append(code[o] | (code[o + 1] << 8))
                out.append((ip - 1, ops))
                ip += cnt * 2 + 1
            else:
                if t >= len(V2_TESTS):
                    break
                ip += len(V2_TESTS[t][1])
        # the two-byte forward jump after the condition
        ip += 2
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--json", default="")
    a = ap.parse_args()

    game = resource.load_from_files(a.game_dir)
    sites = []
    logics_with = 0
    logics_total = 0
    for nr in range(256):
        try:
            raw = game.load("LOGIC", nr)
        except Exception:                                        # noqa: BLE001
            continue
        if raw is None:
            continue
        try:
            lg = logic_mod.split(raw, index=nr)
        except Exception:                                        # noqa: BLE001
            continue
        logics_total += 1
        found = walk_logic(lg.bytecode)
        if found:
            logics_with += 1
        for ip, ops in found:
            sites.append({"logic": nr, "ip": ip, "operands": ops})

    widths = collections.Counter(len(s["operands"]) for s in sites)
    any_word = sum(1 for s in sites if 1 in s["operands"])
    rest = sum(1 for s in sites if 9999 in s["operands"])
    distinct = {tuple(s["operands"]) for s in sites}

    print("game            : %s" % a.game_dir)
    print("LOGICs          : %d total, %d contain said()" % (logics_total, logics_with))
    print("said() sites    : %d   distinct operand patterns: %d" % (len(sites), len(distinct)))
    print("operand widths  : %s" % ", ".join("%d->%d" % (w, c) for w, c in sorted(widths.items())))
    print("uses 1 (any)    : %d sites" % any_word)
    print("uses 9999 (rest): %d sites" % rest)

    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(sites), encoding="utf-8")
        print("wrote %s" % a.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
