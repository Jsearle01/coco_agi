* src/harness/text_probe.s -- run the PORTED text engine over the gate's messages. [T-P0-075 AC-3]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE SAME MESSAGES THE REFERENCE RAN, IN THE SAME ORDER. harness/tools/text_port_gate.py
* walks agi.cpp's sweep rule (every loadable logic, its first eight non-empty texts, skipping the
* one the oracle cannot survive) and stages exactly that list here; the records this probe writes
* are diffed against tools/agivm/text.py's events. **The 6809 is compared against the Python, and
* the Python is compared against the oracle at 4,594 rectangles and 293,648 glyphs across nine
* titles** -- so the chain is 6809 -> Python -> ScummVM without an emulated ScummVM.
*
* ★★★ WHY NOT DIFF AGAINST THE ORACLE DIRECTLY: the same comparison with a longer chain and one
* more thing to get wrong. If this probe ever diverges from the Python, bisecting is one step
* [L-36]. ★★ And the Python leg is re-gated on every run of harness/tools/text_run.sh, so the
* reference leg cannot go stale under this one.
*
* ★ Flat map: this probe has the whole 64 KB and no framebuffer, so txt_noblit is set and the
* per-glyph callback records instead. **The pixels are AC-1's eye gate, not this probe's job**
* -- and both run the same object code, which is the point of the two hooks in text.s.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                org     $2000

* ── the host handshake, the same shape parser_probe.s uses ───────────────────────
TX_GO           equ     $0020           ; host writes 1 to start a chunk
TX_DONE         equ     $0021           ; probe writes 1 when the chunk is finished
TX_NMSG         equ     $0022           ; 2 B: messages staged in this chunk
TX_RUN          equ     $0024           ; 2 B: messages completed
TX_ROVF         equ     $0026           ; 1 B: the result buffer filled -- see below

