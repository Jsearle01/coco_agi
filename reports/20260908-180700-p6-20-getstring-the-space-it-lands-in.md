## Form B Report — T-P0-076 (P6.20) — `get.string`, the input line, and the space it lands in
**Class:** build.  wip.  ★★★★★ **STOPPED AT §8 TRIGGER 1 — the space, before the code.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08T18:07:41-04:00 (HEAD cee2722, wip). Working tree carries this task's new tools only.
`coco_agi.code-workspace` is untracked editor state and is NOT staged.

---

### §5 — Pre-dispatch grep (verbatim, run not asserted)

```
=== coco_agi ===      cee2722  wip   (clean but for this task's untracked tools)
=== POP3_port ===     104b197  wip   no dirty tracked files
=== karateka_coco3 == 29f8f0a  wip   M harness/smoke/last-run.log only

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi   (from POP)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi        (from Karateka)

★ gates run: pic res cel comp p3b  -- all green
  per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
  resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
  cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
  ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ TEXT GATE PASS over all 9 titles        (the reference leg)
★ PORT GATE PASS over all 9 titles        (the 6809 leg)
VM gate no-input arm: 9/9 PASS.  VM parser arm: 9/9 PASS, 6 of 9 fed input.

[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   8   $FFA5 $FFA6
```

★ **§2T:** P6.19 §0 recorded POP `104b197` and Karateka `29f8f0a`; **both unchanged and measured
again this task**, tracked source clean in both.

**Flag sets, enumerated and diffed** [L-77] — no new arm was built this task; the required set is
P6.19's and every member was rebuilt and re-run:

| build | flags | bytes |
|---|---|---|
| `text_probe.bin` | *(none)* | 1,714 |
| `text_probe.bin` — fault arm 1 | `-DTXT_FAULT_WRAP` | 1,714 |
| `text_probe.bin` — fault arm 2 | `-DTXT_FAULT_PRINTF` | 1,717 |
| `text_show.bin` | *(none)* + `content/agi_palette.s` | 1,644 |
| `parser_probe.bin` | *(none)* | rebuilt clean |

**`MAP_RESERVED` occupancy at HEAD — bytes, not a percentage:**

```
  region                     3328 B  ($5300-$6000, floor 3072 on the SIZE)
  parser                      954 B
  text engine                1411 B   [P6.19, measured]
  text substitution buffer    768 B
  FREE                        195 B   ★ and sound is unwritten
```

★★ **What sound is estimated to need:** §5.1's stub is a completion flag and no audio. **Nobody has
estimated it**, and `MAP_RESERVED_MIN`'s own note says the floor is "deliberately arbitrary … the
point is not to model them but to make the next reduction impossible to take silently." **So I have
no figure to offer and will not invent one** — the honest statement is that 195 B is what remains
for a subsystem nobody has sized.

**Does patch 0010 cover `get.string`'s draws?** — **Partly, and the gap is one call.** Every
character the player types is echoed through `TextMgr::displayCharacter` → `_gfx->drawCharacter`
(text.cpp:333), and patch 0010's log sits on `drawCharacter` — so **the printable echo and the
cursor character are already covered**. ★★★ **Backspace is not**: `displayCharacter(0x08)` takes the
branch at text.cpp:313-322 and calls `clearBlock(...)`, a graphics call with no `drawCharacter` in
it, so it produces **no log entry at all**. Extending patch 0010 means one `oracleLogText` call in
`clearBlock`, the same shape as the three already there — **a bounded change, so §8 trigger 2 does
not fire.**

---

