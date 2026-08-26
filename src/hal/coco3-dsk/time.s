* src/hal/coco3-dsk/time.s
*
* HAL Time subsystem — minimal-functional stubs for P2.1.
*
* Purpose:
*   HAL Time subsystem — real GIME VBL interrupt implementation (R-vbl).
*   Provides a 16-bit frame counter (DP $10/$11) backed by the VBL IRQ
*   handler in irq_vbl.s. HAL_time_vbl_wait blocks on real VBL when IRQ
*   is unmasked; falls back to synthetic increment when masked (N3=β).
*
*   [ref: docs/project/interrupt-handling.md §10 — per-driver opt-in sequence]
*   [ref: docs/project/open-questions.md Q001 — design decisions]
*
* HAL contract reference: src/hal.inc (HAL_time_* definitions)
*   [ref: hal.inc HAL_time_init, HAL_time_vbl_wait,
*          HAL_time_frame_count, HAL_time_delay]
*
* DP layout (HAL scratch $00-$1F per conventions.md §2):
*   $10    hal_frame_hi  — frame counter high byte (16-bit, BE)
*   $11    hal_frame_lo  — frame counter low byte
*   [ref: conventions.md §2 — DP $00-$1F HAL scratch (reserved)]
*
* Calling convention:
*   [ref: conventions.md §3 — Args: A,B,D; Returns: D; CC.C error/success]
*   All functions return CC.C clear on success (no error paths in stubs).
* ---------------------------------------------------------------

        ifdef   OBJTARGET
        * setdp is NOT permitted for the object target — the fourth
        * object-incompatible directive class (P2.4; the recon found three).
        * The HAL uses explicit `<` direct-mode operands, so omitting the
        * declaration changes nothing it relies on.
        else
        setdp   0
        endc
        
        ifdef   OBJTARGET
        * Object/linked build (POP, P2.4). Guard OFF = the absolute build
        * (karateka today): not one byte of this file changes.
        section code
        export  HAL_time_init
        export  HAL_time_vbl_wait
        export  HAL_time_frame_count
        export  HAL_time_delay
        endc

* HAL-private DP locations — declared in src/engine/globals.s (P2.3a.3)
* hal_frame_hi equ $10  / hal_frame_lo equ $11
* [ref: src/engine/globals.s — canonical DP home]

* ---------------------------------------------------------------
* HAL_time_init  [extended R-vbl]
*
* Zero the frame counter; install real IRQ handler at $010C;
* configure GIME for VBL -> IRQ. Does NOT unmask CPU IRQ.
* Caller must call andcc #$EF to opt in to real-VBL behavior.
*
* ORIGIN: no Apple II equivalent (Apple II uses ROM-managed timing)
*
* Init order: 2 (after HAL_sys_init; before HAL_gfx_init).
*   HAL_sys_init writes $FF90=$4C (IEN=0). This function writes
*   $FF90=$6C (IEN=1). MC3=1 and MMUEN=1 are preserved.
*   Source/FIRQ enables written BEFORE enabling IEN (step 3 before
*   step 4) to avoid IRQ assertion from stale boot state.
*
* [ref: hal.inc HAL_time_init — contract]
* [ref: docs/project/interrupt-handling.md §10.1 — five-step sequence]
* [ref: docs/project/interrupt-handling.md §8.1 — enabling sequence]
* Clobbers: A, X, CC
* ---------------------------------------------------------------
HAL_time_init:
* Step 1: Zero the frame counter.
        clr     <hal_frame_hi           ; frame counter hi = 0
        clr     <hal_frame_lo           ; frame counter lo = 0

* Step 2: Patch $010C dispatch slot with JMP to real VBL handler.
* hal_vbl_handler defined in src/hal/coco3-dsk/irq_vbl.s.
* [ref: docs/project/interrupt-handling.md §4 — install procedure]
        lda     #$7E                    ; JMP opcode
        sta     $010C                   ; overwrite RTI stub at irq_handler slot
        ldx     #hal_vbl_handler        ; handler address (irq_vbl.s)
        stx     $010D                   ; write hi/lo address bytes

* Step 3: Configure GIME source enables BEFORE enabling IEN globally.
* Writing $FF92/$FF93 while IEN=0 prevents IRQ assertion from stale
* boot-state pending flags during the write sequence.
* [ref: docs/project/interrupt-handling.md §8.1 steps 2-3 / §8.3]
        clra
        sta     $FF93                   ; FIRQENR = 0: no FIRQ sources
        lda     #$08                    ; VBORD bit (bit 3) only
        sta     $FF92                   ; IRQENR: enable VBL -> IRQ only

* Step 4: Enable GIME IRQ globally (IEN bit in $FF90).
* Done AFTER source enables to avoid asserting IRQ on stale state.
* $4C -> $6C: set bit 5 (IEN=1); all other bits preserved.
* [ref: docs/ground-truth/SockmasterGime.md — $FF90 Bit 5 IEN]
        lda     #$6C
        sta     $FF90                   ; INIT0: IEN=1 added; MC3/MMUEN/COCO preserved

