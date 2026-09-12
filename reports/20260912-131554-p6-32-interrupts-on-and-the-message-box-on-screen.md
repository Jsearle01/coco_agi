## Form B Report — P6.32 — Interrupts on, and the message box on screen
**Class:** build.  wip.

★★ **No numbered dispatch. This work was directed conversationally by Jay**, step by step, from
P6.31's stop onward. The §5 structure is kept; the AC list is replaced by §4's rulings, each
quoted, because there was no contract to check against.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 13:15 (HEAD ab89018, wip). Clean but for the two untracked files that are not mine —
`agi-coco3-design-v1_3.md` (Orchestrator's, §2D) and `coco_agi.code-workspace` (Jay's).

### 1 — Summary
P6.31 ended with `print` blocking on a tick source no probe had ever advanced. **Interrupts are now
on, the blocking message box draws, presents, holds and dismisses, and `-DTEXT_FAULT_NOTICK` goes
RED** — the §2W obligation open since P6.29c. `p3b_box` is a gate row and is in the suite.

★★★★★ **Four defects were found in this subsystem, all by Jay watching a screen, none visible to
any byte gate.** The text gate matched the oracle on 4,594 rectangles throughout the entire period
in which nothing drew a box at all.

Two things are open and both are stated rather than implied: the scoped restore leaves residue, and
the 128-glyph font degrades 13 fan titles. ★★★ **Three of my own claims were wrong and are corrected
in §7 rather than quietly dropped.**

### 2 — Files modified
- `src/harness/p3b_probe.s` — `-DP3B_IRQ`; the `$FEF7` vector stub; `p3_restore_box`; the font and
  `TEXT_BOX`/`TEXT_FONT128` decisions; `P3_TXDIAG`.
- `src/engine/text.s` — `tx_drawbox` + `tx_boxfill`; the window offset at draw time; `txt_restore`
  and `txt_winactive`; the high-glyph fold.
- `src/harness/vm_text_ops.s` — the `tx_msgptr` differential logger; `tx_wt_nwait`.
- `harness/tools/` — `run_gates.sh` (mojibake gate, `p3b_box`), `gates.manifest`, `p3b_show.ps1`,
  `p3b_run.lua`, `p3b_room.lua`, `font_high_census.py` (new), `msg_probe.py` (new).
- `CLAUDE.md` — **v1.9, §2J.5–§2J.7**, landed on Jay's instruction.

### 3 — Reasoning

**3.1 ★★★★★ The CoCo3 interrupt vector chain has TWO hops and `HAL_time_init` patches one.**
Measured at the DECB prompt before takeover:
```
$FFF8 -> $FEF7   holds 16 02 12 = LBRA, and $FEFA+$0212 wraps to $010C
$010C            holds 7E D8 AF = JMP into DECB's handler
```
`HAL_time_init` patches the **second** hop [time.s step 2], which is right on a machine whose
`$FExx` page is still the ROM's. Read again after takeover with IRQs masked, `$010C` survives and
`$FEF7` reads `52 5D 5C 5F 5E` — **this probe's MMU remap destroys the first hop, and it is the
remap, not the crash.** That second read is what separated the two, because a crash with `S=$F41C`
pushes wildly through high memory and could have eaten `$FEF7` itself. Fix is 7 bytes and
probe-local; **no shared HAL file was touched** and `hal_sync_check.py` is clean on all three.

★★★ **Placement is the safety argument**, not an afterthought: after `p3_cal`, because an IRQ inside
the calibration adds cycles it cannot see and would report "SLOW CLOCK" about a build that has the
fast clock — corrupting a measurement rather than crashing, which is worse. Verified: the clock
still reads **1.789772 MHz**. Stack low-water **`S=$07C6`**, 58 bytes used of 768, against a 12-byte
IRQ frame.

