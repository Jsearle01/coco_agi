## Form B Report — P3.14 — the stack blast, retested
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-28 (dispatch T-P0-022 receipt; HEAD at receipt `b7bd9aa`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  b7bd9aa6830a73a867e1469b6d705e946e9cbdf7  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
lwasm from lwtools 4.24        MAME 0.281 (mame0281)
[hal-sync] coco_agi OK / POP3_port OK / karateka_coco3 OK   (11 files compared, all three)
[reg-discipline] scope: src/engine   0 register access(es).
45-picture gated set: reproducible; AC-2 runs it.
span-length distribution [T-P0-014]:
    min 1  p25 4  median 9  p75 23  p90 56  p99 160  max 160   mean 21.3
```

★★ **L-53, and it mattered again: `pic_fill.s`'s span loop does NOT write runs.** It writes one
pixel per iteration, interleaved with the up and down tests, because transition detection
happens per pixel. §2's *"a scanline fill writes uniform runs"* is true of the **shape** and not
of our **loop order** — so the blast needed a restructure, not a drop-in. §3.1.

★ **§2T — POP `430a91c` and Karateka `78c8c27` unchanged from P3.13 §0.**

---

### 1 — Summary

★★★ **AD-45 IS CLOSED. THE STACK BLAST IS NOT WORTH IT, AND HERE IS THE NUMBER.**

| variant | min | **median** | max | >3 s | vs P3.13 |
|---|---|---|---|---|---|
| P3.13 per-pixel write | 2.168 | **2.973** | 4.599 | 20 | baseline |
| **P3.14 deferred write** | 1.998 | **2.746** | 4.357 | 5 | **7.6% faster** |
| P3.14 deferred **+ blast** | 1.922 | **2.749** | 4.221 | 5 | 7.5% faster |

> ★★★ **THE BLAST'S OWN CONTRIBUTION: −0.1%. It was 0.004 s SLOWER, not faster.**
> ★★ **The 7.6% came from DEFERRING the write, not from `pshs`.**

★★★ **The arithmetic predicted ~4% and the measurement said nothing.** Per byte the blast really
is cheaper — **2.9 cycles against 11** — but it is paid **per span**: mask, save `S`, compute the
end pointer, load five registers, restore `S`, then a tail loop for run mod 8. ★★ **With a
median span of 9 bytes that setup amortises over about ONE 8-byte group and cancels the gain.
The blast wins on long runs and ours are short** — L-52, and exactly the check §6 asked for.

★★ **Shipped together, the two changes would have recorded a 7.6% win for a technique worth
nothing.** ★ **Measuring them separately is the only reason AD-45 gets a real answer after three
deferrals.**

**AC-6 — where the 2.746 s now goes**, which the dispatch says it wanted regardless:

```
fills            2.233 s   81.3%
everything else  0.512 s   18.7%     lines, opcode dispatch, put_pixel, clears
```

★ **Gate 45/45 byte-identical; every counter unchanged; captures byte-identical to P3.3's.
Cumulatively 75.3% below P3.3's 11.102 s.**

### 2 — Files modified
- **`src/harness/pic_fill.s`** — the span's writes are deferred to its end and flushed once;
  the blast was built, gated, measured and **removed** (§3.4).

**No `src/engine/**` change; `reg_discipline` stays at 0.** No game data, resources, renderings
or screenshots committed (§2P).

### 3 — Reasoning

**3.1 ★★★ The blast needed a restructure, and the cheap restructure was not the obvious one.**
The dispatch assumes a run to blast. Our loop had none: it tests the current pixel, writes it,
tests above, tests below, advances. ★★ **The obvious fix — two passes: find the extent, blast
it, re-walk for transitions — costs an extra pointer walk per pixel and gives most of the
saving back.**

★★★ **The single-pass version works because within one span, NO TEST READS A PIXEL THAT SPAN
WRITES.** The current-row test reads **ahead** of the write position; the up and down tests read
**other rows**. So the writes have no reader until the span ends, and deferring them changes
nothing any test can observe. ★ **That is the whole justification for AC-2 and AC-3 holding.**

**3.2 ★★★ Why deferring is worth 7.6% when the store is only 4 cycles.**
The per-pixel path was not a store:

```
lda ff_wval (5) / sta ,x (4) / lda fc_case (5) / bne (3) / lda ff_sec (5) / beq (3)  = 25
```

★★ **Sixteen of those 25 cycles were re-deciding, per pixel, two facts fixed for the entire
fill** — which plane is primary, and whether a second plane needs writing. The flush decides
them **once per span**. ★ **The store itself was never the expensive part, which is exactly why
the blast — an optimisation of the store — had nothing to win.**

**3.3 ★★ AC-5 — the crossover, and what falls under it.**

```
per-pixel write (P3.13)   lda 5 + sta 4 + lda 5 + bne 3 + lda 5 + beq 3   = 25 cy/byte
deferred sta ,x+ loop     sta ,x+ 6 + decb 2 + bne 3                      = 11 cy/byte
pshs a,b,x,y,u blast      (pshs 13 + dec 7 + bne 3) / 8 bytes             = 2.9 cy/byte
```

★★★ **The crossover is 8 bytes BY CONSTRUCTION** — the blast only runs on whole 8-byte groups
and the tail is handled at 11 cycles a byte. ★ Against the distribution (**median 9**, p25 4),
**about half of all spans are at or below one group**, and those are precisely where the
per-span setup has nothing to amortise against. ★★ **The long spans do blast fully and hold most
of the bytes — and it still came to nothing, which says the setup cost is larger than the
per-byte gain over a realistic mix.** [L-26: the setup cost was not measured in isolation; the
end-to-end difference is the measurement.]

**3.4 ★★ The blast is REMOVED, not parked behind a define.**
It borrowed `S`. ★★★ **Dead code that borrows `S` is a liability for whoever next adds a `bsr`
near it** — POP `char_draw.s:512` lost three dispatches to *"two wrong flame bytes that came
from a `bsr` executed while S pointed into the framebuffer"*. ★ The finding is kept in the
file's header where the next person will read it; the mechanism is gone.

**3.5 ★★★ THE MEASURED BUILD WAS NOT THE SHIPPED BUILD, AND I RE-RAN RATHER THAN CARRYING THE
NUMBER ACROSS.** Removing the blast shifted the layout by 5 bytes — its variables were declared
unconditionally rather than inside the `ifdef`, so they were assembled even when it was off.
★★ **A five-byte shift should not change timing, and "should not" is not a measurement.** The
shipped build was re-gated and re-timed and lands on the same **2.746 s**. ★ **It is now a
measurement of the artifact that exists.**

**3.6 §2S / §2.2.** POP `430a91c`, Karateka `78c8c27`, both `wip`, at those refs. MC6809 cycle
counts read from POP3_port's `docs/ground-truth/`; `coco_agi`'s is empty —
**orchestrator-unverifiable**.

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] PASS.** `reg_discipline` 0; `hal_sync_check` OK ×3; §2T cited.
- **AC-2 [byte-comparable] ★★★ PASS — 45/45 byte-identical.** ★ **Both variants gated
  separately** — deferred alone and deferred+blast — **and the shipped build was gated again
  after the removal** (§3.5).
- **AC-3 [state-comparable] ★★★ PASS — unchanged to the unit.** Boundary tests **3,666,862**,
  pixels **1,188,430**, seed peak **74 B / 37 entries**. ★★ **CNT_PIX is now added once per span
  as the run length rather than incremented per pixel; the total is identical, which is what
  AC-3 is for** [L-37].
- **AC-4 [state-comparable] ★★★ PASS — the number is in §1.** **Blast NOT adopted; its measured
  effect is −0.1%.** Deferred write adopted at **7.6%**. **n=45, one run per variant**; emulated
  time is deterministic to 9 dp [T-P0-012] and the clock guard reports an identical interval
  across all 45 [L-30, L-33].
- **AC-5 [state-comparable] ★★ PASS.** §3.3. ★ **Confidence: the 8-byte crossover is structural
  and certain; the claim that setup dominates is inferred from the end-to-end null result rather
  than measured directly** [L-26].
- **AC-6 [state-comparable] ★★★ PASS — fills 81.3%, everything else 18.7%** (by difference,
  `-DPIC_NOFILL`). ★ Per-test **48/62/76 cycles**, spread 1.59×; per-pixel **143/181/440**,
  spread 3.1×. **Cost still tracks boundary tests.**
- **AC-7 [byte-comparable] ★★★ PASS.** `-DPIC_FAULT`: 44 PASS, 1 FAIL, named **`Kingquest3-030
  visual`** — exactly the injected picture.
- **AC-8 [state-comparable] ★ N/A — `S` IS NOT BORROWED IN THE SHIPPED BUILD.** ★★ For the record
  of the variant that was measured: `CC` was pushed on the real stack **before** the borrow and
  pulled **after** `S` was restored, interrupts were masked with `orcc #$50` across it, **no
  subroutine call occurred inside the borrow**, and the tail was written with `sta ,x+` and never
  touched `S`.
- **AC-9 [eye-gated] ★★★ CAPTURED AND VERIFIED — pending Jay's eye.** Three rooms in
  `C:\karateka-capture\agi_captures\`, and **all three are byte-identical to P3.3's**:
  ```
  agi-p3.14-Kingquest1-080-RGB-4x3.png   88AFDEBBD487AC02   IDENTICAL to P3.3
  agi-p3.14-Kingquest2-094-RGB-4x3.png   2ED9A6DE8708327E   IDENTICAL
  agi-p3.14-Kingquest3-074-RGB-4x3.png   F17920528DDC8279   IDENTICAL
  ```
  ★★ **This is the DISPLAY path, not the framebuffer read-back** [idiom 19j] — through
  `HAL_gfx_swap`, the GIME's scanner and MAME's renderer. **Launch path: sweep + `PIC_SNAP`,
  RGB asserted from Lua, `-snapview auto -snapsize 640x480 -keepaspect`, IHDR read back at
  1.333.**
- **AC-10 [suite] PASS.** Two candidates; §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-4: the three points ===
variant                                min   median     max  >3s  vs P3.13
P3.13  per-pixel write   [cited]     2.168    2.973   4.599   20  baseline
P3.14  deferred, sta ,x+             1.998    2.746   4.357    5    7.6% faster
P3.14  deferred + BLAST              1.922    2.749   4.221    5    7.5% faster

★★★ THE STACK BLAST'S OWN CONTRIBUTION (AD-45, closed)
    deferred write alone : 2.746 s   (7.6% below P3.13)
    deferred + blast     : 2.749 s   (7.5% below P3.13)
    ★ THE BLAST ITSELF   : 2.746 -> 2.749 = -0.1%   (-0.004 s)
```

```
=== AC-2, the SHIPPED build (re-run after the blast removal shifted 5 bytes) ===
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
picgate exit=0

=== AC-7 ===
★ FAILING PICTURES (named, not counted):  Kingquest3-030 visual
--expect-fail exit=0

=== AC-3 ===
set totals: 3666862 fill_check calls against 1188430 pixels written (3.1x)
measured here: max 74 bytes = 37 entries, on Kingquest1-009
   ★ IDENTICAL to T-P0-014 and P3.13

=== AC-6: the decomposition of 2.746 s (4.91 M cycles) ===
render time   min 1.998 s   median 2.746 s   max 4.357 s
FILL vs LINE/PEN split (by difference, -DPIC_NOFILL):
  ★ fill is 81.9% of total render time across the set
    fills            2.233 s   81.3%
    everything else  0.512 s   18.7%
per FILL_CHECK    : min 48  median 62  max 76   spread 1.59x
per PIXEL WRITTEN : min 143 median 181 max 440  spread 3.1x
```

```
=== AC-9: the display path, byte-identical to P3.3 ===
agi-p3.14-Kingquest1-080-RGB-4x3.png  640x480  ratio 1.333   88AFDEBBD487AC02  IDENTICAL
agi-p3.14-Kingquest2-094-RGB-4x3.png  640x480  ratio 1.333   2ED9A6DE8708327E  IDENTICAL
agi-p3.14-Kingquest3-074-RGB-4x3.png  640x480  ratio 1.333   F17920528DDC8279  IDENTICAL
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle; the probe is a harness binary.

25.3 operator-runtime-smoke: **pending Jay** (AC-9). ★ Captures taken and verified identical;
launch path recorded above.

### 6 — Reactive deviations and what it means

★★★ **AC-6's decomposition is the durable artifact, and it points away from the fill.**

```
fills            81.3%     of which the boundary test is the flat, dominant unit
everything else  18.7%     lines, opcode dispatch, put_pixel, clears
```

★★ **The fill is still four fifths of the render — but the test count (3.09/pixel) is fixed by
the algorithm and the per-test cost is now 62 cycles.** ★★★ **Between P3.13 and P3.14 the fill
went 2.973 → 2.746 s and the remaining 7.6% came from work that was never the fill's inner
question at all.** ★ **I do not see another 7% in it without changing which pixels are tested.**

★★ **And the Orchestrator's own M-32 doubt looks right:** compositing runs **every frame**, has
never been measured on hardware, and a render that now costs 2.746 s **once per room** is no
longer obviously the constraint. ★ **AC-6 does not settle that — it cannot, because compositing
is not in this measurement at all — but it removes the reason to keep looking here.**

**Triggers.**
- ★★ **Trigger 3 partially applies and I am flagging it as the dispatch asks:** the remaining
  time **is** still in the fill (81.3%), so it does not fire — ★ **but the fill's remaining cost
  is structural, and that is the same conclusion by a different route.**
- **Trigger 1 did not fire** — gate held, counters unchanged. **Trigger 2 did not fire** — the
  blast needed ~90 lines, but it is removed, so the bound is moot. **Trigger 4 did not fire** —
  2.746 s, above ~2 s.

**ROUTE ACCOUNTING.** ★ **What I did NOT do:** any further fill optimisation beyond the retest,
per §11. ★★ **What I did that was not asked:** measured the deferred write **separately** from
the blast. **That was not in the dispatch and it is the only reason AD-45 has an answer rather
than a 7.6% misattribution.**

### 7 — Uncertainty flags
- ★★ **AC-5's "setup dominates" is inferred from a null end-to-end result, not measured in
  isolation** (§3.3). ★ The 8-byte crossover is structural and certain.
- ★★ **The blast was measured in ONE implementation.** A different register allocation or a
  per-fill rather than per-span setup might do better; **I am reporting that this one is worth
  nothing, not that no `pshs` scheme could be.**
- ★ **One run of 45 per variant** [L-33]; emulated time is deterministic, so this is
  reproducibility rather than hardware variance.
- ★ **AC-6's split is by difference (`-DPIC_NOFILL`)**, which attributes everything the fill does
  not do to "everything else" — including any interaction between them.
- ★ **KQ1/2/3 PC resources, 45 pictures** [L-24]. **AC-9 is captured but unobserved by Jay.**

### 8 — Follow-up candidates
1. ★★★ **Measure compositing on hardware** (M-32). ★★ **It runs every frame; the render runs
   once per room and is now 2.746 s. The ranking that put the renderer first predates both.**
2. ★★ **Re-baseline design §6.2/§6.3** — written against 7.473 s, now twice out of date.
3. ★ **`put_pixel` and the line renderer** are 18.7% and have not been decomposed since P3.5.
4. ★ **AD-45 should be marked CLOSED with the number**, not deferred again.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
Two, to `seeds/AGI/live/` (§2C — new rows):
1. ★★★ **`measure-the-carrier-separately-from-the-technique`** — a technique was adopted inside
   a restructure that was needed to make it possible. Together they were 7.6% faster; **the
   technique itself was −0.1%.** Measuring the carrier alone is what turned a plausible
   attribution into a closed question after three deferrals.
2. ★★ **`a-conditional-optimisation-must-be-conditional-all-the-way-down`** — the blast sat
   behind a define, but its VARIABLES were declared unconditionally, so removing it shifted the
   layout and the measured binary was not the shipped one. **The measurement had to be redone
   for a change that was supposed to be a no-op.**

### 11 — Commit
`d7047be` — the deferred write; the blast built, measured and removed.
Pool: `eb06eca` — two rows on top of `d142906`.
★ Pushed to `origin/wip` before this report.
★★ **No `src/engine/**` change: `reg_discipline` 0.**

