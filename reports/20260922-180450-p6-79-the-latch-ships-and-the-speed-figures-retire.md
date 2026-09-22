## Form B Report — T-P0-132 / P6.79 — The latch ships; `$FFA6` still has two owners; and three tasks' speed figures retire
**Class:** integration (§4A). wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-22T00:44:54Z (HEAD b051dde, wip). git status clean at receipt (untracked
`coco_agi.code-workspace`, not mine).

### 1 — Summary

**Part A — the latch ships.** §1.1's premise is CONFIRMED: it was failing on P6.78's corruption,
not on itself.
- **20 of 20** presses delivered, against **1 of 20** for the per-cycle scan (P6.75 measured 10 of
  20 for the *level* scan it then had).
- **420 castle cycles, no input: the port moves exactly as the oracle-gated reference does** — ego
  still, obj 11 stopping at (147,161), obj 12 at (147,51), window for window. **No
  latch-specific difference: the latch arm and the no-latch arm are identical cycle for cycle.**
- **Logic 1's resident copy: 0 of 256 bytes differ** at the end of the run. The interrupt does not
  reopen P6.78's class.
- **Jay:** taps register without holding (1), everything keeps moving (3) — **P6.75's failure, asked
  directly, did not recur.**
- `-DP3B_VBLKEYS_OPT` is retired; the combined arm ships the latch and `-NoVblKeys` is its fault arm.
  ★ **`p3b_comb` is now byte-identical to the arm those measurements were taken on** (18,869 /
  30AEF5F9).

**Part B — B.1 done, B.2 STOPPED under §6.**
- ★★★★★ **The census now sees both writers and reports the red:** `$FFA6`, owners
  `src/engine/mmu_phase.s` **and** `src/harness/res_core.s`. Its roots were `src/engine` alone; the
  storage layer lives in `src/harness`, so `res_map_block`'s write had never been counted.
- ★★★★★ **B.2 stops on a hard obstacle, not a judgement call:** `res_probe.s` and `vm_probe.s` —
  the producers of the `res` and `vm` gates — include `res_core.s` and **not** `mmu_phase.s`, and
  `memmap.inc:470` **refuses to assemble `mmu_phase.s` without `PLANE_WINDOWED`**. Routing storage's
  mapping through the phase module would move both gate probes onto the windowed memory map.
  §6: *"stop and report, do not repair."* The design and the obstacle are in §7.1.

★★★★★ **And an unplanned finding that retires three tasks' headline numbers.** Re-profiling the
castle on P6.78's *fixed* build gives **0.92 s/cycle in stages (1.1 cycles/s), not 0.245**. Same
binary hash, same staging, same scenario as P6.77's measurement — the only difference is the
`plane_reset` fix. **P6.76's profile and P6.77's speed figures were measured on a game that had
been crippled by data corruption at cycle 18**: the death branch stops the ego, erases objects and
does very little work. With the game actually running, `interpret` goes 0.263 → 0.577 s/cycle and
the resource layer is **62% of the cycle** (`res_cache_stash` 24%, `res_fetch` 19%, `res_decode`
19%): the logic cache thrashes, with 155 bytes free in a full arena.

### 2 — Files modified
- `src/harness/p3b_probe.s` — the latch's flag block: shipped, not opt-in; the parking note
  resolved (§9).
- `src/harness/res_core.s` — §9: the false *"this is the ONLY routine that writes it"* corrected,
  with what the sentence cost and why the fix is not here yet.
- `harness/tools/reg_discipline.py` — roots widened to `src/engine` + `src/harness`; 16 probes
  allowlisted **by explicit filename**; header records P6.38 and P6.79 as the two times the narrow
  root hid a writer.
- `harness/tools/p3b_show.ps1` — `-VblKeys` is a no-op (default); want-line condition follows the
  source's new condition.
- `harness/tools/p3b_arms_check.ps1` — the two combined arms re-baselined (+51 B, the latch).
- `harness/tools/ego_ref.py` — `--dir0` and `--watch` (the reference's objects, per window).
- `reports/20260922-180450-p6-79-the-latch-ships-and-the-speed-figures-retire.md` — this report.

### 3 — Reasoning

**§3(1)** Nine arms verified at P6.78's figures before any change.

**§3(2) The latch arm on P6.78's base.** It still builds, and **the pieces compose directly**: the
IRQ enqueues key-down edges, and P6.78's dispatcher already drains a queue (`p3_kq_get` in
`p3_poll_dir` and in `tx_wait_dismiss`). The per-cycle edge detector is excluded in that arm
(`ifndef P3B_VBL_KEYS`), so **the PIA has exactly one owner, the interrupt** — §1.2's rule, met by
construction. The only byte the latch arm gained from P6.78 was `plane_reset`'s 3.

