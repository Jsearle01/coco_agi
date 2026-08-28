-- harness/tools/sierra_trace.lua -- T-P0-019 / P3.10: GATED LIVE TRACE OF THE FILL.
--
-- OPERATOR-DRIVEN. ★★★ NO INPUT PATH. Audit: grep "set_value\|:post\|natkeyboard" -> no hits.
-- Boot: DOS <ENTER> ... ~25 s ... R <ENTER> (capital) ... CTRL+DELETE, then walk between rooms.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ WHY A TRACE AND NOT A DUMP. P3.9 located the fill at PC $E1B1 across five transitions,
-- then read the bytes at that address out of an EARLIER session's memory dumps. CPU slot 7
-- holds whatever block the MMU mapped in THAT session's OS-9 task, so the bytes decoded
-- cleanly into a loop with NO STORE INSTRUCTION -- code that cannot be doing 26,000 writes.
-- 0 of 120 windows from that region appeared anywhere in the extracted module.
-- ★★ MAME's tracer disassembles LIVE, at execution time, through the map as it actually is.
-- There is no "which block was mapped" question to get wrong: the failure cause is removed,
-- not mitigated. [Jay, 2026-08-28]
--
-- ★★ VERIFIED BEFORE BUILDING (L-47): a 10-frame trace on a plain boot produced 1,013 lines of
-- real disassembly (`A7D5: BNE $A7D3` ...), so the form works and emits instructions.
--
-- ★★★ VOLUME IS THE ONLY REAL RISK, so the trace is GATED THREE WAYS:
--   1. it starts only when a DISK BURST ENDS -- the draw phase, where the 160-byte row runs are
--   2. it runs for TRACE_FRAMES frames and then stops
--   3. it arms ONCE, for the first qualifying transition, then disarms permanently
-- ★ At ~1.79 MHz a frame is ~29,900 cycles, so TRACE_FRAMES=6 is ~180,000 cycles, roughly
-- 40,000 instructions and a few MB. That window holds ~40 picture rows and several thousand
-- inner-loop iterations -- far more than is needed to read a loop.
-- ★ noloop is passed so every instruction appears; MAME otherwise collapses repeats into
-- "(loops for N instructions)", which is easier to read but destroys the counts AC-4 needs.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local OUT   = os.getenv("SIERRA_OUT")   or "build/sierra_trace"
local TRDIR = os.getenv("SIERRA_TRACE") or "C:/Users/jayse/AppData/Local/Temp/claude/c--Projects-coco-agi/cb21c600-0f44-4dc7-b6e0-4da1fd2ac46e/scratchpad/trace"
local TRACE_FRAMES = tonumber(os.getenv("SIERRA_TRACE_FRAMES") or "10")   -- ★ L-44: stated
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
os.execute('mkdir "' .. TRDIR:gsub("/", "\\") .. '" 2>nul')

local logf = io.open(OUT .. "/run.log", "w")
local csv  = io.open(OUT .. "/frames.csv", "w")
csv:write("frame,time_s,changed,fdc,voffset,total,"
       .. "b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,bA,bB,bC,bD,bE,bF,"
       .. "n_mmu,n_pal,n_vid,init0,vmode,vres,border,"
       .. "w_seq,w_asc,w_other,w_maxrun,w_lo,w_hi,scr_w,unres,pcsamp,tracing\n")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens:at(1)

-- ★ headless/attached -debug starts PAUSED and hangs without this (idiom §10)
if m.debugger then
    pcall(function() m.debugger.execution_state = "run" end)
    w("debugger present; execution_state=%s", tostring(m.debugger.execution_state))
else
    w("★★★ NO DEBUGGER -- launch with -debug or no trace can be taken.")
end

