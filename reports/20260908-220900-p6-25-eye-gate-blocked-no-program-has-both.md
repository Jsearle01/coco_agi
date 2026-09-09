## Form B Report — T-P0-081 (P6.25) — The eye gate: §1's premise does not hold
**Class:** build.  wip.  ★★★★★ **STOPPED at §4's contradiction rule. Two of AC-1's three parts
require code that does not exist, and §1 states none is required.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-08T22:09:40-04:00 (HEAD 5efad04, wip). Working tree clean but for untracked editor
state. **No source was changed by this task.**

---

### §4 — Pre-dispatch grep (verbatim, run not asserted)

```
=== coco_agi ===      5efad04  wip   (clean; ?? coco_agi.code-workspace only)
=== POP3_port ===     104b197  clean
=== karateka_coco3 == 29f8f0a  M harness/smoke/last-run.log only  (pre-existing)

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi   (from POP)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi        (from Karateka)

★ gates run: pic res cel comp p3b  -- all green
  per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
  resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
  cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
  ★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
  ★ 160 cycles in 18.4571 emulated s
★ TEXT GATE PASS over all 9 titles     ★ PORT GATE PASS over all 9 titles
★ GET.STRING GATE PASS over all 9 titles
VM gate no-input arm: 9/9 PASS.  VM parser arm: 9/9 PASS, 6 of 9 fed input.
[reg-discipline] 8 register access(es) in 1 file(s): src/engine/mmu_phase.s $FFA5 $FFA6
```

★ **§2T:** P6.24 §0 recorded POP `104b197` and Karateka `29f8f0a`; **both unchanged**.
`hal_globals.s` is PROJECT_LOCAL, so their inputs are unchanged and neither was rebuilt.

**Flag sets, enumerated and diffed** [L-77]:

| build | flags | bytes |
|---|---|---|
| `input_probe.bin` | `-DHAL_KEYBOARD` | 3,572 |
| `p3b_probe.bin` | its own set (`run_gates.sh` p3b row) | 13,010 |
| `gs_probe.bin` | *(none)* | 2,375 |
| `text_probe.bin` | *(none)* | 1,866 |
| `pic_probe.bin` | `-DHAL_GFX_MODE_SERVICE` | 2,654 *(record says 2,642 — P6.22 §3.E)* |

**The input chain reproduces, before any eye-gate run:**

```
=== 10 of 10 AD-134 items decoded as expected ===
★ line entered: 13 key events, 30 raw scans, last key $0D
★ parser: egon=2  word numbers = 2,37
```

---

### 1 — Summary
★★★★★ **§1 states "There is no new code the task requires." That is not correct, and the
contradiction is §4's stop.** AC-1 has three parts. **§2B is runnable today.** §2A and §2C are not,
for two independent reasons, both measured this task:

1. ★★★★★ **`display` and `display.v` are still `vm_op_modelled`** — declared no-ops. The scroll
   panel's words go through them [AD-156] and nothing draws.
2. ★★★★★ **No program combines the text engine with the VM.** `p3b_probe.s` is vm+parser+hal;
   `input_probe.s` is text+getstring+parser+hal. **There is no binary that can render a room and
   draw text**, let alone answer a command.

★★★★ **I reported this at the close of P6.24** — *"the only thing now between here and AC-1 is the
eight text opcodes"* — so the premise was contradicted before the dispatch was written, and I am
not treating my own prior statement as sufficient: both halves are re-measured below. **No source
was changed**; the integration is a real piece of work and its scope is Jay's.

---

### 2 — Files modified
**None.** ★★★ That is the point of the stop: building the missing integration would be a
substantial unsanctioned expansion of a task whose stated premise is that no code is needed.

---

### 3 — Reasoning

