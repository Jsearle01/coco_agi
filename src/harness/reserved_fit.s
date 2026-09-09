* src/harness/reserved_fit.s -- does the engine actually FIT MAP_RESERVED? [T-P0-077 AC-5]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AN ASSERTION, NOT A TABLE IN A REPORT. P6.20's answer to "does get.string fit" was an
* arithmetic estimate; Jay's ruling was to resolve it by building and letting the map's own
* assertions be the stop. **This is that assertion**: it orgs the real engine files at
* MAP_RESERVED, one after another, and refuses to assemble if they run past MAP_RESERVED_END.
*
* ★★★★ IT IS THE ONLY PLACE THE THREE ARE ASSEMBLED TOGETHER. parser.s is gated by
* parser_probe.s, text.s by text_probe.s and getstring.s by gs_probe.s -- each in its own flat
* map with the whole 64 KB, so **no gate this project has ever run would notice the reservation
* overflowing.** That is the same shape as P6.11's code-region overrun, which went a whole task
* unnoticed because nobody ran the build that asserts [memmap.inc's own note].
*
* ★★★ It produces no artifact anybody runs. Assembling it IS the test.
*
* usage:  lwasm --raw -I. -o build/reserved_fit.bin src/harness/reserved_fit.s
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/engine/memmap.inc"

GS_STR_SLOTS    equ     MAP_STR_SLOTS
GS_STR_LEN      equ     MAP_STR_LEN

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ TWO REGIONS NOW, AND THE SPLIT IS THE P6.22 RESULT. get.string and the key decoder are
* INPUT, not text rendering, and they live in MAP_INPUT -- the 1,024 bytes the DIR stride freed.
* MAP_RESERVED goes back to holding what it was reserved for: the parser, the text engine and its
* substitution buffer, with the remainder for sound.
                org     MAP_RESERVED

RF_PARSER       equ     *
                include "src/engine/parser.s"
RF_TEXT         equ     *
                include "src/engine/text.s"
RF_RES_END      equ     *

* ★★ The substitution buffer is not code and is not emitted here, so it is added explicitly.
RF_RES_TOTAL    equ     RF_RES_END-MAP_RESERVED+TXT_PBUF_MAX

                ifgt    RF_RES_TOTAL-(MAP_RESERVED_END-MAP_RESERVED)
                error   "MAP_RESERVED OVERFLOW -- parser + text + substitution buffer exceed the reservation."
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ RF_NO_GETSTRING IS THE GREEN DIRECTION, AND IT IS NOT A CONVENIENCE FLAG. §2W: an
* assertion nobody has seen pass is as untrustworthy as one nobody has seen fail. Without
* getstring.s this is P6.19's shipped engine, which is KNOWN to fit -- so the flag turns the check
* into a two-sided instrument instead of a line that is green today and might be green for a
* reason nobody checked.
                org     MAP_INPUT
RF_GETSTRING    equ     *
                ifndef  RF_NO_GETSTRING
                include "src/engine/getstring.s"
                endc
RF_INPUT_END    equ     *

* ★★★ RF_INPUT_BUDGET exists so the MAP_INPUT assertion can be SEEN TO FIRE. It is green today
* with 620 bytes spare, and an assertion that has only ever been green is an assertion nobody has
* tested -- the same reason RF_NO_GETSTRING exists for the other direction. Setting it below what
* get.string occupies must produce the error below.
                ifndef  RF_INPUT_BUDGET
RF_INPUT_BUDGET equ     MAP_INPUT_END-MAP_INPUT
                endc
                ifgt    RF_INPUT_END-MAP_INPUT-RF_INPUT_BUDGET
                error   "MAP_INPUT OVERFLOW -- get.string plus the key decoder exceed the 1,024 bytes the DIR stride freed."
                endc

                end
