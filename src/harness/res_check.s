* ═══════════════════════════════════════════════════════════════════════════════════════════
* res_check.s -- -DRES_CHECKSUM: DO THE RESIDENT BYTES STILL MATCH WHAT WAS LOADED? [T-P0-103]
*
* ★★★★★ THE GAP THIS CLOSES, IN P6.46's OWN WORDS: *"no gate looks at resource bytes after a
* bind."* Every instrument in this project checks what the VM DID. None checked whether what it
* READ was what was loaded -- and for twenty tasks the opcode counters were incrementing a resident
* LOGIC, which took eight tasks to find because the only way to see it was to read the bytes.
*
* ★★★★★ IT IS A GATE INSTRUMENT, NOT A SHIPPED GUARD. Behind -DRES_CHECKSUM, off by default, every
* shipped artifact byte-identical. **So cost is not the design constraint**: this checksums whole
* resources rather than sampling them, because a sampled checksum is a checksum that can miss the
* thing it was built for.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ WHERE THE BASELINE IS TAKEN, AND WHY IT IS RIGHT RATHER THAN CONVENIENT.
*
* ★★★★ SOME RESOURCE BYTES CHANGE LEGITIMATELY. res_decode XORs a LOGIC's message section IN
* PLACE, once, on a fresh open [vm_run.s:83-91]. **A baseline taken before it fires on every LOGIC
* and the instrument is useless on its first run.**
*
* ★★★★★ SO THE BASELINE IS TAKEN AT vm_run.s's `vbl_nodec` -- the point where a LOGIC's bytes are
* in their final form ON BOTH PATHS. That is not a convenience: it is **the seam the resource gate
* is already aligned to**, chosen four phases earlier for the same reason. agi.cpp:456 takes the
* oracle's raw dump "immediately after loadVolumeResource() returns and BEFORE any decode", and
* the decode is `if (~flags & RES_LOADED)` -- **once per load, by the oracle's own structure**
* [P1.1, T-P0-084h §4A]. A resource decoded twice is a defect in either implementation, so "after
* exactly one decode" is a well-defined instant and not a moving target.
*
* ★★★★ AND THE CARRY FLAG ALREADY DISTINGUISHES THE TWO CASES, so this needs no new signal:
* res_open returns **C set = served from cache** (bytes already decoded, baseline exists -> VERIFY)
* and **C clear = fresh fetch** (decode runs, bytes are new -> NOTE). §2F: one home for that fact,
* and it is res_core's, not this file's.
*
* ★★★★★ THE BLIND SPOTS, STATED IN THE SAME BREATH AS THE DESIGN [L-121]:
*   1. **A corruption between the fetch and the baseline is invisible** -- it is baselined AS the
*      truth. The window is res_fetch's copy plus res_decode, inside one call, with no VM running.
*      Small, but not empty, and nothing here can see into it.
*   2. **A resource nobody notes is not watched.** LOGIC (every bind) and VIEW (every composite)
*      are; PICTURE and SOUND are not, because no call site notes them. That is a coverage
*      statement, not a safety one, and the gates.manifest row says so.
*   3. **A checksum says THAT it changed, never WHAT changed it.** The offsets come from the host
*      diffing the dumped bytes against the game file [res_copy_diff.py] -- which is exactly how
*      P6.46's answer was actually reached, by hand, and this makes it a tool.
*   4. **A stale entry is skipped, not reported.** A cached LOGIC that is evicted or relocated no
*      longer describes live memory; the sweep asks res_cache_find first and skips what it cannot
*      confirm, counting the skips. ★★ A sweep that reported those would produce confident false
*      positives -- §2W.3's "a diagnostic that cannot be wrong does not measure", pointed the other
*      way -- and a sweep that skipped them silently would be L-88's scoped-by-accident comparison.
* ═══════════════════════════════════════════════════════════════════════════════════════════
                ifdef   RES_CHECKSUM

RCK_MAX         equ     16              ; watched resources; the cache is 8 and stack depth is 8
RCK_ROWS        equ     8               ; mismatch rows kept
RCK_ROWSZ       equ     14

