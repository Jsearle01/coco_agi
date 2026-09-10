## Form B Report — P6.28f (T-P0-084f) — ruling C separates flags; the constraint is in shared source
**Class:** integration (§4A) — **AC-1/AC-2/AC-3 all met; the fix is HELD at trigger 1.**  wip.

★★★★★ **All three eye-gate and fault ACs are now satisfied.** AC-2 confirmed this task — Jay:
***"yes it was black"***. AC-1 carried from P6.28e — ***"yes the text appreaed was readable and
stayed in the sroll box"***. **AC-3 demonstrated for the first time**, both sides.

★★★★★ **And ruling C does not unblock the fix.** The split separates **flags**; the 3-byte
`jsr res_decode` lives in `src/harness/res_core.s`, which is **shared source**. Applied, the `p3b`
row's cel configuration reaches `P3_CODE_END = $5302` against `CP_CEL = $5300` — **2 over — and that
row then does not assemble at all.** ★★★ **A gate row cannot relieve a source constraint.**

★★★★ **Trigger 1 fired and the fix is held.** The tree is green: `p3b` builds at
`F51FF8482D0B07E49F46B18612D20B06`, 13,925 B, and `res_decode` has one caller again.

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-084f dispatch receipt (HEAD `6145913`, wip). At report time HEAD `bee179a`.
`git status` clean but for `coco_agi.code-workspace` (untracked).

---

### §3 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===        6145913  wip   ?? coco_agi.code-workspace
=== POP3_port ===       104b197  wip
=== karateka_coco3 ===  29f8f0a  wip

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6

CHECK OK: src/harness/vm_tables.s matches optable.py.

=== p3b gate row binary ===
13925 B  F51FF8482D0B07E49F46B18612D20B06          ★ as expected

=== res_decode call sites ===
res_probe.s:127: jsr     res_decode                ★ exactly one; absent from res_core.s

=== gates.manifest p3b row, verbatim (unchanged) ===
p3b	src/harness/p3b_probe.s	build/p3b_probe_pk_fresh.bin	-DHAL_GFX_MODE_SERVICE
  -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED	integration probe -- PLANE_WIN_MMU
  comes from the SOURCE (line 65), never the command line	purpose=timing
```

★★ **§2T citation, P6.28e §3's caveat carried forward unchanged.** Both siblings at **the same refs
P6.28e §3 recorded**, read at their **`wip` working trees**, not a public ref (§2S). No tracked
source modification in either.

★★★ **Every expected value matched and no §3 stop condition fired.** ★★★★ **§1's AC-2 ruling arrived
UNFILLED** — the placeholder *"[TO BE FILLED BY JAY BEFORE THIS DISPATCH IS SENT]"* was still in the
text — so per §1 I stopped at the grep and asked. **Jay: *"yes it was black"*.** Work resumed there.

---

### 1 — Summary

The fix is fully validated and cannot land. Everything that does not depend on the 2 bytes is
committed (`bee179a`); the fix and its fault arm are held.

### 2 — Files modified — committed (`bee179a`)

- `harness/tools/gates.manifest` — the `p3b_text` row (ruling C). ★★ It records that the row
  currently gates **health** over a build whose messages are ciphertext, rather than implying a
  correctness it does not yet have.
- `harness/tools/p3b_run.lua` — `P3_PBUF` printable-ASCII count at run end (**+36 lines, no
  churn**; editor used, per trigger 6 and P6.28d §7.7).
- `harness/tools/p3b_show.ps1` — `P3_PBUF` in the symbol list; `-DecodeFault` retained **with a
  loud notice that its consumer is absent**; `P3_PBUF` added to the headless log filter.

**Held, not committed:** the `res_core.s` decode call + `RES_FAULT_DECODE_HIT` guard (P6.28e §5's
diff, re-applied verbatim and reverted), and `run_gates.sh`'s `p3b_text` block.

### 3 — Reasoning

**3.1 ★★★★★ Why the gate split cannot work.**

Ruling C's premise is that a second row lets the fix land while the timing row keeps its binary.
★★★★ **But a manifest row selects FLAGS against ONE source tree.** `res_open` is in `res_core.s`,
included by `p3b_probe.s` in **both** configurations, so the call is present in the cel build
whatever the row says:

```
cel configuration, fix applied:   P3_CODE_END = $5302   CP_CEL = $5300   -> over by 2
                                  the row does not assemble; no artifact is produced