### 1 — Summary
★★★★★ **`get.string` plus an input line does not fit what `MAP_RESERVED` has left, and the DATA
alone settles it before a single instruction is written: 572 bytes of tables and buffers against
195 free — 2.9× over with zero bytes of code.** Moving the string table to its natural home in the
`MAP_VMSTATE` tail (576 B free, measured from memmap.inc's own constants) does not rescue it: what
remains still needs ~562 B against 195. **Stopped at §8 trigger 1 without building.** Everything
the dispatch asks that does not consume the contested resource is delivered: the full grep, the
measured space accounting, and AC-4's answer about patch 0010. The string table's real size was
measured rather than inherited — **13 slots, not the oracle's 25** — across 889 logics at 100% walk
coverage.

---

### 2 — Files modified
- `harness/tools/string_census.py` — NEW. Walks every logic of every gate title recording which
  string slots are written and read. **Measures the table instead of inheriting 1,000 bytes.**
- `harness/tools/getstring_space.py` — NEW. AC-3's accounting, reproducible: measured data rows,
  labelled code estimates, and the verdict under both placements.

★ **No engine or probe source was changed.** That is the stop.

---

### 3 — Reasoning

**A. The string table is the row that decides it, and it was measured.** [authority: measurement]
The oracle declares `strings[MAX_STRINGS + 1][MAX_STRINGLEN]` = **25 × 40 = 1,000 B** (agi.h).
Inheriting that would repeat what `text_bufmax.py` already disproved once — the oracle's 2,000-byte
wrap buffer turned out to be 4× the corpus's real maximum. `string_census.py` walks the bytecode of
**889 logics across nine titles at 100% coverage**, recording every `set.string` / `get.string` /
`word.to.string` slot written and every `%s<n>` slot read:

| title | max write | max read | slots |
|---|---|---|---|
| Kingquest1 | 0 | — | 1 |
| Kingquest2 | 4 | 4 | 5 |
| Kingquest3 | 2 | — | 3 |
| SpaceQuest-1 | 4 | 4 | 5 |
| SpaceQuest-2 | 4 | 4 | 5 |
| PoliceQuest1 | 12 | 9 | 13 |
| larry1 | 12 | 11 | 13 |
| BlackCauldron | 0 | — | 1 |
| MixedUpMotherGoose | 6 | 6 | 7 |

★ **13 slots × 40 = 520 B**, not 1,000. The writers and readers corroborate each other per title,
which is what makes the number believable rather than merely small.

**B. The verdict, and why it does not rest on an estimate.** [authority: measurement]

```
  DATA (measured / read at the pin)
    string table, 13 slots x 40    520 B
    _inputString[42]                42 B   [text.h at the pin]
    edit state, 9 fields            10 B   [enumerated in the tool]
    DATA SUBTOTAL                  572 B     against 195 free  ->  2.9x over
  CODE (ESTIMATED, each anchored on a measured routine in text.s)
    CODE SUBTOTAL                 ~510 B
  TOTAL                          ~1082 B     against 195 free
```

★★★★★ **Even with zero bytes of code the data does not fit.** The code estimates are labelled as
estimates and anchored (`txt_dispch` 44 B, `txt_dec3` 46 B, `txt_digits` 59 B, `txt_blit` 156 B,
all measured from `build/text_probe.map`) — but they are deliberately not load-bearing.

**C. The one placement worth naming, offered rather than taken.** [authority: memmap.inc]
★★★ **The string table is VM state, not text-engine state**, and `MAP_VMSTATE`'s tail is free:
`MAP_VM_OBJ` at `$0B20` holds 16 × 42 = 672 B ending at `$0DC0`, and `MAP_DIRS` begins at `$1000` —
**576 bytes**, computed from that file's own constants. A 520 B table fits there with 56 to spare.
★★★★ **It still does not rescue the task**: `MAP_RESERVED` would then need 42 + 10 + ~510 = ~562 B
against 195, **the same 2.9× over.** I am naming it because it is the obvious first question and
the answer is "yes, and it is not enough" — but it is a **map change and therefore Jay's** (§8).

**D. What is already ruled out, checked rather than assumed.** M-48's 455 bytes are spent — all
four dispatch tables are sized to their opcode spaces [P6.12]. `MAP_CODE` has 5 bytes and p3b's own
`ifgt P3_CODE_END-MAP_CODE_END` assertion is what holds it there. `MAP_FONT` stays.

**E. §2H's three checks on `get.string`.** (1) *A second mechanism?* Yes — `stringEdit`'s echo is
**not** the same path as `drawMessageBox`'s: it goes through `displayCharacter`, which has three
arms (backspace, CR/LF, printable), and only the third reaches `drawCharacter`. Reading only the
printable arm is what would have made patch 0010 look complete. (2) *Name the caller.* `stringEdit`
is called by `cmdGetString` **and** by `cmdGetNum` and the save/restore description prompt, each
with a different `stringMaxLen` — 30 for `askForSaveGameDescription`, which the RTL branch tests
explicitly (text.cpp:959). (3) *Grep the reports.* P6.19 §4 AC-9 recorded `get.string`'s
requirements from `cmdGetString`; this report does not contradict it and adds the echo path, which
P6.19 did not reach.

**F. §2S refs.** POP `104b197` wip, Karateka `29f8f0a` wip, both measured this task. ScummVM at the
pin `9d9b9e93`, with P6.18's sweep amendment in the working tree.

---

### 4 — Verification (AC-by-AC)

- **AC-1** [class: **eye-gated**] — ★★★★★ **NOT REACHED, and not "pending Jay" either.** Both halves
  of it — the scroll panel filling, and a typed command echoing — depend on work the stop blocks:
  the panel needs `display`/`display.v` (still `vm_op_modelled`) and the echo needs the input line.
  ★★★ **The prediction from P6.19 §9 stands unrefuted and untested**: white lettering at rows 6–18,
  columns 12–28. §8 trigger 4 has not fired because the test has not run.
- **AC-2** [class: byte-comparable] — every gate RUN, verbatim in §5 and §5's block. `hal_sync`
  green in all three repos; `reg_discipline` unchanged at 8 accesses, all `mmu_phase.s`'s.
- **AC-3** [class: state-comparable] — ★★★★★ **DELIVERED, AND IT IS THE STOP.** §3.B. Reproducible
  via `python harness/tools/getstring_space.py`; verbatim in §5 of the evidence block.
- **AC-4** [class: state-comparable] — ★★★★ **DELIVERED as its second branch.** Patch 0010 covers
  the printable echo and the cursor character (both reach `drawCharacter`); **it does not cover
  backspace**, which goes through `clearBlock` and logs nothing. Extending it is **one
  `oracleLogText` call in `clearBlock`**, the same shape as the three already present — bounded, so
  trigger 2 does not fire. ★★ **The reference implementation was NOT written**: it is the step after
  AC-3, and AC-3 stopped.
- **AC-5** [class: byte-comparable] — **NOT REACHED** (the port). Blocked by AC-3.
- **AC-6** [class: byte-comparable] — **NOT REACHED** (its fault). Blocked by AC-3.
- **AC-7** [class: byte-comparable] — **NOT REACHED** (the input line). Blocked by AC-3. ★ No key
  was found unreachable, because no key was read: §8 trigger 3 has not fired and is untested.
- **AC-8** [class: state-comparable] — **NOT REACHED** (the input line's cost). ★★ What P6.19
  measured still stands and bears on it: the glyph blitter is **2,970 cycles/glyph**, so a
  40-column line redraw is ~119,000 cycles — **6.6% of a second at 1.789 MHz, and the input line
  does not block**, so that lands in the frame. §8 trigger 5 is *anticipated* by that figure but
  not measured on the real path.
- **AC-9** [class: state-comparable] — §2V's table: ★★★ **the structures BUILT this task are two
  host-side Python tools and nothing on the target**, so there is nothing to enumerate against a
  prediction. L-105's discipline is recorded for the next attempt: enumerate what was built, then
  diff against what was predicted, rather than only checking the predicted rows.
- **AC-10** [class: state-comparable] — occupancy **after is identical to before**: 3,328 total,
  parser 954, text engine 1,411, buffer 768, **195 free for sound**. Nothing was added.
- **AC-11** [class: byte-comparable] — **nine-title state diff unchanged, both arms, exclusion set
  EMPTY.** No-input 9/9 PASS; parser arm 9/9 PASS with input fed to 6 of 9. Verbatim in §5.
- **AC-12** [class: state-comparable] — §7.
- **AC-13** [class: suite] — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
★ gates run: pic res cel comp p3b  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ TEXT GATE PASS over all 9 titles
★ PORT GATE PASS over all 9 titles
```

```
=== AC-2 SUMMARY ===  (VM gate, no-input arm)   all nine PASS
=== AC-2 SUMMARY ===  (VM gate, parser arm)     all nine PASS, 6 fed input
compared: 600 cycles x 288 bytes, exclusion set EMPTY;  divergent cycles: 0 of 600
```

```
title                 logics  walked  max write   max read   slots
Kingquest1                90      90          0          -       1
Kingquest2               133     133          4          4       5
Kingquest3               125     125          2          -       3
SpaceQuest-1             101     101          4          4       5
SpaceQuest-2             118     118          4          4       5
PoliceQuest1             118     118         12          9      13
larry1                    46      46         12         11      13
BlackCauldron             85      85          0          -       1
MixedUpMotherGoose        73      73          6          6       7
walk coverage: 889 of 889 logics (100.0%)
CORPUS: highest slot touched = 12, so 13 slots are used
  oracle's declared table : 25 x 40 = 1000 bytes
  measured requirement    : 13 x 40 = 520 bytes
```

```
═══ what MAP_RESERVED has ═══
  region                     3328 B  ($5300-$6000, floor 3072 on the SIZE)
  parser                      954 B
  text engine                1411 B   [P6.19, measured]
  text substitution buffer    768 B
  FREE                        195 B   ★ and sound is unwritten
═══ free elsewhere ═══
  MAP_VMSTATE tail            576 B   ($0DC0-$1000, after 16 x 42 B screen objects)
  MAP_CODE spare                5 B
── DATA (measured or read at the pin) ──
  string table, 13 slots x 40     520 B
  _inputString[42]                 42 B
  edit state, 9 fields             10 B
  DATA SUBTOTAL                   572 B
  CODE SUBTOTAL                 ~ 510 B   ★ ESTIMATE
  TOTAL                        ~ 1082 B  against 195 free in MAP_RESERVED
  ★★★★★ THE DATA ALONE DOES NOT FIT: 572 B against 195 free. Even with ZERO
        bytes of code this is 2.9x over.
  ★★★★ With the string table moved to the MAP_VMSTATE tail, MAP_RESERVED would
        need 42 + 10 + ~510 = ~562 B -- still 2.9x over 195.
```

```
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s    8   $FFA5 $FFA6
```

**§2W — the instrument shown able to fail, and it failed first:**
★★★★★ **`string_census.py`'s first version reported "0 slots are needed" from a walker that had
never walked anything.** It indexed `optable.V2_COMMANDS[op].name`, and the entries are plain
`(name, params, handler)` **tuples** — so every logic raised on its first opcode, all nine titles
reported `0 walked`, and the summary printed a requirement of **zero**. ★★★★ **Zero is the most
convenient possible answer to AC-3's question**, and it would have turned a stop into a green light.
Two changes: the walk is now `opcode_census.py`'s proven one, and **the tool refuses to print a
requirement when coverage is zero** rather than dividing by nothing.
★★★★ **Then the corrected walker was still wrong, in the other direction.** It mapped `get.num`'s
operand 1 as a string slot; `get.num` is `nv` and stores into a **variable**, so it sampled variable
numbers and reported a maximum slot of **255 for larry1 and 237 for PoliceQuest1** — a table of
256 × 40 = **10,240 bytes, three times the whole of MAP_RESERVED.** That would have triggered the
same stop for a reason that was not true. ★★★ **Both errors produced a plausible headline number
and the walk coverage line is what exposed each** — 0/889 for the first, and for the second an
implausible index against a 25-slot table the oracle itself declares.

**25.2 bundled-artifact grep:** N/A — no target artifact was produced or changed. Two host-side
Python tools is the whole delta.

**25.3 operator-runtime-smoke:** **N/A — not reached.** AC-1 depends on work the stop blocks; no
launch path was exercised and none is claimed.

---

### 6 — Reactive deviations and route accounting
**Deviations (§22.5):** none. ★★★ **The stop is the dispatch's own trigger 1, taken as written**:
the bytes are reported and nothing was cut, moved or trimmed to make it fit.

**Route accounting:** I proposed no route. **What I did NOT implement, explicitly and by design:**
the reference `get.string` (AC-4's first branch), the port (AC-5), its fault (AC-6), the input line
(AC-7) and its cost (AC-8). ★★ I judged that building the Python reference would not have violated
the trigger — it consumes no target bytes — but the trigger says stop, and the reference's value is
that it precedes a port that is now blocked. **Said here rather than left to a diff that cannot
show it.**

---

### 7 — Uncertainty flags
- ★★★★ **13 slots is a corpus measurement, not a bound.** The oracle's own bound is 25, and a title
  outside the nine could use more. Sizing the table at 13 buys 480 bytes and takes on a risk the
  gate cannot currently see, since no gate exercises the string table at all (P6.19: `%s` is read
  189 times but both legs read an *empty* table).
- ★★★ **The code figures are estimates.** Anchored on measured routines and labelled, and the
  verdict does not rest on them — but if the map question is settled by finding ~600 bytes, the
  estimate becomes load-bearing and should be replaced by writing the reference and re-deriving it.
- ★★★ **Nobody has sized sound.** 195 B is what is left for it; whether that is a crisis or ample
  is unknown, and `MAP_RESERVED_MIN`'s own note says as much.
- ★★ **AD-134's scheme is untested in software.** It reads at the PIA matrix with no ghosting; no
  code has read it into a buffer, so trigger 3 is untested rather than clear.
- ★ **Backspace is unlogged by patch 0010**, so a port's backspace would be ungated until that one
  call is added.

---

### 8 — Follow-up candidates
- ★★★★★ **The map/design decision** — Jay's. The concrete shape: ~572 B of data and ~510 B of code
  need a home, `MAP_RESERVED` has 195, and the `MAP_VMSTATE` tail's 576 B is the one natural place
  for the string table specifically.
- ★★★★ **The eight text opcodes** — `display`, `display.v`, `print`, `print.v`, `print.at`,
  `print.at.v`, `clear.lines`, `clear.text.rect`, `close.window`, `status.line.on/off`. ★★★ **These
  need far less space than `get.string`** — no string table, no input buffer, no key decode — and
  they are what fills the KQ1 scroll panel. **If a smaller slice of AC-1 is wanted before the map
  question is settled, this is it.**
- ★★★ **One `oracleLogText` call in `clearBlock`**, so backspace is gateable when the port arrives.
- ★★ P6.19's open items: the message-box border (`drawBox`, unmodelled on both legs), the blitter's
  2,970 cycles/glyph, §2B's authored font.
- ★ p3b's missing `PIC_NOCOUNT` (twelve tasks); `-DVM_VBLCLOCK` runaway into `$0400-$05FF`.

---

### 9 — User interaction during task
None.

---

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-08-measure-the-requirement-before-you-negotiate-the-space.md`

---

### 11 — Commit
`6a7b132` — pushed to origin/wip, carrying both tools and this report. ★ Corrected by one follow-up
commit, since a report cannot name the hash of the commit that contains it.
