## Form B Report — P6.29b (T-P0-085b) — the `getstring` analogy does not transfer; the oracle's shape does
**Class:** integration (§4A) — **stopped at §4A's design step, before implementation.**  wip.

★★★★★ **§4A's answer contradicts §1.2's shape ruling, so it goes back rather than being worked
around.** The `getstring` split cannot carry a VM opcode, and the shape §1.2 ruled *"not available"*
— the oracle's own blocking loop — **is available, is cheaper, and satisfies §1.3's invariant by
construction rather than by care.**

★★★★ **The invariant is the argument.** §1.3 requires that a suspended `print` not move a cycle
boundary. ★★★★★ **A design that never unwinds cannot move one.** Nothing to preserve, nothing to
restore, nothing to re-enter.

★★★ **And §1.2's premise came from T-P0-085 — mine.** I wrote that the port *"has no inner-loop
re-entry"*, which is true of the **reference's event pump** and false of **the 6809's ability to
spin**. The ruling inherited a conflation I introduced.

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-085b dispatch receipt (HEAD `232ce06`, wip). **No source file was modified.**

---

### §3 — Pre-dispatch grep (C-13), verbatim — all five matched

```
=== coco_agi === 232ce06 wip   ?? agi-coco3-design-v1_3.md   ?? coco_agi.code-workspace
=== POP3_port === 104b197      === karateka_coco3 === 29f8f0a
[hal-sync] OK x3 (11 files compared)
[reg-discipline] 8 in src/engine/mmu_phase.s -- $FFA5 $FFA6
CHECK OK: src/harness/vm_tables.s matches optable.py.

(1) res gate  -- FRESH RUN:  1264 / 1264 requested (100.00%)
(2) vm gate   -- FRESH RUN:  9/9 PASS (Kingquest1/2/3, SpaceQuest-1/2, PoliceQuest1,
                             larry1, BlackCauldron, MixedUpMotherGoose)
    vm_probe.bin   9667 B  771F147DE2A54688ABFA8823784323DB
(3) p3b       13918 B  58AD3C27164BD63FDE17E18041160B28
(4) p3b_text  14582 B  FA7F2FB9CD542B58ED3D4E75D365C43E
(5) spare     P3_CODE_END=$52F8  CP_CEL=$5300  SPARE = 8 bytes
```

★★ **(1) and (2) are measurements, not citations**, as §3 required of a task that modifies the VM.
★ **§2S:** siblings read at their `wip` working trees, not a public ref; same refs as P6.28h §3.

---

### 1 — Summary

The design was settled on paper, as §4A directs, and it does not match the shape §1.2 ruled. No code
was written.

### 2 — Files modified

**None.** This report only.

### 3 — Reasoning — §4A, settled on paper

**3.1 ★★★★★ The `getstring` split cannot carry a VM opcode. Three reasons, each checkable.**

**(i) `get.string` has never run as a VM opcode.**

```
src/harness/vm_tables.s:   fdb  vm_op_unimpl   ; 73 get.string(nsnnn)
```

★★★ **It is `vm_op_unimpl`.** The split's only callers are probes:

```
gs_probe.s:126,135,142     jsr gs_get_string / gs_keypress / gs_finish
input_probe.s:195,233,246  jsr gs_get_string / gs_keypress / gs_finish
```

★★★★ **In both, the PROBE'S OWN MAIN LOOP owns the wait** — that is precisely what P6.21 §3 says the
split was for: *"lets the caller own that loop, so a probe can drive it from a key list."* **It is
not a suspend across an opcode dispatch, and it has never been asked to be one.**

**(ii) There is no continuation mechanism.** `print` is reached as
`vm_interpret_cycle` → the logic loop → `jsr ,x` [vm_core.s] → `vmop_print`. ★★★ **To suspend there
and resume later, the 6809 return stack between those frames would have to be unwound and restored.
Nothing in the port does that**, and building it is a far larger change than the feature.

**(iii) ★★★★★ Re-entry is worse than §1.3 says, and the extra hazard is recorded in the file.**
§1.3 names the cycle counter. `vm_interpret_cycle` does **three** things before any logic runs:

```
vm_cycle.s:175      jsr     res_cache_flush
vm_cycle.s:176-178  ldd vm_cycle / addd #1 / std vm_cycle
vm_cycle.s:180+     start-of-cycle work (ego direction, motions, ...)
```

