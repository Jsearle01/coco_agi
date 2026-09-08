* src/harness/vm_cycle.s -- start(), the pacing loop, the in-game timer and interpret_cycle().
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE CYCLE IS THE UNIT THE DIFF IS INDEXED BY. The oracle's patch dumps flags+vars at
* cycle ENTRY, once per interpretCycle() call, counted from zero and taken BEFORE the cycle
* does anything. `cycle N` here must mean exactly that, or the whole diff shifts by one line
* and reports a divergence at the wrong place [cycle.py's own module docstring].
*
* ★★ start() IS INTERPRETER-VISIBLE STATE, NOT SETUP TRIVIA. Scripts branch on vars 20/22/26 to
* decide what machine they are on and on flags 5/9/11 at first run. cycle.py records that the
* first version of the Python VM omitted it and diverged at CYCLE 0 with six differences.
* ═══════════════════════════════════════════════════════════════════════════════════════════


* ═══════════════════════════════════════════════════════════════════════════════════
* ── start() [cycle.py start()] ────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vm_start:
* ★★★★★ THE OBJECT BOUND, RESET WITH THE REST OF THE STATE [P6.11 AC-2, vm_objects.s vm_objtop].
* It belongs here for the same reason VP_FREE's initialisation did: a location the guest relies on
* must have a defined power-on value from the guest, not whatever the previous run or cold-boot
* RAM left in it. ★★★ A stale HIGH mark would only cost speed; a stale LOW one loses objects, and
* on a re-init after restart.game that is exactly the direction it could go wrong.
* ★★ VM_OBJ + one slot: object 0 is the ego and always exists.
* ★★★★★ AC-4's FAULT DOES NOT CLAMP THIS VALUE -- IT DISABLES THE RAISING [vm_state.s,
* vm_cmds.s]. Clamping here would not stick: the first vm_objflags_set would lift the mark again
* and the "fault" build would behave exactly like the good one, which is a fault injection that
* cannot fail [§2W -- the thing this project has now found eight times].
* ★★★★ With raising off, the mark stays at slot 0 and the PREDICTION IS SPECIFIC: the two titles
* whose census max is 0 -- Kingquest1 and PoliceQuest1 -- must still PASS, and the other seven
* must FAIL. A fault that breaks everything proves the gate is connected; one that breaks exactly
* the titles the census says it should proves the gate is measuring the bound.
                ldx     #VM_OBJ                 ; ★ INCLUSIVE mark: slot 0, the ego
                stx     vm_objtop
* clear vars, flags and controllers
                ldx     #VM_VARS
                ldb     #0
vm_st_v:        clr     ,x+
                decb
                bne     vm_st_v
                ldx     #VM_FLAGS
                ldb     #64                     ; flags + controllers, 32 bytes each
vm_st_f:        clr     ,x+
                decb
                bne     vm_st_f
                ldx     #VM_OBJROOMS
                ldb     #0
vm_st_o:        clr     ,x+
                decb
                bne     vm_st_o
                ldx     #VM_OPSEEN
                ldb     #0
vm_st_c:        clr     ,x+
                decb
                bne     vm_st_c
* ★★ AND THE TEST TABLE, which the first version of the test counter did not clear. An `inc`
* counter is only meaningful from a known start: VM_TESTSEEN held cold-boot RAM, so AC-5 read
* 256 distinct test opcodes against a possible 18. **The table was added and its initialisation
* was not** -- and the reading was impossible rather than plausible, which is the cheap case.
                ldx     #VM_TESTSEEN
                ldb     #0
vm_st_t:        clr     ,x+
                decb
                bne     vm_st_t

* ★ every object starts with stepTime/stepTimeCount/cycleTime/cycleTimeCount/stepSize = 1
* [state.py ScreenObj.__init__]. Zero there would stall every cycler permanently.
                ldx     #VM_OBJ
                ldb     #VM_OBJ_MAX
vm_st_ob:       pshs    b
                clra
                ldb     #VMO_SIZE
vm_st_ozero:    clr     ,x
                leax    1,x
                decb
                bne     vm_st_ozero
                leax    -VMO_SIZE,x
                lda     #1
                sta     VMO_STEPSIZE,x
                sta     VMO_STEPTIME,x
                sta     VMO_STEPTIMECNT,x
                sta     VMO_CYCLETIME,x
                sta     VMO_CYCLETIMECNT,x
                leax    VMO_SIZE,x
                puls    b
                decb
                bne     vm_st_ob

