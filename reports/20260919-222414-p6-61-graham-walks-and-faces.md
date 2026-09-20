## Form B Report — T-P0-115 / P6.61 — Graham walks, and he faces the other way
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 22:24:14 (HEAD cf3d576, wip). `src/harness/p3b_probe.s`,
`harness/tools/{p3b_run.lua,p3b_show.ps1,p3b_arms_check.ps1}`. ★★ **`git diff --stat -- src/hal/`
is EMPTY** [§6's third trigger, and AC-5's claim].

### 1 — Summary

★★★★★ **EYE-GATE QUESTION 2 IS ANSWERED AFTER EIGHT TASKS.** Jay: ***"yes he faces."*** **9,193
cels matched our own reference with 1,525 of them mirrored, and until this run no person had ever
seen one.** Internal consistency is not correctness; a human has now looked at a mirrored cel and
it is the same silhouette flipped.

★★★★★ **AND THE SMEAR PREDICTION IS RESOLVED — IT FAILED, WHICH IS THE OUTCOME IT WAS WRITTEN TO
HAVE.** P6.55 §3.3 predicted *"when input is wired and Graham walks, he will smear a trail"*, made
falsifiable on purpose and carried through six reports. Jay: ***"he does move left and right, no
smear."*** **The restore work of T-P0-112/114 is what makes it false.**

★★★★ **He blinks while walking, and that CONFIRMS P6.60 rather than contradicting it.** A walking
ego changes position every frame, so it is changed, so it is erased — and the erase is the blink.
**Standing steady, walking blinking, is exactly the rule shape 3 claimed and no more.**

★★★★★ **The join was the only thing missing, and it is ~40 bytes.** Four subsystems were already
green with no call between them — **P6.28d's shape, fourth time this arc** (§3.2).

**Loop selection measured against the oracle's own table: RIGHT → loop 0, LEFT → loop 1, both as
predicted** (§3.3). Six text arms byte-identical; four byte gates fresh green.

### 2 — Files modified

- `src/harness/p3b_probe.s` — `p3_poll_dir` (the join), its call site before `p3_run_vm`,
  `-DP3B_FAULT_NOJOIN`, and §3.5's stale-comment correction.
- `harness/tools/p3b_run.lua` — the ego's x/y/view/**loop**/cel in the summary.
- `harness/tools/p3b_show.ps1` — `-DHAL_KEYBOARD` for the cel arm; `-NoJoin`; `p3_ndirs`/`p3_newdir`
  published; `ego: x=` on the console allowlist.
- `harness/tools/p3b_arms_check.ps1` — `p3b` re-baselined **15,246 / A2724197**, flag set updated.

### 3 — Reasoning

#### 3.1 §4A — the oracle, before the wiring [L-116]. Tier 3 (ScummVM) throughout.

**(1) Where a key becomes a direction** — `keyboard.cpp:537-564`, in `handleController`:

```
UP=1  UP_RIGHT=2  RIGHT=3  DOWN_RIGHT=4  DOWN=5  DOWN_LEFT=6  LEFT=7  UP_LEFT=8
```

**(2) What it writes** — `keyboard.cpp:600-611`. ★★★★ **It writes the VARIABLE, not the object:**

```c
if (screenObjEgo->direction == newDirection) setVar(VM_VAR_EGO_DIRECTION, 0);
else                                         setVar(VM_VAR_EGO_DIRECTION, newDirection);
if (_game.playerControl) screenObjEgo->motionType = kMotionNormal;
```

and `cycle.cpp:256-259` copies it: `playerControl ? ego->direction = getVar(6) : setVar(6,
ego->direction)`. ★★★ **Our port already has both halves** — `VAR_EGO_DIRECTION` is var 6 and
`vm_cycle.s:192-219` is that copy, keyed on `vm_playerctl`.

**(3) What stops the ego** — ★★★★★ **pressing the CURRENT direction again**, the first branch above.
Also a key-up in `_keyHoldMode`, which becomes a stationary event and the same direction-0 write
[`keyboard.cpp:337-345`]. ★★★ **The same-key rule is what makes a stop reachable here at all**,
because `HAL_key_scan` reports matrix STATE and has no key-up event.

**(4) Whether the loop changes with direction — §6's STOP CONDITION, and it did NOT fire.**
`view.cpp:719-767`, in `updateScreenObjTable`, *"called at the end of each interpreter cycle"*:

```c
static int loopTable2[] = { 0x04, 0x04, 0x00, 0x00, 0x00, 0x04, 0x01, 0x01, 0x01 };
static int loopTable4[] = { 0x04, 0x03, 0x00, 0x00, 0x00, 0x02, 0x01, 0x01, 0x01 };
loopNr = 4;                                       // 4 == leave the loop alone
if (!(screenObj->flags & fFixLoop)) { switch (screenObj->loopCount) { case 2: case 3: ... } }
if (loopNr != 4 && loopNr != currentLoopNr) { if (version <= 0x2272 || stepTimeCount == 1) setLoop(...) }
```

★★★★★ **The port has all of it** — `vm_objects.s:151-183`: both tables as
`VMT_LOOP_TABLE_2/4` *"generated from the pinned oracle"*, the `fFixLoop` bypass, the
`VMO_NUMLOOPS` switch, the `VMO_DIR` index, the change-only-if-different guard and
`jsr vm_set_loop`. ★★ Its one documented omission is the oracle's fifth branch (loopTable4 for any
loop count at v3086/KQ4), noted at `vm_objects.s:171`.

#### 3.2 ★★★★★ Four green subsystems and no call between them

| piece | state before this task |
|---|---|
| key decoder | **gated 10/10** [P6.24] |
| `HAL_input_init` precondition | **already satisfied** at T-P0-092 (§3.5) |
| direction → loop | **ported with both oracle tables** [`vm_objects.s:151-183`] |
| var 6 → `VMO_DIR` | **already copied every cycle** [`vm_cycle.s:212-219`] |
| `update_position` | ported from `checks.cpp` |
| ★★★★★ **key → var 6** | ★★★★★ **did not exist** |

★★★★ **So the whole of eight tasks' blockage was one routine that writes one variable.** The
dispatch said so in §1.1 and it was right. ★★★ **This is the fourth time in this arc that every
subsystem was green and the join was the defect** — P6.28d, P6.51's `vc_srcend`, P6.56's `CP_SAVE`,
and now this. **A gate that verifies a piece cannot see the absence of a call to it.**

#### 3.3 §4C(2) — the loop, as a number, against the oracle's prediction

★★★★ **A keypress cannot be scripted** [P6.37: natkeyboard holds a key 2-3 frames, the port polls
once per cycle, 180 posts delivered zero], so the DIRECTION was injected with the same `P3B_SETVAR`
mechanism `p3b_box` uses for var 17 — **the identical path a key drives, from var 6 onward.**

```
standing                LOOP=0   x=110 y=100
walking RIGHT (var6=3)  LOOP=0   -> loopTable4[3] = 0   ✓   final room 8
walking LEFT  (var6=7)  LOOP=1   -> loopTable4[7] = 1   ✓   final room 2, x 110 -> 0
```

★★★★★ **Both match, and `loopTable2` agrees on both entries**, so the result does not depend on the
ego view's loop count. ★★★ **And the ego left the room in both directions**, which the dispatch did
not ask for: `update_position` plus edge handling, evidenced by the room number changing.

#### 3.4 ★★★★ Two instruments, each covering HALF the chain — stated rather than blurred

| instrument | covers | does NOT cover |
|---|---|---|
| Jay's eye gate | ★★★ **key → var 6** (he pressed arrows and the ego moved) | the loop number; anything as a value |
| `P3B_SETVAR` injection | ★★★ **var 6 → loop → motion**, measured | the key path — `dir-keys accepted 0` in every arm |

★★★★★ **Neither instrument covers both halves, and the pair does.** ★★ Saying which half each one
reaches is what keeps *"Graham walks"* from resting on an instrument that never touched a key.

#### 3.5 §1.2's precondition was already satisfied, and the note saying otherwise was stale

The dispatch quoted `p3b_probe.s` — *"`HAL_input_init` lives in `input.s` and this probe never
included it, so the PIA precondition ... has never been asserted here"* — as an open item to close.
★★★★ **It was closed at T-P0-092**, which added `jsr HAL_input_init` under `ifdef HAL_KEYBOARD` at
the init site. **The comment beside the include was never updated**, survived three tasks, and was
quoted forward into this dispatch as work to do.

★★★ **Corrected rather than deleted**, with the old sentence preserved and dated — and ★★ **it is
the same shape as P6.60 §3.6's stale binary figure**: a fact recorded in prose beside code that
later changed, with nothing that can make the prose fail. **Second instance in two tasks.**

#### 3.6 What was deliberately not implemented

