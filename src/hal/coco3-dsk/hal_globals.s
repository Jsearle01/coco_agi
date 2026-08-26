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
* The palettes are shared and live in gfx.s.
                ifdef   HAL_GFX_MODE_SERVICE

                ifdef   OBJTARGET
                section code
                endc

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
        fdb     gfx_pal16               ;   shared palette; AGI's own palette is loaded by the
                                        ;   engine at init (design §2.2), not from here
        fcb     16                      ;   palette regs $FFB0-$FFBF

                ifdef   OBJTARGET
                endsection
                endc

                endc                    ; HAL_GFX_MODE_SERVICE
