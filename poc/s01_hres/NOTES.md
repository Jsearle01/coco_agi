# Spike S-01 (rev B) — does a mid-frame HRES change hold under MAME?

**Run 2026-09-26. Not a dispatch, not a gate. No `src/` change, no HAL, no oracle.**

★★★★★ **This note exists because a future reader will want to know whether a negative was the
GIME's or MAME's — and, as it turns out, whether it was the instrument's.** T-P0-015's capture sat
unexamined for 61 tasks because nobody wrote down what it meant [§8].

---

## The short version

| stage | result |
|---|---|
| **Stage 0 — the control (mid-frame PALETTE change)** | ★★★★★ **PASSED.** Measured and eye-confirmed. |
| **Stage 1 — mid-frame HRES change** | ★★★★★ **NOT ANSWERED. The instrument is not trustworthy yet.** |
| **Stage 2 — precision / jitter** | Not reached. |

★★★★★ **160-wide is neither opened nor closed by this run.** Stage 0's pass means MAME *can* answer
the question; the stage-1 measurement is not sound enough to report an answer. **This is explicitly
NOT the §7 "stage 1 fails" outcome**, which would have closed 160-wide — that outcome requires a
working instrument and this one is not.

---

## Stage 0 — PASSED, and it is solid

**A mid-frame write to palette register `$FFB1` splits the screen, and the boundary tracks the
delay.** Sweeping the host-poked delay moved the boundary linearly down the screen:

```
dly    1200 1400 1600 1800 2000 2200 2400 2600 2800 3000 3200 3400 3600
y        39   53   67   81   95  109  123  137  152  166  180  194  208
```

- **14 scanlines per 200 delay iterations = 1,600 CPU cycles / 14 lines = 114 cycles per scanline.**
  At the measured 1.789772 MHz that is **63.6 µs per line**, which is NTSC's real line time
  (63.556 µs), and 114 × 262 = 29,868 cycles/frame = **59.9 Hz**. ★★★★ The instrument recovered the
  raster geometry it was never told, which is the strongest available evidence that it is measuring
  the raster and not an artefact.
- Active display is **y = 25..217 = exactly 192 lines**, consistent with `LPF=00`.
- Delays 0–1000 give no mid-screen boundary: the write lands in vertical blank, as expected.
- **Guest liveness rose throughout** (`s01_frames` 0 → 214), so this is not a still frame or a crash.
- **17 of 19 sweep points were steady across 4 consecutive samples**; 2 jittered by one scanline,
  which is what a write landing on a line boundary should do and is a real datum for stage 2.

★★★★★ **Jay's eye, at 99.99% speed (§2U.2), `dly 2400`:** *"i see top half white and bottom half
blue. i think thats what you'd expect."* — and it is exactly what was expected: `colA=$3F` white
over `colB=$09` blue, boundary at y=123, on a black border. **Two independent confirmations, one
numeric and one human, of the same frame.**

> ★★★★★ **CONCLUSION: MAME samples GIME video registers during the scan. An HRES result from this
> emulator is worth having.** §2's control is discharged and the §7 "stage 0 fails" branch — where
> 160-wide would have stayed open pending hardware — does not apply.

★★ Incidental, and confirmed empirically rather than derived: **`$FFB1 = $09` renders BLUE and
`$3F` renders WHITE** on the RGB monitor profile.

---

## ★★★★★ CORRECTION — two claims in the first draft of this note are WITHDRAWN

**Written after a second session of work. The first draft's stage-1 account was itself built on a
broken sampler, and two of its conclusions are wrong.**

1. ★★★★★ **`VOFFSET = $EA00` is WITHDRAWN. The correct value is `$E800` — the DERIVED one.**
   `physical $74000 >> 3` was right all along and the `$1000` discrepancy never existed. The `$EA00`
   "all rows patterned" result was an artefact of the per-pixel sampler and **is not reproducible**:
   the same value set directly gives a broken profile, and it only ever looked right as step 6 of a
   7-step sweep. ★★★ **`gfx.s`'s formula is not implicated and its open VOFFSET debt is untouched by
   this spike.** The proof that `$E800` is correct is below and it is unambiguous.
