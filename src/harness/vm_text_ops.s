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
* ★★★★★ THE clr GOES **ABOVE** THE sta, AND PUTTING IT BELOW BROKE THE ROUTINE IT MEASURES.
* `clr` sets Z unconditionally, so with it between `sta tx_msgno` and `beq tx_mp_bad` **every call
* took the out-of-range branch** -- and the diagnostic then faithfully reported msgpos $0000,
* count 0, ok 0 for a message number of 4. ★★★★ That is §2W.3 exactly: the instrument manufactured
* the failure it was installed to explain, and its output was entirely self-consistent.
* ★★★ `sta` sets Z from A, which is the test this routine wants, so the clear must precede it.
                ifdef   TX_MSGDIAG
                clr     tx_diag_cnt             ; ★ so a stale count is never logged
                endc
                sta     tx_msgno
                beq     tx_mp_bad               ; message 0 does not exist
                ldd     vm_code
                addd    vm_codelen
                std     tx_msgpos
                tfr     d,x
                ifdef   TX_MSGDIAG
* ★★ B is dead here -- it holds the low half of the sum and is overwritten by `tfr a,b` below --
* so capturing the count costs no save/restore. It is the byte the compare is ABOUT to read.
                ldb     ,x
                stb     tx_diag_cnt
                endc
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
                ifdef   TX_MSGDIAG
                jsr     tx_diag_ok
                endc
                rts
tx_mp_bad:
                ldx     #0
                orcc    #$04                    ; set Z
                ifdef   TX_MSGDIAG
                jsr     tx_diag_bad
                endc
                rts

                ifdef   TX_MSGDIAG
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE DIFFERENTIAL LOGGER [T-P0-087 §4A]. One record per call, first 8 per site.
* ★★★★ IT MUST PRESERVE CC AND X, because they ARE tx_msgptr's return protocol -- Z says
* in-range and X is the message pointer. `pshs cc` is the FIRST instruction of both entry points
* for that reason; anything before it would report on a flag it had already changed.
* ★★★ On the tx_mp_bad path tx_msgpos may be STALE (msgno 0 branches before it is computed) and
* tx_diag_cnt is cleared at entry, so a zero count column means "never read", not "read as zero".
tx_diag_site    fcb     0                       ; 1 = display, 2 = print; set by the caller
tx_diag_cnt     fcb     0
tx_diag_res     fcb     0
tx_diag_n1      fcb     0
tx_diag_n2      fcb     0

tx_diag_ok:     pshs    cc,d,x
                lda     #1
                bra     txd_go
tx_diag_bad:    pshs    cc,d,x
                clra
txd_go:         sta     tx_diag_res
                lda     tx_diag_site
                cmpa    #1
                bne     txd_print
                lda     tx_diag_n1
                cmpa    #TXD_EACH
                bhs     txd_out                 ; this site's slots are full
                inc     tx_diag_n1
                ldx     #P3_TXDIAG
                bra     txd_have
txd_print:
                lda     tx_diag_n2
                cmpa    #TXD_EACH
                bhs     txd_out
                inc     tx_diag_n2
                ldx     #P3_TXDIAG+TXD_EACH*TXD_REC
txd_have:
                ldb     #TXD_REC
                mul                             ; D = slot * 12
                leax    d,x
                lda     tx_diag_site
                sta     ,x
                lda     tx_msgno
                sta     1,x
                ldd     vm_code
                std     2,x
                ldd     vm_codelen
                std     4,x
                ldd     tx_msgpos
                std     6,x
                lda     tx_diag_cnt
                sta     8,x
                lda     vm_curlogic
                sta     9,x
                lda     tx_diag_res
                sta     10,x
                lda     vm_cycle+1
                sta     11,x
txd_out:
                puls    cc,d,x,pc
                endc

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
                ifdef   TX_MSGDIAG
                pshs    a                       ; ★ A is the message number -- do not disturb it
                lda     #1
                sta     tx_diag_site
                puls    a
                endc
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
* ★★★★★ IT BLOCKS, WHERE THE ORACLE BLOCKS -- inside the opcode, inside the cycle [T-P0-085c §1.1].
* Nothing unwinds, so §1.3's invariant holds BY CONSTRUCTION: the cycle counter is never reached,
* nothing re-dumps, and res_cache_flush is never called under a running logic.
vmop_print:
                jsr     vm_p0
                bra     tx_print_common
vmop_print_f:
                jsr     vm_v0

tx_print_common:
                ifdef   TX_MSGDIAG
                pshs    a
                lda     #2
                sta     tx_diag_site
                puls    a
                endc
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ FLAG 15 SITS ABOVE THE WAIT, AND THE ORDER IS THE ORACLE'S [text.cpp:373-380]:
*     if (_vm->getFlag(VM_FLAG_OUTPUT_MODE)) { setFlag(..., false); nonBlockingText_IsShown();
*                                              return true; }
* ★★★ The check is ABOVE the loop, not inside it, and it CLEARS the flag as it passes -- the flag
* is one-shot, so a game that wants a second non-blocking box must set it again.
* ★★ `nonBlockingText_IsShown()` has no counterpart here: it feeds ScummVM's own redraw
* bookkeeping, which this port does not have. Stated, not invented [§2.1].
                lda     #VM_FLAG_OUTPUT_MODE
                jsr     vm_getflag
                beq     tx_print_wait           ; flag clear -> blocking window
                lda     #VM_FLAG_OUTPUT_MODE
                clrb
                jsr     vm_setflag              ; one-shot: consume it
                rts                             ; ★ box stays up, no wait, no close
