## Form B Report — INFRA.1 new machine — prove the new laptop reproduces the recorded state

**Class:** recon. wip. Calibration-light — receipt stamp only.

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-09-05 (dispatch carried no explicit receipt timestamp; report written 2026-09-05T21:37:55-04:00).

| repo | branch | HEAD | tracked-modified | untracked |
|---|---|---|---|---|
| `coco_agi` | `wip` | `ecf7d5c9726c140afc5fd338358a2c8e821c921a` | 3 | 1 |
| `POP3_port` | `wip` | `104b1977eb9ef2b8c6849bcdba85e393a5e97ffc` | 0 | 20 |
| `karateka_coco3` | `wip` | `29f8f0ae8cf1ce75715b0e43b0ff7d1ff462866a` | 1 | 18 |
| `scummvm` | detached | `9d9b9e93108a276c551aeffa390169ccc5148e15` | 11 (the patches) | 1 |

**git status is NOT clean, and the dirt is load-bearing.** `coco_agi` carries three tracked
modifications that came across from the old machine and were already there before this task:
`src/harness/vm_probe.s`, `harness/tools/vm_sweep.lua`, `harness/tools/vm_ablate.ps1`. **These
explain AC-3's one anomaly entirely** (§3.C). `POP3_port` has zero tracked modifications — which is
consistent with AC-1 reproducing perfectly. `scummvm`'s eleven are the applied instrumentation
patches, expected (`2.9.1dirty`).

---

### 1 — Summary

The new machine reproduces the recorded state. **POP's six shipped DECB files and `probe.dmk` rebuild
byte-identical, and so do all 711 files `build.bat` writes; Karateka's production binary and all 1,222
`build/` files rebuild byte-identical; all five `coco_agi` gates pass from fresh builds at their recorded
figures; and fault-detectability was re-proven on two independent gates.** The dispatch's central
premise was wrong in a useful direction: **MAME, lwtools and MinGW-w64 were never absent** — they came
across inside `C:\Users\jayse\DEV`, at exactly the recorded versions. What was absent was *PATH and the
recorded directory layout*, which is a different problem with a different fix. Four figures did not
reproduce and are reported rather than fixed (§3.C, §3.D).

---

### 2 — Files modified

**No tracked file in any repo was edited by this task.** The environment was restored by
filesystem-level indirection instead, so that no sibling was adjusted to make a gate pass (trigger 1).

Environment changes (all reversible, none tracked):

