-- harness/tools/sierra_readfill.lua -- T-P0-021 / P3.12: READ THE FILL AT $909A.
--
-- OPERATOR-DRIVEN. ★★★ NO INPUT PATH. Launch with -debug -state agi_ingame, walk into a room.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ $909A IS THE FILL, ISOLATED BY DIFFERENCE, NOT BY THRESHOLD.
-- sierra_pcdiff.lua accumulated two PC histograms over writes into the picture buffer
-- ($2000-$5F60, itself derived from the blit's own source pointer):
--        $909A   4,283 samples DURING disk bursts        0 samples otherwise
--        $E95F   6,506 during bursts                54,200 otherwise   <- background
-- ★★ A routine that writes the picture buffer only while a room is loading, and never once in
-- 79,823 other samples, is the picture interpretation. Nothing had to be caught in the act.
--
-- ★ FOUR EARLIER ATTEMPTS FAILED BY TRIGGERING ON A PROXY -- the disk, ordering, timing, run
-- length, write region. THE PC IS NOT A PROXY. Gating a trace on "PC reached $909A" cannot
-- catch a different routine, because it IS the routine.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local OUT   = os.getenv("SIERRA_OUT")   or "build/sierra_readfill"
local TRDIR = os.getenv("SIERRA_TRACE") or
  "C:/Users/jayse/AppData/Local/Temp/claude/c--Projects-coco-agi/cb21c600-0f44-4dc7-b6e0-4da1fd2ac46e/scratchpad/readfill"
local TRACE_FRAMES = tonumber(os.getenv("SIERRA_TRACE_FRAMES") or "8")
local FILL_PC      = tonumber(os.getenv("SIERRA_FILL_PC") or "37018")   -- $909A
local BUF_LO       = tonumber(os.getenv("SIERRA_BUF_LO") or "8192")     -- $2000
local BUF_HI       = tonumber(os.getenv("SIERRA_BUF_HI") or "24416")    -- $5F60
local MAX_CAPTURES = 3
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
os.execute('mkdir "' .. TRDIR:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

if not m.debugger then w("★★★ NO DEBUGGER -- launch with -debug."); return end
pcall(function() m.debugger.execution_state = "run" end)

pcall(function()
    local cs = m.ioport.ports[":ctrl_sel"]
    if cs then for n, f in pairs(cs.fields) do f.user_value = 0 end end
end)

_G._hit, _G._buf_writes = false, 0
_G._t = prog:install_write_tap(BUF_LO, BUF_HI, "buf", function()
    _G._buf_writes = _G._buf_writes + 1
    local ok, pc = pcall(function() return cpu.state["PC"].value end)
    -- ★ the trigger is the PC itself; only a FLAG is set here, the debugger command is issued
    -- from the frame notifier (never from inside a tap).
    if ok and pc == FILL_PC then _G._hit = true end
end)

local ncap, tracing, trace_end, armed = 0, false, 0, true
local win_writes = 0

_G._n = emu.add_machine_frame_notifier(function()
    local bw = _G._buf_writes; _G._buf_writes = 0
    if tracing then
        win_writes = win_writes + bw
        if m.time:as_double() * 59.92 >= trace_end then
            pcall(function() m.debugger:command("trace off,0") end)
            tracing = false
            local fh = io.open(string.format("%s/fill%d.tr", TRDIR, ncap), "r")
            local n = 0
            if fh then for _ in fh:lines() do n = n + 1 end; fh:close() end
            w("★★★ TRACE %d OFF -- %d instructions, %d picture-buffer writes in the window",
              ncap, n, win_writes)
            if ncap >= MAX_CAPTURES then armed = false; w("(no captures left)") end
        end
        return
    end
    if armed and _G._hit then
        ncap = ncap + 1
        local f = string.format("%s/fill%d.tr", TRDIR, ncap)
        local ok, err = pcall(function() m.debugger:command("trace " .. f .. ",0,noloop") end)
        if ok then
            tracing = true
            trace_end = m.time:as_double() * 59.92 + TRACE_FRAMES
            win_writes = 0
            w("★★★ TRACE %d ON at t=%.3f -> %s   (PC $%04X reached)",
              ncap, m.time:as_double(), f, FILL_PC)
        else
            w("trace start failed: %s", tostring(err))
        end
        _G._hit = false
    end
end)

w("sierra_readfill: trace gated on PC $%04X writing $%04X-$%04X. %d frames, up to %d captures.",
  FILL_PC, BUF_LO, BUF_HI, TRACE_FRAMES, MAX_CAPTURES)
w("★ Walk into a room. The PC is the trigger -- it cannot catch a different routine.")

_G._stop = emu.add_machine_stop_notifier(function()
    if tracing then pcall(function() m.debugger:command("trace off,0") end) end
end)
