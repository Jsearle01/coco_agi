-- harness/tools/pic_probe.lua -- T-P0-011 Part B driver.
--
-- Pokes the render probe and one PICTURE resource into a real CoCo3 under MAME, runs it, and
-- reads BOTH planes back out:
--   fb.bin   the 160x168 window of the mode-2 framebuffer, PACKED 4bpp (two pixels per byte)
--   pri.bin  the 160x168 priority plane, one byte per pixel
--
-- ★★ THE FRAMEBUFFER IS READ BACK PACKED, ON PURPOSE. The unpacking happens on the Python
-- side, so an error in OUR packing cannot cancel an error in the rendering -- if the Lua
-- unpacked it here, the two would be the same code path and a symmetric mistake would diff
-- clean (design §8.2).
--
-- ★ Idioms honoured (mame-idioms-coco3-port.md §10): output via io.open (the console is not
-- captured headless), the frame notifier kept in _G or it is GC'd and silently stops firing,
-- and the machine is allowed to SETTLE before the poke -- poking at frame 2 does not stick,
-- POP's shift_bench.lua waits for frame 240 and that is the proven idiom.

local OUTDIR = os.getenv("PIC_OUT") or "build/picrun"
local PROG   = os.getenv("PIC_PROG") or "build/pic_probe.bin"
local PICRES = os.getenv("PIC_RES") or "build/pic080.res"

local LOAD     = 0x0800     -- probe_entry / org
local PIC_DATA = 0x1200     -- where the probe expects the resource
local PRI_BASE = 0x1700     -- priority plane
local FB_BASE  = 0x8000     -- GFX_DB_WINDOW
local STATUS   = 0x16F0
local W, H     = 160, 168
local PLANE    = W * H      -- 26880

local function logf(fmt, ...)
    local f = io.open(OUTDIR .. "/run.log", "a")
    if f then f:write(string.format(fmt, ...) .. "\n"); f:close() end
end

os.execute('mkdir "' .. OUTDIR:gsub("/", "\\") .. '" 2>nul')
local f0 = io.open(OUTDIR .. "/run.log", "w"); if f0 then f0:close() end

local cpu  = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]

local function slurp(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local d = fh:read("*all"); fh:close()
    return d
end

local blob = slurp(PROG)
local pic  = slurp(PICRES)
if not blob then logf("FAIL: cannot read %s", PROG); return end
if not pic then logf("FAIL: cannot read %s", PICRES); return end
logf("program %d bytes -> $%04X ; picture %d bytes -> $%04X", #blob, LOAD, #pic, PIC_DATA)

if PIC_DATA + #pic >= PRI_BASE then
    -- ★ Loud rather than silent: a resource that runs into the priority plane would render a
    -- picture that is wrong for a reason the diff cannot name.
    logf("FAIL: picture is %d bytes and would overrun the priority plane at $%04X",
         #pic, PRI_BASE)
    manager.machine:exit()
    return
end

_G._pp_frames = 0
_G._pp_done   = false

_G._pp_notifier = emu.add_machine_frame_notifier(function()
    _G._pp_frames = _G._pp_frames + 1

    if _G._pp_frames == 240 then
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, string.byte(blob, i)) end
        for i = 1, #pic do prog:write_u8(PIC_DATA + i - 1, string.byte(pic, i)) end
        prog:write_u8(STATUS, 0)
        prog:write_u8(STATUS + 1, 0)
        cpu.state["PC"].value = LOAD
        logf("poked and PC set at frame %d", _G._pp_frames)
        return
    end

    if _G._pp_frames > 241 and not _G._pp_done then
        local sentinel = prog:read_u8(STATUS)
        if sentinel == 0xA5 then
            local bad = prog:read_u8(STATUS + 1)
            logf("probe completed at frame %d, bad_op=$%02X", _G._pp_frames, bad)
            if bad ~= 0 then
                logf("★ HALT REASON: $EE = fill-stack overflow, else an unimplemented opcode")
            end

            local fb = io.open(OUTDIR .. "/fb.bin", "wb")
            for i = 0, PLANE - 1 do fb:write(string.char(prog:read_u8(FB_BASE + i))) end
            fb:close()

            local pr = io.open(OUTDIR .. "/pri.bin", "wb")
            for i = 0, PLANE - 1 do pr:write(string.char(prog:read_u8(PRI_BASE + i))) end
            pr:close()

            logf("wrote fb.bin and pri.bin (%d bytes each)", PLANE)
            _G._pp_done = true
            manager.machine:exit()
        elseif _G._pp_frames > 1800 then
            local pc = 0
            pcall(function() pc = cpu.state["PC"].value end)
            logf("FAIL: sentinel never written after %d frames (PC=$%04X, bad_op=$%02X)",
                 _G._pp_frames, pc, prog:read_u8(STATUS + 1))
            _G._pp_done = true
            manager.machine:exit()
        end
    end
end)
