* src/harness/vm_pic_ops.s -- load.pic / draw.pic / show.pic / configure.screen [T-P0-121]
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THESE THREE OPCODES ARE WHY THE GAME COULD NOT ORDER ITS OWN SCREEN. Until now the
* picture was rendered by p3_room_check -- a PORT-SIDE room-change detector -- and $19/$1A/$6F
* were `vm_op_modelled`. **Nothing in the binary could put the picture and the text in the
* order the game asks for**, because the game's request was being discarded and a detector was
* guessing at it afterwards.
*
* ★★★★★ THE ORDER, MEASURED RATHER THAN ASSUMED [harness/tools/pic_order.py, KQ1 cycle 1]:
*     new.room 83 / load.pic v0=83 / configure.screen 0 21 0 / draw.pic v0=83 /
*     prevent.input / display 22 1 24 / display 24 5 25 / show.pic
* **draw.pic RENDERS and show.pic REVEALS, with the two copyright lines drawn in between.**
* The displays land at rows 22 and 24, below the 21-row picture, so show.pic never covers them.
*
* ★★★★ AND THAT IS THE DEFECT JAY SAW, FROM THE FRONT. Our render takes ~2.8 s and ran AFTER
* the logic, so the copyright appeared and the picture arrived 2.8 s later. Faithful ordering
* moves that 2.8 s IN FRONT of the text: draw.pic renders (screen unchanged), the displays draw,
* show.pic reveals. **Text and picture then arrive together, which is what the oracle does.**
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE BUFFER SPLIT IS ALREADY OURS AND THAT IS WHY THIS IS SMALL. The oracle renders into
* _gameScreen and reveals with render_Block into _displayScreen [picture.cpp:834-864]; we render
* into the SHADOW (blocks 2-5) and reveal with p3_present into the VISIBLE plane (40-43).
* **p3_room_check was already doing both halves -- in one call, at the wrong time.** This file
* splits the call; it does not invent a mechanism.
*
* ★★★★ WIRED/MODELLED EXACTLY AS vm_text_ops.s IS, AND FOR ITS REASON. gen_vm_tables.py globs
* src/harness/vm_*.s for `^vmop_\w+:` and emits `fdb vmop_draw_pic` once a LABEL exists, for
* every client of the table -- including vm_probe, which has no renderer and no framebuffer and
* could not link a real handler. The `equ` branch carries no colon, so the generator still sees
* the label, and the ALIAS resolves the table entry back to vm_op_modelled emitting zero bytes.
* ★★★★★ SO THE NINE-TITLE GATE'S BINARY IS UNCHANGED BY THIS FILE. **That is a COVERAGE fact and
* not a correctness one**: the gate stays 9/9 because it does not contain this code, and citing
* it as evidence these handlers are right would be precisely the §2W error.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                ifndef  PIC_WIRED
* ★★★ The declared no-ops. Three `equ`s, zero bytes emitted -- the state before this task, kept
* reachable so the renderer-less clients still assemble against the generated table.
vmop_draw_pic           equ     vm_op_modelled
vmop_show_pic           equ     vm_op_modelled
vmop_configure_screen   equ     vm_op_modelled
                endc

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AC-9's FAULT ARM: -DP3B_FAULT_SHOWPIC LEAVES show.pic MODELLED AND NOTHING ELSE.
* draw.pic still renders the room into the shadow; nothing ever reveals it. **The expected red
* is a screen that never shows the picture** while every byte gate that reads the SHADOW still
* passes, because the shadow is correct -- it is the reveal that is missing.
* ★★★★ THAT IS THE POINT OF CHOOSING THIS FAULT. It is the §4A.1 defect shape in miniature: a
* byte gate cannot see a plane that is right and never presented [AD-114 was exactly this, found
* by Jay watching and by no gate]. **A fault only a person can see is the honest fault for a
* change whose whole subject is what a person sees.**
* ★★★ AND IT PROVES THE OWNERSHIP CLAIM. If the picture still appears with show.pic modelled,
* something OTHER than show.pic is presenting it and §1.2's ruling is false.
                ifdef   P3B_FAULT_SHOWPIC
vmop_show_pic           equ     vm_op_modelled
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

                ifdef   PIC_WIRED
* ── the screen geometry, configure.screen's observable state ─────────────────────
* ★★★★★ THE DEFAULTS ARE THE ORACLE'S CONSTRUCTOR, NOT ZERO [text.cpp:61-63,74]: TextMgr sets
* _statusRow = 0 and _promptRow = 0 and then calls configureScreen(2). **gameRow defaults to 2,
* which puts the 168-line picture 16 pixels down** -- rows 2-22 of 25, the status line above it
* and the prompt below. A zero default would be this port's invention.
* ★★★★ KQ1's TITLE SCREEN ASKS FOR 0 (measured above), which is what we already present at, so
* the title is unaffected either way. The default matters for every room that does not ask.
p3_gamerow      fcb     2
p3_promptrow    fcb     0
p3_statusrow    fcb     0

