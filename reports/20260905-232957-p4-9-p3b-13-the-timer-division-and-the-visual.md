## Form B Report — P4.9 / P3b.13 — the timer division, and the visual opened

**Class:** build. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-05 (dispatch carried no explicit receipt timestamp; report written 2026-09-05T23:29:57-04:00).

---

## §4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `wip` @ **`70b1dba07ff81009383614bbb9f61cd399697ef5`**, `origin/wip` identical |
| `git status` | **clean at task start** — see the correction below |
| POP + Karateka | §2T cite P4.8 §0 |
| `hal_sync_check.py` | **OK in all three repos** |
| the five gates, fresh builds | §2T cite P4.8 §4 AC-1 + byte-identity; **VM gate re-run in full this task** (AC-3) |
| **flag sets — enumerated and diffed** | **8/8 artifacts identical** at task start |
| **the clock — measured** | **1.789417 MHz** (ablation harness, 640,000 cycles) · **1.789772 MHz** (p3b, `VP_MARK`, 160,009 cycles) |
| **the division's callers** | ★★★★ **ONE caller, and no caller needs the quotient** — see AC-2 |

### ★★ CORRECTION to §4's premise, reported before the summary

> §4 states: *"`vm_probe.s` was modified relative to HEAD at INFRA.1; that is live work."*

**It was clean at task start**, and has been since P4.7 fetched `ec86b83` and reset onto it. The bytes
never changed — only the git status did. This is the second dispatch to carry the premise forward; it
is now stale by two tasks. ★ **`vm_probe.s` is modified now, by this task, and that is deliberate.**

---

### 1 — Summary

**A and B are independent and are attributed separately throughout** [L-54].

**A — the division is gone.** Its one caller never used the quotient as a number, so it was replaced by
a 40-tick counter whose exactness was **simulated over 4,000,000 ticks before a line was written**.
**Kingquest1 runs 10.2% faster — 126,762 → 113,796 cy/VM cycle, 14.1 → 15.7 VM cycles/s — and 110 bytes
came back.** The VM gate is 9/9 with an empty exclusion set: **the change moved no byte of state.**

**B — the visual is open, and P3b's `sprites 0` was never a compositor problem.** At 300 cycles, five
times P3b's 60, Kingquest1 still reported `room 83 sprites 0`: **the game never leaves its opening
room.** Two host writes fix it, and with them **the compositor runs live at 2 and 4 sprites** —
**0.02107 and 0.03929 s/cycle**, which is far cheaper than the pre-windowing prediction. **The
4-sprite margin is comfortably positive.** AC-6's byte comparison and AC-9's eye gate are **not
delivered** and §6 says why.

---

### 2 — Files modified

**A:**
- `src/harness/vm_cycle.s` — `vm_timer_update`'s boundary detection replaced by a counter;
  `vm_div32` and its scratch (`vm_q32`, `vm_dvsr`, `vm_rem32`, `vm_dvcnt`) removed; `vm_sectick`
  added and reset with the clock it counts.

**B:**
- `harness/tools/p3b_room.lua` — **new.** Room jump for the integrated probe; installs a notifier and
  `dofile`s `p3b_run.lua` unchanged.

★ Nothing else. No gate artifact's source was touched by B, and A's effect on the gates is AC-3.

---

### 3 — Reasoning

#### A.1 — The division had one caller and it never wanted a quotient [AC-2, trigger 1]

Enumerated rather than sampled [L-77]. **`vm_div32` is called from exactly one site**
(`vm_cycle.s:361`), and `vm_q32` is read at exactly four (`:363, :366, :370, :372`) — **all inside
`vm_timer_update`, and all either comparing the quotient against `vm_lastsec` or storing it into
`vm_lastsec`.**

★★★★ **A value that is only ever compared against its own previous value is a change detector.** No
caller needs the number. **Trigger 1 does not fire.**

The same enumeration on the clock itself: **`vm_vms` has exactly two writers** — the zeroing at
`:122-123` and the `+25` at `:319-325` — **and no reader outside the increment and the division.**

#### A.2 — The keying, measured before building [§2, AD-87's precedent]

