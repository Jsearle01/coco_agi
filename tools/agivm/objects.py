"""The screen-object table: view/loop/cel binding, position clipping, and the per-cycle update.

Supersedes the P4.1 stub `anim.py`, which modelled this well enough to prove the VM's variable
handling correct and declared what it could not do. This is that declaration discharged.

Transcribed from the pinned oracle:
  setView / setLoop / setCel / clipViewCoordinates   view.cpp 419-560 region
  updateView (cel cycling + COMPLETION FLAGS)        view.cpp 98-155
  updateScreenObjTable                               view.cpp 657-733
  updatePosition                                     checks.cpp 187-289
  fixPosition                                        checks.cpp 300-360

★★ THE COMPLETION FLAGS ARE THE POINT OF THIS FILE. updateView() sets the script's flag when a
kCycleEndOfLoop / kCycleRevLoop animation reaches its last cel (view.cpp:70,85). P4.1's VM
matched the oracle on all 256 variables for three titles and diverged on exactly one flag each
-- 20, 33 and 221 -- and every one of those is such a flag. Nothing here is cosmetic.

★ STILL DECLARED ABSENT, and named so a later divergence is recognised rather than re-diagnosed:
fixPosition's spiral search and updatePosition's collision/priority rollback both need the
PRIORITY SCREEN, which this VM does not build. Both are treated as "passes". For a screen with
nothing walking into an obstacle they are equivalent; for one where an object is pushed out of
a forbidden band they are not.
"""

from .optable import (fAnimated, fUpdate, fDrawn, fUpdatePos, fFixLoop, fCycling,
                      fIgnoreHorizon, fOnWater, fOnLand, fDontUpdate,
                      kCycleNormal, kCycleEndOfLoop, kCycleRevLoop, kCycleReverse,
                      kMotionMoveObj, kMotionNormal,
                      VM_VAR_BORDER_CODE, VM_VAR_BORDER_TOUCH_EGO,
                      VM_VAR_BORDER_TOUCH_OBJECT,
                      LOOP_TABLE_2, LOOP_TABLE_4, DIR_DX, DIR_DY)
from .state import SCREENOBJECTS_EGO_ENTRY

SCRIPT_WIDTH = 160
SCRIPT_HEIGHT = 168

_ACTIVE = fAnimated | fUpdate | fDrawn


# ── view / loop / cel binding ──────────────────────────────────────────────────────────────
def set_view(vm, obj, view_nr):
    """view.cpp setView(). ★ NOT an assignment -- it walks into setLoop -> setCel ->
    clipViewCoordinates, and that chain is what gives an object its size and clamps its y."""
    view = vm.load_view(view_nr)
    obj.view = view_nr
    obj.numLoops = view.loop_count

    if obj.loop >= obj.numLoops:
        set_loop(vm, obj, 0)
    else:
        set_loop(vm, obj, obj.loop)


def set_loop(vm, obj, loop_nr):
    """view.cpp setLoop(), including the out-of-range CLIP rather than an error."""
    view = vm.load_view(obj.view)
    if obj.numLoops == 0:
        return                      # warning() in the oracle; no state change either way

    if loop_nr >= obj.numLoops:
        # ★ The oracle clips rather than erroring, and carries a KQ1-specific workaround for
        # view 71 (bowing to the king, Bug #7045) that re-sets the view instead. That
        # workaround is a §2.1 NORMALISATION -- not reproduced. It fires only for KQ1 view 71
        # loop 1; if a KQ1 divergence ever appears at that moment, this is why.
        loop_nr = obj.numLoops - 1

    obj.loop = loop_nr
    obj.numCels = len(view.loops[loop_nr].cels)

    if obj.cel >= obj.numCels:
        set_cel(vm, obj, 0)
    else:
        set_cel(vm, obj, obj.cel)


def set_cel(vm, obj, cel_nr):
    """view.cpp setCel(). Sets xSize/ySize from the cel, then clips coordinates."""
    view = vm.load_view(obj.view)
    if obj.numLoops == 0:
        return
    loop = view.loops[obj.loop]
    if len(loop.cels) == 0:
        return                      # oracle warns and returns

    if cel_nr >= obj.numCels:
        cel_nr = obj.numCels - 1    # oracle clips (KQ3 Apple IIgs plank death, Bug #5832)

    obj.cel = cel_nr
    cel = loop.cels[cel_nr]
    obj.xSize = cel.width
    obj.ySize = cel.height
    clip_view_coordinates(vm, obj)


