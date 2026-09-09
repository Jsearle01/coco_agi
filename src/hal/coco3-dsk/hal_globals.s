* src/hal/coco3-dsk/hal_globals.s
*
* HAL-owned Direct Page allocations for the POP CoCo3 port.
*
* ADOPTION NOTE (P2.1). Karateka carries these in `src/engine/globals.s`, a file
* that also declares the ENGINE bands ($20-$7F). POP has no engine yet and engine
* code is out of scope for this dispatch, so only the HAL-owned declarations are
* adopted here — same symbols, same addresses, same meaning. When POP's engine
* arrives it takes the engine bands; this file keeps the HAL band.
*
* The addresses are NOT a POP choice — they are the shared contract:
*   [ref: src/hal.inc — DIRECT PAGE (DP) USAGE POLICY]
*     HAL owns    $00-$1F
*     Engine owns $20-$7F
*     Reserved    $80-$FF  (CoCo3 system use)
*
* Values are byte-for-byte the same as karateka's globals.s. Any divergence here
* would fork the shared contract, which P2.1's governing rules forbid.
* ---------------------------------------------------------------

                ifdef   OBJTARGET
                * setdp is NOT permitted for the object target — the fourth
                * object-incompatible directive class (P2.4; the recon found three).
                * The HAL uses explicit `<` direct-mode operands, so omitting the
                * declaration changes nothing it relies on.
                else
                setdp   0
                endc

* ---------------------------------------------------------------
* HAL scratch band $00-$1F
*   $00-$03  HAL_ZP_PARAM0-3  (declared in hal.inc)
*   $04-$05  HAL_ZP_PTR0      (declared in hal.inc)
*   $06-$07  HAL_ZP_PTR1      (declared in hal.inc)
*   $08-$0F  reserved for HAL internal use
* ---------------------------------------------------------------

* --- HAL time subsystem ($10-$11) ---
hal_frame_hi        equ $10     ; frame counter high byte (time.s, irq_vbl.s)
hal_frame_lo        equ $11     ; frame counter low byte  (time.s, irq_vbl.s)

* --- HAL gfx subsystem ($12) ---
gfx_initialized     equ $12     ; $00 = not init; $01 = HAL_gfx_init complete

* --- HAL sys subsystem ($13) ---
sys_init_cc_mask    equ $13     ; CC captured after HAL_sys_init; test diagnostic only

* $14-$1F: reserved for future HAL subsystem allocations

* ---------------------------------------------------------------
* page_register — ENGINE-owned by the DP policy, but HAL-CONSUMED.
*
* HAL_gfx_present (gfx.s) READS $50 to decide which buffer to show, so the HAL
* cannot assemble without it. It sits in the engine band, so POP's engine will own
* it once the engine exists; it is declared here only so the adopted HAL builds
* standalone. Flagged in the P2.1 report as a contract observation, not changed —
* altering it would reshape the shared interface.
*
*   Option I convention (karateka-canonical): page_register identifies the BACK
*   buffer (the active draw target). HAL_gfx_present displays the buffer it points
*   at.  $20 = buffer A ($8000).  $40 = buffer B ($C000).
*   [ref: src/hal.inc; karateka src/engine/globals.s]
* ---------------------------------------------------------------
page_register       equ $50     ; active draw buffer ($20 = A, $40 = B)
page_source_blit    equ $51     ; prior draw buffer (blit source)

* ---------------------------------------------------------------
* Page tokens — also engine-band constants that the HAL COMPARES against.
* gfx.s does `cmpa #PAGE_A_TOKEN` in HAL_gfx_present and the blit paths, so the
* HAL cannot assemble without them. Same values as karateka; adopted, not chosen.
*   $20 = buffer A ($8000-range) — Apple II hires page 1 high byte
*   $40 = buffer B ($C000-range) — Apple II hires page 2 high byte
* [ref: karateka src/engine/globals.s:142-143]
* ---------------------------------------------------------------
PAGE_A_TOKEN        equ $20     ; draw target = buffer A
PAGE_B_TOKEN        equ $40     ; draw target = buffer B

