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

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ THE LOGIC CACHE. The reference has always had one; the port did not, and paid per
* INVOCATION what the reference pays per GAME [L-66].
*
* ★★★ MEASURED [AD-87]: 3.01 LOGIC invocations per cycle on KQ1, 13,715 bytes copied per cycle,
* **3 distinct LOGICs totalling 13,669 B -- 99.7% of the copying was the same bytes again**,
* uniform across six titles.
*
* ★★★★ KEYED ON THE LOGIC INDEX, NOT ON ARENA DEPTH, AND THAT IS A MEASUREMENT.
* AD-86's ablation was depth-keyed -- "is the resource at THIS depth already the one I want?" --
* because the arena is already a stack indexed by depth and it was nearly free. Simulating both
* keyings against the corpus:
*       KQ1  depth-keyed 33.0% hit   index-keyed 99.7%      (misses 605 vs 3)
*       KQ3  depth-keyed 99.0%       index-keyed 99.3%      (misses   6 vs 4)
*       SQ1  depth-keyed 98.7%       index-keyed 99.3%      (misses   8 vs 4)
* ★★ KQ1 alternates two logics at one depth, so depth-keying collapses there. **The ablation's
* 37.5% was therefore a FLOOR measured on the worst case for its own keying**, not the copy's
* full share. Index keying is what the reference does and what the corpus wants.
*
* ★★★★ THE INVALIDATION POLICY, MEASURED NOT ARGUED.
* cycle.py fills `_logic_cache` on miss and there is NO del, pop or clear anywhere in agivm --
* the reference NEVER invalidates. Not even on new_room, which clears the `loaded_*` residency
* SETS: a different concept, being AGI's declared residency and queryable by the game.
* ★★★ But "never" is an OPTIMUM, not a requirement. Two experiments, both entirely in the
* reference with no assembly in either [L-58]:
*       re-load every call vs cached        -> byte-identical, 300 cycles, six titles
*       clear on new_room  vs never-clear   -> byte-identical, 300 cycles, three titles
* **So invalidation is a MEMORY/TIME choice and cannot be a correctness one.**
* ★★ The port clears on new.room, which the reference does not. Safe for the measured reason
* above, and necessary for a bounded arena: the reference's cache is an unbounded Python dict,
* ours is 24 KB, and T-P0-031 measured KQ1's 40-room working set at 85,852 B. One room's set is
* 13,669 B and captures the whole 99.7%, because the redundancy is the same few logics
* recurring WITHIN a room.
*
* ★★★ HOW IT LIVES IN THE EXISTING ALLOCATOR, WITHOUT A SECOND ONE.
* res_marks[depth] records the res_top to restore on close. A cached frame simply records the
* res_top it wants to KEEP:
*       HIT  -> nothing is fetched; mark = res_top unchanged, so the pop is a no-op
*       MISS -> fetch at res_top as usual, advance res_top, then mark = the NEW res_top
* **So res_close is untouched and there is no second allocator.** The only change is which value
* the mark records for a LOGIC frame.
RES_CACHE_MAX   equ     8               ; measured distinct LOGICs in use is 3-4
res_cn          fcb     0               ; entries live
res_ckey        rmb     RES_CACHE_MAX           ; LOGIC index
res_caddr       rmb     2*RES_CACHE_MAX         ; where its bytes are
res_clen        rmb     2*RES_CACHE_MAX         ; how many
res_ccur        fdb     RES_ARENA_END   ; cache allocation pointer, grows DOWN
res_evicted     fcb     0               ; ★ per-open latch: at most one evict-and-retry
res_cevict      fdb     0               ; ★ how many times starvation forced an eviction --
                                        ;   reported, because a HIGH count means the arena is
                                        ;   genuinely too small and the cache is only masking it
