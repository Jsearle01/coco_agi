## Form B Report — T-P0-120 / P6.66 — Text and cels in one binary; the copyright draws and the picture is on the wrong clock
**Class:** integration (§4A).  wip.

### 0 — Receipt / status (C-35 stamp)

t0=2026-09-20 19:30:58 (HEAD 9829f78, wip). `src/harness/p3b_probe.s`,
`harness/tools/{p3b_show.ps1,p3b_run.lua,p3b_arms_check.ps1}`. ★★ **`git diff --stat -- src/hal/
src/engine/memmap.inc` is EMPTY.**

### 1 — Summary

★★★★★ **The combined arm exists, fits, and runs. It is the first binary this project has had with
both the text engine and the compositing path in it.** `src/engine/text.s` is `org`ed into slot 7 at
`$EBBA-$F477` — 2,237 B — beside the parser that was already there. **Region A keeps 1,724 B free
and slot 7 keeps 1,929 B.** Six poke runs, every byte accounted.

★★★★★ **The copyright draws, in the text area, with the picture behind it.** Jay: ***"it is
readable."*** 715 non-black bytes in rows 168-199 where the cel arm had **zero**.

★★★★★ **AND JAY'S THREE FURTHER OBSERVATIONS ARE ONE MECHANISM AND TWO OPEN QUESTIONS:**

1. ***"the copyright shouldn't appear until the title screen is rendered"*** — ★★★★★ **`draw.pic`,
   `show.pic` AND `configure.screen` are all `vm_op_modelled`.** The text runs on the game's
   schedule and the picture runs on the probe's. §3.4.
2. ***"the text still doesn't scroll"*** — ★★★ `display.v` **is** wired, so this is a different
   cause and is **open**. §3.5.
3. ***"i see a 'press a key to continue' … which doesn't appear in the oracle"*** — ★★ **open**, and
   `configure.screen` is the first suspect. §3.5.

★★★★ **Three defects of my own were found and fixed or corrected in this task, two of them by
instruments refusing to do what I claimed** (§3.6). **One of them cost the first eye gate.**

### 2 — Files modified

- `src/harness/p3b_probe.s` — the slot-7 `org` under `P3B_COMBINED`; `P3_TEXTB_BASE/_END`,
  `P3_TEXT_SPLIT`; the ceiling assertion; the two cross-checks.
- `harness/tools/p3b_run.lua` — the fifth poke run.
- `harness/tools/p3b_show.ps1` — `-Combined`; the split symbols; **`$Wired` corrected** (§3.6).
- `harness/tools/p3b_arms_check.ps1` — the eighth arm.

### 3 — Reasoning

#### 3.1 §4A — the move, and the numbers

```
P3_TEXTB_BASE $EBBA   P3_TEXTB_END $F477     2,237 B in slot 7
P3_CODE_END   $5944                          region A headroom 1,724 B
slot 7 left to MAP_COVERAGE ($FC00)          1,929 B
combined binary 18,393 B  89837FCA
```

★★★★ **It assembles with NO `-DP3B_ACCEPT_OVERRUN`** — AC-1. ★★★ Against P6.64's 513 B over,
moving the whole text half rather than 513 bytes of it leaves both regions comfortable, which is
what Jay's ruling asked for.

★★ **The base is a literal with an assertion**, for the forward-reference reason the `P3_VOCAB`
block states: `P3_CLNBUF` is declared 240 lines below the relocation, so an expression there fails
pass 1 with *"Conditions must be constant"*.

#### 3.2 §4D / AC-3 — the image, verified before the screen

```
poked  2184 B -> $2000  code
poked   626 B -> $0200  vm_tables (relocated)
poked 12133 B -> $2888  code
poked  2237 B -> $EBBA  text.s (relocated, slot 7)
poked   343 B -> $57ED  code
poked   870 B -> $E000  parser (org'd)
program 18393 bytes in 6 run(s)
vm_tables at $0200..$0471: 0 of 626 bytes differ from what was poked -- intact
```

