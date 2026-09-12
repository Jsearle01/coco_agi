## Form B Report — T-P0-087 / P6.31 — `print` never reaches `tx_msgptr`; the wait loop's tick source is dead
**Class:** integration.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 11:09 (HEAD ebe5d17, wip). Clean but for the two untracked files that are not mine —
`agi-coco3-design-v1_3.md` (Orchestrator's, §2D) and `coco_agi.code-workspace` (Jay's).

### 1 — Summary
★★★★★ **The dispatch's premise is false, and the differential is what showed it.** `tx_msgptr` does
not reject `print`'s message number — **`print` never calls `tx_msgptr` at all.** The table shows 8
healthy `display` records and **0 `print` records**, in every configuration tried.

Two distinct blockers sit behind that, and neither is in `tx_msgptr`:

1. **The trigger title was already dead.** Kingquest2 halts the VM on a resource bind —
   `vm_badop=$F6`, which `vm_run.s:114` builds as `res_err | $F0`, i.e. `RES_E_DEPTH` — in **logic
   0**, with or without the room jump. ★★★★ **P6.30 read `vm_quit=1` as proof that the instruction
   after `print.v` had executed. It is the halt setting `vm_quit`.** The VM never reached `print`.
2. **On a title that does not halt, the box draws and the wait loop runs — and then hangs.**
   SpaceQuest-2 room 101 stalls in cycle 9 with the most-visited PCs at **`tx_wt_loop+3`,
   `tx_wt_tick+5` and `HAL_key_scan`**. ★★★★★ **`hal_frame` is frozen at 0 across the whole stall:
   nothing installs the `$010C` vector or enables GIME VBORD in any probe, so the wait loop's tick
   source never advances,** `vm_step_clock` is never called, and var 21's deadline — correctly
   computed as `tx_wt_end=109` from `vm_vms 49 + 60` — can never arrive.

★★★★ **That also explains the fault arm exactly.** The omitted `jsr vm_step_clock` sits *after* the
tick-edge test, so **neither arm ever reaches it**; the clean and fault arms stall at identical PCs.
Per §4D and §6 this is a stop. **AC-3 is UNMET.** No clean binary moved: `p3b`, `p3b_text` and
`p3b_notick` are byte-identical, `vm` is 9/9 and `res` is 1,264/1,264, both fresh.

### 2 — Files modified
All new code is behind `-DTX_MSGDIAG` and emits nothing in any shipped build.
- `src/harness/vm_text_ops.s` — the differential logger and its two call-site tags.
- `src/harness/p3b_probe.s` — `P3_TXDIAG` in MAP_INPUT's tail, with two overrun assertions.
- `harness/tools/p3b_run.lua` — the table, the decoded halt line, and the two-clock stall sample.
- `harness/tools/p3b_show.ps1` — `-Diag`, and the symbols these read.

### 3 — Pre-dispatch grep (C-13)
| check | expected | found |
|---|---|---|
| `p3b` | `58AD3C27…` 13,918 B, spare 8 | ✔ `P3_CODE_END $52F8`, `CP_CEL $5300` |
| `p3b_text` | `AF0B2A02…` 15,036 B | ✔ |
| `p3b_notick` | `2268DAB7…` 15,033 B | ✔ |
| delta | 3 | ✔ |
| untracked | the two known files | ✔ exactly those |
| `tx_msgptr` call sites | exactly two | ✔ `vm_text_ops.s:188` (display), `:213` (print) |

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — the differential table.** **MET.** §4A.
- **AC-2 [state-comparable] — the buffer checksum differs across message numbers.** ★★★ **UNMET.**
  `print` does not substitute because it does not run; the checksum test cannot be applied.
- **AC-3 [state-comparable · fault injection] — the fault arm goes red.** ★★★★★ **UNMET.** §4D.
- **AC-4 [state-comparable] — var 21 consumed.** ★★★ **UNMET**, and the reason is now exact: the
  wait loop is entered (that much is new and confirmed) but never exits, so `tx_wt_done`'s zeroing
  of var 21 is never reached.
- **AC-5 [byte-comparable · gate] — `vm` 9/9 fresh.** **MET.** All nine titles PASS.
- **AC-6 [byte-comparable · gate] — `res` 1,264/1,264 fresh.** **MET.** 10 sweeps, all clean.
- **AC-7 [byte-comparable] — `p3b` byte-identical.** **MET.** `58AD3C27164BD63F`, 13,918 B, spare 8.
- **AC-8 [suite] — full suite green.** **MET.** `pic` 45/45 · `res` 1,264/1,264 · `cel` 9,193/9,193 ·
  `comp` 124/124 · `p3b` 160 cycles · `p3b_text` 120 cycles, **171 s**.
