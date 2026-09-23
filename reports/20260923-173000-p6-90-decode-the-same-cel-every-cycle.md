## Form B Report — T-P0-143 / P6.90 — We decode the same cel every cycle; the oracle decodes it once
**Class:** recon (the dispatch opened as integration; §6 trigger 2 fired at §4B and nothing was built). wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-23 (HEAD `9c49181`, wip). git status clean at t0.

### 1 — Summary

**§4A's measurement does not kill the cache, and the measurement the dispatch prescribed would have
killed it wrongly.** The adjacency rate — "is this staged sprite's `(view, loop, cel)` the same as
last cycle's" — is **25.0% standing and 0.7% moving**, which is §6's first trigger in as many words.
★★★★★ **It is also the wrong question.** Room 1 runs three animation loops of 6, 5 and 9 cels that
each advance **one cel per cycle**, and a cyclic sweep has *no* distance-1 reuse and *total*
distance-N reuse. Against the real decode sequence, **3.98 decodes/cycle collapse to 0.18 at 20
slots — a 95.4% hit rate** — while every cache size from 1 to 14 slots is flat at 25.1%.

**§4B then kills the placement, not the idea.** The castle's 20-cel working set is **3,906 bytes**.
Region A is full (`-IfRec` still refuses, AC-8), and MAP_INPUT's tail is P3_KQ's — about **74 bytes
free against 3,906 needed**. §6's *second* trigger fires: nothing fits without the map ruling, and
this is not the task that takes it.

★★★★ **One part of the win needs no storage at all.** All 109 of the 1-slot hits are *intra-cycle
adjacent duplicates*: room 1's two alligators share view 107 and swim in lockstep, staged
consecutively with an identical triple (x=147,y=161,prio 14 and x=104,y=135,prio 12 — two objects,
verified, not one staged twice). Decoding each row once and blitting it to both destinations reuses
the existing `CP_CEL` row buffer, changes no decoded byte, and keeps the `cel` gate's subject
intact. **Recorded as the recommended next task; not taken, because §6 stopped this one at the
census.**

**No shipped byte moved** — all nine arms byte-identical by SHA-256, all five non-p3b probes
byte-identical. The only source changes are two guarded test arms and four comment blocks.

### 2 — Files modified
- `src/harness/p3b_probe.s` — `-DP3B_CELSTATS` counter (`pcs_count`, out of line), its two §2W fault
  arms `-DP3B_CELSTATS_NEVER` / `-DP3B_CELSTATS_ALWAYS`, and the map-ruling fifth-symptom note.
- `src/harness/view_cel.s` — comment only: what P6.50 traded, priced (§9 delta 1).
- `harness/tools/p3b_run.lua` — `P3B_CELTRACE` host tap and the CELSTATS readout.
- `harness/tools/p3b_show.ps1` — `-CelStats`, `-CelStatsNever`, `-CelStatsAlways`, `-CelTrace`.
- `harness/tools/cel_reuse.py` — NEW. Offline LRU pricing of a decode trace.
- `harness/tools/cel_runs.py` — `--dims`, §3(3)'s `w × h` column.
- `harness/tools/gates.manifest` — what no gate here can see about re-decode (AC-11).

(Explicit-path staging only. `coco_agi.code-workspace` is untracked and left alone.)

### 3 — Reasoning

**§3(2) — where the counter goes.** `p3_prev` is 7 bytes: `x, ytop, w, h, view, loop, cel`, so the
cel identity is at `+4, +5, +6`; `p3_spr` is 6 bytes, `x, y, prio, view, loop, cel`, identity at
`+3, +4, +5`. The counter sits in `p3_skip_decide`'s `psd_each` loop, which already walks both.
★★ **Deliberately a different comparison from `prp_same`'s**, which also requires `x` and `y` to
match: a sprite that walks changes its rectangle every cycle and need not change its cel.

