# docs/gates/ — artifacts a human has to look at

★★ **Everything here is for an eye gate (CLAUDE.md §4) and is tracked on purpose.** `build/` is
gitignored, so an artifact left there is invisible to anyone reading the repo — including the
Orchestrator, who fetches the tree rather than a description of it (§2E).

★★★ **Why images are allowed here at all, when T-P0-025 §11 puts "renderings or screenshots"
out of scope.** That ban exists because a rendering of a room *is* game data — Sierra's
copyrighted content in another wrapper. **These are not renderings of anything.** AC-12's
swatches are sixteen blocks of a known palette index, and the reference strip is synthesised
from EGA's published RGB values. Jay's note adds the ruling explicitly:

> ★ **AC-12 needs no game data** — sixteen blocks of a known index. ★★ **Which also means it is
> not copyrighted content and the capture can be handled normally.**

★ **So the test is not "is it a PNG", it is "does it contain game content".** A room capture
still does not belong in the repo and never will.

---

## AC-11 — the palette write path

`AC11-palette-readback.txt` — what `$FFB0`–`$FFBF` held after `pal_load`, read back **by the
guest** and masked to the low 6 bits.

★★ **The mask is documented, not discovered:** *"These registers can also be read to determine
what palettes are set but like the MMU registers, the upper 2 bits must be masked out."*
[ref: `docs/ground-truth/SockmasterGime.md` — "FFB0-FFBF Color palette registers"]. Without it
the comparison reports sixteen false mismatches.

★ **This proves the intended values LANDED. It does not prove they are the right colours.**

## AC-12 — the palette values

| file | what it is |
|---|---|
| `AC12-coco3-palette-swatches-rgb.png` | the **CoCo3**, RGB monitor (`screen_config=1`), captured from MAME |
| `AC12-reference-ega.png` | the **EGA reference**, synthesised from EGA's 16 RGB values |

**Both run index 0 at the left through index 15 at the right. Band 6 is brown** — the entry a
"double the CGA bit" conversion silently turns into dark yellow.

★★★ **THE BANDS DO NOT LINE UP HORIZONTALLY.** The CoCo3 capture is the whole MAME screen
*including the border*; the AGI picture is 320 px wide inside it. The two images share the
**order and the count, not the geometry** — count six bands in from the left in each. Finding
the border inset would mean reading pixels, which §3 forbids.

★ **A saturation difference is expected; a hue difference is not.** The GIME has four levels per
channel and EGA's values (`$00`/`$55`/`$AA`/`$FF`) land exactly on them, so the encoding is
lossless for these sixteen colours.

★★ **Neither image was interpreted by Clyde** (§3). The reference was synthesised; from the
capture only the IHDR width and height were read.

---

## AC-9 (T-P0-028) — does a sprite go BEHIND scenery?

**PoliceQuest1, frame 306.** One sprite, **212 pixels drawn and 196 refused** by the priority
test — split almost exactly in half, which is what makes the decision visible.

| file | what it is | §2P |
|---|---|---|
| **`pq1-frame306.decision.png`** | ★★★ **read this one** — every sprite pixel coloured by OUTCOME | ours |
| `pq1-frame306.priority.png` | the priority screen after compositing, one colour per depth band | ours |
| `build/gate-ac9/pq1-frame306.coco3.png` | the CoCo3's composited frame | **game content — not committed** |
| `build/gate-ac9/pq1-frame306.oracle.png` | the oracle's rendering of the same frame | **game content — not committed** |

### ★★★ How to read `decision.png`

| colour | meaning |
|---|---|
| **GREEN** | the sprite was **drawn** — the priority test found scenery *behind* it |
| **RED** | the sprite was **refused** — scenery is *in front*, so it is hidden |
| grey | the depth map before compositing; **lighter = nearer** |

★★ **The green/red boundary IS the occlusion edge.** The sprite occupies rows 61–70, columns
50–101 — a single 52×10 strip crossing a depth boundary, so its left part is drawn and its right
part is hidden. **If the priority test were inverted, green and red would simply swap**, which is
instantly visible and is exactly what AC-4 proved a byte gate can miss on two of five titles.

### ★★ Why `priority.png` alone was not enough

It shows the depth map — correct, and nearly illegible for this question. On this frame the
sprite is **588 of 26,880 pixels (2%)**, and the 196 pixels where it was **refused** are not in
that image *at all*, because refusing means nothing was drawn. **The one thing the gate exists to
show is the part that picture cannot contain.** It is kept because it shows the scenery's own
depth structure; `decision.png` is the one that answers the question.

### ★ Why this frame, and what the corpus does not contain

`harness/tools/comp_pick.py` scored all **1,679** frames:

| | frames | |
|---|---|---|
| **zero** priority rejections | **1,545** | **92%** — every sprite in front of everything |
| a sprite **partly** occluded | **99** | 5.9% |
| a **tall** partly-occluded sprite | **0** | ★★ none in the corpus |

★★ **Every partly-occluded sprite in the captured window is a wide, short shape** (aspect ≈ 0.19)
— in Police Quest, a vehicle passing behind scenery. **There is no "character walking behind a
tree" frame to show**, which is §7.8's capture-window limit, measured.

★★ **Scored per SPRITE, and the first version was per frame — which was wrong.** SpaceQuest-1
frame 029 topped the per-frame ranking (575 rejected, 564 written) and contains **no
partly-occluded sprite**: one is entirely hidden, a *different* one entirely in front. A
per-frame total cannot tell that from "half a sprite is behind scenery".

### ★★★ OBSERVED BY JAY, 2026-08-29 — and it matches the buffers

> *"the green appears in the darker black area and the red appears in the upper lighter gray
> area."*

**Correct, and it is the discriminating observation.** Confirmed against the plane buffers
afterwards, not asserted from memory:

| Jay saw | buffers | rule |
|---|---|---|
| green on the **darker** grey | 212 px, all over band **4**, grey level 56, rows **66–70** | 4 ≤ 5 → **draw** |
| red on the **upper lighter** grey | 196 px, all over band **8**, grey level 88, rows **61–65** | 8 > 5 → **refuse** |

★★ The sprite is priority 5 and straddles a depth boundary at row 65/66: its **upper half is
behind** near scenery and hidden, its **lower half in front of** far scenery and drawn. Higher
band = nearer, and the ramp is `24 + band*8`, so nearer scenery is lighter — which is why the
refused pixels sit on the lighter grey.

★★★ **An inverted priority test would swap them** — green on the light grey, red on the dark.
That is the fault AC-4 proved a byte gate misses on two of five titles, so this observation is
the thing 100/100 byte-identical could not establish.

### ★★★ Launch path, and what this does NOT discharge

**`poke` + `static-png`, RGB.** §4: *"MOTION-BEARING gates require a LIVE run, not a still... For
AGI this includes sprite compositing, priority interactions."* Both are named. This verifies
**one frame's endpoint** and **cannot show motion**. **AC-9 is recorded as `static-png`, NOT as
PASSED**; a live run remains outstanding.

★★ **Clyde interpreted none of the four images** (§3). Every number here comes from the plane
buffers and the cel, not from a rendered PNG.

---

