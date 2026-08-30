* src/engine/mmu_phase.s -- §3.4's phase discipline, as code.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE PHASE PAIR IS DECLARED ONCE PER PHASE, NEVER PER OBJECT AND NEVER PER SCANLINE.
* Design §3.4: the VM runs with NO plane mapped; picture-draw and sprite-composite each need
* one framebuffer slice plus one priority slice. **Get this wrong and it becomes a remap per
* scanline -- 7 cycles against a performance failure.**
*
* ★★ ONLY TWO SLOTS EVER MOVE. Slots 0-4 and 7 are mapped once at init and never touched
* again; slot 5 (priority) and slot 6 (framebuffer / volume) are the entire phase mechanism.
* That is why this file is short, and the shortness is the design being right rather than the
* implementation being incomplete.
*
* ★★★ THIS FILE IS WHY reg_discipline.py NOW REPORTS A NON-ZERO COUNT, AND THAT IS CORRECT.
* CLAUDE.md §2N.2: "the goal is ONE SANCTIONED OWNER per register, not zero references."
* **This file is the sanctioned owner of $FFA5 and $FFA6.** A count of zero would mean the
* engine does not exist, which is exactly what the previous zero meant.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/engine/memmap.inc"

* ★★ THE MMU TASK-1 SLOTS. $FFA0-$FFA7 map $0000,$2000,...,$E000. Named here rather than
* written as literals so §2N's alias-resolving scan sees them [it MISSES literal greps by
* design -- CEL_MMU/BANK_MMU/TC_MMU/PALETTE are the majority of POP's real accesses].
MMU_SLOT5       equ     $FFA5           ; $A000-$BFFF -- the priority slice
MMU_SLOT6       equ     $FFA6           ; $C000-$DFFF -- framebuffer slice / volume window

* ── the block numbers, filled at init by the allocator ───────────────────────────
* ★ Blocks are ALLOCATED, not compiled in: a 128 KB machine masks a block number to the RAM
* actually installed and every number aliases mod 16 [§2K, gfx.s:405-417]. A hard-coded block
* is the P3.10 defect -- fine on 512 KB, fatal on 128 KB.
ph_blk_pri      fcb     0               ; first block of the priority plane
ph_blk_fb       fcb     0               ; first block of the framebuffer
ph_blk_vol      fcb     0               ; the block currently holding the VOL window

* ── phase_vm -- no plane mapped; slot 6 is the volume window ─────────────────────
* ★★ SLOT 5 IS LEFT ALONE, NOT CLEARED. There is no "unmapped" block number on the GIME -- a
* slot always maps something -- so the VM phase is defined by what it does NOT touch, not by
* writing a sentinel. Clearing it to a dummy block would be a write with no reader.
phase_vm:
                lda     ph_blk_vol
                sta     MMU_SLOT6
                rts

* ── phase_draw -- the pair: priority in slot 5, framebuffer slice in slot 6 ──────
* ★ A = the framebuffer slice index (0..3), because the visual plane is 26,880 B and the
* aperture is 8,192. B is preserved: callers hold the object index across this call, and
* T-P0-027/030 found that class of defect three times in three different registers.
phase_draw:
                pshs    b
                tfr     a,b
                addb    ph_blk_fb
                stb     MMU_SLOT6
                lda     ph_blk_pri
                sta     MMU_SLOT5
                puls    b,pc

* ── phase_draw_pri -- select which priority slice is visible ─────────────────────
* ★ The packed plane is 13,440 B against an 8,192 B aperture, so it is TWO slices and the
* caller names which. Separate from phase_draw because a composite pass crosses the priority
* boundary at a different row than the framebuffer boundary -- 13,440/8,192 vs 26,880/8,192 --
* and folding them would force a remap of both whenever either moved.
phase_draw_pri:
                pshs    a
                adda    ph_blk_pri
                sta     MMU_SLOT5
                puls    a,pc

* ── phase_vol -- point the volume window at a block, VM phase only ───────────────
* ★★ ASSERTS NOTHING AT RUNTIME AND THAT IS DELIBERATE. Calling this during a draw phase would
* silently unmap the framebuffer slice. The guarantee is structural -- a fetch never happens
* while drawing (§3.4) -- and a runtime check here would cost cycles on the hot path to
* re-verify a property the phase discipline already provides.
phase_vol:
                sta     ph_blk_vol
                sta     MMU_SLOT6
                rts
