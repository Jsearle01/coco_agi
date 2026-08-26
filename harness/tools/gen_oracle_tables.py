#!/usr/bin/env python3
"""Generate tools/agivm/optable.py from the PINNED oracle's opcodes.cpp.

★★ WHY THIS IS GENERATED AND NOT TYPED. The V2 tables are 20 test opcodes and 183 command
opcodes -- 203 entries, each carrying a name and a parameter-type string that determines how
many bytes the interpreter consumes. Hand-transcribing 203 entries produces a defect surface
larger than the rest of the VM, and every defect in it is a silent instruction-stream
desynchronisation rather than a visible error.

★★ AND IT MUST COME FROM THE ORACLE, NOT THE SPECS. CLAUDE.md §2 ranks ScummVM above the AGI
Specifications, and §2Q pins the exact commit. This reads that commit's own table. Where the
Specs and ScummVM disagree about an opcode's arity, this file follows ScummVM by construction.

★ WHAT THE GENERATED TABLE IS *NOT*: it is not the dispatch table the VM runs. setupOpCodes()
(opcodes.cpp:372) does not load a static table -- it copies a base table and then MUTATES it by
interpreter version, platform, gameID and feature flags. That mutation is applied at runtime by
tools/agivm/dispatch.py, which is where those rules live. This file is only the base.

Usage:
    python harness/tools/gen_opcode_table.py [--scummvm DIR] [--out FILE] [--check]

--check regenerates into memory and compares against the committed file, exiting 1 on drift.
That is what a build step runs: it catches the generated file being edited by hand, which is
the failure this design otherwise invites.
"""
import argparse
import pathlib
import re
import sys

TABLE_RE = r"static const AgiOpCodeDefinitionEntry %s\[\] = \{(.*?)\n\};"

# { "name", "params", &handler },   // XX  optional trailing comment
ENTRY_RE = re.compile(
    r'\{\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(?:&(\w+)|(nullptr|NULL))\s*\}'
)

TABLES = ["opCodesV1Cond", "opCodesV1", "opCodesV2Cond", "opCodesV2"]

# ★ The VM variable and flag numbers are generated for the SAME reason the opcode table is.
# Typing them by hand was tried first and produced three errors in seventeen lines:
# VM_VAR_WINDOW_AUTO_CLOSE_TIMER became "WINDOW_RESET", VM_FLAG_MENUS_ACCESSIBLE became
# "MENUS_WORK", and one line was outright corrupted. None of the three would have raised --
# they would have silently addressed the wrong variable. Read the enum (L-25), do not retype it.
#
# ★ The ViewFlags bits were then typed by hand too, and were wrong in the same way: fDrawn is
# 0x0001 and fAnimated is 0x0040, not the other way round. A wrong bit here does not raise
# either -- it silently tests the wrong property of a screen object. Generated as well.
ENUM_ANCHORS = {
    "VM_VAR": ("agi.h", "VM_VAR_CURRENT_ROOM"),
    "VM_FLAG": ("agi.h", "VM_FLAG_EGO_WATER"),
    "ViewFlag": ("view.h", "fDrawn"),
    "CycleMode": ("view.h", "kCycleNormal"),
    "MotionType": ("view.h", "kMotionNormal"),
    # ★ The startup values of vars 20/22/26. These are the values a game's own scripts branch
    # on to decide what machine they are running on, so they are interpreter-visible state and
    # not presentation. Note the enums are SPARSE (kAgiComputerPC=0 then 3,4,5,7) -- an
    # implicit-increment reading of them would be wrong for every member after the first.
    "ComputerType": ("agi.h", "kAgiComputerPC"),
    "SoundType": ("agi.h", "kAgiSoundPC"),
    "MonitorType": ("agi.h", "kAgiMonitorCga"),
}


# ★ P5.1 (L-29). Integer ARRAYS the motion and animation systems index into. These are the same
# class as the enums: nine-element direction tables where a single transposed entry sends an
# object the wrong way and raises nothing. Two of them (dx/dy) appear TWICE in the oracle --
# motion.cpp:42-43 and checks.cpp:212-213 -- and the generator asserts the duplicates agree
# rather than picking one, because a future divergence between them is a real finding.
ARRAY_ANCHORS = {
    "DIR_TABLE": ("motion.cpp", "dirTable"),
    "DIR_DX": ("motion.cpp", "dx"),
    "DIR_DY": ("motion.cpp", "dy"),
    "LOOP_TABLE_2": ("view.cpp", "loopTable2"),
    "LOOP_TABLE_4": ("view.cpp", "loopTable4"),
}

