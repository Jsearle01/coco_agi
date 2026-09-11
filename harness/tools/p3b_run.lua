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
-- ★ How long a cycle may take before the watchdog calls it stuck. See the watchdog below for
-- why this is 1800 and not 240: the first cycle renders a room.
local STALL_FRAMES = tonumber(os.getenv("P3B_STALL_FRAMES") or "1800")
local DUMP  = os.getenv("P3B_DUMP")            -- write the planes out for the gate
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')

local LOAD      = 0x2000        -- MAP_CODE
local RES_DIRS  = 0x1000        -- MAP_DIRS
-- ★★★★ 768, matching MAP_DIR_STRIDE and RES_DIR_STRIDE [P6.22]. A v2 DIR is at most 256 entries
-- of 3 bytes because a resource number is a byte, and 66 of 156 v2 titles reach slot 255 -- so
-- 1,024 reserved 256 bytes per type that no game can ever use. ★★ THREE FILES CARRY THIS NUMBER
-- and they must agree; the resource gate is what proves it.
local DIR_STRIDE= 0x0300
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
-- ★★★★★ AC-5's PER-STAGE TIMING. P3_PHASE is write-tapped and stamped with exact emulated time
-- at the instant of the store -- pic_probe's mechanism since T-P0-012, one-instruction
-- resolution, deterministic. The guest's P3_T_* bytes were zeroed every cycle and never written,
-- so the breakdown had no producer; this replaces them rather than pretending they work.
-- ★★ Odd marker = entering a stage, even = leaving. An unpaired marker means a stage did not
-- return, which is reported rather than silently dropped.
local PHASE  = ST+30
local MARK   = {[1]="pace(wait)", [3]="interpret", [5]="sprites", [7]="roomcheck", [9]="composite"}
local stage_total, stage_open, stage_n = {}, nil, {}
local REMAPS    = ST+28

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- ★★★ THE TAP MUST LIVE IN _G OR IT IS GARBAGE-COLLECTED AND SILENTLY STOPS FIRING, which reads
-- as "every stage took no time" rather than as an error [idioms; the same trap pic_sweep.lua
-- carries a warning about].
-- ★★★★★ THE MEASURED CLOCK. Markers 11/12 bracket exactly 160,009 CPU cycles in the guest, so
-- the elapsed emulated time between them GIVES the clock rather than assuming it. This file
-- previously printed "@ 1.789390 MHz" as a constant while the machine ran at 0.894 MHz -- the
-- string stated the one thing it was not checking, and every timing figure was 2.003x wrong.
local CAL_CYCLES = 160009
local cal_t0, CLOCK = nil, nil
-- ★ P3B_HOLD: emulated seconds to keep the finished picture displayed before exiting (AC-1).
local HOLD = tonumber(os.getenv("P3B_HOLD") or "0")
local hold_until = nil

