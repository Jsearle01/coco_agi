## Form B Report — T-P0-111 / P6.57 — The priority plane has no shadow, and that is the cheap half
**Class:** measurement.  wip.  **No `src/` change.**

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 20:36:22 (HEAD 98fbe76, wip). git status clean except `?? coco_agi.code-workspace`.

★★ **AC-6 met and verified first, not last:** `git diff --stat 221e664..HEAD -- src/` is **empty**,
and `git diff --stat 98fbe76..HEAD` is empty. Nothing under `src/` has moved since P6.54.

### 1 — Summary

★★★★★ **§4A's answer: the priority plane has NO shadow.** `ph_blk_pri` is written **once** in the
entire tree — `clr ph_blk_pri`, `p3b_probe.s:473` — and is never redirected, while `ph_blk_fb` is
redirected seven times. One copy of priority, at blocks 0-1, written by the render and then mutated
by every sprite that draws over it.

★★★★★ **And that turns out to be the good news, because the fix is a BLOCK.** The visual shadow
already exists and costs 4 blocks; a priority shadow is **2 blocks**, by the same mechanism, already
proven twice in this probe.

★★★★★ **The headline: restore-from-shadow is not merely cheaper in memory than a banked save-under,
it is HALF THE PER-FRAME WORK.** A save-under copies a sprite's rectangle **twice** per frame — out
on save, back on restore — across two planes: **4 × w × h bytes per sprite per frame**. A shadow is
permanent, so nothing is ever saved: **2 × w × h**, restore only. ★★★★ **And the per-sprite store
falls to ZERO, which deletes the unmeasured concurrent-sum bound from the problem entirely rather
than measuring it.**

★★★ **The one real constraint found: text is not in the shadow** (§3.3). `txt_blit` writes the
visible plane directly, so restoring a rectangle from the shadow erases any glyph inside it.

**Ranked recommendation in §7, addressed to Jay. No decision taken.**

### 2 — Files modified

**None.** Scratchpad only. The §9 doc deltas are surfaced as text and **deliberately not landed** —
see §6.

### 3 — Reasoning

#### 3.1 §3(2) — the plane inventory, and which planes are double-buffered

From the probe's own block-allocation comments [`p3b_probe.s:472`, `486-492`, `2063-2072`]:

| blocks | holds | size | shadowed? |
|---|---|---|---|
| **0-1** | **priority plane** | 13,440 B of 16,384 (`-DPRI_PACKED`) | ★★★★★ **NO** |
| **2-5** | **shadow framebuffer** — *"the picture renders here, unseen"* | 26,880 B of 32,768 | — (it IS the shadow) |
| 6 | vocabulary, windowed builds | 8,192 | n/a |
| **7** | ★ **free** — *"blocks 6 and 7 are free and the dictionary takes 6"* | 8,192 | n/a |
| 8-38 | host-staged volumes (31 blocks) | — | n/a |
| **40-43** | **visible plane** — *"what the display shows and sprites composite onto"* | 26,880 B of 32,768 | yes, by 2-5 |
| $38-$3F (56-63) | the CPU's own boot window | — | n/a |

★★ **Blocks 39 and 44-55 are named by no allocation comment.** They are *probably* free — the
probe's allocator range was 0-7 (*"block 8 up, and `$38-$3F` are the CPU window, so 0-7 are
free"*) and the visible plane took 40-43 as *"four blocks nobody was using"* — ★ **but I did not
verify that by reading the MMU state, and do not claim it.** §7.3.

★★★ **The asymmetry is the finding.** The visual plane is double-buffered because a *person* asked
for it — Jay watched the render happen and ruled the draw must not be visible [T-P0-051]. The
priority plane was never double-buffered because **nobody can see it**, and the reason it now needs
to be is invisible for the same reason.

#### 3.2 §4A — what is under a sprite in the priority plane, and where it could come from

`composite.s:10-16` transcribes the oracle's three branches:

```
if (screenPriority <= 2)        putPixel(VISUAL only, ...)    ★ priority plane UNTOUCHED
else if (screenPriority <= viewPriority)  putPixel(ALL, ..., viewPriority)  ★ BOTH planes
```

★★★ **Branch two stamps `viewPriority` into the priority plane, so compositing mutates its own
input** [`composite.s:24-26`]. What *should* be under the sprite is the picture's own priority
data — which exists exactly once, was written at room entry, and is overwritten in place.

