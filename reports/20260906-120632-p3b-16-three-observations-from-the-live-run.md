## Form B Report — P3b.16 — three observations from the live run (M-53)

**Class:** recon. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-06 (note carried no receipt timestamp; report written 2026-09-06T12:06:32-04:00).
`coco_agi` `wip` @ **`216d6935d18a15f2614fc904e86286148b5450a6`**, `origin/wip` identical,
**status clean**. `gate_audit.py --verify` **8/8 identical** at start and end. No file was modified
by this task.

---

### 1 — Summary

**All three observations reproduce, and they are three different things.**

★★★★★ **§1 is architectural and is a stop-and-report.** The visible fill is a P3b.15 artifact by
construction — the display path has **no present point** and re-asserts VOFFSET at the plane the
renderer is writing, every frame. But the reason it cannot simply be fixed is §3.6: **with one
framebuffer there is no back buffer to render into and flip.** That is Jay's decision to revisit.

★★★★★ **§2 reproduces and is worse than described, and it has a pattern nobody was looking for.**
The castle room diverges from the oracle by **28.8%**, in exactly the shape "some fills but not all"
predicts. Room 3 diverges by **71.5%**. **Picture 80 — the one of the three that is in the renderer's
gate corpus — is 0.0%.**

★★ **§3 does not reproduce as a room change.** The plane holds picture 1, and across 200 cycles the
room goes 83 → 1 and stays. What was seen as a switch is most likely the castle room re-rendering
badly.

---

### 2 — Files modified

**None.** This task measured and changed nothing.

---

### 3 — Findings

#### 3.A ★★★★★ The visible fill: a harness artifact, over an architectural constraint [§1]

**The artifact half, measured from the code I wrote:** `p3b_show.lua`'s notifier fires **every frame**
and unconditionally writes `$FF98`/`$FF99`, the palette, and VOFFSET ← `ph_blk_fb * 1024`. There is no
present point and no gate on render completion. **The display is a continuously-live view of the
working plane**, so watching strokes and floods appear in resource order is guaranteed, not symptomatic.

★★★ **Answering the note's three questions directly:**

| question | answer |
|---|---|
| does the display point at the plane the renderer writes, or at a copy? | **the plane the renderer writes** — `ph_blk_fb`, blocks 2-5, read from the guest's own allocator byte |
| is there a present POINT at all? | **no.** VOFFSET is re-asserted every frame, deliberately, so a guest write cannot undo it |
| if §3.6's single buffer means the visible plane IS the working plane, is a visible fill unavoidable? | ★★★★ **yes, without a second buffer** |

★★★★ **The architectural half.** The port renders directly into its only framebuffer. To present a
finished room it would have to render somewhere else and flip — which is the second buffer §3.6
declined. ★★★ **And this is the shape T-P0-019 established Sierra does NOT have:** `$E1B1` is a format
conversion emitting an **already-rendered** buffer, 24 cycles/pixel, zero comparisons on pixel data.
**Render-then-present is the reference architecture and single-buffer-with-save-under is not it.**

★★ **Not fixed at site, per the note.** Adding a buffer is a §3.6 revision and it is Jay's. ★ What
*could* be done cheaply without touching §3.6 is to move the display's VOFFSET write to a present
point — but with one buffer that only changes *when* the tearing is visible, not whether it is.

#### 3.B ★★★★ The castle room diverges, and so does room 3 [§2]

Guest planes dumped at the end of a 40-cycle run, compared against the oracle's own picture
references. The guest doubles each pixel into both nibbles and the oracle does not; the comparison
accounts for that [P3b.15 §3.E].

| room | picture the plane holds | in the gate corpus | differing | still WHITE (fill never ran) | filled wrong |
|---|---|---|---|---|---|
| 80 | pic080 (71.2%→ n/a, exact) | **yes** | **0 of 26,880 (0.0%)** | 0 | 0 |
| 1 (castle) | pic001, best match 71.2% (next 22.1%) | no | **7,745 (28.8%)** | **2,963** | 4,782 |
| 3 | pic003, best match 28.5% (next 20.9%) | no | **19,217 (71.5%)** | 1,481 | 17,736 |

★★★ **The shape matches Jay's description exactly.** 2,963 pixels still holding the clear value 15 are
fills that never ran — "some wireframe filling but not all" — and they sit alongside 4,782 pixels that
were filled with the wrong value. **This is a different defect from AD-111's clear**, which produced
*no* fills at all and is fixed.

★★ **Both planes were checked.** The visual figures are above; the priority plane diverges too, and is
not separately characterised here.

#### 3.C ★★★★★ The pattern nobody was looking for — and why it is NOT yet a finding

**The three samples correlate with gate-corpus membership, not with sprite count:**

```
Kingquest1-001  ABSENT from picset.json   ->  28.8% differing
Kingquest1-003  ABSENT                    ->  71.5% differing
Kingquest1-080  present                   ->   0.0% differing
```

