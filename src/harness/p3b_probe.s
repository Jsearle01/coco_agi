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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE COMPOSITOR READS THE VIEW IN PLACE [T-P0-136]. Declared in the SOURCE, as
* PLANE_WIN_MMU is and for the same reason [AD-119: a symbol on a command line is a fact nobody
* can see from the source]. Two flags because they are two mechanisms:
*   RES_CURSOR        res_core.s's stream cursor -- map once, re-map on crossing or on theft
*   VC_SRC_WINDOWED   view_cel.s reads the VIEW through the window instead of out of the arena
* ★★★ NEITHER IS SET BY cel_probe OR comp_probe, so the cel and comp gates assemble the byte
* identical decoder they always have and their 9,193/9,193 and 124/124 remain claims about the
* same program. ★★ -DP3B_VIEW_COPY restores the copy: AC-4's arm and the before side of §4D.
                ifndef  P3B_VIEW_COPY
RES_CURSOR      equ     1
VC_SRC_WINDOWED equ     1
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PIC_NOCOUNT -- THE FILL'S INSTRUMENTATION IS NOT ASSEMBLED HERE [T-P0-138 §4C].
* ★★★★★ MEASURED: fc_count was 29.4% of the room-render cycle, the largest single routine in it.
* It is a pure counter -- `ldd CNT_CHK+2 / addd #1 / std` -- called from the fill's INNERMOST
* loops (ff_left, ff_right, and both seed tests), and every `ifndef PIC_NOCOUNT` block in
* pic_fill.s is an increment with no logic in it.
* ★★★★ NOTHING IN THIS PROBE OR ANY HOST READS THEM. p3b_probe.s declares the CNT_* addresses
* because pic_draw.s and pic_core.s increment two of them UNGUARDED and the file must assemble;
* it never loads one, and no .lua, .ps1 or .py reads p3b's copies [grepped, T-P0-138 §3]. **The
* renderer gate is a different probe with its own flags and is untouched.**
* ★★★ pic_fill.s's own comment has said the answer since it was written: *"timings come from
* -DPIC_NOCOUNT, where this vanishes entirely"* -- and every p3b timing this project has published
* was taken without it. ★★ -DP3B_PIC_COUNT restores the counters and is the before arm.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifndef  P3B_PIC_COUNT
PIC_NOCOUNT     equ     1
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ UNCONDITIONAL SINCE T-P0-118, AND THE PRICE IS NOT WHAT P6.63 SAID IT WAS. That report
* -- mine -- called relocating vm_tables "626 B for a two-line conditional, the mechanism six arms
* already use". ★★★★★ **It is not free: the space the tables move INTO is the space freed by
* shrinking this seed stack from 384 entries to 128.** The two are one change and always were;
* the text arms took both together at T-P0-091 and the paragraph above says so in as many words
* -- *"the cel build has no font and no font pressure, so it keeps the engine's seed stack"*.
* ★★★★ SO THE TRADE, STATED: 626 bytes of region A in exchange for a fill seed stack of 128
* entries instead of 384. **The peak measured across the 45 gated pictures is 37** [above], so 128
* is a 3.5x margin -- ★★★ but that is a CORPUS measurement and not a bound [L-86], and the margin
* the cel arm gives up is real.
* ★★★ THE FAILURE IS LOUD, WHICH IS WHY IT IS TAKEABLE: pic_fill's ff_push compares against
* STACK_TOP-2 and HALTS. A picture that needs more fails visibly with an attributable cause rather
* than wrapping the stack into code.
* ★★ AND THE GATE DOES NOT COVER IT: the renderer's 45/45 runs on pic_probe.s, which declares its
* own STACK_TOP. **Nothing gates p3b's seed stack depth**; the evidence is that its rooms render.
                ifdef   P3B_STACK_FULL
STACK_TOP       equ     MAP_SEEDSTACK_E         ; ★ the engine's 384 entries -- the pre-T-P0-118
                else                            ;   cel-arm shape, kept as a fault/comparison arm
STACK_TOP       equ     MAP_SEEDSTACK+256       ; 128 entries; engine reserves 384
                endc
* ★★★ $0200-$0480 is what that frees. $0480-$0500 is left as margin below the hardware stack,
* whose own low-water is measured at S=$07C6 -- 710 bytes clear of its $0500 floor.
P3_TABLES_BASE  equ     MAP_SEEDSTACK+256
P3_TABLES_LIMIT equ     $0480
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHAT IS LINKED, SAID DIRECTLY [T-P0-118]. Sixteen sites in this file tested `P3B_NO_CEL`
* to mean three different things -- "the text engine is linked", "the compositing path is linked",
* and "this is the stripped configuration" -- and those were the same question only for as long as
* the two were MUTUALLY EXCLUSIVE. ★★★★★ **They stopped being exclusive when CP_CEL left
* MAP_RESERVED**, so the flag can no longer answer all three.
* ★★★ Each site now names the thing it actually depends on. `P3B_NO_CEL` keeps its meaning --
* the stripped, text-only configuration whose six gate rows must keep working -- and
* `-DP3B_COMBINED` is the third shape: cels AND text in one binary.
                ifndef  P3B_NO_CEL
P3B_CEL_LINK    equ     1               ; view_cel.s + composite.s are linked
                endc
                ifdef   P3B_NO_CEL
P3B_TEXT_LINK   equ     1               ; src/engine/text.s is linked
                else
                ifdef   P3B_COMBINED
P3B_TEXT_LINK   equ     1
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ P3B_VBL_KEYS -- THE KEYBOARD IS SCANNED AT VERTICAL BLANK, NOT AT THE CYCLE RATE [T-P0-128].
* p3_poll_dir scanned once per interpreter cycle, which with four sprites is 2.6 times a second
* [P6.74's measurement], so a keypress had about a one-in-three chance of falling between polls.
* ★★★★★ AND IT SAMPLED A LEVEL WHERE THE ORACLE DELIVERS AN EDGE. ScummVM enqueues on KEYDOWN only
* and DISCARDS OS auto-repeat for direction keys [keyboard.cpp:226-242, `!event.kbdRepeat`], so a
* held arrow is ONE event. A per-cycle level scan sees a held key on every cycle, and the
* same-direction-stops rule [keyboard.cpp:537-611] then toggles the ego: set, stop, set, stop.
* **Holding an arrow -- which is what I told Jay to do -- made it worse.**
* ★★★★ So the latch records KEY-DOWN TRANSITIONS at 60 Hz and the cycle drains them. Both defects
* go with one mechanism.
* ★★★ COMBINED ARM ONLY. It needs P3B_IRQ (a VBL to scan in) and P3B_CEL_LINK (p3_poll_dir, the
* drain point). `p3b` has no IRQ and keeps its per-cycle scan -- one owner of the PIA either way --
* and the five text arms stay byte-identical. -DP3B_FAULT_NOVBLKEYS is the fault arm.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ OPT-IN, BECAUSE IT FAILED ITS EYE GATE [T-P0-128]. Headless it delivers every press (20 of
* 20, against 10 of 20 for the per-cycle scan). Jay, playing it: **"after a few cycles of animation
* the game goes into a loop with everything animating, but nothing moving just flashing including
* graham."**
* ★★★★ THE LEADING SUSPECT IS EDGE BOUNCE, NOT PROVEN: a coded arrow post produced ~5 captured
* edges per press (40 from 8). Each extra edge of the same arrow is "the same direction again",
* which STOPS the ego [keyboard.cpp:537-611] -- go, stop, go, stop -- and a walk cycle animating in
* place is very close to what Jay describes. The per-cycle scan at 2.6 Hz sampled too slowly to see
* bounce; a 60 Hz edge detector sees all of it. **It needs debouncing before it ships.**
* ★★★ NOT REPRODUCED HEADLESS: coded arrows do not register as directions in EITHER arm, and the
* stall the headless run does reach is a message box that occurs in BOTH arms -- pre-existing, and
* a blocking box stops cycling, so it cannot be the flashing Jay saw.
* ★★ So it stays in the tree behind -DP3B_VBLKEYS_OPT, with every instrument, and the combined arm
* ships the per-cycle scan it had before this task.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PARKED, AT JAY'S DIRECTION [T-P0-129 §2]. WHOEVER RE-OPENS THIS STARTS FROM THE ALLIGATORS,
* NOT FROM BOUNCE -- the paragraph above was written before this was noticed, and it points the
* wrong way:
*   1. MEASURED, THEN FAILED. Headless it captured 20 of 20 presses against the per-cycle scan's
*      10 of 20. Live, Jay: "everything animating, but nothing moving just flashing including
*      graham."
*   2. ★★★★★ THE ALLIGATORS STOPPED TOO, AND THEY NEVER READ A KEY -- they move by wander. So
*      bounce explains Graham and cannot explain the alligators; something that corrupts shared
*      STATE explains both. Bounce is not the leading suspect for the whole symptom.
*   3. THE LEAD, UNVERIFIED: HAL_key_scan was written for the main loop and keeps its scratch in
*      the direct page ($0000-$0020). Called from inside an interrupt, it overwrites any DP byte
*      a main-loop HAL routine was holding at the instant the IRQ landed, and that routine then
*      resumes on corrupted scratch. [no-ref: DP overlap between HAL_key_scan and the routines it
*      can interrupt -- discharge at re-open, by listing both sets of DP addresses]
*   4. ★★★★ A SHIPPED DEFECT THIS DOES NOT DEPEND ON: p3_poll_dir samples the key LEVEL once per
*      cycle where the oracle delivers one EDGE per press [keyboard.cpp:226-242], so a held arrow
*      reads set, stop, set. That is live in the combined arm today, latch or no latch.
*      ★★★★★ FIXED AT T-P0-131, WITHOUT THE INTERRUPT: p3_key_edge is one edge detector, and this
*      latch's CONSUMER SHAPE now ships in every arm -- p3_poll_dir dispatches, p3_poll_key drains,
*      tx_wait_dismiss takes edges. **What remains parked here is only the 60 Hz CAPTURE**: an edge
*      that starts and ends between two scans is still lost, and catching it needs the interrupt.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ UNPARKED AND SHIPPED AT T-P0-132, AND BULLET 2 WAS RIGHT: IT WAS STATE CORRUPTION.
* P6.78 found the compositor writing sprite pixels into KQ1's staged volume through slot 6, which
* corrupted LOGIC 1 and sent it into the alligator-death block -- program.control, stop.motion,
* follow.ego on both alligators, print(1). **That is "everything animating, but nothing moving just
* flashing including graham", and it stopped the alligators too, which bounce never could.**
* ★★★★★ THE LATCH WAS JUDGED ON A BUILD THAT WAS CORRUPTING ITS OWN GAME DATA. Re-tested on
* P6.78's base [T-P0-132 Part A]: 20 of 20 presses delivered against 1 of 20 for the per-cycle
* scan; 420 castle cycles with everything moving exactly as the oracle-gated reference does, ego
* and both alligators, with NO latch-specific difference; logic 1's resident copy 0 of 256 bytes
* differing at the end. Jay, playing it: taps register without holding, and **"3. yes"** to
* "does everything keep moving".
* ★★★ THE BOUNCE SUSPICION IS RETIRED, NOT DISPROVEN: ~5 captured edges per coded post was real,
* but it was measured through natkeyboard's synthetic posts, not a finger, and the symptom it was
* invoked to explain is now accounted for. **If a real key ever bounces, the queue is where a
* debounce goes.**
* ★★ -DP3B_FAULT_NOVBLKEYS is the fault arm: the per-cycle scan, which measures 1 of 20.
                ifdef   P3B_COMBINED
                ifndef  P3B_FAULT_NOVBLKEYS
P3B_VBL_KEYS    equ     1
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SHIPPED COMBINED ARM DOES NOT COUNT PIXELS [T-P0-130 removal 1].
* cp_composite called co_inc32 -- a 32-bit software increment through U -- for EVERY source pixel,
* and again per reject and per control step [composite.s:181-191, 236-239, 347-350, 474-476,
* 585-588]. **P6.76 profiled that at 11.9% of a castle cycle**: a measuring instrument left on in
* the build being measured.
* ★★★★ THE INSTRUMENT MOVES, IT DOES NOT DISAPPEAR. -DP3B_COUNT is the counting arm and keeps every
* p3b readout that reads co_tested / co_written / co_rejkey / co_rejpri -- p3b_run.lua's sprite and
* rectangle readouts and p3b_show.ps1's want-line, which gate on the same condition as this block.
* ★★★ IN THE SOURCE AND NOT ON A COMMAND LINE, so every builder of the combined arm -- p3b_show.ps1,
* p3b_arms_check.ps1, a hand build -- gets the shipped form without being told.
* ★★ CP_BLITS is NOT a counter this removes: it is one add per COMPOSITE, not per pixel
* [composite.s:140-142], so "how many cels composited" survives in both arms.
* ★★ The cel arm (`p3b`) keeps counting: it is not the shipped build, and gates.manifest's rows
* for it quote co_tested and co_rej_pri as their evidence.
                ifdef   P3B_COMBINED
                ifndef  P3B_COUNT
COMP_NOCOUNT    equ     1
                endc
                endc
* ★★★★ P3B_KEY_DISPATCH -- p3_poll_dir is linked, so IT is the per-cycle key dispatcher and
* p3_poll_key only drains what it forwards [T-P0-131]. Same nesting as p3_poll_dir's definition.
                ifdef   P3B_CEL_LINK
                ifdef   HAL_KEYBOARD
P3B_KEY_DISPATCH equ    1
                endc
                endc
* ★★★★★ PIC_WIRED -- the game's own picture opcodes are REAL in this build [T-P0-121]. Every
* p3b configuration links the renderer (pic_render_at) and owns both planes, so unlike
* TEXT_WIRED this is not conditional on an arm: the thing it needs is always present.
* ★★★ It is still a NAMED flag rather than an unconditional include, because vm_pic_ops.s is
* shared with vm_probe -- which has no renderer -- and the name is what makes that build's
* three `equ`s to vm_op_modelled a decision instead of an accident.
* ★★★★★ AND -DP3B_ROOMDRIVE TURNS IT OFF, WHICH IS WHAT MAKES THAT ARM A REAL COMPARISON. With
* PIC_WIRED still on, the room detector AND the opcodes would both render -- twice per room --
* and the arm would measure a configuration nobody has ever shipped. **Off, it is exactly the
* binary this task started from**: three modelled opcodes and a detector driving the screen.
                ifndef  P3B_ROOMDRIVE
PIC_WIRED       equ     1
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

* ── the subsystems' instrumentation: the ADDRESSES are required, the COUNTING is not ──
* ★★★ THE ADDRESSES ARE REQUIRED TO ASSEMBLE. pic_draw.s does `ldd CNT_VERT / addd #1 /
* std CNT_VERT` with no guard, and pic_core.s does the same for CNT_PIX. **Those two are the
* genuinely unguarded pair** and they are per-LINE and per-PIXEL, not per fill-check.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THE SENTENCE THAT STOOD HERE WAS FALSE, AND IT COST 29.4% OF A ROOM CHANGE.
* It read: *"composite.s guards its counters behind -DCOMP_NOCOUNT; **the renderer has no such
* switch**"* -- and concluded that "a shipped renderer cannot currently be built without its
* counters". ★★★★★ **The renderer has had exactly such a switch since pic_fill.s was written:
* PIC_NOCOUNT, tested in SIXTEEN places across pic_fill.s and pic_core.s**, and pic_fill.s's own
* comment says "timings come from -DPIC_NOCOUNT, where this vanishes entirely".
* ★★★★ WHAT THE WRONG SENTENCE COST: fc_count -- a `ldd CNT_CHK+2 / addd #1 / std` in the flood
* fill's innermost loops -- was **29.4% of the room-change cycle**, the largest single routine in
* it, until T-P0-138 defined the flag. **Room change 9.5456 -> 6.1579 s for one `equ`.**
* ★★★★★ THE SHAPE, AND IT IS THE THIRD INSTANCE: A COMMENT ASSERTING AN ABSENCE, WITH NOTHING
* ABLE TO MAKE IT FAIL. The others are res_core.s's *"this is the ONLY routine that writes it"*
* about $FFA6 [P6.79, two shipped defects] and this file's *"no reader"* [P6.71]. ★★★ A negative
* claim in prose is the one kind of comment that cannot decay LOUDLY: the code stays correct while
* the sentence stops being true, so nothing ever contradicts it.
* ★★ The instrument inventory below is the answer to "which of these is on": a table, not a
* sentence, and one a future reader can check against the build.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ INSTRUMENT INVENTORY [T-P0-139 §4A]. Every conditional instrument in the tree, and
* whether a p3b arm pays for it. **ON-BY-DEFAULT ones are `ifndef` -- they cost unless disabled.**
*
*   flag            sites  what it counts              disabled in p3b by
*   PIC_NOCOUNT       16    fill checks, line/px paths  THIS FILE, all arms   [T-P0-138]
*   COMP_NOCOUNT       6    composite pixels tested/    THIS FILE, COMBINED arm only  [T-P0-130]
*                           written/rejected            ★ LIVE in the `p3b` cel arm, deliberately:
*                           gates.manifest's rows quote co_tested and co_rej_pri as evidence,
*                           so the answer there is a counting ARM, not a switch. Cost when on:
*                           11.9% of a castle cycle [P6.76].
*   VM_NOCOUNT         5    opcodes and tests seen      THIS FILE, all arms but -DP3B_COVERAGE
*                                                       [T-P0-102; P6.46 -- these CORRUPTED game
*                                                       data before they were guarded]
*
* ★★★ OPT-IN (`ifdef`) instruments cost nothing unless a flag is passed, and **none is `equ`'d in
* any source file** -- checked, not assumed: RES_CHECKSUM, VM_TRACE, VM_IFDIAG, VM_SAIDDIAG,
* VM_VAR0DIAG, VM_OBJCENSUS, TX_MSGDIAG, P3B_SPRSTATS, P3B_COVERAGE, P3B_CELTEST,
* P3B_VIEWHDR_TEST, P3B_PICSTEPS, RES_TEST_TRIMALL.
* ★★ No shipped arm's flag set names one [p3b_arms_check.ps1: $BASE, $TEXT and the two combined
* rows contain no instrument flag].
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
                ifdef   P3B_CEL_LINK
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ CP_CEL LEAVES REGION A [T-P0-118, Jay's ruling on P6.63's 221-byte shortfall]. It was
* MAP_RESERVED_END-256 = $5F00, the top page of the reservation; it is now MAP_INPUT's tail.
* ★★★★★ THAT RETURNS 256 BYTES TO REGION A, which is what closes the gap: P6.63 measured the
* combined build 221 B over after vm_tables relocated, and 256 - 221 = 35 B to spare.
*
* ★★★★★ AD-191'S CLOSURE DOES NOT APPLY, AND THE SCOPE MATTERS. That ruling killed moving a
* **4,784-byte** staging buffer SIXTEEN BYTES UP, because the buffer overlapped MAP_ARENA_WIN by
* 1,456 bytes and every write moved closer to the arena the decode was READING FROM. ★★★★ This is
* a **256-byte row buffer** and the move is DOWNWARD, out of the reservation entirely -- the
* opposite direction, a different buffer, and a different hazard. **Do not re-apply the closed
* ruling to this move; read its scope.**
*
* ★★★★ MAP_INPUT IS SAFER THAN $5F00, not merely available. $1C00 is in SLOT 0, which nothing
* remaps -- the property P3_PBUF was put there for and which vm_text_ops.s's hazard 1 depends on.
* $5F00 sat directly below MAP_ARENA_WIN at $6000, which is live during the decode. ★★★ A row
* buffer resident in every phase has no adjacency to the arena at all.
*
* ★★ THE TAIL, AND ITS ARITHMETIC MEASURED NOT ASSUMED: MAP_INPUT is $1C00-$2000 = 1,024 B.
* P3_PBUF takes TXT_PBUF_MAX (576 max) from the base; P3_TXDIAG and P3_RBTRACE both sit at +576
* and are 96 B at most. 576 + 96 = 672, so the tail begins at MAP_INPUT+672 = $1EA0 and runs
* 352 bytes to $2000. CP_CEL needs 256, leaving 96.
CP_CEL          equ     MAP_INPUT+672           ; ★ $1EA0. ONE ROW; VC_ROW_MAX is the format's max
CP_CEL_BYTES    equ     256
                ifgt    CP_CEL+CP_CEL_BYTES-MAP_INPUT_END
                error   "CP_CEL overruns MAP_INPUT -- the decoded-cel row no longer fits in the tail left by P3_PBUF and the diagnostic records; re-measure MAP_INPUT's occupancy before moving it again"
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE KEY QUEUE, AND IT MUST BE IN SLOT 0 [T-P0-128]. It is written from the VBL interrupt,
* which can fire in ANY phase -- including the text window, which borrows slots 3-6 -- so the
* buffer has to be mapped in every one of them. Slot 0 is never remapped [mmu_phase.s].
* ★★★★ CP_CEL ends at MAP_INPUT+672+256 = $1FA0, so $1FA0-$1FFF is 96 bytes nothing owns. (The
* P3_RBTRACE collision message below still says "$1F60"; +928 is $1FA0 and that figure is stale.)
* ★★★ SINGLE PRODUCER, SINGLE CONSUMER, SO NO INTERRUPT MASKING: the IRQ writes only TAIL and the
* drainer writes only HEAD, and a byte store is atomic on a 6809.
* ★★★ These are ADDRESSES, not fcb -- the image does not initialise them, so init clears them
* before IRQs are enabled.
                ifdef   P3B_VBL_KEYS
