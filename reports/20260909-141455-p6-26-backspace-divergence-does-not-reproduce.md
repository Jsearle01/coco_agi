## Form B Report — P6.26 (T-P0-082) — the backspace divergence: a control before a fix
**Class:** build (measurement-first).  wip.

★★★★★ **The headline is a negative and it is the result: the divergence does NOT reproduce.** Five
arms, CLEAR driven by ioport field assertion, two byte-identical runs. **This is §7 trigger 1 — stop
and report.** No fix was attempted and none is proposed.

### 0 — Receipt / status (C-35 stamp)
t0 = the T-P0-082 dispatch receipt (HEAD `5a6f18f`, wip).
`git status` clean but for `coco_agi.code-workspace` (untracked editor file, deliberately unstaged).

---

### §3 — Pre-dispatch grep (C-13), verbatim, before the summary

```
=== coco_agi ===
5a6f18f
wip
?? coco_agi.code-workspace
=== POP3_port ===
104b197
wip
?? .vscode/  ?? POP-idioms-coco3-markers.md  ?? content/intro/broderbund_splash_render.bin
?? docs/ground-truth/*.pdf (16)  ?? docs/project/pop-coco3-design-v0_7.pdf  ?? nvram/
=== karateka_coco3 ===
29f8f0a
wip
 M harness/smoke/last-run.log
?? docs/ground-truth/*.pdf (13)  ?? harness/tools/oracle_arch_region.lua
?? harness/tools/oracle_arch_trace.lua  ?? nvram/  ?? sta/
```

★★ **§2S, ref and scope stated:** both siblings read at their **`wip` working trees**, not at a public
ref. **No sibling has a tracked source modification** — POP is entirely untracked material, and
Karateka's single tracked change is `harness/smoke/last-run.log`, a run log. The untracked PDFs are
`docs/ground-truth/`, gitignored by §2.2 and therefore invisible in any clone.

★ **§2T does not apply and no baseline is cited.** P6.25 §0 recorded only `coco_agi`'s HEAD, not the
siblings' (§2T.1 item 4), and **this task builds no sibling artifact** — it touches no HAL file and no
`src/engine/` file, so there is nothing on the after side to compare.

```
=== hal_sync_check from coco_agi ===
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
=== from POP3_port ===
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, ...)
=== from karateka_coco3 ===
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, ...)
```

```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6
```

**Flag set, enumerated not confirmed [L-77]:** `input_probe.bin` is built by exactly one line, now in
`input_run.ps1`:
`lwasm --6809 -f raw -DHAL_KEYBOARD=1 -o build/input_probe.bin --map=build/input_probe.map -I. src/harness/input_probe.s`
→ **3,734 B**. ★ `-DHAL_KEYBOARD=1` is the only flag; without it four symbols are undefined.

**Staged vocabulary [L-111]:** `build\vm_stage\Kingquest1\words.tok`, **3,144 bytes**, printed by both
the runner and the Lua on every run below. ★ **Not `oracle_words.bin`**, whose 4,818 bytes produced the
`egon=1, word 0` reading one task ago.

**The divergence itself — does the posting arm still give `egon=2, words 2,37`?**

```
input_probe: 3734 bytes
vocabulary: build\vm_stage\Kingquest1\words.tok (3144 bytes)
staged: program 3734 B; typing 12 characters
★ line 1: 13 keys, last=$0D -> decoded [LOOK AT ROCK] -> egon=2  words = 2,37
★ run complete: 1 line(s), nothing further posted
```

★ **Yes. No contradiction found in the grep; proceeding.**

---

### 1 — Summary

A scripted backspace was made possible for the first time by **driving CLEAR as an ioport field**
rather than through `natkeyboard` (idiom 41f). With that, the P6.25 §7.1 divergence **does not
reproduce**: a line containing a backspace parses `egon=2, words 2,37`, exactly as the line without
one, on the first line and on reopened lines alike. Two full runs are byte-identical.

