#!/usr/bin/env python3
"""reg_discipline.py -- REGISTER DISCIPLINE FOR coco_agi (CLAUDE.md §2N).

WHAT THIS MEASURES, AND WHAT IT IS NOT FOR
==========================================
It enumerates GIME / MMU / SAM / palette register ACCESSES in 6809 assembly outside the HAL,
so that the project can answer one question: **who owns each register?**

★★ "THE ENGINE TOUCHES NO REGISTERS" IS NOT THE GOAL, AND CHASING IT IS A KNOWN ERROR.
POP measured 59 accesses outside its HAL and **71% of them are HOT** -- msys_player.s makes 23
of them from *inside the FIRQ handler*, at audio rate. A `jsr` costs ~12-14 cycles against a
single-register write of 7 (POP §5.224), so routing those through the HAL is the single worst
conversion available: it is not a re-gate cost, it is a correctness risk to the sound arc.
POP's genuinely convertible tier was NINE accesses, not 109.

**The goal is ONE SANCTIONED OWNER per register.** This tool counts; it does not judge. A high
count in the file that is already the sanctioned owner is fine. A low count in a file nobody
expected is the finding.

  The HAL owns $FF90-$FF9F (GIME / MMU / SAM control) and $FFB0-$FFBF (palette).

★ SCAN RANGE vs OWNERSHIP RANGE -- these are deliberately different. The two ranges above are
the OWNERSHIP claim. The SCAN range is the whole GIME/MMU/SAM window $FF80-$FFDF, because the
registers that actually caused trouble in the siblings sit outside the ownership ranges: the
MMU task-0 slots at $FFA0-$FFA7 and the SAM speed pair $FFD8/$FFD9. A scanner narrowed to the
ownership ranges would have been blind to POP's $FFA4/$FFA5 incident entirely.

  The PIA at $FF00-$FF7F (DAC, DSKREG) is a different subsystem and is OUT OF SCOPE.
  Recorded here so the next reader knows it was DECIDED, not missed.


★★ THE FOUR-PART RULE -- AND WHY A LITERAL grep '$FF..' IS THE DISCREDITED INSTRUMENT
=====================================================================================
POP P5.17 established this by getting the method wrong twice, in OPPOSITE DIRECTIONS at once:

  OVER-COUNTS: a literal grep over POP's src/engine returned 117 hits of which **85 were
  COMMENT TEXT**. This family of codebases quotes register addresses in prose constantly, and
  correctly. A check that fires on prose is a check that gets switched off -- exactly the
  reasoning hal_sync_check.py applies to line endings.

  UNDER-COUNTS: the same grep **misses every access made through an `equ` alias** -- CEL_MMU,
  BANK_MMU, TC_MMU, SAM_SLOW/SAM_FAST, PALETTE, and msys_player's FF90-FF95 forms -- and those
  are **the majority of the real accesses**. `sta CEL_MMU+2` contains no `$FF` at all.

★ PALETTE is on that alias list, which is why this matters to us specifically: CLAUDE.md §2F.1
makes the 16-byte palette table HAL-owned and forbids inlining a palette constant at a write
site. A literal grep would miss exactly the accesses that rule exists to police.

So a line counts as an access ONLY IF ALL FOUR HOLD. Each part is reportable individually via
--explain, so the rule can be demonstrated rather than asserted:

  P1  it is not a full-line comment        ('*' or ';' in the first non-blank column)
  P2  it is not the inline half after ';'  (code before ';' counts; the comment after does not)
  P3  it is not an `equ` DEFINITION        (defining the alias is not accessing the register)
  P4  it carries a load/store/modify mnemonic

...and ALIASES ARE RESOLVED to the register they name, `+n` OFFSETS INCLUDED, so `sta CEL_MMU+1`
is recorded against $FFA7 -- which is what it actually writes.

Measured under this rule: **POP 59, Karateka 8** (see --expect, and the P0.1 report).


★ THE ALLOWLIST IS BY EXPLICIT FILENAME, NEVER BY PATTERN OR DIRECTORY
======================================================================
A probe's job is to poke hardware, so probes are exempt -- but adding one must be a VISIBLE ACT,
one reviewable line, not a glob that silently widens. It is also why filenames beat directories:
POP's src/engine/tile_probe.s is a probe by name, header and behaviour while living in the
ENGINE tree, and a directory rule would either miss it or force a file to move to satisfy a
checker.

coco_agi SHIPS WITH AN EMPTY ALLOWLIST. There are no probes yet. See ALLOWLIST below.

★ KNOWN LIMITATION, FOUND WHILE VALIDATING THIS TOOL (P0.1) -- IN THE HEADER SO THE NEXT
READER MEETS IT BEFORE REDISCOVERING IT
=======================================================================================
P2 strips the comment half at ';' ONLY. A trailing '*' comment is NOT stripped, so:

    lda  $FF92        * a trailing star comment that also names $FFB0

counts TWO accesses where there is one. This is deliberate, not an oversight: in LWASM '*'
opens a comment only in column 1, and elsewhere it is the MULTIPLICATION operator, so a
tool that stripped at any '*' would silently discard the operand of `ldb #WIDTH*2`. The
project convention -- '*' in column 1, ';' inline -- is what makes ';' the correct split.

**Measured, not assumed: this affects NEITHER sibling.** Zero lines in POP's src/boot +
src/engine carry a mnemonic and a trailing '*' comment holding a register literal, so the
59 is unaffected. POP's register_owner_check.py splits at ';' identically and agrees with
this tool SITE FOR SITE. If AGI code ever adopts trailing '*' comments, this becomes live.

Standalone, stdlib only, no config file -- POP harness/tools/ convention.
"""
import argparse
import pathlib
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


