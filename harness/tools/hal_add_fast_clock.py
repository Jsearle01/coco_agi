#!/usr/bin/env python3
"""harness/tools/hal_add_fast_clock.py -- land the fast-clock step in all three HAL trees at once.

★★★ §2M: A CHANGE TO A SHARED FILE LANDS IN EVERY REPO OR IN NONE. This script edits
src/hal/coco3-dsk/sys.s in coco_agi, POP3_port and karateka_coco3 in one action, so the three
cannot be left in a drifted state by a partial edit.

★★ IT PRESERVES EACH TREE'S LINE ENDINGS. karateka_coco3's copy is CRLF and coco_agi's is LF;
hal_sync_check.py normalises EOL and is the contract (§2M.1), so the difference is legitimate and
must survive this edit. A naive rewrite would flip Karateka's file to LF -- not drift by the
checker's definition, but a gratuitous whole-file diff in a sibling repo.

★★★ THE ADDITION IS GUARDED AND THE GUARD IS THE POINT (§2M.3). The block is byte-identical in
all three trees; only coco_agi defines HAL_SYS_FAST_CLOCK, so only coco_agi assembles it. POP's
and Karateka's artifacts are therefore expected to be BYTE-UNCHANGED, which is a checkable claim
and is checked in the report rather than asserted.

★ Idempotent: re-running is a no-op once the block is present.
"""
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

REPOS = ["C:/Projects/coco_agi", "C:/Projects/POP3_port", "C:/Projects/karateka_coco3"]
REL = "src/hal/coco3-dsk/sys.s"

ANCHOR = """        puls    u,y                     ; restore U, Y per contract
        andcc   #$FE                    ; CC.C clear = success"""

BLOCK = """* Step 5: SAM CPU clock -- 1.7898 MHz.
*
* PROJECT-SELECTED AND GUARDED. The block is byte-identical in all three HAL
* trees (2M: a change to a shared file lands in every repo or in none); only a
* project that defines HAL_SYS_FAST_CLOCK assembles it. POP and Karateka do not,
* so their artifacts are unchanged by this addition -- 2M.3's "a guard is the
* mechanism that lets identical source assemble differently".
*
* WHY AGI NEEDS IT HERE AND THE SIBLINGS DO NOT. The 1.78 MHz write already
* existed in gfx.s, inside HAL_gfx_set_mode. POP and Karateka select a graphics
* mode during boot, so they reach fast mode before anything is timed. AGI runs
* its VM before any mode is selected, so an AGI harness that calls only
* HAL_sys_init runs at 0.894 MHz -- which is exactly what happened: T-P0-024
* calibrated the resource layer at 0.8937 MHz while the fill work measured at
* 1.7898, and the two subsystems' figures would not have composed.
*
* Same write and same provenance as gfx.s step 8:
* [ref: GFXMODE3.ASM line 36 - STA $FFD9 (A=0, 1.78 MHz clock)]
* Any write to $FFD9 sets the SAM speed bit; the value is irrelevant. `sta` is
* used rather than `clr` because `clr` extended performs a read cycle at the
* address first, and SAM control addresses respond to accesses, not just writes.
        ifdef   HAL_SYS_FAST_CLOCK
        clra
        sta     $FFD9                   ; SAM: 1.7898 MHz CPU clock
        endc

"""


def main():
    rc = 0
    for repo in REPOS:
        p = pathlib.Path(repo) / REL
        raw = p.read_bytes()
        crlf = b"\r\n" in raw
        text = raw.decode("utf-8", errors="replace").replace("\r\n", "\n")

        if "HAL_SYS_FAST_CLOCK" in text:
            print("%-28s already present -- no change" % pathlib.Path(repo).name)
            continue
        if text.count(ANCHOR) != 1:
            print("%-28s ★★★ anchor found %d times, expected 1 -- NOT EDITED"
                  % (pathlib.Path(repo).name, text.count(ANCHOR)))
            rc = 1
            continue

        text = text.replace(ANCHOR, BLOCK + ANCHOR)
        out = text.replace("\n", "\r\n") if crlf else text
        p.write_bytes(out.encode("utf-8"))
        print("%-28s inserted (%s, %d -> %d bytes)"
              % (pathlib.Path(repo).name, "CRLF" if crlf else "LF", len(raw), len(out.encode())))
    return rc


if __name__ == "__main__":
    sys.exit(main())
