## Form B Report — T-P0-004 — the CoCo3 corpus: OS-9 manifests and tier-2 evidence
**Class:** build + recon. wip.

---

### 0 — Receipt / status (C-35 stamp)

t0 = 2026-08-24T04:11:59Z. HEAD at receipt `84c4517` (wip) → **at report `11d73f3`**, pushed.
`git status --porcelain` at report → **clean**.

★ This dispatch was worked in two sittings: the ignore hardening landed and was pushed at
`1edff3e`, the task stopped at §2's step 2 per §8.2, and resumed when Jay dropped the archives.
The interim report is `reports/20260824-035415-p0-4-ignore-hardening-landed-corpus-awaited.md`.

---

## ★ §3 PRE-DISPATCH GREP FINDINGS (C-13) — VERBATIM, BEFORE THE SUMMARY

```
coco_agi        branch wip   HEAD 84c4517cb8291d38844548cc70331147ac6df436  (at receipt)
POP3_port       branch wip   HEAD 282a65cf9c79739326e101b3d7cccffc8cff2daa
karateka_coco3  branch wip   HEAD 072ddcfc27ccb2c0a9b820913cd57b341a6e6fbc
```

Sibling refs **unchanged since T-P0-001**, so AC-9's figures stand at the refs they were first
measured at (§2S.3).

### ★★★ Is any game data already tracked? — **NO. HISTORY IS CLEAN.**

**Checked before any other work, because §8.1 makes it a stop.**

```
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u
  -> 50 distinct paths ever added, all branches, life of the repository
$ ... | grep -iE '\.dsk$|\.par$|\.zip$|\.os9$|\.img$|vol\.|logdir|picdir|viewdir|snddir|words\.tok|object$'
  (no output)
```

★ All 50 were **read in full**, not only grepped — a grep proves absence only of what it looks
for. Every path is repository infrastructure; the single file under `games/` is P0.3's manifest.
**§8.1 did not fire.**

### Corpus location, archive presence, tool state

```
C:\Projects\agi-games\        EXISTS -- contained only agile-gdx/ (the P0.3 fan corpus)
C:\Projects\agi-games\coco3\  ABSENT at receipt -- created this task
repo root archives            NONE at §2 step 2; SEVEN present when Jay dropped them
game_manifest.py              ZIP archives only: zipfile at :38, glob("*.zip") at :142.
                              No OS-9 support, no disk-image support of any kind.
```

---

### 1 — Summary

**All ten AC pass. The corpus is processed, manifested, and nothing entered the repository.**

★★★ **The sequencing held.** `.gitignore` was hardened, committed and pushed at `1edff3e`
**before Jay dropped anything**; when the seven archives arrived git marked every one `!!`
ignored. After processing, `git status` is clean, history is clean, and the tree contains no
`.dsk`, `.par`, `.zip` or `.png`.

★★ **M-11 is settled, and the Orchestrator's two hypotheses were a false dichotomy — both are
true, on independent axes** (§3D). There are **two distinct KQ3 builds**, and *separately*
three variants **dropped `vol.14`**. AC-6 **confirms KQ3 at 51.4%** and **corrects LSL from 21%
to 14.8%**.

★★ **AC-7 answers whether one engine served all seven: for the modern repacks, yes — a single
`CMDS/MnLn` build runs all seven titles. The two Sierra-shipped originals each carry their own,
smaller, earlier build.** Three interpreter builds exist, not one and not seven.

★ **Two format findings the corpus forced, neither guessed** (§3B, §3C): DrivePak `.par` images
are **512-byte-sector containers**, and `DD.TOT` disagrees with file length across three whole
media classes. All seven `.par` files parsed to **zero files** until the first was found — and
the fix for it failed silently until the second was.

★ **Only two of the seven titles are genuinely Sierra CoCo3 releases** (§3A). That materially
bounds the tier-2 claim in the dispatch's §1 and design v0.4 §8.1.

---

### 2 — Files modified

Explicit-path staging (§2E). Two commits.

**`1edff3e` — the hardening, before the drop**
- `.gitignore` — carrier formats, extensionless AGI names, Sierra's interpreter directories.

