* src/harness/res_core.s -- the AGI resource layer on 6809: DIR index, fetch, MMU residency.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE REFERENCE IS tools/volread/, WHICH IS ORACLE-VERIFIED. Every format below is
* transcribed from it, not from the Specs:
*
*   DIR entry, 3 bytes  [dirfile.py, from loader_v2.cpp]
*       volume = byte0 >> 4                      (top nibble)
*       offset = BIG-endian 24-bit & 0x0FFFFF    (low 20 bits)
*       empty  = offset == 0xFFFFF
*       ★★ TEST THE OFFSET, NEVER THE VOLUME: an empty entry is FF FF FF, so its volume nibble
*       reads as 15 and is meaningless. dirfile.py says this in as many words.
*
*   Volume record header, 5 bytes  [volume.py, design §4.2]
*       +0  signature 0x1234, BIG-endian
*       +2  volume byte
*       +3  length, LITTLE-endian
*       +5  payload
*       ★ The two endiannesses are adjacent and opposite. That is not a transcription slip; it
*       is what the oracle reads, and getting it backwards yields a plausible wrong length.
*
* ★★★ §4.2a's SEAM IS THE POINT: callers ask for (type, index) and receive bytes. Nothing
* outside this file learns which volume, which offset, or which version produced them. The
* header length is a PARAMETER (res_hdrlen), not a branch -- so a v3 decoder changes a constant
* and adds a decompressor behind this seam rather than adding a version test to every caller.
* ═══════════════════════════════════════════════════════════════════════════════════════════

* ── layout ────────────────────────────────────────────────────────────────────────
* ★ Sized against MEASURED figures, not guesses:
*     largest single resource across the gated set : 10,428 bytes (KQ3 LOGIC)
*     largest LOGIC working set (call depth 2-3)   :  8,537 bytes (§ vm_resdepth.py)
* ★★ THE THREE BASE ADDRESSES ARE OVERRIDABLE, and the default is P1.3's gated map. A client
* that needs more room for CODE defines them before including this file; res_probe.s does not,
* so P1.3's 1,264-resource gate keeps the exact layout it was verified against.
* ★ vm_probe.s does override them: the VM plus the resource layer plus the HAL does not fit
* below $2000, and the layout assertion at the bottom of the probe is what said so rather than
* letting the code run into the DIR tables.
                ifndef  RES_DIRS
RES_DIRS        equ     $2000           ; four DIR tables, resident (see RES_DIR_* below)
                endc
                ifndef  RES_ARENA
RES_ARENA       equ     $3000           ; the residency arena -- 12 KB
RES_ARENA_END   equ     $6000
                endc
RES_DIR_STRIDE  equ     $0400           ; 1 KB per type: 341 slots, against 216 present max
RES_SLOT        equ     RES_ARENA       ; a depth-0 fetch lands here; kept as a name for AC-2
RES_SLOT_END    equ     RES_ARENA_END
RES_MAXDEPTH    equ     8               ; ★ against a MEASURED maximum LOGIC call depth of 3
RES_WINDOW      equ     $C000           ; ★ THE VOLUME WINDOW: MMU slot 6, remapped per block
RES_WINDOW_SIZE equ     $2000           ; 8 KB, one MMU block
RES_MMU_SLOT    equ     $FFA6           ; the register that maps $C000-$DFFF

RES_LOGIC       equ     0
RES_PICTURE     equ     1
RES_VIEW        equ     2
RES_SOUND       equ     3

