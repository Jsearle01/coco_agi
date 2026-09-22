## Form B Report — T-P0-133 / P6.80 — 19,230 bytes into 16,384: the working set against the arena
**Class:** measurement. wip. **No fix built.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22T22:11:48Z (HEAD dc67f7b, wip). git status clean at receipt (untracked
`coco_agi.code-workspace`, not mine).

### 1 — Summary

★★★★★ **The castle's working set is 19,230 bytes and the arena is 16,384. It is over by 2,846.**
Every cycle, with the game actually running: **4 distinct LOGICs and 3 VIEWs**, identical cycle
after cycle.

| | bytes | | | bytes |
|---|---|---|---|---|
| LOGIC 0 | 8,999 | | VIEW 0 (the ego) | 2,413 |
| LOGIC 102 | 3,817 | | VIEW 107 | 808 |
| LOGIC 1 | 1,631 | | VIEW 97 | 633 |
| LOGIC 101 | 929 | | **LOGICs together** | **15,376** |

★★★★★ **The mechanism, in one line of arithmetic.** Four cached LOGICs occupy 15,376 B of 16,384,
leaving **1,008 B** for transients — and the compositor's largest VIEW needs **2,413 B**. Every
cycle that fetch starves, `res_cache_evict` drops the **whole** cache, and the next cycle re-fetches
and re-decodes all four LOGICs. **Measured, per steady cycle: 0 hits, 4 misses, 1 starvation
eviction**, and the cache holds **nothing** at every park.

★★★★★ **So: BOTH, and the order matters.** The arena is too small to hold the set (short by
2,846 B), **but the policy is what converts a 1,405-byte shortfall into a 15,376-byte loss.**
★★★★ **Per-entry eviction needs no extra memory**: evicting the smallest entry that frees enough
(LOGIC 1, 1,631 B) leaves three cached and re-fetches **1,631 B a cycle instead of 15,376** — an
89% cut in the bytes the resource layer moves, which P6.79 profiled at 62% of the cycle.

★★★ **§4C(4) checked first, because §6 makes it a stop: a cached LOGIC is NOT re-decoded.**
`vm_bind_logic`'s `bcs` skips `res_decode` on a hit [`vm_run.s:94-113`]. `res_decode` is 19% of the
cycle because **almost every bind is a miss**, which the counters confirm. No defect; no stop.

★★★★ **Widening the arena is blocked today** [§4B]: the aperture is two MMU slots, `$6000-$A000`;
below it `MAP_RESERVED` has 256 B of slack over its declared floor, and above it `$A000` is slot 5,
which holds the object table in the VM phase. **256 B available against 1,405 B needed.** The map's
own note says the arena may grow behind the aperture — that needs a banked arena, which is a
residency project, not an address change.

### 2 — Files modified (no shipped byte moves)
- `harness/tools/p3b_show.ps1` — six cache symbols exported: `res_cn`, `res_chits`, `res_cmiss`,
  `res_cevict`, `res_ckey`, `res_clen`. ★ They have existed since the cache landed and **no host
  had ever read them.**
- `harness/tools/p3b_run.lua` — `P3B_RESSTATS`: per-cycle hits/misses/evictions/occupancy deltas,
  and the cache's contents at the end. Host-side reads only.
- `harness/tools/res_sizes.py` — NEW: the working set from the oracle-gated reference, by count and
  bytes, per cycle.
- `src/harness/res_core.s` — **comments only** (§9): the stale "3-4 LOGICs" figure, the eviction
  policy's justification, and what the gate's larger arena hides. **All nine arms and all five
  probes byte-identical** (§5).
- `reports/20260922-181714-p6-80-the-working-set-against-the-arena.md` — this report.

### 3 — Reasoning

**§3(1)** Nine arms verified at P6.79's figures, `p3b_comb` 18,869 / 30AEF5F9.

**§3(2) ★★★★★ The arena's layout in the combined arm, and a correction to the dispatch.**
★★★★ **`p3b`'s arena is 16,384 B, not 12 KB.** `$3000-$6000` is `res_core.s`'s DEFAULT, which
`res_probe` uses; `p3b_probe.s:29-31` overrides it with `MAP_ARENA_WIN`:

