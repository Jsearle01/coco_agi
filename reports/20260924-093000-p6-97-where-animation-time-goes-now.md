## Form B Report — T-P0-151 / P6.97 — Where does animation time go NOW, and what do they spend per pixel?
**Class:** measurement. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-24 (HEAD `db9baea`, wip). git status clean at t0.

### 1 — Summary

★★★★★ **The cel cache did exactly what it was built to do: cel decode went from 27.6% of the drawing
stage to 2.7% — a 10× collapse** — at a 95.3% live hit rate. ★★★★ **And the drawing stage itself fell
from 65.5% of the cycle to 48.7%**, with `interpret` now **37.5%**: the drawing path is no longer most
of a cycle.

**The class table, same window (KQ1 room 1, cycles 11-120), moving:**

| | now | P6.87 |
|---|---|---|
| blit | **46.2%** | 35.0% |
| restore walk | **20.3%** | 8.5% |
| plane window access | **15.1%** | 18.6% |
| **cel decode** | **2.7%** | **27.6%** |
| key scan · resource mgr · MMU phase · other | 5.2 · 3.9 · 3.9 · 2.7% | — · 8.2 · 1.8% |

★★★ **The restore walk more than doubled its share without changing**: same work, smaller
denominator. **A share is not a cost** — the trap P6.84 spent a task correcting.

★★★★★ **The largest item is `cp_composite` at 38.0% (42.8% standing).**

★★★★★ **And the per-unit costs are ~5× a 6809 floor, which is the actionable finding:**

| | measured | floor | |
|---|---|---|---|
| blit, incl. the plane access it calls | **159 cycles per pixel TESTED** | ~32 | **5.0×** |
| restore, incl. its plane access | **46 cycles per byte put back** | ~10.5 | **4.4×** |

> ★★★★★ **Two independent paths, both ~4–5× over, and the factor they share is WINDOWED PLANE
> ACCESS** — a 26,880 B plane reached through an 8 KB aperture, one address computation per unit.
> ★★★★ **So §4C's answer is per-pixel COST, not workload, and the target is the ADDRESSING.**

★★★ **Sierra's side is not reducible to cycles-per-pixel** — their pixel count is not observable from
outside — **but one thing is measurable and informative: their total bus write rate is FLAT at
96–101 K writes/s** across pen-standing, pen-walking and P6.91's walking. **Animation is a
perturbation on their traffic, not a driver of it**, and ~100 K writes/s is **17.9 cycles per write**
at the measured clock.

**`src/` change is a comment-only publish** (§9 delta 1); **all nine arms byte-identical.**

### 2 — Files modified
- `src/harness/composite.s` — **comment only**: P6.87's class table marked superseded and replaced
  with this task's, plus the two per-unit costs and the windowed-access conclusion (§9 delta 1).

### 3 — Reasoning

**§3(4) FIRST, as §7 instructs — and it paid again, partly.** ★★★★ **The write census in
`build/sierra_pen/frames.csv` answered the Sierra half without a new operator run**, exactly as
P6.96 found. ★★★★★ **But not in the form §4B specified**: the census buckets are 4 KB of the CPU map,
and in the pen's standing window they show **99,818 writes/s total** while two small chickens
animating at ~2.12 events/s can account for only a few hundred pixel-writes per second. **The plane
aperture cannot be identified among the buckets, and most writes are not pixels.** ★★★ §6's fifth
trigger applies to the *ratio*; the differential form below is what survives it.

**§3(3) — the cel cache's live rate: 95.3% (424 hit / 21 miss over 120 cycles), 21 entries, 4,198 of
8,192 B, 0 flushes, 0 bypassed.** ★★★ So §4A's decode row can be read against it, and it is
consistent: a 95.3% hit rate collapsing decode 10× is the expected shape.

**§3(2) — `pc_profile.py --stage 9` and the marks.** Stage 9 is confirmed as **restore + composite**
— the profiler's own stage readout says `composite 15280 100.0%` with `prp_copy` inside it, so the
restore walk is in stage 9 and the class table must account for it separately. ★★ Both runs used
`P3B_PROFILE="11-120"` at 997 Hz, coprime to 60.

★★★★ **A limitation of the symbol map that changes how the table must be read**: the `.map` carries
global symbols only, so local labels inside the blit (`co_pix`, `co_opaque`, `co_depth`, `co_nextx`,
`co_rownext`) are **absorbed into `cp_composite`**. ★★★ **"`cp_composite` 38.0%" therefore means "the
whole per-pixel blit body", not one routine** — which is why §4A(2)'s top-25 is reported as classes
as well as rows.