tx_print_wait:
                jsr     tx_wait_dismiss
                jsr     txt_close
tx_print_out:
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ tx_wait_dismiss -- THE LOOP, AND IT SERVICES WHAT THE CYCLE WOULD HAVE [§1.3, §4A].
*
* ★★★★★ A BLOCK THAT STARVES THE IN-GAME TIMER CANNOT AUTO-CLOSE, because var 21 is measured in
* elapsed time and nothing else advances the game clock inside a cycle. The oracle services it every
* pass -- `inGameTimerUpdate()` at text.cpp:399 -- and so does this.
*
* ★★★★★ THE DEADLINE IS MEASURED ON THE GAME CLOCK, NOT ON WALL TIME, AND THAT IS READ FROM THE
* ORACLE RATHER THAN CHOSEN [text.cpp:395-409]:
*     inGameTimerResetPassedCycles();          <- entry
*     do { processAGIEvents(); inGameTimerUpdate();
*          if (windowTimer > 0 && inGameTimerGetPassedCycles() >= windowTimer) ...close
*     } while (...);
*     inGameTimerResetPassedCycles();          <- exit
* ★★★★ So the counter the box counts in IS the in-game timer's, and the loop advances it itself.
* **That makes "a block that starves the game clock" and "a box that never auto-closes" the SAME
* defect**, which is what AC-8's fault arm exercises [§2W].
*
* ★★★★★ AND cycle.cpp:558 SETTLES WHICH COUNTER: `if (_passedPlayTimeCycles >= timeDelay)` then
* `inGameTimerResetPassedCycles()` -- **the pacing gate and this deadline are the same variable**,
* which here is vm_passed (vm_pace tests it against vm_tdelay and clears it, vm_cycle.s:316-322).
* ★★★★ §4A's census called vm_passed "a counter this loop must not disturb, because advancing it
* would make the next vm_pace short". **The oracle disturbs it deliberately, on both sides.** A
* short next pace is not a side effect to be avoided here, it is text.cpp:409's behaviour -- so
* vm_step_clock is called whole rather than having its parts copied out.
*
* ★★★★ WHAT IS SERVICED, AND WHAT IS DELIBERATELY NOT [§4A's census, as corrected]:
*   vm_step_clock                       CALLED WHOLE, once per VBL tick -- the game clock
*                                       (vm_vms), vm_passed, vm_timer_update and the tdelay
*                                       recompute, which is the set the oracle's loop advances
*   the key scan                        SERVICED -- it is the dismissal
*   hal_frame_hi/lo                     SELF-SERVICING -- the $010C IRQ advances it through a
*                                       block, so it is the TICK SOURCE here and never the deadline
*   motion / sprites / the cycle body   NOT serviced, and harmless: the oracle's cycle is suspended
*                                       across a blocking box too, so freezing them is fidelity
*   sound                               nothing to starve -- every sound opcode is vm_op_modelled
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE TIMER TICK BELONGS TO THE MESSAGE BOX AND MUST NOT BE HOISTED [Amendment 1].
* `print` is NOT the only opcode that blocks. op_cmd.cpp:736-746 -- **and it names this target**:
*     if (platform == kPlatformApple2 || platform == kPlatformCoCo3) {
*         // Sound playback is a blocking operation on these platforms.
*         startSound(...); waitAnyKeyOrFinishedSound(); stopSound(); }
*     setFlagOrVar(flagNr, true);
* ★★★★ waitAnyKeyOrFinishedSound (keyboard.cpp:685-694) is a plain `while` INSIDE the opcode -- not
* a cycleInnerLoop -- so it is the same shape as this loop and the host handshake covers both.
* ★★★★★ BUT IT DOES **NOT** CALL inGameTimerUpdate(). The game clock advances across a message box
* and does NOT advance across a blocking sound. **So a shared "block until a key" helper with the
* tick inside it would give sound a tick the oracle does not have.** The tick stays here, in print's
* own loop, and that is now a reason rather than an accident.
* ★★★ Nothing to do today -- 62/63/64 are vm_op_modelled and src/engine/sound/ is empty -- and the
* finding is recorded at the seam for whoever implements it [§4A's census: not applicable because
* unimplemented, with the shape named].
*
* ★★★★ VAR 21's TIMEBASE, DERIVED [§4D]. The data-format fact is **1 = 0.5 seconds**; ScummVM's
* `* 20` at text.cpp:392 is ITS OWN correction -- its passed-cycles unit is 25 ms (global.cpp:262,
* `curPlayTimeMilliseconds / 25`) and 0.5 s / 25 ms = 20. Ours is the VERTICAL SYNC: vm_step_clock's
* header calls its unit "one VERTICAL-SYNC tick" and vm_cycle.s:364 fixes it at 16.667 ms, so
*     0.5 s / 16.667 ms = 30 ticks per unit   ->   timeout = var21 * 30
* ★★★ 30 against the oracle's 20 for the SAME half-second: the unit differs, the semantics do not.
TX_TICKS_PER_UNIT equ   30

* ★★ §2V.2: the oracle holds passed-cycles in a uint32 and compares it to windowTimer. On the 6809
* vm_passed is a BYTE and var21*30 reaches 7,650, so the deadline cannot live in it. It is held
* instead as an ABSOLUTE 16-bit mark on vm_vms' low half -- one fdb, no second counter to keep in
* step, and the comparison below is wrap-safe.
tx_wt_end       fdb     0               ; vm_vms+2 value at which the box auto-closes
tx_wt_timed     fcb     0               ; non-zero = var 21 was set, so a deadline exists
tx_wt_last      fcb     0               ; hal_frame_lo as last seen, for edge detection
tx_wt_key       fcb     0

tx_wait_dismiss:
                clr     tx_wt_key
* ── the deadline, if var 21 is non-zero ──
                lda     #VM_VAR_WINDOW_AUTO_CLOSE_TIMER
                jsr     vm_getvar
                sta     tx_wt_timed
                beq     tx_wt_notimed
                ldb     #TX_TICKS_PER_UNIT
                mul                             ; D = var21 * 30, game-clock ticks
                addd    vm_vms+2                ; ★ absolute mark on the clock vm_step_clock moves
                std     tx_wt_end
tx_wt_notimed:
* ★★★ inGameTimerResetPassedCycles() [text.cpp:395]. Cleared on BOTH sides, so whatever vm_passed
* reaches inside the loop -- it can wrap past 255 on a long box -- is irrelevant to vm_pace.
                clr     vm_passed
                lda     <hal_frame_lo
                sta     tx_wt_last
tx_wt_loop:
* ── the key scan: ENTER dismisses, ESC dismisses and cancels [text.cpp:421-443] ──
* ★★ Nothing else dismisses. A build that took any key would pass an eye gate and be wrong.
                jsr     HAL_key_scan
                tsta
                beq     tx_wt_tick
                cmpa    #HAL_KEY_ENTER
                beq     tx_wt_done
                cmpa    #HAL_KEY_ESC
                bne     tx_wt_tick
* ★★★ ESC sets the cancel. **Our port has no consumer for it** -- the oracle's messageBox returns
* false and its caller acts on that; nothing here reads it yet. Recorded rather than invented
* [T-P0-085 §7.3]: the byte is set so the next task has it, and nothing depends on it today.
                lda     #1
                sta     tx_wt_key
                bra     tx_wt_done
tx_wt_tick:
* ── one pass per VBL tick: advance the game clock, then test the deadline ──
* ★★ The VBL counter is the TICK SOURCE and never the deadline. It is IRQ-driven, so it keeps
* running through the block whatever this loop does -- which is what makes it a usable edge, and
* exactly why it must not be what the timeout is measured against [see the fault arm below].
                lda     <hal_frame_lo
                cmpa    tx_wt_last
                beq     tx_wt_loop              ; same tick, nothing to service yet
                sta     tx_wt_last
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SERVICING -- vm_step_clock WHOLE [text.cpp:399's inGameTimerUpdate()]. It advances
* vm_vms, vm_passed and vars 11-14 and recomputes vm_tdelay; the oracle's loop advances the same
* set, and vm_passed's reset on both sides is text.cpp:395/409.
* ★★★★★ AC-8's FAULT ARM, AND IT IS ONE OMISSION WITH BOTH CONSEQUENCES [§2W.1]. -DTEXT_FAULT_NOTICK
* drops this call, so the loop still polls the key and still redraws nothing -- but the game clock
* stops, and because the deadline is a mark ON that clock, **var 21 can never be reached and the box
* hangs forever.** The headless arm's watchdog is then the thing under test: it must fire.
* ★★★★ A fault arm that hung by some other means (a `bra *`, a deadline that never loads) would
* prove the watchdog fires and nothing about THIS loop. This one is the defect §4A's census named.
                ifndef  TEXT_FAULT_NOTICK
                jsr     vm_step_clock
                endc
* ── the deadline ──
* ★★★ Signed difference, not `cmpd`: both sides are 16-bit counters that wrap together and the span
* between them is at most 7,650, so `now - end` stays well inside +/-32,768 and `bmi` means "the
* mark is still ahead" across the wrap. An unsigned compare would close the box early at the wrap.
                tst     tx_wt_timed
                beq     tx_wt_loop
                ldd     vm_vms+2
                subd    tx_wt_end
                bmi     tx_wt_loop              ; not yet
tx_wt_done:
* ★★★ inGameTimerResetPassedCycles() [text.cpp:409], then var 21 zeroed [text.cpp:411] -- the
* auto-close is one-shot and a game that wants another must set it again.
                clr     vm_passed
                lda     #VM_VAR_WINDOW_AUTO_CLOSE_TIMER
                clrb
                jsr     vm_setvar
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
