-- harness/tools/sierra_live.lua -- T-P0-015: OBSERVE ONLY, whole-map write census.
--
-- ★★★ THIS SCRIPT HAS NO INPUT PATH. No natkeyboard, no ioport write, nothing on a timer.
-- BREAK is bound in the cfg (currently DELETE) -- press Ctrl+Delete. Jay drives everything.
-- ★ Audit with:  grep -n "set_value\|:post\|natkeyboard"  -- there should be NO hits.
--
-- ★★ WHY LUA MUST NOT DRIVE INPUT: ioport_field:set_value() is a PERMANENT programmatic
-- override, not a momentary press. Writing defvalue back marks the field released but never
-- hands it back to the input system, so any script that touches CTRL owns CTRL for the session
-- -- and movement here is CTRL+letter, so a stuck CTRL turns every keystroke into a menu
-- command. Three trigger designs failed for that one reason before it was understood.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THIS RUN IS FOR: is a room change a RENDER or a COPY?
--
-- A confirmed inside->outside transition was captured at t=185.54 s with:
--   * ZERO disk -- the last FDC access was 50.7 s earlier;
--   * the whole transition inside FIVE FRAMES (0.083 s);
--   * only ~6,100 writes seen, in an 8 KB window.
-- ★★ A 160x168 picture needs >= 26,880 pixel writes, and 0.083 s at 1.79 MHz is 5.5 cycles per
-- pixel -- not achievable for opcode interpretation plus a flood fill. ~6,100 writes IS what a
-- ~27 KB block copy looks like when the tap covers only 8 KB of the buffer.
-- ★★★ So: count writes across the WHOLE map, bucketed by 4 KB. A COPY shows ~27 K writes in a
-- tight burst concentrated in one or two blocks. An opcode-driven RENDER shows far more writes,
-- spread over many more frames.
-- ★ The earlier whole-map tap still ran at 950% of real time, so this is affordable while
-- playing at normal speed.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local OUT = os.getenv("SIERRA_OUT") or "build/sierra_live"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local csv  = io.open(OUT .. "/frames.csv", "w")
csv:write("frame,time_s,changed,fdc,voffset,total,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,bA,bB,bC,bD,bE,bF\n")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local prog = m.devices[":maincpu"].spaces["program"]
local scr  = m.screens:at(1)

_G._fdc = 0
-- ★★★ THE DECIDING TAP: VOFFSET at $FF9D-$FF9E. A confirmed room change showed NO write burst
-- and NO disk -- the write rate through the transition matched the surrounding baseline, and
-- 1,068 writes in the changing frame is BELOW it. That rules out an opcode-driven render AND a
-- block copy (27 KB would spike). What changes a whole screen with neither is a PAGE FLIP:
-- pointing the GIME at a buffer that was already prepared. VOFFSET is write-only, so a write
-- tap is the only way to see it.
-- ★ If VOFFSET is written at the instant the room changes, Sierra does not render at transition
-- time at all -- and the steady ~1,600 writes/frame during play is the NEXT screen being built.
_G._voff = 0
_G._voff_log = {}
_G._b = {}
for i = 0, 15 do _G._b[i] = 0 end

