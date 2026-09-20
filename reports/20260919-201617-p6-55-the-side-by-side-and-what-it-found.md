## Form B Report — P6.55 — The side-by-side, and the two defects it found in one look
**Class:** recon.  wip.

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-19 20:16:17 (HEAD 221e664, wip). git status: clean except `?? coco_agi.code-workspace`,
an untracked VS Code workspace file written by the editor when it restarted after the host crash
described in §3.1. Not staged — it is the editor's, not this task's.

★ **NOT A DISPATCHED TASK.** No numbered dispatch was issued. This report exists because an
unscheduled session produced two findings about the port, and a finding with no report is a
finding that gets rediscovered. Numbered P6.55 for ordering only.

**No source file changed.** This is recon; §5's 25.1 is therefore a statement about what was
NOT rebuilt, and is argued rather than pasted.

### 1 — Summary

Jay asked for the oracle to be run so he had something to compare the port against — the exact
gap [the-eye-gates-ceiling-is-plausible-not-correct] was captured for one task earlier. **The
oracle cannot do it: it is built `--backend=null` and has no display backend at all**, which
this project's own `oracle/scummvm.pin` states in capitals and which four rounds of debugging a
"hang" did not consult. A stock ScummVM 2.9.1 — the same source as the pin, being the same
release tag — was downloaded instead, and **the first side-by-side look produced a defect
report in one sentence**: the port draws a squarish background around the animating castle
flags where the oracle shows the picture through.

That defect is **`CP_SAVE` not being defined in p3b, so save-under is not compiled in** — which
our own P6.52 report recorded as a scope note three tasks ago, correctly, without anyone stating
what it would therefore look like. A second, independent latent defect was found while
investigating and is **not** the cause: `view_cel.s:249` clears each decoded row to 0 rather than
to the cel's clear key.

### 2 — Files modified

None in the repository. This task changed no source, no tool and no gate.

Written outside the repo:
- `~/.claude/.../memory/coco-agi-oracle-is-headless.md` — new; the oracle has no display backend,
  and the two `scummvm.exe` on this machine both report FileVersion 2.9.1 so version cannot
  distinguish them.
- `~/.claude/.../memory/coco-agi-toolchain-paths.md` — amended; `scummvm.exe` needs
  `C:\Users\jayse\DEV\mingw64\bin` on PATH or it dies at load on `libwinpthread-1.dll` behind a
  **title-less** system dialog, which presents as a hang.
- scratchpad: `vmstate_trace.py`, `vmstate_watch.py`, `clearkey_census.py`, `run_oracle_kq1.cmd`.

### 3 — Reasoning

#### 3.1 Four rounds of debugging a window that cannot exist

The oracle was launched to give Jay a reference. It appeared to hang. Four successive
explanations were offered and **three of them were wrong**, each disproved by the next
measurement:

| offered | killed by |
|---|---|
| working directory wrong (theme/ini not found) | moving it back did not fix the hang |
| my repeated force-kills crashed the host | the bugcheck was `0x154`, a memory-compression store fault, not a display fault |
| "sitting on the title screen waiting for a key" | read off a **stale** `vmstate.txt.tmp` from an earlier, working run [L-92] |
| "not hung, visible window, low CPU" | that window was a **title-less error dialog**, not the game |

The actual cause of the launches that hung: `scummvm.exe` is dynamically linked against MinGW's
runtime and needs `mingw64\bin` on PATH. The **first** relaunch of the session set it; every
later one did not, because PowerShell state does not persist between tool calls — a fact
recorded in this project's own machine notes. The resulting dialog carries **no window title**,
so every instrument that asked "is there a window and is it responding" answered *yes, fine*.

★★ **And underneath all four: `oracle/scummvm.pin` says the build is headless, in capitals, in a
file checked into this repository.** The §2A.5 / §2S discipline — enumerate before concluding —
was applied diligently to the *machine* and never to *our own record of it*.

