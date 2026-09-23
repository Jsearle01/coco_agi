* src/harness/composite.s -- the sprite composite: transparency, the priority test, save-under.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE DISPATCH'S INNER LOOP IS NOT THE ORACLE'S, AND THE DIFFERENCE IS THREE MECHANISMS.
*
* T-P0-028 §2 states the loop as: "if source != 0 and sprite priority >= priority[x>>1], write."
* The pinned oracle's SpritesMgr::drawCel (sprite.cpp:233) is:
*
*     if (curColor != celClearKey) {                       // ★ the CEL'S clear key, not 0
*         screenPriority = getPriority(curX, curY);
*         if (screenPriority <= 2) {                       // ★★★ CONTROL DATA -- a third branch
*             if (checkControlPixel(curX, curY, viewPriority))
*                 putPixel(VISUAL only, curColor, 0);      // ★ priority plane UNTOUCHED
*         } else if (screenPriority <= viewPriority) {
*             putPixel(ALL, curColor, viewPriority);       // ★ writes BOTH planes
*         }
*     }
*
* ★★ 1. PRIORITY VALUES 0-2 ARE NOT DEPTH, THEY ARE CONTROL LINES. checkControlPixel walks
*    DOWN the column from the pixel until it finds a priority > 2, and compares THAT. A pixel
*    over a control line therefore costs a loop of up to 168 iterations, which the two-test
*    model does not account for at all. Counted separately below, because AC-5 asks for the
*    cost and a mean that hides a per-pixel column scan is not the cost.
* ★★ 2. THE SPRITE WRITES THE PRIORITY SCREEN. Branch three stamps viewPriority into the
*    priority plane. So compositing MUTATES its own input, and save-under must restore BOTH
*    planes -- which is why the oracle's backing store is `xSize * ySize * 2` (sprite.cpp:131).
*    ★★★ P5.1's cost model reported "peak TOTAL cel area 4,152 B -- the save-under bound"; the
*    real bound is TWICE that, because one plane is half the state a sprite disturbs.
* ★ 3. yPos IS THE LOWER-LEFT CORNER: `curY = curY - celPtr->height + 1`. Taking it as upper
*    left puts every sprite one cel-height too low.
*
* ★★ AND THE LOOKUP IS `x`, NOT `x >> 1`. getPriority is `_priorityScreen[y * 160 + x]`. The
* design's `x >> 1` is the CoCo3 mapping from a 320-wide VISUAL plane to a 160-wide priority
* screen; the oracle composites in 160-wide space where the two already agree. This harness
* composites in the oracle's space so the gate can be byte-identical, so it uses `x`. **The
* shift is a property of the shipped framebuffer, not of the algorithm.**
* ═══════════════════════════════════════════════════════════════════════════════════════════

CO_CTRL_MAX     equ     2               ; priority <= 2 is control data, not depth

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ -DPRI_PACKED: THE PRIORITY PLANE AT 4 BITS PER PIXEL. THIS IS NOT AN OPTIMISATION.
* memmap.inc has specified 13,440 B since P6.1 and every subsystem wrote 26,880. P3b measured
* the draw phase at **72,194 bytes against 65,280 available** -- and packing saves exactly
* 13,440, which is the whole of the 6,914-byte overrun and 6,526 to spare. **Without it nothing
* integrates** [L-64: P6.1 recorded this as a divergence with a cost, which concealed that it
* was a requirement].
*
* ★★ AGI priority values are 0-15, so four bits are lossless. The plane becomes 80 x 168.
*
* ★★★ THE NIBBLE CONVENTION, STATED ONCE AND USED EVERYWHERE:
*     byte index = (y * 160 + x) >> 1  =  y * 80 + (x >> 1)
*     EVEN x -> HIGH nibble          ODD x -> LOW nibble
* ★ Left-to-right raster order, so a hex dump reads in pixel order. Six sites depend on it:
* co_rowset, co_rownext, co_opaque's read, co_depth's stamp, co_checkctrl's walk, and
* put_pixel in pic_core.s. **A convention disagreement between any two of them is a silent
* half-pixel shift**, which is why it is written here and referenced rather than re-derived.
*
* ★★ THE COST IS A NIBBLE EXTRACT ON READ AND A READ-MODIFY-WRITE ON WRITE. P5.4 measured the
* priority test at 2.7% of composite cost against the transparency test's 70.9%, so this lands
* on the cheap path -- but that was an inference and AC-4/AC-7 measure it rather than assume.
                ifdef   PRI_PACKED
PRI_STRIDE      equ     PRI_W/2         ; 80 bytes per row
                else
