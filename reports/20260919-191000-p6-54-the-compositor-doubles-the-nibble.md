## Form B Report — T-P0-109 / P6.54 — The compositor doubles the nibble; Graham is solid
**Class:** integration (§4A).  wip.  Descends from `1e853fb`.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 19:10 (HEAD 1e853fb, wip). Two `src/harness/` files, **four instructions**; two
harness tools.

### 1 — Summary

★★★★★ **Jay: *"he is solid as are the flags... colors look correct."*** Three tasks after the first
sprite reached a screen, it is a figure rather than a comb.

★★★★★ **The format question is settled by the oracle's own structure, and `comp`'s reference was
right all along.** `graphics.h:116,119` keeps **`_gameScreen`** — *"160x168 - screen, where the
actual game content is drawn to"* — apart from **`_displayScreen`** — *"320x200 or 640x400 ... which
is then copied to framebuffer"*. ★★★★ **Our instrumentation dumps `_gameScreen`**
(`getGameScreenForOracle`), so every reference this project owns is one byte per pixel, raw index.
**The packing is ours, at the display boundary, exactly where the oracle puts it.**

★★★★★ **And `composite.s` was the only writer of five that did not pack** — the invariant is
written down twice in our own tree.

★★★ **The fix is four instructions.** `comp_probe.bin` **967 B `39F5D105`**, byte-identical.

### 2 — Files modified
- `src/harness/composite.s` — `-DVIS_DOUBLED` in `co_put_visual`, `-DCOMP_FAULT_RAW_VIS`.
- `src/harness/p3b_probe.s` — defines `VIS_DOUBLED`.
- `harness/tools/p3b_run.lua` — the nibble census; `p3b_show.ps1` — `-RawVis`;
  `p3b_arms_check.ps1` — re-baselined.

### 3 — Pre-dispatch grep (C-13)

**§3(1)** Seven arms and every probe at P6.53's figures ✔. `comp_probe.bin` **967 B `39F5D105`**.

**§3(2) — ★★★★★ EVERY VISUAL-PLANE WRITER AND ITS FORMAT. This census is the task's subject and it
found the invariant already stated, twice.**

| writer | what it stores | packed? |
|---|---|---|
| `pic_core.s:113` `put_pixel` | `scr_dbl` — `:91` *"identically `(scr_color & 15) * 17`"* | ✔ |
| `pic_fill.s:251` (read side) | `anda #$0F` — ★★★★ *"either nibble; **equal by construction**"* | ✔ |
| `p3b_probe.s` `p3_clear_planes` | `ldd #$FFFF` — ★★★★ *"visual 15, **both nibbles (the pixel doubling)**"* | ✔ |
| `text.s` `txt_blit` | `ccol * TXT_VW` = **4 bytes per 8-pixel char** — the full 320-px resolution | ✔ |
| ★★★★★ **`composite.s` `co_put_visual`** | ★★★★★ **`co_col`, raw** | ✘ |

★★★★ **Two of the four correct writers say the rule out loud**, and one of them (`pic_fill`) depends
on it to READ. **The compositor broke an invariant its own neighbours document.**

**§3(3)** `picgate.py:34-42` unpacks the CoCo3 buffer and its header states *"the CoCo3's 4bpp
buffer is UNPACKED to indices and those are compared... **nibble agreement is verified before either
half is trusted**"*. `comp`'s reference is one byte per pixel, raw. ★★★ **The two gates model
different things and both are right about what they test** — §4A(2).

**§3(4)** `text.s`'s glyph blit is packed-aware at 2 px/byte, and its panel has been eye-gated
readable. ★★ **Third independent data point, and it is the one that settles the framebuffer's
geometry**: 160 bytes per row = 320 screen pixels at 4 bpp.

### 4A — ★★★★★ The two questions, answered before any code

**(1) What does the oracle's screen hold?** ★★★★ **One byte per pixel, colour indices** — and the
oracle keeps the display format in a *separate buffer*, copied at the boundary [`graphics.h:116,119`,
tier 3]. **No stop condition: the oracle's game screen is not packed.** §1.1's expectation holds.

**(2) Why does `pic` pass at 45/45 while writing doubled bytes?** ★★★★★ **Because `picgate.py`
models the packed plane explicitly and checks the nibbles agree** — it is the only gate in the tree
that knows a plane byte carries a pixel twice. ★★★ **So `pic` and `comp` do NOT disagree about a
shared artefact: they gate two different probes whose planes are genuinely different objects.**
`comp_probe`'s is scratch in `_gameScreen` form; `pic_probe`'s is a CoCo3 framebuffer.

