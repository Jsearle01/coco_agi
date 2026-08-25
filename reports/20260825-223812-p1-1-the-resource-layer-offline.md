## Form B Report — T-P0-005 — P1 begins: the resource layer, offline
**Class:** build. wip.

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-25T22:38:12Z. HEAD at receipt `c819283` (wip) → **at report `38e458f`**, pushed.
`git status --porcelain` at report → one staged manifest, committed with this report.

---

## ★ §3 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

```
coco_agi        branch wip   HEAD c819283fc08b2ae92669a5be9af4cfdfc51e3161  (at receipt)
POP3_port       branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3  branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
```

Sibling refs **unchanged since T-P0-001** (§2S.3).

| check | measured |
|---|---|
| `oracle/scummvm.pin` | commit still **`9d9b9e93`**; WSL build clone at that commit, binary present, 8 oracle symbols linked, **rebuilt and runnable** |
| `games/manifests/` | `agile-gdx-81c42ba.tsv` 150 games · `coco3-images.tsv` 80 images · `coco3-files.tsv` 1,311 rows. **Both corpora present.** |
| `harness/tools/os9fs.py` | ★ **Already exposes file CONTENTS**, not only sizes: `read_file(lsn)` at `os9fs.py:201` returns `(bytes, short_flag)`. **No extension was needed and §8.3 did not fire.** |

★★ **DESIGN v0.5 WAS NOT PROVIDED.** §2 describes it as provided and lists its four supersessions,
but no file was dropped and none exists in the tree or `docs/project/`. **AC-1 is BLOCKED**;
nothing else depends on it, so the task proceeded (§8.5 could not fire — there is no file to
check). See §7.1.

---

### 1 — Summary

★★★ **AC-5 — THE GATE — PASSES: 2,410 resources, 2,410 byte-identical, 0 different**, across
**eight games and two corpora**, diffed against the pinned ScummVM's own loaded bytes. That is
the only AC that tests the parser against something that did not come from us (§2O.1), and it is
the only reason to believe any other number in this report.

★★ **It first read 0 of 299, and the fault was MY INSTRUMENT, not the parser.** I assumed
ScummVM's `RESOURCETYPE_*` enum ran `0..4` beginning at logic; it actually begins at **1** in a
different order (`LOGIC=1, SOUND=2, VIEW=3, PICTURE=4`, `agi.h:171-174`). Every dump was
mislabelled and I was comparing our PICTURE against their VIEW. **Reading the enum instead of
assuming it took it to 1146/1146** (§3C).

★★ **The CoCo3 corpus turns out to be almost entirely out of scope, for a documented reason.**
Six of seven titles — and five of KQ3's six variants — have **V2 directories but V3 VOLUMES**
(7-byte headers, LZW). ScummVM's own comment names the cause: *"Fan ports of DOS games to CoCo3
use V3 volumes; presumably they used the Leisure Suit Larry interpreter."* **`KQ3/Original` is
the single V2-volume build in the whole CoCo3 corpus**, exactly as that comment predicts (§3D).
That is a §8.2 finding and it bounds AC-9.

★ **Jay's PC drop arrived mid-task and is ingested** — ignore-hardening pushed first, 216/216
CRC-verified, archive deleted, nothing in tree or history (§3F).

★ **The Orchestrator's ~98%-differ figure evaporates, and the reason is now known** (§3G).

**Seven AC pass, one is bounded by scope, one is blocked, one partial.**

---

### 2 — Files modified

Explicit-path staging (§2E). Three commits.

**`e874155` — ignore hardening, before the PC drop**
- `.gitignore` — `.EXE/.COM/.OVL/.DRV/.SYS`, `.QA/.MSG/.SCR/.HLP/.GIF`, and **SCI
  `RESOURCE.MAP`/`RESOURCE.NNN`**. ★ `*.bat` deliberately **not** ignored (§6.3).

