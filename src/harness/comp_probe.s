* src/harness/comp_probe.s -- the composite gate: both planes resident, one sprite per handshake.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE MAP IS THE FINDING. Visual and priority are 160 x 168 = 26,880 bytes EACH, because
* that is how the oracle holds them and a byte-identical gate must produce the same shape. Both
* resident is 53,760 bytes; with the decoded cel and this probe's code that is 62,464 of the
* 65,280 bytes below the I/O page, and it fits with 2.8 KB to spare:
*
*     $0700-$1100   code                     2,560 B
*     $1100-$2900   CP_CEL   (decoded cel)   6,144 B   -- corpus max is 4,784
*     $2900-$9200   CP_PRI                  26,880 B
*     $9200-$FB00   CP_VIS                  26,880 B
*     $FB00-$FEFF   spare                    1,024 B
*
* ★★ WHAT DOES NOT FIT IS THE SAVE-UNDER STORE. It is 2 x cel area (the oracle mallocs
* `xSize * ySize * 2 // for visual + priority data`, sprite.cpp:131), so 9,568 bytes at the
* corpus maximum -- and there are 1,024 spare. **On a 512 KB machine the backing store lives in
* a spare BLOCK, not in the CPU window**, and that is an input to design §3.6 rather than a
* limitation of this harness. AC-7 reports the size and the copy cost; it does not pretend the
* store can sit beside both planes, because it cannot.
*
* ★ THE CEL IS STAGED, NOT DECODED HERE. AC-2 already gates the decoder at 6,782/6,782, and
* §4A decodes on load into a cache. Re-decoding per composite would measure a cost the shipped
* interpreter never pays, and would put a gated subsystem inside an ungated measurement.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                include "src/hal.inc"

CP_CEL          equ     $1100
CP_PRI          equ     $2900
CP_VIS          equ     $9200
PRI_W           equ     160
PRI_H           equ     168

CP_GO           equ     $0080           ; host writes 1; probe clears it when done
CP_MODE         equ     $0081           ; 2 = composite, 3 = free-run N, 4 = calibrate
CP_X            equ     $0084
CP_Y            equ     $0085
CP_PRIO         equ     $0086
CP_ERR          equ     $0087
CP_W            equ     $0088           ; the staged cel's width
CP_H            equ     $0089           ; ... and height
CP_KEY          equ     $008A           ; ... and clear key
CP_N            equ     $008E           ; 2 bytes: free-run / calibration count
CP_TESTED       equ     $0090           ; 4 bytes
CP_WRITTEN      equ     $0094           ; 4 bytes
CP_REJPRI       equ     $0098           ; 4 bytes
CP_REJKEY       equ     $009C           ; 4 bytes
CP_BLITS        equ     $00A4           ; 2 bytes
CP_CTRLHIT      equ     $00A8           ; 4 bytes: pixels that took the CONTROL branch
CP_CTRLSTEP     equ     $00AC           ; 4 bytes: column-scan steps those cost
CP_HW_STACK     equ     $0700

                org     $0700
comp_probe_entry:
                orcc    #$50
                lds     #CP_HW_STACK
                jsr     HAL_sys_init
* ★ ALL-RAM: HAL_sys_init does not write $FFDF (sys.s:118-128) and CP_VIS lives at $9200, which
* is ROM until it does. T-P0-027 found that by watching an arena refuse to hold a byte.
                sta     $FFDF

                ldd     #0
                std     CP_N
                std     CP_BLITS
                clr     CP_ERR
                jsr     co_zero_counters

cp_loop:
                clr     CP_GO
cp_wait:        lda     CP_GO
                beq     cp_wait

                lda     CP_MODE
                cmpa    #2
                beq     cp_do_comp
                cmpa    #3
                beq     cp_do_free
                cmpa    #4
                beq     cp_do_cal
                cmpa    #5
                beq     cp_do_zero
                bra     cp_loop

cp_do_comp:
                jsr     cp_setup
                jsr     cp_composite
                jsr     co_publish
                bra     cp_loop

* ★ MODE 5 zeroes the counters, so the host can bracket a measurement without reloading the
* program. Without it every free-run figure would be cumulative from boot and AC-5 would be
* reporting a running total dressed as a rate.
cp_do_zero:
                jsr     co_zero_counters
                bra     cp_loop

* ── MODE 3: free-run N composites ────────────────────────────────────────────────
* ★★ THE HANDSHAKE COSTS A WHOLE EMULATED FRAME per composite, so timing through the gate
* measures MAME's frame period. N back-to-back composites and the emulated clock either side
* gives the real per-composite figure [the T-P0-027 free-run, same reasoning].
cp_do_free:
                ldd     CP_N
                beq     cp_loop
                jsr     cp_setup
cp_free_lp:     pshs    d
                jsr     cp_composite
                puls    d
                subd    #1
                bne     cp_free_lp
                jsr     co_publish
                bra     cp_loop

* ── MODE 4: clock calibration, N x 160,000 cycles ────────────────────────────────
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

* ── cp_setup ── publish the staged cel's geometry into the composite's inputs ────
cp_setup:
                lda     CP_W
                sta     vc_w
                lda     CP_H
                sta     vc_h
                lda     CP_KEY
                sta     vc_key
                rts

                include "src/harness/composite.s"

                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"

* ★ vc_w / vc_h / vc_key are the decoder's outputs and the composite's inputs. This probe does
* not decode, so it declares them itself -- one home per fact still holds, because the DECODE
* probe includes view_cel.s and this one does not.
vc_w            fcb     0
vc_h            fcb     0
vc_key          fcb     0

* ═══════════════════════════════════════════════════════════════════════════════════
* ★★ EVERY ADJACENCY, in map order.
CP_CODE_END     equ     *
                ifgt    CP_CODE_END-CP_CEL
                error   "comp_probe code overlaps CP_CEL"
                endc
                ifgt    CP_CEL+6144-CP_PRI
                error   "CP_CEL overlaps CP_PRI"
                endc
                ifgt    CP_PRI+PRI_W*PRI_H-CP_VIS
                error   "CP_PRI overlaps CP_VIS"
                endc
                ifgt    CP_VIS+PRI_W*PRI_H-$FF00
                error   "CP_VIS runs into the $FF00 I/O page"
                endc
                end     comp_probe_entry
