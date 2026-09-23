## Form B Report — T-P0-146 / P6.92 — Three numbers the map ruling needs
**Class:** measurement. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-23 (HEAD `5f4b26d`, wip). git status clean at t0.

### 1 — Summary

★★★★★ **§4A's answer is yes, and it makes the ruling much easier than the Orchestrator expected.**
A host-side census tapped every MMU aperture and bucketed reads and writes by `P3_PHASE`:
**slot 4 (`$8000-$9FFF`, the arena's high aperture) is completely silent — 0 reads, 0 writes — from
the end of `interpret` until the next cycle's `interpret`.** That window covers sprites, roomcheck,
every room-render sub-step and the whole composite. ★★★ **The same taps see 83,357 accesses there
in other phases**, so the zero is a measurement, not a dead instrument.

> ★★★★★ **A cel cache can be placed. Map its block into slot 4 at draw-phase entry; restore the
> arena's high block at exit. Two MMU writes per cycle, ~14 cycles, against ~16% of a cycle.**

★★★★★ **§4B: the right shape is PER-LOOP, and it beats the 20-slot cache.** Caching whole loops,
LRU over loops: **3 loops = 4,006 B = 99.3% hit**, against the 20-slot LRU's 95.4% at 3,906 B.
★★★★ **A better hit rate, for 100 more bytes, with a three-entry policy instead of twenty** — and
**4,006 B fits slot 4's 8,192 with room for double.**

★★★★★ **§4C, and it is the largest finding in this task: the engine is not the problem.**
**Room 83, zero sprites: 0.0668 s/cycle = 15.0 cycles/second.** **Room 1, four sprites:
0.2336 s/cycle = 4.3.** ★★★★ **Same build, same run, same window** — the run starts in 83 and jumps
to 1 at cycle 9. **Four sprites cost 0.1668 s/cycle, 71.4% of the castle's standing cycle.**

> ★★★★★ **15.0 cycles/second is faster than AGI's PC 10/second and 2.5× Sierra's ≥5.87.**
> ★★★★ **Most of our Sierra gap is WORKLOAD, not engine speed** — their idle rooms animate ~nothing
> and our castle composites 3.11 cels every cycle standing still.

**`src/` change is a comment-only publish** (§9 delta 1); **all nine arms byte-identical by
SHA-256** (AC-5).

### 2 — Files modified
- `src/harness/p3b_probe.s` — **comment only**, at the region-A assert: §4A's slot census and
  verdict, and §4B's per-loop curve (§9 delta 1). ★ Arms re-verified byte-identical after.
- `harness/tools/p3b_run.lua` — `P3B_SLOTCENSUS`: per-aperture read/write taps bucketed by phase.
- `harness/tools/p3b_show.ps1` — `-SlotCensus`.
- `harness/tools/cel_reuse.py` — `--cel-sizes` and `loop_sim()`, the per-loop byte curve.
- `harness/tools/cel_runs.py` — `--tsv`, so one producer supplies the cel sizes.
- `harness/tools/gates.manifest` — the idle figure beside the castle's (§9 delta 2).

### 3 — Reasoning

**§3(1) — the nine arms** are at P6.90's figures, SHA-256 verified (§5); P6.91 and P6.91b moved no
shipped byte and neither did this task.

**§3(2) — which slots `cp_composite` holds, in full.** ★★★★★ **Measured, not read off the map**,
because reasoning from the map is exactly how the two `$FFA6` defects happened [P6.74, P6.78]:
*a cache of a register's contents is wrong the moment anyone else writes that register.*

| slot | aperture | holds | phase 9 (composite) |
|---|---|---|---|
| 0 | `$0000-1FFF` | status, stacks, VM state, DIRS, **`CP_CEL`** | 293,078 r / 185,457 w — **LIVE** |
| 1 | `$2000-3FFF` | code | 762,448 r — **LIVE** (fetches) |
| 2 | `$4000-5FFF` | code + reserved | 4,347,707 r / 233,883 w — **LIVE** |
| **3** | `$6000-7FFF` | **arena low** | **0 r / 0 w** |
| **4** | `$8000-9FFF` | **arena high** | **0 r / 0 w** |
| 5 | `$A000-BFFF` | priority slice / vocab | 17,204 r / 36,651 w — **LIVE** |
| 6 | `$C000-DFFF` | framebuffer slice / volume window | 36,239 r / 8,539 w — **LIVE** |
| 7 | `$E000-FEFF` | tables / text engine | 759 r — **LIVE** |

★★★★ **Slot 7 is not a candidate on two independent grounds**: it shows traffic during the
composite, **and it is not free anyway** — `p3b_probe.s:4020` names *"slot 7's hole"* as the home of
the text engine, the font, the parser buffers and the flat vocabulary, with `MAP_COVERAGE` at
`$FC00`. ★★ It is also **never remapped**: `mmu_phase.s` defines `MMU_SLOT3/4/5/6` only, and
`reg_discipline` confirms **`$FFA7` is written nowhere in the tree.**

★★★★★ **The borrow window is wider than phase 9, and that distinction decides the answer.** A slot
handed to a cache at draw-phase entry is away until draw-phase exit, so "silent in the composite" is
not yet "safe to borrow". Per phase:

| | slot 3 (arena low) | slot 4 (arena high) |
|---|---|---|
| 0 (boot/leaving) | 14,712 r / 11,314 w | 19,114 r / 8,241 w |
| 3 interpret | 67,592 r / 63,955 w | 28,528 r / 27,474 w |
| **7 roomcheck** | **4,456 r / 2,752 w** | **0** |
| 5 sprites, 9 composite, 13–22 render | **0** | **0** |

★★★★★ **So slot 4 is the one.** Slot 3 is busy during `roomcheck`, which is where the picture is
fetched — it would be borrowable for the composite alone, but not for the draw phase.

**§3(3) — where the decode reads from.** P6.83 made the VIEW read **in place through the volume
window**, which is **slot 6** [`VC_SRC_WINDOWED`]. ★★★★ **That is why the arena is silent**: the
decoder no longer reads the VIEW out of the arena at all. ★★★ **And it means the cache does not
conflict with the decode source** — slot 6 carries the compressed VIEW, slot 4 would carry the
decoded cels, and they are different apertures.

**§3(4) — `cel_reuse.py`'s policy knobs.** It had LRU over cels and a fixed slot count. ★★ **A
per-loop policy needed more than a flag** [§6 trigger 3]: `loop_sim()` plus a byte table, because
**the ruling needs a curve in bytes and the tool had no notion of a cel's size.** `cel_runs.py`
already walks every cel, so `--tsv` was added there rather than creating a second size source —
**one producer, so the two tools cannot disagree.**

**Authority tier.** Every figure is **measured in this tree**. ★ Sierra's comparators are cited from
T-P0-144 (tier 2, the running original). ★★ P6.90's 95.4%/3,906 B is **cited, not re-derived** [§2].

**§2H's three checks.** (1) *A second mechanism for a different object class?* Yes, and it is §4C:
the cost decomposes into **engine** and **sprite workload**, and every prior figure in this arc
conflated them. (2) *The calling routine.* `vc_decode_row` is called from `cp_composite`'s row loop,
so the cache's lifetime is the **draw phase**, not the decode — which is why the borrow window, not
phase 9, is the question. (3) *Grep the reports.* P6.65 (arena widening closed by exhaustion), P6.82
(`$FFA6` one owner), P6.83 (VIEW read in place), P6.90 (the curve) agree; **none contradicts, and
P6.65's closure is about address space, which is precisely what this task re-opened by asking a
narrower question.**

**§2S.** No sibling claim is made.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement]** §4A's slot enumeration at decode time, and the verdict — **PASS.**
  Table in §3(2). ★★★★★ **Verdict: a banked cel cache IS possible, via slot 4**, free for the whole
  draw phase, at two MMU writes per cycle. ★★ **Slot 3 is free for the composite but not for
  `roomcheck`; slots 5, 6, 7 are live; slots 0-2 carry code.**

