* src/harness/parser_probe.s -- run the ported parser over the gate's cases. [T-P0-059 AC-7]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE SAME CASES THE PYTHON REFERENCE RAN. harness/tools/said_gate.py emits
* oracle_parser_cases.txt for the oracle; parser_gate.lua stages that same file here, byte for
* byte, and the results are diffed against tools/agivm/parser.py's. **The 6809 is compared
* against the Python, and the Python is already compared against the oracle** -- so the chain
* runs 6809 -> Python -> ScummVM without this probe needing an emulated ScummVM.
*
* ★★★ WHY NOT DIFF THE 6809 DIRECTLY AGAINST THE ORACLE: it would be the same comparison with a
* longer chain and one more thing to get wrong. The Python leg is gated at 23,328 cases across
* five titles with zero divergence [T-P0-059 AC-2/AC-3], so it is a sound reference. ★★ If this
* probe ever diverges from the Python, bisecting is one step [L-36].
*
* ★ Flat map: this probe has the whole 64 KB and stages one vocabulary. The WINDOWED question is
* answered elsewhere and by measurement -- every WORDS.TOK in the corpus is under 8,192 bytes, so
* one window holds any of them [parser.s's header]. Nothing here depends on that.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                org     $2000

* ── the host handshake ───────────────────────────────────────────────────────────
PP_GO           equ     $0020           ; host writes 1 to start
PP_DONE         equ     $0021           ; probe writes 1 when finished
PP_NCASE        equ     $0022           ; 2 B: how many cases the host staged
PP_RUN          equ     $0024           ; 2 B: how many the probe completed

* ── staged by the host ───────────────────────────────────────────────────────────
PP_VOCAB        equ     $4000           ; WORDS.TOK, verbatim (<= 8,192 B measured)
PP_CASES        equ     $6000           ; case records, see below
PP_RESULTS      equ     $A000           ; one record per case, see below
PP_INBUF        equ     $3E00           ; the raw input for the case being run
PP_CLNBUF       equ     $3F00           ; par_clean's output

* case record:    u8 nwords, nwords x u16 LE operands, NUL-terminated input text
* result record:  u8 egon, egon x u16 LE word numbers, u8 match (0/1)

start:
                orcc    #$50                    ; ★ no interrupts: nothing here needs them and a
                                                ;   stray IRQ would run DECB's handler over us
                lds     #$3D00
                ldd     #PP_VOCAB
                std     par_vocab
                ldd     #PP_INBUF
                std     par_inbuf
                ldd     #PP_CLNBUF
                std     par_clnbuf
* ★★★★★ CLEAR PP_GO, NOT JUST PP_DONE. $0020 is in the direct page and DECB was running here a
* moment ago; whatever it left is not zero. The single-shot host set PC and GO in the SAME frame
* so the leftover never mattered -- the chunked host sets PC, then stages on the next frame, and
* in that gap the probe saw a non-zero GO and started on a garbage PP_NCASE.
* ★★★ The symptom was a hang with RUN=0 and the PC parked in par_is_inv, which reads as a parser
* defect. **It was a handshake that had never initialised its own start condition** and only
* worked because the caller happened to be fast enough.
                clr     PP_GO
                clr     PP_DONE
                ldd     #0
                std     PP_RUN
pp_wait:        lda     PP_GO
                beq     pp_wait

                ldx     #PP_CASES
                ldy     #PP_RESULTS
                ldd     #0
                std     pp_i
pp_loop:
                ldd     pp_i
                cmpd    PP_NCASE
                bhs     pp_fin
* ── X -> this case. Copy the operand block address, then the input text. ──
                stx     pp_ops                  ; X points at the u8 count
                lda     ,x                      ; nwords
                sta     pp_nw
                leax    1,x
                ldb     pp_nw
                lda     #0
                pshs    a
                puls    a
                lda     pp_nw
                tfr     a,b
                clra
                aslb
                rola                            ; D = nwords*2
                leax    d,x                     ; X -> the input text
* copy the input into PP_INBUF (NUL-terminated)
                ldu     #PP_INBUF
pp_cpy:         lda     ,x+
                sta     ,u+
                bne     pp_cpy
                stx     pp_next                 ; X -> the next case record
* ── run the parser ──
                jsr     par_parse
                ldx     pp_ops
                jsr     par_said
                bne     pp_nomatch
                lda     #1
                sta     pp_res
                bra     pp_store
pp_nomatch:     clr     pp_res
pp_store:
* ── write the result record ──
                lda     par_egon
                sta     ,y+
                ldb     par_egon
                beq     pp_res_done
                ldx     #par_ego
pp_res_lp:      lda     ,x+
                sta     ,y+
                lda     ,x+
                sta     ,y+
                decb
                bne     pp_res_lp
pp_res_done:
                lda     pp_res
                sta     ,y+
                ldd     pp_i
                addd    #1
                std     pp_i
                std     PP_RUN
                ldx     pp_next
                bra     pp_loop
pp_fin:
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ RESTARTABLE, BECAUSE THE CASES AND THE RESULTS SHARE THE ADDRESS SPACE.
* The case block for one title is 32,273 bytes from $6000, which runs to $DE11 -- straight
* through PP_RESULTS at $A000. The probe read cases sequentially and wrote results from $A000
* upward, so at roughly case 993 **the read cursor reached bytes the write cursor had already
* overwritten and the probe began parsing its own output.**
* ★★★★ THE SYMPTOM WAS NOT A CRASH. It was a plausible wrong answer -- one word tokenising as
* unknown -- 993 cases into a run whose first 992 were correct, and the same case in isolation
* was right. **A defect that only appears after enough work is the shape a small test cannot
* reach**, which is why the gate runs the whole corpus and not a sample.
* ★★★ So the host feeds the probe in chunks that fit: it stages, sets GO, reads the results,
* clears GO and stages the next. No buffer grows without bound and the map stays honest.
                lda     #1
                sta     PP_DONE
pp_ack:         lda     PP_GO                   ; host clears GO to acknowledge
                bne     pp_ack
                clr     PP_DONE
                lbra    pp_wait                 ; ready for the next chunk

pp_i            fdb     0
pp_ops          fdb     0
pp_next         fdb     0
pp_nw           fcb     0
pp_res          fcb     0

                include "src/engine/parser.s"

                end     start
