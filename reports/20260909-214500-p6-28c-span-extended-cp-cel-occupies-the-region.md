## Form B Report — P6.28c (T-P0-084c) — span extended; `CP_CEL` occupies the region it grants
**Class:** integration (§4A) — **stopped at trigger 1, before wiring.**  wip.

★★★★★ **Ruling 2 is implemented and it grants no usable bytes.** `p3b_probe.s` now asserts against
`MAP_RESERVED_END` (`$6000`) — but **`CP_CEL equ MAP_RESERVED` puts the 4,784-byte decoded-cel
staging buffer at `$5300`, which is exactly the old `MAP_CODE_END`.** The spare against the thing
that is actually there is **1 byte, unchanged.**

★★★★ **Measured, not predicted.** With `text.s` and the nine handler stubs linked, `P3_CODE_END`
reaches **`$5922`** — comfortably inside the span (1,758 B spare) and **1,570 bytes inside the cel
buffer.**

★★★ **The extension is committed with a second assertion that makes the collision fail the build**,
so the constraint is permanent and machine-checked rather than a sentence in a report.

★★★★★ **`p3b_probe.bin` is byte-identical: `F51FF8482D0B07E49F46B18612D20B06`, 13,925 B.** An
assertion emits no bytes, so **the extension alone does not re-baseline the gate** — ruling 2's
stated consequence becomes true only when wiring adds code. **AC-3's re-baseline did not happen and
could not have.**

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-084c dispatch receipt (HEAD `8b269ca`, wip; descends from `7e96072` as expected).
At report time HEAD `469921e`. `git status` clean but for `coco_agi.code-workspace` (untracked).

---

### §3 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===        8b269ca  wip   ?? coco_agi.code-workspace
=== POP3_port ===       104b197  wip   (no tracked modification)
=== karateka_coco3 ===  29f8f0a  wip    M harness/smoke/last-run.log

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6

=== p3b_probe.bin PRE-EXTENSION (the baseline being replaced) ===
13925 B  F51FF8482D0B07E49F46B18612D20B06

