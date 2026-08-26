"""The V2 command opcodes.

Transcribed from the pinned oracle's op_cmd.cpp. Three statuses, and the distinction is
load-bearing rather than bookkeeping:

  IMPLEMENTED   the opcode writes VM state the diff can see. Must be exact.
  MODELLED      the opcode only drives presentation (drawing, sound, text, menus). Executing
                it changes nothing the diff observes, so doing nothing is FAITHFUL here --
                but it is declared, not assumed, and a MODELLED opcode that turns out to
                write a variable is a defect this file is expected to catch.
  UNIMPLEMENTED anything not bound below. Reaching one RAISES.

★★ WHY UNIMPLEMENTED MUST RAISE. A VM that silently ignores unknown opcodes still consumes
their parameter bytes and keeps running, so the state diff drifts for a reason the diff cannot
attribute -- the first divergent cycle then names a symptom, not a cause. Backlog L-23.

★ §2.1 NORMALISATIONS PRESENT IN THIS FILE. ScummVM carries game-specific workarounds inside
opcode bodies. They are NOT transcribed, and each is flagged where it was found:
  - cmdDistance    : a KQ4 zombie-bug workaround keyed on room 16/18 and vars 221-223.
                     ScummVM's own comment says the bug "also happens in the original
                     interpreter", so reproducing it would be reproducing a ScummVM FIX, not
                     AGI behaviour.
  - newRoom        : LSL1 flag-36 and KQ3 flags-193..197 workarounds, plus a Gold Rush copy
                     protection redirect.
None of these fire for a game outside the named titles, so omitting them is invisible for the
rest of the corpus -- but for KQ4/LSL1/KQ3/GoldRush a state diff WILL diverge here, and that
divergence is expected and correct rather than a defect in this VM.
"""

from .dispatch import IMPLEMENTED, MODELLED, OpcodeError
from .optable import (VM_VAR_PREVIOUS_ROOM, VM_VAR_CURRENT_ROOM,
                      VM_VAR_BORDER_TOUCH_OBJECT, VM_VAR_BORDER_CODE,
                      VM_VAR_BORDER_TOUCH_EGO, VM_VAR_EGO_VIEW_RESOURCE,
                      VM_VAR_EGO_DIRECTION, VM_FLAG_NEW_ROOM_EXEC,
                      fDrawn, fAnimated, fUpdate, fIgnoreHorizon, fIgnoreBlocks,
                      fIgnoreObjects, fCycling, fOnWater, fOnLand, fFixLoop,
                      fDontUpdate, fMotion,
                      kMotionNormal, kMotionEgo, kMotionWander, kMotionFollowEgo,
                      kMotionMoveObj,
                      kCycleNormal, kCycleEndOfLoop, kCycleRevLoop, kCycleReverse)

EGO_OWNED = 0xFF
SCRIPT_WIDTH = 160
SCRIPT_HEIGHT = 168


class Impl:
    __slots__ = ("fn", "status")

    def __init__(self, fn, status):
        self.fn = fn
        self.status = status


def _impl(status=IMPLEMENTED):
    def deco(fn):
        return Impl(fn, status)
    return deco


def _nop(name):
    """A MODELLED opcode: presentation only, nothing the diff observes."""
    def fn(vm, p):
        vm.modelled_calls[name] = vm.modelled_calls.get(name, 0) + 1
    return Impl(fn, MODELLED)


# ── arithmetic and assignment ──────────────────────────────────────────────────────────────
# ★ setVar takes a byte in ScummVM, so add/sub/mul/div WRAP mod 256 at the call. increment and
# decrement do NOT wrap -- they clamp. That asymmetry is real and is transcribed, not tidied.
@_impl()
def cmdIncrement(vm, p):
    v = vm.get_var(p[0])
    if v < 0xFF:                      # maxValue is 0xF0 only for version < 0x2000
        vm.set_var(p[0], v + 1)


