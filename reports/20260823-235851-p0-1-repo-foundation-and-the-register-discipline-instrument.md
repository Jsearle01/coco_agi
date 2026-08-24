## Form B Report — T-P0-001 repo foundation — tree, working agreement, register-discipline instrument
**Class:** build (infrastructure). wip.

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-23T23:58:51Z.

★ **HEAD at receipt: none — `coco_agi` was not a git repository.** The directory existed and held
three untracked files (`CLAUDE.md`, `mame-idioms-coco3-port.md`, `mame-idioms-addendum.md`) and no
`.git`. `git init -b wip` is therefore part of this task, and the C-35 stamp has no pre-image HEAD
to quote. **HEAD at report: `74d48fa`, `wip`, pushed to `origin/wip`.**

`git status --porcelain` at report → **one line**, `?? mame-idioms-addendum.md` — deliberately left
untracked, see §7.1.

---

## ★ §2.1 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

### A — File locations, the HARD STOP table

| check | expected | measured | verdict |
|---|---|---|---|
| repo dir name | `coco_agi` exactly | `/c/Projects/coco_agi`, basename `coco_agi` | ✅ **PASS** |
| `C:\Projects\POP3_port`, branch `wip` | present | present, `wip` | ✅ **PASS** |
| `C:\Projects\karateka_coco3`, branch `wip` | present | present, `wip` | ✅ **PASS** |
| `git remote -v` | `github.com/Jsearle01/coco_agi` | **no repository existed** — see below | ⚠️ **see A.1** |

**Sibling refs, stated as CLAUDE.md §2S.3 requires:**

```
POP3_port        branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
                 origin git@github.com:Jsearle01/POP3_port.git
karateka_coco3   branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
                 origin git@github.com:Jsearle01/karateka-coco3.git
```

★ Karateka's HEAD `072ddcf` is the `HAL_gfx_clear` fix commit named in CLAUDE.md §2M.1. The
sibling is at exactly the ref that section describes.

#### A.1 ★ The remote check could not be run as specified, and here is what was done instead

There was no `coco_agi` git repository, so there was no remote to inspect and no clone that could
have landed via the `coco-agi` redirect. **The hard stop guards against a wrongly-named working
directory arriving from the redirect; the directory name is correct, which is the condition that
actually matters** (`hal_sync_check.py` resolves siblings by directory name, CLAUDE.md §1A).

Probing both names before creating anything:

```
git ls-remote git@github.com:Jsearle01/coco_agi.git   -> rc=0, zero refs
git ls-remote git@github.com:Jsearle01/coco-agi.git   -> rc=0, zero refs
```

★★ **Both names resolve and both are empty, so `ls-remote` cannot distinguish the canonical name
from the redirect** — GitHub serves the permanent redirect over SSH transparently. The remote was
therefore **authored, not inherited**: `git remote add origin git@github.com:Jsearle01/coco_agi.git`,
the canonical underscore form, typed explicitly rather than resolved. The push confirms the
canonical name in its own output (§5). **This is a deliberate deviation from the letter of the
check and is recorded rather than treated as a pass.**

### B — Shape checks (report, do not act on)

**`harness/tools/hal_sync_check.py` in POP — read only, NOT modified, `coco_agi` NOT added.**

```
SHARED = src/hal.inc
         src/hal/coco3-dsk/{sys,time,irq_vbl,gfx,input,sound,file,mem,disk_read}.s
         harness/tools/hal_sync_check.py
PROJECT_LOCAL = {'src/hal/coco3-dsk/hal_globals.s'}
SIBLINGS      = POP3_port <-> karateka_coco3   (two-party, 1:1)
```

Confirmed as CLAUDE.md §2M.5 describes: **eleven files compared, two participants.** D-08 is
untouched; `coco_agi` has no `src/hal/`, no `build.bat`, and no sync call.