* ★ Site codes, so a row says WHICH check caught it rather than only that one did.
RCK_AT_BIND     equ     1               ; a later bind of a resident LOGIC (cache hit)
RCK_AT_CLOSE    equ     2               ; a transient, verified before it is released
RCK_AT_SWEEP    equ     3               ; the end-of-run sweep

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE STATE LIVES IN MAP_COVERAGE, NOT IN THE CODE IMAGE, AND THE REASON IS MEASURED.
* 268 bytes of table in region A is 268 bytes this probe does not have: the text arms had 1,622
* free and the **cel arm has EIGHT** (code ends $52F8, CP_CEL starts $5300). Putting the tables
* inline refused the cel build outright, which is how this was found rather than reasoned.
* ★★★★ MAP_COVERAGE is the 512-byte slot-7 region T-P0-102 declared for the opcode counters, which
* `p3b` then declined [P6.47 §4B] -- so it is free, it is resident in every phase, and the engine
* map already records that it is not free space. ★★★ Slot 7 is required, not convenient: these are
* written from the VM phase and from the draw phase, and slot 7 is the only one that never moves.
* ★★ It is still 244 bytes short of enough for the CEL arm's CODE, which is why that arm does not
* define RES_CHECKSUM at all -- see the gates.manifest row and §4D.
RCK_MEM         equ     MAP_COVERAGE
rck_type        equ     RCK_MEM                 ; RCK_MAX
rck_idx         equ     rck_type+RCK_MAX
rck_live        equ     rck_idx+RCK_MAX         ; ★ 0 = released; see res_ck_release
rck_base        equ     rck_live+RCK_MAX        ; 2*RCK_MAX
rck_len         equ     rck_base+2*RCK_MAX
rck_sum         equ     rck_len+2*RCK_MAX
rck_ring        equ     rck_sum+2*RCK_MAX       ; RCK_ROWS*RCK_ROWSZ
rck_n           equ     rck_ring+RCK_ROWS*RCK_ROWSZ
rck_cur         equ     rck_n+1                 ; the logic number, stashed before res_open
rck_site        equ     rck_cur+1               ; which check is running; the caller sets it
rck_bad         equ     rck_site+1              ; mismatch rows written
rck_skipped     equ     rck_bad+1               ; sweep entries that could not be confirmed
rck_full        equ     rck_skipped+1           ; ★ the table overflowed -- coverage reduced, loudly
rck_s1          equ     rck_full+1
rck_s2          equ     rck_s1+1
rck_tmp         equ     rck_s2+1
rck_seen        equ     rck_tmp+1               ; ★★★ 2 B: VERIFICATIONS PERFORMED. §2W -- a green
                                                ;   from a checker that never ran is not a green,
                                                ;   and this is what separates them. Printed always.
rck_noted       equ     rck_seen+2              ; 2 B: baselines taken
* ★★★★ THERE IS NO rck_off, AND ITS ABSENCE IS THE POINT. 2*slot cannot live in U (the 6809's
* accumulator-offset modes are A, B and D only -- the assembler says "Undefined symbol u", which
* reads as a typo rather than as an addressing mode that does not exist), and it cannot live in a
* global: it did for one draft, and the readout found that global holding $C400 after a run with
* every other field correct. **A per-call value in a global is this VM's own named defect class**
* [vm_core.s records four instances]. It lives on the caller's frame.
RCK_MEM_END     equ     rck_noted+2
                ifgt    RCK_MEM_END-MAP_COVERAGE_END
                error   "res_check's tables overrun MAP_COVERAGE -- lower RCK_MAX or RCK_ROWS"
                endc

* ── res_ck_init -- zero the block. THE HOST DOES NOT POKE IT ─────────────────────
* ★★★★ MAP_COVERAGE is not part of the program image, so it holds whatever the machine had. An
* `inc` counter read from cold-boot RAM is the defect vm_state.s already records once (AC-5 read
* 256 distinct test opcodes against a possible 18 because its table was never cleared). **The
* table that decides whether a slot is in use MUST start at zero**, or rck_n is garbage and the
* first note writes somewhere arbitrary.
res_ck_init:
                pshs    a,x
                ldx     #RCK_MEM
