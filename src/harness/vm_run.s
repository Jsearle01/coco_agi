* src/harness/vm_run.s -- the cycle, resource binding, VIEW metadata, motion and the RNG.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE MOTION SUBSET IS HERE BECAUSE IT WAS MEASURED TO BE NECESSARY, NOT BECAUSE THE
* DISPATCH ASKED FOR IT. T-P0-025 §11 puts motion out of scope; AC-2 requires 256 vars and 256
* flags byte-identical against tools/agivm for >=500 cycles across >=3 titles with an EMPTY
* exclusion set. interpret_cycle() calls check_all_motions() BEFORE logic.0, and get.posn --
* 3,625 executions in the gated set -- copies object x/y into variables.
*
* Measured with harness/tools/vm_motion_impact.py, reference against itself, 600 cycles:
*     Kingquest1  divergent    0
*     Kingquest2  divergent  530   first at cycle 49   18 vars, 17 flags
*     Kingquest3  divergent    0
* ★★ So two titles do not need it and one does, and "three titles" is the AC.
*
* ★★★ AND ONLY A SUBSET FIRES. vm_motion_which.py counted the branches: KQ2 reaches
* check_motion, check_step, is_ego, get_direction, motion_move_obj, motion_move_obj_stop,
* cycler_activated and motion_activated. It never reaches wander, follow.ego, check_block or
* change_pos. Those are NOT implemented, and check_motion HALTS on them rather than falling
* through -- a mode we do not model must not become a silent no-op (AC-4).
* ═══════════════════════════════════════════════════════════════════════════════════════════

SCRIPT_WIDTH    equ     160
SCRIPT_HEIGHT   equ     168

* ── interpreter state that vm_core.s reads ────────────────────────────────────────
vm_code         fdb     0               ; -> the CURRENT logic's bytecode (inside the arena)
vm_horizon      fcb     36
vm_playerctl    fcb     0
vm_gfxmode      fcb     0
vm_blk_on       fcb     0
vm_blk_x1       fcb     0
vm_blk_y1       fcb     0
vm_blk_x2       fcb     0
vm_blk_y2       fcb     0
vm_rndlo        fcb     0
vm_vwbase       fdb     0               ; base of the VIEW currently open
vm_vtmp         fdb     0
vm_vtmp2        fdb     0

* ═══════════════════════════════════════════════════════════════════════════════════
* ── resource binding ──────────────────────────────────────────────────────────────
*
* ★★★ THE ARENA STACK IS THE LOGIC CALL STACK. cmdCall saves ip/code/logic-number, runs the
* callee, and restores them; here the callee's bytes are res_open'd above the caller's and
* res_close'd after, so the caller's code is still resident and still at the same address.
* ★ That is what P1.3's 12 KB arena was sized for: working set 4,679-8,537 B at depth 2-3.
* ═══════════════════════════════════════════════════════════════════════════════════

* vm_bind_logic: A = logic number. res_open it and point vm_code/vm_codelen at its BYTECODE.
* ★ A LOGIC resource is `u16 bytecode size (LITTLE-endian)` then the bytecode; the message
* section follows and is not executable. Pointing vm_code at the resource base instead of
* base+2 would interpret the size field as two opcodes.
vm_bind_logic:
                ldb     #RES_LOGIC
                exg     a,b                     ; A = type, B = index
                jsr     res_open
                lda     res_err
                lbne    vm_res_fail
                ldx     res_base
                ldb     ,x                      ; LITTLE-endian low byte
                lda     1,x
                std     vm_codelen
* ★ A SEPARATE, UNRESTORED COPY FOR DIAGNOSIS. vm_call_logic restores vm_codelen on the way out,
* so a probe reading it after the call sees the CALLER's value -- the first diagnostic reported
* codelen=0 and I nearly went looking for a broken bind. It was measuring the unwind [L-56].
                std     vm_lastlen
                leax    2,x
                stx     vm_code
                rts

vm_lastlen      fdb     0

* ★ THE HALT NAMES WHICH RESOURCE FAILURE, not just "a resource failure". $F0 | res_err, so
* $F1 empty slot, $F2 bad signature, $F3 out of range, $F4 too big for the arena, $F5 arena
* full, $F6 max depth. The first version reported a bare $FE and I could not tell a staging
* miss from an arena overflow -- the halt was loud and uninformative, which is half a gate.
vm_res_fail:
                lda     res_err
                ora     #$F0
                sta     vm_badop
                lda     vm_curlogic
                sta     vm_badlogic
                lda     #1
                sta     vm_quit
                sta     vm_exitall
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ TWO ENTRY POINTS, AND THE DIFFERENCE IS retflag. In the reference, run_logic's result is
* a RETURN VALUE: cmdCall ignores it, and the cycle's `while run_logic(0) == 0` uses it. Here it
* is a byte, so who restores it is a real decision:
*
*   vm_call_logic   -- cmdCall. RESTORES retflag, because a callee's `return` must not still be
*                      showing when the CALLER later falls off its own end.
*   vm_call_logic0  -- the cycle's own invocation of logic.0. Does NOT restore it, because that
*                      value is exactly what the cycle is asking for.
*
* ★★ Both were the same routine at first and the cycle read the restored value: logic.0 executed
* its `return`, retflag went to 1, the unwind put 0 back, and the cycle re-ran logic.0 forever.
* The guard caught it as "$FD -- logic.0 never returned", which was true and pointed one layer
* away from the cause. ★ The diagnostic that settled it was lastop=$00 -- a `return` HAD run.
* ★★★ THE keepret FLAG LIVES ON THE STACK, NOT IN A GLOBAL. It was a global set at entry and
* read at exit -- and a nested cmdCall between those two points overwrote it. So logic.0's own
* unwind read the NESTED call's flag (1, "restore"), threw away logic.0's `return`, and the
* cycle re-ran logic.0 for ever. ★★ The trace is what named it: `3893 00 0` -- logic.0 DID
* execute its return opcode, so the fault had to be between run_logic setting retflag and the
* cycle reading it. **Any per-invocation value in a recursive routine belongs in the frame; a
* global is per-routine, not per-call, and the distinction only bites once nesting exists.**
* ★ A holds the logic number and B is free, so B carries the flag into the shared body.
vm_call_logic0:
                clrb                            ; 0 = keep the callee's retflag (the cycle)
                bra     vm_call_body