2. ★★★★ **"The instrument cannot display a static 160-wide screen" is too broad.** The instrument
   displays a 320-wide screen *perfectly*. What it cannot do is produce a trustworthy display in any
   arm that writes `$FF99`, which is a narrower and more specific problem.

★★★ **The first draft's stage 0 account needed no correction.**

---

## ★★★★★ The sampler was the first real defect, and fixing it changed the answers

**`scr:pixel(x, y)` was called 640 times per row — 640 separate reads of a bitmap that changes
between them.** It produced results that were not reproducible: the same binary, VOFFSET and `$FF99`
gave "all rows 159" in one invocation and "72, 66, 66 then flat" in another, and rows 30/50/70 read
**identically across all eight video modes** — a number that does not move when the mode changes is
not measuring the mode.

★★★★ **The fix is `scr:pixels()`** (MAME 0.281), which returns the whole frame as one 611,840-byte
string — 640 × 239 × 4 — so every pixel in a profile comes from **the same frame by construction**.
Pixels are compared as 4-byte substrings, which also removes a byte-order assumption nothing checked.

★★★★★ **And the second defect was reading a DERIVED number instead of the raw datum.** A transition
*count* of 66 is consistent with the stripe pattern, with DECB's text screen, and with garbage. Run
lengths distinguish them in one look, and the moment they were printed the whole picture resolved:

```
STAGE 0, $0F stripe fill, VOFF=$E800  ($0F = indices 0,0,3,3 at 2bpp)
  y= 30 runs 4,4,4,4,4,4,4,4,...  colours 00000000 00FFFFFF
  y=110 runs 4,4,4,4,4,4,4,4,...  colours 00000000 00FFFFFF
  y=210 runs 4,4,4,4,4,4,4,4,...  colours 00000000 00FFFFFF
```

★★★★★ **Perfectly regular runs of 4, black and white, on every row.** Two pixels of index 0 then two
of index 3, each pixel two raster columns wide at 320-wide on a 640 raster — **exactly the
prediction.** ★★★★ **This is the proof that `VOFF=$E800` is correct and that the whole display path
works**: framebuffer, MMU map, VOFFSET, palette and mode, end to end.

★★★ §2W.3's rule, learned the expensive way: *a diagnostic that reports a derived number where it
could report the raw observation can only tell you that something is wrong, never what.*

---

## Stage 1 — STILL NOT ANSWERED, and now the reason is precise

> ★★★★★ **THE ISOLATION, and it is clean: mode 0 renders the framebuffer PERFECTLY. Mode 1 — whose
> only additional act is writing `$FF99` — renders DECB's text screen above and below a band of
> framebuffer. The guest is alive in both (`s01_frames` 20 → 88).**

★★★★★ **And it happens even when the value written is IDENTICAL to the one already set, and even when
the write lands in vertical blank.** Writing `$FF99 = $15` over an existing `$15`, during blanking,
breaks the display.

> ★★★★★ **That is incoherent as a GIME behaviour, which is exactly why stage 1 cannot be called a
> FAILURE.** A real GIME cannot be disturbed by writing a register the value it already holds. So the
> fault is in this arm or in how MAME handles `$FF99` writes generally — and **until that is
> distinguished, "a mid-frame HRES change does not hold" is not a claim this spike has earned.**

### Eight hypotheses tested and eliminated

★★★ Recorded because a hypothesis killed by measurement is worth as much as the one that lands, and
because the next person should not re-run these:

| # | hypothesis | verdict |
|---|---|---|
| 1 | `-video none` stops MAME rasterising | **NO** — identical with `-Render` |
| 2 | the screen needs time to settle | **NO** — identical at 291 guest frames |
| 3 | per-pixel sampling tears the bitmap | ★★★★ **YES, a real defect** — fixed with `scr:pixels()`, and it changed the numbers |
| 4 | the MMU map / task register was wrong | **NO** — all eight task-0 slots pinned, then task 0 selected; no change |
| 5 | VOFFSET was wrong (`$EA00` not `$E800`) | **NO** — `$E800` is correct, proven by the run-length dump |
| 6 | the bitmap only refreshes on palette writes | **NO** — adding `$FFB1` traffic to mode 1 changed nothing |
| 7 | `$FF99` must be written paired with `$FF98` via `std`, as `gfx.s` does | **NO** — the paired write behaves identically |
| 8 | the write must avoid the active display | **NO** — `dly=0` (blanking) and `dly=2400` (mid-active) are byte-identical |

