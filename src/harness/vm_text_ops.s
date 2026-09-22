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
* ★★★ $77/$78 ARE INPUT OPCODES, NOT TEXT ONES, AND THEY LIVE HERE ANYWAY [T-P0-092]. This file is
* the one every probe includes and it is where AD-176's rule bites: once vm_tables.s names a label
* it must resolve in EVERY build, wired or not. A second file with the same two-branch shape would
* be a second place to get that wrong.
vmop_accept_input       equ     vm_op_modelled
vmop_prevent_input      equ     vm_op_modelled
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
* ★★★★★ HAZARD 1 -- THE ARENA IS BORROWED WHOLE, AND THE ISOLATION IS NOW A REQUIREMENT [T-P0-093].
* MAP_ARENA_WIN is $6000-$A000, slots 3 AND 4, and the largest corpus LOGIC is 10,964 B, so a
* resource at the arena base reaches $8AD4. **The message text is bytes of that resource.**
* ★★★★★ THIS PARAGRAPH USED TO END "that is luck, and it is recorded as luck rather than as
* design." It is not luck any more. The window borrowed slot 4 only; it now borrows slot 3 as
* well, so the arena is COMPLETELY unmapped for the whole blit -- **a blit that read the message
* from txt_msgp would read framebuffer bytes, with no partial case left to be lucky about.**
* ★★★★ THE REQUIREMENT, STATED AS ONE: substitution runs FIRST, with the arena mapped, and writes
* txt_pbuf in MAP_INPUT ($1C00) -- slot 0, resident in every phase. The blit then reads txt_pbuf,
* the font at $E3BA (slot 7) and text.s's own state (slot 2), and nothing else. Measured, not
* assumed [T-P0-093 §4A].
*
* ★★★★★ HAZARD 2 IS SETTLED AND THE SETTLEMENT IS IN mmu_phase.s. The registers are write-only, so
* there is no save; restoration is by KNOWN VALUE, and those values now live in ph_blk_slot3/4/5
* beside the routine that writes them. **This file no longer writes an MMU register at all** --
* which is what the old note here asked for and declined to do:
*     "$FFA4 HAS NO SANCTIONED OWNER: mmu_phase.s manages slots 5 and 6 only. This file becomes
*      the second writer of the MMU register file, which is a §2N ownership question and is
*      reported rather than settled here."
* ★★★ Kept quoted rather than deleted: the question stood for six tasks and the answer is only
* legible beside it.
* ★★★★ AND THE CENSUS CANNOT SEE THIS FILE. reg_discipline.py scans src/engine, so these five
* writes were never counted -- the ownership claim needed a WHOLE-TREE grep to be checkable, and
* that grep is §3(3) of T-P0-093's report.
TX_WIN          equ     $6000           ; slots 3-6, flat
* ★★★★ 25 ROWS, AND THE ARITHMETIC RATHER THAN A CONSTANT: $6000-$DFFF is 32,768 B; a character
* row is 8 * 160 = 1,280 B; the last byte of row 24 is (24*8+7)*160 + 159 = 31,999 < 32,768, and
* row 25 would end at 33,279 and overrun into slot 7's parser. **Rows 0-24, which is TXT_ROWS.**
TX_WIN_ROWS     equ     25
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FAULT ARM IS THE ROW BOUND, NOT THE SLOT COUNT, AND THE CHANGE IS DELIBERATE [§2W].
* The dispatch asked for "map THREE slots instead of four". **Mapping three from here would put an
* MMU write back in this file**, which is the one thing this task exists to remove -- the fault arm
* would have quietly re-created the defect the clean arm just fixed, and AC-2 would be true of one
* build and false of another.
* ★★★★ -DTEXT_WIN3 CHANGES ONE CONSTANT: the row count text.s is told the window holds. txt_blit
* refuses `crow >= txt_fbrows` and tx_boxfill's yhi is fbrows*8, so 19 reproduces P6.37's geometry
* exactly -- rows 0-18 drawable, the prompt at row 22 refused, **and nothing else different
* anywhere.** The box still draws, the parse still fires, the run still completes.
* ★★★ THAT IS A STRICTLY BETTER FAULT [L-73]: one variable rather than two, and it isolates the
* thing actually under test -- the BOUND -- from the mapping, which is now somebody else's file.
                ifdef   TEXT_WIN3
TX_WIN_ROWS_EFF equ     19
                else
TX_WIN_ROWS_EFF equ     TX_WIN_ROWS
                endc

