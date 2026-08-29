* src/harness/vm_core.s -- the AGI VM's state, interpreter loop and condition evaluator.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE REFERENCE IS tools/agivm/, WHICH IS ORACLE-GATED. This is a transcription of
* cycle.py's run_logic() and tests.py's test_if_code(), not a reimplementation from the Specs.
* Where the two disagree the reference wins, because the reference is what AC-2 diffs against
* and the reference is what matches the pin on all 256 variables every cycle.
*
* ★★ WHAT THE DIFF SEES, AND THEREFORE WHAT MUST BE EXACT: 256 variables and 256 flags. Every
* other structure here exists only so that the opcodes writing those two arrays are given
* correct inputs [state.py]. That is the licence for the object table carrying only the fields
* the executed opcodes read, and for `modelled` opcodes changing nothing.
*
* ★★★ FLAGS ARE PACKED, 32 BYTES, and they are packed HERE for the same reason state.py packs
* them there: the oracle's dump emits those 32 bytes verbatim, so storing them unpacked and
* converting at dump time would put a transform between our state and the compared bytes -- and
* a transform is a place a defect can hide on one side only [§2O.1 in spirit].
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ── state layout ──────────────────────────────────────────────────────────────────
* ★★ THE LAYOUT AND THE PER-OBJECT FIELDS MOVED TO vm_state.s. P4.3 declared them here with a
* 16-entry object table; state.py says SCREENOBJECTS_MAX = 255 ("KQ3 uses o255"), and a
* 16-entry table would have let KQ3 write object 255 straight through the LOGIC buffer.
* ★ One home per fact (§2F): vm_state.s owns VM_VARS/VM_FLAGS/VM_OBJ and every VMO_* offset.

* ── interpreter registers ─────────────────────────────────────────────────────────
vm_ip           fdb     0               ; instruction pointer, relative to vm_code
vm_codelen      fdb     0               ; length of the resident logic
vm_curlogic     fcb     0               ; which logic is resident
* ★ vm_logsp is gone: the arena stack (res_open/res_close) IS the logic call stack, so a
* second stack pointer would be a second home for the same fact (§2F).
vm_quit         fcb     0               ; should_quit
vm_exitall      fcb     0               ; exit_all_logics
vm_testres      fcb     0               ; st.test_result
vm_badop        fcb     0               ; the opcode that halted us
vm_badlogic     fcb     0
vm_cycle        fdb     0               ; cycle_nr, for the trace
vm_req          fcb     0               ; ★ demand-load request: logic number
vm_reqpend      fcb     0               ; 1 = host must supply vm_req before we continue

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── vm_run_logic ── interpret the resident logic from ip 0 ────────────────────────
*
* ★★★ TRANSCRIBED FROM cycle.py run_logic(), statement for statement:
*     op 0xFF -> test_if_code
*     op 0xFE -> goto, SIGNED 16-bit little-endian, ip += 2 + off
*     op 0x00 -> return
*     else    -> command; advance ip by VMOP_ARGS[op] AFTER the handler
*
* ★★ THE OFFSET IS SIGNED AND THE COORDINATES ARE NOT [L-40]. `ip += 2 + off` uses a signed
* 16-bit add; the x/y comparisons elsewhere in this VM are UNSIGNED byte compares and use
* bhs/blo. Mixing the two is the defect L-40 exists to name.
* ═══════════════════════════════════════════════════════════════════════════════════════════
vm_run_logic:
* ★★ CLEARED AT ENTRY, AND SAVED/RESTORED BY vm_call_logic. run_logic's result is "did an
* explicit `return` opcode run", which the cycle tests to decide whether to re-run logic.0. A
* nested cmdCall runs its own run_logic, and a callee's `return` would otherwise still be
* showing when logic.0 fell off its end -- so logic.0 would look like it returned when it did
* not, and the cycle would stop re-running it. The two together are what make it per-invocation.
                clr     vm_retflag
                ldd     #0
                std     vm_ip
vm_rl_loop:
                ldd     vm_ip
                cmpd    vm_codelen
                lbhs    vm_rl_done              ; ip >= len -- UNSIGNED [L-40]
                lda     vm_quit
                lbne    vm_rl_done

                ldx     vm_code                 ; ★ a POINTER now: the logic lives in P1.3's arena
                ldd     vm_ip
                leax    d,x
