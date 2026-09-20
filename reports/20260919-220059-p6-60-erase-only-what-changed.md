## Form B Report — T-P0-114 / P6.60 — Erase only what changed; Graham is steady
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 22:00:59 (HEAD 3d1c756, wip). Four files: `src/harness/p3b_probe.s` +87,
`harness/tools/p3b_run.lua` +14, `harness/tools/p3b_show.ps1` +12/−1,
`harness/tools/p3b_arms_check.ps1` +5/−2. ★★ **`src/hal/` untouched** [§6].

### 1 — Summary

★★★★★ **Jay, at the eye gate, answering the three expectations the ask carried:** ***"graham is
steady and the flags blink. no square background."*** **All three as predicted** — the fix works,
the residual is the one that was declared in advance, and the box did not come back.

★★★★★ **AND THE CENSUS IS FINALLY CLOSED, in both directions, after being owed for three tasks:**

```
clean (changed only)   : restore 186,240 bytes over 300 cycles = 620.8 / cycle
always-restore (fault) : restore 270,048 bytes over 300 cycles = 900.2 / cycle
                delta  :          83,808 bytes = 31.0% never touched
```

★★★★ **The two builds differ by one flag and five bytes**, so the gap is attributable and is
exactly the bytes not copied for unchanged sprites. ★★★ **31% is one sprite in four, which is what
"Graham is the static one" predicts.**

★★★ **The flags still blink and that is not a defect of this change.** They change cel every frame,
so they are erased by definition. Only a page flip removes theirs, and that is blocked behind a
`src/hal/` task [P6.59 §3.2].

### 2 — Files modified