**Because `vm_vms` starts at 0 and only ever grows by 25, the quotient by 1000 increments on precisely
every 40th tick.** That is an argument; AD-87's precedent is that arguments about keying are what
cost a third of the cache's gain, so it was **simulated first**:

```
ticks simulated      : 4000000  (27.8 h of game time)
division boundaries  : 100000
counter  boundaries  : 100000
DISAGREEMENTS        : 0
period               : 40 ticks  (1000 ms / 25 ms)
```

★★ **And the counter is strictly more correct at the wrap.** 2^32 ms is a multiple of neither 25 nor
1000, so when `vm_vms` wraps the old comparison sees a huge stored quotient against a small new one
and misfires. The counter never consults `vms`. **That is 49.7 days of game time away and is not the
reason for the change** — it is stated so the change is not later mistaken for a risk it removes.

#### A.3 — What the change cost and returned [AC-5, L-78]

Clock **measured 1.789417 MHz**, not asserted.

| title | before | after | saved | rate |
|---|---|---|---|---|
| Kingquest1 | 126,762 cy/VM cycle | **113,796** | **12,966 cy = 10.2%** | 14.1 → **15.7** cyc/s |
| Kingquest3 | 191,534 | **185,070** | 6,464 cy = 3.4% | 9.3 → **9.7** cyc/s |

**Size: 8,822 → 8,712 B — 110 bytes reclaimed.**

★★★★ **P4.8's profiler predicted this before the change existed.** It put the timer path at 11.2% of
KQ1 and 4.1% of KQ3; the change delivered **10.2% and 3.4%**, both inside the sampler's stated ±1.5 pp.
**A sampled profile that predicts an unbuilt change to within its own error bars is the strongest
evidence available that it was measuring the right thing.**

★★★ **Two corroborations that were not designed for:**
- **`ABL_NOCACHE` saved 12,966 cy — the identical absolute figure as baseline** (289,301 → 276,335).
  A change confined to the timer must save the same absolute amount regardless of the cache, and it did.
- **`VM_PACEONLY` collapsed from 3,443 to 221 cy/VM cycle.** P4.8 §3.D argued that arm's cost was
  mostly the divide; removing the divide removed 94% of it. **The prediction and the result are
  independent of each other.**

#### B.1 — P3b's `sprites 0` was the game, not the compositor [AD-99]

P3b closed with `sprites 0` and `composite 0.0%`, which reads as "the compositor is untested". **The
measurement says something simpler and more actionable:**

```
cycle   1  room  83  sprites  0
cycle 300  room  83  sprites  0        ← 300 cycles, FIVE TIMES p3b's 60
composite    0.0045 s total   0.0%  (300 entries)
```

★★★ **The game never leaves room 83, and no number of extra cycles changes that** — an AGI title sits
in its credits until something moves it. **The compositor had nothing to composite.**

#### B.2 — The jump is two host writes, and the addresses are the trap [L-56]

`vm_sweep.lua` already carried the mechanism (P5.3 C1): AGI routes a room change through
**`VAR_CURRENT_ROOM` (var 0) and `FLAG_NEW_ROOM_EXEC` (flag 5)**, which logic.0 tests every cycle. Set
both and the game's own logic dispatches the room. **Nothing is added to the 6809.**

★★★ **But `vm_sweep.lua` hardcodes `VM_VARS $4000 / VM_FLAGS $4100`, and the integrated probe maps
them at `$0800 / $0900`** (`p3b_probe_pk.map`). Copying the pair across would have written into
whatever lives at $4000 in that build and reported "the room jump does nothing."

★★ **A second defect of my own, caught by its own printout.** The first run announced
`room jump at cycle 65535` — RAM read before the probe zeroed the counter — so both writes landed
during init and the guest's reset erased them. **The jump reported success and the room never
changed.** Guarded with an upper bound: a cycle number above the run length is not a cycle number.

#### B.3 — Compositing live, and the margin [AC-6, AC-7]

