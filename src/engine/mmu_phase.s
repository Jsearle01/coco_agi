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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE EXCEPTION, AND IT IS AN EXCEPTION TO THE SENTENCE ABOVE [T-P0-093]. The TEXT WINDOW
* borrows slots 3 AND 4 as well, for the duration of one glyph blit or one line clear, and puts
* them back by known value. **Slots 0-4 are no longer "never touched"; slots 3 and 4 are touched
* by phase_text_in/_out and by nothing else.**
* ★★★★★ IT IS WRITTEN DOWN HERE BECAUSE THE CONTRACT IS WRITTEN DOWN HERE. The mapping used to
* live in src/harness/vm_text_ops.s, whose own comment said: *"$FFA4 HAS NO SANCTIONED OWNER:
* mmu_phase.s manages slots 5 and 6 only. This file becomes the second writer of the MMU register
* file, which is a §2N ownership question and is reported rather than settled here."* **A second
* writer that breaks the first writer's stated invariant is the shape this move exists to end.**
* ★★★★ WHY FOUR SLOTS: the display is mode 2, 320x200x16, 160 B/row = 32,000 bytes. Three
* contiguous blocks are 24,576 B = rows 0-18, and AGI's command line is at row 22 -- pixel row
* 176, byte 28,160. **Every prompt glyph was silently refused for want of a fourth block** [P6.37].
* $6000-$DFFF is 32,768 B and holds all 200 display rows with 768 to spare.
* ★★★ THE RESTORE IS BY KNOWN VALUE BECAUSE THE REGISTERS ARE WRITE-ONLY. There is no save. The
* values come from the client, in ph_blk_slot3/4/5, and the client got them from the boot map.
*
* ★★★★ AND SLOT 5 NOW HAS A THIRD TENANT, WHICH IS A WIDENING OF THE SAME MECHANISM RATHER
* THAN AN EXCEPTION TO IT [T-P0-091]. memmap.inc has said since T-P0-060 that the VOCABULARY
* lives in slot 5 in the VM phase (`MAP_VOCAB equ MAP_PRI_SLICE`) -- it just had no code.
* phase_vocab_in/_out below are that line becoming a routine. **Slot 5 was already the moving
* slot; nothing that this file called fixed has become movable.**
*
* ★★★ THIS FILE IS WHY reg_discipline.py NOW REPORTS A NON-ZERO COUNT, AND THAT IS CORRECT.
* CLAUDE.md §2N.2: "the goal is ONE SANCTIONED OWNER per register, not zero references."
* **This file is the sanctioned owner of $FFA5 and $FFA6.** A count of zero would mean the
* engine does not exist, which is exactly what the previous zero meant.
* ★★ THE COUNT IN THE OLD TEXT BELOW WAS 5 AND THE CENSUS SAYS 8 -- a figure in a comment with
* no producer, stale since the cross-slot pair landed [AD-95's shape, corrected in passing
* because this task moves the number again: 8 -> 10, both new writes in this file].
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/engine/memmap.inc"

* ★★ THE MMU TASK-1 SLOTS. $FFA0-$FFA7 map $0000,$2000,...,$E000. Named here rather than
* written as literals so §2N's alias-resolving scan sees them [it MISSES literal greps by
* design -- CEL_MMU/BANK_MMU/TC_MMU/PALETTE are the majority of POP's real accesses].
MMU_SLOT3       equ     $FFA3           ; $6000-$7FFF -- arena low / text window rows 0-6
MMU_SLOT4       equ     $FFA4           ; $8000-$9FFF -- arena high / text window rows 7-12
MMU_SLOT5       equ     $FFA5           ; $A000-$BFFF -- the priority slice
MMU_SLOT6       equ     $FFA6           ; $C000-$DFFF -- framebuffer slice / volume window

