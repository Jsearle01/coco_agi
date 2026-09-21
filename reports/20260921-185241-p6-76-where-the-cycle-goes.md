## Form B Report — T-P0-129 / P6.76 — Where the cycle goes: throttle, profile, budget
**Class:** measurement. wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-21T22:28:36Z (HEAD 87f5673, wip). git status clean at receipt (one untracked
`coco_agi.code-workspace`, not mine, not staged).

### 1 — Summary

★★★★★ **The target was wrong by half and the problem was overstated by a third, so the gap is 3×,
not 7.8×.** Kingquest1 sets **var 10 = 2** at cycle 1, which the oracle turns into **10 cycles/s
(100 ms)**, not 20. The design spec already says so [§5.4a, AD-82]; P6.74's "0.050 / 20" was a
mis-quote. **The port does not pace in real time**: `vm_pace` spins a virtual counter and costs
**0.2% of a castle cycle**. **The steady castle cycle is 0.300 s (3.3/s), not 0.389**: P6.74's figure is
a whole-run average with ~26 s of startup renders folded in.

★★★★ **A continuous PC profiler** (new `P3B_PROFILE` mode, 997 Hz on an emulated-time timer, CURPC,
checked against the exact stage timer to within 0.2 points) **puts the castle cycle at: compositor
38.5% · cel decode 17.2% · resource manager 16.8% · plane window access 10.0% · VM interpret 6.4% ·
restore walk 5.5%.** ★★★★★ **Two items nobody expected are 28.7% of the cycle between them, and both
are work the cycle does not need**: every sprite's whole VIEW is re-copied into the arena every cycle
(`res_fetch`, 15.9%), and **the shipped arm counts every pixel with a 32-bit software increment**
(`co_inc32`, 11.9%) because `COMP_NOCOUNT` is not set.

★★★★ **Structural, not one hotspot.** The composite stage is 81% of the cycle, but no routine exceeds
21%, and **the stage must shrink ~4.7× to fit 100 ms**. Removing the re-fetch, the counters and every
plane-window call outright would still leave ~1.8× (arithmetic, unverified).

**No optimisation attempted.** `src/`: 18 comment lines (the §9 parking note), all 8 arms byte-identical.

### 2 — Files modified
- `harness/tools/p3b_run.lua` — `P3B_PROFILE` / `P3B_PROFILE_HZ` / `P3B_PROFILE_PC`: an off-frame PC
  sampler (CURPC + MMU block + stage marker per sample). §9 note beside the stall sampler.
- `harness/tools/pc_profile.py` — NEW. Maps samples to routines and subsystems, cross-checks them
  against the stage timer, and differences a second profile to measure bias.
- `src/harness/p3b_probe.s` — **comments only**: §9's parking note beside `-DP3B_VBLKEYS_OPT`.
- `mame-idioms-coco3-port.md` — new §44 (the sampler, and CURPC ≠ PC) per §2A.4.
- `reports/20260921-185241-p6-76-where-the-cycle-goes.md` — this report.

### 3 — Reasoning

#### §3 pre-dispatch checks

**§3(1) Arms.** All eight byte-identical to the recorded SHA-256 baseline, **before and after** the
comment edit (§5 below). Latch build 18782 / B9F06823 remains the recorded opt-in figure.

**§3(2) ★★★★★ Every wait in the cycle, in full.** There are **three**, and only one is in the port:

| wait | where | what it waits on | measured |
|---|---|---|---|
| `vm_pace` | `vm_cycle.s:328-334`, called at `p3b_probe.s:1234` | **nothing real.** It loops `vm_step_clock`, which increments a counter, until `vm_passed ≥ vm_tdelay` (= var 10 × 3 = **6**) | **0.00065 s/cycle** = ~1,160 CPU cycles, **0.2%** castle, 0.9% title |
| `p3_wait` (the handshake park) | `p3b_probe.s:1043-1048` | the HOST's `P3_GO`, written on the next frame notifier; runs `p3_key_latch` while it spins | castle 2.3% of wall, **title 17.9%**. ★★ **Harness, not port** — a shipped interpreter has no host |
| `tx_wait_dismiss` | `vm_text_ops.s:435` | `hal_frame_lo` edges while a message box is up | **not in either window** (the castle window ends at cycle 55, before the box at 57; text = 0.0% in both profiles) |