* ---------------------------------------------------------------
* s4_dest_row — engine-band scratch used by HAL_gfx_blit_scroll (gfx.s:968).
* Declared here for the same reason as page_register: the HAL reads it, so the HAL
* cannot assemble without it. Adopted at karateka's address, unchanged.
* [ref: karateka src/engine/globals.s:119]
* ---------------------------------------------------------------
s4_dest_row         equ $66     ; 16-bit scroll-blit destination row ($66/$67)

* ═══════════════════════════════════════════════════════════════════
* GRAPHICS MODE DESCRIPTOR TABLE — PROJECT-LOCAL (T-P0-011)
* ═══════════════════════════════════════════════════════════════════
* ★★ THIS IS WHY POP-HAL-01 HAPPENED. The table used to live in gfx.s, which is SHARED and
* kept aligned by hal_sync_check.py. Adding AGI's 200-line mode there grew the table by one
* 7-byte row, shifted every address after it, and changed 27 of POP's built artifacts --
* making POP's byte-identity rule unsatisfiable for the one change AGI required. The table
* became project-local so a project can add a mode WITHOUT touching a shared file.
* [CLAUDE.md §2M.5; POP-HAL-01, landed 2026-08-26]
*
* Rows 0 and 1 are carried unchanged from the shared table AGI inherited: the lookup is
* POSITIONAL (row index = mode id), so mode 2 cannot exist at index 2 unless 0 and 1 do.
* They are not AGI's modes and AGI does not select them.
*
* Row layout is the SHARED contract, gfx.s GFX_MODE_ENTSZ = 7:
*   +0 VRES  +1 stride  +2 size in WORDS  +4 palette ptr  +6 palette count
* Modes 0 and 1 use the palettes that are SHARED and live in gfx.s; AGI's own mode 2 uses
* AGI's own palette, which is authored content and lives under content/ (see below).
                ifdef   HAL_GFX_MODE_SERVICE

                ifdef   OBJTARGET
                section code
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AGI'S PALETTE, INCLUDED FROM ITS ONE HOME [CLAUDE.md §2F, §2B].
* ★★★★ Mode 2's palette pointer below used to name gfx_pal16 -- the SHARED HAL's generic
* 16-colour ramp -- with a comment saying AGI's own palette was "loaded by the engine at init,
* not from here". **Nothing loaded it.** The engine does not exist yet, the renderer probe kept
* a private copy, and the integration probe therefore drew every room through the HAL's ramp:
* index 2 is EGA green and the ramp maps it to light grey, so foliage rendered as pale grey and
* read as unfilled [AD-125, found by Jay's eye gate and by no byte gate].
* ★★★ Pointing the row at the real table is what makes that unrepeatable: any build that selects
* mode 2 through HAL_gfx_set_mode now gets AGI's palette by construction rather than by a caller
* remembering to load it.
* ★★ The include sits HERE, in a PROJECT_LOCAL file, so no shared file changes (§2M) and every
* probe that includes hal_globals.s can resolve the symbol.
                include "content/agi_palette.s"
* ═══════════════════════════════════════════════════════════════════════════════════════════

GFX_MODE_MAX        equ 2           ; highest supported id — AGI ships 0, 1 and 2

gfx_mode_table:
        fcb     $15                     ; mode 0: 320x192x4  VRES  [GIME-RM §10]
        fcb     80                      ;   80 bytes/row
        fdb     $1E00                   ;   15,360 B / 2 = $1E00 words
        fdb     gfx_pal4                ;   shared palette, defined in gfx.s
        fcb     4                       ;   palette regs $FFB0-$FFB3

        fcb     $1E                     ; mode 1: 320x192x16 VRES  [GIME-RM §10]
        fcb     160                     ;   160 bytes/row
        fdb     $3C00                   ;   30,720 B / 2 = $3C00 words
        fdb     gfx_pal16               ;   shared palette, defined in gfx.s
        fcb     16                      ;   palette regs $FFB0-$FFBF

* ★ AGI'S MODE. 200 lines costs NO extra MMU blocks: 32,000 B is 3.91 blocks against mode 1's
* 3.75, and both round to 4 with 768 B spare. VRES $3E confirmed from two independent sources,
* not derived: [ref: GIME-RM $FF99 VRES bit layout — "LPF1 LPF0 / Visible lines: 0 0 192,
* 0 1 200"] and [ref: docs/ground-truth/SockmasterGime.md:110-113]. $3E = %0 01 111 10 --
* LPF 01 = 200 lines, HRES 111 = 160 B/row, CRES 10 = 16 colours. It differs from mode 1's
* $1E in the LPF field ALONE.
        fcb     $3E                     ; mode 2: 320x200x16 VRES  [GIME-RM $FF99 LPF=01]
        fcb     160                     ;   160 bytes/row
        fdb     $3E80                   ;   32,000 B / 2 = $3E80 = 16,000 words
        fdb     agi_pal16               ; ★ AGI's OWN palette, content/agi_palette.s -- gated at
                                        ;   P4.4 (AC-11 readback, AC-12 Jay's eye gate). This row
                                        ;   named gfx_pal16 until T-P0-056b [AD-125].
        fcb     16                      ;   palette regs $FFB0-$FFBF

                ifdef   OBJTARGET
                endsection
                endc

                endc                    ; HAL_GFX_MODE_SERVICE

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE KEYBOARD DECODER, AND IT IS HERE RATHER THAN IN input.s BECAUSE OF §2M. [P6.22]
*
* ★★★★ HAL_input_poll IS DETECTION-ONLY: it drives all eight columns low at once, reads the row
* sense, and returns "some key is down" with B = 0 -- its own header says "directional decode
* deferred to R-p25+". **So there is no key code anywhere in the HAL**, and AGI's input line
* cannot be built on what exists.
*
* ★★★★★ AND input.s IS SHARED. Adding a decoder there would change POP's and Karateka's builds
* for a routine neither calls -- §2M.4: "An AGI-only export in a shared file is drift even when
* guarded." hal_globals.s is PROJECT_LOCAL (hal_sync_check.py's own PROJECT_LOCAL set names it
* for all three repos), so this lands in AGI alone. ★★★ **POP and Karateka are not rebuilt
* byte-identical here -- their inputs do not change at all**, which is the stronger property and
* the one §2M actually wants.
* ★★ HAL_input_poll is untouched: same text, same signature, same three-repo agreement.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE MATRIX. $FF02 selects columns (write, a LOW bit selects); $FF00 reads rows PA0-PA6
* (a LOW bit means pressed); PA7 is the joystick comparator and is masked off. Eight columns by
* seven rows = 56 keys.
*
*        PB0   PB1   PB2   PB3   PB4   PB5   PB6   PB7
*  PA0    @     A     B     C     D     E     F     G
*  PA1    H     I     J     K     L     M     N     O
*  PA2    P     Q     R     S     T     U     V     W
*  PA3    X     Y     Z    up    dn   left right space
*  PA4    0     1     2     3     4     5     6     7
*  PA5    8     9     :     ;     ,     -     .     /
*  PA6   ENT   CLR   BRK   ALT  CTRL   F1    F2   SHIFT
*
* ★★★ AD-134's scheme reads off that table directly: the four arrows are PA3/PB3-PB6, CTRL is
* PA6/PB4, ALT is PA6/PB3, ENTER is PA6/PB0, and Ctrl+Q/E/Z/C are PA2/PB1, PA0/PB5, PA3/PB2 and
* PA0/PB3. **Every key the scheme names is a distinct matrix position**, which is what "no
* ghosting" meant -- no two of them share a row or a column in a way that aliases.
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ★★★★★ BEHIND A GUARD, AND THE REASON IS MEASURED. hal_globals.s is included by every probe that
* pulls in the HAL, and the decoder is 318 bytes -- adding it unguarded broke pic_probe.s with
* "pic_probe code overlaps PIC_DATA", a probe that has nothing to do with the keyboard.
* ★★★★ §2M.2's pattern applied to a PROJECT_LOCAL file: **a build pays for what it asks for.**
* The renderer, resource, cel and composite gates never define HAL_KEYBOARD and are byte-identical
* to what they were; the input probe defines it and gets 318 bytes.
                ifdef   HAL_KEYBOARD

HAL_KEY_ENTER   equ     $0D
HAL_KEY_BS      equ     $08             ; CLEAR is AGI's backspace
HAL_KEY_ESC     equ     $1B             ; BREAK
HAL_KEY_UP      equ     $81
HAL_KEY_DOWN    equ     $82
HAL_KEY_LEFT    equ     $83
HAL_KEY_RIGHT   equ     $84
HAL_KEY_ALT     equ     $85             ; a MODIFIER, reported so the caller can see the menu key

                ifdef   OBJTARGET
                section code
                endc

* ★ EXPORT only under OBJTARGET, as the rest of the HAL does -- lwasm rejects it in --raw mode.
                ifdef   OBJTARGET
                export  HAL_key_scan
                endc

* ── unshifted, row-major: 8 columns x 7 rows. 0 = not a character key. ───────────
hal_kb_lo
        fcb     '@,'A,'B,'C,'D,'E,'F,'G
        fcb     'H,'I,'J,'K,'L,'M,'N,'O
        fcb     'P,'Q,'R,'S,'T,'U,'V,'W
        fcb     'X,'Y,'Z,HAL_KEY_UP,HAL_KEY_DOWN,HAL_KEY_LEFT,HAL_KEY_RIGHT,$20
        fcb     '0,'1,'2,'3,'4,'5,'6,'7
        fcb     '8,'9,':,';,',,'-,'.,'/
        fcb     HAL_KEY_ENTER,HAL_KEY_BS,HAL_KEY_ESC,HAL_KEY_ALT,0,0,0,0

* ── shifted. ★★ Only the rows that DIFFER need a second table, but a full one costs 56 bytes
* and removes a per-key branch; the branch would cost more in code than the table costs in data.
* ★ Letters shift to lower case: AGI's parser lowercases anyway [parser.s par_clean], but the
* ECHO must show what was typed, so the distinction is real on screen.
hal_kb_hi
        fcb     '`,'a,'b,'c,'d,'e,'f,'g
        fcb     'h,'i,'j,'k,'l,'m,'n,'o
        fcb     'p,'q,'r,'s,'t,'u,'v,'w
        fcb     'x,'y,'z,HAL_KEY_UP,HAL_KEY_DOWN,HAL_KEY_LEFT,HAL_KEY_RIGHT,$20
        fcb     $30,'!,'",'#,'$,'%,'&,$27
        fcb     '(,'),'*,'+,'<,'=,'>,'?
        fcb     HAL_KEY_ENTER,HAL_KEY_BS,HAL_KEY_ESC,HAL_KEY_ALT,0,0,0,0

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ HAL_key_scan -- one pressed key as a code, or 0.
*
* Returns: A = the key code (0 = nothing), B = modifier bits: bit0 SHIFT, bit1 CTRL, bit2 ALT.
* Clobbers A, B, CC. Preserves X, Y, U.
*
* ★★★ IT REPORTS ONE KEY, NOT A SET, and that is the right shape for a text input line: the
* caller wants "what was typed", and AGI's own input model is a stream of single key events
* [text.cpp stringKeyPress takes ONE key]. A caller that needs simultaneous keys -- a game
* reading two arrows for a diagonal -- needs the mask, and that is what the modifier byte and
* AD-134's Ctrl+Q/E/Z/C exist to avoid.
* ★★ The modifiers are read FIRST and excluded from the key search, so SHIFT alone reports
* nothing rather than reporting itself.
HAL_key_scan:
        pshs    x,y,u
        clr     hal_kb_mod
        clr     hal_kb_key
* ★★★ RESET THE INDEX, and it is $FF rather than 0 because 0 is a legitimate index -- PA0/PB0 is
* the '@' key. A sentinel that collides with a real value is the AD-125 shape: it assembles, it
* runs, and it reports one specific wrong answer.
        lda     #$FF
        sta     hal_kb_idx
* ── column 6 first: the modifier row lives there (PA6) but so do ENTER/CLEAR/BREAK ──
        lda     #$FF
        sta     $FF02
        ldb     #0
        stb     hal_kb_col
hal_ks_col:
* ★★ Select ONE column by writing a single low bit. The idle state is all-high, restored at exit
* by HAL_input_poll's own convention.
        ldb     hal_kb_col
        lda     #$FF
hal_ks_shift:
        tstb
        beq     hal_ks_sel
        lsla
        ora     #$01
        decb
        bra     hal_ks_shift
hal_ks_sel:
        sta     $FF02
        lda     $FF00
        ora     #$80                    ; ignore PA7, the joystick comparator
        coma                            ; now a SET bit means pressed
        anda    #$7F
        beq     hal_ks_next
        sta     hal_kb_rows
* ── walk the seven rows of this column ──
        ldb     #0
hal_ks_row:
        cmpb    #7
        bhs     hal_ks_next
        lda     hal_kb_rows
        pshs    b
hal_ks_bit:
        tstb
        beq     hal_ks_test
        lsra
        decb
        bra     hal_ks_bit
hal_ks_test:
        puls    b
        bita    #$01
        beq     hal_ks_rownext
* ── (row B, column hal_kb_col) is down. Modifier or key? ──
        cmpb    #6
        bne     hal_ks_key
        lda     hal_kb_col
        cmpa    #7
        bne     hal_ks_ctrl
        lda     hal_kb_mod              ; PA6/PB7 = SHIFT
        ora     #$01
        sta     hal_kb_mod
        bra     hal_ks_rownext
hal_ks_ctrl:
        cmpa    #4
        bne     hal_ks_alt
        lda     hal_kb_mod              ; PA6/PB4 = CTRL
        ora     #$02
        sta     hal_kb_mod
        bra     hal_ks_rownext
hal_ks_alt:
        cmpa    #3
        bne     hal_ks_key
        lda     hal_kb_mod              ; PA6/PB3 = ALT -- recorded AND reported as a key,
        ora     #$04                    ;   because AD-134 opens the menu with it
        sta     hal_kb_mod
hal_ks_key:
* ★ index = row*8 + column. The FIRST key found wins; a second is ignored, which is what
* "one key" means and is why the modifier row is tested before this branch.
* ★★ The test is on the INDEX, not on hal_kb_key -- the key code is not resolved until after the
* whole matrix is walked, so testing it here would always see 0 and the LAST key would win
* instead of the first.
        lda     hal_kb_idx
        cmpa    #$FF
        bne     hal_ks_rownext
        pshs    b
        lda     #8
        mul
        addb    hal_kb_col
        stb     hal_kb_idx
        puls    b
hal_ks_rownext:
        incb
        bra     hal_ks_row
hal_ks_next:
        inc     hal_kb_col
        lda     hal_kb_col
        cmpa    #8
        lblo    hal_ks_col
* ── deselect, then resolve the index through the right table ──
        lda     #$FF
        sta     $FF02
        lda     hal_kb_idx
        cmpa    #$FF
        beq     hal_ks_none
        ldx     #hal_kb_lo
        ldb     hal_kb_mod
        bitb    #$01
        beq     hal_ks_tbl
        ldx     #hal_kb_hi
hal_ks_tbl:
        ldb     hal_kb_idx
        abx
        lda     ,x
        sta     hal_kb_key
hal_ks_none:
        lda     hal_kb_key
        ldb     hal_kb_mod
        puls    x,y,u,pc

hal_kb_col      fcb     0
hal_kb_rows     fcb     0
hal_kb_idx      fcb     $FF
hal_kb_key      fcb     0
hal_kb_mod      fcb     0

                ifdef   OBJTARGET
                endsection
                endc

                endc                    ; HAL_KEYBOARD