* Step 5: Return CC.C clear. CC.I intentionally preserved.
* andcc #$FE clears CC.C (bit 0) ONLY. CC.I (bit 4) is NOT cleared.
* INTENTIONALLY preserves CC.I per E1.c invariant (HAL init does not
* change caller's mask state). Do not broaden this mask.
* [ref: docs/project/interrupt-handling.md §10.1 — step 5]
* [ref: docs/project/open-questions.md Q001 EXTRA-1 — E1.c decision]
        andcc   #$FE                    ; CC.C clear = success; CC.I unchanged
        rts

* ---------------------------------------------------------------
* HAL_time_vbl_wait  [real VBL gate — R-vbl]
*
* Block until next vertical blanking interval.
* N3=β: if CC.I=1 (IRQ masked), fall back to synthetic one-frame
*   increment (backward compatibility for masked callers).
*
* Contract change (R-vbl): A argument dropped. Callers that loaded
*   A=1 before calling (timer_framesync.s lda #1 / jsr) are NOT
*   modified; the lda #1 is harmless dead code post-R-vbl.
*   [ref: docs/project/open-questions.md Q001 — N3=β; Q001.4/4.c callers]
*
* ORIGIN: karateka_dissasembly_claude src/kernel.s $07D7 (routine_07d7)
*         Apple II spins on RDVBL ($C019); replaced entirely by HAL.
*         [ref: kernel.s routine_07d7 — lda ROM_VERSION; lda RDVBL; bmi spin]
*
* [ref: hal.inc HAL_time_vbl_wait — contract (no args)]
* [ref: docs/project/interrupt-handling.md §10.2 — opt-in sequence]
* Clobbers: A, B, CC
* ---------------------------------------------------------------
HAL_time_vbl_wait:
        tfr     cc,a                    ; A = CC register value
        bita    #$10                    ; test CC.I (bit 4): IRQ masked?
        bne     hal_vbl_synthetic       ; CC.I=1: masked path (N3=β fallback)

* Unmasked path: spin until frame counter lo advances.
* hal_vbl_handler (irq_vbl.s) increments hal_frame_lo on each VBL IRQ.
        ldb     <hal_frame_lo           ; B = current lo byte (snapshot)
hal_vbl_spin:
        cmpb    <hal_frame_lo           ; counter changed?
        beq     hal_vbl_spin            ; no: keep spinning
        andcc   #$FE                    ; CC.C clear = success
        rts

* Masked path (N3=β): synthetic one-frame increment.
* Matches prior FRAME-COUNTER STUB behavior for A=1 masked callers.
* [ref: docs/project/open-questions.md Q001 N3=β decision]
hal_vbl_synthetic:
        inc     <hal_frame_lo           ; synthetic increment lo byte
        bne     hal_vbl_syn_done        ; no wrap: done
        inc     <hal_frame_hi           ; wrap: carry to hi byte
hal_vbl_syn_done:
        andcc   #$FE                    ; CC.C clear = success
        rts

* ---------------------------------------------------------------
* HAL_time_frame_count  [race fix — R-vbl]
*
* Return current 16-bit frame counter. Masks IRQ during the two-
* instruction read to prevent torn values from a handler firing
* between the two loads. Saves/restores caller's CC to preserve
* their mask state exactly.
*
* [ref: docs/project/interrupt-handling.md §10.4 — race fix, Option A]
* [ref: docs/project/open-questions.md Q001 EXTRA-2]
* [ref: hal.inc HAL_time_frame_count — Args: none; Returns: D=frame count]
* Clobbers: A, B (D), CC (except caller's mask bits via pshs/puls)
* Overhead: ~14 cycles (negligible; not called in inner loops)
* ---------------------------------------------------------------
HAL_time_frame_count:
        pshs    cc                      ; save caller's CC (preserves mask state)
        orcc    #$10                    ; mask IRQ (CC.I=1) — no handler mid-read
        lda     <hal_frame_hi           ; D hi = frame counter high byte
        ldb     <hal_frame_lo           ; D lo = frame counter low byte (atomic pair)
        puls    cc                      ; restore caller's CC exactly
        rts                             ; D = 16-bit frame count (BE)

* ---------------------------------------------------------------
* HAL_time_delay  [restructured — R-vbl]
*
* Wait A frames by calling HAL_time_vbl_wait A times.
* HAL_time_vbl_wait clobbers A; saved on stack per iteration.
*
* NOTE: A=0 causes 256 iterations (unsigned wraparound; preserved
*   from prior stub behavior).
*
* [ref: hal.inc HAL_time_delay — Args: A=frame count; Returns: CC.C clear]
* Clobbers: A, B, CC
* ---------------------------------------------------------------
HAL_time_delay:
hal_delay_loop:
        pshs    a                       ; save remaining frame count
        jsr     HAL_time_vbl_wait       ; wait 1 frame (real or synthetic per N3=β)
        puls    a                       ; restore remaining count
        deca                            ; decrement
        bne     hal_delay_loop          ; loop if more frames remaining
        andcc   #$FE                    ; CC.C clear = success
        rts
                
                ifdef   OBJTARGET
                endsection
                endc
