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
* ★ Addresses are the harness's, not the engine's. §3.2's block allocation governs the engine;
* this probe only has to be self-consistent and out of the way of the code and the LOGIC buffer.
VM_VARS         equ     $2000           ; 256 bytes -- HALF THE DIFF
VM_FLAGS        equ     $2100           ; 32 bytes, packed -- THE OTHER HALF
VM_CTRL         equ     $2120           ; 32 bytes, packed: controllers (cmdController reads)
VM_OBJ          equ     $2140           ; 16 objects x 16 bytes (see VMO_* below)
VM_LOGSTK       equ     $2240           ; call stack: 16 frames x 4 bytes
VM_LOGSTK_TOP   equ     $2280
VM_CODE         equ     $2300           ; the CURRENT logic's bytecode, demand-loaded
VM_CODE_MAX     equ     $2C00           ; 10,496 bytes: the largest logic measured is 10,428
                                        ; (Kingquest3). ★ MEASURED, not assumed -- 133 to 238 KB
                                        ; of LOGIC per title cannot be resident at once, which
                                        ; is why the design says "current LOGIC" singular.

* ── per-object fields (16 bytes each) ─────────────────────────────────────────────
* ★ ONLY the fields the executed opcodes actually read. state.py carries ~25; the gated set
* reaches x, y, view, loop, cel, priority, flags, direction, stepSize, cycle status. Carrying
* the rest would be state the gate cannot check.
VMO_X           equ     0
VMO_Y           equ     1
VMO_VIEW        equ     2
VMO_LOOP        equ     3
VMO_CEL         equ     4
VMO_PRIORITY    equ     5
VMO_FLAGS       equ     6               ; 2 bytes, ViewFlag bits
VMO_DIR         equ     8
VMO_STEPSIZE    equ     9
VMO_CYCLE       equ     10
VMO_MOTION      equ     11
VMO_SIZE        equ     16

* ── interpreter registers ─────────────────────────────────────────────────────────
vm_ip           fdb     0               ; instruction pointer INTO VM_CODE
vm_codelen      fdb     0               ; length of the resident logic
vm_curlogic     fcb     0               ; which logic is resident
vm_logsp        fdb     VM_LOGSTK       ; call-stack pointer
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
                ldd     #0
                std     vm_ip
vm_rl_loop:
                ldd     vm_ip
                cmpd    vm_codelen
                bhs     vm_rl_done              ; ip >= len -- UNSIGNED [L-40]
                lda     vm_quit
                bne     vm_rl_done

                ldx     #VM_CODE
                ldd     vm_ip
                leax    d,x
                lda     ,x                      ; the opcode
                ldb     #1
                stb     vm_tmp8
                ldd     vm_ip
                addd    #1
                std     vm_ip

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
                ldx     #VM_CODE
                ldd     vm_ip
                leax    d,x
                ldb     ,x                      ; low byte first -- LITTLE endian
                lda     1,x
                exg     a,b                     ; D = the signed offset, now big-endian
                addd    #2
                addd    vm_ip
                std     vm_ip
                lbra    vm_rl_loop

vm_rl_return:   lda     #1
                sta     vm_retflag
vm_rl_done:     rts

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
                ldx     #VM_CODE
                ldd     vm_ip
                leax    d,x
                lda     ,x
                ldd     vm_ip
                addd    #1
                std     vm_ip

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
                ldx     #VM_CODE
                ldd     vm_ip
                leax    d,x
                ldb     ,x
                lda     1,x
                exg     a,b                     ; D = skip, big-endian
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
vm_skip_until:
                sta     vm_tmp8
vm_su_lp:       ldx     #VM_CODE
                ldd     vm_ip
                cmpd    vm_codelen
                bhs     vm_su_out
                leax    d,x
                lda     ,x
                ldd     vm_ip
                addd    #1
                std     vm_ip
                cmpa    vm_tmp8
                bne     vm_su_lp
vm_su_out:      rts

* ── vm_skip_instruction -- step ip past one test's operands ───────────────────────
* ★ Operand counts come from the GENERATED table, never from a literal here.
vm_skip_instruction:
                ldx     #VMTEST_ARGS
                lda     vm_op
                ldb     a,x
                clra
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
