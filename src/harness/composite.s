* src/harness/composite.s -- the sprite composite: transparency, the priority test, save-under.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE DISPATCH'S INNER LOOP IS NOT THE ORACLE'S, AND THE DIFFERENCE IS THREE MECHANISMS.
*
* T-P0-028 §2 states the loop as: "if source != 0 and sprite priority >= priority[x>>1], write."
* The pinned oracle's SpritesMgr::drawCel (sprite.cpp:233) is:
*
*     if (curColor != celClearKey) {                       // ★ the CEL'S clear key, not 0
*         screenPriority = getPriority(curX, curY);
*         if (screenPriority <= 2) {                       // ★★★ CONTROL DATA -- a third branch
*             if (checkControlPixel(curX, curY, viewPriority))
*                 putPixel(VISUAL only, curColor, 0);      // ★ priority plane UNTOUCHED
*         } else if (screenPriority <= viewPriority) {
*             putPixel(ALL, curColor, viewPriority);       // ★ writes BOTH planes
*         }
*     }
*
* ★★ 1. PRIORITY VALUES 0-2 ARE NOT DEPTH, THEY ARE CONTROL LINES. checkControlPixel walks
*    DOWN the column from the pixel until it finds a priority > 2, and compares THAT. A pixel
*    over a control line therefore costs a loop of up to 168 iterations, which the two-test
*    model does not account for at all. Counted separately below, because AC-5 asks for the
*    cost and a mean that hides a per-pixel column scan is not the cost.
* ★★ 2. THE SPRITE WRITES THE PRIORITY SCREEN. Branch three stamps viewPriority into the
*    priority plane. So compositing MUTATES its own input, and save-under must restore BOTH
*    planes -- which is why the oracle's backing store is `xSize * ySize * 2` (sprite.cpp:131).
*    ★★★ P5.1's cost model reported "peak TOTAL cel area 4,152 B -- the save-under bound"; the
*    real bound is TWICE that, because one plane is half the state a sprite disturbs.
* ★ 3. yPos IS THE LOWER-LEFT CORNER: `curY = curY - celPtr->height + 1`. Taking it as upper
*    left puts every sprite one cel-height too low.
*
* ★★ AND THE LOOKUP IS `x`, NOT `x >> 1`. getPriority is `_priorityScreen[y * 160 + x]`. The
* design's `x >> 1` is the CoCo3 mapping from a 320-wide VISUAL plane to a 160-wide priority
* screen; the oracle composites in 160-wide space where the two already agree. This harness
* composites in the oracle's space so the gate can be byte-identical, so it uses `x`. **The
* shift is a property of the shipped framebuffer, not of the algorithm.**
* ═══════════════════════════════════════════════════════════════════════════════════════════

CO_CTRL_MAX     equ     2               ; priority <= 2 is control data, not depth

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ -DPRI_PACKED: THE PRIORITY PLANE AT 4 BITS PER PIXEL. THIS IS NOT AN OPTIMISATION.
* memmap.inc has specified 13,440 B since P6.1 and every subsystem wrote 26,880. P3b measured
* the draw phase at **72,194 bytes against 65,280 available** -- and packing saves exactly
* 13,440, which is the whole of the 6,914-byte overrun and 6,526 to spare. **Without it nothing
* integrates** [L-64: P6.1 recorded this as a divergence with a cost, which concealed that it
* was a requirement].
*
* ★★ AGI priority values are 0-15, so four bits are lossless. The plane becomes 80 x 168.
*
* ★★★ THE NIBBLE CONVENTION, STATED ONCE AND USED EVERYWHERE:
*     byte index = (y * 160 + x) >> 1  =  y * 80 + (x >> 1)
*     EVEN x -> HIGH nibble          ODD x -> LOW nibble
* ★ Left-to-right raster order, so a hex dump reads in pixel order. Six sites depend on it:
* co_rowset, co_rownext, co_opaque's read, co_depth's stamp, co_checkctrl's walk, and
* put_pixel in pic_core.s. **A convention disagreement between any two of them is a silent
* half-pixel shift**, which is why it is written here and referenced rather than re-derived.
*
* ★★ THE COST IS A NIBBLE EXTRACT ON READ AND A READ-MODIFY-WRITE ON WRITE. P5.4 measured the
* priority test at 2.7% of composite cost against the transparency test's 70.9%, so this lands
* on the cheap path -- but that was an inference and AC-4/AC-7 measure it rather than assume.
                ifdef   PRI_PACKED