| | address | size | note |
|---|---|---|---|
| `MAP_CODE` | `$2000-$5300` | 13,056 B | the probe's code |
| `MAP_RESERVED` | `$5300-$6000` | 3,328 B | parser + sound; floor `MAP_RESERVED_MIN` 3,072 → **256 B slack** |
| **`MAP_ARENA_WIN`** | **`$6000-$A000`** | **16,384 B** | slots 3-4; `res_top` up from `$6000`, `res_ccur` down from `$A000` |
| `MAP_PRI_SLICE` | `$A000-$C000` | 8,192 B | slot 5: priority slice when drawing, **VM_OBJ / vocabulary in the VM phase** |
| volume window | `$C000-$E000` | 8,192 B | slot 6 |

P6.78/P6.79's readouts agree: *"arena peak 13,669 B of 16,384"*, *"16384 bytes free"*.

**§3(3) The cache's state, and where the host can read it** — all six already existed:
`res_cn` (entries live), `res_ckey`/`res_caddr`/`res_clen` (the table), `res_chits`, `res_cmiss`,
`res_cevict` (starvation evictions), plus `res_top`/`res_ccur` (already exported). ★★★
**`res_cevict`'s own comment says a high count means "the arena is genuinely too small and the cache
is only masking it"** — it counts 32 in 40 cycles and nothing had ever read it.

**§3(4) ★★★★★ Every consumer of arena space in a cycle:**

| consumer | when | bytes | resident? |
|---|---|---|---|
| LOGIC fetches (4) | interpret | 15,376 | cached if they fit |
| VIEW fetches (3, one at a time) | composite, per sprite | 2,413 max | **transient**: opened, decoded from, closed |
| PICTURE | room change only | 2,752 (picture 1) | transient, at depth |
| the stash region | after each LOGIC miss | = the LOGIC's size | the cache itself |
| the scratch | during every fetch | = the resource's size | popped at `res_close` |

★★★ The PICTURE is why `draw.pic` was deferred with 1,084 B free [P6.67]: **2,752 B wanted against
~1,008 B of headroom.** Same constraint, third hat.

#### §4A — the measurement (castle, room 1, game running, cycles 12-40)

