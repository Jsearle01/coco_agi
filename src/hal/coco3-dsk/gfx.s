* src/hal/coco3-dsk/gfx.s
*
* HAL Graphics subsystem — P2.3a implementation.
*
* Purpose:
*   HAL_gfx_init: initialize GIME for 320x192x4 double-buffered mode.
*   HAL_gfx_clear: fill active back buffer with palette index 0.
*   HAL_gfx_present: display buffer page_register identifies; swap displayed/draw buffers.
*
* Adapted from refs/GFXMODE3.ASM (Jay-authored, November 2025,
*   MAME-verified at authorship). Adaptation per P1.6 frame buffer
*   layout ($8000/$C000 instead of asm's $6000/$A000). EDTASM
*   single-quote operand comments converted to lwasm ';' syntax.
*   asm's START routine (ORCC, LDS, TFR A,DP) NOT ported here —
*   those are boot responsibilities, not HAL_gfx_init's job per A3.
*   asm's $FF90-last order REVERSED: P1.6 $8000/$C000 buffers are
*   in ROM territory; $FF90 must fire FIRST (see Step 1 note).
*
* Reference citations:
*   [ref: refs/GFXMODE3.ASM Jay-authored Nov 2025 — GIME register
*          values lines 36, 48-56 (mode/SAM); lines 57-64 (palette);
*          lines 39-45 / 108-113 (clear loop pattern)]
*   [ref: memory-map.md §4.8-4.9 — frame buffer CPU addresses]
*   [ref: memory-map.md §4.10 — initial GIME display state (frame B)]
*   [ref: memory-map.md §5 — GIME init sequence and mandatory order]
*   [ref: memory-map.md §6 — hal.inc address constants (KCOCO3_*)]
*   [ref: GIME-RM §10] — 320x192x4: $FF98=$80, $FF99=$15
*   [ref: GIME-RM §13] — VOFFSET = physical_addr / 8
*   [ref: GIME-RM §14] — init order; §14 prefers $FF90 last; P1.6
*                         $8000/$C000 layout requires FIRST (Step 1)
*   [ref: hal.inc — HAL_gfx_init/HAL_gfx_clear/HAL_gfx_present contracts]
*   [ref: conventions.md §2 — DP $00-$1F HAL scratch band]
*   [ref: conventions.md §3 — calling conventions]
*
* DP allocations (HAL scratch band $00-$1F):
*   $10-$11  hal_frame_hi/lo  (time.s — frame counter; not touched here)
*   $12      gfx_initialized  — $00 at reset; $01 after HAL_gfx_init
*
* P3 REPLACEMENT NOTES:
*   HAL_gfx_present: P2.3a.6-followup-1 implemented real VOFFSET swap.
*     P3 may refine to VBL-gated swap (HAL_time_vbl_wait integration).
*   HAL_gfx_init: P3 may add real MMU slot programming when A7 is
*     discharged (currently accepted as MAME-default MMU floor per plan
*     §A4/A7). HAL_gfx_init calls omitted per plan §4.4.
*
* METHODOLOGY OPEN ITEM (non-blocking):
*   $FF90/$FFD9/$FFDF register values are empirically known-good from
*   GFXMODE3.ASM (MAME-verified Nov 2025). Bit-level derivation from
*   GIME-RM not completed in P2.3a; carried forward as R4/R5 debt.
*   [no-ref: $FF90 INIT0 bit semantics from GIME-RM §4 — discharge P2.3a.1]
*   [no-ref: $FFD9/$FFDF SAM clock/RAM semantics — discharge P2.3a.1]
*
* ERR_NOMEM clause: HAL_gfx_init contract specifies ERR_NOMEM if frame
*   buffers cannot be allocated. In P2.3a, frame buffers are statically
*   allocated per P1.6 memory map ($8000-$BBFF, $C000-$FBFF). No
*   dynamic allocation; ERR_NOMEM is never returned. HAL_gfx_init
*   always returns CC.C clear in this implementation.
* ---------------------------------------------------------------

        ifdef   OBJTARGET
        * setdp is NOT permitted for the object target — the fourth
        * object-incompatible directive class (P2.4; the recon found three).
        * The HAL uses explicit `<` direct-mode operands, so omitting the
        * declaration changes nothing it relies on.
        else
        setdp   0
        endc
        
        ifdef   OBJTARGET
        * Object/linked build (POP, P2.4). Guard OFF = the absolute build
        * (karateka today): not one byte of this file changes.
        section code
        export  HAL_gfx_init
        export  HAL_gfx_clear
        export  HAL_gfx_present
        ifdef   HAL_GFX_MODE_SERVICE
        export  HAL_gfx_set_mode
        export  HAL_gfx_cur_mode
        export  HAL_gfx_cur_vres
        export  HAL_gfx_cur_stride
        export  HAL_gfx_cur_words
        export  HAL_gfx_cur_palcnt
        export  HAL_gfx_swap
        export  HAL_gfx_mirror
        export  HAL_gfx_draw_base
        export  HAL_gfx_cur_back
        export  HAL_gfx_swaps
        export  HAL_gfx_swaps_hi
        endc
        endc

* DP allocations and shared constants declared in src/engine/globals.s (P2.3a.3).
* [ref: src/engine/globals.s — canonical home]
*
* Symbols used here (defined in globals.s):
*   gfx_initialized equ $12  ; HAL gfx init flag
*   page_register   equ $50  ; active draw buffer (Option I back buffer)
*   PAGE_A_TOKEN    equ $20  ; draw target = buffer A
*   PAGE_B_TOKEN    equ $40  ; draw target = buffer B
*
* Frame buffer constants (HAL-private; defined locally here)
* [ref: memory-map.md §4.8-4.9]
GFX_FB_A_BASE       equ $8000       ; Frame A CPU base (back buffer initial)
GFX_FB_B_BASE       equ $C000       ; Frame B CPU base (front buffer initial)
GFX_FB_WORDS        equ $1E00       ; $3C00 bytes / 2 = $1E00 word stores

* ---------------------------------------------------------------
* HAL_gfx_init
*
* Initialize GIME for 320x192x4 double-buffered mode.
* Programs GIME mode registers, VOFFSET for initial display of
* frame B, clears both frame buffers, writes palette descriptor 0.
*
* ORIGIN: adapted from refs/GFXMODE3.ASM (Jay-authored Nov 2025,
*   MAME-verified). Register values from asm lines 36, 48-56, 57-64.
*   asm's $6000/$A000 layout DISCARDED per plan §A1 (use $8000/$C000).
*   asm's START sequence (ORCC, LDS, TFR A,DP) NOT ported per §A3.
*
* Args:    A = palette descriptor index (0 = Brøderbund default).
*          Only descriptor 0 is implemented. A != 0 falls through to
*          descriptor 0 (no panic; documented behavior per §A4).
* Returns: CC.C clear (always succeeds; ERR_NOMEM never raised,
*          frame buffers statically allocated per P1.6).
* Preserves: U, Y  [per hal.inc contract]
* Clobbers:  A, B, X, CC
*
* [ref: hal.inc HAL_gfx_init — contract specification]
* [ref: memory-map.md §5 — mandatory GIME init sequence]
* ---------------------------------------------------------------
HAL_gfx_init:
        pshs    u,y                     ; preserve U, Y per contract

* --- Step 1: Activate CoCo3 mode ($FF90) — MUST BE FIRST ---
* GIME INIT ORDERING CONSTRAINTS (empirical, per GFXMODE3.ASM Nov 2025):
*
*   CONSTRAINT A — $FF90 written FIRST:
*     Our framebuffers are at $8000-$FBFF (ROM territory under CoCo1/2 map).
*     $FF90=$4C transitions to CoCo3 map (COCO=0, all-RAM) so the framebuffer
*     is accessible. GFXMODE3 wrote $FF90 last because its framebuffers
*     ($6000-$9BFF) are accessible under either map type. We cannot.
*     [ref: GFXMODE3.ASM line 53-54 — LDA #$4C / STA $FF90]
*
*   CONSTRAINT B — Palette ($FFB0-$FFB3) written LAST:
*     Empirical observation from GFXMODE3 development (P2.3a.6-followup-3).
*     Palette writes do not appear to latch correctly until the GIME's video
*     mode ($FF98/$FF99) is in its final 4-color state. Writing palette before
*     $FF98/$FF99 causes indices 1-2 to render as black regardless of value.
*     NOT documented in SockmasterGime.md; inferred from working GFXMODE3 vs
*     broken pre-reorder HAL_gfx_init. Combined constraint:
*     $FF90 first → clear buffers → mode → VOFFSET → VSCROL → HOFFSET → SAM
*     → palette LAST.
*     [ref: GFXMODE3.ASM lines 48-64 — mode-before-palette ordering]
*
*   IEN PRESERVATION NOTE (HAL_gfx_init IEN fix, 2026-05-20):
*     Value written is $6C, not $4C. $6C = $4C | $20 (adds IEN=1, bit 5).
*     GFXMODE3.ASM used $4C (IEN=0) which is sufficient for a standalone
*     demo without interrupts. karateka-coco3 requires IEN=1 because
*     HAL_time_init (init order step 2) writes $FF90=$6C to enable GIME VBL
*     interrupts; HAL_gfx_init at step 3 must not clobber that bit.
*
*     $FF90 is write-only (reads return hardware status, not last-written
*     value; [ref: docs/project/interrupt-handling.md §8.4]). Read-modify-write is
*     impossible. All bits this function requires are preserved in $6C:
*     COCO=0, MMUEN=1, IEN=1, FEN=0, MC3=1, MC2=1, MC1=0, MC0=0.
*
*     Coupling: this value assumes IEN=1 is the correct state after
*     HAL_time_init. Safe for standalone drivers that omit HAL_time_init:
*     such drivers keep CC.I=1 throughout (per Q001.4/4.c — never opt in
*     to real-VBL). CPU never services IRQ regardless of GIME assertion
*     state, so IEN=1 is harmless in this configuration.
*     [ref: src/hal.inc INIT ORDER — time init (step 2) before gfx (step 3)]
*
        lda     #$6C                    ; == KCOCO3_INIT0_RUN (hal.inc) — IEN=1 MUST be
                                        ; re-asserted here or HAL_time_init's VBL interrupt
                                        ; dies silently. $FF90 is write-only: no RMW possible.
                                        ; Literal, not the symbol: hal.inc uses `import` and
                                        ; cannot be included in a --decb build.
        sta     $FF90                   ; INIT0: COCO=0,MMUEN=1,IEN=1,MC3=1,MC2=1

* --- Step 2: Clear Frame A ($8000-$BBFF, 15,360 bytes) ---
* [ref: GFXMODE3.ASM lines 39-45 — clear pattern]
* [ref: plan O2 — both buffers cleared at init time]
        ldx     #GFX_FB_A_BASE          ; $8000
        ldd     #$0000
        ldy     #GFX_FB_WORDS           ; $1E00 = 7,680 word stores = 15,360 bytes
gfx_init_clear_a:
        std     ,x++
        leay    -1,y
        bne     gfx_init_clear_a

* --- Step 3: Clear Frame B ($C000-$FBFF, 15,360 bytes) ---
        ldx     #GFX_FB_B_BASE          ; $C000
        ldy     #GFX_FB_WORDS
gfx_init_clear_b:
        std     ,x++
        leay    -1,y
        bne     gfx_init_clear_b

* --- Step 4: GIME video mode = 320x192x4 ---
* Mode written BEFORE palette (Constraint B above).
* [ref: GFXMODE3.ASM line 48 — LDD #$8015 / STD $FF98]
* [ref: GIME-RM §10] $FF98=$80 (VMODE: BP=1 graphics); $FF99=$15 (VRES: 320x192x4)
        ldd     #$8015
        std     $FF98                   ; $FF98=$80 VMODE; $FF99=$15 VRES

* --- Step 5: VOFFSET — point GIME at Frame B (initial front buffer) ---
* Initial state: GIME displays Frame B; engine renders to Frame A.
* [ref: memory-map.md §4.10 — "Initial state: GIME displays frame B"]
* [ref: memory-map.md §4.9 — Frame B physical $7C000]
* [ref: GIME-RM §13] VOFFSET = physical_addr / 8 = $7C000 / 8 = $F800
*   $FF9D=$F8 (high byte), $FF9E=$00 (low byte)
* VOFFSET CORRECTNESS: inferred from disassembly; NOT verified in P2.3a.
*   Discharge by P2.3a.1 sentinel test per plan §3.2 R6 amendment.
        ldd     #$F800
        std     $FF9D                   ; $FF9D=$F8 VOFFSET_HI; $FF9E=$00 VOFFSET_LO

* --- Step 6: VSCROL = 0 (REQUIRED; undefined at reset) ---
* [ref: memory-map.md §5 step 8] "$FF9C=$00 VSCROL = 0 (REQUIRED)"
        clr     $FF9C                   ; VSCROL = 0

* --- Step 7: HOFFSET = 0 (REQUIRED; undefined at reset) ---
* [ref: memory-map.md §5 step 9] "$FF9F=$00 HOFFSET = 0 (REQUIRED)"
        clr     $FF9F                   ; HOFFSET = 0

* --- Step 8: SAM clock + RAM ---
* [ref: GFXMODE3.ASM line 36 — STA $FFD9 (A=0, 1.78 MHz clock)]
* [ref: GFXMODE3.ASM line 56 — STA $FFDF (A=0, SAM RAM at $C000)]
* METHODOLOGY NOTE: bit semantics not derived from GIME-RM in P2.3a.
* Values are empirically known-good from MAME-verified asm. Carry as
* non-blocking open item; discharge bit-level derivation in P2.3a.1.
        clra
        sta     $FFD9                   ; SAM: 1.78 MHz CPU clock
        sta     $FFDF                   ; SAM: RAM at $C000 (task 0)

* --- Step 9: Palette descriptor 0 (Brøderbund) — MUST BE LAST ---
* Palette written AFTER all mode/offset/SAM setup (Constraint B above).
* [ref: GIME-RM §8] palette registers $FFB0-$FFB3, 6-bit GIME color codes.
*
* PALETTE FORMAT NOTE (P2.3a.6-followup-2):
* CoCo3 GIME palette registers support two interpretations:
*   1) RGB monitor:   bits 5:0 = R1 G1 B1 R0 G0 B0
*      [ref: docs/ground-truth/SockmasterGime.md lines 218-240]
*   2) Composite monitor: bits 5:4 = intensity (0-3), bits 3:0 = hue (0-15)
*      [ref: docs/ground-truth/SockmasterGime.md lines 241-242]
* MAME emulates CoCo3 in composite mode.
*
* Descriptor 0 (Brøderbund palette) — composite format, MAME-verified:
*   $00 = black     (intensity 0)
*   $26 = orange    (intensity 2, hue 6)   [MAME-verified Nov 2025]
*   $1B = blue/cyan (intensity 1, hue 11)  [MAME-verified Nov 2025]
*   $3F = white     (intensity 3, hue 15)
* [ref: refs/GFXMODE3.ASM lines 57-64 — palette programming]
*
* Only descriptor 0 implemented. A != 0 falls through to descriptor 0.
        lda     #$00
        sta     $FFB0                   ; palette index 0 (background / black)
        lda     #$26
        sta     $FFB1                   ; palette index 1 (orange)    — $26 composite hue 6, intensity 2
        lda     #$1B
        sta     $FFB2                   ; palette index 2 (blue/cyan) — $1B composite hue 11, intensity 1
        lda     #$3F
        sta     $FFB3                   ; palette index 3 (white)     — $3F composite intensity 3

* --- Step 10: Mark initialization complete ---
        lda     #$01
        sta     <gfx_initialized        ; $12 = $01 (init complete)

        puls    u,y                     ; restore U, Y per contract
        andcc   #$FE                    ; CC.C clear = success
        rts

                ifdef   HAL_GFX_MODE_SERVICE
* P2.5 KERNEL SERVICE -- compiled where a project asks for it.
* ONE shared source, per-project CONFIGURATION (governance rule 3), the same
* mechanism as the runtime-blit dormancy guard. POP defines the flag in its
* build.bat; karateka does not YET, so its absolute binary stays byte-identical
* and adopting the service later is a one-flag change, not a port.
* ===============================================================
* HAL_gfx_set_mode  [P2.5 — the first real kernel GRAPHICS SERVICE]
*
* Switch the display to a requested graphics mode. This generalizes the
* register programming that HAL_gfx_init hardcodes for 320x192x4.
*
* Args:    A = mode id (GFX_MODE_320x192x4 = 0, GFX_MODE_320x192x16 = 1)
*              Out-of-range falls back to mode 0, same documented behaviour
*              as HAL_gfx_init's palette-descriptor argument.
* Returns: CC.C clear (always succeeds; no failure mode exists — every
*          supported mode is statically allocatable).
* Preserves: U, Y   [per the hal.inc calling convention]
* Clobbers:  A, B, X, CC
*
* GUARANTEE TO THE CALLER, on return:
*   - display is in the requested mode
*   - the framebuffer is CLEARED to palette index 0
*   - that mode's palette is loaded
*   - HAL_gfx_cur_* describe the active geometry
*   - ready to draw. NOTHING carries over from the previous mode.
*
* WHY CLEAR-ON-SWITCH IS THE CONTRACT, not a convenience:
*   The two modes pack pixels differently (4 px/byte vs 2 px/byte). Surviving
*   pixels would not be "old content" under the new mode — they would be
*   reinterpreted as garbage at a different width. There is no meaningful way
*   to preserve them, so the service defines the slate as clean and the caller
*   never has to wonder.
*
* MODE VALUES — CONFIRMED FROM THE REFERENCE, NOT DERIVED (P2.5 §0.2):
*   [ref: docs/ground-truth/GIME_Reference_Manual.pdf §10 Video Mode Reference]
*     "320 x lines | 16 | 4 | 160 | 111 | 10 | $1E"   <- 192-line column
*     "320 x lines |  4 | 2 |  80 | 101 | 01 | $15"
*   [ref: docs/ground-truth/SockmasterGime.md:108-136 — $FF99 bit layout]
*     bits 6-5 LPF  00 = 192 scan lines
*     bits 4-2 HRES 111 = 160 bytes/row ; 101 = 80 bytes/row
*     bits 1-0 CRES  10 = 16 colours (2 px/byte) ; 01 = 4 colours (4 px/byte)
*   Both sources agree independently: $1E = %0 00 111 10.
*
* GEOMETRY DIFFERS AND IT IS NOT SUBTLE:
*   4-colour : 2 bpp,  80 B/row, 192 rows = 15,360 B ($3C00)
*   16-colour: 4 bpp, 160 B/row, 192 rows = 30,720 B ($7800)  <- DOUBLE
*   A caller that draws with the wrong stride does not fail loudly; it draws a
*   skewed diagonal. Hence HAL_gfx_cur_stride, published rather than assumed.
*
* SINGLE-BUFFERED BY CONSTRUCTION (P2.5 scope):
*   The framebuffer is FB_A ($8000) and VOFFSET points at it. 16-colour
*   double-buffering would need 2 x 30,720 = 60 KB of the 64 KB CPU window,
*   which is a real constraint for later animation work. NOT solved here;
*   recorded so the number is on the table when it matters.
*
* ORDERING — the codebase's empirically-proven sequence is used, and it
* DIFFERS from GIME-RM §14's generic example. Two deliberate divergences:
*   (1) $FF90 FIRST. Our framebuffer lives at $8000+, which is ROM territory
*       under the CoCo1/2 map, so the CoCo3 all-RAM map must exist before the
*       clear can write anything. GIME-RM's example uses $6000 and can afford
*       to write $FF90 late. We cannot. [HAL_gfx_init CONSTRAINT A]
*   (2) PALETTE LAST. GIME-RM §14 loads the palette at step 4, before the mode
*       registers. This codebase found empirically that palette writes do not
*       latch until $FF98/$FF99 hold their final values — indices render black
*       otherwise. [HAL_gfx_init CONSTRAINT B, MAME-verified]
*   Per CLAUDE.md §2, observed behaviour outranks documentation: the trace wins
*   on fact, the manual wins on intent. Recorded here so the divergence reads
*   as a decision rather than an oversight.
* ===============================================================
* The MODE IDs themselves live in hal.inc, not here — they are contract, not
* implementation. A caller that includes only the contract must be able to name
* the mode it wants; this file never uses them by name because its table is
* positional (row 0 = mode 0, row 1 = mode 1). One home each.
*   [ref: src/hal.inc — GFX_MODE_320x192x4 / GFX_MODE_320x192x16]
* ★★ GFX_MODE_MAX AND THE DESCRIPTOR TABLE ARE PROJECT-LOCAL (POP-HAL-01).
* They moved to src/hal/coco3-dsk/hal_globals.s, which hal_sync_check.py lists as
* PROJECT_LOCAL. The reason is not tidiness: this file is SHARED, and a shared table is a
* shared BINARY -- adding one 7-byte row for another project shifted every address after it
* and changed 27 of POP's artifacts. Shared mechanism, project-local data.
*
* ★★★ REQUIREMENT, DOCUMENTED RATHER THAN GUARDED: a project that defines
* HAL_GFX_MODE_SERVICE MUST define GFX_MODE_MAX and gfx_mode_table in its own hal_globals.s.
* Omit them and lwasm fails with "Undefined symbol gfx_mode_table" -- which NAMES the missing
* thing at assembly time. A guard was considered and rejected: it would replace a loud,
* self-describing failure with either a silent compile-out (the service present but inert) or
* a second symbol every project must keep in sync, which is more coupling, not less.
*
* GFX_MODE_ENTSZ stays HERE because the row LAYOUT is what this file's code indexes with; a
* project that changed it would break the shared service. Layout is mechanism, rows are data.
GFX_MODE_ENTSZ      equ 7           ; bytes per mode-descriptor row

* ===============================================================
* DOUBLE-BUFFER GEOMETRY (P2.6) — ONE model, BOTH modes.
*
* THE CORRECTION THIS RESTS ON. P2.5 shipped this service single-buffered and
* recorded a worry that 16-colour double-buffering would need 60 KB of the 64 KB
* CPU window. That was WRONG, and the error was reasoning about the CPU's view
* instead of the machine's. Framebuffers live in PHYSICAL RAM addressed by the
* GIME's VOFFSET register; the CPU only ever sees an MMU-mapped window onto part
* of it. There is no 60 KB wall and no forced choice — 16-colour double-buffers
* exactly like 4-colour, with bigger buffers at different physical addresses.
*
* PHYSICAL RAM: 512 KB, $00000-$7FFFF, blocks $00-$3F (8 KB each).
*   CONFIRMED, not assumed: `mame coco3 -listxml` reports
*   <ramoption name="512K" default="yes">524288</ramoption>.
*
* PLACEMENT — deliberately AWAY from the default-mapped top 64 KB:
*   buffer A  physical $20000  blocks $10-$13   VOFFSET $20000/8 = $4000
*   buffer B  physical $30000  blocks $18-$1B   VOFFSET $30000/8 = $6000
*   32 KB reserved per buffer, which is the 16-colour size (30,720 B) rounded up
*   to the 8 KB block granularity. 4-colour uses 15,360 B of the same reservation.
*
*   WHY NOT THE TOP 64 KB. The CoCo3 boots with CPU $0000-$FFFF mapped to physical
*   $70000-$7FFFF, so a buffer placed there overlaps the running program: this
*   program loads at CPU $0200 = physical $70200 and its kernel at CPU $3000 =
*   physical $73000. Drawing into such a buffer would overwrite the code doing the
*   drawing. Blocks $10-$1B are in the 448 KB the default map never touches.
*
* THE DRAW WINDOW: the BACK buffer is always mapped at CPU $6000 through MMU
* registers $FFA3-$FFA6 (CPU $6000-$DFFF, 32 KB).
*   [ref: GIME-RM §2 — $FFA0-$FFA7 MMU task set 0]
*   $FFA3 -> $6000  $FFA4 -> $8000  $FFA5 -> $A000  $FFA6 -> $C000
*
*   WHY $8000 (MOVED from $6000 in P3.2). The first real screen carries a 26,880-byte
*   image asset; a program loading at $0200 with that much data runs past $6000, into
*   the window itself. Moving the window to $8000 ($FFA4-$FFA7) gives the program
*   $0200..$7FFF and keeps the two apart.
*
*   The cost is that $FFA7 (CPU $E000-$FFFF) is now remapped, which P2.6 deliberately
*   avoided because that block holds the stack and vector area. Two facts make it
*   safe and BOTH must hold: $FF00-$FFFF is ALWAYS I/O regardless of the MMU, and
*   MC3=1 in $FF90 holds $FE00-$FEFF constant, so the secondary vectors are not
*   remapped either. What IS remapped is $E000-$FDFF, which the framebuffer
*   legitimately occupies ($8000 + $7800 = $F800).
*
*   THE CALLER REQUIREMENT MOVES WITH IT: the stack must now be BELOW $8000, not
*   merely outside $6000-$DFFF.
*
* CALLERS DRAW AT HAL_gfx_draw_base AND NEVER AT A BUFFER ADDRESS. The physical
* addresses above are HAL-private on purpose: a caller that learns one of them
* would be writing to whichever buffer happens to be mapped, which is a bug that
* only shows up as a tear.
* ===============================================================
GFX_DB_WINDOW       equ $8000       ; CPU address the BACK buffer is mapped at
GFX_DB_MMU          equ $FFA4       ; first MMU reg covering the window
GFX_DB_BLOCKS       equ 4           ; 4 x 8 KB = 32 KB window
* THE TWO BUFFERS ARE ADJACENT, AND THAT IS A 128 KB REQUIREMENT (P3.10).
* The GIME masks a block number to the RAM actually installed, so on a 128 KB
* machine only $00-$0F exist and every number aliases mod 16:
*
*     CPU map   $38-$3B  ->  $08-$0B      (sys.s sets $FFA0-$FFA7 = $38-$3F)
*     buffer A  $10-$13  ->  $00-$03      clear
*     buffer B  $18-$1B  ->  $08-$0B      ON TOP OF THE PROGRAM AND KERNEL
*
* B at $18 is fine on 512 KB and fatal on 128 KB: the port loaded, started, and
* died at the first framebuffer access. $14 aliases to $04-$07 instead, so the
* two buffers sit adjacent in both configurations and nothing overlaps the code.
* On 128 KB that leaves $0C-$0F -- 32 KB, exactly one screen -- free.
GFX_DB_A_BLOCK      equ $10         ; buffer A, physical $20000 (128K: $00000)
GFX_DB_B_BLOCK      equ $14         ; buffer B, physical $28000 (128K: $08000)
GFX_DB_A_VOFF       equ $4000       ; $20000 / 8
GFX_DB_B_VOFF       equ $5000       ; $28000 / 8

HAL_gfx_set_mode:
        pshs    u,y                     ; preserve U, Y per contract

        cmpa    #GFX_MODE_MAX
        bls     gfx_sm_ok
        clra                            ; unsupported -> mode 0 (documented)
gfx_sm_ok:
        sta     HAL_gfx_cur_mode
        ldb     #GFX_MODE_ENTSZ
        mul                             ; D = mode * entry size
        ldx     #gfx_mode_table
        leax    d,x                     ; X -> this mode's descriptor

* --- publish the geometry BEFORE touching hardware ---------------
* Callers read these; the clear below uses them too, so there is exactly one
* source for "how big is the screen" and it cannot disagree with itself.
        lda     ,x                      ; $FF99 (VRES) value
        sta     HAL_gfx_cur_vres
        lda     1,x                     ; stride, bytes per row
        sta     HAL_gfx_cur_stride
        ldd     2,x                     ; framebuffer size in WORDS
        std     HAL_gfx_cur_words
        ldu     4,x                     ; -> palette table
        lda     6,x                     ; palette entry count
        sta     HAL_gfx_cur_palcnt

* --- Step 1: CoCo3 map FIRST (Constraint A) ----------------------
* $6C == KCOCO3_INIT0_RUN: COCO=0, MMUEN=1, IEN=1, MC3=1, MC2=1.
* Write-only register; no read-modify-write is possible. IEN=1 is re-asserted
* because HAL_time_init depends on it and would die silently if cleared.
        lda     #$6C
        sta     $FF90

* --- Step 2: build the DOUBLE buffer and clear BOTH halves --------
* Clear-on-switch means BOTH buffers, not just the visible one: the caller is
* promised a clean slate and the very first swap reveals the other half.
*
* Each buffer is mapped into the draw window in turn, because they live in
* PHYSICAL RAM the CPU cannot see two of at once (see the header).
        clr     HAL_gfx_cur_back        ; buffer A is the first draw target
        lda     #GFX_DB_B_BLOCK
        jsr     gfx_map_blocks
        jsr     gfx_clear_window        ; clear B (the initial FRONT)
        lda     #GFX_DB_A_BLOCK
        jsr     gfx_map_blocks
        jsr     gfx_clear_window        ; clear A, and leave A mapped = BACK

* --- Step 3: video mode + resolution -----------------------------
        lda     #$80                    ; VMODE: BP=1 graphics
        sta     $FF98
        lda     HAL_gfx_cur_vres        ; VRES: $15 (4-col) or $1E (16-col)
        sta     $FF99

* --- Step 4: VOFFSET -> buffer B (the FRONT while A is drawn) ----
* VOFFSET = physical / 8  [ref: GIME-RM §13]. B is physical $30000, so
* $30000 / 8 = $6000. Displaying B while the caller draws into A is what makes
* the first frame appear without a flash of half-drawn content.
        ldd     #GFX_DB_B_VOFF
        std     $FF9D

* --- Step 5: VSCROL / HOFFSET = 0 (REQUIRED, undefined at reset) -
        clr     $FF9C
        clr     $FF9F

* --- Step 6: SAM clock + RAM -------------------------------------
        clra
        sta     $FFD9                   ; 1.78 MHz CPU clock
        sta     $FFDF                   ; RAM at $C000 (task 0)

* --- Step 7: PALETTE LAST (Constraint B) -------------------------
* U -> this mode's palette table, A = entry count (4 or 16). Writing these
* before $FF98/$FF99 settle makes indices render black; see the header.
        ldx     #$FFB0
        ldb     HAL_gfx_cur_palcnt
gfx_sm_pal:
        lda     ,u+
        sta     ,x+
        decb
        bne     gfx_sm_pal

        lda     #$01
        sta     <gfx_initialized        ; the display is live and usable

        puls    u,y
        andcc   #$FE                    ; CC.C clear = success
        rts

* ===============================================================
* HAL_gfx_swap  [P2.6 — the VBL-synced buffer flip]
*
* Show the buffer the caller just drew, then map the other one in as the new
* draw target. This is the whole point of double-buffering: the caller never
* draws into memory the GIME is scanning out.
*
* Args:    none
* Returns: CC.C clear (always succeeds)
* Preserves: U, Y
* Clobbers:  A, B, X, CC
*
* ORDER MATTERS, AND IT IS NOT ARBITRARY:
*   1. WAIT for vertical blank. Writing VOFFSET mid-scanline switches the
*      GIME's source address while it is drawing, which is a visible tear —
*      the top of the frame comes from one buffer and the bottom from the
*      other. Waiting is what makes the flip atomic to the eye.
*   2. WRITE VOFFSET to the just-drawn buffer, which becomes the front.
*   3. TOGGLE the back index and MAP that buffer into the window, so the
*      caller's next draw lands in the newly hidden half.
*
* THE CC.I TRAP — the one thing that silently un-does all of this:
*   HAL_time_vbl_wait has a documented fallback (Q001 N3=beta). If CC.I is SET,
*   it does NOT wait — it synthesises a frame-counter increment and returns
*   immediately. A caller that leaves interrupts masked therefore gets a swap
*   loop that runs flat out at CPU speed and flips VOFFSET at arbitrary raster
*   positions. It compiles, it runs, the counters advance, and it tears.
*   The caller MUST install the handler (HAL_time_init) and CLEAR CC.I
*   (andcc #$EF) before animating. HAL_time_init deliberately does not clear it
*   (the E1.c invariant: HAL init never changes the caller's mask state), so
*   this is the caller's job and nothing will remind them.
*   [ref: src/hal/coco3-dsk/time.s — HAL_time_vbl_wait, hal_vbl_synthetic]
* ===============================================================
HAL_gfx_swap:
        pshs    u,y

* --- 1. wait for vertical blank (see the CC.I trap above) --------
        jsr     HAL_time_vbl_wait

* --- 2. display the buffer just drawn ---------------------------
        lda     HAL_gfx_cur_back
        bne     gfx_sw_show_b
        ldd     #GFX_DB_A_VOFF
        bra     gfx_sw_store
gfx_sw_show_b:
        ldd     #GFX_DB_B_VOFF
gfx_sw_store:
        std     $FF9D                   ; VOFFSET hi/lo in one 16-bit write

* --- 3. the other buffer becomes the new draw target ------------
        lda     HAL_gfx_cur_back
        eora    #$01
        sta     HAL_gfx_cur_back
        bne     gfx_sw_map_b
        lda     #GFX_DB_A_BLOCK
        bra     gfx_sw_map
gfx_sw_map_b:
        lda     #GFX_DB_B_BLOCK
gfx_sw_map:
        jsr     gfx_map_blocks

        inc     HAL_gfx_swaps           ; observable: swaps actually performed
        bne     gfx_sw_done
        inc     HAL_gfx_swaps_hi
gfx_sw_done:
        puls    u,y
        andcc   #$FE                    ; CC.C clear = success
        rts

* ===============================================================
* HAL_gfx_mirror — make the FRONT buffer identical to the BACK one.
*
* WHY THIS EXISTS (POP P3.17). A page-flipping caller that draws a small animation
* over a STILL background needs that background in both buffers, and the obvious way
* to get it there is to produce it twice. The cutscene room did exactly that and Jay
* saw the cost: the room was swapped into view as soon as it existed, and the second
* copy was then built while the finished picture sat on screen -- first as a second
* disk read (~2 s), then, once that was removed, as a second LZ expand (15 frames,
* 0.25 s). Both are the same shape of bug: work done AFTER the reveal that the viewer
* has to wait through.
*
* Copying is strictly cheaper than reproducing, and doing it BEFORE the first swap
* costs the viewer nothing at all, because the screen is still black. The caller
* builds its picture once, calls this, and swaps -- and both buffers are ready at the
* instant anything becomes visible.
*
* HOW BOTH BUFFERS ARE MAPPED AT ONCE. Normally they cannot be: the window is 32 KB
* and gfx_map_blocks fills all four blocks with ONE buffer, which is what keeps a
* caller from ever writing to the displayed page by accident. But a 4-colour
* framebuffer is 15,360 B -- under half the window -- so the two fit side by side:
* back at $8000, front at $C000. That is a property of the MODE, not of the HAL, so
* this routine CHECKS it rather than assuming it, and refuses in 16-colour where a
* 30,720 B framebuffer needs all four blocks to itself.
*
* The destination top is $C000+15,360 = $FC00, which stays below the $FE00 constant-
* RAM boundary. 16-colour would need $10000 and is exactly what the guard rejects.
*
* Entry: nothing. Exit: CC.C clear = mirrored, CC.C set = refused (mode too large).
* Clobbers: A, B, X, and restores the normal single-buffer mapping either way.
* ===============================================================
GFX_MIRROR_MAX  equ     8192            ; framebuffer WORDS that fit in half a window

HAL_gfx_mirror:
        pshs    u,y

        ldd     HAL_gfx_cur_words
        cmpd    #GFX_MIRROR_MAX
        bhi     gfx_mir_refuse          ; 16-colour: no room for two at once
        tstb
        bne     gfx_mir_ok
        tsta
        beq     gfx_mir_refuse          ; zero-size: nothing sane to copy
gfx_mir_ok:
        pshs    b,a                     ; keep the word count

* --- map BACK low and FRONT high, as one critical section --------
* Same hazard gfx_map_blocks documents: between the first MMU write and the last,
* the window is half one thing and half another. Nothing may run in that gap.
        pshs    cc
        orcc    #$50
        lda     HAL_gfx_cur_back
        bne     gfx_mir_back_b
        lda     #GFX_DB_A_BLOCK         ; back = A low, front = B high
        ldb     #GFX_DB_B_BLOCK
        bra     gfx_mir_setmmu
gfx_mir_back_b:
        lda     #GFX_DB_B_BLOCK         ; back = B low, front = A high
        ldb     #GFX_DB_A_BLOCK
gfx_mir_setmmu:
        sta     GFX_DB_MMU              ; $FFA4 -> $8000, back buffer
        inca
        sta     GFX_DB_MMU+1            ; $FFA5 -> $A000
        stb     GFX_DB_MMU+2            ; $FFA6 -> $C000, front buffer
        incb
        stb     GFX_DB_MMU+3            ; $FFA7 -> $E000
        puls    cc

* --- the copy, 16 bytes per pass --------------------------------
* Unrolled eight ways because the loop overhead is otherwise a third of the cost.
* The count is in WORDS, so eight `ldd`s consume eight of them per pass; the
* framebuffer word counts are all multiples of eight (7,680 for 4-colour), which the
* mode table guarantees and the guard above keeps true.
        ldx     #GFX_DB_WINDOW          ; $8000, the back buffer
        ldu     #GFX_DB_WINDOW+$4000    ; $C000, the front buffer
        ldd     ,s                      ; word count
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb                            ; /8 = passes
        std     ,s
gfx_mir_loop:
        ldd     ,x++
        std     ,u++
        ldd     ,x++
        std     ,u++
        ldd     ,x++
        std     ,u++
        ldd     ,x++
        std     ,u++
        ldd     ,x++
        std     ,u++
        ldd     ,x++
        std     ,u++
        ldd     ,x++
        std     ,u++
        ldd     ,x++
        std     ,u++
        ldd     ,s
        subd    #1
        std     ,s
        bne     gfx_mir_loop
        leas    2,s                     ; drop the count

* --- put the normal single-buffer mapping back ------------------
        lda     HAL_gfx_cur_back
        bne     gfx_mir_remap_b
        lda     #GFX_DB_A_BLOCK
        bra     gfx_mir_remap
gfx_mir_remap_b:
        lda     #GFX_DB_B_BLOCK
gfx_mir_remap:
        jsr     gfx_map_blocks
        puls    u,y
        andcc   #$FE                    ; CC.C clear = mirrored
        rts

gfx_mir_refuse:
        puls    u,y
        orcc    #$01                    ; CC.C set = caller must fill it itself
        rts

* ---------------------------------------------------------------
* gfx_map_blocks — map GFX_DB_BLOCKS consecutive physical blocks starting at A
* into the draw window ($FFA3-$FFA6). HAL-private.
*
* Blocks are consecutive because a framebuffer is contiguous physical memory;
* the MMU just needs to be told which run of 8 KB pages it is.
* Clobbers: A, B, X
* ---------------------------------------------------------------
* INTERRUPTS MASKED ACROSS THE WHOLE REMAP -- this is a CRITICAL SECTION.
*
* Writing GFX_DB_BLOCKS MMU registers is a MULTI-STEP update of the CPU memory
* map. Between the first write and the last, the window is half old buffer and
* half new. An interrupt taken in that gap runs with a memory map that never
* legitimately exists; nothing about the handler is wrong, the machine underneath
* it is inconsistent.
*
* MEASURED, NOT ASSUMED (P2.9). With the remap unmasked, a probe drawing fast
* enough to keep landing in that window fails reproducibly under the DECB load
* path; masking ONLY these four writes makes it pass 27/27. Two earlier theories
* (stack-clobber, ROM-residency) were killed by measurement before this one was
* confirmed by it -- and the variable was SPEED, which is what pointed at an
* asynchronous interaction in the first place.
*
* THE DISCIPLINE IS KARATEKA-S, NOT NEW. HAL_time_frame_count masks IRQ around
* its two-byte read of the interrupt-updated frame counter for exactly this
* reason: the 6809 offers no atomicity across multiple accesses, so any state the
* interrupt context can observe part-way through must be made atomic by masking.
* [ref: src/hal/coco3-dsk/time.s -- HAL_time_frame_count, the R-vbl race fix]
*
* CC is saved/restored, so a caller that had interrupts masked stays masked (the
* E1.c invariant: HAL routines never change the caller mask state).
gfx_map_blocks:
        pshs    cc                      ; save caller mask state
        orcc    #$50                    ; mask IRQ+FIRQ -- remap is atomic
        ldx     #GFX_DB_MMU
        ldb     #GFX_DB_BLOCKS
gfx_map_lp:
        sta     ,x+                     ; MMU reg <- physical block number
        inca                            ; next 8 KB block
        decb
        bne     gfx_map_lp
        puls    cc                      ; restore caller CC exactly
        rts

* ---------------------------------------------------------------
* gfx_clear_window — zero whichever buffer is currently mapped, using the
* ACTIVE mode's size. HAL-private.
*
* The length comes from HAL_gfx_cur_words, the same value callers read, so
* "how big is the screen" has exactly one source and the clear cannot disagree
* with the geometry the caller is drawing against.
* Clobbers: A, B, X, Y
* ---------------------------------------------------------------
gfx_clear_window:
        ldx     #GFX_DB_WINDOW
        ldd     #$0000
        ldy     HAL_gfx_cur_words
gfx_cw_lp:
        std     ,x++
        leay    -1,y
        bne     gfx_cw_lp
        rts

* ---------------------------------------------------------------
* The mode descriptor table lives in hal_globals.s (PROJECT_LOCAL) -- see the note at
* GFX_MODE_ENTSZ above. Row layout, which IS shared and is what the code below indexes with
* (GFX_MODE_ENTSZ = 7):
*   +0  $FF99 VRES value
*   +1  stride, bytes per row
*   +2  framebuffer size in WORDS (bytes / 2, the clear loop's unit)
*   +4  pointer to palette table
*   +6  palette entry count
*
* The PALETTES stay here, below, and are shared: a project-local row may point at gfx_pal4 or
* gfx_pal16, or at a palette of its own defined beside its table. gfx_pal4 in particular has a
* checked consumer -- harness/tools/palette_check.py reads it out of THIS file by path.
* ---------------------------------------------------------------

gfx_pal4:
        fcb     $00                     ; 0 black
        fcb     $26                     ; 1 orange  R=3 G=1 B=0
        fcb     $19                     ; 2 blue    R=0 G=2 B=3
        fcb     $3F                     ; 3 white   R=3 G=3 B=3

gfx_pal16:
        fcb     $00                     ;  0 black      R0 G0 B0
        fcb     $07                     ;  1 dk grey    R1 G1 B1
        fcb     $38                     ;  2 grey       R2 G2 B2
        fcb     $3F                     ;  3 white      R3 G3 B3
        fcb     $24                     ;  4 red        R3 G0 B0
        fcb     $26                     ;  5 orange     R3 G1 B0
        fcb     $36                     ;  6 yellow     R3 G3 B0
        fcb     $12                     ;  7 green      R0 G3 B0
        fcb     $1B                     ;  8 cyan       R0 G3 B3
        fcb     $09                     ;  9 blue       R0 G0 B3
        fcb     $2D                     ; 10 magenta    R3 G0 B3
        fcb     $04                     ; 11 dk red     R1 G0 B0
        fcb     $02                     ; 12 dk green   R0 G1 B0
        fcb     $01                     ; 13 dk blue    R0 G0 B1
        fcb     $1D                     ; 14 lt blue    R1 G2 B3
        fcb     $33                     ; 15 lt green   R2 G3 B1

* ---------------------------------------------------------------
* Published geometry of the ACTIVE mode. Callers read these to draw with the
* right stride; the service itself uses them for the clear, so there is one
* source of truth rather than two that can drift.
* ---------------------------------------------------------------
HAL_gfx_cur_mode:   fcb 0               ; active mode id
HAL_gfx_cur_vres:   fcb 0               ; $FF99 value written for it
HAL_gfx_cur_stride: fcb 0               ; bytes per row (80 or 160)
HAL_gfx_cur_words:  fdb 0               ; framebuffer size in words
HAL_gfx_cur_palcnt: fcb 0               ; palette entries loaded (4 or 16)
* --- double-buffer state (P2.6) ---
HAL_gfx_draw_base:  fdb GFX_DB_WINDOW   ; CPU address of the BACK buffer. Callers
                                        ;   draw HERE and nowhere else.
HAL_gfx_cur_back:   fcb 0               ; which buffer is the draw target: 0=A 1=B
HAL_gfx_swaps_hi:   fcb 0               ; swaps performed, high byte
HAL_gfx_swaps:      fcb 0               ;   ... low byte. Proof the flip ran.

                endc                    ; HAL_GFX_MODE_SERVICE

* ---------------------------------------------------------------
* HAL_gfx_clear
*
* Fill active back buffer with palette index 0 (background = $00).
* Never writes to the front buffer (D.3 back-buffer discipline).
*
* Back buffer is determined by page_register (DP $50):
*   PAGE_A token ($20) → back buffer = Frame A ($8000-$BBFF)
*   PAGE_B token ($40) → back buffer = Frame B ($C000-$FBFF)
* page_register MUST be initialized before calling HAL_gfx_clear.
*
* ORIGIN: clear loop pattern from refs/GFXMODE3.ASM lines 108-113.
*   Loop adapted to back-buffer-only discipline; asm cleared all of
*   WORK_SCREEN ($A000) without HAL buffer abstraction.
*
* Args:    none
* Returns: CC.C clear
* Preserves: U  [per hal.inc contract]
* Clobbers:  A, B, X, Y, CC
*
* [ref: hal.inc HAL_gfx_clear — contract; "never writes to front"]
* [ref: src/engine/timer_framesync.s — page_register equ $50]
* ---------------------------------------------------------------
HAL_gfx_clear:
* ★★★ THE GEOMETRY IS ASKED FOR, NOT ASSUMED (P5.18). This routine took BOTH of its
* facts from the FOUR-COLOUR layout: the BASE from page_register ($8000 or $C000), and the
* LENGTH from a fixed GFX_FB_WORDS. Both are right for 320x192x4, where two whole 15,360 B
* framebuffers sit side by side in one window. Mode 1 is 320x192x16 -- ONE 30,720 B buffer
* across all four blocks -- and there $C000 is not a second page at all: it is the BOTTOM
* HALF of the only one. So this cleared the bottom half of the picture and left the top,
* which is exactly what Jay reported: "the bottom half of the screen ... disappears".
*
* ★★ set_mode ALREADY CLAIMED THIS WAS TRUE, where it publishes the geometry: "Callers read
* these; THE CLEAR BELOW USES THEM TOO, so there is exactly one source for how big is the
* screen and it cannot disagree with itself." It did not use them. The invariant was stated,
* believed, and never held -- which is why it survived: nothing that ran was wrong until a
* 16-colour caller appeared, and POP's first one arrived at P5.16e.
*
* ★ THE DISCRIMINATOR IS HAL_gfx_mirror'S, deliberately -- that routine already decides this
* same question the same way ("16-colour: no room for two at once"), and two different tests
* for one fact is how they drift apart.
*
* ★★ AND THE MODE SERVICE IS OPTIONAL, WHICH SHAPES THE WHOLE ROUTINE. HAL_gfx_cur_words
* and HAL_gfx_draw_base live inside `ifdef HAL_GFX_MODE_SERVICE`; this routine sits after its
* endc. POP defines the guard (build.bat) and karateka does not, so with the guard OFF those
* symbols do not exist and the old fixed-size path is not merely acceptable, it is the only
* one that resolves -- and it is CORRECT there, because without a mode service there is one
* mode and $1E00 is its size. Guard off, the code below assembles to exactly what it always
* did, byte for byte.
                ifdef   HAL_GFX_MODE_SERVICE
        ldy     HAL_gfx_cur_words       ; the MODE's size, not a constant
        beq     gfx_clear_done          ; zero-size mode: 0 would wrap to 65,536 stores
        cmpy    #GFX_MIRROR_MAX
        bls     gfx_clear_two_buf       ; fits half a window => 4-colour, two side by side
        ldx     HAL_gfx_draw_base       ; 16-colour: ONE buffer, and the HAL's own contract
        bra     gfx_clear_common        ;   names where it is -- "callers draw at
gfx_clear_two_buf:                      ;   HAL_gfx_draw_base and never at a buffer address"
                endc
        lda     <page_register               ; read page_register ($50)
        cmpa    #PAGE_A_TOKEN           ; PAGE_A=$20 → back=frame A
        bne     gfx_clear_b_buf
        ldx     #GFX_FB_A_BASE          ; back buffer = Frame A ($8000)
        bra     gfx_clear_common
gfx_clear_b_buf:
        ldx     #GFX_FB_B_BASE          ; back buffer = Frame B ($C000)
gfx_clear_common:
        ldd     #$0000                  ; clear value (palette index 0 = $00 per byte)
                ifndef  HAL_GFX_MODE_SERVICE
        ldy     #GFX_FB_WORDS           ; $1E00 word stores = 15,360 bytes
                endc
gfx_clear_loop:
        std     ,x++
        leay    -1,y
        bne     gfx_clear_loop
gfx_clear_done:
        andcc   #$FE                    ; CC.C clear = success
        rts

* ---------------------------------------------------------------
* HAL_gfx_present  [P2.3a.5 real implementation]
*
* Swap the GIME-displayed buffer by writing VOFFSET ($FF9D/$FF9E).
* Reads page_register (DP $50) — the CURRENT BACK BUFFER (active draw
* target) — then writes VOFFSET so GIME displays that buffer, making
* the just-drawn content visible.
*
* Option I convention (P2.3a.6-followup-1 — canonical):
*   page_register holds the BACK buffer (draw target). HAL_gfx_present
*   displays the buffer page_register identifies (the one just drawn to).
*   Caller flow: draw → HAL_gfx_present → toggle page_register for next draw.
*
*   PAGE_A_TOKEN ($20) → buffer A was the draw target.
*                        HAL_gfx_present writes VOFFSET for Frame A
*                        ($F000/$00). GIME displays Frame A.
*   PAGE_B_TOKEN ($40) → buffer B was the draw target.
*                        HAL_gfx_present writes VOFFSET for Frame B
*                        ($F800/$00). GIME displays Frame B.
*
* CONVENTION NOTE: "page_register" identifies the BACK buffer (draw
*   target). Convention established in P2.1 with timer_framesync.s.
*   See docs/project/conventions.md §2 frame-coherent band.
*
* NOTE on PAGE_A_TOKEN ($20) / PAGE_B_TOKEN ($40): Apple II heritage.
*   On Apple II, $20/$40 are the high bytes of hires page base addresses
*   ($2000/$4000). On CoCo3 they are opaque draw-target tokens; they have
*   no CoCo3 hardware significance.
*   [ref: src/engine/globals.s — token declarations and heritage note]
*
* CALLER CONTRACT (Option I):
*   - Caller draws to the buffer page_register points at.
*   - Caller calls HAL_gfx_present — displays the just-drawn buffer.
*   - Caller toggles page_register to designate the new draw target.
*   - HAL_gfx_present does NOT modify page_register.
*
* NO VBL gating. This implementation writes VOFFSET immediately without
* waiting for vertical blanking. Tearing may occur if called mid-scanline.
* VBL synchronization is deferred to P3.2.
*
* VOFFSET derivation:
*   Frame A physical $78000: VOFFSET = $78000/8 = $F000 → $FF9D=$F0,$FF9E=$00
*   Frame B physical $7C000: VOFFSET = $7C000/8 = $F800 → $FF9D=$F8,$FF9E=$00
*   [ref: GIME-RM §13] VOFFSET = physical_addr / 8
*   [ref: memory-map.md §4.8-4.9] physical addresses for Frame A/B
*
* Args:    none (reads page_register from DP $50)
* Returns: CC.C clear
* Preserves: U, Y
* Clobbers: A, B, D, CC
*
* [ref: src/engine/timer_framesync.s — page_register equ $50]
* [ref: hal.inc HAL_gfx_present — contract]
* [ref: memory-map.md §4.10 — GIME VOFFSET swap mechanism]
* ---------------------------------------------------------------
HAL_gfx_present:
        pshs    u,y                     ; preserve U, Y per contract

        ; Option I convention (P2.3a.6-followup-1):
        ;   page_register holds the BACK buffer (just drawn to).
        ;   HAL_gfx_present displays the buffer page_register identifies.
        ;   Caller flow: draw → HAL_gfx_present → toggle page_register for next draw.
        lda     <page_register               ; read back-buffer token (buffer just drawn to)
        cmpa    #PAGE_A_TOKEN           ; is frame A the current draw target (back)?
        beq     gfx_present_show_a      ; yes → GIME displays frame A (just drawn)

        ldd     #$F800                  ; frame B VOFFSET ($FF9D=$F8, $FF9E=$00)
        bra     gfx_present_write

gfx_present_show_a:
        ldd     #$F000                  ; frame A VOFFSET ($FF9D=$F0, $FF9E=$00)

gfx_present_write:
        std     $FF9D                   ; write VOFFSET: $FF9D=hi, $FF9E=lo
                                        ; [ref: GIME-RM §13] VOFFSET registers

        puls    u,y                     ; restore U, Y per contract
        andcc   #$FE                    ; CC.C clear = success
        rts

* ---------------------------------------------------------------
* HAL_gfx_blit_sprite  [P2.4.1 sub-byte runtime shifter]
*
* Blit a CoCo3 packed sprite into the active back buffer at a sub-byte-
* precise position. Implements runtime pixel-shift equivalent to the
* Apple II Karateka L1A84 mechanism (karateka_dissasembly_claude/
* src/video.s lines 391-492).
*
* Sprite data format (per P1.2 / tools/sprite_convert.py):
*   byte 0:  height (number of rows)
*   byte 1:  coco3_width (bytes per row; 4 pixels per byte, 2bpp MSB-first)
*   bytes 2+: packed bitmap, row-major, top-to-bottom
*
* Sub-byte shift mechanism (CoCo3 2bpp, 4 pixels per byte):
*   subbyte=0: no shift; byte-aligned blit (fast path)
*   subbyte=1: 2-bit right shift; output=src>>2, overflow=(src&0x03)<<6
*   subbyte=2: 4-bit right shift; output=src>>4, overflow=(src&0x0F)<<4
*   subbyte=3: 6-bit right shift; output=src>>6, overflow=(src&0x3F)<<2
*   Overflow from each source byte is OR-merged into the next dest byte.
*   The effective output width is (sprite_width + 1) bytes when subbyte>0.
*
* Apple II port note: Apple II has 7 pixels per byte (1bpp), so L1A84
* dispatches on 7 shift values (0-6) and uses 1-bit shift units. CoCo3
* has 4 pixels per byte (2bpp), so 4 shift values (0-3) with 2-bit units.
* The LSR/ROR mechanics are identical in structure; only the number of
* shift cases and bits-per-shift differ.
*
* Cycle estimate per source byte (static analysis):
*   subbyte=0: ~10 cy (lda ,x+ + sta ,y+ + loop overhead)
*   subbyte=1: ~47 cy (2×LSR + 2×ROR + OR-blend + overflow handling)
*   subbyte=2: ~55 cy (4×LSR + 4×ROR + OR-blend + overflow)
*   subbyte=3: ~63 cy (6×LSR + 6×ROR + OR-blend + overflow)
* For a 4-byte × 10-row sprite at subbyte=1: ~1880 cycles.
*
* Back buffer selected by page_register (DP $50, Option I convention):
*   PAGE_A_TOKEN ($20) → buffer A ($8000-$BBFF)
*   PAGE_B_TOKEN ($40) → buffer B ($C000-$FBFF)
* Row stride is 80 bytes (320px / 4px per byte).
*
* DP scratch (HAL internal band $08-$0F per conventions.md §2):
*   $08  blit_height  — sprite height (row loop counter)
*   $09  blit_width   — sprite width in bytes (inner loop count per row)
*   $0A  blit_col     — destination byte column (saved from A arg)
*   $0B  blit_row     — destination pixel row (saved from B arg)
*   $0C  blit_subbyte — sub-byte pixel offset 0-3 (set by CALLER before call)
*   $0D  blit_ovf_new — per-byte overflow accumulator (HAL internal, shifted bits)
*   $0E  blit_ovf_prev— per-row overflow carry (HAL internal, OR'd into next dest byte)
*
* Args:    X = pointer to sprite data (height byte + width byte + rows)
*          A = destination byte column (0-79; 4 pixels per byte)
*          B = destination pixel row (0-191)
*          ZP $0C (blit_subbyte) = sub-byte pixel offset (0-3); CALLER MUST SET
* Returns: CC.C clear on success
*          CC.C set, A = ERR_INVALID if sprite extends beyond frame buffer
* Preserves: U
* Clobbers: A, B, X, Y, CC, ZP $0D/$0E
*
* Limitation: bounds check does not account for the +1 overflow byte
* when subbyte>0. Caller must ensure col+width <= 78 when subbyte>0.
*
* [ref: hal.inc HAL_gfx_blit_sprite — contract specification]
* [ref: docs/project/conventions.md §2 — DP $08-$0F HAL internal scratch band]
* [ref: karateka_dissasembly_claude/src/video.s L1A84 lines 391-492]
* [ref: Apple II sub-byte inspection report (2026-05-17)]
* ---------------------------------------------------------------

* HAL-private DP scratch locations for blit (HAL internal band $08-$0F)
blit_height     equ $08                 ; sprite row count (loop counter)
blit_width      equ $09                 ; sprite bytes per row (inner count)
blit_col        equ $0A                 ; destination byte column (0-79)
blit_row        equ $0B                 ; destination pixel row (0-191)
blit_subbyte    equ $0C                 ; sub-byte pixel offset 0-3 (set by caller)
blit_ovf_new    equ $0D                 ; per-byte overflow accumulator (HAL internal)
blit_ovf_prev   equ $0E                 ; per-row overflow carry (HAL internal)
blit_tmp        equ $0F                 ; transparency scratch: source byte during mask sequence
blit_opaque     equ $13                 ; 0=transparent (index-0 keyed), nonzero=opaque (store all)
* ===============================================================
* POP DORMANCY GUARD (P2.1) — everything below is ADOPTED BUT NOT ASSEMBLED.
*
* POP does not use the runtime masked blit. PA.6 measured it at 5.4x the cost the
* design assumed and ruled it INFEASIBLE for POP's per-frame budget; PA.7/PA.9/P1.3
* replaced it with COMPILED SPRITES (harness/tools/sprite_compiler.py emits a
* straight-line draw routine per cel, JSR'd directly). So these six entry points
* have no POP caller.
*
* They are LEFT IN SOURCE, VERBATIM AND UNMODIFIED, per the P2.1 governing rule
* that the HAL stays the same recognizable artifact across Karateka and POP —
* dormant-but-present, not deleted, not rewritten. Re-enable with a single
* assembler flag, no source edit:
*     lwasm -DPOP_HAL_RUNTIME_BLIT ...
*
* Not free to leave assembling: measured at 1,231 of 1,609 bytes = 77% of the
* adopted HAL's code. That is the whole reason this guard exists rather than a
* comment in the audit table.
*
* Everything between `ifdef` and `endc` is byte-identical to karateka's gfx.s.
* ===============================================================
                ifdef   POP_HAL_RUNTIME_BLIT
                ifdef   OBJTARGET
                * PUBLIC only while the runtime blit is enabled. Dormant in POP, so
                * deliberately NOT exported there: a POP call to one of these becomes
                * a LINK ERROR rather than a jump into whatever occupies the address.
                export  HAL_gfx_blit_sprite_opaque
                export  HAL_gfx_blit_sprite
                export  HAL_gfx_blit_sprite_mixed
                export  HAL_gfx_blit_sprite_masked
                export  HAL_gfx_blit_stencil_punch
                export  HAL_gfx_blit_scroll
                endc


* HAL_gfx_blit_sprite_opaque — like HAL_gfx_blit_sprite but OPAQUE: every pixel
* (incl. index-0/black) is stored, overwriting the dest. Faithful to the oracle's
* $0F-selected store blend (video.s routine_1927). Use for black shadows / solid
* fills that must show against a (partially black) background. Same args as
* HAL_gfx_blit_sprite (X=sprite, A=col, B=row, blit_subbyte set).
HAL_gfx_blit_sprite_opaque:
        pshs    a
        lda     #$01
        sta     <blit_opaque
        puls    a
        bra     blit_have_mode

HAL_gfx_blit_sprite:
        clr     <blit_opaque            ; default transparent (existing callers unchanged)
blit_have_mode:
        pshs    u                       ; preserve U per contract

        sta     <blit_col               ; $0A = destination byte column
        stb     <blit_row               ; $0B = destination pixel row

        lda     ,x+                     ; A = height
        sta     <blit_height
        lda     ,x+                     ; A = width
        sta     <blit_width

        ; Bounds check: col + width > 80
        lda     <blit_col
        adda    <blit_width
        lbcs    blit_out_of_bounds
        cmpa    #81
        lbhs    blit_out_of_bounds

        ; Bounds check: row + height > 192
        lda     <blit_row
        adda    <blit_height
        lbcs    blit_out_of_bounds
        cmpa    #193
        lbhs    blit_out_of_bounds

        ; Compute buffer base → Y
        lda     <page_register
        cmpa    #PAGE_A_TOKEN
        beq     blit_base_a
        ldy     #GFX_FB_B_BASE
        bra     blit_got_base
blit_base_a:
        ldy     #GFX_FB_A_BASE
blit_got_base:
        lda     #80
        ldb     <blit_row
        mul
        leay    d,y                     ; Y = buffer_base + row*80
        ldb     <blit_col
        leay    b,y                     ; Y = buffer_base + row*80 + col
        ldu     #blit_trans_table_mid   ; U = transparency mask table midpoint
        tst     <blit_opaque            ; opaque mode? -> all-$FF table (store verbatim)
        beq     blit_dispatch
        ldu     #blit_opaque_table_mid

        ; Dispatch to sub-byte-specific row loop
blit_dispatch:                          ; shared entry (HAL_gfx_blit_scroll jumps here w/ Y,U set)
        lda     <blit_subbyte
        beq     blit_do_sb0
        cmpa    #1
        beq     blit_do_sb1
        cmpa    #2
        beq     blit_do_sb2
        lbra    blit_do_sb3             ; subbyte=3

* ---------------------------------------------------------------
* Transparency-aware blit sequence (all subbyte cases):
*   U = blit_trans_table_mid (set before dispatch; table[$80-$FF] below, [$00-$7F] at U)
*   lda b,u: B = source byte → signed offset → correct mask for all 256 values
*   For each output byte A:
*     pshs b              ; save loop counter
*     tfr  a,b            ; B = output (A unchanged; TFR non-destructive)
*     lda  b,u            ; A = mask(output): 11 per non-black pixel pair, 00 per black
*     coma                ; A = ~mask
*     anda ,y             ; A = dest & ~mask (preserve black-keyed positions)
*     stb  <blit_tmp      ; output to DP scratch
*     ora  <blit_tmp      ; A = (dest & ~mask) | output
*     sta  ,y+            ; write result; advance Y (or sta ,y for overflow byte)
*     puls b              ; restore loop counter
* ---------------------------------------------------------------

* ---------------------------------------------------------------
* subbyte=0: byte-aligned (no shift); transparency-aware
* ---------------------------------------------------------------
blit_do_sb0:
        lda     <blit_height
blit_row_sb0:
        ldb     <blit_width
blit_byte_sb0:
        lda     ,x+                     ; source byte
        pshs    b                        ; save loop counter
        tfr     a,b                      ; B = source (TFR: A unchanged)
        lda     b,u                      ; A = mask(source)
        coma                             ; A = ~mask
        anda    ,y                       ; A = dest & ~mask
        stb     <blit_tmp                ; source to DP scratch
        ora     <blit_tmp                ; A = (dest & ~mask) | source
        sta     ,y+                      ; write, advance Y
        puls    b                        ; restore loop counter
        decb
        bne     blit_byte_sb0
        ldb     #80
        subb    <blit_width
        leay    b,y
        dec     <blit_height
        bne     blit_row_sb0
        lbra    blit_done

* ---------------------------------------------------------------
* subbyte=1: 2-bit right shift; transparency-aware
* ---------------------------------------------------------------
blit_do_sb1:
        lda     <blit_height
blit_row_sb1:
        clr     <blit_ovf_prev
        ldb     <blit_width
blit_byte_sb1:
        clr     <blit_ovf_new
        lda     ,x+
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        ora     <blit_ovf_prev          ; A = shifted output byte
        pshs    b
        tfr     a,b
        lda     b,u
        coma
        anda    ,y
        stb     <blit_tmp
        ora     <blit_tmp
        sta     ,y+
        puls    b
        lda     <blit_ovf_new
        sta     <blit_ovf_prev
        decb
        bne     blit_byte_sb1
        lda     <blit_ovf_prev          ; overflow byte
        tfr     a,b
        lda     b,u
        coma
        anda    ,y
        stb     <blit_tmp
        ora     <blit_tmp
        sta     ,y                       ; write overflow (no Y advance)
        ldb     #80
        subb    <blit_width
        leay    b,y
        dec     <blit_height
        bne     blit_row_sb1
        lbra    blit_done

* ---------------------------------------------------------------
* subbyte=2: 4-bit right shift; transparency-aware
* ---------------------------------------------------------------
blit_do_sb2:
        lda     <blit_height
blit_row_sb2:
        clr     <blit_ovf_prev
        ldb     <blit_width
blit_byte_sb2:
        clr     <blit_ovf_new
        lda     ,x+
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        ora     <blit_ovf_prev
        pshs    b
        tfr     a,b
        lda     b,u
        coma
        anda    ,y
        stb     <blit_tmp
        ora     <blit_tmp
        sta     ,y+
        puls    b
        lda     <blit_ovf_new
        sta     <blit_ovf_prev
        decb
        bne     blit_byte_sb2
        lda     <blit_ovf_prev          ; overflow byte
        tfr     a,b
        lda     b,u
        coma
        anda    ,y
        stb     <blit_tmp
        ora     <blit_tmp
        sta     ,y
        ldb     #80
        subb    <blit_width
        leay    b,y
        dec     <blit_height
        bne     blit_row_sb2
        lbra    blit_done

* ---------------------------------------------------------------
* subbyte=3: 6-bit right shift; transparency-aware
* ---------------------------------------------------------------
blit_do_sb3:
        lda     <blit_height
blit_row_sb3:
        clr     <blit_ovf_prev
        ldb     <blit_width
blit_byte_sb3:
        clr     <blit_ovf_new
        lda     ,x+
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        lsra
        ror     <blit_ovf_new
        ora     <blit_ovf_prev
        pshs    b
        tfr     a,b
        lda     b,u
        coma
        anda    ,y
        stb     <blit_tmp
        ora     <blit_tmp
        sta     ,y+
        puls    b
        lda     <blit_ovf_new
        sta     <blit_ovf_prev
        decb
        bne     blit_byte_sb3
        lda     <blit_ovf_prev          ; overflow byte
        tfr     a,b
        lda     b,u
        coma
        anda    ,y
        stb     <blit_tmp
        ora     <blit_tmp
        sta     ,y
        ldb     #80
        subb    <blit_width
        leay    b,y
        dec     <blit_height
        bne     blit_row_sb3

blit_done:
        andcc   #$FE                    ; CC.C clear = success
        puls    u
        rts

blit_out_of_bounds:
        lda     #$02                    ; A = ERR_INVALID (2) per hal.inc
        orcc    #$01                    ; CC.C set = error
        puls    u
        rts

* ---------------------------------------------------------------
* HAL_gfx_blit_sprite_mixed — per-REGION mixed-opacity blit (ADDITIVE).
*   Splits a sprite into byte-COLUMN runs; each run is blitted OPAQUE (index-0
*   stored solid) or TRANSPARENT (index-0 keyed) per a descriptor. It WRAPS the
*   existing transparent + opaque blits — their optimized loops are UNCHANGED,
*   so every existing caller stays byte-identical. Reusable: any sprite with
*   region-separable opacity supplies its own run descriptor. NO pixel-format
*   change (2bpp preserved) — the opacity lives in the descriptor, not the data.
*
* Args: X = sprite (height,width,bitmap); A = dest byte col; B = dest row;
*       blit_subbyte ($0C) set; U = descriptor ptr.
* Descriptor: repeating RECTANGLE entries
*       fcb start_col, width, start_row, num_rows, opaque(0=transp,1=opaque)
*       terminated by a width byte of 0. (Row-bands, column-runs, or cells.)
* Per region: extract the rectangle [start_col..+width) x [start_row..+num_rows)
*       to MIX_SCRATCH, then blit via the existing leaf at dest
*       (A+start_col, B+start_row), same sub-byte.
* Uses mix_* ZP ($14-$20) which the inner blits do not touch; blit_subbyte
*       persists across regions (the blits read it, never write it).
* ---------------------------------------------------------------
mix_col         equ $14
mix_row         equ $15
mix_desc        equ $16                 ; 16-bit descriptor ptr
mix_data        equ $18                 ; 16-bit source bitmap ptr
mix_w           equ $1A                 ; source row stride (sprite width)
mix_sc          equ $1B                 ; region start_col
mix_rw          equ $1C                 ; region width
mix_sr          equ $1D                 ; region start_row
mix_nr          equ $1E                 ; region num_rows
mix_op          equ $1F                 ; region opacity
        ifndef  MIX_SCRATCH             ; caller may override BEFORE including gfx.s (large programs
MIX_SCRATCH     equ $3E00               ; whose load reaches $3E00 must relocate it to free RAM).
        endc                            ; default: extracted sub-sprite scratch below FLIP_BUF

HAL_gfx_blit_sprite_mixed:
        sta     <mix_col
        stb     <mix_row
        stu     <mix_desc
        leax    1,x                     ; skip height byte
        lda     ,x+                     ; width
        sta     <mix_w
        stx     <mix_data               ; X -> source bitmap
mix_run:
        ldu     <mix_desc
        lda     ,u                      ; start_col
        sta     <mix_sc
        ldb     1,u                     ; width
        bne     mix_have
        rts                             ; width 0 -> done
mix_have:
        stb     <mix_rw
        lda     2,u                     ; start_row
        sta     <mix_sr
        lda     3,u                     ; num_rows
        sta     <mix_nr
        lda     4,u                     ; opacity
        sta     <mix_op
        leau    5,u
        stu     <mix_desc
        ; build sub-sprite header (num_rows, width) at MIX_SCRATCH
        ldx     #MIX_SCRATCH
        lda     <mix_nr
        sta     ,x+
        lda     <mix_rw
        sta     ,x+                     ; X -> scratch data
        ; Y = mix_data + start_row*width + start_col
        lda     <mix_sr
        ldb     <mix_w
        mul                             ; D = start_row * width
        addd    <mix_data
        addb    <mix_sc
        adca    #0
        tfr     d,y                     ; Y = rectangle top-left source byte
        lda     <mix_nr                 ; row counter
mix_erow:
        pshs    a
        ldb     <mix_rw
mix_ebyte:
        lda     ,y+
        sta     ,x+
        decb
        bne     mix_ebyte
        ldb     <mix_w                  ; skip to next row's region start: Y += (w - rw)
        subb    <mix_rw
        leay    b,y
        puls    a
        deca
        bne     mix_erow
        ; blit the extracted rectangle via the existing leaf at (col+sc, row+sr)
        ldx     #MIX_SCRATCH
        lda     <mix_row
        adda    <mix_sr
        pshs    a                       ; dest row
        lda     <mix_col
        adda    <mix_sc                 ; A = dest col
        ldb     ,s+                     ; B = dest row
        tst     <mix_op
        bne     mix_blit_op
        jsr     HAL_gfx_blit_sprite     ; transparent region
        bra     mix_run
mix_blit_op:
        jsr     HAL_gfx_blit_sprite_opaque  ; opaque region
        bra     mix_run

* ---------------------------------------------------------------
* HAL_gfx_blit_sprite_masked — opaque blit with a per-COLUMN POSITIONAL mask
*   (ADDITIVE, sub-byte precision, NO format change). Where the existing mixed
*   blit splits opacity at BYTE boundaries, this splits it at the PIXEL within a
*   byte: each source byte is merged with the caller's mask byte for that column
*   via the SAME engine the transparent/opaque blits use — result =
*   (dest AND ~mask) OR source. mask bit-pair = 11 -> take source (opaque),
*   00 -> keep dest (transparent). So a column can be opaque on some pixels and
*   transparent on others (e.g. trim a 1px edge off an otherwise-solid byte).
*
*   Like the transparent blit, kept-dest (mask=00) pixels rely on source being
*   index-0 there (the OR contributes 0) — true for black edges/keying.
*
* Args: X = sprite (height,width,bitmap); A = dest byte col; B = dest row;
*       U = mask array ptr (one mask byte per source column, width bytes).
* BYTE-ALIGNED ONLY (no sub-byte shift) — the feet use blit_subbyte=0.
* Reuses blit_height/width/col/row/tmp + mix_data ($18) for the mask base.
* Preserves nothing extra; clobbers A,B,X,Y,U,CC. Bounds-checked like the others.
* ---------------------------------------------------------------
emask_ptr       equ mix_data            ; reuse $18 (16-bit) — disjoint from a mixed-blit call
HAL_gfx_blit_sprite_masked:
        stu     <emask_ptr              ; mask array base (reloaded per row)
        sta     <blit_col
        stb     <blit_row
        lda     ,x+                     ; height
        sta     <blit_height
        lda     ,x+                     ; width
        sta     <blit_width
        lda     <blit_col               ; bounds: col+width <= 80
        adda    <blit_width
        bcs     emask_oob
        cmpa    #81
        bhs     emask_oob
        lda     <blit_row               ; bounds: row+height <= 192
        adda    <blit_height
        bcs     emask_oob
        cmpa    #193
        bhs     emask_oob
        lda     <page_register
        cmpa    #PAGE_A_TOKEN
        beq     emask_base_a
        ldy     #GFX_FB_B_BASE
        bra     emask_got_base
emask_base_a:
        ldy     #GFX_FB_A_BASE
emask_got_base:
        lda     #80
        ldb     <blit_row
        mul
        leay    d,y                     ; Y = base + row*80
        ldb     <blit_col
        leay    b,y                     ; Y = dest top-left
emask_row:
        ldu     <emask_ptr              ; U = mask array (reset each row)
        ldb     <blit_width
emask_byte:
        lda     ,x+                     ; source byte
        sta     <blit_tmp               ; stash source
        lda     ,u+                     ; positional mask for this column
        coma                            ; ~mask
        anda    ,y                      ; dest AND ~mask  (keep dest where mask=00)
        ora     <blit_tmp               ; OR source       (take source where mask=11)
        sta     ,y+                     ; write, advance
        decb
        bne     emask_byte
        ldb     #80
        subb    <blit_width
        leay    b,y                     ; next row
        dec     <blit_height
        bne     emask_row
emask_oob:
        rts

* ---------------------------------------------------------------
* HAL_gfx_blit_stencil_punch — punch a per-PIXEL 2D silhouette to black.
*   (ADDITIVE.) Unlike HAL_gfx_blit_sprite_masked (per-COLUMN mask, reset each
*   row), this walks a FULL 2D mask (width*height bytes, advancing continuously)
*   and writes: dest = dest AND ~mask. Mask bit-pair 11 -> force pixel black
*   (occlude), 00 -> keep dest. Used to occlude a moving actor behind Akuma's
*   exact figure silhouette (mask from fig_974B: 11=figure, 00=surround+gaps),
*   trimmed to his shape (not a rectangle) incl. the interior armpit gaps.
* Args: X = stencil (height,width,maskbytes); A = dest byte col; B = dest row.
* BYTE-ALIGNED. Bounds-checked like the others. Clobbers A,B,X,Y,CC.
* ---------------------------------------------------------------
HAL_gfx_blit_stencil_punch:
        sta     <blit_col
        stb     <blit_row
        lda     ,x+                     ; height
        sta     <blit_height
        lda     ,x+                     ; width
        sta     <blit_width
        lda     <blit_col               ; bounds: col+width <= 80
        adda    <blit_width
        bcs     epun_oob
        cmpa    #81
        bhs     epun_oob
        lda     <blit_row               ; bounds: row+height <= 192
        adda    <blit_height
        bcs     epun_oob
        cmpa    #193
        bhs     epun_oob
        lda     <page_register
        cmpa    #PAGE_A_TOKEN
        beq     epun_base_a
        ldy     #GFX_FB_B_BASE
        bra     epun_got_base
epun_base_a:
        ldy     #GFX_FB_A_BASE
epun_got_base:
        lda     #80
        ldb     <blit_row
        mul
        leay    d,y                     ; Y = base + row*80
        ldb     <blit_col
        leay    b,y                     ; Y = dest top-left
epun_row:
        ldb     <blit_width
epun_byte:
        lda     ,x+                     ; 2D mask byte (advances continuously)
        coma                            ; ~mask
        anda    ,y                      ; dest AND ~mask  (11 -> black, 00 -> keep)
        sta     ,y+
        decb
        bne     epun_byte
        ldb     #80
        subb    <blit_width
        leay    b,y                     ; next row
        dec     <blit_height
        bne     epun_row
epun_oob:
        rts

* ---------------------------------------------------------------
* HAL_gfx_blit_scroll  [R-p26 — full-region scroll blit]
*
* Like HAL_gfx_blit_sprite, but targets a 16-bit physical row (0-391)
* in the COMBINED display region ($8000-$FBFF = physical $78000-$7FBFF,
* CPU- and physically-contiguous), with NO 192-row bounds check. Used by
* the scene-4 VOFFSET sliding-window scroll, which renders lines into a
* ~392-row ring buffer spanning both frame buffers (legal: the display is
* single-buffered per R-p25, so both buffers form one scroll region).
*
* Args:    X = sprite ptr (height,width,bitmap)
*          A = destination byte column (0-79; 4px/byte)
*          s4_dest_row ($66, 16-bit) = destination physical row (0-391)
*          blit_subbyte ($0C) = sub-byte offset 0-3 (CALLER sets)
* Returns: CC.C clear. Preserves U. Clobbers A,B,X,Y,CC,$0D/$0E.
*
* dest = $8000 + row*80 + col. row*80 with row<=391 ($187): row_lo*80
* (<=20400) + (row_hi ? 80<<8 : 0). Shares the sub-byte dispatch/row-loops
* with HAL_gfx_blit_sprite (blit_do_sb0..3 above; row stride is #80).
* Caller guarantees row+height <= 392 and col+width(+1) <= 80.
* ---------------------------------------------------------------
HAL_gfx_blit_scroll:
        pshs    u                       ; preserve U per contract
        sta     <blit_col               ; $0A = destination byte column
        lda     ,x+                     ; A = height
        sta     <blit_height
        lda     ,x+                     ; A = width
        sta     <blit_width
        ; Y = $8000 + s4_dest_row*80 + blit_col
        lda     #80
        ldb     <s4_dest_row+1          ; row low byte
        mul                             ; D = row_lo * 80
        ldu     <s4_dest_row            ; U = full 16-bit row (hi:lo)
        cmpu    #256                    ; row >= 256? (hi byte set)
        blo     blit_scroll_base
        addd    #$5000                  ; + (1 * 80) << 8
blit_scroll_base:
        addd    #GFX_FB_A_BASE          ; + $8000 region base
        tfr     d,y
        ldb     <blit_col
        leay    b,y                     ; Y = $8000 + row*80 + col
        ldu     #blit_trans_table_mid   ; U = transparency table midpoint
        lbra    blit_dispatch           ; shared sub-byte dispatch (Y,U set)

* ---------------------------------------------------------------
* blit_trans_table — 256-byte transparency mask lookup table
*
* Maps each possible source byte to its transparency mask:
*   2bpp pixel pair (2 bits) non-zero → mask bits = 11 (replace dest)
*   2bpp pixel pair zero              → mask bits = 00 (preserve dest)
*
* Table layout uses signed-B indexed addressing trick:
*   U = blit_trans_table_mid (= table_base + 128)
*   lda b,u: B $00-$7F (positive) → accesses [mid+0..mid+127] = masks $00-$7F
*            B $80-$FF (negative) → accesses [mid-128..mid-1]  = masks $80-$FF
*
* Physical memory order:
*   Offset 0-127   (blit_trans_table_base): masks for source bytes $80-$FF
*   Offset 128-255 (blit_trans_table_mid):  masks for source bytes $00-$7F
* ---------------------------------------------------------------
blit_trans_table_base:
* Sources $80-$FF (accessed via negative B offset from mid)
        fcb     $C0,$C3,$C3,$C3,$CC,$CF,$CF,$CF,$CC,$CF,$CF,$CF,$CC,$CF,$CF,$CF  ; src $80-$8F
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $90-$9F
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $A0-$AF
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $B0-$BF
        fcb     $C0,$C3,$C3,$C3,$CC,$CF,$CF,$CF,$CC,$CF,$CF,$CF,$CC,$CF,$CF,$CF  ; src $C0-$CF
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $D0-$DF
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $E0-$EF
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $F0-$FF
blit_trans_table_mid:
* Sources $00-$7F (accessed via positive B offset from mid = U base)
        fcb     $00,$03,$03,$03,$0C,$0F,$0F,$0F,$0C,$0F,$0F,$0F,$0C,$0F,$0F,$0F  ; src $00-$0F
        fcb     $30,$33,$33,$33,$3C,$3F,$3F,$3F,$3C,$3F,$3F,$3F,$3C,$3F,$3F,$3F  ; src $10-$1F
        fcb     $30,$33,$33,$33,$3C,$3F,$3F,$3F,$3C,$3F,$3F,$3F,$3C,$3F,$3F,$3F  ; src $20-$2F
        fcb     $30,$33,$33,$33,$3C,$3F,$3F,$3F,$3C,$3F,$3F,$3F,$3C,$3F,$3F,$3F  ; src $30-$3F
        fcb     $C0,$C3,$C3,$C3,$CC,$CF,$CF,$CF,$CC,$CF,$CF,$CF,$CC,$CF,$CF,$CF  ; src $40-$4F
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $50-$5F
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $60-$6F
        fcb     $F0,$F3,$F3,$F3,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$FF,$FF,$FF  ; src $70-$7F

* ---------------------------------------------------------------
* blit_opaque_table — 256-byte all-$FF mask. Selected (instead of the
* transparency table) by HAL_gfx_blit_sprite_opaque. mask=$FF -> coma=$00 ->
* anda dest = 0 -> ora output = output, i.e. a plain STORE: every pixel incl.
* index-0/black overwrites the dest. Mid at +128 (same signed-offset indexing).
* ---------------------------------------------------------------
blit_opaque_table_base:
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
blit_opaque_table_mid:
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF


                endc                    ; POP_HAL_RUNTIME_BLIT — end dormancy guard
                
                ifdef   OBJTARGET
                endsection
                endc
