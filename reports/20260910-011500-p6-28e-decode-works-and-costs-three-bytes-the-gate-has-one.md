## Form B Report — P6.28e (T-P0-084e) — the decode works; it costs 3 bytes and the gate has 1
**Class:** integration (§4A) — **AC-1 PASSED; stopped, uncommitted, at a 2-byte blocker.**  wip.

★★★★★ **AC-1 PASSES. Jay, on the wired arm: *"yes the text appreaed was readable and stayed in the
sroll box"*.** `res_decode` on the cache-miss path fixes it. **AD-156's prediction is confirmed** and
P6.28d's §7.2 is settled: **the wrap symptom was the same defect, not a second one** — ciphertext
carries no spaces for `txt_wrap` to break at. **Trigger 4 does not fire.**

★★★★★ **AND IT CANNOT BE COMMITTED.** `jsr res_decode` costs **3 bytes**. The p3b gate's binary — the
**cel** configuration, per `gates.manifest` — had **1 byte** of headroom, so it lands at
`P3_CODE_END = $5302` against `CP_CEL = $5300`: **over by 2.** The collision guard from `469921e`
caught it at assembly time instead of letting code overwrite the cel buffer.

★★★★ **The change is therefore REVERTED and the tree is green.** The verified diff is in §5 for the
ruling. **Nothing about the fix is in doubt; only where the 2 bytes come from.**

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-084e dispatch receipt (HEAD `f6d08a7`, wip; descends from `c86a709` as expected).
At report time HEAD unchanged bar this report. `git status` clean but for `coco_agi.code-workspace`.

---

### §3 — Pre-dispatch grep (C-13), verbatim

```
=== coco_agi ===        f6d08a7  wip   ?? coco_agi.code-workspace
=== POP3_port ===       104b197  wip
=== karateka_coco3 ===  29f8f0a  wip

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6

CHECK OK: src/harness/vm_tables.s matches optable.py.

=== p3b wired pre-change ===
14589 B  0574A33A6484D6019321678B5C6C1CE2

=== res_decode call sites ===
res_probe.s:127: jsr     res_decode          ★ exactly one, and absent from vm_run.s
```

★★ **§2T citation, P6.28d §4's caveat carried forward unchanged.** Both siblings are at **the same
refs P6.28d §4 recorded**, read at their **`wip` working trees**, not a public ref (§2S). Neither has
a tracked source modification.

★★★★ **THREE FIGURES IN THE DISPATCH DO NOT MATCH THE TREE. None blocks; all three are reported
because a ruling would otherwise rest on them.**

1. ★★★ **The wired hash is `0574A33A…`, not `14EBADB6…`** — same size, 14,589 B. **`14EBADB6…` is
   the pre-`P3_FONT` build.** P6.28d moved the font pointer from `MAP_FONT` to `P3_FONT`, changing
   one immediate operand ($E0B8 → $5800) and no lengths. The dispatch quoted the superseded figure.
2. ★★★ **`src/engine/res_open.s` does not exist.** `res_open` lives in `src/harness/res_core.s`.
3. ★★★★★ **There is no `res.py`, and the Python leg ALREADY DECODES.**
   `tools/volread/logic.py:102` does `body[strings_pos:end] = decrypt(...)` at parse time — which is
   why the reference has always rendered correct text. **§4A's instruction to "decode the resource
   bytes on cache miss before stashing" in Python would DOUBLE-XOR and re-encrypt**, the exact
   hazard the ruling names on the 6809 side. ★★★ **So the Python leg was not touched**, and §2V is
   satisfied by the legs CONVERGING: the fix brings the 6809 to where the reference already was.

★ **No stop condition in §3 fired** (`res_decode` had one caller, absent from `vm_run.s`).

---

### 1 — Summary

The ruling's placement is correct and the fix is verified by eye. It is not in the tree, because the
3-byte call does not fit the gate's binary.

### 2 — Files modified

**None committed.** ★★ `src/harness/res_core.s` carried the change (+40 lines, of which **3 bytes**
emitted) through the eye gate and was reverted with `git checkout` once the cel configuration was
shown not to assemble. **The tree is byte-identical to `f6d08a7`.**

### 3 — Reasoning

**3.1 ★★★★★ The placement, and why it is above the index load.**

The miss path for a LOGIC is `res_core.s:349-369`. The call went **above `ldb 1,s`**, not between it
and the stash, and that is forced: **`res_decode` uses B freely and `res_cache_stash` takes the LOGIC
index IN B.** A call after the load would stash correctly-decoded bytes **filed under whatever index
the decode's last `ldb` left** — a poisoned cache presenting as a resource-mapping bug.

