* src/harness/vm_tests.s -- the test (condition) opcode handlers.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ TRANSCRIBED FROM tools/agivm/tests.py, itself from op_test.cpp.
*
* ★★ EVERY COMPARISON IS UNSIGNED [L-40]. AGI variables are BYTES with the full 0-255 range,
* and `bmi`/`blt` on a variable is wrong for half of it -- var 6 (ego direction) never exceeds
* 8, but var 0 (current room) and the score vars routinely exceed 127. The 6809's unsigned
* conditions are blo/bls/bhi/bhs and those are the only ones used below.
* ★ The ONE signed quantity in this VM is 0xFE's goto offset, which is handled in vm_core.s and
* is not a test. Knowing which is which is the whole of L-40.
*
* ★ Handlers set vm_testres to 0 or 1. Operands start at vm_ip, exactly as for commands.
* ═══════════════════════════════════════════════════════════════════════════════════════════

* vm_tr_set / vm_tr_clr -- the two endings every test has
vm_tr_true:     lda     #1
                sta     vm_testres
                rts
vm_tr_false:    clr     vm_testres
                rts

* ── comparisons ───────────────────────────────────────────────────────────────────
vmtest_equal:
                jsr     vm_v0
                pshs    a
                jsr     vm_p1
                cmpa    ,s+
                lbeq    vm_tr_true
                lbra    vm_tr_false

vmtest_equal_v:
                jsr     vm_v0
                pshs    a
                jsr     vm_v1
                cmpa    ,s+
                lbeq    vm_tr_true
                lbra    vm_tr_false

* ★ get_var(p0) < p1 -- the operand order matters and so does the unsigned condition.
vmtest_less:
                jsr     vm_p1
                pshs    a
                jsr     vm_v0
                cmpa    ,s+
                lblo    vm_tr_true
                lbra    vm_tr_false

vmtest_less_v:
                jsr     vm_v1
                pshs    a
                jsr     vm_v0
                cmpa    ,s+
                lblo    vm_tr_true
                lbra    vm_tr_false

vmtest_greater:
                jsr     vm_p1
                pshs    a
                jsr     vm_v0
                cmpa    ,s+
                lbhi    vm_tr_true
                lbra    vm_tr_false

vmtest_greater_v:
                jsr     vm_v1
                pshs    a
                jsr     vm_v0
                cmpa    ,s+
                lbhi    vm_tr_true
                lbra    vm_tr_false

* ── flags ─────────────────────────────────────────────────────────────────────────
vmtest_is_set:
                jsr     vm_p0
                jsr     vm_getflag
                sta     vm_testres
                rts

* ★★ NOT a typo for is_set: the parameter names a VARIABLE whose VALUE is the flag number.
* Reading it as "flag p0" tests a different flag and still runs -- tests.py says so in as
* many words, which is why the comment is here rather than trusted to be obvious.
vmtest_is_set_v:
                jsr     vm_v0
                jsr     vm_getflag
                sta     vm_testres
                rts

* ── inventory ─────────────────────────────────────────────────────────────────────
vmtest_has:
                jsr     vm_p0
                ldx     #VM_OBJROOMS
                lda     a,x
                cmpa    #EGO_OWNED
                lbeq    vm_tr_true
                lbra    vm_tr_false

vmtest_obj_in_room:
                jsr     vm_p0
                ldx     #VM_OBJROOMS
                lda     a,x
                pshs    a
                jsr     vm_v1
                cmpa    ,s+
                lbeq    vm_tr_true
                lbra    vm_tr_false

* ── positional ────────────────────────────────────────────────────────────────────
* ★ o.x >= p1 and o.y >= p2 and o.x <= p3 and o.y <= p4, all UNSIGNED.
vmtest_posn:
                jsr     vm_obj0
                pshs    x
                jsr     vm_p1
                ldx     ,s
                cmpa    VMO_X,x
                bhi     vm_posn_false           ; p1 > x  ->  x < p1
                jsr     vm_p2
                ldx     ,s
                cmpa    VMO_Y,x
                bhi     vm_posn_false
                jsr     vm_p3
                ldx     ,s
                cmpa    VMO_X,x
                blo     vm_posn_false           ; p3 < x  ->  x > p3
                jsr     vm_p4
                ldx     ,s
                cmpa    VMO_Y,x
                blo     vm_posn_false
                leas    2,s
                lbra    vm_tr_true
vm_posn_false:  leas    2,s
                lbra    vm_tr_false

* ── input ─────────────────────────────────────────────────────────────────────────
vmtest_controller:
                jsr     vm_p0
                jsr     vm_ctrl_get
                sta     vm_testres
                rts

* ★ §2.1: ScummVM's condHaveKey pumps the event loop and can consume a real keypress. This VM
* is headless with no input source, so this is the "no key waiting" path -- FAITHFUL for a run
* with no input, which is what the diff compares, and WRONG the moment input exists.
vmtest_have_key:
                lda     #VAR_KEY
                jsr     vm_getvar
                tsta
                lbne    vm_tr_true
                lbra    vm_tr_false

* ★★★ `said` MATCHES PARSED INPUT WORDS AND THERE IS NEVER ANY. cycle.py test_said returns
* False unconditionally for the same reason. ★ Its OPERANDS are variable-length and are stepped
* over by vm_skip_instruction's said case, not here -- 28,053 of the gated set's test
* executions are this opcode, so a wrong skip desynchronises almost immediately.
vmtest_said:
                lbra    vm_tr_false
