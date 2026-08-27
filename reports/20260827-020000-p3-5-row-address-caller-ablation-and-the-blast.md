## Form B Report — P3.5 — hoist the row address; ablate the caller; answer the blast
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-27 (dispatch T-P0-014 receipt; HEAD at receipt `90106e3`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  90106e3da181b065fe950e19b5f4ae7934310e5b  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
                      (harness/smoke/last-run.log — the same pre-existing file since T-P0-011)
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] coco_agi       OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
[hal-sync] POP3_port      OK -- aligned with karateka_coco3, coco_agi (11 files compared)
[hal-sync] karateka_coco3 OK -- aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] coco_agi        0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
[reg-discipline] POP3_port      59 register access(es) in 7 file(s) over 14 register(s).
[reg-discipline] karateka_coco3  8 register access(es) in 2 file(s) over 4 register(s).

picset.py re-run: set reproduces IDENTICALLY, 45 pictures
  selection sha256[:16] 156df0797c2c68f0   (T-P0-013 recorded 156df0797c2c68f0)
```

**★ §2T — POP `430a91c` and Karateka `78c8c27` unchanged from T-P0-013 §0**, both clean apart
from Karateka's pre-existing `last-run.log`, lwasm unchanged. No shared file is touched by this
task, so there is no artifact-moving change for a sibling build to be about; AC-1's two figures
are second-scale source measurements and were run fresh.

**★★ `-DPIC_NOCOUNT` / counted still separate.** Every timing here is the no-count build; every
count is the counted build.

---

### 1 — Summary

**★★★ I reordered the dispatch's §3 to B → A → C, and B then re-ranked A.** Part A restructures
the caller, so measuring the current caller-side work had to happen first or the ~75 cycles/check
figure would have become permanently unverifiable.

**★★★ Consultation trigger 2 fired, twice over.** The caller-side residual is **42.3 cycles per
check, not ~75** — and the direct benchmark found something nobody had looked at:

> **`put_pixel` cost 186 cycles per call and was 29.8% of the entire render.**
> **T-P0-012's regression had it at ~40.**

★★ It was the second largest component in the renderer and it was invisible because a regression
coefficient said it was small. **That is the third derived figure this project has carried as
measured** [L-41], and it is why AC-5 asked for an ablation.

**So Part A became `put_pixel` and the caller, not the row address.** The row hoist is
**measured and NOT implemented** — §3.5 shows it is roughly a wash, because the span loop touches
**three rows per pixel**, so "y is invariant along the span" is true per row and false for the
loop. ★ **That is trigger 5, and it is reported rather than worked around.**

> **Median 8.909 s → 7.473 s (16.1% faster). Worst 16.963 → 14.343 s.**
> **Cumulative over P3.4+P3.5: 11.102 → 7.473 s, 32.7% faster.**
> **`put_pixel` 186 → 125 cycles/call. Caller-side 42.3 → 32.5 cycles/check.**

★★★ **Identical, not merely passing.** AC-2 **45/45 byte-identical**; AC-3's counts **unchanged
to the unit** — boundary tests **3,666,862**, pixels 1,188,430, spans 54,918, fills 1,669, seed
peak 74 B, and the three path counters. The AC-9 captures are **byte-identical to P3.3's and
P3.4's**.

★ **AC-7: the unit of cost has not moved.** 204.2 → 170.6 cycles per boundary test, spread
1.11× → **1.13×**. Still flat.

**★★ AC-6 — the blast, answered with a number: NO, not at this point in the ordering.** §3.6 has
the arithmetic. ★★★ **And a correction to the dispatch's premise: the effective group is 8 AGI
pixels, not 16** — one AGI pixel is one CoCo3 *byte* here, because the nibble doubling IS the
pixel doubling, so `puls a,b,x,y,u` pulls 8 AGI pixels and `cmpd #$FFFF` clears two, not four.
**The leverage is half what the dispatch assumed.**

★ **Trigger 3 did not fire** — 7.473 s is still well above ~3 s.

