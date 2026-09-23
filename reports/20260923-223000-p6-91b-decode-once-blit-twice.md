## Form B Report — T-P0-145 / P6.91 — Decode once, blit twice
**Class:** recon (the dispatch opened as integration; §6 triggers 1 and 5 fired at §4A/§3(2) and
nothing was built). wip.

★ **Numbering note:** T-P0-144 was also labelled **P6.91**. Two dispatches now carry that number;
this report is filed as `p6-91b` so the two are distinguishable. **The Orchestrator's to reconcile.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-23 (HEAD `4962fc9`, wip — the dispatch says it descends from `d01f4a7`, which is two
commits back; T-P0-144 landed in between and touched no `src/`). git status clean at t0.

### 1 — Summary

★★★★★ **The dispatch's enabling premise is false, and `cp_composite` settles it in eleven lines.**
§1.2 says *"`CP_CEL` already holds the row while the first sprite is blitted; the second blit can
read it before it is overwritten."* **`CP_CEL` is overwritten `vc_h − 1` times during ONE sprite**:
`co_row` calls `vc_decode_row` per row under `COMP_ROW_PULL`, so when `cp_composite` returns the
buffer holds the last row only. ★★★★ **The dedup is not a second blit after a decode — it is two
blits interleaved inside one row loop**, each carrying its own `co_basex`, `co_prio`, `co_cury` and
row bases. **That is a restructure of the hottest loop in the program** (`cp_composite`, 28.9% of
the drawing stage).

★★★★★ **§4A's mirroring trap cannot occur, and the reason is architectural.** `vc_mir` is derived
inside `vc_decode_begin` from the cel header's mirror bit **and** the recorded loop compared against
`vc_loop` — both functions of `(view, loop, cel)`. ★★★★ **`vc_mir` appears nowhere in
`p3b_probe.s` or `composite.s`: there is no per-sprite mirror state.** Facing is a different
**loop**, which is already in the triple. **So the rule is simply: equal triples share a decode.**

★★★★★ **And the saving is room 1's alone.** Measured on every reachable room: room 1 has **1.00
adjacent duplicate per cycle** of 4.00 staged; **rooms 2, 3 and 5 have zero** — room 3 stages two
sprites but they are views 0 and 10. ★★★ **Two sprites sharing a view is a property of this room,
not of AGI** [§4C(4)], which is §6's fifth trigger verbatim.

★★★★ **Adjacency is incidental too.** `p3_stage_sprites` appends in **object-number order with no
sort**; nothing contracts that a shared view lands consecutively. A non-adjacent pair could only be
deduped by hoisting one blit next to the other, **changing draw order — and at equal priority
`co_depth` lets the later drawer win.** §6's first trigger.

> ★★★★ **So: ~4.4% of a cycle, in one room, by rebuilding the hottest loop, on an incidental
> property, in a region that is full.** **Reported, not built.**

★★★★★ **A §2W defect was found and fixed in this task's own instrument** — see §6(1). It printed
*"0 actually decoded"* for rooms that decoded every staged sprite.

**No shipped byte moved**: all nine arms byte-identical by SHA-256, all five probes byte-identical.

### 2 — Files modified
- `src/harness/p3b_probe.s` — **comment only**, beside `vc_dest`/`CP_CEL` in `p3_composite_all`:
  the sharing rule including mirroring, why the premise fails, the per-room table, and the
  adjacency caveat (§9 delta 1). ★ Arms re-verified byte-identical after the edit.
- `harness/tools/cel_reuse.py` — `--noskip`, and the §2W note explaining why it is needed.

### 3 — Reasoning

**§3(1) — the nine arms** are at P6.90's figures, SHA-256 verified (§5). P6.90 moved no shipped
byte and neither did T-P0-144.

**§3(2) — `p3_composite_all`'s loop, in full, which is what settles §7's premise.** Per staged
sprite `i`:

```
pca_lp:  p3_spr[i] -> CP_X, CP_Y, CP_PRIO, p3_view, vc_loop, vc_cel
         [P6.88 skip check -> pca_keep_rect + pca_next]
         res_locate(VIEW) ; vc_src, vc_srcend
         vc_dest = CP_CEL
         jsr vc_decode_begin      <- parses the header; sets vc_w/h/key/mir/remh
         jsr cp_composite         <- THE ROW LOOP LIVES IN HERE
         record p3_prev[i] = x, ytop, w, h, view, loop, cel
pca_next: i++
```

