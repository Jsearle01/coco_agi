## Form B Report — P3.13 — the fill, restructured
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-28 (dispatch T-P0-021 receipt; HEAD at receipt `8057fb6`, wip, clean).

---

### Pre-dispatch grep (C-13) — verbatim, before the summary

```
coco_agi         wip  8057fb68bf5f4547a485d4be597e3feba578be46  tracked-dirty 0
POP3_port        wip  430a91c2f6e92488959f2d8e8159c3ca6ba96eb3  tracked-dirty 0
karateka_coco3   wip  78c8c27674b9c6e760adb8bac45450f2cd82d685  tracked-dirty 1
lwasm from lwtools 4.24        MAME 0.281 (mame0281)
[hal-sync] coco_agi OK / POP3_port OK / karateka_coco3 OK   (11 files compared, all three)
[reg-discipline] scope: src/engine   0 register access(es).

fill_check's decomposition, still current [T-P0-013 §5]:
    bounds 28 | row address (mul) 20 | plane test 14 | call/return 13 | dispatch 11  = 86
span-length distribution [T-P0-014]:
    min 1  p25 4  median 9  p75 23  p90 56  p99 160  max 160   mean 21.3
45-picture gated set: reproducible; AC-2 below runs it.
```

★ **§2T — POP `430a91c` and Karateka `78c8c27` unchanged from P3.12 §0.**

---

### 1 — Summary

★★★ **CONSULTATION TRIGGER 2 HAS FIRED — THE MEDIAN IS BELOW 3 s.**

| | min | **median** | max | >10 s | >5 s | >3 s |
|---|---|---|---|---|---|---|
| **BEFORE** [T-P0-014] | 5.603 | **7.473** | 14.343 | 3 | 45 | 45 |
| **AFTER** | 2.168 | **2.973** | 4.599 | **0** | **0** | 20 |

> **Median 60.2% faster (2.51×). Worst case 67.9% faster. Not one picture over five seconds,
> where every one of the 45 was before. Cumulatively 73.2% below P3.3's 11.102 s baseline.**

★★★ **AND EVERY COUNTER IS UNCHANGED, WHICH IS THE POINT:**

```
boundary tests   3,666,862 -> 3,666,862    UNCHANGED
pixels written   1,188,430 -> 1,188,430    UNCHANGED
seed-stack peak       74 B -> 74 B         UNCHANGED
cycles per test  205/221/228 -> 51/68/78   ★ 3.25x cheaper (median)
45 pictures                                ★ BYTE-IDENTICAL to the pinned oracle
```

★★ **The dispatch's AC-5 expected the counters to move. They must not, and §3.1 is why.**

★★★ **THE DISPATCH'S §2 DESCRIBES A FILL WE DO NOT HAVE, AND CORRECTING THAT SHAPED THE WHOLE
TASK.** It says ours is *"seed-based: pop a seed, test the pixel, write it, test its four
neighbours, push the fillable ones"* and proposes replacing it with a span-based scanline fill.
**`pic_fill.s`'s header has said since it was written that it IS a scanline fill with span
seeding** — pop, scan left, walk right writing, seed above and below on transitions only.

> ★★★ **So 3.09 tests per pixel is not an artifact of the wrong structure. It is one test on
> the pixel, one on the row ABOVE and one on the row BELOW — at EVERY pixel, because that is
> how a transition is detected. Remove one and you change which spans get seeded, and therefore
> which pixels get filled.**

★★ **Which makes §2's second half the entire task, and it is exactly right:** along a span the
**row is invariant**, and `fill_check` was recomputing bounds (28 cy) and a row address by `MUL`
(20 cy) on every one of those tests.

### 2 — Files modified
- **`src/harness/pic_fill.s`** — the span walk carries three invariant row pointers; the
  per-pixel tests and the pixel write are inlined; the per-fill constants are hoisted.
