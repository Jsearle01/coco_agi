* src/harness/vm_objects.s -- the per-cycle animation update: the cel cycler and the position pass.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THIS IS HERE FOR THE SAME REASON THE MOTION SUBSET IS, AND IT IS THE BIGGER OF THE TWO.
* T-P0-025 §11 puts "cel decoding and motion" out of scope. Measured with
* vm_motion_impact.py --suppress objects, reference against itself, 600 cycles:
*
*     Kingquest1  divergent    0
*     Kingquest2  divergent  536   first at cycle 49
*     Kingquest3  divergent  594   first at cycle  6   vars 37,38,221-224  flags 221-224
*
* ★★ KQ3 needs it and the motion subset does NOT cover that -- suppressing motion alone left
* KQ3 clean. Two out-of-scope steps, two different titles, and measuring only the first would
* have produced a gate that fails on KQ3 for a reason the diff could not name.
*
* ★★★ BUT "CEL DECODING" AND "THE CEL CYCLER" ARE DIFFERENT THINGS, AND ONLY ONE IS NEEDED.
* Nothing here unpacks a pixel. update_view advances obj.cel and set_cel reads width/height out
* of the VIEW HEADER -- the RLE/mirroring unpack in view.cpp is untouched and stays out of
* scope. That distinction is what makes this affordable.
*
* ★ vm_motion_which.py --module objects measured which branches fire: update_screen_obj_table,
* update_view, update_position, set_cel/set_loop/set_view and clip_view_coordinates. Nothing
* else in objects.py is reached by the gated set.
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ★ _ACTIVE = fAnimated | fUpdate | fDrawn [objects.py:37]
VM_ACTIVE_L     equ     fAnimated+fUpdate+fDrawn        ; $51 -- all three bits are in the LOW byte

* LOOP_TABLE_2 / LOOP_TABLE_4, 9 entries each, generated from the pinned oracle
* [optable.py:372,375]. ★ L-29: read off the generated table, never typed from the Specs.
* ★ the generated tables; the hand-typed copies are gone (L-29)
vm_loop_tab2    equ     VMT_LOOP_TABLE_2
vm_loop_tab4    equ     VMT_LOOP_TABLE_4
* DIR_DX / DIR_DY [optable.py:363,366] -- SIGNED deltas, stored as two's complement bytes.
vm_dir_dx       equ     VMT_DIR_DX
vm_dir_dy       equ     VMT_DIR_DY

* ═══════════════════════════════════════════════════════════════════════════════════
* ── update_screen_obj_table [objects.py] ──────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vm_update_objs:
                clr     vm_changecnt
                ldx     #VM_OBJ
                ldb     #VM_OBJ_MAX
vm_uo_lp:       pshs    b
                lda     VMO_FLAGS+1,x
                anda    #VM_ACTIVE_L
                cmpa    #VM_ACTIVE_L
                lbne    vm_uo_next
                inc     vm_changecnt

* ---- loop selection from the direction ----------------------------------------
                lda     #4
                sta     vm_loopnr
                lda     VMO_FLAGS,x
                bita    #fFixLoop_H
                bne     vm_uo_cyc               ; fFixLoop: leave loop_nr at 4 (= "no change")
                lda     VMO_NUMLOOPS,x
                cmpa    #2
                beq     vm_uo_t2
                cmpa    #3
                beq     vm_uo_t2
                cmpa    #4
                bne     vm_uo_cyc
                ldu     #vm_loop_tab4
                bra     vm_uo_pick
vm_uo_t2:       ldu     #vm_loop_tab2
vm_uo_pick:
                lda     VMO_DIR,x
                lda     a,u
                sta     vm_loopnr
* ★ The oracle's fifth branch (loopTable4 for ANY loop count at version 0x3086 or GID_KQ4) is
* NOT reproduced: neither applies to the pinned v2 corpus. Named so its absence is a decision.
                cmpa    #4
                beq     vm_uo_cyc
                cmpa    VMO_LOOP,x
                beq     vm_uo_cyc
* ★ version <= 0x2272 OR stepTimeCount == 1. The pin is 0x2917, so only the second applies.
                lda     VMO_STEPTIMECNT,x
                cmpa    #1
                bne     vm_uo_cyc
                pshs    x
                lda     vm_loopnr
                jsr     vm_set_loop
                puls    x

* ---- the cel cycler -----------------------------------------------------------
vm_uo_cyc:
                ldd     VMO_FLAGS,x
                bitb    #fCycling
                beq     vm_uo_next
                lda     VMO_CYCLETIMECNT,x
                beq     vm_uo_next              ; zero: the reference does not decrement
                deca
                sta     VMO_CYCLETIMECNT,x
                bne     vm_uo_next
                pshs    x
                jsr     vm_update_view
                puls    x
                lda     VMO_CYCLETIME,x
                sta     VMO_CYCLETIMECNT,x
