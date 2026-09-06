## Form B Report — P3b.20 — Fills must write the priority plane

**Class:** build. wip.

---

### §4 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===  wip   abcd6ee   (clean at start)
=== POP3_port === wip   104b197   untracked docs/ground-truth PDFs + nvram/ only
=== karateka_coco3 === wip 29f8f0a   M harness/smoke/last-run.log; untracked ground-truth PDFs

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
             src/engine/mmu_phase.s   8   $FFA5 $FFA6

gate   artifact                  shipped    fresh  verdict
pic    build/pic_probe.bin          2642     2642  identical
pic_nc build/pic_nc_unpacked.bin     2512     2512  identical
pic_nc_pk build/pic_nc_packed.bin      2971     2971  identical
pic_win build/pic_v_windowed_nocount.bin     2655     2655  identical
res    build/res_probe.bin          2019     2019  identical
cel    build/cel_probe.bin          1436     1436  identical
comp   build/comp_probe.bin          967      967  identical
vm     build/vm_probe.bin           8712     8712  identical
p3b    build/p3b_probe_pk_fresh.bin    12962    12962  identical

clock MEASURED 1.789772 MHz (160009 cycles calibrated)      [L-78]
```

★ **§2T:** siblings cited from P3b.19 §0; both HEADs unchanged. **Karateka's tree is dirty**
(`harness/smoke/last-run.log`), which under §2T.1(2) would force a rebuild — **no sibling artifact
is at stake here**: every file this task touched is in `src/harness/`, which no sibling builds, and
`hal_sync_check` passes in all three.

★★★ **§4's last row — which artifacts does each comparison READ against what its run PRODUCES
[L-88]?** Answered in full at AC-9. **Every committed comparison tool reads both planes.** The
one-plane reader was the uncommitted scratch script, and **two further instrument defects were
found by asking the question of the whole harness rather than of that one script.**

★★ **§4's flag row is reported as a CONTRADICTION and is resolved at AC-9.3:**
`flag_diff.py --manifest` lists `PRI_WIN_WRITE` and `PLANE_PRI_WIN` as **ON for the four `pic`
rows**, which would mean this task changed them. **The bytes say otherwise** — all four are
identical at their original sizes. The tool lists source-declared symbols, not active ones.

---

### 1 — Summary

**Fills wrote the priority plane flat while the plane was windowed.** `ff_store_pri` computed
`PRI_BASE + y*80 + x/2` — a flat offset of up to 13,439 bytes into an **8,192-byte window** — and
**never mapped the slice it was writing.** The fill's row seam maps only the plane the *test*
reads, which is the visual plane on 100% of KQ1's fills, so nothing ever put the needed priority
slice into slot 5; on a straddling span that slot holds a **framebuffer** slice.

★★★★★ **That is one mechanism producing both symptoms.** Priority values were being written into
the visual plane, which is the visual plane's wrong-colour damage and the priority plane's
under-fill from a single cause — and it closes P3b.19 §7.1, which recorded that no single mechanism
had been shown to produce both. **Picture 3's 92.3% wrong-colour visual divergence was the priority
write landing in the wrong plane, and it went to zero without one line of visual-plane code
changing.**

**A second site had the identical defect and was found by prediction, not by search:** `fill_check`'s
FC_PRIORITY **seed test** read the plane flat too. After the first fix, exactly five pictures still
failed — all with priority-only under-fill — and **every one had `PRI-ONLY > 0` while every passing
picture had `PRI-ONLY == 0`.**

**Result: pictures 22, 53 and 3 are 0% on both planes; the `priSeed == 0` control group is
unmoved; and 53 of 53 rendered KQ1 pictures are byte-identical on both planes.**

---

### 2 — Files modified

- `src/harness/pic_fill.s` — **the fix, two sites**, plus `PRI_WIN_WRITE` (declared at the top, see
  §3.C) and `-DPRI_FAULT_FLAT` (AC-6's fault).
- `harness/tools/plane_pair_diff.py` — slice-boundary split, which is what separated the mapping
  defect from the aperture overflow.
- `harness/tools/plane_sweep.py` — **new.** Corpus sweep, both planes, and it reads each run's log
  to refuse to score a run that did not render the picture (§3.E).

---

### 3 — Reasoning

#### 3.A Missing write, or a write to the wrong place? — **wrong place** [§2's first question]

`ff_store_pri` **is** called, from `ff_flush` under `ff_sec`, and `ff_sec = pri_on`. The write was
issued on every fill that should have written priority. It went to the wrong address:

1. ★★★★ **It never mapped a slice.** There is no `phase_draw_pri` or `plane_pri` call anywhere in
   the routine. It wrote to whatever slot 5 happened to hold.
2. ★★ **Rows ≥ 102 addressed past the aperture** — `$A000 + 8192 = $C000`, which is slot 6.

★★★★★ **The measurement decided between these two**, and it is why the boundary split was added to
the instrument: **the divergence sits on BOTH sides of the 8 KB boundary and is HEAVIER BEFORE it**
— pic022 **4,606** differing before row 102 against **427** at or after. An overflow alone cannot
damage a row it never addresses, so the mapping is primary and the overflow secondary.

#### 3.B Do lines and fills share a write path? — **two** [§2's third question]

Lines write through `put_pixel`, which handles the priority plane correctly and is why picture 80's
priority plane was byte-perfect while carrying 2.4% drawn non-clear pixels. The fill has its own
deferred per-span flush [P3.14, the 7.6% win] and that is the path that was flat. ★★ **The working
reference was in the same file the whole time** — §2H check 1, and it is what made the fix a
three-line redirection rather than a design.

#### 3.C ★★★★ The fix, and the ordering hazard that nearly split it in two

`plane_pri` maps the slice and returns the window address; `plane_avail` reports how many bytes of a
run fit before the boundary. ★★★ **Both already existed in `plane_win.s`, written for exactly this,
and were wired to the visual plane only.** A run is ≤160 pixels (80 bytes) against an 8,192-byte
slice, so it crosses at most one boundary and the loop runs at most twice.

★★★★★ **`PRI_WIN_WRITE` is declared at the TOP of the file and that placement is load-bearing.** It
was first declared beside `ff_store_pri`, **900 lines below `fill_check`** — and `ifdef` resolves in
source order, so the seed test would have silently taken the flat branch while the flush took the
windowed one. **Two sites disagreeing about whether the plane is windowed is the defect the symbol
exists to prevent.**

★★ **The flat build keeps its original code byte for byte**, which is why the eight gate artifacts
did not move (AC-8). `pic_probe` forces `PLANE_PRI_FLAT` whenever it windows, so the windowed
priority path is p3b's alone — **which is exactly why it was never gated.**

#### 3.D The second site, found by prediction [AD-122]

After AD-121's fix, five pictures still failed, all priority-only under-fill. The census predicted
them exactly:

| picture | visual | priority | **PRI-ONLY** |
|---|---|---|---|
| 1 | 0 | 994 | **2** |
| 2 | 0 | 6631 | **6** |
| 15 | 0 | 94 | **13** |
| 16 | 0 | 273 | **7** |
| 33 | 0 | 194 | **5** |
| *every passing picture* | 0 | 0 | **0** |

★★★ **`fill_check`'s FC_VISUAL branch was windowed at T-P0-041 (`jsr plane_vis`) and the
FC_PRIORITY branch forty lines below was left behind** — the same omission, on the same plane, in
the same routine. A seed that tests false is dropped silently and its whole region never fills,
which is why the damage is priority under-fill with the visual plane perfect.

#### 3.E ★★★★★ 29 of 82 runs never rendered the picture they were scored against

The first full sweep reported **41 of 82**. That number was wrong, and not because of the renderer:

- ★★★★ **27 pictures returned `err 2` from `res_open` and never rendered at all** — the plane still
  held the previous room. **This harness stages vol.0 and vol.1 only**, so pictures from later
  volumes cannot be loaded.
- ★★★ **2 room jumps missed** — `sw020` ended on room **83** and `sw054` on room **53**, so a
  title-screen render was about to be scored against picture 20's reference at 93.8% divergence.

★★★★★ **Both look exactly like catastrophic renderer failure, and neither is evidence about the
renderer.** `plane_sweep.py` now reads each run's log and excludes them by name and reason. **This
is L-88 one level up: the comparison must know what the run actually produced, not merely how many
files it wrote.**

★★ **Consequence for the dispatch's framing [L-83]:** §2 says *"`priSeed` gives it free — 79 of 82
KQ1 pictures exercise the path."* **True of the resources and not of this harness** — the reachable
corpus is **53**, and the other 29 are a staging limit, not renderer coverage.

#### 3.F Authority tiers and §2H

Oracle planes are the reference per §2O.1. §2H's three checks: the **second mechanism** was looked
for and found — the plane has a READ site and a WRITE site and fixing one left the other (§3.D); the
**calling routine** is named at each step (`ff_flush` → `ff_store_pri`; `ff_pop_lp` → `fill_check`);
the **prior-report grep** is AC-7's re-take of six figures and P3b.19 §7.1's closure. §2S: the only
sibling claim is `hal_sync_check`, at the HEADs quoted in §4.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: eye-gated] — PENDING JAY.** ★★★ **Reported first per §4A**, and §5's commands are
  the castle room and room 22, the two Jay described as under-filled. **Launch path `poke`.**
  ★★ **§4A tension stated rather than glossed:** §4A.3 says "pending Jay" is not acceptable on an
  integration task, and this dispatch's AC-1 says "pending Jay." **The byte evidence below is
  complete and Jay has not yet seen it run; the task is not closed until he has.**
- **AC-2 [class: byte-comparable] — PASS.** `hal_sync_check` **OK in all three**; `reg_discipline`
  **8 accesses, 1 file, 2 registers — unchanged.** ★★ The fix creates no register owner: it routes
  through `plane_pri` → `phase_draw_pri` → `mmu_phase.s`, which stays the single sanctioned owner of
  `$FFA5`/`$FFA6` (§2N). §2T citation: P3b.19 §0.
- **AC-3 [class: byte-comparable] — PASS. ★★★★★ All three at 0% on BOTH planes.**

  | picture | before (visual / priority) | after |
  |---|---|---|
  | 22 | 14.8% / 18.7% | **0.0% / 0.0%** |
  | 53 | 23.9% / 21.6% | **0.0% / 0.0%** |
  | 3 | 71.5% / 16.0% | **0.0% / 0.0%** |

- **AC-4 [class: byte-comparable] — PASS.** The `priSeed == 0` control group is unmoved:
  **80, 83 and 84 all 0.0% / 0.0%.** ★ 83 is the title screen and 84 the third exempt picture.
- **AC-5 [class: byte-comparable] — PASS. 53 of 53 RENDERED pictures byte-identical on both planes
  (100.0%).** 29 excluded as harness rather than renderer, itemised in §3.E and listed by name in
  §5. ★★★ **Trigger 1 did not fire**: no rendered picture diverges.
- **AC-6 [class: byte-comparable] — PASS, and specifically on the PRIORITY plane.**
  `-DPRI_FAULT_FLAT` reverts both sites. On picture 22: **fault 14.8% visual / 18.7% priority,
  100% under-fill; control 0.0% / 0.0%.** ★★★★ **The fault reproduces the ORIGINAL figures exactly**
  — the same 14.8/18.7 measured before the fix — and **the fault binary is 12,859 bytes, byte-count
  identical to the pre-fix artifact.** ★★ Trigger 3 did not fire.
- **AC-7 [class: state-comparable] — DONE. Every published figure re-taken on both planes**, and
  **the priority plane was worse than the visual plane in every case:**

  | picture | published (visual only) | re-taken PRIORITY | after fix |
  |---|---|---|---|
  | 1 | 28.8% | **55.3%** | 0.0% / 0.0% |
  | 3 | 71.5% | 16.0% | 0.0% / 0.0% |
  | 5 | 20.7% | **37.0%** | 0.0% / 0.0% |
  | 17 | 20.6% | **35.8%** | 0.0% / 0.0% |
  | 22 | 14.8% | 18.7% | 0.0% / 0.0% |
  | 53 | 23.9% | 21.6% | 0.0% / 0.0% |
  | 80 | 0.0% | 0.0% | 0.0% / 0.0% |

  ★★★★ **The published figures understated the damage on four of seven pictures, on the plane
  nobody read.** None is withdrawn — each was a correct visual-plane figure — and none may now be
  quoted without its plane named [L-64].
- **AC-8 [class: byte-comparable] — PASS.** The eight other gates **identical at their original
  byte counts**: 2642 / 2512 / 2971 / 2655 / 2019 / 1436 / 967 / 8712.
- **AC-9 [class: state-comparable] — the harness sweep, and it found three things.**
  1. ★★ **Every committed comparison tool already reads both planes** — `picgate.py:72-73`,
     `picdiff.py:90-91`, `comp_stage/comp_pick/comp_overlay/comp_fault_predict`, `comp_sweep.lua`.
     **The one-plane reader was the uncommitted scratch script**, which is itself the finding: it
     was never subject to review because it was never a file in the tree [L-45].
  2. ★★★ **`picset.py:82` selects the corpus on `pic%03d.visual.bin` existing and never checks the
     priority reference.** Harmless today — KQ1 has 82 of each — but it is corpus selection on one
     plane, which is L-88's shape.
  3. ★★★★ **`flag_diff.py --manifest` reports symbols the source DECLARES, not symbols that are
     ACTIVE.** It lists `PRI_WIN_WRITE` and `PLANE_PRI_WIN` as ON for all four `pic` rows, which
     cannot be true — those artifacts are byte-identical. **An instrument in §4's own checklist,
     whose entire job is saying which flags are live, over-reports conditionally-defined ones.**
- **AC-10 [class: state-comparable] — six things the dispatch did not anticipate.**
  1. ★★★★★ **The visual plane was fixed by a priority-plane fix.** Picture 3's 71.5% was mostly
     wrong-colour damage in the *visual* plane and no visual-plane code changed.
  2. ★★★★ **There were two sites, not one**, and the second was predicted by `PRI-ONLY` before it
     was located.
  3. ★★★★ **29 of 82 sweep runs never rendered the picture they were scored against** (§3.E), so
     the corpus this harness can reach is 53 and not 79.
  4. ★★★ **`ifdef` ordering** — the guard symbol had to move 900 lines up or the two sites would
     have disagreed (§3.C).
  5. ★★★ **`flag_diff --manifest` over-reports** (AC-9.3).
  6. ★★ **The fix costs nothing where the path is unused.** Cycle 1 (room 83, `priSeed == 0`) is
     **7.2927 s before and after, to four decimals.**
- **AC-11 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — AC-5, the corpus, both planes:**

```
★ 53 of 53 RENDERED pictures byte-identical on BOTH planes (100.0%)
★★★ EXCLUDED (the run did not render this picture -- harness, not renderer): 29
      pic020  room jump missed -- rendered room 83
      pic054  room jump missed -- rendered room 53
      pic049 050 051 052 056 057 058 059 060 061 062 064 065 066 067 068
      pic069 070 071 072 073 074 075 076 077 078 079
              err 2 -- resource not loaded, no render   (vol.0/vol.1 staged only)
