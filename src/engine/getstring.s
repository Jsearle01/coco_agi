* src/engine/getstring.s -- AGI's get.string and the input line on the 6809. [T-P0-077]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ A TRANSCRIPTION, NOT A REDESIGN, and the chain is checkable end to end:
*
*     gs_get_string  <- text.py get_string       <- op_cmd.cpp cmdGetString
*     gs_edit        <- text.py string_edit      <- text.cpp:936  TextMgr::stringEdit
*     gs_keypress    <- text.py string_key_press <- text.cpp:987  TextMgr::stringKeyPress
*     gs_edit_on/off <- text.py _edit_on/_edit_off <- text.cpp:670/:679
*
* ★★★★ THE LEAD-IN TEXT PATH IS NOT REBUILT. cmdGetString runs stringPrintf -> stringWordWrap(40)
* -> displayText, and all three already exist in text.s and are gated over 4,594 message boxes.
* **This file calls them at max_width 40 instead of 30 and adds nothing.** That is the whole
* reason P6.19's engine was worth building before this one.
*
* ★★★★★ WHERE THE STATE LIVES, AND WHY IT IS SPLIT.
*   - the STRING TABLE (13 x 40) and the INPUT LINE BUFFER (42) are at MAP_STRINGS / MAP_INPUTSTR
*     in the VM state block's tail. **They are VM state**: set.string, word.to.string and
*     get.string write the table and %s reads it, exactly as vars and flags are written and read.
*   - the ten SCALARS below sit with the code, as text.s's do. Putting them at a MAP_ address
*     would cost indexed addressing on every access to save ten bytes in a region that has 387.
*
* ★★★ §2N: this file touches no hardware register. The key SOURCE does (the PIA matrix) and is in
* the HAL, where §2N says it belongs.
* ═══════════════════════════════════════════════════════════════════════════════════════════

GS_MAXLEN       equ     40              ; text.h TEXT_STRING_MAX_SIZE
* ★★★ THE TABLE'S SHAPE IS A CONSTANT HERE AND AN ADDRESS IN memmap.inc, and the two are bound by
* the engine build rather than by this file including the map. text.s learned the same lesson with
* MAP_FONT in P6.19: an engine file that reaches into memmap.inc cannot be assembled by a probe
* with its own flat map, and the probes are how the engine is gated.
* ★★ 13 slots is measured -- harness/tools/string_census.py, 889 logics at 100% coverage, highest
* slot touched is 12. agi.h's own bound is 25.
                ifndef  GS_STR_SLOTS
GS_STR_SLOTS    equ     13
                endc
                ifndef  GS_STR_LEN
GS_STR_LEN      equ     40
                endc
GS_KEY_BS       equ     $08
GS_KEY_ENTER    equ     $0D
GS_KEY_ESC      equ     $1B

* ── caller-supplied ──────────────────────────────────────────────────────────────
gs_strings      fdb     0               ; -> the string table, MAP_STRINGS
gs_inbuf        fdb     0               ; -> the input line buffer, MAP_INPUTSTR
gs_leadin       fdb     0               ; -> the lead-in message, 0 = none
gs_dest         fcb     0               ; which string slot the line lands in
gs_row          fcb     0
gs_col          fcb     0

* ── the ten scalars ──────────────────────────────────────────────────────────────
gs_curpos       fcb     0               ; _inputStringCursorPos
gs_maxlen       fcb     0               ; _inputStringMaxLen
gs_entered      fcb     0               ; _inputStringEntered
gs_cursorchar   fcb     0               ; _inputCursorChar -- 0 for get.string
gs_editon       fcb     0               ; _inputEditEnabled
gs_saverow      fcb     0               ; charPos_Push
gs_savecol      fcb     0
gs_savereset    fcb     0
gs_preved       fcb     0               ; the PREVIOUS edit state, restored not cleared
gs_done         fcb     0               ; the inner loop's exit flag

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ gs_edit_on / gs_edit_off <- text.cpp:670 / :679.
* ★★★★ WITH A CURSOR CHARACTER THESE ARE NOT NO-OPS: every keypress is bracketed by them, so a
* single typed letter emits backspace, letter, cursor -- THREE events, not one. get.string leaves
* the cursor character at 0 and the command-line prompt does not, so the same code produces two
* very different event streams and only one of them is what this task gates.
gs_edit_on:
                tst     gs_editon
                bne     geo_out
                lda     #1
                sta     gs_editon
                lda     gs_cursorchar
                beq     geo_out
                lda     #GS_KEY_BS
                jsr     txt_dispch
geo_out:        rts

gs_edit_off:
                tst     gs_editon
                beq     gef_out
                clr     gs_editon
                lda     gs_cursorchar
                beq     gef_out
                jsr     txt_dispch
gef_out:        rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ gs_keypress <- text.cpp:987. A = the key. Sets gs_done when the loop should end.
gs_keypress:
                sta     gs_key
                jsr     gs_edit_on
                lda     gs_key
                cmpa    #$03                    ; ctrl-c
                beq     gs_clearline
                cmpa    #$18                    ; ctrl-x
                beq     gs_clearline
                cmpa    #GS_KEY_BS
                beq     gs_bs
                cmpa    #GS_KEY_ENTER
                beq     gs_enter
                cmpa    #GS_KEY_ESC
                beq     gs_esc
* ── printable ──
* ★★★★ `_inputStringMaxLen > _inputStringCursorPos`, STRICTLY GREATER, so the buffer fills to
* max_len and the next keystroke is DISCARDED IN SILENCE -- no beep, no echo, no truncation
* marker. Getting this as >= would let one extra character in and the divergence would appear as
* a wrong checksum forty keystrokes later.
                lda     gs_maxlen
                cmpa    gs_curpos
                bls     gs_kp_out