* runGame(): the DOS branch. ★ §2.1 -- on the CoCo3 var 26 will NOT be kAgiMonitorEga, and a
* game branching on it takes a different path. That is a real decision for the target and is
* NOT settled here; this value exists to match the oracle and nothing more.
                lda     #VAR_COMPUTER
                ldb     #kAgiComputerPC
                jsr     vm_setvar
                lda     #VAR_SOUNDGENERATOR
                ldb     #kAgiSoundPC
                jsr     vm_setvar
                lda     #VAR_MONITOR
                ldb     #kAgiMonitorEga
                jsr     vm_setvar
                lda     #VAR_FREE_PAGES
                ldb     #180
                jsr     vm_setvar
                lda     #VAR_MAX_INPUT_CHARS
                ldb     #38
                jsr     vm_setvar

* playGame(). ★ The oracle's source comment beside flag 11 reads "not in 2.917" and the CODE
* sets it unconditionally; the dump for a 2.917 game confirms it is set. Code over comment --
* CLAUDE.md §2 ranks comments lowest.
                lda     #FLAG_LOGIC_ZERO_FIRST
                ldb     #1
                jsr     vm_setflag
                lda     #FLAG_NEW_ROOM_EXEC
                ldb     #1
                jsr     vm_setflag
                lda     #FLAG_SOUND_ON
                ldb     #1
                jsr     vm_setflag
                lda     #1
                sta     vm_gfxmode              ; cycle.cpp:382, before the main loop

                lda     #FLAG_ENTERED_CLI
                clrb
                jsr     vm_setflag
                lda     #FLAG_SAID_ACCEPTED
                clrb
                jsr     vm_setflag
                lda     #VAR_WORD_NOT_FOUND
                clrb
                jsr     vm_setvar
                lda     #VAR_KEY
                clrb
                jsr     vm_setvar

                ldd     #0
                std     vm_cycle
                std     vm_vms
                std     vm_vms+2
                std     vm_lastsec
                std     vm_lastsec+2
                std     vm_lastcyc
                std     vm_lastcyc+2
* ★ The second-boundary counter resets with the clock it counts. `fcb 0` covers the first run;
* this covers a restart, which is what vm_lastsec's zeroing above used to cover.
                clr     vm_sectick
                clr     vm_quit
                clr     vm_restart              ; ★ a location the host may read still needs the
                                                ;   GUEST to define its power-on value [vm_probe.s]
                clr     vm_exitall
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── reset_controllers ─────────────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vm_reset_ctrl:
                ldx     #VM_CTRL
                ldb     #32
vm_rc_lp:       clr     ,x+
                decb
                bne     vm_rc_lp
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── interpret_cycle [cycle.py interpret_cycle] ────────────────────────────────────
*
* ★ The host samples flags+vars BEFORE this is entered -- that is what makes "cycle N" mean the
* same thing on both sides. The probe's GO gate is the sampling point.
* ═══════════════════════════════════════════════════════════════════════════════════
vm_interpret_cycle:
* ★★★ THE LOGIC CACHE'S FLUSH POINT, AND IT MUST BE HERE RATHER THAN IN new.room. res_depth is 0
* at the top of a cycle, so nothing is executing out of the arena and res_top can move. Doing it
* inside new.room -- which runs INSIDE a logic -- overwrote the running logic and halted all nine
* titles at cycle 0. See res_cache_reset's block in res_core.s.
                jsr     res_cache_flush
                ldd     vm_cycle
                addd    #1
                std     vm_cycle

                clra
                jsr     vm_obj                  ; X -> ego
                tst     vm_playerctl
                bne     vm_ic_player
                ldb     VMO_DIR,x               ; not under player control: publish the direction
                lda     #VAR_EGO_DIRECTION
                jsr     vm_setvar
                bra     vm_ic_motions
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ vm_obj DESTROYS B. Its first act after the bound check is `tfr a,b`, because it turns the
* object NUMBER into an offset. So `jsr vm_getvar / tfr a,b / clra / jsr vm_obj / stb VMO_DIR,x`
* stores the OBJECT INDEX, not the direction -- and for the ego, whose index is 0, it stores 0.
*
* ★★ larry1: the ego was under move.obj with a destination of (80,160), motion_move_obj computed
* direction 3 and published it as var 6 correctly, and then this line put 0 back. The watch
* showed `dir 0 ... var6 3` on the same line, which is the pair that named it.
* ★ THE MIRROR OF THE X-CLOBBER CLASS x_liveness.py finds, in the other register. Same shape --
* a value held in a register across a call that needs it -- and the same fix: take the pointer
* FIRST, fetch the value SECOND, with the pointer stacked across the fetch.
* ═══════════════════════════════════════════════════════════════════════════════════
vm_ic_player:
                clra
                jsr     vm_obj                  ; X -> ego, and B is now scrap
                pshs    x
                lda     #VAR_EGO_DIRECTION
                jsr     vm_getvar               ; ★ clobbers X, hence the stack
                puls    x
                sta     VMO_DIR,x

