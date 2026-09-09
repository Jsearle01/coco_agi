-- harness/tools/input_display_check.lua -- why is the screen pink? [P6.25 AC-1 follow-up]
--
-- ★★★★★ JAY'S EYE GATE FAILED AND NO BYTE GATE SAW IT: "i saw basic, the program took over, i got
-- a pink screen and it hung." The probe's own log shows it COMPLETED -- line entered, parsed,
-- egon=2 -- and then halts at ip_end by design, so "hung" is the probe having nothing left to do.
-- **The pink screen is the finding**, and it is §4A's whole argument: the readback path and the
-- display path are different paths [idiom 19j], and every gate in P6 has been readback.
--
-- ★★★★ THIS READS THE DISPLAY CHAIN, not the drawing. Four things have to agree for a glyph the
-- guest drew to be a glyph the operator sees:
--   1. the guest wrote ink into ITS address space              ($8000..$FCFF)
--   2. those addresses map to the blocks the GIME scans        (MMU slots 4-7 vs VOFFSET)
--   3. the palette says what those pixel values look like      ($FFB0-$FFBF)
--   4. the mode is what the geometry assumes                   ($FF98/$FF99)
-- ★★★ A uniform WRONG COLOUR is most consistent with 3 or 2; a NOISY screen with 2; a BLACK screen
-- with 1. Reporting all four separates them instead of guessing from the colour.
--
-- ★★ §3: this reads the framebuffer as STRUCTURED TEXT -- counts and register values -- never a
-- PNG, and it prints no game text.
--
-- usage:  mame coco3 -autoboot_script harness/tools/input_display_check.lua -seconds_to_run 25

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
m.natkeyboard.in_use = true

local PROG = os.getenv("IP_PROG") or "build/input_probe.bin"
local FONT = os.getenv("IP_FONT") or "build/text_font.bin"
local TEXT = os.getenv("IP_TEXT") or "look at rock"

local IP_GO, IP_DONE, IP_NKEY = 0x0020, 0x0021, 0x0022
local IP_FONT_A = 0x3400

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

-- ★★★ AT TAKEOVER, not at script load -- the defect this tool was written to find. See
-- input_gate.lua's assert_display note.
local function assert_display()
    prog:write_u8(0xFF98, 0x80)
    prog:write_u8(0xFF99, 0x3E)
    for i = 0, 15 do prog:write_u8(0xFFB0 + i, 0x00) end
    local BLK = 32
    for s = 0, 3 do prog:write_u8(0xFFA4 + s, BLK + s) end
    prog:write_u8(0xFF9D, ((BLK * 1024) >> 8) & 0xFF)
    prog:write_u8(0xFF9E, (BLK * 1024) & 0xFF)
end

local booted, posted, waited, done = false, false, 0, false

-- ★★★★★ READINESS COMES FROM harness/tools/decb_ready.lua, NOT FROM A FIXED DELAY. This file
-- used `if m.time:as_double() < 0.4 then return end` -- a guess at when the machine became ready
-- rather than a reading of whether it had -- and took DECB over mid-boot. Jay's standing rule,
-- broken here and in six sibling files at once [T-P0-060, T-P0-081].
local decb_ready = dofile("harness/tools/decb_ready.lua").new{ hold = 0 }

