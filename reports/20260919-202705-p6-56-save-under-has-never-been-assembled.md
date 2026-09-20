## Form B Report — T-P0-110 / P6.56 — Save-under has never been assembled, and it has rotted where it sits
**Class:** integration (§4A) — **STOPPED at §6 before any change.**  wip.

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 20:27:05 (HEAD 068df1f, wip). git status: clean except `?? coco_agi.code-workspace`,
the editor's file, unstaged and not this task's.

★★★★★ **NOTHING WAS CHANGED. §6's fourth trigger fired during the pre-dispatch grep** — *"the
save-under routine needs changing rather than defining"* — and it fired on evidence, not on
judgement. The dispatch instructs: **stop and report, do not repair.** This report is that stop.

### 1 — Summary

The dispatch's model was: `CP_SAVE` is undefined, `comp_probe` presumably defines it and provides a
siting precedent, so define it for `p3b`, site a store, and look. **Three of those four premises are
false.**

★★★★★ **`CP_SAVE` is defined NOWHERE in the repository** — not by `comp_probe`, not by any probe,
not by any build row in `gates.manifest`. **The `ifdef` block at `composite.s:663-763` has never
been assembled by anything, ever.** There is no siting precedent because there has never been a
siting.

★★★★★ **And it has rotted.** The routine was correct when it was written. Three tasks have since
changed how this file addresses a plane, and **each of them swept the four sites the assembler could
see and could not see the fifth.** Against the live build's own flags (`-DPLANE_WINDOWED
-DPRI_PACKED`, `gates.manifest:200`) the save-under carries **two independent live defects**.

★★★★ **The guard that exists to catch precisely this cannot fire** (§3.3).

★★★ **And the store bound in §1.3 of the dispatch is not safe** (§3.4). The dispatch was right to
demand a measurement and the measurement does not support the number it was told not to quote — nor
does it support mine.

**The finding of P6.55 is untouched by all of this.** Save-under being absent is still the best
explanation of Jay's box. **It is now known to be absent for a stronger reason than "the flag is
off".**

### 2 — Files modified

**None.** No source, no tool, no gate, no manifest. Scratchpad only:
`celarea_peak.py` (§3.4's measurement).

### 3 — Reasoning

#### 3.1 §3(2) — `CP_SAVE` is defined nowhere, and the block has never been assembled

A repository-wide grep returns **six lines, all inside `composite.s` itself**, plus report prose:

```
src\harness\composite.s:663:    ifdef   CP_SAVE
src\harness\composite.s:690:    ldd     #CP_SAVE
src\harness\composite.s:696:    addd    #CP_SAVE
src\harness\composite.s:702:    std     CP_SAVEB
src\harness\composite.s:703:    cmpd    CP_SAVEPK
src\harness\composite.s:705:    std     CP_SAVEPK
```

★★ **`CP_SAVEB` and `CP_SAVEPK` are referenced inside the block and defined nowhere either.** So
the block cannot assemble today even with `CP_SAVE` supplied: it needs a store address **and** two
host-readable counter cells that do not exist.

★★★★★ **§2W in its purest form.** The project's rule is that an instrument is believed only once it
has been seen to fail. **This is code that has never been seen to do anything** — not compiled, not
run, not gated, not ablated. The dispatch's §4A calls the with/without pair "the fault arm"; the
without-arm is today's build, and **the with-arm does not exist and never has.**

#### 3.2 §2H check 2 — the caller carries the scope, and here the *build* is the caller

P6.55 §3.3 said the save-under code "is not defective, it simply isn't compiled", and the dispatch
§2 carried that forward as *"the save-under CODE is not suspected."* ★★★ **That is now withdrawn,
and it was my sentence in P6.55 that put it there.** The code is not *wrong about save-under*. It
is **stale about the plane**, which is a different subject and was not examined when the claim was
made — I read the routine for what it did with the backing store and not for how it reached the
screen.

Measured against the four compiled sites in the same file:

| | live compositor | save-under |
|---|---|---|
| priority access | `addd co_rowpri` + `jsr plane_pri` — lines 207-8, 225-6, 275-6, 310-11 | ★★★★ `ldy co_rowpri` used as a **direct pointer**, line 716 |
| visual access | `addd co_rowvis` + `jsr plane_vis` — lines 422-3 | ★★★★ `ldx co_rowvis` used as a **direct pointer**, line 714 |
| row advance | visual `+PRI_W`, priority `+PRI_STRIDE` — lines 362-7 | ★★★ **both `+PRI_W`**, lines 755, 758 |

**Defect 1 — windowed addressing.** `composite.s:69` and `:514`: *"UNDER `-DPLANE_WINDOWED` THESE
TWO ARE FLAT OFFSETS, NOT ADDRESSES [T-P0-107]."* The save-under loads them as addresses.
`memmap.inc:462` establishes that `PLANE_WINDOWED` is **mandatory** — *"p3b_probe.s refuses to
assemble without it"* — so this is live, not conditional. ★★★ **The consequence is written out in
the repository already**, in the assertion text at `p3b_probe.s:2168`: *"row 100 lands at `$FE80`
beside the vector stubs and row 167 wraps to `$2860`, inside this probe's code."* Enabling the
block as it stands would have the save-under **write the screen into the probe's own code**.

**Defect 2 — the priority stride.** `PRI_STRIDE equ PRI_W/2` under `-DPRI_PACKED`
(`composite.s:62-63`) = 80, against `PRI_W` = 160. `co_rownext` advances the two planes by their
own strides; the save-under advances both by `PRI_W`. `gates.manifest:200` defines `-DPRI_PACKED`,
so this is live too, and it walks the priority store at double rate.

★ **A third axis was checked and is FINE, and is recorded so the next task does not re-open it.**
`co_put_visual` addresses the visual plane at **one byte per AGI pixel** (`ldb co_curx`, then
`addd co_rowvis`) with the colour doubled into both nibbles — 1 AGI pixel = 1 byte = 2 screen
pixels. The save-under's per-pixel byte walk matches that. **P6.54's packing does not affect it.**

★★★★★ **The mechanism of the rot is worth naming, because it will recur.** Each of P6.50, P6.52 and
P6.54 enumerated "every site in this file" and fixed what it found. **An assembler under `ifdef`
does not show unfired blocks to a grep for a symbol**, and a human enumerating sites reads the
symbol, not the guard. **Code behind a define that nothing defines is not dormant; it is
unmaintained, and it decays at the speed of the code around it.**

#### 3.3 ★★★★★ The guard for this exact defect cannot fire

`p3b_probe.s:2166-2168` exists *because* of T-P0-107, and its error text describes this failure
precisely. **It asserts on the symbol `COMP_PLANE_SAFE`.** And `composite.s:80-82`:

```
                ifdef   PLANE_WINDOWED
