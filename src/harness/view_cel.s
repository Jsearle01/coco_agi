* src/harness/view_cel.s -- VIEW cel decoding on the 6809: header, RLE, mirroring.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ TRANSCRIBED FROM tools/agivm/view.py's _unpack_cel(), whose own header says its index
* arithmetic mirrors the oracle's POINTER arithmetic exactly. That is the thing being
* reproduced -- not "an RLE decoder that produces the same picture", but the same walk, because
* the mirrored case is expressed as two adjustment constants and a running pointer and any
* tidier formulation is a different program with different edge cases.
*
* ★★ MIRRORING IS NOT "FLIP THE CEL", and this is the trap view.py warns about at its own top.
* The cel header's transparency/mirror byte carries BOTH a mirror bit ($80) AND the loop number
* the cel originally belongs to (bits 4-6). **A cel is mirrored only when that recorded loop is
* NOT the loop being decoded.** Loops share cel data: the same bytes decode un-mirrored in
* their home loop and mirrored in the borrowing loop. Testing bit 7 alone mirrors the original
* too, and the sprite faces the wrong way in half its loops.
*
* ★ VERSION 0x2230 puts the mirror information in the LOOP header instead, with a TWO-bit loop
* number. Not reproduced here: the pinned corpus is 0x2440/0x2917 and celcheck reports the
* detected version per title, so a 0x2230 title would be visible rather than silently wrong.
* **Declared, not omitted** -- vc_decode_cel sets vc_err rather than guessing.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★ WIDTH IS A BYTE AND THE PIXEL INDEX IS NOT. width*height reaches 255*255 = 65,025, and the
* mirrored row advance is `p += width * 2` -- up to 510. **Every pointer here is 16-bit and
* every adjustment is a 16-bit signed add**, which is the T-P0-027 lesson (a value fits a byte;
* a product or difference of two does not) applied before it could bite rather than after.
* ★ adjust_pre is 0 or -1 and adjust_after is 1 or 0; they are held as 16-bit words so the add
* is one `addd` with no sign-extension step to get wrong.
* ═══════════════════════════════════════════════════════════════════════════════════════════

VC_E_OK         equ     0
VC_E_ZEROCEL    equ     1               ; width and height both zero
VC_E_EMPTY      equ     2               ; zero compressed bytes
VC_E_CHUNK      equ     3               ; chunk length > remaining width
VC_E_TRUNC      equ     4               ; ran out of compressed data mid-cel
VC_E_VERSION    equ     5               ; ★ 0x2230 loop-header mirroring -- declared unhandled
VC_E_BIG        equ     6               ; decoded cel will not fit VC_CEL_MAX

* ── inputs, set by the caller ─────────────────────────────────────────────────────
vc_view         fdb     0               ; -> the VIEW resource's first byte
vc_loop         fcb     0               ; loop number to decode
vc_cel          fcb     0               ; cel number within that loop
vc_dest         fdb     0               ; -> where the decoded pixels go

* ── outputs ───────────────────────────────────────────────────────────────────────
vc_w            fcb     0
vc_h            fcb     0
vc_key          fcb     0               ; clear key (transparency index)
vc_mir          fcb     0               ; 1 = this cel is mirrored IN THIS LOOP
vc_err          fcb     0
vc_nloops       fcb     0
vc_ncels        fcb     0

* ── working state ─────────────────────────────────────────────────────────────────
vc_p            fdb     0               ; the running destination index [16-bit, always]
vc_pre          fdb     0               ; adjust_pre  : 0 or -1
vc_post         fdb     0               ; adjust_after: 1 or 0
vc_remw         fdb     0               ; remaining_width
vc_remh         fdb     0               ; remaining_height
vc_len          fdb     0               ; chunk_len
vc_col          fcb     0               ; colour of the current chunk
vc_src          fdb     0               ; -> next compressed byte (a PAYLOAD OFFSET if windowed)
* ★★★ vc_srcend MEANS TWO DIFFERENT THINGS AND THE FLAG SAYS WHICH [T-P0-136]: one past the last
* byte of the resource in the flat build, and the payload LENGTH in the windowed one. Stated here
* because a caller that gets it wrong produces a decoder that walks off the resource quietly.
vc_srcend       fdb     0               ; flat: end address | windowed: payload length
                ifdef   VC_SRC_WINDOWED
