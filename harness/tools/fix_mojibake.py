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

# ═══════════════════════════════════════════════════════════════════════════════════════════
# ★★★★★ "DECODES AS VALID UTF-8" IS NECESSARY AND NOT SUFFICIENT, AND THE GAP DAMAGED A CORRECT
# FILE [T-P0-158 §4A, Jay's ruling: narrow it].
#
# The old acceptance test was the single `.decode("utf-8")` below. It flagged the two-character run
# U+00D7 U+2013 -- a MULTIPLICATION SIGN followed by an EN DASH, as in a ratio written
# "2.8<times><en-dash>4.7<times>" -- because cp1252-encoding those two gives the bytes D7 96, and
# **D7 is a structurally valid UTF-8 lead byte with 96 a valid continuation.** The reversal therefore
# decoded cleanly, to U+05D6 (HEBREW LETTER ZAYIN), and the repair WROTE THAT INTO A CORRECT REPORT.
# ★★★★★ run_gates.sh printed this tool as its own repair advice, so following the gate's instruction
# destroyed content.
#
# ★★★★ WHY NOT "REQUIRE THE RUN TO BE >= 3 CHARACTERS", the other candidate: it would stop catching
# damage to every TWO-byte character, and `U+00D7` itself is one (C3 97). **A checker narrowed into
# silence is worse than one that false-positives** [§6's first trigger], so the length test is refused.
#
# ★★★★★ THE TEST ADDED: the run's FIRST character must be the cp1252 decode of a UTF-8 lead byte that
# the tree's characters actually produce -- C2 and C3 (Latin-1 Supplement, so × © etc.) and E2
# (U+2000-U+2FFF: the stars, box-drawing and dashes this harness is full of). `U+00D7` decodes from
# byte D7, which leads the Hebrew block and nothing this project writes, so the false positive is
# excluded on a PRINCIPLED basis rather than by a length heuristic.
#
# ★★★ THE LIMITATION, STATED RATHER THAN DISCOVERED LATER: damage to a character whose UTF-8 lead byte
# is outside {C2, C3, E2} -- CJK (E3-E9), or anything in the astral planes (F0-F4) -- will NOT be
# detected. **No file in this tree contains one**, and if that changes this set must grow. A narrowing
# that silently stops covering something is the failure mode being guarded against here.
_LEAD_OK = {"Â", "Ã", "â"}
# ═══════════════════════════════════════════════════════════════════════════════════════════


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
        # ★★★★★ BOTH conditions, and the lead test comes FIRST because it is the cheap one and the
        # one that carries the meaning: a genuine double-encoding begins with a mis-decoded UTF-8
        # LEAD byte, and only C2/C3/E2 lead the characters this tree contains. See _LEAD_OK.
        if run[0] not in _LEAD_OK:
            out.append(run)
            i = j
            continue
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
    # ═══════════════════════════════════════════════════════════════════════════════════════
    # ★★★★★ --allow-bom EXISTS SO THE GATE CAN COVER MAME's OWN FILES WITHOUT BLINDING ITSELF
    # [T-P0-158 §4A]. Broadening the sweep to every tracked file found three MAME-written `.cfg`
    # files carrying a BOM -- **and MAME writes that BOM itself**, so stripping it is not a repair:
    # MAME puts it back on the next save and the gate is red forever, which is exactly the condition
    # that gets a gate switched off [§2M.8].
    # ★★★★ The alternative -- allowlisting the three files -- would stop checking their CONTENTS too.
    # This tolerates the BOM and still scans for double-encoded runs, so coverage is not traded away
    # for a green. ★★★ And in repair mode the BOM is PRESERVED rather than silently dropped.
    ap.add_argument("--allow-bom", action="store_true",
                    help="a leading BOM is not a defect (MAME writes one into its .cfg files)")
    # ═══════════════════════════════════════════════════════════════════════════════════════
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
        bom_bad = had_bom and not a.allow_bom
        if not bom_bad and fixed == 0:
            print("%-42s clean%s" % (f, " (BOM tolerated)" if had_bom else ""))
            continue
        dirty += 1
        print("%-42s %s%s"
              % (f, "BOM " if bom_bad else "", "%d run(s) double-encoded" % fixed if fixed else ""))
        if not a.check:
            # ★ LF preserved: .gitattributes pins .s/.sh/.lua to eol=lf, and a BOM before a shebang
            # is what started this -- so a BOM is dropped UNLESS --allow-bom says the file owns one.
            head = BOM if (had_bom and a.allow_bom) else ""
            p.write_bytes((head + new).encode("utf-8"))
    return 1 if (dirty and a.check) else 0


if __name__ == "__main__":
    sys.exit(main())
