## Form B Report — T-P0-097 / P6.42 — The seams do not match, and no shift can align them
**Class:** measurement.  wip.  **No `src/` change.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-13 19:30 (HEAD 1dad433, wip). One harness tool modified. `git diff --stat -- src/` is
**empty**.

### 1 — Summary
★★★★★ **§1.1 is right and it is worse than stated: the two probes sample a FRACTION of a cycle
apart, so no integer record shift aligns them.** At offset 0 the port is a whole body ahead; at
offset +1 it is a pace-and-feed behind.

★★★★★ **Two of P6.41's five bytes were seam artefacts.** At the corrected alignment `var 10` and
`var 88` stop differing entirely — **§1.3's reading was correct.**

★★★★★ **And flag 2 does not survive either.** It differs at both alignments, but at each one it is
the feed landing on one side of the sample and not the other. **The only byte that survives both is
`var 0` — the room — which is the effect.**

★★★★★ **§4D inverts P6.41's chain.** `op_test.cpp:509-513` takes the displacement when the condition
is **FALSE**, so `goto +N` skips the block. `v88 = 4` therefore executes **when `said(161)` is
TRUE** — and both sides end cycle 100 with `v88 = 4`. ★★★★ **Both matched the command. The
"flag 2 was clear so `said()` failed" chain is dead.**

### 2 — Files modified
- `harness/tools/p3b_run.lua` — `P3B_PHASETAP` (dropped, see §4C), the third closure-scope fix.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| seven artifacts | P6.40's hashes | ✔ |
| untracked | one file | ✔ |

**§3(3) `P3_PHASE`** [`p3b_probe.s:885-922`]: **1** before `vm_pace`; **2** after the feed and the
key poll, **before `vm_interpret_cycle`**; **3** immediately after; **4** after `vm_post_cycle`.

### 4A — ★★★★★ THE THREE SEAMS, QUOTED. This is the deliverable.

**`vm_probe`** [`vm_probe.s:384-435`] — its own comment: *"FEED HERE — AFTER THE PACING GATE, BEFORE
THE PUBLISH AND THE PARK … Order: interpret → reset → pace → FEED → sample."*
> **record "cycle N" = pace(N) ✔ · feed(N) ✔ · interpret(N) ✘ · post_cycle(N) ✘**

**the reference** [same comment, citing `cycle.py:418-427`]: *"feeds immediately before
interpret_cycle(), which emits the trace row at its top, so the reference's row for cycle N already
carries ENTERED_CLI."*
> **record "cycle N" = pace ✔ · feed ✔ · interpret ✘ · post_cycle ✘** — the same instant as `vm_probe`.

**`p3b`** [`p3b_probe.s:884-923`, and the park at `p3_loop`]: the host samples at the park, which is
**before** `p3_do_cycle`; `P3_CYCLE` is incremented at the **end** of the body, so the row the host
labels N is taken after cycle N completed.
> **record "cycle N" = pace(N) ✔ · feed(N) ✔ · interpret(N) ✔ · post_cycle(N) ✔**

★★★★★ **They are NOT the same instant.** `vm_probe` and the reference agree with each other and
differ from `p3b` by **the entire cycle body plus `vm_post_cycle`**.

★★★★★ **And no integer shift fixes it.** `p3b`'s row N and the oracle's row N+1 still differ by
`pace(N+1)` and `feed(N+1)` — a fraction of a cycle. **Offset 0 is a body too early; offset +1 is a
feed too late.** Both are wrong, in opposite directions.

### 4B — The re-diff, and which bytes survive

| byte | offset 0 | offset +1 | verdict |
|---|---|---|---|
| **var 10** (TIME_DELAY) | oracle 2, port 4 | **no difference** | ★★★★ **seam artefact** |
| **var 88** (speed shadow) | oracle 2, port 4 | **no difference** | ★★★★ **seam artefact** |
| **flag 2** (ENTERED_CLI) | differs at c100 | differs at c99 | ★★★★ **seam artefact — the feed is on one side of the sample and not the other at BOTH offsets** |
| **var 11** (a timer) | no difference c97-99 | differs from c99 | ★★★ **seam artefact** — it moves with the alignment |
| **var 0** (room) | oracle 1, port 0 | oracle 1, port 0 | ★★★★★ **SURVIVES — and it is the effect, not the cause** |

★★★★★ **So nothing in the 288-byte state block differs BEFORE the restart, at either alignment.**
That is AC-5/AC-8's negative result: **the divergence is outside these 288 bytes.**

★★★ **And P6.41's "cycles 95-99 byte-identical" was not evidence either.** The reference's own state
is **completely static** across cycles 93-99 — 0 bytes differ between consecutive records — so every
offset matches there. **That is also why the `--scan` was flat**, and P6.41 read flat as "not
alignment-sensitive" when it means "the state does not change, so alignment is invisible."

### 4C — The direct reads: three of four, and one instrument dropped

1. **`par_egon` = 1, `par_cli` = 1** — from `p3b_parse`'s readback: *"1 word(s) [161] notfound=0"* at
   cycle 100, exactly as §2 predicts.
2. ★★★ **Flag 2 immediately after the feed — NOT OBTAINED.** See below.
3. **Flag 2 after `post_cycle`** = 0, from the port's own row (§4B).
4. **`vm_restart` at cycle 100 — NOT OBTAINED**, same cause.