text configuration, fix applied:  14,592 B  3C7BA151...  P3_CODE_END = $559A, 2,662 B spare
```

**3.2 ★★★★ Why moving `CP_CEL` is not the escape either.**

It is the cheapest conceivable unblock — 16 bytes into a region this probe **already** overlaps by
1,456 [AD-179] — and I did not take it. ★★★★★ **`CP_CEL` is an address operand in the compositing
code (`ldx #CP_CEL`), so relocating it changes the emitted bytes and therefore the `p3b` timing
binary's hash.** That is **trigger 1's literal condition**, and AD-96 is recorded in
`gates.manifest` precisely to stop published figures drifting onto a different program.

**3.3 ★★★★★ AC-3, demonstrated, and the two instrument defects found building it.**

The observable is `P3_PBUF`'s printable-ASCII count — **a property, never the text** [§2P]:

```
CLEAN  (decode on MISS path only)          16 of 16 bytes printable -- DECODED
FAULT  (-DRES_FAULT_DECODE_HIT, hit too)   18 of 32 bytes printable -- ★★★ NOT DECODED
```

★★★ **Corroborating cost signal:** 22.3621 s vs **36.3802 s** emulated for the same 120 cycles —
the fault arm re-XORing on every cached re-bind, which is L-66's 3.01 binds/cycle made visible.

★★★★ **Two defects in my own instrument, both of the shape this project keeps paying for:**

1. ★★★ **It was placed beside the vocabulary readout, which runs ONLY when the watchdog fires.** On
   a healthy run it printed nothing at all. **An observable emitted only after the run has failed
   cannot compare a good arm against a bad one.**
2. ★★★★ **It counted all 64 bytes including the dead tail past the NUL**, mixing live text with
   whatever an earlier, longer message left — and reported **NOT DECODED for the very build Jay had
   just read as legible**. ★★★★★ **An instrument that contradicts a confirmed observation is the
   instrument's problem first**: the eye gate is tier-1 evidence and this readout is tier-3.
   Counting to the terminator gives the table above.

★★ And the headless log filter dropped the new line, because **an allowlist drops what it does not
name** — the same conclusion-loss shape as the star-in-a-pattern two tasks ago.

**3.4 ★★ §2H's three checks.**

1. **A second mechanism for another object class?** ★★★ Yes: **a gate row configures a BUILD; a
   size constraint lives in SOURCE.** Ruling C treated them as the same lever.
2. **The calling routine.** `res_open`'s miss branch is shared by every probe that links
   `res_core.s` — **the enclosing fact is "shared", which is what the row cannot change.**
3. **Grep the reports for the same subsystem.** P6.28c measured the 1-byte headroom; P6.28d found
   the missing call; P6.28e priced it at 3 bytes; this task shows the row does not help. ★★★ **Four
   reports, one constraint, unchanged throughout.**

**3.5 ★★ Authority tier.** No ScummVM or Specs claim. Every figure is `lwasm` or MAME output on this
tree at this HEAD.

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it. AC-1 and AC-2 are eye-gated by Jay; nothing else is.**

- **AC-1 [eye gate — Jay — carried]** ★★★★★ **PASSED (P6.28e).** *"yes the text appreaed was
  readable and stayed in the sroll box."* Not re-run; AC-2 was confirmed, so the §1 condition for
  re-running did not arise.
