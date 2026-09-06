## Form B Report — P3b.22 / P3b.23 — The palette p3b did not load, and the gates that ran to a clock

**Class:** build. wip. ★★★ **Two pieces, attributed separately per L-54: A is the Orchestrator's
note on the palette, B is Jay's instruction on throttling.**

---

### §4 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===       wip  04bf97d at start -> 02badf7 at report
=== POP3_port ===      wip  104b197  unchanged from P3b.21 §4
=== karateka_coco3 === wip  29f8f0a  unchanged from P3b.21 §4

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s)   -- unchanged

gate   artifact                  shipped    fresh  verdict
pic 2654 | pic_nc 2524 | pic_nc_pk 2983 | pic_win 2667 | res 2055
cel 1472 | comp 967 | vm 8748 | p3b 13052          ALL NINE IDENTICAL

clock MEASURED 1.789772 MHz (160009 cycles calibrated)      [L-78]
```

★★ **§2T:** siblings cited from P3b.21 §4, both HEADs unchanged.
★ **Artifact sizes moved in this task and are accounted for in §3.A.4** — they are not drift.

---

### 1 — Summary

★★★★★ **A — the Orchestrator's note was right, and the tap proved it before anything changed.**
A write tap on `$FFB0`–`$FFBF` across a full p3b run recorded **16 writes, every one from PC
`$C00F` — Disk BASIC's ROM — and ZERO from the guest.** `p3b_show.lua` asserted the table from the
host on every frame, so **the three rooms Jay approved at AC-1 were coloured by the harness** and
the pass said nothing about p3b. ★★★ **L-86's shape one level up: a pass whose cause sits outside
the thing under test.**

★★★★ **The reason was that T-P0-056b consolidated the DATA and left the MECHANISM behind.**
`agi_pal_load` lived in `pic_probe.s`, so p3b could reach the table and had no way to install it.
Both routines now sit beside the table in `content/agi_palette.s`; p3b calls the loader at init.
**Re-proved: 16 guest writes from PC `$5005`, all 16 matching `content/agi_palette.s`.**

★★★★★ **B — the gates ran to a clock, and now they do not.** The renderer gate took **312.7 s at
99.98% speed**; unthrottled it takes **16.5 s at 2869%** — **19×, with 45/45 PASS and every
per-picture hash identical.** Verified the same way for cel, comp and p3b, then made the default.
**The full suite went from 403.7 s to 74.8 s.** ★★ **Jay's visual gate is excluded by instruction
and by what it is for**, and `p3b_show.lua` now carries a standing note saying so.

★★★ **Two defects of mine are reported below rather than quietly repaired: an instrument that
would have called the working palette fix a failure (§3.A.3), and an edit that broke the cel gate
while the gate still reported 100% (§3.B.3).**

---

### 2 — Files modified

**A:** `content/agi_palette.s` (loader + guarded readback) · `src/harness/pic_probe.s` (delegates;
declares `AGI_PAL_READBACK`) · `src/harness/p3b_probe.s` (calls `agi_pal_load`) ·
`harness/tools/p3b_show.lua` (host palette write REMOVED) · `harness/tools/p3b_palwatch.lua` (new).

**B:** `harness/tools/run_gates.sh` · `cel_run.sh` · `run_comp_sweep.sh` · `pic_variants.sh` ·
`vm_ablate.ps1` (all `-nothrottle` + `MAME_EXTRA`) · `p3b_show.lua` (the do-not-add note).

---

### 3 — Reasoning

#### 3.A.1 ★★★★★ The measurement that came first

The note said the palette was *"almost certainly left there by something else"*. **A write tap
settles it without the readback ambiguity** — a host-side READ of `$FFB0`–`$FFBF` tests MAME's
palette model rather than the guest's writes, which is why AC-11 read them from inside the guest
[`pic_probe.s` says so]. A tap asks the one question with no such ambiguity: **did any instruction
store here.**

```
★ PALETTE WRITE TAP on $FFB0-$FFBF, host wrote none of them
   guest writes observed: 16
   values (bits 7-6 masked): $12 x16
      PC $C00F  16 write(s)
   ★★★ guest writes 0, non-guest writes 16