- **AC-2 [class: measurement]** §4B's per-loop curve, hit rate against **bytes** — **PASS.**
  Moving, room 1, cycles 11–119, 434 decoded requests over 3 loops:

  | loops cached | hit rate | high-water bytes | decodes/cycle avoided |
  |---|---|---|---|
  | 1 | 25.1% | 2,100 | 1.00 |
  | 2 | 25.6% | 3,252 | 1.02 |
  | **3** | **99.3%** | **4,006** | **3.95** |

  Loop sizes: `v0.l1` (ego walk) 1,152 B · `v97.l0` 2,100 B · `v107.l0` (alligators) 754 B.
  ★★★ **Still a cliff** — the three loops sweep concurrently, so all must be resident; 1 and 2 loops
  buy only the intra-cycle duplicate. ★★★★ **Against P6.90's 20-slot LRU (95.4% at 3,906 B), the
  per-loop form is better on hit rate for 100 more bytes and needs a three-entry table.**

- **AC-3 [class: measurement]** §4C's idle figure, mean and median, with the engine-versus-workload
  statement — **PASS.**

  | | median | mean | cycles/s |
  |---|---|---|---|
  | **room 83, 0 sprites** | **0.0668 s** | 0.1951 s | **15.0** |
  | **room 1, 4 sprites** | **0.2336 s** | 0.3162 s | **4.3** |

  ★★ Window cycles 11+; **means include boot and a room render and are quoted only for
  completeness** — room 83's `p25 = p50 = p75 = 0.0668` is rock steady, and 23 of 120 cycles above
  2× median hold 71.8% of the time (boot + renders).
  ★★★★ **Room 83 verified idle FRESH** — `sprites 0` on every one of 120 cycles, not taken from
  P6.51 [§6 trigger 4].

  > ★★★★★ **The statement: our engine runs at 15.0 cycles/second. Four sprites cost 0.1668 s/cycle
  > — 71.4% of a standing castle cycle. Most of the Sierra gap is workload, not engine speed.**
  > ★★★ 15.0 is faster than AGI's PC 10/second and 2.5× Sierra's ≥5.87; Sierra's idle rooms animate
  > ~nothing (0.00–0.40 events/s) while ours composites 3.11 cels every cycle standing still.

