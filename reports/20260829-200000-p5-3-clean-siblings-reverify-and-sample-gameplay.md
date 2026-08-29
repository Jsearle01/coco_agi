## Form B Report — P5.3, clean the siblings, re-verify, and sample real gameplay
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-29 (HEAD `bc972cb`, wip). git status clean at receipt.

---

### §5 — Pre-dispatch grep (C-13), verbatim

```
coco_agi         wip  bc972cb   clean

POP3_port        wip  430a91c   DIRTY:  M src/hal/coco3-dsk/sys.s
karateka_coco3   wip  78c8c27   DIRTY:  M src/hal/coco3-dsk/sys.s
                                        M harness/smoke/last-run.log
  ★ the twice-reported hazard, confirmed present before §2 acted on it

hal_sync_check.py  (BEFORE)
  coco_agi        OK -- aligned with POP3_port, karateka_coco3   (11 files)
  POP3_port       OK -- aligned with karateka_coco3, coco_agi    (11 files)
  karateka_coco3  OK -- aligned with POP3_port, coco_agi         (11 files)

THE FOUR GATES
  renderer     45/45     ★ re-run this task -- AC-2, PASS
  resources 1264/1264    [P5.2 §5, inputs unchanged]
  VM           9 titles  [P5.2 §5, inputs unchanged]
  cels      6782/6782    [P5.2 AC-2, inputs unchanged]

clock          1.789390 MHz [AD-73], fast mode asserted by the HAL
oracle console CONFIRMED in engines/agi/console.cpp:
                 Cmd_Room   argc==2 -> _vm->newRoom(strtoul(argv[1]))
                            argc==1 -> prints _vm->getVar(0)
                 Cmd_SetVar "Usage: %s <varnum> <value>"
                 Cmd_SetObj "Usage: %s <objnum> <location>"
```

★ **No contradiction.** The dirty siblings are the task's own §2, not a conflict.

---

### 1 — Summary

**§2 and §3 landed first, as ordered.** The shared HAL change is **committed and pushed in all
three repos**, both siblings rebuilt **byte-identical** to their baselines, and the renderer gate
re-runs **45/45**. The twice-reported hazard is closed.

★★★ **The room jump works, and it needed no target code — two host writes.** 12 rooms across 3
titles reached. **Gameplay frames now contain the ego**, which the attract-mode corpus never
composited: **1,115 ego frames** against 0 of 1,680 before.

★★★ **The control-line branch FIRES on gameplay frames** — 0 of 1,680 in attract mode, and
measured here for the first time. **The composite is byte-identical on gameplay frames anyway**
(AC-6), so the transcription of `checkControlPixel` is correct.

★★★★ **AC-7 IS NOT REPORTED AS A NUMBER, AND THE REASON IS L-56 AGAIN.** My free-run timing
harness inflates the work by ~2,049× on frames where the control branch fires. **The composite
is not slow — my measurement of it is wrong**, and I caught it by measuring the same frame two
ways. Detail in §4 AC-7; **T-P0-028's attract-mode figures are unaffected and stated why.**

---

### 2 — Files modified

**Siblings** (the shared HAL only — no other sibling content touched, §2G):
- `POP3_port` `104b197` — `src/hal/coco3-dsk/sys.s`
- `karateka_coco3` `29f8f0a` — `src/hal/coco3-dsk/sys.s`

**coco_agi:**
- `oracle/patches/0008-oracle-room-jump.patch` — ★ the gated room jump
- `harness/tools/oracle_dump.sh` — `ROOM` / `ROOM_AFTER` / `EGO_X` / `EGO_Y`
- `harness/tools/vm_sweep.lua` — ★ C1's host-side room jump (`VM_ROOM`)
- `harness/tools/comp_sweep.lua` — `COMP_COUNT`, MODE-2 counter readback
- `harness/tools/comp_stage.py` — `--frames-dir` used against gameplay captures

---

### 3 — Reasoning

★★★ **C1 — the room jump on OUR VM is two host writes, and that is a property of the design.**
AGI routes a room change through **`VAR_CURRENT_ROOM` (var 0)** and **`FLAG_NEW_ROOM_EXEC`
(flag 5)**, and **logic.0 already tests flag 5 every cycle**. Our VM keeps 256 variables and 256
flags flat and byte-indexed at `$4000`/`$4100`, so from MAME Lua:

```
prog:write_u8(VM_VARS + 0, room)            -- var 0 = the room
prog:write_u8(VM_FLAGS + 0, b | 0x20)       -- flag 5, byte 0 bit 5
```

**No opcode, no probe mode, no 6809 instruction was added.** ★ The game's own logic.0 dispatches
the room on its next pass — which is why KQ3's ego lands at a *different* position in each room
(94/131, 84/148, 43/135, 110/149): the room's own setup ran.

★★ **On the ORACLE the jump is patch 0008**, calling the engine's own `newRoom()` — the same
entry `Cmd_Room` uses. It resets the screen-object table, unloads resources, sets
playerControl/horizon, writes the room vars and loads the room's LOGIC. ★ **A jumped run
perturbs the engine and its `vmstate.txt` is not a valid baseline** — patch 0006's rule.

★★★ **§2H check 3 — grep before citing, applied to MY OWN measurement.** T-P0-028 reported
compositing at 53%/106% of a second. Those figures came from `cp_do_free`, the same free-run path
that is broken here. **They are not withdrawn, and the reason is checkable:** SpaceQuest-1's
attract samples produced `tested = 115,000` for a 575-pixel cel over 200 reps — **exactly
575 × 200**, a clean multiple. The path is correct when the control branch does not fire, and
attract mode had **zero** control hits. ★ **So the old numbers stand and the new ones cannot be
taken yet** — a distinction I would rather state than average over.

★ **§2S — refs.** Sibling state read from local working trees, 2026-08-29. POP `430a91c` →
`104b197`, Karateka `78c8c27` → `29f8f0a`, both pushed to their `origin/wip`.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★★★ **PASS — the hazard is closed.** Both siblings committed
  (§2), `git status` clean of tracked changes, both rebuilt **byte-identical to P4.4 §5**:

  | | recorded | now | |
  |---|---|---|---|
  | POP `build/loader.bin` | `56bf6740440c4e0a` | `56bf6740440c4e0a` | ✓ |
  | POP `build/probe.dmk` | `ec6daccb0b78a9d5` | `ec6daccb0b78a9d5` | ✓ |
  | Karateka `karateka.bin` | `9cd20dc537415e80` | `9cd20dc537415e80` | ✓ |
  | Karateka `gfxmode3.bin` | `d447c768bd5e6b80` | `d447c768bd5e6b80` | ✓ |
  | Karateka `sprite_engine_sandbox.bin` | `543ad8f014bd84d6` | `543ad8f014bd84d6` | ✓ |

  POP's own image check: **VERDICT PASS — every file on the image matches its artefact.**
  `hal_sync_check.py` **OK in all three** after the commits. ★ **Trigger 1 did not fire.**
  ★ **One tracked file left dirty in Karateka, deliberately:** `harness/smoke/last-run.log`
  differs only in its timestamp line, is a regenerated smoke artifact, is **not** the shared
  change, and is not mine to commit under §2G. **Stated rather than tidied away.**
  ★ §2T: the trees were **dirty**, so §2T's citation precondition did not hold and a **real
  rebuild** was done, as the dispatch required.

- **AC-2 [class: byte-comparable]** ★★ **PASS — 45/45**, both planes, per-picture:
  `per-picture: 45 PASS, 0 FAIL, 0 with no output (of 45)`, games covered 3
  (Kingquest1=16, Kingquest2=15, Kingquest3=14). **P5.2 §7.2 is closed.** ★ Trigger 2 did not
  fire — nothing drifted under four subsystems sharing a tree.

- **AC-3 [class: byte-comparable]** `reg_discipline.py`: **0** accesses in `src/engine/**`.
  Siblings at their recorded figures (AC-1).

- **AC-4 [class: state-comparable]** ★★★ **PASS — 12 rooms across 3 titles, every one reached.**
  KQ2 rooms 1–4, KQ3 1–4, larry1 1–4: `var0` equals the requested room in all twelve, `icguard=1`,
  **no halts**. ★ **Mechanism: two host writes, no target code** (§3). ★★ KQ3's ego position
  differs per room, which is the proof the room's own logic ran rather than the var merely
  changing.

