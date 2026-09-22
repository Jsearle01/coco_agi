## Form B Report — P6.82 — One owner, one record: `$FFA6`
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `df88846`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task.

### 1 — Summary
★★★★★ **§4A's premise holds and the ruling's cost was an artifact.** `memmap.inc`'s plane-reach
assertion was firing on builds that address no plane, so scoping it to the ones that do let
`res_probe` and `vm_probe` link `mmu_phase.s` **without either gate's memory model moving one
byte**. `mmu_phase.s` now holds one record per contended slot and owns the only instruction in the
tree that writes each register; storage maps through `phase_vol`; `plane_vis`/`plane_pri` test the
record. **`reg_discipline`: 18 accesses in 2 files → 6 in 1.** `plane_reset` is retired along with
three separate invalidations that existed only to tell the other owner, and **all nine arms
shrink**. `res` 1,264/1,264 and `vm` 9/9 run fresh; Jay's eye gate: behaviour identical, speed
unchanged.

★★★★ **Two things this task did not expect and both are reported as findings**: §4B's design needed
a correction (`plane_pri` is slot 5, not slot 6, so one `$FFA6` record cannot serve it), and the
`res` gate's symbol map turned out to have **no producer** — a hand-made file dated 2026-08-28 that
made the gate correct only while `res_probe`'s layout never moved.

### 2 — Files modified
- `src/engine/mmu_phase.s` — `ph_cur5`/`ph_cur6`; `phase_slot5`/`phase_slot6` as the only writers;
  all ten entry points routed through them.
- `src/engine/memmap.inc` — the plane-reach assertion scoped by `PLANE_ABSENT`, plus the
  contradiction check.
- `src/harness/composite.s`, `pic_core.s`, `plane_win.s` — each refuses `PLANE_ABSENT`.
- `src/harness/res_core.s` — `res_map_block` calls `phase_vol`; `res_curblk equ ph_cur6`;
  `RES_MMU_SLOT` removed.
- `src/harness/plane_win.s` — the record replaces the slice caches under `PLANE_WIN_MMU`;
  `plane_reset` retired; `-DPLANE_FAULT_PRIVCACHE` added; the base constants initialised.
- `src/harness/res_probe.s`, `vm_probe.s` — declare `PLANE_ABSENT`, include `mmu_phase.s`.
- `src/harness/p3b_probe.s`, `pic_probe.s`, `pic_fill.s`, `vm_text_ops.s` — invalidations removed.
- `harness/tools/res_run.ps1` — **the symbol map gains a producer** (§6).
- `harness/tools/p3b_show.ps1` — `-NoPlaneReset` → `-PrivCache`.
- `harness/tools/p3b_arms_check.ps1`, `probe_identity_check.ps1` — re-baselined.

Explicit-path staging only.

### 3 — Reasoning

**Authority tier.** Jay for the eye gate; everything else is measurement of this port's own
registers. No ScummVM or Specs claim is involved — this is register ownership, not AGI behaviour —
so §2H's three checks have no reference mechanism to apply to.

#### §3(2) — every writer of `$FFA6`, and every reader of the caches ★★★★★

**Before** (`reg_discipline`, verbatim, measured at `df88846`):
```
18 register access(es) in 2 file(s) over 4 register(s).
  src/engine/mmu_phase.s   17  $FFA3 $FFA4 $FFA5 $FFA6
  src/harness/res_core.s    1  $FFA6
```

| reader / writer | of what | disposition |
|---|---|---|
| `res_map_block` | wrote `$FFA6`, cached in `res_curblk` | ★ calls `phase_vol`; `res_curblk` **is** `ph_cur6` |
| `plane_vis` → `pl_map_vis` → `phase_draw_fb` | cached slice in `pl_vis_cur` | ★ tests `ph_cur6`, in block units |
| `plane_pri` → `pl_map_pri` → `phase_draw_pri` | cached slice in `pl_pri_cur` | ★★★★ **slot 5** — tests `ph_cur5` |
| `pic_fill.s` `ff_win_map` / `_lo` | invalidated **both** caches | ★★★ removed — a THIRD instance |
| `vm_text_ops.s` `tx_window_exit` | invalidated `res_curblk` **and** called `plane_reset` | ★ removed |
| `p3b_probe.s` ×6 | `plane_reset` / `sta res_curblk` | ★ removed |
| `pic_probe.s` ×2 | `plane_reset` | ★ removed |
| hosts: `res_sweep.lua`, `vm_sweep.lua` | **write `$FF` to `res_curblk`** | ★★ correct on the single record; unchanged |
| hosts: `p3b_show.ps1`, `p3b_run.lua`, `p3b_gain.ps1`, `vm_run.ps1`, `vm_ablate.ps1`, `vm_symbols.py` | read `res_curblk` by name | ★★★ **why the name survives as an `equ`** |

