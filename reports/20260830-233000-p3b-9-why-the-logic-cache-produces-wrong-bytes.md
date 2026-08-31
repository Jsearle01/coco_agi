## Form B Report — T-P0-040 (P3b.9) — Why the LOGIC cache produces wrong bytes
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-30 (HEAD `8ca6a6e`, wip). `git status` clean at t0.

### §4 — Pre-dispatch grep (verbatim, before the summary)

```
=== coco_agi ===
HEAD 8ca6a6e on wip
(clean)

=== POP ===        HEAD 104b197 on wip
=== Karateka ===   HEAD 29f8f0a on wip
```

★ **§2T citation.** POP `104b197` and Karateka `29f8f0a` are **unchanged from P3b.8 §0**, where
their baseline was recorded. Neither has dirty *source*: POP's untracked entries are
`docs/ground-truth/` PDFs and `.vscode/`; Karateka's are ground-truth PDFs plus one modified
`harness/smoke/last-run.log`. lwasm 4.24 unchanged. **No sibling artifact was rebuilt — this task
touches no shared file.**

```
=== hal_sync_check ===
POP:      [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
Karateka: [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
coco_agi: [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)

=== reg_discipline (coco_agi) ===
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 5 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   5   $FFA5 $FFA6

=== gate artifacts, content-verified against a fresh build ===
pic  2642 identical · res 2019 identical · cel 1436 identical · comp 967 identical · vm 9499 identical
```

★ **Note against the dispatch's §4 row:** it lists `hal_sync_check.py` as "OK in all three repos",
and that is now literally true — **coco_agi has joined as the third participant** (§2M.6's entry
at P3). P3b.8 reported it `N/A` for that task because no shared file was touched; that remains
correct and is not a contradiction.

**★★★★ The 28 mismatches, itemised — and the dispatch's premise about them does not survive.**

| arm | mismatches |
|---|---|
| cache on, eviction on | 28 |
| cache on, eviction **compiled out** | 9 |
| **in both** | ★★★ **6, not 9** |

★★ **The dispatch reads "9 survive eviction being compiled out" as "9 of the 28 are
eviction-independent". The two sets are not nested.** The no-evict arm halts on `RES_E_BIG` after
805 of 1,264 fetches, so **22 of the 28 are simply never reached in that arm** — their absence is
"not tested", not "correct". Three of its 9 (`KQ1-v0 LOGIC 104`, `KQ2-v2 LOGIC 11`,
`KQ3-v1 LOGIC 3`) do **not** appear in the eviction arm at all. **Set arithmetic on a truncated
run is not evidence**, and the "9" was the wrong lead — ★ though it pointed at the right place
anyway, because the true cause covers all 28.

`run_gates.sh` **did not** exit non-zero on a partial run at t0 — it ended in a bare `exit 0`,
discarding every adjudicator's verdict. Fixed under AC-9.

### 1 — Summary

★★★★★ **The cache was never returning wrong bytes. The GATE was reading the wrong address, and
T-P0-039's "the cache is incorrect" — my conclusion — is withdrawn.**

`harness/tools/res_sweep.lua` read each payload from a hardcoded `RES_SLOT = 0x3000`. That was
true for four tasks: before the LOGIC cache, every depth-0 fetch landed at `RES_ARENA`, and
`res_probe.s:70` says so in as many words — *"the byte gate reads one fixed address"*. The cache
relocates a LOGIC to `res_ccur - len`, so `0x3000` now holds the **scratch**, whose upper part the
relocation copy overwrote. The result is corruption beginning at exactly `D = dest - src`, with
the tail equal to the resource's own bytes shifted by `D`.

★★★★ **The signature is arithmetic and it confirms on all 28.** First difference `= D`; tail
`= oracle[0 : len-D]`. **28 of 28.** One cause, not two (AC-3).

★★★★ **And the control arm was green for the wrong reason.** Ablating the cache forces `res_base`
back to `RES_ARENA`, which makes the stale literal accidentally correct again — so
"cache off → 1,264/1,264" measured the harness's assumption being restored, not the cache being
removed. **The ablation exonerated the wrong component.**

