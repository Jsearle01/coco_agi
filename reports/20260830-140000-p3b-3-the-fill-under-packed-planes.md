## Form B Report — P3b.3 — the fill under packed planes
**Class:** build. wip. ★★★★ **AC-2 and AC-3 both PASS. Packing costs back 1.0% of P3.3's gain.
No trigger fired.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `7687f55`, wip). git status clean at receipt.

---

### §5 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===        7687f55  wip   (clean)

=== siblings (§2T: cite P3b.2 §0) ===
POP3_port          104b197 wip  tracked-modified=0
karateka_coco3     29f8f0a wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)

=== reg_discipline ===
  src/engine/mmu_phase.s                       5  $FFA5 $FFA6

=== pic_core.s [AD-80] ===
★ pic_probe.bin BYTE-IDENTICAL
```

**The five gates:** renderer **45 PASS / 0 FAIL**, resources **1,264** across 10 sweeps,
VM **nine titles PASS**, cels **6,782/6,782**, compositing **20/20 identical**.

★★★★ **THE PHASE ARITHMETIC, BOTH OPTIONS, BEFORE CHOOSING:**

| option | visual | priority | total | vs 65,280 |
|---|---|---|---|---|
| flat / flat | 26,880 | 26,880 | 72,826 | over by 7,546 |
| **(b) priority packed only** | 26,880 | **13,440** | **59,386** | ✓ **fits, 5,894 spare** |
| (a) both packed | 13,440 | 13,440 | 45,946 | fits — **but see §3.1** |

**No contradiction found. Proceeded.**

---

### 1 — Summary

★★★★ **The picture-draw phase fits, the gate is 45/45, and every counter is unchanged to the
unit.** Final figure, from the probe's own armed assertion: **59,706 against 65,280, spare
5,574.**

★★★★ **AC-5 — packing costs back 1.0% of P3.3's gain.** Median **2.746 → 2.832 s (+3.1%)**;
P3.3's gain was 8.354 s, and 0.086 s of it comes back. ★★ **Trigger 2's threshold was a median
above ~4.5 s. Not close.**

★★★ **§4's option (a) does not exist.** The visual plane is **not "unpacked" — it IS the
framebuffer**: mode 2 is 4 bpp and AGI is 160 wide against the CoCo3's 320, so one AGI pixel is
exactly one byte and 160 B/row is mode 2's stride. **"Packing" it means 80 B/row = 160 CoCo3
pixels — a horizontal resolution halving.** So (b) was never a preference; it was the only
option. ★ **Third false premise in three tasks** [L-65, after X-61 and X-62].

★★★★ **And the Orchestrator's hypothesis about (b) is CORRECT, with numbers.** `fc_pbase`
selects the test plane **once per span**, so under (b) the **FC_VISUAL byte-pointer walk (70.3%
of calls) is untouched byte for byte**; only the 6.4% priority walk becomes a nibble walk, in
its own loop. ★★ **Pictures with zero priority fills measure −0.4% to −1.0% — unchanged or
marginally faster.**

★★ **An eighth packing site, and a ninth thing that is not a site at all:** `fill_check`'s seed
test (§3.3), and the discovery that a `-DPIC_PRESENT` build's framebuffer dumps are meaningless
(§3.5) — a new idiom, **19j-bis**.

---

### 2 — Files modified

- `src/harness/pic_fill.s` — the packed-priority span walk (`ffp_*`), `fill_check`'s packed seed
  test, the refusal removed.
- `src/harness/pic_probe.s` — `PIC_DATA` relocated in the packed build.
- `src/engine/memmap.inc` — ★★ code/reserved boundary `$5000 → $5100` (§3.4).
- `harness/tools/pic_sweep.lua` — `PIC_DATA` follows the build.
- `mame-idioms-coco3-port.md` — **new idiom 19j-bis** (§3.5).

★★ **`pic_probe.bin` unpacked verified BYTE-IDENTICAL** after every change; `comp_probe.bin` and
`vm_probe.bin` untouched. The five unpacked gates cannot have moved.

---

### 3 — Reasoning

#### 3.1 Why option (a) is not an option

`pic_probe.s` states it: *"Mode 2 is 4bpp… ONE AGI pixel is TWO CoCo3 pixels — exactly one byte,
with the colour in BOTH nibbles. 160 AGI px/row × 1 B = 160 B/row, which is mode 2's stride
exactly. The nibble duplication IS the pixel doubling."*

★★★ So the visual plane is already at the display mode's minimum. Halving it halves the
horizontal resolution — a §3.3 design change, not a packing. **(a)'s 45,946 is arithmetically
real and physically unavailable.**

#### 3.2 Why (b) preserves the inner loop, and the number that forced the design

`fc_pbase` is set **once per fill**; the span walk reads through `ff_row`. Under (b) the visual
plane is still flat, so **FC_VISUAL's walk is unchanged**. Only FC_PRIORITY's changes.

★★★★ **The design was forced by one figure: a per-pixel `lda fc_case / cmpa / bne` on the SHARED
path is ~10 cycles × 1,188,430 written pixels ≈ 11.9M cycles ≈ 6.6 s** — worse than the entire
pre-P3.3 render. So the branch is taken **once per span** and the priority case gets its own
loop. ★★ The duplicate costs ~450 bytes of code and ~0.5% of render time.

★★★★ **I nearly sized this wrong by a factor of 45** [L-66, new]. The corpus figures are
**3,666,862 boundary tests across ALL 45 pictures**; the baseline is a **2.746 s median for ONE
room**. Dividing the first by the second reads the extra cost as ~0.66 s *per room* when it is
0.66 s *across the corpus* — 14 ms per room. **Two numbers three lines apart in the same report,
in different units**, and the inflated reading looked like a finding rather than an error.

#### 3.3 The eighth site — `fill_check`'s seed test

★★★ T-P0-033 enumerated six sites and found a seventh (`pri_clear`) by the shape of its failure.
**The eighth is `fill_check`'s priority read**, called once per popped seed from `ff_pop_lp`
**before** any row base is formed and before the span walk sets its nibble selectors — so it
cannot use `fc_mask`/`fc_match` and computes its own address and nibble.

★ **It is missed by a span-walk-focused reading because it is not in the walk**: it is the gate
that decides whether a walk happens at all.

★★ One bug caught in my own edit before assembly: `mul` returns 16 bits and `y*80` reaches
13,360 at y=167, so `pshs d` / `addd ,s++` — saving only B loses the high byte.

#### 3.4 The map boundary moved, and it costs a reservation

The packed span walk made the P3b image **12,299 bytes against a 12,288 region — over by
eleven.** `MAP_CODE_END`/`MAP_RESERVED` moved `$5000 → $5100`: code 12,544 (245 spare),
**parser/sound reservation 4,096 → 3,840.**

★★ P6.1 §7.4 flagged that 4 KB as *"a residual, not a requirement… to be CHECKED against the
parser and sound when they exist"*, so spending 256 bytes is sanctioned — **but it shrinks a
reservation P6.1's AC-3 required, and that must not happen silently inside another task's diff.**
★ Both regions are in slot 2, so the phase total is unchanged and AC-2's figure does not move.

#### 3.5 ★★★ A new idiom: `-DPIC_PRESENT` invalidates the framebuffer dumps

Producing AC-9's captures, three different rooms — provably different (fills 33/6/30, spans
1249/534/1066, px 28075/28425/28710) — emitted **three byte-identical `.fb.bin` dumps**
(`010928b46bb6`). ★★★ `-DPIC_PRESENT` calls `HAL_gfx_swap`, which remaps the framebuffer window,
so `finish()`'s readback at CPU `$8000` reads the **back buffer** after the flip: the same
untouched page every time.

★★★★ **This is idiom 19j's converse and it was not written down.** 19j says a byte-identical
buffer proves nothing about the screen; **19j-bis says that once the screen path is engaged, the
buffer readback stops being valid.** The gate build owns the dumps; the present build owns the
PNGs; neither's output may cross that line. ★★ **The run log looks perfect** — three renders,
three snapshots, three differently-sized PNGs. Only the dump hashes disagree, and nothing
compares them unless you look. **Added to the idioms file.**

#### 3.6 §2H's three checks

1. **A second mechanism for a different object class?** ★★ **Yes — `fill_check` (§3.3).** The
   span walk and the seed test read the same plane by different routes.
2. **The calling routine.** `fill_check`'s caller is `ff_pop_lp`, which runs *before* `ff_row` is
   formed — that ordering is exactly why it needs its own address computation.
3. ★ **Grepped before citing.** P3.14's median/worst are reproduced by measurement below rather
   than quoted (§AC-5).

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★ **PASS.** §5 verbatim; §2T cited from P3b.2 §0.

- **AC-2 [class: byte-comparable]** ★★★★ **PASS — the probe's own armed assertion, not
  arithmetic.** `p3b_probe.s` builds clean under `-DPRI_PACKED` **with no bypass flag**, and
  still refuses unpacked (`DRAW PHASE DOES NOT FIT`).
  `26,880 vis + 13,440 pri + 12,299 code + 5,205 picture + 1,024 seed + 768 hw + 90 status`
  = ★★★ **59,706 against 65,280 — spare 5,574.**

- **AC-3 [class: byte-comparable]** ★★★★ **PASS — 45 PASS, 0 FAIL, both planes, packed build.**
  ★★ Guest priority bytes are **expanded** for comparison; the oracle's are never packed (§2O.1),
  so a packing bug cannot cancel a rendering bug.

- **AC-4 [class: state-comparable]** ★★★★ **PASS — every counter identical to the unit.**

  | counter | unpacked | packed |
  |---|---|---|
  | boundary tests | **3,666,862** | **3,666,862** |
  | pixels written | **1,188,430** | **1,188,430** |
  | spans | 54,918 | 54,918 |
  | fills | 1,669 | 1,669 |
  | seed-stack peak | **74 B** | **74 B** |
  | path_v / path_p | 612,650 / 236,140 | 612,650 / 236,140 |

  ★★ **Same pixels, same values** — and `path_p` unchanged confirms the same tests took the
  priority route.

- **AC-5 [class: state-comparable]** ★★★★ **PASS. Clock 1.789390 MHz, `-DPIC_NOCOUNT` builds
  (the separate-builds rule), 45 pictures.**

  | | median | mean | worst | total |
  |---|---|---|---|---|
  | **unpacked** | **2.746** | 2.784 | **4.357** | 125.29 s |
  | **packed** | **2.832** | 2.934 | 5.140 | 132.05 s |
  | delta | **+0.086 (+3.1%)** | +0.150 | +0.783 (+18.0%) | **+5.4%** |

  ★★★ **The unpacked run reproduces P3.14's cited table to the millisecond — median 2.746,
  worst 4.357** — which is the §2T citation check passing rather than being asserted.
  ★★★★ **P3.3's gain was 11.1 → 2.746 s = 8.354 s. Packing returns 0.086 s = 1.0% of it.**
  ★ Worst single picture: `Kingquest2-096` 4.357 → 5.140 (+18.0%).

- **AC-6 [class: state-comparable]** ★★★ **Option (b), and it was never a choice** — (a)
  requires halving horizontal resolution (§3.1). (b) fits at 59,706 with 5,894–5,574 spare and
  preserves the byte walk for 70.3% of calls (§3.2).

- **AC-7 [class: byte-comparable]** ★★★★ **PASS — re-proven ON THE PACKED BUILD** [L-62].
  `-DPRI_PACKED -DPIC_FAULT`, armed on `Kingquest2-073`:
  **44 PASS, 1 FAIL**, `DIFFERS 1 px, first (37,42)` — the injected offset — and the other 44
  still pass. ★★ **It localises; it does not merely go red.**

- **AC-8 [class: state-comparable]** ★★ **PARTIAL — the unit holds, the flatness degrades, and I
  will not name a mechanism.**
  - µs per boundary test: median **34.536 → 36.015 (+4.3%)**.
  - **Spread widened: max/min 1.59× → 1.89×; stdev/mean 9.7% → 12.6%.**
  - ★★★ **The regression is CONFINED as designed**: every picture with `path_p = 0` is
    **−0.4% to −1.0%** (unchanged or marginally faster); every regressing picture has priority
    fills.
  - ★★★★ **But the MAGNITUDE is not explained.** `path_p` does not predict it — `Kingquest2-096`
    has 8.0% priority tests and regresses 18.0% while `Kingquest3-065` has 68.4% and regresses
    23.3%. Span count does not either (µs/span ranges 148–699). **Two hypotheses tested and
    rejected; I am reporting the confinement and leaving the driver open** rather than adding a
    fourth wrong mechanism guess to this thread.

- **AC-9 [class: eye-gated]** ★★ **Three captures produced — "pending Jay". Launch path `poke`,
  monitor RGB** (`MONITOR TYPE -> RGB` logged).
  `build/snap_pk/png/coco3/0000.png` `f52910566dc139e8` — Kingquest1-021
  `build/snap_pk/png/coco3/0001.png` `f89a928f7d9b5ed1` — Kingquest2-073
  `build/snap_pk/png/coco3/0002.png` `38e21268c81e2759` — Kingquest3-036
  ★★★ **NOT compared byte-for-byte against P3.3's**, and the reason is §3.5: this build's
  framebuffer dumps are invalid, and no P3.3 capture of these three rooms was retained (§2P —
  frames are not committed). ★★ **The byte-identity that IS established is stronger and comes
  from the gate build**: all three are among AC-3's 45/45. ★ Per §3 I have not inspected the
  images; they are Jay's.

- **AC-10 [class: suite]** ★ **Two rows** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

```
★ AC-2: packed p3b builds clean, code 12299 bytes          [no bypass flag]
  26880 vis + 13440 pri(packed) + 12299 code + 5205 picture + 1024 seed + 768 hw + 90 status
        = 59706 against 65,280  ->  FITS, spare 5574
