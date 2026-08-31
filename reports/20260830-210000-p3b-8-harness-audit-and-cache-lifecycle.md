## Form B Report — T-P0-039 (P3b.8) — Audit every harness, then the cache lifecycle
**Class:** build + recon.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `53352e2`, wip). Working tree dirty at t0 in the paths this task owns:
`harness/tools/{res_run.ps1,run_comp_sweep.sh,run_gates.sh,vm_load.ps1,vm_run.ps1}`,
`src/harness/{cel_probe.s,res_core.s}`, plus four new untracked tools. lwasm 4.24.

### 1 — Summary

The audit found the stale-binary defect was **the smallest of three defect classes**, and the two
larger ones were invisible to the instrument the dispatch anticipated. Staleness by mtime turned
out to be a **false positive on every artifact it flagged**: rebuilding all five gate probes and
byte-comparing showed every one identical to what its source builds now, including
`build/pic_probe.bin`, which was a full day stale by timestamp. The real defects were **wrong
flags** (four gates, four different flag sets, two of them recorded nowhere) and **wrong scope**
(three of five gates never ran their own adjudication step, and `run_gates.sh` printed partial
results with exit 0).

On the cache: `res_core`'s LOGIC cache had no owner because it had no bound. `res_ccur` grew
downward and was reset only by `vm_new_room`, so a caller with no VM starved. Eviction-on-
starvation at depth 0 closes that — `RES_E_BIG` is gone and all 1,264 resources fetch. **But the
gate is still not clean, and the ablation says the cache itself is why:** cache off gives
1,264/1,264 byte-identical; cache on gives 28 LOGIC mismatches, and 9 of them occur with eviction
compiled out entirely. **The LOGIC cache is incorrect independent of the lifecycle fix.**

Four gates re-run from freshly built artifacts are green: renderer 45/45, cels 9,193/9,193,
compositing 20/20, VM 9/9 titles byte-identical per cycle. The resource gate is green **only with
the cache ablated**.

★★ Two published figures turned out to be fossils that no command could reproduce: the cel gate is
**9,193 across 6 titles**, not 6,782 across 5, and the VM runner's default was **three** titles
where the gate is nine. Both were recovered and are now recorded in the runners.

### 2 — Files modified

- `harness/tools/gate_audit.py` — NEW. Classifies runners build-vs-consume, follows `.lua`
  program defaults, `--hash` (AC-3 stamp), `--check` (refuse a stale input), `--verify`
  (rebuild + byte-compare).
- `harness/tools/gates.manifest` — NEW. One home for each gate's source, artifact and **flags**.
- `harness/tools/res_aggregate.py` — NEW. Computes the 1,264 figure, which had no producer.
- `harness/tools/cel_run.sh` — NEW. The cel gate's runner, which did not exist.
- `harness/tools/run_gates.sh` — builds+stamps pic; delegates res and cel to real drivers; runs
  `picgate.py`; refuses to fake comp; header numbers corrected.
- `harness/tools/run_comp_sweep.sh` — assembles `comp_probe.bin` on the default path.
- `harness/tools/vm_load.ps1` — still does not build (deliberate); now **refuses a stale input**.
- `harness/tools/{res_run.ps1,vm_run.ps1}` — AC-3 source-tree stamp; `$env:RES_ASMFLAGS` hook.
- `src/harness/res_core.s` — `res_cache_evict`; evict-and-retry at depth 0; `res_evicted`,
  `res_cevict`; `ABL_NOCACHE`, `ABL_NOEVICT`.
- `src/harness/cel_probe.s` — `CEL_FAULT` (the cel gate had no fault mode).

### 3 — Reasoning

**§2H check 1 — is there a second mechanism?** Yes, and it was the governing one. "Stale harness"
names an artifact older than its source. The `res_run.ps1` incident in T-P0-037 was that. But a
gate can test the wrong thing three ways: **old code** (stale), **different code** (wrong flags),
**a different sample** (wrong scope). Only the first has a timestamp signature. Building the
mtime instrument first and stopping there would have reported three stale artifacts, fixed
nothing real, and left both larger classes in place.

**§2H check 2 — name the caller, not the implementation.** `res_cache_stash` fails closed and is
correct about its own job; it is not where the starvation lives. The starvation is a property of
**who calls the flush**: `vm_cycle.s:154`, reached only from `vm_interpret_cycle`. `res_core` has
three callers with three arena sizes (12,288 `res_probe` / 16,384 `p3b` / 21,760 `vm_probe`) and
**two of them have a VM**. The defect was invisible in both, and enlarging the arena would have
hidden it again at a new threshold.

