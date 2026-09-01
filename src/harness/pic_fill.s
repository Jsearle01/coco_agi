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

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ -DPRI_PACKED IS NOT COMPLETE IN THIS FILE, AND THIS ERROR IS DELIBERATE (§9 trigger 1).
*
* T-P0-033 packed the priority plane and it DOES make the draw phase fit -- 58,842 against
* 65,280, 6,438 spare, proven by p3b_probe.s's own assertion. The compositor packs cleanly and
* its gate passes 20/20 with the injected fault still detected 20/20. **The renderer does not**,
* and the reason is structural rather than a missing case:
*
* ★★★ 1. `PRI_DELTA equ PRI_BASE-FB_BASE` is a CONSTANT offset from a visual pointer to the
*    same pixel's priority byte, and it exists ONLY because both planes share geometry. At 80
*    bytes per row against 160 there is no such constant. **Fixed** -- ff_store_pri recomputes
*    from (x, y) -- and the fix costs the second write a multiply it did not previously do.
*
* ★★★★ 2. THE SPAN WALK IS A BYTE-POINTER WALK AND THIS IS THE BLOCKER. `abx` forms
*    `X = &row[fc_x]`, then the left and right scans step `leax -1,x` / `leax 1,x` once per
*    PIXEL and read `lda ,x`. Packed, the pointer advances every OTHER pixel and the nibble
*    alternates, so the step becomes conditional and the read gains a shift. **That restructures
*    the inner loop P3.3 took from 11.1 s to 2.7 s across three decompositions**, whose
*    per-pixel cost is documented here down to the cycle.
*
* ★★ SO THE MAP'S FRAMING WAS WRONG A SECOND TIME, ONE LEVEL DEEPER. P6.1 said the cost of
* packing was "a nibble extract on the priority read". The read is the cheap part; the plane's
* GEOMETRY is load-bearing for the fill's two central optimisations, and neither survives.
* ★ [L-64 again: a divergence described by its cost concealed what it actually required.]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ T-P0-034 RESOLVES BOTH, AND THE OPTION IS (b): PRIORITY PACKED, VISUAL LEFT ALONE.
*
* ★★★ THE VISUAL PLANE IS NOT "UNPACKED" -- IT IS THE FRAMEBUFFER. Mode 2 is 4 bpp and AGI is
* 160 wide against the CoCo3's 320, so one AGI pixel is exactly one byte with the colour in
* both nibbles, and 160 B/row IS mode 2's stride [pic_probe.s]. **Packing it would mean 80
* B/row = 160 CoCo3 pixels: a horizontal RESOLUTION HALVING, not a packing.** So §4's option
* (a) does not exist at this resolution, and (b) is not a preference -- it is the only option.
* ★ Arithmetic: flat/flat 72,826 OVER by 7,546; (b) 59,386 FITS with 5,894 spare.
*
* ★★★★ AND (b) PRESERVES THE INNER LOOP FOR 70.3% OF CALLS, WHICH IS THE WHOLE POINT.
* fc_pbase selects the TEST plane ONCE PER SPAN: FB_BASE for FC_VISUAL (70.3%), PRI_BASE for
* FC_PRIORITY (6.4%), and FC_NEVER (the rest) reads no plane at all. **Under (b) the visual
* plane is still flat, so the FC_VISUAL byte-pointer walk is untouched byte for byte.** Only
* the 6.4% priority walk becomes a nibble walk, and it gets its own loop below.
*
* ★★★ WHY A SEPARATE LOOP AND NOT A BRANCH IN THE SHARED ONE. A per-pixel `lda fc_case / cmpa
* / bne` on the shared path is ~10 cycles x 1,188,430 written pixels = 11.9M cycles = **6.6 s**,
* which is worse than the entire pre-P3.3 render. The branch is taken ONCE PER SPAN instead.
* ★★ The duplicated loop costs ~250 bytes of code and, at 6.4% of 3,666,862 tests ACROSS ALL 45
* PICTURES, about 0.5% of render time. **Per-picture and total are different units and mixing
* them is how this nearly became a redesign** -- 235k extra tests is 0.66 s across the whole
* corpus, not per room.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════════════

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
* ★★★★ THE EIGHTH SITE, AND IT IS THE SEED TEST -- REACHED BEFORE ANY SPAN WALK.
* fill_check is called once per popped seed, from ff_pop_lp, BEFORE the row base is formed and
* before ffp_entry sets the nibble selectors. So it cannot use fc_mask/fc_match: it computes
* its own address and must select its own nibble.
* ★★★ T-P0-033 enumerated six sites, then found a seventh (pri_clear) by the shape of its
* failure. **This is the eighth**, and it is the one a span-walk-focused reading misses because
* it is not in the walk at all -- it is the gate that decides whether a walk happens.
                ifdef   PRI_PACKED
