## Form B Report — P6.28 (T-P0-084) — placement measurement for `text_vm_probe.s`
**Class:** integration (§4A) — **stopped at §5A for the placement ruling.**  wip.

★★★★★ **This is a §5A stop, as the dispatch directs: measure, propose, stop before any wiring.**
Leading with the numbers, per §9.

---

## THE PLACEMENT NUMBERS

### What it needs

| component | bytes | how measured |
|---|---:|---|
| skeleton library — VM + res + picture + parser + HAL, **no** cel/composite, **no** text | **11,994** | assembled |
| **+ `src/engine/text.s`** | **13,556** | assembled — **Δ 1,562** |
| *(alternative)* + `view_cel.s` + `composite.s` instead of text | 13,082 | assembled — Δ 1,088 |
| probe glue (staging, handshake, room setup, cycle driver) | **~927** | **derived by difference**, not assembled — see §3.3 |
| **`text_vm_probe.s`, estimated total** | **~14,483** | 13,556 + glue |

★★★ **Cross-check that makes the 1,562 trustworthy:** `text.s` was measured a second time and
independently, against a bare HAL stub — 773 B → 2,335 B, **Δ 1,562**, identical to the delta inside
the full skeleton. Two different baselines, same number.

★★ **Additional addresses needed, not code:** the substitution buffer **576 B**
(`TXT_PBUF_MAX`; `txt_pbuf` is a caller-supplied `fdb`, so it is **external** to the 1,562) and the
authored font **2,048 B**.

### Free regions at HEAD, for *this* probe

★★★★ **`memmap.inc`'s own header governs: "THE HARNESS IS NOT CHANGED BY THIS FILE AND MUST NOT BE.
`src/harness/` keeps its own addresses."** `p3b_probe.s` *chooses* to org at `MAP_CODE` and assert
against `MAP_CODE_END`; that is its decision, not a constraint on a new probe.

| region | bytes | free for `text_vm_probe`? |
|---|---:|---|
| `MAP_INPUT` `$1C00-$2000` | 1,024 | ★ **YES** — this probe has no `getstring.s` and no key decoder |
| `MAP_CODE` `$2000-$5300` | 13,056 | occupied by the probe body |
| `MAP_RESERVED` `$5300-$6000` | 3,328 | ★★ **YES** — it is the parser/sound *reservation*, and the only probe that uses it is `p3b_probe.s` for `CP_CEL` cel staging, which **this probe drops** |
| `MAP_ARENA_WIN` `$6000-$A000` | 16,384 | NO — resources |
| `MAP_PRI_SLICE` `$A000-$C000` | 8,192 | NO — priority slice / vocabulary window |
| `MAP_PHASE_WIN` `$C000-$E000` | 8,192 | NO — volume window / framebuffer slice |
| `MAP_TABLES` `$E000-$FF00` | 7,936 | ★ **PARTLY** — font 2,048 + KQ1 vocab 3,144 = 5,192, leaving 2,744 |

### The proposal — one placement

> ★★★★★ **`text_vm_probe.s` orgs at `MAP_CODE` (`$2000`) and asserts against `MAP_RESERVED_END`
> (`$6000`) rather than `MAP_CODE_END`, giving it 16,384 B for an estimated 14,483 — about 1,900 B
> spare.** The substitution buffer goes in `MAP_INPUT` (`$1C00`, 1,024 B free); the font and the
> vocabulary go in `MAP_TABLES` (`$E000-$FF00`); `parser.s` is inline in the code span rather than
> org'd to `$E000` as `p3b_probe.s` does.

★★★★ **Nothing in `memmap.inc` changes. `MAP_CODE`, `MAP_CODE_END`, `MAP_RESERVED` and
`MAP_RESERVED_END` keep the values they have**, and no reservation is reduced — §12's prohibition and
AD-95's "fourth reduction" tripwire are both untouched. **The probe simply spans two regions that are
both unused by it**, and says so in an assertion of its own.

