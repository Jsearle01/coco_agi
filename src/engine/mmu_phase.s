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
ph_blk_vol      fcb     0               ; ★ the block slot 6 holds IN THE VM PHASE -- an INTENT
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SINGLE RECORD OF WHAT THE TWO MOVING SLOTS ACTUALLY HOLD [T-P0-135].
*
* ★★★★★ TWO SUBSYSTEMS USED TO KEEP PRIVATE CACHES OF THIS AND EACH WAS CORRECT ONLY WHILE THE
* OTHER REMEMBERED TO INVALIDATE IT -- res_curblk in res_core.s, pl_vis_cur/pl_pri_cur in
* plane_win.s. **It failed twice, in opposite directions**: P6.74, where res_open read framebuffer
* bytes as a resource header and silently refused two sprites; P6.78, where the compositor wrote
* sprite pixels into Kingquest1's volume 1 and the re-fetched logic 1 fell into the alligator-death
* block. ★★★★ Both fixes were a THIRD invalidation rather than an owner, which is why there is now
* a record instead.
*
* ★★★★★ ph_blk_vol IS AN INTENT AND THESE ARE THE FACT, AND CONFLATING THEM IS THE OLD DEFECT IN
* MINIATURE. phase_vm restores slot 6 from ph_blk_vol -- "what the VM phase wants there". ph_cur6
* is "what is there now", which a draw phase changes without changing the intent. **Two questions,
* two bytes**; one byte answering both is what res_curblk tried to be.
*
* ★★★ $FF IS "UNKNOWN", AND IT IS SAFE BECAUSE A GIME BLOCK NUMBER IS SIX BITS ($00-$3F). Never
* initialise these to 0: block 0 is legal, and a zero-initialised record would skip the first map
* and address whatever the window happened to hold [plane_win.s made exactly this point].
* ★★ A HOST THAT MOVES THE MMU ITSELF WRITES $FF HERE. res_sweep.lua and vm_sweep.lua already do
* that to res_curblk, which is this byte under its old name.
ph_cur5         fcb     $FF             ; what slot 5 holds NOW ($FF = unknown)
ph_cur6         fcb     $FF             ; what slot 6 holds NOW ($FF = unknown)

