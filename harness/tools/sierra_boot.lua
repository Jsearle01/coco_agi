-- harness/tools/sierra_boot.lua -- T-P0-015: bring Sierra's 1988 CoCo3 AGI interpreter up to
-- GAMEPLAY and instrument it, so a ROOM CHANGE can be timed and its disk and render phases
-- separated.
--
-- ★★★ THE BOOT SEQUENCE IS T-P0-004's, VERBATIM, AND IT IS NOT NEGOTIABLE BY REASONING.
-- os9rgb2.lua established it against the real machine and Jay confirmed the gate:
--     f300   post "DOS\r"      DECB hands off to OS-9 (idiom 41a)
--     f2400  the monitor prompt is UP -- /d0/Startup has run by now and is at GETMODE
--     f2460  post "R"          CAPITAL R (idiom 41c)
--     f2580  post "\r"         ENTER, as a SEPARATE post
--
-- ★★ WHAT I GOT WRONG, recorded because the failure mode is subtle. I fired the answer at
-- f900 -- twenty-five seconds before the prompt existed -- and then "improved" it into an
-- event-driven wait for a PINNED PC. ★ THAT IS WORSE, NOT BETTER: PC pins during DISK WAITS
-- as well as at a keyboard prompt, so it triggered at f1510, still far too early. The stray
-- input then landed in the shell, ran /d0/Startup off the end of its input, and OS-9 printed
-- EOF at a repeating prompt.
-- ★★★ I also inferred from `Startup`'s `IF %0=r` that the answer had to be LOWERCASE. That
-- inference was wrong and I acted on it over code that already worked. The timing was the bug.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ STATUS AT THE END OF T-P0-015: THE BOOT HALF WORKS. THE CTRL+LETTER PROBE BELOW DOES
-- NOT, AND MUST NOT BE RE-RUN WHILE AN OPERATOR IS AT THE KEYBOARD.
--
-- ★★ hold() drives ioport_field:set_value(), which is a PERMANENT PROGRAMMATIC OVERRIDE and
-- not a momentary press. Writing defvalue back marks the field released but never hands it
-- back to the input system, so once this script touches CTRL it OWNS CTRL for the session --
-- and movement in this interpreter is CTRL+letter, so a stuck CTRL turns every operator
-- keystroke into a menu command. Three trigger designs failed for that one reason before it
-- was understood; the fault was never the trigger.
--
-- ★★★ AND THE PROBE NEVER WORKED ANYWAY. Twelve CTRL+letter candidates produced no room
-- change, and the cause was not the keys: BOTH :ctrl_sel PORTS DEFAULT TO "Joystick", the
-- interpreter polls the joystick, and every key was arriving correctly on the CoCo3 matrix
-- with nothing to respond to it. Setting both ports to Unconnected fixed movement instantly.
-- ★ The SLOT/CAND tuning below is that dead approach's last state, kept only for the record.
--
-- ★ THE MEASUREMENT IN THE P3.6 REPORT CAME FROM sierra_live.lua -- observe-only, no input
-- path at all, with Jay driving. Use that one.
-- ═════════════════════════════════════════════════════════════════════════════════════════
-- /d0/Startup, read off the disk, for the record -- it runs automatically and launches the
-- interpreter itself, so there is NO `Sierra` command to type:
--     *GETMODE / echo What display are you using? / var.0
--     IF %0=r  montype -r ... ELSE GOTO GETMODE ... / sierra <>>>/term
--
-- ★ Instrumentation added on top (this is the new part):
--     DISK    read+write taps on the FDC at $FF40-$FF4F, counted per frame. The OS-9 RBF
--             driver POLLS, so the count marks WHEN the disk is worked, by density.
--     RENDER  a write tap on $8000-$9FFF, which took 91% of all write traffic in a discovery
--             run and is where this interpreter draws.
--     SCREEN  a 16x10 lattice change-count per frame, as a cross-check that does not depend on
--             having guessed the draw window right.
-- ★ No pixel is interpreted (§3); snapshots are for Jay.

local OUT  = os.getenv("SIERRA_OUT") or "build/sierra"
local SECS = tonumber(os.getenv("SIERRA_SECONDS") or "240")
local SNAP = os.getenv("SIERRA_SNAP")
local WALK = os.getenv("SIERRA_WALK")            -- set to drive the ego after gameplay starts

os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local csv  = io.open(OUT .. "/frames.csv", "w")
csv:write("frame,time_s,changed,fdc,fb_writes,note\n")
local function w(f, ...) local s = string.format(f, ...); logf:write(s .. "\n"); logf:flush() end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens:at(1)
local nk   = m.natkeyboard
nk.in_use = true                                  -- 14b: armed at load

_G._fdc, _G._fb = 0, 0
_G._tw = prog:install_write_tap(0xFF40, 0xFF4F, "fw", function() _G._fdc = _G._fdc + 1 end)
_G._tr = prog:install_read_tap (0xFF40, 0xFF4F, "fr", function() _G._fdc = _G._fdc + 1 end)
-- ★★★ THE DRAW AREA IS $6000-$7FFF, NOT $8000-$9FFF. The first discovery ran during IDLE
-- sprite animation and found $9000 taking 91% -- a small status region. Re-run across a real
-- room change, the map is completely different: $7000-$7FFF 40.1%, $0000-$1FFF 35.4%,
-- $6000-$6FFF 7.5%, $8000-$8FFF 6.8%. ★ Measuring a window discovered under the wrong
-- workload is how a tap ends up watching the wrong thing and reporting it confidently.
-- Both ranges are counted so the two can be compared rather than one replacing the other.
_G._fb2 = 0
_G._tf  = prog:install_write_tap(0x6000, 0x7FFF, "draw", function() _G._fb  = _G._fb  + 1 end)
_G._tf2 = prog:install_write_tap(0x8000, 0x9FFF, "stat", function() _G._fb2 = _G._fb2 + 1 end)

