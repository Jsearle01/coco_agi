* src/harness/res_probe.s -- the harness that drives res_core.s under MAME.
*
* ★★ SAME SHAPE AS pic_probe.s's GO GATE, and for the same reason: the host stages the inputs,
* pokes a request, releases the guest, and reads the result back. One resource per handshake, so
* AC-2 compares ACTUAL BYTES rather than a checksum -- 200 fetches of up to 10 KB is about 2.5 s
* of host reads at the measured 65,280 bytes per 0.08 s, which buys an unambiguous comparison.
*
* ★★★ WHY NOT A CHECKSUM: a 16-bit sum over 200 resources has a real collision probability, and
* a collision would report a byte-identical gate that is not. The gate is the deliverable; it
* does not get to be probabilistic to save two seconds.

                include "src/hal.inc"

RP_REQ_TYPE     equ     $0080           ; host writes: resource type
RP_REQ_INDEX    equ     $0081           ; host writes: resource index
RP_GO           equ     $0082           ; host writes 1 to release; probe clears when done
RP_STATUS       equ     $0083           ; probe writes: res_err
RP_LEN          equ     $0084           ; probe writes: res_len (2 bytes)
RP_REMAPS       equ     $0086           ; probe writes: MMU remaps for THIS fetch (2 bytes)
RP_MODE         equ     $0088           ; host writes: 0 fetch, 1 census, 2 open, 3 close
RP_BASE         equ     $008D           ; probe writes: where the bytes landed (2 bytes)
RP_DEPTH        equ     $008F           ; probe writes: residency depth after the operation
RP_MSGS         equ     $0090           ; probe writes: message count from res_decode (AC-9)
RP_VOL          equ     $0089           ; probe writes: the parsed volume nibble
RP_OFFHI        equ     $008A           ; probe writes: offset bits 19..16
RP_OFF          equ     $008B           ; probe writes: offset bits 15..0 (2 bytes)
RP_HW_STACK     equ     $0700           ; S grows DOWN from here into $0400-$06FF

                org     $0700
res_probe_entry:
                orcc    #$50                    ; the probe owns the machine; no interrupts
                lds     #RP_HW_STACK            ; ★ hal.inc:357 -- the CALLER owns S

* ★★★ THE BARE-METAL TRANSITION IS NOT OPTIONAL AND ITS ABSENCE COST A RUN. Without
* HAL_sys_init the machine is still in DECB's map: the GIME MMU is not enabled, so $C000-$DFFF
* is ROM rather than a mappable window, and writing $FFA6 changes nothing. The first sweep
* staged its slice, poked its tables, set PC -- and fetched nothing, because the volume window
* did not exist. ★ pic_probe.s has done this since P3.1; I wrote a new entry point and left it
* out, so the harness reported a clean 48 KB stage and zero fetched bytes.
*
* ★★ AND IT MOVES THE STAGING TOO. $FFA6 does nothing before this call, so the HOST cannot
* stage either: res_sweep.lua now waits for the probe to reach its gate and stages afterwards.
* The transition is a precondition of BOTH sides, not just the guest's.
                jsr     HAL_sys_init            ; bare-metal transition: $FF90 + MMU on

* ★ Announce readiness, then wait. Everything the fetch needs -- DIR tables, the staged volume
* slice, res_volbase and res_slicebase -- is poked by the host while the probe sits here.
rp_loop:
                clr     RP_GO
rp_wait:        lda     RP_GO
                beq     rp_wait

* ---- AC-7: count the MMU remaps this fetch performs -------------------------
* ★★ res_remaps is zeroed per fetch, so the number reported is THIS resource's remap count and
* not a running total. The wall-clock cost comes from a host tap on RP_GO, exactly as the
* picture probe timed its phases; a remap count is the part a cycle figure cannot infer.
                ldd     #0
                std     res_remaps

                lda     RP_REQ_TYPE
                ldb     RP_REQ_INDEX

