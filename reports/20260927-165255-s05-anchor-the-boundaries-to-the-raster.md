## Form B Report — Spike S-05 — Anchor the boundaries to the raster
**Class:** recon (spike). wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-27 16:52:55 (HEAD `bc54a07`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that is not this task's and was not staged.

---

### 1 — Summary

**The FIRQ-placed raster program works, and the reason it appeared not to was a signed indexed
offset in one instruction I wrote myself.** With it fixed, a boundary lands exactly where the raster
table places it — `y = line − 46`, measured, not assumed — at **300 of 300 frames = 100.00% with 0
frames deviating**, and a three-entry program puts a **320-wide band bracketed by 160-wide regions**
at a position the table controls. That is the mechanism Jay's requirement needs: 160 for the picture,
320 for a message box inside it.

★★★★★ **The task also withdrew more claims than it established, and the withdrawals are the more
useful half.** Six previously-reported figures are void, three instruments were found unsound, and
one whole line of investigation (a border flicker) turned out to be this spike's own scaffold. Every
withdrawal is recorded below with what disproved it.

★★★★ **A design consequence surfaced that the spike was not looking for and that outranks its
measurement:** an HRES change is per-scanline, so a message box narrower than the screen still forces
its entire rows to 320, and the picture either side of the box must be emitted at 320 on those rows.
Jay identified this from the eye gate before any byte reading suggested it.

---

### 2 — Files modified

- `poc/s01_hres/s01.s` — the signed-offset fix (two sites, both now call `s01_palwr`); the FIRQ
  handler restructured to own the frame reset off VBORD; `s01_m3own`, `s01_bset`, `s01_bcol`,
  `s01_hflip`, `s01_hwrite` added; the hardcoded `eora #$3F` border flip made to honour `s01_bxor`.
- `poc/s01_hres/s01_run.lua` — raster-table parser rewritten with validation; full-height row dump
  (`-FullDump`); border sampler (added, corrected twice, and its output withdrawn); parameter and
  liveness readbacks moved after settle.
- `poc/s01_hres/s01.ps1` — `-BSet`, `-BCol`, `-FullDump`, `-M3Own` switches.
- `poc/s01_hres/NOTES.md` — the §8 record, including the four withdrawn claims and the lesson.
- `harness/tools/fix_mojibake.py`, `mojibake_selftest.py`, `run_gates.sh` — T-P0-158 Part A, reported
  separately at `reports/20260926-200632-p6104-mojibake-gate.md`; unchanged this task and listed only
  because the suite output below exercises them.

Explicit-path staging throughout; no `git add -A`.

---

### 3 — Reasoning

#### 3.1 The defect, and why it hid

The handler's paired palette write was inlined as `ldx #$FF00 / ldb s01_palreg / sta b,x`. **6809
accumulator-offset indexing treats the offset as SIGNED.** `s01_palreg = $B1 = −79`, so every write
landed at `$FF00 − 79 = $FEB1` — plain RAM, not a palette register.

`s01_palwr`, twenty lines away in the same file and proven since S-02, uses **`abx`**, which adds B
**unsigned**. That is why it is written that way. ★★★★★ **I inlined a reimplementation of a working
subroutine instead of calling it, and the reimplementation assembles cleanly and stores somewhere
plausible.**

It hid because this spike's own established finding is that *the screen only stays current while some
palette value CHANGES*. A handler that never reaches the palette therefore produces no boundary —
which reads as "the mechanism does not work" rather than "the refresh never happened".

**Authority tier: none of this rests on ScummVM or the Specs.** It is the CoCo3's instruction set and
MAME's rendering, so the evidence is tier 2 (the machine under emulation) plus the citations in §3.3.

#### 3.2 §2H's three checks, applied to the mechanism

1. **Is there a second mechanism serving a different object class?** Yes, and it is the one that
   solved this. The *cycle-counted* path (stage 1) places the same boundary from the main loop and
   works. Treating the FIRQ handler as the only mechanism is what kept the investigation inside it.
2. **Name the routine that CALLS it.** The caller carried the fact. Stage 1's boundary path ends
   `std $FF98` **then `lbsr s01_palwr`** — the palette write is part of the boundary, not decoration.
   The handler had the first half and a broken copy of the second.
3. **Grep the prior record for the same subsystem.** ★★★★ **Not done early, and it would have cost
   a day.** The S-03 header already recorded this exact symptom — *"the first stage-1 and static runs
   displayed a screen that CANNOT have been this framebuffer… the display was showing someone else's
   memory"* — and its fix (pin `$FFA0-$FFA7`, select MMU task 0 via `$FF91` bit 0).

#### 3.3 What is now cited rather than swept

★★★★★ **S-05 §4A said the FIRQ enable bit and vector slot could not be cited because
`docs/ground-truth/` holds only a `.gitkeep`. That was §2S's error**: the reference is in both
siblings. `GIME_Reference_Manual.pdf` and `SockmasterGime.md` are present in **POP3_port** and
**karateka_coco3** `docs/ground-truth/`. Read-only use of a sibling, per §2G.

[ref: `SockmasterGime.md`, POP3_port `docs/ground-truth/`, working tree, read at HEAD of this task]

- **`$FF93` FIRQENR**: bit 5 TMR, **bit 4 HBORD** *"generated on the falling edge of HSYNC"*,
  **bit 3 VBORD** *"on the falling edge of VSYNC"*, bit 2 EI2 serial, bit 1 EI1 keyboard, bit 0 EI0
  cartridge. Reading the register *"tells you which interrupts came in and acknowledges and resets
  the interrupt source."*
- **`$FF92` IRQENR is a separate register with separate enables** — which is why the guest loses no
  frames with FIRQ enabled (§4, AC-2).
- **`$FF90` INIT0**: bit 5 IEN (GIME IRQ), **bit 4 FEN (GIME FIRQ)**. So `$5C` enables FIRQ.
- **Interrupt vectors, and the table is NOT sequential**: SWI3 `$0100`, SWI2 `$0103`,
  **FIRQ `$010F`**, IRQ `$010C`, SWI `$0106`, NMI `$0109`. ★★★ **The earlier inference that `$0106`
  "should be" the FIRQ slot was wrong for a reason the document makes plain.**

**Measured rates match the document exactly**, which is the §2W confirmation the swept choice never
had:

| `$FF93` bit | measured | documented source |
|---|---|---|
| `$08` | 1.00 / frame | VBORD, falling edge of VSYNC |
| `$10` | 260.32 / frame | HBORD, falling edge of HSYNC (~262-line frame) |
| `$20` | 0.06 / frame | TMR — timer register never written; `$000` stops it |
| `$01` / `$02` / `$04` | 0 | cartridge / keyboard / serial |

#### 3.4 The design consequence, and it is Jay's finding

★★★★★ **HRES is per-scanline. There is no way to have 320 and 160 on the same line.** Jay, from the
eye gate: *"i saw fine coarse fine coarse, but not coarse and fine on the same lines which is what i
would expect."*

So a message box narrower than the screen still forces its whole rows to 320, and the picture content
either side of it must be emitted at 320 on those rows. Consequences, with the arithmetic labelled as
**Clyde's and unverified** per §8:

| picture-area layout | bytes / frame | vs all-320 |
|---|---|---|
| all 320-wide (160 B/row × 168) | 26,880 | — |
| all 160-wide (80 B/row × 168) | 13,440 | −50% |
| 160 + a 3-text-line box (24 rows at 320) | 15,360 | −43% |
| 160 + a 6-text-line box (48 rows at 320) | 17,280 | −36% |

★★★★ **A correction to a figure this task itself produced:** an earlier estimate of "~3.5% for a
6-row box" treated text rows as scanlines. AGI text is 8 scanlines per character row, so a 6-line box
is 48 scanlines, not 6 — wrong by ~5×. The saving survives the correction; the estimate did not.

#### 3.5 Two port facts read out of the tree, bearing on whether 160-wide is worth having

- **The port composites the visual plane at 320-wide, so the saving is NOT already banked.**
  `src/hal.inc:463` — *"Callers MUST draw with HAL_gfx_cur_stride: 80 in 4-colour, 160 in 16-colour"*;
  `src/engine/mmu_phase.s:24` — *"the display is mode 2, 320x200x16, 160 B/row = 32,000 bytes"*;
  `src/harness/composite.s:36` — *"The shift is a property of the shipped framebuffer, not of the
  algorithm."* The harness composites in the oracle's 160-wide space **only for byte-identity**.
- ★★★★ **The nibble-packing cost is not unknown, and a 160-wide visual plane is a MEMORY argument
  before a cycle one.** `src/harness/composite.s:42-66`: `PRI_PACKED` already packs the priority
  plane to 4 bits/pixel, `80 × 168`, *"a nibble extract on read and a read-modify-write on write"*,
  and *"P5.4 measured the priority test at 2.7% of composite cost against the transparency test's
  70.9%."* The same comment records why it exists: *"P3b measured the draw phase at 72,194 bytes
  against 65,280 available — and packing saves exactly 13,440… Without it nothing integrates."*
  **A 160-wide visual plane would free another 13,440 bytes by the identical mechanism.**

★★★ **Not measured, and not claimed:** cycles for a packed 160-wide visual row against an unpacked
320-wide one. Priority is read-mostly and the visual plane is write-mostly, so 2.7% is evidence and
not a transfer. §8 carries it.

#### 3.6 §2S — ref and scope of every sibling claim

- `SockmasterGime.md` and `GIME_Reference_Manual.pdf` read from **`C:\Users\jayse\DEV\POP3_port\docs\
  ground-truth\`**, working tree, at this task's HEAD. Identical filenames present in
  `karateka_coco3`. **Not pushed and not fetchable by the Orchestrator** (§2.2) — these citations are
  executor-verifiable and orchestrator-unverifiable.
- The S-03 comparison in §4 AC-6 used **`coco_agi` commit `0f37499`**, `poc/s01_hres/` only, checked
  out into the working tree and restored to HEAD immediately after.
- No sibling was built, and no sibling file was modified. §2T's baseline machinery is not engaged:
  **this task touches no `SHARED` file and no `src/`.**

---

### 4 — Verification (AC-by-AC)

ACs follow the S-05 dispatch. Where the dispatch's wording is paraphrased it is marked *(paraphrased)*.

- **AC-1 [class: byte-comparable] The FIRQ handler fires, and at a rate consistent with its source.**
  **PASS.** `s01_fcount = 51283` over `197` guest frames = **260.32 per frame** against a ~262-line
  frame, matching the cited HBORD definition (§3.3). The bit sweep across all six `$FF93` sources
  reproduces the document's rates exactly.

- **AC-2 [class: byte-comparable] Enabling FIRQ does not cost the main loop its frames.**
  **PASS.** `guest frames = 197` with FIRQ **off** and with FIRQ **on** — identical. The 250→197 gap
  is the handover offset, not lost frames. ★★★ This retires the ack-interference hypothesis, which
  §3.3's separate-register citation independently explains.

- **AC-3 [class: byte-comparable] The handler's mode write executes, once per table entry per frame.**
  **PASS, after correcting my own reading of it.** `s01_hwrite` = **196 / 136 / 76** for one / two /
  three entries. ★★★★ **Those are 197 / 394 / 591 modulo 256** — `s01_hwrite` is an `fcb` byte
  counter. My first reading, "only the first entry fires", was a counter overflow: **the third
  overflow-misreading of my own instrument in this session.**

- **AC-4 [class: byte-comparable] A FIRQ-placed boundary lands where the table puts it, stably.**
  **PASS.** `y = line − 46`, exact and reproducible:

  | raster line | predicted y | measured | stability |
  |---|---|---|---|
  | 70 | 24 | `[]` — below the band scanner's window (starts y=25) | — |
  | 100 | 54 | **`[54]`** | 300/300 = 100.00%, 0 deviating |
  | 130 | 84 | **`[84]`** | 300/300 = 100.00%, 0 deviating |

- **AC-5 [class: byte-comparable] Three boundaries in one frame — a 320 box inside a 160 picture.**
  **PASS.**

  | table | predicted | measured | stability |
  |---|---|---|---|
  | `76:$16,126:$1E,156:$16` | 30, 80, 110 | **`[80,110]`** | 300/300 = 100.00%, 0 deviating |
  | `76:$16,106:$1E,136:$16` | 30, 60, 90 | **`[60,90]`** | 300/300 = 100.00%, 0 deviating |

  The 320-wide band **lands where the table puts it and moves when the table moves.**

- **AC-6 [class: eye-gated] Jay sees mode 3 run.** **PASS — Jay, live window, NORMAL SPEED, RGB,
  40 s at 100.00%.** *"i saw fine coarse fine coarse"* — which is exactly correct: the handler sets
  `$1E` (320, fine) at VBORD, then the table gives coarse at y30, fine at y60, coarse at y90. **Four
  bands.**
  ★★★★★ **AND THE EYE FOUND A BOUNDARY THE BYTE GATE MISSED.** AC-5's scanner reported only
  `[60,90]`; Jay's eye confirms the **y30** boundary is present. §4A.3: *a byte gate that passes
  where the eye disagrees is a finding about the GATE.* The band scanner's window starts at y=25 and
  needs rows to establish a run-length baseline — **now confirmed by the eye rather than suspected.**
  Separately eye-gated earlier in the task: the **flicker fix** (*"it was steady"*, both borders red)
  and the **stage 1 baseline** (*"yes that's what i see"*).

- **AC-7 [class: suite] The record carries the outcome, including the withdrawals.**
  **PASS.** `poc/s01_hres/NOTES.md` §8 gained the four withdrawn claims, what disproved each, and
  the lesson. Commits `e4f1713`, `c485455`, `2ed44ff`, `8e15b3d`, `61afeeb`, `dc9fa52`, `bc54a07`
  each carry their own withdrawal in the subject line.

- ★★★ **AC-8 [class: byte-comparable] The boundary result survives removal of the scaffold.**
  **FAIL AS ORIGINALLY REPORTED, PASS AS RE-MEASURED.** See §7.1. The original result was entangled
  with a border flip that inverted every row of every other frame; the re-measured result above was
  taken with the flip off the picture and no inversion.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

Suite, at HEAD `bc54a07`:
```
★ source integrity: clean (535 files swept, 3 BOM-tolerated)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
volume               expected requests  identical   mismat  guestfail
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
```

AC-4, one boundary following the table:
```
  line 70 (expect y~24) -> distinct patterns 1 MODE [] (300 of 300 = 100.00%)  |  frames deviating from the mode: 0 (0.00%)
  line 100 (expect y~54) -> distinct patterns 1 MODE [54] (300 of 300 = 100.00%)  |  frames deviating from the mode: 0 (0.00%)
  line 130 (expect y~84) -> distinct patterns 1 MODE [84] (300 of 300 = 100.00%)  |  frames deviating from the mode: 0 (0.00%)
```

AC-5, three entries:
```
  [76:0x16,126:0x1E,156:0x16]
     -> distinct patterns 1 MODE [80,110] (300 of 300 = 100.00%)  |  frames deviating from the mode: 0 (0.00%)
  [76:0x16,106:0x1E,136:0x16]
     -> distinct patterns 1 MODE [60,90] (300 of 300 = 100.00%)  |  frames deviating from the mode: 0 (0.00%)
```

AC-1/AC-2/AC-3, liveness and the source sweep:
```
  FIRQ OFF -> s01_fcount = 0 (guest frames 197)  |  s01_hwrite = 0 (hcount now 0)
  FIRQ ON  -> s01_fcount = 51283 (guest frames 197)  |  s01_hwrite = 196 (hcount now 20)

  bit 0x01 -> 0 interrupts / 197 frames = 0 per frame
  bit 0x02 -> 0 interrupts / 197 frames = 0 per frame
  bit 0x04 -> 0 interrupts / 197 frames = 0 per frame
  bit 0x08 -> 197 interrupts / 197 frames = 1 per frame
  bit 0x10 -> 51283 interrupts / 197 frames = 260.32 per frame
  bit 0x20 -> 12 interrupts / 197 frames = 0.06 per frame

  1 entries -> s01_hwrite = 196     2 entries -> s01_hwrite = 136     3 entries -> s01_hwrite = 76
```

The S-03 comparison that withdrew four claims (§7.2), at `0f37499`:
```
  4-colour   FillB 85 -> transitions 4 at y=[24,77,94,216] guest frames 51 steady across samples
  4-colour   FillB 15 -> transitions 4 at y=[24,77,94,216] guest frames 51 steady across samples
  16-col Big FillB 85 -> transitions 5 at y=[24,106,107,109,216] guest frames 11 steady across samples
  16-col Big FillB 15 -> transitions 5 at y=[24,106,107,109,216] guest frames 11 steady across samples
```

The raster validator's §2W red arms:
```
  HTab 133:1E    -> raster entry [133:1E] does not parse as line:value -- hex needs the 0x prefix
  HTab 133:0x22  -> raster value $22 sets LPF=1 -- that is a GEOMETRY change, not an HRES switch
  HTab 133:0x1D  -> raster value $1D has CRES=1, not 2 (16-colour)
```

**`hal_sync_check.py`: N/A — no `SHARED` file touched.**
**`reg_discipline.py`: N/A — no `src/engine/` file touched.** `poc/s01_hres/` is a standalone spike
with no HAL, no includes and no `src/` dependency.

**25.2 bundled-artifact grep:** N/A — this task ships no DECB artifact. `poc/s01_hres/s01.bin` is a
poked standalone binary, not a build output.

**25.3 operator-runtime-smoke:** **PASSED — Jay, `poke`, RGB, live window at NORMAL SPEED**, three
separate gates: the flicker fix (*"it was steady"*, both borders red), the stage 1 baseline (*"yes
that's what i see"*), and mode 3's four-band raster program (*"i saw fine coarse fine coarse"*).
★★★ **Recorded as `poke`, not `live-disk`**: the spike is poked into a DECB machine at its OK prompt
and never reaches a floppy, so **this gate does not gate delivery** (§4). Motion was under gate in
all three — real runs in a real window, not stills.

---

### 6 — Reactive deviations and route accounting

**§22.5 deviations from the spike spec:**

1. ★★★ **The border investigation was pursued and then dropped on Jay's instruction** — *"i dont
   completely understand… it always going to be black so chasing this might be wasted effort unless
   you have a valid reason."* No valid reason existed; the border is a refresh scaffold, not a
   deliverable. Before dropping it I confirmed the one thing that could have justified it: `-Render`
   gives byte-identical output to `-video none`, so `scr:pixels()` is sound where the project needs
   it.
2. **`-M3Own`, `-BSet`, `-BCol`, `-FullDump` and the raster validator were added** — not in the
   spike spec. Each exists to make a hypothesis falsifiable rather than arguable.
3. **A rollback was proposed and NOT performed.** Scoping it showed the workable state was already at
   HEAD, and a blanket revert would have discarded the flicker fix, the validator and the mojibake
   gate. Only `poc/s01_hres/` at `0f37499` was checked out, for comparison, and restored.

**ROUTE ACCOUNTING.** ★★★★★ **I proposed three routes this task and two of them I did not carry out
as described.**

- **Proposed:** "go back to the last arm Jay eye-confirmed, get mode 3's PICTURE right and eye-gated
  FIRST, then rebuild the raster program on top of it in verified steps."
  **Implemented:** the re-establishment of stages 2 and 1 (steps 1 and the diff), **and then the
  defect was found by reading source rather than by rebuilding in steps.** Steps 2 and 3 as described
  — incrementally reconstructing mode 3 from stage 1 — **were never executed.** The outcome was
  better and the route was not followed.
- **Proposed:** "price the 320-everywhere composite first, and only go back to the raster mechanism
  if the number doesn't fit." **NOT implemented.** Jay's requirement (a box inside the picture area)
  made the mechanism load-bearing regardless, so the pricing was deferred. **It is still not done**
  and is §8's first item.
- **Proposed:** the eye gate would show "a band of finer striping across the middle with coarser
  above and below." **Implemented, and the prediction was incomplete** — four bands, not three,
  because the handler's own VBORD write is a fourth region. Jay's report is what corrected it.

---

### 7 — Uncertainty flags

#### 7.1 ★★★★★ SIX FIGURES WITHDRAWN, AND WHAT DISPROVED EACH

| withdrawn | disproved by |
|---|---|
| `39,88,138 × 10800`, "three boundaries, 1 pattern, 100.00%" | the raster parser was `(%d+):(%d+)` — **decimal only** — so `88:1E` poked `$01`. A silently truncated value that still switched something, so the classifier still found a boundary. |
| `[43,93] 300 of 300` | measured while a hardcoded `eora #$3F` border flip inverted **every row of every other frame**. |
| "the FIRQ-placed boundary is 100% stable at every scanline" | same flip. Re-measured clean in AC-4; **the conclusion survived, the measurement did not.** |
| "the knife-edge sweep is 100% stable at every value" | same flip. **Not re-measured** — see 7.3. |
| "mode 3 renders nothing the guest does / every mode-3 measurement is void" | the `-FillB` discriminator does not respond at `0f37499` **either**. |
| "stage 2 has regressed since S-03" | stage 2's 16-colour transitions at `0f37499` are **identical to HEAD's**. |

#### 7.2 ★★★★ Three instruments were unsound, and one is still not trusted

1. **The raster parser** — decimal-only. Now demands an explicit whole value and validates CRES=2 and
   LPF=0, **shown red three ways** (§5).
2. **The border sampler** — keyed on region not row, took a second whole-frame `grab()` in the same
   notifier tick as the band measurement, and sampled through 250 settle frames: **495 of 550 samples
   were black at y=100–150, the active display every other instrument calls stable.** Corrected, and
   **its output is withdrawn entirely** because writing `$FF9A` to pure red changed it by not one
   byte.
3. **The full-height dump** — trustworthy for the active area and the bottom border; **not for
   `y0–23`.** It reads `y0–23` black while `y216–237` is red, and ★★★★ **Jay's hardware correction
   makes that a state the machine cannot produce**: *"the border color register changes both borders
   to the designated color."* His eye saw both red. **Tier 1 outranks the byte reading** (§2).

#### 7.3 Open, and not explained

- **The knife-edge comparison is not re-measured.** S-05's headline contrast — FIRQ placement stable
  where cycle-counting has an 8-cycle window — **has not been re-run since the fix.** The FIRQ side
  is now solid (AC-4); the comparison is not.
- **`y = line − 46`, not −45.** Measured and consistent; **the one-line offset is not explained.**
- **The band scanner misses a boundary at y30.** Jay's eye confirms it exists. Suspected scan-window
  start; **not fixed.**
- **`-FillB` does not move stage 2's picture, at HEAD or at `0f37499`.** Original behaviour, and
  **still unexplained.** It is why the discriminator was invalid, so the explanation is owed.
- **Cycles for a packed 160-wide visual row vs an unpacked 320-wide one.** Not measured (§3.5).

#### 7.4 Labelled as Clyde's arithmetic, per §8

§3.4's byte table and the "up to ~30% of total cycles" figure are **derived, not measured**. The
59.4% composite share is measured; the mapping from bytes saved to cycles saved is not, and §3.5's
packing caveat is the reason to doubt it.

---

### 8 — Follow-up candidates

1. ★★★★★ **Price the 160-wide visual plane** — cycles for a packed 160-wide composite row against an
   unpacked 320-wide one, in `src/harness/comp_probe.s`, which already has a clock-calibration mode.
   **This is the decision, not the raster mechanism.** §3.5 gives the memory case (another 13,440 B
   by `PRI_PACKED`'s mechanism) and the cheap-path evidence (2.7%), and neither is the number.
2. **Re-measure the knife-edge comparison** since the fix (§7.3). Without it S-05 has a working
   mechanism and no *comparison*.
3. **Fix the band scanner's window** so a boundary at y30 is reported (§7.3, confirmed by eye).
4. **Explain `y = line − 46`** and `-FillB`'s non-effect on stage 2 (§7.3).
5. **Design question for the Orchestrator, per §2D:** an HRES change is per-scanline, so a message box
   forces its whole rows to 320 and the picture on those rows must be doubled. **Proposed text only —
   not written to the design spec.**
6. **T-P0-158 Part B** — the priority row buffer; buffer size 129 vs 81 bytes remains unanswered.
7. **T-P0-158 Part C** — the two `gfx.s` comment edits (VOFFSET's 256-byte granularity, `$FF9F` in
   the fetch address). Deferred five reports; needs all three repos in hand.
8. **`gates.manifest`** to record the mojibake narrowing; re-run the `VM_FAULT` arms and close their
   scope hole; `MAP_PRI_BANDS` (`memmap.inc` is a §6 stop trigger).

---

### 9 — User interaction during task

Itemised. **Jay corrected the executor four times and each correction changed the work.**

1. *"the flashing didn't start until you started the new firq process so i'd look there."* — Correct
   as to location (mode 3 *is* the FIRQ arm) and the defect was there, in my scaffold.
2. *"i think the border color issue your seeing is by design… the border color register changes both
   borders."* — ★★★★ Hardware fact that made the dump's reading impossible, not merely unreliable.
3. *"i dont completely understand… it always going to be black so chasing this might be wasted effort
   unless you have a valid reason."* — Border work dropped; no valid reason existed.
4. *"why would you use an interrupt without knowing what it was? tht's bad engineering. you could
   just check the gime refernces you have."* — ★★★★★ Correct, and the specific failure was §2S:
   I asserted `docs/ground-truth/` was empty having looked only in `coco_agi`, while the reference sits
   in both siblings. §3.3 is the result.
5. *"i thought s2 was also eye-gated or is that not usable in your new plan"* — ★★★★★ **This is what
   broke the deadlock.** Checking stage 2 against `0f37499` withdrew four claims and converted the
   problem from "rebuild a subsystem" to "diff the working path against the broken one", which found
   the defect in one reading.
6. *"i want 160pixel on top for the picture, but 320pixel in the text area for text… what we need it
   the ability to print 40 column text in a message box displayed in the upper picture area"* — the
   requirement, which made the mechanism load-bearing.
7. *"i saw fine coarse fine coarse, but not coarse and fine on the same lines which is what i would
   expect"* — the eye gate, **and §3.4's design consequence is his.**
8. *"yes that's what i see"* (stage 1 baseline), *"it was steady"* / *"the top and bottom border are
   red"* (flicker fix), *"lets rollback to something workable and builf from there"*, *"report for the
   orchestrator"*.

---

### 10 — Candidate(s) captured this task

Two fresh single-instance `live` rows in `seeds/AGI/live/`:

- `2026-09-27-a-control-whose-parameter-arrives-but-whose-code-ignores-it.md` — **reading a poked
  parameter back proves it ARRIVED, not that any code READS it.** `s01_bxor` was poked, read back as
  `$00`, and never read by the guest, because the flip was `eora #$3F`. This is the row owed across
  six reports; captured with this session's instance, which is its clearest.
- `2026-09-27-a-null-result-needs-a-known-good-positive-before-it-indicts.md` — **the mirror of
  §2W.** A green check needs a red arm; a **null** needs a known-good **positive**, because an
  unexercised null *accuses* the subject and so propagates further. Four claims came from one
  discriminator never shown to respond.

---

### 11 — Commit

`bc54a07` (pushed to origin/wip before this report). Task commits, each carrying its own withdrawal:
`e4f1713`, `c485455`, `2ed44ff`, `8e15b3d`, `61afeeb`, `dc9fa52`, `bc54a07`.
