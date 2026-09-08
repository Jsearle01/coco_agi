* src/harness/gs_probe.s -- run the PORTED get.string over the gate's cases. [T-P0-077 AC-8]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE SAME CASES THE REFERENCE RAN. harness/tools/gs_gate.py emits (lead-in, key list) cases
* and diffs the records this probe writes against tools/agivm/text.py's get_string events. The
* text reference is itself gated against the oracle at 4,594 rectangles and 293,648 glyphs, so
* the chain is 6809 -> Python -> ScummVM.
*
* ★★★★★ WHAT IS AND IS NOT GATEABLE AGAINST THE ORACLE, STATED HERE BECAUSE IT IS A LIMIT AND NOT
* A DETAIL. The printable echo goes through displayCharacter -> drawCharacter and patch 0010 logs
* it, so it is oracle-gateable in principle. **The BACKSPACE is not**: text.cpp:320 clears the
* cell through clearBlock, which contains no drawCharacter, so the oracle's log is silent on it
* [P6.20 §5]. This probe emits a 'C' record for it and the comparison is 6809-against-Python only
* on those. ★★ Extending patch 0010 is one oracleLogText call in clearBlock and is not done here.
*
* ★ Flat map, no framebuffer: txt_noblit is set and the callbacks record instead.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                org     $2000

GP_GO           equ     $0020
GP_DONE         equ     $0021
GP_NCASE        equ     $0022           ; 2 B
GP_RUN          equ     $0024           ; 2 B

GP_VARS         equ     $2D00           ; 256 zeroed variables (%v)
GP_TABLE        equ     $3000           ; logic-0 pointer table, then its text
GP_STRINGS      equ     $4A00           ; the string table, 13 x 40
GP_INBUF        equ     $4C00           ; the input line, 42 B
GP_CASES        equ     $5000           ; case records
GP_PBUF         equ     $9000           ; txt_pbuf
GP_RESULTS      equ     $9400
GP_RES_END      equ     $FE00

* case record:  u16 leadin-offset (into GP_TABLE's text, $FFFF = none)
*               u8 row  u8 col  u8 maxlen  u8 dest  u8 cursorchar
*               u8 nkeys, nkeys x u8
* result record: 'G' row col fg bg u16 cksum   |   'C' row col bg
*                'E' u8 curpos u8 entered u8 nrec-hi u8 nrec-lo   (one per case, LAST)

start:
                orcc    #$50
                lds     #$2C00

                ldx     #GP_VARS
                ldb     #0
gp_zv:          clr     ,x+
                decb
                bne     gp_zv

                ldd     #GP_VARS
                std     txt_vars
                ldd     #GP_PBUF
                std     txt_pbuf
                ldd     #GP_TABLE
                std     txt_l0base
                std     txt_curbase
                ldd     #GP_STRINGS
                std     gs_strings
                ldd     #GP_INBUF
                std     gs_inbuf
                lda     #1
                sta     txt_noblit
                ldd     #gp_glyph
                std     txt_gcb
                ldd     #gp_cell
                std     txt_ccb
                ldd     #0
                std     txt_ck                  ; ★ rolls over the whole run, as both legs do
                std     txt_fbwin
                lda     #2
                sta     txt_rowmin

                clr     GP_GO
                clr     GP_DONE
                ldd     #0
                std     GP_RUN
gp_wait:        lda     GP_GO
                beq     gp_wait

                ldx     #GP_CASES
                stx     gp_cur
                ldy     #GP_RESULTS
                sty     gp_out
                ldd     #0
                std     gp_i
gp_loop:
                ldd     gp_i
                cmpd    GP_NCASE
                lbhs    gp_fin
* ★★ The subtract-don't-add bound, for the reason text_probe.s records: `out + N < END` WRAPS past
* $FFFF and passes exactly when it should fail.
                ldd     #GP_RES_END
                subd    gp_out
                lbmi    gp_fin
                cmpd    #2048
                lblo    gp_fin

                ldx     gp_cur
* ── the lead-in pointer: $FFFF means none ──
                ldd     ,x++
                cmpd    #$FFFF
                bne     gp_lead
                ldd     #0
                bra     gp_lead_set
gp_lead:
                addd    gp_textbase
gp_lead_set:    std     gs_leadin
                lda     ,x+
                sta     gs_row
                lda     ,x+
                sta     gs_col
                lda     ,x+
                sta     gs_maxlen_in
                lda     ,x+
                sta     gs_dest
                lda     ,x+
                sta     gs_cursorchar
                lda     ,x+
                sta     gp_nk
                stx     gp_keys

                ldd     #0
                std     gp_nrec
                clr     gs_editon               ; ★ each case starts from a known edit state
                jsr     gs_get_string
* ── feed the keys ──
                ldx     gp_keys
gp_key_lp:      tst     gp_nk
                beq     gp_key_done
                tst     gs_done
                bne     gp_key_skip
                lda     ,x
                pshs    x
                jsr     gs_keypress
                puls    x
gp_key_skip:    leax    1,x
                dec     gp_nk
                bra     gp_key_lp
gp_key_done:
                stx     gp_cur                  ; -> the next case
                jsr     gs_finish
* ── the per-case record, written AFTER its G/C records (as text_probe.s does) ──
                ldy     gp_out
                lda     #'E
                sta     ,y+
                lda     gs_curpos
                sta     ,y+
                lda     gs_entered
                sta     ,y+
                ldd     gp_nrec
                std     ,y++
                sty     gp_out
                ldd     gp_i
                addd    #1
                std     gp_i
                std     GP_RUN
                lbra    gp_loop
gp_fin:
                ldd     gp_i
                std     GP_RUN
                lda     #1
                sta     GP_DONE
gp_ack:         lda     GP_GO
                bne     gp_ack
                clr     GP_DONE
                lbra    gp_wait

gp_glyph:
                pshs    a,y
                ldy     gp_out
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
                sty     gp_out
                ldd     gp_nrec
                addd    #1
                std     gp_nrec
                puls    a,y,pc

gp_cell:
                pshs    a,y
                ldy     gp_out
                lda     #'C
                sta     ,y+
                lda     txt_crow
                sta     ,y+
                lda     txt_ccol
                sta     ,y+
                lda     txt_bg
                sta     ,y+
                sty     gp_out
                ldd     gp_nrec
                addd    #1
                std     gp_nrec
                puls    a,y,pc

gp_i            fdb     0
gp_cur          fdb     0
gp_out          fdb     0
gp_keys         fdb     0
gp_nrec         fdb     0
gp_textbase     fdb     0               ; host-set: where GP_TABLE's text block starts
gp_nk           fcb     0

                include "src/engine/text.s"
                include "src/engine/getstring.s"

                end     start
