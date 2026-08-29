* src/harness/vm_cmds.s -- the command opcode handlers.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ TRANSCRIBED FROM tools/agivm/commands.py, WHICH IS TRANSCRIBED FROM op_cmd.cpp. Where a
* handler looks odd it is because the oracle is odd, and the oddity is noted rather than tidied.
* The two that bite hardest:
*
*   increment/decrement CLAMP; add/sub/mul/div WRAP mod 256. commands.py calls that asymmetry
*   out explicitly ("that asymmetry is real and is transcribed, not tidied") and it is
*   reproduced here -- `inc` on 255 must not become 0.
*
*   cmdRindirect is opcode 0x0A, whose TABLE NAME is "lindirect". The name is misleading and the
*   handler name is not; this is the RIGHT-indirect form, var[p0] = var[var[p1]].
*
* ★★ HANDLER CONTRACT: on entry vm_ip points at p[0] (vm_run_logic advanced past the opcode and
* advances by VMOP_ARGS[op] afterwards). Handlers may destroy A, B, X; they must not touch
* vm_ip unless they mean to.
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ── operand fetch ─────────────────────────────────────────────────────────────────
* vm_arg: A = operand index -> A = p[index]
vm_arg:
                pshs    b
                tfr     a,b
                clra
                addd    vm_ip
                ldx     vm_code
                leax    d,x
                lda     ,x
                puls    b,pc

vm_p0:          clra
                bra     vm_arg
vm_p1:          lda     #1
                bra     vm_arg
vm_p2:          lda     #2
                bra     vm_arg
vm_p3:          lda     #3
                bra     vm_arg
vm_p4:          lda     #4
                bra     vm_arg

* vm_v0/v1/v2 -- get_var(p[n])
vm_v0:          jsr     vm_p0
                jmp     vm_getvar
vm_v1:          jsr     vm_p1
                jmp     vm_getvar
vm_v2:          jsr     vm_p2
                jmp     vm_getvar

* vm_obj0 -- X = the object named by p[0]
vm_obj0:        jsr     vm_p0
                jmp     vm_obj

* ═══════════════════════════════════════════════════════════════════════════════════
* ── arithmetic and assignment ─────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════

* ★ increment CLAMPS at 255 -- `if v < 0xFF` in the reference, not a wrap.
vmop_increment:
                jsr     vm_v0
                cmpa    #$FF
                beq     vmop_inc_out
                inca
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar
vmop_inc_out:   rts

* ★ decrement CLAMPS at 0 -- `if v != 0`.
vmop_decrement:
                jsr     vm_v0
                tsta
                beq     vmop_dec_out
                deca
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar
vmop_dec_out:   rts

vmop_assign_n:
                jsr     vm_p1
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar

vmop_assign_v:
                jsr     vm_v1
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar

* ★ add/sub/mul/div WRAP: setVar takes a byte in ScummVM.
vmop_add_n:
                jsr     vm_v0
                pshs    a
                jsr     vm_p1
                adda    ,s+
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar

vmop_add_v:
                jsr     vm_v0
                pshs    a
                jsr     vm_v1
                adda    ,s+
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar

vmop_sub_n:
                jsr     vm_p1
                pshs    a
                jsr     vm_v0
                suba    ,s+
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar

vmop_sub_v:
                jsr     vm_v1
                pshs    a
                jsr     vm_v0
                suba    ,s+
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar

* ★ 8x8 -> low 8 bits. mul on the 6809 is unsigned A*B -> D; the reference masks to 0xFF.
vmop_mul_n:
                jsr     vm_v0
                pshs    a
                jsr     vm_p1
                ldb     ,s+
                mul
                jsr     vm_p0
                jmp     vm_setvar

vmop_mul_v:
                jsr     vm_v0
                pshs    a
                jsr     vm_v1
                ldb     ,s+
                mul
                jsr     vm_p0
                jmp     vm_setvar

vmop_div_n:
                jsr     vm_p1
                sta     vm_divisor
                jsr     vm_v0
                jsr     vm_div8
                jsr     vm_p0
                jmp     vm_setvar

vmop_div_v:
                jsr     vm_v1
                sta     vm_divisor
                jsr     vm_v0
                jsr     vm_div8
                jsr     vm_p0
                jmp     vm_setvar

* vm_div8: A / vm_divisor -> B = quotient.  ★ Restoring shift-subtract; the 6809 has no divide.
* ★ A zero divisor cannot be made faithful -- Python raises ZeroDivisionError and the oracle
* would trap. Returning 0 here would be a silent wrong answer, so it halts like an
* unimplemented opcode does.
vm_div8:
                tst     vm_divisor
                beq     vm_div_zero
                clrb
