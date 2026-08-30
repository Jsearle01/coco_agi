#!/usr/bin/env python3
"""harness/tools/x_liveness.py -- find handlers that hold an object pointer in X across a call.

★★★ THE DEFECT THIS EXISTS TO FIND, STATED ONCE. vm_obj/vm_obj0 return the object's base
address in X. vm_arg -- which every operand accessor (vm_p0..vm_p4, and vm_v0..vm_v2 through
them) goes through -- indexes the bytecode with `ldx vm_code / leax d,x`, so it DESTROYS X.
A handler written in the natural order

        jsr     vm_obj0                 ; X = the object
        jsr     vm_p1                   ; ★ X is now a pointer into the logic's bytecode
        sta     VMO_X,x                 ; writes a coordinate INTO THE BYTECODE

assembles, runs, and corrupts the resident logic instead of moving the object. ★★ It is
invisible to a build and nearly invisible to a state diff: cmdPosition's write lands in the
arena, so what the diff reports is whatever the corrupted bytecode goes on to do, at some later
cycle, in some other variable.

★★ IT IS A CLASS AND NOT AN INSTANCE. Found in vmop_position while bisecting KQ2, it applies to
every handler that interleaves an object pointer with an operand fetch, and the same trap holds
for X across vm_getvar/vm_setvar. Enumerating them mechanically is the whole point -- CLAUDE.md
2H's third check is "grep, do not recall", and a fix applied only where the diff happened to
point would leave the rest of the class in the tree.

The rule enforced: between a `jsr vm_obj*` and the last use of X in that routine, there must be
no `jsr` to any routine not on the X-PRESERVING list. Being wrong in the safe direction, an
unknown callee is treated as clobbering.

★ Reports; does not gate (2N.1). Exit 1 when anything is found, so a caller may choose.
"""
import argparse
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ★ Callees KNOWN to leave X alone. Anything absent is assumed to clobber -- the conservative
# direction, because a false positive costs a comment and a false negative costs a session.
X_SAFE = {
    "vm_obj", "vm_obj0",            # these DEFINE X
    "vmtr_rec",                     # documents "preserves A, B, X, D" and pshs a,b,x
    # ★ These TAKE the object pointer in X and hand it back -- `pshs d ... puls d,pc`, and X is
    # never written. Verified by reading them, not by assuming from the name.
    "vm_objflags_set", "vm_objflags_clr",
}

# ★★★ THE B PASS EXISTS BECAUSE THE X PASS MISSED ITS MIRROR IMAGE. vm_obj's first act is
# `tfr a,b` -- it turns an object NUMBER into an offset -- so it destroys B, and
# `jsr vm_getvar / tfr a,b / clra / jsr vm_obj / stb VMO_DIR,x` stores the object index instead
# of the value. For the ego, whose index is 0, that stores 0, which is indistinguishable from
# "the direction really is 0". larry1 ran 91 correct cycles before it mattered.
# ★★ The X pass had already been built and had already found four real defects, and it could
# not see this one at all: it models one register. **The class is "a value held in a register
# across a call", and the register is not part of the class.**
B_WRITE = re.compile(r"\b(ldb|clrb|comb|negb|incb|decb|lslb|aslb|lsrb|asrb|rolb|rorb|mul"
                     r"|addb|adcb|subb|sbcb|andb|orb|eorb|tfr\s+\w+\s*,\s*b|exg\b"
                     # ★ the 16-bit forms write B as D's low half; omitting them reported
                     # `ldd #0 / std vm_cycle` as a defect, which is the tool crying wolf.
                     r"|ldd|addd|subd)", re.I)