**§3(1)** — nine arms at P6.95's re-baselined figures, verified after this task's comment edit.

**Authority tier.** Our figures are **measured in this tree** at a **measured clock (1.789772 MHz,
160,009 cycles calibrated)** — not assumed, which matters because this file once printed 1.789 MHz as
a constant while the machine ran at half that. Sierra's are **tier 2, observed from outside**.

**§2H's three checks.** (1) *A second mechanism for a different object class?* ★★★★★ **Yes, and it is
the finding**: the **restore** walk is a second per-byte path with the same ~4–5× overrun as the
blit, and looking only at the blit would have attributed the cost to the pixel loop alone.
(2) *The calling routine.* `plane_vis`/`plane_pri` are **callees of both** the blit and the restore,
and the profiler cannot attribute a callee to its caller — hence §7(1)'s stated assumption.
(3) *Grep the reports.* P6.87 (the stale table), P6.93 (the cache), P6.94 (the ~6×), P6.96 (the
census) agree; **P6.87's table was cited in four dispatches after it went stale and nobody
re-measured** — this task's origin.

**§2S.** No sibling claim is made.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement]** **PASS** — §1's class table, and the top routines both ways:

  | # | routine | class | moving | standing |
  |---|---|---|---|---|
  | 1 | `cp_composite` | blit body | **38.0%** | **42.8%** |
  | 2 | `prp_copy` | restore | 11.1% | 10.4% |
  | 3 | `plane_pri` | plane access | 8.9% | 9.8% |
  | 4 | `plane_vis` | plane access | 6.2% | 8.7% |
  | 5 | `co_put_visual` | blit | 5.5% | 7.2% |
  | 6 | `HAL_key_scan` | key scan | 5.2% | — |
  | 7-10 | `prp_priority` · `prp_visual` · `prp_split` | restore | 3.8 · 3.1 · 2.3% | 2.4 · 2.1 · 1.5% |
  | 11 | `co_checkctrl` | blit | 2.1% | 1.3% |
  | 12 | **`vc_decode_row`** | **decode** | **1.5%** | **0.9%** |

  ★★ Top 25 cover 97.8% of stage-9 samples; 42 routines seen; 15,280 stage-9 samples moving, 10,606
  standing.

  ★★★★ **§4A(4): the stage's share of the whole cycle is 48.7%, not 65.5%.** Full table:
  pace 0.2% · **interpret 37.5%** · sprites 0.8% · roomcheck 12.8% · **composite 48.7%**.

  ★★★ **§4A(3), per sprite and per pixel**: 725.4 pixels tested and 255.9 written per cycle; 395.8
  key-rejected, 73.8 priority-rejected; 3.71 cel lookups/cycle; 1,107 bytes restored per cycle.

- **AC-2 [class: measurement]** ★★★★★ **PASS, in one sentence: the largest item is now
  `cp_composite`, the per-pixel blit body, at 38.0% moving and 42.8% standing** — and **the cel cache
  took decode from 27.6% to 2.7%**, a 10× collapse that also dropped the whole stage from 65.5% of a
  cycle to 48.7%.

- **AC-3 [class: measurement]** ★★★ **PASS for ours; NOT DETERMINABLE for theirs, with the reason.**

  **Ours** (shipped arm, 0.2336 s/cycle, composite 48.7%, clock measured):
  - **159 cycles per pixel tested** in the blit including its plane access; **281 cycles/tested pixel**
    if the whole composite stage is charged to it; **796 per pixel *written***.
  - **46 cycles per byte** in the restore including its plane access.
  - ★★ **Error bars**: the `-Count` arm reads 341 and 966 rather than 281 and 796 because the counters
    themselves cost — **the pixel counts come from that arm and the times from the shipped one**, and
    the pixels drawn are identical in both. The 70/30 plane-access attribution is an assumption
    (§7(1)). The ~32-cycle floor is **my own arithmetic, labelled unverified per §8**.

  **Theirs: not reducible to cycles per pixel.** ★★★★ Their pixel count is not identifiable — 99,818
  writes/s in a window where the animation can account for a few hundred — so the dispatch's
  "writes into the visible plane's aperture ≈ pixels drawn" **rests on an assumption I cannot check**
  [§4B's own last line, §6's fifth trigger]. ★★ **A bucket is an aperture, not a destination**
  [P6.96].

  ★★★★★ **What is measurable, and it is the differential form that worked at P6.94:**

  | Sierra window | writes/s | FDC | lattice/s |
  |---|---|---|---|
  | pen standing, 2 chickens | **99,818** | 1 | 2.2 |
  | pen walking, +ego | **96,102** | 0 | 18.2 |
  | P6.91 walking, near-empty room | **101,350** | 0 | 7.6 |
  | P6.91 idle (disk active) | 58,653–76,081 | 14,829–19,202 | 0.0–0.6 |

  ★★★★ **Flat at 96–101 K writes/s across every disk-quiet window regardless of animation load** —
  **17.9 cycles per write** at the measured clock. **Animation is a perturbation on their bus
  traffic, not a driver of it.**