vm_call_logic:
                ldb     #1                      ; 1 = restore the caller's (cmdCall)
vm_call_body:
                pshs    b                       ; the frame's own keepret
                pshs    a
                ldd     vm_ip
                pshs    d
                ldd     vm_code
                pshs    d
                ldd     vm_codelen
                pshs    d
                lda     vm_retflag
                pshs    a                       ; ★ per-invocation; see vm_run_logic's comment
                lda     vm_curlogic
                pshs    a
* frame: ,s=curlogic 1,s=retflag 2,s=codelen 4,s=code 6,s=ip 8,s=nr 9,s=keepret
                lda     8,s
                sta     vm_curlogic
                jsr     vm_bind_logic
                lda     vm_quit
                bne     vm_call_unwind
                jsr     vm_run_logic
                jsr     res_close
vm_call_unwind:
                puls    a
                sta     vm_curlogic
                puls    a                       ; the caller's saved retflag
* ★ 7,s: two bytes have been popped, so nr is at 6,s and this frame's keepret at 7,s.
                tst     7,s
                beq     vm_cu_keep              ; the cycle's call: leave the callee's result
                sta     vm_retflag
vm_cu_keep:
                puls    d
                std     vm_codelen
                puls    d
                std     vm_code
                puls    d
                std     vm_ip
                leas    2,s                     ; the logic number and the keepret flag
                rts

* ★ load.logic / load.view are set membership in the reference; the diff never reads those
* sets. They are IMPLEMENTED rather than modelled because load_logic has a real effect in the
* reference (it makes the logic fetchable) and dropping them would be an undeclared divergence.
vm_mark_logic:  rts
vm_mark_view:   rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── VIEW metadata ─────────────────────────────────────────────────────────────────
*
* ★★ ONLY THE HEADER IS PARSED -- loop count, cel count, cel width and height. The pixel
* unpack (RLE, mirroring) is view.cpp's and is not needed: nothing the state diff compares
* depends on a pixel, and set_view/set_loop/set_cel need only these four numbers.
*
* Layout [view.py decode_view]:
*     +2            loop count
*     +5 + n*2      loop offset n, LITTLE-endian
*     loop+0        cel count for that loop
*     loop+1 + m*2  cel offset m, LITTLE-endian, RELATIVE TO THE LOOP
*     cel+0/+1      width / height
* ★ The cel offset is relative to the LOOP, not to the resource. Adding it to the wrong base
* yields a plausible width and height from the middle of the pixel data.
* ═══════════════════════════════════════════════════════════════════════════════════

* vm_view_open: A = view number -> vm_vwbase, or halts.
vm_view_open:
                ldb     #RES_VIEW
                exg     a,b
                jsr     res_open
                lda     res_err
                lbne    vm_res_fail
                ldx     res_base
                stx     vm_vwbase
                rts
vm_view_close:  jmp     res_close

* vm_le16: X -> two little-endian bytes; returns D
vm_le16:        ldb     ,x
                lda     1,x
                rts

* vm_loop_ptr: A = loop number -> X = pointer to that loop's header
vm_loop_ptr:
                tfr     a,b
                clra
                aslb
                rola                            ; D = n*2
                addd    #5
                addd    vm_vwbase
                tfr     d,x
                jsr     vm_le16                 ; D = loop offset (relative to the resource)
                addd    vm_vwbase
                tfr     d,x
                rts

* ── set_view / set_loop / set_cel ────────────────────────────────────────────────
* ★ set_view walks into set_loop walks into set_cel; that chain is what gives an object its
* size and clamps its y. Assigning obj.view alone would leave xSize/ySize stale.
* in: X -> object, A = view number
vm_set_view:
                pshs    x
                sta     ,-s                     ; the view number
                jsr     vm_view_open
                lda     ,s+
                ldx     ,s
                sta     VMO_VIEW,x
                ldy     vm_vwbase
                lda     2,y                     ; loop count
                sta     VMO_NUMLOOPS,x
                lda     VMO_LOOP,x
                cmpa    VMO_NUMLOOPS,x
                blo     vm_sv_keep              ; UNSIGNED [L-40]
                clra                            ; loop >= numLoops -> set_loop(0)
vm_sv_keep:
                jsr     vm_set_loop_open        ; the view is already open
                puls    x
                jmp     vm_view_close

* in: X -> object, A = loop number.  Opens the object's view, then delegates.
vm_set_loop:
                pshs    x
                sta     ,-s
                lda     VMO_VIEW,x
                jsr     vm_view_open
                lda     ,s+
                ldx     ,s
                jsr     vm_set_loop_open
                puls    x
                jmp     vm_view_close

* in: X -> object, A = loop number, view already open
vm_set_loop_open:
                tst     VMO_NUMLOOPS,x
                beq     vm_slo_out              ; numLoops == 0: the oracle warns, no state change
                cmpa    VMO_NUMLOOPS,x
                blo     vm_slo_ok
                lda     VMO_NUMLOOPS,x          ; ★ the oracle CLIPS rather than erroring
                deca
vm_slo_ok:
                sta     VMO_LOOP,x
                pshs    a,x
                jsr     vm_loop_ptr             ; X -> the loop header
                lda     ,x                      ; cel count
                puls    b,x                     ; B = loop nr (discarded), X = object
                sta     VMO_NUMCELS,x
                lda     VMO_CEL,x
                cmpa    VMO_NUMCELS,x
                blo     vm_slo_cel
                clra
