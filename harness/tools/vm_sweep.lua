-- harness/tools/vm_sweep.lua -- drive the 6809 VM one cycle per handshake and dump its state.
--
-- ★★★ THE SAMPLE IS TAKEN WHILE THE GUEST IS PARKED, BEFORE THE CYCLE RUNS. The oracle's patch
-- dumps flags+vars at cycle ENTRY, once per interpretCycle(), counted from zero. "Cycle N" has
-- to mean the same thing on both sides or the whole diff shifts by one line and reports the
-- divergence at the wrong place. The probe parks at vm_pace's exit -- after the clock ticks
-- that led to this cycle, before the cycle body -- and that is where these 288 bytes come from.
--
-- ★★ STAGING RUNS AFTER THE GUEST'S BARE-METAL TRANSITION (P1.3's lesson, unchanged): $FFA6
-- does nothing before HAL_sys_init, so a host write to the volume window lands in ROM and the
-- byte counter still reports success. The guest clearing GO is the proof the MMU is live.

local OUT   = os.getenv("VM_OUT")   or "build/vm_sweep"
local PROG  = os.getenv("VM_PROG")  or "build/vm_probe.bin"
local STAGE = os.getenv("VM_STAGE") or "build/vm_stage/Kingquest1"
local SYMF  = os.getenv("VM_SYMBOLS") or "build/vm_stage/symbols.txt"
local NCYC  = tonumber(os.getenv("VM_CYCLES") or "600")
-- ★★ THE TRACE ADDRESSES COME FROM THE BUILD'S SYMBOL TABLE, not from a hex env var typed by
-- hand. Two addresses were already wrong once each in this task ($9300, $9400 -- both in MMU
-- slots the host cannot read), and a hand-set constant cannot be caught by the build.
local VMTR      = os.getenv("VM_TRACE") ~= nil
local VMTR_FROM = tonumber(os.getenv("VM_TRACEFROM") or "0")
local VMTR_LOG  = tonumber(os.getenv("VM_TRACELOGIC") or "0")
local TRACE_AT  = tonumber(os.getenv("VM_TRACECYCLE") or "1")
local WATCHOBJ  = tonumber(os.getenv("VM_WATCHOBJ") or "") -- nil unless asked
local TIMED     = tonumber(os.getenv("VM_TIMED") or "")    -- AC-7: free-run this many cycles
local timed_t0                                              -- set on the first timed frame
local CAL       = tonumber(os.getenv("VM_CAL") or "")      -- clock calibration: N x 160,000 cycles
local cal_t0
-- ★★★ The free-run's own clock measurement, run after the timing bracket closes. 4 blocks =
-- 640,000 cycles ~ 0.36 emulated s, which is 2.5% of a 200-cycle run and buys L-78.
local TIMED_CAL = tonumber(os.getenv("VM_TIMED_CAL") or "4")
local timed_dt, timed_op, timed_h, timed_m, timed_cy
local ROOM      = tonumber(os.getenv("VM_ROOM") or "")     -- P5.3 C1: host-side room jump
local ROOM_AT   = tonumber(os.getenv("VM_ROOM_AT") or "40")
local VMTR_BUF, VMTR_IDX
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD      = 0x0700
local RES_DIRS  = 0x3000        -- vm_probe.s overrides res_core's default map
local DIR_STRIDE= 0x0400
local WINDOW    = 0xC000
local MMU_SLOT  = 0xFFA6
local VM_FLAGS  = 0x4100
local VM_VARS   = 0x4000
local GO, STATUS, BADOP, BADLOGIC, CYCLE = 0x0080, 0x0081, 0x0082, 0x0083, 0x0084
local FREE      = 0x0090                                     -- VP_FREE, the AC-7 free-run counter
local CALADDR   = 0x0092                                     -- VP_CAL, the calibration block count
-- ★★★★ T-P0-060: the scripted input path. VP_FEED and VP_VOCAB_BAD are handshake slots and are
-- declared in vm_probe.s beside the rest of that block; the parser's own addresses (par_vocab,
-- vm_saidn, vm_saidm, vm_fedn) come from the SYMBOL MAP, never from a literal here [P6.3 §3.F.2
-- -- three hard-coded addresses in a diagnostic, every one two bytes stale, printed fpos=33849].
local FEED      = 0x0096                                     -- VP_FEED
local VOCAB_BAD = 0x0097                                     -- VP_VOCAB_BAD, 2 bytes
local INBUF     = 0x6220                                     -- VP_INBUF, 42 B (text.h:170)
local INBUF_MAX = 42
local VOCAB     = 0xE000                                     -- VP_VOCAB
local VOCAB_MAX = 0xFF00 - 0xE000                            -- 7,936 >= 6,828 (SpaceQuest-2)

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- ═══════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ STAMP THE PARK AT THE GUEST'S INSTRUCTION, NOT AT THE HOST'S NEXT FRAME.
-- The host notices a park only when its frame notifier next fires, so an interval closed by
-- reading m.time in the notifier is long by up to one whole frame -- 16.7 ms, 29,880 CPU
-- cycles. Over a 14-second free run that is 0.1% and invisible; over a 0.36-second clock
-- calibration it is 2.6%, and it is exactly why the first run of this calibration reported
-- 1.7432 MHz for a 1.789772 MHz machine.
-- ★★★ A write tap on VP_GO stamps the guest's own `clr VP_GO` -- one-instruction resolution,
-- deterministic, and the same instrument P3b.12 used for the phase brackets. ★ It must be held
-- in _G or MAME collects it and the tap silently stops firing (idioms 31).
local park_t, cal_open, cal_shut
_G._gotap = prog:install_write_tap(GO, GO, "vmgo", function(offset, data, mask)
    if data % 256 == 0 then park_t = m.time:as_double() end
end)
-- ★★★★ AND THE CALIBRATION BRACKET IS STAMPED BY THE GUEST TOO, for a reason the park tap does
-- not cover: on release from the free-run park the guest runs ONE interpret cycle before it
-- reaches the calibration blocks. On KQ1 that is ~120,000 CPU cycles inside a 640,000-cycle
-- interval, and it reported 1.5379 MHz for a 1.789772 MHz machine -- 14% low, and low in the
-- direction that would have read as a missing -DHAL_SYS_FAST_CLOCK if it had been worse.
_G._mktap = prog:install_write_tap(0x0094, 0x0094, "vmmark", function(offset, data, mask)
    local v = data % 256
    if v == 1 then cal_open = m.time:as_double()
    elseif v == 2 then cal_shut = m.time:as_double() end
end)

