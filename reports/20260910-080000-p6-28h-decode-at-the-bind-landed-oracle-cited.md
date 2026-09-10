## Form B Report — P6.28h (T-P0-084h) — the decode lands at the bind; the oracle says so
**Class:** integration (§4A) — **all ten ACs met. The fix is in the tree.**  wip.

★★★★★ **Landed, after five tasks held.** The LOGIC decode sits at `vm_bind_logic` on a fresh open,
`res_open` still returns Sierra's raw bytes, and **the `res` gate is 1,264/1,264 — unchanged**, which
is the single number this task was defined to preserve.

★★★★★ **§4A turned the ruling into a citation.** At the pin `9d9b9e93` the oracle decrypts inside
`decodeLogic()`, above the raw fetch, guarded by a fresh-load test. **Route (a) would have invented a
contract the oracle does not have.**

★★★★ **Jay, on the eye gate:** ***"kings quest title scene, black area, lines scrolled up, readable,
then mame closed"*** — and *"lines scrolled up"* is **AD-156's prediction observed directly**: the
panel redrawing on its cycle.

---

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-084h dispatch receipt (HEAD `00577d6`, wip). At report time HEAD `1008d9d`.

---

### §3 — Pre-dispatch grep (C-13), verbatim — all four extras matched

```
=== coco_agi === 00577d6 wip   ?? coco_agi.code-workspace
=== POP3_port === 104b197      === karateka_coco3 === 29f8f0a
[hal-sync] OK x3 (11 files compared)
[reg-discipline] 8 in src/engine/mmu_phase.s -- $FFA5 $FFA6
CHECK OK: src/harness/vm_tables.s matches optable.py.

(1) res gate:      1264 / 1264 requested (100.00%)        ★ the number to preserve
(2) res_decode:    res_probe.s:127                        ★ exactly one
(3) p3b row:       13925 B  F51FF8482D0B07E49F46B18612D20B06
(4) vm_probe.bin:   9660 B  EC8991A52A09C27BD502E4A480DB75C1   ★ first time recorded
```

★★ **§2T, P6.28g §3's caveat carried forward unchanged.** Siblings at **the same refs P6.28g §3
recorded**, read at their **`wip` working trees**, not a public ref (§2S). ★ **No stop fired.**

---

### 1 — Summary

The oracle check supported the ruling, the implementation cost 7 bytes, and every gate held.

### 2 — Files modified (`1008d9d`)

`src/harness/res_core.s` (+2 emitted bytes) · `src/harness/vm_run.s` (+5) ·
`src/harness/p3b_probe.s` (−14) · `harness/tools/gates.manifest` (two re-baselines) ·
`harness/tools/run_gates.sh` (`p3b_text` block) · `harness/tools/p3b_show.ps1` (`-DecodeFault`).

★★ **Nothing in `src/hal/` or any `SHARED` file. No gate's reference data was edited.**

### 3 — Reasoning

**3.1 ★★★★★ §4A — the oracle, quoted at the pin.**

`engines/agi/agi.cpp`, `RESOURCETYPE_LOGIC` case:

```
488   case RESOURCETYPE_LOGIC:
489       if (~_game.dirLogic[resourceNr].flags & RES_LOADED) {
490           unloadResource(RESOURCETYPE_LOGIC, resourceNr);
493           data = _loader->loadVolumeResource(&_game.dirLogic[resourceNr]);
495           _game.logics[resourceNr].data = data;
497           // uncompressed logic files need to be decrypted
500               ec = decodeLogic(resourceNr);
505       }
```

`engines/agi/logic.cpp`, inside `decodeLogic()`:

```
53    // decrypt the message strings if the logic was not compressed
54    // and the logic has messages.
55    if ((~dirLogic.flags & RES_COMPRESSED) && messageCount > 0) {
56        decrypt(logic.data + stringsPos, stringsSize);
57    }
```

★★★★ **A tree-wide search for `decrypt(` finds exactly three call sites: `logic.cpp:56` (LOGIC),
`objects.cpp:40` (OBJECT), and the definition at `global.cpp:340`. There is none in the loader.**

★★★★★ **Three facts follow, and all three favour (b):**
1. **`loadVolumeResource()` returns undecrypted bytes** — decryption is not in the fetch path. That
   is `res_open`'s contract, unchanged.
2. **`decodeLogic()` is called from the LOGIC load case, above the fetch** — route (b)'s placement.
3. **It is guarded by `if (~flags & RES_LOADED)` — only on a fresh load.** A cached logic skips the
   whole block. **That is "on a fresh open only", in the oracle's own words.**

