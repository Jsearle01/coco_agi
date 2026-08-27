## Form B Report — P3.4 — the boundary test: decomposed, then optimised
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-26 (dispatch T-P0-013 receipt; HEAD at receipt `07578f3`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  07578f3f21f4178d6c30621ed51ce7ae096b304f  tracked-dirty 0
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

picset.py re-run: set reproduces IDENTICALLY, 45 pictures, selection sha256[:16] 156df0797c2c68f0
  Kingquest1 16 / Kingquest2 15 / Kingquest3 14; 577 fills; all 10 implemented opcodes reached
```

**★ §2T — POP `430a91c` and Karateka `78c8c27` are unchanged from T-P0-012 §0**, both clean apart
from Karateka's pre-existing `last-run.log`, lwasm unchanged at 4.24. ★ **No shared file is
touched by this task** (everything is `src/harness/` and `harness/tools/`), so there is no
artifact-moving change for a sibling build comparison to be about. The two figures AC-1 wants are
second-scale source measurements and were **run fresh rather than cited** — cheaper than a
citation and strictly stronger.

**★★ The -DPIC_NOCOUNT / counted separation still holds and is load-bearing here.** Every timing
figure in this report is from the **no-count** build; every count is from the **counted** build.
★★★ **This mattered more than usual: the counted build GAINED three path counters this task, so
a counted-vs-counted comparison would have reported the optimisation as ~3% instead of 19.7%.**

---

### 1 — Summary

**Part A first, because it changed what Part B did.**

★★★ **A correction to my own T-P0-012 headline, which this dispatch quotes as its premise.** That
report said *"`fill_check` costs 253 cycles"*. **253 is a RATIO — total render cycles divided by
`fill_check` calls — not the cost of the routine.** Measured directly by ablation,
**`fill_check` was 141 cycles per call**, and the four block costs agree **exactly** with a hand
count from the assembled listing. **112 cycles per call (44%) were never inside `fill_check`.**
The flatness finding stands and was the right lead; the sentence over-claimed.

★★★ **Consultation trigger 1 FIRED: the `mul` is NOT the dominant term.** It is **11 cycles** of
the original 141 — **8%** — and the row-address block containing it is 25, the *third* largest.
The two larger blocks were **flag dispatch + plane test (48)** and **pointer forming (34)**. §4's
candidate ordering is overturned and Part B was reordered accordingly.

**Part B took the two blocks the measurement named, not the one that was visible:**

> **Median 11.102 s → 8.909 s per room (19.7% faster). Worst 21.007 → 16.963 s.**
> **Pictures over 10 s: 37 of 45 → 4 of 45.**
> **`fill_check` itself: 141 → 86 cycles per call (39% faster).**

★★★ **And it is identical, not merely passing.** AC-3 is **45/45 byte-identical, per picture**;
AC-6's boundary-test count is **3,666,862 → 3,666,862 with zero pictures moved**; pixels, spans,
fills and the seed-stack peak are **all unchanged to the unit**. ★ The three AC-9 screenshots are
**byte-identical to P3.3's**, which corroborates the same conclusion through the display path
rather than the readback path (idiom 19j).

★ **AC-5: the unit of cost has NOT moved.** Cycles per boundary test 253.3 → 204.2, spread
**1.12× → 1.11×**. Still flat, so the boundary test is still what cost tracks.

★ **Trigger 4 did not fire** — 8.909 s is a long way from ~2 s. **The renderer is still far too
slow for the design's budget**, and §8 carries what the measurement says to do next.

### 2 — Files modified
- `src/harness/pic_fill.s` — **`fill_check` rewritten** around a once-per-fill case byte; the
  once-per-fill decision added to `flood_fill`; `FC_STOP0..3` ablation points; per-path counters.
- `src/harness/pic_probe.s` — `-DFC_BENCH` microbenchmark mode, `PATH_V/P/G` equates, `fc_case`
  set in the bench.
- `harness/tools/pic_sweep.lua` — path counters in the readback (3 new CSV columns).

`src/engine/**` untouched — **0 `.s` files**. No game data, resource bytes, renderings or
screenshots committed (§2P).

### 3 — Reasoning

**3.1 ★★★ PART A — how the 253 was decomposed, and the two methods that agree.**

*Method 1, static.* Every instruction of `fill_check` was cycle-counted from the **assembled
listing** (not the source), for the both-planes-on path. Labelled as derived arithmetic per §8.

*Method 2, measured.* `-DFC_STOP0..3` return early after each block, so five builds of **the same
routine, truncated** were timed over 20,000 calls each through the render's own write-tap. **The
code being timed IS `fill_check`** — no copy to drift. Successive differences give the blocks.

★★ **They agree exactly:** bounds 20, row address 25, pointer forming 34, flags+test+verdict 48.
**A static derivation and a dynamic measurement agreeing block-for-block is the strongest form of
agreement available** — no shared assumption between them.

**3.2 ★★★ Attributing all 253, including what is NOT in `fill_check`.**
`fill_check` is 141. The other 112 were attributed by **regression across the 45 pictures**, whose
differing ratios of checks to pixels to spans make the coefficients separable:

| component | cycles/check | how |
|---|---|---|
| `fill_check` itself | **141** | direct ablation, exact |
| fill-loop caller-side per check | ~75 | regression (216 total per check, less the 141) |
| `put_pixel` | ~13 | regression, ~40 cycles/call × 0.32 calls/check |
| `ff_push` | ~5 | regression |
| non-fill work (lines, dispatch) | ~20 | regression constant, ~1.6 M cycles/picture |
| **total** | **~254** | against the measured 251–253 |

★ **The regression's limits, stated rather than buried:** five parameters over 45 observations
with collinear regressors; the `flood_fill`-entry coefficient came out **negative (−5,704)**,
which is a fit artifact, not a physical cost. Median residual 0.75%, max 4.60%. **The 141 is
solid; the 112's internal split is indicative and I would not build a decision on any single one
of its rows.**

**3.3 ★★ Which path the corpus actually takes — measured, not assumed.**
Before attributing cycles to any of `draw_FillCheck`'s three cases, three counters were added:

```
visual-only  1,452,247  39.6%      priority-only  236,140   6.4%
general      1,126,507  30.7%      returned before any plane test  851,968  23.2%
```

★★ **The visual-only and general cases are 70.3% of calls, and they are THE SAME TEST.**

**3.4 ★★★ PART B — the optimisation, and why it is provably identical.**
At the pin, case 1 is `!priOn && scrOn && scrColor != 15 → screenColor == 15` and the catch-all is
`scrOn && screenColor == 15 && scrColor != 15`. **Both test the visual plane for 15**; they differ
only in the route that reaches them. So the three-way choice collapses to:

```
FC_VISUAL    scr_on && scr_color != 15            -> visual == 15
FC_PRIORITY  pri_on && !scr_on && pri_color != 4  -> priority == 4
FC_NEVER     otherwise                            -> always false
```

★★★ **The decision depends only on four flags and never on the pixel**, and those flags are
written only by opcodes F0–F3 — never during a fill. So it is hoisted to `flood_fill` entry.
★★ **Verified by exhaustive enumeration, not by argument: all 262,144 combinations** of
`pri_on`/`scr_on`/`scr_color`/`pri_color` × both pixel values agree with the pin's function,
**0 mismatches.** ★ `FC_NEVER` skips the bounds test, which is identical — out-of-bounds and
never-fillable both yield false.

**Three savings, all "identical, only cheaper":**
1. the flag dispatch and the general case's re-checks disappear — **48 → 14 cycles**;
2. the **priority pointer is no longer formed on the visual path** — the `pshs`/`puls` pair
   existed only to carry a pointer that 70% of calls never read — **34 → 10 cycles**;
3. `lda fc_y` was issued **twice** — A still holds `fc_y` after the bounds compare — **25 → 20**.

Cost: an 8-cycle case dispatch, folded into the bounds block (20 → 28).

**3.5 ★ What was NOT done, and why.** §4's candidates 3 and 4 (wide compares, `puls` as a 16-pixel
load) were **not attempted**. Part A says why: the whole plane test is now **14 cycles** of an
86-cycle call, so a wide scan can win at most 14 and would pay §6's `S`-borrowing risk — POP spent
three dispatches on two wrong bytes from exactly that. ★★ **The remaining cost is not in the
compare; it is in the bounds test (28), the row address (20) and the call itself (13).** §8
carries the leads that follow from that, in measured order.

**3.8 ★ The capture step is now a tracked script, at Jay's request.**
All AGI captures moved to `C:\karateka-capturegi_captures\` (ten files, P3.2 onward), and
`harness/tools/roomshots.ps1` writes there by default. ★★ **It asserts the three things that each
cost a rejected capture earlier in P3**: `-DPIC_PRESENT` so the flip is `HAL_gfx_swap` and not the
legacy `HAL_gfx_present` (idiom 19j); Monitor Type = RGB, set and logged from Lua because MAME's
`coco3` defaults to COMPOSITE (19l); and `-snapview auto -snapsize 640x480 -keepaspect`, because
the default `native` means SQUARE pixels and stretched every capture ~2x (19k). ★ It **reads each
delivered PNG's IHDR back** to verify 4:3 rather than trusting the flags. Verified by re-running
it: the three captures come out **byte-identical to the ones Jay gated**.

**3.6 §2S — sibling claims and their ref.** POP `430a91c`, Karateka `78c8c27`, both `wip`, both
measured **this task** at those refs, scope `<repo>/src` excluding `src/hal` and `src/harness`.
No sibling file was modified.

**3.7 Authority tier.** The equivalence proof rests on **ScummVM at the pin `9d9b9e9`**
(`draw_FillCheck`, tier 3), enumerated exhaustively against a transcription of that function.
★ Per §2.1 the three-case structure is believed **ORIGINAL** rather than a ScummVM normalisation —
it is load-bearing for rendering any v2 picture, and the 45/45 byte-identity across three games is
consistent with that. **Not verified against a running original** (tier 2); stated as a limit.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline.py` `coco_agi` **0**, POP **59**,
  Karateka **8**; `hal_sync_check.py` **OK in all three**, each naming the other two. Run fresh
  (see the C-13 note on why citation was not the cheaper path here).
- **AC-2 [class: state-comparable] ★★★ PASS — the durable artifact.** All 141 cycles of
  `fill_check` attributed by two independent methods that agree exactly; the remaining 112 of the
  253 ratio attributed by regression with its limits stated (§3.2). ★ **Trigger 1 fired: the
  `mul` is 11 cycles, 8% of the original call.**
- **AC-3 [class: byte-comparable] ★★★ PASS — 45/45, per picture, both planes**, at the same
  hashes as T-P0-012. Table verbatim in §5. ★ Corroborated independently: the three AC-9
  screenshots are byte-identical to P3.3's.
- **AC-4 [class: state-comparable] ★★★ PASS.** Median **11.102 → 8.909 s (19.7% faster)**, worst
  **21.007 → 16.963 s (19.3%)**, over-10 s **37/45 → 4/45**. Fill share **94.4% → 93.1%**.
  ★ Baseline **cited** from T-P0-012's recorded `-DPIC_NOCOUNT` run, not re-derived (§2T).
  ★ **Run count: 1 per build** — emulated time is deterministic to 9 dp, so repetition adds no
  information (L-33); stated rather than padded.
- **AC-5 [class: state-comparable] PASS — the flatness SURVIVED.** Cycles per boundary test
  **253.3 → 204.2**; spread **1.12× → 1.11×**. ★ The unit of cost has **not** moved, so L-39's
  finding still holds and the next optimisation still aims at the same unit.
- **AC-6 [class: state-comparable] ★★★ PASS — behaviour did not move.** Boundary tests
  **3,666,862 → 3,666,862**, **0 pictures changed**. Pixels 1,188,430 → 1,188,430; spans
  54,918 → 54,918; fills 1,669 → 1,669. **Identical to the unit on every structural count.**
- **AC-7 [class: byte-comparable] PASS — and it still localises.** `-DPIC_FAULT` armed on
  `Kingquest3-030` only: **44 PASS, 1 FAIL, and the failure is `Kingquest3-030`.** exit 0.
- **AC-8 [class: state-comparable] PASS.** Seed-stack peak **74 B / 37 entries → 74 B / 37
  entries**, max unchanged; the per-picture distribution is identical. ★ The wide-scan change that
  might have altered seeding was not made (§3.5), so this is a confirmation rather than a risk
  retired.
- **AC-9 [class: eye-gated] ★★ PASS — Jay, `poke`, RGB, 4:3.** Jay: *"rooms look fine."*
  Three rooms — KQ1 #80, KQ2 #94, KQ3 #74 — at
  `C:\karateka-capture\agi_captures\agi-p3.4-*-RGB-4x3.png`, **outside the repo** (§2P), pixels not interpreted
  by Clyde (§3). **Launch path `poke`, RGB, 4:3** (640×480 verified from each IHDR).
  ★★ Per idiom 19j a byte-identical buffer proves nothing about the screen — which is why these
  were captured even though AC-3 is green.
- **AC-10 [class: suite] PASS.** Two candidates; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-2 PART A: fill_check DECOMPOSED, before and after ===
   (20,000 calls per variant, FC_VISUAL path, -DPIC_NOCOUNT, ablation of the SAME routine)
BEFORE block                              cycles   AFTER block                               cycles
----------------------------------------------------------------------------------------------------
bench loop + jsr + rts                      32.0   bench loop + jsr + rts                      32.0
bounds test                                 20.0   case dispatch + bounds test                 28.0
row address (mul)                           25.0   row address (mul)                           20.0
pointer forming (BOTH planes)               34.0   pointer forming (visual only)               10.0
flag dispatch + plane test + verdict        48.0   plane test + verdict                        14.0
----------------------------------------------------------------------------------------------------
fill_check per call (jsr+rts incl.)        141.0   fill_check per call (jsr+rts incl.)         86.0

STATIC cross-check from the assembled listing (independent method):
  bounds 20 | row address 25 | pointer forming 34 | flags+test+verdict 48  -- EXACT AGREEMENT
  the mul itself is 11 cycles = 8% of the original 141

=== AC-2: path distribution over the 45-picture set ===
  visual-only   1452247  39.6%     priority-only  236140   6.4%
  general       1126507  30.7%     returned early 851968  23.2%
  ★ visual-only + general = 70.3%, and they are the SAME test

=== AC-2: the once-per-fill decision is EXHAUSTIVELY equivalent ===
  262144 state combinations tested (every pri_on/scr_on/scr_color/pri_color/vis/pri)
  mismatches: 0
```

```
=== AC-3 THE GATE — 45 pictures, 3 games, per picture, AFTER the optimisation ===
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
=== AC-4 / AC-5 before/after ===
﻿AC-4 -- BEFORE / AFTER on the same 45 pictures (-DPIC_NOCOUNT both sides)
picture             before_s   after_s   change    fill_b    fill_a
------------------------------------------------------------------------
Kingquest1-080         9.810     7.902   -19.4%     9.590     7.682
Kingquest1-053         9.847     7.951   -19.3%     9.075     7.179
Kingquest2-094        15.116    12.235   -19.1%    14.619    11.738
Kingquest3-074         9.960     8.037   -19.3%     9.178     7.255
Kingquest1-065        10.873     8.808   -19.0%    10.102     8.036
Kingquest2-014        12.407     9.998   -19.4%    11.802     9.393
Kingquest3-065         9.769     8.015   -17.9%     8.696     6.943
Kingquest1-022        10.986     8.869   -19.3%    10.327     8.210
Kingquest2-024        11.135     8.909   -20.0%    10.660     8.435
Kingquest3-076        11.325     9.032   -20.2%    10.717     8.424
Kingquest1-045        11.022     8.879   -19.4%    10.337     8.195
Kingquest2-071         8.319     6.709   -19.3%     7.680     6.070
Kingquest3-073        10.322     8.275   -19.8%     9.781     7.734
Kingquest1-004        11.176     9.001   -19.5%    10.435     8.260
Kingquest2-011        11.036     8.882   -19.5%    10.468     8.314
Kingquest3-048        11.135     8.914   -20.0%    10.584     8.362
Kingquest1-034        11.731     9.494   -19.1%    11.056     8.819
Kingquest2-104         9.918     7.999   -19.3%     9.308     7.389
Kingquest3-148        11.031     8.796   -20.3%    10.645     8.411
Kingquest1-050        11.202     9.065   -19.1%    10.365     8.228
Kingquest2-080        13.284    10.781   -18.8%    12.643    10.140
Kingquest3-064        11.226     8.972   -20.1%    10.597     8.342
Kingquest1-062        10.923     8.819   -19.3%    10.107     8.004
Kingquest2-072        11.498     9.196   -20.0%    10.795     8.492
Kingquest3-030        11.255     9.081   -19.3%    10.656     8.482
Kingquest1-009        10.999     8.888   -19.2%    10.373     8.262
Kingquest2-067        11.819     9.504   -19.6%    11.133     8.818
Kingquest3-078        11.190     9.096   -18.7%    10.454     8.360
Kingquest1-058        10.958     8.843   -19.3%    10.206     8.091
Kingquest2-050        10.719     8.420   -21.4%    10.510     8.211
Kingquest3-060        10.212     8.270   -19.0%     9.447     7.505
Kingquest1-043        11.503     9.237   -19.7%    10.750     8.485
Kingquest2-096        20.830    16.837   -19.2%    20.512    16.519
Kingquest3-062        11.265     8.969   -20.4%    10.613     8.317
Kingquest1-056         9.734     7.981   -18.0%     8.696     6.943
Kingquest2-097         9.315     7.566   -18.8%     8.774     7.024
Kingquest3-075        11.310     9.019   -20.3%    10.710     8.418
Kingquest1-055        10.444     8.383   -19.7%     9.729     7.668
Kingquest2-114        10.770     8.709   -19.1%    10.345     8.284
Kingquest3-063        11.448     9.143   -20.1%    10.616     8.311
Kingquest1-060        10.810     8.772   -18.8%    10.025     7.988
Kingquest2-095        21.007    16.963   -19.3%    20.787    16.743
Kingquest3-036        11.536     9.248   -19.8%    10.813     8.526
Kingquest1-021        11.102     8.976   -19.1%    10.312     8.186
Kingquest2-073        11.336     9.092   -19.8%    10.811     8.568
------------------------------------------------------------------------
  render   BEFORE  min 8.319  median 11.102  max 21.007
  render   AFTER   min 6.709  median 8.909  max 16.963
  ★ median 11.102 -> 8.909 s  (19.7% faster)   worst 21.007 -> 16.963 s  (19.3% faster)
  in cycles: median 19.87 M -> 15.95 M
  fill share of total: BEFORE 94.4%   AFTER 93.1%
  over 3 s: before 45/45, after 45/45 | over 10 s: before 37/45, after 4/45

AC-5 -- cycles per boundary test, and whether the flatness survived
  BEFORE min  233.9 (Kingquest2-095)  median  253.3  max  260.8 (Kingquest3-063)  spread 1.12x
  AFTER  min  188.8 (Kingquest2-095)  median  204.2  max  210.2 (Kingquest3-065)  spread 1.11x
  ★ 1.12x -> 1.11x : the unit of cost IS STILL THE BOUNDARY TEST
```

```
=== AC-6 boundary-test count and structural counts: before vs after ===
  before 3666862   after 3666862   delta 0
  pictures whose check count moved: 0
  pixels         before    1188430  after    1188430  IDENTICAL
  spans          before      54918  after      54918  IDENTICAL
  fills          before       1669  after       1669  IDENTICAL
  sp_peak_bytes  before        686  after        686  IDENTICAL
  AC-8 seed peak: before 74 B  after 74 B
```

```
=== AC-7 the gate can still fail, and still localises ===
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)   [fault armed on Kingquest3-030 only]
★ FAILING PICTURES (named, not counted):
    Kingquest3-030 visual
★ --expect-fail: a FAIL here is the expected result.
picgate exit=0  (0 = fault caught)
```

```
=== AC-3 corroborated through the DISPLAY path, not the readback path (idiom 19j) ===
KQ1-080    P3.3 88AFDEBBD487  P3.4 88AFDEBBD487  IDENTICAL
KQ2-094    P3.3 2ED9A6DE8708  P3.4 2ED9A6DE8708  IDENTICAL
KQ3-074    P3.3 F17920528DDC  P3.4 F17920528DDC  IDENTICAL
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` still ships no bundle; no `build.bat`, no
`LOADER.BIN`, no disk image (all out of scope). Probe binaries are gitignored.

25.3 operator-runtime-smoke: **PASSED — Jay, `poke`, RGB, 4:3 (endpoints only, three stills;
no motion under gate).** Jay: *"rooms look fine."* Captures now live in
`C:\karateka-capture\agi_captures\` — see §3.8.

### 6 — Reactive deviations and route accounting

- ★★★ **Trigger 1 FIRED and is reported prominently, as the dispatch required.** The `mul` is
  **11 cycles, 8%** of the original call. §4's ordering put it first; the measurement puts it
  third, behind two blocks that turned out to be **invariant work and unused work** rather than
  expensive work. **Part B was reordered on the measurement and this is the deviation.**
- **Triggers 2, 3 did NOT fire** — AC-3 is 45/45 and AC-6's count is identical to the unit.
- **Trigger 4 did NOT fire** — median 8.909 s, nowhere near ~2 s.
- **Trigger 5 did not arise** — candidate 4 was not attempted (§3.5), so **`S` was never
  borrowed** and POP's `char_draw.s:512` warning did not need to be paid.
- ★★ **Deviation, self-reported: my T-P0-012 summary over-claimed** and this dispatch inherited it
  as its premise. §1 and §3.1 correct it. The underlying flatness finding is unaffected.
- **ROUTE ACCOUNTING.** The dispatch's Part A → Part B order was followed and Part A gated Part B
  in fact, not just in form — it changed which candidate was implemented. ★ **What I did NOT do:**
  candidates 3 and 4 (wide compares, `puls` as a wide load), and no `S` borrowing. ★★ **One thing
  not asked for:** three per-path counters and an exhaustive equivalence check. The first told me
  which path to optimise; the second is what lets §3.4 say *provably* identical rather than
  *believed* identical.

### 7 — Uncertainty flags

- ★★★ **8.909 s is still far too slow, and this task does not change that conclusion.** 19.7% is
  real and it moves 33 pictures under the 10-second line, but the design budget is not in this
  neighbourhood. **The remaining cost is now genuinely distributed** — see §8.
- ★★ **The 112-cycle non-`fill_check` remainder is attributed only by regression**, with a
  negative coefficient on one term. Its total is trustworthy; its internal split is not. **A
  direct ablation of the fill loop's caller-side work is the honest next measurement**, and I did
  not do it.
- ★ **The bench pins one state** (FC_VISUAL, in-bounds, fillable). The FC_PRIORITY path (6.4%) and
  the out-of-bounds early return (23.2%) were **not separately benchmarked** after the change;
  their costs are inferred from the instruction stream, not measured.
- ★ **45 pictures of 3 games is still not the corpus** (597 offline), and resources > 1,280 B are
  still excluded by the probe window.
- ★ **A 128 KB build has not been run** (§2K); everything here is 512 KB.
- ★ **Tier-2 evidence (a running original) was not consulted.**

### 8 — Follow-up candidates
1. ★★★ **Hoist the row address out of the span, which is now the largest remaining block.**
   `fill_check` is 86 cycles: bounds 28, row address 20, plane test 14, call/return 13, dispatch
   ~11. Along `ff_right`, **y is invariant and x increments by one**, so the address could be a
   pointer the caller advances — removing the `mul` *and* most of the bounds test. ★★ This is
   §4's candidate 1 and 2 combined, and it is now correctly first **because the measurement says
   so**, not because it was the visible suspect.
2. ★★ **Ablate the fill loop's caller-side work directly** (§7) — ~75 cycles/check is the second
   largest single item in the whole render and is currently regression-attributed only.
3. ★ **Reconsider wide compares only after 1 and 2.** The plane test is 14 cycles of 86; there is
   little left for a wide scan to win, and it costs the `S` risk.
4. **Widen the gate beyond 45 pictures / 3 games**, and raise the probe's resource window.
5. ★ **A `reports/` encoding check** — carried forward from T-P0-011 §3.12, still not built.

### 9 — User interaction during task
Two, both at the gate:
1. Jay observed the three rooms: *"rooms look fine."* — **AC-9 and 25.3 PASS.**
2. Jay asked for the captures to live in a dedicated folder. `C:\karateka-capturegi_captures\`
   now holds all ten AGI captures from P3.2 onward, and the capture step is a **tracked script**
   rather than ad-hoc shell (§3.8).

### 10 — Candidate(s) captured this task
Two, both to `seeds/AGI/live/` (§2C — new rows, nothing existing read or edited):

1. **`a-ratio-is-not-a-cost`** — ★★★ the important one, and it is about my own error. Total ÷
   count produces a figure whose **units read as a per-unit cost** and whose value is not one;
   the phrase survived into the next dispatch's premise and aimed it at an 11-cycle instruction.
   ★ Also records that a **hand count from the listing** would have caught it in one command.
2. **`exhaustive-enumeration-turns-provably-identical-into-a-fact`** — the state space of the
   hoisted decision is 262,144 combinations, which is nothing. ★ When a refactor's equivalence
   rests on a small finite space, **enumerate it instead of arguing it** — the argument is what
   review cannot check.

### 11 — Commit
`52fd98c` — P3.4 the boundary test: decomposed and optimised
Pool `b8fb79d` — the two candidate rows (§10)
(pushed to origin/wip before this report; `52fd98c` carries the report itself)
