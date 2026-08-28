* src/hal/coco3-dsk/sys.s
*
* HAL System subsystem — P2.3a.0 deliverable.
*
* Purpose:
*   Handler dispatch block at $0100-$0111 (static RTI stubs;
*     loaded into RAM by DECB; CoCo3 $FExx chain routes here).
*   HAL_sys_init: CoCo3 bare-metal transition (mask + $FF90 + MMU).
*   HAL_sys_panic: Unrecoverable error handler (infinite loop).
*
* ORIGIN: HAL_sys_init is new karateka-coco3 work. Not ported from
*   GFXMODE3.ASM. Designed for CoCo3 bare-metal transition per P2.3a.0.
*
* CoCo3 INTERRUPT DISPATCH (three-level; per Sockmaster-GIME §1):
*   CPU reads from $FFxx (ROM — unchangeable).
*   $FFxx ROM values contain $FExx addresses (BASIC-installed secondary
*     vectors). After $FF90=$4C is written, MC3=1 locks $FExx as
*     "constant" — they cannot be overwritten.
*   $FExx values contain JMPs/LBRAs to $01xx (the dispatch block below).
*   This binary provides RTI stubs at $0100-$010F so that if an
*     interrupt fires despite ORCC #$50 masking, the CPU safely returns.
*
*   HAL_sys_init does NOT write vectors at runtime. The dispatch block
*   is statically allocated at .org $0100 in this file and loaded into
*   RAM by DECB. BASIC's $FExx routing remains in effect (locked by
*   MC3=1 in $FF90=$4C).
*
*   Per Sockmaster-GIME §1 (docs/ground-truth/SockmasterGime.md):
*     SWI3 → $FFF2(ROM) → $FEEE → $0100
*     SWI2 → $FFF4(ROM) → $FEF1 → $0103
*     SWI  → $FFFA(ROM) → $FEFA → $0106
*     NMI  → $FFFC(ROM) → $FEFD → $0109
*     IRQ  → $FFF8(ROM) → $FEF7 → $010C
*     FIRQ → $FFF6(ROM) → $FEF4 → $010F
*
*   [ref: docs/ground-truth/SockmasterGime.md §1 — Interrupt Vectors table]
*   [ref: 6502-6809-conversion-patterns/shared/G-methodology/
*         G.3-coco3-platform-assumptions.md — G.3.3 exemplar]
*
* INTERRUPT MASK POLICY (P2.3a.0 era):
*   Three-layer protection:
*     Layer 1: Test driver global ORCC #$50 at entry
*     Layer 2: HAL_sys_init internal ORCC #$50 (belt-and-suspenders)
*     Layer 3: Dispatch block RTI stubs (safe no-op if interrupt fires)
*   This is acceptable while no interrupt-driven behavior exists.
*   Migration required when real handlers land (P3.1 VBL at minimum).
*   [ref: docs/project/conventions.md — "Interrupt mask policy" section]
*   [ref: docs/project/open-questions.md Q001 — migration plan]
*   [ref: docs/project/interrupt-handling.md — full dispatch documentation]
*
* PRODUCTION BUILD NOTE:
*   The dispatch block at .org $0100 and the HAL code (HAL_sys_init,
*   HAL_sys_panic) are in separate address regions ($0100 and HAL
*   $2000-$3FFF respectively). A production linker script will place
*   the two sections correctly. For test drivers (lwasm --decb single-
*   file builds), both sections appear in the binary via multiple .org
*   directives. This file is the authoritative source for both; the
*   production build wiring is deferred to post-P2.
*
* Reference citations:
*   [ref: docs/ground-truth/SockmasterGime.md §1] — three-level interrupt dispatch
*   [ref: docs/project/memory-map.md §2] — dispatch block within stack region
*   [ref: docs/project/memory-map.md §3.2] — MMU task 0 page values $38-$3F
*   [ref: hal.inc HAL_sys_init — contract]
*   [ref: docs/project/conventions.md §2 — DP $13 sys_init_cc_mask]
*   [ref: docs/project/conventions.md — interrupt mask policy section]
*   [ref: KCOCO3_INIT0_COCO3 = $4C in hal.inc]
*
* DP allocations (HAL scratch band $00-$1F):
*   $12  gfx_initialized  — set by HAL_gfx_init (gfx.s)
*   $13  sys_init_cc_mask — CC state post-HAL_sys_init (test diagnostic)
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
        export  HAL_sys_init
        export  HAL_sys_panic
        endc

