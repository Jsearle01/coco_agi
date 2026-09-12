## Form B Report — T-P0-088 / P6.33 — The box closes clean; `ldd` clobbered the loop count
**Class:** integration.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-12 13:40 (HEAD 7d7f042, wip). Clean but for the two untracked files that are not mine —
`agi-coco3-design-v1_3.md` (Orchestrator's, §2D) and `coco_agi.code-workspace` (Jay's).

### 1 — Summary
★★★★★ **COPY, not source — and §1.1's lead was wrong.** §4A's one read came back clean on all seven
rows, so the shadow plane was never contaminated and that whole branch was eliminated for the cost
of one run.

The defect is **one instruction order**. `p3rb_span` loaded the row width into B, then loaded the
offset with `ldd` — **which writes A and B** — so the loop count silently became the low byte of
the offset. `$44` inside the rectangle after close: **65 → 0**. Jay, live: *"looked good."*

★★★★ **Every traced parameter was correct**, which is what made this invisible for three rounds of
hypotheses.

### 2 — Files modified
- `src/harness/p3b_probe.s` — the fix in `p3rb_span`; §4B(ii)'s per-row trace (`P3_RBTRACE`); two
  branches lengthened to `lbhs`/`lbra` because the trace pushed their targets out of byte range.
- `harness/tools/p3b_run.lua` — §4A's shadow read; the trace readout with an independent
  recomputation of `within`.
- `harness/tools/p3b_show.ps1` — the two new symbols.
- `harness/tools/gates.manifest` — both rows re-baselined with retirement lines.

### 3 — Reasoning

**3.1 §4A settled the branch, and the Orchestrator's lead was the branch it eliminated.**
Sampled with the box still on screen and `txt_close` not yet run — var 21 unarmed, so the guest
parks in the wait loop and the watchdog dumps while the box is up:

| row | shadow `$44` | visible `$44` | |
|---|---|---|---|
| 91 | **0** | 0 | residue row |
| 96 | **0** | 2 | residue row |
| 99 | **0** | 2 | residue row |
| 104 | **0** | 2 | residue row |
| 107 | **0** | 72 | residue row |
| 93 | **0** | 2 | control |
| 100 | **0** | 2 | control |

★★★ **The shadow is clean everywhere**, so box drawing never reached it and `p3_restore_box` was not
faithfully re-rendering contamination. ★★ The visible column also confirms the box is drawn
correctly: 2 per row is the left and right border bytes, 72 on row 107 is the bottom border.

**3.2 §4B(ii)'s trace: every parameter correct, result still wrong.** Recorded by the guest at the
moment it acted, for all 18 rows, with `within` checked against an independent host computation:

```
r91:w6411/n74  r92:w6571/n74  r93:w6731/n74  r94:w6891/n74  r95:w7051/n74  r96:w7211/n74
r97:w7371/n74  r98:w7531/n74  r99:w7691/n74  r100:w7851/n74 r101:w8011/n74 r102:w8171/n21
r103:w139/n74  r104:w299/n74  r105:w459/n74  r106:w619/n74  r107:w779/n74  r108:w939/n74
```
★★★★ **No mismatches, including the straddle row correctly taking `n=21`.** Row, offset and count
were all right and the copy still failed.

**3.3 ★★★★★ The defect.**
```
                ldb     p3rb_n          ; B = 74, the row width
                ldd     p3rb_within     ; ★ ldd loads A AND B -- B is destroyed here
```
The loop ran for the **low byte of the offset**. `within` advances by 160 per row, so its low byte
cycles `$0B $AB $4B $EB $8B $2B $CB $6B` — **period 8**. Exactly two are below the 74-byte width:
`$0B`=11 and `$2B`=43. Rows 91, 96, 99, 104, 107 are precisely those.

★★★ **The pattern was legible from the start and I did not read it.** Offsets 0, 5, 8, 13, 16 look
arbitrary; modulo 8 they are 0, 5, 0, 5, 0. A period-8 quantity in a loop whose only per-row change
is adding a stride points at that stride's low byte, and a low byte only matters if something uses
it as a count.

★★ Rows whose low byte exceeded 74 copied *too much*, overrunning into the following row — which is
why thirteen rows looked clean and why the margins above and below always read 0.

**3.4 Authority tier.** No oracle question arose; this is a port-side defect measured on the machine
(tier 2) and confirmed by Jay (tier 1).

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — §4A's seven-row read with its branch.** **MET.** §3.1; selected §4B(ii).
- **AC-2 [state-comparable] — `$44` inside the rectangle after close: ZERO.** **MET.** 65 → **0**,
  same trigger, P6.32 §7.4's instrument. Per-row all zero, and visible-vs-shadow is 0 inside the
  rect with 0 in both 8-row margins.
- **AC-3 [state-comparable · control] — no-box control still 0.** **MET.** `-Fault` with
  `P3B_RECT=43,91,74,18`: **0 bytes differ.** The fix is not a broader repaint wearing a narrow name.
- **AC-4 [state-comparable · fault injection] — `-DTEXT_FAULT_NOTICK` still RED.** **MET.** Stalls in
  cycle 9; `hal_frame` +1799 while `vm_vms` +0. Re-shown on the shipped flag sets [L-62].
