## Form B Report — T-P0-004 — the CoCo3 corpus: ignore hardening landed, archives awaited
**Class:** build + recon. wip. **★ PARTIAL — stopped at §2's step 2 by design (§8.2).**

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-24T03:54:15Z. HEAD at receipt `84c4517` (wip) → **at report `1edff3e`**, pushed.
`git status --porcelain` at report → **clean**.

---

## ★ §3 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

### 3.1 Locations

```
coco_agi        branch wip   HEAD 84c4517cb8291d38844548cc70331147ac6df436  (at receipt)
POP3_port       branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3  branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
```

Both sibling refs **unchanged since T-P0-001**, so AC-9's figures stand at the refs at which they
were first measured (§2S.3).

### 3.2 ★★★ IS ANY GAME DATA ALREADY TRACKED? — **NO. HISTORY IS CLEAN.**

**The hard stop was checked first, before any other work.**

```
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u
  -> 50 distinct paths ever added, across all branches, for the life of the repository

$ ... | grep -iE '\.dsk$|\.par$|\.zip$|\.os9$|\.img$|vol\.|logdir|picdir|viewdir|snddir|words\.tok|object$|agidata'
  (no output)
```

★ **The 50 paths were also read in full rather than only grepped**, because a grep proves absence
only of what it looks for. Every one is repository infrastructure: `.gitattributes`,
`.gitignore`, `CLAUDE.md`, `README.md`, 31 × `.gitkeep`, six `harness/tools/` scripts and
fixtures, four `oracle/` patches plus `scummvm.pin`, two `mame-idioms-*.md`, three reports, and
**one file under `games/`: `games/manifests/agile-gdx-81c42ba.tsv`** — the P0.3 manifest, which
carries checksums and sizes and no content.

**§8.1's trigger did NOT fire. No remedy was attempted or needed.**

### 3.3 Corpus location and archive presence

```
C:\Projects\agi-games\           EXISTS -- contains only: agile-gdx/   (the P0.3 fan corpus)
C:\Projects\agi-games\coco3\     ABSENT -- not yet created
repo root archives (.dsk/.par/.zip/.os9/.img)   NONE PRESENT
```

### 3.4 `game_manifest.py` — the input formats it currently handles

**ZIP archives only**, and nothing else:

```
harness/tools/game_manifest.py:38   import zipfile
                             :102   with zipfile.ZipFile(path, "r")   # 'r' -- read only, always
                             :136   ap.add_argument("corpus", ...)    # "directory of game .zip archives"
                             :142   zips = sorted(root.glob("*.zip"))
```

★ **There is no OS-9 support and no disk-image support of any kind.** AC-4's extension is
genuinely new code, not a parameter change — and per §2H it cannot responsibly be written
against zero images (§6.2).

---

### 1 — Summary

**The safety property is in place and pushed. The corpus has not arrived, so the task stops
where §2 says it stops.**

★★★ **AC-1 is done and it is the acceptance criterion the whole dispatch is sequenced around.**
`.gitignore` now rejects every carrier format and every extensionless AGI resource name at any
depth, plus Sierra's interpreter directories — **committed and pushed at `1edff3e` BEFORE any
archive exists in the repo root**, which is the entire point. 32 probe paths were proven ignored
and 6 manifest/source paths proven still allowed, without creating a single file (§3A).

**AC-9 passes.** Everything else — AC-2 through AC-8 — requires the seven archives, which are
not present. §8.2 is explicit that this is a stop and not an invitation to proceed speculatively,
and §6.2 explains why writing the OS-9 reader blind would be worse than merely premature.

> ★★ **It is now safe for Jay to drop the archives in the repository root.** The hardening is
> pushed. Nothing further should be dropped until this report's verdict, but the ordering
> constraint that made step 2 a gate has been satisfied.

---

### 2 — Files modified

Explicit-path staging (§2E). One commit.

**`1edff3e`**
- `.gitignore` — the game-data hardening block. **The only change this task.**