**§3(3) ★★★★★ Every writer of `$FFA6` in the tree, across `src/`:**

| writer | file | sites | its cache |
|---|---|---|---|
| `phase_vm`, `phase_draw`, `phase_draw_fb`, `phase_draw_pri_slot6`, `phase_vol` | `src/engine/mmu_phase.s` | 5 | `pl_vis_cur` / `pl_pri_cur` in `plane_win.s`, one layer up |
| `res_map_block` | `src/harness/res_core.s` | 1 | `res_curblk` |
| `sta $FFA6` at boot / mode set | `src/hal/coco3-dsk/sys.s:239`, `gfx.s:655` | 2 | none; not called in the cycle |
| `sta $FFA6` | `src/harness/input_probe.s:83` | 1 | a probe, allowlisted |

**§3(4) Readers and invalidators**: `res_curblk` is read only in `res_map_block` and invalidated in
`p3_enter_vm_phase`, `tx_window_exit` and before every VIEW fetch in `p3_composite_all` (P6.74);
`pl_vis_cur`/`pl_pri_cur` are read in `plane_vis`/`plane_pri` and invalidated by `plane_reset`,
called from `tx_window_exit`, `phase_draw_enter` and — since P6.78 — after each VIEW fetch.
★★★ **Two records of one register, each invalidated where its author remembered the other.**

#### Part A — measurements

