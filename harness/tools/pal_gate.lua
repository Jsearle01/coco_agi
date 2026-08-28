-- harness/tools/pal_gate.lua -- AC-11's readback and AC-12's swatch capture.
--
-- ★★ AC-11 reads $00A0-$00AF, which pal_readback filled from $FFB0-$FFBF with bits 7-6 masked
-- [SockmasterGime.md: "like the MMU registers, the upper 2 bits must be masked out"]. Reading
-- the registers from the HOST instead would test MAME's palette model, not the guest's writes.
--
-- ★★★ AC-12 only SNAPSHOTS. It does not interpret the image: CLAUDE.md §3 forbids reading PNG
-- pixel content, and §4 makes the eye gate Jay's. The file is produced and surfaced, nothing
-- more, and the report records it as "pending Jay".

local OUT  = os.getenv("PAL_OUT")  or "build/pal"
local PROG = os.getenv("PAL_PROG") or "build/pal_ac11.bin"
local SNAP = os.getenv("PAL_SNAP")            -- set for AC-12
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD     = 0x0700
local READBACK = 0x00A0

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end

local frame, state = 0, "load"
_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    if state == "load" then
        local blob = slurp(PROG)
        if not blob then w("★★★ no program at %s", PROG); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        cpu.state["PC"].value = LOAD
        w("program %d bytes at $%04X, PC set", #blob, LOAD)
        state = "run"
        _G._at = frame
        return
    end

    -- ★ 30 frames: pal_readback runs in the prologue, so this is generous rather than tuned.
    if state == "run" and frame - _G._at > 30 then
        local vals = {}
        for i = 0, 15 do vals[#vals + 1] = prog:read_u8(READBACK + i) end
        local f = io.open(OUT .. "/readback.txt", "w")
        for i = 1, 16 do f:write(string.format("%d %02X\n", i - 1, vals[i])) end
        f:close()
        w("palette readback ($FFB0-$FFBF, bits 7-6 masked):")
        w("  %s", table.concat(vals, " ", 1, 8))
        w("  %s", table.concat(vals, " ", 9, 16))

        if SNAP then
            -- ★ MAME writes the snapshot under its own snapshot directory; the path is echoed
            -- so the report can name the file rather than describe it.
            m.video:snapshot()
            w("snapshot requested -> %s", SNAP)
        end
        state = "done"
        _G._at2 = frame
        return
    end

    if state == "done" and frame - _G._at2 > 4 then
        m:exit()
    end
end)