vm_ic_motions:
                jsr     vm_check_all_motions
                clr     vm_exitall
                clr     vm_icguard

* ---- while run_logic(0) == 0 and not should_quit --------------------------------
* ★★★ THE GUARD IS NOT DEFENSIVENESS, IT IS A DEBUGGING INSTRUMENT THAT EARNED ITS PLACE. This
* loop re-runs logic.0 until it executes an explicit `return`, exactly as the reference does.
* If the bind is wrong -- a zero code length, a bad res_open -- run_logic falls straight off the
* end, retflag stays 0, and the loop spins with the CPU busy and GO never cleared. The first
* run did exactly that: MAME sat there and the harness reported nothing at all, which is the
* least informative failure available. ★★ 64 iterations of logic.0 in one cycle is already
* impossible; hitting the cap halts with a reason instead of hanging [L-37: instrument
* something that can CONTRADICT you].
vm_ic_loop:
                inc     vm_icguard
                lda     vm_icguard
                cmpa    #200
                blo     vm_ic_ok
                lda     #$FD                    ; sentinel: "logic.0 never returned"
                sta     vm_badop
                lda     #1
                sta     vm_quit
                bra     vm_ic_after
vm_ic_ok:
                clra                            ; logic 0
                jsr     vm_call_logic0          ; ★ the cycle needs logic.0's OWN retflag
                lda     vm_quit
                bne     vm_ic_after
                lda     vm_restart              ; ★ cycle.cpp:270's other guard on this same loop
                bne     vm_ic_after
                lda     vm_retflag
                bne     vm_ic_after             ; an explicit `return` ends the loop

                lda     #VAR_WORD_NOT_FOUND
                clrb
                jsr     vm_setvar
                lda     #VAR_BORDER_TOUCH_OBJECT
                clrb
                jsr     vm_setvar
                lda     #VAR_BORDER_CODE
                clrb
                jsr     vm_setvar
                lda     #FLAG_ENTERED_CLI
                clrb
                jsr     vm_setflag
                clr     vm_exitall
                jsr     vm_reset_ctrl
                bra     vm_ic_loop

vm_ic_after:
                jsr     vm_reset_ctrl
* ★ Same defect as vm_ic_player above, same fix -- and this is the one that actually fired every
* cycle, because larry1's ego is not under player control.
                clra
                jsr     vm_obj                  ; X -> ego
                pshs    x
                lda     #VAR_EGO_DIRECTION
                jsr     vm_getvar
                puls    x
                sta     VMO_DIR,x

                lda     #VAR_BORDER_TOUCH_OBJECT
                clrb
                jsr     vm_setvar
                lda     #VAR_BORDER_CODE
                clrb
                jsr     vm_setvar
                lda     #FLAG_NEW_ROOM_EXEC
                clrb
                jsr     vm_setflag
                lda     #FLAG_RESTART_GAME
                clrb
                jsr     vm_setflag
                lda     #FLAG_RESTORE_JUST_RAN
                clrb
                jsr     vm_setflag

                tst     vm_gfxmode
                beq     vm_ic_out
                jsr     vm_update_objs
vm_ic_out:      rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── the pacing loop and the in-game timer [cycle.py run() and timer_update()] ─────
*
* ★★ THE PACING GATE IS REPRODUCED, NOT SKIPPED. run() advances a virtual clock 25 ms per
* iteration and interprets a cycle only when enough has accumulated for VM_VAR_TIME_DELAY.
* That relationship is what makes cycle number and virtual time track each other, which is
* exactly what the timer variables depend on -- skipping it makes vars 11-14 lag.
*
* ★ virtual_ms is 32-bit: 600 cycles at 25 ms is 15,000 ms, but TIME_DELAY can be 0 and the
* loop then runs once per cycle, so the counter must survive long runs. Held big-endian.
* ═══════════════════════════════════════════════════════════════════════════════════
vm_vms          rmb     4               ; virtual_ms
vm_lastsec      rmb     4               ; _last_seconds
vm_lastcyc      rmb     4               ; _last_cycles
vm_passed       fcb     0