res_chits       fdb     0               ; ★ AC-5 evidence the cache is actually hitting
res_cmiss       fdb     0
* ═══════════════════════════════════════════════════════════════════════════════════════════

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
* ★★★ CACHE LOOKUP -- LOGIC only. See the policy block above res_cn.
                lda     ,s                      ; type, without disturbing the saved pair
                cmpa    #RES_LOGIC
                bne     ro_fetch
                ldb     1,s                     ; index
                jsr     res_cache_find
                bne     ro_fetch                ; miss -> the ordinary fetch path
* ── HIT: X = slot. Publish its address and length; nothing is fetched, nothing copied ──
                pshs    x
                tfr     x,d
                lslb
                ldx     #res_caddr
                abx
                ldd     ,x
                std     res_base
                std     res_dest
                puls    x
                tfr     x,d
                lslb
                ldx     #res_clen
                abx
                ldd     ,x
                std     res_len
                ldd     res_chits
                addd    #1
                std     res_chits
                leas    2,s                     ; drop the saved a,b
* ★ mark = res_top UNCHANGED, so res_close's pop restores the same value: a no-op frame.
                ldb     res_depth
                lslb
                ldx     #res_marks
                abx
                ldd     res_top
                std     ,x
                inc     res_depth
                clr     res_err
                rts

ro_fetch:
                clr     res_evicted             ; ★ at most one eviction per open
ro_fetch_retry:
                ldd     res_top
                std     res_dest
                std     res_base
* ★★ THE STACK'S CEILING IS THE CACHE'S FLOOR, not the arena's end. The two allocators grow
* toward each other and this is the line that keeps them apart -- without it the stack would
* fetch straight over cached bytes and the failure would look like a state divergence.
                ldd     res_ccur
                std     res_ceil
                puls    a,b
                pshs    a,b                     ; ★ kept: a LOGIC miss records the index below
                jsr     res_fetch               ; refuses if it will not fit above res_top
                lda     res_err
                beq     ro_fetched

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ EVICT AND RETRY -- THE CACHE MUST BOUND ITSELF, BECAUSE res_core HAS CALLERS WITH NO VM.
*
* ★★★★ THE DEFECT THIS CLOSES. res_ccur grows DOWN and NOTHING EVER MOVED IT BACK except
* res_cache_flush, which is called from vm_interpret_cycle. So the cache's correctness depended
* on a VM running rooms. res_probe has no VM and no rooms: res_ccur walked down until the space
* left above res_top could not hold the next payload, and the gate reported RES_E_BIG at 805 of
* 1,264. **The cache was not full and the arena was not too small -- the cache had eaten the
* arena and had no way to give it back.**
*
* ★★★★ A CACHE THAT CAN CAUSE AN ERROR IS NOT A CACHE, IT IS AN ALLOCATOR WITH A LEAK. That is
* the finding, and it is a LAYERING fact rather than a sizing one: the cache lives in res_core,
* its lifecycle lived in vm_run/vm_cycle, and res_core has three callers with three arena sizes
* (12,288 res_probe / 16,384 p3b / 21,760 vm_probe). Two of them have a VM and the defect was
* invisible in both. **Sizing the arena up would have hidden it again**, at whatever the new
* arena's threshold turned out to be.
*
* ★★★ DEPTH 0 IS THE WHOLE SAFETY ARGUMENT, and it is the SAME argument res_cache_flush already
* makes. Above depth 0 a cached LOGIC's bytes may be the bytes currently executing -- evicting
* there is precisely the fault that halted all nine titles at cycle 0 when the first version
* reset the arena inside `new.room`. So: evict only at depth 0, where no frame is open and
* nothing is running out of the arena. **The unsafe case is not handled more cleverly here; it
* is declined**, and RES_E_FULL is still reported above depth 0 exactly as before.
*
* ★★ vm_new_room's reset is now a POLICY HINT, not a correctness requirement. It still flushes
* at a room change, which is the right moment to drop a working set; but a caller that never
* calls it can no longer starve. ★ Retry is capped at one: after an eviction the arena is at its
* maximum, so a second failure is a genuine RES_E_BIG and must be reported as one.
* ★★★ -DABL_NOEVICT KEEPS THE CACHE AND REMOVES ONLY THE RETRY, which is the arm that separates
* "the cache is wrong" from "eviction is wrong". -DABL_NOCACHE proved the cache is implicated
* (1,264/1,264 clean with it off, 28 LOGIC mismatches with it on) but CANNOT say which half,
* because eviction only ever runs when the cache is on. ★★ With this the sweep halts at
* RES_E_BIG again as it did in T-P0-037, and any volume that COMPLETES before starving reports
* whether its LOGICs are byte-correct without eviction ever having fired.
                ifdef   ABL_NOEVICT
                bra     ro_fail_pop
                endc
                tst     res_evicted
                bne     ro_fail_pop             ; already evicted -- this is a real RES_E_BIG
                tst     res_depth
                bne     ro_fail_pop             ; ★ depth>0: cached bytes may be executing
                lda     res_cn
                beq     ro_fail_pop             ; nothing cached -- eviction would free nothing
                jsr     res_cache_evict
                inc     res_evicted
                ldd     res_cevict
                addd    #1
                std     res_cevict
                clr     res_err
                bra     ro_fetch_retry
