#!/usr/bin/env python3
"""harness/tools/fix_mojibake.py -- undo a cp1252/UTF-8 double-encoding, run by run.

★★★★★ WHY THIS EXISTS. PowerShell 5.1's `Get-Content -Raw` reads a UTF-8 file using the ANSI
codepage and `Set-Content -Encoding utf8` writes UTF-8 WITH A BOM. A round trip through the pair
therefore does two things to every non-ASCII character:

    U+2605  E2 98 85  --read as cp1252-->  three chars  --written as UTF-8-->  7 bytes
                                           U+00E2 U+02DC U+2026   C3 A2 CB 9C E2 80 A6

★★★★ THE EXAMPLE IS SPELT IN CODEPOINTS AND NOT IN THE CHARACTERS THEMSELVES.
The first draft embedded the damaged form literally so a reader could see it -- and this tool
then flagged its OWN DOCSTRING, because a written-down example is byte-identical to the real
thing. Running the repair over the tree would have "fixed" the illustration and destroyed the
one place the defect is recorded. ★★★ A tool that cannot be run on its own source is one
somebody will exclude from the sweep, and an excluded file is where the next instance hides.

and prepends EF BB BF. T-P0-061 did that to six files, four of them already pushed, while doing
bulk edits that the Edit tool would have made safely. **The damage is comment-only and every
affected script still ran**, which is exactly why it survived several commits unnoticed.

★★★★ A BLANKET INVERSE IS WRONG HERE, and that is the whole design of this tool. The files are
MIXED: some stars are double-encoded (from the bad round trip) and some are proper UTF-8 (added
afterwards by an editor that got it right). Decoding the whole file as UTF-8 and re-encoding as
cp1252 would repair the first set and destroy the second -- a repair that damages is worse than
the damage, because the next reader trusts it.

★★★ SO IT WORKS RUN BY RUN. Take maximal runs of characters that could only have come from a
cp1252 misread, try to round-trip just that run, and keep the result ONLY if it decodes as valid
UTF-8. A proper "★" is not in that alphabet and is never touched. A run that does not decode is
left alone -- this tool declines rather than guesses.

★★ It is idempotent: running it on a clean file changes nothing, which is the property that
makes it safe to point at a whole tree.

usage:  python harness/tools/fix_mojibake.py [--check] <file> [<file>...]
"""
import argparse
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BOM = "﻿"

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ .NET's cp1252 IS NOT PYTHON'S, AND THE DIFFERENCE IS FIVE BYTES THAT MATTER HERE.
# Windows-1252 leaves 0x81, 0x8D, 0x8F, 0x90 and 0x9D undefined. Python's strict codec REFUSES
# them; .NET's Encoding.GetEncoding(1252) maps each to the same-numbered control codepoint. The
# damage was done by .NET, so only .NET's table can reverse it.
# ★★★★ IT IS NOT A CORNER CASE -- IT IS THE BOX-DRAWING CHARACTERS. "═" is U+2550 = E2 95 90,
# and that trailing 0x90 is one of the five. Every "═══" banner in this harness therefore
# contains a byte Python's cp1252 cannot encode, so the first version of this tool DECLINED every
# banner run and left it mangled -- while reporting the file repaired.
# ★★★ The witness caught it: run_gates.sh came back with `echo "═══ $1 ═══"` among the lines not
# recovered, on a line I had never edited. **A line I did not touch appearing as "lost" is the
# repair failing, not the diff being noisy** -- and without the superset check it would have
# shipped as a fix.
_TBL = {}
for _b in range(0x80, 0x100):
    try:
        _TBL[bytes([_b]).decode("cp1252")] = _b
    except UnicodeDecodeError:
        _TBL[chr(_b)] = _b          # ★ 0x81/8D/8F/90/9D -- .NET's best-fit, and the fix

MOJI = set(_TBL)


def _to_cp1252(run):
    """Encode with .NET's table, not Python's. Raises KeyError on anything outside it."""
    return bytes(_TBL[c] for c in run)


def repair(text):
    out = []
    i, n, fixed = 0, len(text), 0
    while i < n:
        if text[i] not in MOJI:
            out.append(text[i])
            i += 1
            continue
        j = i
        while j < n and text[j] in MOJI:
            j += 1
        run = text[i:j]
        try:
            cand = _to_cp1252(run).decode("utf-8")
        except (KeyError, UnicodeDecodeError):
            out.append(run)          # ★ not a double-encoding, or not one we can prove: leave it
        else:
            out.append(cand)
            fixed += 1
        i = j
    return "".join(out), fixed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--check", action="store_true",
                    help="report what WOULD change and exit non-zero; write nothing")
    a = ap.parse_args()

    dirty = 0
    for f in a.files:
        p = pathlib.Path(f)
        raw = p.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            print("%-42s NOT UTF-8 -- skipped (this tool would guess)" % f)
            continue
        had_bom = text.startswith(BOM)
        if had_bom:
            text = text[1:]
        new, fixed = repair(text)
        if not had_bom and fixed == 0:
            print("%-42s clean" % f)
            continue
        dirty += 1
        print("%-42s %s%s"
              % (f, "BOM " if had_bom else "", "%d run(s) double-encoded" % fixed if fixed else ""))
        if not a.check:
            # ★ LF preserved and no BOM written: .gitattributes pins .s/.sh/.lua to eol=lf, and
            # a BOM before a shebang is what started this.
            p.write_bytes(new.encode("utf-8"))
    return 1 if (dirty and a.check) else 0


if __name__ == "__main__":
    sys.exit(main())
