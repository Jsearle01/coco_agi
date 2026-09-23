## Form B Report — P6.88 — Composite only what changed
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `6f41ad8`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task.

### 1 — Summary
The composite now skips a sprite that is **unchanged, isolated from every other OLD rectangle, and
alone in its priority band**. `p3_skip_decide` runs inside `p3_restore_prev`, where `p3_prev` is
still live. **Standing still: cels composited 3.73 → 2.91, steady cycle 0.2796/0.2837 →
0.2350/0.2336 (−16.0% / −17.7%).** ★★★★★ **Moving: nothing at all — 0.03 skips/cycle, and both
arms measure 0.3063/0.3004.** Room change unmoved. **Both planes byte-identical to a non-skipping
reference over 120 cycles.**

★★★★★ **§4A's rule needed more than the dispatch proposed, and the extra piece is the finding.**
"Unchanged AND not overlapped by a restored rectangle" misses a sprite that **moves into** an
unchanged one's area — and at **equal priority** `co_depth` lets the later drawer win, so a skip
can invert the overlap. **A new rectangle's extent is not knowable before `vc_decode_begin`**, so
the rect test cannot be widened to cover it; requiring the sprite's **priority band to be unique**
removes the dependence on that extent. It refuses 12 of 111 skips.

★★★★★ **THE CORRECTNESS EVIDENCE IS WEAKER THAN IT LOOKS AND THE REPORT SAYS SO.** Both guards are
**unexercised**: disabling the isolation test *or* the priority test leaves both planes identical,
because **the castle has no overlapping sprites at all** and no room this probe can reach stages
more than four. ★★★ **The comparison proves the skip is right in a room that cannot test its
guards.**

★★★★ **And it costs 371 B: `-IfRec` no longer assembles.** Region A is full again — the headroom
P6.85 recovered is spent.

### 2 — Files modified
- `src/harness/p3b_probe.s` — `p3_skip`, `p3_nskip`, `p3_nunch`; `p3_skip_decide`, `psd_iso`,
  `psd_prio_uniq`; the skip at `p3_composite_all`'s per-sprite head; `pca_keep_rect`;
  `-DP3B_NOSKIP` (before arm), `-DP3B_SKIP_NOISO` / `-DP3B_SKIP_NOPRIO` (fault arms).
- `harness/tools/p3b_run.lua` — the SKIP-ceiling readout.
- `harness/tools/p3b_show.ps1` — `-NoSkip`, `-SkipNoIso`, `-SkipNoPrio`, and the two symbols.
- `harness/tools/gates.manifest` — §9's record of what `comp` cannot see, and of this task's arm
  **and its blind spot**.
- `harness/tools/p3b_arms_check.ps1` — the three cel-linked arms re-baselined (+371 B).

### 3 — Reasoning

#### §3(2) — the two routines, their order, and where a skip sits ★★★★★
`p3_restore_prev` runs at stage 9 before `p3_composite_all`. It walks `p3_prev` (last frame's
rectangles), calls `prp_same` per index, and **erases only the changed ones**. `p3_composite_all`
then **clears `p3_prevn`** and rebuilds the list from what it draws.

★★★★★ **That clear is why the decision cannot be taken in the composite loop**: by the time it
walks the sprites, the previous frame's rectangles are gone. The decision is taken during the
restore, which is also where `prp_same` already runs — **the same test at a second call site**,
which was §1.1's premise and holds, but not on its own (§4A).

#### §3(3) — `prp_same` answers a different question than the composite needs ★★★★
`prp_same` compares **x, y, view, loop, cel** and answers *"are this sprite's pixels identical to
what is already on the plane?"* ★★★ That is necessary for the composite and **not sufficient**: the
restore's question is about the sprite itself, the composite's is about **whether anything else
disturbed it**. §4A is the difference.

#### §3(4) — what can disturb a skipped sprite's priority bytes ★★★★
`prp_visual` and `prp_priority` walk the **identical rectangle**, so a restore disturbs both planes
over exactly the same area — **one overlap test serves both** and §1.2(3) needs no separate rule.
The composite's priority write is per drawn pixel and is mediated by `co_depth`, which is the
equal-priority case below.

#### §4A — the three disturbance cases, and the rule ★★★★★

| | case | can it occur? | what covers it |
|---|---|---|---|
| 1 | a changed sprite's **RESTORE** overlaps an unchanged one | ★ **yes** — the restore writes the shadow blindly, respecting no priority | the **old-rectangle** disjointness test |
| 2 | a changed sprite's **COMPOSITE** overlaps an unchanged one | ★★★ **yes, and only at equal priority** | the **priority-uniqueness** test |
| 3 | the **PRIORITY plane** | ★ same two cases, same rectangles | both of the above |

