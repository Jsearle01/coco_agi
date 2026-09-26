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
| **Stage 1 — mid-frame HRES change** | ★★★★★ **PASSED.** Resolution halves below the write, ratio 2.01, boundary tracks the delay. |
| **Stage 2 — precision / jitter (FIRQ)** | Not reached. |
| **S-02 — where the data below the switch comes from** | ★★★★★ **ANSWERED: the counter KEEPS RUNNING (§1.1 case 1) — a single linear buffer works.** |
| **S-02 §4C — do 2 more splits land in one frame?** | ★★★★★ **YES. Three boundaries, four bands. N splits cost N writes.** |

> ★★★★★ **A MID-FRAME HRES CHANGE HOLDS UNDER MAME.** The screen renders 320-wide above the write and
> 160-wide below it; the horizontal period doubles exactly (**159 → 79 transitions per row, ratio
> 2.01**) and **the boundary tracks the poked delay** across six delays, so the register write is what
> places it. Per §7 this is the *"stages 1 and 2 pass"* branch minus stage 2: **the 160-wide picture
> becomes a live option**, with the §3.4 caveat that two GIME revisions exist and MAME models one —
> **"worth building on", never "proven".**

★★★ **The measurement, verbatim** (`-Stage 1 -VresT $15 -VresB $0D`, stripe fill, `VOFF=$E800`):

```
dly   1400 1800 2200 2600 3000 3400
first 160-wide row y=   70   90  110  150  170  210     <- boundary tracks the delay
ratio               2.01 2.01 2.01 2.01 2.01 2.01     <- the resolution HALVES, every time
row profile at dly=2400:  30:159 50:159 70:159 90:159 110:159 | 130:79 150:79 170:79 190:79 210:79
raw runs at dly=2400:     y=30 4,4,4,4,...   y=110 4,4,4,4,...   y=210 8,8,8,8,...
```

★★★★ **The run lengths are the proof, not the counts.** `$0F` is indices 0,0,3,3 at 2 bits per pixel;
at 320-wide each pixel is 2 raster columns, so two pixels of a colour give **runs of 4**, and at
160-wide each pixel is 4 columns, giving **runs of 8**. Both appear, on the same frame, split at the
scanline the write landed on.

★★★★★ **EYE-CONFIRMED at 99.99% speed** (§2U.2), `dly 2400`: fine stripes above the boundary, stripes
of double the width below it. **Jay, watching: *"thats exactly what i saw"***, against a stated
expectation given before the run. ★★★ **Both stages therefore carry two independent confirmations —
a host-side number and a human — of the same frame**, which is the standard the first draft of this
note could not meet for stage 1.

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

---

# S-04 — Is the row repeat real, or the instrument?

★★★★★ **THE INSTRUMENT. The 16-colour mode is CLEAN and matches 4 colours exactly.**

```
BEFORE (S-03):  runs of 1: 175   runs of 2: 9   <- the "repeat"
AFTER  (S-04):  runs of 1: 191   runs of 2: 1   <- identical to the 4-colour baseline
 4-colour ref:  runs of 1: 191   runs of 2: 1
```
★★ The lone remaining "2" is the final scanline, where 193 active scanlines read slightly past the
buffer — the same edge 4 colours shows, not a pattern.

## The cause, and it was mine

★★★★★ **The palette flip that keeps MAME's bitmap current was pointed at `$FFB8` — palette index 8.**
S-02 chose it because **4-colour mode displays only indices 0-3, so index 8 was invisible.** ★★★★★ **At
16 colours EVERY index is displayed.** So the flip was overwriting index 8 with `$3F` twice a frame,
`pal16[7]` is also `$3F`, and **two indices rendered identically** — making two source rows that differ
only in that nibble indistinguishable, and reporting them as one repeated row.

★★★★ **Fix: flip the BORDER (`$FF9A`) instead.** MAME records the border per scanline too
(`update_value(&m_scanlines[..].m_border, border)`), so it keeps the bitmap current without touching any
picture colour, **and the border is outside the decoded area so it cannot alias.**