PRI_STRIDE      equ     PRI_W/2         ; 80 bytes per row
                else
PRI_STRIDE      equ     PRI_W           ; 160 -- one byte per pixel, the gate's shape
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

co_rowvis       fdb     0               ; -> visual row base for curY
co_rowpri       fdb     0               ; -> priority row base for curY
co_src          fdb     0               ; -> next cel pixel
co_remh         fcb     0
co_remw         fcb     0
co_curx         fcb     0
co_basex        fcb     0
co_cury         fdb     0               ; ★ 16-bit: yPos - height + 1 can go NEGATIVE
co_prio         fcb     0
co_key          fcb     0
co_col          fcb     0
co_tmp          fdb     0
co_ctrly        fdb     0               ; checkControlPixel's walking row
co_ctrloff      fdb     0

* ★ AC-5 counters. 32-bit: a 500-frame run at ~900 tested pixels per composite passes 65,535
* in the first second, and a 16-bit counter would wrap silently into a plausible figure.
co_tested       rmb     4
co_written      rmb     4
co_rejkey       rmb     4
co_rejpri       rmb     4
co_ctrlhit      rmb     4               ; ★ pixels that took the CONTROL branch
co_ctrlstep     rmb     4               ; ★ total column-scan iterations those cost

* ═══════════════════════════════════════════════════════════════════════════════════
* ── cp_composite ── draw the decoded cel at (CP_X, CP_Y) with priority CP_PRIO ────
* ═══════════════════════════════════════════════════════════════════════════════════
cp_composite:
                lda     CP_X
                sta     co_basex
                lda     CP_PRIO
                sta     co_prio
                lda     vc_key
                sta     co_key
                lda     vc_h
                sta     co_remh
                ldd     #CP_CEL
                std     co_src

* curY = yPos - height + 1   ★ yPos is the LOWER-left corner (sprite.cpp:247)
                clra
                ldb     CP_Y
                pshs    d
                clra
                ldb     vc_h
                pshs    d
                ldd     2,s
                subd    ,s++
                leas    2,s
                addd    #1
                std     co_cury

* row bases for curY. ★ Kept as running pointers and advanced by 160 per row rather than
* recomputed as y*160: the multiply is 16-bit and the add is not, and this is the inner loop.
                ldd     co_cury
                jsr     co_rowset

                ldd     CP_BLITS
                addd    #1
                std     CP_BLITS

co_row:
                lda     co_remh
                lbeq    co_done
                lda     co_basex
                sta     co_curx
                lda     vc_w
                sta     co_remw

co_pix:
                lda     co_remw
                lbeq    co_rownext

                ldx     co_src
                lda     ,x+
                stx     co_src
                sta     co_col
                ifndef  COMP_NOCOUNT
                ldu     #co_tested
                jsr     co_inc32
                endc

                cmpa    co_key
                bne     co_opaque
                ifndef  COMP_NOCOUNT
                ldu     #co_rejkey
                jsr     co_inc32
                endc
                bra     co_nextx

co_opaque:
* screenPriority = priority[row + curX]
                ldx     co_rowpri
                clra
                ldb     co_curx
                ifdef   PRI_PACKED
* ★ byte = row + (x >> 1); EVEN x -> high nibble, ODD x -> low. See the convention block.
                lsrb                            ; A is 0, so D = x >> 1
                leax    d,x
                lda     ,x
                ldb     co_curx
                bitb    #1
                bne     co_op_lo
                lsra
                lsra
                lsra
                lsra
                bra     co_op_got
co_op_lo:       anda    #$0F
co_op_got:
                else
                leax    d,x
                lda     ,x                      ; A = screenPriority
                endc
                cmpa    #CO_CTRL_MAX
                bhi     co_depth                ; > 2: ordinary depth comparison

* ---- CONTROL DATA: walk DOWN the column for the first real priority ---------------
                ifndef  COMP_NOCOUNT
                ldu     #co_ctrlhit
                jsr     co_inc32
                endc
                jsr     co_checkctrl            ; A = 1 draw, 0 skip
                tsta
                beq     co_reject_pri
                jsr     co_put_visual           ; ★ VISUAL ONLY -- priority stays as it was
                bra     co_nextx

