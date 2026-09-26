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
                lda     s01_fillm
                bne     s01_fill_rows
                ldx     #S01_FB
                lda     s01_fillb
s01_fill:
                sta     ,x+
                cmpx    #S01_FBEND
                bne     s01_fill
                bra     s01_fill_done
s01_fill_rows:
                ldx     #S01_FB
                clrb                            ; B = row number, 0..191
s01_fr_row:
                tfr     b,a                     ; every byte of this row carries the row number
                ldy     #80                     ; 80 bytes per row at $FF99=$15
s01_fr_byte:
                sta     ,x+
                leay    -1,y
                bne     s01_fr_byte
                incb
                cmpx    #S01_FBEND
                bne     s01_fr_row
s01_fill_done:

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
* ★★ FOUR DISTINCT ENTRIES, not two. Stage 0 only needs index 1, but stage 1's stripe uses index 3
* and stage 1b recovers a byte value from all four, so every entry is host-settable and distinct.
                clr     $FFB0                   ; index 0 = black (the background/border)
                lda     s01_colA
                sta     $FFB1                   ; index 1 = the register stage 0 flips
                lda     s01_col2
                sta     $FFB2
                lda     s01_col3
                sta     $FFB3

* ★ Enable VBORD as a POLLABLE source. IEN stays 0, so this latches status without vectoring.
                lda     #$08
                sta     $FF92

* ═══════════════════════════════════════════════════════════════════════════════════════════
* THE LOOP. Per frame: wait for the vertical border, assert the TOP state, burn s01_dly, assert
* the BOTTOM state. ★★★★ The boundary's position is a FUNCTION OF s01_dly, which the host pokes
* and sweeps -- so the question is not "is there a band in the right place" but "does the boundary
* MOVE with the delay", which is a much harder thing for an accident to satisfy.
* ★★ One inner iteration is `leax -1,x` + `bne` = 8 CPU cycles. A 60 Hz frame is ~29,830 cycles at
* 1.79 MHz, of which the vertical blank is ~8,000 and the 192 active lines ~21,800, so the useful
* sweep is roughly s01_dly = 0 .. 3,700.
* ═══════════════════════════════════════════════════════════════════════════════════════════
s01_loop:
s01_vb:
                lda     $FF92                   ; read = status + ack
                bita    #$08                    ; VBORD?
                beq     s01_vb

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
                sta     $FFB1
                bra     s01_wait
s01_top_hres:
                lda     s01_vrest               ; ★ host-poked, so the 16-colour pair $1E/$16 can
                sta     $FF99                   ;   be tried without reassembling

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
                sta     $FFB1
                bra     s01_tick
s01_bot_hres:
                lda     s01_vresb               ; ★★★★★ THE THING UNDER TEST
                sta     $FF99

* ---- liveness, read by the host ----
s01_tick:
                inc     s01_frames+1
                bne     s01_loop
                inc     s01_frames
                bra     s01_loop

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
s01_col2:       fcb     $12             ; palette index 2
s01_col3:       fcb     $3F             ; palette index 3 -- the stripe's bright half
s01_fillm:      fcb     0               ; 0 = constant s01_fillb, 1 = row N filled with N
s01_fillb:      fcb     $55             ; the constant: $55 = flat index 1, $0F = a 4-pixel stripe
s01_voff:       fdb     S01_VOFF        ; ★ $FF9D/$FF9E -- physical address >> 3; host-poked and swept
s01_dly:        fdb     0               ; delay iterations after VBORD, 8 CPU cycles each
s01_frames:     fdb     0               ; ★ incremented once per frame by the guest

                end     entry