**`38e458f` — the resource layer**
- `tools/volread/{__init__,dirfile,volume,resource,logic,inventory,words,corpus}.py` — **new.**
- `harness/tools/seam_check.py` — **new**, AC-8's instrument.
- `oracle/patches/0004-oracle-raw-resource-dump.patch` — **new**, 60 inserted lines.

**this commit**
- `games/manifests/pc-agi.tsv` — **new**, 6 rows.

★ **No game data, game text, resource bytes or renderings are in the repository.** Corpora at
`C:\Projects\agi-games\{agile-gdx,coco3,pc}`. **No sibling repository was modified.**

---

### 3 — Reasoning

#### 3A — The format came from the oracle, not the Specs

§7 and CLAUDE.md §2 rank ScummVM (tier 3) above the AGI Specifications (tier 4, *"known
incomplete in places"*). Every field below was read at the pin rather than recalled:

| fact | source |
|---|---|
| DIR: 3 B/entry, `volume = b0>>4`, `offset = BE24 & 0xFFFFF`, empty = `0xFFFFF` | `loader_v2.cpp:31-68`, `agi.h:88` |
| VOL v2: 5-byte header, `0x1234` **BIG**-endian sig, length **LITTLE**-endian at +3 | `loader_v2.cpp:134-176` |
| LOGIC: `u16` bytecode size, then count / size / offsets / strings | `logic.cpp` `decodeLogic` |
| XOR: `mem[i] ^= "Avis Durgan"[i % 11]`, **strings region only** | `global.cpp:311-316`, `agi.h:92` |
| OBJECT: encrypted iff `LE16(mem) > flen`; `numObjects = LE16(mem)/3` | `objects.cpp:28-78` |
| WORDS.TOK: 26 **BIG**-endian offsets, prefix-compressed, chars `(c ^ 0x7F) & 0x7F` | `words.cpp:84-125` |

★★ **Three details are silent when wrong and would never have been guessed right:**
1. **LOGIC message offsets are relative to `messageSectionPos + 1`** — not the section start,
   not the resource start. Off by one yields *plausible text, shifted*, which no eyeball catches.
2. **Mixed endianness inside one 5-byte VOL header** — big-endian signature beside a
   little-endian length.
3. **WORDS.TOK offsets are BIG-endian** amid an otherwise little-endian format, and its
   prefix compression is incremental, so one bad length corrupts every later word in that
   letter's run with nothing to resynchronise on.

#### 3B — The seam is real, and its instrument caught me

Design §4.2a separates finding a resource from decoding it. `dirfile.py` yields
`(volume, offset)`; `volume.py` takes the header length as a **parameter, not a branch**;
`resource.py` is the only module that knows a version.

★★ **`seam_check.py` uses AST, not grep, and §2N is why.** §2N's four-part rule exists because
a literal grep over POP counted **comments** and missed **aliases** — wrong in both directions
at once. The identical trap is here: these modules are thick with the words "v2" and "v3" in
prose, and a regex would flag every one. So a line counts only if it is **code** (comments and
docstrings are invisible to `ast`) and only if a version token appears in a **conditional**.

★★★ **It found a real violation in my own code on its first run** — `inventory.py:72` carried
`spos = PAD_SIZE if version >= 0x2000 else 0`, mirroring `objects.cpp:57`. **Fixed by
parameterising `spos`, not by allowlisting the file.** An allowlist entry would have been the
cheap move and would have hollowed out the rule the same day it was written. Verified in both
directions: a deliberately injected branch in `volume.py` was caught, and removing it returned
the check to green (§5).

#### 3C — ★★ AC-5 read 0/299 first, and the instrument was at fault

The gate's first run reported **0 of 299 matching**, with LOGIC producing no oracle dumps at all
and lengths uncorrelated. **§8.1 forbids adjusting the parser to match**, so it was diagnosed
instead — and the fault was mine:

```
agi.h:171-174   RESOURCETYPE_LOGIC = 1,  SOUND = 2,  VIEW = 3,  PICTURE = 4
my patch        kNames[] = { "logic", "object", "view", "picture", "sound" }, indexed from 0
```

So LOGIC was written as `oracle_object_*`, and our PICTURE was compared against files holding
VIEW data. **The enum does not start at zero and is not in the obvious order.** Corrected to
`{ "other", "logic", "sound", "view", "picture" }` and the gate went to 1146/1146.

★★ **The generalisable half: a RED gate says nothing about the thing under test until the
instrument itself is verified.** This is the fifth instrument defect in this project and the
same family as P0.4's three — I had the enum available to read and asserted it instead.

#### 3D — ★★★ §2H's three checks, and the finding that bounds AC-9

1. **Is there a SECOND mechanism serving a different object class?** ★★ **Yes, and it is the
   task's largest finding.** "Is this game v2?" is **two independent facts** — v2 *directories*
   and v2 *volumes* — and a game can be v2 in one and v3 in the other. My first loader tested
   only the DIR shape, which answers the wrong half. The oracle documents the case at
   `loader_v2.cpp:61-71`:

   > *"The CoCo3 version of Leisure Suit Larry uses a V3 volume, even though it is a V2 game
   > with V2 directory files. Sierra's other CoCo3 release, King's Quest III, uses regular V2
   > volumes. Fan ports of DOS games to CoCo3 use V3 volumes; presumably they used the Leisure
   > Suit Larry interpreter."*

   **Measured against the media, that prediction holds exactly:** of 38 CoCo3 variant
   directories, **`KQ3/Original` alone uses V2 volumes**; `LSL/Original` is V3, as stated; every
   fan port is V3. CoCo3 KQ1 `vol.0` reads `len=8950, clen=5960` — a 7-byte header with real
   compression — against PC KQ1's 5-byte `len=8999`.
2. **Name the routine that CALLS it.** ★ Decisive for how the check is written. My first
   v3 test was my own heuristic — "does a plausible `clen` sit at +5?" — which classified
   **every** CoCo3 title as v3 including ones where `len == clen`, and could not fail. The
   oracle's `detectV3VolumeFormat()` instead walks **ten consecutive records** and requires each
   to land where the previous one's `clen` says it will. **A wrong assumption desynchronises
   within a record or two, so ten in a row is a test that CAN fail** — L-23 exactly. Replaced
   mine with the oracle's.
3. **Grep prior reports for the same subsystem.** P0.4 §3D found KQ3's `Original` differs from
   its five repacks (M-11: two builds). **This task explains the mechanism** — the repacks are
   V3-volume, the Original is V2 — and the two findings agree without either being adjusted.
   P0.4 §3A's tier-2 scoping likewise survives, now with ScummVM's own attribution behind it
   (§3E).

#### 3E — ★ ScummVM independently confirms P0.4's tier-2 scoping, and names the porter

Prompted by Jay's question about shared md5s, each CoCo3 image's `logDir` was hashed and looked
up in ScummVM's detection table (`GAME()` hashes exactly `logdir`, `detection_tables.h:122`):

| title | variants matched | ScummVM's own attribution |
|---|---|---|
| **KQ3** | **1 of 6 — `Original/KQ3-1-1.DSK` only** | ★ **"Official port by Sierra"** |
| **LSL1** | **6 of 6, including `Original`** | ★ **"Official port by Sierra"** |
| KQ2, KQ4 | 6 of 6 | *"Unofficial port by Guillaume Major"* |
| KQ1, KQ6, PQ1 | 0 | not catalogued |

★★ **Jay's hypothesis — that CoCo3 KQ1 shares an md5 with DOS KQ1 — is NOT supported.** ScummVM's
CoCo3 entries are separate from its DOS entries with different md5s. The ports rebuilt their
DIRs, which they must: resources were re-laid-out for CoCo3 media, so `logdir` cannot match even
if content did. ★ **The check produced something better than it was aimed at:** an independent
confirmation of P0.4 §3A's official/unofficial split, from a third party, with the porter named.

★ It also corroborates M-11 from a new direction — KQ3's `Original` hashes differently from all
five repacks (two builds), while LSL's repacks preserved its `logdir` byte-for-byte (one build).

#### 3F — The PC ingest, and the ordering that made it safe

Jay's note arrived mid-task. **Ignore-hardening was committed and pushed at `e874155` BEFORE
telling him it was safe to drop** — the P0.4 ordering, for the P0.4 reason: game data pushed to
a public repository cannot be deleted.

★ **Verified before extending rather than assuming**: the AGI resource names (`LOGDIR`, `VOL.n`,
`WORDS.TOK`, `OBJECT`) were **already** covered by the uppercase rules from `1edff3e`. What was
not: Sierra's binaries, shipped text and art, and **SCI `RESOURCE.MAP`/`RESOURCE.NNN`** — out of
scope (design §1.1) is not the same as safe to commit.

216/216 members CRC-verified **before** the archive was deleted — the last moment the source
existed to check against. Three AGI v2 directories, three SCI (recorded in the manifest with
`shape=SCI`, **not parsed**).

#### 3G — ★★ The ~98% figure: what it was

Jay's note flags an Orchestrator observation — *"~98% of bytes differ within same-length
resources"*, with *"matching byte islands at identical offsets"* — at **LOW confidence**, asking
whether AC-5 shows the header parse wrong.

**It does not show the parse wrong. It shows the parse is right — for V2 volumes.** And that is
the answer: **the example title, CoCo3 KQ1, is a V3-volume build** (§3D). Reading a 7-byte,
LZW-compressed record with a 5-byte header produces exactly the described signature — garbage
with coincidental islands at fixed offsets, no common prefix or suffix.

★ **So the figure evaporates, and not for the reason anticipated.** The header parse is correct
where it applies and was applied where it does not. ★ **The measured comparison, for the one
title where both sides are readable** (§5), finds only **3** same-length-but-differing resources
out of 440 — the overwhelming majority differ in **length**, a much simpler story than a
transform. **I have not carried the 98% forward.**

#### 3H — Refs and scopes (§2S.3, L-24)

Oracle citations at **`9d9b9e93` (v2.9.1)**. Corpora at **`agile-gdx@81c42ba`**, the CoCo3 drop,
and the PC drop (`Kingquest_zip.zip`, sha256 `7051d7c9…`). Sibling figures at **POP `wip`
`282a65c`** / **Karateka `wip` `072ddcf`**. ★ Every CoCo3 row names its **variant**, never just
the title.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] — ❌ BLOCKED.** Design v0.5 was not provided (§3 grep, §7.1). No file
  exists to check, so §8.5 could not fire. **Nothing else in the task depended on it.**
