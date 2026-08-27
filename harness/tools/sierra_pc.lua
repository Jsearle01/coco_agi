-- harness/tools/sierra_pc.lua -- T-P0-018 / P3.9: LOCATE THE FILL, AND PRICE IT.
--
-- OPERATOR-DRIVEN. ★★★ NO INPUT PATH. Audit: grep "set_value\|:post\|natkeyboard" -> no hits.
-- Boot: DOS <ENTER> ... ~25 s ... R <ENTER> (capital) ... CTRL+DELETE, then walk between rooms.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- TWO THINGS T-P0-017 COULD NOT DO, BOTH FIXED HERE.
--
-- (1) ★★★ PHYSICAL ADDRESSES. T-P0-017 counted writes by CPU address, so it could not say
--     which of them landed on the SCREEN -- and its shadow-buffer search covered ~11% of RAM
--     for exactly this reason. The MMU registers are write-only, but every write to them is
--     visible to a tap, so the mapping can be TRACKED and each write resolved:
--          physical = block[slot] * 8192 + (cpu_addr & 0x1FFF),  slot = cpu_addr >> 13
--     ★★ $FF91 bit 0 (TR) selects which half of $FFA0-$FFAF is live [ref: GIME-RM §2 register
--     map; SockmasterGime.md INIT1 bit 0 TR], so both task sets are tracked and TR chooses.
--     ★ Writes made before the mapping is known are counted as UNRESOLVED, never guessed.
--
-- (2) ★★★ THE PC OF THE CODE DOING THE DRAWING. This is what locates the fill. Sampling PC on
--     every write would be ruinous, so it is sampled only when a SEQUENTIAL RUN reaches
--     PC_AT_RUN bytes -- i.e. only inside the inner loop of whatever emits the long runs.
--     ★★ T-P0-017 measured 152 draw-phase frames whose longest run is EXACTLY 160 bytes = one
--     picture row. The PC histogram at those moments IS the fill's inner loop, by construction.
--
-- ★★★ AND THE NUMBER THE WHOLE THREAD HAS BEEN FOR (AC-4), derivable without any disassembly:
--     cycles per screen pixel = draw-phase seconds x 1.79 MHz / writes landing on the display.
--     Ours is ~506 (7.473 s / 26,409 px). ★ A static cycle count is better; this is obtainable
--     now, and an aggregate that includes their non-fill work is a CEILING on their fill.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local OUT = os.getenv("SIERRA_OUT") or "build/sierra_pc"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local csv  = io.open(OUT .. "/frames.csv", "w")
csv:write("frame,time_s,changed,fdc,voffset,total,"
       .. "b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,bA,bB,bC,bD,bE,bF,"
       .. "n_mmu,n_pal,n_vid,init0,vmode,vres,border,"
       .. "w_seq,w_asc,w_other,w_maxrun,w_lo,w_hi,"
       .. "scr_w,unres,pcsamp\n")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens:at(1)

local PC_AT_RUN = 64        -- ★ sample PC once a run reaches this length (L-44: stated)

_G._fdc, _G._voff = 0, 0
_G._b = {}; for i = 0, 15 do _G._b[i] = 0 end
_G._n_mmu, _G._n_pal, _G._n_vid = 0, 0, 0
_G._init0, _G._vmode, _G._vres, _G._border, _G._init1 = -1, -1, -1, -1, -1
_G._gev = {}
_G._mmu0, _G._mmu1 = {}, {}          -- task 0 ($FFA0-$FFA7), task 1 ($FFA8-$FFAF)
_G._voffset = -1                     -- physical screen start
_G._scrw, _G._unres = 0, 0           -- writes landing on the display / unresolvable
_G._pc = {}                          -- PC histogram, sampled inside long runs
_G._pcn = 0
_G._prev, _G._seq, _G._asc, _G._oth = -2, 0, 0, 0
_G._run, _G._maxrun = 0, 0
_G._lo, _G._hi = 0x10000, -1

