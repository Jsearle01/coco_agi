## Form B Report — P3b.4 — the resource copy, and the rest of the VM
**Class:** recon. wip.
★★★★ **§8 TRIGGER 1 FIRED: the copy is per-cycle and avoidable. Reported; NOTHING CHANGED.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `2ac0231`, wip). git status clean at receipt.

---

### §5 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===        2ac0231  wip   (clean)

=== siblings (§2T: cite P3b.3 §0) ===
POP3_port          104b197 wip  tracked-modified=0
karateka_coco3     29f8f0a wip  tracked-modified=1

=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)

=== reg_discipline ===
  src/engine/mmu_phase.s                       5  $FFA5 $FFA6
```

**The five gates:** renderer **45 PASS / 0 FAIL (packed)**, resources **1,264** across 10 sweeps,
VM **nine titles PASS**, cels **6,782/6,782**, compositing **20/20 identical**.

★★★★ **THE COPY, NAMED BEFORE ANY MEASUREMENT:**

| | |
|---|---|
| **routine** | `res_fetch`'s `rfe_copy` loop [`res_core.s`] |
| **reached via** | `res_open` ← `vm_bind_logic` ← `vm_call_body` ← `vm_call_logic0` / `vm_call_logic` |
| **call sites in the VM** | **two** — `vm_run.s:57` (`vm_bind_logic`, LOGIC) and `vm_run.s:182` (`vm_view_open`, VIEW) |
| **per-cycle call count** | `vm_call_logic0` runs **once per cycle** from `vm_cycle.s:209`; `vm_call_logic` is `cmdCall`, so nested invocations add more |
| ★★ **structure** | `vm_call_body` = `jsr vm_bind_logic / jsr vm_run_logic / jsr res_close` — **a full bind, and therefore a full copy, on EVERY invocation** |

★ **`VM_VAR_TIME_DELAY` today:** var 10, read at `vm_cycle.s:325` into `vm_tdelay`; `vm_pace`
advances 25 ms per step and interprets when `vm_passed >= vm_tdelay`. The oracle doubles it
(`cycle.py:358-363`), so v10=4 → 200 ms. Unchanged this task.

**No contradiction found. Proceeded.**

---

### 1 — Summary

★★★★ **A — THE COPY IS PER-CYCLE, AND 99.7% OF IT IS THE SAME BYTES AGAIN.** On KQ1: **3.01
LOGIC invocations per cycle, 13,715 bytes copied per cycle, 3 distinct LOGICs totalling 13,669
bytes.** Uniform across six titles (99.6–99.7% redundant). ★★ **The reference does not do this**
— `cycle.py`'s `load_logic` fills `_logic_cache` once and never invalidates it. **The port pays
per INVOCATION what the reference pays per GAME.**

★★★★ **B — AND IT DOES NOT HAVE TO.** AC-3's experiment ran entirely in the reference [L-58]:
re-loading vs cached, **byte-identical 288-byte state on all 300 cycles of six titles.**
**Re-copying is behaviourally neutral.**

★★★★ **C — WHICH MADE THE ABLATION LEGITIMATE, AND IT CORRECTS AD-83.** T-P0-033 excluded the
copy from ablation for a stated and correct reason. **The neutrality proof retracts that
exclusion.** Measured: the copy loop is **37.5%**, not 57.9%; the per-fetch lookup and block
mapping are **0.1%**. ★★★ **Unattributed rises to 55.2%** — §8 trigger 3, reported not
distributed.

★★★ **The ablated build reaches 9.9 VM cycles/s** against 6.2 baseline and **10 asked by the
corpus** — and is **byte-identical to the oracle on 600 cycles × 288 bytes for KQ1 and KQ3,
empty exclusion set.**

> ★★★★ **§8 trigger 1: "the copy is per-cycle and avoidable — report and stop before changing
> anything." NOTHING WAS CHANGED.** The ablation is a guarded measurement build, off by default,
> and every shipped binary is byte-identical.

★★ **One near-miss worth reading: the first ablation reported a 98.7% saving and was broken**
(§3.4).

---

### 2 — Files modified

- `src/harness/res_core.s` — `-DABL_NOCOPY` and `-DABL_NOFETCH`, **measurement builds only**,
  both inert by default.
- `harness/tools/vm_ablate.ps1` — the two variants added; the stale header claiming the copy
  could not be ablated corrected.
- `harness/tools/copy_census.py` — **new.** AC-2's census and AC-3's suppression experiment.

★★ **Byte-identity verified with flags held constant on both sides:** `res_probe.bin`,
`vm_probe.bin`, `pic_probe.bin` all unchanged. **No shipped behaviour was touched.**

---

### 3 — Reasoning

#### 3.1 AC-2 — what the copy copies

| title | LOGIC inv/cycle | bytes/cycle | distinct | cached once | redundant | VIEW B/cycle |
|---|---|---|---|---|---|---|
| Kingquest1 | **3.01** | **13,715** | 3 | 13,669 | **99.7%** | 24 |
| Kingquest2 | 2.01 | 10,871 | 3 | 11,107 | 99.7% | 7,510 |
| Kingquest3 | 2.01 | 12,591 | 4 | 13,031 | 99.7% | 7,050 |
| PoliceQuest1 | 2.01 | 11,094 | 4 | 11,593 | 99.7% | 394 |
| SpaceQuest-1 | 2.04 | 11,705 | 4 | 13,523 | 99.6% | 6,319 |
| larry1 | 2.01 | 11,557 | 4 | 12,012 | 99.7% | 4,273 |

★★★ **PER-CYCLE, definitively.** KQ1's three logics are each invoked **301 times in 300
cycles** — logic0 ×301 (8,999 B), logic102 ×301 (3,817 B), logic83 ×301 (853 B).
★★ **13,715 B/cycle independently reproduces P4.5's 13,687** by a different route.
★★★★ **The entire working set is 13,669 B against a 24,576-byte arena** — it already fits, with
room to spare. The copy is not managing scarcity; it is re-doing settled work.

#### 3.2 AC-3 — must it happen? No.

★★ **The experiment contains no assembly** [L-58]. Both arms are `tools/agivm/`: one with
`_logic_cache` intact, one with the memo cleared before every call so the reference re-reads
exactly as the port re-copies. **Identical sha256 over 300 cycles × 288 bytes, six titles.**

★ **Why it must be the reference:** the port is the thing that would be changed, so it cannot
also be the thing under test.

#### 3.3 AC-4 — the decomposition, and AD-83 corrected

★★★★ **T-P0-033 was right to refuse this ablation, and §3.2 is what retracts the refusal.** Its
note read: *"skipping it leaves stale bytes in the arena and the dispatch then runs different
opcodes, which is a different program rather than the same program with a part removed."* That
holds for skipping *any* fetch. **It does not hold for skipping a REPEAT fetch**, because a
repeat provably cannot change what executes.

KQ1, **1.7898 MHz**, 200 free-run cycles, baseline 288,575 CPU cycles/VM cycle:

| build | CPU cy/VM cy | ms/cycle | isolates | share |
|---|---|---|---|---|
| baseline | 288,575 | 161.236 | — | 100% |
| `-DVM_NOCOUNT` | 284,415 | 158.911 | VM instrumentation | **1.44%** |
| `-DVM_PACEONLY` | 16,643 | 9.299 | harness + pacing floor | **5.77%** |
| **`-DABL_NOCOPY`** | **180,248** | **100.710** | **the copy loop** | ★★★ **37.5%** |
| `-DABL_NOFETCH` | 179,951 | 100.544 | + lookup and block mapping | **0.1% more** |

★★★★ **AD-83's 57.9% is CORRECTED to 37.6%.** The coefficient (1,022 cy + 11.98/byte) conflated
the copy loop with a per-fetch fixed cost that the ablation measures at **297 cycles — 0.1%.**
★★ **The whole of the fetch cost is the byte loop**; the lookup is noise.

★★★★ **UNATTRIBUTED: 159,148 cycles = 55.2%.** Higher than T-P0-033's 34.9%, because the copy's
real share is smaller than the coefficient claimed. **§8 trigger 3 honoured: reported, not
distributed.**

#### 3.4 ★★ The ablation that looked too good

The first `ABL_NOCOPY` run reported **2.076 ms/cycle — a 98.7% saving** from a component
estimated well under 60%. It completed 201 cycles without error.

★★★ **It was broken, and only the work counter said so: opcount 15 against baseline 184.** The
memo was declared with `rmb`, which reserves space **without emitting bytes**, so it booted
holding whatever RAM held and could false-hit on a *first* fetch — skipping a copy that was
needed and leaving the VM interpreting garbage. Fixed by explicit zeros plus a `type+1` marker
that a zeroed slot cannot match. After the fix: **100.710 ms, opcount 184, matching baseline
exactly.**

★★★★ **2.076 ms is the same figure T-P0-033's stale-symbol run produced.** Two unrelated defects
converged on it, which is a signature rather than a coincidence: **a program doing almost nothing
takes almost the same time however it came to be doing nothing.** ★ That recurrence is what made
me check instead of report.

#### 3.5 §2H's three checks

1. **A second mechanism for a different object class?** ★★ **Yes — VIEWs.** `vm_view_open` is a
   second `res_open` call site, and on SpaceQuest-1 it copies **6,319 B/cycle**, comparable to
   LOGIC's 11,705. **Any caching decision must cover both**, and AC-2's table reports VIEW
   separately for that reason.
2. **The calling routine.** `vm_call_body` is the caller, and its `bind / run / close` triple is
   the fact — not `res_fetch` itself. The copy is per-invocation *because of the caller*.
3. ★ **Grepped before citing.** T-P0-033's exclusion note was read in full before being
   retracted, and it is quoted rather than paraphrased.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** ★ **PASS.** §5 verbatim; five gates re-run.
  ★★ `res_probe.bin` byte-identity was checked **with flags held constant on both sides** — the
  first comparison used a stale artifact built with unknown flags and appeared to differ.

- **AC-2 [class: state-comparable]** ★★★★ **PASS — §3.1.** Routine, call sites, source
  (VOL window through the MMU), destination (`res_dest` = arena top), bytes per call (the whole
  resource), calls per cycle (2.0–3.0), **and it is PER-CYCLE, not per-room.**

- **AC-3 [class: state-comparable]** ★★★★ **PASS — the copy is NOT load-bearing.** Reference
  cached vs reference re-loading: identical sha256, all 300 cycles, six titles. **No assembly in
  the experiment.**

- **AC-4 [class: state-comparable]** ★★★★ **PASS — ablated, and AD-83 corrected 57.9% → 37.6%.**
  §3.3. **55.2% unattributed, reported not distributed.**

- **AC-5 [class: state-comparable]** ★★ **PASS.** Beyond the known floor: nothing new is
  instrument. Harness+pacing **5.77%**, VM instrumentation **1.44%** — **7.2% total is
  scaffolding**, and it disappears in the shipped interpreter. ★ The copy census runs in the
  reference and adds no target-side instrument at all.

- **AC-6 [class: state-comparable]** ★ **Ranked BY MEASURED SHARE, not acted on:**

  | # | candidate | measured | note |
  |---|---|---|---|
  | 1 | **the unattributed 55.2%** | ablated residue | ★★★ **ranked first because it is the largest and least understood** — aiming at anything else first is aiming at a third of the problem |
  | 2 | **LOGIC bind-caching** | **37.5%** | ★★★★ neutrality proven (AC-3), target state verified; **§8 trigger 1 blocks acting on it** |
  | 3 | VIEW caching | up to 6,319 B/cycle | ★★ same shape, not separately ablated |
  | 4 | harness + pacing | 5.77% | ★ not the engine |
  | 5 | VM instrumentation | 1.44% | `-DVM_NOCOUNT` exists |
  | — | per-fetch lookup/mapping | **0.1%** | ★ measured and dismissed |

  ★★★ **§4's condition was met and §8's trigger 1 overrides it.** The dispatch says make the
  change if A makes one obvious; trigger 1 says report and stop before changing anything because
  it is architectural and Jay should see it first. **I took the trigger.**

- **AC-7 [class: byte-comparable]** ★★★ **NO CHANGE WAS MADE — stated explicitly, as AC-7
  requires.** Every shipped binary is byte-identical. ★★ The ablation build was nonetheless
  validated: **KQ1 and KQ3, 600 cycles × 288 bytes, 0 divergent, exclusion set EMPTY** — so if
  the change is later adopted, the evidence already exists. ★ No injected-fault run: there is no
  new build to re-prove one on.

- **AC-8 [class: state-comparable]** ★★ **No change, so no new rate — but the ablation shows what
  one would buy.** Clock **1.7898 MHz**: baseline **6.2 cyc/s**, ablated **9.9 cyc/s**, corpus
  asks **10**. ★★★ **The gap closes to within 1%** on this measure — and that is a projection
  from an ablation, **not a shipped result.**

- **AC-9 [class: suite]** ★ **Two rows** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

```
=== Kingquest1   300 cycles, seed 12345
LOGIC invocations   :      903   =   3.01 per cycle
                    :  4114369 B =    13715 B per cycle