# ---------------------------------------------------------------- scope

# The SCAN window: GIME video/interrupt, MMU task registers, palette, SAM. NOT the PIA.
SCAN_LO, SCAN_HI = 0xFF80, 0xFFDF

# The OWNERSHIP claim (CLAUDE.md §2N). Reported by --by-register; never used to filter.
HAL_OWNED = ((0xFF90, 0xFF9F), (0xFFB0, 0xFFBF))

# ★ ALLOWLIST -- BY EXPLICIT FILENAME, NEVER BY PATTERN.
# EMPTY ON PURPOSE: coco_agi has no harness probes yet. When the first one is written, its
# repo-relative posix path goes here as its own line, in the same commit as the probe. One
# reviewable line per exemption is the entire mechanism.
ALLOWLIST = frozenset()

DEFAULT_ROOTS = ("src/engine",)


# ---------------------------------------------------------------- the four-part rule

# P4: load / store / modify against a memory operand. 6809 base plus the 6309 additions, since
# src/opt/6309/ is a planned target. Mnemonics that only touch a register (tsta, clra, ...) are
# excluded by the trailing \b -- 'clr' does not match 'clra'.
MNEMONIC = re.compile(
    r"\b("
    r"ld[abdefqwxyus]|st[abdefqwxyus]|"          # loads and stores (6809 + 6309 e/f/q/w)
    r"clr|com|neg|inc|dec|tst|"                  # read-modify-write, memory form
    r"lsl|asl|lsr|asr|rol|ror|"                  # shifts and rotates, memory form
    r"aim|oim|eim|tim"                           # 6309 logical-immediate-to-memory
    r")\b",
    re.I,
)

# P3: `SYMBOL equ $FFxx`. Applied AFTER the inline comment is stripped, so a trailing comment
# on the definition does not defeat the match.
EQU_DEF = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+equ\s+\$([0-9A-Fa-f]{4})\s*$", re.I)

# A literal in the scan window: $FF80-$FFDF.
LITERAL = re.compile(r"\$FF([89ABCD][0-9A-Fa-f])", re.I)

# Any `equ` at all, in code position -- P3's rejection test.
ANY_EQU = re.compile(r"\bequ\b", re.I)


def classify(raw):
    """Apply the four-part rule to one raw source line.

    Returns (code, reason) where `code` is the scannable code half or None if rejected.
    `reason` names the rule part that decided, so --explain can DEMONSTRATE the rule
    instead of asserting it.
    """
    stripped = raw.strip()
    if not stripped:
        return None, "P0 blank"
    if stripped[0] in "*;":
        return None, "P1 full-line comment"

    code = raw.split(";", 1)[0]                      # P2: the comment half is discarded here
    if ANY_EQU.search(code):
        return None, "P3 equ definition"
    if not MNEMONIC.search(code):
        # Distinguish the two ways a line reaches here, because they mean different things:
        # a register named ONLY in the comment half was rejected by P2, not by P4.
        if not LITERAL.search(code) and LITERAL.search(raw):
            return None, "P2 register only in the inline comment"
        return None, "P4 no load/store/modify mnemonic"
    return code, "ACCESS"


