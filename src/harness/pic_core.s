* src/harness/pic_core.s -- the PICTURE renderer, extracted so more than one probe can hold it.
*
* ★★★★ EXTRACTED BY T-P0-032 BECAUSE THE FIVE "SUBSYSTEMS" ARE NOT FIVE MODULES.
* pic_draw.s and pic_fill.s were already separate files, but they call put_pixel and read
* cur_x/cur_y/scr_on/pri_on -- all of which lived in pic_probe.s. So the gated "renderer" was
* pic_probe.s + pic_draw.s + pic_fill.s, and the reusable part could not be included anywhere
* else. Integration is what exposed it: p3b_probe.s named 33 undefined symbols, and a third of
* them were this file.
*
* ★★ THE MOVE IS PURE. Content and order are unchanged, and nothing between the old regions
* emitted bytes (comments and two equs), so pic_probe.bin is byte-identical across the change
* -- verified, not assumed. §2F: one home per fact, and put_pixel now has one.
*
* ★ THE INCLUDER SUPPLIES: FB_BASE, PRI_BASE, PIC_W, PIC_H, bad_op, and the CNT_* counters.
* ★★ THE COUNTERS ARE NOT OPTIONAL AND THAT IS A FINDING. composite.s guards its counters
* behind -DCOMP_NOCOUNT; pic_draw.s increments CNT_VERT unconditionally. **The two subsystems
* disagree about whether instrumentation is part of the product**, and a shipped renderer
* cannot currently be built without it.

* ═══════════════════════════════════════════════════════════════════
* pix_addr — D = y*160 + x, X = FB_BASE+D (visual), Y = PRI_BASE+D (priority)
* in: cur_x (byte), cur_y (byte).  ★ 167*160 = 26,720, so MUL's 16-bit result is exact.
* ═══════════════════════════════════════════════════════════════════
pix_addr:
                lda     cur_y
                ldb     #PIC_W
                mul                             ; D = y*160
                addb    cur_x
                adca    #0                      ; D = y*160 + x
                std     pix_off
                addd    #FB_BASE
                tfr     d,x
                ldd     pix_off
                addd    #PRI_BASE
                tfr     d,y
                rts

* ═══════════════════════════════════════════════════════════════════
* in_bounds — Z set (eq) when cur_x/cur_y are on the picture
* ═══════════════════════════════════════════════════════════════════
in_bounds:
                lda     cur_x
                cmpa    #PIC_W
                bhs     ib_no
                lda     cur_y
                cmpa    #PIC_H
                bhs     ib_no
                andcc   #$FB                    ; clear Z ... then set it
                orcc    #$04
                rts
ib_no:          andcc   #$FB                    ; Z clear = out of bounds
                rts

* ═══════════════════════════════════════════════════════════════════
* put_pixel — write the ENABLED planes at cur_x/cur_y (putVirtPixel)
* ═══════════════════════════════════════════════════════════════════
put_pixel:
* ★★★ P3.5 — 186 -> ~118 cycles. Measured at 186 by direct benchmark (Part B), against a
* REGRESSION estimate of ~40 in T-P0-012. It was the second largest component of the whole
* render, 29.8%, and nobody had looked at it because the ratio said it was small.
*
* ★★ THREE THINGS IT WAS DOING, none of them necessary:
*   1. `jsr in_bounds` + `jsr pix_addr` -- two subroutine calls, ~26 cycles of jsr/rts alone,
*      for two compares and an address. Both are now inline.
*   2. `pix_addr` formed BOTH plane pointers every call. The priority pointer is formed only
*      when pri_on, and the visual pointer only when scr_on.
*   3. the nibble doubling was recomputed per pixel -- `anda`, a second load, four `lslb`, a
*      pshs/ora pair, ~30 cycles -- from scr_color, which CANNOT CHANGE during a fill. It is
*      now precomputed into scr_dbl by op_set_visual (and by the state reset).
* ★ scr_dbl is identically (scr_color & 15) * 17, which is exactly what the old sequence
* computed: low nibble, OR'd with the same nibble shifted up four.
                lda     cur_x
                cmpa    #PIC_W                  ; UNSIGNED (L-40)
                bhs     pp_out
                lda     cur_y
                cmpa    #PIC_H
                bhs     pp_out
                ldb     #PIC_W                  ; A still holds cur_y
                mul
                addb    cur_x
                adca    #0                      ; D = y*160 + x
                std     pix_off
                lda     scr_on
                beq     pp_pri
                ldd     pix_off
                addd    #FB_BASE
                tfr     d,x
                lda     scr_dbl                 ; the doubled byte, precomputed
                sta     ,x
                ifndef  PIC_NOCOUNT
                pshs    d
                ldd     CNT_PIX
                addd    #1
                std     CNT_PIX
                puls    d
                endc