**Case 2 in full, because it is where the dispatch's rule fails.** If `j` composites into `i`'s
area while `i` is skipped, the result differs from a full redraw **only if `i` would have drawn over
`j`** — and in two of three sub-cases it would not:
- `i` **nearer** (`prio_i > prio_j`): `i`'s priority bytes are still in the plane (unchanged ⇒ not
  restored), so `co_depth` **rejects** `j` there. Correct without drawing `i`.
- `i` **farther**: a full redraw also lets `j` win, whatever the order. Correct.
- **equal**: `co_depth` rejects only `screenPriority > viewPriority`, so it **draws** — the later
  drawer wins, and if `i` is later in list order a full redraw would have put `i` on top.
  ★★★★★ **This one is wrong.**

★★★★★ **And it cannot be fixed by widening the rectangle test, because `j`'s NEW extent is unknown
here**: `p3_spr` carries x, y, prio, view, loop, cel and **no width or height** — those come from
`vc_decode_begin`, inside the composite loop. ★★★ **Requiring `i`'s priority to be unique removes
the dependence on an extent this point cannot know.** Conservative, computable, sound.

> **THE RULE.** Skip sprite *i* iff `prp_same(i)` **and** `rect_old(i)` is disjoint from every other
> `rect_old(j)` **and** `prio(i)` differs from every other staged sprite's priority.

★★★ **The rect test is not subsumed by the priority test**: a restore writes the shadow *blindly*,
so an overlapping restore erases `i` whatever the priorities are.

★★ **`pca_keep_rect` is the other half.** `p3_composite_all` rebuilds `p3_prev` from what it draws,
so a skipped sprite recording nothing would be **absent from next frame's list** and next frame's
restore would not erase it — **it would smear the first time it moved.** The record to carry is the
one already there, copied because a sprite that failed to composite leaves `p3_prevn` behind
`p3_si`.

#### §2S — sibling refs
POP3_port `104b197` (wip), karateka_coco3 `29f8f0a` (wip); both dirty with pre-existing work not
mine. **No `SHARED` file touched**; `hal_sync_check.py` OK. lwasm 4.24 unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [design]** §4A's rule and all three cases, above, before the implementation.

- **AC-2 [state-comparable] The frame-to-frame comparison — and §4C's arm ALREADY EXISTED.**
  `p3b_run.lua` dumps `guest.visual.bin` and `guest.priority.bin` (26,880 B each) under
  `P3B_DUMP=1`. Run 120 cycles with and without `-DP3B_NOSKIP` and compare:
  ```
  reference (-NoSkip) : A98D101961D6 / AC8216D4CFD8
  skip active         : A98D101961D6 / AC8216D4CFD8    ★ IDENTICAL, both planes
  ```
  ★★★★ **120 cycles of accumulated skipping leave both planes byte-identical.** That is the
  correctness claim and the only instrument that can hold it.

- **AC-3 [measurement] §4D's five figures.**

  | | standing still | moving (LEFT held from c12) |
  |---|---|---|
  | **(1)** cels composited / cycle | 3.73 → **2.91** | 3.73 → **3.71** |
  | | skipped / cycle (unchanged → isolated → skipped) | 0.93 → 0.93 → **0.82** | 0.03 → 0.03 → **0.03** |
  | **(2)** mean, cycles 11+ | 0.2796 → **0.2350** (**−16.0%**) | 0.3063 → **0.3063** (**0.0%**) |
  | | median | 0.2837 → **0.2336** (**−17.7%**) | 0.3004 → **0.3004** |
  | **(3)** the stage's share | 65.5% → ~60% (the classes that scale with cels) | unchanged |
  | **(5)** room change | 6.1412 s, **unmoved** | — |

  ★★★★★ **§4D(4) is the headline: the saving exists only while things hold still.** ★★★ By reason:
  of 0.93 unchanged per cycle, **the isolation test refuses 0** and **the priority test refuses
  0.11** (12 over 120 cycles). ★★ Moving is also inherently slower than standing (0.306 vs 0.280)
  because the ego animates.

- **AC-4 [state-comparable] What moved and what did not.** ★★★ **`co_written` and `CP_BLITS` are
  EXPECTED to fall** — that is the change: `CP_BLITS` 448 → 349 over 120 cycles, exactly the 99
  skipped; `co_WRITTEN` 38,559 → 29,550. ★★★★ **What must NOT move, and did not: both planes**
  (AC-2), `restore 99954 bytes` on both arms, ego position, room, `staged sprites 4`.

- **AC-5 [byte-comparable · gate] All RUN.** `comp` **124/124** and `cel` **9,193/9,193**, `pic`
  **45 PASS / 0 FAIL (of 45)**, `res` **1,264/1,264**, `vm` **9/9**. ★★★★★ **`comp` staying green is
  NOT evidence for this change** [§1.3] — recorded in `gates.manifest` rather than only here.
  **`comp_probe` byte-identical**; nothing in `composite.s` changed.

