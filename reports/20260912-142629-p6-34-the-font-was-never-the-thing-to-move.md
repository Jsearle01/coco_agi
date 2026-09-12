## Form B Report — T-P0-089 / P6.34 — The font was never the thing to move
**Class:** integration.  wip.  ★★ **Reopened by Jay after an initial stop; see §6.1.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 14:26 (HEAD 9579b43, wip). Clean but for the two untracked files that are not mine —
`agi-coco3-design-v1_3.md` (Orchestrator's, §2D) and `coco_agi.code-workspace` (Jay's).

### 1 — Summary
★★★★★ **The full 256-glyph font is back, and no bytes were saved to do it.** `vm_tables.s` — 626
bytes of pure table — moved out of the crowded region into stack reservation that two existing
measurements had already shown nobody uses. `P3_CODE_END` fell from `$5963` to `$56EB` and the
2,048-byte font landed at `$5800` with **277 bytes spare**.

★★★★ **§4A's prediction was right and did not matter.** The parser's `org $E000` *is* a stale
inheritance — `CP_CEL` forced it and `-DP3B_NO_CEL` strips `CP_CEL` — but moving it takes 954 bytes
out of the region the font needs, so `$E000` was already the better placement.

★★★ **I stopped this task once before Jay reopened it**, and the stop was correct on its own terms
and wrong in its framing. §6.1.

### 2 — Files modified
- `src/harness/p3b_probe.s` — the probe-local seed-stack size; `P3_TABLES_BASE`/`_LIMIT`; the
  relocation with its overrun assert; the 256-glyph font; `TEXT_FONT128` retired; map commentary.
- `harness/tools/p3b_run.lua` — the image is a **run list**, not a code block plus a tail.
- `harness/tools/p3b_show.ps1` — three new symbols.
- `harness/tools/font_glyph_check.py` — NEW. AC-3's certification.
- `harness/tools/gates.manifest` — both moved rows re-baselined.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| `p3b` | `58AD3C27…` 13,918 B | ✔ , spare vs `CP_CEL` = **8 B** |
| `p3b_text` | `63597E4D…` 15,561 B | ✔ |
| `p3b_notick` | `DA798353…` 15,558 B | ✔ |
| `p3b_box` | in `run_gates.sh`, green | ✔ |
| untracked | the two known files | ✔ |

**Every `org` in `p3b_probe.s` — there were exactly two:**
```
line  265:   org     MAP_CODE          ($2000)
line 1460:   org     P3_PARSER_BASE    ($E000)
```
**Values at entry:** `P3_FONT $5C00` · `P3_FONT_BYTES $0400` · `TEXT_FONT128` defined ·
`MAP_FONT $E0B8` · `MAP_RESERVED_END $6000`.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — map enumeration, parser `org` answered.** **MET.** §4A.
- **AC-2 [state-comparable] — 256 glyphs, `TEXT_FONT128` gone.** **MET.** Harness: `font 2048 of
  2048 bytes -> P3_FONT $5800 (256 glyphs)`. ★★ The fold is *compiled out*, verified by `tb_glyph`'s
  absence from the map — not merely by the flag being undefined.
- **AC-3 [state-comparable] — `groza`/`0fb053` spot-check.** **MET.** §4D.
- **AC-4 [byte-comparable] — sizes, hashes, spare, headroom.** **MET.**

  | row | bytes | SHA-256 (16) | |
  |---|---|---|---|
  | `p3b` | 13,918 | `58AD3C27164BD63F` | **spare vs `CP_CEL`: 8 B — unchanged** |
  | `p3b_text` / `p3b_box` | 15,555 | `C4A4346B55330174` | **headroom to `P3_FONT $5800`: 277 B** |
  | `p3b_notick` | 15,552 | `2849A07A738B3DEA` | |

- **AC-5 [byte-comparable · gate] — `vm` 9/9, `res` 1,264/1,264, fresh.** **MET.**
- **AC-6 [suite] — full suite green.** **MET.** `pic` 45/45 · `res` 1,264/1,264 · `cel` 9,193/9,193 ·
  `comp` 124/124 · `p3b` · `p3b_text` · `p3b_box` · mojibake gate.
- **AC-7 [state-comparable] — box works, fault arm RED.** **MET.** `-DTEXT_FAULT_NOTICK` stalls in
  cycle 9, `hal_frame` +1799 and `vm_vms` +0, on the shipped flag sets [L-62].
- **AC-8 [state-comparable] — `$44` still ZERO.** **MET.** 0 inside the rect, 0 in both margins.
- **AC-9 [manifest] — moved rows re-baselined; if `p3b` moves, say why.** **MET**, and ★★★★ **`p3b`
  did NOT move — deliberately.** §4C.