- **AC-4 [class: attribution]** ★★★★★ **PER-PIXEL COST, not workload.**

  > **Our blit spends 159 cycles per tested pixel where a load-test-read-compare-write-write-advance
  > floor is ~32, and our restore spends 46 cycles per byte where a 16-bit copy loop is ~10.5. Two
  > independent paths, both ~4–5× over, sharing one factor: every unit of work goes through a
  > windowed address computation because a 26,880 B plane does not fit an 8 KB aperture.**

  ★★★ **§4C asks what our pixel does that theirs might not, from our own routine table**: it calls
  `plane_vis`/`plane_pri` (15.1% of the stage), and `co_checkctrl` walks a column per pixel that sits
  on a control line. ★★ **Not inferred from their code** — §4C's own instruction.

- **AC-5 [class: process]** ★★★★★ **PASS.** **Nothing was written into their machine and no new run
  was performed** — the Sierra figures come from recordings Jay drove at P6.91 and P6.94.
  **No instruction of theirs was read or interpreted.** What was sampled on their side: per-frame
  **write counts** bucketed to 4 KB, FDC port accesses, and a 16×10 screen lattice — **"what address,
  how often", never "what instruction"**.

- **AC-6 [class: byte-comparable]** ★★ **A comment-only publish, not empty.**
  `git diff --stat -- src/` = `src/harness/composite.s | 27 +++`, **comment only**, and **all nine
  arms byte-identical by SHA-256** after it, plus every non-p3b probe byte-identical. ★★★ §9 delta 1
  asked for the stale table to be replaced where the next reader finds it, and that is `src/`.

- **AC-7 [class: suite]** **PASS by §2T citation.** The `src/` edit moved no byte (AC-6), so no
  artifact changed. Cited from **P6.95's report §5, run 2026-09-24 at HEAD `7b284d1`**: `comp`
  124/124, `cel` 9,193/9,193, `res` 1,264/1,264, `pic` 45/45, five p3b probes, *"all green"*,
  exit 0. ★ No sibling touched.

- **AC-8 [class: ruling requested]** **PASS** — §7.

- **AC-9** **PASS.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
=== §3(3), the cache's live rate ===
CEL CACHE over 120 cycles: 424 hit / 21 miss = 95.3% hit   (3.71 lookups/cycle)
   flushes 0   bypassed 0   resident: 21 entries, 4198 of 8192 B used

=== §4A, stage 9, MOVING (pc_profile.py --stage 9) ===
# window cycles 11-120  hz 997  samples 26605  span 26.6841 s
  composite  15280  100.0%   [cp_composite 38%, prp_copy 11%, plane_pri 9%, plane_vis 6%]
   1 cp_composite     compositor            5809  38.0%
   2 prp_copy         restore walk          1690  11.1%
   3 plane_pri        plane window access   1361   8.9%
   4 plane_vis        plane window access    949   6.2%
   5 co_put_visual    compositor             833   5.5%
   6 HAL_key_scan     key scan               787   5.2%
   7 prp_priority     restore walk           582   3.8%
   8 prp_visual       restore walk           468   3.1%
  11 co_checkctrl     compositor             315   2.1%
  12 vc_decode_row    cel decode / blit      224   1.5%
  17 vc_decode_begin  cel decode / blit      103   0.7%
  22 vc_rd8           cel decode / blit       82   0.5%
     top 25 cover 97.8% of samples; 42 routines seen