@_impl()
def cmdDecrement(vm, p):
    v = vm.get_var(p[0])
    if v != 0:
        vm.set_var(p[0], v - 1)


@_impl()
def cmdAssignN(vm, p):
    vm.set_var(p[0], p[1])


@_impl()
def cmdAssignV(vm, p):
    vm.set_var(p[0], vm.get_var(p[1]))


@_impl()
def cmdAddN(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) + p[1]) & 0xFF)


@_impl()
def cmdAddV(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) + vm.get_var(p[1])) & 0xFF)


@_impl()
def cmdSubN(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) - p[1]) & 0xFF)


@_impl()
def cmdSubV(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) - vm.get_var(p[1])) & 0xFF)


@_impl()
def cmdMulN(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) * p[1]) & 0xFF)


@_impl()
def cmdMulV(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) * vm.get_var(p[1])) & 0xFF)


@_impl()
def cmdDivN(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) // p[1]) & 0xFF)


@_impl()
def cmdDivV(vm, p):
    vm.set_var(p[0], (vm.get_var(p[0]) // vm.get_var(p[1])) & 0xFF)


@_impl()
def cmdLindirectN(vm, p):
    # var[ var[p0] ] = p1
    vm.set_var(vm.get_var(p[0]), p[1])


@_impl()
def cmdLindirectV(vm, p):
    # var[ var[p0] ] = var[p1]
    vm.set_var(vm.get_var(p[0]), vm.get_var(p[1]))


@_impl()
def cmdRindirect(vm, p):
    # var[p0] = var[ var[p1] ]   -- opcode 0x0A, named "lindirect" in the table but it is the
    # RIGHT-indirect form. The table name is misleading; the handler name is not.
    vm.set_var(p[0], vm.get_var(vm.get_var(p[1])))


# ── flags ──────────────────────────────────────────────────────────────────────────────────
@_impl()
def cmdSet(vm, p):
    vm.state.set_flag(p[0], True)


@_impl()
def cmdReset(vm, p):
    vm.state.set_flag(p[0], False)


@_impl()
def cmdToggle(vm, p):
    vm.state.set_flag(p[0], not vm.state.get_flag(p[0]))


@_impl()
def cmdSetV(vm, p):
    vm.state.set_flag(vm.get_var(p[0]), True)


@_impl()
def cmdResetV(vm, p):
    vm.state.set_flag(vm.get_var(p[0]), False)


@_impl()
def cmdToggleV(vm, p):
    n = vm.get_var(p[0])
    vm.state.set_flag(n, not vm.state.get_flag(n))


# ── rooms and logic control ────────────────────────────────────────────────────────────────
@_impl()
def cmdNewRoom(vm, p):
    vm.new_room(p[0])


@_impl()
def cmdNewRoomF(vm, p):
    vm.new_room(vm.get_var(p[0]))


@_impl()
def cmdLoadLogic(vm, p):
    vm.load_logic(p[0])


@_impl()
def cmdLoadLogicF(vm, p):
    vm.load_logic(vm.get_var(p[0]))


@_impl()
def cmdCall(vm, p):
    st = vm.state
    old_ip = st.ip
    old_code = st.code
    old_nr = st.cur_logic_nr
    vm.run_logic(p[0])
    st.cur_logic_nr = old_nr
    st.code = old_code
    st.ip = old_ip


@_impl()
def cmdCallF(vm, p):
    cmdCall.fn(vm, bytes([vm.get_var(p[0])]))


# ── screen objects: state the tests read back ──────────────────────────────────────────────
def _obj(vm, n):
    return vm.state.screen_objs[n]


@_impl()
def cmdAnimateObj(vm, p):
    o = _obj(vm, p[0])
    if o.flags & fAnimated:
        return
    o.flags = fAnimated | fUpdate | fCycling
    o.motionType = kMotionNormal
    o.cycle = kCycleNormal
    o.direction = 0


@_impl()
def cmdUnanimateAll(vm, p):
    for o in vm.state.screen_objs:
        o.flags &= ~(fAnimated | fDrawn)


def _fix_position(vm, o):
    """checks.cpp fixPosition() -- THE HORIZON CLAMP ONLY.

    ★★ THIS IS A DECLARED PARTIAL IMPLEMENTATION. The oracle's fixPosition does two things:

      1. if the object does not ignore the horizon and its y is at or above it, push y to
         horizon + 1;
      2. then spiral outward (west, south, east, north, widening) until checkPosition,
         checkCollision and checkPriority all pass.

    Step 2 needs the PRIORITY SCREEN, which this VM does not build -- it has no picture
    renderer attached. So step 2 is absent, and an object placed somewhere the priority screen
    forbids will sit where the oracle would have moved it.

    ★ Step 1 alone is what produced the first real behavioural divergence found by the state
    diff: KQ1's ego sat at y=0 here and y=37 in the oracle, surfacing through
    get.posn(0, v100, v101). horizon is 36 after new.room, so 36 + 1 = 37. Implementing the
    clamp fixes that case honestly; pretending step 2 exists would not.
    """
    if not (o.flags & fIgnoreHorizon) and o.y <= vm.state.horizon:
        o.y = vm.state.horizon + 1
    # step 2 (the spiral search) intentionally absent -- see docstring.


@_impl()
def cmdDraw(vm, p):
    o = _obj(vm, p[0])
    if o.flags & fDrawn:
        return                       # ★ early-out: draw on an already-drawn object is a no-op
    o.flags |= fUpdate
    _fix_position(vm, o)
    o.flags |= fDrawn
    o.flags &= ~fDontUpdate


@_impl()
def cmdErase(vm, p):
    _obj(vm, p[0]).flags &= ~fDrawn


@_impl()
def cmdPosition(vm, p):
    o = _obj(vm, p[0])
    o.x = p[1]
    o.y = p[2]


@_impl()
def cmdPositionF(vm, p):
    o = _obj(vm, p[0])
    o.x = vm.get_var(p[1])
    o.y = vm.get_var(p[2])


@_impl()
def cmdGetPosn(vm, p):
    o = _obj(vm, p[0])
    vm.set_var(p[1], o.x)
    vm.set_var(p[2], o.y)


@_impl()
def cmdReposition(vm, p):
    # ★ dx/dy are SIGNED bytes, and the underflow guard is a clamp to 0 rather than a general
    # clamp to the screen -- transcribed as ScummVM has it, not tidied into a min/max pair.
    o = _obj(vm, p[0])
    dx = vm.get_var(p[1])
    dy = vm.get_var(p[2])
    if dx > 127:
        dx -= 256
    if dy > 127:
        dy -= 256
    o.flags |= 0x0400                      # fUpdatePos
    o.x = 0 if (dx < 0 and o.x < -dx) else o.x + dx
    o.y = 0 if (dy < 0 and o.y < -dy) else o.y + dy
    _fix_position(vm, o)


@_impl()
def cmdRepositionTo(vm, p):
    o = _obj(vm, p[0])
    o.x = p[1]
    o.y = p[2]
    o.flags |= 0x0400
    _fix_position(vm, o)


@_impl()
def cmdRepositionToF(vm, p):
    o = _obj(vm, p[0])
    o.x = vm.get_var(p[1])
    o.y = vm.get_var(p[2])
    o.flags |= 0x0400
    _fix_position(vm, o)


@_impl()
def cmdSetView(vm, p):
    vm.set_view(_obj(vm, p[0]), p[1])


@_impl()
def cmdSetViewF(vm, p):
    vm.set_view(_obj(vm, p[0]), vm.get_var(p[1]))


@_impl()
def cmdSetLoop(vm, p):
    from . import objects
    objects.set_loop(vm, _obj(vm, p[0]), p[1])


@_impl()
def cmdSetLoopF(vm, p):
    from . import objects
    objects.set_loop(vm, _obj(vm, p[0]), vm.get_var(p[1]))


@_impl()
def cmdSetCel(vm, p):
    from . import objects
    objects.set_cel(vm, _obj(vm, p[0]), p[1])


@_impl()
def cmdSetCelF(vm, p):
    from . import objects
    objects.set_cel(vm, _obj(vm, p[0]), vm.get_var(p[1]))


@_impl()
def cmdCurrentCel(vm, p):
    vm.set_var(p[1], _obj(vm, p[0]).cel)


@_impl()
def cmdCurrentLoop(vm, p):
    vm.set_var(p[1], _obj(vm, p[0]).loop)


@_impl()
def cmdCurrentView(vm, p):
    vm.set_var(p[1], _obj(vm, p[0]).view)


@_impl()
def cmdLastCel(vm, p):
    vm.set_var(p[1], max(0, _obj(vm, p[0]).numCels - 1))


@_impl()
def cmdNumberOfLoops(vm, p):
    vm.set_var(p[1], _obj(vm, p[0]).numLoops)


@_impl()
def cmdFixLoop(vm, p):
    _obj(vm, p[0]).flags |= fFixLoop


@_impl()
def cmdReleaseLoop(vm, p):
    _obj(vm, p[0]).flags &= ~fFixLoop


@_impl()
def cmdSetPriority(vm, p):
    o = _obj(vm, p[0])
    o.flags |= 0x0004          # fFixedPriority
    o.priority = p[1]


@_impl()
def cmdSetPriorityF(vm, p):
    o = _obj(vm, p[0])
    o.flags |= 0x0004
    o.priority = vm.get_var(p[1])


@_impl()
def cmdReleasePriority(vm, p):
    _obj(vm, p[0]).flags &= ~0x0004


@_impl()
def cmdGetPriority(vm, p):
    vm.set_var(p[1], _obj(vm, p[0]).priority)


@_impl()
def cmdStopUpdate(vm, p):
    _obj(vm, p[0]).flags &= ~fUpdate


@_impl()
def cmdStartUpdate(vm, p):
    _obj(vm, p[0]).flags |= fUpdate


@_impl()
def cmdForceUpdate(vm, p):
    pass                        # forces a redraw; no diffable state


@_impl()
def cmdIgnoreHorizon(vm, p):
    _obj(vm, p[0]).flags |= fIgnoreHorizon


@_impl()
def cmdObserveHorizon(vm, p):
    _obj(vm, p[0]).flags &= ~fIgnoreHorizon


@_impl()
def cmdSetHorizon(vm, p):
    vm.state.horizon = p[0]


@_impl()
def cmdObjectOnWater(vm, p):
    _obj(vm, p[0]).flags |= fOnWater


@_impl()
def cmdObjectOnLand(vm, p):
    _obj(vm, p[0]).flags |= fOnLand


@_impl()
def cmdObjectOnAnything(vm, p):
    _obj(vm, p[0]).flags &= ~(fOnWater | fOnLand)


@_impl()
def cmdIgnoreObjs(vm, p):
    _obj(vm, p[0]).flags |= fIgnoreObjects


@_impl()
def cmdObserveObjs(vm, p):
    _obj(vm, p[0]).flags &= ~fIgnoreObjects


@_impl()
def cmdIgnoreBlocks(vm, p):
    _obj(vm, p[0]).flags |= fIgnoreBlocks


@_impl()
def cmdObserveBlocks(vm, p):
    _obj(vm, p[0]).flags &= ~fIgnoreBlocks


@_impl()
def cmdDistance(vm, p):
    o1, o2 = _obj(vm, p[0]), _obj(vm, p[1])
    if (o1.flags & fDrawn) and (o2.flags & fDrawn):
        x1 = o1.x + o1.xSize // 2
        x2 = o2.x + o2.xSize // 2
        d = abs(x1 - x2) + abs(o1.y - o2.y)
        if d > 0xFE:
            d = 0xFE
    else:
        d = 0xFF
    # ★ ScummVM's KQ4 zombie workaround is deliberately NOT reproduced -- see module docstring.
    vm.set_var(p[2], d & 0xFF)


# ── cycling and motion ─────────────────────────────────────────────────────────────────────
@_impl()
def cmdStopCycling(vm, p):
    _obj(vm, p[0]).flags &= ~fCycling


@_impl()
def cmdStartCycling(vm, p):
    _obj(vm, p[0]).flags |= fCycling


@_impl()
def cmdNormalCycle(vm, p):
    o = _obj(vm, p[0])
    o.cycle = kCycleNormal
    if vm.version >= 0x2000:
        o.flags |= fCycling


@_impl()
def cmdReverseCycle(vm, p):
    o = _obj(vm, p[0])
    o.cycle = kCycleReverse
    if vm.version >= 0x2000:
        o.flags |= fCycling


@_impl()
def cmdEndOfLoop(vm, p):
    from . import motion
    o = _obj(vm, p[0])
    o.cycle = kCycleEndOfLoop
    o.flags |= (fDontUpdate | fUpdate | fCycling)
    # ★ setLoopFlag() sets loop_flag AND CLEARS ignore_loop_flag. P4.1 set only the number;
    # a stale ignore_loop_flag from an earlier motion would then suppress this cycler's flag.
    o.loop_flag = p[1]
    o.ignore_loop_flag = False
    vm.state.set_flag(o.loop_flag, False)
    motion.cycler_activated(vm, o)


@_impl()
def cmdReverseLoop(vm, p):
    from . import motion
    o = _obj(vm, p[0])
    o.cycle = kCycleRevLoop
    o.flags |= (fDontUpdate | fUpdate | fCycling)
    o.loop_flag = p[1]
    o.ignore_loop_flag = False
    vm.state.set_flag(o.loop_flag, False)
    motion.cycler_activated(vm, o)


@_impl()
def cmdCycleTime(vm, p):
    # ★ BOTH fields take the value: `cycleTime = cycleTimeCount = getVar(varNr)`.
    # P4.1 set cycleTimeCount to 0 instead, which stalls the cycler for ever -- the update
    # only advances a counter that is already non-zero, so 0 never decrements to 0. Unreachable
    # until cycling mattered, and it is exactly why KQ2's flag 33 never fired.
    o = _obj(vm, p[0])
    o.cycleTime = o.cycleTimeCount = vm.get_var(p[1])


@_impl()
def cmdStopMotion(vm, p):
    o = _obj(vm, p[0])
    o.direction = 0
    o.motionType = kMotionNormal
    if p[0] == 0:
        vm.set_var(VM_VAR_EGO_DIRECTION, 0)
        vm.state.player_control = False


@_impl()
def cmdStartMotion(vm, p):
    o = _obj(vm, p[0])
    o.motionType = kMotionNormal
    if p[0] == 0:
        vm.set_var(VM_VAR_EGO_DIRECTION, 0)
        vm.state.player_control = True


@_impl()
def cmdStepSize(vm, p):
    _obj(vm, p[0]).stepSize = vm.get_var(p[1])


@_impl()
def cmdStepTime(vm, p):
    o = _obj(vm, p[0])
    o.stepTime = vm.get_var(p[1])
    o.stepTimeCount = o.stepTime


def _move_obj(vm, obj_nr, move_x, move_y, step_size, move_flag):
    """Shared body of move.obj / move.obj.v -- they differ only in operand fetch."""
    from . import motion
    o = _obj(vm, obj_nr)
    o.motionType = kMotionMoveObj
    o.move_x = move_x
    o.move_y = move_y
    o.move_stepSize = o.stepSize      # ★ saves the CURRENT step size, before the override
    o.move_flag = move_flag
    if step_size != 0:
        o.stepSize = step_size
    vm.state.set_flag(o.move_flag, False)
    o.flags |= fUpdate                # ★ P4.1 omitted this; without it the object is never
                                      #   active in checkAllMotions and never moves
    motion.motion_activated(vm, o)
    if obj_nr == 0:
        vm.state.player_control = False
    # ★ AGI 2.272 (ddp, xmas) does NOT call moveObj here. A real per-version difference.
    if vm.version > 0x2272:
        motion.motion_move_obj(vm, o)


@_impl()
def cmdMoveObj(vm, p):
    _move_obj(vm, p[0], p[1], p[2], p[3], p[4])


@_impl()
def cmdMoveObjF(vm, p):
    _move_obj(vm, p[0], vm.get_var(p[1]), vm.get_var(p[2]),
              vm.get_var(p[3]), p[4])


@_impl()
def cmdFollowEgo(vm, p):
    from . import motion
    o = _obj(vm, p[0])
    o.motionType = kMotionFollowEgo
    # ★ transcribed as the oracle writes it: <= keeps the object's own step size
    if p[1] <= o.stepSize:
        o.follow_stepSize = o.stepSize
    else:
        o.follow_stepSize = p[1]
    o.follow_flag = p[2]
    o.follow_count = 255
    vm.state.set_flag(o.follow_flag, False)
    o.flags |= fUpdate
    motion.motion_activated(vm, o)


@_impl()
def cmdWander(vm, p):
    from . import motion
    o = _obj(vm, p[0])
    if p[0] == 0:
        vm.state.player_control = False
    o.motionType = kMotionWander
    o.flags |= fUpdate
    motion.motion_activated(vm, o)


@_impl()
def cmdNormalMotion(vm, p):
    _obj(vm, p[0]).motionType = kMotionNormal


@_impl()
def cmdSetDir(vm, p):
    _obj(vm, p[0]).direction = vm.get_var(p[1])


@_impl()
def cmdGetDir(vm, p):
    vm.set_var(p[1], _obj(vm, p[0]).direction)


@_impl()
def cmdBlock(vm, p):
    vm.state.block = (p[0], p[1], p[2], p[3])


@_impl()
def cmdUnblock(vm, p):
    vm.state.block = None


# ── inventory ──────────────────────────────────────────────────────────────────────────────
@_impl()
def cmdGet(vm, p):
    vm.object_set_location(p[0], EGO_OWNED)


@_impl()
def cmdGetF(vm, p):
    vm.object_set_location(vm.get_var(p[0]), EGO_OWNED)


@_impl()
def cmdDrop(vm, p):
    vm.object_set_location(p[0], 0)


@_impl()
def cmdPut(vm, p):
    vm.object_set_location(p[0], vm.get_var(p[1]))


@_impl()
def cmdPutF(vm, p):
    vm.object_set_location(vm.get_var(p[0]), vm.get_var(p[1]))


@_impl()
def cmdGetRoomF(vm, p):
    vm.set_var(p[1], vm.object_get_location(vm.get_var(p[0])))


# ── control ────────────────────────────────────────────────────────────────────────────────
@_impl()
def cmdPlayerControl(vm, p):
    vm.state.player_control = True
    o = vm.state.ego()
    if o.motionType != kMotionEgo:
        o.motionType = kMotionNormal


@_impl()
def cmdProgramControl(vm, p):
    vm.state.player_control = False


@_impl()
def cmdRandom(vm, p):
    vm.set_var(p[2], vm.rnd.get_random_number(p[1] - p[0]) + p[0])


@_impl()
def cmdQuit(vm, p):
    vm.should_quit = True
    vm.state.exit_all_logics = True


@_impl()
def cmdRestartGame(vm, p):
    raise OpcodeError("restart.game is not implemented; it re-enters the whole game loop and "
                      "would silently restart the state diff mid-run")


# ── resources ──────────────────────────────────────────────────────────────────────────────
@_impl()
def cmdLoadView(vm, p):
    vm.state.loaded_views.add(p[0])


@_impl()
def cmdLoadViewF(vm, p):
    vm.state.loaded_views.add(vm.get_var(p[0]))


@_impl()
def cmdDiscardView(vm, p):
    vm.state.loaded_views.discard(p[0])


@_impl()
def cmdDiscardViewV(vm, p):
    vm.state.loaded_views.discard(vm.get_var(p[0]))


@_impl()
def cmdLoadPic(vm, p):
    vm.state.loaded_pics.add(vm.get_var(p[0]))


@_impl()
def cmdDiscardPic(vm, p):
    vm.state.loaded_pics.discard(vm.get_var(p[0]))


@_impl()
def cmdSetString(vm, p):
    # ★ textNr is parameter[1] - 1: the message numbering is 1-based in the bytecode and
    # 0-based in the texts array. Off by one here silently yields the neighbouring message.
    vm.state.strings[p[0]] = vm.get_message(vm.state.cur_logic_nr, p[1] - 1)


@_impl()
def cmdTextScreen(vm, p):
    # ★ NOT presentation-only, despite the name. gfxMode gates updateScreenObjTable(), which
    # writes VM_VAR_BORDER_*. Classifying this as MODELLED would silently disable the
    # animation update's variable writes.
    vm.state.gfx_mode = False


@_impl()
def cmdGraphics(vm, p):
    vm.state.gfx_mode = True


COMMAND_IMPLS = {}


def _register():
    g = globals()
    for name, obj in list(g.items()):
        if isinstance(obj, Impl):
            COMMAND_IMPLS[name] = obj

    # ── MODELLED: presentation only. Declared explicitly, one line each, so that the set is
    # readable as a list rather than inferred from what is missing.
    for name in (
        # pictures / screen
        "cmdDrawPic", "cmdShowPic", "cmdOverlayPic", "cmdShowPriScreen",
        "cmdAddToPic", "cmdAddToPicF", "cmdSetPriBase", "cmdShakeScreen",
        "cmdConfigureScreen", "cmdSetUpperLeft", "cmdClearTextRect",
        "cmdSetSimple",
        # text
        "cmdPrint", "cmdPrintF", "cmdDisplay", "cmdDisplayF", "cmdClearLines",
        "cmdSetCursorChar", "cmdSetTextAttribute", "cmdStatusLineOn",
        "cmdStatusLineOff", "cmdPrintAt", "cmdPrintAtV", "cmdCloseWindow",
        "cmdOpenDialogue", "cmdCloseDialogue", "cmdStatus", "cmdShowObj",
        "cmdShowObjV", "cmdShowMem", "cmdVersion", "cmdEchoLine", "cmdCancelLine",
        # sound
        "cmdLoadSound", "cmdSound", "cmdStopSound", "cmdDiscardSound",
        # menus
        "cmdSetMenu", "cmdSetMenuItem", "cmdSubmitMenu", "cmdEnableItem",
        "cmdDisableItem", "cmdMenuInput", "cmdAllowMenu",
        # input / mouse
        "cmdPreventInput", "cmdAcceptInput", "cmdSetKey", "cmdHideMouse",
        "cmdShowMouse", "cmdFenceMouse", "cmdGetMousePosn", "cmdHoldKey",
        "cmdReleaseKey", "cmdAdjEgoMoveToXY", "cmdPause", "cmdInitJoy",
        "cmdToggleMonitor",
        # housekeeping with no diffable effect
        "cmdInitDisk", "cmdScriptSize", "cmdSetGameID", "cmdLog",
        "cmdSetScanStart", "cmdResetScanStart", "cmdTraceOn", "cmdTraceInfo",
        "cmdPushScript", "cmdPopScript", "cmdObjStatusF",
    ):
        COMMAND_IMPLS[name] = _nop(name)


_register()
