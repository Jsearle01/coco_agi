-- harness/tools/p3b_show.lua -- POINT THE DISPLAY AT WHAT THE GUEST ALREADY COMPOSITED.
--
-- â˜…â˜…â˜…â˜…â˜… WHAT THIS IS AND, MORE IMPORTANTLY, WHAT IT IS NOT.
-- It does NOT give the port a present path. The port still cannot display anything on its own, and
-- AD-110 Â§3.F's finding stands unchanged. This is the HARNESS pointing the GIME at the planes the
-- guest wrote, so a human can watch the compositing that the byte gates already proved correct.
-- â˜…â˜…â˜…â˜… The distinction matters and must survive into the report: **the pixels are the guest's, the
-- decision to display them is ours.** A real CoCo3 running this port standalone would still show
-- nothing.
--
-- â˜…â˜…â˜…â˜…â˜… WHY THE HARNESS AND NOT THE PROBE. T-P0-050's AC-2 asks for HAL_gfx_swap, and measurement
-- says it cannot serve here:
--   * p3b allocates ph_blk_pri=0 (blocks 0-1) and ph_blk_fb=2 (blocks 2-5) [p3b_probe.s:179-181].
--   * HAL_gfx_swap writes VOFFSET GFX_DB_A_VOFF/$4000 or B/$5000 -> physical $20000/$28000, i.e.
--     blocks $10/$14 [gfx.s:431-434,563-570]. **Those are not blocks 2-5.**
--   * It then remaps slot 6 to a GFX_DB block, which would tear p3b's framebuffer slice out from
--     under the phase discipline [gfx.s:576-582 vs mmu_phase.s:49-56].
--   * And the mode/palette half lives in HAL_gfx_set_mode, which maps buffer A to $8000 --
--     MAP_ARENA_WIN, where p3b keeps the LOGIC it is interpreting [memmap.inc, gfx.s:469-478].
-- â˜…â˜…â˜… Each of those is a change to shared HAL or to the phase map, which is T-P0-050 trigger 1 and
-- trigger 3 and belongs to a dispatch that gates it. **This file changes neither.**
--
-- â˜…â˜… WHAT IT WRITES, and every value is read from the project rather than chosen here:
--   $FF98=$80 VMODE, $FF99=$3E VRES   mode 2, from gfx_mode_table [hal_globals.s:124-129]
--   $FFB0-$FFBF                        the guest's OWN gfx_pal16, read out of its memory
--   $FF9D/$FF9E VOFFSET                ph_blk_fb * 1024, read out of the guest's own allocator byte
-- â˜…â˜…â˜… Mode BEFORE palette is a documented constraint, not a preference: palette writes do not latch
-- until the video mode is final [gfx.s:145-148, Constraint B].
-- â˜… Re-asserted every frame rather than once, so a guest write cannot silently undo the display.
--
-- usage:  P3B_ROOM=1 SHOW_SNAP=1 mame ... -autoboot_script harness/tools/p3b_show.lua

local SNAP_EVERY = tonumber(os.getenv("SHOW_SNAP_EVERY") or "0")   -- frames between snapshots
local SYMS       = os.getenv("SHOW_SYMS") or "build/p3b_probe_pk.map"

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- â˜… Monitor type -> RGB. Same idiom as pic_sweep.lua:67-76; the AGI palette is undefined on
-- composite (Â§11l, design Â§2.2), so a capture taken there would be a picture of the wrong machine.
pcall(function()
    local port = m.ioport.ports[":screen_config"]
    if port then
        for name, field in pairs(port.fields) do
            if name == "Monitor Type" then field.user_value = 1
                print("MONITOR TYPE -> RGB"); return end
        end
    end
end)

-- â˜…â˜… Symbols from the build's own map, never hardcoded: ph_blk_fb is an ALLOCATED block and
-- gfx_pal16's address moves with the binary [mmu_phase.s:29-31 -- a hard-coded block is the P3.10
-- defect].
local function sym(name)
    local fh = io.open(SYMS, "r")
    if not fh then return nil end
    local want = "^Symbol: " .. name .. " "
    for line in fh:lines() do
        if line:find(want) then
            local hex = line:match("=%s*([0-9A-Fa-f]+)%s*$")
            fh:close()
            if hex then return tonumber(hex, 16) end
        end
    end
    fh:close(); return nil
end

