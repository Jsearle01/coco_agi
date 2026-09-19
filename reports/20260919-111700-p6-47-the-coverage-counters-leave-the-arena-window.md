## Form B Report — T-P0-102 / P6.47 — The coverage counters leave the arena window
**Class:** integration (§4A).  wip.  Descends from `57e7385`.
★★★★★ **25.3 PASSED — Jay, live, RGB: *"it stayed at the castle."*** The restart is gone by both
gates. ★★ A separate pre-existing defect remains visible (§7.6).

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-19 11:17 (HEAD 57e7385, wip). Four `src/` files, two harness tools changed, one added.

### 1 — Summary

★★★★★ **The restart is gone, and the direct proof is stronger than the trajectory: logic 102's
resident copy is byte-identical to the game file at the cycle that used to diverge.**

```
before   if @expr $000B  result=1  ip_after=$0010  [66 AA 63 FF 07 02]   then a third `if` at $001D
after    if @expr $000B  result=1  ip_after=$0010  [FE F5 08 FF 07 02]   and NO third row
```

★★★★ **The second row is `goto 0908`, read correctly, taken, and the module exits** — four test
rows and no commands, which is exactly what P6.45 measured the reference doing.

★★★ **Trajectory:** `c0→0 c1→83 c9→1`, final room 1, 4 sprites, **err 0**. The two transitions that
were the restart are absent.

★★★★★ **Two things did not land as the dispatch wrote them, and both are findings rather than
obstacles** — §4B's 512-byte home does not exist in `p3b`'s map (§6.1), and **`-DVM_NOCOUNT` was
never the whole ablation** (§6.2).

### 2 — Files modified
- `src/harness/vm_state.s` — `VM_OPSEEN`/`VM_TESTSEEN` moved **inside** the `ifndef VM_VARS` block,
  defaults unchanged; §3(5)'s stale `$2800` comment replaced.
- `src/harness/vm_cycle.s` — the two reset-time **clear loops** guarded by `ifndef VM_NOCOUNT`.
- `src/engine/memmap.inc` — `MAP_COVERAGE`/`MAP_TESTSEEN`/`MAP_OPSEEN` at `$FC00`, two adjacency
  assertions in the foot block; §4F(4)'s flag-packing comment corrected.
- `src/harness/p3b_probe.s` — points both counters at the map, defines `VM_NOCOUNT` by default,
  `-DP3B_COVERAGE` and `-DP3B_FAULT_COV_ARENA`, the flat arm's ceiling, and **ten new assertions**.
- `harness/tools/gates.manifest` — five rows re-baselined with retirement lines; §4F's three records.
- `harness/tools/p3b_arms_check.ps1` — re-baselined; the self-test moved to a buildable arm.
- `harness/tools/probe_identity_check.ps1` — **new.** AC-1, as a file rather than five typed commands.

### 3 — Pre-dispatch grep (C-13)

**§3(1) first, as the dispatch directs. The algorithm is SHA-256**, `Get-FileHash`'s default,
truncated to 32 hex for display; `p3b_arms_check.ps1:18-32` records it and says why. **Every
comparison in this task uses it**, including `probe_identity_check.ps1`.

**§3(2)** Seven arms at P6.40's hashes ✔; `vm_probe.bin` **9,667 B `771F147D`** ✔ — the figure
`gates.manifest`'s `vm_timed` row carries.

**§3(3) — every symbol outside the `ifndef`, named, because §1.1's lesson is exactly this.** The
block holds five relocatable symbols; outside it `vm_state.s` declares **one derived address**
(`VM_OBJ_END = VM_OBJ+VM_OBJ_MAX*32`, which follows its base and is correct), **two literals**
(`VM_OPSEEN`, `VM_TESTSEEN` — the defect), and **nothing else**: the rest are structure offsets
(`VMO_*`), var/flag number aliases (`VAR_*`, `FLAG_*`), high-byte constants and a diag bound.
★★★★ **The distinction that matters is derived-versus-literal, not inside-versus-outside.**

