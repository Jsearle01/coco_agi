## Form B Report — P6.28g (T-P0-084g) — the two bytes are solved; `res_open`'s contract is the new blocker
**Class:** integration (§4A) — **the saving is found and works; the fix is held at a different constraint.**  wip.

★★★★★ **The 2-byte problem is SOLVED.** `p3_zero_timers` is dead code — verified, not taken on the
comment's word — and removing it frees **14 bytes**. With the fix applied **both rows build**: the
cel configuration has **12 bytes spare** against `CP_CEL` and comes out 11 bytes *smaller* than the
retired baseline.

★★★★★ **And landing it breaks the `res` gate: 1,264/1,264 → 959/1,264 (75.87%), 305 mismatches.**
The 305 are the LOGIC subset. ★★★★ **`res_decode` on the miss path changes what `res_open` RETURNS
for a LOGIC**, and the resource gate compares fetched bytes against `tools/volread/`'s **raw**
resource. **That is a contract change to the resource layer, not a probe detail** — and it is a
different constraint from the one this task was sent to clear.

★★★ **The tree is green and byte-identical to `8b522ee`** but for the new tool: res 1,264/1,264,
`p3b` at `F51FF848…`.

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-084g dispatch receipt (HEAD `8b522ee`, wip). At report time HEAD `7b30e99`.

---

### §3 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===        8b522ee  wip   ?? coco_agi.code-workspace
=== POP3_port ===       104b197  wip        === karateka_coco3 ===  29f8f0a  wip
[hal-sync] OK x3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) -- src/engine/mmu_phase.s $FFA5 $FFA6
CHECK OK: src/harness/vm_tables.s matches optable.py.

(1) p3b row:   13925 B  F51FF8482D0B07E49F46B18612D20B06        ★ as expected
(2) res_decode call sites:  res_probe.s:127                     ★ exactly one
(3) cel:   CP_CEL = 5300   P3_CODE_END = 52FF                   ★ 1 byte spare
    text:  P3_CODE_END = 5597   MAP_RESERVED_END = 6000  (14589 B)
```

★★ **§2T, P6.28f §3's caveat carried forward unchanged.** Siblings at **the same refs P6.28f §3
recorded**, read at their **`wip` working trees**, not a public ref (§2S). ★ **All three extra
checks matched; no stop condition fired.**

---

### 1 — Summary

§4A's decomposition ran and answered the question §4B asked. The saving exists, is structural, and
works. The fix then failed a gate nobody had modelled: **`res_open`'s return value for a LOGIC.**

### 2 — Files modified

**Committed:** `harness/tools/size_decompose.py` (`7b30e99`) — new.

**Applied, measured, and reverted:** the `res_core.s` decode call + fault guard; `p3b_probe.s`'s
`p3_zero_timers` removal; `run_gates.sh`'s `p3b_text` block; `gates.manifest`'s re-baseline;
`p3b_show.ps1`'s `-DecodeFault` notice update. **All re-appliable from §5.**

### 3 — Reasoning

**3.1 ★★★★★ §4A's decomposition — the cel configuration, `$2000-$5300`, 12,739 bytes emitted.**

| bytes | share | source |
|---:|---:|---|
| 1805 | 14.2% | `vm_cmds.s` |
| 1666 | 13.1% | `vm_run.s` |
| 1431 | 11.2% | `pic_fill.s` |
| 1022 | 8.0% | `res_core.s` |
| 748 | 5.9% | `p3b_probe.s` |
| 697 | 5.5% | `vm_objects.s` |
| 611 | 4.8% | `vm_cycle.s` |
| 599 | 4.7% | `vm_core.s` |
| 588 | 4.6% | `pic_core.s` |
| 546 | 4.3% | `composite.s` |
| 529 | 4.2% | `hal/coco3-dsk/gfx.s` |
| 525 | 4.1% | `vm_tables.s` |
| 518 | 4.1% | `view_cel.s` |
| 457 | 3.6% | `pic_draw.s` |
| 332 | 2.6% | `vm_tests.s` |
| 204 | 1.6% | `vm_state.s` |

★★★★★ **THE DECISIVE LINE IS NOT IN THE TABLE: the largest single emission anywhere in the region
is EIGHT BYTES.** ★★★ **There is no fill, no padding block, no fat table to reclaim** — unlike
AD-97's 927 bytes of table padding, this region is 12,739 bytes of ordinary code in ≤8-byte
increments. ★★ The 316-byte gap against the 13,055-byte span is `rmb` reservations, which advance
the location counter and emit nothing to the listing.

★ **The tool reads lwasm's LISTING, not the map**, because a map only permits *inferring* extents by
subtracting adjacent symbols — wrong wherever code and data interleave or a symbol is an `equ`.

**3.2 ★★★★ Candidate 1 (`CP_CEL` relocation) is DEAD, by §4B's own test.**

★ First, a correction: `CP_CEL_END` is **`$65B0`**, not `$6590` — 4,784 is `$12B0`.

**What occupies `$6000` onward is `MAP_ARENA_WIN`, and it is live at the moment the cel buffer is
written.** `p3_composite_all` does `res_open(VIEW)` — landing the VIEW in the arena at `$6000+` —
then `ldx res_base / stx vc_view`, `ldx #CP_CEL / stx vc_dest`, `jsr vc_decode_cel`. ★★★ **The
decode reads from the arena while writing into a buffer that overlaps it.** The overlap is latent
only because real cels are far smaller than the 4,784-byte corpus maximum; moving `CP_CEL` up moves
every write 16 bytes closer to the resource being read. **§4B: "if it is live, this candidate is
dead and says so."** It is live.

