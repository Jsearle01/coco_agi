-- harness/tools/sierra_gime.lua -- T-P0-016 / P3.7: DOES SIERRA BLANK THE DISPLAY?
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ THE DISPATCH ASKS FOR "THE GIME VIDEO-ENABLE BIT". THERE IS NO SUCH BIT.
-- Checked against the register map before building anything, because tapping a bit that does
-- not exist would produce a confident "no blanking" that means nothing:
--   [ref: GIME-RM §2 Register Map Summary] -- $FF90-$FFBF enumerated; no display-enable
--       register appears anywhere in it.
--   [ref: GIME-RM §3 INIT0]  bits COCO/MMUEN/IEN/FEN/MC3/MC2/MC1/MC0 -- no video enable.
--   [ref: GIME-RM §6 VMODE]  bits BP/BPI/MOCH/H50/LPR2-0                -- no video enable.
--   [ref: GIME-RM §6 VRES]   bits LPF1-0/HRES2-0/CRES1-0                -- no video enable.
--   ★ Corroborated by SockmasterGime.md, which enumerates the same four registers bit by bit.
--   ★★ coco_agi's own docs/ground-truth/ is EMPTY (.gitkeep only); both documents were read
--   from POP3_port's copy. §2G permits it -- reading a reference is read-only use of a sibling.
--
-- ★★★ SO THE QUESTION IS RIGHT AND THE INSTRUMENT IS WRONG. "Blank the display" is a RESULT,
-- and on a GIME there are at least six documented ways to reach it. Tapping one bit would have
-- answered a narrower question than the one asked. This taps EVERY register by which what the
-- screen shows can change -- the same cost as tapping one:
--
--   $FF90  INIT0     bit 7 COCO=1 -> CoCo1/2 mode; the whole screen changes meaning
--   $FF98  VMODE     bit 7 BP=0   -> alphanumeric; a graphics screen becomes text
--   $FF99  VRES      LPF=10       -> [ref: GIME-RM §6] "Reserved"; SockmasterGime.md records
--                                   this as zero/infinite lines -- set during the vertical
--                                   border it yields A SCREEN THAT IS ALL BORDER. ★★ That is
--                                   the closest thing the GIME has to a blank, and it is the
--                                   single most likely mechanism if the answer is yes.
--   $FF9A  BORDER    the colour such a blanked screen would show
--   $FF9C  VSCROLL   $FF9D/$9E VOFFSET, $FF9F HOFFSET -- point the scanner elsewhere
--   $FFA0-$FFAF MMU  ★★ remap the displayed blocks. T-P0-015 §3.10's hypothesis, and the one
--                    thing the previous run was structurally blind to: its write tap covered
--                    $0000-$FEFF and the MMU slots are above it.
--   $FFB0-$FFBF PAL  ★ set all sixteen to one colour and the screen is uniform. A "blank" with
--                    no video bit involved at all, invisible to any tap that watches $FF98/99.
--
-- ★★ Every one of these is write-only, so a write tap is the only way to see any of them.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
--
-- ★★★ THIS SCRIPT DRIVES INPUT AND IS THEREFORE UNATTENDED-ONLY. ioport_field:set_value() is a
-- PERMANENT programmatic override; writing defvalue back never returns the field to the input
-- system. Do not run this with an operator at the keyboard -- it will steal CTRL and every
-- keystroke becomes a menu command. For an operator-driven run use sierra_live.lua, which has
-- no input path at all.
--
-- Output is sierra_rooms.py-compatible (same column names, extra columns appended), so the
-- transitions are found by THE SAME instrument that produced T-P0-015's seven.

local OUT = os.getenv("SIERRA_OUT") or "build/sierra_gime"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local csv  = io.open(OUT .. "/frames.csv", "w")
csv:write("frame,time_s,changed,fdc,voffset,total," ..
          "b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,bA,bB,bC,bD,bE,bF," ..
          "n_init,n_video,n_mmu,n_pal,init0,vmode,vres,border\n")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens:at(1)
local nk   = m.natkeyboard
nk.in_use = true                                  -- 14b: armed at load

