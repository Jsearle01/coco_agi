-- harness/tools/p3b_run.lua -- drive the integrated P3b probe: five subsystems, one machine.
--
-- ★★★★ WHAT MAKES THIS DIFFERENT FROM EVERY EARLIER SWEEP. The other harnesses stage what their
-- subsystem needs and drive it directly: pic_sweep pokes a picture, comp_sweep pokes cels and
-- sprite records. **This one stages the GAME and then does nothing but tick.** The picture is
-- fetched by the guest through res_open, the sprites come from the guest's own object table,
-- and the host's only job per cycle is to release the handshake and read state back.
--
-- ★★ So the host cannot accidentally supply anything the interpreter should have produced --
-- which is the property AC-3 and AC-4 need and which a poking harness cannot have.
--
-- ★ Staging is vm_sweep.lua's, unchanged: the volumes into physical blocks, the four DIR tables
-- into the map's DIR region, and the per-volume base table from the build's symbols.

local OUT   = os.getenv("P3B_OUT")   or "build/p3b"
local PROG  = os.getenv("P3B_PROG")  or "build/p3b_probe_pk.bin"
local STAGE = os.getenv("P3B_STAGE") or "build/vm_stage/Kingquest1"
local SYMF  = os.getenv("P3B_SYMBOLS") or "build/p3b/symbols.txt"
local NCYC  = tonumber(os.getenv("P3B_CYCLES") or "60")
local DUMP  = os.getenv("P3B_DUMP")            -- write the planes out for the gate
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD      = 0x2000        -- MAP_CODE
local RES_DIRS  = 0x1000        -- MAP_DIRS
local DIR_STRIDE= 0x0400
local WINDOW    = 0xC000        -- MAP_PHASE_WIN, the volume window in the VM phase
local MMU_SLOT  = 0xFFA6
local FB_BASE   = 0xC000        -- MAP_PHASE_WIN, the framebuffer slice in a draw phase
local PRI_BASE  = 0xA000        -- MAP_PRI_SLICE
local W, H      = 160, 168
local PLANE     = W * H

local ST        = 0x0020        -- MAP_STATUS
local GO, MODE, STATUS, ERR = ST+0, ST+1, ST+2, ST+3
local CYCLE, ROOM, NSPR     = ST+4, ST+6, ST+7
local T_VM, T_MOTION, T_COMP, T_FETCH, T_RENDER = ST+8, ST+12, ST+16, ST+20, ST+24
local REMAPS    = ST+28

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...) local s = string.format(f, ...); logf:write(s.."\n"); logf:flush(); print(s) end
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end
                        local d = f:read("a"); f:close(); return d end

local SYM = {}
do
    local f = io.open(SYMF, "r")
    if f then for line in f:lines() do
        local k, v = line:match("^(%S+)%s+(%x+)$"); if k then SYM[k] = tonumber(v, 16) end
    end f:close() end
end
if not SYM.res_volbase then w("★★★ %s lacks res_volbase", SYMF); return end