> `# ★★ HEADLESS, AGI-ONLY, NO SDL. --backend=null is not a convenience, it is a §2O.1 decision:`
> `# the dumps come from the engine's own 160x168 buffers, and a build with no display backend`
> `# cannot accidentally route a baseline through a scaler or a palette.`

**The decision is correct and is not being questioned.** A build that cannot display cannot
contaminate a baseline through a scaler or a palette. The finding is not about the build; it is
that **a deliberately unobservable instrument is indistinguishable from a broken one**, and the
only thing that separates them is a written record someone reads.

#### 3.2 The reference that was used instead, and why stock rather than a build of ours

Options were: build a second SDL ScummVM from the pin, or install stock 2.9.1.

**Stock was chosen, and not only for effort.** The pin is `v2.9.1` — a release tag, so stock
*is* the pinned source. A visual build of *our* tree would additionally carry patch 0005, which
the pin file itself flags:

> `0005 adds 38 and deletes 1 -- it is the ONLY patch that changes existing behaviour rather`
> `than purely adding instrumentation`

That is the deterministic clock. Since the thing under comparison is **animating** flags, a
reference whose timing is a virtual 25 ms tick would be the wrong reference for precisely this
question. Stock 2.9.1 is the unmodified pin; our tree is the pin plus a deliberate timing
deviation.

★ SDL2 was verified absent on this host before the build option was priced — and **the first
sweep was wrong**: `Get-ChildItem -Include` with `-Recurse` on a literal path returns directories
rather than filtering, so it produced a list that looked like a negative result and was not. Re-run
with `-Filter` **and a control probe** (`libwinpthread-1.dll`, 4 hits) to show the search can find
something, it returns exactly one hit — ScummVM's own `backends/platform/sdl/sdl.h`, not the
library. §2W: the instrument was shown able to succeed before its failure was believed.

**Authority tier: §2 tier 3 (ScummVM) for both sides.** Stock ScummVM auto-detected
`2.0F 1987-05-05 5.25"/3.5"/DOS/English` — the same release the oracle detects — so the visual
reference and the gate references are the same game bytes. ★ Per §2.1 this is a fact about
ScummVM, not about Sierra's interpreter; it is a **sanity** reference, not a fidelity ruling.

#### 3.3 Finding 1 — the box is save-under, and it is not compiled

Jay, at the side-by-side: *"the flags in the oracle have a clean background the port does not.
the port still shows a squarish background while the oracle shows that area as transparent."*

**Mechanism.** `composite.s:663` puts `co_save`/`co_restore` inside `ifdef CP_SAVE`, and p3b does
not define it. Nothing saves the background under a sprite and nothing restores it. Every
composited pixel stays on the plane permanently, so an animating sprite accumulates the **union
of its cels' opaque pixels** — which is a rough rectangle.

★★★ **§2H check 2 — name the caller, not the implementation.** The save-under *code* is not
defective; it is notably careful, and knows the backing store is `2 x cel area` because the
sprite writes the priority plane too. **The defect is in what the build includes**, which is a
property of the enclosing build configuration and invisible from inside the routine.

★★ **§2H check 3 — grep the reports for the same subsystem.** Done, and it is the finding:

```
reports/20260919-135700-p6-52-the-compositor-learns-about-windows.md:45
| ~~co_save/co_restore~~ | both planes, by row | ★★★ inside ifdef CP_SAVE; p3b does not define it |
reports/20260919-135700-p6-52-the-compositor-learns-about-windows.md:134
AC-1  five sites enumerated; co_save/co_restore not compiled in p3b (ifdef CP_SAVE)
```

★★★★★ **The fact was already recorded, correctly, three tasks ago — as a note about scope.** It
said what was not compiled. It did not say what would therefore be wrong on a screen, and nobody
made that step for three tasks while the screen was looked at twice.