- **AC-6 [state-comparable · fault injection] ★★★★★ NEITHER FAULT ARM CAN FIRE, AND THAT IS
  REPORTED AS A FAILURE OF THE CORPUS, NOT A PASS.**
  ```
  -SkipNoIso  (isolation test always yes) : A98D101961D6 / AC8216D4CFD8   ★ IDENTICAL, 99 skips
  -SkipNoPrio (priority test always yes)  : A98D101961D6 / AC8216D4CFD8   ★ IDENTICAL, 111 skips
  ```
  ★★★★ **The castle has no overlapping sprites**: 0 of 111 unchanged sprites are refused by
  isolation. `-SkipNoPrio` skips **12 more** sprites and still produces identical planes.
  ★★★ **Searched for a busier room and there is none reachable**: room 2 stages 0 sprites, room 3
  stages 2, room 5 stages 1, against the castle's 4. ★★ **So AC-6 is NOT satisfied**, and §6's
  fourth trigger applies: the eye gate is not being allowed to stand in for it silently.

- **AC-7 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green (`all green`);
  `-SelfTest` red on exactly one row; mojibake clean. ★★★★★ **`-IfRec` does NOT assemble** —
  `"P3b code overruns MAP_RESERVED_END"`. **AC-7's last clause fails**, see §7(3).

- **AC-8 [eye gate — Jay]** Live, RGB, 300 cycles, offered before the byte gates were reported,
  with expectations including that a wrong skip looks like a *mostly right* sprite. Jay:
  1. *"nothing noticed"* — ★★★★ no trail, hole or half-erased edge while walking.
  2. *"yes"* — the screen stays correct standing still.
  3. *"no"* — not faster while moving. ★★★ **Exactly the stated expectation (0.0%).**
  4. *"no"* — nothing else different.

- **AC-9 [manifest]** Three cel-linked arms re-baselined **+371 B**; ★★★ **the six text arms
  byte-identical** — the scoping check. The new arm and **its blind spot** recorded in
  `gates.manifest` [L-121].
- **AC-10 [tooling]** `hal_sync_check.py` OK; `reg_discipline` **6 accesses in 1 file — still one
  owner of `$FFA6`**; `gen_vm_tables.py --check` OK; `probe_identity_check.ps1` every non-p3b probe
  byte-identical; `p3b_arms_check.ps1 -SelfTest` red on one row.
- **AC-11** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
=== AC-2 SUMMARY === all nine titles PASS (vm, 600 cycles each, 0 divergent)

AC-2 plane comparison, 120 cycles, P3B_DUMP=1, room 1 (visual / priority):
  -NoSkip reference   A98D101961D6 / AC8216D4CFD8
  skip active         A98D101961D6 / AC8216D4CFD8    IDENTICAL
  -SkipNoIso  (fault) A98D101961D6 / AC8216D4CFD8    IDENTICAL -- the guard is unexercised
  -SkipNoPrio (fault) A98D101961D6 / AC8216D4CFD8    IDENTICAL -- 12 extra skips, no difference

AC-3 standing: SKIP ceiling over 120 cycles: unchanged 111 (0.93/cycle), isolated 99 (0.82/cycle)
     CP_BLITS 448 -> 349      mean 0.2796 -> 0.2350   median 0.2837 -> 0.2336
     moving  : SKIP ceiling over 120 cycles: unchanged 3 (0.03/cycle), isolated 3 (0.03/cycle)
     CP_BLITS 448 -> 445      mean 0.3063 -> 0.3063   median 0.3004 -> 0.3004
     room change [cyc] 9 = 6.1412 s, unmoved
AC-4 co_WRITTEN 38559 -> 29550 (expected); restore 99954 bytes both arms; ego x=110 y=100 both

rooms reachable, staged sprites: room 1 -> 4 | room 2 -> 0 | room 3 -> 2 | room 5 -> 1
-IfRec: ★★★ DOES NOT ASSEMBLE -- "P3b code overruns MAP_RESERVED_END"

