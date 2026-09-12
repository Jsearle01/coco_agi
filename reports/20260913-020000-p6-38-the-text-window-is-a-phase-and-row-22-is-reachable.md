## Form B Report — T-P0-093 / P6.38 — The text window is a phase; row 22 is reachable
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-09-13 02:00 (HEAD 11a2dda, wip). Six files modified; the two known untracked files.

### 1 — Summary
★★★★★ **You can see what you type.** The text window became a phase in `mmu_phase.s` and grew to
four slots, so the command line at row 22 — pixel row 176, byte 28,160 — is inside it. Measured:
**55 of 1,280 bytes of ink on row 22 for four characters, against 0 under the fault arm.**

★★★★★ **`vm_text_ops.s` writes no MMU register.** The question its own comment raised six tasks ago
is closed, and `mmu_phase.s` is the sole writer again.

★★★★ **Three colour defects, all found by Jay looking and none by any byte gate**, all fixed at his
instruction: the text strip was white, the attribute had no default, and the message box's
attribute leaked because `charAttrib_Push`/`Pop` were never ported.

### 2 — Files modified
- `src/engine/mmu_phase.s` — `phase_text_in`/`_out`, `ph_blk_text`/`slot3`/`slot4`, `MMU_SLOT3`/`4`,
  the header's new exception.
- `src/engine/text.s` — `txt_attrib_push`/`_pop` and their use in `txt_msgbox`; **two off-by-one
  window bounds**.
- `src/harness/vm_text_ops.s` — the mapping delegated; `TX_WIN` $8000 → $6000; HAZARD 1 rewritten.
- `src/harness/p3b_probe.s` — `PHASE_TEXT`, the block numbers, the attribute default, the black
  text strip.
- `harness/tools/p3b_run.lua`, `p3b_show.ps1`, `run_gates.sh`, `gates.manifest`.

### 3 — Pre-dispatch grep (C-13)

| check | expected | found |
|---|---|---|
| the five artifacts | the P6.37 hashes | ✔ |
| region A headroom | 1,723 | **1,723** |
| `reg_discipline.py` | 10, one file, two registers | ✔ |

★★★★ **§3(3) — every MMU writer in the tree, and there were FIVE files, not two.** The dispatch
expected `mmu_phase.s` and `vm_text_ops.s`:

| file | writes | verdict |
|---|---|---|
| `mmu_phase.s` | 10 | the sanctioned owner |
| `vm_text_ops.s` | **5** ($FFA4 ×2, $FFA5 ×2, $FFA6) | **this task removes them** |
| `p3b_probe.s` | **1** | ★★★ the **cel** branch only, and it exists to keep `p3b` byte-identical |
| `input_probe.s` | 4 | a different probe's own boot map |
| `sys.s` | 8 | SHARED HAL, the boot map — legitimately its own |

★★★ **`reg_discipline.py` scans `src/engine` only, so `vm_text_ops.s`'s five were never counted.**
The ownership claim was never checkable by the census; it needed this grep, and that is worth
keeping because AC-2 is phrased in terms of the census.

### 4A — What must be mapped during a blit (enumerated fresh, from the build's own map)

| | address | slot | needed while the window is open? |
|---|---|---|---|
| the font | `P3_FONT` **$E3BA** | **7** — never remapped | yes, and it is safe |
| the substituted text | `P3_PBUF` **$1C00** | **0** — never remapped | yes, and it is safe |
| `txt_prompt` and all `txt_*` state | **$4F3F-$5498** | **2** — never remapped | yes, and it is safe |
| the string table (the `>` prefix) | `txt_strbase` = **0** | — | skipped; no base to read |
| stack, direct page | $0500-$0800, $0000-$001F | **0** | yes, and it is safe |
| **the framebuffer** | $6000-$DFFF | **3-6** | this IS the window |

★★★★★ **NOTHING in slots 3-6 is read during a blit.** §6's first trigger does not fire. The
arena (slots 3-4) is read by `txt_printf`, which runs before the window opens; the vocabulary
(slot 5) is read by `par_parse`, which the oracle's own parse-then-redraw order puts before it;
the volume window (slot 6) is read by `res_open`, which is not on this path.

★★★★ **And that is what makes HAZARD 1 a requirement.** `vm_text_ops.s` recorded the `txt_pbuf`
isolation as *"luck, and it is recorded as luck rather than as design."* The window used to borrow
slot 4; it now borrows slot 3 as well, so **the arena is completely unmapped for the whole blit and
there is no partial case left to be lucky about.** That paragraph is rewritten.

### 4B — The mapping moved, and the contract's exception

`phase_text_in` writes four slots from one block number and three increments; `phase_text_out`
restores slots 3, 4 and 5 from `ph_blk_slot3`/`4`/`5` and hands slot 6 to `phase_vm`.

★★★★ **The restore values and where they come from:** `p3b_run.lua` pre-sets all eight slots to
`$38+i` at load, so slot 3 is **$3B** and slot 4 is **$3C** — the same `$3C` `vm_text_ops.s` used to
carry as `TX_ARENA_HI`, now stated once beside the slot-5 value. **The registers are write-only, so
these are the only record of what was mapped**; a wrong value unmaps the arena permanently.