local vols = {}
do
    local f = io.open(STAGE .. "/manifest.txt", "r")
    if not f then w("★★★ no manifest at %s", STAGE); return end
    for line in f:lines() do
        local v, b, n = line:match("^vol%s+(%d+)%s+(%d+)%s+(%d+)$")
        if v then vols[#vols+1] = { tonumber(v), tonumber(b), tonumber(n) } end
    end
    f:close()
end

local function stage()
    for _, e in ipairs(vols) do
        local vnr, base = e[1], e[2]
        local data = slurp(STAGE .. string.format("/vol%d.bin", vnr))
        if not data then w("★★★ missing vol%d.bin", vnr); return false end
        local nblk = math.ceil(#data / 0x2000)
        for b = 0, nblk - 1 do
            prog:write_u8(MMU_SLOT, base + b)
            local off = b * 0x2000
            for i = 0, 0x1FFF do
                local c = data:byte(off + i + 1); if c == nil then break end
                prog:write_u8(WINDOW + i, c)
            end
        end
        prog:write_u8(MMU_SLOT, base)
        local got, want = prog:read_u8(WINDOW), data:byte(1)
        w("  vol.%d %7d B -> %2d blocks at %2d; readback $%02X vs $%02X %s",
          vnr, #data, nblk, base, got, want, got == want and "OK" or "★★★ MISMATCH")
        if got ~= want then return false end
        prog:write_u8(SYM.res_volbase + vnr, base)
    end
    for t, name in ipairs({ "logdir", "picdir", "viewdir", "snddir" }) do
        local d = slurp(STAGE .. "/" .. name .. ".bin")
        if d then
            local base = RES_DIRS + (t - 1) * DIR_STRIDE
            for i = 1, #d do prog:write_u8(base + i - 1, d:byte(i)) end
            w("  %-8s %5d B -> $%04X (%d slots)", name, #d, base, math.floor(#d/3))
        end
    end
    prog:write_u8(SYM.res_slicebase, 0); prog:write_u8(SYM.res_slicebase + 1, 0)
    prog:write_u8(SYM.res_curblk, 0xFF)
    return true
end

local function rd16(a) return prog:read_u8(a)*256 + prog:read_u8(a+1) end
local function rd32(a) return prog:read_u8(a)*16777216 + prog:read_u8(a+1)*65536
                            + prog:read_u8(a+2)*256 + prog:read_u8(a+3) end

local n, frame, state = 0, 0, "load"
local t0, tprev
local per = {}

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    -- ★★★★ THE MMU SLOTS MUST BE RIGHT BEFORE THE GUEST ENABLES MMUEN, AND THIS IS NEW.
    -- HAL_sys_init writes $FF90 (MMUEN=1) and only THEN writes $FFA0..$FFA7 in order. Between
    -- those, slot n maps whatever its register held -- so code living in slot n disappears
    -- underneath the CPU if DECB left that register wrong.
    -- ★★★ Every earlier probe orgs at $0700, in slot 0, which the sequence fixes FIRST and which
    -- is therefore never exposed. **The reconciled map puts code at $2000-$5300, spanning slots
    -- 1 and 2, and lands the HAL itself around $4E00 -- in slot 2, exposed for two writes.**
    -- ★★ Diagnosed with progress markers, not a PC histogram: the guest reached the instruction
    -- before `jsr HAL_sys_init` (marker $A2) and never reached the one after [L-59].
    -- ★ A HARNESS fix. It touches no shared HAL file (§2M) and is the host doing what a real
    -- loader would have done before handing over.
    if state == "load" then
        for i = 0, 7 do prog:write_u8(0xFFA0 + i, 0x38 + i) end
        local blob = slurp(PROG)
        if not blob then w("★★★ no program at %s", PROG); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
        w("program %d bytes at $%04X; MMU slots pre-set $38..$3F", #blob, LOAD)
        state = "boot"; return
    end

    if state == "boot" then
        if prog:read_u8(GO) ~= 0 then return end
        w("guest at its gate (frame %d) -- all-RAM live, MMU up", frame)
        if not stage() then m:exit(); return end
        t0 = m.time:as_double(); tprev = t0
        state = "cycle"; return
    end

    -- ★★★ WATCHDOG. A cycle that never clears the handshake is indistinguishable from a slow one
    -- until you look, and this is the first harness where the guest can hang inside its own code
    -- rather than in the driver. Sampling the PC while stuck turns "it hangs" into "it hangs
    -- here", which is the difference between a finding and a shrug [L-59].
    if prog:read_u8(GO) ~= 0 then
        stuck = (stuck or 0) + 1
        if stuck == 1 then spin = {} end
        local pc = cpu.state["PC"].value
        spin[pc] = (spin[pc] or 0) + 1
        if stuck == 240 then
            local l = {}
            for k, v in pairs(spin) do l[#l+1] = {k, v} end
            table.sort(l, function(a, b) return a[2] > b[2] end)
            w("★★★ STUCK in cycle %d after 900 frames -- most-visited PCs:", n)
            for i = 1, math.min(6, #l) do w("     $%04X  x%d", l[i][1], l[i][2]) end
            w("     S=$%04X  U=$%04X  (hw stack base $0800, usable down to $0500;", cpu.state["S"].value, cpu.state["U"].value)
            w("      seed stack $0100-$04FF -- S below $0500 means they collided)")
            w("     status=$%02X (B1 fetched, B2 draw-phase, B3 planes cleared, B4 rendered, B5 closed)", prog:read_u8(STATUS))
            w("     status=$%02X", prog:read_u8(STATUS))
            w("     room %d  sprites %d  err %d  remaps %d",
              prog:read_u8(ROOM), prog:read_u8(NSPR), prog:read_u8(ERR), rd16(REMAPS))
            m:exit()
        end
        return
    end
    stuck = 0

    if state == "cycle" then
        if n > 0 then
            local now = m.time:as_double()
            per[#per+1] = now - tprev
            tprev = now
            if n <= 3 or n == NCYC then
                w("  cycle %3d  %.4f s  room %3d  sprites %2d  remaps %d  err %d",
                  n, per[#per], prog:read_u8(ROOM), prog:read_u8(NSPR),
                  rd16(REMAPS), prog:read_u8(ERR))
            end
        end
        if n >= NCYC then
            local tot = m.time:as_double() - t0
            table.sort(per)
            local med = per[math.floor(#per/2)+1] or 0
            w("")
            w("★ %d cycles in %.4f emulated s", NCYC, tot)
            w("    median %.4f s/cycle = %.2f cycles/second @ 1.789390 MHz", med, 1.0/med)
            w("    mean   %.4f s/cycle = %.2f cycles/second", tot/NCYC, NCYC/tot)
            w("    remaps total %d = %.2f per cycle", rd16(REMAPS), rd16(REMAPS)/NCYC)
            -- ★★★ THE VM'S OWN STATE, READ THROUGH THE BUILD'S SYMBOLS. No guest code is added,
            -- so this costs nothing in a code region that is already at its ceiling -- which is
            -- why halt detection went in the host rather than the probe.
            w("    var0=%d flag0=$%02X  vm_quit=%d vm_badop=$%02X vm_cycle=%d vm_tdelay=%d res_err=%d",
              prog:read_u8(0x0800), prog:read_u8(0x0900),
              prog:read_u8(SYM.vm_quit or 0), prog:read_u8(SYM.vm_badop or 0),
              rd16(SYM.vm_cycle or 0), prog:read_u8(SYM.vm_tdelay or 0),
              prog:read_u8(SYM.res_err or 0))
            w("    final room %d, sprites %d, err %d, status=$%02X",
              prog:read_u8(ROOM), prog:read_u8(NSPR), prog:read_u8(ERR), prog:read_u8(STATUS))
            if DUMP then
                -- ★ the guest's OWN planes. Priority is PACKED, so it is expanded here and the
                -- oracle's copy is never packed [§2O.1].
                local fv = io.open(OUT .. "/guest.visual.bin", "wb")
                local tv = {}
                for i = 0, PLANE-1 do tv[i+1] = string.char(prog:read_u8(FB_BASE + i)) end
                fv:write(table.concat(tv)); fv:close()
                local fp = io.open(OUT .. "/guest.priority.bin", "wb")
                local tp = {}
                for j = 0, (PLANE//2)-1 do
                    local b = prog:read_u8(PRI_BASE + j)
                    tp[#tp+1] = string.char((b >> 4) & 0x0F)
                    tp[#tp+1] = string.char(b & 0x0F)
                end
                fp:write(table.concat(tp)); fp:close()
                w("    planes written to %s", OUT)
            end
            m:exit(); return
        end
        n = n + 1
        prog:write_u8(MODE, 1)
        prog:write_u8(GO, 1)
        return
    end
end)
