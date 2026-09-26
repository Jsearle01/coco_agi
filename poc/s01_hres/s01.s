* poc/s01_hres/s01.s -- Spike S-01 rev B: does a mid-frame GIME register change hold under MAME?
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ NOT THE PORT. No HAL, no includes, no gates, no oracle. A single standalone binary,
* assembled on its own and poked into a DECB machine at its OK prompt [§6]. `src/hal/` is shared
* with two other projects and this file touches none of it.
*
* ★★★★★ TWO STAGES IN ONE BINARY, selected by s01_mode, which the HOST pokes:
*   mode 0 = STAGE 0, THE CONTROL: flip PALETTE register $FFB1 mid-frame. A mid-frame palette
*            change is the classic CoCo3 raster trick and is not in doubt on silicon, so if it
*            does not split under MAME then MAME renders from frame-start register state and
*            CANNOT ANSWER THIS CLASS OF QUESTION AT ALL [§2].
*   mode 1 = STAGE 1: flip HRES in $FF99 mid-frame -- the thing actually under test.
*
* ★★★★★ RUN STAGE 0 FIRST. A stage-1 failure means nothing until stage 0 passes [§2, §7].
*
* ── the mode pair, and why it is the 4-COLOUR pair ──────────────────────────────────────────
* ★★★★ $FF99 = $15 is 320x192x4, 80 bytes/row, 15,360 bytes; $0D is 160x192x4, 40 bytes/row.
* HRES is bits 4-2 and selects bytes-per-row alone: 101 -> 80, 011 -> 40. So $15 -> $0D changes
* ONLY the horizontal resolution and leaves colour depth alone, which is exactly the variable.
* ★★★ THE PORT'S REAL TARGET IS THE 16-COLOUR PAIR, $1E (320, 160 B/row) <-> $16 (160, 80 B/row),
* and this spike deliberately does NOT use it: a 16-colour buffer is 30,720 bytes and would cross
* $8000 into ROM territory, forcing all-RAM mode and putting the interrupt vectors in RAM.
* ★★★★ At 4 colours the whole framebuffer sits at $4000-$7BFF, which is RAM under EVERY map, so
* nothing about the memory map can confound the result. **A pass here is about the GIME's HRES and
* address-counter behaviour and would still need confirming on the 16-colour pair.** Said here
* rather than discovered later.
*
* ── register values: every one is confirmed IN-TREE, not derived here ───────────────────────
*   $FF90 = $4C    COCO=0, MMUEN=1, IEN=0, FEN=0 -- "sufficient for a standalone demo without
*                  interrupts", from GFXMODE3.ASM (MAME-verified Nov 2025)
*                  [ref: src/hal/coco3-dsk/gfx.s:133-178]
*   $FF98 = $80    VMODE: BP=1 graphics          [ref: src/hal.inc:105]
*   $FF99 = $15    VRES: LPF=00, HRES=101, CRES=01, 320x192x4   [ref: src/hal.inc:106, 327]
*   VOFFSET        = physical address >> 3       [ref: gfx.s:206-215, $7C000 -> $F800]
*   $FF9C, $FF9F   VSCROL and HOFFSET are UNDEFINED at reset and REQUIRED to be cleared
*                                                [ref: gfx.s:217-223]
*   $FF92          write = enable ($08 = VBORD); read = status AND ACK, bit 3 = VBL
*                                                [ref: src/hal/coco3-dsk/irq_vbl.s:67-78]
*   ORDER          $FF90 first -> clear -> mode -> VOFFSET -> VSCROL -> HOFFSET -> SAM ->
*                  PALETTE LAST. ★★★★ Constraint B is load-bearing for THIS spike in particular:
*                  "palette writes do not appear to latch correctly until $FF98/$FF99 is in its
*                  final state" [gfx.s:143-152]. Stage 0 flips a palette register, so if the mode
*                  were not already settled a null result would be that latching rule, not MAME.
*                  The mode is written before any palette write here, init and mid-frame alike.
*
* ★★★ ONE DELIBERATE DIVERGENCE FROM THE VERIFIED SEQUENCE, AND IT IS NOT AN OVERSIGHT:
* gfx.s step 8 writes $FFDF (all-RAM). **This file does NOT.** Everything it touches -- code at
* $3000, stack below it, framebuffer $4000-$7BFF -- is RAM in every map, so all-RAM buys nothing,
* while it WOULD move the 6809's interrupt vectors at $FFF0-$FFFF into RAM. DECB may leave the
* FDC's NMI enabled, and an NMI through a garbage vector would crash the machine in a way that
* looks exactly like "stage 0 failed" -- a false negative on the control, which §2 says closes
* 160-wide for the wrong reason. $FFD9 (1.79 MHz clock) IS written: the delay loop is calibrated
* in CPU cycles.
*
* ★★★★★ s01_frames IS THE LIVENESS WITNESS AND IT IS NOT DECORATION [§2W]. If the screen shows no
* split, "MAME does not sample mid-frame" and "the guest crashed before the first flip" are the
* same picture. The host reads this counter: a split-free screen with a RISING counter is a real
* negative; a stalled counter is a broken spike and says nothing about the GIME.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                org     $3000