### 2 — Files modified
- `src/harness/pic_probe.s` — **`put_pixel` rewritten** (both helper calls inlined, pointers
  formed only when their plane is enabled, the doubled colour byte precomputed); `scr_dbl` added
  and maintained by `op_set_visual` and the state reset; the bench generalised to four targets.
- `src/harness/pic_fill.s` — the **CC-preservation dance removed** from both y probes.

`src/engine/**` untouched — **0 `.s` files**. No game data, resource bytes, renderings or
screenshots committed (§2P).

### 3 — Reasoning

**3.1 ★★★ PART B FIRST, and why the ordering had to change.**
§3's A restructures the caller. Measuring the caller *after* restructuring it would measure the
new caller and leave T-P0-013's ~75 cycles/check permanently unchecked — the exact failure L-41
names. So B ran first.

**3.2 ★★★ B, measured directly: the render decomposed by SUBTRACTION of measured quantities.**
The bench that ablated `fill_check` in T-P0-013 was generalised to call any of four targets
through the identical loop, so the loop cancels in every difference:

| routine | before | after | method |
|---|---|---|---|
| `fill_check` | 85 | 85 | direct bench, 20,000 calls |
| **`put_pixel`** | **186** | **125** | direct bench, 20,000 calls |
| `ff_push` | 59 | 59 | direct bench (includes ~11 cyc of bench-only `ff_sp` reset) |

Then **caller-side = total − fill_check − put_pixel − ff_push − lines**, each term measured:

```
                                 BEFORE                    AFTER
fill_check          311.68 M  42.0%   85.0/chk    311.69 M  50.1%   85.0/chk
put_pixel           221.05 M  29.8%   60.3/chk    148.55 M  23.9%   40.5/chk
ff_push               2.64 M   0.4%    0.7/chk      2.64 M   0.4%    0.7/chk
lines + dispatch     51.49 M   6.9%   14.0/chk     40.61 M   6.5%   11.1/chk
RESIDUAL caller      155.06 M  20.9%   42.3/chk    119.09 M  19.1%   32.5/chk
TOTAL               741.92 M                      622.58 M
```

★ **What is unattributed:** the residual line itself. It is a subtraction, so it absorbs every
error in the four measured terms — but each of those is a direct benchmark rather than a fitted
coefficient, so the residual is far tighter than T-P0-012's regression.
★★ **One known contamination, stated:** `CNT_PIX` counts `put_pixel` calls from **lines as well
as fills** (1,188,430 hardware vs 1,165,306 fill-only offline — a 23,124 difference). Those
~23 k calls are counted in the `put_pixel` row **and** inside the `-DPIC_NOFILL` lines row, so
`put_pixel` is over-stated and the residual under-stated by **~2.9 M cycles, 0.5%**.

**3.3 ★★★ WHY `put_pixel` WAS 186 CYCLES, and it is the same three faults as `fill_check`.**
1. **`jsr in_bounds` and `jsr pix_addr`** — two subroutine calls, ~26 cycles of `jsr`/`rts`
   alone, for two compares and an address. Both inlined.
2. **`pix_addr` formed BOTH plane pointers on every call**, exactly as `fill_check` did before
   P3.4. Each pointer is now formed only inside its own plane's branch.
3. **The nibble doubling was recomputed per pixel** — `anda`, a second load, four `lslb`, a
   `pshs`/`ora ,s+` pair, ~30 cycles — from `scr_color`, **which cannot change during a fill.**
   `scr_dbl` is now maintained by `op_set_visual`, the only place a picture writes `scr_color`.
★ `scr_dbl` is identically `(scr_color & 15) * 17`, which is precisely what the old sequence
computed: the low nibble OR'd with itself shifted up four.

**3.4 ★★ The caller: 19 cycles of flag preservation, twice per pixel.**
Both y probes read `pshs cc / inc fc_y / puls cc` — 19 cycles whose only purpose was to stop
`inc` from disturbing Z across the y restore. Branching on the flag first and restoring on
**both** paths costs 7. ★ 12 cycles × 2 probes × 1.19 M pixels ≈ **28 M cycles**.