★★★★ **The buffers are dumped in full and are as expected at every stage** — `IP_INBUF` and
`par_clean`'s output are byte-identical across all four non-fault arms in their significant bytes.
**The claim "the buffer is identical" from P6.25 §7.1 is now proven rather than asserted**, and the
divergence it was attached to is not.

★★★ **The finding is therefore about the observation, not about the port.** §7 trigger 1.

### 2 — Files modified

- `harness/tools/backspace_repro.lua` — **NEW.** Five arms, CLEAR by field assertion, full buffer
  dumps, fault-arm adjudication.
- `harness/tools/input_run.ps1` — a `-Repro` arm added; the dump filter widened to pass hex rows.

★★ **No guest source was touched.** `git diff --stat HEAD -- src/hal/coco3-dsk/hal_globals.s src/engine/`
is empty. Nothing in `src/` changed at all.

### 3 — Reasoning

**3.1 ★★★★★ The observation had TWO uncontrolled variables, and the dispatch named one.**

P6.25's divergent line contained backspaces **and was a reopened line** — the second line of the
session. Every account of it so far, including my own §7.1, treated backspace as the variable. **It
was never isolated.** So the repro runs four arms rather than two:

| | line | contains backspace | is a reopened line |
|---|---|---|---|
| 1 | plain | no | **no** |
| 2 | backspace | **yes** | yes |
| **3** | **plain** | **no** | **yes** |
| 4 | backspace | **yes** | yes |

★★★★ **Arm 3 is the one that separates them.** Had arms 2, 3 and 4 agreed against arm 1, the variable
would have been *reopening* and backspace would have been innocent — a different defect in a different
place. [L-73: name every variable a toggle moves, not only the intended one.] **In the event all four
agree, so neither variable moves the parse.**

**3.2 ★★★★★ Arm 5 exists because four agreeing arms is the result this run was most likely to produce
for the wrong reason.**

Arms 1–4 can only agree or disagree with each other. **If the chain were wedged — vocabulary
unstaged, `IP_EGOLOG` stale, the adjudicator reading one arm's numbers four times — they would agree**,
and "all four the same" would be printed with total confidence. That is AD-122 and AD-131 exactly.

★★★★ **Arm 5 types `look at rockk` and presses ENTER with no CLEAR** — arm 2's keys minus the
backspace, a line whose last word is not in KQ1's vocabulary. It **must** parse differently. It does:
`egon=2, words 2,0` against arm 1's `2,37`, and its `IP_INBUF` differs. ★★★ **The comparison has been
seen to say DIFFER on this build and this corpus** [§2W.1], and the adjudicator prints that verdict
**before** the four "same" lines so a blind instrument cannot reassure first and be caught later.

**3.3 ★★★ What the dumps establish, stage by stage** (the bisection AC-3 asked for, run against a
divergence that is not there).

- **`IP_INBUF`, arms 1–4:** bytes 0–11 are `4C 4F 4F 4B 20 41 54 20 52 4F 43 4B` = `LOOK AT ROCK` in
  all four; byte 12 is `00` in all four.
- **`par_clean` output, arms 1–4:** `6C 6F 6F 6B 20 61 74 20 72 6F 63 6B 00` — **byte-identical across
  all four**, including both backspace arms.
- **Word numbers:** `2,37` in all four.

★★★ **There is no first diverging stage, because no stage diverges.**

**3.4 ★★ One real observation from the dumps, which is not the divergence.**

Arm 1's byte 13 is `FF`; arms 2, 3 and 4 have `00` there. **The input buffer is NUL-terminated on
reopen but never wiped**, so a backspace's `clr ,x` leaves a second NUL that persists into the next
line. ★★ **Harmless today** — `par_clean` walks to the *first* NUL and its output is byte-identical —
and recorded because it is a latent hazard for anything that ever reads the buffer by length rather
than by terminator. **This is why the dump runs past the terminator; a dump that stopped at the NUL
could not have shown it.**

**3.5 ★★ §2H's three checks, on the key path.**

