-- harness/tools/gs_gate.lua -- run the PORTED get.string over the gate's cases. [P6.23 AC-3]
--
-- ★★★★ THE SAME SHAPE AS text_port_gate.lua, deliberately: stage in chunks, watch progress rather
-- than the clock, read symbols from the map and refuse a stale one. Those three came from real
-- incidents (a probe reading its own output, a working chunk declared stalled, a diagnostic
-- printing addresses two bytes out) and none of them is worth re-learning here.
--
-- ★★★ WHAT IT STAGES: the logic-0 pointer table and its text (for %g / %m in the lead-in), then
-- one record per case -- lead-in offset, row, column, max length, destination slot, cursor
-- character, and the key list. The probe replies with G/C records and one E record per case.
--
-- ★★ Environment: GS_PROG, GS_CASES, GS_TABLE, GS_OUT, GS_CHUNK, GS_MAP.
-- ★ §2P: stages game text and typed keys into RAM; writes positions, colours and checksums.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG  = os.getenv("GS_PROG")  or "build/gs_probe.bin"
local CASES = os.getenv("GS_CASES") or "build/gs_cases.bin"
local TABLE = os.getenv("GS_TABLE") or "build/gs_table.bin"
local OUT   = os.getenv("GS_OUT")   or "build/gs_6809_results.bin"
local CHUNK = tonumber(os.getenv("GS_CHUNK") or "24")
local MAP   = os.getenv("GS_MAP")   or "build/gs_probe.map"

local GP_GO, GP_DONE, GP_NCASE, GP_RUN = 0x0020, 0x0021, 0x0022, 0x0024
local GP_TABLE, GP_CASES = 0x3000, 0x5000
local GP_CASES_END, GP_RESULTS, GP_RES_END = 0x9000, 0x9400, 0xFE00

local sym = {}
do
    local f = io.open(MAP, "r")
    if f then
        for line in f:lines() do
            local n, v = line:match("^Symbol:%s+(%S+)%s+%b()%s+=%s+(%x+)")
            if n then sym[n] = tonumber(v, 16) end
        end
        f:close()
    end
end
local function symbol(n)
    if not sym[n] then
        print(string.format("★★★ no symbol '%s' in %s -- assemble with --map", n, MAP))
        m:exit(); error("missing symbol " .. n)
    end
    return sym[n]
end

local lfs = select(2, pcall(require, "lfs"))
local function mtime(p)
    local ok, a = pcall(function() return lfs and lfs.attributes(p, "modification") end)
    if ok and a then return a end
    return nil
end
local function nearest(addr)
    local bn, bv = nil, -1
    for n, v in pairs(sym) do
        if v <= addr and v > bv then bn, bv = n, v end
    end
    if not bn then return "?" end
    return string.format("%s+%d", bn, addr - bv)
end

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

