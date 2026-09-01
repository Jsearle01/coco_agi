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
STACK_TOP       equ     $0400           ; one past the last usable fill entry
HW_STACK        equ     $0700           ; 6809 S, grows DOWN into $0400..$06FF
* ★★★ P3.13 — THE SEED STACK WAS CUT FROM 1024 B TO 768 B AND THE ORIGIN MOVED DOWN 256 B,
* because the COUNTED build overran PIC_DATA and the gate reported it as one picture with
* "no output" rather than as a build error.
*   org $0800 + 2,579 bytes = $1213, and PIC_DATA is $1200 -- a 19-byte overlap.
* ★★ The nocount build (2,451 B -> $1193) fitted, so the TIMINGS were valid and only the
* GATE broke. A size regression that damages one artifact and not the other is exactly the
* kind that hides.
* ★ The space came from the seed stack, which was provisioned at 512 entries against a
* MEASURED peak of 37 (74 bytes). 384 entries is still 10x the measured peak, and the
* overflow path still HALTS rather than wrapping.
* ★★★ Margin is now 237 bytes and it is ASSERTED at assembly time below, not assumed.
PRI_BASE        equ     $1700           ; 160*168 = $6900 -> ends at $8000
FB_BASE         equ     $8000           ; GFX_DB_WINDOW

* Where the driver leaves the picture resource, and where the probe reports.
*
* ★★ BOTH ADDRESSES MUST LIE BELOW $8000. The framebuffer window is $8000-$FFFF and
* HAL_gfx_set_mode CLEARS it, so anything staged up there is destroyed before the first opcode
* is read. The gap between the code (~$1125) and the priority plane ($1700) is the only space
* that is neither cleared nor overwritten, so both live there.
* ★★★★ PACKING PAYS FOR ITS OWN CODE GROWTH, IN THIS PROBE'S MAP.
* The packed priority plane is 13,440 B, not 26,880, so it ends at $4B80 instead of $8000 --
* **freeing 13,440 bytes between $4B80 and the framebuffer window.** The packed span walk grows
* the code past $1200, so PIC_DATA moves into that freed space and the code region becomes
* $0800..$1700 instead of $0800..$1200.
* ★★ This is the GATE PROBE's layout, not the shipped map -- it exists so 45 pictures can be
* poked and compared, and it is free to differ. The shipped figure is p3b_probe.s's assertion.
* ★ Stated because "the code got bigger so I moved a buffer" is exactly the kind of change that
* silently invalidates a gate if the buffer lands somewhere the plane clears.
                ifdef   PRI_PACKED
PIC_DATA        equ     $5000           ; ★ in the space the packed plane vacated ($4B80..$8000)
                else
