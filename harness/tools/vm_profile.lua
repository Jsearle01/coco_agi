-- harness/tools/vm_profile.lua -- WHERE DOES THE VM's CYCLE GO? A PC sampler over the real sweep.
--
-- ★★★★★ IT ADDS NOTHING TO THE GUEST. T-P0-047 may change no code, and the exact per-stage
-- mechanism the project prefers (a write-tap on a phase byte, stamped with total_cycles --
-- pic_probe's since T-P0-012) needs the GUEST to publish that byte. vm_probe.s does not, and
-- adding it would change the very binary the VM gate builds. So attribution here is by SAMPLED
-- PC, which costs the guest nothing and cannot alter what is measured.
--
-- ★★★★ IT DOES NOT REIMPLEMENT THE STAGING. vm_sweep.lua's staging is intricate -- volumes into
-- physical blocks, four DIR tables, per-volume bases from the build's symbols -- and a second
-- copy of it would measure a different program [L-56, and vm_ablate.ps1's own header on the
-- symbols-from-the-wrong-map failure]. This installs a notifier and then `dofile`s vm_sweep.lua
-- UNCHANGED, so the run being profiled is the run the ablation harness performs.
--
-- ★★★ SAMPLED, AND SAID SO. One sample per emulated frame (~60/s). A VM cycle is ~70 ms, so a
-- 200-cycle run yields roughly four samples per cycle and ~850 in total. That is enough for
-- module-level shares and NOT enough for per-symbol claims at the margin; the attributor prints
-- the sample count beside every share so the reader can see which is which [L-41: a ratio is
-- not a cost].
-- ★★ Aliasing is the risk a fixed-rate sampler carries: work periodic with the frame would be
-- over- or under-counted systematically. The guard is external -- two shares in this profile
-- (the pacing floor and the instrumentation) were measured INDEPENDENTLY by ablation, and the
-- profile is only trusted where it reproduces them [AD-105's discipline applied to this tool].
--
-- usage:  VM_PROF_OUT=build/vm_prof/kq1.txt  mame ... -autoboot_script harness/tools/vm_profile.lua
--         (plus every variable vm_sweep.lua itself reads: VM_STAGE, VM_PROG, VM_SYMBOLS, ...)

local OUT = os.getenv("VM_PROF_OUT") or "build/vm_prof.txt"

local m   = manager.machine
local cpu = m.devices[":maincpu"]

os.execute('mkdir "' .. OUT:gsub("/", "\\"):gsub("\\[^\\]*$", "") .. '" 2>nul')

local f = io.open(OUT, "w")
if not f then
    print("★★★ vm_profile: cannot open " .. OUT .. " -- no samples will be written")
else
    local n = 0
    -- ★ A DISTINCT GLOBAL. vm_sweep.lua parks its own notifier in _G._t; anchoring this one
    -- under the same name would let one replace the other and the failure would look like
    -- "the sampler produced nothing" rather than "the sweep stopped running" [the frame-notifier
    -- GC gotcha, mame-idioms-coco3-port.md].
    _G._prof = emu.add_machine_frame_notifier(function()
        local ok, pc = pcall(function() return cpu.state["PC"].value end)
        if not ok or not pc then return end
        f:write(string.format("%04X\n", pc))
        n = n + 1
        -- ★★ Flush periodically rather than at exit. -seconds_to_run terminates the process
        -- without unwinding Lua, so an unflushed buffer is lost -- the same shape as the
        -- oracle's never-closed logs landing as .tmp (scummvm.pin [patches]).
        if n % 64 == 0 then f:flush() end
    end)
    print("vm_profile: sampling PC -> " .. OUT)
end

-- ★★★★★ DELEGATE. Everything below this line is vm_sweep.lua's, run unmodified.
dofile("harness/tools/vm_sweep.lua")