* ★★ The acceptable range is 0x20..0x7F for the default language, not 0x20..0xFF: text.cpp:1056.
                lda     gs_key
                cmpa    #$20
                blo     gs_kp_out
                cmpa    #$7F
                bhi     gs_kp_out
                ldx     gs_inbuf
                ldb     gs_curpos
                abx
                sta     ,x                      ; store the character
                clr     1,x                     ; and keep it NUL-terminated [the P6.19 lesson]
                inc     gs_curpos
                jsr     txt_dispch              ; echo it
                bra     gs_kp_out
gs_bs:
* ★★★ DECREMENT FIRST, THEN DRAW. A backspace on an empty line draws nothing at all, because the
* guard is on the cursor position and not on the drawing.
                tst     gs_curpos
                beq     gs_kp_out
                dec     gs_curpos
                ldx     gs_inbuf
                ldb     gs_curpos
                abx
                clr     ,x
                lda     #GS_KEY_BS
                jsr     txt_dispch
                bra     gs_kp_out
gs_clearline:
                tst     gs_curpos
                beq     gs_kp_out
                dec     gs_curpos
                ldx     gs_inbuf
                ldb     gs_curpos
                abx
                clr     ,x
                lda     #GS_KEY_BS
                jsr     txt_dispch
                bra     gs_clearline
gs_enter:
                lda     #1
                sta     gs_entered
                sta     gs_done
                bra     gs_kp_out
gs_esc:
                clr     gs_curpos
                clr     gs_entered
                ldx     gs_inbuf
                clr     ,x
                lda     #1
                sta     gs_done
gs_kp_out:
                jsr     gs_edit_off
                rts

gs_key          fcb     0

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ gs_edit <- text.cpp:936, the non-RTL branch: echo whatever the caller pre-set, then arm.
gs_edit:
                clr     gs_curpos
                ldx     gs_inbuf
gs_ed_lp:       lda     ,x+
                beq     gs_ed_done
                pshs    x
                jsr     txt_dispch
                puls    x
                inc     gs_curpos
                bra     gs_ed_lp
gs_ed_done:
                lda     gs_maxlen_in
                sta     gs_maxlen
                clr     gs_entered
                jsr     gs_edit_off
                rts

gs_maxlen_in    fcb     0

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ gs_get_string <- op_cmd.cpp cmdGetString. Entry: gs_leadin, gs_row, gs_col, gs_dest and
* gs_maxlen_in set by the caller. Feed keys with gs_keypress until gs_done, then gs_finish.
*
* ★★★★ THE INNER LOOP IS NOT HERE, AND THAT IS THE HONEST SHAPE. The engine calls
* cycleInnerLoopActive(CYCLE_INNERLOOP_GETSTRING) and spins on the event pump WITHOUT advancing
* the interpreter cycle -- a re-entrant loop the port's main cycle does not have, and the same
* shape have.key needs. **Splitting start / keypress / finish lets the caller own that loop**, so
* a probe can drive it from a key list and the VM can drive it from the real pump, and neither has
* to pretend the other's structure.
gs_get_string:
                lda     gs_maxlen_in
                cmpa    #GS_MAXLEN
                bls     gs_gs_len
                lda     #GS_MAXLEN
                sta     gs_maxlen_in
gs_gs_len:
                lda     gs_editon
                sta     gs_preved               ; ★ restored to PREVIOUS, not cleared
                lda     txt_crow                ; charPos_Push
                sta     gs_saverow
                lda     txt_ccol
                sta     gs_savecol
                lda     txt_rcol
                sta     gs_savereset
                clr     gs_done
                jsr     gs_edit_on
* ★★ `if (stringRow < 25)` -- a row of 25 or more leaves the cursor where it was rather than
* clamping. text.cpp does not clamp here and neither does this.
                lda     gs_row
                cmpa    #TXT_ROWS
                bhs     gs_gs_lead
                sta     txt_crow
                lda     gs_col
                sta     txt_ccol
                sta     txt_rcol
gs_gs_lead:
* ── the lead-in, through the ALREADY-GATED text path at width 40 ──
                ldx     gs_leadin
                beq     gs_gs_edit
                stx     txt_msgp
                lda     #40                     ; ★ 40, not the message box's 30
                sta     txt_maxw
                clrb
                exg     a,b
                std     txt_maxw16
                jsr     txt_printf
                ldd     #txt_dispch
                std     txt_emit
                jsr     txt_wrap
                ldd     #0
                std     txt_emit
gs_gs_edit:
                ldx     gs_inbuf                ; stringSet("")
                clr     ,x
                jsr     gs_edit
                rts

* ★★ gs_finish -- setString(dest) and charPos_Pop. Called once the caller's loop ends.
gs_finish:
                lda     gs_dest
                cmpa    #GS_STR_SLOTS
                bhs     gs_fin_pop              ; ★ out of range: drop it rather than write past
                ldb     #GS_STR_LEN
                mul
                ldx     gs_strings
                leax    d,x
                ldu     gs_inbuf
                ldb     #GS_STR_LEN
gs_fin_cp:      lda     ,u+
                sta     ,x+
                beq     gs_fin_pop
                decb
                bne     gs_fin_cp
                clr     -1,x                    ; ★ a full-length line still terminates
gs_fin_pop:
                lda     gs_saverow
                sta     txt_crow
                lda     gs_savecol
                sta     txt_ccol
                lda     gs_savereset
                sta     txt_rcol
                tst     gs_preved
                bne     gs_fin_out
                jsr     gs_edit_off
gs_fin_out:     rts