-- ★★★★★ THE PALETTE COMES FROM ITS SOURCE, NOT FROM THE LOADED BINARY, AND THIS IS §2F.
-- The first version read gfx_pal16 out of guest memory at a map-supplied address. That couples
-- the capture to WHICH BUILD is loaded, and this session found build/p3b_probe_pk.map to be five
-- days older than build/p3b_probe_pk.bin -- so the address was wrong and the palette would have
-- been read from whatever happened to sit there. **A wrong palette does not fail; it renders.**
-- ★★★ gfx.s is the palette's one home [§2F; palette_check.py already reads gfx_pal4 out of this
-- file by path, so the precedent for parsing it here is the project's own].
local function read_pal16()
    local fh = io.open("src/hal/coco3-dsk/gfx.s", "r")
    if not fh then return nil end
    local pal, inside = {}, false
    for line in fh:lines() do
        if line:find("^gfx_pal16:") then inside = true
        elseif inside then
            local hex = line:match("^%s*fcb%s+%$(%x%x)")
            if hex then
                pal[#pal + 1] = tonumber(hex, 16)
                if #pal == 16 then break end
            elseif line:match("^%a") then break end   -- next label: the table ended
        end
    end
    fh:close()
    return (#pal == 16) and pal or nil
end

local PAL16 = read_pal16()
-- ★★★★★ FOLLOW p3_blk_vis, NOT ph_blk_fb. Since T-P0-051 the picture renders into a SHADOW plane
-- and ph_blk_fb points AT THAT SHADOW for the duration of the render -- so a display that tracked
-- ph_blk_fb would show the draw happening, which is the exact thing the shadow buffer exists to
-- stop. p3_blk_vis names the visible plane and never moves.
-- ★ Falls back to ph_blk_fb so this file still works against a pre-shadow build.
local A_FB  = sym("p3_blk_vis") or sym("ph_blk_fb")
print(string.format("palette: %s from gfx.s   visible-plane byte=$%04X (%s)",
                    PAL16 and "16 entries" or "★★★ NOT FOUND", A_FB or 0,
                    sym("p3_blk_vis") and "p3_blk_vis" or "ph_blk_fb -- pre-shadow build"))

local ST, CYCLE = 0x0020, 0x0024
local shots, armed, last_snap_cycle = 0, -1, -1

_G._show = emu.add_machine_frame_notifier(function()
    local n = prog:read_u8(CYCLE) * 256 + prog:read_u8(CYCLE + 1)
    -- â˜… Same guard as p3b_room.lua: RAM before the probe zeroes it reads as 65535, and acting on
    -- that once cost a run that reported a successful room jump and never changed room.
    if n < 2 or n > 4096 then return end

    -- 1. mode, BEFORE palette (gfx.s Constraint B)
    prog:write_u8(0xFF98, 0x80)
    prog:write_u8(0xFF99, 0x3E)

    -- 2. the project's own 16-entry palette, from gfx.s
    if PAL16 then
        for i = 1, 16 do
            prog:write_u8(0xFFB0 + i - 1, PAL16[i])
        end
    end

    -- 3. VOFFSET = physical / 8, and physical = block * 8192, so VOFFSET = block * 1024
    if A_FB then
        local blk  = prog:read_u8(A_FB)
        local voff = blk * 1024
        prog:write_u8(0xFF9D, (voff >> 8) & 0xFF)
        prog:write_u8(0xFF9E, voff & 0xFF)
        -- â˜…â˜…â˜… REPORT EVERY CHANGE, NOT JUST THE FIRST. The first version printed once and latched,
        -- and its one line said ph_blk_fb=0 -- read before the guest's allocator had run, which
        -- would have pointed the display at block 0, the PRIORITY plane, and been indistinguishable
        -- from a correct capture to anyone not reading the log [L-37].
        if blk ~= armed then
            print(string.format("DISPLAY -> ph_blk_fb=%d  physical=$%05X  VOFFSET=$%04X  (cycle %d)",
                                blk, blk * 8192, voff, n))
            armed = blk
        end
    end

    -- ★★★ ONCE PER CYCLE, NOT ONCE PER FRAME. A VM cycle spans many frames, so `n % N == 0`
    -- evaluated in a frame notifier fires on EVERY frame the guest spends on a matching cycle:
    -- the first run wrote 629 PNGs for 120 cycles and dragged the machine to 57% speed, which
    -- also starved the run before it reached its cycle count. The guard is the cycle number
    -- itself, remembered.
    if SNAP_EVERY > 0 and n ~= last_snap_cycle and (n % SNAP_EVERY == 0) then
        last_snap_cycle = n
        local ok = pcall(function() m.video:snapshot() end)
        if ok then shots = shots + 1 end
    end
end)

dofile("harness/tools/p3b_room.lua")