# name -> (file, identifier) pairs that MUST equal the array of the same name above
ARRAY_DUPLICATE_CHECKS = {
    "DIR_DX": ("checks.cpp", "dx"),
    "DIR_DY": ("checks.cpp", "dy"),
}


def parse_int_array(src, name):
    """Parse `<type> name[...] = { a, b, c };` wherever it appears, file- or function-scope."""
    m = re.search(r"\b%s\s*\[[^\]]*\]\s*=\s*\{([^}]*)\}" % re.escape(name), src, re.S)
    if not m:
        raise SystemExit("array %s not found" % name)
    body = re.sub(r"//[^\n]*", "", m.group(1))
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    out = []
    for tok in body.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if not re.match(r"^-?(0x[0-9a-fA-F]+|\d+)$", tok):
            raise SystemExit("unparsed array element in %s: %r" % (name, tok))
        out.append(int(tok, 0))
    return out


def parse_enum(src, anchor):
    """Parse a C enum body starting at `anchor`, honouring implicit incrementing values."""
    m = re.search(r"enum\s*(?:\w+\s*)?\{([^}]*?\b%s\b[^}]*)\}" % re.escape(anchor), src, re.S)
    if not m:
        raise SystemExit("enum containing %s not found" % anchor)
    # ★ Strip comments from the WHOLE body BEFORE splitting on commas. A comment can itself
    # contain a comma -- kAgiSoundTandy's does -- and splitting first tears it in half, so the
    # fragment then fails to parse. Order matters here.
    body = re.sub(r"//[^\n]*", "", m.group(1))
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    out, nxt = [], 0
    for raw in body.split(","):
        line = raw.strip()
        if not line:
            continue
        em = re.match(
            r"^(\w+)\s*(?:=\s*(?:\(?\s*1\s*<<\s*(\d+)\s*\)?|(-?\d+|0x[0-9a-fA-F]+)))?$", line)
        if not em:
            raise SystemExit("unparsed enum member: %r" % line)
        name, shift, val = em.groups()
        if shift is not None:
            nxt = 1 << int(shift)
        elif val is not None:
            nxt = int(val, 0)
        out.append((name, nxt))
        nxt += 1
    return out


def parse_tables(src):
    out = {}
    for name in TABLES:
        m = re.search(TABLE_RE % name, src, re.S)
        if not m:
            raise SystemExit("table %s not found in opcodes.cpp" % name)
        body = m.group(1)
        entries = []
        for em in ENTRY_RE.finditer(body):
            opname, params, handler, null = em.groups()
            entries.append((opname, params, handler if handler else None))
        # ★ A count check, because a regex that silently matches FEWER entries than the table
        # holds would shift every opcode after the gap and look like a working table.
        braces = body.count("{")
        if len(entries) != braces:
            raise SystemExit(
                "%s: matched %d entries but found %d '{' -- the regex missed one, and a "
                "missed entry silently renumbers every opcode after it"
                % (name, len(entries), braces))
        out[name] = entries
    return out