★★★★ **I judged this NOT to be §6's "references disagree" stop**, and the reason is that the fix
touches neither reference: the packing becomes conditional on the plane being a display, which is
the distinction the oracle itself draws. **Said plainly because §6 starred it at five.**

### 4B — The write
```
                ifdef   VIS_DOUBLED
                ldb     co_col
                lda     #17
                mul                     ; B = c * 17 = the colour in both nibbles
                stb     ,x
                else
                lda     co_col          ; ★ the flat path, instruction for instruction
                sta     ,x
                endc
```
★★★ **`c * 17` is the documented form**, not `(c<<4)|c`: `pic_core.s:91` says `scr_dbl` *"is
identically `(scr_color & 15) * 17`"*. ★★ **One `MUL` against four shifts and a `pshs`/`ora` pair**,
which `pic_core.s:88-92` costs at ~30 cycles. **The cost is paid per pixel and cannot be hoisted**
the way `scr_dbl` was — `co_col` is per-pixel data, not per-fill. ★ Measured: the arm grew **3
bytes** and the composite stage is unchanged at ~15.7%.

### 4C — The other writers
★★★★ **All four already pack, and none needed touching.** The text engine was the useful check: it
has been eye-gated readable for tasks, and it addresses the framebuffer at 2 px/byte — ★★★ **which
is what makes §3(2) a census rather than a hunt.**

### 4D — ★★★★★ The eye gate

**Kingquest1, room 1, the ego.** Jay:

> ***"he is solid as are the flags. facing right. dosn't move. colors look correct. the flags look
> ok but i don't remember what they look like in the actual interpreter."***

| | |
|---|---|
| 1. solid, no half-black columns? | ★★★★★ **yes** |
| 2. same silhouette flipped? | ★★★★ **STILL BLOCKED** — *"facing right"*, one pose only |
| 3. the flags? | ★★★ **look ok** — the *"don't look right"* of P6.52 was this defect |
| 4. colours? | ★★★★ **correct** |

★★★★★ **Question 2 is blocked for the THIRD task**, and now for a named reason rather than a defect:
**there is no input path in this arm** [P6.53 §7.2], so the ego never turns. §7.1.

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-1  oracle: _gameScreen 160x168 one byte/pixel, _displayScreen separate [graphics.h:116,119]
      picgate.py:34-42 unpacks and verifies nibble agreement -- why pic passes at 45/45
AC-2  five writers censused; four pack, two of them say so in their own comments
AC-3  comp_probe 967 B 39F5D105 -- BYTE-IDENTICAL
AC-4  comp 124/124 | pic 45/45 | cel 9193/9193 | vm 9/9 | res 1264/1264   ★ all fresh
AC-5  nibble census, all four sprites: 805 / 697 / 246 / 701 equal, ZERO split
AC-6  -RawVis: 58 and 274 SPLIT, e.g. $0C -- half black. The known-good red.
AC-7  Jay, live, RGB -- §4D
AC-8  suite all green; mojibake clean; RED ($44) inside the rect: 0
AC-9  p3b 14,149 2C4DB737 -> 14,152 26763F91 (+3). ONLY this arm; the text arms link no
      compositor and comp_probe defines no VIS_DOUBLED. Region A's 2,904 B still unclaimed.
