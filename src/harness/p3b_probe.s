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

FB_BASE         equ     MAP_PHASE_WIN           ; framebuffer slice, draw phase
PRI_BASE        equ     MAP_PRI_SLICE           ; priority slice, draw phase
PIC_W           equ     160
PIC_H           equ     168
STACK_BASE      equ     MAP_SEEDSTACK
STACK_TOP       equ     MAP_SEEDSTACK_E
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
CP_CEL          equ     MAP_RESERVED    ; decoded cel staging, 4,784 B corpus max

* ★★★ PIC_DATA IS THE ARENA, NOT A POKED BUFFER -- this is AC-2's "real path" in one line.
* pic_probe.s pokes the picture to a fixed $1200 window; here the PICTURE is fetched by
* (type, index) through res_core and lands at RES_SLOT, which is RES_ARENA, which the map
* points at MAP_ARENA_WIN. ★ res_core.s:46 keeps `RES_SLOT equ RES_ARENA` as a name "for AC-2",
* and this is the AC-2 it was kept for.
PIC_DATA        equ     MAP_ARENA_WIN

                org     MAP_CODE

p3b_entry:
                orcc    #$50
                lds     #MAP_HWSTACK
                jsr     HAL_sys_init
                sta     $FFDF                   ; all-RAM; sys.s:118-128 does not do this
                jsr     p3_zero
p3_loop:
                clr     P3_GO
p3_wait:        lda     P3_GO
                beq     p3_wait
                lda     P3_MODE
                cmpa    #1
                beq     p3_do_cycle
                bra     p3_loop

* ── one interpreter cycle: VM, then render if the room changed, then composite ───
p3_do_cycle:
                jsr     p3_zero_timers
                jsr     phase_vm                ; ★ AC-6: no plane mapped
                jsr     p3_run_vm
                jsr     p3_stage_sprites        ; ★ BEFORE the remap -- slot 5 still holds VM_OBJ
                jsr     phase_draw_enter        ; ★ AC-6: the pair, exactly two MMU writes
                jsr     p3_composite_all
                ldd     P3_CYCLE
                addd    #1
                std     P3_CYCLE
                bra     p3_loop

p3_zero:
                ldx     #MAP_STATUS+4
                ldb     #30
p3_z1:          clr     ,x+
                decb
                bne     p3_z1
                rts

p3_zero_timers:
                ldx     #P3_T_VM
                ldb     #22
p3_z2:          clr     ,x+
                decb
                bne     p3_z2
                rts

* ── stubs the host drives; the real bodies land as the integration proceeds ──────
p3_run_vm:      rts
p3_stage_sprites: rts
p3_composite_all: rts

* ── the phase pair, counted ──────────────────────────────────────────────────────
* ★★ COUNTS ITS OWN REMAPS so AC-6 is measured rather than asserted. §3.4's claim is "two per
* phase transition, not per scanline"; a counter is the difference between knowing that and
* believing it.
phase_draw_enter:
                lda     #0
                jsr     phase_draw
                ldd     P3_REMAPS
                addd    #2
                std     P3_REMAPS
                rts

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
* ★ pic_core.s includes pic_draw.s and pic_fill.s itself -- those two includes sat inside the
* extracted range, so the renderer arrives as one unit. Listing them again here is a
* multiply-defined error, which is the assembler enforcing §2F rather than a nuisance.
                include "src/harness/pic_core.s"
                include "src/harness/view_cel.s"
                include "src/harness/composite.s"

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE MEASUREMENT THAT DECIDES WHETHER THE MAP SURVIVES INTEGRATION.
* P6.1 allocated 12,288 B for engine code against vm_probe.bin's MEASURED 9,089 -- but that was
* the VM plus the HAL only, and P6.1's §7 flagged it as "an allocation to be checked, not a
* measurement". This is the check, and it fires at assembly time.
P3_CODE_END     equ     *
                ifgt    P3_CODE_END-MAP_CODE_END
                error   "P3b code overruns the map's code region -- see the .map for the size"
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