vm_uo_next:     leax    VMO_SIZE,x
                puls    b
                decb
                lbne    vm_uo_lp

                tst     vm_changecnt
                beq     vm_uo_out
                jsr     vm_update_position
                clra
                jsr     vm_obj                  ; the ego
                ldd     #fOnWater+fOnLand
                jsr     vm_objflags_clr
vm_uo_out:      rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── update_view -- THE CEL CYCLER, and where end.of.loop sets its flag ────────────
* in: X -> object
* ═══════════════════════════════════════════════════════════════════════════════════
vm_update_view:
                lda     VMO_FLAGS,x
                bita    #fDontUpdate_H
                beq     vm_uv_go
                ldd     #fDontUpdate
                jmp     vm_objflags_clr         ; consume the one-shot and return

vm_uv_go:
                lda     VMO_CEL,x
                sta     vm_celcur
                lda     VMO_NUMCELS,x
                deca
                sta     vm_cellast              ; last_cel_nr = numCels - 1

                lda     VMO_CYCLE,x
                bne     vm_uv_eol
* ---- kCycleNormal: advance, wrapping to 0 past the last ------------------------
                lda     vm_celcur
                inca
                cmpa    vm_cellast
                bls     vm_uv_store
                clra
                bra     vm_uv_store

vm_uv_eol:      cmpa    #kCycleEndOfLoop
                bne     vm_uv_rev
* ---- kCycleEndOfLoop ----------------------------------------------------------
* ★★ `advanced` is true only when the cel moved AND did not land ON the last cel. Landing on
* the last cel is what ENDS the cycle, so the flag fires on arrival, not one cel later.
                clr     vm_advanced
                lda     vm_celcur
                cmpa    vm_cellast
                bhs     vm_uv_eol_done          ; cel >= last: cannot advance
                inca
                sta     vm_celcur
                cmpa    vm_cellast
                beq     vm_uv_eol_done
                lda     #1
                sta     vm_advanced
vm_uv_eol_done:
                tst     vm_advanced
                bne     vm_uv_storecur
                jsr     vm_uv_complete
                lda     vm_celcur
                bra     vm_uv_store

vm_uv_rev:      cmpa    #kCycleRevLoop
                bne     vm_uv_reverse
* ---- kCycleRevLoop -----------------------------------------------------------
                clr     vm_advanced
                lda     vm_celcur
                beq     vm_uv_rev_done          ; cel == 0: cannot retreat
                deca
                sta     vm_celcur
                bne     vm_uv_setadv
                bra     vm_uv_rev_done
vm_uv_setadv:   lda     #1
                sta     vm_advanced
vm_uv_rev_done:
                tst     vm_advanced
                bne     vm_uv_storecur
                jsr     vm_uv_complete
                lda     vm_celcur
                bra     vm_uv_store

* ---- kCycleReverse: 0 wraps to last, else step back ---------------------------
vm_uv_reverse:
                lda     vm_celcur
                bne     vm_uv_revdec
                lda     vm_cellast
                bra     vm_uv_store
vm_uv_revdec:   deca
                bra     vm_uv_store

vm_uv_storecur: lda     vm_celcur
vm_uv_store:    jmp     vm_set_cel              ; X still -> the object

* ── the completion path shared by end.of.loop and reverse.loop ──────────────────
* ★★★ ignore_loop_flag IS A SCUMMVM DEVIATION (§2.1), reproduced because the diff is against
* ScummVM. motion.cpp sets it when a motion overwrote the cycler's flag field, and the oracle
* then declines to set the resulting flag -- its own comment says "the original would set an
* unintended game flag ... we do not set any flag". ★ It is NOT a claim about Sierra's
* interpreter, and KQ1 room 22 (the eagle) is among the moments it changes.
vm_uv_complete:
                tst     VMO_IGNLOOPFLAG,x
                bne     vm_uvc_noflag
                pshs    x
                lda     VMO_LOOPFLAG,x
                ldb     #1
                jsr     vm_setflag
                puls    x
vm_uvc_noflag:
                ldd     #fCycling
                jsr     vm_objflags_clr
                clr     VMO_DIR,x
                clr     VMO_CYCLE,x             ; kCycleNormal
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── update_position [checks.cpp updatePosition] ───────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vm_update_position:
                lda     #VAR_BORDER_CODE
                clrb
                jsr     vm_setvar
                lda     #VAR_BORDER_TOUCH_EGO
                clrb
                jsr     vm_setvar
                lda     #VAR_BORDER_TOUCH_OBJECT
                clrb
                jsr     vm_setvar

                ldx     #VM_OBJ
                clr     vm_objidx
vm_up_lp:
                lda     VMO_FLAGS+1,x
                anda    #VM_ACTIVE_L
                cmpa    #VM_ACTIVE_L
                lbne    vm_up_next

                lda     VMO_STEPTIMECNT,x
                cmpa    #1
                bls     vm_up_move
                deca
                sta     VMO_STEPTIMECNT,x
                lbra    vm_up_next