#### §3(3) — what the two probes actually address ★★★★★

**Neither `res_probe.s` nor `vm_probe.s` references one plane symbol** — no `MAP_VIS_*`, no
`MAP_PRI_*`, no `plane_vis`, no `CP_VIS`, no `PLANE_WINDOWED`. `res_probe` fetches resources into
an arena and reports bytes; `vm_probe` runs the interpreter against per-cycle oracle state and
models the picture opcodes rather than drawing them.

★★★★★ **Measured before any edit**, with a six-line scratch file that included `mmu_phase.s` and
nothing else: **exactly the two plane errors and no other complaint from `memmap.inc`.** So the
blocker was those two `error` directives alone.

#### §3(4) — the guard, and why it was too wide ★★★★

Its own sentence is *"a build that addresses a plane **FLAT** must have a plane that fits its
window."* The condition was `ifndef PLANE_WINDOWED`, **which is also true of a build that addresses
no plane at all.** `MAP_VIS_BYTES` and `MAP_PHASE_WIN` are defined by `memmap.inc` itself, so the
arithmetic is meaningful in any build — and meaningless about a build with no plane to reach.

★★★★★ **Scoped, not weakened, and the default is unchanged.** A build that says nothing still gets
both checks; only a client that names itself plane-less is exempt, and naming itself is a visible
act in its own source [§2N's allowlist discipline]. ★★★★ **And the claim is checked rather than
trusted** — `composite.s`, `pic_core.s` and `plane_win.s` each refuse to assemble under
`PLANE_ABSENT`, which is the `COMP_PLANE_SAFE` pattern in the direction that works. The exemption
three paragraphs above it in that file decayed precisely because it was *"an assertion about code
that is not in the expression"*; this one cannot.

#### §4B — the design, and the correction it needed ★★★★★

★★★★★ **§4B said `plane_vis`/`plane_pri` should test the same record. They cannot: `plane_pri`
maps through `phase_draw_pri` into SLOT 5.** The contention that caused P6.74 and P6.78 is in slot
6. A single `$FFA6` record serves `res_map_block` and `plane_vis` and has nothing to say about
`plane_pri`.

★★★★ **And the units differed too** — `pl_vis_cur` held a SLICE (0..3), `res_curblk` a BLOCK
(0..$3F): the same register described two ways, which is part of why nobody noticed they were the
same fact. **The answer is one record per CONTENDED SLOT, in block units**, which is the unit the
register takes. The conversion is one `adda`: slice *n* of a plane is block `ph_blk_fb + n`, the
identity `pl_map_vis` already relied on when it called `phase_draw_fb`.

★★★★★ **AC-3's question — "can a cache disagree with the register?" — is answered structurally.**
After this change there is **exactly one `sta MMU_SLOT5` and exactly one `sta MMU_SLOT6` in the
tree**, each immediately preceded by the store that records it. **A writer cannot forget the
record, because reaching the register means coming through `phase_slot5`/`phase_slot6`.** Every
other routine — ten in `mmu_phase.s`, plus `plane_win.s` and `res_core.s` — calls one of them.

★★★ **`ph_blk_vol` is kept and is a different fact**: it is what slot 6 should hold **in the VM
phase** (an intent, which `phase_vm` restores from); `ph_cur6` is what it holds **now**, which a
draw phase changes without changing the intent. Two questions, two bytes — one byte answering both
is what `res_curblk` tried to be.

#### §1.3 — the structural guarantee, restated for its new customer ★★★★
`phase_vol` asserts nothing at runtime and still should not. **The guarantee being relied on is
unchanged** — a fetch never happens while drawing (§3.4) — and storage was **already** relying on
it: `res_core.s` wrote `$FFA6` directly from exactly the same call sites. What changes is that a
violation would now be visible rather than silent: a mid-draw fetch would record the volume block
and `plane_vis` would remap on its next access, instead of two caches disagreeing and one writing
into the other's memory.

#### §2S — sibling refs
POP3_port HEAD `104b197` (wip), karateka_coco3 HEAD `29f8f0a` (wip); both dirty with pre-existing
work not mine. **No `SHARED` file touched** — `src/engine/` and `src/harness/` are this repo's —
and `hal_sync_check.py` was run in all three repos (§5). lwasm 4.24 unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] Does scoping the assertion avoid moving any probe? ★★★★★ YES.** Reported
  before any other change (§3(3)/§3(4)). Both probes assemble with `PLANE_ABSENT` and their own
  maps; **neither gained a plane symbol, a window or a `PLANE_WINDOWED`.** The only footprint is
  `mmu_phase.s` itself: **+83 B on each**, identically (AC-5).