=== gen_vm_tables.py --check ===
CHECK OK: src/harness/vm_tables.s matches optable.py.
```

★★ **§2T citation, P6.28b §3's caveat carried forward unchanged.** Both siblings are at **the same
refs P6.28b §3 recorded**, read at their **`wip` working trees**, not a public ref (§2S). Neither has
a tracked source modification; Karateka's one tracked change is a run log. ★ No sibling artifact is
built or claimed.

**The nine entries, verbatim [L-77]:**

```
239: fdb     vm_op_modelled          ; 65 print(s)  [modelled]
240: fdb     vm_op_modelled          ; 66 print.v(v)  [modelled]
241: fdb     vm_op_modelled          ; 67 display(nns)  [modelled]
242: fdb     vm_op_modelled          ; 68 display.v(vvv)  [modelled]
243: fdb     vm_op_modelled          ; 69 clear.lines(nns)  [modelled]
246: fdb     vm_op_modelled          ; 6C set.cursor.char(s)  [modelled]
247: fdb     vm_op_modelled          ; 6D set.text.attribute(nn)  [modelled]
250: fdb     vm_op_modelled          ; 70 status.line.on()  [modelled]
251: fdb     vm_op_modelled          ; 71 status.line.off()  [modelled]
```

★ All nine still read `vm_op_modelled`. **No contradiction in the grep; proceeded to §4A.**

---

### 1 — Summary

§4A was carried out: the span assertion moved from `MAP_CODE_END` to `MAP_RESERVED_END`. ★★★★★ **The
region it opens is already occupied by this probe's own cel buffer**, which starts at the byte the
old boundary ended on. **The extension is real, correct, and worth nothing to the wiring.**

★★★★ **The conflict is with ruling 2's precondition, not with ruling 2.** P6.28 §5A measured
`MAP_RESERVED` as free **for `text_vm_probe.s`, which drops `view_cel.s` and `composite.s`** — my own
report scoped it that way explicitly. §2 of this dispatch keeps both linked in `p3b_probe.s`, and
`CP_CEL` is the buffer `composite.s` decodes into. **Dropping cel is what made the region free, and
this probe does not drop it.**

★★★ **What was delivered:** the span extension plus a `CP_CEL` collision assertion that fails the
build — verified firing — so the next attempt cannot rediscover this by symptom. **The gate is green
and the baseline hash is untouched.**

### 2 — Files modified

- `src/harness/p3b_probe.s` — span assertion `MAP_CODE_END` → `MAP_RESERVED_END`; **new** `CP_CEL`
  collision assertion. **+23 / −2 lines, zero bytes of emitted code.**

★★ Created and deleted during the measurement: `src/harness/vm_text_ops.s` (nine handlers with a
`-DTEXT_MODELLED` toggle) and two `include` lines in `p3b_probe.s`. ★★★ **Removed deliberately** —
`vm_text_ops.s` defines labels under `src/harness/vm_*.s`, which `gen_vm_tables.py` scans globally
[AD-176], so leaving it would bind the shared table and **fail the drift check**. It is re-creatable
from §5 verbatim.

### 3 — Reasoning

**3.1 ★★★★★ Why the span buys nothing: three addresses.**

```
Symbol: MAP_CODE_END      = 5300
Symbol: CP_CEL            = 5300      ★ the same address
Symbol: MAP_RESERVED_END  = 6000
Symbol: P3_CODE_END       = 52FF      (pre-wiring)
```

`CP_CEL equ MAP_RESERVED` [`p3b_probe.s:174`]. **The reservation's first byte is the cel buffer's
first byte.** So "code may now reach `$6000`" and "code may now reach `$5300`" describe the same
usable space, and the pre-existing 1 byte of headroom is still 1 byte.

**3.2 ★★★★★ The collision is silent, and worse than silent.**

★★★★ **Room 83 stages ZERO sprites** — `p3b_run.lua`'s own line, and the reason §2 of this dispatch
could contemplate dropping cel at all. So nothing decodes a cel, **the p3b gate's 160 cycles would
pass with the buffer already overwritten by code**, and the eye gate at room 83 would look correct.
Room 1 has four sprites; the first decode writes cel pixels over executing code.

★★★★★ **This probe has been here before.** `p3b_probe.s:980` records the *previous* `CP_CEL`
collision — the parser's `par_vocab` shared CP_CEL's first byte, room 83 ran 160 clean cycles, and
**the eye gate found it a room away from its cause.** ★★★ Repeating that shape with the same buffer
is what the new assertion exists to prevent [L-86: a fixed sample that always passes is evidence
about the sample first].

**3.3 ★★★★ The guard was shown to fire, in both directions.**

Default build, with `text.s` and the nine stubs linked:

```
ERROR : User Specified: "P3b code has grown into the decoded-cel buffer at CP_CEL ($5300, 4,784 B)..."
```

With `-DP3B_ACCEPT_OVERRUN` (the existing escape that exists so a size can be *read* when a guard
refuses to emit a map):

```
Symbol: P3_CODE_END = 5922    Symbol: CP_CEL = 5300    Symbol: CP_CEL_END = 65B0
```

★★★ And with the includes removed it does **not** fire and the hash returns to `F51FF848…`. ★★ **Red
on the failing case, green on the passing one** — §2W's requirement, tested in both directions
because a guard tested only against the case it was meant to allow is P6.3's defect exactly.

**3.4 ★★★ Why I did not move `CP_CEL` myself.**

The obvious repair is to move the cel buffer above the new code end. ★★★★ **It is a layout ruling,
not a task-level fix, and the region it would move into is already contested:** `CP_CEL_END = $65B0`
**already overruns `MAP_RESERVED_END` into the arena window**, which `p3b_probe.s`'s own §8-trigger
block reports rather than patches. Moving it further in deepens a known, unresolved overlap.

★★ I checked the alternatives before concluding: **`$E000-$FF00` cannot host `text.s`** — parser
(954 B) plus the vocabulary window leaves 154 B against 1,562 — and **`MAP_INPUT` (`$1C00`, 1,024 B)
cannot host `CP_CEL`** at 4,784 B. **There is no free 1,562 B in this probe's map without moving
something substantial**, and §7 trigger 1 says report the numbers rather than propose a layout.

**3.5 ★★ The `-DTEXT_MODELLED` toggle exists and works** (trigger 6's requirement), and is recorded
in §5 rather than committed. ★★★ Under the flag each label is `equ vm_op_modelled` — **the same
address the pre-wiring build used, not a similar no-op** — so AC-2's fault arm would be the
pre-wiring behaviour rather than a reconstruction of it. ★ It needs one table, not two; route (b)
stays withdrawn.

**3.6 ★★ §2H's three checks.**

1. **A second mechanism for another object class?** ★★★ Yes: `MAP_RESERVED` has **two consumers with
   different claims** — the *engine's* (parser + sound, per `memmap.inc`) and the *probe's*
   (`CP_CEL`). A reading of `memmap.inc` alone says the region is a reservation; the probe's own
   `equ` says it is occupied. **The map and the probe disagree, and the probe wins at assembly.**
2. **The calling routine.** `CP_CEL`'s consumer is `composite.s`'s cel decode, reached only when
   sprites stage — **so the enclosing fact is "how many sprites does this room have", which is zero
   for the gate's terminal room.** That is precisely why the collision does not show up in the gate.
3. **Grep the reports for the same subsystem.** P6.28 §5A is the source of ruling 2 and **scoped its
   claim to a probe that drops cel**; P6.28b established the generator coupling that forced the move
   to `p3b_probe.s`. ★★★ **The two findings compose into this one**: the coupling requires one probe,
   and the one probe is the one where the region is not free.

**3.7 ★★ Authority tier.** No ScummVM or Specs claim. Every figure is `lwasm` output on this tree at
this HEAD.

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it.**

- **AC-1 [eye gate — Jay]** ★★★★★ **NOT ATTEMPTED.** No wiring, so nothing to gate. **Jay has seen
  nothing and no eye-gate claim is made.**
- **AC-2 [eye gate — Jay]** ★★★★ **NOT ATTEMPTED.** The `-DTEXT_MODELLED` mechanism is designed and
  demonstrated (§3.5) but not committed. ★★ Running a fault arm whose wired counterpart does not
  exist shows Jay a black screen with nothing to compare against — **a validator with nothing to
  validate is not evidence.**
- **AC-3 [byte-comparable · observed by: SHA-256]** ★★★★ **NOT MET, AND IT COULD NOT BE.** The
  re-baseline was to come from the post-extension, pre-wiring build. That build is
  **`F51FF8482D0B07E49F46B18612D20B06`, 13,925 B — identical to the pre-extension hash**, because an
  assertion emits no bytes. ★★★ **There is no new baseline to record; the old one still stands.**
  `git diff --stat HEAD -- src/hal/ src/engine/` is **empty**.
- **AC-4 [state-comparable]** ★★ **HALF-MET.** The "before" column is §3's nine entries, all
  `vm_op_modelled`. **No "after" column: `vm_tables.s` was not regenerated** and all nine still read
  `vm_op_modelled` in the tree.
- **AC-5 [byte-comparable · assembler]** ★★★ **MET, and it is the finding.** New span:
  `P3_CODE_END = $52FF` against `MAP_RESERVED_END = $6000`. **Spare against the span 1,793 B; spare
  against `CP_CEL` ($5300) 1 byte.** Both assertions are live and the second was seen to fire.
- **AC-6 [byte-comparable]** **NOT REACHED.** `-DTEXT_MODELLED` is designed, not committed, so there
  is no second hash to state.
- **AC-7 [suite · observed by: byte gates]** ★★ **PASSED.** `★ gates run: pic res cel comp p3b --
  all green`; `hal_sync_check.py` OK ×3; `reg_discipline.py` 8 in `mmu_phase.s`, unchanged;
  `gen_vm_tables.py --check` **CHECK OK**.
- **AC-8 [byte-comparable · runner]** **NOT APPLICABLE.** No gate run beyond the suite.
- **AC-9** One candidate; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §3's grep is above.

```
=== §4A: extended span, pre-wiring ===
13925 B  F51FF8482D0B07E49F46B18612D20B06        ★ IDENTICAL to pre-extension
Symbol: CP_CEL            = 5300
Symbol: MAP_CODE_END      = 5300
Symbol: MAP_RESERVED_END  = 6000
Symbol: P3_CODE_END       = 52FF