* ---- depth: draw only where the sprite is at least as near as the screen ---------
co_depth:
                cmpa    co_prio
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ AC-4's INJECTED FAULT, behind -DCOMP_FAULT, and it is ONE BOUNDARY.
* The oracle draws when `screenPriority <= viewPriority`; the faulted build draws only when
* strictly less, so pixels at EQUAL priority stop being drawn. Nothing halts, no plane changes
* size, and a sprite in open ground is unaffected -- it changes only where a sprite meets
* scenery at its own depth, which is exactly the interaction the priority test exists for.
* ★★ The failure is PREDICTED before it is run: comp_fault_predict.py counts the equal-priority
* pixels in each staged frame and names the first differing row and column. A gate that fails
* somewhere is weaker evidence than a gate that fails where the model said it would [L-27].
                ifdef   COMP_FAULT
                bhs     co_reject_pri           ; ★ INJECTED: `bhi` in the correct build
                else
                bhi     co_reject_pri           ; screenPriority > viewPriority: behind
                endc
                jsr     co_put_visual
                ldx     co_rowpri
                clra
                ldb     co_curx
                ifdef   PRI_PACKED
* ★★ THE READ-MODIFY-WRITE. Packing makes a plane store into a load, a mask, an or and a store
* -- this is the write half of the packing cost, and AC-7 measures it rather than assuming it.
                lsrb
                leax    d,x
* ★★ Same ordering trap as put_pixel: load first, THEN test parity on B, or the `bne` reads the
* flags `lda ,x` just set.
                lda     ,x
                ldb     co_curx
                bitb    #1
                bne     co_st_lo
                anda    #$0F                    ; even x: keep the ODD pixel, replace the high
                ldb     co_prio
                aslb
                aslb
                aslb
                aslb
                pshs    b
                ora     ,s+
                bra     co_st_put
co_st_lo:       anda    #$F0                    ; odd x: keep the EVEN pixel, replace the low
                ora     co_prio
co_st_put:      sta     ,x
                else
                leax    d,x
                lda     co_prio
                sta     ,x                      ; ★ the sprite stamps the priority plane
                endc
                bra     co_nextx

co_reject_pri:
                ifndef  COMP_NOCOUNT
                ldu     #co_rejpri
                jsr     co_inc32
                endc

co_nextx:
                inc     co_curx
                dec     co_remw
                lbra    co_pix

co_rownext:
                dec     co_remh
                ldd     co_cury
                addd    #1
                std     co_cury
                ldd     co_rowvis
                addd    #PRI_W
                std     co_rowvis
                ldd     co_rowpri
                addd    #PRI_STRIDE
                std     co_rowpri
                lbra    co_row

co_done:
                rts

* ── co_publish ── copy the counters out to where the host reads them ─────────────
* ★ Done ONCE per handshake rather than per pixel: publishing inside the loop would put four
* extended stores on the inner path and AC-5 would be measuring its own instrument [L-56].
co_publish:
                ldd     co_tested
                std     CP_TESTED
                ldd     co_tested+2
                std     CP_TESTED+2
                ldd     co_written
                std     CP_WRITTEN
                ldd     co_written+2
                std     CP_WRITTEN+2
                ldd     co_rejpri
                std     CP_REJPRI
                ldd     co_rejpri+2
                std     CP_REJPRI+2
                ldd     co_rejkey
                std     CP_REJKEY
                ldd     co_rejkey+2
                std     CP_REJKEY+2
                ldd     co_ctrlhit
                std     CP_CTRLHIT
                ldd     co_ctrlhit+2
                std     CP_CTRLHIT+2
                ldd     co_ctrlstep
                std     CP_CTRLSTEP
                ldd     co_ctrlstep+2
                std     CP_CTRLSTEP+2
                rts

* ── co_zero_counters ─────────────────────────────────────────────────────────────
co_zero_counters:
                ldx     #co_tested
                ldb     #24                     ; six 32-bit counters
                clra
co_zc_lp:       clr     ,x+
                decb
                bne     co_zc_lp
                jmp     co_publish