- **AC-2 [assembler · fault injection] The assertion shown RED. ★★★★ Three directions:**
  ```
  flat plane build (p3b without -DPLANE_WINDOWED):
    memmap.inc(494) : ERROR : "visual plane cannot be REACHED flat: it exceeds MAP_PHASE_WIN..."
  contradiction (-DPLANE_ABSENT -DPLANE_WINDOWED):
    memmap.inc(488) : ERROR : "PLANE_ABSENT and PLANE_WINDOWED are contradictory..."
  a plane subsystem refusing the claim (p3b with -DPLANE_ABSENT):
    plane_win.s(81) : ERROR : "plane_win.s addresses planes -- PLANE_ABSENT is false in this build"
  ```
  ★★★ **The guard is aimed, not removed**, and its new claim is itself checked.

- **AC-3 [design] The single record and the "can a cache disagree?" answer.** §4B above; stated in
  the source beside `phase_slot5`/`phase_slot6`, beside the retired caches in `plane_win.s`, and
  beside `res_map_block`.

- **AC-4 [byte-comparable · gate] All RUN, on the final source.**
  `res` **1,264/1,264 (100.00%)**, `vm` **9/9, 0 divergent cycles of 600 each**, `pic` **45 PASS /
  0 FAIL (of 45)**, `cel` **9,193/9,193**, `comp` **124/124**.

- **AC-5 [byte-comparable] §4A succeeded, so the probes change only by the mapping call.**

  | probe | before | after | delta |
  |---|---|---|---|
  | `vm` | 9,985 → 10,057 `90832641` | **10,140 `67987995`** | **+83** |
  | `res` | 2,129 `C96D1F68` | **2,212 `3826E5C0`** | **+83** |
  | `pic` | 2,654 `E0DDA8F0` | 2,654 `E0DDA8F0` | ★ **identical** |
  | `cel` | 1,527 `8B754B9C` | 1,527 `8B754B9C` | ★ **identical** |
  | `comp` | 967 `39F5D105` | 967 `39F5D105` | ★ **identical** |

  ★★★★ **What moved: `mmu_phase.s`, and nothing else.** The two probes share `res_core.s` and
  `mmu_phase.s` and no other changed file, so **an identical +83 on both attributes the delta to
  that one file.** ★★★ Their memory models are untouched; `res_probe` still orgs at `$0700` and
  `vm_probe` at its own base.

- **AC-6 [tooling] §4D's before and after.**
  ```
  BEFORE: 18 register access(es) in 2 file(s) over 4 register(s).
            src/engine/mmu_phase.s  17  $FFA3 $FFA4 $FFA5 $FFA6
            src/harness/res_core.s   1  $FFA6
  AFTER:   6 register access(es) in 1 file(s) over 4 register(s).
            src/engine/mmu_phase.s   6  $FFA3 $FFA4 $FFA5 $FFA6
  ```
  ★★★★★ **Two owners → one.** The count falls 17 → 6 in `mmu_phase.s` as well, because ten entry
  points now share two write sites.