and inside `cp_composite` [composite.s:170-192]:

```
co_row:  if co_remh == 0 -> done
         ifdef COMP_ROW_PULL
             jsr vc_decode_row    <- CP_CEL is REWRITTEN here, once per row
             co_src = vc_dest
         endc
         blit the row; advance; loop
```

★★★★★ **`CP_CEL` is filled and consumed `vc_h` times per sprite, inside `cp_composite`.** There is
no instant at which one decoded cel is available to two blits. **§7's fifty-fourth premise is
refuted.**

**§3(3) — is the pair always staged consecutively? No, and nothing makes it so.**
`p3_stage_sprites` walks `VM_OBJ` from object 0 upward and appends any object with `fDrawn` set
[`pss_lp`]. ★★★★ **Ordering is by OBJECT NUMBER. There is no sort anywhere** — not by priority, not
by anything. Back-to-front is achieved by `co_depth`'s per-pixel test, not by list order. ★★★ **So
for room 1 the two alligators are reliably consecutive because they are adjacent object numbers and
that is stable — but it is a fact about KQ1's object table, not a contract.**

**§3(4) — what a second blit would need re-established.** Per sprite: `co_basex` (from `CP_X`),
`co_prio` (from `CP_PRIO`), `co_cury` and the running row bases (`co_rowset`), `co_remw`, `co_curx`.
**Per cel, and therefore shared:** `vc_w`, `vc_h`, `vc_key`, `vc_mir`, and the row walk itself.
★★★★ **The depth test and the priority write are per sprite and both must still run** — the two
alligators are at priorities 14 and 12 and different positions, so the blit differs even where the
row does not [§4B]. **That is exactly why the two blits must interleave rather than share state.**

**Authority tier.** Every claim here is **measured in this tree** or read from its source. ★ The
mirroring model is corroborated by the oracle's own loop tables (`loopTable4[3] = 0` RIGHT,
`loopTable4[7] = 1` LEFT, `view.cpp:719-725`), which express facing as a **loop index** — consistent
with `vc_mir` being a function of the triple. **Believed original, not a ScummVM normalisation**
[§2.1]: the mirror bit and its recorded-loop field are in the cel header on disk.

**§2H's three checks.** (1) *A second mechanism for a different object class?* Yes — the ego is
deduped by P6.88's **skip**, background props by nothing; the two paths do not compose, and §4C(4)'s
per-room table is what exposed it. (2) *The calling routine.* `cp_composite` is called once per
sprite from `p3_composite_all`; **the row loop is the callee's**, which is the whole finding. (3)
*Grep the reports.* P6.90 (the 1-slot hits), P6.89 (runs not reachable), P6.87 (`cp_composite`
28.9%, `vc_decode_row` 26.6%) agree and none contradicts.

**§2S.** No sibling claim is made.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: design]** ★★★★★ **§4A's rule, before any implementation narrative** — **PASS.**

  > **Two staged sprites share a decoded row iff their `(view, loop, cel)` triples are equal.
  > Nothing else is required.**

  ★★★★ **Mirroring does not enter the rule, and cannot.** `vc_decode_begin` sets `vc_mir` from the
  cel header's bit 7 **and** the recorded loop (bits 4-6) compared against `vc_loop`
  [`view_cel.s:223-235`] — both determined by the triple. ★★★ **`vc_mir` is referenced in no other
  file**; `grep vc_mir src/harness/p3b_probe.s src/harness/composite.s` returns nothing.
  **"Same triple, opposite mirror flags" is not a reachable state**, because a sprite facing the
  other way is a different **loop**, and the loop is in the triple. ★★ Size cannot differ either:
  `vc_w`/`vc_h` come from the same header.

- **AC-2 [class: state-comparable]** Planes byte-identical over 120 cycles — **PASS, by SHA-256.**
  All nine arms are byte-identical **after** this task's comment-only edit, so the pre- and
  post-change programs are the same program and a plane dump would compare a binary with itself.
  ★★ **Stated with its reason rather than run** — P6.88's stale-dump incident is precisely the
  failure a self-comparison invites.