**POP's `.gitattributes`** — reproduced verbatim as AC-3's baseline; see §5 for the identity proof.
**POP's `.gitignore`** — read; `coco_agi`'s is seeded from it and diverges deliberately (§3E).

### C — ★★★ THE MATERIAL FINDING: P5.17, P5.18, P5.18b **AND P5.19** ALL EXIST LOCALLY

The dispatch (§2.2) records the Orchestrator's last fetch as ending at **p5-16** and asks for
filenames if later reports exist locally. They do — **four of them**, and the last one changes the
premise of this task:

```
reports/20260823-200239-p5-17-who-owns-the-gime-registers.md
reports/20260823-202551-p5-18-hal-gfx-clear-blocked-by-the-sync-gate.md
reports/20260823-210943-p5-18b-hal-gfx-clear-landed-in-both.md
reports/20260823-214135-p5-19-the-register-ratchet.md          <-- NOT ANTICIPATED
```

★★ **P5.19 already built this instrument for POP.** `harness/tools/register_owner_check.py`
(10,522 B, 2026-08-23 17:29) exists, is wired into `build.bat:884`, and has a hand-annotated
baseline at `docs/project/register-owners.tsv`. **This is CLAUDE.md §2S.2 in miniature — the
Orchestrator's fetch is not the working tree — and it is exactly the failure shape §2S was written
to stop, arriving on the first dispatch after it was written.**

**Consultation trigger §8.3 evaluated and NOT fired.** The trigger is *"P5.17 or P5.18 exists
locally **and contradicts §3**."* The primary sources were read in full and **they do not
contradict §3 — they confirm it**, and each of §3's four parts appears in P5.17 §3A and P5.19 §3B
in the same words. **One refinement, in the primary's favour:** P5.19 §3B states part 4 as
*"carries a load/store/**modify** mnemonic"* where the dispatch says *"load/store"*. Modify is the
wider and correct reading — `clr $FF9C` is a register write with neither a load nor a store — so
**the primary was followed** and part 4 is implemented as load/store/modify. See §3B.

★ Also carried over from the primary and **not** in the dispatch: `TC_MMU` belongs on §3's alias
list (P5.17 §3B; it is how `$FFA4`/`$FFA5` acquired a second owner). The tool discovers aliases by
parsing `equ` rather than from a hardcoded list, so the omission cost nothing — but the dispatch's
list is incomplete and that is worth saying.

### D — Pre-existing files in the working directory

`mame-idioms-coco3-port.md` was already present and is **byte-identical to POP's at `wip`
`282a65c`** (SHA-1 `3c862de27b7398b19531d2080cbce6cd491ce73c`, both). `mame-idioms-addendum.md`
was also present, byte-identical to POP's (`8f4442d8…`), and **is not in the dispatch's §5 file
list** — see §7.1.

---

### 1 — Summary

The tree, the working agreement and the register-discipline instrument are in place at `74d48fa`,
and **the instrument reproduces POP's independently measured 59 and Karateka's 8.**

★★ **The load-bearing result is not that it returned 59 — it is why the 59 was not accepted when
it appeared.** The tool hit 59 on its first run, which is AC-5, and the per-file breakdown printed
beside it **disagreed with P5.17 §3A's per-file table**: `intro_splash.s` 1 against 5,
`char_draw.s` 6 against 4, `loader.s` 3 against 2, `intro_seq.s` 20 against 19. **The
discrepancies cancel exactly.** A total-only comparison would have certified the tool by a
coincidence. Running it down found a genuine fork in what counts as an access — `ldu #$FFB0` loads
a register's *address* into a pointer, so one line stands for several indirect writes — and
settled it with a third measurement: **POP's own `register_owner_check.py`, imported and run over
the identical scope, agrees with this tool SITE FOR SITE, zero divergence in either direction
(59 = 59).** Both tools agree; P5.17 §3A's published **table** is what is transcribed wrongly,
while its **total** is right. That is a finding about POP's report, not a defect here.