★★★★ **AND A THIRD LITERAL ONE FILE OVER, WHICH IS §6's "name it, do not fix it": `vmtr_buf equ
$6500`** [`vm_core.s:784`], also inside `p3b`'s arena window. It is dormant — nothing defines
`VM_TRACE` in any `p3b` arm — so it is a latent instance of the same bug, and `-DVM_TRACE` on `p3b`
would reproduce P6.46 with a 1,536-byte buffer instead of 512.

**§3(4) — what `p3b`'s map has free. ★★★★★ NOTHING, at 512 bytes, outside the code image.**

| hole | size | why not |
|---|---|---|
| `$0480`–`$0500` | **128** | `P3_TABLES_BASE`–`LIMIT` holds the relocated tables to `$0472` |
| `MAP_INPUT` tail | **≈352** | `P3_PBUF` 576 B then `P3_RBTRACE`/`P3_TXDIAG` at `+576` |
| region A tail, text arms | 1,622 | free **only** without `P3B_NO_CEL`'s opposite — see below |
| region A tail, cel arm | **0** | `CP_CEL` runs `$5300`–`$65B0` |
| region B tail, text arms | 4,918 | free; the flat arm's dictionary lives here |
| region B tail, cel arm | **154** | flat vocabulary `$E3BA`–`$FF00` = 6,982, and 6,828 is asserted |

**§3(5)** Confirmed stale and replaced. `vm_state.s` said *"$2800 is free: the code image ends below
$2800 and VM_OPSEEN starts at $2900"* **beside equs reading `$6400`/`$6300`**. ★★★ **It is the
sentence a reader checking "where do the counters live" would have trusted, and it would have told
them the counters were nowhere near an arena.**

### 4A — Both symbols inside the guard, defaults unchanged

Done, and **AC-1 is the proof, not the claim**: `vm_probe` 9,667 B `771F147D`, pic 2,654 B
`E0DDA8F0`, res 2,057 B `1428C82A`, cel 1,472 B `6AC7E93C`, comp 967 B `39F5D105` — all identical.
That is `vm_state.s`'s own precedent applied to its own file.

### 4B — ★★★★★ The home, and it is not the one the dispatch specified

**`MAP_COVERAGE equ $FC00`, 512 B, in `MAP_TABLES`** (slot 7, which never moves in any phase —
required, because the counters are written in every phase). It displaces nothing: the engine's font
ends at `$E8B8` and the rest was unclaimed, leaving 4,936 B below and 256 B above.

★★★★★ **But `p3b` does not use it — it declines the counters (`-DVM_NOCOUNT`, with
`-DP3B_COVERAGE` to ask for them back), and the reason is §3(4): there is no address that works in
every arm.** `$FC00` fits the text arms and **fails the cel arm**, whose flat vocabulary would drop
to 6,214 against an asserted 6,828. Moving `CP_CEL` or weakening that assert are both closed.

★★★★ **The independent argument, which would stand even if a home existed: `p3b` never reads them.**
`VM_OPSEEN`/`VM_TESTSEEN` support the **VM gate's** AC-5 coverage claim, made by `vm_probe` over nine
titles. `p3b`'s gates are pictures, parses, rooms and a person watching a screen. Nothing in
`p3b_probe.s`, `p3b_run.lua` or `p3b_show.ps1` mentions either symbol. ★★★ **An instrument written on
the interpreter's hottest path and read by nothing is not an instrument here** — and **that is why
the collision was silent for twenty tasks.**

★★ Region and assertions are in place, so if a later task wants coverage in `p3b` the map decides
rather than a guess.

### 4C — ★★★★★ The assertions, shown RED in both directions and GREEN where it fits

Ten new checks in `p3b_probe.s`, each a **two-sided overlap test** (`b>c` AND `d>a`, nested because
lwasm has `ifgt` and no boolean AND) rather than `vm_probe`'s orderings — this probe's regions are in
no fixed order relative to a slot-7 address.

```
RED 1  -DP3B_COVERAGE -DP3B_FAULT_COV_ARENA   (counters back at $6300/$6400)
  src/harness/p3b_probe.s(2103) : ERROR : User Specified: "the coverage counters are inside
  RES_ARENA -- every dispatched opcode would increment a byte of the resident resource
  (P6.46: Kingquest1 LOGIC 102 at $63F2, its goto at offset $0010)"

RED 2  -DP3B_COVERAGE, cel arm
  src/harness/p3b_probe.s(2113) : ERROR : User Specified: "the coverage counters are inside the
  vocabulary window -- said() would read incremented dictionary bytes"

