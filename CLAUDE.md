# CLAUDE.md — AGI Interpreter → CoCo3 Project (Clyde standing rules)
## Working Agreement v1.4 (forked from POP3_port CLAUDE.md v1.1)
**Version:** 1.4
**Instantiates:** CODM v0.7. Where this doc and v0.7 overlap, v0.7 governs; this doc adds AGI invariants.

**Changelog v1.3 → v1.4 (2026-08-26, Jay).** ★ **§2T ADDED — sibling baselines are established by
CITING the previous report when the inputs are unchanged**, rather than by rebuilding. No other rule
changed.

**Changelog v1.2 → v1.3 (2026-08-26, from T-P0-010 and POP-HAL-01).** ★★★ **§2G's "read-only /
copy-and-adapt / no build-time dependency / never an automatic sync" wording was inherited from POP's
v1.1 and is STALE** — all four are false of the current tree. **§2M already had it right**; §2G now
agrees with it. ★★ **The byte-identity rule's scope corrected**: POP ships **six DECB files plus
`probe.dmk`**, not "three prod artifacts", and `build.bat` writes **125 files**. ★ **§2M gains the
mode-table seam** — shared mechanism, project-local data. No other rule changed.

**Changelog v1.1 → v1.2 (2026-08-24, from T-P0-002's verdict).** ★ **§2H's two line-count figures
corrected against the pin** — `op_cmd.cpp` is **2,483** not 2,540, and the engine is **30,066** lines not
6,369. **The correction strengthens §2H rather than weakening it: the reference is ~5× larger than the
figure quoted.** ★★ **§2H gains the "319 opcodes" scope note** — the value is confirmed at the pin and a
v2/v3 target needs **203**. No other rule changed.

**Changelog v1.0 → v1.1 (2026-08-24, Orchestrator-authored per §2D, from T-P0-001's verdict).** ★ **§2N's
rule part 4 corrected to load/store/MODIFY** — v1.0 said "load/store" and would have undercounted `clr`,
`com`, `neg`, `inc`, `dec`, `tst` and the shift/rotate group. **`TC_MMU` added to the alias list** (six,
not five). **§2N gains the scan window, the `src/harness/` exclusion, §2N.1 (census-not-gate) and §2N.2
(the pointer-load class).** No other rule changed. **The corrections come from POP P5.17/P5.19, which are
primary and outranked the dispatch that got them wrong.**

**Provenance (2026-08-23).** Forked from POP's v1.1 rather than written fresh: roughly 70% is
machine-and-methodology discipline that took thirteen amendments to arrive at, and each rule carries a
precedent that a rewrite would lose. **Five sections changed and seven were added.** §2 is rewritten for a
reimplementation oracle; §2K inverts to 512 KB with its reasoning preserved verbatim; §2I becomes
behavioural correctness; §2G becomes two siblings under a synchronised HAL; **§2M–§2S are new.** Design
authority is `agi-coco3-design-v0.3.md`.

★ **Read §2M and §2N before touching any HAL or engine file.** They are the two rules whose earlier
versions were wrong three times, and the corrected versions constrain day-one work.

---

## 1. Project Bindings

- **25.1** (fresh tool output) = `build.bat` + `run_*_test` (verbatim in the report).
- **25.3** (operator-runtime-smoke) = **Jay's MAME visual gate only.**
- **Candidate capture path** = the shared pool, `seeds/AGI/live/` (see §2C).
- **Repos:** port = `github.com/Jsearle01/coco_agi`, local `C:\Projects\coco_agi`, branch `wip`.
  **POP (`C:\Projects\POP3_port`) and Karateka (`C:\Projects\karateka_coco3`) are siblings** — read-only
  for everything EXCEPT the synchronised HAL (§2G, §2M). Candidate pool =
  `github.com/Jsearle01/methodology-candidate-pool`.
- **Build mode: LINKED** (as POP; Karateka is absolute). The HAL must keep supporting both.
- **Oracle pin:** the ScummVM commit and the pinned game set (§2Q). **Both are bindings, not preferences.**
- **CALIBRATION-LIGHT (inherited from POP):** no dual-band prediction, no C-35 elapsed-time calibration
  block. The C-35 **receipt stamp** (t0 + HEAD, §5) IS kept as provenance.

These bindings are fixed for the life of this project. Never substitute alternatives without explicit Jay
authorization.

### 1A. Directory structure (settled 2026-08-23)

```
src/hal.inc                      ── SHARED (§2M)
src/hal/coco3-dsk/               ── SHARED; hal_globals.s is PROJECT_LOCAL
src/boot/                        loader.s → LOADER.BIN
src/engine/{vm,text,picture,view,parser,sound,storage}/
src/opt/6809/  src/opt/6309/
src/harness/                     probe .s files
harness/tools/hal_sync_check.py  ── SHARED; path pinned by the script's own parents[2]
harness/tools/reg_discipline.py  four-part rule (§2N)
harness/{lib,scripted,smoke,tmp}/
tools/{volread,imgbuild,picdiff}/   host-side deliverables
oracle/{scummvm.pin,patches,dumps}/ pin + instrumentation, NOT a vendored source tree
games/manifests/                 checksums and version ID — NEVER game data
content/                         font and palette tables — ours, not Sierra's
docs/ground-truth/  docs/project/
dist/mame-cfg/{rgb,composite}/
tests/scripted/  poc/  link/  reports/
```

★ **`harness/tools/hal_sync_check.py` resolves siblings as `parents[2]` then `here.parent / <name>`.**
The working directory must be named **`coco_agi`** and sit adjacent to both siblings, or the check prints a
warning and returns 0 — silent non-enforcement. **The repo was renamed from `coco-agi` and GitHub keeps the
old URL as a permanent redirect**; a clone from it lands in a wrongly-named directory.

★ **The register check targets `src/engine/**` recursively** (§2N).

---

## 2. Ground Truth Hierarchy (AGI — DIFFERS FROM POP: THERE IS NO SOURCE)

**POP is ported from real, buildable Mechner assembly pinned at a commit — the exact tree its oracle is
built from. None of that exists here.** Sierra's interpreter source is not public. What exists is:

- **ScummVM's `engines/agi`** — a *reimplementation*, reverse-engineered and maintained.
- **The AGI Specifications** (Lance Ewing et al., 1997) — also derived, by reverse engineering.

★★ **Neither is the source. Both are evidence about AGI's behaviour, produced by people who did not have
the source either.** The authority stack:

1. **Jay (the human)** — ultimate; visual/behavioural ground truth; overrides all below.
2. **The original game running** — in an accurate emulator or on period hardware. **The only primary
   evidence that exists.**
3. **ScummVM** — the best secondary evidence; tested against dozens of games, actively maintained. The
   working basis you plan and build from.
4. **The AGI Specifications** — good, older, **known incomplete in places.**
5. Comments and labels — lowest; unverified hypothesis.

### 2.1 ★★ ScummVM is not neutral

**It fixes original bugs, works around game-specific quirks, and normalises across interpreter versions.
Reproducing ScummVM faithfully may mean reproducing choices Sierra never made.**

Where ScummVM and the Specs disagree, **ScummVM is usually right about *what works*; it is not
automatically right about *what the original did.*** ★ **Say which you are reproducing.** A report that
cites ScummVM for a behavioural conclusion states whether the behaviour is believed original or believed
a ScummVM normalisation — **"ScummVM does it this way" is a fact about ScummVM, not about AGI.**

**When behavioural uncertainty exists AND ScummVM does not settle it, run the original game and observe** —
do not proceed on comment-based or guessed assumptions when dynamic verification is possible.

### 2.2 Ground-truth documents are local and orchestrator-unverifiable

**`docs/ground-truth/` is gitignored.** Its documents (GIME reference, AGI Specs) live in the working tree
and are never pushed.

★★ **Consequence for the evidence flow: when Clyde cites `[ref: GIME-RM §10]`, the Orchestrator cannot
check it.** Such citations are **executor-verifiable and orchestrator-unverifiable** — the same class as
§4's operator gate, not the class a verdict confirms from fresh tool output. **Cite in POP's form:**

- `[ref: GIME-RM §N]` — verified against the document.
- `[no-ref: <claim> — discharge <task>]` — asserted, carrying a visible debt marker.

**An unverified assertion must not be indistinguishable in the source from a checked one.**

---

## 2A. Instrumentation Reference Files (check every dispatch)

- **`mame-idioms-coco3-port.md`** — the `coco3` / 6809 target. **Carried over from POP** (§2G). Seed from
  POP's, then extend.
- ★ **POP's `mame-idioms-apple2e-oracle.md` does NOT transfer.** AGI's oracle is ScummVM running on the
  host, not a machine under emulation. **There is no second emulated target.**

**Mandatory read points, not optional references:**

1. **At the start of any dispatch that touches MAME** (trace, watchpoint, breakpoint, snapshot, boot,
   gate), read the file first. **6809 read-taps work** (the 6502 false-0 caveat is inherited context, not
   an AGI concern).
2. **Before exercising a MAME function not already confirmed this session** — a new debugger command,
   `bpset`/`wpset`/tap form, `tracelog`/`trace`, `natkeyboard:post`, `execution_state`, a speed/GIME/FDC
   poke, an image-build step — check the file for verified syntax and known gotchas. Do not rediscover by
   trial and error (headless `-debug` hangs without `execution_state="run"`; the frame-notifier/tap GC
   gotcha; bp-action `tracelog` is brace-free while trace-action is braced; `-seconds_to_run` is emulated
   seconds; Windows paths need forward slashes in Lua).
3. ★ **DMK and SDF are READ-ONLY in MAME's floppy layer.** A guest that formats a mounted `.dmk` leaves
   the file byte-unchanged. Only JVC and `coco_rawdsk` write back, and **JVC discards physical order**
   (§2R.1). Timing work uses the in-session CPU-hijack pattern against a known-good pristine disk.
4. **When you discover a new idiom/gotcha, add it to the file** and surface the addition in the report.
5. **Before concluding a MAME mode/config/flag does NOT exist, do an EXHAUSTIVE search** — `-showusage`,
   **`-listxml <machine>`**, and the in-machine config/DIP ports (Lua `field.user_value`). "I didn't find
   it" is valid only after the enumeration; a premature "MAME can't do X" is a reportable error. State
   which surfaces you searched.

The idioms files serve the ground-truth hierarchy; they never override it.

---

## 2B. Authored Asset Protection

**This project ships almost no assets** — §2P makes the game data the user's. What IS ours and authored:
**the 8×8 40-column font, the RGB palette table, and (when it exists) the composite palette table**, all
under `content/`.

**Re-running a generator over a hand-tuned asset silently destroys work that cannot be reproduced.** If a
target is authored or hand-corrected, **stop and get Jay's ruling before overwriting.** ★ **The composite
palette table will be hand-tuned by eye and is unreproducible by any tool** — treat it as PROTECTED from
the moment it exists.

---

## 2C. Methodology candidate capture — WHERE candidates go

Candidates go to the **shared cross-project pool**, a SEPARATE repo, NOT `coco_agi`. (Karateka's capture
silently no-op'd for several dispatches by searching the wrong repo and rerouting to inline — lost-
reference drift. Recorded here so it stays found.)

- **Pool:** `github.com/Jsearle01/methodology-candidate-pool`, local `C:\Projects\methodology-candidate-pool`
  (sibling of `coco_agi`). **AGI candidates live in `seeds/AGI/live/`.** **Clyde creates `seeds/AGI/` on
  first capture** (dispatch-#1 item).
- **Capture at the FIRST instance** as a NEW row: `seeds/AGI/live/<iso8601-date>-<slug>.md`. **New rows
  only — NEVER read or edit existing pool entries** (folding is the reconciler's read-time job).
- **Row schema:** match an existing `seeds/POP/live/*.md` exactly (`project: AGI`, `source: live`,
  `instance_history` with `initiator` set faithfully, never guessed). **Schema is frozen in the pool's root
  `SCHEMA.md`**; two load-bearing constraints: `instance_count` MUST equal `len(instance_history)`, and
  `live` rows are ALWAYS fresh single-instance rows.
- **Commit + push fire-and-forget** — non-blocking; a failed push NEVER gates a task. Report captured
  slug(s) in the report's "Candidate(s) captured" line.
- **Credential note:** if the pool remote carries an embedded credential, NEVER copy the token into
  CLAUDE.md, a row, or any tracked file.
- **Fallback:** if the pool can't be reached, **STOP and ask Jay** — do NOT create a `seeds/` dir inside
  `coco_agi` (a shadow pool is worse than a lost reference).

---

## 2D. Authored authoritative docs — Orchestrator owns CONTENT, Clyde owns COMMIT

**Clyde does NOT edit the body of authored authoritative docs directly** (the design spec, decision
records, post-mortems, behavioural models). Findings surface in Clyde's reports; the **Orchestrator** folds
them into the text; **Clyde commits** the Orchestrator-provided result. Rationale: the reasoning behind
these docs lives in the Orchestrator's context; parallel edits diverge. Split: **Jay authors /
Orchestrator drafts / Clyde renders.**

- **Before overwriting one with an Orchestrator-provided file, run the SUPERSET DIFF-CHECK** (hard gate):
  every substantive line of the in-repo copy must be present in the provided file (verbatim or explicitly
  superseded). If the in-repo copy has content the provided file lost, **STOP and surface the delta.**
- Recording a finding in a report is always fine; editing these doc bodies is the Orchestrator's job.

---

## 2E. The `wip` branch — in-flight sandbox work, visible to the Orchestrator

A single long-lived **`wip`** branch holds all in-flight work, pushed when a dispatch reports
(push-before-report). **Purpose: the Orchestrator reads the actual tree, not report descriptions.**

- **One home per fact** — work lives in its normal paths on `wip`; NO `/inprogress` dir or duplicate copy.
- **`main` = coherent/deliverable; `wip` = in-flight.**
- **Explicit-path staging always** (never `git add -A`), on `wip` too. Over-inclusion on `wip` is fine
  (visibility > tidiness) but must be by named path.

---

## 2F. Single-home placement

**Exactly ONE home for each fact.** The AGI instances:

1. **The palette is a 16-byte table loaded at init.** ★ **Never inline a palette constant at a write
   site** — this is what makes the composite table a later data change rather than a rewrite (design
   §2.2).
2. **The floppy span layout is read from the disk signature sector, never compiled into the loader**
   (design §4.4). Symmetric and asymmetric layouts then cost the same.
3. **The resource map is the game's own DIR tables.** There is no second index. Do not build one.
4. **Priority banding is a 168-byte lookup table**, not a computation (design §3.5).

**Enforcement:** a dispatch touching any of these carries it as a hard-stop; the verdict verifies it
against the tree. Bypass = failed verdict.

---

## 2G. POP and Karateka are SIBLINGS — read-only for content, SYNCHRONISED for the HAL

**AGI has two siblings and POP is the more relevant one.**

| | role |
|---|---|
| **POP** | **the architecture oracle.** MMU cost, GIME modes, the page flip, save-under, blocks-vs-bytes, the disk cost model, DMK interleave. Design spec §1.3 tabulates what it is authoritative on. |
| **Karateka** | the original substrate, and a **HAL co-client** whose build must keep working (§2M). |

- **Read-only for CONTENT.** Never modify a sibling's scene logic, sprite content, behavioural models or
  game data. **Reuse the SUBSTRATE, not the game.**
- ★★★ **The HAL is NOT read-only and NOT copied — it is SYNCHRONISED, and POP HAS a build-time
  dependency on it.** `hal_sync_check.py` runs inside `build.bat` and **fails the build on drift.** See
  §2M.
  > ★★ **POP's own CLAUDE.md §2G still says "read-only", "copy-and-adapt, don't depend", "POP has no
  > build-time dependency on it", and "back-ports are never an automatic sync". ALL FOUR ARE FALSE of the
  > current tree** [POP-HAL-01 §3.1]. **Stale, not contradicted** — the bridge arrived at `dd1cec4` P2.4,
  > after that text was written.
  ★ **Third instance of the same error class** (with X-33 and AD-28): **a document describing how
  something ARRIVED, read as describing how it is MAINTAINED.**
- **Confirm each reuse for AGI** — reuse the mechanism, but verify the constant for AGI. **AGI is 16-colour
  and both siblings are 4-colour**; a constant that transferred between POP and Karateka may not transfer
  here.
- **Back-ports of non-HAL work are separate explicit tasks** in the receiving repo, never an automatic
  sync.
- **What does NOT transfer from POP:** its animation rate, cel model, two-format ruling, phase and facing
  findings, disk split. ★ **Those are properties of POP's content, and §2H's discipline applies to reading
  POP's backlog exactly as it applies to reading ScummVM.**

---

## 2H. Look past the first mechanism

A mechanism found in the reference is a **hypothesis about the whole mechanism**, not the mechanism. Before
building on one, run these three checks and **state their results in §3**:

1. **Is there a SECOND mechanism serving a different object class?** Ask what the *other* kind of object
   does.
2. **Name the routine that CALLS it, not only the one that implements it.** The caller carries the scope —
   how often, under what condition, for which objects. *The enclosing routine is the fact, not the line
   number.*
3. **Before citing a prior report's characterisation, grep the reports for the same subsystem.** **A
   contradiction between two reports survives indefinitely when each is cited alone, and the later one
   wins by recency rather than by evidence.**

This is not a mandate to search without bound. It is three bounded checks, and **the third is mechanical.**

★★ **This matters MORE here than in POP.** POP's version was written against a 6502 source tree. **AGI's
reference is 30,066 lines of C++ at the pin** — `op_cmd.cpp` alone is 2,483 — and a first-mechanism read
of it is very easy to make and hard to catch. **The three checks apply verbatim to reading ScummVM.**

★ **On "319 opcodes": the number is right and its scope is not.** `opcodes.cpp` holds FOUR tables —
`opCodesV1Cond` 17, `opCodesV1` 99, `opCodesV2Cond` 20, `opCodesV2` 183 — summing to 319 across **two
orthogonal axes**: two interpreter-version families (selected at runtime, `opcodes.cpp:381-389`; a game
uses ONE) and two dispatch classes (tests vs commands, separate opcode spaces). **A v2/v3 target needs
203, and fewer still** — `opCodesV2` marks entries Apple IIGS-only and AGI3+-only. ★★ **This is the
worked example of §2H in the reference itself: a figure can be exactly correct and mean something other
than what quoting it implies. Verify what a number COUNTS, not just its value.**

**The pattern this exists to break** (Jay, 2026-08-15): *"There's been a pattern of Clyde finding a
mechanism and then going with it as THE mechanism. We've seen several times in this project that there was
a deeper truth than what is found initially."* The first mechanism found is usually REAL — it is just not
the WHOLE mechanism, or not the GOVERNING one. POP's five instances (PA.2 vs P3.44's contradictory
`DRAWALL` readings; `pburn`'s enclosing routine inverting a correct measurement; the cadence gate applied
to the decision instead of the drawing; the slip attributed to a cost when it was a grid; the peel-skip
true only while nothing else was on screen) are the evidence base and are worth reading in POP's copy.

---

## 2I. The mandate is BEHAVIOURAL CORRECTNESS

**POP's mandate is that the port LOOKS right and FEELS right. That is a sound rule for a port of one
program and a dangerous one for an interpreter.**

★★ **An AGI interpreter can look perfect and be wrong.** A LOGIC opcode that sets the wrong flag, an
off-by-one in a `said()` match, a variable updated in the wrong cycle — **none of it is visible until a
puzzle becomes unsolvable forty minutes in, in one game out of thirty.**

> **The mandate is that the games run correctly.** Visual fidelity is necessary and not sufficient.
> **Where behaviour is observable — variables, flags, object state, parser results — it must match, and
> "it looks right" is not evidence that it does.**
>
> **Where behaviour is genuinely unobservable, POP's §2I applies unchanged:** a divergence that preserves
> output is legitimate and needs no justification beyond measurement. Do not argue for it as a deviation;
> implement it and report what it costs and what it saves.

Where the reference's approach is cheaper or safer, prefer it — **it usually is.** Where the CoCo3 makes a
different approach cheaper at equal output, take it.

**★ THIS DOES NOT RE-RANK §2 — it clarifies what §2 is FOR.** §2 ranks the running original, ScummVM and
the Specs as authorities on **what AGI does**. This section is about **what the interpreter must
reproduce.** Those are different questions, and conflating them is a known failure shape. **"ScummVM does
it this way" is not, on its own, a reason to do it that way** — and per §2.1 it may not even be a fact
about AGI.

---

## 2J. File creation and editing — not via shell heredocs

Create and edit files with `create_file` / `str_replace`, **not** with shell heredocs. On Git Bash,
heredocs bit POP twice in one session: **CRLF line endings attach to the delimiter** so the heredoc never
terminates, and **`$` interpolates** inside the body, silently corrupting assembly and script text. Both
failures produce a file that looks plausible and is wrong. ★ **These are Git Bash properties, not POP
properties** — they reproduce here identically.

---

## 2K. 512 KB is the verification target (INVERTED FROM POP — read the reasoning, it still governs)

**Verify on 512 KB. It is the target machine.** Design spec §3.2 puts the framebuffer at 4 blocks and the
priority screen at 2, before the interpreter's data; **§3.7 puts 128 KB at ≈6 free blocks, 48 KB of
cache**, which forecloses the RAM-disk and therefore floppy entirely. **128 KB is an SDC-only stretch
target that may simply fail.**

★ Sierra's own two CoCo3 AGI titles — King's Quest III and Leisure Suit Larry 1 — **both required 512 KB.**
512 KB is not a regression from the originals.

★★ **POP's reasoning is preserved verbatim because the ORDERING rule still holds whenever 128 KB is tested
at all:**

> *"Verify on stock 128 KB first. It is strictly the harder case: the GIME masks a block number to the RAM
> actually installed, so the framebuffers alias and the bank occupies the top of real RAM. **512 KB can
> pass while a masking assumption is wrong; the reverse does not happen.**"*
>
> The mechanism, from the HAL rather than from memory [`src/hal/coco3-dsk/gfx.s:405-417`]: *"The GIME masks
> a block number to the RAM actually installed, so on a 128 KB machine only `$00-$0F` exist and every
> number aliases mod 16."*
>
> **★ AND THERE IS A PRECEDENT, WHICH IS WHY THIS IS A RULE AND NOT A PREFERENCE.** P3.10: buffer B at
> `$18` was *"fine on 512 KB and fatal on 128 KB: the port loaded, started, and died at the first
> framebuffer access."* A 512-KB-first order would have called that build green.

**Applied here: if AGI ever runs a 128 KB build, it is reported FIRST, for exactly POP's reason.**

---

## 2L. DECB is a bootstrap and nothing more

**`LOADM` + `EXEC` a small loader; the loader switches to all-RAM mode; from that instruction there is no
Color BASIC, no Extended BASIC, no Disk BASIC, no DECB working storage, no ROM disk driver.** The
interpreter owns `$0000`–`$FEFF` as RAM through the eight MMU slots, with only the `$FFxx` I/O page live.
**Nothing is ever called back into.**

- **Two artifacts, not one.** `LOADER.BIN` is the sole `LOADM` target. **The interpreter lives in the raw
  tracks and is loaded like any other payload** — it is not in the `LOADM` image.
- **The LOADM ceiling (`$2488..$2535`, POP P3.22) applies ONLY to `LOADER.BIN`.** After handover the
  ceiling no longer applies. ★ **If something does not fit in the LOADM image, the first question is
  whether it belongs there at all** — for AGI the answer is almost always no.
- ★ **This narrows the `$010C` problem.** DECB's `LOADM` overwrites the IRQ vector, but nothing after
  handover cares what it held — **the constraint is only that the `LOADM` survive itself.** With only a
  small loader being loaded, the collision surface is a couple of KB.
- **`LOADM` needs `disk11.rom` present** or the machine boots to Extended Color BASIC and `LOADM` silently
  does nothing (idioms §14). Inherited: `decb-assumes-slow-does-not-force-slow`.
- **All-RAM transition and vector installation are `sys.s` and `irq_vbl.s` — both SHARED (§2M), both
  already solved.** Do not re-derive them.

---

## 2M. ★★ The HAL is SYNCHRONISED across three repos by tooling

**This rule was wrong twice before it was right. Read it, do not reconstruct it.**

`harness/tools/hal_sync_check.py` runs as a pre-build step and **fails the build on substantive drift.**
`SHARED` is ten files plus the script itself:

```
src/hal.inc
src/hal/coco3-dsk/{sys,time,irq_vbl,gfx,input,sound,file,mem,disk_read}.s
harness/tools/hal_sync_check.py          <-- checks itself
```

`PROJECT_LOCAL = {'src/hal/coco3-dsk/hal_globals.s'}` — the only sanctioned per-project file.
`normalise()` removes EOL, comments, whitespace runs, and a dormancy guard's **own directives — never its
contents.** Exports are compared as a **set**, independent of placement.

> **A change to any shared file is a change to every client, and it lands in every repo or in none.**

1. **`hal_sync_check.py` is the contract, not a convention.** The script is in its own `SHARED` list and
   derives the sibling path from `SIBLINGS` rather than a per-repo constant — **a repo cannot quietly
   configure its own check.**
2. ★★ **A THIRD CLIENT MAKES THIS STRICTER, NOT LOOSER. AGI is 16-colour. POP is 4-colour WITH the mode
   service. Karateka is 4-colour and does not define `HAL_GFX_MODE_SERVICE` at all.** **Every AGI addition
   to a shared file must assemble in a tree where the mode service is OFF — `ifndef` fallbacks are
   MANDATORY, not stylistic.** ★ **P5.18 found this twice: a one-line change referencing
   `HAL_gfx_cur_words` broke Karateka's build.**
3. **A guard is not an escape hatch.** `normalise()` drops a guard's directives but **compares its
   contents**, so guarded AGI code must still be substantively identical in all three trees. **A guard is
   the mechanism that lets identical source assemble differently.**
4. **New AGI-only exports go in `hal_globals.s`** or arrive in all three trees together. **An AGI-only
   export in a shared file is drift even when guarded.**
5. ★★★ **THE MODE TABLE IS PROJECT-LOCAL — shared mechanism, project-local data.** `gfx_mode_table` and
   `GFX_MODE_MAX` live in `hal_globals.s` (PROJECT_LOCAL); the mode service **code** stays in `gfx.s`
   (SHARED). ★ **A project may add a mode without touching any shared file** [POP-HAL-01, landed
   2026-08-26]. **This exists because POP ASSEMBLES the table**: a 7-byte row shifted 27 artifacts and
   made §1.4's byte-identity rule unsatisfiable for the one change D-13 required.
   ★ **A project that defines `HAL_GFX_MODE_SERVICE` but supplies no table will not assemble** — a
   documented requirement, not a guard.
6. ★★ **ENTRY IS AT P3, NOT AT REPO CREATION.** `compare()` skips a file missing on BOTH sides but reports
   drift when it is missing on ONE. **Adding `coco_agi` to `SIBLINGS` before its HAL exists reads as ten
   files `MISSING in coco_agi` and BLOCKS BOTH SIBLINGS' BUILDS.** Until P3, `coco_agi` has no `src/hal/`,
   no sync call in `build.bat`, and the siblings continue as a two-party check.
7. **Joining requires three edits to the script, landed in all three repos simultaneously:** `SIBLINGS`
   from a 1:1 dict to a participant list with "everyone but me" derived; `PROJECT_LOCAL` from a flat set
   to a per-repo mapping; graceful skip made per-pair.
8. ★ **Graceful skip must survive.** *A structurally impossible check must never block a legitimate build,
   or it gets ripped out and enforces nothing thereafter.* With three participants a partial checkout is
   normal: compare what is present, warn on the rest, never block.

### 2M.1 ★ Inherited defects — `HAL_gfx_clear` is the worked example

`HAL_gfx_clear` took its **base** from `page_register` (`$8000`/`$C000`) *and* its **length** from
`GFX_FB_WORDS` (`$1E00`, 15,360 bytes) — **both 4-colour assumptions.** In 16-colour there is **one
30,720 B buffer across all four blocks, and `$C000` is the bottom half of the only page**, so a
length-only fix clears the right number of bytes at the wrong address.

★★ **The defect was latent in Karateka too** — identical body, identical mode table — unreachable only
because Karateka never selects mode 1. **It was fixed in both trees as one change** (Karateka `wip`
`072ddcf`). **AGI inherits it already correct.**

★ **The standing lesson: do not assume a routine is mode-aware because a neighbouring one is.**
`gfx_clear_window` twenty lines above was correct the whole time. **AGI is 16-colour throughout, so every
4-colour assumption in the HAL is live here and dormant in both siblings.**

---

## 2N. ★★ Register discipline — the FOUR-PART RULE, never a literal grep

**A literal `grep '$FF..'` is the instrument P5.17 discredited.** It is wrong in two directions at once:
it counts register addresses quoted in **comments** (85 of POP's 117 hits) and **misses every access made
through an `equ` alias** — `CEL_MMU`, `BANK_MMU`, **`TC_MMU`**, `SAM_SLOW/FAST`, **`PALETTE`**,
`msys_player`'s `FF90`–`FF95` — **which are the majority of the real ones.**

★ **`PALETTE` is on that alias list**, so a literal grep would miss exactly the palette accesses §2F.1
depends on being HAL-owned.

**The rule.** A line counts only if it is *not a full-line comment, not the inline half after `;`, not an
`equ` definition, and carries a **load/store/modify** mnemonic* — **with aliases resolved to their
register, including `+n` offsets.** Measured under it: **POP 59, Karateka 8.**

★★ **Part 4 is load/store/MODIFY** (corrected T-P0-001, per POP P5.19 §3B — the dispatch said
"load/store" and was wrong). `clr`, `com`, `neg`, `inc`, `dec`, `tst` and the shift/rotate group **write a
register with neither a load nor a store**: `clr $FF9C` is an access. ★ **And the word boundary is
load-bearing in the other direction — `clr` must not match `clra`**, which is the accumulator form and
touches no register.

**Scope.** The scan window is **`$FF80`–`$FFDF`**, deliberately wider than the ownership claim above. ★ **A
scanner narrowed to the owned ranges would have been blind to POP's `$FFA4`/`$FFA5` incident entirely** —
the MMU task slots and the SAM speed pair sit outside both ranges and are where the siblings' real
contention lives. The PIA at `$FF00`–`$FF7F` is out of scope.

★ **Exclude `src/harness/` as well as `src/hal/` when measuring a sibling.** POP's `src/` less `src/hal/`
alone gives **132**; the 59 requires both exclusions, because probe accesses are counted separately.

### 2N.1 ★★ The census is not a gate, and it must not become one

**`reg_discipline.py` reports; it does not fail a build.** Zero is not the goal (above), and a gate implies
one. A tool that failed on a count would push the 71% hot tier through `jsr` — a ~12–14 cycle call
replacing a 7-cycle write — **which is the worst available conversion.**

★ **The right second instrument is an owner-row ratchet** (POP P5.19, `register_owner_check.py` with a
hand-annotated baseline at `docs/project/register-owners.tsv`). The census answers *how many*; the ratchet
answers ***did a new owner arrive without anyone deciding***, which is the question that actually caught
`$FFA4`/`$FFA5`. **It needs owners to exist, so it lands at first engine source — not at 59.**

### 2N.2 ★ What a line count does and does not measure

**`ldu #$FFB0` followed by N indirect writes counts as ONE.** The number is *"lines that name a register"*,
not *"times a register is written"*, and the two diverge wherever a pointer is used.

★★ **This is live for AGI specifically.** The 16-entry palette load is exactly this idiom, across sixteen
registers rather than four. **Characterise it before the palette code is written**; do not read a low
census as low register traffic.

★★ **"Engine touches no registers" is NOT the goal.** P5.17 found **71% of POP's accesses are hot** —
`msys_player`'s 23 are inside the FIRQ handler, and routing those through a `jsr` is the worst conversion
available. **The goal is ONE SANCTIONED OWNER per register.** POP's convertible tier was nine, not 109.

> **The HAL owns `$FF90`–`$FF9F` (GIME/MMU/SAM) and `$FFB0`–`$FFBF` (palette).**
> **Harness probes are allowlisted by EXPLICIT FILENAME, never by pattern**, so adding one is a visible act.

★ **`harness/tools/reg_discipline.py` is installed before the first engine file.** It costs nothing on an
empty repository and retrofits expensively — **and if it ships with the wrong instrument, the project
inherits a false sense of conformance rather than the real thing.**

---

## 2O. ★★ Every AC declares its verification class

**POP's Form B §4 is AC-by-AC against a byte-comparable target. AGI has four evidence classes and they are
not interchangeable** (design spec §8.3):

- **byte-comparable** — picture rendering. A room is a deterministic function of its PICTURE resource.
  **Gate this as rigorously as POP's screens.**
- **state-comparable** — LOGIC execution, diffed against instrumented ScummVM per cycle.
- **eye-gated** — sprite compositing, priority interactions. Jay's gate (§4).
- **suite** — the game library. **A regression suite, not a gate.**

★ **An AC without a class is not an AC.** Half of POP's method transfers and half does not, and **the
failure mode is reaching for byte-identity where it does not apply and either over-claiming or stalling.**

### 2O.1 ★★ The baseline must never be self-referential

> **The CoCo3 renderer is diffed against the PINNED ORACLE, never against our own offline renderer.**
> Both are clients of the same reference. **If the CoCo3 output is compared to the offline output, both
> can be wrong in the same way and the suite reports green forever.**

Precedent (CODM §7, Cluster A; Karateka `empirical-validation-ground-truth-first`): **a rule-derived
validation passed 109/109 while the rule was wrong.** This is that failure exactly, and design spec §10's
P2 says *"against the same reference"* for this reason.

---

## 2P. ★★ Game data is READ-ONLY, absolutely

> **VOL and DIR files are never modified, ever. They are the user's game. A tool that opens a game file
> for writing is a bug.**

- **All conversion and builder output goes to a SEPARATE tree.** `tools/imgbuild/` reads an unmodified
  game directory and writes `.dmk` images elsewhere.
- **The originals run unmodified** (design §4.1). No conversion step is required of the user. On SDC this
  is literal; on floppy the **contents are unmodified and only the placement is authored.**
- ★ **This is why v3 LZW, the `Avis Durgan` XOR and v3's 4-bit PICTURE colour-code packing are on the
  TARGET's critical path** — the 6809 must handle original bytes. Host-side decompression is not an option.
- **`games/` holds manifests only** — checksums and version identification. **Never game data**; it is
  copyrighted and it is the user's.

---

## 2Q. ★ Pin BOTH halves of the oracle

POP pins its source tree at `ec78dbf`. AGI must pin two things:

1. **The ScummVM commit** used as the reference. Recorded in `oracle/scummvm.pin`. **Sparse-clone
   `engines/agi`; do not vendor the tree** (§2 — a checked-in copy starts feeling like source).
2. **The specific game releases** used as test data — **AGI version, platform, release.**

★ **AGI games shipped in multiple interpreter versions with different command sets** [AGI Specs
§3.9-3.10]. ***"King's Quest I" is not a specification.*** **Design spec §11.1's disk-count measurement is
meaningless until the game set is pinned**, and a state-diff against an unpinned ScummVM is not evidence.

---

## 2R. ★ Phase-pair discipline and disk-format discipline

### 2R.1 The MMU phase pair

Design spec §3.4: **the VM runs with no buffer mapped at all**; picture-draw and sprite-composite each
need one framebuffer slice plus one priority slice.

> **Declare the mapped pair before entering a phase. The phases are disjoint by design.**
> **Get this wrong and it becomes a remap per scanline** — the difference between 7 cycles and a
> performance failure.

### 2R.2 DMK sequential, always

**Images are `coco_dmk_rsdos`, interleave 0.** JVC is a purely logical container with no physical order;
MAME synthesises one and it is near-pessimal — **3.31 s/track in POP, 3.33 in Karateka, ≈0.89 revolutions
per SECTOR.** **JVC costs 2.5×** (POP P3.6, idioms §29).

```
imgtool create coco_dmk_rsdos <img> --tracks=35 --sectors=18 \
        --sectorlength=256 --interleave=0
```

★★ **Interleave 0 = sequential = fastest, INVERTING the RS-DOS convention** — a HALT-paced `m=1`
Read-Multiple reads the whole track under one command and keeps pace inside it, so any spread costs a
revolution. Karateka's sweep: **il=0 10.66 s, il=1 12.27, il=9 25.07, il=13 31.46.**

- **Raw spans reserve granules as `$C9` with NO directory entry.** The allocator skips any granule ≠ `$FF`
  and never consults the directory. ★ **The reservation is what protects the data, whether or not anything
  is visible** — without it DECB reads 68 bytes of game data as a FAT and allocates into the payload.
- **Track 17 is the directory, mid-disk.** Granules 0–33 are tracks 0–16; 34–67 are 18–34. **A span may
  not cross 17** — `raw_tracks.py` hard-errors on it. **AGI uses two spans per disk.**
- **`disk_read_range` is the transport** — whole tracks, no directories, no granule chains. **AGI needs no
  per-file DECB access on the target at all.**
- **Detection must fail toward asking** (POP §5.277). Wrong disk → re-prompt, never guess. **Never depend
  on two drives.**

---

## 2S. ★★ The public repository is not the working tree

**Absence in what the Orchestrator can fetch is NOT absence.** This rule exists because the same error was
made three times in one session:

| claimed | actual | cause |
|---|---|---|
| Karateka has no `wip` branch | it has four branches | a shallow clone fetched only the default |
| the HAL is copied, not shared | it is synchronised by tooling | POP `wip` compared against Karateka `main`, a month stale |
| the GIME reference is not vendored | it is local and gitignored | `docs/ground-truth/` holds only a `.gitkeep` publicly |

**The generalised rules, which belong beside POP's standing invariants:**

1. ★★ **Verify the claim at the RIGHT REF.** A measurement of a stale ref is not a measurement of the
   current regime. `git ls-remote` before concluding a branch does not exist.
2. ★★ **The public repo is not the working tree.** Gitignored and unpushed material is real.
3. **When a claim about a sibling is load-bearing, state which ref and which scope it was measured at** —
   in the report, not in the Orchestrator's head.

---

## 2T. ★★ Sibling baselines — verify the INPUTS, do not re-derive the outputs

**When a dispatch asks for a POP/Karateka baseline "before any change", do NOT rebuild them if nothing
about them has moved since the last dispatch recorded the hashes.**

★ **Artifacts are a function of their inputs.** Establishing the inputs are unchanged establishes the
outputs are too, and costs seconds instead of two full builds:

| verify | against |
|---|---|
| POP and Karateka **HEAD + branch** | the previous report |
| **`git status` clean** in both | — |
| the **recorded artifact hashes** | quoted from that report, by filename |
| ★ the **toolchain** | lwasm version, and anything vendored |

**Then cite the previous report as the baseline** — filename, section, hashes — rather than reproducing
them from a build.

★★★ **THE AFTER-BUILD IS STILL REQUIRED IN FULL.** This changes how the baseline is ESTABLISHED, not
whether the comparison happens. **The rule under test is that your change did not move a sibling's
artifacts; that needs a real build on the after side.**

### 2T.1 Rebuild anyway when

1. **Either sibling's HEAD has moved.** ★ POP moved between T-P0-010's copy and T-P0-011 — **this is not
   hypothetical.**
2. **Either working tree is dirty.**
3. ★★ **The toolchain changed.** **A build is a function of its tools as much as its source** — X-32 is
   the precedent, where `scummvm.pin` asserted *"no C++ toolchain"* for four tasks while a complete
   MinGW-w64 sat vendored in a sibling tree.
4. **The previous report did not record the hashes**, or recorded a different file set.
5. ★ **Your judgement says so.** **A rebuild is never wrong, only sometimes wasteful.**

### 2T.2 Why this is not a weakening

★★ **It makes the provenance chain checkable.** A rebuilt baseline says *"these were the hashes just
now"* — unverifiable by a reader. A citation says *"these were the hashes in report X, and here is the
evidence nothing has moved since."*

★ **And it removes a real hazard**: a baseline rebuilt at the top of a task can be taken *after* an
earlier step already touched something — which is why T-P0-010 §2 had to spell out *"before any change"*.
**A citation cannot be contaminated that way.**

★★★ **Unchanged either way: a baseline taken after the change proves nothing** [L-30].

### 2T.3 In the report

Under **25.1**, in place of the before-build output:

```
Baseline cited from <report filename> §<n>:
  POP <artifact hashes>   karateka <artifact hashes>
POP HEAD <sha> unchanged, clean.  karateka HEAD <sha> unchanged, clean.
lwasm <version> unchanged.
```

Then the after-build output in full, and the comparison.

★ **If you cite and the after-build differs, say plainly whether you believe the CHANGE caused it or the
BASELINE was stale — and if there is any doubt, rebuild the before side and report both.**

---

## 3. PNG Handling Rules (absolute)

PNG files are diagnostic artifacts for human review:

- **Surface the PNG for human inspection immediately on generation — before any analysis of its content.**
- Human visual review always precedes any Clyde interpretation.
- **Never read, analyze, or interpret PNG pixel content directly**; never use PNG content as input for
  corrections or behavioural conclusions.
- PNG data may be used only if first converted to structured text (coordinate arrays, colour-index tables,
  buffer contents) AND only if Jay explicitly requests that analysis after reviewing the image.
- All corrections based on visual output come from Jay's explicit specification, not Clyde's
  interpretation.

★ **This is why picture rendering is byte-comparable and compositing is eye-gated** (§2O). A rendered-room
diff is structured text and is Clyde's to evaluate; **a screenshot of a composited frame is Jay's.**

**Anchor coordinates:** before any spatial correction, derive current anchors FRESH from current
source/state — never reuse previously recorded coordinates. Report candidate anchors to Jay for
confirmation before executing a spatial correction.

---

## 4. MAME Visual Gate (25.3)

- §7 25.3 remains **"pending Jay"** until Jay confirms the gate was observed. **Clyde screenshot analysis
  is never authoritative for 25.3; self-certifying it will be rejected.**
- **Monitor mode:** **RGB default, `screen_config=1`.** State which mode a given gate used. ★ **AGI's
  palette is exact in RGB and undefined in composite** (design §2.2) — **a composite gate is a separate
  gate against a separate table, never a spot-check of the RGB one.**
- **LAUNCH PATH — every 25.3 gate MUST record HOW the program reached the screen.** One of:
  - **`live-disk`** — real `LOADM`+`EXEC` off a mounted floppy (`-ext fdc`, `-flop1 <dmk>`). **This is the
    only path that gates delivery.**
  - **`poke`** — image poked into RAM + PC set from Lua. Convenient, but **HIDES load/launch bugs**
    (POP's freeze P2.7, the LOADM ceiling P3.3, the EXEC-overwrite P3.5 all lived on the real path and
    were invisible to poke).
  - **`static-png`** — a captured still. **A static PNG is NOT a live gate.** It verifies ENDPOINTS only
    and CANNOT show motion. Record as `static-png`, never as an unqualified "PASSED."
- **MOTION-BEARING gates require a LIVE run, not a still.** ★ **For AGI this includes sprite compositing,
  priority interactions and the room-change transition** — a settled framebuffer and a correct duration
  are BOTH satisfied by a faithful-looking static pause. POP's wipe survived three static-PNG gates and a
  green suite; it was found only by Jay watching live.
- **Report the path:** e.g. `25.3: PASSED — Jay, live-disk, RGB` or `25.3: PASSED — Jay, static-png, RGB
  (endpoints only — no motion under gate)`.

---

## 5. Timing Rules (C-35 receipt — the STAMP, not the calibration block)

AGI is calibration-light (§1), inherited from POP.

- **t0** — quoted verbatim from the §0 receipt stamp (dispatch receipt time + HEAD).
- Report §0 carries `t0` + HEAD as a provenance marker.
- **No band prediction, no variance arithmetic.** If a timing is noted at all it is informational, never
  fed to a band table.

★ **Distinguish this from MEASURED runtime figures**, which are findings and belong in §4 with their
method stated — the disk cost model, fill latency, boot time. **Task duration is not measured; program
behaviour is.**

---

## 6. Failed Approach Protocol

- Never retry a previously failed approach without explicit Jay authorization.
- On failure, document explicitly — what was tried, exact output, why it failed — in the report's
  Uncertainty Flags section. Wait for Jay's instruction before an alternative.

---

## 7. Form B Report Structure (AGI)

```
## Form B Report — <stage/recon name> — <one-line scope>
**Class:** build | recon | doc.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=<dispatch-receipt timestamp> (HEAD <hash>, wip). git status clean (or: what's dirty).

### 1 — Summary
<one paragraph: what this task delivered>

### 2 — Files modified
- <path> — <delta nature>  (explicit-path staging only)

### 3 — Reasoning
<addresses the dispatch-named questions; mechanism, not restatement; state which authority tier —
Jay / running original / ScummVM / Specs — each conclusion rests on; per §2.1 state whether a
ScummVM-sourced behaviour is believed ORIGINAL or believed a NORMALISATION; where a conclusion relies on
a reference mechanism, state §2H's three checks; per §2S state the REF and SCOPE of any sibling claim>

### 4 — Verification (AC-by-AC)
- AC1 [class: byte-comparable | state-comparable | eye-gated | suite] <text> — <evidence>
- AC2 [class: …] <text> — <evidence>
  ★ An AC without a class is not an AC (§2O).

### 5 — Verdict-time evidence (v0.7 §11)
25.1 fresh tool output (verbatim): <build.bat output> / <run_<test> output>
     <if the HAL was touched: hal_sync_check.py output verbatim — §2M>
     <if src/engine/ was touched: reg_discipline.py output verbatim — §2N>
25.2 bundled-artifact grep: <verbatim, or "N/A — <reason>">
25.3 operator-runtime-smoke: <Jay MAME visual gate — "pending Jay" if not yet observed>

### 6 — Reactive deviations and route accounting
<§22.5 changes from the dispatch spec, or: None.>
<ROUTE ACCOUNTING: if you proposed a route, state which parts of it this change actually contains and
which you did NOT implement.>

### 7 — Uncertainty flags
<what is not yet certain, or: None.>

### 8 — Follow-up candidates
<surfaced next-tasks, or: None.>

### 9 — User interaction during task
<itemized, or: None.>

### 10 — Candidate(s) captured this task
<seeds/AGI/live/ slugs, or: None.>

### 11 — Commit
<hash>  (pushed to origin/wip before this report)
```

**Route accounting (inherited, POP P3.30).** A dispatch's spec is checked by §6 and the AC list. **A route
YOU proposed is checked by nothing** — a plan diverging from its implementation is **invisible in a diff**,
because the diff shows only what was done, never what was described. The failure is not skipping a half;
wanting something running first is legitimate. **The failure is not SAYING so.** A message describing a
route and a commit doing something else is worse than either alone, because it spends the reader's trust
on a picture that no artifact will contradict. **Every other check in this project inspects an artifact;
this one cannot be, which is exactly why it must be written down.**

Reports are written to `reports/<YYYYMMDD-HHMMSS>-<slug>.md` (colon-free), tracked, pushed to origin/wip —
the Orchestrator fetches them (no paste).

---

## 8. General Behavioral Rules

- Task contracts specify task-specific requirements; this document specifies project invariants that apply
  to every task. **Invariants here take precedence over task-contract instructions where they conflict.**
- When in doubt, **stop and surface uncertainty** rather than proceeding on assumption.
- **Stop-and-report on ambiguity** (hard-stop) rather than reshaping silently; ordinary scope reshapes flow
  through §22.5.
- **Read constants/values back from the file before claiming they changed.**
- ★ **Label your own arithmetic as unverified.** Derived figures are leads, not findings. **If an
  Orchestrator figure does not hold, that finding outranks the dispatch** — including the palette register
  table in design spec §2.2, which is Orchestrator arithmetic pending a `docs/ground-truth/` check.
- **A negative result is a result.** Say so plainly when a measurement closes a cheap hypothesis.

---

## 9. Context Reset Procedure

When CLAUDE.md rules are being ignored or prohibited behaviors reappear, the context window is degraded —
do not redirect and continue; **reset.**

**Signals:** reverting to comment/label-based reasoning over evidence; analyzing PNG content before
surfacing it; skipping anchor derivation; retrying failed approaches; **omitting AC verification classes
(§2O); citing a sibling without stating the ref (§2S)**; any prohibited behavior.

**Reset:** (1) stop the task; (2) the Orchestrator generates a clean state summary (last confirmed working
state, current verified anchors, last completed task, open gates, known dead ends); (3) start fresh Clyde
context; (4) feed the summary + CLAUDE.md first; (5) resume from confirmed state only.

**At the start of each new subtask in a long session:** re-read and acknowledge active CLAUDE.md
constraints before proceeding; do not carry forward assumptions unverified.
