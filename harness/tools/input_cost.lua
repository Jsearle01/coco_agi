-- harness/tools/input_cost.lua -- what does polling the keyboard cost per frame? [P6.24 AC-5]
--
-- ★★★★★ THE INPUT LINE DOES NOT BLOCK. A message box runs an inner loop that never calls
-- interpretCycle(), so its cost competes with nothing; the input line is polled while the game
-- keeps cycling, so **every scan is charged to the frame** [§3].
--
-- ★★★★ TWO ARMS, ONE VARIABLE: with a key asserted and without. The idle arm is what every frame
-- pays whether or not anyone is typing; the difference is the marginal cost of a keystroke being
-- present. ★★★ N iterations with no handshake inside the interval, so a fixed overhead cannot be
-- divided into the per-scan figure [P6.19: a three-glyph message "cost" 84,626 cycles/glyph].
--
-- ★★ m.time is EMULATED time, so -nothrottle cannot move the answer (§2U.1), and the clock rate is
-- READ and printed rather than labelled [p3b_run.lua printed 1.789 MHz while running at 0.894].
--
-- usage:  IC_KEY=1 mame coco3 -autoboot_script harness/tools/input_cost.lua -seconds_to_run 90

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
m.natkeyboard.in_use = true

local PROG = os.getenv("IP_PROG") or "build/input_probe.bin"
local ITER = tonumber(os.getenv("IC_ITER") or "200")
local KEY  = os.getenv("IC_KEY") == "1"

local IP_GO, IP_DONE = 0x0020, 0x0021
local IP_ITER, IP_PHASE = 0x0027, 0x0028

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

local fields, phase, t0 = {}, "boot", nil

-- ★★★★★ READINESS COMES FROM harness/tools/decb_ready.lua, NOT FROM A FIXED DELAY. This file
-- used `if m.time:as_double() < 0.5 then return end` -- a guess at when the machine became ready
-- rather than a reading of whether it had -- and took DECB over mid-boot. Jay's standing rule,
-- broken here and in six sibling files at once [T-P0-060, T-P0-081].
local decb_ready = dofile("harness/tools/decb_ready.lua").new{ hold = 0 }

_G._ic = emu.add_machine_frame_notifier(function()
    if phase == "boot" then
        do
            local st = decb_ready(m, cpu, prog)
            if st == "timeout" then m:exit(); return end
            if st ~= "go" then return end
        end
        for tag, port in pairs(m.ioport.ports) do
            local r = tag:match("row(%d)")
            if r then
                for _, f in pairs(port.fields) do fields[r .. "," .. f.mask] = f end
            end
        end
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        poke(0x2000, blob)
        prog:write_u8(IP_ITER, ITER)
        cpu.state["PC"].value = 0x2000
        prog:write_u8(IP_GO, 1)
        phase = "arm"
        return
    end

    -- ★★★ Keep raising GO -- the guest clears it in its own init [P6.23's whole blockage].
    if phase == "arm" then
        if prog:read_u8(IP_GO) == 0 then prog:write_u8(IP_GO, 1); return end
        -- ★★★★ THE ARM: hold a letter down for the whole timing loop, or none at all. That is the
        -- only difference between the two runs. ★★ No ENTER is needed -- the probe branches
        -- straight to the timing loop when IP_ITER is set, so no line, no vocabulary, no parser.
        if KEY then
            local q = fields["2,2"]                 -- 'Q' at row2/col1
            if q then q:set_value(1) end
        end
        phase = "wait"
        return
    end

    if phase == "wait" then
        if prog:read_u8(IP_PHASE) == 2 then
            t0 = m.time:as_double()
            phase = "run"
        end
        return
    end

    if phase == "run" then
        if prog:read_u8(IP_PHASE) ~= 0xFF then return end
        local dt = m.time:as_double() - t0
        local hz, src = nil, "?"
        if type(cpu.clock) == "number" and cpu.clock > 0 then hz, src = cpu.clock, "device.clock" end
        if not hz then hz, src = 894886, "coco3 power-on rate (probe sets no SAM speed)" end
        local cyc = dt * hz
        print(string.format("ARM key=%s  iterations=%d", tostring(KEY), ITER))
        print(string.format("  %.5f s emulated, %.0f cycles  [%.0f Hz via %s]", dt, cyc, hz, src))
        print(string.format("  per HAL_key_scan: %.0f cycles", cyc / ITER))
        -- ★★★ What it means for the frame: a 60 Hz frame at this clock is hz/60 cycles.
        print(string.format("  one scan per frame = %.3f%% of a %.0f-cycle frame",
                            100.0 * (cyc / ITER) / (hz / 60), hz / 60))
        m:exit()
    end
end)