**`11d73f3` — the corpus work**
- `harness/tools/os9fs.py` — **new**, a read-only OS-9 RBF reader.
- `harness/tools/game_manifest.py` — `--os9` mode, per-image and per-file manifests.
- `games/manifests/coco3-images.tsv` — **new**, 80 rows, one per image.
- `games/manifests/coco3-files.tsv` — **new**, 1,311 rows, one per file-in-image.
- `.gitignore` — mixed-case `*Dir`/`*DIR` and `tOC` variants, added **because the corpus showed
  the real filenames** (§3E).

★ **No game data, screenshot, or extracted resource is in the repository.** Corpus at
`C:\Projects\agi-games\coco3\`; AC-8's screenshots at `.../coco3/_ac8-screenshots/`. **No sibling
repository was modified.**

---

### 3 — Reasoning

#### 3A — ★★ What these seven titles actually are, which is not quite what §1 says

The dispatch describes *"seven AGI titles as they existed on the CoCo3."* **Measured, that is
true of two of them.**

★ **Only King's Quest III and Leisure Suit Larry have an `Original/` directory** — KQ3 as ten
`KQ3-D<n>_S<m>` volumes, LSL as `LL1disk1..3`. The other five titles (KQ1, KQ2, KQ4, KQ6 AGI,
PQ1) have **no `Original/` at all**: their media are `Coco SDC`, `DrivePak`, `Drivewire`,
`Floppy 360K/720K` — modern distribution formats.

**This corroborates CLAUDE.md §2K independently:** *"Sierra's own two CoCo3 AGI titles — King's
Quest III and Leisure Suit Larry 1."* The corpus agrees exactly, and it was not consulted to
reach that conclusion — the `Original/` directories were.

★★ **Consequence for the authority stack, and it is the reason this is in §3 and not §7:**
design v0.4 §8.1 wants tier 2 restored for CoCo3-specific questions. **It is restored for KQ3
and LSL. For the other five, these images are a community conversion running Sierra's
interpreter — evidence about the interpreter, not about a Sierra release.** A palette or timing
observation from KQ6 AGI is a fact about Brandon Kouri's conversion; the same observation from
`KQ3/Original` is a fact about a Sierra artifact. **Do not let all seven carry the same weight.**

★ Also found: **the KQ IV archive contains the complete Police Quest 1 archive as a member**,
byte-identical to the standalone (`4603e2b3…`, 2,329,167 B both). Extracted as a file and **not
recursively unpacked** — doing so would have silently duplicated an entire title and corrupted
every byte total downstream. Removed as a proven duplicate after the hash comparison, not before.

#### 3B — ★★ The `.par` stride, and §2H's first check earning its keep

**§6 required §2H's three checks on the OS-9 parser, and the first one is the whole of this
section.** The reader was written to the RBF format and validated across the corpus rather than
one image — and **seven of eighty images parsed to zero files** while still reporting a valid
volume header, a plausible sector count and a correct volume name.

**Is there a SECOND mechanism serving a different object class?** ★ **Yes — a `.par` is not a
bare filesystem, it is a CONTAINER.** Mapping one byte by byte showed **2,880 data sectors
alternating one-for-one with 2,880 all-`0xFF` sectors**, and `DD.TOT = 2880 = filesize / 512`.
DrivePak stores one 256-byte OS-9 sector per **512-byte physical block**, upper half erased.

★ **The stride is now detected by evidence, not by file extension.** Extension would be the lazy
discriminator and would be wrong for any `.dsk` imaged the other way; the reader instead asks
whether the root descriptor reads as a plausible directory at each stride.

#### 3C — ★★★ The detection fix failed silently, and why is the task's sharpest finding

The first stride detector asked *"does the root descriptor have its directory-attribute bit set?"*
**It did not work, and it could not have.** At the wrong stride the reader lands on an **erased
sector, which is `0xFF` bytes — and `0xFF` has bit 7 set.** The erased sector passed the
directory test perfectly. **The check could not fail on precisely the input it existed to
reject**, so the fallback never fired and all seven images still reported zero files — now with a
detection step that *looked* like the problem had been considered.

It works only because three fields must now agree, each implausible when erased **for a
different reason**:

- the directory attribute bit;
- a size that fits inside the image (`0xFFFFFFFF` does not);
- a first segment LSN inside the image and non-zero (`0xFFFFFF` does not).

★ **`0xFF` cannot simultaneously be a valid flag, a sane length and an in-range pointer.** That
is the whole mechanism, and it is this task's captured candidate (§10).

#### 3D — ★★ M-11 SETTLED: both hypotheses are true, on independent axes

The Orchestrator claimed KQ3's variants differ by a missing `vol.14`, then revised to "different
builds" on near-universal small size differences. **Both are Orchestrator inference from one
comparison, and §5 asks which is true. The answer is: both, and they are unrelated to each
other.**

**Axis 1 — a genuinely missing volume.**

| variant | images | `vol.N` present | has `vol.14`? |
|---|---|---|---|
| `Original` | 10 | 0–9, 11, 12, 14 | ✅ |
| `Floppy 360K` | 3 | 0–9, 11, 12, 14 | ✅ |
| `Coco SDC` | 1 | 0–9, 11, 12 | ❌ |
| `DrivePak` | 1 | 0–9, 11, 12 | ❌ |
| `Drivewire` | 2 | 0–9, 11, 12 | ❌ |

★ **`vol.10` and `vol.13` are absent from EVERY variant** — they are gaps in Sierra's own
numbering, not losses, and mistaking them for losses is the easy error here. **The real loss is
`vol.14`, dropped by SDC / DrivePak / Drivewire and retained by Original and 360K.**

**Axis 2 — two distinct builds, and it is not the same split.**

Per-file content sha256 across variants: **`Original` differs from all four others in every
volume and every DIR file**, by small amounts — `vol.0` is 73,493 B (`f67dd150…`) in `Original`
against 72,932 B (`4a376fb5…`) in all four others; `logDir`, `picDir`, `viewDir`, `sndDir` differ
in content at **identical sizes**. Measured across the shared files: **2 identical, 17
different.**

★★ **The two files that are byte-identical everywhere are `object` and `words.tok`** — the
inventory table and the parser vocabulary. **The data that was rebuilt is the resource data; the
data that was not is the game's vocabulary and object list.** That is a strong hint about what
kind of rebuild it was, and it is a fact, not an inference from sizes.

**So the split is: `Original` is one build; `SDC`+`DrivePak`+`Drivewire`+`360K` are another —
and within that second group, `360K` kept `vol.14` while the other three dropped it.** Two axes,
different boundaries. **§8.5 was considered and did not fire:** no third explanation appeared,
the two named ones are simply both true and independent.

#### 3E — §2H's remaining two checks

2. **Name the routine that CALLS it.** ★ Decisive for the manifest's honesty. `CMDS/Sierra`,
   `CMDS/MnLn`, `MODULES/*` and `OS9Boot` sit on the same disks as the AGI resources and would
   be counted as game bytes by any size-summing walk. **They are CODE our port replaces** — the
   same reasoning that removed `AGIDATA.OVL` from the P0.3 figures — so the tool classifies each
   file and reports `agi_bytes`, `interp_bytes` and `host_bytes` separately. A single total
   would have overstated every "does it fit" figure by ~55 KB per disk.
3. **Grep prior reports for the same subsystem.** P0.3 §3B established the exclude-the-
   interpreter rule and P0.3 §2 the do-not-commit-renderings rule; both are applied here
   unchanged, the second extended to AC-8's screenshots. **No contradiction.**

★ **And a §2H-shaped finding in my own AC-1 work:** the corpus showed the real filenames are
**mixed case** — `logDir`, `picDir`, `viewDir`, `sndDir`. **`*dir` would NOT match those on a
case-sensitive filesystem**; it matched here only because this Windows host compares
case-insensitively, which is a property of the host and not of the rule. `*Dir`/`*DIR` added, and
the reasoning recorded in `.gitignore` (§7.2).

#### 3F — AC-8, and the two rules that shaped how it was run

★★ **§2P nearly lost a game image to the emulator.** The idioms file records that **MAME opens a
floppy READ-WRITE and JVC saves back**. Mounting a corpus image directly could have modified
Jay's data. **The run was made on a COPY**, and the original's sha256 was re-checked afterwards
and is unchanged (`5e9fd9d8…`, §5).

★ **§3's PNG rule shaped the verification.** I may not read or interpret PNG pixel content, so
"did it boot?" could not be answered from the screenshots. The idioms file's own debugging route
— **read the 32×16 VDG text screen** — is structured text and is permitted, so that is what was
used. Before `DOS`: the DECB banner and `OK`, `PC=$A7D5` (idiom 14a's documented prompt poll).
After `DOS`: `PC=$EFCB`, later `$C50F`, and `$0400` no longer holds a text screen. **The machine
accepted `DOS`, left Disk BASIC, and never returned an error to the prompt** — objective, and it
does not require me to look at a pixel. **Whether King's Quest III is on that screen is Jay's
call, and 25.3 is pending it.**

#### 3G — Refs and scopes (§2S.3)

Corpus figures at the seven archives Jay supplied, sha256 of each in §5. Sibling figures at
**POP `wip` `282a65c`** and **Karateka `wip` `072ddcf`**. MAME `coco3`, RGB default.

---

### 4 — Verification (AC-by-AC)

- **AC-1 [byte-comparable] ★★★** — `.gitignore` hardened, **committed and pushed at `1edff3e`
  BEFORE the archives arrived**. 32 probe paths proven ignored with rule and line, 6 proven still
  allowed, **without creating a single probe file**. When the seven archives landed, git marked
  every one `!!`. ✅ **PASS.**
- **AC-2 [byte-comparable]** — after processing: `git status --porcelain` **empty**; history grep
  **empty**; tree scan for `.dsk`/`.par`/`.zip`/`.png` **empty**. Verbatim in §5. ✅ **PASS.**
- **AC-3 [suite]** — all seven extracted to `C:\Projects\agi-games\coco3\<title>/<variant>/`,
  **81 members CRC-verified against the archives before deletion**, then the seven repo-root
  archives deleted. Tree in §5. ✅ **PASS.**
- **AC-4 [suite]** — `game_manifest.py --os9` reads OS-9; **80 images, 1,311 files, zero parse
  failures, zero empty**. `coco3-images.tsv` carries image sha256, bytes, stride, sectors,
  volume name, DD.FMT, version, file/AGI counts, agi/interp/host bytes, volume count;
  `coco3-files.tsv` carries per-file content sha256. Both committed. ✅ **PASS.**
- **AC-5 [state-comparable] ★ M-11 SETTLED** — **both hypotheses true on independent axes**
  (§3D). Per-volume hashes and the volume inventory in §5. ✅ **PASS.**
- **AC-6 [suite]** — **KQ3 `Original` 51.4% — confirms the Orchestrator's 51%.**
  **LSL `Original` 14.8% — CORRECTS the reported 21%.** Also measured for the 360K sets
  (KQ3 20.3%, LSL 9.6%), which is where the difference in method shows. ✅ **PASS.**
- **AC-7 [state-comparable]** — **three distinct interpreter builds**, table in §5. One
  `CMDS/MnLn` (25,559 B) on 38 images spanning **all seven titles**; KQ3 `Original` and LSL
  `Original` each carry their own smaller build. `MODULES/` is four modules, **one version each,
  byte-identical wherever present**. ✅ **PASS.**
- **AC-8 [eye-gated] ★ BOUNDED — ONE TITLE, TWO STILLS, THEN STOPPED.** `KQ3/Original/KQ3-1-1.DSK`
  booted under MAME `coco3` via a real `DOS` off a mounted floppy. **Launch path: `live-disk`**
  (nothing poked). **Observation mode: `static-png`** — endpoints only, no motion (§4).
  Screenshots at `C:\Projects\agi-games\coco3\_ac8-screenshots\`. **Surfaced unexamined per §3.**
  ✅ **DELIVERED — 25.3 pending Jay.**
- **AC-9 [byte-comparable]** — `coco_agi` **0**, POP **59** at `282a65c`, Karateka **8** at
  `072ddcf`; fixture demo rc=0 including its negative control. ✅ **PASS.**
- **AC-10 [suite]** — one candidate captured and pushed. §10. ✅ **PASS.**

---

### 5 — Verdict-time evidence (v0.7 §11)

**25.1a — AC-1, `git check-ignore -v`** (excerpt; full 38-line output in the interim report):

```
  IGNORED   kq3.dsk        <- 87:*.dsk        IGNORED   vol.14         <- 111:vol.*
  IGNORED   lsl.par        <- 88:*.par        IGNORED   logdir         <- 132:*dir
  IGNORED   corpus.zip     <- 89:*.zip        IGNORED   CMDS/Sierra    <- 137:CMDS/
  IGNORED   boot.os9       <- 90:*.os9        IGNORED   OS9Boot        <- 140:os9boot
  IGNORED   x/y/kq3.dsk    <- 87:*.dsk        IGNORED   a/b/c/logdir   <- 132:*dir
  allowed   games/manifests/coco3-images.tsv  allowed   games/manifests/coco3-files.tsv
```

After the mixed-case addition (§3E):

```
  IGNORED   logDir   picDir   viewDir   sndDir   a/b/logDir   tOC   tOC.txt
  allowed   games/manifests/coco3-images.tsv     games/manifests/coco3-files.tsv
```

**★ When the seven archives were dropped, git saw them as ignored — the hardening working:**

```
$ git status --porcelain --ignored
!! "King's Quest I (Sierra On-Line) (OS-9) (Coco 3).zip"
!! "King's Quest II (Sierra On-Line) (OS-9) (Coco 3).zip"
!! "King's Quest III (Sierra On-Line) (OS-9) (Coco 3).zip"
!! "King's Quest IV (Sierra On-Line) (OS-9) (Coco 3).zip"
!! "King's Quest VI AGI (Brandon Kouri) (OS-9) (Coco 3).zip"
!! "Leisure Suit Larry (Sierra On-Line) (OS-9) (Coco 3).zip"
!! "Police Quest 1 (Sierra On-Line) (OS-9) (Coco 3).zip"
```

**25.1b — AC-2, after all processing, verbatim:**

```
$ git status --porcelain
(empty)
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u | grep -iE '<game-data signatures>|\.png$'
(empty)
$ find . -path ./.git -prune -o \( -name '*.dsk' -o -name '*.par' -o -name '*.zip' -o -name '*.png' \) -print
(empty)
```

**25.1c — AC-3, extraction verified BEFORE deletion (the last moment the sources existed):**

```
King's Quest I ...zip         6/ 6 members verified (CRC)
King's Quest II ...zip        8/ 8 members verified (CRC)
King's Quest III ...zip      17/17 members verified (CRC)
King's Quest IV ...zip       16/16 members verified (CRC)
King's Quest VI AGI ...zip   15/15 members verified (CRC)
Leisure Suit Larry ...zip     9/ 9 members verified (CRC)
Police Quest 1 ...zip        10/10 members verified (CRC)
total bytes verified: 59295823
VERDICT: ALL MEMBERS EXTRACTED AND CRC-VERIFIED -- safe to delete sources
```

★ Checked against the archive's own **CRC**, not sizes: a size match is not a content match.

Corpus tree (`C:\Projects\agi-games\coco3\`):

```
King's Quest I      6 files   Coco SDC 1 · DrivePak 1 · Drivewire 2 · Floppy360K 1 · Savegames 1
King's Quest II     8 files   + Floppy720K 1
King's Quest III   17 files   Coco SDC 1 · DrivePak 1 · Drivewire 2 · Floppy360K 3 · ORIGINAL 10
King's Quest IV    15 files   Floppy360K 6 · Floppy720K 3 · Savegames 2
King's Quest VI    15 files   Floppy360K 6 · Floppy720K 2 · Savegames 3
Leisure Suit Larry  9 files   Coco SDC 1 · DrivePak 1 · Drivewire 2 · Floppy360K 2 · ORIGINAL 3
Police Quest 1     10 files   Floppy360K 3 · Savegames 3
```

**25.1d — AC-4, the manifest run:**

```
[manifest] wrote games/manifests/coco3-images.tsv (80 images)
[manifest] wrote games/manifests/coco3-files.tsv (1311 file rows)
[manifest] 80 image(s), 1311 file(s)
[manifest] stride: 256-byte=73, 512-byte=7
[manifest] images with zero files: 0
```

**25.1e — ★ AC-5 / M-11, per-volume content sha256 across KQ3 variants (first 12 hex):**

```
file       Coco SDC        DrivePak        Drivewire       Floppy 360K     Original
vol.0      4a376fb5 72932  4a376fb5 72932  4a376fb5 72932  4a376fb5 72932  f67dd150 73493
vol.1      4cc95ff6 23116  4cc95ff6 23116  4cc95ff6 23116  4cc95ff6 23116  05012597 23067
vol.2      e24807e6 64535  e24807e6 64535  e24807e6 64535  e24807e6 64535  196762cb 64446
vol.11     412cb8cc  8076  412cb8cc  8076  412cb8cc  8076  412cb8cc  8076  370fcf42  8062
vol.12     53278d0c 15067  53278d0c 15067  53278d0c 15067  53278d0c 15067  ff0dc9dc 15037
vol.14     -               -               -               39f38a96  5606  3c353158  5596
logdir     a8505f8c   429  a8505f8c   429  a8505f8c   429  a8505f8c   429  a408792b   429
picdir     696b2eee   531  696b2eee   531  696b2eee   531  696b2eee   531  24f648a5   531
object     6785f2d9   793  6785f2d9   793  6785f2d9   793  6785f2d9   793  6785f2d9   793
words.tok  fc077189  4463  fc077189  4463  fc077189  4463  fc077189  4463  fc077189  4463
                                                                           ^^ identical
files present in >1 variant with IDENTICAL content : 2   (object, words.tok)
files present in >1 variant with DIFFERENT content : 17
missing vs union:  Coco SDC [14] · DrivePak [14] · Drivewire [14] · 360K none · Original none
```

**25.1f — AC-6, duplication:**

```
King's Quest III / Original   -- 10 images   total 1316889  unique 639940   DUPLICATION 51.4%
   object on 10 disks · vol.0 on 9 · vol.12 on 5 · vol.11 on 3 · vol.14 on 2
Leisure Suit Larry / Original --  3 images   total  427616  unique 364303   DUPLICATION 14.8%
   object on 3 disks · vol.0 on 3 · vol.4 on 2
King's Quest III / Floppy 360K --  3 images  total  800622  unique 638105   DUPLICATION 20.3%
Leisure Suit Larry / Floppy 360K -- 2 images total  404486  unique 365470   DUPLICATION  9.6%
```

★ **KQ3 51.4% confirms the reported 51%. LSL 14.8% corrects the reported 21%.**

**25.1g — AC-7, interpreter inventory:**

```
--- CMDS/MnLn --- 3 distinct builds across 40 images
  c64de18528a7c6db  25559 B  on 38 images:  ALL SEVEN TITLES
  288d9dc4dda11cdd  24622 B  on  1 image :  King's Quest III   (Original)
  207989968af82f47  25413 B  on  1 image :  Leisure Suit Larry (Original)

--- CMDS/Sierra --- 3 distinct builds across 40 images
  4f41f53e8951ba45   1371 B  on 38 images:  ALL SEVEN TITLES
  5f416abc5003338e   1377 B  on  1 image :  King's Quest III   (Original)
  63976c176410c52d   1371 B  on  1 image :  Leisure Suit Larry (Original)

--- MODULES/ --- one version each, byte-identical wherever present
  AGIVIRQDr 222 B · Clock.50Hz 503 B · Clock.60Hz 494 B · VI 58 B
```

**25.1h — AC-8, the boot, and the §2P check around it:**

```
$ mame coco3 -ext fdc -flop1 <COPY of KQ3-1-1.DSK> -autoboot_script os9boot.lua ...
[f00000] script loaded; natkeyboard armed
[f00300] boot settled -- posting DOS
[f00361] DOS post drained
[f01500] snapshot at frame 1500
[f02400] second snapshot (later endpoint)
Average speed: 485.58% (40 seconds)                                   mame rc=0

--- objective boot check via the VDG TEXT SCREEN (structured text, not pixels -- §3) ---
=== BEFORE the DOS command  (frame 280)  PC=$A7D5 ===
   0 |DISK EXTENDED COLOR BASIC 2.1
   1 |COPR. 1982,1986 BY TANDY
   2 |UNDER LICENSE FROM MICROSOFT
   3 |AND MICROWARE SYSTEMS CORP.
   5 |OK
=== AFTER DOS, ~9s in   (frame  900)  PC=$EFCB ===   (no longer a text screen)
=== AFTER DOS, ~22s in  (frame 2200)  PC=$C50F ===   (no longer a text screen)

--- §2P: the corpus original after the MAME run ---
5e9fd9d8637fa80c2496ef431f563927e1b484ba0370dc8752ceb4c994ea970a  KQ3-1-1.DSK  UNCHANGED
```

**25.1i — AC-9:**

```
coco_agi  src/engine/**                   [reg-discipline] OK -- measured 0   rc=0
POP       src/ less src/hal,src/harness   [reg-discipline] OK -- measured 59  rc=0
Karateka  src/ less src/hal               [reg-discipline] OK -- measured 8   rc=0
run_rule_demo.sh                          rc=0  (incl. the --expect 7 negative control)
```

**25.2 — bundled-artifact grep:** **N/A.** No build artifact was produced; the deliverables are
a `.gitignore`, two Python tools and two TSV manifests, none of which bundles anything.

**25.3 — operator-runtime-smoke:** **PENDING JAY — `live-disk`, RGB default, `static-png`.**
Two stills at `C:\Projects\agi-games\coco3\_ac8-screenshots\`:
`kq3-original-d1s1-boot-frame1500.png`, `kq3-original-d1s1-boot-frame2400.png`.
★ **Surfaced unexamined (§3). Clyde screenshot analysis is never authoritative for 25.3 (§4).**
★ **Endpoints only — a static PNG cannot show motion**, so this is not a live gate even once Jay
looks.

---

### 6 — Reactive deviations and route accounting

1. **Extra ignore patterns beyond AC-1's list** — more archive wrappers, both letter cases, and
   `CMDS/`/`MODULES/`/`OS9Boot`. A spare pattern costs nothing; a missing one is unbounded.
2. **Mixed-case `*Dir`/`*DIR` and `tOC` added after the corpus arrived** (§3E) — a correction to
   my own AC-1 work, made because the artifacts disproved an assumption in it.
3. **The nested PQ1 archive was hash-compared and then deleted**, not recursively unpacked (§3A).
4. **AC-8 ran on a COPY** (§3F), and the original was re-hashed afterwards.
5. **AC-8 produced two stills, not one.** §5 says one screenshot; a second endpoint 15 emulated
   seconds later costs nothing and lets Jay distinguish a settled screen from a transient one.
6. **A second Lua run** dumped the text screen, because §3 forbids me answering "did it boot?"
   from the PNGs.

**ROUTE ACCOUNTING.** No route was proposed to Jay or the Orchestrator. What this change contains
is §2's file list plus the six items above. **What it does NOT contain, said here rather than
left to the diff:** no AGI resource decoding of any kind, no play past the first screen, no
second title booted, no disassembly, and **no interpretation of either PNG**. **Explicitly not
done per §12:** no `src/hal/`, no `hal_sync_check.py` edit, no `build.bat`, no CoCo3 code, no
offline renderer, no VOL/DIR parser of our own — `os9fs.py` reads a **filesystem** and reports
file sizes, and stops there — no game data or screenshot committed, and no v3 decision.

---

### 7 — Uncertainty flags

1. **★★ Five of the seven titles are NOT Sierra CoCo3 releases** (§3A). They are community
   conversions running Sierra's interpreter. **Tier-2 authority attaches to `KQ3/Original` and
   `LSL/Original`; the rest are evidence about the interpreter, not about a Sierra artifact.**
   Design v0.4 §8.1's tier-2 restoration should be scoped accordingly.
2. **★ The `Original` sets are 5 disks × 2 SIDES, not 10 disks** (`KQ3_D1_S1`…`D5_S2`). AC-6's
   51.4% is computed per **side**, which is what a manifest can see. If design v0.4 §4.5 counted
   ten *disks*, the duplication figure agrees numerically but describes different media.
3. **AC-6's figure depends on which variant is measured** — KQ3 is 51.4% on `Original` and 20.3%
   on `Floppy 360K`. **A duplication number without its variant is not a number**, and the
   Orchestrator's 21% for LSL is close to the 360K-set answer for KQ3, which may be the source
   of the discrepancy. Not investigated further; the measured values are all in §5.
4. **Interpreter builds are compared by content hash, not disassembled** (§12). *"Three distinct
   builds"* means three distinct byte sequences; **what differs between them is unknown**, and
   the KQ3 and LSL originals differing from each other is interesting and unexplained.
5. **`vol.10` and `vol.13` are absent from every KQ3 variant.** Read as gaps in Sierra's own
   numbering; **not verified against a DIR table**, because that needs resource decoding (§12).
6. **★ AC-8 shows the machine left Disk BASIC and ran something. It does NOT show that King's
   Quest III rendered.** That is Jay's to say, and 25.3 is pending it. A `static-png` verifies
   endpoints only.
7. **Savegame disks (`FMT=0x00`, blank volume names) carry no AGI content** and are in the
   manifest with `agi_bytes` 0. They inflate image counts per title; filter on `agi_files > 0`
   when using the TSV for content questions.
8. **DriveWire images declare `DD.TOT` far beyond their file length** (18,432 sectors on files as
   small as 1,394). Reads are clamped to the file, so a file whose segments point past the end
   is returned **short and flagged**, not zero-padded. No such truncation was observed in this
   corpus, but the flag exists in the TSV.

---

### 8 — Follow-up candidates

1. ★★ **Scope design v0.4 §8.1's tier-2 claim to KQ3 and LSL** (§7.1). The other five are a
   different kind of evidence and should not be quoted as Sierra CoCo3 behaviour.
2. ★★ **Fold AC-5's answer into the spec: M-11 is BOTH, on independent axes** (§3D) — and record
   that `object` and `words.tok` survive the rebuild byte-identical while every resource volume
   does not.
3. ★ **Correct design v0.4 §4.5's LSL figure from 21% to 14.8%**, and attach the variant name to
   both it and the confirmed KQ3 51.4% (§7.3).
4. **Decide what the three interpreter builds mean** (§7.4) — one engine serving all seven modern
   repacks is a strong signal for D-14's eye-gated comparison work, and the two original builds
   are the only Sierra-shipped ones.
5. **AC-8 follow-up is Jay's**: if the stills show KQ3 running, `KQ3/Original` becomes the
   reference for the palette and timing questions design §8.1 wants.
6. **Consider back-porting the ignore hardening to POP and Karateka** (§2G, separate task).

---

### 9 — User interaction during task

**Jay sent one message: `dropped`**, indicating the seven archives were in the repo root. That
resumed the task at §2's step 3. **No guidance about the work's content was given and none was
requested.**

★ **One trigger fired across the two sittings and was obeyed: §8.2** — the archives were absent
at §2 step 2, so the first sitting stopped and reported. §8.1 was checked first, both sittings,
and did not fire. **§8.3 was approached and resolved rather than fired**: OS-9 parsing *was*
ambiguous across images (§3B) — but the ambiguity was a second media class with a different
stride, identified from the bytes and handled, not an entry shape that fails to hold. §8.4 did
not fire; the MAME boot worked first try. §8.5 did not fire; no third explanation appeared.

---

### 10 — Candidate(s) captured this task

`seeds/AGI/live/2026-08-24-erased-media-is-the-adversarial-input-to-a-validity-check.md`

*Test a format-validity check against erased media specifically — all-ones and all-zeros are the
two values most likely to satisfy a weak check by accident, so a discriminator must require
several independent fields to agree rather than one flag bit.* From §3C: the stride detector
tested one attribute bit, and `0xFF` has that bit set, so **the check could not fail on precisely
the input it existed to reject.** Captured at first instance, `initiator: executor`,
`instance_count` verified equal to `len(instance_history)`.

★ The row notes for the reconciler that this sits **apart** from the three prior AGI rows rather
than with them: those are about the distance between what a check examined and what it was taken
to prove, whereas here the check pointed at exactly the right thing and **could not fail on it**.
The remedies differ, so folding them into one heading would lose something.

Pushed `c88daa5..e6946c9`, fire-and-forget. No existing pool entry read for content or edited (§2C).

---

### 11 — Commit

`11d73f3ca3d8e54a79f315d6397c11a67ff5be3e` — two commits this task:

```
11d73f3  P0.4  CoCo3 corpus: OS-9 reader, image and file manifests
1edff3e  P0.4a .gitignore: game-data hardening, BEFORE the CoCo3 corpus arrives
```

Pushed to `origin/wip` before this report. This report is a third commit on `wip`.
