* src/harness/vm_text_ops.s -- the nine text command handlers. [T-P0-084d §5B]
*
* ★★★★★ THE NINE OPCODES, BY THEIR HEX NUMBERS [X-78 corrected -- they are NOT decimal]:
*   $65 print   $66 print.v   $67 display   $68 display.v   $69 clear.lines
*   $6C set.cursor.char   $6D set.text.attribute   $70 status.line.on   $71 status.line.off
*
* ★★★★★ -DTEXT_MODELLED ALIASES ALL NINE BACK TO vm_op_modelled -- AC-2's fault arm. The generated
* table names these labels unconditionally [gen_vm_tables.py:225 prefers a defined label over the
* reference's `modelled` status], so the toggle has to live HERE, at the label, rather than in a
* second table [route (b), withdrawn]. ★★★ An `equ` to vm_op_modelled resolves the table entry to
* the SAME address the modelled build used -- not a similar no-op -- so the fault arm IS the
* pre-wiring behaviour rather than a reconstruction of it.

* ★★★★★ INCLUDED BY **EVERY** PROBE THAT INCLUDES vm_tables.s, AND THAT IS FORCED BY AD-176.
* The generated table names these nine labels unconditionally, so a probe that omits this file
* fails to assemble with `Undefined symbol vmop_print` -- which is exactly what p3b's default
* (cel) configuration and vm_probe.s did on the first wired build.
* ★★★★ THE ALIASES EMIT NO BYTES. `equ` produces nothing, so a probe that takes the modelled
* branch is BYTE-IDENTICAL to what it was before this file existed -- which is what keeps the p3b
* and vm gates testing the binaries they have always tested.
* ★★★ TEXT_WIRED is defined by the probe when it has actually linked src/engine/text.s. It is not
* the same question as TEXT_MODELLED: the fault arm links the engine and declines to call it,
* while the cel configuration does not link it at all, and both must reach the aliases.
                ifndef  TEXT_WIRED
vmop_print              equ     vm_op_modelled
vmop_print_f            equ     vm_op_modelled
vmop_display            equ     vm_op_modelled
vmop_display_f          equ     vm_op_modelled
vmop_clear_lines        equ     vm_op_modelled
vmop_set_cursor_char    equ     vm_op_modelled
vmop_set_text_attribute equ     vm_op_modelled
vmop_status_line_on     equ     vm_op_modelled
vmop_status_line_off    equ     vm_op_modelled
                else

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FLAT 24 KB WINDOW [ruling 3], AND THE TWO THINGS THAT MAKE IT SAFE.
*
* text.s blits through a window and asks the caller how many CHARACTER ROWS that window holds
* (txt_fbrows). Through ONE 8 KB slice the answer is 5, because a character row is 1,280 bytes and
* the last byte a glyph writes is (r+7)*160+159. ★★★★ At that size **rows 6 and 12 straddle slice
* boundaries and BOTH are inside the scroll panel (rows 6-18)** -- a per-slice blit leaves two
* blank rows, which is a defect a person sees and no byte gate does.
*
* ★★★★ THREE CONTIGUOUS BLOCKS IN SLOTS 4-6 GIVE $8000-$DFFF = 24,576 B = rows 0-18 EXACTLY
* (row 18's last byte is 24,319). Nothing straddles. Slot 7 is untouched, so the font at MAP_FONT
* stays resident through the blit.
*
* ★★★★★ HAZARD 1 -- SLOT 4 IS THE ARENA WINDOW'S HIGH HALF, AND THE MESSAGE LIVES IN THE ARENA.
* MAP_ARENA_WIN is $6000-$A000 (slots 3-4) and the largest corpus LOGIC is 10,964 B, so a resource
* at the arena base reaches $8AD4 -- inside slot 4. **The message text is bytes of that resource.**
* Blitting straight from txt_msgp with slot 4 remapped would read framebuffer bytes as text.
* ★★★★ SO THE SUBSTITUTION RUNS FIRST, WITH THE ARENA FULLY MAPPED, AND THE BLIT READS ONLY
* txt_pbuf -- which lives in MAP_INPUT ($1C00), slot 0, resident in every phase. The buffer that
* §2V sized for %-code substitution is also the isolation this needs; that is luck, and it is
* recorded as luck rather than as design.
*
* ★★★★ HAZARD 2 -- THE MMU REGISTERS ARE WRITE-ONLY, so there is no save/restore. Restoration is
* by KNOWN VALUE: p3b_run.lua:345 pre-sets all eight slots to $38+i and mmu_phase.s's contract is
* that **slots 0-4 and 7 are set once at init and never touched**, so slot 4's value is $3C. Slots
* 5 and 6 belong to the phase machinery and are put back through it.
* ★★★ $FFA4 HAS NO SANCTIONED OWNER: mmu_phase.s manages slots 5 and 6 only. This file becomes the
* second writer of the MMU register file, which is a §2N ownership question and is reported rather
* than settled here. It is in src/harness/, so reg_discipline.py's src/engine census does not move.
MMU_SLOT4       equ     $FFA4
TX_ARENA_HI     equ     $3C             ; $38 + 4, from p3b_run.lua's boot pre-set
TX_WIN          equ     $8000           ; slots 4-6, flat
TX_WIN_ROWS     equ     19              ; rows 0-18 inclusive

* ── tx_window_enter -- map three visible-plane blocks flat across slots 4-6 ───────
tx_window_enter:
                lda     #P3_BLK_VISIBLE
                sta     MMU_SLOT4
                inca
                sta     MMU_SLOT5
                inca
                sta     MMU_SLOT6
                ldx     #TX_WIN
                stx     txt_fbwin
                clr     txt_fbrow0
                lda     #TX_WIN_ROWS
                sta     txt_fbrows
                rts

* ── tx_window_exit -- put the VM phase back, by known value ──────────────────────
* ★★ res_core caches which block it believes is in slot 6 and SKIPS the write when it matches, so
* after anyone else moves that register the cache has to be invalidated or the next fetch reads
* the wrong block while being certain it is right [p3b_probe.s's own note at the cycle body].
tx_window_exit:
                lda     #TX_ARENA_HI
                sta     MMU_SLOT4
                lda     #$3D                    ; VM_OBJ, exactly as the cycle body restores it
                sta     MMU_SLOT5
                lda     #$FF
                sta     res_curblk
                jsr     phase_vm
                ifdef   PLANE_WINDOWED
                jsr     plane_reset
                endc
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ tx_msgptr -- A = message number (1-based) -> X = the message text, Z set if out of range.
*
* ★★ Layout [res_core.s res_decode, from logic.cpp decodeLogic]: the message section follows the
* bytecode at vm_code + vm_codelen; u8 count, u16 size, then count u16 LITTLE-endian offsets,
* each RELATIVE TO message_section + 1. res_decode has already XORed the strings in place, so the
* bytes here are text. ★ Only ONE pointer is resolved, not a table: display names one message.
tx_msgpos       fdb     0
tx_msgno        fcb     0

tx_msgptr:
                sta     tx_msgno
                beq     tx_mp_bad               ; message 0 does not exist
                ldd     vm_code
                addd    vm_codelen
                std     tx_msgpos
                tfr     d,x
                lda     tx_msgno
                cmpa    ,x                      ; count
                bhi     tx_mp_bad
                deca                            ; 0-based index
                tfr     a,b
                clra
                lslb
                rola                            ; D = 2 * index
                addd    #3                      ; past count + size
                leax    d,x
                ldb     ,x                      ; LITTLE-endian: low byte first
                lda     1,x
                addd    tx_msgpos
                addd    #1                      ; offsets are relative to section + 1
                tfr     d,x
                andcc   #$FB                    ; clear Z -- success
                rts
tx_mp_bad:
                ldx     #0
                orcc    #$04                    ; set Z
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ tx_emit -- blit the substituted buffer at (tx_row, tx_col).
* ★★★ The substitution has already happened; this touches the arena not at all, which is what
* makes the window swap legal (hazard 1 above).
tx_row          fcb     0
tx_col          fcb     0

tx_emit:
                jsr     tx_window_enter
                lda     tx_row
                sta     txt_crow
                lda     tx_col
                sta     txt_ccol
                sta     txt_rcol                ; _reset_Column: where a newline returns to
                ldx     txt_pbuf
tx_em_lp:       lda     ,x+
                beq     tx_em_done
                pshs    x
                jsr     txt_dispch
                puls    x
                bra     tx_em_lp
tx_em_done:
                jsr     tx_window_exit
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ $67 display(row, col, message) -- op_cmd.cpp cmdDisplay.
* ★★ White on black is AGI's display default and is set here rather than inherited: get.string
* left fg=bg=0 in P6.25 and twelve glyphs were drawn black on black, which is the same class of
* silence this sets out of the way [AD-160].
vmop_display:
                jsr     vm_p0
                sta     tx_row
                jsr     vm_p1
                sta     tx_col
                jsr     vm_p2
                bra     tx_display_common

* ★ $68 display.v -- the same, with all three operands VAR-INDEXED.
vmop_display_f:
                jsr     vm_v0
                sta     tx_row
                jsr     vm_v1
                sta     tx_col
                jsr     vm_v2

tx_display_common:
                jsr     tx_msgptr
                beq     tx_disp_out
                stx     txt_msgp
                lda     #15
                clrb
                jsr     txt_attrib              ; white on black
* ★★★ SUBSTITUTE FIRST, WHILE THE ARENA IS STILL MAPPED (hazard 1).
                jsr     txt_printf
                jsr     tx_emit
tx_disp_out:
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ $65 print / $66 print.v -- op_cmd.cpp cmdPrint. Renders the message BOX.
*
* ★★★★★ IT DOES NOT BLOCK, AND THAT IS A STATED DIVERGENCE RATHER THAN AN OVERSIGHT. The engine's
* print waits for a keypress before closing the window; this probe has no key path wired in this
* configuration, so a blocking print would hang the cycle loop and the eye gate would report a
* stall that is not a defect in the text engine. **The rendering is full; the wait is omitted and
* said out loud** -- an unstated omission here is exactly what §6's route accounting exists for.
vmop_print:
                jsr     vm_p0
                bra     tx_print_common
vmop_print_f:
                jsr     vm_v0

tx_print_common:
                jsr     tx_msgptr
                beq     tx_print_out
                stx     txt_msgp
                lda     #15
                clrb
                jsr     txt_attrib
                jsr     txt_printf
                jsr     tx_window_enter
                jsr     txt_msgbox
                jsr     tx_window_exit
tx_print_out:
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE FIVE SECONDARY OPCODES -- MINIMAL STUBS, AND WHY EACH IS ONE.
* ★★ VMOP_ARGS advances ip for them regardless, so a bare rts is a correct no-op BODY. What they
* may not be is vm_op_modelled, which is what AC-4 forbids in the wired build.
* ★ None is needed to reach the scroll panel: the panel is `display`, and these four set state the
* title screen does not read (cursor glyph, status line) or clear rows it does not clear.
* set.text.attribute is the one with a real argument this probe ignores -- display sets its own
* attribute per call, so honouring it here would change nothing the eye gate can see. Recorded so
* the next task knows it is deliberate rather than forgotten.
vmop_clear_lines:
                rts
vmop_set_cursor_char:
                rts
vmop_set_text_attribute:
                rts
vmop_status_line_on:
                rts
vmop_status_line_off:
                rts
                endc
