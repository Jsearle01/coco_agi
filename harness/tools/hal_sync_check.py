#!/usr/bin/env python3
"""hal_sync_check.py — the HAL-SYNC BRIDGE (P2.4).

POP builds LINKED, karateka builds ABSOLUTE, from ONE guarded HAL source that
currently exists as TWO COPIES, one per repo. Two copies drift. This check is wired
into BOTH projects' build.bat as a pre-build step and FAILS the build on substantive
drift, so neither project can be built past a divergence.

THIS SCRIPT IS TEMPORARY BY DESIGN. It exists only for the bridge period. When
karateka also converts to linked and the kernel becomes a single shared source, the
two copies collapse into one, there is nothing left to compare, and this file plus
its two build.bat call sites delete cleanly. It is deliberately not built into
permanent infrastructure — no config file, no plugin points, no dependencies.

IT CHECKS ITSELF. The script is byte-identical in both repos and is included in its
own compared file set, which answers "who watches the watcher": editing it in one
repo fails both builds until the copies match again. That is why the sibling path is
DERIVED (see SIBLING below) rather than written in — a per-repo path constant would
make the two copies differ and the self-check would fail forever.

WHAT COUNTS AS SANCTIONED DIVERGENCE (the load-bearing judgment)
---------------------------------------------------------------
Not drift — the check tolerates these:

  1. LINE ENDINGS. POP's .gitattributes pins *.s to LF; karateka's tree is CRLF; both
     trees are internally mixed. A byte comparison reports drift on every single file
     and the check gets switched off in a week. Normalised away.

  2. THE POP DORMANCY GUARD. POP wraps the six runtime-blit entry points in
     `ifdef POP_HAL_RUNTIME_BLIT` (PA.6 ruled the runtime blit infeasible for POP;
     P1.3 replaced it with compiled sprites). Karateka calls all six from 25 live
     sites and has no guard. Governance rule 3: per-project CONFIGURATION, not a
     fork. The guard's own directive lines are dropped — THE CODE INSIDE IS STILL
     COMPARED, which is the point.

  3. EXPORT PLACEMENT. Because of (2), POP's blit exports nest inside the dormancy
     guard while karateka's sit at top level. The SET of exported symbols per file is
     compared, not where the lines appear. A symbol appearing or vanishing from a
     file's ABI surface IS drift and is still caught.

  4. COMMENTS. Comment-only lines are dropped. Per-project adoption notes (P2.1's
     dormancy rationale, POP's OBJTARGET annotations) are exactly the kind of thing
     that legitimately differs, and failing a build over prose trains people to
     bypass the check.

  5. POP-LOCAL FILES. hal_globals.s exists only in POP: karateka carries the same
     declarations inside src/engine/globals.s, which is engine code POP does not have
     yet (P2.1). Listed explicitly below so its absence is a known fact rather than a
     silent gap.

Everything else — every instruction, every equ, every directive, the whole contract
in hal.inc — must match exactly.

EXIT CODES:  0 = aligned (or gracefully skipped)   1 = substantive drift
"""
import sys
import pathlib

# Sibling map. DERIVED, not configured — this is what keeps the two copies of this
# file byte-identical so it can check itself.
SIBLINGS = {'POP3_port': 'karateka_coco3', 'karateka_coco3': 'POP3_port'}

# The shared kernel source. Compared file-by-file; missing on BOTH sides is fine,
# missing on ONE side is drift (unless declared POP-local below).
SHARED = ['src/hal.inc',
          'src/hal/coco3-dsk/sys.s', 'src/hal/coco3-dsk/time.s',
          'src/hal/coco3-dsk/irq_vbl.s', 'src/hal/coco3-dsk/gfx.s',
          'src/hal/coco3-dsk/input.s', 'src/hal/coco3-dsk/sound.s',
          'src/hal/coco3-dsk/file.s', 'src/hal/coco3-dsk/mem.s',
          'src/hal/coco3-dsk/disk_read.s',
          'harness/tools/hal_sync_check.py']          # <-- checks itself

# Sanctioned per-project files (see note 5 above).
PROJECT_LOCAL = {'src/hal/coco3-dsk/hal_globals.s'}

GUARD_DIRECTIVES = ('ifdef', 'endc', 'else')