* ★★★ THE OPCODE IS SAVED BEFORE ip IS ADVANCED, AND THAT IS THE WHOLE POINT OF vm_op HERE.
* This read `lda ,x` (the opcode) and then `ldd vm_ip` -- which overwrites A with vm_ip's HIGH
* byte. For any ip below 256 that is zero, so every compare below saw opcode $00 and every
* logic "returned" on its first instruction. ★★ The symptom was silent and total: logic.0 ran,
* set retflag, dispatched nothing, and the state diff reported cycle 1 with thirteen variables
* at zero. The counter that named it was opcount=0 -- no command had EVER dispatched, which no
* amount of staring at the resource layer would have explained [L-37].
                lda     ,x                      ; the opcode
                sta     vm_op                   ; ★ survives the ip update; A does not

* ★★ AN OPCODE TRACE, BUILD-GATED. Hand-tracing the bytecode against the reference was costing
* more than the instrument: this records (ip, opcode) for the first VM_TRACE_MAX steps so the
* host can print exactly where the 6809 and the reference part company. ★ Guarded by -DVM_TRACE
* so the gated build carries none of it -- L-56's other half: do not let the instrument into
* the measurement.
* ★ The 6809 indexes only by A, B or D -- `leax y,x` is not a form, and lwasm reports it as an
* undefined symbol `y` rather than as a bad addressing mode.
                ifdef   VM_TRACE
                clrb                            ; kind 0 = the outer interpreter loop
                jsr     vmtr_rec
                ldx     vm_code
                ldd     vm_ip
                leax    d,x
                endc

                ldd     vm_ip
                addd    #1
                std     vm_ip
                lda     vm_op

                cmpa    #$FF
                beq     vm_rl_if
                cmpa    #$FE
                beq     vm_rl_goto
                tsta
                beq     vm_rl_return

* ---- a command ---------------------------------------------------------------
                sta     vm_op                   ; keep it for the handler and for halts
* ★★ AC-5's COVERAGE, RECORDED BY THE INTERPRETER ITSELF. One byte per opcode, set as it is
* dispatched: "every opcode reached is implemented; every one not reached is listed" cannot be
* answered from the host, because the host cannot see which opcodes a given run took. ★ It is
* also the cheapest possible probe -- two instructions on the dispatch path -- and it doubles as
* the answer to "did this opcode execute at all", which is the question a state diff cannot ask.
                ldx     #VM_OPSEEN
                pshs    a
                clra
                ldb     ,s
                leax    d,x                     ; ★ D-offset: UNSIGNED (the signed-index lesson)
                inc     ,x
                puls    a
* ★★★ THE OPCODE GOES ON THE STACK *HERE*, above the VMOP_TAB index computation and not below
* it. The first version of this fix pushed after the `clra` that zeroes D's high half for the
* table index -- so it pushed 0, and every command looked up VMOP_ARGS[0] = 0 args. ip then
* advanced by the opcode byte alone and the stream desynchronised at the third instruction.
* ★★ A push has to be placed against the LAST WRITE to the register, not against the place the
* value is wanted; `tfr a,b` reads A and `clra` two lines later kills it.
                pshs    a                       ; ★ survives both the index maths and the callee
                ldx     #VMOP_TAB
                tfr     a,b
                clra
                aslb                            ; entry is 2 bytes
                rola
                leax    d,x
                ldx     ,x                      ; X = handler
                ldy     vm_opcount
                leay    1,y
                sty     vm_opcount
* ★★★ THE OPCODE GOES ON THE STACK ACROSS THE HANDLER, because vm_op is a GLOBAL and `call` /
* `call.v` run a whole nested logic that overwrites it. The arg-count lookup below then read the
* CALLEE's last opcode -- $00, `return` -- whose VMOP_ARGS entry is 0, so ip did not advance past
* call.v's operand. The interpreter re-read that operand as an opcode; it is $00, so logic.0
* "returned" three instructions early and the last `call`, `get.posn` and `assignv` never ran.
* ★★ The state diff saw exactly that: var 109, written by the second get.posn, and nothing else.
* ★ FOURTH INSTANCE OF ONE CLASS in this VM -- a per-invocation value kept in a global. The
* others were the opcode in A, retflag, and keepret. **Nesting is what turns a global into a bug,
* and this interpreter nests the moment a logic calls a logic.**
                jsr     ,x
                puls    a                       ; ★ pushed above, before the index maths
