* src/harness/pic_probe.s
*
* T-P0-011 Part B — render ONE AGI PICTURE on a real CoCo3, in 320x200x16.
*
* ★★ THIS IS A HARNESS PROBE, NOT ENGINE CODE. It lives in src/harness/ so src/engine/** stays
* empty and reg_discipline.py stays at 0 (CLAUDE.md §2N). The real engine renderer is a later
* task; this exists to put the FIRST PIXELS on the machine and prove the pipeline end to end.
*
* ★★★ WHAT IS BEING TESTED. The framebuffer this writes is read back by MAME, unpacked, and
* diffed against the PINNED ORACLE's 160x168 visual buffer — never against tools/picrender/.
* Both are clients of the same reference; comparing them to each other would let both be wrong
* the same way and report green for ever [CLAUDE.md §2O.1, design §8.2].
*
* ═══════════════════════════════════════════════════════════════════
* MEMORY MAP — chosen so both planes and the code fit one 64 KB map
* ═══════════════════════════════════════════════════════════════════
*   $0100..$04FF  fill stack, 512 B = 256 entries of 2 B (x,y)
*                 ★ measured peak seed depth in the offline renderer was 102 (P2 fill study),
*                   so 256 is ~2.5x headroom. The probe HALTS on overflow rather than wrapping.
*   $0500..$07FF  the 6809 HARDWARE stack, S starts at $0800 and grows DOWN.
*                 ★★ THE CALLER MUST SET S AND THE HAL DOES NOT. hal.inc:357-362 states the
*                   requirement outright -- "THE STACK MUST NOT LIVE IN THE DRAW WINDOW ... put
*                   the stack BELOW $8000" -- and its suggested $7F00 is inside THIS probe's
*                   priority plane, so it cannot be taken literally here. Leaving S where DECB
*                   put it aimed the hardware stack straight into the fill stack: the first
*                   deep fill overwrote a return address and the CPU ran off into $0211.
*   $0800..$16FF  code (this file + the HAL modules it calls)
*   $1700..$7FFF  PRIORITY plane, 160 x 168 = 26,880 B = $6900. Ends at exactly $8000.
*   $8000..$FFFF  the GIME framebuffer window (GFX_DB_WINDOW, 4 blocks = 32 KB). The VISUAL
*                 plane is written straight into it.
*
* ★ VISUAL IS 1 BYTE PER AGI PIXEL AND THAT IS NOT A COINCIDENCE. Mode 2 is 4bpp, so a
* CoCo3 byte holds two adjacent screen pixels. AGI's picture is 160 wide against the CoCo3's
* 320, so ONE AGI pixel is TWO CoCo3 pixels — exactly one byte, with the colour in BOTH
* nibbles. 160 AGI px/row x 1 B = 160 B/row, which is mode 2's stride exactly.
* ★★ The nibble duplication IS the pixel doubling. Writing colour*17 ($0->$00, $F->$FF) is the
* whole transform, and the read-back side inverts it by checking the two nibbles agree.
*
* ★ PRIORITY IS NOT DOUBLED. Design §3.3 keeps the priority plane 160 wide with the lookup
* x>>1, so it is 160x168 one byte per pixel — the SAME shape as the oracle's. No transform, no
* place for a transform error to hide (AC-7).

                include "src/hal.inc"

PIC_W           equ     160
PIC_H           equ     168

STACK_BASE      equ     $0100           ; fill stack (seed points)
STACK_TOP       equ     $0500           ; one past the last usable fill entry
HW_STACK        equ     $0800           ; 6809 S, grows DOWN into $0500..$07FF
PRI_BASE        equ     $1700           ; 160*168 = $6900 -> ends at $8000
FB_BASE         equ     $8000           ; GFX_DB_WINDOW

* Where the driver leaves the picture resource, and where the probe reports.
*
* ★★ BOTH ADDRESSES MUST LIE BELOW $8000. The framebuffer window is $8000-$FFFF and
* HAL_gfx_set_mode CLEARS it, so anything staged up there is destroyed before the first opcode
* is read. The gap between the code (~$1125) and the priority plane ($1700) is the only space
* that is neither cleared nor overwritten, so both live there.
PIC_DATA        equ     $1200           ; picture resource, poked in by the MAME side.
                                        ;   $1200..$16EF = 1,264 B; picture 80 is 211 B.
STATUS          equ     $16F0           ; +0 done sentinel, +1 bad opcode / $EE stack overflow

                org     $0800
* ═══════════════════════════════════════════════════════════════════
probe_entry:
                orcc    #$50                    ; mask interrupts for the duration
                lds     #HW_STACK               ; ★ hal.inc:357 -- the CALLER owns S

                jsr     HAL_sys_init            ; bare-metal transition: $FF90 + MMU
                lda     #GFX_MODE_320x200x16    ; = 2, by contract name not literal
                jsr     HAL_gfx_set_mode        ; clears both buffers, loads mode 2's palette

                jsr     pal_load                ; ★ AGI's 16 EGA colours, from a TABLE
                jsr     vis_clear               ; visual plane = 15 (white)
                jsr     pri_clear               ; priority plane = 4 (red)
                jsr     pic_render              ; interpret the picture

                lda     #$A5                    ; sentinel LAST: a partial run is visible
                sta     done_flag
probe_halt:     bra     probe_halt

* ═══════════════════════════════════════════════════════════════════
* pal_load — write the 16 AGI colours to $FFB0-$FFBF
*
* ★★ FROM A TABLE, NEVER INLINE (CLAUDE.md §2F.1: "never inline a palette constant at a write
* site"). That is what makes the composite palette a later data change rather than a rewrite.
* ★ These 16 values are a TRANSCRIPTION of AGI's EGA palette, not a choice. Entry 6 is brown
* $22 = (R2,G1,B0) — the ONLY non-uniform entry, and the one a "double the CGA bit" conversion
* silently turns into dark yellow.
* ═══════════════════════════════════════════════════════════════════
pal_load:
                ldx     #agi_pal16
                ldy     #$FFB0
pal_lp:         lda     ,x+
                sta     ,y+
                cmpx    #agi_pal16+16
                blo     pal_lp
                rts

agi_pal16:
                fcb     $00             ;  0 black
                fcb     $08             ;  1 blue
                fcb     $10             ;  2 green
                fcb     $18             ;  3 cyan
                fcb     $20             ;  4 red
                fcb     $28             ;  5 magenta
                fcb     $22             ;  6 brown      ★ (2,1,0), the odd one out
                fcb     $38             ;  7 light grey
                fcb     $07             ;  8 dark grey
                fcb     $0F             ;  9 light blue
                fcb     $17             ; 10 light green
                fcb     $1F             ; 11 light cyan
                fcb     $27             ; 12 light red
                fcb     $2F             ; 13 light magenta
                fcb     $37             ; 14 yellow
                fcb     $3F             ; 15 white

* ═══════════════════════════════════════════════════════════════════
* vis_clear / pri_clear — THE AGI CANVAS IS WHITE-ON-RED, NOT BLACK
*
* ★★★ HAL_gfx_set_mode clears the framebuffer to palette index 0, which is correct for the HAL
* and WRONG for an AGI picture. AGI draws onto visual=15 (white) and priority=4 (red)
* [tools/picrender/screens.py, "clear to 15/4"], and draw_FillCheck fills only where the
* VISUAL is 15. Leaving the HAL's black canvas meant no fill could EVER succeed: the first run
* rendered 705 line pixels and none of the 88% of the picture that is fill.
*
* ★ Note the first row agreed with the oracle anyway, because the oracle's row 0 is genuinely
* black there -- two buffers matching for different reasons. A gate that only checked row 0
* would have passed.
* ═══════════════════════════════════════════════════════════════════
vis_clear:
                ldx     #FB_BASE
                ldd     #$FFFF                  ; 15 in both nibbles = white, doubled
vc_lp:          std     ,x++
                cmpx    #FB_BASE+(PIC_W*PIC_H)
                blo     vc_lp
                rts

pri_clear:
                ldx     #PRI_BASE
                ldd     #$0404
pc_lp:          std     ,x++
                cmpx    #PRI_BASE+(PIC_W*PIC_H)
                blo     pc_lp
                rts

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
                jsr     in_bounds
                bne     pp_out
                jsr     pix_addr
                lda     scr_on
                beq     pp_pri
                lda     scr_color
                anda    #$0F
                ldb     scr_color
                lslb
                lslb
                lslb
                lslb
                pshs    b
                ora     ,s+                     ; ★ colour in BOTH nibbles = the pixel doubling
                sta     ,x
pp_pri:         lda     pri_on
                beq     pp_out
                lda     pri_color
                sta     ,y
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
                fdb     0                       ; F4 y_corner   -- not needed by picture 80
                fdb     op_x_corner             ; F5
                fdb     0                       ; F6 abs_line   -- not needed by picture 80
                fdb     op_rel_line             ; F7
                fdb     op_fill                 ; F8
                fdb     0                       ; F9 set_pattern
                fdb     0                       ; FA pattern_brush

* pic_get — next picture byte into A
pic_get:        ldx     pic_ptr
                lda     ,x+
                stx     pic_ptr
                rts

* ── F0 set_visual / F1 disable / F2 set_priority / F3 disable ──────
op_set_visual:  jsr     pic_get
                sta     scr_color
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
                jsr     flood_fill
                bra     op_fill
of_done:        rts

* ═══════════════════════════════════════════════════════════════════
* State. Absolute rather than direct-page: this is a probe, clarity beats a few cycles, and
* the HAL owns DP $00-$1F.
* ═══════════════════════════════════════════════════════════════════
done_flag       equ     STATUS
bad_op          equ     STATUS+1

pic_ptr         fdb     0
pix_off         fdb     0
cur_x           fcb     0
cur_y           fcb     0
scr_color       fcb     0
pri_color       fcb     4
scr_on          fcb     0
pri_on          fcb     0
xc_isx          fcb     0

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"
                include "src/hal/coco3-dsk/input.s"
                include "src/hal/coco3-dsk/sound.s"
                include "src/hal/coco3-dsk/file.s"
                include "src/hal/coco3-dsk/mem.s"
                include "src/hal/coco3-dsk/disk_read.s"
                end     probe_entry