local LAT, prev = {}, {}
for gy = 1, 10 do for gx = 1, 16 do
    LAT[#LAT+1] = { math.floor(640*(gx-.5)/16), math.floor(239*(gy-.5)/10) }
end end
for i = 1, #LAT do prev[i] = -1 end
local function sample()
    local c = 0
    for i = 1, #LAT do
        local p = scr:pixel(LAT[i][1], LAT[i][2]) or 0
        if p ~= prev[i] then c = c + 1; prev[i] = p end
    end
    return c
end

local R3, R6 = m.ioport.ports[":row3"], m.ioport.ports[":row6"]
local ROWS = {}
for _, tg in ipairs({":row0",":row1",":row2",":row3",":row4",":row5",":row6"}) do
    ROWS[#ROWS+1] = m.ioport.ports[tg]
end
local function hold(port, name, on)
    if port then for n, f in pairs(port.fields) do
        if n == name then f:set_value(on and 0 or f.defvalue) end
    end end
end
local function letter(ch)
    for _, p in ipairs(ROWS) do
        if p then for n, _ in pairs(p.fields) do
            if n:sub(1,1) == ch and (#n == 1 or n:sub(2,2) == " ") then return p, n end
        end end
    end
end

local frame, stage, gameplay_at = 0, 0, nil
local held, hold_off = nil, nil

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    local t   = m.time:as_double()
    local ch  = sample()
    local fd  = _G._fdc; _G._fdc = 0
    local fbw = _G._fb;  _G._fb  = 0
    local st  = _G._fb2; _G._fb2 = 0
    local mark = ""

    -- ---- T-P0-004's proven schedule, unchanged -------------------------------------------
    if stage == 0 and frame >= 300 then
        w("[f%05d] posting DOS", frame); nk:post("DOS\r"); mark = "DOS"; stage = 1
    elseif stage == 1 and nk.empty and frame > 360 then
        stage = 2
    elseif stage == 2 and frame >= 2400 then
        w("[f%05d] monitor prompt should be up (PC=$%04X)", frame, cpu.state["PC"].value)
        stage = 3
    elseif stage == 3 and frame >= 2460 then
        w("[f%05d] posting R (capital -- idiom 41c)", frame); nk:post("R"); mark = "R"; stage = 4
    elseif stage == 4 and nk.empty and frame >= 2580 then
        w("[f%05d] posting ENTER (separate post)", frame); nk:post("\r"); mark = "CR"; stage = 5
    elseif stage == 5 and nk.empty and frame >= 3600 then
        w("[f%05d] title should be rendering (PC=$%04X)", frame, cpu.state["PC"].value)
        stage = 6
    elseif stage == 6 and frame >= 5400 then
        w("[f%05d] CTRL+BREAK past the title (41d)", frame)
        hold(R6,"CTRL",true); hold(R6,"BREAK",true); mark = "BREAK"; stage = 7
    elseif stage == 7 and frame >= 5430 then
        hold(R6,"CTRL",false); hold(R6,"BREAK",false)
        w("[f%05d] BREAK released -- GAMEPLAY", frame)
        gameplay_at = frame; mark = "gameplay"; stage = 8
    elseif stage == 8 and WALK and frame >= gameplay_at + 1800 then
        -- ★ Wait 30 s after BREAK before walking: the first room is still loading and
        -- animating until ~f6800, and probing during the load would attribute the load's
        -- traffic to a keypress.
        -- ★★ Movement is CTRL + letter on this interpreter, not the CoCo3 arrow diamond
        -- [Jay, from Nerdly Pleasures / I-16 -- SECONDARY evidence, so the mapping is PROBED
        -- here, not assumed]. Each candidate is HELD for 5 s, which is what it takes for the
        -- ego to cross a room and reach an edge; 1.5 s only twitches it.
        local base = gameplay_at + 1800
        local SLOT = 1500                      -- 1200 held (20 s) + 300 idle
        local CAND = { "m", "j", "k", "i", "u", "n", "h", "l", "e", "s", "d", "x" }
        local ph  = (frame - base) % SLOT
        local idx = (math.floor((frame - base) / SLOT) % #CAND) + 1
        if ph == 0 then
            local pt, n = letter(CAND[idx])
            if pt then hold(R6,"CTRL",true); hold(pt,n,true); held = {pt,n} end
            w("[f%05d] hold CTRL+%s", frame, CAND[idx]); mark = "key:" .. CAND[idx]
        elseif ph == 1200 then
            if held then hold(held[1], held[2], false) end
            hold(R6,"CTRL",false); held = nil
            mark = "release"
        end
    end

    csv:write(string.format("%d,%.9f,%d,%d,%d,%s\n", frame, t, ch, fd, fbw, mark))
    if frame % 600 == 0 then
        w("[f%05d] pc=$%04X chg=%d fdc=%d fb=%d", frame, cpu.state["PC"].value, ch, fd, fbw)
    end
    if SNAP and frame % 1800 == 0 then scr:snapshot() end

    if frame >= SECS * 60 then
        w("[f%05d] done. PC=$%04X", frame, cpu.state["PC"].value)
        if SNAP then scr:snapshot() end
        csv:close(); logf:close(); m:exit()
    end
end)