[unpacked] DRAW PHASE DOES NOT FIT
```

```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)        <- PACKED renderer gate
```

```
UNPACKED  checks 3666862   path_v 612650  path_p 236140  path_g 0
PACKED    checks 3666862   path_v 612650  path_p 236140  path_g 0
UNPACKED  fills 1669  spans 54918  peak 74 B  px 1188430
PACKED    fills 1669  spans 54918  peak 74 B  px 1188430
```

```
             median     mean    worst    total          [-DPIC_NOCOUNT, 1.789390 MHz]
UNPACKED      2.746    2.784    4.357   125.29
PACKED        2.832    2.934    5.140   132.05
delta median +0.086 s (+3.1%)   delta total +6.755 s (+5.4%)
largest single regression: Kingquest2-096  4.357 -> 5.140  (+18.0%)
```

```
us per boundary test:   UNPACKED   PACKED
  median                  34.536    36.015
  spread (max/min)          1.59x     1.89x
  stdev/mean                 9.7%     12.6%
zero-priority pictures:  Kingquest2-050 -1.0%  Kingquest3-148 -0.6%  Kingquest3-048 -0.4%
```

```
Kingquest2-073   3   844   DIFFERS 1 px, first (37,42)   identical ae94489a381e63d5   ★ FAIL
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)     <- PACKED + PIC_FAULT
★ --expect-fail: a FAIL here is the expected result.
```

```
byte-identical resources: 1264 across 10 (title, volume) sweeps -- all sweeps clean
TOTAL             6782    6782    6782       0        0      995
=== AC-2 SUMMARY === nine titles, all PASS
★ 20 frames: 20 identical, 0 divergent                       <- compositing, PACKED
★ pic_probe.bin BYTE-IDENTICAL                               <- unpacked, after every change
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; the shipped images are unchanged.