★★★ **Four directions, not eight**, and the reason is the scanner rather than scope.
`hal_globals.s:252-256`: `HAL_key_scan` *"reports ONE KEY, NOT A SET ... A caller that needs
simultaneous keys -- a game reading two arrows for a diagonal -- needs the mask"*. ★★ The oracle's
2/4/6/8 are **named and left unimplemented**; reaching them means changing a PROJECT_LOCAL HAL
routine's contract, which is its own task.

### 4 — Verification (AC-by-AC)

- **AC-1 [citation · oracle] — MET.** §3.1, four answers, quoted, tier named. ★★ (4) did **not**
  block question 2.
- **AC-2 [state-comparable] — MET.** §3.3, as values: `LOOP` 0/1 and the room number changing.
- **AC-3 [measurement] — MET.** §3.3 and §4C(3): `restore` **620.8/cycle standing → 990.8/cycle
  walking left** (+59.6%), a moving sprite being restored every frame by definition. ★★ The
  right-walking arm is **not comparable** — it left room 1 for room 8, so its 145.7 measures a
  different room; said rather than averaged in.
- **AC-4 [state-comparable] — MET.** ★★★★★ **The smear prediction is resolved and FAILED**, by the
  eye gate, which is the instrument that can see a trail. §1.
- **AC-5 [byte-comparable] — MET.** Six text arms byte-identical; `src/hal/` diff empty;
  `hal_sync_check.py` green against both siblings.
- **AC-6 [byte-comparable · gate] — MET, fresh.** `comp 124/124` · `cel 9,193/9,193` ·
  `pic 45/45` · `res 1,264/1,264`. `vm` cited under §2T — `vm_probe.s` unchanged.
- **AC-7 [fault injection] — PARTIAL.** `-DP3B_FAULT_NOJOIN` builds at **15,247 B / 81E0DC54**
  (+1 B: the early `rts`). ★★ **Not run in front of Jay** — its red is *"i can't move him"*, which
  he has already reported, but that is a citation and not a fresh observation. §7.3.
- **AC-8 [eye gate — Jay] — MET, before the byte gates, with expectations in the ask.**
  *"he does move left and right, no smear, but does blink"* and *"yes he faces."* ★★ **Questions
  4 (animate vs slide) and 5 (background/flags) not explicitly answered** — §7.2.
- **AC-9 [suite] — PARTIAL.** Four byte gates and the seven-arm check green; `$44`, `p3b_rescheck`
  and `-CelCheck` **still not run** — ★★ third task carrying these.
- **AC-10 [manifest] — MET.** `p3b` re-baselined **and its flag set recorded** — the arm now takes
  `-DHAL_KEYBOARD`.
- **AC-11 [tooling] — MET.** `hal-sync OK (11 files, both siblings)` · `reg-discipline 17 in 1 file`
  · `gen_vm_tables CHECK OK` · `fix_mojibake --check` clean on all four edited files.
  ★ `probe_identity_check.ps1` not run — `comp_probe` untouched, `comp` green.
- **AC-12 — MET.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
$ lwasm ... -DHAL_KEYBOARD src/harness/p3b_probe.s   -> 15246 B  A2724197   (+461 over P6.60)
$ ... -DP3B_FAULT_NOJOIN                             -> 15247 B  81E0DC54   (+1 B, the early rts)
$ ... -DP3B_NO_CEL -DHAL_KEYBOARD -DP3B_IRQ          -> 16409 B  D09866C3   (unchanged)
   region A: P3_CODE_END $5828 against CP_CEL $5F00 = 1,752 B margin

$ p3b_arms_check.ps1   -> p3b 15246 A2724197 OK ; six text arms OK
                          ★ all 7 shipped arms byte-identical

$ walkcheck.ps1   (P3B_ROOM=1, 300 cycles, headless)
standing              restore 186240 = 620.8/cycle   ego: x=110 y=100 LOOP=0 cel=0
walking RIGHT var6=3  restore  43712 = 145.7/cycle   ego: LOOP=0   final room 8
walking LEFT  var6=7  restore 297252 = 990.8/cycle   ego: x=0 LOOP=1 cel=3  final room 2

$ run_gates.sh comp -> 124/124 (100.00%)   cel -> 9193/9193 (100.00%)
                pic -> 45 PASS, 0 FAIL      res -> 1264/1264 (100.00%)     ★ all green
