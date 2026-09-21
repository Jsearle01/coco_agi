#!/usr/bin/env python3
"""pc_profile.py -- attribute p3b_run.lua's P3B_PROFILE samples to routines and subsystems.
[T-P0-129 §4B]

    pc_profile.py <profile.txt> <p3b_probe_pk.map> [--top 25] [--vs <profile.txt>]

★★★★ ROUTINE, NOT LABEL. The map carries every label, loop heads included (`al_lp`, `co_cc_lp`),
so nearest-label-below would split one routine across its loops. A ROUTINE ENTRY is a label that
something CALLS or VECTORS to: the target of jsr/bsr/lbsr/jmp, or of an `fdb` (the opcode tables
reach every handler that way). A sample is charged to the nearest routine entry at or below its
PC. ★★ Stated because it is a heuristic: a routine entered only by fall-through, or only by a
branch, is folded into the routine above it -- which is the right answer for a loop head and the
wrong one for an un-called routine laid out after another. The per-LABEL table is printed too, so
a reader can see what each routine row is made of.

★★★ FILE, FROM THE SOURCE. The map says where a label is, not which file defined it; the file
comes from a column-0 definition in src/**/*.s. The subsystem is a function of the file and, for
the probe (which holds several subsystems), of the routine name -- the table is below, in one home.

★★★ THE MMU BLOCK IS CHECKED. Each sample carries the block behind PC's slot. Slots 0,1,2,7 are
never remapped, so a PC there is unambiguous; a PC in slots 3-6 is running code out of a window
and is reported separately rather than attributed from a map that describes the image, not the
window. [§6's stop trigger: a PC not attributable to one routine.]
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

CALLS = re.compile(r"^(?:[A-Za-z_][\w@]*:?)?\s+(jsr|bsr|lbsr|jmp)\s+([A-Za-z_][\w@]*)\s*$", re.I)
FDB = re.compile(r"^\s*(?:\w+\s+)?fdb\s+(.*)$", re.I)
LABEL = re.compile(r"^([A-Za-z_][\w@]*)(?::)?(?:\s|$)")

# ★★★ SUBSYSTEM TABLE -- one home. File first; the probe and the HAL split by routine name.
FILE_SUBSYS = {
    "vm_core.s": "VM interpret", "vm_run.s": "VM interpret", "vm_cmds.s": "VM interpret",
    "vm_tests.s": "VM interpret", "vm_state.s": "VM interpret", "vm_tables.s": "VM interpret",
    "vm_objects.s": "object update / motion", "vm_cycle.s": "VM cycle / pacing",
    "res_core.s": "resource manager", "res_check.s": "resource manager",
    "plane_win.s": "plane window access", "pic_core.s": "picture render",
    "view_cel.s": "cel decode / blit", "composite.s": "compositor",
    "mmu_phase.s": "MMU phase switches", "text.s": "text", "vm_text_ops.s": "text",
    "vm_pic_ops.s": "picture render", "parser.s": "parser",
    "irq_vbl.s": "IRQ handler", "time.s": "IRQ handler", "input.s": "key scan",
}
PROBE_RULES = [   # (regex on routine name, subsystem) -- first match wins
    (r"^p3_(irq|vbl_latch)", "IRQ handler"),
    (r"^(p3_(poll|key|kq)|HAL_key)", "key scan"),
    (r"^(p3_restore|prp_)", "restore walk"),
    (r"^p3_(rb|save)", "compositor"),
    (r"^p3_(composite|comp|cp_|spr|stage|draw_obj|blit)", "compositor"),
    (r"^p3_(pic|room)", "picture render"),
    (r"^p3_(enter_vm|phase)", "MMU phase switches"),
    (r"^p3_(loop|wait)$", "harness handshake park"),
]


def load_map(path):
    syms = {}
    for line in Path(path).read_text(errors="replace").splitlines():
        mm = re.match(r"^Symbol:\s+(\S+)\s+\(.*\)\s+=\s+([0-9A-Fa-f]+)$", line)
        if mm:
            syms[mm.group(1)] = int(mm.group(2), 16)
    return syms


def scan_source():
    """label -> set(files) defining it; set of routine-entry names."""
    defs, entries = defaultdict(set), set()
    for f in sorted((ROOT / "src").rglob("*.s")):
        for raw in f.read_text(errors="replace").splitlines():
            line = raw.split(";", 1)[0].rstrip()
            if not line:
                continue
            lm = LABEL.match(line)
            if lm and lm.group(1).lower() not in ("if", "ifdef", "ifndef", "endc", "else"):
                defs[lm.group(1)].add(f.name)
            cm = CALLS.match(line)
            if cm:
                entries.add(cm.group(2))
            fm = FDB.match(line)
            if fm:
                for tok in fm.group(1).split(","):
                    tok = tok.strip()
                    if re.match(r"^[A-Za-z_]\w*$", tok):
                        entries.add(tok)
    return defs, entries | EXTRA_ENTRIES


# ★★ Entered by FALL-THROUGH, so no call names them -- the heuristic's stated blind spot. Found
# as "<below first routine>" in the first castle profile (38 samples at $20E3-$20FA) and named
# here rather than left unattributed.
EXTRA_ENTRIES = {"p3_loop"}


def subsystem(name, files):
    fs = sorted(files) if files else ["?"]
    for f in fs:
        if f in FILE_SUBSYS:
            return FILE_SUBSYS[f]
    for pat, sub in PROBE_RULES:
        if re.search(pat, name):
            return sub
    if any(f in ("sys.s", "gfx.s", "mem.s", "hal_globals.s", "sound.s", "file.s", "disk_read.s")
           for f in fs):
        return "HAL other"
    return "other (" + "/".join(fs) + ")"


def load_profile(path):
    hdr, samples = "", Counter()
    for line in Path(path).read_text().splitlines():
        if line.startswith("#"):
            hdr = line
            continue
        pc, blk, ph, c = line.split()
        samples[(int(pc, 16), int(blk, 16), int(ph, 16))] += int(c)
    return hdr, samples


# P3_PHASE: odd = inside that stage, even = between stages [p3b_run.lua MARK].
MARK = {1: "pace(wait)", 3: "interpret", 5: "sprites", 7: "roomcheck", 9: "composite"}


def stage_of(ph):
    return MARK.get(ph, f"between stages (P3_PHASE={ph})")


def attribute(samples, syms, defs, entries):
    code = sorted((a, n) for n, a in syms.items() if n in defs and a >= 0x0100)
    routines = sorted((a, n) for a, n in code if n in entries)
    ra = [a for a, _ in routines]
    la = [a for a, _ in code]
    import bisect
    by_routine, by_label, windowed, blocks = Counter(), Counter(), Counter(), defaultdict(Counter)
    by_stage_routine = defaultdict(Counter)
    for (pc, blk, ph), c in samples.items():
        slot = pc >> 13
        blocks[slot][blk & 0x3F] += c      # ★ top two bits of an MMU read are not driven
        if 3 <= slot <= 6:
            windowed[(pc, blk)] += c
        i = bisect.bisect_right(ra, pc) - 1
        r = routines[i][1] if i >= 0 else f"<below first routine: ${pc:04X}>"
        by_routine[r] += c
        by_stage_routine[stage_of(ph)][r] += c
        j = bisect.bisect_right(la, pc) - 1
        by_label[code[j][1] if j >= 0 else f"<below first label: ${pc:04X}>"] += c
    return by_routine, by_label, windowed, blocks, by_stage_routine


def main():
    args = sys.argv[1:]
    top = 25
    if "--top" in args:
        k = args.index("--top"); top = int(args[k + 1]); del args[k:k + 2]
    vs = None
    if "--vs" in args:
        k = args.index("--vs"); vs = args[k + 1]; del args[k:k + 2]
    prof, mapf = args
    syms = load_map(mapf)
    defs, entries = scan_source()
    hdr, samples = load_profile(prof)
    total = sum(samples.values())
    by_r, by_l, windowed, blocks, by_sr = attribute(samples, syms, defs, entries)
    print(hdr)
    print("\nSAMPLES BY STAGE (compare with the write-tapped stage timer, which is exact)")
    for s, cnt in sorted(by_sr.items(), key=lambda kv: -sum(kv[1].values())):
        n = sum(cnt.values())
        top3 = ", ".join(f"{r} {100*c/n:.0f}%" for r, c in cnt.most_common(4))
        print(f"  {s:<30} {n:>7} {100*n/sum(samples.values()):>6.1f}%   [{top3}]")
    print(f"samples {total}, routine entries known {len([n for n in syms if n in entries])}")
    print("\nMMU block behind PC's slot (slot: block=count):")
    for s in sorted(blocks):
        print(f"  slot {s}: " + ", ".join(f"${b:02X}={c}" for b, c in blocks[s].most_common()))
    print(f"  PCs in remapped slots 3-6: {sum(windowed.values())} samples"
          + (" -- ★★★ NOT attributable from the image map" if windowed else ""))

    print(f"\nTOP {top} ROUTINES")
    print(f"  {'#':>2} {'routine':<24} {'file':<16} {'subsystem':<24} {'samples':>7} {'share':>6}")
    for i, (n, c) in enumerate(by_r.most_common(top), 1):
        f = "/".join(sorted(defs.get(n, {"?"})))
        print(f"  {i:>2} {n:<24} {f:<16} {subsystem(n, defs.get(n)):<24} {c:>7} {100*c/total:>5.1f}%")
    shown = sum(c for _, c in by_r.most_common(top))
    print(f"     top {top} cover {100*shown/total:.1f}% of samples; {len(by_r)} routines seen")

    print("\nBY SUBSYSTEM (every sample, sums to 100%)")
    sub = Counter()
    for n, c in by_r.items():
        sub[subsystem(n, defs.get(n))] += c
    for s, c in sub.most_common():
        print(f"  {s:<28} {c:>7} {100*c/total:>6.1f}%")
    print(f"  {'SUM':<28} {sum(sub.values()):>7} {100*sum(sub.values())/total:>6.1f}%")

    print("\nTOP 40 LABELS (what the routine rows are made of)")
    for n, c in by_l.most_common(40):
        print(f"  {n:<24} {c:>7} {100*c/total:>5.1f}%")

    if vs:
        _, s2 = load_profile(vs)
        t2 = sum(s2.values())
        r2 = attribute(s2, syms, defs, entries)[0]
        sub2 = Counter()
        for n, c in r2.items():
            sub2[subsystem(n, defs.get(n))] += c
        print(f"\nBIAS: this profile vs {vs} ({t2} samples), subsystem share difference")
        for s in sorted(set(sub) | set(sub2), key=lambda s: -sub[s]):
            a, b = 100 * sub[s] / total, 100 * sub2[s] / t2
            print(f"  {s:<28} {a:>6.1f}% vs {b:>6.1f}%   diff {b - a:>+6.1f}")


if __name__ == "__main__":
    main()