B_READ = re.compile(r"\b(stb|cmpb|bitb|tstb|abx|tfr\s+b\s*,|std|pshs[^;]*\bb\b)", re.I)
# ★ Routines that preserve B. vm_arg brackets its body with `pshs b ... puls b,pc`, and every
# operand accessor reaches B through it. Verified by reading, not assumed from the name.
B_SAFE = {"vm_arg", "vm_p0", "vm_p1", "vm_p2", "vm_p3", "vm_p4", "vmtr_rec",
          # ★ vm_v0/v1/v2 are `jsr vm_pN / jmp vm_getvar`. vm_pN reaches vm_arg (above) and
          # vm_getvar brackets its body `pshs b ... puls b,pc` [vm_state.s:182-189], so the pair
          # is B-preserving. Read, not inferred -- and note vm_obj0 is the SAME SHAPE and is
          # deliberately absent, because vm_obj's first act is `tfr a,b`.
          "vm_v0", "vm_v1", "vm_v2"}

# ★★★★ THE A/D PASS EXISTS BECAUSE THIS TOOL WAS GREEN WHILE THE DEFECT IT WAS BUILT FOR SAT IN
# THE TREE, IN A THIRD REGISTER. T-P0-030: `ldd CP_N / jsr cp_setup` -- and cp_setup ends
# `lda CP_KEY / sta vc_key`, so it returns with A holding the cel's clear key. D is A:B, so a
# loop counter of 1 became (key << 8) | 1: **2,049 repeats for key 8, 769 for key 3, 1 for key
# 0**. The free-run harness did 2,049x the work and the cost figure was unusable.
# ★★ The class was already named twice -- X (four handlers) and B (vm_obj) -- and this checker
# was written to enumerate it. It models exactly those two registers, so it could not see A.
# **"A value held in a register across a call" was the sentence; "X" and "B" were the code.**
# ★★★ THE PASS IS ON **D**, NOT ON A, AND THE NARROWING IS DELIBERATE. A is both a clobbered
# register and this codebase's standard RETURN register: `jsr vm_getvar / tfr a,b` is correct
# code, not a defect, and an A pass reports every one of them. A checker that cries wolf gets
# ignored -- which is the lesson the X pass already learned when its first version reported 17
# sites of which 4 were real.
# ★★ A 16-BIT quantity is the discriminator: a call that returns a byte in A cannot be supplying
# D, so `ldd ... / jsr ... / std` is unambiguous. That is exactly cp_do_free's shape
# (`ldd CP_N / jsr cp_setup / pshs d`) and it is caught without touching the return-value idiom.
# ★ The cost is real and stated: a defect that parks a value in A ALONE still slips through.
#
# ★★★ THE WRITE AND READ SETS ARE DELIBERATELY ASYMMETRIC, AND NARROWING BOTH WAS A MISTAKE THAT
# COST THREE FALSE POSITIVES ON THE REAL TREE. They are not two halves of one list:
#   * WRITE is a LIVENESS KILL. Broad is SAFE -- every mnemonic added can only retire a stale
#     value earlier and REMOVE reports. D is A:B, so anything writing EITHER half kills it.
#     vm_passed is the worked example: `jsr vm_timer_update / lda / jsr vm_getvar / tfr a,b /
#     clra / cmpd #0` rebuilds D entirely, and a narrow set that could not see `tfr a,b` or
#     `clra` reported the cmpd as a use of the pre-call value.
#   * READ is the ACCUSATION. Narrow is safe: 16-bit reads only, because a callee returning a
#     byte in A cannot be supplying D, whereas `tfr a,b` after a call is this codebase's ordinary
#     return-value idiom and must never be flagged.
A_WRITE = re.compile(r"\b(lda|ldb|clra|clrb|coma|comb|nega|negb|inca|incb|deca|decb"
                     r"|lsla|aslb|asla|lslb|lsra|lsrb|asra|asrb|rola|rolb|rora|rorb|mul"
                     r"|adda|addb|adca|adcb|suba|subb|sbca|sbcb|anda|andb|ora|orb|eora|eorb"
                     r"|tfr\s+\w+\s*,\s*[abd]|exg\b|sex"
                     r"|ldd|addd|subd|adcd|sbcd)\b", re.I)
A_READ = re.compile(r"\b(std|cmpd|subd|addd|tfr\s+d\s*,|pshs[^;]*\bd\b)\b", re.I)
A_SAFE = {"vmtr_rec"}

