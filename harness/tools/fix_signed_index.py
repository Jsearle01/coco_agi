#!/usr/bin/env python3
"""harness/tools/fix_signed_index.py -- replace SIGNED accumulator-offset lookups with D-offset.

★★★ THE 6809's 8-BIT ACCUMULATOR-OFFSET INDEXED MODE IS SIGNED. `ldb a,x` with A = $8F reads
X-113, not X+143. Every table lookup in this VM indexed by a byte that can reach $80 was
therefore reading 256 bytes before its table:

    VMOP_ARGS[opcode]      -- opcodes $80-$B6 are 55 of the 183 commands
    VM_VARS[var]           -- ★★★ variables 128-255, which the AC-2 diff compares
    VM_OBJROOMS[object]    -- object numbers up to 255

★★ The 16-bit form (`leax d,x`) is signed too, but with A cleared the offset is 0..255 and
therefore positive -- so `clra / ldb <index> / leax d,x` is the correct idiom and is what this
substitutes. ★ Sites whose index is provably small (flag byte 0-31, test opcode 0-$13, direction
0-8) are left alone and listed, because rewriting them would add instructions for no correctness
gain -- but they are named here so the audit is complete rather than partial.

★ Emits a report; --apply performs the edits. Written to a file and run by path (§2J, L-45).
"""
import argparse
import io
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = pathlib.Path(__file__).resolve().parents[2]

# (file, 1-based line, the exact source line, why it is or is not unsafe)
SAFE_REASON = {
    "flag byte index 0-31", "controller byte index 0-31", "test opcode 0-$13",
    "direction 0-8", "loop table index 0-8", "32-bit accumulator byte 0-3",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    # site -> (pattern to find, replacement, note)
    edits = [
        ("src/harness/vm_core.s",
         "                ldx     #VMOP_ARGS\n"
         "                lda     vm_op\n"
         "                ldb     a,x\n"
         "                clra\n"
         "                addd    vm_ip\n",
         "                ldx     #VMOP_ARGS\n"
         "                clra\n"
         "                ldb     vm_op\n"
         "                leax    d,x                     ; ★ D-offset: UNSIGNED for 0..255\n"
         "                clra\n"
         "                ldb     ,x\n"
         "                addd    vm_ip\n",
         "VMOP_ARGS[opcode] -- opcodes >= $80 read before the table"),

        ("src/harness/vm_core.s",
         "                ldx     #VMTEST_ARGS\n"
         "                ldb     a,x\n"
         "                clra\n"
         "                addd    vm_ip\n",
         "                ldx     #VMTEST_ARGS\n"
         "                clra\n"
         "                tfr     a,b\n"
         "                ldb     vm_op\n"
         "                leax    d,x\n"
         "                clra\n"
         "                ldb     ,x\n"
         "                addd    vm_ip\n",
         "VMTEST_ARGS[test] -- index <= $13, safe today, made uniform"),

        ("src/harness/vm_state.s",
         "vm_getvar:\n"
         "                ldx     #VM_VARS\n"
         "                lda     a,x\n"
         "                rts\n",
         "vm_getvar:\n"
         "                ldx     #VM_VARS\n"
         "                pshs    b\n"
         "                tfr     a,b\n"
         "                clra\n"
         "                leax    d,x                     ; ★ UNSIGNED; vars 128-255 are half\n"
         "                lda     ,x                      ;   the array the AC-2 diff compares\n"
         "                puls    b,pc\n",
         "VM_VARS[var] -- ★★★ variables 128-255"),

        ("src/harness/vm_state.s",
         "vm_setvar:\n"
         "                ldx     #VM_VARS\n"
         "                stb     a,x\n"
         "                rts\n",
         "vm_setvar:\n"
         "                ldx     #VM_VARS\n"
         "                pshs    b\n"
         "                tfr     a,b\n"
         "                clra\n"
         "                leax    d,x                     ; ★ UNSIGNED\n"
         "                puls    b\n"
         "                stb     ,x\n"
         "                rts\n",
         "VM_VARS[var] store -- ★★★ variables 128-255"),

        ("src/harness/vm_cmds.s",
         "vm_objloc_set:\n"
         "                ldx     #VM_OBJROOMS\n"
         "                stb     a,x\n"
         "                rts\n",
         "vm_objloc_set:\n"
         "                ldx     #VM_OBJROOMS\n"
         "                pshs    b\n"
         "                tfr     a,b\n"
         "                clra\n"
         "                leax    d,x                     ; ★ UNSIGNED; object numbers reach 255\n"
         "                puls    b\n"
         "                stb     ,x\n"
         "                rts\n",
         "VM_OBJROOMS[object] store"),

        ("src/harness/vm_cmds.s",
         "vmop_get_room_f:\n"
         "                jsr     vm_v0\n"
         "                ldx     #VM_OBJROOMS\n"
         "                ldb     a,x\n",
         "vmop_get_room_f:\n"
         "                jsr     vm_v0\n"
         "                ldx     #VM_OBJROOMS\n"
         "                tfr     a,b\n"
         "                clra\n"
         "                leax    d,x                     ; ★ UNSIGNED\n"
         "                ldb     ,x\n",
         "VM_OBJROOMS[object] read"),

        ("src/harness/vm_tests.s",
         "vmtest_has:\n"
         "                jsr     vm_p0\n"
         "                ldx     #VM_OBJROOMS\n"
         "                lda     a,x\n",
         "vmtest_has:\n"
         "                jsr     vm_p0\n"
         "                ldx     #VM_OBJROOMS\n"
         "                pshs    b\n"
         "                tfr     a,b\n"
         "                clra\n"
         "                leax    d,x                     ; ★ UNSIGNED\n"
         "                puls    b\n"
         "                lda     ,x\n",
         "VM_OBJROOMS[object] in `has`"),

        ("src/harness/vm_tests.s",
         "vmtest_obj_in_room:\n"
         "                jsr     vm_p0\n"
         "                ldx     #VM_OBJROOMS\n"
         "                lda     a,x\n",
         "vmtest_obj_in_room:\n"
         "                jsr     vm_p0\n"
         "                ldx     #VM_OBJROOMS\n"
         "                pshs    b\n"
         "                tfr     a,b\n"
         "                clra\n"
         "                leax    d,x                     ; ★ UNSIGNED\n"
         "                puls    b\n"
         "                lda     ,x\n",
         "VM_OBJROOMS[object] in `obj.in.room`"),
    ]

    print("SIGNED accumulator-offset audit\n")
    changed = 0
    for rel, find, repl, note in edits:
        p = ROOT / rel
        text = p.read_text(encoding="utf-8")
        n = text.count(find)
        print("  %-26s %-52s %s" % (rel.split("/")[-1], note,
                                    "found" if n == 1 else "★★★ %d matches" % n))
        if n == 1 and a.apply:
            p.write_text(text.replace(find, repl), encoding="utf-8", newline="\n")
            changed += 1

    print()
    print("LEFT ALONE -- index provably < $80, listed so the audit is complete:")
    for s in ("vm_getflag / vm_setflag / vm_ctrl_get   flag byte index 0-31",
              "vm_objects loop tables                  direction 0-8",
              "vm_run vm_dir_table                     direction index 0-8",
              "vm_run vm_mul32 accumulator             byte index 0-3"):
        print("  %s" % s)
    print()
    if a.apply:
        print("applied %d edit(s)" % changed)
    else:
        print("dry run -- re-run with --apply")
    return 0


if __name__ == "__main__":
    sys.exit(main())