pp_pri:         lda     pri_on
                beq     pp_out
                ldd     pix_off
* ★★★★ -DPRI_PACKED: the sixth site of the nibble convention, which is stated in full at the
* head of composite.s. byte = (y*160+x) >> 1; EVEN x -> HIGH nibble, ODD x -> LOW.
* ★★ pix_off is already y*160+x, so one shift gives the packed offset -- the renderer needs no
* second address computation. ★ The write becomes a read-modify-write, which is the cost.
                ifdef   PRI_PACKED
                lsra
                rorb
                addd    #PRI_BASE
                tfr     d,x
* ★★ ORDER IS LOAD-BEARING: `lda ,x` sets N/Z from the byte it loads, so the parity test must
* come AFTER it, on B. Writing `bitb #1 / lda ,x / bne` tests the loaded byte instead of the
* parity -- caught here before assembly, and it is the flag-clobber shape x_liveness.py was
* built for, one register further along.
                lda     ,x
                ldb     cur_x
                bitb    #1
                bne     pp_pri_lo
                anda    #$0F                    ; even x: keep the ODD pixel
                ldb     pri_color
                aslb
                aslb
                aslb
                aslb
                pshs    b
                ora     ,s+
                bra     pp_pri_put
pp_pri_lo:      anda    #$F0                    ; odd x: keep the EVEN pixel
                ora     pri_color
pp_pri_put:     sta     ,x
                else
                addd    #PRI_BASE
                tfr     d,x
                lda     pri_color
                sta     ,x
                endc
pp_out:         rts

                include "src/harness/pic_draw.s"
                include "src/harness/pic_fill.s"

* ═══════════════════════════════════════════════════════════════════
* pic_render — the opcode loop
*
* ★★ UNIMPLEMENTED OPCODES HALT LOUDLY (L-23). Picture 80 uses set_visual, set_priority,
* disable_priority, x_corner, rel_line, fill and end — measured from the resource bytes, not
* assumed. Anything else stores its opcode in bad_op and stops, so a silent mis-render is not
* on the table. KQ1's whole corpus uses NO pattern opcodes.
* ═══════════════════════════════════════════════════════════════════
pic_render:
                ldx     #PIC_DATA
                stx     pic_ptr
pr_next:        jsr     pic_get
                cmpa    #$FF
                beq     pr_done
                cmpa    #$F0
                blo     pr_bad                  ; a parameter where an opcode was expected
                suba    #$F0
                cmpa    #10
                bhi     pr_bad
                ldx     #pr_table
                lsla
                ldx     a,x
                cmpx    #0
                beq     pr_bad
                jsr     ,x
                bra     pr_next
pr_done:        clr     bad_op
                rts
pr_bad:         adda    #$F0
                sta     bad_op
                rts

pr_table:       fdb     op_set_visual           ; F0
                fdb     op_dis_visual           ; F1
                fdb     op_set_pri              ; F2
                fdb     op_dis_pri              ; F3
                fdb     op_y_corner             ; F4  [T-P0-012]
                fdb     op_x_corner             ; F5
                fdb     op_abs_line             ; F6  [T-P0-012]
                fdb     op_rel_line             ; F7
                fdb     op_fill                 ; F8
