## Form B Report — P3.6 — what does Sierra's own interpreter take? (D-14)
**Class:** recon.  wip.

---

## ★★★ CORRECTION — 2026-08-27, AFTER `95d902b`. THE HEADLINE BELOW IS WITHDRAWN.

**This report's own §7 said the live detector was untrustworthy and that the numbers came from
offline analysis "with proper filtering". ★★ That offline script was run inline and was never
saved.** Rebuilding it as `harness/tools/sierra_rooms.py` — at Jay's request to save the
harness so a re-run needs no re-derivation — reproduced the seven transitions exactly, and
then showed that **two of the three headline figures were artifacts of an unstated parameter.**

**What survives, unchanged:**

- **7 room changes**, operator-confirmed. The count is **robust**: every coalescing gap from
  0.25 s to 3.0 s finds the same seven, with the same lattice signatures (62, 103, 100, 47,
  47, 61, 72 of 160).
- **DRAW (last disk access → screen settles): median 0.47 s.** Reproduced to within one frame.
- **VOFFSET writes during a room change: 0.** A room change is not a page flip.
- **Per-frame lattice max 16/160** against a cumulative 47–103 — Sierra draws progressively.

**★★★ WHAT IS WITHDRAWN, AND WHY:**

**1. "DISK 8.48 s (88%)" — the 8.48 s is not disk time, and it is not a measurement.** It is
the span you get when you treat up to 3 s of silence as "still loading". The sensitivity:

```
 gap_s   n  med_total  med_disk  med_draw  disk%  draw%
  0.25   7       3.54      1.97      0.47    56%    13%
  0.50   7       3.54      1.97      0.47    56%    13%
  1.00   7       3.54      1.97      0.47    56%    13%
  1.50   7       3.54      1.97      0.47    56%    13%
  2.00   7       8.38      7.06      0.47    84%     6%
  3.00   7       9.66      8.48      0.47    88%     5%
```

★★ **The count never moves and the split moves by 4×.** The report quoted the gap=3.0 column
without ever stating that a parameter existed. **A figure that swings 4× on an unstated
parameter is not a measurement.**

**2. ★★★ "Strictly load-then-draw" is FALSE, and this is the one that matters.** The lattice
does not move during the load, and I read that as "no drawing is happening". **The write
census — already in the same CSV — says the opposite:**

```
regime    frames    sec | $7000/frame  $0000/frame  total/frame  fdc/frame
idle        8369  139.7 |          57          620         1681          0
load        4567   76.2 |         383          312         1071         46
settle       442    7.4 |          98          458         1531          0
  ★ $7000 (the draw window, 40.1% of room-change traffic): load vs idle = 6.7x

per transition, $7000 writes during the LOAD phase (a 160x168 picture = 26,880 px):
  #1 965679 (35.9 screenfuls)   #2 288525 (10.7)   #3 242811 ( 9.0)   #4 158081 ( 5.9)
  #5 134576 ( 5.0)              #6 149413 ( 5.6)   #7 132154 ( 4.9)
     ...against 4,434-11,725 writes in the whole "draw" phase (under 0.2 of a screenful)
```

★★★ **Sierra is drawing THROUGHOUT the load, 6.7× above idle, five to thirty-six screenfuls
per transition — into something not being displayed, since the lattice never moves and VOFFSET
is never written. The 0.47 s "draw phase" is a TAIL, not the render.**

**3. ★★★ THEREFORE "~17× faster" IS WITHDRAWN AND D-14 IS NOT ANSWERED.** 0.47 s was never
Sierra's render time, so it cannot be divided into our 7.473 s. **What the experiment actually
bounds is the ELAPSED room change: 3.54 s at the tightest reading, 9.66 s at the loosest** —
disk, LOGIC, resource setup and render together, with no way to separate the render out using
these instruments. Our renderer alone is **7.473 s per picture**.

> **The defensible statement: Sierra performs an ENTIRE room change — load included — in
> somewhere between half and one-and-a-third of the time our renderer takes to draw one
> picture from RAM with no disk at all. ★ At the tight end that is damning; at the loose end
> it is inconclusive. THE RATIO IS NOT ESTABLISHED.**