_G._ptap = prog:install_write_tap(PHASE, PHASE, "p3bphase", function(offset, data, mask)
    local v = data % 256
    local t = m.time:as_double()
    if v == 11 then cal_t0 = t; return end
    if v == 12 and cal_t0 then CLOCK = CAL_CYCLES / (t - cal_t0); cal_t0 = nil; return end
    if MARK[v] then
        stage_open = {v, t}
    elseif stage_open and v == stage_open[1] + 1 then
        local name = MARK[stage_open[1]]
        stage_total[name] = (stage_total[name] or 0) + (t - stage_open[2])
        stage_n[name] = (stage_n[name] or 0) + 1
        stage_open = nil
    end
end)

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

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★ T-P0-060: the scripted input, for §4A's eye gate. Same two files as the byte gate.
-- Absent = no parser, which is every p3b run before this task.
-- ★★★★★ FROM THE MAP, NOT AS OFFSETS. I wrote these as ST+32/ST+33 to match the probe, then
-- moved the probe's declarations to +88/+89 to clear a collision -- and this side kept reading
-- +32, which is the renderer's CNT_VERT. The self-test check then read a line counter as an
-- address and refused to stage with "FAILED at $00FF". **The check was right and its input was
-- not**, which is §2W's whole subject, produced twice in one task by the same author.
-- ★★★ P3_FEED and P3_VOCAB_BAD are `equ`s and are in the map like everything else. One home.
-- ★★★★★ P3_INBUF COMES FROM THE MAP. I typed `0x5666` here first, read it back, and it is
-- exactly P6.3 §3.F.2: an INTERIOR address written as a literal. P3_INBUF sits immediately
-- after src/engine/parser.s inside MAP_RESERVED, so it moves whenever the parser or the code
-- region does -- and a stale one stages the input line into the parser's own tables, which
-- presents as a tokeniser defect. ★★ VOCAB and the handshake offsets stay literal because they
-- are DECLARED CONTRACTS -- fixed by the map, not by how big the code grew [idiom 42b].
-- ★★★ AND THE VOCABULARY WINDOW TOO. It used to be $E000 flat; it now starts AFTER the parser
-- and its input buffers, so it is an interior address like the rest and comes from the map.
local INBUF_MAX = 42
local VOCAB, VOCAB_END = nil, nil
local function rd16_early(a) return prog:read_u8(a) * 256 + prog:read_u8(a + 1) end

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

    -- ═══════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ THE VOCABULARY, FOR §4A's EYE GATE [T-P0-060]. This is the probe that has a screen,
    -- so it is the one Jay watches the VM respond on. Same two files as the byte gate --
    -- words.tok and input.txt out of the stage directory, written by vm_stage.py -- so the
    -- thing Jay sees and the thing vm_diff.py compares are fed identically.
    -- ★★★★ REFUSE ON A FAILED SELF-TEST. The guest walks $E000-$FEFF and reports the first
    -- address that did not hold its pattern; staging a dictionary into a window that is not RAM
    -- gives a parser reading noise and a screen that is wrong for a reason nobody would look
    -- for in the harness [§2W: a check that cannot refuse is not a check].
    if words then
        if not (SYM.par_vocab and SYM.P3_INBUF and SYM.P3_FEED and SYM.P3_VOCAB_BAD
                and SYM.P3_VOCAB and SYM.P3_VOCAB_END) then
            w("★★★ the build has no par_vocab/P3_INBUF symbols -- rebuild with --map and add "
              .. "them to the --want list. NOT staging a dictionary from a guessed address.")
            return false
        end
        VOCAB, VOCAB_END = SYM.P3_VOCAB, SYM.P3_VOCAB_END
        local vb = rd16_early(SYM.P3_VOCAB_BAD)
        if vb ~= 0 then
            w("★★★ vocabulary window self-test FAILED at $%04X -- NOT staging the dictionary", vb)
            return false
        end
        if #words > (VOCAB_END - VOCAB) then
            w("★★★ WORDS.TOK is %d bytes, past the %d-byte window", #words, VOCAB_END - VOCAB)
            return false
        end
        for i = 1, #words do prog:write_u8(VOCAB + i - 1, words:byte(i)) end
        -- ★★ A SAMPLE, NOT BYTE 1. WORDS.TOK's first byte is zero (the 'a' bucket's head offset,
        -- high half), so a one-byte readback passes on RAM nothing was written to -- which is
        -- what the first version of this check did in vm_sweep.lua before it was caught.
        local bad = 0
        for k = 0, 32 do
            local off = math.floor((#words - 1) * k / 32)
            if prog:read_u8(VOCAB + off) ~= words:byte(off + 1) then bad = bad + 1 end
        end
        w("  vocabulary %d B -> $%04X; window self-test clean; %d/33 sample points match %s",
          #words, VOCAB, 33 - bad, bad == 0 and "OK" or "★★★ MISMATCH")
        if bad ~= 0 then return false end
        prog:write_u8(SYM.par_vocab, math.floor(VOCAB / 256))
        prog:write_u8(SYM.par_vocab + 1, VOCAB % 256)
        -- ★★★★★ READ IT BACK. The first version printed "the parser is LIVE: par_vocab = $E000"
        -- from the CONSTANT it had just written -- a message asserting what it did rather than
        -- what happened -- and par_vocab read $0000 at the stall forty cycles later. **A log line
        -- that cannot be wrong is not evidence** [§2W.3], and this one was the only thing
        -- standing between "the pointer is set" and forty cycles of looking elsewhere.
        local back = prog:read_u8(SYM.par_vocab) * 256 + prog:read_u8(SYM.par_vocab + 1)
        w("  %s par_vocab written $%04X, reads back $%04X %s", back == VOCAB and "★" or "★★★",
          VOCAB, back,
          back == VOCAB and "-- the parser is LIVE: said() now reads a dictionary."
                         or "★★★ THE WRITE DID NOT STICK -- not staging a parser that cannot work")
        if back ~= VOCAB then return false end
        -- ★★★★★ AND WATCH IT. par_vocab was staged correctly and read back as $0000 at the
        -- stall, so something between staging and the feed writes it -- and a dump that says
        -- "it is zero now" cannot say WHO. A write tap names the PC of the store, which is the
        -- difference between a finding and another round of reading source [P3b.12's pattern,
        -- and the same instrument that settled the palette question].
        -- ★★ Held in _G or MAME collects it and the tap silently stops firing (idiom 31) --
        -- which would read as "nothing wrote it", the most misleading answer available.
        -- ★★ THE TAP RECORDS, IT DOES NOT LOG. Writing to the log file from inside a tap ran the
        -- machine into the ground -- the run ended at cycle 8 with no tap output at all, which
        -- reads as "nothing wrote it" and is the most misleading answer available. A tap fires
        -- on the store, so it must be cheap: append to a table, print it later.
        _G._pv = {}
        _G._pvtap = prog:install_write_tap(SYM.par_vocab, SYM.par_vocab + 1, "parvocab",
            function(offset, data, mask)
                if #_G._pv < 24 then
                    _G._pv[#_G._pv + 1] = { offset, data % 256, cpu.state["PC"].value, n }
                end
            end)
    end
    return true
end

local function rd16(a) return prog:read_u8(a)*256 + prog:read_u8(a+1) end
local function rd32(a) return prog:read_u8(a)*16777216 + prog:read_u8(a+1)*65536
                            + prog:read_u8(a+2)*256 + prog:read_u8(a+3) end

local n, frame, state = 0, 0, "load"
local t0, tprev
local per = {}
local last_timed = -1           -- ★ the last cycle number this file has timed; see below

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ THE BLOCKING MESSAGE BOX, AND HOW A HEADLESS RUN GETS PAST ONE [T-P0-085c].
-- print now BLOCKS inside the opcode until ENTER, ESC, or var 21's timer expires. A headless gate
-- has no one to press a key, so it arms VAR 21 -- **the reference's own auto-close control**, not a
-- harness-only build flag [T-P0-085 §3: the oracle already carried the control we were inventing].
-- ★★★★ THE SAME TECHNIQUE p3b_room.lua USES TO WRITE VAR 0 [AD-99]: the host writes a VM variable
-- through the build's symbols and the guest reads it as its own state. No second code path, so the
-- gate exercises the shipping program.
-- ★★★ RE-ARMED EVERY CYCLE, DELIBERATELY. messageBox zeroes var 21 on exit [text.cpp:411], so an
-- arm written once auto-closes exactly ONE box and every later box hangs. Re-arming is the harness
-- standing in for a player who keeps pressing a key, and it is stated rather than hidden.
-- ★★ VM_VARS is $0800 (the flag/var readout below already reads var 0 there); var 21 is $0815.
local VM_VARS  = 0x0800
local VAR_AUTOCLOSE = VM_VARS + 21
local AUTOCLOSE = tonumber(os.getenv("P3B_VAR21") or "0")
-- ★★★★★ AC-4's INSTRUMENT: the GAME clock across a held box. vm_vms is advanced ONLY by
-- vm_step_clock, so the per-cycle delta is the number of ticks the guest counted -- and a cycle that
-- held a box for var21 * 30 ticks must show a delta that large. **A frozen clock and a box that
-- never closes are the same defect** [vm_text_ops.s], which is what -NoTick demonstrates.
-- ★ 32-bit big-endian; the low half is what moves over a run this short.
local vms_prev, vms_max, vms_max_at = nil, 0, 0

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ THE ROOM JUMP, SO THE BLOCKING BOX CAN BE REACHED AT ALL [T-P0-086 §4B].
-- P6.29c measured that no title executes print from its intro -- NEVER at 3,000 cycles. Every
-- measurement had run in the intro room. **A room jump reaches it in one write pair**: AGI routes
-- a room change through VAR_CURRENT_ROOM (var 0) and FLAG_NEW_ROOM_EXEC (flag 5), and logic.0
-- tests flag 5 every cycle, so the GAME dispatches the room itself [AD-99, T-P0-048 B].
-- ★★★★ Deliberately the same two writes p3b_room.lua:49-51 makes, and the same two
-- print_first_cycle.py makes offline [§2F]. Three callers, one mechanism; if they diverge, the
-- offline confirmation stops predicting the MAME run.
-- ★★★ Confirmed offline before being used here: PoliceQuest1 room 97 is `print.v(v131); return()`
-- -- unconditional, no quit, no unimplemented opcode -- and prints 112 times from cycle 8, the
-- same on both runs.
-- ★★★★★ AND THE JUMP IS VERIFIED TO HAVE LANDED, BOTH WAYS [L-56]. p3b_room.lua's own header
-- records a jump written to the wrong address reading as "the room jump does nothing". Writing it
-- back is not enough on its own -- a write nothing consumes looks identical to a working jump --
-- so flag 5 being CLEARED later is what says logic.0 actually saw it.
local JUMP_ROOM = tonumber(os.getenv("P3B_ROOM") or "0")
local JUMP_AT   = tonumber(os.getenv("P3B_ROOM_AT") or "8")
-- ★★★★★ P3B_SETVAR -- GAME STATE THE ROOM NEEDS, WRITTEN WITH THE JUMP [T-P0-086 §4C].
-- Every room reachable by a cold jump that prints on entry is AGI's ERROR ROOM:
-- `print.v(v17); quit(1); return()`. print.v resolves message number var17 - 1, so with var 17 at
-- its cold value of 0 the index is -1, no message is found, and print returns WITHOUT drawing a
-- box. ★★★★ That is why the first port run reached `quit` (vm_quit=1) with var 21 still armed:
-- **the opcode executed and no box was drawn, which are different facts.**
-- ★★★ Setting var 17 is what the GAME does before sending itself here -- same class of poke as
-- var 0 and flag 5, the game's own state written by the host and acted on by the game [AD-99].
-- format: P3B_SETVAR="17=1" or "17=1,20=3"
local SETVAR = {}
for pair in (os.getenv("P3B_SETVAR") or ""):gmatch("[^,]+") do
    local k, v = pair:match("^%s*(%d+)%s*=%s*(%d+)%s*$")
    if k then SETVAR[#SETVAR+1] = { tonumber(k), tonumber(v) } end
end
local VM_FLAGS  = 0x0900        -- MAP_VM_FLAGS; flag 5 is byte 0, bit 5
local jumped, jump_seen_clear = false, false

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ WAIT FOR DECB'S "OK" PROMPT, NOT FOR A FRAME COUNT. [Jay, T-P0-060]
-- This file poked the image and set PC at FRAME 4 -- while DECB is still booting. The machine
-- is not ready to be taken over until it has finished its own start-up and printed `OK`, and a
-- frame count is a guess at when that happened rather than a reading of whether it has.
-- ★★★★ THE READY SIGNAL IS ON THE SCREEN. Idiom 14f: the VDG text screen is at $0400, 32x16,
-- and SCREEN CODES ARE NOT ASCII -- uppercase $40-$5F is stored as-is, so "OK" is the byte pair
-- $4F,$4B. Scanning for it is a reading of the guest's actual state; `frame < 4` is a hope.
-- ★★★ Same class as idiom 14d, one level along: "POLL for the image, don't settle-and-hope."
-- The poll converts "the machine was not ready" from a mystery downstream into a wait.
-- ★★ Bounded, and the bound is reported: a machine that never prints OK is a broken launch and
-- must say so rather than hanging with no output [§2W -- a wait that cannot fail is not a wait].
-- ★★★★★ TWO INDEPENDENT SIGNALS, AND THE FIRST VERSION HAD ONE THAT FIRED ON GARBAGE.
-- v1 scanned all 512 screen bytes for any adjacent $4F,$4B and reported "at its OK prompt
-- (frame 28)". **The banner is not even on screen until ~frame 60** [measured, this task]: at
-- frame 28 the screen is still uninitialised RAM and a chance $4F $4B is easy to find. Jay,
-- watching: "you still are not getting to the basic prompt". ★★★★ A pattern search over
-- uninitialised memory is not a readiness check, it is a lottery -- and it went green early,
-- which is the direction that hides the problem [§2W].
-- ★★★ SO: the "OK" must be at the START OF A ROW, where DECB prints it, AND the CPU must be
-- sitting in DECB's prompt poll. Idiom 14a records that poll at PC=$A7D7/$D7D5, and this task's
-- own screen probe measured $A7D7 at frame 60 and $A7D5 at frame 300 -- so the range is read
-- from the machine rather than taken from the idiom alone.
-- ★★ AND SUSTAINED. One frame in the right place can be a pass through; three consecutive says
-- the machine is parked there. Cheap, and it is the difference between arriving and passing by.
local OK_TIMEOUT = tonumber(os.getenv("P3B_OK_FRAMES") or "1800")
-- ★ 120 frames = 2 emulated seconds at the throttled rate the eye gate runs at (§2U.2). Long
-- enough to read "OK" off the screen, short enough not to pad every headless run.
local OK_HOLD = tonumber(os.getenv("P3B_OK_HOLD") or "120")
local ok_streak = 0
local function decb_ready()
    local seen = false
    for row = 0, 15 do
        local b = 0x0400 + row * 32
        if prog:read_u8(b) == 0x4F and prog:read_u8(b + 1) == 0x4B then seen = true; break end
    end
    local pc = cpu.state["PC"].value
    local parked = (pc >= 0xA7D0 and pc <= 0xA7E0)
    if seen and parked then ok_streak = ok_streak + 1 else ok_streak = 0 end
    return ok_streak >= 3
end

_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if state == "load" and not _G._p3b_ok then
        if decb_ready() then
            -- ★★★★ HOLD THE PROMPT, THEN BLANK, THEN TAKE OVER [Jay's ruling, T-P0-060].
            -- The point of waiting for OK is that a person can SEE the machine was ready. A
            -- wait that is only in the log proves it to the log. So the boot stays on screen
            -- for P3B_OK_HOLD frames, and only then does the display move to mode 2.
            if _G._p3b_okframe == nil then
                _G._p3b_okframe = frame
                w("DECB is at its OK prompt (frame %d, PC=$%04X, 'OK' at a row start, 3 frames)"
                  .. " -- holding it for %d frames so it can be seen",
                  frame, cpu.state["PC"].value, OK_HOLD)
                return
            end
            if frame - _G._p3b_okframe < OK_HOLD then return end
            _G._p3b_ok = true
            -- ★ p3b_show.lua defines this; p3b_run.lua standalone is headless and defines none.
            if _G._p3b_blank then _G._p3b_blank() end
            w("taking the machine over at frame %d", frame)
        elseif frame > OK_TIMEOUT then
            w("★★★ no OK prompt on the $0400 text screen after %d frames -- the machine never "
              .. "finished booting. NOT poking.", OK_TIMEOUT)
            m:exit(); return
        else
            return
        end
    end

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
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ TWO SEGMENTS, NOT ONE. p3b_probe.s `org`s the parser to $E000 because
        -- MAP_RESERVED is already the decoded-cel buffer, and lwasm --format=raw emits NO
        -- PADDING for an org -- the parser's bytes simply follow the code's in the file. A
        -- single poke at MAP_CODE therefore lands the parser 36 KB below its own symbols.
        -- ★★★★ THE SPLIT COMES FROM THE MAP. P3_CODE_END and P3_PARSER_BASE are `equ`s; using
        -- them here means the two sides cannot disagree about where the seam is, which is the
        -- same rule that put P3_INBUF in the symbol list rather than in a literal.
        -- ★★★ Guarded: a build without the parser (no P3_PARSER_BASE) pokes one segment exactly
        -- as before, so this file still drives the pre-parser p3b unchanged.
        local codelen = #blob
        if SYM.P3_CODE_END and SYM.P3_PARSER_BASE then
            codelen = SYM.P3_CODE_END - LOAD
            if codelen < 0 or codelen > #blob then
                w("★★★ P3_CODE_END $%04X is not inside the %d-byte image -- stale map?",
                  SYM.P3_CODE_END, #blob)
                m:exit(); return
            end
        end
        for i = 1, codelen do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        if codelen < #blob then
            for i = codelen + 1, #blob do
                prog:write_u8(SYM.P3_PARSER_BASE + (i - codelen) - 1, blob:byte(i))
            end
            w("program %d bytes: %d at $%04X + %d at $%04X (the parser, org'd)",
              #blob, codelen, LOAD, #blob - codelen, SYM.P3_PARSER_BASE)
        else
            w("program %d bytes at $%04X; MMU slots pre-set $38..$3F", #blob, LOAD)
        end
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ THE FONT, STAGED INTO P3_FONT [T-P0-084d §5C]. text.s reaches every glyph through
        -- txt_font, which the probe points at P3_FONT -- the top of MAP_RESERVED, in slot 2,
        -- resident in both phases and untouched by the flat window.
        -- ★★★★★ IT IS **NOT** MAP_FONT, AND THE FIRST VERSION USED THAT AND HUNG THE RUN.
        -- memmap.inc puts the engine's font at $E0B8; this probe orgs the PARSER at $E000, so
        -- $E0B8 is 184 bytes into parser code. Staging 2,048 bytes there overwrote the parser and
        -- the run reported STUCK in cycle 6 [AD-179's class: an ENGINE address reused inside a
        -- probe whose own map already claimed it].
        -- ★★★★ WITHOUT A FONT THE PANEL DRAWS FROM WHATEVER IS THERE -- 2 KB of arbitrary bytes
        -- rendered as 8x8 cells. **A wrong font and a wrong blit look the same to a person**, so
        -- staging it is a precondition of the eye gate meaning anything.
        -- ★★★ Optional: a build with no P3_FONT symbol (the cel configuration) skips it silently.
        local FONT = os.getenv("P3B_FONT") or "build/text_font.bin"
        if SYM.P3_FONT then
            local fd = slurp(FONT)
            if not fd then
                w("★★★ no font at %s -- the text gate needs one [P3B_FONT]", FONT)
                m:exit(); return
            end
            if #fd ~= 2048 then
                w("★★★ font is %d bytes, expected 2048", #fd); m:exit(); return
            end
            for i = 1, #fd do prog:write_u8(SYM.P3_FONT + i - 1, fd:byte(i)) end
            w("font %d bytes -> P3_FONT $%04X", #fd, SYM.P3_FONT)
        end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
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
        -- ★★★★★ THE THRESHOLD WAS 240 FRAMES AND THE MESSAGE SAID 900. Four emulated seconds is
        -- not a hang for a cycle that fetches a PICTURE and RENDERS it -- the room render alone
        -- is ~2.9 s measured -- so the first run of the integrated probe reported "STUCK in
        -- cycle 1" for a cycle that was merely doing its job. **A watchdog shorter than the work
        -- it guards manufactures the failure it is looking for.**
        -- ★★★ And the message misreported its own limit, which is the worse half: the number a
        -- reader would have used to judge whether 900 frames was generous was not the number the
        -- code used. Both are now STALL_FRAMES.
        -- ★★ 1800 frames = 30 emulated seconds, against a first cycle of render (~2.9 s) plus
        -- fetches plus VM. Generous on purpose: a real hang stays hung, and the PC census below
        -- costs nothing extra when it finally fires.
        if stuck == STALL_FRAMES then
            local l = {}
            for k, v in pairs(spin) do l[#l+1] = {k, v} end
            table.sort(l, function(a, b) return a[2] > b[2] end)
            w("★★★ STUCK in cycle %d after %d frames (%.1f emulated s) -- most-visited PCs:",
              n, STALL_FRAMES, STALL_FRAMES / 60.0)
            for i = 1, math.min(6, #l) do w("     $%04X  x%d", l[i][1], l[i][2]) end
            w("     S=$%04X  U=$%04X  (hw stack base $0800, usable down to $0500;", cpu.state["S"].value, cpu.state["U"].value)
            w("      seed stack $0100-$04FF -- S below $0500 means they collided)")
            w("     status=$%02X (B1 fetched, B2 draw-phase, B3 planes cleared, B4 rendered, B5 closed)", prog:read_u8(STATUS))
            w("     status=$%02X", prog:read_u8(STATUS))
            w("     room %d  sprites %d  err %d  remaps %d",
              prog:read_u8(ROOM), prog:read_u8(NSPR), prog:read_u8(ERR), rd16(REMAPS))
            -- ★★★★★ REPORT THE PARSER'S INPUTS, NOT ONLY ITS PC. A stall inside par_fi_char is
            -- the walk failing to find a terminator, and that is a statement about the BYTES it
            -- is reading, not about the loop. Without these the dump says "the parser hung" and
            -- sends the reading to parser.s -- which is gated at 23,328 cases and is not where
            -- the fault is [P6.3 §3.C: the PC landed in the character loop every time, for the
            -- honest reason that that is where a working parser spends its time].
            -- ★★★★ THE MMU SLOTS ARE THE FIRST SUSPECT AND WERE NOT PRINTED. The vocabulary
            -- lives at $E000 -- slot 7 -- and mmu_phase.s's contract is that slots 0-4 and 7 are
            -- set once at init and never touched. If something moved slot 7 the window holds
            -- someone else's bytes and the walk cannot terminate. Print the register, not the
            -- assumption.
            if words then
                local sl = {}
                for s = 0, 7 do sl[#sl+1] = string.format("%02X", prog:read_u8(0xFFA0 + s)) end
                w("     MMU $FFA0-7: %s   (slot 7 = $E000, the vocabulary window)",
                  table.concat(sl, " "))
                local got, want = {}, {}
                local bad = 0
                for i = 0, 7 do
                    local g = prog:read_u8(VOCAB + i)
                    got[#got+1] = string.format("%02X", g)
                    want[#want+1] = string.format("%02X", words:byte(i + 1))
                    if g ~= words:byte(i + 1) then bad = bad + 1 end
                end
                w("     vocab $E000: %s  (staged: %s)  %s",
                  table.concat(got, " "), table.concat(want, " "),
                  bad == 0 and "MATCHES -- the window still holds WORDS.TOK"
                           or "★★★ DIFFERS -- the vocabulary window has been overwritten")
                if SYM.par_vocab then
                    w("     par_vocab = $%04X", rd16(SYM.par_vocab))
                end
                -- ★★★ WHO WROTE IT. The tap records rather than logs (logging from a tap ran the
                -- machine into the ground), so this is where the recording is read out. An EMPTY
                -- list is itself the answer: no guest instruction stored to par_vocab, so a zero
                -- there was never written by the guest and the question moves to the host.
                if _G._pv then
                    w("     par_vocab stores seen by the tap: %d", #_G._pv)
                    for i = 1, #_G._pv do
                        w("       $%04X <- $%02X from PC=$%04X at cycle %d",
                          _G._pv[i][1], _G._pv[i][2], _G._pv[i][3], _G._pv[i][4])
                    end
                end
                if SYM.P3_INBUF then
                    local t = {}
                    for i = 0, 11 do t[#t+1] = string.format("%02X", prog:read_u8(SYM.P3_INBUF + i)) end
                    w("     inbuf: %s", table.concat(t, " "))
                end
            end
            m:exit()
        end
        return
    end
    stuck = 0

    if state == "cycle" then
        -- ★★★★ TIME A CYCLE ONCE, NOT ONCE PER FRAME OF THE HOLD. The hold guard below is
        -- correctly placed so the SUMMARY runs once, but this block sits above it and `n` stays
        -- at NCYC across the hold -- so `n == NCYC` was true on every frame and the last cycle's
        -- line printed **~250 times**, each with a fresh one-frame delta (0.0167 s) that is not
        -- a cycle time at all. ★★★ Same shape as the 900 copies of "final room 22" the hold
        -- guard was added to stop, one block further up, and the fix is the same: key on the
        -- EVENT (a new cycle completed) rather than on the state.
        -- ★★ It also stopped `per` collecting frame deltas as if they were cycles. The median
        -- was computed before the hold began so no published figure moved -- but a timing array
        -- that accepts non-timings is one task away from one that does.
        if n > 0 and n ~= last_timed then
            last_timed = n
            local now = m.time:as_double()
            per[#per+1] = now - tprev
            tprev = now
            -- ★★★★ THE GAME CLOCK'S PER-CYCLE DELTA [AC-4]. Keyed on the same "a new cycle
            -- completed" event as the timing above, for the same reason: sampled per FRAME it
            -- would report zero on most frames and mean nothing.
            if SYM.vm_vms then
                local v = rd32(SYM.vm_vms)
                if vms_prev then
                    local d = v - vms_prev
                    if d > vms_max then vms_max, vms_max_at = d, n end
                end
                vms_prev = v
            end
            if n <= 3 or n == NCYC then
                w("  cycle %3d  %.4f s  room %3d  sprites %2d  remaps %d  err %d",
                  n, per[#per], prog:read_u8(ROOM), prog:read_u8(NSPR),
                  rd16(REMAPS), prog:read_u8(ERR))
            end
        end
        if n >= NCYC then
            -- ★★★ THE HOLD IS TESTED FIRST so the summary and the plane dump happen exactly
            -- once. Placing it after them re-ran the whole report on every frame of the hold --
            -- 900 copies of "final room 22" for a 15-second look at the screen.
            if hold_until then
                if m.time:as_double() < hold_until then return end
                m:exit(); return
            end
            local tot = m.time:as_double() - t0
            table.sort(per)
            local med = per[math.floor(#per/2)+1] or 0
            w("")
            w("★ %d cycles in %.4f emulated s", NCYC, tot)
            -- ★★★★ REPORT THE MEASURED CLOCK, AND SAY SO WHEN IT IS NOT THE EXPECTED ONE. A
            -- machine at 0.894 MHz is a missing -DHAL_SYS_FAST_CLOCK, not a slow interpreter,
            -- and that distinction is the difference between a cycle-rate decision for Jay and
            -- a one-line build fix.
            if CLOCK then
                w("    clock MEASURED %.6f MHz (%d cycles calibrated)", CLOCK/1e6, CAL_CYCLES)
                if CLOCK < 1.3e6 then
                    w("    ★★★ SLOW CLOCK -- expected 1.789390 MHz. The build is missing")
                    w("        -DHAL_SYS_FAST_CLOCK; every figure below is ~2x too slow.")
                end
            else
                w("    ★★★ clock NOT calibrated -- markers 11/12 never paired. Treat every")
                w("        timing below as unverified [L-57].")
            end
            w("    median %.4f s/cycle = %.2f cycles/second", med, 1.0/med)
            w("    mean   %.4f s/cycle = %.2f cycles/second", tot/NCYC, NCYC/tot)
            w("    remaps total %d = %.2f per cycle", rd16(REMAPS), rd16(REMAPS)/NCYC)
            -- ★★★★ AC-5: the per-cycle breakdown, from the phase tap.
            local order = {"pace(wait)", "interpret", "sprites", "roomcheck", "composite"}
            local tot = 0
            for _, k in ipairs(order) do tot = tot + (stage_total[k] or 0) end
            w("    ── per-stage, %d cycles ──", NCYC)
            for _, k in ipairs(order) do
                local s, cnt = stage_total[k] or 0, stage_n[k] or 0
                w("       %-10s %8.4f s total  %8.5f s/cycle  %5.1f%%  (%d entries)",
                  k, s, s/NCYC, tot > 0 and 100*s/tot or 0, cnt)
            end
            w("       %-10s %8.4f s total  %8.5f s/cycle", "SUM", tot, tot/NCYC)
            if stage_open then
                w("    ★★★ stage %s entered and never left -- an unpaired marker",
                  MARK[stage_open[1]] or "?")
            end
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
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE BLOCKING BOX's OBSERVABLES [AC-4, AC-5, AC-7]. All three are properties,
            -- never text [§2P].
            -- ★★★★ var 21 reading 0 at the end is text.cpp:411's zeroing, which happens ONLY on the
            -- path that actually left the wait -- so a non-zero value here means the last armed box
            -- was never entered, and that is a different failure from a hang.
            -- ★★★ tx_wt_key distinguishes ESC from ENTER-or-timer. It is the port's
            -- _messageBoxCancelled and **nothing consumes it yet** [T-P0-085 §7.3]; it is read here
            -- so AC-7 is a measurement rather than an eye-only claim.
            if SYM.vm_vms then
                w("    game clock: vm_vms=%d, largest per-cycle delta %d ticks at cycle %d"
                  .. " (%.2f s at 16.667 ms/tick)",
                  rd32(SYM.vm_vms), vms_max, vms_max_at, vms_max * 0.016667)
                if AUTOCLOSE > 0 then
                    local want = AUTOCLOSE * 30
                    w("    var21 armed %d -> expected hold >= %d ticks; observed %d -- %s",
                      AUTOCLOSE, want, vms_max,
                      vms_max >= want and "the clock ADVANCED across the box"
                                      or "★★★ the box did not hold for its timer")
                end
            end
            if JUMP_ROOM > 0 then
                w("    room jump: asked %d, landed %s, dispatched %s, final room %d",
                  JUMP_ROOM, tostring(jumped), tostring(jump_seen_clear), prog:read_u8(ROOM))
            end
            if SYM.tx_wt_key then
                w("    var21 now %d (0 = a box was entered and left), tx_wt_key=%d (1 = ESC)",
                  prog:read_u8(VAR_AUTOCLOSE), prog:read_u8(SYM.tx_wt_key))
            end
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ AC-3's OBSERVABLE, AS A PROPERTY RATHER THAN THE TEXT [§2P].
            -- P3_PBUF holds the last message the text engine substituted. With res_decode on the
            -- cache-MISS path those bytes are plaintext, so nearly all are printable ASCII. Under
            -- -DRES_FAULT_DECODE_HIT the decode ALSO runs on the hit path, re-encrypting every
            -- cached re-bind, so the same buffer fills with cipher bytes and the count collapses.
            -- ★★★★ COUNTED, NEVER PRINTED. §2P forbids committing game text; a count says
            -- everything AC-3 needs and discloses nothing.
            -- ★★★ ON THE COMPLETION PATH, AND THE FIRST VERSION PUT IT ON THE STALL PATH beside
            -- the vocabulary readout -- which runs only when the watchdog fires, so on a healthy
            -- run it printed nothing. **An observable emitted only when the run has already failed
            -- cannot compare a good arm against a bad one.**
            -- ★★ It also discharges P6.28d §7.1: it answers "did the bytes reaching the renderer
            -- decode" from the guest's own memory rather than from a person reading the screen.
            -- ★★★★★ COUNT THE STRING, NOT THE BUFFER, AND THE FIRST VERSION COUNTED THE BUFFER.
            -- txt_printf writes a NUL-terminated string into a 576-byte scratch that is never
            -- cleared, so bytes past the terminator are whatever an EARLIER, LONGER message left.
            -- Counting all 64 mixed live text with dead tail and reported "NOT DECODED" for the
            -- very build a person had just read off the screen as legible.
            -- ★★★★ **An instrument that contradicts a confirmed observation is the instrument's
            -- problem until proven otherwise** -- the eye gate is tier-1 evidence here and this
            -- readout is tier-3 [§2W; and L-88: count the artifacts the run produces against the
            -- artifacts the comparison reads].
            if SYM.P3_PBUF then
                local pr, n = 0, 0
                for i = 0, 575 do
                    local c = prog:read_u8(SYM.P3_PBUF + i)
                    if c == 0 then break end
                    n = n + 1
                    if c >= 0x20 and c < 0x7F then pr = pr + 1 end
                end
                -- ★★★★★ A CHECKSUM, BECAUSE THE COUNT CANNOT TELL TWO MESSAGES APART [T-P0-086].
                -- "26 of 26 printable" read identically before and after var 17 was set, which
                -- looks like print substituting a message and is equally consistent with the
                -- buffer holding a STALE one from the intro's display. **A property that does not
                -- change when the input changes is not measuring the input** [§2W].
                -- ★★ §2P: a sum over the bytes is a property; the bytes are the game's.
                local ck = 0
                for i = 0, n - 1 do ck = (ck * 31 + prog:read_u8(SYM.P3_PBUF + i)) % 65536 end
                w("    P3_PBUF $%04X: %d of %d bytes to the terminator are printable ASCII,"
                  .. " checksum $%04X -- %s",
                  SYM.P3_PBUF, pr, n, ck,
                  n == 0 and "buffer empty"
                        or (pr * 100 // n >= 90 and "DECODED" or "★★★ NOT DECODED"))
            end
            if DUMP then
                -- ★★★★★ READ THE PLANES THROUGH THEIR WINDOWS. This read 26,880 bytes flat from
                -- $C000 -- i.e. $C000..$128FF, wrapping past $FFFF. That was correct while the
                -- planes were contiguous and became a defect the moment windowing landed: the
                -- window is 8,192 bytes and the visual plane is 26,880. **A gate reading a
                -- wrapped address reports on nothing** [L-74, and §5's grep asked for exactly
                -- this before anything was changed].
                -- ★★★ The guest owns the block numbers (ph_blk_fb / ph_blk_pri) and the host
                -- reads them rather than assuming: mapping is the guest's fact, and duplicating
                -- it here is how the constant went stale in the first place.
                -- ★★ Slot 6 ($FFA6) covers $C000 and slot 5 ($FFA5) covers $A000, which is the
                -- pair mmu_phase.s owns. The host restores nothing afterwards because the probe
                -- is finished; the next cycle would re-map for itself.
                local SLOT6, SLOT5 = 0xFFA6, 0xFFA5
                local blk_fb  = SYM.ph_blk_fb  and prog:read_u8(SYM.ph_blk_fb)  or nil
                local blk_pri = SYM.ph_blk_pri and prog:read_u8(SYM.ph_blk_pri) or nil
                if not blk_fb or not blk_pri then
                    w("    ★★★ cannot dump: symbols.txt lacks ph_blk_fb/ph_blk_pri")
                else
                    w("    dumping through the window: fb blocks $%02X.. pri blocks $%02X..",
                      blk_fb, blk_pri)
                    local fv = io.open(OUT .. "/guest.visual.bin", "wb")
                    local tv = {}
                    for i = 0, PLANE-1 do
                        local sl, off = i >> 13, i & 0x1FFF
                        if off == 0 then prog:write_u8(SLOT6, blk_fb + sl) end
                        tv[i+1] = string.char(prog:read_u8(FB_BASE + off))
                    end
                    fv:write(table.concat(tv)); fv:close()
                    -- ★ priority is PACKED (two pixels per byte), so its plane is PLANE//2 bytes
                    -- and it is expanded here; the oracle's copy is never packed [§2O.1].
                    local fp = io.open(OUT .. "/guest.priority.bin", "wb")
                    local tp = {}
                    for j = 0, (PLANE//2)-1 do
                        local sl, off = j >> 13, j & 0x1FFF
                        if off == 0 then prog:write_u8(SLOT5, blk_pri + sl) end
                        local b = prog:read_u8(PRI_BASE + off)
                        tp[#tp+1] = string.char((b >> 4) & 0x0F)
                        tp[#tp+1] = string.char(b & 0x0F)
                    end
                    fp:write(table.concat(tp)); fp:close()
                    w("    planes written to %s", OUT)
                end
            end
            -- ★★★★★ P3B_HOLD -- KEEP THE PICTURE ON SCREEN AFTER THE LAST CYCLE [T-P0-056 AC-1].
            -- ★★★★ This exited the instant the cycles completed, so the room Jay is being asked
            -- to judge was on screen for a fraction of a second and then the window closed.
            -- **An eye gate the operator cannot actually look at is not an eye gate**, and this
            -- one had been run four times before he said so: "i need a delay after each is
            -- displayed to really see for sure".
            -- ★★★ Emulated seconds, like everything else here: the guest is idle across the hold
            -- so nothing it does can change what is displayed, and the dump above has already
            -- been written -- the hold cannot affect any measurement.
            if HOLD > 0 then
                hold_until = m.time:as_double() + HOLD
                w("    ★ holding the display for %g emulated s (P3B_HOLD)", HOLD)
                return
            end
            m:exit(); return
        end
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ ARM THE FEED, ONE PARK EARLY -- the same off-by-one vm_sweep.lua holds and for
        -- the same reason: the guest checks P3_FEED after vm_pace, which it reaches only after
        -- the body of the cycle this release starts. So a line armed here lands before cycle
        -- n+1's body. **Both probes feed at the same seam or the eye gate and the byte gate are
        -- watching different programs.**
        -- ★ §2P: the CYCLE and the LENGTH are printed. The words are the game's.
        local feed = script[n + 1]
        if feed and words then
            if #feed >= INBUF_MAX then
                w("★★★ input for cycle %d is %d chars, past the oracle's %d-byte input line "
                  .. "[text.h:170] -- NOT fed", n + 1, #feed, INBUF_MAX)
            else
                for i = 1, #feed do prog:write_u8(SYM.P3_INBUF + i - 1, feed:byte(i)) end
                prog:write_u8(SYM.P3_INBUF + #feed, 0)
                prog:write_u8(SYM.P3_FEED, 1)
                w("  ★ COMMAND TYPED at cycle %d (%d chars) -- watch the screen", n + 1, #feed)
            end
        end

        -- ★★★ THE JUMP, one release before the cycle that should dispatch it -- the same seam the
        -- feed and the var-21 arm use, for the same reason: the guest reads this state inside the
        -- cycle this write releases.
        if JUMP_ROOM > 0 and not jumped and n >= JUMP_AT then
            prog:write_u8(VM_VARS + 0, JUMP_ROOM)
            local b = prog:read_u8(VM_FLAGS + 0)
            prog:write_u8(VM_FLAGS + 0, b | 0x20)
            for _, kv in ipairs(SETVAR) do
                prog:write_u8(VM_VARS + kv[1], kv[2])
                w("  ★ var %d <- %d (reads %d)", kv[1], kv[2],
                  prog:read_u8(VM_VARS + kv[1]))
            end
            local rb_room = prog:read_u8(VM_VARS + 0)
            local rb_flag = (prog:read_u8(VM_FLAGS + 0) & 0x20) ~= 0
            jumped = true
            w("  %s room jump at cycle %d: var0 <- %d (reads %d), flag 5 set (reads %s)",
              (rb_room == JUMP_ROOM and rb_flag) and "★" or "★★★",
              n, JUMP_ROOM, rb_room, tostring(rb_flag))
            if not (rb_room == JUMP_ROOM and rb_flag) then
                w("★★★ THE JUMP DID NOT LAND -- not a negative result, a broken write [L-56]")
                m:exit(); return
            end
        end
        -- ★★ flag 5 CLEARED means logic.0 consumed it and dispatched the room. Sampled every
        -- cycle after the jump because it is cleared within a cycle or two and a single late look
        -- would miss it.
        if jumped and not jump_seen_clear and (prog:read_u8(VM_FLAGS + 0) & 0x20) == 0 then
            jump_seen_clear = true
            w("  ★ flag 5 cleared by cycle %d -- logic.0 DISPATCHED the room", n)
        end

        -- ★★★ ARM THE AUTO-CLOSE BEFORE RELEASING THE CYCLE, not after: the guest runs print
        -- inside the cycle this write releases, and tx_wait_dismiss reads var 21 at the moment it
        -- enters the wait. Written one release early for exactly the reason the feed above is.
        if AUTOCLOSE > 0 then prog:write_u8(VAR_AUTOCLOSE, AUTOCLOSE) end

        n = n + 1
        prog:write_u8(MODE, 1)
        prog:write_u8(GO, 1)
        return
    end
end)
