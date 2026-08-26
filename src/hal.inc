;==============================================================
; karateka-coco3 HAL contract
; hal.inc — assembly-syntactic interface definition
; Version: 0.1 (P1.3 deliverable)
;
; Defines the contract between platform-neutral engine code
; and platform-specific HAL implementations.
;
; Shape inherited from pop-coco3-design v0.7 Section 6.11.
; Karateka-specific divergences documented in docs/hal.md.
;
; See docs/hal.md for the human-readable companion.
; Reference discipline per docs/karateka-coco3-design-v0.1.md
; Section 6.6 and 6502-6809-conversion-patterns/shared/
; G-methodology/G.1-reference-discipline.md.
;==============================================================

;--------------------------------------------------------------
; CALLING CONVENTION (applies to all HAL functions)
;
; Arguments:  A, B, D (scalar), X (pointer in), Y (secondary)
; Returns:    D (scalar), X (pointer out), CC.C (error flag)
; On error:   CC.C set, A = error code
; On success: CC.C clear
; Preserved:  U (engine frame pointer), DP (direct page)
; Scratch:    A, B, X, Y, CC bits except .C
;
; HAL functions are main-context only. Not safe from interrupt
; handlers.
;--------------------------------------------------------------

;--------------------------------------------------------------
; DIRECT PAGE (DP) USAGE POLICY
;
; HAL owns:    $00-$1F  (32 bytes — scratch, temp params)
; Engine owns: $20-$7F  (96 bytes — engine ZP variables)
; Reserved:    $80-$FF  (CoCo3 system use — do not touch)
;
; [no-ref: CoCo3 system DP usage at $80-$FF — resolve during
;   P2 by checking CC3-TR for system ZP conventions]
;
; The HAL/engine split within $00-$7F is a design choice, not
; a hardware constraint. Subject to revision if pressure
; surfaces during P2 engine porting.
;--------------------------------------------------------------

HAL_ZP_BASE     equ $00         ; HAL scratch region base
HAL_ZP_PARAM0   equ $00         ; Byte parameter 0
HAL_ZP_PARAM1   equ $01         ; Byte parameter 1
HAL_ZP_PARAM2   equ $02         ; Byte parameter 2
HAL_ZP_PARAM3   equ $03         ; Byte parameter 3
HAL_ZP_PTR0     equ $04         ; Pointer scratch 0 (2 bytes)
HAL_ZP_PTR1     equ $06         ; Pointer scratch 1 (2 bytes)
; $08-$1F: HAL internal use (subsystem-specific, defined in
;          each HAL implementation file)

ENGINE_ZP_BASE  equ $20         ; Engine ZP region base

;--------------------------------------------------------------
; MEMORY MAP CONSTANTS
; Per docs/memory-map.md §6.
; Physical address derivation per [ref: GIME-RM §13].
; All values subject to revision if P2/P3 implementation
; surfaces pressure (single comment update + rebuild).
;--------------------------------------------------------------

; Frame buffers (320x192x4, $3C00 bytes each)
; [ref: GIME-RM §10] buffer size derivation
KCOCO3_FB_A_BASE    equ $8000   ; Frame A CPU base (back buffer)
KCOCO3_FB_B_BASE    equ $C000   ; Frame B CPU base (front buffer)
KCOCO3_FB_SIZE      equ $3C00   ; Frame buffer byte count (80 B/row × 192 rows)

; GIME VOFFSET values for frame buffer swap
; [ref: GIME-RM §13] physical $78000: $FF9D=$F0, $FF9E=$00
;                    physical $7C000: $FF9D=$F8, $FF9E=$00
KCOCO3_FB_A_VOFF_HI equ $F0    ; $FF9D value → Frame A visible
KCOCO3_FB_A_VOFF_LO equ $00    ; $FF9E value
KCOCO3_FB_B_VOFF_HI equ $F8    ; $FF9D value → Frame B visible
KCOCO3_FB_B_VOFF_LO equ $00    ; $FF9E value

; Trace ring buffer
; [ref: memory-map §4.7]
KCOCO3_TRACE_BUFFER     equ $7800   ; trace ring buffer CPU base
KCOCO3_TRACE_BUF_SIZE   equ $0100   ; 256 bytes

