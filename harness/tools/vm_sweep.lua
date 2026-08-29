-- harness/tools/vm_sweep.lua -- drive the 6809 VM one cycle per handshake and dump its state.
--
-- ★★★ THE SAMPLE IS TAKEN WHILE THE GUEST IS PARKED, BEFORE THE CYCLE RUNS. The oracle's patch
-- dumps flags+vars at cycle ENTRY, once per interpretCycle(), counted from zero. "Cycle N" has
-- to mean the same thing on both sides or the whole diff shifts by one line and reports the
-- divergence at the wrong place. The probe parks at vm_pace's exit -- after the clock ticks
-- that led to this cycle, before the cycle body -- and that is where these 288 bytes come from.
--
-- ★★ STAGING RUNS AFTER THE GUEST'S BARE-METAL TRANSITION (P1.3's lesson, unchanged): $FFA6
-- does nothing before HAL_sys_init, so a host write to the volume window lands in ROM and the
-- byte counter still reports success. The guest clearing GO is the proof the MMU is live.

local OUT   = os.getenv("VM_OUT")   or "build/vm_sweep"
local PROG  = os.getenv("VM_PROG")  or "build/vm_probe.bin"
local STAGE = os.getenv("VM_STAGE") or "build/vm_stage/Kingquest1"
local SYMF  = os.getenv("VM_SYMBOLS") or "build/vm_stage/symbols.txt"
local NCYC  = tonumber(os.getenv("VM_CYCLES") or "600")
local VMTR     = os.getenv("VM_TRACEBUF") ~= nil
local VMTR_BUF = tonumber(os.getenv("VM_TRACEBUF") or "0", 16)
local VMTR_IDX = tonumber(os.getenv("VM_TRACEIDX") or "0", 16)
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD      = 0x0700
local RES_DIRS  = 0x3000        -- vm_probe.s overrides res_core's default map
local DIR_STRIDE= 0x0400
local WINDOW    = 0xC000
local MMU_SLOT  = 0xFFA6
local VM_FLAGS  = 0x7100
local VM_VARS   = 0x7000
local GO, STATUS, BADOP, BADLOGIC, CYCLE = 0x0080, 0x0081, 0x0082, 0x0083, 0x0084

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end