* ── staged by the host ───────────────────────────────────────────────────────────
* ★★★★★ THESE FOUR ADDRESSES ARE ALSO IN text_port_gate.lua AND THEY MUST AGREE. The first run
* had TX_MSGS at $4000 here and $5000 there: the host staged messages the probe never read, so the
* probe parsed whatever DECB had left at $4000 as NUL-terminated text. **The symptom was a blown
* stack and a PC inside the result buffer** -- which reads as a defect in the wrap, and is a map
* disagreement between two files. ★★★ $5000 is also what the logic-0 text block needs: its base is
* $3000 + 2 + 176*2 = $3162 and Kingquest1's block is 4,738 bytes, ending at $43E4.
* ★★★★★ THE 256 VARIABLES, ZEROED, AND THEY ARE NOT OPTIONAL. PrintfState's default get_var is
* `lambda i: 0` -- the sweep runs at init, so every variable really is 0 on the oracle's leg. The
* first run left txt_vars at 0, so `%v` read address $0000 upward: the DIRECT PAGE and this
* probe's own handshake bytes. ★★★★ The failure was small, late and precise -- 554 of 596
* rectangles identical and then message 555, KQ1's first %v-bearing message, two characters too
* wide because a garbage byte formatted as three digits where zero formats as one. **The same
* index P6.18's --fault-printf arm diverges at**, which is the gate saying "substitution" as
* clearly as it can.
TX_VARS         equ     $2D00           ; 256 B, zeroed at start
TX_TABLE        equ     $3000           ; logic-0 / current-logic pointer table, then its text
TX_MSGS         equ     $5000           ; the chunk's messages, each NUL-terminated
TX_PBUF         equ     $9000           ; txt_pbuf: TXT_PBUF_MAX scratch  ($9000-$92FF)
TX_RESULTS      equ     $9400           ; records, see below
TX_RES_END      equ     $FE00           ; ★ stop before the vector page [vm_probe's $FE00 lesson]

* message record (per message, written by the probe):
*   'M'  u8 boxw  u8 boxh  u8 srow  u8 trow  u8 tcol
*        i16 bgx  i16 bgy  u16 bgw  u16 bgh   u16 nglyph
*   then nglyph x:  'G' u8 row  u8 col  u8 fg  u8 bg  u16 cksum
* ★★ Big-endian for every 16-bit field, because STD stores high byte first and the reader is told
* so once rather than guessing per field [parser_gate.lua's two-orders note].

start:
                orcc    #$50                    ; ★ no interrupts: nothing here needs them, and a
                                                ;   stray IRQ would run DECB's handler over us
                lds     #$2F00

                ldx     #TX_VARS                ; zero the variables the sweep's %v reads
                ldb     #0
tx_zv:          clr     ,x+
                decb
                bne     tx_zv
                ldd     #TX_VARS
                std     txt_vars

                ldd     #TX_PBUF
                std     txt_pbuf
                lda     #30                     ; text.cpp:458's default max width
                sta     txt_maxw
                lda     #2                      ; _window_Row_Min for a normal v2 game
                sta     txt_rowmin
                lda     #$FF
                sta     txt_wantrow             ; -1: centre
                sta     txt_wantcol
                lda     #1
                sta     txt_noblit              ; ★ no framebuffer in this map
                ldd     #tx_glyph
                std     txt_gcb
                ldd     #0
                std     txt_ck                  ; ★★★ ONCE, not per message -- the checksum rolls
                                                ;     over the whole run on both legs
                std     txt_fbwin

* ★★★★★ CLEAR TX_GO, NOT JUST TX_DONE. $0020 is in the direct page and DECB was running here a
* moment ago; whatever it left is not zero. parser_probe.s lost a session to exactly this -- the
* host sets PC on one frame and stages on the next, and in that gap a leftover GO starts the probe
* on a garbage count.
                clr     TX_GO
                clr     TX_DONE
                clr     TX_ROVF
                ldd     #0
                std     TX_RUN
tx_wait:        lda     TX_GO
                beq     tx_wait

                ldx     #TX_MSGS
                stx     tx_cur
                ldy     #TX_RESULTS
                sty     tx_out
                ldd     #0
                std     tx_i
                clr     TX_ROVF
tx_loop:
                ldd     tx_i
                cmpd    TX_NMSG
                bhs     tx_fin
* ── room for the worst case? A box is at most 40 columns x 20 rows plus the header. ──
* ★★★ 12 header bytes + 800 glyph records of 6 = 4,812. Checked BEFORE the message rather than
* after, because a record half-written into the next region is the shape that reads as a text
* defect three subsystems away.
* ★★★★★ THE FIRST FORM OF THIS CHECK OVERFLOWED AND THEREFORE PASSED WHEN IT SHOULD HAVE FAILED.
* It was `tx_out + 4812 < TX_RES_END`, and once tx_out passed $F3F4 the sum WRAPPED past $FFFF to
* a small number, which compares below $FE00 -- so the guard waved through exactly the case it
* existed to catch. The cursor ran on to $173E, writing glyph records over the probe's own code
* and over the $0020 handshake, and the host then read DONE and GO as a foreground and a
* background colour.
* ★★★★ §2W: **an instrument that cannot fail does not measure**, and a bounds check that overflows
* is that, in the one place where being right matters. Subtracting cannot wrap the same way: if
* tx_out is already past the end the difference is negative and BMI catches it.
                ldd     #TX_RES_END
                subd    tx_out
                bmi     tx_full
                cmpd    #4812
                bhs     tx_room
tx_full:
                lda     #1
                sta     TX_ROVF                 ; tell the host to take a shorter chunk
                bra     tx_fin
tx_room:
                ldx     tx_cur
                stx     txt_msgp
                ldd     #0
                std     txt_ng
                jsr     txt_msgbox
                jsr     txt_close
* ── advance past this message's NUL ──
                ldx     tx_cur
tx_skip:        lda     ,x+
                bne     tx_skip
                stx     tx_cur
* ── write the message record ──
                ldy     tx_out
                lda     #'M
                sta     ,y+
                lda     txt_boxw
                sta     ,y+
                lda     txt_boxh
                sta     ,y+
                lda     txt_srow
                sta     ,y+
                lda     txt_trow
                sta     ,y+
                lda     txt_tcol
                sta     ,y+
                ldd     txt_bgx
                std     ,y++
                ldd     txt_bgy
                std     ,y++
                ldd     txt_bgw
                std     ,y++
                ldd     txt_bgh
                std     ,y++
                ldd     txt_ng
                std     ,y++
                sty     tx_out
* ★★★★ THE GLYPH RECORDS WERE ALREADY WRITTEN, BY tx_glyph, DURING txt_msgbox -- so this header
* is emitted AFTER them and the reader must know that. It is written this way because nglyph is
* not known until the message is drawn, and buffering the glyphs to put the header first would
* need the very second buffer txt_wrap exists to avoid.
                ldd     tx_i
                addd    #1
                std     tx_i
                std     TX_RUN
                lbra    tx_loop
tx_fin:
                ldd     tx_i
                std     TX_RUN
                lda     #1
                sta     TX_DONE
tx_ack:         lda     TX_GO                   ; host clears GO to acknowledge
                bne     tx_ack
                clr     TX_DONE
                lbra    tx_wait

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ tx_glyph -- txt_gcb. Called once per glyph, with the decision in text.s's own state.
* ★ It writes into the SAME cursor the message header uses, ahead of that header (see above).
tx_glyph:
                pshs    a,y
                ldy     tx_out
                lda     #'G
                sta     ,y+
                lda     txt_crow
                sta     ,y+
                lda     txt_ccol
                sta     ,y+
                lda     txt_fg
                sta     ,y+
                lda     txt_bg
                sta     ,y+
                pshs    b
                ldd     txt_ck
                std     ,y++
                puls    b
                sty     tx_out
                puls    a,y,pc

tx_i            fdb     0
tx_cur          fdb     0
tx_out          fdb     0

                include "src/engine/text.s"

                end     start
