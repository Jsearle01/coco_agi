## Form B Report — P3b.5 — the LOGIC cache, and the remaining 55.2%
**Class:** build. wip.
★★★★ **AC-2 PASSES on nine titles. KQ1 6.2 → 14.2 cyc/s, KQ3 5.3 → 9.4. No trigger fired.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `eed895c`, wip). git status clean at receipt.

---

### §4 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===        eed895c  wip   (clean)

=== siblings (§2T: cite P3b.4 §0) ===
POP3_port          104b197 wip  tracked-modified=0
karateka_coco3     29f8f0a wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)

=== reg_discipline ===
  src/engine/mmu_phase.s                       5  $FFA5 $FFA6
```

**The five gates:** renderer **45 PASS / 0 FAIL (packed)**, resources **1,264** across 10 sweeps,
VM **nine titles PASS**, cels **6,782/6,782**, compositing **20/20 identical**.

★★★★ **`cycle.py`'s `load_logic` — the cache's specification, exhaustively:**

```
cycle.py:94-95    self._logic_cache = {} / self._view_cache = {}      created empty
cycle.py:156-162  fill on miss, return on hit                          load_logic
cycle.py:173-179  same                                                 load_view
```
★★★ **THAT IS EVERY REFERENCE.** There is no `del`, no `.pop()`, no `.clear()` anywhere in
agivm. **The reference NEVER invalidates.**
★★ **`new_room` (cycle.py:267-270) clears `loaded_logics` / `loaded_views` / `loaded_pics` /
`loaded_sounds` — the residency SETS, a different concept**: AGI's *declared* residency, which
the game manipulates via `load.view` / `discard.view`. ★ Note `discard.view` removes from
`loaded_views` and **not** from `_view_cache`, which confirms the split.
★ **Nothing mutates cached bytecode** — no `bytecode[...]` write, no `.bytecode =` assignment.

**The ablation build:** still off by default; `vm_probe.bin` byte-identical without the flags.

**No contradiction found. Proceeded.**

---

### 1 — Summary

★★★★ **The cache is real and the gate is green on nine titles, empty exclusion set.** On-target
hit rates **99.0% (KQ1, 598 hits / 6 misses)** and **98.5% (KQ3)**.

★★★★ **AC-5 — and it beats the ablation:**

| | baseline | ablation [AD-86] | **real cache** | corpus asks |
|---|---|---|---|---|
| KQ1 | 6.2 cyc/s | 9.9 | ★★★ **14.2** | 10 |
| KQ3 | 5.3 cyc/s | — | ★★★ **9.4** | 10 |

★★★ **It beats the ablation because the ablation was keyed differently, and I measured that
before building.** AD-86 was depth-keyed; simulating both keyings against the corpus:
**KQ1 depth-keyed 33.0% hit vs index-keyed 99.7%.** KQ1 alternates two logics at one depth, so
depth keying collapses exactly there. ★★★★ **AD-86's 37.5% was a floor measured on the worst
case for its own keying — and AD-83's original 57.9% coefficient, which T-P0-035 "corrected"
downward, was nearer the truth (measured now at 56.2%).**

★★★★ **AC-3 — the invalidation policy is a MEMORY/TIME choice, not a correctness one**, proven
in the reference: clear-on-new_room vs never-clear is byte-identical, 300 cycles, three titles.

> ★★★★ **But that result covers the POLICY and NOT the MECHANISM, and reading it as covering both
> halted all nine titles at cycle 0** (§3.3). **`new.room` runs INSIDE a logic**, so resetting the
> arena there allocated over the logic still executing. The reference could not have caught it:
> clearing a Python dict leaves the held object intact; **in the port the bytes ARE the storage.**

★★ **A second implementation error, and its symptom named it** (§3.4): a permanent allocation
made above a transient VIEW frame is reclaimed when that frame pops. **KQ1 and PoliceQuest1
passed and the other seven failed — and the passing pair copy 24 and 394 VIEW B/cycle against
the failing set's 4,273–7,510.**

★★★ **AC-7 — unattributed falls from 55.2% to 36.6%.**

★★ **AC-6: the cache fits, but it cost the parser/sound reservation a second time** (§3.6) —
**4,096 → 3,840 → 3,584 across three tasks, none of them about the parser.**

---

### 2 — Files modified

- `src/harness/res_core.s` — the cache: `res_cache_find` / `res_cache_stash` /
  `res_cache_reset` / `res_cache_flush`, the two-allocator split, the hook in `res_open`.
- `src/harness/vm_run.s` — `vm_new_room` raises the pending flag.
- `src/harness/vm_cycle.s` — `vm_interpret_cycle` performs the deferred flush.
- `src/engine/memmap.inc` — code/reserved boundary `$5100 → $5200` (§3.6).
- `harness/tools/vm_sweep.lua` — reads `res_chits` / `res_cmiss` from the timed run.
- `harness/tools/copy_census.py` — the invalidation-policy experiment and the keying simulation.

★★ `pic_probe.bin` verified byte-identical; the renderer, resource and compositing gates are
unaffected by construction and were re-run anyway.

---

### 3 — Reasoning

#### 3.1 The keying, measured before building

| title | depth-keyed hit | index-keyed hit | misses |
|---|---|---|---|
| **Kingquest1** | ★★★ **33.0%** | **99.7%** | 605 vs 3 |
| Kingquest3 | 99.0% | 99.3% | 6 vs 4 |
| SpaceQuest-1 | 98.7% | 99.3% | 8 vs 4 |

★★★ **KQ1 is the outlier and AD-86 was measured on KQ1.** Its logic102 and logic83 alternate at
one depth, so a depth-keyed memo misses every time. Index keying is what the reference does and
what the corpus wants.

★★ **One correction to my own instrument:** the first keying simulation reported depth-keyed
**0.0%** everywhere, because I incremented the depth counter around `load_logic` — which does not
nest. **`run_logic` is the routine that nests**, and it is the port's `res_open`/`res_close`
pair. The wrong hook would have contradicted AD-86's measured 37.5% and I would have had two
irreconcilable numbers.

#### 3.2 AC-3 — the policy, and its exact scope

★★★ The reference never invalidates (§4). Two experiments, both entirely in the reference:

| experiment | result |
|---|---|
| re-load every call vs cached [AD-87] | byte-identical, 300 cycles, six titles |
| **clear on new_room vs never-clear** | ★★★ **byte-identical, 300 cycles, three titles** |

★★★★ **So "never" is an OPTIMUM, not a requirement**, and the port may invalidate. It must:
the reference's cache is an unbounded Python dict, ours is a 24 KB arena, and T-P0-031 measured
KQ1's 40-room working set at 85,852 B. **One room's set is 13,669 B and captures the whole
99.7%**, because the redundancy is the same few logics recurring *within* a room.

★★ **The port's policy, stated: invalidate on `new.room` and nowhere else.** Justified above,
not by analogy.

#### 3.3 ★★★★ Where reading that result too broadly went wrong

The first implementation reset the arena inside `vm_new_room` and **halted all nine titles at
cycle 0** — `opcode $F5 in logic 102`, `reserr=5` (RES_E_FULL).

★★★ **`new.room` is a COMMAND. It executes INSIDE a logic**, whose bytes are live in the arena.
Resetting `res_top` there let the next fetch allocate straight over the running logic.

★★★★ **And the reference experiment could not have caught it.** Clearing `_logic_cache` does not
disturb the `lg` object the interpreter already holds — Python's reference counting keeps it
alive. **In the port the bytes ARE the storage.** The experiment validated the *policy* and said
nothing about the *mechanism*; I read it as covering both.

★ **The fix:** `new.room` raises a flag; the flush happens at the top of the next
`vm_interpret_cycle`, where `res_depth` is 0 and nothing executes out of the arena.

#### 3.4 ★★ The second error, and the symptom that named it

With the deferred flush, KQ1 and PoliceQuest1 passed and **seven titles still failed.**

★★★ **The split was VIEW traffic, exactly**: the passing pair copy **24 and 394 VIEW B/cycle**;
every failing title copies **4,273–7,510** [AD-87's table]. A VIEW opens a transient frame at
`res_top`; a LOGIC miss inside it allocated *above* the VIEW and pinned `res_top` there; the VIEW
then closed and popped `res_top` back **below** the cached logic, whose memory was now above the
stack pointer and was overwritten by the next transient allocation.

★★ **The fix is two allocators that cannot interleave**: the stack grows **up** from
`RES_ARENA`, the cache grows **down** from `RES_ARENA_END`, and `res_ceil` is now `res_ccur` so
the stack cannot fetch into cached bytes. ★ The fetch still lands on the stack (that is where the
length is discovered) and is relocated down — **one extra copy per MISS**, 3–4 per room, against
the 3 per *cycle* this removes.

#### 3.5 §2H's three checks

1. **A second mechanism for a different object class?** ★★★ **Yes, and it is §3.4's whole
   story.** VIEWs are the other `res_open` client, and the cache's first two designs were both
   broken *by* VIEWs rather than by LOGICs. **VIEW caching itself remains undone** and is AC-9's
   rank 2.
2. **The calling routine.** `vm_call_body`'s `bind / run / close` is the caller, and `new.room`'s
   caller is a logic — which is the whole of §3.3.
3. ★ **Grepped before citing.** AD-86's 37.5% and AD-83's 57.9% were both re-read before being
   re-corrected (§3.1); the reversal is stated rather than quietly applied.

#### 3.6 The reservation, spent a second time

The cache added **352 bytes** of code and overran the map's code region by **107**. Boundary
`$5100 → $5200`: code 12,800 (149 spare), **parser/sound reservation 3,840 → 3,584.**

★★★★ **The trend is the finding, not the byte count:**

| task | cause | reservation |
|---|---|---|
| P6.1 | reserved | 4,096 |
| T-P0-034 | packed span walk, over by 11 | 3,840 |
| **T-P0-036** | **LOGIC cache, over by 107** | **3,584** |

★★ Each step was small, measured, forced by a real overrun, and taken by a task **that was not
about the parser**. The map's only assertion is that the regions do not overlap, which stays true
as the boundary slides. **12.5% gone with the parser not yet existing to argue for itself.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★ **PASS.** §4 verbatim; all five gates re-run; §2T cited
  from P3b.4 §0.

- **AC-2 [class: state-comparable]** ★★★★ **PASS — nine titles, 600 cycles × 288 bytes, exclusion
  set EMPTY, 0 divergent, cache live.**

- **AC-3 [class: state-comparable]** ★★★★ **PASS — policy stated and justified against
  `cycle.py`.**

  | point | reference | port | why |
  |---|---|---|---|
  | fill | on miss | on miss | same |
  | `new.room` | **does not invalidate** | ★★ **invalidates** | bounded 24 KB arena; measured free (§3.2) |
  | `discard.view` | does not invalidate | does not invalidate | same |
  | anywhere else | never | never | — |

  ★★★ **The one divergence is named with its reason and its evidence**, and §3.3 records that the
  evidence covers the policy only.

- **AC-4 [class: byte-comparable]** ★★★ **PASS — re-proven on THIS build.** `-DVM_FAULT`:
  **KQ2 188 divergent of 600, KQ3 73 of 600, both FAIL as required.**
  ★★ **KQ1 passes with the fault injected — and that immunity is PRE-EXISTING, not introduced
  here:** the same fault on the **pre-cache** binary also gives 0 of 600 on KQ1. ★ Reported
  because L-62 asks whether detectability survived the build change: it did, and KQ1's blind spot
  predates it (AD-77's shape, already open).

- **AC-5 [class: state-comparable]** ★★★★ **PASS. Clock 1.7898 MHz, 200 free-run cycles,
  opcount identical to baseline (184 KQ1, 361 KQ3).**

  | | baseline | cached | saving | rate |
  |---|---|---|---|---|
  | KQ1 | 288,575 cy / 161.236 ms | **126,307 / 70.572** | **162,268 = 56.2%** | **6.2 → 14.2 cyc/s** |
  | KQ3 | 339,693 cy / 189.797 ms | **191,096 / 106.771** | **148,597 = 43.7%** | **5.3 → 9.4 cyc/s** |

  ★★★ **Hit rates read off the target, from the run that was timed:** KQ1 **598 hits / 6 misses =
  99.0%**; KQ3 **399 / 6 = 98.5%**. ★★ **It exceeds the ablation (9.9) because the ablation was
  depth-keyed** — §3.1, and that was predicted before building rather than explained after.
  ★ **KQ1 beats the corpus's 10 cyc/s; KQ3 is 0.6 short.**

- **AC-6 [class: state-comparable]** ★★★ **PASS — it fits, and it cost a reservation.**
  - **Table 40 B** (8 entries × key + address + length) **+ 8 B state = 48 bytes.**
  - **Code +352 B**; the packed P3b image is **12,651 B**.
  - **Arena: 13,669 cached bytes (KQ1) inside 21,760 (harness) / 24,576 (shipped).** Fits with
    room; the cache **fails closed** — table full or no space leaves the resource uncached and it
    simply re-copies next time.
  - **Draw phase 60,058 against 65,280 — spare 5,222** (was 5,574).
  - ★★★★ **Reservation 3,840 → 3,584** — §3.6.

- **AC-7 [class: state-comparable]** ★★★ **PASS — and AD-86's 37.5% is corrected UPWARD to
  56.2%.** KQ1, of 288,575 cycles:

  | component | cycles | share |
  |---|---|---|
  | **resource copy** (removed by the cache) | **162,268** | ★★★ **56.2%** |
  | harness + pacing floor | 16,643 | 5.77% |
  | VM instrumentation | 4,160 | 1.44% |
  | **UNATTRIBUTED** | **105,504** | ★★ **36.6%** |

  ★★★★ **AD-83's coefficient said 57.9%; T-P0-035's depth-keyed ablation "corrected" it to
  37.5%; the real cache measures 56.2%. The coefficient was closer, and my correction of it was
  the less accurate of the two** — because the ablation's mechanism differed from the fix's.
  ★★ **Unattributed falls 55.2% → 36.6%, and is reported rather than distributed** (third task
  running).

- **AC-8 [class: state-comparable]** ★★ **Nothing new is instrument.** Harness + pacing 5.77%,
  VM instrumentation 1.44% — **7.2% is scaffolding** and disappears in the shipped interpreter.
  ★ The keying simulation and the policy experiment both run in the reference and add no
  target-side instrument; the cache's own counters are 4 bytes and 6 instructions per open.

- **AC-9 [class: state-comparable]** ★ **Ranked by measured share, not acted on:**

  | # | candidate | measured | note |
  |---|---|---|---|
  | 1 | **the unattributed 36.6%** | ablated residue | ★★★ still the largest unknown |
  | 2 | **VIEW caching** | up to **7,510 B/cycle** (KQ2) | ★★★ the second `res_open` client; it broke this cache twice (§3.4) and is still uncached |
  | 3 | harness + pacing | 5.77% | ★ not the engine |
  | 4 | VM instrumentation | 1.44% | `-DVM_NOCOUNT` exists |

- **AC-10 [class: suite]** ★ **Two rows** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

```
=== AC-2 SUMMARY ===   (cache live)
Kingquest1 PASS · Kingquest2 PASS · Kingquest3 PASS · PoliceQuest1 PASS · SpaceQuest-1 PASS
SpaceQuest-2 PASS · larry1 PASS · MixedUpMotherGoose PASS · BlackCauldron PASS
compared : 600 cycles x 288 bytes, exclusion set EMPTY
```

```
★ cache keying, simulated:
  Kingquest1   depth-keyed  33.0% hit   index-keyed  99.7% hit   (misses 605 vs 3)
  Kingquest3   depth-keyed  99.0% hit   index-keyed  99.3% hit   (misses   6 vs 4)
  SpaceQuest-1 depth-keyed  98.7% hit   index-keyed  99.3% hit   (misses   8 vs 4)