★★★ It also sits **above the `ABL_NOCACHE` divert**, so the ablation arm decodes too: with no cache
every fetch is a miss and it decodes once per fetch.

**3.2 ★★★★★ The 2 bytes, measured.**

```
cel configuration (the p3b gate's build, gates.manifest):
    P3_CODE_END = $5302        CP_CEL = $5300      -> over by 2
text configuration (-DP3B_NO_CEL):
    14,592 B  3C7BA1519C9D7E69566E946FDB9373B8    -> 2,662 B spare, builds clean
```

★★★★ **The cel configuration had ONE byte before this task** [P6.28c §3.1: `P3_CODE_END = $52FF`].
**Any 2-byte engine change breaks it; this correctness fix merely happened to be the first.** ★★★
**That is the durable finding, and it is bigger than this dispatch:** the integration probe's default
configuration can no longer absorb correctness work.

**3.3 ★★★★★ Why I did not move the gate to the stripped configuration.**

It is the obvious escape and it looked defensible — ruling A says cel/composite are stripped *"for
this gate"*, and at room 83 composite measures **0.0%** (0.0013 s over 120 cycles), so nothing
measurable is lost. ★★★★ **`gates.manifest`'s own header forbids it in as many words:** *"Flags are
load-bearing… comp built with -DHAL_GFX_MODE_SERVICE is 1,373 bytes, not 967, and is a different
program"*, and AD-96 is recorded there precisely because **published figures were taken from a
binary the manifest did not build.** The `p3b` row is `purpose=timing`. ★★★ **Changing its flags
would invalidate every published p3b timing figure**, which is the substitution AD-96 exists to
prevent. ★★ I also said one task ago that the default build stays byte-identical *"so the existing
p3b gate keeps testing the binary it has always tested"*; reversing that unilaterally, one task
later, is not mine to do.

**3.4 ★★★ Why I did not find the 2 bytes.**

★★ The `+3` is irreducible: the decode must be *called*, and every restructuring I considered
(folding decode into `res_cache_stash`, falling through, a combined entry point) costs 3 or more.
★★★ Freeing 2 bytes in the cel configuration means changing gated code, and §11 of the last three
dispatches forbids trimming to absorb a fit problem [AD-95's precedent: a boundary that slides
because each step was individually justified].

**3.5 ★★★★ What the eye gate proves, and what it does not.**

★★★ **It proves the placement.** The wired arm ran the miss-path build and Jay read the words. ★★
**It does not prove the hit path is safe**, because AC-3's common-path fault arm was built
(`AACA21DE…`, 14,595 B) and **never run** — the tree was reverted first. ★★★★ **So AC-3 is NOT met**,
and the ruling's central constraint is argued rather than demonstrated. §7.2.

**3.6 ★★ §2H's three checks.**

1. **A second mechanism for another object class?** ★★★ Yes, and it is §3's finding 3: **the Python
   leg decodes at PARSE time, not at cache-miss time.** The two legs reach the same state by
   different mechanisms, and the dispatch's instruction assumed they were the same mechanism.
2. **The calling routine.** `res_decode`'s new caller is `res_open`'s LOGIC miss branch — **the
   enclosing fact is "once per fetch", which is what makes in-place XOR safe.**
3. **Grep the reports for the same subsystem.** P6.28d named the missing call; P6.28c measured the
   1-byte headroom that now blocks it. ★★★ **The two compose: the fix was diagnosed in one task and
   is unaffordable because of a constraint measured in the one before.**

**3.7 ★★ Authority tier.** No ScummVM or Specs claim. The decode contract is `res_core.s`'s, citing
`logic.cpp decodeLogic`; the reference's own decode is `volread/logic.py:102`.

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it. AC-1 and AC-2 are eye-gated by Jay; nothing else is.**

- **AC-1 [eye gate — Jay]** ★★★★★ **PASSED.** Jay: *"yes the text appreaed was readable and stayed
  in the sroll box"*. Legible, and **fitting the panel** — so trigger 4 does not fire and P6.28d
  §7.2 is closed as the same defect. Launch path: **`poke`**, RGB, throttled, `P3B_ROOM=83`, 120
  cycles ≈ 21 s plus a 12 s hold — more than one full redraw cycle [AD-156]. **Not `live-disk`.**
- **AC-2 [eye gate — Jay — ran first]** ★★ **RUN, AND ITS CONFIRMATION IS AMBIGUOUS — stated rather
  than assumed.** The `-DTEXT_MODELLED` arm ran first at room 83 (`err 0`, 120 cycles, 12 s hold).
  Jay's reply opened with *"yes"* and then described the wired arm. ★★★ **I asked again explicitly
  and the answer had not arrived when this report was written.** He confirmed the same arm
  unambiguously one task ago (*"yes same as before. middle panel black"*), and **that is a different
  binary** — this task's fault arm carried the decode change. **Recorded as unconfirmed-for-this-run
  rather than carried over.**