## How it was found, and the three wrong turns are the useful part

★★★★★ **§4A(1) — shifting the row numbering — is what killed it, and it took one poke.** If the repeats
were an artefact of the byte VALUE they would move with `s01_rowbase`; if they were tied to a screen
POSITION they would stay:

| `s01_rowbase` | first repeat at index | byte value there |
|---|---|---|
| 0 | 6 | **6** |
| 4 | 2 | **6** |
| 8 | 14 | **22** |

★★★★★ **6, 6, 22 — all ≡ 6 (mod 16). The repeated rows are those whose LOW NIBBLE is 6**, which is a
property of the data and cannot be a property of the raster. ★★★ §4A(2)'s independent pixel-pair reading
agreed with the signature at every step, so §6's first trigger never fired and neither reading was the
problem.

★★★★ **Then the rendered-palette dump named it outright:**
```
0=0000FF 1=00FF00 2=00FFFF 3=FF0000 4=FF00FF 5=FFFF00 6=FFFFFF 7=FFFFFF ...
★★★★★ DUPLICATE RENDERED COLOURS: 6==7
```

★★★★★ **THREE WRONG TURNS, AND THEY ARE WORTH MORE THAN THE ANSWER:**

1. ★★★★★ **S-03 "fixed" a palette collision by setting 16 distinct palette BYTES and never checked that
   they render distinctly.** ★★★★ **Distinct inputs are not distinct outputs.** The fix addressed the
   cause I had identified rather than **the property I actually needed**, and it left the defect in place
   while reading as closed.
2. ★★★★ **I then edited `s01_pal16` twice and the dump did not change.** ★★★ That was the signal the
   colliding entry was **never a pal16 entry at all** — it was the flip register — and I should have read
   "my edit changed nothing" as evidence rather than trying a third value.
3. ★★★ **My byte→RGB arithmetic was wrong twice** before the dump let me derive the real mapping from
   observed data (`$09` → pure blue max, `$12` → pure green max, so R = bit5·2+bit2, G = bit4·2+bit1,
   B = bit3·2+bit0). ★★ **The dump is what made it derivable**; predicting it was what kept failing.

## ★★★★★ WITHDRAWN: S-03 §7.3's hypothesis about the port's display

**S-03 raised the possibility that MAME duplicates a scanline in `$1E` — the port's own display mode —
and that every byte gate would be blind to it because it compares the plane rather than the raster.**

★★★★★ **That hypothesis is WITHDRAWN. There is no row duplication in `$1E`.** ★★★★ It was an artefact of
a flip register that is invisible at 4 colours and displayed at 16, and **it says nothing about the port,
whose display this spike never touched.** ★★★ It was flagged as a hypothesis with a cheap test rather
than as a finding, which is the only reason it cost a paragraph instead of a task.

## §4B / §4D — STAGE 2, measured on the busy-wait arm, and it stops at §6's fifth trigger

★★★★★ **FIRQ WAS NOT BUILT, AND THAT IS DELIBERATE: the problem was measured first.** Building a
hardware-paced boundary before establishing that the cycle-counted one drifts is how a task ends up
proving its own premise.

**§4B(1) — ONE boundary, 10,800 frames = 3 emulated minutes:**
```
distribution: y123 x10800     distinct patterns 1     MODE y123 (10800 of 10800 = 100.00%)
frames deviating from the mode: 0 (0.00%)
★ every sampled frame had exactly one readable boundary
```
★★★★★ **Perfectly steady. Zero deviation in three minutes.** ★★ §4B(2), tearing: **no frame failed to
present exactly one readable boundary** — the reader rejects a frame whose top is already narrow or
whose bottom is still wide, and none was.

**§4D — THREE boundaries, same window:**
```
distribution: 39,88,138 x1067    39,89,138 x9733
distinct patterns 2     MODE [39,89,138] (9733 of 10800 = 90.12%)
```
★★★★★ **The OUTER two boundaries are rock steady at y=39 and y=138. The MIDDLE one alternates between
y=88 and y=89 on 9.88% of frames.** ★★★ §6's fifth trigger: **which, and where — the second of three,
at the top of the middle band.**