vc_remsrc       fdb     0               ; ★ bytes left before truncation; the windowed bound
                endc
vc_loopoff      fdb     0               ; loop offset, absolute
vc_tested       fdb     0               ; ★ AC-5: source pixels this cel produced
vc_w16          fdb     0               ; width, zero-extended, for the 16-bit adds

* ═══════════════════════════════════════════════════════════════════════════════════
* ── vc_decode_cel ── decode vc_view[vc_loop][vc_cel] into vc_dest ─────────────────
*
* Layout [view.py decode_view]:
*     +2            loop count
*     +5 + n*2      loop offset n, LITTLE-endian, relative to the RESOURCE base
*     loop+0        cel count
*     loop+1 + m*2  cel offset m, LITTLE-endian, relative to the LOOP
*     cel+0/+1/+2   width / height / transparency-and-mirror
*     cel+3...      the compressed data
* ★ The cel offset is relative to the LOOP, not to the resource. Adding it to the wrong base
* yields a plausible width and height from the middle of the pixel data -- P4.5 recorded that
* trap when it parsed the same header for loop and cel COUNTS; this is the same arithmetic.
* ═══════════════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE UNPACK IS ONE ROUTINE WITH TWO ENTRY POINTS SINCE T-P0-105.
*
*   vc_decode_begin  parse the cel header; leave vc_src, vc_w/h, vc_key, vc_mir and vc_remh set
*   vc_decode_row    unpack exactly ONE row into vc_dest (which is then a WIDTH-sized buffer)
*   vc_decode_cel    begin, clear the whole destination, then loop rows -- the ORIGINAL contract
*
* ★★★★★ WHY: p3b's staging buffer was 4,784 bytes at $5300 and the arena starts at $6000, so a
* cel wider-and-taller than the margin overwrote the VIEW it was decoding FROM [P6.49]. **The
* oracle has no shared staging buffer at all** -- `unpackViewCelData` does `new byte[w*h]` per cel
* and keeps it with the loaded VIEW [view.cpp:357-370 at the pin] -- so the buffer was ours, and a
* row is all the compositor ever needs at once.
*
* ★★★★ TWO ENTRY POINTS AND ONE UNPACK, NOT TWO UNPACKS [§2F]. The cel gate compares a whole
* decoded bitmap and must keep doing so; p3b wants a row at a time. **Duplicating the RLE walk to
* serve both is how the two would drift apart on exactly one opcode**, which is the argument this
* file already makes about skip lengths.
*
* ★★★ vc_decode_cel's behaviour is UNCHANGED, including on the error paths: it still clears the
* whole destination up front, so a cel that raises VC_E_TRUNC half way leaves the same zeroed tail
* it always did. The per-row clear below then re-clears rows it has already cleared, which costs a
* pass in the gate and keeps the two paths exactly equivalent.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHAT P6.50 TRADED, PRICED AT LAST [T-P0-143 §4A, and it was never priced until here].
* ★★★★ The trade above is real and was the right call: it bought back 4,784 bytes and closed a
* corruption. ★★★★★ WHAT IT SOLD was the oracle's *residency* -- `unpackViewCelData` decodes a cel
* ONCE and the bytes live with the VIEW, and row-at-a-time decodes it again every time it is drawn.
* ★★★ vc_decode_row is 26.6% of the drawing stage [P6.87], so the sold side is worth measuring.
*
* ★★★★★ MEASURED, over 109 steady castle cycles (room 1, cycles 11-119):
*   decodes/cycle             3.98 moving, 3.11 standing (P6.88's skip takes 0.89 standing, 0.02 moving)
*   SAME CEL AS LAST CYCLE    0.7% moving, 25.0% standing
*   distinct cels in flight   20 moving (three loops sweeping: 6 + 5 + 9 cels, one step per cycle)
*   LRU hit rate, 1..14 slots 25.1% moving -- FLAT, because a cyclic sweep is LRU-pessimal
*   LRU hit rate, 20 slots    95.4% moving, and the 20 cels are 3,906 bytes
*
* ★★★★★ SO THE RE-DECODE IS ~95% WASTE AND BUYING IT BACK COSTS 3,906 BYTES, which region A does
* not have -- `-IfRec` has not assembled since P6.88 and MAP_INPUT's tail is P3_KQ's. **The cache
* is not refuted; it is unplaceable until the map ruling** [T-P0-143 §6, trigger 2].
*
* ★★★★★ AND THE ADJACENCY RATE WOULD HAVE KILLED IT WRONGLY. 0.7% moving reads as "cels change
* every cycle, there is nothing here" -- the exact §6 trigger the dispatch wrote -- while the same
* trace collapses 3.98 decodes/cycle to 0.18 with enough slots. ★★★★ A sweep has NO distance-1
* reuse and TOTAL distance-N reuse [§2H: the first mechanism was real and was not the governing one].
*
* ★★★★★ ONE PART OF IT NEEDS NO STORAGE AT ALL, and it is the whole of the 1-slot rate: **all 109
* of the 1-slot hits are two CONSECUTIVELY-STAGED sprites carrying the identical (view, loop, cel)**
* -- room 1's two alligators share view 107 and swim in lockstep (x=147,y=161,prio 14 and
* x=104,y=135,prio 12: two objects, not one staged twice). ★★★ Decoding each row once and blitting
* it to both destinations reuses THIS buffer, changes no decoded byte, and keeps the cel gate's
* subject intact. ★★ Recorded, not taken: §6 stopped this task at the census.
* ═══════════════════════════════════════════════════════════════════════════════════════════
vc_decode_begin:
                clr     vc_err
                ldd     #0
                std     vc_tested

                ldx     vc_view
                ifdef   VC_SRC_WINDOWED
                leax    2,x
                jsr     vc_rd8
                else
                lda     2,x
                endc
                sta     vc_nloops
                lda     vc_loop
                cmpa    vc_nloops
                blo     vc_dc_loopok
                lda     #VC_E_TRUNC
                sta     vc_err
                rts