**Ten AC met, one deliberately deferred** (AC-7's fixture is not tracked, because tracking it
would break AC-1's "matches §5 exactly" — §7.2).

---

### 2 — Files modified

Explicit-path staging throughout; **`git add -A` was not used** (§2E).

- `CLAUDE.md` — **committed as provided, not edited** (§2D, AC-2).
- `.gitattributes` — **copied byte-verbatim from POP** `282a65c` (AC-3).
- `.gitignore` — new; seeded from POP's, plus `docs/ground-truth/` (§2.2), `games/**` (§2P) and
  the no-vendored-oracle rules (§2Q.1). Each divergence carries its rule citation in-file.
- `README.md` — new, 9 lines.
- `mame-idioms-coco3-port.md` — **banner prepended**, marking it inherited-and-unverified for AGI
  and naming the 16-vs-4-colour trap (§2G). Body untouched.
- `harness/tools/reg_discipline.py` — **new, the deliverable.** 380 lines, stdlib only.
- 31 × `.gitkeep` — the §5 skeleton.

**Not created, as §12 requires:** no `src/hal/`, no `build.bat`, no engine/tool/converter source,
no game data, no ScummVM. **No sibling repository was modified** — POP's tracked tree is clean at
report (§5).

---

### 3 — Reasoning

#### 3A — Which authority each conclusion rests on

Every conclusion in this report rests on **§2 tier 2, execution / fresh tool output** — counts
measured over the trees, not descriptions of them — except the four-part rule itself, which rests
on **POP's P5.17/P5.19 as a project-internal primary source**, read in full rather than
paraphrased. **No conclusion here rests on ScummVM or the AGI Specs**, so §2.1's
original-vs-normalisation declaration does not arise this task. Nothing here is eye-gated.

#### 3B — ★★ The instrument, and the one place it departs from the dispatch's wording

Implemented **fresh from §3's statement**, not copied from POP's `register_owner_check.py`. That
was a deliberate choice and it is what makes AC-5 mean anything: had POP's classifier been copied,
reproducing POP's figure would have been near-tautological. **The two implementations are
independent and their agreement is evidence** (§2O.1 applied to the tool itself).

Part 4 follows P5.19's **load/store/modify** over the dispatch's **load/store**, for the reason in
§C: `clr`, `com`, `neg`, `inc`, `dec`, `tst` and the shift/rotate group all write a register with
neither a load nor a store, and excluding them would undercount. The trailing `\b` is load-bearing
in the opposite direction — **`clr` must not match `clra`**, which is the accumulator form and
touches no register. Both are demonstrated in the fixture (§4, AC-7).

The scan window is **$FF80–$FFDF**, deliberately wider than §3's ownership claim of $FF90–$FF9F
and $FFB0–$FFBF. **A scanner narrowed to the ownership ranges would have been blind to POP's
`$FFA4`/`$FFA5` incident entirely** — the MMU task slots and the SAM speed pair sit outside both
ranges and are where the siblings' real contention lives. The PIA at $FF00–$FF7F is out of scope
and the tool's header says so, so the next reader knows it was decided rather than missed.

#### 3C — ★★ §2H's three checks, applied to reading POP's reports

1. **Is there a SECOND mechanism serving a different object class?** ★ **Yes, and it is the whole
   of §1's finding.** Registers are named two ways — **literal** (`sta $FFA6`) and **alias**
   (`sta CEL_MMU+2`) — and the alias class carries the majority of real accesses while containing
   no `$FF` at all. A tool seeing only the first is worse than useless because it is wrong in both
   directions at once. **And a third class was found by this task and is new: the register address
   loaded into a POINTER** (`ldu #$FFB0`), where one counted line stands for N indirect writes.
   That class is what made the per-file tables disagree, and it is a real limit on what any
   line-counting instrument can mean (§7.3).
2. **Name the routine that CALLS it, not only the one that implements it.** Decisive, and it is
   why the tool counts rather than judges. P5.17 §3C: `cel_bank_map` reads cold at its own line
   and is **per frame** at its caller `room_present`; `fh_quiet` is an opaque label until you know
   `fh_` is the FIRQ handler. **No hot/cold verdict is derivable from the line**, so the tool does
   not attempt one — it reports owners and leaves the caller analysis to a human. Encoding a
   hot/cold guess would have been the first-mechanism error in tool form.
3. **Grep the reports for the same subsystem before citing one.** ★ **This check is why this
   report is not wrong.** Citing P5.17 alone would have reproduced its per-file table as fact.
   Grepping the set surfaced **P5.19**, whose tool contradicts that table and agrees with this
   one — the later report winning **by evidence rather than by recency**, which is precisely the
   failure §2H.3 names. The contradiction had survived two reports and would have survived
   indefinitely.

#### 3D — Why the tool counts and does not gate

`reg_discipline.py` reports; it does not fail a build. **Zero is not the goal** and a gate implies
one. P5.17 measured **71% of POP's accesses as hot**, 23 of them inside the FIRQ handler where a
`jsr` at ~12–14 cycles would exceed the 7-cycle write it replaces — so a tool that failed on a
count would push work in the worst available direction. The census is the instrument the project
needs **now**, at zero engine files; POP's owner-row ratchet is the right *second* instrument and
is the natural P3-or-later follow-up (§8.1), once there are owners to ratchet.

`--expect N` exists so the tool can assert against an **externally supplied** figure and exit 1 on
mismatch — the AC-5 mechanism — with a message that says, in the tool's own voice, *do not tune
the tool to hit the number.* Verified in both directions (§4, AC-5).

#### 3E — `.gitignore`: three rules that are project invariants, not hygiene

`docs/ground-truth/*` with `!.gitkeep` (§2.2) — the directory exists on a fresh clone so a
`[ref: GIME-RM §N]` citation has a home, while the documents never push. `games/**` with narrow
manifest re-inclusions (§2P) — and **`games/manifests/kq3.vol` is still ignored**, verified in §4:
a VOL cannot be tracked even inside the manifests directory, which is the rule stated as
`.gitignore` rather than as a hope. `oracle/scummvm/`, `oracle/src/` (§2Q.1) — a vendored tree
starts feeling like source, and §2 says there is none.

#### 3F — Sibling claims, with ref and scope (§2S.3)

Every sibling figure in this report was measured at **POP `wip` `282a65c`** and **Karateka `wip`
`072ddcf`**, over the scopes named in §5's commands. **POP's 59 is measured over `src/` excluding
`src/hal/` AND `src/harness/`** — the second exclusion is required and the dispatch omits it
(§7.4). **Karateka's 8 is measured over `src/` excluding `src/hal/`**, no second exclusion needed
because Karateka has no `src/harness/`.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable]** — tree matches §5. `git ls-files` = **37 entries**: the 6 named
  files + 31 `.gitkeep`. Full listing in §5. ✅ **PASS.**