* ★★★ SPLIT IN TWO, AND THE SPLIT POINT IS THE SAMPLE POINT. The oracle emits its dump INSIDE
* interpretCycle(), so the compared state is "after the clock ticks that led to this cycle,
* before the cycle body". vm_pace advances the clock and returns when a cycle is DUE without
* running it; the probe parks there for the host to sample, then calls vm_interpret_cycle and
* vm_post_cycle. ★ Running the pacing and the cycle in one call would sample before the timer
* updates and vars 11-14 would read one tick early -- a divergence that looks like a clock bug.

* vm_pace: advance until a cycle is due. Returns with vm_passed reset; the caller runs the cycle.
vm_pace:
                jsr     vm_step_clock
                lda     vm_passed
                cmpa    vm_tdelay
                blo     vm_pace
                clr     vm_passed
                rts

* vm_post_cycle: the four resets run() does after each interpreted cycle.
vm_post_cycle:
                lda     #FLAG_ENTERED_CLI
                clrb
                jsr     vm_setflag
                lda     #FLAG_SAID_ACCEPTED
                clrb
                jsr     vm_setflag
                lda     #VAR_WORD_NOT_FOUND
                clrb
                jsr     vm_setvar
                lda     #VAR_KEY
                clrb
                jsr     vm_setvar
                rts

* vm_step_clock: one VERTICAL-SYNC tick, the timer update, and the current delay threshold.
* ★★★★★ IT COUNTS TICKS, NOT MILLISECONDS [AD-138; the reference's `self.vsync` is the same
* quantity]. It added 25 per iteration and called itself virtual_ms. ★★★★ **Nothing has ever read
* it** -- vm_timer_update advances the game clock from vm_sectick, and the only other writers of
* this location are here and vm_start's reset -- so the milliseconds were a 32-bit accumulator
* maintained for no consumer, and a unit the 6809 cannot measure. As ticks it is the same storage
* and the same cost, and it now names something the machine will actually have: the VBL counter.
* ★★ Kept rather than deleted: removing state nothing reads is a separate change [L-54], and this
* one has a consumer the moment the VBL clock comes off its flag.
vm_step_clock:
                ldd     vm_vms+2
                addd    #1
                std     vm_vms+2
                bcc     vm_sp_nocarry
                ldd     vm_vms
                addd    #1
                std     vm_vms
vm_sp_nocarry:
                inc     vm_passed
                jsr     vm_timer_update

                lda     #VAR_TIME_DELAY
                jsr     vm_getvar
* ★★★★★ x3, NOT x2 -- VM_VAR_TIME_DELAY IS IN 50 ms AGI TICKS AND A TICK IS NOW A VERTICAL SYNC.
* 50 ms is 2 x 25 ms and is 3 x 16.667 ms, so the wall-clock time per cycle is IDENTICAL and only
* the unit changed. cycle.py carries the same multiplier for the same reason [P6.12].
* ★★★ `aslb / rola` doubled; tripling is the double plus the original, which needs the original
* kept -- hence the push. Still 16-bit before the clamp below, so a TIME_DELAY of 85 (the largest
* that fits x3 in a byte) behaves and anything larger clamps visibly rather than aliasing.
                tfr     a,b
                clra
                pshs    d                       ; keep time_delay
                aslb
                rola                            ; x2
                addd    ,s++                    ; + x1 = time_delay * 3
                cmpd    #0
                bne     vm_sp_have
                ldd     #1
* ★ time_delay*2 is clamped into a byte. TIME_DELAY above 127 would overflow it, and the
* reference has no such limit -- but a delay of 128 means ~6.4 s per cycle and no title in the
* pinned set sets one. Clamped rather than truncated, so an unexpected value stalls visibly
* instead of aliasing to a small delay.
vm_sp_have:     cmpa    #0
                beq     vm_sp_fits
                ldb     #$FF
vm_sp_fits:     stb     vm_tdelay
                rts