local PC_AT_RUN = 128   -- ★ raised from 64: only the picture fill reaches a full row
_G._fdc, _G._voff = 0, 0
_G._b = {}; for i = 0, 15 do _G._b[i] = 0 end
_G._n_mmu, _G._n_pal, _G._n_vid = 0, 0, 0
_G._init0, _G._vmode, _G._vres, _G._border, _G._init1 = -1, -1, -1, -1, -1
_G._gev = {}
_G._mmu0, _G._mmu1 = {}, {}
_G._voffset = -1
_G._scrw, _G._unres = 0, 0
_G._pc, _G._pcn = {}, 0
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
            local phys = ((_G._vo_hi * 256) + _G._vo_lo) * 8
            if phys ~= _G._voffset then
                _G._voffset = phys; ev("SCREEN START = physical $%05X", phys)
            end
        end
    elseif off >= 0xFFA0 and off <= 0xFFAF then
        _G._n_mmu = _G._n_mmu + 1
        if off <= 0xFFA7 then _G._mmu0[off - 0xFFA0] = d else _G._mmu1[off - 0xFFA8] = d end
    elseif off >= 0xFFB0 then _G._n_pal = _G._n_pal + 1
    end
    if off >= 0xFF98 and off <= 0xFF9F then _G._n_vid = _G._n_vid + 1 end
end)

local SCREEN_BYTES = 30720

