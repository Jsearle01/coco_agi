* ═══════════════════════════════════════════════════════════════════════════════════════════
* src/harness/plane_win.s -- WINDOWED PLANE ADDRESSING
*
* ★★★★★ THE DEFECT THIS CLOSES [L-69: fitting and reaching are different questions].
* The map gives each draw phase an 8,192-byte slice -- MAP_PRI_SLICE $A000-$C000 for priority
* and MAP_PHASE_WIN $C000-$E000 for the framebuffer. The planes are larger than their windows:
*
*     visual    26,880 B = 3.28 slices     $C000 + 26,879 = $128FF  -> WRAPS to $28FF,
*                                          inside the code region $2000-$5300
*     priority  13,440 B = 1.64 slices     $A000 + 13,439 = $D47F   -> runs THROUGH $C000,
*                                          which is the framebuffer slice
*
* ★★★ THE SECOND ONE IS NOT IN THE DISPATCH AND IS ARGUABLY WORSE. The visual overrun wraps
* into code and the CPU ends up executing the seed stack, which is loud. The priority overrun
* does not wrap at all -- it quietly writes priority bytes over the framebuffer, and the failure
* is a wrong picture rather than a crash.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE SEAM. A plane access has always been "flat offset -> address":
*
*     flat:      addr = BASE + off
*     windowed:  slice = off >> 13,  within = off & $1FFF,  addr = WINDOW + within
*                ...and the slice must be mapped before the access.
*
* ★★★ `pix_off` ALREADY EXISTS as a separate value in pic_core.s, and co_rowset already forms a
* row base once per row. **The flat offset is computed either way**, so windowing changes the
* address-formation step and nothing else. That is why this is a seam and not a rewrite.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHY THERE ARE TWO MAP ACTIONS, AND WHY THE FLAT-BACKED ONE IS THE POINT.
*
* The renderer gate runs pic_probe.s, whose map is PRI_BASE $1700 and FB_BASE $8000 -- both
* planes FIT FLAT in the 64K CPU map. **So the 45/45 gate has never exercised windowing and
* cannot, as written.** Adding a windowed mode that is simply OFF for pic_probe would leave
* AC-3 proving that windowing did not break the flat path, which is not the claim that matters.
*
* ★★★★ So the slice/offset arithmetic is separated from the ACT of mapping:
*
*   PLANE_WIN_MMU   the real thing: the window is fixed at MAP_PHASE_WIN / MAP_PRI_SLICE and
*                   mapping a slice writes the MMU task register.
*   (default)       flat-backed: mapping a slice sets the base to BASE + slice*8192 and touches
*                   no register. **Identical arithmetic, identical boundary splitting, no MMU.**
*
* ★★★ The flat-backed build runs the whole windowed code path in pic_probe's map, so the
* renderer gate can be run BOTH ways against the same oracle. **Byte-identical output from the
* windowed path is the evidence that windowing does not change a pixel** -- the arithmetic is
* what can be wrong, and it is what gets tested. The MMU write is the part a gate in this map
* could never cover.
* ★★ It is also the honest limit of that evidence, and it is stated rather than glossed: a
* flat-backed pass does NOT prove the MMU remap is correct. p3b is where that is exercised.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ GRANULARITY -- one choice per site, from what each loop already does (dispatch §3):
*
*   ff_store    PER SPAN.  The run is B bytes from one pointer and B is a BYTE, so a run
*               crosses at most ONE boundary. Split into two flat runs; the 11-cycle inner
*               loop (sta ,x+ / decb / bne) is UNTOUCHED. P3.3 took the fill from 11.102 s to
*               2.746 s largely by making this a byte-pointer walk, and a per-pixel test here
*               would give that back.
*   co_rowset   PER ROW.  It already computes a row base once per row; the slice split costs
*               one shift chain in a routine that runs 168 times, not 26,880.
*   put_pixel   PER PIXEL, with a CACHED SLICE.  Random access by nature -- there is no loop to
*               hoist out of. The common case is a compare-and-branch against the cached slice;
*               a remap happens only when it actually changes.
*
* ★★ The per-pixel case is the one with a real cost and §3 predicted that. It is measured, not
* asserted -- see the report's AC-5 and AC-10.
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ★★★★★ IS THE PRIORITY PLANE WINDOWED HERE? A build can window one plane and not the other.
* pic_probe's gate map keeps priority FLAT at $1700 (only the visual plane lives in blocks there)
* and declares PLANE_PRI_FLAT; p3b windows both. Routing priority through plane_pri regardless --
* which is what a bare `ifdef PLANE_WINDOWED` does -- addresses a $1700 plane through an $A000
* window and puts every priority pixel in the wrong place.
* ★★★★ It cost a full sweep to find, and the split was diagnostic: **45 of 45 VISUAL planes
* byte-identical, 43 of 45 PRIORITY planes wrong.** One plane perfect and the other uniformly
* broken is a configuration fault, not an algorithm fault.
                ifndef  PLANE_PRI_FLAT