**Port, per steady cycle** (`P3B_RESSTATS`, host reads of the guest's own counters):
```
c10 h0 m4 ev1 cn0 top$6000 ccur$A000 free16384      ... identical every cycle to c40
RESSTATS totals over 40 cycles: hits 22, misses 132, starvation evictions 32,
                                cache entries 0, arena free 16384 B
```
★★ The 22 hits are the first cycles, before the room settles; **from c10 on there are none**.

**Reference** (`res_sizes.py`, the oracle-gated VM, same scene): 4 LOGICs + 3 VIEWs = **19,230 B**,
every cycle from 12 to 40, union identical to the per-cycle set. **The port fetches exactly what
the reference asks for; nothing is spurious.**

★★★★★ **AC-3 — policy or size, with the arithmetic:**
```
LOGIC working set      15,376 B      arena 16,384 B      headroom 1,008 B
largest transient      2,413 B  (VIEW 0)                 short by 1,405 B
whole set + transient  17,789 B                          short by 1,405 B
whole set incl. all 3 VIEWs (if VIEWs were cached too)   19,230 B, short by 2,846 B
```
**SIZE is the binding constraint for a cache that never misses** (+1,405 B minimum).
**POLICY is what makes today's cost total**: all-or-nothing eviction throws 15,376 B away to make
room for 2,413.

#### §4B — the price of widening the arena
- **Below:** `MAP_RESERVED` `$5300-$6000`, 3,328 B with a declared floor of 3,072 → **256 B** can be
  taken without lowering a floor deliberately. **Not enough** (1,405 needed).
- **Above:** `$A000` is slot 5, which holds **VM_OBJ during the VM phase** — the phase in which
  fetches happen. Taking it would collide with the object table the interpreter is reading.
- **Behind the aperture:** `memmap.inc:242` — *"THE WINDOW IS NOT THE ARENA. The arena is 3 blocks
  (24 KB) of the ~46 free, and this is the aperture onto it."* ★★★ **`res_core` does not implement
  that**: `res_top`/`res_ccur` are flat pointers inside the two-slot window. A 24 KB arena needs a
  banked residency manager — a project, not a constant.
- ★ Code could move: `MAP_CODE` ends `$5300` against `CP_CEL`; the combined arm is the fullest
  configuration and has 8 bytes of slack there [P6.71's note]. **Nothing cheap to reclaim.**

**Priced as BLOCKED**, per §6, at 256 B available against 1,405 B needed.

#### §4C — the options, priced against §4A

| option | memory needed | bytes re-fetched per cycle | est. effect on the cycle | risk |
|---|---|---|---|---|
| **1. Per-entry eviction** (evict the smallest entry that frees enough) | **none** | **1,631** (LOGIC 1) vs 15,376 | ★★★★ 62% → roughly 10-15% of the cycle; **~0.92 → ~0.5 s** (arithmetic, unverified) | eviction must still refuse to drop bytes that are executing (`res_depth > 0`), which the current guard already does |
| 2. Bigger arena (+1,405 B minimum, +2,846 to cache VIEWs too) | **blocked** (256 B available) | 0 | would remove the layer entirely | needs a banked arena or the slot-5 collision resolved |
| 3. Larger `RES_CACHE_MAX` | none | unchanged | **none — 4 of 8 entries are used**; the table is not the limit | — |
| 4. Don't cache what is not worth caching | none | e.g. skip LOGIC 0 (8,999 B) → 6,377 B cached, 10 KB free | ★★ removes starvation, but re-fetches the **largest** logic every cycle: worse than option 1 | the biggest logic runs every cycle |

★★★ **Ranked: 1, then 2 when the arena can grow, and 3 not at all.** ★★ Option 1 is a policy change
inside `res_cache_evict` and its caller; it does not touch the seam or the fetch path.

★★★★★ **§4C(4), checked: a cached LOGIC is not re-decoded.** `vm_run.s:101-113` skips
`jsr res_decode` on the carry that `res_open` sets for a hit, and `-DRES_FAULT_DECODE_HIT` exists
precisely to reintroduce that defect. **`res_decode`'s 19% is 4 misses a cycle, not a re-decode.**

#### §4D — what the `vm` gate can see: nothing of this
`vm_probe`'s arena is **21,760 B** [`res_core.s:483`]. The same 15,376 B of LOGICs leave **6,384 B**
free there, so a 2,413-byte transient never starves. ★★★★ **And `vm_probe` links no compositor, so
it never fetches a VIEW at all.** The nine-title gate cannot exercise arena pressure in either
direction; **its green is a coverage fact about this question** — third instance of that lesson.

### 4 — Verification (AC-by-AC)
- **AC-1 [measurement] PASS** — 4 LOGICs + 3 VIEWs, 19,230 B, per cycle, with per-resource sizes.
- **AC-2 [measurement] PASS** — 0 hits / 4 misses / 1 starvation eviction per steady cycle; 22 /
  132 / 32 over 40; `res_cn` 0 and `res_top`/`res_ccur` at their extremes at every park. ★ **Stash
  refusals are not separately counted** (`rcs_out` is shared by the success and refusal paths); the
  eviction count plus an empty cache at every park measures the same thing here, and a dedicated
  counter is named as a follow-up.
- **AC-3 [attribution] PASS** — size binds (short 1,405 B); policy multiplies (15,376 vs 1,631).
- **AC-4 [measurement] PASS** — blocked: 256 B available, 1,405 needed; the three directions priced.
- **AC-5 [measurement] PASS** — §4C's table, including the re-decode check.
- **AC-6 [measurement] PASS** — §4D.
- **AC-7 [byte-comparable] PASS with the stated exception** — `git diff --stat -- src/` is
  **comment-only** (25 lines in `res_core.s`, §9's three corrections). **All nine arms and all five
  non-p3b probes byte-identical** (§5). No counter needed publishing: they all existed.
- **AC-8 [suite] Discharged** — no artifact moved, proven by hash rather than by input citation
  (stronger than §2T). Gates last run green at P6.79 (`dc67f7b`) on these exact binaries.
- **AC-9 [ruling requested]** — §7.1.
- **AC-10** — §10.

### 5 — Verdict-time evidence (v0.7 §11)
```
★ all 9 arms byte-identical to the recorded baseline (SHA256)
★ every non-p3b probe byte-identical
 src/harness/res_core.s | 26 +++++++++++++++++++++++++-      (comments only)

RESSTATS totals: hits 22, misses 132, starvation evictions 32, cache entries 0,
                 arena free 16384 B (res_top $6000, res_ccur $A000)
c10..c40:  h0 m4 ev1 cn0 top$6000 ccur$A000 free16384        (every steady cycle)
reference: 4 LOGIC + 3 VIEW = 19230 B/cycle; union 7 resources, 19230 B
           arena 16384 B -> DOES NOT FIT, over by 2846 B
stage timing, same run: interpret 0.610 s/cycle (60.8%), roomcheck 0.227, composite 0.162,
                        SUM 1.003 s/cycle  [game RUNNING, post-P6.78]
source integrity: clean
```
**25.2:** N/A — measurement task. **25.3:** N/A — no shipped byte changed; nothing new to see.

### 6 — Reactive deviations and route accounting
- **No fix built** (§6's first trigger respected). Option 1 is priced, not written.
- **§9's three comment corrections were made in `src/`**, against AC-7's "EMPTY", because they are
  the stale figures this task falsifies and §9 names them. **Arms and probes byte-identical**;
  reported rather than quietly taken.
- **The dispatch's "12 KB arena" is corrected to 16,384 B** (§3(2)). The 12 KB figure is
  `res_core.s`'s default, used by `res_probe`, not by `p3b`.
- **§9 `memmap.inc:310` `MAP_PRI_BANDS`: not done, 27th task** (§6 stop trigger).

### 7 — Uncertainty flags

#### 7.1 ★★★★★ For Jay — where the 62% goes, and what the fixes cost
Every cycle the game needs four scripts and three sprite pictures: **19,230 bytes, into a
16,384-byte space.** The four scripts alone are 15,376, which leaves about 1,000 bytes free — and
the ego's sprite picture alone needs 2,413. So the sprite fetch runs out of room, and the way the
port recovers is to **throw away everything it had cached** and start again. Next cycle it reloads
and re-decrypts all four scripts. That is your 62%.

**Two fixes, and the cheap one is not the obvious one.**
- ★★★★ **Change what gets thrown away — no extra memory.** Dropping just enough to make room (one
  1,631-byte script instead of all 15,376) would leave three of the four cached. **Re-loaded bytes
  per cycle fall by about 89%**, and my arithmetic puts the cycle at roughly **0.9 s → 0.5 s**.
  That is a change inside one routine.
- **Make the space bigger — blocked for now.** We would need about 1,400 more bytes. There are 256
  spare below the arena; above it is the object table the interpreter reads. The memory map always
  intended the arena to be larger than its window, with paging behind it, but that part was never
  built. **It is a real project, not a constant.**

**My recommendation: do the eviction policy first**, then revisit the arena when the paging work
happens. Note the same shortage is what defers a room's picture on arrival (the 2,752-byte picture
against ~1,000 bytes free), so the policy change should help that too.

#### 7.2 Other flags
- **Stash refusals are not counted separately.** Today `res_cache_stash` returns silently when an
  entry will not fit or the table is full, and the same exit increments the miss counter. In this
  scene the eviction counter answers the question; in a scene where the table filled, it would not.
- **The measurement is of ONE room of ONE title.** KQ1's castle is the scene every recent task has
  used. A room with more objects would fetch more VIEWs; a title with a bigger LOGIC 0 (the corpus
  maximum is 10,964 B, larry1) would be worse. **The 19,230 is not a corpus figure.**
- **The 22 early hits** come from cycles before the room settles; they are in the totals and
  excluded from the per-cycle claim, which is taken from c10 onward.
- **The estimated 0.5 s/cycle is arithmetic**, from bytes moved, not a measurement of a built fix.

### 8 — Follow-up candidates
1. ★★★★★ **Per-entry eviction in `res_cache_evict`** — §4C option 1, the only one that needs no
   memory. Gate it on `res_chits`/`res_cmiss` per cycle, which now have a reader.
2. ★★★★ **A stash-refusal counter**, so the silent path is visible in a scene where it matters.
3. ★★★★ **The banked arena** the memory map already describes — this is the structural answer, and
   it also unblocks the picture deferral and a VIEW cache.
4. ★★★ **Re-measure the working set across rooms and titles** before sizing anything permanently.
5. ★★★ **The `$FFA6` ownership ruling** (P6.79) is still the queued decision.
6. Carried: `checkPriority`, real-time pacing, `MAP_PRI_BANDS` (27th).

**PROPOSED TEXT for the design spec [§2D], §3.7's residency section:**
> ★★★★★ *MEASURED [P6.80]: KQ1's castle needs 4 LOGICs (15,376 B) and 3 VIEWs (3,854 B) per cycle
> against a 16,384 B arena window. The LOGIC cache is therefore evicted by starvation once per
> cycle and the interpreter re-fetches and re-decodes 15,376 B every cycle — 62% of the cycle.
> **The arena window is the binding constraint on residency, and the all-or-nothing eviction policy
> multiplies it.** A banked arena behind the two-slot aperture, which §3.2 always intended, is the
> structural answer; per-entry eviction is the cheap one.*

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `2026-09-22-the-counter-that-answers-the-question-was-already-there` — pool `6de755d`.

### 11 — Commit
`05bab98`  (pushed to origin/wip before this report)