★★ AC-3b -- reference NEVER-INVALIDATES vs reference CLEARS-ON-new_room:
  ★★★★ IDENTICAL. Invalidation is a MEMORY/TIME choice, not a correctness one.
```

```
=== Kingquest1 ===
    cache: hits 598  misses 6  hit-rate 99.0%
    70.572 ms/cycle   126307 CPU cycles/VM cycle @ 1.7898 MHz   14.2 VM cycles/s
    opcount=184  (0.9 commands/cycle)
=== Kingquest3 ===
    cache: hits 399  misses 6  hit-rate 98.5%
    106.771 ms/cycle   191096 CPU cycles/VM cycle @ 1.7898 MHz    9.4 VM cycles/s
    opcount=361  (1.8 commands/cycle)
```

```
FAULT INJECTED (-DVM_FAULT) -- this build is EXPECTED to fail AC-2
Kingquest1   PASS   (pre-existing: the PRE-CACHE build also gives 0 of 600)
Kingquest2   FAIL   divergent cycles : 188 of 600
Kingquest3   FAIL   divergent cycles :  73 of 600
```

```
AC-6: packed P3b code 12651 B -> draw phase 60,058 vs 65,280, spare 5,222
per-picture: 45 PASS, 0 FAIL (of 45)      byte-identical resources: 1264, all sweeps clean
cels 6782 / 6782                           ★ 20 frames: 20 identical, 0 divergent
★ pic_probe.bin unchanged
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; `vm_probe.bin` is the changed image
and is a harness probe, not a shipped one.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen; headless gates and
free-run timing only.