- **AC-2 [class: byte-comparable]** — `CLAUDE.md` committed byte-identical to the provided file.
  Working-tree SHA-1 `5e7d808ab77b174458da62945e769c95f0be7661`; **content of the committed blob,
  SHA-1 `5e7d808ab77b174458da62945e769c95f0be7661`** — identical. Blob id `a8d0c403…`. Not edited.
  ✅ **PASS.** (EOL note in §7.5.)
- **AC-3 [class: byte-comparable]** — `.gitattributes` identical to POP's **at both layers**:
  working-tree `diff` **empty, rc=0**, SHA-1 `d18574ce…` both sides; and blob `bc182e6157292d59311e68caf3b8ca99107df194`
  **equal to POP's `HEAD:.gitattributes`**. ✅ **PASS.**
- **AC-4 [class: byte-comparable]** — `.gitignore` contains `docs/ground-truth/*`;
  `git check-ignore -v docs/ground-truth/probe.txt` → `.gitignore:15:docs/ground-truth/*`, and
  `docs/ground-truth/.gitkeep` is **tracked** (`git ls-files` line 8, and `check-ignore -q` → 1).
  ✅ **PASS.**
- **AC-5 [class: byte-comparable] ★ THE GATE ON THE INSTRUMENT** — **59 over POP's `src/` excluding
  `src/hal/` and `src/harness/`, at `wip` `282a65c`.** Verbatim output in §5. `--expect 59` → rc=0;
  negative control `--expect 7` on the fixture → **rc=1** with the do-not-tune message, so the
  assertion is known to fail when it should. ★ **And the figure was corroborated at the level of
  the individual site, not the total: POP's own `register_owner_check.py` over the identical scope
  gives 59 access sites with `only POP's tool: 0 / only new tool: 0`.** ✅ **PASS.**