No `sync`, no `cwai`, no `HAL_time_vbl_wait` in the cycle [grep over `src/` less `src/hal/`].
★★★★ **The comment at `p3b_probe.s:1224` calls `vm_pace` "a BUSY-WAIT … deliberately hitting the rate
the GAME asked for (var 10)". It is not a wait in real time.** It reproduces the reference's virtual
clock [`cycle.py run()`] so that cycle count and the game timers track each other, and it returns
after six counter steps whatever the wall clock says. **Consequence for later, not this task: once
the port is faster than 100 ms it will run too fast**, because nothing holds it back to real time.
Not edited (§6: no `src/` change beyond §9's note); recorded in §8.

**§3(3) What Kingquest1 writes to var 10, and when.** From the offline reference's opcode trace
(`pic_order.py`, which runs the oracle-gated reference):
`1  0  0  assignv  0A 58  v10=0 v88=2` — **logic 0, cycle 1: `v10 = v88`, and v88 = 2.** The guest
agrees: castle `vm_tdelay=6`, which is var 10 × 3 VBL ticks. [Tier: the reference is gated against
the pinned ScummVM at 288 bytes of state per cycle; the port's own register corroborates it.]

**§3(4) Attribution and the fixed-slot claim — HOLDS.** Each sample records the block behind the
PC's slot (masked `& $3F`, idioms §22a). **Across 17,137 samples: zero PCs in slots 3-6; slot 1 is
always block `$39`, slot 2 always `$3A`, slot 7 always `$3F`.** So every PC names one routine in
every phase. Slot 7 (text engine at `$EBBA`, parser at `$E000`): castle 7 samples, title 29, all
attributed to named routines (`par_said` 26, text 3). **§6's slot-7/region-B trigger does not fire.**

#### §4A — the throttle, before the profile

1. **The oracle** [ScummVM `engines/agi/cycle.cpp:538-558`, secondary tier]: for v2 the delay is
   `getVar(VM_VAR_TIME_DELAY)`; the source's own comment says *"In Original AGI 1 cycle was 50
   milliseconds, so 20 frames per second"*, with **TIME_DELAY 1 → ~20 fps, 2 → ~10 fps, 0 → no
   limit**. ScummVM counts it in 25 ms units, doubled. **Nominal rate = 20 / var 10 cycles/s.**
   ★★ Per §2.1: the 50 ms unit is ScummVM's statement about the original, in a comment. Not checked
   against the running original in this task, and it does not need to be: the corpus survey
   [AD-82] already found 100 ms dominant across 92 write sites.
2. ★★★★★ **KQ1 in the castle: var 10 = 2 → 10 cycles/s, 100 ms/cycle.** **Replaces P6.74's "0.050 /
   20".** ★★★ §2H check 3: **design spec §5.4a already recorded 10**: *"the corpus asks for 10 — 92
   write sites, dominant value 100 ms"*. P6.74 contradicted the project's own record and nobody
   caught it, **me included — P6.74 is my report.**
3. ★★★★★ **The port does not pace.** The wait is **0.2% of a castle cycle** (0.00067 s of 0.300),
   0.9% of a title cycle, measured by the write-tapped stage timer in emulated time. **§6's "pacing
   is most of the cycle" trigger does not fire. §1.1's hypothesis is half confirmed**: the target
   IS a throttle and IS 10, not 20. The other half is killed: none of the 389 ms is deliberate
   waiting.

**The corrected table** (steady state, stages differenced so one-off renders cancel):

| scene | s/cycle | cycles/s | vs P6.74/P6.75 |
|---|---|---|---|
| title, no input (cycles 130-230) | **0.0667** wall; 0.0547 in stages | 15.0 | P6.75's **0.201** |
| castle, 4 sprites (cycles 20-55) | **0.3004** wall; 0.2930 in stages | **3.33** | P6.74's **0.389** |
| **KQ1's own throttle** | **0.100** | **10** | P6.74's 0.050 / 20 |

★★★★ **Why the old figures are high:** they are whole-run averages, and startup is heavy. The
56-cycle castle run spends **37.0 s** in all, of which cycles 1-20 take **~26.5 s** (title render,
castle render, first VIEW loads; `roomcheck` alone is 9.0 s). **26.5 + 170 × 0.300 ≈ 77.5 s over
190 cycles ≈ 0.41**, close to P6.74's 74.0 s / 190 = 0.389 on a slightly different binary
(arithmetic, unverified). P6.75's title 0.201 fits the same shape; I did not re-derive its run length.

#### §4B — the profile

**The instrument.** `P3B_PROFILE="A-B"` samples on `emu.wait(1/997)`, emulated time, **997 Hz, coprime
to 60, so the sample phase sweeps the video frame instead of sitting on one point of it**. Per sample:
**CURPC**, the MMU block behind it, and `P3_PHASE`. Castle: **10,482 samples** over cycles 20-55
(10.51 s). Title: **6,655** over cycles 130-230 (6.67 s).

★★★★★ **§2W — the instrument was shown able to fail, and it did, once.**
- **Its first version read `cpu.state["PC"]`** and put **41 title samples on one straight-line INIT
  instruction** (`$20B9`, `std txt_winon`), once per cycle, which nothing executes after boot. A
  targeted probe (`P3B_PROFILE_PC=20B9`) logged **CURPC = `$21B8` at the same instants**: MAME's "PC"
  is the 6809's fetch pointer, which mid-instruction already holds a jump target. Switched to
  CURPC; routine shares moved ≤ 1.4 points and the unexplainable address vanished. **Idioms §44.**
- ★★★★ **Cross-check against the exact instrument.** Per-stage sample shares against the write-tapped
  stage timer, as a fraction of wall:

  | stage | castle: profile / timer | title: profile / timer |
  |---|---|---|
  | composite | **81.4% / 81.3%** | 0.0% / 0.1% |
  | interpret | **14.6% / 14.6%** | **74.9% / 74.9%** |
  | sprites | 1.4% / 1.4% | 6.0% / 6.0% |
  | pace(wait) | 0.2% / 0.2% | 0.9% / 0.9% |
  | outside stages | 2.3% / 2.5% | 17.9% / 18.1% |

  **Two workloads whose split differs by 70 points, and the profiler followed the timer within 0.2
  points on every row.** A mis-attributed stage byte or a mis-scoped window would break this.
- **It does not perturb the guest.** Stage totals were identical to four decimals under 997 Hz and
  60 Hz sampling. **Deterministic**: two 997 Hz castle runs gave identical histograms.

★★★★ **THE SAMPLER'S BIAS, STATED AND BOUNDED.** The same castle window sampled **frame-locked at
exactly 60 Hz** (the stall sampler's regime, 630 samples) differs from the 997 Hz profile by
**≤ 1.0 point on every subsystem**: compositor −0.9, plane window +0.8, VM +0.5, others ≤ 0.4. At 630
samples the binomial error on a 38% share is ≈ 1.9 points, **so the frame-lock bias is below what the
60 Hz arm can resolve.** Small **because this workload runs flat out and is not VBL-synchronised**
(pace 0.2%). The VBL-synchronised code, the IRQ handler, is 0.1% either way. **The 997 Hz table
carries no correction and needs none.** Its own residual error is sampling (±0.5 points at 38% with
10,482 samples).

**Attribution method (a heuristic, stated):** a *routine* is a label that is the target of
`jsr/bsr/lbsr/jmp` or appears in an `fdb` table (360 found), plus `p3_loop`, entered by fall-through
and named explicitly. A sample is charged to the nearest routine at or below it. Subsystem is by
defining file, and by name within `p3b_probe.s` (`pc_profile.py`, table in one home).

**CASTLE — top 25 routines** (cycles 20-55, 4 sprites, 10,482 samples, 997 Hz, CURPC)

| # | routine | file | subsystem | share |
|---|---|---|---|---|
| 1 | `cp_composite` | composite.s | compositor | **21.3%** |
| 2 | `vc_decode_row` | view_cel.s | cel decode | **16.9%** |
| 3 | ★★★★★ `res_fetch` | res_core.s | resource manager | **15.9%** |
| 4 | ★★★★★ `co_inc32` | composite.s | compositor (instrumentation) | **11.9%** |
| 5 | `plane_pri` | plane_win.s | plane window | 6.8% |
| 6 | `prp_copy` | p3b_probe.s | restore walk | 3.6% |
| 7 | `co_put_visual` | composite.s | compositor | 3.3% |
| 8 | `plane_vis` | plane_win.s | plane window | 3.1% |
| 9 | `vm_update_position` | vm_objects.s | object motion | 2.1% |
| 10 | `vm_test_if_code` | vm_core.s | VM | 2.1% |
| 11 | `p3_stage_sprites` | p3b_probe.s | compositor | 1.4% |
| 12 | `HAL_key_scan` | hal_globals.s | key scan | 1.3% |
| 13 | `vm_run_logic` | vm_core.s | VM | 1.1% |
| 14 | `prp_priority` | p3b_probe.s | restore walk | 0.7% |
| 15 | `p3_key_latch` | p3b_probe.s | key scan (harness park) | 0.7% |
| 16 | `prp_visual` | p3b_probe.s | restore walk | 0.6% |
| 17 | `vm_getflag` | vm_state.s | VM | 0.5% |
| 18 | `prp_split` | p3b_probe.s | restore walk | 0.4% |
| 19 | `co_checkctrl` | composite.s | compositor | 0.4% |
| 20 | `vm_op_return` | vm_core.s | VM | 0.4% |
| 21 | `vm_skip_instruction` | vm_core.s | VM | 0.3% |
| 22 | `vm_setflag` | vm_state.s | VM | 0.3% |
| 23 | `res_ptr` | res_core.s | resource manager | 0.3% |
| 24 | `p3_loop` | p3b_probe.s | harness park | 0.3% |
| 25 | `vc_decode_begin` | view_cel.s | cel decode | 0.3% |
| | **top 25** | | | **96.0%** (84 routines seen) |

Labels inside those rows: `rfe_word` (the resource copy's word loop) **15.5%**; `co_inc32` 8.6% +
`co_i32_out` 3.3%; `co_pix` 8.5%; `co_depth` 4.3%; `pp_have` (in `plane_pri`) 3.6%; `vc_dc_*`
(decode inner loop) ~15% across nine labels.

**CASTLE — by subsystem, sums to 100%** (dispatch's categories; the compositor split as it asked)

| subsystem | share | of which |
|---|---|---|
| compositor | **38.5%** | pixel loop `cp_composite` 21.3 · **counters `co_inc32` 11.9** · `co_put_visual` 3.3 · staging 1.4 · `co_checkctrl` 0.4 · `co_depth` is inside `cp_composite` (4.3 by label) |
| cel decode | **17.2%** | |
| resource manager | **16.8%** | ★★★★ `res_fetch` 15.9 — VIEW copies, in BOTH the composite stage (≈1,110 samples) and interpret (≈550) |
| plane window access (`plane_pri`/`plane_vis`) | **10.0%** | pri 6.8 · vis 3.1 · `pl_map_vis` 0.3 |
| VM interpret | 6.4% | |
| restore walk | 5.5% | |
| object update / motion | 2.3% | |
| key scan | 2.0% | ~0.7 of it is the harness park's latch |
| MMU phase switches | 0.4% | |
| harness handshake park | 0.3% | harness only |
| **pacing wait** (`vm_pace`/`vm_step_clock`/timer) | **0.3%** | |
| IRQ handler | 0.1% | |
| parser · text · picture | 0.1% | |
| **SUM** | **100.0%** | 10,482 samples |

**TITLE — baseline** (cycles 130-230, no input, 6,655 samples): **VM interpret 73.1%** (`vm_test_if_code`
25.8 · `vm_run_logic` 10.2 · `vm_skip_instruction` 7.9 · `vm_skip_until` 7.3 · `vm_getflag` 6.3 ·
`vm_op_return` 4.7) · **harness park 9.4% + its key latch 8.4%** · `p3_stage_sprites` 6.0% (it walks the
whole object table even with nothing to draw) · VM cycle/pacing 1.4% · resource 0.8% · parser 0.4% ·
other 0.5% = 100%. Top 25 routines cover 97.6%; full table in `pc_profile.py`'s output, reproducible
by the command in §5.

★★★★ **The sprite cost, which is Jay's hypothesis:** castle stages 0.2930 − title stages 0.0547 =
**0.238 s per cycle for four sprites**, and the composite stage alone is 0.244. **Four sprites cost
~4.4× what the whole interpreter costs on an idle screen.**

#### §4C — the budget in CPU cycles

At the measured **1.789772 MHz**:

| | s | CPU cycles |
|---|---|---|
| castle steady cycle, wall | 0.3004 | **537,600** |
| of which port stages | 0.2930 | 524,400 |
| ★ dispatch's figure (0.389, whole-run) | 0.389 | 696,000 |
| **budget: 100 ms (var 10 = 2)** | **0.100** | **179,000** |
| non-composite castle work (interpret + sprites + pace) | 0.0488 | 87,300 |
| **left for the composite stage** | 0.0512 | **91,700** |
| composite stage now | 0.2443 | 437,200 |

★★★★★ **Ratio 3.0× on the whole cycle, and 4.8× on the composite stage, which must carry it.**
(Arithmetic from measured inputs, unverified as arithmetic.) The title fits: 0.0547 s = 97,900
cycles, 55% of budget.

> ★★★★★ **Structural.** The composite stage is one stage at 81% of the cycle, but no routine in it
> exceeds 21%, and removing the three largest avoidable costs outright (VIEW re-fetch 16.8%, pixel
> counters 11.9%, plane-window calls 10.0%) still leaves ~330,000 cycles, **1.8× over**. Closing the
> gap needs the per-pixel and per-row work itself to get cheaper.

(Removal arithmetic assumes each cost goes to zero and nothing else moves. **Unverified.**)

#### §4D — the candidates, named and NOT pursued

**1. Compositor, 38.5%.**
- ★★★★★ **The per-pixel counters: 11.9%, and the switch already exists.** `cp_composite` calls
  `co_inc32` — a 32-bit software increment through `U` — for **every source pixel** (`co_tested`) and
  again per reject/control hit [`composite.s:181-191, 236-239, 347-350`]. `-DCOMP_NOCOUNT` removes all
  of them; **the combined arm does not set it.** *Cheaper version:* set it in the shipped arm.
  *Risk:* the counters are the comp gate's and p3b's composited-vs-staged instruments
  (`CP_TESTED`/`CP_WRITTEN` etc.); a gate reading them needs its own counting arm, which is §2W's
  pairing in reverse. **Check before switching**: does the comp gate's fault detection read the
  counters or the planes?
- **The pixel loop keeps its state in memory.** Per pixel: `ldx co_src / lda ,x+ / stx co_src`,
  `inc co_curx`, `dec co_remw`, `lbra co_pix`, all extended addressing [`composite.s:173-179,
  352-355`]. *Cheaper:* hold the source pointer and the count in registers across a row. *Risk:*
  every `jsr plane_pri` clobbers `X`, so this is coupled to item 4.

**2. Cel decode, 17.2%.** `vc_decode_row` unpacks every sprite's cel every cycle, whether or not the
cel changed. *Cheaper:* decode once per cel change and keep the rows. `p3_prev` already records
view/loop/cel per sprite [`p3b_probe.s:2831-2836`], which is the key a cache needs. *Risk:* a decoded
4-sprite set does not fit the memory the row-pull design freed (`CP_CEL` shrank from 4,784 B to
`VC_ROW_MAX` for exactly this reason [`p3b_probe.s:2781-2784`]), and row-pull was a deliberate port
decision [`composite.s:150-158`].

**3. Resource manager, 16.8%: ★★★★★ the one nobody expected.** **Every sprite's whole VIEW is copied from
the volume window into the arena on every cycle.** `p3_composite_all` invalidates `res_curblk` and
calls `res_open(VIEW)` per sprite [`p3b_probe.s:2728-2732`]. `res_open` caches **LOGIC only**
[`res_core.s:222-225`]. And the VM does it again: `vm_set_cel`/`vm_set_loop` open the object's whole
VIEW to read **four header bytes** [`vm_run.s:243-251, 297-335`]. `rfe_word` alone is 15.5%.
★★★★ **This is L-66 again, for VIEWs**: the LOGIC re-copy was 3.01× per cycle and the cache cut it
[design §5.4a]. *Cheaper:* (a) extend the cache to VIEWs; (b) read the VIEW in place through the
volume window; (c) for set.cel/set.loop, read the four bytes through `res_ptr` without copying.
*Risk:* (a) the arena is already contested: P6.67's draw.pic was refused with **1,084 bytes free**
at depth 2. (b) is **P6.74's defect class exactly**, because the compositor writes slot 6 between
fetches. (c) is the smallest change and the safest.

**The dispatch's two known candidates:**
- **4. Per-access `plane_vis` — CONFIRMED, smaller than P6.52's 15.7%**: plane window access is **10.0%
  now, and the priority side is the larger** (`plane_pri` 6.8%, `plane_vis` 3.1%). *Cheaper:* map
  once per row, handle the straddling row explicitly. *Risk:* that straddle is why per-access was
  chosen [P6.52].
- **5. Restore traffic — CONFIRMED, but not top three**: the restore walk is **5.5%** (`prp_copy` 3.6%).
  *Cheaper:* extend P6.60's static-sprite skip. Worth ~5% at most.

### 4 — Verification (AC-by-AC)

- **AC-1 [citation · oracle] PASS** — `cycle.cpp:538-558` quoted (§4A.1); **var 10 = 2 in the castle**
  (reference trace, cycle 1, `v10=v88=2`; guest `vm_tdelay=6`); **nominal 10 cycles/s, 100 ms.**
- **AC-2 [measurement] PASS** — pacing wait **0.00067 s = 0.2% of a castle cycle**, 0.9% title;
  write-tapped stage timer, emulated time. Every wait listed with its site (§3(2)).
- **AC-3 [measurement] PASS** — top-25 routines and subsystem roll-up summing to 100%, castle and title.
  Bias measured by a 60 Hz arm, ≤ 1.0 point. Profiler cross-checked against the stage timer within
  0.2 points, and shown able to fail (PC → CURPC).
- **AC-4 [measurement] PASS** — 537,600 vs 179,000 CPU cycles, **3.0×**; the composite stage must
  shrink 4.8×. **Structural**, sentence in §4C.
- **AC-5 [measurement] PASS** — three subsystems plus the two known candidates, cheaper version and
  risk each, none pursued.
- **AC-6 [byte-comparable] PASS, with the stated exception** — `git diff --stat -- src/`:
  `src/harness/p3b_probe.s | 18 ++++++++++++++++++` — **comments only** (§9's parking note, which the
  dispatch requires in that file). **All 8 arms byte-identical, SHA-256** (§5). No profiling flag in
  `src/`: the profiler is host-side, in `p3b_run.lua`.
- **AC-7 [suite] PASS, by a full run, not a citation** — `src/` was touched (comments), so I did not
  rely on §2T: `run_gates.sh all` all green (§5).
- **AC-8 [ruling requested]** — §7.1, addressed to Jay.
- **AC-9** — one candidate (§10).

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
> git diff --stat -- src/
 src/harness/p3b_probe.s | 18 ++++++++++++++++++
 1 file changed, 18 insertions(+)

> harness/tools/p3b_arms_check.ps1
p3b         15484 B  3F4BDC80  OK
p3b_text    16715 B  2463C537  OK
p3b_win3    16715 B  ED4243EC  OK
p3b_notick  16712 B  02BFEBD5  OK
p3b_nomap   16712 B  B37C6E92  OK
p3b_fault   15747 B  AEBC7C44  OK
p3b_flat    15732 B  DD0A2E91  OK
p3b_comb    18703 B  5F96E2BD  OK
★ all 8 arms byte-identical to the recorded baseline (SHA256)

> bash harness/tools/run_gates.sh all      (tail)
★ p3b headless: 60 cycles, no stall
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
```

(`run_gates.sh` runs `fix_mojibake.py --check` first; it passed. §2J.5 held this task: every tracked
file was edited with the Edit/Write tools.)

**The profile runs** (`p3b_show.ps1 -Title Kingquest1 -Headless -Combined`, env as named):

```
castle  P3B_ROOM=1 P3B_ROOM_AT=8 P3B_PROFILE=20-55  -Cycles 56
PROFILE: 10482 samples at 997 Hz over cycles 20-55 -> build\p3b_headless/profile.txt
    clock MEASURED 1.789772 MHz (160009 cycles calibrated)
castle  ... P3B_PROFILE_HZ=60
PROFILE: 630 samples at 60 Hz over cycles 20-55
title   P3B_PROFILE=130-230  -Cycles 231
PROFILE: 6655 samples at 997 Hz over cycles 130-230
  -> python harness/tools/pc_profile.py <profile.txt> build/p3b_probe_pk.map [--vs <60 Hz profile>]
```

**The stage timer, differenced** (run(55) − run(20) castle; run(230) − run(130) title):

```
CASTLE (4 sprites) : 35 steady cycles        TITLE : 100 steady cycles
  composite   8.5486 s  0.24425 s/cycle 83.4%   interpret  4.9995  0.05000 91.4%
  interpret   1.5318    0.04377         14.9%   sprites    0.4014  0.00401  7.3%
  sprites     0.1495    0.00427          1.5%   pace(wait) 0.0623  0.00062  1.1%
  pace(wait)  0.0233    0.00067          0.2%   composite  0.0034  0.00003  0.1%
  roomcheck   0.0011    0.00003          0.0%   roomcheck  0.0032  0.00003  0.1%
  SUM        10.2543    0.29298                 SUM        5.4698  0.05470
  wall       10.5136    0.30039  (97.5%)        wall       6.6752  0.06675  (81.9%)
```

**25.2 bundled-artifact grep:** N/A — no artifact is shipped by a measurement task.
**25.3 operator-runtime-smoke:** N/A. Nothing the screen shows changed: the `src/` delta is comments
and all arms are byte-identical. This is not an integration task (§4A).

### 6 — Reactive deviations and route accounting

- **The profiler samples off the frame instead of using the stall sampler as-is.** The dispatch says
  "run it continuously" and "state the bias". I built a second sampler so the bias could be
  **measured** (60 Hz arm vs 997 Hz). The stall sampler is untouched apart from its §9 note.
- **The castle window stops at cycle 55**, not an open-ended "long" window: a message box at cycle 57
  blocks cycling headless (P6.75 §7, pre-existing). 35 cycles × 0.3 s still gave 10,482 samples.
- **AC-7 by a full suite run, not by §2T citation**: `src/` had a comment change.
- **§9 `memmap.inc:310` `MAP_PRI_BANDS` NOT done. It has now been carried for 23 tasks.** §6 lists
  `memmap.inc` as a stop trigger and AC-6 wants `src/` empty, so this task cannot also be the one
  that edits it. It needs a task where touching `memmap.inc` is in scope.
- **Route accounting:** everything I proposed is in the commit. No optimisation. The one instrument
  change I made mid-task (PC → CURPC) is described in §3/§4B, and its first-version output is not
  quoted as a result anywhere.

### 7 — Uncertainty flags

#### 7.1 ★★★★★ For Jay — where the time goes, whether the target was right, what to attack first

**Where the time goes.** In the castle with four sprites, one cycle takes **0.30 seconds**, so the game
runs at **3.3 cycles a second**. **81% of that is drawing the sprites.** The game's own logic, the
thing that decides what happens, is **15%**, and the port waits for **nothing** (0.2%). With nothing
moving (the title screen) a cycle takes 0.055 s, so the interpreter itself is fast enough. **The four
sprites are the problem**, and they cost about four times the rest of the interpreter put together.

**Was the target right? No, and the real gap is smaller than we thought.** KQ1 asks for **10 cycles a
second, not 20**. It sets its speed variable to 2 on the first cycle, and ScummVM turns 2 into 100 ms.
The design spec already said the corpus runs at 10; my P6.74 report quoted 20, and that was wrong. And
the 0.389 s we have been quoting included the room-drawing at startup. **So we are 3× too slow, not
8×.**

**Your hypothesis — keys arriving faster than the game can decide and render — is consistent with
this.** At 3.3 cycles a second the game looks at the keyboard every 300 ms; at 10 it would look
every 100 ms, which is the rate the game was written for.

**What to attack first — two things, both removals of work the cycle does not need:**
1. ★★★★★ **Stop re-copying every sprite's picture data on every cycle** (16.8%). Each cycle the port
   copies each sprite's complete VIEW, several KB, from the game data into working memory, and then
   the game logic copies it again to read four bytes. The game logic already had this problem, and a
   cache fixed it. Safest first step: read those four bytes without the copy.
2. ★★★★ **Turn off the pixel counters in the shipped build** (11.9%). The compositor adds 1 to a
   32-bit counter for every pixel it looks at. That is a measuring instrument left switched on, and
   there is already a build switch that removes it. It needs one check first: whether a gate reads
   those counters.

**Expected from both together: about 0.30 → 0.21 s, roughly 4.7 cycles a second (arithmetic, not
measured).** ★★★★ **That is not enough on its own.** The rest is the per-pixel drawing loop and the
cel unpacking. Those need restructuring rather than switching off, and they are the task after.

#### 7.2 Other flags
- **The port has no real-time pacing at all** (§3(2)). Harmless while it is 3× slow. Once it gets
  under 100 ms it will run too fast, and a VBL-based pace will be needed. The comment at
  `p3b_probe.s:1224` describes `vm_pace` as a real wait. It is not one.
- **Design spec §7.1's "CURRENT: 0.03929 s per cycle at four sprites" [AD-109]** is `comp_probe`'s
  figure, with host-staged VIEWs. **The integrated composite stage measures 0.244 s, 6.2× that.** The
  VIEW re-fetch, windowed planes and restore walk are the obvious differences, but I have not
  decomposed the 6.2×. PROPOSED TEXT below.
- **Attribution is a heuristic** (routine = called label). A routine reached only by fall-through
  folds into the one above it. One was found (`p3_loop`) and named; the per-label table is printed
  so a reader can see what each routine row contains.
- **`co_depth` is a label inside `cp_composite`**, so the dispatch's "compositor (… `co_depth` …)"
  breakdown reports it by label (4.3%), not as a routine.
- **P6.75's title 0.201** is reconciled by inference (whole-run averaging), not by re-deriving its run
  length.
- **The 50 ms unit is ScummVM's comment about the original** (§2.1), not checked against the running
  original. The var-10 value itself is measured.
- **The HAL_key_scan DP lead in the parking note is unverified** and is marked `[no-ref: … discharge at
  re-open]` in the source.
- ★★ **Pool schema defect, mine:** P6.75's row `2026-09-21-a-faster-sensor-sees-the-noise-the-slow-one-
  averaged-away` has `initiator: user`, which is not a schema value (`executor | orchestrator | n/a |
  unknown`, pool `SCHEMA.md:47`). Faithfully it is `orchestrator` (Jay's eye gate surfaced it). **Not
  edited**: pool rows are new-only (§2C). Left for the reconciler.

### 8 — Follow-up candidates

1. ★★★★★ **P6.77: remove the VIEW re-copy.** Start with (c) (set.cel/set.loop read four bytes
   in place), then (a) or (b) for the compositor. Price each by the profiler, which now exists.
2. ★★★★ **`COMP_NOCOUNT` in the shipped arm**, after checking which gates read `CP_TESTED` and the
   other counters.
3. ★★★ **Restructure the pixel loop** (registers, per-row plane mapping): items 1b + 4 together.
4. ★★★ **Cel decode cache**, keyed on `p3_prev`'s view/loop/cel.
5. ★★ **Real-time pacing** (VBL-based `vm_pace`), needed as soon as a cycle fits in 100 ms.
6. ★★ `p3_stage_sprites` walks the whole object table every cycle: 6% of an idle title.
7. Carried: `MAP_PRI_BANDS` at `memmap.inc:310` (23rd task), the stale `$1F60` message, and the
   P6.75 backlog (latch, edge-vs-level in `p3_poll_dir`, faithful headless arrows, volume 2 / view 68,
   alligators leaving the moat).

**PROPOSED TEXT for the design spec [§2D — the Orchestrator's to fold in, not edited here]:**

> **§5.4a, after the table:** ★★★★★ *The rate is a THROTTLE, not a speed: v2 derives the cycle delay
> from var 10, 20/var10 cycles per second [cycle.cpp:538-558]. KQ1 sets var 10 = 2 at cycle 1, so it
> asks for 10 cycles/s, 100 ms = 179,000 CPU cycles at 1.79 MHz. The port reproduces the pacing gate
> as a VIRTUAL clock and does not wait in real time (0.2% of a cycle) [P6.76].*
>
> **§7.1, replacing "CURRENT":** ★★★★★ *INTEGRATED, KQ1 castle, 4 sprites: the composite stage is
> 0.244 s/cycle, 81% of a 0.300 s cycle, 6.2× comp_probe's 0.039 [AD-109]. Profiled: compositor
> 38.5% (per-pixel counters 11.9%), cel decode 17.2%, VIEW re-fetch 16.8%, plane-window access 10.0%,
> restore 5.5%. 4.8× over the 100 ms budget's composite share [P6.76].*

### 9 — User interaction during task
None. (The dispatch was received; no questions were asked.)

### 10 — Candidate(s) captured this task
- `2026-09-21-a-whole-run-average-is-not-a-rate` — pool commit in §11.

### 11 — Commit
(filled in by the follow-up commit)