PRI_STRIDE      equ     PRI_W           ; 160 -- one byte per pixel, the gate's shape
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ★★★★★ UNDER -DPLANE_WINDOWED THESE TWO ARE FLAT OFFSETS, NOT ADDRESSES [T-P0-107].
co_rowvis       fdb     0               ; -> visual row base for curY   (offset if windowed)
co_rowpri       fdb     0               ; -> priority row base for curY (offset if windowed)
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ COMP_PLANE_SAFE -- THE SYMBOL A PROBE ASSERTS ON, AND IT EXISTS BECAUSE THE LAST GUARD
* OF THIS KIND WAS A SENTENCE IN A COMMENT [T-P0-107 §4C].
* memmap.inc exempts the windowed configuration from its plane-overflow assertion on the grounds
* that "PLANE_WINDOWED reaches every byte through plane_vis/plane_pri, which mask the offset".
* **That was prose, it quantified over every subsystem, and it was false for this one for the
* whole life of the file.** A symbol a probe can assert on is the version that cannot decay.
* ★★★ -DCOMP_FAULT_FLAT_PLANE suppresses it, so the assertion can be shown RED [§2W].
                ifdef   PLANE_WINDOWED
                ifndef  COMP_FAULT_FLAT_PLANE
COMP_PLANE_SAFE equ     1
                endc
                endc
* ★★★★★ AND THE SAME PATTERN IN THE OTHER DIRECTION [T-P0-135]. memmap.inc's reach assertion is
* now scoped to builds that address a plane, and a build opts out by defining PLANE_ABSENT. **That
* claim is checked here rather than trusted**: this file composites into both planes, so a build
* that links it and claims to have none is wrong, and says so at assembly time.
                ifdef   PLANE_ABSENT
                error   "composite.s addresses both planes -- PLANE_ABSENT is false in this build"
                endc
co_src          fdb     0               ; -> next cel pixel
co_remh         fcb     0
co_remw         fcb     0
co_curx         fcb     0
co_basex        fcb     0
co_cury         fdb     0               ; ★ 16-bit: yPos - height + 1 can go NEGATIVE
co_prio         fcb     0
co_key          fcb     0
co_col          fcb     0
co_tmp          fdb     0
* ★★★ co_prix -- the priority byte's address, formed at site 1 and reused at site 2 [T-P0-140].
* Windowed only: the flat build re-forms it with a `leax d,x` that costs nothing to repeat.
                ifdef   PLANE_WINDOWED
co_prix         fdb     0
                endc
co_ctrly        fdb     0               ; checkControlPixel's walking row
co_ctrloff      fdb     0

* ★ AC-5 counters. 32-bit: a 500-frame run at ~900 tested pixels per composite passes 65,535
* in the first second, and a 16-bit counter would wrap silently into a plausible figure.
co_tested       rmb     4
co_written      rmb     4
co_rejkey       rmb     4
co_rejpri       rmb     4
co_ctrlhit      rmb     4               ; ★ pixels that took the CONTROL branch
co_ctrlstep     rmb     4               ; ★ total column-scan iterations those cost

* ═══════════════════════════════════════════════════════════════════════════════════
* ── cp_composite ── draw the decoded cel at (CP_X, CP_Y) with priority CP_PRIO ────
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHAT THE DRAWING PATH COSTS, SO THE NEXT READER NEED NOT RE-MEASURE IT [T-P0-140 §4A].
* Window: KQ1 room 1, steady cycles 11-120, four staged sprites, **3.2 cels composited per cycle**.
* The whole draw stage (P3_PHASE=9: restore + decode + blit) is **65.5% of a 0.279 s cycle =
* 0.191 s**, decomposing to 100.0%:
*     compositor 35.0%  ·  cel decode 27.6%  ·  plane window access 18.6%
*     restore walk 8.5% ·  resource manager 8.2%  ·  MMU phase 1.8%
* ★★★★ PER CEL: ~60 ms all in -- ~21 ms to blit and ~16 ms to decode.
* ★★★★ PER PIXEL: 630 tested and 284 written per cycle, so **~106 us per pixel TESTED** (~190 CPU
* cycles at 1.79 MHz). That is the number a pixel-loop ruling starts from, not the total.
* ★★★ THE TWO CORE LOOPS ARE 55% OF THE STAGE -- cp_composite 28.9%, vc_decode_row 26.6% -- and
* inside each the cost is spread across its own internals. **Structural, not a defect** [§4B].
* ★★ The castle's sprite load is FOUR objects with two sharing a view; a room with more objects
* composites more, and this figure is one room of one title.
* ═══════════════════════════════════════════════════════════════════════════════════
cp_composite:
                lda     CP_X
                sta     co_basex
                lda     CP_PRIO
                sta     co_prio
                lda     vc_key
                sta     co_key
                lda     vc_h
                sta     co_remh
                ldd     #CP_CEL
                std     co_src

* curY = yPos - height + 1   ★ yPos is the LOWER-left corner (sprite.cpp:247)
                clra
                ldb     CP_Y
                pshs    d
                clra
                ldb     vc_h
                pshs    d
                ldd     2,s
                subd    ,s++
                leas    2,s
                addd    #1
                std     co_cury

* row bases for curY. ★ Kept as running pointers and advanced by 160 per row rather than
* recomputed as y*160: the multiply is 16-bit and the add is not, and this is the inner loop.
                ldd     co_cury
                jsr     co_rowset

                ldd     CP_BLITS
                addd    #1
                std     CP_BLITS