★★ **Why not the alternative** — org the body at `$2000-$5300` and put the text engine at `$E000`
like p3b puts its parser: it works arithmetically (7,936 − 2,048 font − 3,144 vocab = 2,744 ≥ 1,562)
but leaves **1,182 B** of headroom in a region also holding the font and vocabulary, and it sizes on
**KQ1's** 3,144-byte vocabulary when the corpus maximum is 6,828 (SpaceQuest-2). ★ At that vocabulary
the region has **−1,940 B** and the placement fails. **The proposed placement does not depend on which
title is loaded.**

---

## ★★★ A CONTRADICTION IN §3's PREMISE, found by the grep

The dispatch states: *"`p3b_probe.s` is 13,010 bytes against `MAP_CODE`'s 13,056 — 46 spare."*

**Measured at HEAD** (`build/measure_p3b.map`):

```
Symbol: MAP_CODE      = 2000
Symbol: MAP_CODE_END  = 5300
Symbol: P3_CODE_END   = 52FF
```

★★★★ **`$52FF − $2000` = 13,055 B occupied of 13,056. The spare is ONE byte, not 46.**

★★★ **It does not change the dispatch's conclusion** — 46 bytes and 1 byte are both far short of
1,562 — **so §4's "contradiction → stop" is satisfied by reporting it here rather than by abandoning
the measurement.** It is reported because a placement ruling would otherwise rest on a figure that is
45 bytes optimistic, and because **a number in a comment has no producer** is this project's own
recurring lesson [AD-95].

★★ **Two further figures in §3 also differ from measurement**, in the same direction and to no
different conclusion: the text engine is **1,562 B assembled**, not "1,411 bytes of code", and its
substitution buffer is **576 B** (`TXT_PBUF_MAX`), not 768.

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-084 dispatch receipt (HEAD `0ec045d`, wip; descends from `645ffef` as expected).
`git status` clean but for `coco_agi.code-workspace` (untracked editor file) and the two scratch
measurement stubs, which live in the scratchpad and are **not** in the repo.

---

### §4 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===        0ec045d  wip   ?? coco_agi.code-workspace
=== POP3_port ===       104b197  wip   (no tracked modification)
=== karateka_coco3 ===  29f8f0a  wip    M harness/smoke/last-run.log
```

★★ **§2T citation, P6.27 §3's caveat carried forward unchanged.** Both siblings are at **the same
refs P6.27 §3 recorded**, read the same way — at their **`wip` working trees**, not a public ref
(§2S). Neither has a tracked source modification; Karateka's one tracked change is a run log. ★ **No
sibling artifact is built or claimed**; this task touches no HAL file.

```
=== hal_sync ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

=== reg_discipline ===
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6

