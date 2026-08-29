-- harness/tools/comp_time.lua -- AC-5/AC-6: what a composite costs on hardware, in fast mode.
--
-- ★★★ THE HANDSHAKE COSTS AN EMULATED FRAME (16.7 ms) PER COMPOSITE, which is 300x the thing
-- being measured. So each sprite is composited N times back to back inside the guest and the
-- emulated clock is read either side. Timing through the gate would report MAME's frame period
-- [the T-P0-027 free-run, same reasoning].
--
-- ★★ ONE OBSERVATION PER SPRITE, not one per frame, and each carries its own counters:
-- tested / written / rejected / control-branch / control-steps. Cost is then FITTED against
-- those predictors rather than divided by a single number, so the model is over-determined and
-- can be contradicted [L-54: attribute each change separately].
--
-- ★ Emulated seconds, not wall clock: wall clock measures this laptop.

local OUT   = os.getenv("COMP_OUT")   or "build/comp_time"
local PROG  = os.getenv("COMP_PROG")  or "build/comp_probe.bin"
local STAGE = os.getenv("COMP_STAGE") or "build/comp_stage/SpaceQuest-1"
local FRAMES= os.getenv("COMP_FRAMES")or "oracle/dumps/frames-SpaceQuest-1"
local REPS  = tonumber(os.getenv("COMP_REPS") or "200")
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD   = 0x0700
local CP_CEL = 0x1100
local CP_PRI = 0x2900
local CP_VIS = 0x9200
local GO, MODE = 0x0080, 0x0081
local X, Y, PRIO = 0x0084, 0x0085, 0x0086
local CW, CH, CKEY, N = 0x0088, 0x0089, 0x008A, 0x008E
local TESTED, WRITTEN, REJPRI, REJKEY = 0x0090, 0x0094, 0x0098, 0x009C
local CTRLHIT, CTRLSTEP = 0x00A8, 0x00AC
local W, H = 160, 168
local PLANE = W * H

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local logf = io.open(OUT .. "/run.log", "w")
local csv  = io.open(OUT .. "/cost.csv", "w")
csv:write("frame,sprite,w,h,reps,seconds,tested,written,rejpri,rejkey,ctrlhit,ctrlstep\n")
local function w_(f, ...)
    local s = string.format(f, ...); logf:write(s .. "\n"); logf:flush(); print(s)
end
local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end
local function rd32(a)
    return prog:read_u8(a) * 16777216 + prog:read_u8(a+1) * 65536
         + prog:read_u8(a+2) * 256 + prog:read_u8(a+3)
end

local frames = {}
for line in io.lines(STAGE .. "/frames.txt") do
    local n = line:match("^(%d+)")
    if n then frames[#frames + 1] = n end
end

local fi, si, t0, calN = 1, 0, nil, 0
local sprites, celblob
local frame, state = 0, "load"

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    if state == "load" then
        local b = slurp(PROG)
        for k = 1, #b do prog:write_u8(LOAD + k - 1, b:byte(k)) end
        prog:write_u8(GO, 1); cpu.state["PC"].value = LOAD
        state = "boot"; return
    end
    if state == "boot" then
        if prog:read_u8(GO) ~= 0 then return end
        w_("guest at its gate -- fast mode, all-RAM")
        state = "cal0"; return
    end
    if prog:read_u8(GO) ~= 0 then return end

    -- ★ CLOCK FIRST, from this very binary. L-57 says state the clock; measuring it here means
    -- the figure below is not inherited from another probe's calibration.
    if state == "cal0" then
        calN = 200
        t0 = m.time:as_double()
        prog:write_u8(N, math.floor(calN / 256)); prog:write_u8(N + 1, calN % 256)
        prog:write_u8(MODE, 4); prog:write_u8(GO, 1)
        state = "cal1"; return
    end
    if state == "cal1" then
        local dt = m.time:as_double() - t0
        w_("clock: %d x 160,000 cycles in %.9f emulated s -> %.4f MHz",
           calN, dt, (calN * 160000) / dt / 1e6)
        state = "next"; return
    end

    if state == "next" then
        if fi > #frames then
            csv:close()
            w_("★ cost samples written to %s/cost.csv", OUT)
            m:exit(); return
        end
        local n = frames[fi]
        local pv = slurp(FRAMES .. "/frame" .. n .. ".before.visual.bin")
        local pp = slurp(FRAMES .. "/frame" .. n .. ".before.priority.bin")
        for i = 1, PLANE do prog:write_u8(CP_VIS + i - 1, pv:byte(i)) end
        for i = 1, PLANE do prog:write_u8(CP_PRI + i - 1, pp:byte(i)) end
        sprites = {}
        for line in io.lines(STAGE .. "/f" .. n .. ".spr.txt") do
            local t = {}
            for v in line:gmatch("%-?%d+") do t[#t + 1] = tonumber(v) end
            if #t >= 8 then sprites[#sprites + 1] = t end
        end
        celblob = slurp(STAGE .. "/f" .. n .. ".cels.bin")
        si = 1
        state = "stage"; return
    end

    if state == "stage" then
        if si > #sprites then fi = fi + 1; state = "next"; return end
        local s = sprites[si]
        local off, len = s[7], s[4] * s[5]
        for k = 1, len do prog:write_u8(CP_CEL + k - 1, celblob:byte(off + k)) end
        prog:write_u8(X, s[1]); prog:write_u8(Y, s[2]); prog:write_u8(PRIO, s[3])
        prog:write_u8(CW, s[4]); prog:write_u8(CH, s[5]); prog:write_u8(CKEY, s[6])
        prog:write_u8(MODE, 5); prog:write_u8(GO, 1)     -- zero the counters
        state = "zeroed"; return
    end

    if state == "zeroed" then
        prog:write_u8(N, math.floor(REPS / 256)); prog:write_u8(N + 1, REPS % 256)
        prog:write_u8(MODE, 3)
        t0 = m.time:as_double()
        prog:write_u8(GO, 1)
        state = "timing"; return
    end

    if state == "timing" then
        local dt = m.time:as_double() - t0
        local s = sprites[si]
        csv:write(string.format("%s,%d,%d,%d,%d,%.9f,%d,%d,%d,%d,%d,%d\n",
            frames[fi], si - 1, s[4], s[5], REPS, dt,
            rd32(TESTED), rd32(WRITTEN), rd32(REJPRI), rd32(REJKEY),
            rd32(CTRLHIT), rd32(CTRLSTEP)))
        si = si + 1
        state = "stage"; return
    end
end)