**3.5 ★★★ THE ROW HOIST: MEASURED, AND NOT IMPLEMENTED. Trigger 5.**
§3's A assumes *"along `ff_right`, y is invariant and x increments by one."* ★★ **The first half
is false as stated.** Per pixel the loop calls `fill_check` at **y−1, y and y+1** — three rows —
and `fc_y` is written four times per pixel. The arithmetic:

- Replacing the `mul` path with `fc_row + fc_x` saves **11 cycles** per call
  (`ldb fc_x / clra / addd fc_row / tfr d,x` = 19 against `ldb #160 / mul / addb / adca /
  addd #FB_BASE / tfr` = 30).
- But `fc_row` must then be set for whichever of the three rows is being probed: **10 cycles**
  (`ldd row_up / std fc_row`) at each of the three call sites.
- **Net −1 cycle per call.** Passing the base in `U` instead (which `fill_check` does not clobber)
  gets it to about **−5 cycles/call ≈ 18 M ≈ 2.4%** — for an interface change to the renderer's
  hottest routine.

★ **A single row base cannot serve a loop that interleaves three rows**, which is trigger 5's
*"a caller that changes y mid-span"* almost verbatim. **Not implemented; the number is recorded
so the next task need not re-derive it.**

**3.6 ★★★ AC-6 — THE STACK BLAST, ANSWERED.**

***First, a correction to the premise.*** The dispatch says *"a `D` of four is `$FFFF`"* and
*"`puls a,b,x,y,u` pulls 16 pixels at 4bpp."* ★★ **In this renderer one AGI pixel is one CoCo3
BYTE**, because the nibble doubling *is* the pixel doubling (design §3.3, and `put_pixel` writes
`scr_dbl` as a plain `sta`). So `cmpd #$FFFF` clears **two AGI pixels** and `puls a,b,x,y,u`
pulls **eight**. Both dispatch figures are right about *screen* pixels and **double the AGI-pixel
leverage the fill actually gets.**

***The measured inputs.***

| quantity | value |
|---|---|
| plane test's share of `fill_check` | **14 of 85 = 16.5%** (unchanged — `fill_check` was not touched) |
| span length | median **9**, mean 21.3, p25 4, p75 23, max 160 |
| spans shorter than one 8-px group | **46.9%** of spans, carrying 8.8% of pixels |
| pixels in fully-contained aligned **8**-px groups | **74.5%** |
| pixels in fully-contained aligned **4**-px groups | **87.2%** |
| right-scan self-checks | ≈1.22 M of 3.67 M checks (**33%**) |

***The arithmetic.*** A wide group costs ≈`puls`(13) + four immediate compares(19) + branch and
loop(~22) ≈ **54 cycles per 8 AGI pixels = 6.75/px**, against `fill_check`'s 85.

- **Self-scan only:** (85 − 6.75) × 0.745 × 1.22 M ≈ **71 M cycles = 11.4%** of the render.
- **Optimistically including the up/down probes** (two-thirds of all checks, where a uniformly
  fillable group means "no transition" and is the cheap case): **≈34%**.
- **Crossover:** in pure cycle terms a group wins from L≈1 (setup ~60 cycles against 78 saved per
  pixel). ★ **The real limit is not length but ALIGNMENT** — 25.5% of pixels sit in groups that
  straddle a span end and get no benefit at all, and that fraction is measured, not modelled.

***The answer: NO, not at this point in the ordering.*** Four reasons, in order of weight:
1. ★★ **Comparable gain is available at far lower risk and is not yet taken** — §8 lists ~20%
   from inlining `fill_check`'s call/return, removing a provably redundant y-bounds test, and
   unifying the fill's coordinates with `put_pixel`'s. **None of them borrows `S`.**
2. ★★★ **It borrows `S`, against a three-dispatch precedent.** POP `char_draw.s:512` — *"P3.81-83
   spent three dispatches on two wrong flame bytes that came from a `bsr` executed while S
   pointed into the framebuffer."* T-P0-011 paid a version of the same.