vm_up_move:
                lda     VMO_STEPTIME,x
                sta     VMO_STEPTIMECNT,x

                lda     VMO_X,x
                sta     vm_upx
                lda     VMO_Y,x
                sta     vm_upy
                clr     vm_border

* ★ the step is applied only when fUpdatePos is CLEAR -- the flag means "a command already
* placed this object this cycle, do not also walk it".
                lda     VMO_FLAGS,x
                bita    #fUpdatePos_H
                bne     vm_up_bounds
                lda     VMO_DIR,x
                ldu     #vm_dir_dx
                ldb     a,u                     ; signed dx
                stb     vm_upd
                lda     VMO_STEPSIZE,x
                jsr     vm_smul                 ; A = stepSize * dx, signed
                adda    vm_upx
                sta     vm_upx
                lda     VMO_DIR,x
                ldu     #vm_dir_dy
                ldb     a,u
                stb     vm_upd
                lda     VMO_STEPSIZE,x
                jsr     vm_smul
                adda    vm_upy
                sta     vm_upy

vm_up_bounds:
* ★ x < 0 (version 0x3086 uses <= 0; the pin is 0x2917, so <). x is held as a byte, so
* "negative" is bit 7 -- the step above can carry it there and that is the test.
                lda     vm_upx
                bpl     vm_up_xhigh
                clr     vm_upx
                lda     #4
                sta     vm_border
                bra     vm_up_y
vm_up_xhigh:
                adda    VMO_XSIZE,x
                cmpa    #SCRIPT_WIDTH
                bls     vm_up_y
                lda     #SCRIPT_WIDTH
                suba    VMO_XSIZE,x
                sta     vm_upx
                lda     #2
                sta     vm_border
vm_up_y:
* y - ySize < -1  <=>  y < ySize - 1
                lda     vm_upy
                suba    VMO_YSIZE,x
                cmpa    #$FF
                blt     vm_up_ytop              ; SIGNED: y - ySize < -1
                lda     vm_upy
                cmpa    #SCRIPT_HEIGHT-1
                bhi     vm_up_ybot
                ldd     VMO_FLAGS,x
                bitb    #fIgnoreHorizon
                bne     vm_up_apply
                lda     vm_upy
                cmpa    vm_horizon
                bhi     vm_up_apply
                lda     vm_horizon
                inca
                sta     vm_upy
                lda     #1
                sta     vm_border
                bra     vm_up_apply
vm_up_ytop:     lda     VMO_YSIZE,x
                deca
                sta     vm_upy
                lda     #1
                sta     vm_border
                bra     vm_up_apply
vm_up_ybot:     lda     #SCRIPT_HEIGHT-1
                sta     vm_upy
                lda     #3
                sta     vm_border

vm_up_apply:
                lda     vm_upx
                sta     VMO_X,x
                lda     vm_upy
                sta     VMO_Y,x
* ★ checkCollision()/checkPriority() rollback omitted -- both need the priority screen, which
* this VM does not build. Declared in objects.py the same way.
                lda     vm_border
                beq     vm_up_clearpos
                tst     vm_objidx
                bne     vm_up_notego
                ldb     vm_border
                lda     #VAR_BORDER_TOUCH_EGO
                pshs    x
                jsr     vm_setvar
                puls    x
                bra     vm_up_stopmove
vm_up_notego:
                pshs    x
                ldb     vm_objidx
                lda     #VAR_BORDER_CODE
                jsr     vm_setvar
                ldb     vm_border
                lda     #VAR_BORDER_TOUCH_OBJECT
                jsr     vm_setvar
                puls    x
vm_up_stopmove:
                lda     VMO_MOTION,x
                cmpa    #kMotionMoveObj
                bne     vm_up_clearpos
                jsr     vm_motion_move_obj_stop
vm_up_clearpos:
                ldd     #fUpdatePos
                jsr     vm_objflags_clr
vm_up_next:
                leax    VMO_SIZE,x
                inc     vm_objidx
                lda     vm_objidx
                cmpa    #VM_OBJ_MAX
                lbne    vm_up_lp
                rts

* vm_smul: A = A * vm_upd, where vm_upd is a SIGNED byte in {-1, 0, +1}.
* ★ The oracle multiplies stepSize by a direction delta that is only ever -1/0/+1, so this is a
* negate-or-zero rather than a multiply. Written as the three cases because a `mul` would be
* unsigned and $FF would become 255 * stepSize.
vm_smul:
                ldb     vm_upd
                beq     vm_sm_zero
                bmi     vm_sm_neg
                rts                             ; +1: A unchanged
vm_sm_neg:      nega
                rts
vm_sm_zero:     clra
                rts

vm_changecnt    fcb     0
vm_loopnr       fcb     0
vm_celcur       fcb     0
vm_cellast      fcb     0
vm_advanced     fcb     0
vm_objidx       fcb     0
vm_upx          fcb     0
vm_upy          fcb     0
vm_upd          fcb     0
vm_border       fcb     0