=== with src/engine/text.s + the nine handler stubs linked, default build ===
src/harness/p3b_probe.s(947) : ERROR : User Specified: "P3b code has grown into the
  decoded-cel buffer at CP_CEL ($5300, 4,784 B) -- the span reaches MAP_RESERVED_END
  but CP_CEL is already there; move CP_CEL or shrink the code, do not let them overlap"

=== the same, with -DP3B_ACCEPT_OVERRUN, to read the size ===
Symbol: P3_CODE_END = 5922    ★ 1,570 B into the cel buffer; 1,758 B spare in the span
Symbol: CP_CEL      = 5300
Symbol: CP_CEL_END  = 65B0    ★ already past MAP_RESERVED_END, pre-existing

=== includes removed ===
13925 B  F51FF8482D0B07E49F46B18612D20B06        ★ guard green on the passing case
CHECK OK: src/harness/vm_tables.s matches optable.py.
```

The `-DTEXT_MODELLED` toggle, verbatim, for the next attempt (not committed — see §2):

```
                ifdef   TEXT_MODELLED
vmop_print              equ     vm_op_modelled
vmop_print_f            equ     vm_op_modelled
vmop_display            equ     vm_op_modelled
vmop_display_f          equ     vm_op_modelled
vmop_clear_lines        equ     vm_op_modelled
vmop_set_cursor_char    equ     vm_op_modelled
vmop_set_text_attribute equ     vm_op_modelled
vmop_status_line_on     equ     vm_op_modelled
vmop_status_line_off    equ     vm_op_modelled
                else
                ... real handlers ...
                endc