_G._t3 = prog:install_write_tap(0x0000, 0xFEFF, "all", function(off)
    _G._b[off // 4096] = _G._b[off // 4096] + 1
    local tab = ((_G._init1 >= 0) and (_G._init1 & 1) == 1) and _G._mmu1 or _G._mmu0
    local blk = tab[off >> 13]
    local onscreen = false
    if blk == nil or _G._voffset < 0 then
        _G._unres = _G._unres + 1
    else
        local phys = blk * 8192 + (off & 0x1FFF)
        if phys >= _G._voffset and phys < _G._voffset + SCREEN_BYTES then
            _G._scrw = _G._scrw + 1
            onscreen = true
        end
    end
    if off == _G._prev + 1 then
        _G._seq = _G._seq + 1
        _G._run = _G._run + 1
        if _G._run > _G._maxrun then _G._maxrun = _G._run end
        if _G._run == PC_AT_RUN then
            local ok, pc = pcall(function() return cpu.state["PC"].value end)
            if ok then _G._pc[pc] = (_G._pc[pc] or 0) + 1; _G._pcn = _G._pcn + 1 end
            -- ★★★ THE TRIGGER, FINAL FORM: a long run THAT IS LANDING ON THE DISPLAY.
            -- The previous cut used run length alone, and SECTOR COPIES PRODUCE 256-BYTE RUNS
            -- -- 256 >= 128, so all three captures were spent on the game load with
            -- `screen writes: 0`. Run length cannot separate a 256-byte sector copy from a
            -- 160-byte picture row by magnitude alone in a way I trust.
            -- ★ The destination does separate them exactly: the fill writes into
            -- [VOFFSET, VOFFSET+30720), the sector buffer does not. `onscreen` is computed
            -- from the tracked MMU for every write already, so this costs nothing.
            if onscreen then _G._saw_run = true end
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

-- ---- the gate ----------------------------------------------------------------------------
-- ★★★ GATE CONDITIONS, all four stated (L-44). The first attempt used only MIN_FDC and
-- caught the GAME LOAD (51,409 accesses) instead of a room change: 6,877 iterations of
-- `LEAX -$1,X / BNE`, a disk-wait spin, with the boot-time MMU map and the screen at $70000.
local MAX_FDC      = 20000   -- room changes measured 3,820-11,985; the boot load was 51,409
local MAX_CAPTURES = 3       -- ★★★ one wasted arming must not cost the session
local ncap         = 0
local armed      = (m.debugger ~= nil)
local tracing    = false
local trace_end  = 0
local trace_file = TRDIR .. "/fill.tr"    -- reassigned per capture
local trace_meta = nil

local function mmu_string()
    local tab = ((_G._init1 >= 0) and (_G._init1 & 1) == 1) and _G._mmu1 or _G._mmu0
    local t = {}
    for i = 0, 7 do t[#t + 1] = string.format("%02X", tab[i] or 255) end
    return table.concat(t, " ")
end

local function trace_start(f, t, acc)
    ncap = ncap + 1
    trace_file = string.format("%s/fill%d.tr", TRDIR, ncap)
    local ok, err = pcall(function()
        m.debugger:command("trace " .. trace_file .. ",0,noloop")
    end)
    if not ok then w("[f%05d] TRACE START FAILED: %s", f, tostring(err)); return false end
    tracing = true
    trace_end = f + TRACE_FRAMES
    trace_meta = { frame = f, t = t, fdc = acc, mmu = mmu_string(), voff = _G._voffset }
    _G._win_maxrun, _G._win_scrw = 0, 0
    w("[f%05d] t=%.3f  ★★★ TRACE ON -> %s   (disk burst of %d acc just ended)",
      f, t, trace_file, acc)
    w("           MMU at trace start: %s   screen start physical $%05X",
      trace_meta.mmu, _G._voffset)
    return true
end

local function trace_stop(f, t)
    pcall(function() m.debugger:command("trace off,0") end)
    tracing = false
    if ncap >= MAX_CAPTURES then armed = false end
    -- ★★★ report the window's OWN run signature, so the right capture is identifiable
    -- immediately rather than after offline analysis. The picture fill shows ~159; the cel
    -- blitter shows 11.
    w("[f%05d] t=%.3f  ★★★ TRACE %d OFF after %d frames   maxrun in window: %d  screen writes: %d",
      f, t, ncap, TRACE_FRAMES, _G._win_maxrun or -1, _G._win_scrw or -1)
    if (_G._win_maxrun or 0) >= 128 and (_G._win_scrw or 0) > 1000 then
        w("           ★★★ THIS WINDOW CONTAINS THE PICTURE FILL (long run + screen writes).")
    else
        w("           (no long run ONTO THE SCREEN -- not the picture fill; %s)",
          ncap < MAX_CAPTURES and "still armed for another" or "no captures left")
    end
    w("[f%05d] t=%.3f  ★★★ TRACE OFF after %d frames", f, t, TRACE_FRAMES)
    -- ★ report the size here so a failed capture is visible during the run, not afterwards
    local fh = io.open(trace_file, "r")
    if fh then
        local n = 0
        for _ in fh:lines() do n = n + 1 end
        fh:close()
        w("           trace lines: %d", n)
    else
        w("           ★★★ TRACE FILE COULD NOT BE OPENED")
    end
    local mf = io.open(string.format("%s/fill%d.meta", TRDIR, ncap), "w")
    if mf and trace_meta then
        mf:write(string.format(
            "start_frame=%d\nstart_t=%.6f\nframes=%d\ndisk_acc=%d\nmmu=%s\nscreen_phys=%d\n",
            trace_meta.frame, trace_meta.t, TRACE_FRAMES, trace_meta.fdc,
            trace_meta.mmu, trace_meta.voff))
        mf:close()
    end
end

w("sierra_trace: gate = graphics mode + a %d+ byte sequential run LANDING ON THE DISPLAY.", PC_AT_RUN)
w("              Neither the disk nor run length alone -- sector copies run 256 bytes.")
w("              %d frames each, noloop, up to %d captures. ★ WALK THROUGH A FEW ROOMS.",
  TRACE_FRAMES, MAX_CAPTURES)
w("Boot: DOS <ENTER> ... ~25 s ... R <ENTER> ... CTRL+DELETE, then walk between rooms.")

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ AUTO SAVE-STATE AT GAMEPLAY. [Jay, 2026-08-28: "take mame state capture right now so we
-- can just jump back in the game for testing"]
--
-- ★★ Booting to gameplay costs ~60 s of operator time EVERY run: DOS, wait 25 s, capital R,
-- ENTER, CTRL+BREAK. That has now been paid for on every dispatch since T-P0-015, and it is
-- pure overhead on a machine state that is identical each time.
--
-- The state is written ONCE, the first time the machine is demonstrably in the game -- taken
-- as the first confirmed ROOM CHANGE, which is the same evidence the rest of this harness
-- uses, rather than a timer that could fire on a title screen.
-- ★ Reload with:  mame coco3 ... -state agi_ingame
-- ★★ CAVEAT, to be verified before it is relied on: MAME save states restore DEVICE state, and
-- the floppy image must be mounted identically for the FDC to make sense afterwards. The
-- launcher copies the same image to the same path every run, so that holds -- but a restored
-- state has NOT yet been shown to reach a working room change, and until it has, this is a
-- convenience and not a verified shortcut.
local STATE_NAME = os.getenv("SIERRA_STATE") or "agi_ingame"
local state_saved = false
local function save_state_once(f, t)
    if state_saved then return end
    state_saved = true
    local ok, err = pcall(function() m:save(STATE_NAME) end)
    w("[f%05d] t=%.3f  ★★★ SAVE STATE -> %q  ok=%s %s",
      f, t, STATE_NAME, tostring(ok), ok and "" or tostring(err))
    w("           reload with:  -state %s", STATE_NAME)
end

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

    if tracing then
        _G._win_maxrun = math.max(_G._win_maxrun or 0, mr)
        _G._win_scrw   = (_G._win_scrw or 0) + sw
    end
    if tracing and frame >= trace_end then trace_stop(frame, t) end

    -- ★★★ THE GATE, third cut: THE DISK IS NOT THE TRIGGER AT ALL.
    -- Cut 1 keyed on "first disk burst >= 2000" and caught the GAME LOAD (51,409 accesses):
    --     a LEAX/BNE disk-wait spin.
    -- Cut 2 keyed on ordering ("skip the first room change") and skipped the ONLY room change
    --     in the session, then fired on a 4,548-access load that was not a transition:
    --     a 4-byte-wide strip blitter, maxrun 11 against the fill's 159.
    -- Cut 3 keyed on "the instant the disk goes quiet" and burned all three captures inside
    --     half a second of the game LOADING, on three short bursts, screen writes 0.
    -- ★★★ Every one of those was a proxy. The fill has a DIRECT signature and nothing else in
    -- the draw phase comes near it: a sequential run of a FULL SCREEN ROW. PC_AT_RUN is 128,
    -- so _G._saw_run is set only by a run of 128+ bytes -- the cel blitter tops out at 11.
    -- ★ The flag is set inside the write tap; the debugger command is issued HERE, one frame
    -- later, which is affordable because the fill spans ~25 frames [T-P0-017: 152 frames at
    -- exactly 159 across 6 transitions].
    if armed and not tracing and _G._saw_run
       and (_G._vmode >= 0 and (_G._vmode & 0x80) ~= 0) then
        trace_start(frame, t, dsk_start and dsk_start[3] or 0)
    end
    _G._saw_run = false

    if fd > 0 then
        if (not dsk_start) or dsk_quiet >= GAP_FRAMES then dsk_start = { frame, t, 0 } end
        dsk_start[3] = dsk_start[3] + fd
        dsk_end = { frame, t }
        dsk_quiet, draw_lat, settle = 0, 0, 0
    elseif dsk_start then
        dsk_quiet = dsk_quiet + 1
        draw_lat = draw_lat + ch
        if ch == 0 then settle = settle + 1 else settle = 0 end

        if dsk_quiet >= GAP_FRAMES and settle >= SETTLE_FRAMES then
            if dsk_start[3] >= MIN_FDC and draw_lat >= MIN_LAT then
                nroom = nroom + 1
                if armed then
                    -- ★ say why this transition was not traced, rather than leaving the
                    -- operator wondering whether the gate is broken
                    local why = {}
                    if nroom <= MIN_ROOMS then why[#why+1] = "first room change (arming)" end
                    if dsk_start[3] > MAX_FDC then why[#why+1] = "burst too large" end
                    if #why > 0 then
                        w("           (not traced: %s)", table.concat(why, ", "))
                    end
                end
                local disk = dsk_end[2] - dsk_start[2]
                local draw = (t - SETTLE_FRAMES / 59.92) - dsk_end[2]
                w("[f%05d] * ROOM CHANGE %d: disk %.3f s + draw %.3f s  lat=%d/160",
                  frame, nroom, disk, draw, draw_lat)
                save_state_once(frame, t)   -- ★ demonstrably in the game: save the shortcut
            end
            dsk_start, dsk_end = nil, nil
            dsk_quiet, draw_lat, settle = 0, 0, 0
        end
    end

    csv:write(string.format(
        "%d,%.9f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
        frame, t, ch, fd, vo, tot,
        per[0], per[1], per[2], per[3], per[4], per[5], per[6], per[7],
        per[8], per[9], per[10], per[11], per[12], per[13], per[14], per[15],
        nm, np, nv, _G._init0, _G._vmode, _G._vres, _G._border,
        sq, as, ot, mr, lo == 0x10000 and -1 or lo, hi,
        sw, ur, pn, tracing and 1 or 0))
end)

_G._stop = emu.add_machine_stop_notifier(function()
    if tracing then pcall(function() m.debugger:command("trace off,0") end) end
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