**Three possible sources, and only one is cheap:**

1. ★★★★★ **A priority shadow — 2 blocks.** The render writes priority once per room, exactly as it
   writes visual once per room. `ph_blk_fb` is already pointed at a shadow for the render and blitted
   by `p3_present`; **`ph_blk_pri` would do the identical thing.** The mechanism is written, gated
   and proven.
2. **Re-render the picture's priority** per restore. Rejected on cost without measurement: a room's
   priority render is the picture opcode stream, per frame instead of per room.
3. **A per-sprite priority-only store** — half of 9,568 B, and re-opens the concurrent-sum bound and
   the flat-siting problem P6.56 found impossible.

#### 3.3 §3(3) — everything that writes the VISIBLE plane, and what the shadow cannot reproduce

| writer | evidence | in the shadow? |
|---|---|---|
| `p3_present` | `p3b_probe.s:1370` — shadow → visible, once per room | ★ it **is** the shadow copy |
| `p3_restore_box` | `:1389` — *"re-rendering ITS RECTANGLE, shadow -> visible"* | ★ same source |
| `co_put_visual` | `composite.s:414` — the sprites | **the thing being restored** |
| `p3_clear_planes` | the per-room clear | reproducible |
| `add.to.pic` | `vm_tables.s:260-261` — **`vm_op_modelled`** | ★★ **writes nothing today** |
| ★★★★★ **`txt_blit`** | `text.s:1638`, `:1558` — *"the 8x8 glyph into the 320x200x16 framebuffer"* | ★★★★★ **NO** |

★★★★ **`text.s:1011-1012` states the mapping in the engine's own words:** *"Our game screen is the
SHADOW plane and our display screen is the VISIBLE plane."* **Glyphs go to the display screen. The
shadow never holds them.**

★★★ **So §6's second trigger is NOT fired — shape 2 is not killed — but it acquires a constraint:**
restoring a rectangle from the shadow erases any text inside that rectangle.

**How much that matters, stated carefully rather than alarmingly:**

- **The status line and command line** sit outside the 160×168 picture area, where sprites do not
  go. ★ **No overlap in normal play** — though this is an argument from AGI's screen layout, not a
  measurement, and a sprite at the horizon is the case to check.
- ★★★ **The message box DOES overlap the picture area** — and this interaction **already exists
  today**: `p3_restore_box` closes the box by copying shadow → visible over its rectangle, which
  already erases any sprite pixels there. **Shape 2 does not create this; it makes the ordering
  explicit.** The box is *blocking*, so sprites are not animating while it is up.
- ★★★★ **`add.to.pic` is the one to get right later, and shape 2 makes it EASIER, not harder.** In
  AGI `add.to.pic` draws permanently into the picture. **Written into the shadow, it is preserved by
  every restore for free.** Written into the visible plane it would be erased by the first restore.
  ★★ **That is a design constraint this task can hand forward before the opcode is implemented**,
  which is the cheapest moment to have it.

#### 3.4 §4C — the concurrent-sum bound, and why the recommended shape deletes it

**It was not measured. Two statements about that, and the second matters more.**

★★ **What it would take.** A per-frame counter of Σ(`vc_w` × `vc_h`) over sprites actually
composited, maxed across a run. `p3b` already maintains six 32-bit per-frame counters in the
compositor (`co_tested`, `co_written`, …) and publishes them, **so the hook exists and the cost is
one more counter plus a max.**

★★★★ **Why it would still not be the bound.** The scenarios `p3b` can run are Kingquest1 room 1 and
a handful of staged rooms. A maximum taken over those is **a maximum over those** — which is exactly
how 4,152 was produced and exactly why P6.56 found it unsafe [L-85, L-86]. ★★★ **Producing a third
sampled number and calling it a bound would repeat the error this task inherited.**

★★★★★ **And under shapes 2+3 the question is moot: there is no per-sprite store to size.** The
shadow is a whole plane whose size is a property of the screen, not of the sprites on it. ★★★ **The
strongest argument for the recommended shape is that it deletes an unanswerable question rather than
answering it.**

★ **The bound is required only if shape 1 is chosen**, and then it must be measured before siting,
not after.

#### 3.5 §4B — the shapes, priced

**Per-frame cost is stated as bytes copied per sprite per frame**, with `A` = `vc_w` × `vc_h`.

