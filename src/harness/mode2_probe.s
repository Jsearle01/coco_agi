* src/harness/mode2_probe.s
*
* AC-6 probe: select mode 2 and publish what the HAL recorded for it.
*
* ★★ THIS DOES NOT RENDER. Dispatch §12 puts pixels in T-P0-011; the probe exists only to
* prove the DESCRIPTOR is reachable and correct at runtime. It selects the mode, copies the
* three published geometry values to a fixed address, and halts. Nothing is drawn.
*
* ★ Why a runtime probe at all when the listing already shows the emitted bytes: the bytes
* prove the TABLE is right. They do not prove HAL_gfx_set_mode can REACH row 2 -- that needs
* GFX_MODE_MAX to have been bumped, and a stale MAX silently clamps mode 2 to mode 0 with no
* error (gfx.s: `cmpa #GFX_MODE_MAX / bls / clra`). Reading the value back is what
* distinguishes "the row exists" from "the row is selectable".
*
* Result block at PROBE_OUT, for the MAME-side reader:
*   +0  byte   mode id the HAL settled on   (2 if reachable, 0 if clamped)
*   +1  byte   $FF99 VRES value             ($3E expected)
*   +2  byte   stride                       (160 = $A0 expected)
*   +3  word   HAL_gfx_cur_words            ($3E80 = 16000 expected)
*   +5  byte   $A5 sentinel, written LAST   -- proves the probe ran to completion
                include "src/hal.inc"

PROBE_OUT       equ     $7F00           ; scratch, well clear of the probe at $2000

                org     $2000
probe_entry:
                orcc    #$50                    ; mask interrupts for the duration

* ★ HAL_sys_init FIRST. Skipping it was the probe's own first defect: HAL_gfx_set_mode
* writes $FF90 and enables the MMU (gfx.s "Constraint A"), and with the task registers
* never initialised the CPU's view of memory changes underneath the running code -- the
* probe simply vanished and the sentinel was never written. hal.inc lists it as step 0,
* "bare-metal transition: mask + $FF90 + MMU". Not a mode-2 problem.
                jsr     HAL_sys_init

                lda     #GFX_MODE_320x200x16    ; = 2, the contract name not the literal
                jsr     HAL_gfx_set_mode

                ldx     #PROBE_OUT
                lda     HAL_gfx_cur_mode
                sta     ,x
                lda     HAL_gfx_cur_vres
                sta     1,x
                lda     HAL_gfx_cur_stride
                sta     2,x
                ldd     HAL_gfx_cur_words
                std     3,x

                lda     #$A5                    ; sentinel LAST -- a partial run is visible
                sta     5,x

probe_halt:     bra     probe_halt

* --- the HAL itself, same module list and order as src/harness/hal_build.s ------
* A raw image has no linker, so the probe carries the kernel it calls. hal.inc above
* is the CONTRACT (declarations); these are the implementations.
                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"
                include "src/hal/coco3-dsk/input.s"
                include "src/hal/coco3-dsk/sound.s"
                include "src/hal/coco3-dsk/file.s"
                include "src/hal/coco3-dsk/mem.s"
                include "src/hal/coco3-dsk/disk_read.s"
                end     probe_entry
