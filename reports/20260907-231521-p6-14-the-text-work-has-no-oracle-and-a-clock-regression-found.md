## Form B Report — P6.14 — The text work has no oracle, and a clock regression of mine, two tasks old
**Class:** build.  wip.

★★★★★ **The text work did not land, and the reason is structural: it has no oracle.** The reference
models no display buffer, no glyph rendering, and treats `print`/`display`/`clear.lines` as declared
no-ops; there are no text dumps in `oracle/dumps/`. **CLAUDE.md §2V mandates reference-first**, so
the text subsystem's first task is the Python model — not the 6809.

★★★★★ **What this task DID find is a regression of mine that has been live for two tasks**: P6.12's
VSYNC clock moved only the reference, and **the parser arm has been failing five of six fed titles
ever since**, unnoticed because P6.12 and P6.13 both ran only the no-input gate. **Fixed; both arms
are 9/9 again.**

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-07 23:15:21 (HEAD `25d6d93`, wip). `git status` clean apart from untracked
`coco_agi.code-workspace`, an editor file, not staged (§2E, explicit-path only).

---

### 4' — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===   25d6d93 P6.13 three placements, two already done and one in the wrong region  wip
=== POP ===        104b197 HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)  wip
=== Karateka ===   29f8f0a HAL: commit the guarded HAL_SYS_FAST_CLOCK block (CLAUDE.md 2M)  wip

=== hal_sync x3 ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)