```

★★★ **Sixteen identical values is no palette at all** — it is a boot-time initialisation, and
`$C00F` is ROM. **p3b wrote nothing.**

#### 3.A.2 ★★★★ Why consolidating the data was half a fix

T-P0-056b gave the table one home and **left the only routine that installs it inside a renderer
probe.** p3b could `fdb` the symbol and had no loader. ★★ **A second copy of the loop in p3b would
have been the duplication T-P0-056b had just removed, one level down**, so the loop moved to the
palette's own file and `pic_probe.s` delegates to it.

★★★ **NOT `HAL_gfx_set_mode`, deliberately.** It would load mode 2's palette for us **and** remap
slot 6 to a GFX_DB block, tearing p3b's framebuffer slice out from under it — a hazard
`p3b_show.lua`'s own header records. The palette is wanted; the MMU side effects are not.

#### 3.A.3 ★★★★ An instrument that would have called the fix a failure

The tap classified the guest as `$2000-$3FFF`. **p3b's code region is `$2000-$5300`**
[`memmap.inc`], and the working fix writes from **PC `$5005`** — so the first re-run reported
`guest writes 0` and *"p3b WRITES NO PALETTE"* about a build that had just been fixed.

> ★★★ **A tap that answers "who wrote this" is only as good as its idea of where the guest is**,
> and 13 KB of guest code does not fit in 8 KB.

★★ It is corrected in the file with the reasoning attached, and it now also compares the observed
values against `content/agi_palette.s` rather than against a copy in the script.

#### 3.A.4 ★★★★ Four bytes spare, and that is the finding

p3b's code region is `$2000-$5300` = **13,056 B**, and the build had **27 B** spare. The loader
plus its call site is 23 and fits. **Adding the readback is 25 more and does not** — the build
failed with *"P3b code overruns the map's code region"*.

★★★ So `agi_pal_readback` is guarded on `AGI_PAL_READBACK`, which `pic_probe.s` declares **in its
own source** (the `PLANE_WIN_MMU` idiom — a symbol on a command line is a fact nobody can see from
the source [AD-119]). **p3b now builds at 13,052 of 13,056: four bytes spare.** ★★ **Reported
because the next addition will not fit**, and because the map allocation P6.1 flagged as *"an
allocation to be checked, not a measurement"* has now been checked by being hit.

Artifact sizes this task: `pic` 2642→2654, `pic_nc` 2512→2524, `pic_nc_pk` 2971→2983, `pic_win`
2655→2667, `res` 2035→2055, `cel` 1452→1472, `vm` 8728→8748, `p3b` 13029→13052, `comp` **967
unchanged** (no mode service, so it links none of it).

#### 3.A.5 ★★★★★ The host no longer supplies what the program must

`p3b_show.lua`'s per-frame palette write is **removed**. ★★★ **Leaving it would keep the display
correct and the program wrong, which is the exact condition that hid this for four tasks.** The
display now shows what the program establishes; if that regresses, the colours go wrong and
someone sees it.

★ **AC-1 is not withdrawn** [the note says so and I agree]: Jay saw three rooms render correctly
and the planes are byte-identical to the oracle. **What was unproven — that p3b PRODUCES that
state — is now proven.**

#### 3.B.1 ★★★★★ B: the gates ran to a clock

MAME paces to emulated real time by default, so a gate emulating 308 seconds spent 308 seconds of
Jay's day. Measured per gate, against baselines already held rather than re-runs:

| gate | throttled | unthrottled | verdict |
|---|---|---|---|
| **pic** | **312.7 s @ 99.98%** | **16.5 s @ 2869%** | 45/45 PASS, every per-picture hash identical |
| **cel** | ~380 s | **35.2 s** | 9193/9193; 118/814, 207/1189, 216/1861, 220/2411, 238/1728, 151/1190 |
| **comp** | 72 s | **42.9 s** | nine corpora, 20/20 each, 0 divergent |
| **p3b** | 83 s | **17 s** | pictures 22/1/3/83 at 0.0% on both planes |
| res | — | — | **already `-nothrottle`**; 1264/1264 |
| vm | — | — | **already `-nothrottle`** |

**Full suite (pic+res+cel): 403.7 s → 74.8 s.**

#### 3.B.2 ★★★★ Why it cannot change a result here, which is the part worth writing down

★★★★★ **Emulation is deterministic and throttle paces the HOST.** ★★★ **Nothing in this harness
measures wall clock** — every timing call in every sweep is `m.time:as_double()`, which is
**emulated** time. ★★ **That is not luck:** L-78/AD-100 moved this project off host-side intervals
after one was found to be the wrong instrument, and `VP_MARK` exists for the same reason.

★★★★ **And two gates had been proving it quietly for many tasks.** `res_run.ps1` and `vm_run.ps1`
have passed `-nothrottle` all along. **The suite was half-paced and nobody had noticed** — which is
also why no re-verification was owed for those two.

★★ **The note's other premise is corrected:** the early-exit fix it proposes **is already in the
tree**. `pic_sweep.lua:187`, `cel_sweep`, `comp_sweep`, `vm_sweep` and `pal_gate` all call
`machine:exit()`. `-seconds_to_run` is a safety net, not a budget that is always spent — the 312.7 s
was real emulated work.

★ **Parallelism was considered and rejected as the riskier option** [Jay asked directly]: it
multiplies a hazard this project has already been burned by — the `-cfg_directory` write-back of
P3-2 §3.9 — plus nvram and `build/` path collisions and CPU contention. `-nothrottle` touches
nothing the gates measure.

#### 3.B.3 ★★★★★ I broke the cel gate and the cel gate reported 100%

The first `cel_run.sh` edit put a `# shellcheck` comment **between the `CEL_STAGE=... \`
continuation and the MAME line.** The environment prefix then applied to the **comment**, so every
title ran with the previous title's settings:

```
═══ Kingquest2 ═══   ★ 118 views staged, 814 cels decoded -> build/cel_sweep
═══ Kingquest3 ═══   ★ 118 views staged, 814 cels decoded -> build/cel_sweep
      ... six runs of Kingquest1, into the wrong directory ...
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
```

★★★★★ **The headline number was still green**, because `celcheck.py` adjudicated the **per-title
directories left by the previous good run.** ★★★ **The pass survived the gate not running** —
L-72 exactly, and precisely the risk the note flagged in touching the runners.

★★★ **What caught it was not the verdict but the per-title counts**, all six identical to
Kingquest1's. The repaired run was made against a **cleared** output directory. ★★ The failure mode
is now documented in `cel_run.sh` so the comment does not get reinserted.

#### 3.C Authority tiers

Every figure is fresh tool output on this machine (25.1). Oracle planes and cel bytes are the
reference per §2O.1. §2H: the **second mechanism** is §3.A.2's data-vs-mechanism split; the
**caller** is named at each step; the **prior-report grep** is what found P4.4 in the addendum and
was run again here before claiming the palette had no other home.

---

### 4 — Verification (AC-by-AC)

The note carried no AC list; these are its §3 asks and Jay's instruction, answered in order.

- **A-1 [class: state-comparable] — ANSWERED. The pass WAS inherited.** Write tap, §3.A.1: 16
  writes, all PC `$C00F` (ROM), zero guest. ★★ **Reported as the finding, not as a failure**, per
  the note.
- **A-2 [class: byte-comparable] — PASS.** p3b loads the palette from `content/agi_palette.s` at
  init. Re-run tap: **16 guest writes from PC `$5005`, all 16 matching the file.**
- **A-3 [class: byte-comparable] — PASS.** Renderer gate **45/45 both planes**; p3b pictures
  22/1/3/83 **0.0% on both planes**; `gate_audit` **9/9 identical**; `hal_sync` OK in three;
  `reg_discipline` unchanged at 8/1/2 — the loader writes `$FFB0`–`$FFBF`, which is the HAL's own
  range and is reached from a file included **by** `hal_globals.s`, so no new owner (§2N).
- **A-4 [class: state-comparable] — the provenance line the note asked for.** Every run now prints
  `palette: 16 entries EXPECTED from content/agi_palette.s [P4.4 AC-11/AC-12] -- INSTALLED BY THE
  GUEST  idx2=$10 idx6=$22 idx15=$3F`. ★★ **The readback the note also asked for did not fit**
  (§3.A.4) and the tap stands in its place; that substitution is stated, not glossed.
- **B-1 [class: state-comparable] — PASS.** All gates run unthrottled, verdicts identical (§3.B.1).
- **B-2 [class: byte-comparable] — PASS.** `-nothrottle` is now the default in five launchers.
  `MAME_EXTRA=-throttle` restores pacing.
- **B-3 [class: eye-gated] — the visual gate stays throttled**, per Jay. `p3b_show.lua` carries a
  standing note; its dump twin (`p3b_room.lua`, no display) is unthrottled.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — A, before and after:**

```
BEFORE  guest writes observed: 16   PC $C00F  16 write(s)  rom/other
        ★★★ guest writes 0, non-guest writes 16
        ★★★★★ p3b WRITES NO PALETTE. Any correct colour on screen is INHERITED.

AFTER   guest writes observed: 32
        values (masked): $00 $08 $10 $18 $20 $28 $22 $38 $07 $0F $17 $1F $27 $2F $37 $3F
        PC $C00F  16 write(s)  rom/other        PC $5005  16 write(s)  ★ GUEST
        ★★★★★ p3b WRITES ITS OWN PALETTE, and all 16 match content/agi_palette.s
```

**25.1 — B, the suite on the new defaults:**