* ── draw.pic(v) -- RENDER into the shadow. Does not reveal. ──────────────────────
* ★★★ `decodePicture(resourceNr, true)` then `pictureShown = false` [op_cmd.cpp:1178-1210]. The
* number comes from the VARIABLE named by the operand, not from the operand.
vmop_draw_pic:
                jsr     vm_v0                   ; A = the picture number
                jmp     p3_pic_draw

* ── show.pic() -- REVEAL what draw.pic rendered ──────────────────────────────────
* ★★★★★ AND CLEAR FLAG 15 [op_cmd.cpp:1215]. VM_FLAG_OUTPUT_MODE is flag 15 [agi.h:297] and it
* has exactly two engine sites: this clear, and TextMgr::messageBox, which consumes it to make
* ONE window non-blocking [text.cpp:373-375]. **Nothing in the engine ever SETS it -- the game
* does** -- so this is the interpreter taking back a request the game made and did not spend.
* ★★★★ MEASURED, NOT ASSUMED: over KQ1's first 30 cycles the one show.pic executes with flag 15
* ALREADY CLEAR, so the clear is inert there [pic_order.py §6]. That is evidence about ONE
* execution of ONE title [L-86] and is recorded as such, not as a licence to skip the write.
* ★★★★★ closeWindow() IS PORTED AS OF T-P0-122 -- see the call below. This note previously read
* "NOT ported here -- this probe has no open-window state for it to close", which was wrong on
* both halves: `txt_close` has existed since P6.19 and the text arms very much have window state.
* ★★★ Corrected rather than deleted, because the claim was cited in P6.67's report and a reader
* arriving from there needs to find it superseded rather than absent [§2D's superset discipline].
* ★★★★★ THE ORACLE'S ORDER, AND IT IS NOT THE ORDER THIS FILE SHIPPED AT P6.67 [op_cmd.cpp:1215-
* 1218]: setFlag, THEN closeWindow, THEN the reveal. P6.67 revealed first and cleared the flag
* afterwards, which is observationally the same only while no window is open -- **and closing a
* window AFTER presenting would repaint the restore rectangle over the picture just revealed.**
                ifndef  P3B_FAULT_SHOWPIC
vmop_show_pic:
                lda     #15                     ; VM_FLAG_OUTPUT_MODE
                clrb                            ; B = 0 -> clear
                jsr     vm_setflag
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ closeWindow() IS NOW PORTED, AND THIS FILE'S OWN NOTE SAYING IT IS NOT WAS THE THING TO
* CORRECT [T-P0-122 §1.3]. `txt_close` has been in the engine since P6.19 [text.s:1024, from
* text.cpp:549]; what was missing was the CALL, not the routine.
* ★★★★ IT IS SAFE WHEN NO BOX IS UP, BY THE ORACLE'S OWN GUARD: `if (_messageState.window_Active)`
* [text.cpp:550] is `tst txt_winactive / beq tc_out` [text.s:1030-1031], so a show.pic with no
* window open falls straight through. **The guard is the oracle's, not one this port invented.**
* ★★★ TEXT_WIRED, NOT P3B_TEXT_LINK, AND THE DIFFERENCE IS LOAD-BEARING. tx_window_enter lives in
* vm_text_ops.s's WIRED branch [ifndef TEXT_WIRED at :24, else at :40]; -DTEXT_MODELLED links
* text.s and leaves TEXT_WIRED undefined, so guarding on "text.s is linked" would name a symbol
* that does not exist in the fault arm. **The condition must be the one that DEFINES the symbol**
* [P6.66's rule, and the third time this file's family has had to apply it].
* ★★ The window must be entered: txt_close's restore writes the framebuffer through txt_restore,
* and every other caller in this file brackets its text work the same way.
                ifdef   TEXT_WIRED
                ifndef  P3B_FAULT_NOCLOSEWIN
                jsr     tx_window_enter
                jsr     txt_close
                jsr     tx_window_exit
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                jmp     p3_pic_show
                endc

* ── configure.screen(n,n,n) -- gameRow, promptRow, statusRow ─────────────────────
* ★★★ `configureScreen(gameRow)` sets _window_Row_Min/_Max AND forwards gameRow*8 to the
* renderer as a start offset [text.cpp:92-98]; statusRow_Set and promptRow_Set take the other
* two [op_cmd.cpp:1833-1845]. The operands are LITERALS ("nnn"), not variable numbers.
* ★★★★★ THE THREE BYTES ARE STORED AND THE RENDER OFFSET IS NOT YET CONSUMED, deliberately and
* reported: p3_present copies slice-for-slice, source offset == destination offset, and a
* gameRow shift breaks that alignment (dest byte = k*8192 + gameRow*1280 crosses a block the
* source does not). **That is a rewrite of p3_present with its own eye gate, not a line here.**
* ★★ It costs nothing today -- the measured title screen asks for gameRow 0, which is the offset
* p3_present already uses -- and the debt is visible rather than assumed away.
vmop_configure_screen:
                jsr     vm_p0
                sta     p3_gamerow
                jsr     vm_p1
                sta     p3_promptrow
                jsr     vm_p2
                sta     p3_statusrow
                rts
                endc