**Why it survived the byte gates.** `comp` passes 124/124 by compositing single frames onto a
clean plane, and a single composite genuinely is correct — the gate has no way to express a
relationship between frame N and frame N+1. `cel` 9,193/9,193 gates decoding, not presentation.
★ This is §4A.1's shape exactly: a byte gate cannot find a defect in the glue between the things
it gates.

**It also explains the asymmetry in Jay's own reports, which is why it is believed and not merely
liked:** Graham is *"facing right, doesn't move"* — a static sprite accumulates nothing and looks
correct; the flags animate and box. ★★ **Falsifiable prediction: when input is wired and Graham
walks, he will smear a trail.** If he does not, this finding is wrong.

**Cost, so the fix is not mistaken for a one-line define:** the backing store is `2 x cel area`
(P6.52 measured the peak at 8,304 B, twice P5.1's published 4,152 B bound). It needs a siting
decision. Region A's 2,904 recovered bytes remain unclaimed and are not enough alone.

#### 3.4 Finding 2 — the row clear uses 0 where AGI uses the clear key. Latent, and NOT the box.

`view_cel.s:242-251` clears each row with `clr ,x+` — to 0. AGI's transparent colour is the
cel's **clear key**, the low nibble of cel header byte 2 (`view_cel.s:159-162`). Where the key is
not 0, any byte the RLE never covers is left as colour 0, and `composite.s:186`'s `cmpa co_key`
will not reject it.

★★ **This was offered as the explanation of Jay's box and then withdrawn, on two grounds:**

1. **The happy path never needs the clear.** `view_cel.s:280-285` handles the terminating zero
   byte by filling the rest of the row with `vc_key` explicitly. The clear is a safety net for
   early-ending rows.
2. **Measured, not argued** (`clearkey_census.py` over the gate's own view dumps, via
   `tools/agivm/view.py`'s decoder — §2O.1: the reference, not a reimplementation of it):

```
cels-Kingquest1 : 118 views, 740 cels,   26 with clear_key != 0  (3.5%)   keys 1 and 3
cels-larry1     : 151 views, 1121 cels, 1017 with clear_key != 0 (90.7%)  mostly key 3
```

★★★ **The defect is nearly dormant on KQ1 and would be pervasive on LSL1** — one of the two
titles Sierra shipped for the CoCo3. It is a porting hazard that is invisible on the title the
port is currently developed against, which is the worst shape for a latent defect to have.

★ **A negative result is a result** [§8]: this is a real defect, it is not the reported one, and
saying so keeps it from being "fixed" and credited with a change it would not have caused.

### 4 — Verification (AC-by-AC)

No dispatch, so no dispatch ACs. The findings are classified as §2O requires.

- **F1 [class: eye-gated]** The port draws a filled rectangle around animating sprites where the
  oracle shows the background — **Jay, live, side-by-side against stock ScummVM 2.9.1 on the same
  game bytes.** ★ This is the §4 operator gate and is authoritative; it is not Clyde-certified.
- **F2 [class: state-comparable]** The cause is `CP_SAVE` undefined in p3b — evidenced by
  `composite.s:663` plus the P6.52 report's own two statements, quoted in §3.3. ★ **Not yet
  closed by measurement.** The discriminating experiment is named in §8.1 and has NOT been run.
- **F3 [class: byte-comparable]** `view_cel.s:249` clears to 0, not `vc_key`; 26 of 740 KQ1 cels
  and 1,017 of 1,121 LSL1 cels carry a non-zero key — **census run against the oracle's own view
  dumps**, output in §3.4.
- **F4 [class: suite]** The oracle has no display backend — `oracle/scummvm.pin [build]` and
  `config.mk` (`BACKEND := null`, `MODULES += backends/platform/null`), two independent records.

★★ **F2 is the one carrying weight and is the one not yet measured.** It is consistent with every
observation including the Graham/flags asymmetry, and it remains an inference from a build flag
until the arm in §8.1 runs.

### 5 — Verdict-time evidence (v0.7 §11)

**25.1 fresh tool output:** ★ **No build was run, because no source changed.** Per §2T the
baseline is cited rather than rebuilt, and here the stronger statement is available: the tree is
byte-identical to the one P6.54 reported at `221e664` — `git status` clean but for the editor's
untracked workspace file, HEAD unmoved, lwasm 4.24 unchanged. **Gate figures are therefore
carried from `reports/20260919-191000-p6-54-the-compositor-doubles-the-nibble.md`: pic 45/45,
res 1,264/1,264, cel 9,193/9,193, comp 124/124, vm 9/9, `comp_probe.bin` 967 B `39F5D105`.**
★★ Nothing in this task is a claim that those figures moved; §3.3's point is that **they did not,
and could not**, while a visible defect stood.

Fresh output that WAS produced, in full in §3.4 and §3.2: the clear-key census, and the SDL2
sweep with its control probe.

**25.2 bundled-artifact grep:** N/A — no artifact built.

**25.3 operator-runtime-smoke:** ★★★ **PASSED as an observation and FAILED as a result — Jay,
live, RGB, side-by-side against stock ScummVM 2.9.1.** The gate did its job: it produced a defect
report on the first look, on a path five byte gates call green. Per §4A.3, **a byte gate that
passes where the eye gate fails is a finding about the gate**, and §3.3 states which gate and why.

### 6 — Reactive deviations and route accounting

**Deviations.**
1. ★★ **Repeated force-kills of the oracle process, four times.** Then blamed for the host crash
   in §3.1 — wrongly, and the retraction is recorded there. It was still the wrong way to work
   and it stopped.
2. ★ **Launching a 6 MB-per-run instrumented binary repeatedly** without first reading what it
   was. `oracle/scummvm.pin` would have ended the excursion before it began.
3. ★ **479 untracked run artifacts** were left in the sibling ScummVM tree and swept at the end
   (§2G). Verified by enumerating untracked paths through `git ls-files --others`, so nothing
   tracked could be reached; the tracked-modified count held at 14 across the sweep.

**Route accounting.** ★★ I proposed building a second SDL ScummVM from the pin and **did not
build it.** §3.2 states why — stock 2.9.1 is the same source and is a *better* reference here
because it lacks patch 0005. **Nothing was built, nothing was configured, and no second tree
exists.** The offer stands and is not a plan of record.

★ I also proposed rendering `pic<NNN>.visual.bin` to images as a reference and **did not do
that either** — it shows pictures only, and flags are views, so it would not have answered the
question asked.

### 7 — Uncertainty flags

1. ★★★ **F2 is unmeasured.** Everything is consistent with absent save-under; nothing has yet
   *shown* it. §8.1 is the experiment.
2. ★★ **The flags' view number is not identified.** The accumulation argument is generic. Which
   view animates on the castle screen, and its cel geometry, is unknown — so the *shape* of the
   predicted box has not been compared with the shape of the observed one.
3. ★★ **The host crashed once during this work** (`0x154 UNEXPECTED_STORE_EXCEPTION`, 7:22:09 PM,
   no dump written — `volmgr 161` records the dump write itself failing). Cause unattributed. The
   storage stack logged nothing and both repos verified intact afterwards. ★ It is **not**
   established that ScummVM was involved; it is also not established that it was not. A memory
   test has been recommended to Jay and not run.
4. ★ **The stock build's visual correctness is assumed from provenance**, not verified — it is
   the official release, so it has the SDL backend by construction. No independent check was made
   that its AGI rendering matches the pin's.
5. ★ **Stock 2.9.1 landed inside `C:\Users\jayse\DEV\`**, alongside the project trees rather than
   outside them. Harmless — no tool resolves siblings by wildcard — but a script globbing
   `scummvm*` there would now match two things.

### 8 — Follow-up candidates

1. ★★★★★ **Define `CP_SAVE` for p3b and site the backing store.** `2 x cel area`, peak 8,304 B
   measured. **The discriminating experiment, and it is cheap: build p3b with and without it and
   have Jay look at the flags.** ★ Per §2W the with/without pair IS the fault arm — if the box is
   unchanged with save-under on, F2 is wrong and the box is something else.
2. ★★★★ **Clear decoded rows to `vc_key`, not 0** (`view_cel.s:249`). A one-instruction class of
   change. ★★ Gate it on **LSL1**, not KQ1 — 90.7% against 3.5% — which makes it a **corpus**
   question before it is a code question [L-85, L-86].
3. ★★★ **The comp gate composites single frames and cannot see frame-to-frame state.** F1 is
   invisible to it by construction. A two-frame arm — composite, advance a cel, composite again,
   compare the plane against the oracle's — would close the class, not the instance.
4. ★★ **Identify the castle flags' view and loop**, so the predicted box can be compared with the
   observed one in shape as well as in kind (§7.2).
5. ★★ **Wire `HAL_KEYBOARD` into the cel arm.** Eye-gate question 2 — is the ego the same
   silhouette flipped — has been blocked for **four** tasks now, and §3.3's Graham-smear
   prediction also needs him to walk.
6. ★ **Record the two-binary hazard in the repo, not only in an agent's memory.** ★★★ §2J.6's
   lesson exactly: the PowerShell rule lived in a memory file, failed three times, and held only
   once it was in CLAUDE.md. **This note is currently in the weaker slot.** `oracle/scummvm.pin`
   is the natural home and is Orchestrator-owned content (§2D), so it is surfaced here, not edited.
7. ★ **`oracle/scummvm.pin` understates the CoCo3 title set**, carried from P6.54 and still
   unaddressed: CLAUDE.md §2K says *"Sierra's own two CoCo3 AGI titles"* while
   `C:\Projects\agi-games\coco3\` holds seven OS-9 AGI titles, six of them Sierra.

### 9 — User interaction during task

Substantial, and it drove every finding:

1. *"can you run the game on the oracle for me so i can see what its supposed to look like?"* —
   the request that started it.
2. *"it looks like scummvm hangs"* / *"still seems to hang"* — two reports that were each
   answered with a wrong explanation before the right one (§3.1).
3. **Jay supplied the screenshot of the `libwinpthread-1.dll` dialog.** ★★ That image ended four
   rounds of misdiagnosis in one message; no instrument I had ran had reported it, because the
   dialog has no window title.
4. *"my computer crashed hard when scummvm was running not sure if it was coincidental or not"* —
   §7.3.
5. *"why run a memory check when it complained about a storgae device error"* — ★★ a correct
   challenge to my wording. Nothing had reported a storage error; `UNEXPECTED_STORE_EXCEPTION`
   names the memory-compression **store manager**. I had repeated "storage device" from a generic
   cause list without checking whether this host had logged one. It had not.
6. *"it never got to a room, it was stalled in the cmd boot window"* — ★★★ the correction that
   reframed the problem from "the engine will not run" to "there is no window", which is what led
   to the pin file.
7. *"is it possible for you to build a scummvm version that has the visuals distinct from your
   non visual version"* — §3.2.
8. *"i want you to run it for me so i know it will work for later testing"* — stock launched,
   window title confirmed.
9. ★★★★★ *"so the flags in the oracle have a clean backgorund the port does not. the port still
   shows a squarish background while the oracle shows that area as transparent"* — **the first
   sentence spoken after the side-by-side existed, and it is Finding 1.**

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-19-a-scope-note-is-not-a-consequence.md`
- `seeds/AGI/live/2026-09-19-an-instrument-built-to-be-unobservable-looks-broken.md`

### 11 — Commit

★ **No source commit exists, because this task changed no source.** The report is its own
commit and cannot name its own hash, so it is recorded here by the follow-up commit that adds
this line:

- `d3ede9b` — P6.55 report (this file)
- this line added in the commit immediately following `d3ede9b`

Both pushed to origin/wip before this report. Pool rows pushed separately (§10).