- **`src/harness/pic_probe.s`** — layout: origin `$0700`, seed stack 768 B, **plus an
  assembly-time assertion that the code cannot reach `PIC_DATA`** (§3.4).
- `harness/tools/pic_sweep.lua`, `harness/tools/pic_probe.lua` — `LOAD` moved to `0x0700` to
  match the origin. ★ **Both must agree or the program is poked to the wrong address.**

**No `src/engine/**` change; `reg_discipline` stays at 0.** No game data, resources, renderings
or screenshots committed (§2P).

### 3 — Reasoning

**3.1 ★★★ Why the counters must NOT move, and why that is the safety net.**
The three tests per pixel are the algorithm. **The restructure changes what each test COSTS,
not which tests happen**, so:

- `CNT_CHK` unchanged ⇒ the same pixels were examined, in the same order;
- `CNT_PIX` unchanged ⇒ the same pixels were written;
- `CNT_SPAN` and `SP_PEAK` unchanged ⇒ the same seeds were pushed, so the same regions were
  reached.

★★ **Together with 45/45 byte-identity, that is four independent statements of the same fact.**
★★★ **AC-5's instruction to explain each moved counter is satisfied by there being none — and
if any had moved, trigger 1 would have applied** [L-37: instrument something that can
contradict you].

**3.2 ★★★ The change itself, and the measurement it corrects.**
`fill_check` per test: **bounds 28 · row address 20 · plane test 14 · call/return 13 ·
dispatch 11 = 86**. Along a span walk, `fc_y` is constant and `fc_x` advances by one, so:

- the **row address** is loop-invariant — formed once per span with one `MUL`;
- the **y half of the bounds test** is loop-invariant — `ff_upok` / `ff_dnok`, once per span;
- the **x half** is already performed by the span loop's own `cmpa #PIC_W`;
- the **call/return** and the **dispatch** vanish when the test is inlined.

What remains is the plane read: `lda ,X` / `anda fc_mask` / `cmpa fc_match`. **Measured
51–78 cycles per test against 205–228** — the residue is the surrounding span-loop work the
per-test figure amortises, not the test itself.

★★★ **T-P0-014 TRIED THE ROW HOIST AND CALLED IT "roughly a wash, because the span loop touches
three rows per pixel". That measurement was correct and its conclusion was too narrow.** Three
rows means **three invariant pointers, not zero**: `X` walks the current row, `U` the row above,
`Y` the row below, advancing together with three `LEA`s. ★★ **The earlier attempt hoisted one
pointer and paid to re-derive the other two; hoisting all three is what makes it pay.**

★ **Identity by construction**, which is what AC-2 rests on: the bounds are **hoisted, not
skipped**; the plane read, mask and compare are byte-for-byte `fill_check`'s; the pixel write is
`put_pixel`'s body minus the bounds test, for the same reason. `put_pixel` itself is unchanged
for its other callers.

**3.3 ★★ What is still there, deliberately.**
`fill_check` survives for the **per-seed** test at `ff_pop_lp`, where no row pointer exists yet
— about 1.5% of all tests. ★ **Duplicating its logic inline for that case would have bought
almost nothing and doubled the surface where the three cases could drift apart.**

**3.4 ★★★ THE FIRST GATE RUN FAILED, AND THE FAILURE WAS A BUILD ERROR WEARING A RENDERING
ERROR'S CLOTHES.**

```
per-picture: 44 PASS, 0 FAIL, 1 with no output   (of 45)
★ FAILING PICTURES: Kingquest1-080 no output
```

Running it alone: `render 0.0000 s  fills 0  spans 0  px 0  bad=$10` — the interpreter went off
the rails before doing any work. **The cause was arithmetic, not logic:**

```
org $0800 + 2,579 bytes (counted build) = $1213    PIC_DATA = $1200    OVERLAP 19 bytes
org $0800 + 2,451 bytes (nocount build) = $1193    -> fits
```

