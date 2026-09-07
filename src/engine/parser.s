* src/engine/parser.s -- AGI's parser on the 6809: tokenise input, match said(). [T-P0-059]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ A TRANSCRIPTION, NOT A REDESIGN. tools/agivm/parser.py's header carries one row per
* structure with its 6809 form and its cost [P6.2 §3.E], written before this file existed so the
* port would be a transcription. Each routine below names the Python function it transcribes and
* the oracle line that function transcribes, so the chain is checkable end to end:
*
*     par_clean   <- parser.py clean_up_input         <- words.cpp:218 cleanUpInput
*     par_find    <- parser.py Vocabulary.find        <- words.cpp:250 findWordInDictionary
*     par_parse   <- parser.py parse_using_dictionary <- words.cpp:326 parseUsingDictionary
*     par_said    <- parser.py test_said              <- op_test.cpp:318 testSaid
*
* ★★★★ THE VOCABULARY IS THE RESOURCE, IN PLACE. No index is built and no copy is made:
* WORDS.TOK is already an index -- 26 big-endian head offsets, then alphabetically sorted
* prefix-compressed runs -- so this walks the file the way the oracle walks its buckets.
* ★★★ RESIDENCY, MEASURED: the largest WORDS.TOK in the corpus is SpaceQuest-2 at 6,828 bytes
* and all twelve are under 8,192, so ONE window holds any of them. Unlike AD-78's arena, where
* the largest LOGIC exceeded a window and forced a two-slot design, this needs one slot.
*
* ★★★ WHY NOT A HASH OR A SORTED INDEX: the oracle's rule is "the LAST full match in bucket
* order wins", and bucket order is file order. Any structure that reorders entries changes which
* one wins. **The portable shape and the correct shape are the same shape here**, which is worth
* stating because L-66, L-67 and AD-88 are all cases where they were not.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★ §2N: this file touches no hardware register. It is pure computation over two buffers.

PAR_MAX_WORDS   equ     20              ; agi.h:81 MAX_WORDS
PAR_UNKNOWN     equ     $FFFF           ; words.h:27 DICTIONARY_RESULT_UNKNOWN (-1)
PAR_IGNORE      equ     0               ; words.h:28 DICTIONARY_RESULT_IGNORE
PAR_SPACE       equ     $20             ; ★ named: a bare #' literal loses its space to any
                                        ;   tool that trims trailing whitespace, and one did

* ── inputs the caller supplies ───────────────────────────────────────────────────
par_vocab       fdb     0               ; -> WORDS.TOK, in its window
par_inbuf       fdb     0               ; -> the raw input, NUL-terminated
par_clnbuf      fdb     0               ; -> scratch for the cleaned, lowercased input

* ── outputs ──────────────────────────────────────────────────────────────────────
* ★★ `fill 0,N` rather than `rmb N`, and the reason is NOT the one first written here. I claimed
* rmb emits nothing in --format=raw and shifts everything after it; **the binary is 1,047 bytes
* either way, so lwasm does emit it** and that claim was wrong. `fill` is kept only because an
* explicitly-zeroed buffer is worth more than an implicitly-zeroed one when the loader stages
* over it. ★ The actual defect that looked like this was a byte-order mismatch in the reader
* [parser_gate.lua], not a layout one.
par_ego         fill    0,PAR_MAX_WORDS*2 ; word NUMBERS, 20 x u16  [§3.E: 40 bytes]
par_egon        fcb     0               ; how many are valid
par_notfound    fcb     0               ; VM_VAR_WORD_NOT_FOUND, 1-based, 0 = none
par_cli         fcb     0               ; VM_FLAG_ENTERED_CLI
par_accepted    fcb     0               ; VM_FLAG_SAID_ACCEPTED_INPUT

