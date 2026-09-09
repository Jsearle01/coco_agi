* src/harness/input_probe.s -- a typed line, from the key matrix to the parser. [T-P0-079 AC-4/AC-1]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE WHOLE PATH, IN ONE PROGRAM, because every piece of it is gated separately and none of
* the SEAMS between them is:
*
*     the PIA matrix  ->  HAL_key_scan   (hal_globals.s, 318 B, never executed before this)
*                     ->  gs_keypress    (getstring.s, gated 9/9 against the reference)
*                     ->  txt_dispch     (text.s, gated 9/9 -- the echo appears on screen)
*                     ->  par_clean/par_parse (parser.s, gated at 23,328 cases)
*
* ★★★★ THE DECODER HAS NEVER RUN. P6.22 built it and said so; this is the first program that
* calls it, and it is therefore the first evidence that the matrix table is right rather than
* merely transcribed.
*
* ★★★ THE ECHO IS DRAWN, not just recorded, so this doubles as AC-1's second half: Jay sees the
* characters appear as they are typed. The plane is mapped flat across slots 4-7 exactly as
* text_show.s does it -- src/harness/ keeps its own addresses [memmap.inc's header].
*
* ★ LAUNCH PATH: poke (§4). Records it as `poke`, never as an unqualified pass.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                org     $2000

IP_GO           equ     $0020           ; host: 1 = run
IP_DONE         equ     $0021           ; probe: 1 = a line was entered and parsed
IP_NKEY         equ     $0022           ; probe: how many keys it decoded
IP_EGON         equ     $0023           ; probe: how many words the parser found
IP_LASTK        equ     $0024           ; probe: the last key code decoded (host diagnostic)
IP_NRAW         equ     $0025           ; probe: how many raw scans saw ANY key down

IP_FONT         equ     $3400           ; 2,048 B
IP_VARS         equ     $3C00           ; 256 B
IP_STRINGS      equ     $3D00           ; 13 x 40
IP_INBUF        equ     $4200           ; the input line, 42 B
IP_PBUF         equ     $4300           ; txt_pbuf
IP_VOCAB        equ     $6000           ; WORDS.TOK
IP_CLNBUF       equ     $5F00           ; par_clean's output
IP_EGOLOG       equ     $4600           ; the parsed word numbers, for the host

IP_FB           equ     $8000
IP_FB_LEN       equ     32000

* ★★ The input line sits on row 22, which is where AGI's prompt lives and is the first row a
* backspace may retreat from (text.cpp:316's `row > 21`).
IP_ROW          equ     22
IP_COL          equ     0

start:
                orcc    #$50
                lds     #$3400
* ★★★★★ HAL_input_init FIRST, AND ITS ABSENCE COST THE FIRST RUN. input.s's header states the
* precondition plainly -- "HAL_input_init asserted CR bit 2 = 1 (data mode); BASIC's keyboard DDR
* persists" -- and without it a write to $FF02 lands in the PIA's DATA DIRECTION register instead
* of the port, so no column is ever strobed and $FF00 reads nothing.
* ★★★★ The probe reported NRAW=0: the matrix saw no key at all. **That is the discriminator
* input_gate.lua exists to provide** -- zero raw scans is a hardware-setup problem and non-zero
* raw with zero decoded would have been a table problem, and from the host the two are identical
* symptoms [L-54: attribute separately].
                jsr     HAL_input_init

                ldx     #IP_VARS
                ldb     #0
ip_zv:          clr     ,x+
                decb
                bne     ip_zv

                ldd     #IP_VARS
                std     txt_vars
                ldd     #IP_PBUF
                std     txt_pbuf
                ldd     #IP_FONT
                std     txt_font
                ldd     #IP_FB
                std     txt_fbwin
                clr     txt_fbrow0
                lda     #24
                sta     txt_fbrows
                clr     txt_noblit              ; ★★★ DRAW: this is AC-1's half
                ldd     #0
                std     txt_gcb
                std     txt_ccb
                std     txt_ck
                lda     #40
                sta     txt_maxw
                clrb
                exg     a,b
                std     txt_maxw16
                lda     #2
                sta     txt_rowmin

                ldd     #IP_STRINGS
                std     gs_strings
                ldd     #IP_INBUF
                std     gs_inbuf
                ldd     #IP_VOCAB
                std     par_vocab
                ldd     #IP_INBUF
                std     par_inbuf               ; ★ the parser reads the line in place
                ldd     #IP_CLNBUF
                std     par_clnbuf

                clr     IP_GO
                clr     IP_DONE
                clr     IP_NKEY
                clr     IP_EGON
                clr     IP_NRAW
ip_wait:        lda     IP_GO
                beq     ip_wait

* ── clear the plane, then the palette, in that order [p3b's garbage-before-the-title lesson] ──
                ldx     #IP_FB
                ldd     #0
ip_clr:         std     ,x++
                cmpx    #IP_FB+IP_FB_LEN
                blo     ip_clr
                jsr     agi_pal_load

* ── open the input line: no lead-in, row 22, column 0, 40 characters ──
                ldd     #0
                std     gs_leadin
                lda     #IP_ROW
                sta     gs_row
                lda     #IP_COL
                sta     gs_col
                lda     #40
                sta     gs_maxlen_in
                clr     gs_dest
                clr     gs_cursorchar           ; ★ 0: no cursor glyph, so one key = one event
                clr     gs_editon
                jsr     gs_get_string

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE POLL LOOP, AND THE DEBOUNCE IS THE WHOLE OF IT. HAL_key_scan reports the key that is
* DOWN, so a key held for a thousand scans reports a thousand times. Acting on a CHANGE rather
* than on a state is what turns a level into an event.
* ★★★★ This is the shape cycleInnerLoopActive(CYCLE_INNERLOOP_GETSTRING) has in the engine: spin
* on input WITHOUT advancing the interpreter cycle. **The port's main loop still has no such
* re-entry** -- this probe owns the loop, exactly as getstring.s's split allows [P6.21 §3].
ip_loop:
                jsr     HAL_key_scan
                sta     ip_key
                tsta
                bne     ip_down
* ── nothing down: clear the repeat latch and go round ──
                clr     ip_last
                bra     ip_next
ip_down:
                inc     IP_NRAW
                cmpa    ip_last
                beq     ip_next                 ; still the same key: not a new event
                sta     ip_last
                sta     IP_LASTK
                inc     IP_NKEY
* ★★ ALT is reported as a key so the caller can open the menu; it is not text, so the input line
* ignores it rather than echoing $85 [AD-134: Alt opens the menu, arrows navigate it].
                cmpa    #HAL_KEY_ALT
                beq     ip_next
                jsr     gs_keypress
                tst     gs_done
                bne     ip_entered
ip_next:
                ldx     #400                    ; ★ a scan interval, not a timing claim
ip_dly:         leax    -1,x
                bne     ip_dly
                bra     ip_loop

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ ENTER: hand the line to the parser. **This is the seam the whole task is about** -- the
* buffer gs_keypress filled is the buffer par_parse reads, in place, with no copy between them.
ip_entered:
                jsr     gs_finish
                jsr     par_parse
                lda     par_egon
                sta     IP_EGON
* ── copy the word numbers out for the host ──
                ldx     #par_ego
                ldy     #IP_EGOLOG
                ldb     par_egon
                beq     ip_fin
ip_cp:          lda     ,x+
                sta     ,y+
                lda     ,x+
                sta     ,y+
                decb
                bne     ip_cp
ip_fin:
                lda     #1
                sta     IP_DONE
ip_end:         bra     ip_end

ip_key          fcb     0
ip_last         fcb     0

                include "content/agi_palette.s"
                include "src/engine/text.s"
                include "src/engine/getstring.s"
                include "src/engine/parser.s"
                include "src/hal/coco3-dsk/hal_globals.s"
* ★ input.s is SHARED and is included READ-ONLY here, for HAL_input_init's PIA setup. Nothing in
* it is changed by this task -- the decoder went to hal_globals.s precisely so it would not be.
                include "src/hal/coco3-dsk/input.s"

                end     start
