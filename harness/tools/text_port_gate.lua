-- harness/tools/text_port_gate.lua -- run the PORTED text engine over the gate's messages.
-- [T-P0-075 AC-3]
--
-- ★★★★ THE SAME MESSAGE LIST THE REFERENCE RAN. text_port_gate.py --emit writes the sweep's own
-- messages, NUL-terminated, plus logic 0's pointer table; this stages both byte for byte and
-- reads the probe's decision records back. The comparison is --check's, not this file's.
--
-- ★★★★★ FED IN CHUNKS, AND THE CHUNK IS BOUNDED AT BOTH ENDS. The parser gate learned this the
-- expensive way: a single-shot run had the probe reading bytes its own results had overwritten
-- from case 993 onward, and the symptom was a plausible wrong answer rather than a crash. Here
-- the MESSAGE area and the RESULT area are disjoint regions, and the probe additionally refuses a
-- message when fewer than 4,812 result bytes remain -- setting TX_ROVF so this file shortens the
-- chunk rather than discovering the truncation in the diff.
--
-- ★★ Environment: TXP_PROG, TXP_CASES, TXP_TABLE, TXP_OUT, TXP_CHUNK, TXP_MAP.
-- ★ §2P: stages message text into RAM, writes positions, colours and checksums. Nothing printed.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG  = os.getenv("TXP_PROG")  or "build/text_probe.bin"
local CASES = os.getenv("TXP_CASES") or "build/text_cases.bin"
local TABLE = os.getenv("TXP_TABLE") or "build/text_table.bin"
local OUT   = os.getenv("TXP_OUT")   or "build/text_6809_results.bin"
local CHUNK = tonumber(os.getenv("TXP_CHUNK") or "64")
local MAP   = os.getenv("TXP_MAP")   or "build/text_probe.map"

-- ★★★★★ SYMBOLS FROM THE MAP, NEVER FROM A LITERAL, and the map must be as new as the binary.
-- parser_gate.lua's header records what a stale hard-coded address cost: a diagnostic that
-- printed `fpos=33849` from three addresses that had gone two bytes stale, and four titles
-- investigated on the strength of a number the diagnostic invented.
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

-- ★★★★ `lfs` IS NOT A GLOBAL IN MAME'S LUA -- only via require("lfs"). A guard that read the
-- global got nil, fell through to a "does the file exist" fallback, compared 0 < 0 and passed a
-- deliberately stalened map [P6.3]. This is the corrected form.
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

local TX_GO, TX_DONE, TX_NMSG, TX_RUN, TX_ROVF = 0x0020, 0x0021, 0x0022, 0x0024, 0x0026
local TX_TABLE, TX_MSGS   = 0x3000, 0x5000
local TX_MSGS_END         = 0x9000
local TX_RESULTS, TX_RES_END = 0x9400, 0xFE00

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end

local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