★ **It had to go out of line.** Inlining forty bytes put `psd_each`'s own `beq psd_out` and
`blo psd_each` out of 8-bit branch reach (lwasm "Byte overflow" ×2). A `jsr` costs the loop three
bytes when the guard is defined and nothing when it is not — which is why every shipped arm is still
byte-identical.

**§3(3) — cel dimensions** (`cel_runs.py --dims`, 8,682 cels across the six pinned titles, read-only):

| | bytes (`w × h`, one byte per pixel) |
|---|---|
| mean | 372.3 |
| median | 272 |
| p90 | 738 |
| p99 | 1,508 |
| max | 4,784 (Kingquest3 view 64 loop 0 cel 0, 46×104) |

79.0% of corpus cels are ≤ 512 B; 95.7% are ≤ 1,024 B. **The castle's four sprites use 20 distinct
cels totalling 3,906 B**: view 97 loop 0 is 5 × 420 B (42×10), the ego's view 0 loop 1 is 6 × 192 B
(6×32), and view 107 loop 0 is 9 cels of 143/143/104/104/52×5 = 654 B.

**§3(4) — what is free.** `MAP_INPUT` is $1C00–$2000, 1,024 B, and it is fully allocated:
`P3_PBUF` 576, `P3_TXDIAG` +576 (96), `CP_CEL` +672 (256), `P3_KQ` at $1FA0 (22). ~74 B remain.
Region A is full — see AC-8. **The arena is out of scope (§10).** So a cache of any useful size has
nowhere to live: §6 trigger 2.

**★★★★★ §2H, and this is the task's finding.** The adjacency rate is a real measurement of a real
mechanism and it is not the governing one. The dispatch's §1.1 reasons from persistence
("two cycles → ~50% waste"), which is correct for a sprite that *holds* a cel and silent about one
that *sweeps* a loop. §4A(2) asks what is **avoidable**, and avoidable is set by reuse distance, not
adjacency. Had this task reported 0.7% and stopped — which is exactly what §6 trigger 1 instructs —
it would have closed a 95.4% win with a correct number.

**★★ The three §2H checks, stated.** (1) *A second mechanism serving a different object class?*
Yes, and it is the whole finding: the ego **sweeps** a walk loop while a background prop may **hold**
a cel; `VMO_CYCLETIME` gates one and the walk gates the other. (2) *The calling routine.*
`p3_composite_all` decodes per staged sprite per cycle; the scope is "every draw", not "every
change" — which is what makes the sweep expensive. (3) *Grep the reports for the subsystem.*
P6.87 (`vc_decode_row` 26.6%), P6.88 (skip: −16% standing, **zero moving**) and P6.89 (runs not
reachable) agree and do not contradict: P6.88's zero-moving is the same sweep seen from the other
side.

**Authority tier.** The oracle claim is ScummVM at the pin — `unpackViewCelData` decodes once and
keeps the bytes with the VIEW [`view.cpp:357-370`]. ★ **Believed original rather than a ScummVM
normalisation**: it is a memory-management choice on the host side with no observable behaviour, so
§2.1's caution applies but nothing behavioural rests on it. Every rate, size and hit figure below is
measured in this tree, not cited.

**§2S.** No sibling claim is made in this report.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: measurement]** §4A's repeat rate, moving and standing, with the persistence
  distribution — **PASS.** Over 109 steady castle cycles (room 1, cycles 11–119, `P3B_ROOM=1`):

  | | standing | moving (`LEFT` held from cycle 12) |
  |---|---|---|
  | staged records | 4.00/cycle | 4.00/cycle |
  | actually decoded | 3.11/cycle (P6.88 skips 0.89) | 3.98/cycle (P6.88 skips 0.02) |
  | **same cel as last cycle** | **25.0%** (guest) / 24.8% (host) | **0.7%** (guest) / 0.0% (host) |
  | mean persistence | 1.33 cycles | 1.01 cycles |
  | distinct cels in flight | 15 | 20 |

  ★ **Persistence distribution:** there is no tail. Each of the three loops advances exactly one cel
  per cycle, so a cel persists 1 cycle and recurs at its loop period (6, 5 and 9 cycles). The 25.0%
  standing figure is the ego holding a single idle cel, not any cel persisting.