=== reg_discipline ===
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s   8   $FFA5 $FFA6
```
★ **§2T baseline cited, not rebuilt.** POP `104b197` / Karateka `29f8f0a` are P6.13 §0's refs,
unchanged; lwasm 4.24 unchanged.

★★★★★ **EVERY GATE RUN, NOT ASSERTED — and one of them was RED:**
```
★ gates run: pic res cel comp p3b  -- all green
=== p3b ASSEMBLY ===  exit=0   P3_CODE_END = 0x52FB   MAP_CODE_END = 0x5300   spare = 5 bytes
=== VM gate, plain (no input) ===  9/9 PASS
=== VM gate, PARSER ARM (VM_INPUT=1) ===
Kingquest1 FAIL  Kingquest2 FAIL  Kingquest3 FAIL  SpaceQuest-1 FAIL  larry1 FAIL
PoliceQuest1 PASS   SpaceQuest-2/BlackCauldron/MixedUpMotherGoose PASS (no input, not covered)
★ parser arm covered 6 of 9 titles with input; 3 ran without.
```
★★★★★ **Five of the six fed titles failed. §1 and §3.1.**

**Flag sets, enumerated and diffed** (L-77): one expected-on guard absent — p3b's `PIC_NOCOUNT`,
pre-existing, **sixth consecutive task**. **The clock, MEASURED** in every arm (L-78).

**`MAP_RESERVED` occupancy (AC-8):** 3,328 B region, **954 B used** by the parser — the map's own
comment and p3b's measured `P3_PARSER_TOTAL` (`$03BA` = 954) agree exactly — **2,374 B free.**

---

### 1 — Summary

★★★★★ **The text work has no oracle and cannot be gated.** `print` (65), `print.v`, `display`,
`display.v`, `clear.lines`, `set.cursor.char`, `set.text.attribute`, `status.line.on/off` are **all
`vm_op_modelled`** — declared no-ops in both legs. The reference implements only `cmdSetString` and
`cmdTextScreen`, has **no display buffer and no glyph rendering**, and `oracle/dumps/` holds base,
cels and frames but **nothing for text**. AC-3 asks for planes "byte-identical to the oracle"; there
is no such oracle, and implementing text on the 6809 alone would make the diff go red *correctly*.
★★★ **CLAUDE.md §2V:815 is explicit** — *"Every subsystem is built first as a Python reference,
gated against the oracle, then ported. That order is right and it stays."*

★★★★★ **`have.key` is already implemented and matched on both legs.** The dispatch says it "spins";
it does not. 6809 `vmtest_have_key` reads `VAR_KEY` and branches; reference `condHaveKey` does the
same and nothing else. **It is gated by the nine-title diff today.**

★★★★ **`get.string` is unimplemented on BOTH legs** — `vm_op_unimpl` on the 6809 and *declared but
not implemented* in the reference (`optable.py` maps opcode 73 to `cmdGetString`; `commands.py` has
no such function). It prompts at a row/column and blocks, so it needs the display buffer and the
input line. **§7 trigger 5 fires.**

★★★★★ **And the finding that cost the task: my P6.12 clock change broke the parser arm and it has
been broken for two tasks.** P6.12 moved the **reference** to vertical-sync ticks and left the 6809
on 25 ms. I wrote the non-equivalent case into the source — `time_delay == 0`, 25 ms against
16.667 ms — and predicted the diff would move if a title hit it. **The no-input corpus never does;
input drives titles straight into it.** Five of six fed titles diverge on **vars 11 and 12,
SECONDS and MINUTES**, guest ahead of oracle, from cycle 36. **Fixed by putting the port on the same
model: 40→60 tick second, ×2→×3 delay, ms→ticks. Both arms 9/9.**

---

### 2 — Files modified

- `src/harness/vm_cycle.s` — the port's clock on vertical-sync ticks: `vm_sectick` boundary 40→60,
  `VM_VAR_TIME_DELAY` ×2→×3, and `vm_vms` counting ticks rather than milliseconds.

**Nothing else.** No text engine, no glyph table, no shared HAL file, no `src/engine/` change.

---

### 3 — Reasoning

#### 3.1 ★★★★★ The regression: what it was, since when, and why nobody saw it

`cycle.py` (P6.12) advances `self.vsync += 1` per pacing iteration and gates on `time_delay * 3`;
`vm_cycle.s` still advanced `vm_vms += 25` and gated on `time_delay * 2`. For every **non-zero**
`time_delay` those are the same 50 ms and the legs agree. For **zero** they are not: one tick is
16.667 ms in the reference and was 25 ms in the port.

★★★★ **I recorded that exact case in `cycle.py` before running it**, and concluded from a 9/9 that
no gated title sets `time_delay` to 0. ★★★★★ **That conclusion was true of the arm I ran and false
of the arm I did not.** The parser arm feeds input; input drives titles into the zero case.

| | P6.12 | P6.13 | P6.14 (this task) |
|---|---|---|---|
| plain gate | 9/9 run | 9/9 run | 9/9 run |
| **parser arm** | **not run** | **not run** | ★★★★★ **run — 5 of 6 fed titles FAIL** |

★★★ **So it broke at P6.12 and survived P6.13's "every gate RUN" because the parser arm is a
separate invocation of the same runner (`VM_INPUT=1`) and I ran the default.** §4's instruction
caught it only because this dispatch's AC-5 made me feed input.

★★★ **L-85 on my own claim**: a gate's corpus is part of its claim, and an *arm* is part of a gate.

#### 3.2 The fix, and why it is the ruling's software half

Three constants, all in `vm_cycle.s`, all matching `cycle.py`:

| | was | now | why |
|---|---|---|---|
| second boundary | `cmpa #40` (40 × 25 ms) | `cmpa #60` | a second is 60 vertical syncs |
| delay multiplier | `aslb/rola` (×2) | ×2 + ×1 = **×3** | `TIME_DELAY` is in 50 ms AGI ticks; 50 ms is 3 ticks at 60 Hz |
| `vm_vms` | `+= 25` ms | `+= 1` tick | ★★★ **nothing has ever read it** — the only writers are this and `vm_start`'s reset, so the milliseconds were a 32-bit accumulator with no consumer, in a unit the 6809 cannot measure |

★★★★ **This is the "both legs" the ruling asked for, in software, and it does not need the VBL
hardware.** The tick source is still the pacing loop; when `-DVM_VBLCLOCK` comes off its flag the
hardware VBL replaces the source and neither leg's arithmetic changes.

#### 3.3 §2H's three checks, on the text blocker

1. **A SECOND mechanism?** ★★★★ Yes — I checked for a display buffer in the reference and found
   none, then checked the **opcode table** and found `print`/`display`/`clear.lines` are
   `vm_op_modelled`, then checked **`oracle/dumps/`** and found no text dump. **Three independent
   places, same answer**, which is what stops this being one bad grep — and my first grep for
   `def cmd_print` *did* miss, because the reference names them `cmdSetString`-style.
2. **Name the caller.** `vm_op_modelled` is reached through `VMOP_MODELLED_LO` (P6.12) and is a
   declared no-op that consumes its arguments — so a text command today changes nothing either leg
   observes, which is exactly why the gate is green with no text implemented.