| | shape 1 — banked save-under | shape 2 — shadow restore, visual | shape 3 — + priority shadow | 2+3 combined |
|---|---|---|---|---|
| **per-sprite store** | ★★★ **≥ 9,568 B floor, true bound unknown** | **0** | **0** | ★★★★★ **0** |
| **blocks** | ≥ 2 (banked; must be mapped during composite) | **0 new** | **2** | ★★★★ **2** |
| **bytes copied / sprite / frame** | ★★★ **4A** (save 2A + restore 2A) | 1A | 1A | ★★★★★ **2A** |
| **MMU slot pressure during composite** | ★★ store must be mapped **alongside both planes** | shadow + visible | + priority pair | 2 extra map calls per row-straddle |
| **reuses** | `co_save`/`co_restore` — ★★★★★ **never assembled** | ★★★★★ `p3_restore_box`'s slice-aware straddle walk, debugged P6.33 | `ph_blk_fb`/`p3_present`'s redirect+blit, proven twice | both |
| **must first repair** | ★★★★ flat pointers → `plane_vis`/`plane_pri`; `PRI_W` → `PRI_STRIDE`; define `CP_SAVEB`/`CP_SAVEPK` | — | — | — |
| **new code** | rot repair + siting + banking | a priority-plane twin of `p3rb_span` | redirect + present for priority | one walk, two planes |
| **risks** | ★★★★ code that has never assembled [§2W]; unmeasured bound | text erasure in-rect (§3.3) | 2 blocks; present cost per room | as shape 2 |
| **forecloses** | a block pair + a slot, permanently | nothing | 2 blocks | 2 blocks |

★★★★★ **Shape 1 costs twice the per-frame copying of 2+3, needs a store whose size nobody can
state, revives a routine that has never assembled, and consumes comparable blocks anyway.**

★★★ **The saving is structural, not clever: a save-under must save because its source is destroyed;
a shadow never is.**

★★ **What 2+3 does NOT do.** It restores a *rectangle*, so it repaints the whole sprite bounding box
every frame including its transparent margin, where a save-under restores exactly what it saved —
the same bytes. ★ **For the cel sizes measured (peak 46×104) that difference is inside the 2A vs 4A
gap and does not change the ranking**, but it is the honest counterpoint.

#### 3.6 §4D — what gates each shape

★★★★ **`comp` gates none of them.** It composites single frames onto a clean plane and cannot
express a frame-to-frame relationship [P6.55, P6.56 §4C]. **Stated as a cost, not a footnote:**

| shape | gated by | 
|---|---|
| 1 | ★★★★ **nothing.** `co_save`/`co_restore` are on no gated path. Needs the two-frame arm — which needs a **sixth oracle patch** [P6.56 §4C] |
| 2 | ★★★ **the walk is already gated** — `p3_restore_box` is exercised by `p3b_box`. ★★ The *sprite-restore usage* of it is not |
| 3 | ★★★ **the mechanism is already gated** — render-to-shadow + present is what `pic` 45/45 and `p3b` exercise for visual. ★★ The *priority* instance would be new |

★★★★★ **This is a real argument for 2+3 beyond cost: both shapes reuse mechanisms with existing
gates, while shape 1 revives a routine with none and would need a new oracle patch to get one.**

★★ **None of the three is fully gated**, and the two-frame arm remains the only thing that would
close the class for any of them.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — MET.** §3.1/§3.2. **No priority shadow**; `ph_blk_pri` written once,
  `p3b_probe.s:473`, never redirected. Three candidate sources priced.
- **AC-2 [measurement] — MET.** §3.3's table. ★ The one writer the shadow cannot reproduce is
  `txt_blit`.
- **AC-3 [measurement] — MET.** §3.5, in blocks and bytes and per-frame copy cost.
- **AC-4 [measurement] — MET AS "WHAT IS NEEDED", NOT AS A NUMBER.** §3.4. ★★ The dispatch
  explicitly prefers this to *"a third number that measures something else"*, and that is the
  judgement made.
- **AC-5 [measurement] — MET.** §3.6.
- **AC-6 [byte-comparable] — MET.** §0, verified at the top of the task.
- **AC-7 [suite] — DISCHARGED BY §2T CITATION.** Inputs verified unmoved (§5); figures carried from
  P6.54.