**3.3 ★★★★★ Candidate 2 delivered: `p3_zero_timers`, 14 bytes, verified dead.**

`p3b_probe.s`'s own header has said it since P3b.1 — *"P3_T_VM..P3_T_RENDER have existed since
P3b.1 and are ZEROED EVERY CYCLE AND NEVER WRITTEN — declared, cleared, dead."* ★★★★ **Verified
rather than believed**, because a comment is not a producer [AD-95]:

- **Guest:** the only reference to any `P3_T_*` is the `ldx #P3_T_VM` **inside the clear itself**.
- **Host:** `p3b_run.lua:43` defines all five addresses and **never reads one**.

★★★ **So it cleared 22 bytes nothing writes and nothing reads, every cycle. There is no observer, so
there is no behaviour to change** — §4B(ii) satisfied, and it is neither a hot-path shave (i) nor in
`src/hal/` (iii). ★★ The `P3_T_*` equs are **kept**: they document that `MAP_STATUS+8..+27` is
reserved and unused, which is worth more than the zero bytes deleting them would save.

**3.4 ★★★★★ The new blocker: `res_open`'s contract.**

```
res gate, fix applied:   959 / 1264 byte-identical (75.87%)   305 mismatches
res gate, reverted:     1264 / 1264 (100.00%)
```

★★★★ **The 305 are the LOGIC subset.** With `res_decode` on the miss path, `res_open` returns
**decoded** bytes for a LOGIC; the gate compares against `tools/volread/`'s **raw** resource, and
`volread/logic.py` decodes only when it *parses* a LOGIC object, not when it loads bytes.

★★★ **This is not a probe defect and not a double-decode.** `res_probe.s:127`'s explicit
`jsr res_decode` does compound it in mode 5, but the 305 are plain fetches: **the resource layer's
published contract — "callers ask for (type, index) and receive bytes" — has changed to "…and
LOGICs arrive decoded".** The res gate is the artifact that documents the old contract, and it has
been 1,264/1,264 since P1.3.

★★★★★ **Updating a primary gate's reference is not mine to do unilaterally.** If I decode the
reference and get it subtly wrong, the gate goes green for the wrong reason — the failure this
project fears most and has recorded repeatedly.

**3.5 ★★★ Three routes, named, none taken.**

| | cost |
|---|---|
| **(a) Decode the gate's LOGIC reference** to match the new contract | redefines a primary gate's expectations; smallest code change, largest evidential change |
| **(b) Decode in `vm_bind_logic` on a fresh open**, via a hit/miss flag `res_open` already knows | ★★★ **leaves `res_open`'s contract and the res gate untouched.** Costs a flag byte plus a test (~10-12 B) in `vm_run.s` — which `vm_probe.s` also links, so **its binary moves too**; the nine-title diff should not, since decoding messages touches no VM state |
| **(c) Accept the gate's new numbers** and re-baseline it | the gate stops being a raw-bytes check |

★★ **(b) is the one I would ask about first**, because it is the only one that leaves the resource
layer's contract — and its 1,264/1,264 — exactly where they are. ★ It is **not** the ruling's
placement, so it is a ruling, not a workaround.