**No game data entered the repository, the index, or history.** Nothing was extracted, because
nothing arrived.

---

### 3 — Reasoning

#### 3A — ★★★ Why the ordering is the whole task, and how AC-1 was proven without creating files

§2 is emphatic and it is right: **game data pushed to a public repository cannot be deleted.**
A later `rm` removes it from the working tree and leaves it in history; the remedy is a history
rewrite plus a force-push, and this project has **three synchronised sibling repos** (§2M) whose
HAL contract is checked by tooling — so a rewrite here is not a local act. **Patterns added after
the fact protect nothing that matters.** Hence: commit, push, *then* invite the drop.

★ **The proof method matters too.** `git check-ignore` operates on a **path string**, so every
pattern was verified **without writing a single probe file into the repository**. Testing a rule
whose purpose is *"these files must never exist here"* by first creating such files would be a
small self-contradiction, and on a `.dsk` of real game data it would not be small.

**32 paths proven ignored** — carrier formats at root and at depth, all four v2 DIR names, both
case variants of `words.tok`/`object`/`LOGDIR`, v3 shapes (`dmdir`, `vdir`), volume forms
(`vol.0`, `vol.14`, `KQ3VOL.1`, `dmvol.0`), and Sierra's `CMDS/`, `MODULES/`, `OS9Boot`.
**6 paths proven still allowed**, including both manifest TSVs — the `games/**` negations are not
overridden, because no pattern in the new block matches a `.tsv`, `.md` or `.json`.

★ **Two deliberate choices, stated because they cost something:**

1. **`*dir` is broad on purpose.** A v3 title names its directory file after its own prefix
   (`dmdir`, `vdir`), so the name set is open-ended and cannot be enumerated. The cost is that a
   future directory ending in "dir" would also be ignored; the benefit is that no v3 title slips
   through on a prefix nobody predicted. An intended file can still be added with `git add -f`,
   **which is a visible act** — the same reasoning §2N applies to the register allowlist.
2. **Both letter cases are listed** (`logdir` and `LOGDIR`, `object` and `OBJECT`). On this
   Windows host git matched case-insensitively — `WORDS.TOK` was caught by the `words.tok` rule —
   **but that is a property of this filesystem, not of the rule.** On a case-sensitive checkout
   only the exact case matches, and OS-9 media conventionally uses upper case. Listing both makes
   the rule portable rather than accidentally correct here.

★ **What this does NOT do, said plainly so nobody over-trusts it:** `.gitignore` does not protect
an already-tracked file and does not stop `git add -f`. **It stops the accident, not the intent.**
The primary control remains §2E's explicit-path staging, and this dispatch is the one that earns
that rule its keep.

#### 3B — Why the stop is at step 2 and not further in

§2's sequence puts "tell Jay it is safe" at step 2 and processing at step 3. The archives are
absent (§3.3), and **§8.2 makes that a report-and-stop, not a wait-and-guess.**

★ **The one piece of work that might look safe to start — extending `game_manifest.py` for OS-9 —
is the piece most clearly barred, and §6 says why in advance:** *"a directory format found in one
image is a hypothesis about the format, not the format"* (§2H). **I have zero images.** Writing an
OS-9 directory reader now would mean writing it against the format as I understand it in the
abstract and then meeting seven real images that may each disagree — the exact first-mechanism
failure §2H exists to prevent, with the added hazard that a reader which *runs* is far more
persuasive than one that does not, whether or not it is right. **AC-4's figures also have to
reproduce the Orchestrator's ad-hoc numbers (§4.4), which is only meaningful if the tool was
written to the images rather than to an expectation.**

AC-9 was run because it depends on nothing this task is blocked on.

#### 3C — §2H's three checks, applied to what little was decided