-- ─── state ────────────────────────────────────────────────────────────────────────────────
_G._fdc, _G._voff = 0, 0
_G._b = {}; for i = 0, 15 do _G._b[i] = 0 end
_G._n_init, _G._n_video, _G._n_mmu, _G._n_pal = 0, 0, 0, 0
_G._ev = {}                                       -- display-affecting writes, this frame
-- ★ Last known value of each latched register. The GIME powers up with these unknown to us;
-- -1 means "never seen written", which is itself reportable -- a register Sierra never
-- touches cannot be how it blanks.
_G._init0, _G._vmode, _G._vres, _G._border = -1, -1, -1, -1
_G._pal = {}; for i = 0, 15 do _G._pal[i] = -1 end

local function ev(fmt, ...) _G._ev[#_G._ev + 1] = string.format(fmt, ...) end

_G._t1 = prog:install_write_tap(0xFF40, 0xFF4F, "fw", function() _G._fdc = _G._fdc + 1 end)
_G._t2 = prog:install_read_tap (0xFF40, 0xFF4F, "fr", function() _G._fdc = _G._fdc + 1 end)

-- ★★★ THE GIME TAP. One range, $FF90-$FFBF, classified on the way through.
_G._tg = prog:install_write_tap(0xFF90, 0xFFBF, "gime", function(off, data)
    local d = data % 256
    if off <= 0xFF91 then
        _G._n_init = _G._n_init + 1
        if off == 0xFF90 then
            if d ~= _G._init0 then
                ev("INIT0=$%02X%s", d, (d & 0x80) ~= 0 and " COCO=1(!)" or "")
                _G._init0 = d
            end
        end
    elseif off <= 0xFF9F then
        _G._n_video = _G._n_video + 1
        if off == 0xFF98 then
            if d ~= _G._vmode then
                ev("VMODE=$%02X BP=%d", d, (d & 0x80) ~= 0 and 1 or 0); _G._vmode = d
            end
        elseif off == 0xFF99 then
            if d ~= _G._vres then
                local lpf = (d >> 5) & 3
                ev("VRES=$%02X LPF=%d%s", d, lpf, lpf == 2 and " ZERO-LINES(!)" or "")
                _G._vres = d
            end
        elseif off == 0xFF9A then
            if d ~= _G._border then ev("BORDER=$%02X", d); _G._border = d end
        elseif off == 0xFF9D or off == 0xFF9E then
            _G._voff = _G._voff + 1
            ev("VOFFSET $%04X<=$%02X", off, d)
        elseif off == 0xFF9C then ev("VSCROLL=$%02X", d)
        elseif off == 0xFF9F then ev("HOFFSET=$%02X", d)
        end
    elseif off <= 0xFFAF then
        _G._n_mmu = _G._n_mmu + 1                 -- ★ counted, never logged: OS-9 task-switches
    else
        _G._n_pal = _G._n_pal + 1
        local i = off - 0xFFB0
        if d ~= _G._pal[i] then _G._pal[i] = d end
    end
end)

_G._t3 = prog:install_write_tap(0x0000, 0xFEFF, "all", function(off)
    local k = off // 4096
    _G._b[k] = _G._b[k] + 1
end)

-- ★ Both controller ports to Unconnected. Both default to Joystick and the interpreter polls
-- the joystick, so with the default every key arrives on the CoCo3 matrix and nothing responds
-- -- which cost T-P0-015 an entire probe before the cause was found.
pcall(function()
    local cs = m.ioport.ports[":ctrl_sel"]
    if cs then for n, f in pairs(cs.fields) do f.user_value = 0; w("ctrl_sel: %q -> Unconnected", n) end end
end)

local LAT, prev = {}, {}
for gy = 1, 10 do for gx = 1, 16 do
    LAT[#LAT + 1] = { math.floor(640 * (gx - 0.5) / 16), math.floor(239 * (gy - 0.5) / 10) }
end end
for i = 1, #LAT do prev[i] = -1 end

local ROWS = {}
for _, tg in ipairs({":row0",":row1",":row2",":row3",":row4",":row5",":row6"}) do
    ROWS[#ROWS + 1] = m.ioport.ports[tg]
end
local R6 = m.ioport.ports[":row6"]
local function hold(port, name, on)
    if port then for n, f in pairs(port.fields) do
        if n == name then f:set_value(on and 0 or f.defvalue) end
    end end
end
local function findkey(ch)
    for _, p in ipairs(ROWS) do
        if p then for n, _ in pairs(p.fields) do
            if n:sub(1, 1) == ch and (#n == 1 or n:sub(2, 2) == " ") then return p, n end
        end end
    end
end

-- ★★ MOVEMENT CANDIDATES, in order of what the evidence supports.
-- T-P0-015 probed twelve CTRL+letter combinations and got no transition -- but the cause was
-- the JOYSTICK PORTS, not the keys, and the probe was never re-run after that was fixed. So
-- BARE ARROWS are tried first (they reach the machine; measured on :row6) before CTRL+letter.
local MOVES = {
    { "arrows",      { "UP", "DOWN", "LEFT", "RIGHT" },              false },
    { "ctrl-arrows", { "UP", "DOWN", "LEFT", "RIGHT" },              true  },
    -- ★ Field names on the CoCo3 matrix are "h  H", "i  I" ... -- LOWERCASE FIRST. The
    -- first run passed uppercase and every letter reported NOT FOUND, which was a defect in
    -- the probe, not evidence about the keys. Dumped from the running machine, not guessed.
    { "ctrl-hijk",   { "h", "i", "j", "k" },                         true  },
    { "ctrl-uonm",   { "u", "o", "n", "m" },                         true  },
    { "ctrl-wasd",   { "w", "a", "s", "d" },                         true  },
}
local function arrowport(name)
    for _, p in ipairs(ROWS) do
        if p then for n, _ in pairs(p.fields) do
            if n:upper() == name or n:upper() == name .. " (ARROW)" then return p, n end
        end end
    end
end

-- ★★★ THE MOVEMENT SWEEP IS DISARMED BY DEFAULT AND SHOULD STAY THAT WAY.
-- CTRL+letter IS THE MENU SYSTEM, not movement [Jay, tier 1: "your just spamming the menus
-- again"]. The measurement agrees and is unambiguous: each CTRL+letter hold moved 520-568
-- lattice points across ~95 of its 240 frames -- a menu opening and closing -- while the bare
-- arrows moved ~0. ★★ So this sweep cannot produce a room change; it can only churn menus,
-- and it does so on a visible window.
-- ★ T-P0-015 recorded "movement is Ctrl+letter" from documentation [I-16, flagged secondary].
-- ★★★ THAT IS NOW CONTRADICTED BY BOTH TIER-1 OBSERVATION AND MEASUREMENT, and the earlier
-- twelve-candidate probe's failure was never the joystick alone -- the keys were also wrong.
-- Set SIERRA_SWEEP=1 only for an unattended experiment that WANTS menu traffic.
local SWEEP = os.getenv("SIERRA_SWEEP") == "1"
local frame, stage = 0, 0
local held_key, held_ctrl = nil, false
local mi, ki, phase0 = 1, 1, nil
local HOLD, GAPF = 240, 120                      -- 4 s held, 2 s idle -- an ego crosses a room

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
    local ni, nv, nm, np = _G._n_init, _G._n_video, _G._n_mmu, _G._n_pal
    _G._n_init, _G._n_video, _G._n_mmu, _G._n_pal = 0, 0, 0, 0
    local per, tot = {}, 0
    for i = 0, 15 do per[i] = _G._b[i]; tot = tot + per[i]; _G._b[i] = 0 end

    if #_G._ev > 0 then
        w("[f%05d] t=%.3f  GIME: %s", frame, t, table.concat(_G._ev, "  "))
        _G._ev = {}
    end

    -- ---- T-P0-004's proven boot schedule, unchanged -------------------------------------
    -- ★★ Do NOT make this event-driven on a pinned PC: PC pins during DISK WAITS as well as
    -- at a keyboard prompt, and answering early runs Startup off the end of its input.
    if stage == 0 and frame >= 300 then
        w("[f%05d] posting DOS", frame); nk:post("DOS\r"); stage = 1
    elseif stage == 1 and nk.empty and frame > 360 then
        stage = 2
    elseif stage == 2 and frame >= 2460 then
        w("[f%05d] posting R (CAPITAL -- idiom 41c)", frame); nk:post("R"); stage = 3
    elseif stage == 3 and nk.empty and frame >= 2580 then
        w("[f%05d] posting ENTER", frame); nk:post("\r"); stage = 4
    elseif stage == 4 and frame >= 3300 then
        -- ★★★ CTRL+BREAK IS REQUIRED, AND IT IS NOT OPTIONAL POLISH [Jay, tier 1]:
        -- "you have to send ctrl+break after the R+enter when everything is settled to get
        -- into the game proper."  Without it the interpreter sits on its title screen and
        -- NOTHING MOVES -- the first run of this script held eight different movement keys
        -- for four seconds each and the lattice never moved a single point, INCLUDING its
        -- idle baseline. ★★ A completely static lattice is the signature of a machine that
        -- is not in the game at all, not of wrong keys, and I read it as wrong keys.
        -- ★ It is also visible in T-P0-015's own operator log: Jay pressed CTRL, then
        -- BREAK+CTRL, at t=46 s -- immediately after his R and ENTER.
        w("[f%05d] CTRL+BREAK -> into the game proper", frame)
        hold(R6, "CTRL", true); hold(R6, "BREAK", true)
        stage = 5
    elseif stage == 5 and frame >= 3320 then
        hold(R6, "BREAK", false); hold(R6, "CTRL", false)
        w("[f%05d] CTRL+BREAK released", frame)
        stage = 6
    elseif stage == 6 and frame >= 3900 then
        if SWEEP then
            w("[f%05d] starting movement sweep (SIERRA_SWEEP=1) -- THIS CHURNS MENUS", frame)
            phase0 = frame; stage = 7
        else
            w("[f%05d] in the game; movement sweep DISARMED (CTRL+letter is the menu system).",
              frame)
            w("         For a room change use sierra_live.lua with an operator driving.")
            stage = 8
        end
    elseif stage == 7 then
        local ph = (frame - phase0) % (HOLD + GAPF)
        if ph == 0 then
            local set = MOVES[mi]
            local keyname = set[2][ki]
            local p, n
            if set[1] == "arrows" or set[1] == "ctrl-arrows" then p, n = arrowport(keyname)
            else p, n = findkey(keyname) end
            if p then
                if set[3] then hold(R6, "CTRL", true); held_ctrl = true end
                hold(p, n, true); held_key = { p, n }
                w("[f%05d] t=%.1f  MOVE %s: %s%s", frame, t, set[1],
                  set[3] and "CTRL+" or "", n)
            else
                w("[f%05d] MOVE %s: key %q NOT FOUND on the matrix", frame, set[1], keyname)
            end
        elseif ph == HOLD then
            if held_key then hold(held_key[1], held_key[2], false); held_key = nil end
            if held_ctrl then hold(R6, "CTRL", false); held_ctrl = false end
            ki = ki + 1
            if ki > #MOVES[mi][2] then ki = 1; mi = mi + 1
                if mi > #MOVES then mi = 1 end
            end
        end
    end

    csv:write(string.format(
        "%d,%.9f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
        frame, t, ch, fd, vo, tot,
        per[0], per[1], per[2], per[3], per[4], per[5], per[6], per[7],
        per[8], per[9], per[10], per[11], per[12], per[13], per[14], per[15],
        ni, nv, nm, np, _G._init0, _G._vmode, _G._vres, _G._border))

    if frame % 1800 == 0 then
        w("[f%05d] t=%.0fs  INIT0=$%02X VMODE=$%02X VRES=$%02X BORDER=$%02X  mmu/frame~%d",
          frame, t, _G._init0 & 0xFF, _G._vmode & 0xFF, _G._vres & 0xFF, _G._border & 0xFF, nm)
    end
end)

w("sierra_gime: GIME register tap $FF90-$FFBF armed (init/video/MMU/palette).")
w("★ There is no video-enable bit [ref: GIME-RM §2/§3/§6]; every display-affecting register")
w("  is watched instead. UNATTENDED ONLY -- this script drives input.")