=== p3b_probe.bin ===
p3b_probe_pk_fresh.bin  13925 B  F51FF8482D0B07E49F46B18612D20B06
```

**`vm_op_modelled`** — assembles and resolves in the current tree: it is defined in
`src/harness/vm_core.s` and referenced **55 times** in `src/harness/vm_tables.s`. Every build above
links it.

**The eight opcodes from AD-146, enumerated verbatim from `src/harness/vm_tables.s` [L-77]:**

```
239: fdb vm_op_modelled   ; 65 print(s)                [modelled]
240: fdb vm_op_modelled   ; 66 print.v(v)              [modelled]
241: fdb vm_op_modelled   ; 67 display(nns)            [modelled]
242: fdb vm_op_modelled   ; 68 display.v(vvv)          [modelled]
243: fdb vm_op_modelled   ; 69 clear.lines(nns)        [modelled]
246: fdb vm_op_modelled   ; 6C set.cursor.char(s)      [modelled]
247: fdb vm_op_modelled   ; 6D set.text.attribute(nn)  [modelled]
250: fdb vm_op_modelled   ; 70 status.line.on()        [modelled]
251: fdb vm_op_modelled   ; 71 status.line.off()       [modelled]
```

★★★ **All nine table entries (eight named opcodes; `status.line.on/off` is two entries) are still
`vm_op_modelled`. No prior task silently wired one**, so §4's stop condition does not fire.

---

### 1 — Summary

Measured the minimum skeleton for `text_vm_probe.s` and its available placements; **stopped before
wiring**, per §5A. The skeleton is **13,556 B of library** plus **~927 B of estimated glue**, against
a proposed **16,384 B** span (`MAP_CODE` + `MAP_RESERVED`, both unused by this probe) — **about 1,900
B spare, with no change to any address in `memmap.inc`.**

★★★ **Three figures in the dispatch's §3 differ from measurement**, the load-bearing one being
`p3b_probe.s`'s spare capacity: **1 byte, not 46.**

★★ **One structural finding that constrains any future "minimal VM":** `parser.s` is **not
optional** — `vm_tests.s` implements `said()` as a VM *test* opcode and references `par_said`,
`par_accepted` and `par_cli` directly, so the VM will not assemble without it (§3.2).

### 2 — Files modified

**None in the repository.** ★★ The two measurement stubs are in the session scratchpad
(`measure_base.s`, `measure_text.s`, `measure_skel.s`) and are deliberately **not** committed: they
are a measurement, not a deliverable, and `text_vm_probe.s` proper is post-ruling work.

★ Assembled artifacts landed in `build/` (untracked): `m_base.bin`, `m_text.bin`, `m_cfg.bin`,
`measure_vm.bin`, `measure_p3b.bin` and their maps.

### 3 — Reasoning

**3.1 ★★★★ Why the measurement is a delta and not a citation.**

`text.s`'s size is quoted in P6.19 and again in this dispatch, with two different numbers. ★★★ **A
number in a comment has no producer** [AD-95], so it was measured twice from scratch here — once
against a bare HAL stub and once inside the full skeleton — and both give **1,562 B**. The agreement
across two unrelated baselines is what makes it a measurement rather than a third quoted figure.

**3.2 ★★★★★ `parser.s` is not optional, and that is a finding about "minimal VM".**

The first skeleton omitted it, on the reasoning that a title screen takes no typed input. It does not
assemble: `vm_tests.s:202-236` references `par_accepted`, `par_cli` and `par_said` directly, because
**`said()` is a VM test opcode and the parser is its implementation.**

★★★ **The consequence for placement is real:** any probe that runs the VM at all carries the parser's
954 B, whether or not a line is ever typed — and if `said()` is *evaluated* (logic 0 does evaluate
said patterns), the vocabulary window must be mapped too. ★★ **That is why the proposed placement
puts the vocabulary in `MAP_TABLES` and does not try to reclaim it.**

**3.3 ★★★ The glue figure is derived, and is labelled as such.**

`p3b_probe.s` occupies 13,055 B in `MAP_CODE` plus 954 B of parser org'd at `$E000` = 14,009 B total.
The equivalent stub library (cel + composite, no text, parser inline) is 13,082 B. **The difference,
927 B, is p3b's own glue.** ★★ **It is arithmetic on two measurements, not a measurement**, and
`text_vm_probe`'s glue will differ — probably downward, since it stages no sprites. ★ The ~1,900 B of
headroom in the proposal is large enough that the estimate's error does not change the conclusion,
which is the only reason it is safe to propose on.

**3.4 ★★★ Why cel and composite can go, stated from evidence rather than assumption.**

`p3b_run.lua`'s own completion line for room 83 reads **`final room 83, sprites 0`**. The title screen
stages no sprites, so `view_cel.s` and `composite.s` are dead weight for this probe — **1,088 B
measured**, which is most of what `text.s` costs. ★★ **This is scoped to this probe and to room 83**;
it is not a claim that the shipped engine can drop them.

**3.5 ★★ §2H's three checks, on the placement question.**

1. **A second mechanism for another object class?** Yes — **the harness has its own address space**,
   separate from the engine map, stated in `memmap.inc`'s header. ★★ The dispatch frames the
   constraint as `MAP_CODE`, which is the *engine's* fact; the probe's fact is that it may org where
   it likes. **Reading the constraint as binding on a probe is what would have forced a needless
   `MAP_CODE` change.**
2. **The calling routine.** `MAP_RESERVED`'s only current consumer is `p3b_probe.s`'s `CP_CEL`, not
   the engine — the parser and sound it is reserved *for* do not exist yet. **The enclosing fact is
   that the reservation is notional today**, which is exactly why §12 forbids *reducing* it and why
   this proposal does not.
3. **Grep the reports for the same subsystem.** The `MAP_RESERVED` boundary has moved three times
   (T-P0-034, T-P0-036, T-P0-037), a fourth was taken and reverted, and `MAP_RESERVED_MIN` exists to
   stop a fifth. ★★★ **This proposal deliberately does not move it** — a probe spanning an unused
   region is not a reduction, and the distinction is the whole reason the floor was installed.

**3.6 ★★ Authority tier.** No ScummVM or Specs claim. Every figure is `lwasm` output on this tree at
this HEAD, or arithmetic on it that is labelled as arithmetic (§3.3).

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it. This is a pre-wiring stop, so most are not yet
attempted and are marked so rather than claimed.**

- **AC-1 [eye gate — Jay]** ★★★★★ **NOT ATTEMPTED — the dispatch stops the task before wiring.**
  Nothing was built and Jay has seen nothing. **No eye-gate claim is made.**
- **AC-2 [eye gate — Jay]** **NOT ATTEMPTED.** Same reason. ★★ The fault arm is the current
  `vm_op_modelled` binary and requires no work to produce — it is what HEAD already builds.
- **AC-3 [byte-comparable · observed by: SHA-256]** ★ **HELD, not passed.** `p3b_probe_pk_fresh.bin`
  = `F51FF848…`, 13,925 B, recorded in §4 for comparison **after** wiring. Nothing in `src/` changed
  this task, so it cannot have moved; the check that matters is the post-wiring one.
- **AC-4 [state-comparable · observed by: grep of `vm_tables.s`]** ★★ **HALF-MET, deliberately.** All
  nine entries are **enumerated with their opcode numbers** in §4 — the "before" column of the wiring
  table. The "after" column does not exist because no wiring was done.
- **AC-5 [suite]** ★★ **NOT RUN, and stated rather than skipped quietly.** No `src/` file was
  modified, so the suite cannot have moved; `hal_sync_check.py` (×3) and `reg_discipline.py` were run
  as part of §4's grep and are green. **The full `run_gates.sh all` belongs with the wiring commit,
  where it can actually fail.**
- **AC-6 [byte-comparable]** **NOT APPLICABLE YET.** No probe exists, so no runner does. ★ The
  measurement invocations are recorded verbatim in §5.
- **AC-7 [suite]** `None.` — see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §4's grep is above. The measurement invocations and results:

```
lwasm --format=raw --output=build/measure_p3b.bin --map=build/measure_p3b.map -I. \
      -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED \
      src/harness/p3b_probe.s
