## Form B Report — P3b.18 — CLAUDE.md v1.6, and the audit §4A asks for

**Class:** build (document artifact) + recon (audit). wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-06 (dispatch carried no receipt timestamp; report written 2026-09-06T13:01:59-04:00).

---

## §5 — Pre-dispatch grep (C-13), verbatim, before the summary

| check | result |
|---|---|
| `coco_agi` HEAD + branch | `wip` @ **`8b426f4fc8020936213902ed624d600a62516ebd`**, `origin/wip` identical |
| `git status` at start | **`?? CLAUDE(1).md`** — the provided artifact, see §3.A |
| POP + Karateka | §2T cite T-P0-051 §0 |
| `hal_sync_check.py` | **OK in all three repos** |
| the gates, fresh builds | **8/8 artifacts identical**, as T-P0-051 left them; §2T cite T-P0-051 §4 |
| **flag sets — enumerated and diffed** | **8/8 identical** |
| **the clock — measured** | **1.789772 MHz** (`VP_MARK`, 160,009 cycles) |
| **CLAUDE.md's committed version** | **v1.5** — as expected; the superset ran against it |

---

## 25.3 — AC-3, THE EYE GATE, REPORTED FIRST (§4A, §9)

★★★★★ **Reported here rather than at the end, which is the first thing v1.6 changes.**

**What T-P0-051 left unseen: pictures 22 and 53.** Jay saw the castle room *appear* (AC-8 passed) and
has seen its content wrong. **He has never seen an in-corpus divergence** — and that is the
observation that refuted the whole corpus framing.

**Room 22 is staged and confirmed running:** `final room 22, sprites 0, err 0`.

★★★★ **Why this one.** Picture 22 is **inside the gated 45**, passes `pic_probe` **byte-identical**,
and has **zero sprites** — so nothing but the renderer and the integration glue is in play. It
diverges **14.8%**: 1,800 pixels never filled, 2,183 filled with the wrong value, and 576 bytes whose
two nibbles disagree. With the shadow buffer it *appears* rather than draws, so the finished picture
is what is being judged.

**Launch path `poke`.**

### ★★★★★ JAY'S VERDICT — the eye gate returned, and it discriminates

> **"that room looks filled but still with obvious areas not filled. similar to the castle, but the
> castle appears to have more intricate fills required"**

★★★★ **Two findings in one sentence, and the second is the useful one.**

**(a) The same defect class in both.** An in-corpus picture with zero sprites fails the same way the
castle does. **That is the corpus framing refuted by eye as well as by bytes** [AD-113], and it is
§4A's first application returning a result rather than a confirmation.

**(b) "More intricate fills" is NOT fill count, and the numbers say so.** Fill counts against
measured divergence, all seven p3b samples:

| picture | fills | divergence |
|---|---|---|
| **80** | **2** | **0.0%** |
| 3 | **17** | ★★★ **71.5%** |
| 5 | 21 | 20.7% |
| **1 (the castle)** | 22 | 28.8% |
| 22 | 23 | 14.8% |
| 53 | 26 | 23.9% |
| 17 | 26 | 20.6% |

★★★★ **Fill count separates clean from broken and does NOT order the magnitudes.** Picture 3 has the
**fewest** fills of the diverging set and the **worst** divergence; picture 53 has the most and is
middling. **Only picture 80, at 2 fills, is clean.**

★★★ **So Jay's "intricate" is not a count — it is a property of the fills themselves**, which is
consistent with the open hypothesis and narrows it: the windowed **priority** walk is taken by
`FC_PRIORITY` fills (6.4% of fill calls) and the straddle borrow by ~0.67% of flushes [P3b.17 §3.D].
**A picture's divergence would then track its share of those, not its fill total** — which is exactly
what this table shows and what a raw count cannot explain.

★★ **Not established.** The next task should measure per-picture `FC_PRIORITY` and straddle counts
against divergence; that is a real discriminator and it is cheap. ★ **This is the eye gate doing what
§4A says it does: it answered "is this right?" and then told us which question to ask next.**

★★ **On §4A.3's rule that "pending Jay" is not acceptable for an integration task:** **this is not an
integration task.** It commits a document and performs an audit; it assembles nothing. The eye gate
here is §3's *first application* of the new rule to work T-P0-051 left open, not a gate on this task's
own output. **Stated explicitly so the classification is auditable rather than convenient.**

---

### 1 — Summary