**A. The opcodes, measured this task.** [authority: the reference's own status table]

```
print 101 modelled   print.v 102 modelled   display 103 modelled   display.v 104 modelled
clear.lines 105 modelled   status.line.on 112 modelled   status.line.off 113 modelled
print.at 151 modelled   print.at.v 152 modelled   close.window 169 modelled
```

★★★ **`modelled` is a DECLARED no-op** [gen_vm_tables.py: "an opcode whose only effects are
presentation and which changes nothing the state diff can observe"]. That classification is exactly
why the nine-title state diff is 9/9 green while nothing appears on screen — **the byte gates and
the eye gate are asking different questions, which is idiom 19j in its original form.**

**B. No program has both halves.** [authority: measurement over `src/harness/`]

| probe | text | getstring | vm | parser | hal |
|---|---|---|---|---|---|
| `p3b_probe.s` | — | — | ✔ | ✔ | ✔ |
| `input_probe.s` | ✔ | ✔ | — | ✔ | ✔ |
| `gs_probe.s` | ✔ | ✔ | — | — | — |
| `text_show.s` | ✔ | — | — | — | — |

★★★★ **The two rows that matter are the first two, and they are disjoint in exactly the place
AC-1 needs them joined.** p3b renders rooms and cannot draw a character; input_probe draws
characters and runs no interpreter. §2C — "the game responds" — needs a program that has both and
also routes the parser's result back into the VM's `said()` evaluation.

**C. What §2B needs, and it is nothing.** `input_probe.s` already opens an input line at row 22,
decodes AD-134's scheme, echoes each keystroke into the 320×200×16 plane through the gated blitter,
and hands the line to the parser. ★★★ **It is a `poke` launch and it draws to a real screen.**
Running it throttled in front of Jay is one command and needs no code:

```
IP_VOCAB=C:/Projects/agi-games/pc/Kingquest1/WORDS.TOK IP_WATCH=1 \
  mame coco3 -rompath C:/mame/roms -window -seconds_to_run 40 \
  -autoboot_script harness/tools/input_gate.lua
```

★★ **No `-nothrottle`** — §2U.2, an eye gate runs at the speed the machine would.

**D. Why I did not build it anyway.** The missing work is: implement the ten text opcodes against
the reference, wire `text.s` + `getstring.s` into `p3b_probe.s` (13,010 bytes against a 13,056-byte
`MAP_CODE` — see §7), and route the parsed line into the VM's input variables so `said()` can match.
★★★ **That is a multi-task piece with a real placement question in it**, and §1's premise means
nobody has costed it. ★★ Doing it silently under a dispatch that says "no new code" is the failure
§22.5 exists to prevent.

**E. §2S refs.** POP `104b197`, Karateka `29f8f0a`, measured this task. ScummVM at the pin
`9d9b9e93`.

---

### 4 — Verification (AC-by-AC)

- **AC-1** [class: **eye-gated**] — ★★★★★ **NOT RUN, and two of its three parts cannot be.**
  **§2A (scroll panel)**: blocked by §3.A — `display`/`display.v` are no-ops.
  **§2C (game responds)**: blocked by §3.B — no program has the VM and the text engine.
  **§2B (typed command echoes)**: ★★★ **runnable today, command in §3.C, and it is the one thing
  here I can put in front of Jay.** ★★ Not claimed as passed: Jay has not seen it.
  ★★★★ **Triggers 1 and 3 have NOT fired** — the predictions are untested, not refuted. AD-156's
  three pieces of evidence still stand.
- **AC-2** [class: byte-comparable] — every gate RUN, verbatim §4. `hal_sync` green ×3;
  `reg_discipline` unchanged at 8, all `mmu_phase.s`'s.
- **AC-3** [class: state-comparable] — ★★★★ **cannot be measured as asked, and that is the same
  finding.** The AC wants the cycle rate *"with text and input live"*; **no program has them live**,
  so the configuration does not exist to measure. What was measured: **p3b, 160 cycles in 18.4571
  emulated seconds = 8.67 cycles/s (0.1154 s/cycle), with text and input ABSENT.** ★★★ I am not
  comparing that to AD-135's T3 figure: different harness, different flag set, and a like-for-like
  claim needs both taken the same way [L-77]. ★★ The one input-side cost that *is* measured is
  P6.24's: 75 cycles per idle poll, 0.50% of a frame.
- **AC-4** [class: state-comparable] — **launch path `poke`** for everything runnable here. ★★★ §4:
  a `poke` gate **hides load and launch bugs** and is **not a delivery gate**; `live-disk` is the
  only path that gates delivery and the storage layer does not exist (§11).
- **AC-5** [class: state-comparable] — ★★★ **Nothing broke, and here that is not suspicious but
  tautological: nothing was combined.** All eight gate rows are green at the same values as P6.24.
  ★★ The dispatch's own warning applies to a run that happened; this one did not.
- **AC-6** [class: byte-comparable] — **N/A.** AC-1 exposed no rendering fault because AC-1 did not
  run.
- **AC-7** [class: state-comparable] — §7.
- **AC-8** [class: suite] — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim):**

```
★ gates run: pic res cel comp p3b  -- all green
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)
★ composites byte-identical on both planes: 124 / 124 frames (100.00%)
★ 160 cycles in 18.4571 emulated s        -> 8.669 cycles/s, 0.11536 s/cycle
★ TEXT GATE PASS over all 9 titles   ★ PORT GATE PASS over all 9 titles
★ GET.STRING GATE PASS over all 9 titles
VM no-input FAILs: 0;  parser arm 9/9, 6 of 9 fed input
[hal-sync] OK in all three;  [reg-discipline] 8, all mmu_phase.s
```

```
=== the input chain, reproduced ===
=== 10 of 10 AD-134 items decoded as expected ===
★ line entered: 13 key events, 30 raw scans, last key $0D
★ parser: egon=2  word numbers = 2,37
```

```
=== the contradiction, measured ===
display 103 modelled   display.v 104 modelled   (+ 8 more text opcodes, all modelled)

probe            subsystems
p3b_probe.s      vm+parser+hal          <- renders rooms, cannot draw text
input_probe.s    text+getstring+parser+hal  <- draws text, runs no interpreter
```

**§2W:** no new instrument was built this task. The instruments quoted above are the existing gates
and P6.24's `key_coverage.lua` / `input_gate.lua`, each shown able to fail in its own task.

**25.2 bundled-artifact grep:** N/A — no artifact produced or changed.

**25.3 operator-runtime-smoke:** ★★★★ **NOT RUN. "pending Jay" for §2B only**, launch path `poke`,
RGB, command in §3.C. **§2A and §2C are not pending Jay — they are unbuilt.**

---

### 6 — Reactive deviations and route accounting
**Deviations (§22.5):** none — no code was changed. ★★★★ **The stop itself is the deviation from the
dispatch's expectation**, taken under §4's "Contradiction → stop and report".

**Route accounting — what I did NOT do, explicitly:** I did not implement the ten text opcodes, did
not wire the text engine into `p3b_probe.s`, and did not route the parser's output into the VM.
★★ Any of the three would have been a large change under a dispatch stating none was needed.

---

### 7 — Uncertainty flags
- ★★★★ **`p3b_probe.bin` is 13,010 bytes against a `MAP_CODE` of 13,056** — 46 spare. **Adding
  `text.s` (1,478) and `getstring.s` (404) to it does not fit**, so §2A and §2C need a placement
  decision as well as code. That is worth knowing before the work is scoped.
- ★★★ **AC-3's number is not the one the AC asked for.** 8.67 cycles/s is p3b without text or
  input; the asked-for figure requires the program that does not exist.
- ★★ **§2B has never been watched by anyone.** It runs headless and draws into the plane; whether
  the letterforms are legible is precisely what a human is for, and P6.19's font is a `build/`-only
  extraction pending §2B's authored asset.
- ★★ **The word numbers `2,37` remain unverified** as "look"/"rock" (P6.24 §7).
- ★ `pic_probe.bin`'s 12-byte discrepancy against the recorded 2,642 is still unchased.

---

### 8 — Follow-up candidates
- ★★★★★ **The ten text opcodes, against the reference** — `display`, `display.v`, `print`,
  `print.v`, `print.at`, `print.at.v`, `clear.lines`, `close.window`, `status.line.on/off`. The
  text engine they need is built and gated 9/9; this is the wiring.
- ★★★★★ **A combined probe**, and it needs the `MAP_CODE` question answered first (§7): p3b has 46
  spare bytes and the text engine is 1,882.
- ★★★★ **Routing the parsed line into the VM** so `said()` sees it — §2C's other half.
- ★★★ **Watch §2B now**, which needs nothing: one throttled command (§3.C).
- ★★ One home for the DIR stride; `oracleLogText` in `clearBlock`; the message-box border; §2B's
  authored font.
- ★ `run_gates.sh`'s stale probe sizes; p3b's `PIC_NOCOUNT`.

---

### 9 — User interaction during task
None.

---

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-08-a-dispatch-premise-is-a-claim-about-the-tree.md`

---

### 11 — Commit
`8df390d` — pushed to origin/wip. ★ Corrected by one follow-up commit, since a report cannot name
the hash of the commit that contains it.