_G._idc = emu.add_machine_frame_notifier(function()
    if not booted then
        do
            local st = decb_ready(m, cpu, prog)
            if st == "timeout" then m:exit(); return end
            if st ~= "go" then return end
        end
        booted = true
        poke(0x2000, slurp(PROG))
        local f = slurp(FONT)
        if f and #f == 2048 then poke(IP_FONT_A, f) end
        prog:write_u8(0x0027, 0)                -- IP_ITER
        assert_display()
        cpu.state["PC"].value = 0x2000
        prog:write_u8(IP_GO, 1)
        return
    end
    if prog:read_u8(IP_GO) == 0 and prog:read_u8(IP_DONE) == 0 then
        prog:write_u8(IP_GO, 1)
    end
    if not posted then
        waited = waited + 1
        if waited < 14 then return end
        posted = true
        m.natkeyboard:post(TEXT .. "\r")
        return
    end
    if done or prog:read_u8(IP_DONE) ~= 1 then return end
    done = true

    -- ★★★★★ $FF98/$FF99/$FF9D/$FF9E ARE WRITE-ONLY ON THE GIME. The first version of this tool
    -- printed them as "want $80 / want $3E" and they read $1B, $1B, $1B1B -- **three different
    -- registers returning the same byte is the floating bus, not their contents**, and reading
    -- them proves nothing in either direction. §2W.3: a diagnostic that cannot be right does not
    -- measure. The MMU at $FFA0-$FFA7 and the palette at $FFB0-$FFBF ARE readable and are below.
    print("=== 4. mode/VOFFSET: NOT CHECKABLE (write-only registers) ===")

    print("=== 3. palette, as the GUEST left it ===")
    local pal = {}
    for i = 0, 15 do pal[#pal + 1] = string.format("%02X", prog:read_u8(0xFFB0 + i)) end
    print("  " .. table.concat(pal, " "))
    print(string.format("  index 0 = $%02X   ★ a non-zero index 0 paints the CLEARED plane",
                        prog:read_u8(0xFFB0)))

    print("=== 2. mapping ===")
    local mmu = {}
    for s = 0, 7 do mmu[#mmu + 1] = string.format("%d", prog:read_u8(0xFFA0 + s)) end
    print("  MMU slots 0-7: " .. table.concat(mmu, " "))
    local voff = prog:read_u8(0xFF9D) * 256 + prog:read_u8(0xFF9E)
    print(string.format("  VOFFSET=$%04X -> physical $%06X -> block %d",
                        voff, voff * 8, (voff * 8) // 8192))
    print(string.format("  slots 4-7 hold blocks %s -- the guest writes $8000-$FCFF through these",
                        table.concat({mmu[5], mmu[6], mmu[7], mmu[8]}, " ")))

    print("=== 1. did the guest actually write ink? ===")
    local rows, total = {}, 0
    for r = 0, 24 do
        local n = 0
        for line = 0, 7 do
            local base = 0x8000 + (r * 8 + line) * 160
            for b = 0, 159 do
                if prog:read_u8(base + b) ~= 0 then n = n + 1 end
            end
        end
        if n > 0 then rows[#rows + 1] = string.format("row%d:%d", r, n) end
        total = total + n
    end
    print(string.format("  %d non-zero bytes in the plane  [%s]", total,
                        #rows > 0 and table.concat(rows, " ") or "NONE"))
    print(string.format("  key events=%d", prog:read_u8(IP_NKEY)))

    -- ★★★★★ AND THE GUEST'S OWN TEXT STATE. "No ink" has three candidate causes and the plane
    -- cannot distinguish them: the blitter was switched off (txt_noblit), it had no window
    -- (txt_fbwin), or it refused the row (txt_fbrows / txt_fbrow0 vs txt_crow). **Reading them is
    -- the discriminator; reading the plane again is not** [L-103].
    local sym = {}
    do
        local f = io.open(os.getenv("IP_MAP") or "build/input_probe.map", "r")
        if f then
            for line in f:lines() do
                local n, v = line:match("^Symbol:%s+(%S+)%s+%b()%s+=%s+(%x+)")
                if n then sym[n] = tonumber(v, 16) end
            end
            f:close()
        end
    end
    local function u8(n) return sym[n] and prog:read_u8(sym[n]) or -1 end
    local function u16(n)
        return sym[n] and (prog:read_u8(sym[n]) * 256 + prog:read_u8(sym[n] + 1)) or -1
    end
    print("=== 0. the guest's text state ===")
    print(string.format("  txt_fbwin=$%04X  txt_noblit=%d  txt_fbrow0=%d  txt_fbrows=%d",
                        u16("txt_fbwin"), u8("txt_noblit"), u8("txt_fbrow0"), u8("txt_fbrows")))
    print(string.format("  txt_crow=%d txt_ccol=%d  txt_font=$%04X  txt_ng=%d",
                        u8("txt_crow"), u8("txt_ccol"), u16("txt_font"), u16("txt_ng")))
    print(string.format("  gs_curpos=%d gs_entered=%d", u8("gs_curpos"), u8("gs_entered")))
    m:exit()
end)