* ── state ─────────────────────────────────────────────────────────────────────────
res_hdrlen      fcb     5               ; ★ A PARAMETER, NOT A BRANCH. v3 sets 7 here.
* ★★ A TABLE, ONE ENTRY PER VOLUME, INDEXED BY THE DIR ENTRY'S VOLUME NIBBLE. P1.3 staged one
* volume at a time and a single base was enough; the VM needs every volume resident at once,
* because a logic can call a logic in any volume and there is no point in the cycle where a
* restage would be safe. All three titles' volumes together fit: KQ3 is 651 KB across four
* volumes against 56 free blocks (458 KB) -- so the biggest title does NOT fit, and the sweep
* stages the volumes the gated window actually touches. Stated because "they all fit" was the
* first assumption and it is false for KQ3.
* ★ THE SINGLE-VOLUME CASE IS PRESERVED EXACTLY: res_sweep.lua fills all 16 entries with the
* same base, so indexing by res_vol yields what the old scalar yielded and P1.3's
* 1,264-resource gate is unaffected. Verified by re-running it, not assumed.
res_volbase     rmb     16              ; physical block holding each volume's offset 0
res_slicebase   fdb     0               ; the staged slice's first offset, >>8 (see the probe)
res_len         fdb     0               ; length of the fetched resource
res_vol         fcb     0               ; volume the last fetch came from
res_off         fdb     0               ; low 16 bits of its offset
res_offhi       fcb     0               ; high 4 bits -- the offset is 20 BITS, not 16
res_err         fcb     0               ; 0 = ok; see RES_E_* below
res_curblk      fcb     $FF             ; which physical block is mapped ($FF = none)
res_remaps      fdb     0               ; ★ AC-7: MMU remaps performed, counted not estimated

res_top         fdb     RES_ARENA       ; bump pointer: the arena's first free byte
res_depth       fcb     0               ; how many resources are currently resident
res_marks       rmb     2*RES_MAXDEPTH  ; res_top as it was before each open
res_base        fdb     0               ; where the LAST open put its bytes
res_dest        fdb     RES_ARENA       ; where res_fetch copies to
* ★ ABLATION-ONLY storage. Absent from every shipped build -- see res_fetch's ABL_NOCOPY block.
* ★★★★ EXPLICIT ZEROS, NOT `rmb`, AND THE SLOT HOLDS type+1 -- BOTH ARE BUG FIXES.
* The first version used `rmb`, which reserves space WITHOUT emitting bytes, so the memo booted
* holding whatever RAM held. A slot that happened to match the incoming (type, index) produced a
* FALSE HIT on a FIRST fetch, skipped a copy that was needed, and left the VM interpreting
* garbage: **opcount fell from 184 to 15 and the ablation "measured" 2.076 ms/cycle -- a 98.7%
* saving that was really a VM that had stopped working.**
* ★★★ Storing type+1 makes a zeroed slot unmatchable, because a real type+1 is always >= 1.
* ★★ THE NUMBER WAS CAUGHT BY opcount, NOT BY THE TIMING. The timing looked spectacular and
* plausible; only the instruction count showed the run was not doing the work [L-37 -- instrument
* something that can contradict you].
                ifdef   ABL_NOCOPY
abl_type        fcb     0
abl_idx         fcb     0
abl_memo        fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0     ; 2 * RES_MAXDEPTH, ZEROED
                endc
* ★★★ A SECOND ABLATION LEVEL. ABL_NOCOPY skips the byte-moving loop but still pays res_find's
* DIR lookup and res_ptr's block mapping on every fetch. ABL_NOFETCH skips the WHOLE fetch on a
* repeat, so the difference between the two levels isolates that per-fetch overhead -- which is
* exactly the term AD-83's 1,022-cycles-per-call coefficient was carrying.
* ★ Needs res_len remembered as well, since res_open uses it to push the arena.
                ifdef   ABL_NOFETCH
abn_type        fcb     0
abn_idx         fcb     0
abn_memo        fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0     ; (type+1, idx) per depth
abn_lens        fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0     ; res_len per depth
                endc
res_ceil        fdb     RES_ARENA_END   ; the byte res_fetch must not write at or past

