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
* ★★★★★ $FF9A (BRDR) HAS NEVER BEEN WRITTEN BY THIS SPIKE IN ANY STAGE -- it has carried whatever
* DECB left in it, and the border was never sampled, so nothing noticed. Jay saw the top and bottom
* border flickering fast.
* ★★★★ With the sampler fixed, every border row alternates black/white on a period of exactly 2
* frames, IDENTICALLY whether the guest alternates $FF9A by construction or never touches it. So
* the rendered border is not following $FF9A, and the next question is whether it follows it AT ALL.
* ★★★ This writes it ONCE to a host-poked value, gated on a flag so the unwritten case stays
* reachable as the control. A distinctive mid-palette value is neither of the two colours observed,
* so "the border became the value I asked for" and "the border stopped alternating" are separable.
                lda     s01_bset
                beq     s01_bset_done
                lda     s01_bcol
                sta     $FF9A
s01_bset_done:
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ★ Enable VBORD as a POLLABLE source. IEN stays 0, so this latches status without vectoring.
                lda     #$08
                sta     $FF92

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ S-05 §4A: ROUTE AN INTERRUPT TO FIRQ, WITH BOTH UNKNOWNS HOST-POKED SO THEY ARE MEASURED.
*
* ★★★★★ TWO THINGS THIS SPIKE CANNOT LOOK UP. §1.2 says to take the register bits from Sock's
* reference, and **docs/ground-truth/ holds only a .gitkeep in this working copy** -- the GIME manual
* and Sock's page are not here [§2.2], so neither the HBORD bit nor the FIRQ RAM vector can be cited.
* ★★★★ The tree gives the ADDRESSES only: `$FF93` is FIRQENR [hal.inc:91] and `$FF92`'s bit 3 is
* VBORD [hal.inc:90, irq_vbl.s:77]. **The bit number for HBORD and the vector slot are unknown.**
*
* ★★★★★ SO BOTH ARE SWEPT RATHER THAN ASSUMED, which is what §4A asks for anyway -- "report how
* firing was confirmed, not that it was assumed". s01_firqbit selects the enable bit and s01_fvec the
* RAM vector slot; the host tries combinations and reads s01_fcount back. **A handler that never runs
* looks exactly like one that does not help**, so the counter is the whole point.
* ★★★ Read from the machine at the OK prompt: $0100-$0105 are RTI stubs, **$0106-$0108 is 00 00 00 --
* uninitialised**, and $0109/$010C/$010F hold JMPs into ROM. An unused vector is what FIRQ looks like
* on a machine that never enables it, so $0106 is the first candidate -- and writing a JMP there also
* makes a slot that would otherwise jump to $0000 safe.
* ★★ Nothing is enabled unless the host asks: s01_firqon = 0 leaves the machine exactly as S-04 had it.
                lda     s01_firqon
                beq     s01_no_firq
                lda     #$7E                    ; JMP
                ldx     s01_fvec
                sta     ,x
                ldd     #s01_firq
                std     1,x                     ; the slot now points at our handler
                lda     s01_firqbit
                sta     $FF93                   ; enable the candidate source on FIRQ
                lda     #$5C                    ; ★ $FF90 with FEN=1; $4C with bit 4 set, nothing else
                sta     $FF90
                andcc   #$BF                    ; ★ unmask F -- the ORCC at entry masked both