* ═══════════════════════════════════════════════════════════════════════════════════════════

ro_fetched:     lda     res_err
                bne     ro_fail_pop             ; ★ no push on failure: depth is unchanged

* ★★★★ A LOGIC MISS RELOCATES ITS BYTES INTO THE CACHE REGION, AND THE FIRST DESIGN DID NOT.
*
* The first attempt kept the fetch where it landed and advanced res_top permanently, recording
* the NEW top as the mark so res_close would not reclaim it. **That is wrong whenever a
* TRANSIENT frame is open below it.** A VIEW opens at res_top; a LOGIC miss inside it allocates
* above the VIEW and pins res_top there; the VIEW then closes and pops res_top back BELOW the
* cached logic -- whose memory is now above the stack pointer and is overwritten by the next
* transient allocation.
* ★★★ THE SYMPTOM NAMED THE CAUSE. KQ1 and PoliceQuest1 passed; KQ2, KQ3, SQ1, SQ2, larry1 and
* the rest failed -- and the passing pair copy **24 and 394 VIEW bytes per cycle** against the
* failing set's **4,273-7,510** [AD-87's table]. The split was exactly VIEW traffic.
*
* ★★ SO THE TWO ALLOCATORS ARE SEPARATED: the stack grows UP from RES_ARENA, the cache grows
* DOWN from RES_ARENA_END, and they cannot interleave. res_ceil keeps the stack below res_ccur.
* ★ The fetch still lands on the stack (that is where the length is discovered) and is then
* relocated down. **One extra copy per MISS** -- 3-4 per room, against the 3 per CYCLE this
* whole change removes.
                lda     ,s
                cmpa    #RES_LOGIC
                bne     ro_push_transient
                ldb     1,s
                leas    2,s
                jsr     res_cache_stash         ; relocate + record; leaves res_base pointing at it
ro_push_after_stash:
                ldb     res_depth
                lslb
                ldx     #res_marks
                abx
                ldd     res_top                 ; ★ the OLD top: the fetch's scratch is reclaimed
                std     ,x
                inc     res_depth
                clr     res_err
                rts

ro_push_transient:
                leas    2,s
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

ro_fail_pop:    leas    2,s
                bra     ro_fail

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
* ── res_cache_find — B = LOGIC index. Z SET and X = slot on a hit, Z clear on a miss ──
* ★ Linear over at most RES_CACHE_MAX entries; the measured live set is 3-4, so the whole scan
* is shorter than one iteration of the copy loop it replaces.
res_cache_find:
                pshs    a,b