3. **It exceeds trigger 5's ~80-line budget** — a wide scan plus the narrowing path plus
   alignment handling plus the borrow/restore, inlined with no calls, is not 80 lines.
4. ★ **The leverage is half the dispatch's figure** (8 AGI pixels, not 16).

★★★ **What would change the answer, stated so it is citable without a re-run:** once §8's
low-risk items are taken, `fill_check` and the caller stop being 69% of the render and the wide
scan's ~34% ceiling becomes the largest remaining item. **Jay's headroom argument is sound and
the 34% is real — this is a "not yet", not a "no".**

**3.7 §2S — sibling claims and their ref.** POP `430a91c`, Karateka `78c8c27`, both `wip`, both
measured this task at those refs, scope `<repo>/src` excluding `src/hal` and `src/harness`. No
sibling file modified.

**3.8 Authority tier.** `put_pixel`'s structure follows `putVirtPixel` at the pin `9d9b9e9`
(tier 3): bounds check, then each plane written only if its flag is set. ★ The optimisation
changes **when** the address is computed, never **which** pixels are written — AC-3's identical
counts are the evidence. **Not verified against a running original** (tier 2).

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline.py` 0 / 59 / 8; `hal_sync_check.py` OK
  in all three, each naming the other two. §2T citation for the sibling *builds*; the two figures
  themselves run fresh.
- **AC-2 [class: byte-comparable] ★★★ PASS — 45/45 byte-identical, per picture, both planes**, at
  T-P0-013's hashes. Table verbatim in §5.
- **AC-3 [class: state-comparable] ★★★ PASS — behaviour did not move.** Boundary tests
  **3,666,862 → 3,666,862, 0 pictures moved**; put_pixel writes 1,188,430; ff_push 54,918;
  flood_fill 1,669; seed peak 74 B; path counters `path_v` 612,650 / `path_p` 236,140 /
  `path_g` 0 — **all identical to the unit.**
- **AC-4 [class: state-comparable] PASS.** Median **8.909 → 7.473 s (16.1%)**, worst
  **16.963 → 14.343 s (15.4%)**, over-10 s **4/45 → 3/45**. `fill_check` 85 → 85 (untouched);
  `put_pixel` **186 → 125**. Baseline **cited** from T-P0-013 (§2T). ★ **Run count: 1 per build**
  — emulated time is deterministic to 9 dp (L-33).
- **AC-5 [class: state-comparable] ★★★ PASS — measured, not regressed.** §3.2's table. The
  caller-side residual is **42.3 → 32.5 cycles/check**, against T-P0-013's regression estimate of
  ~75. ★ **Unattributed:** the residual line, plus a stated ~0.5% contamination from line-drawn
  `put_pixel` calls being counted in two rows.
- **AC-6 [class: state-comparable] ★★★ PASS — answered NO, with the arithmetic.** §3.6. Plane
  test 16.5% of `fill_check`; span median 9; 74.5% of pixels in fully-contained 8-px groups;
  estimated 11.4% (self-scan) to 34% (optimistic, all probes); crossover limited by **alignment**
  rather than length. ★ Includes the correction that the effective group is **8 AGI pixels, not
  16**.
- **AC-7 [class: state-comparable] PASS — the flatness held.** 204.2 → **170.6** cycles per
  boundary test; spread 1.11× → **1.13×**. The unit of cost has **not** moved.
- **AC-8 [class: byte-comparable] PASS.** `-DPIC_FAULT` armed on `Kingquest3-030` only:
  **44 PASS, 1 FAIL, and the failure is `Kingquest3-030`.** exit 0.
- **AC-9 [class: eye-gated] PENDING JAY.** Three rooms at
  `C:\karateka-capture\agi_captures\agi-p3.5-*-RGB-4x3.png`, **outside the repo** (§2P), pixels
  not interpreted by Clyde (§3). **Launch path `poke`, RGB, 4:3.** ★★ **Byte-identical to P3.3's
  and P3.4's captures** — the expected result, and corroboration of AC-2 through the display path
  rather than the readback path (idiom 19j).
- **AC-10 [class: suite] PASS.** Two candidates; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-5 PART B: routine costs, DIRECT benchmark (20,000 calls each, -DPIC_NOCOUNT) ===
  routine        before    after   change
  fill_check         85       85        -
  put_pixel         186      125     -33%
  ff_push            59       59        -
  ★ fill_check and ff_push are UNCHANGED this task -- the measurement sent the work to
    put_pixel and to the caller instead.

=== AC-5: decomposition by SUBTRACTION of measured quantities (after) ===
  component                        Mcycles    share  cyc/check
  fill_check                        311.69    50.1%       85.0
  put_pixel                         148.55    23.9%       40.5
  ff_push                             2.64     0.4%        0.7
  lines + opcode dispatch            40.61     6.5%       11.1
  RESIDUAL caller-side              119.09    19.1%       32.5
  TOTAL                             622.58
  ★ caller-side residual 42.3 -> 32.5 cycles/check   (regression had estimated ~75)

=== AC-4 / AC-7 ===
  render BEFORE  min 6.709  median 8.909  max 16.963
  render AFTER   min 5.603  median 7.473  max 14.343
  ★ median 8.909 -> 7.473 s (16.1% faster)   worst 16.963 -> 14.343 s (15.4%)
  over 10 s: 4/45 -> 3/45     over 5 s: 45/45 -> 45/45     over 3 s: 45/45 -> 45/45
  fill share: 93.1% -> 93.5%
  ★ P3.3 baseline was median 11.102 s; cumulative over P3.4+P3.5: 32.7% faster
  cycles per boundary test:
    BEFORE min 188.8  median 204.2  max 210.2  spread 1.11x
    AFTER  min 159.7  median 170.6  max 181.1  spread 1.13x
  ★ the unit of cost is STILL the boundary test

=== AC-3: identity evidence, T-P0-013 -> T-P0-014 ===
  boundary tests     before    3666862  after    3666862  IDENTICAL
  put_pixel writes   before    1188430  after    1188430  IDENTICAL
  ff_push            before      54918  after      54918  IDENTICAL
  flood_fill         before       1669  after       1669  IDENTICAL
  seed peak (max)    before         74  after         74  IDENTICAL
  pictures whose check count moved: 0
  path_v             before     612650  after     612650  IDENTICAL
  path_p             before     236140  after     236140  IDENTICAL
  path_g             before          0  after          0  IDENTICAL
```