★★★★ **And that is the expected physics rather than a surprise**: the first boundary is anchored to
VBORD, so its cycle count is measured from a hardware event; the second is placed by an accumulated
busy-wait (`dly + dly2`) whose total lands near a scanline edge and therefore alternates. ★★★ The third
is steady because its total cycle count is unchanged by which scanline the second write was *sampled*
on — **the jitter is in the reading, not in the accumulated time.**

**§4B(3) — CPU time:** ★★★ **1.000 guest loop iterations per frame**, sustained over 10,200 host
frames, in every arm. **The guest keeps up exactly.** ★★ This is the BASELINE a FIRQ arm must be
compared against, and no FIRQ arm exists yet, so **no cost for the handler is claimed.**

### What this means for the message-box case

★★★★★ **A box edge that moves by one scanline on 10% of frames would shimmer.** ★★★★ **So FIRQ pacing
is now MOTIVATED BY A MEASUREMENT rather than assumed** — it is precisely the fix for a boundary placed
by a cycle count near a line edge, because it anchors the write to a hardware event. ★★★ **One boundary
needs no help at all.**

★★ **The instrument for §4D is stronger than three separate distributions**: the whole band pattern is
compared as one string, so **a frame where two boundaries moved in compensating directions would still
show as a distinct pattern.** Only two patterns appeared.

---

# S-03 — The 16-colour pair, and stage 2

★★★★★ **STOPPED AT A §6 TRIGGER. The 16-colour pair SPLITS exactly as the 4-colour pair does, but its
row-to-scanline behaviour is NOT identical — there is a periodic single-row repeat that 4 colours does
not have — and §6 says report a behavioural difference rather than push on.** ★★★★ **Stage 2 (§4C) and
§4D were NOT attempted**: the dispatch's own words are *"stage 2 on a mode the port will not use is
wasted"*, and the mode the port WILL use has an unexplained difference in it.

| item | result |
|---|---|
| §4A buffer placement + vectors | ★★★★★ **SOLVED without all-RAM.** See below. |
| §4B(1) does it split at `$1E`/`$16`? | ★★★★★ **YES** — runs 2 → 4, transitions 319 → 159, **ratio 2.01** |
| §4B(3) do three boundaries land? | ★★★★★ **YES** — four bands, same structure as 4 colours |
| §4B(2) does the counter keep running? | ★★★★ **In kind YES (1 above, 2 below) — but with a periodic repeat 4 colours does not show** |
| §4C stage 2 (FIRQ) | **NOT ATTEMPTED** — stopped at the trigger |
| §4D three boundaries under FIRQ | **NOT ATTEMPTED** |

## §4A — the buffer, and the vectors, with no all-RAM

★★★★★ **The 30,720-byte buffer is filled through a MOVING TWO-SLOT WINDOW, so `$FFDF` is never written
and the 6809's vectors stay in ROM.**

The observation that makes it free: **VOFFSET addresses PHYSICAL RAM, not the CPU's logical space**
[`gfx.s:206-215`; S-01 confirmed `$E800` → physical `$74000` empirically]. The GIME fetches the
framebuffer without going through the MMU, **so the buffer never has to be visible to the CPU all at
once — only the bytes being WRITTEN do.** The buffer lives at physical `$74000`–`$7B7FF` (blocks
`$3A,$3B,$3C,$3D`) and is filled through logical `$4000`–`$7FFF`, remapping slots 2 and 3 once at the
seam. **Logical `$4000`–`$7FFF` is RAM under every map.**

★★★★★ **So §1.2's trap is AVOIDED rather than managed.** Nothing in this spike can produce an NMI
through a garbage vector, which is the false negative the series exists to prevent. ★★★ Code at `$3000`
is slot 1 (block `$39`) and is never remapped; slots 2 and 3 are restored before the fill returns.
★★ The seam is crossed exactly once (30,720 < 32,768).

