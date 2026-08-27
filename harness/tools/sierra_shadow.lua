-- harness/tools/sierra_shadow.lua -- T-P0-017 / P3.8: is there a SHADOW BUFFER?
--
-- OPERATOR-DRIVEN. ★★★ NO INPUT PATH. Audit: grep "set_value\|:post\|natkeyboard" -> no hits.
-- Boot it yourself:  DOS <ENTER> ... wait ~25 s ... R <ENTER> (capital) ... CTRL+DELETE
-- then walk in and out of rooms.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- THE HYPOTHESIS: Sierra renders a room into an off-screen buffer DURING the disk load, then
-- BLITS it to the display when the load finishes. It survives every explanation T-P0-016 ruled
-- out -- a memory-to-memory copy writes no GIME register and needs no MMU swap -- and it would
-- explain why disk and render could never be separated: they overlap.
--
-- ★★★ TWO INSTRUMENTS, AND THE FIRST MAY SETTLE IT ALONE.
--
-- (A) WRITE-ORDER TRACE. ★★ An AGI picture is VECTOR commands -- lines, strokes and floods in
--     resource order, i.e. arbitrary spatial order. A raster sweep is what a MEMORY COPY looks
--     like. So classify every write by its address relative to the previous one:
--         seq  : addr == prev + 1          <- a copy walks memory this way
--         asc  : addr  > prev              <- weaker; a downward-drawing renderer also ascends
--         else : addr <= prev              <- vector interpretation jumps backwards constantly
--     and track the LONGEST RUN of consecutive +1 writes in the frame. ★★★ A 26,880-byte blit
--     produces one enormous run. A flood fill cannot, whatever its shape.
--     ★ This needs no assumption about WHERE the buffer is, which is why it goes first.
--
-- (B) 64 KB CPU-SPACE SNAPSHOTS around each transition, for the search.
--     ★★ Why the CPU window is the right search space even though physical RAM is 512 KB:
--     A MEMORY-TO-MEMORY BLIT REQUIRES BOTH ENDS MAPPED AT ONCE. If Sierra copies a rendered
--     room to the screen, the source is CPU-visible at that instant by construction. A shadow
--     buffer that is never CPU-visible cannot be blitted from by the 6809.
--     ★ That is an argument, not a proof, and §AC-3 of the report states what it does not cover:
--     a buffer made visible by an MMU remap AT the moment of the copy would be seen only in a
--     snapshot taken during the copy itself.
--
-- ★★ MAME's Lua cannot read physical RAM outside the window on this driver: there is no :ram
-- share or region, the ram_device exposes no read method, and the GIME publishes no address
-- space. Only :maincpu (32 KB ROM) and :ext:fdc:eprom are regions. Probed, not assumed.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local OUT = os.getenv("SIERRA_OUT") or "build/sierra_shadow"
local DUMP = os.getenv("SIERRA_DUMP") or (OUT .. "/dumps")
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
os.execute('mkdir "' .. DUMP:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local csv  = io.open(OUT .. "/frames.csv", "w")
csv:write("frame,time_s,changed,fdc,voffset,total,"
       .. "b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,bA,bB,bC,bD,bE,bF,"
       .. "n_mmu,n_pal,n_vid,init0,vmode,vres,border,"
       .. "w_seq,w_asc,w_other,w_maxrun,w_lo,w_hi\n")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local prog = m.devices[":maincpu"].spaces["program"]
local scr  = m.screens:at(1)

_G._fdc, _G._voff = 0, 0
_G._b = {}; for i = 0, 15 do _G._b[i] = 0 end
_G._n_mmu, _G._n_pal, _G._n_vid = 0, 0, 0
_G._init0, _G._vmode, _G._vres, _G._border = -1, -1, -1, -1
_G._gev = {}

-- ---- (A) the write-order classifier -------------------------------------------------------
_G._prev = -2
_G._seq, _G._asc, _G._oth = 0, 0, 0
_G._run, _G._maxrun = 0, 0
_G._lo, _G._hi = 0x10000, -1

_G._t1 = prog:install_write_tap(0xFF40, 0xFF4F, "fw", function() _G._fdc = _G._fdc + 1 end)
_G._t2 = prog:install_read_tap (0xFF40, 0xFF4F, "fr", function() _G._fdc = _G._fdc + 1 end)

_G._tg = prog:install_write_tap(0xFF90, 0xFFBF, "gime", function(off, data)
    local d = data % 256
    local function ev(f, ...) _G._gev[#_G._gev + 1] = string.format(f, ...) end
    if off == 0xFF90 then
        if d ~= _G._init0 then ev("INIT0=$%02X", d); _G._init0 = d end
    elseif off == 0xFF98 then
        if d ~= _G._vmode then ev("VMODE=$%02X BP=%d", d, (d & 0x80) ~= 0 and 1 or 0); _G._vmode = d end
    elseif off == 0xFF99 then
        if d ~= _G._vres then ev("VRES=$%02X LPF=%d", d, (d >> 5) & 3); _G._vres = d end
    elseif off == 0xFF9A then
        if d ~= _G._border then ev("BORDER=$%02X", d); _G._border = d end
    elseif off == 0xFF9D or off == 0xFF9E then
        _G._voff = _G._voff + 1; ev("VOFFSET $%04X<=$%02X", off, d)
    elseif off >= 0xFFA0 and off <= 0xFFAF then
        _G._n_mmu = _G._n_mmu + 1
        -- ★ MMU registers are WRITE-ONLY, so the only way to know the current mapping is to
        -- watch it being set. OS-9 task-switches constantly, so all eight fill in quickly.
        _G._mmu = _G._mmu or {}
        _G._mmu[off - 0xFFA0] = d
    elseif off >= 0xFFB0 then _G._n_pal = _G._n_pal + 1
    end
    if off >= 0xFF98 and off <= 0xFF9F then _G._n_vid = _G._n_vid + 1 end
end)

_G._t3 = prog:install_write_tap(0x0000, 0xFEFF, "all", function(off)
    _G._b[off // 4096] = _G._b[off // 4096] + 1
    if off == _G._prev + 1 then
        _G._seq = _G._seq + 1
        _G._run = _G._run + 1
        if _G._run > _G._maxrun then _G._maxrun = _G._run end
    elseif off > _G._prev then
        _G._asc = _G._asc + 1; _G._run = 0
    else
        _G._oth = _G._oth + 1; _G._run = 0
    end
    _G._prev = off
    if off < _G._lo then _G._lo = off end
    if off > _G._hi then _G._hi = off end
end)

pcall(function()
    local cs = m.ioport.ports[":ctrl_sel"]
    if cs then for n, f in pairs(cs.fields) do f.user_value = 0; w("ctrl_sel: %q -> Unconnected", n) end end
end)

-- ---- (B) the snapshot ---------------------------------------------------------------------
-- ★ 65,280 bytes read through prog:read_u8 takes ~0.08 s of HOST time (measured), which is
-- invisible to the guest -- emulated time does not advance inside a frame notifier.
local nsnap = 0
local function snapshot(tag, frame, t)
    nsnap = nsnap + 1
    local name = string.format("%s/%03d_%s_f%05d.bin", DUMP, nsnap, tag, frame)
    local f = io.open(name, "wb")
    if not f then w("[f%05d] SNAPSHOT FAILED to open %s", frame, name); return end
    local buf = {}
    for a = 0, 0xFEFF do
        buf[#buf + 1] = string.char(prog:read_u8(a) & 0xFF)
        if #buf >= 4096 then f:write(table.concat(buf)); buf = {} end
    end
    if #buf > 0 then f:write(table.concat(buf)) end
    f:close()
    -- ★ record the MMU mapping alongside: a dump of the CPU window is meaningless later
    -- without knowing which physical blocks it was showing.
    local mm = {}
    for i = 0, 7 do mm[#mm + 1] = string.format("%02X", (_G._mmu and _G._mmu[i]) or 255) end
    w("[f%05d] t=%.3f  SNAP %s -> %s  mmu=%s", frame, t, tag, name:match("[^/]+$"),
      table.concat(mm, " "))
end

local LAT, prev = {}, {}
for gy = 1, 10 do for gx = 1, 16 do
    LAT[#LAT + 1] = { math.floor(640 * (gx - 0.5) / 16), math.floor(239 * (gy - 0.5) / 10) }
end end
for i = 1, #LAT do prev[i] = -1 end

-- detector parameters, identical to sierra_rooms.py's defaults (L-44: stated, not implied)
local GAP_FRAMES, SETTLE_FRAMES, MIN_LAT, MIN_FDC = 30, 60, 30, 2000
local frame, nroom = 0, 0
local dsk_start, dsk_end, dsk_quiet, draw_lat, settle = nil, nil, 0, 0, 0
local snapped_pre, dur_at = false, 0

w("sierra_shadow: write-order trace + 64 KB snapshots. OBSERVE ONLY -- no input path.")
w("Boot: DOS <ENTER> ... ~25 s ... R <ENTER> ... CTRL+DELETE, then walk between rooms.")

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    local t = m.time:as_double()

    local ch = 0
    for i = 1, #LAT do
        local px = scr:pixel(LAT[i][1], LAT[i][2]) or 0
        if px ~= prev[i] then ch = ch + 1; prev[i] = px end
    end
    if frame == 1 then ch = 0 end

    local fd = _G._fdc; _G._fdc = 0
    local vo = _G._voff; _G._voff = 0
    local per, tot = {}, 0
    for i = 0, 15 do per[i] = _G._b[i]; tot = tot + per[i]; _G._b[i] = 0 end
    local nm, np, nv = _G._n_mmu, _G._n_pal, _G._n_vid
    _G._n_mmu, _G._n_pal, _G._n_vid = 0, 0, 0
    local sq, as, ot = _G._seq, _G._asc, _G._oth
    local mr, lo, hi = _G._maxrun, _G._lo, _G._hi
    _G._seq, _G._asc, _G._oth, _G._maxrun = 0, 0, 0, 0
    _G._lo, _G._hi = 0x10000, -1
    _G._run, _G._prev = 0, -2

    if #_G._gev > 0 then
        w("[f%05d] t=%.3f  GIME: %s", frame, t, table.concat(_G._gev, "  "))
        _G._gev = {}
    end
    -- ★★ A very long sequential run is the blit signature. Surfaced the instant it happens so
    -- it cannot be lost in the CSV, and so Jay's eye and the instrument share the event (AC-8).
    if mr >= 1024 then
        w("[f%05d] t=%.3f  ★★ SEQUENTIAL RUN %d bytes  ($%04X-$%04X, %d writes this frame)",
          frame, t, mr, lo, hi, sq + as + ot)
    end

    -- ---- transition state machine (identical to sierra_rooms.py) ---------------------------
    if fd > 0 then
        if (not dsk_start) or dsk_quiet >= GAP_FRAMES then
            dsk_start = { frame, t, 0 }
            snapped_pre = false; dur_at = 0
        end
        dsk_start[3] = dsk_start[3] + fd
        dsk_end = { frame, t }
        dsk_quiet, draw_lat, settle = 0, 0, 0
        if not snapped_pre then
            snapshot("pre", frame, t)         -- ★ the load has just begun
            snapped_pre = true
        elseif frame - dur_at >= 60 and dsk_start[3] >= 500 then
            snapshot("dur", frame, t)         -- ★ once a second WHILE the disk works
            dur_at = frame
        end
    elseif dsk_start then
        dsk_quiet = dsk_quiet + 1
        draw_lat = draw_lat + ch
        if ch == 0 then settle = settle + 1 else settle = 0 end
        if dsk_quiet == 1 then snapshot("diskend", frame, t) end   -- ★ disk stops, draw begins
        if dsk_quiet >= GAP_FRAMES and settle >= SETTLE_FRAMES then
            if dsk_start[3] >= MIN_FDC and draw_lat >= MIN_LAT then
                nroom = nroom + 1
                local disk = dsk_end[2] - dsk_start[2]
                local draw = (t - SETTLE_FRAMES / 59.92) - dsk_end[2]
                w("[f%05d] * ROOM CHANGE %d: disk %.3f s (%d acc) + draw %.3f s = %.3f s  lat=%d/160",
                  frame, nroom, disk, dsk_start[3], draw, disk + draw, draw_lat)
                snapshot("post", frame, t)
                scr:snapshot()
            end
            dsk_start, dsk_end = nil, nil
            dsk_quiet, draw_lat, settle = 0, 0, 0
        end
    end

    csv:write(string.format(
        "%d,%.9f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
        frame, t, ch, fd, vo, tot,
        per[0], per[1], per[2], per[3], per[4], per[5], per[6], per[7],
        per[8], per[9], per[10], per[11], per[12], per[13], per[14], per[15],
        nm, np, nv, _G._init0, _G._vmode, _G._vres, _G._border,
        sq, as, ot, mr, lo == 0x10000 and -1 or lo, hi))
end)