```
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
118/814  207/1189  216/1861  220/2411  238/1728  151/1190
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ gates run: pic res cel  -- all green
TOTAL wall, all gates, new defaults: 74.8 s      (403.7 s before)
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact; the nine gate binaries are byte-identical
to their sources (§4).

**25.3 operator-runtime-smoke: PASSED earlier this session** — Jay, live, `poke`, RGB, on the
castle, room 22 and picture 3: ***"all three look good."*** ★★ **Not re-run after A**, and that is
the one thing outstanding: the display no longer supplies the palette, so a cold run is now a real
test of the guest. **Offered, not claimed** (§7.1).

---

### 6 — Reactive deviations and route accounting

- **A was a note, not a dispatch**, and its §3 verification was performed as specified except for
  the readback, which did not fit (§3.A.4) — **substitution stated**.
- **B was Jay's instruction** and is implemented as given, including the exclusion.
- **ROUTE ACCOUNTING.** I proposed no route. ★★ **What I did NOT do:** widen `MAP_CODE_END` to make
  room for the readback (a map change, not mine to make); make parallelism changes (rejected,
  §3.B.2); re-run the eye gate after A.
- ★★★ **A correction I owe on the record.** When Jay asked *"are sure youre running unthrottled"* I
  probed, got `MAME_EXTRA=[]`, and told him the flag never reached MAME. **That was wrong** — my
  probe was mangled by nesting PowerShell → cmd → `sh -c` with a `$`. Re-run through a script file
  it reads `MAME_EXTRA=[-nothrottle]`, and the arithmetic confirms it (308 emulated s ÷ 28.7 =
  10.7 s + build ≈ 16.5 s). **The challenge was right to make; my answer to it was not.**

---

### 7 — Uncertainty flags

1. ★★★★ **The eye gate has not been re-run since the host stopped supplying the palette.** Every
   byte check passes, but the thing Jay actually looks at now depends on p3b's own load.
2. ★★★★ **p3b has four bytes of code region left.** The next addition fails the build. ★★ This is
   not a soft limit — it is an assemble-time `error`.
3. ★★★ **p3b's palette load depends on the host having set the video mode first** [gfx.s
   Constraint B: palette writes may not latch until `$FF98`/`$FF99` are final]. The host sets mode
   2 before staging, so it holds today. **A p3b that boots without the harness would need to set
   its own mode**, and §2N says the HAL owns those registers.
4. ★★ **cel's throttled baseline is derived, not isolated** — taken from the `all` run rather than
   a dedicated throttled cel run, because Jay's instruction was to use the baselines already held.
5. ★ **`docs/gates/onehome22.priority.png` is untracked scratch** from a verification run. §2P
   permits committing a priority visualisation; I would rather delete it. **Jay's call.**

---

### 8 — Follow-up candidates

1. ★★★★★ **Re-run the eye gate cold** (§7.1) — the one outstanding item.
2. ★★★★ **The composite gate still cannot fail on the priority plane** — unchanged, still trigger 4
   [P3b.21 §3.D].
3. ★★★ **p3b's code region** — 4 bytes. Either reclaim (the init `p3_clear_planes` call is now
   partly redundant against `p3_black_visible`) or move `MAP_CODE_END`.
4. ★★★ **Give `celcheck.py` a staleness guard** — it adjudicated a previous run's output and
   reported 100% (§3.B.3). The same question applies to every adjudicator that reads a directory.
5. ★★ **`flag_diff --manifest` over-reports** — open across four tasks now.
6. ★ **5 of 9 composite corpora exercise zero priority rejections** [AD-126].

---

### 9 — User interaction during task

★★★★ **Recorded here per the note's instruction.**

- **The Orchestrator's note** — *"p3b still has no palette of its own, and AC-1 passed on state it
  did not set"*, quoting Jay: ***"p3b still doesn't have the palette incorporated properly."***
  Answered in full as A; its central claim was correct and is now measured rather than inferred.
- **Jay, on gate speed** — a note offering `-nothrottle`, parallelism and early exit as candidates,
  then the direct question ***"would splitting the gate out to multiple mame instances be safer
  than -nothrottle"*** (answered §3.B.2: no), then ***"are sure youre running unthrottled"***
  (answered, and my first answer was wrong — §6), then the instruction ***"run all your normal
  gates with -nothrottle, verify the results. if same, change all gates to use -nothrottle. my
  visual gate for p3b should still run throttled"*** — implemented as B.
- **Jay, on method** — ***"you should already have baselines"***, after I began re-running a
  throttled cel baseline I already held. **He was right; the re-run was abandoned** and every
  comparison in §3.B.1 is against a baseline already in hand.
- **Jay, earlier** — ***"all three look good. I closed the window manually"***, which closed AC-1
  and also explained a picture-3 run I had flagged as a possible intermittent early exit.

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-09-06-the-runner-and-the-adjudicator-are-different-programs.md`

---

### 11 — Commit

`f2ce3a1` (A, the palette) · `02badf7` (B, the throttle). Both pushed to origin/wip before this
report. This report lands in the follow-up commit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