vc_dc_loopok:
* loop_offset = le16(view + 5 + loop*2) + view
                ldb     vc_loop
                lslb
                clra
                addd    #5
                addd    vc_view
                tfr     d,x
                jsr     vc_le16                 ; D = the loop's offset, little-endian
                addd    vc_view
                std     vc_loopoff

                tfr     d,x
                ifdef   VC_SRC_WINDOWED
                jsr     vc_rd8
                else
                lda     ,x
                endc
                sta     vc_ncels
                lda     vc_cel
                cmpa    vc_ncels
                blo     vc_dc_celok
                lda     #VC_E_TRUNC
                sta     vc_err
                rts
vc_dc_celok:
* cel_offset = le16(loop_offset + 1 + cel*2) + LOOP_OFFSET   ★ loop base, not view base
                ldb     vc_cel
                lslb
                clra
                addd    #1
                addd    vc_loopoff
                tfr     d,x
                jsr     vc_le16
                addd    vc_loopoff
                tfr     d,x                     ; X -> the cel header

                ifdef   VC_SRC_WINDOWED
                jsr     vc_rd8
                sta     vc_w
                clra
                ldb     vc_w
                std     vc_w16
                leax    1,x
                jsr     vc_rd8
                sta     vc_h
                leax    1,x
                jsr     vc_rd8                  ; transparency + mirror byte
                leax    -2,x                    ; ★ X back at the cel header, as the flat path
                else
                lda     ,x
                sta     vc_w
                clra
                ldb     vc_w
                std     vc_w16
                lda     1,x
                sta     vc_h
                lda     2,x                     ; transparency + mirror byte
                endc
                tfr     a,b
                andb    #$0F
                stb     vc_key

