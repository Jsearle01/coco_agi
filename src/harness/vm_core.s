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
                pshs    a
                ldd     vmtr_idx
                cmpd    #VMTR_MAX*3
                bhs     vm_rl_notr
                ldx     #vmtr_buf
                leax    d,x
                addd    #3
                std     vmtr_idx
                ldb     vm_ip
                stb     ,x
                ldb     vm_ip+1
                stb     1,x
                lda     ,s
                sta     2,x
vm_rl_notr:     puls    a
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
                jsr     ,x
* ★ advance by the ARGUMENT COUNT, after the handler, exactly as the reference does. A wrong
* count here desynchronises the stream and every later opcode is garbage -- which is why
* VMOP_ARGS is generated rather than typed.
                ldx     #VMOP_ARGS
                lda     vm_op
                ldb     a,x
                clra
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

                cmpa    #$FC
                beq     vm_tic_or
                cmpa    #$FD
                beq     vm_tic_not
                tsta
                beq     vm_tic_end
                cmpa    #$FF
                beq     vm_tic_end

* ---- evaluate one test ------------------------------------------------------
                sta     vm_op
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
                ldd     vm_ip
                std     vmtr_endip              ; ★ where the expression finished
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
                ifdef   VM_TRACE
                std     vmtr_skip               ; ★ the branch word as READ
                endc
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
vm_su_lp:       ldd     vm_ip
                cmpd    vm_codelen
                bhs     vm_su_out               ; UNSIGNED [L-40]
                ldx     vm_code                 ; ★ a POINTER now: the logic lives in P1.3's arena
                leax    d,x
                lda     ,x
                addd    #1
                std     vm_ip
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
                ldb     a,x
                clra
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

                ifdef   VM_TRACE
VMTR_MAX        equ     400
vmtr_idx        fdb     0
vmtr_buf        rmb     VMTR_MAX*3
vmtr_endip      fdb     0
vmtr_skip       fdb     0
                endc
