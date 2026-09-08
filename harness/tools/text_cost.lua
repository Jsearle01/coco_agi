-- harness/tools/text_cost.lua -- AC-7: what a glyph and a message window actually cost.
-- [T-P0-075]
--
-- ★★★★★ THE FIRST ATTEMPT MEASURED THE HARNESS, and the numbers said so if you read them: a
-- three-glyph message "cost" 84,626 cycles per glyph and a ninety-six-glyph one 6,067. **A
-- per-unit cost that falls as units are added is a fixed overhead being divided**, and the fixed
-- overhead was a 32,000-byte plane clear plus frame-quantised handshake round-trips.
--
-- ★★★★ So this drives text_show.s's timing loop instead: N iterations of the same message, no
-- clear, no handshake inside the interval, one bracket around the whole run. Two arms, differing
-- in exactly one thing -- whether txt_blit runs -- so the subtraction names the blitter and the
-- remainder names substitution + wrap + placement.
--
-- ★★★ m.time is EMULATED time (§2U.1), so -nothrottle cannot move the answer; the clock rate is
-- read and printed rather than labelled [p3b_run.lua's "@1.789390 MHz" while running at 0.894].
--
-- ★★ Environment: TC_ITER, TC_NOBLIT, and text_show.lua's staging variables.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG  = os.getenv("TS_PROG")  or "build/text_show.bin"
local FONT  = os.getenv("TS_FONT")  or "build/text_font.bin"
local TABLE = os.getenv("TS_TABLE") or "build/text_table.bin"
local MSGS  = os.getenv("TS_MSGS")  or "build/text_cases.bin"
local MAP   = os.getenv("TS_MAP")   or "build/text_show.map"
local ITER  = tonumber(os.getenv("TC_ITER") or "50")
local NOBLIT = tonumber(os.getenv("TC_NOBLIT") or "0")

local TS_GO, TS_DONE, TS_PAGE = 0x0020, 0x0021, 0x0022
local TS_NMSG_A, TS_ITER_A, TS_NOBLIT_A = 0x0023, 0x0024, 0x0025
local TS_FONT, TS_TABLE, TS_MSGS = 0x3000, 0x3800, 0x6000

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

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

prog:write_u8(0xFF98, 0x80)
prog:write_u8(0xFF99, 0x3E)
for i = 0, 15 do prog:write_u8(0xFFB0 + i, 0x00) end
local BLK = 32
for s = 0, 3 do prog:write_u8(0xFFA4 + s, BLK + s) end
prog:write_u8(0xFF9D, ((BLK * 1024) >> 8) & 0xFF)
prog:write_u8(0xFF9E, (BLK * 1024) & 0xFF)

local booted, t0, done = false, nil, false

_G._tc = emu.add_machine_frame_notifier(function()
    if not booted then
        if m.time:as_double() < 0.3 then return end
        booted = true
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        poke(0x2000, blob)
        local font = slurp(FONT)
        if not font or #font ~= 2048 then print("★★★ bad font"); m:exit(); return end
        poke(TS_FONT, font)

        local t = slurp(TABLE)
        local nent = t:byte(1) * 256 + t:byte(2)
        local textbase = TS_TABLE + 2 + nent * 2
        for i = 0, nent - 1 do
            local o = t:byte(3 + i * 2) * 256 + t:byte(4 + i * 2)
            local p = (o == 0xFFFF) and 0 or (textbase + o)
            prog:write_u8(TS_TABLE + i * 2, (p >> 8) & 0xFF)
            prog:write_u8(TS_TABLE + i * 2 + 1, p & 0xFF)
        end
        poke(textbase, t:sub(5 + nent * 2))
        if sym["txt_l0n"] then prog:write_u8(sym["txt_l0n"], nent & 0xFF) end
        if sym["txt_curn"] then prog:write_u8(sym["txt_curn"], nent & 0xFF) end

        -- ★★ ONE message staged, and the timing loop redraws that one. Using many would average
        -- over lengths and hide the per-glyph slope this measurement exists to find.
        local blob2 = slurp(MSGS)
        local j = blob2:find("\0", 1, true)
        poke(TS_MSGS, blob2:sub(1, j))
        prog:write_u8(TS_NMSG_A, 0)              -- ★ skip the paced box page entirely
        prog:write_u8(TS_ITER_A, ITER)
        prog:write_u8(TS_NOBLIT_A, NOBLIT)
        cpu.state["PC"].value = 0x2000
        prog:write_u8(TS_GO, 1)
        return
    end

    if done then return end
    local page = prog:read_u8(TS_PAGE)
    -- ★★★★★ KEEP RAISING GO UNTIL THE GUEST MOVES. text_show.s clears TS_GO itself before waiting
    -- on it, because $0020 is in the direct page and DECB was there a moment ago -- so a GO set in
    -- the same frame as the PC is erased by the guest's own initialisation. **The first run of
    -- this file set GO once and produced no output at all**, which is parser_probe.s's handshake
    -- lesson arriving from the other side: there the leftover GO started the probe too early,
    -- here the cleared GO never started it.
    if page == 0 and not t0 then
        prog:write_u8(TS_GO, 1)
    end
    if page == 2 and not t0 then
        t0 = m.time:as_double()
        return
    end
    if page == 0xFF and t0 then
        done = true
        local dt = m.time:as_double() - t0
        local hz, src = nil, "?"
        if type(cpu.clock) == "number" and cpu.clock > 0 then
            hz, src = cpu.clock, "device.clock"
        end
        if not hz then hz, src = 894886, "coco3 power-on rate (probe sets no SAM speed)" end
        local ng = 0
        if sym["txt_ng"] then
            ng = prog:read_u8(sym["txt_ng"]) * 256 + prog:read_u8(sym["txt_ng"] + 1)
        end
        local cyc = dt * hz
        print(string.format("ARM noblit=%d  iter=%d  glyphs/msg=%d", NOBLIT, ITER, ng))
        print(string.format("  %.4f s emulated, %.0f cycles total  [%.0f Hz via %s]",
                            dt, cyc, hz, src))
        print(string.format("  per message window: %.0f cycles", cyc / ITER))
        if ng > 0 then
            print(string.format("  per glyph:          %.0f cycles", cyc / (ITER * ng)))
        end
        m:exit()
    end
end)
