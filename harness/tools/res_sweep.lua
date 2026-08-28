-- harness/tools/res_sweep.lua -- drive res_core.s on a real CoCo3 and dump what it fetched.
--
-- ★★ THE HOST STAGES, THE GUEST FETCHES. The Lua writes the volume slice into PHYSICAL blocks
-- and pokes the DIR tables, then releases the 6809; the 6809 does the DIR lookup, the header
-- parse, the MMU mapping and the straddling copy. ★ Everything AC-2 gates is on the guest side;
-- the host only supplies bytes and reads results, exactly as pic_sweep.lua does.
--
-- ★★★ STAGING RUNS AFTER THE GUEST'S BARE-METAL TRANSITION, NOT BEFORE IT. The first attempt
-- staged everything up front, while the machine was still in DECB's map: $C000-$DFFF was ROM,
-- $FFA6 did nothing, and the run reported "staged 48472 bytes into 6 blocks" followed by zero
-- fetches. ★★ The MMU is a precondition of the HOST's writes as much as the guest's reads --
-- which is why the order here is: poke the program, run it, wait for its gate, THEN stage.
--
-- ★★★ STAGING WRITES $FFA6 FROM THE HOST. That is the register res_core.s owns, and it is safe
-- only because the guest is parked at its GO gate throughout -- never inside a fetch. Stated
-- because a host and a guest writing the same MMU slot is exactly the contention §2N warns of;
-- res_curblk is set to $FF afterwards so the guest re-maps rather than trusting a stale cache.

local OUT   = os.getenv("RES_OUT")   or "build/res_sweep"
local PROG  = os.getenv("RES_PROG")  or "build/res_probe.bin"
local STAGE = os.getenv("RES_STAGE") or "build/res_stage"   -- written by res_stage.py
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD      = 0x0700
local RES_DIRS  = 0x2000
local DIR_STRIDE= 0x0400
local RES_SLOT  = 0x3000
local WINDOW    = 0xC000
local MMU_SLOT  = 0xFFA6
local REQ_TYPE, REQ_INDEX, GO = 0x0080, 0x0081, 0x0082
local STATUS, RLEN, REMAPS    = 0x0083, 0x0084, 0x0086
local MODE, PVOL, POFFHI, POFF= 0x0088, 0x0089, 0x008A, 0x008B
local PBASE, PDEPTH, PMSGS    = 0x008D, 0x008F, 0x0090
local RMODE  = os.getenv("RES_MODE") or "fetch"
local CENSUS = (RMODE == "census")   -- AC-4: res_find only, every slot
local STACK  = (RMODE == "stack")    -- AC-5: open/close, driven from ops.txt

local TIME = (os.getenv("RES_TIME") == "1")     -- AC-7: cycles per fetch, via a write tap

local logf = io.open(OUT .. "/run.log", "w")
local function w(f, ...)
    local s = string.format(f, ...)
    logf:write(s .. "\n"); logf:flush(); print(s)
end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end

-- ── the work list and the staging manifest, both produced by res_stage.py ──────────────
local manifest = {}
do
    local f = io.open(STAGE .. "/manifest.txt", "r")
    if not f then w("★★★ no manifest at %s/manifest.txt -- run res_stage.py first", STAGE); return end
    for line in f:lines() do
        local k, v = line:match("^(%S+)%s+(.*)$")
        if k then manifest[k] = v end
    end
    f:close()
end
local VOLBASE   = tonumber(manifest["volbase"])
local SLICEBASE = tonumber(manifest["slicebase"])
w("staging: volbase block %d, slicebase 0x%05X, %s resources requested",
  VOLBASE, SLICEBASE, manifest["count"])

-- ★★★ SYMBOLS COME FROM THE BUILD, NEVER FROM A COPY IN THE STAGE DIRECTORY (§2F: one home
-- per fact). res_run.ps1 used to copy symbols.txt into each stage dir; after two probe rebuilds
-- moved res_volbase from $0784 to $07A1, every stage dir still poked the old address, the guest
-- kept res_volbase = 0, mapped block 0, and reported bad-signature on all 336 fetches -- while
-- the staging log said the readback was OK, because the readback does not use the symbol.
local SYMFILE = os.getenv("RES_SYMBOLS") or "build/res_stage/symbols.txt"
local SYM = {}
do
    local f = io.open(SYMFILE, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%S+)%s+(%x+)$")
            if k then SYM[k] = tonumber(v, 16) end
        end
        f:close()
    end
end
if not SYM.res_volbase then w("★★★ %s lacks res_volbase -- run resbuild first", SYMFILE); return end
w("symbols from %s: res_volbase $%04X", SYMFILE, SYM.res_volbase)

