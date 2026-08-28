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
