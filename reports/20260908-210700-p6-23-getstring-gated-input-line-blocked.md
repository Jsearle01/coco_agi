## Form B Report — T-P0-079 (P6.23) — `get.string` gated; the input line is blocked at the matrix
**Class:** build.  wip.  ★★★★ **AC-3 DELIVERED (9/9, and it found a real port bug). AC-4 NOT
DELIVERED: the decoder now runs, one real bug in it is fixed, and keys still do not reach the PIA
matrix.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08T21:07:17-04:00 (HEAD 874f0ab, wip). Working tree carries this task's changes only.

---

### §4 — Pre-dispatch grep (verbatim, run not asserted)

```
=== coco_agi ===      874f0ab  wip
=== POP3_port ===     104b197  no dirty tracked files
=== karateka_coco3 == 29f8f0a  M harness/smoke/last-run.log only  (pre-existing)

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi   (from POP)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi        (from Karateka)

★ gates run: pic res cel comp p3b  -- all green      [re-run AFTER every change]
  per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
  resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
  cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
  ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ TEXT GATE PASS over all 9 titles     ★ PORT GATE PASS over all 9 titles
★ GET.STRING GATE PASS over all 9 titles
VM gate no-input arm: 9/9 PASS.  VM parser arm: 9/9 PASS, 6 of 9 fed input.
[reg-discipline] 8 register access(es) in 1 file(s): src/engine/mmu_phase.s $FFA5 $FFA6
```

★ **§2T:** P6.22 §0 recorded POP `104b197` and Karateka `29f8f0a`; **both unchanged**. The decoder
lives in `hal_globals.s`, which is PROJECT_LOCAL, so **their inputs are unchanged and neither was
rebuilt** — there was nothing to rebuild.

**Flag sets, enumerated and diffed** [L-77]:

| build | flags | bytes |
|---|---|---|
| `gs_probe.bin` — **NEW gate** | *(none)* | 2,375 |
| `input_probe.bin` — **NEW** | `-DHAL_KEYBOARD` | 3,505 |
| `text_probe.bin` | *(none)* / wrap / printf / pbuf | 1,714 / 1,714 / 1,717 / 1,714 |
| `pic_probe.bin` | `-DHAL_GFX_MODE_SERVICE` | 2,654 *(record says 2,642 — P6.22 §3.E)* |
| `hal_build.bin` | with / without `-DHAL_KEYBOARD` | 1,470 / 1,152 |
| `reserved_fit.s` | `-DPLANE_WINDOWED` (+ `RF_INPUT_BUDGET=256` red) | green / fires |

**`MAP_RESERVED`:** 3,008 of 3,328 → **320 free**, sound unwritten. **`HAL_key_scan`:** 318 B, and
**nothing else calls it** — `input_probe.s` is its only caller and it did not exist until this task.

---

### 1 — Summary
**`get.string` is gated: 9/9 titles, 432 cases, 23,878 events**, and the gate earned itself
immediately by finding a real port bug — the oracle calls `clearBlock` **unconditionally** after
backspace's if/else and my 6809 had it inside a branch. The fault arm fires on all nine at exactly
the strictly-greater buffer test. ★★★★ **AC-4 is not delivered.** The decoder ran for the first
time and that produced a second real bug — the column strobe started from `$FF` and shifted, which
stays `$FF` and **selects no column at all**. Fixed, and keys still do not reach the matrix:
natkeyboard accepts the post, the guest is strobing (`$FF02=$EF` observed), and `$FF00` reads
all-high on every scan. **The evidence bounds this to key delivery rather than decoder logic**, and
I stopped there rather than guess. AC-1 and AC-5 depend on it and are not reached.

---