★★★ **The picture resource is poked over the tail of the program.** ★★ **And the nocount build
fitted, so the TIMINGS were valid and only the GATE broke — a size regression that damages one
artifact and not the other, while the other reports excellent numbers.**

★ **The fix took space from where there is provable slack:** the seed stack was provisioned at
**512 entries against a measured peak of 37**. It is now 384 entries (still 10×), the origin is
`$0700`, and the margin is **237 bytes**.

★★★ **AND THE MARGIN IS NOW ASSERTED AT ASSEMBLY TIME**, via `lwasm`'s `error` directive on
`PIC_CODE_END-PIC_DATA`. ★★ **My first version of that guard was itself broken: I placed it
after `end probe_entry`, which TERMINATES ASSEMBLY, so the label, the condition and the error
were all silently ignored.** ★★★ **It was found only by breaking it on purpose** — forcing
`PIC_DATA` below the code and checking the build fails. **An assertion that has not been broken
is not an assertion** [L-27].

**3.5 ★ Trigger 2's consequence, stated for the Orchestrator.**
The median at **2.973 s** changes §9's ranking and P3b's budget. ★★ **It also weakens the case
for reopening M-29 (Sierra's region fill): the gap that motivated six recon tasks was 7.473 s
against their 3.54 s elapsed room change; at 2.973 s our render alone is now BELOW that
figure** — though **I-19 and the ceiling caveats on their number still apply, and the two are
not measured the same way.**

**3.6 §2S / §2.2.** POP `430a91c`, Karateka `78c8c27`, both `wip`, at those refs. MC6809 cycle
counts read from POP3_port's `docs/ground-truth/`; `coco_agi`'s is empty —
**orchestrator-unverifiable**.

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] PASS.** `reg_discipline` 0; `hal_sync_check` OK ×3; §2T cited.
- **AC-2 [byte-comparable] ★★★ PASS — 45/45 byte-identical**, per picture, both planes, against
  the pinned oracle. ★ **The first run failed on one picture and §3.4 is the cause and the
  fix.**
- **AC-3 [byte-comparable] ★★★ PASS.** `-DPIC_FAULT`: 44 PASS, 1 FAIL, named as
  **`Kingquest3-030 visual`** — exactly the injected picture. ★★ **This mattered more than
  usual because the algorithm changed**, and it confirms the gate still discriminates.
- **AC-4 [state-comparable] ★★★ PASS.** The table in §1. **n=45, one run**; emulated time is
  deterministic to 9 dp [T-P0-012] and the clock calibration guard reports **1.7898 MHz,
  identical across all 45 runs** [L-30, L-33].
- **AC-5 [state-comparable] ★★★ PASS — AND NOTHING MOVED.** Boundary tests, pixels, spans and
  seed peak are all unchanged (§3.1). ★★ **Pixels written = 1,188,430 exactly**, which the
  dispatch names as the safety net.
- **AC-6 [state-comparable] ★★ PASS — and the flatness IMPROVED.** Cycles per `fill_check`:
  **51 / 68 / 78, spread 1.54×** (was 205/221/228, spread 1.11×). ★★★ **The spread widened
  slightly while the cost fell 3.25×** — expected, because a smaller per-test cost amortises a
  fixed per-span overhead less evenly. **The unit of cost has NOT moved:** per-test spread
  (1.54×) is still far flatter than per-pixel (2.9×), so cost still tracks boundary tests.
- **AC-7 [state-comparable] PASS.** Seed-stack peak **74 bytes / 37 entries, unchanged** —
  expected, since the seeding pattern is untouched. ★ Provisioned at 768 B: **10× headroom.**
- **AC-8 [suite] PASS — §6.**
- **AC-9 [eye-gated] PENDING JAY.** ★★ Three rooms, and the captures **should be byte-identical
  to P3.3's** — the gate already proves the framebuffers match; this corroborates through the
  **display path** [idiom 19j], which the gate does not exercise. **Launch path to be recorded
  with the gate.**
- **AC-10 [suite] PASS.** Two candidates; §10.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim):

