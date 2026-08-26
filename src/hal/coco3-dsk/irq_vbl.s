* src/hal/coco3-dsk/irq_vbl.s
*
* HAL VBL IRQ handler — R-vbl deliverable.
*
* Purpose:
*   Real IRQ handler for GIME VBL interrupt. Installed at the
*   $010C dispatch slot by HAL_time_init. Fires on each vertical
*   blank; increments the 16-bit frame counter at DP $10/$11.
*
* ORIGIN: R-vbl; no Apple II equivalent.
*   Apple II karateka busy-polls RDVBL ($C019) in routine_07d7;
*   replaced entirely by HAL_time_vbl_wait (main context) backed
*   by this interrupt handler (interrupt context).
*
* Handler address: wherever the linker places it. HAL_time_init
*   patches $010C with JMP to this routine.
*   [ref: docs/project/interrupt-handling.md §4 — install procedure]
*   [ref: docs/project/interrupt-handling.md §9 — reference skeleton]
*
* Entry state: 6809 IRQ mechanism has stacked full machine state
*   (CC, A, B, DP, X, Y, U, PC — 12 bytes). CC.I=1 (set by CPU
*   on IRQ entry). DP=0 invariant holds; HAL scratch at $00-$1F.
*
* Calling convention: interrupt context. Restores all registers
*   via RTI. Caller-visible side effect: hal_frame_lo/hi advance.
*
* DP allocations (same as time.s):
*   $10  hal_frame_hi  — frame counter high byte
*   $11  hal_frame_lo  — frame counter low byte
*   [ref: src/engine/globals.s — canonical DP home]
*
* Reference citations:
*   [ref: docs/ground-truth/SockmasterGime.md line 67 — reading $FF92 = ack]
*   [ref: docs/project/interrupt-handling.md §8.2 — ack mechanism]
*   [ref: docs/project/interrupt-handling.md §9 — reference skeleton]
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
        endc

* hal_frame_hi/lo — declared in src/engine/globals.s (P2.3a.3).
* In production multi-file builds, globals.s defines these symbols.
* In single-file test driver builds, the driver declares them inline.
* [ref: src/engine/globals.s — canonical DP home]

* ---------------------------------------------------------------
* hal_vbl_handler
*
* VBL IRQ handler: ack GIME, check VBORD, increment frame counter.
*
* Handler runtime: ~30 cycles (budget: ~2500 cycles per VBL period
*   at 60Hz NTSC / 1.79MHz). Well within limit.
*   [ref: docs/project/interrupt-handling.md §9 — handler runtime constraint]
*
* Multi-source constraint: lda $FF92 clears ALL pending GIME IRQ
*   flags simultaneously. With only VBORD enabled ($FF92=$08), this
*   is correct. If future work enables additional GIME sources
*   (timer, HBORD, keyboard, serial, cartridge), save A and dispatch
*   on each bit before any are lost.
*   [ref: docs/project/interrupt-handling.md §9 — multi-source constraint]
* ---------------------------------------------------------------
hal_vbl_handler:
        lda     $FF92                   ; ACK: read IRQENR; clears all GIME
                                        ;   IRQ pending flags. A = source bitmap.
        bita    #$08                    ; test VBORD (bit 3): VBL fired?
        beq     hal_vbl_irq_exit        ; no: spurious or other source — exit
        inc     <hal_frame_lo           ; VBL: increment frame counter lo byte
        bne     hal_vbl_irq_exit        ;      no wrap: done
        inc     <hal_frame_hi           ;      wrap: carry to hi byte
hal_vbl_irq_exit:
        rti                             ; restore full machine state; CC.I
                                        ;   restored from stacked CC
                
                ifdef   OBJTARGET
                endsection
                endc