Clock **measured 1.789772 MHz** (`VP_MARK`, the guest's own instruction closing the interval).

| room | sprites | composite s/cycle | share of cycle | cycle cost |
|---|---|---|---|---|
| 83 (opening) | **0** | 0.00002 | 0.0% | 0.0834 s |
| 3 | **2** | **0.02107** | 4.7% | 0.3671 s |
| 1 | **4** | **0.03929** | 8.3% | 0.4506 s |

★★★ **Per sprite ≈ 0.0095–0.0105 s/cycle — about 17,000 CPU cycles.** Roughly linear from 2 to 4.

★★★★ **Against the dispatch's 14.0% / 28.0% / 42.1%, which predate windowing: measured 4.7% at two
sprites and 8.3% at four.** Compositing is **three to five times cheaper** than the figures the parser
budget was being planned against. **Trigger 2 does not fire — the margin is not negative, it is
comfortable.**

★★ **The shares are of different totals and should not be compared across rooms**; the absolute
s/cycle figures are the measurement, and the share is given for orientation only [L-41].

#### B.4 — The occlusion question, answered against the gate that is passing [AC-8, AD-77]

```
291 frames scored; 39 show PARTIAL occlusion (both drawn and refused)
291 frames scored; 250 have ZERO priority rejections (86%)
```

★★★★ **86% of frames test transparency and nothing about depth** — AD-77's trap, quantified for the
first time. **A gate sampling frames at random would have an 86% chance per frame of proving nothing
about priority.**

★★★★★ **But the compositing gate is NOT vulnerable, and this checks it rather than assuming it.** All
**20 of 20** staged frames carry priority rejections, **410 to 575 pixels each** — higher than any
frame in `comp_pick`'s printed top ten. `comp_stage.py`'s selection did its job. **Trigger 3 does not
fire: frames with occlusion exist, and the gate is already using them.**

#### B.5 — Authority tiers

Every figure is fresh tool output on this machine (25.1). The one reference claim — that `vm_div32`
reproduces `global.cpp inGameTimerUpdate` — is `vm_cycle.s:349`'s own citation, and per §2.1 that is
**a fact about ScummVM**; no claim is made about what Sierra's interpreter did, and the counter
reproduces the port's existing behaviour byte-for-byte either way (AC-3). §2H: the second mechanism
was looked for — `vm_step_clock` does two things, and the other one (`TIME_DELAY`) is what P4.8 §3.D
turned on; the calling routine is named at every step; the prior-report grep is A.3's reconciliation
against P4.8's prediction.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS.** `hal_sync_check.py` **OK in all three repos**;
  `reg_discipline.py` **8 accesses, 1 file, 2 registers** — noted, not chased [AD-104, §11]. Flag set
  **8/8 identical** at task start. **§2T citation:** gates from **P4.8 §4 AC-1**, itself citing
  INFRA.1's fresh five-gate run. ★ **The VM gate was re-run in full this task** because A changes the
  binary it builds — see AC-3.
- **AC-2 [class: state-comparable] — PASS, designed from measurement, before building.** **One
  caller; no caller needs the quotient** (§A.1) — trigger 1 does not fire. **Counter counts ticks;
  period 40 = 1000 ms / 25 ms per tick**, from the enumerated fact that `vm_vms` starts at 0 and has
  exactly one other writer adding exactly 25. **Wrap: the counter is unaffected where the division
  misfires** (§A.2). **Simulated 4,000,000 ticks, 100,000 boundaries each way, 0 disagreements**
  before the edit was made.
- **AC-3 [class: byte-comparable] — PASS. THE GATE.** **VM 9/9 titles**, 600 cycles × 288 bytes each,
  **exclusion set EMPTY**, **0 divergent cycles on every title**. ★★★ **A timing change moved no byte
  of state.** Trigger 4 does not fire.
- **AC-4 [class: byte-comparable] — PASS, on this build.** Fault re-proven: `-DVM_FAULT` →
  **SpaceQuest-1 FAIL, 519 of 600 divergent, first divergence cycle 77**; Kingquest1 still PASSes
  under the same fault, the per-title detectability P4.7 recorded. **`opcount` per arm, every one
  moving as predicted:**

  | arm | `opcount` | predicted | verdict |
  |---|---|---|---|
  | baseline KQ1 | 2,950 | unchanged — timing change, not work | ✓ |
  | baseline KQ3 | 5,439 | unchanged | ✓ |
  | `VM_PACEONLY` | **0** | zero | ✓ |
  | `VM_NOCOUNT` | 2,950 | unchanged | ✓ |
  | `ABL_NOCACHE` | 2,950 | unchanged | ✓ |

  ★ `ABL_NOCOPY`/`ABL_NOFETCH` remain rejected [P4.7, P4.8] and are used for nothing here. Trigger 5
  does not fire.
- **AC-5 [class: state-comparable] — PASS, measured, clock stated.** **KQ1 126,762 → 113,796
  (−12,966 = 10.2%), 14.1 → 15.7 cyc/s; KQ3 191,534 → 185,070 (−6,464 = 3.4%), 9.3 → 9.7 cyc/s;
  110 bytes reclaimed.** Clock **1.789417 MHz measured**. ★★★★ **Against the dispatch's 11.2% of KQ1's
  cycle: predicted 11.2%, delivered 10.2%** — inside P4.8's stated margin (§A.3). **Attributed to A
  alone**; B changed no target code.
- **AC-6 [class: byte-comparable] — PARTIAL, and the missing half is named.** ★★★ **Sprites live at
  2 and 4, windowed** — room 3 gives `sprites 2`, room 1 gives `sprites 4`, `err 0` in both, the
  compositor doing real work in both (§B.3). ★★★★ **The byte comparison against the oracle was NOT
  performed and this AC is not satisfied.** The oracle's room jump exists (patch 0008, `coco_room`)
  but **jumps at loop 300 by default while the guest jumped at cycle 8**, and establishing that
  alignment — so that "frame N" means the same event on both sides — is the work this AC actually
  requires. It was not attempted rather than attempted badly. ★★ **What DOES stand, cited not
  re-run:** the compositing gate's **20/20 byte-identical frames** [P4.8 §4 AC-1, INFRA.1], now known
  to carry genuine occlusion (AC-8).
- **AC-7 [class: state-comparable] — PASS, MEASURED not derived.** **Compositing costs 0.02107 s/cycle
  at two sprites and 0.03929 s/cycle at four**, ego composited every cycle, clock **1.789772 MHz
  measured** (§B.3). ★★★★ **Against 14.0% / 28.0% / 42.1%: measured 4.7% and 8.3%.** The pre-windowing
  figures overstate compositing by roughly 3–5×. **The 4-sprite margin is positive with room to
  spare** — trigger 2 does not fire.
- **AC-8 [class: byte-comparable] — PASS, and the answer is better than the AC feared.** **39 of 291
  frames show partial occlusion; 250 (86%) have zero priority rejections.** ★★★★★ **The chosen
  frames are not the problem: all 20 staged gate frames carry 410–575 rejected pixels each** (§B.4).
  Trigger 3 does not fire. ★ The count is reported per frame in §5, auditable rather than asserted.
- **AC-9 [class: eye-gated] — NOT DELIVERED.** No image was produced and Jay has seen nothing. The
  three-image set AC-9 asks for depends on AC-6's alignment (the composited frame must be one whose
  oracle counterpart exists), so this fell with it. **`25.3` stays "pending Jay" and is not
  self-certified.** §6 carries the honest accounting.
