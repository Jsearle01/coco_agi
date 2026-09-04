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
* ★★★★ vm_start, AND OMITTING IT PRODUCED A PLAUSIBLE WRONG RUN RATHER THAN A FAILURE.
* Without it the object table is never cleared, so every one of the 255 entries read fDrawn from
* uninitialised RAM: the staging array filled to its 16-sprite cap **every cycle**, the
* compositor then opened 16 garbage VIEW numbers, and the measured rate was 1.93 cycles/second.
* ★★★ None of that looked like a crash. It looked like a slow interpreter -- which is exactly
* the number this task exists to report, so it would have been reported [L-56: the first
* measurement of a new subsystem often measures the scaffolding].
* ★ vm_probe.s:126 calls it before its loop; copying the sequence rather than inventing one is
* what keeps this build's VM identical to the gated one.
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
                lda     #2
                sta     ph_blk_fb
p3_loop:
                clr     P3_GO
p3_wait:        lda     P3_GO
                beq     p3_wait
                lda     P3_MODE
                cmpa    #1
                beq     p3_do_cycle
                bra     p3_loop

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
                jsr     p3_zero_timers
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
                lda     #$3D                    ; the block the host pre-set slot 5 to at boot
                sta     MMU_SLOT5
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

p3_zero_timers:
                ldx     #P3_T_VM
                ldb     #22
p3_z2:          clr     ,x+
                decb
                bne     p3_z2
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
                jsr     phase_draw_enter
                jsr     p3_clear_planes
                ldx     p3_picptr
                stx     pic_ptr
                jsr     pic_render_at
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
p3_clear_planes:
                ldx     #FB_BASE
                ldd     #$FFFF                  ; visual 15, both nibbles (the pixel doubling)
p3_cv:          std     ,x++
                cmpx    #FB_BASE+(PIC_W*PIC_H)
                blo     p3_cv
                ldx     #PRI_BASE
                ldd     #$4444                  ; four packed pixels of priority 4
p3_cp:          std     ,x++
                cmpx    #PRI_BASE+(PIC_W*PIC_H/2)
                blo     p3_cp
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
p3_composite_all:
                lda     p3_nspr
                beq     pca_out
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
                ldx     res_base
                stx     vc_view
                ldx     #CP_CEL
                stx     vc_dest
                jsr     vc_decode_cel
                lda     vc_err
                bne     pca_close
                jsr     cp_composite
pca_close:      jsr     res_close
pca_skip:       puls    y
                inc     p3_si
                lda     p3_si
                cmpa    p3_nspr
                blo     pca_lp
pca_out:        rts

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
* ★★★ plane_win.s before pic_core.s: pic_core's windowed sites `jsr plane_vis`, and the module
* must be defined first. Guarded, so a flat build of this probe is unaffected -- though a flat
* build is exactly what memmap.inc's reachability assertion now refuses (§AC-2, T-P0-041).
                ifdef   PLANE_WINDOWED
                include "src/harness/plane_win.s"
                endc
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
