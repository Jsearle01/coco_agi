* src/harness/vm_probe.s -- the harness that drives the VM under MAME, one cycle per handshake.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ SAME GO GATE AS res_probe.s AND pic_probe.s. The host stages the game's DIR tables and
* volume slice (P1.3's staging, unchanged), releases the guest for one cycle, and reads 256
* variables and 32 flag bytes back. AC-2 compares those 288 bytes per cycle.
*
* ★★★ THE SAMPLE IS TAKEN WHILE THE GUEST IS PARKED AT vm_pace's EXIT -- after the clock ticks
* that led to this cycle, before the cycle body. That is where the oracle's patch dumps, and
* "cycle N" has to mean the same thing on both sides or the whole diff shifts by one line.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/hal.inc"

* ★★★ THE RESOURCE LAYER MOVES UP FOR THIS CLIENT. res_core.s defaults to RES_DIRS $2000 and
* the arena at $3000-$5FFF, which is P1.3's gated map and is right for res_probe.s. The VM adds
* ~6 KB of handlers on top of the resource layer and the HAL, and does not fit below $2000 --
* the layout assertion at the bottom of this file is what said so, on the first assembly, which
* is exactly the job P3.13's misplaced guard failed to do.
RES_DIRS        equ     $3000           ; four DIR tables
* ★★★ 23 KB, NOT 12, AND THE 12 CAME FROM A MEASUREMENT TAKEN ON A RUN THAT NEVER NESTED.
* KQ1 cycle 0 holds logic 0's 8,999-byte RESOURCE open across a call to logic 102's 3,817 =
* 12,816 bytes, and res_open returned RES_E_FULL 528 bytes short. The old figure was measured
* while the arg-count clobber made logic 0 "return" three instructions before its own `call`.
* ★★ The arena is the one large allocation that does NOT need to be host-readable -- it holds
* resource bytes and the state diff never reads them -- so it is the right thing to put above
* $8000 and the VM's state block moved down to $4000 to make room. It stops at $C000 because
* res_core maps VOL blocks through that window. See vm_state.s for the whole map.
RES_ARENA       equ     $6B00           ; the residency arena -- 21 KB
RES_ARENA_END   equ     $C000

VP_GO           equ     $0080           ; host writes 1 to release one cycle; probe clears it
VP_STATUS       equ     $0081           ; 0 = ok, else the halt reason
VP_BADOP        equ     $0082           ; the opcode that halted us
VP_BADLOGIC     equ     $0083
VP_CYCLE        equ     $0084           ; 2 bytes: cycles interpreted so far
* ★ Diagnostics. A halt that names only "logic 0 never returned" cannot distinguish a wrong
* code length from a desynchronised opcode stream, and those need opposite fixes.
VP_CODELEN      equ     $0086           ; 2 bytes: the bound logic's bytecode length
VP_IP           equ     $0088           ; 2 bytes: where interpretation stopped
VP_LASTOP       equ     $008A           ; the last opcode dispatched
VP_OPCOUNT      equ     $008B           ; 2 bytes: commands dispatched, cumulative
VP_ICGUARD      equ     $008D           ; logic.0 invocations in the last cycle
VP_ARENA_BAD    equ     $008E           ; ★ 2 bytes: first arena address that failed readback, 0 = clean
VP_FREE         equ     $0090           ; ★ 2 bytes: AC-7 free-run counter, 0 = normal handshake
VP_CAL          equ     $0092           ; ★ 2 bytes: clock-calibration blocks, 0 = none
* ★★★★ THE CALIBRATION BRACKET, STAMPED BY THE GUEST. The host cannot close this interval
* itself: on release from the free-run park the guest runs one interpret cycle (~120,000 CPU
* cycles on KQ1) before it reaches the calibration blocks, and charging that to the calibration
* reported 1.5379 MHz for a 1.789772 MHz machine. ★★★ A marker written either side of the
* blocks and read through a write tap gives one-instruction resolution -- P3b.12's pattern.
VP_MARK         equ     $0094           ; 1 = calibration opens, 2 = calibration closes
* ── T-P0-060: the scripted input path ────────────────────────────────────────────
* ★★ The host writes the text into VP_INBUF and sets VP_FEED while the guest is parked; the
* guest feeds it after vm_pace and BEFORE it publishes and parks again. See vp_feed.
VP_FEED         equ     $0096           ; host: 1 = parse VP_INBUF before the next park
VP_VOCAB_BAD    equ     $0097           ; 2 bytes: first vocab-window address that failed, 0 = ok
* ★★ THE said() COVERAGE COUNTERS ARE BUILD SYMBOLS (vm_saidn / vm_saidm / vm_fedn in
* vm_tests.s), NOT handshake addresses. The host reads them through build/vm_stage/symbols.txt
* like every other interior value here -- "symbols come from the BUILD, never from a copy beside
* the fixture" [vm_sweep.lua:102, P1.3]. A fifth hard-coded address in this block would be the
* thing P6.3 §3.F.2 cost hours to.
VP_HW_STACK     equ     $0700

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE INPUT BUFFERS ARE 42 BYTES, MEASURED AT THE PIN, NOT ESTIMATED [T-P0-060 AC-7].
* T-P0-059 §7.3 supplied 256 B each and flagged the figure as an unmeasured guess. The oracle:
*     text.h:170    byte _prompt[42];                     <- the buffer parseUsingDictionary gets
*     text.cpp:778  _vm->_words->parseUsingDictionary((char *)&_prompt);
*     text.h:74     #define TEXT_STRING_MAX_SIZE  40      <- the prompt's own clamp
*     text.cpp:745  maxChars = TEXT_STRING_MAX_SIZE - strlen(string 0)   [-1 if the cursor moved]
*     cycle.cpp:663 setVar(VM_VAR_MAX_INPUT_CHARACTERS, 38)
* ★★★ 42 is the ARRAY and 40 is the CLAMP; a game may raise var 24 but text.cpp:751 takes the
* MINIMUM, so nothing above 40 characters can reach the parser. 42 holds 40 + NUL with a byte
* spare, which is the oracle's own margin and is kept rather than re-derived.
* ★★ THE CLEANED BUFFER IS THE SAME SIZE BECAUSE par_clean CANNOT GROW ITS INPUT: it copies or
* drops characters and collapses each separator run to exactly one space, so |out| <= |in|.
* ★ They sit in the 224-byte gap between VM_OBJ_END ($6220) and VM_TESTSEEN ($6300); the
* assertions at the foot of this file are what keep that true as the map moves.
VP_INBUF        equ     $6220           ; 42 B, host-written, NUL-terminated
VP_CLNBUF       equ     $6250           ; 42 B, par_clean's output
VP_BUF_END      equ     VP_CLNBUF+42

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE VOCABULARY WINDOW. WORDS.TOK is a RESOURCE and lives in a window, not in the code
* image (§2V.2's residency row). The largest in the twelve-title corpus is SpaceQuest-2 at
* **6,828 bytes** [T-P0-059 §3.E, re-measured], so ONE window holds any of them.
* ★★★ $E000-$FEFF is 7,936 bytes and is the only contiguous free window in THIS PROBE's map --
* $C000-$DFFF is res_core's VOL window and the arena runs $6B00-$C000. It is reachable only
* because vm_probe.s writes $FFDF itself (SAM TY=1, above). ★★ The ENGINE's answer is a
* different address and is deliberately so: memmap.inc puts the vocabulary in slot 5
* ($A000-$BFFF), which is unmapped for the whole VM phase, and that file's own header forbids it
* from moving the harness. Two maps, one decision each, both written down.
* ★★★★★ AND IT IS TESTED, NOT ASSUMED. vm_state.s records two tasks of a wrong mechanism read
* out of a host readback -- "MAME cannot see it" and "it is not RAM" are indistinguishable from
* the host. The guest writes a walking pattern here and reads it back ITSELF, exactly as the
* arena self-test does, and reports the first address that does not hold what was written.
VP_VOCAB        equ     $E000
* ★★★★★ $FE00, NOT $FF00 -- THE VECTOR PAGE IS NOT OURS EITHER, AND IT WAS BEING SCRIBBLED ON.
* INIT0 bit 3 (MC3) is set by HAL_sys_init and preserved by HAL_time_init [time.s:61-62,98], so
* $FE00-$FEFF is constant RAM holding the interrupt vectors. The vocabulary self-test writes a
* walking pattern the length of its window and this window ENDED AT $FF00 -- so it has been
* overwriting the vector page on every VM run since T-P0-060.
* ★★★★ IT WAS HARMLESS FOR EXACTLY AS LONG AS NOTHING ENABLED INTERRUPTS. Switching the VBL clock
* on made the CPU vector through the garbage the self-test had just written: the probe ran away out
* of vp_vt_rd across 283 distinct PCs, executing the address-derived pattern itself -- and two runs
* traced the SAME address sequence offset by a constant, which is what executing that pattern looks
* like. The control settles it: HEAD's probe takes the identical path to frame 46 and then goes
* vm_st_c -> vm_st_ozero -> vp_wait and parks, 71% of samples at the gate.
* ★★★ **This is §2M.1's shape in the harness** -- a defect latent in a tree that never exercises
* the path, surfacing the moment a second client does. The clock change did not cause it; it was
* the first thing to READ what the self-test had been writing.
* ★★ 7,680 still clears the 6,828 the window must hold, so nothing is lost by stopping lower.
VP_VOCAB_END    equ     $FE00           ; $FE00-$FEFF is the VECTOR PAGE; $FF00+ is I/O
VP_VOCAB_MAX    equ     VP_VOCAB_END-VP_VOCAB           ; 7,680 >= 6,828

                org     $0700
vm_probe_entry:
                orcc    #$50
                lds     #VP_HW_STACK
                jsr     HAL_sys_init            ; bare-metal transition, and FAST MODE (§4A)

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ ALL-RAM MODE. HAL_sys_init DOES NOT DO THIS, AND ITS OWN HEADER SAYS SO.
*
* sys.s:118-128, corrected at P2.9: "$FF90 selects ROM MAPPING, and it has no all-RAM setting
* at all: $FFDE/$FFDF, which THIS ROUTINE NEVER WRITES; HAL_gfx_init and HAL_gfx_set_mode write
* $FFDF as their final step." ★★ This probe calls neither -- it renders nothing -- so
* $8000-$FEFF was still ROM, and the arena's first byte above $8000 was the first byte that
* would not hold a value. **The arena self-test below returned $8000 exactly.**
*
* ★★ IT ALSO RETIRES A WRONG CONCLUSION. mem_probe.lua found $8900/$9300/$9400/$A900/$C900/
* $E900 unreadable and everything below $8000 fine, and I read that as "MAME's program space
* does not follow the GIME MMU above $8000". Same evidence, and the cause was ROM: the HOST's
* writes did not stick either, for the same reason the guest's did not. VM_OPSEEN and the trace
* buffer were moved below $8000 on that reasoning -- harmless in itself, and recorded with a
* cause that was not the cause. ★ §2 in miniature: a mechanism that explains the observation is
* not thereby the mechanism, and this one was refutable by a five-line guest-side write test.
*
* ★ REGISTER OWNERSHIP (§2N): $FFDF is inside the $FF80-$FFDF scan window and outside both HAL
* ranges. src/harness/ is excluded from the census and probes are allowlisted by explicit
* filename, so this write is declared here rather than hidden. The alternative -- calling
* HAL_gfx_set_mode for its side effect -- would remap $FFA4-$FFA7 to framebuffer blocks and
* clear 30 KB, both of which a VM probe wants no part of.
* ★ `sta`, not `clr`: `clr` extended reads the address first, and SAM control addresses respond
* to accesses rather than to writes (the same reasoning as sys.s step 5's $FFD9).
                sta     $FFDF                   ; SAM TY=1: $0000-$FEFF is RAM

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE VBL CLOCK SOURCE [Jay's ruling, AD-138]. VAR_SECONDS and friends advance from the
* CoCo3's 60 Hz vertical-sync interrupt, not from a cycle-derived virtual counter.
* ★★★★ WHY IT IS NOT A FIDELITY ARGUMENT: the virtual clock is COUPLED TO OUR PERFORMANCE
* PROBLEM. At T3's 2.22 cycles/s it runs ~4.5x slow against real time and ZERO during a blocked
* message window [AD-135, AD-138], so a timing-dependent puzzle behaves differently at 2.22 than
* at 10 -- and the error CHANGES as T3 improves. VSYNC decouples them.
* ★★★★★ AND THE ORACLE PACES THE SAME WAY ROUND, which is the deeper reason [cycle.cpp:558]:
*     if (_passedPlayTimeCycles >= timeDelay) { inGameTimerResetPassedCycles(); interpretCycle(); }
* **_passedPlayTimeCycles comes from the REAL clock**, so a slow machine DROPS CYCLES and the
* clock keeps real time. Our vm_pace had cause and effect inverted -- time advanced BECAUSE a
* cycle ran -- which slows the clock instead of dropping frames. Different games.
* ★★★ NOTHING SHARED CHANGES (§2M): irq_vbl.s already carries a real GIME VBL handler that
* increments the 16-bit counter at DP $10/$11, and HAL_time_init already installs it at $010C.
* **The machinery was here and was never switched on** -- this probe masked IRQ at entry and
* never called HAL_time_init, so the counter has been dead in every VM run to date.
* ★★ The mask must be LIFTED and stay lifted: a handler masked while the interpreter is blocked
* reproduces the exact defect this ruling exists to remove [Jay's note §4].
* ★★★★★ THE ENABLE IS NOT HERE. IT IS AFTER THE SELF-TESTS, AND PUTTING IT HERE COST A RUN.
* Placed at this line — the obvious spot, beside the all-RAM write — the probe ran the arena and
* vocabulary self-tests with IRQ live and then PARKED AT $8957 FOREVER, with CC.I set, 260 of 260
* samples at ONE address. mask_where.lua's trajectory is unambiguous: frames 1-40 in vp_at_wr /
* vp_at_rd / vp_vt_wr with CC.I CLEAR and VBLs arriving normally (39 of them), then frame 41 at
* $8957 and never anywhere else again.
* ★★★★ THE SELF-TESTS ARE DESTRUCTIVE BY DESIGN AND THAT IS THE POINT OF THEM. vp_at_* writes a
* walking pattern over the WHOLE 21 KB arena, $6B00-$BF00 — **$8957 is inside it** — and vp_vt_*
* does the same over $E000-$FF00. They exist to prove that memory is RAM end to end, so they must
* own the machine while they run. An interrupt taken mid-sweep vectors through plumbing the sweep
* is in the middle of overwriting, and the CPU lands in the pattern it just wrote.
* ★★★ IT IS ALSO WHY THE SYMPTOM POINTED AT THE WRONG THING FOR THREE MEASUREMENTS. The counter
* read 7.79 Hz against 59.92, and "13% of VBLs delivered" reads as a masking problem in the VM's
* hot path — so the search went to every orcc #$50 in the HAL, to HAL_time_frame_count, to DP, and
* to S-as-a-data-pointer, and all four were innocent. **A crashed guest and a masked guest produce
* the same rate.** The discriminator was the ADDRESS, not the rate: one PC with a 100% share is a
* park, and a park is a crash. [§2W.3 — a diagnostic that reports a rate without an address cannot
* distinguish the two things that produce it.]
* ★★ vbl_probe.s is the control that made this readable: identical prologue, no self-tests, 300 of
* 300 VBLs at 59.9227 Hz with CC.I 0.0%. **The machine, the GIME setup, HAL_time_init, the $010C
* vector and hal_vbl_handler are all correct** — nothing shared needed changing (§2M).
* ★★★★ NOR IS HAL_time_init ITSELF HERE, AND THAT IS THE SECOND HALF OF THE SAME LESSON.
* Moving only the `andcc` down and leaving the init at this line, the probe still never reached its
* first park: it ran away DURING vp_vt_rd, wandering 284 distinct PCs with CC.I SET THROUGHOUT --
* so no interrupt took it there and the enable was not the remaining cause.
* ★★★ HAL_time_init WRITES THE GIME, NOT ONLY THE VECTOR. It sets $FF90 = $6C, and INIT0 bit 3 is
* MC3, which maps the $FE00-$FEFF vector page -- INSIDE the $E000-$FF00 range vp_vt_* sweeps. The
* self-test and the clock init are contending for the same 256 bytes, and the self-test loses.
* ★★ So the whole clock bring-up moves below the self-tests, which is where it belonged on its own
* merits: **initialise a device next to where you enable it, not three hundred lines earlier.**

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ THE ARENA SELF-TEST -- IS THE ARENA ACTUALLY RAM, FOR THE GUEST, END TO END?
*
* The arena grew past $8000 and logic 83 then loaded as garbage from byte zero, while the same
* fetch at the same depth was byte-correct when its destination was $6687. That is a claim
* about MEMORY, and it was about to be settled by reading MMU tables and reasoning. ★★ Two
* instruments have already lied in this task by being read instead of run (a coverage table and
* a trace buffer, both in slots MAME cannot see), so this one RUNS: the guest writes a walking
* pattern the length of the arena and reads it back itself, and reports the first address that
* does not hold what was written.
* ★ It is the guest testing guest-visible RAM, which is the only party whose answer matters --
* the host's view above $8000 is known to be unreliable and is not consulted.
                ldx     #RES_ARENA
vp_at_wr:       tfr     x,d
                eora    #$A5
                eorb    #$5A
                stb     ,x+                     ; a function of the address, not a constant
                cmpx    #RES_ARENA_END
                blo     vp_at_wr
                ldx     #RES_ARENA
vp_at_rd:       tfr     x,d
                eora    #$A5
                eorb    #$5A
                cmpb    ,x+
                bne     vp_at_bad
                cmpx    #RES_ARENA_END
                blo     vp_at_rd
                ldd     #0                      ; 0 = every byte of the arena held its pattern
                bra     vp_at_done
vp_at_bad:      leax    -1,x
                tfr     x,d
vp_at_done:     std     VP_ARENA_BAD

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE SAME TEST FOR THE VOCABULARY WINDOW, AND FOR THE SAME REASON.
* $E000-$FEFF is above $8000, which is the range vm_state.s spent two tasks holding a wrong
* mechanism about: a host readback there cannot distinguish "MAME cannot see it" from "it is not
* RAM", and the answer that matters is the GUEST's. So the guest writes and reads it back
* itself, before anything stages a vocabulary into it.
* ★★★ Run BEFORE the host stages, or the test would destroy what it is meant to protect -- and
* the host cannot stage before HAL_sys_init anyway (the MMU is not live until then).
* ★★ A non-zero VP_VOCAB_BAD means the window is not usable and the parser must not be trusted;
* vm_sweep.lua refuses the run rather than staging into it [§2W: a check that cannot refuse is
* not a check].
                ldx     #VP_VOCAB
vp_vt_wr:       tfr     x,d
                eora    #$5A
                eorb    #$A5
                stb     ,x+
                cmpx    #VP_VOCAB_END
                blo     vp_vt_wr
                ldx     #VP_VOCAB
vp_vt_rd:       tfr     x,d
                eora    #$5A
                eorb    #$A5
                cmpb    ,x+
                bne     vp_vt_bad
                cmpx    #VP_VOCAB_END
                blo     vp_vt_rd
                ldd     #0
                bra     vp_vt_done
vp_vt_bad:      leax    -1,x
                tfr     x,d
vp_vt_done:     std     VP_VOCAB_BAD
* ★ The parser's three pointers. par_vocab stays 0 until the host stages a vocabulary; par_said's
* guard makes the whole path inert while it is (see vm_tests.s), so this is the "no parser"
* default cycle.py:83 describes, expressed as an address.
                ldd     #0
                std     par_vocab
                std     vm_saidn
                std     vm_saidm
                clr     vm_fedn
                clr     VP_FEED
                ldx     #VP_INBUF
                stx     par_inbuf
                ldx     #VP_CLNBUF
                stx     par_clnbuf

* ★★★ CLEARED, BECAUSE NOTHING ELSE DOES. VP_FREE is host-settable and the host only writes it
* when it wants a timed run -- so on every other run it held cold-boot RAM, which is not zero,
* and the probe free-ran through all nine titles instead of parking for the handshake. Every
* gate went red at once.
* ★★ SECOND INSTANCE IN ONE SESSION of "a new location added without its initialisation": the
* AC-5 test-coverage table was the first, and it counted from garbage. **A location the HOST may
* write still needs the GUEST to define its power-on value**, because "the host will set it" is
* only true on the runs where the host sets it.
                ldd     #0
                std     VP_FREE
                std     VP_CAL

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE VBL CLOCK GOES LIVE HERE [Jay's ruling, AD-138] — after every destructive self-test
* and before any interpretation. HAL_time_init ran at entry with the mask still up, so the vector
* and the counter are installed; this is the single instruction that starts the clock.
* ★★★ The counter is re-zeroed because the sweeps above ran between init and here, and a clock
* that starts at an arbitrary value is a clock nobody can subtract from. hal_frame_hi/lo are DP
* $10/$11 and are outside both self-test ranges, so this is cheap insurance, not a fix.
* ★★ FIRQ stays masked: there is no sound yet, and an unhandled FIRQ is a crash with a worse
* signature than the one this task just spent three measurements chasing.
* ★★★★★ BEHIND A FLAG, BECAUSE THE GATE MUST NOT BE LEFT RED BY AN UNFINISHED CHANGE.
* The clock source itself is PROVEN [vbl_probe.s: 300 of 300 VBLs, 59.9227 Hz, CC.I 0.0%], and the
* vector-page defect this work uncovered is fixed above and is fixed for everyone. What is NOT yet
* understood is an interaction between live interrupts and the probe's FIRST cycle: with the clock
* on and the host's VP_GO already set, the guest runs away into the $0400-$05FF text buffer before
* its first park -- 109 addresses, all masked, arena_bad=$0000 and vocab_bad=$0000, so both
* self-tests pass and the runaway is downstream of them.
* ★★★★ Jay's ruling accepts the nine-title gate going red while T3 recovers -- but that is a
* STATE-DIFF divergence from a changed clock model, which is a finding. **A guest that crashes is
* not that; it is a defect, and shipping it as "the accepted redness" would spend the ruling's
* budget on a bug.** So the default build is HEAD's behaviour exactly, and the clock is one flag
* away for the task that finishes it.
* ★★★ THE INSTRUMENT TO FINISH IT IS NOW IN THE TREE: vm_sweep.lua's boot-state stall detector is
* what turned thirteen minutes of silent CPU burn into an address list, and mask_where.lua is the
* standalone form. Neither existed this morning.
                ifdef   VM_VBLCLOCK
                jsr     HAL_time_init           ; $010C, $FF90/$FF92/$FF93, counter zeroed
                andcc   #$EF                    ; ★ unmask IRQ. The VBL clock is now running.
                endc

                jsr     vm_start

* ★ The host pokes P1.3's staging parameters (res_volbase / res_slicebase / res_curblk) and the
* DIR tables while the probe sits at the first gate, exactly as res_sweep.lua does -- $FFA6
* does nothing before HAL_sys_init, so staging cannot happen earlier.
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★ AC-7's FREE-RUN. The handshake costs a whole emulated FRAME per cycle -- the guest spins on
* VP_GO until the host's next frame notifier -- so wall time through the gate measures MAME's
* frame rate and nothing about the VM. With VP_FREE set to N the probe runs N cycles back to
* back and parks; the host reads the emulated clock either side and divides.
* ★ Same code path, same staging, same pacing: the only thing removed is the park. A separate
* timing binary would measure a different program [L-56].
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ CLOCK CALIBRATION, WITH THE SCAFFOLDING SEPARABLE. Two figures for one clock are on
* record: 1.7898 MHz (P3.3/P3.13, a 160,009-cycle loop) and 1.7871 MHz (P1.3/P4.4, a
* 160,000-cycle loop). They differ by 0.15% and the hardware constant is 14.31818/8 =
* 1.789773 MHz, which the first matches to five figures and the second does not.
*
* ★★ The suspicion is L-56 -- the timing bracket contains the loop AND the probe's own report
* path, so a fixed overhead is divided into a fixed cycle count and comes out as clock error.
* A single measurement cannot separate the two. **N blocks of 160,000 cycles can**: elapsed =
* (N * 160000 + overhead) / f, so two N values give f and the overhead, and a third CHECKS them.
*
* ★ 20,000 iterations of `leax -1,x` (5 cycles) + `bne` (3, taken or not) = 160,000 exactly.
* `ldx #20000` (3) and the outer decrement are part of the overhead the fit recovers.
vp_loop:
                ldd     VP_CAL
                beq     vp_nocal
                lda     #1
                sta     VP_MARK                 ; ★ bracket opens -- see VP_MARK's note
                ldd     VP_CAL
vp_calblk:      pshs    d
                ldx     #20000
vp_calloop:     leax    -1,x
                bne     vp_calloop
                puls    d
                subd    #1
                std     VP_CAL
                bne     vp_calblk
                lda     #2
                sta     VP_MARK                 ; ★ bracket closes
                clr     VP_GO                   ; park: the host reads the clock here
vp_calwait:     lda     VP_GO
                beq     vp_calwait
vp_nocal:
                ldd     VP_FREE
                beq     vp_paced                ; not free-running: normal handshake
                subd    #1
                std     VP_FREE
                jsr     vm_pace
                lda     vm_quit
                bne     vp_halted
* ★★ A restart STOPS this probe, for the reason vm_core.s gives at vm_restart's declaration: a
* leg that re-initialises is not comparable with one that continues. The host distinguishes the
* two by reading vm_restart -- badop stays 0 for both, so the byte is the only discriminator.
                lda     vm_restart
                bne     vp_halted
* ★★ AC-7's SPLIT. -DVM_PACEONLY runs the pacing gate and NOTHING ELSE, so the difference
* between the two timed runs is the interpreter proper. Measuring the total alone would report
* a number without saying which half to attack, and the pacing path is not free: vm_step_clock
* does a 32-bit divide per tick and runs time_delay*2 times per cycle.
                ifndef  VM_PACEONLY
                jsr     vm_interpret_cycle
                jsr     vm_post_cycle
                endc
                bra     vp_loop
vp_paced:
                jsr     vm_pace                 ; advance the clock until a cycle is due
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ FEED HERE -- AFTER THE PACING GATE, BEFORE THE PUBLISH AND THE PARK.
* cycle.py:418-427 feeds immediately before interpret_cycle(), which emits the trace row at its
* top, so the reference's row for cycle N already carries ENTERED_CLI. The host samples THIS
* probe at the park below, i.e. also before the cycle body -- so feeding here, and not after the
* park, is what makes "cycle N" mean the same thing on both sides.
* ★★★★ THE HOST THEREFORE ARMS ONE PARK EARLY: at the park where VP_CYCLE reads K it writes the
* text and sets VP_FEED for cycle K+1, because the guest passes this point once more before it
* parks again. That off-by-one is real, it is the host's to hold, and vm_sweep.lua says so at
* the site rather than here. ★★★ A one-cycle shift in a flag is precisely the defect P4.x spent
* a task on when the park sat above vm_pace, and it presents as a clock bug rather than a
* wiring bug -- so the seam is stated on both sides and checked by the diff.
* ★★ vm_post_cycle has already cleared ENTERED_CLI / SAID_ACCEPTED / WORD_NOT_FOUND for the
* cycle that just ran, and cycle.py does the same before its next iteration, so the feed lands
* on a cleared state in both. Order: interpret -> reset -> pace -> FEED -> sample.
                lda     VP_FEED
                beq     vp_nofeed
                clr     VP_FEED
                jsr     vp_feed
vp_nofeed:
* ---- THE SAMPLE POINT ---------------------------------------------------------
* ★★★ PACE, THEN PARK. The park was ABOVE vm_pace, so the host sampled before the clock ticks
* that lead to this cycle -- while the oracle's Recorder fires inside interpret_cycle, i.e.
* AFTER them. Everything timer-driven was therefore reported one cycle late: VAR_SECONDS went
* to 1 at oracle cycle 10 and guest cycle 11, and nothing else in 20 cycles could see it.
* ★★ The file's own header already said "parks at vm_pace's EXIT -- after the clock ticks that
* led to this cycle, before the cycle body". The comment was right and the code was two
* instructions away from it; a described invariant that nothing checks is not an invariant.
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PUBLISH THE CUMULATIVE COUNTERS *BEFORE* THE PARK -- THE FREE-RUN NEVER DID.
* This is AD-102's actual defect, and it is not the one the dispatch named. VP_OPCOUNT was
* written ONLY in the block below, i.e. only on the handshake path AFTER a cycle. In free-run
* mode the host writes VP_FREE and releases; the guest runs ONE handshake cycle here, writes
* VP_OPCOUNT from it, then loops through VP_FREE free-run cycles that write NOTHING, and parks.
* ★★★★ So the number the host read was the count from a single cycle -- logic.0's
* initialisation -- taken BEFORE the free run began. Every cycle the measurement was about was
* invisible to it.
* ★★★★★ MEASURED, NOT ARGUED: baseline at TIMED=1 (2 cycles) reported opcount=184, and at
* TIMED=20 (21 cycles) reported opcount=184, and at TIMED=200 (201 cycles) reported opcount=184.
* **A counter that does not move when the work is multiplied by a hundred is not measuring the
* work.** That it also matched across ablation ARMS was a symptom, not the disease.
* ★★★ vm_cycle and vm_opcount are cumulative and monotone, so publishing them at the park is
* correct on BOTH paths: in handshake mode nothing has changed since the block below wrote
* them, and in free-run mode this is the only write that ever sees the free-run's work.
                ldd     vm_cycle
                std     VP_CYCLE
                ldd     vm_opcount
                std     VP_OPCOUNT
                clr     VP_GO
vp_wait:        lda     VP_GO
                beq     vp_wait

                lda     vm_quit
                bne     vp_halted
* ★★ A restart STOPS this probe, for the reason vm_core.s gives at vm_restart's declaration: a
* leg that re-initialises is not comparable with one that continues. The host distinguishes the
* two by reading vm_restart -- badop stays 0 for both, so the byte is the only discriminator.
                lda     vm_restart
                bne     vp_halted

* ★★★★★ GUARDED, BECAUSE -DVM_PACEONLY MUST MEAN *NO INTERPRETATION ANYWHERE* [L-79].
* The free-run branch above has carried `ifndef VM_PACEONLY` since T-P0-033 and this one did
* not, so the pace-only arm still ran exactly one interpret cycle -- the one whose count was
* then the only thing published. **An arm that is supposed to do no work must be able to drive
* the check to zero, or the check has never been shown able to fail.**
                ifndef  VM_PACEONLY
                jsr     vm_interpret_cycle
                jsr     vm_post_cycle
                endc

                ldd     vm_cycle
                std     VP_CYCLE
                ldd     vm_lastlen
                std     VP_CODELEN
                ldd     vm_lastip
                std     VP_IP
                lda     vm_op
                sta     VP_LASTOP
                ldd     vm_opcount
                std     VP_OPCOUNT
                lda     vm_icguard
                sta     VP_ICGUARD
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE POST-CYCLE CHECK MUST TEST vm_restart TOO, AND MEASUREMENT IS WHAT SAID SO.
* This tested vm_quit alone. A restart fires DURING a cycle body, so with only the quit test
* here the probe looped, paced, and parked once more before vp_wait's guard caught it -- the host
* sampled one extra row and only then saw the halt.
* ★★★★ MEASURED, NOT REASONED: Kingquest3's parser arm gave **oracle 508 cycles, guest 509**,
* and vm_diff.py reported `AC-2 PASS -- byte-identical on every compared cycle`. It passes
* because its length rule is `len(guest) >= len(oracle)` and it compares min(), so a guest that
* runs PAST the reference satisfies it. **The gate passed on an asymmetry, by accident of the
* rule rather than by agreement** -- which is this task's own subject aimed at itself.
* ★★★ cycle.py exits its run loop on should_restart at the top of the next iteration, i.e. after
* the cycle in which it fired. Testing it here is what makes the two legs stop at the same cycle.
* ★★ vm_diff.py's rule is tightened to `==` in the same change, so the next asymmetry of this
* shape fails instead of passing quietly.
                lda     vm_restart
                bne     vp_halted
                lda     vm_quit
                beq     vp_ok
vp_halted:      lda     #1
                sta     VP_STATUS
                lda     vm_badop
                sta     VP_BADOP
                lda     vm_badlogic
                sta     VP_BADLOGIC
* ★★ `lbra`, NOT `bra`. The publish block above added 8 bytes and pushed both of these past the
* -128 reach; lwasm said "Byte overflow" and named the branch, not the insertion. ★ Same shape as
* pic_fill.s's ff_win_row placement -- an insert in the middle of a loop is a range change, and
* the assembler reports it at the far end.
                lbra    vp_loop
vp_ok:          clr     VP_STATUS
                lbra    vp_loop

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ vp_feed -- what pressing Enter does. words.cpp:326 parseUsingDictionary, via
* parser.py parse_using_dictionary, via par_parse.
*
* ★★★★ THE THREE SIDE EFFECTS ARE THE CALLER'S, NOT par_parse's, AND cycle.py PUTS THEM IN THE
* SAME PLACE [cycle.py feed_input]:
*     st.set_flag(VM_FLAG_ENTERED_CLI, entered)
*     st.set_flag(VM_FLAG_SAID_ACCEPTED_INPUT, False)
*     if not_found: self.set_var(VM_VAR_WORD_NOT_FOUND, not_found)
* ★★★ THE `if not_found` IS LOAD-BEARING AND IS EASY TO DROP. The reference writes the variable
* only when a word was NOT found; writing 0 unconditionally would be a different program on
* every cycle where a line parses cleanly, and vm_post_cycle is what zeroes it afterwards.
* ★★ par_cli / par_accepted are read back out of parser.s here and published into VM_FLAGS,
* which is the home of record (§2F) and the half of the state the AC-2 diff actually compares.
vp_feed:
                ldx     #VP_INBUF
                stx     par_inbuf
                ldx     #VP_CLNBUF
                stx     par_clnbuf
                jsr     par_parse
                lda     #FLAG_ENTERED_CLI
                ldb     par_cli
                jsr     vm_setflag
                lda     #FLAG_SAID_ACCEPTED
                clrb
                jsr     vm_setflag
                lda     par_notfound
                beq     vp_feed_nonf            ; ★ ONLY when a word was not found
                ldb     par_notfound
                lda     #VAR_WORD_NOT_FOUND
                jsr     vm_setvar
vp_feed_nonf:
                inc     vm_fedn
                rts

                include "src/harness/vm_tables.s"
                include "src/harness/vm_state.s"
                include "src/harness/vm_core.s"
                include "src/harness/vm_cmds.s"
                include "src/harness/vm_tests.s"
                include "src/harness/vm_run.s"
                include "src/harness/vm_objects.s"
                include "src/harness/vm_cycle.s"
                include "src/harness/res_core.s"
* ★★★★ THE ENGINE'S PARSER, UNCHANGED, INCLUDED BY THE HARNESS. src/engine/parser.s is gated at
* 23,328 cases across five titles [T-P0-059] and is not touched by this task -- if it were, that
* gate would be a claim about a different file. The wiring is vm_tests.s's vmtest_said and
* vp_feed above, both of which are new code in the HARNESS.
                include "src/engine/parser.s"

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"

* ★★ The layout assertion, BEFORE `end` -- P3.13 put one after it, where lwasm has already
* stopped reading, and it enforced nothing until the violation was forced.
VM_CODE_END     equ     *
                ifgt    VM_CODE_END-RES_DIRS
                error   "vm_probe code overlaps RES_DIRS -- shrink it or move the layout"
                endc
* ★★ THE SECOND ASSERTION EXISTS BECAUSE THE FIRST ONE'S ABSENCE COST A SESSION. The arena and
* the object table are now neighbours, and an arena that starts below VM_OBJ_END would have the
* resource layer write live logic bytecode over object state -- which presents as a corrupted
* object, i.e. as a VM defect, at whatever cycle the overlap is first touched.
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ EVERY ADJACENCY, NOT ONE. The only assertion here used to be VM_CODE_END vs RES_DIRS, and
* it was TRUE while the code image ran 1.5 KB past VM_OPSEEN and vmtr_buf at $2900/$2A00 -- the
* interpreter incremented coverage counters inside its own code for a whole task. **A layout
* assertion that names one neighbour certifies nothing about the other three**, and the failure
* it misses is silent: the guest keeps running and only the instrument's output is nonsense.
* ★★ The tell was AC-5 reporting 247 distinct test opcodes against a possible 18. An instrument
* whose reading is impossible is the cheap case; one whose reading is merely plausible is the
* expensive one, and this layout had already produced two of those.
* ★ Each pair below is checked in the direction that can actually fail, and they are ordered as
* the map in vm_state.s is ordered, so a new region has an obvious place to be added.
* ═══════════════════════════════════════════════════════════════════════════════════
                ifgt    VM_OBJ_END-VM_TESTSEEN
                error   "VM_OBJ overlaps VM_TESTSEEN"
                endc
* ★★★ T-P0-060's THREE NEW REGIONS, each checked in the direction that can fail. The input
* buffers live in the 224-byte gap between the object table and the coverage tables, which is a
* gap only as long as neither neighbour moves -- and both have moved before (vm_state.s's own
* header is about exactly that).
                ifgt    VM_OBJ_END-VP_INBUF
                error   "VM_OBJ overlaps VP_INBUF -- the object table would eat the input line"
                endc
                ifgt    VP_INBUF+42-VP_CLNBUF
                error   "VP_INBUF overlaps VP_CLNBUF"
                endc
                ifgt    VP_BUF_END-VM_TESTSEEN
                error   "the input buffers overlap VM_TESTSEEN"
                endc
* ★★ And the vocabulary window must hold the corpus. 6,828 is SpaceQuest-2's WORDS.TOK, the
* largest of the twelve [T-P0-059 §3.E]. An assertion, not a table a human reads [AD-78].
                ifgt    6828-VP_VOCAB_MAX
                error   "the vocabulary window is smaller than the largest corpus WORDS.TOK (6,828 B)"
                endc
                ifgt    RES_ARENA_END-VP_VOCAB
                error   "RES_ARENA runs into the vocabulary window"
                endc
                ifgt    VM_TESTSEEN+256-VM_OPSEEN
                error   "VM_TESTSEEN overlaps VM_OPSEEN"
                endc
                ifdef   VM_TRACE
                ifgt    VM_OPSEEN+256-vmtr_buf
                error   "VM_OPSEEN overlaps vmtr_buf"
                endc
                ifgt    vmtr_buf+VMTR_MAX*4-RES_ARENA
                error   "vmtr_buf overlaps RES_ARENA -- shrink VMTR_MAX or move the arena"
                endc
                endc
                ifgt    VM_OPSEEN+256-RES_ARENA
                error   "VM_OPSEEN overlaps RES_ARENA"
                endc
                ifgt    VM_OBJ_END-RES_ARENA
                error   "VM_OBJ overlaps RES_ARENA -- the object table would be overwritten"
                endc
* ★ And the arena must stop short of the VOL window res_core maps at $C000.
                ifgt    RES_ARENA_END-$C000
                error   "RES_ARENA_END runs into the $C000 volume window"
                endc
                end     vm_probe_entry
