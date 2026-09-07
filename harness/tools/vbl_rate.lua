-- harness/tools/vbl_rate.lua -- does the VBL counter actually tick, and at what rate?
-- [T-P0-064 / Jay's AD-138 ruling]
--
-- ★★★★★ THE CLOCK SOURCE IS SHOWN TO WORK BEFORE ANYTHING DEPENDS ON IT [§2W]. The ruling moves
-- VAR_SECONDS onto the CoCo3's vertical-sync interrupt. That interrupt has NEVER FIRED in this
-- probe: vm_probe.s masked IRQ at entry and never called HAL_time_init, so DP $10/$11 has been a
-- dead counter in every VM run to date. **A clock nobody has seen advance is not a clock.**
--
-- ★★★★ IT MEASURES THE RATE RATHER THAN ASSUMING 60 Hz. NTSC vertical sync is 59.92 Hz, not 60,
-- and Jay has ruled the ~0.13% drift acceptable ("one second in 12.5 minutes won't be missed").
-- **That ruling is only safe if the rate really is 59.92 and not, say, half of it** -- a handler
-- that fires on both field halves, or one the GIME is not actually configured to raise, would
-- give 120 or 0, and either would be invisible in a report that assumed the number.
--
-- ★★★ IT MUST ALSO BE SHOWN ABLE TO FAIL. Run it against a build that does NOT enable the
-- interrupt and the counter stays flat -- that is the negative control, and it is the state
-- every previous VM run was in.
--
-- usage:  VBL_PROG=build/vm_probe.bin mame ... -autoboot_script harness/tools/vbl_rate.lua

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG = os.getenv("VBL_PROG") or "build/vm_probe.bin"
local OUT  = os.getenv("VBL_OUT")  or "build/vbl_rate.txt"
local LOAD = 0x0700

-- ★ hal_frame_hi/lo are DIRECT PAGE $10/$11, declared in time.s and incremented by
-- irq_vbl.s's handler. Big-endian 16-bit.
local FRAME_HI, FRAME_LO = 0x10, 0x11

-- ★ hal_vbl_handler's address, from the build's map.
_G._vbl_sym = nil
do
    local h = io.open(os.getenv("VBL_MAP") or "build/vm_probe.map", "r")
    if h then
        for line in h:lines() do
            local v = line:match("^Symbol:%s+hal_vbl_handler%s+%b()%s+=%s+(%x+)")
            if v then _G._vbl_sym = tonumber(v, 16) end
        end
        h:close()
    end
end

local f = io.open(OUT, "w")
local function w(s, ...) local t = string.format(s, ...); f:write(t .. "\n"); print(t) end

local function slurp(p)
    local h = io.open(p, "rb"); if not h then return nil end
    local d = h:read("a"); h:close(); return d
end

local function frames() return prog:read_u8(FRAME_HI) * 256 + prog:read_u8(FRAME_LO) end

local state, t0, f0, n = "boot", nil, nil, 0

_G._vbl = emu.add_machine_frame_notifier(function()
    n = n + 1
    if state == "boot" then
        -- ★ Same OK-prompt discipline as p3b_run.lua [idiom 43a]: a frame count is a guess.
        local ok = false
        for row = 0, 15 do
            local b = 0x0400 + row * 32
            if prog:read_u8(b) == 0x4F and prog:read_u8(b + 1) == 0x4B then ok = true break end
        end
        local pc = cpu.state["PC"].value
        if not (ok and pc >= 0xA7D0 and pc <= 0xA7E0) then return end
        local blob = slurp(PROG)
        if not blob then w("★★★ no program at %s", PROG); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        cpu.state["PC"].value = LOAD
        w("poked %d bytes, PC set (frame %d)", #blob, n)
        state = "settle"
        return
    end
    if state == "settle" then
        -- let the guest reach its gate and install the handler
        if n % 30 ~= 0 then return end
        t0, f0, _G._vbl_n0 = m.time:as_double(), frames(), n
        -- ★★★★★ TAP THE HANDLER ITSELF. The guest's counter and the machine's frame rate are two
        -- different quantities, and when they disagree the question is WHICH ONE is wrong. A read
        -- tap on hal_vbl_handler's entry counts how many times the CPU actually vectored there,
        -- which separates "the IRQ is not being delivered" from "the handler is not counting".
        -- ★★ Symbol from the map, never a literal [P6.3 §3.F.2].
        local h = _G._vbl_sym
        if h then
            _G._vbl_hits = 0
            _G._vbl_tap = prog:install_read_tap(h, h, "vblh", function()
                _G._vbl_hits = _G._vbl_hits + 1
            end)
        end
        w("counter at t0 : %d   (emulated t=%.4f, MAME frame %d)", f0, t0, n)
        state = "measure"
        return
    end
    if state == "measure" then
        -- ★★★★ SAMPLE CC.I. Handler entries (39) against MAME frames (300) says the IRQ is not
        -- being DELIVERED, not that the handler is wrong. The 6809 takes an IRQ only at an
        -- instruction boundary with CC.I clear, and the GIME's pending flag is cleared by the
        -- handler's own $FF92 read -- so every VBL that arrives while masked is LOST, and a run
        -- of them collapses into one. This counts how often the CPU is masked when sampled.
        _G._cci = _G._cci or 0
        _G._ccn = (_G._ccn or 0) + 1
        if (cpu.state["CC"].value & 0x10) ~= 0 then _G._cci = _G._cci + 1 end
        local dt = m.time:as_double() - t0
        if dt < 5.0 then return end
        local df = frames() - f0
        w("counter at t1 : %d   (emulated t=%.4f)", frames(), m.time:as_double())
        w("")
        w("elapsed emulated : %.4f s", dt)
        w("VBL ticks        : %d", df)
        if df == 0 then
            w("★★★ THE COUNTER DID NOT MOVE. Either the IRQ is masked, HAL_time_init was not")
            w("    called, or the GIME is not raising VBL. This is the state every VM run before")
            w("    Jay's ruling was in -- and it is the negative control for this instrument.")
        else
            w("measured rate    : %.4f Hz", df / dt)
        w("MAME frames      : %d in the same window = %.4f Hz",
          n - _G._vbl_n0, (n - _G._vbl_n0) / dt)
        if _G._vbl_hits then
            w("handler ENTERED  : %d times = %.4f Hz", _G._vbl_hits, _G._vbl_hits / dt)
            w("★ handler entries vs counter increments: %d vs %d", _G._vbl_hits, df)
            w("CC.I set when sampled : %d of %d samples = %.1f%% of the time MASKED",
              _G._cci, _G._ccn, 100.0 * _G._cci / _G._ccn)
        end
            w("")
            w("★ NTSC vertical sync is 59.92 Hz. 60 ticks called one second drifts +0.13%%,")
            w("  which Jay has ruled acceptable: about one second per 12.5 minutes.")
            w("★ seconds implied by a 60-tick second : %.4f  (true elapsed %.4f)", df / 60.0, dt)
        end
        f:close()
        m:exit()
    end
end)