PLANE_PRI_WIN   equ     1
                endc

PLANE_SLICE_SZ  equ     8192
PLANE_SLICE_MSK equ     PLANE_SLICE_SZ-1        ; $1FFF

* ★ A slice number is off>>13. D's high byte is A, so slice = A>>5 and within-A = A&$1F.
PLANE_SLICE_SH  equ     5

* ── state: which slice each plane currently has mapped, and the base to add ──
* ★★ -1 = nothing mapped, so the first access always maps. **Never initialise these to 0**:
* slice 0 is a legal slice, and a zero-initialised cache would skip the first map and address
* whatever the window happened to hold.
pl_vis_cur      fcb     $FF
pl_pri_cur      fcb     $FF
pl_vis_base     fdb     0
pl_pri_base     fdb     0
pl_remaps       fdb     0               ; ★ how many times a slice actually changed (AC-5/AC-10)

* ── plane_reset — force both caches invalid. Call at the top of a draw phase ──
* ★★★ REQUIRED, not hygiene. The MMU slot is shared with the VM phase's volume window
* (MAP_VOL_WINDOW equ MAP_PHASE_WIN), so after a phase change the register no longer holds what
* the cache thinks. §2R.1's phase pair is exactly this hazard.
plane_reset:
                lda     #$FF
                sta     pl_vis_cur
                sta     pl_pri_cur
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── plane_vis — D = flat visual offset. Returns X = CPU address, slice mapped. ──
* ★ Preserves B's low bits through the shift by working on A only.
* ═══════════════════════════════════════════════════════════════════════════════════════════
plane_vis:
                pshs    a                       ; keep the full high byte
                lsra
                lsra
                lsra
                lsra
                lsra                            ; A = slice
                cmpa    pl_vis_cur
                beq     pv_have
                sta     pl_vis_cur
                bsr     pl_map_vis
pv_have:
                puls    a
                anda    #$1F                    ; within-slice offset, high byte
                addd    pl_vis_base
                tfr     d,x
                rts

* ── plane_pri — D = flat priority offset (already packed if PRI_PACKED). X = address. ──
plane_pri:
                pshs    a
                lsra
                lsra
                lsra
                lsra
                lsra
                cmpa    pl_pri_cur
                beq     pp_have
                sta     pl_pri_cur
                bsr     pl_map_pri