★★★ **Authority: §2 tier 3 — ScummVM, best secondary evidence, not the original.** ★★ **Per §2.1,
stated as ScummVM's STRUCTURE, not as a fact about Sierra's interpreter.** ★★★★ **What is structural
rather than a normalisation is the ONCE-per-load part: the decrypt is in place, so any
implementation that runs it twice re-encrypts. That constraint belongs to the data format, not to
ScummVM's taste** — and it is the same constraint AD-184 derived independently on our side.

**3.2 ★★★★★ Our own oracle instrumentation corroborates the seam — and explains P6.28g.**

`agi.cpp:452-461`, P1.1's dump:

> *"the dump is taken at exactly one point: immediately after `loadVolumeResource()` returns and
> BEFORE any decode. ★ FOR LOGIC THAT ORDERING IS NOT A DETAIL, IT IS THE WHOLE THING.
> `decodeLogic()` DECRYPTS THE MESSAGE STRINGS IN PLACE. Dumping after it would compare our
> pre-decode bytes against their post-decode bytes and fail everywhere."*

★★★★★ **That is why `tools/volread/`'s reference is raw, and therefore why the `res` gate compares
raw.** The alignment was established deliberately four phases ago. ★★★ **P6.28g's 959/1,264 was not a
mystery and not a regression — it was decoding on the wrong side of a seam this project had already
chosen, and the gate said so.**

**3.3 ★★★★★ Carry carries the hit/miss bit — 7 bytes, not 17.**

`res_open`'s hit path sets C; the miss path's `clr res_err` clears it for free; `vm_bind_logic`
tests `bcs`. ★★★★ **A memory flag is ~17 bytes across the two files and the cel configuration had 15
to spend.** ★★★ **Carry rather than Z, and that is forced**: the caller's `lda res_err` between the
return and the test destroys Z and N — **`lda` does not touch C**. ★★ **It is this file's existing
convention, not a new one**: `res_cache_find` already returns hit/miss in Z (`orcc #$04` at
`rcf_hit`).

**3.4 ★★★ The saving, verified at both ends before removal.**

`p3_zero_timers`, 14 bytes. The probe's header has called `P3_T_VM..P3_T_RENDER` dead since P3b.1;
**a comment is not a producer** [AD-95], so: the guest's only reference to any `P3_T_*` was the `ldx`
**inside the clear itself**, and `p3b_run.lua:43` defines all five addresses and **never reads one**.
★★ No observer, so no behaviour to change. The equs are kept — they document that
`MAP_STATUS+8..+27` is reserved and unused.

**3.5 ★★ §2H's three checks.**

1. **A second mechanism for another object class?** ★★★ Yes, and §4A settled which one governs:
   **decryption is bound to LOADING A LOGIC, not to FETCHING BYTES.** Two plausible homes; the
   oracle names one.
2. **The calling routine.** `decodeLogic`'s caller is `loadResource`'s LOGIC case **inside the
   `RES_LOADED` guard** — the enclosing routine carries the once-per-load scope, which is the whole
   correctness argument. Reading `decodeLogic` alone would have missed it.
3. **Grep the reports.** P6.28c (1 byte), P6.28d (missing call), P6.28e (3 bytes), P6.28f (a row
   cannot fix source), P6.28g (contract). ★★★ **Six reports; this one closes it, and the thing that
   closed it was a citation nobody had gone to fetch.**

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it. AC-8 is eye-gated by Jay; nothing else is.**

- **AC-1 [citation · oracle]** ★★★★★ **MET.** §3.1: `agi.cpp:488-505`, `logic.cpp:53-57` at
  `9d9b9e93`, quoted, tier 3 named, §2.1 distinction stated. **It supported (b); had it not, §4A's
  stop would have cost the task nothing.**
- **AC-2 [byte-comparable · gate]** ★★★★★ **MET — `res` 1,264/1,264 (100.00%), UNCHANGED.**
- **AC-3 [state-comparable · gate]** ★★★★★ **MET.** `vm` **9/9 titles PASS**, byte-identical on
  every compared cycle, on the **new** `vm_probe.bin` — Kingquest1/2/3, SpaceQuest-1/2,
  PoliceQuest1, larry1, BlackCauldron, MixedUpMotherGoose. ★★ **P6.28g §7.2 predicted this; it is
  now shown.**
- **AC-4 [state-comparable · fault injection]** ★★★★ **MET at the new site, both arms on the
  shipped build** [L-62]: clean **16 of 16 printable — DECODED**; fault **18 of 32 — NOT DECODED**.
  ★★★ **The replacement fault is stated:** `-DRES_FAULT_DECODE_HIT` now drops `vm_bind_logic`'s
  `bcs`, so the decode runs on **every** bind including cached ones — the same in-place
  re-encryption as the old decode-on-hit arm, moved with the decode. Cost signal 22.36 s → 36.38 s.