co_row:
                lda     co_remh
                lbeq    co_done
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DCOMP_ROW_PULL: THE COMPOSITOR DRIVES THE DECODER, ONE ROW AT A TIME [T-P0-105].
*
* ★★★★★ PULL AND NOT PUSH, AND THE REASON IS IN THIS LOOP. co_src is a running pointer that only
* ever moves FORWARD, one byte at a time, in row-major order, and **nothing re-reads a row it has
* passed** -- co_save/co_restore walk the SCREEN, not the cel. So the cel is consumed exactly once
* in exactly the order the decoder produces it, and the interface was already row-shaped.
* ★★★★ PUSH would have inverted THIS routine -- the more heavily gated of the two, and the one
* holding the transparency test, the priority test and the control-line walk. **Pull moves one
* pointer assignment; push would have moved three decisions into the decoder.**
* ★★★ The oracle is no guide here: it allocates the whole bitmap and composites later, which is
* the shape being left behind. **This is a port decision, stated as one** [§2.1].
* ★★ Guarded because comp_probe composites a cel the HOST staged, with no decoder linked at all.
                ifdef   COMP_ROW_PULL
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE CEL CACHE'S ROW HOOK [T-P0-147]. cc_open ran ONCE for this cel in p3_composite_all
* and left cc_state; this loop only acts on it. ★★★★ Three states, and the third is today's code
* unchanged, which is what makes the degradation real rather than promised:
*   CC_HIT    the rows are already decoded in slot 4 -- co_src points at them, NO DECODE AT ALL
*   CC_FILL   decode as usual, then COPY the row into the cache so the next cycle hits
*   CC_BYPASS decode as usual and touch nothing -- byte-for-byte the pre-task path
* ★★★★★ A CACHED ROW MUST EQUAL A DECODED ONE [AC-1]: CC_FILL copies the bytes vc_decode_row just
* produced, so the cache cannot hold anything the decoder would not have produced. **The planes are
* compared over 120 cycles in both scenes rather than argued about.**
* ★★★ vc_w bytes per row, not 256: CP_CEL is a 256-byte buffer but only the cel's width is live.
                ifdef   CEL_CACHE
                lda     cc_state
                cmpa    #CC_HIT
                bne     co_rp_decode
                ldd     cc_ptr                  ; ★ rows are contiguous in the cache
                std     co_src
                clra
                ldb     vc_w
                addd    cc_ptr
                std     cc_ptr
                bra     co_rp_done
co_rp_decode:
                endc
                jsr     vc_decode_row
                lda     vc_err
                lbne    co_done                 ; ★ a mid-cel error stops the blit, as before
                ldd     vc_dest
                std     co_src
                ifdef   CEL_CACHE
                lda     cc_state
                cmpa    #CC_FILL
                bne     co_rp_done
                pshs    x,u
                ldx     vc_dest                 ; source: the row just decoded
                ldu     cc_ptr                  ; destination: the cache
                ldb     vc_w
                beq     co_rp_cpdone
co_rp_cp:       lda     ,x+
                sta     ,u+
                decb
                bne     co_rp_cp
co_rp_cpdone:
                stu     cc_ptr
                puls    x,u
co_rp_done:
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                lda     co_basex
                sta     co_curx
                lda     vc_w
                sta     co_remw

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHAT SHAPE THE DATA IS, SO THE NEXT READER NEED NOT RE-MEASURE IT [T-P0-142 §4A].
* This loop tests transparency, reads screen priority and writes two planes ONCE PER PIXEL. Every
* pixel inside one RLE run shares a colour, so a per-run fast path is the obvious idea -- and the
* census says the runs are too short to pay for it.
*     castle cels (view 0/97/107): KEY 58.0% of pixels, mean run 3.47
*                                  OPAQUE 42.0%, **mean run 1.84**, 80 of 152 runs are ONE pixel
*                                  opaque pixels in runs >= 4: 20.8%
*     corpus, 8,682 cels:          KEY 58.9%, mean 4.21 | OPAQUE 41.1%, **mean 2.17**
*                                  349,915 of 613,176 opaque runs are ONE pixel; >= 4: 41.8%
* ★★★★★ AND THE RUNS ARE NOT AVAILABLE HERE ANYWAY. co_src walks a PER-PIXEL row buffer that
* vc_decode_row has already expanded, so this loop cannot see a run without comparing bytes --
* **and that comparison is the per-pixel look a run-skip would exist to avoid.** Carrying runs
* across from the decoder is option 3 (fusing decode and blit), which T-P0-141 §1.4 objects to
* because `cel` gates 9,193 cels by comparing DECODED CEL BYTES.
* ★★★ PRICED [T-P0-142 §4A, stage-9 labels, moving]: co_pix is 9.2% of the drawing stage and the
* whole opaque path ~28%. With opaque runs at 1.84 the recoverable share is ~3-5% of a cycle,
* against a change to code two byte-comparable gates own. **Measured and not taken.**
* ═══════════════════════════════════════════════════════════════════════════════════════════
co_pix:
                lda     co_remw
                lbeq    co_rownext

                ldx     co_src
                lda     ,x+
                stx     co_src
                sta     co_col
                ifndef  COMP_NOCOUNT
                ldu     #co_tested
                jsr     co_inc32
                endc

                cmpa    co_key
                bne     co_opaque
                ifndef  COMP_NOCOUNT
                ldu     #co_rejkey
                jsr     co_inc32
                endc
                bra     co_nextx

