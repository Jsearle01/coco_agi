* A fixture for harness/tools/x_liveness.py -- the two defects it exists to find, verbatim as
* they stood in the tree, plus the two correct idioms that must NOT be reported.

* --- REAL: X held across an operand fetch (vmop_position, pre-fix) ---------------
vmop_position:  jsr     vm_obj0
                jsr     vm_p1
                sta     VMO_X,x
                rts

* --- REAL: B held across vm_obj (vm_ic_after, pre-fix) ---------------------------
vm_ic_after:    lda     #VAR_EGO_DIRECTION
                jsr     vm_getvar
                tfr     a,b
                clra
                jsr     vm_obj
                stb     VMO_DIR,x
                rts

* --- CORRECT: the pointer is stacked across the fetch ---------------------------
vmop_step_size: jsr     vm_obj0
                pshs    x
                jsr     vm_v1
                puls    x
                sta     VMO_STEPSIZE,x
                rts

* --- CORRECT: D written after the call, then stored -----------------------------
vm_st_ozero:    lda     #VAR_KEY
                clrb
                jsr     vm_setvar
                ldd     #0
                std     vm_cycle
                rts

* --- REAL: D held across a call that returns in A (cp_do_free, pre-fix) ---------
cp_do_free:     ldd     CP_N
                beq     cp_loop
                jsr     cp_setup
cp_free_lp:     pshs    d
                jsr     cp_composite
                puls    d
                subd    #1
                bne     cp_free_lp
                rts