* ★★★★ -DABL_NOCACHE TURNS THE CACHE OFF ENTIRELY: every find misses, every stash is a no-op, so
* res_core degrades to the pre-T-P0-036 fetch-every-time path. ★★★ This exists because the gate
* went from RES_E_BIG to LOGIC MISMATCHES when eviction landed, and "the cache caused it" and
* "the cache revealed it" are different claims that a LOGIC-only failure pattern cannot separate
* on its own -- LOGIC is both the cached class AND the class the eviction path touches.
* ★★ An ablation answers it in one run and a reading of the copy loop does not [L-58].
                ifdef   ABL_NOCACHE
                bra     rcf_miss
                endc
                lda     res_cn
                beq     rcf_miss
                ldx     #res_ckey
                clrb
rcf_lp:         lda     ,x+
                cmpa    1,s                     ; the saved index
                beq     rcf_hit
                incb
                cmpb    res_cn
                blo     rcf_lp
rcf_miss:       puls    a,b
                andcc   #$FB                    ; Z clear = miss
                rts
rcf_hit:        clra
                tfr     d,x                     ; X = slot number
                puls    a,b
                orcc    #$04                    ; Z set = hit
                rts

* ── res_cache_stash — B = LOGIC index. Relocate the just-fetched bytes into the cache ──
* ★★ Fetched bytes are at res_base (on the stack) with res_len bytes. Move them DOWN to
* res_ccur - res_len, record the entry, and repoint res_base. ★ If they will not fit, or the
* table is full, this is a NO-OP: the resource is already correctly fetched and simply stays
* uncached, so the next invocation re-copies. **A cache that fails closed degrades to the old
* behaviour**, which is exactly what re-fetch being neutral [AD-87] buys.
res_cache_stash:
                pshs    a,b,x,y,u
                ifdef   ABL_NOCACHE
                bra     rcs_out                 ; ★ nothing is ever cached; see res_cache_find
                endc
                lda     res_cn
                cmpa    #RES_CACHE_MAX
                bhs     rcs_out                 ; table full -- leave it uncached
                ldd     res_ccur
                subd    res_len
                cmpd    res_top
                blo     rcs_out                 ; ★ would collide with the stack -- UNSIGNED
                std     res_ccur                ; commit the downward allocation
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★ COPIED BACKWARD, BECAUSE SOURCE AND DESTINATION CAN OVERLAP AND THE FIRST VERSION DID
* NOT NOTICE. The scratch grows UP from res_top and the cache grows DOWN from res_ccur; whether
* they overlap depends entirely on how big the arena is:
*     vm_probe.s  arena 21,760 B ($6B00-$C000): logic0's scratch ends $8E27, its cache
*                 destination starts $9CD9 -- **no overlap, so the nine-title gate passes**
*     p3b_probe.s arena 16,384 B ($6000-$A000): scratch ends $8327, destination starts $7CD9
*                 -- **~1.4 KB of overlap**
* ★★★ Copying FORWARD into an overlapping region that sits ABOVE the source overwrites bytes the
* read pointer has not reached yet. The integrated probe hung with the CPU bouncing between
* rcs_lp and $0102, executing corrupted memory.
* ★★ **The bug was invisible to every existing gate** because the gate's arena happens to be
* large enough to separate the two regions. It is a property of the ARENA SIZE, not of the code
* under test -- so a client with a smaller arena inherits a latent corruption [L-63's shape: the
* binding constraint was a property of the configuration, not the routine].
* ★ The destination is always ABOVE the source here (the cache is above the stack), so copying
* from the high end downward is always safe and needs no overlap test.
* ★★★★ -DABL_FWDCOPY RESTORES THE DEFECT, ON PURPOSE. AC-7 asks for a test that fails on the OLD
* code, and the existing gates could not see this bug at all -- so the only way to show the new
* test has teeth is to put the old behaviour back behind a flag and watch it fail.
* ★★ A fix whose regression test has never failed is an assertion, not a test [L-62's principle].
                ifdef   ABL_FWDCOPY
                tfr     d,y                     ; ★ THE DEFECT: forward, dest above src
                ldu     res_base
                ldx     res_len
                beq     rcs_done
rcs_lp:         lda     ,u+
                sta     ,y+
                leax    -1,x
                bne     rcs_lp
                else
                addd    res_len
                tfr     d,y                     ; Y = one past the destination's last byte
                ldd     res_base
                addd    res_len
                tfr     d,u                     ; U = one past the source's last byte
                ldx     res_len
                beq     rcs_done
rcs_lp:         lda     ,-u
                sta     ,-y
                leax    -1,x
                bne     rcs_lp
                endc
rcs_done:
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ldd     res_ccur
                std     res_base                ; ★ callers now see the CACHED copy
* ── record: key, address, length ──
                ldx     #res_ckey
                lda     res_cn
                tfr     a,b
                clra
                leax    d,x
                ldb     1,s                     ; ★ saved B: pshs a,b,x,y,u leaves S->A, S+1->B
                stb     ,x
                lda     res_cn
                tfr     a,b
                clra
                lslb
                ldx     #res_caddr
                leax    d,x
                ldd     res_ccur
                std     ,x
                lda     res_cn
                tfr     a,b
                clra
                lslb
                ldx     #res_clen
                leax    d,x
                ldd     res_len
                std     ,x
                inc     res_cn
rcs_out:
                ldd     res_cmiss
                addd    #1
                std     res_cmiss
                puls    a,b,x,y,u
                rts

* ── res_cache_reset / res_cache_flush — DEFERRED, and the deferral is the whole point ──
*
* ★★★★ THE FIRST VERSION RESET THE ARENA IMMEDIATELY AND HALTED ALL NINE TITLES AT CYCLE 0.
* `new.room` is a COMMAND: it is executed BY a logic, so at least one frame is open and the
* running logic's bytes are in the arena. Resetting res_top to RES_ARENA there let the next
* fetch allocate straight over the logic that was still executing -- the VM then read opcode
* $F5 out of its own corrupted bytecode, and `reserr=5` (RES_E_FULL) followed as the wreckage
* spread.
*
* ★★★★ AND THE REFERENCE EXPERIMENT COULD NOT HAVE CAUGHT IT. AD-88 cleared `_logic_cache` on
* new_room in the reference and measured byte-identical state -- correctly, because clearing a
* Python dict does NOT disturb the `lg` object the running interpreter already holds. **In the
* port the bytes ARE the storage.** A policy that is free in the reference is not automatically
* free in a port whose cache and whose working memory are the same memory.
* ★★★ So the experiment validated the POLICY and said nothing about the MECHANISM, and I read it
* as covering both [L-58's limit, stated].
*
* ★★ The fix is to defer: `new.room` only raises a flag, and the flush happens at the top of the
* next interpret_cycle, where res_depth is 0 and nothing is executing out of the arena.
res_cache_pend  fcb     0               ; 1 = flush before the next cycle's first bind

res_cache_reset:
                lda     #1
                sta     res_cache_pend
                rts

* ── res_cache_evict — drop the whole cache NOW. Caller must guarantee res_depth = 0 ──
* ★★★ The one home for "give the arena back" (2F). res_cache_flush is the DEFERRED entry, called
* from vm_interpret_cycle; ro_fetch's starvation retry is the IMMEDIATE entry, called at depth 0.
* Both do the same two stores, and having them written twice is how the two paths would drift.
* ★★ No victim choice, no timestamps: the working set is 3-4 entries and a starving fetch needs
* the whole region, not a slot.
res_cache_evict:
                clr     res_cn
                ldd     #RES_ARENA_END
                std     res_ccur
                rts

* ★ Called from vm_interpret_cycle, outside every frame. Safe to move res_top here and only here.
res_cache_flush:
                lda     res_cache_pend
                beq     rcx_out
                clr     res_cache_pend
                ldd     #RES_ARENA
                std     res_top
                jsr     res_cache_evict         ; ★ one home: clears res_cn, res_ccur = ARENA_END
rcx_out:        rts

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