★ all 9 arms byte-identical to the recorded baseline (SHA256)   [3 re-baselined, +371 B]
★ every non-p3b probe byte-identical      comp 967 B 39F5D105
[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
[hal-sync] OK      CHECK OK: vm_tables.s matches optable.py.
```

**25.2 bundled-artifact grep:** N/A — nine arms and five probes pinned by hash.

**25.3 operator-runtime-smoke:** **PASSED — Jay, live, RGB, `-Combined`, 300 cycles.** AC-8.

### 6 — Reactive deviations and route accounting

★★★★★ **TWO STALE ARTIFACTS WERE NEARLY REPORTED AS RESULTS, AND ONE OF THEM WAS THE CORRECTNESS
CLAIM.**
1. **The plane dump is gated by `P3B_DUMP`, which I had not set.** The first AC-2 comparison read
   `guest.visual.bin` **dated the previous day** and reported "both planes identical" — **a stale
   file compared with itself.** Caught because room 3's planes hashed identically to room 1's,
   which is implausible. Re-run with `P3B_DUMP=1`; the real reference hashes differ from the stale
   pair, and the claim survived — **but it was luck that the tell was visible.**
2. **lwasm writes nothing on error**, so `-IfRec`'s check printed `19988 B` from the previous
   successful assemble. Deleted and re-run: it does not assemble. [AD-90's shape, both.]

**Other deviations:**
3. ★★★ **`-DP3B_SKIP_NOPRIO` was added after `-DP3B_SKIP_NOISO` came back green** — §2W: an arm
   that cannot fire is not an arm, so a second was built to find one that could. **It also came
   back green**, which is the §4A/AC-6 finding rather than a third attempt.
4. ★★ **`-DP3B_NOSKIP` was added** — the before arm, so the saving is measured one binary apart.
5. ★★ **`p3_nskip`/`p3_nunch` are cumulative 16-bit**, not per-frame bytes: the question is a rate
   over a window [P6.84].

**ROUTE ACCOUNTING.** The dispatch specified the skip and this commit contains it, **with a third
condition the dispatch did not name** (priority uniqueness, §4A). **NOT implemented**: any change
to `p3_restore_prev` (§6's sixth trigger — it is correct and is what makes this possible); option 4
per-run compositing; option 3's fusion (§1.4, deferred).

### 7 — Uncertainty flags

1. ★★★★★ **Neither guard is exercised, anywhere this probe can reach.** The correctness evidence is
   "the skip is right in a room that cannot test its guards." **A room with overlapping sprites, or
   a constructed scenario, is what would settle it** — and §1.3 predicted exactly this.
2. ★★★★★ **The saving is 16% standing and 0% moving**, and the player notices movement. ★★★ In real
   play the ego is often idle (reading, typing, thinking), so this is not nothing — but **it is not
   a 16% faster game.**
3. ★★★★★ **`-IfRec` no longer assembles: +371 B has re-closed region A.** P6.85's 142 B of headroom
   is spent and then some. **The map ruling is now twice-blocked** and this task made it worse.
4. ★★★★ **The castle's four sprites are an atypically LOW load** [§2]. A busier room composites
   more and would skip a larger absolute number — **but would also be likelier to overlap**, which
   is where the unexercised guards start mattering.
5. ★★★ **`psd_prio_uniq` refuses 12 of 111 skips**, so two sprites DO share a priority band in the
   castle — the guard is doing work even though removing it changes no pixel here. ★★ That is the
   shape of a guard that is right in principle and unprovable in this corpus.
6. ★★ **The decision routine is O(n²) per frame** with n = `p3_prevn`. At 4 sprites it is below
   measurement; at 16 (`P3_SPR_MAX`) it would be 240 pair-tests a frame and worth re-measuring.

### 8 — Follow-up candidates

1. ★★★★★ **A scene that exercises the guards.** Two overlapping sprites, one moving into the other,
   at equal priority. ★★★ **Until that exists, both guards and the skip's soundness are argued
   rather than measured.**
2. ★★★★★ **The map ruling** — region A is full again and `-IfRec` is blocked. **Twice now.**
3. ★★★★ **Option 4, per-run compositing** — the dispatch's next item, and the one that does not
   depend on things holding still.
4. ★★★★ **Option 3's fusion** — deferred, with §1.4's objection recorded: `cel` gates 9,193 cels by
   comparing DECODED CEL BYTES, and fusing decode and blit removes the gate's subject.
5. ★★★ **Design spec §7.1's `0.039 s/cycle`** is `comp_probe`'s and is **eleven tasks flagged**.
   ★★★★ **The number that replaces it is now 0.2350 s/cycle mean standing, 0.3063 moving** — and
   **both should be published, because one without the other misleads** — PROPOSED TEXT ONLY [§2D].
6. ★★ **The fill** [P6.86]; **the two core loops** [P6.87]; **real-time pacing**; **typing
   cadence**; **`checkPriority`/`checkCollision`**; **`MAP_PRI_BANDS`** at `memmap.inc:310` — **the
   thirty-fourth task.**

### 9 — User interaction during task
The AC-8 eye gate, offered before the byte gates were reported, with expectations for all four
questions — including that a wrong skip looks like a *mostly right* sprite rather than a missing
one, and that no speed-up should be expected while moving. Jay's four answers are quoted in AC-8.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-a-guard-the-corpus-cannot-exercise.md`

### 11 — Commit
`c7ffb7a`  (pushed to origin/wip before this report)
Pool candidate `0ae67a7` (methodology-candidate-pool, main).