...
COMP_PLANE_SAFE equ     1
```

★★★★★ **The symbol is set unconditionally whenever `PLANE_WINDOWED` is defined. It is a claim the
file makes about itself, not a property the assembler checks.** Compiling the stale save-under
changes nothing about it, so **the guard stays green while the defect it was written for is
reintroduced.**

★★★★ **This is P6.3's shape with a new mechanism** [§2W's fifth row: *"a guard added to PREVENT a
recurrence could not fire"*]. P6.3's guard read a global its interpreter did not define. This one
reads a symbol its subject defines about itself. ★★ **Both were tested only against the case they
were meant to allow.**

★★★ **The fix is not more assertion text.** A symbol cannot witness a property of code. What would
witness it is the *absence* of the flat-pointer form — which is a grep, not an `ifgt`, and belongs
in the tooling beside `probe_identity_check.ps1`.

#### 3.4 §3(3) — the store bound, measured, and neither published figure is it

`celarea_peak.py` over the oracle's own VIEW dumps, decoded by `tools/agivm/view.py` (§2O.1 — the
reference, not a reimplementation of it):

```
cels-Kingquest1    cels  740  peak area 1242 B (27x46,   view 35)   store 2x =  2484 B
cels-Kingquest2    cels 1074  peak area 1650 B (33x50,   view 208)  store 2x =  3300 B
cels-Kingquest3    cels 1753  peak area 4784 B (46x104,  view 64)   store 2x =  9568 B
cels-larry1        cels 1121  peak area 4592 B (82x56,   view 41)   store 2x =  9184 B
cels-PoliceQuest1  cels 2342  peak area 2496 B (52x48,   view 96)   store 2x =  4992 B
cels-SpaceQuest-1  cels 1652  peak area 3500 B (50x70,   view 82)   store 2x =  7000 B