**§2H check 3 — grep the reports before citing a characterisation.** This is where the cel figure
came apart. "6,782 cels across 5 titles" is cited by number across reports and appears in
`run_gates.sh`'s header. Aggregating the six staged titles gives **9,193**, and
9,193 − 2,411 (PoliceQuest1) = 6,782 exactly. PoliceQuest1 was staged later and the figure was
never updated. The gate was **stronger** than advertised — benign in direction, total in kind:
the published number could not be reproduced by any command, including the one printed beside it.

**★★★ The wrong-scope class has FOUR instances, not one, and it is the disease of this audit.**
Each gate's *scope* — the thing that makes its number mean what it means — lived outside the
runner:

| gate | recorded invocation produced | the gate is | where the scope actually lived |
|---|---|---|---|
| res | 74 fetches, exit 0 | 1,264 (10 volumes) | `res_run.ps1`'s loop |
| cel | 1 title | 9,193 (6 titles) | a hand loop in **no file** |
| pic | a sweep, no verdict | 45/45 | `picgate.py`, never called |
| VM | **3 titles**, "3 PASS" | 9 titles | `$env:VM_TITLES`, unrecorded |

In every case the partial run **exits 0 and prints a smaller number**, so it reads as a pass to
anyone who does not already know the expected total. **A gate's scope is part of its definition
and it kept living in an environment variable or someone's shell history.**

**★★ The audit's own instrument then caught the audit reintroducing the original defect.** The
`-DABL_NOEVICT` arm assembled to `build/res_probe.bin` — the artifact's normal path — leaving the
ablated program (2,021 bytes) where the clean one (2,019) belongs. Any later run that did not
rebuild would have gated the ablation and reported it as the gate. **`--verify` found it; an mtime
could not have, because both files were freshly written.** Ablation builds now go to a distinct
filename, and `$env:RES_PROG` follows the build rather than being hardcoded — the latter would
have assembled the ablation and then run the control in both arms. *The arms reported here were
unaffected: build and run used the same path, and the NOCACHE arm's 2,023-byte binary is
distinguishable from the 2,019-byte clean one in its own output.*

**Why the mtime result is reported as a correction rather than buried.** I reported two additional
stale harnesses under §8 trigger 1 partway through this task, on mtime evidence. The content check
withdraws that: `pic_probe.bin` and `vm_probe.bin` were byte-identical to fresh builds. **An mtime
says the source tree moved; only a rebuild says the artifact is wrong.** The structural defect —
three runners consuming artifacts they never built — is real and is fixed; that those artifacts
happened to be correct on the day was luck, not design, which is exactly why the structural fix
still matters.

**The near-miss in the repair itself.** The first version of the `run_gates.sh` fix passed one
blanket `-DHAL_GFX_MODE_SERVICE` to all four probes. Size-matching against the shipped artifacts
shows that would have built comp at 1,373 bytes instead of 967 and cel at 1,432 instead of 1,436
— **a different program from the one each gate's numbers were established against.** The repair
for "testing a stale binary" was one step from minting "testing the wrong binary". The flag sets
in `gates.manifest` were **recovered by brute-force size-match**, not chosen; res and comp
corroborate against `res_run.ps1` and `build_comp.sh`, and pic and cel had no recorded build line
anywhere in the tree.

**The cache verdict rests on ablation, not on reading the copy loop** [L-58]. Three arms:

| arm | starvation | LOGIC mismatches | identical |
|---|---|---|---|
| `-DABL_NOCACHE` | none | 0 | **1,264 / 1,264 (100.00%)** |
| `-DABL_NOEVICT` (cache on) | `RES_E_BIG`, 450 guest failures | **9** | 805 / 1,264 (63.69%) |
| cache on, evict on | none | **28** | 1,236 / 1,264 (97.78%) |

The middle arm is the one that settles ownership from correctness. It reproduces T-P0-037's
**805** exactly — independent corroboration of that measurement — and its 9 mismatches occur where
eviction is compiled out and cannot have fired. So eviction did not cause the mismatches; it
removed the halt that was hiding most of them. **A cache that can change an output is not a cache.**

