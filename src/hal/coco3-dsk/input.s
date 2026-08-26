* src/hal/coco3-dsk/input.s
*
* HAL Input subsystem — real polled implementation (R-p24).
*
* Purpose:
*   HAL_input_init asserts PIA0 data-register access mode; HAL_input_poll
*   performs a CoCo3 keyboard-matrix + joystick-button scan and reports
*   whether any input is present. Replaces the P2.2 stubs.
*
* INPUT IS POLLED (no interrupts). The R-boot HAL_sys_init disabled PIA0
*   CA1/CA2/CB1/CB2 IRQ generation (CR bits 0,1 cleared, mask $FC). That
*   suppresses IRQ assertion only; the PIA data registers ($FF00/$FF02)
*   remain fully readable/writable, so polled scanning works WITHOUT any
*   CA/CB re-enable. Re-enabling PIA IRQ would reintroduce the R-boot
*   keyboard-IRQ trap (PIA IRQ lines OR onto the 6809 IRQ pin, bypassing
*   GIME) — so this subsystem must NOT re-enable it.
*   [ref: src/hal/coco3-dsk/sys.s Step 2 — PIA IRQ disable, mask $FC]
*   [ref: docs/project/conventions.md — scene-1 polled-input / CR-bit-2 rule]
*
* CoCo3 keyboard matrix (PIA0, [ref: CC3-TR §keyboard]):
*   $FF00 (PDRA) — row sense PA0-PA6 (7 rows, active low); PA7 = joystick
*                  comparator (not a key row; masked off).
*   $FF02 (PDRB) — column strobe PB0-PB7 (8 columns, drive low to select).
*   $FF01/$FF03 (CRA/CRB) bit 2 = 1 selects data register (vs DDR). BASIC
*                  configured DDRA=inputs / DDRB=outputs; that DDR config
*                  persists (no DDR write anywhere in the boot path —
*                  verified by the R-p24 DDR-persistence sweep).
*   Scan-all: drive all columns low ($FF02=$00); any pressed key OR
*   joystick fire button (matrix-connected on PA0/PA1) pulls its row line
*   low, so PA0-PA6 != all-high ⇒ input present.
*
* R-p24 SCOPE: detection only ("any input" → scene advance, the Apple II
*   "ordinary key/button advances past title" semantics). Full action /
*   directional bit decode (a real keymap + joystick axes) is deferred to
*   gameplay (R-p25+); HAL_input_poll returns A = pressed-row mask, B = 0.
*
* Apple II equivalent:
*   [ref: kernel_per_frame.s input_poll_loop — 65536-iter poll of
*    KBD ($C000), KBDSTRB ($C010), RDBTN0 ($C061), RDBTN1 ($C062)]
*   [ref: input.s L7603-$774A — keyboard handler subsystem]
*
* HAL contract reference: src/hal.inc (HAL_input_* definitions)
*   [ref: hal.inc HAL_input_init — Args: none; Returns: CC.C clear]
*   [ref: hal.inc HAL_input_poll — Args: none; Returns: D=input state]
*   [ref: docs/project/hal.md §5.5 Input — skeleton subsystem]
*
* Calling convention:
*   [ref: conventions.md §3 — CC.C clear on success]
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
        export  HAL_input_init
        export  HAL_input_poll
        endc

* ---------------------------------------------------------------
* HAL_input_init
*
* Initialize input subsystem.
*
* ORIGIN: no Apple II equivalent (Apple II polls hardware directly)
*
* Asserts PIA0 data-register access (CR bit 2 = 1) on both sides so the
* scan reads PDRA/PDRB (not DDR), while KEEPING CA/CB IRQ disabled (CR
* bits 0,1 = 0 — does NOT re-enable the R-boot-suppressed PIA IRQ). Does
* not touch DDR (relies on BASIC's persisting keyboard DDR config).
*
* [ref: hal.inc HAL_input_init — Args: none; Returns: CC.C clear]
* [ref: docs/project/hal.md §7 Init Order — init order 4]
* [ref: src/hal/coco3-dsk/sys.s — R-boot CR mask $FC, IRQ stays disabled]
* Clobbers: A, CC
* ---------------------------------------------------------------
HAL_input_init:
        lda     $FF01                   ; PIA0 CRA (row side)
        anda    #$FC                    ; keep CA1/CA2 IRQ disabled (no re-enable)
        ora     #$04                    ; CR bit2=1: access PDRA (data), not DDRA
        sta     $FF01
        lda     $FF03                   ; PIA0 CRB (column side)
        anda    #$FC                    ; keep CB1/CB2 IRQ disabled
        ora     #$04                    ; CR bit2=1: access PDRB (data), not DDRB
        sta     $FF03
        andcc   #$FE                    ; CC.C clear = success
        rts

* ---------------------------------------------------------------
* HAL_input_poll  [R-p24 — real polled scan]
*
* Sample the CoCo3 keyboard matrix + joystick fire buttons; report
* whether ANY input is present (R-p24 detection-only scope).
*
* Method: drive all 8 keyboard columns low ($FF02=$00) so any pressed
* key/button pulls its row line (PA0-PA6) low; read $FF00; mask off PA7
* (joystick comparator); complement → pressed-row mask. Restore columns.
*
* Returns: CC.C set  = input present; CC.C clear = none.
*          A = pressed-row mask (nonzero ⇒ input); B = 0 (directional
*              decode deferred to R-p25+ — see file header SCOPE note).
*
* ORIGIN: karateka_dissasembly_claude src/intro.s routine_b7f5 +
*         kernel_per_frame.s input_poll_loop (Apple II polled KBD/RDBTN;
*         "ordinary key/button advances past title").
*         [ref: input.s routine_b7f5 — lda KBD; RDBTN0/RDBTN1]
*
* PRECONDITION: HAL_input_init asserted CR bit 2 = 1 (data mode); BASIC's
*   keyboard DDR persists (no DDR write in the boot path).
* [ref: hal.inc HAL_input_poll — Returns: D=input state, CC.C=present]
* Clobbers: A, B, CC.  Preserves X, Y, U.
* ---------------------------------------------------------------
HAL_input_poll:
        lda     #$00
        sta     $FF02                   ; drive all 8 columns low (select all keys)
        lda     $FF00                   ; read row sense PA0-PA6 (+ PA7 comparator)
        ldb     #$FF
        stb     $FF02                   ; deselect columns (idle state)
        ora     #$80                    ; force PA7=1 — ignore joystick comparator
        coma                            ; A = pressed-row mask (0 ⇒ none); sets Z
        beq     hal_input_none
        clrb                            ; B = 0 (directional decode deferred)
        orcc    #$01                    ; CC.C set = input present
        rts
hal_input_none:
        clrb
        andcc   #$FE                    ; CC.C clear = no input
        rts
                
                ifdef   OBJTARGET
                endsection
                endc