- **AC-10 [eye gate — Jay].** ★★★★ **MET.** Jay, live, RGB: **"looked good"**.
- **AC-11 [tooling]. MET.** `[hal-sync] OK … 11 files` · `[reg-discipline] 8 register access(es)` ·
  `CHECK OK: vm_tables.s matches optable.py`.
- **AC-12 — candidate.** §10.

### 4A — The probe's map, and what actually had the weakest claim

**Resident regions** — those mapped through the glyph blit, which remaps slots 4-6:

| region | extent | reserved | **measured use** |
|---|---|---|---|
| DP / HAL scratch | `$0000-$0020` | 32 | used |
| `MAP_STATUS` | `$0020-$0100` | 224 | used |
| **seed stack** | `$0100-$0400` | 768 | ★ **74 B** — `memmap.inc`: "384 entries of (x,y); **peak measured at 37**" |
| **gap** | `$0400-$0500` | 256 | ★ **declared by nothing** |
| **hw stack** | `$0500-$0800` | 768 | ★ **58 B** — low-water `S=$07C6` |
| VM state | `$0800-$1000` | 2,048 | structural |
| DIR tables | `$1000-$1C00` | 3,072 | 1,794 staged for SpaceQuest-2 |
| `MAP_INPUT` | `$1C00-$2000` | 1,024 | 576 + 96 trace = 352 free |
| **A** = slots 1-2 | `$2000-$6000` | 16,384 | code to `$5963`, font above |
| **B** = slot 7 | `$E000-$FF00` | 7,936 | parser 870 + bufs 84 + vocab 6,966 + stubs 16 |

**4A.1 Why the parser orgs at `$E000` — an inheritance, confirmed.** `CP_CEL equ MAP_RESERVED`
placed the 4,784-byte decoded-cel buffer at `$5300`, and the parser's first byte collided with it.
★★★★ **`CP_CEL` does not exist in the text configuration** — verified against the build's own symbol
map; `-DP3B_NO_CEL` strips it. The constraint has not applied to this build for several tasks.
★★ **And correcting it buys nothing**: moving the parser into A costs A 954 bytes. Reported as a
finding that is not a lever.

**4A.2 ★★★★★ The reframing, which is the actual finding.** Three tasks priced this as *"how much
must the code shrink"* — 54, then 312, then 355, each stale within a task. **Region A contains data
as well as code.** `vm_tables.s` is 626 bytes of `fdb` dispatch entries and `fcb` argument counts,
reached only by address, so where it lives is free to choose. **Moving it drops `P3_CODE_END` by
more than any of those three figures.**

★★★ **Both justifying measurements already existed in the tree**: the engine's own seed-stack note
("peak measured at 37") and this probe's stack low-water instrument, added two tasks ago for Jay's
interrupt-safety question. Nothing new had to be measured.

### 4B — What was done