- **AC-4 [class: measurement]** §4D's candidate list — **PASS.**

  | candidate | number | source |
  |---|---|---|
  | **Per-loop cel cache in borrowed slot 4** | **99.3%, 4,006 B, ~16% of a cycle** | AC-1 + AC-2 |
  | **Skip decode when the sprite is fully occluded** | ★★★★ **ZERO in the castle** — `co_rej_pri` is 0; no pixel is ever priority-rejected | P6.89, cited in `composite.s` |
  | Decode only the rows the blit uses (clipped sprites) | **unknown** — no clip census exists; room 1's cels sit fully on screen, so likely ~0 there | — |
  | A smaller decoded representation (4 bpp) | halves `CP_CEL` traffic and the cache to ~2,003 B; **changes `vc_decode_row`'s output** = **option 3, deferred** | P6.89 §2 |
  | Intra-cycle dedup | ★★ **dead** — room 1 only, hottest-loop restructure | P6.91b |

  ★★ **None pursued** [§4D].

- **AC-5 [class: byte-comparable]** **PASS — a publish only.** `git diff --stat -- src/` is
  **`src/harness/p3b_probe.s | 26 ++++++`, comment-only**, and **all nine arms are byte-identical by
  SHA-256** after it (§5).

- **AC-6 [class: suite]** **PASS by §2T citation.** `src/` carries a comment-only publish that moved
  no byte (AC-5), so no artifact changed. Cited from **P6.91b's report §5, run 2026-09-23 at HEAD
  `1f5bdb7`**: `pic` 45/45, `res` 1,264/1,264, `cel` 9,193/9,193, `comp` 124/124, `vm` 9/9, nine
  arms and five probes byte-identical. ★ No sibling was touched, so §2T's HEAD/clean check does not
  apply.

- **AC-7 [class: ruling requested]** **PASS** — §7.

- **AC-8** **PASS.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
=== §4A, the slot census, 40 castle cycles (p3b_show.ps1 -SlotCensus) ===
    ── SLOT CENSUS: traffic per aperture, by stage [T-P0-146 §4A] ──
       region                             phase 9 COMPOSITE      all other
       slot0 $0000-1FFF code/VM/CP_CEL     293078 r 185457 w       1497939
       slot1 $2000-3FFF code               762448 r  26761 w       6610776
       slot2 $4000-5FFF code/reserved     4347707 r 233883 w      12142580
       slot3 $6000-7FFF ARENA low               0 r      0 w        164781   ★ SILENT in composite
       slot4 $8000-9FFF ARENA high              0 r      0 w         83357   ★ SILENT in composite
       slot5 $A000-BFFF priority/vocab      17204 r  36651 w       1421618
       slot6 $C000-DFFF fb / volume         36239 r   8539 w        797944
       slot7 $E000-FEFF tables/text           759 r      0 w        262337