- **AC-6 [class: state-comparable]** — Karateka `src/` excluding `src/hal/`, at **`wip` `072ddcf`**:
  **8** — `bootloader.s` 2 (`$FF90`, `$FFA0`), `scene4_scroll.s` 6 (`$FF9D`, `$FFA2`).
  ★ **The count IS 8**, matching the figure the dispatch flagged as measured at an unstated ref, so
  no `wip`-vs-`main` drift is implicated here. ✅ **PASS.**
- **AC-7 [class: byte-comparable]** — all four parts demonstrated deciding, line by line, via
  `--explain`. Verbatim in §5. Cases: **P1** full-line comment naming `$FFA6` → rejected; **P2**
  `nop` with `$FFA4` only in the comment → rejected, *and* line 28 `sta $FFA6` whose comment names
  three further registers → **counted exactly once**; **P3** `CEL_MMU equ $FFA6` → rejected;
  **P4** `fdb $FFA2` (data) and `clra` (accumulator form) → both rejected. **Alias-with-offset:
  `sta CEL_MMU+2` → `$FFA8`, on a line containing no `$FF` at all.** ✅ **PASS** — with the
  fixture untracked, see §7.2.
- **AC-8 [class: byte-comparable]** — over `coco_agi`'s own `src/engine/**`: **0 accesses, rc=0**,
  clean report and no error. A non-existent root also exits **0** with *"no such path yet"*.
  ✅ **PASS.**
- **AC-9 [class: byte-comparable]** — `ALLOWLIST = frozenset()` at `reg_discipline.py:115`, a
  **frozenset of filenames, not a pattern**, with the comment above it stating it is empty on
  purpose and that a probe's path is added as its own line in the same commit as the probe.
  ✅ **PASS.**
- **AC-10 [class: suite]** — `seeds/AGI/{live,seed,incorporated,closed}` created in the pool,
  matching POP's folder shape; one row captured; `instance_count: 1` equals
  `len(instance_history)` (verified). Pushed `26f02a2..744af1e`. ✅ **PASS.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 — fresh tool output, verbatim.**

```
$ cd /c/Projects/POP3_port                                    # wip 282a65c
$ python .../reg_discipline.py --roots src --exclude src/hal src/harness --by-file --expect 59
[reg-discipline] scope: src  (scan $FF80-$FFDF, excluding src/hal, src/harness)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 59 register access(es) in 7 file(s) over 14 register(s).

  file                                     count  registers
  src/boot/loader.s                            3  $FFB0 $FFD8 $FFD9
  src/engine/char_draw.s                       6  $FFA6 $FFA7 $FFB0
  src/engine/cutscene_room.s                   4  $FFA6 $FFA7 $FFD8 $FFD9
  src/engine/intro_seq.s                      20  $FFA2 $FFA4 $FFA5 $FFA6 $FFA7 $FFB0 $FFD8 $FFD9
  src/engine/intro_splash.s                    1  $FFB0
  src/engine/msys_player.s                    23  $FF90 $FF91 $FF92 $FF93 $FF94 $FF95
  src/engine/tile_probe.s                      2  $FFA6 $FFD8
[reg-discipline] OK -- measured 59, matching the independent figure.
rc=0

$ cd /c/Projects/karateka_coco3                               # wip 072ddcf
$ python .../reg_discipline.py --roots src --exclude src/hal --by-file --expect 8
[reg-discipline] scope: src  (scan $FF80-$FFDF, excluding src/hal)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 8 register access(es) in 2 file(s) over 4 register(s).

  file                                     count  registers
  src/boot/bootloader.s                        2  $FF90 $FFA0
  src/engine/scene4_scroll.s                   6  $FF9D $FFA2
[reg-discipline] OK -- measured 8, matching the independent figure.
rc=0

$ cd /c/Projects/coco_agi                                     # wip 74d48fa
$ python harness/tools/reg_discipline.py --expect 0
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
[reg-discipline] OK -- measured 0, matching the independent figure.
rc=0
```