**AC-4 is delivered: 1,264/1,264 byte-identical with the cache LIVE.** AC-5 reproduces the
original 28 exactly — same logics, same lengths, same offsets. The VM gate is **9/9 with an empty
exclusion set**.

★★★★ **AC-7: AD-87's numbers survive exactly — KQ1 6.2 → 14.2, KQ3 5.3 → 9.4, the cached rows
matching to the CPU cycle.** That is the consequence of AC-2: the VM reads `res_base` and was
never fed a wrong byte, so its budget figures were never at risk. **Nothing the project has been
planning against moves.** ★★ KQ3's 0.6 shortfall against the corpus's 10 is unchanged and
pre-existing (trigger 2 — reported, not pursued).

★★★ **Two further harness defects were found and fixed in passing** — `ABL_NOCACHE` was diverting
in the wrong place (opcount 37 vs 184), and `vm_ablate.ps1`'s `ABL_TITLE` was **inert**, so every
ablation it has ever run measured Kingquest1 (trigger 5, §6).

### 2 — Files modified

- `harness/tools/res_sweep.lua` — read the payload from the address the guest publishes at
  `RP_BASE`, not the literal; `RES_STALE_READ=1` restores the defect (AC-5).
- `harness/tools/run_gates.sh` — accumulate gate failures; **exit non-zero on any** (AC-9, L-72).
- `harness/tools/vm_ablate.ps1` — `ABL_NOCACHE` variant, `$env:ABL_VARIANTS`; **stage the
  requested title and set `VM_STAGE`** — `ABL_TITLE` was inert (§6, trigger 5).
- `harness/tools/res_mismatch_list.py` — NEW. Itemises mismatches per arm and set-compares.
- `harness/tools/res_shift_test.py` — NEW. Tests the shift hypothesis against the oracle.

- `src/harness/res_core.s` — **`ABL_NOCACHE` only.** The guard was diverting inside
  `res_cache_stash`, which left the LOGIC branch taking `ro_push_after_stash` and its
  "scratch already relocated" mark; corrected to divert to `ro_push_transient`, the actual
  pre-cache path. ★★★ **The cache's live code paths are untouched by this task** — verified, not
  asserted: all five gate artifacts rebuild byte-identical (`res` 2,019, `vm` 9,499), so the
  guarded edit is inert outside the ablation and no gate needed re-running because of it.

### 3 — Reasoning

**§2H check 1 — is there a second mechanism?** The dispatch offered keying, lifetime and aliasing.
**All three are about the cache.** The measured signature excludes every one of them: a key
collision returns a *different resource*, not the same resource shifted; a lifetime bug returns
*stale or clobbered* bytes, not a clean constant displacement; aliasing gives *two logics'* bytes
interleaved. **Only reading at the wrong offset produces `guest[D+k] == oracle[k]` for the whole
tail** — and the second mechanism was in the harness, which none of the three candidates named.

**§2H check 2 — name the caller.** `res_cache_stash`'s copy loop is `lda ,-u` / `sta ,-y`,
backward, and **correct** for `dest > src` (the clobbered location is always above the read
pointer). Reading only the copy would have produced a plausible wrong answer, because the
*offsets look exactly like a forward-copy defect* — first difference at `dest - src` is the
forward-overlap signature, and AD-89 was a forward-copy defect. ★★★ **The caller is what settles
it: the bytes are correct where the cache put them, and wrong where the harness looked.**

**§2H check 3 — grep the reports.** T-P0-039 §7 recorded "the LOGIC cache is incorrect,
independent of eviction" and flagged it unlocated. That characterisation is now **withdrawn by its
own author**, which is the case §2H.3 exists to catch before the claim is cited a third time.

**The arithmetic, from the arena's own constants.** `RES_ARENA = $3000` (12,288),
`RES_ARENA_END = $6000` (24,576). The first LOGIC cached in an empty cache goes to
`dest = 24576 - len`, with `src = res_top = 12288`:

| volume | len | dest | `D = dest-src` | measured first diff |
|---|---|---|---|---|
| KQ1-v0 L0 | 8,999 | 15,577 | **3,289** | **3,289** |
| KQ2-v2 L0 | 8,938 | 15,638 | **3,350** | **3,350** |
| KQ3-v1 L0 | 10,428 | 14,148 | **1,860** | **1,860** |

★★ The closed form only applies to a *first* cached logic; for the other 22 `res_ccur` has already
descended, so `D` differs — which is why the test **recovers the shift from the data** and then
checks it explains the entire tail, rather than assuming the formula. **28 of 28 confirmed.**

**Why the fix is "publish, don't assume".** `res_probe.s` already writes `res_base` to `RP_BASE`
every report, and `res_sweep.lua` already reads it into `base` twenty lines above, for modes 2 and
5. ★★★ **The correct pattern was adjacent and the byte gate used the literal anyway** — §2M.1's
lesson (*do not assume a routine is mode-aware because a neighbouring one is*) reappearing on the
host side. ★★ Under §2F the payload address had **two homes across a language boundary**:
`res_core.s`'s `RES_SLOT equ RES_ARENA` and the Lua's `0x3000`. The cache updated one; nothing
connected it to the other, and no tool in the tree checks a constant duplicated between `.s` and
`.lua`.

**★★★★ Was the VM ever fed wrong bytes? No — and this is checked, not inferred.** The VM locates
a logic's bytes at `vm_run.s:60` and `vm_run.s:185`, both `ldx res_base`; **it never reads a
literal address.** Three independent confirmations: the VM gate is **9/9 byte-identical with an
EMPTY exclusion set**; AC-7's two arms have **identical opcounts (184 = 184)**; and AD-87's own
opcount check (184 KQ1) would have diverged had the interpreter been executing shifted bytecode.
★★★ **The defect was confined to one host-side readback in one gate.** Nothing that consumed
`res_base` was ever affected.

**Authority tier.** All of this is measurement of our own tree against `tools/volread/`. No
ScummVM or Specs claim is involved, so §2.1's original-vs-normalisation distinction does not
arise. ★ The dispatch's §3 suggestion to diff against `tools/agivm/`'s `_logic_cache` per fetch
was **not needed**: the defect is a host-side address, and L-67's boundary says a reference-side
proof could not have modelled it anyway.

**§2S — sibling refs.** POP `104b197` wip, Karateka `29f8f0a` wip; scope: `hal_sync_check.py`
only. No sibling source was read or modified.

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** `reg_discipline.py` and `hal_sync_check.py` — **PASS**, §4
  verbatim. Baseline cited per §2T from P3b.8 §0; both sibling HEADs unchanged.
- **AC-2 [class: state-comparable]** ★★★★ **THE MECHANISM — NAMED.** The byte gate reads the
  payload from a hardcoded `0x3000` instead of the guest-published `RP_BASE`. A cached LOGIC lives
  at `res_ccur - len`; `0x3000` holds the scratch, whose tail the relocation copy overwrote.
  Corruption begins at `D = dest - src` and the tail is `oracle[0 : len-D]`. **Not a cache defect.**
- **AC-3 [class: state-comparable]** ★★★ **ONE cause, not two.** All 28 carry the shift signature
  (28/28 confirmed). ★★ **The dispatch's 9-vs-19 split does not hold**: the no-evict arm halts at
  805 fetches, so only 6 of the 28 appear in both arms and 3 of its 9 appear in neither — the
  partition was an artifact of a truncated run, not two defects.
- **AC-4 [class: byte-comparable]** ★★★★ **PASS — 1,264/1,264 byte-identical WITH THE CACHE LIVE**
  (100.00%, 0 mismatches, 0 guest failures, all ten volumes). §5.
- **AC-5 [class: byte-comparable]** ★★★★ **PASS.** `RES_STALE_READ=1` restores the defect and
  reproduces **exactly the original 28** — same volumes, same LOGIC indices, same lengths, same
  first-difference offsets; **0 in either exclusive set**; 1,236/1,264 = 97.78%, identical to
  T-P0-039's cache-on figure.
- **AC-6 [class: state-comparable]** ★★★ **PASS — 9/9 titles**, 0 divergent of 600 on each,
  **exclusion set EMPTY**, with the corrected harness and the cache live.