AC-10 hal_sync x3 OK   reg-discipline 17/1/4   gen_vm_tables --check OK
```
**25.2:** N/A. **25.3: PASSED — Jay, live, RGB.** ★★★ **Solid figure, correct colours; question 2
blocked by §7.1, not by a defect.**

### 6 — Reactive deviations and route accounting
1. ★★★★ **§6's "references disagree" trigger was considered and declined**, with reasons (§4A(2)).
   The two gates model two different probes' planes; neither reference changes.
2. ★★★ **I ran the oracle for Jay mid-task**, on request, so he has something to compare against —
   §7.3. **Not a scope change; a tier-3 reference he asked for and did not have.**
3. ★★ **The first launch failed (exit 255)**: a background task has no window station, so SDL could
   not open a display. Relaunched detached.
4. **ROUTE ACCOUNTING.** §4A–§4D answered. ★★★★ **Only the compositor changed; the four other
   writers were censused and left alone** [§6].

### 7 — Uncertainty flags

**7.1 ★★★★★ EYE-GATE QUESTION 2 IS BLOCKED FOR THE THIRD TASK, AND NOW FOR A KNOWN REASON.** The
ego *"doesn't move"* because the cel arm defines no `HAL_KEYBOARD` — there is no input path in that
build at all [P6.53 §7.2]. ★★★★ **So the row-scope mirroring still has not been seen by a person**,
and 9,193 matching cels remain a statement about our own reference. ★★★ **Until an arm exists in
which the ego turns, that question cannot be asked** — and it is the last unexamined thing in the
sprite path.

**7.2 ★★★ Jay cannot judge the flags against the original**: *"i don't remember what they look like
in the actual interpreter."* ★★★★ **That is the eye gate's ceiling, stated by its operator.** It can
confirm *solid, coherent, plausible* and cannot confirm *correct* without a side-by-side — and §3
forbids me from supplying one by reading pixels.

**7.3 ★★★★★ RUNNING THE ORACLE REGENERATES DUMPS, AND I CHECKED WHETHER I HAD MOVED A GATE
REFERENCE.** `C:\Projects\scummvm\scummvm.exe` (built 2026-09-08) on Kingquest1, at Jay's request.
Its console reports ***"dumped 312 raw resources"***, ***"rendered 82 pictures"***, ***"dumped 495
dictionary entries"*** — **the instrumentation runs on every launch.**

★★★★★ **The references are intact, and that is measured rather than assumed.** The dumps landed in
the process's working directory (`C:\Projects\scummvm\`), **not** in `coco_agi/oracle/dumps/`, whose
newest file is still **2026-09-08**. `oracle/dumps` is **not** gitignored — `git check-ignore`
returns nothing and it has a tracked file — so `git status`'s silence is evidence and not an
artefact. ★★★ **Had I run it with `coco_agi/oracle/dumps` as the working directory, the reference
every gate compares against would have been rewritten**, which §2O.1 and §6 forbid absolutely.
★★ **314 stray `oracle_*.bin` files were created in the sibling tree and removed**; all 314 were
untracked, none tracked, and the sibling's 14 modified files are its own pre-existing patches [§2G].

**7.4 ★★★ The oracle itself reports four unreadable resources in Kingquest1**:
`AgiLoader_v2::loadVolRes: bad signature 5cd7!`, **four times**. ★★ Our `res` gate is 1,264/1,264
against `tools/volread/`, not against ScummVM, so the two are not in conflict — **but the oracle
declining four resources of a gate title is a fact nobody has recorded.** Named, not investigated.

**7.5 ★★ Its detection listed TWO KQ1 variants in the game directory**: `2.0F 1987-05-05
DOS/English` (which it ran, *"Emulating Sierra AGI v2.917"*) and ★★★ **`CoCo3/English`**. CLAUDE.md
§2K records Sierra's CoCo3 AGI titles as **KQ3 and LSL1**, not KQ1, so this is either a loose
fallback match or a fact about that directory. ★★★★ **§2Q makes the game set a BINDING — "AGI
version, platform, release" — and an ambiguous directory is exactly what that rule exists to
prevent.** Named, not investigated.

**7.6 ★★ The doubling is per pixel and cannot be hoisted.** ~11 cycles of `MUL` on every written
pixel, against `scr_dbl`'s zero. ★ Unmeasured as a percentage; the composite stage did not visibly
move at 60 cycles.

### 8 — Follow-up candidates
1. ★★★★★ **An arm in which the ego turns** (§7.1) — **the only way to ask question 2.** Either
   `HAL_KEYBOARD` in a cel configuration, or a scripted `set.loop`/direction change.
2. ★★★★ **A side-by-side against the oracle** (§7.2) — now possible, and it is what makes an eye
   gate say *correct* rather than *plausible*.
3. ★★★ **Pin the Kingquest1 directory** (§7.3) [§2Q] · why the ego does not move · `set.pri.base`.
4. ★★ Region A's 2,904 bytes · the windowed composite's gate [P6.52 §4E].

### 9 — User interaction during task
1. Jay ran the eye gate: ***"he is solid as are the flags... colors look correct."*** ★★★ **Three
   defects in three tasks were each found by that gate and none by a byte gate.**
2. ★★★★ **Jay asked for the oracle to be run so he had something to compare against** — which is
   §7.2's ceiling, recognised by its operator before I named it.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-the-invariant-was-written-down-twice-and-broken-once.md`
- `seeds/AGI/live/2026-09-19-the-eye-gates-ceiling-is-plausible-not-correct.md`

### 11 — Commit
`8caebc8` (pushed to origin/wip before this report).