- **AC-2 [class: measurement]** §3(3)'s dimensions and §4B's price — **PASS**, §3 above. **§4B's
  answer:** with a 512-byte slot, 79.0% of corpus cels and **100% of the castle's** are cacheable;
  the policy that works is **not LRU** — a cyclic sweep is LRU-pessimal, and 1–14 slots are flat at
  25.1% — it is **hold the whole loop**, 20 slots / 3,906 B for 95.4%. Degradation is forced anyway
  (a cel above the slot size must fall through to today's path, `res_cache_stash`'s fail-closed
  precedent). **None of it is placeable: ~74 B free against 3,906 needed.**

  | LRU slots | moving hit | standing hit | decodes/cycle avoided (moving) |
  |---|---|---|---|
  | 1 | 25.1% | 32.2% | 1.00 |
  | 2–14 | 25.1% | 32.2–35.4% | 1.00–1.10 |
  | 16 | 49.1% | 95.6% | 1.95 |
  | 18 | 72.4% | — | 2.88 |
  | **20** | **95.4%** | 95.6% | **3.80** |

  ★ **Priced against the cycle:** `vc_decode_row` is 26.6% of the drawing stage [P6.87] and the
  drawing stage is 59% of a cycle [P6.87], so 95.4% of it is **~15% of the cycle**; the free
  two-destination blit is **~3.9%**. ★★ *Arithmetic from this task's rates against P6.87's shares —
  labelled unverified per §8; only the rates are measured here.*

- **AC-3 [class: state-comparable]** Both planes byte-identical to the pre-change build —
  **PASS, by a stronger instrument than the dump.** All nine arms are byte-identical by SHA-256
  (§5), so the pre- and post-change programs are *the same program*; the plane dump would have
  compared a binary with itself. ★★ **Stated rather than run, and stated as the reason** — P6.88's
  stale-dump incident is exactly the failure a self-comparison invites.

- **AC-4 [class: measurement]** §4D's four figures — **N/A, and that is §6's answer, not a gap.**
  Nothing was built, so there is no "after" to measure. Today's budget is unmoved: 0.2350/0.2336
  standing, 0.3063/0.3004 moving.

- **AC-5 [class: state-comparable]** Cache counters read by the host from the first run —
  **N/A (no cache built).** ★ The *measurement* counters were read from their first run and are in
  AC-1; P6.80's lesson is honoured in the only form available here.

- **AC-6 [class: state-comparable · fault injection]** An arm serving a stale cel — **N/A (no cache
  built).** ★★ **Replaced by the §2W arms that were needed instead**, on the instrument this task
  actually shipped: see §5.

- **AC-7 [class: byte-comparable · gate]** **PASS.** `pic` 45/45, `res` 1,264/1,264, `cel`
  9,193/9,193, `comp` 124/124, `vm` 9/9 — all fresh, verbatim in §5. **`cel_probe`, `comp_probe`,
  `res_probe` byte-identical**; no change was unconditional.

- **AC-8 [class: byte-comparable]** Region A's headroom and `-IfRec` — **PASS (still red,
  unchanged).** `-IfRec` fails with two asserts: *"P3b code has grown past MAP_RESERVED_END ($6000)
  into MAP_ARENA_WIN — region A is full."* ★ **Unchanged since P6.88 and not worsened by this task**,
  which added no unconditional code (all nine arms byte-identical).