**25.3 operator-runtime-smoke:** **pending Jay** — AC-9, three captures, launch path **`poke`**,
monitor **RGB**. ★ Not a delivery gate (§2, §4).

---

### 6 — Reactive deviations and route accounting

1. ★★★ **Chose (b) and reported (a) as unavailable** rather than unranked — §3.1. §8's
   "Do NOT consult… which option if the arithmetic is clear" applies.
2. ★★ **Moved the map's code/reserved boundary** by 256 bytes (§3.4). Sanctioned by P6.1 §7.4,
   surfaced because it shrinks a reservation.
3. ★★ **Relocated `PIC_DATA`** in the packed renderer build, into space the packed plane vacated,
   with the Lua side guarded to match.
4. ★ **Added idiom 19j-bis** (§3.5), per §2A item 4.

**ROUTE ACCOUNTING.** ★★ **What I did NOT do:** did not optimise the fill beyond restoring what
packing cost (§12); did not touch the VM decomposition — AD-83's 57.9% and the 34.9%
unattributed are untouched and still queued; did not name a mechanism for AC-8's magnitude; did
not compare AC-9's captures byte-for-byte (§3.5 explains why that comparison is unavailable);
did not run the integrated P3b loop.

---

### 7 — Uncertainty flags

1. ★★★ **AC-8's regression magnitude is unexplained.** Confined to priority-fill pictures, but
   neither `path_p` nor span count predicts how much. **Reported open.**
