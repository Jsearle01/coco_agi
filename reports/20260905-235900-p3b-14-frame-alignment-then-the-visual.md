## Form B Report — P3b.14 — frame alignment, then the visual

**Class:** build. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-05 (dispatch carried no explicit receipt timestamp; report written 2026-09-05T23:59:00-04:00).

---

## §4 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `wip` @ **`d91b5a9ce91aadbd11506bf54b4e00bc31c9b6e5`**, `origin/wip` identical, **status clean** |
| POP + Karateka | §2T cite P4.9 §0 |
| `hal_sync_check.py` | **OK in all three repos** |
| the five gates, fresh builds | §2T cite P4.9 §4 AC-1; **compositing gate re-run this task on a new corpus** (AC-4) |
| **flag sets — enumerated and diffed** | ★★★★★ **CONTRADICTION — `vm` DIFFERED. See below.** Restored; **8/8 identical** |
| **the clock — measured** | **1.789417 MHz** (ablation harness) · **1.789772 MHz** (`VP_MARK`, p3b) |
| **patch 0008's loop default** | **300 `s_cocoLoop` main-loop iterations**; the guest jumps at **VM cycle 8**. Stated in both sides' terms below |
| `p3b_room.lua` | **reproduces** — room 1 → `sprites 4`, room 3 → `sprites 2`, room 2 → `sprites 0` |

### ★★★★★ CONTRADICTION — a fault-injected gate artifact was left in the tree, by me

`gate_audit.py --verify` at task start:

```
vm     build/vm_probe.bin           8712     8712  ★★★ DIFFERS -- the gate is testing something else
```

**Same size, different bytes** — the signature P4.7 recorded. **`build/vm_probe.bin` was the
`-DVM_FAULT` build.** P4.9's AC-4 ran the fault last and I did not restore the clean binary
afterwards. Faulted hash `313D5F30…`; clean rebuild `1B5EA3B7…`; **8/8 identical after.**

★★★ **Nothing faulted was ever committed** — `/build/` is gitignored, confirmed by `check-ignore`.
★★ **P4.9's own §5 claim of "8/8 identical" was true at ITS task start and I did not re-check at its
end.** The discipline that caught this is the one P4.7 introduced for exactly this artifact, and it
worked; **the gap is that a task can leave a faulted binary behind and only the NEXT task notices.**

---

### 1 — Summary

★★★ **AC-7 is PARTIAL and the summary below was corrected to say so** — the still frames were
delivered; the *animating* run on the CoCo3 was not, because the integrated probe has no present
path at all (§3.F). **P3b's last byte-comparable AC is closed; its eye gate is not.**

**The alignment problem dissolved rather than being solved, and that is the finding.** P4.9 refused to
compare because guest cycle 8 and oracle loop 300 name different events — correct, and it assumed the
comparison required aligning two independent runs. **It does not.** The compositing gate stages the
oracle's own per-frame inputs into the guest, so **the anchor is the frame's input tuple and there is
no clock to align.** With that established: **24 of 24 composited frames byte-identical on both
planes**, on a corpus deliberately built to contain occlusion — and **the priority-test fault is
caught on it**, which is what makes the 24/24 mean something. P3b's last byte-comparable AC is closed;
**AC-7's images are delivered and its
animating run is not** (§3.F).

---

### 2 — Files modified

- `harness/tools/vm_profile.py` — *(unchanged this task; listed for provenance only)*
- `docs/gates/p3b14-frame568.priority.png` — **new**, committed (§2P: ours)
- `docs/gates/p3b14-frame568.outcome-overlay.png` — **new**, committed
- `docs/gates/p3b14-frame569.outcome-overlay.png` — **new**, committed

★★ **NOT committed, per §2P:** `build/eye-gate/p3b14-frame568.coco3.png` and `…oracle.png` are
composited game content and live in gitignored `build/`. **They were sent to Jay directly.**

★ **No `src/` file was changed.** A's dead storage is recorded, not removed (AC-8).

---

### 3 — Reasoning

#### 3.A The alignment gap, stated in both sides' terms — and then dissolved [AC-2]

**The gap is real and worse than a count mismatch.** Read from patch 0008 and the engine:

| | counts | jump fires at |
|---|---|---|
| oracle `s_cocoLoop` | **`playGame()` main-loop iterations** | `>= coco_room_after`, default **300** |
| oracle `s_oracleCycleNr` | **`interpretCycle()` calls** — what `vmstate.txt` numbers | — |
| guest `P3_CYCLE` | **interpreted cycles** | **8** |

★★★ **Loop iterations and interpreted cycles are different clocks**: the main loop advances the virtual
clock 25 ms per iteration and `interpretCycle()` runs only when the pacing gate says a cycle is due —
`timeDelay × 2` iterations apart, and `timeDelay` is a value the game sets. **So "loop 300" does not
name a cycle number at all without knowing the title's `TIME_DELAY`.**

★★★★ **And the two jumps are not the same operation.** The guest sets var 0 and flag 5 and lets
logic.0 dispatch the room. The oracle calls `newRoom()` directly, which additionally *"resets the
screen-object table, unloads resources, sets playerControl/horizon"* [patch 0008]. **Two different
mechanisms cannot be aligned by matching their trigger points**, and patch 0008 says so itself: *"a run
with it on is NOT a valid vmstate baseline."*

★★★★★ **THE ANCHOR, and it is not a count.** The compositing gate does not run the game on the guest.
It stages, per frame, **the oracle's own before-planes, its own sprite list, and its own after-planes**,
and asks the 6809 to composite those exact inputs. **The frame's input tuple IS the anchor: it names the
same event on both sides because it is literally the same bytes on both sides.**

> ★★★ **"Both counted to N" is not an anchor; "both were given these 26,880 bytes and this sprite
> list" is.** The clock alignment P4.9 was blocked on was never required for this comparison — it
> would be required to compare two independently *running* engines, which is a different gate.

★★ **P4.9's refusal was still correct**: it declined to compare on an unjustified basis. What it got
wrong was the premise that the comparison needed a shared clock at all.

#### 3.B Demonstrating the anchor, not asserting it [AC-3]

Two independent quantities agree at the anchor, which is what turns one agreement into an alignment:

1. ★★★★ **An independent model reproduces every candidate frame.** `comp_stage.py` carries a Python
   transcription of the oracle's `SpritesMgr::drawCel` and replays each frame's
   before-planes + sprite list → after-planes, comparing against the oracle's own `after` dump.
   **576 candidates, self-check passed on all of them.** This is not the 6809's answer — it is a third
   party agreeing that the tuple describes the event it claims to.
2. ★★★ **The sprite count agrees with the integrated run.** The staged frames report **4 sprites**;
   `p3b_room.lua` running the *guest's own game* in room 1 independently reports **`sprites 4`**
   (P4.9 §B.3). Two different paths to the same room agree on how many objects are on screen.

★ **Neither quantity is the composited bytes**, so neither is the thing AC-4 tests.

#### 3.C Building a corpus that can fail [AC-6, AD-77]

★★★★ **The room jump alone was not enough, and the census says so.** Oracle runs jumped to rooms 1, 3
and 5 produced **1,353 frames whose maximum priority rejection is 5 pixels.** Room 1: **566 frames, 97%
with zero rejections**, best frame rejecting **3 pixels of 354 written**. **A gate on those frames would
pass with the priority test inverted** — AD-77 exactly.

★★★ **The scenery is there; the ego never walks to it.** Scanning room 1's own priority plane for
standing positions where the band exceeds what a sprite standing there would carry found **600 pixels
refusable at x=132, y=60** (band 13 covers 37.8% of that screen). **So the deficiency was the ego's
path, not the room.**

★★★★ **Patch 0008's `coco_ego_x/y` exists for this.** Re-run with the ego placed at the scanned
position: **576 frames, zero-rejection frames fall from 97% to 6%**, and the best frames reject
**94 sprite pixels** — against 243–263 written, **roughly 28% of the sprite refused.**

★★ **The selection is mechanical and auditable**, not a judgement call: the position came from the
room's priority map, and the frame ranking from counted rejections.

★ **`comp_pick.py` still ranks by the wrong key** (P4.9 AC-10: it sorts `(best, rej_pri, …)`, so the
primary key is `best`). Its printed "top" is not the most-occluded set, so **every ranking in this
report was re-sorted on the rejection column** rather than taken from its output.

#### 3.D What the fault proves, and the margin it leaves [AC-5, L-62, L-81]