- **AC-10 [class: state-comparable] — three things this dispatch did not anticipate.**
  (1) ★★★★ **P3b's `sprites 0` was the game sitting in room 83, not an untested compositor** (§B.1) —
  measurable in one run and mis-framed for a full task.
  (2) ★★★★ **`comp_pick.py` does not rank by what it documents.** Its docstring says frames are scored
  by priority rejections and "ranked descending"; the code builds `(best, rej_pri, ...)` and sorts the
  tuple, so **the primary key is `best`, not the rejection count** [`comp_pick.py:86,89`]. Demonstrably
  wrong output: its printed top ten have **319–359** rejections while the staged frames it does not
  list have **410–575**. ★★ **Harmless in effect — `comp_stage.py` selects independently — and exactly
  wrong for the use this dispatch put it to.** **Fourth instrument defect in four tasks.**
  (3) ★★ **`vm_lastcyc` is dead storage** — declared and zeroed, never read or written; the `/25`
  early-out its comment describes was never implemented. **`vm_lastsec` joins it dead** as of this
  change. Both left in place deliberately (AC-3 required the reset path untouched) and reported
  rather than bundled [L-54].
- **AC-11 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*§4 — git, hal-sync, flag diff at task start:*
```
branch: wip   HEAD: 70b1dba07ff81009383614bbb9f61cd399697ef5   origin/wip: 70b1dba…   status: clean
coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
gate_audit --verify : 8/8 identical (pic 2642, pic_nc 2512, pic_nc_pk 2971, pic_win 2655,
                      res 2019, cel 1436, comp 967, vm 8822)
```