**★ AC-5's site-level corroboration — two independent implementations, identical scope:**

```
POP register_owner_check.py  : 59 access site(s), 27 owner row(s)
coco_agi reg_discipline.py   : 59 access site(s)

only POP's tool  : 0
only new tool    : 0
```

(27 owner rows = the baseline's 25 plus `tile_probe.s`'s 2, which POP allowlists and this scope
does not — consistent, not a discrepancy.)

**★ AC-7 — the four-part rule deciding, verbatim (`--explain`):**

```
[explain] aliases in scope: CEL_MMU=$FFA6, SAM_FAST=$FFD9

    3  P1            * P1 CASE: this whole line is a comment and it rejected -> P1 full-line comment
    4  P1            ;  P1 CASE (semicolon form): sta $FFB0 written rejected -> P1 full-line comment
    6  P3            CEL_MMU         equ     $FFA6           ; P3 C rejected -> P3 equ definition
    7  P3            SAM_FAST        equ     $FFD9           ; P3 C rejected -> P3 equ definition
   10  P2                            nop                     ; P2 C rejected -> P2 register only in the inline comment
   12  P4                            fdb     $FFA2           * P4 C rejected -> P4 no load/store/modify mnemonic
   14  P4                            clra                    ; P4 C rejected -> P4 no load/store/modify mnemonic
   18  ACCESS                        sta     $FFB0           ; COUN COUNTED  -> $FFB0
   19  ACCESS                        lda     $FF92           * COUN COUNTED  -> $FF92
   20  ACCESS                        sta     CEL_MMU         ; COUN COUNTED  -> $FFA6
   21  ACCESS                        sta     CEL_MMU+1       ; COUN COUNTED  -> $FFA7
   22  ACCESS                        sta     CEL_MMU+2       ; COUN COUNTED  -> $FFA8
   26  ACCESS                        stb     SAM_FAST        ; COUN COUNTED  -> $FFD9
   27  ACCESS                        clr     $FF9C           ; COUN COUNTED  -> $FF9C
   28  ACCESS                        sta     $FFA6           ; COUN COUNTED  -> $FFA6
```

Negative control on the same fixture: `--expect 8` → rc=0; `--expect 7` → **rc=1** with
*"★ EXPECTED 7, MEASURED 8 — the instrument and the independent figure DISAGREE. Do NOT tune the
tool to hit the number."*

**AC-1 — `git ls-files` (37 entries):**

```
.gitattributes  .gitignore  CLAUDE.md  README.md
harness/tools/reg_discipline.py         mame-idioms-coco3-port.md
content/.gitkeep                        dist/mame-cfg/composite/.gitkeep
dist/mame-cfg/rgb/.gitkeep              docs/ground-truth/.gitkeep
docs/project/.gitkeep                   games/manifests/.gitkeep
harness/lib/.gitkeep                    harness/scripted/.gitkeep
harness/smoke/.gitkeep                  harness/tmp/.gitkeep
harness/tools/.gitkeep                  link/.gitkeep
oracle/dumps/.gitkeep                   oracle/patches/.gitkeep
poc/.gitkeep                            reports/.gitkeep
src/boot/.gitkeep                       src/harness/.gitkeep
src/engine/{parser,picture,sound,storage,text,view,vm}/.gitkeep
src/opt/6309/.gitkeep                   src/opt/6809/.gitkeep
tests/scripted/.gitkeep
tools/imgbuild/.gitkeep                 tools/picdiff/.gitkeep   tools/volread/.gitkeep
```

