* src/harness/p3b_probe.s -- P3b: five gated subsystems on one machine, for the first time.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ WHAT THIS IS AND IS NOT. It fetches a PICTURE through the REAL resource path, renders
* it, runs the VM cycle against real LOGIC, and composites sprites with the priority test live.
* **It is NEVER a delivery gate**: resources are POKED by the host, and poke hides load and
* launch bugs -- POP's freeze P2.7, the LOADM ceiling P3.3 and the EXEC-overwrite P3.5 all
* lived on the real path and were invisible to poke [CLAUDE.md §4]. `live-disk` gates delivery
* and does not exist yet.
*
* ★★ THE DELIVERABLE IS THE PER-CYCLE BUDGET, not the picture. Each subsystem's cost is known
* alone and none has been measured beside the others: a cycle that must run five times a second
* has to fit the VM, motion, compositing and any fetch inside 200 ms, and nothing has ever run
* that loop.
*
* ★★★ THE MAP IS src/engine/memmap.inc AND IT DRIVES, rather than this file choosing addresses.
* That inverts every previous probe and it is the whole point of P6.1: four probes each assumed
* the whole 64 KB and two of them overlapped. Here the map is included FIRST and the subsystem
* defaults are overridden from it, so a collision is an assembly error rather than a runtime
* mystery.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/engine/memmap.inc"

* ── the map drives the subsystems ────────────────────────────────────────────────
* ★★ These override res_core.s's and vm_state.s's own `ifndef`-guarded defaults. res_core was
* already guarded; vm_state was NOT and was nailed to $4000 -- guarding it (defaults unchanged,
* every existing probe byte-identical) is what made a shared map possible at all.
RES_DIRS        equ     MAP_DIRS
RES_ARENA       equ     MAP_ARENA_WIN
RES_ARENA_END   equ     MAP_ARENA_WIN_E

* ★★★★ THE VM STATE BLOCK IS 8,736 BYTES AND P6.1'S MAP ALLOCATED 2,048.
* VM_OBJ is **255 entries x 32 bytes = 8,160 B** [vm_state.s:63-66], because
* SCREENOBJECTS_MAX is 255 and the comment records WHY: *"KQ3 uses o255"*
* [tools/agivm/state.py:32]. That is a real index in a real title, not a safety margin.
* ★★★ P6.1's map said "screen objects, 16 x 42 B" -- MY OWN ARITHMETIC, not read from the
* source. This is L-63 in the place L-63 was written: the binding constraint was a property of
* the DATA, and the one number I did not go and look up is the one that was wrong.
* ★★ The resolution is below at PH_VMOBJ, and it is a phase decision rather than a bigger box.
VM_VARS         equ     MAP_VM_VARS
VM_FLAGS        equ     MAP_VM_FLAGS
VM_CTRL         equ     MAP_VM_CTRL
VM_OBJROOMS     equ     MAP_VM_OBJROOMS
* ★★★ THE OBJECT TABLE LIVES IN SLOT 5, WHICH IS IDLE IN THE VM PHASE.
* memmap.inc gives slot 5 ($A000-$BFFF) to the priority slice, mapped ONLY during draw phases
* -- so in the VM phase 8 KB of address space is doing nothing while the VM needs 8,160 bytes.
* ★★ The compositor does NOT need this table: it consumes a staged sprite list (x, y, prio, w,
* h, key, cel pointer), exactly as comp_probe's gate does. So the VM stages the list, then the
* draw phase remaps slot 5 to priority. **The phases stay disjoint and no region grows.**
* ★ 8,160 <= 8,192 with 32 bytes to spare, which is uncomfortably tight and is reported as such.
VM_OBJ          equ     MAP_PRI_SLICE
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE TWO COVERAGE COUNTERS, AND THIS PROBE HAD NO OPINION ABOUT THEM FOR TWENTY TASKS
* [P6.46, P6.47]. vm_state.s's defaults are $6300/$6400 -- `vm_probe`'s free space and **this
* probe's RES_ARENA window**, which is the line directly above at :30. Every dispatched opcode
* incremented a byte of whatever resource the arena held; Kingquest1's LOGIC 102 landed at $63F2
* and its `goto 0908` became an execution count.
* ★★★★ THEY ARE SLOT 7 NOW, which never moves in any phase -- the counters are written in every
* phase, so a region that is only sometimes mapped would be a different bug.
* ★★ Nothing in this probe or its host READS them; they are write-only here. That is not a reason
* to leave them unplaced -- **it is why the collision was silent.**
* ★★★★★ -DP3B_FAULT_COV_ARENA PUTS THEM BACK WHERE THEY WERE, and the assertions at the foot of
* this file must REFUSE the build [§2W]. It is P6.46's defect exactly -- $6300/$6400, inside
* RES_ARENA -- not an imitation of it, and it is the only way to know the new assertion is
* load-bearing rather than decorative. **An assertion nobody has seen fail is an unexercised
* assertion, and this whole task exists because the assertions that DID exist named the wrong
* neighbour.** Requires -DP3B_COVERAGE, since a dead counter collides with nothing.
                ifdef   P3B_FAULT_COV_ARENA
VM_TESTSEEN     equ     $6300
VM_OPSEEN       equ     $6400
                else
VM_TESTSEEN     equ     MAP_TESTSEEN
VM_OPSEEN       equ     MAP_OPSEEN
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THIS PROBE TURNS THEM OFF. -DVM_NOCOUNT unless -DP3B_COVERAGE asks for them back.
* ★★★★★ THE ARGUMENT IS NOT "they are dangerous" -- it is that **this probe never reads them**.
* VM_OPSEEN and VM_TESTSEEN exist to support the VM gate's AC-5 coverage claim, and that claim is
* made by `vm_probe` against nine titles. `p3b`'s gates are pictures, parses, rooms and a person
* looking at a screen. **An instrument that is written on the hottest path in the interpreter and
* read by nothing is not an instrument here**, and for twenty tasks it was writing into game data.
* ★★★★ IT COSTS NOTHING MEASURABLE AND IT IS NOT A WORKAROUND. The structural fix is the `ifndef`
* in vm_state.s and the assertions below; this line is the separate observation that `p3b` was
* carrying an instrument it had no use for. If a future task wants coverage here, -DP3B_COVERAGE
* turns it on and the assertions decide whether the map can hold it.
* ★★★ -DP3B_COVERAGE IS EXPECTED TO FAIL IN THE CEL CONFIGURATION AND THAT IS THE POINT [§2W].
* That arm's flat vocabulary window runs $E3BA-$FF00 and needs 6,828 of its 7,238 bytes, so
* MAP_COVERAGE at $FC00 does not fit -- **the build refuses and says so**, rather than the
* dictionary and the counters sharing 512 bytes the way the arena and the counters did.
* ★★ The inner `ifndef` is not redundant: -DVM_NOCOUNT on the command line is how every other probe
* ablates the counters, and a bare `equ` here would make that a multiply-defined symbol -- refusing
* a build for asking for the state this file is already in.
                ifndef  P3B_COVERAGE
                ifndef  VM_NOCOUNT
VM_NOCOUNT      equ     1
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════════════

FB_BASE         equ     MAP_PHASE_WIN           ; framebuffer slice, draw phase
PRI_BASE        equ     MAP_PRI_SLICE           ; priority slice, draw phase

* ★★★★★ THIS PROBE'S WINDOW IS REAL, SO THE MAP ACTION MUST BE THE MMU ONE.
* plane_win.s has two map actions: a flat-backed one that computes BASE + slice*8192 and touches
* no register, and the MMU one that calls mmu_phase.s. **The flat-backed action is correct ONLY
* where the plane is genuinely contiguous**, which is pic_probe's map ($8000 + 26,880 fits) and
* is emphatically not this one: $C000 + slice*8192 gives $C000, $E000, then $10000 -> $0000 and
* $12000 -> $2000, which is the code region. **Building this probe windowed but without
* PLANE_WIN_MMU reintroduces the exact wrap the windowing exists to remove**, and it was built
* that way once -- 12,782 bytes that assembled cleanly and could not be run.
PLANE_WIN_MMU   equ     1
PIC_W           equ     160
PIC_H           equ     168
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SEED STACK IS SIZED HERE, BY THIS PROBE, AND memmap.inc IS NOT TOUCHED [T-P0-089].
* STACK_BASE/STACK_TOP have always been probe-local equs that happened to take the engine's
* values. The engine reserves 768 B = 384 entries of (x,y) and records its own measurement beside
* it: **"peak measured at 37"**. 74 bytes used of 768.
* ★★★★ That slack is what the font needs. Region A ($2000-$6000) holds 14,691 B of code against a
* 2,048 B font and 16,384 of space -- 355 short -- and **the answer is not to shrink the code but
* to move DATA out of it** [Jay: "what lies below the code"]. vm_tables.s is 525 B of pure table
* and it now lives at P3_TABLES_BASE, in space this reservation was never using.
* ★★★ 128 ENTRIES, which is 3.5x the measured peak, not the 384 the engine reserves. ★★★★ AND THE
* FAILURE IS LOUD: pic_fill's ff_push compares against STACK_TOP-2 and HALTS on overflow -- "
* wrapping the stack would overwrite code and produce a wrong picture with no attributable cause"
* -- so a picture that needs more fails visibly and the renderer gate's 45 pictures, both planes,
* is what says it did not.
* ★★ THE PEAK IS A CORPUS MEASUREMENT, NOT A BOUND [L-86]. 37 is the deepest fill in 45 gated
* pictures; a picture outside that set could go deeper. The margin is 3.5x and the guard halts.
* ★★★★★ AND IT IS SCOPED TO THE TEXT CONFIGURATION. `p3b` is purpose=timing and its figures are
* attached to a binary; relocating bytes changes that binary even when it changes no behaviour, and
* AD-96 is the standing lesson about quoting a figure whose producer moved. **The cel build has no
* font and no font pressure, so it keeps the engine's seed stack and its own byte identity.**
STACK_BASE      equ     MAP_SEEDSTACK
                ifdef   P3B_NO_CEL
STACK_TOP       equ     MAP_SEEDSTACK+256       ; 128 entries; engine reserves 384
* ★★★ $0200-$0480 is what that frees. $0480-$0500 is left as margin below the hardware stack,
* whose own low-water is measured at S=$07C6 -- 710 bytes clear of its $0500 floor.
P3_TABLES_BASE  equ     MAP_SEEDSTACK+256
P3_TABLES_LIMIT equ     $0480
                else
STACK_TOP       equ     MAP_SEEDSTACK_E         ; the engine's 384 entries, unchanged
                endc
HW_STACK        equ     MAP_HWSTACK

* ── host handshake, in the status block ──────────────────────────────────────────
P3_GO           equ     MAP_STATUS+0
P3_MODE         equ     MAP_STATUS+1
P3_STATUS       equ     MAP_STATUS+2
P3_ERR          equ     MAP_STATUS+3
P3_CYCLE        equ     MAP_STATUS+4    ; 2 B: cycles completed
P3_ROOM         equ     MAP_STATUS+6
P3_NSPR         equ     MAP_STATUS+7    ; sprites staged this cycle
* ★ Per-phase cycle counters -- AC-5's breakdown. 4 bytes each, because a 200 ms budget at
* 1.789 MHz is 357,878 cycles and a 16-bit counter overflows inside one phase.
P3_T_VM         equ     MAP_STATUS+8
P3_T_MOTION     equ     MAP_STATUS+12
P3_T_COMP       equ     MAP_STATUS+16
P3_T_FETCH      equ     MAP_STATUS+20
P3_T_RENDER     equ     MAP_STATUS+24
P3_REMAPS       equ     MAP_STATUS+28   ; 2 B: MMU writes this cycle -- AC-6
* ★★★★ STALE, AND IT COST T-P0-060 THE EYE GATE'S FIRST TWO RUNS. MAP_STATUS+32 is NOT free --
* CNT_VERT is there (see the counter block below) -- and P3_FEED was placed at +32 on the
* strength of this line. Kept, struck through in words, because a comment that was believed is
* worth more as evidence than as a deletion [§2H's third check, which is mechanical and which I
* did not run on my own file].
* ★ SUPERSEDED: MAP_STATUS+32 is left free for a palette readback if this probe ever has room for one; see
* the note beside the agi_pal_load call. The status block is 224 B [memmap.inc].
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ P3_PHASE — THE TIMING MARKER, AND AC-5 CANNOT BE ANSWERED WITHOUT IT.
* P3_T_VM..P3_T_RENDER have existed since P3b.1 and are ZEROED EVERY CYCLE AND NEVER WRITTEN --
* declared, cleared, dead. The host read nothing from them because there was nothing to read, so
* "the per-cycle breakdown" had no producer at all.
* ★★★★ Rather than count cycles on the 6809 -- which costs the very time it measures -- this
* uses the mechanism pic_probe has proven since T-P0-012: the guest stores a phase number here,
* MAME write-taps the address and stamps `manager.machine.time` at the instant of the store.
* **Resolution is one instruction and emulated time is exact and deterministic**, so a stage's
* cost is a subtraction on the host and the guest pays one `sta`.
* ★★★ Odd = entering a stage, even = leaving it: 1/2 VM, 3/4 sprites, 5/6 room-check (fetch and
* render), 7/8 composite. The host pairs them; an unpaired marker is a stage that did not
* return, which is itself the finding.
P3_PHASE        equ     MAP_STATUS+30
* ── T-P0-060: the scripted input path, for §4A's eye gate ────────────────────────
* ★★ The host writes the line into P3_INBUF and sets P3_FEED while the guest is parked at
* p3_loop; the guest feeds it after vm_pace and before the cycle body, which is the same seam
* vm_probe.s uses so the two probes cannot disagree about when a keystroke lands.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ +88, AND THE FIRST VERSION SAID +32 BECAUSE A COMMENT IN THIS FILE SAID +32 WAS FREE.
* Line 88 above reads "MAP_STATUS+32 is left free for a palette readback if this probe ever has
* room for one". **It is not free: CNT_VERT has been at MAP_STATUS+32 since the renderer landed**
* (see the counter block below). The comment describes an intention that a later change
* overtook, and nothing checked it.
* ★★★★ THE FAILURE WAS EXACTLY WHAT §2F PROMISES. The renderer's vertical-line counter shares a
* byte with the feed flag, so drawing a room with vertical lines SET P3_FEED -- and the guest
* dutifully parsed an input line nobody had staged, against a vocabulary that was not there.
* par_fi_char's walk then had no terminator to find and ran away: the eye gate reported STUCK in
* the room-jump cycle with 105 hits on six consecutive PCs inside the bucket walk.
* ★★★★★ AND IT REPRODUCED WITH NO INPUT AND NO VOCABULARY STAGED, which is what proved it was a
* collision rather than a parser defect -- an ablation, not a reading [L-73].
* ★★★ THE LESSON IS §8's, and it is the one I skipped: **read the constants back from the file
* rather than from a comment about them.** A stale comment claiming a byte is free is worse than
* no comment, because it answers the question you were about to ask.
* ★★ +88 is past CP_CTRLSTEP's four bytes (+84..+87), the highest offset this probe declares,
* and the assertion at the foot of this file is what keeps that true rather than this sentence.
P3_FEED         equ     MAP_STATUS+88
P3_VOCAB_BAD    equ     MAP_STATUS+89   ; 2 B: first vocabulary-window address that failed
* ★★★ THE TYPED PATH'S OBSERVABLES [T-P0-092]. P3_KEY is the last key the editor was handed and
* P3_NKEY counts them, so the host can say "the matrix delivered N keys" independently of anything
* on screen. **A dead matrix and a dead editor are indistinguishable from the framebuffer alone**,
* and that is the discrimination AC-3 needs [§2W.3].
* ★★ +91 and +92, past P3_VOCAB_BAD's two bytes; the block's 224-byte assertion at the foot of this
* file is what keeps that true rather than this sentence.
P3_KEY          equ     MAP_STATUS+91
P3_NKEY         equ     MAP_STATUS+92

* ── the subsystems' instrumentation, which is NOT optional ───────────────────────
* ★★★ EVERY ONE OF THESE IS REQUIRED TO ASSEMBLE. pic_draw.s does `ldd CNT_VERT / addd #1 /
* std CNT_VERT` with no guard, and pic_core.s does the same for CNT_PIX. composite.s guards its
* counters behind -DCOMP_NOCOUNT; the renderer has no such switch.
* ★★ **The two subsystems disagree about whether instrumentation is part of the product**, and
* integration is what surfaced it: a shipped renderer cannot currently be built without its
* counters. Reported, not worked around (§8 trigger 5).
CNT_VERT        equ     MAP_STATUS+32
CNT_HORIZ       equ     MAP_STATUS+34
CNT_DIAG        equ     MAP_STATUS+36
CNT_PIX         equ     MAP_STATUS+38
CNT_SPAN        equ     MAP_STATUS+40
CNT_FILL        equ     MAP_STATUS+42
CNT_CHK         equ     MAP_STATUS+44
SP_PEAK         equ     MAP_STATUS+46
PATH_V          equ     MAP_STATUS+48
PATH_P          equ     MAP_STATUS+50
bad_op          equ     MAP_STATUS+52

* ── the compositor's inputs and counters ─────────────────────────────────────────
PRI_W           equ     PIC_W
PRI_H           equ     PIC_H
CP_X            equ     MAP_STATUS+54
CP_Y            equ     MAP_STATUS+55
CP_PRIO         equ     MAP_STATUS+56
CP_TESTED       equ     MAP_STATUS+60   ; 4 B each -- a 200 ms budget overflows 16 bits
CP_WRITTEN      equ     MAP_STATUS+64
CP_REJPRI       equ     MAP_STATUS+68
CP_REJKEY       equ     MAP_STATUS+72
CP_BLITS        equ     MAP_STATUS+76
CP_CTRLHIT      equ     MAP_STATUS+80
CP_CTRLSTEP     equ     MAP_STATUS+84

* ★★★★ THESE THREE ARE WHERE INTEGRATION BREAKS, AND THE ADDRESSES ARE WRITTEN DOWN HERE SO
* THE BREAK IS VISIBLE RATHER THAN LATENT. composite.s and pic_core.s both address their planes
* as FLAT arrays -- `put_pixel` computes y*160+x up to 26,879 and indexes from the base; the
* compositor does the same. **The map gives them 8 KB SLICES.** See the §8-trigger block at the
* foot of this file: the arithmetic does not work and it is reported rather than patched.
CP_VIS          equ     FB_BASE
CP_PRI          equ     PRI_BASE
* ★★★★★ NOT DEFINED UNDER -DP3B_NO_CEL, AND THAT IS THE POINT OF THE FLAG. CP_CEL is what occupies
* MAP_RESERVED; leaving the `equ` in place while stripping its consumers would keep the region
* nominally claimed and the collision guard below would still fire against a buffer nothing uses.
                ifndef  P3B_NO_CEL
* ★★★★★ ONE ROW, NOT A WHOLE CEL, SINCE T-P0-105. This was 4,784 bytes -- the corpus maximum --
* and it overlapped RES_ARENA ($6000) by 1,456, zeroing the VIEW it was decoding from [P6.49].
* ★★★★ The oracle keeps no shared staging buffer [view.cpp:357-370], so the buffer was ours; the
* compositor already consumed it a row at a time, so a row is all it ever needed.
* ★★★ COMP_ROW_PULL makes cp_composite call vc_decode_row at the top of each row. It is defined
* here and nowhere else: comp_probe composites a host-staged cel with no decoder linked.
* ★★★★★ AND IT MOVES TO THE TOP OF REGION A. At 4,784 bytes it had to start at $5300 and ran 1,456
* past the region's end into the arena; at 255 it fits in the last page, so **the code ceiling
* rises from $5300 to $5F00 -- 3,072 bytes back to region A** -- and the arena's first 1,456 bytes
* are its own again. ★★★ One page rather than 255 bytes exactly: the spare byte is free and a page
* boundary is one less thing to get wrong.
* ★★★★★ THE VISUAL PLANE HERE IS THE DISPLAY, SO A PIXEL GOES IN BOTH NIBBLES [T-P0-109].
* CP_VIS is FB_BASE is MAP_PHASE_WIN -- the CoCo3 framebuffer, mode 2, two screen pixels per byte.
* Every other writer in this probe already doubles: pic_core's scr_dbl, p3_clear_planes' $FFFF,
* text.s's 4-bytes-per-char blit. **The compositor did not, and every sprite pixel was half black.**
* ★★★ comp_probe does NOT define this: its plane is a scratch buffer compared one byte per pixel
* against a reference in the oracle's _gameScreen format, and nothing displays it.
VIS_DOUBLED     equ     1
COMP_ROW_PULL   equ     1
CP_CEL          equ     MAP_RESERVED_END-256    ; ★ $5F00. ONE ROW; VC_ROW_MAX is the format's max
                endc

* ★★★ PIC_DATA IS THE ARENA, NOT A POKED BUFFER -- this is AC-2's "real path" in one line.
* pic_probe.s pokes the picture to a fixed $1200 window; here the PICTURE is fetched by
* (type, index) through res_core and lands at RES_SLOT, which is RES_ARENA, which the map
* points at MAP_ARENA_WIN. ★ res_core.s:46 keeps `RES_SLOT equ RES_ARENA` as a name "for AC-2",
* and this is the AC-2 it was kept for.
PIC_DATA        equ     MAP_ARENA_WIN