_G._t1 = prog:install_write_tap(0xFF40, 0xFF4F, "fw", function() _G._fdc = _G._fdc + 1 end)
_G._t2 = prog:install_read_tap (0xFF40, 0xFF4F, "fr", function() _G._fdc = _G._fdc + 1 end)
_G._tv = prog:install_write_tap(0xFF9D, 0xFF9E, "voffset", function(off, data)
    _G._voff = _G._voff + 1
    _G._voff_log[#_G._voff_log + 1] = string.format("$%04X<=$%02X", off, data % 256)
end)
_G._t3 = prog:install_write_tap(0x0000, 0xFEFF, "all", function(off)
    local k = off // 4096
    _G._b[k] = _G._b[k] + 1
end)

-- ★★ PASSIVE KEY NAMING. Jay asked whether the run specifies a keyboard type: it does not --
-- the coco3 driver has no keyboard-layout config at all (Becker, ctrl_sel, drivewire port,
-- artifacting, hires_intf, RS232, screen_config -- and nothing else). The CoCo3 keyboard is a
-- fixed matrix and MAME maps host keys straight onto it.
-- ★ So instead of guessing the movement keys, this READS every row each frame and names the
-- CoCo3 keys actually asserted. Press anything; the log says what the machine received. This
-- only READS ioport state -- it never writes a field.
local KROWS = {}
for _, tg in ipairs({":row0", ":row1", ":row2", ":row3", ":row4", ":row5", ":row6"}) do
    local pt = m.ioport.ports[tg]
    if pt then KROWS[#KROWS + 1] = { tg, pt } end
end
local last_keys = ""

-- ★★ CONTROLLER PORTS -> UNCONNECTED. Both default to "Joystick", and an interpreter that
-- polls a joystick for movement would ignore the keyboard entirely -- which is exactly the
-- symptom: every key arrives correctly on the CoCo3 matrix and nothing responds.
-- ★ This is a MACHINE CONFIGURATION (field.user_value on an IPT_CONFIG port), the same
-- mechanism as Monitor Type -- it is NOT keyboard input and does not touch any key field.
-- Set to Unconnected: Right (P1) 0, Left (P2) 0.
pcall(function()
    local cs = m.ioport.ports[":ctrl_sel"]
    if cs then
        for n, f in pairs(cs.fields) do
            f.user_value = 0
            w("ctrl_sel: %q -> Unconnected", n)
        end
    end
end)

local LAT, prev = {}, {}
for gy = 1, 10 do
    for gx = 1, 16 do
        LAT[#LAT + 1] = { math.floor(640 * (gx - 0.5) / 16), math.floor(239 * (gy - 0.5) / 10) }
    end
end
for i = 1, #LAT do prev[i] = -1 end

w("sierra_live: OBSERVE ONLY. This script cannot send input.")
w("BREAK is bound in the cfg (DELETE) -- press Ctrl+Delete. Everything is yours.")
w("Whole-map write census is on. A picture repaint (>=30/160) logs a ROOM CHANGE line.")

local frame, peak, peak_f = 0, 0, 0
local dsk_start, dsk_end, dsk_quiet = nil, nil, 0
local drawing, draw_lat, settle, nroom = false, 0, 0, 0

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    local t = m.time:as_double()

    local ch = 0
    for i = 1, #LAT do
        local px = scr:pixel(LAT[i][1], LAT[i][2]) or 0
        if px ~= prev[i] then ch = ch + 1; prev[i] = px end
    end
    -- ★ The lattice starts at -1, so the first sampled frame would report all 160 changed.
    if frame == 1 then ch = 0 end

    -- name whatever CoCo3 keys are currently down (read-only)
    local down = {}
    for _, e in ipairs(KROWS) do
        local v = e[2]:read()
        for n, f in pairs(e[2].fields) do
            if n ~= "Keyboard" and (v & f.mask) ~= (f.defvalue & f.mask) then
                down[#down + 1] = n
            end
        end
    end
    table.sort(down)
    local keys = table.concat(down, "+")
    if keys ~= last_keys then
        if keys ~= "" then w("[f%05d] t=%.2f  KEYS: %s", frame, t, keys) end
        last_keys = keys
    end

    local fd = _G._fdc; _G._fdc = 0
    local vo = _G._voff; _G._voff = 0
    local volist = table.concat(_G._voff_log, " "); _G._voff_log = {}
    if vo > 0 then
        w("[f%05d] t=%.3f  VOFFSET WRITE x%d  %s", frame, t, vo, volist)
    end
    local per, tot = {}, 0
    for i = 0, 15 do per[i] = _G._b[i]; tot = tot + per[i]; _G._b[i] = 0 end

    -- ★★★ THE DETECTOR, CORRECTED. A per-frame lattice threshold DOES NOT WORK: Sierra draws
    -- a new room PROGRESSIVELY, so the lattice moves a few points per frame and never spikes.
    -- Measured across 7 operator-confirmed room changes, the per-frame maximum was 16/160 while
    -- the cumulative change was 47-103. A detector that assumes an instantaneous repaint is
    -- blind to a progressive one -- and it reported "no room change" through fifteen of them.
    -- ★ The real signature is: DISK BURST -> (disk stops) -> DRAW -> screen settles.
    if fd > 0 then
        if not dsk_start then dsk_start = { frame, t, 0 } end
        dsk_start[3] = dsk_start[3] + fd
        dsk_quiet = 0
        drawing = false
    elseif dsk_start then
        dsk_quiet = dsk_quiet + 1
        if dsk_quiet == 1 then dsk_end = { frame, t }; drawing = true; draw_lat = 0 end
    end
    if drawing then
        draw_lat = draw_lat + ch
        if ch == 0 then
            settle = settle + 1
            if settle >= 60 and dsk_start[3] >= 2000 then
                local disk = dsk_end[2] - dsk_start[2]
                local draw = t - 60/59.92 - dsk_end[2]
                nroom = nroom + 1
                w("[f%05d] * ROOM CHANGE %d: disk %.3f s (%d acc) + draw %.3f s = %.3f s  lat=%d voff=%d",
                  frame, nroom, disk, dsk_start[3], draw, disk + draw, draw_lat, vo)
                scr:snapshot()
                dsk_start, dsk_end, drawing, settle = nil, nil, false, 0
            end
        else
            settle = 0
        end
        if dsk_start and t - dsk_end[2] > 20 then     -- give up on a stale candidate
            dsk_start, dsk_end, drawing, settle = nil, nil, false, 0
        end
    end

    if ch > peak then peak, peak_f = ch, frame end

    csv:write(string.format("%d,%.9f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
        frame, t, ch, fd, vo, tot,
        per[0], per[1], per[2], per[3], per[4], per[5], per[6], per[7],
        per[8], per[9], per[10], per[11], per[12], per[13], per[14], per[15]))

    if frame % 3600 == 0 then
        w("[f%05d] t=%.0fs  peak lattice %d/160 (f%d)", frame, t, peak, peak_f)
    end
end)