=== §4A, stage 9, STANDING ===
   1 cp_composite  4541  42.8%    2 prp_copy 1108 10.4%   3 plane_pri 1036  9.8%
   4 plane_vis      928   8.7%    5 co_put_visual 761 7.2%  12 vc_decode_row 100 0.9%

=== §4A, classes, MOVING, against P6.87 ===
blit 46.2%  restore 20.3%  plane access 15.1%  DECODE 2.7%
   (P6.87: compositor 35%, restore 8.5%, plane 18.6%, DECODE 27.6%)

=== §4A(4), the whole cycle ===
pace(wait)  0.00062 s/cycle   0.2%      interpret 0.13510 s/cycle  37.5%
sprites     0.00281 s/cycle   0.8%      roomcheck 0.04603 s/cycle  12.8%
composite   0.17555 s/cycle  48.7%      (P6.87 had the stage at 65.5%)
clock MEASURED 1.789772 MHz (160009 cycles calibrated)

=== §4A(3) / §4B, our pixels (-Count arm, 120 cycles) ===
co_tested  : 87052      co_rej_key : 47491
co_rej_pri : 8857       co_WRITTEN : 30704
restore    : 132786 bytes put back, 4 rect(s) live from last frame
  -> per cycle: 725.4 tested, 255.9 written, 1107 bytes restored

=== §4B, our cycles per unit (shipped arm times, -Count arm pixel counts) ===
SHIPPED 0.2336 s/cycle = 418091 CPU cyc; composite 48.7% = 203610 cyc
   blit incl. plane access  56.8% = 115590 cyc -> 159 cyc/tested px   (floor ~32 -> 5.0x)
   restore incl. plane access 24.8% =  50556 cyc ->  46 cyc/byte      (floor ~10.5 -> 4.4x)
-Count arm for contrast: 341 cyc/tested px, 966 cyc/written px

=== §4B, THEIRS -- differential, disk-quiet windows, same instrument ===
pen STANDING, 2 chickens    63.3 s     99818 writes/s  fdc      1  lattice  2.2/s
pen WALKING, +ego           27.1 s     96102 writes/s  fdc      0  lattice 18.2/s
P6.91 walking (5.87/s)       7.7 s    101350 writes/s  fdc      0  lattice  7.6/s
P6.91 idle room              5.3 s     58653 writes/s  fdc  14829  lattice  0.0/s
P6.91 idle before RC3        10.0 s    76081 writes/s  fdc  19202  lattice  0.6/s
  -> flat at 96-101 K/s in every disk-quiet window = 17.9 cycles per write

=== AC-6 ===
$ git diff --stat -- src/
 src/harness/composite.s | 27 +++++++++++++++++++++++++++     <-- comment only