rck_init_lp:    clr     ,x+
                cmpx    #RCK_MEM_END
                blo     rck_init_lp
                puls    a,x,pc

* ── res_ck_calc -- X = base, Y = length -> D = Fletcher-16 of those bytes ─────────
* ★★★ FLETCHER, NOT A SUM. A plain sum cannot see two bytes swapping places, and it cannot see a
* +1 and a -1 in the same resource -- which is the shape a counter overlapping a wrapping byte
* would produce. s2 accumulates s1, so position is part of the value.
* ★★ Wrap-around at 8 bits rather than mod 255: the textbook modulus buys a little strength and
* costs a divide on every byte, and this runs over whole resources in a diagnostic build.
res_ck_calc:
                pshs    x,y
                clr     rck_s1
                clr     rck_s2
                cmpy    #0
                beq     rck_calc_out
rck_calc_lp:    lda     ,x+
                adda    rck_s1
                sta     rck_s1                  ; s1 += byte
                adda    rck_s2
                sta     rck_s2                  ; s2 += s1
                leay    -1,y
                bne     rck_calc_lp
rck_calc_out:   lda     rck_s2
                ldb     rck_s1
                puls    x,y,pc

* ── res_ck_slot -- A = type, B = index -> B = slot, Z set on a hit ────────────────
* ★★ PULS DOES NOT TOUCH CC unless CC is in the list, so the Z from `cmpa b,y` survives the
* restore below it. That is load-bearing, and it is the kind of thing that reads as a bug later.
res_ck_slot:
                pshs    a,x,y
                stb     rck_tmp
                ldx     #rck_type
                ldy     #rck_idx
                clrb
rck_sl_lp:      cmpb    rck_n
                bhs     rck_sl_miss
                cmpa    b,x
                bne     rck_sl_next
                pshs    a
                lda     rck_tmp
                cmpa    b,y
                puls    a
                beq     rck_sl_hit
rck_sl_next:    incb
                bra     rck_sl_lp
rck_sl_hit:     orcc    #$04                    ; Z set = hit, B = slot
                puls    a,x,y,pc
rck_sl_miss:    andcc   #$FB
                puls    a,x,y,pc

* ── res_ck_note -- A = type, B = index. Baseline res_base/res_len as the truth ────
* ★★ A FRESH FETCH REPLACES, it does not verify: the bytes are new and may be at a new address
* after an eviction. **The caller decides which of note/verify to call, from res_open's carry.**
* ★ Stack after the pshs: 0,s A  1,s B  2,s X  4,s Y  6,s U  8,s return.
res_ck_note:
                pshs    a,b,x,y,u
                jsr     res_ck_slot
                beq     rck_note_have
                ldb     rck_n
                cmpb    #RCK_MAX
                blo     rck_note_room
                lda     #1
                sta     rck_full                ; ★ latched, never silent
                bra     rck_note_out
rck_note_room:  inc     rck_n                   ; B is the OLD count = the new slot
                ldx     #rck_type
                lda     ,s
                sta     b,x
                ldx     #rck_idx
                lda     1,s
                sta     b,x
rck_note_have:
                ldx     #rck_live
                lda     #1
                sta     b,x