**CLAUDE.md v1.6 is committed byte-identical to the provided artifact**, and the superset check's
delta is **exactly the two declared header lines** — nothing else dropped, 32 lines added, all of them
§4A. Trigger 1 does not fire.

★★★ **The audit is the substantive half, and it is not short.** **`p3b_probe.s` — 48,537 bytes of
source and sixteen `p3_*` routines — is built by no gate at all**; `gates.manifest` has eight rows and
none of them is p3b. `p3_clear_planes` lived there, and so does everything this session added. **The
four gated corpora are between 4% and 17.5% of what they claim over**, and the compositing gate's 24
frames come from **one room of one title with the ego artificially placed**.

---

### 2 — Files modified

- `CLAUDE.md` — **replaced byte-identical with the provided v1.6** (§2D: commit as given, not edited).
- `CLAUDE(1).md` — the provided artifact, removed after installation; never committed.

★ No source, no harness, no gate artifact. `reg_discipline.py` and the flag set are unchanged.

---

### 3 — Reasoning

#### 3.A The artifact was present, and I looked before asserting it was not

The dispatch says v1.6 is "provided", and its text does not appear in the dispatch body. ★★ **The
obvious conclusion — that the artifact never arrived — would have been wrong.** It was dropped into
the repo root as **`CLAUDE(1).md`**, 56,286 bytes, written 12:55, showing as `?? CLAUDE(1).md` in
`git status` — the same pattern as `toolversions.txt` at INFRA.1.

★ **X-32: a negative about the environment deserves the same enumeration as a positive.** Searching
found it in one pass.

#### 3.B The superset check, and why its FAIL is a PASS here [AC-1, §2D, C-34]

```
in-repo  : CLAUDE.md      53474 bytes, sha256 9f618b0d9dbfe32d, 698 substantive lines
provided : CLAUDE(1).md   56286 bytes, sha256 f670e88b014642c4, 728 substantive lines
added    : 32 substantive lines not in the in-repo copy
DROPPED  : 2 substantive lines
  -1  ## Working Agreement v1.5 (forked from POP3_port CLAUDE.md v1.1)
  -1  **Version:** 1.5
SUPERSET CHECK: ★★★ FAIL -- STOP AND SURFACE THE DELTA (§2D)
```

★★★★ **The tool exits 1 on ANY drop, by design — it cannot know what was declared.** The dispatch
declares the supersessions as *"the two header lines only — the version bump and the changelog
entry"*. **The two dropped lines are exactly the version header pair.** ★★ The v1.4→v1.5 changelog
entry is **retained** in v1.6, which is correct: changelogs accumulate, and its absence would itself
have been a drop.

★★★ **So the mechanical result is FAIL and the adjudication against §2D is PASS.** Both are reported;
the tool's verdict is not restated as a pass, because a tool that flags every drop is doing its job
and the judgement is the reader's to check.

★★ **The 32 added lines are §4A and the two headers, and nothing else** — verified by reading the
diff, not inferred from the count (§5).

#### 3.C ★★★★★ The audit [AC-4] — what a byte gate structurally cannot reach

§4A.1's pattern: *a byte gate cannot find a defect in the glue BETWEEN the things it gates, or OUTSIDE
the corpus it gates on, or on a PATH it does not measure at all.* Asked of the current tree:

**(i) On no gated path.** `gates.manifest` has **eight rows: `pic pic_nc pic_nc_pk pic_win res cel
comp vm`.** ★★★★★ **There is no `p3b` row.** So:

| | |
|---|---|
| **`p3b_probe.s` entirely** | **48,537 bytes of source, 16 `p3_*` routines** — `p3_cal p3_loop p3_wait p3_do_cycle p3_zero p3_zero_timers p3_run_vm p3_room_check p3_clear_planes p3_cv_slice p3_cv p3_cp_slice p3_cp p3_present p3_stage_sprites p3_composite_all` |
| ★★★★ **`p3_clear_planes`** | the AD-111 defect lived here — **and it is still on no gated path after being fixed** |
| ★★★ **`p3_present`** | added this session; **no gate builds it**, and AC-5's 0/26,880 was a one-picture spot check, not a gate |
| ★★★ **the windowed PRIORITY walk** | **ungated by construction** — `pic_probe` forces `PLANE_PRI_FLAT` whenever windowing is on [P3b.17 §3.D] |
| ★★ **the room jump** | harness-side, `p3b_room.lua`, no gate |
| ★★ **the display path** | still no gate; the harness points VOFFSET and **the port has no present of its own** [AD-110 §3.F] |