* ── co_put_visual ── visual[row + curX] = colour, and count it ───────────────────
co_put_visual:
                ldx     co_rowvis
                clra
                ldb     co_curx
                leax    d,x
                lda     co_col
                sta     ,x
                ifndef  COMP_NOCOUNT
                ldu     #co_written
                jmp     co_inc32
                else
                rts
                endc

* ── co_rowset ── D = y; set co_rowvis / co_rowpri to that row's bases ────────────
* ★ y * 160 = (y << 7) + (y << 5). Done once per composite; the per-row path adds 160.
co_rowset:
                std     co_tmp
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola                            ; D = y * 32
                pshs    d
                ldd     co_tmp
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola                            ; D = y * 128
                addd    ,s++                    ; D = y * 160
                std     co_tmp
                addd    #CP_VIS
                std     co_rowvis
                ldd     co_tmp
* ★ y*160 >> 1 = y*80, the packed row base. One shift rather than a second multiply chain.
                ifdef   PRI_PACKED
                lsra
                rorb
                endc
                addd    #CP_PRI
                std     co_rowpri
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── co_checkctrl ── checkControlPixel(): walk DOWN until a priority > 2 ──────────
* out: A = 1 draw, 0 skip.  ★ Transcribed from graphics.cpp:553.
*
*     while (1) { y++; offset += 160;
*                 if (y >= 168) return true;          // nothing but control below: draw
*                 cur = priority[offset];
*                 if (cur > 2) break; }
*     return cur <= viewPriority;
*
* ★★ THE COST IS NOT ONE COMPARE. Every step is counted into co_ctrlstep, because a sprite
* standing on a control line pays a column scan PER PIXEL and that is invisible in a
* two-tests-per-pixel model. AC-5 reports it separately for exactly that reason.
* ═══════════════════════════════════════════════════════════════════════════════════
co_checkctrl:
                ldd     co_cury
                std     co_ctrly
                ldx     co_rowpri
                clra
                ldb     co_curx
                ifdef   PRI_PACKED
                lsrb                            ; A is 0, so D = x >> 1
                endc
                leax    d,x
                stx     co_ctrloff
co_cc_lp:
                ldd     co_ctrly
                addd    #1
                std     co_ctrly
                ldx     co_ctrloff
                leax    PRI_STRIDE,x
                stx     co_ctrloff
                ifndef  COMP_NOCOUNT
                ldu     #co_ctrlstep
                jsr     co_inc32
                endc
                ldd     co_ctrly
                cmpd    #PRI_H
                blt     co_cc_read
                lda     #1                      ; off the bottom: nothing but control -- draw
                rts
co_cc_read:
                ldx     co_ctrloff
                lda     ,x
* ★ x does not change down a column, so the nibble selector is FIXED for the whole walk -- but
* it is re-tested per step rather than hoisted, because the walk is 2.7% of composite cost
* [P5.4] and hoisting it would be an optimisation, which this task does not authorise (§13).
                ifdef   PRI_PACKED
                ldb     co_curx
                bitb    #1
                bne     co_cc_lo
                lsra
                lsra
                lsra
                lsra
                bra     co_cc_got
co_cc_lo:       anda    #$0F
co_cc_got:
                endc
                cmpa    #CO_CTRL_MAX
                bls     co_cc_lp                ; still control data: keep walking
                cmpa    co_prio
                bhi     co_cc_no                ; the real pixel is nearer than the sprite
                lda     #1
                rts
co_cc_no:       clra
                rts

* ── co_inc32 ── U -> a 32-bit big-endian counter; ++ ─────────────────────────────
* ★ Preserves A, B, X. The composite's inner loop calls this four times per pixel and a
* diagnostic that perturbs its own measurement is the failure mode this task keeps meeting.
* ★★★ THE OFFSETS ARE 2 AND 0, NOT 3 AND 1. A 4-byte big-endian counter holds its LOW word at
* bytes [2],[3] and its HIGH word at [0],[1]. Loading at 3,u reads bytes [3] and [4] -- the last
* byte of this counter and the FIRST BYTE OF THE NEXT ONE -- so every increment corrupted its
* neighbour and read back values like 939,524,096 ($38000000) for a count that should have been
* in the hundreds.
* ★★ The counters are contiguous by design (co_zero_counters clears all 24 bytes in one loop),
* which is exactly what turned an off-by-one into cross-contamination rather than a local error.
* The tell was `tested` looking plausible while `written` and `rejkey` were astronomically wrong.
co_inc32:
                pshs    a,b,x
                ldx     2,u
                leax    1,x
                stx     2,u
                bne     co_i32_out
                ldx     ,u
                leax    1,x
                stx     ,u