- **AC-8 [ruling requested] — MET.** §7A.
- **AC-9 — MET.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output:** ★★ **No build, because nothing was changed** — which is this task's
AC-6, not an omission.

```
$ git -C coco_agi diff --stat 221e664..HEAD -- src/
(empty)
$ git -C coco_agi diff --stat 98fbe76..HEAD
(empty)
$ git -C coco_agi rev-parse --short HEAD
98fbe76
$ lwasm --version
lwasm from lwtools 4.24
```

**Baseline cited from `reports/20260919-191000-p6-54-the-compositor-doubles-the-nibble.md`:**
pic 45/45, res 1,264/1,264, cel 9,193/9,193, comp 124/124, vm 9/9; `comp_probe.bin` 967 B
`39F5D105`. §2T.1's five rebuild triggers: none fired — HEAD has moved only by report commits.

**25.2 bundled-artifact grep:** N/A — no artifact built.

**25.3 operator-runtime-smoke:** ★★ **N/A for a measurement task that changed nothing.** The screen
is unchanged from P6.55's. ★ Not recorded as "pending Jay": there is nothing pending.

### 6 — Reactive deviations and route accounting

★★★ **No §6 trigger fired.** In particular the second — *"§3(3) finds something writing the visible
plane that the shadow cannot reproduce"* — **came close and did not fire.** `txt_blit` is such a
writer (§3.3), but it does not kill shape 2: the overlap it creates is confined to the message box,
already exists today in `p3_restore_box`, and is an ordering constraint rather than a contradiction.
★★ **Reported plainly as the dispatch asks, rather than worked around.**