* ★ advance by the ARGUMENT COUNT, after the handler, exactly as the reference does. A wrong
* count here desynchronises the stream and every later opcode is garbage -- which is why
* VMOP_ARGS is generated rather than typed.
                ldx     #VMOP_ARGS
                tfr     a,b
                clra
                leax    d,x                     ; ★ D-offset: UNSIGNED for 0..255
                clra
                ldb     ,x
                addd    vm_ip
                std     vm_ip
                lda     vm_exitall
                bne     vm_rl_done
                lbra    vm_rl_loop

vm_rl_if:       jsr     vm_test_if_code
                lbra    vm_rl_loop

* ---- 0xFE goto: SIGNED 16-bit little-endian, ip += 2 + off -------------------
vm_rl_goto:
                ldx     vm_code                 ; ★ a POINTER now: the logic lives in P1.3's arena
                ldd     vm_ip
                leax    d,x
* ★★★ THE LOAD ORDER *IS* THE ENDIAN CONVERSION -- there is nothing left to swap. `ldb ,x`
* takes the LOW byte into B and `lda 1,x` the HIGH byte into A, so D is already the value. An
* `exg a,b` after it inverts a conversion that has already happened. ★★ P1.3 fixed exactly this
* in res_core.s's record length; P4.3 wrote it twice more, here and in the branch skip below,
* and the symptom was a `goto` of 2 becoming 512.
                ldb     ,x                      ; LOW byte -- LITTLE endian
                lda     1,x                     ; HIGH byte; D is now the signed offset
                addd    #2
                addd    vm_ip
                std     vm_ip
                lbra    vm_rl_loop

vm_rl_return:   lda     #1
                sta     vm_retflag
* ★ An UNRESTORED record of where interpretation actually stopped. vm_ip is restored by
* vm_call_logic, so reading it after the call measures the unwind, not the run [L-56 again].
vm_rl_done:     ldd     vm_ip
                std     vm_lastip
                rts

vm_lastip       fdb     0

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── vm_test_if_code ── the condition evaluator (AC-6) ─────────────────────────────
*
* ★★★ TRANSCRIBED FROM tests.py test_if_code(), including the OR state machine, which is the
* part that is easy to get subtly wrong:
*     0xFC  FIRST occurrence enters OR mode; SECOND ends a failed OR expression
*     0xFD  NOT, applying to exactly ONE following test
*     0x00 or 0xFF  end of expression
*     else  evaluate a test opcode, then skip its operands
*
* ★★ A test's operands are skipped by vm_skip_instruction, NOT by a per-opcode length baked in
* here: `said` reads a variable number of operands from the stream and the reference handles it
* in the same place. Duplicating that length knowledge in two places is how the two VMs would
* drift apart on exactly one opcode.
* ═══════════════════════════════════════════════════════════════════════════════════════════
vm_test_if_code:
                clr     vm_notmode
                clr     vm_ormode
                lda     #1
                sta     vm_result

vm_tic_loop:
                ldx     vm_code                 ; ★ a POINTER now: the logic lives in P1.3's arena
                ldd     vm_ip
                leax    d,x
* ★ Same clobber, same fix: the test opcode must survive the ip update.
                lda     ,x
                sta     vm_op
                ldd     vm_ip
                addd    #1
                std     vm_ip
                lda     vm_op

                ifdef   VM_TRACE
                ldb     #1                      ; kind 1 = an evaluator step
                jsr     vmtr_rec
                endc
                cmpa    #$FC
                lbeq    vm_tic_or
                cmpa    #$FD
                lbeq    vm_tic_not
                tsta
                lbeq    vm_tic_end
                cmpa    #$FF
                lbeq    vm_tic_end

* ---- evaluate one test ------------------------------------------------------
                sta     vm_op