`-DCOMP_FAULT` swaps **`bhs` for `bhi` in the priority test** — a one-boundary error in precisely the
comparison AD-77 says an occlusion-free corpus cannot see.

**On this corpus it is caught: 24 frames, 22 identical, 2 divergent** — frame 568 (5 bytes, first in
visual at row 158 col 41) and frame 569 (6 bytes, row 158 col 40).

★★★★ **But 22 of 24 frames pass under a priority-inverted build, and that is the reportable part.**
`bhs` and `bhi` differ *only* where a sprite pixel meets a priority value exactly equal to its own
band — the boundary, not the whole occlusion. **So a rejection count selects for "this frame tests
priority at all", which is what AD-77 asks for, and NOT for "this frame tests the boundary."**
★★ The staged set carries **2,184 rejected pixels** and still only two frames sit on the boundary.
★ **The gate is fault-detectable with a margin of two frames**, and a differently-chosen 24 could
plausibly have had none.

#### 3.E Authority tiers

Every figure is fresh tool output on this machine (25.1). The oracle's behaviour is cited as **a fact
about ScummVM** (§2.1) and is not a claim about Sierra's interpreter; the composited bytes are the
oracle's own output, which §2O.1 makes the reference. §2H: the second mechanism was looked for and
found — the control-line branch is a *separate* priority path from the band test (frame 568 draws 25
pixels through it), and it is reported separately rather than folded into the rejection count. The
calling routine is named at each step (`playGame` → `newRoom`; `vm_pace` → `interpretCycle`), and the
prior-report grep is §3.A's reconciliation against P4.9 §6.1.

#### 3.F ★★★★★ THE INTEGRATED PROBE HAS NO PRESENT PATH — nothing has ever reached the screen

★★★★★ **Found after this report was first written, when Jay read it and said he expected a live run
on the CoCo.** The expectation was correct and the delivery was a still. **The reason is not that
this task chose a still — it is that a live view is not currently possible from the integrated
probe.**

★★★★ **`src/harness/p3b_probe.s` contains no present of any kind.** Grepped for `PRESENT`,
`gfx_swap`, `gfx_present`: **no match.** The probe composites into RAM planes and never points the
video hardware at them. ★★★ **So the MAME screen has been blank for every P3b run ever made**, and
every "visual" in the phase — including all three images in AC-7 — is **plane bytes rendered to PNG
by a host tool**, not a capture of the machine's display.

★★★ **`pic_probe`'s recipe does not transfer, and assuming it did would have produced a confident
wrong picture.** `pic_probe.s:421` gets its screenshots with `ifdef PIC_PRESENT` → `jsr
HAL_gfx_swap`, which flips VOFFSET between `GFX_DB_A_BLOCK` and `GFX_DB_B_BLOCK` [`gfx.s:475-479`].
**p3b's framebuffer is `MAP_PHASE_WIN`** [`p3b_probe.s:54`], its own phase-window slice — **not the
HAL's double buffer.** Calling `HAL_gfx_swap` from p3b would point the screen at RAM the composite
never wrote.
★★ **Stated as inference, not measurement:** this reads two files against each other and was not
confirmed by running it. **It is the first thing to check before anyone builds the present**, and it
is exactly the shape of claim L-53 says to verify rather than carry forward.

★★★ **What a live view needs**, so the next task does not rediscover it: point VOFFSET at the
physical block `p3_composite_all` writes; guard it with an ifdef so the **gate build stays
byte-identical**; and call it **per cycle** — `pic_probe.s:420` warns its own once-after-settling
placement is wrong for motion (*"A moving picture must not copy this"*). ★ The capture side is
already solved: `roomshots.ps1` records the flags that make a CoCo3 PNG correct (RGB monitor,
`-snapview auto`, `-snapsize 640x480`, `-keepaspect`, scratch `-cfg_directory`), and
`m.video:snapshot()` is established in `pal_gate.lua` and `pic_probe.lua`.