- **AC-5 [class: state-comparable]** ★★ **PARTIAL — the sample is rich on ONE title, absent on
  two. §8 trigger 5 fired.**

  | room | frames | **with EGO** | ego cel median |
  |---|---|---|---|
  | Kingquest2 r1 | 402 | **325** | 192 px |
  | Kingquest2 r2 | 299 | **223** | 192 px |
  | Kingquest2 r3 | 282 | **204** | 192 px |
  | Kingquest2 r4 | 208 | **132** | 192 px |
  | Kingquest2 r2 (2nd capture) | 307 | **231** | 192 px |
  | Kingquest3 r2 | 582 | 9 | 238 px |
  | **TOTAL** | **2,080** | **1,124** | |

  ★★★ **1,124 ego frames against 0 of 1,680 in attract mode** — the correction works.
  ★ **The ego composites at a 192 px median against the attract-mode 120 px**, 1.6× larger.
  ★★★ **BUT: Kingquest3 yields 9 and larry1 yields ZERO**, at rooms 1–4 and again at 8, 14 and
  20. **The room jump alone does not reach their gameplay** — they need state a jump does not
  set. **Trigger 5: reported, not worked around.** `setvar`/`setflag` on an "intro complete" flag
  is the obvious next lever and is untried.

- **AC-6 [class: byte-comparable]** ★★★ **PASS — 80 gameplay frames, both planes, 0 divergent.**
  Per room: **KQ2-r3 40/40**, **KQ2-r2 20/20**, **KQ2-r4 20/20**. ★★★ **This is the gate
  T-P0-028's AC-3 could not run**, and it now includes frames that exercise **the control-line
  branch and the priority test together** — paths the attract corpus never reached.
  ★ **Trigger 3 did not fire**: nothing diverged on gameplay where attract passed.
  ★★ Below the dispatch's ≥100 across ≥3 titles because AC-5's sample is one title (above).

- **AC-7 [class: state-comparable]** ★★★★ **NOT REPORTED AS A NUMBER. The harness is wrong, not
  the composite, and I would rather say so than publish it.**

  Measuring one frame two ways:

  | path | tested pixels | time for the frame |
  |---|---|---|
  | **MODE 2** — one composite per handshake | **916** = 340+384+192, **exactly the three cels** | 0.017–0.05 s |
  | **MODE 3** — `cp_do_free`, the timing path | **696,660** for the 340-pixel cel alone | **59–97 s** |

  ★★★ **2,049× the work, for byte-identical output.** The no-count build shows the same, so it
  is **not** the counters. MODE 2's counters are exact and its control figures sane (37 hits,
  206 steps). **`cp_do_free` is the defect**, and it misbehaves only when the control branch
  fires — which is why attract mode never exposed it.
  ★★ **T-P0-028's 53%/106% are NOT withdrawn**: their samples produced clean multiples
  (`115,000 = 575 × 200`) and had zero control hits, so that path was behaving. See §3.
  ★ **What AD-71's four missing terms look like now:** the **control branch is IN** the corpus at
  last (AC-8) but **not yet in a cost figure**; **MMU remaps** and **save-under restore** remain
  outside (AC-9). **The 106% floor is unchanged, and no new number replaces it.**

- **AC-8 [class: state-comparable]** ★★★ **YES — THE CONTROL BRANCH FIRES, for the first time.**
  0 of 1,680 attract frames; on gameplay:

  | staged set | priority rejections | **control hits** | scan steps |
  |---|---|---|---|
  | KQ2 r1 (40 frames) | 0 | **1,105** | 1,105 (1.0 per hit) |
  | KQ2 r3 (40 frames) | **442** | **174** | **850 (4.9 per hit)** |
  | KQ2 frame 078 alone (MODE 2) | 19 | 37 | 206 (5.6 per hit) |

  ★★ **The column walk is real, not trivial** — 4.9–5.6 steps per control pixel where r1's is 1.0,
  so its cost varies with scenery. ★★★ **And the composite is byte-identical on these frames
  (AC-6), so the `checkControlPixel` transcription is correct.** ★ Its **cost** is still
  unmeasured, for AC-7's reason.

