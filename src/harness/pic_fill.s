* src/harness/pic_fill.s  — draw_Fill, transcribed for the 6809.
*
* ★★ SCANLINE FILL WITH A STACK OF SEED POINTS, not a per-pixel recursion. The oracle pushes
* POINTS, pops one, scans left to the border, then walks right writing pixels and seeding the
* rows above and below on span TRANSITIONS only (newspan_up / newspan_down). Replacing it with
* a simpler flood changes which pixels get seeded and therefore which get filled.
*
* ★★★ THE THREE CASES OF fill_check ARE THE WHOLE ALGORITHM, and the third is the one that is
* easy to get wrong (tools/picrender/fill.py has the same note):
*     visual-only  and scr_color != 15 : fill where the VISUAL is white(15)
*     priority-only and pri_color != 4 : fill where the PRIORITY is red(4)
*     otherwise                        : scr_on AND visual==15 AND scr_color!=15
*   ★ When BOTH planes are on, the bound is tested on the VISUAL screen ALONE. A fill that also
*   tested priority would stop at priority edges the oracle walks straight through.
*
* ★ STACK OVERFLOW HALTS. 448 entries against a measured peak of 102 is ample, but a wrap would
* corrupt code and produce a picture that is wrong for a reason no diff could name (L-23).

* ── fill_check ────────────────────────────────────────────────────
* in:  fc_x, fc_y.   out: Z set (eq) = "this pixel may be filled"
fill_check:
* ★★★ AC-7's DECIDING COUNTER, and it is 32-bit on purpose: 4 checks per pixel over a
* full-screen fill is ~107,000, which overflows 16 bits. ★★ Counting here costs ~30 cycles on
* the hottest path in the renderer, so the COUNTS and the TIMINGS are taken from SEPARATE
* BUILDS -- -DPIC_NOCOUNT for time, the counted build for structure. An instrument that changes
* what it measures by 15% cannot also be the thing reporting the measurement.
                ifndef  PIC_NOCOUNT
                pshs    d
                ldd     CNT_CHK+2
                addd    #1
                std     CNT_CHK+2
                bcc     fc_nocarry
                ldd     CNT_CHK
                addd    #1
                std     CNT_CHK
fc_nocarry:     puls    d
                endc
                lda     fc_x
                cmpa    #PIC_W
                bhs     fc_no
                lda     fc_y
                cmpa    #PIC_H
                bhs     fc_no

* address of (fc_x, fc_y) in both planes
                lda     fc_y
                ldb     #PIC_W
                mul
                addb    fc_x
                adca    #0
                pshs    d
                addd    #FB_BASE
                tfr     d,x                     ; X -> visual byte
                puls    d
                addd    #PRI_BASE
                tfr     d,y                     ; Y -> priority byte

                lda     pri_on
                bne     fc_pri_on
* --- !pri_on and scr_on and scr_color != 15 : visual must be white ---
                lda     scr_on
                beq     fc_no
                lda     scr_color
                cmpa    #15
                beq     fc_general
                lda     ,x
                anda    #$0F                    ; ★ either nibble; they are equal by construction
                cmpa    #15
                beq     fc_yes
                bra     fc_no
fc_pri_on:
                lda     scr_on
                bne     fc_general
* --- pri_on and !scr_on and pri_color != 4 : priority must be red(4) ---
                lda     pri_color
                cmpa    #4
                beq     fc_general
                lda     ,y
                cmpa    #4
                beq     fc_yes
                bra     fc_no
fc_general:
* --- scr_on AND visual == 15 AND scr_color != 15 ---
                lda     scr_on
                beq     fc_no
                lda     scr_color
                cmpa    #15
                beq     fc_no
                lda     ,x
                anda    #$0F
                cmpa    #15
                beq     fc_yes
fc_no:          andcc   #$FB                    ; Z clear = do not fill
                rts
fc_yes:         orcc    #$04                    ; Z set = fill
                rts

* ── flood_fill ────────────────────────────────────────────────────
* in: cur_x, cur_y = the seed.  Uses scr_on/pri_on/scr_color/pri_color.
flood_fill:
* picture.cpp: if (!_scrOn && !_priOn) return;
                lda     scr_on
                ora     pri_on
                bne     ff_go
                rts