★★★★ **Why it was not done here:** it is a change to `p3b_probe.s`, **the probe every P3b timing
figure was taken against** — 8.3% compositing, 0.03929 s/cycle, the 4-sprite margin [AD-109]. It is
out of T-P0-049's scope (§11), and the dispatch had ended at a stop. **Reported rather than
attempted.**

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS, after a repair.** `hal_sync_check.py` **OK in all three**;
  `reg_discipline.py` **8 accesses, 1 file, 2 registers** — noted, not chased [AD-104, §11]. **Flag
  set 8/8 identical only AFTER restoring a faulted `vm_probe.bin` left by P4.9** (§4). **Gates
  unchanged by this task:** no `src/` file was modified. §2T citation: P4.9 §0/§4.
- **AC-2 [class: state-comparable] — PASS. THE ANCHOR is the frame's input tuple.** The oracle's
  before-planes, sprite list and after-planes are staged verbatim into the guest, so the two sides are
  given **the same bytes**, not the same count (§3.A). ★★★ **Why it names the same event on both
  sides:** the guest is not running the game at that point — it is compositing the oracle's own inputs,
  so the event is defined by the data rather than by either side's clock. **The gap P4.9 named is
  stated in both sides' terms** (loop 300 vs cycle 8; `s_cocoLoop` vs `s_oracleCycleNr` vs `P3_CYCLE`)
  **and shown to be irrelevant to this comparison.**
- **AC-3 [class: byte-comparable] — PASS, demonstrated.** **(i)** `comp_stage.py`'s independent
  Python model of `SpritesMgr::drawCel` reproduced **all 576 candidate frames** before staging.
  **(ii)** The staged frames' **4 sprites** agree with `p3b_room.lua`'s independent report of
  **`sprites 4`** in room 1 (P4.9 §B.3). ★ Two quantities, neither of them the composited bytes.
- **AC-4 [class: byte-comparable] — PASS. THE GATE.** **24 frames staged, 24 identical, 0 divergent**,
  **both planes**, 4 sprites each, **reported per frame** (§5). Frames 476–569 of the room-1 ego-placed
  corpus. ★★★ **≥20 required; 24 delivered.**
- **AC-5 [class: byte-comparable] — PASS on this build and this corpus, with the margin stated.**
  `-DCOMP_FAULT` (`bhs` for `bhi` in the priority test) → **22 identical, 2 divergent**: **frame 568,
  5 bytes, first in visual at row 158 col 41**; **frame 569, 6 bytes, row 158 col 40**. ★★★★ **Only 2
  of 24 catch it** (§3.D) — reported as a narrow margin, not as a clean pass. **A fault proven
  elsewhere did not transfer; this is the proof on this corpus.**
- **AC-6 [class: byte-comparable] — PASS, and the census is the finding.** **Chosen frame 568:
  91 sprite pixels REFUSED by the priority test**, 221 drawn, 25 via the control-line branch. **Staged
  set: 2,184 rejected pixels across 24 frames.** ★★★★ **Unaided, no reachable frame had occlusion** —
  rooms 1, 3 and 5 gave **1,353 frames with a maximum rejection of 5 pixels**, room 1 at **97% zero**.
  **The ego placement is what made the corpus able to fail** (§3.C).