- **AC-9 [class: suite]** **PASS.** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green
  (`run_gates.sh all` → "all green"). Fault arms red under their own scenarios: `p3b_arms_check
  -SelfTest` red (1 arm moved, as designed); `-CelStatsNever` 0.0%; `-CelStatsAlways` 100.0%.
  ★ **`-ForceOverlap` was re-run** and still drives `isolated` to 0 — P6.88's guards still refuse.

- **AC-10 [class: eye-gated — Jay]** ★★ **Not offered, and the reason is the finding.** The nine
  shipped arms are byte-identical to the build Jay watched at T-P0-141/142, so there is nothing to
  look at and nothing could be faster. AC-10's three questions all presuppose a change §6 stopped.
  **Per CLAUDE.md §4A.3, this task is a census, not an integration task, so "pending Jay" is not
  owed.**

- **AC-11 [class: measurement]** **PASS.** Arms re-baselined (all nine OK); `gates.manifest` records
  what no gate can see about re-decode, the `-CelTrace` instrument, and the `-CelStats` caution.

- **AC-12 [class: byte-comparable]** **PASS.** Verbatim in §5. ★ **`reg_discipline`: still one
  owner** — 6 accesses, 1 file (`mmu_phase.s`), 4 registers.

- **AC-13** **PASS.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
=== §2W: the CELSTATS fault arms, run BEFORE the figure was believed ===
-CelStatsNever :  CELSTATS over 120 cycles: staged-sprite records 444 (3.70/cycle),
                  cel UNCHANGED from last cycle 0 -- repeat rate 0.0%
-CelStatsAlways:  CELSTATS over 120 cycles: staged-sprite records 444 (3.70/cycle),
                  cel UNCHANGED from last cycle 444 -- repeat rate 100.0%, mean persistence 1000.00
live, standing :  CELSTATS over 120 cycles: staged-sprite records 444 (3.70/cycle),
                  cel UNCHANGED from last cycle 111 -- repeat rate 25.0%, mean persistence 1.33
live, moving   :  CELSTATS over 120 cycles: staged-sprite records 444 (3.70/cycle),
                  cel UNCHANGED from last cycle 3 -- repeat rate 0.7%, mean persistence 1.01
```

★★★★★ **`ALWAYS` counting all 444 is the load-bearing half**: it shows the `i >= p3_nspr` bail never
fires, so the entire 444 → 111 reduction is the three cel compares and nothing else.

```
=== §4A(2), cel_reuse.py, moving, cycles 11-119 ===
MOVING: 109 cycles (11..119), 436 staged records, 434 actually decoded (2 skipped by P6.88)
  staged 4.00/cycle, decoded 3.98/cycle
  distinct (view,loop,cel) among decoded: 20 over 434 requests -- mean 21.70 uses each
  ADJACENCY (host-side, cross-checks -CelStats): 0/436 = 0.0% unchanged from last cycle
  INTRA-CYCLE duplicates among decoded: 109 adjacent (1.00/cycle), 109 anywhere in the cycle
      -- adjacent ones need NO storage, only a two-destination row blit
  -- LRU hit rate on the DECODED stream --
      1 slot :   109 hit /   325 miss =  25.1% hit   (1.00 decodes/cycle avoided)
     12 slots:   109 hit /   325 miss =  25.1% hit   (1.00 decodes/cycle avoided)
     14 slots:   110 hit /   324 miss =  25.3% hit   (1.01 decodes/cycle avoided)
     16 slots:   213 hit /   221 miss =  49.1% hit   (1.95 decodes/cycle avoided)
     18 slots:   314 hit /   120 miss =  72.4% hit   (2.88 decodes/cycle avoided)
     20 slots:   414 hit /    20 miss =  95.4% hit   (3.80 decodes/cycle avoided)
     32 slots:   414 hit /    20 miss =  95.4% hit   (3.80 decodes/cycle avoided)

