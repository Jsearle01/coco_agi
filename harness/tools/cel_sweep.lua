-- harness/tools/cel_sweep.lua -- decode every queued cel on the 6809 and dump the pixels.
--
-- ★★ ONE MAME LAUNCH PER TITLE. The work list interleaves `view` lines (stage this resource)
-- with `cel` lines (decode this loop/cel of the resource last staged), so a VIEW is written
-- once and all its cels are decoded against it. Staging per cel would multiply the host writes
-- by seven and measure Lua rather than the 6809.
--
-- ★ The probe is DECODE-ONLY and its map has no screen planes -- see cel_probe.s. Nothing here
-- touches the MMU: everything the host writes is below $8000 in the guest's flat all-RAM map.
--
-- ★ §2P: cel pixels are copyrighted game content. They are written to build/, which is not
-- tracked, and the gate that reads them reports counts and hashes.

local OUT   = os.getenv("CEL_OUT")   or "build/cel_sweep"
local PROG  = os.getenv("CEL_PROG")  or "build/cel_probe.bin"
local STAGE = os.getenv("CEL_STAGE") or "build/cel_stage/Kingquest1"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD      = 0x0700
local CP_VIEW   = 0x2000
local CP_CEL    = 0x4000
local GO, MODE  = 0x0080, 0x0081
local LOOPNR, CELNR = 0x0082, 0x0083
local ERR, W, H, KEY, MIR = 0x0087, 0x0088, 0x0089, 0x008A, 0x008B
local VIEWLEN   = 0x008C

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local logf = io.open(OUT .. "/run.log", "w")
local function w_(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end

-- ── the work list ──────────────────────────────────────────────────────────────────────
local work = {}
do
    local f = io.open(STAGE .. "/work.txt", "r")
    if not f then w_("★★★ no work.txt in %s -- run cel_stage.py first", STAGE); return end
    for line in f:lines() do
        local kind, a, b, c = line:match("^(%a+)%s+(%d+)%s*(%d*)%s*(%d*)$")
        if kind then
            work[#work + 1] = { kind, tonumber(a), tonumber(b), tonumber(c) }
        end
    end
    f:close()
end
w_("work list: %d entries from %s", #work, STAGE)

local blob = io.open(OUT .. "/cels.bin", "wb")
local man  = io.open(OUT .. "/cels.txt", "w")
local blobOffset = 0

local i, frame, state = 1, 0, "load"
local staged, decoded, errors = 0, 0, 0

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
        state = "boot"
        return
    end

    if state == "boot" then
        if prog:read_u8(GO) ~= 0 then return end
        w_("guest at its gate (frame %d) -- all-RAM live", frame)
        state = "run"
        return
    end

    if prog:read_u8(GO) ~= 0 then return end        -- still working

    -- collect the previous decode, if there was one
    if state == "pending" then
        local e = prog:read_u8(ERR)
        local ww, hh = prog:read_u8(W), prog:read_u8(H)
        -- ★ THE LOCALISER (§5). A wrong loop offset, a wrong cel offset and a wrong header read
        -- all present as "the width is wrong". These four numbers separate them in one line.
        if decoded + errors < 3 then
            w_("  diag v%d l%d c%d: loopoff $%04X nloops %d ncels %d src $%04X -> %dx%d err %d",
               pend[1], pend[2], pend[3],
               prog:read_u8(0x00A8) * 256 + prog:read_u8(0x00A9),
               prog:read_u8(0x00AA), prog:read_u8(0x00AB),
               prog:read_u8(0x00AC) * 256 + prog:read_u8(0x00AD), ww, hh, e)
        end
        if e ~= 0 then
            errors = errors + 1
            if errors <= 6 then
                w_("★★★ decode error %d on view %d loop %d cel %d",
                   e, pend[1], pend[2], pend[3])
            end
            man:write(string.format("%d %d %d ERR %d\n", pend[1], pend[2], pend[3], e))
        else
            local n = ww * hh
            local t = {}
            for k = 0, n - 1 do t[#t + 1] = string.char(prog:read_u8(CP_CEL + k)) end
            blob:write(table.concat(t))
            man:write(string.format("%d %d %d %d %d %d %d %d\n",
                pend[1], pend[2], pend[3], ww, hh,
                prog:read_u8(KEY), prog:read_u8(MIR), blobOffset))
            blobOffset = blobOffset + n
            decoded = decoded + 1
        end
        state = "run"
    end

    if i > #work then
        blob:close(); man:close()
        w_("★ %d views staged, %d cels decoded, %d errors -> %s", staged, decoded, errors, OUT)
        m:exit()
        return
    end

    local e = work[i]; i = i + 1
    if e[1] == "view" then
        local d = slurp(STAGE .. string.format("/view%03d.bin", e[2]))
        if not d then w_("★★★ missing view%03d.bin", e[2]); m:exit(); return end
        for k = 1, #d do prog:write_u8(CP_VIEW + k - 1, d:byte(k)) end
        prog:write_u8(VIEWLEN, math.floor(#d / 256))
        prog:write_u8(VIEWLEN + 1, #d % 256)
        staged = staged + 1
        curview = e[2]
        return                                       -- staging costs no guest cycle
    end

    -- a cel: ask the guest to decode it
    pend = { e[2], e[3], e[4] }
    prog:write_u8(LOOPNR, e[3])
    prog:write_u8(CELNR, e[4])
    prog:write_u8(MODE, 1)
    prog:write_u8(GO, 1)
    state = "pending"
end)
