* src/harness/cel_probe.s -- the compositing harness: cel decode, the blit, save-under, cost.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ SAME GO-GATE SHAPE AS res_probe.s / vm_probe.s. The host stages one VIEW resource and one
* priority screen, asks for an operation, and reads the result back. Every address the host
* touches is listed below and nothing else is poked.
*
* ★★★ TWO OPERATIONS, GATED SEPARATELY, because AC-2 and AC-3 are different claims:
*   MODE 1  decode cel (loop, cel) of the staged VIEW  -> AC-2, byte-identical against view.py
*   MODE 2  composite the decoded cel at (x, y)        -> AC-3, byte-identical against the ref
*   MODE 3  free-run N composites for timing           -> AC-5/AC-6
*   MODE 4  clock calibration, N x 160,000 cycles      -> ★ L-57, and see the note below
*
* ★★ MODE 4 EXISTS BECAUSE TWO CLOCK FIGURES ARE ON RECORD -- 1.7898 MHz (P3.3/P3.13) and
* 1.7871 (P1.3/P4.4) -- and every cost figure this task produces is divided by one of them. The
* single-block form cannot separate the loop from the harness overhead around it; running N
* blocks and taking the SLOPE can. Measured here at 1.78939 MHz against a hardware constant of
* 14.31818/8 = 1.789772, so the lower figure is scaffolding [L-56].
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/hal.inc"

* ── the map. Every region is asserted against its neighbour at the bottom of this file. ──
* ★ T-P0-027 spent a session on instrument tables the code had grown into, guarded by an
* assertion that named one of four adjacencies and was true throughout. Every pair is checked.
* ═══════════════════════════════════════════════════════════════════════════════════
* ★★★ THE TWO PLANES DO NOT FIT IN THE CPU WINDOW, AND THAT IS A FINDING, NOT A LAYOUT
* INCONVENIENCE. Visual and priority are 160 x 168 = 26,880 bytes EACH -- the size the oracle
* holds them at and therefore the size a byte-identical gate must produce. 53,760 bytes of
* planes, plus ~4 KB of code, 4 KB of decoded cel, the staged VIEW and the save-under store,
* is over 70 KB against the 6809's 64 KB.
*
* ★★ So the planes are BANKED, which is what design §2R.1 already says the shipped path does:
* "the VM runs with no buffer mapped at all; picture-draw and sprite-composite each need one
* framebuffer slice plus one priority slice." The harness reproduces that rather than inventing
* a flat layout no CoCo3 can have -- otherwise AC-5's cost figure would omit the remaps and be
* an underestimate of exactly the thing the task exists to measure.
*
* ★ THIS PROBE IS DECODE-ONLY (AC-2). The composite probe is separate, because its map is the
* banked one and mixing the two would put a windowing scheme into a measurement that does not
* need it. Two probes, two maps, each asserted.
* ═══════════════════════════════════════════════════════════════════════════════════
CP_VIEW         equ     $2000           ; staged VIEW resource
CP_VIEW_MAX     equ     $2000           ; 8 KB -- larger than any VIEW in the pinned corpus
CP_CEL          equ     $4000           ; decoded cel pixels (VC_CEL_MAX)

PRI_W           equ     160
PRI_H           equ     168

CP_GO           equ     $0080           ; host writes 1; probe clears it when done
CP_MODE         equ     $0081           ; 1 decode, 2 composite, 3 free-run, 4 calibrate
CP_LOOP         equ     $0082
CP_CEL_NR       equ     $0083
CP_X            equ     $0084           ; composite position, x
CP_Y            equ     $0085           ; composite position, y
CP_PRIO         equ     $0086           ; the sprite's priority
CP_ERR          equ     $0087
CP_W            equ     $0088           ; decoded width  (readback)
CP_H            equ     $0089           ; decoded height (readback)
CP_KEY          equ     $008A
CP_MIR          equ     $008B
CP_VIEWLEN      equ     $008C           ; 2 bytes: staged resource length
CP_N            equ     $008E           ; 2 bytes: free-run / calibration count
CP_TESTED       equ     $0090           ; 4 bytes: source pixels tested, cumulative
CP_WRITTEN      equ     $0094           ; 4 bytes: pixels actually written
CP_REJPRI       equ     $0098           ; 4 bytes: rejected by the PRIORITY test
CP_REJKEY       equ     $009C           ; 4 bytes: rejected by TRANSPARENCY
CP_BLITS        equ     $00A4           ; 2 bytes: composites performed
CP_DIAG         equ     $00A8           ; ★ 6 bytes: loopoff, nloops, ncels, src
CP_HW_STACK     equ     $0700

                org     $0700
cel_probe_entry:
                orcc    #$50
                lds     #CP_HW_STACK
                jsr     HAL_sys_init
* ★ ALL-RAM. HAL_sys_init does not do this -- sys.s:118-128 says so, naming $FFDE/$FFDF as the
* addresses it never writes. Without it $8000-$FEFF is ROM and CP_VIS at $E000 silently will
* not hold a byte. T-P0-027 found that the expensive way; this probe writes it at entry.
* ★ §2N: $FFDF is in the scan window and outside both HAL ranges. src/harness/ is excluded from
* the census and probes are allowlisted by filename, so the write is declared here.
                sta     $FFDF