co_opaque:
* screenPriority = priority[row + curX]
* ★★ SITE 1 of 4. The `ifndef` around the ldx and the `ifdef` around the leax keep the FLAT build's
* instruction order byte-for-byte; the windowed build forms a flat offset and maps it instead.
                ifndef  PLANE_WINDOWED
                ldx     co_rowpri
                endc
                clra
                ldb     co_curx
                ifdef   PRI_PACKED
* ★ byte = row + (x >> 1); EVEN x -> high nibble, ODD x -> low. See the convention block.
                lsrb                            ; A is 0, so D = x >> 1
                ifdef   PLANE_WINDOWED
                addd    co_rowpri
                jsr     plane_pri               ; X = address, slice mapped
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ KEEP IT: SITE 2 WANTS THIS EXACT ADDRESS AND USED TO RE-DERIVE IT [T-P0-140].
* A drawn pixel calls plane_pri TWICE -- here to READ screenPriority for the depth test, and at
* site 2 to WRITE the priority back -- from the same `co_rowpri + (co_curx >> 1)`. **The inputs
* are identical and nothing between them changes either one.**
* ★★★★★ AND THE MAPPING SURVIVES, WHICH IS WHY THE ADDRESS CAN BE REUSED RATHER THAN JUST THE
* ARITHMETIC SKIPPED. Between the two calls sits only `cmpa co_prio` and `jsr co_put_visual`, and
* co_put_visual touches co_rowvis and plane_vis -- **slot 6**. plane_pri maps **slot 5**
* [plane_win.s: "plane_pri is not even the same REGISTER"], and since T-P0-135 the two have
* separate records, ph_cur6 and ph_cur5. So slot 5 still holds this slice when site 2 runs.
* ★★★★ MEASURED: co_rej_pri is ZERO in the castle -- every opaque pixel is drawn -- so **exactly
* half of all plane_pri calls were this re-derivation**: 11,360 of 22,720 over 40 cycles, with
* plane_pri at 11.5% of the drawing stage [T-P0-140 §4A].
* ★★★ THE CONTROL-DATA PATH DOES NOT REACH SITE 2 (it draws and takes co_nextx), so the `stx`
* there is spent and not recovered -- 5 cycles against a ~40-cycle call saved on every pixel that
* does reach it.
* ★★ WINDOWED ONLY, deliberately: the flat build's site 2 is a `leax d,x` that costs nothing to
* repeat, and this file's own rule is that the flat build's instruction order stays byte-for-byte
* [site 1's header]. **comp_probe is the flat build and is the `comp` gate.**
                stx     co_prix
                endc
                ifndef  PLANE_WINDOWED
                leax    d,x
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                lda     ,x
                ldb     co_curx
                bitb    #1
                bne     co_op_lo
                lsra
                lsra
                lsra
                lsra
                bra     co_op_got
co_op_lo:       anda    #$0F
co_op_got:
                else
                ifdef   PLANE_WINDOWED
                addd    co_rowpri
                jsr     plane_pri
                else
                leax    d,x
                endc
                lda     ,x                      ; A = screenPriority
                endc
                cmpa    #CO_CTRL_MAX
                bhi     co_depth                ; > 2: ordinary depth comparison

* ---- CONTROL DATA: walk DOWN the column for the first real priority ---------------
                ifndef  COMP_NOCOUNT
                ldu     #co_ctrlhit
                jsr     co_inc32
                endc
                jsr     co_checkctrl            ; A = 1 draw, 0 skip
                tsta
                beq     co_reject_pri
                jsr     co_put_visual           ; ★ VISUAL ONLY -- priority stays as it was
                bra     co_nextx

* ---- depth: draw only where the sprite is at least as near as the screen ---------
co_depth:
                cmpa    co_prio
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ AC-4's INJECTED FAULT, behind -DCOMP_FAULT, and it is ONE BOUNDARY.
* The oracle draws when `screenPriority <= viewPriority`; the faulted build draws only when
* strictly less, so pixels at EQUAL priority stop being drawn. Nothing halts, no plane changes
* size, and a sprite in open ground is unaffected -- it changes only where a sprite meets
* scenery at its own depth, which is exactly the interaction the priority test exists for.
* ★★ The failure is PREDICTED before it is run: comp_fault_predict.py counts the equal-priority
* pixels in each staged frame and names the first differing row and column. A gate that fails
* somewhere is weaker evidence than a gate that fails where the model said it would [L-27].
                ifdef   COMP_FAULT
                bhs     co_reject_pri           ; ★ INJECTED: `bhi` in the correct build
                else
                bhi     co_reject_pri           ; screenPriority > viewPriority: behind
                endc
                jsr     co_put_visual
* ★★ SITE 2 of 4 -- the priority WRITE.
                ifndef  PLANE_WINDOWED
                ldx     co_rowpri
                endc
                clra
                ldb     co_curx
                ifdef   PRI_PACKED
* ★★ THE READ-MODIFY-WRITE. Packing makes a plane store into a load, a mask, an or and a store
* -- this is the write half of the packing cost, and AC-7 measures it rather than assuming it.
                lsrb
                ifdef   PLANE_WINDOWED
* ★★★★★ SITE 1's ADDRESS, NOT A SECOND DERIVATION [T-P0-140]. See the block at site 1 for why it
* is still valid: co_put_visual maps slot 6 and this is slot 5. ★★★ -DCOMP_PRIX_REDERIVE is the
* before arm -- it puts the second plane_pri call back and changes nothing else.
                ifdef   COMP_PRIX_REDERIVE
                addd    co_rowpri
                jsr     plane_pri
                else
                ldx     co_prix
                endc
                else
                leax    d,x
                endc
* ★★ Same ordering trap as put_pixel: load first, THEN test parity on B, or the `bne` reads the
* flags `lda ,x` just set.
                lda     ,x
                ldb     co_curx
                bitb    #1
                bne     co_st_lo
                anda    #$0F                    ; even x: keep the ODD pixel, replace the high
                ldb     co_prio
                ifdef   COMP_PRI_FAULT
                eorb    #1                      ; ★ INJECTED: adjacent band (see co_pri_fault)
                endc
                aslb
                aslb
                aslb
                aslb
                pshs    b
                ora     ,s+
                bra     co_st_put
co_st_lo:       anda    #$F0                    ; odd x: keep the EVEN pixel, replace the low
                ifdef   COMP_PRI_FAULT
                ldb     co_prio
                eorb    #1                      ; ★ INJECTED: adjacent band
                pshs    b
                ora     ,s+
                else
                ora     co_prio
                endc
co_st_put:      sta     ,x
                else
                ifdef   PLANE_WINDOWED
                addd    co_rowpri
                jsr     plane_pri
                else
                leax    d,x
                endc
                lda     co_prio
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★★★ co_pri_fault — AC-3's INJECTED FAULT, AND IT PERTURBS THE VALUE, NOT THE DECISION.
*
* ★★★★★ WHY A SECOND FAULT WAS NEEDED. -DCOMP_FAULT flips the depth test at the EQUAL-priority
* boundary, so it changes behaviour only where screenPriority == viewPriority -- and at such a
* pixel **the priority value the sprite would write is the value already there**. Drawing and
* not-drawing leave the priority plane byte-identical. Measured across two corpora and every
* divergent frame: visual 1642/1612/1606/1566/5/6 bytes differ, PRIORITY **0**.
* ★★★★ So "BOTH PLANES IDENTICAL" was one claim and one tautology: the composite gate had never
* been shown able to fail on the priority plane, on any frame, under any fault. ★★★ That is the
* same condition that let the fill's priority write stay broken for eleven tasks [AD-121] --
* twice on the same plane, which is why L-62 wants the pair and not the green.
*
* ★★★ WHAT REAL BUG THIS RESEMBLES [AC-6]. The sprite stamps an ADJACENT priority band. Design
* §3.5 makes priority banding a 168-byte LOOKUP TABLE rather than a computation, and an
* off-by-one in a band table -- or a table built with the wrong rounding at a band edge -- lands
* exactly here: every stamped pixel carries a plausible, in-range, WRONG band. ★★ `eor #1` keeps
* the value inside 0-15, so nothing overflows a nibble and no plane changes size; the defect is
* a wrong depth, not a corruption, which is the kind a byte gate exists to catch and an eye gate
* would miss.
* ★★ SEPARABLE FROM COMP_FAULT [L-54]: different symbol, different mechanism, different plane.
* Neither replaces the other and the gate should be run under both.
* ═══════════════════════════════════════════════════════════════════════════════════
                ifdef   COMP_PRI_FAULT
                eora    #1                      ; ★ INJECTED: adjacent band
                endc
                sta     ,x                      ; ★ the sprite stamps the priority plane
                endc
                bra     co_nextx

co_reject_pri:
                ifndef  COMP_NOCOUNT
                ldu     #co_rejpri
                jsr     co_inc32
                endc

co_nextx:
                inc     co_curx
                dec     co_remw
                lbra    co_pix

co_rownext:
                dec     co_remh
                ldd     co_cury
                addd    #1
                std     co_cury
                ldd     co_rowvis
                addd    #PRI_W
                std     co_rowvis
                ldd     co_rowpri
                addd    #PRI_STRIDE
                std     co_rowpri
                lbra    co_row

co_done:
                rts

* ── co_publish ── copy the counters out to where the host reads them ─────────────
* ★ Done ONCE per handshake rather than per pixel: publishing inside the loop would put four
* extended stores on the inner path and AC-5 would be measuring its own instrument [L-56].
co_publish:
                ldd     co_tested
                std     CP_TESTED
                ldd     co_tested+2
                std     CP_TESTED+2
                ldd     co_written
                std     CP_WRITTEN
                ldd     co_written+2
                std     CP_WRITTEN+2
                ldd     co_rejpri
                std     CP_REJPRI
                ldd     co_rejpri+2
                std     CP_REJPRI+2
                ldd     co_rejkey
                std     CP_REJKEY
                ldd     co_rejkey+2
                std     CP_REJKEY+2
                ldd     co_ctrlhit
                std     CP_CTRLHIT
                ldd     co_ctrlhit+2
                std     CP_CTRLHIT+2
                ldd     co_ctrlstep
                std     CP_CTRLSTEP
                ldd     co_ctrlstep+2
                std     CP_CTRLSTEP+2
                rts

* ── co_zero_counters ─────────────────────────────────────────────────────────────
co_zero_counters:
                ldx     #co_tested
                ldb     #24                     ; six 32-bit counters
                clra
co_zc_lp:       clr     ,x+
                decb
                bne     co_zc_lp
                jmp     co_publish

* ── co_put_visual ── visual[row + curX] = colour, and count it ───────────────────
co_put_visual:
* ★★ SITE 3 of 4 -- the visual WRITE, and the one that reached $FE80 and $2860.
                ifndef  PLANE_WINDOWED
                ldx     co_rowvis
                endc
                clra
                ldb     co_curx
                ifdef   PLANE_WINDOWED
                addd    co_rowvis
                jsr     plane_vis               ; X = address, slice mapped
                else
                leax    d,x
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ -DVIS_DOUBLED: THE PLANE IS A PACKED DISPLAY AND A PIXEL GOES IN BOTH NIBBLES.
*
* ★★★★★ THE DEFECT THIS CLOSES [P6.53 §7.1]. This routine stored the raw AGI colour index into
* what is, in `p3b`, the CoCo3 framebuffer -- mode 2, 4 bits per pixel, TWO SCREEN PIXELS PER
* BYTE. `$0c` is a black pixel beside a coloured one, so every sprite pixel was half black. Jay,
* on the first sprite anyone has seen: *"him and the flages look to be missing every other row of
* pixels."*
*
* ★★★★★ EVERY OTHER WRITER IN THE TREE ALREADY DOUBLES, AND TWO OF THEM SAY SO:
*     pic_core.s:113        stores scr_dbl -- ":91 identically (scr_color & 15) * 17"
*     pic_fill.s:251        reads `anda #$0F` -- "either nibble; equal by construction"
*     p3b_probe.s           clears with $FFFF -- "visual 15, both nibbles (the pixel doubling)"
*     text.s txt_blit       4 bytes per 8-pixel char -- the full 320-px resolution, 2 px/byte
* **This routine was the only one that did not**, and the invariant was stated in two files.
*
* ★★★★ WHY IT IS CONDITIONAL AND NOT UNCONDITIONAL. The ORACLE keeps the two representations
* apart: `_gameScreen` is "160x168 - screen, where the actual game content is drawn to" and
* `_displayScreen` is "320x200 or 640x400 ... which is then copied to framebuffer"
* [graphics.h:116,119 at 9d9b9e93]. **Our oracle dumps _gameScreen** (getGameScreenForOracle), so
* every reference this project compares against is ONE BYTE PER PIXEL, raw index -- including
* comp_probe's. ★★★ **comp's reference is right and the packing is ours**, at the display
* boundary, exactly where the oracle puts it. So comp_probe keeps its format and its bytes.
* ★★★ pic's gate proves the same thing from the other side: picgate.py:34-42 UNPACKS the CoCo3
* buffer and "nibble agreement is verified before either half is trusted" -- it models a packed
* plane explicitly, which is why 45/45 passes while the renderer writes doubled bytes.
*
* ★★ c*17 IS THE DOCUMENTED FORM, not (c<<4)|c: pic_core.s:91 says scr_dbl "is identically
* (scr_color & 15) * 17". One MUL beats four shifts and a pshs/ora pair [pic_core.s:88-92 costs
* that sequence at ~30 cycles], and co_col is PER-PIXEL data so it cannot be hoisted the way
* scr_dbl was.
* ★★★ -DCOMP_FAULT_RAW_VIS restores the raw store -- today's behaviour, a known-good red [§2W].
                ifdef   VIS_DOUBLED
                ifndef  COMP_FAULT_RAW_VIS
                ldb     co_col
                lda     #17
                mul                             ; B = c * 17 = the colour in both nibbles
                stb     ,x
                else
                lda     co_col
                sta     ,x
                endc
                else
                lda     co_col
                sta     ,x
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifndef  COMP_NOCOUNT
                ldu     #co_written
                jmp     co_inc32
                else
                rts
                endc