RES_E_EMPTY     equ     1               ; the DIR slot is FF FF FF
RES_E_SIG       equ     2               ; the record's signature was not 0x1234
RES_E_RANGE     equ     3               ; the resource is outside the staged slice
RES_E_BIG       equ     4               ; the payload will not fit the arena at all
RES_E_FULL      equ     5               ; ★ the arena is exhausted AT THIS DEPTH -- see res_open
RES_E_DEPTH     equ     6               ; more than RES_MAXDEPTH resources held at once

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── res_open / res_close ── THE RESIDENCY POLICY, AND IT IS A STACK, NOT A CACHE ──
*
* ★★★ THE POLICY IS CHOSEN FROM A MEASUREMENT, NOT FROM A PREFERENCE. vm_resdepth.py measured
* the LOGIC working set across the pinned titles at 4,679-8,537 bytes with a maximum call depth
* of 3, against 133,428-237,663 bytes of LOGIC in total. ★★ The totals argue for an LRU cache;
* the WORKING SET argues for a stack, and the working set is the number that governs. A
* resource is live exactly while the logic that opened it is running, which is a stack
* discipline by construction -- so an eviction policy would be machinery with nothing to evict.
*
* ★★ WHAT HAPPENS WHEN IT IS EXHAUSTED IS THE PART THAT MATTERS. res_open refuses: it sets
* RES_E_FULL, copies nothing, and does NOT push. ★★★ The failure mode being designed against is
* silent wrong bytes -- an allocator that wrapped, or reused a live level, would return a
* plausible resource belonging to something else, and no byte gate downstream could see it.
*
* ★ The arena is 12 KB against a measured 8,537-byte working set and a 10,428-byte largest
* single resource. It holds the largest resource AND the deepest measured nest; it does not hold
* both at once, which is why exhaustion is a reported error rather than an impossible one.
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE FIT TEST HAPPENS BEFORE THE COPY, AND THAT IS WHY res_fetch TAKES A CEILING. The
* first version called res_fetch and checked the length afterwards -- which is a check that runs
* after the arena has already been overrun. res_dest and res_ceil are set here; res_fetch reads
* the header, compares against the ceiling, and refuses before writing a byte.
res_open:
                pshs    a,b
                lda     res_depth
                cmpa    #RES_MAXDEPTH
                blo     ro_room
                leas    2,s
                lda     #RES_E_DEPTH
                sta     res_err
                rts
ro_room:
                ldd     res_top
                std     res_dest
                std     res_base
                ldd     #RES_ARENA_END
                std     res_ceil
                puls    a,b
                jsr     res_fetch               ; refuses if it will not fit above res_top
                lda     res_err
                bne     ro_fail                 ; ★ no push on failure: depth is unchanged

* push the mark: res_marks[depth] = old res_top, then bump
                ldb     res_depth
                lslb
                ldx     #res_marks
                abx
                ldd     res_top
                std     ,x
                inc     res_depth
                ldd     res_top
                addd    res_len
                std     res_top
                clr     res_err
                rts

* ★ RES_E_BIG at depth 0 means the resource does not fit the arena AT ALL; above depth 0 it
* means the levels already held left too little. They are different facts and AC-5 wants both.
ro_fail:        cmpa    #RES_E_BIG
                bne     ro_out
                tst     res_depth
                beq     ro_out
                lda     #RES_E_FULL
                sta     res_err
ro_out:         rts

* ★ close is the whole eviction policy: drop the level, and the bytes above it are free. No
* scan, no timestamps, no victim choice.
res_close:
                lda     res_depth
                beq     rc_out                  ; closing at depth 0 is a no-op, not an error
                deca
                sta     res_depth
                ldb     res_depth
                lslb
                ldx     #res_marks
                abx
                ldd     ,x
                std     res_top
rc_out:         rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── res_map_block ── map physical block A into the volume window ──────────────────
*
* ★★★ THIS IS A NEW REGISTER OWNER AND IT IS DECLARED, NOT INCIDENTAL. §2N says the HAL owns
* $FF90-$FF9F and $FFB0-$FFBF; the MMU task slots at $FFA0-$FFAF are in the SCAN window and
* owned by nobody, and §2N notes that is exactly where the siblings' real contention lives.
* ★★ There is no HAL mapping API -- HAL_gfx_set_mode remaps $FFA4-$FFA7 for the framebuffer and
* nothing else exists. So storage takes $FFA6 and this is the ONLY routine that writes it.
* ★ When §2N.1's owner ratchet is built, "storage owns $FFA6" is the row to add.
*
* ★ Skips the write when the block is already mapped: the counter then measures REAL remaps,
* which is what AC-7 is about. A counter that ticks on every fetch would report the call rate.
* ═══════════════════════════════════════════════════════════════════════════════════════════
res_map_block:
                cmpa    res_curblk
                beq     res_mb_out              ; already mapped -- no register write, no count
                sta     res_curblk
                sta     RES_MMU_SLOT
                ldd     res_remaps
                addd    #1
                std     res_remaps
