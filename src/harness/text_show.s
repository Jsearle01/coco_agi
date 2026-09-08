* src/harness/text_show.s -- AC-1's EYE GATE: the ported text engine, on a real screen. [T-P0-075]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE HALF NO BYTE GATE CAN REACH. tools/agivm/text.py models POSITIONS, not pixels, and
* says so deliberately -- so txt_blit has no Python to be diffed against and the port gate's
* 4,594 rectangles and 293,648 glyphs say nothing whatever about whether a glyph LOOKS like its
* character. **§4A: that is what a human is for.**
*
* ★★★★ WHAT JAY SHOULD SEE: a white message box with black lettering, centred, with the text
* wrapped exactly where the reference wraps it -- and then, on the second page, the same messages
* drawn as plain white-on-black display text.
*
* ★★★★★ THE WHOLE PLANE IS ADDRESSABLE AT ONCE, WHICH IS THIS PROBE'S ONE DIVERGENCE FROM THE
* ENGINE MAP AND IT IS DELIBERATE. 320x200x16 is 32,000 bytes = four 8 KB slices, and memmap.inc
* gives the framebuffer ONE window in slot 6. A probe that windowed it would spend its code on
* remapping and its evidence on whether the remap was right -- which is a display-driver question
* and not a text question. So slots 4-7 are mapped to the four framebuffer blocks and the plane
* lives flat at $8000-$FCFF, with txt_fbrows set to 24 instead of 5.
* ★★★ THE ENGINE IS UNCHANGED BY THIS. txt_blit takes the window base, the row it starts at and
* how many rows it holds; this probe hands it a big window and the gate probe hands it none. **The
* same object code runs in both** -- which is the point of the two hooks in text.s.
* ★★ src/harness/ keeps its own addresses [memmap.inc's header]; this is not an engine decision.
*
* ★ LAUNCH PATH: poke. §4 -- this HIDES load and launch bugs and is recorded as `poke`, never as
* an unqualified pass. It is a component eye gate, not a delivery gate.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                org     $2000

TS_GO           equ     $0020           ; host writes 1 when everything is staged
TS_DONE         equ     $0021           ; probe writes 1 per page drawn
TS_PAGE         equ     $0022           ; which page the probe is showing
TS_NMSG         equ     $0023           ; how many messages the host staged
TS_ITER         equ     $0024           ; AC-7: timing iterations after the boxes, 0 = none
TS_NOBLIT       equ     $0025           ; AC-7: 1 = decision layer only, 0 = decision + blit

TS_FONT         equ     $3000           ; 2,048 B, staged by the host
TS_TABLE        equ     $3800           ; logic-0 pointer table + its text
TS_MSGS         equ     $6000           ; the messages, NUL-terminated
TS_PBUF         equ     $7C00           ; txt_pbuf, TXT_PBUF_MAX
TS_VARS         equ     $7B00           ; 256 zeroed variables

TS_FB           equ     $8000           ; the whole plane, flat, slots 4-7
TS_FB_LEN       equ     32000

start:
                orcc    #$50
                lds     #$2F00

* ── zero the variables the sweep's %v reads, exactly as the gate probe does ──
                ldx     #TS_VARS
                ldb     #0
ts_zv:          clr     ,x+
                decb
                bne     ts_zv

                ldd     #TS_VARS
                std     txt_vars
                ldd     #TS_PBUF
                std     txt_pbuf
                ldd     #TS_FONT
                std     txt_font
                ldd     #TS_TABLE
                std     txt_l0base
                std     txt_curbase
                ldd     #TS_FB
                std     txt_fbwin
                clr     txt_fbrow0
                lda     #24                     ; ★ the flat map holds every character row
                sta     txt_fbrows
                clr     txt_noblit              ; ★★★★★ DRAW. This is the whole point of the probe.
                ldd     #0
                std     txt_gcb                 ; no decision log here; the screen is the log
                std     txt_ck
                lda     #30
                sta     txt_maxw
                lda     #2
                sta     txt_rowmin
                lda     #$FF
                sta     txt_wantrow
                sta     txt_wantcol

                clr     TS_GO
                clr     TS_DONE
                clr     TS_PAGE
ts_wait:        lda     TS_GO
                beq     ts_wait

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ CLEAR THE PLANE BEFORE THE PALETTE, AND THE ORDER IS NOT COSMETIC. p3b_probe.s records
* what happens otherwise: installing real colours while the plane still holds uninitialised RAM
* showed Jay "a bunch of garbage before the king's quest title screen". The host asserts a black
* palette before staging; this zeroes the plane under it; index 0 is $00 in agi_pal16, so the
* screen never stops being black and the transition is invisible rather than merely brief.
                ldx     #TS_FB
                ldd     #0
ts_clr:         std     ,x++
                cmpx    #TS_FB+TS_FB_LEN
                blo     ts_clr
                jsr     agi_pal_load

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── page 1: message boxes, exactly as drawMessageBox places them ──
                ldx     #TS_MSGS
                stx     ts_cur
                clr     ts_i
ts_box_lp:
                lda     ts_i
                cmpa    TS_NMSG
                bhs     ts_box_done
* ★★★ CLEAR BETWEEN BOXES. AGI does NOT do this -- a message box draws over whatever is there and
* closeWindow restores it -- but this probe has no save-under, so without a clear each box lands
* on the previous one and the third is unreadable. **A demo that accumulates is not a gate**, and
* the readback confirmed it: box 2's row counts included box 1's ink.
                ldx     #TS_FB
                ldd     #0
ts_pclr:        std     ,x++
                cmpx    #TS_FB+TS_FB_LEN
                blo     ts_pclr
                ldx     ts_cur
                stx     txt_msgp
                jsr     txt_msgbox
                jsr     txt_close
                ldx     ts_cur
ts_box_skip:    lda     ,x+
                bne     ts_box_skip
                stx     ts_cur
                inc     ts_i
* ★★ One box at a time, with a handshake between, so the host can pace them for a human. A page
* that flashed twenty boxes in four frames is not something anyone can judge.
                lda     #1
                sta     TS_DONE
ts_box_ack:     lda     TS_GO
                beq     ts_box_ack2
                bra     ts_box_ack
ts_box_ack2:
                clr     TS_DONE
ts_box_wait:    lda     TS_GO
                beq     ts_box_wait
                bra     ts_box_lp
ts_box_done:
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AC-7's TIMING LOOP, AND IT EXISTS BECAUSE THE FIRST MEASUREMENT WAS OF THE HARNESS.
* Timing the paced box loop gave 84,626 cycles per glyph for a three-glyph message and 6,067 for a
* ninety-six-glyph one -- a "per-glyph cost" that falls as glyphs are added, which is the shape of
* a FIXED overhead being divided. The interval was bracketing a 32,000-byte plane clear and
* several frame-quantised handshake round-trips, and the rendering was the small part.
* ★★★★ So: N iterations of the SAME message, no clear, no handshake, one GO/DONE around the whole
* run. The fixed cost is then amortised to nothing and what is left is the work.
* ★★★ TWO ARMS, because AC-7 asks what the cost IS and what it competes with. TS_NOBLIT selects
* whether txt_blit runs, so the difference between the arms is the BLITTER and the remainder is
* the decision layer -- substitution, wrap and placement. **Naming both is what stops "text is
* expensive" from being a sentence about the wrong half** [L-73: name every variable a toggle
* moves; this one moves exactly one].
                lda     TS_ITER
                beq     ts_finish
                sta     ts_n
                lda     TS_NOBLIT
                sta     txt_noblit
                lda     #2
                sta     TS_PAGE                 ; the host reads this as "timing has begun"
ts_time_lp:
                ldx     #TS_MSGS
                stx     txt_msgp
                jsr     txt_msgbox
                jsr     txt_close
                dec     ts_n
                bne     ts_time_lp
ts_finish:
                lda     #$FF
                sta     TS_PAGE
                lda     #1
                sta     TS_DONE
ts_end:         bra     ts_end

ts_n            fcb     0

ts_i            fcb     0
ts_cur          fdb     0

                include "content/agi_palette.s"
                include "src/engine/text.s"

                end     start