-- ── the staging manifest and the build's symbol addresses ──────────────────────────────
local vols = {}
do
    local f = io.open(STAGE .. "/manifest.txt", "r")
    if not f then w("★★★ no manifest at %s -- run vm_stage.py first", STAGE); return end
    for line in f:lines() do
        local v, b, n = line:match("^vol%s+(%d+)%s+(%d+)%s+(%d+)$")
        if v then vols[#vols + 1] = { tonumber(v), tonumber(b), tonumber(n) } end
    end
    f:close()
end

-- ★ Symbols come from the BUILD, never from a copy beside the fixture (§2F). P1.3 lost half a
-- session to a stale symbols.txt that made every fetch report a bad signature.
local SYM = {}
do
    local f = io.open(SYMF, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%S+)%s+(%x+)$")
            if k then SYM[k] = tonumber(v, 16) end
        end
        f:close()
    end
end
if not SYM.res_volbase then w("★★★ %s lacks res_volbase", SYMF); return end
w("symbols from %s: res_volbase $%04X", SYMF, SYM.res_volbase)

local function stage()
    for _, e in ipairs(vols) do
        local vnr, base = e[1], e[2]
        local data = slurp(STAGE .. string.format("/vol%d.bin", vnr))
        if not data then w("★★★ missing vol%d.bin", vnr); return false end
        local nblk = math.ceil(#data / 0x2000)
        for b = 0, nblk - 1 do
            prog:write_u8(MMU_SLOT, base + b)
            local off = b * 0x2000
            for i = 0, 0x1FFF do
                local c = data:byte(off + i + 1)
                if c == nil then break end
                prog:write_u8(WINDOW + i, c)
            end
        end
        -- ★ read one byte back through the window before trusting any of it
        prog:write_u8(MMU_SLOT, base)
        local got, want = prog:read_u8(WINDOW), data:byte(1)
        w("  vol.%d %7d bytes -> %2d blocks at %2d; readback $%02X vs $%02X %s",
          vnr, #data, nblk, base, got, want, got == want and "OK" or "★★★ MISMATCH")
        if got ~= want then return false end
        -- the per-volume base, indexed by the DIR entry's volume nibble
        prog:write_u8(SYM.res_volbase + vnr, base)
    end

    for t, name in ipairs({ "logdir", "picdir", "viewdir", "snddir" }) do
        local d = slurp(STAGE .. "/" .. name .. ".bin")
        if d then
            local base = RES_DIRS + (t - 1) * DIR_STRIDE
            for i = 1, #d do prog:write_u8(base + i - 1, d:byte(i)) end
            w("  %-8s %5d bytes -> $%04X  (%d slots)", name, #d, base, math.floor(#d / 3))
        end
    end
    prog:write_u8(SYM.res_slicebase, 0)
    prog:write_u8(SYM.res_slicebase + 1, 0)
    prog:write_u8(SYM.res_curblk, 0xFF)
    return true
end

local out = io.open(OUT .. "/guest.bin", "wb")
local idx = io.open(OUT .. "/cycles.txt", "w")
idx:write("cycle,status,badop,badlogic\n")

local n, frame, state = 0, 0, "load"
_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    if state == "load" then
        local blob = slurp(PROG)
        if not blob then w("★★★ no program at %s", PROG); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
        w("program %d bytes at $%04X, PC set", #blob, LOAD)
        state = "boot"
        return
    end

    if state == "boot" then
        if prog:read_u8(GO) ~= 0 then return end
        w("guest reached its gate at frame %d -- MMU live, staging", frame)
        if not stage() then out:close(); idx:close(); m:exit(); return end
        state = "run"
        return
    end

    if prog:read_u8(GO) ~= 0 then return end        -- the guest is still in a cycle

    if n > 0 then
        local st = prog:read_u8(STATUS)
        idx:write(string.format("%d,%d,%d,%d\n", n - 1, st,
                                prog:read_u8(BADOP), prog:read_u8(BADLOGIC)))
        if st ~= 0 then
            w("★★★ guest HALTED at cycle %d: opcode $%02X in logic %d",
              n - 1, prog:read_u8(BADOP), prog:read_u8(BADLOGIC))
            w("    codelen=%d ip=%d lastop=$%02X opcount=%d icguard=%d",
              prog:read_u8(0x0086)*256 + prog:read_u8(0x0087),
              prog:read_u8(0x0088)*256 + prog:read_u8(0x0089),
              prog:read_u8(0x008A),
              prog:read_u8(0x008B)*256 + prog:read_u8(0x008C),
              prog:read_u8(0x008D))
            -- ★ dump the opcode trace on the HALT path too: the halt is exactly when it is
            -- wanted, and the first version only dumped on clean completion.
            if VMTR then
                local f = io.open(OUT .. "/trace.txt", "w")
                local ti = prog:read_u8(VMTR_IDX) * 256 + prog:read_u8(VMTR_IDX + 1)
                for i = 0, math.floor(ti / 3) - 1 do
                    f:write(string.format("%d %02X\n",
                        prog:read_u8(VMTR_BUF + i * 3) * 256 + prog:read_u8(VMTR_BUF + i * 3 + 1),
                        prog:read_u8(VMTR_BUF + i * 3 + 2)))
                end
                f:close()
                w("trace: %d steps -> %s/trace.txt", math.floor(ti / 3), OUT)
                w("    endip=%d skipword=%d", prog:read_u8(0x1515)*256+prog:read_u8(0x1516),
                  prog:read_u8(0x1517)*256+prog:read_u8(0x1518))
            end
            out:close(); idx:close(); m:exit(); return
        end
    end

    if VMTR and n >= 1 then
        local f = io.open(OUT .. "/trace.txt", "w")
        local idx = prog:read_u8(VMTR_IDX)*256 + prog:read_u8(VMTR_IDX+1)
        for i = 0, math.floor(idx/3) - 1 do
            f:write(string.format("%d %02X\n",
                prog:read_u8(VMTR_BUF+i*3)*256 + prog:read_u8(VMTR_BUF+i*3+1),
                prog:read_u8(VMTR_BUF+i*3+2)))
        end
        f:close()
        w("trace: %d steps -> %s/trace.txt", math.floor(idx/3), OUT)
        out:close(); idx = nil; m:exit(); return
    end

    if n >= NCYC then
        out:close(); idx:close()
        w("★ %d cycles complete", n)
        m:exit()
        return
    end

    if n < 3 then
        w("  cycle %d entry: opcount=%d lastop=$%02X codelen=%d", n,
          prog:read_u8(0x008B)*256 + prog:read_u8(0x008C),
          prog:read_u8(0x008A),
          prog:read_u8(0x0086)*256 + prog:read_u8(0x0087))
        w("               icguard=%d var0=%d", prog:read_u8(0x008D), prog:read_u8(0x7000))
    end

    -- ★ THE SAMPLE: 32 flag bytes then 256 var bytes, exactly the oracle.s layout.
    local buf = {}
    for i = 0, 31 do buf[#buf + 1] = string.char(prog:read_u8(VM_FLAGS + i)) end
    for i = 0, 255 do buf[#buf + 1] = string.char(prog:read_u8(VM_VARS + i)) end
    out:write(table.concat(buf))

    n = n + 1
    prog:write_u8(GO, 1)
end)