- **AC-5 [byte-comparable · assembler]** ★★★ **MET.** `p3b` **13,918 B `58AD3C27164BD63F…`**,
  `P3_CODE_END $52F8` vs `CP_CEL $5300` — **8 bytes spare**. `p3b_text` **14,582 B
  `FA7F2FB9CD542B58…`**.
- **AC-6 [suite]** ★★★ **MET.** `★ gates run: pic res cel comp p3b p3b_text -- all green` —
  res 1,264/1,264, cel 9,193/9,193, comp 124/124, both p3b rows. **`p3b_text` run, not
  manifest-only, for the first time.**
- **AC-7 [byte-comparable · manifest]** ★★★ **MET — both re-baselines with retirement lines.**
  `p3b`: retired `F51FF848…` 13,925 B → `58AD3C27…` 13,918 B. `vm_timed`: producer
  `EC8991A5…` 9,660 B → `771F147D…` 9,667 B, **P6.10's medians RETIRED**.
- **AC-8 [eye gate — Jay]** ★★★★★ **PASSED.** ***"kings quest title scene, black area, lines
  scrolled up, readable, then mame closed."*** ★★ **Valid this time: the build is in the tree.**
- **AC-9 [tooling]** ★★ **MET.** `hal_sync_check.py` OK ×3; `reg_discipline.py` **8 in
  `mmu_phase.s`, unchanged** — the new code touches no register; `gen_vm_tables.py --check` OK.
- **AC-10** One candidate; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §3's grep and §3.1's citation are above.

```
=== the change, 7 emitted bytes ===
res_core.s, hit path:        clr res_err / +orcc #$01 / rts
vm_run.s, vm_bind_logic:     lda res_err / lbne vm_res_fail
                            +ifndef RES_FAULT_DECODE_HIT
                            +  bcs vbl_nodec
                            +endc
                            +jsr res_decode
                            +vbl_nodec:
                             ldx res_base
p3b_probe.s:                 -p3_zero_timers and its call        (-14)

=== artifacts ===
p3b       13918 B  58AD3C27164BD63FDE17E18041160B28   P3_CODE_END $52F8, CP_CEL $5300 -> 8 spare
p3b_text  14582 B  FA7F2FB9CD542B58ED3D4E75D365C43E
vm_probe   9667 B  771F147DE2A54688ABFA8823784323DB

=== AC-2 ===
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)

=== AC-3 ===
Kingquest1 PASS  Kingquest2 PASS  Kingquest3 PASS  SpaceQuest-1 PASS  SpaceQuest-2 PASS
PoliceQuest1 PASS  larry1 PASS  BlackCauldron PASS  MixedUpMotherGoose PASS

=== AC-4, both arms, new build ===
CLEAN  120 cycles in 22.3621 emulated s   P3_PBUF $1C00: 16 of 16 printable -- DECODED
FAULT  120 cycles in 36.3802 emulated s   P3_PBUF $1C00: 18 of 32 printable -- NOT DECODED

=== AC-6 ===
resources byte-identical: 1264 / 1264 (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ p3b headless: 160 cycles, no stall      ★ p3b headless: 120 cycles, no stall
★ gates run: pic res cel comp p3b p3b_text  -- all green
[reg-discipline] 8 in src/engine/mmu_phase.s     CHECK OK: vm_tables.s matches optable.py.
```

**25.2 bundled-artifact grep:** N/A — harness binaries.

**25.3 operator-runtime-smoke — THE EYE GATE.**

`p3b_show.ps1 -Text -Hold 12`, `P3B_ROOM=83`, RGB, **no `-nothrottle`** [§2U.2]. Launch path
**`poke`** — image poked into RAM and PC set from Lua after DECB's OK prompt. **Not `live-disk`.**
Guest state at the hold: `var0=83 vm_cycle=120 vm_badop=$00 res_err=0`, and the guest's own
buffer **16 of 16 printable — DECODED**.

**Jay: *"kings quest title scene, black area, lines scrolled up, readable, then mame closed."***

★★★ *"lines scrolled up"* is **AD-156's prediction observed** — the panel redraws on a cycle, which
is why the dispatch has asked for a full cycle since P6.28d. ★★ §2P: no screenshot, no message text;
Jay's words and a printable **count** are the record.

### 6 — Reactive deviations and route accounting