par_cl_src      fdb     0
par_cl_dst      fdb     0

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ par_is_sep / par_is_inv -- words.cpp:184 / :205. A is the char; Z set = yes.
* ★★★ A IS PUSHED, NOT B, AND THE ORDER IS WHY. PSHS stacks in the fixed order PC,U,Y,X,DP,B,A,CC
* -- A lands at ,s only if B is NOT also pushed. `pshs x,b` would put B at ,s and the compare
* would test the caller's B against the table. ★★ B is clobbered by design (it carries the table
* byte); callers do not rely on it.
* ★★★★★ HEX, NOT CHARACTER LITERALS, AND THE ASSEMBLED BYTES ARE WHY. Written as
*     fcb  PAR_SPACE,",",".","?",...
* lwasm emitted  20 22 22 22 22 22 22 22 22 22 22 22 22 00 -- **twelve copies of `"` (0x22)**.
* Double quotes are lwasm's STRING delimiter, so each "," was read as the quote character and
* the separator it contained was lost. ★★★★ The table assembled, the file built, the probe ran,
* and every separator except the space silently stopped being one. ★★★ A wrong table is not a
* crash: commas and full stops became ordinary word characters and the tokeniser diverged
* quietly -- which is the same shape as AD-125's palette, a data table that assembles fine and
* means something else.
* ★★ Verified by reading the emitted bytes back out of the binary, not by re-reading the source.
par_septab      fcb     $20,$2C,$2E,$3F,$21,$28,$29,$3B,$3A,$5B,$5D,$7B,$7D,$00
*                       sp   ,    .    ?    !    (    )    ;    :    [    ]    {    }   end
par_invtab      fcb     $27,$60,$2D,$5C,$22,$00
*                       '    `    -    \    "   end

par_is_sep:
                pshs    x,a                     ; A at ,s
                ldx     #par_septab
par_sep_lp:     ldb     ,x+
                beq     par_sep_no
                cmpb    ,s
                bne     par_sep_lp
                puls    a,x
                orcc    #$04                    ; Z set = separator
                rts
par_sep_no:     puls    a,x
                andcc   #$FB                    ; Z clear
                rts

par_is_inv:
                pshs    x,a
                ldx     #par_invtab
par_inv_lp:     ldb     ,x+
                beq     par_inv_no
                cmpb    ,s
                bne     par_inv_lp
                puls    a,x
                orcc    #$04
                rts
par_inv_no:     puls    a,x
                andcc   #$FB
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ par_clean -- words.cpp:218 cleanUpInput, plus the toLowercase at :339.
*
* ★★★ THE TWO ARE FUSED HERE AND SEPARATE IN THE ORACLE, deliberately. ScummVM builds the
* cleaned string, then copies it and lowercases the copy, because it compares the LOWERCASE form
* against the dictionary while storing the ORIGINAL-case word for display. **We store no word
* text at all** [§3.E: the tokenised result is word NUMBERS], so nothing needs the original case
* and one pass does both. ★★ Recorded as a deliberate divergence: if the port ever needs the
* display form, this is where it went.
* ★★ The loop shape is transcribed, not tidied: what "a  b" and "a-b" become is decided by the
* nesting, and a cleaner rewrite gets those wrong in ways a small test would not show.
par_clean:
                ldx     par_inbuf
                stx     par_cl_src
                ldx     par_clnbuf
                stx     par_cl_dst
par_cl_outer:
                ldx     par_cl_src
                lda     ,x
                beq     par_cl_end
                jsr     par_is_sep
                beq     par_cl_skip
                jsr     par_is_inv
                beq     par_cl_skip
par_cl_inner:
                ldx     par_cl_src
                lda     ,x
                beq     par_cl_end
                jsr     par_is_inv
                beq     par_cl_noadd            ; invalid chars are DROPPED, not separators
                cmpa    #'A
                blo     par_cl_store
                cmpa    #'Z
                bhi     par_cl_store
                adda    #32                     ; lowercase, words.cpp:339
par_cl_store:
                ldx     par_cl_dst
                sta     ,x+
                stx     par_cl_dst
par_cl_noadd:
                ldx     par_cl_src
                leax    1,x
                stx     par_cl_src
                lda     ,x
                beq     par_cl_end
                jsr     par_is_sep
                bne     par_cl_inner
                lda     #PAR_SPACE              ; a separator ends the run: exactly one space
                ldx     par_cl_dst
                sta     ,x+
                stx     par_cl_dst
                bra     par_cl_outer
par_cl_skip:
                ldx     par_cl_src
                leax    1,x
                stx     par_cl_src
                bra     par_cl_outer
par_cl_end:
                ldx     par_cl_dst              ; one trailing space is removed [words.cpp:244]
                cmpx    par_clnbuf
                beq     par_cl_term
                lda     -1,x
                cmpa    #PAR_SPACE
                bne     par_cl_term
                leax    -1,x
                stx     par_cl_dst