★★★★ **2184 + 626 + 12133 + 2237 + 343 + 870 = 18,393**, which is the binary exactly, and the
host's own byte-accounting guard refuses any run list that does not add up. ★★★ **This is the check
P6.64 taught: a green run is not evidence the image was placed correctly; the run count is.**

#### 3.3 ★★★★★ P6.65's "4,166-byte hole" was the flat vocabulary's window — my error, corrected

P6.65 — mine — scanned three arms for symbols **declared inside** `$EBBA-$FC00`, found none, and
reported the space unclaimed.

★★★★★ **A region owned by ONE symbol with a large extent shows zero symbols inside it.** Measured
this task:

| arm | `P3_VOCAB` | extent |
|---|---|---|
| cel | `$E3BA` | **`$FF00`** — covers the hole |
| text / combined | `$A000` | `$C000` — windowed |
| `p3b_flat` | **`$EBBA`** | **`$FC00`** — *is* the hole |

★★★ **And `p3b_probe.s:2708-2711` names the figure back at me** — *"4,166 B against Kingquest1's
3,144"* — in the flat vocabulary's own block. **The number I reported as a discovery was already
written down as that window's size.**

★★★★ **The combined arm is safe only because its vocabulary is windowed at `$A000`**, which §4B's
second assertion now requires rather than assumes.

#### 3.4 ★★★★★ The picture is on the probe's clock and the text is on the game's

The oracle's title sequence [P6.62 §3.1, logic 83, cycle 1]:

```
$18 load.pic  $6F configure.screen  $19 draw.pic  $77 prevent.input
$67 display   $67 display                                   <- the copyright
$1A show.pic                                                <- THE PICTURE APPEARS HERE
```

★★★★★ **`show.pic` comes AFTER both `display` calls.** AGI renders the picture offscreen, writes
the text, and shows both together. **Our handlers:**

| opcode | handler |
|---|---|
| `$18 load.pic` | `vmop_load_pic` |
| ★★★★★ **`$19 draw.pic`** | **`vm_op_modelled`** |
| ★★★★★ **`$1A show.pic`** | **`vm_op_modelled`** |
| ★★★★★ **`$6F configure.screen`** | **`vm_op_modelled`** |
| `$77 prevent.input` | `vmop_prevent_input` |
| `$67 display` / `$68 display.v` | **real** |

★★★★★ **All three picture-timing opcodes are no-ops.** The picture appears when `p3_room_check`
notices var 0 changed and calls `pic_render_at` + `p3_present` — **the probe's own room detection,
not the game's instruction.** The copyright appears when `display` executes, which is real.

★★★★ **So there is nothing in the port that COULD order them**, and Jay's *"the copyright shouldn't
appear until the title screen is rendered"* is that fact seen from the front. ★★★ **It is not a
timing bug to be tuned; it is three unimplemented opcodes.**

#### 3.5 The two that stay open

★★★ **The scroll.** `display.v` is wired, so the P6.62 mechanism — one more line every five cycles
— should reach the screen. ★★ **The text-area census is FLAT at 715 bytes from cycle 6 through 160**,
which is consistent with the scroll redrawing the same rows rather than advancing, and also
consistent with it targeting the picture area where the census cannot see. ★★★★ **Jay's eye settles
which: it does not scroll.** The cause is not established.

★★ **The 'press a key' line.** It is not a string in `text.s` (grepped). ★★★ **`configure.screen` is
the first suspect** — it is the opcode that sets how many rows the picture occupies against the text
area, and it is modelled. ★ Not investigated further; §10 keeps the integrated run out of scope and
this is its territory.

#### 3.6 ★★★★★ Three of my own defects, and two were caught by instruments refusing to comply

**1. The font was never staged, and it cost the first eye gate.** Jay: *"the text is garbled."*
★★★★★ **The host stages the font only when it extracted `P3_FONT`/`P3_FONT_BYTES`; those are on the
`$Linked` want-line; `$Linked` derives from `$Wired`; and `-Combined` was in neither.** So
`txt_blit` fetched glyphs from cold RAM at `$E3BA`.

