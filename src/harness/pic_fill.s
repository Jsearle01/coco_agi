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

FC_VISUAL       equ     0               ; test visual == 15   (70.3% of calls)
FC_PRIORITY     equ     1               ; test priority == 4  (6.4%)
FC_NEVER        equ     2               ; always false        (the rest)

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
* ★★★ AC-2 ABLATION POINTS. -DFC_STOP0..3 returns early after each block, so the per-block cost
* is a DIFFERENCE between two timed runs of THIS routine rather than a copy of it or a sum of
* datasheet numbers. The measured code is fill_check itself, truncated -- no duplicate to drift.
* ★ FC_STOP0 measures the floor: jsr + rts + the bench loop, i.e. what any call costs before
* fill_check does anything at all.
* ★★★ P3.4 — THE CASE DECISION IS HOISTED OUT OF THE PER-PIXEL PATH.
* draw_FillCheck's three-way choice depends ONLY on scr_on / pri_on / scr_color / pri_color,
* never on the pixel under test. Those four are set by PICTURE opcodes and cannot change during
* a flood_fill, so the decision is made ONCE at flood_fill entry (ff_case) and fill_check
* branches on a single byte.
*
* ★★ AND THE THREE CASES COLLAPSE TO TWO TESTS. At the pin, case 1 is
*   `!priOn && scrOn && scrColor != 15  -> screenColor == 15`
* and the catch-all is
*   `scrOn && screenColor == 15 && scrColor != 15`
* -- the SAME test on the visual plane, reached by different routes. So:
*     FC_VISUAL   (scr_on && scr_color != 15)                  -> visual == 15
*     FC_PRIORITY (pri_on && !scr_on && pri_color != 4)         -> priority == 4
*     FC_NEVER    (anything else)                               -> always false
* ★★★ VERIFIED EXHAUSTIVELY, not argued: all 262,144 combinations of the four flags x both
* pixel values agree with the pin's function. Measured on the corpus, FC_VISUAL takes 70.3% of
* calls and FC_PRIORITY 6.4%.
*
* ★ THREE THINGS THIS BUYS, all of them "identical, only cheaper":
*   1. the flag dispatch (16 cyc) and the general case's re-checks (18 cyc) are gone;
*   2. the PRIORITY pointer is no longer formed on the visual path -- the pshs/puls pair and
*      `addd #PRI_BASE / tfr d,y` (24 cyc) existed only to carry a pointer 70% of calls never
*      read;
*   3. `lda fc_y` was issued TWICE -- A still holds fc_y after the bounds compare (5 cyc).
* ★ FC_NEVER returns without the bounds test, which is identical: an out-of-bounds pixel and a
* never-fillable state both yield false.
                ifdef   FC_STOP0
                rts
                endc
                lda     fc_case
                bne     fc_notvis

* ── FC_VISUAL: the 70.3% path ─────────────────────────────────────
                lda     fc_x
                cmpa    #PIC_W
                bhs     fc_no
                lda     fc_y
                cmpa    #PIC_H
                bhs     fc_no
                ifdef   FC_STOP1
                rts
                endc
                ldb     #PIC_W                  ; A still holds fc_y -- no reload
                mul
                addb    fc_x
                adca    #0
                ifdef   FC_STOP2
                rts
                endc
                addd    #FB_BASE
                tfr     d,x
                ifdef   FC_STOP3
                rts
                endc
                ifndef  PIC_NOCOUNT
                inc     PATH_V+1
                bne     fc_pv
                inc     PATH_V
fc_pv:          endc
                lda     ,x
                anda    #$0F                    ; either nibble; equal by construction
                cmpa    #15
                beq     fc_yes
                bra     fc_no

* ── FC_PRIORITY (6.4%) and FC_NEVER ──────────────────────────────
fc_notvis:      cmpa    #FC_PRIORITY
                bne     fc_no                   ; FC_NEVER -- always false
                lda     fc_x
                cmpa    #PIC_W
                bhs     fc_no
                lda     fc_y
                cmpa    #PIC_H
                bhs     fc_no
                ldb     #PIC_W
                mul
                addb    fc_x
                adca    #0
                addd    #PRI_BASE
                tfr     d,x
                ifndef  PIC_NOCOUNT
                inc     PATH_P+1
                bne     fc_pp
                inc     PATH_P
fc_pp:          endc
                lda     ,x
                cmpa    #4
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
* ★★★ DECIDE THE CASE ONCE PER FILL, not once per pixel. The four flags this reads cannot
* change between here and ff_done -- they are written only by PICTURE opcodes F0-F3, and a
* flood_fill runs to completion inside one F8 operand pair. ★ Exhaustively verified equivalent
* to the pin's draw_FillCheck over all 262,144 flag/pixel combinations.
                lda     scr_on
                beq     ffc_notvis
                lda     scr_color
                cmpa    #15
                beq     ffc_notvis
                lda     #FC_VISUAL
                bra     ffc_set
ffc_notvis:     lda     pri_on
                beq     ffc_never
                lda     scr_on
                bne     ffc_never               ; scr_on set but scr_color==15 -> never fills
                lda     pri_color
                cmpa    #4
                beq     ffc_never
                lda     #FC_PRIORITY
                bra     ffc_set
ffc_never:      lda     #FC_NEVER
ffc_set:        sta     fc_case

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
* ★★ P3.5 — BRANCH ON THE FLAG, THEN RESTORE, instead of carrying the flag over the restore.
* `pshs cc / inc fc_y / puls cc` cost 19 cycles and existed only so `inc` could not disturb Z.
* Branching first and restoring on BOTH paths costs 7, and it happens twice per pixel.
                jsr     fill_check
                bne     ff_up_reset
                inc     fc_y                    ; restore y (fillable path)
                lda     ff_up
                beq     ff_down_test
                lda     fc_x
                ldb     fc_y
                decb
                jsr     ff_push
                clr     ff_up
                bra     ff_down_test
ff_up_no:       bra     ff_down_test
ff_up_reset:    inc     fc_y                    ; restore y (not-fillable path)
                lda     #1
                sta     ff_up

* --- the row BELOW ----------------------------------------------
ff_down_test:
                lda     fc_y
                cmpa    #PIC_H-1
                bhs     ff_down_no
                inca
                sta     fc_y
                jsr     fill_check
                bne     ff_down_reset
                dec     fc_y                    ; restore y (fillable path)
                lda     ff_down
                beq     ff_advance
                lda     fc_x
                ldb     fc_y
                incb
                jsr     ff_push
                clr     ff_down
                bra     ff_advance
ff_down_no:     bra     ff_advance
ff_down_reset:  dec     fc_y                    ; restore y (not-fillable path)
                lda     #1
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
fc_case         fcb     FC_NEVER        ; set by flood_fill; see ff_go
fc_x            fcb     0
fc_y            fcb     0
ff_up           fcb     0
ff_down         fcb     0