- **AC-9 [class: state-comparable]** ★ **Not measured. MMU remaps and save-under restore remain
  outside the cost figure**, unchanged from P5.2 §7.5/§7.6 — AC-7's harness defect took the
  budget that would have gone here. **Stated, not estimated.**

- **AC-10 [class: eye-gated]** ★★ **NOT PRODUCED — and the honest reason is AC-5.** The ask is
  *the EGO behind scenery*. KQ2 supplies ego frames in quantity, but a frame needs the ego
  **partly occluded** to show anything, and the priority-rejection counts above are per staged
  set rather than per sprite. Selecting and rendering it is `comp_pick.py` + `comp_overlay.py`
  work that did not fit. **"pending Jay", nothing self-certified, no image offered.**

- **AC-11 [class: suite]** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

Siblings, before → after:
```
BEFORE   POP3_port       M src/hal/coco3-dsk/sys.s
         karateka_coco3  M src/hal/coco3-dsk/sys.s
                         M harness/smoke/last-run.log
AFTER    POP3_port       (no tracked changes)          HEAD 104b197  pushed
         karateka_coco3  M harness/smoke/last-run.log  HEAD 29f8f0a  pushed
                         ^ timestamp-only smoke log, not the shared change (§2G)

POP  build.bat -> === BUILD COMPLETE ===
  PROBE.BIN 1269/1269 ok  MODE.BIN 1332/1332 ok  ANIM.BIN 1451/1451 ok
  INTRO.BIN 28145/28145 ok  LOADER.BIN 1606/1606 ok  TILE.BIN 1500/1500 ok
  VERDICT: PASS - every file on the image matches its artefact.
  build/loader.bin  1606 B  56bf6740440c4e0a   [P4.4 §5: same]  UNCHANGED
  build/probe.dmk 224016 B  ec6daccb0b78a9d5   [P4.4 §5: same]  UNCHANGED

karateka build.bat -> === BUILD COMPLETE ===
  build/karateka.bin               17978 B  9cd20dc537415e80   UNCHANGED
  build/gfxmode3.bin                4412 B  d447c768bd5e6b80   UNCHANGED
  build/sprite_engine_sandbox.bin   1720 B  543ad8f014bd84d6   UNCHANGED

hal_sync_check.py (AFTER)
  coco_agi        OK -- aligned with POP3_port, karateka_coco3  (11 files)
  POP3_port       OK -- aligned with karateka_coco3, coco_agi   (11 files)
  karateka_coco3  OK -- aligned with POP3_port, coco_agi        (11 files)

[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
```

AC-2:
```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
```

AC-4:
```
KQ2  room 1  ★ room jump at cycle 40: var0 <- 1, flag 5 set   var0=1  icguard=1
KQ2  room 2  ...                                              var0=2  icguard=1
KQ2  room 3/4                                                 var0=3 / var0=4
KQ3  room 1  ego x=94  y=131  var0=1     room 2  ego x=84  y=148  var0=2
KQ3  room 3  ego x=43  y=135  var0=3     room 4  ego x=110 y=149  var0=4
larry1 rooms 1-4                          var0=1..4, no halts
```

AC-6:
```
Kingquest2-r3   ★ 40 frames: 40 identical, 0 divergent
Kingquest2-r2   ★ 20 frames: 20 identical, 0 divergent
Kingquest2-r4   ★ 20 frames: 20 identical, 0 divergent
```

AC-7 / AC-8 — the same frame, two ways:
```
MODE 2 (one composite per handshake):
  counters: tested 916 written 497 rejpri 19 rejkey 400 ctrlhit 37 ctrlstep 206
  frame 078   3 sprites  BOTH PLANES IDENTICAL          ★ 916 = 340+384+192 exactly

MODE 3 (cp_do_free, the timing path), REPS=1, counted build:
  078,0,10,34,1,97.59 s,tested 696660,written 473319,rejpri 16392,rejkey 206949,...
MODE 3, REPS=1, -DCOMP_NOCOUNT build:
  078,0,10,34,1,59.33 s   ★ still enormous -> NOT the counters
  078,2, 6,32,1, 0.0167 s ★ the ego, sane
```

25.2 bundled-artifact grep: **N/A** — this task ships no bundled artifact; the deliverables are
harness tooling, an oracle patch and two sibling commits.