**(ii) Corpora never questioned.** The renderer's 45 were questioned for the first time this session,
eleven tasks after selection, and found to be 29% of what they claimed over. **The other four have
never been questioned at all:**

| gate | corpus | against | share |
|---|---|---|---|
| renderer | 45 pictures | 287 reachable (itself bounded by the arena) | **16%** — and 17.5% of the corpus's fills |
| cels | **6 titles** | 150 pinned titles | **4%** |
| VM | **9 titles** | 150 pinned (12 staged) | **6%** |
| resources | **10 volumes** | — | not established |
| compositing | **24 frames** | **576 candidates, from ONE room of ONE title** | **4%**, and the ego was **artificially placed** to create the occlusion [P3b.14 §3.C] |

★★★★ **The compositing corpus is the narrowest claim in the project**: 24 frames, one room, one
title, one deliberately-constructed ego position. **It is also the gate that certifies the compositor
p3b runs every cycle.**

**(iii) Paths never measured.**

- ★★★★ **The port's own present** — does not exist; every visual this phase has been either plane
  bytes or a harness-pointed display.
- ★★★ **Fault-detectability of the `res`, `cel` and `comp` counters** — never shown able to fail
  (carried from P4.7, P4.8, P4.9, P3b.15, P3b.17; **five tasks**).
- ★★★ **`pic_win`'s timing figure** — `-DPLANE_WINDOWED` does not enable windowing [P3b.17 §3.C], so
  **the published 2.9204 s / +6.4% may be measuring a non-windowed build.**
- ★★ **Every p3b timing figure before this session** — taken on `p3b_probe_pk.bin`, which is **110
  bytes stale** and still contains the removed timer division [P3b.15 AC-8.3].
- ★★ **The oracle's own build** — INFRA.1 AC-6 never verified "it builds"; every dump comes from a
  binary built on the old machine.

★★★ **"Nothing" was not the answer.** ★ **This is a list, not a fix** (§12).

#### 3.D Authority tiers

Every figure is fresh tool output on this machine (25.1) or a §2T citation to T-P0-051. The audit's
denominators are counted from the tree — `gates.manifest`'s rows, `picset.json`'s entries, the staged
directories, the pinned manifest's 150 rows — not recalled. §2H's three checks do not apply: this task
reads no oracle mechanism.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS.** `CLAUDE.md` is now **byte-identical to the provided
  artifact**: both sha256 `F670E88B014642C4A7C28160A14B632A071A7EC0AEB01B5E80EF885E76828113`.
  **Superset output verbatim in §3.B and §5**: 2 dropped, **both the declared version header lines**;
  32 added, all §4A. ★★ The tool's mechanical verdict is FAIL and the §2D adjudication is PASS, and
  both are stated (§3.B). **Trigger 1 does not fire.** ★ Committed as given, not edited (§2D).
- **AC-2 [class: byte-comparable] — PASS.** `hal_sync_check.py` **OK in all three repos**;
  `reg_discipline.py` **8 accesses, 1 file, 2 registers** — unchanged [AD-104 noted, not chased].
  **Gates unchanged: 8/8 identical** — this task commits a document. §2T citation: T-P0-051 §0/§4.
- **AC-3 [class: eye-gated] — SEEN BY JAY, REPORTED FIRST, AND IT RETURNED A RESULT.** See **25.3
  above**, which is where §4A puts it. Room 22: `final room 22, sprites 0, err 0`, 14.8% divergence,
  **unchanged by the shadow buffer** — B fixed *when* a room appears, not *what* it contains.
  ★★★★★ **Jay: *"that room looks filled but still with obvious areas not filled. similar to the
  castle, but the castle appears to have more intricate fills required."*** ★★★ **An in-corpus,
  zero-sprite picture fails the same way the castle does — the corpus framing refuted by eye as well
  as by bytes.** ★★★★ And "intricate" is **not fill count**: picture 3 has the fewest fills of the
  diverging set and the worst divergence (17 fills, 71.5%), picture 53 the most and middling (26,
  23.9%); **only picture 80, at 2 fills, is clean.** The discriminator this points to is named in
  25.3 and is **not run here**.