- **AC-2 [byte-comparable]** — `coco_agi` **0**, POP **59** at `282a65c`, Karateka **8** at
  `072ddcf`; fixture demo rc=0 with its negative control. ✅ **PASS.**
- **AC-3 [byte-comparable]** — DIR enumeration for **10 games across three corpora**, every
  resource as `(type, index, volume, offset)`. ★ **Slot cross-check against P0.3/P0.4 manifests
  agrees exactly** — e.g. CoCo3 KQ1 `logDir` 315 B → 105 slots, matching the manifest's
  `log_slots` 105; PC KQ3 `picturedir` 177 slots both sides. **No disagreement, so §8.4 did not
  fire.** ✅ **PASS.**
- **AC-4 [byte-comparable]** — every LOGIC/PICTURE/VIEW/SOUND extracted for the readable games:
  **PC 1,264 resources / 1,461,234 B**; fan corpus 1,146. ★ **4 resources overrun their volume
  and are REFUSED, not truncated** — PC KQ1 SOUND 34-37 point to 0x20E2F in a 90,891-byte
  volume. **Dangling entries in the game's own SNDDIR, not a parser fault** (§7.4). ✅ **PASS.**
- **AC-5 [state-comparable] ★★★ THE GATE** — **2,410 compared, 2,410 byte-identical, 0
  different**, across 8 games and two corpora, against the oracle's own pre-decode buffer.
  Verbatim in §5. ✅ **PASS.**
