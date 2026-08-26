## Form B Report — P4.2 the native Windows oracle — build ScummVM with MinGW and drop the WSL dependency
**Class:** build.  wip.

### 0 — Receipt / status (C-35 stamp)
t0=2026-08-25 (operator instruction, mid-session; HEAD at receipt `e8f3c0b`, wip, clean).
HEAD at report: `58e4e11`. Two commits this task: `d287119` (native build), `58e4e11` (ignore rule).
git status clean apart from this report.

★ **This task had no dispatch.** It came from Jay directly — *"i would like you to stop using WSL.
you should be able to use mingw and powershell instead."* There is therefore no dispatch AC list;
§4 lists the verifiable claims the work actually delivers, each with a class (§2O).

### 1 — Summary
WSL is no longer required for any part of this project. The oracle now builds and runs as a
native Windows binary under MinGW-w64, and the whole pipeline — oracle dump, VM run, state diff —
runs in Git Bash and PowerShell. **The premise of Jay's instruction was correct and the project's
own recorded fact was wrong:** `scummvm.pin [host]` had asserted since P0.2 that this machine had
no C++ toolchain, and that assertion is what put the oracle in WSL in the first place. A complete
MinGW-w64 14.2.0 toolchain was present the whole time, vendored into a sibling project's tree and
therefore invisible to a PATH-and-standard-roots check. Because the oracle **is** the baseline
every other result is diffed against (§2O.1), the new binary was proved equivalent to the old one
before anything was allowed to depend on it.

### 2 — Files modified
- `oracle/scummvm.pin` — `[host]` **corrected** (the wrong text is kept, quoted, beside the correction); new `[build-native]` section with the full recipe, both local build steps, and the equivalence evidence.
- `harness/tools/oracle_dump.sh` — default binary is now the native build; WSL documented as historical. No other change; the script itself needed none.
- `.gitignore` — `scummvm.ini` / `scummvm.log` (see §3.6).

Explicit-path staging throughout. **No change to the pinned ScummVM source**: the native build is
configure flags plus two invocation-level steps, and `oracle/patches/0001-0005` are untouched.

### 3 — Reasoning

**3.1 ★★ The recorded fact was wrong, and the shape of the error is the finding.**
`scummvm.pin [host]` read:

> *"Windows host : NO C++ toolchain. No gcc, g++, clang, MSVC, make, cmake or pkg-config; no
> MSYS2 and no MinGW compiler (the git on PATH is Git-for-Windows' mingw64 bundle, which ships
> no compiler). No SDL2 anywhere."*

Every clause of that is individually true of the places it looked. Measured again this task: PATH
carries no compiler; `C:\msys64`, `C:\msys32`, `C:\mingw64`, `C:\MinGW`, `C:\TDM-GCC-64`,
`C:\Strawberry\c\bin`, `C:\Program Files\LLVM`, both Visual Studio roots, `chocolatey\bin` and
`C:\Qt` are all absent; and Git's `mingw64\bin` holds 50 exes, none of them a compiler (my grep
matched `psl-make-dafsa`, which is not one).

A recursive sweep for `gcc.exe`/`g++.exe`/`cl.exe` found, in one pass:

```
C:\Projects\2600em\tools\mingw64\bin\g++.exe
C:\Projects\2600em\tools\mingw64\bin\gcc.exe
```

— **MinGW-w64 GCC 14.2.0**, full binutils (`ar`, `ld`, `ranlib`, `strip`, `windres`) and **GNU
Make 4.4.1**, vendored into a *sibling project's* tree, off PATH, in no standard location.

★ **This is CLAUDE.md §2A.5 applied to the environment instead of to a tool's feature set** —
*"before concluding a mode/config/flag does NOT exist, do an EXHAUSTIVE search … 'I didn't find
it' is valid only after the enumeration."* The rule existed because of premature *"MAME can't do
X"* claims; nobody had extended it to *"this machine can't do X."* It is also §2S: absence in what
you happened to reach is not absence. **Checking PATH is not an enumeration.** What broke the
error was a search of a different *shape* (sweep the filesystem for the artifact), not more
instances of the same shape (check more known locations).

★ Environment negatives are arguably worse than tool negatives: they are recorded once, they
justify an entire workflow built around the workaround, and nothing re-tests them because the
workaround keeps working. This one stood for six dispatches.