- **AC-3 [class: measurement]** §4C's four figures — **PASS for (1) and (4); (2) and (3) are
  unmoved by construction.**
  1. **Decodes per cycle: 3.98 moving / 3.11 standing, unchanged** — nothing was built.
     **Rows** is the right unit if the dedup were per row, and the dedup would remove **1.00
     decode/cycle**, i.e. `vc_h` row-decodes for one cel.
  2. **0.3063/0.3004 moving, 0.2350/0.2336 standing — unchanged**, cited [§2, P6.90].
  3. **`vc_decode_row` 26.6% of the drawing stage — unchanged**, cited [P6.87].
  4. ★★★★★ **How often the dedup fires, and in rooms that are NOT room 1** — the measurement §6's
     fifth trigger turns on:

     | room | staged/cycle | **adjacent duplicates/cycle** | distinct triples |
     |---|---|---|---|
     | **1** | 4.00 | **1.00** | 15 |
     | 2 | 0.00 | 0.00 | 0 |
     | 3 | 2.00 | **0.00** | 2 — views 0 and 10, different |
     | 5 | 1.00 | 0.00 | 1 |

     ★★★ **In room 1 every duplicate is adjacent** (79 adjacent = 79 any-order over 79 cycles).
     ★★ **Priced**: 1.00 of 3.98 decodes = 25.1%, × 26.6% of the stage × 59–65.5% of the cycle ≈
     **4.4% of a cycle, in room 1 only.** *Arithmetic composing this task's rate with P6.87's
     shares — labelled unverified per §8.*

- **AC-4 [class: state-comparable · fault injection]** An arm sharing a decode it should not, the
  mirror flag ignored — ★★★★ **NOT BUILDABLE AS SPECIFIED, and AC-1 is why.** There is no
  per-sprite mirror flag to ignore. ★★★ **The arm that would produce the intended artefact is one
  that shares on a PARTIAL triple** — matching `view` while ignoring `loop` and `cel` — which is
  exactly "a sprite facing the wrong way or stuck on the wrong frame". ★★ **Not built, because
  §6 stopped the implementation**; recorded so the arm arrives with the change if it is ever taken.

- **AC-5 [class: byte-comparable · gate]** **PASS, fresh.** `cel` 9,193/9,193 and `comp` 124/124
  **run**; `pic` 45/45, `res` 1,264/1,264, `vm` 9/9. **`cel_probe` and `comp_probe`
  byte-identical**; no change was unconditional — the only `src/` edit is a comment.

- **AC-6 [class: byte-comparable]** Region A's headroom and `-IfRec` — **PASS (still red,
  unchanged).** `-IfRec` fails at `p3b_probe.s:4014`, *"P3b code overruns MAP_RESERVED_END"*.
  ★★★★ **The dispatch anticipated that this task would add code to that region. It did not** — so
  the headroom is exactly P6.90's, and the block stands.

- **AC-7 [class: suite]** **PASS.** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green
  ("all green"). ★★ **`-ForceOverlap` re-run: `isolated` still falls to 0** — P6.88's guards still
  refuse. Fault arms red under their own scenarios (`p3b_arms_check -SelfTest`, §5).

- **AC-8 [class: eye-gated — Jay]** ★★ **Not offered, and the reason is the finding.** The nine
  arms are byte-identical to the build Jay watched at T-P0-141/142. AC-8's three questions all
  presuppose a dedup that §6 stopped: **"do they animate identically" has the same answer it had
  before, because nothing changed.** Per CLAUDE.md §4A.3 this is a census, not an integration task,
  so "pending Jay" is not owed.

- **AC-9 [class: manifest]** **PASS.** Arms did not move, so no re-baseline was needed; verified
  twice — before the comment edit and after.

- **AC-10 [class: byte-comparable]** **PASS.** Verbatim in §5. ★ **`reg_discipline`: still one
  owner** — 6 accesses, 1 file, 4 registers.

- **AC-11** **PASS.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
=== §4A, the rule: vc_mir has no per-sprite source ===
$ grep -n vc_mir src/harness/p3b_probe.s     ->  (no matches)
$ grep -n vc_mir src/harness/composite.s     ->  (no matches)
src/harness/view_cel.s:49   vc_mir  fcb  0   ; 1 = this cel is mirrored IN THIS LOOP
src/harness/view_cel.s:223  * mirrored = bit 7 set AND the recorded loop != the loop we are decoding