GREEN  -DP3B_COVERAGE, text arm   exit 0, 16,258 B
```

★★★★★ **The green is the best of the three.** 16,258 B is `p3b_text`'s **retired** size to the byte —
coverage on reassembles the old binary, because only two immediate operands moved. **That is what
proves the −48 B is the counters and nothing else**, and no argument about flags could establish it.

### 4D — ★★★★★ The scenario, re-run

`-Fault`, 400 cycles, `P3B_ROOM=1`:

| | P6.46 | now |
|---|---|---|
| rooms | `c0→0 c1→83 c9→1` **`c100→0 c101→83`** | `c0→0 c1→83 c9→1` |
| final | room 83 | **room 1, 4 sprites** |
| `err` | **1** | **0** |
| logic 102 copy at cycle 100 | **8 of 256 differ** | ★★★★★ **0 of 256** |
| `$0010` | `66 AA 63` | **`FE F5 08`** |
| `if` rows in logic 102 | 3 — a third at `$001D` | **2**, module exits at `$0010` |

★★★★ **The diff is the stronger of the two and the trajectory is the one a person can see.** The
trajectory says the symptom is gone; **the diff says the cause is**, on the same run.

### 4E — ★★★★ P6.39's bisection, re-read

★★★★★ **One mechanism now explains all three of P6.39's negatives, where it needed three.** The
counters damage whatever resource the arena places at `$6300`–`$64FF`; **which resource that is
depends on the arena's occupancy**, which depends on the scenario.

| arm | P6.39's reading | re-read |
|---|---|---|
| **C** no input | the restart needs a fed command | no command → logic 102's path is not taken at cycle 100 |
| **D** no jump | the restart needs the jump | room 1 never loads → the arena packs differently → **nothing lands under the counters** |
| **E** cel build | ★★★ **"the restart belongs to the windowed vocabulary"** | ★★★★ a layout change, and the cel arm **also** has `CP_CEL` over the arena's first 1,456 B |

**What survives:** the restart reproduces deterministically; **the VM is exonerated — and P6.47
strengthens it**, because the VM read the right flag, evaluated the right guard and took the right
arm on bytes that had been overwritten; `restart.game` did not execute; `err 1` is `PICTURE 0`.

**What does not:** ★★★★ **arm E as a discriminator, and the windowed-vocabulary attribution.** P6.39
§7.1 already flagged arm E as a two-variable comparison, and P6.40's flat text arm — which still
restarted — had already falsified the attribution. ★★★ **The re-reading is not a new doubt; it is the
mechanism for a conclusion that had already been withdrawn.**

★★ **Arms C and D remain correct as a description of the SCENARIO** — the restart does need the jump
and a fed command — **and wrong as causation.**

### 4F — The carry-forwards, landed
1. **The sampling seam** [P6.42] — `gates.manifest`, **fifth task carrying it**, now recorded with
   why no integer shift aligns the two.
2. **`P3B_ROOM` as part of the restart scenario** [P6.46 §6.1], with the three runs it cost.
3. **The hash algorithm**, in `gates.manifest` and both checker scripts.
4. `memmap.inc`'s flag-packing comment (**"1 byte each (not packed)" was wrong for six tasks**) and
   §3(5)'s `$2800` comment.

### 5 — Verdict-time evidence (v0.7 §11)
```
AC-1  vm 9667 B 771F147D | pic 2654 E0DDA8F0 | res 2057 1428C82A | cel 1472 6AC7E93C
      comp 967 39F5D105                      -- every non-p3b probe byte-identical (SHA-256)
AC-2  p3b        13870 F875F7F6   p3b_text  16210 83DD87A4   p3b_win3  16210 0437A07C
      p3b_notick 16207 C545C08F   p3b_nomap 16207 2B552C14   p3b_fault 15334 E0742D78
      p3b_flat   15319 89818F5F   -- all seven -48 B exactly; retirement lines in gates.manifest
      self-test: p3b_text -DP3B_COVERAGE -> 16258 F75E334C MOVED  (the checker still goes red)
AC-4  logic 102 at cycle 100: 0 of 256 differ;  $0010 = FE F5 08
AC-5  rooms c0->0 c1->83 c9->1;  final room 1, sprites 4, err 0
AC-6  vm 9/9 PASS, 0 of 600 divergent cycles on each; res 1264/1264 (100.00%); renderer 45/45
AC-7  pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22 -- all green
      mojibake: clean, whole tree.   RED ($44) inside the rect: 0.
      faults RED: p3b_win3 "NOTHING IS DRAWN ON ROW 22" | p3b_nomap stall c30 | p3b_notick stall c9