- **AC-2 [eye gate — Jay]** ★★★★★ **PASSED, this task.** ***"yes it was black."*** ★★★ Obtained
  before any further work, per §1. **L-113 is satisfied: AC-1's pass is now a validated positive.**
- **AC-3 [state-comparable · fault injection]** ★★★★★ **PASSED — first time.** Both sides shown
  above. **The re-bind is exercised by the title screen's own repeated `display` calls** — 120
  cycles at room 83, where the same LOGIC is re-bound every cycle (L-66's 3.01/cycle). The wrong
  output is **cipher bytes in the substitution buffer**: 18 of 32 printable against 16 of 16.
- **AC-4 [byte-comparable · SHA-256]** ★★★ **PASSED for the `p3b` row: `F51FF848…`, 13,925 B,
  UNCHANGED.** ★★ The `p3b_text` row currently builds **without** the fix; **with** it, 14,592 B
  `3C7BA151…`. `git diff --stat HEAD -- src/hal/ src/engine/` is **empty**.
- **AC-5 [state-comparable · call graph]** ★★ **NOT MET as specified, and the reason is the
  finding.** With the fix applied there were **three** source lines — `res_core.s` miss path,
  `res_core.s` inside the `RES_FAULT_DECODE_HIT` guard (inactive by default), `res_probe.s:127` —
  i.e. **two active**. ★ After the revert: **one**. The dispatch expected two; the fault guard is
  the third line and is deliberate.
- **AC-6 [suite]** ★★ **PASSED with a stated shortfall.** `★ gates run: pic res cel comp p3b -- all
  green`; `hal_sync_check.py` OK ×3; `reg_discipline.py` 8; `gen_vm_tables.py --check` **CHECK OK**.
  ★★★ **`p3b_text` is NOT in the suite output**: its `run_gates.sh` block was held with the fix,
  because a *correctness* row green over a ciphertext binary is a gate that passes for the wrong
  reason. **The row exists in the manifest; it is not yet run.**
- **AC-7 [byte-comparable · runner]** ★★ **PASSED.** Both AC-3 arms from `p3b_show.ps1`
  (`-Text -Headless`, `-DecodeFault -Headless`); no hand-typed MAME line.
- **AC-8** One candidate; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §3's grep is above.

```
=== AC-3, both arms, 120 cycles, room 83 ===
CLEAN   ★ 120 cycles in 22.3621 emulated s
        final room 83, sprites 0, err 0, status=$00
        P3_PBUF $1C00: 16 of 16 bytes to the terminator are printable ASCII -- DECODED
FAULT   ★ 120 cycles in 36.3802 emulated s
        final room 83, sprites 0, err 0, status=$00
        P3_PBUF $1C00: 18 of 32 bytes to the terminator are printable ASCII -- ★★★ NOT DECODED

=== the fix applied (held, not committed) ===
text  14592 B  3C7BA1519C9D7E69566E946FDB9373B8   P3_CODE_END $559A, 2,662 B spare
cel   DID NOT ASSEMBLE:
  src/harness/p3b_probe.s(1039) : ERROR : "P3b code has grown into the decoded-cel buffer
    at CP_CEL ($5300, 4,784 B) ..."
  with -DP3B_ACCEPT_OVERRUN:  P3_CODE_END = 5302   CP_CEL = 5300     -> over by 2

=== after the revert ===
cel   13925 B  F51FF8482D0B07E49F46B18612D20B06   ★ unchanged
res_decode call sites: res_probe.s:127             ★ one
★ gates run: pic res cel comp p3b  -- all green
CHECK OK: src/harness/vm_tables.s matches optable.py.
```

**25.2 bundled-artifact grep:** N/A — no bundled artifact.

**25.3 operator-runtime-smoke — THE EYE GATE.**

**Invocation** (`p3b_show.ps1`, RGB, **no `-nothrottle`** [§2U.2], `P3B_ROOM=83`, `-Hold 12`):
`-Fault` then `-Text`, fault arm first [L-113]. Launch path **`poke`** — image poked into RAM and PC
set from Lua after DECB's OK prompt. **Not `live-disk`.**

- **AC-2, fault arm, ran first (P6.28e's run):** **Jay: *"yes it was black"*** — confirmed this task.
- **AC-1, wired arm (P6.28e's run):** **Jay: *"yes the text appreaed was readable and stayed in the
  sroll box"*.**

★★★ §2P: no screenshot and no message text is committed; Jay's words and a printable-byte **count**
are the record.

### 6 — Reactive deviations and route accounting

**Deviation 1 — held at the grep for AC-2.** §1's ruling was unfilled; §1 says do not proceed past
§3 without Jay's word. **Asked and received before any further work.**

**Deviation 2 — `run_gates.sh`'s `p3b_text` block was written and NOT committed.** §4A asks both
rows green. ★★ A correctness row green over a ciphertext binary **passes for the wrong reason**, so
the row is recorded in the manifest and left un-run until the fix lands.

**Deviation 3 — `-DecodeFault` is committed with no consumer**, and announces that at run time.
★★ Deleting it would mean re-deriving AC-3's arm; a **silent** dead switch would be worse than
either. **A control that does nothing must say so.**

**ROUTE ACCOUNTING.** ★★★★ Scope **A** was implemented and reverted (the row landed; the fix did
not). Scope **B** is **complete** — AC-3 is demonstrated, which P6.28e could not do. Scope **C** did
not commit: **the eye-gate commit does not exist**, because its fix is not in the tree and an
eye-gate commit whose fix the repo cannot build would record a pass for a binary nobody can produce.
★★★★★ **Scope D's design-spec edit is NOT made** — conditioned on the fix landing.

★★★ **I did not take either escape** (re-point the `p3b` row's flags; move `CP_CEL`). §3.2 gives the
measured reason for the second; the first is AD-96 and my own commitment two tasks ago.

### 7 — Uncertainty flags

1. ★★★★★ **The 2 bytes remain the only open question**, and it is now four reports old. Routes:
   free ≥2 bytes in the cel configuration; retire or re-baseline the `p3b` timing row; or split the
   SOURCE so the cel build does not link the decode call — **the last is a silent divergence and I
   do not recommend it** (the timing row would then under-report the decode's real cost).
2. ★★★ **AC-3's fault arm was run with the fix out-of-tree.** Its evidence is reproducible only by
   re-applying P6.28e §5's diff; `-DecodeFault` alone does nothing today, and it says so.
3. ★★ **`p3b_text` is not in the suite.** Until it is, nothing automatically re-checks the text
   path — the eye gate is the only instrument that has ever seen it.
4. ★★ **The `res_err` masking** (P6.28e §7.4), **`$FFA4` ownership** [AD-182] and **`print`'s
   key-wait** [AD-183] all remain open, out of scope here.

### 8 — Follow-up candidates

- ★★★★★ **The ruling on the 2 bytes** (§7.1). Everything else is done and waiting on it.
- ★★★ **Land the fix, add `run_gates.sh`'s `p3b_text` block, make the design-spec edit** — one
  commit once §7.1 is settled.
- ★★ **Correct AC-5's expectation in the backlog**: with the fault guard the fix yields **three**
  source lines, two active.

### 9 — User interaction during task

Jay confirmed AC-2, which §1 required before work could continue: ***"yes it was black"***.

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-10-an-observable-that-only-fires-on-failure-cannot-compare-two-arms`
  — *initiator: executor*. §3.3's first defect: the readout was placed on the stall path, so a
  healthy run emitted nothing and the good arm produced no evidence at all — a comparison needs its
  instrument on the path both arms take, and the successful path is the one that gets forgotten.

### 11 — Commit

`bee179a` — the `p3b_text` row and the decode observable, pushed to origin/wip before this report.
★★ **No fix commit and no eye-gate commit**; both are held at trigger 1.
