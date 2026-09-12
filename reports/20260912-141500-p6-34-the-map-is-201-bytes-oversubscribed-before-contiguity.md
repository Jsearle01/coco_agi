## Form B Report — T-P0-089 / P6.34 — The map is 201 bytes oversubscribed before contiguity
**Class:** integration.  wip.  **STOP — §6 trigger 1.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 14:15 (HEAD 73f7a2f, wip). ★★★ **No file was modified this task.** `git status` shows
only the two untracked files that are not mine — `agi-coco3-design-v1_3.md` (Orchestrator's, §2D)
and `coco_agi.code-workspace` (Jay's).

### 1 — Summary
★★★★★ **The parser's `org $E000` IS a stale inheritance, exactly as §4A predicted — and moving it
changes nothing, because it is already out of the font's way.**

The real constraint is arithmetic and it is not close: **the text configuration's resident demand is
24,521 bytes against 24,320 of supply — over by 201 before contiguity is considered at all.** With
contiguity the 2,048-byte font is **355 bytes short in region A** and **956 short in region B**.

★★★★ **So there is no placement that fits, and the remaining route is the 312-byte hunt §1.1
forbids.** Per §6's first trigger — *"that is a ruling, not a workaround"* — I stopped. Nothing was
changed; the suite is green and every artifact is byte-identical to T-P0-088's close.

★★★ **One route does fit and it is not mine to take**: dropping the parser and vocabulary from the
text configuration. §4B.4.

### 2 — Files modified
**None.** This task is measurement and a stop.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| `p3b` | `58AD3C27…` 13,918 B | ✔ ; spare `CP_CEL $5300` − `P3_CODE_END $52F8` = **8 B** |
| `p3b_text` | `63597E4D…` 15,561 B | ✔ |
| `p3b_notick` | `DA798353…` 15,558 B | ✔ |
| `p3b_box` | same binary as `p3b_text` | ✔ , green in the suite |
| untracked | the two known files | ✔ |

**★★★★ Every `org` in `p3b_probe.s`, verbatim — there are exactly two:**
```
line  265:   org     MAP_CODE          ($2000)
line 1460:   org     P3_PARSER_BASE    ($E000)
```
**Current values:** `P3_FONT` `$5C00` · `P3_FONT_BYTES` `$0400` (1,024) · `TEXT_FONT128` defined ·
`MAP_FONT` `$E0B8` · `MAP_RESERVED_END` `$6000`.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — the map enumeration, parser `org` reason answered.** **MET.** §4A.
- **AC-2 [state-comparable] — 256 glyphs staged, `TEXT_FONT128` gone.** ★★★★ **UNMET — BLOCKED.**
  §4A.3 shows no placement exists.
- **AC-3 [state-comparable] — `groza`/`0fb053` spot-check.** ★★★ **UNMET — nothing to certify.**
  Deliberately not run: a census of a compromise that is still in place would report the compromise.
- **AC-4 [byte-comparable] — sizes, hashes, spare and headroom as numbers.** **MET.**

  | row | bytes | SHA-256 (16) | |
  |---|---|---|---|
  | `p3b` | 13,918 | `58AD3C27164BD63F` | **spare vs `CP_CEL`: 8 B** |
  | `p3b_text` / `p3b_box` | 15,561 | `63597E4DE0AB58EF` | **headroom to `P3_FONT $5C00`: 669 B** |
  | `p3b_notick` | 15,558 | `DA79835306CF64AE` | |

- **AC-5 [byte-comparable · gate] — `vm` 9/9, `res` 1,264/1,264.** **MET**, inside the suite run;
  ★★ no producer moved, since nothing was modified.
- **AC-6 [suite] — full suite green.** **MET.** `pic` 45/45 · `res` 1,264/1,264 · `cel` 9,193/9,193 ·
  `comp` 124/124 · `p3b` · `p3b_text` · `p3b_box` · mojibake gate clean.
- **AC-7 [state-comparable] — box still works, fault arm still RED.** **MET by §2T citation** to
  T-P0-088 §4 (AC-2/AC-4/AC-9), whose binaries are byte-identical here. ★★ Not re-run: **a rerun of
  an unchanged binary is not evidence about a change that did not happen** [§2T.2].
- **AC-8 [state-comparable] — `$44` count still ZERO.** **MET**, same citation; and the `p3b_box`
  row inside the suite exercises that path.
- **AC-9 [manifest] — re-baselines.** ★★ **NOT APPLICABLE.** No row moved.
- **AC-10 [eye gate — Jay].** ★★★ **Not offered.** Nothing changed and no high glyph is reachable;
  a gate on an unchanged build would spend Jay's time to confirm T-P0-088.
- **AC-11 [tooling]. MET.** `[hal-sync] OK … 11 files` · `[reg-discipline] 8 register access(es)` ·
  `CHECK OK: vm_tables.s matches optable.py`.
- **AC-12 — candidates.** §10.

### 4A — The probe's map, enumerated fresh

**Resident regions** — those mapped through the glyph blit, which remaps slots 4-6 (`$8000-$DFFF`):

| region | extent | bytes | holds | why there |
|---|---|---|---|---|
| slot 0 | `$0000-$2000` | 8,192 | status, seed + hw stacks, 2 KB VM state, 3 KB DIR tables, `MAP_INPUT` | **fully allocated**; `memmap.inc` |
| **A** = slots 1-2 | `$2000-$6000` | 16,384 | code `org MAP_CODE`, ending `$5963`; the 1 KB font at `$5C00` | the only place code is |
| slot 3 | `$6000-$8000` | 8,192 | `MAP_ARENA_WIN`'s low half | live resource data, not free |
| slots 4-6 | `$8000-$DFFF` | — | **remapped by the blit itself** | cannot host anything resident |
| **B** = slot 7 | `$E000-$FF00` | 7,936 | parser 870 + input buffers 84 + vocabulary 6,966 + vector stubs 16 | |

**4A.1 ★★★★★ Why the parser orgs at `$E000` — answered, and it is an inheritance.**
`p3b_probe.s` states it directly: *"`CP_CEL equ MAP_RESERVED` … p3b's DECODED CEL STAGING lives at
`$5300` and is 4,784 bytes … So the parser's first byte, `par_vocab`, was also the cel buffer's
first byte."*

★★★★★ **`CP_CEL` does not exist in the text configuration.** Verified against the build's own map:
`-DP3B_NO_CEL` strips it, which is that flag's entire purpose. **The constraint that forced the
parser to `$E000` applies only to the cel build, and the text build has carried the placement ever
since without anyone re-examining it** — precisely the "it was already there" §4A was looking for.

**4A.2 ★★★ And correcting it buys nothing.** Moving the parser into A would take 954 bytes *out of
the region the font needs*, leaving 739 instead of 1,693. **The parser at `$E000` is already the
better of the two placements.** ★★ A genuine finding that is not a lever — stated as such rather
than dressed up as one.

**4A.3 ★★★★★ The conflict, named specifically as §4B requires.**

```
resident demand   code 14,691 + parser/bufs 954 + vocabulary 6,828 + font 2,048 = 24,521
resident supply   A 16,384 + B 7,936                                            = 24,320
                                                                        OVER BY    201
```
★★★★ **It does not fit in aggregate**, so no rearrangement can succeed — and contiguity makes it
worse:

| font placed in | free there | short by |
|---|---|---|
| **A** (`$2000-$6000`) | 1,693 | **355** |
| **B**, parser moved out | 1,092 | **956** |

**The two things that want the same addresses are the CODE and the FONT, in region A.** Neither
moves: the code is `org`'d at `$2000` and contiguous, and the font must be resident through a blit
that remaps every other candidate slot. ★★★ **Not "space" — that pair.**

**4A.4 The engine has no such conflict, which is why its layout cannot be borrowed.** `memmap.inc`
puts the vocabulary at `MAP_VOCAB` = `MAP_PRI_SLICE` (`$A000`), *"VM phase only: WORDS.TOK, read in
place"* — **phase-switched, not resident.** That is what frees slot 7 for `MAP_FONT`. The probe
keeps the vocabulary resident at `$E3BA` instead. ★★★★ **Adopting the engine's layout therefore
means implementing phase-switched vocabulary mapping**, which is the MMU layer — §6's fifth trigger,
and a far wider blast radius than this task authorises.

### 4B — Options, priced

1. **355 bytes of code savings** → font in A. ★★★★ **This is §1.1's forbidden byte hunt.** T-P0-084g
   spent a whole task finding 14 bytes honestly.
2. **Phase-switch the vocabulary to `$A000`**, as the engine does → frees B for `MAP_FONT`. ★★★
   Correct long-term and the engine's own answer. **MMU-layer work; §6 trigger.**
3. **Revert the scoped restore** (~288 B refund). ★★★★★ **Declined by Jay** and re-declined by §2 —
   whole-plane re-presentation flickers every sprite on every dismissal.
4. ★★★ **Drop the parser and vocabulary from the TEXT configuration only.** Demand falls to
   code 14,691 + font 2,048; the font lands at `MAP_FONT` in B with **5,872 bytes to spare**. It is
   the one route that fits inside the current map. ★★★★ **Not taken, because it changes what a gate
   row tests**: `parser.s` is included unconditionally and `vm_tests.s` reaches `par_*` for `said()`,
   so `said()` would need stubbing and the text build's VM would differ from the cel build's.
   **"The scope and the invocation of a gate are part of its definition"** — that is a decision to
   surface, not to take inside a map task.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:**
```
★ gates run: pic res cel comp p3b p3b_text p3b_box  -- all green
★ source integrity: clean
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
CHECK OK: src/harness/vm_tables.s matches optable.py.

p3b        13918 B  58AD3C27164BD63F…   spare 8
p3b_text   15561 B  63597E4DE0AB58EF…   headroom 669
p3b_notick 15558 B  DA79835306CF64AE…
```
**25.2 bundled-artifact grep:** N/A — nothing changed.
**25.3 operator-runtime-smoke:** **Not offered** — no change to observe (AC-10).

### 6 — Reactive deviations and route accounting
1. ★★★★★ **Stopped at §6's first trigger.** The map cannot be fixed and the remaining route is the
   forbidden hunt. **No file was modified.**
2. ★★ **AC-3 deliberately not run.** Certifying a removal that did not happen would produce a census
   of the compromise still in place — a green-looking artifact about the wrong thing.
3. ★★★ **ROUTE ACCOUNTING.** I proposed nothing I did not do; the four options in §4B are priced
   and explicitly **not** acted on. §4C and §4D are unreachable given §4A's arithmetic, and are
   reported as such rather than partially attempted.

### 7 — Uncertainty flags

**7.1 ★★★ The 201-byte aggregate overrun is the durable number; 355 is the one that moves.**
355 is region A's shortfall *at this code size*, and code size has moved four times in two tasks.
★★ **Quote 201, or re-measure** — P6.32 §7.2's stale 54 is the precedent for quoting the other one.

**7.2 ★★ The vocabulary is budgeted at its FLOOR (6,828) in §4A.3, not its current 6,966.** Using
the floor is the generous reading — it gives the font 138 more bytes than the build actually leaves
free — **and it still does not fit.** Stated so the arithmetic cannot be accused of pessimism.

**7.3 ★★ Option 4's coverage cost is asserted, not measured.** I did not build it, so "said() would
need stubbing" is read from `vm_tests.s` referencing `par_*`, not from an attempted build.

**7.4 ★ The fold-to-space stays, and is not ambiguous** [§2's requirement]: with 128 glyphs it is
load-bearing, and it retires **only** if 256 glyphs land.

### 8 — Follow-up candidates
1. ★★★★ **Decide among §4B's four options.** ★★★ Option 4 is the only one inside the current map;
   option 2 is the only one that is also the engine's design.
2. ★★★ **The probe's map deserves the same treatment the engine's got** — `memmap.inc` documents
   every region and its floor; `p3b_probe.s` documents placements one incident at a time.
3. ★★ **`err 1`** [P6.32 §7.6], still unexplained.
4. ★ **`p3rb_span`'s lesson as an idiom entry** — "load counts after addresses, never before"
   [T-P0-088 §8.4].

### 9 — User interaction during task
None.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-12-a-constraint-can-outlive-the-configuration-that-caused-it.md`

★★ One only. The aggregate-vs-contiguity distinction is real but reads as ordinary allocation
arithmetic rather than a methodology lesson.

### 11 — Commit
**The report only; no source change.** Pool: `methodology-candidate-pool`, one row under `seeds/AGI/live/`.
