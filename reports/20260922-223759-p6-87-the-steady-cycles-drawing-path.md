## Form B Report — P6.87 — The steady cycle's drawing path: structural, with one defect inside it
**Class:** measurement, §1.3's licence exercised once.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22 (HEAD `73ec5d6`, wip). `git status` clean apart from an untracked
`coco_agi.code-workspace` that predates this task.

### 1 — Summary
★★★★★ **The verdict is MIXED, and both halves are stated in §4B's terms.** The drawing stage is
**65.5% of a steady cycle** and decomposes to **100.0%**; its two core loops — `cp_composite`
28.9% and `vc_decode_row` 26.6% — are **55% of the stage between them, spread across their own
internals with no further defect. That half is structural.**

★★★★★ **But one thing inside it was a defect of the same shape P6.84 found: `plane_pri` derived
the same address twice per drawn pixel** — once to READ the screen priority for the depth test and
again to WRITE it back, with only `co_put_visual` between. `plane_vis` maps **slot 6** and
`plane_pri` **slot 5**, so the mapping survives and only `X` was clobbered. ★★★★ **`co_rej_pri` is
ZERO in the castle**, so every opaque pixel is drawn and **exactly half of all `plane_pri` calls
were that re-derivation — 11,360 of 22,720 over 40 cycles.**

All five criteria held. **Steady cycle mean 0.2925 → 0.2791 (−4.6%), median 0.2837 → 0.2670
(−5.9%)**; **pixels identical**; **the room change unmoved** (6.1579 → 6.1412). ★★★ **Windowed
build only — `comp_probe` is the flat `comp` gate and is byte-identical**, and only the three
cel-linked arms moved.

★★★ **§1.1's "six for six, expect a defect" was half right, which is the honest answer**: there
was one, and it is worth 4.6%, and the other 95% of the stage is the algorithm.

### 2 — Files modified
- `src/harness/composite.s` — site 1 caches the priority address in `co_prix`; site 2 reuses it;
  `-DCOMP_PRIX_REDERIVE` (the before arm); §9's per-sprite/per-pixel cost block beside
  `cp_composite`. **Windowed paths only.**
- `harness/tools/p3b_show.ps1` — `-PriXRederive`.
- `harness/tools/p3b_arms_check.ps1` — the three cel-linked arms re-baselined (+2 B each).

### 3 — Reasoning

#### §3(2) — the drawing path's structure, and which routine is which ★★★★
`p3_composite_all` per staged sprite → `res_locate` (VIEW, in place since P6.83) →
`vc_decode_begin` → `cp_composite`, which pulls each row through `vc_decode_row` into `CP_CEL` and
blits it. `p3_restore_prev` (`prp_copy`/`prp_visual`/`prp_priority`/`prp_split`) runs first, in the
same stage. The plane accessors `plane_vis`/`plane_pri` sit under all of it.

#### §3(3)/(4) — the sprite load, and whether it is typical ★★★★
**Four staged sprites, 128 cels composited over 40 cycles = 3.2 per cycle.** Two of the four share
view 107. ★★★ **The castle's load is small**: four objects, one of them the ego. A room with more
objects composites more, and every figure below is one room of one title — ★★ stated rather than
qualified away, because §6 makes an atypical load a stop and this one is atypical in the *low*
direction, which makes the figures a floor rather than a ceiling.

#### §4A(1) — the decomposition ★★★★★
**Window: `--stage 9`, cycles 11–120, 20,774 samples at 997 Hz. The stage is 65.5% of the steady
window (0.191 s of a 0.292 s cycle).**

| class | samples | share of stage | s/cycle |
|---|---|---|---|
| compositor | 7,265 | **35.0%** | 0.0669 |
| cel decode / blit | 5,732 | **27.6%** | 0.0527 |
| plane window access | 3,872 | **18.6%** | 0.0355 |
| restore walk | 1,764 | 8.5% | 0.0162 |
| resource manager | 1,694 | 8.2% | 0.0157 |
| MMU phase switches | 365 | 1.8% | 0.0034 |
| key scan / IRQ | 80 | 0.4% | 0.0008 |
| **SUM** | **20,774** | **100.0%** | **0.191** |