- **AC-7 [class: state-comparable]** ★★★★ **AD-87's NUMBERS SURVIVE, EXACTLY. KQ1 6.2 → 14.2,
  KQ3 5.3 → 9.4**, clock **1.7898 MHz**, 200 free-run cycles, opcount identical in every arm
  (184/184, 361/361). **The cached rows match AD-87 to the CPU cycle** (126,307 / 70.572 and
  191,096 / 106.771). ★★★ **This follows from AC-2 rather than contradicting the dispatch's
  premise**: the dispatch expected the figures to have been "measured on a cache returning wrong
  bytes", but the cache never returned wrong bytes to the VM — only one host-side readback in one
  gate was affected. **Nothing in the project's budget planning moves.**
  ★★ **Trigger 2's condition is nonetheless met and is reported, not resolved: KQ3 at 9.4 is 0.6
  short of the corpus's 10.** That shortfall is **pre-existing and unchanged** — AD-87 stated it
  in the same words — so it is not a new finding, but the cycle-rate decision is Jay's and I have
  stopped rather than pursued it.
- **AC-8 [class: state-comparable]** ★★ **Ownership: settled, and the question changes shape.**
  T-P0-039 made the cache self-bounding (evict at depth 0) so `res_core` need not assume a VM;
  that stands and is unmodified here. **What is new is that the cache never had a correctness
  defect to own.** The residual ownership question is not the cache's — it is that **the payload
  address must be owned by the guest and published**, not assumed by any of the three callers.
- **AC-9 [class: byte-comparable]** ★★★ **PASS.** All five artifacts content-verified identical to
  a fresh build (§4). `run_gates.sh` now accumulates failures and **exits non-zero**; verified that
  `res_aggregate.py` returns 1 on a failing arm, which is the signal it consumes.
- **AC-10 [class: suite]** Candidates — §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

**AC-4 — the gate, cache LIVE** (`res_run.ps1` then `res_aggregate.py`):
```
res_probe: 2019 bytes (assembled by this script) -> build\res_probe.bin
  [source-tree b9c1edcb831b (8 files)]
volume               requests  identical   mismat  guestfail
--------------------------------------------------------------
Kingquest1-v0              74         74        0          0
Kingquest1-v1             150        150        0          0
Kingquest1-v2              88         88        0          0
Kingquest2-v0              86         86        0          0
Kingquest2-v1             187        187        0          0
Kingquest2-v2             207        207        0          0
Kingquest3-v0             124        124        0          0
Kingquest3-v1              87         87        0          0
Kingquest3-v2             132        132        0          0
Kingquest3-v3             129        129        0          0
--------------------------------------------------------------
TOTAL                    1264       1264        0          0

resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
```

**AC-2 — the mechanism, tested** (`res_shift_test.py`, KQ1-v0; `D` column is the closed form,
which applies only to a first-cached logic — the test recovers the shift from the data):
```
type       idx     len  firstdiff  D=dest-src  match?  shift-test
LOGIC        0    8999       3289        3289     yes  ★ tail==oracle[0:len-D] CONFIRMED
LOGIC      100     785        328       11503      no  ★ tail==oracle[0:len-D] CONFIRMED
mismatched: 2   shift-tested: 2   confirmed: 2
```
Across all seven mismatching volumes: **28 mismatched, 28 shift-tested, 28 confirmed.**

**AC-5 — fault restored** (`RES_STALE_READ=1`):
```
TOTAL                    1264       1236       28          0
resources byte-identical to tools/volread/: 1236 / 1264 requested (97.78%)
★★★ volumes with mismatches: Kingquest1-v0 Kingquest1-v1 Kingquest1-v2 Kingquest2-v2
                             Kingquest3-v1 Kingquest3-v2 Kingquest3-v3
```
Set-compared against T-P0-039's cache-on sweep: **IN BOTH (28)**, ONLY IN A (0), ONLY IN B (0).