vm_div_lp:      cmpa    vm_divisor
                blo     vm_div_out              ; UNSIGNED [L-40]
                suba    vm_divisor
                incb
                bra     vm_div_lp
vm_div_out:     rts
vm_div_zero:
                jmp     vm_op_unimpl            ; loud, not a silent 0

vmop_lindirect_n:
                jsr     vm_p1
                tfr     a,b
                jsr     vm_v0                   ; A = var[p0] = the destination var number
                jmp     vm_setvar

vmop_lindirect_v:
                jsr     vm_v1
                tfr     a,b
                jsr     vm_v0
                jmp     vm_setvar

* ★ 0x0A: the table calls it "lindirect"; it is the RIGHT-indirect form.
vmop_rindirect:
                jsr     vm_v1
                jsr     vm_getvar               ; A = var[ var[p1] ]
                tfr     a,b
                jsr     vm_p0
                jmp     vm_setvar

* ═══════════════════════════════════════════════════════════════════════════════════
* ── flags ─────────────────────────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vmop_set:       jsr     vm_p0
                ldb     #1
                jmp     vm_setflag
vmop_reset:     jsr     vm_p0
                clrb
                jmp     vm_setflag
vmop_toggle:    jsr     vm_p0
                pshs    a
                jsr     vm_getflag
                eora    #1
                tfr     a,b
                puls    a
                jmp     vm_setflag
vmop_set_v:     jsr     vm_v0
                ldb     #1
                jmp     vm_setflag
vmop_reset_v:   jsr     vm_v0
                clrb
                jmp     vm_setflag
vmop_toggle_v:  jsr     vm_v0
                pshs    a
                jsr     vm_getflag
                eora    #1
                tfr     a,b
                puls    a
                jmp     vm_setflag

* ═══════════════════════════════════════════════════════════════════════════════════
* ── rooms and logic control ───────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vmop_new_room:  jsr     vm_p0
                jmp     vm_new_room
vmop_new_room_f:
                jsr     vm_v0
                jmp     vm_new_room

vmop_load_logic:
                jsr     vm_p0
                jmp     vm_mark_logic
vmop_load_logic_f:
                jsr     vm_v0
                jmp     vm_mark_logic

* ★★ cmdCall SAVES AND RESTORES ip, code and the current logic number around run_logic. On the
* 6809 the code pointer is P1.3's arena base, so the save/restore is res_open/res_close and the
* arena stack does the work -- see vm_run.s vm_call_logic.
vmop_call:      jsr     vm_p0
                jmp     vm_call_logic
vmop_call_f:    jsr     vm_v0
                jmp     vm_call_logic

* ═══════════════════════════════════════════════════════════════════════════════════
* ── screen objects ────────────────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vmop_animate_obj:
                jsr     vm_obj0
                ldd     VMO_FLAGS,x
                bitb    #fAnimated
                bne     vmop_ao_out             ; already animated: the reference returns
                ldd     #fAnimated+fUpdate+fCycling
                std     VMO_FLAGS,x             ; ★ ASSIGNED, not OR'd -- the reference replaces
                clr     VMO_MOTION,x            ; kMotionNormal
                clr     VMO_CYCLE,x             ; kCycleNormal
                clr     VMO_DIR,x
vmop_ao_out:    rts

vmop_unanimate_all:
                ldx     #VM_OBJ
                ldb     #VM_OBJ_MAX
* ★ vm_objflags_clr already complements the mask, so the clear is expressed once rather than
* as a hand-built AND mask -- lwasm rejects `>>` in an operand and a hand-split high/low pair
* is a second place for the bit assignment to be wrong.
vmop_ua_lp:     pshs    b,x
                ldd     #fAnimated+fDrawn
                jsr     vm_objflags_clr
                puls    b,x
                leax    VMO_SIZE,x
                decb
                bne     vmop_ua_lp
                rts

* ★★ _fix_position: THE HORIZON CLAMP ONLY. commands.py declares the spiral search absent
* because it needs the priority screen. Reproducing the declared partial keeps the two VMs
* identical; reproducing the full oracle would make them differ.
vm_fix_position:
                ldd     VMO_FLAGS,x
                bitb    #fIgnoreHorizon
                bne     vm_fp_out
                lda     VMO_Y,x
                cmpa    vm_horizon
                bhi     vm_fp_out               ; y > horizon: nothing to do (UNSIGNED)
                lda     vm_horizon
                inca
                sta     VMO_Y,x