**3.2 The box's draw call never existed.** `txt_msgbox` computed `txt_bgx/bgy/bgw/bgh` exactly and
drew only glyphs. `tx_drawbox` follows `graphics.cpp:1079` / `text.cpp:507` including its colours
("Hardcoded colors: white background and red lines" → 15 and 4, which are `$FF` and `$44` at 2
px/byte) and its position between the geometry and `displayText`. ★★★ **Three rectangles, not the
oracle's five, and exactly equivalent**: fill the frame solid then hollow it, and what survives is
byte for byte the four inset lines converted from display pixels to our 2-px bytes.

**3.3 The box was 16 pixels above its own text.** `txt_bgy` is game-screen; the glyphs render at
`txt_srow + txt_rowmin`. ★★★★ **The oracle has the same split and adds the offset at draw time**
[`graphics.cpp:1089`], so the fix matches its structure rather than changing the stored value —
which also keeps `text_probe`'s 4,594-rectangle comparison intact. **The geometry was never wrong,
only the space it was drawn in.**

**3.4 The restore needs no saved pixels, which Jay said before I did.** This project's own oracle
instrumentation records it [`text.cpp:560-564`]: *"the window is closed by RE-RENDERING a rectangle
of the game screen into the display screen. There is no save-under buffer anywhere."* Our game
screen is the SHADOW plane and our display screen is the VISIBLE plane. `txt_close` was a stub;
it now calls `txt_restore`, a vector the probe installs, plus `txt_winactive` — the oracle's own
guard at `text.cpp:550`, without which `txt_close` would restore whatever rectangle the *last* box
left behind.

**3.5 Authority tiers.** Everything above rests on ScummVM at `9d9b9e93` (secondary) except the
vector chain, which is **measured on the machine** (tier 2), and the four screen defects, which are
**Jay's** (tier 1). Per §2.1: the box's colours and geometry are believed **original** — the
hardcoded 15/4 and the inset-line shape are what EGA AGI drew — while the `$FExx` redirect is a
**CoCo3 hardware fact**, not an AGI one.

### 4 — Jay's rulings, and what each produced

| ruling (quoted) | outcome |
|---|---|
| "lets move forward with turning on interrupts… that can lead to stack corruption and the PC jumping into lala land" | Both hazards materialised on the first attempt and both are now measured: stack 710 bytes free, PC explained by the two-hop chain. |
| "do it" (`p3b_text` carries `-DP3B_IRQ`) | Both rows re-baselined with retirement lines; `p3b_box` added because the flag changing and the coverage changing are different facts. |
| "fix the two things" | Restore scoped to the rectangle; `p3b_box` in `run_gates.sh`. |
| "i thought the restore was just a rectangle redraw with no back copy required" | **Correct, and I had overcomplicated it.** §3.4. |
| "first i want you to do a census… that are not in the pinned games" | §4C. |
| "if the freed kilobyte can be spent well then it makes sense to find the 56 bytes and restore the font" | Attempted; **312 bytes short, not 54**. §7.2. |

**4A — The fault arm goes RED.** Open since P6.29c, blocked through P6.30 and P6.31.

| | clean arm | fault arm |
|---|---|---|
| outcome | 40 cycles, no stall | **STUCK in cycle 9**, watchdog fires |
| `hal_frame` across the stall | live | live, **+1799** |
| `vm_vms` across the stall | **+66** | **+0** |
| box | held 1.10 s, auto-closed | never closes |

★★★★ **Interrupts stay healthy in both arms and only the game clock is starved**, which is the defect
§4A's census named rather than a hang arranged by some other route. Re-shown on the **shipped** flag
sets after the configuration changed [L-62].

**4B — `p3b_box`, and the reason it was held out was wrong.** The manifest said its clean arm ends
via `quit(1)` so the completion check would read a failure. ★★★ **Measured: the probe keeps cycling
after `vm_quit`, reaches its full count and exits 0. The claim was never tested when it was
written.** Corrected in the manifest rather than deleted — an untested reason for excluding a gate
is how a gate stays excluded.