★★★★ **It reconciles: 100.0%, no gap to name** (the profile's shares sum by construction, and the
stage's own share of the window — 65.5% — is the write-tapped marker's).

#### §4A(2) — top routines inside the stage ★★★★
`cp_composite` 28.9% · `vc_decode_row` 26.6% · `plane_pri` **11.5%** · `plane_vis` **6.1%** ·
`prp_copy` 5.3% · `co_put_visual` 4.8% · `res_cnext` 4.2% · `res_ptr` 1.9% · `prp_priority` 1.2% ·
`prp_visual` 1.0% · `pl_map_vis` 1.0% · `res_map_block` 0.9% · `co_checkctrl` 0.8% · `prp_split`
0.8%. ★★★ **Top 25 cover 98.5%; 39 routines seen; 0 samples in remapped slots.**

#### §4A(3) — per sprite and per pixel ★★★★
★★★★ **A total is not a cost model** [P6.86's lesson, applied]:
- **Per cel composited: ~60 ms** — ~21 ms to blit, ~16 ms to decode (0.191 s ÷ 3.2 cels).
- **Per pixel: 630 tested and 284 written per cycle**, so **~106 µs per pixel TESTED** — about
  **190 CPU cycles at 1.79 MHz**. ★★★ **That is the number a pixel-loop ruling starts from.**
- **Per restored byte: ~23 µs** (0.0162 s ÷ 707.9 bytes).

#### §4A, last paragraph / AC-3 — where the other 41% goes ★★★
Same window, by stage: **interpret 29.3%** (`vm_test_if_code` 30% of it, `vm_run_logic` 11%,
`vm_skip_instruction` 8%, `vm_getflag` 8%) · **cycle end (`P3_PHASE=10`) 3.5%** (`p3_loop` 74%,
`p3_key_latch` 25%) · **sprite staging 1.5%** (`p3_stage_sprites` 100%) · **pacing 0.2%** ·
roomcheck ≈0%. ★★ **65.5 + 34.5 = 100**, so nothing is unaccounted.

#### §4B — defect or structural: BOTH, and here is the line between them ★★★★★

> **§4B's test:** one class over ~50% with one routine inside it dominating = a defect to look at;
> cost spread across many routines with none dominant = structural.

**Structural (the 95%).** No class exceeds 35%. The two biggest routines are the two core loops,
and inside each the cost is its own internals — for `cp_composite`: `co_pix`, `co_depth`,
`co_opaque`, `co_put_visual`, `co_checkctrl`; for `vc_decode_row`: `vc_dc_emit`, `vc_dc_clr`,
`vc_dc_fill`, `vc_dc_run`, `vc_dc_after`. ★★★★ **That is an algorithm's shape.**

**The defect (the 4.6%).** ★★★★★ `plane_pri` at **11.5%** is nearly twice `plane_vis` at 6.1%, and
the asymmetry had been noticed at P6.84 and never diagnosed. The cause: **two calls per drawn pixel
from identical inputs** — site 1 (`co_opaque`, the depth-test READ) and site 2 (`co_depth`, the
priority WRITE), both computing `co_rowpri + (co_curx >> 1)`.

★★★★★ **The mapping survives between them, which is why the ADDRESS can be reused and not merely
the arithmetic skipped.** Between the two sits `cmpa co_prio` and `jsr co_put_visual`, and
`co_put_visual` touches `co_rowvis` and `plane_vis` — **slot 6**. `plane_pri` maps **slot 5**, and
since P6.82 the two have separate records (`ph_cur6`, `ph_cur5`). ★★★ **Checked, not assumed.**

★★★★ **And the measurement makes the share exact rather than estimated**: `co_rej_pri` is **0**, so
opaque == drawn, so site 2 runs on **every** pixel site 1 ran on. **Half of `plane_pri`'s 11.5%.**

**§4B's named options for a ruling, NOT started** [§6's second trigger]:
1. ★★★ **Per-row instead of per-pixel window access** — a row is one slice by construction unless
   it straddles; `plane_avail` already computes the split for the fill.