- **AC-7 [state-comparable · fault injection] `plane_reset` retired; its arm replaced.**
  ★★★★★ **`-DPLANE_FAULT_PRIVCACHE` restores `plane_vis`'s private cache — the defect itself rather
  than the absence of its patch.** RED, on P6.78's own instrument:
  ```
  FAULT  RANGETAP A000-DFFF values BB,33 blk$0E:
    c8:$BB->$C3B4@$5444  c8:$BB->$C3B5@$5444  c8:$33->$C455@$5444  ... (24 records, all @$5444)
  CLEAN  RANGETAP A000-DFFF values BB,33 blk$0E:   <empty -- ZERO writes>
  ```
  ★★★★ Block `$0E` is KQ1 vol.1's first block and `$5444` is `co_put_visual`: **doubled sprite
  pixels written into the staged game data**, which is P6.78's measurement to the mechanism.
  ★★★★★ **AND THE FIRST INSTRUMENT I REACHED FOR COULD NOT SEE IT, which is a finding about
  P6.81 rather than about this arm.** `logic_copy_diff.py` on logic 1 read **0 of 256 on the fault
  arm** at 40 cycles and again at 120. The reason: **P6.81 made logic 1 resident** (hits 113,
  misses 41), so it is no longer re-fetched from the volume every cycle and the corruption no
  longer reaches it. **P6.78's symptom path is closed by the previous task, not by this one** — the
  writes still happen, and only a tap on the volume sees them. ★★★ Reported rather than reported as
  a pass [§2W: an arm proven for one question is not proven for another, L-82].

- **AC-8 [state-comparable] A castle run: logic 1 intact and the sprites draw.**
  `logic_copy_diff.py` **0 of 256** on logic 1 (resident at `$7327`, cycle 30); **staged sprites 4**;
  ego `x=110 y=100`; final room 1, err 0. ★★★ Every figure identical to P6.81's shipped arm,
  including `P3_PBUF` checksum `$C834` and `RESSTATS hits 113, misses 41, episodes 32, trims 34`.

- **AC-9 [measurement] `res_remaps` and s/cycle, before and after.**

  | | before (`df88846`) | after |
  |---|---|---|
  | remaps total (40 cycles) | **154 = 3.85/cycle** | **154 = 3.85/cycle** |
  | s/cycle (sum of stages) | 0.75688 | 0.76142 |

  ★★★★★ **Byte-for-byte the same remap count** — one owner costs no remaps it did not cost before.
  ★★ The 0.6% on s/cycle is run-to-run noise on an unthrottled host and is **not** claimed as a
  change; the cache figures are identical, which is the invariant that matters.

- **AC-10 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green (`all green`);
  `-ResCheck` **11 baselined, 228 verified, 0 mismatches, 0 sweep skips** — identical to P6.81;
  the mojibake gate clean over every tracked text file (§2J.7).

- **AC-11 [manifest]** Nine arms re-baselined — **all SHRINK**, by `-34` (cel arm), `-46` (the four
  `TEXT_WIRED`), `-37` (fault/flat), `-49` (the two combined). ★★★ **The split falls along what
  each arm links**, which is the check that the removal is scoped. `vm` re-pinned +83; `pic`, `cel`
  and `comp` byte-identical and untouched.

- **AC-12 [tooling]** `hal_sync_check.py` **OK in all three repos**; `gen_vm_tables.py --check` OK;
  `probe_identity_check.ps1` every non-p3b probe byte-identical; `p3b_arms_check.ps1` all 9
  byte-identical, `-SelfTest` red on exactly one row.

- **AC-13** §10.

- **25.3 / §4A eye gate [eye-gated — Jay] — RUN FIRST, before the byte gates were reported.**
  Live, RGB, `screen_config=1`, 300 cycles, `-Combined`. Expectations stated in the ask. Jay:
  1. behaves exactly as the last build — *"yes"* ★★★★ **as expected; this task moves ownership, not
     behaviour**, and the byte evidence agrees (AC-8).
  2. Graham, alligators and flags drawn and moving — *"yes"*.
  3. speed about the same — *"yes"* ★★ **as expected; no speed was claimed.**
  4. *"still same issues with the title page as before"* — ★★★ **pre-existing and unchanged by this
     task.** Two known items: the credits are cut by the gate's own room jump (`P3B_ROOM=1`, which
     `p3b_show.ps1` warns about and which T-P0-134 showed scroll normally under `-NoRoomJump`), and
     the "press a key to continue" carrying into the castle is P6.79's open item. §8 carries it.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**