def render(tables, enums, arrays, pin_commit, src_path):
    L = []
    a = L.append
    a('"""AGI opcode base tables -- GENERATED, DO NOT EDIT BY HAND.')
    a("")
    a("Generated by harness/tools/gen_opcode_table.py from the pinned oracle:")
    a("    commit %s" % pin_commit)
    a("    %s" % src_path)
    a("")
    a("Regenerate:  python harness/tools/gen_opcode_table.py")
    a("Verify:      python harness/tools/gen_opcode_table.py --check")
    a("")
    a("Each entry is (name, parameters, handler). `parameters` is ScummVM's own type string;")
    a("its LENGTH is the instruction's parameter byte count -- opcodes.cpp computes")
    a("parameterSize as strlen(parameters), so every parameter is exactly one byte. The type")
    a("letters are: n = literal number, v = variable number, s = message/string number.")
    a("")
    a("★ TWO ENTRIES CARRY NO HANDLER AND ARE NOT DEFECTS:")
    a("  commands[0x00] 'return'  -- handled inline by the interpreter loop, never dispatched")
    a("  tests[0x00]    ''        -- condUnknown; an illegal test opcode")
    a("")
    a("★ 'said' (test 0x0E) has an EMPTY parameter string and is NOT zero-length. Its operand")
    a("count is read from the instruction stream: a leading byte N, then N 16-bit words.")
    a("op_test.cpp skipInstruction() special-cases it. A table-driven skip that trusts the")
    a("empty string here desynchronises the whole instruction stream.")
    a('"""')
    a("")
    for name in TABLES:
        entries = tables[name]
        pyname = {
            "opCodesV1Cond": "V1_TESTS",
            "opCodesV1": "V1_COMMANDS",
            "opCodesV2Cond": "V2_TESTS",
            "opCodesV2": "V2_COMMANDS",
        }[name]
        a("# %s -- %d entries (opcodes 0x00-0x%02X)" % (name, len(entries), len(entries) - 1))
        a("%s = [" % pyname)
        for i, (opname, params, handler) in enumerate(entries):
            handler_txt = ('"%s"),' % handler) if handler else "None),"
            a("    (%-24s %-10s %-26s  # %02X"
              % ('"%s",' % opname, '"%s",' % params, handler_txt, i))
        a("]")
        a("")
    a("SAID_TEST_OPCODE = 0x0E  # variable length; see module docstring")
    a("")
    for name in sorted(arrays):
        vals = arrays[name]
        a("# %s -- %d entries, generated from the pinned oracle" % (name, len(vals)))
        a("%s = (%s)" % (name, ", ".join(str(v) for v in vals)))
        a("")
    for prefix in sorted(enums):
        members = enums[prefix]
        a("# %s_* -- %d members, from engines/agi/agi.h" % (prefix, len(members)))
        for name, val in members:
            a("%-34s = %d" % (name, val))
        a("")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scummvm", default=r"C:\Projects\scummvm")
    ap.add_argument("--out", default=None)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    repo = pathlib.Path(__file__).resolve().parents[2]
    out = pathlib.Path(args.out) if args.out else repo / "tools" / "agivm" / "optable.py"

    src_path = pathlib.Path(args.scummvm) / "engines" / "agi" / "opcodes.cpp"
    if not src_path.exists():
        raise SystemExit("no opcodes.cpp at %s" % src_path)

    pin = repo / "oracle" / "scummvm.pin"
    pin_commit = "UNKNOWN"
    if pin.exists():
        m = re.search(r"^commit\s*=\s*([0-9a-f]{40})", pin.read_text(encoding="utf-8",
                                                                    errors="replace"),
                      re.M)
        if m:
            pin_commit = m.group(1)

    tables = parse_tables(src_path.read_text(encoding="utf-8", errors="replace"))

    agi_dir = pathlib.Path(args.scummvm) / "engines" / "agi"
    hdr_cache = {}
    enums = {}
    for prefix, (fname, anchor) in ENUM_ANCHORS.items():
        if fname not in hdr_cache:
            hdr_cache[fname] = (agi_dir / fname).read_text(encoding="utf-8", errors="replace")
        enums[prefix] = parse_enum(hdr_cache[fname], anchor)

    arrays = {}
    for name, (fname, ident) in ARRAY_ANCHORS.items():
        if fname not in hdr_cache:
            hdr_cache[fname] = (agi_dir / fname).read_text(encoding="utf-8", errors="replace")
        arrays[name] = parse_int_array(hdr_cache[fname], ident)

    # ★ The duplicated tables are compared, not assumed equal. If the oracle ever lets them
    # drift this fails loudly instead of silently generating one of two different answers.
    for name, (fname, ident) in ARRAY_DUPLICATE_CHECKS.items():
        if fname not in hdr_cache:
            hdr_cache[fname] = (agi_dir / fname).read_text(encoding="utf-8", errors="replace")
        other = parse_int_array(hdr_cache[fname], ident)
        if other != arrays[name]:
            raise SystemExit(
                "%s differs between its two definitions in the oracle: %s has %s, %s has %s"
                % (name, ARRAY_ANCHORS[name][0], arrays[name], fname, other))

    text = render(tables, enums, arrays, pin_commit, "engines/agi/opcodes.cpp + agi.h + view.h")

    for name in TABLES:
        print("  %-16s %3d entries" % (name, len(tables[name])))
    for p in sorted(enums):
        print("  %-16s %3d members" % (p + "_*", len(enums[p])))
    for n in sorted(arrays):
        print("  %-16s %3d entries  %s" % (n, len(arrays[n]), arrays[n]))
    print("  duplicate-array checks: %d, all agree" % len(ARRAY_DUPLICATE_CHECKS))
    v2c, v2 = len(tables["opCodesV2Cond"]), len(tables["opCodesV2"])
    print("  V2 total: %d tests + %d commands = %d" % (v2c, v2, v2c + v2))

    if args.check:
        if not out.exists():
            print("CHECK FAILED: %s does not exist" % out)
            return 1
        if out.read_text(encoding="utf-8").replace("\r\n", "\n") != text:
            print("CHECK FAILED: %s differs from what the pinned oracle generates." % out)
            print("  Either the generated file was hand-edited, or the oracle moved.")
            return 1
        print("CHECK OK: %s matches the pinned oracle." % out)
        return 0

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8", newline="\n")
    print("wrote %s (%d lines)" % (out, text.count("\n") + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