* ★★ CENSUS MODE CALLS res_find AND STOPS THERE. AC-4 is about the DIR parse, and running it
* through res_fetch would confound two things: an entry can be parsed perfectly and still be
* unfetchable because its volume is not the one staged. ★ Census reports what the 6809 DECODED
* -- volume nibble and 20-bit offset, per slot, present and empty alike -- so the "test the
* offset, never the volume" rule is checked against every FF FF FF slot in the corpus rather
* than inferred from the resources that happened to load.
                tst     RP_MODE
                bne     rp_notfetch
* ★ Mode 0 is open-then-close: the arena returns to depth 0 every time, so AC-2's 1,264 fetches
* all land at RES_ARENA and the byte gate reads one fixed address. It is the same code path
* AC-5 drives, not a second one kept alongside it.
                jsr     res_open
                pshs    a
                jsr     res_close
                puls    a
                bra     rp_report
rp_notfetch:
                pshs    a
                lda     RP_MODE
                cmpa    #1
                puls    a
                bne     rp_stack
                jsr     res_find
                ldd     #0
                std     res_len
                bra     rp_report
rp_stack:
                pshs    a
                lda     RP_MODE
                cmpa    #2
                puls    a
                bne     rp_pop
                jsr     res_open
                bra     rp_report
rp_pop:
                pshs    a
                lda     RP_MODE
                cmpa    #3
                puls    a
                bne     rp_mode4
                jsr     res_close
                clr     res_err
                ldd     #0
                std     res_len
                bra     rp_report

* ★★ MODE 4 IS THE CLOCK CALIBRATION, AND IT IS A GUARD, NOT A CONVENIENCE [idioms 19l].
* AC-7 is quoted in cycles and the host measures SECONDS; the conversion needs the live clock,
* and a CoCo3 in SLOW mode makes every derived cycle figure 2x wrong with nothing to show for
* it. 20,000 iterations of `leax -1,x` (5) + `bne` taken (3) = 160,000 cycles exactly.
rp_mode4:
                pshs    a
                lda     RP_MODE
                cmpa    #4
                puls    a
                bne     rp_decode
                bra     rp_calib
rp_decode:
* ★ Mode 5 = fetch a LOGIC and decode it in place. Same res_open the byte gate uses, then the
* XOR; the host reads the arena back and diffs the DECODED bytes. AC-9's claim is about the
* decode, so the fetch underneath it is the already-gated path and not a second one.
                jsr     res_open
                lda     res_err
                bne     rp_report
                jsr     res_decode
                bra     rp_report
rp_calib:
                ldx     #20000
rp_calloop:     leax    -1,x
                bne     rp_calloop
                clr     res_err
                ldd     #0
                std     res_len
rp_report:
                ldd     res_base
                std     RP_BASE
                lda     res_depth
                sta     RP_DEPTH
                lda     res_msgs
                sta     RP_MSGS
                lda     res_vol
                sta     RP_VOL
                lda     res_offhi
                sta     RP_OFFHI
                ldd     res_off
                std     RP_OFF

                lda     res_err
                sta     RP_STATUS
                ldd     res_len
                std     RP_LEN
                ldd     res_remaps
                std     RP_REMAPS
                lbra    rp_loop

                include "src/harness/res_core.s"

* ★ The HAL, included exactly as pic_probe.s includes it (§2M: including a shared file is not
* modifying one). Only sys.s is called, but hal_globals.s and gfx.s resolve each other's symbols.
                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"

* ★★ The layout assertion, and it is BEFORE `end` -- P3.13 placed one after it, where lwasm has
* already stopped reading, and it silently enforced nothing until the violation was forced.
RES_CODE_END    equ     *
                ifgt    RES_CODE_END-RES_DIRS
                error   "res_probe code overlaps RES_DIRS -- shrink it or move the layout"
                endc
                end     res_probe_entry