- **AC-3 [state-comparable · fault injection]** ★★★★ **NOT MET.** The common-path fault arm was
  **built** (`-DRES_FAULT_DECODE_HIT`, **14,595 B `AACA21DE64E6A6CD7D68420A4458BC31`**) and **not
  run**: the cel configuration failed to assemble, the tree was reverted, and running a fault arm
  whose clean counterpart cannot be committed would demonstrate nothing that survives the revert.
  ★★★ **The ruling's constraint is therefore argued, not shown** [§2W]. §7.2.
- **AC-4 [byte-comparable · SHA-256]** ★★ **N/A — nothing committed.** The decode-wired text build
  measured **14,592 B `3C7BA1519C9D7E69566E946FDB9373B8`**; the tree is back to `f6d08a7`.
  `git diff --stat HEAD -- src/hal/ src/engine/` is **empty**.
- **AC-5 [state-comparable · call graph]** ★★ **N/A after the revert.** With the change applied there
  were exactly three: `res_core.s:264` (miss path), `res_core.s:386` (the `RES_FAULT_DECODE_HIT`
  guard), `res_probe.s:127`. **Now back to one.**
- **AC-6 [suite · byte gates]** ★★ **PASSED.** `★ gates run: pic res cel comp p3b -- all green`
  — including **`res`**, explicitly, which exercises `res_decode`. `hal_sync_check.py` OK ×3;
  `reg_discipline.py` 8 in `mmu_phase.s`; `gen_vm_tables.py --check` **CHECK OK**.
- **AC-7 [state-comparable · memory dump]** ★★★ **NOT TAKEN AS SPECIFIED, and superseded in
  strength.** No dump of the message region was made. ★★ **A person read the words off the screen**,
  which is a stronger observation that the bytes reaching `txt_dispch` were plaintext than the
  XOR-to-printable property would have been. ★ §2P respected either way: no text is recorded here.
- **AC-8 [byte-comparable · runner]** ★★ **PASSED.** Both arms from `p3b_show.ps1` (`-Fault`,
  `-Text`); no hand-typed MAME line.
- **AC-9** One candidate; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §3's grep is above.

```
=== the change, on the LOGIC miss path (res_core.s:349-369), 3 bytes emitted ===
                lda     ,s
                cmpa    #RES_LOGIC
                bne     ro_push_transient
+               jsr     res_decode                  ★ above `ldb 1,s`: res_decode uses B and
                ifdef   ABL_NOCACHE                   res_cache_stash takes the index IN B
                bra     ro_push_transient
                endc
                ldb     1,s
                leas    2,s
                jsr     res_cache_stash

=== and AC-3's fault, on the HIT path (never run) ===
                ldd     res_top
                std     ,x
+               ifdef   RES_FAULT_DECODE_HIT
+               jsr     res_decode
+               endc
                inc     res_depth

=== builds with the change ===
text  (-DP3B_NO_CEL)                 14592 B  3C7BA1519C9D7E69566E946FDB9373B8   2,662 B spare
fault (-DRES_FAULT_DECODE_HIT)       14595 B  AACA21DE64E6A6CD7D68420A4458BC31   built, not run
cel   (default, the p3b gate's)      DID NOT ASSEMBLE:
  src/harness/p3b_probe.s(1039) : ERROR : User Specified: "P3b code has grown into the
    decoded-cel buffer at CP_CEL ($5300, 4,784 B) ..."
  with -DP3B_ACCEPT_OVERRUN:  P3_CODE_END = 5302   CP_CEL = 5300     -> over by 2

=== gates.manifest's p3b row -- the binary that must keep building ===
p3b  src/harness/p3b_probe.s  build/p3b_probe_pk_fresh.bin
     -DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK -DPLANE_WINDOWED -DPRI_PACKED
     integration probe ...  purpose=timing

=== after the revert ===
cel  13925 B  F51FF8482D0B07E49F46B18612D20B06      ★ byte-identical to f6d08a7
res_decode call sites: res_probe.s:127               ★ back to one
★ gates run: pic res cel comp p3b  -- all green
CHECK OK: src/harness/vm_tables.s matches optable.py.
```

**25.2 bundled-artifact grep:** N/A — nothing was built for delivery.

**25.3 operator-runtime-smoke — THE EYE GATE.**

**Invocation** (both arms, `p3b_show.ps1`, RGB, **no `-nothrottle`** [§2U.2]):

```
$env:P3B_ROOM="83"
powershell -File harness\tools\p3b_show.ps1 -Fault -Hold 12      # AC-2, ran first
powershell -File harness\tools\p3b_show.ps1 -Text  -Hold 12      # AC-1
```
Launch path **`poke`**; the image is poked into RAM and PC set from Lua after DECB's OK prompt.

