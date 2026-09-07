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

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ THIS SCRIPT MUST RUN THROTTLED. DO NOT ADD -nothrottle TO ITS LAUNCHER.
-- ★★★★ T-P0-058 made -nothrottle the default for every BYTE gate -- pic, cel, comp, p3b's dump
-- runs, the ablations -- after verifying each produces identical results either way. **This one
-- is excluded by Jay's instruction and by what it is for.** It is the eye gate: a human watches
-- a room appear, judges whether the fills and the palette are right, and needs the machine to
-- run at the speed the machine would run at. At 2,800% a 7-second render is a flicker.
-- ★★★ P3B_HOLD exists for the same reason [T-P0-056]: the gate had been running four times with
-- the window closing on the frame the work finished, and nobody could see it.
-- ★★ The dump path (p3b_room.lua, no display) IS unthrottled -- it produces plane bytes for
-- plane_pair_diff.py and no human looks at it while it runs.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
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
-- The first version read the table out of guest memory at a map-supplied address. That couples
-- the capture to WHICH BUILD is loaded, and this session found build/p3b_probe_pk.map to be five
-- days older than build/p3b_probe_pk.bin -- so the address was wrong and the palette would have
-- been read from whatever happened to sit there. **A wrong palette does not fail; it renders.**
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ T-P0-056: THIS READ gfx_pal16 AND THAT IS THE WRONG TABLE [AD-125].
-- ★★★★ gfx_pal16 is the SHARED HAL's generic 16-colour ramp. It is not AGI's palette and was
-- never meant to be: hal_globals.s:133 points mode 2 at it with the words "AGI's own palette is
-- loaded by the engine at init (design §2.2), NOT FROM HERE". Reading it here made this script
-- assert the placeholder over the display, every frame.
--
-- ★★★★★ AGI'S PALETTE WAS DECIDED AND GATED EIGHT DAYS BEFORE THIS BUG WAS SEEN. T-P0-024 P4.4
-- closed it: AC-11 proved 16 of 16 values land in $FFB0-$FFBF (read back by the guest, bits 7-6
-- masked), and AC-12 is Jay's eye gate on the swatches beside a synthesised EGA reference --
-- "band 6 is brown in both". The table is agi_pal16 [pic_probe.s:498-514].
--
-- ★★★★ THE DIFFERENCE IS NOT SUBTLE, and index 2 is the one Jay saw:
--       idx 2  green   agi_pal16 $10 = R0 G2 B0     gfx_pal16 $38 = R2 G2 B2 (light grey)
-- Jay, live: "in the first room the trees look unfilled (white)". Green foliage through the
-- placeholder is pale grey. **The planes were byte-identical to the oracle throughout** -- the
-- fills were complete and only the value-to-colour map was wrong.
--
-- ★★★ WHY THIS SURVIVED: p3b_probe.s loads NO palette at all -- no pal_load, no agi_pal16, no
-- $FFB0 write, and it never calls HAL_gfx_set_mode. The palette work landed in the RENDERER
-- probe and was never carried into the INTEGRATION probe, and this script filled the gap with
-- the nearest table it could find. That is §4A's pattern exactly: a defect in the glue between
-- two independently-gated subsystems, invisible to both of their gates.
-- ★★ Reading it from pic_probe.s is a harness-side stopgap, not the fix. §2F wants one home for
-- agi_pal16 once p3b needs it too; that move is the Orchestrator's to place.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
local function read_pal16()
    -- ★★★ content/agi_palette.s is the palette's ONE HOME [CLAUDE.md §2F/§2B, T-P0-056b]. This
    -- read named gfx.s, then pic_probe.s, and both were places the table happened to be rather
    -- than where it belongs. It is now a file whose only purpose is to hold it.
    local fh = io.open("content/agi_palette.s", "r")
    if not fh then return nil end
    local pal, inside = {}, false
    for line in fh:lines() do
        if line:find("^agi_pal16:") then inside = true
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
-- ★★★ NAME THE TABLE IN THE LOG. The old line said "from gfx.s" and was accurate about a file
-- that held the wrong table -- a provenance string is only useful if a reader can tell from it
-- whether the RIGHT thing was loaded, so it now prints the entries as well as the source.
print(string.format("palette: %s EXPECTED from content/agi_palette.s [P4.4 AC-11/AC-12] -- INSTALLED BY THE GUEST%s   visible-plane byte=$%04X (%s)",
                    PAL16 and "16 entries" or "★★★ NOT FOUND",
                    PAL16 and string.format("  idx2=$%02X idx6=$%02X idx15=$%02X",
                                            PAL16[3], PAL16[7], PAL16[16]) or "", A_FB or 0,
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

    -- ═══════════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ 2. THE PALETTE IS THE GUEST'S NOW, AND THIS NO LONGER WRITES IT [T-P0-057].
    -- ★★★★ This loop asserted the table from the host on EVERY FRAME, so the colours Jay
    -- approved at AC-1 were the host's and said nothing about p3b. A write tap proved it: 16
    -- writes to $FFB0-$FFBF across a whole run, all from PC $C00F -- Disk BASIC's ROM -- and
    -- none from the guest. **Leaving this in would keep the display correct and the program
    -- wrong, which is the exact condition that hid the defect for four tasks.**
    -- ★★★ p3b now calls agi_pal_load at init [p3b_probe.s], so the screen shows what the
    -- PROGRAM established. If that regresses, the colours go wrong and someone sees it.
    -- ★★ PAL16 is still parsed, and still printed at startup, purely so the log records what the
    -- guest is EXPECTED to install -- a reader can compare it against the tap's report.
    -- ═══════════════════════════════════════════════════════════════════════════════════════


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

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ BLACK THE SCREEN BEFORE THE LOAD, NOT AFTER IT [T-P0-056b].
-- ★★★★ The notifier above returns until the guest's cycle counter reaches 2, so for the WHOLE
-- of staging and the whole of cycle 1's ~7 s render the machine sat in DECB's text mode --
-- displaying VRAM that the stager was busy overwriting with the program image. Jay: "the program
-- sits in the text screen which is overwritten by the code on load and i'd rather it just be
-- black as soon as possible".
-- ★★★ This runs BEFORE the dofile below, which is what does the staging, so it is the earliest
-- point in the session at which anything can be asserted about the display.
-- ★★ A BLANKED PALETTE, NOT A CLEARED BUFFER, is what makes this safe here: the MMU is not up
-- yet and nothing has allocated the framebuffer blocks, so there is no buffer this script could
-- correctly clear. Sixteen black entries render whatever is in VRAM as black without needing to
-- know where VRAM is. The real values are written by the notifier from cycle 2, by which point
-- the guest has cleared the visible plane and presented its first room.
-- ★ The guest blacks its own visible plane at init as well [p3b_probe.s p3_black_visible], so
-- the port does not depend on this script for the same effect -- this covers only the window
-- before the guest is running at all.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ IT IS A FUNCTION NOW, AND p3b_run.lua CALLS IT AFTER THE OK PROMPT [Jay, T-P0-060].
-- ★★★★ These four writes ran AT SCRIPT LOAD, i.e. before DECB had printed anything -- so the
-- display left the text screen before the boot was on it and Jay never saw a BASIC prompt:
-- "you still are not getting to the basic prompt". The takeover was also happening at frame 4,
-- before the machine was ready, and both halves looked the same from the outside.
-- ★★★ THE ORDER JAY ASKED FOR: show DECB boot to OK, HOLD it long enough to confirm by eye,
-- then blank and take the machine over. That is what "black as soon as possible AFTER THE LOAD"
-- meant [T-P0-056b] -- after, not before, and this ran before.
-- ★★ The hook is optional on p3b_run.lua's side, so p3b_run.lua still runs standalone (headless,
-- no display to assert about) with nothing here defined.
_G._p3b_blank = function()
prog:write_u8(0xFF98, 0x80)
prog:write_u8(0xFF99, 0x3E)
for i = 0, 15 do prog:write_u8(0xFFB0 + i, 0x00) end
-- ★★★★★ AND POINT VOFFSET AT THE VISIBLE PLANE NOW, NOT AT CYCLE 2.
-- ★★★★ The notifier below sets VOFFSET once the guest is running, so until then the display was
-- still scanning wherever DECB left it -- the text screen, which the stager is busy overwriting.
-- A black palette hid that, until the guest started installing the REAL palette at init and Jay
-- saw it: "i saw a bunch of garbage before the king's quest title screen". **Two things have to
-- be true for the boot to be black: the palette must be black AND the display must be looking at
-- a plane we control.** Only the first was.
-- ★★★ 40 is P3_BLK_VISIBLE [p3b_probe.s] written as a literal because the guest has not been
-- staged yet, so p3_blk_vis cannot be read from memory. VOFFSET = block * 1024.
-- ★★ The guest blacks that plane at init and only then loads the palette, so the screen is black
-- from here until the first room is presented.
local BLK_VISIBLE = 40
prog:write_u8(0xFF9D, ((BLK_VISIBLE * 1024) >> 8) & 0xFF)
prog:write_u8(0xFF9E, (BLK_VISIBLE * 1024) & 0xFF)
print(string.format("display: mode 2 + 16 black palette entries + VOFFSET=$%04X asserted at TAKEOVER",
                    BLK_VISIBLE * 1024))
end
-- ═══════════════════════════════════════════════════════════════════════════════════════════

dofile("harness/tools/p3b_room.lua")