_G._t1 = prog:install_write_tap(0xFF40, 0xFF4F, "fw", function() _G._fdc = _G._fdc + 1 end)
_G._t2 = prog:install_read_tap (0xFF40, 0xFF4F, "fr", function() _G._fdc = _G._fdc + 1 end)

_G._tg = prog:install_write_tap(0xFF90, 0xFFBF, "gime", function(off, data)
    local d = data % 256
    local function ev(f, ...) _G._gev[#_G._gev + 1] = string.format(f, ...) end
    if off == 0xFF90 then
        if d ~= _G._init0 then ev("INIT0=$%02X", d); _G._init0 = d end
    elseif off == 0xFF91 then
        if d ~= _G._init1 then ev("INIT1=$%02X TR=%d", d, d & 1); _G._init1 = d end
    elseif off == 0xFF98 then
        if d ~= _G._vmode then ev("VMODE=$%02X", d); _G._vmode = d end
    elseif off == 0xFF99 then
        if d ~= _G._vres then ev("VRES=$%02X", d); _G._vres = d end
    elseif off == 0xFF9A then
        if d ~= _G._border then ev("BORDER=$%02X", d); _G._border = d end
    elseif off == 0xFF9D or off == 0xFF9E then
        _G._voff = _G._voff + 1
        if off == 0xFF9D then _G._vo_hi = d else _G._vo_lo = d end
        if _G._vo_hi and _G._vo_lo then
            -- ★ VOFFSET is the screen start in 8-byte units [ref: GIME-RM §2]
            local phys = ((_G._vo_hi * 256) + _G._vo_lo) * 8
            if phys ~= _G._voffset then
                _G._voffset = phys
                ev("SCREEN START = physical $%05X", phys)
            end
        end
    elseif off >= 0xFFA0 and off <= 0xFFAF then
        _G._n_mmu = _G._n_mmu + 1
        if off <= 0xFFA7 then _G._mmu0[off - 0xFFA0] = d else _G._mmu1[off - 0xFFA8] = d end
    elseif off >= 0xFFB0 then _G._n_pal = _G._n_pal + 1
    end
    if off >= 0xFF98 and off <= 0xFF9F then _G._n_vid = _G._n_vid + 1 end
end)

-- ★★ 160 bytes/row x 192 rows = 30,720 B [VRES $1E -> HRES=111, LPF=00; ref GIME-RM §6]
local SCREEN_BYTES = 30720

_G._t3 = prog:install_write_tap(0x0000, 0xFEFF, "all", function(off)
    _G._b[off // 4096] = _G._b[off // 4096] + 1

    -- (1) resolve to a physical address through the tracked MMU
    local tab = ((_G._init1 >= 0) and (_G._init1 & 1) == 1) and _G._mmu1 or _G._mmu0
    local blk = tab[off >> 13]
    if blk == nil or _G._voffset < 0 then
        _G._unres = _G._unres + 1
    else
        local phys = blk * 8192 + (off & 0x1FFF)
        if phys >= _G._voffset and phys < _G._voffset + SCREEN_BYTES then
            _G._scrw = _G._scrw + 1
        end
    end

    -- (2) write-order classification, and the PC sample inside a long run
    if off == _G._prev + 1 then
        _G._seq = _G._seq + 1
        _G._run = _G._run + 1
        if _G._run > _G._maxrun then _G._maxrun = _G._run end
        if _G._run == PC_AT_RUN then
            local ok, pc = pcall(function() return cpu.state["PC"].value end)
            if ok then
                _G._pc[pc] = (_G._pc[pc] or 0) + 1
                _G._pcn = _G._pcn + 1
            end
        end
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
    if cs then for n, f in pairs(cs.fields) do f.user_value = 0 end end
end)

local LAT, prev = {}, {}
for gy = 1, 10 do for gx = 1, 16 do
    LAT[#LAT + 1] = { math.floor(640 * (gx - 0.5) / 16), math.floor(239 * (gy - 0.5) / 10) }
end end
for i = 1, #LAT do prev[i] = -1 end

local GAP_FRAMES, SETTLE_FRAMES, MIN_LAT, MIN_FDC = 30, 60, 30, 2000
local frame, nroom = 0, 0
local dsk_start, dsk_end, dsk_quiet, draw_lat, settle = nil, nil, 0, 0, 0

-- ★ per-transition PC histogram: snapshot the counts at the start of each draw phase so the
-- fill's PCs can be separated from everything else the machine does.
local pc_at_diskend = nil
local function pc_snapshot()
    local t = {}
    for k, v in pairs(_G._pc) do t[k] = v end
    return t
end
local function pc_delta(a, b)
    local d = {}
    for k, v in pairs(b) do
        local base = a[k] or 0
        if v > base then d[#d + 1] = { k, v - base } end
    end
    table.sort(d, function(x, y) return x[2] > y[2] end)
    return d
end

w("sierra_pc: physical-address resolution + PC sampling at run>=%d. OBSERVE ONLY.", PC_AT_RUN)
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
    local sw, ur = _G._scrw, _G._unres
    _G._scrw, _G._unres = 0, 0
    local pn = _G._pcn; _G._pcn = 0

    if #_G._gev > 0 then
        w("[f%05d] t=%.3f  GIME: %s", frame, t, table.concat(_G._gev, "  "))
        _G._gev = {}
    end

    if fd > 0 then
        if (not dsk_start) or dsk_quiet >= GAP_FRAMES then dsk_start = { frame, t, 0 } end
        dsk_start[3] = dsk_start[3] + fd
        dsk_end = { frame, t }
        dsk_quiet, draw_lat, settle = 0, 0, 0
    elseif dsk_start then
        dsk_quiet = dsk_quiet + 1
        draw_lat = draw_lat + ch
        if ch == 0 then settle = settle + 1 else settle = 0 end
        if dsk_quiet == 1 then pc_at_diskend = pc_snapshot() end
        if dsk_quiet >= GAP_FRAMES and settle >= SETTLE_FRAMES then
            if dsk_start[3] >= MIN_FDC and draw_lat >= MIN_LAT then
                nroom = nroom + 1
                local disk = dsk_end[2] - dsk_start[2]
                local draw = (t - SETTLE_FRAMES / 59.92) - dsk_end[2]
                w("[f%05d] * ROOM CHANGE %d: disk %.3f s + draw %.3f s  lat=%d/160",
                  frame, nroom, disk, draw, draw_lat)
                -- ★★★ the PCs that emitted long sequential runs during THIS draw phase
                if pc_at_diskend then
                    local d = pc_delta(pc_at_diskend, _G._pc)
                    local shown = 0
                    for _, e in ipairs(d) do
                        if shown < 12 then
                            w("      PC $%04X  x%d", e[1], e[2]); shown = shown + 1
                        end
                    end
                    if shown == 0 then w("      (no PC samples in this draw phase)") end
                end
            end
            dsk_start, dsk_end = nil, nil
            dsk_quiet, draw_lat, settle = 0, 0, 0
        end
    end

    csv:write(string.format(
        "%d,%.9f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
        frame, t, ch, fd, vo, tot,
        per[0], per[1], per[2], per[3], per[4], per[5], per[6], per[7],
        per[8], per[9], per[10], per[11], per[12], per[13], per[14], per[15],
        nm, np, nv, _G._init0, _G._vmode, _G._vres, _G._border,
        sq, as, ot, mr, lo == 0x10000 and -1 or lo, hi,
        sw, ur, pn))
end)

-- ★ dump the whole PC histogram at exit so nothing depends on the live log
_G._stop = emu.add_machine_stop_notifier(function()
    local f = io.open(OUT .. "/pc_hist.csv", "w")
    if f then
        f:write("pc,count\n")
        local t = {}
        for k, v in pairs(_G._pc) do t[#t + 1] = { k, v } end
        table.sort(t, function(a, b) return a[2] > b[2] end)
        for _, e in ipairs(t) do f:write(string.format("%d,%d\n", e[1], e[2])) end
        f:close()
    end
end)