- `src/harness/p3b_probe.s` — `P3_PREV_SIZE` 4 → **7** (the cel's identity joins the rectangle);
  the recorder stores view/loop/cel; `prp_same`; the skip in `prp_each`;
  `-DP3B_FAULT_ALWAYSRESTORE`.
- `harness/tools/p3b_run.lua` — the restore figure **moved into the unconditional summary**.
- `harness/tools/p3b_show.ps1` — `-AlwaysRestore`; `restore \d+ bytes` added to the console
  allowlist.
- `harness/tools/p3b_arms_check.ps1` — `p3b` re-baselined 14,666 → **14,785 / B3E4AD4C**.

### 3 — Reasoning

#### 3.1 §4A / AC-1 — what "changed" means, stated before the code

> **Changed = `x`, `y`, `view`, `loop`, `cel` differ from this frame's staged sprite at the same
> index.** Geometry **and** cel identity.

★★★★★ **Geometry alone is not enough and the failure mode is worse than the blink.** The record was
four bytes — `x, ytop, w, h` — so **a sprite that stays put and swaps to a different cel of the same
size compares equal.** Skipping its erase would leave the old cel on screen **permanently**. The
record now carries three identity bytes (+48 B across `P3_SPR_MAX`), and the reasoning is written
beside the comparison so the next reader knows what the test protects.

★★★★ **The comparison is possible because the staged list is already built:** `p3_stage_sprites`
runs at phase 5, `p3_restore_prev` at phase 9. ★★★ **Index-wise, and safe in the only direction
that matters** — a shifted set disagrees and we restore (merely wasteful), while a false *skip*
would need all five fields to match, and a sprite matching all five has identical pixels whatever
its index.

#### 3.2 §4B — the sprite is still COMPOSITED, and the priority plane is why

★★★★★ **Skipping the erase must not mean skipping the draw.** A changed neighbour's restore can
reset priority **inside** an unchanged sprite's rectangle, and the composite pass is what repairs
it.

★★★ **Re-compositing is harmless on both planes.** The visual write is identical. On the priority
plane `co_depth` reads what is already there — which, for a sprite that was not erased, is **its own
stamp from last frame** — and re-stamps the same `viewPriority`, so the depth test reaches the same
decision. ★★ **Pixels it did not draw last frame still hold the picture's priority**, so those
decisions are unchanged too.

★ **And it does not reintroduce the blink**, because the blink is the erase: writing identical
pixels over identical pixels changes nothing on screen.

#### 3.3 ★★★★ A Z-flag bug caught by reading the flags rather than the branch

`prp_same` returns "unchanged" in Z. The first version began:

```
                lda     p3rp_i
                cmpa    p3_nspr
                bhs     prp_ns_no       ; no sprite i this frame -> changed
...
prp_ns_no:      rts
```

★★★★★ **`cmpa` SETS Z when `i == p3_nspr` — which is the commonest way to reach that branch (the
list shrank by one) — so it would have returned "unchanged" and skipped erasing a sprite that had
just been REMOVED, leaving it on screen permanently.** ★★★ That is the same failure §3.1's identity
bytes exist to prevent, arriving by a different route. Fixed with an explicit `andcc #$FB`.

★★ **Found by tracing the flags out of the compare, not by testing** — and it would have been
invisible to the census, which counts bytes and not absences of sprites.

#### 3.4 ★★★★★ The counter was never published, and an allowlist is why

P6.58 owed a per-frame byte figure. P6.59 "published" it and produced no number. **This task found
both reasons, and neither was the guest:**

1. The readout was placed beside the composite counters, **inside a diagnostic block that does not
   run on an ordinary sweep.**
2. ★★★★ **Even once moved to the unconditional summary, the console shows an ALLOWLIST of patterns**
   [`p3b_show.ps1:400`] **and nothing named it.** The line was written to `run.log` and dropped on
   the way to the screen.

★★★★★ **So for two tasks the guest computed the number correctly, a reader existed in the host, and
it was invisible.** ★★★ **A counter whose readout is behind a flag nobody passes, or a filter that
does not name it, is not published — it is written down.** The file's own comment warns that *"an
allowlist filter drops what it does not name, and what it does not name is always the newest
thing"*; **this is the fourth instance and the warning is now cited beside the fix.**

#### 3.5 §4D / AC-3 — the figures

| | clean | always-restore | delta |
|---|---|---|---|
| bytes restored, 300 cycles | **186,240** | 270,048 | **−83,808 (−31.0%)** |
| per cycle | **620.8** | 900.2 | −279.4 |
| rects live at exit | 2 | 2 | — |

★★★ **What remains unmeasured:** the animating sprites' gap in milliseconds. The blink's *duration*
is the number that would decide between a page flip and a per-sprite interleave, and **it needs a
raster-relative measurement this harness does not take.** §7.3.

#### 3.6 §2H check 3 — the reports, grepped

P6.55 → P6.60 is one chain and each report's caveat is discharged by the next. ★★ **P6.59's "shape 3
is reasoned, not measured"** [§7.3 there] **is discharged here by §1's census and Jay's sentence.**

### 4 — Verification (AC-by-AC)

- **AC-1 [design] — MET.** §3.1, reported before the implementation, with the missed-change failure
  named.
- **AC-2 [state-comparable] — MET, both directions.** §1. ★★★★ **Owed since P6.58 and closed.**
- **AC-3 [measurement] — PARTIAL.** §3.5's table is complete for bytes and rectangles; ★★ **the
  residual blink's duration is not measured** and is called out rather than estimated.
- **AC-4 [fault injection] — MET.** `-DP3B_FAULT_ALWAYSRESTORE` → **14,780 B / 45079437**, −5 B (the
  `jsr` + `beq`), run headless, and **differencing it is what produced AC-2's census.** ★★
  `-NoRestore` retained as the second arm.
- **AC-5 [byte-comparable] — MET.** Six text arms byte-identical; `src/hal/` untouched.
- **AC-6 [byte-comparable · gate] — MET, fresh.** `comp 124/124 (100.00%)` · `cel 9,193/9,193
  (100.00%)` · `pic 45/45 PASS` · `res 1,264/1,264 (100.00%)`. `vm` cited under §2T —
  `vm_probe.s` unchanged.
- **AC-7 [eye gate — Jay] — MET, offered before the byte gates, with the expected observation in the
  ask.** *"graham is steady and the flags blink. no square background."* ★★ **Question 4 (anything
  left behind) was not explicitly answered** — §7.2.
- **AC-8 [suite] — PARTIAL.** Four byte gates and the seven-arm check green; `$44`, `p3b_rescheck`
  and `-CelCheck` not run.
- **AC-9 [manifest] — MET.** `p3b` re-baselined; `★ all 7 shipped arms byte-identical`.
- **AC-10 [tooling] — MET.** `hal-sync OK (11 files, POP3_port + karateka_coco3)` ·
  `reg-discipline 17 in 1 file over 4 registers` · `gen_vm_tables CHECK OK` · `fix_mojibake --check`
  clean on all four edited files. ★ `probe_identity_check.ps1` not run — `comp_probe` untouched,
  `comp` green.
- **AC-11 — MET.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
$ lwasm ... src/harness/p3b_probe.s        -> 14785 B  B3E4AD4C   (+119 over P6.58)
$ ... -DP3B_FAULT_ALWAYSRESTORE            -> 14780 B  45079437   (-5 B)
$ ... -DP3B_NO_CEL -DHAL_KEYBOARD -DP3B_IRQ-> 16409 B  D09866C3   (unchanged)

$ p3b_arms_check.ps1
p3b 14785 B3E4AD4C OK ; six text arms OK ; ★ all 7 shipped arms byte-identical

$ census.ps1   (P3B_ROOM=1, 300 cycles, headless)
clean          : restore 186240 bytes over 300 cycles = 620.8 per cycle  (2 rects live)
always-restore : restore 270048 bytes over 300 cycles = 900.2 per cycle  (2 rects live)
both arms      : final room 1, sprites 4, err 0, status=$00, no stall

$ run_gates.sh comp -> 124/124 identical, 0 divergent   ★ all green
$ run_gates.sh cel  -> 9193 / 9193 (100.00%)            ★ all green
$ run_gates.sh pic  -> 45 PASS, 0 FAIL                  ★ all green
$ run_gates.sh res  -> 1264 / 1264 (100.00%)            ★ all green

$ hal_sync_check.py -> OK, aligned with POP3_port, karateka_coco3 (11 files)
$ reg_discipline.py -> 17 access(es), 1 file, 4 registers (mmu_phase.s)
$ gen_vm_tables.py --check -> CHECK OK
$ fix_mojibake.py --check <4 edited files> -> clean
```

**25.2 bundled-artifact grep:** N/A.

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED — Jay, live, RGB, room 1, 400 cycles at 99.31%.**
*"graham is steady and the flags blink. no square background."*

★★★★ **AND THE ASK CARRIED ITS OWN EXPECTED ANSWER THIS TIME** [§4E]. P6.59 §3.1 and T-P0-105 both
asked Jay to judge a screen without saying what to look for and he had to ask both times. **This ask
named all three expectations, including the one that was NOT going to be fixed**, and his reply
addressed each in order. ★★★ **The fix was in the framing, not in the observer.**

### 6 — Reactive deviations and route accounting

★★ **No §6 trigger fired.** The second — *"the census shows an unchanged sprite's background IS
being touched"* — **could fire and did not**: §1's delta is the measurement that would have shown it.

**Deviation.** ★★★ **§4C's census was not built as a plane census.** The dispatch asked for bytes of
background compared between frames; I measured it instead by **differencing two arms that differ in
one variable**, which counts the same thing from the other side and needed no new instrument. ★★
**A plane-content census would additionally prove the restored bytes are the RIGHT bytes**, and that
is still not proven by anything except `pic` 45/45 and Jay's eye. §7.1.

**Route accounting.** ★★ I proposed nothing beyond the dispatch and implemented exactly §4A-§4B.
**The page flip was not touched and `src/hal/` was not opened.**

### 7 — Uncertainty flags

1. ★★★ **The census counts BYTES MOVED, not bytes correct.** It proves the restore ran over the
   right rectangles and skipped the right ones; **it does not prove the copied values are the
   picture's.** The straddle clamp (§7.4) is exactly the kind of defect it would miss.
2. ★★ **Eye-gate question 4 was not answered.** *"Anything left on screen that should not be"* — Jay
   reported the other three and did not mention it. ★ **Absence of a report is not a report**, and
   the missed-cel-change failure is the one it was asked about.
3. ★★★ **The residual blink is unmeasured in time.** §3.5.
4. ★★★ **P6.58's straddle clamp is still in** — ~1.9% of row starts restore short, and **nothing has
   yet looked for its residue.** Fourth task carrying it.
5. ★★ **Index-wise matching is argued safe, not exhaustively tested.** The argument is in §3.1; no
   arm forces a shifted sprite list.
6. ★ **`vm` cited, not re-run** (§2T; `vm_probe.s` unchanged).

### 8 — Follow-up candidates

1. ★★★★★ **The flags' blink is now the only visible defect, and the page flip needs a `src/hal/`
   task.** ★★★ **`HAL_gfx_present` contradicts its own file's geometry** [P6.59 §3.2] — that is a
   defect for Karateka's successor too and **should be raised with the other two ports**, not fixed
   unilaterally.
2. ★★★★ **Measure the blink's duration** before choosing between the flip and a per-sprite
   interleave. §3.5.
3. ★★★★ **Fix the straddle clamp properly** — fourth task. §7.4.
4. ★★★ **A plane-CONTENT census** — §7.1. The bytes-moved census cannot see a wrong value.
5. ★★★ **`HAL_KEYBOARD` in the cel arm** — eye-gate question 2 blocked **eight** tasks, and the
   Graham-smear prediction is now sharper: with the restore in, he should not smear when he walks.
6. ★★ **Delete the dead `ifdef CP_SAVE` block** — fourth task carrying it.
7. ★ `MAP_PRI_BANDS` — **eighth task carrying an address nothing uses.**

### 9 — User interaction during task

1. ★★★★★ **"graham is steady and the flags blink. no square background."** — AC-7, answering all
   three declared expectations in order. ★★★ **Each clause is a separate result: the fix works, the
   declared residual is real, and there is no regression.**

★★ **This is the first eye gate in this chain where the ask carried its expected answer**, and it is
also the first where Jay did not have to ask what he was looking at.

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-a-counter-nothing-prints-is-not-published.md`
- `seeds/AGI/live/2026-09-19-measure-a-non-event-by-differencing-against-an-arm-where-it-happens.md`

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting.
