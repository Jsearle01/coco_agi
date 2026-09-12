* src/engine/text.s -- AGI's text engine on the 6809: substitute, wrap, place, draw. [T-P0-075]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ A TRANSCRIPTION, NOT A REDESIGN, and the chain is checkable end to end:
*
*     txt_printf   <- text.py string_printf     <- text.cpp:1217 TextMgr::stringPrintf
*     txt_wrap     <- text.py string_word_wrap  <- text.cpp:1095 TextMgr::stringWordWrap
*     txt_msgbox   <- text.py draw_message_box  <- text.cpp:445  TextMgr::drawMessageBox
*     txt_dispch   <- text.py _display_text     <- text.cpp:295  TextMgr::displayText
*     txt_close    <- text.py close_window      <- text.cpp:549  TextMgr::closeWindow
*     txt_attrib   <- text.py char_attrib_ega   <- text.cpp:162  TextMgr::charAttrib_Set
*
* ★★★★ tools/agivm/text.py's header carries one row per structure with its PREDICTED 6809 form
* [§2V]. This file is where the second column is filled, and every place the actual differs from
* the prediction is marked ▲ ACTUAL and says why. Three differ materially and one of those makes
* the port strictly smaller than the prediction.
*
* ★ §2N: this file touches no hardware register in its decision layer. txt_blit writes the
* framebuffer through a caller-supplied window base -- memory, not I/O. Confirmed by measurement:
* reg_discipline.py reports 8 accesses in src/engine, all of them mmu_phase.s's, none of them here.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ §2V's TABLE, SECOND COLUMN FILLED. text.py predicted eleven forms; NINE HELD, TWO DIFFER,
* and TWO MORE were not predicted at all. The two that differ both make the port SMALLER than the
* prediction, and the two unpredicted ones are both "Python carries something a byte does not".
*
*  | structure            | predicted                  | ACTUAL                       | verdict |
*  |----------------------|----------------------------|------------------------------|---------|
*  | the message text     | a POINTER into the LOGIC   | txt_msgp, a pointer. No copy | HELD ★  |
*  |                      | resource; not copied       | anywhere on the path         |         |
*  | wrap output buffer   | a FIXED 2,000-BYTE BUFFER  | ★★★★★ ZERO BYTES. The wrap   | DIFFERS |
*  |                      | ("they cannot share one    | streams to a per-character   |         |
*  |                      | buffer")                   | sink and runs TWICE          |         |
*  | printf output buffer | a SECOND 2,000-byte buffer | 768 B, measured: corpus max  | DIFFERS |
*  |                      |                            | is 490 and 2,000 would not   |         |
*  |                      |                            | fit MAP_RESERVED             |         |
*  | %s / %m recursion    | "either a second staging   | append-in-place with a       | HELD    |
*  |                      | buffer, or an append-in-   | 4-deep cursor stack: 8 BYTES |         |
*  |                      | place rewrite"             | -- the cheaper option named  |         |
*  | box_width/box_height | two bytes                  | two bytes                    | HELD    |
*  | the per-glyph tuple  | four bytes of state mutated| four bytes (crow/ccol/fg/bg) | HELD    |
*  |                      | in place, DP if it can be  | -- NOT in the direct page;   | (mostly)|
*  |                      | had; no allocation         | see the cost note below      |         |
*  | the events list      | DOES NOT EXIST on target   | does not exist; the gate     | HELD    |
*  |                      |                            | probe's callback writes them |         |
*  | the checksum         | "gate-only. The port has   | ★★★★ THE PORT COMPUTES IT,   | DIFFERS |
*  |                      | no reason to compute it"   | in 16 bits not 32 -- and 16  |         |
*  |                      |                            | is EXACT, not an approx      |         |
*  | z, the %015i scratch | 16 B + ~40 B of code       | 16 B + txt_dec3, ~40 B       | HELD ★  |
*  | PrintfState's six    | not closures; direct reads | seven base pointers, 15 B    | HELD    |
*  | "not copied" -- the  | FLAGGED as "the claim most | ★★★ IT HELD. The wrap reads  | HELD    |
*  |   row it flagged     | likely to conceal a copy"  | the printf buffer in place   |         |
*  | -- not predicted --  | (absent)                   | ★★★★★ A NUL TERMINATOR. A    | NEW     |
*  |                      |                            | Python str carries its       |         |
*  |                      |                            | length; a byte buffer does   |         |
*  |                      |                            | not. Its absence cost a      |         |
*  |                      |                            | debugging pass -- see tp_done|         |
*  | -- not predicted --  | (absent)                   | txt_fbrows: how many rows a  | NEW     |
*  |                      |                            | window holds is MAP-dependent|         |
*
* ★★★★ THE TWO "NEW" ROWS ARE THE SAME LESSON TWICE: Python objects carry metadata (a length, a
* bound) that a 6809 array does not, and BOTH omissions produced plausible wrong output rather
* than a crash. §2V.2 lists strings, residency, lookup and unbounded containers; **"a container
* that knows where it ends" belongs on that list and was not on it.**
* ═══════════════════════════════════════════════════════════════════════════════════════════

TXT_HEIGHT_MAX  equ     20              ; text.h:74 HEIGHT_MAX
TXT_COLS        equ     40              ; text.h:69 FONT_COLUMN_CHARACTERS
TXT_ROWS        equ     25              ; text.h:68 FONT_ROW_CHARACTERS
TXT_VW          equ     4               ; text.h:63 FONT_VISUAL_WIDTH
TXT_VH          equ     8               ; text.h:64 FONT_VISUAL_HEIGHT

* ★★★★★ THE SUBSTITUTION BUFFER IS 576 BYTES, AND THE NUMBER IS NOW MEASURED AT FULL COVERAGE.
* ▲ ACTUAL vs §2V's "a FIXED 2,000-BYTE BUFFER ... the port inherits the same bound".
*
* ★★★★ THE FIRST MEASUREMENT DID NOT COVER THE CORPUS AND THE SECOND DOES. harness/tools/
* text_bufmax.py (P6.18) reported "printf max 490" and P6.19 sized 768 from it -- but it walks
* agi.cpp's SWEEP rule, the first eight non-empty texts per logic, which is **4,595 of the
* corpus's 14,944 messages, 31%.** A buffer bound taken over a third of the inputs is not a bound
* [L-85]. harness/tools/subst_census.py re-measures over EVERY message in every logic, and with
* the stricter %m model -- each logic substituting from ITS OWN texts, which is what curLogicNr
* means in gameplay, rather than the sweep's logic 0:
*
*     coverage 14,943 of 14,944 (99.99%)   raw max 490   SUBSTITUTED max 490   wrapped max 474
*     13,612 messages under 128 B; 5 over 384; the longest is larry1 logic 37
*
* ★★★★★ TRIPLING THE COVERAGE DID NOT MOVE THE BOUND, which is the useful result: 490 was right
* and was not known to be right. ★★★ The one message not substituted is a SpaceQuest-2 %m cycle
* that recurses without terminating; it is COUNTED and excluded rather than silently skipped, and
* the port's TXT_SUBMAX cap truncates it where Python cannot.
* ★★ The stricter model earned itself: BlackCauldron's raw maximum is 222 and its SUBSTITUTED
* maximum is 291 -- substitution genuinely expands there, and the gate's logic-0 model cannot see
* it.
*
* ★★★★ SO 576, NOT 768 AND NOT 512. 576 carries 86 bytes over the measured maximum -- 1.18x -- and
* returns 192 bytes to MAP_RESERVED, which is what P6.21 needed to build get.string in. 512 would
* return 256 and leave 22 bytes of margin, 4.5%, on a nine-title sample of a much larger AGI
* universe; that is a worse trade than the 64 bytes it saves.
* ★★★ txt_put REFUSES to write past the end rather than trusting the number, so the failure mode
* for a title outside the corpus is a TRUNCATED message, not a corrupted parser sitting below it.
* ★★★★★ AND THE TRUNCATION IS GATED: TXT_FAULT_PBUF shrinks this below the corpus maximum and the
* text gate must go red. **A buffer sized from a census needs the arm that proves the census
* bounds it** [§2W, and the dispatch's trigger 3].
                ifdef   TXT_FAULT_PBUF
TXT_PBUF_MAX    equ     256             ; ★ AC-6's arm: below the measured 490, so long messages
                else                    ;   truncate and every downstream number moves
TXT_PBUF_MAX    equ     576
                endc

* ★★★ Nesting cap for %s / %m. The oracle recurses without one; a 6809 with a fixed `lds` cannot.
* Measured need in the corpus is 1 (no message's substitution introduces another %m or %s), so 4
* is three deeper than anything observed. txt_push_src REFUSES past it rather than smashing.
TXT_SUBMAX      equ     4

* ── inputs the caller supplies ───────────────────────────────────────────────────
txt_msgp        fdb     0               ; -> the raw message, NUL-terminated, in the arena
txt_pbuf        fdb     0               ; -> TXT_PBUF_MAX scratch for the substituted string
txt_maxw        fcb     30              ; text.cpp:458 -- 30 unless the caller forces a width
txt_rowmin      fcb     2               ; _window_Row_Min (text.cpp:93); 2 for a normal v2 game
txt_wantrow     fcb     $FF             ; -1 = centre vertically
txt_wantcol     fcb     $FF             ; -1 = centre horizontally

* ── what stringPrintf substitutes FROM ───────────────────────────────────────────
* ★★★★ ▲ ACTUAL vs §2V's "NOT closures -- five are direct reads of resident state". Held exactly:
* each is a base pointer to state that is resident anyway, and the sixth (curLogicNr) collapses
* into txt_curbase because the sweep and the VM both resolve it before calling.
* ★★ A message TABLE is an array of 16-bit absolute pointers into the LOGIC resource in the arena
* window -- §2V's "a resource is in BANKED MEMORY, not a dict". Nothing is copied.
txt_vars        fdb     0               ; -> 256 VM variables            (%v)
txt_l0base      fdb     0               ; -> logic 0's pointer table     (%g)
txt_l0n         fcb     0               ;    entries in it
txt_curbase     fdb     0               ; -> current logic's table       (%m)
txt_curn        fcb     0
txt_objbase     fdb     0               ; -> object-name table, 0 = none (%0)
txt_wordbase    fdb     0               ; -> parsed-word table, 0 = none (%w)
txt_strbase     fdb     0               ; -> string table, 0 = none      (%s)

* ── outputs ──────────────────────────────────────────────────────────────────────
txt_boxw        fcb     0               ; textSize_Width,  in CHARACTERS
txt_boxh        fcb     0               ; textSize_Height, in CHARACTERS
txt_srow        fcb     0               ; startingRow
txt_trow        fcb     0               ; textPos.row
txt_tcol        fcb     0               ; textPos.column
txt_bgx         fdb     0               ; backgroundPos_x   -- SIGNED
txt_bgy         fdb     0               ; backgroundPos_y   -- SIGNED, clamped at close
txt_bgw         fdb     0
txt_bgh         fdb     0
txt_ck          fdb     0               ; the rolling checksum -- see txt_hash
txt_ng          fdb     0               ; glyphs emitted for this message

* ── the two hooks, so one build serves the gate and the screen ────────────────────
* ★★★ A GATE PROBE HAS NO FRAMEBUFFER AND A RUNNING GAME HAS NO LOG. Rather than two builds --
* which is how a gate ends up measuring a different program from the one that ships [L-70] --
* the per-glyph decision is emitted through txt_gcb and the pixels through txt_blit, and each is
* independently switchable. **The gate and the screen run the same object code.**
txt_gcb         fdb     0               ; per-glyph callback, 0 = none
txt_ccb         fdb     0               ; per-cell-clear callback (backspace), 0 = none
txt_noblit      fcb     0               ; non-zero = compute, do not draw
txt_fbwin       fdb     0               ; -> the framebuffer window base
txt_fbrow0      fcb     0               ; first CHARACTER row this window covers, see txt_blit
* ★★★★ HOW MANY CHARACTER ROWS THE WINDOW CAN HOLD, AND IT IS A VARIABLE BECAUSE THE ANSWER
* DEPENDS ON THE MAP. Through one 8 KB slice it is 5: a slice is 51.2 pixel rows, the last byte a
* glyph writes is (r+7)*160 + 159, and 5*8+7 = 47 fits where 6*8+7 = 55 does not. Through a probe
* that maps the whole 32,000-byte plane at once it is 24. ★★★ A constant here would have silently
* refused every glyph below row 5 in the second case -- a blank lower screen with no error, which
* is the shape a human notices and a byte gate does not.
txt_fbrows      fcb     5
* ★★ THE FONT BASE IS A POINTER, NOT MAP_FONT INLINED. memmap.inc puts the authored 8x8 font at
* $E0B8 in MAP_TABLES slot 7 -- "resident tables (unchanged)" in BOTH phases, so zero remaps per
* glyph -- and the engine build sets this to MAP_FONT. ★ A probe with its own flat map sets its
* own, which is what keeps text.s free of a dependency on the engine map [§2F: one home, and the
* address's home is memmap.inc].
txt_font        fdb     0

* ── internal state ───────────────────────────────────────────────────────────────
txt_src         fdb     0               ; printf: current source cursor
txt_dst         fdb     0               ; printf: current output cursor
txt_dend        fdb     0               ; printf: one past the end of pbuf
txt_sp          fcb     0               ; printf: %s/%m nesting depth
txt_substk      fill    0,TXT_SUBMAX*2  ; printf: saved source cursors
txt_num         fdb     0               ; printf: the digits after a code
txt_code        fcb     0
txt_zbuf        fill    0,16            ; printf: the "%015i" scratch  [§2V predicted 16 B]

txt_ws          fdb     0               ; wrap: word_start
txt_cr          fdb     0               ; wrap: cur_read
txt_wl          fdb     0               ; wrap: word_len -- 16 BIT, see below
txt_wec         fcb     0               ; wrap: word_end_char
txt_lw          fcb     0               ; wrap: line_width
txt_lwl         fcb     0               ; wrap: line_width_left
txt_emit        fdb     0               ; wrap: per-character sink, 0 = measure only

txt_crow        fcb     0               ; display: current row
txt_ccol        fcb     0               ; display: current column
txt_rcol        fcb     0               ; display: _reset_Column
txt_fg          fcb     0
txt_bg          fcb     0
txt_char        fcb     0               ; the glyph being emitted

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ txt_hash -- the checksum, and ▲ ACTUAL IS 16 BITS WHERE THE ORACLE KEEPS 32.
*
* patch 0010 accumulates `s_textChecksum = s_textChecksum * 31u + character` in a uint32 and logs
* `checksum & 0xFFFF`. ★★★★★ **Only the low 16 bits are ever observable, and multiplication and
* addition are closed modulo 2^16** -- the low half of a product depends only on the low halves of
* its operands -- so a 16-bit accumulator produces the identical sequence. This is exact, not an
* approximation, and it halves the state and removes a 32-bit multiply from the per-glyph path.
* ★★★ 31x is (x<<5) - x: five shifts and a subtract, no multiply at all.
* ★★ A is the character; D and CC are clobbered.
txt_hash:
                pshs    a
                ldd     txt_ck
                pshs    d
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola                    ; D = ck * 32
                subd    ,s++            ; D = ck * 31
* ★★★★ `,s` AND NOT `2,s`. `pshs a` then `pshs d` puts A two bytes down; `subd ,s++` then pops the
* D and leaves A AT ,s. The first draft read 2,s -- the low byte of this routine's own RETURN
* ADDRESS -- so the checksum was a function of where txt_hash was called from. ★★★ It does not
* crash and it does not look wrong: every glyph still gets a checksum, the stream is still
* order-sensitive, and it disagrees with the reference for a reason no position or colour shows.
                addb    ,s              ; ★ the char, zero-extended: B += c, A += carry
                adca    #0
                std     txt_ck
                puls    a,pc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ txt_put -- append A to the substitution buffer, refusing to run past its end.
* ★★★★ §2V.2 says "a 6809 array does not grow -- state the maximum". The maximum is stated at
* TXT_PBUF_MAX and this is what enforces it. **A silent overrun here would corrupt whatever
* MAP_RESERVED holds next**, which is the parser, and the symptom would appear in said().
txt_put:
                pshs    x
                ldx     txt_dst
                cmpx    txt_dend
                bhs     txt_put_full
                sta     ,x+
                stx     txt_dst
txt_put_full:   puls    x,pc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ txt_printf <- text.cpp:1217. THE RECURSION IS GONE AND THIS IS THE §2V ROW THAT MOVED.
*
* PREDICTED: "THE HAZARD ROW ... a 6809 port that recurses straight into one shared output buffer
* CLOBBERS THE CALLER ... Either a second staging buffer, or an append-in-place rewrite that never
* returns a pointer to shared storage."
*
* ▲ ACTUAL: the second option, and it costs EIGHT BYTES rather than a second buffer.
* ★★★★ The oracle recurses because it returns a `char *`; each level builds a whole string and
* hands it up. **But the output is strictly append-only and strictly in order**, so a level's
* contribution is exactly "the bytes it would have appended, in place". Substituting %s or %m is
* therefore not a call at all -- it is a SOURCE SWITCH: push the cursor, point at the referenced
* message, and pop when it terminates. One buffer, no copy, no call depth.
* ★★★ The prediction named this as one of two options and the cheaper one won. It also removes
* the hazard it was written to warn about: there is no caller state to clobber, because there is
* no caller. ★★ TXT_SUBMAX bounds it where the oracle is unbounded.
*
* ★★ %g / %w / %0 are NOT source switches -- text.cpp appends those literally, without recursing
* (:1260, :1264, :1256), so a `%` inside one of them is not a code. Two append paths, both here.
txt_printf:
                ldx     txt_msgp
                stx     txt_src
                ldx     txt_pbuf
                stx     txt_dst
                ldd     #TXT_PBUF_MAX
                leax    d,x
                stx     txt_dend
                clr     txt_sp
* ★★★★★ txt_ck IS **NOT** RESET HERE. patch 0010's `s_textChecksum` is a static that accumulates
* across the whole sweep, and text.py's TextRenderer sets self.checksum once in __init__ -- so the
* checksum is ROLLING OVER THE RUN, not over the message. Clearing it per message would produce a
* stream that is self-consistent, looks entirely reasonable, and disagrees with both.
* ★★ txt_ng is ours and IS per message; nothing compares it.
                ldd     #0
                std     txt_ng
tp_loop:
                ldx     txt_src
                lda     ,x+
                bne     tp_char
* ── end of this source: pop a %s/%m level, or finish ──
                tst     txt_sp
                lbeq    tp_done
                dec     txt_sp
                ldb     txt_sp
                aslb
                ldx     #txt_substk
                abx
                ldx     ,x
                stx     txt_src
                bra     tp_loop
tp_char:
                stx     txt_src
                cmpa    #'%
                beq     tp_pct
                cmpa    #'\
                bne     tp_lit
* ★★★ The escape branch, text.cpp:1283-1288: consume the backslash and take the NEXT character
* literally. ★★★★ The oracle FALLS THROUGH to `resultString += *originalText++` without testing
* for the terminator, so a message ending in a backslash appends the NUL and walks on into the
* next message. **Measured: no message in any of the nine titles ends in a backslash** (65 contain
* one, 63 of them PoliceQuest1's), so the path is unreachable from the corpus -- and this stops,
* which is text.py's documented divergence C, carried across deliberately rather than inherited.
                ldx     txt_src
                lda     ,x+
                beq     tp_loop         ; trailing backslash: stop, do not walk on
                stx     txt_src
tp_lit:
                jsr     txt_put
                bra     tp_loop
* ═══════════════════════════════════════════════════════════════════════════════════════════
tp_pct:
                ldx     txt_src
                lda     ,x+
                lbeq    tp_done         ; a '%' at the very end
                sta     txt_code
                stx     txt_src
                jsr     txt_digits      ; -> txt_num, txt_src advanced
                lda     txt_code
* ★★ All six are LONG branches. The short forms reach in the default build and one of them does
* not once TXT_FAULT_PRINTF adds three bytes -- so an arm that exists to be built would fail to
* assemble, which is a fault arm that cannot be run.
                cmpa    #'v
                lbeq    tp_v
                cmpa    #'0
                lbeq    tp_obj
                cmpa    #'g
                lbeq    tp_g
                cmpa    #'w
                lbeq    tp_w
                cmpa    #'s
                lbeq    tp_s
                cmpa    #'m
                lbeq    tp_m
* ★★ default (text.cpp:1275): the code is consumed and NOTHING is emitted. Real corpus data hits
* this -- %o, %$, %&, %^ and a bare "% " appear across four titles [text_census.py] -- so it is a
* live path, not a defensive one, and it falls straight into the shared digit-skip below.
tp_skipd:
                jsr     txt_digits      ; the outer `while (isdigit)` at text.cpp:1279
                lbra    tp_loop

* ── %v: getVar(i) through "%015i", then a leading-zero strip or a field width ──────
* ★★★ ▲ ACTUAL vs §2V's "16 bytes + a byte-to-decimal routine (~40 B of code)": held, with the
* refinement that the value is a BYTE, so z[0..11] are always '0' and only three digits are ever
* generated. The strip and the width then both reduce to an index into a fixed 15-byte string.
tp_v:
                ldx     txt_vars
                ldb     txt_num+1       ; ★ vars are 256; the low byte is the index
                abx
                lda     ,x
                jsr     txt_dec3        ; -> txt_zbuf, 15 chars, zero-padded
                ldb     #99             ; the sentinel text.cpp:1236 uses
                stb     txt_wid
                ldx     txt_src
                lda     ,x
                cmpa    #'|
                bne     tp_v_strip
                leax    1,x
                stx     txt_src
                jsr     txt_digits
                ldb     txt_num+1
                stb     txt_wid
tp_v_strip:
                lda     txt_wid
                cmpa    #99
                bne     tp_v_width
* leading-zero strip: k = 0; while k < 14 and z[k] == '0': k++
* ★★★★★ AC-4's SUBSTITUTION FAULT, and it is the same one text.py's FAULT_PRINTF injects, so the
* two legs fail the same way for the same reason. Dropping the strip turns "3" into
* "000000000000003": the CHECKSUM moves and so does the WRAP (a 15-digit number wraps differently),
* while everything the wrap itself does stays correct. **It therefore exercises the substitution
* stage specifically, which is what the wrap fault cannot reach** [§2W: two stages, two arms].
                ifdef   TXT_FAULT_PRINTF
                clrb
                bra     tp_v_out
                endc
                clrb
tp_v_zl:        cmpb    #14
                bhs     tp_v_out
                ldx     #txt_zbuf
                abx
                lda     ,x
                cmpa    #'0
                bne     tp_v_out
                incb
                bra     tp_v_zl
tp_v_width:
* k = 15 - width. ★★ The oracle does not bound this: a width above 15 indexes BEFORE the buffer
* (text.cpp:1250 `i = 15 - i`, then `z + i`). Clamped here; no corpus message uses a width at all.
                lda     #15
                suba    txt_wid
                bpl     tp_v_wok
                clra
tp_v_wok:       tfr     a,b
tp_v_out:
                ldx     #txt_zbuf
                abx
tp_v_cp:        lda     ,x+
                lbeq    tp_skipd
                jsr     txt_put
                bra     tp_v_cp

* ── %0 / %g / %w: a LITERAL append from a pointer table, no substitution ──────────
tp_obj:
                ldx     txt_objbase
                lbeq    tp_skipd
                lda     txt_num+1
                bra     tp_lit_tab
tp_g:
                ldx     txt_l0base
                lbeq    tp_skipd
                lda     txt_num+1
                cmpa    txt_l0n
                bhi     tp_skipd        ; ★ 1-based: n > count is out of range
                tsta
                lbeq    tp_skipd        ; ★ and %g0 would index [-1]; the oracle does not check
                bra     tp_lit_tab
tp_w:
                ldx     txt_wordbase
                lbeq    tp_skipd
                lda     txt_num+1
tp_lit_tab:
* A = the 1-based index, X = the table base. Fetch the pointer and copy until NUL.
                tsta
                lbeq    tp_skipd
                deca
                tfr     a,b
                clra
                aslb
                rola
                leax    d,x
                ldx     ,x
                lbeq    tp_skipd
tp_lit_cp:      lda     ,x+
                lbeq    tp_skipd
                jsr     txt_put
                bra     tp_lit_cp

* ── %s / %m: a SOURCE SWITCH, not a call. See the header note above. ──────────────
tp_s:
* ★★ %s does NOT subtract 1 (text.cpp:1267) where %0/%g/%w/%m all do. The single most likely
* transcription slip in this function after the '0'-not-'o' code.
                ldx     txt_strbase
                lbeq    tp_skipd
                ldb     txt_num+1
                aslb
                abx
                ldx     ,x
                lbeq    tp_skipd
                bra     tp_push
tp_m:
                ldx     txt_curbase
                lbeq    tp_skipd
                lda     txt_num+1
                tsta
                lbeq    tp_skipd        ; ★ %m0 -> texts[-1]: THE ORACLE READS IT AND SEGFAULTS
                cmpa    txt_curn        ;   on SpaceQuest-2 message #355 [AD-154]. Not ours to
                lbhi    tp_skipd        ;   reproduce; the sweep skips that message and so does
                deca                    ;   the reference, so this guard is never the difference.
                tfr     a,b
                clra
                aslb
                rola
                leax    d,x
                ldx     ,x
                lbeq    tp_skipd
tp_push:
* X -> the referenced message. Push the cursor that follows the code and switch sources.
                lda     txt_sp
                cmpa    #TXT_SUBMAX
                lbhs    tp_skipd        ; ★ refuse rather than smash; corpus depth is 1
                pshs    x
                jsr     txt_digits      ; consume trailing digits BEFORE saving the cursor
                ldb     txt_sp
                aslb
                ldx     #txt_substk
                abx
                ldu     txt_src
                stu     ,x
                inc     txt_sp
                puls    x
                stx     txt_src
                lbra    tp_loop
tp_done:
* ★★★★★ TERMINATE IT. THE FIRST DRAFT DID NOT, AND THIS IS THE §2V CLASS IN ITS PUREST FORM.
* text.py's `"".join(out)` CARRIES ITS OWN LENGTH; a 6809 byte buffer carries nothing, and
* txt_wrap reads until NUL. Without this store the wrap walked off the end of the substituted
* string into whatever the buffer held from the previous message and kept wrapping until
* box_height hit HEIGHT_MAX.
* ★★★★ THE SYMPTOM NAMED THE WRONG SUBSYSTEM, WHICH IS WHY IT IS WORTH THE PARAGRAPH: every
* rectangle came out 30 wide and 21 tall -- the maximum width and one past the height cap -- and
* the gate reported "box WIDTH and HEIGHT both differ" on message 0. **That reads as a wrapping
* defect and the wrap was correct.** 235,071 glyphs against the reference's 32,105, from a missing
* one-byte store in the stage before it.
* ★★★ It is bounds-checked like every other write: at the very end of a full buffer there is no
* room for the terminator, and truncating one byte earlier is better than terminating outside.
                ldx     txt_dst
                cmpx    txt_dend
                blo     tp_term
                leax    -1,x
tp_term:        clr     ,x
                rts

txt_wid         fcb     0

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ txt_digits -- strtoul over txt_src, leaving the value in txt_num. Non-digits stop it and an
* empty run gives 0, which is exactly what strtoul does and what a bare `%m` relies on.
txt_digits:
                ldd     #0
                std     txt_num
                pshs    x,y
                ldx     txt_src
td_lp:          lda     ,x
                cmpa    #'0
                blo     td_end
                cmpa    #'9
                bhi     td_end
                suba    #'0
                pshs    a
                ldd     txt_num
                aslb
                rola                    ; n*2
                pshs    d
                ldd     txt_num
                aslb
                rola
                aslb
                rola
                aslb
                rola                    ; n*8
                addd    ,s++            ; n*10
                addb    ,s+
                adca    #0
                std     txt_num
                leax    1,x
                bra     td_lp
td_end:         stx     txt_src
                puls    x,y,pc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ txt_dec3 -- A (a byte) as "%015i": twelve '0' then three decimal digits, NUL-terminated.
* ★ Repeated subtraction, not a divide: the 6809 has no divide and three digits is six iterations
* worst case.
txt_dec3:
                pshs    a,b,x
                ldx     #txt_zbuf
                ldb     #12
                lda     #'0
td3_pad:        sta     ,x+
                decb
                bne     td3_pad
                lda     ,s              ; the value back
                ldb     #'0-1
td3_h:          incb
                suba    #100
                bcc     td3_h
                adda    #100
                stb     ,x+
                ldb     #'0-1
td3_t:          incb
                suba    #10
                bcc     td3_t
                adda    #10
                stb     ,x+
                adda    #'0
                sta     ,x+
                clr     ,x
                puls    a,b,x,pc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ txt_wrap <- text.cpp:1095. AND ▲ THE SECOND BUFFER DOES NOT EXIST.
*
* PREDICTED: "A SECOND FIXED 2,000-BYTE BUFFER, DISTINCT FROM THE WRAP'S ... they cannot share
* one buffer because the wrap READS the printf output while WRITING its own."
*
* ▲ ACTUAL: ZERO bytes, because the wrap does not need to write anything. Its output is consumed
* by exactly one thing -- displayText's per-character loop -- so the port STREAMS it: txt_emit is
* a per-character sink and the wrapped string never exists as a string.
* ★★★★ But the geometry must be known BEFORE the glyphs are placed (textPos.row and .column are
* computed from textSize_Height and _Width), so the wrap RUNS TWICE: once with txt_emit = 0 to
* measure, once with the sink attached to place. **1,024 bytes of RAM traded for a second pass
* over at most 490 characters**, and on this machine RAM is the scarce one.
* ★★★ This is the §2V case the table exists to catch, and it went the way the table did not
* predict: the reference's structure was not portable and the port is SMALLER for it, not larger.
*
* ★★ word_len is 16-BIT and line_width is 8. A "word" is a run of non-space characters and the
* corpus's longest message is 490 bytes, so word_len can exceed 255 before it is truncated to
* max_width. line_width cannot: line_width + line_width_left == max_width is invariant.
txt_wrap:
                ldx     txt_pbuf
                stx     txt_ws
                stx     txt_cr
                clr     txt_boxw
                clr     txt_boxh
                clr     txt_lw
                lda     txt_maxw
                sta     txt_lwl
tw_loop:
                ldx     txt_cr
                lda     ,x
                lbeq    tw_tail
* ★ "If first character is a space, skip it, so that we process at least this space" -- and the
* skipped space stays INSIDE word_len, because word_start still points at it. That is what makes
* Gold Rush's "  Lake" keep one of its two spaces.
                cmpa    #$20
                bne     tw_scan
                leax    1,x
tw_scan:
                lda     ,x
                beq     tw_scanend
                cmpa    #$20
                beq     tw_scanend
                cmpa    #$0A
                beq     tw_scanend
                leax    1,x
                bra     tw_scan
tw_scanend:
                sta     txt_wec
                stx     txt_cr
                tfr     x,d
                subd    txt_ws
                std     txt_wl
* ── the wrap test. text.cpp:1141 is `>=`; the fault arm makes it `>`. ──
* ★★ line_width_left is REBUILT as 16 bits on every pass, not cached: it changes inside the loop,
* and a shadow set once at entry would compare against max_width forever -- which passes the first
* word of every line and fails every one after it.
                clra
                ldb     txt_lwl
                std     txt_lwl16
                ldd     txt_wl
                cmpd    txt_lwl16
                ifdef   TXT_FAULT_WRAP
                bls     tw_nowrap       ; ★ FAULT: wraps only when word_len > line_width_left
                else
                blo     tw_nowrap       ;   wraps when word_len >= line_width_left
                endc
* ── the wrapping branch ──
                ldd     txt_wl
                beq     tw_w2
                ldx     txt_ws
                lda     ,x
                cmpa    #$20
                bne     tw_w2
                leax    1,x             ; ★ the leading space is dropped ONLY here
                stx     txt_ws
                ldd     txt_wl
                subd    #1
                std     txt_wl
tw_w2:
                ldd     txt_wl
                cmpd    txt_maxw16
                bls     tw_w3
                subd    txt_maxw16      ; word way too long: split it
                pshs    d
                ldx     txt_cr
                tfr     x,d
                subd    ,s++
                tfr     d,x
                stx     txt_cr
                ldd     txt_maxw16
                std     txt_wl
tw_w3:
                lda     #$0A
                jsr     txt_emitch
                jsr     txt_newline
                lbeq    tw_tail         ; box_height reached HEIGHT_MAX: break out of the LOOP
tw_nowrap:
* ── out.append(text[word_start : word_start + word_len]) ──
* ★★★ word_len FITS IN A BYTE HERE and nowhere else in this routine. On the wrapping branch it has
* just been truncated to max_width; on this branch the test that got here proves
* word_len < line_width_left <= max_width. **The 16-bit form is needed only for the comparison
* that decides the branch**, which is the whole reason txt_wl is a word and txt_lw is a byte.
                ldb     txt_wl+1
                stb     txt_wlb
                stb     tw_cpn
                beq     tw_endch
                ldx     txt_ws
* ★★ The counter is in MEMORY, not in B. txt_emitch calls through to txt_dispch, which calls
* txt_hash, which uses D -- so no register survives the sink and X must be reloaded too.
tw_cp:          stx     tw_cpp
                lda     ,x
                jsr     txt_emitch
                ldx     tw_cpp
                leax    1,x
                dec     tw_cpn
                bne     tw_cp
tw_endch:
* line_width += word_len; line_width_left -= word_len
                lda     txt_lw
                adda    txt_wlb
                sta     txt_lw
                lda     txt_lwl
                suba    txt_wlb
                sta     txt_lwl
* ── if word_end_char == '\n' ──
                lda     txt_wec
                cmpa    #$0A
                bne     tw_next
                ldx     txt_cr
                leax    1,x
                stx     txt_cr
                lda     #$0A
                jsr     txt_emitch
                jsr     txt_newline
                beq     tw_tail
tw_next:
                ldx     txt_cr
                stx     txt_ws
                lbra    tw_loop
tw_tail:
* ★★ THE TAIL IS GUARDED BY cur_read, NOT BY line_width: an all-empty message leaves cur_read at
* the start and must produce a box of height 0, which is a case the sweep really hits.
                ldx     txt_cr
                cmpx    txt_pbuf
                beq     tw_done
                lda     txt_lw
                cmpa    txt_boxw
                bls     tw_t2
                sta     txt_boxw
tw_t2:          inc     txt_boxh
tw_done:
                rts

* ★ close a line: box_width = max(box_width, line_width); box_height++; reset the line.
* Returns Z SET when box_height has reached HEIGHT_MAX, which is the loop's break condition.
txt_newline:
                lda     txt_lw
                cmpa    txt_boxw
                bls     tnl_1
                sta     txt_boxw
tnl_1:          inc     txt_boxh
                clr     txt_lw
                lda     txt_maxw
                sta     txt_lwl
                lda     txt_boxh
                cmpa    #TXT_HEIGHT_MAX
                bhs     tnl_stop
                andcc   #$FB                    ; Z clear: keep going
                rts
tnl_stop:       orcc    #$04                    ; Z set: break
                rts

txt_emitch:
                pshs    x
                ldx     txt_emit
                beq     tec_none
                jsr     ,x
tec_none:       puls    x,pc

* 16-bit shadows of the two 8-bit widths, kept in step by txt_msgbox.
txt_lwl16       fdb     0
txt_maxw16      fdb     0
txt_wlb         fcb     0
tw_cpn          fcb     0
tw_cpp          fdb     0

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ txt_attrib <- text.cpp:162, the EGA branch. Returns the COMBINED pair, which is what
* drawCharacter receives and what the oracle logs -- not the requested one. drawMessageBox asks
* for (0, 15) and every glyph in a box is therefore (15, 8); background 8 is the engine's INVERT
* flag, not a colour [graphics.cpp drawCharacter: `if (background & 0x08)`].
* Entry: A = foreground, B = background.
txt_attrib:
                tstb
                beq     ta_plain
                lda     #15
                ldb     #8
                bra     ta_out
ta_plain:       clrb
ta_out:         sta     txt_fg
                stb     txt_bg
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ txt_msgbox <- text.cpp:445. Substitute, measure, place, then draw.
txt_msgbox:
                lda     txt_maxw
                clrb
                exg     a,b
                std     txt_maxw16      ; the 16-bit shadow the wrap compares against
                jsr     txt_printf
* ── pass 1: measure. txt_emit = 0, so the wrap computes geometry and emits nothing. ──
                ldd     #0
                std     txt_emit
                jsr     txt_wrap
* ── placement, text.cpp:483-503 ──
* ★★★★ startingRow = ((HEIGHT_MAX - height - 1) / 2) + 1, and THE DIVISION IS C's, which
* TRUNCATES TOWARD ZERO. Python's // FLOORS, so tools/agivm/text.py disagrees with the oracle
* whenever the numerator is negative -- height == 20 gives Python -1 and C 0, hence startingRow
* 0 against 1. **Unreachable in the corpus** (the gate matches on all 4,594 rectangles, so no
* message wraps to exactly 20 lines), but the ORACLE is the authority (§2) and this follows it.
* ★★★ Recorded rather than silently matched: the reference has a latent divergence here and a
* title outside the corpus could reach it.
                lda     txt_wantrow
                cmpa    #$FF
                bne     tmb_row_given
                lda     #TXT_HEIGHT_MAX
                suba    txt_boxh
                deca                    ; A = HEIGHT_MAX - height - 1, SIGNED
                bpl     tmb_pos
                nega                    ; |A|
                lsra
                nega                    ; -(|A|/2)  == C's truncation toward zero
                bra     tmb_row_add
tmb_pos:        lsra
tmb_row_add:    inca
                bra     tmb_row_set
tmb_row_given:  lda     txt_wantrow
tmb_row_set:    sta     txt_srow
                adda    txt_rowmin
                sta     txt_trow
* ── column ──
                lda     txt_wantcol
                cmpa    #$FF
                bne     tmb_col_set
                lda     #TXT_COLS
                suba    txt_boxw
                lsra                    ; ★ boxw <= max_width <= 40, so this is never negative
tmb_col_set:    sta     txt_tcol
* ── the background rectangle, text.cpp:500-503 ──
                lda     txt_boxw
                ldb     #TXT_VW
                mul
                addd    #10
                std     txt_bgw
                lda     txt_boxh
                ldb     #TXT_VH
                mul
                addd    #10
                std     txt_bgh
                lda     txt_tcol
                ldb     #TXT_VW
                mul
                subd    #5
                std     txt_bgx
                lda     txt_srow
                ldb     #TXT_VH
                mul
                subd    #5
                std     txt_bgy
* ★★★★★ DRAW THE BOX, HERE, BEFORE THE GLYPHS -- the oracle's order [text.cpp:507 sits between
* the geometry at :500-503 and displayText at :512]. Reversing it would paint the background over
* the text, which is a defect that looks like "the text never rendered".
                ifdef   TEXT_BOX
                jsr     tx_drawbox
                endc
* ── the attribute, then pass 2: place ──
                clra
                ldb     #15
                jsr     txt_attrib      ; charAttrib_Set(0, 15) -> (15, 8)
                lda     txt_trow
                sta     txt_crow
                lda     txt_tcol
                sta     txt_ccol
                sta     txt_rcol        ; _reset_Column, text.cpp:511
                ldd     #txt_dispch
                std     txt_emit
* ★★★★ PASS 2 OVER THE SAME BUFFER. txt_printf is NOT re-run -- the substitution is done once and
* only the wrap repeats, so the second pass costs a scan of at most 490 bytes and no substitution
* work at all. **This is what buys away the 2,000-byte second buffer** (see txt_wrap's header).
                jsr     txt_wrap
                ldd     #0
                std     txt_emit
* ★★ window_Active = true [text.cpp:509], set AFTER the box is on screen so txt_close can only
* restore a rectangle that was actually drawn.
                ifdef   TEXT_BOX
                lda     #1
                sta     txt_winactive
                endc
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ txt_dispch <- text.cpp:295 displayText + :307 displayCharacter. A = the character.
* ★★ The engine RECURSES with 0x0D rather than wrapping inline when a column runs past 39; the
* effect is identical and this does it inline.
txt_dispch:
* ★★★★★ THE BACKSPACE ARM, ADDED P6.21 FOR THE ECHO. text.cpp:313-322: step back one cell (or to
* the end of the previous row, but ONLY when row > 21), clear that cell, and draw nothing.
* ★★★ It is safe to add here rather than in a separate routine because a WRAPPED MESSAGE NEVER
* CONTAINS 0x08 -- the wrap emits only the message's own bytes and newlines -- so the message path
* cannot reach this branch and the text gate's 4,594 rectangles are unaffected. The gate re-run is
* what checks that claim rather than this sentence.
* ★★★★ patch 0010 DOES NOT LOG THIS. The engine's backspace calls clearBlock, which contains no
* drawCharacter, so the oracle's decision log is silent on it [P6.20 §5]. The port emits a 'C'
* record so the two legs are comparable to each other; against the ORACLE it is ungated, and that
* is stated rather than papered over.
                cmpa    #$08
                beq     tdc_bs
                cmpa    #$0A
                beq     tdc_nl
                cmpa    #$0D
                beq     tdc_nl
                sta     txt_char
                jsr     txt_hash
                jsr     txt_putglyph
                inc     txt_ccol
                lda     txt_ccol
                cmpa    #TXT_COLS
                blo     tdc_ret
tdc_nl:
                lda     txt_crow
                cmpa    #TXT_ROWS-1
                bhs     tdc_col
                inc     txt_crow
tdc_col:        lda     txt_rcol
                sta     txt_ccol
tdc_ret:        rts
* ── the backspace arm ──
tdc_bs:
                lda     txt_ccol
                beq     tdc_bs_row
                deca
                sta     txt_ccol
                bra     tdc_bs_clr
tdc_bs_row:
* ★★ `else if (charCurPos.row > 21)` -- STRICTLY 21, and only then does it wrap to the previous
* row. At row 21 or above-left the POSITION does not move: the input line lives at rows 22-24 and
* cannot back up into the play area.
                lda     txt_crow
                cmpa    #22
                blo     tdc_bs_clr              ; ★ fall through to the CLEAR, do not skip it
                lda     #TXT_COLS-1
                sta     txt_ccol
                dec     txt_crow
tdc_bs_clr:
* ★★★★★ THE CLEAR IS UNCONDITIONAL, AND THE FIRST DRAFT MADE IT CONDITIONAL. text.cpp:313-322 puts
* `clearBlock(...)` AFTER the if/else-if, not inside either arm -- so a backspace at column 0 of
* row 0, where neither arm moves the cursor, still clears the cell it is sitting on.
* ★★★★ The gate found it on case 0 event 0: the reference emitted a cell-clear at (0,0) and the
* port emitted the first GLYPH instead, because get.string's opening inputEditOn sends a backspace
* whenever a cursor character is set. **A branch that skipped the clear looked like a missing
* event and was a missing SIDE EFFECT** -- the position was right either way.
                jsr     txt_cellcb              ; the 'C' record, for the gate
                tst     txt_noblit
                bne     tdc_bs_done
                jsr     txt_clearcell
tdc_bs_done:    rts

* ★★ txt_cellcb -- the per-CLEAR callback, the backspace twin of txt_gcb.
txt_cellcb:
                pshs    x
                ldx     txt_ccb
                beq     tcc_none
                jsr     ,x
tcc_none:       puls    x,pc

txt_putglyph:
                ldd     txt_ng
                addd    #1
                std     txt_ng
                ldx     txt_gcb
                beq     tpg_blit
                jsr     ,x
tpg_blit:
                tst     txt_noblit
                bne     tpg_ret
                jsr     txt_blit
tpg_ret:        rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ txt_close <- text.cpp:549. The restore rectangle, with the y CLAMPED to >= 0.
* ★★ print.at with y = 0 puts the border over the menu bar and backgroundPos_y goes negative;
* the engine clamps before render_Block and the log records the CLAMPED value (bugs #13820,
* #15241 -- MixedUpMotherGoose's nursery rhymes are the corpus case).
* ★★★★★ txt_restore -- THE RESTORE, AS A VECTOR THE CALLER INSTALLS.
* The oracle closes a window by RE-RENDERING a rectangle of the game screen into the display
* screen: "There is no save-under buffer anywhere" [text.cpp:560-564, this project's own oracle
* instrumentation at P6.15]. Nothing is saved and nothing is copied back.
* ★★★★ THE ENGINE CANNOT NAME THE PORT'S VERSION OF THAT. Our game screen is the SHADOW plane and
* our display screen is the VISIBLE plane, and both are the probe's block model, not text.s's. So
* this is a vector, the same idiom txt_emit already uses in this file -- the probe installs its
* routine and the engine stays independent of how planes are mapped.
* ★★ Zero = no restore, which is what text_probe and gs_probe want: they have no framebuffer.
txt_restore     fdb     0
* ★★★ window_Active [text.cpp:550, `if (_messageState.window_Active)`]. The oracle guards the
* restore on it, and so must we: txt_close is reachable without a box having been drawn, and the
* rectangle it would restore is then whatever the LAST box left in txt_bgx/bgy/bgw/bgh. **A
* restore of a stale rectangle repaints a region nothing asked for**, which reads as a flicker in
* an unrelated part of the screen.
txt_winactive   fcb     0

txt_close:
                ldd     txt_bgy
                bpl     tc_ok
                ldd     #0
                std     txt_bgy
tc_ok:
                tst     txt_winactive
                beq     tc_out
                clr     txt_winactive
                ldx     txt_restore
                beq     tc_out
                jsr     ,x
tc_out:         rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ tx_drawbox <- graphics.cpp:1079 GfxMgr::drawBox, called from text.cpp:507.
*
* ★★★★★ THIS WAS MISSING ENTIRELY AND NO BYTE GATE COULD SEE IT. txt_msgbox computed
* txt_bgx/bgy/bgw/bgh exactly right -- the text gate matches the oracle on 4,594 rectangles -- and
* then drew only the glyphs. **The geometry was gated; the DRAW was never written.** Jay, on the
* eye gate: "i'm not actually seeing a box, at least not like i'd expect in a sierra game. just
* the text." ★★★★ Same shape as AD-114: a gate comparing numbers cannot see a missing draw call,
* and this is the second time this subsystem has needed a person to find that.
*
* ★★★★ THE ORACLE'S COLOURS, NOT CHOSEN ONES: `drawBox(..., 15, 4)` with its own comment
* "Hardcoded colors: white background and red lines". One AGI pixel is one byte with both nibbles
* equal [design §2.1, 2 px/byte], so 15 is $FF and 4 is $44.
*
* ★★★★★ THE BORDER GEOMETRY IS THE `default:` ARM (EGA/CGA/VGA/AtariST), graphics.cpp:1119-1122,
* and it is expressed in DISPLAY pixels -- i.e. AFTER translateVisualRectToDisplayScreen has
* doubled x and width. Our framebuffer is 2 display pixels per byte, so a display offset of +2 is
* +1 byte and a display width of 2 is 1 byte. Converted once, here, rather than at four sites:
*     top     x+1,      y+1,      w-2,  1
*     bottom  x+1,      y+h-2,    w-2,  1
*     left    x+1,      y+2,      1,    h-4
*     right   x+w-2,    y+2,      1,    h-4
* ★★★ Vertical is 1:1 (TXT_VH=8 is already display rows), so y is used unscaled.
*
* ★★ Gated on txt_noblit, the switch this file already uses for the glyphs: text_probe and
* gs_probe have no framebuffer and set it, so they keep comparing geometry and draw nothing.
* ★★★★★ BEHIND -DTEXT_BOX, AND NOT BECAUSE IT IS OPTIONAL -- BECAUSE IT DOES NOT FIT.
* Measured: with the box in, P3_CODE_END reaches $5830 against a font at $5800. **48 bytes over**,
* and p3b_probe.s:1275's assert is what says so rather than the code silently overwriting glyphs.
* ★★★★ THE MAP IS FULL, not merely tight. $2000-$6000 is 16,384 bytes and holds 14,384 of code
* plus the 2,048-byte font. Slot 0 is allocated end to end (status, seed stack, hw stack, the
* 2 KB VM state block, 3 KB of DIR tables, MAP_INPUT). Slot 7 holds the parser at $E000 and a
* vocabulary window with 138 bytes of slack against its own 6,828-byte floor. **There is nowhere
* to put 2 KB of font and nowhere to take 48 bytes from without a decision about the map.**
* ★★★ So the flag is a holding position, not a feature switch: the code is written, reviewed
* against the oracle and compact (three rects, a 15-byte table), and it turns on the moment 48
* bytes exist. Left OFF so p3b_text keeps building and no gate moves [§22.5 -- where the fix
* belongs is a memory-map decision, not one to take inside this change].
                ifdef   TEXT_BOX
TXF_BG          equ     $FF             ; colour 15, both nibbles
TXF_LINE        equ     $44             ; colour 4

* ★★ WIDTH AND HEIGHT ARE BYTES, X AND Y ARE SIGNED WORDS, and the asymmetry is measured rather
* than assumed: bgw = boxw*4+10 <= 170 and bgh = boxh*8+10 <= 170, both inside a byte, while
* bgx = tcol*4-5 and bgy = srow*8-5 go NEGATIVE when the box starts at column or row 0 [the
* MixedUpMotherGoose print.at case txt_close already clamps for]. §2V.2: state the maximum.
txf_x           fdb     0               ; BYTE column, signed
txf_y           fdb     0               ; PIXEL row, signed
txf_w           fcb     0
txf_h           fcb     0
txf_val         fcb     0
txf_wy          fdb     0               ; working row, so the caller's txf_y survives
txf_ylo         fdb     0               ; first/last pixel row this window covers
txf_yhi         fdb     0

* tx_boxfill: A = byte value; rectangle in txf_x (BYTE column), txf_y (PIXEL row), txf_w, txf_h.
* ★★★★ ROWS OUTSIDE THE WINDOW ARE SKIPPED, NOT CLAMPED, and the bound is txt_blit's own: a slice
* holds txt_fbrows character rows starting at txt_fbrow0. **A fill that can run past its window
* will**, and it would land in whatever the MMU has next -- the class of defect that cost
* AD-111's 2-byte clear and AD-121's wrap.
tx_boxfill:
                sta     txf_val
                ldd     txt_fbwin
                beq     txf_out                 ; no framebuffer mapped
* ★★ A NEGATIVE COLUMN IS CLAMPED, NOT WRAPPED. bgx reaches -5; left uncorrected, `addd txf_x`
* would step BACK off the row start and paint the tail of the row above.
                ldd     txf_x
                bpl     txf_xok
                clr     txf_x
                clr     txf_x+1
txf_xok:
                lda     txt_fbrow0
                ldb     #TXT_VH
                mul
                std     txf_ylo                 ; first pixel row in this window
                lda     txt_fbrows
                inca
                ldb     #TXT_VH
                mul
                addd    txf_ylo
                std     txf_yhi                 ; one past the last
                ldd     txf_y
                std     txf_wy
txf_rows:
                lda     txf_h
                beq     txf_out
                deca
                sta     txf_h
                ldd     txf_wy
* ★★★ SIGNED compares: txf_wy is negative for a box that starts above the screen, and an unsigned
* test would read -5 as 65531 and call it "below the window" -- right answer, wrong reason, and
* wrong the moment the window stops starting at row 0.
                cmpd    txf_ylo
                blt     txf_next
                cmpd    txf_yhi
                bge     txf_next
                subd    txf_ylo
* ★★ ONE MUL, not a shift chain: the row within a window is under 256, so row*160 fits D directly.
                tfr     b,a
                ldb     #160
                mul
                addd    txf_x
                addd    txt_fbwin
                tfr     d,x
                ldb     txf_w
                beq     txf_next
                lda     txf_val
txf_b:          sta     ,x+
                decb
                bne     txf_b
txf_next:
                ldd     txf_wy
                addd    #1
                std     txf_wy
                bra     txf_rows
txf_out:        rts

* ★★★★★ THREE RECTANGLES, NOT FIVE, AND IT IS EXACTLY EQUIVALENT -- not an approximation.
* The oracle draws a background and four inset lines. Filling the frame SOLID and then hollowing
* it out leaves precisely the same pixels:
*     1. background   (x,   y,   w,   h  )  white
*     2. frame block  (x+1, y+1, w-2, h-2)  red
*     3. hollow       (x+2, y+2, w-4, h-4)  white
* What survives red is the border of (2): the top row, the bottom row, and one byte down each
* side between them -- byte for byte the four rects at graphics.cpp:1119-1122, converted from
* display pixels to our 2-px bytes. ★★★★ Checked rather than eyeballed: the oracle's left line is
* x+2disp..x+3disp = byte x+1, rows y+2..y+h-3; (2)-minus-(3) gives byte x+1, rows y+2..y+h-3.
*
* ★★★ IT IS ALSO WHAT MADE IT FIT. Five inline setups cost 118 bytes more than MAP_RESERVED has
* left before the font, and the assert at p3b_probe.s:1275 caught that rather than letting the
* code silently overwrite glyphs. The table costs 15 bytes and the loop 35.
txb_n           fcb     0
txb_yoff        fdb     0               ; txt_rowmin * TXT_VH, added when the box is DRAWN
txb_tab         fcb     0,0,0,0,TXF_BG          ; dx, dy, dw, dh, colour
                fcb     1,1,-2,-2,TXF_LINE
                fcb     2,2,-4,-4,TXF_BG

tx_drawbox:
                tst     txt_noblit
                bne     txf_out
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE WINDOW OFFSET IS ADDED AT DRAW TIME, NOT STORED. txt_bgy is srow*8-5 and the GLYPHS
* go at txt_trow = txt_srow + txt_rowmin -- so the box and the text are in different spaces, and
* without this the box lands txt_rowmin*8 = 16 pixels ABOVE the text it is supposed to contain.
* Jay, on the eye gate: "i see the box with the same text underneath it."
* ★★★★ THE ORACLE DOES EXACTLY THIS AND AT EXACTLY THIS POINT: backgroundPos_y is stored in
* game-screen coordinates [text.cpp:503] and drawBox adds the offset when it draws
* [graphics.cpp:1089, `y = y + _renderStartDisplayOffsetY`]. **So the fix is to match the oracle's
* split, not to change the stored value.**
* ★★★ WHICH ALSO KEEPS THE GATE HONEST: txt_bgy is what text_probe compares, and it matches the
* oracle on 4,594 rectangles. Folding the offset into it would have "fixed" the screen by breaking
* the comparison -- the geometry was never wrong, only the space it was drawn in.
                lda     txt_rowmin
                ldb     #TXT_VH
                mul
                std     txb_yoff
                ldu     #txb_tab
                lda     #3
                sta     txb_n
txb_loop:
* ★★ `sex` sign-extends B into A, which is what makes a one-byte signed delta table legal for a
* 16-bit coordinate -- dw and dh are negative.
                ldb     ,u+
                sex
                addd    txt_bgx
                std     txf_x
                ldb     ,u+
                sex
                addd    txt_bgy
                addd    txb_yoff        ; ★ the window offset, applied at DRAW time
                std     txf_y
                ldb     ,u+
                addb    txt_bgw+1
                stb     txf_w
                ldb     ,u+
                addb    txt_bgh+1
                stb     txf_h
                lda     ,u+
                jsr     tx_boxfill              ; ★ leaves U alone; it uses D and X only
                dec     txb_n
                bne     txb_loop
                rts
                endc                    ; TEXT_BOX

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ txt_blit -- the 8x8 glyph into the 320x200x16 framebuffer. NOT modelled by the reference.
*
* ★★★★ THE REFERENCE MODELS POSITIONS, NOT PIXELS, DELIBERATELY [text.py's TextRenderer docstring]
* -- so this half has no Python to transcribe and no byte gate can reach it. **It is what AC-1's
* eye gate is for**, and it is the only part of this file whose evidence is a human looking at it.
*
* ★★★ THE MAP: 320x200x16 is 4 bits per pixel, 2 pixels per byte, 160 bytes per row [design §2.1].
* A character cell is 8 pixels wide = 4 BYTES, and 8 rows tall. The font at MAP_FONT is 1 bit per
* pixel, 8 bytes per glyph, so each font byte expands to 4 framebuffer bytes.
*
* ★★★★ THE WINDOW IS 8,192 BYTES AND A ROW IS 160, SO A SLICE COVERS 51.2 ROWS -- the boundary
* does NOT fall on a character row. A glyph at pixel row 408 straddles two slices. This routine
* therefore takes the window base AND the pixel row that base corresponds to, and REFUSES a glyph
* that would cross the end of the window rather than wrapping into the wrong block.
* ★★ That refusal is the honest form for this task: the caller (§3's eye probe) maps the slice the
* status/message rows live in. A general text engine needs the caller to remap per straddle, which
* is a phase question (§2R.1) and belongs with the display driver, not here.
*
* ★ Invert: background bit 3 set means "draw the glyph inverted" -- the font bits are XOR'd, so a
* set bit takes the BACKGROUND colour and a clear bit the foreground. (15, 8) is therefore black
* text on the white message box, which is what a message box looks like.
* ★★★ txt_clearcell -- clearBlock over ONE character cell (text.cpp:320's backspace). It is
* txt_blit with the font replaced by a constant: same window bound, same address arithmetic, four
* bytes of background per row for eight rows. ★★ Sharing the addressing rather than copying it is
* the point -- a second copy of "(crow - fbrow0) * 8 * 160 + ccol * 4" is a second place for the
* straddle bound to be got wrong.
txt_clearcell:
                pshs    a,b,x
                lda     txt_bg
                anda    #$07                    ; the invert bit is not a colour
                sta     tb_acc
                lda     tb_acc
                lsla
                lsla
                lsla
                lsla
                ora     tb_acc
                sta     tb_acc                  ; both nibbles = the background colour
                jsr     txt_celladdr
                beq     tcl_out
                ldb     #8
tcl_row:        lda     tb_acc
                sta     ,x
                sta     1,x
                sta     2,x
                sta     3,x
                leax    160,x
                decb
                bne     tcl_row
tcl_out:        puls    a,b,x,pc

* ★★ txt_celladdr -- X = the cell's top-left byte, Z CLEAR on success and Z SET when the cell is
* outside this window. Factored out of txt_blit so the clear cannot drift from the draw.
txt_celladdr:
                ldx     txt_fbwin
                beq     tca_no
                lda     txt_crow
                suba    txt_fbrow0
                bmi     tca_no
                cmpa    txt_fbrows
                bhi     tca_no
                ldb     #160
                mul
                aslb
                rola
                aslb
                rola
                aslb
                rola
                std     tb_off
                lda     txt_ccol
                ldb     #TXT_VW
                mul
                addd    tb_off
                leax    d,x
                andcc   #$FB                    ; Z clear = usable
                rts
tca_no:         orcc    #$04                    ; Z set = refused
                rts

txt_blit:
                pshs    a,b,x,y,u
                ldx     txt_fbwin
                lbeq    tb_out
* ── the bound, and it is arithmetic rather than a guess ──
* A slice is 8,192 B at 160 B per pixel row = 51.2 rows. The LAST byte this glyph writes is
* (r+7)*160 + ccol*4 + 3 with ccol at most 39, i.e. (r+7)*160 + 159 <= 8191, so r <= 43 pixel
* rows into the window -- FIVE character rows, not six-and-a-bit. Anything past that is refused.
                lda     txt_crow
                suba    txt_fbrow0
                lbmi    tb_out                  ; the row is above this window
                cmpa    txt_fbrows
                lbhi    tb_out
* offset = (crow - fbrow0) * 8 * 160 + ccol * 4. ★ 8*160 = 1,280 does not fit MUL's 8x8 form, so
* it is done as (rows * 160) shifted left three times rather than with one multiply.
                ldb     #160
                mul                             ; D = (crow - fbrow0) * 160, at most 800
                aslb
                rola
                aslb
                rola
                aslb
                rola                            ; D *= 8  -> at most 6,400
                std     tb_off
                lda     txt_ccol
                ldb     #TXT_VW
                mul                             ; D = ccol * 4, at most 156
                addd    tb_off
                leax    d,x                     ; X -> the glyph's top-left byte
* U -> the font bytes
                ldu     txt_font
                beq     tb_out
                lda     txt_char
                ifdef   TEXT_FONT128
* ★★★★★ FOLD >= 128 TO SPACE. The font is 128 glyphs [p3b_probe.s, with the census], so an index
* above 127 would read past it -- into whatever follows P3_FONT.
* ★★★★ SPACE, NOT `anda #$7F`. The mask is one byte cheaper and WRONG: the only high codepoint in
* the corpus is 255, whose glyph is blank, and masking sends it to 127, whose glyph is not. Fifteen
* blanks in Kingquest2 would become fifteen visible marks. Folding to 32 renders 255 exactly right.
                cmpa    #$80
                blo     tb_glyph
                lda     #$20
tb_glyph:
                endc
                ldb     #8
                mul
                leau    d,u
* ── invert, and the background COLOUR is the attribute with the invert bit removed ──
* graphics.cpp drawCharacter: `if (background & 0x08) { background &= 0x07; transformXOR = 0xFF; }`
                lda     txt_bg
                tfr     a,b
                andb    #$07
                stb     txt_bgc
                anda    #$08
                sta     tb_inv
                ldb     #8
                stb     tb_line
tb_row:
                lda     ,u+
                tst     tb_inv
                beq     tb_norm
                coma
tb_norm:        sta     tb_bits
                ldb     #4
                stb     tb_pair
tb_pairlp:
* two pixels per byte: bit 7 -> high nibble, bit 6 -> low nibble
                clrb
                lsl     tb_bits
                bcc     tb_p1z
                ldb     txt_fg
                bra     tb_p1d
tb_p1z:         ldb     txt_bgc
tb_p1d:         lslb
                lslb
                lslb
                lslb
                stb     tb_acc
                clrb
                lsl     tb_bits
                bcc     tb_p2z
                ldb     txt_fg
                bra     tb_p2d
tb_p2z:         ldb     txt_bgc
tb_p2d:         andb    #$0F
                orb     tb_acc
                stb     ,x+
                dec     tb_pair
                bne     tb_pairlp
                leax    156,x                   ; 160 - 4: next pixel row
                dec     tb_line
                bne     tb_row
tb_out:
                puls    a,b,x,y,u,pc

tb_off          fdb     0
tb_bits         fcb     0
tb_inv          fcb     0
tb_line         fcb     0
tb_pair         fcb     0
tb_acc          fcb     0
txt_bgc         fcb     0               ; the background COLOUR (bg with the invert bit removed)