**Deviation 1 — ★★★★★ §9's design-spec edit was NOT made, and §2D is why.** The dispatch asks me to
edit `agi-coco3-design-v1.1.md`. **§2D names the design spec explicitly as a doc whose body Clyde
does not edit** — *"findings surface in Clyde's reports; the Orchestrator folds them into the text;
Clyde commits the Orchestrator-provided result"* — and **§8 makes CLAUDE.md invariants take
precedence over task-contract instructions where they conflict.** ★★★ **The exact proposed text is
in §8 below for folding.** The file is present in the tree, so this is a choice, not an inability.

**Deviation 2 — `vm_timed`'s medians retired rather than re-measured.** §4D permitted either. A
`VM_TIMED` free-run publishes no per-cycle trace, so `vm_run.ps1`'s diff reports `FAIL` on it and a
median needs a driver path this task did not work out. ★★ **A retired figure with a named retiring
task beats a fresh figure nobody can reproduce.** Recorded as a follow-up.

**ROUTE ACCOUNTING.** ★★★★ **§4A, §4B, §4C and §4D all complete**, except §4C's design-spec third,
held under §2D. **Nothing was left implied**: both re-baselines carry retirement lines, `p3b_text`
is in the suite, and the fault arm was moved rather than dropped.

★★★ **No gate reference data was edited** — trigger 1's last condition. The `res` gate passes on its
original reference because `res_open`'s contract never moved.

### 7 — Uncertainty flags

1. ★★★ **`vm_timed`'s medians are retired and unreplaced.** The VM now decrypts on a fresh LOGIC
   bind, so it does measurably more work than the retired figures describe; **how much is
   unmeasured.**
2. ★★★ **The carry convention is a returned CPU flag across a `jsr`**, which is correct here (`lda`
   does not touch C, and `res_cache_find` already does this with Z) but is **fragile to a future
   edit inserting a C-clobbering instruction** between `res_open` and the `bcs`. Asserted in
   comments at both ends; **not enforced by anything mechanical.**
3. ★★ **8 bytes spare** in the cel configuration. Better than 1, still the tightest thing in the
   tree.
4. ★★ **`res_probe.s:127`'s explicit decode is untouched and now benign** — under (b) it decodes a
   resource `res_open` did not, which is what its mode 5 is for. **It would double-decode under (a);
   (a) is not taken.**
5. ★★ **`res_err` masking** (P6.28e §7.4), **`$FFA4`** [AD-182], **`print`'s key-wait** [AD-183] —
   untouched, per §10.

### 8 — Follow-up candidates

★★★★★ **The design-spec edit, for the Orchestrator to fold** (§6 Deviation 1). Proposed text:

> **§3.x opcode table.** All nine text opcodes — `$65 print`, `$66 print.v`, `$67 display`,
> `$68 display.v`, `$69 clear.lines`, `$6C set.cursor.char`, `$6D set.text.attribute`,
> `$70 status.line.on`, `$71 status.line.off` — are **wired and verified by eye gate** [AD-187].
> `display`/`display.v` and `print`/`print.v` have full implementations; the other five are
> minimal stubs, none of which is needed to reach the scroll panel.
> **`display`'s precondition** is a flat 24 KB framebuffer window: three visible-plane blocks in
> MMU slots 4–6 (`$8000-$DFFF`), covering character rows 0–18 with no slice straddle. Substitution
> runs before the window swap, because the message text lives in the arena and slot 4 is the arena
> window's high half.
> **LOGIC message decryption is bound to the BIND, not the fetch**: `res_open` returns Sierra's raw
> bytes and `vm_bind_logic` decrypts on a fresh open only, signalled by carry. This follows the
> oracle at `9d9b9e93` — `agi.cpp:489-500` guards `decodeLogic()` with `~flags & RES_LOADED`, and
> `logic.cpp:56` is the engine's only LOGIC decrypt. Tier 3; stated as ScummVM's structure per §2.1.
> **The text gate runs the `p3b_text` configuration** (cel/composite stripped); `p3b` remains the
> timing row.

- ★★★ **Re-measure `vm_timed`** (§7.1) and give the row live figures again.
- ★★ **Decompose the text configuration** (P6.28g §8) — `size_decompose.py` is in the tree.

### 9 — User interaction during task

Jay adjudicated the eye gate: ***"kings quest title scene, black area, lines scrolled up, readable,
then mame closed."***

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-10-go-and-read-the-reference-before-arguing-about-placement`
  — *initiator: executor*. Five tasks argued where a decryption call belonged — bytes, gate rows,
  contracts — and the question was settled in minutes by reading the reference implementation, which
  binds the decrypt to loading a resource and guards it with a fresh-load test. **The citation was
  available the whole time and nobody went to get it.**

### 11 — Commit

`1008d9d` — route (b), both re-baselines, `p3b_text` in the suite — pushed to origin/wip before this
report.