res_mb_out:     rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── res_ptr ── point X at staged-volume offset (res_offhi:res_off), mapping as needed
*
* ★★ THE OFFSET IS 20 BITS AND UNSIGNED [L-40]. It is carried as an 8-bit high part and a
* 16-bit low part precisely so that no 16-bit signed compare can ever see it; every comparison
* below is on the BLOCK NUMBER, which is 8-bit unsigned.
* ★ block = (offset - slice_base) >> 13 ; in-block displacement = offset & $1FFF.
* ═══════════════════════════════════════════════════════════════════════════════════════════
res_ptr:
* D = offset low 16, res_offhi = high 4. Subtract the slice base (which is a whole block, so
* its low 13 bits are zero) and split.
                ldd     res_off
                subd    res_slicebase
                sta     res_tmp                 ; A = bits 8..15 of the in-slice offset
                stb     res_tmp+1
                lda     res_offhi
                sbca    #0                      ; borrow from the high nibble
                sta     res_tmphi

* block index = in-slice offset >> 13  == (high4:high8) >> 5
                lda     res_tmphi
                ldb     res_tmp
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb                            ; B = block index within the slice
* ★ the base for THIS resource's volume, not a global one
                pshs    b
                lda     res_vol
                ldx     #res_volbase
                lda     a,x
                adda    ,s+
                jsr     res_map_block

* X = RES_WINDOW + (offset & $1FFF)
                ldd     res_tmp
                anda    #$1F
                addd    #RES_WINDOW
                tfr     d,x
                rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── res_find ── DIR lookup: A = type, B = index -> res_vol / res_off / res_offhi ──
*
* ★ dirfile.py: "Empty slots are RETAINED ... because the INDEX is the resource's identity."
* So the table is indexed directly by resource number, gaps included, and a gap is detected by
* the OFFSET being $FFFFF -- never by the volume nibble.
* ═══════════════════════════════════════════════════════════════════════════════════════════
res_find:
                clr     res_err
                ldx     #RES_DIRS
                pshs    b
                ldb     #0
                tsta
                beq     rf_have
                pshs    a
rf_stride:      leax    RES_DIR_STRIDE,x
                dec     ,s
                bne     rf_stride
                leas    1,s
rf_have:        puls    b                       ; B = resource index
* entry = base + index*3
                pshs    b
                clra
                lslb
                rola                            ; D = index*2
                addb    ,s
                adca    #0                      ; D = index*3
                leas    1,s
                leax    d,x

                lda     ,x                      ; byte0: volume nibble + offset bits 19..16
                tfr     a,b
                lsrb
                lsrb
                lsrb
                lsrb
                stb     res_vol
                anda    #$0F
                sta     res_offhi
                lda     1,x                     ; BIG-endian: byte1 is bits 15..8
                ldb     2,x
                std     res_off

* empty test: offset == $FFFFF, i.e. offhi==$0F and off==$FFFF
                lda     res_offhi
                cmpa    #$0F
                bne     rf_ok
                ldd     res_off
                cmpd    #$FFFF
                bne     rf_ok
                lda     #RES_E_EMPTY
                sta     res_err