```
=== AC-6: the span-length distribution and aligned-group coverage ===
﻿AC-6 -- SPAN LENGTH DISTRIBUTION over the 45-picture set
  54739 spans, 1165306 pixels written, mean 21.3 px/span
  min 1   p25 4   median 9   p75 23   p90 56   p99 160   max 160

  cumulative share of PIXELS in spans of length <= L:
    L <= 1        0.3% of pixels   (  7.3% of spans)
    L <= 2        1.1% of pixels   ( 15.6% of spans)
    L <= 3        2.1% of pixels   ( 22.6% of spans)
    L <= 4        3.2% of pixels   ( 28.3% of spans)
    L <= 6        5.8% of pixels   ( 38.4% of spans)
    L <= 8        8.8% of pixels   ( 46.9% of spans)
    L <= 12      14.6% of pixels   ( 59.0% of spans)
    L <= 16      20.5% of pixels   ( 67.7% of spans)
    L <= 24      28.9% of pixels   ( 76.6% of spans)
    L <= 32      35.5% of pixels   ( 81.6% of spans)
    L <= 64      57.3% of pixels   ( 91.7% of spans)
    L <= 160    100.0% of pixels   (100.0% of spans)

  ★ spans shorter than 16 px (one `puls a,b,x,y,u` load): 36005 of 54739 spans (65.8%),
    carrying 19.1% of all pixels written.

  GROUP SIZE 4 px (4 bytes, one wide load):
    pixels in FULLY-CONTAINED aligned groups:  1015668   87.2%
    pixels needing the per-pixel fallback   :   149638   12.8%

  GROUP SIZE 8 px (8 bytes, one wide load):
    pixels in FULLY-CONTAINED aligned groups:   868184   74.5%
    pixels needing the per-pixel fallback   :   297122   25.5%

  GROUP SIZE 16 px (16 bytes, one wide load):
    pixels in FULLY-CONTAINED aligned groups:   677056   58.1%
    pixels needing the per-pixel fallback   :   488250   41.9%
```