* ── tx_window_enter -- the text phase: four visible-plane blocks flat, $6000-$DFFF ──
* ★★ The MAPPING is mmu_phase.s's; what stays here is the text engine's view of it -- the base,
* the first row and how many rows it holds, which are text.s's parameters and not the MMU's.
tx_window_enter:
                jsr     phase_text_in
                ldx     #TX_WIN
                stx     txt_fbwin
                clr     txt_fbrow0
                lda     #TX_WIN_ROWS_EFF
                sta     txt_fbrows
                rts

* ── tx_window_exit -- put the VM phase back ──────────────────────────────────────
* ★★ res_core caches which block it believes is in slot 6 and SKIPS the write when it matches, so
* after anyone else moves that register the cache has to be invalidated or the next fetch reads
* the wrong block while being certain it is right [p3b_probe.s's own note at the cycle body].
tx_window_exit:
                jsr     phase_text_out
                lda     #$FF
                sta     res_curblk
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
tx_wt_nwait     fcb     0               ; times the blocking wait was ENTERED this run

tx_wait_dismiss:
* ★★★ HOW MANY TIMES THE BOX WAS PUT UP. Jay: "it also seems like my first enter press is being
* eaten." Two explanations fit that and they need opposite fixes -- print running TWICE (so the
* first ENTER dismissed a first box the eye read as the same one), or ONE box whose key scan
* misses the first press. **A counter separates them; reasoning about it cannot** [§2W].
                inc     tx_wt_nwait
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE FOURTH SCANNER, AND T-P0-128's DISPATCH DID NOT LIST IT. p3_key_latch, p3_poll_key and
* p3_poll_dir were named; this blocking wait spins on the matrix while a print box is up, and in
* the VBL arm that would make TWO owners of the PIA's column register for exactly as long as a box
* is on screen -- **the hazard that fails intermittently rather than always**, when the interrupt
* lands mid-scan. Found by grepping every caller rather than trusting the list [§2H check 3].
* ★★★★ So it DRAINS the VBL queue there. Edges, not levels: one ENTER press dismisses once, which
* is the oracle's KEYDOWN-only delivery [keyboard.cpp:333-334]; any other key is drained and
* ignored, as it is for dismissal in text.cpp:421-443.
* ★★★ UNGATED IN THIS ARM: p3b_box is a P3B_NO_CEL row and exercises the scan branch below, not
* this one. Stated rather than implied.
                ifdef   P3B_VBL_KEYS
                jsr     p3_kq_get
                else
* ★★★★★ AN EDGE HERE TOO [T-P0-131]. A level scan dismissed a box the instant it opened if ENTER
* was still down -- the ENTER that submitted the line, or the one that closed the previous box --
* which is the text-side twin of the arrow defect. p3_key_event shares p3_klast with the cycle's
* dispatcher, so an ENTER already counted there is not counted again here: the box waits for a
* NEW press, as the oracle's KEYDOWN-only delivery does [keyboard.cpp:333-334].
                jsr     p3_key_event
                endc
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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ accept.input / prevent.input, REAL [op_cmd.cpp:1980-1997, T-P0-092].
* ★★★★ THEY ARE TWO LINES EACH IN THE ORACLE AND THE SECOND LINE IS THE ONE THAT MATTERS:
*     accept.input   promptEnable();  promptRedraw();                       [:1985-1986]
*     prevent.input  promptDisable(); inputEditOn(); clearLine(row, 0);     [:1994-1997]
* **prevent.input CLEARS THE ROW.** A port that only dropped the flag would leave the last typed
* line on screen with nothing able to edit it, and every byte gate would agree it was fine.
* ★★★ Behind TEXT_PROMPT, so a wired build without the command line keeps the modelled behaviour
* rather than failing to assemble on txt_prompt_on.
                ifdef   TEXT_PROMPT
vmop_accept_input:
                jmp     txt_prompt_on
vmop_prevent_input:
                jmp     txt_prompt_off
                else