★★★ **And the corpus is small against what exists:** picset carries **16 Kingquest1 pictures**; the
oracle has **82** references for that title alone. The renderer's 45/45 covers 45 pictures across
three games.

★★★★★ **THIS IS THREE SAMPLES AND I HAVE NOT RUN THE TEST THAT WOULD SETTLE IT.** Two readings fit
the same data and they have opposite consequences:

1. **The defect is in p3b's integrated path** — compositing, staging, or the room-render entry — and
   the renderer is fine. The 1,163 (room 1) and 401 (room 3) bytes whose two nibbles disagree
   **scale with sprite count** (4 and 2 sprites), which points at the compositor writing single
   nibbles into a doubled-nibble plane. Picture 80's run had 1 sprite and 0 differing bytes.
2. ★★★★ **The renderer is correct on exactly the 45 pictures it is gated on.** Under this reading the
   corpus has been certifying itself, and every "the renderer is gated" claim in the project covers
   45 of roughly 250 pictures.

★★★★★ **THE DISCRIMINATOR, NOT RUN: render picture 1 through `pic_probe`** — the gated renderer, no
sprites, no p3b, no compositor. If it renders picture 1 correctly, reading (1) holds and this is a
p3b defect. If it renders picture 1 badly, reading (2) holds. **It requires staging picture 1 into the
sweep, which the fixed 45-picture set does not currently include.**

★★ **Stated at its real strength: a correlation over three samples with a named, cheap, unrun
experiment that would resolve it.** [L-41 — a ratio is not a cost; three points are not a pattern.]

#### 3.D §3 does not reproduce as a room change

★★ **The plane holds picture 1**, and by a clear margin: 71.2% match against 22.1% for the next best
of 82 references. It is not a different room's picture.

★★ **The room does not move.** Over a 200-cycle run the room column reads 83 for cycles 1-3 and 1 at
cycle 200; `p3b_room.lua` jumps **once**, at cycle 8, and latches (`done = true`). Nothing in the
harness or the observed LOGIC switches rooms after that.

★ **A hypothesis, offered as one:** the castle room renders 28.8% wrong with 2,963 pixels of unfilled
white in large regions. **A render in that state could reasonably read as "just ground and clouds"** —
i.e. what looked like a switch may be the same room, drawn badly, resolving as the render proceeded.
Not established; it is consistent with the measurement and with §3.A's continuously-live display.

---

### 4 — Verification

This task has no acceptance criteria of its own; it answers a note. Evidence classes:

- **§1 [byte-comparable → architectural]** — read from `p3b_show.lua`'s own source and §3.6. **Answered.**
- **§2 [byte-comparable]** — three rooms, planes dumped and diffed against oracle references. **Reproduces.**
- **§3 [state-comparable]** — best-match over 82 references, plus the room column over 200 cycles.
  **Does not reproduce as described; explained differently.**
- **§3.C [suite]** — **NOT ESTABLISHED.** Correlation over three samples, discriminator named and unrun.

★ **AD-111 stands unretracted**, as the note says: the clear fix is real and picture 80 is 0 of 26,880
on both planes. These are observations about what remains.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*§2 — the three rooms:*
```
room 80  final room 80, sprites 1, err 0     VISUAL differing 0 of 26880 (0.0%)
                                             PRIORITY differing 0 of 26880 (0.00%)

room 1   final room 1, sprites 4, err 0
  pixels                : 26880
  identical             : 19135 (71.2%)
  DIFFERING             : 7745 (28.8%)
    guest still WHITE 15: 2963  <- a fill that never ran
    guest a wrong value : 4782
  bytes with unequal nibbles: 1163

room 3   final room 3, sprites 2, err 0
  identical             : 7663 (28.5%)
  DIFFERING             : 19217 (71.5%)
    guest still WHITE 15: 1481
    guest a wrong value : 17736
  bytes with unequal nibbles: 401
```

*§3 — which picture the plane actually holds (82 references scored):*
```
room 1 plane          room 3 plane
pic001  71.2%         pic003  28.5%
pic050  22.1%         pic050  20.9%
pic051  21.9%         pic075  18.9%
pic080   4.2%  (last)
```

*§3 — the room column over 200 cycles:*
```
room 83: cycles 1..3
room  1: cycle 200
★ room jump at cycle 8: var0 <- 1, flag 5 set     (p3b_room.lua jumps once and latches)
```

*§3.C — corpus membership and size:*
```
Kingquest1-001: ABSENT
Kingquest1-003: ABSENT
Kingquest1-080: present
picset Kingquest1 entries : 16
oracle pic*.visual.bin    : 82
```

*§0 — state:*
```
HEAD 216d6935d18a15f2614fc904e86286148b5450a6 == origin/wip, status clean
gate_audit --verify: 8/8 identical (start and end)
```