local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end

-- ── the staging manifest and the build's symbol addresses ──────────────────────────────
local vols = {}
do
    local f = io.open(STAGE .. "/manifest.txt", "r")
    if not f then w("★★★ no manifest at %s -- run vm_stage.py first", STAGE); return end
    for line in f:lines() do
        local v, b, n = line:match("^vol%s+(%d+)%s+(%d+)%s+(%d+)$")
        if v then vols[#vols + 1] = { tonumber(v), tonumber(b), tonumber(n) } end
    end
    f:close()
end

-- ★ Symbols come from the BUILD, never from a copy beside the fixture (§2F). P1.3 lost half a
-- session to a stale symbols.txt that made every fetch report a bad signature.
local SYM = {}
do
    local f = io.open(SYMF, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%S+)%s+(%x+)$")
            if k then SYM[k] = tonumber(v, 16) end
        end
        f:close()
    end
end
if not SYM.res_volbase then w("★★★ %s lacks res_volbase", SYMF); return end
w("symbols from %s: res_volbase $%04X", SYMF, SYM.res_volbase)
if VMTR then
    if not (SYM.vmtr_buf and SYM.vmtr_idx and SYM.vmtr_from) then
        w("★★★ trace requested but the build has no vmtr_* symbols -- assemble with -DVM_TRACE")
        return
    end
    VMTR_BUF, VMTR_IDX = SYM.vmtr_buf, SYM.vmtr_idx
    w("trace: buf $%04X idx $%04X, logic %d, window [%d, %d)",
      VMTR_BUF, VMTR_IDX, VMTR_LOG, VMTR_FROM, VMTR_FROM + 384)
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★ THE SCRIPTED INPUT [T-P0-060 AC-4]. Both legs read THE SAME TWO FILES out of the stage
-- directory -- words.tok and input.txt, written there by vm_stage.py from the game and from
-- vm_input_script.py. ★★★ One producer, two consumers: if the host synthesised its own text
-- here, the reference and the guest could be fed different lines and the diff would report a
-- parser defect. §2O.1's rule, applied to the INPUT rather than to the baseline.
-- ★★ Absent = no parser, and that is every existing gate invocation.
local words = slurp(STAGE .. "/words.tok")
local script = {}
do
    local f = io.open(STAGE .. "/input.txt", "r")
    if f then
        for line in f:lines() do
            if line ~= "" and line:sub(1, 1) ~= "#" then
                local c, t = line:match("^(%d+)%s(.*)$")
                if c then script[tonumber(c)] = t end
            end
        end
        f:close()
    end
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
                local c = data:byte(off + i + 1)
                if c == nil then break end
                prog:write_u8(WINDOW + i, c)
            end
        end
        -- ★ read one byte back through the window before trusting any of it
        prog:write_u8(MMU_SLOT, base)
        local got, want = prog:read_u8(WINDOW), data:byte(1)
        w("  vol.%d %7d bytes -> %2d blocks at %2d; readback $%02X vs $%02X %s",
          vnr, #data, nblk, base, got, want, got == want and "OK" or "★★★ MISMATCH")
        if got ~= want then return false end
        -- the per-volume base, indexed by the DIR entry's volume nibble
        prog:write_u8(SYM.res_volbase + vnr, base)
    end

    for t, name in ipairs({ "logdir", "picdir", "viewdir", "snddir" }) do
        local d = slurp(STAGE .. "/" .. name .. ".bin")
        if d then
            local base = RES_DIRS + (t - 1) * DIR_STRIDE
            for i = 1, #d do prog:write_u8(base + i - 1, d:byte(i)) end
            w("  %-8s %5d bytes -> $%04X  (%d slots)", name, #d, base, math.floor(#d / 3))
        end
    end
    prog:write_u8(SYM.res_slicebase, 0)
    prog:write_u8(SYM.res_slicebase + 1, 0)
    prog:write_u8(SYM.res_curblk, 0xFF)

    -- ═══════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ THE VOCABULARY [T-P0-060]. WORDS.TOK is a RESOURCE: it is staged into a window and
    -- read in place, and no index is built (§2V.2's residency row; parser.s's header).
    -- ★★★★ REFUSE IF THE GUEST'S OWN SELF-TEST FAILED. $E000-$FEFF is above $8000, and
    -- vm_state.s records two tasks spent on a wrong mechanism read out of a HOST readback up
    -- there -- "MAME cannot see it" and "it is not RAM" look identical from here. The guest
    -- writes a walking pattern and reads it back itself; a non-zero VP_VOCAB_BAD means the
    -- window is not usable and staging into it would produce a parser that reads noise and a
    -- divergence that points at parser.s. **A check that cannot refuse is not a check** [§2W].
    if words then
        local vb = prog:read_u8(VOCAB_BAD) * 256 + prog:read_u8(VOCAB_BAD + 1)
        if vb ~= 0 then
            w("★★★ vocabulary window self-test FAILED at $%04X -- the guest cannot hold "
              .. "WORDS.TOK there. NOT staging; the parser would read noise.", vb)
            return false
        end
        if #words > VOCAB_MAX then
            w("★★★ WORDS.TOK is %d bytes, past the %d-byte window", #words, VOCAB_MAX)
            return false
        end
        for i = 1, #words do prog:write_u8(VOCAB + i - 1, words:byte(i)) end
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ READ BACK A SAMPLE, NOT THE FIRST BYTE. The first version compared byte 1 only
        -- and printed "readback $00 vs $00 OK" -- and WORDS.TOK's first byte IS zero (the 'a'
        -- bucket's head offset, high half), so **that check passes on RAM nothing was written
        -- to**. It was written to verify staging and could not fail on the case it was written
        -- for [§2W: an instrument must be shown able to FAIL].
        -- ★★★ Caught by reading my own output rather than by a run going wrong, which is the
        -- cheap way to find this class and the only way that does not cost a task first. The
        -- volume staging above has the same shape and is NOT changed here -- a second change
        -- riding on this one [L-54]; it is reported instead.
        -- ★★ 33 points spread across the file plus the last byte: enough that an all-zero or
        -- unwritten window cannot match a real dictionary, cheap enough to be unconditional.
        local bad, checked = 0, 0
        for k = 0, 32 do
            local off = math.floor((#words - 1) * k / 32)
            checked = checked + 1
            if prog:read_u8(VOCAB + off) ~= words:byte(off + 1) then bad = bad + 1 end
        end
        local nz = 0
        for k = 1, math.min(#words, 64) do if words:byte(k) ~= 0 then nz = nz + 1 end end
        w("  vocabulary %d bytes -> $%04X; window self-test clean; readback %d/%d sample points "
          .. "match (%d non-zero in the first 64) %s",
          #words, VOCAB, checked - bad, checked, nz, bad == 0 and "OK" or "★★★ MISMATCH")
        if bad ~= 0 then return false end
        -- ★★ par_vocab is what makes the parser live. Until it is set the port is inert by
        -- construction and vmtest_said returns false on testSaid's own guard -- which is what
        -- every run without an input script gets, and why the nine-title gate is unmoved.
        prog:write_u8(SYM.par_vocab, math.floor(VOCAB / 256))
        prog:write_u8(SYM.par_vocab + 1, VOCAB % 256)
    end
    if VMTR then
        prog:write_u8(SYM.vmtr_from, math.floor(VMTR_FROM / 256))
        prog:write_u8(SYM.vmtr_from + 1, VMTR_FROM % 256)
        prog:write_u8(SYM.vmtr_logic, VMTR_LOG)
    end
    return true
end

-- ★★★★ THE WIRING'S COVERAGE, FROM THE GUEST'S OWN COUNTERS. vm_stage.py prints the same three
-- numbers for the reference; printing them side by side is what makes "the state diff is clean"
-- evidence ABOUT said() rather than evidence that said() was never reached -- which is exactly
-- what the stub also produced [§2W: an instrument must be shown able to fail].
-- ★ Symbols, not literals. A build without them prints nothing rather than reading $0000.
local function report_parser()
    if not (SYM.vm_saidn and SYM.vm_saidm and SYM.vm_fedn) then return end
    local function u16(a) return prog:read_u8(a) * 256 + prog:read_u8(a + 1) end
    w("    said(): evaluated %d, matched %d;  inputs fed %d   [6809 side]",
      u16(SYM.vm_saidn), u16(SYM.vm_saidm), prog:read_u8(SYM.vm_fedn))
end

local out = io.open(OUT .. "/guest.bin", "wb")
local idx = io.open(OUT .. "/cycles.txt", "w")
idx:write("cycle,status,badop,badlogic\n")

local n, frame, state = 0, 0, "load"
_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    if state == "load" then
        local blob = slurp(PROG)
        if not blob then w("★★★ no program at %s", PROG); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
        w("program %d bytes at $%04X, PC set", #blob, LOAD)
        state = "boot"
        return
    end

    if state == "boot" then
        -- ★★★★★ THE STALL DETECTOR BELONGS HERE TOO, AND THIS IS WHERE IT WAS NEEDED FIRST.
        -- It was added to the "run" state below and the guest hung in BOOT -- so it never fired,
        -- and the gate looked from the outside exactly as it had before: MAME burning CPU,
        -- guest.bin at zero bytes, run.log ending at "PC set". **A detector on the wrong state is
        -- not a detector** [§2W: the instrument must be shown able to fire on the case at hand].
        if prog:read_u8(GO) ~= 0 then
            _G._bstall = (_G._bstall or 0) + 1
            if _G._bstall == 1 then _G._bhist, _G._btraj = {}, {} end
            if _G._bstall > 60 then
                local pc = cpu.state["PC"].value
                _G._bhist[pc] = (_G._bhist[pc] or 0) + 1
                if #_G._btraj < 40 then
                    _G._btraj[#_G._btraj + 1] = string.format("$%04X%s", pc,
                        ((cpu.state["CC"].value & 0x10) ~= 0) and "I" or "-")
                end
            end
            if _G._bstall > 1200 then
                w("★★★ GUEST NEVER REACHED ITS GATE -- VP_GO uncleared for %d frames.", _G._bstall)
                w("    VP_GO=%d VP_STATUS=%d arena_bad=$%04X vocab_bad=$%04X",
                  prog:read_u8(GO), prog:read_u8(STATUS),
                  prog:read_u8(0x008E) * 256 + prog:read_u8(0x008F),
                  prog:read_u8(0x0097) * 256 + prog:read_u8(0x0098))
                local names = {}
                for k, v in pairs(SYM) do names[#names + 1] = { name = k, addr = v } end
                table.sort(names, function(a, b) return a.addr < b.addr end)
                local function near(p)
                    local best
                    for _, s in ipairs(names) do
                        if s.addr <= p then best = s else break end
                    end
                    return best and string.format("%s+%d", best.name, p - best.addr) or "?"
                end
                local rows, tot = {}, 0
                for p, c in pairs(_G._bhist) do rows[#rows + 1] = { pc = p, c = c }; tot = tot + c end
                table.sort(rows, function(a, b) return a.c > b.c end)
                for i = 1, math.min(#rows, 10) do
                    w("    $%04X %6d %5.1f%%  %s", rows[i].pc, rows[i].c,
                      100.0 * rows[i].c / tot, near(rows[i].pc))
                end
                w("    distinct PCs: %d %s", #rows,
                  #rows == 1 and "★ ONE address = a PARK (crash), not a busy loop" or "")
                w("    run-in: %s", table.concat(_G._btraj, " "))
                out:close(); idx:close(); m:exit()
            end
            return
        end
        w("guest reached its gate at frame %d -- MMU live, staging", frame)
        do local ab = prog:read_u8(0x008E)*256 + prog:read_u8(0x008F)
           w("  arena self-test: %s", ab == 0 and "clean -- every byte held its pattern"
             or string.format("★★★ FIRST BAD ADDRESS $%04X", ab)) end
        if not stage() then out:close(); idx:close(); m:exit(); return end
        state = "run"
        return
    end

    -- ═══════════════════════════════════════════════════════════════════════════════════
    -- ★★ AC-7: TIME N CYCLES WITH THE HANDSHAKE OUT OF THE WAY. Through the gate the guest
    -- spins on VP_GO until the host's next frame notifier, so elapsed time per cycle measures
    -- MAME's frame period (16.7 ms) and says nothing about the VM. VP_FREE makes the probe run
    -- N cycles back to back; the emulated clock either side gives the real figure.
    -- ★ Emulated time, not wall time: wall time measures this laptop.
    -- ═══════════════════════════════════════════════════════════════════════════════════
    -- ★★★ CLOCK CALIBRATION AT N BLOCKS, so the fixed overhead can be separated from the clock
    -- instead of being charged to it. Each block is exactly 160,000 CPU cycles; elapsed time is
    -- (N*160000 + overhead)/f. Run at several N and fit -- with three points the two-parameter
    -- fit is over-determined and can be contradicted, which a single measurement never can.
    if CAL then
        if cal_t0 == nil then
            cal_t0 = m.time:as_double()
            prog:write_u8(CALADDR, math.floor(CAL / 256))
            prog:write_u8(CALADDR + 1, CAL % 256)
            prog:write_u8(GO, 1)
            return
        end
        if prog:read_u8(GO) ~= 0 then return end
        local dt = m.time:as_double() - cal_t0
        w("CAL blocks=%d cycles=%d elapsed=%.9f implied_MHz=%.4f",
          CAL, CAL * 160000, dt, (CAL * 160000) / dt / 1e6)
        m:exit()
        return
    end

    if TIMED then
        if timed_t0 == nil then
            timed_t0 = m.time:as_double()
            park_t = nil
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE ROOM JUMP MUST HAPPEN HERE TOO, AND ITS ABSENCE SILENTLY VOIDED AN ARM.
            -- The jump below at `if ROOM and n == ROOM_AT` is keyed to the PACED cycle counter,
            -- and a free-run never advances it -- so VM_ROOM did nothing in a VM_TIMED run and
            -- the probe stayed in attract mode. **P6.10's first sweep reported room 83 and room 1
            -- as 67.802 ms/cycle, opcount 2950, 13.628296 s -- IDENTICAL TO SIX DECIMAL PLACES**,
            -- which is the only reason it was caught: two rooms cannot agree that exactly.
            -- ★★★★ A scaling measurement whose independent variable never moved would have
            -- reported "the cost is flat in object count" -- a clean, plausible, completely false
            -- finding, and one that fits the per-slot loop structure well enough to be believed
            -- [§2W: the arm must be shown to do the thing it is named for].
            -- ★★★ The jump is applied BEFORE the free-run is released, so the whole timed bracket
            -- runs in the target room rather than jumping partway through it.
            if ROOM then
                prog:write_u8(VM_VARS + 0, ROOM)
                local b = prog:read_u8(VM_FLAGS + 0)             -- flag 5 = byte 0, bit 5
                prog:write_u8(VM_FLAGS + 0, b | 0x20)
                w("  ★ room jump BEFORE free-run: var0 <- %d, flag 5 set", ROOM)
            end
            prog:write_u8(FREE, math.floor(TIMED / 256))
            prog:write_u8(FREE + 1, TIMED % 256)
            prog:write_u8(GO, 1)            -- release the park; the free-run follows
            return
        end
        if prog:read_u8(GO) ~= 0 then return end     -- still free-running (or still calibrating)

        -- ═══════════════════════════════════════════════════════════════════════════
        -- ★★★★★ PHASE 2: MEASURE THE CLOCK, IN THIS SESSION, AFTER THE TIMED BRACKET.
        -- This file printed "@ 1.7898 MHz" as a LITERAL for every figure it ever produced --
        -- the same defect AD-100 found in p3b_run.lua, still here [L-78]. A displayed constant
        -- is an assertion, and the one run where it is false is the run nobody catches.
        -- ★★★★ THE CALIBRATION RUNS *AFTER* THE FREE RUN, DELIBERATELY. Putting it first would
        -- move the guest's one handshake init cycle out of the timing bracket and silently
        -- re-base every published free-run figure -- a second change riding on this one [L-54].
        -- The bracket below is byte-for-byte the bracket that produced AD-87 and AD-101.
        if timed_dt == nil then
            timed_dt = (park_t or m.time:as_double()) - timed_t0
            timed_op = prog:read_u8(0x008B) * 256 + prog:read_u8(0x008C)
            -- ★★★★ THE FREE RUN NOW CHECKS THAT IT RAN THE CYCLES IT CLAIMS. vm_cycle is
            -- published at the park alongside vm_opcount, so "21 cycles in 2.0 s" is no longer
            -- an assertion about a loop the host cannot see. ★★★ This is the check AD-102 was
            -- missing in its other half: opcount says how much work, vm_cycle says how many
            -- cycles, and either one alone can be satisfied by a loop that did neither.
            timed_cy = prog:read_u8(CYCLE) * 256 + prog:read_u8(CYCLE + 1)
            if SYM.res_chits and SYM.res_cmiss then
                local function rd16(a) return prog:read_u8(a) * 256 + prog:read_u8(a + 1) end
                timed_h, timed_m = rd16(SYM.res_chits), rd16(SYM.res_cmiss)
            end
            cal_open, cal_shut, park_t = nil, nil, nil
            prog:write_u8(CALADDR, math.floor(TIMED_CAL / 256))
            prog:write_u8(CALADDR + 1, TIMED_CAL % 256)
            prog:write_u8(GO, 1)
            return
        end
        if not (cal_open and cal_shut) then
            w("★★★ CALIBRATION BRACKET DID NOT FIRE -- the marker tap saw open=%s shut=%s. "
              .. "No clock figure is reported rather than a wrong one.",
              tostring(cal_open), tostring(cal_shut))
            m:exit(); return
        end
        local clk = (TIMED_CAL * 160000) / (cal_shut - cal_open)

        local dt = timed_dt
        local cycles = TIMED + 1                     -- the released paced cycle counts too
        -- ★★ THE LOGIC CACHE'S OWN COUNTERS, read from the run that was just timed. A timing
        -- improvement is not evidence that the cache is what improved it; the hit rate is.
        -- ★ Absent from the symbol file on a pre-cache build, so this stays silent there.
        if timed_h then
            local tot = timed_h + timed_m
            w("    cache: hits %d  misses %d  hit-rate %.1f%%", timed_h, timed_m,
              tot > 0 and (100.0 * timed_h / tot) or 0)
        end
        w("clock MEASURED %.6f MHz (%d cycles calibrated, this session)", clk / 1e6,
          TIMED_CAL * 160000)
        if clk < 1.2e6 then
            w("★★★ SLOW CLOCK -- the build is missing -DHAL_SYS_FAST_CLOCK [AD-100]")
        end
        w("AC-7 free-run: %d cycles in %.6f emulated s", cycles, dt)
        w("    %.3f ms/cycle   %.0f CPU cycles/VM cycle   %.1f VM cycles/s",
          1000 * dt / cycles, clk * dt / cycles, cycles / dt)
        -- ★★★★★ opcount IS NOW CUMULATIVE OVER THE WHOLE BRACKET. It was the count from the one
        -- pre-run handshake cycle and did not move when TIMED went 1 -> 20 -> 200; the probe now
        -- publishes vm_opcount at the park. **A commands/cycle figure taken before this fix was
        -- one cycle's commands divided by every cycle** [AD-102].
        w("    opcount=%d  (%.2f commands/cycle)   vm_cycle=%d of %d expected%s",
          timed_op, timed_op / cycles, timed_cy, cycles,
          timed_cy == cycles and "" or "  ★★★ MISMATCH")
        -- ★★★★★ THE MEASURED OBJECT COUNT [P6.10 AC-3]. vm_update_objs sets vm_changecnt to the
        -- number of ACTIVE objects it processed on the last cycle. Printing it makes the scaling
        -- curve's x-axis a measurement rather than a claim about which room holds what -- and it
        -- is the check that a room jump actually landed somewhere with objects in it.
        if SYM.vm_changecnt then
            w("    active objects (vm_changecnt, last cycle) = %d",
              prog:read_u8(SYM.vm_changecnt))
        end
        m:exit()
        return
    end

    -- ═══════════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ THE STALL DETECTOR. The line below waits for the guest to clear VP_GO, and if the
    -- guest never does, this notifier returns forever: MAME burns CPU, guest.bin stays ZERO
    -- BYTES, and run.log's last line is "PC set". **That is what a hung gate looked like from
    -- the outside for thirteen minutes** -- no error, no timeout, no address, nothing to act on.
    -- ★★★★ THE FIX IS AN ADDRESS, NOT A TIMEOUT. A timeout says "it hung"; the histogram below
    -- says WHERE, and this task has already had that distinction cost five measurements: a VBL
    -- rate of 7.79 Hz against 59.92 was read as an interrupt-masking problem in the interpreter's
    -- hot path, and four candidate maskers were chased through the HAL and all four were
    -- innocent. One PC sample settled it -- a single address with a 100% share, which is a park,
    -- not a workload. **A crashed guest and a slow guest produce the same rate** [L-93 candidate
    -- `a-rate-is-not-an-address`].
    -- ★★★ THE TRAJECTORY IS KEPT, NOT ONLY THE DESTINATION. The address a guest dies at is
    -- usually in data and names nothing (the last one resolved to a framebuffer base + 2391);
    -- the address it LEFT is in code and names the routine. So the run-in is printed too.
    -- ★★ It cannot fire on a healthy run: STALL_FRAMES is 4x the worst paced cycle ever
    -- measured here, and the counter resets on every cycle the guest completes.
    if prog:read_u8(GO) ~= 0 then
        _G._stall = (_G._stall or 0) + 1
        if _G._stall == 1 then _G._stall_hist, _G._stall_traj = {}, {} end
        if _G._stall > 60 then                       -- only sample once it looks stuck
            local pc = cpu.state["PC"].value
            _G._stall_hist[pc] = (_G._stall_hist[pc] or 0) + 1
            if #_G._stall_traj < 40 then
                _G._stall_traj[#_G._stall_traj + 1] =
                    string.format("$%04X %s", pc,
                                  ((cpu.state["CC"].value & 0x10) ~= 0) and "I" or "-")
            end
        end
        if _G._stall > 1800 then                     -- ~30 emulated s with no cycle completed
            w("★★★ GUEST STALLED at cycle %d -- VP_GO never cleared for %d frames.", n, _G._stall)
            w("    VP_STATUS=%d badop=$%02X badlogic=%d  vm_cycle=%d",
              prog:read_u8(STATUS), prog:read_u8(BADOP), prog:read_u8(BADLOGIC),
              prog:read_u8(CYCLE) * 256 + prog:read_u8(CYCLE + 1))
            -- ★ nearest preceding symbol, from SYM, so the address names a routine where it can
            local names = {}
            for k, v in pairs(SYM) do names[#names + 1] = { name = k, addr = v } end
            table.sort(names, function(a, b) return a.addr < b.addr end)
            local function near(pc)
                local best
                for _, s in ipairs(names) do
                    if s.addr <= pc then best = s else break end
                end
                return best and string.format("%s+%d", best.name, pc - best.addr) or "?"
            end
            local rows = {}
            for pc, c in pairs(_G._stall_hist) do rows[#rows + 1] = { pc = pc, c = c } end
            table.sort(rows, function(a, b) return a.c > b.c end)
            local tot = 0
            for _, r in ipairs(rows) do tot = tot + r.c end
            w("    %-8s %6s %7s  %s", "PC", "hits", "share", "nearest preceding symbol")
            for i = 1, math.min(#rows, 10) do
                w("    $%04X    %6d  %5.1f%%  %s", rows[i].pc, rows[i].c,
                  100.0 * rows[i].c / tot, near(rows[i].pc))
            end
            w("    distinct PCs while stalled: %d  %s", #rows,
              #rows == 1 and "★ ONE address = a PARK (crash), not a busy loop" or "")
            w("    run-in: %s", table.concat(_G._stall_traj, " "))
            out:close(); idx:close(); m:exit()
        end
        return                                       -- the guest is still in a cycle
    end
    _G._stall = 0

    if n > 0 then
        local st = prog:read_u8(STATUS)
        idx:write(string.format("%d,%d,%d,%d\n", n - 1, st,
                                prog:read_u8(BADOP), prog:read_u8(BADLOGIC)))
        if st ~= 0 then
            -- ★★★★ WITH A SCRIPT FED, A "HALT" MAY BE THE GAME QUITTING. vm_probe.s sets
            -- VP_STATUS from vm_quit as well as from a bad opcode, and a said() branch that
            -- reaches quit is the wiring WORKING [T-P0-060: Kingquest1 runs 600 cycles with no
            -- input and 140 with the script]. badop=0 with quit set is that case; the reference
            -- must stop at the same cycle or vm_diff.py fails on the length.
            w("★★★ guest HALTED at cycle %d: opcode $%02X in logic %d%s",
              n - 1, prog:read_u8(BADOP), prog:read_u8(BADLOGIC),
              (prog:read_u8(BADOP) == 0 and prog:read_u8(SYM.vm_quit or 0) ~= 0)
                and "   ★ badop=0 and quit set -- this is the GAME QUITTING, not a bad opcode"
                or "")
            report_parser()
            w("    codelen=%d ip=%d lastop=$%02X opcount=%d icguard=%d",
              prog:read_u8(0x0086)*256 + prog:read_u8(0x0087),
              prog:read_u8(0x0088)*256 + prog:read_u8(0x0089),
              prog:read_u8(0x008A),
              prog:read_u8(0x008B)*256 + prog:read_u8(0x008C),
              prog:read_u8(0x008D))
            w("    var0=%d var7=%d flag5=%d", prog:read_u8(0x4000), prog:read_u8(0x4007),
              (prog:read_u8(0x4100) >> 5) % 2)
            -- ★★ THE HALT PATH GOT THE SAME FIELDS AS THE CLEAN PATH ONLY AFTER a halt reported
            -- "opcode $F5 in logic 102" while the logic-102 trace was EMPTY -- i.e. nothing in
            -- that logic ever dispatched, so the failure is at BIND time and the opcode number
            -- is stale. res_err and res_depth are the fields that distinguish the two, and the
            -- halt is exactly when they are wanted.
            w("    exitall=%d quit=%d reserr=%d curlogic=%d resdepth=%d restop=%04X",
              prog:read_u8(SYM.vm_exitall or 0), prog:read_u8(SYM.vm_quit or 0),
              prog:read_u8(SYM.res_err or 0), prog:read_u8(SYM.vm_curlogic or 0),
              prog:read_u8(SYM.res_depth or 0),
              (SYM.res_top and prog:read_u8(SYM.res_top)*256+prog:read_u8(SYM.res_top+1)) or 0)
            -- ★ dump the opcode trace on the HALT path too: the halt is exactly when it is
            -- wanted, and the first version only dumped on clean completion.
            if VMTR then
                local f = io.open(OUT .. "/trace.txt", "w")
                local ti = prog:read_u8(VMTR_IDX) * 256 + prog:read_u8(VMTR_IDX + 1)
                -- ★ 4-byte entries: ip_hi, ip_lo, opcode, kind (0 loop / 1 eval / 2 expr-end)
                for i = 0, math.floor(ti / 4) - 1 do
                    f:write(string.format("%5d %02X %d\n",
                        prog:read_u8(VMTR_BUF + i * 4) * 256 + prog:read_u8(VMTR_BUF + i * 4 + 1),
                        prog:read_u8(VMTR_BUF + i * 4 + 2),
                        prog:read_u8(VMTR_BUF + i * 4 + 3)))
                end
                f:close()
                w("trace: %d steps -> %s/trace.txt", math.floor(ti / 4), OUT)
            end
            out:close(); idx:close(); m:exit(); return
        end
    end

    -- ★★ THE TRACE RUN USED TO STOP AFTER ONE CYCLE, which made every divergence past cycle 1
    -- untraceable -- and KQ2's is at cycle 92. VM_TRACECYCLE says which cycle to stop at, so the
    -- window can be aimed at the cycle the state diff actually named instead of at cycle 0.
    -- ★ It still stops rather than running to NCYC: the buffer holds 384 entries and a longer
    -- run would simply fill it earlier in the run than the cycle under investigation.
    if VMTR and n >= TRACE_AT then
        local f = io.open(OUT .. "/trace.txt", "w")
        local idx = prog:read_u8(VMTR_IDX)*256 + prog:read_u8(VMTR_IDX+1)
        for i = 0, math.floor(idx/4) - 1 do
            f:write(string.format("%5d %02X %d\n",
                prog:read_u8(VMTR_BUF+i*4)*256 + prog:read_u8(VMTR_BUF+i*4+1),
                prog:read_u8(VMTR_BUF+i*4+2),
                prog:read_u8(VMTR_BUF+i*4+3)))
        end
        f:close()
        w("trace: %d steps -> %s/trace.txt", math.floor(idx/4), OUT)
        out:close(); idx = nil; m:exit(); return
    end

    if n >= NCYC then
        out:close(); idx:close()
        w("★ %d cycles complete", n)
        report_parser()
        w("    ego x=%d y=%d  var0=%d var109=%d  icguard=%d  resdepth=%d restop=%04X",
          prog:read_u8(0x4240), prog:read_u8(0x4241), prog:read_u8(0x4000),
          prog:read_u8(0x406D), prog:read_u8(SYM.vm_icguard or 0),
          prog:read_u8(SYM.res_depth or 0),
          (SYM.res_top and prog:read_u8(SYM.res_top)*256+prog:read_u8(SYM.res_top+1)) or 0)
        w("    exitall=%d quit=%d reserr=%d", prog:read_u8(SYM.vm_exitall or 0),
          prog:read_u8(SYM.vm_quit or 0), prog:read_u8(SYM.res_err or 0))
        do local cf = io.open(OUT .. "/opseen.txt","w")
           for i=0,255 do cf:write(string.format("%02X %d\n", i, prog:read_u8(0x6400+i))) end
           cf:close()
           -- ★ AC-5 needs BOTH dispatch classes: tests and commands are separate opcode spaces
           -- and test $01 is not command $01. One table each.
           local tf = io.open(OUT .. "/testseen.txt","w")
           for i=0,255 do tf:write(string.format("%02X %d\n", i, prog:read_u8(0x6300+i))) end
           tf:close()
           w("    coverage -> %s/opseen.txt + testseen.txt", OUT) end
        if SYM.vm_seed then
            local s = ""
            for i = 0, 3 do s = s .. string.format("%02X", prog:read_u8(SYM.vm_seed + i)) end
            local ac = ""
            for i = 0, 3 do ac = ac .. string.format("%02X", prog:read_u8(SYM.vm_acc + i)) end
            w("    rng seed = $%s acc = $%s rndmax = %d rndlo = %d divisor = %d", s, ac,
              prog:read_u8(SYM.vm_rndmax or 0), prog:read_u8(SYM.vm_rndlo or 0),
              prog:read_u8(SYM.vm_divisor or 0))
        end
        m:exit()
        return
    end

    if n < 3 then
        w("  cycle %d entry: opcount=%d lastop=$%02X codelen=%d", n,
          prog:read_u8(0x008B)*256 + prog:read_u8(0x008C),
          prog:read_u8(0x008A),
          prog:read_u8(0x0086)*256 + prog:read_u8(0x0087))
        w("               icguard=%d var0=%d", prog:read_u8(0x008D), prog:read_u8(0x4000))
    end

    -- ★★ AN OBJECT WATCH, because the state diff reports VARIABLES and the object table is
    -- where the cause usually is. VM_OBJ moved below $8000 when the arena moved up, so the host
    -- can read it now -- the fields below are the exact inputs update_position works from, in
    -- the same order scratchpad/obj_state.py prints them for the reference. Diffing those two
    -- listings is what turns "var 5 is wrong" into "object 1's direction is wrong".
    if WATCHOBJ then
        local b = 0x4240 + WATCHOBJ * 32
        local function u8(o) return prog:read_u8(b + o) end
        w("  cycle %-3d obj %-3d flags %02X%02X x %-4d y %-4d dir %-2d step %-3d stc %-3d "
          .. "st %-3d ySize %-3d motion %d mv %d,%d mstep %d var6 %d gfx %d",
          n, WATCHOBJ, u8(10), u8(11), u8(0), u8(1), u8(12), u8(13),
          u8(15), u8(14), u8(3), u8(19), u8(26), u8(27), u8(28),
          prog:read_u8(0x4006), prog:read_u8(SYM.vm_gfxmode or 0))
    end

    -- ═══════════════════════════════════════════════════════════════════════════════════
    -- ★★★ THE ROOM JUMP (P5.3 C1) -- HOST-SIDE, NO TARGET CODE.
    --
    -- T-P0-028's compositing sample was attract mode: the ego appeared in 0 of 1,680 frames,
    -- because an AGI game sits in its credits for the whole capture window. The jump is what
    -- gets past that, and on OUR VM it needs nothing added to the 6809 at all.
    --
    -- ★★ WHY IT IS THIS CHEAP: our VM state is 256 variables and 256 flags, flat and
    -- byte-indexed at a known address (VM_VARS $4000, VM_FLAGS $4100, packed LSB-first). AGI
    -- routes a room change through VAR_CURRENT_ROOM (var 0) and FLAG_NEW_ROOM_EXEC (flag 5) --
    -- **which logic.0 already tests every cycle**. So `room <n>` is two host writes: set var 0,
    -- set flag 5, and the game's own logic.0 dispatches the room on its next pass.
    -- ★ That is the whole mechanism. No new opcode, no new probe mode, no 6809 instruction.
    if ROOM and n == ROOM_AT then
        prog:write_u8(VM_VARS + 0, ROOM)
        local b = prog:read_u8(VM_FLAGS + 0)                  -- flag 5 lives in byte 0, bit 5
        prog:write_u8(VM_FLAGS + 0, b | 0x20)
        w("  ★ room jump at cycle %d: var0 <- %d, flag 5 set", n, ROOM)
    end

    -- ★ THE SAMPLE: 32 flag bytes then 256 var bytes, exactly the oracle.s layout.
    local buf = {}
    for i = 0, 31 do buf[#buf + 1] = string.char(prog:read_u8(VM_FLAGS + i)) end
    for i = 0, 255 do buf[#buf + 1] = string.char(prog:read_u8(VM_VARS + i)) end
    out:write(table.concat(buf))

    -- ═══════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ ARM THE FEED ONE PARK EARLY, AND THE OFF-BY-ONE IS DELIBERATE.
    -- This park is where cycle `n` is sampled; the release below runs cycle n's BODY. The guest
    -- then does vm_post_cycle, vm_pace, and THEN checks VP_FEED -- before it parks again for
    -- cycle n+1. So a feed armed here lands before the body of cycle n+1, and cycle n+1's
    -- sampled row carries its ENTERED_CLI.
    -- ★★★★ cycle.py feeds immediately before interpret_cycle() for that cycle, and
    -- interpret_cycle() emits its trace row at the top -- so the reference's row for cycle n+1
    -- carries it too. **"Cycle N" means the same thing on both sides**, which is the invariant
    -- this file's header is about and the one a shifted park already broke once.
    -- ★★ The text is written NUL-terminated and bounded at 42, the oracle's own _prompt[42]
    -- [text.h:170]. A longer line is refused rather than truncated: a truncated line still
    -- parses, into something nobody asked for.
    local feed = script[n + 1]
    if feed then
        if #feed >= INBUF_MAX then
            w("★★★ input for cycle %d is %d chars, past the oracle's %d-byte input line -- "
              .. "NOT fed", n + 1, #feed, INBUF_MAX)
        else
            for i = 1, #feed do prog:write_u8(INBUF + i - 1, feed:byte(i)) end
            prog:write_u8(INBUF + #feed, 0)
            prog:write_u8(FEED, 1)
            -- ★ §2P: the CYCLE and the LENGTH, never the text. It is the game's dictionary.
            w("  ★ input armed for cycle %d (%d chars)", n + 1, #feed)
        end
    end

    n = n + 1
    prog:write_u8(GO, 1)
end)