* ── co_rowset ── D = y; set co_rowvis / co_rowpri to that row's bases ────────────
* ★ y * 160 = (y << 7) + (y << 5). Done once per composite; the per-row path adds 160.
co_rowset:
                std     co_tmp
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola                            ; D = y * 32
                pshs    d
                ldd     co_tmp
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola                            ; D = y * 128
                addd    ,s++                    ; D = y * 160
                std     co_tmp
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ UNDER -DPLANE_WINDOWED co_rowvis/co_rowpri ARE FLAT OFFSETS, NOT ADDRESSES [T-P0-107].
* ★★★★★ THE DEFECT THIS CLOSES. `addd #CP_VIS` makes a flat ADDRESS, and in a windowed probe
* CP_VIS is an 8,192-byte WINDOW: row 100 lands at $FE80 beside the vector stubs and row 167 wraps
* to $2860, inside the code region. **Both were observed** -- pixel data at the IRQ vector $FEF7
* and the stall's PCs inside the interpreter's own overwritten dispatch [P6.51 §7.1].
* ★★★★ memmap.inc predicted the wrap to the byte and exempted the windowed case because
* "PLANE_WINDOWED reaches every byte through plane_vis/plane_pri, which mask the offset."
* **This file never did.** The exemption covered two subsystems and held for one.
* ★★★ THE OFFSET ARITHMETIC IS UNCHANGED -- co_rownext's +PRI_W/+PRI_STRIDE advance an offset
* exactly as they advanced an address -- so only the four ACCESS sites change, and each one is an
* `addd co_rowXXX` + `jsr plane_XXX` where it was a `leax d,x`.
* ★★ The flat build's instruction ORDER is preserved at every site, not merely its behaviour:
* comp_probe.bin must not move [§1.3], and reordering two instructions would move it.
                ifndef  PLANE_WINDOWED
                addd    #CP_VIS
                endc
                std     co_rowvis
                ldd     co_tmp
