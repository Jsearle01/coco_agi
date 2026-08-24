## Form B Report — T-P0-002 — the pinned ScummVM oracle
**Class:** build (infrastructure + recon). wip.

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-24T01:10:45Z. HEAD at receipt `02b7e0b` (wip) → **at report `f9c11e8`**, pushed.
`git status --porcelain` at report → **clean** (the `?? mame-idioms-addendum.md` line from
T-P0-001 is gone; §3's ruling tracked it).

---

## ★ §4 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

### 4.1 Locations and toolchain

```
coco_agi        branch wip   HEAD 02b7e0bb025d0889d20c9b64ced847b337352ad9  (at receipt)
POP3_port       branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3  branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
```

Both sibling refs are **unchanged from T-P0-001**, so every sibling figure in that report still
stands at the ref it was measured at (§2S.3).

| check | measured |
|---|---|
| ScummVM clone anywhere under `C:\Projects\` | ★ **ABSENT.** Searched `C:\Projects` to depth 2, case-insensitive. Nothing. Cloned fresh this task. |
| C++ toolchain | ★★ **NONE ON THE WINDOWS HOST.** See below. |
| SDL2 dev libraries | ★★ **ABSENT EVERYWHERE** — Windows host and WSL both. |

★★ **The Windows host cannot build C++ at all.** Probed for `gcc`, `g++`, `clang`, `clang++`,
`cl`, `cc`, `make`, `cmake`, `ninja`, `pkg-config`: **every one absent.** No MSYS2
(`C:\msys64` absent), no MinGW install, no Visual Studio directory. The `git` on PATH is
Git-for-Windows' `/mingw64/bin/git`, which **bundles no compiler** — a detail worth stating
because a `mingw64` path on `PATH` looks like a toolchain and is not one.

**WSL2 Ubuntu is present and is the only viable build host:**

```
Linux JComputer 6.6.87.2-microsoft-standard-WSL2 x86_64
g++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0 · GNU Make 4.3 · git · python3 · curl
2 CPUs · 950 GB free · git network OK
SDL2: /usr/include/SDL2 absent, no libsdl2 packages
```

★ **§8.1's trigger did not fire, and the reason is specific rather than a judgement call.** That
trigger covers *"the ScummVM build proves hostile — SDL, MSVC vs mingw, missing deps"* and
directs that WSL is an Orchestrator decision. **No fight occurred and no dependency was
installed:** ScummVM ships a **`null` backend** (`backends/platform/null`, `configure:4094`)
which needs no SDL at all, and it configured and built first try. §4.1 of the dispatch
explicitly asks which toolchain is available *"(MSYS2/mingw, MSVC, WSL)"*, so probing WSL is
the grep, not a deviation. **Nothing was installed into WSL** — the toolchain was already
complete. Had SDL2 been required, this would have stopped.

### 4.2 ★★ The design spec's five ScummVM citations, verified AT THE PIN

Pin: **commit `9d9b9e93108a276c551aeffa390169ccc5148e15`**, tag `v2.9.1`.

| # | claim | cited | **found** | verdict |
|---|---|---|---|---|
| 1 | play area **160×168** | `graphics.h:29-31` | `graphics.h:29-30` — `SCRIPT_WIDTH 160`, `SCRIPT_HEIGHT 168` | ✅ **VALUE CONFIRMED** |
| 2 | priority screen **160×168** | `graphics.h:116-117` | `graphics.h:116-117` — exact | ✅ **VALUE CONFIRMED** |
| 3 | **319** opcode table entries | `opcodes.cpp` | **319**, but see ★★ below | ⚠️ **value confirmed, SCOPE MISLEADING** |
| 4 | **14 bands × 12 rows**, `<4` clamped to 4 | `graphics.cpp:1295-1303` | `graphics.cpp:1295-1303` — exact | ✅ **VALUE CONFIRMED** |
| 5 | `setPriorityTable` override exists | `graphics.cpp:1305-1313` | `graphics.cpp:1305-1315` | ✅ **CONFIRMED** |

**No changed VALUE was found, so §8.3 did not fire.** Line drift was ±1–2 and is unremarkable.

Citation 4 verbatim, because it is the one design §3.5 turns into a 168-byte table:

```cpp
1295  void GfxMgr::createDefaultPriorityTable(uint8 *priorityTable) {
1296      int16 yPos = 0;
1298      for (int16 priority = 1; priority < 15; priority++) {     // 14 bands (1..14)
1299          for (int16 step = 0; step < 12; step++) {             // 12 rows each
1300              priorityTable[yPos++] = priority < 4 ? 4 : priority;   // <4 clamped to 4
```

★ **14 × 12 = 168 = `SCRIPT_HEIGHT` exactly** — the table fills the play area with nothing left
over, which is why §2F.4's "168-byte lookup table, not a computation" is the right shape.
Corroborated by `graphics.h:137`: `uint8 _priorityTable[SCRIPT_HEIGHT];`.

#### ★★ Citation 3 — the number is right and what it counts is not what the spec implies

`opcodes.cpp` holds **four** tables, not one:

```
opCodesV1Cond    lines  34-52     17 entries
opCodesV1        lines  54-154    99 entries
opCodesV2Cond    lines 156-177    20 entries
opCodesV2        lines 179-363   183 entries
                                 --- 319 total
```

**319 is the sum of all four.** That conflates two independent axes:

1. **Two interpreter-version families.** V2 (`183 + 20 = 203`) and V1 (`99 + 17 = 116`) are
   selected at runtime — `opcodes.cpp:381-389` picks one pair — and a given game uses **one**.
2. **Two dispatch classes.** `*Cond` are the **test/condition** opcodes and the others are
   **commands**; they are separate opcode spaces, dispatched differently. They are not
   interchangeable entries in one table.

★ **A CoCo3 interpreter targeting AGI v2/v3 needs 203, not 319** — and even 203 overstates it,
because `opCodesV2`'s own comments mark entries as *"Apple IIGS only"* and *"AGI3+ only starts
here"* (`opcodes.cpp:355-362`). **The value is confirmed; quoting it as "319 opcodes to
implement" would overstate the target by ~57%.** Reported prominently per §8's rule that a
figure which does not hold outranks the dispatch — here the figure holds and its *meaning* does
not.

#### ★ Two CLAUDE.md §2H figures do not hold at the pin

§2H says *"AGI's reference is 6,369 lines of C implementing 319 opcodes — `op_cmd.cpp` alone is
2,540."* Measured at the pin:

```
op_cmd.cpp                 2,483 lines   (§2H says 2,540)
engines/agi *.cpp          23,752 lines
engines/agi *.cpp + *.h    30,066 lines  (§2H says 6,369)
```

★ **This does not weaken §2H — it strengthens it.** The engine is roughly **5× larger** than the
figure quoted, so *"a first-mechanism read of it is very easy to make and hard to catch"* is
more true than stated, not less. Surfaced as a doc-delta for the Orchestrator (§8.3), not
edited (§2D).

### 4.3 ★★ M-05 — YES. ScummVM addresses row 24, by four independent mechanisms

**AD-01 has a real gap.** At 192 lines the CoCo3 has `8 status + 168 play = 176`, leaving
**16 px = two 8-px text rows (22, 23)**. ScummVM's text model is **25 rows, 0–24**
(`text.h:68`, `FONT_ROW_CHARACTERS 25`), and **row 24 is reachable four different ways:**

| # | mechanism | evidence |
|---|---|---|
| 1 | `text.screen` clears **through 24** unconditionally | `op_cmd.cpp:1823` — `clearLines(0, 24, ...)` |
| 2 | `get.string` **explicitly permits** row 24 for an input field | `op_cmd.cpp:2003` — `if (stringRow < 25) charPos_Set(stringRow, ...)`, and `stringRow` is an **opcode parameter** |
| 3 | `configure.screen` sets promptRow/statusRow from LOGIC params, **unclamped** | `op_cmd.cpp:1802-1811` |
| 4 | `clear.lines` takes both row bounds from the game | `op_cmd.cpp:2144-2156` |

★★ **Mechanism 4 carries a NAMED REAL GAME.** ScummVM's own comment at `op_cmd.cpp:2150`:

```cpp
// Residence 44 calls clear.lines(24,0,0), see Sarien bug #558423
```

**That is a shipped AGI game addressing row 24**, recorded in the reference itself. M-05 is not
theoretical.

★ **And the clamp that does exist permits 24 rather than forbidding it:** `charPos_Clip`
(`text.cpp:111-114`) is `CLIP<int16>(row, 0, FONT_ROW_CHARACTERS - 1)` = **[0, 24]**.

★ **A disabled clamp confirms the intent.** `op_cmd.cpp:1999-2001` carries commented-out code:

```cpp
// Workaround for SQLC bug.  See Sarien bug #792125 for details
//	if (promptRow > 24)
//		promptRow = 24;
```

**ScummVM considered clamping to 24 and switched it off.** The default prompt row is 22
(`cycle.cpp:346`), which fits AD-01's two rows — **but 22 is only a default, and three of the
four mechanisms above are driven by game data, not by the engine.**

★★ **§2.1 DECLARATION — this one matters.** `clearBlock` (`text.cpp:629-631`) says in its own
comment: *"Sierra didn't do clipping of the coordinates, we do it for security and b/c there
actually are some games, that call commands with invalid coordinates."* **The clipping is a
ScummVM NORMALISATION, believed NOT original.** So the *bound* of 24 is ScummVM's; what the
original did with an out-of-range row is unknown and is not answered by this read. **What is
believed ORIGINAL is that games issue row-24 addresses at all** — Residence 44 does, and that
is a fact about the game data, not about ScummVM.

---

### 1 — Summary

**The oracle is pinned, instrumented, and building; and the four acceptance criteria that need a
game to run are BLOCKED on the game-set pin, which §2Q makes Jay's to supply.**

Delivered: CLAUDE.md v1.1 committed after a superset check that found **exactly the six declared
supersessions and no others**; both D-11 rulings; ScummVM pinned at **`9d9b9e93` (v2.9.1)** and
built **headless, AGI-only, with no SDL** via `--backend=null`; 81 lines of instrumentation as
two patches that **apply clean to a pristine tree at the pin and build**; and §4.2/§4.3 answered
from the code.

★★ **The finding that changes a settled decision is §4.3: ScummVM addresses text row 24, and a
named commercial game — Residence 44 — actually does it.** AD-01's 192-line layout has two text
rows where AGI has three. That is now evidence, not a worry.

★ **The defect found in my own work is the one worth reading (§4, AC-10).** The patch files were
generated, committed, and verified to apply — twice, cleanly. Every check passed, and every
check ran against the copy in my working tree, which is **the one copy that never passes through
the checkout filter.** Under the inherited `* text=auto` rule a fresh clone rewrites them CRLF,
and `git apply` then fails *on every hunk*. Found only by deleting the file and restoring it
from git to see what a clone actually produces. **AC-10 would have been false on any machine but
this one.** Fixed by one `.gitattributes` line and re-verified.

**AC-7, AC-8, AC-9 are BLOCKED — nothing is estimated** (§5.5, §2P, §2Q).

---

### 2 — Files modified

Explicit-path staging throughout (§2E). Three commits.

**`0284093` — v1.1 and the D-11 rulings**
- `CLAUDE.md` — **v1.0 → v1.1, committed as provided, not edited** (§2D).
- `mame-idioms-addendum.md` — **now tracked** (D-11 ruling 1).
- `harness/tools/fixtures/rule_fixture.s` — **now tracked** (D-11 ruling 2).
- `harness/tools/fixtures/run_rule_demo.sh` — new; the standing re-check.

**`146fc4b` — the oracle**
- `oracle/scummvm.pin` — new; commit, tag, both clone recipes, configure line, build command,
  host constraints, and the **`[game-set]` block recording what is blocked and what unblocks it.**
- `oracle/patches/0001-oracle-room-dump.patch` — new; `graphics.h`, `graphics.cpp`, `picture.cpp`.
- `oracle/patches/0002-oracle-vm-state-dump.patch` — new; `cycle.cpp`.
- `harness/tools/oracle_dump.sh` — new; the runner, written and reviewable, **not yet runnable.**

**`f9c11e8` — the CRLF fix**
- `.gitattributes` — `*.patch` / `*.diff` pinned to LF, with the measurement in the comment.

**Outside the repo, and NOT committed** (§2Q.1 — the oracle is pinned, never vendored):
`C:\Projects\scummvm` (reading clone) and `~/scummvm` inside WSL (build clone), both at
`9d9b9e93`. **No sibling repository was modified.**

---

### 3 — Reasoning

#### 3A — §2 CLAUDE.md v1.1: the superset check, and why a naïve diff would have lied

Run at **normalised EOL**, as the dispatch warns (§2, my own T-P0-001 §7.5): `* text=auto` means
the working copies differ by CRLF while the blobs match, and a byte diff reports drift that is
not there. Multiset line membership, so a line appearing twice must appear twice.

**Exactly six substantive v1.0 lines are absent from v1.1**, and all six are declared:

```
v1.0:2    ## Working Agreement v1.0 (forked from POP3_port CLAUDE.md v1.1)
v1.0:3    **Version:** 1.0
v1.0:433  through an `equ` alias** — `CEL_MMU`, `BANK_MMU`, `SAM_SLOW/FAST`, **`PALETTE`**, …
v1.0:434  `FF90`–`FF95` — **which are the majority of the real ones.**
v1.0:440  `equ` definition, and carries a load/store mnemonic* — **with aliases resolved …
v1.0:441  including `+n` offsets.** Measured under it: **POP 59, Karateka 8.**
```

The dispatch's table lists four rows, two of which are *pairs* — 1 + 1 + 2 + 2 = **6**. Exact
match, **no seventh line.** §8.5 did not fire.

Confirmed that the superseding text carries the corrections rather than merely replacing the
lines: `TC_MMU` present at `v1.1:440`, and part 4 reads **load/store/modify** at `v1.1:447` with
the correction's reasoning at `v1.1:450-451`.

#### 3B — ★★ Why `--backend=null` is a §2O.1 decision and not a convenience

It began as the answer to "there is no SDL2 anywhere", and it is the right answer for a better
reason. **§7 forbids anything we write from participating in producing the baseline**, and §2O.1
forbids a self-referential one. The dumps come from `_gameScreen` and `_priorityScreen` — the
engine's own 160×168 buffers. A build with **no display backend at all cannot route a baseline
through a scaler, a palette, or an aspect correction**, because those code paths are not linked.

The instrumentation dumps those two buffers and **deliberately does not dump `_displayScreen`**
(320×200 or 640×400), which is a *rendering* of them. Diffing our renderer against ScummVM's
renderer-of-a-renderer would put ScummVM's upscaler inside the baseline.

**Verified rather than assumed that the buffers are untransformed:** `getColor(x,y)` is
`_gameScreen[y * SCRIPT_WIDTH + x]` (`graphics.cpp:502-506`) — a pure index, no transformation —
and the buffers are `calloc(SCRIPT_WIDTH * SCRIPT_HEIGHT)` = **26,880 bytes, flat row-major**
(`graphics.cpp:200-202`). So a raw `write()` of the buffer *is* the engine's own bytes.

#### 3C — ★★ §2H's three checks, applied to choosing the instrumentation seam

1. **Is there a SECOND mechanism serving a different object class?** ★ **Yes, and it moved the
   seam.** The obvious hook is `PictureMgr::drawPicture()` — and it is **one of two decoders**:
   `drawPicture_AGI256()` is a separate one for a different picture format, and
   `decodePictureFromBuffer()` is a third entry used by PreAGI games. Hooking the decoder would
   have silently missed AGI256 and produced an oracle with a hole in it that no test would show.
   **The seam is `decodePicture()`** (`picture.cpp:764`), above the fork, which catches both.
   *(`decodePictureFromBuffer` remains uncovered and is flagged in §7.4.)*
2. **Name the routine that CALLS it.** Decisive twice. **For the picture seam:** the callers are
   four opcode handlers — `op_cmd.cpp:1138, 1155, 1223, 2329` — so hooking any single opcode
   would have missed three call sites, while `decodePicture` catches all four. **For M-05:** the
   callers of the row-24 mechanisms are `cmdConfigureScreen`, `cmdGetString`, `cmdClearLines`,
   `cmdTextScreen` — every one an **opcode handler**, meaning *the caller is the game's LOGIC
   script, not the engine.* ★ **That is why M-05 cannot be closed by reading ScummVM alone:
   whether row 24 is used is a property of GAME DATA.** It can only be settled per-game — which
   makes it another thing gated on the §2Q pin.
3. **Grep prior reports for the same subsystem.** Only T-P0-001 exists. Its §7.3 flagged the
   pointer-load class as uncharacterised for AGI; unrelated to this task's subsystems, and no
   contradiction. §2H's discipline was applied to reading ScummVM instead, per §2H's own note
   that it *"applies verbatim to reading ScummVM."*

#### 3D — The VM-state seam, and the one judgement call in it

`AgiEngine::interpretCycle()` (`cycle.cpp:157`) is the interpreter cycle. The dump is taken at
**cycle ENTRY** — the state the cycle is about to act on — rather than at exit. Either is
defensible; entry is unambiguous (exit has multiple paths) and makes "cycle N" mean "before
cycle N ran". **Stated because it is a convention the CoCo3 side must match**, and a silent
choice here would surface later as an off-by-one-cycle diff that looks like a logic bug.

Emitted as one fixed-width hex line per cycle, `flags` (32 bytes = 256 flags) then `vars` (256
bytes), from `AgiGame::flags[]` and `AgiGame::vars[]` (`agi.h:383-384`) — **the engine's own
storage, verbatim, not a reconstruction.** A line diff then makes the first divergent cycle the
first differing line.

#### 3E — ★ The patch CRLF defect, and why it is a method finding rather than a typo

The patches passed `git apply --check` twice. **Both runs read the file in my working tree.** The
repository's inherited `* text=auto` rewrites text on checkout, so the artifact a *clone* gets is
CRLF, and `git apply` matches context lines byte for byte. Measured, by deleting the file and
restoring it from git:

```
error: while searching for:
	return _priorityScreen[offset];?      <-- the '?' is the stray CR
error: patch failed: engines/agi/graphics.cpp:514
error: engines/agi/graphics.cpp: patch does not apply
```

★★ **The structural point: my working copy is the only copy in existence that never passes
through the outbound filter, so testing it proves the least of any available test — and the more
carefully I verified locally, the more confident I became about the least informative form.**
The fix mirrors a rule already in the same file: POP forces `*.bat` to **CRLF** because cmd.exe
needs it; this forces `*.patch` to **LF** because `git apply` needs it. **Same hazard, opposite
direction, and the existing rule was evidence the hazard was live rather than evidence it was
handled.** Captured as the task's candidate (§10).

#### 3F — Sibling and reference claims, with ref and scope (§2S.3)

All ScummVM file:line citations are at **commit `9d9b9e93` (tag v2.9.1)**, from the reading clone
at `C:\Projects\scummvm`. Sibling figures in AC-3 are at **POP `wip` `282a65c`** and **Karateka
`wip` `072ddcf`**, unchanged from T-P0-001, over the scopes named in §5.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** — CLAUDE.md v1.1 committed byte-identical at the blob layer:
  provided file SHA-1 `4b925643d8822e16f06f12e29877d795c525247e`; **committed blob content SHA-1
  `4b925643d8822e16f06f12e29877d795c525247e`** — identical. Superset output verbatim in §3A:
  **6 substantive absences, all six declared, none other.** ✅ **PASS.**
- **AC-2 [class: byte-comparable]** — `mame-idioms-addendum.md` tracked; `rule_fixture.s` tracked
  at `harness/tools/fixtures/`; `sh harness/tools/fixtures/run_rule_demo.sh` runs from the repo
  root and exits 0, including the negative control. Verbatim in §5. ✅ **PASS.**
- **AC-3 [class: byte-comparable]** — regression, re-run after every change this task:
  `coco_agi src/engine/**` = **0**; POP = **59** at `282a65c`; Karateka = **8** at `072ddcf`.
  All three `--expect` assertions rc=0. **The instrument has not moved.** ✅ **PASS.**
- **AC-4 [class: byte-comparable]** — `oracle/scummvm.pin` records commit, tag, **tag-object SHA
  (they differ — see §7.1)**, both clone recipes, the configure line, the build command, and the
  host constraints that determine where the build must happen. ★ **Reproducibility corroborated
  from outside the file: the built binary self-reports `ScummVM 2.9.19d9b9e93`**, embedding the
  pinned commit. ✅ **PASS.**
- **AC-5 [class: state-comparable]** — five citations verified at the pin, each reported as
  found (§4.2). Four exact; the fifth (319) value-confirmed with its **scope corrected**.
  ✅ **PASS**, with the §4.2 scope finding.
- **AC-6 [class: state-comparable]** — M-05 answered **YES**, four mechanisms, file:line for
  each, plus a named game (Residence 44) and a §2.1 normalisation declaration (§4.3).
  ✅ **PASS.**
- **AC-7 [class: byte-comparable] — ❌ BLOCKED.** The instrumentation is written, compiled and
  **linked** (`nm` output in §5), but a room dump requires a PICTURE resource, which requires a
  game. **No AGI game data exists on this machine.** The mechanism is one command away
  (`harness/tools/oracle_dump.sh`); the *evidence* is not producible. **Nothing estimated.**
- **AC-8 [class: state-comparable] — ❌ BLOCKED.** Same cause. `oracleDumpVmState` is linked and
  its `vmstate.txt` format string is in the binary, but there is no game to cycle.
- **AC-9 [class: suite] — ❌ BLOCKED**, as the dispatch's §5.5 anticipates. Searched
  `C:\Projects`, `C:\Games`, Documents, Downloads and Desktop to depth 4 for `VOL.*`, `*VOL.0`,
  `LOGDIR`, `PICDIR`, `VIEWDIR`, `AGIDATA*`: **nothing.** ★ **Not estimated.** What is needed is
  in `oracle/scummvm.pin [game-set]`: one or more AGI game directories plus Jay's ruling on the
  pinned set, each identified by **title · interpreter version · platform · release**.
- **AC-10 [class: byte-comparable]** — **PARTIAL, and the part that passed is the part that
  nearly failed.** `git apply --check` **rc=0** and `git apply` **rc=0** against a tree at the
  pin with **zero tracked modifications**, then `make -j2` **rc=0** and the instrumentation
  symbols present in the linked binary. ★ **This is what the CRLF fix bought** — before it, the
  same check against the *as-cloned* form failed on every hunk (§3E). **The final clause —
  "AC-7 reproduces the same sha256" — is BLOCKED with AC-7.** ⚠️ **PARTIAL.**
- **AC-11 [class: suite]** — one candidate captured and pushed. §10. ✅ **PASS.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1a — `reg_discipline.py` (AC-3), verbatim:**

```
$ python harness/tools/reg_discipline.py --expect 0                      # coco_agi
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
[reg-discipline] OK -- measured 0, matching the independent figure.          rc=0

$ ... --roots src --exclude src/hal src/harness --expect 59                # POP 282a65c
[reg-discipline] OK -- measured 59, matching the independent figure.         rc=0

$ ... --roots src --exclude src/hal --expect 8                             # Karateka 072ddcf
[reg-discipline] OK -- measured 8, matching the independent figure.          rc=0
```

**25.1b — the fixture demonstration from a clean checkout (AC-2):**

```
$ sh harness/tools/fixtures/run_rule_demo.sh
[explain] aliases in scope: CEL_MMU=$FFA6, SAM_FAST=$FFD9
    3  P1     * P1 CASE: this whole line is a comment ...  rejected -> P1 full-line comment
    6  P3     CEL_MMU  equ  $FFA6                          rejected -> P3 equ definition
   10  P2     nop                                          rejected -> P2 register only in the inline comment
   12  P4     fdb  $FFA2                                   rejected -> P4 no load/store/modify mnemonic
   14  P4     clra                                         rejected -> P4 no load/store/modify mnemonic
   22  ACCESS sta  CEL_MMU+2                               COUNTED  -> $FFA8
   28  ACCESS sta  $FFA6                                   COUNTED  -> $FFA6
[reg-discipline] 8 register access(es) in 1 file(s) over 7 register(s).
[reg-discipline] OK -- measured 8, matching the independent figure.
OK: --expect 7 exited non-zero as required.                              runner rc=0
```

**25.1c — the ScummVM build, verbatim:**

```
$ ./configure --backend=null --disable-all-engines --enable-engine=agi
Creating config.h / config.mk                                          configure rc=0
  config.mk:  BACKEND := null
              ENABLE_AGI = STATIC_PLUGIN        (all other engines commented out)

$ make -j2
    LINK     scummvm
    DWP      scummvm.dwp                                                    make rc=0
-rwxr-xr-x 1 jaysearle jaysearle 31225432 scummvm
ScummVM 2.9.19d9b9e93 (Aug 23 2026 21:06:19)      <-- pinned commit, embedded in the binary
```

**25.1d — AC-10, patches against a tree at the pin, verbatim:**

```
=== HEAD (must be the pin) ===
9d9b9e93108a276c551aeffa390169ccc5148e15
=== tracked modifications before apply (must be none) ===
(none)
=== git apply --check (dry run) ===
Checking patch engines/agi/graphics.cpp...
Checking patch engines/agi/graphics.h...
Checking patch engines/agi/picture.cpp...
Checking patch engines/agi/cycle.cpp...                                    check rc=0
=== git apply ===                                                          apply rc=0
 engines/agi/cycle.cpp    | 33 +++++++++++++++++++++++++
 engines/agi/graphics.cpp | 34 ++++++++++++++++++++++++
 engines/agi/graphics.h   |  6 ++++++
 engines/agi/picture.cpp  |  8 ++++++++
 4 files changed, 81 insertions(+)          <-- 0 deletions; under §8.4's ~100-line trigger
=== rebuild ===
    LINK     scummvm                                                        make rc=0
ScummVM 2.9.1dirty
```

★ Note `2.9.19d9b9e93` (pristine) vs `2.9.1dirty` (instrumented) — **a free marker
distinguishing an oracle build from a stock one.**

**25.1e — the instrumentation is LINKED, not merely compiled:**

```
$ nm -C scummvm | grep oracleDump
000000000044b742 T Agi::GfxMgr::oracleDumpScreens(short) const
0000000000445cad t Agi::oracleDumpVmState(unsigned int, unsigned char const*, unsigned char const*)
$ strings scummvm | grep -E '^pic%03d|^vmstate.txt'
vmstate.txt
pic%03d.%s.bin
```

**25.1f — the CRLF defect, measured (§3E):**

```
$ rm oracle/patches/0001-*.patch && git checkout -- oracle/patches/    # what a clone gets
... ASCII text, with CRLF line terminators
$ git apply --check 0001-oracle-room-dump.patch
error: patch failed: engines/agi/graphics.cpp:514
error: engines/agi/graphics.cpp: patch does not apply     (all three files failed)

# after adding `*.patch text eol=lf`:
... ASCII text                                            (no CRLF)
apply --check rc=0
```

**25.2 — bundled-artifact grep:** **N/A.** The built `scummvm` binary is an oracle tool that
lives outside the repository and is never shipped or committed (§2Q.1); no coco_agi artifact was
produced this task. The equivalent check — that the pinned commit is embedded in the built
binary — is 25.1c.

**25.3 — operator-runtime-smoke:** **N/A — no CoCo3 visual surface this task.** No target code
exists. The room dumps are byte-comparable data and would not be an eye gate even once produced
(§2O, §3).

---

### 6 — Reactive deviations and route accounting

1. **Built in WSL2, not on the Windows host.** Forced: the host has no C++ toolchain at all
   (§4.1). **Nothing was installed** — WSL's toolchain was already complete, and `--backend=null`
   removed the SDL2 requirement, so §8.1's "do not fight a toolchain" was honoured rather than
   worked around.
2. **`--backend=null`** is not spelled out in §5.3, which specifies only
   `--disable-all-engines --enable-engine=agi`. Added, for the §3B reason.
3. **`.gitattributes` modified** — the first divergence from POP's verbatim copy, which
   T-P0-001 AC-3 established. It **extends** the policy to `*.patch`/`*.diff`, file types POP
   does not have, and contradicts no POP rule. Flagged because §2G makes divergence from a
   sibling a reportable act.
4. **`harness/tools/oracle_dump.sh` was written** although the ACs it serves are blocked, so
   that "blocked" means one command away rather than unstarted.
5. **Pin is a release tag rather than a master commit** (§5 leaves the choice open). Reasoning
   recorded in the pin file.

**ROUTE ACCOUNTING.** No route was proposed to Jay or the Orchestrator during this task, so there
is no proposed-route/implementation gap. **What this change contains** is §2's file list and the
five items above. **What it does NOT contain, and I am saying so rather than leaving it to the
diff:** no room dump, no VM-state dump, no game-set pin, no M-01 measurement — all four blocked
on game data, none attempted, none estimated. **Explicitly not done per §12:** no `src/hal/`, no
`hal_sync_check.py` edit, no `build.bat`, no CoCo3 code, no offline renderer, no VOL/DIR parser,
no owner-row ratchet, no game data committed, and P5.17 §3A's table left uncorrected.

---

### 7 — Uncertainty flags

1. **★ The pin has two SHAs and confusing them will read as drift.** `v2.9.1` is an **annotated
   tag**: `git ls-remote` reports the **tag object** `4f4258679fd50dac40ed86ad241ab295bb9ebfa6`,
   while `git rev-parse HEAD` reports the **commit** `9d9b9e93…`. **The commit is the pin.** Both
   are in `scummvm.pin` with the `verify` command that relates them.
2. **★★ AC-7's byte-stability across runs is UNVERIFIED, and it is the assumption the method
   rests on.** §8.2 makes non-determinism a consult-first finding. **I could not test it** — no
   game. A picture render *should* be a deterministic function of its PICTURE resource, but
   ScummVM has an RNG (`cmdRandom`) and version/platform-conditional paths, and "should" is not
   evidence. **The first thing to run when game data arrives is the same room twice.**
3. **`decodePictureFromBuffer` is NOT instrumented.** It is a third entry to picture drawing,
   used by PreAGI titles (Mickey, Winnie, Troll). Out of scope for AGI proper and named here so
   its absence is a decision rather than an oversight — the same courtesy §2H asks for.
4. **The VM-state dump is entry-of-cycle** (§3D). The CoCo3 side must match this convention or
   every diff is off by one cycle.
5. **The oracle runs one interpreter-version family at a time** (§4.2). Which one is selected
   depends on the game, so a state-diff is only meaningful once §2Q's pin names the version —
   another dependency on the blocked game set.
6. **CLAUDE.md §2H's line-count figures do not hold** (§4.2): `op_cmd.cpp` 2,483 not 2,540, and
   the engine is 30,066 lines not 6,369. Doc-delta for the Orchestrator; §2H's *argument* is
   strengthened, not weakened.
7. **`git apply --check`'s exit code was unreliable in one probe** (reported rc=0 while printing
   "patch does not apply"), which is why §5's AC-10 evidence quotes the *messages* and the final
   verification was re-run standalone. Noted so nobody trusts that rc in a future script.
8. **`scummvm.ini` is created by the binary in the build clone.** Untracked, outside coco_agi,
   harmless — stated so a later reader does not read it as tree dirt.

---

### 8 — Follow-up candidates

1. ★★ **Unblock the oracle: Jay supplies the game set** (§2Q). This gates AC-7, AC-8, AC-9,
   AC-10's final clause, design §11.1's M-01, and every state-diff the project will ever run.
   **It is the critical path.** Needed per title: interpreter version, platform, release.
2. ★★ **AD-01 needs re-deciding in light of §4.3.** Row 24 is addressable four ways and a named
   game uses it. Options: accept truncation, scroll, or find 8 more lines. **A decision, not a
   measurement** — and it wants making before picture/text work starts.
3. **First run when unblocked: the same room twice** (§7.2), before anything is built on the
   dumps.
4. **Orchestrator doc-deltas:** §2H's line counts (§4.2), and whether the design spec's "319
   opcodes" should read 203 with its scope stated.
5. **Instrument `decodePictureFromBuffer`** if PreAGI ever enters scope (§7.3).
6. **Consider whether `*.patch text eol=lf` should be back-ported to POP and Karateka** — neither
   has `.patch` files today, so this is pre-emptive and is a separate explicit task per §2G, not
   an automatic sync.

---

### 9 — User interaction during task

**None.** No question was put to Jay and no guidance was received. ★ **`CLAUDE (1).md` appeared
in the working directory mid-task** — after my first `git status` showed it absent and before the
second showed it present. It is v1.1 and I treated it as the dispatch's §2 artifact, verified it
by superset check before committing, and removed the duplicate filename. **That is an inference
about a file appearing on disk, not a communication**, and it is recorded here as such.

No consultation trigger fired. All five were evaluated: §8.1 (§4.1 — no toolchain fight, nothing
installed), §8.2 (untestable, flagged §7.2), §8.3 (no changed value), §8.4 (81 lines, under
~100), §8.5 (exactly six supersessions).

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-08-24-check-the-artifact-in-the-form-the-recipient-receives.md`

*Verify an artifact in the form the RECIPIENT will receive it, not the form you authored it in —
for anything that passes through a transformation on the way out, the author's working copy is
the one form guaranteed never to expose the defect, so testing it proves the least of any
available test.* Captured at its first instance (§3E), single-instance `live` row,
`initiator: executor`, `instance_count` verified equal to `len(instance_history)`.

★ The row links `[[a-matching-total-is-not-a-matching-measurement]]` (T-P0-001's candidate) and
notes for the reconciler that both may belong under one heading about **what a green check
actually licenses you to say** — there the comparison was too coarse, here it was of the wrong
artifact; in both the check ran, passed, and was reported honestly.

Pushed `744af1e..1808196`, fire-and-forget. No existing pool entry was read for content or
edited (§2C).

---

### 11 — Commit

`f9c11e8adb3ff5a38c426bedc6f2e836a4a982bc` — three commits this task:

```
f9c11e8  P0.2b .gitattributes: force LF on *.patch (oracle reproducibility)
146fc4b  P0.2  oracle: pinned ScummVM, room and VM-state dump instrumentation
0284093  P0.2a CLAUDE.md v1.1 and the two D-11 rulings
```

Pushed to `origin/wip` before this report. This report is a fourth commit on `wip`.