* ★★ mirrored = bit 7 set AND the recorded loop != the loop we are decoding. Both halves.
                clr     vc_mir
                bita    #$80
                beq     vc_dc_nomir
                lsra
                lsra
                lsra
                lsra
                anda    #$07                    ; the cel's HOME loop, 3 bits
                cmpa    vc_loop
                beq     vc_dc_nomir             ; home loop: draw it as authored
                lda     #1
                sta     vc_mir
vc_dc_nomir:
                lda     vc_w
                bne     vc_dc_sized
                lda     vc_h
                bne     vc_dc_sized
                lda     #VC_E_ZEROCEL
                sta     vc_err
                rts
vc_dc_sized:
* ★ refuse rather than overrun: the destination is a fixed buffer in every client.
                lda     vc_w
                ldb     vc_h
                mul                             ; D = width * height
                cmpd    #VC_CEL_MAX
                bls     vc_dc_fits
                lda     #VC_E_BIG
                sta     vc_err
                rts
                ifdef   VC_SRC_WINDOWED
* ★ One home for the windowed truncation exit; the flat path has no caller for it.
vc_dc_trunc:    lda     #VC_E_TRUNC
                sta     vc_err
                rts
                endc
vc_dc_fits:
                std     vc_tested               ; ★ AC-5: every source pixel this cel carries
                leax    3,x
                ifdef   VC_SRC_WINDOWED
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE CURSOR IS OPENED HERE, AND THE TRUNCATION BOUND BECOMES A COUNT [T-P0-136].
* The flat path's bound is `vc_src < vc_srcend`, a compare of two CPU addresses. Through the
* window vc_src is a CPU address inside an 8 KB aperture and the resource's end is a PAYLOAD
* offset -- **the two are not comparable, and comparing them anyway is how a decoder walks off a
* resource while believing it is inside one.** So the bound is carried as a remaining-byte count,
* which is addressing-independent by construction.
* ★★★ vc_srcend IS THE PAYLOAD LENGTH under this flag, not an end address: the caller already
* has it from res_locate, and the contract change is stated in the caller [p3b_probe.s].
                stx     vc_src                  ; payload offset of the compressed data
                pshs    x
                ldd     vc_srcend               ; = the payload length
                subd    ,s++                    ; - where this cel starts
                std     vc_remsrc
                bls     vc_dc_trunc             ; ★ a cel starting at or past the end is corrupt
                ldd     vc_src
                jsr     res_cseek
* ═══════════════════════════════════════════════════════════════════════════════════════════
                else
                stx     vc_src                  ; the compressed data starts here
                endc
* ★★ THE PER-CEL CONSTANTS. adjust_pre/adjust_after depend only on the mirror bit, so they are
* settled once here; vc_p is per-ROW and is set by vc_decode_row.
                ldd     #0
                std     vc_pre                  ; adjust_pre = 0
                ldd     #1
                std     vc_post                 ; adjust_after = 1
                lda     vc_mir
                beq     vc_db_nomir
                ldd     #-1
                std     vc_pre                  ; adjust_pre = -1
                ldd     #0
                std     vc_post                 ; adjust_after = 0
