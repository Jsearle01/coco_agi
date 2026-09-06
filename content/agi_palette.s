* content/agi_palette.s -- AGI's 16 colours, as GIME RGB palette bytes. THE ONE HOME.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHY THIS FILE EXISTS. The table lived inside src/harness/pic_probe.s -- a RENDERER PROBE
* -- and that is why the integration probe rendered every room in the wrong colours for four
* tasks [AD-125]. p3b could not reach it, hal_globals.s's mode 2 row pointed at the shared HAL's
* generic gfx_pal16 instead, and the display script parsed whichever file it had been told about.
* **A fact that three consumers need cannot live inside one of them** [CLAUDE.md §2F].
*
* ★★★★ CLAUDE.md §2B PUTS IT HERE, NOT IN THE HAL: *"What IS ours and authored: the 8x8
* 40-column font, the RGB palette table, and (when it exists) the composite palette table, all
* under content/."* ★★★ §2B also makes this file PROTECTED -- it is hand-derived and
* eye-gated, so a generator must never overwrite it without Jay's ruling.
*
* ★★★★ AND IT IS NOT HAL DATA. gfx.s is SHARED across three repos (§2M) and gfx_pal16 is its
* generic 16-colour ramp, correct for a HAL that knows nothing about AGI. Putting AGI's palette
* there would be drift; putting it in hal_globals.s would make an authored asset look like
* machine configuration. hal_globals.s (PROJECT_LOCAL) INCLUDES this file, which is what lets
* mode 2's palette pointer resolve without any shared file changing.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ PROVENANCE -- THIS TABLE IS GATED, NOT ASSERTED. T-P0-024 (P4.4, 2026-08-29) closed it:
*   AC-11 [byte-comparable] 16 of 16 values read back BY THE GUEST from $FFB0-$FFBF with bits
*          7-6 masked [ref: SockmasterGime.md, "FFB0-FFBF Color palette registers"].
*   AC-12 [eye-gated]       PASSED -- Jay, static-png, RGB. The guest's swatches beside a
*          synthesised EGA reference: "band 6 is brown in both".
* ★★ Re-confirmed live 2026-09-06 on the castle, room 22 and picture 3: "all three look good."
*
* ★★★ THE ENCODING, verified from gfx.s's own gfx_pal4 comments rather than assumed:
*     value = R1<<5 | G1<<4 | B1<<3 | R0<<2 | G0<<1 | B0,  each channel 2 bits, 0-3.
*     gfx_pal4 $26 is commented "R=3 G=1 B=0" and $19 "R=0 G=2 B=3"; both satisfy it.
* ★★ EGA's levels $00/$55/$AA/$FF land exactly on the GIME's four steps, so a SATURATION
* difference against an EGA reference is expected and a HUE difference is not.
*
* ★★★★ ENTRY 6 IS THE ONE THAT CATCHES A WRONG CONVERSION. Brown is (R2,G1,B0) = $22 -- the only
* entry whose three channels differ. A "double the CGA bit" conversion yields $32, dark yellow,
* and every other entry survives that mistake unchanged. If this table is ever re-derived, check
* entry 6 first.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★ Consumers, so a reader can find them all from here (§2F):
*     src/hal/coco3-dsk/hal_globals.s   includes this file; mode 2's palette pointer
*     src/harness/pic_probe.s           pal_load / pal_readback  (AC-11, AC-12)
*     harness/tools/agi_palette.py      parses this file; the Python tools import from there
*     harness/tools/p3b_show.lua        parses this file to assert the palette host-side

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ agi_pal_load / agi_pal_readback — THE ONE LOADER, beside the one table [T-P0-057].
*
* ★★★★ WHY THE ROUTINE MOVED HERE TOO. T-P0-056b gave the DATA one home and left the LOADER in
* pic_probe.s, so p3b could reach the table and still had no way to install it. **It installed
* nothing**: a write tap on $FFB0-$FFBF across a full p3b run recorded 16 writes, all of them
* from PC $C00F -- Disk BASIC's ROM -- and ZERO from the guest. Every correct colour Jay saw was
* asserted by the host script, so AC-1 passed on a machine state p3b did not establish.
* ★★★ Consolidating the data and leaving the mechanism behind is half a fix, and the half that
* was left is the half that made the defect invisible.
*
* ★★ REGISTER-CLEAN, because both callers reach it from init code with live registers and one of
* them (p3b) has no spare. A/X/Y are preserved.
* ★★★★ $FFB0-$FFBF IS THE HAL'S RANGE (§2N: "the HAL owns $FF90-$FF9F and $FFB0-$FFBF"). This
* file is included BY hal_globals.s, so the owner is unchanged -- the write site did not move out
* of the HAL, it moved out of a probe INTO it.
* ★ Constraint B [gfx.s:143]: palette writes may not latch until $FF98/$FF99 are final, so the
* caller must have set the video mode first. Both callers do; p3b's is set host-side before
* staging, which is stated in §7 rather than assumed here.
agi_pal_load:
        pshs    a,x,y
        ldx     #agi_pal16
        ldy     #$FFB0
