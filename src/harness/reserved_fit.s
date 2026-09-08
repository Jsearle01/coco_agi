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

                org     MAP_RESERVED

RF_PARSER       equ     *
                include "src/engine/parser.s"
RF_TEXT         equ     *
                include "src/engine/text.s"
* ★★★★★ RF_NO_GETSTRING IS THE GREEN DIRECTION, AND IT IS NOT A CONVENIENCE FLAG. §2W: an
* assertion nobody has seen pass is as untrustworthy as one nobody has seen fail. Without
* getstring.s this is exactly P6.19's shipped engine, which is KNOWN to fit with 195 bytes spare
* -- so the flag turns the check into a two-sided instrument instead of a line that is red today
* and might be red for a reason nobody checked.
RF_GETSTRING    equ     *
                ifndef  RF_NO_GETSTRING
                include "src/engine/getstring.s"
                endc
RF_END          equ     *

* ★★ The substitution buffer is not code and is not emitted here, so it is added explicitly.
RF_TOTAL        equ     RF_END-MAP_RESERVED+TXT_PBUF_MAX

                ifgt    RF_TOTAL-(MAP_RESERVED_END-MAP_RESERVED)
                error   "MAP_RESERVED OVERFLOW -- parser + text + getstring + substitution buffer exceed the reservation. This is the stop, not a nudge: M-48 is spent, MAP_CODE has 5 bytes, and growing the region is a map change."
                endc

                end