1. **A second mechanism for another object class?** Yes, and it is now three: **delivery** (host key →
   matrix), **decoding** (matrix → code) and **host binding** [AD-165]. ★ This task's instrument
   bypasses the first two entirely by asserting the field, which is what makes it a *control* over the
   third rather than another observation through it.
2. **The calling routine.** `par_parse`'s caller is the probe's `ip_entered`, which calls `par_clean`
   on `IP_INBUF` and then parses. **Both buffers are dumped at that boundary**, so the scope of the
   check is the caller's, not the callee's.
3. **Grep the reports for the same subsystem.** P6.23 blamed key delivery; P6.24 disproved it; P6.25
   blamed debounce and the cause was a UX change. ★★★ **This report adds a fourth entry to that list
   and is explicit that it does not settle §7.1** — it removes backspace and reopening as causes and
   leaves the observation unexplained.

**3.6 ★★ Authority tier.** No ScummVM or Specs claim is made or relied on. Everything here is
**measured from the running machine** (tier 2's local analogue: our port under MAME) plus KQ1's own
`WORDS.TOK`. ★ The one behavioural expectation used — that an unknown word yields word number 0 — is
**observed in arm 5**, not assumed from the reference.

### 4 — Verification (AC-by-AC)

★ **Per L-112, each AC names what observed it, and no PASS covers two classes.**

- **AC-1 [class: state-comparable · observed by: field assertion + host readback]**
  ★★★★★ **NOT MET, AND THAT IS THE RESULT.** The divergence does not reproduce. Five arms, CLEAR
  driven by field assertion, **run twice with byte-identical output** [L-30]. **Per §7 trigger 1 this
  was reported rather than pursued** — no variants were tried after the negative.

- **AC-2 [class: byte-comparable · observed by: host memory dump]** **PASSED.** Every byte of
  `IP_INBUF` from `$4200` to `$4230` — 48 bytes, past the 42-byte field — dumped for all five arms and
  diffed, with `par_clean`'s output dumped the same way. ★★★ **P6.25 §7.1's claim "the buffer reads
  back as exactly `LOOK AT ROCK`" is hereby PROVEN for the scripted line** and remains unverified for
  the line Jay typed, which no longer exists.

- **AC-3 [class: state-comparable · observed by: host memory dump]** ★★ **VACUOUS, stated plainly
  rather than claimed.** The bisection ran — buffer → `par_clean` → word numbers, both sides printed
  at each stage — and **no stage differs**, so there is no first diverging stage to name. The
  apparatus is in place for the next dispatch if a repro is ever obtained.

- **AC-4 [class: state-comparable · observed by: fault injection]** **PASSED.** Arm 5, same code path
  and same run, parses `egon=2, words 2,0` against arms 1/3's `2,37`, and its buffer differs.
  ★★★ **The instrument is shown able to go red**; the no-backspace control the dispatch asked for is
  arms 1 and 3, which pass at `2,37`.

- **AC-5 [class: byte-comparable · observed by: the runner's own output]** **PASSED.** Every run came
  from `input_run.ps1` (`-Post` and `-Repro`); no MAME or `lwasm` line was hand-typed. Vocabulary path
  and size printed by both the runner and the Lua on every run.

- **AC-6 [class: suite · observed by: byte gates]** **PASSED.** `★ gates run: pic res cel comp p3b --
  all green`; `hal_sync_check.py` OK from all three repos; `reg_discipline.py` 8 accesses in
  `mmu_phase.s`, unchanged.

- **AC-7 [class: state-comparable · observed by: git]** **PASSED.**
  `git diff --stat HEAD -- src/hal/coco3-dsk/hal_globals.s src/engine/` is **empty**; `hal_globals.s`
  is unchanged since `5c6217a` (P6.24). ★ Echo remains UPPERCASE on the unshifted table — visible in
  every dump above as `LOOK AT ROCK`. **AD-167 untouched.**

- **AC-8 [class: suite]** One candidate captured; see §10.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).** §3's grep is above. The two AC-1 runs printed identical text;
this is the third, captured with the hex rows:

```
=== P6.26: four arms, CLEAR driven by field assertion ===
1 plain  (first line)  keys=13 curpos=12 entered=1  egon=2  words=2,37
2 backsp (reopened)    keys=15 curpos=12 entered=1  egon=2  words=2,37
3 plain  (reopened)    keys=13 curpos=12 entered=1  egon=2  words=2,37
4 backsp (reopened)    keys=15 curpos=12 entered=1  egon=2  words=2,37
5 FAULT  (rockk, none)  keys=14 curpos=13 entered=1  egon=2  words=2,0

=== IP_INBUF, every byte to $4200+48 ===
1 plain  (first line) |LOOK AT ROCK.???????????????????????????????????|
                      4C 4F 4F 4B 20 41 54 20 52 4F 43 4B 00 FF FF FF ...
2 backsp (reopened)   |LOOK AT ROCK..??????????????????????????????????|
                      4C 4F 4F 4B 20 41 54 20 52 4F 43 4B 00 00 FF FF ...
3 plain  (reopened)   |LOOK AT ROCK..??????????????????????????????????|
                      4C 4F 4F 4B 20 41 54 20 52 4F 43 4B 00 00 FF FF ...
4 backsp (reopened)   |LOOK AT ROCK..??????????????????????????????????|
                      4C 4F 4F 4B 20 41 54 20 52 4F 43 4B 00 00 FF FF ...
5 FAULT  (rockk, none) |LOOK AT ROCKK.??????????????????????????????????|
                      4C 4F 4F 4B 20 41 54 20 52 4F 43 4B 4B 00 FF FF ...

=== par_clean output at IP_CLNBUF ===
1 plain  (first line) |look at rock.???????????????????????????????????|
                      6C 6F 6F 6B 20 61 74 20 72 6F 63 6B 00 FF FF FF ...
2 backsp (reopened)   |look at rock.???????????????????????????????????|
                      6C 6F 6F 6B 20 61 74 20 72 6F 63 6B 00 FF FF FF ...
3 plain  (reopened)   |look at rock.???????????????????????????????????|
                      6C 6F 6F 6B 20 61 74 20 72 6F 63 6B 00 FF FF FF ...
4 backsp (reopened)   |look at rock.???????????????????????????????????|
                      6C 6F 6F 6B 20 61 74 20 72 6F 63 6B 00 FF FF FF ...
5 FAULT  (rockk, none) |look at rockk.??????????????????????????????????|
                      6C 6F 6F 6B 20 61 74 20 72 6F 63 6B 6B 00 FF FF ...

=== §2W: can this comparison say DIFFER? ===
  fault arm 5 vs arm 1        : DIFFER -- the instrument can go red  (arm 5 egon=2 words=2,0)
  inbuf  arm 5 vs arm 1       : DIFFER

=== which variable moved ===
  inbuf 1 vs 3 (both plain)   : DIFFER
  inbuf 1 vs 2 (plain vs bs)  : DIFFER
  parse 1 vs 3 (both plain)   : same
  parse 2 vs 4 (both bs)      : same
  parse 1 vs 2 (plain vs bs)  : same
  ★★★ NO DIVERGENCE REPRODUCED -- all four arms parse alike [trigger 1: stop]
```

★ The two `inbuf ... DIFFER` lines are §3.4's trailing-NUL residue, not a content difference; the
significant bytes and every `par_clean` output are identical.

Suite:

```
★ gates run: pic res cel comp p3b  -- all green
[hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared, ...)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s     8    $FFA5 $FFA6
```

**25.2 bundled-artifact grep:** N/A — this task produces no bundled artifact. `input_probe.bin` is a
harness binary, unchanged at 3,734 B (no `src/` file was touched).

**25.3 operator-runtime-smoke:** **N/A as expected.** Nothing reached a screen: the repro arm runs
`-video none -sound none -nothrottle`, and every output is a byte comparison (§2U). **No eye gate was
needed and none is claimed.**

### 6 — Reactive deviations and route accounting

**Deviation 1 — a fifth arm was added beyond the dispatch's four.** §4 specified the repro and §5's
AC-4 specified a no-backspace control; **neither would have caught a wholly wedged chain**, in which
all arms agree and the run reports "no divergence" with confidence. Arm 5 is a fault injection under
§2W.1 and its verdict is printed **first**. ★★ Recorded as a deviation because it enlarged the
dispatch's scope, small as it is.

**Deviation 2 — arm 3.** The dispatch's §4A asks for "a line containing backspaces". Arm 3 (plain, but
reopened) is not required by any AC. It is there because **the observation confounded backspace with
reopening** and without it a four-arm agreement would still not have separated them. §22.5.