; GIME hardware registers
; [ref: GIME-RM §3] register map summary
KCOCO3_GIME_INIT0       equ $FF90   ; initialization reg 0 (COCO3 mode)
KCOCO3_GIME_INIT1       equ $FF91   ; initialization reg 1 (TR, TINS)
KCOCO3_GIME_IRQENR      equ $FF92   ; IRQ enable (bit 3 = VBORD/VBL)
KCOCO3_GIME_FIRQENR     equ $FF93   ; FIRQ enable
KCOCO3_GIME_VMODE       equ $FF98   ; video mode (graphics: $80)
KCOCO3_GIME_VRES        equ $FF99   ; video resolution (320×192×4: $15)
KCOCO3_GIME_VSCROL      equ $FF9C   ; vertical scroll (init $00 required)
KCOCO3_GIME_VOFFSET_HI  equ $FF9D   ; screen start phys addr high
KCOCO3_GIME_VOFFSET_LO  equ $FF9E   ; screen start phys addr low
KCOCO3_GIME_HOFFSET     equ $FF9F   ; horizontal offset (init $00 required)
KCOCO3_MMU_TASK0        equ $FFA0   ; MMU task set 0 base (FFA0-FFA7)
KCOCO3_GIME_PALETTE_BASE equ $FFB0  ; palette register 0 (4 used in 4-color mode)
KCOCO3_SAM_CLK_HI       equ $FFD9   ; SAM: set 1.78 MHz CPU clock
KCOCO3_SAM_RAM_C000     equ $FFDF   ; SAM: RAM at $C000 (task 0)

; GIME mode values
; [ref: GIME-RM §10] verified working reference mode
KCOCO3_VMODE_GRAPHICS   equ $80     ; $FF98 = graphics (BP=1)
KCOCO3_VRES_320x192x4   equ $15     ; $FF99 = LPF=00, HRES=101, CRES=01
; $FF90 INIT0 has TWO correct values at TWO points in the boot sequence. A single
; constant cannot serve both, and the one that existed was correct only for the
; early write — so gfx.s bypassed it with a literal. Split, so each site can name
; what it means and neither has to hard-code a magic number.
;
;   bit 5 = IEN (GIME master interrupt enable).
;   ACTIVATE ($4C, IEN=0) — HAL_sys_init step 3. Switches to CoCo3-mode address
;     translation before interrupts are wanted. IEN=0 is CORRECT here.
;   RUN      ($6C, IEN=1) — every write AFTER HAL_time_init has enabled the GIME
;     VBL interrupt. $FF90 is write-only, so a read-modify-write is impossible and
;     any later writer must re-assert IEN or the VBL interrupt dies silently.
;
; Using ACTIVATE at a late site clears IEN and stops the frame counter with no
; error — the failure mode this split exists to prevent.
KCOCO3_INIT0_ACTIVATE   equ $4C     ; $FF90 = COCO=0, MMUEN=1, IEN=0, MC3=1, MC2=1
KCOCO3_INIT0_RUN        equ $6C     ; $FF90 = COCO=0, MMUEN=1, IEN=1, MC3=1, MC2=1

;--------------------------------------------------------------
; ERROR CODES
; Inherited from pop-coco3 Section 6.11.4.2.
; Codes are stable; new codes appended; existing not renumbered.
;--------------------------------------------------------------

ERR_OK          equ 0           ; success (CC.C always clear)
ERR_NOT_FOUND   equ 1           ; resource not found
ERR_INVALID     equ 2           ; invalid argument
ERR_NOMEM       equ 3           ; insufficient memory
ERR_IO          equ 4           ; I/O failure
ERR_DEVICE      equ 5           ; hardware not present/responding
ERR_TIMEOUT     equ 6           ; operation timed out
ERR_BUSY        equ 7           ; resource busy
ERR_INTERNAL    equ 8           ; internal HAL error

;--------------------------------------------------------------
; INIT ORDER (call in this sequence at boot)
;
; 0. HAL_sys_init         (bare-metal transition: mask + $FF90 + MMU)
; 1. HAL_mem_size_detect  (memory probe)
; 2. HAL_time_init        (timing before other init)
; 3. HAL_gfx_init         (screen up early for error display)
; 4. HAL_input_init
; 5. HAL_sound_init
; 6. HAL_file_init
; -  Debug/Trace: no init function; HAL_debug_trace_event is
;    available immediately at boot (ring buffer in static memory)
;--------------------------------------------------------------

;==============================================================
; GRAPHICS SUBSYSTEM — DETAILED
; Target: GIME 320×192×4 color mode, double-buffered.
; P2.3a: HAL_gfx_init and HAL_gfx_clear implemented in
;   src/hal/coco3-dsk/gfx.s. HAL_gfx_present remains a stub.
;
; Symbol resolution note (P2.3a, D2):
;   The prior `equ *` pattern for HAL_gfx_init/HAL_gfx_clear was
;   broken: including hal.inc at any point resolved all gfx symbols
;   to the same PC value. Replaced with `import` declarations for
;   lwasm multi-file builds. When building single-file test drivers
;   (lwasm --decb), hal.inc is NOT included — drivers inline the HAL
;   functions directly (existing pattern per timer_framesync_driver.s
;   and kernel_dispatch_driver.s). The `import` declarations are
;   effective only in multi-object production builds.
;   Precedent: no prior lwasm import/export usage in this project.
;   Pattern introduced here; document in build system when production
;   build is wired (post-P2).
;==============================================================

