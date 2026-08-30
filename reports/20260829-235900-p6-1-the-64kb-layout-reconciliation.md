## Form B Report — P6.1 — the 64 KB layout reconciliation
**Class:** build. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-29 (HEAD `7f0912a`, wip). git status clean at receipt.

---

### §4 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===
7f0912a
wip
(git status clean)

=== siblings (§2T: cite P5.4 §0) ===
POP3_port                    104b197  wip  tracked-modified=0
karateka_coco3               29f8f0a  wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared,
           EOL/guard/export-placement normalised)
```

**Sibling baseline cited from P5.4 §AC-1** (§2T): POP `104b197`, karateka `29f8f0a`, both
unchanged; artifacts `loader.bin 56bf6740440c4e0a`, `probe.dmk ec6daccb0b78a9d5`,
`karateka.bin 9cd20dc537415e80`, `gfxmode3.bin d447c768bd5e6b80`,
`sprite_engine_sandbox.bin 543ad8f014bd84d6`. lwasm 4.24 unchanged.
★ **This task modifies no shared file and adds no sibling dependency**, so no sibling rebuild
was required; `hal_sync` OK in all three is the check that matters.

**The four gates** — all re-run this task, results in §AC-5.

★★★ **Every fixed address in the harness — ENUMERATED, and §1's table is incomplete.**

```
117 absolute address(es) across 20 harness file(s)
27 address(es) claimed by more than one file
```

> ★★★ **§1's table names THREE probes. The harness fixes addresses in TWENTY files.** The
> dispatch said the table was the Orchestrator's reading and might be incomplete [L-53]; it is,
> and the gap is 17 files. `harness/tools/addr_census.py` is new and is the enumeration.

The collisions that matter (the full 27 are in the tool's output):

| address | claimed by | real? |
|---|---|---|
| `$0080`–`$00AF` | ★ **all five probes**, different meanings each | **no** — probe handshake, never co-resident, does not ship |
| `$0700` | all five (`org` + hardware stack) | **no** — same meaning in each |
| `$2000` | `CP_VIEW`@cel · `RES_DIRS`@res_core · `org`@hal_build · `org`@mode2 | ★★ **YES** |
| `$3000` | `RES_ARENA`@res_core · `RES_DIRS`@vm_probe | ★★ **YES** |
| `$4000` | `CP_CEL`@cel_probe · `VM_VARS`@vm_state | ★★ **YES** |
| `$C000` | `RES_WINDOW`@res_core · `RES_ARENA_END`@vm_probe | ★★ **YES** |

★★★ **And one §1 does not mention at all: the two probes disagree about where the priority
plane lives.** `pic_probe` puts it at `$1700`–`$7FFF`; `comp_probe` puts `CP_PRI` at `$2900`
and `CP_VIS` at `$9200` — **inside pic_probe's framebuffer window.** They are two different
models of the planes, not two addresses for one model (§3.2 below).

---

### 1 — Summary

**The map exists.** All four subsystems are resident simultaneously, nothing overlaps, and the
overlap claim is **asserted at assembly time** rather than by a human reading a table — which is
the state this task existed to end.

★★★ **The arena is 24 KB (3 blocks), chosen from a measured eviction curve.** The knee is at
**20 KB** and it is a **thrash boundary**, not a shape: below it the cost scales with how long
you run (486 → 766 evictions as cycles/room goes 40 → 80); at 20 KB and above it is **constant**
at 63 regardless. Neither probe's figure was carried forward — 12 KB is deep in the thrashing
region, and 21 KB was a lucky guess two KB past the knee.

★★★★ **The binding constraint was a number nobody asked for.** The arena's *window* is two MMU
slots, not one, because **the largest single resource in the corpus is a 10,964-byte LOGIC** and
every one of seven v2 titles exceeds 8,192. A one-slot window could not have addressed the
largest LOGIC in **any** title. Nothing in the dispatch, the design spec or the four probes
mentions resource size.

★★ **One divergence from the harness, named with its cost:** the shipped priority plane is
**packed 4 bpp (13,440 B)**, because design §3.2 budgets 2 blocks = 16,384 B and the probes'
1-byte-per-pixel plane is 26,880 B and **does not fit**. Both representations are right for
their purpose (§3.3).

★★★ **All four gates re-run and pass** — renderer 45/45, resources 1,264/1,264, cels 6,782/6,782,
VM nine titles — **and the renderer gate is proven to still FAIL when it should**, localising to
exactly one picture at exactly the injected pixel (§7's L-62 point).

★ `src/engine/` exists; `reg_discipline.py` reports **5 accesses over 2 registers** with one
sanctioned owner. **Trigger 1 did not fire: everything fits.**

---

### 2 — Files modified

New:
- `src/engine/memmap.inc` — ★★★★ **the map.** Every region, owner, size; 14 assembly-time
  overlap assertions.
- `src/engine/mmu_phase.s` — §3.4's phase discipline as code; sanctioned owner of `$FFA5`/`$FFA6`.
- `harness/tools/addr_census.py` — the §4 enumeration.
- `harness/tools/arena_replay.py` — M-34's eviction curve.
- `harness/tools/run_gates.sh` — the four gate invocations, which existed nowhere on disk.

★ **No file in `src/harness/` was modified** — §5C: the harness stays and the gates keep
running. The map is built alongside, and nothing includes it yet.

---

### 3 — Reasoning

#### 3.1 AC-1's curve — and why the knee is believable

Three titles, room sweep 1–40 via the host-side room jump (var 0 + flag 5), 40 cycles/room:

| arena | KQ1 ev / refetch | KQ3 ev / refetch | SQ2 ev / refetch |
|---|---|---|---|
| 16 KB | 486 / 441 | 404 / 349 | 84 / 33 |
| 18 KB | 295 / 250 | 378 / 323 | 58 / 10 |
| **20 KB** | **63 / 18** | **142 / 87** | **51 / 8** |
| 24 KB | 46 / 3 | 92 / 38 | 44 / 3 |
| 32 KB | 36 / 1 | 68 / 18 | 37 / 2 |

★★★ **L-61, and it is what makes the knee a finding rather than a curve shape.** Varying
cycles-per-room:

| cycles/room | evictions @16 KB | @18 KB | **@20 KB** | **@24 KB** |
|---|---|---|---|---|
| 20 | 346 | 195 | **63** | **46** |
| 40 | 486 | 295 | **63** | **46** |
| 80 | 766 | 495 | **63** | **46** |

> ★★★ **Below the knee the cost grows with how long you run; above it the cost is constant.**
> That is the difference between thrashing and compulsory misses, and it is a much stronger
> statement than "the curve bends here." Seed made no difference (deterministic).

★ **KQ4 could not be replayed and the reason is internal to the dispatch.** AC-1 names KQ4;
§12 puts v3 out of scope, and KQ4 is v3 — `volread` rejects it by design decision, not by
defect. ★★ **SpaceQuest-2 (747,417 B) substituted** as the largest **v2** title. §8 does not
gate title choice, so I chose and am saying so.

#### 3.2 The four probes' models, and why two of them could never have coexisted

★★ **pic_probe and comp_probe are not two layouts, they are two MODELS:**

- **pic_probe** — visual = **the GIME framebuffer window** at `$8000`, written directly;
  priority = plain RAM at `$1700`. This is the shipping model: the hardware scans out the
  framebuffer regardless of what the CPU maps.
- **comp_probe** — **both** planes are plain linear RAM (`$2900`, `$9200`), one byte per pixel,
  because the gate byte-compares them against the oracle's arrays. `CP_VIS` at `$9200` sits
  **inside** pic_probe's framebuffer window and was never a framebuffer at all.

★ **The map resolves this by taking pic_probe's model and moving both planes out of the CPU
window into blocks**, reached a slice at a time. Neither probe changes.

#### 3.3 The priority plane — a real divergence, with its cost

Design §3.2 budgets **2 blocks** for priority = 16,384 B. At 1 B/px the plane is
**26,880 B — 64% over.** At 4 bpp it is **13,440 B**, fitting exactly, and AGI priority values
are 0–15 so four bits are lossless. ★★ **The two-block budget is only satisfiable by a packed
plane**, which is almost certainly what it was computed from.

★★★ **The probes' 1 B/px is right for a gate and wrong for the ship**, and pic_probe says why:
*"the SAME shape as the oracle's. No transform, no place for a transform error to hide"*
[`pic_probe.s:39-41`]. **The cost of packing is named and not yet measured:** the composite's
priority access becomes a nibble extract per pixel. T-P0-030 measured the priority test at
**2.7%** of composite cost against the transparency test's 70.9%, so it lands on the cheap path
— **but "lands on the cheap path" is a lead, not a measurement** (§8).

★ **Authority tier:** design spec §3.2 (Orchestrator arithmetic) against the probes' source.
Per CLAUDE.md §8 I am flagging that the reconciliation rests on §3.2's block figure being right.

#### 3.4 §2H's three checks

1. **A second mechanism for a different object class?** ★★ **Yes, and it changed the map.** The
   arena has a *size* (blocks) and a *window* (slots) and they are set by different evidence —
   the curve sets the first, the max resource sets the second. Treating "arena size" as one
   number is what would have produced a one-slot window.
2. **The calling routine.** `phase_draw`'s callers are the picture-draw and composite phases,
   which enter **once per phase**, not per object — that is the whole §3.4 constraint, and it is
   why only two slots move.
3. ★ **Grepped the reports before citing.** The "6,782 cels" and "1,264 resources" figures are
   from different gates than I first reached for (§AC-5) — both discrepancies were my invocation,
   and both are resolved there rather than left as apparent regressions.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: state-comparable]** ★★★ **PASS — curve delivered, §3.1.** Workload stated:
  room sweep 1–40 via the **host-side room jump** (var 0 = `VAR_CURRENT_ROOM`, flag 5 =
  `FLAG_NEW_ROOM_EXEC`), 40 cycles/room, seed 12345, **not a walkthrough**. KQ1 40/40 rooms
  reached, KQ3 40/40, SQ2 38/40. ★ **KQ4 replaced by SpaceQuest-2** — §3.1.

- **AC-2 [class: state-comparable]** ★★★★ **The arena is 24 KB = 3 blocks; its window is 16 KB
  at `$6000`–`$9FFF`.**
  - **Why 24 KB and not 20:** the knee is at 20 KB on all three titles, and 24 KB is the first
    **block-aligned** size past it (3 × 8,192). It buys KQ1 18→3 refetches and KQ3 87→38.
  - **Why not larger:** past 24 KB the return collapses — KQ1 gains 3→1 for another 8 KB.
  - **Why neither probe's figure:** ★★ **12 KB is inside the thrashing region** (KQ1 530
    evictions, and rising with runtime); **21 KB is 1 KB past the knee and not block-aligned.**
  - ★★ **The size can grow without the map moving** — the arena is blocks behind a fixed window.

- **AC-3 [class: byte-comparable]** ★★★★ **PASS — one map, no overlaps, ASSERTED.**

  | region | address | size | owner |
  |---|---|---|---|
  | HAL direct page | `$0000`–`$001F` | 32 | HAL |
  | interpreter status | `$0020`–`$00FF` | 224 | engine |
  | picture seed stack | `$0100`–`$04FF` | 1,024 | picture |
  | hardware stack (`S`=`$0800`, down) | `$0500`–`$07FF` | 768 | system |
  | VM state (vars/flags/ctrl/objrooms/obj) | `$0800`–`$0FFF` | 2,048 | VM |
  | DIR tables (4 × 1 KB) | `$1000`–`$1FFF` | 4,096 | resources |
  | engine code | `$2000`–`$4FFF` | 12,288 | engine |
  | ★ **RESERVED — parser + sound** | `$5000`–`$5FFF` | 4,096 | *not built* |
  | **arena window** (slots 3–4) | `$6000`–`$9FFF` | 16,384 | resources |
  | **priority slice** (slot 5, draw only) | `$A000`–`$BFFF` | 8,192 | picture/composite |
  | **phase window** (slot 6) | `$C000`–`$DFFF` | 8,192 | vol *or* framebuffer |
  | resident tables (bands 168 · palette 16 · font 2,048) | `$E000`–`$FEFF` | 7,936 | engine |
  | I/O page | `$FF00`–`$FFFF` | 256 | hardware |

  ★★★ **14 assembly-time assertions**, and **proven able to fail**: shrinking the arena window to
  one slot produces
  `ERROR : User Specified: "arena window smaller than the largest corpus resource (10,964 B)"`.

- **AC-4 [class: state-comparable]** ★★★ **PASS — the phases are disjoint, and only two slots
  move.**

  | slot | window | VM phase | picture-draw / composite |
  |---|---|---|---|
  | 0–4, 7 | `$0000`–`$9FFF`, `$E000`+ | resident | **unchanged** |
  | **5** | `$A000`–`$BFFF` | *nothing mapped* | **priority slice** |
  | **6** | `$C000`–`$DFFF` | **volume window** | **framebuffer slice** |

  ★★ **Slot 6's two uses never collide** because a resource fetch happens in the VM phase and
  never while drawing — that is §3.4's disjointness, and it is the one place in the map where the
  property is load-bearing rather than incidental. ★ **Two remaps per phase transition, not per
  scanline**: at 160 B/row an 8 KB slice covers 51 rows, so a full-screen pass costs 3 more.
  ★ Measured corroboration: the resource gate reports **0.22 MMU remaps per fetch**.

- **AC-5 [class: byte-comparable]** ★★★★ **PASS — all four gates, against the reconciled layout.**

  | gate | result |
  |---|---|
  | renderer | **45 PASS, 0 FAIL** (of 45), 3 games, both planes |
  | resources | **1,264 byte-identical** across 10 (title, volume) sweeps, all clean |
  | cels | **6,782 / 6,782**, 995 mirrored, 0 mismatch, 5 titles |
  | VM | **nine titles all PASS**, 0 divergent of 600 cycles × 288 bytes |

  ★★★ **L-62 discharged on the renderer gate — it still fails when it should, and it
  LOCALISES:** the `-DPIC_FAULT` build fails **exactly one** picture, `Kingquest2-073`, at
  `DIFFERS 1 px, first (37,42)` — the injected offset — **and the other 44 still pass.**
  ★★ **Two apparent regressions were my invocation, not the gates:** 8,003 cels (I passed
  PoliceQuest1 where the recorded set uses larry1 — the 1,221 difference is exactly those two
  titles), and 74 fetches (the default stage; the 1,264 figure is `res_run.ps1`'s full sweep).
  Both reproduce the recorded numbers exactly once invoked correctly.

- **AC-6 [class: byte-comparable]** ★★ **PASS — `src/engine/` exists and the count is non-zero,
  which is correct.**
  ```
  [reg-discipline] 5 register access(es) in 1 file(s) over 2 register(s).
    src/engine/mmu_phase.s   5   $FFA5 $FFA6
  ```
  ★★★ **One sanctioned owner per register** (§2N.2): `mmu_phase.s` owns `$FFA5` and `$FFA6` and
  nothing else touches them. ★ Both are reached through `equ` aliases (`MMU_SLOT5`/`MMU_SLOT6`),
  so the four-part rule's alias resolution is doing the work a literal grep would miss.

- **AC-7 [class: state-comparable]** ★ **PASS.** 512 KB = 64 blocks; §3.2's 56 free.

  | allocation | blocks |
  |---|---|
  | framebuffer (visual, 26,880 B) | 4 |
  | priority (packed, 13,440 B) | 2 |
  | **arena (24,576 B)** | **3** |
  | resident CPU-window content | 4 |
  | volume staging buffer | 1 |
  | **total** | **14 of 56** |

  ★★ **42 blocks (344,064 B) remain** for the parser, sound and save-under. Save-under is
  2 × max cel (4,784 B) = 9,568 B = **2 blocks**, leaving 40. ★ Plus the 4 KB CPU-window
  reservation at `$5000` so neither has to move the map.

- **AC-8 [class: state-comparable]** ★★ **PASS — each probe's exclusive assumption, and its
  resolution.**

  | probe | assumed exclusive | resolved by |
  |---|---|---|
  | `pic_probe` | `$1700`–`$7FFF` priority (1 B/px); `$8000`+ framebuffer window; `S`=`$0800` | plane → 2 blocks packed via slot 5; framebuffer → slices via slot 6; ★ **`S` and the seed stack keep their addresses exactly** |
  | `res_probe` | `$3000`–`$6000` arena (12 KB); `$2000` DIRs; `$C000` vol window | arena → blocks behind `$6000`–`$9FFF`; DIRs → `$1000`; ★ **vol window keeps `$C000`** |
  | `vm_probe` | `$6B00`–`$C000` arena (21 KB); `$3000` DIRs; `$6500` trace; `$4000` VM state | arena → as above; DIRs → `$1000`; VM state → `$0800`; ★ trace is harness-only and does not ship |
  | `cel_probe` | `$2000` view, `$4000` cel | both are staging inside the arena window |
  | `comp_probe` | `$2900` pri, `$9200` vis | both → blocks; `CP_VIS` was never the framebuffer |
  | **all five** | `$0080`–`$00AF` handshake, `$0700` stack/org | ★★ **does not ship** — but noted as a live seam: the map's status block at `$0020`–`$00FF` overlaps it, so a probe must never include `memmap.inc` while the harness stands |

- **AC-9 [class: suite]** ★ **Three rows** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
117 absolute address(es) across 20 harness file(s)
27 address(es) claimed by more than one file
```

