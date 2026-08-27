* src/harness/pic_probe.s
*
* T-P0-011 Part B — render ONE AGI PICTURE on a real CoCo3, in 320x200x16.
*
* ★★ THIS IS A HARNESS PROBE, NOT ENGINE CODE. It lives in src/harness/ so src/engine/** stays
* empty and reg_discipline.py stays at 0 (CLAUDE.md §2N). The real engine renderer is a later
* task; this exists to put the FIRST PIXELS on the machine and prove the pipeline end to end.
*
* ★★★ WHAT IS BEING TESTED. The framebuffer this writes is read back by MAME, unpacked, and
* diffed against the PINNED ORACLE's 160x168 visual buffer — never against tools/picrender/.
* Both are clients of the same reference; comparing them to each other would let both be wrong
* the same way and report green for ever [CLAUDE.md §2O.1, design §8.2].
*
* ═══════════════════════════════════════════════════════════════════
* MEMORY MAP — chosen so both planes and the code fit one 64 KB map
* ═══════════════════════════════════════════════════════════════════
*   $0100..$04FF  fill stack, 512 B = 256 entries of 2 B (x,y)
*                 ★ measured peak seed depth in the offline renderer was 102 (P2 fill study),
*                   so 256 is ~2.5x headroom. The probe HALTS on overflow rather than wrapping.
*   $0500..$07FF  the 6809 HARDWARE stack, S starts at $0800 and grows DOWN.
*                 ★★ THE CALLER MUST SET S AND THE HAL DOES NOT. hal.inc:357-362 states the
*                   requirement outright -- "THE STACK MUST NOT LIVE IN THE DRAW WINDOW ... put
*                   the stack BELOW $8000" -- and its suggested $7F00 is inside THIS probe's
*                   priority plane, so it cannot be taken literally here. Leaving S where DECB
*                   put it aimed the hardware stack straight into the fill stack: the first
*                   deep fill overwrote a return address and the CPU ran off into $0211.
*   $0800..$16FF  code (this file + the HAL modules it calls)
*   $1700..$7FFF  PRIORITY plane, 160 x 168 = 26,880 B = $6900. Ends at exactly $8000.
*   $8000..$FFFF  the GIME framebuffer window (GFX_DB_WINDOW, 4 blocks = 32 KB). The VISUAL
*                 plane is written straight into it.
*
* ★ VISUAL IS 1 BYTE PER AGI PIXEL AND THAT IS NOT A COINCIDENCE. Mode 2 is 4bpp, so a
* CoCo3 byte holds two adjacent screen pixels. AGI's picture is 160 wide against the CoCo3's
* 320, so ONE AGI pixel is TWO CoCo3 pixels — exactly one byte, with the colour in BOTH
* nibbles. 160 AGI px/row x 1 B = 160 B/row, which is mode 2's stride exactly.
* ★★ The nibble duplication IS the pixel doubling. Writing colour*17 ($0->$00, $F->$FF) is the
* whole transform, and the read-back side inverts it by checking the two nibbles agree.
*
* ★ PRIORITY IS NOT DOUBLED. Design §3.3 keeps the priority plane 160 wide with the lookup
* x>>1, so it is 160x168 one byte per pixel — the SAME shape as the oracle's. No transform, no
* place for a transform error to hide (AC-7).

                include "src/hal.inc"

PIC_W           equ     160
PIC_H           equ     168

STACK_BASE      equ     $0100           ; fill stack (seed points)
STACK_TOP       equ     $0500           ; one past the last usable fill entry
HW_STACK        equ     $0800           ; 6809 S, grows DOWN into $0500..$07FF
PRI_BASE        equ     $1700           ; 160*168 = $6900 -> ends at $8000
FB_BASE         equ     $8000           ; GFX_DB_WINDOW

* Where the driver leaves the picture resource, and where the probe reports.
*
* ★★ BOTH ADDRESSES MUST LIE BELOW $8000. The framebuffer window is $8000-$FFFF and
* HAL_gfx_set_mode CLEARS it, so anything staged up there is destroyed before the first opcode
* is read. The gap between the code (~$1125) and the priority plane ($1700) is the only space
* that is neither cleared nor overwritten, so both live there.
PIC_DATA        equ     $1200           ; picture resource, poked in by the MAME side.
                                        ;   $1200..$16EF = 1,264 B; picture 80 is 211 B.
* ★★ STATUS MOVED TO LOW RAM (T-P0-012). It was at $16F0, inside the PIC_DATA window, which
* capped a resource at 1,264 bytes; the gated set's largest is 1,254 and 31 of 45 exceed 1 KB.
* $0020-$00FF is free -- the HAL owns DP $00-$1F and the fill stack starts at $0100 -- so the
* block lives there and PIC_DATA gets the whole $1200..$16FF (1,280 B).
STATUS          equ     $0080           ; +0 done sentinel, +1 bad opcode / $EE stack overflow
CNT_VERT        equ     $0082           ; DIAGNOSTIC: draw_line vertical-branch entries
CNT_HORIZ       equ     $0084           ;             horizontal-branch entries
CNT_DIAG        equ     $0086           ;             diagonal-branch entries
CNT_PIX         equ     $0088           ;             put_pixel writes to the visual plane
CNT_FILL        equ     $008A           ; AC-7: flood_fill invocations
CNT_SPAN        equ     $008C           ; AC-7: seed points PUSHED onto the fill stack
SP_PEAK         equ     $008E           ; AC-6: fill-stack high-water mark, in BYTES
* ★★★ THE TIMING MARKER (AC-5). The probe stores a phase number here; the MAME side has a
* WRITE TAP on this address and records `manager.machine.time` at the instant of the store.
* Resolution is one instruction, and emulated time is exact and deterministic -- not a frame
* counter, which would be 16.7 ms granular and useless for decomposition.
PHASE           equ     $0090
CNT_CHK         equ     $0094           ; AC-7: fill_check calls, 32-bit (4/px overflows 16)
PATH_V          equ     $0098           ; AC-2: fill_check took the visual-only case
PATH_P          equ     $009A           ; AC-2: ... the priority-only case
PATH_G          equ     $009C           ; AC-2: ... the general (both planes on) case

                org     $0800
* ═══════════════════════════════════════════════════════════════════
probe_entry:
                orcc    #$50                    ; mask interrupts for the duration
                lds     #HW_STACK               ; ★ hal.inc:357 -- the CALLER owns S

                jsr     HAL_sys_init            ; bare-metal transition: $FF90 + MMU
                lda     #GFX_MODE_320x200x16    ; = 2, by contract name not literal
                jsr     HAL_gfx_set_mode        ; clears both buffers, loads mode 2's palette

                ldd     #0                      ; DIAGNOSTIC counters
                std     CNT_VERT
                std     CNT_HORIZ
                std     CNT_DIAG
                std     CNT_PIX
                std     CNT_FILL
                std     CNT_SPAN
                std     SP_PEAK
                std     CNT_CHK
                std     CNT_CHK+2
                std     PATH_V
                std     PATH_P
                std     PATH_G
* ★★★ PICTURE STATE RESET — EVERY RENDER, NOT JUST THE FIRST LOAD.
* [ref: picture.cpp:385-388 @ 9d9b9e9] drawPicture() opens with
*     _priOn = false;  _scrOn = false;  _scrColor = 15;  _priColor = 4;
* ★★ scr_color is 15, NOT 0. The probe had `scr_color fcb 0` -- harmless while the driver
* re-poked the whole binary before each picture, and a real defect the moment it stopped.
* ★★★ TWO DEFECTS, ONE CAUSE, AND THE SECOND WAS SELF-INFLICTED. The GO re-run gate fixed the
* counters by making the probe restart itself -- and in doing so removed the blob re-poke that
* had been silently re-initialising `fcb` data. probe_entry reset the COUNTERS explicitly but
* not the PEN, so picture N+1 inherited picture N's scr_on/pri_on/colours. It showed up in 11
* of 45 pictures, 9 of them priority-only, because most pictures issue set_visual/set_priority
* immediately and overwrite the inherited state before it can matter.
* ★ The lesson is the same one twice: RE-ENTRY MUST RE-ESTABLISH ALL STATE, NOT THE STATE YOU
* HAPPEN TO BE THINKING ABOUT. Initialised data is state.
                clr     scr_on
                clr     pri_on
                clr     xc_isx
                lda     #15
                sta     scr_color
                lda     #$FF                    ; 15 doubled -- keep scr_dbl in step (§3.4)
                sta     scr_dbl
                lda     #4
                sta     pri_color

                jsr     pal_load                ; ★ AGI's 16 EGA colours, from a TABLE
                jsr     vis_clear               ; visual plane = 15 (white)
                jsr     pri_clear               ; priority plane = 4 (red)

* ★★★ AC-5's MEASUREMENT BRACKET. The markers sit IMMEDIATELY either side of pic_render, so
* the interval excludes sys_init, set_mode and the two plane clears -- what is timed is the
* interpretation of the picture and nothing else. The MAME side write-taps PHASE and stamps
* `manager.machine.time` at the store, giving one-instruction resolution on exact emulated
* time. ★ Marker 1 is written LAST before the call and marker 2 FIRST after it.
* ★★ CLOCK CALIBRATION FIRST (phases 3→4), so cycle figures are MEASURED rather than assumed.
* Exactly 20,000 iterations of an 8-cycle body: `leax -1,x` is 5 (indexed, 5-bit offset) and
* `bne` is 3 = 160,000 cycles, plus ~9 for the setup and the final untaken branch. Dividing by
* the measured interval gives the effective CPU clock, which must come out at the CoCo3's fast
* rate (1.7898 MHz) because HAL_gfx_set_mode writes $FFD9. ★ If it lands near 0.8949 MHz the
* machine is in SLOW mode and every timing in this report would be off by 2x -- so this is a
* guard, not a decoration [L-24: name the variant].
                lda     #3
                sta     PHASE
                ldx     #20000
cal_lp:         leax    -1,x
                bne     cal_lp
                lda     #4
                sta     PHASE

* ★★★ -DFC_BENCH — AC-2's MEASUREMENT. Calls fill_check FC_ITERS times with fixed arguments,
* between the same phase markers the render uses, so the per-call cost falls out of the same
* write-tap mechanism at the same one-instruction resolution. Combined with -DFC_STOP0..3 the
* successive differences attribute the cost block by block, and the code being timed IS
* fill_check rather than a copy of it.
* ★ State is pinned to the case the corpus actually takes (measured by PATH_V/P/G, not assumed):
* both planes on, scr_color 7, and the visual plane left at 15 by vis_clear so the test yields
* a consistent verdict every iteration.
                ifdef   FC_BENCH
                lda     #1
                sta     scr_on
                sta     pri_on
                lda     #7
                sta     scr_color
                lda     #2
                sta     pri_color
                lda     #80
                sta     fc_x
                lda     #100
                sta     fc_y
* ★★ THE BENCH MUST SET fc_case, because flood_fill now owns it and the bench does not go
* through flood_fill. Without this the case byte kept its FC_NEVER initialiser and every
* iteration took the always-false path -- FC_STOP1/2/3 sit inside the FC_VISUAL branch, so all
* four ablations returned the IDENTICAL time and the decomposition silently measured nothing.
* ★ FC_VISUAL is the 70.3% path and the one the decomposition is about.
                lda     #FC_VISUAL
                sta     fc_case
* put_pixel reads cur_x/cur_y (not fc_x/fc_y) -- set both so any bench target is well-defined.
                lda     #80
                sta     cur_x
                lda     #100
                sta     cur_y
                lda     #1
                sta     PHASE
* ★★ THE COUNTER LIVES IN MEMORY, NOT IN X. fill_check does `tfr d,x` and `tfr d,y` while
* forming its plane pointers, so an X or Y loop counter is destroyed the moment the ablation
* reaches that block -- stop0/1/2 timed fine and stop3/full ran away, which is exactly the kind
* of result that looks like a measurement. U survives, but `leau` does not set Z, so a memory
* counter it is. ★ Its cost is IDENTICAL in every variant, so it cancels in the differences and
* only inflates the absolute floor, which is reported as such.
                ldd     #FC_ITERS
                std     fcb_n
* ★★★ WHICH ROUTINE THE BENCH CALLS IS SELECTED AT ASSEMBLE TIME (T-P0-014 Part B).
* The loop, the counter and the phase markers are IDENTICAL for every target, so the loop's own
* cost cancels when two targets are differenced and shows up only in the -DBENCH_NULL floor.
*   -DBENCH_FC -DFC_STOP0   fill_check truncated to `rts` -> jsr + rts + loop, THE FLOOR (32 cyc)
*   -DBENCH_FC              fill_check          -> the boundary test
* ★ Selection is EXPLICIT rather than "fill_check unless another is set": lwasm mis-pairs the
* `endc`s of three nested `ifndef`s, and a label defined inside a nested `ifdef` is reported as
* multiply-defined across its two passes. One `ifdef` per target, no nesting, no new labels --
* the floor comes from -DFC_STOP0, which already returns immediately and was measured at 32.
*   -DBENCH_PP     put_pixel           -> the plane write
*   -DBENCH_PUSH   ff_push             -> a seed-stack push
* ★★ ff_push MUTATES ff_sp, so the bench resets it every iteration -- 20,000 pushes would
* otherwise overflow a 512-entry stack and halt. The reset is inside the timed region and is
* subtracted as part of the NULL floor comparison; it is called out in the report rather than
* hidden, because it inflates the ff_push figure by the cost of one `ldx #`/`stx`.
fcb_lp:
                ifdef   BENCH_PP
                jsr     put_pixel
                endc
                ifdef   BENCH_PUSH
                ldx     #STACK_BASE
                stx     ff_sp
                lda     #80
                ldb     #100
                jsr     ff_push
                endc
                ifdef   BENCH_FC
                jsr     fill_check
                endc
                ldd     fcb_n
                subd    #1
                std     fcb_n
                bne     fcb_lp
                lda     #2
                sta     PHASE
                endc


                ifndef  FC_BENCH
                lda     #1
                sta     PHASE
                jsr     pic_render              ; interpret the picture
                lda     #2
                sta     PHASE
                endc

* ★★ AC-8 -- PROVE THE GATE CAN FAIL, ON THE REAL PIPELINE.
* A gate that has only ever reported PASS has not been shown to be a gate. -DPIC_FAULT flips
* both nibbles of ONE pixel, (37,42), AFTER a correct render; picdiff.py --expect-fail then
* requires that the diff CATCH it at exactly that offset. Assemble-time and off by default, so
* a gate run cannot accidentally carry it and so the check is REPRODUCIBLE rather than an
* ad-hoc edit -- an injection that lives only in someone's shell is not evidence.
* offset = 42*160 + 37 = 6757.
* ★★ ARMED PER PICTURE, NOT PER BUILD (T-P0-012). Injecting into all 45 would prove only that
* the gate can go red; arming ONE proves it LOCALISES -- that picture fails and the other 44
* still pass. A gate that fails everything is not distinguishable from a gate that is broken.
                ifdef   PIC_FAULT
                lda     FAULT_ARM
                beq     pf_skip
                lda     FB_BASE+6757
                eora    #$11                    ; both nibbles: still a legal doubled pixel
                sta     FB_BASE+6757
pf_skip:
                endc

                lda     #$A5                    ; sentinel LAST: a partial run is visible
                sta     done_flag
* ★ The rendered picture is in the BACK buffer; the display shows the front one. The flip is
* assemble-time optional and sits AFTER the sentinel, because the MAME side reads $8000 the
* moment the sentinel appears and the flip REMAPS that window -- a gate run must never race a
* remap. Screenshot build: -DPIC_PRESENT. Gate build: omit it.
*
* ★★★ HAL_gfx_swap, NOT HAL_gfx_present. THE HAL HAS TWO FLIPS AND THEY TARGET DIFFERENT RAM.
*   HAL_gfx_swap    reads HAL_gfx_cur_back, writes VOFFSET $4000/$5000 -> physical
*                   $20000/$28000. These are the MODE SERVICE's buffers, the ones
*                   HAL_gfx_set_mode allocates and maps to $8000. This is the right one.
*   HAL_gfx_present reads page_register at DP $50 and writes VOFFSET $F000/$F800 ->
*                   physical $78000/$7C000. That is the LEGACY 4-colour single-buffer
*                   scheme in the TOP 64 KB -- where this running program lives. hal.inc:158
*                   calls it "a stub" and its VOFFSET derivation still carries a [no-ref:]
*                   debt marker.
*
* ★★ Calling present pointed the GIME 352 KB away from the rendered pixels and displayed
* PROGRAM BYTES AS PIXELS. The gate did not and could not catch it: picdiff reads $8000
* through the CPU's MMU window, while the screen is fed from VOFFSET -- two independent
* address paths. The buffer was byte-identical to the oracle the whole time. Found by Jay
* looking at the screenshot [CLAUDE.md §2 tier 1; §2H check 1 -- the SECOND mechanism].
*
* ★ CC.I CAVEAT, stated rather than hidden: hal.inc's caller sequence for HAL_gfx_swap
* requires HAL_time_init + `andcc #$EF`, because HAL_time_vbl_wait does NOT wait while CC.I
* is set -- it synthesises a counter increment and returns. This probe masks interrupts at
* entry and installs no handler, so the flip is NOT VBL-synced and may tear on the flip
* frame. Acceptable here and ONLY here: the image is static and the snapshot is taken four
* frames later, so nothing torn survives to the capture. A moving picture must not copy this.
                ifdef   PIC_PRESENT
                jsr     HAL_gfx_swap
                endc

* ═══════════════════════════════════════════════════════════════════
* THE RE-RUN GATE — how the sweep renders 45 pictures in one MAME session
*
* ★★★ THE DRIVER MUST NOT SET PC TO RESTART THIS PROBE. It was a 2-byte self-branch
* (`probe_halt: bra probe_halt`), and writing PC from a frame notifier while the CPU is
* mid-instruction inside it does NOT reliably land on probe_entry. Measured: on picture 2 the
* counter-reset store at $0813 NEVER EXECUTED while pic_render did, so every counter
* ACCUMULATED across pictures -- Kingquest1-053 reported px 50756 = its own 25677 plus
* Kingquest1-080's 25079, fills 72 = 64 + 8, and a 42,241-byte "peak" on a 1,024-byte stack.
* MAME reported PC=$0839 at the moment of the write: inside the two bytes of the `bra`.
*
* ★★ THE FAILURE MODE IS THE POINT. It did not crash and it did not halt -- it produced
* PLAUSIBLE NUMBERS THAT WERE WRONG, and the only reason it was caught is that a 42 KB peak on
* a 1 KB stack is arithmetically impossible. A subtler skew would have gone into the report as
* a measurement [L-37: instrument something that can CONTRADICT you].
*
* ★ So the probe re-runs ITSELF. The driver writes GO and touches nothing else; every
* iteration re-executes the whole prologue -- stack, HAL_sys_init, set_mode, both plane clears
* and the counter resets -- so picture N+1 cannot inherit anything from picture N.
GO              equ     $0091           ; driver writes non-zero to request another render
FAULT_ARM       equ     $0092           ; AC-8: driver arms the injection for ONE picture
probe_halt:     clr     GO
ph_wait:        lda     GO
                beq     ph_wait
                jmp     probe_entry

* ═══════════════════════════════════════════════════════════════════
* pal_load — write the 16 AGI colours to $FFB0-$FFBF
*
* ★★ FROM A TABLE, NEVER INLINE (CLAUDE.md §2F.1: "never inline a palette constant at a write
* site"). That is what makes the composite palette a later data change rather than a rewrite.
* ★ These 16 values are a TRANSCRIPTION of AGI's EGA palette, not a choice. Entry 6 is brown
* $22 = (R2,G1,B0) — the ONLY non-uniform entry, and the one a "double the CGA bit" conversion
* silently turns into dark yellow.
* ═══════════════════════════════════════════════════════════════════
pal_load:
                ldx     #agi_pal16
                ldy     #$FFB0
pal_lp:         lda     ,x+
                sta     ,y+
                cmpx    #agi_pal16+16
                blo     pal_lp
                rts

agi_pal16:
                fcb     $00             ;  0 black
                fcb     $08             ;  1 blue
                fcb     $10             ;  2 green
                fcb     $18             ;  3 cyan
                fcb     $20             ;  4 red
                fcb     $28             ;  5 magenta
                fcb     $22             ;  6 brown      ★ (2,1,0), the odd one out
                fcb     $38             ;  7 light grey
                fcb     $07             ;  8 dark grey
                fcb     $0F             ;  9 light blue
                fcb     $17             ; 10 light green
                fcb     $1F             ; 11 light cyan
                fcb     $27             ; 12 light red
                fcb     $2F             ; 13 light magenta
                fcb     $37             ; 14 yellow
                fcb     $3F             ; 15 white

* ═══════════════════════════════════════════════════════════════════
* vis_clear / pri_clear — THE AGI CANVAS IS WHITE-ON-RED, NOT BLACK
*
* ★★★ HAL_gfx_set_mode clears the framebuffer to palette index 0, which is correct for the HAL
* and WRONG for an AGI picture. AGI draws onto visual=15 (white) and priority=4 (red)
* [tools/picrender/screens.py, "clear to 15/4"], and draw_FillCheck fills only where the
* VISUAL is 15. Leaving the HAL's black canvas meant no fill could EVER succeed: the first run
* rendered 705 line pixels and none of the 88% of the picture that is fill.
*
* ★ Note the first row agreed with the oracle anyway, because the oracle's row 0 is genuinely
* black there -- two buffers matching for different reasons. A gate that only checked row 0
* would have passed.
* ═══════════════════════════════════════════════════════════════════
vis_clear:
                ldx     #FB_BASE
                ldd     #$FFFF                  ; 15 in both nibbles = white, doubled
vc_lp:          std     ,x++
                cmpx    #FB_BASE+(PIC_W*PIC_H)
                blo     vc_lp
                rts

pri_clear:
                ldx     #PRI_BASE
                ldd     #$0404
pc_lp:          std     ,x++
                cmpx    #PRI_BASE+(PIC_W*PIC_H)
                blo     pc_lp
                rts

* ═══════════════════════════════════════════════════════════════════
* pix_addr — D = y*160 + x, X = FB_BASE+D (visual), Y = PRI_BASE+D (priority)
* in: cur_x (byte), cur_y (byte).  ★ 167*160 = 26,720, so MUL's 16-bit result is exact.
* ═══════════════════════════════════════════════════════════════════
pix_addr:
                lda     cur_y
                ldb     #PIC_W
                mul                             ; D = y*160
                addb    cur_x
                adca    #0                      ; D = y*160 + x
                std     pix_off
                addd    #FB_BASE
                tfr     d,x
                ldd     pix_off
                addd    #PRI_BASE
                tfr     d,y
                rts

* ═══════════════════════════════════════════════════════════════════
* in_bounds — Z set (eq) when cur_x/cur_y are on the picture
* ═══════════════════════════════════════════════════════════════════
in_bounds:
                lda     cur_x
                cmpa    #PIC_W
                bhs     ib_no
                lda     cur_y
                cmpa    #PIC_H
                bhs     ib_no
                andcc   #$FB                    ; clear Z ... then set it
                orcc    #$04
                rts
ib_no:          andcc   #$FB                    ; Z clear = out of bounds
                rts

* ═══════════════════════════════════════════════════════════════════
* put_pixel — write the ENABLED planes at cur_x/cur_y (putVirtPixel)
* ═══════════════════════════════════════════════════════════════════
put_pixel:
* ★★★ P3.5 — 186 -> ~118 cycles. Measured at 186 by direct benchmark (Part B), against a
* REGRESSION estimate of ~40 in T-P0-012. It was the second largest component of the whole
* render, 29.8%, and nobody had looked at it because the ratio said it was small.
*
* ★★ THREE THINGS IT WAS DOING, none of them necessary:
*   1. `jsr in_bounds` + `jsr pix_addr` -- two subroutine calls, ~26 cycles of jsr/rts alone,
*      for two compares and an address. Both are now inline.
*   2. `pix_addr` formed BOTH plane pointers every call. The priority pointer is formed only
*      when pri_on, and the visual pointer only when scr_on.
*   3. the nibble doubling was recomputed per pixel -- `anda`, a second load, four `lslb`, a
*      pshs/ora pair, ~30 cycles -- from scr_color, which CANNOT CHANGE during a fill. It is
*      now precomputed into scr_dbl by op_set_visual (and by the state reset).
* ★ scr_dbl is identically (scr_color & 15) * 17, which is exactly what the old sequence
* computed: low nibble, OR'd with the same nibble shifted up four.
                lda     cur_x
                cmpa    #PIC_W                  ; UNSIGNED (L-40)
                bhs     pp_out
                lda     cur_y
                cmpa    #PIC_H
                bhs     pp_out
                ldb     #PIC_W                  ; A still holds cur_y
                mul
                addb    cur_x
                adca    #0                      ; D = y*160 + x
                std     pix_off
                lda     scr_on
                beq     pp_pri
                ldd     pix_off
                addd    #FB_BASE
                tfr     d,x
                lda     scr_dbl                 ; the doubled byte, precomputed
                sta     ,x
                ifndef  PIC_NOCOUNT
                pshs    d
                ldd     CNT_PIX
                addd    #1
                std     CNT_PIX
                puls    d
                endc
pp_pri:         lda     pri_on
                beq     pp_out
                ldd     pix_off
                addd    #PRI_BASE
                tfr     d,x
                lda     pri_color
                sta     ,x
pp_out:         rts

                include "src/harness/pic_draw.s"
                include "src/harness/pic_fill.s"

* ═══════════════════════════════════════════════════════════════════
* pic_render — the opcode loop
*
* ★★ UNIMPLEMENTED OPCODES HALT LOUDLY (L-23). Picture 80 uses set_visual, set_priority,
* disable_priority, x_corner, rel_line, fill and end — measured from the resource bytes, not
* assumed. Anything else stores its opcode in bad_op and stops, so a silent mis-render is not
* on the table. KQ1's whole corpus uses NO pattern opcodes.
* ═══════════════════════════════════════════════════════════════════
pic_render:
                ldx     #PIC_DATA
                stx     pic_ptr
pr_next:        jsr     pic_get
                cmpa    #$FF
                beq     pr_done
                cmpa    #$F0
                blo     pr_bad                  ; a parameter where an opcode was expected
                suba    #$F0
                cmpa    #10
                bhi     pr_bad
                ldx     #pr_table
                lsla
                ldx     a,x
                cmpx    #0
                beq     pr_bad
                jsr     ,x
                bra     pr_next
pr_done:        clr     bad_op
                rts
pr_bad:         adda    #$F0
                sta     bad_op
                rts

pr_table:       fdb     op_set_visual           ; F0
                fdb     op_dis_visual           ; F1
                fdb     op_set_pri              ; F2
                fdb     op_dis_pri              ; F3
                fdb     op_y_corner             ; F4  [T-P0-012]
                fdb     op_x_corner             ; F5
                fdb     op_abs_line             ; F6  [T-P0-012]
                fdb     op_rel_line             ; F7
                fdb     op_fill                 ; F8
* ★ F9/FA REMAIN 0 AND HALT LOUDLY, and that is reported rather than hidden (AC-4). No picture
* in the gated set uses them -- picset.py's census across three games counts set_pattern=0 and
* pattern_brush=0 -- so they are UNREACHED, not silently skipped. A silent no-op is forbidden.
                fdb     0                       ; F9 set_pattern   -- unreached by the set
                fdb     0                       ; FA pattern_brush -- unreached by the set

* pic_get — next picture byte into A
pic_get:        ldx     pic_ptr
                lda     ,x+
                stx     pic_ptr
                rts

* ── F0 set_visual / F1 disable / F2 set_priority / F3 disable ──────
op_set_visual:  jsr     pic_get
                sta     scr_color
* ★ Maintain the doubled byte HERE, where the colour changes, instead of in put_pixel, where it
* is read. This is the only place scr_color is written by a picture.
                anda    #$0F
                sta     scr_dbl
                lsla
                lsla
                lsla
                lsla
                ora     scr_dbl
                sta     scr_dbl
                lda     #1
                sta     scr_on
                rts
op_dis_visual:  clr     scr_on
                rts
op_set_pri:     jsr     pic_get
                sta     pri_color
                lda     #1
                sta     pri_on
                rts
op_dis_pri:     clr     pri_on
                rts

* ── F5 x_corner: x,y then alternating x,y,x,y... ──────────────────
op_x_corner:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
                lda     #1
                sta     xc_isx                  ; next parameter is an X
xc_lp:          jsr     pic_peek
                cmpa    #$F0
                bhs     xc_done
                jsr     pic_get
                tfr     a,b                     ; B = the new coordinate
                lda     cur_x
                sta     ln_x1
                lda     cur_y
                sta     ln_y1
                lda     xc_isx
                beq     xc_isy
                stb     cur_x
                bra     xc_draw
xc_isy:         stb     cur_y
xc_draw:        lda     cur_x
                sta     ln_x2
                lda     cur_y
                sta     ln_y2
                jsr     draw_line
                lda     xc_isx
                eora    #1
                sta     xc_isx
                bra     xc_lp
xc_done:        rts

* ── F4 y_corner: x,y then alternating y,x,y,x... ──────────────────
* ★★ THE SAME LOOP AS x_corner, ENTERED ON THE OTHER PHASE. At the pin, `xCorner` and
* `yCorner` are mirror-image functions [picture.cpp:178,219 @ 9d9b9e9]: x_corner takes an X
* first and draws a horizontal segment, y_corner takes a Y first and draws a vertical one, and
* both then alternate. `xc_isx` already encodes exactly that phase, so y_corner is x_corner
* with the toggle cleared instead of set. ★ Sharing the loop is not a shortcut -- it is the
* same mechanism in the reference, and duplicating it would let the two drift.
* ★ Called as `yCorner()` from drawPicture's 0xF4 case, i.e. skipOtherCoords=false; the true
* variant is the AGI256/v1 path and is not this target (§2H check 2 -- the caller carries the
* scope).
op_y_corner:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
                clr     xc_isx                  ; next parameter is a Y  <-- the only difference
                bra     xc_lp

* ── F6 abs_line: x,y then absolute x,y PAIRS ──────────────────────
* [ref: picture.cpp draw_LineAbsolute @ 9d9b9e9] -- getNextCoordinates(x2,y2) is
* getNextXCoordinate && getNextYCoordinate, so on a terminating byte the X IS ALREADY
* CONSUMED and only the Y is rewound (getNextParamByte does `_dataOffset--`). ★ This peeks
* each byte before taking it, which reproduces that asymmetry exactly: X is consumed, then Y
* is peeked, and a terminator at the Y position leaves the X spent.
op_abs_line:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
al_lp:          jsr     pic_peek
                cmpa    #$F0
                bhs     al_done
                jsr     pic_get                 ; X consumed
                pshs    a
                jsr     pic_peek
                cmpa    #$F0
                bhs     al_pop                  ; terminator at Y: X stays spent
                jsr     pic_get                 ; Y consumed
                tfr     a,b                     ; B = y2
                lda     cur_x
                sta     ln_x1
                lda     cur_y
                sta     ln_y1
                puls    a                       ; A = x2
                sta     cur_x
                sta     ln_x2
                stb     cur_y
                stb     ln_y2
                jsr     draw_line
                bra     al_lp
al_pop:         leas    1,s                     ; discard the consumed X
al_done:        rts

pic_peek:       ldx     pic_ptr
                lda     ,x
                rts

* ── F7 rel_line: x,y then packed signed nibble deltas ─────────────
op_rel_line:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
rl_lp:          jsr     pic_peek
                cmpa    #$F0
                bhs     rl_done
                jsr     pic_get
                pshs    a
                lda     cur_x
                sta     ln_x1
                lda     cur_y
                sta     ln_y1
* ★★★ SIGN-MAGNITUDE, NOT TWO'S COMPLEMENT. picture.cpp:640-643:
*     if (dx & 0x08) dx = -(dx & 0x07);
*     if (dy & 0x08) dy = -(dy & 0x07);
* Bit 3 is a SIGN BIT and bits 0-2 are the MAGNITUDE, so $F is -7. A two's-complement
* sign-extension (`ora #$F0`) makes $F into -1 instead, and every negative delta lands in the
* wrong place. That was this probe's first real rendering defect: the lines went astray, so the
* colour-7 fills had no boundary, leaked across the whole picture, and left nothing white for
* the final background fill to claim. 92% of the visual plane differed for want of these four
* instructions.
                lda     ,s
                lsra
                lsra
                lsra
                lsra                            ; A = high nibble = dx
                bita    #$08
                beq     rl_dxpos
                anda    #$07                    ; magnitude
                nega                            ; ...negated
rl_dxpos:       adda    cur_x
                sta     cur_x
                puls    a
                anda    #$0F                    ; A = low nibble = dy
                bita    #$08
                beq     rl_dypos
                anda    #$07
                nega
rl_dypos:       adda    cur_y
                sta     cur_y
                lda     cur_x
                sta     ln_x2
                lda     cur_y
                sta     ln_y2
                jsr     draw_line
                bra     rl_lp
rl_done:        rts

* ── F8 fill: (x,y) pairs until the next opcode ────────────────────
op_fill:        jsr     pic_peek
                cmpa    #$F0
                bhs     of_done
                jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                ldd     CNT_FILL                ; AC-7: invocations, counted even when skipped
                addd    #1
                std     CNT_FILL
* ★★★ -DPIC_NOFILL — THE DECOMPOSITION BUILD (AC-5). There is no cycle counter on a 6809 and
* per-call instrumentation would perturb what it measures, so fill cost is obtained by
* DIFFERENCE: the same binary, the same picture, the fill call alone suppressed. Both builds
* still walk the resource, consume the same operands and count the same invocations, so the
* delta is the flood fill and nothing else. ★ This build renders a WRONG picture on purpose
* and must never be gated -- picdiff is not run on it.
                ifndef  PIC_NOFILL
                jsr     flood_fill
                endc
                bra     op_fill
of_done:        rts

* ═══════════════════════════════════════════════════════════════════
* State. Absolute rather than direct-page: this is a probe, clarity beats a few cycles, and
* the HAL owns DP $00-$1F.
* ═══════════════════════════════════════════════════════════════════
done_flag       equ     STATUS
bad_op          equ     STATUS+1

pic_ptr         fdb     0
pix_off         fdb     0
cur_x           fcb     0
cur_y           fcb     0
scr_color       fcb     0
scr_dbl         fcb     0       ; (scr_color & 15) * 17 -- see put_pixel
pri_color       fcb     4
scr_on          fcb     0
pri_on          fcb     0
xc_isx          fcb     0
fcb_n           fdb     0       ; -DFC_BENCH loop counter (see the bench block)

* ★ ONLY THE HAL MODULES THIS PROBE ACTUALLY CALLS. T-P0-012 needed ~150 bytes of code space
* and the probe had 101; input/sound/file/mem/disk_read were assembled into every build and
* never called. Verified by grep that none of the five is referenced from sys/time/irq_vbl/gfx
* or from this file. ★★ Dropping an include does not modify a SHARED file (§2M) — the files are
* untouched and hal_sync_check still reports OK across all three repos.
                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"
                end     probe_entry