- **AC-7 [class: eye-gated] — ★★★★ PARTIAL. The images were delivered; "ANIMATING" WAS NOT.**
  ★★★★★ **CORRECTED after Jay read the first version of this report and said he expected a live run
  on the CoCo.** He is right and the first version of this AC overstated itself: the criterion says
  *"Jay sees a character partly behind scenery, **animating**"*, and what was delivered is **one
  still frame**. ★★★ **The cause is structural and is §3.F's finding: the integrated probe has no
  present path, so nothing has ever reached the CoCo3's screen.** What follows is what WAS
  delivered, and the §2P split is enforced by `comp_render.py` itself:
  - **committed (ours):** `docs/gates/p3b14-frame568.priority.png` — the priority buffer, one colour
    per band; `docs/gates/p3b14-frame568.outcome-overlay.png` and `…frame569…` — **the sprite's
    per-pixel outcome**: GREEN drawn / RED refused / AMBER control-line, over the dimmed depth map.
  - **NOT committed (game content):** `build/eye-gate/p3b14-frame568.coco3.png` (the composited frame)
    and `…oracle.png` (the oracle's rendering). **Sent to Jay directly.**
  ★★ **Launch path `poke`.** ★★★ **`25.3` is "pending Jay" and is NOT self-certified** — per §3 of
  CLAUDE.md I have not interpreted the PNG pixels; the figures above are the tool's own counted text
  output.
  ★★★★★ **What is still owed on this AC:** a live run on the CoCo3 showing the character in motion.
  It needs a present added to `p3b_probe.s` (§3.F) — **target code in the probe every P3b timing
  figure was taken against**, so it is not something to bolt on at the end of a dispatch that ended
  at a stop. **Recorded as owed, not quietly reclassified as satisfied by a still.**
- **AC-8 [class: state-comparable] — RECORDED, deliberately not removed.** `vm_lastsec` (`rmb 4`,
  `vm_cycle.s:284`) and `vm_lastcyc` (`rmb 4`, `:285`) are referenced **only** by their declarations
  and the four zeroing `std`s at `:124-127`. **8 bytes of storage plus ~12 bytes of reset code, all
  dead.** ★★★ **Why recorded and not removed:** removing them changes `vm_probe.bin`, and **this
  dispatch has no VM-gate AC** — P4.9 needed a 9/9 run with an empty exclusion set to justify touching
  that binary, and doing it here would ship a gate-affecting change under a task that does not gate it
  [L-54: A's residue must not ride in on B's accounting]. **It is A's residue and belongs to a task
  that re-runs A's gate.**
- **AC-9 [class: state-comparable] — four things this dispatch did not anticipate.**
  (1) ★★★★★ **A faulted gate artifact was sitting in the tree** and only the next task's §4 caught it
  (§4). **The check works; the gap is that nothing re-checks at task END.**
  (2) ★★★★★ **The alignment problem did not need solving.** The premise that guest and oracle clocks
  must be reconciled was wrong for this gate — the pipeline stages one side's inputs into the other
  (§3.A). **The dispatch, P4.9 and I all carried the same wrong premise.**
  (3) ★★★★ **The rooms have occluding scenery and the ego never goes there** — 1,353 frames, max 5
  rejected pixels, while the priority map offers 600 (§3.C).
  (4) ★★★★ **Rejection count is the wrong selector for a boundary fault** — 2,184 rejected pixels
  across the staged set, and only 2 frames catch a `bhs`/`bhi` swap (§3.D).
  (5) ★★★★★ **The integrated probe has no present path and the CoCo3's screen has been blank for
  every P3b run** (§3.F). **Found only because Jay said he expected a live run** — no AC in this
  dispatch or P4.9's would have surfaced it, because both are satisfied by plane bytes. ★★★ **The
  phase has been calling plane dumps "the visual" throughout**, and the distinction between "the
  bytes the guest produced" and "the machine displaying them" went unstated until a human asked for
  the second one.
- **AC-10 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*§4 — the contradiction, and the repair:*
```
gate   artifact                  shipped    fresh  verdict
vm     build/vm_probe.bin           8712     8712  ★★★ DIFFERS -- the gate is testing something else
faulted hash : 313D5F30C3D31F3F8D7869B1C827BCE81E704AC9E83CB908EBF3792E58BBADAC
clean hash   : 1B5EA3B7F5EF0BAB97262C5145DBDA6D4D2C1D02A8EEBC7E22E484999CD298D9
vm     build/vm_probe.bin           8712     8712  identical
.gitignore:2:/build/	build/oracle_room1/frame000.after.visual.bin
.gitignore:45:oracle/dumps/*	oracle/dumps/frames-X/frame000.after.visual.bin
```

*§4 — hal-sync, all three:*
```
coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
```

*AC-6 — the census WITHOUT ego placement (rooms 1, 3, 5; re-sorted on the rejection column):*
```
KQ1room1: 566 frames scored; 16 show PARTIAL occlusion; 550 have ZERO priority rejections (97%)
          best frame 291: REJECTED 3, written 354, sprites 4
rooms 1+3+5 combined: 1353 frames, MAXIMUM rejection = 5 px (KQ1room3 frames 121-132)
```

*AC-6 — the room's own priority map says the scenery exists:*
```
room 1, frame283.before.priority.bin -- bands present [0,1,2,3,4,6,11,13,15]
   band 13 : 10149 px (37.8%)
top standing positions by pixels the priority test would REFUSE:
     x      y   band    refused
   132     60      8        600
```

*AC-6 — the corpus WITH the ego placed at (132, 60):*
```
576 frames scored; 34 have ZERO priority rejections (6%)
best frames 288/234/233/282…: REJECTED 94, written 243-263, sprites 4
```

*AC-3 — the independent model, and the staging:*
```
KQ1ego1  candidates  576   staged  24   (model self-check passed on all candidates)
   staged frames exercise: tested 17184  written 6116  rejected-by-priority 2184  control-branch 584
```

*AC-4 — the gate, per frame:*
```
built build/comp_probe.bin  [source-tree fc0acf1d9f9f (8 files)]
frames: 24 from build/comp_stage/KQ1ego1
program 967 bytes at $0700
guest at its gate (frame 5) -- all-RAM live
  frame 551   4 sprites  BOTH PLANES IDENTICAL
  frame 552   4 sprites  BOTH PLANES IDENTICAL
  frame 525   4 sprites  BOTH PLANES IDENTICAL
  frame 550   4 sprites  BOTH PLANES IDENTICAL
  frame 568   4 sprites  BOTH PLANES IDENTICAL
  frame 569   4 sprites  BOTH PLANES IDENTICAL
  frame 476   4 sprites  BOTH PLANES IDENTICAL
  frame 477   4 sprites  BOTH PLANES IDENTICAL
  frame 478   4 sprites  BOTH PLANES IDENTICAL
  frame 479   4 sprites  BOTH PLANES IDENTICAL
  frame 480   4 sprites  BOTH PLANES IDENTICAL
  frame 485   4 sprites  BOTH PLANES IDENTICAL
  frame 486   4 sprites  BOTH PLANES IDENTICAL
  frame 487   4 sprites  BOTH PLANES IDENTICAL
  frame 488   4 sprites  BOTH PLANES IDENTICAL
  frame 489   4 sprites  BOTH PLANES IDENTICAL
  frame 494   4 sprites  BOTH PLANES IDENTICAL
  frame 495   4 sprites  BOTH PLANES IDENTICAL
  frame 496   4 sprites  BOTH PLANES IDENTICAL
  frame 497   4 sprites  BOTH PLANES IDENTICAL
  frame 498   4 sprites  BOTH PLANES IDENTICAL
  frame 503   4 sprites  BOTH PLANES IDENTICAL
  frame 504   4 sprites  BOTH PLANES IDENTICAL
  frame 505   4 sprites  BOTH PLANES IDENTICAL
★ 24 frames: 24 identical, 0 divergent
```

*AC-5 — the same 24 frames against a priority-inverted build:*
```
build/comp_probe_fault.bin  967 bytes   (-DCOMP_FAULT: `bhs` for `bhi` in the priority test)
  frame 568   4 sprites  ★★★ 5 byte(s) differ; first in visual at row 158 col 41
  frame 569   4 sprites  ★★★ 6 byte(s) differ; first in visual at row 158 col 40
★ 24 frames: 22 identical, 2 divergent
```

*AC-7 — the images, and the §2P split the tool enforces:*
```
frame 568 of KQ1ego1 -- sprite outcome overlay
  GREEN  drawn   :   221   the priority test ALLOWED it (scenery behind)
  RED    refused :    91   the priority test REFUSED it (scenery in front)
  AMBER  control :    25   drawn via the control-line branch
  sprite 0 (object 0, priority 6): rows 29-60, columns 133-137
  sprite 1 (object 11, priority 14): rows 157-160, columns 41-53
  sprite 2 (object 12, priority 14): rows 158-161, columns 33-45
  sprite 3 (object 1, priority 15): rows 8-17, columns 5-45

frame p3b14-frame568
  guest visual vs oracle visual: IDENTICAL
  ★ GAME CONTENT -- NOT committed (§2P), surfaced for Jay:
      build\eye-gate\p3b14-frame568.coco3.png
      build\eye-gate\p3b14-frame568.oracle.png
  ★ OURS -- committed to docs/gates/:
      docs\gates\p3b14-frame568.priority.png
  priority bands present in this frame:
       0  CONTROL     529 px      4  depth      7742 px     13  depth     10149 px
       1  CONTROL     208 px      6  depth      2049 px     14  depth        54 px
       2  CONTROL      27 px     11  depth      3942 px     15  depth       761 px
       3  depth      1419 px
```

*§4 — `p3b_room.lua` still reproduces:*
```
room 1  sprites 4   composite 0.03929 s/cycle
room 3  sprites 2   composite 0.02107 s/cycle
room 2  sprites 0   composite 0.00002 s/cycle
```

**25.2 bundled-artifact grep:** N/A — no sibling artifact was imported. The staged frames are the
oracle's own output, staged by `comp_stage.py` into gitignored `build/`, and no game data is committed
(§2P; `check-ignore` output above).

**25.3 operator-runtime-smoke:** ★★★★ **INCOMPLETE — `static-png`, not a live gate.** Launch path
**`poke`**. The composited frame and the oracle's rendering were **sent to Jay**; the priority and
outcome overlays are committed under `docs/gates/`. ★ Not self-certified.

★★★★★ **Recorded per CLAUDE.md §4's launch-path rule, which POP wrote for exactly this:** *"A static
PNG is NOT a live gate… it verifies ENDPOINTS only and CANNOT show motion"*, and *"a motion-bearing
effect gated only on `static-png` is an INCOMPLETE gate and must say so."* **A character animating
behind scenery is motion-bearing.** ★★ **The first version of this report recorded 25.3 as "pending
Jay" without that qualifier, which was the wrong label** — pending implies the gate is formed and
awaiting an observer. It is not formed: **the machine cannot currently display anything** (§3.F).

---

### 6 — Reactive deviations and route accounting

1. **A faulted `vm_probe.bin` was found and restored before any measurement** (§4). It was my residue
   from P4.9, and restoring it is a repair this dispatch did not ask for.
2. **The anchor is not any of §2's four named candidates.** The dispatch offered a VM state anchor, the
   room transition, a shared origin, or "something else the alignment work names." **It is the fourth:
   the frame's input tuple**, and it makes the other three unnecessary for this gate rather than
   better or worse than them.
3. **The corpus was built, not found.** Rooms 1/3/5 alone could not fail (§3.C), so the ego was placed
   using the room's own priority map. **That is a change to the oracle run's configuration, not to the
   engine** — `coco_ego_x/y` is patch 0008's own switch.
4. **AC-8 was recorded rather than removed**, with the reason in AC-8.
5. **Gate images were consolidated into `docs/gates/`** rather than a new `dist/p3b-eye-gate/`, since
   `docs/gates/` is the established home (it already holds `pq1-frame306.priority.png` and a README).
   §2F, single home.
6. **`comp_pick.py`'s ranking was worked around, not fixed** — every ranking here was re-sorted on the
   rejection column. Fixing it is P4.9's follow-up 3 and belongs to a task that gates it.

7. ★★★★★ **THIS REPORT WAS CORRECTED AFTER JAY READ IT.** Its first version recorded AC-7 as
   "DELIVERED TO JAY, pending his eye" and 25.3 as "pending Jay". Jay replied that he expected a
   live run on the CoCo. **He was right, the AC says "animating", and a still does not satisfy it.**
   The investigation that followed produced §3.F — the probe has no present path — which is the
   largest finding in this report and **was surfaced by a human noticing a gap no AC checked.**
   ★★ **Corrections are marked in place rather than silently applied**: AC-7, 25.3, §1, AC-9(5),
   §7 and §8 all carry what they previously said.

**ROUTE ACCOUNTING.** No route was proposed in advance. Delivered: the anchor and its justification,
the second-quantity demonstration, the 24/24 gate, the fault proof, the occlusion corpus, and three
still images. ★★★★ **NOT delivered: AC-7's animating run on the CoCo3** — and the first version of
this report did not say so plainly enough (§6.7). **Not attempted:** the present path itself,
removing A's dead storage, fixing `comp_pick.py`, the surviving resource copy, the cycle-rate
decision.

---

### 7 — Uncertainty flags

- ★★★★★ **§3.F's second claim is inference, not measurement.** That `HAL_gfx_swap` targets RAM the
  p3b composite never writes comes from reading `p3b_probe.s:54` (`FB_BASE equ MAP_PHASE_WIN`)
  against `gfx.s:475-479` (`GFX_DB_A_BLOCK`/`GFX_DB_B_BLOCK`). **It was not run.** The first claim —
  that p3b has no present of any kind — IS measured, by grep. **Verify the second before building on
  it** [L-53].
- ★★★★ **AC-7 is not merely unobserved, it is unformed.** No amount of Jay's attention closes it
  until the probe can present. **Do not read "pending Jay" anywhere in this phase's history as
  meaning the image exists and awaits an eye** — for the animating gate, it never has.
- ★★★★ **AC-5's margin is two frames.** The gate catches a priority-boundary fault, but 22 of 24
  frames do not. **A corpus selected by rejection count is not selected for boundary coverage**
  (§3.D), and no tool in the tree ranks by equal-band adjacency. **This is the weakest link in an
  otherwise closed gate.**
- ★★★ **The 24 frames come from one room of one title**, with the ego artificially placed. They prove
  the compositor reproduces the oracle on frames containing occlusion; they do not sample the corpus.
- ★★★ **`comp_render.py` was given the oracle's `after` planes as the guest's output.** That is
  legitimate **only because AC-4 proved them byte-identical** — the sweep compares in-Lua and does not
  dump guest planes. The image is what the guest produced because the bytes are the same bytes; it is
  not an independent capture, and it is labelled as such here rather than in the filename.
- ★★ **The ego placement perturbs the run** — patch 0008 says a jumped run's `vmstate.txt` is not a
  valid baseline, and placing the ego compounds that. **Nothing in this report uses that run's
  vmstate**; only its composited frames, which are the oracle's own output either way.
- ★★ **Only frames 476–569 were staged** (the highest-scoring 24 of 576). The other 552 were scored
  but not gated.
- ★ **`reg_discipline.py` still reads 8 against a recorded 5** [AD-104]; `scummvm.pin` still records
  five patches against eight applied. Carried, untouched (§11).

**Triggers:** **1 does not fire** — an anchor was justified. **2 does not fire** — both second
quantities agree. **3 does not fire** — AC-4 did not diverge at the anchor. **4 does not fire** — a
frame with occlusion was reached, though only after the ego was placed (§3.C). **5 does not fire** —
the fault is detectable on this corpus, with the margin stated.

---

### 8 — Follow-up candidates

1. ★★★★★ **Add a guarded present to `p3b_probe.s` and close AC-7 with a live animated run.** §3.F has
   what it needs and what to verify first (that `HAL_gfx_swap` targets the wrong RAM for p3b). ★★
   **It changes the probe P3b's timing figures come from**, so it wants its own dispatch with a
   re-run of those figures — the gate build must come out byte-identical and be shown to.
2. ★★★★ **Rank frames by equal-band adjacency, not rejection count** — AC-5's two-frame margin is the
   symptom, and a boundary fault needs a boundary-aware selector.
3. ★★★★ **Re-check gate artifacts at task END, not only at task start.** P4.9 left a faulted binary
   and nothing noticed until §4 of the next task.
4. ★★★ **The surviving resource copy** — 63.6% of KQ3's extra cost [AD-106]. §11 kept it out; it is
   now the largest addressable term.
5. ★★★ **Remove `vm_lastsec` and `vm_lastcyc`** (8 bytes + ~12 of reset code) in a task that re-runs
   the VM gate.
6. ★★★ **Fix `comp_pick.py`'s sort key** (carried from P4.9).
7. ★★ **Widen the occlusion corpus** beyond one room of one title before the compositor is called
   gated across the corpus.
8. ★★ **Retire or repair `VM_PACEONLY`, `ABL_NOCOPY`, `ABL_NOFETCH`** (carried from P4.8).

---

### 9 — User interaction during task

`None.`

### 10 — Candidate(s) captured this task

Pushed to `methodology-candidate-pool` **`main`**, `seeds/AGI/live/`:

- `2026-09-05-a-comparison-may-need-shared-inputs-rather-than-a-shared-clock.md` — §3.A: two runs were
  assumed to need clock alignment when the pipeline already supplied one side's inputs to the other.
- `2026-09-06-a-test-corpus-that-cannot-fail-must-be-built-not-found.md` — §3.C: the rooms contained
  occluding scenery and the actor never walked to it; the corpus had to be constructed against the
  data's own map.

★ **INFRA.1's two rows remain owed** (its §10).

### 11 — Commit

Committed on `wip` and pushed to `origin/wip`, staged by explicit path per §2E: the three
`docs/gates/*.png` and this report. ★ **No game content is in that list** (§2P); the composited frames
stayed in gitignored `build/` and went to Jay directly.