### 2 — Files modified
- `src/engine/text.s` — M. Backspace's cell clear made **unconditional** (the gate's find).
- `src/hal/coco3-dsk/hal_globals.s` — M. Column strobe `$FF` → `$FE` (the run's find).
- `src/engine/memmap.inc` — M. The stride's **five** homes enumerated; my own "three" corrected.
- `src/harness/input_probe.s` — NEW. Matrix → decoder → `gs_keypress` → echo → parser.
- `harness/tools/gs_gate.py` / `gs_gate.lua` / `gs_run.sh` — NEW. The `get.string` gate.
- `harness/tools/input_gate.lua` — NEW. Types a command; reports where it stops.

---

### 3 — Reasoning

**A. The `get.string` gate found a port bug on its first run.** [authority: measurement]
Case 0, event 0: the reference emitted a **cell clear at (0,0)** and the port emitted a glyph.
`get.string`'s opening `inputEditOn` sends a backspace whenever a cursor character is set, and
text.cpp:313-322 puts `clearBlock(...)` **after** the if/else-if, not inside either arm — so a
backspace at column 0 of row 0, where neither arm moves the cursor, still clears the cell it sits
on. ★★★ **My branch skipped the clear, and the position was right either way**: it was a missing
side effect, not a missing move, which is why nothing before this noticed.

**B. The cases are derived, not invented, and cover the four branches.** [L-85]
48 per title from a fixed generator: real lead-in messages from the title, five rows (including 22,
23, 24 — where backspace's `row > 21` matters), four columns, five max lengths, and four key
shapes — plain, backspace, **over-length (`max_len + 3` keys, so the strictly-greater test is
exercised)** and escape. Every fourth case has no lead-in at all, covering the null-`textPtr`
branch. ★★ Fixed generator, so a title always produces the same cases.

**C. The fault arm targets the one-byte test.** [§2W]
`--fault-maxlen` gives the **reference** one extra byte of buffer — one leg only [L-73] — so a
correct port must fail. It does, on all nine, and it fails **on case 2, the over-length shape**,
with `curpos=20` against `21`. ★★★ That is precisely the `_inputStringMaxLen > _inputStringCursorPos`
test, and a `>=` there would have been invisible to everything else in this gate.

**D. The decoder's first execution found the bug "never executed" was flagging.** [measurement]
`HAL_key_scan` selects a column by driving one bit low. The first version started from `$FF` and
shifted left, ORing the vacated bit back in — and `$FF << 1 | 1` is `$FF`. **Every column select
wrote `$FF`, which selects nothing.** Corrected to start from `$FE`. ★★★ The code reads plausibly;
the loop is right for every starting value except the one it used.

**E. Where AC-4 actually stops, and the diagnosis is bounded rather than guessed.** [measurement]
After the fix, one run reports:

```
natkeyboard: in_use=true empty before=true after=false
  scan check: $FF02=$EF  NRAW=0  keys pending
★★★ no progress: DONE=0 NKEY=0 NRAW=0 LASTK=$FF PC=$207C
```

- **natkeyboard accepted the characters** (`empty` true → false), so MAME has them and is feeding
  them.
- **The guest is scanning**: `$FF02 = $EF` is bit 4 low — column 4 selected — read from the host
  while keys were pending.
- **`NRAW = 0`**: the count of scans that saw *any* row low, across the whole run. `$FF00` never
  showed a pressed key.
- `HAL_input_init` is called and is correct — it sets CR bit 2 on **both** sides (`$FF01` and
  `$FF03`), so both ports address data rather than DDR.

★★★★ **`NRAW` is the instrument that makes this a bounded finding rather than a shrug.** Zero raw
scans means the matrix saw nothing; non-zero raw with zero decoded would have meant the table was
wrong. **From the host those two are identical symptoms**, and I built the counter before running
so the first failure would be diagnostic [L-54]. ★★★ What remains unknown is how MAME delivers
natural-keyboard input to `coco3` when the guest has taken the machine over — and **that is a
harness question, not a decoder-logic one, on the evidence I have.** I did not guess at it.

**F. §2S refs.** POP `104b197`, Karateka `29f8f0a`, measured this task; neither rebuilt, neither
needed to be. ScummVM at the pin `9d9b9e93`.

---

### 4 — Verification (AC-by-AC)

- **AC-1** [class: **eye-gated**] — ★★★★ **NOT REACHED, and neither half is.** The typed-command
  half is blocked by §3.E. The scroll-panel half needs `display` / `display.v`, still
  `vm_op_modelled`. ★★★ **P6.19 §9's prediction — rows 6–18, columns 12–28 — remains unrefuted and
  untested.** Trigger 1 has not fired because the test has not run.
- **AC-2** [class: byte-comparable] — every gate RUN, verbatim §4. `hal_sync` green ×3;
  `reg_discipline` unchanged at 8, all `mmu_phase.s`'s — **`getstring.s` and the decoder add zero**
  (the decoder's `$FF00`/`$FF02` are in the HAL, where §2N says they belong).
- **AC-3** [class: byte-comparable] — ★★★★★ **DELIVERED.** Per title [L-10]:

  | title | cases | events | result |
  |---|---|---|---|
  | Kingquest1 | 48 | 3,004 | PASS |
  | Kingquest2 | 48 | 3,061 | PASS |
  | Kingquest3 | 48 | 2,332 | PASS |
  | SpaceQuest-1 | 48 | 2,763 | PASS |
  | SpaceQuest-2 | 48 | 2,594 | PASS |
  | PoliceQuest1 | 48 | 2,715 | PASS |
  | larry1 | 48 | 2,272 | PASS |
  | BlackCauldron | 48 | 2,773 | PASS |
  | MixedUpMotherGoose | 48 | 2,364 | PASS |
  | **TOTAL** | **432** | **23,878** | **9/9** |

  Events compared are glyph position/colour/checksum, cell clears, cursor position and the entered
  flag. **Fault arm: caught on all nine** (§3.C).
- **AC-4** [class: byte-comparable] — ★★★★ **NOT DELIVERED.** §3.E. ★★★ **No key in AD-134's scheme
  was shown reachable, and none was shown unreachable either** — the matrix reports nothing for any
  key, so this is not trigger 2's case (a specific key the decoder cannot reach) and I have not
  reported one. The decoder is now *executed* and one real bug in it is fixed.
- **AC-5** [class: state-comparable] — **NOT REACHED.** Depends on AC-4. ★★ P6.19's 2,970
  cycles/glyph still bounds the echo: a 40-column redraw is ~119,000 cycles, 6.6% of a second at
  1.789 MHz, **and the input line does not block**.
- **AC-6** [class: byte-comparable] — **VM gate 9/9 both arms, exclusion set EMPTY; resource gate
  1,264/1,264 at the 768 stride.** Verbatim §4.
- **AC-7** [class: state-comparable] — §2V's table. ★★★ **Structures BUILT, enumerated first**
  [L-105]:

  | built | predicted? | verdict |
  |---|---|---|
  | `ip_key`, `ip_last` (2 B) | no | **NEW** — a debounce latch. `HAL_key_scan` reports a LEVEL; turning it into an EVENT needs one byte of history, and the reference has no analogue because ScummVM is handed events |
  | `IP_NRAW` counter | no | **NEW** — a diagnostic, and the one that made §3.E bounded |
  | the poll loop itself | partly | the engine's `cycleInnerLoopActive` re-entry; the probe owns it, which is what `getstring.s`'s start/keypress/finish split was for [P6.21] |
  | `gs_key` save | yes (P6.22) | held |

  ★★★★ **The debounce is the row that matters and it was not predicted.** §2V's table describes
  data shapes; **the miss was again in control flow** — level-versus-edge is not a structure, and
  it is the difference between one keystroke and a thousand.
- **AC-8** [class: state-comparable] — `MAP_RESERVED` 3,008 of 3,328 → **320 free for sound**;
  `MAP_INPUT` 404 of 1,024 → **620 free**; `MAP_VMSTATE` tail 14 free.
- **AC-9** [class: state-comparable] — ★★★★ **Five homes, no sixth.** `addr_census.py` names
  `RES_DIR_STRIDE` only in a comment explaining why `_STRIDE` suffixes are **excluded** as sizes;
  `p3b_probe.s` and `p3b_boot_test.s` inherit `RES_DIRS equ MAP_DIRS` rather than restating the
  stride. ★★★ **But my own P6.22 comment in `memmap.inc` said "three homes" — written in the same
  task that discovered the fourth and fifth.** Corrected, with the full list enumerated in the file.
- **AC-10** [class: state-comparable] — §7.
- **AC-11** [class: suite] — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
=== get.string gate: Kingquest1 ===
  cases  : 6809 48   reference 48
  events : 6809 3004   reference 3004
  OK 48 cases identical: 3004 events, cursor positions and entered flags
GET.STRING GATE PASS
★ GET.STRING GATE PASS over all 9 titles

=== fault arm ===
  *** CASE 2 STATE: 6809 curpos=20 entered=1   reference curpos=21 entered=1
★ maxlen fault CAUGHT on all 9 titles -- the gate can go red
```

```
=== the gate's first run, before the fix ===
  *** CASE 0 EVENT 0: 6809 ('G', 22, 0, 0, 0, 89)   reference ('C', 0, 0, 0)
  events : 6809 2987   reference 3004
```

```
=== AC-4, where it stops ===
staged: program 3505 B; typing 12 characters
natkeyboard: in_use=true empty before=true after=false
  scan check: $FF02=$EF  NRAW=0  keys pending
★★★ no progress: DONE=0 NKEY=0 NRAW=0 LASTK=$FF PC=$207C
     curpos=0 done=0
```

```
★ gates run: pic res cel comp p3b  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ TEXT GATE PASS over all 9 titles     ★ PORT GATE PASS over all 9 titles
=== AC-2 SUMMARY === (no-input) all nine PASS   (parser) all nine PASS, 6 fed input
compared: 600 cycles x 288 bytes, exclusion set EMPTY; divergent cycles: 0 of 600

MAP_RESERVED: 2432 code + 576 buffer = 3008 of 3328 -> free 320
MAP_INPUT:     404 of 1024 -> free 620
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] 8 register access(es) in 1 file(s): src/engine/mmu_phase.s $FFA5 $FFA6
```

**§2W — instruments shown able to fail:**
- The `get.string` gate's fault arm fires on all nine, at the specific case the fault targets.
- ★★★ **The gate failed on its first real run and was right to** — the port was wrong, not the gate.
- `IP_NRAW` is a diagnostic built to discriminate two failure modes that look identical from the
  host, and it did the job the first time it was needed.
- The `reserved_fit` assertions remain two-sided (green default, red at `RF_INPUT_BUDGET=256`).

**25.2 bundled-artifact grep:** N/A — no delivery artifact produced or changed.

**25.3 operator-runtime-smoke:** **N/A — not reached.** AC-1 depends on AC-4. No launch path was
exercised for a human and none is claimed.

---

### 6 — Reactive deviations and route accounting
**Deviations (§22.5):** none. ★ The two source fixes (the unconditional clear, the column strobe)
are defects found by the task's own instruments, not scope changes.

**Route accounting — what I did NOT implement, explicitly:** AC-4's working input line; AC-5's
cost; AC-1's eye gate, neither half. ★★ **The decoder is executed but not validated**: one bug in
it is fixed and no key has yet been decoded end to end, so the matrix table remains transcribed
rather than confirmed.

---

### 7 — Uncertainty flags
- ★★★★★ **How MAME delivers natural-keyboard input to `coco3` under a taken-over machine is
  unknown to me.** natkeyboard accepts the post and the matrix reads nothing. **This is the whole
  of AC-4's blockage** and it is a harness question on the evidence.
- ★★★★ **The decoder's matrix table is unvalidated.** One structural bug found by running it; the
  56 key positions are still transcribed from the standard CoCo layout and unconfirmed.
- ★★★ **`get.string` is gated against the reference, not the oracle.** Driving it in ScummVM needs
  a keystroke-fed sweep patch 0010 does not have, and the `C` (cell-clear) records are
  6809-against-Python only because `clearBlock` emits no `drawCharacter` [P6.20 §5].
- ★★ **The 48 cases per title are generated, not sampled from play.** They cover the four branches
  deliberately; they are not evidence about what real games do with `get.string`.
- ★ `pic_probe.bin`'s 12-byte discrepancy against `run_gates.sh`'s recorded 2,642 is still unchased.

---

### 8 — Follow-up candidates
- ★★★★★ **Resolve the key delivery.** Two concrete routes: drive `$FF00` through a MAME **read
  tap** so the matrix value is injected directly (idioms §287 records the tap-GC gotcha), or
  determine how `coco3`'s natural keyboard reaches the PIA and meet it. **A read tap would also
  let every one of AD-134's 56 positions be tested deterministically**, which is the arm AC-4 wants
  regardless.
- ★★★★ **The eight text opcodes** — still the reachable half of AC-1, needing no keyboard, with
  320 B free in `MAP_RESERVED`.
- ★★★ One home for the DIR stride (five files); one `oracleLogText` in `clearBlock`.
- ★★ The message-box border; §2B's authored font; `run_gates.sh`'s stale probe sizes.
- ★ p3b's `PIC_NOCOUNT`; `-DVM_VBLCLOCK`'s runaway.

---

### 9 — User interaction during task
None.

---

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-08-build-the-discriminator-before-the-first-failure.md`

---

### 11 — Commit
See the follow-up commit.