- **AC-9 [manifest] — re-baseline.** ★★ **NOT APPLICABLE, and that is the correct outcome.** Both
  rows reassemble to their recorded hashes; the diagnostic is a third configuration that is not a
  gate row. **Nothing to retire.**
- **AC-10 [eye gate] — Jay.** **Not offered.** AC-3 did not pass; the dispatch conditions it on that.
- **AC-11 [tooling]. MET.** `[hal-sync] OK … (11 files compared)` · `[reg-discipline] 8 register
  access(es) in 1 file(s)` · `CHECK OK: vm_tables.s matches optable.py` (179 of 183 commands wired).
- **AC-12 — candidates.** §10.

### 4A — ★★★★★ The differential table

One run, both call sites, Kingquest2 jumped to room 98 at cycle 8 with `17=1`, 40 cycles.
**Counts come from `tx_diag_n1`/`tx_diag_n2`, not from scanning the buffer** — see §4A.2.

| site | msgno | `vm_code` | `codelen` | `tx_msgpos` | count read | curlogic | ok | cyc |
|---|---|---|---|---|---|---|---|---|
| display | 4 | `$7C07` | 225 | `$7CE8` | 4 | 180 | **1** | 1 |
| print | — | — | — | — | — | — | — | — |

> ★★★★★ **1 display record. 0 print records.** `tx_msgptr` is never called from `print`.

The display row is healthy and is the control the dispatch wanted: `msgpos $7CE8` is exactly
`$7C07 + 225`, the count byte reads 4, message 4 is in range, and it returned success.

**Across configurations** (all with `-Diag`, 40 cycles):

| run | display records | print records | halt |
|---|---|---|---|
| Kingquest1, no jump | **8** (cap) | **0** | none — `vm_quit=0`, `vm_badop=$00`, `res_err=0` |
| Kingquest2, no jump | 1 | **0** | ★★★ `RES_E_DEPTH`, logic 0 |
| Kingquest2 → room 98 | 1 | **0** | ★★★ `RES_E_DEPTH`, logic 0 |

**4A.1 ★★★★★ Blocker one: Kingquest2 halts, and it halts without the jump too.**
`vm_run.s:114`'s `vm_res_fail` does `lda res_err / ora #$F0 / sta vm_badop`, so **`$F6` decodes as
`res_err` 6 = `RES_E_DEPTH`** — more than `RES_MAXDEPTH` (8) resources held at once, in a constant
sized "against a MEASURED maximum LOGIC call depth of 3" (`res_core.s:61`). It halts in **logic 0**.
★★★★ **So P6.30 §4C.3 exonerated `res_err=6` on the grounds that the no-jump control showed it too.
The control showing it is the finding, not the exoneration**: Kingquest2 is halted on the port from
its intro onward, and the room jump was landing on an already-dead VM. Kingquest1 is clean, so this
is not universal.

**4A.2 ★★★★ The dump's first version fabricated eight rows, and §2W caught it.** It decided a slot
was empty by testing its site byte against 0; unwritten `MAP_INPUT` holds `$FF`, so it printed eight
all-`$FF` rows labelled "print" — **the exact rows this task existed to read.** I was one step from
reporting `vm_code=$FFFF` as a finding. The counters are incremented at the moment a record is
written and are the only thing that knows how many exist. **A diagnostic must not infer how much it
recorded from the recording.**

**4A.3 ★★★★★ And the instrument broke the routine it measured.** The first `-DTX_MSGDIAG` build put
`clr tx_diag_cnt` between `sta tx_msgno` and `beq tx_mp_bad`. **`clr` sets Z unconditionally, so
every call took the out-of-range branch** — and the logger then reported, perfectly self-
consistently, `msgpos $0000`, `count 0`, `ok 0` for a message number of 4. It looked exactly like
the defect the dispatch predicted. ★★★ Caught because `msgpos $0000` contradicts
`vm_code + codelen`, and confirmed by the fix: the same run now yields `msgpos $7CE8`, `ok 1`, **and
a `P3_PBUF` checksum of `$7B94` identical to the clean build's**, which is the evidence that the
diagnostic no longer perturbs. ★★ §2W.3, self-inflicted, in the instrument built to answer a §2W
question.

### 4B — The dispatch's leads, answered by the table

1. **The arena window's mapping at the moment of the read.** ★★★ **WRONG, and cleanly so.** The
   count byte read at `,x` is **4** — a plausible message count, not framebuffer content — and
   `msgpos` is exactly `vm_code + codelen`. The dispatch said this column "decides this outright";
   it does. **The arena is mapped correctly when `tx_msgptr` runs.**
2. **Staleness across `vm_call_logic`'s unwind.** ★★ **Not reached.** `print` never calls
   `tx_msgptr`, so there is no stale-input question to answer. `display`'s `codelen` (225) is
   consistent with its `vm_code` and its count byte.