* ★★ AC-5 COVERAGE FOR THE *TEST* OPCODE SPACE. The command counter has been here since P4.5 and
* the test counter had not, so "coverage" meant one of the two dispatch classes and the report
* would have compared it against a census counting both. ★★★ CLAUDE.md 2H's worked example is
* exactly this: 319 opcodes across TWO ORTHOGONAL AXES, and a figure can be exactly right while
* meaning something other than what quoting it implies. Tests and commands are separate opcode
* SPACES -- test $01 and command $01 are different instructions -- so they need separate tables.
                ldx     #VM_TESTSEEN
                pshs    a
                clra
                ldb     ,s
                leax    d,x                     ; ★ D-offset: UNSIGNED (the signed-index lesson)
                inc     ,x
                puls    a
                ldx     #VMTEST_TAB
                tfr     a,b
                clra
                aslb
                rola
                leax    d,x
                ldx     ,x
                jsr     ,x                      ; sets vm_testres
                lda     vm_exitall
                bne     vm_tic_true
                jsr     vm_skip_instruction

                lda     vm_notmode
                beq     vm_tic_nonot
                lda     vm_testres              ; NOT applies to exactly one test
                eora    #1
                sta     vm_testres
                clr     vm_notmode
vm_tic_nonot:
                lda     vm_ormode
                beq     vm_tic_and

* ---- in OR mode: a true test short-circuits to the closing 0xFC ---------------
                lda     vm_testres
                lbeq    vm_tic_loop
                lda     #$FC
                jsr     vm_skip_until
                clr     vm_ormode
                lbra    vm_tic_loop

* ---- in AND mode: a false test ends the whole expression ---------------------
vm_tic_and:
                lda     vm_testres
                lbne    vm_tic_loop
                clr     vm_result
                lda     #$FF
                jsr     vm_skip_until
                lbra    vm_tic_end

* ★ tests.py: `if st.exit_all_logics: return True` -- the expression evaluates TRUE and the
* branch word is NOT consumed, because run_logic is about to unwind anyway.
vm_tic_true:    lda     #1
                sta     vm_result
                rts

vm_tic_or:
                lda     vm_ormode
                beq     vm_tic_or_enter
* ★ SECOND 0xFC with nothing true: the whole expression is false.
                lda     #$FF
                jsr     vm_skip_until
                clr     vm_result
                lbra    vm_tic_end
vm_tic_or_enter:
                lda     #1
                sta     vm_ormode
                lbra    vm_tic_loop

vm_tic_not:     lda     #1
                sta     vm_notmode
                lbra    vm_tic_loop

* ---- the branch itself -------------------------------------------------------
* ★★ After the expression, the stream carries a 16-bit LITTLE-ENDIAN skip. A true expression
* steps over it and runs the block; a false one adds it.
vm_tic_end:
                ifdef   VM_TRACE
                lda     vm_result
                ldb     #2                      ; kind 2 = expression end; A carries the result
                jsr     vmtr_rec
                endc
                ldx     vm_code                 ; ★ a POINTER now: the logic lives in P1.3's arena
                ldd     vm_ip
                leax    d,x
* ★ Same conversion, same non-swap: B = low, A = high, D = the skip. This one cost the gate --
* the whole IF block was skipped by 512 bytes instead of 2, so logic.0 executed no command at
* all and the diff reported thirteen variables stuck at zero.
                ldb     ,x                      ; LOW byte
                lda     1,x                     ; HIGH byte
                pshs    d
                ldd     vm_ip
                addd    #2
                std     vm_ip                   ; past the skip word
                lda     vm_result
                bne     vm_tic_taken
                puls    d
                addd    vm_ip
                std     vm_ip                   ; false: skip the block
                rts
vm_tic_taken:   leas    2,s                     ; true: fall into the block
                rts

* ── vm_skip_until -- advance ip past the next occurrence of A ─────────────────────
*
* ★★★ IT DECODES; IT DOES NOT SCAN FOR A BYTE VALUE. The first version compared each byte
* against the target and stopped on a match, which finds the target inside an OPERAND. A test
* like `equaln v255 252` puts $FF and $FC directly in the stream, so a raw scan for $FF ends the
* skip in the middle of an instruction and every byte after it is read at the wrong alignment.
* ★★ tests.py skip_instructions_until() reads an opcode, then calls skip_instruction() to step
* over ITS operands, and only a byte in OPCODE POSITION can match. That is the whole difference,
* and it is invisible until a logic happens to compare against 252-255.
vm_skip_until:
                sta     vm_sutarget