P3_KQ           equ     CP_CEL+CP_CEL_BYTES     ; $1FA0
* ★★★★ 16, THE ORACLE'S KEY_QUEUE_SIZE [agi.h:571]. The first build used 8 and a per-frame ENTER
* poster DROPPED 33 of 110: keys pile up during a ~8 s picture render, when nothing drains, and 7
* usable slots (one is the full/empty sentinel) is under 4 seconds of a person tapping. 16 costs
* 8 more bytes of the 96 free.
P3_KQ_SIZE      equ     16                      ; a power of two: the index wraps with a mask
P3_KQ_HEAD      equ     P3_KQ+P3_KQ_SIZE        ; written ONLY by the drainer
P3_KQ_TAIL      equ     P3_KQ_HEAD+1            ; written ONLY by the IRQ
P3_KQ_LAST      equ     P3_KQ_TAIL+1            ; the key the IRQ saw last frame -- the edge detector
P3_KQ_NIN       equ     P3_KQ_LAST+1            ; edges enqueued, for the host
P3_KQ_NDROP     equ     P3_KQ_NIN+1             ; edges dropped on a full queue, for the host
P3_KQ_NOUT      equ     P3_KQ_NDROP+1           ; keys drained, for the host
P3_KQ_END       equ     P3_KQ_NOUT+1
                ifgt    P3_KQ_END-$2000
                error   "the VBL key queue overruns slot 0 -- it must end at or below $2000"
                endc
                endc
                ifgt    MAP_INPUT+672-CP_CEL
                error   "CP_CEL starts inside P3_PBUF or the diagnostic records -- it must begin at or after MAP_INPUT+672"
                endc
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
                ifdef   P3B_TEXT_LINK
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
                ifdef   P3B_TEXT_LINK
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
                ifdef   P3B_TEXT_LINK
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE KEY LATCH CHAINS IN FRONT OF THE SHARED HANDLER, IT DOES NOT MODIFY IT [T-P0-128].
* irq_vbl.s is SHARED with POP and Karateka and hal_sync_check.py gates it three ways. **This probe
* already owns the first hop** -- it writes this very JMP because its MMU remap destroyed the ROM's
* -- so pointing the JMP at p3_irq, which latches and then JMPs to hal_vbl_handler, adds a stage
* without touching a shared byte. §2M.
                ifdef   P3B_VBL_KEYS
                ldx     #p3_irq
* ★★★ Clear the queue BEFORE the IRQ can write it: these are raw slot-0 addresses and hold whatever
* RAM held.
                clr     P3_KQ_HEAD
                clr     P3_KQ_TAIL
                clr     P3_KQ_LAST
                clr     P3_KQ_NIN
                clr     P3_KQ_NDROP
                clr     P3_KQ_NOUT
                else
                ldx     #hal_vbl_handler
                endc
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
                jsr     p3_enter_vm_phase       ; ★ AC-7: no plane mapped
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE BODY OF THIS MOVED TO p3_enter_vm_phase [T-P0-121] AND THE REASON IS §2F. draw.pic
* and show.pic now run INSIDE p3_run_vm and both disturb slots 5 and 6, so each has to put the
* VM phase back before the handler returns -- and the loop continues into p3_stage_sprites,
* which reads the object table through slot 5. **Three callers of one sequence is one routine.**
* ★★★★ THE ALTERNATIVE WAS A THIRD COPY OF "what slot 5 holds", and this file already carries
* two -- ph_blk_slot5 in the text arms and the `#$3D` literal in the cel arm. mmu_phase.s:234-239
* says what a second opinion costs: *"declaring a second would let the two restores disagree."*
* The comments that explained each step moved with the code and are unchanged at the routine.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                bra     p3_after_vm_phase
p3_enter_vm_phase:
                jsr     phase_vm
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
                rts
* ★★ The `bra` above jumps this body; the routine sits inside the loop rather than beside
* phase_draw_enter so its comments stay where they were written, and the whole change reads as
* a factoring rather than a move [3 bytes: the bra and the rts].
p3_after_vm_phase:
                ifdef   P3B_VIEWHDR_TEST
                jsr     p3_vh_test              ; ★ T-P0-130 AC-8, test arm only
                endc
                ifdef   P3B_CELTEST
                jsr     p3_ct_test              ; ★ T-P0-136 AC-4, test arm only
                endc
* ★★★ AC-5's brackets. One `sta` per boundary; the host tap does the arithmetic. Placed around
* the calls rather than inside them so a stage's cost includes its own call overhead, which is
* what a budget consumer cares about.
* ★ p3_run_vm emits 1/2 (pace) and 3/4 (interpret) itself; the outer stages continue from 5.
* ★★★★★ THE KEY IS READ BEFORE THE CYCLE, AND THE ORDER IS THE ORACLE'S [T-P0-115]. ScummVM polls
* input in mainCycle and handleController writes VAR_EGO_DIRECTION; interpretCycle THEN copies
* that variable into the ego's direction [cycle.cpp:256-259, mirrored at vm_cycle.s:212-219].
* Reading the key after p3_run_vm would land the direction one whole cycle late.
                ifdef   P3B_CEL_LINK
                ifdef   HAL_KEYBOARD
                jsr     p3_poll_dir
                endc
                endc
                jsr     p3_run_vm
                lda     #5
                sta     P3_PHASE
                jsr     p3_stage_sprites        ; ★ BEFORE the remap -- slot 5 still holds VM_OBJ
                lda     #6
                sta     P3_PHASE
                lda     #7
                sta     P3_PHASE
                jsr     p3_room_check           ; ★ now a DIAGNOSTIC only -- see the routine