★★ Mode 1 also renders `$FF99 = $15` and `$FF99 = $0D` **byte-identically**, which on its own says the
writes are not reaching the video path in the way the model expects.

### The first draft's chain, kept because the reasoning was sound even where the conclusion moved

### 1. A uniform fill did not render uniformly

With all 15,360 framebuffer bytes set to `$0F` in a **static** mode — no mid-frame write of any
kind — the horizontal transition count per row came back:

```
row   30:72  50:66  70:66  90:0  110:0  130:0  150:0  170:0  190:0  210:176
```

★★★★★ **Every row of the buffer is byte-identical, so every row must render identically.** A
patterned top, a flat middle and a patterned bottom is not a picture of this framebuffer.

★★★★ **This was caught by a self-check added AFTER the first stage-1 run had already produced a
number** — the first run reported a "width ratio of 36.00" and a VOID verdict, and both were
meaningless. **The check that a constant fill must render constantly is the one that should have
existed before any HRES claim, and writing it is what exposed everything below.**

### 2. The fill is correct; the display path is at fault

A host-side readback of the framebuffer settles which half is broken:

```
framebuffer readback (expect $0F): $4000=$0F $5000=$0F $6000=$0F $7000=$0F $7BFF=$0F
  -> FILL IS CORRECT -- any screen mismatch is the DISPLAY path
```

★★★ Two hypotheses, separated by measurement rather than chosen by argument.

### 3. Two assumptions in the display path were wrong, and fixing them was not enough

- **The MMU map was assumed.** VOFFSET is a *physical* address, so logical `$4000` only lands at
  physical `$74000` if MMU slot 2 holds block `$3A`. The spike took DECB's default on faith;
  `p3b_run.lua` does not — it writes `$FFA0`–`$FFA7` on every launch. **Fixed** by filling all eight
  task-0 slots and only then selecting task 0 with `clr $FF91` (the safe order: the map is valid
  before it goes live, so it cannot pull the ground from under code running in slot 1).
- **VOFFSET's value was derived, twice, and measured differently.** Sweeping it found that only
  **`$EA00`** makes every row patterned and equal — at which point all ten rows read **159
  transitions**, against **160 predicted** for 320-wide. The derived value was **`$E800`**
  (`physical $74000 >> 3`, per `gfx.s:206-215`). ★★★ **A `$1000` / 4,096-byte discrepancy, recorded
  as measured and NOT rationalised.**
  ★★★★ `gfx.s:212-213` already carries this as open debt: *"VOFFSET CORRECTNESS: inferred from
  disassembly; NOT verified in P2.3a. Discharge by P2.3a.1 sentinel test."* **This spike inherited an
  unverified assumption and then reported a GIME result on top of it.**

### 4. ★★★★★ And then the result that invalidates the stage-1 measurement outright

The static profile was taken for **every** 4-colour `$FF99` value:

```
$FF99=0x01  30:72  50:66  70:66  90:0  110:0  130:2  ...
$FF99=0x05  30:72  50:66  70:66  90:0  110:12 130:0  ...
$FF99=0x09  30:72  50:66  70:66  90:0  110:2  130:2  ...
$FF99=0x0D  30:72  50:66  70:66  90:0  110:0  130:0  ...
$FF99=0x11  30:72  50:66  70:66  90:2  110:2  130:2  ...
$FF99=0x15  30:72  50:66  70:66  90:0  110:0  130:0  ... 210:162
$FF99=0x19  30:72  50:66  70:66  90:2  110:2  130:2  ... 210:256
$FF99=0x1D  30:72  50:66  70:66  90:0  110:0  130:0  ... 170:319
```

★★★★★ **Rows 30, 50 and 70 read 72, 66, 66 for all eight video modes — and `$15` read 159, 159, 159
in the VOFFSET sweep.** A number that does not move when the video mode changes is not a measurement
of the video mode, and the same setting giving 66 in one run and 159 in another means **the host-side
sampling is not reliably reading a settled frame.**

> ★★★★★ **So the stage-1 numbers describe my sampler, not the GIME.** The `ratio 36.00`, the flat
> middle rows, and even the `$EA00` VOFFSET "pass" are all suspect, because they share one
> unvalidated instrument.