★★★★★ **The flush is the dangerous one.** Its own comment: *"res_depth is 0 at the top of a cycle,
so nothing is executing out of the arena and res_top can move. Doing it inside new.room — which runs
INSIDE a logic — overwrote the running logic and halted all nine titles at cycle 0."* ★★★ **Mid-print,
`res_depth` is NOT 0.** A resume that re-entered `vm_interpret_cycle` would flush the cache under a
logic that is still executing — **the exact defect that file records having already cost nine
titles.**

**3.2 ★★★★★ The oracle's shape IS available, and §1.2's premise was mine and was wrong.**

§1.2 says the oracle's shape *"is not available"*, citing T-P0-085. ★★★★ **What T-P0-085 §7.1
actually established is that the port has no re-entry into the REFERENCE'S EVENT PUMP.** That is a
statement about `processAGIEvents()` and `cycleInnerLoopActive()` — **not about whether a 6809 can
sit in a loop polling the key matrix.** It can; `input_probe.s`'s poll loop has done it since P6.24
and is gated 10/10.

★★★ **I introduced that conflation and it propagated into a ruling.** Correcting it is the substance
of this report.

**3.3 ★★★★ The proposed shape, and why the invariant is structural rather than careful.**

> **`vmop_print` draws the box and then BLOCKS IN PLACE**, polling `HAL_key_scan` for ENTER/ESC and
> ticking var 21, exactly where the oracle blocks — inside the opcode, inside the cycle.

| §1.3 requirement | how it is met |
|---|---|
| must not increment the cycle counter | **nothing returns to `vm_interpret_cycle`** — the counter is not reached |
| must not re-dump | the host samples at the GO gate, which is not re-entered |
| must not re-run start-of-cycle work | never left it |
| resource stack intact | `res_depth`/`res_marks` untouched — **no flush under a running logic** |

★★★★★ **§4B's enumeration becomes empty, and that is the strongest argument for the shape.** The
dispatch asks what state must survive the suspend — `vm_ip`, the current logic, the nested-call
context [vm_run.s:105], the restore rectangle, the cursor. ★★★ **Under a blocking wait, NONE of it
has to survive anything: it is all still live in registers, on the stack, and in the arena, because
the frame was never left.** ★★ The nested-`print`-inside-a-called-logic case that §4B warns would
find the defect **cannot arise**, because there is no saved context to get wrong.

**3.4 ★★★ It costs the cel configuration nothing, and the text configuration can afford it.**

