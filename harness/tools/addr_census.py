#!/usr/bin/env python3
"""harness/tools/addr_census.py -- enumerate every absolute address the harness fixes.

★★★ WHY THIS IS A SCRIPT AND NOT A GREP. T-P0-031's dispatch supplies a table of three probes and
says plainly that it is the Orchestrator's reading and MAY BE INCOMPLETE [L-53]. It is: ELEVEN
harness files carry absolute addresses, not three. A hand-read of three files would have produced
a map that omits eight, and the omission would not surface until two structures collided at
runtime -- which is exactly how the $1700-$8000 / $3000-$6000 overlap survived this long.

★★ WHAT COUNTS. An `equ` to a 3-or-4 digit hex literal, or an `org`. Deliberately NOT counted:
  * `equ` to a decimal or small hex constant  -- those are sizes and masks, not addresses
  * anything after a `;`                      -- CLAUDE.md 2N's rule, same shape
  * register addresses $FF00-$FFFF            -- the I/O page is not ours to place

★ SIZES ARE DERIVED WHERE THE SOURCE STATES THEM and left blank otherwise; a guessed size in a
memory map is worse than an absent one, because the overlap check would then be reporting on
arithmetic rather than on the source.
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

EQU = re.compile(r"^\s*([A-Za-z_]\w*)\s+equ\s+\$([0-9A-Fa-f]{3,4})\b", re.I)

# ★★★ L-56 IN ITS PUREST FORM: THE FIRST RUN OF THIS SCRIPT MEASURED ITS OWN SCAFFOLDING.
# It reported 137 addresses across 20 files and flagged 30 collisions -- and among them were
# `fMotion equ $0080` and `fFixLoop equ $2000`, which are AGI OBJECT-FLAG BITMASKS, and
# `RES_WINDOW_SIZE equ $2000` and `RES_DIR_STRIDE equ $0400`, which are SIZES. A four-hex-digit
# literal after `equ` is not an address; it is a four-hex-digit literal.
# ★★ Had this gone unchecked, AC-3's memory map -- the artifact every later task builds on --
# would have contained bitmasks presented as owned memory, and the overlap check would have been
# reporting collisions between a flag constant and a framebuffer.
# ★ The exclusions are BY MEANING, not by convenience: a name that denotes a length, a stride, a
# maximum or a bitmask cannot denote a location.
SIZE_SUFFIX = re.compile(r"_(SIZE|LEN|STRIDE|MAX|MIN|COUNT|WORDS|BYTES|MASK|BITS)$", re.I)
FLAG_FILES = {"vm_tables.s"}     # ★ holds AGI's flag/var NUMBER tables, no addresses at all
ORG = re.compile(r"^\s+org\s+\$([0-9A-Fa-f]{3,4})\b", re.I)
# ★ `X equ Y+N` and `X equ Y*N` -- symbolic, resolved in a second pass so a probe that derives one
# address from another is not silently dropped.
EQU_SYM = re.compile(r"^\s*([A-Za-z_]\w*)\s+equ\s+([A-Za-z_]\w*)\s*([+\-])\s*(\$?[0-9A-Fa-f]+)\s*$", re.I)
SIZE_HINT = re.compile(r"(\d[\d,]*)\s*(?:B|bytes|KB)\b", re.I)


def strip(line):
    s = line.rstrip("\n")
    if s.lstrip().startswith("*") or s.lstrip().startswith(";"):
        return ""
    return s.split(";", 1)[0]


def scan(path):
    out = []
    syms = {}
    pending = []
    if path.name in FLAG_FILES:
        return out
    for i, raw in enumerate(path.read_text(errors="replace").splitlines()):
        c = strip(raw)
        if not c.strip():
            continue
        m = ORG.match(c)
        if m:
            out.append((int(m.group(1), 16), "org", path.name, i + 1))
            continue
        m = EQU.match(c)
        if m:
            a = int(m.group(2), 16)
            if a >= 0xFF00:                      # ★ the I/O page is not ours
                continue
            if SIZE_SUFFIX.search(m.group(1)):   # ★ a length is not a location
                syms[m.group(1)] = a             #   still resolvable for `X equ Y+SIZE`
                continue
            syms[m.group(1)] = a
            out.append((a, m.group(1), path.name, i + 1))
            continue
        m = EQU_SYM.match(c)
        if m:
            pending.append((m.group(1), m.group(2), m.group(3), m.group(4), i + 1))
    for name, base, op, off, ln in pending:
        if base in syms:
            v = int(off[1:], 16) if off.startswith("$") else int(off)
            a = syms[base] + (v if op == "+" else -v)
            if a < 0xFF00:
                out.append((a, name + f"  (={base}{op}{off})", path.name, ln))
    return out


def main():
    files = sorted(pathlib.Path("src/harness").glob("*.s"))
    rows = []
    for f in files:
        rows += scan(f)
    rows.sort(key=lambda r: (r[0], r[2]))
    print(f"{'addr':>7}  {'symbol':<26} {'file':<20} line")
    print("-" * 68)
    for a, s, f, ln in rows:
        print(f"  ${a:04X}  {s:<26} {f:<20} {ln}")
    print(f"\n{len(rows)} absolute address(es) across {len(files)} harness file(s)")

    # ★★ THE COLLISION REPORT IS THE POINT. Group by address: any address claimed by two files
    # under different names is a place where two probes disagree about who owns memory.
    by_addr = {}
    for a, s, f, ln in rows:
        by_addr.setdefault(a, []).append((s, f))
    shared = {a: v for a, v in by_addr.items() if len({f for _, f in v}) > 1}
    print(f"\n{len(shared)} address(es) claimed by more than one file:")
    for a in sorted(shared):
        names = ", ".join(f"{s}@{f}" for s, f in shared[a])
        print(f"  ${a:04X}  {names}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
