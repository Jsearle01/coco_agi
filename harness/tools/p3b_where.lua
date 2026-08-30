-- harness/tools/p3b_where.lua -- where does the P3b guest actually go?
--
-- ★★ The integrated probe loaded and never cleared its handshake, so it stopped somewhere
-- between `orcc #$50` and `p3_loop`. A state diff cannot localise that [L-59]; the PC can.
-- ★ Samples PC over a window of frames rather than once, so a spin loop is distinguishable from
-- a crash into unmapped memory: a spin shows two or three repeating addresses, a runaway shows
-- a drifting one.
local PROG = os.getenv("P3B_PROG") or "build/p3b_probe_pk.bin"
local LOAD = 0x2000
local GO   = 0x0020

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local function slurp(p) local f = io.open(p,"rb"); if not f then return nil end
                        local d = f:read("a"); f:close(); return d end

local frame, state, seen, n = 0, "load", {}, 0
_G._w = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end
    -- ★★★★ TWO-STAGE ENTRY, AND THE FIRST STAGE EXISTS TO GET DECB OUT OF THE WAY.
    -- Poking 13 KB over $2000-$52E1 lands on DECB's own workspace while DECB is still running
    -- its idle loop with a 60 Hz IRQ live. It crashed before the PC was ever set: sampled PCs
    -- were $6D46, $C011, $0982, $56B8 -- a runaway across the whole map, settling in ROM.
    -- ★★ Stage 1 pokes FOUR bytes (`orcc #$50 / bra *`) and jumps to them, so interrupts are
    -- masked and nothing is executing out of the region about to be overwritten. Stage 2 then
    -- loads the real image into a machine that is no longer running anything.
    -- ★ Earlier probes org at $0700 with smaller images and survived; this one does not, and the
    -- difference is how much of DECB the image lands on.
    if state == "load" then
        prog:write_u8(LOAD + 0, 0x1A); prog:write_u8(LOAD + 1, 0x50)   -- orcc #$50
        prog:write_u8(LOAD + 2, 0x20); prog:write_u8(LOAD + 3, 0xFE)   -- bra *
        cpu.state["PC"].value = LOAD
        print("stage 1: interrupts masked, DECB parked")
        state = "load2"; return
    end
    if state == "load2" then
        -- ★★★★ PRE-SET THE MMU SLOTS BEFORE THE GUEST ENABLES MMUEN.
        -- HAL_sys_init writes $FF90 (MMUEN=1) and only THEN writes $FFA0..$FFA7 in order. From
        -- the instant MMUEN goes on until $FFAn is written, slot n maps whatever the register
        -- happened to hold -- so code living in slot n vanishes underneath the CPU if DECB left
        -- that register wrong. ★★★ Every earlier probe orgs at $0700, in slot 0, which the
        -- sequence fixes FIRST and which is therefore never exposed. This image spans $2000-$511D
        -- and puts the HAL itself around $4E00, in SLOT 2 -- exposed for two writes.
        -- ★★ Marker $A2 proved it: the guest reached the instruction before `jsr HAL_sys_init`
        -- and never reached the one after.
        -- ★ Setting the slots here is a HARNESS fix and touches no shared HAL file (§2M).
        for i = 0, 7 do prog:write_u8(0xFFA0 + i, 0x38 + i) end
        local b = slurp(PROG)
        for i = 1, #b do prog:write_u8(LOAD + i - 1, b:byte(i)) end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
        print(string.format("stage 2: loaded %d bytes at $%04X", #b, LOAD))
        state = "watch"; return
    end
    n = n + 1
    local pc = cpu.state["PC"].value
    -- ★★ The FIRST few samples matter most: they say whether our code ever ran at all, or
    -- whether control left it before the first instruction. A histogram over 240 frames cannot
    -- distinguish "never started" from "started and escaped".
    if n <= 4 then print(string.format("  frame+%d  PC=$%04X  GO=%d", n, pc, prog:read_u8(GO))) end
    seen[pc] = (seen[pc] or 0) + 1
    if n == 240 then
        print(string.format("marker = $%02X  (A1 entry, A2 stack, A3 after sys_init, A4 after FFDF)", prog:read_u8(0x0021)))
        local list = {}
        for k, v in pairs(seen) do list[#list+1] = { k, v } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        print(string.format("GO = %d after %d frames", prog:read_u8(GO), n))
        print("most-visited PCs:")
        for i = 1, math.min(6, #list) do
            print(string.format("   $%04X  x%d", list[i][1], list[i][2]))
        end
        m:exit()
    end
end)