CORPUS PEAK single cel : 4784 B      ->  2x = 9568 B
```

★★★★★ **The design spec defines the bound as something neither figure measures.** §1261-1263:
*"peak simultaneous active objects and **peak total cel area on screen** are the save-under
backing-store bound ... **Save-under bounds cost by total sprite area, not screen area**."*

So the bound is the **sum over concurrently drawn sprites**, per frame, times two planes.

| figure | what it actually measures | status |
|---|---|---|
| 4,152 B [P5.1] | peak total on-screen cel area **observed in the scenarios P5.1 ran** | a sample, not a bound [L-85, L-86] |
| 8,304 B [P6.52, and the dispatch §1.3] | 2 × the above | ★★★★ **unsafe — smaller than one KQ3 cel needs** |
| 9,568 B [here] | 2 × the largest **single** cel in six titles | ★★★ **a FLOOR, not the bound** |

★★★★★ **A single KQ3 cel at 46×104 requires 9,568 B on its own, which exceeds the figure the
dispatch instructed the siting to be built around.** The dispatch's §3(3) said *"measured — not
P6.52's 8,304 quoted forward"*, and **that instruction earned its stars**: 8,304 was P5.1's
observation doubled, never re-measured, and it is below the static single-cel floor.

★★ **And my 9,568 must not now be quoted forward in its place.** It is a static maximum over one
cel. The real bound needs the peak *concurrent sum*, which is a property of scenarios and not of
resources — ★ **it cannot be obtained by reading VIEW files and was not obtained here.** §8.2.

#### 3.5 §3(4) — region A, and why the siting question is not yet answerable

`gates.manifest:277-278` and the P6.36 report: the font left region A, taking headroom from 277 B to
**2,289 B**; P6.39/P6.40 record it at **1,622 B** after subsequent growth. ★★ **The cel arm has
EIGHT bytes** — `p3b_show.ps1:177`, *"region A ends at `$52F8` with `CP_CEL` at `$5300`"*.

★★★★ **Against a floor of 9,568 B, region A is not a candidate and neither is anything else inside
`$2000-$6000`.** The store is ~9.3 KB and must be reachable while both planes are windowed. ★★★
**That makes this a banking question, not a siting question**, and the dispatch's §4B ("name the
address, what it displaces, what it neighbours") presumes an answer inside the flat map that does
not exist. §6's second trigger — *"no siting exists without `MAP_RESERVED`, `CP_CEL` or the font
moving"* — is therefore **also** fired, on arithmetic rather than on a failed attempt.

#### 3.6 §2H check 3 — the reports, grepped

P6.52 and P6.55 both state `p3b` does not define `CP_SAVE`. ★★ **Neither states that nothing else
does either**, and P6.55 §3.3 positively asserts the code is sound. **The contradiction is mine and
is resolved here in favour of the measurement** (§3.2). ★ Recorded because §2H check 3 exists for
exactly this: *"a contradiction between two reports survives indefinitely when each is cited alone."*

### 4 — Verification (AC-by-AC)

★★★★★ **The task stopped at §6 before changing anything, so most ACs are NOT MET BY DESIGN.**
Reporting them as anything else would be the failure §2W describes.

- **AC-1 [state-comparable · fault injection] — NOT MET, BLOCKED.** The with/without pair cannot be
  built. The without-arm is today's binary; **the with-arm does not assemble** (`CP_SAVEB`/
  `CP_SAVEPK` undefined, §3.1) and would be wrong if it did (§3.2). ★★ Building it anyway would have
  the save-under write screen rows into the probe's own code.
- **AC-2 [measurement] — MET.** §3.4. Corpus peak single cel 4,784 B → 9,568 B floor; **and the
  finding that this is a floor and not the bound.**
- **AC-3 [assembler] — NOT MET, BLOCKED.** No siting exists to assert (§3.5).
- **AC-4 [state-comparable] — NOT MET, BLOCKED.** Depends on AC-1.
- **AC-5 [byte-comparable] — MET TRIVIALLY, and said plainly: `comp_probe.bin` is unchanged because
  nothing was changed.** 967 B `39F5D105` carried from P6.54 under §2T, with the inputs verified
  unmoved (§5). ★ This is not evidence of care taken; it is evidence of a task that stopped.
- **AC-6 [byte-comparable · gate] — CITED, NOT RE-RUN.** §2T: `git diff --stat 221e664..HEAD --
  src/ harness/ tools/ content/` is **empty**. pic 45/45, res 1,264/1,264, cel 9,193/9,193, comp
  124/124, vm 9/9 carried from P6.54. ★★ **A gate run here would measure the same bytes and is the
  waste §2T exists to remove** — and per §2T.3, if anything had differed it would be reported.
- **AC-7 [eye gate — Jay] — NOT OFFERED, AND DELIBERATELY.** ★★★ §4A puts the eye gate first on an
  integration task, and **there is nothing to look at**: no arm was built, so the screen is
  byte-identical to the one Jay already reported on. **Offering it would be asking him to re-observe
  P6.55's finding and calling it a gate.**
- **AC-8 [measurement] — MET.** §4C costing below.
- **AC-9 [suite] — NOT RUN.** Same basis as AC-6.
- **AC-10 [manifest] — NOT MET.** ★★ Its second half (§1.1's rule) is the one piece of this dispatch
  that could still be landed without touching the compositor; it is left undone rather than
  half-done, and carried to §8.4.
- **AC-11 [tooling] — NOT RUN.** Nothing was built.
- **AC-12 — MET.** §10.

#### §4C — costing the two-frame arm (AC-8)

**What it would take.** `comp_probe` stages a host-supplied cel and composites once onto a clean
plane. A two-frame arm needs: a second staged cel (the next cel in the loop), a second
`cp_composite` call, **and save-under between them** — which is the thing under test, so ★★ **the
arm cannot be built before the fix and is not an independent check of it.** The honest sequence is
fix first, then this arm as the regression.

**What it would cover.** The whole class §4C names: any defect in the relationship between frame N
and frame N+1 — absent restore, partial restore, wrong-plane restore, restore-after-draw ordering.
★★★ **None of which `comp`'s 124/124 can express**, because it composites single frames onto a
clean plane and a single composite is genuinely correct.

**What it would cost.** The probe gains a second cel slot and one more handshake; the reference side
needs the oracle to emit the plane **after** two composites, which is a new dump point in
`sprite.cpp`, i.e. a **sixth instrumentation patch** against the pin (§2Q) — ★ the first new patch
since 0005, and 0005 is the one the pin file flags as behaviour-changing. **That is the real cost:
not probe code, but an addition to the oracle.**

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output:** ★★★ **No build was run, because nothing was changed.** §2T baseline,
with the inputs verified rather than the outputs rebuilt:

```
$ git -C coco_agi diff --stat 221e664..HEAD -- src/ harness/ tools/ content/
(empty)

