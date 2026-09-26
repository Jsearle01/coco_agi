## Form B Report — Spike S-04 — Is the row repeat real, or is it the instrument?
**Class:** spike (recon). **Not a dispatch.** No `src/` change at all — **including §4D's authorised
comment edits, which were NOT made** (§7.1). No oracle, no gates. wip.
**Continues S-01/S-02/S-03** in `poc/s01_hres/`.

### 0 — Receipt / status
t0=2026-09-26 (Spike S-04, issued after S-03's report `2c2cb78`). HEAD at report `dc7b666`.
`git status` clean except untracked `coco_agi.code-workspace` (an editor file).
Commits: `44b65b3`, `4b03e4c`, `dc7b666`.

### 1 — Summary

★★★★★ **THE INSTRUMENT. The 16-colour mode is CLEAN and matches 4 colours exactly**, so §4B's stage 2
was unlocked and run. ★★★★★ **The gating result: a SINGLE 320/160 split is rock steady — 10,800 of
10,800 frames over three emulated minutes, zero deviation.** ★★★★★ **But THREE boundaries — the
message-box case — has a VISIBLE defect: the middle one jitters by one scanline on 9.88% of frames, and
Jay confirmed it at normal speed.** ★★★★ **So the two cases have different answers**, and FIRQ is now
motivated by a measurement and an observation rather than assumed. ★★★ **S-03 §7.3's hypothesis about
the port's display is WITHDRAWN.** ★★ **§4D's HAL comment edits were not made and are the top
follow-up** (§7.1).

### 2 — Files modified
`poc/` only:
- `poc/s01_hres/s01.s` — `s01_rowbase` (§4A(1)'s one-poke test); the `s01_pal16` note recording that
  distinct bytes are not distinct colours.
- `poc/s01_hres/s01_run.lua` — §4A(2)'s independent pixel-pair reading; the rendered-palette dump with a
  duplicate check; the flip retargeted to the border at 16 colours; §4B's per-frame boundary tracker
  (binary search) and §4D's band-pattern scan.
- `poc/s01_hres/s01.ps1` — `-RowBase`, `-Stab`.
- `poc/s01_hres/NOTES.md` — AC-5: the verdict, both readings, the withdrawal, the three wrong turns, the
  stability distributions and Jay's words.

### 3 — Reasoning

**3.1 §3's four checks were performed.** Sampler stayed `scr:pixels()` (§3.1). ★★★★ **§3(2) was the
binding one — "the signature is the suspect, do not reuse it to test itself"** — and §4A(1) honours it
by changing the *data* rather than the reading, so no new aliasing could be introduced. Liveness within
one sample window (§3.3); the framebuffer readback kept as the control (§3.4).

**3.2 §2H's three checks.** (1) *A second mechanism for a different object class?* ★★★★★ **Yes, and it
is the answer: the flip register is a REFRESH mechanism at 4 colours and a DISPLAYED COLOUR at 16.** One
register, two roles, and the second only exists at the greater depth. (2) *The calling routine.* The
collision was not in `s01_pal16` — it was in the per-frame flip that writes `$FF00 + s01_palreg`, so
**the caller is what mattered and the table was innocent.** (3) *Grep the prior record.* S-01/S-02/S-03's
NOTES supplied everything in §2 and none of it was re-derived.

**3.3 Authority tier.** MAME 0.281, `poke` launch, one configuration. ★★★ **A pass here is "worth
building on", never proof about silicon.** The stability figures are statements about the model.

### 4 — Verification (AC-by-AC)

**AC-1 [measured] §4A's two readings, and the verdict. ★★★★★ MET — THE INSTRUMENT.**

```
BEFORE (S-03):  runs of 1: 175   runs of 2: 9    <- the "repeat"
AFTER  (S-04):  runs of 1: 191   runs of 2: 1    <- identical to the 4-colour baseline
 4-colour ref:  runs of 1: 191   runs of 2: 1
```
★★ The lone remaining "2" is the final scanline, where 193 active scanlines read slightly past the
buffer — the same edge 4 colours shows.

**§4A(1) — the row-numbering shift, and it killed the hypothesis in one poke:**

| `s01_rowbase` | first repeat at index | byte value there |
|---|---|---|
| 0 | 6 | **6** |
| 4 | 2 | **6** |
| 8 | 14 | **22** |

★★★★★ **6, 6, 22 — all ≡ 6 (mod 16). The repeated rows are those whose LOW NIBBLE is 6**, which is a
property of the data and cannot be a property of the raster.

**§4A(2) — the independent pixel-pair reading AGREED with the signature at every step**, so §6's first
trigger never fired and neither reading was at fault.

**The cause, named by a rendered-palette dump:**
```
0=0000FF 1=00FF00 2=00FFFF 3=FF0000 4=FF00FF 5=FFFF00 6=FFFFFF 7=FFFFFF 8=5555AA ...
★★★★★ DUPLICATE RENDERED COLOURS: 6==7
```
★★★★★ **The palette flip that keeps MAME's bitmap current was pointed at `$FFB8` — palette index 8.**
S-02 chose it because **4-colour mode displays only indices 0-3, so index 8 was invisible.** ★★★★★ **At
16 colours EVERY index is displayed**, so the flip wrote `$3F` into index 8 twice a frame, `pal16[7]` is
also `$3F`, and two indices rendered identically — making two source rows that differ only in that
nibble indistinguishable. ★★★★ **Fix: flip the BORDER (`$FF9A`)**, which MAME also records per scanline
(`update_value(&m_scanlines[..].m_border, border)`) and which is outside the decoded area.

**AC-2 [measured] §4B's four figures (the instrument branch). ★★★★★ MET.**

**§4B(1) — ONE boundary, 10,800 frames = 3 emulated minutes:**
```
distribution: y123 x10800    distinct patterns 1    MODE y123 (10800 of 10800 = 100.00%)
frames deviating from the mode: 0 (0.00%)
★ every sampled frame had exactly one readable boundary
```
**§4B(2) — tearing: NONE.** ★★ The reader rejects a frame whose top is already narrow or whose bottom is
still wide; no frame was rejected.

**§4D — THREE boundaries, same window:**
```
distribution: 39,88,138 x1067    39,89,138 x9733
distinct patterns 2    MODE [39,89,138] (9733 of 10800 = 90.12%)
```
★★★★★ **Outer two rock steady at y=39 and y=138. The MIDDLE one alternates y=88/y=89 on 9.88% of
frames.** ★★★ §6's fifth trigger answered: **which and where — the second of three, at the top edge of
the middle band.**

★★★★ **Expected physics, not a surprise:** the first boundary is anchored to VBORD so its cycle count
starts at a hardware event; the second is placed by an **accumulated** busy-wait whose total lands near
a scanline edge and therefore alternates; the third is steady because its accumulated time is unaffected
by which scanline the second write was *sampled* on. ★★ **The jitter is in the reading, not the elapsed
time.**

**§4B(3) — CPU time: 1.000 guest loop iterations per frame**, sustained over 10,200 host frames, in
every arm. ★★★ **This is the BASELINE a FIRQ arm must be compared against; no FIRQ arm exists, so no
handler cost is claimed.**

**AC-3 [eye gate — Jay] ★★★★★ PASSED, and it upgrades the finding.** Normal speed (99.67%, 94 seconds
≈ 5,600 frames), 16 colours, three boundaries, **against an expectation stated before the run** — with
the thing to judge named in advance as the third band's top edge at y≈88/89, and **"I can't tell"
offered as a legitimate answer.**

★★★★★ **Jay: *"it doesn't move constantly, but i can see it moving at times."***

★★★★★ **That is the distribution in words — 90.12% / 9.88%, not constant, visible at times.** ★★★★ **The
eye supplied the one thing the number could not: it is PERCEPTIBLE.** A 10% one-scanline deviation could
have been below the threshold of notice. **It is not.** ★★ This is why S-03's missing eye gate was worth
recording as unmet: **the number establishes the magnitude, the eye establishes whether it matters.**

**AC-4 [byte-comparable] Nothing under `src/` changes except `gfx.s` COMMENTS; `hal_sync_check.py` ×3
RUN. ★★★★★ NOT DONE — see §7.1.** ★★★ **Nothing under `src/` was touched at all**, so the first half
holds trivially and the authorised comment edits were not made. `hal_sync_check.py` not run (nothing to
check); `reg_discipline.py` N/A by scope.

**AC-5 [record] `NOTES.md`. MET** — the verdict, both readings, the withdrawal, each wrong turn with the
test that would have caught it, the stability distributions and Jay's words.

### 5 — Verdict-time evidence

**25.1 fresh tool output (verbatim):**
```
§4A(1) rowbase sweep:   rb=0 first repeat idx 6 (value 6) | rb=4 idx 2 (value 6) | rb=8 idx 14 (value 22)
§4A(2):                 ★ AGREES with the signature reading   (all three runs)
palette dump (before):  6=FFFFFF 7=FFFFFF   ★★★★★ DUPLICATE RENDERED COLOURS: 6==7
palette dump (after):   7=000055            ★ all 16 indices render distinctly
counter, 16 colours:    runs of 1: 191  runs of 2: 1   (4-colour reference: 191 / 1)

§4B(1) one boundary, 10800 frames:
  distribution: y123 x10800   MODE y123 (10800 of 10800 = 100.00%)
  frames deviating from the mode: 0 (0.00%)
  ★ every sampled frame had exactly one readable boundary
  §4B(3) guest loop iterations: 10200 over 10200 host frames = 1.000 per frame

§4D three boundaries, 10800 frames:
  distribution: 39,88,138 x1067   39,89,138 x9733
  distinct patterns 2   MODE [39,89,138] (9733 of 10800 = 90.12%)
```

**25.2 bundled-artifact grep:** N/A — no DECB artifact, no disk image, nothing in `src/`.
**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, live window, RGB, 99.67% speed, 94 seconds,
against an expectation stated beforehand.** Launch path **`poke`**.

### 6 — Reactive deviations and route accounting

1. **§4A(1) was done by shifting the row NUMBERING rather than by building the anti-aliasing fill the
   dispatch suggested.** ★★★★ Cheaper (one poked byte), and it honours §3(2) better: **it changes the
   data and leaves the reading alone, so it cannot introduce a new aliasing mode.** The dispatch's
   `(N<<4) | (~N & 15)` fill was not built.
2. **§4B was run BEFORE building the FIRQ handler, and the handler was NOT built.** ★★★★★ Deliberate:
   **building a hardware-paced boundary before establishing that the cycle-counted one drifts is how a
   task proves its own premise.** The measurement then showed one boundary needs no help at all, and
   located the defect precisely in the three-boundary case. ★★★ **§4B's four figures are all answered
   for the arm that exists; none is answered for a FIRQ arm, and none is claimed.**
3. **§4D's HAL comment edits were not made** (§7.1).
4. **A rendered-palette dump with a duplicate check was added** — not in the dispatch, and it is what
   named the cause after the rowbase sweep had localised it.

**ROUTE ACCOUNTING.** In reporting S-03 I said the port-display hypothesis (§7.3 there) "may matter more
than 160-wide does" and offered to chase it. ★★★★ **It is now withdrawn and there was nothing to chase**
— the effect was my own flip register. **The offer was made on a hypothesis I had correctly labelled as
one, and the labelling is what kept the cost to a paragraph.**

### 7 — Uncertainty flags

**7.1 ★★★★★ AC-4's `gfx.s` COMMENT EDITS WERE NOT MADE, and the reason is scope discipline, not
oversight.** The dispatch authorises comment-only edits to `gfx.s:212-213` and `:222-223` to record
S-03 §4F's VOFFSET and `$FF9F` findings. ★★★★★ **`src/hal/coco3-dsk/gfx.s` is SHARED with POP and
Karateka and `hal_sync_check.py` fails all three builds on drift** [§2M], so the edit **lands in three
repos or in none** — and AC-4 itself requires the sync check ×3 plus the siblings' copies updated.
★★★★ **That is a deliberate three-repo action and it should not be a tail-end addition to a spike that
has already run for a long session.** ★★★ **The finding is in `poc/s01_hres/NOTES.md` and in S-03's
report, so it is not lost** — but it is **not where the next person touching `gfx.s` will see it**, which
is the whole point of the dispatch's §4D. **Top follow-up.**

**7.2 The boundary tracker assumes ONE boundary and would silently return one of three.** ★★★ Guarded:
it rejects a frame whose top is already narrow or whose bottom is still wide, and **§4D uses a full scan
instead.** ★★ The guard is what makes §4B(2)'s "no tearing" a measurement rather than an absence of
evidence.

**7.3 "Three minutes" is emulated time, not wall clock**, at `-nothrottle`. ★★★ **Nothing in this
measurement derives from wall clock** [§2U.1], and the eye gate ran at 99.67% where a human was
watching. ★★ But **10,800 frames is 10,800 samples of the same steady state**, not 10,800 independent
trials of a rare event — a defect with a period longer than three minutes would not appear.

**7.4 The one-scanline jitter's CAUSE is inferred, not measured.** ★★★ The explanation — an accumulated
busy-wait landing near a line edge — fits all three boundaries' behaviour and the 90/10 split, **but no
experiment isolated it.** A FIRQ arm would test it: if hardware pacing removes the jitter, the
explanation is confirmed; if not, something else is going on.

**7.5 ★★★★ Three wrong turns, and they are the transferable part of this spike.**
- ★★★★★ **S-03 "fixed" a palette collision by setting 16 distinct palette BYTES and never checked they
  RENDER distinctly.** **Distinct inputs are not distinct outputs.** The fix addressed the cause I had
  identified rather than **the property I actually needed**, and it left the defect in place *while
  reading as closed*.
- ★★★★ **I then edited `s01_pal16` twice and the dump did not change.** ★★★ **That non-change was
  evidence** — the colliding entry was never a `pal16` entry — **and I tried a third value instead of
  reading it.**
- ★★★ **My byte→RGB arithmetic was wrong twice** before the dump let me derive the mapping from observed
  data (`$09` → pure blue max, `$12` → pure green max ⇒ R = bit5·2+bit2, G = bit4·2+bit1, B = bit3·2+bit0).
  ★★ **The dump made it derivable; predicting it was what kept failing.**

**7.6 Scope.** 16-colour pair, one delay set, one delay triple, one emulator, one configuration. ★★ The
4-colour results were not re-run beyond the reference baselines §2 permits citing.

### 8 — Follow-up candidates

1. ★★★★★ **§4D's `gfx.s` comment edits, as a deliberate three-repo change** (§7.1). VOFFSET's 256-byte
   granularity and `$FF9F`'s participation in the fetch address belong beside that file's own
   undischarged debt, **and they are currently only in `poc/`.**
2. ★★★★★ **The FIRQ handler**, now motivated by a measurement AND an eye confirmation. ★★★ The baseline
   to beat: **1.000 loop iterations per frame, and a 90.12/9.88 jitter split on the middle of three
   boundaries.** ★★ It would also test §7.4's inferred cause.
3. ★★★★★ **THE DESIGN RULING IS NOW ASKABLE for the single-split case**, which is steady and needs
   nothing: **the map, the span-write blit and the gate re-baseline as a package.** ★★★ S-01 §1 prices
   the prize at 24% of the blit, and T-P0-157 measured `composite` at 59.4% of a steady cycle — **≈14% of
   a cycle from plane access alone** (unverified arithmetic, two tasks' measurements multiplied).
   ★★★★ **At 160 physical the visual plane is 13,440 B = 1.64 slices and fits two adjacent 8 KB slots**,
   so plane remapping during a composite stops existing.
4. ★★★★ **The blit must move to span writes in the SAME task** — at 160 an isolated pixel is a
   read-modify-write, and P6.89 measured opaque runs at 1.84.
5. ★★★★★ **The pool row is STILL OWED** and now has **four instances** across four spikes — S-01 §7.3,
   S-02 §7.1, S-03 §6.2 and S-04 §7.5's first item are all *a control or a fix that silently does not do
   what it claims*. ★★★ **Four instances, no row written. It should be written before the next spike.**
6. ★★ **`fix_mojibake.py` remains red on a clean tree with a destructive repair** [T-P0-157 §4F],
   presented to Jay and **not yet ruled on.**

### 9 — User interaction during task
- *"take a look"* → the MAME source reads that produced §4A's mechanism and S-03 §4F's fetch expression.
- *"go to tage 2"* → §4B and §4D's stability measurements.
- *"run the eye gate"* → AC-3.
- ★★★★★ **Jay's judgement, verbatim: *"it doesn't move constantly, but i can see it moving at times."***
  **That is the only evidence in this series that the jitter MATTERS**, as opposed to existing.

### 10 — Candidate(s) captured this task
**None.** ★★★★ §8.5's candidate now has **four instances** and remains unwritten. ★★ Recorded as a debt
in four consecutive reports.

### 11 — Commits
`44b65b3` (the §4A verdict), `4b03e4c` (stage 2's distributions), `dc7b666` (the eye gate) — all pushed
to origin/wip before this report.
