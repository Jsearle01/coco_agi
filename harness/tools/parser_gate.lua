-- harness/tools/parser_gate.lua -- run the PORTED parser over the gate's cases. [T-P0-059 AC-7]
--
-- ★★★★ THE SAME CASE FILE THE ORACLE READ. said_gate.py --emit writes oracle_parser_cases.txt
-- as "<operands>TAB<input>"; this stages that same file, byte for byte, into the probe. The 6809
-- is then diffed against tools/agivm/parser.py, which is itself gated against the oracle at
-- 23,328 cases across five titles with zero divergence -- so the chain is 6809 -> Python ->
-- ScummVM without needing an emulated ScummVM.
--
-- ★★★★★ FED IN CHUNKS, AND THE CHUNK SIZE IS A MEASUREMENT. The case block for one title is
-- 32,273 bytes from $6000 and runs through PP_RESULTS at $A000; a single-shot run had the probe
-- reading bytes its own results had overwritten, from roughly case 993 onward. The symptom was
-- one word tokenising as unknown -- correct in isolation, wrong after 992 cases. So a chunk is
-- sized to fit between $6000 and $A000 with its results fitting above.
--
-- ★★ Environment: PARSER_PROG, PARSER_WORDS, PARSER_CASES, PARSER_OUT, PARSER_CHUNK.
-- ★ §2P: stages a vocabulary and input text, writes word NUMBERS. Nothing is printed.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG   = os.getenv("PARSER_PROG")  or "build/parser_probe.bin"
local WORDS  = os.getenv("PARSER_WORDS") or ""
local CASES  = os.getenv("PARSER_CASES") or ""
local OUT    = os.getenv("PARSER_OUT")   or "build/parser_6809_results.txt"
local CHUNK  = tonumber(os.getenv("PARSER_CHUNK") or "400")

local MAP    = os.getenv("PARSER_MAP")   or "build/parser_probe.map"

-- ★★★★★ SYMBOLS COME FROM THE MAP, NEVER FROM A LITERAL. The stall dump below carried three
-- hard-coded addresses ($21A9/$21AD/$20E6) taken from an earlier build. Every one was 2 bytes
-- low after the source grew, so the dump printed neighbouring bytes as `fpos` -- and it printed
-- 33849, which reads exactly like a runaway cursor. **Four titles were investigated as a parser
-- defect on the strength of a number the diagnostic itself invented.**
-- ★★★ A diagnostic that can go stale silently is worse than no diagnostic: it does not fail, it
-- testifies. So these are read from the assembler's own map and a missing one is fatal.
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
        print(string.format("★★★ no symbol '%s' in %s -- rebuild with --map", n, MAP))
        m:exit()
        error("missing symbol " .. n)
    end
    return sym[n]
end

-- ★★★★ AND THE MAP MUST BE AS NEW AS THE BINARY, or reading it just moves the staleness one file
-- along: `lwasm` without --map leaves the old map in place beside a new .bin, and every symbol is
-- wrong again with nothing to say so. Checked at boot rather than at first use, so a stale map
-- fails the run instead of failing the diagnostic that was supposed to explain the run.
-- ★★★★ `lfs` IS NOT A GLOBAL IN MAME'S LUA -- it is there, but only via require("lfs").
-- The first version of this guard read the global, got nil, fell through to its "does the file
-- exist" fallback and compared 0 < 0. **It passed a deliberately stalened map**, i.e. it was an
-- assertion that could not fire -- the same defect class it was written to prevent, one file
-- along. It was caught only by trying to break it [an assertion you have not broken is not an
-- assertion]. Recorded in mame-idioms-coco3-port.md.
local lfs = select(2, pcall(require, "lfs"))
local function mtime(p)
    local ok, a = pcall(function() return lfs and lfs.attributes(p, "modification") end)
    if ok and a then return a end
    return nil                                  -- unknown: the caller must not silently pass
end

-- ★★ And resolve the PC to the nearest symbol at or below it. "$22E3" needs the map read by hand
-- every time; "par_fi_cmp+7" does not, and a stall report is read far more often than it is made.
local function nearest(addr)
    local bn, bv = nil, -1
    for n, v in pairs(sym) do
        if v <= addr and v > bv then bn, bv = n, v end
    end
    if not bn then return "?" end
    return string.format("%s+%d", bn, addr - bv)