* ★★★ ADVANCE ip BEFORE READING THE OPCODE. `ldd vm_ip` puts ip_hi in A; `lda ,x` then
* overwrites A with the OPCODE, so a following `addd #1` adds one to (opcode:ip_lo) rather than
* to ip. At ip=4 in KQ1's logic.0 the byte there is $FF, so ip became $FF05 = 65285, the outer
* loop saw ip >= codelen, and logic.0 "ended" on its first `if` -- forever.
* ★★ THIRD INSTANCE OF THE SAME CLASS IN THIS VM: the opcode clobber in vm_run_logic and the
* one in vm_test_if_code were the first two, and I introduced THIS one myself while rewriting
* the routine to decode rather than scan. **`ldd`/`ldx` for arithmetic and `lda` for a byte read
* share A, and the read must not sit between the load and the use.**
vm_su_lp:       ldd     vm_ip
                cmpd    vm_codelen
                bhs     vm_su_out               ; UNSIGNED [L-40]
                ldx     vm_code                 ; ★ a POINTER now: the logic lives in P1.3's arena
                leax    d,x
                addd    #1
                std     vm_ip                   ; ★ ip advanced while D still holds ip
                lda     ,x                      ; ★ only now is A free for the opcode
                cmpa    vm_sutarget
                beq     vm_su_out
* ★ operands are stepped over by the SAME routine the evaluator uses, so the two cannot drift
                sta     vm_op
                jsr     vm_skip_instruction
                bra     vm_su_lp
vm_su_out:      rts

* ── vm_skip_instruction -- step ip past one test's operands ───────────────────────
* ★ Operand counts come from the GENERATED table, never from a literal here.
*
* ★★★ THREE CASES, AND THE REFERENCE HAS ALL THREE [tests.py skip_instruction()]:
*     op >= $FC        -- a marker, no operands at all
*     op == $0E (said) -- VARIABLE: a count byte, then that many 16-bit words
*     otherwise        -- VMTEST_ARGS[op]
* ★★ VMTEST_ARGS[$0E] is 0, so without the said case the evaluator steps ip by ZERO and then
* reads said's own count byte as the next opcode. 28,053 of the gated set's test executions are
* `said`, so this is not an edge case -- it is the second most common test after `isset`.
VM_SAID_OP      equ     $0E             ; = optable.SAID_TEST_OPCODE
vm_skip_instruction:
                lda     vm_op
                cmpa    #$FC
                bhs     vm_si_out               ; a marker carries no operands
                cmpa    #VM_SAID_OP
                beq     vm_si_said
                ldx     #VMTEST_ARGS
                clra
                tfr     a,b
                ldb     vm_op
                leax    d,x
                clra
                ldb     ,x
                addd    vm_ip
                std     vm_ip
vm_si_out:      rts

* said: ip += code[ip] * 2 + 1
vm_si_said:     ldx     vm_code
                ldd     vm_ip
                leax    d,x
                ldb     ,x                      ; the word count
                clra
                aslb
                rola                            ; D = count * 2
                addd    #1                      ; + the count byte itself
                addd    vm_ip
                std     vm_ip
                rts

* ── halts ─────────────────────────────────────────────────────────────────────────
* ★★★ AC-5: an unimplemented opcode HALTS with its number and the logic that used it. It does
* not no-op. A silent no-op desynchronises nothing and diverges everything, so the diff would
* name a symptom hundreds of cycles after the cause.
vm_op_unimpl:
                lda     vm_op
                sta     vm_badop
                lda     vm_curlogic
                sta     vm_badlogic
                lda     #1
                sta     vm_quit
                sta     vm_exitall
                rts
vm_test_unimpl: bra     vm_op_unimpl