-- the case blob is a sequence of self-describing records; split host-side
local cases = {}
do
    local blob = slurp(CASES)
    if not blob then print("★★★ no cases at " .. CASES); os.exit(1) end
    local i = 1
    while i + 7 <= #blob do
        local nk = blob:byte(i + 7)
        local rec = blob:sub(i, i + 7 + nk)
        cases[#cases + 1] = rec
        i = i + 8 + nk
    end
end

local outf = io.open(OUT, "wb")
local phase, cursor, staged_n, booted = "boot", 1, 0, false

local function stage_chunk()
    local addr, n = GP_CASES, 0
    while cursor + n <= #cases and n < CHUNK do
        local c = cases[cursor + n]
        if addr + #c > GP_CASES_END then break end
        poke(addr, c)
        addr = addr + #c
        n = n + 1
    end
    staged_n = n
    prog:write_u8(GP_NCASE, (n >> 8) & 0xFF)
    prog:write_u8(GP_NCASE + 1, n & 0xFF)
    prog:write_u8(GP_GO, 1)
end

local function read_chunk()
    local ran = prog:read_u8(GP_RUN) * 256 + prog:read_u8(GP_RUN + 1)
    local addr, done, bytes = GP_RESULTS, 0, {}
    while done < ran and addr < GP_RES_END do
        local tag = prog:read_u8(addr)
        local len
        if tag == 0x47 then len = 7          -- 'G'
        elseif tag == 0x43 then len = 4      -- 'C'
        elseif tag == 0x45 then len = 5      -- 'E', one per case
        else
            print(string.format("★★★ bad record tag $%02X at $%04X after %d cases",
                                tag, addr, done))
            m:exit(); return
        end
        for k = 0, len - 1 do bytes[#bytes + 1] = string.char(prog:read_u8(addr + k)) end
        addr = addr + len
        if tag == 0x45 then done = done + 1 end
    end
    outf:write(table.concat(bytes))
    cursor = cursor + ran
end

-- ★★★★★ READINESS COMES FROM harness/tools/decb_ready.lua, NOT FROM A FIXED DELAY. This file
-- used `if m.time:as_double() < 0.3 then return end` -- a guess at when the machine became ready
-- rather than a reading of whether it had -- and took DECB over mid-boot. Jay's standing rule,
-- broken here and in six sibling files at once [T-P0-060, T-P0-081].
local decb_ready = dofile("harness/tools/decb_ready.lua").new{ hold = 0 }

_G._gs = emu.add_machine_frame_notifier(function()
    if not booted then
        do
            local st = decb_ready(m, cpu, prog)
            if st == "timeout" then m:exit(); return end
            if st ~= "go" then return end
        end
        booted = true
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        local tb, tm = mtime(PROG), mtime(MAP)
        if not tm then print("★★★ cannot stat " .. MAP); m:exit(); return end
        if tb and tm < tb then
            print(string.format("★★★ %s is OLDER than %s -- stale map", MAP, PROG))
            m:exit(); return
        end
        poke(0x2000, blob)

        local t = slurp(TABLE)
        if not t then print("★★★ no table at " .. TABLE); m:exit(); return end
        local nent = t:byte(1) * 256 + t:byte(2)
        local textbase = GP_TABLE + 2 + nent * 2
        for i = 0, nent - 1 do
            local o = t:byte(3 + i * 2) * 256 + t:byte(4 + i * 2)
            local p = (o == 0xFFFF) and 0 or (textbase + o)
            prog:write_u8(GP_TABLE + i * 2, (p >> 8) & 0xFF)
            prog:write_u8(GP_TABLE + i * 2 + 1, p & 0xFF)
        end
        poke(textbase, t:sub(5 + nent * 2))
        prog:write_u8(symbol("txt_l0n"), nent & 0xFF)
        prog:write_u8(symbol("txt_curn"), nent & 0xFF)
        -- ★★ The probe adds this to each case's lead-in offset; the host owns the base so the
        -- guest never has to know where the host chose to put the text.
        local TB = symbol("gp_textbase")
        prog:write_u8(TB, (textbase >> 8) & 0xFF)
        prog:write_u8(TB + 1, textbase & 0xFF)

        print(string.format("staged: program %d B, %d cases, logic0 %d entries",
                            #blob, #cases, nent))
        cpu.state["PC"].value = 0x2000
        phase = "stage"
        return
    end

    if phase == "stage" then
        if cursor > #cases then
            outf:close()
            print(string.format("★ %d cases run -> %s", cursor - 1, OUT))
            m:exit(); return
        end
        stage_chunk()
        phase = "run"
        return
    end

    if phase == "run" then
        if prog:read_u8(GP_DONE) ~= 1 then
            local run_now = prog:read_u8(GP_RUN) * 256 + prog:read_u8(GP_RUN + 1)
            if _G._gs_run ~= run_now then _G._gs_run, _G._gs_t = run_now, m.time:as_double() end
            if not _G._gs_t then _G._gs_t = m.time:as_double() end
            if m.time:as_double() - _G._gs_t > 20 then
                local pc = cpu.state["PC"].value
                print(string.format("★★★ stalled: DONE=%d RUN=%d PC=$%04X (%s) S=$%04X staged=%d",
                                    prog:read_u8(GP_DONE), run_now, pc, nearest(pc),
                                    cpu.state["S"].value, staged_n))
                print(string.format("     curpos=%d maxlen=%d entered=%d done=%d",
                                    prog:read_u8(symbol("gs_curpos")),
                                    prog:read_u8(symbol("gs_maxlen")),
                                    prog:read_u8(symbol("gs_entered")),
                                    prog:read_u8(symbol("gs_done"))))
                m:exit()
            end
            return
        end
        _G._gs_t, _G._gs_run = nil, nil
        read_chunk()
        prog:write_u8(GP_GO, 0)
        phase = "ack"
        return
    end

    if phase == "ack" then
        if prog:read_u8(GP_DONE) ~= 0 then return end
        phase = "stage"
    end
end)