**Sibling trees at report — POP tracked modifications: none.**

```
$ git -C /c/Projects/POP3_port status --porcelain | grep -v '^??'
(empty)
$ git -C /c/Projects/karateka_coco3 status --porcelain | grep -v '^??'
 M harness/smoke/last-run.log
```

★ Karateka's dirty file is **pre-existing and not this task's**: mtime **2026-08-11 20:28**, twelve
days before this session, and nothing here writes to a sibling. Stated rather than omitted.

**25.2 — bundled-artifact grep:** N/A — no build artifact produced this task.

**25.3 — operator-runtime-smoke:** N/A — no visual surface this task. Nothing was built, so there
is nothing for Jay to observe.

**HAL sync / register discipline gates:** N/A — no HAL file and no `src/engine/` source exists.

---

### 6 — Reactive deviations and route accounting

1. **`git init` was performed** — not listed in the dispatch, which assumes a repository. Required
   for every remaining AC.
2. **The remote was authored rather than verified** (§A.1). The specified check was unrunnable;
   what was done instead is recorded in full rather than reported as a pass.
3. **Part 4 of the rule follows P5.19's "load/store/modify"** over the dispatch's "load/store",
   per §8.3's own instruction that the primary source outranks the dispatch. §3B gives the reason.
4. **`src/harness/` is excluded from the AC-5 scope**, which the dispatch's scope statement omits.
   Without it the figure is 132, not 59 (§7.4).
5. **AC-7's fixture is not tracked**, to preserve AC-1 (§7.2).
6. **A `--expect` flag was added** beyond the dispatch's description of the tool, so the validation
   is executable and self-documenting rather than a number transcribed into a report by hand.

**ROUTE ACCOUNTING.** No alternative route was proposed to Jay or the Orchestrator during this
task, so there is no proposed-route/implementation gap to declare. What was built is §5's file
list plus the `git init` and the six items above; **nothing described in this report is
unimplemented**, and nothing was implemented that is not described here. **Explicitly NOT done, per
§12:** no `src/hal/`, no edit to any `hal_sync_check.py`, no `build.bat`, no ScummVM work, no
engine/tool/converter code, no game data, and **POP's `register_owner_check.py` was read but
neither copied nor ported** — §3B says why that mattered.

---

### 7 — Uncertainty flags

1. **`mame-idioms-addendum.md` is untracked and unruled-on.** It was already in the directory,
   is byte-identical to POP's, and **is not in the dispatch's §5 list** — while AC-1 gates on the
   tree matching §5 *exactly*. Tracking it would fail AC-1; deleting it would destroy something
   Jay placed there. It is therefore **left in the working tree, untracked**, and is the only line
   in `git status`. **Needs an Orchestrator ruling: track it, or is it POP-only?**
2. **AC-7's fixture lives in the scratchpad, not the repo** — same AC-1 conflict. Its output is
   reproduced verbatim in §5, but **the demonstration is not currently reproducible from a clone**,
   which is a real weakness in an instrument meant to outlive this session. Recommend a follow-up
   authorising `harness/tools/fixtures/rule_fixture.s`; the file exists and can be committed in one
   step on approval.
3. **★ The pointer-load class is a genuine limit on what any line-counting instrument measures.**
   `ldu #$FFB0` followed by N indirect writes counts as **one**. Both implementations agree on
   this, so the 59 is consistent — but the number is *"lines that name a register"*, not *"times a
   register is written"*, and those diverge wherever a pointer is used. **This has not been
   characterised for AGI**, whose 16-colour palette work will likely use exactly this idiom across
   16 entries rather than 4.