```
=== AC-2 THE GATE — 45 pictures, 3 games, per picture ===
﻿picture            fills  bytes  visual                                 priority                               verdict
--------------------------------------------------------------------------------------------------------------------------------
Kingquest1-080         2    211  identical ef1556f2ae78156e             identical 98cdf968fe6321ca             PASS
Kingquest1-053        26   1057  identical 4e406e78ed2864c3             identical e445ae1bb555aac8             PASS
Kingquest2-094        19   1046  identical a15d01f8f8fa836a             identical da6e1e7355a56fec             PASS
Kingquest3-074        23   1077  identical ad159c03a787768c             identical 1c8d02dd6fdb5951             PASS
Kingquest1-065        25   1145  identical 4fe804be8ba8e631             identical 4e4fa36876a1d64c             PASS
Kingquest2-014        19   1159  identical bf1d04d8867e568d             identical db0c0f800a39fdd3             PASS
Kingquest3-065        17   1207  identical c8f9c7884b89fbc1             identical 6e4b0a322d7b5ef4             PASS
Kingquest1-022        23   1188  identical 1d6484c36edbb44a             identical 6e2b30f87bd1f14d             PASS
Kingquest2-024        13   1063  identical d73bafd8348bc9ad             identical 2ebfeff596cc3b20             PASS
Kingquest3-076        11   1148  identical 120aa06ce4be9d77             identical 199d600642c62165             PASS
Kingquest1-045        21   1207  identical b52f0e638a292e68             identical 0d508f21386f1f89             PASS
Kingquest2-071        13    801  identical c97c9ea144eea08c             identical bb75100dc968f379             PASS
Kingquest3-073        11    681  identical 06645160df3e8356             identical 678931c156158327             PASS
Kingquest1-004        20   1095  identical be7eff18a9faab2d             identical ff25c944eab7f1e7             PASS
Kingquest2-011        12   1124  identical 6116868099594a0d             identical 94f0d545e6d4cd4e             PASS
Kingquest3-048        10   1230  identical 66a8b842b07aa761             identical 9f8957fa5b62b548             PASS
Kingquest1-034        20   1137  identical 93a1419091da6992             identical 35d322ed914f73c7             PASS
Kingquest2-104        12    832  identical 528edc6da2dffd8e             identical 87905a4f63749e1e             PASS
Kingquest3-148        10    773  identical 0b55ace7eef93d5a             identical 171f1751263a710d             PASS
Kingquest1-050        19   1149  identical 8c63debbe0ac68dc             identical 438d17c80ea009a3             PASS
Kingquest2-080        10   1134  identical 7f10a73c696db81f             identical 4366bf0af6d2be5b             PASS
Kingquest3-064        10    841  identical 44aa2b8a9a2729dc             identical a06790a753da2b1c             PASS
Kingquest1-062        19   1095  identical e29787e3ded359f2             identical 8a6878397361d27e             PASS
Kingquest2-072         9   1202  identical d36edd7a021b5ee0             identical 5ee2a913c6dc8b25             PASS
Kingquest3-030         9   1254  identical 0b7284459bd39be3             identical 5d6dbede8c557e3d             PASS
Kingquest1-009        18   1167  identical a19c33db4a8eb7ee             identical 7a9a6989952ded3d             PASS
Kingquest2-067         7    927  identical 3be05d2c3d9973a2             identical 15e6c0ff6ba9dbaa             PASS
Kingquest3-078         8   1060  identical 50d3dcef68daa5e0             identical c895099487c73845             PASS
Kingquest1-058        18   1082  identical e70c6792826c75ca             identical 71dbba7fd3630d34             PASS
Kingquest2-050         6    261  identical f08d321118468ff2             identical e070fbde0eb62b0a             PASS
Kingquest3-060         8   1083  identical 639411f279fb94ed             identical 607ff39fcd86dfd0             PASS
Kingquest1-043        18   1170  identical a8b5a5849618e668             identical 1137e894a455b66a             PASS
Kingquest2-096         6    387  identical 010928b46bb6bf8b             identical efe4f788ff43ba8d             PASS
Kingquest3-062         7    917  identical c9f8e1ee7cc82384             identical d9c8a981a2c5e3e2             PASS
Kingquest1-056        17   1184  identical ea08fe5bf5e3aad9             identical 94ed225c5d72c015             PASS
Kingquest2-097         5   1059  identical f128df72e6801108             identical ecefcc9dd87f2464             PASS
Kingquest3-075         7    977  identical e2f567c10e1c85d5             identical f50c69479ba4bd3d             PASS
Kingquest1-055        16   1077  identical fe6c30720f1344d1             identical f16f536926411085             PASS
Kingquest2-114         4    996  identical 4a08c76fca7b30d6             identical ecefcc9dd87f2464             PASS
Kingquest3-063         6   1193  identical 400b92785e0f98bd             identical 148501a197bc032e             PASS
Kingquest1-060        16   1114  identical a6d333832b4b5555             identical 7faa9b2022398add             PASS
Kingquest2-095         4    420  identical 010928b46bb6bf8b             identical 9a3c1b9afd670071             PASS
Kingquest3-036         5   1129  identical c74622043798bd62             identical 6696758a4d5a1381             PASS
Kingquest1-021        15   1142  identical 84c2a13938b38b1a             identical 7eb9e3d90ed62bf6             PASS
Kingquest2-073         3    844  identical 0ce9958fcb5544d4             identical ae94489a381e63d5             PASS
--------------------------------------------------------------------------------------------------------------------------------
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
```