ff_go:
                ldx     #STACK_BASE
                stx     ff_sp
                lda     cur_x
                ldb     cur_y
                jsr     ff_push

ff_pop_lp:
                ldx     ff_sp
                cmpx    #STACK_BASE
                lbls    ff_done                 ; stack empty
                leax    -2,x
                stx     ff_sp
                lda     ,x
                sta     fc_x
                lda     1,x
                sta     fc_y

                jsr     fill_check
                lbne    ff_pop_lp               ; seed no longer fillable

* --- scan LEFT to the border ------------------------------------
ff_left:        lda     fc_x
                beq     ff_left_done            ; x == 0, cannot go further
                deca
                sta     fc_x
                jsr     fill_check
                beq     ff_left
                inc     fc_x                    ; overshot by one
                bra     ff_span
ff_left_done:                                   ; at x==0 and still fillable
ff_span:
                lda     #1
                sta     ff_up
                sta     ff_down

ff_right:       jsr     fill_check
                lbne    ff_pop_lp               ; span finished -> next seed

* write this pixel into the enabled planes
                lda     fc_x
                sta     cur_x
                lda     fc_y
                sta     cur_y
                jsr     put_pixel

* --- the row ABOVE: seed only on a transition into a fillable span ---
                lda     fc_y
                beq     ff_up_no                ; y == 0, no row above
                deca
                sta     fc_y
                jsr     fill_check
                pshs    cc
                inc     fc_y                    ; restore y
                puls    cc
                bne     ff_up_reset
                lda     ff_up
                beq     ff_down_test
                lda     fc_x
                ldb     fc_y
                decb
                jsr     ff_push
                clr     ff_up
                bra     ff_down_test
ff_up_no:       bra     ff_down_test
ff_up_reset:    lda     #1
                sta     ff_up

* --- the row BELOW ----------------------------------------------
ff_down_test:
                lda     fc_y
                cmpa    #PIC_H-1
                bhs     ff_down_no
                inca
                sta     fc_y
                jsr     fill_check
                pshs    cc
                dec     fc_y
                puls    cc
                bne     ff_down_reset
                lda     ff_down
                beq     ff_advance
                lda     fc_x
                ldb     fc_y
                incb
                jsr     ff_push
                clr     ff_down
                bra     ff_advance
ff_down_no:     bra     ff_advance
ff_down_reset:  lda     #1
                sta     ff_down

ff_advance:
                inc     fc_x
                lda     fc_x
                cmpa    #PIC_W
                lblo    ff_right
                lbra    ff_pop_lp

ff_done:        rts

* ── ff_push — A = x, B = y ────────────────────────────────────────
* ★ Overflow HALTS. Wrapping the stack would overwrite code at $0800 and produce a wrong
* picture with no attributable cause.
ff_push:
                ldx     ff_sp
                cmpx    #STACK_TOP-2
                bhs     ff_overflow
                sta     ,x
                stb     1,x
                leax    2,x
                stx     ff_sp
* ★★ AC-6/AC-7 INSTRUMENTATION — measured at the ONLY push site, so no path can bypass it.
* CNT_SPAN counts seed points pushed; SP_PEAK is the high-water mark in BYTES, kept as a
* depth (X - STACK_BASE) rather than a raw pointer so it is comparable across runs and
* directly against the offline prediction of 204 bytes / 102 entries.
                ifndef  PIC_NOCOUNT
                pshs    a,b
                ldd     CNT_SPAN
                addd    #1
                std     CNT_SPAN
                tfr     x,d
                subd    #STACK_BASE             ; D = current depth in bytes
                cmpd    SP_PEAK
                bls     ff_push_done
                std     SP_PEAK
ff_push_done:   puls    a,b
                endc
                rts
ff_overflow:
                lda     #$EE
                sta     bad_op                  ; reported alongside an unimplemented opcode
ff_ovf_halt:    bra     ff_ovf_halt

ff_sp           fdb     0
fc_x            fcb     0
fc_y            fcb     0
ff_up           fcb     0
ff_down         fcb     0