=== §4A, the BORROW WINDOW -- every phase, the two candidates ===
       ── slot3 $6000-7FFF ARENA low, EVERY phase ──
          phase  0 (leaving)        14712 r     11314 w
          phase  3 interpret        67592 r     63955 w
          phase  7 roomcheck         4456 r      2752 w      <-- busy; not borrowable for the draw phase
       ── slot4 $8000-9FFF ARENA high, EVERY phase ──
          phase  0 (leaving)        19114 r      8241 w
          phase  3 interpret        28528 r     27474 w      <-- and NOTHING else. Free from 3's end.

=== §2W: the zero is a measurement, not a dead tap ===
the SAME taps on slots 3 and 4 read 164,781 and 83,357 accesses in other phases.
A region that never fired anywhere would be a broken tap; these fire, and not in the draw phase.

=== §4B, the per-loop curve in BYTES (cel_reuse.py --cel-sizes) ===
  distinct (view,loop,cel) among decoded: 20 over 434 requests -- mean 21.70 uses each
  ── PER-LOOP cache, LRU over whole loops, priced in BYTES [§4B] ──
     3 distinct loop(s) in the decoded stream: v0.l1, v97.l0, v107.l0
      1 loop :  25.1% hit   high-water  2100 B   (1.00 decodes/cycle avoided)
      2 loops:  25.6% hit   high-water  3252 B   (1.02 decodes/cycle avoided)
      3 loops:  99.3% hit   high-water  4006 B   (3.95 decodes/cycle avoided)
        v0.l1 = 1152 B    v97.l0 = 2100 B    v107.l0 = 754 B
  ★ 26 cel sizes written to build\castle_cels.tsv

=== §4C, the idle figure -- ROOM 83, verified idle FRESH ===
cycle   3  0.0668 s  room  83  sprites  0  remaps 45  err 0
cycle 120  0.0668 s  room  83  sprites  0  remaps 304  err 0
median 0.0668 s/cycle = 14.98 cycles/second
mean   0.1951 s/cycle = 5.13 cycles/second
min 0.0668  p25 0.0668  median 0.0668  p75 0.0668  p90 0.4506  max 4.6727
final room 83, sprites 0, err 0, status=$00

=== §4C, the castle, SAME BUILD, and it reproduces the cited figure exactly ===
cycle 120  0.2503 s  room   1  sprites  4  remaps 314  err 0
median 0.2336 s/cycle = 4.28 cycles/second
mean   0.3162 s/cycle = 3.16 cycles/second
min 0.0668  p25 0.2169  median 0.2336  p75 0.2503  p90 0.2670  max 6.1412
   -- 0.2336 is P6.90's standing median to the digit, from an independent run

=== AC-5 ===
$ git diff --stat -- src/
 src/harness/p3b_probe.s | 26 ++++++++++++++++++++++++++
 1 file changed, 26 insertions(+)          <-- comment only
p3b_comb_count  19371 B  A3DD030C  OK
* all 9 arms byte-identical to the recorded baseline (SHA256)