3. **Grep the reports before citing.** P6.8 established the two-buffer model and P6.12's AC-7 did
   the clock's reference half. ★★ **Neither established an oracle for text**, and this task is where
   that gap becomes load-bearing.

#### 3.4 ★★★★ What the reference must model — taken from the pin, so the next task starts from evidence

From ScummVM at the pin (`9d9b9e9`, v2.9.1), `engines/agi`:

```
graphics.h:29-34   SCRIPT_WIDTH 160  SCRIPT_HEIGHT 168      <- _activeScreen, the game screen
                   DISPLAY_DEFAULT_WIDTH 320  ..HEIGHT 200   <- _displayScreen, what is shown
graphics.h:115,119 byte *_activeScreen;  byte *_displayScreen;
graphics.cpp:1194  void GfxMgr::drawCharacter(int16 row, int16 column, byte character,
                        byte foreground, byte background, bool disabledLook)
                     -> translateFontPosToDisplayScreen(x, y)  then writes the DISPLAY screen
graphics.cpp:588   void GfxMgr::render_Block(int16 x, int16 y, int16 width, int16 height,
                        bool copyToScreen)
                     -> render_Clip(x, y, w, h, 0, SCRIPT_WIDTH, SCRIPT_HEIGHT)
```

★★★ **That is the whole model in three facts**: text goes only into the 320×200 display buffer; the
game screen at 160×168 is never touched; and the restore is `render_Block` — **a re-render of a
clipped rectangle from the untouched game screen**, which is what the dispatch's §2 describes and
what the port will need. ★★ The reference has neither buffer today.

#### 3.5 §2S — ref and scope

Sibling claims are §0's citation at POP `104b197` / Karateka `29f8f0a`, both `wip`, scope = HEAD and
cleanliness. Oracle claims are at the pin `9d9b9e93108a276c551aeffa390169ccc5148e15`, scope =
`engines/agi` `graphics.h`/`graphics.cpp`, read this task.

---

### 4 — Verification (AC-by-AC)

★★★★★ **AC-1 [eye-gated] — NOT DONE, not "pending Jay".** No text renders, so there is nothing to
show. §4A puts the eye gate first; this task produced no visual surface.

- **AC-2 [byte-comparable] — PASS, every gate RUN, and one was RED before the fix.** pic **45/45**,
  res, cel, comp **124/124**, p3b (160 cycles, no stall), **p3b assembly exit 0**, VM plain **9/9**,
  ★★★★ **VM parser arm 5 FAIL → 9/9 after the fix.** `hal_sync_check.py` OK ×3; `reg_discipline.py`
  8; `gen_vm_tables.py --check` OK. §2T cited in §0. — 25.1.

- **AC-3 [byte-comparable] — NOT DONE, and NOT GATEABLE as written.** §1 and §3.3: the reference has
  no display buffer, no glyph rendering, and every text command is a declared no-op on both legs;
  `oracle/dumps/` has no text dump. **§2V's order puts the Python model first.** §3.4 specifies it.

- **AC-4 [byte-comparable] — NOT DONE.** The input line is not implemented. AD-134's scheme remains
  proven readable at the PIA matrix and unproven in software; **no key can be reported unreachable
  because no key was attempted** — trigger 2 is not fired, it is untested.

- **AC-5 [state-comparable] — SPLIT, and the halves differ.**
  ★★★★ **`have.key`: ALREADY IMPLEMENTED AND MATCHED.** `vmtest_have_key` (`vm_tests.s:154`) reads
  `VAR_KEY` and branches; `condHaveKey` (`tests.py:126`) does the same. **The dispatch's "have.key
  spins" is not the case.** Gated by the nine-title diff.
  ★★★★ **`get.string`: NOT DONE, and blocked.** `vm_op_unimpl` on the 6809, and **declared but not
  implemented in the reference** — `optable.py:290` maps opcode 73 to `cmdGetString`, `commands.py`
  has no such function. It prompts at a row/column and blocks, needing the display buffer and the
  input line. **§7 trigger 5: what it needs is stated before building it.**
  ★★★★★ **The three uncovered titles are NOT all blocked on `get.string`**, which the dispatch
  assumes. Measured: SpaceQuest-2's candidates reach `get.string`; **BlackCauldron and
  MixedUpMotherGoose call `said()` zero times in the gated window** [T-P0-061], so no input script
  can cover them and implementing `get.string` would unblock **one** of three, not three.
  ★★★ **The parser arm is restored: 6 of 9 fed, all PASS**, empty exclusion set — 25.1.