1. **A SECOND mechanism for a different object class?** ★ Yes, and it shaped the pattern list.
   The obvious mechanism is *extensions* (`.dsk`, `.zip`) — and **AGI's actual content files have
   no extension at all** (`logdir`, `object`, `words.tok`). An extension-only rule would have
   looked complete, passed a casual review, and ignored none of the game. **A third class exists
   and is also covered: Sierra's interpreter is neither** — it is copyrighted *code*, not game
   data, arriving as `CMDS/`, `MODULES/` and `OS9Boot`.
2. **Name the routine that CALLS it.** The "caller" here is whoever stages. `.gitignore` is
   consulted only by `git add` on an untracked path — so its scope is exactly the accidental
   bulk add, and **nothing else in the pipeline consults it.** That is the honest bound on what
   AC-1 buys, and it is why §3A ends where it does.
3. **Grep prior reports for the same subsystem.** P0.3 §2 recorded the decision not to commit
   room dumps, for the same reason §6 gives here — a rendering of game content is game content.
   **Consistent, no contradiction**, and this task extends that ruling to screenshots (§6).

#### 3D — Refs and scopes (§2S.3)

AC-9's sibling figures at **POP `wip` `282a65c`** and **Karateka `wip` `072ddcf`**, over the
scopes named in §5. No claim about the CoCo3 corpus is made anywhere in this report, because
none can be.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] ★★★ THE SEQUENCED CRITERION** — `.gitignore` hardened, **committed and
  pushed at `1edff3e` before any archive existed in the repo root**. 32 probe paths proven
  ignored with the matching rule and line number shown; 6 proven still allowed. Verbatim in §5.
  ✅ **PASS.**
- **AC-2 [byte-comparable]** — **PARTIAL / VACUOUS.** `git status --porcelain` clean, history
  grep empty, no `.dsk`/`.par`/`.zip` in the tree — **but nothing was processed, so this verifies
  an untouched repository rather than a safely-processed one.** It is re-run evidence after
  step 3, not evidence now. ⚠️ **Reported as vacuous rather than claimed as a pass.**
- **AC-3 [suite]** — ❌ **BLOCKED.** No archives present.
- **AC-4 [suite]** — ❌ **BLOCKED.** `game_manifest.py` handles ZIP only (§3.4); the OS-9 reader
  is new code and §6.2 gives the reason it was not written blind.
- **AC-5 [state-comparable] — M-11** — ❌ **BLOCKED.** Needs the KQ3 variants.
- **AC-6 [suite]** — ❌ **BLOCKED.** Needs both shipped sets.
- **AC-7 [state-comparable]** — ❌ **BLOCKED.** Needs `CMDS/Sierra` and `MODULES/`.
- **AC-8 [eye-gated]** — ❌ **BLOCKED.** Needs a bootable image.
- **AC-9 [byte-comparable]** — `coco_agi` **0**; POP **59** at `282a65c`; Karateka **8** at
  `072ddcf`; all three `--expect` assertions rc=0; fixture demo rc=0 including its negative
  control. ✅ **PASS.**
- **AC-10 [suite]** — **None.** §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1a — ★ AC-1, `git check-ignore -v`, verbatim (rule:line shown for each):**