```

**25.1 — AC-3 and AC-4, per picture, both planes named:**

```
pic022  visual 0.0%   priority 0.0%        pic080  visual 0.0%   priority 0.0%
pic053  visual 0.0%   priority 0.0%        pic083  visual 0.0%   priority 0.0%
pic003  visual 0.0%   priority 0.0%        pic084  visual 0.0%   priority 0.0%
```

**25.1 — AC-6, the priority-plane fault:**

```
fault  : 12859 bytes      shipped: 12962 bytes      BYTES DIFFER
=== FAULT (-DPRI_FAULT_FLAT), picture 22 ===
  VISUAL   14.8%  under 45.2% / wrong 54.8%
  PRIORITY 18.7%  under 100.0% / wrong 0.0%
=== CONTROL, same picture, shipped build ===
  VISUAL   0.0%        PRIORITY 0.0%
```

**25.1 — the localisation, boundary split (pre-fix, picture 22):**

```
VISUAL   3983 (14.8%)  SLICE BOUNDARY row 51:  3465 before, 518 at/after
PRIORITY 5033 (18.7%)  SLICE BOUNDARY row 102: 4606 before, 427 at/after
```

**25.1 — cost:** roomcheck over 40 cycles **13.0477 s → 13.8534 s** (+0.806 s, +6.2%) for picture
22's render; **cycle 1 unchanged at 7.2927 s**. Binary **12,859 → 12,962 B (+103)**.
Clock **1.789772 MHz** measured.

**25.2 bundled-artifact grep:** N/A — no bundled artifact exists; the nine gate binaries are
byte-identical to their sources (§4).

**25.3 operator-runtime-smoke: pending Jay.** Launch path **`poke`**, RGB.

```powershell
$s = '<scratchpad>\p3bshow.cmd'
& $s 40 1  eye01 0 6      # the CASTLE -- was 28.8% visual / 55.3% priority
& $s 40 22 eye22 0 6      # room 22 -- "filled but with obvious areas not filled"
```

---

### 6 — Reactive deviations and route accounting

- **No trigger fired.** Trigger 1: no rendered picture diverges. Trigger 2: the fill's structure is
  unchanged — P3.3's inner loop is untouched and the addition is per-span address setup. Trigger 3:
  the gate fails on the priority plane. Trigger 4: **fired in spirit and is reported** — §4's sweep
  found two further instruments reading or reporting less than they claim (AC-9.2, AC-9.3), neither
  invalidating a published figure. Trigger 5: AC-7 changes no figure the design spec quotes; it adds
  a plane to six of them.
- **ROUTE ACCOUNTING.** I proposed no route before building. The second site (AD-122) was **not** in
  the dispatch and was added because AC-5 measured it; the dispatch's "Do NOT consult for: fix
  implementation" covers it. **What I did NOT do:** widen the volume staging so the other 29
  pictures render (§11 out of scope), and fix `picset.py`'s one-plane corpus selection (AC-9.2).

---

### 7 — Uncertainty flags

1. ★★★ **AC-5's 100% covers 53 pictures, not 79.** The other 29 are unmeasured, not passing. Until
   the harness stages more volumes, the claim is *"every picture this harness can render"*.
2. ★★ **One title.** All of it is Kingquest1. KQ2 and KQ3 have oracle references and were not swept.
3. ★★ **The unpacked windowed priority path is untested.** No build combines them, so the second
   half of AD-122's fix is symmetry rather than measurement, and is labelled as such in source.
4. ★ **The +6.2% render cost is one picture on the counted build**, which costs 2.16× [AD-96]. It is
   not a room-render performance figure and must not be quoted as one.
5. ★ **Pictures 20 and 54's room jumps miss reproducibly** — twice each, same rooms. Not diagnosed.

---

### 8 — Follow-up candidates

1. ★★★★ **Stage the remaining volumes** so the 27 `err 2` pictures render — that is what turns
   AC-5's 53 into 79.
2. ★★★ **Sweep KQ2 and KQ3** on both planes (§7.2).
3. ★★★ **Fix `flag_diff --manifest`** to report active symbols (AC-9.3) — it is a §4 instrument.
4. ★★ **`picset.py`: require both plane references** when selecting a corpus (AC-9.2).
5. ★★ **Diagnose the room-20 and room-54 jump misses** (§7.5).
6. ★ **Give `res`, `cel` and `comp` a `_FAULT`** (carried, 6 tasks).

---

### 9 — User interaction during task

Jay checked progress four times during the sweeps and was given interim results each time
(31 of 37, then 47 of 47, then the second-site finding). No direction was given or requested.

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-09-06-a-run-that-produced-no-output-still-produces-a-file.md`

---

### 11 — Commit

`583f462` (pushed to origin/wip before this report; this §11 hash lands in the follow-up commit).
Pool candidate `d1773a7` on `methodology-candidate-pool@main`.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