PIC_DATA        equ     $1200           ; picture resource, poked in by the MAME side.
                endc
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
* ★★ -DPIC_STRADDLE only. The three multipliers that price windowing designs A and B; see the
* census block in pic_fill.s for what each one is for.
CNT_STRSPAN     equ     $009E           ; spans on a row whose 3-row neighbourhood straddles
CNT_STRPIX      equ     $00A0           ; pixels written by those spans
CNT_SECFLUSH    equ     $00A2           ; flushes that write a SECOND plane (design B's cost)
* ★★★★ THE DENOMINATOR, AND IT IS NOT CNT_SPAN. CNT_SPAN counts SEED POINTS PUSHED onto the fill
* stack; a flush happens once per completed RUN, and the two differ by a large factor. Pricing
* either design against CNT_SPAN would have divided by the wrong number -- CLAUDE.md 2H's worked
* example, verify what a figure COUNTS rather than what its name suggests.
CNT_FLUSH       equ     $00A4           ; runs actually flushed -- the real per-span multiplier

                org     $0700
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
* ★★★★ THE CENSUS COUNTERS MUST BE ZEROED HERE TOO, AND THE FIRST RUN PROVED IT.
* Every counter above is cleared per render because this probe renders many pictures in one
* session. Adding three at $009E-$00A3 and not adding them here left them holding whatever the
* RAM held: the first sweep reported str_span 18,978 against str_pix 1,355 for a picture with
* 357 seeds -- **a span counted without its pixels is arithmetically impossible**, which is what
* made the omission visible rather than merely wrong.
* ★★ The failure is quiet in the other direction: had the garbage been small, the numbers would
* have looked plausible and priced a design decision.
                ifdef   PIC_STRADDLE
                std     CNT_STRSPAN
                std     CNT_STRPIX
                std     CNT_SECFLUSH
                std     CNT_FLUSH
                endc
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
                jsr     pal_readback            ; ★ AC-11: prove they LANDED
                ifdef   PIC_PALSWATCH
* ★ AC-12: paint the swatches and present, instead of rendering a picture. The gate is the
* SCREEN, so the run ends here rather than falling into pic_render.
                jsr     pal_swatch
                jsr     HAL_gfx_swap
ps_hold:        bra     ps_hold
                endc
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

* ═══════════════════════════════════════════════════════════════════
* pal_readback — AC-11: read $FFB0-$FFBF back and stage it for the host
*
* ★★★ WHY THIS EXISTS AT ALL. The picture gate compares the FRAMEBUFFER -- index values per
* pixel -- and the palette is what turns an index into a colour. It lives entirely outside the
* buffer, so SIXTEEN WRONG VALUES WOULD STILL PASS 45/45 BYTE-IDENTICAL. A readback path and a
* display path are different paths, and the palette is only on the display path.
*
* ★★ THE TOP TWO BITS MUST BE MASKED ON READ, and this is documented rather than discovered:
* "These registers can also be read to determine what palettes are set but like the MMU
* registers, the upper 2 bits must be masked out."
* [ref: docs/ground-truth/SockmasterGime.md — "FFB0-FFBF Color palette registers"]
* ★ Without the mask the comparison would report sixteen false mismatches and the obvious
* conclusion would be that pal_load is broken.
*
* ★ This proves the intended values LANDED. It does NOT prove they are the right colours --
* that is AC-12's eye gate, and it is Jay's (CLAUDE.md §3, §4).
* ═══════════════════════════════════════════════════════════════════
PAL_READBACK    equ     $00A0           ; 16 bytes the host reads after the run
pal_readback:
                ldy     #$FFB0
                ldx     #PAL_READBACK
pal_rb_lp:      lda     ,y+
                anda    #$3F                    ; ★ mask bits 7-6 [SockmasterGime.md, above]
                sta     ,x+
                cmpy    #$FFC0
                blo     pal_rb_lp
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

* ═══════════════════════════════════════════════════════════════════
* pal_swatch — AC-12: sixteen bands, one per palette index, in index order
*
* ★★★ AN EYE GATE DESIGNED FOR THE QUESTION. Three 25.3 passes on rooms rule out gross errors
* and would not catch brown reading as dark yellow, because nothing in a room isolates one
* index. Sixteen labelled-by-position bands do: index N is the Nth band from the left, always,
* so "band 6 is wrong" names an entry rather than a symptom.
*
* ★ NO GAME DATA IS INVOLVED -- sixteen blocks of a known index. So the capture is not
* copyrighted content and can be handled normally (the note says so explicitly).
*
* ★★ 160 px / 16 = 10 px per band = 5 bytes per band at 2 pixels/byte. The index is doubled
* into both nibbles, which is the same `scr_dbl` convention the renderer uses (§3.4).
* ═══════════════════════════════════════════════════════════════════
                ifdef   PIC_PALSWATCH
pal_swatch:
                ldu     #FB_BASE
                ldb     #PIC_H                  ; rows
ps_row:         pshs    b
                clra                            ; A = colour index 0..15
ps_band:        pshs    a
                lsla
                lsla
                lsla
                lsla                            ; A = index<<4
                ora     ,s                      ; both nibbles = the index
                ldb     #5                      ; 5 bytes = 10 pixels per band
ps_byte:        sta     ,u+
                decb
                bne     ps_byte
                puls    a
                inca
                cmpa    #16
                blo     ps_band
                puls    b
                decb
                bne     ps_row
                rts
                endc

* ★★★★ THE SEVENTH SITE OF THE NIBBLE CONVENTION, AND IT WAS NOT ON THE LIST OF SIX.
* Packing the plane broke the renderer gate on every picture -- visual identical, priority
* differing by ~13,440 pixels, which is EXACTLY half the plane. The cause is here: the clear
* wrote `$0404` (two bytes of priority 4) over PIC_W*PIC_H bytes, so packed it left every EVEN
* pixel's high nibble at 0 and every odd pixel at 4, and overran the 13,440-byte plane by
* another 13,440 into the framebuffer window.
* ★★★ I enumerated six sites by grepping for plane ACCESS and missed the one that INITIALISES
* it -- a clear is not a read and not a write of a pixel, so it matched no pattern I searched
* for. **The half-the-plane symptom is what named it: a wrong nibble convention corrupts every
* other pixel, and 13,114-of-26,880 is that signature.**
* ★★ Both the fill value and the LENGTH change; either alone still fails.
pri_clear:
                ldx     #PRI_BASE
                ifdef   PRI_PACKED
                ldd     #$4444                  ; four packed pixels of priority 4
pc_lp:          std     ,x++
                cmpx    #PRI_BASE+(PIC_W*PIC_H/2)
                else
                ldd     #$0404
pc_lp:          std     ,x++
                cmpx    #PRI_BASE+(PIC_W*PIC_H)
                endc
                blo     pc_lp
                rts

* ★★★★ THE RENDERER MOVED TO src/harness/pic_core.s (T-P0-032) so p3b_probe.s can include it.
* pix_addr, in_bounds, put_pixel, pic_render, the op handlers and the renderer state were all
* in this file, which meant the gated "renderer" could not be built into any other image.
* ★★ A PURE MOVE: same content, same order, same position. pic_probe.bin is byte-identical
* across the change and that is verified, not assumed.
* ★★★ plane_win.s BEFORE pic_core.s: pic_core's windowed sites `jsr plane_vis`, and lwasm needs
* the label defined for a direct addressing decision on a forward reference. Under the flat build
* the module still assembles but nothing calls it -- verified by pic_probe.bin remaining
* byte-identical at 2,642.
                ifdef   PLANE_WINDOWED
                include "src/harness/plane_win.s"
                endc
                include "src/harness/pic_core.s"

* ═══════════════════════════════════════════════════════════════════
* State. Absolute rather than direct-page: this is a probe, clarity beats a few cycles, and
* the HAL owns DP $00-$1F.
* ═══════════════════════════════════════════════════════════════════
done_flag       equ     STATUS
bad_op          equ     STATUS+1

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

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE LAYOUT ASSERTION. The counted build silently grew past PIC_DATA in P3.13 and the
* only symptom was ONE picture reporting "no output" in a 45-picture gate -- a build error
* wearing a rendering error's clothes. This makes it an ASSEMBLY failure instead.
* ★★ IT MUST SIT BEFORE `end`, WHICH TERMINATES ASSEMBLY. Placed after it, the whole block --
* label, condition and error -- is silently ignored, which is how the first version of this
* guard was written. ★ An assertion that has not been broken on purpose is not an assertion.
PIC_CODE_END    equ     *
                ifgt    PIC_CODE_END-PIC_DATA
                error   "pic_probe code overlaps PIC_DATA -- shrink it or move the layout"
                endc

                end     probe_entry