p3b_probe.bin 13925 B
  Symbol: MAP_CODE = 2000   MAP_CODE_END = 5300   P3_CODE_END = 52FF
  Symbol: P3_PARSER_BASE = E000   P3_PARSER_TOTAL = 03BA   P3_VOCAB = E3BA

lwasm --format=raw --output=build/measure_vm.bin -I. \
      -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK src/harness/vm_probe.s
vm_probe.bin  9660 B

-- text.s against a bare HAL baseline --
base (HAL only)         773 B
base + text.s           2335 B
TEXT ENGINE COST        1562 B

-- the skeleton, three configurations --
skel  (VM+res+pic+text+parser+HAL, NO cel/comp)  13556 B
skel  minus text.s                               11994 B
skel  PLUS cel+composite  (p3b cross-check)      13082 B
```

★ Flags for all three skeleton configurations:
`-I. -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED`, plus
`-DMS_NO_TEXT` / `-DMS_WITH_CEL` to select the configuration.

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing was built for delivery.

**25.3 operator-runtime-smoke:** ★★★★ **N/A — and explicitly NOT "pending Jay".** The task stops
before anything can reach a screen. §4A's rule that an integration task is not reportable until Jay
has seen it **applies to the wiring task, which this is not**; this report delivers a measurement and
asks for a ruling.

### 6 — Reactive deviations and route accounting

**Deviation 1 — the skeleton stub gained `parser.s`.** It was omitted on the reasoning that a title
screen takes no typed input; it does not assemble without it (§3.2). ★★ Reported because it changes
what "minimal VM" can mean for every future probe, not just this one.

**Deviation 2 — `content/agi_palette.s` removed from both measurement stubs.** `gfx.s` already
includes it; including it again is a multiply-defined error. ★ Removed from **both** stubs, so the
delta is unaffected — noted because changing one arm of a differential measurement and not the other
is the L-73 shape.

**ROUTE ACCOUNTING.** ★★★ The dispatch proposed scope A (measure, stop), B (wire) and C (build the
probe). ★★★★ **This report contains A only, which is what §5A instructs.** No opcode was wired, no
probe was written, no reference stub was touched, and **`memmap.inc` was not edited.** ★★ §11's
design-spec edit is **not** made: it is conditioned on the eye gate passing, and the eye gate has not
run.

★ **Trigger 1 did not fire** — a free region *was* found. The stop is §5A's unconditional
"then stop", not a blocked-placement stop.

### 7 — Uncertainty flags

1. ★★★ **The glue figure (~927 B) is arithmetic, not a measurement** (§3.3). The ~1,900 B of headroom
   absorbs a large error, but the total is an estimate and the first real assembly of
   `text_vm_probe.s` is what will settle it.
2. ★★★ **`MAP_RESERVED` is free *for this probe* and not free in general.** The proposal depends on
   `text_vm_probe.s` dropping cel staging. ★★ **If a later task adds sprites to this probe, the
   placement is void**, and the probe should assert that rather than discover it.
3. ★★ **Whether `said()` is evaluated on KQ1's title screen is not measured here.** The proposal
   maps the vocabulary regardless, which is the safe direction; the cost is 3,144 B of `MAP_TABLES`
   that may be unnecessary.
4. ★★ **The `-DPRI_PACKED` / `-DPLANE_WINDOWED` flag pair was carried from `p3b_probe.s` unexamined.**
   They are right for a probe that renders a picture, but this task did not verify that a
   text-and-picture probe needs `PRI_PACKED` at all.
5. ★ **Nothing about the opcodes' *behaviour* is measured** — only that all nine are still
   `vm_op_modelled` and that the engine implementing them assembles.

### 8 — Follow-up candidates

- ★★★★ **The ruling this report asks for**: accept the `$2000-$6000` placement, or direct otherwise.
- ★★★ **Correct the three §3 figures in the backlog** — p3b's spare (1, not 46), `text.s` (1,562, not
  1,411), the substitution buffer (576, not 768). **Orchestrator folds; reported here per §2D.**
- ★★ **Record that `parser.s` is mandatory for any VM-bearing probe** (§3.2) — it belongs beside
  AD-146 rather than in this report alone.
- ★ **Discharge §7.4** — decide whether `PRI_PACKED` is needed by a probe that composites nothing.

### 9 — User interaction during task

**None.**

### 10 — Candidate(s) captured this task

**None.** ★★ The one candidate-shaped observation — *a constraint stated for one component may not
bind a differently-scoped one* (`MAP_CODE` binds the engine, not a harness probe) — **is already this
project's §2H check 2 applied to an address**, and §2C wants new rows rather than restatements of a
standing rule.

### 11 — Commit

**No commit.** ★★ Nothing in the repository changed: the measurement stubs are scratchpad files and
the assembled outputs are untracked `build/` artifacts. **There is nothing to push, and creating a
commit to carry a report about work not yet done would put a report on `wip` describing a tree state
that does not exist.** ★ This report is committed on its own.
