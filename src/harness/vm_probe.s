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
RES_ARENA       equ     $4000           ; the residency arena -- 12 KB, unchanged in SIZE
RES_ARENA_END   equ     $7000

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
VP_HW_STACK     equ     $0700

                org     $0700
vm_probe_entry:
                orcc    #$50
                lds     #VP_HW_STACK
                jsr     HAL_sys_init            ; bare-metal transition, and FAST MODE (§4A)

                jsr     vm_start

* ★ The host pokes P1.3's staging parameters (res_volbase / res_slicebase / res_curblk) and the
* DIR tables while the probe sits at the first gate, exactly as res_sweep.lua does -- $FFA6
* does nothing before HAL_sys_init, so staging cannot happen earlier.
vp_loop:
                clr     VP_GO
vp_wait:        lda     VP_GO
                beq     vp_wait

                lda     vm_quit
                bne     vp_halted

                jsr     vm_pace                 ; advance the clock until a cycle is due
* ---- THE SAMPLE POINT ---------------------------------------------------------
* ★ The host has already read VM_VARS/VM_FLAGS for this cycle while we were parked above.
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
                end     vm_probe_entry