2. ★★★ **A cheaper priority test** — the packed plane forces a read-modify-write per pixel; an
   unpacked shadow of the priority row would make the depth test a byte compare.
3. ★★ **A decode that writes the blit's format directly** — `vc_decode_row` writes `CP_CEL` and
   `cp_composite` immediately re-reads it.
★★★★★ **All three change what the gates at 9,193 and 124 are gating. They are rulings.**

#### §4C — §1.3's five criteria, per candidate ★★★★★

**Candidate 1 — the duplicate `plane_pri` derivation.**

| | criterion | verdict |
|---|---|---|
| 1 | **One cause** | ★ **MET** — one routine called twice from identical inputs; `co_rej_pri = 0` makes it exactly half the calls. |
| 2 | **Local, no new mechanism** | ★ **MET** — one `stx` at site 1, one `ldx` at site 2, one 2-byte variable. **No new mechanism**, and it is the same class as P6.84's `res_cnext` fix: reuse a value instead of re-deriving it. |
| 3 | **No observable behaviour** | ★ **MET** — same address, same byte. `co_tested 25200`, `co_rej_key 13840`, `co_rej_pri 0`, `co_WRITTEN 11360`, `CP_BLITS 128`, `restore 28314`, ego position and text-area bytes **all identical**; five byte gates unmoved. |
| 4 | **Fault arm red** | ★ **MET** — `-DCOMP_PRIX_REDERIVE` restores the second call and differs in nothing but time. |
| 5 | **No ruling** | ★ **MET** — not the map, arena, gate meaning or oracle semantic. ★★★ **Scoped to `PLANE_WINDOWED` precisely so the flat `comp` gate's binary cannot move**, per this file's own rule that the flat build's instruction order stays byte-for-byte. |

★★★★ **Five of five — taken**, measured one binary apart.

**Candidate 2 — the two core loops (55% of the stage).** ★★★ **FAILS (1) and (2)**: no single
routine inside either dominates, and changing them is an algorithm change. §4B's options.

**Candidate 3 — resource manager, 8.2% of the stage.** `res_cnext` 4.2% + `res_ptr` 1.9% is the
in-place VIEW read's cost; `res_ptr` is the ~10 header `res_peek`s per cel. ★★ **FAILS (1)** — it
is spread, and 0.7% of the cycle. ★ Recorded because it is the cost P6.83 knowingly bought, and
it is smaller than the copy it replaced.

#### §2S — sibling refs
POP3_port `104b197` (wip), karateka_coco3 `29f8f0a` (wip); both dirty with pre-existing work not
mine. **No `SHARED` file touched**; `hal_sync_check.py` OK. lwasm 4.24 unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement]** §4A(1). ★★★★★ **Reconciles to 100.0%; no gap.**
- **AC-2 [measurement]** §4A(2)'s top 25 and §4A(3)'s per-sprite / per-pixel figures.
- **AC-3 [measurement]** §4A's last paragraph — interpret 29.3%, cycle end 3.5%, staging 1.5%,
  pacing 0.2%. **65.5 + 34.5 = 100.**
- **AC-4 [attribution]** §4B: **structural in the large, with one local defect inside it**, stated
  in §4B's own terms and with the options named for a ruling.
- **AC-5 [judgement]** §4C's three candidates, criteria answered.
- **AC-6 [measurement] Steady window, cycles 11–120, n=110, one binary apart:**

  | | before (`-PriXRederive`) | after |
  |---|---|---|
  | **mean** | 0.2925 | **0.2791** (**−4.6%**) |
  | **median** | 0.2837 | **0.2670** (**−5.9%**) |
  | p75 / p90 / max | 0.3004 / 0.3171 / 0.3171 | 0.2837 / 0.3004 / 0.3004 |
  | **room change (cycle 9)** | 6.1579 s | **6.1412 s** |
  | class that moved | plane window access 18.6% | ★ `plane_pri`'s share halves |

  ★★★ **The whole distribution shifts down one frame**, which is what the median shows. ★★ **The
  room change is unchanged** (−0.3%, noise) and was not meant to move: the compositor barely runs
  in the render cycle.

