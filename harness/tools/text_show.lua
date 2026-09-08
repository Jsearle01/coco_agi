-- harness/tools/text_show.lua -- AC-1's EYE GATE host: the ported text engine on a real screen.
-- [T-P0-075]
--
-- ★★★★★ THIS ONE RUNS AT NORMAL SPEED, AND THAT IS §2U.2 RATHER THAN AN OVERSIGHT. Every byte
-- gate in this project runs -nothrottle because nothing it measures is wall-clock. **An eye gate
-- nobody can watch at 2869% is not an eye gate**, so text_show.sh does NOT pass -nothrottle and
-- this file paces the boxes for a human.
--
-- ★★★★ WHAT JAY SHOULD SEE: a white box with black lettering appearing centred on a black screen,
-- one message at a time, wrapped exactly where the reference wraps it. The engine drawing them is
-- the same object code the port gate ran over 4,594 message boxes.
--
-- ★★★ Mode BEFORE palette is a documented constraint, not a preference: palette writes do not
-- latch until the video mode is final [gfx.s Constraint B]. The values are p3b_show.lua's, read
-- from gfx_mode_table rather than chosen here: $FF98=$80 VMODE, $FF99=$3E VRES for mode 2.
--
-- ★★ Environment: TS_PROG, TS_FONT, TS_TABLE, TS_MSGS, TS_HOLD (frames per box), TS_MAP.
-- ★ §2P: stages game text into RAM and puts it on a screen for Jay. Nothing is written to disk
-- and nothing is printed -- the report carries counts and positions, never the text.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG  = os.getenv("TS_PROG")  or "build/text_show.bin"
local FONT  = os.getenv("TS_FONT")  or "build/text_font.bin"
local TABLE = os.getenv("TS_TABLE") or "build/text_table.bin"
local MSGS  = os.getenv("TS_MSGS")  or "build/text_cases.bin"
local HOLD  = tonumber(os.getenv("TS_HOLD") or "90")
local NMSG  = tonumber(os.getenv("TS_NMSG") or "12")
local MAP   = os.getenv("TS_MAP")   or "build/text_show.map"

local TS_GO, TS_DONE, TS_PAGE, TS_NMSG_A = 0x0020, 0x0021, 0x0022, 0x0023
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

-- ★★★★★ MODE AND A BLACK PALETTE ASSERTED AT TAKEOVER, not when the guest gets around to it.
-- p3b_show.lua's header records the alternative: the display showed whatever the previous mode
-- was pointing at until the guest ran, which Jay saw as garbage before the title screen.
prog:write_u8(0xFF98, 0x80)
prog:write_u8(0xFF99, 0x3E)
for i = 0, 15 do prog:write_u8(0xFFB0 + i, 0x00) end

-- ★★★★ THE PLANE IS MAPPED FLAT ACROSS SLOTS 4-7 and VOFFSET points at the same blocks. 32,000
-- bytes needs four 8 KB blocks; the guest addresses them at $8000-$FCFF and the GIME scans them
-- from block 32 upward. **Both halves have to agree or the guest draws into memory nobody is
-- looking at** -- which is invisible, and looks exactly like a text engine that draws nothing.
local BLK = 32
for s = 0, 3 do prog:write_u8(0xFFA4 + s, BLK + s) end
prog:write_u8(0xFF9D, ((BLK * 1024) >> 8) & 0xFF)
prog:write_u8(0xFF9E, (BLK * 1024) & 0xFF)

local booted, shown, held = false, 0, 0