vm_slo_cel:     jsr     vm_set_cel_open
vm_slo_out:     rts

* in: X -> object, A = cel number
vm_set_cel:
                pshs    x
                sta     ,-s
                lda     VMO_VIEW,x
                jsr     vm_view_open
                lda     ,s+
                ldx     ,s
                jsr     vm_set_cel_open
                puls    x
                jmp     vm_view_close

* in: X -> object, A = cel number, view already open
vm_set_cel_open:
                tst     VMO_NUMLOOPS,x
                beq     vm_sco_out
                tst     VMO_NUMCELS,x
                beq     vm_sco_out              ; the oracle warns and returns
                cmpa    VMO_NUMCELS,x
                blo     vm_sco_ok
                lda     VMO_NUMCELS,x           ; ★ the oracle clips (KQ3 Apple IIgs, Bug #5832)
                deca
vm_sco_ok:
                sta     VMO_CEL,x
                sta     vm_celnr
                pshs    x
                lda     VMO_LOOP,x
                jsr     vm_loop_ptr             ; X -> loop header
                stx     vm_vtmp                 ; keep the LOOP base: cel offsets are relative
                lda     vm_celnr
                tfr     a,b
                clra
                aslb
                rola
                addd    #1
                addd    vm_vtmp
                tfr     d,x
                jsr     vm_le16                 ; D = cel offset, RELATIVE TO THE LOOP
                addd    vm_vtmp
                tfr     d,x                     ; X -> the cel header
                lda     ,x                      ; width
                ldb     1,x                     ; height
                puls    x
                sta     VMO_XSIZE,x
                stb     VMO_YSIZE,x
                jsr     vm_clip_view
vm_sco_out:     rts

* ── clip_view_coordinates [objects.py] ───────────────────────────────────────────
vm_clip_view:
                lda     VMO_X,x
                adda    VMO_XSIZE,x
                cmpa    #SCRIPT_WIDTH
                bls     vm_cv_y                 ; x + xSize <= 160
                ldd     #fUpdatePos
                jsr     vm_objflags_set
                lda     #SCRIPT_WIDTH
                suba    VMO_XSIZE,x
                sta     VMO_X,x
vm_cv_y:
* y - ySize + 1 < 0  <=>  y < ySize - 1  <=>  y + 1 < ySize
                lda     VMO_Y,x
                inca
                cmpa    VMO_YSIZE,x
                bhs     vm_cv_hz
                ldd     #fUpdatePos
                jsr     vm_objflags_set
                lda     VMO_YSIZE,x
                deca
                sta     VMO_Y,x
vm_cv_hz:
                lda     VMO_Y,x
                cmpa    vm_horizon
                bhi     vm_cv_out
                ldd     VMO_FLAGS,x
                bitb    #fIgnoreHorizon
                bne     vm_cv_out
                ldd     #fUpdatePos
                jsr     vm_objflags_set
                lda     vm_horizon
                inca
                sta     VMO_Y,x
vm_cv_out:      rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── new_room ──────────────────────────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
vm_new_room:
                sta     vm_roomnr
* ★★★ THE CACHE'S ONLY INVALIDATION POINT. The reference never invalidates `_logic_cache` --
* new_room clears the `loaded_*` residency SETS, which are a different thing. We clear here to
* keep the cache inside a 24 KB arena, and AD-88 measured that choice as behaviourally free:
* reference clearing-on-new_room vs never-clearing is byte-identical over 300 cycles on three
* titles. ★ Placed FIRST so nothing below can allocate before the reset.
                pshs    a
                jsr     res_cache_reset
                puls    a
                ldx     #VM_OBJ
                ldb     #VM_OBJ_MAX
vm_nr_lp:       pshs    b
                ldd     #fAnimated+fDrawn
                jsr     vm_objflags_clr
                ldd     #fUpdate
                jsr     vm_objflags_set
                lda     #1
                sta     VMO_STEPTIME,x
                sta     VMO_STEPTIMECNT,x
                sta     VMO_CYCLETIME,x
                sta     VMO_CYCLETIMECNT,x
                sta     VMO_STEPSIZE,x
                leax    VMO_SIZE,x
                puls    b
                decb
                bne     vm_nr_lp

                lda     #1
                sta     vm_playerctl
                clr     vm_blk_on
                lda     #36
                sta     vm_horizon

                lda     #VAR_CURRENT_ROOM
                jsr     vm_getvar
                tfr     a,b
                lda     #VAR_PREVIOUS_ROOM
                jsr     vm_setvar
                lda     #VAR_CURRENT_ROOM
                ldb     vm_roomnr
                jsr     vm_setvar
                lda     #VAR_BORDER_TOUCH_OBJECT
                clrb
                jsr     vm_setvar
                lda     #VAR_BORDER_CODE
                clrb
                jsr     vm_setvar
                clra
                jsr     vm_obj                  ; the ego
                ldb     VMO_VIEW,x
                lda     #VAR_EGO_VIEW_RESOURCE
                jsr     vm_setvar

* ★ load_logic(room_nr) here is a RESOURCE bind in the reference, and its only diffable effect
* is membership. The room's logic is bound by the cycle, not here.
                lda     #VAR_BORDER_TOUCH_EGO
                jsr     vm_getvar
                sta     vm_touch
                clra
                jsr     vm_obj
                lda     vm_touch
                cmpa    #1
                bne     vm_nr_t2
                lda     #SCRIPT_HEIGHT-1
                sta     VMO_Y,x
                bra     vm_nr_tdone
vm_nr_t2:       cmpa    #2
                bne     vm_nr_t3
                clr     VMO_X,x
                bra     vm_nr_tdone
vm_nr_t3:       cmpa    #3
                bne     vm_nr_t4
                lda     vm_horizon
                inca
                sta     VMO_Y,x
                bra     vm_nr_tdone
vm_nr_t4:       cmpa    #4
                bne     vm_nr_tdone
                lda     #SCRIPT_WIDTH
                suba    VMO_XSIZE,x
                sta     VMO_X,x
vm_nr_tdone:
* ★ the version >= 0x3000 ego-motion reset is NOT reached: the pin is 0x2917.
                lda     #VAR_BORDER_TOUCH_EGO
                clrb
                jsr     vm_setvar
                lda     #FLAG_NEW_ROOM_EXEC
                ldb     #1
                jsr     vm_setflag
                lda     #1
                sta     vm_exitall
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── motion: the measured subset ───────────────────────────────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
* ★ _ACTIVE = fAnimated | fUpdate | fDrawn, and the gate is stepTimeCount == 1 EXACTLY, not <=.
VM_MOT_ACTIVE_L equ     fAnimated+fUpdate+fDrawn        ; $51 -- all three bits are in the LOW byte

vm_check_all_motions:
                ldx     #VM_OBJ
                ldb     #VM_OBJ_MAX
vm_cam_lp:      pshs    b
                lda     VMO_FLAGS+1,x
                anda    #VM_MOT_ACTIVE_L
                cmpa    #VM_MOT_ACTIVE_L
                bne     vm_cam_next
                lda     VMO_STEPTIMECNT,x
                cmpa    #1
                bne     vm_cam_next             ; ★ EXACTLY 1
                jsr     vm_check_motion
vm_cam_next:    leax    VMO_SIZE,x
                puls    b
                decb
                bne     vm_cam_lp
                rts

* in: X -> object
vm_check_motion:
                lda     VMO_MOTION,x
                beq     vm_cm_blocks            ; kMotionNormal: nothing
                cmpa    #kMotionMoveObj
                beq     vm_cm_move
                cmpa    #kMotionEgo
                beq     vm_cm_move
                cmpa    #kMotionWander
                beq     vm_cm_wander
                cmpa    #kMotionFollowEgo
                beq     vm_cm_follow
* ★★★ AC-4: an unmodelled mode HALTS. The oracle's `default:` falls through silently; a mode we
* do not model produces a divergence the state diff cannot attribute, so it is loud here.
* ★★ WANDER AND FOLLOW.EGO USED TO LAND HERE, on the strength of "vm_motion_which.py measured
* that the gated set never reaches them". The measurement was true and the SET was smaller than
* the claim: BlackCauldron reaches kMotionWander at cycle 225 and halted with badop=$01. **A
* measured absence is an absence in the thing measured** -- 2H, and the loud halt is what turned
* it into a fact rather than a drift. Both modes are implemented below; this default remains.
                sta     vm_badop
                lda     vm_curlogic
                sta     vm_badlogic
                lda     #1
                sta     vm_quit
                sta     vm_exitall
                rts
vm_cm_move:     jsr     vm_motion_move_obj
                bra     vm_cm_blocks
vm_cm_wander:   jsr     vm_motion_wander
                bra     vm_cm_blocks
vm_cm_follow:   jsr     vm_motion_follow_ego
vm_cm_blocks:
* ★ change_pos runs only when a block is set AND the object does not ignore blocks AND it has a
* direction. vm_motion_which.py measured zero calls in the gated set; the guard is reproduced
* so the absence stays a measurement rather than an omission.
                tst     vm_blk_on
                beq     vm_cm_out
                ldd     VMO_FLAGS,x
                bitb    #fIgnoreBlocks
                bne     vm_cm_out
                lda     VMO_DIR,x
                beq     vm_cm_out
                sta     vm_badop                ; change_pos is NOT implemented -- halt, loudly
                lda     #1
                sta     vm_quit
                sta     vm_exitall
vm_cm_out:      rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── motion_wander [motion.py motion_wander] ──────────────────────────────────────
* in: X -> object.  ★ X is preserved across every call below, by pshs/puls at each site.
*
* ★★★ THE `while wander_count < 6` IS A RETRY LOOP, NOT A CLAMP, and that distinction is the
* whole reason this cannot be approximated. It re-rolls until the value is >= 6, so it consumes
* the generator a VARIABLE number of times. `max(6, roll)` would give the same wander_count and
* a different RNG stream -- and the stream is shared with the random() opcode, so the damage
* surfaces later, in another title, as an unrelated variable. motion.py says so in as many words.
*
* ★★ THIS IS ALSO WHY THE MODES HAD TO BE IMPLEMENTED RATHER THAN SUPPRESSED. Two draws here
* shift every subsequent random() result; there is no version of "skip wander" that keeps the
* diff meaningful.
* ═══════════════════════════════════════════════════════════════════════════════════
vm_motion_wander:
                lda     VMO_WANDERCNT,x
                sta     vm_mwcnt                ; `original`, before the decrement
                deca
                sta     VMO_WANDERCNT,x         ; (count - 1) & 0xFF -- a byte, so it wraps
* re-roll when original == 0 OR the object did not move
                tst     vm_mwcnt
                beq     vm_mw_roll
                lda     VMO_FLAGS,x
                bita    #fDidntMove_H
                beq     vm_mw_out
vm_mw_roll:
                pshs    x
                lda     #8
                jsr     vm_rnd                  ; direction = get_random_number(8)
                ldx     ,s
                sta     VMO_DIR,x
                jsr     vm_is_ego
                tsta
                beq     vm_mw_notego
                ldx     ,s
                ldb     VMO_DIR,x
                lda     #VAR_EGO_DIRECTION
                jsr     vm_setvar
vm_mw_notego:
* ★ the retry loop, verbatim: while wander_count < 6: wander_count = rnd(50)
vm_mw_lp:       ldx     ,s
                lda     VMO_WANDERCNT,x
                cmpa    #6
                bhs     vm_mw_done
                lda     #50
                jsr     vm_rnd
                ldx     ,s
                sta     VMO_WANDERCNT,x
                bra     vm_mw_lp
vm_mw_done:     puls    x
vm_mw_out:      rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── motion_follow_ego [motion.py motion_follow_ego] ──────────────────────────────
* in: X -> object
*
* ★ Both inner loops are retries and both consume the generator a variable number of times, for
* the same reason as wander: `while direction == 0: direction = rnd(8)` and
* `while follow_count < stepSize: follow_count = rnd(d)`.
* ★★ follow_count's decrement is stored into a BYTE and then tested AS SIGNED -- motion.py
* spells this out: "a straight max(0, k) is not the same expression for k in 128..255 after
* wrap". Reproduced as the byte-then-signed-test it is.
* ═══════════════════════════════════════════════════════════════════════════════════
vm_motion_follow_ego:
                pshs    x
* obj_x = obj.x + obj.xSize/2 ; obj_y = obj.y
                lda     VMO_XSIZE,x
                lsra
                adda    VMO_X,x
                sta     vm_fobjx
                lda     VMO_Y,x
                sta     vm_fobjy
* ego_x = ego.x + ego.xSize/2 ; ego_y = ego.y
                ldx     #VM_OBJ                 ; ★ the ego is entry 0
                lda     VMO_XSIZE,x
                lsra
                adda    VMO_X,x
                sta     vm_fegox
                lda     VMO_Y,x
                sta     vm_fegoy
                ldx     ,s
* direction = get_direction(obj_x, obj_y, ego_x, ego_y, follow_stepSize)
                lda     VMO_FOLLOWSTEP,x
                sta     vm_css
                clra
                ldb     vm_fobjx
                pshs    d
                clra
                ldb     vm_fegox
                subd    ,s++                    ; ★ 16-bit: see vm_check_step
                jsr     vm_check_step
                sta     vm_cs_x
                clra
                ldb     vm_fobjy
                pshs    d
                clra
                ldb     vm_fegoy
                subd    ,s++
                jsr     vm_check_step
                ldb     #3
                mul
                addb    vm_cs_x
                ldx     #vm_dir_table
                lda     b,x
                sta     vm_fdir
                ldx     ,s
                tst     vm_fdir
                bne     vm_fe_moving
* ---- arrived: direction 0, back to normal, and the COMPLETION FLAG ----------------
                clr     VMO_DIR,x
                clr     VMO_MOTION,x            ; kMotionNormal
                lda     VMO_FOLLOWFLAG,x
                ldb     #1
                jsr     vm_setflag
                puls    x
                rts
vm_fe_moving:
                lda     VMO_FOLLOWCNT,x
                cmpa    #$FF
                bne     vm_fe_notinit
                clr     VMO_FOLLOWCNT,x
                puls    x
                rts
vm_fe_notinit:
                lda     VMO_FLAGS,x
                bita    #fDidntMove_H
                beq     vm_fe_count
* ---- stuck: re-roll a NON-ZERO direction, then a follow_count >= stepSize ---------
vm_fe_dirlp:    lda     #8
                jsr     vm_rnd
                ldx     ,s
                sta     VMO_DIR,x
                tsta
                beq     vm_fe_dirlp             ; ★ retry until non-zero: a variable draw count
* d = (|ego_y - obj_y| + |ego_x - obj_x|) / 2
* ★ 16-bit for the same reason as check_step: each difference is -167..167 and their sum is not
* a byte quantity either. `coma/comb/addd #1` is the 16-bit negate the 6809 does not have.
                clra
                ldb     vm_fobjy
                pshs    d
                clra
                ldb     vm_fegoy
                subd    ,s++
                bpl     vm_fe_dy
                coma
                comb
                addd    #1
vm_fe_dy:       std     vm_ftmp
                clra
                ldb     vm_fobjx
                pshs    d
                clra
                ldb     vm_fegox
                subd    ,s++
                bpl     vm_fe_dx
                coma
                comb
                addd    #1
vm_fe_dx:       addd    vm_ftmp
                lsra
                rorb
                stb     vm_fd                   ; d <= 163, so the low byte is the whole answer
* if d < stepSize: follow_count = stepSize; return
                lda     VMO_STEPSIZE,x
                cmpa    vm_fd
                bls     vm_fe_cntlp
                sta     VMO_FOLLOWCNT,x
                puls    x
                rts
vm_fe_cntlp:    lda     vm_fd
                jsr     vm_rnd
                ldx     ,s
                sta     VMO_FOLLOWCNT,x
                cmpa    VMO_STEPSIZE,x
                blo     vm_fe_cntlp             ; ★ retry until >= stepSize
                puls    x
                rts
* ---- moving normally: count down, or steer ---------------------------------------
vm_fe_count:
                lda     VMO_FOLLOWCNT,x
                beq     vm_fe_steer
                suba    VMO_STEPSIZE,x          ; stored as a byte, then tested as SIGNED
                sta     VMO_FOLLOWCNT,x
                cmpa    #$80
                blo     vm_fe_fdone             ; k <= 127: keep it
                clr     VMO_FOLLOWCNT,x         ; k > 127 means it went negative -- zero
vm_fe_fdone:    puls    x
                rts
vm_fe_steer:    lda     vm_fdir
                sta     VMO_DIR,x
                puls    x
                rts

* vm_rnd: A = maximum -> A = get_random_number(A).  ★ One home for "set rndmax, then draw":
* motion has four call sites and vmop_random a fifth, and the state diff depends on every one
* of them advancing the SAME generator in the SAME order.
vm_rnd:
                sta     vm_rndmax
                jmp     vm_rnd_next

vm_mwcnt        fcb     0
vm_fobjx        fcb     0
vm_fobjy        fcb     0
vm_fegox        fcb     0
vm_fegoy        fcb     0
vm_fdir         fcb     0
vm_fd           fcb     0
vm_ftmp         fdb     0                       ; ★ 16-bit

* ── motion_move_obj [motion.py] ──────────────────────────────────────────────────
* in: X -> object
vm_motion_move_obj:
                pshs    x
* ★★ THE DELTAS ARE 16-BIT. `lda dest / suba pos` is a byte subtract and dest-pos ranges over
* -167..167; the wrap flipped both classifications and produced the OPPOSITE direction. See
* vm_check_step's header -- this is the call site that found it.
                lda     VMO_STEPSIZE,x
                sta     vm_css
                clra
                ldb     VMO_X,x
                pshs    d
                clra
                ldb     VMO_MOVEX,x
                subd    ,s++                    ; D = move_x - x, 16-bit SIGNED
                jsr     vm_check_step           ; A = 0/1/2
                sta     vm_cs_x
                clra
                ldb     VMO_Y,x
                pshs    d
                clra
                ldb     VMO_MOVEY,x
                subd    ,s++                    ; D = move_y - y
                jsr     vm_check_step
* index = check_step(dx) + 3*check_step(dy)
                ldb     #3
                mul                             ; D = 3 * check_step(dy)
                addb    vm_cs_x
                ldx     #vm_dir_table
                lda     b,x
                puls    x
                sta     VMO_DIR,x
                pshs    x
                jsr     vm_is_ego
                tsta
                beq     vm_mmo_notego
                ldx     ,s
                ldb     VMO_DIR,x
                lda     #VAR_EGO_DIRECTION
                jsr     vm_setvar
vm_mmo_notego:
                puls    x
                lda     VMO_DIR,x
                bne     vm_mmo_out
                jsr     vm_motion_move_obj_stop
vm_mmo_out:     rts

* ── motion_move_obj_stop ─────────────────────────────────────────────────────────
vm_motion_move_obj_stop:
                lda     VMO_MOVESTEP,x
                sta     VMO_STEPSIZE,x
* ★ the oracle checks motionType != kMotionEgo before setting the flag, and says the original
* only did this in AGI3 -- it applies the check in all versions because kMotionEgo is reused
* for mouse movement. Transcribed as the oracle has it, not as the Specs describe it.
                lda     VMO_MOTION,x
                cmpa    #kMotionEgo
                beq     vm_mms_nofl
                pshs    x
                lda     VMO_MOVEFLAG,x
                ldb     #1
                jsr     vm_setflag              ; ★ the completion flag
                puls    x
vm_mms_nofl:
                clr     VMO_MOTION,x            ; kMotionNormal
                pshs    x
                jsr     vm_is_ego
                tsta
                beq     vm_mms_out
                lda     #1
                sta     vm_playerctl
                lda     #VAR_EGO_DIRECTION
                clrb
                jsr     vm_setvar
vm_mms_out:     puls    x
                rts

* vm_is_ego: X -> object -> A = 1 if it is screen object 0
vm_is_ego:
                cmpx    #VM_OBJ
                bne     vm_ie_no
                lda     #1
                rts
vm_ie_no:       clra
                rts

* ── check_step(delta, step) [motion.py] ──────────────────────────────────────────
* if -step >= delta: 0 ; if step <= delta: 2 ; else 1
*
* ★★★ delta IS 16-BIT SIGNED AND IT HAS TO BE. It was a signed BYTE, and a coordinate
* difference does not fit one: y runs to 167, so `20 - 167 = -147` wraps to +109 and the
* classification comes out 2 where the truth is 0. ★★ Both axes invert together, so the
* DIR_TABLE index goes from 2 to 6 -- **exactly the opposite direction** -- and SpaceQuest-2's
* object 1 walked into the bottom border instead of away from it. The state diff called that
* "var 4 = 1, var 5 = 3", two steps removed from the arithmetic.
*
* ★ THIRD INSTANCE OF ONE CLASS IN THIS TASK: the position pass held x/y in bytes, this held
* the deltas in bytes, and follow.ego's distance did too. **A coordinate fits a byte; a
* difference of two coordinates does not.** L-40 named the signed/unsigned half of this; the
* WIDTH half is the same trap one step along.
*
* in: D = delta (SIGNED 16-bit), vm_css = step (0..255) -> A = 0/1/2
* ★ Expressed as `delta + step <= 0` and `delta - step >= 0` so both are plain 16-bit signed
* compares; delta is -255..255 and step 0..255, so neither intermediate can overflow.
vm_check_step:
                std     vm_csd
                clra
                ldb     vm_css
                std     vm_cstep                ; step, zero-extended: always non-negative
                ldd     vm_csd
                addd    vm_cstep
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ AC-3's INJECTED FAULT LIVES HERE, BEHIND -DVM_FAULT, AND IT IS DELIBERATELY SUBTLE.
*
* A gate is only evidence if it can FAIL. `ble` -> `blt` moves ONE boundary by ONE: the case
* delta == -step, which the reference classifies as 0 and the faulted build classifies as 1.
* Nothing halts, no assertion fires, no screenshot looks wrong -- an object simply steps when it
* should have stopped, on the exact frame it reaches its destination.
*
* ★★ THIS IS CLAUDE.md 2I's ARGUMENT MADE EXECUTABLE. "An AGI interpreter can look perfect and
* be wrong": the faulted build renders identically and diverges in state. If the gate catches a
* one-boundary error in a routine called a few times per cycle, it is measuring behaviour and
* not appearance.
* ★ Guarded, so the gated build carries none of it, and NAMED, so a green run with VM_FAULT set
* would itself be the finding.
                ifdef   VM_FAULT
                blt     vm_cs_0                 ; ★ INJECTED FAULT: `ble` in the correct build
                else
                ble     vm_cs_0                 ; SIGNED: delta + step <= 0  <=>  -step >= delta
                endc
                ldd     vm_csd
                subd    vm_cstep
                bge     vm_cs_2                 ; SIGNED: delta - step >= 0  <=>  step <= delta
                lda     #1
                rts
vm_cs_0:        clra
                rts
vm_cs_2:        lda     #2
                rts
vm_cstep        fdb     0

* DIR_TABLE, 9 entries, generated from the pinned oracle [optable.py:369]
vm_dir_table    equ     VMT_DIR_TABLE           ; ★ generated, not typed (L-29)

* ── motion_activated / cycler_activated ──────────────────────────────────────────
* ★ The two cycler/motion interaction workarounds. §2.1 deviations in ScummVM, reproduced
* because the diff compares against ScummVM.
vm_motion_activated:
                ldd     VMO_FLAGS,x
                bitb    #fCycling
                beq     vm_ma_out
                lda     VMO_CYCLE,x
                cmpa    #kCycleEndOfLoop
                beq     vm_ma_set
                cmpa    #kCycleRevLoop
                bne     vm_ma_out
vm_ma_set:      lda     #1
                sta     VMO_IGNLOOPFLAG,x
vm_ma_out:      rts

vm_cycler_activated:
                lda     VMO_MOTION,x
                cmpa    #kMotionWander
                bne     vm_ca_follow
                ldb     VMO_LOOPFLAG,x
                stb     VMO_WANDERCNT,x
                rts
vm_ca_follow:   cmpa    #kMotionFollowEgo
                bne     vm_ca_move
                ldb     VMO_LOOPFLAG,x
                stb     VMO_FOLLOWSTEP,x
                rts
vm_ca_move:     cmpa    #kMotionMoveObj
                bne     vm_ca_out
                ldb     VMO_LOOPFLAG,x
                stb     VMO_MOVEX,x
vm_ca_out:      rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── the RNG: ScummVM's Common::RandomSource, 32-bit ───────────────────────────────
*
* ★★★ REPRODUCED BIT FOR BIT, and §2.1 applies: this is SCUMMVM's generator, not Sierra's. It
* exists so the state diff is meaningful for the 252 random() calls in the gated set. The
* shipped interpreter is free to use its own, and that will be a stated divergence.
*
* common/random.cpp: xorshift (>>13, <<21, >>11), then (seed * 0xDEADBF03) % (max + 1).
* ═══════════════════════════════════════════════════════════════════════════════════
vm_seed         fcb     $00,$00,$30,$39         ; 12345, big-endian in memory
vm_acc          rmb     4
vm_mul          fcb     $DE,$AD,$BF,$03

* seed ^= seed >> 13  (32-bit, big-endian bytes at vm_seed)
vm_rnd_next:
                lda     #13
                jsr     vm_shr32
                jsr     vm_xor32
                lda     #21
                jsr     vm_shl32
                jsr     vm_xor32
                lda     #11
                jsr     vm_shr32
                jsr     vm_xor32
* acc = seed * 0xDEADBF03, low 32 bits
                jsr     vm_mul32
* result = acc % (rndmax + 1)
                jmp     vm_mod32

* vm_shr32: vm_acc = vm_seed >> A  (logical)
vm_shr32:
                sta     vm_shcnt
                ldx     #vm_seed
                ldu     #vm_acc
                ldd     ,x
                std     ,u
                ldd     2,x
                std     2,u
vm_shr_lp:      lda     vm_shcnt
                beq     vm_shr_out
                lsr     vm_acc
                ror     vm_acc+1
                ror     vm_acc+2
                ror     vm_acc+3
                dec     vm_shcnt
                bra     vm_shr_lp
vm_shr_out:     rts

* vm_shl32: vm_acc = vm_seed << A
vm_shl32:
                sta     vm_shcnt
                ldx     #vm_seed
                ldu     #vm_acc
                ldd     ,x
                std     ,u
                ldd     2,x
                std     2,u
vm_shl_lp:      lda     vm_shcnt
                beq     vm_shl_out
                asl     vm_acc+3
                rol     vm_acc+2
                rol     vm_acc+1
                rol     vm_acc
                dec     vm_shcnt
                bra     vm_shl_lp
vm_shl_out:     rts

* vm_xor32: vm_seed ^= vm_acc
vm_xor32:
                ldx     #vm_seed
                ldu     #vm_acc
                ldb     #4
vm_xor_lp:      lda     ,x
                eora    ,u+
                sta     ,x+
                decb
                bne     vm_xor_lp
                rts

* vm_mul32: vm_acc = vm_seed * vm_mul, low 32 bits.
*
* ★★★ SHIFT-AND-ADD, REPLACING A SCHOOLBOOK VERSION THAT THREW AWAY HALF OF EVERY PARTIAL
* PRODUCT. `mul` leaves the 16-bit product in D, and that version did `addb ,x / stb ,x` -- the
* LOW byte only. A, the high byte, was destroyed two instructions later by `lda vm_mt` and never
* added anywhere. ★★ Every one of the sixteen partial products lost its top half, so the result
* was not the product of anything; the random() opcode returned its low bound and KQ3's vars 37
* and 38 sat at 39 and 77 for five hundred cycles while the oracle varied.
*
* ★★ THE SYMPTOM POINTED AT THE SEED AND THE SEED WAS FINE. The xorshift advanced correctly
* ($C8C25BA7 after 20 cycles, from 12345) -- it was the multiply that flattened it. A constant
* output from an advancing generator is a downstream fault, and the diagnostic that separated
* the two was printing the seed rather than reasoning about the arithmetic.
*
* ★ Double-and-add is ~32x slower than schoolbook and is correct by inspection. That is the
* right trade here: this routine has no build-time check, no assertion can catch it, and the
* entire state diff for every title that calls random() rests on it. Cost is AC-7's problem and
* the shipped interpreter is free to use its own generator anyway (2.1, stated above).
vm_mul32:
                clra
                clrb
                std     vm_acc
                std     vm_acc+2
                ldd     vm_mul                  ; a working copy, shifted left one bit per step
                std     vm_mwk
                ldd     vm_mul+2
                std     vm_mwk+2
                lda     #32
                sta     vm_mcnt
vm_mul_lp:
* acc <<= 1, LSB-first so the carry runs toward the MSB
                asl     vm_acc+3
                rol     vm_acc+2
                rol     vm_acc+1
                rol     vm_acc
* ★ A takes the multiplier's top byte BEFORE the shift; `lda` leaves C alone, so the asl/rol
* chain below still sees the carry it needs.
                lda     vm_mwk
                asl     vm_mwk+3
                rol     vm_mwk+2
                rol     vm_mwk+1
                rol     vm_mwk
                tsta                            ; bit 7 of the PRE-shift top byte
                bpl     vm_mul_next
* acc += seed, 32-bit, LSB-first
                ldb     vm_acc+3
                addb    vm_seed+3
                stb     vm_acc+3
                ldb     vm_acc+2
                adcb    vm_seed+2
                stb     vm_acc+2
                ldb     vm_acc+1
                adcb    vm_seed+1
                stb     vm_acc+1
                ldb     vm_acc
                adcb    vm_seed
                stb     vm_acc
vm_mul_next:
                dec     vm_mcnt
                bne     vm_mul_lp
                rts

vm_mwk          rmb     4                       ; the multiplier, consumed a bit at a time
vm_mcnt         fcb     0

* vm_mod32: A = vm_acc % (vm_rndmax + 1)
* ★ The divisor is at most 256. Processing MSB->LSB with an 8-bit running remainder keeps every
* intermediate under 65,536, so a 16/8 divide is exact and no 32-bit division is needed.
* ★★ rndmax == 255 means a divisor of 256, where the answer is just the low byte -- and a
* 16/8 loop with divisor 256 would not terminate, so it is special-cased rather than trusted.
vm_mod32:
                lda     vm_rndmax
                cmpa    #$FF
                bne     vm_mod_gen
                lda     vm_acc+3
                rts
vm_mod_gen:
                inca
                sta     vm_divisor              ; divisor = rndmax + 1, 1..255
                clr     vm_rem
                ldx     #vm_acc
                ldb     #4
vm_mod_byte:    pshs    b
                lda     vm_rem
                ldb     ,x+
                pshs    x
                jsr     vm_div16by8             ; D = rem:byte -> B = remainder
                puls    x
                stb     vm_rem
                puls    b
                decb
                bne     vm_mod_byte
                ldb     vm_rem
                tfr     b,a
                rts

* vm_div16by8: D / vm_divisor -> B = remainder.  Restoring shift-subtract, SIXTEEN iterations.
*
* ★★★ IT RAN EIGHT, AND A 16-BIT DIVIDEND HAS SIXTEEN BITS. Eight iterations walk the HIGH byte
* through the remainder and leave the LOW byte's eight bits sitting in the stack slot, never
* shifted in. ★★ In vm_mod32 the high byte entering each step is the running remainder, which
* is already < divisor -- so eight iterations reduced a value that needed no reducing and
* discarded the byte that did. **Every byte returned 0, so acc % (max+1) was 0 for every input
* and random() returned its low bound exactly.** KQ3's var 36 came out 1 where the reference
* said 4, and the `if` on the next line took the other branch.
*
* ★ THE ARITHMETIC WAS RIGHT UP TO HERE AND THAT IS WHY IT TOOK THREE MEASUREMENTS. The seed
* trajectory was correct (found at draw 19 of the reference's own sequence), and the 32-bit
* product matched bit for bit ($C8C25BA7 * $DEADBF03 = $1E83ABF5). Three routines in a chain,
* two of them right, and the symptom -- a constant random value -- looked most like the seed.
*
* ★★ THE CARRY OUT OF `rol vm_rem2` IS LOAD-BEARING at sixteen iterations. rem2 < divisor <= 255
* going in, so after the shift the true value can reach 511 and does not fit the byte. When the
* rol carries, the value is >= 256 > divisor and the subtraction is unconditional; `suba` then
* yields 256+rem2-divisor, which is < 256 because rem2 <= divisor-1. One subtract is enough.
* ★ The test has to sit IMMEDIATELY after the rol -- `cmpa` overwrites the carry.
vm_div16by8:
                pshs    a,b
                ldb     #16
                stb     vm_shcnt
                clr     vm_rem2
vm_dv_lp:       asl     1,s                     ; shift the 16-bit dividend left
                rol     ,s
                rol     vm_rem2
                bcs     vm_dv_sub               ; ★ bit 8 set: certainly >= divisor
                lda     vm_rem2
                cmpa    vm_divisor
                blo     vm_dv_next
                bra     vm_dv_sub2
vm_dv_sub:      lda     vm_rem2
vm_dv_sub2:     suba    vm_divisor
                sta     vm_rem2
vm_dv_next:     dec     vm_shcnt
                bne     vm_dv_lp
                leas    2,s
                ldb     vm_rem2
                rts

vm_shcnt        fcb     0
vm_mi           fcb     0
vm_mj           fcb     0
vm_mt           fcb     0
vm_rem          fcb     0
vm_rem2         fcb     0
vm_mdx          fcb     0
vm_mdy          fcb     0
vm_cs_x         fcb     0
vm_csd          fdb     0                       ; ★ 16-bit SIGNED delta -- see vm_check_step
vm_css          fcb     0
vm_celnr        fcb     0
vm_roomnr       fcb     0
vm_touch        fcb     0