★★★★ **`P3B_PHASETAP` was built and dropped [§4D's own provision].** A write tap on `P3_PHASE`
(`$003E`) **never fires** — verified with the filter removed entirely, which is the §2W check:
capturing the first 24 markers unconditionally also produced nothing, so it is the tap and not the
filter. MAME's write tap does not catch the guest's stores to that direct-page address. ★★ **Naming
what would work instead:** a tap on a non-direct-page status byte, or the guest publishing the flag
— **and the second is a `src/` change, so it stops here** [§6].

### 4D — ★★★★★ The polarity, cited, and it inverts the chain

`op_test.cpp:509-513`:
```c
// Skip the following IF block if the condition evaluates as false
if (result)
    ip += 2;
else
    ip += READ_LE_UINT16(code + ip) + 2;
```
★★★★★ **The displacement is taken when the condition is FALSE.** `agidis.py`'s `goto +N` is the
**false** arm; the block executes when the condition is **true**.

Applied to logic 0:
```
01FC  if (|| said(161) controller(24) ||) goto +6
0208  assignn(v88, 4)   020B  assignv(v10, v88)      <- runs when TRUE
022C  if (|| said(31,146) controller(3) ||) goto +1
023A  restart.game()                                  <- runs when TRUE
```
★★★★★ **Both sides end cycle 100 with `v88 = 4`** (§4B: no difference at the corrected alignment).
**So `said(161) || controller(24)` was TRUE on both — the port matched the command.**

★★★★★ **And `restart.game()` runs only when `said(31,146) || controller(3)` is TRUE.** The fed line
was **one** word; `said(31,146)` is a **two-word** pattern. ★★★ **So either our `said()` matches a
two-word pattern it should not, or `controller(3)` is spuriously set** — and those are the two
candidates the next task should separate.

### 5 — Verdict-time evidence (v0.7 §11)
```
git diff --stat -- src/ : (empty)
★ source integrity: clean

offset +1:  port c97 vs oracle c98  : identical, all 288 bytes
            port c98 vs oracle c99  : identical, all 288 bytes
            port c99 vs oracle c100 : flag 2, var 11
            port c100 vs oracle c101: var 0, var 11        <- var 10 and var 88 GONE
oracle c94..c99 vs their predecessors : 0 bytes differ     <- the state is static
op_test.cpp:510-513 : if (result) ip += 2; else ip += READ_LE_UINT16(...) + 2;
```
**25.2:** N/A. **25.3:** N/A — nothing built. ★★ **AC-7 by §2T citation to P6.40**: no `src/` file
touched, toolchain unchanged.

### 6 — Reactive deviations and route accounting
1. ★★★★ **`P3B_PHASETAP` built, shown not to fire, and dropped** (§4C) — §4D of the dispatch
   permits exactly this. **It was shown unable to fire before being believed silent.**
2. ★★★ **A THIRD closure-scope bug in the same file**, fixed: `PHASETAP` was declared below
   `stage()`, so the tap's install condition read a nil global and never ran. The two earlier ones
   were the `res_err` and `par_vocab` taps' cycle counters.
3. **ROUTE ACCOUNTING.** §4A, §4B and §4D are complete; §4C is two of four with the reason. **No fix
   attempted; no `src/` change.**

### 7 — Uncertainty flags

**7.1 ★★★★★ Two corrections to P6.41, both mine.** Its five named bytes are two artefacts, one
artefact-at-both-offsets, one timer and one effect — **so its AC-4 answer ("the divergence keyed on
flag 2") does not stand.** And its "cycles 95-99 byte-identical" carried no information, because the
reference's state is static there.

**7.2 ★★★★ The residual sub-cycle offset is unresolved and may be unresolvable by shifting.** The
honest comparison needs `p3b` sampled at `P3_PHASE` 2, which §4C could not reach without a `src/`
change. **Every `p3b`-versus-reference state claim carries this caveat**, including future ones.

**7.3 ★★★ `var 11` still differs at the corrected alignment.** It is a timer and it moves with the
seam, so it is consistent with §7.2 rather than with a divergence — **but it is asserted as an
artefact on that reasoning, not measured as one.**

**7.4 ★★ `memmap.inc`'s flag-packing comment is still stale** [P6.41 §7.3]. Proposed text unchanged:
the 256 flags are stored **packed in 32 bytes**.

### 8 — Follow-up candidates
1. ★★★★★ **`said(31,146)` and `controller(3)` at cycle 100** (§4D) — which one is true in the port.
   **The restart runs only if one of them is, and the fed line was one word.**
2. ★★★★ **Publish flag 2 and `vm_restart` at `P3_PHASE` 2** — a `src/` change, and the only way to
   close §4C(2) and §4C(4).
3. ★★★ **A gate-row note**: `p3b` and `vm_probe` sample at different instants, so any row comparing
   them across a state change is reading two moments [L-121].
4. ★★ `memmap.inc`'s packing comment · `RES_E_BIG`'s identity · `VM_ROOM` in the gate rows.

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-13-two-samplers-one-label.md`

### 11 — Commit
`6c40ada` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `1d68cae`, one row under `seeds/AGI/live/`.