* ★ every host-written control byte gets a power-on value. T-P0-027 shipped VP_FREE without one
* and every gate went red at once, because "the host will set it" is only true on the runs where
* the host sets it.
                ldd     #0
                std     CP_N
                std     CP_TESTED
                std     CP_TESTED+2
                std     CP_WRITTEN
                std     CP_WRITTEN+2
                std     CP_REJPRI
                std     CP_REJPRI+2
                std     CP_REJKEY
                std     CP_REJKEY+2
                std     CP_BLITS
                std     CP_BLITS
                clr     CP_ERR

cp_loop:
                clr     CP_GO
cp_wait:        lda     CP_GO
                beq     cp_wait

                lda     CP_MODE
                cmpa    #1
                beq     cp_do_decode
                cmpa    #3
                beq     cp_do_free
                cmpa    #4
                beq     cp_do_cal
                bra     cp_loop

* ── MODE 1: decode ───────────────────────────────────────────────────────────────
cp_do_decode:
                jsr     cp_decode
                bra     cp_loop

* ── MODE 3: free-run N decodes, for the decode-side cost ─────────────────────────
* ★ §4A decodes cels ON LOAD into a cache, so this is NOT the per-cycle tax -- it is what a
* room change pays once. Reported separately from the composite for that reason.
cp_do_free:
                ldd     CP_N
                beq     cp_loop
cp_free_lp:     pshs    d
                jsr     cp_decode
                puls    d
                subd    #1
                bne     cp_free_lp
                bra     cp_loop

* ── MODE 4: clock calibration ────────────────────────────────────────────────────
* 20,000 iterations of `leax -1,x` (5) + `bne` (3, taken or not) = 160,000 cycles per block.
cp_do_cal:
                ldd     CP_N
                beq     cp_loop
cp_cal_blk:     pshs    d
                ldx     #20000
cp_cal_lp:      leax    -1,x
                bne     cp_cal_lp
                puls    d
                subd    #1
                bne     cp_cal_blk
                bra     cp_loop

* ═══════════════════════════════════════════════════════════════════════════════════
* ── cp_decode ── stage the inputs and call the decoder ───────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════
cp_decode:
                ldd     #CP_VIEW
                std     vc_view
                addd    CP_VIEWLEN
                std     vc_srcend
                ldd     #CP_CEL
                std     vc_dest
                lda     CP_LOOP
                sta     vc_loop
                lda     CP_CEL_NR
                sta     vc_cel
                jsr     vc_decode_cel
* ★★★★ -DCEL_FAULT INJECTS ONE WRONG PIXEL, ON PURPOSE. AC-9 asks every re-run gate to prove it
* can still SEE a fault, and the cel gate had no fault mode at all -- so "9,193/9,193 match" was
* a number with no demonstrated sensitivity. **A gate that has never been shown to fail is not
* known to be a gate**, and this one runs 9,193 comparisons whose only observed outcome is
* success.
* ★★★ One byte, in the decoded output, after the decode: it does not disturb the decoder's own
* state, so what it tests is exactly the comparison path -- readback, manifest, and celgate.py's
* byte diff.
* ★★ MEASURED: 814 of 814 mismatch, not one. CP_CEL is the single destination buffer EVERY cel
* decodes through, so a fault placed here fires once per cel by construction. The prediction
* written here first ("a single mismatched cel") was wrong about its own blast radius, and the
* run said so. ★ It is still a valid detectability proof -- 0/814 match, celgate exits 1 -- but
* it proves the comparison path is live, not that the gate LOCALISES a fault. A localising fault
* would have to key on a specific (view, loop, cel) before writing.
                ifdef   CEL_FAULT
                lda     CP_CEL
                coma
                sta     CP_CEL
                endc
                lda     vc_err
                sta     CP_ERR
                lda     vc_w
                sta     CP_W
                lda     vc_h
                sta     CP_H
                lda     vc_key
                sta     CP_KEY
                lda     vc_mir
                sta     CP_MIR
* ★ Diagnostics, because "ours 8x33, oracle 6x32" is a symptom and the offsets are the cause.
* A wrong loop offset, a wrong cel offset and a wrong header read all present identically.
                ldd     vc_loopoff
                std     CP_DIAG
                lda     vc_nloops
                sta     CP_DIAG+2
                lda     vc_ncels
                sta     CP_DIAG+3
                ldd     vc_src
                std     CP_DIAG+4
                rts

                include "src/harness/view_cel.s"
* ★ composite.s is NOT included: this probe is decode-only. The composite needs the banked
* two-plane map described above and lives in its own probe.

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★ EVERY ADJACENCY, in map order. T-P0-027's lesson, applied at the point of writing rather
* than after a session lost to it: an assertion that names one neighbour reports conformance
* for the rest.
CP_CODE_END     equ     *
                ifgt    CP_CODE_END-CP_VIEW
                error   "cel_probe code overlaps CP_VIEW"
                endc
                ifgt    CP_VIEW+CP_VIEW_MAX-CP_CEL
                error   "CP_VIEW overlaps CP_CEL"
                endc
                ifgt    CP_CEL+VC_CEL_MAX-$FF00
                error   "CP_CEL runs into the $FF00 I/O page"
                endc
                end     cel_probe_entry