```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
fetches requested vs STAGED-FOR: 1264 / 1264
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)

=== AC-2 SUMMARY ===   (vm gate, 600 cycles each, 0 divergent)
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS  SpaceQuest-1 PASS  SpaceQuest-2 PASS
PoliceQuest1 PASS  larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS

[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
  src/engine/mmu_phase.s   6  $FFA3 $FFA4 $FFA5 $FFA6

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)  [coco_agi]
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)   [POP3_port]
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)        [karateka]
CHECK OK: vm_tables.s matches optable.py.

vm 10140 B 67987995 [pinned] OK ... ★ every non-p3b probe byte-identical
p3b 15670 52AB9C76 | p3b_text 16882 4D78128E | p3b_win3 16882 F6FF8580 | p3b_notick 16879 9BF4601F
p3b_nomap 16879 217459FA | p3b_fault 15928 C7E8CEF2 | p3b_flat 15913 B393D1D0
p3b_comb 18892 687EFD0E | p3b_comb_count 18927 1641F878
★ all 9 arms byte-identical to the recorded baseline (SHA256)

res-checksum: 11 baselined, 228 verified, 0 mismatch(es), 0 sweep skip(s)
remaps total 154 = 3.85 per cycle          (before: 154 = 3.85 per cycle)
RESSTATS totals: hits 113, misses 41, starvation episodes 32, entries trimmed 34, cache entries 4
logic 1: differing offsets: 0 of 256 compared
```

**The `res` gate's first run, before its symbol map had a producer (§6):**
```
resources byte-identical to tools/volread/: 0 / 1 requested (0.00%)
fetches requested vs STAGED-FOR: 1 / 1264   ★★★ SHORT
build/res_stage/symbols.txt  (dated 2026-08-28, no producer):
    res_volbase 07BF   res_slicebase 07CF   res_curblk 07D8
generated from this build's map:
    res_volbase 0816   res_slicebase 0826   res_curblk 07C2
```

**25.2 bundled-artifact grep:** N/A — no artifact is bundled; nine arms and five probes are pinned
by hash above.

**25.3 operator-runtime-smoke:** **PASSED — Jay, live, RGB, `-Combined`, 300 cycles.** Answers and
adjudication in AC-13's block above. Run BEFORE the byte gates were reported, per §4A.

### 6 — Reactive deviations and route accounting

**§22.5 deviations. §6 says "anything else lands in the diff" is a stop, so all three are named:**

1. ★★★★★ **`res_run.ps1` gained a producer for its symbol map, and without it the `res` gate could
   not be run at all.** `build/res_stage/symbols.txt` was a hand-made file dated **2026-08-28** that
   nothing regenerated; `res_sweep.lua` pokes `res_volbase`/`res_slicebase`/`res_curblk` at the
   addresses it names. **This task moved `res_probe`'s layout, and the gate reported 1 fetch of
   1,264 with a guest failure** — what a correct program looks like when the host pokes the wrong
   addresses. ★★★★ **The file already warned about this in its own comment** — *"A per-stage copy
   went stale the moment the probe was rebuilt and poked res_volbase at the wrong address, which
   presents as bad-signature on every fetch rather than as a stale file"* — **it diagnosed the copy
   and deleted it, and never noticed the original had the same defect and no producer at all**
   [L-45; AD-119]. Now generated from the build's own map, so it cannot describe a different
   program than the one that runs. **Judged in scope because the dispatch makes `res` the reason
   this is a standalone task**, and it was unrunnable without this.
2. ★★★ **One record per contended SLOT, not one `$FFA6` record** — §4B's wording could not be
   implemented as written (`plane_pri` is slot 5). §6's third trigger, answered in §4B rather than
   stopped on, because the design goal is met and the extra byte is the same mechanism.
3. ★★ **`-PrivCache` replaces `-NoPlaneReset`** — §4C asked for exactly this.