; HAL_gfx_init
;   Initialize GIME for 320×192×4 mode with double buffering.
;   P2.3a: real implementation in src/hal/coco3-dsk/gfx.s.
;   Args:  A = palette descriptor index (0 = Brøderbund default)
;          A != 0 falls through to descriptor 0 (only descriptor
;          implemented in P2.3a).
;   Returns: CC.C clear on success (always; ERR_NOMEM never raised,
;            frame buffers statically allocated per P1.6)
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Init order: 3
;   [ref: src/hal/coco3-dsk/gfx.s — implementation]
        ifdef   OBJTARGET
        import  HAL_gfx_init            ; defined in src/hal/coco3-dsk/gfx.s
        endc

; HAL_gfx_shutdown
;   Restore screen mode (e.g. return to text for error display).
;   Args:  none
;   Returns: nothing
;   Errors:  none
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
HAL_gfx_shutdown    equ *       ; STUB-P3 — not yet implemented

; HAL_gfx_clear
;   Fill active back buffer with palette index 0 (background).
;   P2.3a: real implementation in src/hal/coco3-dsk/gfx.s.
;   Requires page_register (DP $50) initialized before call.
;   Args:  none
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U
;   Clobbers: A, B, X, Y, CC
;   Note: per D.3 back-buffer discipline; never writes to front
;   [ref: src/hal/coco3-dsk/gfx.s — implementation]
        ifdef   OBJTARGET
        import  HAL_gfx_clear           ; defined in src/hal/coco3-dsk/gfx.s
        endc

; HAL_gfx_blit_sprite
;   Render CoCo3 packed sprite at sub-byte-precise (col, row) in back buffer.
;   Runtime pixel-shift port of Apple II Karateka L1A84 mechanism
;   (karateka_dissasembly_claude/src/video.s lines 391-492, P2.4.1).
;   Args:  X = pointer to sprite binary (height + coco3_width +
;               packed bitmap per P1.2 format)
;          A = destination byte column (0-79; 4px per byte)
;          B = destination pixel row (0-191)
;          ZP $0C (blit_subbyte) = sub-byte pixel offset 0-3; CALLER MUST SET
;            0 = byte-aligned (same as prior P2.3a.6 behavior)
;            1 = shift right 1 pixel (2 bits)
;            2 = shift right 2 pixels (4 bits)
;            3 = shift right 3 pixels (6 bits)
;   Returns: CC.C clear on success
;   Errors:  ERR_INVALID if sprite extends beyond frame buffer
;   Preserves: U
;   Clobbers: A, B, X, Y, CC, ZP $0D/$0E (blit_ovf_new/prev)
;   Note: when blit_subbyte>0, effective output width = sprite_width+1 bytes;
;         caller must ensure col+width <= 78 to avoid out-of-bounds overflow write.
;   [ref: src/hal/coco3-dsk/gfx.s — implementation]
        ifdef   OBJTARGET
        import  HAL_gfx_blit_sprite     ; defined in src/hal/coco3-dsk/gfx.s (P2.4.1)
        endc

; HAL_gfx_blit_sprite_opaque
;   As HAL_gfx_blit_sprite, but OPAQUE: every pixel incl. index-0 (black) is
;   stored, overwriting the dest (no index-0 transparency keying). For black
;   shadows / solid fills that must render against a (partially black) floor.
;   Faithful to the oracle's $0F-selected store blend (video.s routine_1927).
;   Same args/returns as HAL_gfx_blit_sprite. [ref: src/hal/coco3-dsk/gfx.s]
        ifdef   OBJTARGET
        import  HAL_gfx_blit_sprite_opaque
        endc