3. **The message number's provenance.** ★★ **Not reached for `print`.** For `display` the value is
   4 and in range, so the `vm_v*` path delivers a value and not a variable number.
4. **The bind itself.** ★★★★ **THIS ONE IS RIGHT, and it is the whole of blocker one.** The error
   room's logic was never bound: the VM had already halted in logic 0 with `RES_E_DEPTH`.

★ Lead 1 was the Orchestrator's strongest and it is wrong; lead 4 was the weakest and it is the
answer. Stated plainly per §7's instruction.

### 4C — Blocker two: the box draws, and the tick source is dead

Kingquest2 halts, so I moved to the other candidate P6.30 §4B confirmed clean — **SpaceQuest-2 room
101**. It does not halt. It stalls:

```
★★★ STUCK in cycle 9 after 1800 frames (30.0 emulated s) -- most-visited PCs:
     $4C2C  x223   HAL_key_scan + 2
     $4C44  x202   hal_ks_go
     $57A3  x175   tx_wt_loop + 3
     $4C31  x67    HAL_key_scan + 7
     $4C40  x67    hal_ks_go
     $57BA  x66    tx_wt_tick + 5
```

★★★★★ **That is the blocking wait, running.** The box drew, `print` blocked, and the loop is
polling the key matrix — which is `tx_wait_dismiss` doing exactly what it was written to do.

Why it never leaves:

```
across the stall: hal_frame 0 -> 0 (+0),  vm_vms 49 -> 49 (+0)
★★★ THE VBL COUNTER IS FROZEN
tx_wt_end=109 tx_wt_timed=2 (var21 as read at entry)
```

★★★★ **The arithmetic is correct** — var 21 = 2, deadline `49 + 2*30 = 109`. ★★★★★ **The tick
source does not exist.** `tx_wt_tick` advances the game clock only when `hal_frame_lo` changes;
`irq_vbl.s` supplies `hal_vbl_handler` and **nothing anywhere installs the `$010C` vector or enables
GIME VBORD** — no probe calls an installer, and none exists. `hal_frame` is 0 for the life of the
run, so the edge never fires, `vm_step_clock` is never called, and the deadline is unreachable.

★★★★★ **My own §4A census in P6.29c asserted `hal_frame_hi/lo` is "SELF-SERVICING — the `$010C` IRQ
advances it through a block".** That was an assumption written in a table of measured facts, and it
is false in this probe. **It is the reason the tick source was chosen.**

### 4D — The two arms, and why they are identical

Same trigger, SpaceQuest-2 room 101, clean vs `-DTEXT_FAULT_NOTICK`:

| observable | clean arm | fault arm |
|---|---|---|
| outcome | **STUCK in cycle 9**, 1800 frames | **STUCK in cycle 9**, 1800 frames |
| top PCs | `$4C2C ×222`, `$4C44 ×202`, `$571B ×178`, `$572F ×67`, `$5732 ×67`, `$4C31 ×66` | **identical** |
| `hal_frame` across stall | 0 → 0 | 0 → 0 |
| `vm_vms` across stall | 49 → 49 | 49 → 49 |
| `tx_wt_end` / `tx_wt_timed` | 109 / 2 | 109 / 2 |

★★★★★ **Identical, and now for a reason that is fully explained rather than merely observed:** the
omitted `jsr vm_step_clock` sits **after** the tick-edge test. `tx_wt_tick`'s `beq tx_wt_loop` takes
the same-tick branch on every iteration in both arms, so **neither arm ever executes the instruction
that distinguishes them.** The 3-byte difference is downstream of the blocker.