vc_db_nomir:
                clra
                ldb     vc_h
                std     vc_remh
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── vc_decode_row ── ONE row into vc_dest. The unpack, against _unpack_cel() ─────
*
* ★★★★★ THE ROW-SCOPE DERIVATION, WHICH IS THE ONE THING IN THIS TASK THAT HAD TO BE RE-DERIVED
* RATHER THAN MOVED. vc_p was an offset into the WHOLE bitmap; it is now an offset into ONE row.
*
*   NOT MIRRORED  p starts at 0 each row; pre=0, post=+1; runs fill forward.
*                 OLD: at the end of row r, p = (r+1)*width -- the start of row r+1.
*                 NEW: p = 0 with vc_dest advanced a row.  **Same address.**
*
*   MIRRORED      p starts at WIDTH each row; pre=-1, post=0; a run of length n does `p -= n`
*                 then fills FORWARD from p, so the walk moves right-to-left across the row.
*                 OLD: at the end of mirrored row r the walk has reached p = r*width, and the
*                      row advance is `p += width*2` -- two widths on, because the walk crossed
*                      one row backwards and must land at the END of the next.
*                 NEW: **that advance IS the reset.** p = width, with vc_dest advanced a row.
*                      (r+2)*width relative to the old base is exactly `width` relative to the
*                      new one.  **Same address, and adjust_pre/adjust_after keep their meaning
*                      inside a 255-byte window that they had inside a 4,784-byte one.**
*
* ★★★ TRANSCRIPTION vs OURS [§2.1]: the chunk decode, the zero-byte row end, the mirrored
* backward walk and both adjustment constants are TRANSCRIBED from view.py/_unpack_cel and are
* unchanged. **The row SCOPE is ours** -- the oracle has no row buffer to scope to, because it
* allocates the whole bitmap. This is a port decision, not a reading of AGI.
* ═══════════════════════════════════════════════════════════════════════════════════════════
vc_decode_row:
* ★ The row is cleared before it is unpacked, for the reason the whole buffer used to be: a chunk
* of length 0 writes nothing and a row that ends early leaves its tail untouched. **Per row now,
* because the buffer IS a row** -- and without it those bytes would be the PREVIOUS row's.
                ldx     vc_dest
                ldd     vc_w16
                tfr     d,y
vc_dc_clr:      clr     ,x+
                leay    -1,y
                bne     vc_dc_clr

                ldd     #0
                std     vc_p
                ldd     vc_w16
                std     vc_remw
                lda     vc_mir
                beq     vc_dc_go
                ldd     vc_w16
                std     vc_p                    ; mirrored: the walk starts at the row's END

vc_dc_go:
                ldd     vc_remh
                lbeq    vc_dc_done
vc_dc_row:
* cur = comp[pos++]  -- with the truncation check the reference raises on
                ifdef   VC_SRC_WINDOWED
* ★★★ THE COUNT IS THE BOUND, AND res_cnext IS THE READ. The cursor re-maps itself whenever the
* walk crosses the aperture OR somebody else takes slot 6 -- and in the compositor somebody does,
* every time a pixel is written [plane_win.s]. Neither is visible here.
                ldd     vc_remsrc
                bne     vc_dc_haveb
                lda     #VC_E_TRUNC
                sta     vc_err
                rts
vc_dc_haveb:
                subd    #1
                std     vc_remsrc
                jsr     res_cnext
                else
                ldx     vc_src
                cmpx    vc_srcend
                blo     vc_dc_haveb
                lda     #VC_E_TRUNC
                sta     vc_err
                rts
vc_dc_haveb:
                lda     ,x+
                stx     vc_src
                endc
                sta     vc_cur                  ; ★ the row-end test below is on THIS byte
                tsta
                bne     vc_dc_run

* ---- cur == 0: colour = clear key, chunk = the REST of the row ------------------
                lda     vc_key
                sta     vc_col
                ldd     vc_remw
                std     vc_len
                bra     vc_dc_emit

* ---- cur != 0: colour = cur >> 4, chunk = cur & 15 ------------------------------
vc_dc_run:
                tfr     a,b
                lsra
                lsra
                lsra
                lsra
                sta     vc_col
                andb    #$0F
                clra
                std     vc_len
                cmpd    vc_remw
                bls     vc_dc_emit
                lda     #VC_E_CHUNK             ; ★ the reference raises here; so do we
                sta     vc_err
                rts