★★★★ **This is NOT §6's "fits only in the text configuration" trigger**, and the distinction is
structural: `vmop_print`'s real body exists **only** under `TEXT_WIRED`; in the cel configuration the
label is `equ vm_op_modelled` and emits **zero bytes** [AD-176's mechanism, P6.28d]. **The 8-byte
budget is untouched because the text opcodes do not exist there at all.** L-114's shape was a fix
needed everywhere that fitted in one place; this is a feature that belongs only where the text
engine is.

**Measured headroom in the configuration that carries it:**

```
p3b_text:  P3_CODE_END = $5590   P3_FONT = $5800   headroom = 624 bytes
```

★★★ **But p3b links NO key input in either configuration today** — no `input.s`, no
`-DHAL_KEYBOARD`, no reference to `HAL_key_scan` anywhere in `p3b_probe.s`. The decoder is ~318 B
[P6.24] behind `ifdef HAL_KEYBOARD` in `hal_globals.s`. ★★ **318 into 624 fits with the wait's own
code**, but it is a **flag-set change to a gate row** and would be recorded in `gates.manifest`.

**3.5 ★★ What the shape does NOT settle, and would still be transcription work.**

Flag 15's short-circuit above the wait; var 21's tick and its zeroing on exit; ESC's
`_messageBoxCancelled`; and **the derived timebase** — *1 = 0.5 seconds* is the data-format fact and
ScummVM's `* 20` is its 40 fps correction, not ours [§2.1]. ★ **None of these depends on the shape**,
so none is lost by stopping here.

**3.6 ★★ Authority.** §3.1(i) and (iii) are **facts about our tree**, verified by reading it.
§3.2's correction is about **my own prior report**, tier-3, now withdrawn. The oracle's blocking
structure is **§2 tier 3**, quoted at T-P0-085 §3.1 and unchanged.

### 4 — Verification (AC-by-AC)

- **AC-1 [state-comparable · gate]** ★★★ **MET as a baseline: `vm` 9/9, fresh run.** Not as a result
  — nothing was changed to disturb it.
- **AC-2 [byte-comparable · gate]** ★★★ **MET as a baseline: `res` 1,264/1,264, fresh run.**
- **AC-3 [design]** ★★★★★ **MET, and it is the deliverable.** §3.1–3.4 is the re-entry design; §3.3's
  table is §4A's answer; §4B's enumeration is **answered as empty, with the reason.**
- **AC-4 … AC-7, AC-9, AC-10** **NOT REACHED** — no implementation.
- **AC-8 [byte-comparable · assembler]** ★★ **MET as a baseline.** `p3b` 13,918 B `58AD3C27…`;
  `p3b_text` 14,582 B `FA7F2FB9…`; **spare against `CP_CEL` = 8 bytes**; text-configuration headroom
  **624 bytes**.
- **AC-11 [tooling]** ★★ **MET.** `hal_sync_check.py` OK ×3; `reg_discipline.py` 8 in
  `mmu_phase.s`; `gen_vm_tables.py --check` **CHECK OK**.
- **AC-12** One candidate; §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1** — §3's grep above; §3.1's three citations are from this tree:

```
vm_tables.s:      fdb vm_op_unimpl   ; 73 get.string(nsnnn)
gs_probe.s:126,135,142   input_probe.s:195,233,246   -- the only gs_* callers
vm_cycle.s:175-178   res_cache_flush ; then vm_cycle += 1
vm_cycle.s:171-174   "res_depth is 0 at the top of a cycle ... Doing it inside new.room --
                      which runs INSIDE a logic -- overwrote the running logic and halted
                      all nine titles at cycle 0."
p3b_probe.s:      no HAL_KEYBOARD, no input.s, no HAL_key_scan
p3b_text:         P3_CODE_END $5590  P3_FONT $5800  -> 624 bytes
```

**25.2** N/A — nothing built. **25.3** ★★ **N/A, and not "pending Jay"** — the task stopped before
anything could reach a screen. **AC-10's corrected wording (ENTER or ESC) stands ready.**

### 6 — Reactive deviations and route accounting

**ROUTE ACCOUNTING.** ★★★★ **§4A complete; §4B answered; §4C, §4D, §4E not started.** ★★★★★ **I did
not implement the blocking shape even though §4A's stop condition — "if it needs a change to
`vm_cycle.s`'s definition of a cycle" — does NOT fire.** By the letter I could have proceeded.
★★★ **§1.2 is a JAY ruling on shape, and my analysis contradicts it on a premise I supplied.
Building a different shape than the one ruled, without asking, would substitute my judgement for
his on the one point he decided.** §8: stop and surface rather than proceed on assumption.

★★ **Nothing was half-built to have something to show.** The transcription work in §3.5 is
shape-independent and survives either ruling.

### 7 — Uncertainty flags

1. ★★★★ **The blocking shape hands the harness a new obligation.** `p3b_probe.s`'s loop is
   wait-GO / run-cycle / set-DONE; a blocking `print` does not return to it, so **the host watchdog
   fires unless something dismisses the box.** ★★★ Headless, that is var 21 — which is why §4E's
   var-21 path is not a convenience but the thing that keeps `p3b_text` meaningful.
2. ★★★ **`-DHAL_KEYBOARD` in `p3b_text` is a flag-set change to a gate row**, and this project has
   AD-96 recorded about exactly that. It is affordable (318 into 624) and it **re-baselines
   `p3b_text`'s binary**; the `p3b` row is untouched.
3. ★★ **ESC's cancel has no consumer in our port.** `messageBox` returns false and the caller acts;
   ours has no such caller yet [T-P0-085 §7.3 asked this be stated rather than invented].
4. ★★ **Var 21's conversion is underived** (§3.5) and is shape-independent.
5. ★ **`agi-coco3-design-v1_3.md` is still untracked at the repo root.** Not read, not moved, not
   committed [§2D].

### 8 — Follow-up candidates

- ★★★★★ **Jay's ruling on shape, with §3.1–3.3 in hand**: blocking-in-place (the oracle's), or the
  suspend/resume split (which needs a continuation the port does not have).
- ★★★ **If blocking is ruled:** flag 15 above the wait, var 21 ticking it, ENTER/ESC via
  `-DHAL_KEYBOARD` in `p3b_text` only, harness writes var 21 headless [AD-99's technique].
- ★★ **Derive var 21's timebase** (§3.5) — needed either way.

### 9 — User interaction during task

**None.**

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-10-a-negative-finding-can-propagate-into-a-ruling-as-a-premise`
  — *initiator: executor*. I reported that the port *"has no inner-loop re-entry"* — true of the
  reference's event pump, false of the CPU's ability to loop. **The next dispatch adopted it as a
  premise and ruled a harder design on the strength of it.** A finding stated about one mechanism
  and read as being about a capability is how a correct observation becomes a wrong constraint.

### 11 — Commit

**No source commit** — the tree is byte-identical to `232ce06`. This report only.