* ★ y*160 >> 1 = y*80, the packed row base. One shift rather than a second multiply chain.
                ifdef   PRI_PACKED
                lsra
                rorb
                endc
                ifndef  PLANE_WINDOWED
                addd    #CP_PRI
                endc
                std     co_rowpri
                rts

* ═══════════════════════════════════════════════════════════════════════════════════
* ── co_checkctrl ── checkControlPixel(): walk DOWN until a priority > 2 ──────────
* out: A = 1 draw, 0 skip.  ★ Transcribed from graphics.cpp:553.
*
*     while (1) { y++; offset += 160;
*                 if (y >= 168) return true;          // nothing but control below: draw
*                 cur = priority[offset];
*                 if (cur > 2) break; }
*     return cur <= viewPriority;
*
* ★★ THE COST IS NOT ONE COMPARE. Every step is counted into co_ctrlstep, because a sprite
* standing on a control line pays a column scan PER PIXEL and that is invisible in a
* two-tests-per-pixel model. AC-5 reports it separately for exactly that reason.
* ═══════════════════════════════════════════════════════════════════════════════════
co_checkctrl:
                ldd     co_cury
                std     co_ctrly
* ★★ SITE 4 of 4 -- the control-line column walk. ★★★ co_ctrloff is an ADDRESS in the flat build
* and a FLAT OFFSET in the windowed one; the `leax PRI_STRIDE,x` that advances it a row is
* unchanged either way, which is the same property that made co_rownext need no edit.
                ifndef  PLANE_WINDOWED
                ldx     co_rowpri
                endc
                clra
                ldb     co_curx
                ifdef   PRI_PACKED
                lsrb                            ; A is 0, so D = x >> 1
                endc
                ifdef   PLANE_WINDOWED
                addd    co_rowpri
                tfr     d,x                     ; ★ the OFFSET; mapped at each read below
                else
                leax    d,x
                endc
                stx     co_ctrloff