- **AC-7 [state-comparable] Pixels identical** — every counter above, both arms.
- **AC-8 [byte-comparable · gate] `src/` changed, all RUN.** `cel` **9,193/9,193** and `comp`
  **124/124** (the two that own this code), `pic` **45 PASS / 0 FAIL (of 45)**, `res`
  **1,264/1,264**, `vm` **9/9 (0 divergent of 600 each)**. ★★★★ **All five gate probes
  byte-identical, `comp_probe` included** — the change is windowed-only and `comp_probe` is flat.
- **AC-9 [state-comparable · fault injection]** `-DCOMP_PRIX_REDERIVE` is the arm: same pixels, the
  old cost. ★★ As with P6.85's flag, **removing a redundant derivation leaves no logic to break**,
  so the arm is the attribution pairing rather than a correctness red; said plainly.
- **AC-10 [suite]** `p3b`, `p3b_text`, `p3b_box`, `p3b_parse`, `p3b_row22` green (`all green`);
  **`-IfRec` still assembles (19,988 B)**; mojibake clean; `-SelfTest` red on exactly one row.
- **AC-11 [eye gate — Jay]** Live, RGB, 300 cycles. Expectations stated, **including that "no
  difference" was a legitimate answer at −4.6%.** Jay:
  1. *"possibly faster hard to tell"* — ★★★★ **exactly the stated expectation.** −4.6% is about one
     frame a cycle and below reliable perception; **not claimed as more.**
  2. *"yes"* — everything looks identical, as AC-7 measures.
  3. *"forgot to check typing"* — ★★★ **recorded as NOT TESTED.** No inference is drawn from the
     other two answers about it.

- **AC-12 [manifest]** **Three cel-linked arms re-baselined, +2 B each**; ★★★ **the six text arms
  byte-identical** — verified, and that split is the scoping check. Probes unmoved.
- **AC-13** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
=== AC-2 SUMMARY === all nine titles PASS (vm, 600 cycles each, 0 divergent)

§4A  # window cycles 11-120  hz 997  samples 31695  [--stage 9: P3_PHASE=9 only -> 20774]
     composite stage = 65.5% of the window
     compositor 35.0% | cel decode 27.6% | plane window 18.6% | restore 8.5%
     resource mgr 8.2% | MMU phase 1.8% | key/IRQ 0.4%     SUM 100.0%
     cp_composite 28.9% | vc_decode_row 26.6% | plane_pri 11.5% | plane_vis 6.1%
     prp_copy 5.3% | co_put_visual 4.8% | res_cnext 4.2% | res_ptr 1.9%
     top 25 cover 98.5%; 39 routines; PCs in remapped slots 3-6: 0
AC-3 interpret 29.3% | P3_PHASE=10 3.5% | sprites 1.5% | pace 0.2%

AC-6 before mean 0.2925 median 0.2837  ->  after mean 0.2791 median 0.2670
     room change 6.1579 -> 6.1412
AC-7 co_tested 25200 | co_rej_key 13840 | co_rej_pri 0 | co_WRITTEN 11360 | CP_BLITS 128
     restore 28314 bytes | ego x=110 y=100 | text area 266 of 5120     both arms