★★ The 4-sample agreement check ("steady across samples") passed throughout and did **not** catch
this — it establishes that consecutive reads agree, not that what they agree on is a settled frame.
★★★ **An agreement check is not a correctness check**, which is the same lesson in a new costume.

---

## What is owed before stage 1 can be answered

★★★★★ **The next step is to read MAME's own `$FF99` write handler**, because eight black-box
hypotheses have been spent and the ninth should not be another guess. The question to answer from the
source is narrow: **what does `gime_device`'s `$FF99` write do to the screen state, and why would
writing an unchanged value disturb it?** That is one file and it converts this from guesswork into a
fact — and it also settles whether the behaviour is a modelling artefact (in which case MAME cannot
answer stage 1 and 160-wide stays OPEN pending hardware, per §7) or a faithful model of something the
GIME really does (in which case stage 1 has its answer).

★★★ Only then, in order:

1. **Re-run the two static endpoints** (`$15` and `$0D`) and require them to differ — a 320-wide
   screen gives run lengths of 4 and a 160-wide screen must give 8. **That is the pass condition, and
   it is now a raw observation rather than a transition count.**
2. **Then the mid-frame flip**, against both endpoints.
3. ★★ **Stage 1b, §3.2** — the row-number fill (`s01_fillm = 1`) is implemented and never used: row
   *N* filled with byte value *N* lets the displayed byte value say which source row arrived below the
   switch, which is the address-counter question. **Nothing has been learned about it.**
4. ★ **The 16-colour pair `$1E`/`$16`** is the port's real target and is deliberately untested: a
   16-colour buffer is 30,720 bytes and would cross `$8000` into ROM territory, forcing all-RAM mode
   and putting the interrupt vectors in RAM. **A 4-colour pass would still need confirming there.**

★★★★★ **What must NOT happen: reporting "stage 1 failed" and closing 160-wide on this evidence.** §7
makes that outcome contingent on a trustworthy instrument, and an arm that breaks when a register is
written its own existing value is not one.

---

## Things this spike got right, worth keeping

- **Stage 0 first, as §2 insisted.** Had the control been skipped, the stage-1 mess would have read
  as "MAME cannot do mid-frame register changes" and **160-wide would have closed for entirely the
  wrong reason.** The control is what makes the failure legible as an instrument problem.
- **The liveness witness.** `s01_frames` distinguishes "no split" from "guest crashed", and it earned
  its place immediately: the first stage-1 run printed **VOID**, correctly refusing to interpret a
  screen it could not vouch for.
  ★★★★ Though the check itself had to be fixed: the first version compared `results[1].frames` with
  `results[#results].frames`, which on a **one-value sweep is the same row** — it read `x > x`,
  declared a running guest STALLED, and voided a real run. **A liveness check a live guest cannot
  pass is worse than none.** It now compares the counter across one sample window.
- **Measuring rather than deriving.** VOFFSET was derived twice and wrong both times; a sweep found a
  value in one run. The same technique then exposed the sampler.
- **`-nothrottle` for numbers, normal speed for the eye** (§2U / §2U.2): the sweeps run at ~2100% and
  the one run a person watched ran at 99.99%.

---

## Files

| | |
|---|---|
| `poc/s01_hres/s01.s` | the standalone binary, 212 bytes. Modes: 0 = palette control, 1 = HRES flip, 2 = static reference. No HAL, no includes. |
| `poc/s01_hres/s01_run.lua` | MAME driver: waits for DECB's OK prompt, pokes, sweeps, samples, computes the verdict. |
| `poc/s01_hres/s01.ps1` | assemble + launch. `-Eye` is the normal-speed human run. |

★★ Register values are cited in `s01.s`'s header against `src/hal.inc` and `src/hal/coco3-dsk/gfx.s`
rather than derived in the spike — **except VOFFSET, which is the one that was derived, and the one
that was wrong.**

★★★ One deliberate divergence from the HAL's verified init order: **`$FFDF` (all-RAM) is not
written.** Everything the spike touches is below `$8000` and therefore RAM under every map, while
all-RAM would move the 6809's vectors into RAM — and an NMI through a garbage vector would look
exactly like "stage 0 failed", the false negative §2 exists to prevent.