OBJ_FETCH = re.compile(r"\bl?jsr\s+(vm_obj0?)\b", re.I)
JSR = re.compile(r"\bl?jsr\s+([A-Za-z_]\w*)", re.I)
# ★ A USE is an indexed reference through X. `leax`/`ldx`/`puls x` REDEFINE X and are handled
# separately -- counting them as uses reported every loop head as a defect.
USES_X = re.compile(r",\s*-{0,2}x\+{0,2}\b", re.I)
REDEF_X = re.compile(r"\b(ldx|leax|tfr\s+\w+\s*,\s*x)\b", re.I)
PSHS_X = re.compile(r"\bpshs\s+([a-z,\s]+)", re.I)
PULS_X = re.compile(r"\bpuls\s+([a-z,\s]+)", re.I)
LABEL = re.compile(r"^([A-Za-z_]\w*):?\s")
# ★★ AN UNCONDITIONAL BRANCH ENDS A LINEAR BLOCK EXACTLY AS `rts` DOES, and omitting `bra`/`lbra`
# produced a false positive on the real tree. pic_draw.s's vertical loop ends `bra dl_vlp`, so
# control CANNOT fall through into the `dl_nvert:` label below it -- yet the scanner carried the
# loop's `jsr put_pixel` across the label and accused the horizontal branch of using a register
# the vertical branch had dirtied.
# ★★★ NOTE WHAT IS **NOT** DONE HERE: state is not reset at every label. A label reached BY FALL-
# THROUGH is a real continuation, and resetting there would discard the cp_do_free finding, whose
# use site IS a loop-head label (`cp_free_lp: pshs d`). The discriminator is the PRECEDING line,
# not the label -- which is why this lives in the block-terminator set and not in the label rule.
RTS = re.compile(r"\b(rts|bra|lbra)\b|\bpuls\b[^;]*\bpc\b|\bl?jmp\s+\S+", re.I)


def strip(line):
    """Drop full-line comments and the inline half after ';' -- 2N's rule, same shape."""
    s = line.rstrip("\n")
    if s.lstrip().startswith("*") or s.lstrip().startswith(";"):
        return ""
    return s.split(";", 1)[0]


def scan(path):
    """Walk each routine tracking whether the object pointer in X is still the object pointer.

    ★★ THE FIRST VERSION DID NOT MODEL `pshs x` / `puls x` AND REPORTED 17 SITES OF WHICH FOUR
    WERE REAL. Thirteen handlers already bracket the operand fetch correctly, and a report that
    cannot tell them from the broken ones is worse than no report: it makes the correct idiom
    look like the defect and invites "fixing" code that is right. The state machine is small --
    x_live / saved_depth / dirty -- and it is the difference between an instrument and noise.
    """
    findings = []
    lines = path.read_text(errors="replace").splitlines()
    cur_label = "?"
    x_live = False          # X currently holds an object pointer
    dirty = None            # (line, callee) of the call that destroyed it, if any
    saved = 0               # pshs x depth

    for i, raw in enumerate(lines):
        c = strip(raw)
        if not c.strip():
            continue
        lm = LABEL.match(c)
        if lm:
            cur_label = lm.group(1)

        if OBJ_FETCH.search(c):
            x_live, dirty, saved = True, None, 0
            continue

        if RTS.search(c) and not PULS_X.search(c):
            x_live, dirty, saved = False, None, 0
            continue

        m = PSHS_X.search(c)
        if m and re.search(r"\bx\b", m.group(1), re.I):
            saved += 1
            continue
        m = PULS_X.search(c)
        if m and re.search(r"\bx\b", m.group(1), re.I):
            saved = max(0, saved - 1)
            dirty = None                       # ★ restored: X is the object pointer again
            if "pc" in m.group(1).lower():
                x_live = False
            continue

        if REDEF_X.search(c):
            x_live, dirty = False, None
            continue

        call = JSR.search(c)
        if call:
            if call.group(1).lower() not in {s.lower() for s in X_SAFE}:
                if x_live and saved == 0 and dirty is None:
                    dirty = (i + 1, call.group(1))
            continue

        if x_live and dirty and USES_X.search(c):
            findings.append({
                "routine": cur_label, "call_line": dirty[0], "callee": dirty[1],
                "use_line": i + 1, "use": c.strip(),
            })
            x_live, dirty = False, None
    return findings + scan_reg(lines, "B", B_WRITE, B_READ, B_SAFE) \
                    + scan_reg(lines, "D", A_WRITE, A_READ, A_SAFE)