rf_ok:          rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── res_fetch ── A = type, B = index -> RES_SLOT, res_len. THE SEAM'S ONLY ENTRY POINT.
*
* ★★★ A caller asks for "LOGIC 3" and gets bytes. It never learns the volume, the offset or
* the header length. That is design §4.2a, and AC-6 checks it by grepping for version tests
* outside this file.
*
* ★★ THE PAYLOAD MAY STRADDLE A BLOCK BOUNDARY. An 8 KB window and a 10,428-byte maximum
* resource guarantee it. The copy therefore re-derives its source pointer whenever it crosses
* the window, rather than assuming a record is contiguous in the CPU's view -- which it is in
* the volume file and is NOT in the mapped window.
* ═══════════════════════════════════════════════════════════════════════════════════════════
res_fetch:
                ifdef   ABL_NOCOPY
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ -DABL_NOCOPY: AN ABLATION, NOT A CHANGE. MEASUREMENT ONLY, NEVER SHIPPED.
*
* AC-4 needs the resource copy's cost by ABLATION rather than by coefficient [L-43], and in a
* VM you normally cannot remove real work without diverging control flow -- deleting the copy
* leaves garbage bytecode and the dispatch then runs a different program.
*
* ★★★ AC-3 IS WHAT MAKES THIS ONE LEGITIMATE. Suppressing the re-fetch in the REFERENCE and
* diffing against the unsuppressed reference gave byte-identical 288-byte state on all 300
* cycles of six titles. **So skipping a REPEAT fetch cannot change what executes**, and this
* ablation removes only the byte-moving loop while every piece of bookkeeping -- res_open's
* push, res_len, res_marks, res_depth, res_close's pop -- runs exactly as before.
*
* ★★ Keyed by DEPTH because the arena is a stack: the same cycle invokes the same logics in the
* same order, so each depth sees the same (type, index) and the same destination address every
* cycle. That is the 99.7% redundancy AC-2 measured, and it is what this skips.
* ★ A first fetch at any depth still copies, so the arena is never read uninitialised.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                sta     abl_type
                stb     abl_idx
                endc
                ifdef   ABL_NOFETCH
* ★★ SKIP THE ENTIRE FETCH on a repeat -- lookup, block mapping and copy. res_len is restored
* from the memo so res_open's arena push is identical to the unablated build.
                sta     abn_type
                stb     abn_idx
                pshs    a,b,x
                ldb     res_depth
                lslb
                ldx     #abn_memo
                abx
                lda     abn_type
                inca
                cmpa    ,x
                bne     abn_miss
                lda     abn_idx
                cmpa    1,x
                bne     abn_miss
                ldb     res_depth
                lslb
                ldx     #abn_lens
                abx
                ldd     ,x
                std     res_len
                puls    a,b,x
                clr     res_err
                rts                             ; ★ ABLATED: no lookup, no mapping, no copy
abn_miss:       lda     abn_type
                inca
                sta     ,x
                lda     abn_idx
                sta     1,x
                puls    a,b,x
                endc
                jsr     res_find
                lda     res_err
                lbne    rfe_out

* ---- header ----------------------------------------------------------------
                jsr     res_ptr
                lda     ,x                      ; signature, BIG-endian
                cmpa    #$12
                lbne    rfe_badsig
                lda     1,x
                cmpa    #$34
                lbne    rfe_badsig
* length is LITTLE-endian at +3
* ★★ THE LOAD ORDER IS THE BYTE SWAP. +3 is the LSB and +4 the MSB, so loading B from +3 and A
* from +4 already assembles D = MSB:LSB -- the value. An `exg a,b` after it was in the first
* version and inverted a conversion that had already happened: LOGIC 0 read as 10019 ($2723)
* where the record declares 8999 ($2327). ★ It survived the signature check, because the
* signature is two independent byte compares and cannot see a length.
                ldb     3,x                     ; B = LSB
                lda     4,x                     ; A = MSB -- D is now the length, do not swap
                std     res_len
* ★★ THE FIT TEST IS AGAINST res_ceil MINUS res_dest, NOT AGAINST THE ARENA SIZE. The space
* that matters is what is left ABOVE the levels already held, which is what makes exhaustion
* depth-aware; a size test would let a depth-3 open overrun a depth-2 resource that is live.
                addd    res_dest
                lbcs    rfe_toobig              ; the destination + length wrapped 16 bits
                cmpd    res_ceil
                lbhi    rfe_toobig              ; UNSIGNED [L-40]