★ all 9 arms byte-identical to the recorded baseline (SHA256)
★ every non-p3b probe byte-identical        mojibake clean, exit=0
```

**25.2 bundled-artifact grep:** N/A — nothing built or bundled.

**25.3 operator-runtime-smoke:** **N/A — no run was offered.** The nine arms are byte-identical to
the build Jay watched at P6.95, and nothing was built; the Sierra figures reuse recordings he already
drove.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **§4B's prescribed derivation was not usable and the differential form replaced it.** The
   dispatch says *"writes into the visible plane's aperture per frame ≈ pixels drawn"*; **the
   aperture cannot be identified among 4 KB buckets, and 99,818 writes/s against a few hundred
   plausible pixel-writes shows most writes are not pixels.** ★★★ §6's fifth trigger says report the
   shape alone; **the write-rate table is that shape, and it carries a real finding (flatness) rather
   than an unverifiable ratio.**
2. ★★★★ **`cp_composite`'s 38% is a class, not a routine.** The symbol map has globals only, so
   `co_pix`/`co_opaque`/`co_depth` are absorbed into it. ★★★ **Noticed because those labels are
   absent from the top 25 while their work obviously happens** — had I read the row as one routine I
   would have attributed the whole blit to its entry code.
3. ★★★ **A comment-only `src/` publish was taken** where AC-6 asked for empty. §9 delta 1 requires
   replacing the stale table *where the next reader finds it*, which is `composite.s`; **arms
   verified byte-identical after.**
4. ★★ **`co_rej_pri` is no longer zero: 8,857 over 120 cycles (73.8 pixels/cycle).** P6.89 recorded
   it as **ZERO** in the castle and `composite.s` still says so beside `co_pix`. ★★★ **The sort
   [P6.95] changed draw order, so the depth test now rejects where a later drawer previously
   overwrote** — consistent with the planes staying byte-identical, since a rejected pixel and an
   overwritten one look the same. **Flagged, not chased** [§7(4)].

**ROUTE ACCOUNTING.** I proposed no route and asked Jay for nothing. What this change contains: one
comment block replacing a stale table. What it does **not** contain: any optimisation, any change to
the blit, any new recording, and any shipped byte.

### 7 — Uncertainty flags, and AC-8's ruling request to Jay

★★★★★ **Where animation time goes now, and what is left worth taking:**

> **The cel cache worked — decode is 2.7%, down from 27.6%, and the drawing stage is 48.7% of a
> cycle rather than 65.5%. The largest item is the blit at 38%. And our per-unit costs are ~5× a
> 6809 floor on TWO independent paths — 159 cycles per tested pixel, 46 cycles per restored byte —
> with one shared factor: windowed plane access.**

**What I am asking you to rule on:**

1. ★★★★★ **Is the windowed plane access worth a task?** ★★★★ **It is the only thing this arc has
   found that explains a ~5× overrun on two unrelated paths**, and it would attack the blit and the
   restore at once. ★★★ **The shape would be reducing address computations per unit** — a row-at-a-time
   base pointer instead of a per-pixel one — **not a faster inner loop.**
2. ★★★★ **The room cache is still unbuilt and still priced**: 0.237 s of copy against a 6.16 s render,
   ~5 s a door [P6.96]. **§1.2 put it out of scope here and §10 calls it its own task.** It is the
   largest single win in hand and it is not about animation.
3. ★★★ **`interpret` is now 37.5% of a cycle** — larger than it has ever been relative to drawing.
   **Nothing in this arc has profiled it.** If the drawing path keeps shrinking it becomes the target.

**Uncertainty flags:**
1. ★★★★★ **The 70/30 split of `plane_vis`/`plane_pri` between blit and restore is an ASSUMPTION.**
   The profiler cannot attribute a callee to its caller and both call them. ★★★ **The 159 and 46
   figures move with it**; the ~5× conclusion survives any split, because charging *all* plane access
   to either path still leaves the other over 3×.
2. ★★★★ **The ~32-cycle pixel floor and the ~10.5-cycle copy floor are my arithmetic**, not measured
   6809 timings from a reference. Labelled per §8. **A real floor would need a micro-benchmark.**
3. ★★★★ **Theirs is not a per-pixel figure and must not be quoted as one.** ~100 K writes/s is all
   bus traffic. ★★★ **The flatness across load is the finding; the rate is not comparable to ours.**
4. ★★★ **`co_rej_pri` went 0 → 73.8/cycle** and `composite.s` still records zero beside `co_pix`.
   **Not chased here** — it is a consequence of P6.95's sort and needs its own look.
5. ★★ **One room, one title, one window.** The castle is four objects with two sharing a view.
6. ★★ **`HAL_key_scan` is 5.2% of the drawing stage** and nothing in this arc has asked why the key
   scan runs there.

### 8 — Follow-up candidates

1. ★★★★★ **The windowed plane access** — §7(1). **~5× on two paths, one cause.**
2. ★★★★★ **The room cache** — §7(2). 0.237 s against 6.16 s, ~5 s a door, still unbuilt.
3. ★★★★★ **Put the cel cache in the gated arms** — P6.93 §7(1), **open across five tasks**.
4. ★★★★ **Profile `interpret`** — §7(3), now 37.5% and never profiled.
5. ★★★ **`co_rej_pri` 0 → 73.8** — §7(4); update `composite.s`'s note once understood.
6. ★★★ **A gated scene with overlapping sprites** — P6.95 §8(1).
7. ★★ **Why `HAL_key_scan` runs in stage 9** — §7(6).
8. Carried: region A at 151 B; the VIEW checksum gap; design spec §7.1's `0.039 s/cycle`; the
   static/regular sprite split; `sierra_rooms.py`'s `min_fdc` floor; option 3 and the sidecar;
   real-time pacing; `checkPriority`/`checkCollision`; `MAP_PRI_BANDS` (forty-second task — ★
   `memmap.inc` is a §6 stop trigger, not bumped).

### 9 — User interaction during task
None. ★★ Both halves used data in hand: our own profile from a fresh headless run, and Sierra's from
recordings Jay drove at P6.91 and P6.94.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-24-a-share-is-not-a-cost.md`

### 11 — Commit
(recorded below after push)