- **AC-6 [byte-comparable]** — message section located, `Avis Durgan` XOR applied, messages
  recovered for **3 games** (PC KQ1/KQ2/KQ3): **1,526 / 1,511 / 2,246 messages**. ★ **Evidenced
  by a discriminating check, not an assertion**: printable-ratio is **100.0% with the XOR and
  47.2% without**, so a pass proves the key was applied and applied correctly. **No message text
  is printed** (§2P). ✅ **PASS** for the PC corpus; CoCo3 is V3-bound (§7.2).
- **AC-7 [byte-comparable]** — `OBJECT` and `WORDS.TOK` parsed for **10 games** including all
  seven CoCo3 titles (both files sit outside the volumes and are readable even where the volumes
  are not). PC: 27/85/55 objects, 495/528/959 words, all at **100% plausibility**; every OBJECT
  detected as encrypted. ⚠️ **PASS at 10 games, short of AC-7's "≥5" only in the sense that the
  oracle cross-check is indirect** — ScummVM does not dump its parsed word list, so the
  comparison is against plausibility ratios rather than the oracle. **Stated rather than
  claimed as oracle-verified** (§7.5).
- **AC-8 [state-comparable]** — `harness/tools/seam_check.py`, **AST-based, not grep** (§3B).
  **0 version branches outside `resource.py`**; 3 inside, which is the point. ★ **The check that
  I used is stated and is executable**, and it caught a real violation of mine on first run.
  Negative control verified. ✅ **PASS.**