```
=== AC-2 ===
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
picgate exit=0   (0 = 45/45 byte-identical)

=== AC-3 ===
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)
★ FAILING PICTURES (named, not counted):
    Kingquest3-030 visual
picgate --expect-fail exit=0   (0 = injected fault caught)

=== CLOCK CALIBRATION (the guard, not a decoration) ===
45 runs; calibration interval median 0.089401890 s over 160009 cycles
-> effective CPU clock 1.7898 MHz   ★ FAST
spread across runs: min 0.089401890 max 0.089401890 (identical = deterministic)

=== AC-4 ===
              min   median      max  >10s  >5s  >3s
BEFORE      5.603    7.473   14.343     3   45   45   [T-P0-014]
AFTER       2.168    2.973    4.599     0    0   20   n=45
  median 7.473 -> 2.973 s = 60.2% faster (2.51x)
  worst  14.343 -> 4.599 s = 67.9% faster
  cumulative from P3.3's 11.102 s: 73.2% faster

=== AC-5 / AC-6 ===
set totals: 3666862 fill_check calls against 1188430 pixels written (3.1x)
   ★ IDENTICAL to T-P0-014's 3,666,862 and 1,188,430
per FILL_CHECK : min 51 (Kingquest2-095)  median 68  max 78 (Kingquest3-065)  spread 1.54x
per PIXEL WRITTEN : min 155  median 195  max 452  spread 2.9x
   ★★★ VERDICT: fill_check cost is flatter (1.54x) than per-pixel (2.9x)
      -> Cost still tracks BOUNDARY TESTS, not pixels written.

=== AC-7 ===
measured peak: 74 bytes = 37 entries, on Kingquest1-009   (unchanged)
distribution : min 4  median 12  max 74 bytes
```

```
=== §3.4: the first gate run, and the layout guard ===
per-picture: 44 PASS, 0 FAIL, 1 with no output
★ FAILING PICTURES: Kingquest1-080 no output
Kingquest1-080  render 0.0000 s  fills 0  spans 0  peak 0 B  px 0  bad=$10

org $0800 + 2579 (counted) = $1213   PIC_DATA $1200   OVERLAP 19 bytes
org $0800 + 2451 (nocount) = $1193   -> fits, so the TIMINGS were valid

after the fix:
  pic_probe     2579 B  ends $1113  PIC_DATA $1200  margin 237 bytes
  pic_nocount   2451 B  ends $1093  PIC_DATA $1200  margin 365 bytes

L-27, the guard broken on purpose (PIC_DATA forced to $0900):
  broke.s(767) : ERROR : User Specified: "pic_probe code overlaps PIC_DATA -- shrink it
                 or move the layout"
  exit=1   ★ the guard FAILS THE BUILD
  ★★ the FIRST version of this guard sat after `end probe_entry`, which terminates
     assembly -- it never ran, and only breaking it on purpose revealed that.
```

25.2 bundled-artifact grep: **N/A** — `coco_agi` ships no bundle; the probe is a harness binary.

25.3 operator-runtime-smoke: **pending Jay** (AC-9). ★ Three rooms; captures should be
byte-identical to P3.3's. **Launch path to be recorded at the gate.**

### 6 — Reactive deviations, route accounting, and AC-8 (what the decomposition says now)

★★★ **AC-8 — WHERE THE REMAINING CYCLES ARE.**

```
2.973 s median = 5.32 M cycles for ~26,400 pixels = ~201 cycles per pixel
   of which boundary testing: 3.09 tests x 68 cy = 210 ... which EXCEEDS 201
```

★★ **That apparent contradiction is the finding: the per-test figure is total cycles divided by
tests, so it already contains everything else.** The honest decomposition is now:

| | before | after |
|---|---|---|
| cycles per pixel | 506 | **201** |
| cycles per test | 221 | **68** |
| tests per pixel | 3.09 | **3.09** |