pp_have:
                puls    a
                anda    #$1F
                addd    pl_pri_base
                tfr     d,x
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── the two map actions ──
* ★★★★ A = slice number. This is the ONLY place the two builds differ, and it is four
* instructions either way.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ B MUST SURVIVE THIS ROUTINE, AND THE FIRST VERSION DESTROYED IT.
* Both branches below build a 16-bit value in D -- the flat-backed one with `clrb` after shifting
* the slice into A, the MMU one with `ldd #MAP_PHASE_WIN`. **B is the offset's LOW BYTE**, and
* plane_vis restores only A (`puls a`) before `addd pl_vis_base`. So every access that triggered
* a remap addressed `offset & $1F00` instead of the real offset.
* ★★★★ THE GATE CAUGHT IT AND NOTHING ELSE WOULD HAVE. The windowed sweep's first run had
* 0 of 45 visual planes byte-identical -- not a subtle drift, every picture -- because put_pixel
* is random-access and remaps constantly. A reading of this routine looks right in isolation:
* the bug is in what the CALLER assumes it preserves, which is §2H check 2 exactly.
pl_map_vis:
                pshs    b
                pshs    d
                ldd     pl_remaps
                addd    #1
                std     pl_remaps
                puls    d
                ifdef   PLANE_WIN_MMU
* ★★★★ THE REAL PATH, AND IT DOES NOT TOUCH A REGISTER. The framebuffer's physical blocks are
* consecutive from ph_blk_fb, so slice n is block ph_blk_fb+n -- which is exactly what
* mmu_phase.s's phase_draw_fb does. **Calling it keeps mmu_phase.s the single sanctioned owner
* of $FFA5/$FFA6** (§2N); writing $FFA6 here would have made a second owner in a file the
* register census does not even scan (`src/engine` only), so the new owner would have been
* invisible to the instrument built to catch exactly that.
* ★★ An earlier draft of this block claimed it was declaring "$FFA7, the slot covering
* $C000-$DFFF". **That was wrong twice**: $FFA7 covers $E000-$FFFF, and $C000-$DFFF is slot 6 at
* $FFA6, which mmu_phase.s already owns. The comment is corrected rather than deleted because it
* was the reasoning that nearly added the second owner.
                jsr     phase_draw_fb
                ldd     #MAP_PHASE_WIN
                std     pl_vis_base
                else
* ★★ FLAT-BACKED: base = FB_BASE + slice*8192. No register is touched, and the arithmetic the
* gate exists to test -- the shift, the mask, the boundary split -- is identical.
* ★ slice*8192 = slice*$2000, so the high byte is slice<<5 and the low byte is zero. Five
* shifts and a clrb, not a rotate chain.
                asla
                asla
                asla
                asla
                asla                            ; A = slice*32 = high byte of slice*8192
                clrb
                addd    #FB_BASE
                std     pl_vis_base
                endc
                puls    b                       ; ★ restore the offset's low byte
                rts

pl_map_pri:
                pshs    b                       ; ★ see pl_map_vis: B is the offset's low byte
                pshs    d
                ldd     pl_remaps
                addd    #1
                std     pl_remaps
                puls    d
                ifdef   PLANE_WIN_MMU
* ★ Same argument as pl_map_vis: phase_draw_pri already maps ph_blk_pri+A into slot 5.
                jsr     phase_draw_pri
                ldd     #MAP_PRI_SLICE
                std     pl_pri_base
                else
                asla
                asla
                asla
                asla
                asla
                clrb
                addd    #PRI_BASE
                std     pl_pri_base
                endc
                puls    b                       ; ★ restore the offset's low byte
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── plane_split — how many bytes of a B-byte run starting at flat offset D fit in the slice ──
* out: B = bytes available in THIS slice (1..8192, capped to 255 by the caller's byte count)
* ★★★ THE PER-SPAN CHECK, and the reason ff_store's inner loop never changes. A run is at most
* 255 bytes and a slice is 8,192, so a run crosses AT MOST ONE boundary: the caller stores
* `avail` bytes, remaps, and stores the rest. No test inside the walk.
* ═══════════════════════════════════════════════════════════════════════════════════════════
plane_avail:
                anda    #$1F                    ; D = within-slice offset, 0..8191
                pshs    a,b
                ldd     #PLANE_SLICE_SZ
                subd    ,s++                    ; D = 8192 - within, 1..8192
                cmpd    #255
                bls     pa_done
                ldb     #255                    ; ★ clamp: the caller's count is a byte
pa_done:
                rts