vc_dc_emit:
                ldd     vc_len
                lbeq    vc_dc_after             ; chunk_len == 0: write nothing
                cmpd    #1
                bne     vc_dc_bulk

* ---- chunk_len == 1: p += adjust_pre ; raw[p] = colour ; p += adjust_after -------
                ldd     vc_p
                addd    vc_pre
                std     vc_p
                addd    vc_dest
                tfr     d,x
                lda     vc_col
                sta     ,x
                ldd     vc_p
                addd    vc_post
                std     vc_p
                bra     vc_dc_after

* ---- chunk_len > 1: mirrored walks BACKWARD before writing forward --------------
* ★★ `if mirrored: p -= chunk_len` THEN a forward fill, and NO post-advance. The fill is
* always left-to-right in memory; mirroring changes where the run STARTS, not its direction.
vc_dc_bulk:
                lda     vc_mir
                beq     vc_dc_fwd
                ldd     vc_p
                subd    vc_len
                std     vc_p
vc_dc_fwd:
                ldd     vc_p
                addd    vc_dest
                tfr     d,x
                ldd     vc_len
                tfr     d,y
                lda     vc_col
vc_dc_fill:     sta     ,x+
                leay    -1,y
                bne     vc_dc_fill
                lda     vc_mir
                bne     vc_dc_after             ; mirrored: p already moved
                ldd     vc_p
                addd    vc_len
                std     vc_p

vc_dc_after:
                ldd     vc_remw
                subd    vc_len
                std     vc_remw

* ---- a ZERO byte ends the row, and only a zero byte ------------------------------
* ★★ The test is on `cur`, the byte read at the top of this iteration -- NOT on whether the
* row filled up. view.py ends a row on `if cur == 0`, so a row whose runs happen to sum to the
* full width does NOT advance until an explicit zero arrives. Testing remaining_width == 0
* instead would advance early on exactly those cels and drift for the rest of the resource.
                lda     vc_cur
                lbne    vc_dc_go2
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE ROW ENDS AND SO DOES THIS CALL. The old code reset vc_remw, decremented vc_remh and
* carried vc_p into the next row -- adding width*2 when mirrored. **All three of those are now
* the next call's job**, and the mirrored advance has become vc_decode_row's `p = width` reset.
* ★★★ vc_remh is decremented HERE rather than by the caller, so "rows still to decode" has one
* home and the pull loop cannot disagree with the decoder about how far through the cel it is.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ldd     vc_remh
                subd    #1
                std     vc_remh
                clr     vc_err
                rts
vc_dc_go2:
                ldd     vc_remh
                lbne    vc_dc_row
vc_dc_done:
                clr     vc_err
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── vc_decode_cel ── the ORIGINAL whole-cel contract, for the cel gate ───────────
* ★★★★ Unchanged behaviour, expressed over the two entry points above. The gate compares a whole
* decoded bitmap against the oracle's, so this must keep producing one -- and it must keep
* clearing the WHOLE destination first, so a cel that raises mid-way leaves the same zeroed tail.
* ★★ vc_dest is saved and restored: this walks it a row at a time, and a caller that set it once
* would otherwise find it pointing at the end of the bitmap.
vc_decode_cel:
                jsr     vc_decode_begin
                lda     vc_err
                beq     vc_wc_ok
                rts
vc_wc_ok:
                ldx     vc_dest
                pshs    x
                ldd     vc_tested
                tfr     d,y
vc_wc_clr:      clr     ,x+
                leay    -1,y
                bne     vc_wc_clr
vc_wc_loop:
                ldd     vc_remh
                beq     vc_wc_done
                jsr     vc_decode_row
                lda     vc_err
                bne     vc_wc_fail
                ldd     vc_dest
                addd    vc_w16
                std     vc_dest
                bra     vc_wc_loop
vc_wc_done:
                puls    x
                stx     vc_dest
                clr     vc_err
                rts
vc_wc_fail:     puls    x
                stx     vc_dest
                rts