★★★★ **A CONFLICT INSIDE THE DISPATCH, surfaced rather than resolved** [§8's stop-and-surface rule].
**§9's first delta asks for a note in `composite.s`'s header. AC-6 requires `git diff` under `src/`
to be EMPTY.** Those cannot both be satisfied. **AC-6 is binary and testable, so it won**, and
**nothing in §9 was landed** — including `gates.manifest`, which is outside `src/` and *would* have
been permissible, because landing one third of a doc delta is worse than landing none and saying so.
★★ Full proposed text is in §8.5 for whichever task takes it.

**Route accounting.** ★★★ **I proposed no route and implemented nothing.** §7A is a ranked
recommendation, explicitly not a decision, as §4B requires.

★ **One reading in the dispatch confirmed rather than corrected:** §1.1's *"the port may already own
the background it needs"* is **right for the visual plane** and §1.2's own caveat is **right about
priority**. Both halves of the Orchestrator's model survived contact.

### 7 — Uncertainty flags

1. ★★★★★ **P6.55's finding is still unproven**, unchanged from P6.56 §7.1. Nothing here tests it.
   Every shape priced assumes absent save-under is the cause of Jay's box.
2. ★★★★ **The concurrent-sum bound remains unmeasured** and is unmeasurable *as a bound* from the
   scenarios that exist (§3.4).
3. ★★★ **Blocks 39 and 44-55 are asserted free by inference, not by measurement** (§3.1). ★★ A shape
   needing them must verify first. **The 2 blocks shape 3 needs are NOT among them** — block 7 is
   documented free and one more is needed.
4. ★★★ **The per-frame cost model is arithmetic, not measurement.** 4A vs 2A counts bytes copied; it
   does not count MMU remaps, which differ between the shapes and which this project has measured to
   matter. ★★ §8 requires me to label my own arithmetic unverified, and I do.
5. ★★ **"No overlap between sprites and the status/command lines" is an argument from AGI's screen
   layout, not a measurement** (§3.3).
6. ★ **`add.to.pic` is modelled today.** Its interaction with every shape is predicted, not observed.

### 8 — Follow-up candidates

1. ★★★★★ **Take Jay's ruling on the shape** (§7A), then build it. ★★★ **The build task must still
   fix P6.56's rot if shape 1 is chosen, and must NOT if it is not** — shapes 2+3 leave
   `co_save`/`co_restore` dead, which is the honest resolution of a routine that has never assembled.
2. ★★★★★ **If 2+3: delete or gut the `ifdef CP_SAVE` block rather than leaving it.** ★★★ It is the
   subject of P6.56's finding — code behind a define nothing sets, rotting silently. **Leaving it in
   place after choosing a different shape guarantees a third task rediscovers it.**
3. ★★★★ **Write the `add.to.pic` constraint down now** (§3.3): it must draw into the SHADOW. ★★★
   Cheapest at this moment, before the opcode exists.
4. ★★★★ **The `COMP_PLANE_SAFE` grep-guard** [P6.56 §3.3, dispatch §2]. ★★ Unchanged and still
   unbuilt; a priority-plane walk is a second place the flat-pointer form could appear.
5. ★★★ **The two-frame comp arm** — still the only thing that would gate any shape (§3.6), still
   needs a sixth oracle patch.
6. ★★★ **The Graham-smear prediction** [P6.56 §8.7], carried: when `HAL_KEYBOARD` reaches the cel arm
   and Graham walks, he should leave a trail. **Fifth task that eye-gate question 2 has been blocked.**
7. ★★ The clear-key defect, gated on LSL1 [P6.55 §3.4].
8. ★ `MAP_PRI_BANDS` — an address nothing uses, **fifth task carrying it**.

#### 8.5 §9's proposed text, not landed (see §6)

- **`composite.s` header:** *"★★★★★ THE `ifdef CP_SAVE` BLOCK BELOW HAS NEVER BEEN ASSEMBLED.
  `CP_SAVE` is defined nowhere in the tree and `CP_SAVEB`/`CP_SAVEPK` are undefined, so it cannot
  assemble as it stands. It has also rotted: lines 714/716 use `co_rowvis`/`co_rowpri` as direct
  pointers where the four compiled sites go through `plane_vis`/`plane_pri`, and 755/758 advance
  both planes by `PRI_W` where priority's stride is `PRI_STRIDE`. Do not enable it without repairing
  both [P6.56]."*
- **`gates.manifest`:** an `ifdef`-excluded subsystem gets a note saying **what its absence looks
  like**, not only that it is absent — e.g. against `comp`: *"`CP_SAVE` undefined: no save-under, so
  an animating sprite accumulates the union of its cels as a filled rectangle [P6.55]."*
- **`memmap.inc:310`:** `MAP_PRI_BANDS` remains an address nothing uses.
- **design spec §3.6 — PROPOSED ONLY** [§2D]: the backing-store bound is stated as *"peak total cel
  area on screen"*; **a shadow-based restore has no backing store at all**, and §3.6 should say which
  shape the bound applies to.

### 9 — User interaction during task

**None.** The dispatch ran to completion without consultation. ★★ **§7A is a ruling request, which is
the interaction this task is for.**

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-the-cheap-fix-deletes-the-question-instead-of-answering-it.md`
- `seeds/AGI/live/2026-09-19-what-nobody-can-see-does-not-get-double-buffered.md`

---

## 7A — ★★★★★ RULING REQUESTED (AC-8) — addressed to Jay

**Your box has a fix with three shapes. Here is what each costs and what it closes off.**

**Recommended: shapes 2 + 3 together — restore both planes from shadows.**

- **Costs 2 blocks** (16 KB of address space) for a priority shadow, beside the 4 the visual shadow
  already uses.
- **Needs no per-sprite buffer at all** — which matters because **nobody can currently state how big
  that buffer would have to be**, and the two figures previously published for it are both wrong in
  different directions.
- **Half the per-frame copying** of a save-under, because a shadow is never destroyed and so never
  needs saving.
- **Reuses two mechanisms that already work and are already gated:** the slice-aware rectangle copy
  that closes your message boxes, and the render-to-shadow-then-blit that stopped you watching
  pictures draw.
- **Leaves `co_save`/`co_restore` dead**, which is the honest end for a routine that has never once
  been assembled.

**The alternative — a banked save-under — costs comparable blocks, twice the per-frame work, a
buffer of unknown size, and reviving code that has rotted in three specific ways.** I can see no
argument for it that survives the measurements in §3.5.

**What you would be giving up by taking the recommendation:** 2 blocks, permanently. And one
behaviour worth knowing about before you choose — **text is not kept in the shadow**, so restoring a
sprite's rectangle repaints the picture there and would wipe any text inside it. In practice that
means the message box, and that interaction already exists today. ★ **If you ever want text to
survive under a sprite, this is the shape that makes it harder, and now is when to say so.**

**One thing this does not do, and I want to be straight about it:** none of this proves absent
save-under is what you are seeing. **It remains the best explanation and it is still unproven** — the
with/without experiment has never been built, and the first honest test is still you looking at the
flags after a fix lands.

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting. **No source commit: nothing was changed.**