par_cl_term:
                clra
                sta     ,x
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ par_find -- words.cpp:250 findWordInDictionary, via parser.py Vocabulary.find.
*
* in:  par_fpos = offset into the cleaned buffer where this word starts
* out: par_fid  = word id, or PAR_UNKNOWN, or PAR_IGNORE;  par_flen = characters to consume
*
* ★★★★ THE RULE IS "LAST FULL MATCH IN BUCKET ORDER WINS", not longest. The scan does not stop
* at the first hit: it overwrites the candidate on every full match and breaks early ONLY when
* the dictionary word consumes all the remaining input. WORDS.TOK is alphabetically sorted so
* later usually means longer -- **"usually" is not the rule**, and a longest-match rewrite
* differs wherever it is not. T-P0-059's FAULT_LONGEST_MATCH is exactly that rewrite: it moved
* 166 tokenised word lists on larry1 and changed ZERO said() results.
*
* ★★★ THE PREFIX DECOMPRESSION HAS NO PYTHON ANALOGUE. parser.py receives an already-expanded
* (word, id) list; here the expansion happens in the walk, because the file is the index and
* expanding it up front would be the copy §3.E says not to make. Each entry is: u8 shared-prefix
* length, characters stored as (c^$7F)&$7F with bit 7 set on the LAST, then u16 BIG-endian id.
* A prefix length of 0 ends the run.
* ★★ par_word accumulates across entries -- that is what "shared with the PREVIOUS word" means,
* and why one mis-read length corrupts every following word in the bucket rather than one.
par_fpos        fdb     0
par_fid         fdb     0
par_flen        fcb     0
par_fptr        fdb     0
par_fwlen       fcb     0
par_fcur_id     fdb     0
par_word        fill    0,40            ; ★ fill, not rmb -- see par_ego above

par_find:
                ldd     #PAR_UNKNOWN
                std     par_fid
                clr     par_flen
                ldx     par_clnbuf
                ldd     par_fpos
                leax    d,x
                lda     ,x                      ; A = first char of this word
* ★ LONG branches: par_fi_tail is past the bucket walk and the 8-bit range does not reach it.
                cmpa    #'a
                lblo    par_fi_tail
                cmpa    #'z
                lbhi    par_fi_tail
                ldb     1,x                     ; a single "a"/"i" + space is IGNORE [:264]
                cmpb    #PAR_SPACE
                bne     par_fi_bucket
                cmpa    #'a
                beq     par_fi_ign
                cmpa    #'i
                bne     par_fi_bucket
par_fi_ign:     ldd     #PAR_IGNORE
                std     par_fid
* ★ IGNORE does NOT end the search: the oracle sets the id then scans the bucket anyway, so a
* dictionary word starting with "a" can still overwrite it. Transcribed, not shortened.
par_fi_bucket:
                suba    #'a
                tfr     a,b
                clra
                aslb
                rola                            ; D = letter*2
                addd    par_vocab
                tfr     d,x
                lda     ,x
                ldb     1,x                     ; D = head offset, BIG-endian
                cmpd    #0
                beq     par_fi_tail
                addd    par_vocab
                std     par_fptr
                clr     par_fwlen
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FIRST PREFIX IS READ BEFORE THE LOOP AND IS NEVER TESTED. words.cpp:96 does
*     int k = stream.readByte();          // outside the while
*     while (...) { ...word...  k = stream.readByte();
*                   if (k == 0 && str[0] >= 'a' + i) break; }
* so the terminator test applies to the NEXT entry's prefix, not this one. ★★★★ The first word
* in every bucket legitimately has prefix 0 -- it shares nothing with a previous word -- and a
* version that tests on entry bails immediately on every bucket. **That is exactly what the
* first port did**, and every lookup returned UNKNOWN.
* ★★★ This is the file's own opening claim failing in practice: "transcribed, not tidied". I
* restructured a loop whose shape was the specification, and the shape was the specification.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ldx     par_fptr
                lda     ,x+                     ; the FIRST prefix: read, not tested
                stx     par_fptr
                bra     par_fi_haveprefix
par_fi_entry:
                ldx     par_fptr
                lda     ,x+                     ; each SUBSEQUENT prefix
                stx     par_fptr
                tsta
                beq     par_fi_tail             ; 0 ends the bucket's run
par_fi_haveprefix:
                cmpa    #40
                bhs     par_fi_tail             ; a prefix past the buffer is a corrupt file
                sta     par_fwlen
par_fi_char:
                ldx     par_fptr
                lda     ,x+
                stx     par_fptr
                pshs    a
                anda    #$7F
                eora    #$7F
                ldb     par_fwlen
                cmpb    #39
                bhs     par_fi_charskip
                ldx     #par_word
                abx
                sta     ,x
                inc     par_fwlen
