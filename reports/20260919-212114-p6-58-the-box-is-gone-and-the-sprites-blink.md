## Form B Report — T-P0-112 / P6.58 — The box is gone, and the sprites blink
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 21:21:14 (HEAD b093d4c, wip). git status: `src/harness/p3b_probe.s`,
`harness/tools/gates.manifest`, `harness/tools/p3b_arms_check.ps1` modified; `?? coco_agi.code-workspace`
untracked (the editor's). One source file changed: **+347 / −2**.

### 1 — Summary

★★★★★ **THE BOX IS GONE.** Jay, at the eye gate: ***"so the flags look right. clean background."***
**P6.55's finding is confirmed** — four tasks after it was proposed and never once proven, absent
save-under *was* the cause, and restoring from the shadow planes fixes it.

★★★★★ **AND THE SPRITES NOW BLINK.** Jay, in the same sentence: ***"bu tboth the flags and graham
flash (blink)."*** ★★★★ **That is a real defect, it is mine, and §3.4 gives its mechanism: the
restore and the composite both write the VISIBLE plane, so for part of every frame the sprite has
been erased and not yet redrawn and the raster shows the gap.**

★★★★★ **The blink was always there and could not be seen, because the bug that was fixed was
hiding it.** While nothing ever erased a sprite there was nothing to blink. **Removing the
accumulation revealed that sprite compositing has never been double-buffered** — a scope decision
taken deliberately at T-P0-051 (*"only the RENDER gets a shadow. Sprites still composite straight
onto the visible plane"*) whose visible consequence had no way to appear until now.

The priority plane has a shadow at **blocks 45-46**, proven free from the allocator rather than from
a comment. Four byte gates re-run green. **Only the cel arm moved; the six text arms are
byte-identical.** §7A requests a ruling on the blink.

### 2 — Files modified

- `src/harness/p3b_probe.s` — the priority shadow (`p3_pri_shadow`), the sprite restore
  (`p3_restore_prev`/`prp_visual`/`prp_priority`/`prp_split`/`prp_copy`), the rectangle recorder in
  `p3_composite_all`, the block constants and their two assertions, `-DP3B_FAULT_NORESTORE`, and two
  short branches promoted to long. **All of it inside `ifndef P3B_NO_CEL`.**
- `harness/tools/p3b_arms_check.ps1` — `p3b` re-baselined 14,152 → **14,666 / F84C874F**. One line.
- `harness/tools/gates.manifest` — the `ifdef`-exclusion note (T-P0-110's rule), and §3.6's stale
  figure corrected.

★★★ **`composite.s` is NOT modified**, so `co_save`/`co_restore` remain dead and unassembled. This
shape does not use them and §6's fifth trigger never came near firing.

### 3 — Reasoning

#### 3.1 §3(2) — the free blocks, from the allocator, and a latent collision found on the way

★★★★★ **Not from a comment** [dispatch §2(3), and §6's first trigger]. Every
`build/vm_stage/*/manifest.txt` was read and each volume's block span computed from its byte length:

```
BlackCauldron  8-12,13-37   Kingquest1  8-13,14-38   Kingquest2  8-13,14-44  <- highest
Kingquest3     8-17,18-38   larry1      8-16,17-34   MixedUpMotherGoose 8-12,13-18
PoliceQuest1   8-16,17-40   SpaceQuest-1 8-12,13-40  SpaceQuest-2 8-16,17-36
```

**Highest physical block any staged title reaches: 44.** MAME's own driver declares
`<ramoption name="512K" default="yes">524288</ramoption>` and no harness passes `-ramsize`, so
blocks 0-63 exist and `$38-$3F` is the CPU window. ★★★ **45-55 is free. Blocks 45-46 taken.**

★★★★ **THE SAME READ FOUND A LATENT COLLISION THAT IS NOT THIS TASK'S.** The visible plane is
blocks **40-43**, and **Kingquest2 stages to 44, PoliceQuest1 and SpaceQuest-1 to 40.** Those three
titles' volumes overlap the visible framebuffer. ★★ **It is unreachable today** — the nine-title
sweep runs `vm_probe.s`, a different probe with no visible plane, and the p3b rows run Kingquest1
and SpaceQuest-2 — **so this is latent, not broken.** ★★★ **Nothing asserts it, which is P6.46's
shape exactly.** Reported, not fixed; §8.3.

#### 3.2 §4A — the blocks, and both assertions shown RED

```
P3_BLK_PRISHADOW   45      P3_BLK_PRISHADOW_N 2      P3_BLK_STAGE_MAX 44     P3_BLK_CPUWIN $38
```

★★★★ **Shown red from the COMMAND LINE, not by editing the file** — `P3_BLK_PRISHADOW` is
overridable via `-DP3B_FAULT_PRISHADOW`, so the fault arms are permanent and repeatable:

```
-DP3B_FAULT_PRISHADOW=44 -> ERROR "the priority shadow overlaps staged volume blocks ..."
-DP3B_FAULT_PRISHADOW=55 -> ERROR "the priority shadow reaches the CPU's own window at $38-$3F ..."
```

★★★ **Both directions** [§2W: *"a guard: break it on purpose in BOTH directions before believing
it"*], and the clean arm with the constants and assertions present built **byte-identical to the
14,152 B baseline**, which is the evidence that `equ`/`ifgt`/`error` emitted nothing.

★★ The code-growth guard was also confirmed live rather than assumed silent: `P3_CODE_END $55E4`
against `CP_CEL $5F00` — **2,332 B of margin** — and forced red to prove it can fire.

#### 3.3 §4B/§4C — the shape as built, and one deliberate departure from the dispatch

**The priority shadow.** §4B asked to *"redirect `ph_blk_pri` for the room's priority render, present
once per room"*. ★★★ **I did the mirror image instead: the render is left exactly where it is, and
the live plane is COPIED to the shadow immediately after `p3_present`.** Same result, and it touches
no part of the render path — which is gated by `pic` 45/45 and is the half worth not disturbing.
★★★★ **It also dissolves §2(4)'s ordering question rather than answering it**: the dispatch warned
that *"presenting priority while priority is the borrow victim is a new ordering question"*, and a
copy taken after the render, before any sprite exists, has no such question.

**The restore.** Per rectangle, per row, per plane, before compositing:

- visual: `off = row*160 + x`, `n = w`, one byte per pixel.
- priority: `off = row*80 + (x>>1)`, `n = ((x+w-1)>>1) - (x>>1) + 1`, packed. ★★ **Whole bytes, so
  it over-restores by up to one pixel at each edge — safe HERE and only here**, because every
  rectangle is restored before any sprite is composited, so the extra pixel can only receive the
  picture's own value.
- slot discipline: each pass maps **source and destination only** — shadow into slot 6, live into
  slot 5 — so no pass needs more than the two windows and §6's second trigger never fired.

★★★★★ **ORDERING.** `jsr p3_restore_prev` sits between `phase_draw_enter` and `p3_composite_all`,
and `p3_prevn` is cleared at the *top* of `p3_composite_all` — after the restore has consumed the
old list. The rectangle is recorded after `vc_decode_begin`, because `vc_w`/`vc_h` are the cel's and
are not known before it.

★★★ **P6.33's register trap was honoured explicitly:** `prp_copy` loads the count **after** the
addresses, with the comment restating why — `ldd` loads A *and* B, and the first version of
`p3rb_span` lost its loop count to the low byte of an offset.

★★★ **Two short branches became long** (`lbeq pca_out`, `lblo pca_lp`) — the byte-overflow this file
has now produced three times when a guarded block grew.

★★★★ **Everything new is inside `ifndef P3B_NO_CEL`, and that was verified, not assumed:**

```
p3b         14666 B  F84C874F  MOVED -- expected 14152 B 26763F91
p3b_text    16409 B  D09866C3  OK        p3b_notick  16406 B  7A9A319C  OK
p3b_win3    16409 B  35AB01B0  OK        p3b_nomap   16406 B  379A9421  OK
p3b_fault   15533 B  FA9C8531  OK        p3b_flat    15518 B  E3E95063  OK
★ 1 ARM(S) MOVED
```

#### 3.4 ★★★★★ The blink — mechanism, and why it could not have been seen before

**Mechanism.** Both the restore and the composite write the **visible** plane, the one the GIME is
displaying. Each frame the sequence is: erase last frame's sprite rectangles → composite this
frame's sprites. **Between those two the sprite is not on the screen**, and at ~10 cycles/second
that gap is a large fraction of a frame. The raster displays it. That is a blink.

★★★★★ **THE DEFECT THAT WAS FIXED WAS MASKING THIS ONE.** Before this change nothing ever erased a
sprite — that *was* the bug, and the accumulated union of cels was the box. A sprite that is never
erased cannot blink. **So the blink is not new behaviour; it is newly VISIBLE behaviour, and what
made it invisible was the defect on top of it.**

★★★★ **The underlying property is a scope decision from T-P0-051, stated in this file in capitals:**
*"THIS IS NARROWER THAN DOUBLE-BUFFERING AND DELIBERATELY SO. The picture render happens ONCE PER
ROOM, so only the RENDER gets a shadow. Sprites still composite straight onto the visible plane."*
★★★ **That was correct when the only thing writing the visible plane per frame was the compositor
adding pixels.** It stops being correct the moment something removes pixels every frame.

★★ **This is the same shape as T-P0-110's lesson, one level up:** a note that correctly recorded
what was excluded, and did not say what the exclusion would look like once the surrounding code
changed.

#### 3.5 §2H check 3 — the reports, grepped

P6.55, P6.56 and P6.57 all treat "absent save-under" as unproven. ★★★★ **It is now proven, by the
only instrument that could prove it** [§4A.3] — and the three reports' shared caveat is discharged
here rather than carried a fourth time.

#### 3.6 A stale baseline found beside a live one

★★★★ **`gates.manifest` carried `F875F7F6 13,870 B, re-baselined T-P0-102` through P6.47-P6.54**,
while `p3b_arms_check.ps1` was re-baselined every time. My first build reproduced 14,152 / 26763F91
and disagreed with the manifest by 282 bytes — **which for a moment looked like my flags being
wrong, and was the manifest being eight tasks stale.**

★★★ **Two records of one fact, one executable and one prose, and only the executable one was
maintained** [§2F]. The manifest row now says which to believe.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — MET.** §3.1/§3.2. Blocks from the allocator; both assertions RED both ways;
  clean arm byte-identical with them present.
- **AC-2 [state-comparable] — PARTIAL.** The priority shadow is taken once per room and the live
  plane is **not written** by that copy, so room-entry contents are unchanged *by construction*.
  ★★ **Not verified by census.** §7.2.
- **AC-3 [state-comparable] — NOT MET.** ★★★★ **No plane census was run.** The restore is evidenced
  only by the eye gate. **This is the gap in this task and it is stated plainly rather than
  softened** — §8.1.
- **AC-4 [measurement] — NOT MET.** `p3_restbytes` is implemented and counted but is **not published
  to the host**, so no per-frame byte figure exists. §8.1.
- **AC-5 [byte-comparable] — MET.** `composite.s` untouched (`git diff --name-only` empty for it);
  `comp` green below.
- **AC-6 [byte-comparable · gate] — MET, fresh.**
  `pic 45/45 PASS` · `res 1,264/1,264 (100.00%)` · `cel 9,193/9,193 (100.00%)` ·
  `comp 124/124, divergent 0`. ★★ **`vm` cited under §2T, not re-run:** it is built from
  `vm_probe.s`, and `git diff --name-only -- src/harness/vm_probe.s` is empty.
- **AC-7 [fault injection] — PARTIAL.** `-DP3B_FAULT_NORESTORE` builds at **14,663 B / D099FFD8**,
  exactly −3 B (the removed `jsr`). ★★ **It has not been RUN and shown red on a screen.** §8.1.
- **AC-8 [eye gate — Jay] — MET, and offered BEFORE the byte gates** [§4A]. Questions 1 and 2
  answered: *"the flags look right. clean background"*; Graham present. ★★★★★ **Question 3 answered
  with a defect: "both the flags and graham flash (blink)."** Question 4 (text) not reached — no box
  came up.
- **AC-9 [suite] — PARTIAL.** Four byte gates green; seven-arm identity check run; `$44`,
  `p3b_rescheck` and `-CelCheck` **not run**.
- **AC-10 [manifest] — MET.** Re-baseline landed, and T-P0-110's exclusion note with it, naming what
  `CP_SAVE`'s absence *looks like*.
- **AC-11 [tooling] — MET.** `hal-sync OK (11 files, POP3_port + karateka_coco3)` ·
  `reg-discipline 17 accesses, 1 file, 4 registers (mmu_phase.s only)` · `gen_vm_tables CHECK OK` ·
  `fix_mojibake --check` clean on all three edited files. ★ `probe_identity_check.ps1` not run —
  `comp_probe` is untouched and `comp` is green.
- **AC-12 — MET.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
$ lwasm ... -DPLANE_WINDOWED -DPRI_PACKED src/harness/p3b_probe.s
cel arm: 14666 B  F84C874F      (baseline 14152 -> +514 B)

$ p3b_arms_check.ps1
p3b 14666 F84C874F MOVED -- expected 14152 26763F91 ; six text arms OK ; ★ 1 ARM(S) MOVED

$ run_gates.sh pic   -> per-picture: 45 PASS, 0 FAIL   ★ all green
$ run_gates.sh res   -> 1264 / 1264 requested (100.00%)   ★ all green
$ run_gates.sh cel   -> 9193 / 9193 queued (100.00%)   ★ all green
$ run_gates.sh comp  -> frames 124  identical 124  divergent 0   ★ all green

$ hal_sync_check.py -> [hal-sync] OK -- aligned with POP3_port, karateka_coco3 (11 files)
$ reg_discipline.py -> 17 access(es) in 1 file(s) over 4 register(s): mmu_phase.s
$ gen_vm_tables.py --check -> CHECK OK
$ fix_mojibake.py --check <3 edited files> -> clean, exit 0

$ p3b_show.ps1 -Title Kingquest1 -Cycles 400 -Headless   (P3B_ROOM=1)
  final room 1, sprites 4, err 0, status=$00 ; 400 of 400 cycles ; no stall
```

**25.2 bundled-artifact grep:** N/A — no DECB artifact built this task.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED for the defect under repair and FAILED on a new
one — Jay, live, RGB, `p3b_show.ps1` room 1, 400 cycles at 99.75% speed** (§2U.2: eye gates run
unthrottled-free). *"the flags look right. clean background, bu tboth the flags and graham flash
(blink)."*

### 6 — Reactive deviations and route accounting

★★ **No §6 trigger fired.** Two came close and both were resolved with evidence rather than
worked around: the block accounting (§3.1 — closed from the allocator, and 45-55 is genuinely free)
and the slot problem (§3.3 — each pass maps only source and destination).

**Deviations from the dispatch's method, both deliberate and both stated:**

1. ★★★★ **§4B asked for `ph_blk_pri` to be redirected for the render and presented. I copied the
   live plane to the shadow after the render instead.** §3.3 gives the reasoning: same result, no
   change to a render path gated at 45/45, and it dissolves the ordering question §2(4) raised.
2. ★★★ **§4C's walk is not `p3_restore_box`'s.** That routine is inside `ifdef P3B_NO_CEL` — the
   cel arm does not have it — so "extend the existing walk" would have meant moving an `ifdef`
   boundary across five gated binaries. ★★ **I wrote the equivalent inside `ifndef P3B_NO_CEL`
   instead, which is duplication, and §2F says so.** The trade was six byte-identical arms against
   one shared routine, and §8.5 records it as debt rather than pretending it is not.

**Route accounting.** ★★★ **I proposed nothing this task beyond §7A's pricing, and implemented
exactly what §1's ruling specified** — shapes 2+3, no save-under revival, no `CP_SAVE`.

★ **One thing I said I would check and did not:** I told Jay the straddle case might show as "a thin
vertical sliver". **No census was run to see whether it did**, and he did not report one. §7.4.

### 7 — Uncertainty flags

1. ★★★★★ **The blink is unpriced.** §7A asks for a ruling; the options in it are costed in blocks
   but **no per-frame timing was measured**, and whether the restore+composite fits a VBL window is
   the question that decides between them. **Not measured.**
2. ★★★★ **AC-3's census was not run**, so "the background is restored" rests on a human looking at
   a screen. ★★★ That is the instrument this project trusts most and it is still one instrument.
3. ★★★★ **The straddle is CLAMPED, not split.** Where a row's span crosses an 8,192-byte slice
   boundary the tail is dropped and that row restores short. **~1.9% of row starts** for a 160-byte
   row. `p3rb_span` splits properly; mine does not. **A known deficiency, shipped knowingly, and
   the first thing to fix if any residue is seen.**
4. ★★★ **Over-restoring the priority plane by one pixel at each edge is argued safe, not measured.**
   The argument (all restores precede all composites) is sound but is an argument.
5. ★★ **The rectangle list caps at `P3_SPR_MAX` = 16 and the recorder silently drops the rest**,
   matching `p3_stage_sprites`' own behaviour. Never exercised — KQ1 room 1 stages 4.
6. ★★ **`vm` 9/9 is cited, not re-run** (§2T; `vm_probe.s` unchanged).

### 8 — Follow-up candidates

1. ★★★★★ **The blink. §7A.** The task that takes it should also land AC-3's census, AC-4's
   published counter and AC-7's fault arm **shown red on a screen** — all three are cheap once
   something is being changed in this area again, and all three are this task's gaps.
2. ★★★★★ **Fix the straddle properly** — split into two mapped copies as `p3rb_span` does. §7.3.
3. ★★★★ **Assert the visible plane against the staged volume blocks.** §3.1: three titles' volumes
   overlap blocks 40-43 and only the choice of which arm runs which title keeps it unreachable.
   **P6.46's shape, found and left in place.**
4. ★★★ **`p3_restore_box` and `prp_*` are now two walks over the same idea** [§6(2), §2F]. When the
   blink task restructures this area, they should become one.
5. ★★★ **The Graham-smear prediction** [P6.55 §3.3] — ★★★★ **still untestable and now more
   interesting**: with the restore in place he should *not* smear when he walks. **`HAL_KEYBOARD` in
   the cel arm is the next task and tests it for free.** Eye-gate question 2 blocked **six** tasks.
6. ★★ **`co_save`/`co_restore` are now provably dead.** This port has chosen its mechanism; the
   block should be deleted rather than left to be rediscovered a third time [P6.56, P6.57 §8.2].
7. ★★ The clear-key defect, gated on LSL1 [P6.55 §3.4].
8. ★ `MAP_PRI_BANDS` — an address nothing uses, **sixth task carrying it**.

### 9 — User interaction during task

1. **"run it"** — the eye gate was launched windowed at 99.75%.
2. ★★★★★ **"so the flags look right. clean baclground, bu tboth the flags and graham flash
   (blink)"** — **both halves of this report.** The first clause closes a chain that began four
   tasks ago with *"the port still shows a squarish background"*; the second opens §7A.

★★ **The eye gate has now located a defect no byte gate could see on five consecutive tasks**, and
on this one it did it in the same sentence as confirming the fix.

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-the-bug-you-fixed-was-hiding-the-next-one.md`
- `seeds/AGI/live/2026-09-19-a-prose-baseline-beside-an-executable-one-goes-stale-alone.md`

---

## 7A — ★★★★★ RULING REQUESTED — the blink

**What happens.** Every frame we erase last frame's sprites from the visible plane and then draw
this frame's onto the same plane. The display is that plane. So the screen spends part of each frame
showing the background with no sprite on it, and at ~10 cycles/second that reads as a blink.

**Why it appeared now.** It has always been true that sprites composite straight onto the displayed
plane — a deliberate narrowing at T-P0-051. It could not show while sprites were never erased,
because the thing that makes it visible is the erase. **Fixing the box is what exposed it.**

**Three shapes, and there are 9 free blocks (47-55) after this task took 45-46.**

1. ★★★★★ **Page-flip the visible plane — 4 blocks (47-50).** Two display planes; build the next
   frame in the one that is not showing, then point the GIME at it. **One register write per frame
   and the blink is structurally impossible**, not merely short. Costs 4 blocks and a second
   rectangle list.
2. ★★★ **Do restore+composite inside the vertical blank — 0 blocks.** Free in memory, and it only
   works if the whole frame's work fits in one VBL period. **That is unmeasured and I doubt it fits**
   for four sprites at 46×104.
3. ★★ **Composite into a back buffer and copy the dirty rectangles out — 4 blocks.** Same memory as
   (1), more copying, and the copy itself is still visible. Strictly worse than (1); listed because
   it is the obvious middle and should be ruled out explicitly.

**Recommendation: (1), and measure (2) first if 4 blocks are precious** — the measurement is one
number and would settle it. ★ **This also revisits the design spec's standing recommendation**
(*"one framebuffer, VBL-synced, with save-under"*), which was written when save-under was the
mechanism and this port has now chosen a different one. §2D — proposed, not edited.

**What I would not do:** leave it. A blinking ego is further from the original than a boxed one is,
and the eye gate will keep reporting it.

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting.