**4C — The font census, extended to every game available.**

| population | scanned | use a glyph ≥128 |
|---|---|---|
| commercial PC DOS v2 (the pinned nine) | 9 | **1** — Kingquest2, 15 chars, all codepoint 255, whose glyph is **blank** |
| fan PC DOS v2 | 147 of 150 | **13** — `groza` 30,238 high bytes, `0fb053` 9,558, others 1–6 |
| other PC directories | 0 of 6 | 3 are v3, 3 are not AGI v2 |
| Sierra's own CoCo3 releases | **0 of 7** | V2 directories, **V3 volumes (LZW)** — out of scope this phase |

★★★ **The commercial target is clean and the pinned nine are the complete set of it.** Jay: the
CoCo3 titles "are not concerning because i never intended to run them anyway."
★★★★ **Fold-to-space, not a 7-bit mask**, because the mask sends 255 to 127 whose glyph is *not*
blank — 15 blanks would have become 15 visible marks.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:**
```
★ gates run: pic res cel comp p3b p3b_text p3b_box  -- all green
★ source integrity: clean

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
CHECK OK: src/harness/vm_tables.s matches optable.py.

p3b        13918 B  58AD3C27164BD63FDE17E18041160B285BB8B5C8C1E2F801836532ECB8201E24
p3b_text   15524 B  086938E69112A38CE9EDA7ED2882FB79665576DC038EA732B2E04D23B2514484
p3b_notick 15521 B  A0E4BC6DD7B88FCCA44F1207F7CF9369BA62577A084DD638BD7951749C4CD7C7
```
★★ **`p3b` is byte-identical throughout** — every text change is behind `P3B_NO_CEL`, and that was
verified by rebuild at each step rather than assumed.

**25.2 bundled-artifact grep:** N/A — no bundled artifact; the three probes are hashed above.

**25.3 operator-runtime-smoke:** ★★★★ **OBSERVED, five times, and it is the whole story.** Jay, in
order: *"i'm not actually seeing a box… just the text"* → *"i see the box with the same text
underneath it"* → *"my first enter press is being eaten"* → *"the text is in the box now, but i
don't see the box close"* → *"the box restore was not clean that time, still saw remnants."*

### 6 — Reactive deviations and route accounting
1. **CLAUDE.md v1.9 was edited by me**, on Jay's explicit "add it to claude.md". Normally §2D
   territory; recorded because the instruction, not my judgement, is the authority for it.
2. **`-DTEXT_BOX` was introduced as a holding position and then retired** once the font halving made
   the box fit. It exists in no shipped configuration.
3. ★★★ **ROUTE ACCOUNTING.** I proposed and did not do: instrumenting `HAL_key_scan` for the
   "eaten ENTER" — correctly abandoned, §7.1. I proposed and did do: the whole-plane restore, then
   replaced it with the scoped one at Jay's instruction. **Nothing else was described and left
   unbuilt.**

### 7 — Uncertainty flags

**7.1 ★★★★★ Three of my own claims were wrong. All three are corrected above, and the pattern is one
thing.**

| claim | truth | what I ignored |
|---|---|---|
| the eaten ENTER is a key-scan debounce defect | **not a defect** — the box was not disappearing, so the first press produced no visible change | `tx_wt_nwait` already reported **one box**; I read that as eliminating a hypothesis rather than as the answer |
| `p3b_box` cannot join the suite because `quit(1)` ends the run early | it completes and exits 0 | I never ran it before asserting it |
| restoring the font needs **54** bytes | it needs **312** | the 54 predated `p3_restore_box`, which cost ~288 |

★★★★ **Each was a statement I could have checked in under a minute and did not.** The third is
AD-95's shape exactly — a recorded number whose producer has moved.