## §4B(1) and §4B(3) — the split, at the port's depth

```
$1E / $16, stripe fill $0F, one split at dly 2400
  y= 30 runs 2,2,2,2,...   y=110 runs 2,2,2,2,...   y=210 runs 4,4,4,4,...
  row transitions  30:319  50:319  70:319  90:319  110:319 | 130:159 150:159 170:159 190:159 210:159
  ratio 2.01

three splits (dly 1200 / dly2 700 / dly3 700)
  row transitions  30:319 | 50:159 70:159 | 90:319 110:319 130:319 | 150:159 170:159 190:159 210:159
  band                320 |     160      |          320           |             160
```

★★★★★ **§3(2)'s caution honoured, and it matters: at 4 bpp a byte is TWO pixels, so the stripe `$0F`
gives runs of 2 and 4 — NOT S-01's 4 and 8 at 2 bpp.** Different arithmetic, same conclusion; **had the
numbers matched, the proof would have been a coincidence.**

## §4B(2) — the counter, and the difference

**Instrument:** the row-number fill, read as *how many consecutive displayed rows share a row
signature*. Above the switch the stride is one source row per displayed row, so the answer must be 1;
below it two displayed rows fall inside one source row, so it must be 2. ★★★★ **This needs no palette
calibration at all**, which is why it was chosen: at 16 colours a byte is two pixels and an absolute
decode would need all sixteen entries mapped.

```
16 COLOURS ($1E/$16):  1,1,1,1,1,1,2, 1x14,2, 1x14,2, 1x14,2, ... then 2,2,2,2,... (the narrow band)
                       runs of 1: 119   runs of 2: 37   anything else: 0
 4 COLOURS ($15/$0D):  1 x 171 (unbroken), then 2,2,2,...
                       runs of 1: 171   runs of 2: 11   anything else: 0
```

★★★★★ **In kind the behaviour matches — 1 above, 2 below — so the counter keeps running at 16 colours
too.** ★★★★★ **But at 16 colours ONE SOURCE ROW IS DISPLAYED TWICE EVERY 16 ROWS, and at 4 colours it
is not.** The period is exact and the 4-colour control with the *same instrument* is unbroken over 171
rows, so **this is not an instrument artefact of the signature method.**

### ★★★★★ ISOLATED: the repeat has NOTHING to do with the split

**Run with NO HRES change at all — `VresT = VresB`, so the mode never changes mid-frame:**

```
16 colours ($1E only):  runs of 1: 175   runs of 2: 9    <- same periodic positions
 4 colours ($15 only):  runs of 1: 191   runs of 2: 1    <- essentially clean
```

★★★★★ **So it is a property of the 320x192x16 mode itself, not of the mid-frame write.** ★★★ And the
fill is not at fault: a host-side readback confirms **every source row 0..100 holds its own number**
(`r0=$00 r1=$01 ... r30=$1E r31=$1F r32=$20 r33=$21`), so the repeat is on the display side.
★★ The 4-colour lone "2" is the last scanline, where 193 active scanlines at 80 B/row read slightly
past a 15,360-byte buffer — an edge, not a pattern.

★★★★ **Where they fall matters**: the repeats occur in roughly the **first 128 scanlines** and then stop,
about **9 occurrences**, so 193 scanlines display ~184 source rows. **A ~4-5% vertical compression in
the upper two thirds of the frame.**

### ★★★★★ CHASED, AND IT TURNED UP A SEPARATE FINDING THE PROJECT SHOULD CARE ABOUT

**VOFFSET's effective granularity in this path is 256 BYTES, not 8.** Sweeping it with no HRES change:

```
VOFF $E800  (+0 bytes)    1,1,1,1,1,1,2,...   runs of 1: 175  runs of 2: 9
VOFF $E801  (+8 bytes)    1,1,1,1,1,1,2,...   IDENTICAL
VOFF $E810  (+128 bytes)  1,1,1,1,1,1,2,...   IDENTICAL
VOFF $E820  (+256 bytes)  1,1,1,1,1,2,...     SHIFTED by one row
```