* ★★★★★ THE OFFSET GOES ON THE STACK, NOT IN A GLOBAL, AND THAT IS THE THIRD ATTEMPT [T-P0-103].
* Draft 1 recomputed the slot before every store. Draft 2 carried it in U -- which is not an index
* register on this CPU. Draft 3 put it in `rck_off`, a global, and **the readout found rck_off
* holding $C400 after a run**, with every other field in the table correct: 2*slot cannot have a
* non-zero high byte, so something was writing it and the row fields were being read from wherever
* that pointed. ★★★★ A per-call value in a global is this VM's own named defect class -- vm_core.s
* records FOUR instances of it -- and the fix is the same one every time: **put it where the call
* lives.** The offset is now read only from the frame that computed it.
                lslb
                clra
                pshs    d                       ; 0,s = 2*slot | 2,s A | 3,s B
                ldx     #rck_base
                leax    d,x
                ldd     res_base
                std     ,x
                ldx     #rck_len
                ldd     ,s
                leax    d,x
                ldd     res_len
                std     ,x
                ldx     res_base
                ldy     res_len
                jsr     res_ck_calc
                pshs    d                       ; 0,s = sum | 2,s = 2*slot
                ldx     #rck_sum
                ldd     2,s
                leax    d,x
                puls    d
                std     ,x
                leas    2,s                     ; drop the offset
                ldd     rck_noted
                addd    #1
                std     rck_noted
rck_note_out:   puls    a,b,x,y,u,pc

* ── res_ck_verify -- A = type, B = index, rck_site set ───────────────────────────
* ★★★ NOT WATCHED IS NOT A FAILURE, and neither is released. A resource nobody baselined returns
* silently; blind spot 2.
res_ck_verify:
                pshs    a,b,x,y,u
                jsr     res_ck_slot
                lbne    rck_ver_out             ; ★ long: the row-writing tail put the exit out of reach
                ldx     #rck_live
                lda     b,x
                lbeq    rck_ver_out
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE SLOT IS TURNED INTO AN OFFSET *BEFORE* THE COUNTER IS BUMPED, AND THE FIRST VERSION
* DID IT THE OTHER WAY ROUND [T-P0-103]. `ldd rck_seen` CLOBBERS B -- which at that point is the
* slot -- so `lslb` doubled the low byte of rck_seen instead, and every array read below used
* `2 x rck_seen` as its offset.
* ★★★★★ IT PRODUCED EIGHT CONFIDENT, FULLY-POPULATED MISMATCH ROWS ON A CLEAN RUN. The offsets
* observed were 32, 34, 36 -- exactly 2 x 16, 17, 18, the value of rck_seen at each -- and the
* rows named real logic numbers with plausible-looking addresses. **A checker whose first output
* is a detailed accusation is the §2W.3 case: a diagnostic that cannot be wrong does not measure,
* it testifies**, and this one testified against five resources that were intact.
* ★★★★ WHAT CAUGHT IT WAS THE RAW DUMP, not reading the source. The table was correct and the rows
* were not, which is only visible if the host prints both. It was NOT caught by the mismatch
* count, by the row contents, or by three readings of this routine.
* ★★★ THIRD `B`-CLOBBER IN THIS FILE'S SHORT LIFE: `lda rck_bad` before `pshs d` destroyed the
* checksum's high byte, `leax u,x` was not an addressing mode, and this. **The common shape is a
* value held in a register across a call or a load that needs the same register.**
* ═══════════════════════════════════════════════════════════════════════════════════════════
                lslb
                clra
                pshs    d                       ; 0,s = 2*slot | 2,s A | 3,s B
                ldd     rck_seen                ; ★ only now, once the slot is safely on the frame
                addd    #1
                std     rck_seen
                ldx     #rck_base
                ldd     ,s
                leax    d,x
                ldx     ,x                      ; X = recorded base
                ldy     #rck_len
                ldd     ,s
                leay    d,y
                ldy     ,y                      ; Y = recorded length
                jsr     res_ck_calc             ; D = the checksum NOW
                pshs    d                       ; 0,s = actual | 2,s = 2*slot | 4,s A | 5,s B
                ldx     #rck_sum
                ldd     2,s
                leax    d,x
                ldd     ,s
                cmpd    ,x
                beq     rck_ver_pop             ; unchanged -- the ordinary case
