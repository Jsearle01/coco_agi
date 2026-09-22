## Form B Report — P6.81 — Evict one entry, not the whole cache
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `0c26ab3`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task and is not mine; nothing staged from it.

### 1 — Summary
The castle's starving VIEW fetch no longer drops the whole LOGIC cache. `res_cache_trim` hands
back the **lowest** entry only — the one a bump allocator can release without moving bytes — and
the caller retries, so "enough" is discovered rather than computed. Measured per steady castle
cycle: **hits/misses/episodes 0/4/1 → 3/1/1**, **bytes re-fetched 15,376 → 3,817 (−75.2%)**,
**s/cycle 1.003 → 0.757 (−24.6%)**, with the interpret stage falling **0.610 → 0.363 s (60.8% →
48.0%)**. Every port-side observable is byte-identical across the old policy, the new policy and
the trim-to-zero arm. The whole drop survives as `res_cache_evict`, now owning only total release
(the room-change flush), and the two paths are counted separately.

★★★★ **The dispatch predicted 1,631 B re-fetched and the delivered figure is 3,817 B**, because
§4B's measurement showed the smallest sufficient entry is in the MIDDLE of the allocation order.
LIFO takes 75% of the available 89% and moves nothing; the reasoning is in §3 and the choice was
fixed before any code was written.

★★★ **Jay's verdict: faster, and still too slow.** That is the honest headline and it is recorded
as such in §4 AC-9 — this task removed one cause, not the cost.

### 2 — Files modified
- `src/harness/res_core.s` — `res_cache_trim` (LIFO partial eviction); `res_ctrim`/`res_cdrop`
  counters; `ro_fetch`'s retry bounded by `res_cn` instead of the `res_evicted` latch;
  `-DRES_FAULT_WHOLEDROP` (AC-5's arm) and `-DRES_TEST_TRIMALL` (§2W's reachability arm); §9's
  four comment corrections.
- `harness/tools/p3b_run.lua` — `P3B_RESTAB` (the cache's layout at the moment it changes, tapped
  on `res_cn`, with the caller chain); `tr`/`dr` in the per-cycle RESSTATS line; totals line split
  into episodes / entries trimmed / cache emptied.
- `harness/tools/p3b_show.ps1` — `res_caddr`, `res_ctrim`, `res_cdrop` exported; `-WholeDrop` and
  `-TrimAll` switches.
- `harness/tools/p3b_arms_check.ps1` — nine arms re-baselined, **all by exactly +72 B**.
- `harness/tools/probe_identity_check.ps1` — the `vm` probe re-pinned, **by the same +72 B**.

Explicit-path staging only.

### 3 — Reasoning

**Authority tier.** ★★★★ **No tier below Jay was consulted and none was needed.** This is a change
to the port's own allocator, not to AGI behaviour: no ScummVM mechanism, no Specs claim, and
nothing about what the interpreter must reproduce. The evidence is measurement of this port, and
the correctness requirement is §2I's — the observable behaviour must not move, which §4 AC-3
tests directly. **§2H's three checks therefore have no reference mechanism to apply to**, and
saying so is the honest answer rather than manufacturing a citation.

#### §3(2) — the cache's allocation order in the castle ★★★★★

Tapped on `res_cn`, which is written by exactly two sites (`inc` at the end of `res_cache_stash`,
`clr` in `res_cache_evict`), so one byte records the whole allocation sequence with the table
still intact. ★★★ A per-cycle sample cannot do this: P6.80's parks all read `cn0`, because the
eviction happens mid-cycle and the park is after it.

Identical every steady cycle, under the OLD policy:

| slot | LOGIC | address | bytes | |
|---|---|---|---|---|
| 0 | L0 | `$7CD9` | 8,999 | first stashed, highest |
| 1 | L1 | `$767A` | **1,631** | ★ the smallest sufficient victim — **in the middle** |
| 2 | L101 | `$72D9` | 929 | |
| 3 | L102 | `$63F0` | **3,817** | ★ the lowest — the LIFO victim |

`res_ccur $63F0`, `res_top $6000`, free **1,008 B**; the transient is a 2,413-byte VIEW, so
**1,405 B must come back**.

#### §3(3) — every reader of `res_caddr` ★★★★

Three sites, all of them named:

| site | what it does | exposure to a moved entry |
|---|---|---|
| `res_core.s:241` (`res_open`'s hit path) | publishes the entry's address into `res_base`/`res_dest` | ★★★★ **`vm_bind_logic` derives `vm_code` from `res_base` and holds it for the whole of that logic's execution** [`vm_run.s:131-140`] |
| `res_core.s:551` (`res_cache_stash`) | writes the record | n/a |
| `res_check.s:356-371` (the checksum sweep) | re-finds the entry and compares the cache's address against its recorded baseline | skips on "evicted" or "relocated" — **degrades safely by construction** |

★★★★★ **LIFO removes this hazard rather than managing it: nothing moves.** The surviving entries
keep their addresses, and the trimmed one is re-stashed at the same address next cycle because the
allocation order is stable. ★★★ That is the substantive reason the cruder mechanism was chosen,
and it is why AC-7 is a confirmation here rather than a gamble.

#### §3(4) — every path assuming contiguity from `res_ccur` ★★★★★

| path | assumption | still true after a trim |
|---|---|---|
| `res_cache_stash` `ldd res_ccur / subd res_len / cmpd res_top / blo` | the next allocation goes directly below `res_ccur`, and colliding with the stack is the only failure | ★ yes — `res_ccur` moves UP by exactly one entry, so the freed span is contiguous and immediately reusable |
| `ro_fetch` `ldd res_ccur / std res_ceil` | the stack's ceiling IS the cache's floor | ★ yes, and it is re-read on every `ro_fetch_retry`, which is what lets the loop make progress |
| `res_cache_evict` (two stores) | dropping everything means `res_ccur = RES_ARENA_END` | ★ unchanged; now reached only from the room-change flush |
| `res_check.s`'s sweep | walks `res_ckey[0..res_cn-1]` | ★ yes — trimming shortens the table from the end |

★★★★ **`res_ccur = res_caddr[last] + res_clen[last]`, not `res_caddr[last-1]`.** The two are equal
by construction, and only the first is also true of the LAST entry — so the empty case needs no
special code. Verified on a real run rather than asserted: §4 AC-5b.

#### §4B — the mechanism choice, with its cost, BEFORE the implementation ★★★★★

**The obstacle the pricing did not name is real and it is §1.1's.** `res_ccur` starts at
`RES_ARENA_END` and only ever moves down, so entries are contiguous in allocation order and only
the lowest sits at the pointer. Removing a middle entry leaves a hole a bump pointer cannot reuse.
**"Evict the smallest sufficient entry" is an allocator change, not a policy change.**

| mechanism | frees | bytes moved | bytes re-fetched / cycle | verdict |
|---|---|---|---|---|
| **LIFO (lowest entry)** | 3,817 (L102) | **0** | **3,817** | ★★★★★ **CHOSEN** |
| Compaction (exact victim L1) | 1,631 | **4,746** (L101 + L102 slid up) | 1,631 | rejected |
| Free list / slot map | exact | 0 | 1,631 | rejected: more state, and the allocator stops being a bump pointer |

★★★★ **Pricing compaction against §6's threshold.** A miss costs roughly three passes over the
payload (fetch copy, stash copy, decode); a compaction move costs one. So compaction ≈
3×1,631 + 4,746 ≈ **9,639** byte-passes against LIFO's 3×3,817 ≈ **11,451**, both far below the
whole drop's 3×15,376 ≈ **46,128**. ★★★ **Compaction IS clearly below 15,376, so §6's first
trigger did not fire** — it is about 16% better than LIFO, not a different order.

★★★★★ **LIFO wins on the balance §4B itself sets: it drops far less than 15,376 anyway.** The 16%
buys the one hazard this file has no other instance of — a caller holding a pointer into moved
bytes (§3(3)) — and LIFO already reaches 75% of the 89% ceiling. ★★ **And the layout is stable, so
which entry sits at the bottom is a fact rather than a variable**, exactly as §4B anticipated.

★★★ **If a room ever puts a small entry at the bottom, the loop simply trims again** — and it
already does: see AC-1's `c8`.

#### Why the retry's bound had to change ★★★

`tst res_evicted` capped the retry at one because one whole drop freed everything there was to
free, so a second failure could only be a genuine `RES_E_BIG`. Trimming frees a little at a time,
so the loop must go round again. It still terminates: every pass either satisfies the fetch or
removes an entry, and `lda res_cn / beq ro_fail_pop` is the floor. ★★★★ **`res_cn` reaching 0 IS
the old whole drop, arrived at rather than jumped to** — which is how §4C's last resort stays
reachable without a second routine to keep in step. `res_evicted` keeps its job; it now latches
the episode COUNTER rather than the retry.

★★ **`res_fetch` refuses before writing a byte** (its ceiling contract), so a failed retry costs a
header read. That is what makes one-at-a-time affordable.

#### §4C(4) — which entry point owns the new policy ★★★★

★★★★★ **The starvation path owns it; the deferred flush does not, and that divergence is correct
rather than drift.** `res_cache_flush` (room change) still calls `res_cache_evict`, because at a
room change the working set is being replaced wholesale — dropping everything is the right answer,
not a starvation response. The two entries used to be two spellings of the same thing, which is
why the file warned they would drift; they now answer two different questions and each has one
home (§2F): **`res_cache_evict` = "give it all back", `res_cache_trim` = "give some back".**

#### §2S — sibling refs and scope
POP3_port HEAD `104b197` (wip), karateka_coco3 HEAD `29f8f0a` (wip); both working trees dirty with
pre-existing work that is not mine. ★ **No SHARED file was touched** — the change is confined to
`src/harness/`, which is this repo's alone — and `hal_sync_check.py` was run IN ALL THREE REPOS
(§5), which is the check that says so rather than my assertion. lwasm 4.24, unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement] What every eviction is triggered by — §4A.**
  ★★★★★ **Not one trigger, two.** The tap records the caller chain, so the episode is named rather
  than assumed (§2W.3). Over 40 cycles, **32 starvation episodes / 34 trims**:

  | cycle(s) | caller (`res_open`'s saved type:index) | trims | what it is |
  |---|---|---|---|
  | c9–c40 (31) | `$0200` = RES_VIEW(2) index 0 | 1 each | ★ the compositor's ego VIEW, 2,413 B |
  | c8 (1) | `$0101` = RES_PICTURE(1) index 1 | **3** | ★★★★ **`draw.pic`'s deferred fetch, 2,752 B** |

  ★★★★ **So the fix has a second customer and the sizing does change**: the picture fetch is the
  larger transient, and at c8 the bottom entry was L101 at 929 B, so one trim freed too little and
  the loop ran three times (929 → +1,631 → +3,817 = 6,377 free). **That is the middle-of-the-order
  case actually occurring**, and it is handled by the mechanism rather than by luck.
  ★★ A third event at c1 is `res_cache_flush`'s whole drop (a room change), which is not a
  starvation episode and does not increment `res_cevict` — the tap catches it because it taps
  `res_cn`, and distinguishing the two is exactly what the DROP/TRIM/stash labels are for.

- **AC-2 [class: measurement] §4B's layout table and the mechanism choice with its cost, before
  the implementation narrative.** ★ §3(2) and §4B above, in that order. Evidence: `RESTAB` in §5.

- **AC-3 [class: design] The last-resort path kept, the two counted separately, and which entry
  point owns the new policy.** ★ §4C above. `res_cache_evict` retained as the total-release home;
  `res_cevict` (episodes) / `res_ctrim` (entries handed back) / `res_cdrop` (episodes that emptied
  the cache) are three distinct counters, all published per cycle and in the totals.

- **AC-4 [class: measurement] §4D's four figures, before and after.** Same instrument, same
  corpus, same 40-cycle castle window; "before" is the `-WholeDrop` arm, not a quoted figure:

  | | before (whole drop) | after (trim) | |
  |---|---|---|---|
  | **(1)** hits / misses / episodes / trims per steady cycle | 0 / 4 / 1 / 0 | **3 / 1 / 1 / 1** | ★ target was hits > 0 and misses < 4 |
  | **(2)** bytes re-fetched per cycle | 15,376 | **3,817** | **−75.2%**; predicted 1,631 for exact choice |
  | **(3)** s/cycle (sum of stages) | 1.00333 | **0.75688** | **−24.6%** |
  | | median / mean | 0.7176 / 1.0121 | **0.4005 / 0.7672** | |
  | | interpret stage | 0.60995 (60.8%) | **0.36337 (48.0%)** | **−40.4%** |
  | **(4)** `res_top` high-water / `res_ccur` low-water | `$6000` / `$A000` at park | `$6000` / `$6F84` at park | ★ `$609B` mid-cycle both; **no fragmentation** |

  ★★★ **The "before" arm reproduces T-P0-133's published numbers exactly** — hits 22, misses 132,
  evictions 32, `interpret 0.610 s/cycle 60.8%` — which is the cross-check that the two
  measurements are of the same thing.
  ★★ Totals over 40 cycles: **hits 22 → 113, misses 132 → 41**; the cache holds 4 entries
  (12,412 B) at exit where it held 0. ★ A fifth LOGIC (L83, 853 B) is now resident and was
  invisible before, because nothing survived a cycle.

- **AC-5 [class: state-comparable · fault injection] §4E's arm RED.**
  ★★★★★ **`-WholeDrop` (`-DRES_FAULT_WHOLEDROP`) is red and its red is a number already
  published**: `h0 m4 ev1 tr0 dr0 cn0 ccur$A000 free16384` every steady cycle, totals 22/132/32,
  cache empty at every park — T-P0-133's measurement to the digit. ★★★ A fault arm whose red the
  project has already reported is the strongest kind [§2W; the `-NoRestore` precedent].

- **AC-5b [class: state-comparable · §2W reachability] The last resort shown able to FIRE.**
  ★★★★★ **It could not fire in the castle and I did not report it as working on that basis.**
  Measured: 34 trims over 32 episodes with **`res_cdrop` = 0** — the lowest entry is 3,817 B and
  the biggest transient is 2,752 B, so the loop never reaches `res_cn = 0`, and **the terminal
  arithmetic (`res_caddr[0] + res_clen[0]` landing on `RES_ARENA_END`) was never executed.**
  ★★★★ `-TrimAll` (`-DRES_TEST_TRIMALL`) forces it: **entries trimmed 129, cache emptied 32,
  `cn0`, `res_ccur $A000` — exactly `RES_ARENA_END`** — and the RESTAB trace shows the descent
  `cn4→3 ccur$63F0`, `cn3→2 $72D9`, `cn2→1 $767A`, `cn1→0 $7CD9`, each equal to the next entry's
  base. ★★★ **It is not a fault arm: its result MATCHES `-WholeDrop` in every observable** (22 /
  132 / 32, `cn0`, free 16,384, SUM 1.00361 vs 1.00333 s/cycle), which is the point — trimming to
  empty and dropping the region are the same end state reached two ways, and a disagreement would
  have been the arithmetic being wrong.

- **AC-6 [class: byte-comparable · gate] All five byte gates RUN, on the FINAL source.**
  ★★★★ `res` **1,264/1,264 (100.00%)** — the gate that owns this code. `vm` **9/9, 0 divergent
  cycles of 600 each**. `pic` **45 PASS / 0 FAIL (of 45)**, `cel` **9,193/9,193 (100.00%)**,
  `comp` **124/124 (100.00%)**.
  ★★★ **The suite was re-run after `-DRES_TEST_TRIMALL` landed**, because the first pass predated
  it and those binaries were therefore not the ones baselined. Stated because the first run is in
  my transcript and citing it would have been a stale-artifact claim [L-70's shape].
  ★★ §2T's lesson, fourth instance, recorded in the re-pin: **the `vm` gate's arena is 21,760 B and
  it links no compositor**, so its green is a coverage fact about a different pressure.

- **AC-7 [class: state-comparable] `logic_copy_diff.py`: 0 of 256 on a cached LOGIC after an
  eviction.** ★★★★★ **0 of 256 differing offsets**, LOGIC 1 at cycle 30, resident at `$7327` —
  a table entry (`L1@$7325` + the 2-byte length header) that has survived **20+ trim episodes**.
  ★★★ **And the instrument was shown able to go red on this exact snapshot**: the same file
  against LOGIC 101's bytes reports **234 of 256** differing [§2W].
  ★★★★ **A second, independent confirmation** from the `-ResCheck` arm, which is the instrument
  built to ask whether resident bytes still match what was loaded: **11 baselined, 228 verified,
  0 mismatches, 0 sweep skips** — against the old policy's 12 / 226 / 0 / **1 skip**. The new
  policy verifies MORE and skips FEWER, which is the direction keeping entries resident should
  move it.

- **AC-8 [class: suite] `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green**; the suite
  reports `all green` and the mojibake gate clean over every tracked text file (§2J.7).

- **AC-9 [class: eye-gated — Jay] ★★★★★ RUN FIRST, before the byte gates were reported (§4A).**
  Live, RGB, `screen_config=1`, 300 cycles, `-Combined` eye path. Expectations were stated in the
  ask. Jay's answers verbatim:
  1. *"yes but still to slow"* — ★★★★ **expectation (yes) met, and the qualifier is the finding.**
     −24.6% is real and is not enough; §8 carries what is left.
  2. *"yes better, but still laggy"* — ★★ **matches the stated expectation exactly** ("somewhat";
     the game still takes one key per cycle).
  3. *"yes"* — ★★★★ **behaviour identical**, as expected. Corroborated byte-wise: the run summary
     (ego position, view/loop/cel, all four staged sprites, room, restore bytes, text-area bytes,
     row 22, `P3_PBUF` checksum) is **byte-identical across `-WholeDrop`, the shipped arm and
     `-TrimAll`**.
  4. *"the title screen does not scroll the credits anf the preass a ket line is still tansiting
     to the castle screen"* — ★★★★★ **neither is a regression and one of them is my fault.**
     - ★★★★ **The credits: the GATE's shape, not the program's.** I launched with `P3B_ROOM=1`, so
       a room jump fires at cycle 8 and `p3b_show.ps1` prints its own warning — *"TITLE SEQUENCE
       CUT ... Do NOT judge the title screen from this run; pass -NoRoomJump."* **Checked rather
       than asserted**: with the jump off, the credits scroll exactly as designed, one line per
       five cycles — credit rows `18` → `17,18` → `16,17,18` → … → `11,12,13,15,16,17,18` at c40,
       and the run banner reads *"title sequence intact"*. ★★★ **This is the third recurrence of
       the trap that file records: the operator judging the gate's shape and reading it as the
       program's behaviour** — and this time the invocation was mine.
     - ★★ **The "press a key" line carrying into the castle is a known open item**, reported at
       P6.79 and unchanged here; it is in §8 and was already out of this task's scope.

- **AC-10 [class: manifest] Arms re-baselined.** ★★★★ **All nine by exactly +72 B**, and
  **the `vm` probe by the same +72 B**. ★★★ The uniformity is the evidence it is ONE change in ONE
  file: the vm probe links `res_core.s` and no p3b file, so an identical delta on both sides
  attributes it to `res_core.s` alone. Self-test still discriminates exactly one row.
  ★★ Both fault flags are absent from every baselined row, so each is a deliberate extra build and
  the default is the trimmed policy.

- **AC-11 [class: tooling]** `hal_sync_check.py` OK in all three repos; `reg_discipline.py` 18
  accesses in 2 files (unchanged: `res_core.s` still names `$FFA6` exactly once);
  `gen_vm_tables.py --check` OK; `probe_identity_check.ps1` every non-p3b probe byte-identical;
  `p3b_arms_check.ps1` all 9 byte-identical, `-SelfTest` red on exactly one row.

- **AC-12 [class: n/a] Candidate(s) captured.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)

=== AC-2 SUMMARY ===   (vm gate, 600 cycles each, 0 divergent)
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS  SpaceQuest-1 PASS  SpaceQuest-2 PASS
PoliceQuest1 PASS  larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS
```

**Shipped arm (trim), per steady castle cycle and totals:**
```
c38 h3 m1 ev1 tr1 dr0 cn4 top$6000 ccur$6F84 free3972      ... identical c9..c40
RESSTATS totals: hits 113, misses 41, starvation episodes 32, entries trimmed 34,
                 cache emptied 0, cache entries 4, arena free 3972 B
RESSTATS cache holds 4 entr(ies), 12412 B: L0:8999B L83:853B L1:1631B L101:929B
   median 0.4005 s/cycle    mean 0.7672 s/cycle    SUM 0.75688 s/cycle
   interpret 14.5346 s total  0.36337 s/cycle  48.0%
```

**AC-5 fault arm `-WholeDrop` (the old policy) — RED, and equal to T-P0-133:**
```
c40 h0 m4 ev1 tr0 dr0 cn0 top$6000 ccur$A000 free16384
RESSTATS totals: hits 22, misses 132, starvation episodes 32, entries trimmed 0,
                 cache emptied 0, cache entries 0, arena free 16384 B
   median 0.7176 s/cycle    mean 1.0121 s/cycle    SUM 1.00333 s/cycle
   interpret 24.3978 s total  0.60995 s/cycle  60.8%
```

**AC-5b `-TrimAll` (§2W reachability) — the terminal case executed:**
```
RESSTATS totals: hits 22, misses 132, starvation episodes 32, entries trimmed 129,
                 cache emptied 32, cache entries 0, arena free 16384 B (res_ccur $A000)
c40 h0 m4 ev1 tr4 dr1 cn0 top$6000 ccur$A000 free16384
c10 TRIM  cn4->3 ccur$63F0 ... c10 TRIM cn3->2 ccur$72D9 ... c10 TRIM cn2->1 ccur$767A
c10 DROP  cn1->0 ccur$7CD9 [L0@$7CD9:8999B]          -> $7CD9 + 8999 = $A000 = RES_ARENA_END
```

**§3(2)/AC-1 RESTAB (layout + caller), shipped arm:**
```
c8  TRIM cn5->4 @[426E 0101 ...] [L0@$7CD9:8999 L83@$7984:853 L102@$6A9B:3817 L1@$643C:1631 L101@$609B:929]
c8  TRIM cn4->3    "     $0101 = RES_PICTURE index 1  (draw.pic, 2,752 B -- three trims)
c8  TRIM cn3->2    "
c10 TRIM cn5->4 @[426E 0200 ...] $0200 = RES_VIEW index 0  (the compositor, 2,413 B -- one trim)
```

**AC-7:**
```
logic 1: file 698 bytes, snapshot 256 bytes       copy at $7327, vm_codelen 698
differing offsets: 0 of 256 compared
  -- teeth, same snapshot vs LOGIC 101:  differing offsets: 234 of 256 compared
res-checksum: 11 baselined, 228 verified, 0 mismatch(es), 0 sweep skip(s)   [old policy: 12 / 226 / 0 / 1]
```

**AC-10 / AC-11:**
```
p3b 15704 5E2BD3CB | p3b_text 16928 C8777E16 | p3b_win3 16928 4BFEC4D7 | p3b_notick 16925 7E41DCD5
p3b_nomap 16925 A7626E70 | p3b_fault 15965 A889DB49 | p3b_flat 15950 941B277E
p3b_comb 18941 F201956F | p3b_comb_count 18976 4E9BB6B5
★ all 9 arms byte-identical to the recorded baseline (SHA256)
vm 10057 B 90832641 [pinned] OK ... ★ every non-p3b probe byte-identical

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)   [in coco_agi]
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)    [in POP3_port]
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)         [in karateka_coco3]
[reg-discipline] 18 register access(es) in 2 file(s) over 4 register(s).
  src/engine/mmu_phase.s 17 ($FFA3 $FFA4 $FFA5 $FFA6) | src/harness/res_core.s 1 ($FFA6)
CHECK OK: vm_tables.s matches optable.py.
src/harness/res_core.s  clean   (fix_mojibake --check, all five touched files)
```

**25.2 bundled-artifact grep:** N/A — no artifact is bundled; the change is probe-side and the
nine arms plus five probes are pinned by hash above.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, live, RGB, `-Combined` eye path, 300
cycles.** Answers and their adjudication in AC-9. **Run BEFORE the byte gates were reported**,
per §4A.

### 6 — Reactive deviations and route accounting

**§22.5 deviations from the dispatch spec:**
1. ★★★★ **`-DRES_TEST_TRIMALL` was added and the dispatch did not ask for it.** §4C required the
   last resort be kept and reachable; measurement showed it **cannot fire in the castle**, so
   reporting it as correct would have been an unexercised assertion [§2W]. The arm is guarded,
   adds no bytes to any shipped row, and is not a fault arm — its result must match `-WholeDrop`,
   and does.
2. ★★★ **`-Combined -IfRec` was used for AC-7 rather than `-IfDiag`.** `-IfDiag` is a text arm and
   evictions only starve where a compositor fetches VIEWs; `-IfRec` adds the same recorder to the
   combined arm, which is the configuration the claim is about.
3. ★★ **The gate suite was run twice**, the second time because the first predated deviation 1.
   Only the second is cited.

**ROUTE ACCOUNTING.** ★★★★★ I proposed LIFO in §4B before implementing, and **the commit contains
exactly that route and no part of the other two.** Specifically **NOT implemented**: compaction
(no bytes are moved and no `res_caddr` is rewritten) and the free list / slot map (the allocator
is still a bump pointer). ★★★ **The 1,631 B/cycle figure the dispatch carried belongs to
compaction and was NOT delivered**; the delivered figure is 3,817 B/cycle, and §1 and §4 AC-4 say
so rather than reporting the predicted number.

### 7 — Uncertainty flags

1. ★★★★★ **The cycle is still too slow and Jay says so.** −24.6% is one cause removed, not the
   cost. The resource layer is no longer 62%; **`interpret` is still 48.0%** and `roomcheck`
   (29.9%) and `composite` (21.4%) now dominate in relative terms without having moved at all.
2. ★★★★ **ONE ROOM OF ONE TITLE, again** [T-P0-133's flag, unretired]. The 3,817 B figure is
   L102's length in KQ1's castle. **A room whose lowest entry is small trims more often** — c8
   already shows three trims — and a room whose lowest entry is huge would free more than needed.
   The mechanism is insensitive to this; **the quoted saving is not.**
3. ★★★ **`res_ctrim` = 34 against 32 episodes is a two-event margin**, and both extra trims are in
   one cycle (c8). A corpus with more deferred pictures would shift that ratio.
4. ★★ **L83 (853 B) became visible only because entries now survive a cycle.** It was in the
   working set all along and P6.80 could not see it, so **P6.80's "4 LOGICs" is 4 per cycle and 5
   per room** — the union is larger than that report's table, and the arena shortfall is therefore
   slightly worse than 1,405 B, not better.
5. ★ **`P3_PBUF ... NOT DECODED` in the `-ResCheck` arm** is pre-existing: identical under
   `-WholeDrop`. Checked rather than assumed, and flagged because it reads like a failure.
6. ★★ **The eye gate's title-screen artifact was caused by my invocation** (AC-9.4). Recorded here
   so the next operator ask carries `-NoRoomJump` when the title screen is in scope.

### 8 — Follow-up candidates

1. ★★★★★ **The arena is still 1,405 B short and that has not changed.** Size binds; the policy no
   longer multiplies it. **The banked arena the memory map describes was never built** — a
   residency project, still blocked by 256 B of slack below and the object table above.
2. ★★★★ **`interpret` at 48.0% is now the largest stage and nothing in it has been measured since
   P6.79's profile**, which was taken on the corrupted base. **Re-profile the shipped arm** before
   choosing the next target — the ranking that justified this task is itself stale.
3. ★★★★ **Typing is still laggy and the cause is named and untouched**: the game takes one key per
   cycle. That is an interpreter-cadence question, not a cache one.
4. ★★★ **Compaction remains on the table at ~16%**, priced in §4B. It is worth building only
   behind a re-measured profile, and it carries the §3(3) hazard that LIFO avoids.
5. ★★★ **Re-measure the working set across rooms and titles** [T-P0-133's follow-up, still open,
   and §7(2)/(4) sharpen it].
6. ★★ **`draw.pic`'s deferral** (AC-1's second customer): with three entries now resident the
   picture still trims three of them. Whether the deferral is still needed at all is now a
   different question than it was.
7. ★★ **A stash-refusal counter** [T-P0-133's follow-up, still open].
8. ★★★★★ **The `$FFA6` ownership ruling** — P6.79's Part B, the Orchestrator's, and named "next"
   by this dispatch's §2.
9. ★ **`checkPriority`/`checkCollision` and the moat**; **the "press a key" line carrying into the
   castle** (AC-9.4); **real-time pacing**; **`MAP_PRI_BANDS`** at `memmap.inc:310` — **the
   twenty-seventh task**.

### 9 — User interaction during task
The AC-9 eye gate, offered before the byte gates were reported, with expectations stated for each
of the four questions (§4A.3). Jay's four answers are quoted verbatim in AC-9 and adjudicated
there; item 4 was checked against a second run rather than explained away.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-the-cheap-mechanism-wins-when-the-layout-is-stable.md`

### 11 — Commit
`<hash>`  (pushed to origin/wip before this report)