*AC-2 — the keying, simulated before building:*
```
ticks simulated      : 4000000  (27.8 h of game time)
division boundaries  : 100000
counter  boundaries  : 100000
DISAGREEMENTS        : 0
period               : 40 ticks  (1000 ms / 25 ms)
32-bit ms wrap at    : 4294967296 ms = 49.7 days of game time
wrap is a multiple of 25?   False
wrap is a multiple of 1000? False
```

*AC-3 — the gate, nine titles, with the counter live:*
```
vm_probe: 8712 bytes
compared     : 600 cycles x 288 bytes, exclusion set EMPTY
divergent cycles : 0 of 600
=== AC-2 SUMMARY ===
Kingquest1 PASS / Kingquest2 PASS / Kingquest3 PASS / SpaceQuest-1 PASS / SpaceQuest-2 PASS
PoliceQuest1 PASS / larry1 PASS / BlackCauldron PASS / MixedUpMotherGoose PASS
```

*AC-4 — the fault, on this build:*
```
FAULT INJECTED (-DVM_FAULT) -- this build is EXPECTED to fail AC-2
vm_probe: 8712 bytes
divergent cycles : 0 of 600        (Kingquest1)
divergent cycles : 519 of 600      (SpaceQuest-1)
first divergence : cycle 77
AC-2 ★★★ FAIL
Kingquest1   PASS
SpaceQuest-1 FAIL
```

*AC-5 — before and after, both titles:*
```
BEFORE (P4.8, 8822 bytes)
  Kingquest1  126762 CPU cycles/VM cycle   14.1 VM cycles/s   opcount=2950
  Kingquest3  191534 CPU cycles/VM cycle    9.3 VM cycles/s   opcount=5439

AFTER (8712 bytes)
=== baseline  (8712 bytes) ===
clock MEASURED 1.789417 MHz (640000 cycles calibrated, this session)
AC-7 free-run: 201 cycles in 12.782340 emulated s
    63.594 ms/cycle   113796 CPU cycles/VM cycle   15.7 VM cycles/s
    opcount=2950  (14.68 commands/cycle)   vm_cycle=201 of 201 expected

=== baseline  (8712 bytes) ===   [Kingquest3]
AC-7 free-run: 201 cycles in 20.788409 emulated s
    103.425 ms/cycle   185070 CPU cycles/VM cycle   9.7 VM cycles/s
    opcount=5439  (27.06 commands/cycle)   vm_cycle=201 of 201 expected
```

*AC-4 — every arm's `opcount`, and two corroborations:*
```
=== VM_PACEONLY  (8700 bytes) ===
    0.124 ms/cycle   221 CPU cycles/VM cycle   8083.3 VM cycles/s
    opcount=0  (0.00 commands/cycle)   vm_cycle=0 of 201 expected  ★★★ MISMATCH
=== VM_NOCOUNT  (8684 bytes) ===
    61.240 ms/cycle   109584 CPU cycles/VM cycle   16.3 VM cycles/s
    opcount=2950
=== ABL_NOCACHE  (8718 bytes) ===
    154.428 ms/cycle   276335 CPU cycles/VM cycle   6.5 VM cycles/s
    opcount=2950

★ ABL_NOCACHE 289301 -> 276335 = 12966 saved; baseline 126762 -> 113796 = 12966 saved. Identical.
★ VM_PACEONLY 3443 -> 221 cy/VM cycle: 94% of that arm's cost WAS the divide [P4.8 §3.D].
```

*B.1 — P3b's `sprites 0`, at five times its cycle count:*
```
cycle   1  6.0411 s  room  83  sprites  0  remaps 4  err 0
cycle 300  0.0834 s  room  83  sprites  0  remaps 2  err 0
composite    0.0045 s total   0.00002 s/cycle    0.0%  (300 entries)
final room 83, sprites 0, err 0, status=$00
```