S01_FB          equ     $4000           ; framebuffer, logical
S01_FBEND       equ     $7C00           ; +15,360 bytes = 80 B/row x 192 rows
S01_VOFF        equ     $E800           ; physical $74000 >> 3  (logical $4000, MMU block $3A)
S01_VRES_320    equ     $15             ; HRES=101, 80 B/row
S01_VRES_160    equ     $0D             ; HRES=011, 40 B/row   <- the mid-frame target
S01_PIX1        equ     $55             ; four pixels of palette index 1, at 2 bits per pixel

entry:
* ★★★ Mask IRQ AND FIRQ. This spike POLLS $FF92 and never vectors; with IEN=0 in $FF90 the GIME
* raises nothing anyway, and masking makes that a property of the CPU as well as of the GIME.
                orcc    #$50
                lds     #$2F00          ; our own stack, below the code, growing down

* ── Step 0: PIN THE FRAMEBUFFER's MMU SLOTS ─────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ ADDED AFTER THE SPIKE LIED TO ME. The first stage-1 and static runs displayed a screen
* that CANNOT have been this framebuffer: with every one of 15,360 bytes set to the same value,
* every row must render identically, and the row profile came back patterned at the top, FLAT
* through the middle and patterned at the bottom. **The display was showing someone else's memory.**
* ★★★★★ THE CAUSE IS AN ASSUMPTION I MADE AND DID NOT CHECK: VOFFSET is a PHYSICAL address >> 3, so
* logical $4000 only lands at physical $74000 if MMU slot 2 holds block $3A. I took DECB's default
* map on faith -- and p3b_run.lua does NOT: it writes $FFA0-$FFA7 explicitly on every launch.
* ★★★★ ONLY SLOTS 2 AND 3 ARE WRITTEN, and that is deliberate. Slot 1 covers $2000-$3FFF, which is
* where this code is executing from; rewriting the ground under our own feet would crash the machine
* if the assumption were wrong -- the very case being defended against. Slots 2+3 cover $4000-$7FFF,
* the whole framebuffer, and nothing is executing there.
* ★★★ gfx.s:212-213 carries this as acknowledged project debt: "VOFFSET CORRECTNESS: inferred from
* disassembly; NOT verified in P2.3a. Discharge by P2.3a.1 sentinel test." This spike inherited an
* unverified assumption and then reported a GIME result on top of it.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND PINNING SLOTS 2-3 ALONE DID NOT FIX IT, WHICH NARROWED THE CAUSE: $FFA0-$FFA7 is MMU
* TASK 0 and $FFA8-$FFAF is TASK 1, and which one is live is $FF91 bit 0. Writing task 0's slots
* while the machine runs on task 1 changes a map nothing is using -- the code keeps running and the
* framebuffer keeps landing wherever task 1 puts it.
* ★★★★ THE ORDER HERE IS THE SAFE ONE: fill in ALL EIGHT task-0 slots FIRST, while still running on
* whatever task DECB chose, and only then select task 0. The map is completely valid before it
* becomes live, so this cannot pull the ground out from under the code -- which writing slot 1
* piecemeal could.
                ldx     #$FFA0
                lda     #$38