★★★★★ **The header's new exception, quoted:**
> *"THE EXCEPTION, AND IT IS AN EXCEPTION TO THE SENTENCE ABOVE. The TEXT WINDOW borrows slots 3
> AND 4 as well, for the duration of one glyph blit or one line clear, and puts them back by known
> value. **Slots 0-4 are no longer "never touched"; slots 3 and 4 are touched by
> phase_text_in/_out and by nothing else.**"*

★★★ **§1.1's framing was right.** The fourth slot could not be had without moving ownership — not
because of the register, but because the restore has no save and therefore belongs beside the
contract it excepts.

### 4C — The arithmetic

$6000-$DFFF = **32,768 B**. A character row is 8 × 160 = **1,280 B**. Row 24's last byte is
(24×8+7)×160 + 159 = **31,999** < 32,768. Row 25's would be **33,279**, past the window and into
slot 7's parser. **`TX_WIN_ROWS` = 25, rows 0-24, which is `TXT_ROWS`.**

★★★★★ **AND BOTH BOUNDS WERE OFF BY ONE, WHICH THIS TASK MADE REACHABLE.** `txt_fbrows` is a count;
`txt_blit` tested `bhi` (allowing `crow == fbrows`) and `tx_boxfill` computed `yhi = (fbrows+1)*8`.
At three blocks the slack was row 19 and nothing drew there. **At four blocks the slack is row 25,
whose last byte is 511 bytes into the parser.** Both corrected — `bhs`, and the `inca` removed.

### 4D — AC-3 and AC-5, as counts

| arm | row 22 ink | keys to the editor | verdict |
|---|---|---|---|
| clean, 25 rows | **55 of 1,280** | 4 | ★ drawn |
| `-DTEXT_WIN3`, 19 rows | **0 of 1,280** | 4 | ★★★ **RED** |

★★★★ **The fault arm is the ROW BOUND, not the slot count, and that is a deliberate change from
§4D's wording.** Mapping three slots from `vm_text_ops.s` would have put an MMU write back into the
file this task emptied — **the fault arm would have re-created the defect the clean arm just
fixed** — and it moves two variables instead of one [L-73].

### 4E — ★★★★★ The instrument I withdrew, and the check that caught it

The first AC-3 instrument marked row 22 with a pattern before the run and counted survivors, on the
theory that only `clearLine(22)` could wipe it. **It passed on the clean arm and passed on the
fault arm.**

★★★★★ **The §2W check is what settled it: run the case that should leave the mark alone.** In room
83 the prompt is never enabled, so nothing should clear anything — and the mark vanished there too,
leaving the band uniform `$FF`, **the colour `p3_clear_planes` writes.** The plane clear reaches
that band, so the instrument was measuring the renderer and reporting it as the text engine.

★★★ **Two green results, one of which should have been red, and the fault was the INPUT rather than
the adjudication** [AD-90, AD-102, AD-122]. What replaced it injects a key at `p3_keybuf` and counts
ink — the path under test and nothing else.

★★ **A second instrument defect, same task:** the ink metric's baseline was the row's **first**
byte, which is inside the first glyph. Four characters read as 1,267 of 1,280 differing. The
baseline is the row's **last** byte now, and the same four characters read 55.

### 4F — The three colour defects [Jay's instruction to land them]

| | cause | citation |
|---|---|---|
| the text strip was white | `p3_clear_planes` whitens four whole slices = 32,768 B; a PICTURE is 26,880. `p3_present` copies all four, so the 5,120-byte tail arrived white every room change | — probe's own |
| the prompt row started white | **the text attribute was never initialised.** The constructor sets `charAttrib_Set(15, 0)` | `text.cpp:46` |
| it stayed white after a box | **`charAttrib_Push`/`Pop` were never ported.** The oracle brackets the box and pops back; we ported the set alone, so black-on-white leaked permanently | `text.cpp:453`, `:455`, `:516` |

★★★★ **None was visible before this task**, because nothing had ever been drawn on row 22. Measured
after: `fg=15 bg=$00`, **normal rather than inverted**, and the row's background reads `$00`.
★★★ **One level of attribute save, not the oracle's stack** — `_textAttribArray` exists because the
oracle nests and our box does not. The depth is stated rather than assumed [§2V.2].