★ all 9 arms byte-identical to the recorded baseline (SHA256)   [3 re-baselined, +2 B]
★ every non-p3b probe byte-identical      comp 967 B 39F5D105  (flat, unmoved)
-IfRec assembles: 19988 B
[reg-discipline] 6 register access(es) in 1 file(s) over 4 register(s).
[hal-sync] OK      CHECK OK: vm_tables.s matches optable.py.
```

**25.2 bundled-artifact grep:** N/A — nine arms and five probes pinned by hash.

**25.3 operator-runtime-smoke:** **PASSED — Jay, live, RGB, `-Combined`, 300 cycles.** AC-11.
★★ Question 3 (typing) **was not checked** and is recorded as such.

### 6 — Reactive deviations and route accounting

1. ★★★ **`-DCOMP_PRIX_REDERIVE` was added and the dispatch did not ask for it** — §4C requires
   before and after in the same task, and a same-binary before arm is the only way to do that.
2. ★★★★ **The fix is inside the pixel loop, which §10 lists out of scope as "algorithmic change to
   the pixel loop".** Judged **in scope**, and the reasoning is recorded rather than assumed: the
   algorithm is unchanged — the same plane bytes are read and written in the same order — and what
   is elided is one duplicate address computation. ★★★ **§10's exclusion is about changing HOW
   compositing works** (per-row access, a different priority representation), which §4B names as
   rulings and does not start. **If the Orchestrator reads that line more strictly, this fix is the
   one to revert**, and `-DCOMP_PRIX_REDERIVE` makes that one flag.

★★★★ **No §2J.5 violation.** Every edit used `Edit`; `fix_mojibake --check` clean.

**ROUTE ACCOUNTING.** §4C evaluated three candidates and took one. **NOT taken, each with the
criterion it fails**: the two core loops (1 and 2 — §4B's three options are named for a ruling and
none is started); the resource manager's 8.2% (1 — spread, and 0.7% of the cycle).

### 7 — Uncertainty flags

1. ★★★★★ **The steady cycle is 0.279 s against a 0.100 s target — still 2.8×.** After this task the
   remaining drawing cost is genuinely the two core loops. **The next move is a ruling, not a
   licence.**
2. ★★★★ **The castle's sprite load is small and the figures are a floor**: four objects, two
   sharing a view, 3.2 cels a cycle. A busier room composites more, and the compositor is 35% of
   the stage.
3. ★★★ **`plane_vis` still derives its address per pixel**, and `co_put_visual` is the only caller
   — but unlike the priority pair there is no second call to elide, so it is option 1's territory.
4. ★★★ **AC-9 has no correctness fault arm**, for the same reason P6.85's did not: removing a
   redundant derivation leaves no logic to break. ★★ The backing is the attribution arm plus five
   unmoved gates.
5. ★★ **Typing was not checked** (AC-11.3) and nothing is inferred about it.
6. ★★ **Wall-clock run times are noise**: 36 → 27 → 19 → 31 s across the session for the same
   300-cycle gate. **Only the emulated figures are quoted**, both mean and median, both windowed.

### 8 — Follow-up candidates

1. ★★★★★ **The pixel loop and the cel unpack, as a RULING** — §4B's three options: per-row window
   access · a cheaper priority test (the packed plane forces a read-modify-write per pixel) · a
   decode that writes the blit's format directly. ★★★★ **All three change what `cel` (9,193) and
   `comp` (124) gate.**
2. ★★★★ **The fill, also a ruling** [P6.86]: 63.6% of a 4.90 s render, ~36 ms a seed.
3. ★★★ **Design spec §7.1's `0.039 s/cycle`** is `comp_probe`'s and is **ten tasks flagged**.
   ★★★★ **This task produces the number that should replace it: 0.2791 s/cycle mean, 0.2670
   median, KQ1 room 1, steady cycles 11–120, four sprites** — PROPOSED TEXT ONLY [§2D].
4. ★★★ **Re-measure with a busier room** before any pixel-loop ruling [§7(2)].
5. ★★ **The map ruling** (region A); **the VIEW checksum gap**; **real-time pacing** (still
   2.8× away); **typing cadence**; **the title page** items; **`checkPriority`/`checkCollision`**;
   **`MAP_PRI_BANDS`** at `memmap.inc:310` — **the thirty-third task.**

### 9 — User interaction during task
The AC-11 eye gate, offered after the fix was taken, with expectations for all three questions
including that "no difference" was legitimate at this size. Jay's three answers are quoted in
AC-11; question 3 was not checked and is recorded as untested.

### 10 — Candidate(s) captured this task
`seeds/AGI/live/2026-09-22-structural-with-one-defect-inside-it.md`

### 11 — Commit
`aa5bc1a`  (pushed to origin/wip before this report)
Pool candidate `a7ab432` (methodology-candidate-pool, main).