s01_mmu:
                sta     ,x+
                inca
                cmpa    #$40
                bne     s01_mmu
                clr     $FF91                   ; TR=0 -> task 0 is live; logical $4000 = phys $74000

* ── Step 1: $FF90 FIRST ─────────────────────────────────────────────────────────────────────
                lda     #$4C
                sta     $FF90

* ── Step 2: fill the framebuffer BEFORE the mode is set (verified order) ────────────────────
* Every pixel is palette index 1, so the screen is ONE FLAT COLOUR and a mid-frame palette change
* produces exactly two bands. ★★ A flat field is what makes the boundary a scanline number rather
* than a judgement about a picture [§5].
* ★★★★★ TWO FILLS, AND STAGE 1 CANNOT USE STAGE 0's [found by running stage 0 first]. A flat field
* is exactly right for the palette control -- it makes the boundary a scanline number -- and it is
* USELESS for HRES, because a uniform screen renders identically at 320 and at 160. **Changing the
* resolution of a field with no detail changes nothing observable.**
*   s01_fillm = 0   every byte = s01_fillb. $55 is four pixels of index 1 (flat, stage 0);
*                   $0F is indices 0,0,3,3 -- a FOUR-PIXEL VERTICAL STRIPE, whose on-screen period
*                   DOUBLES when HRES halves, which is the measurable consequence (stage 1a).
*   s01_fillm = 1   row N is filled with the byte value N. ★★★★ This is §3.2's instrument: the
*                   address counter advances by the CURRENT mode's line length, so rows below a
*                   switch consume a different number of bytes than rows above, and the displayed
*                   byte VALUE says which source row arrived. Recoverable from the pixels because
*                   the four palette entries are set to four distinct colours (stage 1b).
                lbsr    s01_do_fill             ; ★ long: the 16-colour fill pushed this past 127 bytes

* ── Step 3: mode ────────────────────────────────────────────────────────────────────────────
                ldd     #$8000+S01_VRES_320
                std     $FF98                   ; $FF98=$80 VMODE, $FF99=$15 VRES
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ MODE 2 IS THE STATIC REFERENCE, AND IT EXISTS BECAUSE STAGE 1 WAS RUN WITHOUT IT AND THE
* RESULT WAS UNINTERPRETABLE. The first stage-1 run reported a row profile that was patterned at the
* top, FLAT through the middle and patterned again at the bottom -- which is neither "the resolution
* halved" nor "nothing happened", and there was no way to tell which part was the mid-frame write and
* which part was simply what this $FF99 value DOES.
* ★★★★★ **A dynamic result is not readable without the static picture of both endpoints.** Mode 2
* writes s01_vresb once and never flips, so `-Stage 2 -VresB $15` and `-Stage 2 -VresB $0D` give the
* two reference profiles the mid-frame run must be compared against. Same discipline as §2's own
* control, one level down: establish what the thing looks like when it is NOT being switched.
                lda     s01_mode
                cmpa    #2
                bne     s01_not_static
                lda     s01_vresb
                sta     $FF99                   ; the static mode under examination
s01_not_static:
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ── Step 4: VOFFSET ─────────────────────────────────────────────────────────────────────────
* ★★★★★ VOFFSET IS HOST-POKED AND SWEPT, NOT DERIVED, BECAUSE DERIVING IT WAS WRONG. The framebuffer
* readback proves all 15,360 bytes hold the fill value and the screen still does not show them, so the
* fault is on the display side and the arithmetic (physical >> 3, logical $4000 -> block $3A ->
* physical $74000 -> $E800) is the thing that has to be believed. ★★★★ It has been believed twice and
* it is the project's OWN undischarged debt: gfx.s:212 says "VOFFSET CORRECTNESS: inferred from
* disassembly; NOT verified. Discharge by sentinel test."
* ★★★★★ **So the sweep finds it.** With a constant fill in a static mode the correct VOFFSET is the
* only one that makes EVERY sampled row patterned and equal, which is a pass/fail the host computes.
* A third derivation would have been a third guess.
                ldd     s01_voff
                std     $FF9D