# ---------------------------------------------------------------- alias resolution

def collect_aliases(roots):
    """SYMBOL -> register, for every `SYMBOL equ $FFxx` in the scan window.

    Collected across the WHOLE root set including the HAL and .inc files, because an alias is
    defined in one place and used in another; scoping the collection to the scanned files would
    reintroduce exactly the blindness this exists to remove.
    """
    out = {}
    for path in source_files(roots, suffixes=(".s", ".inc")):
        for raw in read_lines(path):
            m = EQU_DEF.match(raw.split(";", 1)[0])
            if m and SCAN_LO <= int(m.group(2), 16) <= SCAN_HI:
                out[m.group(1)] = int(m.group(2), 16)
    return out


def alias_hits(code, aliases):
    """Yield (register, text) for each alias reference in `code`, resolving `+n` offsets.

    ★ The offset is the load-bearing half: `sta CEL_MMU+2` contains no '$FF' and writes $FFA8.
    """
    for sym, base in aliases.items():
        for m in re.finditer(r"\b" + re.escape(sym) + r"\b(\s*\+\s*(\d+))?", code):
            reg = base + (int(m.group(2)) if m.group(2) else 0)
            if SCAN_LO <= reg <= SCAN_HI:
                yield reg, m.group(0).strip()


# ---------------------------------------------------------------- traversal

def read_lines(path):
    return path.read_text(errors="replace").splitlines()


def source_files(roots, suffixes=(".s",), exclude=(), allow=frozenset()):
    """Every source file under `roots`, minus excluded subtrees, minus allowlisted filenames."""
    ex = [pathlib.Path(e).as_posix().rstrip("/") for e in exclude]
    seen = set()
    for root in roots:
        base = pathlib.Path(root)
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in suffixes:
                continue
            rel = path.as_posix()
            if rel in seen:
                continue
            if rel in allow:
                continue
            if any(rel == e or rel.startswith(e + "/") for e in ex):
                continue
            seen.add(rel)
            yield path


def scan(roots, aliases, exclude, allow):
    """-> list of (register, file, lineno, text, kind) for every ACCESS."""
    hits = []
    for path in source_files(roots, (".s",), exclude, allow):
        rel = path.as_posix()
        for lineno, raw in enumerate(read_lines(path), 1):
            code, reason = classify(raw)
            if code is None:
                continue
            for hx in LITERAL.findall(code):
                hits.append((0xFF00 | int(hx, 16), rel, lineno, "$FF" + hx.upper(), "literal"))
            for reg, text in alias_hits(code, aliases):
                hits.append((reg, rel, lineno, text, "alias"))
    return hits


# ---------------------------------------------------------------- reporting

def owned_by_hal(reg):
    return any(lo <= reg <= hi for lo, hi in HAL_OWNED)


def report(hits, roots, allow, args):
    print("[reg-discipline] scope: %s  (scan $%04X-$%04X, excluding %s)"
          % (", ".join(roots), SCAN_LO, SCAN_HI, ", ".join(args.exclude) or "nothing"))
    print("[reg-discipline] allowlist: %d file(s)%s"
          % (len(allow), "" if allow else "  (empty -- no probes exist yet)"))

    if not hits:
        print("[reg-discipline] 0 register access(es). Nothing outside the HAL touches "
              "$%04X-$%04X." % (SCAN_LO, SCAN_HI))
        return

    by_file = {}
    by_reg = {}
    for reg, rel, lineno, text, kind in hits:
        by_file.setdefault(rel, []).append((reg, lineno, text, kind))
        by_reg.setdefault(reg, set()).add(rel)

    print("[reg-discipline] %d register access(es) in %d file(s) over %d register(s)."
          % (len(hits), len(by_file), len(by_reg)))

    if args.by_file or not (args.by_register or args.sites):
        print()
        print("  %-40s %5s  registers" % ("file", "count"))
        for rel in sorted(by_file):
            regs = sorted({r for r, _, _, _ in by_file[rel]})
            print("  %-40s %5d  %s"
                  % (rel, len(by_file[rel]), " ".join("$%04X" % r for r in regs)))

    if args.by_register:
        print()
        print("  %-8s %5s  %-10s owners" % ("reg", "count", "hal-owned"))
        for reg in sorted(by_reg):
            n = sum(1 for h in hits if h[0] == reg)
            print("  $%04X    %5d  %-10s %s"
                  % (reg, n, "yes" if owned_by_hal(reg) else "no", " ".join(sorted(by_reg[reg]))))

    if args.sites:
        print()
        for reg, rel, lineno, text, kind in sorted(hits, key=lambda h: (h[1], h[2], h[0])):
            print("  $%04X  %s:%d  `%s`  (%s)" % (reg, rel, lineno, text, kind))