* ★★ THE FULL 16 BITS OF THE MUL ARE NEEDED: y*80 reaches 13,360 at y=167, so saving only B
* loses the high byte. `pshs d` / `addd ,s++`, not `pshs b` / `addb ,s+`.
                ldb     #PIC_W/2
                mul                             ; D = y * 80
                pshs    d
                lda     fc_x
                lsra
                tfr     a,b
                clra                            ; D = x >> 1  (UNSIGNED, L-40)
                addd    ,s++                    ; D = y*80 + (x>>1)
                addd    #PRI_BASE
                tfr     d,x
                ifndef  PIC_NOCOUNT
                inc     PATH_P+1
                bne     fc_pp
                inc     PATH_P
fc_pp:          endc
                lda     ,x
                ldb     fc_x
                bitb    #1
                bne     fc_pk_lo
                lsra
                lsra
                lsra
                lsra                            ; even x -> high nibble
                bra     fc_pk_got
fc_pk_lo:       anda    #$0F
fc_pk_got:
                cmpa    #4
                beq     fc_yes
                else
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
                endc
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
                ifdef   PRI_PACKED
* ★★ The TEST plane is priority only in the FC_PRIORITY case (6.4% of calls, P3.3), and only
* then is the row 80 bytes wide. Branching once per SPAN rather than per pixel keeps this off
* the inner loop -- the same reasoning that put fc_case on the span in the first place.
                ldb     fc_case
                cmpb    #FC_PRIORITY
                bne     ffr_vis160
                ldb     #PIC_W/2
                mul                             ; D = y * 80
                bra     ffr_rowbase
ffr_vis160:
                endc
                ldb     #PIC_W
                mul                             ; D = y * 160
ffr_rowbase:
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
* ★★★★ THE ONLY COST THE VISUAL PATH PAYS FOR PACKING: three instructions, ONCE PER SPAN.
* Everything below this branch is byte-identical to the unpacked build.
                ifdef   PRI_PACKED
                lda     fc_case
                cmpa    #FC_PRIORITY
                lbeq    ffp_entry
                endc
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

                ifdef   PRI_PACKED
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE PACKED-PRIORITY SPAN WALK -- FC_PRIORITY ONLY, 6.4% OF CALLS.
*
* ★★★ IT IS STILL A BYTE-POINTER WALK. The three pointers stay, the three LEAs stay, and the
* three-instruction test `lda ,x / anda fc_mask / cmpa fc_match` is UNCHANGED. Two things
* differ, and only two:
*   1. the pointers advance every OTHER pixel  -- conditional on the parity of fc_x
*   2. fc_mask / fc_match select the NIBBLE    -- toggled on each advance
*
* ★★★★ THE MASK/MATCH MECHANISM IS WHY THIS IS CHEAP AND IT WAS ALREADY IN THE TREE. fc_mask
* exists because the VISUAL plane's nibbles are equal by construction ($0F) while priority was
* $FF. Packing just makes the pair parity-dependent:
*       EVEN x -> HIGH nibble -> mask $F0, match (v<<4)
*       ODD  x -> LOW  nibble -> mask $0F, match v
* ★★ Both toggle by XOR: mask ^ $FF, match ^ (v*17). `fc_mtog` holds v*17, computed once per
* fill. **So the per-pixel test costs exactly what it always did.**
*
* ★★★ THE PARITY RULES, DERIVED ONCE (this is where an off-by-one meets a `bmi` -- L-40, and
* every quantity here is UNSIGNED):
*   going LEFT  x -> x-1 : byte DECREMENTS iff the OLD x was EVEN
*   going RIGHT x -> x+1 : byte INCREMENTS iff the OLD x was ODD
* ★ Both follow from byte = x>>1, and they are NOT symmetric -- reading one off the other is
* the mistake this comment exists to prevent.
*
* ★★ ff_runp is NOT maintained here. The unpacked flush writes through it; the packed flush
* calls ff_store_pri, which recomputes from (ff_runx, fc_y, ff_runn) because PRI_DELTA cannot
* exist between planes of different geometry. ff_runx is still the span's starting x.
* ═══════════════════════════════════════════════════════════════════════════════════════════
ffp_entry:
* ── set the nibble selectors for the CURRENT parity, and the toggle constant ──
                lda     #4                      ; FC_PRIORITY's match value: priority == 4
                sta     fc_mtog
                asla
                asla
                asla
                asla
                ora     fc_mtog
                sta     fc_mtog                 ; v*17 = $44
                jsr     ffp_setsel