★★★★★ **`+8` and `+128` are byte-identical; only `+256` moves anything. So the register's low 5 bits
are ignored and the framebuffer can only be positioned on a 256-byte boundary.**

★★★★ That fits MAME's fetch expression, which is worth recording in full because `gfx.s` does not have it:

```cpp
offset += get_data((m_video_position + ((base_offset + offset) & 0xff)) | bank_512k, &data, &mode);
//  base_offset = m_legacy_video ? 0 : (m_gime_registers[0x0f] & 0x7f) * 2;   <-- $FF9F, HOFFSET
```

**The COLUMN offset supplies the low byte of every fetch address, and `$FF9F` (HOFFSET) is added into
it.** ★★★ So `$FF9F` is not merely "required to be 0" as `gfx.s:221-223` has it — **it participates in
the fetch address on every byte**, and a nonzero value shifts the whole picture horizontally within a
256-byte window.

★★★★★ **THIS IS THE KIND OF THING `gfx.s`'s UNDISCHARGED VOFFSET DEBT IS ABOUT** (*"inferred from
disassembly; NOT verified… discharge by sentinel test"*). ★★★ **It does not contradict `physical >> 3`
— S-01 proved `$E800` → physical `$74000` — it says the low bits of that quotient do not reach the
hardware.** ★★ A port that ever needs finer than 256-byte framebuffer placement cannot have it.
**Carried as a finding for the HAL, not applied here** (§4A/§6: nothing under `src/`).

### What the row repeat is not, and what was checked

★★★ MAME's mechanism is `m_video_position += pitch` gated on `++m_line_in_row >= get_lines_per_row()`,
and **`get_lines_per_row()` returns 1 for LPR = 000** (`$FF98 & 0x07` cases 0x00 and 0x01 both give 1).
`$FF98 = $80` is written identically at both depths, **so LPR as written is not the differentiator** and
the simple "one row, many scanlines" path does not explain a 16/15 ratio. ★★ `$FF99`'s LPF field
(bits 6-5) is 00 in both `$15` and `$1E`. **Not diagnosed further — §6 says stop and report.**

### ★★★★★ AND A CONSEQUENCE THAT REACHES PAST THIS SPIKE — stated as a HYPOTHESIS, not a claim

★★★★★ **`$1E` is the mode the port uses for its main display TODAY** [`hal.inc:328`,
`GFX_MODE_320x192x16`]. If MAME shows one framebuffer row twice, periodically, in that mode, then **the
port's rendered picture is slightly vertically compressed and its byte gates cannot see it** — because
they compare the FRAMEBUFFER, and *"a readback path and a display path are different paths"*
[idiom 19j; AD-114 was exactly a case where both planes were byte-identical and never presented].

★★★★ **This is a hypothesis with a cheap test and it is NOT this spike's to run**: point the same
row-signature instrument at the port's own display, or compare a picture-gate framebuffer against the
rendered screen row by row. ★★★ **If it holds, it is a finding about every eye gate this project has
passed.** ★★ If it does not, then something about this spike's configuration provokes it and that is
worth knowing too.

## ★★★★ AND A CAVEAT ABOUT THIS INSTRUMENT, which must be stated with its result

★★★★★ **The 4-colour control put the 1→2 transition at run index 171 (≈ scanline 196), but `dly 2400`
places the boundary near y=123** — where S-02's absolute decode found it, and where the stripe
transition profile independently puts it. **So the row-signature instrument's ABSOLUTE POSITIONS are
wrong, even though its 1-vs-2 pattern is clean.**

★★★ **Only the pattern should be read from it, not the position.** ★★ Why the positions are wrong is
not established, and **the repeat-every-16 finding rests on the pattern rather than on any position**,
so it survives the caveat — but a later task must not quote this instrument for a scanline number.

## What is still owed