* ★★★★★ THE PUSH COMES FIRST, AND THE FIRST VERSION HAD IT SECOND [T-P0-103]. `lda rck_bad` for
* the ring-full test DESTROYS A -- which at this instant is the high half of the checksum this row
* exists to report. The row then carried (rck_bad, s1) as its "actual", and the printed values
* marched $0300, $0400, $0500... across successive rows: **the row index in the high byte, which is
* the single most incriminating wrong answer available** [§2W.3]. The comparison above was
* unaffected, so the instrument was right about WHAT it found and wrong about what it said.
                lda     rck_bad
                cmpa    #RCK_ROWS
                bhs     rck_ver_pop             ; ring full
                lda     rck_bad
                ldb     #RCK_ROWSZ
                mul
                ldx     #rck_ring
                leax    d,x
                tfr     x,y                     ; Y = the row
                lda     4,s
                sta     ,y                      ; type
                lda     5,s
                sta     1,y                     ; index
                ldx     #rck_base
                ldd     2,s
                leax    d,x
                ldd     ,x
                std     2,y
                ldx     #rck_len
                ldd     2,s
                leax    d,x
                ldd     ,x
                std     4,y
                ldx     #rck_sum
                ldd     2,s
                leax    d,x
                ldd     ,x
                std     6,y                     ; expected
                ldd     ,s
                std     8,y                     ; actual
                lda     rck_site
                sta     10,y
                ldd     vm_cycle
                std     11,y
                inc     rck_bad
* ★ Two exits: rck_ver_pop drops the two frame words this routine pushed; rck_ver_out is for the
*   early returns that pushed nothing. Sharing one would unbalance the stack on one of the paths.
rck_ver_pop:    leas    4,s
rck_ver_out:    puls    a,b,x,y,u,pc

* ── res_ck_release -- A = type, B = index. Stop watching it ──────────────────────
* ★★★★ A TRANSIENT MUST BE RELEASED WHEN res_close POPS IT, or its entry describes memory the
* next fetch will legitimately reuse and the sweep reports an allocation as a corruption.
* ★★ ONE BYTE, NOT A SLOT RECLAIM. The first draft compacted the table by swapping the last entry
* into the hole -- four array moves and a special case for "it was the last one", to save an entry
* in a 16-slot table that never fills. **The flag is the version that is obviously correct.**
res_ck_release:
                pshs    a,b,x
                jsr     res_ck_slot
                bne     rck_rel_out
                ldx     #rck_live
                clr     b,x
rck_rel_out:    puls    a,b,x,pc

* ── res_ck_sweep -- verify everything still confirmably resident ─────────────────
* ★★★★ IT ASKS res_cache_find FIRST -- blind spot 4. Skips are counted so "swept 4, skipped 2" is
* visible rather than a silent narrowing.
res_ck_sweep:
                pshs    a,b,x,y,u
                clr     rck_skipped
                lda     #RCK_AT_SWEEP
                sta     rck_site
                clrb
rck_sw_lp:      cmpb    rck_n
                bhs     rck_sw_out
                pshs    b                       ; ,s = our slot
                ldx     #rck_live
                lda     b,x
                beq     rck_sw_skip
                ldx     #rck_type
                lda     b,x
                cmpa    #RES_LOGIC
                bne     rck_sw_skip             ; only LOGIC has a cache to confirm against
                ldx     #rck_idx
                ldb     b,x
                jsr     res_cache_find          ; Z set and X = cache slot on a hit
                bne     rck_sw_skip             ; evicted
                tfr     x,d
                lslb
                ldx     #res_caddr
                leax    d,x
                ldy     ,x                      ; Y = where the cache says it is
                ldb     ,s
                lslb
                clra
                ldx     #rck_base
                leax    d,x
                ldd     ,x
                pshs    y
                cmpd    ,s++
                bne     rck_sw_skip             ; relocated
                ldb     ,s
                ldx     #rck_type
                lda     b,x
                ldx     #rck_idx
                ldb     b,x
                jsr     res_ck_verify
                bra     rck_sw_next
rck_sw_skip:    inc     rck_skipped
rck_sw_next:    puls    b
                incb
                bra     rck_sw_lp
rck_sw_out:     puls    a,b,x,y,u,pc

                endc