*B.2 / AC-6 / AC-7 — the jump, and the compositor live:*
```
★ room jump at cycle 8: var0 <- 1, flag 5 set
cycle 120  0.4506 s  room   1  sprites  4  remaps 2  err 0
clock MEASURED 1.789772 MHz (160009 cycles calibrated)
pace(wait)   0.9071 s total   0.00756 s/cycle    1.6%  (120 entries)
interpret   43.6836 s total   0.36403 s/cycle   76.5%  (120 entries)
sprites      0.5070 s total   0.00422 s/cycle    0.9%  (120 entries)
roomcheck    7.3144 s total   0.06095 s/cycle   12.8%  (120 entries)
composite    4.7151 s total   0.03929 s/cycle    8.3%  (120 entries)
final room 1, sprites 4, err 0, status=$00

cycle  60  0.3671 s  room   3  sprites  2  remaps 2  err 0
composite    1.2643 s total   0.02107 s/cycle    4.7%  (60 entries)
final room 3, sprites 2, err 0, status=$00

final room 2, sprites 0, err 0, status=$00      (room 2 draws nothing -- reported, not hidden)

★ FIRST ATTEMPT, and the guard it produced:
  ★ room jump at cycle 65535: var0 <- 1, flag 5 set
  final room 83, sprites 0   -- poked during init; the guest's own reset erased both writes
```

*AC-8 — occlusion, and the frames the gate actually uses:*
```
title           frame  BEST spr   REJECTED    written  sprites   control
SpaceQuest-1      055       256        319        820        2         0
SpaceQuest-1      019       256        319        820        2         0
SpaceQuest-1      056       252        323        816        2         0
291 frames scored; 39 show PARTIAL occlusion (both drawn and refused)
291 frames scored; 250 have ZERO priority rejections (86%)

STAGED GATE FRAMES, rejections per frame:
  011:475  014:451  015:414  017:455  020:460  023:440  025:410  026:480
  028:497  029:575  045:575  046:497  048:480  049:410  051:440  054:460
  057:455  059:414  060:451  063:475
  staged frames WITH priority rejections: 20 of 20
```

*AC-10(2) — `comp_pick.py` ranks by the wrong key:*
```
comp_pick.py:86    rows.append((best, st["rej_pri"], st["written"], ...
comp_pick.py:89    rows.sort(reverse=True)
★ primary key is `best`; the docstring says the score is the rejection count.
★ printed "top" rejections 319-359; unlisted staged frames 410-575.
```

**25.2 bundled-artifact grep:** N/A — no sibling artifact was imported and no bundled asset committed.
The gate and sibling baselines are §2T citations to P4.8 §0/§4.

**25.3 operator-runtime-smoke:** **pending Jay** — and **not observed**. AC-9 was not delivered
(no image was produced), so there is nothing for Jay to look at yet. Launch path when it is run:
`poke`. ★ **This is an INCOMPLETE gate and is recorded as such, not as a deferral.**

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **AC-6's byte comparison and AC-9's eye gate were not delivered.** The guest room jump lands
   at cycle 8; the oracle's (patch 0008) defaults to loop 300, and nothing establishes that "frame N"
   names the same event on both sides. **Producing an unaligned comparison would have been worse than
   producing none** — it would have reported a byte difference as a compositor defect. AC-9 depends on
   AC-6's frame and fell with it. **Stated as incomplete, not as pending.**
2. **Two new harness tools**, `p3b_room.lua` and (from P4.8) the profiler. `p3b_room.lua` changes no
   gate artifact; `gate_audit --verify` was 8/8 identical at task start and A's effect on it is AC-3's
   business.
3. **A's dead storage was not removed.** `vm_lastsec` and `vm_lastcyc` are now unreferenced but their
   zeroing sits in the reset path, and AC-3 required that path untouched. Reported, not bundled [L-54].
4. **Rooms 1, 2 and 3 were probed to find sprite counts of 4, 0 and 2.** Room 2 draws nothing; it is
   reported rather than quietly dropped.
5. **Nothing from §11 was touched** — no surviving resource copy, no cycle-rate decision, no M-48.