vc_cur          fcb     0               ; the compressed byte driving this iteration

* ── vc_le16 ── X -> two little-endian bytes; returns D ───────────────────────────
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ TWO READERS, ONE SEAM [T-P0-136]. Under -DVC_SRC_WINDOWED every value this decoder reads
* out of the VIEW comes through the VOLUME WINDOW instead of out of a copy in the arena, and
* vc_view / vc_loopoff / vc_src are PAYLOAD OFFSETS rather than CPU addresses. All the arithmetic
* around them is unchanged, because it is all relative to the payload base either way.
* ★★★★ THE HEADER READS USE res_peek AND THE STREAM USES res_cnext, and that split is the whole
* design [§4A]. res_peek maps per byte -- straddle-proof by construction, ~90 CPU cycles -- which
* is right for the ten bytes vc_decode_begin reads and wrong for a cel's compressed stream, up to
* 1,552 bytes in the corpus. The cursor maps once and re-maps on crossing.
* ★★★ THE FLAT PATH IS UNTOUCHED, and that is deliberate: cel_probe and comp_probe decode from
* host-staged memory and neither defines the flag, so **the cel and comp gates assemble the same
* bytes they always have** and their 9,193/9,193 and 124/124 stay claims about the same program.
                ifdef   VC_SRC_WINDOWED
* vc_rd8: X = payload offset -> A = that byte. X is preserved; res_peek clobbers it.
vc_rd8:
                pshs    x
                tfr     x,d
                jsr     res_peek
                puls    x
                rts

* vc_le16: X = payload offset -> D = the little-endian 16-bit value there.
* ★ Each byte through its own mapping, so a field split across the boundary is read correctly --
* the same property res_peek gives the VM's header reads [T-P0-130, view_straddle.py].
vc_le16:
                pshs    x
                bsr     vc_rd8                  ; A = LSB
                pshs    a
                leax    1,x
                bsr     vc_rd8                  ; A = MSB
                puls    b                       ; B = LSB -> D = MSB:LSB
                puls    x
                rts
                else
vc_le16:
                ldb     ,x
                lda     1,x
                rts
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ★★ 6,144 AND THE FIGURE IS MEASURED, NOT CHOSEN. This was 4,096 on the strength of P5.1's
* "peak single cel area 3,256 B across the gated set" -- and six cels refused with VC_E_BIG on
* the first full sweep. Measured over the oracle's own manifests for five titles, the corpus
* maximum is **4,784 bytes (46x104, Kingquest3)**; larry1 carries an 82x56 at 4,592.
* ★ P5.1's figure was taken over a 600-cycle window of two titles, so it was true of what it
* measured and 47% below the corpus. A cel bound is a property of the CORPUS, not of a run.
* ★★ The refusal is what surfaced it: VC_E_BIG reports rather than overrunning the buffer, so
* six wrong cels became six named errors instead of silent corruption of whatever follows.
VC_CEL_MAX      equ     6144
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ VC_ROW_MAX IS SIZED FROM THE FORMAT, NOT FROM THE CORPUS, AND THAT IS THE WHOLE LESSON
* OF THE DEFECT THIS REPLACES [T-P0-105].
*
* ★★★★★ VC_CEL_MAX above is 6,144 because the CORPUS maximum is 4,784, and 4,784 turned out to be
* a real cel -- Kingquest3 view 64 loop 0 cel 0 -- that overran the arena by 1,456 bytes. **A
* corpus maximum is a real input, not a safety margin** [P6.49].
* ★★★★ A cel's WIDTH is a single byte in the resource, so **255 is the format's own ceiling** and
* no census can move it. Measured across seven titles the widest row is 115 (Kingquest2 view 130,
* SpaceQuest-1 view 200); this is 255 because that is what the format permits, and the 140 bytes
* of difference are the cheapest insurance in this file.
VC_ROW_MAX      equ     255             ; ★ a cel width is a BYTE; this cannot be exceeded