- **AC-9 [suite]** — runs against **three** corpora, not two: fan directories, CoCo3 OS-9 images
  (mixed-case `logDir` handled), and the new PC/DOS directories. **Per-corpus: fan 5/5 parsed,
  PC 3/3 AGI dirs parsed, CoCo3 1 of 38 variants parsed.** ⚠️ **BOUNDED BY A REAL FINDING, not
  by a parser limit** — 37 of 38 CoCo3 variants are V3-volume and out of scope (§3D, §7.2).
- **AC-10 [suite]** — §10.

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1a — the superset diff (AC-1):** **N/A — design v0.5 was not provided** (§7.1).

**25.1b — `reg_discipline.py` ×3 (AC-2), verbatim:**

```
coco_agi  src/engine/**                    [reg-discipline] OK -- measured 0   rc=0
POP       src/ less src/hal,src/harness    [reg-discipline] OK -- measured 59  rc=0
Karateka  src/ less src/hal                [reg-discipline] OK -- measured 8   rc=0
run_rule_demo.sh                           rc=0  (incl. the --expect 7 negative control)
```

**25.1c — ★★★ AC-5, THE GATE. Fan corpus (agile-gdx@81c42ba):**

```
game       type        ours oracle  match differ
abrah      LOGIC        130    130    130      0
abrah      PICTURE      117    117    117      0
abrah      VIEW          77     77     77      0
goutsq     LOGIC/PIC/VIEW 14/6/12  all matched, 0 differ
herbao     LOGIC/PIC/VIEW 14/7/16  all matched, 0 differ
starco     LOGIC 91 · PICTURE 94 · VIEW 179 · SOUND 17   all matched, 0 differ
kq2bi      LOGIC 99 · PICTURE 78 · VIEW 157 · SOUND 38   all matched, 0 differ

  LOGIC     matched   348   differed 0   IDENTICAL
  PICTURE   matched   302   differed 0   IDENTICAL
  VIEW      matched   441   differed 0   IDENTICAL
  SOUND     matched    55   differed 0   IDENTICAL
  TOTAL compared 1146 · byte-identical 1146 · DIFFERENT 0 · parser errors 0
```

**PC/DOS corpus (detected by the oracle as `agi:kq1`, `agi:kq2`, `agi:kq3`):**

