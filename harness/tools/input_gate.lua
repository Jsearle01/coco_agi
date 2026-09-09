-- harness/tools/input_gate.lua -- type a command; check it reaches the parser. [P6.23 AC-4/AC-1]
--
-- ★★★★★ THE KEYS ARE REAL. natkeyboard:post drives MAME's own keyboard, which drives the CoCo3
-- PIA matrix, which is what HAL_key_scan reads -- so this exercises the decoder against the
-- emulated hardware rather than against a table of what the hardware ought to do.
--
-- ★★★★ TWO RECORDED GOTCHAS, both obeyed rather than rediscovered [mame-idioms §14b, §20d]:
--   14b  natkeyboard.in_use defaults to FALSE and arming it in the same frame as the first post
--        loses the post. It is armed AT SCRIPT LOAD, frames before anything is typed.
--   20d  MAME mis-delivers the SHIFTED DOUBLE QUOTE intermittently. No test string here uses one.
--
-- ★★★ IT RUNS THROTTLED WHEN TS_WATCH=1 (AC-1, a human is looking) and unthrottled otherwise
-- (AC-4, a byte check) -- §2U.2.
--
-- ★★ Environment: IP_PROG, IP_FONT, IP_VOCAB, IP_TEXT, IP_MAP, IP_WATCH.
-- ★ §2P: types a command and puts it on screen. Prints word NUMBERS and counts, never characters.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- ★★★★★ ARMED AT SCRIPT LOAD. Idiom 14b: doing this inside the notifier, in the same frame as the
-- first post, silently drops the keys and the probe reports zero -- which reads as a dead decoder.
m.natkeyboard.in_use = true

local PROG  = os.getenv("IP_PROG")  or "build/input_probe.bin"
local FONT  = os.getenv("IP_FONT")  or "build/text_font.bin"
local VOCAB = os.getenv("IP_VOCAB") or ""
local TEXT  = os.getenv("IP_TEXT")  or "look at the rock"
local MAP   = os.getenv("IP_MAP")   or "build/input_probe.map"
local WATCH = os.getenv("IP_WATCH") == "1"

local IP_GO, IP_DONE, IP_NKEY = 0x0020, 0x0021, 0x0022
local IP_EGON, IP_LASTK, IP_NRAW = 0x0023, 0x0024, 0x0025
local IP_FONT_A, IP_VOCAB_A, IP_EGOLOG = 0x3400, 0x6000, 0x4600

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

-- mode 2 + a black palette + the flat plane across slots 4-7, as text_show.lua does
prog:write_u8(0xFF98, 0x80)
prog:write_u8(0xFF99, 0x3E)
for i = 0, 15 do prog:write_u8(0xFFB0 + i, 0x00) end
local BLK = 32
for s = 0, 3 do prog:write_u8(0xFFA4 + s, BLK + s) end
prog:write_u8(0xFF9D, ((BLK * 1024) >> 8) & 0xFF)
prog:write_u8(0xFF9E, (BLK * 1024) & 0xFF)

local booted, posted, waited = false, false, 0

_G._ip = emu.add_machine_frame_notifier(function()
    if not booted then
        if m.time:as_double() < 0.4 then return end
        booted = true
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        poke(0x2000, blob)
        local font = slurp(FONT)
        if font and #font == 2048 then poke(IP_FONT_A, font) end
        if VOCAB ~= "" then
            local v = slurp(VOCAB)
            if v and #v <= 8192 then poke(IP_VOCAB_A, v) end
        end
        cpu.state["PC"].value = 0x2000
        prog:write_u8(IP_GO, 1)
        print(string.format("staged: program %d B; typing %d characters", #blob, #TEXT))
        return
    end

    if not posted then
        -- ★★ A few frames after GO, so the guest is in its poll loop before the first key lands.
        waited = waited + 1
        if waited < 12 then return end
        posted = true
        -- ★★★★ REPORT WHETHER THE POST WAS ACCEPTED. `empty` false immediately after a post means
        -- natkeyboard took the characters and is feeding them; still true means it took nothing,
        -- and that distinguishes "the keyboard is not delivering" from "the decoder is not
        -- decoding" without touching the guest.
        local before = m.natkeyboard.empty
        m.natkeyboard:post(TEXT .. "\r")
        print(string.format("natkeyboard: in_use=%s empty before=%s after=%s",
                            tostring(m.natkeyboard.in_use), tostring(before),
                            tostring(m.natkeyboard.empty)))
        return
    end

    -- ★★ Once a frame while keys are in flight, sample the COLUMN STROBE the guest is writing.
    -- $FF02 is an output register, so reading it from the host does not race the guest's own
    -- reads of $FF00 and shows whether the scan loop is running at all.
    if not m.natkeyboard.empty and (_G._ip_seen or 0) < 3 then
        _G._ip_seen = (_G._ip_seen or 0) + 1
        print(string.format("  scan check: $FF02=$%02X  NRAW=%d  keys pending",
                            prog:read_u8(0xFF02), prog:read_u8(IP_NRAW)))
    end

    if prog:read_u8(IP_DONE) == 1 then
        local n = prog:read_u8(IP_EGON)
        local ids = {}
        for i = 0, n - 1 do
            ids[#ids + 1] = prog:read_u8(IP_EGOLOG + i * 2) * 256
                            + prog:read_u8(IP_EGOLOG + i * 2 + 1)
        end
        print(string.format("★ line entered: %d key events, %d raw scans, last key $%02X",
                            prog:read_u8(IP_NKEY), prog:read_u8(IP_NRAW),
                            prog:read_u8(IP_LASTK)))
        print(string.format("★ parser: egon=%d  word numbers = %s",
                            n, table.concat(ids, ",")))
        if not WATCH then m:exit() end
        return
    end

    -- ★★★ A budget against PROGRESS, not against the run: a probe that is still decoding keys is
    -- not stalled [parser_gate.lua's own lesson]. NKEY advancing resets the clock.
    local nk = prog:read_u8(IP_NKEY)
    if _G._ip_nk ~= nk then _G._ip_nk, _G._ip_t = nk, m.time:as_double() end
    if not _G._ip_t then _G._ip_t = m.time:as_double() end
    if m.time:as_double() - _G._ip_t > 8 then
        print(string.format("★★★ no progress: DONE=%d NKEY=%d NRAW=%d LASTK=$%02X PC=$%04X",
                            prog:read_u8(IP_DONE), nk, prog:read_u8(IP_NRAW),
                            prog:read_u8(IP_LASTK), cpu.state["PC"].value))
        if sym["gs_curpos"] then
            print(string.format("     curpos=%d done=%d",
                                prog:read_u8(sym["gs_curpos"]), prog:read_u8(sym["gs_done"])))
        end
        -- ★★★★ NRAW is the discriminator: zero means the MATRIX never saw a key (a natkeyboard
        -- problem), non-zero with NKEY zero means the DECODER saw pressure and resolved nothing
        -- (a table problem). **Without it the two look identical from here.**
        m:exit()
    end
end)
