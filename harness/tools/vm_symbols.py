#!/usr/bin/env python3
"""harness/tools/vm_symbols.py -- pull symbol addresses from lwasm's MAP, not from the listing.

★★★ SCRAPING THE LISTING WAS WRONG AND IT FAILED SILENTLY. The first version took the first
listing line that both started with four hex digits and mentioned the symbol name -- which
matches an INSTRUCTION whose comment happens to name it, not the definition. It returned
res_volbase = $2156 where the real address is $2170, and the guest then read its volume base
out of the middle of some other routine's code, mapped a wrong block, and halted with a bad
signature. ★★ The symptom pointed at the resource layer; the cause was the symbol scraper.

★ lwasm's `--map` emits the symbol table as data. Reading the authority instead of pattern-
matching its human-readable rendering is the same lesson P1.3 learned about stale symbol
copies, one layer further out: one home per fact, and read it from the place that owns it.
"""
import argparse
import io
import pathlib
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mapfile")
    ap.add_argument("--out", required=True)
    ap.add_argument("--want", nargs="*",
                    default=["res_volbase", "res_slicebase", "res_curblk"])
    a = ap.parse_args()

    # lwasm 4.24 writes:  Symbol: <name> (<file>) = <HEXADDR>
    syms = {}
    for line in pathlib.Path(a.mapfile).read_text(errors="replace").splitlines():
        m = re.match(r"^\s*Symbol:\s+(\S+)\s+\([^)]*\)\s*=\s*([0-9A-Fa-f]+)\s*$", line)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)

    missing = [w for w in a.want if w not in syms]
    with pathlib.Path(a.out).open("w", encoding="ascii", newline="\n") as f:
        for w in a.want:
            if w in syms:
                f.write("%s %04X\n" % (w, syms[w]))
    for w in a.want:
        print("   %-16s %s" % (w, "$%04X" % syms[w] if w in syms else "★★★ NOT FOUND"))
    if missing:
        print("★★★ %d symbol(s) missing from %s" % (len(missing), a.mapfile))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
