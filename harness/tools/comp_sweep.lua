-- harness/tools/comp_sweep.lua -- composite staged frames on the 6809 and diff both planes.
--
-- ★★ PER FRAME: stage the two BEFORE planes, draw every sprite in the oracle's own draw order,
-- read both planes back and compare against the oracle's AFTER planes. The comparison happens
-- here rather than in a later tool only to avoid writing 53,760 bytes per frame to disk twice;
-- the BYTES compared are the oracle's, which is what §2O.1 requires.
--
-- ★★★ DRAW ORDER IS PART OF THE INPUT. Sprites overlap, so the same set drawn in a different
-- order is a different frame. comp_stage.py preserves the order the oracle's drawSprites() used
-- and this replays it.
--
-- ★ Per-frame verdicts, never a total (L-10), and the first difference is reported as
-- plane/row/column rather than a flat offset -- "column 0 of every row" and "one pixel at row
-- 40" are different defects.

local OUT   = os.getenv("COMP_OUT")   or "build/comp_sweep"
local PROG  = os.getenv("COMP_PROG")  or "build/comp_probe.bin"
local STAGE = os.getenv("COMP_STAGE") or "build/comp_stage/SpaceQuest-1"
local FRAMES= os.getenv("COMP_FRAMES")or "oracle/dumps/frames-SpaceQuest-1"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD    = 0x0700
local CP_CEL  = 0x1100
local CP_PRI  = 0x2900
local CP_VIS  = 0x9200
local GO, MODE = 0x0080, 0x0081
local X, Y, PRIO = 0x0084, 0x0085, 0x0086
local CW, CH, CKEY = 0x0088, 0x0089, 0x008A
local W, H = 160, 168
local PLANE = W * H

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local logf = io.open(OUT .. "/run.log", "w")
local function w_(f, ...)
    local s = string.format(f, ...); logf:write(s .. "\n"); logf:flush(); print(s)
end
local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end

-- ── the frame list ─────────────────────────────────────────────────────────────────────
local frames = {}
do
    local f = io.open(STAGE .. "/frames.txt", "r")
    if not f then w_("★★★ no frames.txt in %s -- run comp_stage.py first", STAGE); return end
    for line in f:lines() do
        local n, cnt = line:match("^(%d+)%s+(%d+)$")
        if n then frames[#frames + 1] = { n, tonumber(cnt) } end
    end
    f:close()
end
w_("frames: %d from %s", #frames, STAGE)

local fi, si = 1, 0
local sprites, celblob
local frame, state = 0, "load"
local pass, fail = 0, 0

local function loadFrame(n)
    local pre_v = slurp(FRAMES .. "/frame" .. n .. ".before.visual.bin")
    local pre_p = slurp(FRAMES .. "/frame" .. n .. ".before.priority.bin")
    if not pre_v or not pre_p then return false end
    for i = 1, PLANE do prog:write_u8(CP_VIS + i - 1, pre_v:byte(i)) end
    for i = 1, PLANE do prog:write_u8(CP_PRI + i - 1, pre_p:byte(i)) end
    sprites = {}
    local f = io.open(STAGE .. "/f" .. n .. ".spr.txt", "r")
    for line in f:lines() do
        local t = {}
        for v in line:gmatch("%-?%d+") do t[#t + 1] = tonumber(v) end
        if #t >= 8 then sprites[#sprites + 1] = t end
    end
    f:close()
    celblob = slurp(STAGE .. "/f" .. n .. ".cels.bin")
    return true
end

local function compareFrame(n)
    local want_v = slurp(FRAMES .. "/frame" .. n .. ".after.visual.bin")
    local want_p = slurp(FRAMES .. "/frame" .. n .. ".after.priority.bin")
    local bad, plane, at = 0, "-", -1
    for i = 1, PLANE do
        if prog:read_u8(CP_VIS + i - 1) ~= want_v:byte(i) then
            bad = bad + 1
            if at < 0 then plane, at = "visual", i - 1 end
        end
    end
    for i = 1, PLANE do
        if prog:read_u8(CP_PRI + i - 1) ~= want_p:byte(i) then
            bad = bad + 1
            if at < 0 then plane, at = "priority", i - 1 end
        end
    end
    if bad == 0 then
        pass = pass + 1
        w_("  frame %s  %2d sprites  BOTH PLANES IDENTICAL", n, #sprites)
    else
        fail = fail + 1
        w_("  frame %s  %2d sprites  ★★★ %d byte(s) differ; first in %s at row %d col %d",
           n, #sprites, bad, plane, math.floor(at / W), at % W)
    end
end

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    if state == "load" then
        local b = slurp(PROG)
        if not b then w_("★★★ no program at %s", PROG); m:exit(); return end
        for k = 1, #b do prog:write_u8(LOAD + k - 1, b:byte(k)) end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
        w_("program %d bytes at $%04X", #b, LOAD)
        state = "boot"; return
    end
    if state == "boot" then
        if prog:read_u8(GO) ~= 0 then return end
        w_("guest at its gate (frame %d) -- all-RAM live", frame)
        state = "next"; return
    end
    if prog:read_u8(GO) ~= 0 then return end

    if state == "next" then
        if fi > #frames then
            w_("★ %d frames: %d identical, %d divergent", #frames, pass, fail)
            m:exit(); return
        end
        if not loadFrame(frames[fi][1]) then
            w_("★★★ frame %s: missing before-planes", frames[fi][1])
            fi = fi + 1; return
        end
        si = 1
        state = "draw"
        return
    end

    if state == "draw" then
        if si > #sprites then
            compareFrame(frames[fi][1])
            fi = fi + 1
            state = "next"
            return
        end
        local s = sprites[si]        -- x y prio w h key celoff obj
        local off, n = s[7], s[4] * s[5]
        for k = 1, n do prog:write_u8(CP_CEL + k - 1, celblob:byte(off + k)) end
        prog:write_u8(X, s[1]); prog:write_u8(Y, s[2]); prog:write_u8(PRIO, s[3])
        prog:write_u8(CW, s[4]); prog:write_u8(CH, s[5]); prog:write_u8(CKEY, s[6])
        prog:write_u8(MODE, 2)
        prog:write_u8(GO, 1)
        si = si + 1
        return
    end
end)