1. ★★★★★ **Diagnose the periodic row repeat at 16 colours**, since it is the port's own depth. The
   likely suspects are `$FF98`'s LPR field and the field-length/LPF interaction — **and MAME's source is
   the cheap way in, as it was for S-01** (`record_full_body_scanline` and whatever advances the row
   index). ★★ Until then, **the 16-colour result is "splits correctly, with a 6.7% vertical stretch of
   unknown origin."**
2. ★★★★ **Fix or replace the row-signature instrument's positional reading**, or retire it in favour of
   S-02's absolute decode extended to 16 colours (which needs all 16 palette entries calibrated).
3. ★★★★★ **Stage 2 (FIRQ) and §4D are UNTOUCHED** and remain the binding question for message boxes.
4. ★★ **A pool row is still owed** for S-01 §7.3's finding, now with a second instance in S-02 §7.1.

---

# S-02 — Where does the data below the switch come from?

★★★★★ **ANSWERED: §1.1 CASE 1. The video address counter KEEPS RUNNING.** Below the switch each row
consumes 40 bytes instead of 80, and the counter continues from exactly where the wide rows left it.
**A single linear buffer works; the picture area and the text area are contiguous with a stride change
at the boundary. This is the good case, and it makes the layout almost free.**

★★★★★ **AND THREE BOUNDARIES LAND IN ONE FRAME** (§4C), so a 320-wide message box inside a 160-wide
picture is achievable: **N splits cost N writes.**

## §4A — the table, read off the screen

Fill: row *N* holds byte value *N* in all 80 of its bytes, so a displayed row reports **which 80-byte
block** it read. Decoded from 4 pixels per row; the colour→index map was calibrated in the same session
from a `$1B` fill (indices 0,1,2,3 → black, blue, green, white — four distinct, verified before use).

**ABOVE the boundary — the control (§4A(2)), and it passes:**

```
w=2 (the 320-wide reading):  y25=1  y26=2  y27=3 ... y121=97  y122=98
```

★★★★★ **Exactly +1 per displayed row, unbroken over 98 rows.** The rows above read as themselves, so
the instrument is sound and what follows can be trusted. ★★ The offset is `src = y - 24` (the first
active scanline shows source row 1, not 0) — noted, not chased; it does not affect the stride question.

**BELOW the boundary:**

```
w=4 (the 160-wide reading):  y123-124=99   y125-126=100  y127-128=101  y129-130=102 ...
                             y211-212=143  y213-214=144  y215=145
```

★★★★★ **The source row advances by one every TWO displayed rows, and it continues from 98 to 99 without
a break.** Two 40-byte rows consume one 80-byte block — which is the counter running on at the new
stride and nothing else.

★★★★ **The arithmetic agrees with the screen**, which is the check that matters: 95 narrow rows × 40 B
= 3,800 B = 47.5 blocks, so the last value should be ≈ 99 + 47 = 146, and the screen says 145.

**§4A(3) — the boundary row:** ★★★ **WHOLE.** y=123 decodes as the first half of the `99` pair. Not
split, not skipped, not duplicated.

## §4B — which of the three it is

★★★★★ **Case 1, unambiguously.** Case 2 (counter restarts or is re-derived from VOFFSET per field)
would have shown the values below the boundary restarting near 0; they continue from 98. Case 3
(a partial line, a skipped row, an offset by the difference) would have shown a discontinuity at the
boundary; there is none. ★★ **The byte arithmetic and the screen agree, so there is no disagreement to
report as a finding.**

## §4C — do a second and third split land?

★★★★★ **YES.** With one frame and three writes (`dly 1200 / dly2 700 / dly3 700`):

```
row transitions  30:159 | 50:79  70:79 | 90:159 110:159 130:159 | 150:79 170:79 190:79 210:79
band                320 |     160     |          320           |             160
```

**Four bands, three boundaries, at the three delays asked for** (≈y39, y88, y137 predicted from the
delays; the band edges bracket all three). ★★★★ **So the message-box problem is a PRECISION question,
not a feasibility one** — which is the outcome §4C said would matter: 160-wide is a picture area AGI
can actually put windows in.