- `C:\Projects\{POP3_port, coco_agi, karateka_coco3, agi-games, scummvm, pop-oracle-build, karateka_dissasembly_claude}` — directory junctions → `C:\Users\jayse\DEV\<name>`
- `C:\Projects\2600em\tools\mingw64` — junction → `C:\Users\jayse\DEV\mingw64` (X-32's vendored toolchain, at its recorded path)
- `C:\mame` → `C:\Users\jayse\DEV\mame`; `C:\WIN_LWTools` → the lwtools `build\bin`
- `C:\Users\jayse\DEV\mingw64\opt\bin\python.exe` — hardlink to the vendored `python3.11.exe` (the trees ship `python3.11.exe`; every build script invokes `python`)

Build outputs regenerated in place (gitignored): POP `build/` (711 files, byte-identical),
Karateka `build/` (1,222, byte-identical) and `tests/scripted/*.bin`, `coco_agi` `build/` gate
artifacts and sweep output.

★ **`coco_agi/build/vm_probe.bin` changed 8,800 B → 8,822 B.** It is not damage: the VM gate rebuilds
its own probe (L-70), and the working-tree `vm_probe.s` is modified relative to HEAD. See §3.C.

---

### 3 — Reasoning

#### A. The version file, and what it actually said

`C:\Users\jayse\DEV\toolversions.txt`, verbatim and read before anything was installed:

```
Found one MinGW toolchain — it's not on PATH.

Location: C:\Projects\2600em\tools\mingw64\ (bin at C:\Projects\2600em\tools\mingw64\bin)

Version: gcc 14.2.0, x86_64-posix-seh-rev1, MinGW-Builds (x86_64-w64-mingw32)
Includes: gcc.exe, g++.exe, cc.exe, mingw32-make.exe, gdb.exe/gdbserver.exe, ar, ld, ld.gold, windres, plus the x86_64-w64-mingw32-* prefixed drivers

PS D:\Projects\WIN_LWTools\lwtools-4.24\build\bin> lwasm --version
lwasm from lwtools 4.24

PS D:\Projects\mame> mame -version
0.281 (mame0281)
```

**Measured on this machine, before any install:**

| tool | recorded | measured | verdict |
|---|---|---|---|
| lwasm | `lwasm from lwtools 4.24` | `lwasm from lwtools 4.24` | **MATCH** |
| MAME | `0.281 (mame0281)` | `0.281 (mame0281)` | **MATCH** |
| gcc | `14.2.0 x86_64-posix-seh-rev1, MinGW-Builds` | `14.2.0 x86_64-posix-seh-rev1, MinGW-Builds` | **MATCH** |

**Trigger 4 does not fire.** Nothing was installed at a version other than the recorded one — nothing
needed installing at all. The recorded lwasm was already present, so AC-1 was run against it directly,
in the order the dispatch required (lwasm first, POP build immediately, everything else after).

#### B. X-32, a third time, and the fix that was NOT to edit anything

The dispatch asserted the three tools were "NOT installed." They were all present under `DEV`. **The
negative was inherited from the old machine's own record and re-asserted without enumeration** —
which is precisely what `scummvm.pin`'s `[host]` section already documents itself doing about the
MinGW toolchain, and what X-32 names. A recursive sweep of `DEV` found all three in one pass, plus a
**vendored Python 3.11.6** inside `mingw64\opt\bin` that made the whole Python surface work.

What was genuinely broken was **layout, not presence**: nothing on PATH, `C:\Projects\` non-existent,
and the old machine's `D:` drive absent. That matters because the trees hardcode the old paths in
**60+ files (search capped at 60)** — `cel_parity_rule.py` blocks POP's build on
`C:\Projects\POP3_port\oracle\source\...`, `vm_run.ps1` does `Set-Location C:\Projects\coco_agi` and
reads `C:\Projects\agi-games\pc`, `classify_corpus.py` defaults to three `C:\Projects\agi-games\*`
paths, `run_gates.sh` hardcodes `-rompath C:/mame/roms`, and **CLAUDE.md §1 binds the repos to
`C:\Projects\` as a project binding.**

So the repair was to **make the recorded layout true again with directory junctions**, not to edit 60
files. This respects trigger 1 ("do not adjust a sibling to match"), §11 ("reproduce the old machine,
not modernise it") and §2D (those paths live in authored docs), and it is the class the dispatch
explicitly excluded from consultation ("install paths, tool locations, environment setup").

#### C. The one gate anomaly, and why it is not a machine difference [trigger 2]

`gate_audit.py --verify` initially reported **7 of 8 artifacts identical and `vm` DIFFERS — shipped
8,800 B, fresh 8,822 B**, deterministic across two runs. Reported before any fix, per trigger 2.

It is not the toolchain, and the evidence is direct rather than inferential:

1. lwasm 4.24 reproduced **POP's 711 files and Karateka's 1,222 files byte-for-byte**. A toolchain
   difference does not land on one artifact out of 8/711/1222.
2. `git status` shows **`src/harness/vm_probe.s` is modified relative to HEAD** — uncommitted `wip`
   work carried over from the old machine.
3. **Decisive:** `git show HEAD:src/harness/vm_probe.s`, assembled on this machine with the manifest's
   flags, produces **8,800 B, sha256 `23703FEB…`, byte-identical to the shipped artifact.**

So the shipped 8,800 B binary *is* what HEAD builds here, and the 8,822 B figure is what the modified
working tree builds. **This is exactly the state POP's CLAUDE.md §2E predicts** — *"`wip` may carry
incoherent WIP; prod byte-identity is NOT guaranteed there"* — and all three repos are on `wip`. The
VM gate then passed 9/9 against that modified source (§4, AC-3), so the edit is live work, not rot.

★ **AC-1 and AC-2 were both verified on `wip` checkouts, where the byte-identity invariant is formally
not guaranteed.** They passed anyway, which is a stronger result than the invariant promises — but the
claim being made is *"this machine rebuilds what the old machine built from this tree,"* not *"`wip`
satisfies the `main` invariant."*

#### D. Figures that did not reproduce

**AC-8, all three repos, at the §2N-documented `src/engine/**` scope:**

| repo | recorded | measured | delta |
|---|---|---|---|
| `coco_agi` | 5 accesses, 2 registers, one sanctioned owner | **8** accesses, **2** registers, **1** owner (`src/engine/mmu_phase.s`, `$FFA5 $FFA6`) | **+3 accesses**; registers and owner MATCH |
| POP | 59 | **56** | **−3** |
| Karateka | 8 | **6** | **−2** |

Before calling this drift I checked it was not my own scope error (L-77 — the required set must be
produced, not assumed): whole-`src` gives 58 / 227 / 49, nowhere near the recorded triple, so
`src/engine` is the right scope and the recorded figures are the ones that moved. The tool is
stdlib-only and deterministic; this is source drift over time, not a machine effect.

**`oracle/scummvm.pin` is stale about its own patch set.** `[patches]` lists 0001–0005. The tree holds
**eight** — 0006-oracle-view-cel-dump, 0007-oracle-composited-frame-dump, 0008-oracle-room-jump — and
**all eight are applied** (verified per-patch by matching every added line against the target file;
0005's single deleted line is correctly absent). This is the second instance of the exact defect that
section documents about itself for patch 0004: *"found by re-reading this file against the tree rather
than trusting it."*

#### E. Python was never version-recorded, and it turned out not to matter

`toolversions.txt` names lwasm, MAME and MinGW — **not Python**, though `build.bat` requires it on PATH
and *silently degrades without it*: `[hal-sync] WARNING: python not found on PATH — HAL-sync check
SKIPPED`. Saying so is §2's requirement for an unnamed tool.

`scummvm.pin` `[host]` does record the old machine indirectly: **"Python 3.13 native."** This task ran
the vendored **3.11.6**. That is a real toolchain difference on a component that *writes bytes into
`probe.dmk`* — `raw_tracks.py`, `decb_to_raw.py`, `cel_link.py` are all in POP's build path. **AC-1
settles it empirically: `probe.dmk` is byte-identical, so the Python minor version did not reach the
artifact.** Flagged rather than assumed away, because the evidence is a measurement and not an argument.

#### F. The clock was measured, not printed [L-78, AD-100]

`p3b_run.lua` calibrates against markers 11/12 bracketing 160,009 guest CPU cycles. Measured here:
**1.789772 MHz**, 0.021% from the 1.789390 MHz hardware constant. This reproduces the figure in
`reports/20260904-160000-p3b-12-close-p3b.md` (*"clock MEASURED 1.789772 MHz (160009 cycles
calibrated)"*) to all six decimals. The harness's own history is the reason this AC exists — it once
printed `@ 1.789390 MHz` as a hardcoded string while the machine ran at half that.

#### G. Authority tiers

Every conclusion here rests on **fresh tool output on this machine** (25.1) — hashes, gate
adjudicator verdicts, `git` plumbing. No conclusion rests on ScummVM's behaviour, the AGI Specs, or a
comment, so §2.1's original-vs-normalisation split does not arise. §2H's three checks do not apply:
this task reads no oracle mechanism. §2S: the two sibling claims (POP's 711-file build, Karateka's
1,222-file build) were **rebuilt and hashed on this machine**, not cited from a prior report.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [class: byte-comparable] — PASS.** POP's six shipped DECB files and `probe.dmk` rebuild
  byte-identical; **all 711** files `build.bat` writes are identical to the pre-rebuild baseline
  (0 differing). Hashes in §5. Baseline captured *before* the first rebuild, so this compares against
  the old machine's bytes, not against itself. **Re-verified a second time after git was installed
  into the MinGW tree mid-task: still 711/711.**
- **AC-2 [class: byte-comparable] — PASS.** `build/karateka.bin` sha256
  `9CD20DC537415E80198DAB59C6573E3A75CF05E055E869EA63CB4C7547DD91EE`, identical to baseline; all
  **1,222** `build/` files identical. ★ *Partial:* `tests/scripted/*.bin` (159 files) had no pre-move
  baseline — Karateka's build writes there and I captured `build/` only. They were shown
  **build-to-build deterministic** (159/159 across two builds), which is weaker than AC-1's evidence
  and is stated as such.
- **AC-3 [class: byte-comparable] — PASS, per-gate, all five from fresh builds.**

  | gate | required | measured | built fresh |
  |---|---|---|---|
  | renderer | 45/45 | **45 PASS, 0 FAIL (of 45)**, both planes, 3 games | `pic_probe.bin` 2,642 B, source-tree `170021b8dc70` (13 files) |
  | cels | 9,193 | **9,193 / 9,193 (100.00%)**, 6 titles, 0 mismatch, 0 errors | per-title staged builds |
  | compositing | 20/20 | **20 frames: 20 identical, 0 divergent** (SpaceQuest-1) | `comp_probe.bin` 967 B, source-tree `fc0acf1d9f9f` |
  | VM | 9/9 titles | **9/9 PASS**, 600 cycles × 288 bytes each, **exclusion set EMPTY** | `vm_probe.bin` 8,822 B |
  | resources | 1,264 | **1,264 / 1,264 (100.00%)**, 10 volumes, 0 mismatch, 0 guestfail | `res_probe.bin` 2,019 B |

  ★ AC-3's wording says renderer **"45/45 windowed."** The 45/45 *correctness* gate is the `pic` row
  (`-DHAL_GFX_MODE_SERVICE`), which is what ran. Per `gates.manifest`/AD-96 the **windowed** build
  (`pic_win`, `-DPLANE_WINDOWED -DPIC_NOCOUNT`, 2,655 B) is a **timing** row, not the correctness
  gate — a different program. Its artifact rebuilds byte-identical, but no 45/45 was claimed from it.
- **AC-4 [class: byte-comparable] — PASS, on two independent gates.**
  - *Renderer:* `-DPIC_FAULT` + `PIC_FAULT_ON=Kingquest1-080` → **44 PASS, 1 FAIL**, the failure
    localised to exactly the armed picture, `DIFFERS 1 px, first (37,42)` — the documented injection
    offset (42·160+37 = 6757) — priority plane still identical, `picgate.py` **exit 1**.
  - *VM:* `VM_FAULT=1` → SpaceQuest-1 **FAIL**, 519 of 600 cycles divergent, first divergence cycle 77,
    vars [31,33,34,126,230,231,232,234,235].
  - ★ **Reportable:** under the same injected fault, **Kingquest1 still PASSED.** Fault-detectability
    is per-title, so a single-title spot check can be green while the fault is present — which is the
    scope-in-an-environment-variable disease `vm_run.ps1`'s own header documents.
  - ★ **A false alarm I raised and cleared:** my first attempt armed `PIC_FAULT_ON` without
    `-DPIC_FAULT` and the gate returned a clean 45/45. That reads exactly like trigger 3 ("a gate that
    can no longer fail"). It was my error — the injection is assemble-time and off by default *by
    design*, so a gate run cannot accidentally carry it. **Trigger 3 does not fire.**
- **AC-5 [class: suite] — PASS.** Corpus complete and byte-verified: **150 manifest rows, 150 `.zip`
  files, 150/150 sha256 IDENTICAL, 0 missing, 0 mismatched** against
  `games/manifests/agile-gdx-81c42ba.tsv` (matches the pin's "titles = 150"). `classify_corpus.py`
  reproduces the three-axis result **byte-identically** — fresh output and the recorded
  `corpus-classification.tsv` share sha256 `1458C42EBA7F6B5B6705D9AD1A14150619FA956CA146DB84A2576D92E49C20CA`
  (213 lines, identical line-for-line): rows=203, oracle-matched=161, PC/DOS 15, CoCo3 38, fan 150,
  dir_format v2=189 v3=6 none=8.
- **AC-6 [class: byte-comparable] — PASS, with one correction and one gap.** `git rev-parse HEAD` =
  `9d9b9e93108a276c551aeffa390169ccc5148e15` ✓. Patches **0001–0005 applied** ✓ (verified line-by-line,
  not by mtime). **It runs:** `ScummVM 2.9.1dirty (Aug 29 2026 16:46:33)`, features `RGB zLib ENet
  TinyGL`, exit 0. ★ Correction: **eight** patches exist and all eight are applied; the pin records
  five (§3.D). ★ Gap: **"and it builds" is NOT verified.** The binary is the one built on the old
  machine (Aug 29). A rebuild needs `./configure`/`make` under a POSIX shell; GNU Make 4.4.1 is
  present and `config.mk` survived (`BACKEND := null`, `ENABLE_AGI = STATIC_PLUGIN`), but the dry run
  failed on missing `git`/`cut`/`cat` before Jay installed Git. **Not retried after Git arrived** —
  see §7.
- **AC-7 [class: state-comparable] — PASS.** **MEASURED 1.789772 MHz (160,009 cycles calibrated)**,
  expected 1.789390, **0.021%**. Measured by calibration markers, not printed (§3.F).
- **AC-8 [class: state-comparable] — DOES NOT REPRODUCE.** `coco_agi` **8** accesses (recorded 5) —
  2 registers and the single sanctioned owner do match; POP **56** (recorded 59); Karateka **6**
  (recorded 8). Scope confirmed as the §2N-documented one (§3.D). Reported, not fixed (§11).
- **AC-9 [class: suite] — see §7.** "Nothing" is not the answer; eleven differences are listed.
- **AC-10 [class: suite] — BLOCKED.** `None.` — and not by choice: see §7.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output (verbatim).**

*AC-1 — POP's shipped set, fresh build vs pre-rebuild baseline:*
```
=== AC-1 SHIPPED SET ===
loop_probe.bin             IDENTICAL 1885B4D01F9166B9A0FA74886776909F608B849A0917D1F31E0732AA4F18381F
mode_probe.bin             IDENTICAL 11134E4E24EEE4E37E40FC17A370BFA284858FB9D373CACE4ECAFDE214100F68
anim_probe.bin             IDENTICAL 2CFA655C5E819A2C43D39E4224A485C3C49E8975C5D350165971CF1C99A4A005
intro_splash.bin           IDENTICAL 8295C4139A2EE0A311D17659ADC46A31BAB5F6759130961D32CB763812DD3073
loader.bin                 IDENTICAL 56BF6740440C4E0A13909F906EFBC2DC3608C7CA50EE4BB5E81BE9D760DC835B
tile_probe.bin             IDENTICAL 69C48C62B528C029F250E1950512A7ECA516AF8C979EC734C76D9EA951B133AE
probe.dmk                  IDENTICAL EC6DACCB0B78A9D52E0BFB2A08D567AFC0940DE4870FF41A2D88CEDE0F11E7A5

identical: 711
differing: 0
```

*POP `build.bat` tail — the six DECB files on the image, read back and compared:*
```
[hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared, EOL/guard/export-placement normalised)
...
 Contents of build\probe.dmk:
   PROBE.BIN     1269     2 B
   MODE.BIN      1332     2 B
   ANIM.BIN      1451     2 B
   INTRO.BIN    28145     2 B
   LOADER.BIN    1606     2 B
   TILE.BIN      1500     2 B
        6 File(s)  35303 bytes   0 bytes free
[reg-owner] OK — 25 owner row(s) over 14 register(s), 10 file(s) allowlisted.
[map_check] 6 map(s) clean — no overlap, nothing below $0E00, introseq.map all below $2700, scene.map linked at $2700.
#   file            on disk  artefact  verdict
  PROBE.BIN            1269      1269  ok
  MODE.BIN             1332      1332  ok
  ANIM.BIN             1451      1451  ok
  INTRO.BIN           28145     28145  ok
  LOADER.BIN           1606      1606  ok
  TILE.BIN             1500      1500  ok
# VERDICT: PASS - every file on the image matches its artefact.
=== BUILD COMPLETE ===
```

*AC-2 — Karateka:*
```
[hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared, EOL/guard/export-placement normalised)
--- Production binary ---
  build/karateka.bin (17978 bytes)
=== BUILD COMPLETE ===

build/ identical: 1222
build/ differing: 0
production binary: 9CD20DC537415E80198DAB59C6573E3A75CF05E055E869EA63CB4C7547DD91EE
baseline:          9CD20DC537415E80198DAB59C6573E3A75CF05E055E869EA63CB4C7547DD91EE
tests/scripted identical: 159  differing: 0   (build-to-build determinism only)
```

*§4's flag enumeration — the required set produced from `gates.manifest` and diffed against the tree
by rebuilding each entry and comparing BYTES [L-77, L-70, L-71]:*
```
gate   artifact                  shipped    fresh  verdict
------------------------------------------------------------------------
pic    build/pic_probe.bin          2642     2642  identical
pic_nc build/pic_nc_unpacked.bin     2512     2512  identical
pic_nc_pk build/pic_nc_packed.bin      2971     2971  identical
pic_win build/pic_v_windowed_nocount.bin     2655     2655  identical
res    build/res_probe.bin          2019     2019  identical
cel    build/cel_probe.bin          1436     1436  identical
comp   build/comp_probe.bin          967      967  identical
vm     build/vm_probe.bin           8822     8822  identical
```
Required flag sets, all confirmed by byte-match at the recorded sizes: `pic` `-DHAL_GFX_MODE_SERVICE`
(2,642) · `res` `-DHAL_GFX_MODE_SERVICE` (2,019) · `cel` `-DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK`
(1,436) · `comp` *no flags* (967) · `vm` `-DHAL_GFX_MODE_SERVICE -DHAL_SYS_FAST_CLOCK`.

*The vm delta, isolated to the working tree rather than the toolchain:*
```
HEAD-built : 8800 B  23703FEB5113100E9376AE7FB2D33D04C73F8537295485CDF006B42BBC1D1253
shipped    : 8800 B  23703FEB5113100E9376AE7FB2D33D04C73F8537295485CDF006B42BBC1D1253
*** IDENTICAL -- shipped artifact IS HEAD; delta = uncommitted wip edits ***
```

*AC-3 — the five gates:*
```
═══ renderer (45 pictures) ═══
  built build/pic_probe.bin from src/harness/pic_probe.s  [source-tree 170021b8dc70 (13 files)]
per-picture: 45 PASS, 0 FAIL, 0 with no output   (of 45)
games covered: 3  (Kingquest1=16, Kingquest2=15, Kingquest3=14)

═══ resources (1,264 fetches, 10 volumes) ═══
volume               requests  identical   mismat  guestfail
Kingquest1-v0              74         74        0          0
Kingquest1-v1             150        150        0          0
Kingquest1-v2              88         88        0          0
Kingquest2-v0              86         86        0          0
Kingquest2-v1             187        187        0          0
Kingquest2-v2             207        207        0          0
Kingquest3-v0             124        124        0          0
Kingquest3-v1              87         87        0          0
Kingquest3-v2             132        132        0          0
Kingquest3-v3             129        129        0          0
TOTAL                    1264       1264        0          0
resources byte-identical to tools/volread/: 1264 / 1264 requested (100.00%)

═══ cels ═══
title           queued decoded   match    mism   errors mirrored
Kingquest1         814     814     814       0        0      204
Kingquest2        1189    1189    1189       0        0      122
Kingquest3        1861    1861    1861       0        0      298
PoliceQuest1      2411    2411    2411       0        0      530
SpaceQuest-1      1728    1728    1728       0        0      224
larry1            1190    1190    1190       0        0      147
TOTAL             9193    9193    9193       0        0     1525
cels byte-identical to the oracle: 9193 / 9193 queued (100.00%)

═══ compositing ═══
  built build/comp_probe.bin  [source-tree fc0acf1d9f9f (8 files)]
frames: 20 from build/comp_stage/SpaceQuest-1
program 967 bytes at $0700
★ 20 frames: 20 identical, 0 divergent

═══ VM ═══
vm_probe: 8822 bytes
=== AC-2 SUMMARY ===
Kingquest1 PASS / Kingquest2 PASS / Kingquest3 PASS / SpaceQuest-1 PASS / SpaceQuest-2 PASS
PoliceQuest1 PASS / larry1 PASS / BlackCauldron PASS / MixedUpMotherGoose PASS
  (each: 600 cycles x 288 bytes, exclusion set EMPTY, divergent cycles 0 of 600)
```

*AC-4 — injected faults:*
```
FAULT ARMED on picture: Kingquest1-080  (build carries -DPIC_FAULT)
build/pic_probe_FAULT.bin  2655 bytes
Kingquest1-080   2   211  DIFFERS 1 px, first (37,42)   identical 98cdf968fe6321ca   ★ FAIL
per-picture: 44 PASS, 1 FAIL, 0 with no output   (of 45)
★ FAILING PICTURES (named, not counted):  Kingquest1-080 visual
--- picgate exit: 1 ---

FAULT INJECTED (-DVM_FAULT) -- this build is EXPECTED to fail AC-2
  cycle 77   1 difference(s): var 31 oracle=0 guest=44
divergent cycles : 519 of 600
first divergence : cycle 77
vars involved    : [31, 33, 34, 126, 230, 231, 232, 234, 235]
flags involved   : [35, 37, 38, 39, 168, 230]
AC-2 ★★★ FAIL
=== AC-2 SUMMARY ===
Kingquest1   PASS
SpaceQuest-1 FAIL
```

*AC-7 — the measured clock:*
```
clock MEASURED 1.789772 MHz (160009 cycles calibrated)
```

*AC-5 — corpus:*
```
manifest data rows: 150
corpus .zip files: 150
sha256 IDENTICAL : 150
MISSING          : 0
MISMATCH         : 0

[classify] detection table: 363 md5 keys, 369 entries
[classify] rows=203   oracle-matched=161   unmatched=42
  pop       rows  matched   volV2   volV3    vol??
  PC/DOS      15       11       9       0        6
  CoCo3       38       16       1      32        5
  fan        150      134     147       0        3
  dir_format:  v2=189, v3=6, none=8
recorded hash: 1458C42EBA7F6B5B6705D9AD1A14150619FA956CA146DB84A2576D92E49C20CA
fresh    hash: 1458C42EBA7F6B5B6705D9AD1A14150619FA956CA146DB84A2576D92E49C20CA
*** IDENTICAL line-for-line ***
```

*AC-8 — `reg_discipline.py`, §2N scope:*
```
[reg-discipline] scope: src/engine  (scan $FF80-$FFDF, excluding nothing)
[reg-discipline] allowlist: 0 file(s)  (empty -- no probes exist yet)
[reg-discipline] 8 register access(es) in 1 file(s) over 2 register(s).
  src/engine/mmu_phase.s      8   $FFA5 $FFA6

POP      : 56 register access(es) in 6 file(s) over 14 register(s).
karateka :  6 register access(es) in 1 file(s) over  2 register(s).
```

*§4 — `hal_sync_check.py`, all three repos:*
```
POP3_port      : [hal-sync] OK -- HAL source aligned with karateka_coco3, coco_agi (11 files compared)
karateka_coco3 : [hal-sync] OK -- HAL source aligned with POP3_port, coco_agi (11 files compared)
coco_agi       : [hal-sync] OK -- HAL source aligned with POP3_port, karateka_coco3 (11 files compared)
```

*AC-6 — the oracle:*
```
git rev-parse HEAD -> 9d9b9e93108a276c551aeffa390169ccc5148e15
0001-oracle-room-dump.patch                 graphics.cpp applied 31/31, graphics.h applied 5/5, picture.cpp applied 7/7
0002-oracle-vm-state-dump.patch             cycle.cpp applied 29/29
0003-oracle-row24-probe-and-lzw-trace.patch loader_v3.cpp applied 13/13, op_cmd.cpp applied 39/39
0004-oracle-raw-resource-dump.patch         agi.cpp applied 83/83
0005-oracle-deterministic-clock.patch       global.cpp applied 29/29 (removed-still-present 0/1), cycle.cpp applied 9/9
0006-oracle-view-cel-dump.patch             view.cpp applied 48/48, agi.cpp applied 35/35
0007-oracle-composited-frame-dump.patch     graphics.h applied 10/10, sprite.cpp applied 82/82, sprite.h applied 3/3
0008-oracle-room-jump.patch                 cycle.cpp applied 76/76

ScummVM 2.9.1dirty (Aug 29 2026 16:46:33)
Features compiled in: RGB zLib ENet TinyGL
```

**25.2 bundled-artifact grep:** N/A — this task imported no sibling artifact and committed no bundled
asset. The sibling *claims* it makes (POP's and Karateka's builds) were verified by rebuilding and
hashing on this machine rather than by importing anything (§2S).

**25.3 operator-runtime-smoke:** `N/A — no visual surface this task.`

---

### 6 — Reactive deviations and route accounting

1. **Environment restored by junction rather than by editing hardcoded paths.** The dispatch did not
   specify a mechanism; 60+ files and CLAUDE.md §1 itself bind `C:\Projects\`. Editing them would have
   modified two sibling repos to make a gate pass (trigger 1) and modernised rather than reproduced
   (§11). Junctions are reversible and touch no tracked file.
2. **`python.exe` hardlink** added beside the vendored `python3.11.exe`, because the scripts invoke
   `python`. A `python.bat` shim was rejected: `build.bat` calls `python` *without* `call`, so a batch
   shim would transfer control and never return — silently truncating the build.
3. **AC-6's "and it builds" was not attempted after Git arrived.** Time; and a ScummVM relink would
   overwrite the oracle binary that every gate baseline depends on. Stated as a gap, not as a pass.
4. **AC-2's `tests/scripted` baseline was not captured** before Karateka's first build. My omission —
   I snapshotted `build/` only. Substituted build-to-build determinism and labelled it as the weaker
   evidence it is.
5. **AC-4's first renderer injection was inert** (missing `-DPIC_FAULT`) and briefly looked like
   trigger 3. Diagnosed as my error against `pic_probe.s` before reporting; re-run correctly.

**ROUTE ACCOUNTING.** Mid-task I proposed, in conversation, to run the five gates plus AC-4 once Git
made a POSIX shell available. **That is what this report contains, in full.** I did *not* propose and
did not perform: a ScummVM rebuild, any fix to the four non-reproducing figures, or any commit/push.

---

### 7 — Uncertainty flags

**AC-9 — what differs from the old machine.** "Nothing" would have been the wrong answer:

1. **Everything lives under `C:\Users\jayse\DEV\`, not `C:\Projects\`** — and the old machine also used a
   **`D:` drive** (`D:\Projects\WIN_LWTools`, `D:\Projects\mame`) that does not exist here. Papered over
   by junctions; the underlying hardcoding is unchanged and will bite again on the next move.
2. **Nothing is on PATH.** Every run in this report supplied it explicitly.
3. **Python 3.11.6 (vendored) vs the recorded 3.13 native** — §3.E. No effect on AC-1's bytes.
4. **`git` was absent at task start**; Jay installed 2.55.0.windows.5 mid-task. **Its version is not
   recorded anywhere**, so it is an unpinned toolchain component going forward.
5. **Git was extracted directly into `C:\Users\jayse\DEV`**, merging PortableGit's own `mingw64\` tree
   into the MinGW-Builds toolchain directory. ★ Verified non-destructive: gcc still 14.2.0, vendored
   Python still 3.11.6, `build-info.txt` intact, **and POP re-verified 711/711 afterwards.** But the
   two toolchains now share one directory and a future reinstall could shadow a compiler binary.
6. **`methodology-candidate-pool` is absent** — §2C's sibling repo did not come across. ★★ **RESOLVED
   at P4.7:** cloned with a PAT Jay supplied and junctioned to `C:\Projects\methodology-candidate-pool`.
   ★ It was never unpopulated — `seeds/AGI/` holds **105 live rows** (POP 205, karateka 114,
   claude-bridge 48, cocobots 29); it was unreachable, which is a different fact.
7. **No SSH keys** in `%USERPROFILE%\.ssh`, and all three remotes are `git@github.com:` — **no push is
   possible**, so §2E's push-before-report cannot be honoured. ★★ **PARTLY RESOLVED at P4.7:**
   `coco_agi`'s remote was switched to HTTPS and **push works with a PAT**; the pool likewise. The SSH
   diagnosis was right but incomplete — `Host key verification failed` fired *first* (no `known_hosts`
   at all) and masked the real `Permission denied (publickey)` underneath. **POP3_port and
   karateka_coco3 are still SSH with no key and still cannot push.**
8. **`docs/ground-truth/` is populated in POP and Karateka** (GIME reference, MC6809 manual, WD177x,
   the Unravelled series) and **empty in `coco_agi`** — matching §2G, so this is the recorded state
   rather than loss.
9. **`NoDefaultCurrentDirectoryInExePath=1`** is set in this shell, so `build.bat` is not found from
   its own directory; every invocation needed `.\build.bat`.
10. **MAME's `roms/` holds only `coco3.zip` and `coco3h.zip`** — sufficient for every gate here.
11. **`agi-games` is not a git repo** (correct per §2P) — 847 files, 150 `.zip`, all sha256-verified.

**Open, and blocking nothing in this report:**

- **AC-6's "it builds" is unverified** (§4). The pieces are now present (Git, bash 5.3.15, Make 4.4.1,
  `config.mk`); it was not retried. **Recommend proving it before any task depends on regenerating an
  oracle dump**, and note the pin's two local build steps (`windres` for `dists/scummvm.o`, and
  `win32_wrapper.o` built *through make*) must be re-run after any clean configure.
- **`karateka_coco3/harness/smoke/last-run.log` is modified** and I cannot say whether my build did it
  or it arrived that way — I had no `git` when I built Karateka. Low stakes (a log), stated for honesty.
- **AC-8's three figures and the pin's patch list are drift I did not touch** (§11). The Orchestrator
  folds; §10 of the dispatch is `None.` by design.
- **`coco_agi` carries uncommitted `wip` work** on `vm_probe.s`, `vm_sweep.lua`, `vm_ablate.ps1` from
  the old machine. It is coherent enough that the VM gate passes 9/9 against it. ★★ **CORRECTED at
  P4.7:** the claim that it was *"unpushed and exists on exactly one disk"* was **wrong**. The work was
  committed and pushed from the old laptop as **`ec86b83`** at 19:17 that same day, byte-identical to
  what is here; this machine's copy was simply taken before that push. **The error was reading
  `git rev-parse origin/wip` — a local cache of the last fetch — as a fact about the remote, in a clone
  that had never been fetched.** See P4.7 §4.

**Nothing here fires triggers 1, 3 or 4.** Trigger 2 fired and is resolved to a working-tree edit
(§3.C). Trigger 5 fires on the candidate pool (below).

---

### 8 — Follow-up candidates

1. **T-P0-045's check repair is unblocked** — AC-1 and AC-3 both pass, which was its precondition.
2. **Re-pin the oracle record:** `scummvm.pin` `[patches]` must list 0006–0008 (§3.D). Orchestrator-owned
   text (§2D).
3. **Reconcile AC-8's three figures** against the current trees, or record why they moved.
4. **Prove the ScummVM native rebuild** on this machine (AC-6's gap).
5. **Restore the candidate pool and SSH credentials**, without which §2C and §2E are both inoperable.
6. **Consider making the hardcoded roots configurable** — one env var per root would have made this task
   a five-minute job instead of a junction farm. Deliberately NOT done here (§11).

---

### 9 — User interaction during task

1. Jay interrupted an early listing with *"try again i just dropped it"* — `toolversions.txt` had just
   been placed in `DEV`; re-listed and read it before proceeding.
2. Jay interrupted a `git status` call and asked for a progress check; I reported status mid-task.
3. Jay said *"i installed git in DEV"* mid-task. I located it, **verified the MinGW toolchain survived
   the merge**, and used it for §4's git checks, the vm HEAD isolation, and the four shell-driven gates.
4. Jay authorised continuing with the gates and AC-4 (*"yes"*).

### 10 — Candidate(s) captured this task

`None.` at the time — **trigger 5, not a nil result.** `methodology-candidate-pool` had not come across
and no credential existed to fetch it. §2C's fallback is to **STOP and ask Jay**, and creating `seeds/`
inside `coco_agi` is worse than a lost reference — so no shadow pool was created.

★★ **RESOLVED at P4.7:** Jay supplied a PAT, the pool was cloned, and its `seeds/AGI/live/` proved to
hold **105 rows** already. **The two rows owed by THIS task remain owed** — P4.7 pushed its own three
(commit `92c10f3`) but not these:

- **the inert-fault false alarm** — an injection that is off by default reads exactly like a gate that
  cannot fail; arm-and-verify before concluding (§4, AC-4).
- **"a negative about the environment survives a machine move"** — X-32's third instance, where the
  dispatch itself carried the stale negative. ★ **Now due a fourth instance from P4.7**, and a sharper
  one: a negative asserted from the single local source that could not falsify it.

### 11 — Commit

**No code commit — no tracked source file was modified by this task** (§2), so there is nothing of the
task's own work to stage under §2E's explicit-path rule.

★ **CORRECTED.** This section originally added *"push is impossible regardless — no SSH key exists for
the `git@github.com:` remotes"*. **Push is possible**: at P4.7 `coco_agi`'s remote was switched to HTTPS
and a PAT authenticates. **This report is committed and pushed to `origin/wip`** alongside P4.7's, staged
by explicit path, so §2E's push-before-report is honoured and the Orchestrator can fetch it normally.
The two remaining siblings still cannot push (§7.7).
