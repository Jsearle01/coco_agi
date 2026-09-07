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
                pshs    b
                tfr     a,b
                clra
                leax    d,x                     ; ★ UNSIGNED
                puls    b
                lda     ,x
                cmpa    #EGO_OWNED
                lbeq    vm_tr_true
                lbra    vm_tr_false

vmtest_obj_in_room:
                jsr     vm_p0
                ldx     #VM_OBJROOMS
                pshs    b
                tfr     a,b
                clra
                leax    d,x                     ; ★ UNSIGNED
                puls    b
                lda     ,x
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

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ `said` NOW CALLS THE PORTED PARSER [T-P0-060]. It was `lbra vm_tr_false`, honestly
* declared as "correct for a headless run and wrong the moment input exists" -- and the parser
* was a function with no caller. This is the caller.
*
* ★★★★ IT IS STILL INERT UNTIL INPUT IS FED, AND THAT IS BY CONSTRUCTION, NOT BY AN ifdef.
* par_said's first two instructions are testSaid's own guard: reject if par_accepted, reject if
* NOT par_cli. par_cli is set only by par_parse, which runs only when the host feeds input. So
* on every run that feeds none -- which is every existing VM gate run -- this returns false on
* the guard exactly as the stub did. **The nine-title gate is unmoved by construction rather
* than by a build flag**, which is the same property cycle.py:83 claims for the Python leg.
*
* ★★★★★ THE VM FLAGS ARE THE HOME OF RECORD AND par_cli/par_accepted ARE PARAMETERS (§2F).
* parser.s owns two bytes with those names, and the temptation is to read that as a second home
* for flags 2 and 4. It is not: parser.py's test_said() takes both as ARGUMENTS and returns the
* new accepted_input, so on the 6809 they are the argument and return slots of the same call.
* ★★★ The marshalling is therefore in ONE place -- here and vp_feed -- rather than distributed,
* because two copies of a flag that are synchronised in several places are a second home in
* everything but name, and the AC-2 diff reads VM_FLAGS, not parser.s's bytes.
*
* ★★ ORDER MATTERS TWICE. vm_getflag and vm_setflag both load X, so X must be computed AFTER
* the two getflag calls; and vm_setflag clobbers CC, so par_said's Z answer is turned into a
* byte BEFORE the flag is published.
* ★ X -> the operand block: vm_test_if_code has already stepped vm_ip past the opcode byte
* (vm_core.s:233-236), so vm_code+vm_ip is said's own count byte -- the same window cycle.py
* slices as code[ip:ip+16]. vm_skip_instruction steps over the operands afterwards, unchanged.
* ★★★★ THE WIRING'S OWN COVERAGE, AND IT IS NOT DECORATION. "The state diff is clean" is exactly
* what the STUB produced, so a clean diff proves nothing about this path unless the path was
* reached. These two say it was: they mirror cycle.py's said_seen / said_matched, and the host
* prints both sides. ★★ vm_fedn is the same question one level up -- did the input arrive at all.
* ★ Read by the host through the symbol map, never by address [vm_probe.s].
vm_saidn        fdb     0               ; said() evaluations
vm_saidm        fdb     0               ; ... of which matched
vm_fedn         fcb     0               ; inputs fed (vp_feed)

vmtest_said:
                ldd     vm_saidn
                addd    #1
                std     vm_saidn
                lda     #FLAG_SAID_ACCEPTED
                jsr     vm_getflag
                sta     par_accepted
                lda     #FLAG_ENTERED_CLI
                jsr     vm_getflag
                sta     par_cli
                ldx     vm_code
                ldd     vm_ip
                leax    d,x
                jsr     par_said                ; Z set = matched; updates par_accepted
                bne     vm_said_no
                ldd     vm_saidm
                addd    #1
                std     vm_saidm
                lda     #1
                bra     vm_said_pub
vm_said_no:     clra
vm_said_pub:    sta     vm_testres
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ VM_FAULT_SAID_PURE -- THIS TASK'S OWN INJECTED FAULT [L-62, §2W.1].
* ★★★★ THE FAULT MUST BE IN THE CODE THIS TASK WROTE. parser.s already carries
* PAR_FAULT_FIRST_MATCH and is gated at 23,328 cases -- but P6.3 measured that fault as
* **match differs 0 on all five titles**, so it is the wrong instrument here: it would not fail
* this gate, and a fault that cannot fail proves nothing about it. What is new here is the
* WIRING, so the fault is in the wiring.
* ★★★★ TREAT said() AS PURE: evaluate the match but do not publish par_accepted back into
* FLAG_SAID_ACCEPTED. **That is the plausible version, not a strawman** -- said() reads like a
* predicate, the side effect is one line, and parser.s's own header names this exact mistake:
* "A matcher that treats said() as pure picks the same set of matching patterns and fires the
* wrong NUMBER of them, which is a game responding to the wrong sentence."
* ★★★ It is deliberately invisible until a line matches: with the flag never set, every LATER
* said() in the same cycle passes the guard that should have rejected it, so the first cycle in
* which two patterns could match is the first cycle that diverges.
* ★★ Off unless -DVM_FAULT_SAID_PURE. Never set in a gate run.
                ifndef  VM_FAULT_SAID_PURE
                lda     #FLAG_SAID_ACCEPTED
                ldb     par_accepted
                jsr     vm_setflag
                endc
                rts