★★ **AC-3 and AC-4 below are therefore FAILED, not passed, and the "consultation trigger 1
fired" claim in §6 rests on a figure that no longer exists.** AC-6's conclusion — *"there is a
technique in their fill we have not found"* — is **plausible and no longer demonstrated**: it
was resting entirely on the 17×.

★★★ **THIS IS THE THIRD CONFIDENT WRONG ANSWER IN ONE TASK, AND ALL THREE HAVE THE SAME
SHAPE — a signal absent from ONE channel read as the phenomenon being absent.** Menus looked
like room changes on the disk channel; a progressive redraw looked like nothing on a per-frame
channel; and drawing-under-load looked like nothing on the lattice channel **while the write
census in the same file said 6.7×**. ★ **In all three the refuting data was already collected
and unexamined.**

★ **What is now tracked, so none of this needs re-deriving:** `sierra_rooms.py` (the
instrument, with its parameters as named flags and defaults), `sierra_live.ps1` (one-command
launch), `harness/mame-cfg/sierra-live/coco3.cfg` (the working key bindings), and a rebuilt
detector in `sierra_live.lua` — **the previous one fired 39 times on this 7-transition run,
with negative draw times.**

**Everything below is the report as filed at `95d902b`, left intact. Read it through this
block.**

---


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

CoCo3 corpus at C:\Projects\agi-games\coco3\ -- 7 titles.
  Original/ media present for exactly TWO: King's Quest III and Leisure Suit Larry.  [X-26]