**3.6 ★★ §2H's three checks.**

1. **A second mechanism for another object class?** ★★★ Yes, and it is §3.4: **`res_open` serves
   two consumers with different needs** — the VM, which wants text, and the resource gate, which
   wants Sierra's bytes. One return value cannot satisfy both.
2. **The calling routine.** `res_decode`'s new caller is `res_open`'s LOGIC miss branch, whose
   callers include **`res_probe.s`, not only the VM** — that is the fact the ruling's placement did
   not account for.
3. **Grep the reports.** P6.28c measured the 1 byte; P6.28d found the missing call; P6.28e priced
   it; P6.28f showed a gate row cannot fix source; **this task clears the bytes and finds the
   contract.** ★★ Five reports, and each one moved the constraint rather than removing it.

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it.**

- **AC-1 [byte-comparable · assembler]** ★★★ **MET while applied.** cel **13,914 B
  `D5710109DBC12384…`**, `P3_CODE_END $52F4` vs `CP_CEL $5300` — **12 bytes spare**. text
  **14,578 B `08A998829F56F6DC…`**, `P3_CODE_END $558C`. **Both assemble.** Reverted; not shipped.
- **AC-2 [state-comparable · call graph]** ★★★ **MET.** With the fix: `res_core.s:262` (miss path),
  `res_core.s:383` (behind `ifdef RES_FAULT_DECODE_HIT`), `res_probe.s:127` — **three source lines,
  two active**, exactly the dispatch's correction to P6.28f's AC-5. ★★ A fourth grep hit was **my
  own comment text**; the check now excludes comment lines, which is §2N's lesson in miniature.
- **AC-3 [state-comparable · fault injection]** ★★★★ **MET, re-shown on the new build** [L-62]:
  clean **16 of 16 printable — DECODED**; fault (`-DRES_FAULT_DECODE_HIT`) **18 of 32 — NOT
  DECODED**. Counted **to the terminator**, per the dispatch. ★ Cost signal: 22.36 s vs 36.38 s
  emulated for 120 cycles.
- **AC-4 [suite]** ★★★★★ **NOT MET — the `res` gate failed.** `959/1264 (75.87%)`, ten volumes
  listed with mismatches. `p3b_text` ran green (120 cycles, no stall) and so did `p3b`, `pic`,
  `cel`, `comp`. **After the revert: all green, res 1,264/1,264.**
- **AC-5 [byte-comparable]** ★★ **NOT SHIPPED.** The re-baseline was written — retired
  `F51FF848…` 13,925 B, current `D5710109…` 13,914 B, with the retirement line §4D asked for — and
  reverted with the fix. Text in §5.
- **AC-6 [eye gate — Jay]** ★★★ **NOT RUN.** ★★ The wired arm's build is not in the tree, so a run
  would gate a binary the repo cannot produce. **AC-1 and AC-2 remain passed from P6.28e/f in Jay's
  words; nothing about the panel is in doubt.**
- **AC-7 [tooling]** ★★ **PASSED.** `hal_sync_check.py` OK ×3; `reg_discipline.py` 8 in
  `mmu_phase.s`; `gen_vm_tables.py --check` **CHECK OK**.
- **AC-8** One candidate; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §3's grep is above; §3.1 carries the decomposition table.

```
=== the saving, verified dead before removal ===
host reads of P3_T_*:   p3b_run.lua:43 (definition only; no read anywhere)
guest refs to P3_T_*:   p3b_probe.s -- the equs, and `ldx #P3_T_VM` inside the clear itself

=== with fix + saving applied ===
cel   13914 B  D5710109DBC123848C8EEF157014B6A752F8E221A267BA5EBF8CB3DD96454322
      P3_CODE_END = 52F4   CP_CEL = 5300      -> 12 bytes spare
text  14578 B  08A998829F56F6DC6F5C9BDD8C2190D6FEE1347AE38917A9815D49D2773B1F54
      P3_CODE_END = 558C

=== AC-3, re-shown on that build ===
CLEAN  120 cycles in 22.3621 emulated s   P3_PBUF $1C00: 16 of 16 printable -- DECODED
FAULT  120 cycles in 36.3802 emulated s   P3_PBUF $1C00: 18 of 32 printable -- NOT DECODED