end

local PP_GO, PP_DONE, PP_NCASE, PP_RUN = 0x0020, 0x0021, 0x0022, 0x0024
local VOCAB, CASEBUF, RESULTS = 0x4000, 0x6000, 0xA000
local CASE_LIMIT = RESULTS - CASEBUF        -- ★ the hard bound the first version ignored

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end

local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

-- read every case up front, host-side: the file is small and this keeps the staging simple
local cases = {}
for line in io.lines(CASES) do
    if line ~= "" and line:sub(1, 1) ~= "#" then
        local tab = line:find("\t")
        if tab then
            cases[#cases + 1] = { ops = line:sub(1, tab - 1), text = line:sub(tab + 1) }
        end
    end
end

local outf = io.open(OUT, "w")
local phase, cursor, staged_n, booted = "boot", 1, 0, false

local function stage_chunk()
    local addr, n = CASEBUF, 0
    while cursor + n <= #cases and n < CHUNK do
        local c = cases[cursor + n]
        local vals = {}
        for v in c.ops:gmatch("[^,]+") do vals[#vals + 1] = tonumber(v) or 0 end
        local need = 1 + #vals * 2 + #c.text + 1
        if addr - CASEBUF + need > CASE_LIMIT then break end
        prog:write_u8(addr, #vals); addr = addr + 1
        for _, v in ipairs(vals) do
            prog:write_u8(addr, v & 0xFF)
            prog:write_u8(addr + 1, (v >> 8) & 0xFF)   -- ★ LE: the AGI stream's own order
            addr = addr + 2
        end
        for i = 1, #c.text do prog:write_u8(addr, c.text:byte(i)); addr = addr + 1 end
        prog:write_u8(addr, 0); addr = addr + 1
        n = n + 1
    end
    staged_n = n
    prog:write_u8(PP_NCASE, (n >> 8) & 0xFF)
    prog:write_u8(PP_NCASE + 1, n & 0xFF)
    prog:write_u8(PP_GO, 1)
end

local function read_chunk()
    local addr = RESULTS
    for _ = 1, staged_n do
        local cnt = prog:read_u8(addr); addr = addr + 1
        local ids = {}
        for _ = 1, cnt do
            -- ★★★★ BIG-ENDIAN: STD stores high byte first and the probe writes the ego array
            -- with two `lda ,x+ / sta ,y+` pairs. Reading it little-endian gave 40960 for 160
            -- and 512 for 2 -- the ids were right and the byte order was not, which reads as a
            -- parser defect and is a wire-format one.
            -- ★★ The OPERANDS going the other way are LITTLE-endian, because that is the AGI
            -- instruction stream's order [op_test.cpp READ_LE_UINT16]. Two orders, both stated.
            ids[#ids + 1] = (prog:read_u8(addr) << 8) | prog:read_u8(addr + 1)
            addr = addr + 2
        end
        local r = prog:read_u8(addr); addr = addr + 1
        outf:write(string.format("%d ego=%s -> %d\n", cursor - 1, table.concat(ids, ","), r))
        cursor = cursor + 1
    end
end

_G._pg = emu.add_machine_frame_notifier(function()
    if not booted then
        if m.time:as_double() < 0.3 then return end
        booted = true
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        local tb, tm = mtime(PROG), mtime(MAP)
        if not tm then
            print(string.format("★★★ cannot stat %s -- no symbol map, or lfs unavailable. "
                                .. "Assemble with --map=%s.", MAP, MAP))
            m:exit(); return
        end
        if tb and tm < tb then
            print(string.format("★★★ %s is OLDER than %s -- the map is stale and every symbol "
                                .. "it names is a guess. Re-assemble with --map.", MAP, PROG))
            m:exit(); return
        end
        poke(0x2000, blob)
        local w = slurp(WORDS)
        if not w then print("★★★ no vocabulary at " .. WORDS); m:exit(); return end
        if #w > 8192 then
            print(string.format("★★★ vocabulary is %d bytes, past the 8,192 window", #w))
            m:exit(); return
        end
        poke(VOCAB, w)
        print(string.format("staged: program %d B, vocabulary %d B, %d cases, chunk %d",
                            #blob, #w, #cases, CHUNK))
        cpu.state["PC"].value = 0x2000
        phase = "stage"
        return
    end

    if phase == "stage" then
        if cursor > #cases then
            outf:close()
            print(string.format("★ %d results written to %s", cursor - 1, OUT))
            m:exit(); return
        end
        stage_chunk()
        phase = "run"
        return
    end

    if phase == "run" then
        if prog:read_u8(PP_DONE) ~= 1 then
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE BUDGET IS AGAINST PROGRESS, NOT AGAINST THE CHUNK. The first version
            -- started a 20-second clock when a chunk began and never restarted it, so a chunk
            -- that took longer than 20 emulated seconds was declared STALLED **while it was
            -- working**. 224 cases fit; 254 did not. Four titles were reported as diverging and
            -- King's Quest 1 -- the smallest corpus -- as passing, which reads exactly like a
            -- parser defect that the bigger dictionaries expose.
            -- ★★★★ It was a measurement of the harness's own clock. The PC in the dump landed in
            -- par_fi_cmp's character loop every time for the honest reason that that is where a
            -- working parser spends its time, and the loop is provably bounded (B decrements).
            -- ★★★ So: reset the clock whenever PP_RUN advances. A probe that is completing cases
            -- is not stalled however long it takes; a probe that is not is stalled in 20 seconds.
            -- ═══════════════════════════════════════════════════════════════════════════════
            local run_now = prog:read_u8(PP_RUN) * 256 + prog:read_u8(PP_RUN + 1)
            if _G._pg_run ~= run_now then _G._pg_run, _G._pg_t = run_now, m.time:as_double() end
            if not _G._pg_t then _G._pg_t = m.time:as_double() end
            if m.time:as_double() - _G._pg_t > 20 then
                -- ★★ Report the PARSER's own cursors, not just the PC. A stall in par_parse
                -- looks identical to one in par_find from the outside, and par_flen == 0 is
                -- the specific way par_parse fails to advance.
                -- ★★ Report the PARSER's own cursors, not just the PC: a stall in par_parse
                -- looks identical to one in par_find from the outside. ★ And name the CASE --
                -- a stall that appears only on the bigger titles is far more likely to be one
                -- input than the walk itself.
                local FPOS, FLEN, EGON = symbol("par_fpos"), symbol("par_flen"), symbol("par_egon")
                local run = prog:read_u8(PP_RUN) * 256 + prog:read_u8(PP_RUN + 1)
                -- ★★★ AND THE STACK POINTER. A stall whose threshold is a CASE COUNT rather than a
                -- case is an accumulating resource, and on a 6809 with a fixed `lds` there is
                -- exactly one that accumulates per call.
                print(string.format(
                    "★★★ stalled: DONE=%d RUN=%d GO=%d PC=$%04X (%s) S=$%04X staged=%d fpos=%d flen=%d egon=%d",
                    prog:read_u8(PP_DONE), run, prog:read_u8(PP_GO),
                    cpu.state["PC"].value, nearest(cpu.state["PC"].value),
                    cpu.state["S"].value, staged_n,
                    prog:read_u8(FPOS) * 256 + prog:read_u8(FPOS + 1),
                    prog:read_u8(FLEN), prog:read_u8(EGON)))
                local idx = cursor + run
                local c = cases[idx]
                print(string.format("     case %d: ops=%s input %d chars",
                                    idx, c and c.ops or "?", c and #c.text or -1))
                -- ★★ Dump the two buffers. fpos running past the end means the cleaned string
                -- lost its terminator or never got one; only the bytes can say which.
                local function dump(name, base, n)
                    local t = {}
                    for i = 0, n - 1 do t[#t + 1] = string.format("%02X", prog:read_u8(base + i)) end
                    print(string.format("     %s: %s", name, table.concat(t, " ")))
                end
                dump("inbuf ", 0x3E00, 40)
                dump("clnbuf", 0x3F00, 40)
                m:exit()
            end
            return
        end
        _G._pg_t, _G._pg_run = nil, nil
        read_chunk()
        prog:write_u8(PP_GO, 0)          -- acknowledge; the probe clears DONE and waits
        phase = "ack"
        return
    end

    if phase == "ack" then
        if prog:read_u8(PP_DONE) ~= 0 then return end
        phase = "stage"
    end
end)