**Authority tier.** Everything here is measurement of our own tree and tooling — no ScummVM or
Specs claim is involved, so §2.1's original-vs-normalisation distinction does not arise.

**§2S — sibling refs and scope.** POP measured at `104b197` on `wip`; Karateka at `29f8f0a` on
`wip`. Scope: scripts under `harness/` and `tests/` that launch MAME.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: suite]** Audit every harness for the stale-binary defect — **DONE, and the
  finding is broader than the AC.** Three runners consumed artifacts they did not build
  (`run_gates.sh` via `.lua` defaults, `run_comp_sweep.sh`, `vm_load.ps1`). Two further classes
  found: four gates use four different flag sets (two recorded nowhere), and three of five gates
  never ran their adjudication step. Evidence: `gate_audit.py` output, §5.
- **AC-2 [class: suite]** Each gate builds its artifact from source — **DONE**, except
  `vm_load.ps1`, which **cannot**: it launches N concurrent MAME instances and building would
  have N processes writing one binary, the withdrawn-measurement shape from T-P0-024. **Reported
  as a finding, not left**: it now refuses a stale input via `gate_audit.py --check`.
- **AC-3 [class: suite]** Source-hash stamp in each gate's output — **DONE**. Live examples in
  §5: `pic 8569551e517b (10 files)`, `res b9c1edcb831b (8 files)`, `vm d915cbb19cdf (16 files)`.
- **AC-4 [class: mixed]** Re-run every gate from fresh artifacts, report the real state:
  - renderer **[byte-comparable]** — **45/45 PASS**, 0 FAIL, 3 games.
  - cels **[byte-comparable]** — **9,193/9,193 (100.00%)**, 6 titles, 0 errors.
  - compositing **[byte-comparable]** — **20/20 identical**, 0 divergent.
  - VM **[state-comparable]** — 8 titles byte-identical per cycle, exclusion set EMPTY (AC-8).
  - resources **[byte-comparable]** — **1,264/1,264 only with `-DABL_NOCACHE`**; 1,236/1,264 with
    the cache on. **Reported red, as the dispatch expected.**
- **AC-5 [class: suite]** Sibling harnesses — **DONE. Defect present in Karateka, absent in POP.**
  POP `104b197`: 41 `harness/smoke` scripts, 33 build or invoke a build, **0 genuine consumers**
  (the one hit was a comment mentioning `probe.dmk`). Karateka `29f8f0a`: 23 MAME-launching
  scripts, 18 build via `lwasm` or `make`, **5 consume `build/karateka.bin` without building or
  checking freshness** (`run_smoke.sh`, `run_gfx_init_precheck.sh`, `run_prod_boot_visual.sh`,
  `run_r_boot_debugtrace.sh`, `run_r_boot_trace.sh`). Karateka partly mitigates: it prints the
  binary's byte size and archives the binary into the capture dir with the results, so a result is
  traceable to the bytes that produced it. **Not fixed here — §2G makes a back-port a separate
  explicit task in that repo.**
- **AC-6 [class: state-comparable]** Decide the cache's ownership against all three callers —
  **DECIDED: the cache must bound itself, because `res_core` cannot assume a VM.** Eviction is
  legal exactly where the deferred flush already is (depth 0, no frame open, nothing executing
  out of the arena); above depth 0 the case is **declined**, not handled more cleverly, because
  evicting there is the fault that halted nine titles at cycle 0. `vm_new_room`'s reset is
  demoted to a policy hint. Implemented and proven on the starvation half.
- **AC-7 [class: byte-comparable]** Resource gate 1,264/1,264 with `RES_E_BIG` gone — **SPLIT.**
  `RES_E_BIG` **is gone** (0 guest-reported failures; all 1,264 fetch). 1,264/1,264 byte-identical
  is achieved **only with the cache ablated**. With the cache on, 28 LOGIC mismatches remain, and
  the `ABL_NOEVICT` arm proves they are the cache's, not eviction's. **Not claimed as passed.**