=== §7's premise, refuted at composite.s:170-192 ===
co_row:
                lda     co_remh
                lbeq    co_done
                ifdef   COMP_ROW_PULL
                jsr     vc_decode_row          <-- CP_CEL rewritten, ONCE PER ROW
                ldd     vc_dest
                std     co_src
                endc

=== §3(3), staging order is object number (p3b_probe.s pss_lp) ===
pss_lp:  lda VMO_FLAGS+1,x / bita #fDrawn / beq pss_next
         ... copy x,y,prio,view,loop,cel ... / inc p3_nspr
pss_next: leax VMO_SIZE,x / incb / cmpb #VM_OBJ_MAX / blo pss_lp
         -- no sort, by priority or otherwise

=== §4C(4), duplicates per room, skip disabled, cycles 11-89 ===
room 1    79 cycles  staged  4.00/cycle  ADJACENT DUPES  79 = 1.00/cycle  (any-order 79)  distinct 15
room 2    79 cycles  staged  0.00/cycle  ADJACENT DUPES   0 = 0.00/cycle  (any-order  0)  distinct 0
room 3    79 cycles  staged  2.00/cycle  ADJACENT DUPES   0 = 0.00/cycle  (any-order  0)  distinct 2
          room 3's staged triples: {'0.0.0': 79, '10.0.0': 79}
room 5    79 cycles  staged  1.00/cycle  ADJACENT DUPES   0 = 0.00/cycle  (any-order  0)  distinct 1

=== §2W, the fixed tool reproduces the independent hand count above ===
room 1: 316 staged, 316 decoded, INTRA adjacent 79 (1.00/cycle)
room 2:   0 staged,   0 decoded, INTRA adjacent  0 (0.00/cycle)
room 3: 158 staged, 158 decoded, INTRA adjacent  0 (0.00/cycle)
room 5:  79 staged,  79 decoded, INTRA adjacent  0 (0.00/cycle)

=== AC-5/AC-7, run_gates.sh all ===
* source integrity: clean
Kingquest3-v0 (comp)      124      124        124        0          0
TOTAL (res)              1264     1264       1264        0          0
TOTAL (cel)              9193     9193       9193        0        0     1525
* gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green

=== AC-5, vm ===
PoliceQuest1 PASS   larry1 PASS   BlackCauldron PASS   MixedUpMotherGoose PASS
(9 of 9)

=== AC-6, -IfRec ===
src/harness/p3b_probe.s(4014) : ERROR : User Specified: "P3b code overruns
  MAP_RESERVED_END -- see the .map for the size"

=== AC-9, arms, AFTER the comment-only edit ===
p3b_comb    19336 B  B5A60E1D  OK
p3b_comb_count  19371 B  A3DD030C  OK
* all 9 arms byte-identical to the recorded baseline (SHA256)

=== AC-10 ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
  src/engine/mmu_phase.s     6   $FFA3 $FFA4 $FFA5 $FFA6