co_cc_lp:
                ldd     co_ctrly
                addd    #1
                std     co_ctrly
                ldx     co_ctrloff
                leax    PRI_STRIDE,x
                stx     co_ctrloff
                ifndef  COMP_NOCOUNT
                ldu     #co_ctrlstep
                jsr     co_inc32
                endc
                ldd     co_ctrly
                cmpd    #PRI_H
                blt     co_cc_read
                lda     #1                      ; off the bottom: nothing but control -- draw
                rts
co_cc_read:
                ifdef   PLANE_WINDOWED
                ldd     co_ctrloff
                jsr     plane_pri
                else
                ldx     co_ctrloff
                endc
                lda     ,x
* ★ x does not change down a column, so the nibble selector is FIXED for the whole walk -- but
* it is re-tested per step rather than hoisted, because the walk is 2.7% of composite cost
* [P5.4] and hoisting it would be an optimisation, which this task does not authorise (§13).
                ifdef   PRI_PACKED
                ldb     co_curx
                bitb    #1
                bne     co_cc_lo
                lsra
                lsra
                lsra
                lsra
                bra     co_cc_got
co_cc_lo:       anda    #$0F
co_cc_got:
                endc
                cmpa    #CO_CTRL_MAX
                bls     co_cc_lp                ; still control data: keep walking
                cmpa    co_prio
                bhi     co_cc_no                ; the real pixel is nearer than the sprite
                lda     #1
                rts
co_cc_no:       clra
                rts