s01_no_firq:
* ═══════════════════════════════════════════════════════════════════════════════════════════

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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE ROW NUMBERING STARTS AT A HOST-POKED VALUE, AND THAT IS S-04's WHOLE TEST [§4A(1)].
* The repeat's period is ~16 rows, and at 4 bpp 16 is exactly the period of a byte's HIGH NIBBLE --
* so the hypothesis is that the SIGNATURE collides at a high-nibble boundary and reports a repeat the
* display does not have.
* ★★★★★ **Shifting the numbering separates the two possibilities with one poke.** If the repeats are
* an artefact of the byte VALUE they move with s01_rowbase; if they are tied to a screen POSITION they
* stay put. ★★★ No new fill mode, no new decode, and nothing that could alias in a new way -- which
* §3(2) warns against, since the signature is the suspect and must not be used to test itself.
                ldb     s01_rowbase             ; ★ B = the FIRST row's value, normally 0
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
* ★★★★★ THE FIRQ HANDLER. Phase 1 counts and acks; nothing else, because §4A says confirm it FIRES
* before asking whether it helps.
*
* ★★★★★ FIRQ STACKS ONLY PC AND CC -- **A, B, X, Y and U are NOT saved** -- which is exactly what makes
* it cheap (§1.2: ~19 cycles of IRQ state-stacking avoided) and exactly what makes it dangerous. This
* handler touches A, so it pushes A. **A handler that clobbered A would corrupt whatever the main loop
* was doing at a random instruction**, and the symptom would be indistinguishable from "FIRQ breaks the
* split".
* ★★★ `inc` on memory does not use A, and CC is restored by RTI, so `pshs a` / `puls a` is sufficient
* and is also the cheapest correct thing.
* ★★ Reading $FF93 is the candidate ack, by symmetry with $FF92 acking IRQ [irq_vbl.s:75]. **If it is
* wrong the handler re-enters forever and the main loop stops**, which s01_frames reports -- so a wrong
* ack is a loud failure, not a quiet one.
* ★★★★★ S-05 PHASE 2: THE HANDLER NOW *PLACES* THE BOUNDARIES. This is §1.2's actual experiment, and
* the counting version was not it -- a handler that merely coexists with busy-waits injects cycles into
* every delay and made stability 690x worse. **Here the delays are GONE.**
*
* ★★★★ ONE COMPARE PER INVOCATION, because the handler runs ~145 times a frame and pays for itself in
* every one of them. s01_hptr walks a table of (scanline, vres) pairs; only the NEXT pair is ever
* compared, and a 0 terminator ends the frame's work. **Three boundaries cost three writes and ~145
* cheap compares, not 145 three-way tests.**
* ★★★ The counter is 8-bit and wraps at 256, which is safe because the frame is ~262 lines and every
* threshold is above 6: after the wrap the count reaches 6, so no threshold is re-triggered.
* ★★ FIRQ stacks only PC and CC, so everything touched is pushed -- A, B and X here.
s01_firq:
                pshs    a,b,x
                inc     s01_hcount
                ldx     s01_hptr
                lda     ,x                      ; the next scanline to act on
                beq     s01_fq_ack              ; 0 = nothing left this frame
                cmpa    s01_hcount
                bne     s01_fq_ack
* ★★★★★ REACHED IT. The mode is written as a PAIR -- $FF98 with BP set and $FF99 from the table -- the
* same form gfx.s and the init use, so the write is identical in kind to the one the busy-wait version
* made. **Only WHEN it happens has changed, and that is the whole experiment.**
                ldb     1,x
                lda     #$80
                std     $FF98
                leax    2,x
                stx     s01_hptr
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PAIR THE MODE WRITE WITH A PALETTE WRITE, WHICH IS WHAT THE CYCLE-COUNTED PATH DOES AND
* THIS HANDLER DID NOT. Every `std $FF98` in the busy-wait arm is followed by `lbsr s01_palwr`
* (see the note at the stage-0 loop: "the refresh IS driven by a changing palette value"). The
* handler wrote the mode ALONE, and with the border scaffold removed four different handler lines
* -- 60, 88, 120, 150 -- rendered IDENTICALLY: no boundary at all.
* ★★★★★ So the earlier "the FIRQ-placed boundary is 100% stable" was measured while a border flip
* happened to be supplying the changing value, from the wrong place and corrupting the frame. The
* boundary needs the change AT THE BOUNDARY, not once per frame at VBORD.
* ★★★★ The value alternates so MAME's update_value() sees a change, and it goes to s01_palreg --
* index 1 by default, which a $0F fill never selects, so it cannot alter a pixel. This is the
* difference from the $FF9A flip that inverted every row.
                inc     s01_hwrite      ; ★★★★★ did this write EXECUTE? Four handler lines rendered
                                        ; identically and I inferred the mechanism twice without ever
                                        ; counting the write. §2W: measure it.
                lda     s01_hflip
                eora    #$3F
                sta     s01_hflip
                ldx     #$FF00
                ldb     s01_palreg
                sta     b,x
* ═══════════════════════════════════════════════════════════════════════════════════════════
s01_fq_ack:
                inc     s01_fcount+1
                bne     s01_fq_ack2
                inc     s01_fcount
s01_fq_ack2:
                lda     $FF93                   ; ack the GIME FIRQ source
                puls    a,b,x
                rti                             ; ★ RTI, not `puls pc` -- FIRQ's return is an RTI
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
                lbsr    s01_do_fill     ; ★ long: the handler's paired palette write moved this out of range
s01_norefill:

* ★★★ VOFFSET IS RE-WRITTEN EVERY FRAME, so the host can sweep it on a running guest. Without this
* the register keeps its init value and poking s01_voff would change nothing -- a sweep that moves a
* variable the hardware never reads again, which is the shape of a diagnostic that cannot fail [§2W].
                ldd     s01_voff
                std     $FF9D

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ MODE 3 -- FIRQ-PLACED BOUNDARIES. **There is no delay loop here at all.** The main loop's
* whole job per frame is: reset the raster program, assert the wide mode for the top of the screen, and
* change one register value so MAME keeps the bitmap current.
* ★★★★ THE BORDER IS WHAT GETS FLIPPED, not a palette index -- S-04 established that a changing palette
* value is required and that pointing the flip at an index displayed in 16-colour mode is what caused
* S-03's false finding. `$FF9A` is recorded per scanline by MAME and is outside the decoded area.
* ★★★ `eora #$3F` alternates it between $00 and $3F, so the value genuinely CHANGES every frame.
* ★★ Everything else the loop used to do -- three delays, three paired writes, three palette writes --
* is now the handler's, and the guest spends the frame doing nothing. **That is the point: the boundary
* is placed by the raster, not by a cycle count.**
                lda     s01_mode
                cmpa    #3
                lbne    s01_not_m3
                clr     s01_hcount
                ldx     #s01_htab
                stx     s01_hptr
                lda     #$80
                ldb     s01_vrest
                std     $FF98                   ; wide, for the top of the frame
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THIS WAS `eora #$3F` -- AN IMMEDIATE. s01_bxor existed as a data byte, the host poked it,
* the readback confirmed it arrived as $00, and THE CODE NEVER READ IT. So -BXor 0 disabled
* nothing, and every mode-3 arm ever run has flipped the border between $00 and $3F -- black and
* white -- once per frame. That is the flicker Jay saw, it is this scaffold, and it lives in the
* mode-3 block alone, which is why "the flashing didn't start until you started the new firq
* process" was exactly right: mode 3 IS the FIRQ arm.
* ★★★★★ AND IT IS WHY THREE BORDER INSTRUMENTS LOOKED INSENSITIVE TO EVERYTHING. They were: the
* flip ran in all of them, so no arm differed. The instruments were reporting a real alternation
* the whole time and the arm labels were the lie.
* ★★★★ Sixth instance of the row this spike keeps feeding, and the worst of them, because the
* readback of the PARAMETER was taken as evidence about the BEHAVIOUR. §2W: a control must be
* shown to change the outcome, not merely to arrive.
* ★★★★★ THE FLIP TARGET IS NOW s01_palreg, NOT $FF9A. Four handler lines -- 60, 88, 120, 150 --
* rendered IDENTICALLY with the flip off: no mid-frame boundary at all. So the flip was not
* incidental to the measurement, it was what kept MAME's per-scanline record refreshed, and the
* boundary result was entangled with its own scaffold.
* ★★★★ $FF9A was the wrong thing to flip: alternating the border inverted EVERY ROW of the frame,
* so it corrupted the active area it was supposed to be keeping current. A palette entry the fill
* never selects keeps the record changing and cannot alter a pixel: at 16 colours a $0F fill uses
* indices 0 and 15 ONLY, so index 1 ($FFB1, s01_palreg's default) is invisible by construction.
* ★★★ S-03's lesson applies in the other direction here -- there, a flip target collided with a
* displayed index and produced a false row repeat. The check is the same one: the flipped register
* must not be a colour the picture can show.
                lda     s01_bxor
                beq     s01_bfix                ; 0 = no flip at all, and now it means it
                lda     s01_bflip
                eora    s01_bxor
                sta     s01_bflip
                ldx     #$FF00
                ldb     s01_palreg
                sta     b,x                     ; ★ keeps MAME's record current, off the picture
                lbra    s01_tick
* ★★★ With the flip off, write the border every frame with the SAME value if asked. MAME's
* update_value() acts only on a CHANGE, so an init-only write is the case it ignores -- the same
* mechanism that forced a per-frame scaffold in S-01..S-04, and the reason the init write showed
* no red even though the parameter had arrived.
s01_bfix:
                lda     s01_bset
                beq     s01_no_bfix
                lda     s01_bcol
                sta     $FF9A
s01_no_bfix:
                lbra    s01_tick
* ═══════════════════════════════════════════════════════════════════════════════════════════
s01_not_m3:
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ---- the TOP state ----
                lda     s01_mode
                cmpa    #2
                beq     s01_tick                ; ★ static reference: flip nothing, just tick
                tsta                            ; ★ NOT `bne` off the cmpa -- mode 0 leaves Z clear
                bne     s01_top_hres            ;   there and would have taken the HRES branch
                lda     s01_colA
                lbsr    s01_palwr
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
                lbsr    s01_palwr

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
                lbsr    s01_palwr
                bra     s01_tick
s01_bot_hres:
                lda     #$80                    ; ★★★★★ THE THING UNDER TEST, as a paired write
                ldb     s01_vresb
                std     $FF98
                lda     s01_colB                ; ★ the paired palette write -- see the note above
                lbsr    s01_palwr
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
                lbsr    s01_palwr
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
s01_rowbase:    fcb     0               ; ★ S-04 §4A(1): the value the first source row is filled with
s01_firqon:     fcb     0               ; ★ S-05: 0 = leave the machine as S-04 had it
s01_firqbit:    fcb     $10             ; ★ the $FF93 bit to enable -- SWEPT, not assumed
s01_fvec:       fdb     $0106           ; ★ the RAM vector slot -- SWEPT; $0106 is uninitialised
s01_fcount:     fdb     0               ; ★ handler invocations; the host reads this to confirm firing
* ★★★★★ THE RASTER PROGRAM: (scanline, $FF99) pairs, 0-terminated, host-poked. Mode 3's handler walks
* it one entry at a time. ★★★ Three pairs plus a terminator is the message-box case -- narrow, wide
* again for the box's rows, narrow below it -- and the table is the only thing that decides where.
s01_htab:       fcb     0,0,0,0,0,0,0
s01_hptr:       fdb     0               ; -> the next pair the handler will act on
s01_hcount:     fcb     0               ; scanlines since VBORD; 8-bit, wraps harmlessly (see s01_firq)
s01_bflip:      fcb     0               ; the border value, alternated each frame
s01_hflip:      fcb     0               ; ★★★★ the handler's paired palette value, alternated per write
s01_hwrite:     fcb     0               ; ★★★★★ times the handler's mode write actually executed
s01_bxor:       fcb     $3F             ; ★ the flip mask; 0 = no border flip at all (see mode 3)
* ★★★ Sixteen DISTINCT CoCo3 palette bytes, so no two indices can render as the same colour. That is
* a requirement of the row-signature measurement, not decoration -- see the note at the palette init.
* ★★★★★ AND "16 DISTINCT BYTES" IS NOT THE REQUIREMENT -- "16 DISTINCT RENDERED COLOURS" IS [S-04].
* S-03 set sixteen distinct palette bytes and called the collision fixed. **$3F and $07 both render as
* FFFFFF**, so two source rows differing only in that nibble were indistinguishable and read as a
* repeated row -- which is the entire "16-colour row repeat" this spike existed to explain.
* ★★★★ `$07` is replaced by `$3C`, and the driver now DUMPS THE SIXTEEN RENDERED COLOURS AND CHECKS
* FOR DUPLICATES on every row-map run, so the property that is actually needed is the one verified.
* ★★★ **Distinct inputs are not distinct outputs**, and the fix for the first collision addressed the
* cause I had identified rather than the property I needed.
* ★★★ MAME's coco3 RGB mapping, DEDUCED from the rendered dump rather than assumed: $09 renders pure
* blue at maximum and $12 pure green, which fits R = bit5*2 + bit2, G = bit4*2 + bit1, B = bit3*2 + bit0.
* ★★ Under it the eight "maximum" primaries are $00,$09,$12,$1B,$24,$2D,$36,$3F and they are confirmed
* distinct in the dump; `$01` gives (0,0,1) which collides with nothing.
s01_pal16:      fcb     $00,$09,$12,$1B,$24,$2D,$36,$3F
                fcb     $01,$0E,$15,$1C,$23,$2A,$31,$38
s01_bset:       fcb     0               ; ★★★★ 1 = write $FF9A once at init; 0 = leave it, the control
s01_bcol:       fcb     $24             ; ★★★ the border value -- $24 is pure red under the mapping above,
                                        ; deliberately neither of the two colours the flicker shows
s01_voff:       fdb     S01_VOFF        ; ★ $FF9D/$FF9E -- physical address >> 3; host-poked and swept
s01_dly:        fdb     0               ; delay iterations after VBORD, 8 CPU cycles each
s01_dly2:       fdb     0               ; ★ 0 = one split. Otherwise: back to WIDE after this delay
s01_dly3:       fdb     0               ; ★ and narrow again after this one -- three boundaries
s01_frames:     fdb     0               ; ★ incremented once per frame by the guest

                end     entry
