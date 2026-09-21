## Form B Report — P6.73 — Two objects, two positions, one x: the port is RIGHT
**Class:** measurement.  wip.  **No fix — §4D's condition was not met, and the reason is that there
is nothing to fix.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-20 (HEAD a44036a, wip). git status clean at t0. **All eight arms byte-identical
throughout: no guest byte was changed by this task.**

### 1 — Summary

★★★★★ **The alligators are not misplaced and they are not frozen. Every element matches the
oracle, and P6.72's report — mine — was wrong on both counts.**

| P6.72 said | measured this task |
|---|---|
| *"the alligators are MISPLACED"* | ★★★★ **`position` lands correctly.** They are then MOVED by wander motion. |
| *"both frozen at `loop=0 cel=6`"* | ★★★★★ **The cel advances 0→7 continuously.** I read the end state of a finished run. |

★★★★★ **What actually happens**, measured per cycle: `position` writes (121,161) and (73,166);
both objects carry **`mo=1` (`kMotionWander`)**; `vm_motion_wander` runs every cycle; they walk in
a straight line at `ss=1` until `x + xSize > SCRIPT_WIDTH`, at which point
`update_position` clamps **`x = 160 − 13 = 147`** — the same value for both, because both are
`view=107` and share a cel width. ★★★ **That is §1.1's "two inputs, one output", and it is the
oracle's own clamp** [vm_objects.s:429-442 ← checks.cpp].

★★★★★ **And the re-steer is not missing — it is 255 cycles away.** `wander_count` is a `uint8`;
`0--` wraps to **255**; the oracle's retry loop then tests `255 < 6`, which is false, so it never
re-rolls — ScummVM's own source carries `// huh?` on that line [motion.cpp:152]. **Every run before
this one was 220 cycles.** At 480 cycles the counter expired and the direction re-picked, exactly
as it should.

### 2 — Files modified
- `harness/tools/p3b_run.lua` — `P3B_OBJTRACE`: the per-cycle object table (§4B/§4C).
- `harness/tools/p3b_show.ps1` — `vm_objtop` on the want-line; `[obj]` in the console allowlist.

**No guest source touched. No arm moved.**

### 3 — Reasoning

**§4A — the oracle** [tier: ScummVM, pin 9d9b9e93; believed ORIGINAL, §2.1]. **P6.72's AC-5,
discharged.**

1. **`cmdPosition`** writes **four** fields and clamps nothing:
   ```c
   op_cmd.cpp:1372   screenObj->xPos = screenObj->xPos_prev = xPos;
                     screenObj->yPos = screenObj->yPos_prev = yPos;
   ```
2. **What else moves an object between `position` and the draw:** `checkMotion` →
   `motionWander`/`motionFollowEgo`/`motionMoveObj` [motion.cpp:226-246], then `updatePosition`'s
   bounds clamp. ★★★★ **`checkCollision()`/`checkPriority()` — omitted at `vm_objects.s:401` — do
   NOT account for this**: for a v2 game their only relevant output would be `fDidntMove`, and see
   (3).
3. **The clamp:** `if x + xSize > SCRIPT_WIDTH: x = SCRIPT_WIDTH - xSize`. ★★★★ **147 is
   `160 − 13`**, and 13 is `view=107`'s `xSize`, measured.

**★★★★★ §4B/§4C — the per-cycle table, four slots.** `objtop=$A180` = `VM_OBJ + 12×32` = **slot 12,
inclusive** — ★★★ **§1.2's slot-number lead is dead, measured rather than argued.**

```
[obj] cycle 140 objtop=$A180
[11] x=127 y=161 xs=13 view=107 l=0 c=7 fl=0171 dir=3 ss=1 ct=1/1 mo=1 wander=250
[12] x= 79 y=160 xs=13 view=107 l=0 c=7 fl=0171 dir=2 ss=1 ct=1/1 mo=1 wander=250
... [11] pinned at x=147 from cycle 160; [12] walks +1x/-1y per cycle to x=147 by cycle 220
cycle 360  wander=30      cycle 400  wander=246   [12] dir 2 -> 0   <- the re-roll
```

★★★★★ **The cel column is the correction that matters:** `c` runs 0,1,2,3,4,5,6,7,0,… continuously
on both objects. **The cycler works.** P6.72 sampled a finished run, where the last value happened
to be 6, and called it frozen.

**★★★★★ `fDidntMove` is correctly absent.** The oracle sets it in exactly one place, under
`if (vm->getVersion() < 0x2000)` [op_cmd.cpp:1288; also cycle.cpp:113]. **Our pin is 0x2917**, so
for this corpus the `(flags & fDidntMove)` arm of `motionWander` is **dead code in the oracle too**.
★★★ Our `fl=0171` has no `$40` bit and that is right.

**§3(4) — every writer of `VMO_X`/`VMO_Y`:** `vmop_position`/`_f` [vm_cmds.s:352,364],
`vmop_reposition` [:486-502], `vmop_reposition_to` [:513,527], and `update_position`'s write-back
[vm_objects.s:487-489]. ★★ **The last is the one that moves these two**, and it is the oracle's.

### 4 — Verification (AC-by-AC)

- **AC-1 [citation · oracle] PASS** — §4A's three answers, quoted. **P6.72's AC-5 discharged.**
- **AC-2 [measurement] PASS** — the per-cycle table above, four slots, with `vm_objtop` and the
  flags. ★★ **Delivered as a per-cycle series rather than three named probe points** — strictly
  more than §4B asked for, and it subsumes the three points.