-- ★ In stack mode the work list is ops.txt: "<mode> <type> <index>", where mode is the probe's
-- own RP_MODE (2 = open, 3 = close). Everything else uses requests.txt and mode 0 or 1.
local reqs = {}
if STACK then
    for line in io.lines(STAGE .. "/ops.txt") do
        local o, t, i = line:match("^(%d+)%s+(%d+)%s+(%d+)$")
        if o then reqs[#reqs + 1] = { tonumber(t), tonumber(i), tonumber(o) } end
    end
else
    for line in io.lines(STAGE .. "/requests.txt") do
        local t, i = line:match("^(%d+)%s+(%d+)$")
        if t then reqs[#reqs + 1] = { tonumber(t), tonumber(i) } end
    end
end

-- ── stage the volume slice into PHYSICAL blocks, and the DIR tables into RAM ───────────
local function stage()
    local slice = slurp(STAGE .. "/slice.bin")
    if not slice then w("★★★ no slice.bin"); return false end
    local nblk = math.ceil(#slice / 0x2000)
    for b = 0, nblk - 1 do
        prog:write_u8(MMU_SLOT, VOLBASE + b)
        local base = b * 0x2000
        for i = 0, 0x1FFF do
            local c = slice:byte(base + i + 1)
            if c == nil then break end
            prog:write_u8(WINDOW + i, c)
        end
    end
    -- ★ Read one byte back through the window before trusting any of it. The zero-fetch run
    -- looked like a successful stage because nothing ever checked that a write stuck.
    prog:write_u8(MMU_SLOT, VOLBASE)
    local got, want = prog:read_u8(WINDOW), slice:byte(1)
    w("staged %d bytes into %d blocks (%d..%d); readback $%02X vs $%02X %s",
      #slice, nblk, VOLBASE, VOLBASE + nblk - 1, got, want,
      got == want and "OK" or "★★★ MISMATCH -- the window is not RAM")
    if got ~= want then return false end

    for t, name in ipairs({ "logdir", "picdir", "viewdir", "snddir" }) do
        local d = slurp(STAGE .. "/" .. name .. ".bin")
        if d then
            local base = RES_DIRS + (t - 1) * DIR_STRIDE
            for i = 1, #d do prog:write_u8(base + i - 1, d:byte(i)) end
            w("  %-8s %5d bytes -> $%04X  (%d slots)", name, #d, base, math.floor(#d / 3))
        end
    end

    prog:write_u8(SYM.res_volbase, VOLBASE)
    prog:write_u8(SYM.res_slicebase,     (SLICEBASE >> 8) & 0xFF)
    prog:write_u8(SYM.res_slicebase + 1,  SLICEBASE       & 0xFF)
    prog:write_u8(SYM.res_curblk, 0xFF)          -- ★ the host just moved the MMU; invalidate
    return true
end

-- ── drive one fetch per handshake, dumping the bytes ───────────────────────────────────
local out = io.open(OUT .. "/fetched.bin", "wb")
local idx = io.open(OUT .. "/fetched.idx", "w")
idx:write(CENSUS and "type,index,status,vol,offset\n"
       or (STACK and "op,type,index,status,len,base,depth,msgs\n")
       or "type,index,status,len,remaps,cycles\n")

-- ── AC-7: the cost of one fetch, in CPU cycles ────────────────────────────────────────
-- ★★ A FRAME NOTIFIER CANNOT MEASURE THIS. A 10 KB fetch is ~100k cycles, comfortably longer
-- than a frame, but the notifier only observes GO at frame boundaries -- it would quantise every
-- measurement to the frame and report the sampling rate rather than the cost. ★ The tap fires on
-- the guest's own `clr RP_GO`, which is the instruction that ends the fetch.
--
-- ★ The tap is held in a global: MAME collects a tap whose only reference is a local
-- (idioms: the frame-notifier/tap GC gotcha), and a collected tap silently measures nothing.
-- ★★★ MAME 0.281's Lua binding EXPOSES NO CYCLE COUNTER ON mc6809e -- `cpu:total_cycles()`,
-- `totalcycles`, `cycles_running` and `clock` are all nil [idioms 19l, and I called it anyway:
-- the tap threw on every fetch, the guest never wrote a status back, and the run reported "129
-- fetches complete" with status=255 on all of them]. ★★ The working instrument is
-- `manager.machine.time:as_double()` inside the tap: emulated time, one-instruction resolution,
-- and DETERMINISTIC across runs -- which is why one run is a measurement and not a sample.
local t0, secs = nil, {}
local cal = nil
if TIME then
    _G._tap = prog:install_write_tap(GO, GO, "res_go", function(offset, data, mask)
        local now = manager.machine.time:as_double()
        if data == 0 then
            if t0 then secs[#secs + 1] = now - t0; t0 = nil end
        else
            t0 = now
        end
        return data
    end)
end

local n, frame, state = 0, 0, "load"
_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    if state == "load" then                       -- the program, then let it run
        local blob = slurp(PROG)
        if not blob then w("★★★ no program at %s", PROG); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        prog:write_u8(GO, 1)                      -- non-zero: the gate must CLEAR it, not find it
        cpu.state["PC"].value = LOAD
        w("program %d bytes at $%04X, PC set", #blob, LOAD)
        state = "boot"
        return
    end

    if state == "boot" then                       -- ★ the guest clearing GO proves it reached
        if prog:read_u8(GO) ~= 0 then return end   --   the gate, i.e. HAL_sys_init returned
        w("guest reached its gate at frame %d -- MMU is live, staging now", frame)
        if not stage() then out:close(); idx:close(); m:exit(); return end
        state = TIME and "cal" or "run"
        return
    end

    -- ★★ CALIBRATE THE CLOCK BEFORE QUOTING ANY CYCLE FIGURE [idioms 19l]. Mode 4 runs a loop
    -- of exactly 160,000 cycles; dividing by the emulated seconds it took gives the LIVE clock.
    -- ★ If the machine were in SLOW mode every AC-7 number would be 2x wrong and nothing else in
    -- the run would look different, which is what makes this cheap guard worth a handshake.
    if state == "cal" then
        if prog:read_u8(GO) ~= 0 then return end
        -- ★★ DISCARD WHAT THE TAP ALREADY COLLECTED. The boot handshake is a GO 1->0 pair too, so
        -- secs[1] is the time from the program poke to HAL_sys_init returning -- 161 cycles' worth.
        -- Using it as the calibration reported the CoCo3 running at 889 MHz, which is the kind of
        -- arithmetically impossible number that is only cheap to catch because it was printed.
        if not _G._calarmed then _G._calarmed = true; secs = {} end
        if #secs == 0 then
            prog:write_u8(MODE, 4)
            prog:write_u8(GO, 1)
            return
        end
        cal = 160000 / secs[1]
        secs = {}
        w("clock calibration: 160,000 cycles in %.9f s -> %.4f MHz", 160000 / cal, cal / 1e6)
        state = "run"
        return
    end

    if prog:read_u8(GO) ~= 0 then return end       -- the guest is still working

    if n > 0 then                                  -- collect the previous result
        local st  = prog:read_u8(STATUS)
        local len = prog:read_u8(RLEN) * 256 + prog:read_u8(RLEN + 1)
        local rm  = prog:read_u8(REMAPS) * 256 + prog:read_u8(REMAPS + 1)
        local r   = reqs[n]
        if CENSUS then
            -- ★ AC-4 records what the 6809 DECODED, not what it managed to load: the volume
            -- nibble and the 20-bit offset, for every slot including the FF FF FF ones.
            local off = prog:read_u8(POFFHI) * 65536
                      + prog:read_u8(POFF) * 256 + prog:read_u8(POFF + 1)
            idx:write(string.format("%d,%d,%d,%d,%d\n", r[1], r[2], st, prog:read_u8(PVOL), off))
        elseif STACK then
            -- ★★ The bytes are read from the base the GUEST reports, not from a constant. AC-5
            -- is precisely the claim that a resource opened at depth 2 lives somewhere else and
            -- is still correct; reading a fixed address would assume away what is under test.
            local base = prog:read_u8(PBASE) * 256 + prog:read_u8(PBASE + 1)
            idx:write(string.format("%d,%d,%d,%d,%d,%d,%d,%d\n", r[3], r[1], r[2], st, len,
                                    base, prog:read_u8(PDEPTH), prog:read_u8(PMSGS)))
            -- ★ Mode 5 (open + Avis Durgan decode) yields bytes exactly as mode 2 does; dumping
            -- only for mode 2 handed AC-9 a zero-byte buffer and the oracle raised on it.
            if (r[3] == 2 or r[3] == 5) and st == 0 and len > 0 then
                local buf = {}
                for i = 0, len - 1 do buf[#buf + 1] = string.char(prog:read_u8(base + i)) end
                out:write(table.concat(buf))
            end
        else
            idx:write(string.format("%d,%d,%d,%d,%d,%d\n", r[1], r[2], st, len, rm,
                                    (cal and secs[n]) and math.floor(secs[n] * cal + 0.5) or 0))
        end
        if not CENSUS and not STACK and st == 0 and len > 0 then
            local buf = {}
            for i = 0, len - 1 do buf[#buf + 1] = string.char(prog:read_u8(RES_SLOT + i)) end
            out:write(table.concat(buf))
        end
    end

    if n >= #reqs then
        out:close(); idx:close()
        w("★ %d fetches complete", n)
        m:exit()
        return
    end

    n = n + 1
    local r = reqs[n]
    -- ★ r, not reqs[n+1]: n has already been advanced above, so reqs[n+1] is the op AFTER this
    -- one. It ran every operation under its successor's mode and threw at the last element.
    prog:write_u8(MODE, STACK and r[3] or (CENSUS and 1 or 0))
    prog:write_u8(REQ_TYPE, r[1])
    prog:write_u8(REQ_INDEX, r[2])
    prog:write_u8(GO, 1)
end)