vmop_accept_input       equ     vm_op_modelled
vmop_prevent_input      equ     vm_op_modelled
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THIS STUB IS NOW KNOWN TO BE VISIBLE, AND JAY SAW IT [T-P0-124's eye gate]. Once the
* title screen advances, the script issues clear.lines EXACTLY ONCE -- it is the opcode that
* removes the title's text -- and this `rts` means it never happens. **Jay, pressing a key at the
* title screen: "the press a key to continue stays on the title screen and transfers to the
* castle screen."** The line survives the room change because the text area is outside the
* picture that draw.pic/show.pic replace, so nothing else overwrites it either.
* ★★★★ AND THE MEASUREMENT I QUOTED DID NOT SAY WHAT I SAID IT SAID: the text area went 715 ->
* 266 non-black bytes across the advance, and I read a CHANGE as a CLEAR and told Jay to expect
* the text to go. 266 is not zero. **A number that moved in the right direction is not evidence
* that it reached the right value** [§2W.3].
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ IMPLEMENTED [T-P0-125]. $4E clear.lines(upper, lower, colour) -- op_cmd.cpp:2181,
* text.cpp:635-653:
*
*     rowUpper = p[0]; rowLower = p[1]; colour = calculateTextBackground(p[2]);
*     if (rowUpper > rowLower) rowLower = rowUpper;          // a guard for buggy games
*     clearLines -> clearBlock(upper, 0, lower, FONT_COLUMN_CHARACTERS-1, colour)
*                -> clip; translateFontRectToDisplayScreen; drawDisplayRect(...)
*
* ★★★★★ IT WRITES THE DISPLAY SCREEN, NOT THE GAME SCREEN, so it never touches the picture --
* §6's "would it have to touch the picture area" answered from the oracle before any code.
* ★★★★ ONE ROW AT A TIME THROUGH txt_clearline, WHICH ALREADY WAS THIS OPCODE'S INNER LOOP:
* text.s:1135 says so in as many words -- *"clearBlock(row, 0, row, 39, colour) in the oracle...
* this is one tx_boxfill"*. **clear.lines is that routine, upper through lower**, and nothing new
* was needed in text.s.
* ★★★ THE COLOUR RULE IS THE ORACLE'S, NOT "the argument": calculateTextBackground returns 15
* only when gfxMode AND the argument is non-zero, else 0 [text.cpp]. **KQ1 calls
* clear.lines(21, 24, 0)** -- measured -- so the title's clear is BLACK over rows 21-24, exactly
* the strip p3_black_visible establishes and p3_present stops short of [P6.62].
TX_CL_ROWS      equ     4               ; ★ state, not registers: txt_clearline clobbers A and B
tx_cl_row       fcb     0               ; the row being cleared, walked upper -> lower
tx_cl_last      fcb     0               ; the bounded lower row
tx_cl_col       fcb     0               ; the computed background colour
tx_cl_save      fcb     0               ; txt_bg, restored after
                ifndef  P3B_FAULT_NOCLEARLINES
vmop_clear_lines:
                jsr     vm_p0
                sta     tx_cl_row
                jsr     vm_p1
                cmpa    tx_cl_row
                bhs     vcl_bounded
                lda     tx_cl_row               ; upper > lower -> lower = upper [op_cmd.cpp:2189]
vcl_bounded:    sta     tx_cl_last
* ---- calculateTextBackground(p[2]) ----
                jsr     vm_p2
                tsta
                beq     vcl_black
                tst     vm_gfxmode
                beq     vcl_black
                lda     #15
                bra     vcl_setbg
vcl_black:      clra
vcl_setbg:      sta     tx_cl_col
* ★★★ txt_clearline takes its colour from txt_bg and the oracle passes one explicitly, so the
* attribute is set for the fill and PUT BACK: clear.lines must not change what the next glyph
* draws on [AD-160's shape -- an attribute left behind drew twelve glyphs black on black].
                lda     txt_bg
                sta     tx_cl_save
                lda     tx_cl_col
                sta     txt_bg
                jsr     tx_window_enter
vcl_lp:         lda     tx_cl_row
                cmpa    tx_cl_last
                bhi     vcl_done
                jsr     txt_clearline
                inc     tx_cl_row
                bra     vcl_lp
vcl_done:       jsr     tx_window_exit
                lda     tx_cl_save
                sta     txt_bg
                rts
                endc
* ★★★★★ AC-9's FAULT ARM: -DP3B_FAULT_NOCLEARLINES puts the bare `rts` back. It is today's
* behaviour and a KNOWN-GOOD RED in Jay's own words, quoted above.
                ifdef   P3B_FAULT_NOCLEARLINES
vmop_clear_lines:
                rts
                endc
* ★★★★★ STILL A STUB, AND NOW WITH THE EVIDENCE RATHER THAN THE INTENTION [T-P0-092 §4A(4)].
* _inputCursorChar is 0 at text.cpp:58 and **inputEditOn and inputEditOff are both no-ops while it
* is zero** [text.cpp:673, :682]. So the command line renders completely without this opcode: there
* is no cursor glyph until a game sets one, and no title this probe runs does.
* ★★★ AND THE ARGUMENT IS A MESSAGE NUMBER, NOT A CHARACTER [op_cmd.cpp:2106-2112] -- it indexes
* _curLogic->texts[] and passes the FIRST CHARACTER. The opcode's name invites the other reading,
* which is why this is written down beside the stub rather than in a report nobody rereads.
vmop_set_cursor_char:
                rts
vmop_set_text_attribute:
                rts
vmop_status_line_on:
                rts
vmop_status_line_off:
                rts
                endc