def normalise(path):
    """Reduce a file to its substantive content: the code and directives that must
    match, with the sanctioned divergences of notes 1-4 removed."""
    text = path.read_bytes().decode('utf-8', errors='replace')
    body, exports = [], set()
    depth, dormancy = 0, []       # dormancy = stack of depths a POP guard opened at
    for raw in text.splitlines():                     # note 1: EOL normalised here
        stripped = raw.strip()
        if not stripped:
            continue
        if stripped[0] in '*;#':
            continue                                  # note 4: comments
        norm = ' '.join(stripped.split())             # collapse whitespace runs
        first = norm.split()[0].lower()

        if first in ('ifdef', 'ifndef'):
            depth += 1
            # note 2: drop the dormancy guard's OWN directives — never its contents.
            # Tracked by depth because POP nests an `ifdef OBJTARGET` export block
            # inside it; matching the first `endc` would close the wrong guard.
            if 'POP_HAL_RUNTIME_BLIT' in norm:
                dormancy.append(depth)
                continue
        elif first == 'endc':
            closing = depth
            depth -= 1
            if dormancy and closing == dormancy[-1]:
                dormancy.pop()
                continue
        elif first == 'export':
            exports.add(norm.split()[1])              # note 3: compared as a set
            continue
        body.append(norm)

    # An `ifdef` whose body was entirely exports/comments now wraps nothing. POP has
    # one (the nested blit-export block) that karateka has no counterpart for, so an
    # empty conditional must reduce to nothing or it reads as drift.
    changed = True
    while changed:
        changed, out, i = False, [], 0
        while i < len(body):
            if (i + 1 < len(body)
                    and body[i].split()[0].lower() in ('ifdef', 'ifndef')
                    and body[i + 1].lower() == 'endc'):
                i += 2
                changed = True
            else:
                out.append(body[i])
                i += 1
        body = out
    return body, exports


def compare(a_root, b_root, a_name, b_name):
    drift = []
    for rel in SHARED:
        pa, pb = a_root / rel, b_root / rel
        if not pa.exists() and not pb.exists():
            continue
        if not pa.exists() or not pb.exists():
            if rel in PROJECT_LOCAL:
                continue
            missing = a_name if not pa.exists() else b_name
            drift.append((rel, f'present in one repo, MISSING in {missing}'))
            continue
        ba, ea = normalise(pa)
        bb, eb = normalise(pb)
        if ea != eb:
            only_a, only_b = sorted(ea - eb), sorted(eb - ea)
            bits = []
            if only_a:
                bits.append(f'exported only in {a_name}: {", ".join(only_a)}')
            if only_b:
                bits.append(f'exported only in {b_name}: {", ".join(only_b)}')
            drift.append((rel, 'ABI surface differs -- ' + '; '.join(bits)))
        if ba != bb:
            where = next((i for i, (x, y) in enumerate(zip(ba, bb)) if x != y),
                         min(len(ba), len(bb)))
            ta = ba[where] if where < len(ba) else '(end of file)'
            tb = bb[where] if where < len(bb) else '(end of file)'
            drift.append((rel,
                          f'content differs at substantive line {where + 1}\n'
                          f'        {a_name}: {ta}\n'
                          f'        {b_name}: {tb}'))
    return drift


def main():
    here = pathlib.Path(__file__).resolve().parents[2]
    mine = here.name
    sibling_name = SIBLINGS.get(mine)
    if sibling_name is None:
        print(f'[hal-sync] WARNING: unrecognised repo "{mine}" -- check SKIPPED')
        return 0
    sibling = here.parent / sibling_name
    # Graceful skip. A structurally impossible check must never block a legitimate
    # build, or it gets ripped out of build.bat and enforces nothing thereafter.
    if not (sibling / 'src' / 'hal').is_dir():
        print(f'[hal-sync] WARNING: sibling repo not found at {sibling} '
              f'-- HAL-sync check SKIPPED')
        return 0
    drift = compare(here, sibling, mine, sibling_name)
    if not drift:
        print(f'[hal-sync] OK -- HAL source aligned with {sibling_name} '
              f'({len(SHARED)} files compared, EOL/guard/export-placement normalised)')
        return 0
    print('[hal-sync] *** HAL DRIFT -- BUILD BLOCKED ***')
    print(f'[hal-sync] {mine} vs {sibling_name}')
    for rel, why in drift:
        print(f'[hal-sync]   {rel}: {why}')
    print('[hal-sync] The HAL is ONE kernel in two copies. Reconcile the two files, '
          'then rebuild.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