_G._ts = emu.add_machine_frame_notifier(function()
    if not booted then
        if m.time:as_double() < 0.3 then return end
        booted = true
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        poke(0x2000, blob)

        local font = slurp(FONT)
        if not font or #font ~= 2048 then
            print(string.format("★★★ font is %s bytes, expected 2048 -- run "
                                .. "harness/tools/text_font_stage.py", font and #font or "no"))
            m:exit(); return
        end
        poke(TS_FONT, font)

        -- the logic-0 table, offsets -> absolute pointers, exactly as the gate host does it
        local t = slurp(TABLE)
        if not t then print("★★★ no table at " .. TABLE); m:exit(); return end
        local nent = t:byte(1) * 256 + t:byte(2)
        local tlen = t:byte(3 + nent * 2) * 256 + t:byte(4 + nent * 2)
        local textbase = TS_TABLE + 2 + nent * 2
        if textbase + tlen > TS_MSGS then
            print(string.format("★★★ logic-0 text block is %d bytes; %d available",
                                tlen, TS_MSGS - textbase))
            m:exit(); return
        end
        for i = 0, nent - 1 do
            local o = t:byte(3 + i * 2) * 256 + t:byte(4 + i * 2)
            local p = (o == 0xFFFF) and 0 or (textbase + o)
            prog:write_u8(TS_TABLE + i * 2, (p >> 8) & 0xFF)
            prog:write_u8(TS_TABLE + i * 2 + 1, p & 0xFF)
        end
        poke(textbase, t:sub(5 + nent * 2))
        if sym["txt_l0n"] then prog:write_u8(sym["txt_l0n"], nent & 0xFF) end
        if sym["txt_curn"] then prog:write_u8(sym["txt_curn"], nent & 0xFF) end

        -- the messages: the first NMSG of the same list the port gate ran
        local blob2 = slurp(MSGS)
        if not blob2 then print("★★★ no messages at " .. MSGS); m:exit(); return end
        local addr, n, i = TS_MSGS, 0, 1
        while n < NMSG and i <= #blob2 do
            local j = blob2:find("\0", i, true)
            if not j then break end
            local msg = blob2:sub(i, j)
            poke(addr, msg)
            addr = addr + #msg
            i = j + 1
            n = n + 1
        end
        prog:write_u8(TS_NMSG_A, n)
        print(string.format("staged: program %d B, font 2048 B, logic0 %d entries, %d messages",
                            #blob, nent, n))
        print(string.format("★ watch for: a white box with black lettering, %d messages, "
                            .. "%d frames each", n, HOLD))
        cpu.state["PC"].value = 0x2000
        prog:write_u8(TS_GO, 1)
        return
    end

    if prog:read_u8(TS_PAGE) == 0xFF then
        print(string.format("★ %d message boxes drawn -- the screen is Jay's evidence, not this "
                            .. "line", shown))
        return
    end

    -- ★★ Hold each box for HOLD frames, then release the guest to draw the next. The guest sets
    -- DONE and waits for GO to drop and rise again, so pacing lives here and the engine does not
    -- know it is being watched.
    if prog:read_u8(TS_DONE) == 1 then
        -- ★★★★★ THE HEADLESS SELF-CHECK, AND IT EXISTS SO NOBODY IS ASKED TO WATCH A BLANK SCREEN.
        -- §3 forbids reading PNG pixels; this reads the FRAMEBUFFER, which is structured text --
        -- a count of non-black bytes per character row. It cannot say whether a glyph looks like
        -- its letter (that is Jay's half) but it can say whether ink reached the plane at all,
        -- and where. ★★★ Without it, "the eye gate is ready" would be an assertion.
        -- ═══════════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ AC-7's COST, AND THE CLOCK IS MEASURED RATHER THAN LABELLED. p3b_run.lua printed
        -- "@ 1.789390 MHz" as a hardcoded string while the machine ran at 0.894 -- every stage
        -- wrong by exactly 2.003x with the label asserting otherwise. So the rate is read from the
        -- device and printed beside the figure, and the figure is in CYCLES, which is
        -- clock-independent [L-78: this project measures cycles].
        -- ★★★ m.time is EMULATED time, not host time, so -nothrottle cannot move it (§2U.1).
        if held == 0 and _G._ts_t0 then
            local dt = m.time:as_double() - _G._ts_t0
            -- ★★★★ THE RATE, FROM WHATEVER SOURCE ACTUALLY EXISTS, AND THE SOURCE IS PRINTED.
            -- `cpu.clock` is nil in this MAME build -- reading it and multiplying gave "0 cycles
            -- total, 0 cycles/glyph", which is a diagnostic that cannot be right rather than one
            -- that is wrong (§2W.3). ★★★ So each candidate is tried, the one that answers is
            -- named in the output, and a total absence prints as unknown rather than as zero.
            local hz, src = nil, "?"
            if type(cpu.clock) == "number" and cpu.clock > 0 then
                hz, src = cpu.clock, "device.clock"
            elseif type(cpu.clock) == "function" then
                local ok, v = pcall(function() return cpu:clock() end)
                if ok and type(v) == "number" and v > 0 then hz, src = v, "device:clock()" end
            end
            if not hz then
                -- ★★ The CoCo3's SAM speed pair: $FFD8 slow / $FFD9 fast, and the probe never
                -- writes either, so the machine is at MAME's power-on rate for coco3.
                hz, src = 894886, "coco3 power-on rate, probe sets no SAM speed"
            end
            local ng = 0
            if sym["txt_ng"] then
                ng = prog:read_u8(sym["txt_ng"]) * 256 + prog:read_u8(sym["txt_ng"] + 1)
            end
            local cyc = dt * hz
            print(string.format("  cost box %d: %d glyphs, %.1f ms, %.0f cycles, %.0f cyc/glyph"
                                .. "  [%.0f Hz via %s]",
                                shown + 1, ng, dt * 1000, cyc,
                                ng > 0 and cyc / ng or 0, hz, src))
        end
        if held == 0 and os.getenv("TS_VERIFY") == "1" then
            local rows, total = {}, 0
            for r = 0, 24 do
                local n = 0
                for line = 0, 7 do
                    local base = 0x8000 + (r * 8 + line) * 160
                    for b = 0, 159 do
                        if prog:read_u8(base + b) ~= 0 then n = n + 1 end
                    end
                end
                if n > 0 then rows[#rows + 1] = string.format("row %d: %d", r, n) end
                total = total + n
            end
            if total == 0 then
                print(string.format("★★★ box %d: THE PLANE IS ENTIRELY BLACK -- nothing drew",
                                    shown + 1))
            else
                print(string.format("  box %d: %d non-black bytes  [%s]",
                                    shown + 1, total, table.concat(rows, ", ")))
            end
        end
        held = held + 1
        if held >= HOLD then
            held = 0
            shown = shown + 1
            prog:write_u8(TS_GO, 0)
        end
    elseif prog:read_u8(TS_GO) == 0 then
        -- ★★ The clock starts when the guest is RELEASED and stops when it reports DONE, so the
        -- interval brackets exactly one clear-plus-msgbox-plus-close and nothing else.
        _G._ts_t0 = m.time:as_double()
        prog:write_u8(TS_GO, 1)
    end
end)