=== mojibake, all six touched files ===
src/harness/p3b_probe.s clean · harness/tools/gates.manifest clean
harness/tools/cel_reuse.py clean · harness/tools/cel_runs.py clean
harness/tools/p3b_run.lua clean · harness/tools/p3b_show.ps1 clean
exit=0
```

**25.2 bundled-artifact grep:** N/A — nothing was built or bundled.

**25.3 operator-runtime-smoke:** **N/A — not offered.** The nine shipped arms are byte-identical to
the build Jay watched at T-P0-141/142; nothing was built.

### 6 — Reactive deviations and route accounting

1. ★★★ **`cel_reuse.py` could not model a per-loop policy with a flag** [§6 trigger 3, which asks me
   to say what it would take]. **It took `loop_sim()` plus a byte table** — about 40 lines — and
   `--tsv` on `cel_runs.py` so the sizes have **one producer**. ★★ Both are host-side tools; no
   `src/` behaviour changed.
2. ★★★ **The first census printed slot 2 under a slot 3 heading** — `REGIONS` is 1-indexed and I
   wrote `for i = 3, 4`. ★★ **Caught because the phase-9 figure in the orphan block was
   4,347,707 r, byte-identical to slot 2's row in the table above it.** Fixed to `for i = 4, 5`;
   the note is in the source so the next reader does not repeat it.
3. ★ **A comment-only `src/` publish was taken**, which AC-5 and §4's header both permit, because
   §9 delta 1 asks for §4A's verdict to be readable from the tree and that is the point of the task.
   **Arms verified byte-identical after.**

**ROUTE ACCOUNTING.** I proposed no route beyond the dispatch. **Nothing was built** [§6 trigger 1].
What this change contains: one comment block in `src/`, one new host-side census, one new offline
policy in `cel_reuse.py`, one TSV emitter, and one manifest note. What it does **not** contain: any
cache, any slot borrow, any change to `mmu_phase.s`, and any shipped byte.

### 7 — Uncertainty flags, and AC-7's ruling request to Jay

★★★★★ **The three numbers, and they point the same way:**

> **1. The cache CAN be placed.** Slot 4's aperture is silent for the entire draw phase. Borrow it
> at draw-phase entry, restore the arena's high block at exit: **two MMU writes per cycle.**
>
> **2. Per-loop is the shape, and it is cheap.** **3 loops, 4,006 B, 99.3%** — better than the
> 20-slot LRU's 95.4% at 3,906 B, with a three-entry table. **Slot 4 is 8,192 B.**
>
> **3. But the engine was never the problem.** **Room 83, no sprites: 15.0 cycles/second.** The
> castle's four sprites cost **71.4%** of a standing cycle. **Most of the Sierra gap is workload.**

**What I am asking you to rule on:**

1. ★★★★★ **Take the slot-4 borrow?** It is the first placement in this arc that needs no map
   reshuffle and no region-A space. ★★★ **The risk is real and named**: the arena is unreachable
   while the slot is away, and two `$FFA6`-class defects [P6.74, P6.78] came from exactly this kind
   of assumption. **The census says nothing reads it; a guard arm should prove that before it
   ships.**
2. ★★★★ **Is 15.0 cycles/second the answer to "is the engine fast enough"?** If so, **the speed
   work's target moves from the interpreter to the drawing path**, and the cel cache is the whole
   remaining item rather than one of several.
3. ★★★ **Does the map ruling still need taking?** ★★ **It is still needed for `-IfRec` and region
   A's diagnostics** — but **the cel cache, its motivating case for six tasks, no longer depends on
   it.** That may change its priority.

**Uncertainty flags:**
1. ★★★★ **The census is room 1, 40 cycles, one probe configuration.** A room whose LOGIC reads the
   arena during the draw phase would break the borrow. ★★★ **The engine's map differs from the
   probe's** — in the engine, slot 7 is `MAP_TABLES` with a real hole; in `p3b` it is the text
   engine. **The slot-4 result is about the arena and should transfer, but it has been measured on
   the probe only.**
2. ★★★★ **"Silent" was measured, not proven.** A read tap counts accesses that happened in this run;
   it cannot show that none can happen. ★★★ **Before a borrow ships it needs a guard arm** — map a
   poison block into slot 4 during the draw phase and assert nothing faults — **which is §2W applied
   to the thing itself rather than to its measurement.**
3. ★★★ **The per-loop curve is room 1's three loops.** A room with five concurrent loops needs five
   resident; **4,006 B is this room's number, not a bound.** The corpus mean is 372 B/cel, so a
   9-cel loop averages ~3.3 KB.
4. ★★ **Room 83 is not Sierra's idle room.** It stages **zero** sprites; Sierra's has a standing ego.
   **It isolates the engine from sprite work, which is the decomposition asked for** — it is not a
   like-for-like scene match.
5. ★ **`co_rej_pri = 0` is cited from P6.89**, not re-measured here.

### 8 — Follow-up candidates

1. ★★★★★ **The slot-4 borrow, with a poison-block guard arm** — §7(1), §7(2).
2. ★★★★★ **The per-loop cache at 4,006 B / 99.3%** — the item the last three tasks have been
   circling, now unblocked.
3. ★★★★ **Re-run the census in the ENGINE's map** when one exists — §7(1).
4. ★★★ **A clip census**, to price "decode only the rows the blit uses" — AC-4's one unknown.
5. ★★★ **The map ruling's priority may have changed** — §7(3).
6. Carried, unchanged: the VIEW checksum gap; design spec §7.1's `0.039 s/cycle` (sixteen tasks
   flagged); the fill and the two core loops as rulings; option 3 and the sidecar; a scene
   separating P6.88's two guards; real-time pacing; typing cadence; the title page items;
   `checkPriority`/`checkCollision`; `p3_stage_sprites` has no sort [P6.91b §8(3)];
   `MAP_PRI_BANDS` (thirty-seventh task — ★ **`memmap.inc` is a §6 stop trigger, so the counter was
   NOT bumped**).

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-23-ask-whether-the-resource-is-free-when-you-need-it.md`

### 11 — Commit
(recorded below after push)