vm_fp_out:      rts

vmop_draw:      jsr     vm_obj0
                ldd     VMO_FLAGS,x
                bitb    #fDrawn
                bne     vmop_draw_out           ; ★ early-out: draw on a drawn object is a no-op
                ldd     #fUpdate
                jsr     vm_objflags_set
                jsr     vm_fix_position
                ldd     #fDrawn
                jsr     vm_objflags_set
                ldd     #fDontUpdate
                jmp     vm_objflags_clr
vmop_draw_out:  rts

vmop_erase:     jsr     vm_obj0
                ldd     #fDrawn
                jmp     vm_objflags_clr

vmop_position:  jsr     vm_obj0
                jsr     vm_p1
                sta     VMO_X,x
                jsr     vm_p2
                sta     VMO_Y,x
                rts

vmop_position_f:
                jsr     vm_obj0
                jsr     vm_v1
                sta     VMO_X,x
                jsr     vm_v2
                sta     VMO_Y,x
                rts

vmop_get_posn:  jsr     vm_obj0
                ldb     VMO_X,x
                pshs    b
                ldb     VMO_Y,x
                pshs    b
                jsr     vm_p1
                ldb     1,s
                jsr     vm_setvar
                jsr     vm_p2
                ldb     ,s
                jsr     vm_setvar
                leas    2,s
                rts

* ★ dx/dy are SIGNED bytes and the underflow guard is a clamp to ZERO, not a general clamp.
vmop_reposition:
                jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                sta     vm_dx
                jsr     vm_v2
                sta     vm_dy
                puls    x
                ldd     #fUpdatePos
                jsr     vm_objflags_set
* x: if dx < 0 and x < -dx then 0 else x + dx
                lda     vm_dx
                bpl     vm_rp_xpos
                nega                            ; A = -dx, positive
                cmpa    VMO_X,x
                bls     vm_rp_xadd              ; x >= -dx: normal add
                clr     VMO_X,x
                bra     vm_rp_y
vm_rp_xpos:
vm_rp_xadd:     lda     VMO_X,x
                adda    vm_dx
                sta     VMO_X,x
vm_rp_y:
                lda     vm_dy
                bpl     vm_rp_yadd
                nega
                cmpa    VMO_Y,x
                bls     vm_rp_yadd
                clr     VMO_Y,x
                bra     vm_rp_fix
vm_rp_yadd:     lda     VMO_Y,x
                adda    vm_dy
                sta     VMO_Y,x
vm_rp_fix:      jmp     vm_fix_position

vmop_reposition_to:
                jsr     vm_obj0
                jsr     vm_p1
                sta     VMO_X,x
                jsr     vm_p2
                sta     VMO_Y,x
                ldd     #fUpdatePos
                jsr     vm_objflags_set
                jmp     vm_fix_position

vmop_reposition_to_f:
                jsr     vm_obj0
                jsr     vm_v1
                sta     VMO_X,x
                jsr     vm_v2
                sta     VMO_Y,x
                ldd     #fUpdatePos
                jsr     vm_objflags_set
                jmp     vm_fix_position

vmop_set_view:  jsr     vm_obj0
                pshs    x
                jsr     vm_p1
                puls    x
                jmp     vm_set_view
vmop_set_view_f:
                jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                jmp     vm_set_view

vmop_set_loop:  jsr     vm_obj0
                pshs    x
                jsr     vm_p1
                puls    x
                jmp     vm_set_loop
vmop_set_loop_f:
                jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                jmp     vm_set_loop

vmop_set_cel:   jsr     vm_obj0
                pshs    x
                jsr     vm_p1
                puls    x
                jmp     vm_set_cel
vmop_set_cel_f: jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                jmp     vm_set_cel

vmop_current_cel:
                jsr     vm_obj0
                ldb     VMO_CEL,x
                lbra    vm_store_p1
vmop_current_loop:
                jsr     vm_obj0
                ldb     VMO_LOOP,x
                lbra    vm_store_p1
vmop_current_view:
                jsr     vm_obj0
                ldb     VMO_VIEW,x
                lbra    vm_store_p1
vmop_get_priority:
                jsr     vm_obj0
                ldb     VMO_PRIORITY,x
                lbra    vm_store_p1
vmop_get_dir:
                jsr     vm_obj0
                ldb     VMO_DIR,x
                lbra    vm_store_p1
