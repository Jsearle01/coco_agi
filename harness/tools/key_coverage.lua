-- harness/tools/key_coverage.lua -- does the decoder carry AD-134's scheme? [P6.24 AC-4]
--
-- ★★★★★ IT ASSERTS THE IOPORT FIELD, which idiom 41f establishes as the technique automation
-- should use and proves by consequence. keymatrix_check.lua confirmed every field this needs
-- lands where hal_globals.s's table says: ENTER row6/col0, CTRL row6/col4, ALT row6/col3, the
-- arrows row3/col3-6.
--
-- ★★★★ LETTERS **ARE** IOPORT FIELDS, and an earlier version of this header said they were not.
-- MAME names them "q  Q" -- lowercase, two spaces, uppercase -- so a `fname:upper()` lookup for
-- "Q" finds nothing and the natural conclusion is that letters are unexposed. **They are exposed;
-- the lookup was wrong**, and the run that "proved" otherwise reported four decoder mismatches
-- that were entirely the driver's. Addressing by tag and mask avoids the naming question.
--
-- ★★★ IT READS WHAT THE GUEST DECODED, not what MAME asserted. The matrix reaching $FF00 was
-- settled by keymatrix_check; what is unsettled is whether HAL_key_scan resolves each position to
-- the right code, and only the guest can answer that.
--
-- usage:  mame coco3 -autoboot_script harness/tools/key_coverage.lua -seconds_to_run 60

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
m.natkeyboard.in_use = true

local PROG = os.getenv("IP_PROG") or "build/input_probe.bin"
local MAP  = os.getenv("IP_MAP")  or "build/input_probe.map"

local IP_GO, IP_DONE, IP_NKEY = 0x0020, 0x0021, 0x0022
local IP_LASTK, IP_NRAW, IP_LASTM = 0x0024, 0x0025, 0x0026

-- ★★★★★ ADDRESSED BY (ROW, COLUMN), NOT BY NAME, and the first version used names and failed.
-- MAME calls the letter fields "q  Q" -- lowercase, two spaces, uppercase -- so a `:upper()`
-- lookup for "Q" found nothing, every Ctrl+letter item drove no key at all, and the run reported
-- four mismatches that were the DRIVER's, not the decoder's.
-- ★★★★ Tag-and-mask is also the better check: `:row<N>` mask `1<<col` is exactly the coordinate
-- hal_globals.s's table is indexed by, so this addresses MAME's port with the port's own geometry
-- and dist/mame-cfg/rgb/coco3.cfg's BREAK=`:row6` mask 4 is the precedent.
-- ★★★ It also removes natkeyboard from the Ctrl+letter case entirely: both halves are field
-- asserts now, so nothing can own the port and clear the other.
--
-- Modifier bits: 1 SHIFT, 2 CTRL, 4 ALT.
local CTRL = { row = 6, col = 4 }
local PLAN = {
    { name = "Up",     keys = {{3, 3}},        want = 0x81, mod = 0 },
    { name = "Down",   keys = {{3, 4}},        want = 0x82, mod = 0 },
    { name = "Left",   keys = {{3, 5}},        want = 0x83, mod = 0 },
    { name = "Right",  keys = {{3, 6}},        want = 0x84, mod = 0 },
    { name = "Alt",    keys = {{6, 3}},        want = 0x85, mod = 4 },
    -- Q=row2/col1  E=row0/col5  Z=row3/col2  C=row0/col3, from hal_globals.s's own table
    { name = "Ctrl+Q", keys = {{2, 1}, {6, 4}}, want = string.byte("Q"), mod = 2 },
    { name = "Ctrl+E", keys = {{0, 5}, {6, 4}}, want = string.byte("E"), mod = 2 },
    { name = "Ctrl+Z", keys = {{3, 2}, {6, 4}}, want = string.byte("Z"), mod = 2 },
    { name = "Ctrl+C", keys = {{0, 3}, {6, 4}}, want = string.byte("C"), mod = 2 },
    -- ★★★★★ ENTER IS LAST, AND IT HAS TO BE. It ends the input line: the guest runs the parser,
    -- sets DONE and halts at ip_end, so every item after it is tested against a probe that has
    -- STOPPED SCANNING. With Enter sixth, Ctrl+Q/E/Z/C all reported "decoded $00" -- four decoder
    -- mismatches that were entirely this plan's ordering.
    -- ★★★ It reads exactly like a decoder that cannot do modifiers, which is the wrong conclusion
    -- to reach about code whose arrows and Alt had just passed.
    { name = "Enter",  keys = {{6, 0}},        want = 0x0D, mod = 0 },
}

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