=== AC-4, the failure ===
resources byte-identical to tools/volread/: 959 / 1264 requested (75.87%)
★★★ volumes with mismatches or guest failures: Kingquest1-v0 Kingquest1-v1 Kingquest1-v2
    Kingquest2-v0 Kingquest2-v1 Kingquest2-v2 Kingquest3-v0 Kingquest3-v1 Kingquest3-v2
    Kingquest3-v3
★★★ GATES FAILED: res
   (p3b_text ran green in the same suite: 120 cycles, no stall)

=== after the revert ===
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
p3b  13925 B  F51FF8482D0B07E49F46B18612D20B06
```

**The re-baseline text written for §4D** (reverted with the fix):

```
#     retired:  F51FF8482D0B07E49F46B18612D20B06  13,925 B   (valid to P6.28f)
#     current:  D5710109DBC12384                  13,914 B
# A reader who meets F51FF848 in P6.28b-f is looking at a RETIRED baseline, not a broken build.
```

**25.2 bundled-artifact grep:** N/A.

**25.3 operator-runtime-smoke:** ★★★ **N/A this task — and NOT "pending Jay".** AC-1 and AC-2 are
passed and confirmed in Jay's words (P6.28e/f); AC-6 asked for one more wired run, and running it
against a build that is not in the tree would record a pass for a binary nobody can produce.

### 6 — Reactive deviations and route accounting

**Deviation 1 — `size_decompose.py` is new and committed.** §4A asked for a decomposition; the
project had no tool for one. ★ Committed separately because it is independent of everything held.

**Deviation 2 — the call-site check now excludes comment lines.** The first run reported four sites;
the fourth was my own prose. **§2N's lesson, produced by me, in the task that quotes it.**

**ROUTE ACCOUNTING.** ★★★★ **§4A complete** (decomposition, reported in full whether or not it
produced the saving — it did). **§4B complete**: candidate 1 measured dead, candidate 2 delivered 14
bytes. **§4C attempted and reverted.** **§4D written and reverted.** ★★★★★ **Nothing conditioned on
the fix has shipped: no design-spec edit, no `run_gates.sh` block, no re-baseline** — all three
would assert a state the tree does not have.

★★★ **I did not update the res gate's reference**, which would have made everything green in about
two lines. §3.4 gives the reason: a primary gate whose expectations I redefine to match my own
change can only tell me what I already believe.

### 7 — Uncertainty flags

1. ★★★★★ **The contract question is the whole of what remains** (§3.4/§3.5). The bytes are solved.
2. ★★★ **Route (b) is unmeasured.** `res_open` already distinguishes hit from miss, so the flag is
   cheap, but I have not built it and **it moves `vm_probe.s`'s binary**; whether the nine-title
   diff holds is predicted, not shown.
3. ★★★ **`res_probe.s:127`'s explicit decode compounds the failure in mode 5** and is a second,
   smaller question inside the first: if route (a) is taken, that call becomes a double decode and
   must go.
4. ★★ **`res_err` masking** (P6.28e §7.4), **`$FFA4`** [AD-182], **`print`'s key-wait** [AD-183] —
   untouched, per §10.
5. ★ **The 12-byte margin is measured with `p3_zero_timers` gone and nothing else.** The cel
   configuration remains the tightest thing in the tree.

### 8 — Follow-up candidates

- ★★★★★ **The ruling on §3.5's three routes.** Everything else this task touched is done.
- ★★★ **Re-apply from §5** — the diff is verbatim and both builds are hashed.
- ★★ **`res_probe.s:127`** (§7.3) travels with route (a).
- ★★ **Run `size_decompose.py` on the text configuration too**, which nobody has decomposed either.

### 9 — User interaction during task

**None.** Jay's AC-1/AC-2 confirmations are carried from P6.28e/f and were not re-solicited.

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-10-a-fix-that-changes-what-a-function-returns-changes-every-gate-that-reads-it`
  — *initiator: executor*. The decode was placed where the ruling said and did exactly what it
  should; the cost was that a shared accessor's return value now differs for one resource type, and
  the gate documenting the old contract fell from 100% to 75.87%. **The blocker moved from bytes to
  meaning, and only landing it could have shown that.**

### 11 — Commit

`7b30e99` — `size_decompose.py`, pushed to origin/wip before this report. ★★ **No fix commit**: held
at §3.4.