**AC-2, fault arm, first.** `var0=83 vm_cycle=120 vm_badop=$00 res_err=0`, held 12 emulated s.
**Jay's reply opened *"yes"* and then described the wired arm; explicit re-confirmation was
requested and had not arrived. See AC-2 above — not carried over from P6.28d.**

**AC-1, wired arm.** `var0=83 vm_cycle=120 vm_badop=$00 res_err=0`, held 12 emulated s.
**Jay: *"yes the text appreaed was readable and stayed in the sroll box"*.**

★★★ §2P: no screenshot and no message text is committed; Jay's description is the record.

### 6 — Reactive deviations and route accounting

**Deviation 1 — the Python leg was NOT changed.** §4A asked for it; `volread/logic.py` already
decodes at parse and a second decode would re-encrypt (§3, finding 3). ★★★ **Following the
instruction would have introduced the defect the ruling exists to avoid.**

**Deviation 2 — the change was reverted after the eye gate.** ★★ It was applied, carried both arms,
and removed once the cel configuration was shown not to assemble, so the tree stays green. **The eye
gate's result was obtained with the diff in §5 applied**, and that provenance is stated rather than
implied.

**ROUTE ACCOUNTING.** ★★★★ Scope **A** was implemented and reverted. Scope **B** was **half done** —
the fault arm was built and **not run**, and AC-3 is not met. Scope **C** ran and **AC-1 passed**.
★★★★★ **Commit 1 of §9's sequence does not exist**, so **commit 2 (the eye-gate commit) does not
either** — an eye-gate commit whose fix is not in the tree would record a pass for a binary the repo
cannot build. §10's design-spec edit is **not** made for the same reason.

★★★ **I did not take the escape.** Moving the p3b gate to the stripped configuration would have made
everything green and is argued against in §3.3 on `gates.manifest`'s own terms.

### 7 — Uncertainty flags

1. ★★★★★ **AC-2 is unconfirmed for THIS run** (see AC-2). The same arm was confirmed one task ago on
   a **different binary**. ★★ **A lit panel without a confirmed black one is an unvalidated
   positive** [L-113], so AC-1's pass is weaker than it looks until that one word arrives.
2. ★★★★ **AC-3 was never run**, so *"decode on the hit path re-encrypts"* is argued from
   `res_decode`'s in-place XOR and L-66's 3.01 re-binds per cycle — **not demonstrated.** The fault
   binary exists (`AACA21DE…`) and running it is one command once the fix can land.
3. ★★★ **Where the 2 bytes come from is the open question**, and every route is a ruling: free them
   in the cel configuration; re-point the `p3b` gate row and accept AD-96's cost; or split the gate
   into two rows so the cel binary keeps its timing provenance while a `p3b_text` row carries the
   correctness build.
4. ★★ **A decode failure sets `res_err`, which `ro_push_after_stash`'s `clr res_err` then masks.**
   Pre-existing for the stash path, inherited by the decode call, **not changed** — a malformed
   message section would pass silently.
5. ★★ **`$FFA4` ownership** [AD-182] and **`print`'s missing key-wait** [AD-183] remain open, out of
   scope here.

### 8 — Follow-up candidates

- ★★★★★ **The ruling: where the 2 bytes come from** (§7.3).
- ★★★★ **Run AC-3** once the fix lands — the fault binary is built and the command is one line.
- ★★★ **Get AC-2's word** and, if it is black, AC-1 stands as passed.
- ★★ **`res_err` masking** (§7.4).
- ★★ **Correct the three §3 figures in the backlog** — the wired hash is `0574A33A…`; `res_open` is
  in `src/harness/res_core.s`; **there is no `res.py` and the Python leg already decodes.**
  Orchestrator folds (§2D).

### 9 — User interaction during task

Jay adjudicated the eye gate:
- **AC-1:** *"yes the text appreaed was readable and stayed in the sroll box"*
- **AC-2:** the opening *"yes"* above; explicit re-confirmation requested, not yet received.

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-10-a-component-at-zero-headroom-cannot-accept-correctness-fixes`
  — *initiator: executor*. A build at one byte of headroom is not "nearly full", it is **closed**:
  the next correctness fix, whatever it is, cannot land — and the cost is paid by whichever fix
  arrives first, which makes it look like that fix's problem rather than the budget's.

### 11 — Commit

**No source commit.** ★★ The tree is byte-identical to `f6d08a7` and `run_gates.sh all` is green.
**This report is committed alone**, and it carries the verified diff so the fix can be re-applied in
one edit once the 2 bytes are ruled on.