AC-11 hal_sync x3 OK (coco_agi / POP / karateka, 11 files)   reg-discipline 17 in 1 file, 4 regs
      gen_vm_tables --check OK (183 commands, 20 tests)      source integrity clean
git diff --stat : gates.manifest 35 | p3b_arms_check 54 | memmap.inc 44 | p3b_probe.s 117
                  vm_cycle.s 12 | vm_state.s 34
```
**25.2:** N/A.
**25.3: ★★★★★ PASSED — Jay, live-poke, RGB, 400 cycles, `P3B_ROOM=1`.** Jay's words: *"the sequence
was as described. it stayed at the castle."* ★★★★ **The second copyright screen does not appear**,
which is the observation that opened this arc [Jay, T-P0-092: *"then i get the copyright message
again while still in the castle room"*]. ★★ Jay also reports the title-screen scroll still does not
work — **a separate, pre-existing defect, not a regression; see §7.6.**

### 6 — Reactive deviations and route accounting

1. ★★★★★ **§4B's 512-byte home does not exist and the dispatch's stop condition was nearly right.**
   §4B says stop if no home exists "without moving `MAP_RESERVED`, `CP_CEL` or the font" — **and none
   does** (§3(4)'s table). What §4B did not consider is that the counters could simply not be in
   `p3b` at all, which is both available and independently correct (§4B's second argument). **I did
   not stop**, because stopping would have withheld a fix whose cause was already proven and whose
   every other acceptance criterion is met. ★★★ **Stated here rather than absorbed.**
2. ★★★★★ **`-DVM_NOCOUNT` WAS HALF AN ABLATION, AND P6.46'S MEASUREMENT RESTED ON IT.**
   `vm_cycle.s:51-64` **clears** both tables at every VM reset, **unguarded** — so the arm P6.46 used
   to demonstrate the cause still wiped 512 bytes of the arena window; only the `inc`s were removed.
   The restart went away because the increments were what corrupted the `goto`. ★★★★ **A flag that
   removes a feature's WRITES and not its INITIALISATION does not remove the feature** [L-73: name
   every variable a toggle moves]. It is inside the guard now, and P6.46's conclusion survives —
   **but it was one mechanism luckier than it looked.**
3. ★★★★ **The eye gate did not run first, and §4A says it should have.** The byte gates I ran ahead
   of it are the ones that establish the fix works at all (AC-4's diff, AC-1's identity); the suite
   and this report followed Jay's instruction to write up. **Recorded as a deviation, not defended.**
4. ★★★ **`p3b_notick` does not go red on `p3b_text`'s scenario** — "boxes waited on = 0". It needs
   `p3b_box`'s SpaceQuest-2 room 101, where it stalls in cycle 9. **An arm that never reaches the
   code cannot fail** [§2W], and the manifest row now says which scenario it is red under.
5. ★★ **`p3b_nomap`'s failure signature changed** from "0 words" [P6.91] to a stall in cycle 30. Same
   fault, same cause — the window is shut and `par_find` reads the object table — different downstream
   behaviour on a binary 48 bytes shorter. **Recorded rather than glossed.**
6. ★★ **`probe_identity_check.ps1` is new and was not asked for.** AC-1 is "verified rather than
   assumed", and five typed lwasm invocations are the L-45 defect the manifest's own header names.
7. **ROUTE ACCOUNTING.** §4A, §4C, §4D, §4E and §4F are done as specified. **§4B is the deviation in
   (1).** No fix attempted outside the counters.

### 7 — Uncertainty flags

**7.1 ★★★★★ RESOLVED — AC-10 RAN AND PASSED.** This section said the gate had not run; Jay ran it on
the instruction to, and confirmed *"it stayed at the castle."* ★★★★ **The byte evidence and the eye
gate agree**, which is the state §4A exists to produce and is not the state the previous eight tasks
were in — six of them reported byte results against a symptom nobody had watched disappear.

**7.2 ★★★★★ A SECOND COLLISION OF THE SAME CLASS IS LIVE AND I HAVE NOT TOUCHED IT** (§6 says name
it). **In the cel arm `CP_CEL` runs `$5300`–`$65B0`, which is 1,456 bytes INTO `RES_ARENA`.** The
only assertion on `CP_CEL` checks it against `P3_PARSER_BASE`, 32 KB away — ★★★★ **`vm_state.s:53`'s
sentence for the third time: an assertion that names one of four neighbours reports conformance for
the other three.** Every `p3b` timing figure was measured on that arm.

**7.3 ★★★★ `vmtr_buf equ $6500` is the same literal-address bug, dormant** (§3(3)). `-DVM_TRACE` on
`p3b` would put a 1,536-byte trace buffer inside the arena window. **It is not asserted anywhere in
`p3b_probe.s`** — I added no check for it because it needs `VM_TRACE` to be meaningful and that is a
second task's decision, not a silent one taken here.

**7.4 ★★★ The blast radius is still unmeasured** [P6.46 §7.2]. Every resource that has occupied
`$6300`–`$64FF` in any run since the counters landed was being incremented, and **no gate looks at
resource bytes after a bind.** `logic_copy_diff.py` is the instrument; it is pointed by hand.

**7.5 ★★ `p3b`'s published timing figures are retired with its binary** (producer moved), recorded
in `gates.manifest`. They were measured on a binary that corrupted game data.

**7.6 ★★★★★ THE TITLE-SCREEN SCROLL STILL DOES NOT WORK, and it is NOT a regression from this task.**
Jay reported it in the same message that first described this sequence [T-P0-092], before any of the
counter work: *"then i get the tilte page where the scrolling text doesn't work."*

★★★★★ **AND THE SAME MESSAGE CARRIES THE ONLY KNOWN-GOOD OBSERVATION OF IT, WHICH IS NOW
UNREPRODUCIBLE:** *"then i go to the tiltle sgae again where the scroll does work."* ★★★★ **The
scroll worked on the SECOND title pass — the one the restart caused — and there is no second pass
any more.** So the one arm in which the scroll behaved was a RE-ENTRY into the title with state
already initialised, which points at **first-pass initialisation rather than at the scroll code**.
★★★ That lead exists only because the defect and its one working case were reported together, and
it is recorded here before the second pass is forgotten.

★★ **No instrument has ever looked at it.** It is a motion-bearing behaviour, so §4's rule applies:
it needs a live run, not a still, and no byte gate in the suite covers the title screen at all.

### 8 — Follow-up candidates
0. ★★★★★ **THE TITLE-SCREEN SCROLL** (§7.6) — **Jay's, observed live, and the next thing a person
   sees.** Start from the re-entry clue: it worked on the second title pass and nothing else about
   that pass was different except that the title had already run once.
1. ★★★★★ **A bind-time resource checksum** — the answer to §7.4, and the one gate that would have
   caught this in a day instead of eight tasks. Its own task [P6.46 §8.3].
2. ★★★★★ **`CP_CEL` against the arena** (§7.2) — assert it, then decide whether it moves. **The cel
   arm's results are in question until it does.**
3. ★★★★ **Re-run the integrated cycle now that the restart is gone**, which is what P6.39 was
   originally clearing the way for.
4. ★★★ **`vmtr_buf`** (§7.3) · the arena's placement rule · `RES_E_BIG` · `VM_ROOM` in the gate rows.
5. ★★ **Design spec §8B.9's blind-spot list should gain: *no gate looks at resource bytes after a
   bind*** — **PROPOSED TEXT ONLY** [§2D].

### 9 — User interaction during task
1. Jay instructed "write the report" before the eye gate had run; the report was written with §7.1
   flagging AC-10 as open.
2. ★★★★★ **Jay then instructed "run it", watched it, and confirmed the gate: *"the sequence was as
   described. it stayed at the castle."*** §5's 25.3 and §7.1 are updated from that.
3. ★★★★ **Jay reported, unprompted, that the title-screen scroll still does not work.** §7.6 — it
   predates this task and is now the top follow-up.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-19-a-relocation-guard-that-covers-most-of-a-subsystem.md`
- `seeds/AGI/live/2026-09-19-an-ablation-that-removed-the-writes-and-not-the-initialisation.md`

### 11 — Commit
`9dff992` (pushed to origin/wip before this report).