* ---- advance past the header, then copy the payload ------------------------
                ldb     res_hdrlen              ; ★ a PARAMETER: v3 sets 7 and nothing else moves
                clra
                addd    res_off
                std     res_off
                bcc     rfe_nocarry
                inc     res_offhi               ; the offset is 20 bits; carry into the high part
rfe_nocarry:

                ifdef   ABL_NOFETCH
* ★ record the length for this depth, now that res_find has produced it, so a later repeat can
* restore it without re-reading the header.
                pshs    a,b,x
                ldb     res_depth
                lslb
                ldx     #abn_lens
                abx
                ldd     res_len
                std     ,x
                puls    a,b,x
                endc
                ifdef   ABL_NOCOPY
* ★ memo slot for this depth: 2 bytes, (type, index). Hit -> the arena already holds these
* exact bytes from the previous fetch at this depth, so the copy is redundant work.
                ldb     res_depth
                lslb
                ldx     #abl_memo
                abx
* ★ type+1, so a zeroed slot (never fetched at this depth) cannot match -- see the storage note.
                lda     abl_type
                inca
                cmpa    ,x
                bne     abl_miss
                lda     abl_idx
                cmpa    1,x
                beq     rfe_done                ; ★ ABLATED: skip the byte-moving loop entirely
abl_miss:       lda     abl_type
                inca
                sta     ,x
                lda     abl_idx
                sta     1,x
                endc
                ldu     res_dest                ; ★ the CALLER chooses where bytes land
                ldd     res_len
                std     res_cnt                 ; bytes still to copy
                lbeq    rfe_done

* ★★ THE STRADDLING COPY. Each pass maps the block holding the current offset, copies to the
* end of that window or the end of the resource -- whichever comes first -- then advances the
* 20-bit offset by what it copied and repeats. ★ The resource is contiguous in the VOLUME and
* is not contiguous in the CPU's view, which is the whole reason this loop exists.
rfe_copy:
                jsr     res_ptr                 ; maps the block; X = pointer into the window
                lda     res_err
                lbne    rfe_out

* avail = (RES_WINDOW + RES_WINDOW_SIZE) - X
                ldd     #RES_WINDOW+RES_WINDOW_SIZE
                pshs    x
                subd    ,s++
                std     res_run                 ; bytes left in this window (always > 0)

* run = min(avail, remaining)   -- UNSIGNED, both are byte counts [L-40]
                ldd     res_run
                cmpd    res_cnt
                bls     rfe_have
                ldd     res_cnt
                std     res_run
rfe_have:
                ldd     res_run
                std     res_runsave

* ★★★ THE COUNTER LIVES IN A REGISTER AND THE COPY MOVES A WORD AT A TIME. The first version
* was `lda ,x+ / sta ,u+ / ldd res_run / subd #1 / std res_run / bne` -- and AC-7 measured it at
* 30.96 cycles per byte, of which the byte move is 10. ★★ The other 21 were the 16-bit counter
* being loaded from memory, decremented and stored back on EVERY BYTE: two extended accesses per
* byte copied. ★ Measured, not reasoned about -- and the two numbers are reported separately
* [L-54] because "batching the counter" and "moving two bytes at a time" are different changes.
                lsra
                rorb                            ; D = whole words to move
                tfr     d,y
                cmpd    #0
                beq     rfe_tail
rfe_word:       ldd     ,x++
                std     ,u++
                leay    -1,y
                bne     rfe_word
* ★ The odd byte, if the run length is odd. The run is bounded by the window end, so this last
* single byte is still inside the mapped block -- it is a remainder, not an overrun.
rfe_tail:       ldb     res_runsave+1
                bitb    #1
                beq     rfe_copied
                lda     ,x+
                sta     ,u+
rfe_copied:

* remaining -= run
                ldd     res_cnt
                subd    res_runsave
                std     res_cnt