* ── X = &row[fc_x >> 1], byte pointer ──
                lda     fc_x
                lsra
                tfr     a,b
                clra
                addd    ff_row
                tfr     d,x

ffp_left:       lda     fc_x
                beq     ffp_span                ; x == 0, cannot go further
* ★ decrement the byte pointer BEFORE the parity flips, using the OLD x's parity
                bita    #1
                bne     ffp_l_same              ; old x odd -> x-1 is even, SAME byte
                leax    -1,x
ffp_l_same:     dec     fc_x
                jsr     ffp_toggle
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,x
                anda    fc_mask
                cmpa    fc_match
                beq     ffp_left
* ── overshot by one: step back right, mirroring the rule above ──
                lda     fc_x
                bita    #1
                beq     ffp_l_back              ; old x even -> x+1 is odd, SAME byte
                leax    1,x
ffp_l_back:     inc     fc_x
                jsr     ffp_toggle

ffp_span:
                lda     #1
                sta     ff_up
                sta     ff_down
                stx     ff_runp                 ; ★ unused by the packed flush; kept for parity
                lda     fc_x
                sta     ff_runx
* ★ the row above and below, in PACKED stride
                leau    -PIC_W/2,x
                tfr     x,d
                addd    #PIC_W/2
                tfr     d,y

ffp_right:
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,x
                anda    fc_mask
                cmpa    fc_match
                lbne    ff_flush                ; span finished -- the SHARED flush

* --- the row ABOVE ---
                lda     ff_upok
                beq     ffp_down_test
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,u
                anda    fc_mask
                cmpa    fc_match
                bne     ffp_up_reset
                lda     ff_up
                beq     ffp_down_test
                lda     fc_x
                ldb     fc_y
                decb
                pshs    x,u,y
                jsr     ff_push
                puls    x,u,y
                clr     ff_up
                bra     ffp_down_test
ffp_up_reset:   lda     #1
                sta     ff_up

* --- the row BELOW ---
ffp_down_test:
                lda     ff_dnok
                beq     ffp_advance
                ifndef  PIC_NOCOUNT
                jsr     fc_count
                endc
                lda     ,y
                anda    fc_mask
                cmpa    fc_match
                bne     ffp_down_reset
                lda     ff_down
                beq     ffp_advance
                lda     fc_x
                ldb     fc_y
                incb
                pshs    x,u,y
                jsr     ff_push
                puls    x,u,y
                clr     ff_down
                bra     ffp_advance
ffp_down_reset: lda     #1
                sta     ff_down

ffp_advance:
* ★ advance the byte pointers only when leaving an ODD pixel
                lda     fc_x
                bita    #1
                beq     ffp_a_same
                leax    1,x
                leau    1,u
                leay    1,y
ffp_a_same:     inc     fc_x
                jsr     ffp_toggle
                lda     fc_x
                cmpa    #PIC_W
                lblo    ffp_right
                lbra    ff_flush