par_fi_charskip:
* ★★★★ PULS DOES NOT SET CC unless CC is in the pull list, so a branch straight after it tests
* whatever the last arithmetic left -- here `inc par_fwlen` or `cmpb #39`. The first version
* branched on those and the walk never terminated. **TSTA is what makes the branch about A.**
                puls    a
                tsta
                bpl     par_fi_char             ; bit 7 clear -> more characters
                ldx     par_fptr
                lda     ,x+
                ldb     ,x+
                stx     par_fptr
                std     par_fcur_id             ; u16 BIG-endian id
                jsr     par_fi_cmp
                bne     par_fi_entry
                ldd     par_fcur_id             ; full match: the LAST one wins
                std     par_fid
                lda     par_fwlen
                sta     par_flen
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PAR_FAULT_FIRST_MATCH -- the PORT's own injected fault [L-62]. A gate that has only ever
* reported PASS has not been shown to be a gate, and the Python leg's two faults do not transfer:
* they prove parser.py's harness, not this one.
* ★★★★ The fault is to STOP at the first full match instead of letting a later one overwrite it.
* **That is the plausible version, not a strawman** -- the bucket is alphabetically sorted, the
* first full match looks final, and `bra par_fi_tail` here saves a walk on every lookup.
* ★★★ It is also deliberately one that said() can MISS: it changes the winner only where one
* dictionary word is a prefix of another IN THE SAME BUCKET, and those are usually synonyms
* sharing an id -- so the ego word NUMBER is often unchanged. That is why the tokenised words are
* diffed alongside the match result and not instead of it [L-38, P6.2 §7.3].
* ★★ Off unless -DPAR_FAULT_FIRST_MATCH. Never set in a delivered build.
                ifdef   PAR_FAULT_FIRST_MATCH
                bra     par_fi_tail
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                jsr     par_fi_left             ; break early only on a PERFECT match
                cmpb    par_fwlen
                bne     par_fi_entry
par_fi_tail:
                lda     par_flen
                bne     par_fi_done
                ldx     par_clnbuf              ; no hit: consume to the next space [:313]
                ldd     par_fpos
                leax    d,x
                clrb
par_fi_skip:    lda     ,x+
                beq     par_fi_skipdone
                cmpa    #PAR_SPACE
                beq     par_fi_skipdone
                incb
                bra     par_fi_skip
par_fi_skipdone:
                stb     par_flen
par_fi_done:
                rts

* ── par_fi_left: B = input characters remaining from par_fpos ──
par_fi_left:
                pshs    x,a
                ldx     par_clnbuf
                ldd     par_fpos
                leax    d,x
                clrb
par_fi_ll:      lda     ,x+
                beq     par_fi_ld
                incb
                bra     par_fi_ll
par_fi_ld:      puls    a,x
                rts

* ── par_fi_cmp: does par_word (par_fwlen) match the input at par_fpos, ending at a space or
*    end-of-string?  Z set = yes.  [words.cpp:277-308]
par_fi_cmp:
                pshs    x,y,a,b
                jsr     par_fi_left
                cmpb    par_fwlen
                blo     par_fi_cmpno            ; dictionary word longer than the input left
                ldx     par_clnbuf
                ldd     par_fpos
                leax    d,x
                ldy     #par_word
                ldb     par_fwlen
par_fi_cmplp:   tstb
                beq     par_fi_cmpend
                lda     ,x+
                cmpa    ,y+
                bne     par_fi_cmpno
                decb
                bra     par_fi_cmplp
par_fi_cmpend:
                lda     ,x
                beq     par_fi_cmpyes
                cmpa    #PAR_SPACE
                bne     par_fi_cmpno
par_fi_cmpyes:  puls    a,b,y,x
                orcc    #$04
                rts
par_fi_cmpno:   puls    a,b,y,x
                andcc   #$FB
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ par_parse -- words.cpp:326 parseUsingDictionary, via parser.py parse_using_dictionary.
*
* ★★★ THREE BEHAVIOURS, ALL LOAD-BEARING AND ALL EASY TO MISS:
*   1. An IGNORE result occupies no word slot -- skipped entirely, not stored as 0.
*   2. An UNKNOWN word IS stored (as 0), sets par_notfound to its 1-based index, and **STOPS
*      parsing**. The rest of the line is never looked at.
*   3. par_cli is set from the word COUNT and par_accepted is always cleared here. Those two are
*      par_said's entire guard, so they belong to this routine and not to its caller.
* ★★ The bound is PAR_MAX_WORDS and we STOP there. The oracle writes _egoWords[wordCount] with
* no bound check and **segfaults past 20 words** -- measured, exit 139, twice [T-P0-059]. There
* is no reference behaviour to match, so this is a deliberate, recorded divergence.
par_parse:
                jsr     par_clean
                clr     par_egon
                clr     par_notfound
                clr     par_cli
                clr     par_accepted
                ldd     #0
                std     par_fpos