* ── co_inc32 ── U -> a 32-bit big-endian counter; ++ ─────────────────────────────
* ★ Preserves A, B, X. The composite's inner loop calls this four times per pixel and a
* diagnostic that perturbs its own measurement is the failure mode this task keeps meeting.
* ★★★ THE OFFSETS ARE 2 AND 0, NOT 3 AND 1. A 4-byte big-endian counter holds its LOW word at
* bytes [2],[3] and its HIGH word at [0],[1]. Loading at 3,u reads bytes [3] and [4] -- the last
* byte of this counter and the FIRST BYTE OF THE NEXT ONE -- so every increment corrupted its
* neighbour and read back values like 939,524,096 ($38000000) for a count that should have been
* in the hundreds.
* ★★ The counters are contiguous by design (co_zero_counters clears all 24 bytes in one loop),
* which is exactly what turned an off-by-one into cross-contamination rather than a local error.
* The tell was `tested` looking plausible while `written` and `rejkey` were astronomically wrong.
co_inc32:
                pshs    a,b,x
                ldx     2,u
                leax    1,x
                stx     2,u
                bne     co_i32_out
                ldx     ,u
                leax    1,x
                stx     ,u
co_i32_out:     puls    a,b,x,pc

* ═══════════════════════════════════════════════════════════════════════════════════
* ── save-under ── BOTH planes, because the sprite writes both ────────────────────
*
* ★★★ THE BACKING STORE IS 2 x cel area, not 1. The oracle mallocs
* `xSize * ySize * 2 // for visual + priority data` (sprite.cpp:131). A save-under that keeps
* only the visual plane restores the picture and leaves the priority screen carrying the
* sprite's stamp -- so the NEXT sprite at that position tests against a depth the room never
* had, and the error is invisible in the visual plane until something walks behind something
* it should have walked in front of.
* ★ P5.1's model named 4,152 B as "the save-under backing-store bound". Measured here, the
* bound is 8,304 B for the same peak, and AC-7 reports the doubled figure.
* ═══════════════════════════════════════════════════════════════════════════════════
* Backing-store layout: the visual block, then the priority block, each vc_w * vc_h bytes.
* co_save and co_restore differ only in the direction of the two moves, so they share a body
* with a flag -- one walk, one set of index arithmetic, one place for it to be wrong.
                ifdef   CP_SAVE
co_svdir        fcb     0                       ; 0 = save (screen -> store), 1 = restore
co_svptr        fdb     0                       ; -> the visual half of the store
co_svptr2       fdb     0                       ; -> the priority half

co_save:        clr     co_svdir
                bra     co_sv_body
co_restore:     lda     #1
                sta     co_svdir
co_sv_body:
* set up the geometry exactly as the composite does, from the same inputs
                lda     CP_X
                sta     co_basex
                clra
                ldb     CP_Y
                pshs    d
                clra
                ldb     vc_h
                pshs    d
                ldd     2,s
                subd    ,s++
                leas    2,s
                addd    #1
                std     co_cury
                ldd     co_cury
                jsr     co_rowset

                ldd     #CP_SAVE
                std     co_svptr
                lda     vc_w
                ldb     vc_h
                mul                             ; D = the per-plane size
                std     co_tmp
                addd    #CP_SAVE
                std     co_svptr2
* ★ AC-7: the backing store is TWO planes. Reported as the doubled figure, not the cel area.
                ldd     co_tmp
                aslb
                rola
                std     CP_SAVEB
                cmpd    CP_SAVEPK
                bls     co_sv_nopk
                std     CP_SAVEPK
co_sv_nopk:
                lda     vc_h
                sta     co_remh
co_sv_row:
                lda     co_remh
                beq     co_sv_done
                clra
                ldb     co_basex
                ldx     co_rowvis
                leax    d,x                     ; X -> visual  screen row + x
                ldy     co_rowpri
                pshs    y
                clra
                ldb     co_basex
                addd    ,s++
                tfr     d,y                     ; Y -> priority screen row + x
                lda     vc_w
                sta     co_remw
co_sv_px:
                lda     co_remw
                beq     co_sv_next
                lda     co_svdir
                bne     co_sv_rest
* ---- save: screen -> store ------------------------------------------------------
                lda     ,x+
                ldu     co_svptr
                sta     ,u+
                stu     co_svptr
                lda     ,y+
                ldu     co_svptr2
                sta     ,u+
                stu     co_svptr2
                bra     co_sv_pxend
* ---- restore: store -> screen ---------------------------------------------------
co_sv_rest:
                ldu     co_svptr
                lda     ,u+
                stu     co_svptr
                sta     ,x+
                ldu     co_svptr2
                lda     ,u+
                stu     co_svptr2
                sta     ,y+
co_sv_pxend:
                dec     co_remw
                bra     co_sv_px
co_sv_next:
                dec     co_remh
                ldd     co_rowvis
                addd    #PRI_W
                std     co_rowvis
                ldd     co_rowpri
                addd    #PRI_W
                std     co_rowpri
                bra     co_sv_row
co_sv_done:
                rts
                endc