### 5 — Verdict-time evidence (v0.7 §11)
```
p3b          13918 B  58AD3C27164BD63FDE17E18041160B28   <- byte-identical, AC-8
p3b_text     16258 B  5B19334FAD8E7AB0F8A7A54C8687163A
p3b_win3     16258 B  5400A30F609A52B5EB8957C0511EC7A5
p3b_notick   16255 B  F7AE0FCFBF0BB3F0DD10D7DF883B7D99
p3b_nomap    16255 B  9604AAAA121CA3D328BFF76E0E5C02CA
p3b_fault    15382 B  16DC35EF28CF1193A21F38EA4D85650A
region A: P3_CODE_END $59AA, headroom 1,622 B

★ source integrity: clean
per-picture: 45 PASS   resources 1264/1264   cels 9193/9193   composites 124/124
★ gates run: pic res cel comp p3b p3b_text p3b_box p3b_parse p3b_row22  -- all green
   p3b_parse: 1 word [161] and 1 word [160], notfound=0 -- unchanged
   p3b_row22: 55 of 1280 bytes differ from $00, keys 4 -- the command line is DRAWN
AC-2 SUMMARY: nine titles, 9/9 PASS
[reg-discipline] 17 access(es) in 1 file(s) over 4 register(s).  src/engine/mmu_phase.s
[hal-sync] OK x3.   CHECK OK: vm_tables.s matches optable.py.

FAULT ARMS, all three RED on THESE binaries:
  p3b_win3   0 of 1280 on row 22    p3b_notick  STUCK cycle 9    p3b_nomap  STUCK cycle 30
```
★★★ **AC-2's delta explained:** 10 → **17**, one file, two → **four** registers. +7 is
`phase_text_in` (4) and `phase_text_out` (3). **The five that left `vm_text_ops.s` were never in the
census** — it scans `src/engine` — which is exactly why §3(3)'s whole-tree grep exists.

**25.2 bundled-artifact grep:** N/A.
**25.3 operator-runtime-smoke:** **PASSED — Jay, live, RGB**, Kingquest1 room 1. Characters appear
as typed; after the colour fixes, *"the color is corect now"*. §9 has his words.

### 6 — Reactive deviations and route accounting
1. ★★★★ **The fault arm is the row bound, not three slots** (§4D). Stated because it diverges from
   the dispatch and the reason is AC-2's own criterion.
2. ★★★★★ **Three colour fixes landed on Jay's instruction**, outside §4's scope (§4F). Offered with
   the citations before any were made.
3. ★★★★ **Two off-by-one window bounds corrected in `text.s`** (§4C). Not in the dispatch; the
   four-slot window turns the slack into a write into the parser.
4. ★★★ **An instrument built, shown non-discriminating, and withdrawn** (§4E).
5. ★★ **`p3b_show.ps1`'s five `-or` chains collapsed to two predicates.** Adding one arm meant
   editing five identical lists; the sixth would have been edited in four of them.
6. **ROUTE ACCOUNTING.** §4B's mapping, §4C's arithmetic and §4D's arm are as described. Nothing
   proposed and not done.

### 7 — Uncertainty flags

**7.1 ★★★★ The game restarts, and Jay's sequence is the sharpest record of it yet.** *Copyright
message → title page, scroll NOT working → castle room, typing fine → message box dismissed →
copyright again while still in the castle room → title page, scroll working → castle room → exit.*
★★★ **The reference ends in room 1 and the guest ends in room 83** on the same 400-cycle run with
the same forced jump. This is the `err 1` cluster, now six tasks old, and §10 puts it out of scope.
★★ **It is the harness's forced jump landing mid-intro, or it is a port divergence, and this task
did not distinguish them.**

**7.2 ★★★ `p3b_probe.s` still writes `$FFA5` once**, in the branch that exists only to keep `p3b`
byte-identical (§3(3)). AC-2 is true of the text configuration and has this one documented
exception in the cel one. Removing it moves the timing row's binary.

**7.3 ★★ The `>` prefix is still absent** and still correct — `set.string` is a bare `rts`, so
`txt_strbase` is 0 and the port skips rather than reading from address 0 [P6.37 §7.2]. Jay noted it
again; it is out of scope by §2 and is §8.3.

**7.4 ★★ `p3b_row22` is blind to colour.** Ink counts bytes differing from the row's last byte; a
row drawn in the wrong attribute counts identically. **All three of §4F's defects would pass it**,
and a person found every one.

### 8 — Follow-up candidates
1. ★★★★★ **The restart / `err 1`** (§7.1). Six tasks. The reference-versus-guest room divergence is
   a concrete place to start.
2. ★★★★ **The integrated run** — the last component is in.
3. ★★★ **`set.string` and the `>` prefix** (§7.3).
4. ★★★ **A key queue or VBL latch**, so a fast typist is not dropped, and `p3b_type` as a real gate.
5. ★★ **An attribute check in `p3b_row22`** (§7.4) — the colour of the row, not only its ink.
6. ★★ **The status line**, which row 22's reachability also unblocks.

### 9 — User interaction during task
1. Eye gate, before the colour fixes — *"they did apper, but they are appearing on white which
   makes them inverted against the other white rows in that area, still no '>'"*.
2. Clarification — *"the letters themselves look to draw properly, its that the rows above and
   below are white and make it look off. also, the line i type on starts off white as well and
   contributes to the wierd look"* → §4F's three causes.
3. Asked whether to land the three colour fixes in this task: **"Land all three now."**
4. Eye gate, after — *"so the color is corect now, but you have other issues"*, followed by the
   restart sequence in §7.1.

### 10 — Candidate(s) captured this task
- `seeds/AGI/live/2026-09-13-the-check-that-cannot-fail-on-the-arm-that-should-fail.md`

### 11 — Commit
`95fa64e` (pushed to origin/wip before this report).
Pool: `methodology-candidate-pool` `a83685b`, one row under `seeds/AGI/live/`.