agi_pl_lp:
        lda     ,x+
        sta     ,y+
        cmpx    #agi_pal16+16
        blo     agi_pl_lp
        puls    a,x,y,pc

* ── agi_pal_readback — in: X = 16-byte destination. Proves the values LANDED. ──
* ★★★★ GUARDED, AND THE GUARD IS A MEASUREMENT NOT A PREFERENCE. p3b's code region is $2000-$5300
* and the build sits 27 bytes under it; the loader plus its call site is 23 and fits, the readback
* plus its call site is 25 and does not. **Linking 19 bytes of routine into every probe that
* includes this file, to serve the one probe that calls it, is what pushed p3b over.**
* ★★ pic_probe.s sets AGI_PAL_READBACK in its own source (like p3b sets PLANE_WIN_MMU), so the
* symbol travels with the file that needs it rather than with a command line [AD-119's lesson:
* a flag on a command line is a fact nobody can see from the source].
* ★ p3b does NOT link it. Its palette is proved instead by a write tap on $FFB0-$FFBF, which
* records the guest's own stores and their values -- stronger than a readback for the question
* "did THIS program write them", and weaker for "did they land". Both are reported.
                ifdef   AGI_PAL_READBACK
* ★★★ BITS 7-6 MUST BE MASKED ON READ, documented rather than discovered: *"These registers can
* also be read to determine what palettes are set but like the MMU registers, the upper 2 bits
* must be masked out."* [ref: docs/ground-truth/SockmasterGime.md, "FFB0-FFBF Color palette
* registers"]. ★★ Without the mask a correct write compares as sixteen mismatches.
* ★ Read BY THE GUEST. A host-side read tests MAME's palette model, not the guest's writes.
agi_pal_readback:
        pshs    a,x,y
        ldy     #$FFB0
agi_pr_lp:
        lda     ,y+
        anda    #$3F
        sta     ,x+
        cmpy    #$FFC0
        blo     agi_pr_lp
        puls    a,x,y,pc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

agi_pal16:
        fcb     $00             ;  0 black          R0 G0 B0
        fcb     $08             ;  1 blue           R0 G0 B2
        fcb     $10             ;  2 green          R0 G2 B0
        fcb     $18             ;  3 cyan           R0 G2 B2
        fcb     $20             ;  4 red            R2 G0 B0
        fcb     $28             ;  5 magenta        R2 G0 B2
        fcb     $22             ;  6 brown          R2 G1 B0   ★ the odd one out
        fcb     $38             ;  7 light grey     R2 G2 B2
        fcb     $07             ;  8 dark grey      R1 G1 B1
        fcb     $0F             ;  9 light blue     R1 G1 B3
        fcb     $17             ; 10 light green    R1 G3 B1
        fcb     $1F             ; 11 light cyan     R1 G3 B3
        fcb     $27             ; 12 light red      R3 G1 B1
        fcb     $2F             ; 13 light magenta  R3 G1 B3
        fcb     $37             ; 14 yellow         R3 G3 B1
        fcb     $3F             ; 15 white          R3 G3 B3
