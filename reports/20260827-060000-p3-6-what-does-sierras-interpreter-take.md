## Form B Report — P3.6 — what does Sierra's own interpreter take? (D-14)
**Class:** recon.  wip.

> ★★★ **REWRITTEN 2026-08-27, superseding the filings at `7c8634e`, `0a5e217`, `95d902b` and
> `6b0cbeb`.** The first three carried findings that are withdrawn below; the fourth carried a
> correction that is **itself withdrawn**. **This version reports what is measured and marks
> D-14 unanswered.** The superseded text stays in git history rather than being rewritten,
> because §3.6–§3.9 are about the wrong answers and deleting them would delete the evidence.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-27 (dispatch T-P0-015 receipt; HEAD at receipt `75d3dd2`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim

```
coco_agi         wip  6b0cbeba887063bc1c14776f83083cb81d1f037b
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
                      (harness/smoke/last-run.log -- pre-existing since T-P0-011)
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared,
                 EOL/guard/export-placement normalised)
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.

CoCo3 corpus at C:\Projects\agi-games\coco3\ -- 7 titles.
  Original/ media present for exactly TWO: King's Quest III and Leisure Suit Larry.  [X-26]
```

**★ §2T — POP `430a91c` and Karateka `78c8c27` are unchanged from T-P0-014 §0**, both clean
(Karateka's one dirty file is the pre-existing smoke log). **No `src/**` file was touched at
all this task**, so `reg_discipline` stays structurally at 0.

---

### 1 — Summary

★★★ **D-14 IS NOT ANSWERED. Sierra's render time was not isolated, and three successive
attempts to state it were each confidently wrong.**

**What IS established, and survives every re-analysis:**

| | |
|---|---|
| **room changes measured** | **7**, each operator-confirmed by Jay walking in and out of rooms |
| **the count is robust** | the same 7, with the same lattice signatures (62/103/100/47/47/61/72 of 160), at **every** coalescing gap from 0.25 s to 3.0 s |
| **elapsed room change** | **3.54 s** at the tightest reading, **9.66 s** at the loosest — disk, LOGIC, setup and render together |
| **post-disk settle** | median **0.47 s**, and this figure is gap-independent |
| **VOFFSET writes during a room change** | **0** — it is not a VOFFSET page flip |
| **per-frame lattice movement** | max **16/160**, against **47–103** cumulative — Sierra draws **progressively** |
| **our renderer** | **7.473 s per picture**, 45/45 over 5 s, no disk at all [T-P0-014] |

> ★★ **The one comparison the evidence supports:** Sierra performs an **entire room change,
> disk included**, in **somewhere between half and one-and-a-third** of the time our renderer
> takes to draw **one** picture from RAM. **At the tight end that is damning. At the loose end
> it is inconclusive. No ratio between the two renderers is established.**

★★★ **WITHDRAWN — three claims, in the order I made them:**

1. **"88.8% of drawing overlaps the disk"** — measured on four events that were **menus in a
   single room**, not room changes (§3.6).
2. **"DISK 8.48 s (88%), strictly load-then-draw" and "Sierra's renderer is ~17× faster"** —
   the 8.48 s is an artifact of an **unstated parameter** (§3.8), and the 0.47 s it was
   divided into is a **post-disk tail**, not a measured render.
3. ★★ **"Sierra draws throughout the load, 6.7× above idle"** — the correction filed at
   `6b0cbeb`. **It rested on `$7000` being the draw window, which it is not** (§3.9).

★★★ **FOUR WRONG ANSWERS IN ONE TASK AND THEY ARE ONE ERROR, NOT FOUR.** Every one read a
signal on **one channel** as settling a question that channel cannot settle — and in every
case **the refuting data had already been collected and was sitting unexamined in the same
file.** §3.10.

★ **What the task does deliver** is the harness: a one-command launch, the working key
bindings, and — for the first time — **the offline instrument the numbers come from, tracked
rather than run inline and lost** (§2). That is what made the withdrawals findable.

### 2 — Files modified

- **`harness/tools/sierra_rooms.py` — NEW. ★★★ The instrument.** Finds and times room changes
  offline over `frames.csv`. Coalescing gap, settle, minimum lattice movement and minimum FDC
  are **named flags with stated defaults** — the parameter whose absence produced withdrawal 2.
- **`harness/tools/sierra_live.ps1` — NEW.** One-command launch. Copies the media (**never
  mounts a corpus original** — §2P, MAME opens floppies read-write), **seeds MAME's cfg into
  temp so a run cannot rewrite tracked inputs**, syntax-checks the Lua before handing the
  machine over, and prints the boot keys the operator must type.
- **`harness/mame-cfg/sierra-live/coco3.cfg` — NEW.** The working bindings: BREAK→DELETE, both
  `:ctrl_sel` ports Unconnected.
- **`harness/tools/sierra_live.lua` — NEW.** The observation harness. ★ **It sends no input**,
  by design. Detector rebuilt (§3.11).
- `harness/tools/sierra_boot.lua` — a **hazard banner**: its CTRL+letter probe must not be
  re-run with an operator at the keyboard, and it never worked anyway (§3.7).
- `mame-idioms-coco3-port.md` — §41h–§41k added.

**No `src/**` change. No game data, resource bytes, renderings or screenshots committed** (§2P).

### 3 — Reasoning

**3.1 ★★ Media — a deviation from the dispatch's `KQ3/Original`.**
The dispatch names `KQ3/Original`, the only non-repacked V2-volume build. **It cannot be used
single-drive**, and the manifest says so without booting anything:

```
KQ3-1-1.DSK  22 files  0 vol.*  [OS9Boot + CMDS/Sierra + logDir picDir viewDir object words.tok]
KQ3-1-2.DSK   3 files  2 vol.*  vol.0 vol.1
```

★★ The boot side carries the AGI **directory** files and **zero volumes** — it can name every
resource and load none (§41b). With only `-flop1`/`-flop2` the volumes land on `/d1` and the
interpreter looks on the boot device. Tried; OS-9 came up with nothing to load.

**Used instead: `Floppy 360K/kq3-1.dsk`** (`sha256[0:16]=20EA31A82087DA90`) — boot plus
`vol.0,1,2,3,12` on one image, the same image T-P0-004 used. ★ **The deviation costs resource
authenticity, not interpreter authenticity:** the binary is Sierra's own either way.

**3.2 ★★★ The boot, and three mistakes of mine.**
`/d0/Startup` runs automatically and **launches the interpreter itself** — there is no `Sierra`
command to type:

```
*GETMODE / echo What display are you using? (R)GB,(C)omposite/TV or (M)onochrome / var.0
IF %0=r montype -r ... ELSE GOTO GETMODE / sierra <>>>/term
```

1. ★★ I fired the monitor answer at frame 900 — **~25 s before the prompt existed.** It is up
   at frame 2400; T-P0-004's `os9rgb2.lua` had it right and I did not read it first.
2. ★★★ I then "improved" that into a wait for a **pinned PC. That is worse:** PC pins during
   **disk waits** as well as at a keyboard prompt. **A liveness signal is not a readiness
   signal.** The stray input landed in the shell and OS-9 printed `EOF` at a repeating prompt.
3. ★★★ I inferred from `IF %0=r` that the answer must be **lowercase**, and acted on that over
   code that already worked. Jay: *"it specifically specifies capital R. you had this working
   before go look at that code."* **He was right; the timing was the bug.**

★ All three are now moot for a re-run: `sierra_live.ps1` prints the two steps and the wait.

**3.3 The mechanism, and its resolutions.**
No marker can be added to the guest, so three guest-agnostic signals:

| signal | measures | resolution |
|---|---|---|
| FDC taps `$FF40-$FF4F`, read **and** write | the disk phase | **one instruction** |
| whole-map write tap, bucketed by 4 KB | where writes go | one instruction |
| VOFFSET tap `$FF9D-$FF9E` | VOFFSET page flips | one instruction |
| 16×10 `scr:pixel()` lattice | when the picture settles | **one frame, 16.688 ms** |

★★ The OS-9 RBF driver **polls**, so an FDC count is not a byte count — it marks **when** the
disk is worked, by density. ★★★ **And the write tap covers `$0000-$FEFF` only. §3.10 is about
what that leaves invisible.**

**3.4 ★★ A DISCOVERY ERROR (the first `$7000` mistake).**
The draw window was first located with a wide write tap **during idle sprite animation**:
`$9000-$9FFF` at **91%**. A narrow tap was pinned there, and the first measurement pass found
**no render burst at all** — a publishable-looking result. Re-running the same discovery
**across a real room change** gives a different map entirely:

```
during a room change:                     during idle animation (the WRONG workload):
  $7000-$7FFF  40.1%                        $9000-$9FFF  91.0%
  $0000-$1FFF  35.4%                        $8000-$8FFF   3.1%
  $6000-$6FFF   7.5%                        rest          5.9%
  total 11,286,077 writes                   total 96,104 writes
```

★ **The instrument was aimed at 0.8% of the traffic**, and the two totals differ by two orders
of magnitude — visible at the time, unexamined.

**3.5 ★★ VOFFSET flips exist — but not for room changes.**
Caught directly: `f2946 VOFFSET := $EC00`, whole screen changes two frames later, at the
title→game transition. Values seen: `$E000`, `$EC01`, `$0000`, `$EC00` — physical `$70000`,
`$76008`, `$00000`, `$76000`. ★★★ **Across all seven room changes, VOFFSET writes = 0.** The
interpreter has multiple buffers and flips between them for *some* transitions, and does **not**
use that path for a room change.

**3.6 ★★★ METHOD FAILURE 1 — a detector that could not tell a menu from a room.**
An earlier filing reported four room changes at a 6.04 s median. **They were menu events in one
room.** Jay checked the stills: *"same room."*

★★ The detector inferred the event from *"disk burst, then the screen settles"* — **and a menu
satisfies that exactly as well as a room change.** I never verified which I had.
★★★ **The refutation was already in my own trace:** the maximum lattice change in any frame was
**14 of 160**, where a full repaint moves most of them.

**3.7 ★★ Causing the room change — the operator drove it, and that was the unblock.**
Movement is Ctrl+letter, not the arrow diamond [Jay, Nerdly Pleasures / I-16 — secondary].
Twelve Ctrl+letter candidates were probed and none produced a transition. ★★★ **The cause was
not the keys: both `:ctrl_sel` ports default to `Joystick`, the interpreter polls the joystick,
and every key was arriving correctly on the CoCo3 matrix with nothing to respond to it.**
Setting both to Unconnected fixed movement immediately, and Jay then walked in and out of rooms.

★ **Input findings, measured by reading `:row6` live rather than assumed:**

```
CTRL, ALT, SHIFT, ENTER, letters, bare arrows   -> reach the machine
End, Insert                                     -> NEVER arrive (MAME's UI; 41f confirmed)
Left Alt                                        -> reaches MAME but WINDOWS grabs it (beep)
```

★★★ **And a harness rule paid for three times over:** `ioport_field:set_value()` is a
**permanent programmatic override**, not a momentary press — writing `defvalue` back marks the
field released but never returns it to the input system. Any script that touches `CTRL` owns
`CTRL` for the session, and since movement is CTRL+letter, that turns every keystroke into a
menu command. Jay: *"it's just blasting the menus and i can't do anything."* **Three trigger
designs failed for that one reason; the fault was never the trigger.**

**3.8 ★★★ METHOD FAILURE 2 — a figure that swings 4× on a parameter I never stated.**
The report filed at `95d902b` said **"DISK 8.48 s (88%), DRAW 0.45 s (5%)"**. ★★ **The 8.48 s
is what you get when up to 3 s of silence counts as "still loading".** A room load is not one
disk burst but a **cluster** of them with quiet gaps inside; how much silence you absorb is a
free parameter, and it was never named:

```
 gap_s   n  med_total  med_disk  med_draw  disk%  draw%
  0.25   7       3.54      1.97      0.47    56%    13%
  0.50   7       3.54      1.97      0.47    56%    13%
  1.00   7       3.54      1.97      0.47    56%    13%
  1.50   7       3.54      1.97      0.47    56%    13%
  2.00   7       8.38      7.06      0.47    84%     6%
  3.00   7       9.66      8.48      0.47    88%     5%
```

★★★ **The event count never moves and the split moves 4×. A figure that swings 4× on an
unstated parameter is not a measurement.** ★ Note what *is* stable: the **seven events** and
the **0.47 s settle**. Those are findings; the 88% was not.

★★ **This was only findable because Jay asked for the harness to be saved.** The offline script
that produced the original numbers had been **run inline and never kept** — the numbers
survived, the instrument did not. Rebuilding it as `sierra_rooms.py` reproduced the seven
transitions exactly and then exposed the parameter.

**3.9 ★★★ METHOD FAILURE 3 — the correction at `6b0cbeb` was ALSO wrong, and it is the
sharpest of the four.**
Having withdrawn the 88%, I claimed instead that **Sierra draws throughout the load**, on this:

```
regime    frames    sec | $7000/frame  $0000/frame  total/frame  fdc/frame
idle        8369  139.7 |          57          620         1681          0
load        4567   76.2 |         383          312         1071         46
settle       442    7.4 |          98          458         1531          0
  ★ $7000 -- "the draw window" -- runs 6.7x above idle during the load
```

★★ **The claim is circular and I did not notice for two hours.** `$7000` was named the draw
window from a census taken **across a room change — which includes the load phase.** If `$7000`
is the RBF **sector buffer**, every number above is exactly what you would see.

★★★ **The discriminator settles it against me.** Split the load phase by whether the frame had
any disk activity: **a sector buffer is written as sectors arrive; drawing is CPU work in the
gaps.**

```
LOAD PHASE          fdc frames  $7000/frame | quiet frames  $7000/frame | quiet share
ALL 7 transitions         2376          685 |         2956          150 |       21.4%
```

★★★ **`$7000` traffic is 4.6× HIGHER in disk-active frames, and only 21% of it falls in the
gaps. It tracks the disk. It is a load buffer, not the draw window** — so "drawing throughout
the load" is withdrawn, and **§3.4's identification of `$7000` was contaminated by the same
load phase it was trying to exclude.**

**3.10 ★★★ WHERE THE PICTURE IS PAINTED IS STILL UNKNOWN — AND THERE IS A BLIND SPOT THAT
WOULD EXPLAIN IT.**
Ask it the other way round: in the frames where **the lattice actually moves** — the only
frames the screen is known to change — how many writes occur, across **all sixteen blocks**?

```
FRAMES WHERE THE LATTICE MOVED       (a 160x168 AGI picture = 26,880 pixels)
 #  frames    writes  screenfuls  top blocks
 1      18     26801        1.00  $8000=5067  $9000=4858  $1000=4156
 2      12     16949        0.63  $0000=2922  $B000=2882  $1000=2047
 3       8     10391        0.39  $B000=2266  $0000=1308  $7000=1200
 4       5      6498        0.24  $B000=1142  $8000=1102  $C000=1092
 5       5      6495        0.24  $B000=1151  $8000=1101  $C000=1086
 6      18     27010        1.00  $1000=8618  $0000=7881  $B000=3536
 7      37     58156        2.16  $1000=23274  $0000=18255  $B000=4655
```

★★★ **Transitions 4 and 5 change 47 of 160 lattice points on a total of 6,498 writes across the
entire address space — a quarter of one screenful. That cannot paint a picture.** And the
writes are spread almost evenly across unrelated blocks, which is the signature of background
traffic, not of a renderer.

★★★ **So the screen changes without enough writes to have drawn it, without a VOFFSET write,
and without a locatable draw window. The instruments have a blind spot exactly shaped like the
missing mechanism: THE WRITE TAP COVERS `$0000-$FEFF`, AND THE MMU TASK REGISTERS ARE AT
`$FFA0-$FFAF`.** A buffer swap performed by **remapping MMU slots** rather than by moving
VOFFSET would be **invisible to every instrument in this run**, and would explain all three
observations at once.

★★ **That is a hypothesis, not a finding** — it is §2H check 1 ("is there a SECOND mechanism?")
applied to a page flip, and §2N's warning that the MMU slots are where the real contention
lives. **It is stated here so the next task can test it, and it is NOT relied on anywhere in
§4.**

**3.11 The live detector, rebuilt — and validated by replay, at the third attempt.**
The detector inside `sierra_live.lua` is a convenience; **`sierra_rooms.py` is the instrument.**
★★★ **Both earlier versions failed against Jay's own recorded run**, which is how they were
caught — replaying a state machine over `frames.csv` costs nothing:

```
v1  39 detections on a 7-transition run, with NEGATIVE draw times
      `settle` never reset on a new burst; no screen-change requirement (a MENU passes);
      no burst coalescing
v2   0 detections
      accumulated lattice change only AFTER the coalescing gap -- and the screen change
      happens INSIDE that gap
v3   7 detections, lat 62/103/100/47/47/61/72  == the offline tool, exactly
```

★★ **v2 is the more instructive failure: it was written as the fix for v1 and was shipped-ready
after "review".** A replay took one minute and refuted it.

**3.12 §2.1 / §8.1 — authority and limits.** Sierra's interpreter is **tier 2** for CoCo3
questions [L-17] and only for KQ3 and LSL [X-26]. This used KQ3 on the `Floppy 360K` re-imaging,
so the **interpreter** is tier-2 Sierra and the **media layout** is not (§3.1). ★★ **Every
figure carries OS-9 overhead and is a FLOOR** [I-19].

**3.13 §2S.** POP `430a91c`, Karateka `78c8c27`, both `wip`, measured this task at those refs.
No sibling file touched.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline` 0; `hal_sync_check` OK across three
  repos. `src/**` untouched.
- **AC-2 [class: state-comparable] PASS.** **7 room changes**, operator-confirmed, elapsed
  **3.54 s median (tight) / 9.66 s (loose)**. ★★ **The count is robust across every parameter
  setting tested; the elapsed figure is not, and both readings are reported rather than one.**
  ★ On the dispatch's *"≥3 transitions, each timed ≥3 times"*: the 7 are distinct transitions
  and were **not** repeated. Emulated time is deterministic [T-P0-012, 9 dp], so a replay
  returns identical numbers — but these were **operator-driven and are not reproducible by
  replay**. ★ **What repetition cannot establish here is variance on real hardware.**
- **AC-3 [class: state-comparable] ★★★ FAIL.** *Separate the disk time from the render time.*
  **Not achieved.** The post-disk settle (0.47 s) is a **tail**, not a render; the load phase
  cannot be shown to contain or exclude drawing (§3.9); and the paint window is not located
  (§3.10). ★ **This was reported PASS twice, on two different wrong bases.**
- **AC-4 [class: state-comparable] ★★★ FAIL.** *Compare against our renderer.* **No ratio is
  established.** The withdrawn 17× divided our 7.473 s by a number that was never their render
  time. **What can be said is in §1's one comparison, and it spans a factor of three.**
- **AC-5 [class: state-comparable] ★★ FAIL — worse than the "could not determine" first
  reported.** Span-seeding vs pixel-queue, 160- vs 320-wide, one pass or two: **all three still
  undetermined.** ★★★ **And the draw window itself is now known to have been MIS-IDENTIFIED,
  not merely unidentified** (§3.9). **No guess is recorded.**
- **AC-6 [class: suite] ★★ NOT DEMONSTRATED.** *Is there a technique in their fill we have not
  found?* **Plausible and unproven.** It rested entirely on the 17×. ★ What survives is weaker
  and still worth acting on: **their whole room change, disk included, can be as fast as 3.54 s
  where our render alone is 7.473 s.**
- **AC-7 [class: eye-gated] PENDING JAY.** Nine stills at
  `C:\karateka-capture\agi_captures\sierra-rooms\`, five at confirmed screen changes.
  ★★ **Launch path `live-disk`** — Sierra's own OS-9 boot off a mounted **copy**, never a corpus
  original (§2P). Monitor: MAME's `screen_config` default is **Composite** while `Startup` ran
  `montype -r`, so **the colours are not the RGB ones** — recorded because it bears on AC-7 and
  not on timing.
- **AC-8 [class: suite] PASS.** Five candidates; §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
$ python harness/tools/sierra_rooms.py build/sierra_nojoy/frames.csv
build/sierra_nojoy/frames.csv: 18107 frames, 0.02..302.17 s
params: gap=0.5s settle=1.0s min_lat=30/160 min_fdc=2000

 #  start_s   disk_s   draw_s  TOTAL_s     fdc   lat  pk/frm  voff
 1    65.03    3.121    0.417    3.538   11983    62      14     0
 2   204.03    2.603    1.035    3.638    7969   103      16     0
 3   248.44    1.502    0.434    1.936    6907   100      16     0
 4   260.42    1.969    0.467    2.436    5470    47      13     0
 5   273.55    1.502    0.434    1.936    6909    47      13     0
 6   284.51    2.537    1.619    4.155    9298    61      12     0
 7   296.58    1.502    2.970    4.472    6910    72      12     0

n = 7
  TOTAL  min 1.94  median 3.54  max 4.47 s
  DISK   min 1.50  median 1.97  max 3.12 s   <- 56% of the median total
  DRAW   min 0.42  median 0.47  max 2.97 s   <- 13%
  VOFFSET writes across all transitions: 0   <- a room change is NOT a page flip
  peak PER-FRAME lattice change: 16/160   <- why a per-frame detector is blind to this
```

```
$ powershell -File harness/tools/sierra_live.ps1 -CheckOnly
media OK  KQ3  sha256[0:16]=20EA31A82087DA90
checking sierra_live.lua loads...
  OK
```

```
=== the parameter that produced withdrawal 2 (§3.8) ===
 gap_s   n  med_total  med_disk  med_draw  disk%  draw%
  0.25   7       3.54      1.97      0.47    56%    13%
  1.50   7       3.54      1.97      0.47    56%    13%
  2.00   7       8.38      7.06      0.47    84%     6%
  3.00   7       9.66      8.48      0.47    88%     5%
  ★ same 7 events throughout; the split moves 4x
```

```
=== the discriminator that produced withdrawal 3 (§3.9) ===
LOAD PHASE          fdc frames  $7000/frame | quiet frames  $7000/frame | quiet share
ALL 7 transitions         2376          685 |         2956          150 |       21.4%
  ★ $7000 tracks the DISK -- it is a load buffer, not the draw window
```

```
=== detector replay against Jay's recorded run (§3.11) ===
v1  39 detections, NEGATIVE draw times
v2   0 detections
v3   7 detections, lat 62/103/100/47/47/61/72  == sierra_rooms.py exactly
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle and this task built nothing.

25.3 operator-runtime-smoke: **pending Jay.** Launch path **`live-disk`**; stills in
`C:\karateka-capture\agi_captures\sierra-rooms\`.

### 6 — Reactive deviations and route accounting

- ★★★ **TRIGGER 1 IS WITHDRAWN. It was reported as fired on "Sierra's render is 0.45 s against
  a 4 s threshold" — a figure that no longer exists.** Their render is not measured, so no
  threshold can be evaluated against it. **The next task should not be planned as though the
  fill question were settled.**
- **Trigger 2 did NOT fire.** **Trigger 3 did NOT fire** — but ★ note this is now for the
  opposite reason from the one filed: disk and render were **not** shown separable.
- ★★ **Trigger 4 was approached and not fired.** The interpreter would not reach gameplay for
  several runs, but ★ **it was my configuration that was wrong, not MAME's** — media (§3.1),
  input timing (§3.2), the joystick (§3.7).
- ★★ **Deviation: `Floppy 360K` instead of `KQ3/Original`** (§3.1).
- ★★ **Deviation: `:ctrl_sel` set to Unconnected.** A machine configuration, not keyboard
  input. **Without it no room change is reachable.**
- ★★★ **ROUTE ACCOUNTING — scope taken beyond the dispatch, on Jay's instruction.** He asked
  that the live harness be saved so a re-run needs no re-derivation. **Doing that required
  rebuilding the lost analyser, and the rebuild refuted the report.** ★ I then ran three further
  analyses (parameter sweep, disk-correlation discriminator, paint-window search) that the
  dispatch did not ask for, because each was needed to know whether the previous claim stood.
  ★★ **What I did NOT do:** re-measure with the MMU tap that §3.10 proposes — **that needs a
  new operator-driven run, which is Jay's call, not mine.** And no fill disassembly (§7 puts it
  out of scope).

### 7 — Uncertainty flags
- ★★★ **The paint mechanism is unknown** (§3.10). The screen changes without enough writes to
  have drawn it, without a VOFFSET write, and with no locatable draw window. **The MMU-remap
  hypothesis is untested.**
- ★★★ **`$7000` was called the draw window in three earlier filings and is not.** Anything
  quoting a `$7000` figure as "drawing" is wrong, including this report's own history.
- ★★ **n=7, one game, one media variant, one operator session.** The event count is solid; the
  distribution is not established.
- ★★ **The elapsed room change spans 3.54–9.66 s depending on a coalescing parameter.** Both
  ends are reported; **neither is privileged**, and the true event boundary is not known.
- ★ **The 0.47 s settle is bounded at frame resolution** (±17 ms) and may include non-render
  work.
- ★ **MAME's monitor was Composite** while the interpreter was told RGB — bears on AC-7, not on
  timing.
- ★ **OS-9 overhead is inside every figure** [I-19]. **Tier-2 evidence (real hardware) was not
  consulted.**

### 8 — Follow-up candidates
1. ★★★ **TAP `$FFA0-$FFAF` AND RE-RUN.** The MMU task registers are the one place a whole-screen
   change could come from that this run could not see (§3.10). **Cheap — one more tap in a
   script that already exists** — and it decides whether the picture is drawn during the load
   into an off-screen buffer or drawn at transition time. **Everything AC-3/4/5/6 needs is
   downstream of that answer.**
2. ★★ **Re-ask D-14 afterwards.** *"How long does Sierra's renderer take?"* is not answerable
   until the paint window is located; the current answer is a three-fold range.
3. ★ **Bucket the write census at 256 B rather than 4 KB** across one transition. 4 KB was too
   coarse to separate a load buffer from a framebuffer, which is the whole of §3.9.
4. ★ **Re-measure with `KQ3/Original`** if a way is found to put the volumes on the boot device.
5. ★ **A `reports/` encoding check** — carried from T-P0-011 §3.12, still not built.

### 9 — User interaction during task
**Jay intervened nine times, and every substantive correction in this report traces to one.**
1. ★★ **A mid-task note**: the dispatch never said how to *cause* a room change; movement is
   Ctrl+letter [I-16], flagged secondary; and **the taps could DETECT the change rather than my
   controlling it**. ★★★ **That is the design AC-2 rests on.**
2. *"os9 never entered the game"* — stopped me analysing a trace of a machine sitting at a prompt.
3. ★★★ *"it specifically specifies capital R. you had this working before go look at that
   code."* — **a direct correction of a wrong inference of mine** (§3.2).
4. ★★★ *"same room"* — **the catch that invalidated the first filing's headline** (§3.6).
5. *"you are still inserting input"* / *"it's just blasting the menus"* — the `set_value`
   override (§3.7). ★ I then removed the trigger he was actually using, twice, because I read a
   symptom report as a request.
6. *"try mapping break to delete"*, *"alt is not working i get a speaker sound"* — §3.7.
7. ★★★ *"i am moving the character much better with the ports off. i moved him into and out of
   several rooms for you to trace."* — **the run every measurement here comes from.**
8. ★★★ *"make sure you save the live run harness as is so if i need to drive again it works
   instead of having to re-derive it."* — **this is what exposed withdrawals 2 and 3.** Saving
   the harness meant rebuilding the analyser that had been run inline and lost, and the rebuild
   refuted the report.
9. ★★ *"if we drew 45 scenes in 7 secs doesn't that make our draw time .15s per scene?"* — a
   check on my arithmetic. **The premise was mine to have made clear:** 7.473 s is the
   **per-picture median**, not a 45-picture total (`over 5 s: 45/45`; the total is ~380 s). ★ The
   figure survived, and it is the kind of check that would have caught the 88% two filings
   earlier.

### 10 — Candidate(s) captured this task
Five, all to `seeds/AGI/live/` (§2C — new rows; nothing existing read or edited):
1. **`discover-the-instrument-window-under-the-workload-you-will-measure`** — §3.4.
   ★ **Note for the reconciler: this row's stated payoff quotes the withdrawn "88.8% overlap"
   finding. The principle and its measurement stand; the illustrative outcome does not.**
2. **`working-code-outranks-a-fresh-inference-about-it`** — §3.2. `initiator: orchestrator`.
3. **`a-detector-must-discriminate-the-event-not-just-detect-activity`** — §3.6/§3.11.
4. ★★ **`a-figure-that-swings-on-an-unstated-parameter-is-not-a-measurement`** — §3.8. The
   88%/56% split, same seven events either way.
5. ★★★ **`keep-the-instrument-not-just-its-output`** — §3.8/§3.9. The analyser was run inline
   and never saved; the numbers outlived it, unreproducible and unchallengeable, and rebuilding
   it on an unrelated request is what refuted them.

### 11 — Commit
Superseded: `7c8634e`, `0a5e217`, `95d902b` (the 17× filing), `6b0cbeb` (the correction that is
itself withdrawn). ★ Left in history deliberately — §3.6–§3.11 are about the wrong answers.
`19d288f` — this rewrite, plus detector v3.
`6b0cbeb` — the tracked harness (`sierra_rooms.py`, `sierra_live.ps1`, the cfg seed).
Pool: `93cabb2`, `66d59b8`, `d18fd47` — five rows.
★ Pushed to `origin/wip` before this report.
