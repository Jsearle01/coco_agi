* rule_fixture.s -- one case per part of the four-part rule (CLAUDE.md §2N), plus alias+offset.
* ---------------------------------------------------------------------------------------------
* P1 CASE: this whole line is a comment and it names $FFA6 -- it must NOT be counted.
;  P1 CASE (semicolon form): sta $FFB0 written in prose. Must NOT be counted.

CEL_MMU         equ     $FFA6           ; P3 CASE: an equ DEFINITION of $FFA6, not an access.
SAM_FAST        equ     $FFD9           ; P3 CASE: second definition, also not an access.

* --- the four rejections -------------------------------------------------------------------
                nop                     ; P2 CASE: the code half has no register; $FFA4 here
                                        ;   is only in the comment. Must NOT be counted.
                fdb     $FFA2           * P4 CASE: a register address as DATA. No load/store/
*                                         modify mnemonic, so it is not an access.
                clra                    ; P4 CASE: 'clra' is the register form, not memory --
*                                         the trailing \b must stop 'clr' matching it.

* --- the accepted cases --------------------------------------------------------------------
                sta     $FFB0           ; COUNTED: a plain literal store to the palette.
                lda     $FF92           * COUNTED: a literal load is an access too.
                sta     CEL_MMU         ; COUNTED via alias -> $FFA6
                sta     CEL_MMU+1       ; COUNTED via alias+offset -> $FFA7
                sta     CEL_MMU+2       ; COUNTED via alias+offset -> $FFA8. ★ NOTE: this line
*                                         contains no '$FF' AT ALL. A literal grep is blind to
*                                         it. This is the class that made up MOST of POP's real
*                                         accesses.
                stb     SAM_FAST        ; COUNTED via alias -> $FFD9
                clr     $FF9C           ; COUNTED: read-modify-write memory form.
                sta     $FFA6           ; COUNTED once, and the comment's $FFB0 $FFD8 $FF90 are
*                                         P2-discarded -- code half only, so this is ONE hit.