* ── ffp_setsel — set fc_mask / fc_match from fc_x's parity, absolutely ──────────
* ★ Used at span entry. The steady state uses ffp_toggle, which is cheaper; this exists so the
* entry does not have to know which state it is toggling FROM.
ffp_setsel:
                lda     fc_x
                bita    #1
                bne     ffp_ss_lo
                lda     #$F0
                sta     fc_mask
                lda     #4*16
                sta     fc_match
                rts
ffp_ss_lo:      lda     #$0F
                sta     fc_mask
                lda     #4
                sta     fc_match
                rts

* ── ffp_toggle — flip both selectors to the other nibble ────────────────────────
ffp_toggle:
                lda     fc_mask
                eora    #$FF
                sta     fc_mask
                lda     fc_match
                eora    fc_mtog
                sta     fc_match
                rts

fc_mtog         fcb     0               ; match toggle = matchvalue * 17
                endc

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

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DPIC_STRADDLE — THE CENSUS THAT PRICES BOTH WINDOWING DESIGNS.
*
* Windowing the fill has two candidate shapes and the choice between them is an arithmetic
* question, not a preference:
*
*   A  single-slice + fallback   map the slice holding this row's 3-row neighbourhood and run
*                                P3.3's walk unchanged; for rows where the neighbourhood crosses
*                                a boundary, a slower per-access path.
*   B  dual-slot 16 KB window    map fb slices n and n+1 into slots 5 and 6 so $A000-$DFFF is
*                                contiguous and NO neighbourhood can straddle -- but slot 5 is
*                                the priority plane, so every span flush that writes the second
*                                plane must remap it and put it back.
*
* ★★★★ A's cost is (straddling spans x fallback penalty). B's is (flushes with a secondary write
* x 2 remaps). **Both multipliers are content properties -- which rows the fills actually touch
* and how often a span writes two planes -- so they are MEASURABLE, and measuring them is
* cheaper and safer than building both.** The per-occurrence costs come from the ISA.
*
* ★★★ The straddle set is a property of the GEOMETRY, not of this probe's map: rows whose
* [(y-1)*160, (y+1)*160+159] span crosses a multiple of 8,192. That is {50,51,52, 101,102,103,
* 152,153,154} for the visual plane -- 9 of 168 -- and it is the same set whatever base address
* the plane sits at, which is why this counts correctly in pic_probe's FLAT map [L-73: name what
* the toggle moves -- this one moves nothing but a counter].
*
* ★★ Guarded, and OFF in every timing build, per the separate-builds rule that P3.3 established
* and P3b.3's 2.832 s depends on.
                ifdef   PIC_STRADDLE
                pshs    a,b
                ldd     CNT_FLUSH               ; ★ the denominator: runs flushed, not seeds
                addd    #1
                std     CNT_FLUSH
                lda     fc_y
                beq     fst_lo                  ; row 0: the neighbourhood starts at row 0
                deca
fst_lo:         ldb     #PIC_W
                mul                             ; D = lo row * 160
                lsra
                lsra
                lsra
                lsra
                lsra                            ; A = lo slice (offset >> 13)
                pshs    a
                lda     fc_y
                cmpa    #PIC_H-1
                beq     fst_hi                  ; last row: the neighbourhood ends at it
                inca
fst_hi:         ldb     #PIC_W
                mul
                addd    #PIC_W-1                ; D = hi row * 160 + 159, the last byte touched
                lsra
                lsra
                lsra
                lsra
                lsra                            ; A = hi slice
                cmpa    ,s+
                beq     fst_done                ; one slice: P3.3's walk runs untouched
                ldd     CNT_STRSPAN
                addd    #1
                std     CNT_STRSPAN
                clra
                ldb     ff_runn
                addd    CNT_STRPIX
                std     CNT_STRPIX
fst_done:       puls    a,b
* ★ B's multiplier: flushes that write a SECOND plane, each needing slot 5 away from priority
* and back. ff_sec is the flag the flush itself tests twenty lines below.
                lda     ff_sec
                beq     fst_nosec
                ldd     CNT_SECFLUSH
                addd    #1
                std     CNT_SECFLUSH
fst_nosec:
                endc