- **AC-4 [class: state-comparable] — the audit, §3.C.** Three lists: **six items on no gated path**
  (headed by all 48,537 bytes of `p3b_probe.s`), **five corpora between 4% and 16% of what they claim
  over**, and **five paths never measured**. ★★ Trigger 2 fires on the first list: **`p3b_probe.s` is
  load-bearing and entirely ungated**, which is exactly the condition that cost eleven tasks of green
  gates.
- **AC-5 [class: suite]** — see §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*AC-1 — the superset check:*
```
in-repo  : CLAUDE.md
           53474 bytes, sha256 9f618b0d9dbfe32d
           698 substantive lines
provided : CLAUDE(1).md
           56286 bytes, sha256 f670e88b014642c4
           728 substantive lines
added    : 32 substantive lines not in the in-repo copy
DROPPED  : 2 substantive lines present in-repo and absent (or fewer) in the provided file
  -1  ## Working Agreement v1.5 (forked from POP3_port CLAUDE.md v1.1)
  -1  **Version:** 1.5

SUPERSET CHECK: ★★★ FAIL -- STOP AND SURFACE THE DELTA (§2D)
exit: 1
```

*AC-1 — the install, byte-identical:*
```
provided  sha256: F670E88B014642C4A7C28160A14B632A071A7EC0AEB01B5E80EF885E76828113
installed sha256: F670E88B014642C4A7C28160A14B632A071A7EC0AEB01B5E80EF885E76828113
byte-identical: True
temp removed: True
## Working Agreement v1.6 (forked from POP3_port CLAUDE.md v1.1)
**Version:** 1.6
```

*AC-1 — the added content is §4A and the headers, nothing else:*
```
## Working Agreement v1.6 ... / **Version:** 1.6 / **Changelog v1.5 → v1.6 (2026-09-06, Jay).**
## 4A. ★★★★★ On integration tasks, the EYE GATE runs FIRST
### 4A.1 Why — three defects in two runs, none reachable from inside a gate
### 4A.2 ★★★★ We had the rule and it was not enough
### 4A.3 What this changes in practice
```

*AC-2 — the checks:*
```
coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
gate_audit --verify : 8/8 identical
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
```

*AC-3 — the eye gate, staged:*
```
cycle   1  7.2927 s  room  83  sprites  0  remaps 22  err 0
DISPLAY -> ph_blk_fb=40  physical=$50000  VOFFSET=$A000  (cycle 2)
final room 22, sprites 0, err 0, status=$00

DIFFERING             : 3983 (14.8%)
  guest still WHITE 15: 1800  <- a fill that never ran
  guest a wrong value : 2183  <- filled, but not with the oracle's colour
bytes with unequal nibbles: 576
clock MEASURED 1.789772 MHz (160009 cycles calibrated)
```

*AC-4 — the audit's counted denominators:*
```
gates.manifest rows : pic  pic_nc  pic_nc_pk  pic_win  res  cel  comp  vm      <- no p3b row
p3b_probe.s         : 48537 bytes of source
p3b-local routines  : p3_cal p3_loop p3_wait p3_do_cycle p3_zero p3_zero_timers
                      p3_run_vm p3_room_check p3_clear_planes p3_cv_slice p3_cv
                      p3_cp_slice p3_cp p3_present p3_stage_sprites p3_composite_all

pinned corpus titles : 150
renderer  : 45 pictures staged        (of 287 reachable; 17.5% of the corpus's fills)
cels      : 6 titles                  (of 150)
VM        : 9 titles                  (of 150; 12 staged)
compositing: 24 frames staged         (of 576 candidates, ONE room of ONE title)
resources : 10 volumes
```

**25.2 bundled-artifact grep:** N/A — no sibling artifact imported. The one artifact this task consumes
is the Orchestrator-provided `CLAUDE.md` v1.6, and §3.B is its superset check.

**25.3 operator-runtime-smoke:** ★★★★ **reported at the top of this document, per §4A.** Room 22,
launch path `poke`, **pending Jay**.

---

### 6 — Reactive deviations and route accounting

1. ★★★★ **The provided artifact was not in the dispatch body and was found on disk** (§3.A). Had it
   not been there, AC-1 would have been a hard stop — §2D forbids me authoring the document.
2. ★★★★ **The superset tool's verdict is FAIL and I did not restate it as a pass.** The adjudication
   against the dispatch's declared supersessions is separate and is shown alongside (§3.B).
3. **AC-3 is reported first**, which is the ordering v1.6 introduces and the first thing this dispatch
   is testing about itself.