vmop_number_of_loops:
                jsr     vm_obj0
                ldb     VMO_NUMLOOPS,x
                lbra    vm_store_p1
* ★ last.cel is max(0, numCels - 1) -- the max matters when numCels is 0.
vmop_last_cel:  jsr     vm_obj0
                ldb     VMO_NUMCELS,x
                beq     vm_store_p1
                decb
* fall through
vm_store_p1:    pshs    b
                jsr     vm_p1
                puls    b
                jmp     vm_setvar

vmop_fix_loop:  jsr     vm_obj0
                ldd     #fFixLoop
                jmp     vm_objflags_set
vmop_release_loop:
                jsr     vm_obj0
                ldd     #fFixLoop
                jmp     vm_objflags_clr

vmop_set_priority:
                jsr     vm_obj0
                pshs    x
                ldd     #fFixedPriority
                jsr     vm_objflags_set
                jsr     vm_p1
                puls    x
                sta     VMO_PRIORITY,x
                rts
vmop_set_priority_f:
                jsr     vm_obj0
                pshs    x
                ldd     #fFixedPriority
                jsr     vm_objflags_set
                jsr     vm_v1
                puls    x
                sta     VMO_PRIORITY,x
                rts
vmop_release_priority:
                jsr     vm_obj0
                ldd     #fFixedPriority
                jmp     vm_objflags_clr

vmop_stop_update:
                jsr     vm_obj0
                ldd     #fUpdate
                jmp     vm_objflags_clr
vmop_start_update:
                jsr     vm_obj0
                ldd     #fUpdate
                jmp     vm_objflags_set
vmop_force_update:
                rts                             ; forces a redraw; no diffable state

vmop_ignore_horizon:
                jsr     vm_obj0
                ldd     #fIgnoreHorizon
                jmp     vm_objflags_set
vmop_observe_horizon:
                jsr     vm_obj0
                ldd     #fIgnoreHorizon
                jmp     vm_objflags_clr
vmop_set_horizon:
                jsr     vm_p0
                sta     vm_horizon
                rts

vmop_object_on_water:
                jsr     vm_obj0
                ldd     #fOnWater
                jmp     vm_objflags_set
vmop_object_on_land:
                jsr     vm_obj0
                ldd     #fOnLand
                jmp     vm_objflags_set
vmop_object_on_anything:
                jsr     vm_obj0
                ldd     #fOnWater+fOnLand
                jmp     vm_objflags_clr

vmop_ignore_objs:
                jsr     vm_obj0
                ldd     #fIgnoreObjects
                jmp     vm_objflags_set
vmop_observe_objs:
                jsr     vm_obj0
                ldd     #fIgnoreObjects
                jmp     vm_objflags_clr
vmop_ignore_blocks:
                jsr     vm_obj0
                ldd     #fIgnoreBlocks
                jmp     vm_objflags_set
vmop_observe_blocks:
                jsr     vm_obj0
                ldd     #fIgnoreBlocks
                jmp     vm_objflags_clr

* ═══════════════════════════════════════════════════════════════════════════════════
* ── cycling ───────────────────────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vmop_stop_cycling:
                jsr     vm_obj0
                ldd     #fCycling
                jmp     vm_objflags_clr
vmop_start_cycling:
                jsr     vm_obj0
                ldd     #fCycling
                jmp     vm_objflags_set

* ★ v2 sets fCycling as well as the mode; the version test is >= 0x2000 and the pin is 0x2917.
vmop_normal_cycle:
                jsr     vm_obj0
                clr     VMO_CYCLE,x
                ldd     #fCycling
                jmp     vm_objflags_set
vmop_reverse_cycle:
                jsr     vm_obj0
                lda     #kCycleReverse
                sta     VMO_CYCLE,x
                ldd     #fCycling
                jmp     vm_objflags_set

* ★★ setLoopFlag sets loop_flag AND CLEARS ignore_loop_flag. P4.1 set only the number, and a
* stale ignore_loop_flag from an earlier motion then suppressed this cycler's completion flag.
vmop_end_of_loop:
                lda     #kCycleEndOfLoop
                bra     vm_loopcycler
vmop_reverse_loop:
                lda     #kCycleRevLoop
vm_loopcycler:
                sta     vm_tmpcycle
                jsr     vm_obj0
                lda     vm_tmpcycle
                sta     VMO_CYCLE,x
                ldd     #fDontUpdate+fUpdate+fCycling
                jsr     vm_objflags_set
                pshs    x
                jsr     vm_p1
                puls    x
                sta     VMO_LOOPFLAG,x
                clr     VMO_IGNLOOPFLAG,x
                pshs    x
                clrb
                jsr     vm_setflag              ; set_flag(loop_flag, False)
                puls    x
                jmp     vm_cycler_activated