```
Kingquest1   LOGIC 90 · PICTURE 82 · VIEW 118 · SOUND 22    all matched, 0 differ
Kingquest2   LOGIC 133 · PICTURE 108 · VIEW 207 · SOUND 32  all matched, 0 differ
Kingquest3   LOGIC 125 · PICTURE 97 · VIEW 216 · SOUND 34   all matched, 0 differ

AC-5 (PC/DOS)  compared=1264  identical=1264  different=0  parser-errors=4
   Kingquest1 SOUND 34-37: VOL.2 header at 0x20E2F.. runs past end (90891 bytes)
```

★ **COMBINED: 2,410 compared, 2,410 byte-identical, 0 different.**

★ **The first run of this gate read 0 of 299** — my type-name mapping, not the parser (§3C).

**25.1d — AC-8, the seam check, both directions:**

```
[seam] scanned 8 file(s) under tools/volread
[seam] sanctioned owner(s): tools/volread/resource.py
  version branches INSIDE the seam (expected, and the point): 3
      resource.py:63 · resource.py:195 · resource.py:216
  ★ version branches outside the seam: 0
[seam] OK -- the §4.2a seam holds.                                          rc=0

first run, before the fix:
  ★ VERSION BRANCHES OUTSIDE THE SEAM: 1 -- THIS IS A FAILURE
      tools/volread/inventory.py:72  version  [VERSION BRANCH]      rc=1

negative control (branch injected into volume.py):
      tools/volread/volume.py:32  v3, version  [VERSION BRANCH]     caught
```

**25.1e — AC-6, the discriminating check (no game text, §2P):**

```
game (image/variant)                      msgs    XOR on   XOR off   verdict
PC/DOS Kingquest1                         1526    100.0%     47.2%   ENCRYPTED (Avis Durgan)
PC/DOS Kingquest2                         1511    100.0%     47.9%   ENCRYPTED (Avis Durgan)
PC/DOS Kingquest3                         2246    100.0%     48.3%   ENCRYPTED (Avis Durgan)
```

★ The two columns are the point: XORing *plaintext* with the key gives ~47%, XORing *ciphertext*
gives ~100%. The check **can fail**, so passing is evidence rather than assertion (L-23).

**25.1f — ★★ the V2/V3 volume split across all 38 CoCo3 variants (§3D):**

```
King's Quest III   Original       V2 volumes  <-- the ONLY one, parses
King's Quest III   Coco SDC / DrivePak / Drivewire / Floppy 360K    V3 volumes (LZW)
Leisure Suit Larry Original + all repacks                           V3 volumes (LZW)
KQ1 / KQ2 / KQ4 / KQ6 AGI / PQ1, every variant                      V3 volumes (LZW)
```

Matching the oracle's comment at `loader_v2.cpp:61-71` exactly.

**25.1g — the CoCo3-vs-PC comparison, KQ3 only (§3G):**

```
CoCo3 King's Quest III/Original   volumes=[0,1,2,3,4,5,6,7,8,9,11,12,14]
PC    Kingquest3                  volumes=[0,1,2,3]

type       coco3      pc  identical  same-len  diff-len  one-side
LOGIC        132     125          8         3       109        17
PICTURE       99      97          0         0        97         2
VIEW         222     216         41         0       175         6
SOUND          7      34          0         0         7        27
TOTAL  identical=49  same-length-but-differing=3  different-length=388  one-side-only=52

object     coco3=793   pc=796    different length
words.tok  coco3=4463  pc=5657   different length
```

★★ **Only 3 resources are same-length-and-differing** — against the ~98% that figure implied.

**25.2 — bundled-artifact grep:** **N/A.** No build artifact; the deliverables are Python, a
patch and a TSV. The ScummVM binary is an oracle tool outside the repository (§2Q.1).

**25.3 — operator-runtime-smoke:** **N/A — no CoCo3 visual surface this task.** Offline only.

---

### 6 — Reactive deviations and route accounting

1. **PC ingest and ignore-hardening absorbed mid-task**, on Jay's note. Sequenced as P0.4 was.
2. **The CoCo3-vs-PC comparison was run**, since its precondition (AC-5 clean) was met. **Bounded
   to KQ3** by the V3 finding, and reported as such rather than extrapolated.