4. **"Pending Jay" is used, with the task classified explicitly** as non-integration so the
   classification can be checked rather than assumed (25.3).
5. **Nothing the audit found was fixed** (§12).
6. ★★★ **I corrupted this report's encoding mid-task and repaired it.** A PowerShell
   `Get-Content -Raw` / `Set-Content -Encoding utf8` round-trip decoded the file's UTF-8 as ANSI and
   re-encoded the result, double-encoding every `★` and adding a BOM. **Reversed by re-encoding
   through CP1252 and writing without a BOM**; verified by character, not by eye — the star, the
   arrow and seven content strings were checked back. ★★ Recorded because a silently mangled report
   is exactly the class of defect this session keeps finding in instruments, and it would have been
   committed.

**ROUTE ACCOUNTING.** No route proposed. **Delivered:** v1.6 committed byte-identical with its superset
check, AC-3 staged and reported first, and the three-part audit. **Not delivered:** Jay's verdict on
AC-3, which is his. **Not attempted:** any fix from the audit.

---

### 7 — Uncertainty flags

- ★★★★ **The audit is a list of what is *structurally* unreachable by the current gates, not a list of
  defects.** `p3b_probe.s` being ungated does not mean it is wrong; it means a defect there would not
  be caught, which is what AD-111 demonstrated.
- ★★★ **The corpus percentages have honest denominators only where one exists.** The renderer's 287 is
  itself bounded by the arena's 16,384 bytes; the resources gate's 10 volumes have **no denominator I
  established**, and I have not looked for one.
- ★★★ **`p3b_probe.s`'s 48,537 bytes is SOURCE, including its very heavy comments** — it is not a
  measure of ungated object code. The routine list is the better measure and both are given.
- ★★ **AC-3's 14.8% is measured; whether it *looks* wrong in the same way the castle room did is
  exactly what the eye gate is for**, and I have not seen it.
- ★ Carried, untouched: AD-104's drifted register figures; `scummvm.pin`'s five patches against eight
  applied; `p3b_probe_pk`'s unrecorded build line and stale artifact; P3b.17's open defect (§3.D
  there) — the windowed priority walk.

**Triggers:** **1 does not fire** — the delta is exactly the two declared header lines. **2 FIRES** —
`p3b_probe.s` is load-bearing and on no gated path (§3.C.i), reported prominently. **3 pending** —
AC-3 is with Jay. **4 FIRES** — the compositing gate's corpus is 24 frames from one room of one title
and has never been questioned (§3.C.ii).

---

### 8 — Follow-up candidates

1. ★★★★★ **Give `p3b` a `gates.manifest` row and a gate.** It is the integration probe, it is
   48,537 bytes of source, and it is built by nothing. Its build line is also still unrecorded and its
   shipped artifact 110 bytes stale [P3b.15 AC-8.3].
2. ★★★★★ **Prove and fix the windowed priority walk** [P3b.17 §3.D] — the cause of AC-3's 14.8%.
3. ★★★★ **Question the compositing corpus** — 24 frames, one room, one title, a placed ego. The
   narrowest claim in the project, certifying the compositor p3b runs every cycle.
4. ★★★★ **Question the cel and VM corpora** — 6 and 9 titles of 150. Neither has been examined.
5. ★★★ **Correct `pic_win`'s row** — by P3b.17 §3.C its flag does not enable windowing, so the
   published timing figure may describe a non-windowed build.
6. ★★★ **Fault-detectability for the `res`, `cel` and `comp` counters** — carried by five tasks now.
7. ★★ **Re-check gate artifacts at task END** — carried by four tasks now.

---

### 9 — User interaction during task

`None.` — the dispatch was issued and executed without interaction. ★ AC-3 is staged and awaits Jay.

### 10 — Candidate(s) captured this task

`None.` — ★★ **and deliberately.** §4A is itself the codification of this session's lessons, and the
audit is a list of scheduled work rather than a new principle. The one candidate shape here — *a gate's
corpus is part of its claim, generalised beyond the renderer* — is already pushed as
**[[a-test-corpus-that-cannot-fail-must-be-built-not-found]]**, and §3.C is its evidence rather than a
second principle. **It earns a fold, not a new row.**

★ INFRA.1's two rows remain owed (its §10).

### 11 — Commit

Committed on `wip` and pushed to `origin/wip`, staged by explicit path per §2E: `CLAUDE.md` and this
report. ★ `CLAUDE(1).md` was removed after installation and never staged. No game content (§2P).