* ★ F9/FA REMAIN 0 AND HALT LOUDLY, and that is reported rather than hidden (AC-4). No picture
* in the gated set uses them -- picset.py's census across three games counts set_pattern=0 and
* pattern_brush=0 -- so they are UNREACHED, not silently skipped. A silent no-op is forbidden.
                fdb     0                       ; F9 set_pattern   -- unreached by the set
                fdb     0                       ; FA pattern_brush -- unreached by the set

* pic_get — next picture byte into A
pic_get:        ldx     pic_ptr
                lda     ,x+
                stx     pic_ptr
                rts

* ── F0 set_visual / F1 disable / F2 set_priority / F3 disable ──────
op_set_visual:  jsr     pic_get
                sta     scr_color
* ★ Maintain the doubled byte HERE, where the colour changes, instead of in put_pixel, where it
* is read. This is the only place scr_color is written by a picture.
                anda    #$0F
                sta     scr_dbl
                lsla
                lsla
                lsla
                lsla
                ora     scr_dbl
                sta     scr_dbl
                lda     #1
                sta     scr_on
                rts
op_dis_visual:  clr     scr_on
                rts
op_set_pri:     jsr     pic_get
                sta     pri_color
                lda     #1
                sta     pri_on
                rts
op_dis_pri:     clr     pri_on
                rts

* ── F5 x_corner: x,y then alternating x,y,x,y... ──────────────────
op_x_corner:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
                lda     #1
                sta     xc_isx                  ; next parameter is an X
xc_lp:          jsr     pic_peek
                cmpa    #$F0
                bhs     xc_done
                jsr     pic_get
                tfr     a,b                     ; B = the new coordinate
                lda     cur_x
                sta     ln_x1
                lda     cur_y
                sta     ln_y1
                lda     xc_isx
                beq     xc_isy
                stb     cur_x
                bra     xc_draw
xc_isy:         stb     cur_y
xc_draw:        lda     cur_x
                sta     ln_x2
                lda     cur_y
                sta     ln_y2
                jsr     draw_line
                lda     xc_isx
                eora    #1
                sta     xc_isx
                bra     xc_lp
xc_done:        rts

* ── F4 y_corner: x,y then alternating y,x,y,x... ──────────────────
* ★★ THE SAME LOOP AS x_corner, ENTERED ON THE OTHER PHASE. At the pin, `xCorner` and
* `yCorner` are mirror-image functions [picture.cpp:178,219 @ 9d9b9e9]: x_corner takes an X
* first and draws a horizontal segment, y_corner takes a Y first and draws a vertical one, and
* both then alternate. `xc_isx` already encodes exactly that phase, so y_corner is x_corner
* with the toggle cleared instead of set. ★ Sharing the loop is not a shortcut -- it is the
* same mechanism in the reference, and duplicating it would let the two drift.
* ★ Called as `yCorner()` from drawPicture's 0xF4 case, i.e. skipOtherCoords=false; the true
* variant is the AGI256/v1 path and is not this target (§2H check 2 -- the caller carries the
* scope).
op_y_corner:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
                clr     xc_isx                  ; next parameter is a Y  <-- the only difference
                bra     xc_lp

* ── F6 abs_line: x,y then absolute x,y PAIRS ──────────────────────
* [ref: picture.cpp draw_LineAbsolute @ 9d9b9e9] -- getNextCoordinates(x2,y2) is
* getNextXCoordinate && getNextYCoordinate, so on a terminating byte the X IS ALREADY
* CONSUMED and only the Y is rewound (getNextParamByte does `_dataOffset--`). ★ This peeks
* each byte before taking it, which reproduces that asymmetry exactly: X is consumed, then Y
* is peeked, and a terminator at the Y position leaves the X spent.
op_abs_line:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
al_lp:          jsr     pic_peek
                cmpa    #$F0
                bhs     al_done
                jsr     pic_get                 ; X consumed
                pshs    a
                jsr     pic_peek
                cmpa    #$F0
                bhs     al_pop                  ; terminator at Y: X stays spent
                jsr     pic_get                 ; Y consumed
                tfr     a,b                     ; B = y2
                lda     cur_x
                sta     ln_x1
                lda     cur_y
                sta     ln_y1
                puls    a                       ; A = x2
                sta     cur_x
                sta     ln_x2
                stb     cur_y
                stb     ln_y2
                jsr     draw_line
                bra     al_lp