* ★★ BOTH fields take the value: cycleTime = cycleTimeCount = getVar(p1). P4.1 set the count to
* 0 instead, which stalls the cycler for ever -- the update only decrements a non-zero counter.
vmop_cycle_time:
                jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                sta     VMO_CYCLETIME,x
                sta     VMO_CYCLETIMECNT,x
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── motion ────────────────────────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vmop_stop_motion:
                jsr     vm_obj0
                clr     VMO_DIR,x
                clr     VMO_MOTION,x            ; kMotionNormal
                jsr     vm_p0
                tsta
                bne     vmop_sm_out
                lda     #VAR_EGO_DIRECTION
                clrb
                jsr     vm_setvar
                clr     vm_playerctl
vmop_sm_out:    rts

vmop_start_motion:
                jsr     vm_obj0
                clr     VMO_MOTION,x
                jsr     vm_p0
                tsta
                bne     vmop_stm_out
                lda     #VAR_EGO_DIRECTION
                clrb
                jsr     vm_setvar
                lda     #1
                sta     vm_playerctl
vmop_stm_out:   rts

vmop_normal_motion:
                jsr     vm_obj0
                clr     VMO_MOTION,x
                rts

vmop_step_size:
                jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                sta     VMO_STEPSIZE,x
                rts

vmop_step_time:
                jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                sta     VMO_STEPTIME,x
                sta     VMO_STEPTIMECNT,x
                rts

vmop_set_dir:   jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                sta     VMO_DIR,x
                rts

* ── move.obj / move.obj.v ────────────────────────────────────────────────────────
* ★ They differ only in operand fetch; the shared body is vm_move_obj_body.
vmop_move_obj:
                jsr     vm_p1
                sta     vm_mx
                jsr     vm_p2
                sta     vm_my
                jsr     vm_p3
                sta     vm_mstep
                bra     vm_move_common
vmop_move_obj_f:
                jsr     vm_v1
                sta     vm_mx
                jsr     vm_v2
                sta     vm_my
                jsr     vm_p3
                jsr     vm_getvar
                sta     vm_mstep
vm_move_common:
                jsr     vm_p4
                sta     vm_mflag
                jsr     vm_obj0
                lda     #kMotionMoveObj
                sta     VMO_MOTION,x
                lda     vm_mx
                sta     VMO_MOVEX,x
                lda     vm_my
                sta     VMO_MOVEY,x
                lda     VMO_STEPSIZE,x
                sta     VMO_MOVESTEP,x          ; ★ saves the CURRENT step size, before override
                lda     vm_mflag
                sta     VMO_MOVEFLAG,x
                lda     vm_mstep
                beq     vm_mv_nostep
                sta     VMO_STEPSIZE,x
vm_mv_nostep:
                pshs    x
                lda     vm_mflag
                clrb
                jsr     vm_setflag              ; set_flag(move_flag, False)
                puls    x
                ldd     #fUpdate                ; ★ P4.1 omitted this and the object never moved
                jsr     vm_objflags_set
                jsr     vm_motion_activated
                pshs    x
                jsr     vm_p0
                tsta
                bne     vm_mv_notego
                clr     vm_playerctl
vm_mv_notego:   puls    x
* ★ AGI 2.272 does NOT call moveObj here; the pin is 0x2917, so it does.
                jmp     vm_motion_move_obj

vmop_follow_ego:
                jsr     vm_obj0
                lda     #kMotionFollowEgo
                sta     VMO_MOTION,x
                pshs    x
                jsr     vm_p1
                puls    x
                cmpa    VMO_STEPSIZE,x
                bhi     vm_fe_use_p1            ; ★ `<=` keeps the object's own step size
                lda     VMO_STEPSIZE,x
vm_fe_use_p1:   sta     VMO_FOLLOWSTEP,x
                pshs    x
                jsr     vm_p2
                puls    x
                sta     VMO_FOLLOWFLAG,x
                lda     #255
                sta     VMO_FOLLOWCNT,x
                pshs    x
                lda     VMO_FOLLOWFLAG,x
                clrb
                jsr     vm_setflag
                puls    x
                ldd     #fUpdate
                jsr     vm_objflags_set
                jmp     vm_motion_activated

vmop_wander:    jsr     vm_obj0
                pshs    x
                jsr     vm_p0
                tsta
                bne     vm_wd_notego
                clr     vm_playerctl
