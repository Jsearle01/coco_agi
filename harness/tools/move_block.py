#!/usr/bin/env python3
"""harness/tools/move_block.py -- move a delimited block of lines within a source file.

★★★★ WHY A SCRIPT AND NOT AN EDITOR ACTION. ff_win_row was inserted immediately before
ff_store, which pushed ff_store out of `bsr` range (-128..+127) and broke the build. The
alternatives were to promote both `bsr ff_store` to `jsr` -- which taxes the FLAT build by a
cycle on all 425,179 flushes, ~0.24 s, for a windowed build's benefit -- or to move the block
past ff_store, which costs nothing at all.

★★★ Placement is load-bearing in 6809 source in a way it is not in most languages, and a move
of ~150 bytes is not a refactor: it changes which branches reach. Saved so the move is auditable
and repeatable rather than a hand-edit nobody can check [L-45].

usage:  python harness/tools/move_block.py FILE --start "text" --end "text" --after "text"
"""
import argparse
import pathlib
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--start", required=True, help="first line of the block (exact match)")
    ap.add_argument("--end", required=True, help="last line of the block (exact match)")
    ap.add_argument("--after", required=True, help="insert the block after this line")
    a = ap.parse_args()

    p = pathlib.Path(a.file)
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)

    def find(text, frm=0):
        for i in range(frm, len(lines)):
            if lines[i].rstrip("\r\n") == text:
                return i
        return -1

    s = find(a.start)
    if s < 0:
        print(f"start not found: {a.start!r}"); return 1
    e = find(a.end, s + 1)
    if e < 0:
        print(f"end not found after start: {a.end!r}"); return 1
    block = lines[s:e + 1]
    rest = lines[:s] + lines[e + 1:]

    t = -1
    for i, ln in enumerate(rest):
        if ln.rstrip("\r\n") == a.after:
            t = i
            break
    if t < 0:
        print(f"anchor not found: {a.after!r}"); return 1

    out = rest[:t + 1] + block + rest[t + 1:]
    p.write_text("".join(out), encoding="utf-8")
    print(f"moved {len(block)} lines from {s+1}-{e+1} to after line {t+1} "
          f"({p.name}, {len(out)} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