3. ★ **`*.bat` deliberately NOT ignored** though a DOS release ships one: `build.bat` is the
   build contract (CLAUDE.md §1) and a blanket rule would make it un-addable without `-f`.
4. **A third corpus** now flows through AC-9. The dispatch says "both"; there are three.
5. **`inventory.parse()` signature changed** from `version=` to `spos=` mid-task, because
   AC-8's own instrument flagged it (§3B). **Fixed rather than allowlisted.**
6. **`detect_v3_volume_format()` replaced my heuristic with the oracle's algorithm** after mine
   proved unfalsifiable (§3D.2).
7. **Patch 0004 was rebuilt twice** — once for a forward-declaration error, once for the enum
   mislabel (§3C).

**ROUTE ACCOUNTING.** No route was proposed to Jay or the Orchestrator. What this change contains
is §2's file list plus the seven items above. **What it does NOT contain, said here rather than
left to the diff:** no design v0.5 commit (not provided); **no LZW and no v3 decoder** — v3-volume
games are *refused*, not partially handled; no PICTURE vector decode, no VIEW cel decode, no
sound decode; no CoCo3 resource extraction beyond `KQ3/Original`; no SCI parsing; **no
disassembly of LOGIC bytecode** — `logic.py` splits and decodes messages only. **Explicitly not
done per §12:** no `src/hal/`, no `hal_sync_check.py`, no `build.bat`, no 6809 code, no image
builder, no game data or text committed.

---

### 7 — Uncertainty flags

1. **★ AC-1 is blocked: design v0.5 was never provided.** §2 lists its four supersessions but no
   file arrived. The four changes it describes are **my own P0.4 measurements**, so I can confirm
   they are what I reported — but **confirming a description is not a superset check**, and I
   have not performed one.
2. **★★ 37 of 38 CoCo3 variants are unreadable this phase**, by scope not by defect. **AC-9's
   CoCo3 coverage is 1 variant**, and every CoCo3 conclusion in this report rests on
   `KQ3/Original` alone. ★ **L-22: the retrieved set is not the whole set** — what this misses is
   every fan-port resource, i.e. most of the CoCo3 corpus, and any v3-only format quirk.
3. **★ AC-5's 2,410 spans 8 games of ~160 available.** All are v2-directory, v2-volume, and
   PC/fan-made. **Not covered: v3 volumes, v3 directories, Amiga padding, AGDS, PreAGI, and the
   `Alex Simkin` key.** A clean gate here does **not** license the parser on those.
4. **4 dangling SNDDIR entries in PC KQ1** (SOUND 34-37) point past their volume. ★ **We refuse
   them; the oracle emits 206 ZERO bytes for each.** Neither produces a real resource, so this is
   a divergence in *failure handling*, not parsing — **but I have not fully explained the
   oracle's 206 bytes**, and its `warning()` for a bad signature does not appear in the log.
   Flagged rather than reconciled (§8.1). Per §2.1 the zero-fill is a **ScummVM behaviour**, not
   evidence about AGI.
5. **AC-7's oracle cross-check is indirect.** ScummVM does not dump its parsed word list or
   object table, so `WORDS.TOK`/`OBJECT` are evidenced by **plausibility ratios**, not by an
   oracle diff. That is materially weaker than AC-5 and is why AC-7 is marked ⚠ rather than
   claimed as oracle-verified.
6. **The KQ3 comparison uses one variant per side.** `KQ3/Original` is five disks × two sides
   merged by first-occurrence; a different merge order would change nothing observed, but the
   collision handling is mine and untested against a case where two disks disagree.
7. **★ The ~98% figure is retired, not disproven in general.** I showed the mechanism that
   explains it for CoCo3 KQ1 (V3 read as V2) and measured the KQ3 case. **KQ1 and KQ2 remain
   uncompared** because their CoCo3 sides are V3.
8. **`logic.py` does not disassemble bytecode.** `split()` bounds-checks the size field but
   nothing validates that the bytecode is *well-formed* — a LOGIC could pass every check here
   and still be nonsense. That check arrives with the VM.