4. **The dispatch's AC-5 scope statement is incomplete.** "POP's `src/` excluding `src/hal/`" yields
   **132**; the 59 additionally requires excluding `src/harness/` (73 probe accesses, which P5.17
   counts separately). Reported rather than silently corrected.
5. **`CLAUDE.md` checks out CRLF, so a fresh clone's working copy is not byte-identical to the
   provided file** — the *blob* is (AC-2 verified at the blob layer). This is `* text=auto` in the
   inherited `.gitattributes`, which AC-3 requires verbatim, so **AC-2 and AC-3 can only both hold
   at the blob layer.** Flagged because a later `sha1sum` on a clone will not reproduce
   `5e7d808a…` and that will look like drift when it is not.
6. **A known limitation, recorded in the tool's own header:** P2 strips comments at `;` only, so a
   trailing `*` comment containing a register literal would be miscounted. **Measured, not
   assumed — it affects neither sibling** (zero such lines in POP's `src/boot` + `src/engine`), and
   POP's tool has the identical behaviour. It becomes live only if AGI adopts trailing `*` comments.
7. **P5.17 §3A's per-file table is wrong where its total is right** (§1). Not this project's
   artifact to correct; surfaced so POP can, and so no future AGI work cites that table.

---

### 8 — Follow-up candidates

1. **Port P5.19's owner-row ratchet to `coco_agi` when `src/engine/` has its first source file.**
   The census answers *how many*; the ratchet answers *did a new owner arrive without anyone
   deciding*, which is the question that actually caught `$FFA4`/`$FFA5`. It needs owners to exist
   first, so it is a P1+ task, not this one — but it should not wait until there are 59.
2. **Rule on §7.1 (the addendum) and §7.2 (the fixture's home).** Both are one-line decisions.
3. **Characterise the pointer-load idiom for AGI** (§7.3) before the palette code is written, since
   the 16-entry palette is where it will first bite.
4. **Consider whether `TC_MMU` and the pointer class belong in CLAUDE.md §2N's alias list** — §2N
   names five aliases and the primary source names six.
5. **POP-side:** correct P5.17 §3A's per-file table. Separate explicit task in POP per §2G, not an
   automatic back-port.

---

### 9 — User interaction during task

**None.** No question was put to Jay and no guidance was received. No consultation trigger fired —
§8.3 was evaluated against the primary sources and did not fire (§C).

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-08-23-a-matching-total-is-not-a-matching-measurement.md`

★ **First `seeds/AGI/` capture** — the four lifecycle folders were created to match POP's shape.
The principle: *agreement on the aggregate is not agreement on the measurement; two methods can
differ item by item and still sum to the same number, so a total that matches on the first try is
the moment to look harder rather than the moment to stop.* Captured at its first instance, as a
new single-instance `live` row, with `initiator: executor`.

★ **Schema note surfaced, not resolved:** the pool's frozen `SCHEMA.md` §4 enumerates
`executor | orchestrator | n/a | unknown`, while the existing corpus predominantly uses the
project-local names `clyde` (155) and `jay` (19) against `executor` (22) and `orchestrator` (9).
The schema-conformant value was used and the divergence noted in the row's prose body. **No
existing pool entry was read for content or edited** — §2C's new-rows-only rule was observed;
`SCHEMA.md` and one POP row were read for *format*, which is what §2C directs.

Pushed `26f02a2..744af1e`, fire-and-forget, non-blocking.

---

### 11 — Commit

`74d48fa3b1271aa7be32f2cd4f2595dd451fbe9d` — pushed to `origin/wip` before this report
(`* [new branch] wip -> wip`, to `github.com:Jsearle01/coco_agi.git`, confirming the canonical
underscore name). This report is a second commit on `wip`.