**A defect this task introduced and caught before reporting** [§2W, and it belongs here]:
★★★★★ **The first version ran the castle at 0.183 s/cycle with `sprites 0`.** `pl_vis_base` is
assigned by `pl_map_vis`, which only runs on a remap; a private cache starting at `$FF` guaranteed
a first remap, and **testing the shared record removes that guarantee** — so the base stayed 0 and
every visual write landed at `offset & $1FFF`, in the direct page and the code. **It presented as a
fourfold speedup.** Fixed by initialising the constants at declaration rather than restoring the
forced remap. ★★★ Caught by `sprites 0` and by the figure being too good, not by a gate.

**ROUTE ACCOUNTING.** The dispatch specified the route (Option A) and this commit contains it. **NOT
implemented**: Option B (a shared record with two writers) and Option C (a mandatory entry point
with two caches) — neither is present; there is one record per slot and one writer per register.

### 7 — Uncertainty flags

1. ★★★★★ **AC-7's headline instrument could not see the defect, and that is a fact about the
   corpus, not about the fix.** `logic_copy_diff.py` is green on the fault arm because P6.81 made
   logic 1 resident. **A future task must not read that green as "the private cache is harmless"** —
   the volume tap shows 24 writes into staged game data in 40 cycles.
2. ★★★★ **`phase_vol` now writes `ph_blk_vol` on every resource fetch**, where `res_map_block` used
   to leave it alone. That is what `phase_vol` is for and `phase_vm` restores the last volume block,
   which is right for the VM phase — **but no test distinguishes "the intent the client set at boot"
   from "the last block fetched"**, and if a client ever depended on the former this would be silent.
3. ★★★ **The flat-backed build keeps `pl_vis_cur`/`pl_pri_cur`.** That is not a second cache — with
   no MMU there is no register to disagree with — but it does mean **`plane_win.s` has two shapes**,
   and only the MMU one is covered by the single-record argument. `pic_probe`'s 45/45 runs the flat
   path.
4. ★★★ **`res_curblk` is an `equ` onto `ph_cur6`.** One storage location, two spellings; kept
   because six host tools read the name and two write `$FF` to it. **It should be renamed in the
   hosts eventually** — until then a reader of `res_core.s` sees a name whose storage is elsewhere.
5. ★★ **The `vm` gate's arena is 21,760 B and it links no compositor**, so its green says nothing
   about slot-6 contention [§2T's lesson, fifth instance]. `p3b` is where that is exercised.
6. ★★ **s/cycle 0.757 → 0.761 is noise** and is not claimed either way.

### 8 — Follow-up candidates

1. ★★★★★ **The in-place VIEW read — next, and it is what this unblocks.** P6.81 left one LOGIC
   re-fetched per cycle because the compositor copies a 2,413-byte VIEW into the arena and starves
   the cache. Reading it in place removes the copy **and** the eviction. **That read is through slot
   6 while the compositor writes slot 6 — which is now ordinary.**
2. ★★★★ **Audit the other gates' symbol maps for producers** [§6(1)]. `res` had none for a month.
   **`build/vm_stage/symbols.txt` and the rest should be checked before one of them fails the same
   way** — and a stale map presents as a wrong result, not as a stale file.
3. ★★★ **The arena shortfall (1,405 B)** and **per-entry compaction at ~16%** — T-P0-134's, open.
4. ★★★ **Re-profile the shipped arm**: `interpret` 48%, `roomcheck` 26%, `composite` 25%, none
   measured since P6.79's profile on the corrupted base.
5. ★★★ **Rename `res_curblk` to `ph_cur6` in the six host tools** [§7(4)].
6. ★★ **The title page** [Jay, AC-13(4)]: the "press a key to continue" carrying into the castle
   (P6.79's open item), and the eye gate's default room jump cutting the credits.
7. ★★ **`checkPriority`/`checkCollision` and the moat**; real-time pacing; typing cadence;
   **`MAP_PRI_BANDS`** at `memmap.inc:310` — **the twenty-eighth task.**

### 9 — User interaction during task
The §4A eye gate, offered before the byte gates were reported, with expectations for each of the
four questions. Jay's answers are quoted in AC-13 and adjudicated there.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-a-guard-that-fires-on-builds-it-cannot-be-about.md`

### 11 — Commit
`fc1513e`  (pushed to origin/wip before this report)
Pool candidate `d1cdd9b` (methodology-candidate-pool, main).