| | latch | no latch |
|---|---|---|
| presses made / delivered (P6.75's scenario, 20 ENTERs) | **20 / 20**, 0 dropped | 20 / **1** |
| 420 castle cycles, no input | room 1 throughout, no box, no stall | identical |
| ego / obj 11 / obj 12 movement per 50-cycle window | 0 / stops c35 (147,161) / stops c125 (147,51) | identical |
| **the reference**, same 420 cycles | **0 / stops c35 (147,161) / stops c125 (147,51)** | — |
| logic 1 resident copy vs the game file | **0 of 256 differ** | 0 of 256 |
| castle window cost (profiler span, 35 cycles) | 24.998 s | 24.964 s → **the latch costs 0.14%** |

★★★ **The alligators stopping at x=147 is the `checkPriority` omission, not a freeze**: 147 is the
right-edge clamp, and **the oracle-gated reference does the same thing in the same windows**. Out of
scope [§2], and now measured rather than assumed.

★★★★ **A test that measured nothing, and was replaced.** My first A.2(2) gave Graham a RIGHT press
and watched for 420 cycles: he walked out of the castle at ~cycle 60 (`new.room`), which is why the
alligators "stopped" — they do not exist in the next room — and the run stalled at 411 in a later
room, with or without the latch. **The run has to keep him in the room being measured.**

#### Part B — B.1's red, quoted before any change
```
[reg-discipline] scope: src/engine, src/harness  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 16 file(s)
[reg-discipline] 18 register access(es) in 2 file(s) over 4 register(s).
  reg      count  hal-owned  owners
  $FFA3        2  no         src/engine/mmu_phase.s
  $FFA4        2  no         src/engine/mmu_phase.s
  $FFA5        7  no         src/engine/mmu_phase.s
  $FFA6        7  no         src/engine/mmu_phase.s src/harness/res_core.s
```
★★ **No other register gained an owner** when the roots widened, so §6's "more than two" trigger did
not fire. `$FFA3/4/5` remain `mmu_phase.s` alone.

#### The retired speed figures
Same scenario (castle, cycles 20-55, 997 Hz profiler), same staging (vol.0 6 blocks at 8, vol.1 25
at 14), same `remaps total 186`, same arena readouts:

| build | interpret | composite | roomcheck | SUM | window span |
|---|---|---|---|---|---|
| 32F9D982 (P6.78 part 1, **corrupted game**) | 0.2632 | 0.1726 | 0.1613 | **0.602** | 8.577 s |
| BD28251C (P6.78 final, **fixed**) | **0.5768** | 0.1730 | 0.1613 | **0.916** | 24.964 s |
| 30AEF5F9 (this task, fixed + latch) | 0.5785 | 0.1735 | 0.1618 | 0.919 | 24.998 s |

★★★★★ **Only `interpret` moved.** The corrupted logic 1 ran the death branch — `program.control`,
`stop.motion`, the ego erased — and did a fraction of the real work. **Every s/cycle figure from
P6.76, P6.77 and P6.78 is a measurement of a crippled game** and is retired here.

### 4 — Verification (AC-by-AC)
- **AC-1 [state-comparable] PASS** — 20/20 delivered, 0 dropped; fault arm 1/20.
- **AC-2 [state-comparable] PASS, as compared** — 420 cycles, positions changing throughout where
  the reference's do, stopping where the reference's stop. ★ Not "everything moves for 420 cycles":
  the reference does not either, and that difference is `checkPriority`, out of scope.
- **AC-3 [state-comparable] PASS** — logic 1: 0 of 256 differ.
- **AC-4 [eye gate — Jay] PASS, with two notes.** *"1. yes"* (taps register), *"3. yes"* (everything
  keeps moving). Notes: *"2. they do arrive but slowly"* — the queue captures every letter, but the
  cycle drains ONE key per cycle, which at ~1 cycle/s is the real limit and is the oracle's own
  shape [cycle.cpp:350-351]; *"4. still have the 'press a key to continue' artifact in the text
  window"* — the harness's room jump skips the title's own `clear.lines` [P6.77 §7.2], unchanged.
  **Ruling §A.4: passes → the latch ships.**
- **AC-5 [tooling · fault] PASS** — the two-owner output, quoted in §3 before B.2.
- **AC-6 [tooling] NOT MET — B.2 stopped.** The census still reports two owners; it now guards the
  property and will show one when the fix lands.
- **AC-7 [design] PARTIAL** — the design is stated in §7.1 and at `res_core.s`'s corrected comment;
  the single record is not built.
- **AC-8 [state-comparable · fault injection] PASS** — `-NoPlaneReset` still red on the new arm
  (flag 63 at cycle 18, ego stops at 113). ★ That build is **B38C1357**, byte-identical to the
  pre-fix latch arm, which is the fault arm removing exactly the 3-byte fix.
- **AC-9 [byte-comparable · gate] PASS, fresh** — **vm 9/9 RUN**; res **1,264/1,264**; pic 45/45;
  cel 9,193/9,193; comp 124/124.
- **AC-10 [suite] PASS** — five p3b rows green; fault arms red (`-NoVblKeys` 1/20, `-NoPlaneReset`
  above, `-SelfTest` on its own row).
- **AC-11 [measurement] PASS** — `res_remaps` **186 before and after** (the latch changes no
  mapping); s/cycle **0.916 → 0.919, +0.14%**. Part B changed no code, so it costs nothing.
- **AC-12 [manifest] PASS** — two arms re-baselined; **the latch's status: SHIPPED**, recorded in
  the arms table and in `p3b_probe.s`.
- **AC-13 [tooling] PASS** — hal_sync ×3 OK; gen_vm_tables OK; probe_identity 5/5 (unmoved: no
  non-p3b probe was touched); arms `-SelfTest` red.
- **AC-14** — §10.

### 5 — Verdict-time evidence (v0.7 §11)
```
p3b         15632 B  0B7B0D00  OK        p3b_flat    15878 B  681455A6  OK
p3b_text    16856 B  A7F35693  OK        p3b_comb    18869 B  30AEF5F9  OK   <- the latch ships
p3b_win3    16856 B  78994468  OK        p3b_comb_count  18904 B  5A6B5DE1  OK
p3b_notick  16853 B  4C3AC864  OK        ★ all 9 arms byte-identical to the recorded baseline
p3b_nomap   16853 B  DC6F6BB2  OK        ★ every non-p3b probe byte-identical
p3b_fault   15893 B  17689A91  OK
=== AC-2 SUMMARY === 9 x PASS            vm_probe: 9985 bytes
per-picture 45 PASS | resources 1264/1264 | cels 9193/9193 | composites 124/124
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
[hal-sync] OK (11 files) | CHECK OK vm_tables.s | source integrity: clean
[reg-discipline] $FFA6 owners: src/engine/mmu_phase.s src/harness/res_core.s   <- the red, kept
```
**25.2:** N/A. **25.3:** `PASSED — Jay, poke, RGB, live: taps register without holding, everything
keeps moving; two notes recorded (drain rate, the title-line artifact)`.

### 6 — Reactive deviations and route accounting
- **B.2 not attempted**, per §6. The obstacle is structural (`memmap.inc:470` + two gate probes that
  do not link `mmu_phase.s`), measured rather than predicted.
- **The census's allowlist gained 16 filenames.** Widening the roots without exempting the probes
  would have reported probe pokes as port accesses. **By filename, one line each**, per its own rule.
- ★★★★ **The speed re-measurement was not asked for.** It came out of AC-11 and contradicts three
  tasks' headline figures, so it is reported rather than left to be discovered.
- **§9 `memmap.inc:310` `MAP_PRI_BANDS`: not done, 26th task** (§6 stop trigger).
- **Route accounting:** everything I proposed is in the commit; B.2 and B.3 are explicitly not.

### 7 — Uncertainty flags

#### 7.1 The `$FFA6` design, and why it stopped
**The design** (unbuilt): `mmu_phase.s` holds ONE record of what slot 6 contains, updated by every
routine there that writes it; `res_map_block` maps through that file instead of writing the register;
`plane_vis`/`plane_pri` test the same record instead of their own slice caches. ★★★ **Then no cache
can disagree with the register, because there is only one**, and `plane_reset` becomes unnecessary
(AC-8's arm would have to be replaced by one that reintroduces a second cache).

**Why it stopped:** `res_probe.s` and `vm_probe.s` include `res_core.s` and not `mmu_phase.s`, and
`memmap.inc:470` refuses `mmu_phase.s` without `PLANE_WINDOWED` (measured: it assembles to 75 bytes
with that flag, and errors without it). **The `res` and `vm` gates would move to the windowed memory
map to give storage a mapping call.** A smaller variant — a shared record in its own include, used
by both writers — avoids the flag but still moves five probes' bytes and **still leaves two writers**,
so the census would stay red. Both are the Orchestrator's to rule on.

#### 7.2 ★★★★★ For Jay — the speed number was wrong, and the reason is good news
Every "cycles per second" figure I gave you in the last three tasks was measured on the corrupted
game. The corruption made the interpreter do **less** work — Graham was dead and the room had given
up — so it ran fast. **Now that the game is actually running, a castle cycle is about 0.92 s, so
roughly one cycle a second.** That is why typing still feels slow to you: the game accepts one
keypress per cycle, as the original does, and the cycles are slow.

**The good news is where the time goes.** 62% of a cycle is now the resource layer re-fetching and
re-decoding the room's logic **every cycle**, because the cache is full: 155 bytes free in a 16 KB
arena. **That is a cache-size and residency problem, not a drawing problem** — and it is the first
thing I would attack now, ahead of the compositor work that was queued.

#### 7.3 Other flags
- **The alligators' stop at x=147 matches the reference exactly.** Both omit `checkPriority`. The
  real oracle keeps them in the moat; neither of ours does.
- **The 420-cycle latch run stalls at cycle 411 if Graham leaves the castle** — a later room puts up
  a box with no auto-close. Not investigated; the measurement was re-scoped to stay in room 1.
- **`p3b_comb_count`** (the counting arm) is now 18,904 B: it carries the latch too.
- **Letters arrive at one per cycle.** That is `cycle.cpp`'s shape, not a defect, but at ~1 cycle/s
  it is a poor typing experience until the cycle gets faster.

### 8 — Follow-up candidates
1. ★★★★★ **The logic cache and the arena**: 62% of a castle cycle is re-fetch + re-decode + re-stash.
   Measure the room's working set against the 16 KB arena; the cache is thrashing every cycle.
2. ★★★★★ **One owner for `$FFA6`** — §7.1's design, once the gate-probe question is ruled on.
3. ★★★★ **`checkPriority`/`checkCollision`** — the moat, and every control-line behaviour.
4. ★★★ **Re-run the compositor pricing task** against the corrected baseline: the compositor is now
   19% of a cycle, not 81%.
5. ★★★ The cycle-411 box in the room right of the castle.
6. Carried: real-time pacing, `MAP_PRI_BANDS` (26th).

**PROPOSED TEXT for the design spec [§2D], §5.4a's rate table:**
> ★★★★★ *RETIRED at P6.79: the 0.245-0.300 s/cycle castle figures of P6.76-P6.78 were measured
> while the compositor was corrupting the game's own staged data, which sent room 1's logic into a
> death branch that does a fraction of the work. **Corrected: 0.92 s/cycle in stages, ~1.1 cycles/s,
> of which the resource layer is 62%** — the logic cache thrashes against a full 16 KB arena.*

### 9 — User interaction during task
1. Eye gate (Part A). Jay: *"1. yes, 2. they do arrive but slowly. 3. yes. 4. still have the 'press
   a c\key to continue artifat in the text window."*
2. Jay: *"are you stuck"* / *"continue"* — I had gone quiet mid-measurement; no scope change.

### 10 — Candidate(s) captured this task
- `2026-09-22-a-performance-figure-taken-on-a-broken-build-measures-the-breakage` — pool commit in §11.

### 11 — Commit
(filled in by the follow-up commit)