**AC-6 — VM gate, nine titles** (`vm_run.ps1`, corrected harness):
```
compared     : 600 cycles x 288 bytes, exclusion set EMPTY
divergent cycles : 0 of 600            [every title]

=== AC-2 SUMMARY ===
Kingquest1 PASS · Kingquest2 PASS · Kingquest3 PASS · SpaceQuest-1 PASS · SpaceQuest-2 PASS
PoliceQuest1 PASS · larry1 PASS · BlackCauldron PASS · MixedUpMotherGoose PASS
```

**AC-7 — cycle rate, clock stated** (`vm_ablate.ps1`, 200 free-run cycles, 1.7898 MHz):
```
Kingquest1
=== baseline  (9499 bytes) ===
AC-7 free-run: 201 cycles in 14.184930 emulated s
    70.572 ms/cycle   126307 CPU cycles/VM cycle @ 1.7898 MHz   14.2 VM cycles/s
    opcount=184  (0.9 commands/cycle)
=== ABL_NOCACHE  (9505 bytes) ===
AC-7 free-run: 201 cycles in 32.441770 emulated s
    161.402 ms/cycle  288872 CPU cycles/VM cycle @ 1.7898 MHz   6.2 VM cycles/s
    opcount=184  (0.9 commands/cycle)

Kingquest3
=== baseline  (9499 bytes) ===
AC-7 free-run: 201 cycles in 21.460965 emulated s
    106.771 ms/cycle  191096 CPU cycles/VM cycle @ 1.7898 MHz   9.4 VM cycles/s
    opcount=361  (1.8 commands/cycle)
=== ABL_NOCACHE  (9505 bytes) ===
AC-7 free-run: 201 cycles in 38.182495 emulated s
    189.963 ms/cycle  339990 CPU cycles/VM cycle @ 1.7898 MHz   5.3 VM cycles/s
    opcount=361  (1.8 commands/cycle)
```

★★ **Opcount is the correctness check on the pair and it is identical in every arm** (184/184,
361/361), so both arms do the same work and the ratio is a timing result rather than a
short-circuit. ★ It is also what caught the first `ABL_NOCACHE` build (opcount 37 against 184,
reporting a spectacular and meaningless 115.8 cyc/s) — §6.

**Against AD-87, measured now vs published then:**

| | AD-87 published | re-measured | |
|---|---|---|---|
| KQ1 cached | 126,307 cy / 70.572 ms / **14.2** | 126,307 / 70.572 / **14.2** | ★ exact |
| KQ1 no-cache | 288,575 cy / 161.236 ms / **6.2** | 288,872 / 161.402 / **6.2** | +0.10% |
| KQ3 cached | 191,096 cy / 106.771 ms / **9.4** | 191,096 / 106.771 / **9.4** | ★ exact |
| KQ3 no-cache | 339,693 cy / 189.797 ms / **5.3** | 339,990 / 189.963 / **5.3** | +0.09% |

★★★ The cached rows are **identical to the cycle**. The no-cache rows differ by ~0.1% because
AD-87's baseline was a genuinely **pre-cache tree** while this is the `ABL_NOCACHE` path through
the current tree, which carries the guard's branch. **The difference is the guard, not the
measurement.**

**25.2 bundled-artifact grep:** N/A — no bundled artifact. This task ships harness tooling and
one Lua readback change; no `src/engine/` or `src/hal/` file was touched.

**25.3 operator-runtime-smoke:** **N/A** — nothing reached the screen. All evidence is structured
text; no motion-bearing or visual output was produced.

### 6 — Reactive deviations and route accounting

- ★★★★ **TRIGGER 5 FIRED — a fifth runner with the audit's defects, reported as required.**
  `vm_ablate.ps1`'s `$env:ABL_TITLE` **was inert.** It set `VM_TITLES`, which `vm_sweep.lua` does
  not read; the Lua stages from `VM_STAGE`, whose default is the literal
  `build/vm_stage/Kingquest1`, and the script never set it or ran `vm_stage.py`. **Every
  measurement this script has ever produced was Kingquest1**, whatever title was asked for.
  ★★★ Caught because the "Kingquest3" run returned numbers identical to Kingquest1's digit for
  digit — 14.184930 emulated s, 126,307 CPU cycles, opcount 184. **A parameter that is accepted
  and ignored is worse than one that errors**: the operator gets a plausible answer to a question
  they did not ask. Fixed (stage the title, set `VM_STAGE`); KQ3 re-measured afterwards.
