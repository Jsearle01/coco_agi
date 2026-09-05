#!/usr/bin/env python3
"""harness/tools/slot_audit.py -- do two host-visible slots occupy the same bytes? [AC-6, §2F]

★★★★★ WHY THIS EXISTS. AD-102 was a counter that could not move. This is its neighbour: a
counter that moves because something ELSE wrote it. `pic_probe.s` declares

    CNT_STRPIX      equ     $00A0           ; pixels written by those spans
    CNT_SECFLUSH    equ     $00A2
    CNT_FLUSH       equ     $00A4           ; runs actually flushed
    ...
    PAL_READBACK    equ     $00A0           ; 16 bytes the host reads after the run

-- **the same sixteen bytes, twice, and nothing in the tree said so.** ★★★ It also identifies
the writer of `$00A6` that P3b.6 could not find and worked around by moving `CNT_ROWTRANS` to
`$00B0`: `$00A6` is `PAL_READBACK+6`, palette entry 6. **The workaround was right and the
diagnosis was never made**, so the same trap stayed armed for the four counters left inside.

★★★★ THE SIZE IS THE WHOLE PROBLEM AND IT CANNOT BE INFERRED. Deriving a slot's extent from the
gap to the next `equ` is precisely the assumption that hides this: `PAL_READBACK` is the last
`equ` in its file and would read as 1 byte. So SIZE MUST BE DECLARED, in the comment, as
"N bytes"; a slot with no declaration is reported as UNDECLARED rather than assumed to be one.
★★★ An undeclared slot is not a pass. It is the tool saying it cannot answer.

★★ Guards are reported, not resolved. Two slots under mutually exclusive `ifdef`s never coexist,
and the tool cannot know that -- it prints the nearest enclosing guard for each side so a reader
can judge. ★ It prints, and does not gate: a fresh probe with undeclared sizes must not block a
build [§2N.1's principle -- a census is not a gate].

usage:  python harness/tools/slot_audit.py                 (every src/harness/*_probe.s)
        python harness/tools/slot_audit.py --src src/harness/pic_probe.s
"""
import argparse
import io
import pathlib
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

EQU = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s+equ\s+\$([0-9A-Fa-f]{2,4})\s*(?:;(.*))?$")
SIZE = re.compile(r"(\d+)\s*bytes?\b")
GUARD_IN = re.compile(r"^\s*if(n?)def\s+([A-Za-z_][A-Za-z0-9_]*)")
GUARD_OUT = re.compile(r"^\s*endc\b")


def slots_of(path):
    """Every `NAME equ $00xx` with its declared size and enclosing guard stack."""
    out, guards = [], []
    for lineno, ln in enumerate(path.read_text(errors="replace").splitlines(), 1):
        g = GUARD_IN.match(ln)
        if g:
            guards.append(("ifndef " if g.group(1) else "ifdef ") + g.group(2))
            continue
        if GUARD_OUT.match(ln):
            if guards:
                guards.pop()
            continue
        m = EQU.match(ln.rstrip())
        if not m:
            continue
        addr = int(m.group(2), 16)
        # ★ Only the direct page. Slots above it are code and data addresses, not host mailbox.
        if addr > 0x00FF:
            continue
        s = SIZE.search(m.group(3) or "")
        out.append({"name": m.group(1), "addr": addr, "line": lineno,
                    "size": int(s.group(1)) if s else None,
                    "guard": guards[-1] if guards else ""})
    return out


def audit(path):
    slots = slots_of(path)
    if not slots:
        return 0
    print(f"── {path.as_posix()}  ({len(slots)} direct-page slots)")
    undeclared = [s for s in slots if s["size"] is None]
    hits = 0
    for i, a in enumerate(slots):
        for b in slots[i + 1:]:
            # ★★ Only a DECLARED size can prove an overlap. An undeclared slot is listed below
            # as unanswerable rather than silently treated as one byte -- which is the exact
            # inference that let a 16-byte buffer sit on four counters unnoticed.
            sa, sb = a["size"], b["size"]
            if sa is None and sb is None:
                continue
            lo_a, hi_a = a["addr"], a["addr"] + (sa or 1) - 1
            lo_b, hi_b = b["addr"], b["addr"] + (sb or 1) - 1
            if lo_a <= hi_b and lo_b <= hi_a:
                hits += 1
                print(f"   ★★★ OVERLAP  {a['name']} ${lo_a:04X}-${hi_a:04X} "
                      f"(line {a['line']}{', ' + a['guard'] if a['guard'] else ''})")
                print(f"                {b['name']} ${lo_b:04X}-${hi_b:04X} "
                      f"(line {b['line']}{', ' + b['guard'] if b['guard'] else ''})")
    if undeclared:
        print(f"   ~ {len(undeclared)} slot(s) declare no size -- not checked, not cleared: "
              + " ".join(s["name"] for s in undeclared))
    if not hits:
        print("   no overlap among the slots that declare a size.")
    print()
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    a = ap.parse_args()
    files = ([ROOT / a.src] if a.src
             else sorted((ROOT / "src" / "harness").glob("*probe*.s")))
    total = sum(audit(f) for f in files if f.exists())
    if total:
        print(f"★★★ {total} overlapping pair(s). A slot written by two owners is a §2F "
              f"single-home violation, and the second writer is invisible in the first's output.")
    else:
        print("★ no declared-size overlap in any probe.")
    return 0        # ★ reports, never gates -- §2N.1


if __name__ == "__main__":
    sys.exit(main())