**3.2 Two configure flags, found by reading rather than by installing.** On a Windows host
ScummVM compiles `backends/dialogs/win32/` and `backends/taskbar/win32/` **regardless of
`BACKEND := null`**, and both `#include <SDL.h>`, which is genuinely absent. The tempting move is
to install SDL2 to satisfy code the null backend never uses. `./configure --help` has
`--disable-taskbar` and `--disable-system-dialogs`, which is the correct fix and removes exactly
the two failing translation units.

**3.3 Two local build steps, neither touching the pinned source.** Both are recorded in
`[build-native]` and both must be re-run after a clean configure.

*The Win32 resource.* `Makefile.common`'s `%.o: %.rc` rule runs four `sed` expressions to
generate a `.d` file, and GNU sed 4.9 under Git Bash rejects them (`unterminated 's' command`).
★ **The failure is in DEPENDENCY GENERATION, not in the resource compile** — `windres -I. -Idists
dists/scummvm.rc -o dists/scummvm.o` succeeds, and make then sees the object as up to date and
skips the broken rule. I did not chase the sed defect further: it does not affect the artifact.

*The win32 wrapper.* `stdiostream.cpp` and `midi/windows.cpp` call `Win32::stringToTchar` /
`tcharToString` / `moveFile`, but the wrapper defining them lives in the SDL platform module,
which `--backend=null` excludes. It must be built **through make** and added to the archive.

★★ **A near-miss worth recording.** I first compiled that wrapper with a hand-assembled `g++`
line whose `DEFINES` extraction was malformed. It compiled, it linked, and the binary would have
run — but the object was **64115 bytes** against make's **63897**, because my line dropped
`-DUNICODE`/`-D_UNICODE`, which silently changes `tchar` behaviour in a file whose entire purpose
is `tchar` conversion. That is the §2N-class failure (a wrong constant that raises nothing) in
build-flag form. Rebuilt via make.

**3.4 ★★ Equivalence was verified, not assumed — because the oracle IS the baseline.**
A different compiler, C++ runtime and OS can produce a different oracle. Since every result in
this project is diffed against oracle output (§2O.1), swapping the binary without checking would
put the whole gate on unverified footing and could not be detected later. Kingquest1, same seed,
WSL-built vs native-built:

**262 common cycles, all 256 variables and all 256 flags identical, zero divergence.**

And the VM's verdict is unchanged by the swap: `tools/agivm` diverges from the native oracle at
**cycle 186, flag 20** — exactly where it diverges from the WSL oracle. The full pipeline
end-to-end with no WSL reproduces KQ3's result (**cycle 6, flag 221**) as well.

Authority tier: this is a claim about **ScummVM**, established from fresh tool output on both
builds. It is not a claim about AGI.

**3.5 Throughput differs; fidelity does not.** The native build produced 262 cycles where WSL
produced 434 in the same 25 s. With the deterministic virtual clock (P4.1, `[determinism]`) cycle
N is cycle N regardless of how fast the host reaches it, so this changes how much evidence a
fixed-duration run yields, not what that evidence says. **NOT ESTABLISHED: the cause.** Patch
0002 calls `s_vmLog.flush()` once per cycle and Windows file I/O is a plausible candidate, but
that is a hypothesis and I did not measure it. Both builds use the same configure optimisation
settings (neither passes `--enable-release`), so it is **not** compiler flags. Raise `SECS` to
compensate.

**3.6 A hygiene defect this task introduced and then closed.** The native binary writes
`scummvm.ini` into the **process working directory**, so invoking it ad hoc with the repo as CWD
drops one in the repo root — which is exactly what happened while I was collecting evidence for
this report. It arrived empty, but a populated one records **game paths into the user's corpus**.
Not game data and not a §2P breach, but machine-local state with no business being tracked, and
deleting it is not a fix because it returns on the next ad-hoc run. Ignored. ★ `oracle_dump.sh`
is not the source — it `cd`s to the output directory first, which is precisely why it does that.

