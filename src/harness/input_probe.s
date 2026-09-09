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
* ★★★★★ IP_NRAW DID NOT DISCRIMINATE AND ITS NAME LIED. It was incremented where HAL_key_scan
* RETURNS A KEY, so zero meant "no key was decoded" and not "no key was pressed" -- and those are
* the two causes it was added to separate [§2W]. It is now incremented on RAW PRESSURE, from the
* row mask the scan read, before any table lookup.
IP_NRAW         equ     $0025           ; probe: scans that saw ANY row low, BEFORE decoding
IP_LASTM        equ     $0026           ; probe: the modifier byte from the last decode
IP_ITER         equ     $0027           ; AC-5: timing iterations after the line, 0 = none
IP_PHASE        equ     $0028           ; AC-5: 2 = timing started, $FF = finished
IP_LOOP         equ     $0029           ; 1 = reopen the line after each Enter (interactive)

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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ HAL_sys_init FIRST, AND ITS ABSENCE IS WHY THE SCREEN WAS PINK AND FULL OF '@'.
* It writes **$FF90 = $4C: COCO=0, MMUEN=1** [sys.s step 3]. Until COCO is cleared the GIME is in
* SAM/VDG compatibility translation and **$FF98/$FF99 ARE IGNORED** -- the machine stays in the
* 32x16 text mode, showing whatever is at the VDG text base through DECB's palette. Screen code
* $00 renders as '@', so a cleared page reads as a screen of '@'.
* ★★★★ Jay diagnosed it from the screen: "shows all @ symbols which tells me that it is still in
* text mode". **That is a reading no byte gate here could produce** -- the plane readback was
* correct, because the plane was correct; it simply was not what the GIME was scanning.
* ★★★ p3b_probe.s calls this at its line 188 and its display works. This probe never did.
                jsr     HAL_sys_init
* ★★★★ AND THE MMU BELONGS TO THE GUEST NOW, not the host. HAL_sys_init reprograms all eight
* slots to blocks $38-$3F [sys.s step 4], so any mapping the Lua set before the guest ran is
* overwritten a few instructions in. Slots 4-7 are re-pointed at the framebuffer blocks here,
* after that, which is the only place the ordering is guaranteed.
                lda     #32
                sta     $FFA4                   ; $8000-$9FFF
                lda     #33
                sta     $FFA5                   ; $A000-$BFFF
                lda     #34
                sta     $FFA6                   ; $C000-$DFFF
                lda     #35
                sta     $FFA7                   ; $E000-$FFFF
* ★★★ Mode BEFORE palette [gfx.s Constraint B], then VOFFSET at the same blocks: block 32 is
* physical $40000, and VOFFSET counts eights, so 32 * 1024 = $8000.
                lda     #$80
                sta     $FF98                   ; VMODE  -- mode 2, 320x200x16
                lda     #$3E
                sta     $FF99                   ; VRES
                lda     #$80
                sta     $FF9D                   ; VOFFSET high
                clr     $FF9E                   ; VOFFSET low
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

* ★★★★ AC-5's TIMING ARM SKIPS THE INPUT LINE ENTIRELY. It measures HAL_key_scan, which needs no
* line, no vocabulary and no parser -- and routing it through the full path made it depend on
* par_parse running against an UNSTAGED vocabulary, which is a runaway rather than a measurement.
                lda     IP_ITER
                lbne    ip_fin
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ SET THE TEXT ATTRIBUTE, AND ITS ABSENCE DREW TWELVE GLYPHS IN BLACK ON BLACK.
* cmdGetString does NOT set one -- it inherits whatever the running game last established -- so
* txt_fg and txt_bg sat at their declared 0, txt_blit wrote colour 0 for both the set and the
* clear bits, and every glyph landed as $00 on a plane already full of $00.
* ★★★★ EVERY INTERNAL SIGNAL SAID IT WORKED: txt_ng=12 glyphs emitted, txt_noblit=0, a valid
* window, gs_entered=1, and the port gate green on 432 cases. **The plane was correct and
* invisible** -- which is idiom 19j from the other side, and exactly the class §4A exists for.
* ★★★ (15, 0) is white on black, non-inverted: the attribute the ORACLE's own log shows for
* display text -- patch 0010 records the KQ1 scroll panel as fg15/bg0 [AD-156]. A message box is
* (15, 8), where bit 3 is the invert flag, and that is a different thing.
                lda     #15
                clrb
                jsr     txt_attrib

* ── open the input line: no lead-in, row 22, column 0, 40 characters ──
ip_open:
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
                stb     IP_LASTM
* ★★★★ RAW PRESSURE FIRST, from hal_kb_idx -- which the scan sets whenever ANY row bit was found,
* before the table is consulted. Counting it here rather than after the decode is what makes the
* counter answer the question it was named for.
                pshs    a
                lda     hal_kb_idx
                cmpa    #$FF
                beq     ip_noraw
                inc     IP_NRAW
ip_noraw:       puls    a
                tsta
                bne     ip_down
* ── nothing down: clear the repeat latch and go round ──
                clr     ip_last
                bra     ip_next