★★★ **Per §4D and §6's first trigger this is a stop.** The fault injection cannot fail while the
tick source is dead, and tuning it until it goes red would produce a green check that means nothing.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:**
```
=== AC-2 SUMMARY ===   [vm_run.ps1]
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS  SpaceQuest-1 PASS  SpaceQuest-2 PASS
PoliceQuest1 PASS  larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS

=== TOTAL ===          [res_run.ps1]
byte-identical resources: 1264 across 10 (title, volume) sweeps
all sweeps clean

per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ gates run: pic res cel comp p3b p3b_text  -- all green        [171 s]

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
CHECK OK: src/harness/vm_tables.s matches optable.py.   [179 of 183 commands wired]

p3b        13918 B 58AD3C27164BD63F  IDENTICAL
p3b_text   15036 B AF0B2A027A960DF4  IDENTICAL
p3b_notick 15033 B 2268DAB7B3CFE6D0  IDENTICAL
```
**25.2 bundled-artifact grep:** N/A — no artifact changed; all three reassemble to their baselines.
**25.3 operator-runtime-smoke:** **Not offered** — AC-3 did not pass (AC-10's own condition).

### 6 — Reactive deviations and route accounting
1. ★★★★★ **Stopped at §4D and at §6's first trigger.** The box draws, the arms remain identical, and
   the cause is a dead tick source. **No fix attempted.**
2. **Did not fix `RES_E_DEPTH`** — §6's fifth trigger names `res_core.s` explicitly as a wider blast
   radius than this dispatch authorises. Reported, not repaired.
3. **Moved the trigger from Kingquest2 to SpaceQuest-2** once the halt was identified. §2 said not to
   hunt for a better room, and I did not re-run the census: SpaceQuest-2 101 is P6.30 §4B's other
   already-confirmed candidate. Without it the run would have stopped at blocker one and blocker two
   would still be unknown.
4. ★★★ **ROUTE ACCOUNTING.** §4A and §4B are delivered in full. §4C ("fix what §4A names") is
   **deliberately not done** — see §7.1 for why the choice is not mine to make. §4D is delivered as
   the stop it specifies.

### 7 — Uncertainty flags

**7.1 ★★★★★ The fix is a real design choice and it is above this dispatch.** Two routes, and they
differ in where the blast radius lands:

| route | what it means | cost |
|---|---|---|
| **(a) enable the VBL IRQ in the probe** | install `$010C`, write `$FF92`/`$FF93`, clear `CC.I` | ★★★★ Touches interrupt state for the *whole* probe — the renderer's timing, the MMU phase machinery and `-nothrottle` all currently run with no IRQ at all. It is also the shape the real interpreter must eventually have. |
| **(b) pace the wait loop off its own iteration count** | keep the deadline on `vm_vms`; replace "when `hal_frame_lo` changes" with "every N iterations" | ★★ Contained to `vm_text_ops.s`. But N is a calibration, and a wrong N makes var 21's half-second wrong on hardware where (a) would be exact. |

★★★ **I did not pick.** Route (a) is §6's "wider blast radius"; route (b) is contained but trades a
measured unit for a tuned one, and P6.29c chose the game clock precisely because the oracle mandates
it.

**7.2 ★★★★ `RES_E_DEPTH` on Kingquest2 is a separate, larger defect.** `RES_MAXDEPTH` is 8 against a
measured maximum LOGIC call depth of 3, and the halt is in logic 0. `res_depth` read **7** at the end
of the run, but that is sampled at the end and not at the halt, so it is not evidence of the depth at
failure. Whether this is a genuine deep nest or a resource that is opened and never released is
unmeasured. Kingquest1 is unaffected; the other seven titles are untested for it.

**7.3 ★★★ The `vm` gate passes 9/9 while Kingquest2 halts in `p3b`.** Not a contradiction — different
probes — but it is worth stating that **the state diff and the integration probe disagree about
whether Kingquest2 runs**, and only one of them binds resources through `res_core.s`'s arena.

**7.4 ★★ The diagnostic build has 34 bytes of headroom** (`P3_CODE_END $57DE` against `P3_FONT
$5800`). It is not a gate row and need not fit forever, but a reader adding to it should know.

**7.5 ★★★★★ I corrupted a file with PowerShell again, in the same session in which I reported doing
it.** `Set-Content -Encoding UTF8` on `p3b_show.ps1` added a BOM and double-encoded **59 runs** of
`★`. Repaired with `fix_mojibake.py`, BOM stripped, and all four touched files verify clean; the
resulting diff is 18 lines, so nothing was mass-rewritten. ★★★ **Twice in two tasks means the note
is in the wrong place** — it is a memory, and the thing that would have stopped it is a hook or a
pre-commit check. Recorded as a standing defect rather than as an apology.

### 8 — Follow-up candidates
1. ★★★★★ **Decide route (a) or (b) for the wait loop's tick source** (§7.1). Nothing about the
   blocking box can be gated until this is settled.
2. ★★★★ **Kingquest2's `RES_E_DEPTH` halt in logic 0** (§7.2) — its own task, with `res_core.s`'s
   depth accounting and a sweep of the other seven titles.
3. ★★★ **`p3b` runs with no interrupts at all.** Worth stating as a standing property of the probe
   somewhere durable; it invalidated a census entry that had been written as measured fact.
4. ★★ **A pre-commit mojibake check** (§7.5). `fix_mojibake.py --check` already exists and exits
   non-zero; it is not wired to anything.
5. ★ **`p3b_show.ps1`'s allowlist filter** — fifth instance, still open.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-12-an-instrument-can-manufacture-the-defect-it-was-installed-to-find.md`
- `seeds/AGI/live/2026-09-12-a-census-entry-asserting-a-mechanism-is-live-must-name-who-runs-it.md`

### 11 — Commit
`e2f4379` — the diagnostic and this report (pushed to origin/wip before reporting).
Pool: `methodology-candidate-pool` `4b23982`, two rows under `seeds/AGI/live/`.