co_i32_out:     puls    a,b,x,pc

* ═══════════════════════════════════════════════════════════════════════════════════
* ── save-under ── BOTH planes, because the sprite writes both ────────────────────
*
* ★★★ THE BACKING STORE IS 2 x cel area, not 1. The oracle mallocs
* `xSize * ySize * 2 // for visual + priority data` (sprite.cpp:131). A save-under that keeps
* only the visual plane restores the picture and leaves the priority screen carrying the
* sprite's stamp -- so the NEXT sprite at that position tests against a depth the room never
* had, and the error is invisible in the visual plane until something walks behind something
* it should have walked in front of.
* ★ P5.1's model named 4,152 B as "the save-under backing-store bound". Measured here, the
* bound is 8,304 B for the same peak, and AC-7 reports the doubled figure.
* ═══════════════════════════════════════════════════════════════════════════════════
* Backing-store layout: the visual block, then the priority block, each vc_w * vc_h bytes.
* co_save and co_restore differ only in the direction of the two moves, so they share a body
* with a flag -- one walk, one set of index arithmetic, one place for it to be wrong.
                ifdef   CP_SAVE
co_svdir        fcb     0                       ; 0 = save (screen -> store), 1 = restore
co_svptr        fdb     0                       ; -> the visual half of the store
co_svptr2       fdb     0                       ; -> the priority half

co_save:        clr     co_svdir
                bra     co_sv_body
co_restore:     lda     #1
                sta     co_svdir
co_sv_body:
* set up the geometry exactly as the composite does, from the same inputs
                lda     CP_X
                sta     co_basex
                clra
                ldb     CP_Y
                pshs    d
                clra
                ldb     vc_h
                pshs    d
                ldd     2,s
                subd    ,s++
                leas    2,s
                addd    #1
                std     co_cury
                ldd     co_cury
                jsr     co_rowset

                ldd     #CP_SAVE
                std     co_svptr
                lda     vc_w
                ldb     vc_h
                mul                             ; D = the per-plane size
                std     co_tmp
                addd    #CP_SAVE
                std     co_svptr2
* ★ AC-7: the backing store is TWO planes. Reported as the doubled figure, not the cel area.
                ldd     co_tmp
                aslb
                rola
                std     CP_SAVEB
                cmpd    CP_SAVEPK
                bls     co_sv_nopk
                std     CP_SAVEPK
co_sv_nopk:
                lda     vc_h
                sta     co_remh
co_sv_row:
                lda     co_remh
                beq     co_sv_done
                clra
                ldb     co_basex
                ldx     co_rowvis
                leax    d,x                     ; X -> visual  screen row + x
                ldy     co_rowpri
                pshs    y
                clra
                ldb     co_basex
                addd    ,s++
                tfr     d,y                     ; Y -> priority screen row + x
                lda     vc_w
                sta     co_remw
co_sv_px:
                lda     co_remw
                beq     co_sv_next
                lda     co_svdir
                bne     co_sv_rest
* ---- save: screen -> store ------------------------------------------------------
                lda     ,x+
                ldu     co_svptr
                sta     ,u+
                stu     co_svptr
                lda     ,y+
                ldu     co_svptr2
                sta     ,u+
                stu     co_svptr2
                bra     co_sv_pxend
* ---- restore: store -> screen ---------------------------------------------------
co_sv_rest:
                ldu     co_svptr
                lda     ,u+
                stu     co_svptr
                sta     ,x+
                ldu     co_svptr2
                lda     ,u+
                stu     co_svptr2
                sta     ,y+
co_sv_pxend:
                dec     co_remw
                bra     co_sv_px
co_sv_next:
                dec     co_remh
                ldd     co_rowvis
                addd    #PRI_W
                std     co_rowvis
                ldd     co_rowpri
                addd    #PRI_W
                std     co_rowpri
                bra     co_sv_row
co_sv_done:
                rts
                endc