* ★★★★ THE SUBSTITUTION BUFFER GOES IN MAP_INPUT, AND THE REGION IS FREE FOR THE SAME REASON
* MAP_RESERVED IS: this probe has no input subsystem. memmap.inc gives MAP_INPUT $1C00-$2000 to
* get.string and the key decoder, neither of which is linked here.
* ★★★ It must be resident in EVERY phase, because tx_emit blits from it while slots 4-6 hold the
* framebuffer -- $1C00 is slot 0, which nothing remaps. That is the property that makes the flat
* window safe [vm_text_ops.s, hazard 1].
* ★ The size assertion is at the FOOT of this file, not here: TXT_PBUF_MAX is defined by text.s,
* which is included below, and lwasm needs a condition to be constant on pass 1.
                ifdef   P3B_NO_CEL
P3_PBUF         equ     MAP_INPUT
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE tx_msgptr DIFFERENTIAL RECORD [T-P0-087 §4A]. ONE routine, TWO callers: display
* substitutes correctly and print does not, so the arithmetic is not the suspect -- the INPUTS are.
* This holds one record per call at each site so they can be compared in a single run.
* ★★★★ IT LIVES IN MAP_INPUT's TAIL, NOT IN THE CODE REGION. p3b_text has 170 bytes of headroom to
* P3_FONT and this needs more than that; $1C00+576 leaves 448 bytes of MAP_INPUT unused, in slot 0,
* resident in every phase -- which is also what makes it safe to write from inside a draw phase.
* ★★★ DIAGNOSTIC ONLY, behind -DTX_MSGDIAG. It is not in the clean build and not in any gate row.
P3_TXDIAG       equ     MAP_INPUT+576           ; TXT_PBUF_MAX; asserted at the foot of this file
TXD_REC         equ     12                      ; bytes per record
TXD_EACH        equ     8                       ; records kept per site
* ★★ FIRST-N PER SITE, NOT A SHARED RING. The intro's display calls come first and the jumped
* room's print comes at cycle 8+, so one shared ring would fill with display and lose the case
* under test. Two sub-arrays guarantee the comparison this task exists to make.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FONT IS **NOT** AT MAP_FONT IN THIS PROBE, AND THE FIRST ATTEMPT PUT IT THERE.
* memmap.inc puts the authored font at MAP_FONT ($E0B8) in slot 7 -- correct for the ENGINE. This
* probe orgs the PARSER at $E000 (slot 5 is its priority slice, so the engine's vocabulary window
* is unavailable here), so $E0B8 is 184 bytes INTO parser code and the vocabulary follows at
* $E3BA. **Staging 2,048 bytes of font there overwrote the parser and the run hung in cycle 6.**
* ★★★★ Same class as CP_CEL [AD-179]: an ENGINE address reused by a probe whose own map already
* claimed it. memmap.inc's header says the harness keeps its own addresses, and twice now the
* thing that bit was taking an engine constant at face value inside a probe.
* ★★★ $5800 = MAP_RESERVED_END - 2048, the top of the reservation, above the code (which ends at
* $5597). It is in slot 2 -- engine code, never remapped -- so it is resident in both phases and
* the flat window (slots 4-6) does not disturb it, which is what a per-glyph fetch needs.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ 128 GLYPHS, NOT 256, AND THE CORPUS SAYS IT COSTS NOTHING [font_high_census.py].
* The message box would not fit: $2000-$6000 is 16,384 bytes against 14,384 of code plus a 2 KB
* font, 48 over. Halving the font buys 1,024.
* ★★★★ MEASURED BEFORE IT WAS DONE, over all nine pinned titles and 14,944 LOGIC messages:
*     Kingquest2   15 messages carry a glyph >= 128, all of them codepoint 255, in ONE logic
*     the other 8  ZERO
* and glyph 255 in the font we ship is `00 00 00 00 00 00 00 00` -- BLANK, byte-identical to
* space. So those fifteen characters are padding and the upper half of the font is otherwise
* untouched by this corpus.
* ★★★★★ WHICH IS WHY txt_blit FOLDS TO SPACE RATHER THAN MASKING TO 7 BITS. A mask sends 255 to
* 127, and glyph 127 is NOT blank (`00 10 38 6C C6 C6 FE 00`) -- fifteen blanks would become
* fifteen pieces of visible garbage. Folding renders 255 CORRECTLY, because space and 255 are the
* same glyph, and degrades any unseen high character to a blank instead of noise.
* ★★★ IT IS A FACT ABOUT THESE NINE TITLES, NOT ABOUT AGI [L-86]. A fan game or an unpinned
* release may use CP437 box-drawing; it would render as blanks. Inventory names and the
* vocabulary go through the same font and were NOT scanned -- the census is necessary, not
* sufficient, and its own header says so.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FULL 256-GLYPH FONT IS BACK [Jay's ruling]. The halving was never a design choice --
* it was 1,024 bytes bought to make the message box fit, and the census showed what it cost:
* **13 of 147 PC DOS AGI v2 FAN games use the upper half**, two of them heavily (groza 30,238
* high bytes, 0fb053 9,558). The nine pinned commercial titles are clean, but fan v2 games are
* PC DOS AGI v2 and are in scope.
* ★★★★ AND THE FREED KILOBYTE BOUGHT NOTHING ELSE. In the ENGINE's map the font lives at MAP_FONT
* ($E0B8) inside MAP_TABLES, which has ~5.7 KB unallocated; sound's budget is MAP_RESERVED's
* "parser + sound (floor 3,072)" and is a different region entirely. **The squeeze is p3b's own**,
* because this probe orgs the parser over MAP_FONT and relocates the font down here.
* ★★★ So the 54 bytes came out of tx_boxfill instead: the window-origin generality nothing used,
* and a shadow row variable that existed to preserve a value every caller overwrote.
* ★★★★★ AND IT FITS NOW, BECAUSE THE FONT WAS NEVER THE THING TO MOVE [T-P0-089].
* Two earlier attempts priced this as a byte hunt: 54 bytes, then 312, then 355 -- each measured
* against a code size that moved under it. ★★★★ **The question was wrong.** Region A holds DATA as
* well as code, and `vm_tables.s` is 626 bytes of pure table sitting in it. Relocated into the seed
* stack's measured slack -- 768 B reserved against a peak of 37 entries -- it drops P3_CODE_END
* from $5963 to $56EB and the full 2,048-byte font lands at $5800 with 277 bytes spare.
* ★★★ Jay asked "what lies below the code", and the answer was 1,660 bytes of stack reservation
* that two independent measurements -- the engine's own seed-stack note and this probe's stack
* low-water instrument -- had already shown nobody uses.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THE FONT HAS NOW LEFT REGION A ENTIRELY [T-P0-091]. P3_FONT is declared with the
* parser's buffers, in slot 7, which is where memmap.inc's MAP_FONT ($E0B8) always wanted it.
* ★★★★ WHAT CHANGED IS NOT THE FONT BUT WHAT WAS BEHIND IT. The block at line 241 recorded the
* obstacle exactly: "this probe orgs the PARSER at $E000 (slot 5 is its priority slice, so the
* engine's vocabulary window is unavailable here), so $E0B8 is 184 bytes INTO parser code and the
* vocabulary follows at $E3BA." **Both halves of that are now false.** The vocabulary rides slot 5
* through phase_vocab_in, which is exactly what memmap.inc's MAP_VOCAB says, and $E3BA upward is
* free. The font goes there and region A's ceiling stops being a font at all.
* ★★★ THE REASON THE OBJECTION DISSOLVED IS WORTH KEEPING: slot 5 was unavailable to a RESIDENT
* vocabulary because it is the priority slice in every DRAW phase. A WINDOW is only open during
* par_parse, which is in the VM phase, where slot 5 is not the priority slice. **Windowing removed
* the reason the probe could not use the engine's own address**, so the two maps converge here
* rather than diverging further.
TEXT_BOX        equ     1
* ★★★★★ AND THE COMMAND LINE [T-P0-092]. text.s's TEXT_PROMPT block is the port of
* text.cpp:720 promptKeyPress -- per-cycle, not blocking -- plus promptRedraw, the two
* input opcodes and the edit-cursor pair. It needs TEXT_BOX (txt_clearline is a tx_boxfill)
* and text.s asserts that rather than failing on an undefined symbol elsewhere.
* ★★★★ CONDITIONED EXACTLY AS TEXT_WIRED IS, AND THE FAULT ARM IS WHY. -DTEXT_MODELLED links
* text.s and declines to call the nine handlers, so it leaves TEXT_WIRED undefined -- and
* tx_window_enter / tx_window_exit live in vm_text_ops.s's wired branch. **A prompt in that arm
* would install two vectors to symbols that do not exist.** Mirroring the same condition keeps the
* two flags from drifting into a combination nobody built.
                ifndef  TEXT_MODELLED
TEXT_PROMPT     equ     1
                endc
P3_FONT_BYTES   equ     2048            ; ★ the staging length; p3b_run.lua reads this symbol
* ★★★★★ DECLARED HERE, WHICH IS EARLIER THAN IT READS. Both are `ifdef`-tested, and an `ifdef` is
* resolved WHEN THE LINE IS PARSED rather than when the symbol is finally known -- so a flag
* declared beside P3_VOCAB (line ~1600) would be invisible to the three sites that use it at
* lines 425, 630 and 750, and to mmu_phase.s's include at 1331. **A forward reference is fine in
* an operand and is not a flag**, which is the distinction that decides this placement.
* ★★★★ PHASE_VOCAB is mmu_phase.s's service switch; P3_VOCAB_WINDOWED is this probe's own use of
* it. Two names because they answer different questions -- does the ENGINE emit the routines, and
* does THIS PROBE call them -- and collapsing them would hide which side a future client changed.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DTEXT_VOCAB_FLAT MAKES ARM E A ONE-VARIABLE ARM [T-P0-095]. P6.39 narrowed the restart to
* the text configuration and showed it absent in the CEL build -- whose dictionary is flat -- but
* those two builds differ in five things, so "the window" was one candidate of five.
* ★★★★★ THIS FLAG REMOVES **ONLY** THE WINDOW. The text configuration keeps its relocated
* vm_tables.s, its 128-entry seed stack, its font address, its input.s and its four-slot text
* window; the dictionary moves to a fixed address and phase_vocab_in/_out are never called.
* ★★★ PHASE_VOCAB STAYS DEFINED, deliberately: phase_text_out restores slot 5 from ph_blk_slot5,
* so the routines and that byte must exist even when nothing maps a vocabulary. **Undefining it
* would have changed the text window too, which is the second variable this arm exists to avoid.**
* ★★ MEASUREMENT ONLY -- see the address note at P3_VOCAB. It is not a shipped configuration and
* no gate row uses it.
                ifndef  TEXT_VOCAB_FLAT
P3_VOCAB_WINDOWED equ   1
                endc
PHASE_VOCAB     equ     1
* ★★★★ PHASE_TEXT ENABLES mmu_phase.s's FOUR-SLOT TEXT WINDOW [T-P0-093]. Same guarding discipline
* as PHASE_VOCAB and for the same measured reason: mmu_phase.s is included unconditionally, so
* unguarded bytes there land in `p3b` and trip its CP_CEL assert.
PHASE_TEXT      equ     1
                endc

                org     MAP_CODE

p3b_entry:
                orcc    #$50
                lds     #MAP_HWSTACK
                jsr     HAL_sys_init
                sta     $FFDF                   ; all-RAM; sys.s:118-128 does not do this
                jsr     p3_zero
* ★★★★ vm_start, AND OMITTING IT PRODUCED A PLAUSIBLE WRONG RUN RATHER THAN A FAILURE.
* Without it the object table is never cleared, so every one of the 255 entries read fDrawn from
* uninitialised RAM: the staging array filled to its 16-sprite cap **every cycle**, the
* compositor then opened 16 garbage VIEW numbers, and the measured rate was 1.93 cycles/second.
* ★★★ None of that looked like a crash. It looked like a slow interpreter -- which is exactly
* the number this task exists to report, so it would have been reported [L-56: the first
* measurement of a new subsystem often measures the scaffolding].
* ★ vm_probe.s:126 calls it before its loop; copying the sequence rather than inventing one is
* what keeps this build's VM identical to the gated one.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ INSTALL THE WINDOW RESTORE. Jay, on the eye gate: "i don't see the box close, mame just
* ends." txt_close was a stub that clamped a value and returned, so the box stayed on screen.
* ★★★★ THE ORACLE NEEDS NO SAVED PIXELS -- it re-renders a rectangle of the game screen into the
* display screen [text.cpp:560-564]. Our game screen is the SHADOW plane and our display screen is
* the VISIBLE plane, and p3_present is already exactly that copy.
* ★★★★★ AND IT IS THE WHOLE PLANE, NOT THE BOX'S RECTANGLE -- A STATED DIVERGENCE, NOT AN
* OVERSIGHT [§2I]. The planes are mapped one 8,192-byte slice at a time and a 74x26 box straddles
* a slice boundary at 160 bytes per row, so a scoped copy needs per-row slice arithmetic that the
* full present does not. **Cost: 26,880 bytes of 16-bit moves, about 75 ms, once per window
* close.** For the box's own area the result is identical.
* ★★★ WHAT THE WIDER SCOPE COSTS, SAID PLAINLY: the compositor draws sprites onto the VISIBLE
* plane, so a full present erases them until the next cycle recomposites -- a one-cycle flicker
* that the oracle's rectangle would not produce outside the box. Room 101 stages one sprite and
* quits immediately, so this trigger cannot show it. **The scoped version is the follow-up.**
* ★★ Installed here rather than in text.s because the block model is this probe's, not the
* engine's; txt_restore is a vector for that reason.
* ★ Guarded: the cel configuration does not link text.s, so txt_restore does not exist there.
                ifdef   P3B_NO_CEL
                ldd     #p3_restore_box
                std     txt_restore
                endc
                jsr     vm_start
* ★★★★ ALLOCATE THE PHASE BLOCKS. mmu_phase.s declares ph_blk_pri / ph_blk_fb "filled at init by
* the allocator" and **nothing filled them** -- they were 0, so every phase_draw mapped BOTH
* slot 5 and slot 6 to physical block 0. The two planes landed on top of each other, and slot 5
* stayed at block 0 afterwards because phase_vm never restores it, so VM_OBJ read priority-plane
* bytes: the sprite count jumped from 0 on cycle 1 to the 16-sprite cap on every cycle after.
* ★★★ A declaration that says "filled at init" is not an initialisation, and nothing in the
* build objects to the difference.
* ★ Blocks 0-1 priority (13,440 B), 2-5 framebuffer (26,880 B). The host stages volumes from
* block 8 up, and $38-$3F are the CPU window, so 0-7 are free.
                clr     ph_blk_pri
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ T-P0-051: THE PICTURE RENDERS INTO A SHADOW AND IS BLITTED WHEN IT IS FINISHED.
* Jay watched the render happen -- strokes and floods appearing in resource order -- and ruled
* that the draw must not be visible. The ORACLE is the argument, not taste: Sierra's $E1B1 emits
* an ALREADY-RENDERED buffer at 24 cy/pixel with zero comparisons on pixel data [T-P0-019].
* **Render then present is what the original does.**
*
* ★★★★ THIS IS NARROWER THAN DOUBLE-BUFFERING AND DELIBERATELY SO. The picture render happens
* ONCE PER ROOM, so only the RENDER gets a shadow. Sprites still composite straight onto the
* visible plane with the same save-under §3.6 chose, and the compositing loop is untouched --
* which is §11's out-of-scope line and trigger 5's condition.
*
* ★★★ THE BLOCKS. Priority 0-1, shadow framebuffer 2-5, and the host stages volumes at 8-13 and
* 14-38 [measured from p3b_run.lua's own staging log]; $38-$3F is the CPU window. **40-43 are
* free**, so the visible plane costs four blocks nobody was using and moves no volume.
* ★★ p3b already exceeds 128 KB by staging 31 blocks of volumes, so §2K's 128 KB rule is not
* newly broken here -- it was never a 128 KB harness. Stated rather than assumed.
P3_BLK_SHADOW   equ     2               ; the picture renders here, unseen
P3_BLK_VISIBLE  equ     40              ; what the display shows and sprites composite onto
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE PRIORITY SHADOW [T-P0-112]. The visual plane has had a shadow since T-P0-051; the
* priority plane never did, and P6.57 found why: `ph_blk_pri` is written ONCE in the whole tree
* (`clr ph_blk_pri` above) and never redirected, while `ph_blk_fb` is redirected seven times.
* ★★★★ THE ASYMMETRY WAS NEVER ABOUT THE PLANES. The visual plane got a shadow because Jay
* watched a picture render and ruled the draw must not be visible. Nobody has ever watched the
* priority plane, so nobody asked for one -- and the defect that absence causes (a sprite
* destroys the depth data underneath it with nothing to restore from) is invisible for exactly
* the same reason.
*
* ★★★★★ THE BLOCKS ARE PROVEN FREE FROM THE ALLOCATOR, NOT FROM A COMMENT [dispatch §2(3)].
* Every stage manifest in build/vm_stage was read and the highest physical block any of the
* twelve staged titles reaches is 44 (Kingquest2: vol 2 at base 14, 247,952 B = 31 blocks,
* 14-44). MAME's coco3 driver declares `<ramoption name="512K" default="yes">` and no harness
* passes -ramsize, so blocks 0-63 exist and $38-$3F is the CPU window. **45-55 are free.**
* ★★★ AND THE SAME READ FOUND A LATENT COLLISION THAT IS NOT THIS TASK'S: Kingquest2 reaches
* 44, PoliceQuest1 and SpaceQuest-1 reach 40, and the VISIBLE PLANE IS 40-43. No arm stages
* those titles AND maps the visible plane today -- the 9-title sweep runs vm_probe.s, a
* different probe -- so it is unreachable rather than broken. **Nothing asserts that, which is
* P6.46's shape exactly.** Reported, not fixed here.
* ★★ OVERRIDABLE so the assertions below can be shown RED from the command line rather than by
* editing this file -- `-DP3B_FAULT_PRISHADOW=44` and `-DP3B_FAULT_PRISHADOW=55` each fire one.
                ifdef   P3B_FAULT_PRISHADOW
P3_BLK_PRISHADOW equ    P3B_FAULT_PRISHADOW
                else
P3_BLK_PRISHADOW equ    45              ; the priority plane's shadow: blocks 45-46
                endc
P3_BLK_PRISHADOW_N equ  2               ; 13,440 B packed needs two 8,192 B blocks
P3_BLK_PRI      equ     0               ; ★ the LIVE priority plane, blocks 0-1 -- what
                                        ;   `clr ph_blk_pri` above sets, named so the restore
                                        ;   can put it back after borrowing ph_blk_pri
P3_BLK_STAGE_MAX equ    44              ; measured, every manifest; see above
P3_BLK_CPUWIN   equ     $38             ; 56 -- the CPU's own window starts here
* ★★★★ ADJACENCY, ASSERTED AGAINST BOTH NEIGHBOURS. P6.46 cost eight tasks because two symbols
* sat in a window with nothing asserting it, and P6.47's answer was assertions against EVERY
* neighbour. Shown RED by setting P3_BLK_PRISHADOW to 44 and to 55 -- both fire [§2W].
                ifgt    P3_BLK_STAGE_MAX+1-P3_BLK_PRISHADOW
                error   "the priority shadow overlaps staged volume blocks -- the highest block any staged title reaches is P3_BLK_STAGE_MAX (Kingquest2, 14-44), so the shadow must start above it; re-measure every build/vm_stage/*/manifest.txt before lowering this"
                endc
                ifgt    P3_BLK_PRISHADOW+P3_BLK_PRISHADOW_N-P3_BLK_CPUWIN
                error   "the priority shadow reaches the CPU's own window at $38-$3F -- those blocks are not ours; 45-55 is the free range on a 512 KB machine"
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ p3_blk_vis IS DECLARED WITH p3_present, NOT HERE. The first version put its `fcb` between
* `clr ph_blk_pri` and the `lda` below -- i.e. IN THE INSTRUCTION STREAM -- so the 6809 executed
* the byte 40 as $28 (BVC) and the probe derailed before it ran. The tell was the harness never
* setting the video mode: its notifier waits on a cycle counter the guest never wrote.
* ★★★ Same class as the data-symbol-in-code defect this project has now hit three times
* [vm_icguard at the top of a cycle profile; PAL_READBACK aliasing the pic counters].
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ LOAD THE PALETTE. p3b DID NOT, AND AC-1 PASSED ANYWAY [T-P0-057].
* ★★★★ A write tap on $FFB0-$FFBF across a full run recorded 16 writes, every one of them from
* PC $C00F -- Disk BASIC's ROM -- and ZERO from this program. The three rooms Jay approved were
* coloured by p3b_show.lua asserting the table from the host on every frame. **The pass was real
* and its cause was outside the thing under test**, which is L-86's shape: picture 80 was clean
* for a reason nobody had checked, and this is the same error one level up.
* ★★★ NOT HAL_gfx_set_mode, deliberately. That would load mode 2's palette for us -- and also
* remap slot 6 to a GFX_DB block, tearing this probe's framebuffer slice out from under it
* [p3b_show.lua's header records exactly that hazard]. The palette is what is wanted; the MMU
* side effects are not.
* ★★ NO READBACK HERE, AND THE REASON IS A MEASUREMENT. This code region is $2000-$5300 and the
* build sits 27 bytes under it: the loader plus this call is 23 and fits, adding the readback and
* its call is 25 more and does not [content/agi_palette.s, AGI_PAL_READBACK]. **The palette is
* proved instead by a write tap on $FFB0-$FFBF**, which records this program's own stores and
* their values -- and is what found the absence in the first place.
* ★ Mode must be final before palette writes latch [gfx.s Constraint B]. The host sets mode 2
* before staging, so it is by the time this runs -- stated in the report's §7, not assumed.
*
* ★★★★★ THE CALL IS BELOW, AFTER THE PLANE IS BLACK, AND THE ORDER IS THE WHOLE POINT.
* ★★★★ Loading it HERE regressed the boot: Jay, on the first cold run, "i saw a bunch of garbage
* before the king's quest title screen". The host asserts sixteen BLACK entries before staging,
* which is what makes the load window invisible -- and this call replaced them with the real
* palette while the visible plane still held uninitialised RAM. **The screen was black because
* the palette was black, not because the plane was clear**, and installing real colours before
* clearing the plane is exactly how you find that out.
* ★★★ So the palette is installed LAST, after p3_black_visible has zeroed the plane it colours.
* Index 0 is $00 [content/agi_palette.s], so a zeroed plane is black under the real palette too --
* the screen never stops being black, and the transition is invisible rather than merely brief.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE VOCABULARY WINDOW, TESTED BY THE GUEST BEFORE ANYTHING IS STAGED INTO IT.
* $E000-$FEFF is above $8000 and vm_state.s records two tasks spent on a wrong mechanism read
* out of a HOST readback up there -- from the host, "MAME cannot see it" and "it is not RAM" are
* the same observation. The guest writes a walking pattern and reads it back ITSELF.
* ★★★ Run here, before the palette and before any staging, for the same reason vm_probe.s runs
* its arena test first: a test that runs after the thing it protects has been written is a test
* of the writing, not of the memory.
* ★★ It does not disturb either plane -- $E000-$FEFF is MAP_TABLES' region and neither plane
* lives there -- and p3_clear_planes / agi_pal_load follow it unchanged.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WINDOWED, THE WALK IS OVER $A000-$C000 AND THE MAPPING IS NOT OPTIONAL [T-P0-091].
* Slot 5 holds the VM OBJECT TABLE at this point -- vm_start ran fifty lines up and initialised
* 8,160 bytes there. **Walking $A000-$C000 without mapping the dictionary's block first would
* write a walking pattern over the object table**, and the symptom would be the sprite-count
* fault this file already records once (0 on cycle 1, pinned at the 16 cap thereafter).
* ★★★★ SO THE MAP/UNMAP IS PART OF THE TEST, NOT SCAFFOLDING AROUND IT. The walk now proves the
* BLOCK is RAM and that phase_vocab_in reaches it -- which is what staging needs to be true, and
* is strictly more than the flat version proved.
* ★★★ The block numbers are set HERE, before the first phase_vocab_in, rather than at the
* allocator above: ph_blk_pri/ph_blk_fb are plane blocks and these are not, and putting them
* beside the routine that first uses them is what keeps the next reader from assuming they are.
* ★★★★ ph_blk_slot5 IS SET WHENEVER THE PHASE SERVICE EXISTS, NOT ONLY WHEN THE VOCABULARY RIDES
* IT [T-P0-095]. phase_text_out restores slot 5 from that byte too, so a build with the text window
* and a FLAT dictionary would otherwise restore slot 5 to ZERO after every blit -- unmapping the
* object table permanently. **The flat measurement arm is exactly such a build**, and this is the
* line that keeps it a one-variable arm rather than a second defect.
* ★★ THE ORDER IS THE ORIGINAL ORDER, DELIBERATELY: vocab block first, then the slot-5 value. It
* emits the same four instructions the windowed build has always emitted, so `p3b_text` stays
* byte-identical and this measurement task re-baselines nothing.
                ifdef   P3_VOCAB_WINDOWED
                lda     #P3_BLK_VOCAB
                sta     ph_blk_vocab
                endc
                ifdef   PHASE_VOCAB
                lda     #P3_BLK_SLOT5
                sta     ph_blk_slot5
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE TEXT WINDOW's BLOCKS [T-P0-093]. Four contiguous blocks of the VISIBLE plane, and the
* two restore values for the slots it borrows on top of the phase machinery's own.
* ★★★★ THE RESTORE VALUES COME FROM THE BOOT MAP AND NOWHERE ELSE: p3b_run.lua pre-sets all eight
* slots to $38+i at load, and mmu_phase.s's contract keeps slots 3 and 4 there for the whole run
* apart from this window. So slot 3 is $3B and slot 4 is $3C -- **the same $3C vm_text_ops.s used
* to carry as TX_ARENA_HI**, now stated once, beside the slot-5 value it sits next to.
* ★★★ The registers are write-only, so these are the only record of what was mapped. A wrong value
* here unmaps the arena permanently and the next resource fetch reads framebuffer bytes.
                ifdef   PHASE_TEXT
                lda     #P3_BLK_VISIBLE
                sta     ph_blk_text
                lda     #$3B
                sta     ph_blk_slot3
                lda     #$3C
                sta     ph_blk_slot4
                endc
                ifdef   P3_VOCAB_WINDOWED
                jsr     phase_vocab_in
                endc
                ldx     #P3_VOCAB
p3_vt_wr:       tfr     x,d
                eora    #$5A
                eorb    #$A5
                stb     ,x+
                cmpx    #P3_VOCAB_END
                blo     p3_vt_wr
                ldx     #P3_VOCAB
p3_vt_rd:       tfr     x,d
                eora    #$5A
                eorb    #$A5
                cmpb    ,x+
                bne     p3_vt_bad
                cmpx    #P3_VOCAB_END
                blo     p3_vt_rd
                ldd     #0
                bra     p3_vt_done
p3_vt_bad:      leax    -1,x
                tfr     x,d
p3_vt_done:     std     P3_VOCAB_BAD
* ★★★★ AND PUT SLOT 5 BACK BEFORE ANYTHING READS THE OBJECT TABLE. The window is open for the
* walk and for par_parse and for nothing else; leaving it open here would hand vm_start's freshly
* initialised object table to the next reader as dictionary bytes.
                ifdef   P3_VOCAB_WINDOWED
                jsr     phase_vocab_out
                endc
* ★ par_vocab stays 0 until the host stages a dictionary; until then par_said's own guard makes
* the whole path inert, which is what every p3b run before this task effectively had.
                ldd     #0
                std     par_vocab
                clr     P3_FEED

                lda     #P3_BLK_VISIBLE
                sta     ph_blk_fb
* ★★★ CLEAR THE VISIBLE PLANE ONCE, HERE. Blocks 40-43 have never been written, so without this
* the display shows uninitialised RAM for the whole of the first room's ~7 s render -- a direct
* consequence of the shadow buffer, since the visible plane is no longer the one being drawn into.
* ★ ph_blk_fb is the visible plane at this point and p3_clear_planes resolves against it.
                jsr     p3_clear_planes
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THEN BLACK IT. p3_clear_planes writes WHITE, because white is what an AGI PICTURE
* is drawn onto -- fills are bounded by white, so the plane being rendered into must start white
* [pic_core.s]. ★★★★ THE VISIBLE PLANE IS NOT BEING RENDERED INTO. Since the shadow buffer
* landed it is only ever a destination for p3_present, so its initial contents are pure display
* state -- and a white screen is the wrong display state to sit on for the ~7 s of the first
* room's render. Jay: "i want video set and cleared to black as soon as possible after the load."
* ★★★ Black is index 0 and index 0 is $00 in agi_pal16 [content/agi_palette.s], so a zeroed plane is
* black under the real palette rather than only under a blanked one.
* ★★ This does NOT touch the shadow plane or the priority plane: the per-room clear in
* p3_room_check still whitens what the renderer draws on, so the renderer's contract is unchanged
* and every picture still gates byte-identical.
                jsr     p3_black_visible
* ★★★★★ NOW the palette, with the plane already black beneath it (see the block above).
                jsr     agi_pal_load
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE TEXT ENGINE'S POINTERS, SET ONCE AT INIT [T-P0-084d §5B]. text.s takes every base as a
* POINTER rather than inlining an address, so the probe says where things are and the engine does
* not need to know the map. ★★★ A pointer left at zero is not inert here: txt_printf would
* substitute from address 0, which is the HAL's direct page -- the same null-base read that walked
* the seed stack when par_vocab was zeroed [p3b_probe.s's CP_CEL collision]. They are set together
* so none can be forgotten individually.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ HAL_input_init, WHICH THIS PROBE HAS NEVER CALLED [T-P0-092]. input.s's header states the
* precondition in as many words: it "asserts PIA0 data-register access mode" -- CRA/CRB bit 2 = 1 --
* and HAL_key_scan reads $FF00/$FF02 assuming it. **p3b has called HAL_key_scan since P6.29c without
* it**, from print's wait loop, and got away with it because DECB leaves the PIA in data mode and
* nothing between the handover and the first scan puts it back.
* ★★★★ IT STOPPED BEING SURVIVABLE THE MOMENT A KEY HAD TO ARRIVE ON TIME. The wait loop polls
* continuously and a human holds ENTER for many frames, so an occasional missed scan is invisible.
* The command line polls ONCE PER CYCLE, and 180 cycles of posted characters delivered ZERO.
* ★★★ input_probe.s:95 RECORDED THIS EXACT FAILURE ALREADY -- "HAL_input_init FIRST, AND ITS
* ABSENCE COST THE FIRST RUN" -- in the probe that was built to gate the key decoder. **The lesson
* was written down in the file next door and this probe did not inherit it**, which is §2H's third
* check (grep the reports for the same subsystem) failing at the source level.
* ★★ input.s is SHARED and is included read-only; this calls it and changes nothing in it [§2M].
                ifdef   HAL_KEYBOARD
                jsr     HAL_input_init
                endc
* ★★ res_check's tables live in MAP_COVERAGE, which is not part of the poked image and therefore
* holds cold-boot RAM until this runs [T-P0-103].
                ifdef   RES_CHECKSUM
                jsr     res_ck_init
                endc
                ifdef   P3B_NO_CEL
                ldx     #P3_PBUF
                stx     txt_pbuf
                ldx     #P3_FONT
                stx     txt_font
                ldx     #VM_VARS
                stx     txt_vars
* ★★ The %-code bases this probe does NOT supply are left zero DELIBERATELY: logic 0's table
* (%g), the object names (%0), the parsed words (%w) and the string table (%s) need resolving
* work the title screen does not exercise. **If a title-screen message uses one, the eye gate is
* what will show it** -- and that is the right instrument for a substitution that renders wrong.
                ldd     #0
                std     txt_l0base
                std     txt_curbase
                std     txt_objbase
                std     txt_wordbase
                std     txt_strbase
                clr     txt_l0n
                clr     txt_curn
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE COMMAND LINE'S THREE VECTORS [T-P0-092]. text.s owns the editor and knows nothing
* about MMU slots or about the parser; the probe supplies all three, exactly as it already
* supplies txt_restore and txt_emit.
* ★★★★★ txt_parse IS THE ONE THAT MATTERS. text.cpp:789 calls parseUsingDictionary from inside
* promptKeyPress, so ENTER is a second consumer of the parser -- and the dictionary rides an MMU
* window only this file knows how to open [P6.36]. Pointing the vector at p3_parse_line means the
* probe still has exactly ONE `jsr par_parse`, with the bracket inside it.
* ★★★★ txt_winon/off ARE NOT DECORATION EITHER: tx_window_enter maps the framebuffer across slots
* 4-6, and slot 5 is the vocabulary window. **The two mappings cannot both be open**, so the echo
* brackets its own blit and the ENTER path parses first and redraws second -- which is also the
* oracle's order at text.cpp:782-793.
* ★★★★★ THE DEFAULT TEXT ATTRIBUTE, WHICH NOTHING EVER SET [text.cpp:46, T-P0-093]. TextMgr's
* constructor calls `charAttrib_Set(15, 0)` -- white on black -- and this port left txt_fg and
* txt_bg at zero until something drew. **The command line clears its row to txt_bg**, so before
* anything else had drawn, the prompt row came up in colour 0's background by accident rather than
* by decision, and after a message box it came up white.
* ★★ B = 0 takes txt_attrib's `ta_plain` arm, which is the (15, 0) the oracle's constructor means.
                lda     #15
                clrb
                jsr     txt_attrib
                ifdef   TEXT_PROMPT
                ldd     #p3_parse_line
                std     txt_parse
                ldd     #tx_window_enter
                std     txt_winon
                ldd     #tx_window_exit
                std     txt_winoff
                endc
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ CLOCK CALIBRATION — A GUARD, NOT A DECORATION, AND ITS ABSENCE COST THIS TASK ITS
* HEADLINE. p3b_run.lua printed "@ 1.789390 MHz" as a hardcoded string while the machine ran at
* 0.894 MHz, because the flag set omitted -DHAL_SYS_FAST_CLOCK. **Every stage was wrong by
* exactly 2.003x and the label said otherwise**, which would have reported a 33% shortfall
* against the corpus's 10 cycles/second and handed Jay a cycle-rate decision that was really a
* missing -D [L-57: state the clock -- and MEASURE the thing you state].
* ★★★★ Exactly 20,000 iterations of an 8-cycle body: `leax -1,x` is 5 (indexed, 5-bit offset)
* and `bne` is 3 = 160,000 cycles, plus ~9 for setup and the final untaken branch. The host
* stamps both markers and divides, so the clock is DERIVED from the machine rather than asserted
* about it. Same construction pic_probe has carried since T-P0-012.
* ★★★ Once, at boot: the SAM speed bit does not change under us, and paying 160,000 cycles per
* cycle would distort the very budget this exists to protect.
* ★★ Markers 11/12 -- 1..10 are the per-stage brackets.
                lda     #11
                sta     P3_PHASE
                ldx     #20000
p3_cal:         leax    -1,x
                bne     p3_cal
                lda     #12
                sta     P3_PHASE
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ TURN THE VBL INTERRUPT ON -- HERE, AND NOWHERE EARLIER [Jay's ruling, after P6.31].
* P6.31 measured hal_frame frozen at 0 for the life of every run: irq_vbl.s supplies the handler
* and NOTHING had ever installed it, so print's wait loop could not see a tick and var 21 could
* never expire. This is the two instructions that fix that, and they are POP's [loader.s:119-120],
* not invented here -- §2L: "vector installation is sys.s and time.s, both SHARED, both already
* solved. Do not re-derive them."
*
* ★★★★★ THE PLACEMENT IS THE WHOLE SAFETY ARGUMENT. Four things had to be true:
*   1. AFTER THE CLOCK CALIBRATION, which is the two instructions above. p3_cal times a known
*      160,009 CPU cycles to DERIVE the machine clock; an IRQ landing inside it adds cycles the
*      calibration cannot see, so CLOCK would read low and the run would report "SLOW CLOCK --
*      missing -DHAL_SYS_FAST_CLOCK" about a build that has it. **Enabling one instruction earlier
*      corrupts a measurement rather than crashing, which is the worse failure.**
*   2. AFTER HAL_sys_init and the graphics init. gfx.s already writes $FF90=$6C with IEN=1 (its
*      "IEN PRESERVATION NOTE"), so whichever of the two runs last, IEN survives. That ordering
*      hazard is already solved in the shared HAL and is not ours to re-solve.
*   3. HAL_time_init PATCHES $010C BEFORE ANY SOURCE IS ENABLED, and enables GIME sources while
*      IEN=0 (time.s steps 2-4). So no interrupt can be taken against an unpatched vector -- which
*      is the "PC into lala land" case, and the HAL already closes it.
*   4. CC.I STAYS SET UNTIL THIS andcc. HAL_time_init deliberately does not clear it (time.s step
*      5, the E1.c invariant), so the CPU cannot take an interrupt until this exact instruction.
*
* ★★★★ THE HANDLER IS ALWAYS MAPPED, which is the other half of "PC into lala land". It assembles
* into MAP_CODE ($2000-$5FFF) = MMU slots 1-2, and mmu_phase.s's contract is that slots 0-4 and 7
* are set once at init and never touched; the phase machinery owns 5-6 and the text blit borrows 4.
* $010C, the stack and hal_frame's DP bytes ($10/$11) are all in slot 0. **Nothing the handler
* touches can be paged out under it.**
*
* ★★★ THE STACK COST IS 12 BYTES, ONCE. A 6809 IRQ stacks the full machine state and the handler
* RTIs without re-enabling, so frames never nest. MAP_HWSTACK is $0800 and the seed stack ends at
* $0500; the harness now samples S every frame and reports the low-water mark, because "it should
* fit" is not a measurement [Jay's warning; §2W].
*
* ★★ OPT-IN, SO `p3b` IS UNTOUCHED. The cel configuration is purpose=timing and an interrupt every
* 16.667 ms would move every figure in that row. -DP3B_IRQ is added to the text arms only, and
* `p3b` stays byte-identical at 58AD3C27.
                ifdef   P3B_IRQ
                jsr     HAL_time_init           ; $010C <- hal_vbl_handler; VBORD on; IEN on
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND RESTORE THE FIRST HOP, WHICH HAL_time_init DOES NOT KNOW ABOUT. **This is what the
* first attempt was missing, and it crashed exactly as Jay predicted: S=$F41C, PC looping in
* $D7F4-$D7F7, every downstream number garbage.**
* ★★★★★ THE CHAIN IS TWO HOPS, MEASURED AT THE DECB PROMPT:
*     $FFF8 -> $FEF7   holds `16 02 12` = LBRA, and $FEFA+$0212 wraps to $010C
*     $010C            holds `7E D8 AF` = JMP into DECB's own handler
*   HAL_time_init patches the SECOND hop only [time.s step 2], which is correct on a machine whose
*   $FExx page is still the one the ROM set up.
* ★★★★★ THIS PROBE'S MMU REMAP DESTROYS THE FIRST HOP. Read after takeover with IRQs still
*   masked, $FEF7 holds `52 5D 5C 5F 5E` while $010C is still intact -- so it is the REMAP that
*   breaks it, not the crash. Without this, the CPU vectors into whatever slot 7 now holds.
* ★★★ A DIRECT JMP, not a rebuilt LBRA: one hop instead of two, and it cannot be wrong about a
*   branch offset that has to wrap through $FFFF to be correct. $010C stays patched by the HAL and
*   is simply no longer traversed -- harmless, and it keeps the shared contract untouched.
* ★★ 3 bytes, inside the 16 reserved out of the vocabulary window (see P3_VOCAB_END).
                lda     #$7E                    ; JMP
                sta     $FEF7
                ldx     #hal_vbl_handler
                stx     $FEF8
                andcc   #$EF                    ; opt in -- CC.I clear, IRQs live from here
                endc
p3_loop:
                clr     P3_GO
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ LATCH A KEY WHILE PARKED, AND THIS IS A HARNESS MECHANISM STANDING IN FOR A QUEUE THE
* PORT DOES NOT HAVE [T-P0-092]. The oracle's key dispatch drains an event QUEUE filled
* asynchronously [cycle.cpp:350]; HAL_key_scan reads the matrix STATE at one instant, and
* p3_poll_key reads it once per cycle.
* ★★★★★ MEASURED, NOT REASONED: with the host posting a character every park and natkeyboard's
* queue drained each time, **180 posts delivered ZERO keys.** It is not bad luck -- a posted
* keypress is down for two or three frames and the guest's single poll comes twelve frames later,
* so it misses EVERY time. The first three explanations (throttling, a missing HAL_input_init, a
* slow post) were each tested and each wrong.
* ★★★★ A HUMAN IS NOT AFFECTED THE SAME WAY and that is the distinction this note exists to draw:
* a finger holds a key for tens of frames, so the once-per-cycle poll catches it -- which is why
* print's ENTER dismissal has worked under the eye gate since P6.33 with no latch at all.
* ★★★ SO THE PORT's REAL LIMIT IS A FAST TYPIST, not a broken matrix, and the engine-level answer
* is a key queue or a VBL-driven latch. Neither is this task [§22.5], and neither belongs in the
* SHARED interrupt handler. **This latch lives in the probe's own park loop, which is a harness
* construct with no counterpart in a shipped interpreter** -- stated so nobody reads it as the
* engine having solved the problem.
                ifdef   TEXT_PROMPT
p3_wait:        jsr     p3_key_latch
                lda     P3_GO
                beq     p3_wait
                else
p3_wait:        lda     P3_GO
                beq     p3_wait
                endc
                lda     P3_MODE
                cmpa    #1
                beq     p3_do_cycle
* ★★★ MODE 4 = SWEEP [T-P0-103]. The probe is host-driven and has no end of its own -- the host
* simply stops parking it -- so the end-of-run sweep is a MODE the host asks for on the last park,
* not something the guest can decide to do. ★★ Mode 1 was the only mode; 4 is chosen rather than 2
* so a stale byte from an older host cannot select it by accident.
                ifdef   RES_CHECKSUM
                cmpa    #4
                beq     p3_do_sweep
                endc
                bra     p3_loop

                ifdef   RES_CHECKSUM
p3_do_sweep:    jsr     res_ck_sweep
                clr     P3_MODE
                bra     p3_loop
                endc

* ── one interpreter cycle: VM, then render if the room changed, then composite ───
* ★★★ THE ORDER IS THE PHASE DISCIPLINE AND EVERY LINE OF IT IS LOAD-BEARING:
*   phase_vm          no plane mapped; slot 6 is the volume window
*   p3_run_vm         the interpreter -- may change the room, may fetch resources
*   p3_stage_sprites  slot 5 still holds VM_OBJ, so copy the sprite fields out NOW
*   p3_room_check     fetches in the VM phase, then enters the draw phase itself if it renders
*   phase_draw_enter  idempotent: the pair, exactly two MMU writes
*   p3_composite_all  planes mapped; cels decoded from the arena, which is resident in both
* ★★ p3_room_check is AFTER staging because it may switch phase, and staging must not be split
* across a remap.
p3_do_cycle:
* ★★★★★ p3_zero_timers IS GONE, AND THIS FILE'S OWN HEADER IS THE EVIDENCE [T-P0-084g §4B].
* The block at P3_T_VM says it in as many words: "P3_T_VM..P3_T_RENDER have existed since P3b.1 and
* are ZEROED EVERY CYCLE AND NEVER WRITTEN -- declared, cleared, dead." Verified rather than taken
* on the comment's word [AD-95: a comment is not a producer]: the guest's ONLY reference to any
* P3_T_* was the `ldx #P3_T_VM` inside the clear itself, and the host defines the five addresses at
* p3b_run.lua:43 and never reads one.
* ★★★★ So this cleared 22 bytes nothing writes and nothing reads, every cycle. **Removing it is a
* dead-code deletion, not a behaviour change** -- there is no observer to change.
* ★★★ 14 BYTES, AND THEY PAY FOR THE DECODE. Route (b) costs 7 (2 in res_core.s, 5 here in
* vm_run.s) and this configuration had 1 spare against CP_CEL. §4A's decomposition found no padding
* anywhere in $2000-$5300 -- the largest single emission in the whole region is 8 bytes -- so a
* dead routine was the only structural saving available.
* ★★ The P3_T_* equs are KEPT: they document that MAP_STATUS+8..+27 is reserved and unused, which
* is worth more than the zero bytes deleting them would save.
                jsr     phase_vm                ; ★ AC-7: no plane mapped
* ★★★★ RESTORE SLOT 5 TO THE OBJECT TABLE, AND THIS IS A GAP IN THE ENGINE'S PHASE MODEL.
* mmu_phase.s's phase_vm touches slot 6 ONLY, and says so deliberately: *"SLOT 5 IS LEFT ALONE,
* NOT CLEARED... the VM phase is defined by what it does NOT touch."* That is correct for a VM
* phase in which slot 5 holds nothing.
* ★★★ But P6.1's map put VM_OBJ in slot 5 precisely BECAUSE it is idle during draw -- so the two
* decisions, each sound alone, leave the object table unmapped after the first draw phase.
* VM_OBJ then reads priority-plane bytes: **the sprite count went 0 on cycle 1 and pinned to the
* 16-sprite cap on every cycle after**, which reads as "lots of sprites" rather than as a fault.
* ★★ Fixed here in the harness rather than in mmu_phase.s: the engine needs a ph_blk_obj and a
* phase_vm that restores it, and that is a design change to report, not to slip into this task.
* ★★★★★ AND T-P0-091 IS THE TASK THAT MADE IT ITS BUSINESS. mmu_phase.s now holds ph_blk_slot5
* and phase_vocab_out, because windowing the vocabulary is the first thing that unmaps slot 5
* mid-phase and the restore had to live somewhere. **The literal `lda #$3D` is gone and this
* probe no longer writes an MMU register anywhere** -- one sanctioned owner, in fact and not only
* in the engine's scan scope [§2N].
* ★★★ The cel configuration has no phase_vocab_out (P3_VOCAB_WINDOWED is undefined there), so it
* keeps the two-instruction literal and stays byte-identical.
                ifdef   P3_VOCAB_WINDOWED
                jsr     phase_vocab_out
                else
                lda     #$3D                    ; the block the host pre-set slot 5 to at boot
                sta     MMU_SLOT5
                endc
* ★★★ INVALIDATE THE VOLUME WINDOW'S CACHE. phase_vm writes slot 6 directly, but res_core tracks
* what it believes is mapped in res_curblk and SKIPS the write when it matches -- so after a
* phase change it would read the wrong block while being certain it had the right one.
* ★★ The two owners of $FFA6 have to agree, and the phase machinery is the one that moved it.
                lda     #$FF
                sta     res_curblk
* ★★★ AC-5's brackets. One `sta` per boundary; the host tap does the arithmetic. Placed around
* the calls rather than inside them so a stage's cost includes its own call overhead, which is
* what a budget consumer cares about.
* ★ p3_run_vm emits 1/2 (pace) and 3/4 (interpret) itself; the outer stages continue from 5.
                jsr     p3_run_vm
                lda     #5
                sta     P3_PHASE
                jsr     p3_stage_sprites        ; ★ BEFORE the remap -- slot 5 still holds VM_OBJ
                lda     #6
                sta     P3_PHASE
                lda     #7
                sta     P3_PHASE
                jsr     p3_room_check           ; fetch in VM phase, render in draw phase
                lda     #8
                sta     P3_PHASE
                jsr     phase_draw_enter        ; ★ AC-7: the pair, exactly two MMU writes
                lda     #9
                sta     P3_PHASE
* ★★★★★ BEFORE THE COMPOSITE, NEVER AFTER [T-P0-112]. This puts back what LAST frame's sprites
* covered, from the shadow planes. Run after compositing it would erase what was just drawn --
* which is the one ordering in this change that cannot be got wrong and is therefore stated at
* the call site as well as at the routine.
* ★★ Guarded: the routine exists only in the cel arm, and the text arms' binaries must not move.
                ifndef  P3B_NO_CEL
                ifndef  P3B_FAULT_NORESTORE
                jsr     p3_restore_prev
                endc
                endc
                jsr     p3_composite_all
                lda     #10
                sta     P3_PHASE
                ldd     P3_CYCLE
                addd    #1
                std     P3_CYCLE
                bra     p3_loop

p3_zero:
* ★ FROM +2, NOT +4. P3_ERR is MAP_STATUS+3 and was never cleared, so a diagnostic run reported
* "err 255" -- not a RES_E_* code at all, just uninitialised RAM reading as a failure. A status
* byte the host prints must be initialised by the guest that owns it.
                ldx     #MAP_STATUS+2
                ldb     #32
p3_z1:          clr     ,x+
                decb
                bne     p3_z1
                rts


* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE CYCLE GLUE. This is what P3b.1 could not build because the phase did not fit.
*
* ★★★ THE PHASE SPLIT IS THE DESIGN, NOT AN OPTIMISATION. VM_OBJ lives in slot 5, which becomes
* the PRIORITY SLICE during a draw phase -- so the object table is NOT addressable while
* compositing. Everything the compositor needs is therefore copied out BEFORE the remap, into a
* staging array that lives in always-resident memory.
* ★★ What is NOT staged: the cel pixels. The VIEW resource lives in the arena (slots 3-4), which
* memmap.inc keeps mapped in BOTH phases, so a cel can be decoded during the draw phase from a
* resource that was fetched during the VM phase. **That is what keeps this at two remaps per
* cycle instead of two per sprite.**
* ═══════════════════════════════════════════════════════════════════════════════════════════

P3_SPR_MAX      equ     16              ; staged sprites; AGI draws far fewer per cycle
P3_SPR_SIZE     equ     6               ; x, y, prio, view, loop, cel

* ── p3_run_vm — one interpreter cycle, exactly as vm_probe drives it ─────────────
* ★ pace, interpret, post. Splitting pace from the cycle body is what makes cycle number and
* virtual time track each other [vm_cycle.s]; copying the sequence rather than inventing one
* keeps this build's VM identical to the gated one.
* ★★★★★ PACE AND INTERPRET ARE TIMED SEPARATELY, AND CONFLATING THEM INVERTED AC-5's ANSWER.
* vm_pace is a BUSY-WAIT: it spins on vm_step_clock until vm_passed reaches vm_tdelay, so time
* inside it is the interpreter deliberately hitting the rate the GAME asked for (var 10), not
* work. Timed as one "vm" stage it read 0.156 s/cycle and 6.66 cycles/second -- which looks like
* a capacity shortfall against the corpus's 10 and is nothing of the sort.
* ★★★★ **A budget that cannot separate waiting from working cannot answer "is it fast enough."**
* Split, the question becomes arithmetic: interpret is the capacity, pace is the gap between
* capacity and the requested rate.
p3_run_vm:
                lda     #1
                sta     P3_PHASE
                jsr     vm_pace                 ; BUSY-WAIT to the game's requested rate
* ★★★★ THE FEED, AT THE SAME SEAM AS vm_probe.s's vp_feed: after the pacing gate, after the
* previous cycle's vm_post_cycle resets, before the cycle body. cycle.py feeds immediately
* before interpret_cycle() for the same reason. ★★ Two probes, one seam -- if this one fed after
* the cycle instead, the eye gate and the byte gate would be testing different programs and only
* one of them would be the one that was gated.
                lda     P3_FEED
                beq     p3_nofeed
                clr     P3_FEED
                jsr     p3_feed
p3_nofeed:
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE TYPED PATH, AT THE SAME SEAM AND FOR THE SAME REASON [T-P0-092]. cycle.cpp:350-351
* polls `if (_text->promptIsEnabled()) _text->promptKeyPress(key)` inside the main cycle's key
* dispatch -- **once per cycle, not in a loop**, which is the whole shape difference from print's
* blocking window.
* ★★★★ IT SITS BESIDE THE SCRIPTED FEED RATHER THAN REPLACING IT, and the two are complementary
* by design: the host's feed writes P3_INBUF directly and **cannot exercise one instruction of the
* editor**, while this path cannot be driven from a script. §1.4 of the dispatch is right, and the
* gate rows are split the same way [gates.manifest: p3b_parse vs p3b_type].
                ifdef   TEXT_PROMPT
                jsr     p3_poll_key
                endc
                lda     #2
                sta     P3_PHASE
                lda     #3
                sta     P3_PHASE
* ★★ HALT DETECTION IS MISSING HERE AND vm_probe HAS IT (`lda vm_quit / bne vp_halted`). Adding
* it pushed the image 7 bytes past the code region, and taking those 7 bytes destabilised the
* run entirely -- so it is reported as a gap rather than carried. **A halted VM currently keeps
* being cycled by the host and reports plausible timings for doing nothing**, which is the same
* shape as the uninitialised object table and should be closed before AC-5 is trusted.
                jsr     vm_interpret_cycle
                jsr     vm_post_cycle
                lda     #4
                sta     P3_PHASE
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ p3_feed -- the same three side effects vp_feed publishes, and the same reason they are
* the CALLER's: cycle.py feed_input() sets ENTERED_CLI from the word count, always clears
* SAID_ACCEPTED, and writes VAR_WORD_NOT_FOUND **only when a word was not found**.
* ★★★ Duplicated from vm_probe.s rather than shared, and that is a cost worth naming: the two
* probes have disjoint maps (§2F is about addresses, and these are eleven instructions against
* two different buffer pairs). ★★ If a third client appears this belongs in src/engine/ beside
* parser.s -- recorded so the second instance does not quietly become three.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ TWO CALLERS NOW, ONE CALL SITE -- AND THAT IS T-P0-092's ANSWER TO §1.3 [P6.36 §7.2].
* The host's scripted feed and the command line's ENTER both need a parse, and P6.36 left the
* vocabulary bracket as a CONVENTION: two instructions around one `jsr`, with nothing asserting it.
* ★★★★★ A SECOND CALLER IS EXACTLY HOW A CONVENTION LIKE THAT DIES, so there is no second call.
* p3_parse_line holds the ONLY `jsr par_parse` in this probe and the bracket is inside it. **A third
* caller cannot get the bracket wrong because there is nothing for it to get wrong** -- it calls
* this, or it does not parse.
* ★★★★ THE ALTERNATIVE WAS TO PUT THE BRACKET INSIDE par_parse ITSELF, which would make the
* invariant structural for every client rather than for this probe. It is proposed in the report
* rather than taken here: parser.s is shared by four probes, three of which have no window and no
* phase_vocab_* symbol at all, so it needs the same -DPHASE_VOCAB treatment mmu_phase.s got and
* that is a change to gated engine source, not to harness glue [§22.5].
p3_parse_line:
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ REFUSE WITHOUT A DICTIONARY, AND THIS IS A REAL DEFECT THE TYPED PATH EXPOSED [T-P0-092].
* par_vocab is 0 until the host stages a WORDS.TOK, and the host stages one only when an input
* script is requested. **par_said has a guard for that and par_parse has none**: par_find computes
* `vocab + letter*2` from ADDRESS ZERO and walks the HAL's direct page and the seed stack for a
* terminator that is not there [the CP_CEL collision, L-86, this file's own history].
* ★★★★ IT WAS UNREACHABLE UNTIL NOW AND IS NOT ANY MORE. The scripted feed only fires when the
* host has a script, and a script implies a dictionary -- so the two always arrived together. **A
* typed line arrives from the keyboard and has no such pairing**, and the first typed run hung in
* cycle 27 for exactly this reason.
* ★★★ IT DOES NOT BLUNT THE FAULT ARM. p3b_nomap leaves par_vocab at $A000 and unmaps the block,
* so it still parses against the object table and still hangs; this refuses only the case where
* there is no dictionary anywhere, which is a configuration and not a fault.
* ★★★★ SCOPED TO THE COMMAND-LINE CONFIGURATION, AND THE FIRST VERSION WAS NOT -- it cost `p3b`
* six bytes and its byte identity, which is §6's own stop condition. The hazard is real in both
* builds and REACHABLE in only one: without the command line the sole caller is the scripted feed,
* which the host arms only when it has a script, and a script implies a staged dictionary.
                ifdef   TEXT_PROMPT
                ldd     par_vocab
                bne     ppl_have
                rts
ppl_have:
                endc
                ldx     #P3_INBUF
                stx     par_inbuf
                ldx     #P3_CLNBUF
                stx     par_clnbuf
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE WINDOW OPENS HERE AND SHUTS TWO INSTRUCTIONS LATER. This is the whole cost of
* windowing the dictionary: two MMU writes per TYPED COMMAND [T-P0-091]. par_said is outside the
* bracket on purpose -- memmap.inc: "ONLY par_parse NEEDS IT MAPPED... a game evaluating fifteen
* said() patterns a cycle needs the vocabulary mapped for none of them."
* ★★★★ EVERYTHING ELSE par_parse TOUCHES IS IN SLOT 0 OR SLOT 7 AND NEITHER MOVES: parser.s's
* code and state, par_inbuf and par_clnbuf (slot 7, $E000 up), the hardware stack and the direct
* page (slot 0). **par_parse calls nothing outside parser.s** -- par_clean, par_is_sep,
* par_is_inv, par_find, par_fi_cmp, par_fi_left, and that is the complete list.
* ★★★ -DP3B_VOCAB_NOMAP IS THE FAULT ARM AND IT DROPS THE `jsr phase_vocab_in`, NOTHING ELSE
* [§2W, L-73: one variable]. par_find then walks the object table as a dictionary and the words
* come back unknown, which is the observable p3b_run.lua reads back as par_egon/par_ego.
                ifdef   P3_VOCAB_WINDOWED
                ifndef  P3B_VOCAB_NOMAP
                jsr     phase_vocab_in
                endc
                endc
                jsr     par_parse
                ifdef   P3_VOCAB_WINDOWED
                jsr     phase_vocab_out
                endc
                lda     #FLAG_ENTERED_CLI
                ldb     par_cli
                jsr     vm_setflag
                lda     #FLAG_SAID_ACCEPTED
                clrb
                jsr     vm_setflag
                lda     par_notfound
                beq     p3_feed_nonf
                ldb     par_notfound
                lda     #VAR_WORD_NOT_FOUND
                jsr     vm_setvar
p3_feed_nonf:
                rts

* ★★ p3_feed is now the host-scripted ENTRY to that routine and nothing else. Kept as a name
* because p3_run_vm's `jsr p3_feed` reads as what it is -- the scripted stand-in -- and the typed
* path enters the same routine from txt_parse [see the vector install at init].
p3_feed         equ     p3_parse_line

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ p3_poll_key -- one key per cycle into the command line [cycle.cpp:350-351].
* ★★★★★ GUARDED ON promptIsEnabled, WHICH IS THE ORACLE'S OWN GUARD AND IS NOT A SHORTCUT. With
* the prompt disabled a keystroke must not reach the editor at all -- not merely go unechoed --
* because txt_pkey's ENTER arm parses, and a parse while the game has called prevent.input would
* set ENTERED_CLI for a line the game refused to accept.
* ★★★ P3_KEY publishes what was seen, so the host can assert that a posted key ARRIVED rather than
* inferring it from the screen. Without it a dead matrix and a dead editor look identical [§2W.3].
* ★★ VM_VAR_KEY is NOT written here. cycle.cpp does set var 19, but the opcodes that read it are
* not wired and writing it would be a side effect with no reader -- the shape mmu_phase.s's
* phase_vm note refuses for the same reason.
* ★★★ GUARDED, AND THE FIRST DRAFT GUARDED ONLY THE CALL. The cel configuration links neither
* text.s nor the keyboard HAL, so an unguarded body here is three undefined symbols -- and lwasm
* then reported the CP_CEL collision guard as well, from a pass that had already failed. **The
* second error named a region that was fine** (P3_CODE_END $52F8 against CP_CEL $5300, eight bytes
* spare, exactly as always), which is how a cascade sends the reading to the wrong place.
                ifdef   TEXT_PROMPT
* ★★★★ THE LATCH IS ONE BYTE DEEP AND IT DOES NOT OVERWRITE. A second key arriving before the
* cycle consumes the first is DROPPED rather than replacing it, which is the same thing a
* one-character queue does and is what keeps the order right: replacing would deliver the second
* character and lose the first, so a fast "lo" would read as "o".
* ★★★ It scans only while the prompt is enabled, so a disabled command line costs nothing and a
* stray key cannot sit latched across an accept.input.
p3_keybuf       fcb     0
p3_key_latch:
                lda     txt_penab
                beq     pkl_out
                lda     p3_keybuf
                bne     pkl_out                 ; one deep: do not overwrite an unread key
                jsr     HAL_key_scan
                tsta
                beq     pkl_out
                sta     p3_keybuf
pkl_out:        rts

* ★★ p3_poll_key takes the latched key first and falls back to a live scan, so a key held across
* the cycle boundary is still seen on a build where the park loop did not run (the first cycle).
p3_poll_key:
                lda     txt_penab
                beq     ppk_out
                lda     p3_keybuf
                beq     ppk_scan
                clr     p3_keybuf
                bra     ppk_have
ppk_scan:
                jsr     HAL_key_scan
                tsta
                beq     ppk_out
ppk_have:
                sta     P3_KEY
                inc     P3_NKEY
                jmp     txt_pkey
ppk_out:        rts
                endc

* ── p3_room_check — fetch and render the room's PICTURE when the room changes ────
* ★★★ THE FETCH RUNS IN THE VM PHASE AND THE RENDER IN THE DRAW PHASE, and they cannot be
* swapped. res_open needs the VOLUME window, which is slot 6; the renderer needs the FRAMEBUFFER
* slice, which is also slot 6. **The bytes bridge the two because they land in the arena, which
* is resident in both.** Getting this backwards is a remap per picture opcode.
p3_room_check:
* ★★★★ VAR 0, NOT vm_roomnr. VAR_CURRENT_ROOM is the room; `vm_roomnr` is a port-side shadow
* that only vm_new_room writes, and vm_new_room is only reached via the new.room COMMAND.
* ★★★ The oracle is in room 83 from cycle 0 -- checked, not assumed -- and our VM matches it on
* var 0 (that is what the nine-title gate compares). But vm_roomnr stayed 0 for 300 cycles, so
* the probe fetched PICTURE 0, got RES_E_EMPTY, and rendered nothing. **The room was right and
* the variable I read was not.**
                lda     VM_VARS+0
                sta     P3_ROOM                 ; ★ publish it: the host was reading a byte the
                cmpa    p3_lastroom             ;   probe never wrote, and reported room 0
                beq     prc_out                 ;   while the VM was elsewhere
                sta     p3_lastroom
* ── still in the VM phase: fetch the PICTURE by (type, index) ──
                lda     #RES_PICTURE
                ldb     p3_lastroom
                jsr     res_open
                lda     res_err
                bne     prc_fail
                ldx     res_base
                stx     p3_picptr
* ★ The step markers that localised the render hang lived here and are removed: they had done
* their job, and keeping them put the image 5 bytes over the code region -- which would have
* meant a fourth bite out of the parser/sound reservation to carry debug scaffolding.
* ── now the draw phase, and only now ──
* ★★★ RENDER INTO THE SHADOW. ph_blk_fb selects which four blocks every plane_win call and every
* phase_draw_fb resolves against, so pointing it at the shadow redirects the WHOLE render --
* clear, lines and fills -- with no change to pic_core. The visible plane keeps the previous
* room on screen throughout, which is the point.
                lda     #P3_BLK_SHADOW
                sta     ph_blk_fb
                jsr     phase_draw_enter
                jsr     p3_clear_planes
                ldx     p3_picptr
                stx     pic_ptr
                jsr     pic_render_at
* ★★★ AND NOW PRESENT IT: one copy per room, against a ~2.8 s render.
                jsr     p3_present
* ★★★★★ AND TAKE THE PRIORITY PLANE'S SHADOW, for the same reason and at the same moment
* [T-P0-112]. pic_render_at has just written the room's priority data into the live plane; from
* here until the next room change that data is the only record of what is underneath a sprite,
* and every sprite that draws destroys some of it. This is the copy that gives the restore a
* source. ★★ Once per room, against the same ~2.8 s render -- the same trade p3_present makes.
                ifndef  P3B_NO_CEL
                jsr     p3_pri_shadow
                endc
                jsr     res_close
                lda     #1
                sta     p3_drew
                rts
prc_fail:       lda     res_err
                sta     P3_ERR
prc_out:        rts

* ── p3_clear_planes — AGI's defaults: visual 15 (white), priority 4 (red) ────────
* ★★ NOT the HAL's clear. HAL_gfx_set_mode clears to palette index 0, which is correct for the
* HAL and wrong for an AGI picture [pic_core.s]. ★ The priority plane is PACKED, so the fill
* value is $44 and the length is halved -- the same pair of changes pri_clear needed in
* T-P0-034, and getting either alone wrong corrupts every other pixel.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ T-P0-050: THIS CLEAR WROTE THROUGH AN APERTURE IT DID NOT FIT IN, AND THE VISUAL HALF
* CLEARED TWO BYTES. Found by the EYE GATE, not by any byte gate: Jay watched the run and saw the
* room come up WIREFRAME -- lines drawn, fills absent. AGI's fills are bounded by white, so a
* visual plane that was never whitened gives the flood nothing to stop at.
*
* ★★★★ THE VISUAL HALF WAS AN ASSEMBLE-TIME CONSTANT OVERFLOW, silently truncated:
*     cmpx #FB_BASE+(PIC_W*PIC_H)   =  $C000 + $6900  =  $12900  ->  emitted as $2900
* Confirmed from the listing, not the arithmetic: `20ED 8C 29 00`. X starts at $C000, which is
* already above $2900, so `blo` failed on the FIRST pass and the loop stored once. **26,880 bytes
* of intended clear became 2.** lwasm emitted it without a diagnostic.
*
* ★★★ THE PRIORITY HALF DID NOT OVERFLOW AND WAS WRONG ANYWAY: $A000+$3480 = $D480 fits, but the
* priority aperture is $A000-$BFFF -- 8,192 bytes -- so it ran 13,440 and overran $C000..$D480,
* which is the FRAMEBUFFER window. It cleared part of the plane it had just been asked not to
* touch. (T-P0-034 fixed the fill VALUE and the LENGTH here; the APERTURE was the third term.)
*
* ★★★★★ WHY NO GATE CAUGHT EITHER. pic_probe's map is FLAT: FB_BASE $8000, so $8000+$6900 =
* $E900 -- no overflow -- and its plane is contiguous, so a flat clear is correct there. **The
* identical expression is right in pic_probe's map and wrong in p3b's**, and p3_clear_planes is
* p3b-local code that no gate builds. The renderer's 45/45 was re-run on the WINDOWED build this
* task and still passes, both planes: the renderer was never the defect.
*
* ★★ THE SHAPE OF THE FIX IS pic_probe.s:551-565's, which the 45/45 gate does cover -- walk the
* slices, mapping each through the phase entry points, and clear one aperture at a time. The
* slice counter lives in MEMORY because `ldd #$FFFF` destroys B [pic_probe.s:541-549: keeping it
* in B cleared slice 0 forever and left exactly 8,192 non-zero bytes].
* ★ Both planes need it here. pic_probe only windows the VISUAL plane (its priority plane is
* flat, hence its flat pri_clear); p3b holds BOTH in blocks -- priority 0-1, framebuffer 2-5 --
* so both walk.
* ═══════════════════════════════════════════════════════════════════════════════════════════
p3_cl_slice     fcb     0               ; the counter, in memory and not in B
p3_clear_planes:
* ---- visual: 26,880 B across four 8,192 B slices (blocks 2-5 = 32,768; the tail is spare) ----
                clr     p3_cl_slice
p3_cv_slice:    lda     p3_cl_slice
                jsr     phase_draw_fb           ; map slice A into the framebuffer window
                ldx     #FB_BASE
                ldd     #$FFFF                  ; visual 15, both nibbles (the pixel doubling)
p3_cv:          std     ,x++
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ P3B_FAULT_CLEAR — THE HISTORICAL DEFECT, RESTORABLE ON DEMAND [T-P0-054 AC-4].
* ★★★★ A gate is only worth its green if a known-bad build turns it red, and this project has
* twice published a clean gate that was measuring nothing [P4.7's inert fault injection, P3b.15's
* three inert windowed runs]. The way to not repeat that is to keep the FAULT, not the memory of
* it: the exact expression that shipped, behind a flag, so the check is re-runnable by anyone.
* ★★★ Under -DP3B_FAULT_CLEAR this restores the assemble-time constant overflow verbatim --
*     $C000 + $6900 = $12900, silently truncated by lwasm to $2900, with X starting at $C000 --
* so `blo` fails on the first pass and 26,880 bytes of intended clear become 2. **lwasm emits it
* without a diagnostic, which is the whole reason it survived to the screen.**
* ★★ NOT reachable by accident: no default build defines this, and the artifact it produces is
* written to a different filename so it can never be mistaken for the shipped probe.
                ifdef   P3B_FAULT_CLEAR
                cmpx    #FB_BASE+(PIC_W*PIC_H)  ; ★ THE DEFECT: overflows to $2900
                else
                cmpx    #FB_BASE+8192           ; ★ ONE APERTURE, not the whole plane
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                blo     p3_cv
                inc     p3_cl_slice
                lda     p3_cl_slice
                cmpa    #4
                blo     p3_cv_slice
* ---- priority: packed, 13,440 B across two slices (blocks 0-1 = 16,384; the tail is spare) ----
                clr     p3_cl_slice
p3_cp_slice:    lda     p3_cl_slice
                jsr     phase_draw_pri          ; map slice A into the priority window
                ldx     #PRI_BASE
                ldd     #$4444                  ; four packed pixels of priority 4
p3_cp:          std     ,x++
                cmpx    #PRI_BASE+8192
                blo     p3_cp
                inc     p3_cl_slice
                lda     p3_cl_slice
                cmpa    #2
                blo     p3_cp_slice
* ---- restore the canonical draw-phase pair, and invalidate the slice caches ----
* ★★ The walk left slot 5 and slot 6 on the LAST slice of each plane, which is not what the
* caller's phase_draw_enter established. plane_win.s caches which slice each plane has mapped,
* so both the register and the cache have to be put back [phase_draw_enter's own note].
                clra
                jsr     phase_draw
* ★★★ COUNT THE REMAPS RATHER THAN LET AC-6's FIGURE QUIETLY UNDER-REPORT. This clear performs
* eight MMU writes -- four framebuffer slices, two priority slices, and the restoring pair -- and
* they are real. **P3_REMAPS is "two per phase transition"; these are not phase transitions**, so
* they are added here and the per-room-change cost is visible instead of missing.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ BLACK THE TEXT STRIP, BECAUSE THE PICTURE IS 168 ROWS AND THE DISPLAY IS 200 [T-P0-093].
* ★★★★★ THE WHITE FILL ABOVE IS RIGHT AND ITS EXTENT WAS NOT. AGI fills are bounded by white, so
* the plane a PICTURE is rendered into must start white -- but a PICTURE is 160x168 = 26,880
* bytes, and this walk whitens four whole 8,192-byte slices = 32,768. **The 5,120 bytes past the
* picture are the text area at the bottom of the screen, and they were being painted white and
* then carried to the visible plane by p3_present, which copies all four slices.**
* ★★★★ IT WAS INVISIBLE UNTIL THIS TASK. Nothing ever drew below row 20, so a white strip under
* the picture looked like part of the border. The command line put characters on row 22 and Jay
* saw it at once: *"the rows above and below are white and make it look off."*
* ★★★ SLICE 3, FROM OFFSET 2,304. 26,880 - 3*8,192 = 2,304, so the picture ends 2,304 bytes into
* the last slice and everything above that is text area. Blacking to the end of the aperture
* covers pixel rows 168-204; the display shows 200 and the rest is spare.
* ★★ Scoped to the text configuration: `p3b` is purpose=timing and byte-identical is its contract,
* and the cel build draws no text at all, so the strip's colour is not observable there.
                ifdef   TEXT_PROMPT
                lda     #3
                jsr     phase_draw_fb
                ldx     #FB_BASE+2304
                ldd     #$0000
p3_cv_tail:     std     ,x++
                cmpx    #FB_BASE+8192
                blo     p3_cv_tail
                ldd     P3_REMAPS
                addd    #1
                std     P3_REMAPS
                endc
                ldd     P3_REMAPS
                addd    #8
                std     P3_REMAPS
                ifdef   PLANE_WINDOWED
                jsr     plane_reset
                endc
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ p3_black_visible — fill the VISIBLE plane with index 0. Called once, at init.
*
* ★★★ Same slice walk as p3_clear_planes' visual half and for the same reason: FB_BASE+26,880
* does not fit the 8,192-byte aperture, and the constant that expresses it overflows to $2900
* [AD-111 -- the clear that cleared two bytes]. **One aperture at a time, counter in memory
* because `ldd` destroys B.**
* ★★ ph_blk_fb must already name the VISIBLE plane when this is called. It does at init; it
* would not during a room render, which is why this has no business being called from anywhere
* else and is not.
* ★ Four slices of $0000 = 32,768 bytes, ~0.09 s once. It is not on any per-room path.
p3_bv_slice     fcb     0
p3_black_visible:
                clr     p3_bv_slice
p3_bv_next:     lda     p3_bv_slice
                jsr     phase_draw_fb           ; map slice A into the framebuffer window
                ldx     #FB_BASE
                ldd     #$0000                  ; index 0, both nibbles (the pixel doubling)
p3_bv:          std     ,x++
                cmpx    #FB_BASE+8192
                blo     p3_bv
                inc     p3_bv_slice
                lda     p3_bv_slice
                cmpa    #4
                blo     p3_bv_next
* ★★ Restore the canonical draw-phase pair and invalidate plane_win.s's slice caches -- the walk
* left slot 6 on the LAST slice, which is not what the caller established [phase_draw_enter].
                clra
                jsr     phase_draw
                ldd     P3_REMAPS
                addd    #5                      ; four slice maps plus the restoring pair's fb half
                std     P3_REMAPS
                ifdef   PLANE_WINDOWED
                jsr     plane_reset
                endc
                rts
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ p3_present — copy the finished picture from the shadow to the visible plane.
*
* ★★★ ONE COPY PER ROOM. The render is ~2.8 s; this is 26,880 bytes moved once at the end of it.
* It is not a per-frame cost and it is not double-buffering: the compositor keeps writing the
* visible plane directly, every cycle, exactly as before [§3.6's save-under is untouched].
*
* ★★★★ IT BORROWS SLOT 5, WHICH HOLDS THE PRIORITY PLANE, AND THAT IS SAFE ONLY BECAUSE OF WHEN
* IT RUNS. The picture is finished and the sprites have not started, so nothing reads priority
* across this call -- the same argument mmu_phase.s makes for the fill's straddle borrow, and it
* has to be made explicitly here because the borrow is longer.
* ★★ The restore below puts slot 5 back and invalidates plane_win.s's caches, because **a cache
* of a register's contents is wrong the moment anyone else writes that register**.
*
* ★ The slice counter is in memory: `ldd` destroys B, which cost pic_probe a whole gate run
* [pic_probe.s:541-549].
* ★ Both bytes live HERE, after a `rts` and before the entry label, so nothing falls through them.
p3p_slice       fcb     0
p3_blk_vis      fcb     P3_BLK_VISIBLE  ; the harness display reads this; it never moves
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ p3_restore_box -- close the message window by re-rendering ITS RECTANGLE, shadow -> visible.
* This replaces a whole-plane p3_present [fc2389e], which worked and restored 26,880 bytes to fix
* about 1,900 of them.
* ★★★★ THE ORACLE'S MODEL, AND IT NEEDS NO SAVED PIXELS: "the window is closed by RE-RENDERING a
* rectangle of the game screen into the display screen. There is no save-under buffer anywhere"
* [text.cpp:560-564, this project's own oracle instrumentation]. Our game screen is the SHADOW
* plane and our display screen is the VISIBLE plane.
* ★★★★★ WHY THE WHOLE-PLANE VERSION HAD TO GO: the compositor draws sprites onto the VISIBLE
* plane, so re-presenting all of it erases every sprite until the next cycle recomposites -- a
* one-cycle flicker outside the box that the oracle never produces. Room 101 quits immediately and
* could not show it; a room with moving sprites would.
*
* ★★★★ PER ROW, NOT PER SLICE, AND THE ARITHMETIC IS WHY. Planes are mapped 8,192 bytes at a time
* and a row is 160 bytes, so a slice boundary falls mid-row (51.2 rows per slice). Iterating rows
* and mapping each row's slice costs ~2 remaps per row -- about 52 for a 26-row box against
* p3_present's 8 -- but copies ~1,900 bytes instead of 26,880. **Remaps are 7 cycles; the copy is
* the whole cost**, so this is ~6x cheaper overall and far simpler than per-slice row clipping.
* ★★★ THE STRADDLE IS HANDLED, NOT ASSUMED AWAY. A 74-byte span crosses a slice boundary whenever
* it starts within 74 bytes of the end, which is ~0.9% of positions -- rare enough to survive
* testing and certain to happen. Split into two mapped copies.
* ★★ Reads the DRAWN rectangle: txt_bgy is game-screen and the box is drawn at txt_bgy + txb_yoff,
* so the restore uses the same sum [§2F -- txb_yoff is computed once, in tx_drawbox].
                ifdef   P3B_NO_CEL
* ★ 160 x 168, one byte per pixel. Declared here rather than forward-referencing P3B_PRI_BYTES,
*   which is defined 550 lines below this and only for the budget asserts.
P3RB_PLANE      equ     26880
* ★★★★★ §4B(ii)'s PER-ROW TRACE. §4A ruled out source contamination -- the shadow is clean on all
* seven sampled rows -- so the copy is not landing, and the question is which of row, offset,
* within, n or the straddle is wrong. **Recorded by the guest at the moment it acts**, because the
* host can recompute the arithmetic but cannot see what the routine actually did.
* ★★★ 4 bytes per row x 24 rows into MAP_INPUT's tail, the same region the tx_msgptr differential
* used. Free here: P3_TXDIAG only exists under -DTX_MSGDIAG and this build has it off.
P3_RBTRACE      equ     MAP_INPUT+576   ; row, within(2), n -- one 4-byte record per iteration
P3_RBTRACE_MAX  equ     24
p3rb_tn         fcb     0               ; records written
p3rb_row        fdb     0
p3rb_rend       fdb     0
p3rb_x          fdb     0
p3rb_w          fcb     0
p3rb_n          fcb     0
p3rb_within     fdb     0

p3_restore_box:
                lda     txt_bgw+1
                lbeq    p3rb_out                ; ★ long: p3rb_out is past the byte range
                sta     p3rb_w
* x, clamped: bgx reaches -5 and a negative would step off the row start
                ldd     txt_bgx
                bpl     p3rb_xok
                ldd     #0
p3rb_xok:       std     p3rb_x
* first and last+1 pixel rows, in DRAWN space
                ldd     txt_bgy
                addd    txb_yoff
                bpl     p3rb_yok
                ldd     #0
p3rb_yok:       std     p3rb_row
                addd    txt_bgh
                std     p3rb_rend
p3rb_loop:
                ldd     p3rb_row
                cmpd    p3rb_rend
                lbhs    p3rb_done               ; ★ long: the trace pushed the target out of range
* offset = row*160 + x   (row < 256 within the plane, so one MUL)
                tfr     b,a
                ldb     #160
                mul
                addd    p3rb_x
                cmpd    #P3RB_PLANE
                bhs     p3rb_next               ; past the plane: skip
                pshs    a,b                     ; keep the absolute offset
                lsra
                lsra
                lsra
                lsra
                lsra                            ; A = offset >> 13 == slice
                jsr     p3rb_map
                puls    a,b
                anda    #$1F
                std     p3rb_within             ; offset within the slice
* n = min(w, 8192 - within)
                lda     p3rb_w
                sta     p3rb_n
                ldd     #8192
                subd    p3rb_within
                tsta
                bne     p3rb_copy               ; >= 256 left, so w always fits
                cmpb    p3rb_w
                bhs     p3rb_copy
                stb     p3rb_n                  ; short: the span straddles
p3rb_copy:
* ★★ Trace BEFORE the copy, so a row that copies zero bytes still leaves a record. A trace written
* after the work cannot describe work that did not happen.
                lda     p3rb_tn
                cmpa    #P3_RBTRACE_MAX
                bhs     p3rb_notrace
                inc     p3rb_tn
                ldb     #4
                mul
                ldx     #P3_RBTRACE
                leax    d,x
                lda     p3rb_row+1
                sta     ,x
                ldd     p3rb_within
                std     1,x
                lda     p3rb_n
                sta     3,x
p3rb_notrace:
                jsr     p3rb_span
* did it straddle?
                lda     p3rb_w
                suba    p3rb_n
                beq     p3rb_next
                sta     p3rb_n                  ; the remainder, in the NEXT slice
                pshs    a
                ldd     p3rb_row
                tfr     b,a
                ldb     #160
                mul
                addd    p3rb_x
                lsra
                lsra
                lsra
                lsra
                lsra
                inca                            ; slice + 1
                jsr     p3rb_map
                puls    a
                ldd     #0
                std     p3rb_within
                jsr     p3rb_span
p3rb_next:
                ldd     p3rb_row
                addd    #1
                std     p3rb_row
                lbra    p3rb_loop
p3rb_done:
* ★ leave the mapping as p3_present does: ph_blk_fb on the visible plane, slot 5 back to priority
                lda     #P3_BLK_VISIBLE
                sta     ph_blk_fb
                clra
                jsr     phase_draw
                ifdef   PLANE_WINDOWED
                jsr     plane_reset
                endc
p3rb_out:       rts

* p3rb_map: A = slice. Visible into slot 5 ($A000), shadow into slot 6 ($C000) -- p3_present's pair.
p3rb_map:
                pshs    a
                lda     #P3_BLK_VISIBLE
                sta     ph_blk_fb
                lda     ,s
                jsr     phase_draw_fb_slot5
                lda     #P3_BLK_SHADOW
                sta     ph_blk_fb
                lda     ,s+
                jsr     phase_draw_fb
                ldd     P3_REMAPS
                addd    #2
                std     P3_REMAPS
                rts

* p3rb_span: copy p3rb_n bytes at p3rb_within, shadow ($C000) -> visible ($A000).
* ★★★★★ THE COUNT IS LOADED AFTER THE ADDRESSES, AND THE ORDER IS THE WHOLE DEFECT [T-P0-088].
* The first version did `ldb p3rb_n` and then `ldd p3rb_within` -- and **`ldd` loads A AND B**, so
* the loop count was silently replaced by the LOW BYTE OF THE OFFSET.
* ★★★★ IT REPRODUCED AS A PERIOD-8 PATTERN AND THAT IS WHY: `within` grows by 160 per row, so its
* low byte cycles $0B, $AB, $4B, $EB, $8B, $2B, $CB, $6B. Two of those are below the 74-byte row
* width -- $0B = 11 and $2B = 43 -- so two rows in every eight copied short and the rest copied
* enough (some far too much, overrunning into the next row). Rows 91, 96, 99, 104 and 107 are
* exactly the ones whose low byte is 11 or 43.
* ★★★ Every trace field was CORRECT -- row, within and n all matched an independent host
* computation -- which is what made this invisible to the parameters and visible only in the
* result. **The arithmetic was never wrong; a register was.**
p3rb_span:
                ldd     p3rb_within
                ldx     #FB_BASE
                leax    d,x
                ldu     #PRI_BASE
                leau    d,u
                ldb     p3rb_n
                beq     p3rbs_out
p3rbs_b:        lda     ,x+
                sta     ,u+
                decb
                bne     p3rbs_b
p3rbs_out:      rts
                endc

p3_present:
                clr     p3p_slice
p3p_next:
* --- destination: the VISIBLE plane's slice, borrowed into slot 5 ($A000) ---
                lda     #P3_BLK_VISIBLE
                sta     ph_blk_fb
                lda     p3p_slice
                jsr     phase_draw_fb_slot5
* --- source: the SHADOW plane's slice, in its usual slot 6 ($C000) ---
                lda     #P3_BLK_SHADOW
                sta     ph_blk_fb
                lda     p3p_slice
                jsr     phase_draw_fb
* --- one aperture, two bytes at a time ---
                ldx     #FB_BASE                ; $C000, the shadow slice
                ldu     #PRI_BASE               ; $A000, the visible slice (borrowed slot 5)
p3p_cp:         ldd     ,x++
                std     ,u++
                cmpx    #FB_BASE+8192
                blo     p3p_cp
                inc     p3p_slice
                lda     p3p_slice
                cmpa    #4
                blo     p3p_next
* --- restore: ph_blk_fb back to the visible plane, slot 5 back to priority ---
* ★★ The compositor runs next and writes the VISIBLE plane, so ph_blk_fb stays at
* P3_BLK_VISIBLE until the next room change points it at the shadow again.
                lda     #P3_BLK_VISIBLE
                sta     ph_blk_fb
                clra
                jsr     phase_draw
* ★ Eight maps for the four slices plus the restoring pair, counted rather than left out of
* AC-6's figure -- the same accounting p3_clear_planes now does.
                ldd     P3_REMAPS
                addd    #10
                std     P3_REMAPS
                ifdef   PLANE_WINDOWED
                jsr     plane_reset
                endc
                rts

* ── p3_stage_sprites — VM PHASE ONLY. Copy out what the compositor will need ─────
* ★★★ Runs while slot 5 still holds VM_OBJ. After phase_draw_enter that memory is the priority
* plane, so anything not copied here is unreachable for the rest of the cycle.
* ★ fDrawn is the oracle's own test for "this object is on screen" [sprite.cpp's drawSprites].
p3_stage_sprites:
                clr     p3_nspr
                ldy     #p3_spr
                ldx     #VM_OBJ
                clrb
pss_lp:
                lda     VMO_FLAGS+1,x           ; low byte: fDrawn is $0001
                bita    #fDrawn
                beq     pss_next
                lda     p3_nspr
                cmpa    #P3_SPR_MAX
                bhs     pss_done                ; ★ full: drop the rest rather than overrun
                lda     VMO_X,x
                sta     ,y+
                lda     VMO_Y,x
                sta     ,y+
                lda     VMO_PRIORITY,x
                sta     ,y+
                lda     VMO_VIEW,x
                sta     ,y+
                lda     VMO_LOOP,x
                sta     ,y+
                lda     VMO_CEL,x
                sta     ,y+
                inc     p3_nspr
pss_next:
                leax    VMO_SIZE,x
                incb
                cmpb    #VM_OBJ_MAX
                blo     pss_lp
pss_done:
                lda     p3_nspr
                sta     P3_NSPR
                rts

* ── p3_composite_all — DRAW PHASE. Decode each staged cel and composite it ───────
* ★★ The VIEW resource is fetched here, per sprite, from the arena -- which is resident in this
* phase. The decoded cel goes to CP_CEL, one at a time, because a single 4,784-byte staging
* buffer is all the map has for it.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DP3B_NO_CEL STRIPS THE WHOLE COMPOSITING PATH [T-P0-084d ruling A]. Room 83 stages ZERO
* sprites (`final room 83, sprites 0`), so the text gate needs no cel decode -- and CP_CEL is what
* occupies MAP_RESERVED, the region the text engine has to live in.
* ★★★★ A FLAG, NOT A DELETION, AND RULING A SAYS WHY: *"this is a probe configuration, not an
* engine change ... cel and composite are restored when a task requires sprite staging."* The
* default build is untouched and byte-identical, so the existing p3b gate keeps testing the
* binary it has always tested; the text gate is a second configuration of the same probe.
* ★★★ p3_stage_sprites is deliberately NOT stripped: it runs in the VM phase, reads VM_OBJ before
* the remap, and writes an array. With nothing consuming that array it is a few wasted cycles --
* and keeping it means the phase discipline the cycle body documents is the same in both
* configurations, which is worth more than the cycles.
                ifndef  P3B_NO_CEL
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ SAVE-UNDER BY SHADOW, NOT BY BUFFER [T-P0-112, Jay's ruling on P6.57's shapes 2+3].
*
* ★★★★★ THE STRUCTURAL REASON, AND IT IS THE WHOLE ARGUMENT: a save-under must save because its
* source is destroyed; A SHADOW NEVER IS. So there is no per-sprite store at all -- which also
* deletes the concurrent-sum bound nobody has ever been able to state [P6.57 §3.4] rather than
* measuring it -- and the per-frame copy is 2A rather than a save-under's 4A, because nothing is
* ever saved. Only restored.
*
* ★★★★ WHAT THIS REPLACES. `co_save`/`co_restore` in composite.s are NOT used and are NOT part
* of this shape. They sit behind `ifdef CP_SAVE`, which is defined nowhere in the tree; P6.56
* established the block has never been assembled by anything, ever, and has rotted where it sits
* (flat pointers where the compiled sites use plane_vis/plane_pri; both planes advanced by PRI_W
* where priority's stride is PRI_STRIDE). **Do not revive them to "reuse" this.**
*
* ★★★ THE ORACLE'S OWN MODEL IS THE SAME ONE, one layer up: text.cpp:560-564 closes a message
* window by RE-RENDERING a rectangle of the game screen into the display screen, with "no
* save-under buffer anywhere". p3_restore_box already does exactly that for the box. This is
* that walk applied per sprite, per frame, over BOTH planes.
*
* ★★★★★ ORDERING, AND IT IS THE ONE THING THAT CANNOT BE GOT WRONG: the previous frame's
* rectangles are restored BEFORE this frame's sprites are composited. Restoring afterwards
* erases what was just drawn. The call sits between phase_draw_enter and p3_composite_all.
* ★★★ The rectangle list is rebuilt DURING compositing, from the cel geometry, which is only
* known after vc_decode_begin -- so p3_prevn is cleared at the top of p3_composite_all, after
* the restore has already consumed the old list.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ SEVEN BYTES SINCE T-P0-114, NOT FOUR. The first four are the rectangle; the last three are
* the cel's IDENTITY, and they are what make "has this sprite changed" answerable. Geometry alone
* cannot: a same-size cel swap at the same position is byte-identical in the first four.
* ★★ Costs 48 bytes of p3_prev (16 x 3) to save a full erase-and-repaint per unchanged sprite.
P3_PREV_SIZE    equ     7               ; x, ytop, w, h, view, loop, cel -- all bytes
p3_prevn        fcb     0               ; rectangles live from the previous frame
p3_prev         rmb     P3_SPR_MAX*P3_PREV_SIZE

p3rp_x          fcb     0
p3rp_w          fcb     0
p3rp_rowb       fcb     0               ; the row being restored, as a byte
p3rp_cnt        fcb     0               ; rows remaining
p3rp_i          fcb     0               ; rectangle index
p3rp_off        fdb     0               ; flat offset into the plane
p3rp_within     fdb     0               ; offset inside the mapped 8,192 B slice
p3rp_slice      fcb     0
p3rp_n          fcb     0               ; bytes to copy in this span
* ★★ AC-4's counter: bytes actually restored per frame. 32-bit for the reason the compositor's
* are -- a 16-bit counter wraps into a plausible figure inside the first second [AC-5's note].
p3_restbytes    rmb     4

* ── p3_restore_prev -- put back what last frame's sprites covered, both planes ────
p3_restore_prev:
                lda     p3_prevn
                lbeq    prp_out
                clr     p3rp_i
                ldy     #p3_prev
prp_each:
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ ERASE ONLY WHAT CHANGED [T-P0-114]. An unchanged sprite's pixels are IDENTICAL to the
* ones already on the plane, so erasing it and repainting it is a no-op that costs a visible
* blink -- and the blink is the erase, not the animation.
*
* ★★★★★ JAY IS THE EVIDENCE, and it came from a fault arm nobody built for this question. On
* -NoRestore: *"graham looks the same except he is not blinking anymore."* Graham neither moves
* nor animates, so the ONLY difference between the two arms for him is whether he was erased.
*
* ★★★★★ WHAT "CHANGED" MEANS, AND WHY IT IS NOT THE RECTANGLE. The record used to be four bytes
* of pure GEOMETRY (x, ytop, w, h). A sprite that stays put and swaps to a DIFFERENT CEL OF THE
* SAME SIZE has an identical rectangle and different pixels -- so a geometry-only test would skip
* the erase and **leave the old cel on the screen forever**, which is worse than a blink and is
* the failure this comparison exists to prevent. The record therefore carries the cel's IDENTITY
* -- view, loop, cel -- and all five fields are compared.
*
* ★★★★ THE COMPARISON IS AGAINST THIS FRAME'S STAGED LIST, WHICH IS ALREADY POPULATED:
* p3_stage_sprites runs at phase 5 and this runs at phase 9. ★★★ Index-wise, and that is SAFE in
* the only direction that matters: if the staged set shifts, the fields disagree and we restore,
* which is merely wasteful. A false SKIP would need x, y, view, loop and cel all to match -- and
* a sprite matching all five is one whose pixels are identical whatever its index.
*
* ★★★★★ THE SPRITE IS STILL COMPOSITED. Skipping the erase must NOT mean skipping the draw:
* a changed neighbour's restore can reset priority inside this sprite's rectangle, and the
* composite pass is what repairs it. ★★★ Re-compositing is harmless on both planes -- the visual
* write is identical, and co_depth re-stamps the same viewPriority it stamped last frame, so the
* depth test reaches the same decision it reached before.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifndef  P3B_FAULT_ALWAYSRESTORE
                jsr     prp_same
                beq     prp_skip                ; unchanged -> do not erase it
                endc
                lda     ,y
                sta     p3rp_x
                lda     2,y
                sta     p3rp_w
                lda     3,y
                sta     p3rp_cnt        ; height = rows to walk
                lda     1,y
                sta     p3rp_rowb       ; ytop
                pshs    y
                jsr     prp_visual
                puls    y
                lda     1,y
                sta     p3rp_rowb
                lda     3,y
                sta     p3rp_cnt
                pshs    y
                jsr     prp_priority
                puls    y
prp_skip:
                leay    P3_PREV_SIZE,y
                inc     p3rp_i
                lda     p3rp_i
                cmpa    p3_prevn
                blo     prp_each
prp_out:        rts

* ── prp_same -- is record i identical to this frame's staged sprite i? ───────────
* ★ Returns Z SET when UNCHANGED (caller skips the erase). Y must survive; A, B and X do not.
* ★★ The five fields are x, y, view, loop and cel. The record keeps ytop and the staged list
* keeps y, so the reconstruction is ytop + h - 1 -- done here rather than stored twice [§2F].
prp_same:
                lda     p3rp_i
                cmpa    p3_nspr
                blo     prp_ns_have
* ★★★★★ NO SPRITE i THIS FRAME -> CHANGED, AND Z MUST BE CLEARED EXPLICITLY. The `cmpa` above
* SETS Z when i == p3_nspr, which is the commonest way to arrive here (the list shrank by one),
* so falling through to a bare `rts` would report "unchanged" and skip erasing a sprite that has
* just been REMOVED -- leaving it on the screen permanently. Caught by reading the flags rather
* than the branch.
                andcc   #$FB                    ; Z is CC bit 2
                rts
prp_ns_have:
                ldb     #P3_SPR_SIZE
                mul                             ; D = i * 6
                ldx     #p3_spr
                leax    d,x
                lda     ,y                      ; x
                cmpa    ,x
                bne     prp_ns_no
                lda     1,y                     ; ytop
                adda    3,y                     ;  + h
                deca                            ;  - 1  == the staged y
                cmpa    1,x
                bne     prp_ns_no
                lda     4,y                     ; view
                cmpa    3,x
                bne     prp_ns_no
                lda     5,y                     ; loop
                cmpa    4,x
                bne     prp_ns_no
                lda     6,y                     ; cel -- the last compare SETS Z for the caller
                cmpa    5,x
prp_ns_no:      rts

* ── prp_visual -- one byte per pixel, 160 per row, shadow -> visible ─────────────
prp_visual:
prpv_row:       lda     p3rp_cnt
                beq     prpv_done
                lda     p3rp_rowb
                cmpa    #PIC_H
                bhs     prpv_next       ; ★ off the bottom: skip, do not wrap into the next plane
* off = row * 160 + x
                lda     #PIC_W
                ldb     p3rp_rowb
                mul                     ; D = row * 160; row <= 167 so this cannot overflow
                pshs    d
                clra
                ldb     p3rp_x
                addd    ,s++
                std     p3rp_off
                lda     p3rp_w
                sta     p3rp_n
                jsr     prp_split
* map: visible slice into slot 5, shadow slice into slot 6 -- p3rb_map's pair
                lda     #P3_BLK_VISIBLE
                sta     ph_blk_fb
                lda     p3rp_slice
                jsr     phase_draw_fb_slot5
                lda     #P3_BLK_SHADOW
                sta     ph_blk_fb
                lda     p3rp_slice
                jsr     phase_draw_fb
                jsr     prp_copy
prpv_next:      inc     p3rp_rowb
                dec     p3rp_cnt
                bra     prpv_row
prpv_done:
* ★ leave ph_blk_fb where the compositor expects it: the VISIBLE plane
                lda     #P3_BLK_VISIBLE
                sta     ph_blk_fb
                rts

* ── prp_priority -- PACKED: 80 bytes per row, two pixels per byte ────────────────
* ★★★★ THE SPAN IS WHOLE BYTES AND DELIBERATELY OVER-RESTORES BY UP TO ONE PIXEL AT EACH EDGE.
* x may start in the low nibble, so the byte span is (x>>1) .. ((x+w-1)>>1). Over-restoring is
* SAFE HERE and only here: every rectangle is restored before ANY sprite is composited, so the
* extra pixel can only be written with the picture's own priority value, which is what belongs
* there. It would NOT be safe after compositing had begun.
prp_priority:
prpp_row:       lda     p3rp_cnt
                beq     prpp_done
                lda     p3rp_rowb
                cmpa    #PIC_H
                bhs     prpp_next
* off = row * 80 + (x >> 1)
                lda     #PRI_STRIDE
                ldb     p3rp_rowb
                mul
                pshs    d
                clra
                ldb     p3rp_x
                lsrb
                addd    ,s++
                std     p3rp_off
* n = ((x + w - 1) >> 1) - (x >> 1) + 1
                lda     p3rp_x
                adda    p3rp_w
                deca
                lsra                    ; A = (x + w - 1) >> 1
                ldb     p3rp_x
                lsrb                    ; B = x >> 1
* ★ 6809 HAS NO REGISTER-TO-REGISTER SUBTRACT. `sba` is a 6800 instruction and assembles here as
* nothing of the kind; the subtrahend goes through the stack.
                pshs    b
                suba    ,s+
                inca
                sta     p3rp_n
                jsr     prp_split
* map: LIVE priority slice into slot 5, SHADOW priority slice into slot 6
                lda     p3rp_slice
                jsr     phase_draw_pri
                lda     #P3_BLK_PRISHADOW
                sta     ph_blk_pri
                lda     p3rp_slice
                jsr     phase_draw_pri_slot6
                lda     #P3_BLK_PRI
                sta     ph_blk_pri
                jsr     prp_copy
prpp_next:      inc     p3rp_rowb
                dec     p3rp_cnt
                bra     prpp_row
prpp_done:      rts

* ── prp_split -- off -> slice + within, and clamp p3rp_n to the slice end ────────
* ★★★★★ THE STRADDLE IS CLAMPED, NOT SPLIT. p3rb_span splits into two mapped copies; here the
* tail is simply dropped, and that is a DEFICIENCY recorded rather than hidden -- see §7 of the
* report. A 160-byte row inside an 8,192-byte slice straddles at ~1.9% of row starts.
prp_split:
                lda     p3rp_off
                lsra
                lsra
                lsra
                lsra
                lsra
                sta     p3rp_slice
                ldd     p3rp_off
                anda    #$1F
                std     p3rp_within
* avail = 8192 - within, so 0 < avail <= 8192. Clamp n to it.
* ★★ TEST THE HIGH BYTE FIRST. If avail >= 256 no byte count can exceed it and the compare below
* would be reading the wrong half.
                ldd     #8192
                subd    p3rp_within
                tsta
                bne     prps_out        ; avail >= 256 -- a byte n always fits
                cmpb    p3rp_n
                bhs     prps_out        ; avail >= n -- fits
                stb     p3rp_n          ; clamp; the tail is dropped, see the header
prps_out:       rts

* ── prp_copy -- p3rp_n bytes at p3rp_within, shadow ($C000) -> live ($A000) ──────
* ★★★★★ THE COUNT IS LOADED AFTER THE ADDRESSES [T-P0-088, and it cost that whole task].
* The first version of p3rb_span did `ldb n` then `ldd within` -- and **`ldd` loads A AND B**, so
* the loop count was silently replaced by the low byte of the offset. It reproduced as a
* period-8 pattern because `within` grows by 160 per row. Every traced field was correct; a
* REGISTER was wrong. The order below is the fix, restated where it can be got wrong again.
prp_copy:
                ldd     p3rp_within
                ldx     #FB_BASE
                leax    d,x
                ldu     #PRI_BASE
                leau    d,u
                ldb     p3rp_n
                beq     prpc_out
                clra
                addd    p3_restbytes+2
                std     p3_restbytes+2
                bcc     prpc_nc
                ldd     p3_restbytes
                addd    #1
                std     p3_restbytes
prpc_nc:        ldb     p3rp_n
prpc_b:         lda     ,x+
                sta     ,u+
                decb
                bne     prpc_b
prpc_out:       rts

* ── p3_pri_shadow -- copy the LIVE priority plane into its shadow, once per room ─
* ★★★★ MIRRORS WHAT THE VISUAL PLANE ALREADY DOES, in the other direction. The visual render is
* redirected INTO the shadow and presented out of it; the priority render is left exactly where
* it is -- writing to the live plane, gated by pic 45/45 -- and copied out afterwards. ★★★ Same
* result, and it touches NO part of the render path, which is the lower-risk half of the two.
* ★★ Called after the room's picture render, while nothing is reading priority.
p3_pri_shadow:
                clr     p3rp_slice
pps_slice:
                lda     p3rp_slice
                jsr     phase_draw_pri          ; live slice -> slot 5 ($A000)
                lda     #P3_BLK_PRISHADOW
                sta     ph_blk_pri
                lda     p3rp_slice
                jsr     phase_draw_pri_slot6    ; shadow slice -> slot 6 ($C000)
                lda     #P3_BLK_PRI
                sta     ph_blk_pri
                ldx     #PRI_BASE
                ldu     #FB_BASE
pps_cp:         lda     ,x+
                sta     ,u+
                cmpx    #PRI_BASE+8192
                blo     pps_cp
                inc     p3rp_slice
                lda     p3rp_slice
                cmpa    #2
                blo     pps_slice
                ldd     P3_REMAPS
                addd    #4
                std     P3_REMAPS
                rts

p3_composite_all:
* ★★★ THE OLD LIST HAS ALREADY BEEN CONSUMED by p3_restore_prev, which ran before this call.
                clr     p3_prevn
                lda     p3_nspr
* ★ LONG. The rectangle recorder below added ~30 bytes inside this routine and put pca_out past
* the short-branch range -- the same byte-overflow this file has produced twice before when a
* guarded block grew [T-P0-102, T-P0-108].
                lbeq    pca_out
                ldy     #p3_spr
                clr     p3_si
pca_lp:
                lda     ,y+
                sta     CP_X
                lda     ,y+
                sta     CP_Y
                lda     ,y+
                sta     CP_PRIO
                lda     ,y+
                sta     p3_view
                lda     ,y+
                sta     vc_loop
                lda     ,y+
                sta     vc_cel
                pshs    y
* ── the VIEW resource, through the real path ──
                lda     #RES_VIEW
                ldb     p3_view
                jsr     res_open
                lda     res_err
                bne     pca_skip
* ★★★★★ THE VIEW IS BASELINED HERE AND VERIFIED BEFORE IT IS RELEASED [T-P0-103]. A VIEW is a
* TRANSIENT -- opened, decoded from, composited, closed, all inside this iteration -- so there is
* no later bind to catch a corruption at. **The window that matters is the one between these two
* calls**, because `vc_decode_cel` writes to CP_CEL, which in this configuration starts at $5300
* and runs 4,784 bytes -- 1,456 of them INSIDE the arena this VIEW was just fetched into
* [P6.47 §7.2]. ★★ No decode applies to a VIEW, so the bytes are final the moment res_open returns.
                ifdef   RES_CHECKSUM
                lda     #RES_VIEW
                ldb     p3_view
                jsr     res_ck_note
                endc
                ldx     res_base
                stx     vc_view
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ vc_srcend, AND THIS PROBE HAS NEVER SET IT [T-P0-106]. It is the ONLY bound VC_E_TRUNC
* tests -- `cmpx vc_srcend / blo` [view_cel.s:268] -- and the decoder does not derive it: the
* CALLER supplies it, because only the caller knows how long the resource is.
* ★★★★★ cel_probe.s:153-154 does exactly this (`CP_VIEW + CP_VIEWLEN`). p3b did not, so vc_srcend
* held its image value of ZERO and **every cel truncated on its first byte, for the life of this
* probe.** Measured: vc_view $6000, vc_src $615A, vc_srcend $0000, vc_err 4, co_tested 0.
* ★★★★ SO `sprites 4` WAS A STAGING COUNT AND NOTHING WAS EVER DRAWN. The two byte gates decode
* from a HOST-staged VIEW and set the bound; this path decodes from an ARENA-RESIDENT one and did
* not. **The join is what nobody watched** [L-121, and P6.28d's shape exactly].
* ★★★ res_open has always published res_len. Nothing in this decode path used it.
                ldd     res_base
                addd    res_len
                std     vc_srcend
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ldx     #CP_CEL
                stx     vc_dest
* ★★★★★ BEGIN, NOT DECODE [T-P0-105]. The cel is no longer unpacked here; cp_composite pulls it a
* row at a time into CP_CEL, which is now VC_ROW_MAX bytes rather than 4,784. **The overlap with
* RES_ARENA is gone rather than relocated**, and the VIEW this decodes FROM is no longer inside
* the buffer it decodes INTO.
                jsr     vc_decode_begin
                lda     vc_err
                bne     pca_close
                jsr     cp_composite
* ★★★★★ RECORD THE RECTANGLE FOR NEXT FRAME'S RESTORE [T-P0-112]. Here and not in p3_stage_sprites
* because the cel's GEOMETRY is what the restore needs, and vc_w/vc_h are only known once
* vc_decode_begin has parsed the cel header -- which is two instructions above this.
* ★★★ yPos IS THE LOWER-LEFT CORNER [sprite.cpp:247, and composite.s:122 says so], so the top row
* is y - h + 1. Clamped at 0: a cel taller than its own y would otherwise record a negative row
* and the restore would walk backwards out of the plane.
                lda     p3_prevn
                cmpa    #P3_SPR_MAX
                bhs     pca_norec
                ldb     #P3_PREV_SIZE
                mul                             ; D = index * 4
                ldx     #p3_prev
                leax    d,x
                lda     CP_X
                sta     ,x
                lda     CP_Y
                suba    vc_h
                inca
                bpl     pca_ytopok
                clra
pca_ytopok:     sta     1,x
                lda     vc_w
                sta     2,x
                lda     vc_h
                sta     3,x
* ★★★★★ AND THE CEL'S IDENTITY [T-P0-114]. All three are in scope here and nowhere later: the
* loop loaded p3_view/vc_loop/vc_cel from p3_spr at the top of this iteration, and vc_decode_begin
* has since parsed the header they name. Without these, next frame's comparison sees only a
* rectangle and cannot tell a cel swap from a still sprite.
                lda     p3_view
                sta     4,x
                lda     vc_loop
                sta     5,x
                lda     vc_cel
                sta     6,x
                inc     p3_prevn
pca_norec:
pca_close:
                ifdef   RES_CHECKSUM
                lda     #RCK_AT_CLOSE
                sta     rck_site
                lda     #RES_VIEW
                ldb     p3_view
                jsr     res_ck_verify
                lda     #RES_VIEW
                ldb     p3_view
                jsr     res_ck_release
                endc
                jsr     res_close
pca_skip:       puls    y
                inc     p3_si
                lda     p3_si
                cmpa    p3_nspr
                lblo    pca_lp          ; ★ long, for the same reason as the lbeq above
pca_out:        rts
                else
* ★★ The stripped configuration still needs the symbol: the cycle body calls it unconditionally,
* and a guarded CALL as well as a guarded BODY would put the strip in two places [§2F].
p3_composite_all:
                rts
                endc

p3_lastroom     fcb     $FF             ; ★ $FF: no room yet, so the first cycle always renders
p3_picptr       fdb     0
p3_drew         fcb     0
p3_nspr         fcb     0
p3_si           fcb     0
p3_view         fcb     0
p3_spr          rmb     P3_SPR_MAX*P3_SPR_SIZE

* ── the phase pair, counted ──────────────────────────────────────────────────────
* ★★ COUNTS ITS OWN REMAPS so AC-6 is measured rather than asserted. §3.4's claim is "two per
* phase transition, not per scanline"; a counter is the difference between knowing that and
* believing it.
phase_draw_enter:
                lda     #0
                jsr     phase_draw
* ★★★★★ INVALIDATE THE WINDOW CACHES HERE, AND THIS IS A CORRECTNESS REQUIREMENT NOT HYGIENE.
* plane_win.s caches which slice each plane has mapped so a per-pixel access can skip the remap.
* phase_draw has just written BOTH slots directly, so those caches now describe the previous
* phase. Slot 6 is shared with the VM phase's volume window (MAP_VOL_WINDOW equ MAP_PHASE_WIN),
* so after any VM phase the register holds a VOL block and the cache would happily skip mapping
* the framebuffer over it.
* ★★★ This is the same class as the res_curblk invalidation twenty lines up, which this probe
* already learned the hard way: **a cache of a register's contents is wrong the moment anyone
* else writes that register**, and the phase pair is exactly that moment [§2R.1].
                ifdef   PLANE_WINDOWED
                jsr     plane_reset
                endc
                ldd     P3_REMAPS
                addd    #2
                std     P3_REMAPS
                rts

                include "src/engine/mmu_phase.s"

* ★★★★ vm_tables.s IS RELOCATED, NOT REORDERED. It stays exactly here in the assembly so nothing
* about symbol visibility changes; only the ADDRESS its bytes land at moves, into the seed stack's
* measured slack. 525 B of `fdb` dispatch entries and `fcb` argument counts -- pure data, reached
* only by address, so where it lives is free to choose.
* ★★★ THE CODE RUN IS SPLIT BY THIS, and the host must know: the raw image is now
* code-before | tables | code-after | parser, four runs where there were two. p3b_run.lua pokes
* them from these symbols rather than from literals [the same rule that put P3_INBUF in the map].
                ifdef   P3B_NO_CEL
P3_CODE_SPLIT   equ     *
                org     P3_TABLES_BASE
                include "src/harness/vm_tables.s"
P3_TABLES_END   equ     *
                ifgt    P3_TABLES_END-P3_TABLES_LIMIT
                error   "vm_tables.s overruns the seed stack's slack and is heading for the hardware stack -- shrink it or raise P3_TABLES_LIMIT after re-measuring the stacks"
                endc
                org     P3_CODE_SPLIT
                else
                include "src/harness/vm_tables.s"
                endc
                include "src/harness/vm_state.s"
                include "src/harness/vm_core.s"
                include "src/harness/vm_cmds.s"
                include "src/harness/vm_tests.s"
                include "src/harness/vm_run.s"
                include "src/harness/vm_objects.s"
                include "src/harness/vm_cycle.s"
                include "src/harness/res_core.s"
* ★★ res_check.s is ENTIRELY inside `ifdef RES_CHECKSUM`, so this include costs nothing in a build
* without the flag -- which is what makes AC-5's byte identity a property of the source rather than
* a thing to be careful about. It follows res_core because it reads res_caddr and res_cache_find.
                include "src/harness/res_check.s"
* ★ pic_core.s includes pic_draw.s and pic_fill.s itself -- those two includes sat inside the
* extracted range, so the renderer arrives as one unit. Listing them again here is a
* multiply-defined error, which is the assembler enforcing §2F rather than a nuisance.
* ★★★ plane_win.s before pic_core.s: pic_core's windowed sites `jsr plane_vis`, and the module
* must be defined first. Guarded, so a flat build of this probe is unaffected -- though a flat
* build is exactly what memmap.inc's reachability assertion now refuses (§AC-2, T-P0-041).
                ifdef   PLANE_WINDOWED
                include "src/harness/plane_win.s"
                endc
                include "src/harness/pic_core.s"
                ifndef  P3B_NO_CEL
                include "src/harness/view_cel.s"
                include "src/harness/composite.s"
                endc

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"
* ★★★★★ input.s ARRIVES WITH THE KEYBOARD AND NOT BEFORE [T-P0-092]. hal_globals.s defines
* HAL_key_scan under -DHAL_KEYBOARD; **HAL_input_init lives in input.s and this probe never
* included it**, so the PIA precondition HAL_key_scan documents has never been asserted here.
* ★★★ SHARED and included READ-ONLY, exactly as input_probe.s includes it and for the same one
* routine [§2M: the mechanism is reused, nothing in it is changed].
* ★★ Guarded, so every build that does not ask for the keyboard is byte-identical.
                ifdef   HAL_KEYBOARD
                include "src/hal/coco3-dsk/input.s"
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE MEASUREMENT THAT DECIDES WHETHER THE MAP SURVIVES INTEGRATION.
* P6.1 allocated 12,288 B for engine code against vm_probe.bin's MEASURED 9,089 -- but that was
* the VM plus the HAL only, and P6.1's §7 flagged it as "an allocation to be checked, not a
* measurement". This is the check, and it fires at assembly time.
* ★★★ The text engine and the nine command handlers [T-P0-084d §5B]. Only in the stripped
* configuration: MAP_RESERVED is where text.s lives, and CP_CEL is what used to be there.
                ifdef   P3B_NO_CEL
                include "src/engine/text.s"
* ★★ TEXT_WIRED says the engine is LINKED AND CALLED. -DTEXT_MODELLED links it and declines to
* call it, which is AC-2's fault arm; the cel configuration does not link it at all.
                ifndef  TEXT_MODELLED
TEXT_WIRED      equ     1
                endc
                endc
* ★★★ UNCONDITIONAL, because the generated table names the nine labels in every build [AD-176].
* Under anything but TEXT_WIRED this emits nothing but nine `equ`s to vm_op_modelled.
                include "src/harness/vm_text_ops.s"
P3_CODE_END     equ     *
* ★★★★★ -DP3B_ACCEPT_OVERRUN NOW SUPPRESSES THIS GUARD TOO, FOR THE SAME REASON IT SUPPRESSES THE
* DRAW-PHASE ONE BELOW: **you cannot measure an overrun with a build that refuses to produce a
* map.** When this fired in P6.12 the error named the .map -- "see the .map for the size" -- and
* lwasm had written no .map, because it errored. The advice pointed at a file the failure prevents
* from existing. ★★ The guard still fires by default and still fails the build; the escape exists
* only so the SIZE can be read, which is the first thing anyone needs when it goes off.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SPAN IS MAP_RESERVED_END, NOT MAP_CODE_END [T-P0-084c ruling 2]. The probe may run
* from MAP_CODE through the parser/sound reservation, giving 16,384 B instead of 13,056.
* memmap.inc is unchanged and no boundary moves: this is the probe declaring how far IT reaches,
* which is memmap.inc's own header ("the harness keeps its own addresses").
                ifndef  P3B_ACCEPT_OVERRUN
                ifgt    P3_CODE_END-MAP_RESERVED_END
                error   "P3b code overruns MAP_RESERVED_END -- see the .map for the size"
                endc
* ★★★★★ AND THE ASSERTION THAT MAKES THE SPAN HONEST, BECAUSE MAP_RESERVED IS NOT EMPTY HERE.
* `CP_CEL equ MAP_RESERVED` (line 174): the decoded-cel staging buffer starts at $5300 and is
* 4,784 bytes. **Code growing past $5300 does not overrun a free region -- it overwrites the cel
* buffer**, and the span assertion above cannot see that because both live inside $2000-$6000.
* ★★★★ THE COLLISION WOULD BE SILENT AND WORSE THAN SILENT: room 83 stages ZERO sprites, so
* nothing decodes a cel and the p3b gate's 160 cycles would pass with the buffer already
* overwritten. Room 1 has four, and the first decode would write cel pixels over executing code.
* **A gate that is green because the corpus never exercises the broken path is the failure this
* project has now named twice** [L-86, and this file's own par_vocab/CP_CEL collision at line 980,
* which was found by the eye gate a room away from its cause].
* ★★★ P6.28's placement measurement was taken for text_vm_probe.s, which DROPS view_cel.s and
* composite.s -- there MAP_RESERVED genuinely is free. §2 of T-P0-084c keeps both linked here, so
* the precondition that made the region free does not hold for this probe.
* ★★★★ THE GUARD IS CONDITIONAL ON THE BUFFER EXISTING. Under -DP3B_NO_CEL there is no CP_CEL, so
* MAP_RESERVED is free for code exactly as P6.28 §5A measured for text_vm_probe.s -- the span
* assertion above is then the only bound, and it is the right one.
                ifndef  P3B_NO_CEL
                ifgt    P3_CODE_END-CP_CEL
                error   "P3b code has grown into the decoded-cel buffer at CP_CEL ($5300, 4,784 B) -- the span reaches MAP_RESERVED_END but CP_CEL is already there; move CP_CEL or shrink the code, do not let them overlap"
                endc
                else
* ★★★★★ AND THE ASSERTION RULING A ASKS FOR, IN THE OTHER DIRECTION: if the compositing path is
* ever re-linked while the text engine occupies MAP_RESERVED, the build must fail rather than
* silently re-occupy the region. `ifdef CP_CEL` under P3B_NO_CEL means someone defined it anyway.
                ifdef   CP_CEL
                error   "CP_CEL is defined in a -DP3B_NO_CEL build -- the compositing path has been re-linked into a configuration whose MAP_RESERVED holds the text engine. Drop -DP3B_NO_CEL or drop the cel path; they cannot share $5300."
                endc
                endc
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE STATUS BLOCK'S OCCUPANCY, ASSERTED. This file's own comment said MAP_STATUS+32 was
* free while CNT_VERT sat there, and P3_FEED was placed on top of it -- so the renderer's
* vertical-line counter armed the parser's feed flag and the eye gate hung in the bucket walk.
* ★★★★ **An overlap claim checked by a human reading a table is the state these assertions exist
* to end** [AD-78, memmap.inc's own words]. The status block had no assertion at all; it has two
* now, and they are the only reason the next offset added here is safe.
* ★★★ CP_CTRLSTEP is the highest declared offset and it is four bytes wide, so anything new must
* start at or above +88. ★★ And the whole block is 224 B [memmap.inc's MAP_SEEDSTACK check].
                ifgt    CP_CTRLSTEP+4-P3_FEED
                error   "P3_FEED overlaps the compositing counters -- the status block is full up to CP_CTRLSTEP+4"
                endc
                ifgt    P3_NKEY+1-(MAP_STATUS+224)
                error   "the status block overruns its 224 bytes into the seed stack"
                endc
* ★ And the new pair against the old highest offset, so neither can be moved onto the other.
                ifgt    P3_VOCAB_BAD+2-P3_KEY
                error   "P3_KEY overlaps P3_VOCAB_BAD's two bytes"
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE PARSER GOES IN MAP_RESERVED, WHICH IS THE REGION RESERVED FOR IT [T-P0-060 AC-9].
*
* ★★★★ memmap.inc:105 reads `MAP_RESERVED_END equ $6000 ; 3,328 B, parser + sound`. This is the
* parser. Placing it here is that reservation being SPENT ON ITS STATED PURPOSE, and the
* boundaries do not move: MAP_RESERVED stays $5300, MAP_RESERVED_END stays $6000, 3,328 B, and
* MAP_RESERVED_MIN's floor assertion is untouched. **The dispatch's "MAP_RESERVED is not
* touched" is satisfied by not moving it, not by not using it.**
* ★★★ WHY THIS AND NOT MORE CODE-REGION SQUEEZING. p3b had FOUR bytes left [T-P0-059 §7.6] and
* M-48's range checks returned 203 of them -- real, and 203 against the parser's 870. Squeezing
* another 670 out of the code region to avoid using a region that exists for this is the shape
* of decision memmap.inc:72-95 spent three tasks regretting: each step small, each justified,
* and the reservation down 12.5% with the parser not yet built to argue for itself.
* ★★ THE `org` COSTS THE GAP IN THE IMAGE, and the gap is what M-48 freed: P3_CODE_END to $5300
* is padded with zeros in the raw image and poked with it. It is bytes on disk and in the poke,
* not bytes of RAM pressure -- the region is reserved either way.
* ★ src/engine/parser.s is UNCHANGED by this task. It is gated at 23,328 cases across five
* titles [T-P0-059]; including it from a second probe is not a change to it.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PAD THE GAP EXPLICITLY. `org` ALONE PRODUCES A RAW IMAGE THAT LIES ABOUT ITS OWN
* ADDRESSES, and this cost the eye gate its first run.
* ★★★★ lwasm --format=raw emits BYTES, not an address space: a forward `org` moves the assembler's
* location counter and writes NO PADDING, so the parser's bytes follow P3_CODE_END's immediately
* in the file. The host pokes the blob at MAP_CODE, so every byte after the org lands
* (MAP_RESERVED - P3_CODE_END) = 36 bytes BELOW the address its symbol claims. **The image was
* 13,890 bytes when $566A-$2000 is 13,930 -- short by exactly the gap.**
* ★★★★ THE SYMPTOM WAS NOT SUBTLE AND IT WAS NOT INFORMATIVE EITHER: `jsr par_parse` entered the
* parser 36 bytes off, and p3b's watchdog reported STUCK in the feed cycle with PC $0109 x1800 --
* the guest executing the flood-fill seed stack. ★★★ A hang whose PC is in a DATA region is an
* entered-at-the-wrong-address signature, and the watchdog naming the PC is what made it one
* look rather than a session [L-59; and the watchdog is correctly charged per CYCLE, so it fired
* on the right cycle -- the one the command was fed].
* ★★★ THE BYTE GATE COULD NOT HAVE CAUGHT THIS. vm_probe.s includes parser.s inline with no org,
* so it has no gap and the nine-title diff is byte-identical either way. **The defect lives only
* in the integration probe, in the glue between two things that are each gated** -- §4A.1's exact
* claim, and the eye gate found it on its first run, before any byte gate was reported.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND IT IS NOT IN MAP_RESERVED IN *THIS PROBE*, BECAUSE SOMETHING IS ALREADY THERE.
* ★★★★★ `CP_CEL equ MAP_RESERVED` (line 174 of this file): p3b's DECODED CEL STAGING lives at
* $5300 and is **4,784 bytes** -- which already overruns the 3,328 B region into the arena
* window, and this file's own §8-trigger block reports that rather than patching it. So the
* parser's first byte, par_vocab, was also the cel buffer's first byte.
* ★★★★★ THE SYMPTOM WAS A ROOM AWAY FROM THE CAUSE, WHICH IS WHY ONLY THE EYE GATE FOUND IT.
* Room 83 has ZERO sprites: nothing decodes, and the parser ran 160 cycles with both commands
* fed, clean. Room 1 has four, and the first cel decode zeroed par_vocab -- so par_find computed
* `vocab + letter*2` from ADDRESS ZERO and walked the HAL's direct page and the flood-fill seed
* stack looking for a terminator that is not there. Jay, watching from the outside: *"if youre
* placing anything at $0000 you are overwriting the DP and probably the stack"* -- which is
* exactly what a null base pointer reads as.
* ★★★★ THE ENGINE'S ANSWER IS UNCHANGED AND IS STILL MAP_RESERVED [AC-6, memmap.inc]. This is a
* HARNESS address, and memmap.inc's header is explicit that the harness keeps its own map.
* **The probe cannot host the parser where the engine will, because the probe put something else
* there first** -- a fact about p3b's over-subscribed map, not about the placement decision.
*
* ★★★ NO `fill` HERE, AND THAT IS DELIBERATE. A fill to $E000 would put ~36 KB of zeros in the
* raw image and in the poke. Instead the HOST pokes TWO SEGMENTS -- the code at MAP_CODE and the
* parser at P3_PARSER_BASE -- with the split read from the map [p3b_run.lua]. ★★ The version
* above DID fill, to $5300, because without it the parser landed 36 bytes below its own symbols.
* **The raw image is bytes, not an address space, and somebody has to say where each run goes**;
* the fill said it one way and the two-segment poke says it the other.
P3_PARSER_BASE  equ     $E000
                org     P3_PARSER_BASE
                include "src/engine/parser.s"
P3_PARSER_END   equ     *

* ★★★ THE INPUT BUFFERS, 42 BYTES EACH, MEASURED AT THE PIN [text.h:170 `byte _prompt[42]`;
* TEXT_STRING_MAX_SIZE 40; cycle.cpp:663 var 24 = 38]. They follow the parser, and the
* vocabulary window follows them, so the whole parser subsystem is one contiguous run and its
* total is one number.
P3_INBUF        equ     P3_PARSER_END
P3_CLNBUF       equ     P3_INBUF+42
P3_PARSER_TOTAL equ     P3_CLNBUF+42-P3_PARSER_BASE

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE VOCABULARY: A WINDOW IN SLOT 5, NOT 6,966 RESIDENT BYTES BEHIND THE PARSER
* [T-P0-091]. The text configuration's region B was parser 870 + buffers 84 + **vocabulary
* 6,966** + 16 of vector stubs: 88% of a permanently-mapped bank spent on a table read ONCE PER
* TYPED LINE. memmap.inc has said `MAP_VOCAB equ MAP_PRI_SLICE` since T-P0-060 and this is that
* line acquiring code [mmu_phase.s phase_vocab_in/_out].
*
* ★★★★★ THE TEXT PARAGRAPH THIS REPLACES SAID "**This probe cannot use it**: slot 5 is p3b's
* PRIORITY slice, live in every draw phase." **That was true of a RESIDENT vocabulary and is
* false of a WINDOW.** par_parse runs in the VM phase, where slot 5 holds the object table and
* not the priority slice, and it needs the dictionary for the duration of one call. The
* objection was about residency all along and windowing removes it.
*
* ★★★★ SCOPED TO THE TEXT CONFIGURATION, DELIBERATELY, AND FOR T-P0-089's REASON. P3_VOCAB and
* P3_VOCAB_END are compared in EMITTED CODE (the window self-test), so moving them
* unconditionally moves `p3b` -- the purpose=timing row, where AD-96 is the standing lesson about
* a figure whose producer moved. The cel build has no font pressure and keeps the flat window it
* has always had, byte-identical at 58AD3C27.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifdef   P3B_NO_CEL
                ifdef   TEXT_VOCAB_FLAT
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FLAT MEASUREMENT ARM's DICTIONARY, AND ITS ADDRESS IS A COMPROMISE THAT IS STATED
* RATHER THAN HIDDEN [T-P0-095 §4A]. Region B above the font is $EBBA-$FEF0 = **4,918 bytes**,
* which holds Kingquest1's 3,144-byte WORDS.TOK and **does NOT hold the corpus maximum of 6,828**
* (SpaceQuest-2). The windowed configuration exists precisely because 6,828 does not fit here.
* ★★★★ SO THIS ARM IS FOR ONE TITLE AND ONE QUESTION. It is not a shipped configuration, it is in
* no gate row, and the assertion below is relaxed for it with the smaller bound named -- **a build
* that silently accepted a dictionary it could not hold would corrupt the vector stubs**, which is
* the failure the 6,828 assert was written against [the IRQ crash, P6.32].
* ★★ SPELLED FROM P3_CLNBUF, NOT FROM P3_FONT, AND THE TWO ARE THE SAME ADDRESS. P3_FONT is
* declared BELOW this block, so `P3_FONT+P3_FONT_BYTES` is a forward reference and the assert
* underneath it fails pass 1 with "Conditions must be constant" -- which reads as a broken
* assertion rather than as a declaration-order problem. P3_FONT is P3_CLNBUF+42 by its own
* definition, so this is that value with no forward reference in it.
P3_VOCAB        equ     P3_CLNBUF+42+P3_FONT_BYTES
* ★★★★ THE CEILING IS MAP_COVERAGE, NOT $FEF0, SINCE T-P0-102. The two coverage counters now sit at
* $FC00-$FE00 in slot 7, and this is the one arm whose dictionary grows up into that space. 4,166 B
* against Kingquest1's 3,144 -- the assert below is what makes the margin a fact rather than a hope,
* and it is the same assert that was already here.
P3_VOCAB_END    equ     MAP_COVERAGE
                ifgt    3144-(P3_VOCAB_END-P3_VOCAB)
                error   "the flat measurement arm cannot hold Kingquest1's WORDS.TOK (3,144 B)"
                endc
                else
P3_VOCAB        equ     MAP_VOCAB       ; $A000, slot 5 -- mapped only while tokenising
P3_VOCAB_END    equ     MAP_VOCAB_E     ; $C000; 8,192 B >= 6,828 (SpaceQuest-2, the corpus max)
* ★★★★ THE BLOCK NUMBERS, WHICH THIS PROBE OWNS AND THE HOST READS [p3b_run.lua's own rule for
* ph_blk_fb/ph_blk_pri]. Priority 0-1, shadow framebuffer 2-5, volumes 8-38, visible plane 40-43,
* $38-$3F the CPU's own boot window -- so **blocks 6 and 7 are free** and the dictionary takes 6.
* ★★★ $3D is what slot 5 holds otherwise: the host pre-sets all eight slots to $38+i at load and
* VM_OBJ has lived in that block ever since [the `lda #$3D` this replaces, p3_do_cycle].
P3_BLK_VOCAB    equ     6
                endc
* ★★★ P3_BLK_SLOT5 IS OUTSIDE THE FLAT/WINDOWED SPLIT: phase_text_out needs it in both, because the
* four-slot text window borrows slot 5 whether or not a dictionary ever does.
P3_BLK_SLOT5    equ     $3D
                else
* ── the flat window the cel configuration keeps, unchanged ───────────────────────
* ★★★ THE INPUT BUFFERS ARE FOLLOWED BY THE DICTIONARY HERE, so the whole parser subsystem is one
* contiguous run and its total is one number.
P3_VOCAB        equ     P3_CLNBUF+42
* ★★★★★ WITH INTERRUPTS ON, THE TOP OF THIS WINDOW IS NOT OURS EITHER [after the IRQ crash].
* The CoCo3 redirects the 6809 vectors into the $FExx page as 3-byte stubs -- $FFF8 reads $FEF7,
* which at the DECB prompt holds `16 02 12` = LBRA wrapping to $010C. **Measured, not assumed.**
* ★★★★ The dictionary is staged from P3_VOCAB upward and the harness only refuses when it exceeds
* the window, so a title with a big enough WORDS.TOK would write over the IRQ stub. That failure
* would be title-dependent and intermittent -- the worst kind -- so the window is shortened rather
* than left to luck. 16 bytes reserved.
* ★★ Reachable only without P3B_NO_CEL now, and P3B_IRQ is a text-configuration flag -- so this
* branch is the `$FF00` one in every shipped build. Kept whole rather than simplified: -NoIrq is
* how the IRQs-off hang stays reproducible [§2W] and it must keep assembling.
                ifdef   P3B_IRQ
P3_VOCAB_END    equ     $FEF0           ; ★ $FEF0-$FF00 = the vector redirect stubs
                else
P3_VOCAB_END    equ     $FF00           ; ★ $FF00-$FFFF is the I/O page and is not ours
                endc
                endc
* ★★ The corpus-maximum assert covers every SHIPPED configuration. The flat measurement arm carries
* its own, smaller, named bound above [§4A]; asserting 6,828 against it would refuse a build whose
* whole purpose is one 3,144-byte title.
                ifndef  TEXT_VOCAB_FLAT
                ifgt    6828-(P3_VOCAB_END-P3_VOCAB)
                error   "the vocabulary window is smaller than the largest corpus WORDS.TOK (6,828 B)"
                endc
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THE FONT LANDS IN WHAT THE DICTIONARY GAVE BACK. 2,048 bytes of authored glyphs,
* reached ONLY through txt_font and only by address -- which is exactly L-127's test for what
* should move when a region is contended [T-P0-089's finding, applied a second time].
* ★★★★ SLOT 7 IS NEVER REMAPPED, so the font is resident in every phase. That is the property
* txt_blit needs -- it fetches a glyph while slots 5 and 6 hold the planes -- and it is the same
* guarantee MAP_INPUT gives P3_PBUF, one slot along [vm_text_ops.s, hazard 1].
* ★★★ THE BYTE FLOW, SO IT IS NOT LEFT TO THE READER: the font LEAVES region A ($5800-$6000) and
* ARRIVES in region B at $E3BA. Region A's ceiling becomes MAP_RESERVED_END with nothing under
* it, and region B holds parser + buffers + font with 2,870 bytes still free.
                ifdef   P3B_NO_CEL
P3_FONT         equ     P3_CLNBUF+42
P3_REGIONB_END  equ     $FEF0           ; ★ the vector stubs, as above -- P3B_IRQ is always on here
                ifgt    P3_FONT+2048-P3_REGIONB_END
                error   "the font overruns region B into the $FEF0 vector stubs -- the parser or its buffers have grown"
                endc
                endc
* ★★★★ AND THE ASSERTION THAT WOULD HAVE CAUGHT THE COLLISION. CP_CEL is 4,784 B from
* MAP_RESERVED; the parser must start above where it ends. An overlap claim checked by a human
* reading a table is the state these exist to end [AD-78] -- and this file had no assertion
* covering CP_CEL against anything at all.
                ifndef  P3B_NO_CEL
CP_CEL_END      equ     CP_CEL+VC_ROW_MAX
                ifgt    CP_CEL_END-P3_PARSER_BASE
                error   "the decoded-cel buffer runs into the parser -- CP_CEL is 4,784 B from MAP_RESERVED"
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND AGAINST THE ARENA, WHICH IS THE ONE THAT IS RED TODAY [T-P0-104, AC-1].
*
* ★★★★★ CP_CEL is $5300 and RES_ARENA is $6000, so the buffer has **3,328 bytes** before it runs
* into the arena and its declared extent is **4,784** -- an overlap of **1,456 bytes**. That was
* recorded as a hazard for several tasks with the standing explanation that real cels are far
* smaller than the corpus maximum. ★★★★★ **cel_extent.py measured it and the explanation is false
* for two titles: Kingquest3's largest decoded cel is 4,784 bytes -- it IS the corpus maximum,
* view 64 loop 0 cel 0 -- and larry1 has three cels over the margin.** Kingquest1, Kingquest2 and
* PoliceQuest1 have none, which is why every cel run in this project has been clean [L-86].
*
* ★★★★★ THE VICTIM IS THE VIEW BEING DECODED FROM. res_top starts at RES_ARENA, so the first
* transient lands at $6000 exactly; p3_composite_all fetches the VIEW there and vc_decode_cel
* decodes FROM it INTO CP_CEL. ★★★★ **And the decode CLEARS its whole destination first**
* [view_cel.s:184-188] -- so an over-margin cel ZEROES 1,456 bytes of the source before the
* unpack reads a byte of it. It is not a gradual overwrite; it is a wipe.
*
* ★★★★★ FIXED AT T-P0-105, AND THE ACCEPTANCE FLAG IS RETIRED WITH THE DEFECT. The buffer is one
* ROW now -- VC_ROW_MAX, sized by the format's width ceiling rather than by a corpus maximum --
* and it sits in region A's last page. **This assertion passes on its own terms**, with no bypass
* in this file, in p3b_show.ps1, in p3b_arms_check.ps1 or in gates.manifest.
* ★★★ -DP3B_ACCEPT_CEL_ARENA existed for exactly one task. **An acceptance flag that outlives the
* defect it accepted is how a known defect becomes invisible**, so it is deleted rather than left
* unused: an unused flag reads as a configuration somebody might still want.
                ifgt    CP_CEL_END-RES_ARENA
                error   "the decoded-cel buffer overlaps RES_ARENA -- CP_CEL + VC_ROW_MAX must end below $6000, where res_top places the VIEW being decoded FROM. This was a real defect: at 4,784 bytes the buffer ran to $65B0 and zeroed 1,456 bytes of its own source [P6.49]."
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE COMPOSITOR MUST BE WINDOWED-SAFE IF THE PLANES ARE WINDOWED [T-P0-107 §4C].
* ★★★★★ memmap.inc's plane-overflow assertion exempts -DPLANE_WINDOWED because "that build reaches
* every byte through plane_vis/plane_pri, which mask the offset". **composite.s did not, for the
* whole life of the file**, and the exemption covered it silently: row 100 of the visual plane
* landed at $FE80 and row 167 wrapped to $2860, inside this probe's own code [P6.51 §7.1].
* ★★★★ AN EXEMPTION IS AN ASSERTION ABOUT CODE THAT IS NOT IN THE EXPRESSION. It quantified over
* every subsystem that touches a plane and nothing rechecked it when a second one arrived. This
* line is the recheck, and it is a symbol rather than a sentence.
* ★★★ -DCOMP_FAULT_FLAT_PLANE suppresses COMP_PLANE_SAFE so this can be seen RED.
                ifdef   PLANE_WINDOWED
                ifndef  COMP_PLANE_SAFE
                error   "composite.s is linked with PLANE_WINDOWED but is not windowed-safe -- co_rowset would form CP_VIS + y*160 as a flat ADDRESS, and CP_VIS is an 8,192-byte window: row 100 lands at $FE80 beside the vector stubs and row 167 wraps to $2860, inside this probe's code. memmap.inc's AC-2 exemption assumes every windowed access goes through plane_vis/plane_pri; this asserts it for the compositor."
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════════════
                else
* ★★ The substitution buffer against MAP_INPUT, asserted HERE because TXT_PBUF_MAX comes from
* text.s and lwasm needs pass-1 constants. §2V.2: "a 6809 array does not grow -- state the maximum."
                ifgt    P3_PBUF+TXT_PBUF_MAX-MAP_INPUT_END
                error   "the text substitution buffer overruns MAP_INPUT ($1C00-$2000)"
                endc
* ★★★ And the diagnostic record against the same region. It sits ABOVE the substitution buffer, so
* an over-large record would corrupt nothing in the clean build and silently scribble on whatever
* follows MAP_INPUT in the diagnostic one -- which is exactly the class of failure a diagnostic must
* not have [§2W.3: a diagnostic that can be wrong about its own storage testifies, it does not
* measure]. 2 sites x 8 records x 12 bytes = 192, into 448 free.
                ifdef   TX_MSGDIAG
                ifgt    P3_TXDIAG+2*TXD_EACH*TXD_REC-MAP_INPUT_END
                error   "the tx_msgptr diagnostic record overruns MAP_INPUT ($1C00-$2000)"
                endc
                ifgt    P3_PBUF+TXT_PBUF_MAX-P3_TXDIAG
                error   "the tx_msgptr diagnostic record overlaps the substitution buffer"
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FONT GUARD, REPOINTED RATHER THAN DELETED [T-P0-091]. It used to read
* `ifgt P3_CODE_END-P3_FONT` and it was the right guard while the font sat at the top of
* MAP_RESERVED with the code growing toward it. **The font is in region B now, so that comparison
* is trivially true and would never fire again** -- a guard that cannot go red is §2W's whole
* subject, and leaving it in place would have been worse than having none.
* ★★★★ WHAT REPLACES IT IS THE SAME QUESTION AGAINST THE CEILING THAT ACTUALLY BOUNDS REGION A
* NOW: MAP_RESERVED_END. Under -DP3B_NO_CEL there is no CP_CEL and no font below it, so the code
* may run the whole way to $6000 and the only thing it can collide with is the arena window.
* ★★★ The region-B half is asserted where the font is declared (P3_FONT+2048 vs $FEF0), so both
* ends of the move carry a check rather than a sentence.
                ifgt    P3_CODE_END-MAP_RESERVED_END
                error   "P3b code has grown past MAP_RESERVED_END ($6000) into the arena window -- region A is full"
                endc
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE COVERAGE COUNTERS AGAINST EVERY NEIGHBOUR THEY HAVE [P6.47, AC-3].
*
* ★★★★★ vm_probe.s:608-620 HAS ASSERTED THIS CLASS SINCE T-P0-032 -- VM_TESTSEEN against
* VM_OPSEEN, VM_OPSEEN against vmtr_buf and RES_ARENA -- **and this file named neither counter
* anywhere.** The counters were at $6300/$6400, which is `vm_probe`'s free space and this probe's
* RES_ARENA window, and nothing in either file could notice.
* ★★★★★ vm_state.s's own header already carries the lesson, written for THESE TWO SYMBOLS
* colliding with the code image: *"An assertion that names one of four neighbours reports
* conformance for the other three."* **Same symbols, same class, one probe later** -- so this
* block names every neighbour rather than the one that happened to bite.
* ★★★★ OVERLAP, NOT ORDERING. vm_probe's map is linear and its asserts are `a+size > b`. This
* probe's is not: region A, region B, the arena window and the windowed vocabulary are in no fixed
* order relative to a slot-7 address, so each check is the real two-sided test -- ranges [a,b) and
* [c,d) overlap iff b > c AND d > a -- written as a nested pair because lwasm has `ifgt` and no
* boolean AND.
* ★★★ LIVE ONLY WHEN THE COUNTERS ARE. Under the default -DVM_NOCOUNT nothing writes or clears
* them, so the address is inert and the checks would refuse a build for a hazard that does not
* exist. **A gate that is permanently red for a legitimate reason gets switched off** [§2M.8].
P3_COV          equ     VM_TESTSEEN
P3_COV_END      equ     VM_OPSEEN+256
                ifne    VM_OPSEEN-(VM_TESTSEEN+256)
                error   "the coverage counters are not contiguous -- the checks below assume one 512 B block"
                endc
                ifndef  VM_NOCOUNT
* ★★★★★ -DP3B_ACCEPT_COV_ARENA IS THE DELIBERATE BYPASS, AND IT EXISTS FOR ONE CALLER [T-P0-103].
* This assertion is the one that refuses P6.46's defect -- and **the resource-checksum instrument's
* fault arm has to BUILD that defect to prove it can detect it.** Without a bypass the two §2W
* obligations contradict each other: the assertion may not be weakened, and the checksum may not be
* believed until it has been seen red on a real corruption.
* ★★★ It is named for what it accepts, it is required in addition to -DP3B_FAULT_COV_ARENA, and it
* is in no gate row. The probe already uses this shape for the draw-phase overrun.
                ifndef  P3B_ACCEPT_COV_ARENA
                ifgt    P3_COV_END-RES_ARENA
                ifgt    RES_ARENA_END-P3_COV
                error   "the coverage counters are inside RES_ARENA -- every dispatched opcode would increment a byte of the resident resource (P6.46: Kingquest1 LOGIC 102 at $63F2, its goto at offset $0010). -DP3B_ACCEPT_COV_ARENA to build it anyway, which only the checksum's fault arm should do."
                endc
                endc
                endc
                ifgt    P3_COV_END-MAP_CODE
                ifgt    P3_CODE_END-P3_COV
                error   "the coverage counters are inside region A -- they would be incremented over this probe's own code"
                endc
                endc
                ifgt    P3_COV_END-P3_VOCAB
                ifgt    P3_VOCAB_END-P3_COV
                error   "the coverage counters are inside the vocabulary window -- said() would read incremented dictionary bytes"
                endc
                endc
                ifgt    P3_COV_END-MAP_INPUT
                ifgt    MAP_INPUT_END-P3_COV
                error   "the coverage counters are inside MAP_INPUT -- the substitution buffer and the counters would share bytes"
                endc
                endc
                ifgt    P3_COV_END-$FF00
                error   "the coverage counters run into the $FF00 I/O page"
                endc
                ifndef  P3B_NO_CEL
                ifgt    P3_COV_END-CP_CEL
                ifgt    CP_CEL_END-P3_COV
                error   "the coverage counters are inside CP_CEL -- decoded cel staging would overwrite them and they would corrupt a staged cel"
                endc
                endc
                else
                ifgt    P3_COV_END-P3_FONT
                ifgt    P3_FONT+2048-P3_COV
                error   "the coverage counters are inside the font -- glyphs would be incremented"
                endc
                endc
                endc
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE DRAW-PHASE FOOTPRINT, AND IT IS §8 TRIGGER 1.
*
* Both pic_core.s and composite.s address their planes FLAT: pix_addr forms
* `X = FB_BASE + (y*160+x)` and co_rowset forms `y*160` the same way, with offsets to 26,879
* and **one byte per pixel on BOTH planes**. So during a draw phase the CPU must see, at once:
*
*     visual plane, flat, 1 B/px                26,880
*     priority plane, flat, 1 B/px              26,880
*     engine code (MEASURED, this build)        11,768
*     decoded cel staging (corpus max)           4,784
*     picture seed stack (fills run here)        1,024
*     hardware stack                               768
*     status + counters                             90
*                                               ------
*                                               72,194   against $0000-$FEFF = 65,280
*
* ★★★ OVER BY 6,914 BYTES. This is why P3b stops rather than integrating: the five subsystems
* are individually correct and do not fit together as written.
*
* ★★★★ AND THE FIX IS ALREADY IN THE MAP, UNIMPLEMENTED. memmap.inc specifies the priority
* plane PACKED AT 4 BPP -- 13,440 B -- derived from design §3.2's two-block budget. No
* subsystem implements it; every one of them writes a byte per pixel. Packing saves 13,440 and
* brings the draw phase to **58,754, which fits with 6,526 to spare**.
* ★★ So the 4 bpp decision is NOT a space optimisation to be scheduled later. **It is what makes
* the draw phase fit at all**, and P6.1 recorded it as a divergence whose cost was "a nibble
* extract on the cheap path" without noticing it was load-bearing for fitting.
*
* ★ WHY pic_probe AND comp_probe BOTH FIT ALONE: their code is 2,642 B and 967 B. The full
* engine is 11,768. **The planes did not grow; the code did**, by 7,928 bytes -- and that is the
* whole of the overrun plus the cel staging.
*
* ★★ THE ASSERTION IS LEFT ARMED. It fails the build, deliberately, so that this is a fact
* about the tree rather than a paragraph in a report [L-27: a finding that cannot fail is not a
* finding]. -DP3B_ACCEPT_OVERRUN builds anyway, for measuring the parts.
* ★ Everything except the code, which is P3_CODE_END and is measured rather than estimated.
* ★★★★ THE PRIORITY TERM IS NOW THE BUILD'S ACTUAL PLANE SIZE, not a constant. Under
* -DPRI_PACKED it is 13,440; without it 26,880. **So this assertion no longer merely records
* the overrun -- it is the AC-2 test**, and whether the draw phase fits is decided by the same
* flag that decides how the six nibble sites assemble. A packed build that still overran would
* fail here rather than in a report.
                ifdef   PRI_PACKED
P3B_PRI_BYTES   equ     13440           ; 80 x 168, 4 bpp
                else
P3B_PRI_BYTES   equ     26880           ; 160 x 168, 1 B/px -- what P3b measured
                endc
* ★★★★ THE ASSERTION WAS OVER-STRICT BY 8,192 AND P3b DID NOT CATCH IT.
* It read `P3B_DRAW_NEED + P3_CODE_END`, and **P3_CODE_END is an ADDRESS** (MAP_CODE + size),
* so it charged the draw phase for the 8,192 bytes below MAP_CODE a second time -- the status,
* stacks and DIRs are already itemised in P3B_DRAW_NEED. The code SIZE is what belongs here.
* ★★★ It went unnoticed because the unpacked case is over the limit either way: 72,194 by hand
* against 80,386 by the assertion, both > 65,280, **same verdict from different arithmetic.**
* ★★ P3b's REPORTED figure (72,194) was summed by hand and is correct; the assertion was not
* measuring what it claimed. **A check that agrees with you for the wrong reason is the one you
* never audit** -- and it only surfaced because packing made the two disagree.
P3B_CODE_SIZE   equ     P3_CODE_END-MAP_CODE
P3B_DRAW_NEED   equ     26880+P3B_PRI_BYTES+4784+1024+768+90
                ifndef  P3B_ACCEPT_OVERRUN
                ifgt    P3B_DRAW_NEED+P3B_CODE_SIZE-$FF00
                error   "DRAW PHASE DOES NOT FIT: planes+code+cel+stacks exceed $0000-$FEFF. 4bpp priority packing (memmap.inc MAP_PRI_BYTES) is unimplemented and is load-bearing. See the block above. -DP3B_ACCEPT_OVERRUN to build anyway."
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════════════
                end     p3b_entry
