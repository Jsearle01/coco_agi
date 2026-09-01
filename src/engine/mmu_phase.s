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

* ── phase_draw_fb — A = framebuffer SLICE index. Map it into slot 6. ──
* ★★★★ THE COUNTERPART TO phase_draw_pri, AND IT EXISTS SO plane_win.s DOES NOT WRITE $FFA6.
* phase_draw remaps BOTH slots and is the phase-entry call; a windowed walk crossing a slice
* boundary needs to move the framebuffer alone, hundreds of times per picture, and must not
* disturb the priority slice while doing it.
* ★★★ §2N: this file is the ONE sanctioned owner of $FFA5/$FFA6 -- reg_discipline reports 5
* accesses in 1 file over 2 registers, and that is the property being preserved. plane_win.s
* calling here keeps the owner count at one; plane_win.s writing the register itself would have
* made it two, silently, in a file the census would then have had to grow to cover.
phase_draw_fb:
                pshs    a
                adda    ph_blk_fb
                sta     MMU_SLOT6
                puls    a,pc

* ── the CROSS-SLOT pair: a plane's slice into the OTHER plane's slot ──
* ★★★★ THESE EXIST FOR THE FILL'S STRADDLE BORROW AND FOR NOTHING ELSE. When a fill's 3-row
* neighbourhood crosses a slice boundary (0.67% of flushes, measured), one 8 KB window cannot
* hold it, so the low slice goes into slot 5 and the high into slot 6 -- $A000-$DFFF contiguous
* -- and P3.3's walk runs unmodified over the pair.
* ★★★ The plane whose slot is borrowed is NOT read during the walk; the flush writes it and
* re-maps for itself. **The borrow lasts one span.**
* ★★ Still the single owner: every MMU write in the tree is in this file, so reg_discipline
* stays at one file over two registers no matter how many entry points it grows.
phase_draw_fb_slot5:
                pshs    a
                adda    ph_blk_fb
                sta     MMU_SLOT5
                puls    a,pc

phase_draw_pri_slot6:
                pshs    a
                adda    ph_blk_pri
                sta     MMU_SLOT6
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