**ROUTE ACCOUNTING.** No route was proposed in this task beyond the dispatch's. ★★★ **What this report
does NOT contain, having said in P6.25 §7.1 that it would:** a named cause for the divergence. The
measurement was run as specified and **returned a negative**; the cause remains unknown and this
report does not offer one. ★★ **The §8 lead below is inference from arm 5's numbers, explicitly not a
finding**, and it is written that way so no later report can cite it as one.

★ **Trigger 1 was honoured**: after the first negative, no variant lines, timings or edit shapes were
tried. The only work done after it was AC-4's fault injection — **which validates the negative rather
than attempting to overturn it** — and the second confirming run.

### 7 — Uncertainty flags

1. ★★★★★ **P6.25 §7.1 is NOT discharged. It is narrowed.** Backspace-in-the-line and
   line-is-reopened are **both eliminated** as causes, individually and together. The observation
   itself is unexplained and **the line that produced it no longer exists**.
2. ★★★★ **The scripted line differs from the human line in a way this task did not control: key
   count and overlap.** Jay's divergent line was **25 key events** for a 12-character result; the
   repro's backspace arm is 15, pressed strictly one at a time with a released, quiet interval
   between. ★★★ **A human types with rollover — two keys down at once — and `HAL_key_scan` resolves
   exactly one.** This is a named, untested difference, not a hypothesis with evidence.
