"""The VM: resource binding, the interpreter loop, and the cycle.

★★ THE CYCLE IS THE UNIT THE DIFF IS INDEXED BY. oracle/patches/0002 dumps flags+vars at cycle
ENTRY, once per interpretCycle() call, so `cycle N` here must mean exactly what `cycle N` means
in the oracle: the Nth call to interpret_cycle(), counted from zero, dumped BEFORE the cycle
does anything. Any other convention silently shifts the whole diff by one line and reports a
divergence at the wrong place.

★ WHAT THIS VM DOES NOT DO. It has no graphics, no sound, no input and no animation update
(updateScreenObjTable). Those are declared absences, not omissions to be discovered:
  - motion/animation: checkAllMotions() and updateScreenObjTable() move objects and can write
    VM_VAR_BORDER_TOUCH_EGO / VM_VAR_BORDER_CODE / VM_VAR_EGO_DIRECTION. A game whose scripts
    read those WILL diverge, and that divergence is real and expected until motion is built.
  - input: no keys are ever delivered, matching a headless oracle run with no input.
The state diff is the instrument that says how far that gets, and it is not fudged to hide it.
"""

import sys

from . import blit, commands, motion, objects, tests
from .dispatch import DispatchTable, OpcodeError, UNIMPLEMENTED
from .optable import (VM_VAR_CURRENT_ROOM, VM_VAR_PREVIOUS_ROOM,
                      VM_VAR_BORDER_TOUCH_OBJECT, VM_VAR_BORDER_CODE,
                      VM_VAR_BORDER_TOUCH_EGO, VM_VAR_EGO_VIEW_RESOURCE,
                      VM_VAR_EGO_DIRECTION, VM_VAR_WORD_NOT_FOUND, VM_VAR_SCORE,
                      VM_VAR_SECONDS, VM_VAR_MINUTES, VM_VAR_HOURS, VM_VAR_DAYS,
                      VM_VAR_TIME_DELAY, VM_VAR_KEY, VM_VAR_COMPUTER,
                      VM_VAR_SOUNDGENERATOR, VM_VAR_MONITOR, VM_VAR_FREE_PAGES,
                      VM_VAR_MAX_INPUT_CHARACTERS, VM_FLAG_LOGIC_ZERO_FIRST_TIME,
                      kAgiComputerPC, kAgiComputerAmiga, kAgiComputerAtariST,
                      kAgiComputerApple2, kAgiSoundPC, kAgiSoundTandy, kAgiMonitorEga,
                      VM_FLAG_NEW_ROOM_EXEC, VM_FLAG_RESTART_GAME,
                      VM_FLAG_RESTORE_JUST_RAN, VM_FLAG_ENTERED_CLI,
                      VM_FLAG_SAID_ACCEPTED_INPUT, VM_FLAG_SOUND_ON,
                      fAnimated, fDrawn, fUpdate, fUpdatePos, fIgnoreHorizon,
                      kMotionEgo, kMotionNormal)
from .state import VmState, SCREENOBJECTS_MAX


class RandomSource:
    """ScummVM's Common::RandomSource, reproduced exactly.

    ★ §2.1: this reproduces SCUMMVM's generator, which is not Sierra's. It exists so the state
    diff is meaningful for games that call the random opcode -- matching the oracle bit for bit
    is the whole point of a diff harness. The CoCo3 target will use its own generator; that is
    a deliberate, stated divergence and not a defect.

    common/random.cpp: xorshift (>>13, <<21, >>11), then (seed * 0xDEADBF03) % (max + 1).
    """

    def __init__(self, seed=12345):
        self.seed = seed if seed != 0 else 1

    def _scramble(self):
        s = self.seed
        s ^= (s >> 13)
        s &= 0xFFFFFFFF
        s ^= (s << 21) & 0xFFFFFFFF
        s &= 0xFFFFFFFF
        s ^= (s >> 11)
        self.seed = s & 0xFFFFFFFF

    def get_random_number(self, maximum):
        self._scramble()
        if maximum == 0xFFFFFFFF:
            return (self.seed * 0xDEADBF03) & 0xFFFFFFFF
        return ((self.seed * 0xDEADBF03) & 0xFFFFFFFF) % (maximum + 1)