- **AC-3 [attribution] PASS** — ★★★★★ **The value never differs from the game's.** `position`
  lands; motion moves it; the clamp pins it. **There is no point at which a write is lost.**
- **AC-4 [measurement] PASS** — §4C's table, both alligators, per cycle. **P6.72's AC-3
  discharged**, and it overturns that report's inference.
- **AC-5 [state-comparable] N/A** — nothing was fixed.
- **AC-6 [byte-comparable] PASS** — **pic 45/45 · res 1,264/1,264 · cel 9,193/9,193 · comp 124/124**,
  fresh. ★★ **Nothing can have moved the `vm` gate: no guest source was touched and all eight arms
  are byte-identical.**
- **AC-7 [suite] PASS** — `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green.
- **AC-8 [fault injection] N/A** — no fix, so no arm to restore.
- **AC-9 [eye gate] NOT OFFERED** — ★★★ **the dispatch is explicit: if nothing was fixed, do not
  offer it.** There is no build to gate, which is not the same as "pending Jay".
- **AC-10 [manifest] N/A** — no arm moved; 8/8 verified unchanged.
- **AC-11 [tooling] PASS** — `hal_sync_check.py` OK against both siblings; `gen_vm_tables --check`
  OK; `reg_discipline.py` unchanged; `p3b_arms_check.ps1` 8/8; `fix_mojibake --check` clean.
- **AC-12** Candidate captured (§10).

### 5 — Verdict-time evidence (v0.7 §11)

```
25.1  ★ all 8 arms byte-identical to the recorded baseline (SHA256)
      per-picture: 45 PASS, 0 FAIL (of 45)
      resources byte-identical to tools/volread/: 1264 / 1264 (100.00%)
      cels byte-identical to the oracle: 9193 / 9193 (100.00%)
      ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
      ★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      [hal-sync] OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
      CHECK OK: src/harness/vm_tables.s matches optable.py

      [obj] cycle 140 objtop=$A180
      [11] x=127 y=161 xs=13 view=107 l=0 c=7 dir=3 ss=1 mo=1 wander=250
      [12] x= 79 y=160 xs=13 view=107 l=0 c=7 dir=2 ss=1 mo=1 wander=250
      [obj] cycle 400  [12] dir 2 -> 0, wander 30 -> 246   (the re-roll)
25.2  N/A -- no artifact changed.
25.3  NOT OFFERED -- nothing was fixed; there is no build to gate [AC-9].
```

### 6 — Reactive deviations and route accounting

**None.** No guest code was written. ★★★★ **§4D's condition — "fix only if §4B names ONE defect" —
was not met because §4B named ZERO.** §6's fifth trigger anticipated this: *"the x placement turns
out to be the game's own — then there is nothing to fix and saying so is the answer."*

**ROUTE ACCOUNTING.** I proposed nothing beyond the dispatch. §4B asked for three named probe
points and I delivered a per-cycle series instead; **that is more, not less, and it is stated in
AC-2 rather than left for a reader to notice.**

### 7 — Uncertainty flags

1. ★★★★★ **Two claims in P6.72's report were wrong and are corrected here** — *"the alligators are
   MISPLACED"* and *"both frozen at loop=0 cel=6"*. ★★★ **Both came from reading P6.71a's
   end-of-run sprite dump as if it described steady state.** A final snapshot cannot distinguish
   static from periodic, and cel 6 was simply where a 220-cycle run happened to stop.
2. ★★★★★ **The original question is NOT answered: Jay sees swimming alligators in ScummVM and none
   in the port.** Everything measured matches the oracle, so the difference must lie somewhere this
   task did not look. **Candidates, none tested:** the RNG sequence (different `rnd(8)` draws give
   different wander directions from the same code); the objects being drawn but unrecognisable
   pinned at the right edge, overlapping, one of them stationary; or a release difference [§2Q,
   still unpinned].
3. ★★★ **`wander_count` reaching 255 via `uint8` wrap is faithful but may still be wrong about the
   ORIGINAL interpreter** [§2.1]. ScummVM's own `// huh?` suggests its authors were unsure. **We
   reproduce ScummVM; whether Sierra's interpreter did this is not established.**
4. ★★ **Only KQ1 room 1 was examined.** Two objects, one view, one motion type.

### 8 — Follow-up candidates

1. ★★★★★ **Why does the oracle show swimming alligators and the port not?** [§7.2] **Everything in
   the port matches; the next place to look is the RNG sequence** — compare `rnd(8)` draws between
   our VM and the reference over the same cycles.
2. ★★★★ **Watch the port for 500+ cycles and look at it** — the re-steer happens at ~255 cycles and
   no eye gate has ever run that long. ★★ **It may already be right and simply never observed.**
3. ★★★ **Pin the game release** [§2Q] — carried from P6.69, P6.70, P6.71, P6.72. Five reports.
4. ★★ `set.key` · controller bindings · the flags' blink · the picture leaving the logic arena ·
   `configure.screen`'s render offset · `MAP_PRI_BANDS` (nineteenth task).

### 9 — Doc-edit deltas applied
- **None to guest source** — there was nothing to correct in it. ★★★ **`vm_objects.s:401`'s
  omission note was checked against §4A(2) and is accurate as written**: `checkCollision`/
  `checkPriority` would not have moved these objects, because their only relevant effect for v2 is
  `fDidntMove`, which the oracle sets only below version 0x2000.
- **Design-spec text: none proposed** [§2D].

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-20-the-last-frame-of-a-run-is-not-the-steady-state.md`

### 11 — Commit
`a9ec29d` — 3 files changed, 206 insertions(+), 2 deletions(-).
Pushed to origin/wip (`a44036a..a9ec29d`).
