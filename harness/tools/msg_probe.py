#!/usr/bin/env python3
"""harness/tools/msg_probe.py -- properties of one LOGIC message, without disclosing it.

★★★★★ WHY THIS EXISTS. The eye gate put a message box on screen and Jay read the text back.
Deciding whether that is the RIGHT message means comparing it to the reference -- and §2P forbids
game text in any tracked file, so the comparison cannot be "print it and look".

★★★★ SO THE TEXT IS THE INPUT, NOT THE OUTPUT. The operator supplies what they saw with
--starts-with / --equals and this reports a BOOLEAN, plus length and a hash. The message itself
never reaches stdout, a report, or a commit.
★★★ That also makes it a real check rather than a display: it can say NO.

★★ Message numbering, spelt out because it is the off-by-one that would produce exactly this
symptom: print.v(vN) resolves get_message(logic, var[N] - 1) [commands.py:902], so var 17 = 1 is
the FIRST message, 0-based index 0. tx_msgptr takes the 1-based number and `deca`s it, which is
the same message. --number is 1-based to match the opcode's operand.

usage:
  python harness/tools/msg_probe.py <game-dir> <logic> [--number 1] [--starts-with "..."]
"""
import argparse
import hashlib
import io
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from volread import logic as logic_mod, resource   # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("logic", type=int)
    ap.add_argument("--number", type=int, default=1, help="1-based, as print.v resolves it")
    ap.add_argument("--starts-with", default="")
    ap.add_argument("--equals", default="")
    a = ap.parse_args()

    game = resource.load_from_files(a.game_dir)
    lg = logic_mod.split(game.load("LOGIC", a.logic), index=a.logic)
    print("logic %d: %d messages" % (a.logic, len(lg.messages)))
    idx = a.number - 1
    if idx < 0 or idx >= len(lg.messages):
        print("★★★ message %d is out of range (1..%d)" % (a.number, len(lg.messages)))
        return 1

    raw = lg.messages[idx]
    text = raw.decode("latin-1") if isinstance(raw, (bytes, bytearray)) else str(raw)
    printable = sum(1 for c in text if 0x20 <= ord(c) < 0x7F)
    print("message %d: %d bytes, %d printable, sha256 %s"
          % (a.number, len(text), printable,
             hashlib.sha256(text.encode("latin-1", "replace")).hexdigest()[:16]))

    rc = 0
    if a.starts_with:
        hit = text.startswith(a.starts_with)
        print("starts with the %d chars the operator supplied: %s" % (len(a.starts_with), hit))
        if not hit:
            # ★ Say HOW FAR it matched -- "no" alone cannot distinguish "wrong message" from
            #   "right message, operator mistyped a character".
            n = 0
            while n < min(len(text), len(a.starts_with)) and text[n] == a.starts_with[n]:
                n += 1
            print("   first %d characters match, then they differ" % n)
            rc = 1
    if a.equals:
        hit = text == a.equals
        print("equals the operator's string exactly: %s" % hit)
        if not hit:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