* offset += run, carrying into the 20-bit high part
                ldd     res_off
                addd    res_runsave
                std     res_off
                bcc     rfe_nocarry2
                inc     res_offhi
rfe_nocarry2:
                ldd     res_cnt
                lbne    rfe_copy
rfe_done:       clr     res_err
                rts

rfe_badsig:     lda     #RES_E_SIG
                sta     res_err
                rts
rfe_toobig:     lda     #RES_E_BIG
                sta     res_err
rfe_out:        rts

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── res_decode ── AC-9: split a LOGIC and XOR its message strings, ON THE 6809 ────
*
* ★★★ THE TARGET HAS TO DO THIS, WHICH IS WHY IT IS HERE AND NOT IN THE HOST TOOL. §2P: the
* games run unmodified, so there is no conversion step in which a host could pre-decrypt
* anything. The 6809 receives Sierra's bytes and must make text out of them.
*
* Layout [tools/volread/logic.py, from ScummVM engines/agi/logic.cpp decodeLogic]:
*     u16  bytecode size, LITTLE-endian
*     u8[] bytecode
*     u8   message count
*     u16  messages size, LITTLE-endian
*     u16[] string offsets      ★ RELATIVE TO message_section_pos + 1
*     strings, NUL-terminated, XORed with "Avis Durgan"
*
* ★★ THE XOR COVERS THE STRINGS REGION ONLY -- not the offsets, not the header, not the
* bytecode [global.cpp:311-316]. A whole-resource XOR would decode the text correctly and
* corrupt the bytecode, which is the shape of bug that runs for forty minutes before it bites.
* ★ The key index cycles over 11 from the START OF THE STRINGS REGION, not from the resource.
* ═══════════════════════════════════════════════════════════════════════════════════════════
res_msgs        fcb     0               ; message count the guest parsed
res_msgsz       fdb     0
res_strp        fdb     0
res_endp        fdb     0
res_t1          fdb     0
res_key         fcc     "Avis Durgan"
RES_KEYLEN      equ     11

res_decode:
                clr     res_msgs
                clr     res_err
                ldx     res_base
                lda     1,x                     ; LITTLE-endian: +1 is the high byte
                ldb     ,x
                addd    #2                      ; D = offset of the message section
                std     res_t1
                addd    #3                      ; need count + messages_size to be in range
                cmpd    res_len
                lbhi    rd_none                 ; ★ no message section, not an error
                ldd     res_t1
                leay    d,x                     ; Y -> message section
                lda     ,y
                sta     res_msgs
                lbeq    rd_none                 ; zero messages is legal
                lda     2,y                     ; messages_size, LITTLE-endian at +1
                ldb     1,y
                std     res_msgsz

                ldb     res_msgs
                clra
                lslb
                rola                            ; D = 2 * count
                std     res_t1
                addd    #3
                leau    d,y
                stu     res_strp                ; strings_pos = msg_pos + 3 + 2*count

                ldd     res_msgsz
                subd    #2
                subd    res_t1                  ; D = strings_size
                lbmi    rd_bad
                addd    res_strp
                std     res_endp

* ★ Clamp to the end of the resource. logic.py does `min(strings_pos + strings_size, n)`, and
* the clamp is load-bearing: a declared messages_size may overrun the record.
                ldd     res_base
                addd    res_len
                cmpd    res_endp
                bhs     rd_haveend
                std     res_endp
rd_haveend:
                ldx     res_strp
                ldu     #res_key
                clrb                            ; B = key index, 0..10
rd_xor:         cmpx    res_endp
                bhs     rd_done
                lda     ,x
                eora    b,u
                sta     ,x+
                incb
                cmpb    #RES_KEYLEN
                blo     rd_xor
                clrb
                bra     rd_xor
rd_done:        clr     res_err
                rts
rd_none:        clr     res_err
                rts
rd_bad:         lda     #RES_E_SIG
                sta     res_err
                rts

res_tmp         fdb     0
res_tmphi       fcb     0
res_cnt         fdb     0
res_run         fdb     0
res_runsave     fdb     0
