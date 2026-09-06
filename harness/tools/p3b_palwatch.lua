-- harness/tools/p3b_palwatch.lua -- does p3b WRITE the palette registers, or inherit them?
--
-- ★★★★★ THE QUESTION [T-P0-057]. AC-1 passed on three rooms that looked right, and p3b_show.lua
-- asserts $FFB0-$FFBF from the host on every frame. So the colours Jay approved were host-asserted
-- and the pass says nothing about whether the GUEST establishes them. Jay: "p3b still doesn't have
-- the palette incorporated properly."
--
-- ★★★★ A WRITE TAP ANSWERS IT WITHOUT A READBACK, and that matters: a host-side READ of
-- $FFB0-$FFBF tests MAME's palette model rather than the guest's writes [pic_probe.s pal_readback
-- says so, which is why AC-11 read them from inside the guest]. A tap on the register range asks
-- the one question that has no such ambiguity -- **did any instruction store here** -- and this
-- script deliberately writes NOTHING to the palette itself, so every hit is the guest's.
--
-- ★★★ It also blacks the screen the way p3b_show.lua does, because otherwise the run is judged
-- against DECB's text screen; the mode registers are $FF98/$FF99 and are NOT in the tapped range.
--
-- ★ §2P: reads guest state, writes nothing but mode registers. No game data.
--
-- usage: P3B_PROG=... P3B_SYMBOLS=... mame coco3 ... -autoboot_script this

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local hits, first_cycle, seen = 0, nil, {}
local CYCLE = 0x0024

-- ★★★ THE TAP MUST LIVE IN _G OR IT IS GARBAGE-COLLECTED AND SILENTLY STOPS FIRING, which would
-- report "the guest never writes the palette" for the wrong reason entirely [idioms; p3b_run.lua
-- carries the same warning on its phase tap].
-- ★★★★★ THE PC IS WHAT DISTINGUISHES THE GUEST FROM THE ROM, and the cycle counter cannot.
-- The first version reported "16 guest writes" at cycle 65535 -- but 65535 is the UNINITIALISED
-- counter, which reads the same whether a write came from DECB's boot before staging or from
-- p3b's own init before it zeroes the counter. **A tap that cannot say WHO wrote is not evidence
-- about the guest.** p3b is poked to $2000; Disk BASIC lives in ROM above $8000.
local by_pc = {}
_G._palwatch = prog:install_write_tap(0xFFB0, 0xFFBF, "palwatch", function(offset, data, mask)
    hits = hits + 1
    seen[offset] = data % 256
    local pc = cpu.state["PC"].value
    by_pc[pc] = (by_pc[pc] or 0) + 1
    if not first_cycle then
        first_cycle = prog:read_u8(CYCLE) * 256 + prog:read_u8(CYCLE + 1)
    end
end)

-- mode only; the palette registers are left strictly alone so the tap measures the guest.
prog:write_u8(0xFF98, 0x80)
prog:write_u8(0xFF99, 0x3E)

_G._palreport = emu.add_machine_frame_notifier(function()
    local n = prog:read_u8(CYCLE) * 256 + prog:read_u8(CYCLE + 1)
    if n < 3 or n > 4096 then return end
    if _G._palreported then return end
    _G._palreported = true
    print("")
    print("★ PALETTE WRITE TAP on $FFB0-$FFBF, host wrote none of them")
    print(string.format("   guest writes observed: %d", hits))
    if hits == 0 then
        print("   ★★★ THE GUEST NEVER WRITES THE PALETTE -- whatever is in those registers was")
        print("       left there by something else. Any correct colour is INHERITED.")
    else
        local t = {}
        for i = 0, 15 do
            local v = seen[0xFFB0 + i]
            t[#t + 1] = v and string.format("$%02X", v & 0x3F) or "--"
        end
        print(string.format("   first write at cycle %s", tostring(first_cycle)))
        print("   values (bits 7-6 masked): " .. table.concat(t, " "))
        -- ★★★★★ THE GUEST RANGE IS MAP_CODE..MAP_CODE_END = $2000-$5300 [memmap.inc], NOT
        -- $2000-$3FFF. The first version of this classifier used $4000 as the top and therefore
        -- reported p3b's OWN palette load -- from PC $5005 -- as "rom/other", i.e. it would have
        -- called a working fix a failure. **A tap that answers "who wrote this" is only as good
        -- as its idea of where the guest is**, and 13 KB of guest code does not fit in 8 KB.
        local CODE_LO, CODE_HI = 0x2000, 0x5300
        print(string.format("   writes by PC -- $%04X-$%04X is p3b [MAP_CODE..MAP_CODE_END],"
                            .. " above $8000 is DECB's ROM:", CODE_LO, CODE_HI))
        local guest, rom = 0, 0
        for pc, c in pairs(by_pc) do
            local is_guest = (pc >= CODE_LO and pc < CODE_HI)
            print(string.format("      PC $%04X  %d write(s)  %s",
                                pc, c, is_guest and "★ GUEST" or "rom/other"))
            if is_guest then guest = guest + c else rom = rom + c end
        end
        print(string.format("   ★★★ guest writes %d, non-guest writes %d", guest, rom))
        if guest == 0 then
            print("   ★★★★★ p3b WRITES NO PALETTE. Any correct colour on screen is INHERITED --")
            print("         from DECB's boot, from the host script, or from an earlier run.")
        else
            -- ★★★ COMPARE AGAINST THE ONE HOME, not against a copy in this script.
            local want, fh = {}, io.open("content/agi_palette.s", "r")
            if fh then
                local inside = false
                for line in fh:lines() do
                    if line:find("^agi_pal16:") then inside = true
                    elseif inside then
                        local hex = line:match("^%s*fcb%s+%$(%x%x)")
                        if hex then
                            want[#want + 1] = tonumber(hex, 16)
                            if #want == 16 then break end
                        elseif line:match("^%a") then break end
                    end
                end
                fh:close()
            end
            local bad = 0
            for i = 1, 16 do
                local got = seen[0xFFAF + i]
                if not got or (got & 0x3F) ~= (want[i] or -1) then bad = bad + 1 end
            end
            if #want == 16 and bad == 0 then
                print("   ★★★★★ p3b WRITES ITS OWN PALETTE, and all 16 match content/agi_palette.s")
            else
                print(string.format("   ★★★ %d of 16 do NOT match content/agi_palette.s", bad))
            end
        end
    end
    print("")
end)

dofile("harness/tools/p3b_room.lua")