* ★★★ THE PRIMARY WRITE IS THE PRIORITY PLANE WHENEVER fc_case IS FC_PRIORITY, so packing has
* to be handled on BOTH write paths, not only the secondary one. Missing this leaves
* priority-only pictures (9 of the gated 45) writing byte-per-pixel into a packed plane.
                ifdef   PRI_PACKED
                lda     fc_case
                cmpa    #FC_PRIORITY
                bne     ffl_vis
                jsr     ff_store_pri            ; primary plane IS priority, packed
                bra     ff_flush_done
ffl_vis:
                endc
                ldx     ff_runp
                lda     ff_wval
                ldb     ff_runn
                bsr     ff_store                ; primary plane
                lda     ff_sec
                beq     ff_flush_done
                ifdef   PRI_PACKED
                jsr     ff_store_pri            ; ★ recomputed from (x, y): no PRI_DELTA
                else
                ldx     ff_runp
                leax    PRI_DELTA,x
                lda     pri_color
                ldb     ff_runn
                bsr     ff_store                ; the second plane, same run
                endc
ff_flush_done:  lbra    ff_pop_lp

* ── ff_store — B bytes of A, starting at X ────────────────────────
* ★ 11 cycles per byte: sta ,x+ (6) / decb (2) / bne (3).
ff_store:
ffs_lp:         sta     ,x+
                decb
                bne     ffs_lp
                rts

                ifdef   PRI_PACKED
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ ff_store_pri -- the packed run store, and the reason packing is not free HERE.
*
* The unpacked second write is `leax PRI_DELTA,x` plus ff_store: ONE lea and a byte run,
* because PRI_DELTA is a CONSTANT offset from a visual pointer to the same pixel's priority
* byte. **That constant exists only because both planes have identical geometry**, and packing
* destroys it -- 80 bytes per row against 160 is not a fixed displacement.
* ★★★ So the second write must recompute its address from (x, y) and handle three pieces: a
* possible odd leading pixel, a run of whole bytes, and a possible odd trailing pixel.
* ★★ THE RUN ITSELF GETS CHEAPER -- half as many stores -- and the ends get more expensive.
* Which wins depends on run length, and P3.3 measured the fill's median span at 9 bytes, so the
* ends are NOT amortised away. **AC-7 reports this rather than assuming it.**
* ★ in: ff_runx = start x, fc_y = row, ff_runn = pixel count, pri_color = value.
ff_store_pri:
                lda     ff_runn
                beq     ffsp_out
                sta     ff_pn
                lda     fc_y
                ldb     #PIC_W/2
                mul                             ; D = y * 80
                addd    #PRI_BASE
                std     ff_ptmp
                lda     ff_runx
                lsra
                tfr     a,b
                clra
                addd    ff_ptmp
                tfr     d,x                     ; X -> the run's first byte
* ★ the doubled nibble byte, formed once for the whole run
                lda     pri_color
                asla
                asla
                asla
                asla
                ora     pri_color
                sta     ff_pval
* ── odd leading pixel: patch the LOW nibble, keeping the EVEN pixel beside it ──
                lda     ff_runx
                bita    #1
                beq     ffsp_whole
                lda     ,x
                anda    #$F0
                ora     pri_color
                sta     ,x+
                dec     ff_pn
                beq     ffsp_out
ffsp_whole:
                lda     ff_pn
                lsra                            ; whole bytes = pixels / 2
                beq     ffsp_tail
                tfr     a,b
                lda     ff_pval
ffsp_lp:        sta     ,x+
                decb
                bne     ffsp_lp
ffsp_tail:
* ── odd trailing pixel: patch the HIGH nibble, keeping the ODD pixel beside it ──
                lda     ff_pn
                bita    #1
                beq     ffsp_out
                lda     ,x
                anda    #$0F
                ldb     pri_color
                aslb
                aslb
                aslb
                aslb
                pshs    b
                ora     ,s+
                sta     ,x
ffsp_out:       rts

ff_ptmp         fdb     0
ff_pn           fcb     0
ff_pval         fcb     0
* ═══════════════════════════════════════════════════════════════════════════════════════════
                endc
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