par_pa_lp:
                ldx     par_clnbuf
                ldd     par_fpos
                leax    d,x
                lda     ,x
                beq     par_pa_end
                cmpa    #PAR_SPACE              ; skip ONE leading space [:355]
                bne     par_pa_find
                ldd     par_fpos
                addd    #1
                std     par_fpos
par_pa_find:
                jsr     par_find
                ldd     par_fid
                cmpd    #PAR_IGNORE
                beq     par_pa_next             ; IGNORE occupies no slot
                lda     par_egon
                cmpa    #PAR_MAX_WORDS
                bhs     par_pa_end              ; our bound; the oracle has none (see above)
                ldb     #2
                mul                             ; D = index*2
                ldx     #par_ego
                leax    d,x
                ldd     par_fid
                cmpd    #PAR_UNKNOWN
                bne     par_pa_store
                ldd     #0                      ; unknown words store 0
par_pa_store:
                std     ,x
                inc     par_egon
                ldd     par_fid
                cmpd    #PAR_UNKNOWN
                bne     par_pa_next
                lda     par_egon
                sta     par_notfound            ; 1-based, then STOP
                bra     par_pa_end
par_pa_next:
                lda     par_flen
                tfr     a,b
                clra
                addd    par_fpos
                std     par_fpos
                bra     par_pa_lp
par_pa_end:
                lda     par_egon
                beq     par_pa_nocli
                lda     #1
                sta     par_cli
par_pa_nocli:
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ par_said -- op_test.cpp:318 testSaid, via parser.py test_said.
*
* in:  X -> the operand stream: u8 N, then N x u16 LITTLE-endian
* out: Z set = matched.  par_accepted updated.
*
* ★★★★★ IT HAS A SIDE EFFECT AND THAT IS THE MATCH-PRECEDENCE RULE. On success it sets
* par_accepted, and the guard rejects every later call while that is set -- so **the FIRST said()
* to match consumes the input** and no other said() in the same cycle can fire. A matcher that
* treats said() as pure picks the same set of matching patterns and fires the wrong NUMBER of
* them, which is a game responding to the wrong sentence.
* ★★★ 9999 is "rest of line, INCLUDING nothing"; 1 is "any single word".
* ★★ The operand count comes from the STREAM, never from an opcode table [optable.py:19, L-28].
par_sd_n        fcb     0
par_sd_e        fcb     0
par_sd_c        fcb     0
par_sd_z        fdb     0
par_sd_p        fdb     0

par_said:
* ★ LONG branches: par_sd_no sits past the whole match loop.
                lda     par_accepted
                lbne    par_sd_no
                lda     par_cli
                lbeq    par_sd_no
                lda     ,x+
                sta     par_sd_n
                stx     par_sd_p
                lda     par_egon
                sta     par_sd_e
                clr     par_sd_c
                ldd     #0
                std     par_sd_z
par_sd_lp:
                lda     par_sd_n
                beq     par_sd_tail
                lda     par_sd_e
                beq     par_sd_tail
                ldx     par_sd_p
                ldb     ,x+                     ; LITTLE-endian: low byte first
                lda     ,x+
                stx     par_sd_p
                std     par_sd_z
                cmpd    #9999
                bne     par_sd_not9999
                lda     #1
                sta     par_sd_n                ; decremented below -> the loop ends
                bra     par_sd_step
par_sd_not9999:
                cmpd    #1
                beq     par_sd_step             ; "any word"
                lda     par_sd_c
                ldb     #2
                mul
                ldx     #par_ego
                leax    d,x
                ldd     ,x
                cmpd    par_sd_z
                bne     par_sd_no
par_sd_step:
                inc     par_sd_c
                dec     par_sd_n
                dec     par_sd_e
                bra     par_sd_lp
par_sd_tail:
                lda     par_sd_e                ; input consumed, or last operand 9999 [:363]
                beq     par_sd_tail2
                ldd     par_sd_z
                cmpd    #9999
                bne     par_sd_no
par_sd_tail2:
                lda     par_sd_n                ; leftovers allowed only if next is 9999 [:368]
                beq     par_sd_yes
                ldx     par_sd_p
                ldb     ,x+
                lda     ,x
                cmpd    #9999
                bne     par_sd_no
par_sd_yes:
                lda     #1
                sta     par_accepted            ; ★ the side effect: input is now consumed
                orcc    #$04
                rts
par_sd_no:
                andcc   #$FB
                rts