=== the trace itself, moving, six consecutive cycles ===
47 0.1.0:0 97.0.0:0 107.0.4:0 107.0.4:0
48 0.1.1:0 97.0.1:0 107.0.5:0 107.0.5:0
49 0.1.2:0 97.0.2:0 107.0.6:0 107.0.6:0
50 0.1.3:0 97.0.3:0 107.0.7:0 107.0.7:0
51 0.1.4:0 97.0.4:0 107.0.8:0 107.0.8:0
52 0.1.5:0 97.0.0:0 107.0.0:0 107.0.0:0

=== the two view-107 records are TWO OBJECTS, checked, not assumed ===
staged sprites: 4
[0] x=110 y=100 prio= 9 view=  0 loop=0 cel=0
[1] x=  5 y= 17 prio=15 view= 97 loop=0 cel=2
[2] x=147 y=161 prio=14 view=107 loop=0 cel=5
[3] x=104 y=135 prio=12 view=107 loop=0 cel=5

=== §3(3), cel_runs.py --dims, the six pinned titles ===
cels 8682   decoded bytes = w x h, one byte per pixel
  mean    372.3   median    272   p90    738   p99   1508   max   4784
  smallest 1 B, largest 46x104 = 4784 B (Kingquest3 view 64 loop 0 cel 0)
  cumulative share at or below:  <=256 B 47.3%   <=512 B 79.0%   <=1024 B 95.7%

=== AC-7 gates (run_gates.sh all) ===
* source integrity: clean
TOTAL (res)              1264     1264       1264        0          0
TOTAL (cel)              9193     9193       9193        0        0     1525
Kingquest3-v0 (comp)      124      124        124        0          0
* gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green

=== AC-7, vm ===
=== AC-2 SUMMARY ===
Kingquest1 PASS   Kingquest2 PASS   Kingquest3 PASS   SpaceQuest-1 PASS
SpaceQuest-2 PASS PoliceQuest1 PASS larry1 PASS       BlackCauldron PASS
MixedUpMotherGoose PASS

=== AC-8, -IfRec ===
src/harness/p3b_probe.s(4069) : ERROR : User Specified: "P3b code has grown past
  MAP_RESERVED_END ($6000) into MAP_ARENA_WIN -- region A is full. CP_CEL already left for
  MAP_INPUT and vm_tables is already relocated, so the next move is a real one: shrink the
  code, or take a ruling on the map"

=== AC-9/AC-11, p3b_arms_check.ps1 ===
p3b         16114 B  8548D2A5  OK      p3b_text    16899 B  D1D65E0A  OK
p3b_win3    16899 B  4A183DF1  OK      p3b_notick  16896 B  841BC1AD  OK
p3b_nomap   16896 B  2A298702  OK      p3b_fault   15945 B  4A31BB0D  OK
p3b_flat    15930 B  18B0E2FB  OK      p3b_comb    19336 B  B5A60E1D  OK
p3b_comb_count  19371 B  A3DD030C  OK
* all 9 arms byte-identical to the recorded baseline (SHA256)

=== AC-9, the arms check's own fault arm (-SelfTest) ===
p3b_text    16947 B  1DF47F60  MOVED -- expected 16899 B D1D65E0A
* 1 ARM(S) MOVED          <-- the intended RED

=== AC-12 ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared,
           EOL/guard/export-placement normalised)
[reg-discipline] scope: src/engine, src/harness  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
  src/engine/mmu_phase.s     6   $FFA3 $FFA4 $FFA5 $FFA6
