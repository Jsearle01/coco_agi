* src/harness/p3b_boot_test.s -- does the HAL's boot sequence survive at MAP_CODE ($2000)?
*
* ★★★ THE INTEGRATED PROBE LOADS AND RUNS AWAY: sampled PCs $6D43 / $C014 / $0981 / $56B5,
* settling in ROM at $8005, with the handshake never cleared. That is a boot failure, not a
* logic failure, and a state diff cannot localise it [L-59].
* ★★ Every earlier probe orgs at $0700. This one orgs at $2000 because memmap.inc puts the code
* region there. **This file changes exactly one thing from the working probes -- the org -- and
* does nothing else**, so if it clears the handshake the org is innocent and the fault is in
* p3b's own code.
* ★ Deliberately does NOT include the VM, renderer or compositor: the point is to remove
* everything that could be blamed.

                include "src/engine/memmap.inc"

                org     MAP_CODE

* ★★★ PROGRESS MARKERS, because a PC histogram says WHERE it ended up and not HOW FAR it got
* [L-59]. Each write lands in a byte the host reads after the run, so the last marker seen names
* the instruction it died after -- which is what a runaway across the whole map cannot tell you.
bt_entry:
                orcc    #$50
                lda     #$A1
                sta     MAP_STATUS+1
                lds     #MAP_HWSTACK
                lda     #$A2
                sta     MAP_STATUS+1
                jsr     HAL_sys_init
                lda     #$A3
                sta     MAP_STATUS+1
                sta     $FFDF                   ; all-RAM
                lda     #$A4
                sta     MAP_STATUS+1
                clr     MAP_STATUS              ; ★ the handshake: the host watches this byte
bt_spin:        bra     bt_spin

* ★★ STEP 2 of the bisection, behind a flag: the same trivial entry, but with every subsystem
* the real probe includes. If boot survives this, the includes are innocent and the fault is in
* p3b's own glue; if it does not, one of the includes is doing something at load time.
                ifdef   BT_WITH_SUBSYS
RES_DIRS        equ     MAP_DIRS
RES_ARENA       equ     MAP_ARENA_WIN
RES_ARENA_END   equ     MAP_ARENA_WIN_E
VM_VARS         equ     MAP_VM_VARS
VM_FLAGS        equ     MAP_VM_FLAGS
VM_CTRL         equ     MAP_VM_CTRL
VM_OBJROOMS     equ     MAP_VM_OBJROOMS
VM_OBJ          equ     MAP_PRI_SLICE
FB_BASE         equ     MAP_PHASE_WIN
PRI_BASE        equ     MAP_PRI_SLICE
PIC_W           equ     160
PIC_H           equ     168
STACK_BASE      equ     MAP_SEEDSTACK
STACK_TOP       equ     MAP_SEEDSTACK_E
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
PRI_W           equ     PIC_W
PRI_H           equ     PIC_H
CP_X            equ     MAP_STATUS+54
CP_Y            equ     MAP_STATUS+55
CP_PRIO         equ     MAP_STATUS+56
CP_TESTED       equ     MAP_STATUS+60
CP_WRITTEN      equ     MAP_STATUS+64
CP_REJPRI       equ     MAP_STATUS+68
CP_REJKEY       equ     MAP_STATUS+72
CP_BLITS        equ     MAP_STATUS+76
CP_CTRLHIT      equ     MAP_STATUS+80
CP_CTRLSTEP     equ     MAP_STATUS+84
CP_VIS          equ     FB_BASE
CP_PRI          equ     PRI_BASE
CP_CEL          equ     MAP_RESERVED
PIC_DATA        equ     MAP_ARENA_WIN
                include "src/engine/mmu_phase.s"
                include "src/harness/vm_tables.s"
                include "src/harness/vm_state.s"
                include "src/harness/vm_core.s"
                include "src/harness/vm_cmds.s"
                include "src/harness/vm_tests.s"
                include "src/harness/vm_run.s"
                include "src/harness/vm_objects.s"
                include "src/harness/vm_cycle.s"
                include "src/harness/res_core.s"
                include "src/harness/pic_core.s"
                include "src/harness/view_cel.s"
                include "src/harness/composite.s"
                endc

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"
                end     bt_entry