25.3 operator-runtime-smoke: **pending Jay (AC-10)** — **no image produced this task**, launch
path therefore not applicable. Nothing self-certified.

---

### 6 — Reactive deviations and route accounting

**Triggers.** ★★ **Trigger 5 FIRED** (AC-5): the room jump cannot reach KQ3's or larry1's
gameplay. **Reported, not worked around.** Triggers 1, 2, 3 did **not** fire. **Trigger 4 could
not be evaluated** — AC-7 produced no number.

**Deviations (§22.5):**
1. **Oracle patch 0008** written and the oracle rebuilt — the oracle needed its own jump for
   AC-5's frames; C1's host-side jump only drives our VM.
2. **`COMP_COUNT`** added to `comp_sweep.lua` — the MODE-2/MODE-3 comparison that localised
   AC-7's defect.
3. **Rooms 8/14/20 tried** for KQ3 and larry1 beyond the planned 1–4, chasing AC-5's third
   title. Unsuccessful; reported.

**ROUTE ACCOUNTING.** I said early on that I would gate "≥100 frames across ≥3 titles". **I
delivered 80 frames on ONE title.** The shortfall is AC-5's, not a change of plan, and it is
stated in AC-6 rather than left to be inferred from the count. ★ I also said the free-run timing
harness was the way to measure AC-7; **it is the thing that failed**, and no number replaced it.

---

### 7 — Uncertainty flags

1. ★★★★ **AC-7's harness defect is localised but NOT diagnosed.** `cp_do_free` inflates the work
   ~2,049× on control-branch frames; MODE 2 on the same frame is exact. **The composite is
   correct** (AC-6, and MODE 2's counters). Until it is fixed there is **no gameplay cost
   figure**, and the 106% floor stands unchanged.
2. ★★★ **AC-5 covers one title.** KQ3 gives 9 ego frames, larry1 zero. **Any statement about
   gameplay compositing rests on Kingquest2 alone.**
3. ★★ **AC-10 was not produced.** No eye gate for the ego behind scenery exists yet.
4. ★★ **AC-9's terms (MMU remaps, save-under restore) remain outside every cost figure.**
5. ★ **A jumped oracle run is not a vmstate baseline** — patch 0008 perturbs the engine by
   design, exactly as 0006 does.
6. ★ **Only rooms 1–4, 8, 14 and 20 were tried.** A different room might reach KQ3/larry1
   gameplay without any extra mechanism.

---

### 8 — Follow-up candidates

1. ★★★★ **Fix `cp_do_free`, then take AC-7.** It is the only thing between here and the number
   §3.6 and §9 are waiting on. MODE 2 already gives exact counters, so a per-composite timing
   loop built on MODE 2's shape would sidestep it entirely.
2. ★★★ **Reach KQ3 and larry1 gameplay** — `setvar`/`setflag` on the intro-complete flag, per
   trigger 5. AC-5 and AC-6 both widen the moment it works.
3. ★★ **AC-10's eye gate**, once (2) supplies a partly-occluded ego.
4. ★★ **Measure the control branch's cost** — it fires at 4.9–5.6 scan steps per pixel and could
   be the largest term (AD-71).
5. ★ **The MMU remaps and save-under restore** (AC-9).

---

### 9 — User interaction during task

★ **One, mid-task:** Jay observed *"seems to be taking a long time"* while §2/§3's housekeeping
was running. Acknowledged with a status; no scope change. ★★ The remark was fair — the
housekeeping consumed a large share of the budget, and AC-7's harness defect consumed most of
what was left.

★★ **§2J: no heredocs were used this session.** Eight were used in T-P0-028 and reported; the
count here is **zero**. ★ No project-level instruction conflicted this session; the standing
"bypass permissions mode" instruction that names heredocs, recorded in P5.2 §9, did not recur.

---

### 10 — Candidate(s) captured this task

`None.` ★ AC-7's defect is a strong candidate in the making — "the harness broke on the data the
gate was widened to reach" — but it is **not yet diagnosed**, and a row written from a symptom
would be a row about the wrong mechanism. **Deferred deliberately** until the cause is known.

### 11 — Commit

`f0b5f5e` — pushed to origin/wip before this report was filed.