* ★★★★★ DRAIN A DEFERRED draw.pic HERE AND NOWHERE ELSE. This is the first point in the cycle
* where res_depth is 0, which is the only depth at which res_open may evict the logic cache
* [res_core.s:309-314]. ★★ After p3_room_check so the published room is current if it renders.
                jsr     p3_pic_pending
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
                ifdef   P3B_CEL_LINK
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
* ★★★★★ CORRECTED [T-P0-130, from P6.76 §3(2)]: vm_pace IS NOT A WAIT IN REAL TIME. It spins
* vm_step_clock -- a counter -- until vm_passed reaches vm_tdelay (var 10 x 3), which is SIX
* counter steps for KQ1 whatever the wall clock says, measured at 0.00065 s a cycle, 0.2%. It
* reproduces the reference's VIRTUAL clock so cycle count and the game timers (vars 11-14) track
* each other [vm_cycle.s:307-311]; **it does not hold the port to the rate the game asked for.**
* ★★★★ So nothing paces this port to real time. At 0.25-0.30 s a cycle that is harmless; once a
* cycle fits inside KQ1's 100 ms it will run too fast, and a VBL-based pace becomes necessary.
* ★★ The history, kept because it was believed: this said "a BUSY-WAIT ... deliberately hitting
* the rate the GAME asked for", and the split below was made on that belief. Timed as one "vm"
* stage it read 0.156 s/cycle and 6.66 cycles/second.
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ VM_VAR_KEY IS STILL NOT WRITTEN HERE, AND THE REASON HAS CHANGED [T-P0-124]. The old text
* is kept because it was TRUE WHEN WRITTEN and the next reader needs to see why:
*
*     "VM_VAR_KEY is NOT written here. cycle.cpp does set var 19, but the opcodes that read it
*      are not wired and writing it would be a side effect with no reader."
*
* ★★★★★ THE READER WAS WIRED AFTERWARDS, IN ANOTHER FILE, BY A TASK ABOUT SOMETHING ELSE.
* vmtest_have_key reads VAR 19 [vm_tests.s:154-159] and the table dispatches to it
* [vm_tables.s:324]. **So the justification expired and nothing anywhere re-checked it**, and the
* title screen waited on a flag that was cleared every cycle and set never [P6.70's measurement].
* ★★★ That is the AD-28 / X-33 class -- a note describing how the port ARRIVED, read ever after as
* describing how it IS. **Dated now, so the same thing cannot happen silently twice.**
*
* ★★★★ WHAT IS TRUE TODAY, and it is a different statement: the publish belongs on the UNGATED
* scan, and this routine is the GATED one. cycle.cpp sets VAR 19 regardless of the prompt and
* hands the key to the editor only when the prompt is enabled [cycle.cpp:347-352] -- so the
* publish lives in p3_poll_dir's "not a direction" branch, which runs every cycle, and this
* routine keeps its txt_penab guard because that guard is about the EDITOR.
* ★★★ GUARDED, AND THE FIRST DRAFT GUARDED ONLY THE CALL. The cel configuration links neither
* text.s nor the keyboard HAL, so an unguarded body here is three undefined symbols -- and lwasm
* then reported the CP_CEL collision guard as well, from a pass that had already failed. **The
* second error named a region that was fine** (P3_CODE_END $52F8 against CP_CEL $5300, eight bytes
* spare, exactly as always), which is how a cascade sends the reading to the wrong place.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ p3_key_edge -- ONE PRESS, ONE EVENT [T-P0-131]. THE ONLY SCANNER OF THE MATRIX OUTSIDE
* THE VBL ARM.
* ★★★★★ THE ORACLE DELIVERS ONE EVENT PER PRESS. Keys are enqueued on EVENT_KEYDOWN only, and
* platform auto-repeat is discarded for the direction keys [keyboard.cpp:224-262, `if
* (_allowSynthetic || !event.kbdRepeat)`, and :333-334]. **Every former reader here sampled the
* LEVEL**: p3_poll_dir once per cycle, p3_poll_key's fallback once per cycle, p3_key_latch on every
* pass of the park loop, and tx_wait_dismiss on every pass of the box's wait.
* ★★★★★ AND A LEVEL POLL GETS WORSE AS THE CYCLE GETS FASTER. A held arrow is sampled once per
* cycle, and the second sample of the same arrow is "the same direction again", which STOPS the ego
* [keyboard.cpp:603-604] -- so it read set, stop, set. A faster cycle takes more samples of the same
* hold. Jay, after P6.77's 18% speed-up: *"the old build took about 3 or 4 to start him moving left.
* the new build didnt move him at all."* **Every speed task would have made it worse.**
* ★★★★ So there is ONE edge detector and every reader goes through it: a key counts only when the
* scan DIFFERS from the last scan and is non-zero. A release (key -> 0) is a change too, and it is
* what resets p3_klast -- so the same key pressed, released and pressed again is two events.
* ★★★ LETTERS AND ENTER ARE EDGES TOO, AND THAT IS A NAMED GAP. The oracle repeats them: the
* `key <= 0xFF` branch at keyboard.cpp:208 has no kbdRepeat test, so ScummVM's platform repeat
* (400 ms, then every 100 ms [common/events.cpp:278-279]) reaches the editor. **That rate is
* ScummVM's, not AGI's**; a port with no OS would have to invent one, and a once-per-cycle poll at
* ~4 Hz could not deliver 100 ms anyway. Edges only, gap stated [T-P0-131 §4A(1)].
* ★★★ -DP3B_FAULT_LEVELKEYS restores the level read: today's behaviour, a known-good red.
                ifdef   HAL_KEYBOARD
                ifndef  P3B_VBL_KEYS
p3_klast        fcb     0               ; what the matrix showed at the last scan; 0 = nothing
* ★★★ ONE EDGE CAUGHT IN THE HARNESS PARK, held for the next cycle's dispatcher. The park is a
* harness construct [p3_wait]; scanning it for edges only catches a tap that falls between two
* cycles. **It shares p3_klast**, so a press seen in the park is not seen again by the cycle.
p3_kpend        fcb     0
* p3_key_edge: A = a newly pressed key, or 0 (Z set). Updates p3_klast either way.
p3_key_edge:
                jsr     HAL_key_scan
                ifdef   P3B_FAULT_LEVELKEYS
                tsta                            ; ★ INJECTED: the level, every call
                rts
                else
                cmpa    p3_klast
                beq     pke_none                ; unchanged: still held, or still nothing
                sta     p3_klast
                tsta                            ; a release is 0: remembered, not an event
                rts
pke_none:       clra
                rts
                endc
* p3_key_event: the pending park edge if there is one, else a scan. A = key or 0 (Z set).
p3_key_event:
                lda     p3_kpend
                beq     p3_key_edge
                clr     p3_kpend
                tsta
                rts
                endc
                endc

                ifdef   TEXT_PROMPT
* ★★★★ THE LATCH IS ONE BYTE DEEP AND IT DOES NOT OVERWRITE. A second key arriving before the
* cycle consumes the first is DROPPED rather than replacing it, which is the same thing a
* one-character queue does and is what keeps the order right: replacing would deliver the second
* character and lose the first, so a fast "lo" would read as "o".
* ★★★ It scans only while the prompt is enabled, so a disabled command line costs nothing and a
* stray key cannot sit latched across an accept.input.
p3_keybuf       fcb     0
p3_key_latch:
* ★★★★★ A NO-OP IN THE VBL ARM [T-P0-128]. This park-loop latch was a harness stand-in for the
* key queue the port did not have [see its header at p3_wait]; the VBL latch IS that queue, and a
* second scanner here would be the §1.2 hazard -- two owners of the PIA's column register.
                ifdef   P3B_VBL_KEYS
                rts
                else
* ★★★★★ AN EDGE INTO THE PENDING SLOT, NOT A LEVEL INTO THE EDITOR'S BUFFER [T-P0-131]. This
* latched the matrix LEVEL into p3_keybuf on every pass of the park while the buffer was empty, so a
* held letter reached the editor once per cycle for as long as it was held. It now records only a
* NEW press, for any key and whatever the prompt state -- the dispatcher decides what a key is for.
                lda     p3_kpend
                bne     pkl_out                 ; one deep: do not overwrite an unread edge
                jsr     p3_key_edge
                beq     pkl_out
                sta     p3_kpend
pkl_out:        rts
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ p3_poll_key -- DRAINS, IT DOES NOT SCAN, WHERE p3_poll_dir IS THE DISPATCHER [T-P0-131].
* It took the latched key and FELL BACK TO A LIVE SCAN, which made it the second per-cycle reader
* of the matrix beside p3_poll_dir -- two level reads a cycle, and a held letter reached the editor
* repeatedly. **One scanner, one dispatcher** [cycle.cpp:347-351]: p3_poll_dir takes the edge, runs
* the direction test, publishes VAR 19, and forwards to p3_keybuf if the prompt is enabled; this
* drains p3_keybuf. That is the VBL arm's consumer shape, shipped without its interrupt.
* ★★★ In a TEXT-ONLY arm there is no p3_poll_dir, so this is the dispatcher there and takes the
* edge itself -- still the one detector, still one read a cycle. It reads EVERY cycle, prompt or
* not, so p3_klast tracks releases; with the prompt disabled the event is dropped, as
* promptKeyPress is not called [cycle.cpp:350-351].
* ★★ p3_keybuf is still drained first: it is where p3_poll_dir forwards AND where P3B_INJECT writes
* [p3b_run.lua], so p3b_row22's path is unchanged.
p3_poll_key:
                lda     txt_penab
                beq     ppk_track
                lda     p3_keybuf
                beq     ppk_scan
                clr     p3_keybuf
                bra     ppk_have
ppk_scan:
                ifdef   P3B_VBL_KEYS
                bra     ppk_out                 ; the IRQ owns the PIA [T-P0-128]
                else
                ifdef   P3B_KEY_DISPATCH
                bra     ppk_out                 ; p3_poll_dir already took this cycle's edge
                else
                jsr     p3_key_event
                beq     ppk_out
                endc
                endc
ppk_have:
                sta     P3_KEY
                inc     P3_NKEY
                jmp     txt_pkey
ppk_track:
* ★★ Prompt disabled. In a text-only arm this is still the cycle's one read, so it is taken and
* discarded rather than skipped -- skipping would let a key held across accept.input fire late.
                ifndef  P3B_VBL_KEYS
                ifndef  P3B_KEY_DISPATCH
                jsr     p3_key_event
                endc
                endc
ppk_out:        rts
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ p3_poll_dir -- A KEY BECOMES A DIRECTION. THE JOIN, AND IT IS ALL THAT WAS MISSING.
*
* ★★★★★ EIGHT TASKS WERE BLOCKED BEHIND THIS AND NONE OF THEM NEEDED NEW MACHINERY. The key
* decoder is gated 10/10 [P6.24]; loop-selection-from-direction is ported from the pinned oracle
* and lives in vm_objects.s:151-183 with both of the oracle's tables; update_position moves the
* ego; vm_cycle.s:212-219 already copies VAR_EGO_DIRECTION into VMO_DIR under player control.
* **Every subsystem was green and nothing called between them** -- P6.28d's shape, fourth time
* this arc.
*
* ★★★★ THE ORACLE, AND EVERY LINE BELOW IS ONE OF ITS LINES [keyboard.cpp:537-611, §2 tier 3]:
*     UP=1  UP_RIGHT=2  RIGHT=3  DOWN_RIGHT=4  DOWN=5  DOWN_LEFT=6  LEFT=7  UP_LEFT=8
*     if (screenObjEgo->direction == newDirection) setVar(VM_VAR_EGO_DIRECTION, 0);
*     else                                        setVar(VM_VAR_EGO_DIRECTION, newDirection);
* ★★★★★ PRESSING THE CURRENT DIRECTION AGAIN STOPS THE EGO. That is not a simplification of the
* oracle, it IS the oracle, and it is also how the player stops walking without a key-up event --
* which matters here because HAL_key_scan reports matrix STATE and has no key-up at all.
*
* ★★★ FOUR DIRECTIONS, NOT EIGHT, AND THE REASON IS THE SCANNER not a scope decision.
* hal_globals.s:252-256 states it: HAL_key_scan "reports ONE KEY, NOT A SET ... A caller that
* needs simultaneous keys -- a game reading two arrows for a diagonal -- needs the mask". The
* diagonals are reachable only by changing a PROJECT_LOCAL HAL routine's contract, which is a
* separate task; the oracle's 2/4/6/8 are left unimplemented and named here rather than faked.
*
* ★★ NOTHING PRESSED LEAVES THE DIRECTION ALONE. The ego keeps walking until a key says
* otherwise, which is the oracle's behaviour under kMotionNormal and is why a stop needs the
* same-key rule above.
                ifdef   P3B_CEL_LINK
                ifdef   HAL_KEYBOARD
p3_newdir       fcb     0               ; the direction the last accepted key produced
p3_ndirs        fcb     0               ; direction keys accepted, for the host
* ★★★★★ A STICKY COPY OF WHAT WAS PUBLISHED, AND IT EXISTS BECAUSE VAR 19 IS NOT OBSERVABLE.
* vm_post_cycle clears VAR 19 at the foot of every interpreted cycle [vm_cycle.s:347,
* cycle.cpp:577], so a host that samples at the park -- which is where every other readout in this
* probe is taken -- sees zero on every cycle no matter what was published. **The first run of this
* change proved the title screen advanced and could not show the value that advanced it.**
* ★★★ These two bytes are the measurement AC-1 asks for: WHAT was published and HOW OFTEN.
p3_varkey       fcb     0               ; the last key published into VAR 19
p3_nvarkey      fcb     0               ; how many keys have been published
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE VBL KEY LATCH [T-P0-128]. p3_irq is the $FEF7 target in this arm: latch, then the
* shared handler unchanged. A 6809 IRQ stacks the full machine state and hal_vbl_handler ends in
* RTI, so nothing here needs to save a register.
                ifdef   P3B_VBL_KEYS
p3_irq:
                jsr     p3_vbl_latch
                jmp     hal_vbl_handler

* ★★★★★ THE ONLY CALLER OF HAL_key_scan IN THIS ARM [§1.2's hazard]. The PIA's column register is
* a single shared resource: if the main loop were mid-scan when this fired, both would read rows
* for a column the other had set. **One owner of the PIA**, the same rule mmu_phase.s holds for the
* MMU [§2N]. p3_poll_dir, p3_poll_key and the park-loop latch all DRAIN in this arm.
* ★★★★★ AN EDGE, NOT A LEVEL. Enqueue only when the scanned key DIFFERS from last frame's and is
* non-zero: a held key is one event, a release is remembered but not enqueued. That is the
* oracle's KEYDOWN-only enqueue with OS auto-repeat discarded [keyboard.cpp:226-242, 333-334].
* ★★★ ON A FULL QUEUE THE NEWEST KEY IS DROPPED AND COUNTED. The oracle's keyEnqueue has NO full
* check [keyboard.h:27-31]: a 17th key advances END onto START and the queue reads as EMPTY, losing
* all sixteen. **A declared divergence** [§2I]: it preserves every key a person can type at the
* drain rate and loses one instead of sixteen when they cannot.
p3_vbl_latch:
                jsr     HAL_key_scan            ; A = key or 0
                cmpa    P3_KQ_LAST
                beq     pvl_out                 ; unchanged: still held, or still nothing
                sta     P3_KQ_LAST
                tsta
                beq     pvl_out                 ; a release -- remembered, not an event
                ldb     P3_KQ_TAIL
                ldx     #P3_KQ
                sta     b,x                     ; the spare slot when full, so harmless if dropped
                incb
                andb    #P3_KQ_SIZE-1
                cmpb    P3_KQ_HEAD
                beq     pvl_full
                stb     P3_KQ_TAIL
                inc     P3_KQ_NIN
                rts
pvl_full:       inc     P3_KQ_NDROP
pvl_out:        rts

* ── p3_kq_get -- the drainer. out: A = next key, Z set if there was none ──────────
p3_kq_get:
                ldb     P3_KQ_HEAD
                cmpb    P3_KQ_TAIL
                beq     pkg_empty
                ldx     #P3_KQ
                lda     b,x
                incb
                andb    #P3_KQ_SIZE-1
                stb     P3_KQ_HEAD
                inc     P3_KQ_NOUT
                tsta
                rts
pkg_empty:      clra
                rts
                endc

p3_poll_dir:
                ifdef   P3B_FAULT_NOJOIN
                rts                     ; ★ AC-7's arm: the join removed, which is "i can't move him"
                endc
* ★★★★★ DRAIN, DO NOT SCAN, WHEN THE IRQ OWNS THE PIA [T-P0-128]. In the VBL arm this takes the
* next key-down EDGE from the queue; elsewhere it still scans the matrix once per cycle, and the
* main loop is then the PIA's only owner because there is no interrupt to contend with it.
                ifdef   P3B_VBL_KEYS
                jsr     p3_kq_get
                else
* ★★★★★ AN EDGE, NOT A LEVEL [T-P0-131]. This was `jsr HAL_key_scan`: a held arrow re-read every
* cycle, and the second read is "same direction again" = stop. Now a key reaches the tests below
* once per PRESS, so a second press stops the ego -- the oracle's rule [keyboard.cpp:603-604] --
* and a held key does nothing further. The result no longer depends on the cycle rate.
                jsr     p3_key_event
                endc
                beq     ppd_out
                ldb     #1
                cmpa    #HAL_KEY_UP
                beq     ppd_have
                ldb     #3
                cmpa    #HAL_KEY_RIGHT
                beq     ppd_have
                ldb     #5
                cmpa    #HAL_KEY_DOWN
                beq     ppd_have
                ldb     #7
                cmpa    #HAL_KEY_LEFT
                beq     ppd_have
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ NOT A DIRECTION -> PUBLISH VAR 19. THIS IS cycle.cpp:347-349 AND IT IS THE WHOLE FIX.
*     if (!handleController(key)) {
*         // Only set VAR_KEY, when no controller/direction was detected
*         setVar(VM_VAR_KEY, key & 0xFF);
*         if (_text->promptIsEnabled()) _text->promptKeyPress(key);
*     }
* ★★★★★ THE `rts` THAT WAS HERE WAS THE ORACLE'S `return true` FROM handleController AND NOTHING
* ELSE. The routine already computes exactly the predicate cycle.cpp branches on -- "was this key
* consumed as a direction?" -- and then threw the answer away. **One branch, four instructions.**
*
* ★★★★★ WHY THE TITLE SCREEN COULD NEVER ADVANCE [P6.70]. `have.key` is true iff VAR 19 is
* non-zero [op_test.cpp:121-137, vm_tests.s:154-159]; vm_post_cycle clears VAR 19 after every
* interpreted cycle [cycle.cpp:574-577, vm_cycle.s:347]; and nothing wrote it. **A flag cleared
* every cycle and set never is a test that is false forever**, so the script's wait had no exit.
*
* ★★★★ THE PUBLISH RIDES THIS ROUTINE AND NOT p3_poll_key, WHICH IS THE POINT. p3_poll_key is
* gated on txt_penab -- correctly, and that guard is NOT touched by this change -- and the title
* screen calls prevent.input, so nothing on the prompt path ever scans. **This routine is already
* ungated: it is called every cycle whenever the keyboard HAL is linked.** The dispatch expected a
* scan/consume split; none was needed, because the ungated scan already existed here.
*
* ★★★ ORDER, with the oracle's citation and the gap named [§4D]. cycle.cpp is
*     handleController(key)  =  controller bindings, THEN direction keys   [keyboard.cpp:527-535]
*     then, only if unconsumed:  setVar(VAR_KEY)  then the editor if the prompt is enabled.
* ★★★★ CONTROLLER BINDINGS ARE NOT IMPLEMENTED [P6.70: set.key binds a 16-bit keycode and
* HAL_key_scan returns 8 bits], so the port's order today is DIRECTION -> publish -> editor.
* **When set.key lands it goes in FRONT of the direction test, inside this routine, and its
* "consumed" answer joins this same branch.**
*
* ★★ `key & 0xFF` is implicit: HAL_key_scan returns one byte [hal_globals.s:249].
* ★★★★★ AND HAND IT TO THE EDITOR, ONLY IF THE PROMPT IS ENABLED [T-P0-128, cycle.cpp:350-351].
* In the VBL arm p3_poll_key no longer scans -- the IRQ owns the PIA -- so this is where the editor's
* key now comes from. **txt_penab is tested HERE, on the forward, and still in p3_poll_key**: the
* guard is about the CONSUME and it survives exactly as P6.71 left it.
* ★★★ Placed before the publish only because `tst` and `sta` leave A intact and vm_setvar does
* not; both land before p3_run_vm, so the order the logic observes is the oracle's.
* ★★★★ AND NOW IN EVERY ARM, NOT ONLY THE VBL ONE [T-P0-131]: p3_poll_key drains instead of
* scanning, so this forward is the editor's only source of typed keys.
                ifdef   TEXT_PROMPT
                tst     txt_penab
                beq     ppd_nofwd
                tst     p3_keybuf
                bne     ppd_nofwd               ; one deep: do not overwrite an unread key
                sta     p3_keybuf
ppd_nofwd:
                endc
                ifndef  P3B_FAULT_NOVARKEY
                sta     p3_varkey               ; ★ sticky copy -- see below
                inc     p3_nvarkey
                tfr     a,b                     ; B = the key -> the value
                lda     #VAR_KEY
                jsr     vm_setvar
                endc
                rts
ppd_have:
                stb     p3_newdir
* ---- the same-direction-stops rule, read off the ego's CURRENT direction ----------
* ★★★ vm_obj DESTROYS B [vm_cycle.s:201], which is why p3_newdir is stored BEFORE this call and
* re-read after. That clobber cost T-P0-0xx a task when `stb VMO_DIR,x` stored the object index.
                clra
                jsr     vm_obj                  ; X -> ego; B is now scrap
                lda     VMO_DIR,x
                cmpa    p3_newdir
                bne     ppd_set
                clr     p3_newdir               ; pressing the current direction = stop
ppd_set:
                lda     #VAR_EGO_DIRECTION
                ldb     p3_newdir
                jsr     vm_setvar
                inc     p3_ndirs
ppd_out:        rts
                endc
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DP3B_VIEWHDR_TEST -- T-P0-130 AC-8: A STRADDLING HEADER, READ BY THE REAL PATH.
* The corpus has three VIEW header fields whose two bytes sit either side of an 8 KB boundary
* [view_straddle.py] and the nine-title gate reads none of them in 600 cycles -- so the gate cannot
* show the in-place read handles one. This does: once, in the VM phase (called just after
* p3_enter_vm_phase, where res_curblk is true), it runs vm_set_view on a scratch object for the
* view the host poked into p3_vh_view -- the routine set.view runs, loop 0, cel 0 -- and publishes
* what it read. ★★★ The host compares against the view's bytes read offline
* [view_straddle.py --expect]; -DVM_VIEW_FAULT_ONEMAP is the arm that must disagree.
* ★★ Out here and not beside its call: inside the loop body it pushed two short branches out of
* range. **Test arm only: no shipped arm assembles a byte of this.**
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DP3B_CELTEST -- T-P0-136 AC-4: A CEL WHOSE STREAM CROSSES A BLOCK BOUNDARY, DECODED BY
* THE REAL PATH.
*
* ★★★★★ THE CASTLE CANNOT SHOW THIS AND THAT IS THE WHOLE REASON THE HOOK EXISTS. The three views
* the castle composites -- 0, 97, 107 -- have payloads that sit inside one 8 KB block, so 40
* cycles of compositing exercise the cursor's boundary path **zero times**. Seven KQ1 views DO
* straddle [view_straddle.py --construct: 67, 79, 81, 85, 116, 117, 138] and none of them is drawn
* in room 1. ★★★★ **So a green castle run says nothing about the straddle**, which is L-85's shape
* and the reason P6.81's and P6.82's reports each had to name an unexercised path.
*
* ★★★★ WHAT IT DOES: once, in the VM phase, decode EVERY row of (p3_ct_view, loop, cel) through
* whichever source path this build has, and publish a 16-bit sum of the decoded pixels plus the
* cel's geometry and error byte. ★★★ The host runs it on the windowed arm and on -DP3B_VIEW_COPY
* and compares: **the copy path cannot straddle (res_fetch re-derives its pointer per window) and
* the windowed path must, so an equal sum is the claim and an unequal one is the defect.**
* ★★ Test arm only: no shipped arm assembles a byte of this.
                ifdef   P3B_CELTEST
p3_ct_view      fcb     $FF             ; $FF = none, or already run
p3_ct_loop      fcb     0
p3_ct_cel       fcb     0
p3_ct_sum       fdb     0               ; sum of every decoded pixel, all rows
p3_ct_rows      fcb     0               ; rows actually decoded
p3_ct_err       fcb     0
p3_ct_w         fcb     0
p3_ct_h         fcb     0

p3_ct_test:
                lda     p3_ct_view
                cmpa    #$FF
                bne     p3_ct_go                ; ★ an rts, not a branch to the far exit
                rts
p3_ct_go:
                pshs    a
                lda     #$FF
                sta     p3_ct_view              ; ★ once only
                lda     #RES_VIEW
                ldb     ,s+
                ifdef   VC_SRC_WINDOWED
                jsr     res_locate
                else
                jsr     res_open
                endc
                lda     res_err
                beq     p3_ct_got
                sta     p3_ct_err
                rts
p3_ct_got:
                ifdef   VC_SRC_WINDOWED
                ldd     #0
                std     vc_view
                ldd     res_len
                else
                ldx     res_base
                stx     vc_view
                ldd     res_base
                addd    res_len
                endc
                std     vc_srcend
                lda     p3_ct_loop
                sta     vc_loop
                lda     p3_ct_cel
                sta     vc_cel
                ldx     #CP_CEL
                stx     vc_dest
                jsr     vc_decode_begin
                lda     vc_err
                sta     p3_ct_err
                bne     p3_ct_done
                lda     vc_w
                sta     p3_ct_w
                lda     vc_h
                sta     p3_ct_h
                ldd     #0
                std     p3_ct_sum
                clr     p3_ct_rows
p3_ct_rowlp:
                lda     p3_ct_rows
                cmpa    p3_ct_h
                bhs     p3_ct_done
                jsr     vc_decode_row
                lda     vc_err
                sta     p3_ct_err
                bne     p3_ct_done
* ★ sum vc_w bytes of the decoded row; a sum is enough to separate "the same pixels" from
* "different pixels" and needs no host-side buffer.
                ldx     #CP_CEL
                clra
                ldb     p3_ct_w
                beq     p3_ct_rownext
                tfr     d,y                     ; Y = width, the row's byte count
p3_ct_sumlp:    ldb     ,x+
                clra                            ; D = the pixel, zero-extended
                addd    p3_ct_sum
                std     p3_ct_sum
                leay    -1,y
                bne     p3_ct_sumlp
p3_ct_rownext:
                inc     p3_ct_rows
                bra     p3_ct_rowlp
p3_ct_done:
                ifndef  VC_SRC_WINDOWED
                jsr     res_close
                endc
p3_ct_out:      rts
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

                ifdef   P3B_VIEWHDR_TEST
p3_vh_view      fcb     $FF             ; the view to test; $FF = none, or already done
* ★★★ AND WHICH LOOP AND CEL: set_view keeps an object's loop and cel when they are in range, so
* presetting them walks set_loop and set_cel to the straddling field. The first run tested KQ2
* view 209 at loop 0 cel 0 and BOTH arms passed -- that field's high byte is $00 and so was the
* byte the fault read in its place. **A fault a test cannot see is a fact about the test.**
p3_vh_loop      fcb     0
p3_vh_cel       fcb     0
p3_vh_out       rmb     6               ; numloops, numcels, loop, cel, xsize, ysize
* ★★★★★ AND A RAW 16-BIT READ AT A CHOSEN PAYLOAD OFFSET, THROUGH vm_le16 -- THE SAME ROUTINE THE
* HEADER FIELDS USE. The three corpus straddles could not discriminate: KQ2 209's high byte is
* $00, which is also what the fault read in its place, and MUMG 85 / PQ1 233 live in volumes the
* p3b staging cannot hold (§7). **So the straddle is constructed**: the host picks an offset whose
* two bytes sit either side of a block boundary and whose high byte differs from the one the fault
* would read, and this reads it by the production path. $FFFF = skip.
p3_vh_off       fdb     $FFFF
p3_vh_le        fdb     0
p3_vh_obj       rmb     VMO_SIZE        ; a scratch object: never in the object table
p3_vh_test:
                lda     p3_vh_view
                cmpa    #$FF
                beq     pvh_out
                ldx     #p3_vh_obj
                ldb     #VMO_SIZE
pvh_clr:        clr     ,x+
                decb
                bne     pvh_clr
                ldx     #p3_vh_obj
                lda     #100                    ; mid-screen, so the clip leaves x/y alone
                sta     VMO_X,x
                sta     VMO_Y,x
                lda     p3_vh_loop
                sta     VMO_LOOP,x
                lda     p3_vh_cel
                sta     VMO_CEL,x
                lda     p3_vh_view
                jsr     vm_set_view             ; ★ the real path: set_view -> set_loop -> set_cel
                ldx     #p3_vh_obj
                ldu     #p3_vh_out
                lda     VMO_NUMLOOPS,x
                sta     ,u+
                lda     VMO_NUMCELS,x
                sta     ,u+
                lda     VMO_LOOP,x
                sta     ,u+
                lda     VMO_CEL,x
                sta     ,u+
                lda     VMO_XSIZE,x
                sta     ,u+
                lda     VMO_YSIZE,x
                sta     ,u
                ldd     p3_vh_off
                cmpd    #$FFFF
                beq     pvh_noraw
                jsr     vm_le16                 ; ★ the VIEW is still located from set_view
                std     p3_vh_le
pvh_noraw:
                lda     #$FF
                sta     p3_vh_view              ; once
pvh_out:        rts
                endc

* ── p3_room_check — fetch and render the room's PICTURE when the room changes ────
* ★★★ THE FETCH RUNS IN THE VM PHASE AND THE RENDER IN THE DRAW PHASE, and they cannot be
* swapped. res_open needs the VOLUME window, which is slot 6; the renderer needs the FRAMEBUFFER
* slice, which is also slot 6. **The bytes bridge the two because they land in the arena, which
* is resident in both.** Getting this backwards is a remap per picture opcode.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ DEMOTED TO A DIAGNOSTIC [T-P0-121]. This routine used to own FIVE things: detect the
* room change, fetch the PICTURE, clear and render it, present it, and shadow the priority
* plane. **Four of those are the game's to order and are now draw.pic and show.pic.** What is
* left is the one thing the GAME cannot tell the host: which room the VM believes it is in.
*
* ★★★★ THE RULING AND ITS EVIDENCE [§1.2]. The oracle renders at draw.pic into _gameScreen and
* reveals at show.pic via render_Block into _displayScreen [op_cmd.cpp:1178,1212;
* picture.cpp:834-864]. **Our shadow IS _gameScreen and our visible plane IS _displayScreen**,
* so the split needed no new mechanism -- only a caller that is the game rather than a detector.
* ★★★ Measured before it was believed [harness/tools/pic_order.py]: KQ1 cycle 1 issues
* load.pic, configure.screen, draw.pic, two displays, then show.pic. A port driven by room
* detection cannot place the text between the render and the reveal, which is where it goes.
*
* ★★★★★ -DP3B_ROOMDRIVE RESTORES THE OLD DRIVER, and it is the comparison arm rather than a
* fallback: with it defined the detector renders and presents exactly as before, so the claim
* "the game now drives the render" has an arm where it does not. **§2W -- an instrument must be
* shown able to fail.** A build with ROOMDRIVE and the opcodes modelled is today's behaviour.
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
                ifdef   P3B_ROOMDRIVE
* ── the retired driver, kept as the comparison arm ──
                lda     p3_lastroom
                jsr     p3_pic_draw
                jsr     p3_pic_show
                endc
prc_out:        rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── p3_pic_draw -- draw.pic's half: FETCH, CLEAR, RENDER, SHADOW THE PRIORITY PLANE ──
* ★★★★★ A = the picture number, already resolved from the variable by the handler.
*
* ★★★★★ THE FETCH IS FOLDED IN HERE AND load.pic DOES NOT DO IT -- a DECLARED DIVERGENCE under
* §2I, not an oversight. The oracle's load.pic calls loadResource and its draw.pic decodes from
* memory [op_cmd.cpp:1223,1178]. **Our arena is a STACK: res_close rewinds res_top**
* [res_core.s:606-617], so a pointer held from load.pic to draw.pic either dangles at the close
* or costs a permanently-held depth level that a game calling load.pic without draw.pic never
* returns. ★★★ Folding the bracket makes the render read bytes it opened itself.
* ★★ WHAT IT COSTS AND WHAT IT SAVES, stated as §2I requires: it moves a volume-window fetch
* (milliseconds) from one opcode to the next one the game issues, and it removes a dangling
* pointer and a depth leak. **The output is identical; the ordering this task exists to fix is
* unaffected, because the RENDER is what moved and it is still here.**
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE "~2.8 s RENDER" THAT STOOD HERE WAS ANOTHER PROBE'S FIGURE [T-P0-138 §4A]. It is
* pic_variants.sh's `nocount_packed` median -- **pic_probe, FLAT-mapped, counters OFF** -- and it
* was quoted as if it described this build, which is windowed through plane_vis/plane_pri and,
* until this task, had the fill's counters ON. **Three differences from the program it labelled.**
* ★★★★★ MEASURED HERE, cycle 9 of a 40-cycle castle run, markers 13..22 [-DP3B_PICSTEPS]:
*     fetch 0.0204  clear 0.2322  RENDER 8.2797  pri shadow 0.1749  present 0.1967
*     -- 91.0% of a 9.5456 s cycle, reconciling to 95.3% of it
* ★★★★ AND AFTER -DPIC_NOCOUNT LANDED IN THIS PROBE: **RENDER 4.8957 s, the cycle 6.1579 s.**
* ★★★ So the honest sentence is: a room change costs ~6.2 s here and the render is ~4.9 s of it,
* measured on THIS probe in THIS configuration. ★★ Same error class as design spec §7.1's
* `0.039 s/cycle`, which is comp_probe's, and as every s/cycle taken over an undeclared window
* [P6.84]. **A figure is about the program it was measured on.**
* ═══════════════════════════════════════════════════════════════════════════════════════════
*
* ★★★ THE FETCH RUNS IN THE VM PHASE AND THE RENDER IN THE DRAW PHASE, and they cannot be
* swapped -- res_open needs the VOLUME window in slot 6 and the renderer needs the FRAMEBUFFER
* slice in the same slot. The bytes bridge the two because they land in the arena, resident in
* both. ★★ That was true when this code lived in p3_room_check and it is unchanged by the move.
p3_pic_draw:
                sta     p3_picnum
* ★★★★★ THE ARENA AS draw.pic FINDS IT, CAPTURED EVERY TIME AND NOT ONLY ON FAILURE. The whole
* consequence of moving this call inside a running logic is that res_top is no longer wherever
* the main loop left it, and a byte recorded only when the fetch FAILS cannot show the margin on
* the runs that succeed [L-88's shape -- an instrument scoped to the interesting case measures
* the case and not the question].
                ldx     res_top
                stx     p3_drawtop
                lda     res_depth
                sta     p3_drawdepth
* ★★★★★ AND res_ccur, WHICH IS THE NUMBER THAT ACTUALLY BOUNDS THE FETCH. res_top is a bump
* pointer rising from RES_ARENA ($6000 here) and res_ccur is the CACHE's floor descending from
* the top: *"the stack's ceiling is the cache's floor... the two allocators grow toward each
* other"* [res_core.s:281-285], and res_open sets res_ceil from res_ccur.
* ★★★★★ THE FREE SPACE IS res_ccur - res_top AND NOTHING ELSE. My first version of this readout
* computed it against the arena's END and printed "0 bytes free" for an EMPTY arena -- a
* confident number about the wrong quantity, which is §2W.3's defect in the instrument added to
* measure §2W's. **The cache had eaten the arena; the stack had not filled it.**
                ldx     res_ccur
                stx     p3_drawccur
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DP3B_PICSTEPS BRACKETS EACH STEP OF A ROOM CHANGE [T-P0-138 §4A]. Markers 13..22, paired
* odd/even like the outer stages, but accumulated separately by the host because these NEST inside
* roomcheck (7/8) and the stage tap keeps one open slot.
* ★★★★ It exists because "roomcheck 8.9076 s" is a TOTAL and not a budget: it is one cycle's worth
* of fetch, clear, render, shadow and present, and nobody had decomposed it. The published render
* figure beside this routine is ~2.8 s, which leaves about seven seconds attributed to nothing.
* ★★★ Flag-guarded, so every shipped arm stays byte-identical.
                ifdef   P3B_PICSTEPS
                lda     #13
                sta     P3_PHASE
                endc
                lda     #RES_PICTURE
                ldb     p3_picnum
                jsr     res_open
                ifdef   P3B_PICSTEPS
                pshs    a
                lda     #14
                sta     P3_PHASE
                puls    a
                endc
                lda     res_err
                bne     ppd_fail
                ldx     res_base
                stx     p3_picptr
* ★★★ RENDER INTO THE SHADOW. ph_blk_fb selects which four blocks every plane_win call and every
* phase_draw_fb resolves against, so pointing it at the shadow redirects the WHOLE render --
* clear, lines and fills -- with no change to pic_core. **The visible plane keeps the previous
* room on screen throughout, which is now the POINT rather than a side effect**: that is what
* makes draw.pic invisible and show.pic the moment the room appears.
                lda     #P3_BLK_SHADOW
                sta     ph_blk_fb
                jsr     phase_draw_enter
                ifdef   P3B_PICSTEPS
                lda     #15
                sta     P3_PHASE
                endc
                jsr     p3_clear_planes
                ifdef   P3B_PICSTEPS
                lda     #16
                sta     P3_PHASE
                lda     #17
                sta     P3_PHASE
                endc
                ldx     p3_picptr
                stx     pic_ptr
                jsr     pic_render_at
                ifdef   P3B_PICSTEPS
                lda     #18
                sta     P3_PHASE
                endc
* ★★★★★ THE PRIORITY SHADOW BELONGS TO draw.pic, NOT show.pic [§1.2's ruling, §2H's second
* check -- the CALLER carries the scope]. pic_render_at has just written the room's priority
* data into the live plane; from here until the next picture that data is the only record of
* what is underneath a sprite, and every sprite that draws destroys some of it. **It must be
* taken while the plane is still clean, which is before drawAllSpriteLists -- inside draw.pic.**
                ifdef   P3B_CEL_LINK
                ifdef   P3B_PICSTEPS
                lda     #19
                sta     P3_PHASE
                endc
                jsr     p3_pri_shadow
                ifdef   P3B_PICSTEPS
                lda     #20
                sta     P3_PHASE
                endc
                endc
                jsr     res_close
                lda     #1
                sta     p3_drew
                clr     p3_shown                ; ★ state->pictureShown = false [op_cmd.cpp:1210]
                jmp     p3_enter_vm_phase
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ RES_E_FULL ABOVE DEPTH 0 IS NOT A FAILURE, IT IS THE ARENA'S DOCUMENTED REFUSAL, AND
* THIS IS THE ONE THING THE OWNERSHIP MOVE BROKE. res_open recovers from a full arena by EVICTING
* a cached LOGIC and retrying -- **but only at depth 0**, because above it the cached bytes may be
* the bytes currently executing [res_core.s:309-314]. The retired driver ran from the main loop at
* depth 0 and could evict. **draw.pic runs inside a running logic and cannot.**
*
* ★★★★★ AND "EVICT ANYWAY" IS THE APPROACH THAT HALTED ALL NINE TITLES AT CYCLE 0 -- res_core.s
* records it in as many words, as the first version that reset the arena inside new.room. §6: a
* previously failed approach is not retried. **So the fetch is DEFERRED to the main loop, which is
* at depth 0, where eviction is exactly as legal as it was before this task.**
*
* ★★★★ WHAT THAT COSTS, STATED PLAINLY: a deferred room renders AFTER the logic returns, which is
* the OLD ordering -- the text first and the picture 2.8 s later. **The common case keeps the fix
* and the full-arena case degrades to precisely the behaviour this task started from**, rather
* than to a room that never draws. It is a fallback, not a solution.
* ★★★ THE SOLUTION IS THAT A PICTURE SHOULD NOT LIVE IN THE LOGIC ARENA AT ALL. It is a
* room-lifetime resource sharing a call-scoped stack, which is §2V.2's residency row exactly.
* Reported as a follow-up; it is a memory-map decision and not a line here.
* ★★ COUNTED, NEVER SILENT: p3_nfall is in the summary. A fallback nobody can see is a fallback
* that becomes the behaviour [§2W].
ppd_fail:       lda     res_err
                cmpa    #RES_E_FULL
                bne     ppd_hard
                lda     res_depth
                beq     ppd_hard                ; at depth 0 the eviction already ran and failed
* ★★★★ RECORD THE REFUSAL'S CONTEXT BEFORE DEFERRING. The deferred retry SUCCEEDS at depth 0, so
* p3_drawtop/p3_drawccur end the run describing the recovery rather than the refusal -- and the
* refusal is the finding. **An instrument that only survives the successful call measures the
* wrong call** [L-88].
                lda     p3_picnum
                sta     p3_errpic
                ldx     res_top
                stx     p3_errtop
                ldx     res_ccur
                stx     p3_errccur
                lda     res_depth
                sta     p3_errdepth
                lda     p3_picnum
                inca                            ; ★ +1 so that 0 means "nothing pending"
                sta     p3_pend
                ldd     p3_nfall
                addd    #1
                std     p3_nfall
                jmp     p3_enter_vm_phase
ppd_hard:       lda     res_err
                sta     P3_ERR
* ★★★★★ NAME WHAT FAILED AND WHERE THE ARENA WAS [§2W.3 -- a diagnostic that cannot be wrong does
* not measure]. P3_ERR is STICKY and carries no context, so "err 5" alone cannot say which
* picture, at what depth, with how much arena left. These three bytes are that context, captured
* at the failure and nowhere else.
                lda     p3_picnum
                sta     p3_errpic
                ldx     res_top
                stx     p3_errtop
                ldx     res_ccur
                stx     p3_errccur
                lda     res_depth
                sta     p3_errdepth
* ★ The failure path never entered a draw phase, so the restore is a no-op there -- called
* anyway because a handler that returns in an unknown phase is the defect this routine exists
* to prevent, and one `jmp` is cheaper than reasoning about which paths need it.
                jmp     p3_enter_vm_phase

* ── p3_pic_show -- show.pic's half: REVEAL what draw.pic rendered ────────────────
* ★★★★★ AND RESTORE THE VM PHASE, WHICH IS NEW AND IS LOAD-BEARING. p3_present borrows the
* VISIBLE plane into slot 5 and leaves it there [p3_present, above]. That was harmless while
* this ran from the main loop -- phase_draw_enter followed immediately -- but show.pic returns
* INTO A RUNNING LOGIC, and the loop then continues to p3_stage_sprites, **which reads the
* object table through slot 5**. ★★★★ This is mmu_phase.s:193-205's recorded hazard arriving:
* *"a parse inside an open text window leaves slot 5 wrong."* Same slot, same shape, new caller.
p3_pic_show:
                ifdef   P3B_PICSTEPS
                lda     #21
                sta     P3_PHASE
                endc
                jsr     p3_present
                ifdef   P3B_PICSTEPS
                lda     #22
                sta     P3_PHASE
                endc
                lda     #1
                sta     p3_shown                ; ★ state->pictureShown = true [op_cmd.cpp:1218]
                jmp     p3_enter_vm_phase

* ── p3_pic_pending -- drain a DEFERRED draw.pic, at depth 0 where eviction is legal ──
* ★★★★★ CALLED FROM THE MAIN LOOP, WHICH IS THE ENTIRE POINT: the logic has returned, res_depth
* is 0, and res_open may evict a cached LOGIC and retry exactly as it did before this task.
* ★★★ It renders AND reveals, because a deferred picture has missed its show.pic -- the game
* issued that opcode while the render was refused. **Not re-ordering the game: recovering a
* frame the arena would otherwise have dropped.**
* ★★ p3_pend holds the picture number PLUS ONE so that zero means nothing pending; picture 0 is
* a legal resource number and a bare 0 sentinel would make it unrenderable.
p3_pic_pending:
                lda     p3_pend
                beq     ppp_out
                clr     p3_pend                 ; ★ clear FIRST: a failing retry must not loop
                deca
                jsr     p3_pic_draw
                jsr     p3_pic_show
ppp_out:        rts

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
* ★★★★ WHAT IT COSTS, SO THE NEXT READER NEED NOT RE-MEASURE A 26,880-BYTE OPERATION [T-P0-138]:
* **0.2322 s, 2.6% of a room change** (cycle 9 of a castle run, -DP3B_PICSTEPS). It was named as a
* likely large cost and it is not one -- the render beside it is 91%. ★★★ Both planes, and the
* visual half writes $FFFF over 26,880 B; **whether it is required or defensive was NOT settled
* here** and is §8's question: `pic_render_at` is the only thing that reads what it leaves.
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
* ★★★ The plane_reset was removed at T-P0-135: mmu_phase.s records every slot-5/6 write, so the
* slices this routine mapped behind plane_vis's back are already in ph_cur5/ph_cur6.
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
* ★★★ plane_reset removed at T-P0-135; the record is kept by the register's only writer.
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
p3p_end         fdb     0               ; ★ T-P0-116: this aperture's copy bound, in memory for
                                        ;   the same reason the slice counter is -- `ldd` kills B
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
                ifdef   P3B_TEXT_LINK
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ P3_TXDIAG AND P3_RBTRACE ARE THE SAME ADDRESS, AND NOTHING SAID SO [T-P0-118 §4B].
* Both are MAP_INPUT+576. Each is behind its own diagnostic flag and the two have never been
* enabled together, so the overlap has been harmless and invisible for two tasks.
* ★★★★ **A combined arm makes both reachable in one binary for the first time**, and P6.46 cost
* eight tasks because two symbols shared a region with nothing asserting it. ★★★ Asserted rather
* than silently renumbered: whoever needs both at once should see why they cannot have them,
* and pick a new home deliberately.
* ★★ Shown RED from the command line with `-DTX_MSGDIAG` on a text arm.
                ifdef   TX_MSGDIAG
                error   "P3_TXDIAG and P3_RBTRACE are both MAP_INPUT+576 and -DTX_MSGDIAG has enabled the first while the restore-box trace owns the second. They cannot share the address; give one of them its own home in MAP_INPUT's tail -- note CP_CEL now takes MAP_INPUT+672..+928, so the free space is $1F60-$2000"
                endc
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

* ★★★★ WHAT IT COSTS [T-P0-138]: **0.1967 s, 2.2% of a room change**, once per room, measured on
* cycle 9 of a castle run (-DP3B_PICSTEPS). ★★★ Named as a likely large cost and it is not one.
* ★★ Unavoidable while the shadow is the render target -- which is the design that makes draw.pic
* invisible and show.pic the moment the room appears -- and now it is unavoidable WITH A NUMBER.
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PRESENT THE GAME SCREEN, NOT THE WHOLE ALLOCATION [T-P0-116]. Jay, at the side-by-side:
* *"the text area is white again. we had it changed to black as it should be."*
*
* ★★★★★ THE MECHANISM, AND IT IS AN EXTENT MISMATCH RATHER THAN A REGRESSION. The visual plane
* is 160x168 = 26,880 bytes -- rows 0-167, the GAME SCREEN. The blocks holding it are 2-5 and
* 40-43, four apertures = 32,768, so rows 168-199 (the TEXT AREA, 5,120 B) and 768 spare bytes
* live in the same allocation and are not part of the plane. Init blacks all 32,768 of the
* VISIBLE plane [p3_black_visible], which is what made the text area black and is what Jay
* remembers. **But p3_clear_planes whitens all 32,768 of the SHADOW before each render, and this
* routine copied all 32,768 across** -- so every room change repainted the blacked text area with
* the picture clear's white. ★★★ Not a regression: the black was real, and the first room's
* present has always overwritten it.
*
* ★★★★ THE ORACLE KEEPS THE TWO APART AND SO SHOULD WE: _gameScreen is "160x168 - screen, where
* the actual game content is drawn to" and is a different buffer from _displayScreen
* [graphics.h:116,119 at the pin]. **The shadow is our _gameScreen, and a game screen has no text
* area to present.**
*
* ★★ THE LAST SLICE STOPS SHORT: 26,880 = three full apertures + 2,304. ★★★★ Expressed as a
* count and NOT as `FB_BASE+(PIC_W*PIC_H)` -- that is AD-111's exact expression, $C000+$6900 =
* $12900, which lwasm truncates to $2900 and which cleared two bytes instead of 26,880. The
* addition here is $C000+$900 = $C900 and cannot overflow, but the constant is kept small anyway.
P3_PRESENT_TAIL equ     (PIC_W*PIC_H)-(3*8192)  ; 2,304 bytes into the fourth aperture
                ifgt    P3_PRESENT_TAIL-8192
                error   "the game screen no longer ends inside the fourth aperture -- p3_present's tail bound is wrong"
                endc
* --- how far this aperture goes: full, except the last, which ends at the game screen ---
* ★★★ A IS LOADED BEFORE D, because `ldd` writes A as well and reading p3p_slice after it would
* read the constant's high byte. The same clobber class this file has now recorded four times.
                ifndef  P3B_FAULT_PRESENT_ALL
                lda     p3p_slice
                cmpa    #3
                beq     p3p_tail
                endc
                ldd     #FB_BASE+8192
                bra     p3p_setend
p3p_tail:       ldd     #FB_BASE+P3_PRESENT_TAIL
p3p_setend:     std     p3p_end
* --- one aperture, two bytes at a time ---
                ldx     #FB_BASE                ; $C000, the shadow slice
                ldu     #PRI_BASE               ; $A000, the visible slice (borrowed slot 5)
p3p_cp:         ldd     ,x++
                std     ,u++
                cmpx    p3p_end
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DP3B_FORCE_OVERLAP -- A SCENE P6.88's GUARDS CAN ACTUALLY FIRE ON [T-P0-142 §4E].
* ★★★★★ THE PROBLEM IT SOLVES: T-P0-141 shipped a composite skip with two guards -- no overlap
* with a restored rectangle, and a unique priority band -- and **neither could be shown to fire**.
* Disabling either left both planes byte-identical, because no room this probe reaches has
* overlapping sprites: 0 of 111 unchanged sprites were refused by the isolation test, and room 2
* stages no sprites, room 3 two, room 5 one, against the castle's four.
* ★★★★ SO THE SCENE IS CONSTRUCTED. Sprite 1 is moved onto sprite 0 and given sprite 0's priority,
* AFTER staging and before compositing -- so the game's own object table is untouched (§2P: the
* game's state is not edited, only this frame's staged copy) and update_position keeps working.
* ★★★ THE RESULT IS TWO OVERLAPPING SPRITES AT EQUAL PRIORITY, which is exactly the configuration
* §4A of T-P0-141 identified as the one the narrow rect test cannot cover.
* ★★ Test arm only: no shipped arm assembles a byte of this.
                ifdef   P3B_FORCE_OVERLAP
                lda     p3_nspr
                cmpa    #2
                blo     pfo_out
                ldx     #p3_spr
                lda     ,x                      ; sprite 0's x
                sta     P3_SPR_SIZE,x           ; -> sprite 1's x
                lda     1,x                     ; sprite 0's y
                sta     P3_SPR_SIZE+1,x
                lda     2,x                     ; sprite 0's priority
                sta     P3_SPR_SIZE+2,x
pfo_out:
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
                ifdef   P3B_CEL_LINK
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE COMPOSITE SKIP'S DECISION, TAKEN WHERE p3_prev IS STILL LIVE [T-P0-141].
* p3_composite_all's first act is `clr p3_prevn`, so the previous frame's rectangles are gone by
* the time it walks the sprites -- **the decision cannot be taken there** and is taken during the
* restore, which is also where `prp_same` already runs.
* ★★★★★ THE RULE, AND THE DISPATCH'S STATED ONE IS NOT SUFFICIENT [§4A].
*   skip i  iff  prp_same(i)  AND  rect(i) is disjoint from every OTHER sprite's rect,
*                                  both its OLD (p3_prev) and its NEW (p3_spr) rect.
* ★★★★ "Unchanged AND not overlapped by a RESTORED rectangle" misses the case where a sprite j
* MOVES INTO i's area: j's old rect is restored somewhere else, nothing restores i's area, and j
* then composites over i. **co_depth rejects only when screenPriority > viewPriority, so at EQUAL
* priority the later drawer wins** -- and in a full redraw i, if later in list order, would have
* drawn over j. Skipping i inverts that. ★★★ The wider test covers it and is conservative: if
* nothing writes into i's area this frame, both planes there are untouched and were right last
* frame.
* ★★★ THE THREE DISTURBANCE CASES COLLAPSE INTO ONE TEST because prp_visual and prp_priority walk
* the IDENTICAL rectangle -- so the visual and the priority plane are disturbed over exactly the
* same area, and one overlap test serves both [§1.2(3)].
* ★★ p3_skip[i] = 1 means "do not composite i". Cleared every frame, in the same walk that fills
* it, so a stale 1 cannot survive a frame in which the sprite changed.
                ifdef   P3B_CEL_LINK
p3_skip         rmb     P3_SPR_MAX      ; 1 = unchanged AND isolated -> do not composite
* ★★★ CUMULATIVE, not per-frame, and 16-bit: the question is a RATE over a window, and a per-frame
* byte would report whatever the last frame happened to be -- the shape P6.84 spent a task
* correcting. p3_nunch counts the merely-unchanged so the report can say what the ISOLATION test
* costs in skips foregone [§4D(1)'s "by which reason"].
p3_nskip        fdb     0               ; ★ sprites skipped, cumulative
p3_nunch        fdb     0               ; ★ sprites UNCHANGED, cumulative (>= p3_nskip)
* ★★★ T-P0-143 §4A's two: how many staged sprites were WALKED, and how many carried the same
* (view, loop, cel) as last cycle. The ratio is the cel-decode repeat rate, and it is measured
* before anything is built.
                ifdef   P3B_CELSTATS
p3_ncelseen     fdb     0
p3_ncelsame     fdb     0
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

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
                ifdef   P3B_CEL_LINK
                jsr     p3_skip_decide          ; ★ T-P0-141: fills p3_skip while p3_prev is live
                endc
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

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── p3_skip_decide -- which sprites need no compositing this frame? [T-P0-141] ───
*
* ★★★★★ RUN BEFORE ANY RESTORE, so it sees the previous frame's rectangles intact -- and it must,
* because its second test needs every sprite's OLD rect as well as its new one.
* ★★★★ The rule and why the narrower one is unsound are stated beside p3_skip.
* ★★★ COST: P3_SPR_MAX is 16 but p3_nspr is 4 in the castle, so the O(n^2) rect test is 12 pairs
* of byte compares once per frame -- against a cel decode and blit per sprite skipped.
* ★★ p3_nunch counts the merely-unchanged, so the report can say how much the ISOLATION test costs
* in skips foregone [§4D(1)'s "by which reason"].
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THE SOUND RULE IS NOT COMPUTABLE HERE, WHICH IS THIS TASK'S OBSTACLE [§4A, §6(1)].
* The rule needs every OTHER sprite's NEW rectangle, and **a new rectangle's width and height are
* not known until vc_decode_begin has parsed that sprite's cel header** -- which happens inside
* p3_composite_all, after this point. p3_spr carries x, y, prio, view, loop, cel and no extent.
* ★★★★ So this routine can only test the OLD rectangles, and that is the NARROW test: it covers a
* sprite that moves AWAY (its old rect is restored) and misses one that moves IN.
* ★★★★★ THE MISS IS BOUNDED, AND THE BOUND IS WHY THIS SHIPS AS A MEASUREMENT AND NOT AS A SKIP.
* If j composites into i's area while i is skipped, the result differs from a full redraw ONLY IF
* i would have drawn over j -- and it would not, in two of the three cases:
*     i NEARER than j   -> i's priority bytes are still in the plane (i was not restored, because
*                          unchanged), so co_depth REJECTS j there. Correct without drawing i.
*     i FARTHER than j  -> a full redraw also lets j win. Correct.
*     EQUAL priority    -> co_depth draws (it rejects only screenPriority > viewPriority), so the
*                          LATER DRAWER WINS -- and if i is later in list order, a full redraw
*                          would have put i on top. **This case is wrong.**
* ★★★ So the narrow rule is unsound exactly for: overlapping, equal priority, i later than j.
* ★★ The castle cannot exercise it -- co_rej_pri is ZERO, no pixel is ever priority-rejected --
* which is §1.3's point restated: **the corpus cannot tell a right skip from a wrong one.**
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifdef   P3B_CEL_LINK
psd_i           fcb     0
psd_j           fcb     0
psd_x0          fdb     0               ; sprite i's rect, as 16-bit bounds [x0,x1) [y0,y1)
psd_x1          fdb     0
psd_y0          fdb     0
psd_y1          fdb     0

* ── pcs_count -- Y = &p3_prev[psd_i]; counts one record, and one repeat if the cel is unchanged ──
* ★★ Y is preserved: psd_each's copy is live across the call.
                ifdef   P3B_CELSTATS
pcs_count:
                pshs    y
                ldd     p3_ncelseen
                addd    #1
                std     p3_ncelseen
* ★★★★★ §2W -- THE TWO FAULT ARMS, AND THEY EXIST BECAUSE THE FIRST READING WAS SUSPICIOUS.
* CELSTATS and the SKIP ceiling's `unchanged` returned the SAME NUMBER in both scenes (111 and 3),
* and ★★★★ two instruments asking different questions that agree exactly is the shape §2W distrusts.
*   -DP3B_CELSTATS_NEVER  -- never count a repeat. The rate MUST read 0%.
*   -DP3B_CELSTATS_ALWAYS -- count every record with a staged partner, compares skipped. The rate
*                            MUST rise well above 25%, or the three compares are not what limits it.
* ★★★ Neither arm ships: both are inside P3B_CELSTATS, which is itself a test-only guard.
                ifdef   P3B_CELSTATS_NEVER
                bra     pcs_done
                endc
                lda     psd_i
                cmpa    p3_nspr
                bhs     pcs_done                ; no staged sprite i -> not a repeat
                ifdef   P3B_CELSTATS_ALWAYS
                bra     pcs_hit
                endc
                ldb     psd_i
                lda     #P3_SPR_SIZE
                mul
                ldx     #p3_spr
                leax    d,x
                lda     4,y                     ; prev view
                cmpa    3,x
                bne     pcs_done
                lda     5,y                     ; prev loop
                cmpa    4,x
                bne     pcs_done
                lda     6,y                     ; prev cel
                cmpa    5,x
                bne     pcs_done
pcs_hit:
                ldd     p3_ncelsame
                addd    #1
                std     p3_ncelsame
pcs_done:       puls    y
                rts
                endc

p3_skip_decide:
                ldx     #p3_skip
                ldb     #P3_SPR_MAX
psd_clr:        clr     ,x+
                decb
                bne     psd_clr
                lda     p3_prevn
                beq     psd_out                 ; no previous frame -> nothing is skippable
                clr     psd_i
psd_each:
                lda     psd_i
                sta     p3rp_i                  ; ★ prp_same reads the index from here
                ldb     psd_i
                lda     #P3_PREV_SIZE
                mul
                ldy     #p3_prev
                leay    d,y
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DP3B_CELSTATS -- HOW OFTEN IS A STAGED SPRITE'S CEL THE SAME AS LAST CYCLE'S?
* ★★★★★ A DIFFERENT QUESTION FROM prp_same's, AND THE DIFFERENCE IS THE WHOLE POINT [T-P0-143 §4A].
* prp_same asks "are this sprite's PIXELS already on the plane?", which needs x and y to match.
* **This asks only whether the CEL IDENTITY is unchanged** -- view, loop, cel -- because a sprite
* that walks changes its rectangle every cycle and need not change its cel: VMO_CYCLETIME gates
* the advance. ★★★★ That is precisely the moving case P6.88 measured at ZERO.
* ★★★ p3_prev is x,ytop,w,h,view,loop,cel (+4,+5,+6); p3_spr is x,y,prio,view,loop,cel (+3,+4,+5).
* ★★ Cumulative 16-bit, per P6.84: the question is a RATE over a window, not a last-frame byte.
* ★★★ OUT OF LINE, and that is not a style choice: inlining forty bytes here put psd_each's own
* `beq psd_out` and `blo psd_each` out of 8-bit branch reach [lwasm "Byte overflow", 2026-09-23].
* ★★ A `jsr` costs the loop three bytes when the guard is defined and NOTHING when it is not.
                ifdef   P3B_CELSTATS
                jsr     pcs_count
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                jsr     prp_same
                bne     psd_next                ; changed -> it must be composited
                ldd     p3_nunch
                addd    #1
                std     p3_nunch
                jsr     psd_iso                 ; ★ jsr, not bsr: both targets are out of 8-bit reach
                tsta
                beq     psd_next                ; unchanged but not isolated -> composite it
                jsr     psd_prio_uniq
                tsta
                beq     psd_next                ; shares a priority -> composite it
                ldb     psd_i
                ldx     #p3_skip
                abx
                lda     #1
                sta     ,x
                ldd     p3_nskip
                addd    #1
                std     p3_nskip
psd_next:
                inc     psd_i
                lda     psd_i
                cmpa    p3_prevn
                blo     psd_each
psd_out:        rts

* ── psd_iso -- is p3_prev[psd_i] disjoint from every other p3_prev[j]? A = 1 if so ──
* ★★ 16-bit bounds because x + w reaches 414 for a 255-wide cel at x=159, and a byte compare
* there would wrap into a false "disjoint" [L-40's rule: a byte compared as if it could not carry].
psd_iso:
* ★★★★★ -DP3B_SKIP_NOISO IS AC-6's FAULT ARM: the isolation test always says yes, so a sprite is
* skipped even when a changed neighbour's restore has just written the SHADOW over it. ★★★★ The
* red is a sprite with a bite taken out of it -- **the picture showing through where the neighbour
* was erased** -- which is the artefact §1.2(1) predicts and exactly the kind Jay is asked to look
* for. ★★★ Verified by the plane comparison rather than by eye alone: both planes must DIFFER from
* the non-skipping reference.
                ifdef   P3B_SKIP_NOISO
                lda     #1
                rts
                endc
                ldb     psd_i
                lda     #P3_PREV_SIZE
                mul
                ldx     #p3_prev
                leax    d,x
                clra
                ldb     ,x                      ; x
                std     psd_x0
                addb    2,x                     ; + w
                adca    #0
                std     psd_x1
                clra
                ldb     1,x                     ; ytop
                std     psd_y0
                addb    3,x                     ; + h
                adca    #0
                std     psd_y1
                clr     psd_j
psd_j_each:
                lda     psd_j
                cmpa    psd_i
                beq     psd_j_next              ; not against itself
                ldb     psd_j
                lda     #P3_PREV_SIZE
                mul
                ldx     #p3_prev
                leax    d,x
* disjoint if  xi1 <= xj0  or  xj1 <= xi0  or  yi1 <= yj0  or  yj1 <= yi0
                clra
                ldb     ,x                      ; xj0
                cmpd    psd_x1
                bhs     psd_j_next              ; xj0 >= xi1 -> disjoint in x
                pshs    a,b
                addb    2,x                     ; xj1 = xj0 + w
                adca    #0
                cmpd    psd_x0
                puls    a,b
                bls     psd_j_next              ; xj1 <= xi0 -> disjoint in x
                clra
                ldb     1,x                     ; yj0
                cmpd    psd_y1
                bhs     psd_j_next
                pshs    a,b
                addb    3,x                     ; yj1
                adca    #0
                cmpd    psd_y0
                puls    a,b
                bls     psd_j_next
                clra                            ; ★ overlaps -> NOT isolated
                rts
psd_j_next:
                inc     psd_j
                lda     psd_j
                cmpa    p3_prevn
                blo     psd_j_each
                lda     #1
                rts

* ── psd_prio_uniq -- does sprite psd_i's priority differ from every other staged one? ──
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THIS IS WHAT MAKES THE NARROW RECT TEST SOUND, AND IT IS THE TASK'S REAL FINDING.
* The rect test uses OLD rectangles, so it cannot see a sprite j that MOVES INTO i's area: j's new
* extent is unknown until vc_decode_begin parses its cel header, inside the composite loop.
* ★★★★★ BUT THE MISS ONLY MATTERS AT EQUAL PRIORITY, and priority IS known here [p3_spr +2]:
*     i NEARER than j  (prio_i > prio_j) -> i's priority bytes are still in the plane, because
*                       unchanged means i was NOT restored, so co_depth REJECTS j there.
*     i FARTHER        -> a full redraw also lets j win, whatever the draw order.
*     EQUAL            -> co_depth rejects only screenPriority > viewPriority, so it DRAWS, and
*                       the later drawer wins. If i is later in list order a full redraw puts i
*                       on top and the skip inverts it. **The one wrong case.**
* ★★★★ So requiring i's priority to be unique among the staged sprites removes the dependence on
* an extent this routine cannot know. **Conservative, computable, and sound.**
* ★★★ In the castle the four priorities are 9, 15, 14 and 12 -- all distinct -- so the test costs
* nothing there; in a room where two sprites share a band it refuses the skip rather than guessing.
* ★★ The rect test is still required and is NOT subsumed: a restore writes the SHADOW blindly,
* respecting no priority at all, so an overlapping restore erases i whatever the priorities are.
* ═══════════════════════════════════════════════════════════════════════════════════════════
psd_prio_uniq:
* ★★★★★ -DP3B_SKIP_NOPRIO IS THE ARM THAT CAN ACTUALLY FIRE, AND FINDING THAT OUT IS A RESULT
* [§2W]. The first fault arm disabled the ISOLATION test and came back GREEN with an identical
* skip count -- because **the castle has no overlapping sprites at all**: 0 of 111 unchanged
* sprites are rejected by isolation, and all 12 rejections come from this test. ★★★★ So the
* isolation test is unexercised code in this corpus and its arm cannot go red here; this one can.
                ifdef   P3B_SKIP_NOPRIO
                lda     #1
                rts
                endc
                ldb     psd_i
                cmpb    p3_nspr
                bhs     psd_pu_no               ; no staged sprite i -> do not skip
                lda     #P3_SPR_SIZE
                mul
                ldx     #p3_spr
                leax    d,x
                lda     2,x                     ; prio of i
                clr     psd_j
psd_pu_each:
                ldb     psd_j
                cmpb    psd_i
                beq     psd_pu_next
                pshs    a
                lda     #P3_SPR_SIZE
                mul
                ldx     #p3_spr
                leax    d,x
                puls    a
                cmpa    2,x
                beq     psd_pu_no               ; shares a priority band
psd_pu_next:
                inc     psd_j
                ldb     psd_j
                cmpb    p3_nspr
                blo     psd_pu_each
                lda     #1
                rts
psd_pu_no:      clra
                rts
                endc
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SKIP [T-P0-141]. p3_skip_decide ran during p3_restore_prev, where p3_prev was still
* live, and decided this sprite is unchanged, isolated from every other OLD rectangle, and alone
* in its priority band. **Its pixels and its priority bytes are exactly what a redraw would put
* there, so the decode, the blit and every plane access for it are not work.**
* ★★★★ IT MUST STILL RECORD ITS RECTANGLE. p3_composite_all clears p3_prevn at the top and rebuilds
* p3_prev from what it draws -- so a skipped sprite that recorded nothing would be ABSENT from next
* frame's list, and next frame's restore would not erase it. **It would smear the first time it
* moved.** The record is rebuilt from p3_prev's own previous entry, which is what p3_skip asserts
* is still correct.
* ★★★ -DP3B_NOSKIP is the before arm: the skip is decided and counted, and then ignored.
                ifndef  P3B_NOSKIP
                ldb     p3_si
                ldx     #p3_skip
                abx
                lda     ,x
                beq     pca_draw
                jsr     pca_keep_rect
                puls    y
                lbra    pca_next
pca_draw:
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── the VIEW resource, through the real path ──
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ INVALIDATE THE VOLUME WINDOW'S CACHE BEFORE EVERY FETCH, AND THIS IS THE ALLIGATORS.
* res_core caches which physical block it believes slot 6 holds in res_curblk and SKIPS the MMU
* write when the block matches [res_core.s:1005-1010]. **cp_composite writes the framebuffer
* THROUGH SLOT 6**, so by the time the next sprite is fetched the register holds a framebuffer
* slice while res_curblk still names a volume block.
* ★★★★★ MEASURED: sprites [0] view 0 and [1] view 97 want DIFFERENT blocks from the stale value,
* so they map and succeed. Sprite [2] wants view 107 in vol 1 block 14 -- **the block sprite [1]
* just left cached** -- so the map is skipped, res_open reads framebuffer bytes as a resource
* header, and the signature check fails with RES_E_SIG. Sprite [3] is the same view and fails
* identically. **Exactly two of four, exactly the two Jay cannot see** [T-P0-127].
* ★★★★ THE PROBE ALREADY KNEW THIS SHAPE IN TWO PLACES and neither covered this one: the cycle
* body invalidates at the loop top [p3_enter_vm_phase] and phase_draw_enter invalidates the PLANE
* caches for the same reason -- *"a cache of a register's contents is wrong the moment anyone else
* writes that register"*. **The compositor is an "anyone else" nobody had listed.**
* ★★★ Per FETCH, not once per loop: cp_composite runs between iterations, so one invalidation at
* the top would be stale again by the second sprite.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND BOTH HALVES OF THAT ARE RETIRED AT T-P0-136 -- THE INVALIDATION AND THE FETCH.
*
* ★★★★ THE INVALIDATION WENT WITH plane_reset [T-P0-135]. `res_curblk` is no longer a cache that
* can go stale: it IS mmu_phase.s's ph_cur6, the single record that the only writer of $FFA6
* updates in the same breath. **There is no second owner to tell**, so storing $FF here would
* only force a remap the cursor would otherwise skip. The paragraph above describes a world with
* two caches and that world ended one task ago.
*
* ★★★★★ THE FETCH IS REPLACED BY A LOCATE. res_open COPIED the whole VIEW into the arena -- every
* loop and every cel, up to 2,413 B in the castle -- to decode the ONE cel about to be drawn. In a
* 16,384 B arena holding 15,376 B of LOGICs that leaves 1,008 B, so the copy starved the cache
* every cycle and P6.81's trim gave back 3,817 B that the next cycle re-fetched [T-P0-133 §4].
* ★★★ res_locate maps nothing into the arena: it resolves the DIR entry, checks the signature and
* publishes where the payload IS and how long it is. **The arena allocation for a sprite becomes
* zero**, which is the whole task.
* ★★ THE BEFORE ARM RESTORES THE COPY AND NOT THE INVALIDATION. -DP3B_VIEW_COPY is here to
* measure what the copy cost; the `sta res_curblk` above retired with plane_reset at T-P0-135 and
* putting it back would be measuring two changes at once [L-73].
                lda     #RES_VIEW
                ldb     p3_view
                ifdef   VC_SRC_WINDOWED
                jsr     res_locate
                else
                jsr     res_open
                endc
                lda     res_err
                beq     pca_gotview
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SILENT DROP, RECORDED [T-P0-127]. This branch has always skipped the sprite and left
* NO TRACE -- no counter, no error byte, nothing the host can read. **"2 of 4 staged sprites
* composited" was as far as any instrument could get**, and which two, and why, was unanswerable.
* ★★★★ Jay's "there are no alligators" is this branch firing twice a frame for view 107.
* ★★★ Behind a flag so every shipped arm stays byte-identical; res_err is LIVE and is overwritten
* by the next fetch, so it has to be captured HERE or not at all [§2W.3: a diagnostic that arrives
* after the value has moved reports a different question's answer].
                ifdef   P3B_SPRSTATS
                sta     p3_droperr              ; the res_err that caused it
                ldb     p3_view
                stb     p3_dropview
                inc     p3_ndrop
                endc
                bra     pca_skip
pca_gotview:
* ★★★★★ THE VIEW IS BASELINED HERE AND VERIFIED BEFORE IT IS RELEASED [T-P0-103]. A VIEW is a
* TRANSIENT -- opened, decoded from, composited, closed, all inside this iteration -- so there is
* no later bind to catch a corruption at. **The window that matters is the one between these two
* calls**, because `vc_decode_cel` writes to CP_CEL, which in this configuration starts at $5300
* and runs 4,784 bytes -- 1,456 of them INSIDE the arena this VIEW was just fetched into
* [P6.47 §7.2]. ★★ No decode applies to a VIEW, so the bytes are final the moment res_open returns.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THE CHECKSUM NOW COVERS NOTHING FOR A VIEW, WHICH IS SAID HERE RATHER THAN DISCOVERED
* [T-P0-136 §4C]. res_ck_note baselines the bytes of a resident COPY and res_ck_verify re-reads
* them later. **With no copy there is no resident object to baseline**: the bytes are the game's
* own, in the staged volume, read once through an 8 KB window and never held.
* ★★★★ THIS IS P6.48's BLIND SPOT 1 GETTING WIDER AND IT IS A REAL LOSS. The instrument's whole
* purpose was catching a resource corrupted after it was loaded -- which is exactly what P6.78
* was -- and a VIEW is now outside its reach entirely. ★★★ What still covers the same failure is
* narrower and worth naming: the volume write-tap [P6.82 AC-7] sees anything writing INTO the
* staged data, and the signature check in res_locate sees a window pointing at the wrong block.
* **Neither is a per-byte guarantee.** ★★ LOGICs are unaffected: they are still copied, still
* baselined at the bind, and still verified on every later bind.
* ★ So the hook is not merely unreachable here, it is removed: a checksum call on a resource with
* no resident bytes would baseline whatever the window happened to hold.
                ifdef   VC_SRC_WINDOWED
                ldd     #0
                std     vc_view                 ; ★ payload offset 0, not a CPU address
                else
                ifdef   RES_CHECKSUM
                lda     #RES_VIEW
                ldb     p3_view
                jsr     res_ck_note
                endc
                ldx     res_base
                stx     vc_view
                endc
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
* ★★★ UNDER THE WINDOW vc_srcend IS THE PAYLOAD LENGTH, NOT AN END ADDRESS [view_cel.s says so
* beside the variable]. res_locate publishes res_len for exactly this reason.
                ifdef   VC_SRC_WINDOWED
                ldd     res_len
                else
                ldd     res_base
                addd    res_len
                endc
                std     vc_srcend
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ldx     #CP_CEL
                stx     vc_dest
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE INTRA-CYCLE DEDUP, MEASURED AND NOT TAKEN [T-P0-145]. Room 1's two alligators share
* view 107 and swim in lockstep -- staged consecutively with an identical (view, loop, cel), two
* objects at (147,161) prio 14 and (104,135) prio 12. **1.00 of 4.00 staged records per cycle.**
*
* ★★★★★ THE SHARING RULE, and the dispatch's stated trap CANNOT OCCUR HERE.
*   **Two staged sprites share a decoded row iff their (view, loop, cel) triples are equal.
*   Nothing else is required, mirroring included.**
* ★★★★ MIRRORING IS A PROPERTY OF THE TRIPLE, NOT OF THE SPRITE. vc_mir is computed inside
* vc_decode_begin from the cel header's mirror bit AND the recorded loop compared against vc_loop
* [view_cel.s:10-14, 223-235] -- both functions of the triple. ★★★ `vc_mir` appears NOWHERE in
* this file or in composite.s: there is no per-sprite mirror state to disagree about. **Facing is
* a different LOOP, which is already part of the triple.** So equal triples always decode to
* identical bytes, and "same triple, opposite mirror" is not a reachable state.
*
* ★★★★★ WHY IT WAS NOT BUILT, AND THE PREMISE THAT FAILED. The dispatch's shape was "decode the
* row once, blit it to both destinations -- the second blit can read CP_CEL before it is
* overwritten." ★★★★★ **CP_CEL IS OVERWRITTEN vc_h-1 TIMES DURING ONE SPRITE.** cp_composite's
* co_row loop calls vc_decode_row per row under COMP_ROW_PULL [composite.s:170-192], so when it
* returns, CP_CEL holds the LAST row only. ★★★★ The dedup is therefore not a second blit after a
* decode; it is **two blits interleaved inside one row loop**, each with its own co_basex,
* co_prio, co_cury and row bases -- a restructure of cp_composite, which is 28.9% of the drawing
* stage and the hottest loop in the program.
*
* ★★★★★ AND THE SAVING IS ROOM 1's ALONE, on every room reachable [§6 trigger 5]:
*     room 1: 4.00 staged/cycle, **1.00 adjacent duplicate**, 15 distinct triples
*     room 2: 0.00 staged        room 3: 2.00 staged, 0 duplicates (views 0 and 10 differ)
*     room 5: 1.00 staged, 0 duplicates
* ★★★ Two sprites sharing a view is a property of THIS ROOM, not of AGI [§4C(4)].
*
* ★★★★ ADJACENCY IS INCIDENTAL, TOO. p3_stage_sprites appends in OBJECT-NUMBER order with no sort
* [pss_lp]; nothing contracts that a shared view lands consecutively. A non-adjacent pair could
* only be deduped by hoisting one sprite's blit next to the other's -- **which changes draw order,
* and at equal priority co_depth lets the LATER drawer win** [§6 trigger 1: a ruling, not a task].
*
* ★★★ This is the 1-slot case of the cel cache P6.90 priced at 95.4%/3,906 B and could not place.
* **It is the part that needs no storage -- and it still needs the hottest loop rebuilt for ~4.4%
* of a cycle in one room.** Recorded so the next reader does not re-derive the premise.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ BEGIN, NOT DECODE [T-P0-105]. The cel is no longer unpacked here; cp_composite pulls it a
* row at a time into CP_CEL, which is now VC_ROW_MAX bytes rather than 4,784. **The overlap with
* RES_ARENA is gone rather than relocated**, and the VIEW this decodes FROM is no longer inside
* the buffer it decodes INTO.
                jsr     vc_decode_begin
                lda     vc_err
                bne     pca_close
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THE PLANE LAYER'S CACHE OF THE SAME REGISTER, WHICH P6.74 DID NOT INVALIDATE [T-P0-131].
* res_open(VIEW) above maps a VOLUME block into slot 6. plane_win.s records which FRAMEBUFFER slice
* it believes slot 6 holds (pl_vis_cur) and SKIPS the remap when the slice matches -- so from the
* second sprite on, co_put_visual was handed an address in the VOLUME WINDOW and wrote sprite
* pixels into the staged game data.
* ★★★★★ MEASURED, END TO END: a write tap on $A000-$DFFF filtered to block $0E (KQ1 vol.1's first
* block) caught co_put_visual storing $BB/$33 -- doubled pixels -- there from the first castle
* cycle. LOGIC 1 is re-fetched from that volume every cycle, so its bytecode acquired the pixels;
* at cycle 18 the corrupted `if` at $0269 fell into the block that sets flag 63 -- the alligator
* death sequence: program.control + stop.motion (Jay: "graham doesn't respond"), follow.ego on both
* alligators ("not contained to the moat"), print(1) (the `"` box). **The text arm, which has no
* compositor, matched the reference exactly; the combined arm did not, with no key at all.**
* ★★★★ P6.74's own words, the rule this completes: *"a cache of a register's contents is wrong the
* moment anyone else writes that register."* Two caches of $FFA6 exist -- res_curblk and
* pl_vis_cur -- and each owner has to be told when the other moves it.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND THE INVALIDATION IS GONE AT T-P0-135, BECAUSE THE SENTENCE ABOVE IS NOW FALSE.
* "Two caches of $FFA6 exist -- res_curblk and pl_vis_cur -- and each owner has to be told when
* the other moves it." **There is one record now**, mmu_phase.s's ph_cur6, written by the only
* instruction in the tree that writes the register. plane_vis tests it directly, so a VIEW fetch
* between two composite writes is seen rather than announced.
* ★★★★ -DP3B_FAULT_NOPLANERESET IS RETIRED AND REPLACED BY -DPLANE_FAULT_PRIVCACHE, which gives
* plane_vis its private cache back. **That is P6.78's defect itself rather than the absence of
* its workaround** -- and it is the same red Jay described: Graham marching in place, the
* alligators chasing, a stray message box [§2W; plane_win.s carries the arm].
* ═══════════════════════════════════════════════════════════════════════════════════════════
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE CLAMP TESTED THE SIGN AND HAD TO TEST THE BORROW [T-P0-127]. `bpl` reads bit 7, so
* **every ytop >= 128 was taken for a negative number and clamped to 0**:
*     y=161, h=4  ->  161-4+1 = 158 = $9E, bit 7 set  ->  ytop recorded as 0
*     y= 51, h=4  ->   51-4+1 =  48 = $30, bit 7 clear ->  ytop recorded as 48   (correct)
* ★★★★★ AND THE RESTORE RECTANGLE IS WHAT THIS FEEDS, so an object low on the screen had last
* frame's pixels put back at rows 0-3 instead of 158-161 -- **its own trail was never erased.**
* Jay, watching the alligators once they finally drew: *"they stretch as they move."*
* ★★★★ THE UNDERFLOW THE CLAMP EXISTS FOR IS REAL -- a cel taller than its own y -- but the sign
* bit cannot distinguish it from a legitimately large row. **The borrow out of the subtraction
* can**: it is set exactly when vc_h > CP_Y, which is the only case that wraps.
* ★★★ L-40's rule, third instance in this tree: a byte compared as signed that was never signed.
                lda     CP_Y
                suba    vc_h
                bcs     pca_ytopzero            ; borrow: vc_h > CP_Y -- a real underflow
                inca
                bra     pca_ytopok
pca_ytopzero:   clra
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
* ★★★★ NOTHING TO CLOSE UNDER THE WINDOW [T-P0-136]. res_locate pushes no frame and allocates no
* arena, so there is no depth level to pop and no res_top to rewind -- and calling res_close here
* would pop a level this iteration never pushed, which res_close treats as a no-op at depth 0 and
* as a REAL pop at any depth above it. ★★★ The release-side checksum goes with it, for the reason
* stated at pca_gotview: there are no resident bytes to verify.
                ifdef   VC_SRC_WINDOWED
                bra     pca_skip
                endc
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
pca_next:
                inc     p3_si
                lda     p3_si
                cmpa    p3_nspr
                lblo    pca_lp          ; ★ long, for the same reason as the lbeq above
pca_out:        rts

* ── pca_keep_rect -- carry a SKIPPED sprite's rectangle into next frame's list ────
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WITHOUT THIS A SKIPPED SPRITE SMEARS THE FIRST TIME IT MOVES. p3_composite_all clears
* p3_prevn and rebuilds p3_prev from what it DRAWS, so a sprite that draws nothing would be absent
* from next frame's list -- and next frame's p3_restore_prev would not erase it. **The old pixels
* would stay on the plane forever**, which is the exact failure prp_same's comment warns about for
* the geometry-only test, arriving by another route.
* ★★★★ THE RECORD TO CARRY IS THE ONE ALREADY THERE: p3_skip asserts this sprite is unchanged, so
* p3_prev[p3_si] still describes it exactly. ★★★ It is COPIED rather than left in place because
* the destination is slot p3_prevn, and an earlier sprite that failed to composite (pca_skip's
* res_err path) leaves p3_prevn BEHIND p3_si -- so the two indices are equal in the common case
* and must not be assumed equal.
* ★★ Bounded by P3_SPR_MAX exactly as the recorder below is.
                ifndef  P3B_NOSKIP
pca_keep_rect:
                lda     p3_prevn
                cmpa    #P3_SPR_MAX
                bhs     pkr_out
                ldb     p3_si
                lda     #P3_PREV_SIZE
                mul
                ldx     #p3_prev
                leax    d,x                     ; X -> the OLD record for this sprite
                ldb     p3_prevn
                lda     #P3_PREV_SIZE
                mul
                ldy     #p3_prev
                leay    d,y                     ; Y -> where this frame's list wants it
* ★ No X==Y special case: a forward byte copy of a record onto itself is a no-op, and testing for
* it would cost more than the seven `ldb`/`stb` pairs it avoids.
                lda     #P3_PREV_SIZE
pkr_copy:
                ldb     ,x+
                stb     ,y+
                deca
                bne     pkr_copy
                inc     p3_prevn
pkr_out:        rts
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                else
* ★★ The stripped configuration still needs the symbol: the cycle body calls it unconditionally,
* and a guarded CALL as well as a guarded BODY would put the strip in two places [§2F].
p3_composite_all:
                rts
                endc

p3_lastroom     fcb     $FF             ; ★ $FF: no room yet, so the first cycle always renders
p3_picptr       fdb     0
p3_drew         fcb     0
p3_picnum       fcb     0               ; ★ the picture draw.pic was last given
* ★★★ pictureShown, and it is the oracle's byte rather than ours: draw.pic clears it and
* show.pic sets it [op_cmd.cpp:1210,1218]. Nothing in this probe READS it yet -- it is carried
* because the two opcodes that write it are being implemented now and a half-implemented
* opcode is the thing §2W's "declared, not stubbed" rule exists to avoid. The host prints it.
p3_shown        fcb     0
p3_errpic       fcb     $FF             ; ★ $FF = no fetch has failed
p3_errtop       fdb     0               ; res_top when it did
p3_errdepth     fcb     0               ; res_depth when it did -- the whole point
p3_errccur      fdb     0               ; the cache floor when it did -- the number that explains it
p3_drawtop      fdb     0               ; res_top as the LAST draw.pic found it
p3_drawdepth    fcb     0               ; res_depth as the LAST draw.pic found it
p3_drawccur     fdb     0               ; res_ccur (the cache floor) as draw.pic found it
p3_pend         fcb     0               ; ★ deferred picture number PLUS ONE; 0 = none pending
p3_nfall        fdb     0               ; how many draw.pic fetches had to be deferred
p3_nspr         fcb     0
p3_si           fcb     0
p3_view         fcb     0
* ★★★ T-P0-127's drop record. Flag-guarded: the shipped arms carry none of it.
                ifdef   P3B_SPRSTATS
p3_droperr      fcb     0               ; res_err from the last sprite dropped before the blit
p3_dropview     fcb     0               ; which view it wanted
p3_ndrop        fcb     0               ; how many sprites have been dropped
                endc
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
* ★★★★ THE INVALIDATION IS GONE [T-P0-135]. The paragraph above is the design's own statement of
* the defect -- "a cache of a register's contents is wrong the moment anyone else writes that
* register, and the phase pair is exactly that moment" -- and phase_draw now records both slots
* as it writes them, so the phase pair no longer needs announcing.
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
* ★★★★★ UNCONDITIONAL SINCE T-P0-118, AND IT WAS THE ONE FREE MOVE P6.63 FOUND. This relocation
* ran only under `ifdef P3B_NO_CEL`; the cel arm took the `else` and kept 626 bytes of dispatch
* tables inside region A, where space was the binding constraint. ★★★★ **Six arms had been doing
* this for tasks and the arm that needed the room was the one not doing it.**
* ★★★ The host needs no change: p3b_run.lua keys on the PRESENCE of P3_CODE_SPLIT /
* P3_TABLES_BASE / P3_TABLES_END and produces four runs when they exist, two when they do not
* [p3b_run.lua:702-709]. It now always sees them.
* ★★ The slack is nearly full -- P3_TABLES_END against P3_TABLES_LIMIT is 14 bytes at the last
* measurement -- so this move is available ONCE and is not a source of further headroom.
P3_CODE_SPLIT   equ     *
                org     P3_TABLES_BASE
                include "src/harness/vm_tables.s"
P3_TABLES_END   equ     *
                ifgt    P3_TABLES_END-P3_TABLES_LIMIT
                error   "vm_tables.s overruns the seed stack's slack and is heading for the hardware stack -- shrink it or raise P3_TABLES_LIMIT after re-measuring the stacks"
                endc
                org     P3_CODE_SPLIT
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
                ifdef   P3B_CEL_LINK
                include "src/harness/view_cel.s"
                include "src/harness/composite.s"
                endc

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"
* ★★★★★ input.s ARRIVES WITH THE KEYBOARD AND NOT BEFORE [T-P0-092]. hal_globals.s defines
* HAL_key_scan under -DHAL_KEYBOARD; HAL_input_init lives in input.s, and this include is what
* makes it reachable.
* ★★★★ THE SENTENCE THAT WAS HERE IS CORRECTED, NOT DELETED [T-P0-115]. It read "**this probe
* never included it**, so the PIA precondition HAL_key_scan documents has never been asserted
* here" -- true when it was written and **false since T-P0-092**, which added the
* `jsr HAL_input_init` at the init site above. The stale claim survived three tasks and was
* quoted forward into T-P0-115's dispatch as an open precondition to satisfy; it was already
* satisfied. ★★★ Same shape as the stale binary figure in gates.manifest [P6.60 §3.6]: a fact
* recorded in prose beside code that later changed, with nothing to make the prose fail.
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
                ifdef   P3B_TEXT_LINK
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ IN THE COMBINED ARM THE TEXT ENGINE LIVES IN SLOT 7 [T-P0-120, Jay's ruling on P6.65].
* Region A cannot hold both halves -- P6.64 measured the combined build 513 B past
* MAP_RESERVED_END -- and slot 7 is the only other place code can live: memmap.inc's phase table
* marks it "resident tables ... unchanged" in BOTH phases, so it is never remapped. ★★★ The
* parser is already `org`ed there and runs 954 bytes, so this is not a new technique; the text
* engine simply joins the other text machinery.
*
* ★★★★★ THE SPACE IS FREE IN THIS ARM AND IS NOT FREE GENERALLY, AND P6.65 -- MINE -- SAID
* OTHERWISE. That report scanned three arms' symbol tables for anything declared inside
* $EBBA-$FC00, found nothing, and called the hole unclaimed. **A region owned by ONE symbol with
* a large extent shows zero symbols inside it**: the cel arm's flat vocabulary is P3_VOCAB at
* $E3BA running to $FF00, and p3b_flat's is $EBBA-$FC00 exactly -- the same 4,166 bytes, named
* as such at the P3_VOCAB block below. ★★★★ **The combined arm is safe because its vocabulary is
* WINDOWED at $A000**, which the assertion below requires rather than assumes.
*
* ★★ THE BASE IS A LITERAL WITH AN ASSERTION, not an expression, for the reason the P3_VOCAB
* block states: P3_CLNBUF is declared 160 lines BELOW this, so `P3_CLNBUF+42+P3_FONT_BYTES` here
* is a forward reference and any `ifgt` on it fails pass 1 with "Conditions must be constant",
* which reads as a broken assertion rather than a declaration-order problem.
                ifdef   P3B_COMBINED
P3_TEXTB_BASE   equ     $EBBA           ; immediately after the font; asserted below
P3_TEXT_SPLIT   equ     *
                org     P3_TEXTB_BASE
                include "src/engine/text.s"
P3_TEXTB_END    equ     *
                org     P3_TEXT_SPLIT
* ★★★★ THE CEILING IS MAP_COVERAGE, the same ceiling the flat vocabulary is bounded by.
                ifgt    P3_TEXTB_END-MAP_COVERAGE
                error   "the text engine overruns slot 7's hole -- it runs from P3_TEXTB_BASE past MAP_COVERAGE ($FC00), where the coverage counters live. Shrink it, or take a ruling on region B's layout"
                endc
                else
                include "src/engine/text.s"
                endc
* ★★ TEXT_WIRED says the engine is LINKED AND CALLED. -DTEXT_MODELLED links it and declines to
* call it, which is AC-2's fault arm; the cel configuration does not link it at all.
                ifndef  TEXT_MODELLED
TEXT_WIRED      equ     1
                endc
                endc
* ★★★ UNCONDITIONAL, because the generated table names the nine labels in every build [AD-176].
* Under anything but TEXT_WIRED this emits nothing but nine `equ`s to vm_op_modelled.
                include "src/harness/vm_text_ops.s"
* ★★★ UNCONDITIONAL FOR THE SAME REASON AND WITH THE SAME SHAPE [AD-176]: gen_vm_tables.py
* names vmop_draw_pic / vmop_show_pic / vmop_configure_screen in EVERY build once the labels
* exist, so every client must define them. Without PIC_WIRED this emits three `equ`s to
* vm_op_modelled and no bytes.
                include "src/harness/vm_pic_ops.s"
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ RETIRED AT T-P0-118, AND THE OLD TEXT IS KEPT BECAUSE THE REASON IT EXISTED IS THE
* REASON IT CAN GO. Both assertions below this comment used to read:
*
*     ifndef P3B_NO_CEL / ifgt P3_CODE_END-CP_CEL
*       error "P3b code has grown into the decoded-cel buffer at CP_CEL ($5300, 4,784 B) ..."
*     else / ifdef CP_CEL
*       error "CP_CEL is defined in a -DP3B_NO_CEL build ... they cannot share $5300."
*
* ★★★★★ THAT `else` BRANCH WAS THE MUTUAL EXCLUSION -- it is what made text and cels unable to
* share a binary, and it was correct for as long as CP_CEL lived in MAP_RESERVED. **CP_CEL is now
* MAP_INPUT+672**, so the two no longer contend for $5300 and the exclusion has no subject.
* ★★★ Its error text had also gone stale: it still said "$5300, 4,784 B" after T-P0-105 made
* CP_CEL 256 bytes at $5F00. **Fourth stale comment found in four tasks** [P6.61 §3.5, P6.62 §3.6,
* P6.63 §3.5]. Kept here verbatim rather than deleted, so the next reader can see what the rule
* was and why it stopped applying.
*
* ★★★★ WHAT REPLACES IT: the code's real ceiling, which is now MAP_RESERVED_END itself, because
* nothing else occupies region A above the code. Unconditional -- it is the same bound in every
* configuration now, which is the point of the move.
* ★★ UNDER THE SAME ESCAPE AS THE SPAN ASSERTION ABOVE, and for the reason its comment gives: a
* guard that errors prevents the .map from being written, so the size -- the first thing anyone
* needs when it fires -- becomes unreadable. `-DP3B_ACCEPT_OVERRUN` lets the build complete so the
* overrun can be MEASURED. It still fails by default.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ IT HAS NOW FIRED, AND ON A DIAGNOSTIC ARM RATHER THAN A SHIPPED ONE [T-P0-136, recorded
* here at T-P0-137 §1.2(2)]. The in-place VIEW read added 205 B and **`-IfRec` no longer
* assembles**: `-DVM_IFDIAG -DVM_SAIDDIAG` on top of the combined arm runs past $6000.
* ★★★★ EVERY SHIPPED ARM STILL BUILDS -- p3b_comb is 19,105 B against a $6000 ceiling -- so what
* is lost is the instrument, not the program. **`logic_copy_diff.py` reads a snapshot only that
* arm produces**, which is why T-P0-136's AC-5 had to be answered by a volume write-tap instead.
* ★★★ RECORDED, NOT FIXED. The remedy this assertion names is a ruling on the map (D-30's map
* document arriving as a symptom), and that is the Orchestrator's, not a task's to take in passing.
* ★★ The next task that adds code to p3b meets this, not just the diagnostic arms.
*
* ★★★★★ THE MAP RULING'S FIFTH SYMPTOM, AND THE FIRST ONE THAT COSTS SPEED RATHER THAN AN
* INSTRUMENT [T-P0-143 §4B]. The four before it were diagnostic arms. **This one is a measured
* 95.4% reduction in cel-decode work that cannot be placed**: the castle's 20-cel working set is
* 3,906 bytes, region A is full, and MAP_INPUT's tail belongs to P3_KQ -- roughly 74 bytes free
* against 3,906 needed. ★★★★ vc_decode_row is 26.6% of the drawing stage and the drawing stage is
* 59% of a cycle, so the unplaceable win is ~15% of the cycle, at 3.3 cycles/second.
* ★★★ Still recorded, still not fixed, and still the Orchestrator's ruling [§6, trigger 2] -- but
* the ledger now has a number in it rather than a list of blocked diagnostics.
*
* ★★★★★ AND THE RULING NOW HAS AN ANSWER THAT DOES NOT NEED REGION A AT ALL [T-P0-146 §4A].
* **The constraint was never RAM** -- 512 KB leaves ~46 of 56 blocks free -- **and it turns out not
* to be the aperture either.** A host-side census tapped every MMU window and bucketed reads and
* writes by P3_PHASE [`p3b_show.ps1 -SlotCensus`], over 40 castle cycles:
*     slot 3 $6000-7FFF ARENA low   0 r  0 w in the composite; busy in phases 0, 3, 7
*     slot 4 $8000-9FFF ARENA high  0 r  0 w in the composite; busy in phases 0 and 3 ONLY
*     slot 5 priority 17,204 r / 36,651 w · slot 6 fb+volume 36,239 r / 8,539 w -- both LIVE
*     slot 7 tables/text 759 r -- LIVE, and it is not free anyway: the text engine, the font,
*            the parser buffers and the flat vocabulary are in "slot 7's hole" [see :4020]
* ★★★★★ **SLOT 4'S APERTURE IS SILENT FROM THE END OF `interpret` UNTIL THE NEXT CYCLE'S** --
* through sprites, roomcheck, every room-render sub-step and the whole composite. ★★★ The same
* taps read 83,357 accesses there in other phases, so the zero is a measurement and not a dead
* instrument [§2W].
*
* ★★★★★ SO A CEL CACHE CAN BE PLACED: map its block into slot 4 at draw-phase entry, restore the
* arena's high block at exit. ★★★★ **Two MMU writes per cycle (~14 cycles) against ~16% of a
* cycle saved.** ★★★ The arena's bytes are never touched -- a remap hides them, it does not
* destroy them -- and $FFA6's single-owner discipline [P6.82] is what makes this askable at all.
*
* ★★★★ AND THE SHAPE IS PER-LOOP, NOT N-SLOT [T-P0-146 §4B]. Whole loops, LRU over loops:
*     1 loop 25.1% / 2,100 B · 2 loops 25.6% / 3,252 B · **3 loops 99.3% / 4,006 B**
* against the 20-slot LRU's 95.4% at 3,906 B -- **a better hit rate, for 100 more bytes, with a
* THREE-entry policy.** ★★★ Still a cliff, because room 1's loops sweep concurrently and all three
* must be resident; **4,006 B fits slot 4's 8,192 with room for double.**
* ★★ NOT BUILT. §4A was the question; the ruling is Jay's [§6 trigger 1].
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifndef  P3B_ACCEPT_OVERRUN
                ifgt    P3_CODE_END-MAP_RESERVED_END
                error   "P3b code has grown past MAP_RESERVED_END ($6000) into MAP_ARENA_WIN -- region A is full. CP_CEL already left for MAP_INPUT and vm_tables is already relocated, so the next move is a real one: shrink the code, or take a ruling on the map"
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
                ifdef   P3B_TEXT_LINK
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE TWO CROSS-CHECKS THE SLOT-7 RELOCATION NEEDS, AND THEY CAN ONLY BE MADE HERE --
* P3_CLNBUF and P3_VOCAB are declared in this block and the relocation is 240 lines above it
* [T-P0-120]. The `org` there uses a LITERAL base for the forward-reference reason the P3_VOCAB
* comment gives; these are what make the literal safe.
                ifdef   P3B_COMBINED
* ★★★★ 1. THE BASE REALLY IS IMMEDIATELY AFTER THE FONT. If the parser, its buffers or the font
* ever change size, $EBBA stops being that address and the text engine would either overlap the
* font or leave a gap -- silently, because an `org` never complains.
                ifne    P3_TEXTB_BASE-(P3_CLNBUF+42+P3_FONT_BYTES)
                error   "P3_TEXTB_BASE is no longer immediately after the font -- the parser, its buffers or P3_FONT_BYTES have changed size, so the literal in the relocation block is stale. Re-read P3_CLNBUF+42+P3_FONT_BYTES and update it"
                endc
* ★★★★★ 2. THE VOCABULARY MUST BE WINDOWED, and this is the assertion P6.65 needed and did not
* have. That report scanned for symbols DECLARED inside $EBBA-$FC00, found none in three arms,
* and concluded the space was free. **It is the flat vocabulary's window**: the cel arm puts
* P3_VOCAB at $E3BA running to $FF00 and p3b_flat puts it at $EBBA-$FC00 -- the same 4,166 bytes
* the block above names. A region owned by ONE symbol with a large extent shows nothing inside it.
* ★★★ The combined arm is safe only because its vocabulary is in slot 5 at $A000. Asserted, so a
* future -DTEXT_VOCAB_FLAT on a combined build fails loudly instead of overwriting the engine.
* ★★★★★ AN OVERLAP TEST, AND THE FIRST VERSION WAS NOT ONE. It read
* `ifgt MAP_ARENA_WIN_E-P3_VOCAB` -- "the vocabulary is below $A000" -- which is FALSE for the
* flat window, because the flat vocabulary is at $EBBA, ABOVE $A000, not below it. ★★★★★ **The
* assertion passed a build where P3_VOCAB and P3_TEXTB_BASE were the SAME ADDRESS**, and it was
* found only because §2W says show it red and it refused to go red. Two ranges overlap iff each
* starts before the other ends, and that needs both halves.
                ifgt    P3_VOCAB_END-P3_TEXTB_BASE
                ifgt    P3_TEXTB_END-P3_VOCAB
                error   "a COMBINED build's vocabulary window OVERLAPS the relocated text engine -- the flat dictionary occupies slot 7's hole ($EBBA upward), which is exactly where the engine was moved. The combined arm requires the WINDOWED vocabulary at $A000"
                endc
                endc
                endc
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
                ifdef   P3B_TEXT_LINK
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
                ifdef   P3B_CEL_LINK
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
                ifdef   P3B_CEL_LINK
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