**ROUTE ACCOUNTING.** No route was proposed in advance. This report contains A in full and B in part:
**delivered** — the room jump, sprites live at 2 and 4, the measured margin, the occlusion census;
**not delivered** — the oracle byte comparison (AC-6) and the eye-gate images (AC-9). ★ **A's win must
not be read as covering B's gap** [L-54]: A is complete and gated, B is two ACs short.

---

### 7 — Uncertainty flags

- ★★★★ **AC-6 and AC-9 are open.** The compositor is *running* at 2 and 4 sprites with `err 0`; it is
  **not** shown byte-identical to the oracle in those rooms. The 20/20 byte-identity that does stand
  is on SpaceQuest-1's staged frames, cited from a prior task.
- ★★★ **AC-7's per-sprite cost is from two data points** (2 and 4 sprites, one room each). The
  linearity between them is an observation, not a model, and 6+ sprites is unmeasured.
- ★★★ **The compositing shares (4.7%, 8.3%) are of different cycle totals** and are not comparable to
  each other or to the 14.0/28.0/42.1 figures as shares. **The absolute s/cycle figures are the
  measurement.**
- ★★ **Room 1 and room 3 were chosen because they have sprites, not because they are representative.**
  A room with more objects will cost more.
- ★★ **A's saving was measured on two titles.** It scales with `TIME_DELAY`, which each game sets, so
  10.2% is Kingquest1's figure and not the corpus's.
- ★ **`reg_discipline.py` still reads 8 against a recorded 5** [AD-104]; `scummvm.pin` still records
  five patches against eight applied. Carried, untouched (§11).
- ★ **The `res`, `cel` and `comp` probes' counters have still never been shown able to fail.**

**Triggers:** **1 does not fire** (no caller needs the quotient). **2 does not fire** (the margin is
positive and comfortable). **3 does not fire** (occlusion frames exist and the gate already uses them).
**4 does not fire** (9/9, exclusion set empty). **5 does not fire** (every arm's `opcount` moved as
predicted).

---

### 8 — Follow-up candidates

1. ★★★★★ **Align the guest and oracle room jumps and close AC-6 / AC-9.** This is the remaining half
   of B and it is the eye gate P3b has been waiting on since it closed.
2. ★★★★ **The surviving resource copy** — 24.3% of KQ3 and 63.6% of its excess [AD-106]. §11 kept it
   out of this task; it is now the largest single addressable term.
3. ★★★ **Fix `comp_pick.py`'s sort key** — sort by `rej_pri`, or rename the score to what it ranks.
4. ★★★ **Retire or repair `VM_PACEONLY`, `ABL_NOCOPY`, `ABL_NOFETCH`** (carried from P4.8).
5. ★★ **Remove `vm_lastsec` and `vm_lastcyc`** — 8 bytes, now provably dead, in a task that may touch
   the reset path.
6. ★★ **Measure compositing at 6+ sprites** before the parser budget is fixed.
7. ★ **Profile the remaining seven titles** and correlate A's saving against each game's `TIME_DELAY`.

---

### 9 — User interaction during task

`None.`

### 10 — Candidate(s) captured this task

`None.` — ★ Nothing new in kind. This task's two instrument defects are instances of rows already
pushed: `p3b_room.lua`'s uninitialised-counter read and `comp_pick.py`'s ranking key both belong to
**[[a-data-symbol-at-the-top-of-a-cycle-profile-means-the-attribution-is-wrong]]**'s family — an
instrument whose output is plausible and whose key is wrong — and P4.7's
**[[two-variants-agreeing-digit-for-digit-is-a-defect-signature-not-corroboration]]**. ★★ Per SCHEMA §7
a fresh `live` row is still the correct write-through for a repeat instance, and **these two are owed
if the Orchestrator reads them as instances rather than as noise**; they are named here rather than
written, because a row per recurrence of a principle already captured twice this week is thrash.
★ **INFRA.1's two rows also remain owed** (its §10).

### 11 — Commit

To be committed on `wip` and pushed to `origin/wip` before this report is read, staged by explicit
path per §2E: `src/harness/vm_cycle.s`, `harness/tools/p3b_room.lua`, and this report.