**7.2 ★★★★ The font decision is open, and it is now a three-way choice.** 128 glyphs costs 13 fan
titles (degraded to blanks, not garbage); 256 needs **312 bytes**; **or revert the restore to
whole-plane `p3_present`**, which returns ~288 and leaves ~24 to find. ★★★ The third option is
worth weighing precisely because **the scoped restore is the one leaving residue and the
whole-plane version is the one Jay saw close cleanly.**
★★ The freed kilobyte buys nothing elsewhere: in the ENGINE's map the font is at `MAP_FONT` inside
`MAP_TABLES` (~5.7 KB unallocated) and sound's budget is `MAP_RESERVED`'s "parser + sound (floor
3,072)" — a different region. **The squeeze is `p3b`'s own**, caused by orging the parser over
`MAP_FONT`.

**7.3 ★★★★ The scoped restore leaves residue and I have not explained it.** 65 red `$44` bytes
survive inside the rectangle. Established: the rectangle is correctly sized (8 rows above and below
are clean); the **straddle path is not the cause** (row 102 is the only row crossing a slice
boundary here and it is clean); residue sits on rows 91, 96, 99, 104, 107 of 18; the restore does
run (`txt_winactive` 1→0). **Why those five rows is unknown.** The next step is single-stepping, not
another hypothesis — three of my last four about this routine were wrong.

**7.4 ★★★ The comparison instrument was wrong twice before it was trustworthy**, and this is §2W in
miniature. First it compared visible against shadow and reported "the copy did not cover its own
rectangle" — confounded, because the compositor draws sprites onto the visible plane every cycle.
`P3B_RECT` forced the same rectangle in a no-box control: **0 differences**, so the sprite is not
there. Then the count itself proved to **undercount**: box background and this room's picture are
both `$FF`, so unrestored background *matches* and scores zero. Counting `$44` — the one value a
picture cannot supply — is the measurement that holds.

**7.5 ★★★★★ I corrupted files with PowerShell three times, including once in the same session that
reported the previous instance and once after writing the rule into CLAUDE.md.** 34 runs, 59 runs,
then 68. Each caught by check and repaired; all files verify clean. ★★★ **The gate is the guarantee
that actually held** — `run_gates.sh` now fails on double-encoded source, shown red by a real
round-trip and green on repair. §2J.5 is the rule; the gate is why it cannot reach a commit.
★★ I also broke a commit by putting quotes in a PowerShell `-m` string, which is the second standing
memory rule. Both rules existed; neither bound me under momentum.

**7.6 ★★ `err 1` (`RES_E_EMPTY`) appears in the SpaceQuest-2 room 101 runs and is unexplained.** It
stops nothing, and I would rather say so than let it sit in a log looking benign.

### 8 — Follow-up candidates
1. ★★★★★ **The restore residue** (§7.3) — single-step `p3_restore_box` against rows 91/96/99/104/107.
2. ★★★★ **The font decision** (§7.2) — Jay's call between three options, one of them new.
3. ★★★ **`p3b`'s map has outgrown itself.** Parser at `$E000` over `MAP_FONT` is what forces every
   font compromise; the engine's own map has no such conflict.
4. ★★ **A PreToolUse hook denying shell writes to tracked files** (§7.5). The gate catches residue;
   only a hook catches the cause. There is no `.claude/` directory in this repo yet.
5. ★★ **v3 LZW volumes** would make Sierra's CoCo3 releases scannable; §2P already puts that on the
   target's critical path.
6. ★ **`err 1`** (§7.6).

### 9 — User interaction during task
Extensive and directive throughout; every ruling is quoted in §4. Five eye-gate observations are
quoted verbatim in §5's 25.3, and **each one found a defect no gate could see.**

### 10 — Candidate(s) captured this task
None yet — the two strongest candidates (a stale budget quoted past its producer; an instrument
confounded by the thing it measures) are already recorded as AD-95 and §2W instances. **Flagged for
the Orchestrator rather than captured, because both may be folds into existing rows.**

### 11 — Commit
`ab89018` and the twelve before it, from `1bd7648`. All pushed to origin/wip before this report.
