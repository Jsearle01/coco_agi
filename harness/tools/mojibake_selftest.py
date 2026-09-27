#!/usr/bin/env python3
"""mojibake_selftest.py -- prove fix_mojibake.py BOTH ways, from CODEPOINTS. [T-P0-158 SS4A]

SS2W: a green check is evidence only once the same check has been seen to go red. This narrows the
acceptance test, so the thing that must be shown is not "the false positive is gone" but "the false
positive is gone AND real damage is still caught AND still repaired correctly".

SS4A's three cases, plus the ones that guard the narrowing itself:

  1. a real damaged run still FLAGS and still REPAIRS correctly     <- the narrowing did not silence it
  2. U+00D7 U+2013 no longer flags                                  <- the false positive
  3. a clean file still does not flag

SS2J.7 IS WHY EVERY STRING HERE IS BUILT FROM \\u ESCAPES. A written-down example of the damage is
BYTE-IDENTICAL to the damage, so a file containing one literally would fail the very check it
documents -- which has happened three times in this project, once to this tool's own docstring and
once to run_gates.sh's comment explaining the allowlist. The damaged forms below are therefore
ASSEMBLED AT RUNTIME and this file stays clean.

Run:  python harness/tools/mojibake_selftest.py
Exit: 0 if every case behaves, non-zero otherwise. run_gates.sh runs it before the tree sweep, so a
      narrowing that breaks detection cannot survive a task.
"""
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
TOOL = HERE / "fix_mojibake.py"
PY = sys.executable

# ── the characters, by codepoint ────────────────────────────────────────────────────────────
STAR   = "★"                      # the harness's own bullet
BOX    = "═"                      # the banner rule
TIMES  = "×"                      # MULTIPLICATION SIGN
ENDASH = "–"                      # EN DASH

# The cp1252 mis-decode of a UTF-8 sequence, assembled rather than pasted.
#   U+2605 = E2 98 85  -> cp1252 -> U+00E2 U+02DC U+2026
#   U+2550 = E2 95 90  -> cp1252 -> U+00E2 U+2022 U+0090   (0x90 is one of .NET's five best-fits)
#   U+00D7 = C3 97     -> cp1252 -> U+00C3 U+2014
def damaged(ch):
    """Return ch's UTF-8 bytes decoded as .NET cp1252 -- i.e. what a bad round trip leaves."""
    out = []
    for b in ch.encode("utf-8"):
        try:
            out.append(bytes([b]).decode("cp1252"))
        except UnicodeDecodeError:
            out.append(chr(b))         # .NET maps 81/8D/8F/90/9D to the same-numbered codepoint
    return "".join(out)


def run_check(text):
    """-> (flagged, repaired_text). Writes only to a temp file."""
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / "case.md"
        p.write_text(text, encoding="utf-8")
        r = subprocess.run([PY, str(TOOL), "--check", str(p)], capture_output=True, text=True)
        flagged = r.returncode != 0
        subprocess.run([PY, str(TOOL), str(p)], capture_output=True, text=True)
        return flagged, p.read_text(encoding="utf-8")


def cps(s):
    return " ".join("U+%04X" % ord(c) for c in s)


CASES = [
    # (name, text, must_flag, must_repair_to)
    ("1a real damage: a 3-byte star",
     "a line with " + damaged(STAR) + " in it", True,
     "a line with " + STAR + " in it"),
    ("1b real damage: a 3-byte box rule",
     "rule " + damaged(BOX) + " here", True,
     "rule " + BOX + " here"),
    ("1c real damage: a 2-BYTE character (the length test would have missed this)",
     "ratio 3" + damaged(TIMES) + "4", True,
     "ratio 3" + TIMES + "4"),
    ("2  the FALSE POSITIVE: MULTIPLICATION SIGN + EN DASH",
     "the true ratio is 2.8" + TIMES + ENDASH + "4.7" + TIMES + ", centred", False, None),
    ("3a clean: a proper star",
     "a line with " + STAR + " in it", False, None),
    ("3b clean: plain ASCII",
     "nothing to see here", False, None),
]

fail = 0
print("fix_mojibake.py self-test -- every string built from codepoints, nothing pasted")
print()
for name, text, must_flag, want in CASES:
    flagged, after = run_check(text)
    ok = (flagged == must_flag)
    note = ""
    if must_flag and want is not None:
        if after != want:
            ok = False
            note = "  *** REPAIRED WRONG: got [%s] want [%s]" % (cps(after), cps(want))
        else:
            note = "  repaired correctly"
    elif not must_flag:
        if after != text:
            ok = False
            note = "  *** MODIFIED A FILE IT DID NOT FLAG: [%s]" % cps(after)
        else:
            note = "  left untouched"
    print("%-62s flag=%-5s %s%s" % (name, flagged, "OK " if ok else "*** WRONG", note))
    if not ok:
        fail += 1

print()
if fail:
    print("*** %d case(s) wrong -- the detector is not behaving" % fail)
else:
    print("all cases behave: real damage flags and repairs, the false positive does not flag,")
    print("clean text is untouched, and nothing the tool declines to flag is ever modified")
sys.exit(1 if fail else 0)