def clip_view_coordinates(vm, obj):
    """view.cpp clipViewCoordinates()."""
    st = vm.state
    if obj.x + obj.xSize > SCRIPT_WIDTH:
        obj.flags |= fUpdatePos
        obj.x = SCRIPT_WIDTH - obj.xSize
    if obj.y - obj.ySize + 1 < 0:
        obj.flags |= fUpdatePos
        obj.y = obj.ySize - 1
    if obj.y <= st.horizon and not (obj.flags & fIgnoreHorizon):
        obj.flags |= fUpdatePos
        obj.y = st.horizon + 1


def fix_position(vm, obj):
    """checks.cpp fixPosition() -- THE HORIZON CLAMP ONLY.

    Step 2 of the oracle's version spirals outward until checkPosition / checkCollision /
    checkPriority all pass, and all three need the priority screen. Declared absent.
    """
    if not (obj.flags & fIgnoreHorizon) and obj.y <= vm.state.horizon:
        obj.y = vm.state.horizon + 1


# ── the cel cycler, and the completion flags ───────────────────────────────────────────────
def update_view(vm, obj):
    """view.cpp updateView(). ★★ This is where end.of.loop / reverse.loop set their flag."""
    if obj.flags & fDontUpdate:
        obj.flags &= ~fDontUpdate
        return

    cel_nr = obj.cel
    last_cel_nr = obj.numCels - 1

    if obj.cycle == kCycleNormal:
        cel_nr += 1
        if cel_nr > last_cel_nr:
            cel_nr = 0

    elif obj.cycle == kCycleEndOfLoop:
        advanced = False
        if cel_nr < last_cel_nr:
            cel_nr += 1
            if cel_nr != last_cel_nr:
                advanced = True
        if not advanced:
            # ★ ignore_loop_flag is a SCUMMVM DEVIATION (§2.1). motion.cpp:83-102 sets it when
            # a motion overwrote the cycler's flag field, and the oracle then declines to set
            # the resulting flag -- its own comment says "the original would set an unintended
            # game flag ... we do not set any flag". Reproduced because we diff against the
            # ORACLE; it is NOT a claim about Sierra's interpreter, and KQ1 room 22 (the
            # eagle) is among the moments it changes.
            if not obj.ignore_loop_flag:
                vm.state.set_flag(obj.loop_flag, True)
            obj.flags &= ~fCycling
            obj.direction = 0
            obj.cycle = kCycleNormal

    elif obj.cycle == kCycleRevLoop:
        advanced = False
        if cel_nr:
            cel_nr -= 1
            if cel_nr:
                advanced = True
        if not advanced:
            if not obj.ignore_loop_flag:
                vm.state.set_flag(obj.loop_flag, True)
            obj.flags &= ~fCycling
            obj.direction = 0
            obj.cycle = kCycleNormal

    elif obj.cycle == kCycleReverse:
        if cel_nr == 0:
            cel_nr = last_cel_nr
        else:
            cel_nr -= 1

    set_cel(vm, obj, cel_nr)


# ── the per-cycle update ───────────────────────────────────────────────────────────────────
def update_screen_obj_table(vm):
    """view.cpp updateScreenObjTable()."""
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
            # ★ The oracle has a fifth branch: for version 0x3086 or GID_KQ4 it uses
            # loopTable4 for ANY loop count. Neither applies to the pinned v2 corpus, and it
            # is not reproduced -- named here so its absence is a decision, not an oversight.

        if loop_nr != 4 and loop_nr != o.loop:
            if vm.version <= 0x2272 or o.stepTimeCount == 1:
                set_loop(vm, o, loop_nr)

        if o.flags & fCycling:
            if o.cycleTimeCount:
                o.cycleTimeCount -= 1
                if o.cycleTimeCount == 0:
                    update_view(vm, o)
                    o.cycleTimeCount = o.cycleTime

    if change_count:
        update_position(vm)
        st.ego().flags &= ~(fOnWater | fOnLand)


def update_position(vm):
    """checks.cpp updatePosition()."""
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

        x = o.x
        y = o.y

        if not (o.flags & fUpdatePos):
            x += o.stepSize * DIR_DX[o.direction]
            y += o.stepSize * DIR_DY[o.direction]

        border = 0

        # ★ version 0x3086 (KQ4's interpreter) compares x <= 0; every other version x < 0.
        # A real per-version behavioural difference, transcribed rather than normalised.
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
        # checkCollision()/checkPriority() rollback omitted -- needs the priority screen.

        if border:
            if idx == SCREENOBJECTS_EGO_ENTRY:
                vm.set_var(VM_VAR_BORDER_TOUCH_EGO, border)
            else:
                vm.set_var(VM_VAR_BORDER_CODE, o.objectNr)
                vm.set_var(VM_VAR_BORDER_TOUCH_OBJECT, border)
            if o.motionType == kMotionMoveObj:
                from . import motion
                motion.motion_move_obj_stop(vm, o)

        o.flags &= ~fUpdatePos