def explain(paths):
    """★ AC-7: show the four-part rule DECIDING, line by line, on a fixture."""
    aliases = collect_aliases([str(pathlib.Path(p).parent) for p in paths])
    if aliases:
        print("[explain] aliases in scope: %s"
              % ", ".join("%s=$%04X" % (k, v) for k, v in sorted(aliases.items())))
    print()
    for p in paths:
        path = pathlib.Path(p)
        print("=== %s ===" % path.as_posix())
        for lineno, raw in enumerate(read_lines(path), 1):
            code, reason = classify(raw)
            if reason == "P0 blank":
                continue
            found = []
            if code is not None:
                found = ["$%04X" % r for r in
                         [0xFF00 | int(h, 16) for h in LITERAL.findall(code)]]
                found += ["$%04X" % r for r, _ in alias_hits(code, aliases)]
            verdict = ("COUNTED  -> " + " ".join(found)) if found else \
                      ("rejected -> " + reason if code is None else "rejected -> "
                       "no register in the code half")
            print("  %3d  %-13s %-46s %s"
                  % (lineno, reason.split()[0], raw.rstrip()[:46], verdict))
        print()


# ---------------------------------------------------------------- entry

def main():
    ap = argparse.ArgumentParser(
        description="Count GIME/MMU/SAM/palette register accesses under the four-part rule "
                    "(CLAUDE.md §2N). Counting is the point; zero is NOT the goal.")
    ap.add_argument("--roots", nargs="*", default=list(DEFAULT_ROOTS),
                    help="roots to scan (default: %s, recursively)" % " ".join(DEFAULT_ROOTS))
    ap.add_argument("--exclude", nargs="*", default=[],
                    help="subtrees to skip, e.g. src/hal src/harness")
    ap.add_argument("--allow", nargs="*", default=[],
                    help="EXTRA allowlisted files, by explicit filename (never a pattern)")
    ap.add_argument("--by-file", action="store_true", help="per-file table (default view)")
    ap.add_argument("--by-register", action="store_true", help="per-register table with owners")
    ap.add_argument("--sites", action="store_true", help="every access site, one per line")
    ap.add_argument("--expect", type=int, default=None,
                    help="assert the total equals N; exit 1 if it does not. For validating "
                         "this tool against an INDEPENDENTLY measured figure (CLAUDE.md §2O.1).")
    ap.add_argument("--explain", nargs="*", metavar="FILE", default=None,
                    help="show the four-part rule deciding, line by line, on the given files")
    args = ap.parse_args()

    if args.explain is not None:
        explain(args.explain)
        return 0

    allow = set(ALLOWLIST) | {pathlib.Path(a).as_posix() for a in args.allow}
    roots = [r for r in args.roots]

    missing = [r for r in roots if not pathlib.Path(r).exists()]
    if missing and len(missing) == len(roots):
        # ★ An empty or not-yet-created tree is a CLEAN result, not an error. This tool is
        # installed before the first engine file exists; erroring here would mean the very
        # first thing it ever did was fail.
        print("[reg-discipline] scope: %s -- no such path yet." % ", ".join(missing))
        print("[reg-discipline] 0 register access(es). Nothing to check.")
        return 0 if args.expect in (None, 0) else 1

    aliases = collect_aliases(roots)
    hits = scan(roots, aliases, args.exclude, allow)
    report(hits, roots, allow, args)

    if args.expect is not None:
        if len(hits) != args.expect:
            print("[reg-discipline] ★ EXPECTED %d, MEASURED %d -- the instrument and the "
                  "independent figure DISAGREE." % (args.expect, len(hits)))
            print("[reg-discipline] Do NOT tune the tool to hit the number; report the "
                  "disagreement (CLAUDE.md §2O.1).")
            return 1
        print("[reg-discipline] OK -- measured %d, matching the independent figure." % len(hits))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