- **No other §22.5 consultation trigger fired.** Trigger 4 ("the defect is in `res_core` rather than the
  cache — stop immediately") is the near miss and it did **not** fire: the defect is in the
  **harness**, in neither `res_core` nor the cache. ★★ **It also does not carry trigger 4's
  consequence.** That trigger exists because a `res_core` defect would mean the resource layer's
  1,264/1,264 was itself wrong; here the cache-ablated 1,264/1,264 was **valid** — with no cache
  `res_base == RES_ARENA` and the literal is genuinely correct — so prior non-cache results stand.
- **Route accounting.** I proposed diagnosing from the nine eviction-independent mismatches. **What
  this change contains** is different in two ways: the nine turned out to be the wrong partition
  (§4), and the fix landed in the harness rather than the cache. **What I did NOT implement:** any
  change to `res_core.s`; any reference-side diff against `tools/agivm/` (§3 says why it was not
  needed); any fix to the two other `res_core` callers, which never had the defect because only
  the Lua hardcoded an address.

### 7 — Uncertainty flags

- ★★★ **T-P0-039's §7 finding is withdrawn.** "The LOGIC cache is incorrect independent of the
  eviction fix" was mine, was stated with three arms of evidence, and was wrong. **The evidence was
  real; the inference was not** — see §10's first candidate.
- ★★ **`res_core.s`'s `RES_SLOT equ RES_ARENA` is now a name for a thing that is no longer always
  true.** I left it — it is still the depth-0 fetch address and `res_core` uses it correctly — but
  it is the surviving half of the two-home pair and is a live trap for the next reader.
- ★ **No tool checks a constant duplicated between `.s` and `.lua`.** The class that caused this is
  still undetected anywhere else in the tree.
- ★★★ **`vm_ablate.ps1` measured Kingquest1 for every prior ablation.** Any figure taken from it
  for another title in an earlier report should be treated as **Kingquest1's**, not that title's.
  I have not swept the report history for such figures; AD-87's KQ3 row is not affected because
  it re-measures correctly now and matches, but **other ablation results may be mislabelled.**
- ★★ **The `ABL_NOCACHE` arm published in T-P0-039 is retrospectively suspect for a second
  reason.** It was sound for `res_probe` (open-then-close) and unsound for the VM until fixed
  here; the resource-gate arm stands, any VM-side use of it before this task does not.

### 8 — Follow-up candidates

1. ★★★ **Audit every host-side script for hardcoded guest addresses** — the same class, not yet
   swept. `res_sweep.lua` had one; `pic_sweep.lua`, `cel_sweep.lua`, `comp_sweep.lua` and
   `vm_sweep.lua` are unexamined for it.
2. ★★ **Rename or retire `RES_SLOT`** so the stale invariant cannot be re-adopted (§7).
3. ★★ **Re-examine T-P0-039's eviction change on its merits.** It is correct and still wanted —
   `res_core` should not assume a VM — but its *justification* cited a gate failure that was not
   the cache's, so the cost/benefit was never measured on true numbers.
4. ★★★ **Sweep the report history for ablation figures attributed to a title other than
   Kingquest1** (§7) — `vm_ablate.ps1` ignored `ABL_TITLE` until this task.
5. ★★ **Audit every runner for parameters that are accepted and ignored.** `ABL_TITLE` is the
   second this week (`VM_TITLES` defaulting to three was the first). A parameter that silently
   does nothing is the same class as a scope living outside the runner.
6. ★ Back-port the build-or-refuse discipline to Karateka's five consumer scripts (carried, §2G).

### 9 — User interaction during task

`None.`

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-08-30-an-ablation-can-exonerate-the-wrong-component-by-restoring-the-harness-assumption.md`
- `seeds/AGI/live/2026-08-30-a-constant-that-was-true-becomes-a-lie-when-the-thing-it-described-moves.md`

### 11 — Commit

<filled at commit>