`STACK_BASE`/`STACK_TOP` were always **probe-local equs** that happened to take the engine's values.
The probe now sets `STACK_TOP = MAP_SEEDSTACK+256` — **128 entries against a measured peak of 37** —
and `vm_tables.s` is `org`'d to `$0200`, ending `$0472` against a `$0480` limit that leaves `$0480-
$0500` as margin below the hardware stack. ★★★★ **`memmap.inc` is untouched**, so §6's fourth
trigger was never approached.

★★ **The overflow is loud, not silent**: `pic_fill`'s `ff_push` compares against `STACK_TOP-2` and
halts — *"wrapping the stack would overwrite code and produce a wrong picture with no attributable
cause"*.

### 4C — ★★★★ Scoped to the text configuration, and that was a decision

Relocating unconditionally **changed `p3b`'s hash** — same 13,918 bytes, bytes moved, `P3_CODE_END`
`$52F8`→`$5086`. That row is `purpose=timing`, and **AD-96 is the standing lesson about quoting a
figure whose producer has moved.** The cel build has no font and no font pressure, so it keeps the
engine's seed stack and its byte identity. ★★ Measured both ways before choosing.

### 4D — The compromise is gone, certified on the titles that paid for it

`font_glyph_check.py` reads **the staged font file**, not the build flags, because "the fold is
compiled out" is a statement about the build and the question is whether those codepoints *render*.

```
cp     staged?    non-blank != space  set pixels
128    yes        yes       yes       26
129    yes        yes       yes       22
130    yes        yes       yes       23
131    yes        yes       yes       31
132    yes        yes       yes       25
133    yes        yes       yes       24
134    yes        yes       yes       25
135    yes        yes       yes       17
★ every codepoint checked has a distinct, non-blank glyph inside the staged font.
```
★★★★ **And the same check against the old 1,024-byte staging reports them OUTSIDE the font** —
the instrument is shown able to fail [§2W]. ★★ A glyph that were blank, or equal to space, would
render exactly as the fold did and the fix would have changed nothing visible; that is what the
`!= space` column exists to catch.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:**
```
poked  1154 B -> $2000  code
poked   626 B -> $0200  vm_tables (relocated)
poked 12905 B -> $2482  code
poked   870 B -> $E000  parser (org'd)
program 15555 bytes in 4 run(s)
font 2048 of 2048 bytes -> P3_FONT $5800 (256 glyphs)
RED ($44) bytes still in the visible plane inside the rect: 0

=== AC-2 SUMMARY ===   all nine titles PASS
byte-identical resources: 1264 across 10 (title, volume) sweeps ; all sweeps clean
★ gates run: pic res cel comp p3b p3b_text p3b_box  -- all green
★ source integrity: clean

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
CHECK OK: src/harness/vm_tables.s matches optable.py.
```
**25.2 bundled-artifact grep:** N/A — probe hashes in AC-4.
**25.3 operator-runtime-smoke:** ★★★★ **PASSED — Jay, RGB: "looked good".**

### 6 — Reactive deviations and route accounting

**6.1 ★★★★★ I stopped this task, and Jay reopened it with one question.** My stop invoked §6's first
trigger and the arithmetic behind it was correct: 24,521 demand against 24,320 supply. ★★★ **But the
demand figure took the stacks at their RESERVED size, and 1,660 bytes of that reservation is slack
two existing measurements had already priced.** I enumerated the map and then asked only "where can
the font go", never "what else is in the way". ★★ Jay's question — *"what lies below the code"* — is
the whole task.

**6.2 §6's other triggers were not reached.** `memmap.inc` untouched; `MAP_RESERVED`'s 3,072 floor
untouched; no `src/hal/` or `SHARED` file; the scoped restore untouched; and **no byte hunt** — the
relocation removes nothing.

**6.3 ROUTE ACCOUNTING.** The four options priced in the stop report: option 1 (byte hunt) and
option 3 (revert the restore) remain declined; option 2 (phase-switch the vocabulary) remains the
engine's long-term answer and is **not** what I did; **option 4 (drop the parser from the text
build) was NOT taken** — the relocation makes it unnecessary, so the gate keeps its parser coverage.

### 7 — Uncertainty flags

**7.1 ★★★★ The seed-stack peak of 37 is measured on a corpus this probe does not run.** It comes
from the renderer gate's 45 pictures, and that gate runs `pic_probe`, whose `STACK_TOP` is untouched.
**The shrunk stack is exercised only by the rooms `p3b_text` and `p3b_box` render** — room 83 and
room 101. ★★★ So the margin is 3.5× against a figure measured elsewhere. The guard halts loudly, and
`p3b` keeps the full stack, but **the coverage claim is weaker than the number suggests** [L-86].

**7.2 ★★ The tables end at `$0472` against a `$0480` limit — 14 bytes.** `gen_vm_tables.py` regenerates
that file from the reference, so a future opcode could overrun it. The assert fires at assemble time
with a message naming the fix, which is the intended failure.

**7.3 ★★ `$0400-$0500` is now data, not margin.** It was undeclared space between the seed stack's
old ceiling and the hardware stack's usable floor. The hardware stack's low-water is `S=$07C6`, 710
bytes clear, so the margin it provided was never the binding one — **but it was a margin and it is
now spent.**

**7.4 ★ `err 1`** [P6.32 §7.6], still unexplained, still out of scope.

### 8 — Follow-up candidates
1. ★★★ **Widen the seed-stack evidence** (§7.1): either run the text configuration over more rooms,
   or instrument its fill depth the way `pic_probe` measured 37.
2. ★★★ **The probe's map deserves `memmap.inc`'s treatment** — every region, its floor, and its
   measured use in one place. This task had to reconstruct it from incident commentary.
3. ★★ **`err 1`** (§7.4).
4. ★ **"Load counts after addresses, never before"** as an idiom entry [T-P0-088 §8.4].

### 9 — User interaction during task
Jay reopened the task with **"what lies below the code"**, which is §4A.2's finding, and confirmed
AC-10 with **"looked good"**.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-12-when-a-thing-will-not-fit-ask-what-else-could-move.md`

★★ It credits the reviewer: the reframing came from one question, against three tasks of
increasingly precise answers to the wrong one.

### 11 — Commit
`9579b43` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `3de055d`, one row under `seeds/AGI/live/`.
