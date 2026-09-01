#!/usr/bin/env python3
"""harness/tools/plane_walk_census.py -- enumerate EVERY site that indexes a plane flatly.

★★★★ WHY A TOOL AND NOT A READING [L-53]. The dispatch names two sites, put_pixel and co_rowset,
and says the list is probably incomplete. A plane walk is not a distinctive token -- it is any
code that forms `FB_BASE + n` or `PRI_BASE + n` where n can exceed the 8,192-byte window, and it
can be spelled as a base-plus-offset, a `leax d,x`, a running pointer that is advanced in a loop,
or a constant delta between the two planes (PRI_DELTA). **Grepping for one spelling finds one
spelling.**

★★★ WHAT COUNTS. A site is reported if it (a) names FB_BASE / PRI_BASE / CP_VIS / CP_PRI /
PRI_DELTA / MAP_FB_SLICE / MAP_PRI_SLICE, or (b) forms an address from a row/column product
(160 * y), or (c) advances a pointer across a row stride. Comments and equ definitions are
excluded the same way reg_discipline.py excludes them (§2N's four-part rule, same shape).

★★ It over-reports on purpose. A false positive costs a read; a false negative is the defect this
task exists to fix.

usage:  python harness/tools/plane_walk_census.py [--scope src]
"""
import argparse
import io
import pathlib
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

PLANE_NAMES = re.compile(
    r"\b(FB_BASE|PRI_BASE|CP_VIS|CP_PRI|PRI_DELTA|MAP_FB_SLICE|MAP_PRI_SLICE|"
    r"MAP_PHASE_WIN|P3_FB|P3_PRI)\b")
# ★ 160 is the AGI row stride in both planes (1 B/px visual, and the packed plane is addressed
# by the same x before the >>1). A literal 160 or #160 near an index is a row-product tell.
STRIDE = re.compile(r"#?\b(160|0xA0|\$A0)\b")
# ★ Loads/stores through an index register -- the running-pointer spelling.
INDEXED = re.compile(r"\b(st|ld)[abdxyus]\s+[a-z0-9_]*\s*,\s*[xyus]\+?\+?", re.I)

MNEM = re.compile(r"^\s*(?:[A-Za-z_.][A-Za-z0-9_.]*:?\s+)?"
                  r"(ld[abdxyus]|st[abdxyus]|lea[xyus]|add[abd]|sub[abd]|"
                  r"clr|com|neg|inc|dec|tst|asl|lsr|ror|rol)\b", re.I)


def code_part(line):
    """Strip a full-line comment and the inline half after ';' or '*' at col 0."""
    s = line.rstrip("\n")
    if s.lstrip().startswith("*") or s.lstrip().startswith(";"):
        return ""
    return s.split(";", 1)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scope", default="src")
    a = ap.parse_args()

    hits = {}
    for f in sorted((ROOT / a.scope).rglob("*.s")):
        for n, raw in enumerate(f.read_text(errors="replace").splitlines(), 1):
            code = code_part(raw)
            if not code.strip() or re.search(r"\bequ\b", code, re.I):
                continue
            named = PLANE_NAMES.search(code)
            strided = STRIDE.search(code) and MNEM.search(code)
            if not (named or strided):
                continue
            why = []
            if named:
                why.append(named.group(1))
            if strided:
                why.append("row-stride 160")
            if INDEXED.search(code):
                why.append("indexed")
            rel = f.relative_to(ROOT).as_posix()
            hits.setdefault(rel, []).append((n, code.strip()[:66], "+".join(why)))

    total = 0
    for f in sorted(hits):
        print(f"── {f} ──")
        for n, code, why in hits[f]:
            print(f"  {n:>5}  {code:<66}  [{why}]")
            total += 1
        print()
    print(f"★ {total} candidate plane-index site(s) in {len(hits)} file(s). "
          f"Over-reports by design -- each needs a read, and a false negative is the defect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
