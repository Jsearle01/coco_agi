-- harness/tools/mask_where.lua -- WHERE is the 6809 when CC.I is set? [T-P0-064, AD-138]
--
-- ★★★★★ "86.7% masked" IS NOT A FINDING, IT IS A SYMPTOM WITH NO ADDRESS. vbl_rate.lua measured
-- that the VM arm receives 13% of VBLs (39 of 300) while a spin loop with the identical prologue
-- receives 100% (300 of 300, CC.I 0.0%). So the machine, the GIME setup, HAL_time_init, the $010C
-- vector and hal_vbl_handler are all CORRECT, and something on the VM's path holds the mask.
--
-- ★★★★ A GREP HAS NOW FAILED TO FIND IT THREE TIMES, AND THAT IS THE REASON FOR THIS FILE.
-- Every orcc #$50 in the HAL is pshs cc / puls cc bracketed; HAL_time_frame_count masks for two
-- loads and restores; the VM calls no HAL_time_* routine at all; vp_halted branches back into the
-- loop rather than parking; and build/vm_probe.bin is 41 s NEWER than its source, so AD-90 does
-- not apply. **Reading the source has been tried and has not answered it.**
--
-- ★★★ THIS IS p3b_run.lua's WATCHDOG APPLIED TO A DIFFERENT QUESTION. That one turned "it hangs"
-- into "it hangs HERE" by sampling the PC. The mask is the same shape of problem: a state whose
-- cause is an address. Sample the PC on every frame where CC.I is set, histogram it, and print the
-- top sites with the nearest preceding symbol from the map.
--
-- ★★ THE SYMBOLISATION IS FROM THE MAP, NEVER A LITERAL [P6.3 §3.F.2]. A nearest-symbol lookup
-- reports "sym+offset" and is honest about being approximate: an address between two symbols is
-- attributed to the earlier one, which is right for code and wrong for data, so the raw address is
-- printed alongside and is what a follow-up disassembles.
--
-- usage:  MW_PROG=build/vm_probe.bin MW_MAP=build/vm_probe.map mame ... -autoboot_script <this>

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG = os.getenv("MW_PROG") or "build/vm_probe.bin"
local MAP  = os.getenv("MW_MAP")  or "build/vm_probe.map"
local OUT  = os.getenv("MW_OUT")  or "build/mask_where.txt"
local LOAD = 0x0700
local FRAME_HI, FRAME_LO = 0x10, 0x11

local f = io.open(OUT, "w")
local function w(s, ...) local t = string.format(s, ...); f:write(t .. "\n"); print(t) end

-- ★ Symbols, sorted, for a nearest-preceding lookup.
local syms = {}
do
    local h = io.open(MAP, "r")
    if h then
        for line in h:lines() do
            local nm, v = line:match("^Symbol:%s+(%S+)%s+%b()%s+=%s+(%x+)")
            if nm then syms[#syms + 1] = { name = nm, addr = tonumber(v, 16) } end
        end
        h:close()
    end
    table.sort(syms, function(a, b) return a.addr < b.addr end)
end

local function near(pc)
    local best
    for _, s in ipairs(syms) do
        if s.addr <= pc then best = s else break end
    end
    if not best then return "?" end
    return string.format("%s+%d", best.name, pc - best.addr)
end

local function slurp(p)
    local h = io.open(p, "rb"); if not h then return nil end
    local d = h:read("a"); h:close(); return d
end

local function frames() return prog:read_u8(FRAME_HI) * 256 + prog:read_u8(FRAME_LO) end

local state, t0, f0, n, n0 = "boot", nil, nil, 0, 0
local hist, masked, total = {}, 0, 0

_G._mw = emu.add_machine_frame_notifier(function()
    n = n + 1
    if state == "boot" then
        local ok = false
        for row = 0, 15 do
            local b = 0x0400 + row * 32
            if prog:read_u8(b) == 0x4F and prog:read_u8(b + 1) == 0x4B then ok = true break end
        end
        local pc = cpu.state["PC"].value
        if not (ok and pc >= 0xA7D0 and pc <= 0xA7E0) then return end
        local blob = slurp(PROG)
        if not blob then w("★★★ no program at %s", PROG); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        cpu.state["PC"].value = LOAD
        w("poked %d bytes, PC set (frame %d)", #blob, n)
        state = "settle"
        return
    end
    if state == "settle" then
        if n % 30 ~= 0 then return end
        t0, f0, n0 = m.time:as_double(), frames(), n
        w("counter at t0 : %d", f0)
        state = "measure"
        return
    end
    if state == "measure" then
        total = total + 1
        local pc = cpu.state["PC"].value
        local cc = cpu.state["CC"].value
        -- ★★★★★ THE TRAJECTORY, NOT ONLY THE DESTINATION. The histogram said the CPU parks at ONE
        -- address with a 100% share, which is a crash rather than a busy workload -- and a crash is
        -- identified by the LAST GOOD PC, not by where it lands. Keep every sample until it parks,
        -- then print the run-in. **The address it dies at is in the resource arena and names
        -- nothing; the address it left is in code and names a routine.**
        _G._traj = _G._traj or {}
        if #_G._traj < 60 then
            _G._traj[#_G._traj + 1] = string.format("$%04X %s %s", pc,
                ((cc & 0x10) ~= 0) and "I" or "-", near(pc))
        end
        if (cc & 0x10) ~= 0 then
            masked = masked + 1
            hist[pc] = (hist[pc] or 0) + 1
        end
        local dt = m.time:as_double() - t0
        if dt < 5.0 then return end

        w("elapsed %.4f s   VBL ticks %d   MAME frames %d", dt, frames() - f0, n - n0)
        w("CC.I set : %d of %d samples (%.1f%%)", masked, total, 100.0 * masked / total)
        w("")
        -- ★★★★ THE POINT OF THE FILE: the ADDRESSES, most frequent first.
        local rows = {}
        for pc, c in pairs(hist) do rows[#rows + 1] = { pc = pc, c = c } end
        table.sort(rows, function(a, b) return a.c > b.c end)
        w("%-8s %6s  %6s  %s", "PC", "hits", "share", "nearest preceding symbol")
        for i = 1, math.min(#rows, 15) do
            local r = rows[i]
            w("$%04X    %6d  %5.1f%%  %s", r.pc, r.c, 100.0 * r.c / masked, near(r.pc))
        end
        w("")
        w("distinct masked PCs: %d", #rows)
        w("")
        w("=== PC trajectory, one sample per frame from t0 (the run-in to the park) ===")
        for i, s in ipairs(_G._traj or {}) do w("  %3d  %s", i, s) end
        f:close()
        m:exit()
    end
end)