* ── phase_slot5 / phase_slot6 — A = an ABSOLUTE block number. THE ONLY WRITERS. ──
* ★★★★★ THE ANSWER TO "CAN A CACHE DISAGREE WITH THE REGISTER?" IS STRUCTURAL, NOT DILIGENT
* [§4B's test of the design]. After this change there is **exactly one `sta MMU_SLOT5` and exactly
* one `sta MMU_SLOT6` in the whole tree**, and each is immediately preceded by the store that
* records it. A writer cannot forget the record, because reaching the register means coming
* through here. ★★★★ Every other routine in this file -- and plane_win.s, and res_core.s -- now
* calls one of these two.
* ★★★ THE RECORD IS WRITTEN FIRST. If an interrupt could observe the pair mid-update, a record
* that is stale-pessimistic (says the OLD block while the register already holds the new one) would
* cause a redundant remap; one that is stale-optimistic would cause a MISSED remap, which is the
* defect class this exists to end. **Neither is reachable today** -- every caller runs with
* interrupts masked or outside the IRQ's reach -- and the safe order is used anyway.
* ★ A is preserved, because callers chain these (phase_text_in's inca walk) and because the
* B-clobber class of defect has been found three times in this project [T-P0-027/030].
phase_slot5:
                sta     ph_cur5
                sta     MMU_SLOT5
                rts

phase_slot6:
                sta     ph_cur6
                sta     MMU_SLOT6
                rts
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
                jmp     phase_slot6

* ── phase_draw -- the pair: priority in slot 5, framebuffer slice in slot 6 ──────
* ★ A = the framebuffer slice index (0..3), because the visual plane is 26,880 B and the
* aperture is 8,192. B is preserved: callers hold the object index across this call, and
* T-P0-027/030 found that class of defect three times in three different registers.
* ★★ A IS CLOBBERED HERE AS IT ALWAYS WAS (it held ph_blk_pri on exit before this change too);
* only B's preservation was ever contractual.
phase_draw:
                pshs    b
                adda    ph_blk_fb
                jsr     phase_slot6
                lda     ph_blk_pri
                jsr     phase_slot5
                puls    b,pc

* ── phase_draw_pri -- select which priority slice is visible ─────────────────────
* ★ The packed plane is 13,440 B against an 8,192 B aperture, so it is TWO slices and the
* caller names which. Separate from phase_draw because a composite pass crosses the priority
* boundary at a different row than the framebuffer boundary -- 13,440/8,192 vs 26,880/8,192 --
* and folding them would force a remap of both whenever either moved.
phase_draw_pri:
                pshs    a
                adda    ph_blk_pri
                jsr     phase_slot5
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
                jsr     phase_slot6
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
                jsr     phase_slot5
                puls    a,pc

phase_draw_pri_slot6:
                pshs    a
                adda    ph_blk_pri
                jsr     phase_slot6
                puls    a,pc

* ── phase_vol -- point the volume window at a block, VM phase only ───────────────
* ★★ ASSERTS NOTHING AT RUNTIME AND THAT IS DELIBERATE. Calling this during a draw phase would
* silently unmap the framebuffer slice. The guarantee is structural -- a fetch never happens
* while drawing (§3.4) -- and a runtime check here would cost cycles on the hot path to
* re-verify a property the phase discipline already provides.
* ★★★★ ITS STRUCTURAL GUARANTEE NOW HAS A SECOND CUSTOMER, AND IT STILL HOLDS [T-P0-135 §1.3].
* res_map_block calls here instead of writing the register itself, so storage is now a client of
* the phase discipline rather than a second owner of it. **The guarantee being relied on is
* unchanged** -- a fetch never happens while drawing (§3.4) -- and storage was ALREADY relying on
* it: res_core.s wrote $FFA6 directly from exactly the same call sites. ★★★ What changes is that
* a violation is now visible rather than silent: if a fetch ever did run mid-draw, ph_cur6 would
* record the volume block and plane_vis would remap on its next access, instead of the two caches
* disagreeing and one of them writing into the other's memory.
* ★★ Still no runtime assertion, for the reason above: a check here costs cycles on the fetch path
* to re-verify a property the phase discipline provides.
phase_vol:
                sta     ph_blk_vol
                jmp     phase_slot6

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
                jmp     phase_slot5

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ HAZARD, RECORDED BEFORE IT IS DISCOVERED: THESE TWO DO NOT NEST [T-P0-095 §1.2].
* phase_vocab_out writes ph_blk_slot5 -- a STATIC value the client sets at boot -- and **it does
* not restore what slot 5 HELD.** Neither `_in` routine saves anything; there is no stack.
* ★★★★★ SO A PARSE INSIDE AN OPEN TEXT WINDOW LEAVES SLOT 5 WRONG. phase_text_in put the third
* framebuffer block there; phase_vocab_out would put the object table's block back, and the rest
* of the blit would draw into the wrong plane with nothing objecting.
* ★★★★ IT IS NOT REACHABLE TODAY and that is why this is a comment rather than a guard: the
* oracle's own order is parse first, redraw second [text.cpp:782-793], and txt_pkey follows it --
* the ENTER arm calls the parse vector before it calls txt_predraw, and the two never overlap.
* ★★★ T-P0-094 measured that this is NOT the restart's cause (the text engine was modelled in the
* arm that still restarts), so it is recorded as a live hazard and not as a suspect.
* ★★ The fix, if one is ever needed, is an actual save -- `phase_vocab_in` reading the current
* slot-5 intent into a byte -- which is a design change and not a line.
phase_vocab_out:
                lda     ph_blk_slot5
                jmp     phase_slot5
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

* ★★ SLOTS 3 AND 4 ARE WRITTEN DIRECTLY AND 5/6 GO THROUGH THE ENTRIES. The record exists for the
* two CONTENDED slots; 3 and 4 have exactly one client (this routine and its partner) and no
* second cache ever existed for them. ★ phase_slot5/6 preserve A, so the inca chain is unbroken.
phase_text_in:
                lda     ph_blk_text
                sta     MMU_SLOT3
                inca
                sta     MMU_SLOT4
                inca
                jsr     phase_slot5
                inca
                jmp     phase_slot6

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
                jsr     phase_slot5
                jmp     phase_vm
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE CEL CACHE'S BORROW OF SLOT 4 [T-P0-147]. Same shape as phase_text_in/out above, in a
* DIFFERENT PHASE, and it restores from the SAME byte.
*
* ★★★★★ WHY SLOT 4 AND NOT ANOTHER: a per-aperture tap bucketed by P3_PHASE measured slot 4
* ($8000-$9FFF, the arena's HIGH half) at **0 reads and 0 writes for the entire draw phase** --
* sprites, roomcheck, every room-render sub-step and the composite -- while the SAME taps counted
* 83,357 accesses there in other phases [P6.92 §4A]. ★★★★ Slot 3 is NOT usable: it is busy during
* roomcheck (4,456 r / 2,752 w), which is inside the borrow window.
*
* ★★★★★ THE REGISTER IS $FFA4. $FFA5 IS SLOT 5 -- THE PRIORITY SLICE, AND IT IS LIVE DURING THE
* COMPOSITE (17,204 r / 36,651 w). The dispatch named $FFA5 for this borrow; borrowing it would
* map the cache over the priority plane mid-blit, which is P6.78's defect exactly.
*
* ★★★★ THE RESTORE VALUE IS ph_blk_slot4 AND ITS PROVENANCE IS THE BOOT MAP: p3b_run.lua pre-sets
* all eight slots to $38+i, so slot 4 is $3C, and p3b_probe.s stores it there at init. ★★★ The
* register is WRITE-ONLY, so this byte is the only record -- a read-back would return nothing and
* a saved copy would be a second opinion about the same fact [§2F].
*
* ★★★ ONE OWNER PRESERVED: these two entries are in THIS file, which reg_discipline already
* reports as the sole owner of $FFA3-$FFA6. A borrow written at the call site would have added a
* second writer, which is §6's first trigger and what P6.82 cost a task to undo.
                ifdef   PHASE_CELCACHE
ph_blk_cache    fcb     0               ; the cache's physical block; set from the boot map
* ★★★★★ ph_blk_slot4 IS DECLARED UNDER PHASE_TEXT ABOVE, AND THE CACHE NEEDS IT WITHOUT THE TEXT
* WINDOW [T-P0-147]. The plain `p3b` gate arm has cels and no PHASE_TEXT, so the first cut failed
* to assemble: "Undefined symbol ph_blk_slot4".
* ★★★★★ AND THE ASSEMBLER IS WHAT SAVED IT. Had the symbol merely EXISTED and been zero -- which is
* what a `rmb` or a differently-ordered declaration would have given -- phase_cache_out would have
* mapped BLOCK 0 over the arena, and block 0 is P3_BLK_PRI, the LIVE PRIORITY PLANE. **That is
* P6.78's defect exactly: silent, plausible, and visible only as corrupted game data.**
* ★★★ Declared here only when PHASE_TEXT has not already declared it, so the two can never both
* define it and the value keeps ONE home [§2F].
                ifndef  PHASE_TEXT
ph_blk_slot4    fcb     0               ; what slot 4 holds outside the cache's borrow
                endc
phase_cache_in:
* ★★★★★ CC_FAULT_POISON -- THE GUARD FOR THE CLASS, NOT FOR THE INSTANCE [T-P0-147].
* ★★★★★ THE BORROW IS SAFE ONLY WHILE NOTHING READS $8000-$9FFF IN THE DRAW PHASE, and that was
* MEASURED ONCE, ON ONE BUILD [P6.92 §4A]. Turning on -CelCheck added a reader the census never
* saw, and the symptom was a plausible wrong checksum rather than a crash. ★★★★ A future reader
* would be just as quiet.
* ★★★ With this arm the borrowed slot holds the PRIORITY SHADOW instead of the cache, so any
* draw-phase arena read returns recognisably wrong bytes AND the cache's own reads break -- the
* planes must go wrong. **It proves the aperture really is being switched, in both directions:
* -NoCelCache + this arm must stay GREEN (nothing reads it), and the cache + this arm must go RED
* (the cache reads it).** ★★ That pair is the whole §2W demonstration for a borrow.
                ifdef   CC_FAULT_POISON
                lda     #45                     ; the priority shadow -- not ours, and not the cache
                sta     MMU_SLOT4
                rts
                endc
                lda     ph_blk_cache
                sta     MMU_SLOT4
                rts
phase_cache_out:
* ★★★★★ AC-5's FAULT ARM: restore the WRONG block. The arena's high half then holds the priority
* shadow, and the next resource fetch that reaches above $8000 reads and writes the wrong memory.
* ★★★ The expected red is logic_copy_diff non-zero on logic 1 -- P6.78's own signature -- and NOT
* merely a different counter. **A restore that cannot be shown to matter is not a restore anyone
* checked** [§2W].
                ifdef   CC_FAULT_BADRESTORE
                lda     #45
                sta     MMU_SLOT4
                rts
                endc
                lda     ph_blk_slot4
                sta     MMU_SLOT4
                rts
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