CHECK OK: src/harness/vm_tables.s matches optable.py.
res     2212 B  3826E5C0  [on-disk]  OK
cel     1527 B  8B754B9C  [pinned]   OK
comp     967 B  39F5D105  [on-disk]  OK
* every non-p3b probe byte-identical
```

**25.2 bundled-artifact grep:** N/A — no artifact was bundled; no shipped byte moved.

**25.3 operator-runtime-smoke:** **N/A — not offered.** The nine shipped arms are byte-identical to
the build Jay watched at T-P0-141/142. See AC-10.

### 6 — Reactive deviations and route accounting

**§6 trigger 2 fired and the task stopped at §4B.** *"Nothing fits without opening the map ruling —
the map is overdue and this is not the task that takes it."* §4C (build), §4D (measure) and §4E (the
opportunistic licence) were **not** executed, and AC-4, AC-5, AC-6 and AC-10 are N/A in consequence.

★★ **§6 trigger 1 was evaluated and deliberately NOT taken.** It reads *"§4A shows cels change nearly
every cycle — report the rate and stop; the idea is dead."* The rate *does* show that (0.7% moving),
and the trigger's conclusion is false for this scene. ★★★ **Reporting the trigger as fired would have
been accurate about the number and wrong about the finding**, so §4A was extended with the reuse
simulation before any verdict was written. **That extension is the deviation and it is the task.**

**ROUTE ACCOUNTING.** I proposed no route beyond the dispatch. What this change contains: two guarded
test arms (`-DP3B_CELSTATS` with its two fault arms; `P3B_CELTRACE`, host-side), one new offline tool,
one new column on an existing one, and four comment blocks. What it does **not** contain: any cache,
any change to `vc_decode_row`, any change to the compositor, and any shipped byte.

★ **The two-destination row blit is described in this report and in `view_cel.s` and was NOT built.**
It is a genuine, priced, zero-storage capture of 25.1% of the decodes, and it is a different change
from the one this dispatch scoped.

### 7 — Uncertainty flags

1. ★★★ **The 20-cel working set is room 1's, not the game's.** Every hit rate above is measured on
   one room with four staged objects. A room with more animating objects needs more slots, and the
   corpus mean of 372 B/cel says 20 slots is ~7.4 KB in general, not 3.9 KB. **§4B's price is a
   lower bound.**
2. ★★ **LRU was simulated; it is also the wrong policy** for a sweep. A policy that holds a whole
   loop would hit at 20 slots too, and might hit at fewer by pinning rather than recycling. **No
   policy other than LRU was simulated**, so "1–14 slots buy nothing" is a statement about LRU.
3. ★★ **The ~15%-of-cycle figure is arithmetic**, composing this task's hit rate with P6.87's two
   shares. Labelled unverified per §8; only the rates and byte counts are measured here.
4. ★ **Host and guest adjacency differ slightly** (24.8% vs 25.0% standing; 0.0% vs 0.7% moving).
   The guest walks `p3_prev` by `p3_prevn`, the host walks `p3_spr` by `p3_nspr` at phase 9; they
   index the same sprites but not through the same table. **The two corroborate; neither is
   contradicted.** Not chased, because no conclusion rests on the difference.
5. ★ **`celtrace.txt` records cycles 0–8 as empty** — before the room jump nothing is staged. All
   figures use `--from-cycle 11`, the steady window.

### 8 — Follow-up candidates

1. ★★★★★ **The two-destination row blit** — 25.1% of decodes moving, 32.2% standing, **zero bytes**,
   no change to any decoded byte, `cel` gate's subject intact. **The highest value-per-risk item this
   task found.**
2. ★★★★★ **The map ruling, now with a number.** Its fifth symptom is a measured ~15%-of-cycle win
   that cannot be placed. The four before it were blocked diagnostics.
3. ★★★ **Re-measure the working set in a busier room** — §7(1).
4. ★★ **A hold-the-loop cache policy**, simulated before it is built — §7(2).
5. Carried, unchanged: the VIEW checksum gap; design spec §7.1's `0.039 s/cycle` (thirteen tasks
   flagged); the fill and the two core loops as rulings; option 3 and the sidecar variant; a scene
   separating P6.88's two guards; real-time pacing; typing cadence; the title page items;
   `checkPriority`/`checkCollision`; `MAP_PRI_BANDS`.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-23-adjacency-is-not-reuse.md`

### 11 — Commit
`4452c98` (pushed to origin/wip before this report)