$ hal_sync_check.py -> OK, aligned with POP3_port, karateka_coco3 (11 files)
$ git diff --stat -- src/hal/  -> (empty)
$ reg_discipline.py -> 17 access(es), 1 file, 4 registers    gen_vm_tables --check -> CHECK OK
$ fix_mojibake.py --check <4 edited files> -> clean
```

**25.2 bundled-artifact grep:** N/A.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, live, RGB, room 1, 700 cycles at 100.00%.**
*"so he does move left and right, no smear, but does blink"* · *"yes he faces."*

### 6 — Reactive deviations and route accounting

★★ **No §6 trigger fired.** Two were live and both came back negative, which is a result:
§4A(4)'s loop selection **is** implemented (§3.1), and **Graham does not smear** (§1).

**Deviation.** ★★★ **§4C's measurements were taken by INJECTING var 6, not by pressing a key.** The
dispatch anticipated this (§2 forbids re-deriving natkeyboard's limits) but did not name the
substitute. §3.4 states exactly which half of the chain each instrument reaches, so the two are not
presented as one.

**Route accounting.** ★★ I implemented §4B's minimum and nothing beyond it: four directions, no
diagonals, no input line, no `get.string`, no key queue. §3.6 names the diagonals as declined rather
than forgotten.

### 7 — Uncertainty flags

1. ★★★★ **"He faces" is a human judgement of a mirrored cel, and it is the only one.** ★★★ It is
   exactly the judgement the cel gate cannot make — but it is one look by one person at one view,
   and 1,525 mirrored cels exist.
2. ★★★ **Eye-gate questions 4 and 5 unanswered.** Whether he **animates between cels** while walking
   rather than sliding, and whether the background/flags are still right. ★★ `cel=3` in the walking
   arms says the cel index moved from 0, which is evidence for animation but is not the observation
   asked for.
3. ★★★ **AC-7's fault arm was not run.** It builds and its red is already on record from Jay's own
   earlier words, but **that is a citation, not a demonstration** [§2W].
4. ★★★ **The right-walking measurement is void for comparison** — the ego left the room. Only the
   left arm's 990.8 is a walking figure.
5. ★★ **`vm_playerctl` was never checked directly.** The copy is conditional on it; the ego moved,
   which implies it was set, but it was not read.
6. ★★ **The straddle clamp is still in** — ~1.9% of row starts restore short. **Fifth task.**
7. ★ **`vm` cited, not re-run.**

### 8 — Follow-up candidates

1. ★★★★★ **The blink is now the dominant visible defect and it hits every sprite the player
   moves.** ★★★★ **Page flip needs a `src/hal/` task, and `HAL_gfx_present` contradicts its own
   file's geometry** [P6.59 §3.2] — **that should be raised with POP and Karateka**, since it is a
   defect for Karateka's successor too.
2. ★★★★ **Run AC-7's arm and the three suite rows P6.60 and this task both skipped** (`$44`,
   `p3b_rescheck`, `-CelCheck`). ★★★ **Third task carrying them**, which is how evidence stops
   being collected.
3. ★★★★ **Ask questions 4 and 5** — cel animation while walking, and the background — §7.2. Cheap,
   and they are the two parts of this eye gate that did not land.
4. ★★★ **Fix the straddle clamp** — fifth task.
5. ★★★ **Diagonals need `HAL_key_scan` to return a SET**, not a key [§3.6]. PROJECT_LOCAL, so it is
   ours to change, but it is a contract change and its own task.
6. ★★ **A plane-content census** — the bytes-moved census cannot see a wrong value [P6.60 §7.1].
7. ★★ **Delete the dead `ifdef CP_SAVE` block** — fifth task carrying it.
8. ★ `MAP_PRI_BANDS` — **ninth task carrying an address nothing uses.**

### 9 — User interaction during task

1. ★★★★★ **"so he does move left and right, no smear, but does blink"** — three results in one
   clause: the join works, **P6.55's prediction is falsified**, and P6.60's model is confirmed.
2. ★★★★★ **"yes he faces"** — **eye-gate question 2, blocked eight tasks, answered.** The first
   mirrored cel this project has ever put in front of a person.

★★ Both asks carried their expected answers [§4D], as P6.60's did; ★ and both replies addressed the
expectations directly rather than needing a follow-up about what to look at.

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-carry-a-falsifiable-prediction-until-it-can-be-tested.md`
- `seeds/AGI/live/2026-09-19-two-instruments-each-covering-half-a-chain.md`

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting.