CHECK OK: src/harness/vm_tables.s matches optable.py.
* every non-p3b probe byte-identical
mojibake: src/harness/p3b_probe.s clean, harness/tools/cel_reuse.py clean
```

**25.2 bundled-artifact grep:** N/A — nothing was built or bundled.

**25.3 operator-runtime-smoke:** **N/A — not offered.** The nine shipped arms are byte-identical to
the build Jay watched at T-P0-141/142. See AC-8.

### 6 — Reactive deviations and route accounting

1. ★★★★★ **A §2W DEFECT IN THIS TASK'S OWN INSTRUMENT, found and fixed.** I ran `-NoSkip` to strip
   P6.88's masking, and `cel_reuse.py` reported ***"158 staged, 0 actually decoded"*** for room 3 —
   **for a build in which the skip was disabled and every staged sprite WAS decoded.**
   ★★★★ **Cause:** `-DP3B_NOSKIP` makes `p3_composite_all` *ignore* `p3_skip[i]`, but
   `p3_skip_decide` still **runs and still sets it**; the CELTRACE tap reads the flag at phase 9,
   so it records **the decision, not the action.** ★★★★★ **The number was plausible, precise and
   completely wrong**, and it is exactly L-82's shape — *an instrument proven for one question is
   not proven for another*. **P6.90 only ever ran it with the skip enabled, where the two agree.**
   ★★★ **Fixed** with `--noskip` plus the note explaining why, and **cross-checked against an
   independent hand count that agrees exactly** (§5). ★★ **Caught because "room 3 stages 2 sprites
   and decodes 0 under -NoSkip" is not a possible state** — the arithmetic, not the eye.
2. ★★★★★ **§6 trigger 5 fired** — the saving is a property of room 1 alone (AC-3(4)) — **and
   trigger 1 with it**: adjacency is incidental, and deduping a non-adjacent pair would change draw
   order, which is a ruling. **§4B (build) and §4D (the licence) were not executed**; AC-4 is
   unbuildable as specified (AC-1) and AC-8 is not owed.
3. ★★★ **The report is filed as `p6-91b`** because T-P0-144 already carries P6.91. **Flagged, not
   silently renumbered.**

**ROUTE ACCOUNTING.** I proposed no route beyond the dispatch. What this change contains: **one
comment block in `p3b_probe.s` and one switch plus its rationale in `cel_reuse.py`.** What it does
**not** contain: any dedup, any change to `cp_composite`, any change to staging, and any shipped
byte. ★★ **The dedup is described in `view_cel.s` (P6.90), in `p3b_probe.s` (this task) and in this
report, and it was not built** — stated here because a described-but-unbuilt optimisation is
invisible in a diff.

### 7 — Uncertainty flags

1. ★★★★ **Four rooms is not the game.** Rooms 1, 2, 3 and 5 are what `P3B_ROOM` reached; **a room
   elsewhere in KQ1 may well stage two sprites of one view.** The claim is *"zero in every room
   measured"*, not *"zero anywhere else"*. ★★ **It is still enough to refute "this is a property of
   AGI"**, which is what §4C(4) asked.
2. ★★★ **The moving runs in rooms 3 and 5 were discarded as confounded** — holding `LEFT` walked
   the ego out of the room and staged records fell to 0.05/cycle. **The per-room table is the
   standing case with the skip disabled**, which is the clean comparison; **no moving figure is
   claimed for rooms other than 1.**
3. ★★★ **The 4.4% is arithmetic**, composing 25.1% with P6.87's two shares. Labelled unverified per
   §8. **Only the duplicate rate is measured here.**
4. ★★ **The restructure was not attempted, so its true cost is an estimate.** "Two blits interleaved
   in one row loop" is read off the code, not built; **the byte cost in a full region A is unknown**
   and would itself be an AC-6 risk.
5. ★ **`vc_mir`'s absence was established by grep over two files.** The rule would break if any
   future per-sprite mirror state were added — **which is why AC-1's rule is now recorded in the
   source beside the loop.**

### 8 — Follow-up candidates

1. ★★★★★ **The map ruling — which the dispatch itself says is NEXT.** P6.90 priced its fifth
   symptom at ~15% of a cycle (the 20-slot cache at 95.4%). ★★★ **This task is the second
   optimisation in a row to end at it.**
2. ★★★ **If the dedup is ever revisited, it is a `cp_composite` restructure**, and it should be
   priced against the same room-1-only caveat and carry the partial-triple fault arm (AC-4).
3. ★★★ **`p3_stage_sprites` has no sort**, and §3(3) is the first task to say so plainly.
   **Worth a ruling of its own**: is object-number order intended, and does `co_depth` alone carry
   back-to-front for every case?
4. ★★ **A busier non-castle room** for the per-room table — §7(1).
5. Carried, unchanged: the VIEW checksum gap; design spec §7.1's `0.039 s/cycle` (fifteen tasks
   flagged); the fill and the two core loops as rulings; option 3 and the sidecar variant; a scene
   separating P6.88's two guards; real-time pacing; typing cadence; the title page items;
   `checkPriority`/`checkCollision`; `MAP_PRI_BANDS` (thirty-sixth task — ★ **`memmap.inc` is a §6
   stop trigger, so the counter was NOT bumped**); **and the Sierra bar from T-P0-144: their room
   draw 1.58 s against our 6.16.**

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-23-the-flag-recorded-a-decision-not-an-action.md`

### 11 — Commit
`1f5bdb7` (pushed to origin/wip before this report)