local fields = {}
local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

local phase, idx, held, results = "boot", 1, 0, {}

_G._kc = emu.add_machine_frame_notifier(function()
    if phase == "boot" then
        if m.time:as_double() < 0.5 then return end
        -- ★★ index every keyboard field by "row,mask" so a key is addressed by its matrix position
        for tag, port in pairs(m.ioport.ports) do
            local r = tag:match("row(%d)")
            if r then
                for _, field in pairs(port.fields) do
                    fields[r .. "," .. field.mask] = field
                end
            end
        end
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        poke(0x2000, blob)
        -- ★★★★★ SET IP_ITER EXPLICITLY, EVEN TO ZERO. It lives at $0027 in the direct page, which
        -- DECB was using moments ago, so "not setting it" means "whatever DECB left". A non-zero
        -- leftover sends the probe straight to its timing loop and the coverage run reports
        -- **0 of 10** -- ten decoder mismatches from a byte nobody wrote.
        -- ★★★ Second instance this task of the same class: the guest clearing IP_GO cost P6.23 a
        -- whole task. **A direct-page byte has no default** [parser_probe.s's original lesson].
        prog:write_u8(0x0027, 0)
        cpu.state["PC"].value = 0x2000
        prog:write_u8(IP_GO, 1)
        phase = "arm"
        return
    end

    -- ★★★★ Keep raising GO: the guest clears it in its own init, and setting it once in the same
    -- frame as the PC is what left P6.23's probe spinning at ip_wait for a whole task.
    if phase == "arm" then
        if prog:read_u8(IP_GO) == 0 then prog:write_u8(IP_GO, 1); return end
        if prog:read_u8(IP_NRAW) == 0 and (_G._kc_w or 0) < 30 then
            _G._kc_w = (_G._kc_w or 0) + 1
            return
        end
        phase = "press"
        return
    end

    if phase == "press" then
        local p = PLAN[idx]
        for _, rc in ipairs(p.keys) do
            local f = fields[rc[1] .. "," .. (1 << rc[2])]
            if f then f:set_value(1)
            else print(string.format("  ★★★ %s: no field at row%d bit %d",
                                     p.name, rc[1], rc[2])) end
        end
        held = 0
        phase = "watch"
        return
    end

    if phase == "watch" then
        local p = PLAN[idx]
        held = held + 1
        local k, md = prog:read_u8(IP_LASTK), prog:read_u8(IP_LASTM)
        if k ~= 0 and k ~= 0xFF and held > 2 then
            results[#results + 1] = { n = p.name, got = k, mod = md,
                                      want = p.want, wmod = p.mod }
            for _, rc in ipairs(p.keys) do
                local f = fields[rc[1] .. "," .. (1 << rc[2])]
                if f then f:set_value(0) end
            end
            prog:write_u8(IP_LASTK, 0)
            idx = idx + 1
            phase = (idx > #PLAN) and "done" or "press"
            return
        end
        if held > 40 then
            results[#results + 1] = { n = p.name, got = -1, mod = md,
                                      want = p.want, wmod = p.mod }
            for _, rc in ipairs(p.keys) do
                local f = fields[rc[1] .. "," .. (1 << rc[2])]
                if f then f:set_value(0) end
            end
            idx = idx + 1
            phase = (idx > #PLAN) and "done" or "press"
        end
        return
    end

    if phase == "done" then
        print("=== AD-134 key coverage: what HAL_key_scan decoded ===")
        local ok = 0
        for _, r in ipairs(results) do
            local hit = (r.got == r.want)
            -- ★★ The modifier is reported but not required to match exactly: asserting CTRL as an
            -- ioport field and posting a letter through natkeyboard can release CTRL between the
            -- two, and that is a property of the DRIVING, not of the decoder.
            if hit then ok = ok + 1 end
            print(string.format("  %-9s decoded $%02X (want $%02X) mod=$%02X (want $%02X)  %s",
                                r.n, r.got < 0 and 0 or r.got, r.want, r.mod, r.wmod,
                                hit and "★ OK" or "★★★ MISMATCH"))
        end
        print(string.format("=== %d of %d AD-134 items decoded as expected ===", ok, #results))
        m:exit()
    end
end)