* sys_init_cc_mask equ $13  — declared in src/engine/globals.s (P2.3a.3)

* NOTE: Handler dispatch block ($0100-$0111) has been moved to
*   src/engine/boot.s for the production build (P2.3a.3).
*   Test drivers that need the dispatch block maintain their own
*   inline copies (self-contained build pattern).
*   [ref: src/engine/boot.s §Segment 1]
*   [ref: docs/project/interrupt-handling.md §4 — dispatch block design]

* ---------------------------------------------------------------
* HAL_sys_init
*
* CoCo3 bare-metal transition: mask interrupts, enable all-RAM mode,
* program MMU task 0 to P1.6 layout.
*
* ORIGIN: New karateka-coco3 work (P2.3a.0). Not from GFXMODE3.ASM.
*
* Args:    none
* Returns: CC.C clear; CC.I=1, CC.F=1 (interrupts remain MASKED)
* Preserves: U, Y
* Clobbers: A, X, CC
* Precondition: BASIC boot complete; DP=0; stack initialized
* Postcondition:
*   - Interrupts masked (ORCC #$50 applied)
*   - $FF90=$4C: COCO=0 (CoCo3 mode), MMUEN=1 (MMU on), IEN=0, FEN=0,
*       MC3=1 ($FExx DRAM held constant), MC2=1 (standard SCS), MC1:MC0=00.
*
*     CORRECTED P2.9 -- this postcondition previously read "all-RAM ... ROM
*     unmapped from $8000-$FEFF". THAT WAS WRONG. $FF90's MC1:MC0 field selects
*     ROM MAPPING, and it has no all-RAM setting at all:
*         MC1 MC0   ROM mapping
*          0   x    16K internal, 16K external
*          1   0    32K internal
*          1   1    32K external (except vectors)
*     $4C is MC1=0, MC0=0 -- "16K internal, 16K external". Writing it does not
*     unmap anything. The CoCo3's upper-memory RAM/ROM control is the SAM pair
*     $FFDE/$FFDF, which THIS ROUTINE NEVER WRITES; HAL_gfx_init and
*     HAL_gfx_set_mode write $FFDF as their final step.
*     [ref: docs/ground-truth/GIME_Reference_Manual.pdf section 3 -- INIT0]
*     [ref: docs/ground-truth/SockmasterGime.md:24-38 -- identical table]
*     Measured alongside: $0200/$3000/$6000/$8000/$9000/$A000/$C000/$D000/$D7FF
*     are all writable RAM at the DECB prompt, before this routine has ever run.
*   - FFA0-FFA7=$38-$3F: MMU task 0 mapped to P1.6 layout
*       ($0000-$1FFF=physical $70000, ..., $C000-$FFFF=physical $7C000+)
*   - PIA0 and PIA1 IRQ enable bits cleared: PIA will not assert IRQ.
*       Future phases that require keyboard input (R-p24+) must
*       re-enable PIA IRQ selectively at that time.
*   - HAL_sys_init does NOT install interrupt vectors. Dispatch block
*       RTI stubs at $0100-$010F are loaded by DECB. BASIC's $FExx
*       secondary vectors remain in effect (MC3=1 locks them).
*
* Interrupt masking rationale:
*   $FF90=$4C unmaps ROM from $8000-$FEFF, invalidating ROM interrupt
*   handlers. Masking before the write ensures no interrupt fires
*   during the transition window when vectors point to invalidated ROM.
*   [ref: docs/project/interrupt-handling.md §3]
*   [ref: docs/project/conventions.md — interrupt mask policy]
*
* $FF90=$4C value provenance:
*   [ref: refs/GFXMODE3.ASM line 53-54 — LDA #$4C / STA $FF90]
*   [ref: KCOCO3_INIT0_COCO3 in hal.inc]
*   Bit semantics: [ref: docs/ground-truth/SockmasterGime.md — $FF90]
*     COCO=0, MMUEN=1, MC3=1 (FExx constant), MC2=1 (standard SCS)
*
* MMU slot values:
*   [ref: docs/project/memory-map.md §3.2] — P1.6 task 0 page assignments
*   [ref: docs/ground-truth/SockmasterGime.md] — MMU task register documentation
*
* [ref: hal.inc HAL_sys_init — contract]
* ---------------------------------------------------------------
HAL_sys_init:
        pshs    u,y                     ; preserve U, Y per contract

* Step 1: Mask interrupts immediately.
* ROM interrupt handlers will be invalidated by $FF90 write in step 2.
* Must not take an interrupt during transition. Belt-and-suspenders:
* caller (test driver) should also mask before calling HAL_sys_init.
* [ref: docs/project/conventions.md — interrupt mask policy]
        orcc    #$50                    ; set CC.I (IRQ mask) and CC.F (FIRQ mask)

* Step 2: Disable PIA0 and PIA1 IRQ enables.
*
* ROOT CAUSE FIX (R-boot, 2026-05-21):
*   CoCo3 BASIC leaves PIA0's keyboard interrupt enabled. PIA0 and PIA1
*   assert the 6809 IRQ line independently of GIME's IRQENR register —
*   the PIA IRQ lines OR directly onto the CPU's IRQ pin, bypassing GIME.
*   When boot.s later executes andcc #$EF (unmask IRQ before the first
*   rendered frame), a pending PIA keyboard interrupt fires before the
*   jsr broderbund_scene at $0226 can execute. Reading $FF92 (GIME ACK)
*   in the handler does not dismiss PIA's IRQ; the CPU is trapped in an
*   infinite interrupt loop at $0226, 833,172 times per 30 seconds in
*   MAME. The jsr broderbund_scene never executed.
*
*   Fix: clear bits 0,1 of each PIA control register here, while IRQ is
*   still masked. This disables CA1/CA2 (and CB1/CB2) IRQ generation on
*   both PIAs. The PIA pins and data registers are unaffected; only the
*   IRQ assertion to the CPU is suppressed.
*
* PIA register map (always accessible; $FFxx hardware page):
*   PIA0 $FF01 = CRA: bits 0=CA1-IRQ-enable, 1=CA2-IRQ-enable
*   PIA0 $FF03 = CRB: bits 0=CB1-IRQ-enable, 1=CB2-IRQ-enable
*   PIA1 $FF21 = CRA: bits 0=CA1-IRQ-enable, 1=CA2-IRQ-enable
*   PIA1 $FF23 = CRB: bits 0=CB1-IRQ-enable, 1=CB2-IRQ-enable
*   Mask $FC = %11111100 clears bits 0,1; preserves all other CR state.
*
* [ref: docs/project/interrupt-handling.md — PIA IRQ bypass of GIME IRQENR]
* [ref: R-boot trace 2026-05-21 — root-cause investigation]
        lda     $FF01
        anda    #$FC
        sta     $FF01                   ; PIA0 CRA: disable CA1+CA2 IRQ
        lda     $FF03
        anda    #$FC
        sta     $FF03                   ; PIA0 CRB: disable CB1+CB2 IRQ
        lda     $FF21
        anda    #$FC
        sta     $FF21                   ; PIA1 CRA: disable CA1+CA2 IRQ
        lda     $FF23
        anda    #$FC
        sta     $FF23                   ; PIA1 CRB: disable CB1+CB2 IRQ

* Step 3: Enable all-RAM mode + MMU.
* MC3=1 locks $FExx secondary vectors; they retain BASIC's routing to
* $01xx dispatch block. MC2=1 = standard SCS. MMUEN=1 enables MMU.
* COCO=0 switches from SAM-mode to GIME-mode address translation.
* [ref: docs/ground-truth/SockmasterGime.md — $FF90 bit definitions]
* [ref: refs/GFXMODE3.ASM line 53-54 — empirical provenance]
        lda     #$4C                    ; == KCOCO3_INIT0_ACTIVATE (hal.inc)
                                        ; literal, not the symbol: hal.inc uses `import`
                                        ; and cannot be included in a --decb build.
        sta     $FF90                   ; INIT0: COCO=0,MMUEN=1,IEN=0,MC3=1,MC2=1

* Step 4: Program MMU task 0 slots to P1.6 physical page layout.
* Must be written AFTER $FF90=$4C (MMUEN bit enables MMU programming).
* [ref: docs/project/memory-map.md §3.2]
* [ref: docs/ground-truth/SockmasterGime.md — MMU task register layout]
        lda     #$38
        sta     $FFA0                   ; $0000-$1FFF → physical $70000
        lda     #$39
        sta     $FFA1                   ; $2000-$3FFF → physical $72000
        lda     #$3A
        sta     $FFA2                   ; $4000-$5FFF → physical $74000
        lda     #$3B
        sta     $FFA3                   ; $6000-$7FFF → physical $76000
        lda     #$3C
        sta     $FFA4                   ; $8000-$9FFF → physical $78000 (Frame A)
        lda     #$3D
        sta     $FFA5                   ; $A000-$BFFF → physical $7A000 (Frame A)
        lda     #$3E
        sta     $FFA6                   ; $C000-$DFFF → physical $7C000 (Frame B)
        lda     #$3F
        sta     $FFA7                   ; $E000-$FFFF → physical $7E000 (Frame B)

* Step 5: SAM CPU clock -- 1.7898 MHz.
*
* PROJECT-SELECTED AND GUARDED. The block is byte-identical in all three HAL
* trees (2M: a change to a shared file lands in every repo or in none); only a
* project that defines HAL_SYS_FAST_CLOCK assembles it. POP and Karateka do not,
* so their artifacts are unchanged by this addition -- 2M.3's "a guard is the
* mechanism that lets identical source assemble differently".
*
* WHY AGI NEEDS IT HERE AND THE SIBLINGS DO NOT. The 1.78 MHz write already
* existed in gfx.s, inside HAL_gfx_set_mode. POP and Karateka select a graphics
* mode during boot, so they reach fast mode before anything is timed. AGI runs
* its VM before any mode is selected, so an AGI harness that calls only
* HAL_sys_init runs at 0.894 MHz -- which is exactly what happened: T-P0-024
* calibrated the resource layer at 0.8937 MHz while the fill work measured at
* 1.7898, and the two subsystems' figures would not have composed.
*
* Same write and same provenance as gfx.s step 8:
* [ref: GFXMODE3.ASM line 36 - STA $FFD9 (A=0, 1.78 MHz clock)]
* Any write to $FFD9 sets the SAM speed bit; the value is irrelevant. `sta` is
* used rather than `clr` because `clr` extended performs a read cycle at the
* address first, and SAM control addresses respond to accesses, not just writes.
        ifdef   HAL_SYS_FAST_CLOCK
        clra
        sta     $FFD9                   ; SAM: 1.7898 MHz CPU clock
        endc

        puls    u,y                     ; restore U, Y per contract
        andcc   #$FE                    ; CC.C clear = success
                                        ; CC.I, CC.F remain SET (interrupts masked)
        rts

* ---------------------------------------------------------------
* HAL_sys_panic
*
* Unrecoverable error handler. Halts the CPU (infinite loop).
*
* Args:  X = pointer to null-terminated message (or 0)
* Returns: does not return
*
* [ref: hal.inc HAL_sys_panic — "Unrecoverable error handler."]
* [ref: docs/project/hal.md §5.7]
*
* P2.x BEHAVIOR: infinite loop (bra *). MAME harness detects as
*   timeout-failure because PASS sentinel is never written.
*   [no-ref: display/serial output destination — deferred P3+]
* ---------------------------------------------------------------
HAL_sys_panic:
        bra     HAL_sys_panic           ; infinite loop — MAME timeout failure
                
                ifdef   OBJTARGET
                endsection
                endc
