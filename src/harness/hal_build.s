* src/harness/hal_build.s
*
* P3.1 build unit for the adopted HAL, modelled on POP's src/harness/hal_build.s.
* Assembles every HAL module coco_agi takes, so the build proves the adopted
* contract still builds. NOT engine code and NOT a driver -- it has no entry
* point and is never executed.
*
* ★ src/engine/** stays EMPTY this task and reg_discipline.py stays at 0. This
* file lives under src/harness/, which the register census excludes by design
* (CLAUDE.md §2N: probes are counted separately, and allowlisted by explicit
* filename rather than by pattern).
*
* ★ The HAL here was copied from POP3_port @ 282a65cf9c79739326e101b3d7cccffc8cff2daa
* (recorded per dispatch §4.2 -- without the source commit, "inherit fixes
* deliberately" becomes guesswork). hal_globals.s is PROJECT_LOCAL and is the
* one file permitted to diverge.
                ifdef   OBJTARGET
                else
                org     $2000
                endc
                include "src/hal/coco3-dsk/hal_globals.s"
                include "src/hal/coco3-dsk/sys.s"
                include "src/hal/coco3-dsk/time.s"
                include "src/hal/coco3-dsk/irq_vbl.s"
                include "src/hal/coco3-dsk/gfx.s"
                include "src/hal/coco3-dsk/input.s"
                include "src/hal/coco3-dsk/sound.s"
                include "src/hal/coco3-dsk/file.s"
                include "src/hal/coco3-dsk/mem.s"
                include "src/hal/coco3-dsk/disk_read.s"
                end