★★★ The palette flip at each split is invisible by construction — the stripe fill `$0F` uses indices 0
and 3 and the flip writes index 1 — **so the only thing that can change a run length here is HRES.**

★★★★★ **EYE-CONFIRMED (AC-5), at normal speed, against an expectation stated before the run** — four
horizontal bands alternating fine and double-width stripes, fine at the top. **Jay: *"that's what i
see."*** ★★★ **Every result in S-01 and S-02 now carries two independent confirmations of the same
frame: a host-side number and a person.**

## ★★★★★ A CORRECTION TO S-01 §7.3, now properly isolated

S-01 concluded that the bitmap stays current only while a **palette** value changes. ★★★★ **The arm that
would have separated the two was missing**: the working run changed *both* the palette and `$FF99`. It
has now been run — **`$FF99` changing while the palette is held constant leaves the screen broken** — so
**a changing palette value is required, and `$FF99` traffic is not a substitute.** S-01's attribution was
right; it was under-tested, and the test that could have falsified it is the one S-01 §7.3 says to run.

★★★ **This is what `s01_palreg` exists for**: the flip is pointed at `$FFB8`, which 4-colour mode never
displays, so S-02 gets a refreshing bitmap *and* four stable decodable colours. **Those two requirements
collide on `$FFB1` and the coupling had to be broken.**

## ★★★★ Four defects in the instrument, which was untested code by definition (§3.1)

★★★ Recorded because §3.1 predicted them and because the *shape* of two is worth carrying:

1. ★★★★ **The palette was coupled to the flip.** Index 1 took its init value from `s01_colA` and index 3
   from `s01_col3`; both defaulted to `$3F`, so two indices rendered identically. **Calibration refused
   to run**, which is the behaviour wanted — but the first failure message named the symptom
   (*"indices 1 render alike"*) and not the datum. Printing the four colours identified it at once.
2. ★★★★★ **A subroutine placed in a fall-through path, twice.** `s01_palwr` sat immediately after
   `s01_bot_hres`'s `bsr` to it, so control fell back in and ran `puls b,pc` against nothing. Moving it
   put it in the **init's** implicit fall-through into `s01_loop` instead — so the init ran the fill
   twice and `rts`-ed into `$8006`. ★★★ **The cure is not a better position but an explicit `bra
   s01_loop`**: the init reached the loop by falling through, which was correct only while nothing sat
   between them.
3. ★★★★ **The host poked parameters the guest's INIT consumes AFTER setting PC.** A race, not a typo:
   the guest starts executing immediately and the init had already filled and set the palette from the
   defaults. **A poke after handover works only for values the LOOP re-reads.**
4. ★★ **Short branches out of reach** once the extra-split block was added; made long rather than
   marginally short.

★★★★★ **What found 2 and 3 was `s01_frames = 0` beside a correct framebuffer and a correct palette** —
the liveness witness naming the *guest* rather than the display — **and then the PC and S.** Two
hypotheses about the palette had already been spent by then. ★★★ **S=$2F08, eight bytes above its
initial value, is what said "a return with nothing pushed"**, and that is a datum no amount of staring
at the screen would have produced.

---

## ★★★★★ CORRECTION — three claims in earlier drafts of this note are WITHDRAWN

0. ★★★★★ **"Stage 1 NOT ANSWERED / the instrument is not trustworthy" is WITHDRAWN. Stage 1 PASSES.**
   The arm was broken by my own control (see *What unblocked stage 1*), not by the model. ★★★ The
   caution that accompanied it was still the right call at the time: **reporting a stage-1 failure then
   would have closed 160-wide on an instrument that was wrong**, which is exactly what §7 guards
   against.

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

## ★★★★★ What unblocked stage 1: reading MAME's source, and finding my own test invalid

**Eight black-box hypotheses were spent before the answer came from twenty lines of emulator source.**
`src/mame/trs/gime.cpp`:

```cpp
case 0x09:   //  $FF99 Video Resolution Register
    if (xorval & 0x60)       // xorval = old ^ new; 0x60 is bits 5-6 = LPF only
        update_geometry();
    break;
```

★★★ So **an HRES change (bits 2-4) triggers nothing at write time** — which is why a static `$FF99`
sweep looked inert. But the rendering path does not read the register live:

```cpp
update_value(&m_scanlines[physical_scanline].m_ff99_value, m_gime_registers[0x09]);
update_value(&m_scanlines[physical_scanline].m_ff98_value, m_gime_registers[0x08]);
...
else if (scanline->m_ff98_value & 0x80)   /* GIME graphics */  else  /* GIME text */
```

★★★★★ **`$FF98` AND `$FF99` ARE RECORDED PER SCANLINE, and every scanline renders from its own
recorded copy** — including whether it is graphics or text. **That is why a mid-frame HRES change
works at all, and it is the mechanism §3.1 said was undocumented.**

★★★★★ **AND `update_value` ONLY ACTS WHEN THE VALUE CHANGES — WHICH INVALIDATED MY OWN HYPOTHESIS
TEST.** Hypothesis 6 was *"the bitmap only refreshes on palette writes"*, and I tested it by adding
`$FFB1` traffic to mode 1 **with `ColA == ColB` so as not to introduce a visual variable.** Equal
colours mean the value never changes, so `update_value` never fires — **I removed the very thing the
hypothesis was about and recorded it as eliminated.** The moment mode 1 ran with `colA ≠ colB`, the
whole screen rendered correctly and stage 1 answered on the first attempt.

> ★★★★★ **The lesson is not "read the source sooner", though that was worth three hours. It is that a
> control which holds a variable constant can silently delete the mechanism under test** — and an
> eliminated hypothesis is only eliminated if the test could have confirmed it.

★★★ Why stage 0 worked throughout while every other arm looked broken: **stage 0 flips a palette
register between two DIFFERENT values twice per frame**, so `update_value` fires and the frame is kept
current. Nothing else in the spike changed a register value at all.

---

## The dead end, kept because the reasoning is reusable

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

## What is still owed

★★★★★ **§3.2 IS UNANSWERED AND IT IS THE ONE THE SPIKE CALLED "MOST LIKELY TO BITE."** The video
address counter advances by the current mode's line length — 80 bytes at 320-wide, 40 at 160 — so rows
below the switch consume a different number of bytes than rows above, and **where the text area's data
comes from after the switch decides the whole buffer layout.** The instrument for it is built and
unused: `s01_fillm = 1` fills row *N* with byte value *N*, and since the four palette entries are
distinct the displayed byte value says which source row arrived. **Nothing has been measured here, and
no buffer layout should be designed until it has been.**

★★★★ **Stage 2 — precision and jitter**, per §4: FIRQ off the horizontal-border interrupt, and the
question of whether the boundary holds steady over minutes or drifts by a scanline. ★★ Partial
evidence already exists: every sweep point reported *"steady across samples"* over 4 consecutive
frames, and in stage 0 **2 of 19 delays jittered by one scanline**, which is what a write landing on a
line boundary should do. **That is not minutes of stability and it is not a FIRQ-paced boundary.**

★★★ **The 16-colour pair `$1E`/`$16`**, which is the port's real target and is deliberately untested: a
16-colour buffer is 30,720 bytes and would cross `$8000` into ROM territory, forcing all-RAM mode and
putting the interrupt vectors in RAM. **A 4-colour pass still needs confirming there**, and the mode
pair is already host-poked so it needs no reassembly — only a buffer that fits.

★★ **The `$FFDF` divergence** (all-RAM not written) will have to be revisited if the 16-colour buffer
forces it; the reason it was skipped is recorded at the end of this note.

★ **And if it ever matters on silicon:** §3.4's caveat is unchanged. Two GIME revisions, the later
changed video timings, a scanline-counter fault on both, and certain HRES values corrupt video on the
'86 part. **MAME models one behaviour.**

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
