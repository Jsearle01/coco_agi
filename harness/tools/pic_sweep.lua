-- harness/tools/pic_sweep.lua -- T-P0-012: render the whole gated PICTURE set on a real
-- CoCo3, in ONE MAME session, and time each render on the emulated clock.
--
-- ★★★ TIMING MECHANISM AND ITS RESOLUTION (AC-5). A WRITE TAP on the probe's PHASE byte:
-- the callback fires at the instant of the store, and reads `manager.machine.time`, which is
-- exact emulated time (attosecond representation). Resolution is ONE INSTRUCTION.
--   * NOT a frame counter -- 16.688 ms granularity, useless for decomposing a render.
--   * NOT host wall-clock -- that measures the host, not the 6809, and is not reproducible.
--   * NOT -seconds_to_run -- that bounds a session, it does not time a region.
-- Emulated time is deterministic: the same binary and picture give the same interval on every
-- run, which is what makes L-33's "two runs is not a sample" answerable at all here.
--
-- ★ Phases: 3->4 clock calibration, 1->2 the render bracket.
--
-- ★★ ONE SESSION, MANY PICTURES. Re-poking the resource and resetting PC to the entry point
-- costs milliseconds; booting MAME 45 times costs minutes and adds 45 chances for a
-- machine-state difference. HAL_gfx_set_mode re-clears both buffers each iteration, so there
-- is no bleed between pictures.
--
-- ★ Idioms honoured: output via io.open (§10), the notifier AND the tap kept in _G or they are
-- GC'd and silently stop firing, MONITOR TYPE set to RGB (§11l -- display-only here but the
-- runs must be identical to the gate's), -cfg_directory owned by the caller (§19i).

local OUTDIR = os.getenv("PIC_OUT") or "build/sweep"
local PROG   = os.getenv("PIC_PROG") or "build/pic_probe.bin"
local LIST   = os.getenv("PIC_LIST") or "build/picset/order.txt"
local RESDIR = os.getenv("PIC_RESDIR") or "build/picset"
local PLANES = os.getenv("PIC_PLANES") ~= "0"   -- "0" = timing only, skip the 54 KB readback

-- ★ P3.13: moved down 256 B with the assembly origin, to keep the code clear of
-- PIC_DATA after the counted build grew past it. LOAD and the .s org must agree.
local LOAD     = 0x0700
-- ★★★★ PIC_DATA MOVES WITH THE PACKED BUILD AND THE TWO MUST AGREE.
-- Packing the priority plane frees $4B80..$8000 in pic_probe's map, and the packed span walk
-- grows the code past $1200, so pic_probe.s relocates PIC_DATA to $5000. **If this side keeps
-- poking $1200 the picture lands inside the code and the gate reports a rendering failure for
-- a staging bug** -- the P3.13 shape exactly, which is why pic_probe.s carries an assembly-time
-- assertion for it and why this constant is guarded rather than assumed.
local PACKED_PIC = os.getenv("PIC_PACKED") ~= nil
local PIC_DATA = PACKED_PIC and 0x5000 or 0x1200
local PIC_MAX  = PACKED_PIC and (0x8000 - 0x5000) or (0x1700 - PIC_DATA)
local PRI_BASE = 0x1700
local FB_BASE  = 0x8000
local STATUS   = 0x0080                         -- moved out of the PIC_DATA window
local PHASE    = 0x0090
local GO       = 0x0091                         -- probe re-runs itself; see pic_probe.s
local FAULT_ARM = 0x0092                        -- AC-8, armed for one picture only
local FAULT_ON = os.getenv("PIC_FAULT_ON")      -- picture name to corrupt, or nil
local SNAP     = os.getenv("PIC_SNAP") ~= nil   -- AC-9: needs a -DPIC_PRESENT build
local W, H     = 160, 168
local PLANE    = W * H

local function logf(fmt, ...)
    local f = io.open(OUTDIR .. "/run.log", "a")
    if f then f:write(string.format(fmt, ...) .. "\n"); f:close() end
end

os.execute('mkdir "' .. OUTDIR:gsub("/", "\\") .. '" 2>nul')
local f0 = io.open(OUTDIR .. "/run.log", "w"); if f0 then f0:close() end
local csv = io.open(OUTDIR .. "/timing.csv", "w")
csv:write("name,render_s,calib_s,vert,horiz,diag,pixels,fills,spans,sp_peak_bytes,bad_op," ..
          "checks,path_v,path_p,path_g\n")

local cpu  = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- monitor type -> RGB, so a sweep run is the same machine as the gate run (§11l)
pcall(function()
    local port = manager.machine.ioport.ports[":screen_config"]
    if port then
        for name, field in pairs(port.fields) do
            if name == "Monitor Type" then field.user_value = 1
                logf("MONITOR TYPE -> RGB"); return end
        end
    end
end)

local function slurp(path)
    local fh = io.open(path, "rb"); if not fh then return nil end
    local d = fh:read("*all"); fh:close(); return d
end

local blob = slurp(PROG)
if not blob then logf("FAIL: cannot read %s", PROG); manager.machine:exit(); return end

-- the work list
local names = {}
for line in io.lines(LIST) do
    line = line:gsub("%s+$", "")
    if #line > 0 then names[#names + 1] = line end