```
=== MUST BE IGNORED ===
  IGNORED   kq3.dsk                      <- 87:*.dsk
  IGNORED   lsl.par                      <- 88:*.par
  IGNORED   corpus.zip                   <- 89:*.zip
  IGNORED   boot.os9                     <- 90:*.os9
  IGNORED   disk1.img                    <- 91:*.img
  IGNORED   game.dmk                     <- 92:*.dmk
  IGNORED   x.jvc                        <- 93:*.jvc
  IGNORED   a.7z                         <- 98:*.7z
  IGNORED   b.rar                        <- 99:*.rar
  IGNORED   c.tar.gz                     <- 103:*.gz
  IGNORED   vol.0                        <- 113:*VOL.[0-9]
  IGNORED   vol.14                       <- 111:vol.*
  IGNORED   KQ3VOL.1                     <- 113:*VOL.[0-9]
  IGNORED   dmvol.0                      <- 113:*VOL.[0-9]
  IGNORED   logdir                       <- 132:*dir
  IGNORED   picdir                       <- 132:*dir
  IGNORED   viewdir                      <- 132:*dir
  IGNORED   snddir                       <- 132:*dir
  IGNORED   words.tok                    <- 124:WORDS.TOK
  IGNORED   object                       <- 125:OBJECT
  IGNORED   LOGDIR                       <- 132:*dir
  IGNORED   WORDS.TOK                    <- 124:WORDS.TOK
  IGNORED   OBJECT                       <- 125:OBJECT
  IGNORED   dmdir                        <- 132:*dir
  IGNORED   vdir                         <- 132:*dir
  IGNORED   CMDS/Sierra                  <- 137:CMDS/
  IGNORED   MODULES/rbf.mn               <- 138:MODULES/
  IGNORED   OS9Boot                      <- 140:os9boot
  IGNORED   deep/nested/path/vol.3       <- 113:*VOL.[0-9]
  IGNORED   a/b/c/logdir                 <- 132:*dir
  IGNORED   x/y/kq3.dsk                  <- 87:*.dsk
  IGNORED   some/where/object            <- 125:OBJECT

=== MUST NOT BE IGNORED ===
  allowed   games/manifests/coco3-images.tsv
  allowed   games/manifests/agile-gdx-81c42ba.tsv
  allowed   games/manifests/notes.md
  allowed   harness/tools/game_manifest.py
  allowed   reports/some-report.md
  allowed   oracle/patches/0004-x.patch
```

★ **No probe file was created.** `check-ignore` takes a path string; the rule was proven against
strings alone (§3A).

**25.1b — AC-2 (interim, and vacuous — see §4):**

```
$ git status --porcelain
(empty)
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u | grep -iE '<game-data signatures>'
(empty)
$ ls *.dsk *.par *.zip *.os9 *.img
NONE PRESENT
```

**25.1c — AC-9, `reg_discipline.py` ×3, verbatim:**

```
coco_agi  src/engine/**                    [reg-discipline] OK -- measured 0   rc=0
POP       src/ less src/hal,src/harness    [reg-discipline] OK -- measured 59  rc=0
Karateka  src/ less src/hal                [reg-discipline] OK -- measured 8   rc=0
harness/tools/fixtures/run_rule_demo.sh    rc=0  (incl. the --expect 7 negative control)
```

**25.1d — the manifest summary (AC-4):** **N/A — blocked.** No OS-9 images exist to measure.

**25.2 — bundled-artifact grep:** **N/A.** No build artifact was produced; the only change is a
`.gitignore`, which produces nothing to bundle.

**25.3 — operator-runtime-smoke:** **N/A — AC-8 blocked, no image to boot.** No launch path to
record, because nothing was launched. When AC-8 runs it will be `live-disk` or it will be
reported as the lesser path it actually was (§4).

---

### 6 — Reactive deviations and route accounting

1. **Extra carrier formats beyond the dispatch's list.** §5 AC-1 names `.dsk`, `.par`, `.zip`,
   `.os9`, `.img`; I also added `.dmk`, `.jvc`, `.vhd`, `.d77`, `.hfe`, `.7z`, `.rar`, `.tar`,
   `.tar.gz`, `.tgz`, `.gz`, `.arc`, `.lzh`. **An archive can arrive in any wrapper**, and the
   cost of an unused pattern is zero while the cost of a missing one is unbounded.
2. **Both letter cases listed** for the extensionless names (§3A.2), which the dispatch does not
   specify. OS-9 media conventionally uses upper case.
3. **`CMDS/`, `MODULES/`, `OS9Boot` added** — not in AC-1's list. Sierra's interpreter is
   copyrighted code rather than game data, and §7 makes clear it is a comparison target; it
   should no more be committed than a VOL.
4. **Stopped at §2 step 2** rather than proceeding — §8.2.

