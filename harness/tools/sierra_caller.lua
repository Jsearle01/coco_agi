-- harness/tools/sierra_caller.lua -- T-P0-020 Part B, second method: FOLLOW THE CODE.
--
-- OPERATOR-DRIVEN, ★★★ NO INPUT PATH. Launch with -state agi_ingame and walk into a room.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ [Jay, 2026-08-28] "does it really matter what is in the buffer if you can determine the
-- code that puts it there? you can deduce what is going there from the code."
--
-- ★★ THREE ATTEMPTS TRIED TO CATCH THE FILL BY FILTERING WRITE TRAFFIC AND ALL THREE CAUGHT
-- THE CEL BLITTER, because the composition buffer below $6000 is written continuously during
-- ordinary play -- 12,000+ bytes every ten frames. No threshold on that region can isolate a
-- once-per-room event inside constant traffic.
--
-- ★★★ BUT THE BLIT AT $E1A7 IS ENTERED WITH ITS PARAMETERS ALREADY SET:
--        $E1A7 LDB <$A1   row length      $E1A9 LDA ,X+   <- X IS THE SOURCE BUFFER
--        $E1B4 DEC <$A0   row count       $E1B8 LDD <$A2  <- stride
-- Whoever set X, <$A0, <$A1 and <$A2 is the code that composed the buffer. A trace window that
-- opens mid-blit cannot see it -- measured: ZERO stores to any of those four variables in a
-- 73,377-instruction capture. The setup happens BEFORE.
--
-- ★ So breakpoint the blit's ENTRY and log the registers and the RETURN ADDRESS. That names
-- the caller in one line, without needing to catch anything in the act.
--        X   -> where the picture buffer actually is
--        Y   -> where on the display it lands
--        B   -> the row length, confirming 160
--        return address -> ★★★ THE CODE TO READ NEXT
--
-- ★★ Idiom, confirmed before use: a BREAKPOINT action's `tracelog` is BRACE-FREE, while a
-- trace command's action is BRACED -- mixing them fails silently. Debugger `printf` is not
-- captured headless, so `tracelog` into an open trace is the way to get the text out.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local OUT   = os.getenv("SIERRA_OUT")   or "build/sierra_caller"
local TRDIR = os.getenv("SIERRA_TRACE") or
  "C:/Users/jayse/AppData/Local/Temp/claude/c--Projects-coco-agi/cb21c600-0f44-4dc7-b6e0-4da1fd2ac46e/scratchpad/caller"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
os.execute('mkdir "' .. TRDIR:gsub("/", "\\") .. '" 2>nul')
local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m   = manager.machine
local cpu = m.devices[":maincpu"]

if not m.debugger then
    w("★★★ NO DEBUGGER -- launch with -debug.")
    return
end
pcall(function() m.debugger.execution_state = "run" end)

pcall(function()
    local cs = m.ioport.ports[":ctrl_sel"]
    if cs then for n, f in pairs(cs.fields) do f.user_value = 0 end end
end)

local BLIT_ENTRY = 0xE1A7
local TRFILE = TRDIR .. "/caller.tr"

-- ★ The tracelog needs an open trace to write into. `trace off` afterwards keeps it small:
-- the breakpoint fires a handful of times, not per instruction.
local ok1, e1 = pcall(function() m.debugger:command("trace " .. TRFILE .. ",0") end)
w("trace open: ok=%s %s", tostring(ok1), e1 and tostring(e1) or "")

-- ★★ s points at the return address only if the blit was reached by JSR/BSR. If it was reached
-- by a jump the word at S is something else -- so BOTH the raw word and the stack pointer are
-- logged, and the report will say which interpretation the evidence supports rather than
-- assuming a call. [L-26]
local ACTION = 'tracelog "BLIT ENTRY x=%04X y=%04X b=%02X u=%04X s=%04X ret?=%04X dp=%02X\\n",' ..
               'x,y,b,u,s,w@(s),dp; go'
local ok2, e2 = pcall(function()
    cpu.debug:bpset(BLIT_ENTRY, nil, ACTION)
end)
w("bpset $%04X: ok=%s %s", BLIT_ENTRY, tostring(ok2), e2 and tostring(e2) or "")
if not ok2 then
    w("★ bpset failed -- falling back to the debugger command form")
    pcall(function()
        m.debugger:command(string.format("bpset %X,1,{%s}", BLIT_ENTRY, ACTION))
    end)
end

w("sierra_caller: breakpoint on the blit's ENTRY, logging its parameters and caller.")
w("★ Launch with -state agi_ingame and walk into a room. Every entry prints one line.")

local frame = 0
_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame == 1800 or frame == 5400 then
        local fh = io.open(TRFILE, "r")
        if fh then
            local n = 0
            for _ in fh:lines() do n = n + 1 end
            fh:close()
            w("[f%05d] trace lines so far: %d", frame, n)
        end
    end
end)

_G._stop = emu.add_machine_stop_notifier(function()
    pcall(function() m.debugger:command("trace off,0") end)
end)