end
logf("program %d bytes; %d pictures to render; planes=%s", #blob, #names, tostring(PLANES))

-- ★★ THE TIMING TAP. Kept in _G: a tap that is garbage-collected stops firing and reports
-- nothing, which reads as "the render took no time" rather than as an error.
_G._t = {}
_G._tap = prog:install_write_tap(PHASE, PHASE, "phase", function(offset, data, mask)
    _G._t[data % 256] = manager.machine.time:as_double()
end)

local idx, state, frames = 0, "idle", 0
local cur

local function rd16(a) return prog:read_u8(a) * 256 + prog:read_u8(a + 1) end

local function start_next()
    idx = idx + 1
    if idx > #names then return false end
    cur = names[idx]
    local pic = slurp(RESDIR .. "/" .. cur .. ".res")
    if not pic then logf("FAIL: cannot read %s.res", cur); return start_next() end
    if #pic > PIC_MAX then
        logf("SKIP %s: %d bytes exceeds the %d-byte window", cur, #pic, PIC_MAX)
        return start_next()
    end
    for i = 1, #pic do prog:write_u8(PIC_DATA + i - 1, string.byte(pic, i)) end
    prog:write_u8(STATUS, 0)
    prog:write_u8(STATUS + 1, 0)
    -- AC-8: arm the fault for exactly one named picture, so the gate must LOCALISE
    prog:write_u8(FAULT_ARM, (FAULT_ON and cur == FAULT_ON) and 1 or 0)
    _G._t = {}
    if idx == 1 then
        -- ★ First render only: the machine is in DECB's idle loop and setting PC is the
        -- proven way in (T-P0-011). The program is poked once, here.
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, string.byte(blob, i)) end
        cpu.state["PC"].value = LOAD
    else
        -- ★★★ EVERY LATER RENDER: write GO and let the probe jump to its own entry point.
        -- Setting PC here instead skipped the prologue and made the counters ACCUMULATE
        -- across pictures -- silently, with plausible values. The probe owns its restart.
        prog:write_u8(GO, 1)
    end
    state = "running"
    return true
end

local function finish()
    local bad = prog:read_u8(STATUS + 1)
    local render = (_G._t[2] and _G._t[1]) and (_G._t[2] - _G._t[1]) or -1
    local calib  = (_G._t[4] and _G._t[3]) and (_G._t[4] - _G._t[3]) or -1
    local pixels, fills, spans = rd16(0x0088), rd16(0x008A), rd16(0x008C)
    local peak = rd16(0x008E)
    local checks = rd16(0x0094) * 65536 + rd16(0x0096)   -- 32-bit: 4/px overflows 16
    -- AC-2: which of draw_FillCheck's three cases did each call take?
    local pv, pp, pg = rd16(0x0098), rd16(0x009A), rd16(0x009C)

    csv:write(string.format("%s,%.9f,%.9f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
        cur, render, calib, rd16(0x0082), rd16(0x0084), rd16(0x0086),
        pixels, fills, spans, peak, bad, checks, pv, pp, pg))
    csv:flush()
    logf("%-18s render %8.4f s  fills %4d  spans %6d  peak %4d B  px %6d  bad=$%02X",
         cur, render, fills, spans, peak, pixels, bad)

    if PLANES and bad == 0 then
        local fb = io.open(OUTDIR .. "/" .. cur .. ".fb.bin", "wb")
        for i = 0, PLANE - 1 do fb:write(string.char(prog:read_u8(FB_BASE + i))) end
        fb:close()
        -- ★★★★ PIC_PACKED: the guest's priority plane is 4 bpp, the ORACLE'S IS NOT. Expand the
        -- GUEST here and never pack the oracle -- §2O.1, so a packing bug cannot cancel a
        -- rendering bug. Packed byte j holds unpacked pixels 2j (high nibble) and 2j+1 (low),
        -- the convention stated at the head of composite.s.
        local pr = io.open(OUTDIR .. "/" .. cur .. ".pri.bin", "wb")
        if os.getenv("PIC_PACKED") then
            for j = 0, (PLANE // 2) - 1 do
                local b = prog:read_u8(PRI_BASE + j)
                pr:write(string.char((b >> 4) & 0x0F), string.char(b & 0x0F))
            end
        else
            for i = 0, PLANE - 1 do pr:write(string.char(prog:read_u8(PRI_BASE + i))) end
        end
        pr:close()
    end
end

_G._n = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if frames < 240 then return end             -- let the machine settle (proven idiom)
    if state == "idle" then
        if not start_next() then
            csv:close(); logf("SWEEP COMPLETE: %d pictures", idx - 1)
            manager.machine:exit()
        end
        return
    end
    -- ★★ AC-9: let the flip reach the screen, then snapshot -- BY COUNTING FRAMES HERE, never
    -- with emu.wait_next_frame() inside this callback. wait_next_frame RE-ENTERS the notifier,
    -- so the state machine ran finish() four times for one picture and wrote three IDENTICAL
    -- screenshots of the first room. The bug was visible only because all three PNGs were
    -- byte-for-byte the same size.
    if state == "snap" then
        _G._snapwait = _G._snapwait - 1
        if _G._snapwait <= 0 then
            manager.machine.video:snapshot()
            logf("  snapshot taken for %s", cur)
            state = "idle"
        end
        return
    end

    if state == "running" then
        _G._budget = (_G._budget or 0) + 1
        if prog:read_u8(STATUS) == 0xA5 then
            _G._budget = 0; finish(); state = SNAP and "snap" or "idle"; _G._snapwait = 4
        elseif prog:read_u8(STATUS + 1) ~= 0 then
            logf("%-18s HALTED bad_op=$%02X", cur, prog:read_u8(STATUS + 1))
            _G._budget = 0; finish(); state = "idle"
        elseif _G._budget > 5400 then
            -- ★ 90 emulated seconds. A picture that never terminates must not hang the sweep
            -- silently; it is recorded as a timeout and the sweep continues (L-23).
            local pc = 0
            pcall(function() pc = cpu.state["PC"].value end)
            logf("%-18s TIMEOUT after %d frames (PC=$%04X)", cur, _G._budget, pc)
            _G._budget = 0; finish(); state = "idle"
        end
    end
end)