$ git -C coco_agi diff --stat 221e664..HEAD
 ...617-p6-55-the-side-by-side-and-what-it-found.md | 327 +++++++++++++++++++++
 1 file changed, 327 insertions(+)

$ git -C coco_agi rev-parse --short HEAD
068df1f
$ lwasm --version
lwasm from lwtools 4.24
```

**Baseline cited from `reports/20260919-191000-p6-54-the-compositor-doubles-the-nibble.md`:**
pic 45/45, res 1,264/1,264, cel 9,193/9,193, comp 124/124, vm 9/9; `comp_probe.bin` 967 B
`39F5D105`. ★★ **HEAD moved by two report-only commits; no gate input moved.** §2T.1's five rebuild
triggers: none fired.

Fresh output produced: §3.4's cel-area measurement, in full above.

**25.2 bundled-artifact grep:** N/A — no artifact built.

**25.3 operator-runtime-smoke:** ★★★ **NOT OFFERED — see AC-7.** Nothing was built; the screen is
unchanged from the one Jay reported at P6.55. **"Pending Jay" would misrepresent a task that
produced nothing to look at.**

### 6 — Reactive deviations and route accounting

★★★★★ **§6 triggers fired, two of them, and the dispatch's instruction was followed exactly: stop,
report, do not repair.**

1. ★★★★★ ***"the save-under routine needs changing rather than defining"*** — fired on §3.2's
   evidence. Two live defects against the build's own flags.
2. ★★★★ ***"no siting exists without `MAP_RESERVED`, `CP_CEL` or the font moving"*** — fired on
   §3.5's arithmetic. A ~9.3 KB store does not fit region A's 1,622 B, and nothing in `$2000-$6000`
   has that much.

**What I did NOT do, and would have had to do to satisfy §4A.** §4A instructs the with/without pair
**first**, crudely sited if necessary, because it can retire the task. ★★★ **I did not build it.**
Doing so required supplying `CP_SAVEB`/`CP_SAVEPK` and repairing two plane-addressing defects —
which **is** trigger 1, so §4A and §6 point opposite ways and §6 is the one that says stop. ★★ Per
§8, stating this plainly rather than quietly reordering the dispatch.

**Route accounting.** ★★★ **I proposed nothing and implemented nothing.** No route was offered in
this task; the only proposals are in §8, and they are proposals.

★ **One correction carried from my own previous report:** P6.55 §3.3's *"the save-under CODE is not
suspected"* is withdrawn (§3.2). The dispatch inherited it in its §2, so the withdrawal is
load-bearing for the next dispatch, not cosmetic.

### 7 — Uncertainty flags

1. ★★★★★ **P6.55's finding is still unproven.** This task was meant to prove or kill it and did
   neither. **Everything remains consistent with absent save-under and nothing has yet shown it.**
   The Graham-smear prediction is untested; the with/without pair is unbuilt.
2. ★★★★ **The store bound is not known.** §3.4: 9,568 B is a floor from a static maximum; the design
   spec's definition needs a peak concurrent sum which was not measured and cannot be read out of
   VIEW files.
3. ★★★ **Whether the two staleness defects are the ONLY ones.** The routine was read against three
   axes (windowed addressing, stride, packing). ★★ **Three is not an enumeration** — §2H's own
   warning — and nothing has assembled this code to find out.
4. ★★ **`CP_SAVEB`/`CP_SAVEPK` were never defined**, which means the AC-7 reporting path P6.52
   described for the doubled figure was also never built. The "reported as the doubled figure"
   comment at `composite.s:698` describes something that has never run.
5. ★ **`comp_probe` was assumed not to define `CP_SAVE` on the strength of a repository grep.** That
   is a strong instrument here — the symbol is short, distinctive and unquoted — but it is a grep,
   not an assembly.

### 8 — Follow-up candidates

1. ★★★★★ **Repair the save-under routine to the file's current conventions, as its own task, before
   anything is sited.** Two named defects, both mechanical, both with four worked examples in the
   same file. ★★★ **It cannot be gated by `comp` 124/124** (the routine is not on that path), so it
   needs the §4C arm or an eye gate — which is the ordering problem the next dispatch must solve.
2. ★★★★★ **Measure the peak CONCURRENT cel area**, per frame, across the corpus. §3.4. This is the
   number the store is sized from and the only one that has never been measured. ★★ It needs a
   scenario run, not a resource scan — plausibly a counter in the existing p3b staging path.
3. ★★★★★ **Site the store as a BANKED region, not a flat one.** §3.5: ~9.3 KB at minimum. ★★★ This
   is design-spec territory (§2D — Orchestrator content), and the three shapes should be priced as
   T-P0-104 priced `CP_CEL`'s.
4. ★★★★ **`gates.manifest` + `composite.s` header: an `ifdef`-excluded subsystem gets a note saying
   what its absence LOOKS like** — the dispatch's §9, unlanded here because the task stopped. ★★
   **It is the cheapest item in this dispatch and the only one with no dependencies.**
5. ★★★★★ **Replace `COMP_PLANE_SAFE` with something that can fail** (§3.3). A symbol cannot witness
   a property of code. ★★★ A grep-based check for the flat-pointer form, beside
   `probe_identity_check.ps1`, would have caught this rot the day P6.52 landed.
6. ★★★ **A standing check for `ifdef` blocks that nothing defines.** §3.2's rot mechanism is
   general: this file has one, and nothing says whether the tree has others. ★★ A census is cheap
   and is a census, not a gate [§2N.1].
7. ★★★ **THE GRAHAM-SMEAR PREDICTION, recorded as the dispatch requires** [§7]: **when
   `HAL_KEYBOARD` reaches the cel arm and Graham walks, he should leave a trail of his own opaque
   pixels.** ★★ If he does not, P6.55's finding is wrong. **The next task tests it for free.**
8. ★★ The clear-key defect [P6.55 §3.4], unchanged and still its own task, **gated on LSL1**.
9. ★ `MAP_PRI_BANDS` is still an address nothing uses — **fourth task carrying it** [P6.53 §4B].

### 9 — User interaction during task

**None during execution.** The dispatch was issued and the task ran to its §6 stop without
consultation. ★★ Jay's words from P6.55 are quoted in the dispatch and are the reason this task
exists; no new eye gate was requested (AC-7) because nothing was built to look at.

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-code-behind-an-undefined-ifdef-is-unmaintained-not-dormant.md`
- `seeds/AGI/live/2026-09-19-a-symbol-cannot-witness-a-property-of-code.md`

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting. **No source commit: nothing was changed.**
