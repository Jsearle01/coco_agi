-- harness/tools/decb_ready.lua -- wait for DECB's OK prompt before taking the machine over.
--
-- ★★★★★ JAY'S STANDING RULE, AND IT HAS NOW BEEN BROKEN TWICE. T-P0-060: "you need to wait for the
-- basic prompt 'ok'. We had this worked out before." T-P0-081: "i don't [see] your waiting for the
-- basic 'ok' prompt and its crashing the system." **The second time it was broken in SEVEN files
-- at once**, each written with its own `if m.time:as_double() < 0.3 then return end` -- a guess at
-- when the machine became ready rather than a reading of whether it had.
--
-- ★★★★ SO IT LIVES IN ONE PLACE NOW [§2F]. Seven copies of a rule is seven chances to write the
-- fixed-delay version again, and the delay version is the one that comes to hand.
--
-- ★★★★★ TWO INDEPENDENT SIGNALS, SUSTAINED THREE FRAMES:
--   1. "OK" as screen codes $4F,$4B at the START OF A ROW of the 32x16 VDG screen at $0400.
--      Idiom 14f: screen codes are not ASCII; uppercase $40-$5F is stored as-is.
--   2. The CPU parked in DECB's prompt poll, PC in $A7D0-$A7E0. Idiom 14a records $A7D7/$D7D5;
--      measured $A7D5 and $A7D7 on this machine.
-- ★★★ NOT a scan of all 512 screen bytes for any adjacent $4F,$4B. That matches uninitialised RAM
-- and passed at frame 28, before the banner is on screen at ~60 -- **it fails EARLY, the direction
-- that hides the problem** [§2W], and Jay caught that version twice.
-- ★★ Sustained three frames because one frame in the right place can be a pass through; three
-- says the machine is parked there.
--
-- ★★★★ AND IT HOLDS THE PROMPT so a person can SEE the machine was ready [Jay's display ruling].
-- A wait that is only in the log proves it to the log. Headless callers pass hold = 0.
--
-- usage:
--   local decb = dofile("harness/tools/decb_ready.lua")
--   local ready = decb.new{ hold = 120 }        -- or hold = 0 for a headless gate
--   ...inside the frame notifier, before any poke:
--   local st = ready(machine, cpu, prog)        -- "wait" | "hold" | "go" | "timeout"

local M = {}

function M.new(opt)
    opt = opt or {}
    local hold = opt.hold or 120
    local timeout = opt.timeout or 1800
    local quiet = opt.quiet or false
    local frame, streak, okframe, done = 0, 0, nil, false

    return function(m, cpu, prog)
        if done then return "go" end
        frame = frame + 1

        local seen = false
        for row = 0, 15 do
            local b = 0x0400 + row * 32
            if prog:read_u8(b) == 0x4F and prog:read_u8(b + 1) == 0x4B then
                seen = true
                break
            end
        end
        local pc = cpu.state["PC"].value
        local parked = (pc >= 0xA7D0 and pc <= 0xA7E0)
        if seen and parked then streak = streak + 1 else streak = 0 end

        if streak < 3 then
            -- ★★ Bounded, and it says so: a machine that never prints OK is a broken launch, and
            -- a wait that cannot fail is not a wait.
            if frame > timeout then
                print(string.format("★★★ no OK prompt on the $0400 text screen after %d frames "
                                    .. "-- the machine never finished booting. NOT poking.",
                                    timeout))
                return "timeout"
            end
            return "wait"
        end

        if okframe == nil then
            okframe = frame
            if not quiet then
                print(string.format("DECB is at its OK prompt (frame %d, PC=$%04X, 'OK' at a row "
                                    .. "start, 3 frames)%s", frame, pc,
                                    hold > 0 and string.format(" -- holding %d frames so it can "
                                                               .. "be seen", hold) or ""))
            end
            if hold > 0 then return "hold" end
        end
        if hold > 0 and frame - okframe < hold then return "hold" end

        done = true
        if not quiet then
            print(string.format("taking the machine over at frame %d", frame))
        end
        return "go"
    end
end

return M