* ── timer_update [global.cpp inGameTimerUpdate, with the patched clock] ──────────
* ★ cur_cycles = virtual_ms / 25 ; cur_seconds = virtual_ms / 1000. Both are early-outs, and
* the seconds one is what actually advances vars 11-14.
vm_timer_update:
* cur_seconds = vms / 1000. ★ vms only ever grows by 25, so seconds advance by at most 1 per
* call and the general delta arithmetic in the reference collapses to an increment here --
* which is reproduced as an increment, with the guard that says why it is safe.
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE BOUNDARY IS WHAT IS WANTED; THE DIVISION WAS HOW IT WAS OBTAINED [AD-106].
* This was `vms / 1000` by 32-iteration restoring long division, EVERY TICK, and the quotient was
* never used as a number: it was compared against the previous quotient and then stored as it.
* A value that is only ever compared with its own predecessor is a change detector, and a change
* detector does not need arithmetic that produces the value.
*
* ★★★★ WHY 40 IS EXACT AND NOT AN APPROXIMATION. vm_vms starts at 0 (the reset above) and its
* ONLY other writer adds exactly 25 (vm_step_clock, just above). A quotient by 1000 therefore
* increments on precisely every 40th tick, forever. Enumerated before this was written -- those
* two writers are the complete set -- and then SIMULATED over 4,000,000 ticks (27.8 h of game
* time): 100,000 boundaries by division, 100,000 by counter, ZERO disagreements.
* ★★★ Measured before building, per AD-87's precedent: the LOGIC cache beat its own ablation
* because its keying was simulated against the corpus first, and building the ablation's choice
* would have delivered a third of the gain.
*
* ★★ AND IT IS STRICTLY MORE CORRECT AT THE WRAP. 2^32 ms is a multiple of neither 25 nor 1000,
* so when vm_vms wraps the old comparison sees a huge stored quotient against a small new one and
* misfires. The counter never consults vms, so it cannot. That is 49.7 days of game time away and
* is NOT the reason for the change -- it is stated so the change is not later mistaken for a
* behavioural risk it removes.
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ 60, NOT 40 -- THE TICK IS A VERTICAL SYNC NOW [Jay's ruling AD-138; P6.12 moved the
* reference and left this leg behind]. A second is 60 ticks at 60 Hz where it was 40 ticks of
* 25 ms. **The boundary argument above is unchanged and still exact**: vm_sectick's only writers
* are this increment and this clear, so it fires on precisely every 60th tick, forever.
* ★★★★ WHY IT HAD TO CHANGE, and it is a regression I introduced: P6.12 put the REFERENCE on
* vertical-sync ticks and argued the two models were equivalent because the nine-title diff stayed
* 9/9. **That test was run on the no-input arm.** With input fed, five of six titles diverge on
* vars 11 and 12 -- SECONDS and MINUTES -- from cycle 36, guest ahead of oracle, because the
* non-equivalent case I wrote into cycle.py (time_delay == 0: 25 ms here against 16.667 ms there)
* is a case that only INPUT drives titles into. ★★★ L-85, on my own claim: a gate's corpus is part
* of its claim, and I checked the corpus that could not fail.
                inc     vm_sectick
                lda     vm_sectick
                cmpa    #60                     ; one second = 60 vertical syncs
                blo     vm_tu_out
                clr     vm_sectick
* seconds += 1, carrying into minutes / hours / days
                lda     #VAR_SECONDS
                jsr     vm_getvar
                inca
                cmpa    #60
                blo     vm_tu_secs
                clra
                pshs    a
                lda     #VAR_MINUTES
                jsr     vm_getvar
                inca
                cmpa    #60
                blo     vm_tu_mins
                clra
                pshs    a
                lda     #VAR_HOURS
                jsr     vm_getvar
                inca
                cmpa    #24
                blo     vm_tu_hours
                clra
                pshs    a
                lda     #VAR_DAYS
                jsr     vm_getvar
                inca
                tfr     a,b
                lda     #VAR_DAYS
                jsr     vm_setvar
                puls    a
vm_tu_hours:    tfr     a,b
                lda     #VAR_HOURS
                jsr     vm_setvar
                puls    a
vm_tu_mins:     tfr     a,b
                lda     #VAR_MINUTES
                jsr     vm_setvar
                puls    a
vm_tu_secs:     tfr     a,b
                lda     #VAR_SECONDS
                jsr     vm_setvar
vm_tu_out:      rts

* ★★ vm_div32 STOOD HERE -- a restoring long division, 32 iterations, called once per 25 ms tick
* solely to find a second boundary. It and its scratch (vm_q32, vm_dvsr, vm_rem32, vm_dvcnt) are
* gone with its only caller; see vm_timer_update above for the counter that replaced it and for
* the simulation that established the two are the same boundary.
* ★ vm_lastsec and vm_lastcyc survive in the reset above and are now DEAD -- vm_lastsec lost its
* only reader with the comparison, and vm_lastcyc never had one. Left in place deliberately:
* removing them touches the reset path, and AC-3 requires that this change move no byte of state.
* Reported rather than bundled [L-54].

* ★ The second-boundary counter. One byte where four plus a routine used to be.
vm_sectick      fcb     0
vm_tdelay       fcb     0
vm_icguard      fcb     0