**3.7 §2S — refs and scopes.** Oracle tree `C:\Projects\scummvm` at `9d9b9e9…` = the pin,
verified this task by `git rev-parse` inside that tree against the `commit =` line in
`scummvm.pin`. Native binary reports `ScummVM 2.9.1dirty` — "dirty" is expected and correct: it is
the pin plus `oracle/patches/0001-0005`. The vendored toolchain at `C:\Projects\2600em\` belongs
to a sibling project and was **read only** — nothing in that tree was modified, and no HAL file
was touched (§2G/§2M do not come into play; the HAL does not exist yet).

### 4 — Verification (AC-by-AC)

★ No dispatch, so no dispatch ACs. These are the claims this task makes, each with a class.

- **AC-1 [class: byte-comparable]** The oracle builds natively on Windows with MinGW. — `scummvm.exe`, 75,131,345 bytes, `ScummVM 2.9.1dirty (Aug 25 2026 21:43:06)`, built with g++ 14.2.0 / GNU Make 4.4.1.
- **AC-2 [class: byte-comparable]** ★★ **The native oracle is equivalent to the WSL oracle.** — Kingquest1, same seed: 262 common cycles, **zero divergence across all 256 vars and all 256 flags**. This is the AC that licenses the swap; without it the rest is worthless.
- **AC-3 [class: state-comparable]** The swap does not change any existing verdict. — `agivm` vs native oracle diverges at cycle 186 / flag 20, identical to the WSL result. KQ3 end-to-end: cycle 6 / flag 221, identical.
- **AC-4 [class: state-comparable]** The full pipeline runs with zero WSL. — `oracle_dump.sh` (unmodified logic) → `run_agivm.py` → `vmdiff.py`, all under Git Bash, on Kingquest3: 511 oracle cycles, 511 VM cycles, gate reports the expected divergence.
- **AC-5 [class: byte-comparable]** The pinned source is unchanged. — `git rev-parse` in the oracle tree = the pin; the eight modified files are exactly patches 0001–0005; no patch file altered. The native build is configure flags + two invocation steps only.
- **AC-6 [class: suite]** The harness self-checks still pass, run natively. — `gen_oracle_tables.py --check` OK, `vmdiff.py --self-test` PASSED, `reg_discipline.py` 0 accesses, `seam_check.py` OK.
- **AC-7 [class: byte-comparable]** The repo stays clean of runtime droppings. — `scummvm.ini`/`scummvm.log` ignored; stray removed; `git status` clean.
- **AC-8 [class: eye-gated]** **NOT APPLICABLE and not claimed.** Nothing renders and nothing runs on the CoCo3 this task.

### 5 — Verdict-time evidence (v0.7 §11)

25.1 fresh tool output (verbatim). ★ There is no `build.bat` yet (P3 has not happened), so §1's
25.1 binding has no target; what follows is the equivalent fresh output for what this task built.

```
=== toolchain (native, no WSL) ===
g++.exe (x86_64-posix-seh-rev1, Built by MinGW-Builds project) 14.2.0
GNU Make 4.4.1
bash: 5.2.37(1)-release  MINGW64_NT-10.0-26200
nproc: 8

=== oracle binary ===
75131345 bytes  Aug 25 21:43
ScummVM 2.9.1dirty (Aug 25 2026 21:43:06)

=== pin ref check (2S) ===
9d9b9e93108a276c551aeffa390169ccc5148e15
commit      = 9d9b9e93108a276c551aeffa390169ccc5148e15
```

```
=== A. oracle equivalence: WSL-built vs NATIVE-built, Kingquest1, same seed ===
oracle: 434 cycles   ours: 262 cycles

NO DIVERGENCE. 262 cycles compared, no divergence (oracle has 434, ours 262)

=== B. agivm vs NATIVE oracle (same verdict as vs WSL oracle) ===
oracle: 262 cycles   ours: 434 cycles

FIRST DIVERGENCE AT CYCLE 186 (line 187)
   flag byte 2 (flags [20]): oracle 30 ours 20
```

```
=== full pipeline, zero WSL, Kingquest3 ===
oracle   : /c/Projects/scummvm/scummvm.exe
scummvm exit=124  (124 = timeout, which is NORMAL: an AGI game does not end by itself)
Emulating Sierra AGI v2.440
  cycles: 511
cycles emitted : 511
oracle: 511 cycles   ours: 511 cycles
FIRST DIVERGENCE AT CYCLE 6 (line 7)
   flag byte 27 (flags [221]): oracle 20 ours 00
```

```
=== harness self-checks, all native ===
CHECK OK: C:\Projects\coco_agi\tools\agivm\optable.py matches the pinned oracle.
SELF-TEST PASSED
[reg-discipline] 0 register access(es). Nothing outside the HAL touches $FF80-$FFDF.
[seam] OK -- the §4.2a seam holds.
```

The enumeration that overturned `[host]`:

```
=== filesystem sweep for gcc.exe / g++.exe / cl.exe (C:\, 4 levels) ===
  C:\Projects\2600em\tools\mingw64\bin\g++.exe
  C:\Projects\2600em\tools\mingw64\bin\gcc.exe