al_pop:         leas    1,s                     ; discard the consumed X
al_done:        rts

pic_peek:       ldx     pic_ptr
                lda     ,x
                rts

* ── F7 rel_line: x,y then packed signed nibble deltas ─────────────
op_rel_line:    jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                jsr     put_pixel
rl_lp:          jsr     pic_peek
                cmpa    #$F0
                bhs     rl_done
                jsr     pic_get
                pshs    a
                lda     cur_x
                sta     ln_x1
                lda     cur_y
                sta     ln_y1
* ★★★ SIGN-MAGNITUDE, NOT TWO'S COMPLEMENT. picture.cpp:640-643:
*     if (dx & 0x08) dx = -(dx & 0x07);
*     if (dy & 0x08) dy = -(dy & 0x07);
* Bit 3 is a SIGN BIT and bits 0-2 are the MAGNITUDE, so $F is -7. A two's-complement
* sign-extension (`ora #$F0`) makes $F into -1 instead, and every negative delta lands in the
* wrong place. That was this probe's first real rendering defect: the lines went astray, so the
* colour-7 fills had no boundary, leaked across the whole picture, and left nothing white for
* the final background fill to claim. 92% of the visual plane differed for want of these four
* instructions.
                lda     ,s
                lsra
                lsra
                lsra
                lsra                            ; A = high nibble = dx
                bita    #$08
                beq     rl_dxpos
                anda    #$07                    ; magnitude
                nega                            ; ...negated
rl_dxpos:       adda    cur_x
                sta     cur_x
                puls    a
                anda    #$0F                    ; A = low nibble = dy
                bita    #$08
                beq     rl_dypos
                anda    #$07
                nega
rl_dypos:       adda    cur_y
                sta     cur_y
                lda     cur_x
                sta     ln_x2
                lda     cur_y
                sta     ln_y2
                jsr     draw_line
                bra     rl_lp
rl_done:        rts

* ── F8 fill: (x,y) pairs until the next opcode ────────────────────
op_fill:        jsr     pic_peek
                cmpa    #$F0
                bhs     of_done
                jsr     pic_get
                sta     cur_x
                jsr     pic_get
                sta     cur_y
                ldd     CNT_FILL                ; AC-7: invocations, counted even when skipped
                addd    #1
                std     CNT_FILL
* ★★★ -DPIC_NOFILL — THE DECOMPOSITION BUILD (AC-5). There is no cycle counter on a 6809 and
* per-call instrumentation would perturb what it measures, so fill cost is obtained by
* DIFFERENCE: the same binary, the same picture, the fill call alone suppressed. Both builds
* still walk the resource, consume the same operands and count the same invocations, so the
* delta is the flood fill and nothing else. ★ This build renders a WRONG picture on purpose
* and must never be gated -- picdiff is not run on it.
                ifndef  PIC_NOFILL
                jsr     flood_fill
                endc
                bra     op_fill
of_done:        rts

* ── renderer state (moved verbatim from pic_probe.s:811-821) ────────────────────

pic_ptr         fdb     0
pix_off         fdb     0
cur_x           fcb     0
cur_y           fcb     0
scr_color       fcb     0
scr_dbl         fcb     0       ; (scr_color & 15) * 17 -- see put_pixel
pri_color       fcb     4
scr_on          fcb     0
pri_on          fcb     0
xc_isx          fcb     0