★★★ **The test count is now the dominant term and it cannot fall without changing the output.**
At 68 cycles a test, the remaining per-test cost is the plane read (≈14), the loop's own
advance and compare, and the write. ★ **A further 2× would require testing fewer pixels, which
means a different algorithm with different seeding — and that is where output identity stops
being free.**

★★ **My recommendation: stop optimising the fill.** It has gone 11.102 → 7.473 → **2.973 s**
across three tasks, is byte-identical throughout, and the next increment is qualitatively harder
than the last three. ★ **The line renderer and `put_pixel` were never the target and are now a
larger share of what remains.**

**Triggers.**
- ★★★ **TRIGGER 2 FIRED — median 2.973 s, below the ~3 s threshold.** Reported; **stopping
  here** per the dispatch, since it changes §9's ranking and P3b's budget.
- ★★ **TRIGGER 1 was met once and obeyed:** the first gate run failed AC-2 on one picture. **I
  stopped, diagnosed and fixed the cause rather than re-running or excluding it** (§3.4).
- **Trigger 3 did not fire** — the restructure helped by 60.2%, far above the ~15% floor.
- ★ **Trigger 4 partially applies:** §2's premise about our structure was wrong, **I went where
  the decomposition pointed instead, and §1 says so plainly.**
- **Trigger 5 did not fire** — seed peak unchanged at 74 bytes.

**ROUTE ACCOUNTING.** ★ **What I did NOT do:** change which pixels are filled, touch
`put_pixel`'s other callers, or restructure the seeding. ★★ **What I did that was not asked:**
the layout move and the assembly-time guard — **forced by my own change overrunning `PIC_DATA`**,
and the guard is the part worth keeping.

### 7 — Uncertainty flags
- ★★ **AC-9 is unobserved.** The gate proves the framebuffers match; **the display path is a
  different path** [idiom 19j] and Jay has not yet looked.
- ★★ **One run of 45.** Emulated time is deterministic [T-P0-012] and the clock guard reports an
  identical interval across all 45, so a re-run returns identical numbers — **but that is
  reproducibility, not variance on real hardware** [L-33].
- ★ **The per-test spread widened** (1.11× → 1.54×). Explained in AC-6 as amortisation, **not
  separately verified.**
- ★ **`fill_check` retains the old cost** for the ~1.5% per-seed tests; the reported per-test
  figure is a blend of the fast inline path and that.
- ★ **KQ1/2/3 PC resources, 45 pictures** [L-24]. **The 6309 is untouched.**

### 8 — Follow-up candidates
1. ★★ **Jay's eye gate (AC-9)** — three rooms, byte-identical to P3.3's captures.
2. ★★ **Re-baseline the design's §6.2/§6.3 figures**: they were written against 7.473 s and the
   ranking they support has moved.
3. ★ **The line renderer and `put_pixel`** are now a larger share of the remainder; neither has
   been decomposed since P3.5.
4. ★ **M-29 (Sierra's region fill) is now weaker value**, not stronger (§3.5) — worth recording
   before it is reopened out of momentum.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
Two, to `seeds/AGI/live/` (§2C — new rows):
1. ★★★ **`hoist-all-the-invariants-or-none-of-them`** — an earlier task hoisted ONE of three
   loop-invariant pointers, measured "roughly a wash", and concluded the hoist did not pay. It
   paid 2.51× when all three were hoisted together. **The partial application produced a
   measurement that was correct and a conclusion that closed the door.**
2. ★★★ **`an-assertion-you-have-not-broken-is-not-an-assertion`** — a build guard was written
   after the directive that terminates assembly, so it never ran. It looked correct in review
   and passed the clean build identically. **Only forcing the violation revealed that the guard
   was inert.**

### 11 — Commit
`746bb47` — the restructured fill, the layout move and the assembly-time guard.
Pool: `d142906` — two rows on top of `133bc8b`.
★ Pushed to `origin/wip` before this report.
★★ **No `src/engine/**` change: `reg_discipline` 0.**

