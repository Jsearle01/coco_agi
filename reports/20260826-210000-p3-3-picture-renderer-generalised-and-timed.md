## Form B Report — P3.3 — the picture renderer, generalised and timed on hardware
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-26 (dispatch T-P0-012 receipt; HEAD at receipt `ff20574`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip    ff205740bd0629d722c684af5f6e161e79cada8f  tracked-dirty 0
POP3_port        wip    430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip    78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
                        (harness/smoke/last-run.log — the same pre-existing file T-P0-011 recorded)
lwasm from lwtools 4.24        MAME 0.281 (mame0281)

[hal-sync] coco_agi       OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
[hal-sync] POP3_port      OK -- aligned with karateka_coco3, coco_agi (11 files compared)
[hal-sync] karateka_coco3 OK -- aligned with POP3_port, coco_agi (11 files compared)

[reg-discipline] coco_agi       0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
[reg-discipline] POP3_port     59 register access(es) in 7 file(s) over 14 register(s).
[reg-discipline] karateka_coco3 8 register access(es) in 2 file(s) over 4 register(s).
```

**★★ §2T applied — and it applies to the BUILD baseline, which this task does not need.**
POP `430a91c` and Karateka `78c8c27` are **unchanged from T-P0-011 §0**, both clean apart from
Karateka's pre-existing `last-run.log`, and lwasm is unchanged at 4.24. ★ **But no shared file is
touched by this task at all** — everything lands in `src/harness/` and `harness/tools/` — so
there is no artifact-moving change for a before/after comparison to be about. The two figures
AC-1 and AC-2 actually want (`reg_discipline` counts and `hal_sync_check`) are **source
measurements that take seconds**, so they were **run fresh rather than cited**: cheaper than a
citation and strictly stronger. §2T's citation path is for the expensive sibling *builds*, and
those are not in scope here.

★ **AC-1's `coco_agi` 0 is structural, not incidental:** `src/engine/**` holds no `.s` files at
all and the renderer lives in `src/harness/`, which the scan excludes by §2N.

**★★ MAME cycle measurement — the mechanism, enumerated before it was chosen (§2A.5).**
`-showusage` and a Lua probe of the `mc6809e` device were both run. Result:

```
cpu.total_cycles / totalcycles / cycles_running / clock   -> all nil in 0.281's Lua binding
manager.machine.time                                      -> attotime, :as_double() available
screen.refresh_attoseconds = 16688153334513408            -> 16.688 ms, i.e. 59.92 Hz
manager.machine.debugger                                  -> nil (no -debug in this session)
addr_space:install_write_tap(lo, hi, name, cb)            -> present and working
```

**Chosen: a WRITE TAP on a phase byte, reading `manager.machine.time` in the callback.** The
callback fires at the instant of the store, so **resolution is one instruction**, on exact
emulated time. Rejected alternatives and why: a **frame counter** is 16.688 ms granular and
cannot decompose a render; **host wall-clock** measures the host, not the 6809, and is not
reproducible; **`-seconds_to_run`** bounds a session and does not time a region within it.
★ Trigger 4 (">60 lines of Lua") **did not fire** — the tap is 3 lines.

---

### 1 — Summary

**Part A is done: the renderer is general.** 45 PICTUREs across **three games** render on a real
CoCo3 with **both planes byte-identical to the pinned oracle, per picture, 45/45** — including
KQ1 #80, so T-P0-011's result is reproduced rather than assumed. Two PICTURE opcodes were
implemented to get there (`y_corner`, `abs_line`); the two pattern opcodes remain unimplemented
and **halt loudly**, and no picture in the set reaches them.

★★★ **Part B is the point, and the number is bad.** On hardware, at a measured 1.7898 MHz:

> **A room takes a MEDIAN of 11.1 seconds to draw, and the worst of 45 takes 21.0.**
> **All 45 exceed 3 s. 37 of 45 exceed 10 s.**
> **94.4% of that is the flood fill.**

★★ **Consultation trigger 2 fired** (median > ~3 s, worst > ~10 s) and, as the dispatch directs,
this is **reported and measurement continued rather than optimised around**. **M-02's time
question is now answered and the answer is a design constraint, not a tuning problem.**

★★★ **AC-7 settles §6.3's ranking, and §6.3 is RIGHT.** The unit of cost is not the pixel — it is
the **boundary test**. `fill_check` costs **253 cycles, and that figure is flat to 1.12x across
all 45 pictures**, while cost-per-pixel-written varies 2.2x. **3.67 M boundary tests against 1.19 M
pixels written, 3.1 tests per pixel.** ★ A picture can write the same number of pixels and cost
twice as much because its regions are shaped so the fill tests more candidates.

★ **AC-6 closes cheaply:** the measured seed-stack peak is **74 bytes (37 entries)** against the
offline prediction of 204 B / 102 entries, on a 1,024-byte stack — **13.8x headroom**. AD-33's
memory answer holds; nothing here disturbs it.

**Three defects were found and fixed on the way, none of them in the picture format** — two were
8-bit signed tests on values whose real range is 0..167, and one was mine, introduced while
fixing the harness. §3.4–§3.6.

### 2 — Files modified
- `src/harness/pic_probe.s` — `y_corner` (F4) and `abs_line` (F6) implemented; status block moved
  out of the PIC_DATA window into low RAM; picture-state reset per render; phase markers and the
  clock calibration loop; `-DPIC_NOFILL`, `-DPIC_NOCOUNT`, per-picture-armed `-DPIC_FAULT`; the
  re-run gate (`GO`); five unused HAL includes dropped.
- `src/harness/pic_draw.s` — **two defect fixes** (§3.4, §3.5), both 8-bit signed tests.
- `src/harness/pic_fill.s` — seed-stack high-water mark, span counter, 32-bit `fill_check`
  counter, all behind `-DPIC_NOCOUNT`.
- `harness/tools/pic_sweep.lua` — NEW. One-session sweep driver, write-tap timing, per-picture
  fault arming, frame-counted snapshots.
- `harness/tools/picset.py` — NEW. Fill-weighted set selection, extraction, opcode census.
- `harness/tools/picgate.py` — NEW. AC-3, **per-picture** pass/fail against the oracle.
- `harness/tools/pictiming.py` — NEW. AC-5/6/7 analysis, clock guard, cost-driver test.
- `harness/tools/pic_probe.lua` — status addresses updated (they had gone stale, §3.8).
- `mame-idioms-coco3-port.md` — idioms **19l** (write-tap timing) and **19m** (guest-owned
  restart).

`src/engine/**` untouched — **0 `.s` files**. No game data, resource bytes, renderings or
screenshots committed (§2P); `build/picset/` and `build/sweep*/` are gitignored.

### 3 — Reasoning

**3.1 ★★ The set is FILL-WEIGHTED on purpose, because of L-38 and my own row-0 case.**
T-P0-011 had a black canvas where no fill could succeed, and row 0 agreed with the oracle
throughout — two buffers matching for different reasons. **A line-heavy, fill-light set could
pass with the fill subsystem broken.** `picset.py` therefore sorts candidates by fill count and
interleaves across games: **29 of 45 pictures have >= 10 fills, 577 fills total, median 12.** ★
Asked the L-38 question directly — *what would this comparison look like if the fill were
absent?* — the `-DPIC_NOFILL` build answers it in numbers: **94.4% of the render time
disappears**, and the planes are nothing like the oracle's. The set cannot pass with a broken
fill.

**3.2 ★★★ THE MEASUREMENT MECHANISM, AND WHY THE ALTERNATIVES WERE REJECTED (AC-5).**
A **MAME write tap** on a phase byte, reading `manager.machine.time` in the callback: the tap
fires at the instant of the store, so **resolution is one instruction** on exact emulated time.
Enumerated first (§2A.5) — `cpu.total_cycles`, `totalcycles`, `cycles_running` and `clock` all
return **nil** on `mc6809e` in 0.281's Lua binding, and `machine.debugger` is nil without
`-debug`. A **frame counter** is 16.688 ms granular and cannot decompose a render; **host
wall-clock** measures the host; **`-seconds_to_run`** bounds a session, not a region.

★★ **The clock is MEASURED, not assumed.** Every run times 20,000 iterations of an 8-cycle loop:
**0.089401890 s over 160,009 cycles -> 1.7898 MHz**, the CoCo3 fast rate, confirming
`HAL_gfx_set_mode`'s `$FFD9` write. Had it come out near 0.8949 every figure would be 2x wrong.
★ **Identical to nine decimal places across all 45 runs** — emulated time is deterministic, which
is how L-33's "two runs is not a sample" is answerable here: **repetition adds no information, so
the run count is stated (1 per build) rather than inflated.**

★ **The harness measures its own overhead.** The counters cost **14.0% median** (12.6–14.5%), so
**counts and timings are taken from SEPARATE BUILDS** — `-DPIC_NOCOUNT` for every timing figure
in this report, the counted build for structure. An instrument that shifts its subject by 14%
must not also be the thing reporting the measurement.

**3.3 ★★ Fill cost is obtained BY DIFFERENCE, and the difference is clean.**
There is no cycle counter on a 6809 and per-call instrumentation perturbs the hottest path, so
`-DPIC_NOFILL` suppresses the `flood_fill` call alone. Both builds walk the same resource, take
the same branches and count the same invocations; line geometry does not depend on the canvas, so
**the line/pen half is identical between them and the delta is the fill and nothing else.** ★ The
no-fill build renders a deliberately WRONG picture and is **never gated** — `picgate.py` is not
run on it.

**3.4 ★★★ DEFECT 1 — an 8-bit SIGNED delta, unreachable until this task.**
`draw_line` computed deltas as `lda x2 : suba x1 : bpl positive : nega`. AGI coordinates run to
159 (x) and 167 (y), so **any delta of 128..167 sets bit 7 and is read as negative.** The oracle
uses `int deltaX = x2 - x1` in int16 [picture.cpp `draw_Line` @ `9d9b9e9`] and never has the
problem. ★★ **T-P0-011 gated this exact routine byte-identically and the diagonal branch ran 130
times during that gate** — it passed because that picture used only `rel_line`, whose packed
nibble deltas cannot exceed +/-7, and `x_corner`, whose segments are axis-aligned and never enter
the branch. **The line was covered; the value range was not.** `abs_line` arrived with this task
and the first long diagonal, `(1,156)->(156,1)`, computed dx = +155 = `$9B` and read it as -101.

**3.5 ★★★ DEFECT 2 — the SAME CLASS, thirty lines away, and I should have swept for it.**
The loop terminator was `dec dl_i : beq end : lda dl_i : bpl loop`. `dl_i` holds up to 167, so
**the `bpl` was a 127-pixel line-length limit** — any longer line stopped after one pixel. It
reads as a defensive underflow guard, which is why it survived review; the oracle is
`i--; while (i > 0)` with `i` an int, so `dec`/`bne` is the faithful form.
★★ **I fixed defect 1, re-ran the full 45-picture gate — fifteen minutes — and still had 3
failures.** A one-line grep for signed branch mnemonics at the moment defect 1 was understood
would have found this immediately. **The grep was run afterwards and came back clean** across
`pic_probe.s`, `pic_draw.s` and `pic_fill.s`; that bounds the risk within those three files and
nowhere else.

**3.6 ★★★ DEFECT 3 — SELF-INFLICTED: my harness fix removed an accidental safety net.**
The driver restarted the probe by writing PC from a frame notifier. **That does not reliably land
on the entry point:** MAME reported **PC=$0839**, mid-instruction inside the two bytes of
`bra probe_halt`, and execution resumed **past the prologue**. The counter-reset block never ran,
so counters **accumulated across pictures** — KQ1-053 reported 72 fills and 50,756 pixels against
true figures of 64 and 25,677, the difference being exactly the previous picture's 8 and 25,079.
★★ **Five of the six counters looked entirely plausible. The sixth reported a 42,241-byte peak on
a 1,024-byte stack that halts on overflow and had not halted** — arithmetically impossible, and
the only reason this was caught before the timing table went into a report.
★ Fixed by making the probe **restart itself** from a `GO` flag. ★★★ **And that fix caused a
second defect:** re-poking the binary each iteration had also been silently re-initialising every
`fcb` datum, so dropping it exposed **picture state that was never reset** — 11 of 45 pictures
failed, 9 on priority only, because most pictures set the pen immediately and only the unusual
ones inherited. Reading the reference then showed a *third*, older instance in the same lines:
`_scrColor` initialises to **15**, not 0 [picture.cpp:387 @ `9d9b9e9`], and the probe had 0 —
latent for exactly the same reason. **probe_entry now resets pen state explicitly, every render.**

**3.7 ★★ How the two draw_line defects were LOCALISED — bisection over the INPUT, not the code.**
Reading the routine against the reference did not find them. What did: the failing resource was
**truncated at every opcode boundary** (125 variants for KQ3-062, 414 across three pictures), each
variant rendered **both on hardware and by `tools/picrender/`**, looking for the first truncation
at which they disagreed. That named **opcode index 116** and the opcode carried its operands —
`abs_line (1,156)->(156,1)`, a 155-pixel span — so the defect arrived as a concrete failing value
rather than a suspicious line. ★ All 125 variants ran in **one MAME session**.
★★ **§2O.1 is not bent by this.** `tools/picrender/` was used to *localise*, after confirming it
is **byte-identical to the ORACLE** on all three failing pictures; **the gate itself
(`picgate.py`) never imports it and compares only against the pinned oracle.** Bisecting against a
reference that has been checked against the oracle is not self-reference.

**3.8 Two harness defects fixed rather than left.** ★ `pic_probe.lua` still read the status block
at `$16F0` after it moved to `$0080` — it would have reported zeros as data; addresses updated.
★★ `emu.wait_next_frame()` **inside a frame notifier re-enters it**: the AC-9 capture ran
`finish()` four times for one picture and wrote three identical screenshots. Only the byte-for-byte
equal PNG sizes gave it away. Snapshots are now taken by **counting frames in the notifier**.

**3.9 Authority tiers, per §2.1.** Every behavioural conclusion here rests on **ScummVM at the pin
`9d9b9e9`** (tier 3) — `draw_Line`'s clipping and int16 deltas, `draw_FillCheck`'s three cases,
`drawPicture`'s state initialisation, `getNextParamByte`'s rewind-on-terminator. ★ **All are
believed ORIGINAL rather than ScummVM normalisations**: they are load-bearing for rendering any
v2 picture correctly, and a normalisation would show as a systematic difference across the corpus
rather than as the exact byte-identity 45/45 observed. **I have not verified this against a
running original** (tier 2) — that is stated as a limit, not claimed as checked.
★ §2H's three checks on `draw_FillCheck`: (1) the **second mechanism** is
`draw_SetNibblePriority`/`nibbleMode` for AGI256 and the `skipOtherCoords` variants for v1 — our
target is v2, `nibbleMode` false, `skipOtherCoords` false; (2) the **caller** is `drawPicture`'s
opcode switch, which is what fixes those two flags; (3) grepped prior reports for the subsystem —
T-P0-011 §3 is the only other treatment and does not contradict this one.

**3.10 §2S — sibling claims and their ref.** POP `430a91c` and Karateka `78c8c27`, both on `wip`,
both measured **this task** by `hal_sync_check.py` and `reg_discipline.py` at those refs, scope
`<repo>/src` excluding `src/hal` and `src/harness`. No sibling file was modified.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] PASS.** `reg_discipline.py`: `coco_agi` **0**, POP **59**,
  Karateka **8** — all three run fresh this task (§C-13), matching the recorded figures. ★ The
  renderer stayed in `src/harness/`; `src/engine/**` holds 0 `.s` files.
- **AC-2 [class: byte-comparable] PASS.** `hal_sync_check.py` **OK in all three repos, each
  naming the other two.** Verbatim x3 in §5. ★ Dropping five HAL *includes* from a probe does not
  modify a shared file, and the check confirms it.
- **AC-3 [class: byte-comparable] ★★★ PASS — 45/45, per picture, both planes.** 45 pictures,
  **3 games** (KQ1 16, KQ2 15, KQ3 14), **including KQ1 #80**. Per-picture table verbatim in §5;
  every row prints its own verdict and the exit code is non-zero if any row fails.
- **AC-4 [class: byte-comparable] PASS.** All 10 implemented opcodes are **reached** by the set:
  `set_visual` 940, `dis_visual` 66, `set_pri` 543, `dis_pri` 181, `y_corner` 305, `x_corner` 415,
  `abs_line` 1358, `rel_line` 1687, `fill` 577, `end` 45. **NOT reached: `set_pattern` ($F9) and
  `pattern_brush` ($FA)** — they remain `0` in the dispatch table and **halt loudly** with the
  opcode in `bad_op`; a silent no-op is not on the table. ★ `picset.py` excluded any candidate
  using them, and **no picture in KQ1/KQ2/KQ3 with an oracle dump needed them**.
- **AC-5 [class: state-comparable] ★★★ PASS — and the result is a design constraint.**
  Mechanism and resolution in §3.2 (write tap on a phase byte, one-instruction resolution, exact
  emulated time; clock **measured** at 1.7898 MHz). Timings from the **`-DPIC_NOCOUNT`** build.
  **min 8.319 s / median 11.102 s / max 21.007 s**; in cycles **14.89 M / 19.87 M / 37.60 M**.
  Worst case **Kingquest2-095, 21.007 s**. **Fill vs line/pen: fill is 94.4%** of total across the
  set (most fill-dominated KQ2-095 at 99.0%, least KQ3-065 at 89.0%). Full table in §5.
  ★ **Run count: 1 per build** — emulated time is deterministic to 9 dp (§3.2), so repetition
  would add no information; this is stated rather than padded (L-33).
- **AC-6 [class: state-comparable] PASS.** Measured seed-stack peak **74 bytes = 37 entries**
  (Kingquest1-009); distribution min 4 / median 12 / max 74. **Offline predicted 204 B / 102
  entries** over 498 pictures. ★ **Measured is well UNDER the prediction, so the offline model is
  not contradicted** — but the two sets differ (45 vs 498 pictures), so this is *consistent with*
  the prediction, **not confirmation of it**. Provisioned 1,024 B = **13.8x headroom** at the
  measured max. Trigger 3 (>1 KB) did not fire.
- **AC-7 [class: state-comparable] ★★★ PASS — and it SUPPORTS §6.3.** For the worst case
  (KQ2-095): 26,880 pixels written, 1,075 spans pushed, 9 fill invocations, 37.60 M cycles.
  **The cost-driver test:** cycles per **pixel written** vary **2.2x** (686–1482) across the set;
  cycles per **`fill_check`** vary only **1.12x** (234–261, median **253**). **The flatter unit is
  the real one** — cost tracks **boundary tests**, not pixels. Set totals: **3,666,862
  `fill_check` calls against 1,188,430 pixels, 3.1 tests per pixel** (min 2.7, max 6.0).
  ★ **The nibble read-modify-write costs ZERO, structurally:** one AGI pixel is exactly one CoCo3
  byte with the colour in both nibbles, so `put_pixel` does a **plain `sta`** with nothing to read
  back. **This does not extend to anything drawn at full 320 resolution later.**
- **AC-8 [class: byte-comparable] ★★ PASS — and it LOCALISES.** `-DPIC_FAULT` armed for exactly
  **one** picture (`Kingquest3-030`) via a driver-written flag. Result: **44 PASS, 1 FAIL, and the
  failure is `Kingquest3-030`.** ★ Arming all 45 would have shown only that the gate can go red;
  arming one shows it names the right picture. `--expect-fail` exit 0.
- **AC-9 [class: eye-gated] ★★ PASS — Jay, `poke`, RGB, 4:3.** Jay: *"the renders look good."** **Three rooms**, not one: KQ1 #80, KQ2 #94, KQ3 #74, at
  `C:\karateka-capture\agi-p3.3-*-RGB-4x3.png` — **outside the repo** (§2P). ★ Per §3 I have not
  read or interpreted their pixels. **Launch path: `poke`, RGB, 4:3** (640x480, ratio verified from
  each PNG's IHDR). ★★ **Per idiom 19j a byte-identical buffer proves nothing about the screen** —
  AC-3 and AC-9 test different paths, and the two display defects of T-P0-011 both survived a
  byte-identical gate. ★ `poke` HIDES load/launch bugs; `live-disk` needs `LOADER.BIN`, out of
  scope.
- **AC-10 [class: suite] PASS.** Four candidates captured; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-1 / AC-2 (also in the C-13 block above) ===
[hal-sync] coco_agi       OK -- aligned with POP3_port, karateka_coco3 (11 files compared)
[hal-sync] POP3_port      OK -- aligned with karateka_coco3, coco_agi (11 files compared)
[hal-sync] karateka_coco3 OK -- aligned with POP3_port, coco_agi (11 files compared)
[reg-discipline] coco_agi        0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
[reg-discipline] POP3_port      59 register access(es) in 7 file(s) over 14 register(s).
[reg-discipline] karateka_coco3  8 register access(es) in 2 file(s) over 4 register(s).
```

```
=== AC-4 opcode census over the gated set (picset.py) ===
candidates with oracle dumps, implemented opcodes, and a resource that fits: 83
★ no picture used an unimplemented opcode
★ KQ1 #80 forced in (reproduces T-P0-011)
SELECTED 45 pictures across 3 games
  Kingquest1   16 pictures   fills min 2 / median 19 / max 26
  Kingquest2   15 pictures   fills min 3 / median 9 / max 19
  Kingquest3   14 pictures   fills min 5 / median 10 / max 23
  ★ fill counts across the set: min 2, median 12, max 26, total 577
  ★ 29 of 45 pictures have >= 10 fills -- a fill-light set could pass with the fill broken (L-38)
  opcodes exercised: abs_line=1358 disable_priority=181 disable_visual=66 end=45 fill=577
                     rel_line=1687 set_priority=543 set_visual=940 x_corner=415 y_corner=305
  ★ implemented but NOT reached by this set (AC-4): none
```

```
=== AC-3 THE GATE -- 45 pictures, 3 games, per picture (picgate.py) ===
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
=== AC-5 / AC-6 / AC-7 (pictiming.py; timings from -DPIC_NOCOUNT, counts from the counted build) ===
﻿====================================================================================================
CLOCK CALIBRATION (the guard, not a decoration)
  45 runs; calibration interval median 0.089401890 s over 160009 cycles
  -> effective CPU clock 1.7898 MHz
  -> CoCo3 fast is 1.7898 MHz, slow is 0.8949: ★ FAST, as HAL_gfx_set_mode's $FFD9 write intends
  spread across runs: min 0.089401890 max 0.089401890 (identical = emulated time is deterministic)

====================================================================================================
AC-5 / AC-7 -- PER-PICTURE COST ON HARDWARE
picture            render_s    Mcycles   fill_s   line_s   fills   spans   pixels peak_B
----------------------------------------------------------------------------------------------------
Kingquest1-080        9.810      17.56    9.590    0.220       8     357    25079     30
Kingquest1-053        9.847      17.62    9.075    0.772      64    1902    25677      8
Kingquest2-094       15.116      27.05   14.619    0.497      59    1349    27477     14
Kingquest3-074        9.960      17.83    9.178    0.782      72    1887    25960      8
Kingquest1-065       10.873      19.46   10.102    0.772      70    1829    27967     10
Kingquest2-014       12.407      22.21   11.802    0.605      29    1572    27709      8
Kingquest3-065        9.769      17.48    8.696    1.072      35    1675    11800     40
Kingquest1-022       10.986      19.66   10.327    0.660      40    1157    27775     22
Kingquest2-024       11.135      19.93   10.660    0.475      43    1281    27646     12
Kingquest3-076       11.325      20.27   10.717    0.609      36     945    28677     14
Kingquest1-045       11.022      19.73   10.337    0.685      39    1295    27898     12
Kingquest2-071        8.319      14.89    7.680    0.639      49    1009    21111      6
Kingquest3-073       10.322      18.47    9.781    0.541      23    1295    26198      4
Kingquest1-004       11.176      20.00   10.435    0.741      53    1566    26972     16
Kingquest2-011       11.036      19.75   10.468    0.568      43    1093    27836     14
Kingquest3-048       11.135      19.93   10.584    0.552      31     659    28120     12
Kingquest1-034       11.731      21.00   11.056    0.675      49    1263    27055     14
Kingquest2-104        9.918      17.75    9.308    0.610      76    1857    25438      6
Kingquest3-148       11.031      19.74   10.645    0.385      14     539    27429     10
Kingquest1-050       11.202      20.05   10.365    0.837      36    1483    28335     12
Kingquest2-080       13.284      23.78   12.643    0.641      23    1295    28085      8
Kingquest3-064       11.226      20.09   10.597    0.630      16     981    28052     10
Kingquest1-062       10.923      19.55   10.107    0.815      32    1684    24511     16
Kingquest2-072       11.498      20.58   10.795    0.704      47    1301    28485      8
Kingquest3-030       11.255      20.14   10.656    0.599      28     680    28959     12
Kingquest1-009       10.999      19.69   10.373    0.626      40    1093    27776     74
Kingquest2-067       11.819      21.15   11.133    0.686      26    1385    28399      8
Kingquest3-078       11.190      20.03   10.454    0.737      60     718    28962      6
Kingquest1-058       10.958      19.61   10.206    0.752      37    1433    27812     12
Kingquest2-050       10.719      19.18   10.510    0.209      11     419    26146     32
Kingquest3-060       10.212      18.28    9.447    0.764      14    1301    24321      8
Kingquest1-043       11.503      20.59   10.750    0.752      70    1349    27668     10
Kingquest2-096       20.830      37.28   20.512    0.318      15    1230    26880      8
Kingquest3-062       11.265      20.16   10.613    0.652      28    1237    27889      8
Kingquest1-056        9.734      17.42    8.696    1.038      35    1675    11800     40
Kingquest2-097        9.315      16.67    8.774    0.542      64     983    24047     12
Kingquest3-075       11.310      20.24   10.710    0.600      33     782    28657     10
Kingquest1-055       10.444      18.69    9.729    0.715      49    1926    26182      8
Kingquest2-114       10.770      19.28   10.345    0.425      40     814    27756     52
Kingquest3-063       11.448      20.49   10.616    0.833      22    1460    28559      8
Kingquest1-060       10.810      19.35   10.025    0.784      32    1235    23235     16
Kingquest2-095       21.007      37.60   20.787    0.220       9    1075    26880     10
Kingquest3-036       11.536      20.65   10.813    0.722      30    1066    28710     14
Kingquest1-021       11.102      19.87   10.312    0.790      33    1249    28075     14
Kingquest2-073       11.336      20.29   10.811    0.525       6     534    28425     10
----------------------------------------------------------------------------------------------------
AC-5 SUMMARY over 45 pictures, 3 games:
  render time   min 8.319 s   median 11.102 s   max 21.007 s
  in cycles     min 14.89 M   median 19.87 M   max 37.60 M
  ★ WORST CASE: Kingquest2-095 at 21.007 s (37.60 M cycles), 9 fills, 1075 spans, 26880 px

  FILL vs LINE/PEN split (by difference, -DPIC_NOFILL):
    fill    min 7.680 s  median 10.454 s  max 20.787 s
    ★ fill is 94.4% of total render time across the set
    most fill-dominated: Kingquest2-095 at 99.0%
    least              : Kingquest3-065 at 89.0%

====================================================================================================
AC-6 -- SEED STACK PEAK, measured on hardware vs the offline prediction
  offline predicted: 102 entries = 204 bytes (over 498 pictures)
  measured here    : max 74 bytes = 37 entries, on Kingquest1-009
  distribution     : min 4  median 12  max 74 bytes
  stack provisioned: 1024 bytes = 512 entries ($0100-$04FF)
  headroom at the measured max: 13.8x
  ★ measured peak is within the prediction; the sets differ, so this is consistent-with, not confirmation-of

====================================================================================================
AC-7 -- WHERE THE TIME GOES (worst case: Kingquest2-095)
  pixels written to visual : 26880
  seed spans pushed        : 1075
  fill invocations         : 9
  cycles                   : 37.60 M
  cycles per visual pixel  : 1398.7
  cycles per span pushed   : 34974.6

  ★★ §6.3 predicts RUN-STRUCTURE work beats PER-PIXEL work.
     Two candidate cost drivers, tested against the same 45 renders:
       per PIXEL WRITTEN : min 686 (Kingquest1-053)  median 714  max 1482 (Kingquest3-065)  spread 2.2x
       per FILL_CHECK    : min 234 (Kingquest2-095)  median 253  max 261 (Kingquest3-063)  spread 1.12x
       fill_check calls PER PIXEL: min 2.7  median 2.8  max 6.0
       set totals: 3666862 fill_check calls against 1188430 pixels written (3.1x)

     ★★★ VERDICT: the quantity with the FLATTER cost per unit is the real driver.
        fill_check cost is flatter (1.12x) than per-pixel cost (2.2x).
        -> Cost tracks BOUNDARY TESTS, not pixels written. A picture can
           write the same number of pixels and cost twice as much because
           its regions are shaped so the fill tests more candidates.
        ★ SUPPORTS §6.3: run structure, not pixel volume.
```

```
=== instrumentation overhead, measured not assumed ===
INSTRUMENTATION OVERHEAD (counted build vs -DPIC_NOCOUNT), 45 pictures:
  median 14.03%   min 12.63%   max 14.47%
  counted median 12.923 s   nocount median 11.102 s
```

```
=== AC-8 the gate can still fail, AND it localises ===
assembled build/pic_fault.bin  2279 bytes  (-DPIC_FAULT)   armed on Kingquest3-030 only
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
★ FAILING PICTURES (named, not counted):
    Kingquest3-030 visual
★ --expect-fail: a FAIL here is the expected result.
picgate exit=0  (0 = the fault WAS caught)
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` still ships no bundle; there is no `build.bat`,
no `LOADER.BIN` and no disk image (all out of scope). Probe binaries are gitignored.

25.3 operator-runtime-smoke: **PASSED — Jay, `poke`, RGB, 4:3 (endpoints only, three stills;
no motion under gate).** Jay: *"the renders look good."* ★ **Launch path `poke`, monitor RGB, aspect 4:3.**
Three rooms at `C:\karateka-capture\agi-p3.3-{KQ1-080,KQ2-094,KQ3-074}-RGB-4x3.png`, outside the
repo (§2P), pixels not interpreted by Clyde (§3).

### 6 — Reactive deviations and route accounting

- ★★★ **Consultation trigger 2 FIRED and is reported here rather than acted on.** Median 11.1 s
  against the ~3 s threshold and worst 21.0 s against ~10 s. Per the dispatch — *"report and
  continue measuring; do not stop"* — measurement continued to completion and **nothing was
  optimised**. Optimising the fill is explicitly out of scope; §8 carries the leads.
- **Trigger 1 examined and NOT fired.** Pictures diverged, but a reference to bisect against
  existed throughout (`tools/picrender/`, confirmed oracle-identical on each failing picture), so
  by L-36 this is not that trigger. ★ Stated because T-P0-011's premature stop was exactly this
  rule misapplied in the other direction.
- **Triggers 3, 4, 5 did not fire.** Seed peak 74 B against the ~1 KB threshold; the timing tap is
  3 lines against the ~60-line threshold; **no PICTURE opcode appeared that `tools/picrender/`
  does not implement** — it rendered all 45 and matched the oracle on every one I asked it about.
- **Deviation:** five unused HAL modules were dropped from the probe's includes to reclaim code
  space (§2 files). This modifies no shared file and `hal_sync_check` confirms it.
- **Deviation:** the status block moved out of the PIC_DATA window into low RAM, and
  `pic_probe.lua`'s addresses were updated to match. Without the move the largest gated resource
  (1,254 B) would not have fit the 1,264-byte window with any margin.
- **ROUTE ACCOUNTING.** I proposed no route beyond the dispatch's two parts; both were done in
  order, Part A verified before Part B's timings were taken. ★ **What I did NOT do:** implement
  `set_pattern`/`pattern_brush` (unreached by the set, and out of scope), and **I did not
  optimise anything** — the fill's 94.4% is reported as a finding.
  ★★ **One thing I did that the dispatch did not ask for:** three extra assemble-time switches
  (`-DPIC_NOFILL`, `-DPIC_NOCOUNT`, per-picture `-DPIC_FAULT` arming). The first two are what make
  AC-5 and AC-7 honest rather than approximate; the third is what makes AC-8 a localisation test.

### 7 — Uncertainty flags

- ★★★ **11.1 s median is measured; what it MEANS for the design is not settled here.** The figure
  is a picture drawn from a resource already in RAM. It excludes loading the resource from disk,
  and it is a one-off cost per room rather than per frame — but **§6.2's budget and P3b's poke
  milestone both assumed something far smaller**, and that is the Orchestrator's to fold.
- ★★ **The 253-cycle `fill_check` is the actionable number and I have not decomposed it further.**
  It recomputes a `mul`-based address on every call and is invoked 3.1 times per pixel. Whether
  the win is caching the address, hoisting the bounds test, or restructuring the scan is
  **unmeasured** — a lead, not a finding (§8).
- ★ **45 pictures of 3 games is not the corpus.** The offline renderer covers 597; this set was
  chosen fill-weighted and size-bounded (<= 1,280 B fits the probe window), so **larger resources
  are systematically absent** — 83 candidates qualified, 45 were taken.
- ★★ **The two pattern opcodes have never executed on hardware.** They halt loudly, which is
  honest, but AGI games outside KQ1–3 do use them.
- ★ **A 128 KB build has not been run** (§2K). 512 KB is the target and everything here is 512 KB;
  when a 128 KB build happens it is reported FIRST, per the rule.
- ★ **Priority-plane behaviour is verified only where the gated pictures exercise it.** 45/45 both
  planes is strong, but `draw_FillCheck`'s `priOn && !scrOn && priColor == 4` corner — which
  returns false and fills nothing — is reachable in principle and I did not confirm any picture
  in the set reaches it.
- ★ **Tier-2 evidence (a running original) was not consulted** for any conclusion in §3.9.

### 8 — Follow-up candidates
1. ★★★ **Decide what to do about 11.1 s.** This is the Orchestrator's call, not an at-site fix.
   The measurement says the target is `fill_check` (253 cycles x 3.1 per pixel = ~94% of a room),
   so the leads are: cache the row address across a scanline instead of recomputing `y*160+x`;
   hoist the bounds test out of the inner scan; test the visual plane directly rather than through
   the general three-case check when only one plane is enabled.
2. ★★ **Widen the gate beyond 45/3 games**, and raise the probe's resource window so the 38
   excluded oversized pictures can be gated.
3. **Implement `set_pattern` and `pattern_brush`**; they halt today and are unreached by KQ1–3.
4. ★ **An owner-row ratchet for registers** (§2N.1) — still pending first engine source, and this
   task kept `src/engine/**` empty, so it is still not due.
5. ★ **A `reports/` encoding check** — carried forward from T-P0-011 §3.12 and still not built.

### 9 — User interaction during task
One, at the gate: Jay observed the three rooms and reported *"the renders look good."* — AC-9
and 25.3 PASS. ★ No correction was needed this time, which is worth noting only because the two
preceding captures in T-P0-011 both were: the display path had two defects the byte-identical
gate could not see (idiom 19j), and this is the first eye-gate submitted with the monitor mode
and aspect ratio asserted by the harness rather than inherited from MAME's defaults.

### 10 — Candidate(s) captured this task
Four, all to `seeds/AGI/live/` (§2C — new rows, nothing existing read or edited):

1. **`an-arithmetically-impossible-number-is-the-cheapest-defect-detector`** — ★★★ the strongest
   of the four. Five of six counters looked like data; the sixth reported 42,241 bytes on a
   1,024-byte stack and that is the only reason the corruption was caught. **Choose some
   instrumentation for what it CANNOT say.**
2. **`a-fix-can-remove-an-accidental-safety-net`** — the GO fix silently dropped a per-picture
   re-poke that had been re-initialising all `fcb` data. ★ Also records that the failure
   distribution (9 of 11 priority-only) was correlated with the cause and not the cause.
3. **`line-coverage-is-not-value-coverage`** — the diagonal branch ran 130 times inside a passing
   byte-identical gate and still hid a signed-overflow defect, because no operand exceeded 7.
4. **`one-instance-of-a-defect-class-means-sweep-for-the-rest`** — ★ `initiator: executor`, and
   the one that cost real time: fixing defect 1 and re-running burned a full 15-minute
   verification cycle that a one-line grep would have saved.

### 11 — Commit
`db6e96f` — P3.3 picture renderer: generalised and timed on hardware
Pool `7acf484` — the four candidate rows (§10)
(pushed to origin/wip before this report; `db6e96f` carries the report itself)