---

### 6 — Reactive deviations and route accounting

1. ★★ **Moved the map's code/reserved boundary** a second time (§3.6). Placement within the
   budget is not a consultation item (§8), but the cumulative trend is surfaced.
2. ★★ **Two implementation designs were built and discarded** before the working one — the
   immediate reset (§3.3) and the pinned-`res_top` allocation (§3.4). Both are recorded because
   the second was diagnosed from a pattern in *which titles failed*, which is reusable.
3. ★ **Added the cache's hit/miss readback** to `vm_sweep.lua` so AC-5's claim rests on the hit
   rate and not only on the timing.
4. ★ **Corrected my own keying simulation** (§3.1) before trusting it.

**ROUTE ACCOUNTING.** ★★ **What I did NOT do:** did not cache VIEWs (AC-9 rank 2, and it is the
thing that broke this cache twice); did not attribute the 36.6%; did not touch the cycle-rate
decision (§11 — Jay's); did not remove the ablation flags, which remain guarded and off; did not
change the parser, sound, storage, renderer or compositor.

---

### 7 — Uncertainty flags

1. ★★★★ **36.6% of the VM cycle is still unattributed** — down from 55.2%, still the largest
   unknown, and AC-9 ranks it first.
2. ★★★ **KQ3 reaches 9.4 cyc/s against the corpus's 10**, and that is the VM ALONE. Compositing,
   motion and text are not in it. ★★ **§7 trigger 5's condition — the budget missing 10 cyc/s
   once those are added — is not yet testable**, because the integrated loop still does not run.
   **It is the open question this task did not close.**
3. ★★★ **VIEW resources are still re-copied every invocation**, up to 7,510 B/cycle. The cache
   covers LOGIC only, deliberately, so AC-5's number is attributable to one change [L-54].
4. ★★ **`RES_CACHE_MAX` is 8 against a measured live set of 3–4.** A room needing more silently
   degrades to re-copying — correct, but it would show as a performance cliff rather than an
   error. Not exercised by the corpus.
5. ★★ **The cache is keyed on LOGIC index alone**, not (type, index), because only LOGIC uses it.
   Extending it to VIEWs requires the key to carry the type.
6. ★ **Pool push failed on auth — seventh consecutive task.** Eighteen rows local only.

---

### 8 — Follow-up candidates

1. ★★★★ **Attribute the 36.6%.** Candidate ablations: opcode dispatch, `vm_update_objs` / motion,
   `timer_update`.
2. ★★★★ **VIEW caching** — 7,510 B/cycle on KQ2, and the two-allocator split now exists to
   support it.
3. ★★★ **Run the integrated P3b loop** and settle §7 trigger 5's question with compositing and
   motion live.
4. ★★ **Give the parser/sound reservation a stated floor and an owner** before it is reduced a
   third time (§3.6).
5. ★ **AD-77** — KQ1's fault immunity is now evidenced as pre-existing; the gate-corpus fix
   remains a separate task.

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

Two rows in `seeds/AGI/live/`, committed locally. ★ **Push failed** — `Authentication failed`,
**seventh task running** — fire-and-forget per §2C, does not gate.

- `2026-08-30-a-policy-proven-safe-in-the-reference-says-nothing-about-the-mechanism-in-the-port.md`
- `2026-08-30-a-reservation-nobody-owns-is-spent-one-small-justified-step-at-a-time.md`

---

### 11 — Commit

`<filled at commit>` (pushed to origin/wip before this report)