distinct LOGICs     :        3   holding 13,669 B if cached once
★ REDUNDANT FRACTION:  99.7% of copied bytes are a resource fetched AGAIN
  most-invoked      : logic0x301 (8,999B)  logic83x301 (853B)  logic102x301 (3,817B)

★★ AC-3 -- reference CACHED vs reference RE-LOADING (no port in the experiment):
  cached      300 cycles  sha256 5160f598ddf5b4a7
  re-loading  300 cycles  sha256 5160f598ddf5b4a7
  ★★★★ IDENTICAL on all 300 cycles, 288 bytes each.  Re-copying is behaviourally NEUTRAL.
```
*(Kingquest2/3, PoliceQuest1, SpaceQuest-1, larry1: 99.6–99.7% redundant, all IDENTICAL.)*

```
=== baseline     161.236 ms/cycle   288575 CPU cycles/VM cycle @ 1.7898 MHz   6.2 VM cycles/s
                 opcount=184  (0.9 commands/cycle)
=== VM_NOCOUNT   158.911 ms/cycle   284415   opcount=184
=== VM_PACEONLY    9.299 ms/cycle    16643   opcount=184
=== ABL_NOCOPY   100.710 ms/cycle   180248   opcount=184   9.9 VM cycles/s
=== ABL_NOFETCH  100.544 ms/cycle   179951   opcount=184   9.9 VM cycles/s
```

```
=== Kingquest1 (ABL_NOCOPY) ===
compared     : 600 cycles x 288 bytes, exclusion set EMPTY
divergent cycles : 0 of 600
AC-2 PASS -- byte-identical on every compared cycle
=== Kingquest3 (ABL_NOCOPY) === same
```

```
★ res_probe.bin BYTE-IDENTICAL across my change (same flags both sides)
★ vm_probe.bin still BYTE-IDENTICAL      ★ pic_probe.bin BYTE-IDENTICAL
per-picture: 45 PASS, 0 FAIL (of 45)     byte-identical resources: 1264, all sweeps clean
cels 6782 / 6782                          nine titles all PASS      ★ 20 frames: 20 identical
```

**25.2 bundled-artifact grep:** N/A — nothing shipped changed; every production binary is
byte-identical.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen. All work was the
reference, headless gates and free-run timing.

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **Stopped on §8 trigger 1** rather than taking §4's "make the change and gate it". The
   trigger is explicit that this is architectural and Jay sees it first. **No change was made.**
2. ★★ **Two ablation build flags added** to `res_core.s`, guarded and inert by default. These are
   instruments, not changes; byte-identity of every shipped binary is the evidence.
3. ★★ **Retracted T-P0-033's stated exclusion** of the copy from ablation, on the strength of
   AC-3, and corrected the stale comment in `vm_ablate.ps1` that asserted it.

**ROUTE ACCOUNTING.** ★★ **What I did NOT do:** did not implement bind-caching in any shipped
path; did not cache VIEWs; did not touch the cycle-rate question (§12 — Jay's); did not attribute
the 55.2%; did not run an injected fault (no new build to prove one on); did not change the
parser, sound, storage or the map.

---

### 7 — Uncertainty flags

1. ★★★★ **55.2% of the VM cycle is unattributed** — larger than before, because correcting AD-83
   shrank the known part. **This is now the largest open number in the project** and AC-6 ranks
   it first for that reason.
2. ★★★ **AC-2 and AC-3 are measured in the REFERENCE.** That is what makes AC-3 valid, but the
   invocation counts are the reference's; the port's could differ if its call structure diverges.
   ★ Against that: 13,715 B/cycle independently reproduces P4.5's target-side 13,687.
3. ★★★ **VIEW copying is measured but not ablated.** SpaceQuest-1 copies 6,319 VIEW B/cycle —
   comparable to LOGIC — and its share of the 55.2% is unknown.
4. ★★ **The ablation memo is keyed by arena DEPTH**, which is correct only while each depth sees
   the same resource each cycle. It does across the sample; a real cache would key on (type,
   index) and must not inherit this simplification.
5. ★★ **AC-8's 9.9 cyc/s is a projection from an ablation, not a shipped measurement**, and it is
   one title. KQ3 was not re-timed under ablation.
6. ★ **Pool push failed on auth — sixth consecutive task.** Sixteen rows local only.

---

### 8 — Follow-up candidates

1. ★★★★ **Jay's call: adopt LOGIC bind-caching?** Neutrality proven in the reference, state
   verified on target, 37.5% of the VM cycle, 6.2 → 9.9 cyc/s. **Trigger 1 stopped short of it
   deliberately.**
2. ★★★★ **Attribute the 55.2%.** Candidate ablations: the opcode dispatch itself, `vm_update_objs`
   / motion, the pacing clock's `timer_update`.
3. ★★★ **Ablate VIEW copying** — the second `res_open` call site, up to 6,319 B/cycle.
4. ★★ **If caching is adopted, key it on (type, index) with real invalidation**, not on depth
   (§7.4), and cover `new.room`.
5. ★ **AD-77** remains open and out of scope.

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

Two rows in `seeds/AGI/live/`, committed locally. ★ **Push failed** — `Authentication failed`,
**sixth task running** — fire-and-forget per §2C, does not gate.

- `2026-08-30-proving-a-change-is-neutral-is-what-makes-the-ablation-possible.md`
- `2026-08-30-an-ablation-that-looks-too-good-has-usually-stopped-doing-the-work.md`

---

### 11 — Commit

`<filled at commit>` (pushed to origin/wip before this report)