```

**★ §2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-014 §0.** `src/**` was not
touched at all this task, so `reg_discipline` stays structurally at 0.

**★★ The timing mechanism — P3.3–P3.5's does NOT transfer.** Those tapped a `PHASE` byte our own
probe wrote; Sierra's interpreter writes no marker. What replaces it is in §3.3.

---

### 1 — Summary

**★★★ D-14 IS ANSWERED, AND CONSULTATION TRIGGER 1 HAS FIRED.**

> **A KQ3 room change under Sierra's own 1988 interpreter takes a median of 9.65 s, of which
> 8.48 s (88%) is the FLOPPY and 0.45 s is DRAWING.**
>
> **Our renderer takes 7.473 s of pure CPU with no disk at all.**
>
> **★★★ SIERRA'S RENDERER IS ~17x FASTER THAN OURS, and 0.45 s is a CEILING on their pure
> render — it contains OS-9 overhead and everything else between the disk stopping and the
> screen settling. The true gap is LARGER.**

★★ **This is the dispatch's first branch: *"there is a technique in their fill we have not
found, and finding it is worth more than any further shaving."*** Two tasks of measured
optimisation took our fill from 11.102 s to 7.473 s — 32.7% — and **a 17x gap is not a tuning
gap.** It is a different algorithm or a different representation, and no amount of shaving
reaches it.

**It is also neither of the two mechanisms I hypothesised on the way, and both are withdrawn:**

- **NOT overlapped with the disk.** Lattice change *during* the disk burst was **0 in 14 of 15
  bursts** — strictly load-then-draw. ★★ My earlier claim that *"88.8% of the drawing happens
  while the disk is working"* is **WITHDRAWN**; it was measured on events that were not room
  changes (§3.6).
- **NOT a page flip.** **Zero VOFFSET writes** across all seven transitions, though VOFFSET
  flips *are* used elsewhere (observed directly at the title→game change, §3.5).

★ **AC-3 is answered properly rather than refused:** disk and draw ARE separable in this
interpreter, because they are sequential. 88% / 5%.

★★★ **THE TASK'S OTHER RESULT IS A METHOD FAILURE OF MINE, AND IT IS THE MORE INSTRUCTIVE ONE.**
An earlier version of this report was filed with four "room changes" that were **menu events in
a single room**, and Jay caught it by looking at the stills. The detector inferred a room change
from *"disk burst, then the screen settles"* — **a menu satisfies that exactly as well.** §3.6
records it and both withdrawn claims trace back to it.

### 2 — Files modified
- `harness/tools/sierra_live.lua` — **NEW.** Observation harness: FDC taps, whole-map write
  census, VOFFSET tap, screen lattice, passive key naming. ★ It sends **no input**.
- `harness/tools/sierra_boot.lua` — a **hazard banner**: the boot half works and is T-P0-004's;
  ★★ the CTRL+letter probe **must not be re-run with an operator at the keyboard** (`set_value`
  owns CTRL for the session), and **it never worked anyway** — the cause was the joystick, not
  the keys (§3.7).
- `mame-idioms-coco3-port.md` — **§41h–§41k added** (boot, timing a guest you do not control,
  the input findings, the detector).

**No `src/**` change. No game data, resource bytes, renderings or screenshots committed** (§2P).

### 3 — Reasoning

**3.1 ★★ Which media, and the deviation from `KQ3/Original`.**
The dispatch names `KQ3/Original` — the only non-repacked V2-volume build. **It cannot be used
single-drive.** The manifest says why without booting anything:

```
KQ3-1-1.DSK  22 files  0 vol.*  [OS9Boot + CMDS/Sierra + logDir picDir viewDir object words.tok]
KQ3-1-2.DSK   3 files  2 vol.*  vol.0 vol.1
```

★★ The boot side carries the AGI **directory** files and **zero volumes** — it can name every
resource and load none (§41b). With only `-flop1`/`-flop2` (§41e) the volumes land on `/d1` and
the interpreter looks on the boot device. **Tried; OS-9 came up with nothing to load.**

**Used instead: `Floppy 360K/kq3-1.dsk`** — boot plus `vol.0,1,2,3,12` on one image, the same
image T-P0-004 used. ★ **The deviation costs resource authenticity, not interpreter
authenticity**: the interpreter binary is Sierra's own either way, and that is what AC-2 times.

**3.2 ★★★ The boot, and three mistakes of mine.**
`/d0/Startup` is an OS-9 shell script that runs automatically and **launches the interpreter
itself** — there is no `Sierra` command to type:

```
*GETMODE / echo What display are you using? (R)GB,(C)omposite/TV or (M)onochrome / var.0
IF %0=r montype -r ... ELSE GOTO GETMODE / sierra <>>>/term
```

1. ★★ **I fired the monitor answer at frame 900 — ~25 s before the prompt existed.** It is up at
   **frame 2400**; T-P0-004's `os9rgb2.lua` had it right and I did not read it first.
2. ★★★ **I then "improved" that into a wait for a PINNED PC. That is WORSE.** PC pins during
   **disk waits** as well as at a keyboard prompt. **A liveness signal is not a readiness
   signal.** The stray input landed in the shell and OS-9 printed `EOF` at a repeating prompt.
3. ★★★ **I inferred from `IF %0=r` that the answer must be lowercase and acted on that over code
   that already worked.** Jay: *"it specifically specifies capital R. you had this working before
   go look at that code."* **He was right. The timing was the bug.**

**3.3 ★★★ The mechanism, and its resolutions.**
No marker can be added to the guest, so three guest-agnostic signals:

| signal | measures | resolution |
|---|---|---|
| FDC taps `$FF40-$FF4F`, read **and** write | the disk phase | **one instruction** |
| whole-map write tap, bucketed by 4 KB | where drawing goes | one instruction |
| VOFFSET tap `$FF9D-$FF9E` | page flips | one instruction |
| 16×10 `scr:pixel()` lattice | when the picture settles | **one frame, 16.688 ms** |

★★ The OS-9 RBF driver **polls**, so an FDC count is not a byte count — it marks **when** the
disk is worked, by density.

**3.4 ★★★ A DISCOVERY ERROR, recorded because it produced a confident wrong answer.**
The draw window was located with a wide write tap **during idle sprite animation**: `$9000-$9FFF`
at **91%**. A narrow tap was pinned there and the first measurement pass found **no render burst
at all** — a publishable-looking result. Re-running the same discovery **across a real room
change** gives a completely different map:

```
during a room change:                     during idle animation (the WRONG workload):
  $7000-$7FFF  40.1%                        $9000-$9FFF  91.0%
  $0000-$1FFF  35.4%                        $8000-$8FFF   3.1%
  $6000-$6FFF   7.5%                        rest          5.9%
  total 11,286,077 writes                   total 96,104 writes
```

★ **The instrument was aimed at 0.8% of the traffic.** Two orders of magnitude separate the two
totals, and that was visible at the time.

**3.5 ★★ VOFFSET flips ARE used — but not for room changes.**
Caught directly: `f2946 VOFFSET := $EC00`, then the whole screen changes two frames later, at the
title→game transition. Values seen: `$E000`, `$EC01`, `$0000`, `$EC00` — physical `$70000`,
`$76008`, `$00000`, `$76000`. ★★★ **But across all seven room changes, VOFFSET writes = 0.**
So the interpreter has multiple buffers and flips between them for *some* transitions, and does
**not** use that path for a room change.

**3.6 ★★★ THE METHOD FAILURE — a detector that could not tell a menu from a room.**
An earlier filing reported four room changes with a median of 6.04 s. **They were menu events in
one room.** Jay checked the stills: *"same room."*

★★ **The detector inferred the event from "disk burst, then the screen settles" — and a menu
satisfies that exactly as well as a room change.** I never verified which I had.
★★★ **The refutation was already in my own trace and I did not read it:** the maximum lattice
change in any frame was **14 of 160**, where a full repaint moves most of them. **The data said
no room change had happened.**

★★ **And the correction has a second half.** After Jay confirmed real transitions, the detector
*still* reported nothing — because it tested a **per-frame** threshold, and **Sierra draws a room
PROGRESSIVELY**: measured across the seven confirmed changes, per-frame maximum **16/160** while
the cumulative change was **47–103**. ★ **A detector that assumes an instantaneous repaint is
blind to a progressive one**, and it silently missed fifteen consecutive transitions.
★★★ **Both halves are the same error: calibrating an instrument on the wrong event and then
trusting it. I made it twice in one task and Jay caught it both times.**

**3.7 ★★ Causing the room change — the operator drove it, and that was the unblock.**
Movement is Ctrl+letter, not the arrow diamond [Jay, Nerdly Pleasures / I-16 — secondary]. Twelve
Ctrl+letter candidates were probed and none produced a transition. ★★★ **The actual cause was
that both controller ports default to `Joystick`, and the interpreter polls the joystick — so
every key arrived correctly on the CoCo3 matrix and nothing responded.** Setting `:ctrl_sel` to
**Unconnected** on both ports fixed movement immediately, and Jay then walked in and out of
rooms to produce the measurement.

★ **Input findings, all measured by reading `:row6` live rather than assumed:**

```
CTRL, ALT, SHIFT, ENTER, letters, bare arrows   -> reach the machine
End, Insert                                     -> NEVER arrive (MAME's UI; 41f confirmed)
Left Alt                                         -> reaches MAME but WINDOWS grabs it (system beep)
```

★★★ **And a harness rule paid for three times over:** `ioport_field:set_value()` is a
**PERMANENT programmatic override**, not a momentary press — writing `defvalue` back marks the
field released but never returns it to the input system. Any script that touches `CTRL` owns
`CTRL` for the session, and since movement is CTRL+letter, that turns every keystroke into a
menu command. Jay: *"it's just blasting the menus and i can't do anything."* **Three trigger
designs failed for that one reason before it was understood; the fault was never the trigger.**

**3.8 §2.1 / §8.1 — authority and limits.** Sierra's interpreter is **tier 2** for CoCo3
questions [L-17] and only for KQ3 and LSL [X-26]. This used KQ3, on the `Floppy 360K` re-imaging,
so the **interpreter** is tier-2 Sierra and the **media layout** is not (§3.1). ★★ **Every figure
carries OS-9 overhead and is a FLOOR** [I-19] — which makes the 17x gap a **lower bound**.

**3.9 §2S.** POP `430a91c`, Karateka `78c8c27`, both `wip`, measured this task at those refs. No
sibling file touched.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline` 0/59/8; `hal_sync_check` OK ×3.
  `src/**` untouched.
- **AC-2 [class: state-comparable] ★★★ PASS.** **7 room changes**, each operator-confirmed by
  walking in and out of rooms. Totals **8.36 / 8.93 / 9.11 / 9.65 / 10.01 / 13.75 / 18.54 s**,
  median **9.65 s**. Mechanism and resolution in §3.3. ★★ **On the dispatch's "≥3 transitions,
  each timed ≥3 times": the 7 are distinct transitions and were NOT repeated.** Emulated time is
  deterministic [T-P0-012, 9 dp], so re-running an identical script returns identical numbers —
  but these were **operator-driven and therefore not reproducible by replay**. ★ **What
  repetition cannot establish here is variance on real hardware**, where head position and drive
  speed vary. Stated as a limit rather than padded.
- **AC-3 [class: state-comparable] ★★★ PASS — separable, and separated.** **DISK median 8.48 s
  (88%), DRAW median 0.45 s.** Lattice change during the disk burst was **0 in 14 of 15 bursts**,
  so the phases are sequential, not concurrent.
- **AC-4 [class: state-comparable] PASS.** Ratio **7.473 s : 0.45 s ≈ 17x**, ours slower.
  ★★★ **THE AXES ON WHICH THESE ARE NOT COMPARABLE, and the ratio must not be quoted without
  them:**
  1. **Ours is 45 pictures across 3 games; Sierra's is 7 transitions in one game.**
  2. **Ours is a poke harness with no OS**; Sierra's carries **OS-9** — so their 0.45 s is a
     **ceiling** and the gap is a **lower bound**.
  3. **Ours renders a PC V2 resource from RAM**; Sierra's room change also runs LOGIC, resolves
     resources, and sets up views — more work, not less, inside the 0.45 s.
  4. **Different pictures** — ours KQ1/2/3 PC; theirs the CoCo3 build's.
  5. **Ours is one routine timed at one-instruction resolution**; Sierra's draw phase is bounded
     by a **frame-resolution** settle detector (±17 ms).
  6. **Media differs** — `Floppy 360K`, not `Original` (§3.1).
  7. **Their draw phase may include non-render work** between the disk stopping and the settle.
- **AC-5 [class: state-comparable] PASS as "could not determine" ×3.** The draw window is **not
  fully identified** (§3.4): traffic concentrates in `$7000-$7FFF` and `$0000-$1FFF`, and 8 KB is
  a quarter of a 320×200×4bpp screen. ★ Span-seeding vs pixel-queue: **could not determine.**
  160- vs 320-wide: **could not determine.** One pass or two: **could not determine.**
  **No guess is recorded.** ★★ This is now the obvious next task and it has a sharp question.
- **AC-6 [class: suite] ★★★ PASS.** **There is a technique in their fill we have not found.**
  A 17x gap is not reachable by shaving — two tasks of measured optimisation bought 32.7%.
  ★ It is not overlap and not a page flip; both were tested and both are ruled out. §6.
- **AC-7 [class: eye-gated] PENDING JAY.** Nine stills at
  `C:\karateka-capture\agi_captures\sierra-rooms\`, five of them at confirmed screen changes.
  ★★ **Launch path: `live-disk`** — Sierra's own OS-9 boot off a mounted **copy**, never a corpus
  original (§2P). Monitor: MAME's `screen_config` default is **Composite** while `Startup` ran
  `montype -r`; recorded because it means the colours are not the RGB ones.
- **AC-8 [class: suite] PASS.** Three candidates; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
AC-2 / AC-3 -- ROOM CHANGES under Sierra's own 1988 interpreter
KQ3, Floppy 360K image, OS-9, operator-driven by Jay, controller ports Unconnected

#    start_s   disk_s    draw_s    TOTAL_s   fdc        lat_chg   voff
1    50.01     18.140    0.400     18.540    55668           62      0
2    193.90    12.733    1.018     13.751    35385          103      0
3    241.99    7.944     0.417     8.361     22568          100      0
4    253.91    8.478     0.451     8.928     26000           47      0
5    266.36    8.695     0.417     9.112     17465           47      0
6    279.01    8.044     1.602     9.646     24131           61      0
7    291.02    7.059     2.954     10.013    17483           72      0

n = 7 room changes, each operator-confirmed by walking in and out of rooms
  TOTAL  min 8.36  median 9.65  max 18.54 s
  DISK   min 7.06  median 8.48  max 18.14 s   <- 88% of the median total
  DRAW   min 0.40  median 0.45  max 2.95 s

  ★ lattice change DURING the disk burst: 0 in 14 of 15 bursts -- strictly LOAD THEN DRAW.
  ★ VOFFSET writes across all of them: 0 -- it is NOT a page flip.

  OUR renderer (P3.5 median, 45 pictures, NO disk at all): 7.473 s
  SIERRA's draw phase (median):                            0.45  s
  ★★★ ratio 17x -- and 0.45 s is a CEILING on their pure render (it contains OS-9
      overhead and any non-render work between the disk stopping and the screen settling),
      so the true gap is LARGER, not smaller.
```

```
=== §3.5: VOFFSET flips exist, but not for room changes ===
[f02946] t=49.162  VOFFSET WRITE x2  $FF9D<=$EC $FF9E<=$00
[f02948] * screen change t=49.195 s  changed=96/160  writes=2174  fdc=0
   -> a flip at the title->game transition, screen changes 2 frames later
VOFFSET values seen: $E000 $EC01 $0000 $EC00  (physical $70000 $76008 $00000 $76000)
VOFFSET writes during the 7 ROOM CHANGES: 0
```

```
=== §3.4: the draw window, discovered under the RIGHT workload vs the wrong one ===
during a room change:              during IDLE animation (the wrong workload):
  $7000-$7FFF  40.1%                 $9000-$9FFF  91.0%
  $0000-$1FFF  35.4%                 $8000-$8FFF   3.1%
  $6000-$6FFF   7.5%                 rest          5.9%
  total 11,286,077 writes            total 96,104 writes
```

```
=== §3.7: input, measured by reading :row6 live ===
CTRL, ALT, SHIFT, ENTER, letters, bare arrows  -> reach the machine
End, Insert                                    -> never arrive (MAME UI; 41f confirmed)
Left Alt                                       -> reaches MAME, WINDOWS grabs it (system beep)
:ctrl_sel both ports default to "Joystick"     -> the interpreter polls it and ignores keys
   set to Unconnected -> movement works immediately
```

```
=== §3.6: why the detector was blind, measured on the 7 confirmed changes ===
per-frame lattice change, maximum        16/160     <- below any sane per-frame threshold
cumulative change per transition          47-103    <- the real signal
  -> Sierra draws a room PROGRESSIVELY; a per-frame detector missed 15 consecutive transitions
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle and this task built nothing.

25.3 operator-runtime-smoke: **pending Jay.** ★★ Launch path **`live-disk`**, Sierra's own OS-9
boot off a mounted copy. Stills in `C:\karateka-capture\agi_captures\sierra-rooms\`.

### 6 — Reactive deviations and route accounting

- ★★★ **TRIGGER 1 FIRED: Sierra's render is 0.45 s against the dispatch's 4 s threshold.**
  Reported immediately and **the task stopped there** rather than hunting the fill — §7 puts a
  disassembly out of scope and the dispatch says this changes the next three tasks.
- **Trigger 2 did NOT fire** — not comparable; materially faster.
- **Trigger 3 did NOT fire** — disk and render **were** separable (§3.5 of the dispatch's sense),
  because they are sequential in this interpreter.
- ★★ **Trigger 4 was APPROACHED and not fired**, but only just: the interpreter would not reach
  gameplay for several runs. ★ **It was my configuration that was wrong, not MAME's** — media
  (§3.1), then input timing (§3.2), then the joystick (§3.7). **I came close to spending the
  whole task here and Jay's interventions are what prevented it.**
- **Trigger 5 did not arise** — C was not attempted beyond the write map.
- ★★ **Deviation: `Floppy 360K` instead of `KQ3/Original`** (§3.1), carried into AC-4's caveats.
- ★★ **Deviation: `:ctrl_sel` set to Unconnected.** A machine configuration, not keyboard input.
  **Without it the game ignores the keyboard and no room change is reachable.**
- **ROUTE ACCOUNTING.** ★ **What I did NOT do:** read the fill (AC-5 is three "could not
  determine"s), and I did **not** attempt the disassembly. ★★ **What I did that was not asked:**
  a VOFFSET tap and a whole-map write census — both were needed to rule out the two wrong
  hypotheses I had already published in an earlier filing.

### 7 — Uncertainty flags
- ★★★ **n=7, one game, one media variant, one operator session.** The 17x is robust to
  measurement error at that magnitude, but the *distribution* is not established.
- ★★ **The draw phase is bounded by a frame-resolution settle detector** and may include
  non-render work. **0.45 s is a ceiling on their render, not an estimate of it.**
- ★★ **Two claims from an earlier filing of this report are WITHDRAWN**: the 6.04 s median
  (menu events, not room changes) and "88.8% of drawing overlaps the disk" (measured on those
  same events; the real transitions are strictly sequential).
- ★ **The draw window is not fully identified** (§3.4), so no per-picture write count is
  comparable to ours.
- ★ **MAME's monitor is Composite** while the interpreter was told RGB — colours are not the RGB
  ones, which matters for AC-7 but not for timing.
- ★ **The live detector in `sierra_live.lua` over-fires** — it triggers on any disk burst
  followed by quiet and produced 29 false positives in one run. **The measurement in this report
  came from OFFLINE analysis with proper filtering, not from that detector.** It needs a screen-
  change requirement before it is trustworthy.
- ★ **OS-9 overhead is inside every figure** [I-19]. **Tier-2 evidence (real hardware) was not
  consulted.**

### 8 — Follow-up candidates
1. ★★★ **WHAT IS SIERRA'S FILL DOING THAT OURS IS NOT, TO BE 17x FASTER ON THE SAME CPU?**
   That is the question this task was built to produce and it is now sharp. §7's bounded static
   read is the cheap first move; a disassembly "wants a separate conversation".
   ★ Concrete sub-questions the write map already poses: why is `$0000-$1FFF` 35% of the draw
   traffic, and is the picture buffer 160-wide rather than 320?
2. ★★ **Fix the live detector** — require screen change, not just a disk burst (§7).
3. ★★ **Identify the draw window properly** — a 256 B-bucketed wide tap across one transition.
4. ★ **Re-measure with `KQ3/Original`** using two drives, if a way is found to put volumes on the
   boot device.
5. ★ **A `reports/` encoding check** — carried from T-P0-011 §3.12, still not built.

### 9 — User interaction during task
**Jay intervened seven times, and the task's result is largely his.**
1. ★★ **A mid-task note**: the dispatch never said how to *cause* a room change; movement is
   Ctrl+letter [I-16], flagged as secondary; and **the taps could DETECT the change rather than
   my controlling it**. ★★★ **That suggestion is the design AC-2/AC-3 rest on.**
2. *"os9 never entered the game"* — stopped me analysing a trace of a machine at a prompt.
3. ★★★ *"it specifically specifies capital R. you had this working before go look at that
   code."* — **a direct correction of a wrong inference of mine** (§3.2).
4. ★★★ *"same room"* — **the catch that invalidated the first filing's headline** (§3.6).
5. *"you are still inserting input"* / *"it's just blasting the menus"* — the `set_value`
   override (§3.7). ★ I then removed the Alt trigger he was actually using, twice, because I
   read a symptom report as a request.
6. *"try mapping break to delete"*, *"alt is not working i get a speaker sound"* — the host-key
   findings in §3.7.
7. ★★★ *"i am moving the character much better with the ports off. i moved him into and out of
   several rooms for you to trace."* — **the run this entire report's measurement comes from.**

### 10 — Candidate(s) captured this task
Three, all to `seeds/AGI/live/` (§2C — new rows, nothing existing read or edited):
1. **`discover-the-instrument-window-under-the-workload-you-will-measure`** — the draw area found
   under idle animation was `$9000` at 91%; under a real room change it is `$7000` at 40% and
   `$9000` at **0.8%**. The instrument was aimed at 0.8% of the traffic and confidently reported
   the phenomenon absent.
2. **`working-code-outranks-a-fresh-inference-about-it`** — ★ `initiator: orchestrator`. I read
   `IF %0=r` in a shell script and overrode a recipe already proven against the machine and
   gated by the operator.
3. **`a-detector-must-discriminate-the-event-not-just-detect-activity`** — ★★★ the most important
   of the three. "Disk burst then settle" is satisfied by a menu; a per-frame repaint threshold
   is blind to a progressive redraw. **The same instrument was wrong in both directions, and both
   times it reported a confident answer rather than an error.**

### 11 — Commit
`3b8aa82` — the corrected report, `sierra_live.lua`, and `sierra_boot.lua`'s hazard banner.
`0a5e217` / `7c8634e` — the superseded filing, left in history rather than rewritten, because
§3.6 is about a wrong result and removing it would remove the evidence.
Pool: `66d59b8` (`seeds/AGI/live/`, third row) on top of `93cabb2` (first two).
★ Pushed to `origin/wip` before this report.