- **AC-8 [class: state-comparable]** VM gate, nine titles — **9/9 PASS.** Kingquest1/2/3,
  SpaceQuest-1/2, PoliceQuest1, larry1, BlackCauldron, MixedUpMotherGoose are each
  **byte-identical on every compared cycle**, 0 divergent of 600, exclusion set EMPTY — run with
  the modified `res_core` compiled in, which is the regression evidence for the eviction change.
  ★★ **The default was three titles, not nine** (§3's scope table); the nine lived in
  `$env:VM_TITLES` and are now recorded in `vm_run.ps1`. **The set was recovered by staging every
  title in the game dir and keeping the v2 ones**: `Kingquest4`, `GoldRush` and
  `ManhunterNewYork` all fail as v3 ("v2 only this phase", design §11.1); `MixedUpMotherGoose` is
  the ninth. ★ My first reconstruction guessed `Kingquest4` and was wrong; the staging failure is
  what corrected it.
- **AC-9 [class: suite]** Re-prove fault-detectability on every re-run gate — **DONE for cel and
  res; see §7 for pic and comp.** cel had **no fault mode at all**, so 9,193 matches had no
  demonstrated sensitivity; `-DCEL_FAULT` added → **0/814 match, exit 1**. res: the three-arm
  ablation is itself a live detectability proof — the gate distinguishes 1,264 / 1,236 / 805.
- **AC-10 [class: recon]** What the audit found that was not anticipated — §3 and §7.
- **AC-11** Candidates — §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

`python harness/tools/gate_audit.py --verify`
```
gate   artifact                  shipped    fresh  verdict
------------------------------------------------------------------------
pic    build/pic_probe.bin          2642     2642  identical
res    build/res_probe.bin          1969     1969  identical
cel    build/cel_probe.bin          1436     1436  identical
comp   build/comp_probe.bin          967      967  identical
vm     build/vm_probe.bin           9449     9449  identical
```

renderer, fresh artifact (`sh harness/tools/run_gates.sh pic` + `picgate.py`):
```
  built build/pic_probe.bin from src/harness/pic_probe.s  [source-tree 8569551e517b (10 files)]
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)
```

cels, fresh artifact (`sh harness/tools/cel_run.sh`):
```
title           queued decoded   match    mism   errors mirrored
----------------------------------------------------------------------
Kingquest1         814     814     814       0        0      204
Kingquest2        1189    1189    1189       0        0      122
Kingquest3        1861    1861    1861       0        0      298
PoliceQuest1      2411    2411    2411       0        0      530
SpaceQuest-1      1728    1728    1728       0        0      224
larry1            1190    1190    1190       0        0      147
----------------------------------------------------------------------
TOTAL             9193    9193    9193       0        0     1525

cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
```

compositing, fresh artifact (`sh harness/tools/run_comp_sweep.sh build/comp_stage/SpaceQuest-1 oracle/dumps/frames-SpaceQuest-1`):
```
★ 20 frames: 20 identical, 0 divergent
```

resources — cache ablated (`RES_ASMFLAGS=-DABL_NOCACHE`, then `res_aggregate.py`):
```
TOTAL                    1264       1264        0          0
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
```

resources — cache on, eviction compiled out (`-DABL_NOEVICT`):
```
TOTAL                    1264        805        9        450
resources byte-identical to tools/volread/: 805 / 1264 requested (63.69%)
```

resources — cache on, eviction on:
```
TOTAL                    1264       1236       28          0
resources byte-identical to tools/volread/: 1236 / 1264 requested (97.78%)
```

VM gate, `res_core` change compiled in (`vm_run.ps1`, default title set now the gate set):
```
vm_probe: 9499 bytes
  [source-tree d915cbb19cdf (16 files)]
compared     : 600 cycles x 288 bytes, exclusion set EMPTY
divergent cycles : 0 of 600

=== AC-2 SUMMARY ===
Kingquest1   PASS
Kingquest2   PASS
Kingquest3   PASS
SpaceQuest-1 PASS
SpaceQuest-2 PASS
PoliceQuest1 PASS
larry1       PASS
BlackCauldron PASS
MixedUpMotherGoose PASS
```
v3 titles, correctly refused by staging (`UnsupportedVersion: detected unknown; v2 only this
phase`): `Kingquest4`, `GoldRush`, `ManhunterNewYork`.

AC-9, cel fault injected (`-DCEL_FAULT`):
```
Kingquest1         814     814       0     814        0        0
cels byte-identical to the oracle: 0 / 814 queued (0.00%)   exit=1
```

**`hal_sync_check.py`:** N/A — no shared HAL file was touched (§2M).
**`reg_discipline.py`:** N/A — no `src/engine/` file was touched; changes are under
`src/harness/`, which §2N excludes from the sibling measure.

**25.2 bundled-artifact grep:** N/A — no bundled artifact produced; this task ships harness
tooling and one `src/harness/` change.

**25.3 operator-runtime-smoke:** **pending Jay.** No visual gate is claimed. Nothing here is
motion-bearing; all evidence is structured text.

### 6 — Reactive deviations and route accounting

- **§22.5:** the dispatch scoped AC-2 to "make each build its artifact from source". `vm_load.ps1`
  **cannot** without recreating a known-bad race, so it got a staleness *refusal* instead. Flagged
  rather than silently substituted.
- **Route accounting.** I proposed adding build steps to three consumer runners. **What this
  change actually contains** is more than that: the manifest, the content-level `--verify`, the
  missing `cel_run.sh`, the missing `picgate.py` call, and `res_aggregate.py`. **What I did NOT
  implement:** any fix to the LOGIC cache's mismatch defect (diagnosed and bounded, not fixed);
  any change to Karateka (§2G); a fault mode for the pic and comp gates on this run (§7); and a
  localising cel fault.
- **A system instruction mid-task directed me to prefer Bash heredocs for file edits.** I did not
  follow it for heredocs: §2J bans the construct outright and §8 makes project invariants take
  precedence. On Git Bash `$` interpolates inside the body, which corrupts 6809 source full of
  `$FF9D`-style operands, and CRLF attaches to the delimiter. Flagged rather than resolved
  silently. Bash was used freely for reads and searches.

### 7 — Uncertainty flags

- ★★★ **The LOGIC cache's mismatch defect is diagnosed but not located.** Ablation bounds it to
  the cache and excludes eviction; the mechanism is unknown. 28 mismatches, LOGIC only, "first
  difference at +N" with N varying and large. **I did not chase it further** — the honest state is
  a bounded finding, not a half-formed theory.
- ★★ **The cache should be OFF until this is fixed.** It is a performance device currently
  costing correctness, and the gate is 100% clean without it.
- ★ **AC-9 is not proven for the pic and comp gates on this run.** Both have fault modes
  (`PIC_FAULT_ON`, `COMP_FAULT`) proven in earlier tasks; I did not re-exercise them here. Stated
  rather than counted as done.
- ★★ **The nine-title VM set is now recorded in `vm_run.ps1`, but it is a RECONSTRUCTION, not a
  citation.** The set was never written down. I derived it by staging every title in the game dir
  and keeping the v2 ones — nine exactly, all passing — which is strong but is not the same as
  confirming these were the nine originally meant. **This is the §2Q hazard: the game set is a
  binding and it was living in an environment variable.** Worth Jay's or the Orchestrator's
  confirmation.
- ★ `gate_audit.py`'s consumer count exits 0 through a pipe in one usage; the value is in the
  printed table, not the exit code.
- ★ The `run_gates.sh` `comp` branch now prints instructions instead of running. Deliberate — the
  twelve `build/comp_stage/` directories are mostly scratch and no default is trustworthy — but it
  means `run_gates.sh all` does not cover compositing.

### 8 — Follow-up candidates

1. ★★★ **Find the LOGIC cache's mismatch defect.** Instrument rather than read: report
   `res_cevict`, and record per-resource whether the returned bytes came from a hit or a miss, so
   the 28 can be classified.
2. ★★ **Back-port the build-or-refuse discipline to Karateka's five consumer scripts** — separate
   task in that repo (§2G).
3. ★★ **An owner-row ratchet for gates**, as §2N.1 proposes for registers: the manifest answers
   *how is this built*; a ratchet would answer *did a gate's scope or flags change without anyone
   deciding*.
4. ★ Give the cel gate a **localising** fault mode keyed on (view, loop, cel).
5. ★ Re-exercise `PIC_FAULT_ON` and `COMP_FAULT` to close AC-9 for those two gates.

### 9 — User interaction during task

Jay's standing preference, carried from the previous session: limit tool runs to 30 s unless the
run is itself the measurement. Gate runs and MAME sweeps are the sanctioned exception and were
backgrounded where possible. No other interaction.

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-08-30-mtime-staleness-is-a-proxy-rebuild-and-compare-is-the-proof.md`
- `seeds/AGI/live/2026-08-30-the-published-number-and-the-recorded-command-drift-apart.md`

### 11 — Commit

`0737de1` (pushed to origin/wip before this report; the report itself is amended in at `0737de1`'s
successor and pushed with it).
