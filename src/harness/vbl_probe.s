* ═══════════════════════════════════════════════════════════════════════════════════════════
* src/harness/vbl_probe.s — DOES THE VBL INTERRUPT ARRIVE AT ALL? [T-P0-064, Jay's ruling AD-138]
*
* ★★★★★ THIS IS THE POSITIVE CONTROL FOR THE CLOCK SOURCE, AND IT EXISTS BECAUSE THE FIRST
* MEASUREMENT WAS AMBIGUOUS. vbl_rate.lua ran the full VM probe and reported 7.79 Hz against
* MAME's 59.92, with handler entries (39) exactly equal to counter increments (39). Two readings
* explain that equally well:
*
*   (a) the interrupt is DELIVERED 59.92 times a second and the CPU is masked for most of them,
*       so 87% are lost — and because hal_vbl_handler ACKs by reading $FF92, a run of missed
*       VBLs collapses into a single increment; or
*   (b) the interrupt is RAISED 7.79 times a second, because the GIME is not configured the way
*       HAL_time_init is believed to configure it.
*
* ★★★★ I HAD ALREADY WRITTEN (a) INTO A REPORT DRAFT AS THE FINDING. The evidence for it was a
* CC.I sample taken in a MAME frame notifier — and a frame notifier fires at the frame boundary,
* which is WHEN THE VBL INTERRUPT IS TAKEN. The sample is phase-locked to the event it measures
* and preferentially lands inside the handler, where the 6809 sets CC.I in hardware on entry.
* **86.7% masked is exactly what that instrument would report on a perfectly healthy machine.**
* ★★★ §2W: the diagnostic could not have produced a low number, so it did not measure — it
* testified [§2W.3]. It is not quoted in any report and the grep for a masker it sent me on
* found nothing, which is the corroboration that matters: every orcc #$50 in the HAL is
* pshs cc / puls cc bracketed and none spans more than a few dozen cycles.
*
* ★★★★★ SO THIS PROBE REMOVES THE VARIABLE INSTEAD OF ARGUING ABOUT IT. It is vm_probe's
* prologue — the same HAL_sys_init, the same all-RAM write, the same HAL_time_init, the same
* andcc #$EF — and then it SPINS. No interpreter, no resource layer, no MMU remapping, nothing
* that could mask anything. Whatever rate this reports is the rate the machine delivers to a
* guest that never masks.
*
*   spin reports 59.92 Hz  →  reading (a): the machine is fine, the VM's own work loses VBLs,
*                             and the ruling needs the losses accounted for.
*   spin reports  7.79 Hz  →  reading (b): the clock source is misconfigured, the VM is
*                             blameless, and the fix is in the GIME setup.
*
* ★★ Either answer is worth the twenty lines. **An instrument shown able to give the RIGHT
* answer on a known-good case is what §2W asks for**, and the spin loop is that case.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/hal.inc"

VB_HW_STACK     equ     $0700

                org     $0700
vbl_probe_entry:
                orcc    #$50
                lds     #VB_HW_STACK
                jsr     HAL_sys_init            ; bare-metal transition + FAST MODE, as vm_probe
                sta     $FFDF                   ; SAM TY=1: $0000-$FEFF is RAM (vm_probe §ALL-RAM)

                jsr     HAL_time_init           ; installs $010C, zeroes hal_frame_hi/lo
                andcc   #$EF                    ; unmask IRQ. FIRQ stays masked, exactly as vm_probe.

* ★★★ THE SPIN. Nothing here masks, remaps, or calls the HAL. The 6809 takes an IRQ at any
* instruction boundary with CC.I clear, and every boundary in this loop qualifies.
* ★ `bra *` would be one instruction and a legitimate spin; the counter read is here so the
* GUEST is demonstrably still executing rather than halted at an address that happens to hold
* $20 $FE — the same reasoning as the arena self-test, which the guest runs itself.
vb_spin:        ldd     <hal_frame_hi           ; DP $10/$11 — the counter the handler increments
                std     vb_seen                 ; guest-visible proof the loop is live
                bra     vb_spin

vb_seen         fdb     0

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"

                end
