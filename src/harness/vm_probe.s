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
VP_HW_STACK     equ     $0700

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
vp_calblk:      pshs    d
                ldx     #20000
vp_calloop:     leax    -1,x
                bne     vp_calloop
                puls    d
                subd    #1
                std     VP_CAL
                bne     vp_calblk
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
* ---- THE SAMPLE POINT ---------------------------------------------------------
* ★★★ PACE, THEN PARK. The park was ABOVE vm_pace, so the host sampled before the clock ticks
* that lead to this cycle -- while the oracle's Recorder fires inside interpret_cycle, i.e.
* AFTER them. Everything timer-driven was therefore reported one cycle late: VAR_SECONDS went
* to 1 at oracle cycle 10 and guest cycle 11, and nothing else in 20 cycles could see it.
* ★★ The file's own header already said "parks at vm_pace's EXIT -- after the clock ticks that
* led to this cycle, before the cycle body". The comment was right and the code was two
* instructions away from it; a described invariant that nothing checks is not an invariant.
                clr     VP_GO
vp_wait:        lda     VP_GO
                beq     vp_wait

                lda     vm_quit
                bne     vp_halted

                jsr     vm_interpret_cycle
                jsr     vm_post_cycle

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
                lda     vm_quit
                beq     vp_ok
vp_halted:      lda     #1
                sta     VP_STATUS
                lda     vm_badop
                sta     VP_BADOP
                lda     vm_badlogic
                sta     VP_BADLOGIC
                bra     vp_loop
vp_ok:          clr     VP_STATUS
                bra     vp_loop

                include "src/harness/vm_tables.s"
                include "src/harness/vm_state.s"
                include "src/harness/vm_core.s"
                include "src/harness/vm_cmds.s"
                include "src/harness/vm_tests.s"
                include "src/harness/vm_run.s"
                include "src/harness/vm_objects.s"
                include "src/harness/vm_cycle.s"
                include "src/harness/res_core.s"

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