3. ★★ **The trailing-NUL residue (§3.4) is benign under `par_clean` and untested against anything
   else.** No code reads that buffer by length today.
4. ★ **Single title.** All arms ran against KQ1's `WORDS.TOK`. Nothing here is claimed for other
   titles.

### 8 — Follow-up candidates

- ★★★★ **A lead, explicitly NOT a finding.** Arm 5 shows an unknown word yields **word number 0** and
  that ignore words are dropped: `look at rockk` → `egon=2, words 2,0`. **P6.25's divergent reading was
  `egon=1, words=0`** — one non-ignore group, unknown. ★★★ **That is not what `LOOK AT ROCK` produces
  under any arm measured here**, which suggests the parser saw a buffer other than the one the host
  printed. ★★ **Unverified inference from two numbers; it names a next question, not an answer.**
- ★★★ **Test the rollover difference (§7.2)**: assert two matrix fields simultaneously and check what
  `HAL_key_scan` resolves. That is the one named, untested difference between the two lines.
- ★★ **Decide whether `gs_get_string` should wipe the input buffer rather than only terminate it**
  (§3.4). A one-line question, deliberately not answered here.
- ★ Re-run this repro across a second title once a second `words.tok` is staged.

### 9 — User interaction during task

**None.** ★ The task ran headless start to finish; no eye gate and no operator input were required.

### 10 — Candidate(s) captured this task

One, to `seeds/AGI/live/`:

- `2026-09-09-adjudicate-the-fault-arm-before-the-comparisons-it-validates` — *initiator: executor*.
  A fault arm placed **after** the comparisons it exists to validate lets a blind instrument print its
  reassuring output first; ordering the verdict first makes that impossible.

★ **No candidate captured for the four-arm confound design** — it is L-73 (*name every variable a
toggle moves*) applied, not a new principle, and §2C wants new rows rather than restatements.

### 11 — Commit

`25121b2` — pushed to origin/wip before this report.