; ---------------------------------------------------------------
; The four blit entry points below were IMPLEMENTED and LIVE but never declared
; here. P2.2 (POP) found them undeclared; P2.2-verify established they are called
; from engine code -- blit_scroll from scene4_scroll.s, and the other three from
; climb_controller.s, plus test drivers (25 call sites total), with
; docs/project/memory-window-audit.md independently marking two of them LIVE and
; dozens of authored content/*/opacity.s files naming them as their descriptor
; format contract. Jay ruled: DECLARE. They are public contract, not internals.
; Declaring an already-defined, already-used symbol is inert to codegen -- the
; production binary is byte-identical before and after this block.
; ---------------------------------------------------------------

; HAL_gfx_blit_sprite_mixed
;   Blit with a MIXED opacity descriptor: repeating rectangle entries select
;   opaque vs keyed regions at byte-column x row-band granularity, composited to
;   MIX_SCRATCH then blitted by the shared leaf.
;   Args:  X = sprite (height,width,bitmap); A = dest byte col; B = dest row;
;          U = descriptor ptr; blit_subbyte ($0C) set by caller.
;   Uses mix_* ZP ($14-$20); blit_subbyte persists across regions.
;   [ref: src/hal/coco3-dsk/gfx.s]
        ifdef   OBJTARGET
        import  HAL_gfx_blit_sprite_mixed
        endc

; HAL_gfx_blit_sprite_masked
;   Opaque blit with a per-COLUMN positional mask -- splits opacity at the PIXEL
;   within a byte (the plain blit splits at byte boundaries). Result is
;   (dest AND ~mask) OR source; mask bit-pair 11 = take source (opaque),
;   00 = keep dest. Kept-dest pixels rely on source being index-0 there.
;   Args:  X = sprite (height,width,bitmap); A = dest byte col; B = dest row;
;          U = mask array ptr (one mask byte per source column, width bytes).
;   BYTE-ALIGNED ONLY (no sub-byte shift).
;   [ref: src/hal/coco3-dsk/gfx.s]
        ifdef   OBJTARGET
        import  HAL_gfx_blit_sprite_masked
        endc

; HAL_gfx_blit_stencil_punch
;   Punch a per-PIXEL 2D silhouette to black: dest = dest AND ~mask, walking a
;   FULL 2D mask (width*height bytes, advancing continuously) rather than a
;   per-column mask reset each row. Mask bit-pair 11 = force pixel black.
;   Args:  X = stencil (height,width,maskbytes); A = dest byte col; B = dest row.
;   BYTE-ALIGNED. Bounds-checked. Clobbers A,B,X,Y,CC.
;   [ref: src/hal/coco3-dsk/gfx.s]
        ifdef   OBJTARGET
        import  HAL_gfx_blit_stencil_punch
        endc

; HAL_gfx_blit_scroll
;   As HAL_gfx_blit_sprite, but targets a 16-bit PHYSICAL row (0-391) rather than
;   a 0-191 screen row -- for the scene-4 VOFFSET sliding-window scroll, where
;   both buffers form one continuous scroll region. Row stride #80.
;   Args:  X = sprite ptr (height,width,bitmap); dest row via s4_dest_row;
;          blit_subbyte ($0C) = sub-byte offset 0-3 (caller sets).
;   Returns: CC.C clear. Preserves U. Clobbers A,B,X,Y,CC,$0D/$0E.
;   [ref: src/hal/coco3-dsk/gfx.s]
        ifdef   OBJTARGET
        import  HAL_gfx_blit_scroll
        endc


; HAL_gfx_set_palette
;   Write 4-entry palette to GIME palette registers.
;   Args:  X = pointer to 4-byte palette array (one byte per
;               entry, each a 6-bit GIME color code 0-63)
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: X, U, Y
;   Clobbers: A, B, CC
;   Timing: call during VBL to avoid mid-scanline artifact
;   [no-ref: GIME palette register addresses — verify in
;     GIME-RM §3.x during P2; Sockmaster-GIME empirical note:
;     writes during active scanline cause visible artifact]
HAL_gfx_set_palette equ *       ; STUB-P3 — not yet implemented

; Mode ids for HAL_gfx_set_mode. These are CONTRACT, so they live here rather
; than in the implementation: a caller that includes only hal.inc must be able
; to name the mode it wants. gfx.s does not define them — its descriptor table
; is positional — so there is exactly one home for the value.
GFX_MODE_320x192x4  equ 0        ; $FF99=$15,  80 B/row, 15,360 B,  4 palette regs
GFX_MODE_320x192x16 equ 1        ; $FF99=$1E, 160 B/row, 30,720 B, 16 palette regs
GFX_MODE_320x200x16 equ 2        ; $FF99=$3E, 160 B/row, 32,000 B, 16 palette regs

; HAL_gfx_set_mode                                    [P2.5 — kernel service]
;   Switch the display to a graphics mode. Generalizes the register
;   programming HAL_gfx_init hardcodes for 320x192x4.
;
;   Args:  A = mode id
;            0 = GFX_MODE_320x192x4   ($FF99=$15,  80 B/row, 15,360 B, 4 pal)
;            1 = GFX_MODE_320x192x16  ($FF99=$1E, 160 B/row, 30,720 B, 16 pal)
;            2 = GFX_MODE_320x200x16  ($FF99=$3E, 160 B/row, 32,000 B, 16 pal)
;              ADDED P3.1 for AGI, whose picture area is 200 lines. It costs NO
;              extra MMU blocks: 32,000 B is 3.91 blocks against mode 1's 3.75,
;              and both round up to 4, leaving 768 B spare in the last block.
;          Out-of-range falls back to mode 0 (same documented behaviour as
;          HAL_gfx_init's descriptor argument; no panic).
;   Returns: CC.C clear — always succeeds, no failure mode exists.
;   Errors:  none
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;
;   GUARANTEE ON RETURN: display is in the requested mode, BOTH buffers are
;   CLEARED to palette index 0, that mode's palette is loaded, the HAL_gfx_cur_*
;   geometry describes the active mode, the back buffer is mapped at
;   HAL_gfx_draw_base, and NOTHING carries over from the previous mode.
;   Clear-on-switch is the contract, not a side effect: the two modes pack pixels
;   at different widths, so surviving pixels would reinterpret as garbage rather
;   than as old content.
;
;   *** CALLER REQUIREMENT: THE STACK MUST NOT LIVE IN THE DRAW WINDOW ***
;   This service REMAPS MMU registers $FFA4-$FFA7, i.e. CPU $8000-$FFFF (moved
;   from $6000-$DFFF in P3.2 to make room for full-screen image assets). A caller
;   whose stack pointer is inside that range has the ground pulled out from under
;   it mid-call and does not return. Put the stack BELOW $8000:
;       lds  #$7F00        ; below the window, never remapped
;   Measured: without this, a probe that had worked for two dispatches hung the
;   moment set_mode gained its MMU mapping. Nothing warns you; the call simply
;   never comes back.
;
;   DOUBLE-BUFFERED, BOTH MODES (P2.6). One model; only the buffer SIZE differs.
;   Buffers live in PHYSICAL RAM (A $20000, B $30000) selected for display by
;   VOFFSET; the CPU sees only the BACK one, MMU-mapped at HAL_gfx_draw_base.
;
;   P2.5 recorded a worry that 16-colour double-buffering would need 60 KB of the
;   64 KB CPU window. That was WRONG — it reasoned about the CPU's view rather
;   than the machine's. There is no memory wall: 16-colour double-buffers exactly
;   like 4-colour.
;
;   Mode register values are CONFIRMED, not derived:
;   [ref: GIME_Reference_Manual.pdf §10 Video Mode Reference — the $FF99 table]
;   [ref: SockmasterGime.md:108-136 — $FF99 LPF/HRES/CRES bit layout]
;   [ref: src/hal/coco3-dsk/gfx.s — implementation, and the two deliberate
;     divergences from GIME-RM §14's ordering ($FF90 first, palette last)]
        ifdef   OBJTARGET
        import  HAL_gfx_set_mode
        endc

; HAL_gfx_swap                                        [P2.6 — the VBL-synced flip]
;   Show the buffer just drawn; map the other in as the new draw target.
;   Args:  none
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;
;   Order is load-bearing: WAIT for vertical blank, THEN write VOFFSET, THEN
;   remap. Writing VOFFSET mid-scanline switches the GIME's source address while
;   it is drawing — the top of the frame comes from one buffer and the bottom
;   from the other, which is a visible tear.
;
;   *** THE CC.I TRAP — read this before animating anything ***
;   HAL_time_vbl_wait does NOT wait when CC.I is SET. It takes its documented
;   fallback (Q001 N3=beta), synthesises a frame-counter increment and returns
;   immediately. A caller that leaves interrupts masked gets a swap loop running
;   flat out, flipping VOFFSET at arbitrary raster positions. It compiles, it
;   runs, the counters advance, and it tears.
;
;   REQUIRED CALLER SEQUENCE:
;       jsr  HAL_time_init      ; install the $010C VBL handler, enable VBORD
;       andcc #$EF              ; CLEAR CC.I -- nothing else will do this
;       lda  #<mode>
;       jsr  HAL_gfx_set_mode
;     loop:
;       ... draw into HAL_gfx_draw_base ...
;       jsr  HAL_gfx_swap
;       bra  loop
;   HAL_time_init deliberately does not clear CC.I (the E1.c invariant: HAL init
;   never changes the caller's mask state), so the andcc is the caller's job and
;   nothing will remind them.
        ifdef   OBJTARGET
        import  HAL_gfx_swap
        endc

; HAL_gfx_mirror                                    [POP P3.17 — kernel service]
;   Make the FRONT buffer identical to the BACK one, so a caller that draws a
;   small animation over a STILL background does not have to PRODUCE that
;   background twice. Building it twice is the obvious way and it is the slow
;   one: the second copy is made after the first swap, which means the viewer
;   waits through it with the finished picture already on screen.
;
;   Call it BEFORE the first swap. The screen is still black then, so the copy
;   costs the viewer nothing and both buffers are ready the instant anything
;   becomes visible.
;
;   ONLY LEGAL WHERE A FRAMEBUFFER FITS IN HALF THE WINDOW. Mapping both buffers
;   at once is what makes a copy possible at all, and 16-colour's 30,720 B needs
;   all four blocks to itself. The routine CHECKS this rather than trusting the
;   caller and refuses rather than corrupting.
;
;   Entry: nothing.  Exit: CC.C clear = mirrored, CC.C set = refused.
;   Callers that can run in either mode must handle the refusal — filling the
;   second buffer the slow way is the correct fallback, not an error path.
;   Clobbers: A, B, X. Restores the normal single-buffer mapping either way.
        ifdef   OBJTARGET
        import  HAL_gfx_mirror
        endc

; HAL_gfx_draw_base / HAL_gfx_cur_back / HAL_gfx_swaps(_hi)   [P2.6]
;   HAL_gfx_draw_base  2 B  CPU address of the BACK buffer. DRAW HERE, and
;                           nowhere else. The physical buffer addresses are
;                           HAL-private on purpose: a caller that hardcodes one
;                           writes to whichever buffer happens to be mapped,
;                           which surfaces only as an intermittent tear.
;   HAL_gfx_cur_back   1 B  current draw target, 0 = A, 1 = B
;   HAL_gfx_swaps(_hi) 2 B  swaps performed; the observable that distinguishes
;                           "flipping" from "drawing to a static screen"
        ifdef   OBJTARGET
        import  HAL_gfx_draw_base
        import  HAL_gfx_cur_back
        import  HAL_gfx_swaps
        import  HAL_gfx_swaps_hi
        endc

; HAL_gfx_cur_mode / _vres / _stride / _words / _palcnt   [P2.5]
;   Published geometry of the ACTIVE mode, written by HAL_gfx_set_mode.
;   Callers MUST draw with HAL_gfx_cur_stride: 80 in 4-colour, 160 in
;   16-colour. Using the wrong stride does not fail loudly — it skews the
;   image into a diagonal, which is why the value is published rather than
;   assumed by each caller.
;     HAL_gfx_cur_mode    1 B  active mode id
;     HAL_gfx_cur_vres    1 B  the $FF99 value written
;     HAL_gfx_cur_stride  1 B  bytes per row
;     HAL_gfx_cur_words   2 B  framebuffer size in words (bytes / 2)
;     HAL_gfx_cur_palcnt  1 B  palette entries loaded (4 or 16)
        ifdef   OBJTARGET
        import  HAL_gfx_cur_mode
        import  HAL_gfx_cur_vres
        import  HAL_gfx_cur_stride
        import  HAL_gfx_cur_words
        import  HAL_gfx_cur_palcnt
        endc

; HAL_gfx_present
;   Swap front/back buffers (double-buffer flip).
;   Args:  none
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Timing: call after render complete, before or during VBL
;   [no-ref: GIME buffer-base register (VOFF or equivalent)
;     for page flip — resolve during P2 from GIME-RM]
        ifdef   OBJTARGET
        import  HAL_gfx_present         ; defined in src/hal/coco3-dsk/gfx.s (P2.3a.5)
        endc

;==============================================================
; TIME SUBSYSTEM — DETAILED
; Frame timing, VBL synchronization, frame counter.
;
; [no-ref: VBL detection mechanism (polling $FF03 vs interrupt
;   vs GIME vsync bit) — resolve during P2 by reading CC3-TR
;   interrupt section and GIME-RM vsync documentation]
;==============================================================

; HAL_time_init
;   Initialize VBL source and start frame counter.
;   Args:  none
;   Returns: CC.C clear on success
;   Errors:  ERR_DEVICE if VBL source unavailable
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Init order: 2
        ifdef   OBJTARGET
        import  HAL_time_init           ; defined in src/hal/coco3-dsk/time.s
        endc

; HAL_time_vbl_wait
;   Block until next vertical blanking interval.
;   Replaces karateka_dissasembly_claude vbl_sync at $779A
;   (display_7700.s; 327,189 fires — hottest routine).
;   Args:  none
;   Returns: CC.C clear
;   Errors:  none (blocking)
;   Preserves: U, Y, X
;   Clobbers: A, B, CC
;   Side effects: increments internal frame counter
        ifdef   OBJTARGET
        import  HAL_time_vbl_wait       ; defined in src/hal/coco3-dsk/time.s
        endc

; HAL_time_frame_count
;   Return current 16-bit frame counter (wraps $FFFF→$0000).
;   Args:  none
;   Returns: D = frame count
;   Errors:  none
;   Preserves: U, Y, X, CC
;   Clobbers: D
        ifdef   OBJTARGET
        import  HAL_time_frame_count    ; defined in src/hal/coco3-dsk/time.s
        endc

; HAL_time_delay
;   Busy-wait N frames.
;   Args:  A = frame count to wait
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U, Y, X
;   Clobbers: A, B, CC
        ifdef   OBJTARGET
        import  HAL_time_delay          ; defined in src/hal/coco3-dsk/time.s
        endc

;==============================================================
; SOUND SUBSYSTEM — DETAILED
; DAC output and tone-record interpretation.
; Replaces karateka_dissasembly_claude sound_engine.s ($0D00)
; and sound.s pcm_player ($0DC0).
;
; [no-ref: CoCo3 DAC register address — resolve during P2
;   from CC3-TR sound/DAC section]
;==============================================================

; HAL_sound_init
;   Initialize sound hardware.
;   Args:  none
;   Returns: CC.C clear on success
;   Errors:  ERR_DEVICE if DAC not available
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Init order: 5
        ifdef   OBJTARGET
        import  HAL_sound_init          ; defined in src/hal/coco3-dsk/sound.s (P2.3a.3 stub)
        endc

; HAL_sound_shutdown
;   Silence output and release sound resources.
;   Args:  none
;   Returns: nothing
;   Errors:  none
;   Preserves: U, Y, X
;   Clobbers: A, B, CC
HAL_sound_shutdown  equ *       ; defined in src/hal/coco3-dsk/sound.s

; HAL_sound_dac_sample
;   Output one 6-bit DAC sample (low-level).
;   For per-frame PCM playback. Engine typically calls
;   HAL_sound_play_event rather than this directly.
;   Args:  A = 6-bit sample value (0-63)
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U, Y, X, B
;   Clobbers: A, CC
;   [no-ref: DAC register address — resolve during P2 from
;     CC3-TR]
HAL_sound_dac_sample equ *      ; defined in src/hal/coco3-dsk/sound.s

; HAL_sound_tone_start
;   Begin playing a tone-record sequence.
;   Data format matches karateka tone-record format (pass-
;   through from tools/sound_convert.py tone section).
;   Args:  X = pointer to tone-record sequence
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Side effects: HAL maintains playback state; advance
;     via per-frame HAL_sound_play_event or explicit update
HAL_sound_tone_start equ *      ; defined in src/hal/coco3-dsk/sound.s

; HAL_sound_tone_stop
;   Silence any active tone.
;   Args:  none
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U, Y, X
;   Clobbers: A, B, CC
HAL_sound_tone_stop equ *       ; defined in src/hal/coco3-dsk/sound.s

; HAL_sound_play_event
;   High-level sound event dispatch. Engine signals event by
;   ID; HAL maps to tone-record or PCM playback.
;   Args:  A = sound event ID (enumeration TBD during P2)
;   Returns: CC.C clear on success
;   Errors:  ERR_INVALID if event ID unknown
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   [no-ref: sound event ID → audio mapping is engine-internal;
;     table defined during P2 engine porting]
;   Note: may be removed in P2 if engine-side sound dispatch
;     makes this layer redundant. See docs/hal.md §5.3.
HAL_sound_play_event equ *      ; defined in src/hal/coco3-dsk/sound.s

;==============================================================
; MEMORY SUBSYSTEM — SKELETON
; Detailed during P2 when engine subsystem is ported.
;==============================================================

; HAL_mem_size_detect
;   Probe installed RAM at boot. Returns memory mode.
;   Args:  none
;   Returns: A = 0 if 128K, 1 if 512K
;   Errors:  none (always succeeds)
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Init order: 1 (first — other init may need memory info)
;   [no-ref: GIME MMU probing for 128K vs 512K — resolve
;     during P2 from CC3-TR MMU section; see D.5 pattern]
        ifdef   OBJTARGET
        import  HAL_mem_size_detect     ; defined in src/hal/coco3-dsk/mem.s (P2.3a.3 stub)
        endc

;==============================================================
; INPUT SUBSYSTEM — SKELETON
; Detailed during P2 when engine input subsystem is ported.
;==============================================================

; HAL_input_init
;   Initialize input scanning.
;   Args:  none
;   Returns: CC.C clear
;   Errors:  none
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Init order: 4
        ifdef   OBJTARGET
        import  HAL_input_init          ; defined in src/hal/coco3-dsk/input.s
        endc

; HAL_input_poll
;   Sample keyboard and joystick; return packed state.
;   Replaces karateka_dissasembly_claude input.s ($7603-$774A).
;   Args:  none
;   Returns: D = packed input state
;              A (hi): action bits (TBD during P2)
;              B (lo): directional bits (TBD during P2)
;   Errors:  none
;   Preserves: U, Y, X
;   Clobbers: A, B, CC
;   [no-ref: CoCo3 keyboard matrix registers — resolve during
;     P2 from CC3-TR input section]
        ifdef   OBJTARGET
        import  HAL_input_poll          ; defined in src/hal/coco3-dsk/input.s
        endc

;==============================================================
; FILE SUBSYSTEM — SKELETON
; Detailed during P2 when disk loading timing is understood.
;==============================================================

; HAL_file_init
;   Initialize disk subsystem.
;   Args:  none
;   Returns: CC.C clear on success
;   Errors:  ERR_DEVICE if disk controller not available
;   Preserves: U, Y
;   Clobbers: A, B, X, CC
;   Init order: 6 (last)
        ifdef   OBJTARGET
        import  HAL_file_init           ; defined in src/hal/coco3-dsk/file.s (P2.3a.3 stub)
        endc

; HAL_file_load
;   Load entire named file to a memory address.
;   Replaces karateka_dissasembly_claude disk_loader.s ($0300).
;   Args:  X = pointer to null-terminated filename
;          U = destination address
;          D = byte count (0 = load entire file)
;   Returns: D = bytes loaded, CC.C clear on success
;   Errors:  ERR_NOT_FOUND, ERR_IO, ERR_NOMEM
;   Preserves: Y
;   Clobbers: A, B, X, U, CC
HAL_file_load       equ *       ; (P2 stub)

;==============================================================
; SYSTEM SUBSYSTEM — P2.3a.0
; HAL_sys_init implemented. Remainder still skeleton.
;==============================================================

; HAL_sys_init
;   CoCo3 bare-metal transition. Call before all other HAL init.
;   Masks interrupts, enables all-RAM mode + GIME MMU, programs
;   MMU task 0 slots to P1.6 physical page layout ($38-$3F).
;
;   Does NOT install interrupt vectors at runtime. The dispatch
;   block at $0100-$010F (RTI stubs) is loaded by DECB. BASIC's
;   $FExx secondary vectors remain in effect (locked by MC3=1
;   in $FF90=$4C). See docs/interrupt-handling.md for full
;   dispatch documentation.
;
;   Args:    none
;   Returns: CC.C clear; CC.I=1, CC.F=1 (interrupts MASKED on return)
;   Errors:  none
;   Preserves: U, Y
;   Clobbers: A, X, CC
;   Init order: 0 (first — call before HAL_mem_size_detect)
;   Precondition: BASIC boot complete; DP=0; stack initialized
;   Postcondition: all-RAM active, MMU $38-$3F, interrupts masked
;   [ref: src/hal/coco3-dsk/sys.s — implementation]
;   [ref: docs/interrupt-handling.md — dispatch block design]
;   [ref: docs/conventions.md — interrupt mask policy section]
        ifdef   OBJTARGET
        import  HAL_sys_init            ; defined in src/hal/coco3-dsk/sys.s
        endc

; HAL_sys_cpu
;   Return detected CPU type (cached from boot probe).
;   Args:  none
;   Returns: A = 0 (6809) or 1 (6309)
;   Errors:  none
;   Preserves: B, X, Y, U, DP
;   Clobbers: A, CC
HAL_sys_cpu         equ *       ; (P2 stub)

; HAL_sys_target
;   Return target platform identifier (constant).
;   Args:  none
;   Returns: A = 0 (coco3-dsk; only target in v1.0)
;   Errors:  none
;   Preserves: B, X, Y, U, DP
;   Clobbers: A, CC
HAL_sys_target      equ *       ; (P2 stub)

; HAL_sys_panic
;   Unrecoverable error handler. Display message, halt.
;   Args:  X = pointer to null-terminated message (or 0)
;   Returns: does not return
;   Errors:  this IS the error path
        ifdef   OBJTARGET
        import  HAL_sys_panic           ; defined in src/hal/coco3-dsk/sys.s
        endc

;==============================================================
; DEBUG/TRACE SUBSYSTEM — DETAILED
; Always-on trace mechanism for harness instrumentation plus
; DEV_MODE-only logging and assertions.
;
; HAL_debug_trace_event is ALWAYS present (all builds). The
; MAME scripted-test harness reads the trace ring buffer to
; verify engine behavior. Compiling it out of production builds
; would prevent harness coverage on release binaries.
;
; HAL_debug_log and HAL_debug_assert are DEV_MODE-only. Wrap
; them in ifdef DEV_MODE blocks (see docs/conventions.md §9).
;
; Engine event code enumeration is engine-internal. The HAL
; accepts event codes as opaque bytes (0-255). Engine defines
; its own enum in src/engine/trace_events.inc (materializes
; during P2 when first trace points are added).
;
; Trace buffer: a fixed-size ring buffer at a known memory
; address. Address assigned during P1.6 memory map work.
; [no-ref: trace buffer location — deferred to P1.6]
;==============================================================

; HAL_debug_trace_event
;   Record an instrumentation event in the trace ring buffer.
;   Called by engine code at state transitions, subsystem
;   entry/exit, and other significant points. MAME harness
;   reads the ring buffer to verify expected event sequences.
;   ALWAYS PRESENT — not DEV_MODE gated.
;   Args:  A = event code (0-255; engine-defined opaque byte)
;          X = event data pointer (or 0 if no data)
;   Returns: nothing (always succeeds; no error path)
;   Preserves: U, Y, X, B
;   Clobbers: A, CC
;   [no-ref: trace mechanism is engine-internal; no hardware
;     reference applies]
HAL_debug_trace_event equ *     ; defined in src/hal/coco3-dsk/debug.s

; HAL_debug_log
;   Emit a null-terminated debug string to implementation-
;   defined destination (MAME debug log, serial port, ring
;   buffer, etc.). DEV_MODE only — wrap in ifdef DEV_MODE.
;   Args:  X = pointer to null-terminated string
;   Returns: nothing (always succeeds)
;   Preserves: U, Y, X
;   Clobbers: A, B, CC
;   [no-ref: debug output destination is implementation choice;
;     no hardware reference applies]
HAL_debug_log       equ *       ; defined in src/hal/coco3-dsk/debug.s

; HAL_debug_assert
;   Verify a precondition. If condition is false, call
;   HAL_sys_panic with message and halt. DEV_MODE only —
;   wrap in ifdef DEV_MODE (or use DEV_MODE_ASSERT macro).
;   Args:  A = condition (0 = fail, non-zero = pass)
;          X = pointer to null-terminated assertion message
;   Returns: nothing on pass (CC.C clear)
;   Errors:  does not return on failure — calls HAL_sys_panic
;   Preserves: U, Y (on pass)
;   Clobbers: A, B, CC
;   Within-HAL call note: HAL_debug_assert calls HAL_sys_panic
;     on failure. This is the one permitted within-HAL call in
;     the contract; HAL functions are otherwise not safe to call
;     from other HAL functions.
;   [no-ref: assertion mechanism is engine-internal; no hardware
;     reference applies]
HAL_debug_assert    equ *       ; defined in src/hal/coco3-dsk/debug.s
