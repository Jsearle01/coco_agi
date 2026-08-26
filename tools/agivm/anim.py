"""updateScreenObjTable() and updatePosition() -- the per-cycle animation update.

★★ THIS SUBSYSTEM WRITES VM VARIABLES, WHICH IS WHY IT IS HERE AT ALL. It looks like
presentation and is not: updatePosition() sets VM_VAR_BORDER_TOUCH_EGO, VM_VAR_BORDER_CODE and
VM_VAR_BORDER_TOUCH_OBJECT, and it moves objects that `posn`/`get.posn` then read back. The
first VM built without it matched the oracle on 434 cycles of KQ1 in every variable but two --
and both of those were ego's y, reaching the scripts through get.posn.

★★ ONE DECLARED HOLE, AND IT IS NAMED RATHER THAN PAPERED OVER. ScummVM's updatePosition ends
with:

    if (checkCollision(screenObj) || !checkPriority(screenObj)) { rollback; fixPosition(); }

checkCollision needs the block rectangle and the other objects; checkPriority needs the
PRIORITY SCREEN, which this VM does not build. Both are treated as "passes" here, so an object
moved somewhere the priority screen forbids stays there instead of being rolled back. For a
static screen with nothing walking around, the two are equivalent. For a room with a walking
ego they are not, and the state diff is the instrument that will say so.

Not a licence to leave it: it is a boundary with a known shape, recorded so a later divergence
is recognised as this and not mistaken for a fresh defect.

★★ MEASURED AT P4.1 -- THE SECOND HOLE IS THE ONE THAT MATTERS, AND IT IS THE ONLY THING LEFT.
updateView() advances the cel within a loop and, when a kCycleEndOfLoop / kCycleRevLoop
animation reaches its last cel, SETS THE SCRIPT'S COMPLETION FLAG (view.cpp:70,85). motion.cpp
does the same for move.obj (272,285) and follow.ego (173). All four need either VIEW cel counts
or the motion system, and this VM has neither.

State diff against the pinned oracle, three titles, all 256 variables and all 256 flags:

    Kingquest1  0x2917   434 cycles   vars: ALL MATCH   flags: flag 20 from cycle 186
    Kingquest2  0x2917   156 cycles   vars: ALL MATCH   flags: flag 33 from cycle 49
    Kingquest3  0x2440   679 cycles   vars: ALL MATCH   flags: flag 221 from cycle 6

★ And the shared cause was CHECKED, not assumed: each of those three flags is an argument to
end.of.loop / reverse.loop / move.obj / follow.ego in the game's own scripts -- 35, 23 and 31
call sites respectively. So this is ONE defect with three symptoms, not three defects. The fix
is a VIEW parser plus motion.cpp, and until it lands these divergences are expected.
"""

from .optable import (fAnimated, fUpdate, fDrawn, fUpdatePos, fFixLoop, fCycling,
                      fIgnoreHorizon, fOnWater, fOnLand,
                      VM_VAR_BORDER_CODE, VM_VAR_BORDER_TOUCH_EGO,
                      VM_VAR_BORDER_TOUCH_OBJECT, kMotionMoveObj)
from .state import SCREENOBJECTS_EGO_ENTRY

SCRIPT_WIDTH = 160
SCRIPT_HEIGHT = 168

# view.cpp loopTable2 / loopTable4, indexed by direction 0-8.
LOOP_TABLE_2 = (4, 4, 0, 0, 0, 4, 1, 1, 1)
LOOP_TABLE_4 = (4, 3, 0, 0, 0, 2, 1, 1, 1)

# updatePosition's direction deltas, indexed by direction 0-8.
DX = (0, 0, 1, 1, 1, 0, -1, -1, -1)
DY = (0, -1, -1, 0, 1, 1, 1, 0, -1)

_ACTIVE = fAnimated | fUpdate | fDrawn


def update_screen_obj_table(vm):
    st = vm.state
    change_count = 0

    for o in st.screen_objs:
        if (o.flags & _ACTIVE) != _ACTIVE:
            continue
        change_count += 1

        loop_nr = 4
        if not (o.flags & fFixLoop):
            if o.numLoops in (2, 3):
                loop_nr = LOOP_TABLE_2[o.direction]
            elif o.numLoops == 4:
                loop_nr = LOOP_TABLE_4[o.direction]

        if loop_nr != 4 and loop_nr != o.loop:
            if vm.version <= 0x2272 or o.stepTimeCount == 1:
                o.loop = loop_nr

        if o.flags & fCycling:
            if o.cycleTimeCount:
                o.cycleTimeCount -= 1
                if o.cycleTimeCount == 0:
                    # updateView() advances the cel within the loop. It needs the VIEW
                    # resource's cel count, which this VM does not parse, so the cel is left
                    # alone. Declared: a script reading current.cel will diverge.
                    o.cycleTimeCount = o.cycleTime

    if change_count:
        update_position(vm)
        st.ego().flags &= ~(fOnWater | fOnLand)


def update_position(vm):
    st = vm.state
    vm.set_var(VM_VAR_BORDER_CODE, 0)
    vm.set_var(VM_VAR_BORDER_TOUCH_EGO, 0)
    vm.set_var(VM_VAR_BORDER_TOUCH_OBJECT, 0)

    for idx, o in enumerate(st.screen_objs):
        if (o.flags & _ACTIVE) != _ACTIVE:
            continue

        if o.stepTimeCount > 1:
            o.stepTimeCount -= 1
            continue
        o.stepTimeCount = o.stepTime

        x = old_x = o.x
        y = old_y = o.y

        if not (o.flags & fUpdatePos):
            x += o.stepSize * DX[o.direction]
            y += o.stepSize * DY[o.direction]

        border = 0

        # ★ left border: version 0x3086 (KQ4's interpreter) compares <= 0, every other
        # version compares < 0. Transcribed rather than normalised -- it is a real
        # per-version behavioural difference, not a ScummVM quirk.
        if vm.version == 0x3086:
            if x <= 0:
                x = 0
                border = 4
        else:
            if x < 0:
                x = 0
                border = 4

        if not border:
            if x + o.xSize > SCRIPT_WIDTH:
                x = SCRIPT_WIDTH - o.xSize
                border = 2

        if y - o.ySize < -1:
            y = o.ySize - 1
            border = 1
        elif y > SCRIPT_HEIGHT - 1:
            y = SCRIPT_HEIGHT - 1
            border = 3
        elif (not (o.flags & fIgnoreHorizon)) and y <= st.horizon:
            y = st.horizon + 1
            border = 1

        o.x = x
        o.y = y
        # checkCollision() / checkPriority() rollback omitted -- see module docstring.

        if border:
            if idx == SCREENOBJECTS_EGO_ENTRY:
                vm.set_var(VM_VAR_BORDER_TOUCH_EGO, border)
            else:
                vm.set_var(VM_VAR_BORDER_CODE, o.objectNr)
                vm.set_var(VM_VAR_BORDER_TOUCH_OBJECT, border)
            if o.motionType == kMotionMoveObj:
                o.motionType = 0        # motionMoveObjStop -> kMotionNormal

        o.flags &= ~fUpdatePos