- **AC-5 [byte-comparable] — `p3b` byte-identical.** **MET.** `58AD3C27164BD63F…`, 13,918 B.
- **AC-6 [byte-comparable · gate] — `vm` 9/9, `res` 1,264/1,264.** **MET**, both fresh.
- **AC-7 [suite] — full suite green.** **MET.** `pic` 45/45 · `res` 1,264/1,264 · `cel` 9,193/9,193 ·
  `comp` 124/124 · `p3b` · `p3b_text` · **`p3b_box`**, plus the mojibake gate.
- **AC-8 [manifest] — re-baselined with retirement lines.** **MET.**

  | row | retired | now |
  |---|---|---|
  | `p3b_text` | `ED3F248A…` 15,548 B | **`63597E4D…` 15,561 B** |
  | `p3b_notick` | `ED500A37…` 15,545 B | **`DA798353…` 15,558 B** |

- **AC-9 [eye gate — Jay] — the box closes clean, no remnants.** ★★★★ **MET — Jay, live-disk path
  not used; poke path, RGB, `screen_config=1`: "looked good".** ★★ This is the observation that
  opened the defect [P6.32 §5], so it is the one that closes it.
- **AC-10 [tooling]. MET.** `[hal-sync] OK … 11 files compared` · `[reg-discipline] 8 register
  access(es) in 1 file(s)` · `CHECK OK: vm_tables.s matches optable.py`.
- **AC-11 — candidates.** §10.

### 5 — Verdict-time evidence (v0.7 §11)
**25.1 fresh tool output:**
```
=== AC-2 SUMMARY ===   [vm_run.ps1]   all nine titles PASS
byte-identical resources: 1264 across 10 (title, volume) sweeps ; all sweeps clean

★ gates run: pic res cel comp p3b p3b_text p3b_box  -- all green
★ source integrity: clean

RED ($44) bytes still in the visible plane inside the rect: 0 -- no border left
visible vs shadow: INSIDE the rect 0 bytes differ; 8 rows above 0; 8 rows below 0
per row: r91:0 r92:0 ... r107:0 r108:0

[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
CHECK OK: src/harness/vm_tables.s matches optable.py.

p3b 13918 B 58AD3C27164BD63FDE17E18041160B285BB8B5C8C1E2F801836532ECB8201E24
```
**25.2 bundled-artifact grep:** N/A — no bundled artifact; probe hashes in AC-8.
**25.3 operator-runtime-smoke:** ★★★★ **PASSED — Jay, poke path, RGB: "looked good".**

### 6 — Reactive deviations and route accounting
1. **Two branches lengthened to `lbhs`/`lbra`.** The trace pushed their targets past byte range;
   mechanical, and the assembler caught it rather than a wrong offset shipping.
2. ★★★ **The per-row trace is KEPT** — ~30 bytes of 706 headroom. It is the instrument that found
   this and a recurrence would show in it immediately. **Flagged as a judgement call for Jay**, not
   presented as obviously right.
3. ★★ **ROUTE ACCOUNTING.** Nothing was proposed and left unbuilt. §6's triggers were not reached:
   no whole-plane re-presentation, no compositor or plane-window change, no `SHARED` file.

### 7 — Uncertainty flags

**7.1 ★★★ The over-copy was real and is now gone, but it wrote outside the rectangle while it
lasted.** Rows whose low byte exceeded 74 copied up to 235 bytes, running past the row's right edge
into the next row's span. It happened to be harmless — the following row was about to be copied
anyway, and the measured margins stayed clean — **but it was an unbounded write driven by an
uninitialised-in-effect count, and it had been shipping since the scoped restore landed.**

**7.2 ★★ The five-row pattern was legible and I read past it three times** (§3.3). Recorded because
the cost was three rounds of wrong hypotheses, not because the fix was hard.

**7.3 ★★ `err 1` (`RES_E_EMPTY`) still appears in these runs and is still unexplained** [P6.32 §7.6,
out of scope here].

**7.4 ★ The font stays at 128 glyphs.** Untouched this task per §2; the 256-glyph question is
T-P0-089 and is a map problem.

### 8 — Follow-up candidates
1. ★★★★ **T-P0-089: the font and `p3b`'s map.** Restoring 256 glyphs needs **312 bytes** [P6.32
   §7.2], and the root cause is that this probe orgs the parser over `MAP_FONT` — the engine's own
   map has no such conflict.
2. ★★ **`err 1`** (§7.3).
3. ★★ **A PreToolUse hook denying shell writes to tracked files** [P6.32 §8.4]; the gate catches
   residue, only a hook catches the cause.
4. ★ **Consider whether `p3rb_span`'s shape should be an idiom entry** — "load counts after
   addresses, never before" is a one-line rule that would have prevented this.

### 9 — User interaction during task
Jay confirmed AC-9 on the live screen: **"looked good"**. No other interaction.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-12-every-parameter-correct-and-the-result-wrong-means-suspect-the-registers.md`
- `seeds/AGI/live/2026-09-12-ask-whether-the-source-is-wrong-before-debugging-the-copier.md`

★★ The second credits the dispatch: **§4A's discrimination was right for reasons independent of the
lead attached to it**, which is the shape worth keeping — mandate the measurement, hold the
hypothesis loosely.

### 11 — Commit
`7d7f042` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `6cbb11f`, two rows under `seeds/AGI/live/`.