```

25.2 bundled-artifact grep: N/A — no target artifact is built this task.
25.3 operator-runtime-smoke: **N/A this task** — nothing renders and nothing runs on the CoCo3.
Not "pending Jay": there is no gate to observe.

### 6 — Reactive deviations and route accounting
- **Deviation:** `oracle/scummvm.pin` is a pinned-fact document and I rewrote part of it. Justified: `[host]` was **factually wrong** and was causing a workflow. The superseded text is quoted verbatim inside the correction rather than deleted, so the record of what was believed — and why it was wrong — survives.
- **Deviation:** the native build needs two steps outside `make`. Both are invocation-level, both recorded, neither modifies the pinned source. A build that needs undocumented manual steps is not reproducible, which is why they are in `[build-native]` and not only in this report.
- **Not done, deliberately:** I did **not** rebuild with `--enable-release` to close the throughput gap. It would change the binary and require re-running the equivalence check, for a rate improvement the `SECS` knob already covers. Recorded rather than silently skipped.
- **Not done, deliberately:** I did **not** install MSYS2 or any toolchain. `winget` is available and `MSYS2.MSYS2` / `LLVM.LLVM` / `Kitware.CMake` are all installable, so that path existed — the vendored toolchain made it unnecessary, and installing system software on Jay's machine is not something to do unasked.
- **ROUTE ACCOUNTING.** I proposed no route in advance; the instruction was one sentence and I worked to it directly. What I said mid-task and then did: I said I would prove the native oracle equivalent before depending on it — done (AC-2). I said the throughput gap was *probably* the per-cycle flush — that remains **unmeasured** and is labelled as a hypothesis in both the pin and §3.5, not as a finding.

### 7 — Uncertainty flags
- **The throughput cause is not established.** 262 vs 434 cycles per 25 s. The flush hypothesis is untested.
- ★ **The equivalence check covers 262 cycles of one title.** It is strong evidence for that path and is not a general proof that the two builds agree everywhere — a divergence in code the KQ1 title screen never reaches would not have shown up. Worth widening if the native binary is ever suspected.
- **The two local build steps are fragile against a clean reconfigure.** They must be re-run, and nothing enforces that. If a future build fails at `dists/scummvm.o` or on `Win32::` link errors, this is why.
- **The vendored toolchain is not ours.** `C:\Projects\2600em\tools\mingw64` belongs to a sibling project and could be moved or removed by work in that repo, silently breaking this build. It is referenced by absolute path in `[build-native]`.
- **`sed`'s rejection of the `.rc` dependency rule is unexplained.** It reproduces with two different delimiters, so it is not the `:` in `[[:space:]]` as I first supposed. Not chased, because it does not affect the artifact.

### 8 — Follow-up candidates
1. **Re-examine whether the P0.2 `[host]` error cost anything else.** It sent all oracle work through WSL for six dispatches; the `$VAR`-eaten-by-Git-Bash defect that repeatedly bit inline `wsl bash -c` calls was a direct consequence and is now gone.
2. Consider vendoring or pinning the toolchain location rather than depending on a sibling repo's tree.
3. If oracle throughput becomes a constraint, measure the flush hypothesis before changing anything — then either buffer the dump or pass `--enable-release`, re-running AC-2 either way.
4. Widen the build-equivalence check beyond one title if the native oracle is ever suspected.
5. Carried from P4.1 and still the highest-value item: **the VIEW parser + `updateView` cel cycling + `motion.cpp`**, which is the whole of the remaining VM divergence.

### 9 — User interaction during task
One instruction, quoted in full: *"i would like you to stop using WSL. you should be able to use
mingw and powershell instead."* ★ The premise was correct and the project's recorded fact was
wrong; §3.1 records how. No other interaction. This report was then requested separately.

### 10 — Candidate(s) captured this task
One, to the shared pool (`seeds/AGI/live/`), pushed at `2db3bd8`:

- `2026-08-25-checking-path-is-not-an-enumeration.md`

`project: AGI`, `source: live`, `instance_count: 1`, **`initiator: operator`** — set faithfully:
Jay's instruction is what prompted the re-check, and recording it as executor-found would be
false. ★ Captured at first instance this time, unlike P4.1's three.

### 11 — Commit
`d287119` — P4.2: build the oracle natively on Windows; drop the WSL dependency
`58e4e11` — P4.2: ignore the native oracle's CWD droppings
(pushed to origin/wip before this report)