-- split the case blob into NUL-terminated messages, host-side
local cases = {}
do
    local blob = slurp(CASES)
    if not blob then print("★★★ no cases at " .. CASES); os.exit(1) end
    local i = 1
    while i <= #blob do
        local j = blob:find("\0", i, true)
        if not j then break end
        cases[#cases + 1] = blob:sub(i, j)      -- keep the terminator
        i = j + 1
    end
end

local outf = io.open(OUT, "wb")
local phase, cursor, staged_n, booted = "boot", 1, 0, false
local chunk = CHUNK

local function stage_chunk()
    local addr, n = TX_MSGS, 0
    while cursor + n <= #cases and n < chunk do
        local c = cases[cursor + n]
        if addr + #c > TX_MSGS_END then break end
        poke(addr, c)
        addr = addr + #c
        n = n + 1
    end
    staged_n = n
    prog:write_u8(TX_NMSG, (n >> 8) & 0xFF)
    prog:write_u8(TX_NMSG + 1, n & 0xFF)
    prog:write_u8(TX_ROVF, 0)
    prog:write_u8(TX_GO, 1)
end

local function read_chunk()
    -- ★★★ The probe stops early on an overflow and reports how many it actually did, so the
    -- number of records read is TX_RUN and not what was staged. A reader that trusted the staged
    -- count would read whatever followed the last record as a record.
    local ran = prog:read_u8(TX_RUN) * 256 + prog:read_u8(TX_RUN + 1)
    local ovf = prog:read_u8(TX_ROVF)
    local addr, done, bytes = TX_RESULTS, 0, {}
    while done < ran and addr < TX_RES_END do
        local tag = prog:read_u8(addr)
        if tag == 0x47 then                     -- 'G', 7 bytes
            for k = 0, 6 do bytes[#bytes + 1] = string.char(prog:read_u8(addr + k)) end
            addr = addr + 7
        elseif tag == 0x4D then                 -- 'M', 16 bytes
            for k = 0, 15 do bytes[#bytes + 1] = string.char(prog:read_u8(addr + k)) end
            addr = addr + 16
            done = done + 1
        else
            print(string.format("★★★ bad record tag $%02X at $%04X after %d messages",
                                tag, addr, done))
            m:exit(); return
        end
    end
    outf:write(table.concat(bytes))
    cursor = cursor + ran
    if ovf ~= 0 and ran < staged_n then
        -- shrink so the next attempt fits; never below 1, or the run cannot progress
        chunk = math.max(1, math.floor(chunk / 2))
        print(string.format("  result buffer full after %d of %d -- chunk now %d",
                            ran, staged_n, chunk))
    end
end

_G._tx = emu.add_machine_frame_notifier(function()
    if not booted then
        if m.time:as_double() < 0.3 then return end
        booted = true
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        local tb, tm = mtime(PROG), mtime(MAP)
        if not tm then
            print(string.format("★★★ cannot stat %s -- no symbol map, or lfs unavailable.", MAP))
            m:exit(); return
        end
        if tb and tm < tb then
            print(string.format("★★★ %s is OLDER than %s -- the map is stale and every symbol it "
                                .. "names is a guess. Re-assemble with --map.", MAP, PROG))
            m:exit(); return
        end
        poke(0x2000, blob)

        -- ── the logic-0 table: u16 count, u16 offsets, u16 textlen, then the text ──
        local t = slurp(TABLE)
        if not t then print("★★★ no table at " .. TABLE); m:exit(); return end
        local nent = t:byte(1) * 256 + t:byte(2)
        local tlen = t:byte(3 + nent * 2) * 256 + t:byte(4 + nent * 2)
        local textbase = TX_TABLE + 2 + nent * 2
        if textbase + tlen > TX_MSGS then
            print(string.format("★★★ logic-0 text block is %d bytes; %d available before $%04X",
                                tlen, TX_MSGS - textbase, TX_MSGS))
            m:exit(); return
        end
        -- ★★ Offsets become ABSOLUTE pointers here, once, rather than in the probe: the 6809's
        -- %g/%m path is then a table lookup and nothing else. 0xFFFF marks an absent message and
        -- becomes a null pointer, which text.s tests for.
        for i = 0, nent - 1 do
            local o = t:byte(3 + i * 2) * 256 + t:byte(4 + i * 2)
            local p = (o == 0xFFFF) and 0 or (textbase + o)
            prog:write_u8(TX_TABLE + i * 2, (p >> 8) & 0xFF)
            prog:write_u8(TX_TABLE + i * 2 + 1, p & 0xFF)
        end
        poke(textbase, t:sub(5 + nent * 2))

        local L0BASE, L0N = symbol("txt_l0base"), symbol("txt_l0n")
        local CURBASE, CURN = symbol("txt_curbase"), symbol("txt_curn")
        prog:write_u8(L0BASE, (TX_TABLE >> 8) & 0xFF)
        prog:write_u8(L0BASE + 1, TX_TABLE & 0xFF)
        prog:write_u8(CURBASE, (TX_TABLE >> 8) & 0xFF)
        prog:write_u8(CURBASE + 1, TX_TABLE & 0xFF)
        -- ★★★★ %m READS LOGIC 0 IN THE SWEEP, because the sweep never sets curLogicNr and so it is
        -- 0. Measured in P6.18 against the oracle's own rectangle for Kingquest1 message 555, and
        -- the reference carries the same setting -- so both legs point here.
        prog:write_u8(L0N, nent & 0xFF)
        prog:write_u8(CURN, nent & 0xFF)

        print(string.format("staged: program %d B, %d messages, logic0 %d entries / %d text B",
                            #blob, #cases, nent, tlen))
        cpu.state["PC"].value = 0x2000
        phase = "stage"
        return
    end

    if phase == "stage" then
        if cursor > #cases then
            outf:close()
            print(string.format("★ %d messages run -> %s", cursor - 1, OUT))
            m:exit(); return
        end
        stage_chunk()
        phase = "run"
        return
    end

    if phase == "run" then
        if prog:read_u8(TX_DONE) ~= 1 then
            -- ★★★★ THE BUDGET IS AGAINST PROGRESS, NOT AGAINST THE CHUNK. The parser gate declared
            -- a working chunk stalled because its clock started when the chunk did and never
            -- restarted; 224 cases fit and 254 did not, and four titles were reported as
            -- diverging. Reset whenever TX_RUN advances.
            local run_now = prog:read_u8(TX_RUN) * 256 + prog:read_u8(TX_RUN + 1)
            if _G._tx_run ~= run_now then _G._tx_run, _G._tx_t = run_now, m.time:as_double() end
            if not _G._tx_t then _G._tx_t = m.time:as_double() end
            if m.time:as_double() - _G._tx_t > 20 then
                local pc = cpu.state["PC"].value
                print(string.format("★★★ stalled: DONE=%d RUN=%d GO=%d PC=$%04X (%s) S=$%04X "
                                    .. "staged=%d cursor=%d",
                                    prog:read_u8(TX_DONE), run_now, prog:read_u8(TX_GO),
                                    pc, nearest(pc), cpu.state["S"].value, staged_n, cursor))
                -- ★★ Name the engine's own cursors: a stall in the wrap and one in the
                -- substitution look identical from outside, and they are different bugs.
                local SRC, DST, SP = symbol("txt_src"), symbol("txt_dst"), symbol("txt_sp")
                local CR, WS, BH = symbol("txt_cr"), symbol("txt_ws"), symbol("txt_boxh")
                print(string.format("     src=$%04X dst=$%04X sp=%d  cur_read=$%04X "
                                    .. "word_start=$%04X boxh=%d",
                                    prog:read_u8(SRC) * 256 + prog:read_u8(SRC + 1),
                                    prog:read_u8(DST) * 256 + prog:read_u8(DST + 1),
                                    prog:read_u8(SP),
                                    prog:read_u8(CR) * 256 + prog:read_u8(CR + 1),
                                    prog:read_u8(WS) * 256 + prog:read_u8(WS + 1),
                                    prog:read_u8(BH)))
                -- ★★★★★ AND THE RETURN CHAIN. A PC inside a DATA region means control was
                -- transferred there, and only two things do that: a `jsr ,x` with a bad X, or an
                -- `rts`/`puls pc` pulling data as an address. **The stack says which**, and
                -- without it the investigation is a reading of the wrap that cannot conclude.
                -- ★★★ Every candidate address is resolved through the map, so a frame that IS a
                -- return address is named and one that is not reads as an offset into a buffer.
                local s = cpu.state["S"].value
                local frames = {}
                for k = 0, 11 do
                    local v = prog:read_u8(s + k * 2) * 256 + prog:read_u8(s + k * 2 + 1)
                    frames[#frames + 1] = string.format("%04X(%s)", v, nearest(v))
                end
                print("     stack: " .. table.concat(frames, " "))
                local ib = {}
                for k = -4, 6 do
                    ib[#ib + 1] = string.format("%02X", prog:read_u8(pc + k))
                end
                print(string.format("     bytes at PC-4..PC+6: %s", table.concat(ib, " ")))
                local TOUT = symbol("tx_out")
                print(string.format("     tx_out=$%04X  txt_gcb=$%04X  txt_emit=$%04X",
                                    prog:read_u8(TOUT) * 256 + prog:read_u8(TOUT + 1),
                                    prog:read_u8(symbol("txt_gcb")) * 256
                                        + prog:read_u8(symbol("txt_gcb") + 1),
                                    prog:read_u8(symbol("txt_emit")) * 256
                                        + prog:read_u8(symbol("txt_emit") + 1)))
                m:exit()
            end
            return
        end
        _G._tx_t, _G._tx_run = nil, nil
        read_chunk()
        prog:write_u8(TX_GO, 0)
        phase = "ack"
        return
    end

    if phase == "ack" then
        if prog:read_u8(TX_DONE) ~= 0 then return end
        phase = "stage"
    end
end)