- **AC-6 [byte-comparable] — PASS, and the fault was NATURAL rather than injected.** ★★★★★ **The
  gate demonstrably fails on a clock mismatch between the legs, and this task observed it happening
  rather than contriving it**: 5 of 6 fed titles, 232 divergent cycles of 600 on Kingquest1, first
  divergence cycle 36, **vars [11, 12] — SECONDS and MINUTES — guest ahead of oracle.** ★★★ That is
  a stronger demonstration than an injected fault: the gate caught a real regression, on this build
  and this corpus, and named the variable. ★★ The tick change was then verified in the other
  direction — both arms 9/9 with it in.

- **AC-7 [state-comparable] — NOT DONE.** Depends on AC-3.

- **AC-8 [state-comparable] — DONE.** `MAP_RESERVED` = 3,328 B, **954 B used** (the parser;
  `P3_PARSER_TOTAL` `$03BA` = 954, and the map's comment agrees), **2,374 B free**. **Unchanged by
  this task** — no text engine was placed. The region is still 3,328 B and the floor still fires on
  size, not usage.
  ★★★ **`P3_CODE_END` moved `$52FB` → `$52FF`: 5 bytes spare → 1.** My ×3 multiplier costs 4 bytes
  (`pshs d` / `addd ,s++`). **Reported because it is nearly out** — §7.4.

- **AC-9 [state-comparable] — NOT DONE.** The glyph source is a decision with a provenance and
  should not be made in passing; nothing was authored, so §2B's protection is not yet engaged.

- **AC-10 [state-comparable] — REPORTED, and it moved.** ★★★★ **The clock's SOFTWARE half is now
  complete in both legs**: reference and port both count vertical-sync ticks, 60 to the second, 3 to
  an AGI tick. ★★★ **The HARDWARE half is still gated.** `-DVM_VBLCLOCK` remains off and the runaway
  into `$0400`–`$05FF` is **still unexplained** [AD-142] — untouched this task, as §11 scopes it.
  ★★ **What changed is that the port no longer computes a unit it cannot measure**, so switching the
  tick source to the real VBL counter is now a source change with no arithmetic behind it.

- **AC-11 [state-comparable] — see §7.**
- **AC-12 [suite] — §10.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 (verbatim).** Gates — §4' above, all run this task.

The regression, Kingquest1 with input, BEFORE the fix:
```
cycle 38   1 difference(s): var 11 oracle=0 guest=1
cycle 47   1 difference(s): var 11 oracle=0 guest=1
divergent cycles : 232 of 600
first divergence : cycle 36
vars involved    : [11, 12]
flags involved   : []
AC-2 ★★★ FAIL
```
```
VM_VAR_SECONDS equ 11    VM_VAR_MINUTES equ 12    VM_VAR_TIME_DELAY equ 10
```
AFTER the fix — both arms, nine titles:
```
########## PARSER ARM, nine titles ##########
Kingquest1 PASS input fed   Kingquest2 PASS input fed   Kingquest3 PASS input fed
SpaceQuest-1 PASS input fed  PoliceQuest1 PASS input fed  larry1 PASS input fed
SpaceQuest-2 / BlackCauldron / MixedUpMotherGoose  PASS  (NO INPUT -- not covered by this arm)
★ parser arm covered 6 of 9 titles with input; 3 ran without and are the plain gate.
########## PLAIN GATE, nine titles ##########
Kingquest1..MixedUpMotherGoose  9/9 PASS
```
AC-3's blocker, the reference's text coverage:
```
fdb vm_op_modelled ; 65 print(s)        fdb vm_op_modelled ; 67 display(nns)
fdb vm_op_modelled ; 66 print.v(v)      fdb vm_op_modelled ; 69 clear.lines(nns)
fdb vm_op_modelled ; 6C set.cursor.char(s)   fdb vm_op_modelled ; 70/71 status.line.on/off
fdb vm_op_unimpl   ; 73 get.string(nsnnn)
commands.py: only cmdSetString, cmdTextScreen        oracle/dumps/: base-, cels-, frames- only
```
AC-8:
```
MAP_RESERVED $5300..$6000 = 3328 B   parser 954 B (P3_PARSER_TOTAL $03BA)   free 2374 B
P3_CODE_END 0x52FF vs MAP_CODE_END 0x5300 -> 1 byte spare (was 5)
```
Final checks: `hal_sync` OK ×3; `reg_discipline` 8; `gen_vm_tables --check` OK; encoding clean.

**25.2 bundled-artifact grep:** N/A — no bundled artifact; nothing shipped, no DECB image, no
`LOADER.BIN`.

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task (AC-1 NOT DONE).`

---

### 6 — Reactive deviations and route accounting

1. ★★★★★ **The task's core was not attempted, and that is the report.** AC-3/AC-4/AC-7/AC-9 depend
   on an oracle that does not exist; §2V's order says the Python model comes first. **Not a
   judgement call about method — the dispatch's premise ("the port already owns the machinery") is
   true of the planes and false of the oracle.**
2. ★★★★★ **A regression of mine was found and fixed instead** (§3.1). It was two tasks old.
3. ★★ **`vm_vms` was converted rather than deleted** though nothing reads it — removing dead state
   is a separate change [L-54], and it acquires a consumer when the VBL clock lands.

**Route accounting.** I proposed no route and claim no text work. ★★★★ **What I asserted in P6.12
and this task disproved: "the nine titles stayed 9/9, so none of them sets time_delay to zero in the
gated window."** True of the no-input arm, false of the parser arm, and I did not run the parser arm
before writing it. ★★ **The correction is in `vm_cycle.s` at the line it affects**, not only here.

---

### 7 — Uncertainty flags  (and AC-11: what the dispatch did not anticipate)

1. ★★★★★ **The text work has no oracle.** Not a placement problem, not a byte problem — the
   evidence chain is missing its first link, and §2V says that link is built before any 6809 code.
2. ★★★★★ **My P6.12 clock change broke the parser arm for two tasks** and neither P6.12's nor
   P6.13's "every gate run" caught it, because **an arm is not a gate row.** §7 trigger 4 fires and
   the Orchestrator should re-examine both verdicts: **any parser-arm claim made in P6.12 or P6.13
   is void.**
3. ★★★★ **`have.key` was already done**; the dispatch's premise for half of AC-5 was wrong.
4. ★★★★ **p3b is at 1 byte spare** (`$52FF` against `$5300`), down from 5, because of this task's
   4-byte multiplier. **The next byte added to any file p3b includes will break the build.**
5. ★★★ **Implementing `get.string` unblocks one of three uncovered titles, not three.** Two call
   `said()` zero times in the gated window and no input script can reach them.
6. ★★★ **The VBL runaway remains unexplained** [AD-142]; only the software model moved.
7. ★★ **p3b's `PIC_NOCOUNT` absence is now six tasks old.**
8. ★★ **AC-4's trigger 2 is untested, not passed** — no key was attempted in software.

---

### 8 — Follow-up candidates

1. ★★★★★ **Build the reference's text model** (§3.4 specifies it from the pin): the two buffers,
   `drawCharacter` into the display screen only, `render_Block`'s clipped re-render as the restore,
   and the text commands promoted from `vm_op_modelled`. **That is the task that must precede the
   6809 text work**, and it needs an oracle dump to gate against — which does not exist either.
2. ★★★★★ **An oracle dump for text**, in `oracle/dumps/`, or the reference has nothing to be gated
   against and §2O.1's self-referential trap opens.
3. ★★★★ **p3b's 1 byte** — the code region needs relief before anything else lands.
4. ★★★★ **Run the parser arm in every task that touches the VM or the reference.** It is the only
   arm that exercises input, and it hid a regression for two tasks.
5. ★★★ **p3b's missing `PIC_NOCOUNT`** — sixth task naming it.

---

### 9 — User interaction during task

`None.`

---

### 10 — Candidate(s) captured this task

`None.` ★★ One is now strong enough to be worth filing and I am naming it rather than writing it
thin: **an arm is part of a gate's identity, and "every gate run" is satisfiable while an arm that
only one dispatch exercises stays broken for tasks.** It is L-85's shape one level down and it has
now cost two tasks; it belongs with the two still-unfiled candidates from P6.12 as one row.

---

### 11 — Commit

See the commit carrying this report; pushed to `origin/wip` before reporting.