```
=== AC-8 the gate can still fail, and still localises ===
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)   [fault armed on Kingquest3-030 only]
★ FAILING PICTURES (named, not counted):
    Kingquest3-030 visual
★ --expect-fail: a FAIL here is the expected result.
exit=0

=== AC-9 corroboration through the DISPLAY path (idiom 19j) ===
KQ1-080    P3.4 88AFDEBBD487  P3.5 88AFDEBBD487  IDENTICAL
KQ2-094    P3.4 2ED9A6DE8708  P3.5 2ED9A6DE8708  IDENTICAL
KQ3-074    P3.4 F17920528DDC  P3.5 F17920528DDC  IDENTICAL
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` still ships no bundle; no `build.bat`, no
`LOADER.BIN`, no disk image (all out of scope). Probe binaries are gitignored.

25.3 operator-runtime-smoke: **pending Jay.** ★ Launch path **`poke`**, monitor **RGB**, aspect
**4:3**. Three rooms in `C:\karateka-capture\agi_captures\`.

### 6 — Reactive deviations and route accounting

- ★★★ **Trigger 2 FIRED and is reported prominently.** The caller-side figure was **42.3, not
  ~75** — and the ablation exposed `put_pixel` at **186 cycles, 29.8% of the render**, where the
  regression had said ~40. **Two derived figures wrong in the same subsystem.**
- ★★★ **Trigger 5 FIRED.** The row hoist cannot be satisfied by a single row base because the
  span loop probes three rows per pixel. **Measured at roughly a wash and NOT implemented**
  (§3.5).
- **Trigger 1 did NOT fire** — AC-2 is 45/45 and AC-3's counts are identical to the unit.
- **Trigger 3 did NOT fire** — median 7.473 s, still well above ~3 s.
- **Trigger 4 did not arise** — the blast was **not implemented** (§3.6), so `S` was never
  borrowed and no line budget was spent.
- ★★ **Deviation: I reordered §3 to B → A → C**, and then B re-ranked A. The dispatch invited
  this — *"§3 is your ordering… if B or C overturns it, say so"* — and it did: **A became
  `put_pixel` and the caller, and the row address was measured and declined.**
- **ROUTE ACCOUNTING.** ★ **What I did NOT do:** the row-address hoist (measured, ~a wash, §3.5);
  the stack blast (answered NO with arithmetic, §3.6); the coordinate unification and the
  `fill_check` inlining (§8, quantified but out of this task's scope). ★★ **One thing not asked
  for:** generalising the bench to four targets, which is what turned AC-5 from a regression into
  a measurement and is reusable for any future routine.

### 7 — Uncertainty flags

- ★★★ **7.473 s is still far too slow.** Two tasks have taken 32.7% and the figure is not in the
  design's neighbourhood. **§8 quantifies ~20% more at low risk and ~34% from the blast**; even
  all of it together does not obviously reach a usable budget, and that is the open question this
  project has not yet confronted.
- ★★ **AC-6's 34% figure is an ESTIMATE, not a measurement.** The 11.4% self-scan figure rests on
  measured inputs (span coverage, `fill_check` cost); the 34% assumes the up/down probes wide-scan
  as well as the self probe, which **has not been prototyped**. ★ Treat 11.4% as the floor and
  34% as an optimistic ceiling.
- ★ **`put_pixel`'s new 125 cycles was benchmarked in ONE state** (both planes on, in bounds).
  The out-of-bounds early return and the single-plane paths are inferred from the instruction
  stream, not measured.
- ★ **The `put_pixel`/lines double-count is ~0.5%** and is stated in §3.2 rather than corrected.
- ★ **45 pictures of 3 games is still not the corpus** (597 offline); resources > 1,280 B remain
  excluded by the probe window.
- ★ **A 128 KB build has not been run** (§2K). **Tier-2 evidence was not consulted.**

### 8 — Follow-up candidates
1. ★★★ **Inline `fill_check` at its five call sites.** Its `jsr`/`rts` is **13 of 85 cycles**, and
   it is called 3.67 M times: **≈47.7 M cycles, 7.7%**, with no interface change and no `S`.
2. ★★ **Remove `fill_check`'s y-bounds test.** Every call site already guarantees y in range —
   `ff_up` guards `y==0`, `ff_down_test` guards `y>=PIC_H-1`, and seeds are pushed only after
   those guards. **10 cycles × 3.67 M ≈ 36.7 M, 5.9%** — but it needs the guarantee proved per
   call site, not asserted.
3. ★★ **Unify the fill's coordinates with `put_pixel`'s.** `ff_right` copies `fc_x`/`fc_y` into
   `cur_x`/`cur_y` before every `put_pixel` — **20 cycles × 1.19 M ≈ 23.8 M, 3.8%.**
4. ★ **Then re-evaluate the blast** (§3.6) — after 1–3 it becomes the largest remaining item.
5. **Widen the gate beyond 45 / 3 games**; raise the probe's resource window.
6. ★ **A `reports/` encoding check** — carried from T-P0-011 §3.12, still not built.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
Two, both to `seeds/AGI/live/` (§2C — new rows, nothing existing read or edited):

1. **`a-regression-coefficient-is-a-hypothesis-about-a-cost`** — ★★★ `put_pixel` was fitted at
   ~40 cycles and measured at **186**, hiding 29.8% of the render in plain sight for two tasks.
   ★ A fitted coefficient over collinear regressors is a lead; **the routine is right there and
   can be called 20,000 times in a loop.**
2. **`check-the-units-of-a-borrowed-figure`** — the blast's "16 pixels per `puls`" is true of
   *screen* pixels and half-true of the pixels the fill operates on. ★ Same shape as the
   253-cycle ratio: **a number that is correct in one unit and load-bearing in another.**

### 11 — Commit
`8193e8e` — P3.5 hoist the row address; ablate the caller; answer the blast
Pool `5e5ede5` — the two candidate rows (§10)
(pushed to origin/wip before this report; `8193e8e` carries the report itself)
