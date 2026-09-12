-- harness/tools/p3b_room.lua -- put the integrated probe in a room that HAS sprites [T-P0-048 B].
--
-- ★★★★★ THE PROBLEM THIS SOLVES, MEASURED FIRST. p3b closed with `sprites 0` and
-- `composite 0.0%` [AD-99], and that was read as "the compositor is untested". It is worse and
-- simpler than that: the game never leaves its opening room. Run at 300 cycles -- FIVE TIMES
-- p3b's 60 -- Kingquest1 still reports `room 83  sprites 0` on every single cycle. **The
-- compositor has nothing to composite, and no number of extra cycles changes that**, because an
-- AGI game sits in its credits until something moves it.
--
-- ★★★★ THE JUMP IS TWO HOST WRITES AND NOTHING ON THE 6809 [AD-99, vm_sweep.lua's P5.3 C1].
-- AGI routes a room change through VAR_CURRENT_ROOM (var 0) and FLAG_NEW_ROOM_EXEC (flag 5),
-- and logic.0 tests flag 5 every cycle. So setting both makes the game's OWN logic dispatch the
-- room on its next pass -- no new opcode, no new probe mode, no target code.
--
-- ★★★ THE ADDRESSES ARE p3b's, NOT vm_sweep's, AND THAT IS THE TRAP. vm_sweep.lua hardcodes
-- VM_VARS $4000 / VM_FLAGS $4100. The integrated probe maps them at **$0800 / $0900**
-- (build/p3b_probe_pk.map). Copying the pair across would have written into whatever lives at
-- $4000 in this build and reported "the room jump does nothing" [L-56].
--
-- ★★ It does not modify p3b_run.lua. A notifier is installed and p3b_run.lua is then `dofile`d
-- unchanged, so the run being measured is the run the closed P3b gate performs.
--
-- usage:  P3B_ROOM=1 P3B_ROOM_AT=8 mame ... -autoboot_script harness/tools/p3b_room.lua

local ROOM    = tonumber(os.getenv("P3B_ROOM") or "1")
local ROOM_AT = tonumber(os.getenv("P3B_ROOM_AT") or "8")

local VM_VARS  = 0x0800        -- MAP_VM_VARS  (p3b_probe_pk.map)
local VM_FLAGS = 0x0900        -- MAP_VM_FLAGS
local ST       = 0x0020        -- MAP_STATUS
local CYCLE    = ST + 4        -- 16-bit, big-endian

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- ★★★★ THE COUNTER IS NOT VALID UNTIL THE GUEST HAS WRITTEN IT, AND AN UNGUARDED READ FIRES
-- IMMEDIATELY. First run of this file jumped "at cycle 65535" -- RAM before the probe zeroed it
-- -- so both writes landed during init and the guest's own reset erased them. The jump reported
-- success and the room never changed. ★★ An upper bound is the guard: a cycle number above the
-- run length is not a cycle number [L-37 -- instrument something that can contradict you; the
-- printed 65535 is what did].
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ THE JUMP MOVED INTO p3b_run.lua, AND THIS FILE IS NOW THE SHIM THAT KEEPS ITS DEFAULT.
-- The notifier that used to live here is gone. It is not a deletion of the technique -- the same
-- two writes, the same cycle guard and the same landing checks are in p3b_run.lua -- it is the
-- removal of a SECOND COPY of them [§2F: one home per fact].
--
-- ★★★★★ WHY IT HAD TO GO, AND IT WOULD HAVE BITTEN THE EYE GATE FIRST. p3b_run.lua's jump also
-- writes var 17 (P3B_SETVAR), because the only rooms that print on a cold jump are AGI's error
-- room and `print.v(v17)` with var 17 at zero resolves to message index -1 and draws NOTHING
-- [P6.31]. This file's notifier wrote var 0 and flag 5 and knew nothing about var 17, and it is
-- registered FIRST, so on the eye-gate path (p3b_show.lua -> here -> p3b_run.lua) it could win
-- the race and dispatch the room before the message number was set. **The box would silently not
-- appear, and the cause would look like a rendering defect rather than a harness one.**
--
-- ★★★ EVERY CALLER STILL WORKS. p3b_show.lua, p3b_palwatch.lua and p3b_time.lua all chain through
-- this file and all of them reach the same driver they always did.
-- ★★ The one thing that was ONLY here is the implicit default of room 1 -- p3b_run.lua's own
-- default is 0, meaning "no jump" -- so it is handed over rather than dropped.
_G._p3b_room_default = ROOM

dofile("harness/tools/p3b_run.lua")