* ── vm_op_modelled -- a DECLARED no-op ────────────────────────────────────────────
* ★★ Presentation-only opcodes, classified by the REFERENCE (dispatch.py's `modelled`), not by
* this file. Their arguments are still consumed, because VMOP_ARGS advances ip regardless.
* ★ This is not the silent no-op AC-5 forbids: it is declared, generated from the reference's
* own classification, and listed in the coverage report.
vm_op_modelled: rts
vm_op_return:   lda     #1
                sta     vm_retflag
                rts

vm_op           fcb     0
vm_tmp8         fcb     0
vm_notmode      fcb     0
vm_ormode       fcb     0
vm_result       fcb     0
vm_retflag      fcb     0
vm_sutarget     fcb     0
vm_opcount      fdb     0

* ═══════════════════════════════════════════════════════════════════════════════════
* ── vmtr_rec ── the build-gated execution trace, 4 bytes per step ────────────────
*
* ★★ A TRACE OF THE OUTER LOOP ALONE WAS NOT ENOUGH. It showed 199 entries all reading
* (ip=0, op=$FF) -- i.e. 199 fresh invocations of vm_run_logic -- which proves the first `if`
* sends ip out of range but says nothing about WHERE inside the evaluator it happens. The KIND
* byte lets the evaluator record its own steps in the same buffer, so the sequence reads as one
* interleaved story rather than two.
*
* in: A = opcode, B = kind (0 outer loop, 1 evaluator step, 2 expression end, 3 skip_until)
* ★ Preserves A, B, X, D. The caller reloads X/D anyway, but a diagnostic that perturbs the
* thing it measures is the failure mode this whole task keeps meeting [L-56].
                ifdef   VM_TRACE
* ★★★ 384 ENTRIES, NOT 2,000, AND THE CEILING IS THE HOST'S EYESIGHT RATHER THAN RAM.
* The buffer was at $9400 "in free RAM above the object table". It is free, and it is also in
* MMU slot 4 -- which mem_probe.lua proved the host CANNOT READ: MAME's CPU `program` space
* does not follow the GIME map above $8000, so `prog:read_u8` there returns unrelated ROM-ish
* constants. **The dump was near-uniform plausible garbage that read as instruction pointers.**
* VM_OPSEEN moved out of $9300 for exactly this reason and the trace buffer was left behind.
* ★★ $2A00..$2FFF is the largest host-readable hole: above VM_OPSEEN ($2900) and below
* RES_DIRS ($3000). 384 entries is what fits, and it fits EXACTLY.
VMTR_MAX        equ     384
* ★★ A WINDOW, BECAUSE A PREFIX NO LONGER REACHES. Logic 0 alone is 719 reference steps in
* cycle 0 and the halt is at opcount 2,587, so no affordable buffer holds the run from step
* zero. vmtr_from is set by the HOST before the run; the first VMTR_MAX steps at or after it
* are recorded. Bisecting the window against the reference costs one MAME launch per probe and
* is the only thing that finds a first divergence 2,000 steps in [L-36].
vmtr_rec:
                pshs    a,b,x
* ★★★ LOGIC-0 ONLY, MATCHING vm_reftrace.py's --logic FILTER. The guest recorded every logic
* and the reference recorded one, so the two traces described different things and every line
* after the first nested call was a false divergence. **A diff is only evidence when both sides
* were asked the same question.**
                lda     vm_curlogic
                cmpa    vmtr_logic
                bne     vmtr_out
                ldd     vmtr_seen
                addd    #1
                std     vmtr_seen
                subd    #1
                cmpd    vmtr_from
                blo     vmtr_out                ; before the window
                ldd     vmtr_idx
                cmpd    #VMTR_MAX*4
                bhs     vmtr_out
                ldx     #vmtr_buf
                leax    d,x
                addd    #4
                std     vmtr_idx
                lda     vm_ip
                sta     ,x
                lda     vm_ip+1
                sta     1,x
                lda     ,s                      ; the opcode as passed
                sta     2,x
                lda     1,s                     ; the kind
                sta     3,x
vmtr_out:       puls    a,b,x,pc

vmtr_idx        fdb     0
vmtr_seen       fdb     0                       ; matching steps SEEN, window or not
vmtr_from       fdb     0                       ; ★ host-settable window start
vmtr_logic      fcb     0                       ; ★ host-settable logic filter
vmtr_buf        equ     $6500
                endc