2. ★★★ **AC-9's captures are not byte-compared to a baseline**, and §3.5 is why. The display path
   is verified only by Jay's eye this task — which is what 19j says is the *only* thing that
   verifies it.
3. ★★ **`ffp_setsel`/`ffp_toggle` are exercised only where the corpus exercises them.** 236,140
   priority tests across 45 pictures is real coverage, but the odd-leading/odd-trailing paths of
   `ff_store_pri` are not separately instrumented.
4. ★★ **The parser/sound reservation is now 3,840 B**, and P6.1 already called it a residual to
   be checked. **It has now been reduced once without the parser existing.**
5. ★ **The packed code region has 245 bytes spare.** The next addition to the renderer or fill
   moves the boundary again.
6. ★ **Pool push failed on auth — fifth consecutive task.** Fourteen rows local only.

---

### 8 — Follow-up candidates

1. ★★★★ **P3b resumes** — AC-5 says the machine can run this: packing costs 1.0% of P3.3's gain
   and the phase fits with 5,574 spare.
2. ★★★★ **The VM decomposition** — AD-83's 57.9% resource copy and the 34.9% unattributed, now
   unblocked.
3. ★★ **Explain AC-8's magnitude** — what drives the 10–23% spread on priority-fill pictures.
4. ★★ **Re-check the parser/sound reservation** against a real parser before it is reduced again.
5. ★ **`pic_draw.s`'s counters** remain the one unguarded set (T-P0-033 §6.4).
6. ★ **AD-77** remains open and out of scope.

---

### 9 — User interaction during task

`None.` ★ Jay's picture-draw-fit question was answered in the preceding note report
(`20260830-070000-note-does-picture-draw-fit-flat.md`, §9) and this dispatch supersedes it.

---

### 10 — Candidate(s) captured this task

Two rows in `seeds/AGI/live/`, committed locally. ★ **Push failed** — `Authentication failed`,
**fifth task running** — fire-and-forget per §2C, does not gate.

- `2026-08-30-per-unit-and-total-are-different-units-and-mixing-them-resizes-the-task.md`
- `2026-08-30-a-build-flag-that-changes-the-pipeline-can-invalidate-the-artifact-you-came-for.md`

---

### 11 — Commit

`74b54b8` (pushed to origin/wip)