```

Suite:

```
★ gates run: pic res cel comp p3b  -- all green
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact.

**25.3 operator-runtime-smoke:** ★★★★ **N/A — and explicitly NOT "pending Jay".** Nothing was wired,
so nothing could reach a screen. §4A's rule that an integration task is not reportable until Jay has
seen it **applies to a task that reaches the gate**; this stopped at §4B's first measurement.

### 6 — Reactive deviations and route accounting

**Deviation 1 — a second assertion was added, beyond ruling 2's one-line change.** ★★★ The ruling
asked for the span; the span alone would have let code walk into the cel buffer with **no diagnostic
and a green gate** (§3.2). ★★ Adding the guard is the difference between implementing a ruling and
implementing it safely, and it emits no bytes.

**Deviation 2 — `vm_text_ops.s` and two `include` lines were created and removed.** They existed to
measure the overrun rather than argue it (§3.3). ★★ Removed because the file would bind the shared
table and break the drift check [AD-176].

**ROUTE ACCOUNTING.** ★★★ The dispatch's scope was **A** (extend, re-baseline), **B** (wire both
legs), **C** (eye-gate), with a three-commit sequence. ★★★★ **This report contains A only, and A
returned a null result: the span extended and the baseline did not move.** ★★★★★ **Commit 2 was not
made — no opcode was wired, `vm_tables.s` was not regenerated, `cycle.py` was not touched, and
`memmap.inc` was not touched.** §10's design-spec edit is not made; it is conditioned on an eye gate
that did not run.

★★ **I did not move `CP_CEL`.** Trigger 1 says report the numbers; §3.4 gives them and the two
alternatives I ruled out with measurements.

### 7 — Uncertainty flags

1. ★★★★ **`P3_CODE_END = $5922` is measured with STUB handlers** — nine bare `rts`. **Real `print`
   and `display` implementations will push it further**, and the flat-window setup of ruling 3 is not
   in that figure at all. **The overrun is a floor, not the number.**
2. ★★★ **Whether `CP_CEL` can move at all is unestablished.** §3.4 rules out two homes by
   measurement; it does not enumerate the map exhaustively, and `CP_CEL_END` already overruns into
   the arena window, so **every candidate home is inside a region this probe already over-subscribes.**
3. ★★★ **Ruling 3's flat 24 KB window (slots 4–6) was not exercised.** Slot 4 is the arena window's
   high half; borrowing it during a blit is the same argument `p3_present` makes for slot 5, **but
   the arena holds the LOGIC the VM is executing** and that is a longer borrow than `p3_present`'s.
   **Untested and not a given, despite being ruled.**
4. ★★ **`PRI_PACKED` was not evaluated** (§2 asked). The framebuffer window question it depends on
   is downstream of a wiring step that did not happen.
5. ★★ **The Python leg was not touched**, so trigger 5's condition (does the state diff move when
   `display` fires?) remains unassessable.

### 8 — Follow-up candidates

- ★★★★ **The ruling this report asks for**: a home for `CP_CEL`, or a decision to strip
  `view_cel.s`/`composite.s` from this probe after all — which would make `MAP_RESERVED` free
  exactly as P6.28 measured it, at the cost of the probe no longer being a general integration
  harness.
- ★★★ **Record that `MAP_RESERVED` has two consumers with different claims** (§3.6 check 1) beside
  AD-177 — `memmap.inc` says reservation, `p3b_probe.s:174` says occupied.
- ★★ **§7.1's real figure**: re-measure `P3_CODE_END` once `print`/`display` are real.
- ★★ **§7.3**: exercise ruling 3's flat window before relying on it.

### 9 — User interaction during task

**None.**

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-09-a-placement-measured-for-one-configuration-does-not-transfer-to-another`
  — *initiator: executor*. A free-space measurement is only valid for the configuration that
  produced it; transplanting the conclusion to a build that links what the measured one dropped
  reinstates the occupant the measurement excluded — and the region reads free in the map that
  reserved it while a second consumer already owns it.

### 11 — Commit

`469921e` — the span extension and the collision guard, pushed to origin/wip before this report.
★★ **No wiring commit**: commit 2 of §9's sequence was not reached.