class Vm:
    def __init__(self, game, version, platform="dos", game_id="", features=(),
                 seed=12345, trace=None):
        self.game = game                 # a volread Game
        self.version = version
        self.platform = platform
        self.state = VmState()
        self.rnd = RandomSource(seed)
        self.trace = trace
        self.should_quit = False
        self.cycle_nr = 0
        self.modelled_calls = {}
        self.motion_modes_seen = {}
        self.instruction_counter = 0

        self.table = DispatchTable(version, platform, game_id, features)
        self.table.bind(commands.COMMAND_IMPLS, tests.TEST_IMPLS)

        # in-game timer, driven by the SAME virtual clock rule as oracle patch 0005:
        # 25 ms per main-loop iteration.
        self.virtual_ms = 0
        self._last_cycles = 0
        self._last_seconds = 0

        self._logic_cache = {}
        self._view_cache = {}
        self.blit_cost = blit.BlitCost()

    # ── variables ──────────────────────────────────────────────────────────────────────────
    def get_var(self, n):
        # ScummVM's getVar() calls inGameTimerUpdate() when a timer var is read. With the
        # virtual clock that update is deterministic, so it is reproduced here rather than
        # skipped -- skipping it would make the timer vars lag by one read.
        if n in (VM_VAR_SECONDS, VM_VAR_MINUTES, VM_VAR_HOURS, VM_VAR_DAYS):
            self.timer_update()
        return self.state.vars[n]

    def set_var(self, n, value):
        self.state.vars[n] = value & 0xFF

    def get_string(self, n):
        return self.state.strings[n]

    # ── the in-game timer (global.cpp inGameTimerUpdate, with patch 0005's clock) ──────────
    def timer_update(self):
        cur_cycles = self.virtual_ms // 25
        if cur_cycles == self._last_cycles:
            return
        self._last_cycles = cur_cycles

        cur_seconds = self.virtual_ms // 1000
        if cur_seconds == self._last_seconds:
            return
        delta = cur_seconds - self._last_seconds
        if delta > 0:
            v = self.state.vars
            secs = delta
            days, hours = v[VM_VAR_DAYS], v[VM_VAR_HOURS]
            mins, sec = v[VM_VAR_MINUTES], v[VM_VAR_SECONDS]
            if secs >= 86400:
                days += secs // 86400
                secs %= 86400
            if secs >= 3600:
                hours += secs // 3600
                secs %= 3600
            if secs >= 60:
                mins += secs // 60
                secs %= 60
            sec += secs
            while sec > 59:
                sec -= 60
                mins += 1
            while mins > 59:
                mins -= 60
                hours += 1
            while hours > 23:
                hours -= 24
                days += 1
            v[VM_VAR_SECONDS] = sec & 0xFF
            v[VM_VAR_MINUTES] = mins & 0xFF
            v[VM_VAR_HOURS] = hours & 0xFF
            v[VM_VAR_DAYS] = days & 0xFF
        self._last_seconds = cur_seconds

    # ── resources ──────────────────────────────────────────────────────────────────────────
    def load_logic(self, nr):
        if nr not in self._logic_cache:
            from volread import logic as logic_mod
            raw = self.game.load("LOGIC", nr)
            lg = logic_mod.split(raw, index=nr)
            self._logic_cache[nr] = lg
        self.state.loaded_logics.add(nr)
        return self._logic_cache[nr]

    def get_message(self, logic_nr, text_nr):
        lg = self._logic_cache.get(logic_nr)
        if lg is None or text_nr < 0 or text_nr >= len(lg.messages):
            return ""
        return lg.messages[text_nr]

    def load_view(self, view_nr):
        """Decode a VIEW resource, cached. ★ P4.1 could not do this and declared the gap;
        objects.py now depends on real loopCount/celCount/xSize/ySize."""
        if view_nr not in self._view_cache:
            from . import view as view_mod
            raw = self.game.load("VIEW", view_nr)
            self._view_cache[view_nr] = view_mod.decode_view(
                raw, version=self.version, view_nr=view_nr)
        self.state.loaded_views.add(view_nr)
        return self._view_cache[view_nr]

    def get_cel(self, obj):
        """The cel an object currently shows, or None if it has no usable view."""
        try:
            v = self.load_view(obj.view)
        except Exception:                                   # noqa: BLE001
            return None
        if obj.loop >= len(v.loops):
            return None
        loop = v.loops[obj.loop]
        if obj.cel >= len(loop.cels):
            return None
        return loop.cels[obj.cel]

    def set_view(self, obj, view_nr):
        objects.set_view(self, obj, view_nr)

    def object_get_location(self, n):
        if n < len(self.state.object_rooms):
            return self.state.object_rooms[n]
        return 0

    def object_set_location(self, n, room):
        if n < len(self.state.object_rooms):
            self.state.object_rooms[n] = room & 0xFF

    def test_said(self, p):
        # `said` matches parsed input words. With no input there is never a match, which is
        # correct for a headless run and wrong the moment input exists. Declared, not silent.
        return False

    # ── the interpreter ────────────────────────────────────────────────────────────────────
    def run_logic(self, logic_nr):
        st = self.state
        lg = self.load_logic(logic_nr)

        st.cur_logic_nr = logic_nr
        st.code = lg.bytecode
        st.ip = 0

        while st.ip < len(st.code) and not self.should_quit:
            self.instruction_counter += 1
            op = st.code[st.ip]
            st.ip += 1

            if op == 0xFF:
                tests.test_if_code(self)
                continue
            if op == 0xFE:
                # goto: +2 covers the offset itself; the offset is SIGNED
                off = int.from_bytes(st.code[st.ip:st.ip + 2], "little", signed=True)
                st.ip += 2 + off
                continue
            if op == 0x00:
                return 1                      # return

            entry = self.table.commands[op]
            if entry is None or entry.handler is None:
                name = entry.name if entry else "?"
                raise OpcodeError(
                    "command opcode %02X (%s) is not implemented by this VM "
                    "(logic %d, ip %d, cycle %d)"
                    % (op, name, logic_nr, st.ip - 1, self.cycle_nr))

            p = st.code[st.ip:st.ip + entry.size]
            entry.handler(self, p)
            st.ip += entry.size

            if st.exit_all_logics:
                break

        return 0

    def new_room(self, room_nr):
        st = self.state
        ego = st.ego()
        for i in range(SCREENOBJECTS_MAX):
            o = st.screen_objs[i]
            o.objectNr = i
            o.flags &= ~(fAnimated | fDrawn)
            o.flags |= fUpdate
            o.stepTime = 1
            o.stepTimeCount = 1
            o.cycleTime = 1
            o.cycleTimeCount = 1
            o.stepSize = 1

        st.loaded_logics.clear()
        st.loaded_views.clear()
        st.loaded_pics.clear()
        st.loaded_sounds.clear()

        st.player_control = True
        st.block = None
        st.horizon = 36
        self.set_var(VM_VAR_PREVIOUS_ROOM, self.get_var(VM_VAR_CURRENT_ROOM))
        self.set_var(VM_VAR_CURRENT_ROOM, room_nr)
        self.set_var(VM_VAR_BORDER_TOUCH_OBJECT, 0)
        self.set_var(VM_VAR_BORDER_CODE, 0)
        self.set_var(VM_VAR_EGO_VIEW_RESOURCE, ego.view)

        self.load_logic(room_nr)

        touch = self.get_var(VM_VAR_BORDER_TOUCH_EGO)
        if touch == 1:
            ego.y = 168 - 1
        elif touch == 2:
            ego.x = 0
        elif touch == 3:
            ego.y = st.horizon + 1
        elif touch == 4:
            ego.x = 160 - ego.xSize

        if self.version >= 0x3000 and ego.motionType == kMotionEgo:
            ego.motionType = kMotionNormal
            self.set_var(VM_VAR_EGO_DIRECTION, 0)

        self.set_var(VM_VAR_BORDER_TOUCH_EGO, 0)
        st.set_flag(VM_FLAG_NEW_ROOM_EXEC, True)
        st.exit_all_logics = True

    # ── the cycle ──────────────────────────────────────────────────────────────────────────
    def interpret_cycle(self):
        st = self.state

        if self.trace is not None:
            self.trace.emit(self.cycle_nr, st.flags, st.vars)
        self.cycle_nr += 1

        ego = st.ego()
        if not st.player_control:
            self.set_var(VM_VAR_EGO_DIRECTION, ego.direction)
        else:
            ego.direction = self.get_var(VM_VAR_EGO_DIRECTION)

        motion.check_all_motions(self)

        st.exit_all_logics = False
        while self.run_logic(0) == 0 and not self.should_quit:
            self.set_var(VM_VAR_WORD_NOT_FOUND, 0)
            self.set_var(VM_VAR_BORDER_TOUCH_OBJECT, 0)
            self.set_var(VM_VAR_BORDER_CODE, 0)
            st.set_flag(VM_FLAG_ENTERED_CLI, False)
            st.exit_all_logics = False
            self.reset_controllers()

        self.reset_controllers()
        ego.direction = self.get_var(VM_VAR_EGO_DIRECTION)

        self.set_var(VM_VAR_BORDER_TOUCH_OBJECT, 0)
        self.set_var(VM_VAR_BORDER_CODE, 0)
        st.set_flag(VM_FLAG_NEW_ROOM_EXEC, False)
        st.set_flag(VM_FLAG_RESTART_GAME, False)
        st.set_flag(VM_FLAG_RESTORE_JUST_RAN, False)

        if st.gfx_mode:
            objects.update_screen_obj_table(self)
            # ★ Cost only, no pixels (blit.py). Placed where the oracle composites sprites.
            self.blit_cost.composite(self, self.cycle_nr - 1)

    def reset_controllers(self):
        for i in range(len(self.state.controller_occurred)):
            self.state.controller_occurred[i] = False

    # ── the main loop (cycle.cpp playGame) ─────────────────────────────────────────────────
    def run(self, max_cycles=None):
        """Run until quit or max_cycles cycles have been INTERPRETED.

        Mirrors the pacing gate: the loop advances the virtual clock 25 ms per iteration and
        interprets a cycle only when enough ticks have accumulated for VM_VAR_TIME_DELAY.
        Reproducing the gate matters because it is what makes cycle number and virtual time
        track each other -- the relationship the timer vars depend on.
        """
        passed = 0
        while not self.should_quit:
            self.virtual_ms += 25
            passed += 1
            self.timer_update()

            time_delay = self.get_var(VM_VAR_TIME_DELAY)
            time_delay = time_delay * 2
            if not time_delay:
                time_delay = 1

            if passed >= time_delay:
                passed = 0
                self.interpret_cycle()
                st = self.state
                st.set_flag(VM_FLAG_ENTERED_CLI, False)
                st.set_flag(VM_FLAG_SAID_ACCEPTED_INPUT, False)
                self.set_var(VM_VAR_WORD_NOT_FOUND, 0)
                self.set_var(VM_VAR_KEY, 0)
                if max_cycles is not None and self.cycle_nr >= max_cycles:
                    return

    def start(self):
        """runGame() + playGame()'s pre-loop initialisation.

        ★★ THIS IS INTERPRETER-VISIBLE STATE, NOT SETUP TRIVIA. Game scripts branch on vars
        20/22/26 to decide what machine they are on, and on flags 5/9/11 at first run. The
        first version of this VM omitted it and the state diff diverged at CYCLE 0 with six
        differences -- which is exactly what the gate is for: the divergence was in
        initialisation, was localised precisely, and named its own cause.
        """
        st = self.state

        # runGame(): computer type and sound type (cycle.cpp). DOS is the default branch.
        if self.platform == "atarist":
            self.set_var(VM_VAR_COMPUTER, kAgiComputerAtariST)
            self.set_var(VM_VAR_SOUNDGENERATOR, kAgiSoundPC)
        elif self.platform == "amiga":
            self.set_var(VM_VAR_COMPUTER, kAgiComputerAmiga)
            self.set_var(VM_VAR_SOUNDGENERATOR, kAgiSoundTandy)
        elif self.platform == "apple2":
            self.set_var(VM_VAR_COMPUTER, kAgiComputerApple2)
            self.set_var(VM_VAR_SOUNDGENERATOR, kAgiSoundPC)
        else:
            self.set_var(VM_VAR_COMPUTER, kAgiComputerPC)
            self.set_var(VM_VAR_SOUNDGENERATOR, kAgiSoundPC)

        # Monitor type. ScummVM keys this off its RENDER MODE, not the platform; the default
        # render mode for these games is EGA.
        # ★ §2.1: on the CoCo3 this will not be kAgiMonitorEga, and a game that branches on
        # var 26 will take a different path. That is a real decision for the target and it is
        # NOT settled here -- this value exists to match the oracle, nothing more.
        self.set_var(VM_VAR_MONITOR, kAgiMonitorEga)

        self.set_var(VM_VAR_FREE_PAGES, 180)
        self.set_var(VM_VAR_MAX_INPUT_CHARACTERS, 38)

        # playGame() (cycle.cpp:377-379)
        # ★ The source comment beside flag 11 reads "not in 2.917", but the code sets it
        # UNCONDITIONALLY and the oracle dump for a 2.917 game confirms it is set. Code over
        # comment (CLAUDE.md §2 ranks comments lowest).
        st.set_flag(VM_FLAG_LOGIC_ZERO_FIRST_TIME, True)
        st.set_flag(VM_FLAG_NEW_ROOM_EXEC, True)
        st.set_flag(VM_FLAG_SOUND_ON, True)
        st.gfx_mode = True                    # cycle.cpp:382, before the main loop

        st.set_flag(VM_FLAG_ENTERED_CLI, False)
        st.set_flag(VM_FLAG_SAID_ACCEPTED_INPUT, False)
        self.set_var(VM_VAR_WORD_NOT_FOUND, 0)
        self.set_var(VM_VAR_KEY, 0)

        # inventory table
        try:
            from volread import inventory
            raw = self.game.extras.get("OBJECT") if self.game.extras else None
            if raw:
                inv = inventory.parse(raw, spos=3)
                st.object_rooms = [o.room for o in inv.objects]
                st.object_names = [o.name for o in inv.objects]
                st.num_objects = len(inv.objects)
        except Exception as exc:                      # noqa: BLE001
            print("  [agivm] OBJECT not loaded: %s" % exc, file=sys.stderr)