---

### 8 — Follow-up candidates

1. ★★ **Decide whether v3 volumes move into scope.** They are not an edge: **six of seven CoCo3
   titles need them**, including `LSL/Original`, one of the two genuine Sierra CoCo3 releases.
   Design §11.1 defers v3 and AD-12 puts LZW on the target's critical path anyway. **The seam
   was built for exactly this** — a v3 decoder goes behind `resource.py`, not around it.
2. ★ **Complete the CoCo3-vs-PC comparison for KQ1 and KQ2** once v3 reads. That is the question
   Jay actually asked, and today it is answered for one title of three.
3. **Provide design v0.5** so AC-1 can be discharged (§7.1).
4. ★ **Explain the oracle's 206 zero bytes** for dangling entries (§7.4) — a small mystery in the
   baseline, and the baseline is the one thing that should hold no mysteries.
5. **Widen AC-5's sample** before trusting the parser beyond v2 (§7.3) — the 150-game fan corpus
   is right there and the harness already runs it.
6. **`seam_check.py` should join `build.bat`** when one exists, as `reg_discipline.py` will —
   both are ratchets, and a ratchet nothing runs is a comment.

---

### 9 — User interaction during task

**Jay sent two messages, and the second reshaped the task.**

1. **Mid-build:** *"AC-9 already runs both corpora — where the same title exists in both, hash
   the extracted resources and report whether they match. ScummVM's detection table shows CoCo3
   KQ1 sharing a md5 with DOS KQ1, which suggests they do."* ★ **Acted on, and the premise did
   not survive** (§3E): the two corpora had **no title in common** at that point, and ScummVM's
   CoCo3 md5s are distinct from its DOS ones. **The check produced a better finding than it was
   aimed at** — an independent confirmation of P0.4's official/unofficial split.
2. **A note on the PC drop** (recorded in §6.1): ingest instructions, the three-title overlap,
   and an explicit warning that the Orchestrator's ~98% figure was **LOW confidence** and might
   evaporate. ★ **It did** (§3G). The note's instruction to *"say so plainly rather than
   reconciling"* is what §3G does.
3. **`continue`** — proceed after the hardening push.

★ **No consultation trigger fired, and two came close:**
- **§8.1** (AC-5 fails ambiguously) — AC-5 *did* fail, at 0/299. **It was not ambiguous**: the
  cause was my instrument and was found by reading the enum. **The parser was never adjusted.**
- **§8.2** (a VOL layout the Specs do not describe) — **found, in the CoCo3 set exactly as the
  trigger predicts.** It did not fire because it is not undescribed: the *oracle* documents it
  at `loader_v2.cpp:61-71`, which made it a scope boundary rather than an unknown.
- §8.3 did not fire (`os9fs.py` already yields contents). §8.4 did not fire (slot counts agree).
  §8.5 could not fire (no v0.5 file).

---

### 10 — Candidate(s) captured this task

**None.**

★ Stated rather than manufactured. The strongest candidate available — *"a red gate says nothing
about the thing under test until the instrument is verified"* (§3C) — is **already captured**, as
`keep-the-artifacts-so-a-broken-summary-costs-a-recompute` and, more directly, in the P0.4
instrument-defect lessons now in idioms §41f. §2C's rule is capture at the **first instance**;
this is the fifth instance of a pattern already in the pool, and re-capturing it would inflate
the count the reconciler uses to weigh it (SCHEMA.md §4: *never fabricate history elements to
inflate the count*). **The right act is to add an instance to the existing row at reconcile
time, not to open a new one** — and that is the reconciler's read-time job, not mine (§2C).

---

### 11 — Commit

`38e458f` — three commits this task:

```
e874155  P1.1a .gitignore: DOS/PC release hardening, BEFORE the PC AGI drop
38e458f  P1.1  resource layer: DIR/VOL parsing, offline, oracle-verified
(this)   P1.1  report + PC manifest
```

Pushed to `origin/wip` before this report.