vm_wd_notego:   puls    x
                lda     #kMotionWander
                sta     VMO_MOTION,x
                ldd     #fUpdate
                jsr     vm_objflags_set
                jmp     vm_motion_activated

vmop_block:     jsr     vm_p0
                sta     vm_blk_x1
                jsr     vm_p1
                sta     vm_blk_y1
                jsr     vm_p2
                sta     vm_blk_x2
                jsr     vm_p3
                sta     vm_blk_y2
                lda     #1
                sta     vm_blk_on
                rts
vmop_unblock:   clr     vm_blk_on
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── inventory ─────────────────────────────────────────────────────────────────────
* ★ object_get/set_location index VM_OBJROOMS, the OBJECT file's own table.
* ═══════════════════════════════════════════════════════════════════════════════════
EGO_OWNED       equ     $FF

vmop_get:       jsr     vm_p0
                ldb     #EGO_OWNED
                bra     vm_objloc_set
vmop_get_f:     jsr     vm_v0
                ldb     #EGO_OWNED
                bra     vm_objloc_set
vmop_drop:      jsr     vm_p0
                clrb
                bra     vm_objloc_set
vmop_put:       jsr     vm_v1
                tfr     a,b
                jsr     vm_p0
                bra     vm_objloc_set
vmop_put_f:     jsr     vm_v1
                tfr     a,b
                jsr     vm_v0
vm_objloc_set:
                ldx     #VM_OBJROOMS
                stb     a,x
                rts

vmop_get_room_f:
                jsr     vm_v0
                ldx     #VM_OBJROOMS
                ldb     a,x
                lbra    vm_store_p1

* ═══════════════════════════════════════════════════════════════════════════════════
* ── control, random, resources ────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vmop_player_control:
                lda     #1
                sta     vm_playerctl
                clra
                jsr     vm_obj                  ; the ego
                lda     VMO_MOTION,x
                cmpa    #kMotionEgo
                beq     vmop_pc_out
                clr     VMO_MOTION,x
vmop_pc_out:    rts

vmop_program_control:
                clr     vm_playerctl
                rts

* ★★★ ScummVM's Common::RandomSource, reproduced bit for bit: xorshift (>>13, <<21, >>11), then
* (seed * 0xDEADBF03) % (max + 1). ★ cycle.py notes this is SCUMMVM's generator, not Sierra's --
* it exists so the state diff is meaningful, and the shipped interpreter is free to differ.
vmop_random:
                jsr     vm_p0
                sta     vm_rndlo
                jsr     vm_p1
                suba    vm_rndlo                ; A = p1 - p0, the generator's `maximum`
                sta     vm_rndmax
                jsr     vm_rnd_next             ; A = get_random_number(maximum)
                adda    vm_rndlo
                tfr     a,b
                jsr     vm_p2
                jmp     vm_setvar

vmop_quit:      lda     #1
                sta     vm_quit
                sta     vm_exitall
                rts

* ★ Resource "loads" are set membership in the reference. The diff never reads those sets, so
* the observable effect is nil -- but they are IMPLEMENTED, not modelled, because load_logic
* has a real effect (it makes the logic fetchable) and the others must stay symmetrical.
vmop_load_view: jsr     vm_p0
                jmp     vm_mark_view
vmop_load_view_f:
                jsr     vm_v0
                jmp     vm_mark_view
vmop_discard_view:
                rts
vmop_discard_view_v:
                rts
vmop_load_pic:  jsr     vm_v0
                rts
vmop_discard_pic:
                jsr     vm_v0
                rts

* ★ set.string stores a message pointer. compare.strings is the only reader and it is never
* executed by the gated set, so the store is a no-op the coverage report names explicitly.
vmop_set_string:
                rts

* ★★ NOT presentation-only despite the name: gfx_mode gates updateScreenObjTable, which writes
* VM_VAR_BORDER_*. Classifying these as MODELLED would silently disable those writes.
vmop_text_screen:
                clr     vm_gfxmode
                rts
vmop_graphics:  lda     #1
                sta     vm_gfxmode
                rts

* ── scratch ───────────────────────────────────────────────────────────────────────
vm_divisor      fcb     0
vm_dx           fcb     0
vm_dy           fcb     0
vm_mx           fcb     0
vm_my           fcb     0
vm_mstep        fcb     0
vm_mflag        fcb     0
vm_tmpcycle     fcb     0
vm_rndmax       fcb     0
vm_rndout       fcb     0