ip_down:
                cmpa    ip_last
                beq     ip_next                 ; still the same key: not a new event
                sta     ip_last
                sta     IP_LASTK
                inc     IP_NKEY
* ★★ ALT is reported as a key so the caller can open the menu; it is not text, so the input line
* ignores it rather than echoing $85 [AD-134: Alt opens the menu, arrows navigate it].
                cmpa    #HAL_KEY_ALT
                beq     ip_next
* ★★ The row is cleared when the line is ACCEPTED, not when the next key arrives -- see ip_ackclr.
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ LOOP BACK FOR ANOTHER LINE WHEN IP_LOOP IS SET, and this is the difference between a gate
* and something a person can use. The first version parsed one scripted line and halted at ip_end
* -- correct for an automated check, and it means the operator watches a finished screen rather
* than typing into a live one. Jay: "i thought i was going to be able to enter input."
* ★★★ The parse result is left in IP_EGON/IP_EGOLOG for the host to read, then the line is
* reopened at the same row and the poll loop resumes. **Nothing about the engine changes** -- this
* is the caller owning the inner loop, which is exactly what getstring.s's start/keypress/finish
* split was built for [P6.21].
                tst     IP_LOOP
                beq     ip_fin
                lda     #1
                sta     IP_DONE                 ; the host reads the result, then clears DONE
ip_ack:         tst     IP_DONE
                bne     ip_ack
* ★★★★★ DO **NOT** CLEAR ip_last HERE. It is the debounce latch: while it holds Enter's code, the
* still-pressed Enter is not a new event. Clearing it would make the held key look freshly pressed
* and submit the reopened line empty. The latch clears itself in the poll loop when the key is
* actually released, which is the only event that should clear it.
                clr     IP_NKEY                 ; ★ per-line, so the count means something
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ CLEAR THE ROW **HERE**, ON ENTER, AND THE DEFERRED VERSION WAS THE DEFECT. Deferring the
* clear to the next keystroke was meant to let the operator keep reading the line they had just
* entered. What it actually produced was an input line where **the first Enter changes nothing on
* screen** -- Jay: "the first enter appears to be eaten then when i press enter again the words
* disappear". The second Enter was doing two things at once: supplying the keystroke the deferred
* clear was waiting for, AND submitting an empty line.
*
* ★★★★★ AND THAT EMPTY LINE IS WHAT I SPENT THREE SESSIONS CALLING A PHANTOM. It was a real
* keypress the whole time. **The operator pressed Enter twice because the first one looked
* ignored** -- the defect and the "phantom" were the same defect, seen from two ends.
* ★★★★ THE EXPERIMENT THAT SETTLED IT: post exactly one Enter headlessly. One line, no second
* line. A human at the keys could not produce that control and the console log could not tell the
* two apart, because **nothing in the log distinguished a key the operator pressed from a key the
* probe invented** [§2W: the instrument could not fail in the direction that mattered].
* ★★★ Two counters were built chasing the wrong story -- a zero-scan counter and an inter-line
* timer -- and BOTH returned numbers that cannot be reconciled with the loop's own rate (224 idle
* scans inside a 20 ms window, against a scan interval of ~1.8 ms). They are removed rather than
* left in the tree: a diagnostic whose reading I cannot defend is worse than no diagnostic [§2W.3].
                ldx     #IP_FB+IP_ROW*8*160
ip_ackclr:      clr     ,x+
                cmpx    #IP_FB+IP_ROW*8*160+8*160
                blo     ip_ackclr
                lbra    ip_open

ip_fin:
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AC-5's TIMING LOOP. **The input line does NOT block**, unlike a message box: the engine
* keeps cycling while the player types, so this cost lands in the frame rather than inside a stall
* the player is already in [§3].
* ★★★★ TWO ARMS, differing in ONE thing: whether a key is decoded or the scan comes back empty.
* The idle arm is what every frame pays whether or not anyone is typing; the difference is what a
* keystroke costs on top.
* ★★★ N iterations, no handshake inside the interval, so a fixed overhead cannot be divided into
* the answer [P6.19's "84,626 cycles per glyph for a three-glyph message" lesson].
                lda     IP_ITER
                beq     ip_halt
                sta     ip_n
                lda     #2
                sta     IP_PHASE
ip_time_lp:
                jsr     HAL_key_scan
                dec     ip_n
                bne     ip_time_lp
                lda     #$FF
                sta     IP_PHASE
ip_halt:
                lda     #1
                sta     IP_DONE
ip_end:         bra     ip_end

ip_n            fcb     0

ip_key          fcb     0
ip_last         fcb     0

                include "content/agi_palette.s"
                include "src/engine/text.s"
                include "src/engine/getstring.s"
                include "src/engine/parser.s"
* ★ sys.s is SHARED and included READ-ONLY, for HAL_sys_init's COCO=0 / MMU transition.
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/hal_globals.s"
* ★ input.s is SHARED and is included READ-ONLY here, for HAL_input_init's PIA setup. Nothing in
* it is changed by this task -- the decoder went to hal_globals.s precisely so it would not be.
                include "src/hal/coco3-dsk/input.s"

                end     start
