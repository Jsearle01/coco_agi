-- harness/tools/sierra_pcdiff.lua -- T-P0-021 / P3.12: FIND THE FILL BY DIFFERENCE.
--
-- OPERATOR-DRIVEN. ★★★ NO INPUT PATH. Launch with -state agi_ingame, walk through rooms.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ WHY THIS HAS NO CAPTURE BUDGET TO BURN, WHICH IS WHY THE LAST THREE ATTEMPTS FAILED.
--
-- P3.11 tried three times to TRIGGER a trace on writes into the picture buffer, and spent every
-- capture on the cel blitter -- because that buffer receives 12,000+ bytes every ten frames
-- during ordinary play. Any threshold on a continuously-written region catches the continuous
-- writer. There is no threshold that fixes that.
--
-- ★★★ BUT THE TWO ROUTINES DIFFER IN *WHEN*, NOT IN *WHERE*:
--       the cel blitter runs EVERY FRAME, forever
--       the picture fill runs ONLY during a room-change disk burst
-- So do not trigger at all. Accumulate TWO PC histograms over the whole session -- one for
-- writes into the buffer while the disk is working, one for writes into it while it is not --
-- and SUBTRACT. A PC that appears in the burst histogram and is absent from the idle one is the
-- fill, by construction, and nothing has to be caught in the act.
--
-- ★★ This is the "ask what ELSE produces this signal" discipline used as the instrument rather
-- than as a caveat: the background IS the control.
--
-- ★ THE BUFFER IS $2000-$5F60, not "below $6000" -- measured in P3.11 from 11,907 breakpoint
-- records of the blit's own source pointer. [Jay: "you can deduce what is going there from
-- the code."]
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local OUT = os.getenv("SIERRA_OUT") or "build/sierra_pcdiff"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens:at(1)

-- ★ L-44: every threshold stated.
local BUF_LO   = tonumber(os.getenv("SIERRA_BUF_LO") or "8192")    -- $2000
local BUF_HI   = tonumber(os.getenv("SIERRA_BUF_HI") or "24416")   -- $5F60
local SAMPLE   = tonumber(os.getenv("SIERRA_SAMPLE") or "8")       -- PC every Nth in-range write
local IDLE_GAP = 30    -- frames of no FDC activity before a frame counts as "idle"

_G._fdc = 0
_G._nw  = 0
_G._burst = {}   -- PC histogram: writes into the buffer while the disk is working
_G._idle  = {}   -- PC histogram: writes into the buffer while it is not
_G._in_burst = false
_G._n_burst, _G._n_idle = 0, 0

_G._t1 = prog:install_write_tap(0xFF40, 0xFF4F, "fw", function() _G._fdc = _G._fdc + 1 end)
_G._t2 = prog:install_read_tap (0xFF40, 0xFF4F, "fr", function() _G._fdc = _G._fdc + 1 end)

_G._t3 = prog:install_write_tap(BUF_LO, BUF_HI, "buf", function(off)
    _G._nw = _G._nw + 1
    if _G._nw % SAMPLE ~= 0 then return end
    local ok, pc = pcall(function() return cpu.state["PC"].value end)
    if not ok then return end
    if _G._in_burst then
        _G._burst[pc] = (_G._burst[pc] or 0) + 1
        _G._n_burst = _G._n_burst + 1
    else
        _G._idle[pc] = (_G._idle[pc] or 0) + 1
        _G._n_idle = _G._n_idle + 1
    end
end)

pcall(function()
    local cs = m.ioport.ports[":ctrl_sel"]
    if cs then for n, f in pairs(cs.fields) do f.user_value = 0 end end
end)

local LAT, prev = {}, {}
for gy = 1, 10 do for gx = 1, 16 do
    LAT[#LAT+1] = { math.floor(640*(gx-0.5)/16), math.floor(239*(gy-0.5)/10) }
end end
for i = 1, #LAT do prev[i] = -1 end

local frame, quiet, nburst = 0, 999, 0

local function dump(tag)
    local f = io.open(OUT .. "/pcdiff.csv", "w")
    if not f then return end
    f:write("pc,burst,idle\n")
    local all = {}
    for k in pairs(_G._burst) do all[k] = true end
    for k in pairs(_G._idle) do all[k] = true end
    local rows = {}
    for pc in pairs(all) do
        rows[#rows+1] = { pc, _G._burst[pc] or 0, _G._idle[pc] or 0 }
    end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    for _, r in ipairs(rows) do
        f:write(string.format("%d,%d,%d\n", r[1], r[2], r[3]))
    end
    f:close()
    -- ★★ the answer, printed live: PCs that write the buffer ONLY while the disk works
    w("")
    w("=== %s: %d samples in bursts, %d idle, %d disk bursts seen ===",
      tag, _G._n_burst, _G._n_idle, nburst)
    w("%8s %9s %9s   %s", "PC", "in-burst", "idle", "verdict")
    local shown = 0
    for _, r in ipairs(rows) do
        if shown < 14 and r[2] > 0 then
            local v
            if r[3] == 0 then v = "★★★ BURST ONLY -- candidate for the fill"
            elseif r[2] / math.max(r[3], 1) >= 10 then v = "★ 10x+ enriched in bursts"
            else v = "background (the cel blitter and friends)" end
            w("  $%04X %9d %9d   %s", r[1], r[2], r[3], v)
            shown = shown + 1
        end
    end
end

w("sierra_pcdiff: two PC histograms over writes to $%04X-$%04X, sampled 1 in %d.",
  BUF_LO, BUF_HI, SAMPLE)
w("★ No trigger, no capture budget: the background IS the control. Walk through rooms.")

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    local fd = _G._fdc; _G._fdc = 0
    if fd > 0 then
        if quiet >= IDLE_GAP then nburst = nburst + 1 end
        quiet = 0
        _G._in_burst = true
    else
        quiet = quiet + 1
        if quiet >= IDLE_GAP then _G._in_burst = false end
    end
    if frame % 1800 == 0 then dump(string.format("f%05d", frame)) end
end)

_G._stop = emu.add_machine_stop_notifier(function() dump("FINAL") end)
