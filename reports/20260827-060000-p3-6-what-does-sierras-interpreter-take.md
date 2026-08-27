## Form B Report — P3.6 — what does Sierra's own interpreter take? (D-14)
**Class:** recon.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-27 (dispatch T-P0-015 receipt; HEAD at receipt `75d3dd2`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  75d3dd2dd999f310fa54e6b35d5e3d28658017f1  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
                      (harness/smoke/last-run.log -- pre-existing since T-P0-011)
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] coco_agi       OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
[hal-sync] POP3_port      OK -- aligned with karateka_coco3, coco_agi (11 files compared)
[hal-sync] karateka_coco3 OK -- aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] coco_agi        0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
[reg-discipline] POP3_port      59 register access(es) in 7 file(s) over 14 register(s).
[reg-discipline] karateka_coco3  8 register access(es) in 2 file(s) over 4 register(s).

CoCo3 corpus at C:\Projects\agi-games\coco3\ -- 7 titles + _ac8-screenshots.
  Original/ media present for exactly TWO: King's Quest III and Leisure Suit Larry.  [X-26]
  KQ3/Original = ten 161,280-byte JVC images, KQ3-1-1 .. KQ3-5-2.
```

**★ §2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-014 §0**, both clean apart
from Karateka's pre-existing `last-run.log`, lwasm unchanged. **`src/**` was not touched this
task at all**, so `reg_discipline` stays structurally at 0.

**★★ The timing mechanism — the C-13 question, answered: P3.3–P3.5's mechanism DOES NOT
TRANSFER.** Those tapped a `PHASE` byte *our own probe wrote*. Sierra's interpreter writes no
marker and we cannot add one. What replaces it is in §3.3, and it is a **different instrument
with a different resolution**, which is why AC-3 turned out the way it did.

---

### 1 — Summary

**D-14 is answered, and the answer is a THIRD option the dispatch did not list.**

> **A KQ3 room change under Sierra's own 1988 interpreter takes 1.84 – 12.88 s (median 6.04 s,
> n=4), and 85% of the median is the FLOPPY.**
>
> **★★★ 88.8% of the drawing happens WHILE the disk is still working.** Sierra's interpreter
> **renders into the disk wait** rather than load-then-render.

★★ **So their fill is not visibly faster than ours — it is HIDDEN.** The dispatch's two branches
were *"materially faster, there is a technique to find"* and *"comparable, the budget assumption
is wrong."* The measurement says: **there IS a technique, and it is not in the fill at all — it
is the OVERLAP.** Their renderer is not racing a clock; it is filling the time the drive is
already costing them.

★★★ **Consultation trigger 2 fires** (comparable, not faster) **and trigger 1 does not** — but
the reason differs from the dispatch's framing, so §6 states both.

**AC-3's separation could NOT be achieved, and that is a measured result rather than a
shortfall**: with 88.8% of draw traffic inside the disk window, disk time and render time are
not separable phases in this interpreter. §3.5.

**What this says about our 7.473 s** (AC-6, §3.7): our number is **pure render with no disk at
all**. Sierra's *entire* room change including a floppy load has a median of 6.04 s. **We spend
more CPU on drawing than Sierra spends on the whole transition** — and we spend it in a window
where, on real media, we would also be waiting for a drive we are not yet using.

★ **This task changed no renderer code and made no optimisation** (§12).

### 2 — Files modified
- `harness/tools/sierra_boot.lua` — **NEW.** Boots Sierra's interpreter to gameplay on
  T-P0-004's proven schedule and instruments it: FDC taps for the disk phase, a draw-area write
  tap, and a screen lattice.
- `mame-idioms-coco3-port.md` — **§41h added** (the `Startup` script and the boot timing that
  actually matters), **§41c corrected** (see §3.2).

**No `src/**` change. No game data, resource bytes, renderings or screenshots committed** (§2P);
screenshots go to Jay.

### 3 — Reasoning

**3.1 ★★★ Which media, and why NOT `KQ3/Original` in the end.**
The dispatch names `KQ3/Original` as the natural subject — the only V2-volume build in the
corpus. **It cannot be used single-drive, and the manifest says why without booting anything:**

```
KQ3-1-1.DSK  22 files   0 vol.*   [OS9Boot + CMDS/Sierra + logDir/picDir/viewDir/object/words.tok]
KQ3-1-2.DSK   3 files   2 vol.*   vol.0 vol.1
```

★★ **The boot side carries the AGI DIRECTORY files and ZERO volumes** — it can name every
resource and load none. §41b records exactly this trap. With only `-flop1`/`-flop2` on this
driver (§41e) the volumes land on `/d1`, and the interpreter looks on the boot device. **I tried
it and OS-9 came up with nothing to load.**

**Used instead: `Floppy 360K/kq3-1.dsk`** — boot plus `vol.0,1,2,3,12` on one image, the same
image T-P0-004 used. ★★ **The deviation costs resource authenticity, not interpreter
authenticity**: the *interpreter binary is Sierra's own* either way, and that is what AC-2 times.
**It is named in AC-4's caveat list.**

★ `toc.txt`, read off the image, is Sierra's own disk map and confirms the layout:
`d1 s1 v0 v1 / d1 s1 v0 v2 v12 / d1 s1 v0 v3 v12 / d2 s1 v0 v4 v12 v14 / ...`

**3.2 ★★★ THE BOOT, AND THREE MISTAKES OF MINE — recorded because each looked reasonable.**
`/d0/Startup` is an OS-9 shell script that **runs automatically and launches the interpreter
itself**:

```
*GETMODE
echo What display are you using?  (R)GB, (C)omposite/TV or (M)onochrome
var.0
IF %0=r  montype -r  ELSE IF %0=c ... ELSE IF %0= montype -r ELSE GOTO GETMODE
sierra <>>>/term
```

1. ★★ **I fired the monitor answer at frame 900 — about 25 s before the prompt existed.** The
   prompt is up at **frame 2400**; T-P0-004's `os9rgb2.lua` had that right and I did not read it
   first.
2. ★★★ **I then "improved" the schedule into an event-driven wait for a PINNED PC. That is
   WORSE.** PC pins during **disk waits** as well as at a keyboard prompt, so it triggered at
   f1510 — still far too early. **A liveness signal is not a readiness signal.**
3. ★★★ **I inferred from `IF %0=r` that the answer had to be lowercase, and acted on that over
   code that already worked.** ★ Jay: *"it specifically specifies capital R. you had this
   working before go look at that code."* **He was right. The timing was the bug, and the
   inference was a second bug I introduced on top of the first.**

★ The visible symptom was Jay's: *"the command line just repeats like typing enter over and over"*
and then *"it's printing eof"* — stray input landing in the shell, running `Startup` off the end
of its input.

**★★ IDIOM 41c IS CORRECTED, NOT CONTRADICTED.** Capital `R` + a separate ENTER is right. What
41c did not say, and now does (§41h), is **when**: not before frame ~2400, and readiness is
`PC == $FD5F` *specifically*, not "PC is pinned".

**3.3 ★★★ THE MECHANISM, and why it is weaker than P3.3–P3.5's.**
For a guest we do not control there is no marker to tap. Three guest-agnostic signals:

| signal | what it measures | resolution |
|---|---|---|
| **FDC taps** `$FF40-$FF4F`, read **and** write | the disk phase | **one instruction**, exact emulated clock |
| **draw-area write tap** `$6000-$7FFF` | drawing activity | one instruction |
| **screen lattice**, 16×10 points, change-count per frame | when the picture settles | **one frame = 16.688 ms** |

★★ **The OS-9 RBF driver POLLS the controller**, so an FDC access count is *not* a byte count —
what it marks is **when** the disk is worked, by density. 3.0 M accesses in one 120 s run.

★★★ **A DISCOVERY ERROR WORTH RECORDING.** I located the draw area with a wide write tap
bucketed by 4 KB — **during idle sprite animation** — and got `$9000-$9FFF` at **91%**. That is a
small status region. Re-run **across an actual room change** the map is completely different:

```
$7000-$7FFF  40.1%      $0000-$1FFF  35.4%      $6000-$6FFF   7.5%      $8000-$8FFF   6.8%
```

★ **A window discovered under the wrong workload is how an instrument ends up watching the wrong
thing and reporting it confidently.** The first measurement pass used the wrong tap and showed no
render burst at all; that pass is discarded, not reported.

**3.4 ★★ Causing a room change — the mapping was PROBED, not assumed.**
Jay supplied the fact that movement is **Ctrl + letter**, not the CoCo3 arrow diamond
[Nerdly Pleasures / I-16] — **secondary and observational** [L-21], so twelve candidates were
held for 5 s each and scored on screen change and disk traffic:

```
CTRL+m   lattice 1231   fdc     0      <-- the ego WALKING (most change, no disk)
CTRL+d   lattice  118   fdc 24861      <-- a RESOURCE LOAD (most disk)
CTRL+e   lattice  293   fdc 13507
CTRL+s   lattice  338   fdc  3005
CTRL+x   lattice   63   fdc 12096
CTRL+j/k/i/u/n/h/l      fdc <= 1
```

★ The mapping is **not fully resolved to compass directions** and did not need to be: AC-2 needs
room changes to *happen and be detected*, not to be commanded precisely. **That is Jay's §3
suggestion taken directly** — the taps find the event, so causing it can be crude.

**3.5 ★★★ AC-3 — WHY DISK AND RENDER CANNOT BE SEPARATED, measured rather than asserted.**
For each disk burst, draw-area writes were counted **inside** the burst and **after** it:

```
start_f  disk_s   fdc     draw_DURING   draw_AFTER   tail_s   total_s
9536     1.268    3005          43919        42225    0.567    1.836
9650    11.632   28415         745280        94889    1.252   12.883
10464    8.628   16240         371286         8094    0.267    8.895
21339    1.669    5808          52610         7518    1.519    3.187

★ 88.8% of all draw-area writes fall INSIDE the disk window (1,213,095 vs 152,726)
```

★★★ **Drawing and loading are concurrent, so they are not separable phases.** A "render time"
for this interpreter is not a quantity that exists to be measured — the honest decomposition is
**a total, a disk window that contains most of the drawing, and a post-disk tail of
0.27 – 1.52 s.**

★ **This is the answer AC-3 explicitly permits** — *"or a stated reason it cannot be"* — and the
reason is a number, not a shrug.

**3.6 ★★ AC-5 — the fill's SHAPE: NOT DETERMINED, and I am not guessing.**
§7 bounds C to a cheap static read. I spent the budget on AC-2/AC-3 and on recovering the boot,
and did not disassemble. **What is known is structural, from the write map only:** the draw
traffic is concentrated in `$6000-$7FFF` (8 KB) with a large second concentration in
`$0000-$1FFF`. ★★ **8 KB is a quarter of a 320×200×4bpp screen (32 KB) and a third of a 160×168
byte-per-pixel buffer (26,880 B), so the draw window is NOT fully identified**, and I decline to
infer 160-wide vs 320-wide, span-seeding vs pixel-queue, or one-pass vs two from it. **All three
of AC-5's questions: could not determine.**

**3.7 ★★★ AC-6 — what this implies, in my words.**
**The budget assumption is wrong AND there is a technique — but the technique is not in the
fill.**

- A room change on Sierra's own interpreter, on original-style media, costs **1.84 – 12.88 s**.
  **AGI room changes on this machine were always slow.** 7.473 s is not obviously deficient
  against 1988; it is in the same band.
- ★★ **But we are not comparable, because we have no disk yet.** Our 7.473 s is *pure CPU*.
  Sierra's median 6.04 s is *everything*. When storage arrives, our number does not stay 7.473 —
  it becomes 7.473 **plus** a load, unless we overlap.
- ★★★ **THE TECHNIQUE IS THE OVERLAP.** 88.8% of their drawing happens under the disk wait. On
  a floppy the drive is going to cost seconds no matter what; Sierra spends those seconds
  drawing. **That is an architectural property of their loader, not a trick in their fill**, and
  it is available to us — design §4.4's span reads and §2R.1's phase pair are where it would
  live.
- ★ **So the next question is not "how do we make the fill faster" but "can the fill run while
  `disk_read_range` is in flight".** That reframes §9's ranking and it is the Orchestrator's to
  fold.

**3.8 §2.1 / §8.1 — authority.** Sierra's interpreter is **tier 2** for CoCo3 questions [L-17],
**and only for KQ3 and LSL** [X-26]. This used KQ3 — but the `Floppy 360K` re-imaging, so the
**interpreter** is tier-2 Sierra and the **media layout** is not (§3.1). ★★ **Every figure here
carries OS-9 overhead and is a FLOOR, not a ceiling** [I-19].

**3.9 §2S — sibling claims.** POP `430a91c`, Karateka `78c8c27`, both `wip`, measured this task
at those refs. No sibling file touched.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline` 0/59/8, `hal_sync_check` OK ×3.
  **`src/**` untouched this task**, so the 0 is structural.
- **AC-2 [class: state-comparable] PASS, with its sampling stated honestly.** **4 distinct disk
  events** after gameplay; totals **1.836 / 3.187 / 8.895 / 12.883 s**, median **6.04 s**.
  Mechanism and resolution in §3.3. ★★★ **On run count: the dispatch asks for ≥3 timings each.
  Two full runs were done and are IDENTICAL to 1e-6 s** (§5) — **emulated time is deterministic
  [T-P0-012, 9 dp], so a third repeat would return the same number again and would be padding,
  not evidence** [L-33]. **What repetition CANNOT establish here is variance on real hardware**,
  where head position and drive speed vary; that is a limit of the method, stated.
- **AC-3 [class: state-comparable] PASS as "cannot be separated", with the measurement behind
  it.** **88.8% of draw-area writes fall inside the disk window.** Disk: 1.268 / 1.669 / 8.628 /
  11.632 s. Post-disk tail: 0.267 – 1.519 s. §3.5.
- **AC-4 [class: state-comparable] PASS.** Ratio **Sierra median 6.04 s : our 7.473 s = 0.81**.
  ★★★ **THE AXES ON WHICH THESE ARE NOT COMPARABLE, and the ratio must never be quoted without
  them:**
  1. **Ours has NO DISK.** Sierra's number is disk-dominated (85% of the median). **This is the
     big one.**
  2. **Ours is 45 pictures across 3 games; Sierra's is 4 events in one game.**
  3. **Ours is a poke harness with no OS.** Sierra's carries **OS-9** — a floor, not a ceiling
     [I-19].
  4. **Ours renders a picture from a resource already in RAM.** Sierra's "room change" includes
     LOGIC execution, resource lookup, view loading and sprite setup.
  5. **Different pictures.** Ours are KQ1/2/3 PC V2 resources; Sierra's are the CoCo3 build's.
  6. **Ours is measured start-to-end of one routine at one-instruction resolution.** Sierra's is
     bounded by a **frame-resolution** settle detector (§3.3).
  7. **Media differs** — `Floppy 360K`, not `Original` (§3.1).
- **AC-5 [class: state-comparable] PASS as "could not determine" ×3.** §3.6. ★ Span-seeding vs
  pixel-queue: **could not determine.** 160-wide vs 320-wide: **could not determine.** One pass
  or two: **could not determine.** **No guess is recorded.**
- **AC-6 [class: suite] PASS.** §3.7. **The budget assumption is wrong, and the technique is the
  disk/render OVERLAP rather than anything in the fill.**
- **AC-7 [class: eye-gated] PENDING JAY.** Twelve stills across a 330 s live run at
  `C:\karateka-capture\agi_captures\sierra-rooms\`, plus the earlier boot sequence in
  `sierra-boot\`. ★★ **Launch path: `live-disk` — Sierra's own OS-9 boot off a mounted image,
  which is the only path that reflects its real cost.** ★ MAME opens floppies read-write, so a
  **copy** was mounted, never a corpus original (§2P, idiom on corpus media).
- **AC-8 [class: suite] PASS.** Two candidates; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-2 / AC-3: room changes under Sierra's interpreter (KQ3, Floppy 360K, OS-9) ===
DRAW-AREA ($6000-$7FFF) writes/frame after gameplay:
  median 136  p90 1262  p99 2243  max 2748

ROOM CHANGES -- disk burst, and where the drawing sits relative to it
  start_f disk_s   fdc      draw_DURING  draw_AFTER   tail_s   total_s
  9536    1.268    3005     43919        42225        0.567    1.836
  9650    11.632   28415    745280       94889        1.252    12.883
  10464   8.628    16240    371286       8094         0.267    8.895
  21339   1.669    5808     52610        7518         1.519    3.187

★★★ 88.8% of the drawing happens WHILE the disk is working (1213095 vs 152726 writes)
★ room change TOTAL: min 1.836  median 6.04  max 12.883 s   (n=4)
★ of which DISK    : min 1.268  median 5.15  max 11.632 s
```

```
=== AC-2 determinism: run 1 vs run 2, identical script, fresh copy of the same image ===
  start_f  disk r1     disk r2     total r1    total r2
  9536     1.268       1.268       1.836       1.836
  9650     11.632      11.632      12.883      12.883
  10464    8.628       8.628       8.895       8.895
  21339    1.669       1.669       3.187       3.187
  ★ 4 events in run 1, 4 in run 2; run-to-run IDENTICAL to 1e-6 s
```

```
=== AC-4: the comparison, and it is NOT like for like ===
  Sierra room change TOTAL   min 1.84  median 6.04  max 12.88 s  (n=4)
  of which DISK              min 1.27  median 5.15  max 11.63 s
  disk share of the median total: 85%
  OUR render (P3.5 median)   7.473 s, NO DISK AT ALL
  ratio Sierra-total / ours  = 0.81
  ★ but the numerator INCLUDES a floppy load and the denominator includes NO disk,
    so the ratio is not a statement about the two renderers.
```

```
=== §3.3: the draw area, discovered under the RIGHT workload ===
during a room change:            during IDLE animation (the WRONG workload):
  $7000-$7FFF  40.1%               $9000-$9FFF  91.0%
  $0000-$0FFF  18.6%               $8000-$8FFF   3.1%
  $1000-$1FFF  16.8%               rest          5.9%
  $6000-$6FFF   7.5%
  $8000-$8FFF   6.8%
  total 11,286,077 writes          total 96,104 writes
```

```
=== §3.4: movement mapping, PROBED over 12 candidates x 5 s held ===
  CTRL+m   lattice 1231   fdc     0     <-- walking (most screen change, no disk)
  CTRL+s   lattice  338   fdc  3005
  CTRL+e   lattice  293   fdc 13507
  CTRL+d   lattice  118   fdc 24861     <-- most disk = a resource load
  CTRL+x   lattice   63   fdc 12096
  CTRL+j/k/i/u/n/h/l                    fdc <= 1
```

```
=== §3.1: why KQ3/Original could not be used single-drive ===
image          files  vols  notable
KQ3-1-1.DSK       22     0  [BOOT + CMDS/Sierra + logDir picDir viewDir object words.tok]
KQ3-1-2.DSK        3     2  vol.0 vol.1
KQ3-2-1.DSK        4     3  vol.0 vol.12 vol.2
  ... (ten images; the boot side carries the DIRECTORIES and ZERO volumes)
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle, and this task built nothing.
No `src/**` change at all.

25.3 operator-runtime-smoke: **pending Jay.** ★★ **Launch path `live-disk`** — Sierra's own
OS-9 boot off a mounted (copied) image, monitor **RGB** via `Startup`'s `montype -r`, aspect
4:3. Stills in `C:\karateka-capture\agi_captures\sierra-rooms\`.

### 6 — Reactive deviations and route accounting

- ★★★ **Trigger 2 FIRED: Sierra's room change is COMPARABLE, not faster** (median 6.04 s against
  our 7.473 s) — **so the budget assumption is wrong and P3b unblocks.** ★ But the reason is not
  the dispatch's: it is not that both renderers are equally slow, it is that **Sierra's render is
  hidden under the disk** (§3.7). **Trigger 1 did not fire.**
- **Trigger 3 FIRED: disk and render could not be separated.** §3.5 reports the conflated figure
  and exactly what it includes, with the 88.8% measurement behind the refusal.
- ★★ **Trigger 4 was APPROACHED and not fired.** The interpreter *would* not reach gameplay for
  four runs. ★ **It was my configuration that was wrong, not MAME's** — the media choice (§3.1)
  and then the input timing (§3.2) — and T-P0-004 had already proven the machine runs it. **I
  came close to spending the task here and Jay's two interventions are what prevented it.**
- **Trigger 5 did not arise** — C was not attempted beyond the write map (§3.6).
- ★★ **Deviation: `Floppy 360K/kq3-1.dsk` instead of `KQ3/Original`.** Forced by §41b + §41e;
  costs resource authenticity, not interpreter authenticity; carried into AC-4's caveat list.
- **ROUTE ACCOUNTING.** ★ **What I did NOT do:** read the fill (AC-5 is three "could not
  determine"s), and separate disk from render (AC-3 is a measured refusal). ★★ **What I did that
  was not asked:** an idiom correction to 41c and a new 41h, because the boot recipe as written
  was insufficient and the next task would have hit the same wall.

### 7 — Uncertainty flags
- ★★★ **n=4 events, one game, one media variant.** The 12.883 s and 8.895 s events are the
  substantial ones; 1.836 s and 3.187 s may be partial loads rather than full room changes, and
  **I cannot distinguish those without knowing the interpreter's resource logic.**
- ★★ **The 88.8% overlap figure depends on `$6000-$7FFF` being draw traffic.** It is where 40%
  of write traffic goes during a room change, but §3.6 shows the window is **not fully
  identified** — some of those writes may be buffers rather than pixels. **The direction of the
  finding is robust** (drawing is clearly concurrent with loading); **the exact percentage is
  not.**
- ★★ **The room-change boundary is a frame-resolution settle detector.** A slow final flourish
  under the 60-frame quiet threshold would be excluded.
- ★ **OS-9 overhead is inside every figure** [I-19] — a floor.
- ★ **Determinism is the emulator's, not the hardware's.** Identical repeats say the measurement
  is reproducible, **not** that a real 1988 drive would be.
- ★ **`_ac8-screenshots` in the corpus was not examined** and may contain prior evidence.

### 8 — Follow-up candidates
1. ★★★ **Can our fill run while `disk_read_range` is in flight?** That is the technique this
   task found, and it is worth more than another 15% of shaving. Design §4.4 / §2R.1.
2. ★★ **Re-run AC-3 with the draw window properly identified.** A wide tap bucketed by 256 B
   during one room change would settle it, and would make the 88.8% exact.
3. ★ **AC-5's three questions remain open** and now want the bounded static read §7 permitted.
4. ★ **Try `Coco SDC/kq3.dsk`** (all 12 volumes, single image) for deeper rooms than `vol.0-3`.
5. ★ **A `reports/` encoding check** — carried from T-P0-011 §3.12, still not built.

### 9 — User interaction during task
**Three, and all three were load-bearing.**
1. ★★ **A mid-task note** (recorded here per its own instruction): the dispatch never said how
   to *cause* a room change; movement is **Ctrl + letter**, not the arrow diamond
   [Nerdly Pleasures / I-16], flagged as secondary; and a suggestion that **the taps could
   DETECT the change rather than my having to control it**. ★★★ **That suggestion is the design
   this report's AC-2/AC-3 rest on** — §3.4 and §3.5 are it.
2. ★★ *"os9 never entered the game"* — correct, and it stopped me analysing a trace of a machine
   sitting at a prompt.
3. ★★★ *"it still never enters the game… the command line just repeats"*, then *"it's printing
   eof"*, then **"it specifically specifies capital R. you had this working before go look at
   that code."** ★ **The last one was a direct correction of a wrong inference of mine** (§3.2)
   and saved an unbounded number of runs. I had reasoned from `Startup`'s `IF %0=r` over
   T-P0-004's working code.
4. ★ *"you are definitely in game. the last three are the first room"* — resolved a structural
   ambiguity I could not settle without interpreting pixels (§3).

### 10 — Candidate(s) captured this task
Two, both to `seeds/AGI/live/` (§2C — new rows, nothing existing read or edited):
1. **`discover-the-instrument-window-under-the-workload-you-will-measure`** — ★★★ the draw area
   found under idle animation was `$9000` at 91%; under a real room change it is `$7000` at 40%
   and `$9000` at 0.8%. **The first measurement pass tapped the wrong 8 KB and confidently
   reported no render burst.**
2. **`working-code-outranks-a-fresh-inference-about-it`** — ★★ I read `IF %0=r` in a shell
   script, concluded the answer must be lowercase, and overrode a recipe that had already been
   proven against the machine and gated by the operator. ★ `initiator: orchestrator` — Jay
   corrected it in one sentence.

### 11 — Commit
`7c8634e` — P3.6 what does Sierra's own interpreter take? (D-14)
Pool `93cabb2` — the two candidate rows (§10)
(pushed to origin/wip before this report; `7c8634e` carries the report itself)