```
=== KQ1   arena   evictions   refetches   fetches  oversized
      16 KB         486         441       492          0
      18 KB         295         250       301          0
      20 KB          63          18        69          0
      24 KB          46           3        54          0
  ★ refetches bottom out at 1 and first reach it at 32 KB
```

```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
```

```
Kingquest2-073   3   844   DIFFERS 1 px, first (37,42)   identical ae94489a381e63d5   ★ FAIL
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)
★ --expect-fail: a FAIL here is the expected result.
```

```
=== TOTAL ===
byte-identical resources: 1264 across 10 (title, volume) sweeps
all sweeps clean
```

```
TOTAL             6782    6782    6782       0        0      995
cels byte-identical to the oracle: 6782 / 6782 queued (100.00%)
```

```
=== AC-2 SUMMARY ===
Kingquest1 PASS · Kingquest2 PASS · Kingquest3 PASS · PoliceQuest1 PASS · SpaceQuest-1 PASS
SpaceQuest-2 PASS · larry1 PASS · MixedUpMotherGoose PASS · BlackCauldron PASS
```

```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] 5 register access(es) in 1 file(s) over 2 register(s).
  file                                     count  registers
  src/engine/mmu_phase.s                       5  $FFA5 $FFA6
```

```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact. `src/engine/` assembles but is not
yet linked into any image; the shipped artifacts are unchanged from P5.4.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen this task. All four gates
ran headless; the renderer gate's planes are byte-compared, not displayed.

---

### 6 — Reactive deviations and route accounting

1. ★★ **KQ4 → SpaceQuest-2** (§3.1). AC-1 names KQ4; §12 excludes v3; KQ4 is v3. §8 does not
   gate title choice.
2. ★ **Three tools written that the dispatch did not request** — `addr_census.py` (§4 requires
   enumeration and no tool existed), `arena_replay.py` (AC-1), `run_gates.sh` (the four gate
   invocations were on disk nowhere, the third instance of that gap in two tasks).
3. ★ **`addr_census.py` was corrected after its first run** — it counted flag bitmasks and sizes
   as addresses (§10's third row). The corrected figures are the ones above.

**ROUTE ACCOUNTING.** I proposed no route beyond the AC list. ★★ **What I did NOT do:** I did
not measure the 4 bpp packing cost (§3.3 — named, estimated from T-P0-030's 2.7%, **not
measured**); did not build the parser or sound (reserved only); did not modify any probe; did
not fold the map into the design spec (§11 — the Orchestrator's job); did not run the
compositing gate (unchanged since P5.4 and not in AC-5's four).

---

### 7 — Uncertainty flags

1. ★★★ **The 4 bpp priority packing is decided but not measured.** Its cost is a nibble extract
   per pixel on a path T-P0-030 measured at 2.7% — **my inference, not a measurement** (§8).
2. ★★★ **The reconciliation rests on design §3.2's "2 blocks priority" being right.** If that
   figure is itself Orchestrator arithmetic, the packing decision follows from it and should be
   re-checked. Per CLAUDE.md §8, flagging rather than assuming.
3. ★★ **The engine code region is 12 KB against `vm_probe.bin`'s measured 9,089 B** — but that
   is the VM plus HAL only. Picture, cel, composite and resources are not yet in one image, so
   **12 KB is an allocation to be checked, not a measurement.**
4. ★★ **The parser/sound 4 KB reservation is a residual, not a requirement** — it is what is
   left in slot 2. It must be checked against the parser and sound when they exist.
5. ★ **`$0020`–`$00FF` overlaps the probes' `$0080`–`$00AF` handshake.** Benign today (the
   harness never includes `memmap.inc`) and a live seam if that ever changes.
6. ★ **The candidate push failed on auth** (§10) — rows committed locally only. Same as P5.4.

---

### 8 — Follow-up candidates

1. ★★★ **Measure the 4 bpp priority pack/unpack cost** on the target — the one number this task
   asserted rather than measured.
2. ★★★ **Build one linked image with all four subsystems** and check the 12 KB code region
   against reality. The map is unproven until something occupies it.
3. ★★ **`addr_census.py` as a standing pre-check** — it found a 17-file gap once and the harness
   keeps growing.
4. ★★ **AD-77 (the vacuous gameplay gate) is still open** and explicitly out of scope here.
5. ★ **Re-run AC-1 on a walkthrough rather than a room sweep** — the sweep exercises loading, not
   plot, and a real playthrough may have a different locality profile.
6. ★ **`res_run.ps1` and `vm_run.ps1` default to 3 titles**; the 9-title VM run needs `VM_TITLES`
   set. Worth a default or a documented line — it is how I first under-ran two gates.

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

Three rows in `seeds/AGI/live/`, committed locally. ★ **Push failed** — `remote: Invalid username
or token` — fire-and-forget per §2C, does not gate. No credential copied anywhere.

- `2026-08-29-the-constraint-that-decides-the-design-is-often-a-number-nobody-asked-for.md`
- `2026-08-29-a-test-representation-and-a-shipped-representation-can-both-be-right.md`
- `2026-08-29-a-syntactic-census-counts-things-that-share-a-shape-not-a-meaning.md`

---

### 11 — Commit

`<filled at commit>` (pushed to origin/wip before this report)