★★★★★ **This is P6.64 §3.5's defect, repeated by me, in the task that documented it** — and the
rule was already written into this file **earlier in this same task**, beside the split symbols:
*"the want-line's condition must be the SAME condition as the symbol's definition, not merely a
related one."* ★★★ **I wrote it and then did not apply it one screen below.** Fixed by putting
`-Combined` into `$Wired`, which is what the source says (`TEXT_WIRED` is defined under
`P3B_TEXT_LINK` with `TEXT_MODELLED` undefined — exactly the wired text arms' condition).

★★ **The evidence it is fixed:** `font 2048 of 2048 bytes -> P3_FONT $E3BA (256 glyphs)`, a line
absent from every previous combined run, and the census moving **1,388 → 715** — fewer, denser bytes,
which is glyphs rather than noise.

**2. The overlap assertion was backwards and passed the case it existed for.** The first version read
`ifgt MAP_ARENA_WIN_E-P3_VOCAB` — *"the vocabulary is below `$A000`"* — but the flat vocabulary is at
`$EBBA`, **above** it. ★★★★★ **It passed a build where `P3_VOCAB` and `P3_TEXTB_BASE` were the SAME
ADDRESS.** Found only because §2W says show a guard red and **it refused to go red.** Replaced with a
two-sided range test, which fires.

**3. P6.65's hole measurement**, §3.3.

**4. ★★★★★ A THIRD want-line instance, in the same file, found by taking my own lesson seriously.**
After writing defect 1 up, I grepped for the *pattern* rather than the instance — every conditional
adding names to `$WANT` — and `p3b_show.ps1:315` was gated on **`-not $Linked`** for the cel-side
symbols (`vc_*`, `co_*`, `p3_restbytes`, `p3_ndirs`). ★★★★ **`$Linked` now includes `-Combined`, so
that line excluded an arm that owns every symbol on it.** Those two predicates were the same only
while text and cels were mutually exclusive. Re-gated on `$CelLink`, spelled from `$FLAGS` as
*"this arm did not ask for `-DP3B_NO_CEL`"*, which is the source's own condition.

★★★ **So the rule was written twice in this file and broken three times in it**, and only the grep
found the third. ★★ **Verified afterwards across five arm shapes — cel, combined, text, fault,
rescheck — all extract and run**, which is the check that a want-line change needs, because
`vm_symbols.py` fails hard on a missing name.

★★ **Two of the four were found by an instrument declining to behave as claimed**, which is the
whole of §2W stated as an experience rather than a rule.

#### 3.7 ★★★★★ Sprites and text in one frame, which has never happened before

The combined arm in room 1, after the want-line corrections:

```
sprites 4    restore 122240 bytes over 200 cycles = 611.2 per cycle  (2 rects live)
ego: x=110 y=100 view=0 LOOP=0 cel=0
text area rows 168-199: 266 of 5120 bytes non-black
final room 1, err 0, no stall
```

★★★★ **Both halves reporting from the same run**: the compositor restoring backgrounds at the same
rate P6.60 measured for the cel arm (611.2 against 620.8, the difference being the text arm's own
status line), and the text engine holding the text area. ★★★ **Nothing in this project has produced
both numbers from one binary before**, and it is the precondition the integrated run has been
waiting on since P6.62.

### 4 — Verification (AC-by-AC)

- **AC-1 [measurement] — MET.** §3.1; assembles with no overrun escape.
- **AC-2 [assembler] — PARTIAL.** The overlap assertion is **shown RED** from the command line
  (`-DTEXT_VOCAB_FLAT` on a combined build). ★★ **The stale-base check is not command-line
  reachable** — `-DP3_FONT_BYTES=…` is a multiply-defined symbol — so it is asserted and not
  demonstrated. Said rather than claimed.
- **AC-3 [measurement] — MET.** §3.2: six runs, bases, lengths, and the sum.
- **AC-4 [state-comparable] — MET.** 715 non-black bytes in rows 168-199 against the cel arm's 0,
  and **Jay: "it is readable."**
- **AC-5 [state-comparable] — NOT MET.** ★★★ The scroll does not work and the census is flat. §3.5.
- **AC-6 [state-comparable] — NOT MET.** ★★★ **The key arbitration was not built.** Both polls now
  exist in one binary and both read the matrix; the title screen does not exercise it because the
  prompt is disabled there, but room 1 with a prompt would. §8.3.
- **AC-7 [byte-comparable] — MET.** All seven existing arms byte-identical; the `p3b` gate green.
- **AC-8 [byte-comparable · gate] — MET, fresh.** `p3b` · `comp 124/124` · `cel 9,193/9,193` ·
  `pic 45/45` · `res 1,264/1,264`. `vm` cited under §2T.
- **AC-9 [fault injection] — NOT RUN.** `TEXT_WIRED` undefined in a combined build is buildable but
  was not exercised; ★★ its red — the copyright missing — is what Jay reported two tasks ago, so it
  is a citation and not a demonstration.
- **AC-10 [eye gate — Jay] — MET, and it produced four results.** §1. ★★★ **Offered before the byte
  gates**, twice — the second time after the font fix.
- **AC-11 [suite] — PARTIAL.** Five gates green; `p3b_rescheck` and `-CelCheck` not re-run this
  task. ★ `$44` is not on this list, per P6.65.
- **AC-12 [manifest] — PARTIAL.** ★★ The eighth arm is **in `p3b_arms_check.ps1`** with its flags and
  hash. **No `gates.manifest` row** — §7.5. ★ Its summary line still says *"all 7 shipped arms"*
  while listing eight; cosmetic, noted.
- **AC-13 [tooling] — MET.** `hal-sync OK (11 files, both siblings)` · `reg-discipline 17 in 1 file`
  · `gen_vm_tables CHECK OK` · `fix_mojibake` clean on all four edited files.
- **AC-14 — MET.** §10.

### 5 — Verdict-time evidence (v0.7 §11)

```
$ lwasm ... -DP3B_COMBINED -DP3B_IRQ           -> 18393 B 89837FCA   (no overrun escape)
   P3_TEXTB_BASE $EBBA  P3_TEXTB_END $F477  P3_CODE_END $5944  P3_VOCAB $A000
$ lwasm ... -DHAL_KEYBOARD                     -> 15266 B 5AA65B69   (cel, unchanged)
$ lwasm ... -DP3B_NO_CEL -DHAL_KEYBOARD -DP3B_IRQ -> 16429 B 3250E5CF (text, unchanged)
$ lwasm ... -DP3B_COMBINED -DTEXT_VOCAB_FLAT
   ERROR: "a COMBINED build's vocabulary window OVERLAPS the relocated text engine ..."   ★ RED

$ p3b_show.ps1 -Combined -Headless
   poked 2184/$2000 code | 626/$0200 vm_tables | 12133/$2888 code
       | 2237/$EBBA text.s (relocated, slot 7) | 343/$57ED code | 870/$E000 parser
   program 18393 bytes in 6 run(s)
   font 2048 of 2048 bytes -> P3_FONT $E3BA (256 glyphs)
   text area rows 168-199: 715 of 5120 bytes non-black
   160/300 cycles, no stall, err 0

$ p3b_arms_check.ps1 -> eight arms, all OK (p3b_comb 18393 89837FCA)
$ run_gates.sh p3b/comp/cel/pic/res -> all green
$ hal_sync_check.py -> OK (11 files, POP3_port + karateka_coco3)
$ git diff --stat -- src/hal/ src/engine/memmap.inc -> (empty)
```

**25.3 operator-runtime-smoke:** ★★★★★ **PASSED with findings — Jay, live, RGB, KQ1 title, 400
cycles at 99.63% and 99.68%.** *"the text is garbled"* → font fixed → *"it is readable. however the
copyright shouldn't appear until the title screen is rendered. also, the text still doesn't scroll
and i see a 'press a key to continue' in the text area which doesn't appear in the oracle."*

### 6 — Reactive deviations and route accounting

★★★ **No §6 trigger fired.** The fifth — *"the copyright still does not draw"* — **did not**: it
draws and is readable. The scroll is §4E's *"what stops them is the finding"*, and §3.4 is that
finding for the ordering.

★★★★ **§4C was not done.** The key arbitration is written down [P6.63 §3.4] and remains unbuilt;
this task reached it for the first time and spent its budget on the relocation and on three
self-inflicted defects. **Named, not quietly dropped.**

**Route accounting.** ★★★ **§4A, §4B and §4D were implemented in full; §4E was measured and
reported; §4C and §4F were not started.** §4F's seed-stack high-water is still owed from P6.64.

★ **One method note:** the eye gate was offered **twice** — once garbled, once readable — and the
second offer named exactly what had changed, so Jay's reply separates the font fix from the three
remaining defects rather than blending them.

### 7 — Uncertainty flags

1. ★★★★ **The scroll's cause is unknown.** §3.5. Two explanations fit the flat census and only an
   instrument that can see the picture area distinguishes them.
2. ★★★★ **The 'press a key' line is unexplained.** `configure.screen` is a suspect, not a finding.
3. ★★★ **The key arbitration is unbuilt and the combined arm has two matrix readers.** The title
   screen does not exercise it; **room 1 with a prompt will.**
4. ★★★ **AC-2's stale-base check is asserted and undemonstrated** — not command-line reachable.
5. ★★ **The combined arm has no `gates.manifest` row**, so nothing states what it does and does not
   cover [L-121]. ★★★ **That is how `p3b` ran a broken sprite path while green for twenty tasks.**
6. ★★ **`p3b_rescheck`/`-CelCheck` not re-run** this task.
7. ★ **The straddle clamp** — tenth task.

### 8 — Follow-up candidates

1. ★★★★★ **Implement `draw.pic` / `show.pic` / `configure.screen`.** §3.4. ★★★★ **This is the
   ordering defect, the likeliest cause of the 'press a key' line, and plausibly the scroll as
   well** — three of Jay's four observations behind three opcodes.
2. ★★★★★ **A `gates.manifest` row for the combined arm**, with what it can and cannot gate. §7.5.
3. ★★★★ **The key arbitration** — §4C, third task carrying it, and now reachable.
4. ★★★ **An instrument that can see the picture area's text**, so the scroll question has a byte
   answer and not only an eye. §7.1.
5. ★★★ **The seed-stack high-water** — §4F, owed since P6.64.
6. ★★ **The straddle clamp** — tenth task.
7. ★ **`p3b_arms_check.ps1`'s summary says "7 shipped arms" while listing eight** — one string.
8. ★ `MAP_PRI_BANDS` — **fourteenth task**, and it is at `$E000`, in the region this task just
   started using.

### 9 — User interaction during task

1. ***"the text is garbled. and it does not scroll"*** — ★★★★★ **the garbling was the unstaged font
   (§3.6) and was fixed within the task.**
2. ***"it is readable. however the copyright shouldn't appear until the title screen is rendered.
   also, the text still doesn't scroll and i see a 'press a key to continue' in the text area which
   doesn't appear in the oracle"*** — ★★★★★ **four results in one sentence**, one of which (§3.4)
   was traceable to three modelled opcodes in a single grep.

★★ **The eye gate has now produced findings on nine consecutive tasks**, and on this one it caught
a defect — the font — that every byte gate passed.

### 10 — Candidate(s) captured this task

- `seeds/AGI/live/2026-09-20-a-region-owned-by-one-symbol-shows-nothing-inside-it.md`
- `seeds/AGI/live/2026-09-20-the-rule-you-just-wrote-down-is-the-one-you-break-next.md`

### 11 — Commit

`<this report>` — pushed to origin/wip before reporting.