* ── the block numbers, filled at init by the allocator ───────────────────────────
* ★ Blocks are ALLOCATED, not compiled in: a 128 KB machine masks a block number to the RAM
* actually installed and every number aliases mod 16 [§2K, gfx.s:405-417]. A hard-coded block
* is the P3.10 defect -- fine on 512 KB, fatal on 128 KB.
ph_blk_pri      fcb     0               ; first block of the priority plane
ph_blk_fb       fcb     0               ; first block of the framebuffer
ph_blk_vol      fcb     0               ; the block currently holding the VOL window
* ★★★★★ WORDS.TOK's BLOCK, AND WHAT SLOT 5 HOLDS WHEN IT IS NOT MAPPED [T-P0-091].
* ★★★★ ph_blk_slot5 EXISTS BECAUSE A CLIENT MAY PUT SOMETHING IN SLOT 5 DURING THE VM PHASE AND
* THE ENGINE'S OWN MODEL DOES NOT. memmap.inc's phase table reads "-- nothing mapped --" for slot
* 5 in the VM phase, and phase_vm says so in as many words ("SLOT 5 IS LEFT ALONE, NOT CLEARED").
* p3b_probe.s:604 names the gap that leaves: it puts the 8,160-byte object table there, and
* "the engine needs a ph_blk_obj and a phase_vm that restores it". **That is this byte**, closed
* here because windowing the vocabulary is the first thing that unmaps slot 5 mid-phase.
* ★★★ AN ENGINE THAT GENUINELY HOLDS NOTHING IN SLOT 5 NEVER CALLS phase_vocab_out -- it enters a
* draw phase next and phase_draw writes the slot anyway. The byte is not a dummy write with no
* reader; it is the client saying what to put back.
* ★★★★★ BEHIND -DPHASE_VOCAB, AND THAT IS NOT TIDINESS. This file is included UNCONDITIONALLY by
* every windowed probe, so two bytes and two routines here are 16 bytes in EVERY client --
* including `p3b`, the purpose=timing row whose byte identity AC-5 gates. **The first build of
* this change grew the cel configuration by exactly those 16 bytes and tripped its CP_CEL guard**,
* which is the guard doing its job. A client that wants the window says so, the way
* HAL_GFX_MODE_SERVICE works one layer down [§2M.2's `ifndef` discipline, same shape].
                ifdef   PHASE_VOCAB
ph_blk_vocab    fcb     0               ; WORDS.TOK, mapped only while a line is TOKENISED
ph_blk_slot5    fcb     0               ; what slot 5 holds outside that window
                endc

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
* ★★★ §2N: this file is the ONE sanctioned owner of $FFA5/$FFA6 -- reg_discipline reports every
* access in 1 file over 2 registers, and THAT is the property being preserved, not the count
* [the count was written as 5 here and measured 8; see the header]. plane_win.s
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

* ── phase_vocab_in / phase_vocab_out -- the VOCABULARY window, TOKENISE only ─────
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHY THIS IS A WINDOW AND NOT A RESIDENT TABLE. WORDS.TOK is up to 6,828 bytes
* (SpaceQuest-2, the corpus maximum, re-measured at T-P0-059 §3.E) and it is READ ONCE PER
* TYPED LINE. Resident, it is 88% of a permanently-mapped 8 KB bank spent on a table that a
* game evaluating fifteen said() patterns a cycle touches for none of them.
*
* ★★★★★ THE NARROWING IS memmap.inc's AND IT IS THE WHOLE REASON THIS IS CHEAP: "ONLY par_parse
* NEEDS IT MAPPED, NOT par_said. par_said reads par_ego, par_egon and the operand stream; it
* never touches par_vocab." So the window is open for one call per ENTER and shut otherwise --
* two MMU writes per typed command, against two per phase transition for everything else.
*
* ★★★★ AND THE RESIDENCY SET IS WHAT MAKES IT LEGAL. Everything par_parse touches besides the
* dictionary is in slot 0 (the hardware stack, the direct page) or slot 7 (parser.s's code, its
* state, par_inbuf, par_clnbuf, par_ego) -- and par_parse calls nothing outside parser.s.
* **Neither slot 0 nor slot 7 ever moves**, so the tokeniser can run with any other slot pointed
* anywhere. Slot 5 is the one memmap.inc already reserved for it.
*
* ★★★ NOT SLOT 6, AND memmap.inc GIVES THE REASON: slot 6 is the VOLUME window in the VM phase
* and a resource fetch happens in the VM phase. Slot 5 is idle there. §3.4's disjointness is
* what makes this legal and it is the third place in the map where that property is load-bearing.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifdef   PHASE_VOCAB
phase_vocab_in:
                lda     ph_blk_vocab
                sta     MMU_SLOT5
                rts

phase_vocab_out:
                lda     ph_blk_slot5
                sta     MMU_SLOT5
                rts
                endc

* ── phase_text_in / phase_text_out -- the TEXT WINDOW, four slots, $6000-$DFFF ───
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ FOUR CONTIGUOUS BLOCKS, FLAT, SO EVERY DISPLAY ROW IS ADDRESSABLE AT ONCE [T-P0-093].
* A character row is 1,280 bytes and the last byte a glyph writes is (r*8+7)*160 + 159, so row 24
* ends at 31,999. **Three blocks stop at 24,576 and row 22 begins at 28,160** -- which is why the
* command line was invisible and nothing said so [P6.37 §4D].
*
* ★★★★★ THE BORROW IS LEGAL BECAUSE NOTHING IN SLOTS 3-6 IS READ DURING A BLIT, AND THAT IS
* MEASURED RATHER THAN ASSUMED [T-P0-093 §4A]: the font is at $E3BA (slot 7, which never moves),
* the substituted text is in txt_pbuf at $1C00 (slot 0), text.s's whole state block is $4F3F-$5498
* (slot 2), and the stack and direct page are slot 0. **The four borrowed slots hold the
* framebuffer and nothing the drawing needs to read.**
*
* ★★★★★ AND THAT TURNS vm_text_ops.s's HAZARD 1 FROM LUCK INTO A REQUIREMENT. That file recorded
* the txt_pbuf isolation as *"luck, and it is recorded as luck rather than as design."* With the
* arena's LOW half borrowed as well, a blit that read the message straight from the resource would
* read framebuffer bytes -- so substitution running first, into slot 0, is now load-bearing.
*
* ★★★★ ONE `inca` CHAIN, NOT FOUR LOADS: the blocks are contiguous by construction (the visible
* plane is four consecutive blocks), so the first block number plus three increments is the whole
* mapping and it cannot describe a discontiguous window by accident.
                ifdef   PHASE_TEXT
* ★★ ph_blk_slot5 IS PHASE_VOCAB's BYTE AND phase_text_out READS IT. One home for "what slot 5
* holds otherwise" [§2F]; declaring a second would let the two restores disagree. Asserted rather
* than left to fail on an undefined symbol sixty lines away.
                ifndef  PHASE_VOCAB
                error   "PHASE_TEXT needs PHASE_VOCAB -- phase_text_out restores slot 5 from ph_blk_slot5"
                endc
ph_blk_text     fcb     0               ; first of FOUR contiguous framebuffer blocks
ph_blk_slot3    fcb     0               ; what slot 3 holds otherwise (the arena's low half)
ph_blk_slot4    fcb     0               ; what slot 4 holds otherwise (the arena's high half)

phase_text_in:
                lda     ph_blk_text
                sta     MMU_SLOT3
                inca
                sta     MMU_SLOT4
                inca
                sta     MMU_SLOT5
                inca
                sta     MMU_SLOT6
                rts

* ★★★ SLOT 6 GOES BACK THROUGH phase_vm, NOT BY A FOURTH LITERAL. That slot's VM-phase content is
* ph_blk_vol and the phase machinery already owns the question; a literal here would be a second
* opinion about the same byte, which is exactly the defect this file exists to prevent.
* ★★ Slot 5 comes back from ph_blk_slot5, which phase_vocab_out already uses -- one home.
phase_text_out:
                lda     ph_blk_slot3
                sta     MMU_SLOT3
                lda     ph_blk_slot4
                sta     MMU_SLOT4
                lda     ph_blk_slot5
                sta     MMU_SLOT5
                jmp     phase_vm
                endc