def scan_reg(lines, regname, WRITE, READ, SAFE):
    """The same state machine over one register: value written, call made, value read.

    ★★ PARAMETERISED BY REGISTER, which is the whole correction. The first version hard-coded X;
    the second added a copy for B; T-P0-030 then lost a session to the identical defect in A.
    **The class is "a value held in a register across a call" and the register is not part of
    it** -- so it is an argument now, and adding U or Y is three lines rather than a new pass.
    """
    findings = []
    cur_label = "?"
    b_live = False
    dirty = None
    saved = 0
    tag = regname.lower()[0]

    for i, raw in enumerate(lines):
        c = strip(raw)
        if not c.strip():
            continue
        lm = LABEL.match(c)
        if lm:
            cur_label = lm.group(1)

        if RTS.search(c) and not PULS_X.search(c):
            b_live, dirty, saved = False, None, 0
            continue

        keep = re.compile(r"\b%s\b|\bd\b" % tag, re.I)
        m = PSHS_X.search(c)
        if m and keep.search(m.group(1)):
            # ★★★ ORDER MATTERS AND IT MISSED cp_do_free THE FIRST TIME. `pshs` was matched as a
            # SAVE before it could be seen as a USE, and the matching `puls` then cleared `dirty`
            # -- so `ldd CP_N / jsr cp_setup / pshs d / ... / puls d / subd #1` reported nothing.
            # ★★ A save PROTECTS a value across a following call; it cannot un-corrupt one the
            # PRECEDING call already destroyed. When `dirty` is set, the pshs IS the first read of
            # the corrupt value, and it is the last point at which the tool can still see it.
            if b_live and dirty:
                findings.append({
                    "routine": cur_label, "call_line": dirty[0], "callee": dirty[1],
                    "use_line": i + 1, "use": c.strip(), "reg": regname,
                })
                b_live, dirty = False, None
                continue
            saved += 1
            continue
        m = PULS_X.search(c)
        if m and keep.search(m.group(1)):
            saved = max(0, saved - 1)
            dirty = None
            continue

        call = JSR.search(c)
        if call:
            if call.group(1).lower() not in {s.lower() for s in SAFE}:
                if b_live and saved == 0 and dirty is None:
                    dirty = (i + 1, call.group(1))
            continue

        # ★ a READ before a WRITE, because `stb` reads and `ldb` writes; checking writes first
        # would mark `ldb ,x` as a use of the old value.
        if b_live and dirty and READ.search(c) and not WRITE.search(c):
            findings.append({
                "routine": cur_label, "call_line": dirty[0], "callee": dirty[1],
                "use_line": i + 1, "use": c.strip(), "reg": regname,
            })
            b_live, dirty = False, None
            continue
        if WRITE.search(c):
            b_live, dirty = True, None
    return findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*",
                    default=["src/harness/vm_cmds.s", "src/harness/vm_tests.s",
                             "src/harness/vm_objects.s", "src/harness/vm_cycle.s",
                             "src/harness/vm_run.s"])
    a = ap.parse_args()

    total = 0
    for f in a.files:
        p = pathlib.Path(f)
        if not p.exists():
            print("  (missing) %s" % f)
            continue
        found = scan(p)
        total += len(found)
        print("%-32s %d" % (f, len(found)))
        for d in found:
            reg = d.get("reg", "X")
            print("    %-24s jsr %-16s at line %-5d destroys %s"
                  % (d["routine"], d["callee"], d["call_line"], reg))
            print("        then %s is used at line %-5d: %s" % (reg, d["use_line"], d["use"]))
    print("\n%d site(s) hold a register across a clobbering call" % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
