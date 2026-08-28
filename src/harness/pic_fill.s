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
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ P3.13 — THE ROW POINTER IS HOISTED OUT OF THE SPAN WALK. THE TEST COUNT IS UNCHANGED.
*
* ★★ THE DISPATCH'S PREMISE NEEDED CORRECTING FIRST. T-P0-021 §2 describes our fill as
* "seed-based: pop a seed, test the pixel, write it, test its four neighbours, push the fillable
* ones", and proposes replacing it with a span-based scanline fill. WE ARE ALREADY THAT: the
* header above says so and the code has always done it. So the 3.09 tests per pixel are NOT an
* artifact of a seed-based structure that a scanline structure would remove.
*
* ★★★ WHERE 3.09 ACTUALLY COMES FROM, and why it cannot go lower without changing the output:
*     1 test on the pixel itself (the span walk's terminator)
*     1 test on the row ABOVE   -- at EVERY pixel, because that is how a transition is detected
*     1 test on the row BELOW   -- likewise
*   plus the left scan and the per-seed pop test, which round it to 3.09.
* A scanline fill seeds only on transitions -- which we do -- but it must still LOOK at every
* pixel of the adjacent rows to find those transitions. ★ The tests are the algorithm. Removing
* one changes which spans get seeded and therefore which pixels get filled.
*
* ★★★ SO THE WIN IS THE COST PER TEST, NOT THE COUNT -- and §2's second half names it exactly:
* along a span walk the ROW IS INVARIANT. fill_check was recomputing, per test:
*     bounds 28 | row address (mul) 20 | plane test 14 | call/return 13 | dispatch 11  = 86
* Of that, the bounds and the row address are loop-invariant along a span, and the call is
* avoidable by inlining. What remains is the plane read itself.
*
* ★★ T-P0-014 tried hoisting the row address and found it "roughly a wash, because the span loop
* touches three rows per pixel". ★★★ THAT MEASUREMENT WAS RIGHT AND ITS CONCLUSION WAS TOO
* NARROW: three rows means THREE invariant pointers, not zero. Carrying all three -- X for the
* current row, U for the row above, Y for the row below -- makes every one of them invariant,
* and they advance together with three LEAs.
*
* ★★★ IDENTICAL BY CONSTRUCTION, which is what AC-2 and AC-5 rest on:
*   * the same tests happen in the same order on the same pixels -- CNT_CHK must not move;
*   * the bounds checks are not skipped, they are HOISTED: x is bounded by the span loop's own
*     `cmpa #PIC_W`, and y by up_ok / dn_ok computed once per span;
*   * the plane read, mask and compare are byte-for-byte what fill_check does;
*   * the pixel write is put_pixel's body with the bounds test removed for the same reason.
* ═══════════════════════════════════════════════════════════════════════════════════════════

FC_VISUAL       equ     0               ; test visual == 15   (70.3% of calls)
FC_PRIORITY     equ     1               ; test priority == 4  (6.4%)
FC_NEVER        equ     2               ; always false        (the rest)

* ★ Offset from a VISUAL-plane pointer to the same pixel's PRIORITY byte. Constant, so the
* secondary write needs no address arithmetic beyond one LEA.
PRI_DELTA       equ     PRI_BASE-FB_BASE

* ── fc_count — the counted build's instrumentation, factored out ───
* ★★ The inline tests must keep counting or AC-5's comparison against T-P0-014 breaks. Putting
* the counters in a subroutine costs a call in the COUNTED build only; timings come from
* -DPIC_NOCOUNT, where this vanishes entirely (§ the separate-builds rule below).
                ifndef  PIC_NOCOUNT
fc_count:
                pshs    d
                ldd     CNT_CHK+2
                addd    #1
                std     CNT_CHK+2
                ldd     CNT_CHK
                adcb    #0                      ; carry out of the low word
                adca    #0
                std     CNT_CHK
                lda     fc_case
                bne     fcc_pri
                inc     PATH_V+1
                bne     fcc_out
                inc     PATH_V
                bra     fcc_out
fcc_pri:        inc     PATH_P+1
                bne     fcc_out
                inc     PATH_P
fcc_out:        puls    d
                rts
                endc

* ── fill_check ────────────────────────────────────────────────────
* in:  fc_x, fc_y.   out: Z set (eq) = "this pixel may be filled"
* ★ STILL USED, for the per-SEED test at ff_pop_lp, where no row pointer exists yet. That is
* ~1.5% of all tests; the other 98.5% are inline.
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

* ★★★ P3.13 — THE PER-FILL CONSTANTS, decided here for the same reason fc_case is: none of
* them can change before ff_done, and every one of them was being recomputed per test or per
* pixel. Deriving them once is what makes the inline test three instructions.
*   fc_pbase : base of the plane the TEST reads        (FB_BASE or PRI_BASE)
*   fc_mask  : $0F for the visual plane (nibbles equal by construction), $FF for priority
*   fc_match : the value that means "fillable"          (15 or 4)
*   ff_wval  : the byte the PRIMARY write stores
*   ff_sec   : 1 when a SECOND plane must also be written
* ★★ Note FC_PRIORITY implies !scr_on, so its primary write IS the priority plane and there is
* no second write. FC_VISUAL implies scr_on, so its primary write is the visual plane and the
* second write happens only when pri_on. That is put_pixel's behaviour, restated without the
* per-pixel branch on two flags.
                lda     fc_case
                cmpa    #FC_PRIORITY
                beq     ffs_pri
                ldd     #FB_BASE
                std     fc_pbase
                lda     #$0F
                sta     fc_mask
                lda     #15
                sta     fc_match
                lda     scr_dbl                 ; constant during a fill (P3.5)
                sta     ff_wval
                lda     pri_on
                sta     ff_sec
                bra     ffs_done
ffs_pri:        ldd     #PRI_BASE
                std     fc_pbase
                lda     #$FF
                sta     fc_mask
                lda     #4
                sta     fc_match
                lda     pri_color
                sta     ff_wval
                clr     ff_sec
ffs_done:

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

* ★★★ THE ROW POINTER, FORMED ONCE PER SPAN. This is the MUL that fill_check was doing on every
* one of the ~3 tests per pixel; here it happens once for the whole span, and the pointers then
* walk. ★ Also decides once whether the rows above and below exist, which is the y half of the
* bounds test fill_check was repeating per call.
                lda     fc_y
                ldb     #PIC_W
                mul                             ; D = y * 160
                addd    fc_pbase
                std     ff_row                  ; row base in the TEST plane
                lda     fc_y
                beq     ffr_noup
                lda     #1
                bra     ffr_setup
ffr_noup:       clra
ffr_setup:      sta     ff_upok
                lda     fc_y
                cmpa    #PIC_H-1
                blo     ffr_dnok
                clra
                bra     ffr_setdn
ffr_dnok:       lda     #1
ffr_setdn:      sta     ff_dnok

* --- scan LEFT to the border ------------------------------------
* ★ The row is invariant here too, so the left walk is a pointer decrement rather than a MUL
* per step. The pixel at fc_x is already known fillable (the pop test passed).
                ldx     ff_row
                ldb     fc_x
                abx                             ; X = &row[fc_x]
ff_left:        lda     fc_x
                beq     ff_span                 ; x == 0, cannot go further
                leax    -1,x
                dec     fc_x
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,x
                anda    fc_mask
                cmpa    fc_match
                beq     ff_left
                inc     fc_x                    ; overshot by one
                leax    1,x

ff_span:
                lda     #1
                sta     ff_up
                sta     ff_down
* ★ the run's origin, for the deferred flush
                stx     ff_runp
                lda     fc_x
                sta     ff_runx
* ★★★ THE THREE INVARIANT POINTERS. X = current row, U = row above, Y = row below. They advance
* together with three LEAs per pixel, replacing three MULs and three bounds tests.
* ★ U and Y are formed even when their row does not exist; ff_upok / ff_dnok gate every
* dereference, so an out-of-range pointer is never read. Forming it costs 5 cycles once per
* span and removes a branch from the per-pixel path.
                leau    -PIC_W,x
                tfr     x,d
                addd    #PIC_W
                tfr     d,y

ff_right:
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,x
                anda    fc_mask
                cmpa    fc_match
                lbne    ff_flush                ; span finished -> flush, then next seed

* ★★★ P3.14 — THE WRITE IS DEFERRED TO THE END OF THE SPAN. Nothing is written here.
*
* ★★ WHY THAT IS SAFE, AND IT IS THE WHOLE JUSTIFICATION: within one span, NO TEST READS A
* PIXEL THAT SPAN WRITES. The current-row test reads AHEAD of the write position; the up and
* down tests read OTHER ROWS. So the writes have no reader until the span ends, and moving them
* changes nothing any test can observe.
* ★ That is what makes this a single-pass change. A two-pass version -- find the extent, blast,
* then re-walk for transitions -- would have cost an extra pointer walk per pixel and given most
* of the saving back.
*
* ★★★ AND IT REMOVES MORE THAN THE STORE. The per-pixel path was
*     lda ff_wval (5) / sta ,x (4) / lda fc_case (5) / bne (3) / lda ff_sec (5) / beq (3) = 25
* -- of which 16 cycles were re-deciding, per pixel, two facts that are fixed for the whole
* fill. The deferred flush decides them ONCE PER SPAN.

* --- the row ABOVE: seed only on a transition into a fillable span ---
                lda     ff_upok
                beq     ff_down_test
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,u
                anda    fc_mask
                cmpa    fc_match
                bne     ff_up_reset
                lda     ff_up
                beq     ff_down_test
                lda     fc_x
                ldb     fc_y
                decb
                pshs    x,u,y                   ; ★ ff_push clobbers X and D
                jsr     ff_push
                puls    x,u,y
                clr     ff_up
                bra     ff_down_test
ff_up_reset:    lda     #1
                sta     ff_up

* --- the row BELOW ----------------------------------------------
ff_down_test:
                lda     ff_dnok
                beq     ff_advance
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,y
                anda    fc_mask
                cmpa    fc_match
                bne     ff_down_reset
                lda     ff_down
                beq     ff_advance
                lda     fc_x
                ldb     fc_y
                incb
                pshs    x,u,y
                jsr     ff_push
                puls    x,u,y
                clr     ff_down
                bra     ff_advance
ff_down_reset:  lda     #1
                sta     ff_down

ff_advance:
                leax    1,x
                leau    1,u
                leay    1,y
                inc     fc_x
                lda     fc_x
                cmpa    #PIC_W
                lblo    ff_right
                lbra    ff_flush

* ── ff_flush — write the span's run, now that it is complete ──────
* ★ run length = fc_x - ff_runx. Correct at BOTH exits: the test-failed exit leaves fc_x on the
* first non-fillable pixel, and the right-edge exit leaves it at PIC_W. ★★ Both are UNSIGNED
* comparisons of unsigned coordinates -- fc_x >= ff_runx always, so no `bmi` is involved [L-40].
ff_flush:
                lda     fc_x
                suba    ff_runx
                lbeq    ff_pop_lp               ; empty run (the seed itself was not fillable)
                sta     ff_runn

* ★ CNT_PIX counts VISUAL writes only, exactly as put_pixel did: FC_PRIORITY's primary write is
* the priority plane and never counted. Adding the run length once is identical to incrementing
* per pixel, which is why AC-3's 1,188,430 must not move.
                ifndef  PIC_NOCOUNT
                lda     fc_case
                bne     ffl_nocnt
                clra
                ldb     ff_runn
                addd    CNT_PIX
                std     CNT_PIX
ffl_nocnt:
                endc

                ldx     ff_runp
                lda     ff_wval
                ldb     ff_runn
                bsr     ff_store                ; primary plane
                lda     ff_sec
                beq     ff_flush_done
                ldx     ff_runp
                leax    PRI_DELTA,x
                lda     pri_color
                ldb     ff_runn
                bsr     ff_store                ; the second plane, same run
ff_flush_done:  lbra    ff_pop_lp

* ── ff_store — B bytes of A, starting at X ────────────────────────
* ★ 11 cycles per byte: sta ,x+ (6) / decb (2) / bne (3).
ff_store:
ffs_lp:         sta     ,x+
                decb
                bne     ffs_lp
                rts
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE STACK BLAST WAS BUILT, GATED AND MEASURED, AND IT IS NOT WORTH IT. AD-45 IS CLOSED.
*
*     P3.13  per-pixel write        2.973 s median
*     P3.14  deferred, sta ,x+      2.746 s      7.6% faster
*     P3.14  deferred + pshs blast  2.749 s      7.5% faster
*     ★★★ THE BLAST'S OWN CONTRIBUTION: -0.1%. It was 0.004 s SLOWER, not faster.
*
* ★★ THE ARITHMETIC PREDICTED ~4% AND THE MEASUREMENT SAID NOTHING, and the reason is the span
* distribution rather than the instruction timings. Per byte the blast really is cheaper --
* 2.9 cycles against 11 -- but it is paid for PER SPAN: mask, save S, compute the end pointer,
* load five registers, restore S, then a tail loop for run mod 8. With a MEDIAN SPAN OF 9 BYTES
* [T-P0-014] that setup is amortised over about one 8-byte group, and it cancels the gain.
* ★ The blast wins on long runs and our runs are short. That is L-52 again: a technique is a
* solution to a problem SHAPE, and ours is not that shape.
*
* ★★ THE 7.6% CAME FROM DEFERRING THE WRITE, NOT FROM pshs -- and deferring removed 16 of the
* 25 per-pixel cycles by deciding `fc_case` and `ff_sec` ONCE PER SPAN instead of once per
* pixel. The store itself was never the expensive part.
*
* ★ The blast code is REMOVED rather than left behind a define: it borrowed S, and dead code
* that borrows S is a liability for the next person who adds a `bsr` near it (POP
* char_draw.s:512 -- three dispatches lost to exactly that).
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════════════

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
* ★ P3.13's per-fill and per-span invariants.
fc_pbase        fdb     0               ; base of the plane the TEST reads
fc_mask         fcb     0               ; $0F visual, $FF priority
fc_match        fcb     0               ; 15 visual, 4 priority
ff_wval         fcb     0               ; the byte the PRIMARY write stores
ff_sec          fcb     0               ; 1 = a second plane must also be written
ff_row          fdb     0               ; base of the current span's row, in the test plane
ff_upok         fcb     0               ; the row above exists
ff_dnok         fcb     0               ; the row below exists
* ★ P3.14's deferred-write state.
ff_runp         fdb     0               ; where the current run starts, in the test plane
ff_runx         fcb     0               ; the x it started at
ff_runn         fcb     0               ; its length in bytes