**25.2 bundled-artifact grep:** N/A — nothing imported, nothing committed but this report. The oracle
references are the project's existing `oracle/dumps/base-Kingquest1/`, read only.

**25.3 operator-runtime-smoke:** **pending Jay, INCOMPLETE.** Launch path `poke`. §1 explains why the
gate cannot currently show a finished room; §2 is the defect it revealed.

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **§1 is reported, not fixed.** The note flags it as possibly architectural and it is:
   presenting a finished room needs a buffer §3.6 declined. **Stop-and-report** rather than adding one.
2. ★★★★ **§3.C's discriminator was named and NOT run.** Jay asked for the report at that point. It
   changes what §3.C means and the report says so rather than quietly picking a reading.
3. **§3 was re-framed rather than confirmed.** The observation was real; "the room switched" is not
   what the measurement shows, and an alternative is offered as a hypothesis.
4. **Nothing was changed.** No source, no harness, no gate.

**ROUTE ACCOUNTING.** No route proposed. **Delivered:** all three observations answered by measurement,
with the third re-framed. **Not delivered:** §3.C's resolution, which is one experiment away.

---

### 7 — Uncertainty flags

- ★★★★★ **§3.C is a correlation over three samples.** Do not cite "the renderer is only correct on
  gated pictures" from this report. **Run the discriminator first** (§3.C).
- ★★★★ **The guest planes were dumped WITH sprites composited**, so every figure in §2 contains an
  unknown sprite contribution. Picture 80's run had 1 sprite and 0 differing, which bounds that
  contribution as small in at least one case — but it is not zero in general, and the unequal-nibble
  counts scaling with sprite count say the compositor writes into these planes.
- ★★★ **§3.D's hypothesis is a hypothesis.** That a 28.8%-wrong render "reads as ground and clouds" is
  consistent with the numbers and is not established. Jay is the authority on what he saw.
- ★★ **Room 3's best match is only 28.5%**, against 20.9% for the next. That margin identifies the
  picture but is not comfortable, and a 71.5%-wrong render makes identification harder — the reasoning
  is circular at the edges and is flagged rather than leaned on.
- ★★ **The priority plane was not characterised** for rooms 1 and 3, only the visual.
- ★ Carried, untouched: `reg_discipline.py` 8 vs a recorded 5 [AD-104]; `scummvm.pin`'s five patches
  against eight applied; `p3b_probe_pk`'s unrecorded build line and 110-byte-stale artifact.

---

### 8 — Follow-up candidates

1. ★★★★★ **Run §3.C's discriminator** — stage picture 1 into the sweep and render it through
   `pic_probe`. It decides between "p3b has a defect" and "the renderer is gated on 45 of ~250
   pictures", and those have very different consequences.
2. ★★★★ **Byte-check the compositor in the integrated path** (carried from P3b.15 §8.1). The
   unequal-nibble counts scaling 401→1,163 with 2→4 sprites is the sharpest lead in this report.
3. ★★★★ **§3.6's single-buffer decision** — Jay's. §3.A states what it costs: no finished-room
   present is possible without a second buffer, and the reference architecture has one.
4. ★★★ **Widen the renderer corpus** beyond 45 pictures, or state explicitly that 45 is the claim.
5. ★★ **Re-check gate artifacts at task END** — carried from P3b.14 and P3b.15, unactioned twice.
6. ★★ **Move the display's VOFFSET write to a present point** — cosmetic given §3.A, but it would stop
   the harness from making the port look worse than it is.

---

### 9 — User interaction during task

Jay's three observations from watching P3b.15 run, which are the whole content of this task:

1. *"I thought the screen was going to be drawn and then presented. I am seeing the fill happening,
   which I believe is wrong."* → §3.A. **Correct on both counts**: it is happening, and
   render-then-present is the reference architecture.
2. *"the castle room — wall, moat, sidewalk — showed some wireframe filling but not all."* → §3.B.
   **Reproduces at 28.8%, in exactly the shape described.**
3. *"it showed the castle room, then switched to just ground and clouds."* → §3.D. **The room does not
   change**; a hypothesis for what was seen is offered.

★★★★ **The eye gate has now found, in two sittings, two defects and one architectural question that
eight byte gates did not.** [AD-111, and §3.A/§3.B here.]

### 10 — Candidate(s) captured this task

`None.` — ★ The instrument lesson here is the same one already pushed as
**[[a-test-corpus-that-cannot-fail-must-be-built-not-found]]**: a 45-picture corpus that the renderer
passes may be selecting for what the renderer does well. **If §3.C's discriminator confirms reading
(2), that row gains its second instance and should be re-captured then, with the evidence** — writing
it now would be capturing a correlation over three samples as though it were a principle.

★ INFRA.1's two rows remain owed (its §10).

### 11 — Commit

Committed on `wip` and pushed to `origin/wip`, staged by explicit path per §2E: this report only.
★ No game content (§2P) — the report carries counts and percentages, no pixels.