* ── Steps 5 and 6: VSCROL and HOFFSET -- REQUIRED, undefined at reset ───────────────────────
                clr     $FF9C
                clr     $FF9F

* ── Step 7: SAM clock (NOT $FFDF -- see the header) ─────────────────────────────────────────
                clra
                sta     $FFD9                   ; 1.79 MHz

* ── Step 8: palette LAST (Constraint B) ─────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ ALL FOUR ENTRIES ARE HOST-SET INDEPENDENTLY OF THE FLIPPING PAIR [S-02]. They used to be
* entangled: index 1 took its init value from s01_colA (the flip's "top" colour) and index 3 from
* s01_col3, and with the defaults BOTH were $3F -- so two palette indices rendered identically and
* the row-number decode could not tell them apart. **Calibration caught it and refused to run**,
* which is the behaviour wanted, but the cause was this coupling.
* ★★★★ Now col0..col3 are the DISPLAYED palette and colA/colB are only the flip, so the two concerns
* are separable: S-02 needs four distinct displayed colours AND a changing register value, and it
* gets the second by flipping an entry that 4-colour mode never displays (see s01_palreg).
* ★★★★★ AT 16 COLOURS ALL SIXTEEN ENTRIES MUST BE SET, AND THE FIRST 16-COLOUR RUN PROVED IT.
* Only indices 0-3 were initialised, so 4-15 held whatever DECB had left -- and with the row-number
* fill, two colliding entries make two CONSECUTIVE SOURCE ROWS render identically. That injected
* spurious "2"s into the rows-per-source-row measurement above the boundary, which is the region the
* control depends on.
* ★★★★ It biased AGAINST the finding rather than for it (it makes the wide region look like the narrow
* one), so the conclusion held -- **but a measurement with a known contaminant gets cleaned, not
* explained.** Sixteen distinct 6-bit values, so no two indices can render alike.
                lda     s01_big
                beq     s01_pal4
                ldx     #s01_pal16
                ldy     #$FFB0
                ldb     #16
s01_p16:        lda     ,x+
                sta     ,y+
                decb
                bne     s01_p16
                bra     s01_pal_done
s01_pal4:
                lda     s01_col0
                sta     $FFB0
                lda     s01_col1
                sta     $FFB1
                lda     s01_col2
                sta     $FFB2
                lda     s01_col3
                sta     $FFB3
s01_pal_done:
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ★ Enable VBORD as a POLLABLE source. IEN stays 0, so this latches status without vectoring.
                lda     #$08
                sta     $FF92

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AN EXPLICIT BRANCH TO THE LOOP, AND IT IS HERE BECAUSE ITS ABSENCE COST TWO ROUNDS OF
* DEBUGGING. The init used to reach s01_loop by FALLING THROUGH, which was correct only while nothing
* sat between them. Converting the fill to a subroutine put `s01_do_fill` in that gap, so the init
* fell into the fill, ran it a second time, and executed its `rts` with nothing on the stack --
* returning to $8006 with S eight bytes ABOVE its initial value.
* ★★★★ The symptom was `s01_frames = 0` beside a correct framebuffer and a correct palette, and the
* liveness witness is what named the guest rather than the display [§2W]. **The PC and S are what
* identified it**, after two hypotheses about the palette had already been spent.
* ★★★ Stated as a rule for this file: **nothing here relies on implicit fall-through into the loop.**
* An inserted subroutine must not be able to change control flow, and one `bra` buys that permanently.
                lbra    s01_loop                ; ★ long, for the same reason
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ═══════════════════════════════════════════════════════════════════════════════════════════
* THE LOOP. Per frame: wait for the vertical border, assert the TOP state, burn s01_dly, assert
* the BOTTOM state. ★★★★ The boundary's position is a FUNCTION OF s01_dly, which the host pokes
* and sweeps -- so the question is not "is there a band in the right place" but "does the boundary
* MOVE with the delay", which is a much harder thing for an accident to satisfy.
* ★★ One inner iteration is `leax -1,x` + `bne` = 8 CPU cycles. A 60 Hz frame is ~29,830 cycles at
* 1.79 MHz, of which the vertical blank is ~8,000 and the 192 active lines ~21,800, so the useful
* sweep is roughly s01_dly = 0 .. 3,700.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FILL AS A SUBROUTINE, AND A HOST-TRIGGERED REFILL, SO CALIBRATION AND MEASUREMENT HAPPEN
* IN ONE SESSION [S-02 §4A]. Reading the row-number fill back requires knowing which on-screen colour
* is which palette INDEX, and deriving that from the CoCo3 palette byte would import an assumption
* about MAME's RGB conversion that nothing would check.
* ★★★★ So the host calibrates empirically: fill with $1B (= indices 0,1,2,3 in one byte), read the four
* colours off one row, then poke s01_fillm=1 and s01_refill=1 and measure. **Same session, same palette
* state, no cross-run assumption** -- which matters because S-01's whole mess came from comparing runs.
* ★★ The fill costs ~200k cycles (~7 frames) and the guest simply misses those VBORDs.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ §4A: THE 16-COLOUR BUFFER IS FILLED THROUGH A MOVING WINDOW, SO ALL-RAM IS NEVER ENTERED
* AND THE 6809's VECTORS STAY IN ROM.
*
* ★★★★★ THE OBSERVATION THAT MAKES THIS FREE: **VOFFSET addresses PHYSICAL RAM, not the CPU's logical
* space** [gfx.s:206-215, and S-01 confirmed $E800 -> physical $74000 empirically]. The GIME fetches
* the framebuffer without going through the MMU, so the buffer NEVER has to be visible to the CPU all
* at once -- only the bytes being WRITTEN do.
* ★★★★ So a 30,720-byte buffer lives at physical $74000-$7B7FF (blocks $3A,$3B,$3C,$3D) and is filled
* in one pass through logical $4000-$7FFF, remapping slots 2 and 3 at the seam. **Logical $4000-$7FFF
* is RAM under every map**, so nothing is written into ROM territory, $FFDF is never touched, and
* $FFF0-$FFFF keeps its ROM vectors.
* ★★★★★ THAT DISPOSES OF §1.2's TRAP BY AVOIDING IT RATHER THAN MANAGING IT. The alternative -- all-RAM
* with vectors in RAM -- makes an NMI through garbage indistinguishable from "the mode does not work",
* which is the false negative this series exists to prevent. **Nothing here can produce that failure.**
* ★★★ Code at $3000 is in slot 1 (block $39) and is never remapped; DECB's low RAM is slot 0. Only
* slots 2 and 3 move, and they are restored before the routine returns so the host's framebuffer
* readback still sees the buffer's start.
* ★★ The seam is crossed ONCE: 30,720 < 32,768, so the check fires a single time.
s01_fill16:
                lda     #$3A
                sta     $FFA2
                lda     #$3B
                sta     $FFA3
                ldx     #$4000
                ldu     #30720                  ; bytes remaining
                clrb                            ; B = source row number
                ldy     #160                    ; bytes remaining in this row (160 B/row at $1E)
* ★★★★★ THE MODE DECISION IS HOISTED OUT OF THE LOOP, and that is not tidiness -- it is why this runs
* at all. The first version re-read s01_fillm AND s01_fillb on every one of 30,720 bytes: ~50 cycles a
* byte, **over 50 frames**, so the sample was taken before the guest had reached its loop and
* `s01_frames` read 0. ★★★ The liveness witness named the guest rather than the display for the third
* time in this series, which is exactly what it is for.
                lda     s01_fillm
                bne     s01_f16_rows
* ---- constant fill: A holds the byte for the whole loop ----
                lda     s01_fillb
s01_f16_clp:
                cmpx    #$8000
                blo     s01_f16_cok
                pshs    a
                lda     #$3C
                sta     $FFA2
                lda     #$3D
                sta     $FFA3
                puls    a
                ldx     #$4000
s01_f16_cok:
                sta     ,x+
                leau    -1,u
                cmpu    #0
                bne     s01_f16_clp
                bra     s01_f16_done
* ---- row-number fill: B is the row, Y counts down the row's 160 bytes ----
* ★★ B and Y carry ACROSS the seam, because 16,384 / 160 = 102.4 and a source row straddles it.
s01_f16_rows:
                cmpx    #$8000
                blo     s01_f16_rok
                lda     #$3C
                sta     $FFA2
                lda     #$3D
                sta     $FFA3
                ldx     #$4000
s01_f16_rok:
                tfr     b,a                     ; this row's value
                sta     ,x+
                leay    -1,y                    ; ★ LEAY sets Z; LEAU does not, hence cmpu below
                bne     s01_f16_rnext
                ldy     #160
                incb
s01_f16_rnext:
                leau    -1,u
                cmpu    #0
                bne     s01_f16_rows
s01_f16_done:
                lda     #$3A                    ; ★ restore, so $4000 shows the buffer's start again
                sta     $FFA2
                lda     #$3B
                sta     $FFA3
                rts
* ═══════════════════════════════════════════════════════════════════════════════════════════

s01_do_fill:
                lda     s01_big
                bne     s01_fill16              ; ★ 16-colour: 30,720 B through a moving window
                lda     s01_fillm
                bne     s01_fill_rows
                ldx     #S01_FB
                lda     s01_fillb
s01_fill:
                sta     ,x+
                cmpx    #S01_FBEND
                bne     s01_fill
                rts
* ★★★ Row N is filled with the byte value N, in all 80 of its bytes. So a displayed row reports WHICH
* 80-BYTE BLOCK it read, and that is the granularity the question needs: if the address counter keeps
* running at 40 B/row below the switch, consecutive displayed rows advance by half a block -- the same
* value twice, then +1. **That signature distinguishes §1.1's cases without needing byte precision.**
s01_fill_rows:
                ldx     #S01_FB
                clrb                            ; B = row number, 0..191
s01_fr_row:
                tfr     b,a                     ; every byte of this row carries the row number
                ldy     #80                     ; 80 bytes per row at $FF99=$15 -- the FILL's stride
s01_fr_byte:
                sta     ,x+
                leay    -1,y
                bne     s01_fr_byte
                incb
                cmpx    #S01_FBEND
                bne     s01_fr_row
                rts

* ★★★★★ THE FLIP TARGETS A HOST-SELECTABLE PALETTE REGISTER, and that is what lets S-02 exist.
* The screen only stays current while some palette value CHANGES (measured: a changing $FF99 alone is
* not enough), but the row-number decode needs the four DISPLAYED entries to hold still and be
* distinct. Those two requirements collide on $FFB1.
* ★★★★ 4-colour mode displays indices 0-3 only, so $FFB4-$FFBF are free: S-02 points s01_palreg at
* $B8 and flips an entry nothing renders. The screen keeps refreshing, the displayed palette is
* constant, and the decode works. Stage 0 and stage 1 leave it at $B1 and behave exactly as before.
* ★ A = the value to write; B and X are scratch.
*
* ★★★★★ AND IT LIVES HERE, BESIDE THE OTHER SUBROUTINES, BECAUSE ITS FIRST HOME WAS INSIDE THE LOOP's
* FALL-THROUGH PATH. `s01_bot_hres` ended with `bsr s01_palwr` and the subroutine was the next thing in
* memory, so after returning the CPU fell straight back INTO it and executed `puls b,pc` against a
* return address nothing had pushed. ★★★★ The guest died on its first loop iteration and the symptom
* was `s01_frames = 0` with a correct framebuffer and a correct palette -- the liveness witness naming
* the guest rather than the display, which is exactly what it is for [§2W].
* ★★ Mode 0's paths happened to survive it because both end in an explicit `bra`; only the mode-1
* bottom branch fell through. **A subroutine placed in a fall-through path is a bug that spares
* whichever caller happens to branch away.**
s01_palwr:
                pshs    b
                ldb     s01_palreg
                ldx     #$FF00
                abx
                sta     ,x
                puls    b,pc
* ═══════════════════════════════════════════════════════════════════════════════════════════

s01_loop:
s01_vb:
                lda     $FF92                   ; read = status + ack
                bita    #$08                    ; VBORD?
                beq     s01_vb

* ★ Host-requested refill, serviced once and acknowledged by clearing the flag, so the host can tell
* the refill actually happened rather than assuming it.
                lda     s01_refill
                beq     s01_norefill
                clr     s01_refill
                bsr     s01_do_fill
s01_norefill:

* ★★★ VOFFSET IS RE-WRITTEN EVERY FRAME, so the host can sweep it on a running guest. Without this
* the register keeps its init value and poking s01_voff would change nothing -- a sweep that moves a
* variable the hardware never reads again, which is the shape of a diagnostic that cannot fail [§2W].
                ldd     s01_voff
                std     $FF9D

* ---- the TOP state ----
                lda     s01_mode
                cmpa    #2
                beq     s01_tick                ; ★ static reference: flip nothing, just tick
                tsta                            ; ★ NOT `bne` off the cmpa -- mode 0 leaves Z clear
                bne     s01_top_hres            ;   there and would have taken the HRES branch
                lda     s01_colA
                bsr     s01_palwr
                bra     s01_wait
s01_top_hres:
* ★★★★★ WRITTEN AS A PAIR WITH `std $FF98`, EXACTLY AS THE INIT AND gfx.s DO, AND THAT IS THE
* EXPERIMENT. A lone `sta $FF99` from this loop broke the display in every arm -- even when the value
* written was IDENTICAL to the one the init had already set, and even when the write landed in
* vertical blank. That cannot be real GIME behaviour, so the suspect is the difference from the
* known-good path: gfx.s:203-204 writes `ldd #$8015 / std $FF98`, touching VMODE and VRES together,
* and this loop touched VRES alone.
* ★★★ A = $80 is VMODE's BP bit (graphics), B is the VRES value, so one `std` restates both.
                lda     #$80
                ldb     s01_vrest               ; ★ host-poked, so the 16-colour pair $1E/$16 can
                std     $FF98                   ;   be tried without reassembling
* ★★★★★ AND A PALETTE WRITE ALONGSIDE IT, WHICH IS AN EXPERIMENT AND NOT A FLOURISH. Stage 0 is the
* only arm that renders a correct full-screen graphics picture, and the only thing it does that no
* other arm does is write $FFB1 twice per frame. Every other arm shows a MIX -- the framebuffer in a
* middle band, DECB's text screen above and below -- which is what a bitmap only refreshed where a
* register write forces it would look like. ★★★ With s01_colA = s01_colB the palette does not change,
* so this adds the register TRAFFIC without adding a visual variable: if the screen then renders
* fully, the refresh is driven by palette writes and that is a MAME idiom worth recording.
* ★★★★★ MEASURED SINCE: the refresh IS driven by a changing palette value. The arm that was missing
* -- $FF99 changing while the palette stays constant -- was run and the screen stayed broken, so it
* is not `$FF99` traffic that keeps the bitmap current. **A CHANGING PALETTE VALUE IS REQUIRED.**
                lda     s01_colA
                bsr     s01_palwr

* ---- the delay that places the boundary ----
s01_wait:
                ldx     s01_dly
                beq     s01_switch              ; ★ ldx sets Z: a zero delay skips the loop
s01_dl:
                leax    -1,x
                bne     s01_dl

* ---- the BOTTOM state ----
s01_switch:
                lda     s01_mode
                tsta
                bne     s01_bot_hres
                lda     s01_colB
                bsr     s01_palwr
                bra     s01_tick
s01_bot_hres:
                lda     #$80                    ; ★★★★★ THE THING UNDER TEST, as a paired write
                ldb     s01_vresb
                std     $FF98
                lda     s01_colB                ; ★ the paired palette write -- see the note above
                bsr     s01_palwr
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ TWO MORE SPLITS, IF THE HOST ASKS FOR THEM [S-02 §4C]. MAME records $FF98/$FF99 per scanline,
* so N splits should cost N writes and be no harder structurally than one -- but "should" is not
* measured, and AGI needs it: message boxes and positioned `display` text live INSIDE the picture area
* (P6.62 put KQ3's credit scroll at rows 13-18), so a usable split needs 320 back for a box's rows and
* 160 below it. **That is three boundaries in one frame, not one.**
* ★★★★ Zero in s01_dly2 skips both, so mode 1 behaves exactly as it did for S-01's stage 1.
* ★★★ The palette flip at each split is INVISIBLE here by construction: the stripe fill $0F uses
* indices 0 and 3, and the flip writes index 1. So it keeps the bitmap refreshing without adding a
* visual variable -- **the only thing that can change the run lengths is HRES.**
                ldx     s01_dly2
                beq     s01_split_done
s01_d2:
                leax    -1,x
                bne     s01_d2
                lda     #$80                    ; back to the WIDE mode
                ldb     s01_vrest
                std     $FF98
                lda     s01_colA
                bsr     s01_palwr
                ldx     s01_dly3
                beq     s01_split_done
s01_d3:
                leax    -1,x
                bne     s01_d3
                lda     #$80                    ; and narrow again
                ldb     s01_vresb
                std     $FF98
                lda     s01_colB
                lbsr    s01_palwr
s01_split_done:
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ---- liveness, read by the host ----
* ★★ LONG branches back to the loop. The extra-split block pushed these past 127 bytes and the
* assembler said so; they are long now rather than marginally short, because the next block added
* here would break them again. One extra byte each, on a path taken once per frame.
s01_tick:
                inc     s01_frames+1
                lbne    s01_loop
                inc     s01_frames
                lbra    s01_loop

* ═══════════════════════════════════════════════════════════════════════════════════════════
* HOST-POKED PARAMETERS AND HOST-READ WITNESS. Addresses are resolved from the assembler's map by
* name, never hard-coded in the Lua -- P6.3's stall dump printed a position of 33,849 into a
* 34-byte string from three hard-coded symbol addresses that had gone stale by two bytes [§2W.3].
* ═══════════════════════════════════════════════════════════════════════════════════════════
s01_mode:       fcb     0               ; 0 = palette control, 1 = HRES flip, 2 = STATIC reference
s01_vrest:      fcb     $15             ; TOP $FF99 -- 320x192x4, 80 B/row
s01_vresb:      fcb     $0D             ; BOTTOM $FF99 -- 160x192x4, 40 B/row; also mode 2's value
s01_colA:       fcb     $3F             ; TOP colour -- white
s01_colB:       fcb     $09             ; BOTTOM colour -- NOT black, so it differs from the border
s01_col0:       fcb     $00             ; ★ the DISPLAYED palette, independent of the flipping pair
s01_col1:       fcb     $3F             ;   index 1 -- stage 0/1 overwrite it via the flip
s01_col2:       fcb     $12             ; palette index 2
s01_col3:       fcb     $3F             ; palette index 3 -- the stripe's bright half
s01_palreg:     fcb     $B1             ; ★ low byte of the palette register the FLIP writes.
                                        ;   $B1 = index 1 (stage 0/1). S-02 uses $B8, which 4-colour
                                        ;   mode never displays, so the flip refreshes the bitmap
                                        ;   without disturbing the four decodable colours.
s01_fillm:      fcb     0               ; 0 = constant s01_fillb, 1 = row N filled with N
s01_fillb:      fcb     $55             ; the constant: $55 = flat index 1, $0F = a 4-pixel stripe
s01_refill:     fcb     0               ; ★ host sets to 1; the guest refills and clears it (an ack)
s01_big:        fcb     0               ; ★ 0 = 15,360 B (4-colour); 1 = 30,720 B (16-colour, S-03)
* ★★★ Sixteen DISTINCT CoCo3 palette bytes, so no two indices can render as the same colour. That is
* a requirement of the row-signature measurement, not decoration -- see the note at the palette init.
s01_pal16:      fcb     $00,$09,$12,$1B,$24,$2D,$36,$3F
                fcb     $07,$0E,$15,$1C,$23,$2A,$31,$38
s01_voff:       fdb     S01_VOFF        ; ★ $FF9D/$FF9E -- physical address >> 3; host-poked and swept
s01_dly:        fdb     0               ; delay iterations after VBORD, 8 CPU cycles each
s01_dly2:       fdb     0               ; ★ 0 = one split. Otherwise: back to WIDE after this delay
s01_dly3:       fdb     0               ; ★ and narrow again after this one -- three boundaries
s01_frames:     fdb     0               ; ★ incremented once per frame by the guest

                end     entry