**ROUTE ACCOUNTING.** No route was proposed to Jay or the Orchestrator this task. **What this
change contains is one file: `.gitignore`.** **What it does NOT contain, said here rather than
left to the diff: no OS-9 reader, no manifest, no extraction, no M-11 answer, no duplication
analysis, no interpreter inventory, no MAME boot, no screenshot.** Seven of ten AC are untouched
and I have deliberately not begun any of them. **Explicitly not done per §12:** no `src/hal/`, no
`hal_sync_check.py` edit, no `build.bat`, no CoCo3 code, no offline renderer, no VOL/DIR parser,
no game data or screenshot committed, no disassembly of Sierra's interpreter, no v3 decision.

---

### 7 — Uncertainty flags

1. **★ AC-2 is currently vacuous and must be re-run after step 3.** A clean status on a repository
   that processed nothing proves only that nothing happened. Its value is entirely in the
   post-processing run, and it should not be read as satisfied.
2. **★ `.gitignore` is defence in depth, not the control.** It cannot protect an already-tracked
   file and does not stop `git add -f`. If the corpus is ever staged deliberately-but-wrongly,
   nothing here intervenes. **The control is §2E.**
3. **`*dir` will ignore any future directory whose name ends in "dir"** (§3A.1). Deliberate, and
   flagged because the surprise would otherwise land on whoever hits it.
4. **The case-insensitive match observed here is a Windows property, not a rule property**
   (§3A.2). A Linux checkout behaves differently, and the rule set was written for that case.
5. **The OS-9 reader's difficulty is unknown**, because no image has been seen. §2H's warning
   about one image not defining the format is the reason I decline to estimate it, and AC-4 may
   turn out to be larger or smaller than it looks.
6. **★ The seven titles are unverified in every respect.** Titles, media variants, byte counts,
   which are Sierra-shipped and which are not — all of it is dispatch description at this point.
   **Nothing in §1 or §3 of the dispatch has been confirmed against an artifact**, and per §2S.2
   a description is not a measurement.

---

### 8 — Follow-up candidates

1. ★★★ **Jay drops the seven archives in the repo root; T-P0-004 resumes at §2 step 3.** The
   hardening is pushed, so the drop is now safe.
2. **Write the OS-9 reader against the images, not ahead of them**, and run §2H's second check
   explicitly: confirm the directory-entry shape holds across **all seven** before trusting a
   figure from any one (§8.3 is the trigger if it does not).
3. **Re-run AC-2 after processing** — its whole value is post-hoc (§7.1).
4. ★ **AC-5 (M-11) should be answered by comparing per-volume hashes, not sizes alone.** The
   Orchestrator's two hypotheses — a missing `vol.14` versus "different builds" — are both
   consistent with a size table; only content hashes separate them, and §8.5 anticipates a third
   answer.
5. **Consider back-porting the hardening block to POP and Karateka.** Neither holds game data
   today, but Karateka's corpus question is the same shape. Separate explicit task per §2G.

---

### 9 — User interaction during task

**None.** No question was put to Jay and no guidance was received.

★ **One consultation trigger fired and was obeyed: §8.2** — the archives were not present at
§2's step 2, so the task stops and reports rather than proceeding speculatively. §8.1 was checked
first and did **not** fire (history clean, §3.2). §8.3, §8.4 and §8.5 cannot fire yet, as all
three concern artifacts that have not arrived.

---

### 10 — Candidate(s) captured this task

**None.**

★ Stated rather than manufactured. This task committed one file and stopped at a gate; nothing in
it was a methodology observation at first instance. The ordering discipline §2 encodes is
genuinely valuable, but it arrived as a dispatch instruction rather than as something discovered
here, and §2C's rule is capture at the **first instance** of an observation — not re-capture of a
rule that was handed over already written.

---

### 11 — Commit

`1edff3e` — one commit this task:

```
1edff3e  P0.4a .gitignore: game-data hardening, BEFORE the CoCo3 corpus arrives
```

Pushed to `origin/wip` **before** this report and, more importantly, **before any archive
exists** — which was the point. This report is a second commit on `wip`.
