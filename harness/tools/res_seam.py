#!/usr/bin/env python3
"""harness/tools/res_seam.py -- AC-6: design §4.2a's seam, made checkable.

★★★ THE CLAIM: no module outside the storage code knows or branches on the AGI version. A
caller asks for (type, index) and receives bytes; it never learns the volume, the offset, the
record header length, or whether the payload was compressed.

★★ THIS IS THE P1-ON-TARGET ANALOGUE OF 2N'S REGISTER DISCIPLINE, and it is written the same
way for the same reason: a literal grep for "v3" would match a comment and miss `res_hdrlen`.
The scan drops full-line comments and the inline half after `;` (or `#`) before matching, so a
DISCUSSION of v3 in a header block is not a violation and a USE of a version constant is.

★ Like 2N.1's census, this REPORTS. It is not wired into a build gate: the storage layer is one
file today and a gate would be measuring nothing. It becomes a ratchet when there are callers.
"""
import argparse
import io
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# The storage module: allowed to know all of this, by definition. ★ Allowlisted by EXPLICIT
# FILENAME, never by pattern (2N) -- so adding a second knowing file is a visible act.
STORAGE = {"src/harness/res_core.s"}

# ★ Tokens that mean "this code knows which AGI version produced the bytes". `res_hdrlen` is on
# the list because it IS the version: 5 for v2, 7 for v3. A caller reading it has the version.
TOKENS = [
    (r"\bres_hdrlen\b",             "reads the record header length"),
    (r"\bres_vol\b|\bres_off\b|\bres_offhi\b", "reads the volume/offset a resource came from"),
    (r"\bres_slicebase\b|\bres_volbase\b",     "reads the volume's physical placement"),
    (r"\bAGI_?V?[23]\b|\bAGIv[23]\b", "names an AGI version"),
    (r"\blzw\b|\bLZW\b",            "names v3 compression"),
    (r"\$1234\b|#\$12\b|0x1234\b",  "knows the volume record signature"),
    (r"\bAvis\b",                   "knows the message encryption key"),
]

COMMENT = re.compile(r"^\s*[*;#]|^\s*--")


def strip(line, suffix):
    if COMMENT.match(line):
        return ""
    if suffix in (".s", ".inc"):
        # lwasm: ';' starts an inline comment; a '*' in column 0 is handled above
        return line.split(";", 1)[0]
    return line.split("#", 1)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--roots", nargs="*", default=["src", "harness/tools", "tools"])
    a = ap.parse_args()

    scanned = 0
    hits = []
    for root in a.roots:
        for p in sorted((ROOT / root).rglob("*")):
            if p.suffix not in (".s", ".inc", ".py", ".lua") or not p.is_file():
                continue
            rel = p.relative_to(ROOT).as_posix()
            # ★ tools/volread/ IS the oracle and tools/agivm/ is the VM reference: they are
            # allowed to know everything about the format. They are not the port.
            if rel.startswith("tools/volread/") or rel.startswith("tools/agivm/"):
                continue
            if rel in STORAGE:
                continue
            scanned += 1
            for n, line in enumerate(p.read_text(encoding="utf-8", errors="replace")
                                     .splitlines(), 1):
                code = strip(line, p.suffix)
                if not code.strip():
                    continue
                for pat, why in TOKENS:
                    if re.search(pat, code):
                        hits.append((rel, n, why, code.strip()[:70]))
                        break

    harness = [h for h in hits if h[0].startswith(("src/harness/", "harness/tools/"))]
    engine = [h for h in hits if not h[0].startswith(("src/harness/", "harness/tools/"))]

    print("AC-6 -- design §4.2a seam check")
    print("storage module (allowlisted by name): %s" % ", ".join(sorted(STORAGE)))
    print("files scanned outside it            : %d" % scanned)
    print("version-aware lines in src/engine, src/hal, src/boot : %d" % len(engine))
    print("version-aware lines in the HARNESS (probe + tools)   : %d" % len(harness))
    for rel, n, why, code in engine:
        print("  ★★★ %s:%d  %s" % (rel, n, why))
        print("        %s" % code)
    for rel, n, why, code in harness[:20]:
        print("  (harness) %s:%d  %s" % (rel, n, why))
    print()
    print("★ The harness hits are the PROBE and the HOST TOOLS, which stage and verify -- they")
    print("  are the test rig, not callers of the seam. The claim AC-6 makes is the engine line.")
    return 0 if not engine else 1


if __name__ == "__main__":
    sys.exit(main())
