"""harness/tools/string_census.py -- how much string table does the corpus ACTUALLY use? [P6.20]

★★★★★ AC-3 ASKS FOR THE SPACE BEFORE THE CODE, AND THE STRING TABLE IS THE ROW THAT DECIDES IT.
The oracle declares `char strings[MAX_STRINGS + 1][MAX_STRINGLEN]` -- 25 x 40 = **1,000 bytes**
(agi.h) -- and MAP_RESERVED has 195 left after P6.19. Inheriting 1,000 is not a decision, it is a
refusal to measure: text_bufmax.py already found the oracle's 2,000-byte wrap buffer was 4x the
corpus's real maximum.

★★★★ SO THIS COUNTS WHAT THE GAMES USE. Every opcode that writes a string slot, plus every %s that
reads one:

    set.string  s n        -- writes slot s      [op_cmd.cpp cmdSetString]
    get.string  s ...      -- writes slot s      [cmdGetString, parameter[0]]
    get.num     ... s      -- writes slot s      [cmdGetNum, parameter[1]]
    word.to.string s n     -- writes slot s
    %s<n> in a message     -- READS slot n       [stringPrintf, text.cpp:1267 -- NO -1]

★★★ The answer that matters is the HIGHEST INDEX touched, not the count of distinct ones: the table
is indexed directly, so a game using only slots 0 and 19 still needs twenty.

★★★★★ THE WALK IS opcode_census.py's, NOT A FRESH ONE. The first version of this file wrote its own
and got `optable.V2_COMMANDS[op].name` -- the entries are plain (name, params, handler) TUPLES, so
every logic raised on its first opcode, every title reported "0 walked", and the summary printed
**"0 slots are needed"**. ★★★★ A requirement of zero is the most convenient possible answer to
AC-3's question and it was produced by a walker that had never walked anything [§2W]. It is now
refused: with no coverage this prints no requirement at all.

★★ §2P: indices and counts. No message text, no string content.

usage:  python harness/tools/string_census.py [title ...]
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
sys.path.insert(0, os.path.dirname(__file__))
from volread import resource, logic as logic_mod                   # noqa: E402
from agivm import optable                                          # noqa: E402
import text_oob                                                    # noqa: E402

GAMES = r"C:\Projects\agi-games\pc"
MAX_STRINGS, MAX_STRINGLEN = 24, 40        # agi.h

SAID = 0x0E
CMD = {i: (n, len(p)) for i, (n, p, h) in enumerate(optable.V2_COMMANDS)}
TEST_ARGS = {i: len(p) for i, (n, p, h) in enumerate(optable.V2_TESTS)}

# ★★ Which OPERAND carries the slot, by opcode name -- the numbers differ between interpreter
# families and the names do not [§2H's "319 opcodes" note].
# ★★★★★ `get.num` IS NOT ON THIS LIST, AND THE FIRST VERSION PUT IT THERE. Its signature is `nv`
# (optable) and cmdGetNum stores into `parameter[1]` as a VARIABLE, not a string slot -- so
# treating operand 1 as a string index sampled a variable number and reported a maximum of 255
# for larry1 and 237 for PoliceQuest1. **A table of 256 slots x 40 bytes = 10,240, which is three
# times the whole of MAP_RESERVED** -- an answer that would have triggered a stop on a measurement
# that was reading the wrong operand.
# ★★★ The three that remain are confirmed at the pin, by reading the handler rather than the
# signature: cmdSetString, cmdWordToString and cmdGetString all take the slot in parameter[0].
WRITERS = {"set.string": 0, "get.string": 0, "word.to.string": 0}

FMT_S = re.compile(rb"%s(\d*)")


class WalkError(Exception):
    pass


def walk_expr(code, ip):
    n = len(code)
    while ip < n:
        op = code[ip]
        ip += 1
        if op in (0xFC, 0xFD):
            continue
        if op in (0x00, 0xFF):
            return ip
        if op not in TEST_ARGS:
            raise WalkError("test %02X" % op)
        ip += code[ip] * 2 + 1 if op == SAID else TEST_ARGS[op]
    return ip


def walk(code, seen_w):
    ip, n = 0, len(code)
    while ip < n:
        op = code[ip]
        ip += 1
        if op == 0xFF:
            ip = walk_expr(code, ip) + 2
            continue
        if op == 0xFE:
            ip += 2
            continue
        if op == 0x00:
            continue
        if op not in CMD:
            raise WalkError("command %02X" % op)
        name, nargs = CMD[op]
        if name in WRITERS:
            k = WRITERS[name]
            if k < nargs and ip + k < n:
                seen_w.add(code[ip + k])
        ip += nargs


def main(argv):
    titles = argv[1:] or text_oob.V2_TITLES
    print("%-20s %7s %7s %10s %10s %7s" %
          ("title", "logics", "walked", "max write", "max read", "slots"))
    print("-" * 66)
    gmax, tot_l, tot_w = -1, 0, 0
    for t in titles:
        p = t if os.path.isdir(t) else os.path.join(GAMES, t)
        if not os.path.isdir(p):
            print("%-20s -- no such game dir" % t)
            continue
        g = resource.load_from_files(p)
        seen_w, seen_r = set(), set()
        nl = ok = 0
        for nr in range(256):
            try:
                raw = g.load("LOGIC", nr)
            except Exception:                                      # noqa: BLE001
                continue
            if not raw:
                continue
            nl += 1
            lg = logic_mod.split(raw, nr)
            try:
                walk(lg.bytecode, seen_w)
                ok += 1
            except (WalkError, IndexError):
                pass
            for m in lg.messages:
                if not m:
                    continue
                for mo in FMT_S.finditer(m):
                    d = mo.group(1)
                    seen_r.add(int(d) if d else 0)
        mw = max(seen_w) if seen_w else -1
        mr = max(seen_r) if seen_r else -1
        hi = max(mw, mr)
        gmax = max(gmax, hi)
        tot_l += nl
        tot_w += ok
        print("%-20s %7d %7d %10s %10s %7s"
              % (t, nl, ok, mw if mw >= 0 else "-", mr if mr >= 0 else "-",
                 (hi + 1) if hi >= 0 else 0))
    print("-" * 66)
    if tot_w == 0:
        print("★★★★★ NO LOGIC WALKED. This tool measured NOTHING and will not print a")
        print("      requirement -- a zero here would be an answer nobody produced.")
        return 1
    cov = 100.0 * tot_w / tot_l if tot_l else 0.0
    print("walk coverage: %d of %d logics (%.1f%%)" % (tot_w, tot_l, cov))
    if cov < 100.0:
        print("★★★ NOT EVERY LOGIC WALKED -- the maximum below is a LOWER BOUND.")
    print("CORPUS: highest slot touched = %d, so %d slots are used" % (gmax, gmax + 1))
    print("  oracle's declared table : %d x %d = %d bytes" %
          (MAX_STRINGS + 1, MAX_STRINGLEN, (MAX_STRINGS + 1) * MAX_STRINGLEN))
    print("  measured requirement    : %d x %d = %d bytes" %
          (gmax + 1, MAX_STRINGLEN, (gmax + 1) * MAX_STRINGLEN))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
