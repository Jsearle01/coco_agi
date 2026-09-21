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
-- ★★★★ 1800 frames is 30 emulated seconds, which is generous for a machine and WRONG for a
-- person. With the blocking message box the guest legitimately waits for a keypress, so on the
-- eye-gate path the watchdog is measuring how fast Jay reads. P3B_STALL_FRAMES is the override
-- and the eye-gate invocation passes it; the headless default is unchanged so no gate moves.
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
-- ★★★ NAMED AT MODULE SCOPE BECAUSE THREE PLACES NOW NEED SLOT 5: the vocabulary staging, the
-- stall dump's dictionary readout, and the plane dump at the foot of this file -- which declared
-- its own `local SLOT6, SLOT5` and was the only home the pair had. **Two homes for $FFA5 in one
-- file is how the next caller writes a literal** [§2F], and the dump's locals now come from here.
local SLOT5     = 0xFFA5        -- MMU slot 5: priority / VM_OBJ / the vocabulary window
local SLOT6     = 0xFFA6        -- MMU slot 6: framebuffer slice / VOL window (== MMU_SLOT)
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
-- ★★★★★ DECLARED HERE, ABOVE stage(), AND THAT PLACEMENT IS THE WHOLE POINT [T-P0-097]. This is
-- the THIRD time in this file that a name read inside stage() was declared below it: the res_err
-- tap's cycle, the par_vocab tap's cycle, and this. **A local declared after a function is a
-- GLOBAL inside it**, and a nil global is silent -- the tap simply never installs, and the missing
-- output reads as "the condition was false".
-- ★★★ The other two were fixed by not capturing at all (they read the guest's counter). This one
-- is a configuration value with nowhere else to come from, so it moves instead.
local PHASETAP = tonumber(os.getenv("P3B_PHASETAP") or "")
-- ★★ P3B_SAIDAT=<vm_cycle> -- record one row per said() in that cycle [T-P0-098]. Declared here,
--    above stage(), for the reason the comment on PHASETAP gives.
local SAIDAT = tonumber(os.getenv("P3B_SAIDAT") or "")
-- ★★ P3B_WATCHVAR=<n> -- which variable the writer recorder watches. 0 by default.
local WATCHVAR = tonumber(os.getenv("P3B_WATCHVAR") or "0")
-- ★★★ P3B_IFLOGIC=<n> -- which logic the `if` recorder watches, in the P3B_SAIDAT cycle
--    [T-P0-101]. Declared up here for the same reason PHASETAP is: a `local` below stage() is a
--    nil GLOBAL inside it, and this file has produced that defect three times.
local IFLOGIC = tonumber(os.getenv("P3B_IFLOGIC") or "")
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
    -- ★★★★★ THE MARK-AND-SURVIVE INSTRUMENT WAS TRIED HERE AND WITHDRAWN [T-P0-093, §2W].
    -- The idea: write a non-uniform pattern into row 22's band before the guest reaches it, and
    -- see whether accept.input's clearLine(22) wipes it. Four slots wipes, three slots cannot.
    -- ★★★★★ IT DOES NOT DISCRIMINATE, AND THE CHECK THAT SHOWED THAT IS THE ONE §2W ASKS FOR:
    -- run the case that should leave the mark ALONE. In room 83 the prompt is never enabled, so
    -- nothing should clear anything -- and the mark vanished there too, leaving the band uniform
    -- $FF, which is the colour p3_clear_planes writes. **The plane clear reaches that band**, so
    -- the instrument was measuring the renderer and reporting it as the text engine.
    -- ★★★★ It had already "passed" on the clean arm and "passed" on the fault arm before that
    -- check was run. Two green results, one of which should have been red, and the reason was the
    -- INPUT rather than the adjudication [AD-90, AD-102, AD-122's shape].
    -- ★★★ What replaces it is below: inject a key at the editor's own entry point and count what
    -- appears on row 22. That measures the path under test and nothing else.

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
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ THE DICTIONARY IS IN A BLOCK NOW, NOT BEHIND THE PARSER [T-P0-091]. The text
        -- configuration maps WORDS.TOK into slot 5 for the duration of par_parse and nothing
        -- else, so staging it means mapping the same block the guest will map and poking $A000.
        -- ★★★★ THE BLOCK NUMBER COMES FROM THE GUEST, WHICH OWNS IT -- ph_blk_vocab, read from
        -- the map, exactly as ph_blk_fb/ph_blk_pri are read for the plane dump below. A literal
        -- here would be a second home for a number the probe already declares [§2F], and the
        -- failure would be a dictionary staged into a block nothing reads: the parser would find
        -- no words and it would look like a tokeniser defect.
        -- ★★★ AND SLOT 5 GOES BACK TO ph_blk_slot5, not to a remembered value. The guest's own
        -- phase_vocab_out uses that byte; using anything else here would leave the host and the
        -- guest disagreeing about what slot 5 holds while the object table lives in it.
        -- ★★ The flat configuration takes neither branch: no ph_blk_vocab symbol, no remap.
        -- ★★★★★ A BLOCK NUMBER OF ZERO MEANS "NO BLOCK", NOT "BLOCK 0" [T-P0-095]. The symbol's
        -- PRESENCE stopped being the right test the moment a build existed that has the phase
        -- service and a FLAT dictionary: ph_blk_vocab exists there and the guest never sets it,
        -- so staging through it would map block 0 -- the priority plane -- over the object table
        -- and poke the dictionary into it.
        -- ★★★ Block 0 is genuinely in use (priority, per this file's own allocation note), so zero
        -- is unambiguous as a sentinel here and is what the guest leaves it at.
        local VBLK = SYM.ph_blk_vocab and prog:read_u8(SYM.ph_blk_vocab) or nil
        if VBLK == 0 then VBLK = nil end
        local V5   = SYM.ph_blk_slot5 and prog:read_u8(SYM.ph_blk_slot5) or nil
        if VBLK and not V5 then
            w("★★★ ph_blk_vocab is in the map and ph_blk_slot5 is not -- cannot restore slot 5")
            return false
        end
        if VBLK then prog:write_u8(SLOT5, VBLK) end
        for i = 1, #words do prog:write_u8(VOCAB + i - 1, words:byte(i)) end
        -- ★★ A SAMPLE, NOT BYTE 1. WORDS.TOK's first byte is zero (the 'a' bucket's head offset,
        -- high half), so a one-byte readback passes on RAM nothing was written to -- which is
        -- what the first version of this check did in vm_sweep.lua before it was caught.
        local bad = 0
        for k = 0, 32 do
            local off = math.floor((#words - 1) * k / 32)
            if prog:read_u8(VOCAB + off) ~= words:byte(off + 1) then bad = bad + 1 end
        end
        if VBLK then prog:write_u8(SLOT5, V5) end
        w("  vocabulary %d B -> $%04X%s; window self-test clean; %d/33 sample points match %s",
          #words, VOCAB,
          VBLK and string.format(" (block %d, slot 5; restored to %d)", VBLK, V5) or " (flat)",
          33 - bad, bad == 0 and "OK" or "★★★ MISMATCH")
        if bad ~= 0 then return false end
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ AND THE CHECK THAT SAYS THE TWO BLOCKS ARE DIFFERENT MEMORY [§2W]. Everything
        -- above would read back perfectly if ph_blk_vocab named the block slot 5 ALREADY holds:
        -- the poke and the readback would be the same bytes in the same place, the sample would
        -- be 33/33, and the dictionary would be sitting on top of the 8,160-byte object table.
        -- ★★★★ **A readback through the window cannot distinguish a window from no window.** So
        -- this reads the SAME address with the window SHUT and requires it to differ: if it does
        -- not, either the block is the object table's or the remap did nothing, and both are the
        -- failure this staging has to be unable to hide.
        -- ★★★ At a NON-ZERO byte, deliberately. WORDS.TOK's first byte is zero and so is freshly
        -- initialised VM_OBJ, so a check at offset 0 would pass on exactly the case it is for --
        -- the same trap the 33-point sample exists to avoid one paragraph up.
        if VBLK then
            local probe_off = nil
            for i = 1, #words do
                if words:byte(i) ~= 0 then probe_off = i - 1; break end
            end
            if not probe_off then
                w("★★★ WORDS.TOK is entirely zero -- refusing to stage a dictionary with no content")
                return false
            end
            local shut = prog:read_u8(VOCAB + probe_off)
            local open = words:byte(probe_off + 1)
            w("  %s window discrimination: $%04X reads $%02X shut and $%02X open %s",
              shut ~= open and "★" or "★★★", VOCAB + probe_off, shut, open,
              shut ~= open and "-- block " .. VBLK .. " is distinct memory"
                            or "★★★ IDENTICAL -- the remap did nothing, or the dictionary is on "
                               .. "top of the object table")
            if shut == open then return false end
        end
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
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ WATCH res_err, BECAUSE SIX TASKS HAVE LOGGED `err 1` AND NONE HAS NAMED IT
        -- [T-P0-094 §4D]. RES_E_EMPTY is "the DIR slot is FF FF FF" [res_core.s:182] and the probe
        -- reports only the byte, at the END of the run -- so the resource, the cycle and the call
        -- site have never been in any log.
        -- ★★★★ A WRITE TAP NAMES THE PC, which names the call site, and the cycle and the room at
        -- that instant give the request its context. **res_open takes the type and index in A and
        -- B and publishes neither**, so without a guest change (out of scope here, §1.3) the PC
        -- plus the room is what is recoverable -- and it is enough to say WHICH fetch.
        -- ★★ Cheap, as taps must be: append to a table, print later. Writing to the log from
        -- inside a tap ran the machine into the ground once already [the par_vocab tap's note].
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ A WRITE TAP ON VAR 0 WAS TRIED AND ABANDONED [T-P0-094]. It would have named the
        -- PC that stores the room, which is the strongest form of the answer. **MAME's write tap
        -- covers the containing region, not the byte**, and $0800 is the VM state block -- written
        -- on essentially every opcode -- so the run did not finish 400 cycles in ten minutes where
        -- it normally takes forty seconds.
        -- ★★★ What replaces it is vm_curlogic sampled at each ROOM TRANSITION: it names the LOGIC
        -- that was executing, which is one level coarser than the PC and costs nothing. Recorded
        -- so the next reader does not re-derive that a hot-byte tap is unaffordable here.
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ MID-CYCLE READS, THROUGH A MECHANISM THAT ALREADY EXISTS [T-P0-097 §4B/§4C].
        -- P3_PHASE is written 1 before vm_pace, **2 immediately after the feed and BEFORE
        -- vm_interpret_cycle**, 3 just after, and 4 after vm_post_cycle [p3b_probe.s:885-922].
        -- ★★★★★ SO PHASE 2 AND PHASE 4 BRACKET THE CYCLE BODY, and a write tap on that one byte
        -- reads the flags at both instants **without touching the port**: phase 2 answers "did the
        -- feed set ENTERED_CLI" and phase 4 answers "did post_cycle clear it". Those are the two
        -- halves of the only remaining question about flag 2 [P6.41 §7.2].
        -- ★★★★ BOUNDED TO ONE CYCLE. A tap on $0800 was abandoned last task because MAME's tap
        -- covers the containing region and the VM writes that page constantly; this is one status
        -- byte written ~4 times a cycle, and the callback's FIRST act is a cycle test so the other
        -- 399 cycles cost a compare.
        -- ★★★ P3B_PHASETAP=<cycle> selects it; absent, nothing is installed.
        if PHASETAP and SYM.vm_restart then
            _G._ph = {}
            _G._phtap = prog:install_write_tap(ST + 30, ST + 30, "phase",
                function(offset, data, mask)
                    -- ★★★ P3_CYCLE COUNTS COMPLETED CYCLES and is incremented at the END of the
                    -- body, so DURING cycle N it still reads N-1. The first version tested for N
                    -- and captured nothing. Both values are accepted and the counter is printed,
                    -- so the reader sees which cycle each row belongs to rather than trusting the
                    -- off-by-one in a comment.
                    -- ★★★ P3B_PHASETAP=0 CAPTURES THE FIRST 24 MARKERS WHATEVER THE CYCLE. A tap
                    -- that produces nothing is indistinguishable from a filter that never matches,
                    -- and this file has already spent two runs on that ambiguity today [§2W: show
                    -- the instrument can fire before believing its silence].
                    local c = prog:read_u8(ST + 4) * 256 + prog:read_u8(ST + 5)
                    if #_G._ph >= 24 then return end
                    if PHASETAP > 0 and (c < PHASETAP - 2 or c > PHASETAP + 1) then return end
                    _G._ph[#_G._ph + 1] = {
                        data % 256,                                   -- the phase
                        prog:read_u8(VM_FLAGS + 0),                   -- flags 0-7, packed
                        SYM.par_egon and prog:read_u8(SYM.par_egon) or -1,
                        SYM.par_cli  and prog:read_u8(SYM.par_cli)  or -1,
                        prog:read_u8(SYM.vm_restart),
                        prog:read_u8(VM_VARS + 0),                    -- the room
                        prog:read_u8(VM_VARS + 88),                   -- the speed shadow
                        c }                                           -- P3_CYCLE as read
                end)
        end
        if SYM.res_err then
            _G._re = {}
            -- ★★★★★ THE CYCLE COMES FROM THE GUEST's OWN COUNTER, NOT FROM `n` [T-P0-095].
            -- stage() is defined ABOVE `local n`, so `n` inside this closure resolves to a GLOBAL
            -- of that name -- which is nil. The tap then recorded a nil cycle, string.format threw
            -- "bad argument #4", and **the frame callback died silently**: the run completed, the
            -- log stopped mid-summary, and the missing lines read as "the check did not fire".
            -- ★★★★ A diagnostic that kills the reporting it belongs to is worse than one that says
            -- nothing [§2W.3]. P3_CYCLE is two bytes at ST+4 and is the same number `n` tracks.
            -- ★★★ The par_vocab tap twenty lines below captures `n` the same way and has the same
            -- latent bug; it only shows on the stall path, which is why nobody has met it.
            _G._retap = prog:install_write_tap(SYM.res_err, SYM.res_err, "reserr",
                function(offset, data, mask)
                    if (data % 256) ~= 0 and #_G._re < 16 then
                        _G._re[#_G._re + 1] = { data % 256, cpu.state["PC"].value,
                                                prog:read_u8(ST + 4) * 256 + prog:read_u8(ST + 5),
                                                prog:read_u8(0x0800) }
                    end
                end)
        end
        _G._pv = {}
        -- ★★★★ THE CYCLE COMES FROM P3_CYCLE, NOT FROM `n` [T-P0-096 §4D(1)]. Same latent closure
        -- bug the res_err tap had: stage() is defined above `local n`, so this captured a global
        -- of that name and stored nil. **It fires only on the stall path**, which is why it has
        -- never been met -- and the stall path is exactly where a nil would kill the frame
        -- callback and take the whole stall dump with it [P6.40 §7.1].
        _G._pvtap = prog:install_write_tap(SYM.par_vocab, SYM.par_vocab + 1, "parvocab",
            function(offset, data, mask)
                if #_G._pv < 24 then
                    _G._pv[#_G._pv + 1] = { offset, data % 256, cpu.state["PC"].value,
                                            prog:read_u8(ST + 4) * 256 + prog:read_u8(ST + 5) }
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
-- ★ _p3b_room_default is p3b_room.lua's handover: that file used to default the room to 1, and it
--   chains here, so the default follows the jump rather than being lost with the notifier.
local JUMP_ROOM = tonumber(os.getenv("P3B_ROOM") or _G._p3b_room_default or "0")
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
-- ★★★★★ P3B_TYPE -- THE LINE IS **TYPED**, THROUGH THE KEY MATRIX [T-P0-092 §1.4].
--
-- ★★★★★ THIS IS NOT THE SAME TEST AS P3B_FEED AND THE DIFFERENCE IS THE POINT. The scripted feed
-- writes P3_INBUF from the host and sets a flag; it exercises par_parse and **not one instruction
-- of the editor** -- no key decode, no echo, no bound, no ENTER arm. A component gated only by
-- that path is a component gated by nothing [§2W, and P6.36 §4E one layer down].
--
-- ★★★★ natkeyboard DRIVES MAME's OWN KEYBOARD, which drives the CoCo3 matrix, which is what
-- HAL_key_scan reads [input_gate.lua, P6.24]. ★★★ Idiom 14b: `in_use` must be armed FRAMES before
-- the first post or the post is silently dropped, so it is armed at script load below and not at
-- the moment of typing.
-- ★ §2P: the LENGTH and the resulting word COUNT are printed. The line is the operator's.
local TYPE_TEXT = os.getenv("P3B_TYPE")
local TYPE_AT   = tonumber(os.getenv("P3B_TYPE_AT") or "20")
local typed, type_report = false, nil
-- ★★★★★ P3B_KEY_AT -- post ONE key at the title screen and watch VAR 19 [T-P0-124]. Distinct
-- from P3B_TYPE, which drives the EDITOR and keys on a counter the prompt gate controls; this
-- drives the SCAN and keys on VAR 19, which is what have.key reads.
local KEY_AT = tonumber(os.getenv("P3B_KEY_AT") or "0")
local KEY_CH = os.getenv("P3B_KEY_CH") or "\r"

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ P3B_INJECT -- A KEY AT THE EDITOR's OWN ENTRY POINT, ONE PER PARK [T-P0-093 AC-3].
--
-- ★★★★★ IT BYPASSES THE MATRIX ON PURPOSE AND SAYS SO. P6.37 established that natkeyboard cannot
-- hold a key across a once-per-cycle poll, and that a HUMAN's keypress arrives fine -- so the
-- matrix is not the thing in doubt and is not the thing this measures. **What is in doubt is
-- whether a character the editor accepts can be DRAWN on row 22**, which is the four-slot window's
-- whole purpose, and that question starts after the key decode.
-- ★★★★ THE INJECTION POINT IS p3_keybuf, the probe's one-deep latch. p3_poll_key consumes it
-- exactly as it consumes a scanned key -- same guard, same counter, same call into txt_pkey -- so
-- everything from the editor inward is the real path.
-- ★★★ WHAT THIS ROW THEREFORE CANNOT SEE [L-121]: the PIA scan, the key decode, and the debounce.
-- Those are input_probe's gate and Jay's eye gate; this one begins one byte later.
-- ★ §2P: the LENGTH and the resulting ink count are printed. The characters are the operator's.
-- ★★ P3B_STATEDUMP="98-102" -- the cycle range whose 288-byte state block is written to
--    <OUT>/state_<nnn>.bin, for state_diff.py to compare against the reference's oracle.bin.
local STATE_LO, STATE_HI
do
    local lo, hi = (os.getenv("P3B_STATEDUMP") or ""):match("^(%d+)%-(%d+)$")
    if lo then STATE_LO, STATE_HI = tonumber(lo), tonumber(hi) end
end

local INJECT    = os.getenv("P3B_INJECT")
local INJECT_AT = tonumber(os.getenv("P3B_INJECT_AT") or "20")
local inj_i     = 0

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

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ THE STACK LOW-WATER MARK [Jay: "that can lead to stack corruption and the PC jumping
-- into lala land"]. A 6809 IRQ stacks 12 bytes of machine state on S, on top of whatever depth
-- the VM's own recursion has reached. MAP_HWSTACK is $0800 and the seed stack ends at $0500, so
-- there are 768 bytes and the question is how much of it the deepest path already uses.
-- ★★★★ Sampled from the HOST, every frame, so it costs the guest nothing and cannot itself
-- perturb what it measures -- which matters more than usual here, because the thing being
-- measured is whether adding 12 bytes is safe [§2W.3].
-- ★★★ It is a low-water mark and not a spot reading: S at the end of a run is S in the handshake
-- loop, which is the shallowest point there is and would report a reassuring number forever.
local s_low, s_low_frame = 0xFFFF, 0
_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if state ~= "load" then
        local s = cpu.state["S"].value
        -- ★★ Ignore the pre-handover value: DECB's stack is elsewhere and would peg the mark.
        if s > 0x0400 and s < s_low then s_low, s_low_frame = s, frame end
    end
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
            -- ★★★★★ THE VECTOR CHAIN **BEFORE WE TOUCH ANYTHING** [after the IRQ crash].
            -- The crash dump showed $FFF8 -> $FEF7 holding non-JMP bytes and $010C zeroed, but
            -- that was read from an already-remapped, already-crashed machine. This samples the
            -- same three things at the DECB prompt, before takeover, and separates the two
            -- explanations that dump cannot: either the CoCo3 never had a stub at $FEF7 and the
            -- $010C route is not how interrupts reach a handler here, or DECB HAD one and our own
            -- MMU remap paged it away. ★★★ Those need opposite fixes, so guessing is expensive.
            do
                local v = prog:read_u8(0xFFF8) * 256 + prog:read_u8(0xFFF9)
                local b, c = {}, {}
                for i = 0, 4 do b[#b+1] = string.format("%02X", prog:read_u8(v + i)) end
                for i = 0, 2 do c[#c+1] = string.format("%02X", prog:read_u8(0x010C + i)) end
                w("AT THE DECB PROMPT: IRQ vector $FFF8 -> $%04X, bytes there %s  [$%02X = %s]",
                  v, table.concat(b, " "), prog:read_u8(v),
                  prog:read_u8(v) == 0x7E and "JMP -- a stub IS here"
                    or (prog:read_u8(v) == 0x6E and "JMP indirect -- a stub IS here"
                        or "NOT a jump"))
                w("AT THE DECB PROMPT: $010C = %s", table.concat(c, " "))
            end
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
        -- ★★★ ARMED HERE, NOT AT THE POST [idiom 14b]. natkeyboard.in_use defaults to false and
        -- arming it in the same frame as the first post loses the keys. This is hundreds of
        -- frames early, which is the margin that idiom asks for.
        if TYPE_TEXT then m.natkeyboard.in_use = true end
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
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ THE IMAGE IS A LIST OF RUNS, NOT A CODE BLOCK PLUS A TAIL [T-P0-089].
        -- lwasm --format=raw emits bytes in SOURCE order with no padding, so every `org` starts a
        -- new run and the file says nothing about where any of them goes. The text configuration
        -- now has FOUR: vm_tables.s is relocated into the seed stack's measured slack so the full
        -- 256-glyph font fits, which splits the code either side of it.
        -- ★★★★ EVERY BOUNDARY COMES FROM THE BUILD'S OWN MAP. A literal here would mis-place a
        -- whole run the moment the code grows -- the same rule that put P3_INBUF in the symbol
        -- list rather than in a constant [P6.3 §3.F.2], and the failure would look like a
        -- corrupted program rather than a staging bug.
        -- ★★★ The cel configuration has no split and no relocation, so it still describes two runs
        -- and this code produces exactly the two it always did.
        local segs = {}
        if SYM.P3_CODE_SPLIT and SYM.P3_TABLES_BASE and SYM.P3_TABLES_END then
            segs[#segs+1] = { LOAD,               SYM.P3_CODE_SPLIT - LOAD,             "code" }
            segs[#segs+1] = { SYM.P3_TABLES_BASE, SYM.P3_TABLES_END - SYM.P3_TABLES_BASE,
                              "vm_tables (relocated)" }
            -- ★★★★★ AND A FIFTH RUN WHEN THE TEXT ENGINE IS IN SLOT 7 [T-P0-120]. The combined
            -- arm `org`s src/engine/text.s to $EBBA, in the hole above the font, because region A
            -- cannot hold both halves. That splits the code a SECOND time, so the run list is
            -- code | vm_tables | code | text.s | code | parser.
            -- ★★★★ KEYED ON PRESENCE, exactly as the vm_tables split above is, so the cel and
            -- text arms -- which do not relocate the engine -- produce the run list they always
            -- did. ★★★ P6.64 §3.5 is why every one of these symbols is on the SHARED want-line
            -- and not a per-configuration one: absent, this silently collapses to a shorter list
            -- and the guest runs anyway, with the engine poked into the middle of the code.
            if SYM.P3_TEXT_SPLIT and SYM.P3_TEXTB_BASE and SYM.P3_TEXTB_END then
                segs[#segs+1] = { SYM.P3_CODE_SPLIT, SYM.P3_TEXT_SPLIT - SYM.P3_CODE_SPLIT, "code" }
                segs[#segs+1] = { SYM.P3_TEXTB_BASE, SYM.P3_TEXTB_END - SYM.P3_TEXTB_BASE,
                                  "text.s (relocated, slot 7)" }
                segs[#segs+1] = { SYM.P3_TEXT_SPLIT, SYM.P3_CODE_END - SYM.P3_TEXT_SPLIT, "code" }
            else
                segs[#segs+1] = { SYM.P3_CODE_SPLIT, SYM.P3_CODE_END - SYM.P3_CODE_SPLIT, "code" }
            end
        else
            segs[#segs+1] = { LOAD, (SYM.P3_CODE_END or (LOAD + #blob)) - LOAD, "code" }
        end
        local used = 0
        for _, s in ipairs(segs) do used = used + s[2] end
        if SYM.P3_PARSER_BASE and used < #blob then
            segs[#segs+1] = { SYM.P3_PARSER_BASE, #blob - used, "parser (org'd)" }
            used = #blob
        end
        -- ★★★★ REFUSE ON A MISMATCH rather than poke a partial program. A run list that does not
        -- account for every byte means the map and the image disagree, and the guest would then
        -- execute whatever the gap left behind.
        if used ~= #blob then
            w("★★★ the run list covers %d bytes of a %d-byte image -- map and image disagree",
              used, #blob)
            m:exit(); return
        end
        local pos = 1
        for _, s in ipairs(segs) do
            if s[2] < 0 then
                w("★★★ run '%s' has negative length -- stale map?", s[3]); m:exit(); return
            end
            for i = 0, s[2] - 1 do prog:write_u8(s[1] + i, blob:byte(pos + i)) end
            w("  poked %5d B -> $%04X  %s", s[2], s[1], s[3])
            -- ★★★★★ REMEMBER THE DISPATCH TABLES SO THEY CAN BE CHECKED AT THE END [T-P0-095].
            -- In the text configuration vm_tables.s is relocated to $0200-$0472, inside what the
            -- ENGINE's map reserves as the flood-fill seed stack ($0100-$0400) and which this
            -- probe shortens to $0100-$0200 to make room. **That is 626 bytes of VMOP_TAB and
            -- VMOP_ARGS living in a region another subsystem believes it owns.**
            -- ★★★★ A CORRUPTED DISPATCH TABLE IS LATENT UNTIL THE DAMAGED OPCODE IS REACHED, which
            -- is exactly the shape of a divergence that appears only when a command is fed: the
            -- render runs at cycle 9 and the wrong entry is not dispatched until cycle 100.
            -- ★★★ Comparing RAM against the bytes THIS run poked is the check; comparing against
            -- the file would be the same bytes one indirection further away.
            if s[3]:find("vm_tables") then
                _G._tab = { s[1], s[2], blob:sub(pos, pos + s[2] - 1) }
            end
            pos = pos + s[2]
        end
        w("program %d bytes in %d run(s); MMU slots pre-set $38..$3F", #blob, #segs)
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
                w("★★★ font FILE is %d bytes, expected 2048", #fd); m:exit(); return
            end
            -- ★★★★★ STAGE WHAT THE BUILD RESERVED, NOT WHAT THE FILE HOLDS. The text
            -- configuration uses a 128-glyph font (1,024 B) because the full 2 KB does not fit
            -- [p3b_probe.s, with font_high_census.py]. **The length comes from P3_FONT_BYTES, a
            -- symbol from this build's own map** -- a literal here would overrun P3_FONT by 1 KB
            -- into whatever follows it the moment the two disagree, which is the class of defect
            -- that put the font over the parser in the first place [AD-179].
            -- ★★ The FILE stays 256 glyphs: the upper half is simply not staged, and txt_blit
            -- folds any character >= 128 to space so nothing indexes past what was written.
            local nfont = SYM.P3_FONT_BYTES or #fd
            if nfont > #fd then
                w("★★★ build wants %d font bytes and the file has %d", nfont, #fd)
                m:exit(); return
            end
            for i = 1, nfont do prog:write_u8(SYM.P3_FONT + i - 1, fd:byte(i)) end
            w("font %d of %d bytes -> P3_FONT $%04X (%d glyphs)",
              nfont, #fd, SYM.P3_FONT, nfont // 8)
        end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
        state = "boot"; return
    end

    if state == "boot" then
        if prog:read_u8(GO) ~= 0 then return end
        w("guest at its gate (frame %d) -- all-RAM live, MMU up", frame)
        -- ★★★★★ THE SAME THREE READS, AFTER THE PROBE HAS REMAPPED AND BEFORE ANY INTERRUPT.
        -- At the DECB prompt the chain is $FFF8 -> $FEF7 (LBRA, wrapping to $010C) -> $010C
        -- (JMP $D8AF). The crash dump showed both hops holding other bytes -- but a crash with
        -- S=$F41C pushes wildly through high memory and could have destroyed $FEF7 ITSELF, so
        -- that dump cannot say whether the remap broke the chain or the crash did.
        -- ★★★ Read here, with IRQs still masked, the answer is unambiguous.
        do
            local v = prog:read_u8(0xFFF8) * 256 + prog:read_u8(0xFFF9)
            local b, c = {}, {}
            for i = 0, 4 do b[#b+1] = string.format("%02X", prog:read_u8(v + i)) end
            for i = 0, 2 do c[#c+1] = string.format("%02X", prog:read_u8(0x010C + i)) end
            w("AFTER TAKEOVER (IRQs still masked): $FFF8 -> $%04X, bytes %s; $010C = %s",
              v, table.concat(b, " "), table.concat(c, " "))
        end
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
        if stuck == 1 then
            spin = {}
            -- ★★★★★ SAMPLE THE TWO CLOCKS AT THE START OF A STALL [T-P0-087].
            -- tx_wait_dismiss detects a tick by watching hal_frame_lo (IRQ-driven) and advances
            -- the GAME clock (vm_vms) once per tick. A stall inside that loop has exactly three
            -- shapes and these two numbers separate them: hal_frame frozen means the $010C IRQ is
            -- not firing here, so no tick is ever seen; hal_frame moving with vm_vms frozen means
            -- the edge is missed; both moving means the deadline arithmetic is wrong.
            -- ★★★★ My own §4A census asserted hal_frame is "SELF-SERVICING -- the $010C IRQ
            -- advances it through a block". **That was an assumption and this measures it** [§2W].
            _G._stall0 = {
                frame = SYM.hal_frame_hi and rd16(SYM.hal_frame_hi) or -1,
                vms   = SYM.vm_vms and rd32(SYM.vm_vms) or -1,
            }
        end
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
            -- ★★★★★ THE INTERRUPT VECTOR CHAIN, READ FROM THE MACHINE [after the IRQ crash].
            -- On the CoCo3 an IRQ fetches its vector from $FFF8/$FFF9, which lands in ROM; the ROM
            -- stub then does JMP [$010C], and HAL_time_init patches $010C with a JMP to our
            -- handler. **In SAM all-RAM mode ($FFDF) that stub may not be there any more**, and
            -- then the CPU jumps into whatever RAM holds -- which is the S=$F41C, PC=$D7F5 crash.
            -- ★★★ Printed rather than reasoned about: this is three reads and it names which link
            -- of the chain is broken, where an argument about GIME modes would not.
            do
                local v = prog:read_u8(0xFFF8) * 256 + prog:read_u8(0xFFF9)
                local b = {}
                for i = 0, 4 do b[#b+1] = string.format("%02X", prog:read_u8(v + i)) end
                local c = {}
                for i = 0, 2 do c[#c+1] = string.format("%02X", prog:read_u8(0x010C + i)) end
                w("     IRQ vector $FFF8 -> $%04X; bytes there: %s", v, table.concat(b, " "))
                w("     $010C dispatch slot: %s  (expect 7E + handler address)",
                  table.concat(c, " "))
            end
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ §4A's ONE READ: IS THE SOURCE CONTAMINATED? [T-P0-088]
            -- p3_restore_box copies SHADOW -> VISIBLE. If box pixels reached the SHADOW plane,
            -- the restore is innocent and is faithfully re-rendering them. This samples the
            -- shadow WHILE THE BOX IS STILL UP -- the watchdog fires with var 21 unarmed, so the
            -- guest is parked in the wait loop and txt_close has not run.
            -- ★★★★ $44 is the discriminator and nothing else is: it is the box's line colour and
            -- the one value a picture cannot supply [P6.32 §7.4, where a difference count was
            -- confounded by the compositor and then by white-on-white].
            -- ★★★ The two clean rows are controls. A read that only looks at rows already known
            -- to be bad cannot tell contamination from coincidence.
            if SYM.txt_bgx then
                local function rd16s(a)
                    local v = rd16(a); if v >= 0x8000 then v = v - 0x10000 end; return v
                end
                local bx = rd16s(SYM.txt_bgx)
                local by = rd16s(SYM.txt_bgy) + (SYM.txb_yoff and rd16s(SYM.txb_yoff) or 0)
                local bw = rd16(SYM.txt_bgw)
                w("     ── §4A: the SHADOW plane, box still up (rect x=%d y=%d w=%d) ──",
                  bx, by, bw)
                w("     %-6s %8s %8s   %s", "row", "shadow", "visible", "verdict")
                for _, dr in ipairs({0, 5, 8, 13, 16, 2, 9}) do
                    local r = by + dr
                    local sred, vred = 0, 0
                    for c = math.max(0, bx), bx + bw - 1 do
                        local off = r * 160 + c
                        if off >= 0 and off < 26880 then
                            local sl, wi = off >> 13, off & 0x1FFF
                            prog:write_u8(0xFFA6, 2 + sl)          -- P3_BLK_SHADOW
                            if prog:read_u8(0xC000 + wi) == 0x44 then sred = sred + 1 end
                            prog:write_u8(0xFFA6, 40 + sl)         -- P3_BLK_VISIBLE
                            if prog:read_u8(0xC000 + wi) == 0x44 then vred = vred + 1 end
                        end
                    end
                    w("     %-6d %8d %8d   %s", r, sred, vred,
                      (dr == 2 or dr == 9) and "(control -- a clean row)" or "(residue row)")
                end
            end
            if _G._stall0 then
                local f1 = SYM.hal_frame_hi and rd16(SYM.hal_frame_hi) or -1
                local v1 = SYM.vm_vms and rd32(SYM.vm_vms) or -1
                w("     across the stall: hal_frame %d -> %d (%+d),  vm_vms %d -> %d (%+d)",
                  _G._stall0.frame, f1, f1 - _G._stall0.frame,
                  _G._stall0.vms, v1, v1 - _G._stall0.vms)
                w("     %s",
                  (f1 == _G._stall0.frame)
                    and "★★★ THE VBL COUNTER IS FROZEN -- the tick source never advances here, so"
                     .. " the wait loop can never see a tick and var 21 can never expire"
                    -- ★★★ NAME BOTH READINGS, because this branch has two causes and the fault
                    -- arm is one of them. "the tick edge is missed" was the only label here and
                    -- it is wrong for -DTEXT_FAULT_NOTICK, where the edge is seen and the clock
                    -- advance was deliberately removed. **A label that names the usual cause
                    -- instead of the actual one is the defect this project keeps paying for**
                    -- [§2W.3; said_gate.py printing the 6809 side as `oracle`].
                    or ((v1 == _G._stall0.vms)
                        and "★★★ hal_frame ADVANCES and vm_vms does NOT -- the wait loop is not"
                         .. " advancing the game clock. EXPECTED under -DTEXT_FAULT_NOTICK (that"
                         .. " is the injected fault); otherwise the tick edge is being missed"
                        or "★ both clocks advance -- the deadline arithmetic is the suspect"))
                if SYM.tx_wt_end then
                    w("     tx_wt_end=%d tx_wt_timed=%d (var21 as read at entry)",
                      rd16(SYM.tx_wt_end),
                      SYM.tx_wt_timed and prog:read_u8(SYM.tx_wt_timed) or -1)
                end
            end
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
                local vblk = SYM.ph_blk_vocab and prog:read_u8(SYM.ph_blk_vocab) or nil
                w("     MMU $FFA0-7: %s   (%s)", table.concat(sl, " "),
                  vblk and string.format("slot 5 = $A000, the vocabulary window; block %d", vblk)
                        or "slot 7 = $E000, the vocabulary window")
                -- ★★★★★ MAP IT BEFORE READING IT, OR THIS DUMP ACCUSES THE WRONG PLANE
                -- [T-P0-091]. Windowed, $A000 holds the vocabulary only during par_parse; a stall
                -- anywhere else leaves the OBJECT TABLE there, and eight bytes of object table
                -- printed under the label "vocab" would read as "the window has been overwritten"
                -- on every healthy run. **A diagnostic that labels a side must name the side it
                -- actually has** [§2W.3, and said_gate.py printing the 6809 under `oracle`].
                -- ★★★★ The restore is unconditional and comes from the guest's own byte: the
                -- probe is stalled, not dead, and leaving its object table unmapped would change
                -- what every line BELOW this one reads.
                local v5 = SYM.ph_blk_slot5 and prog:read_u8(SYM.ph_blk_slot5) or nil
                if vblk and v5 then prog:write_u8(SLOT5, vblk) end
                local got, want = {}, {}
                local bad = 0
                for i = 0, 7 do
                    local g = prog:read_u8(VOCAB + i)
                    got[#got+1] = string.format("%02X", g)
                    want[#want+1] = string.format("%02X", words:byte(i + 1))
                    if g ~= words:byte(i + 1) then bad = bad + 1 end
                end
                if vblk and v5 then prog:write_u8(SLOT5, v5) end
                w("     vocab $%04X: %s  (staged: %s)  %s", VOCAB,
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
            -- ═══════════════════════════════════════════════════════════════════════════
            -- ★★★★★ DOES THE PLANE ANIMATE WITHIN ONE RUN? [T-P0-122, after Jay's "no"]
            -- The end-of-run census proved the credit glyphs are IN the visible plane, and
            -- comparing a 20-cycle run against a 60-cycle run showed them at different rows.
            -- **But two runs are not motion.** Jay watches ONE run, and answered "no". So the
            -- question this samples is the one actually in dispute: within a single run, do the
            -- rows holding credit text CHANGE from cycle to cycle?
            -- ★★★ Narrow on purpose: columns 12-23 only, which is where display.v writes, and
            -- only every 5th cycle, which is the measured scroll cadence. A full-band census per
            -- cycle would remap slot 6 tens of thousands of times and change what it measures.
            -- ═══════════════════════════════════════════════════════════════════════════
            -- ★★★★★ POST A REAL KEY AT THE TITLE SCREEN [T-P0-124 §4C]. P6.70 posted VAR 19
            -- directly into the offline reference; this posts a KEY into the matrix and lets the
            -- guest's own scan publish it. **If the two do not produce the same outcome, the
            -- publish and the post are not equivalent and that difference is the finding.**
            -- ★★★★ IT CANNOT KEY ON P3_NKEY the way the typing loop does: that counter is
            -- incremented inside p3_poll_key, which is gated on txt_penab, and the title screen
            -- has called prevent.input. **The completion signal is VAR 19 itself.**
            -- ★★★ Re-posted while natkeyboard's queue is drained, for the reason the typing loop
            -- records: the guest looks once per CYCLE and a single post holds the key for a frame
            -- or two, so one post is about a one-in-five chance of being seen.
            if KEY_AT > 0 and n >= KEY_AT and not _G._key_done then
                local v19 = prog:read_u8(0x0800 + 19)
                if v19 ~= 0 then
                    _G._key_done = true
                    w("  ★ VAR 19 = $%02X at cycle %d, after %d post(s) -- the guest's own scan "
                      .. "published it", v19, n, _G._key_posts or 0)
                elseif m.natkeyboard.empty then
                    m.natkeyboard:post(KEY_CH)
                    _G._key_posts = (_G._key_posts or 0) + 1
                end
            end
            -- ═══════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE OBJECT TABLE, PER CYCLE [T-P0-126 §4B/§4C]. The game positions objects
            -- 11 and 12 at (121,161) and (73,166); we stage both at x=147. **Two different inputs
            -- producing one output** is either a read that does not vary per slot or a value that
            -- moved after the write -- and update_position's edge clamp is
            -- `x = SCRIPT_WIDTH - xSize` [vm_objects.s:429-442], which is the SAME number for two
            -- objects sharing a view. 160 - 13 = 147. **This watches x between the write and the
            -- draw to see whether it is clamped or never arrived.**
            -- ★★★★ VM_OBJ is MAP_PRI_SLICE = $A000 [p3b_probe.s:52], i.e. SLOT 5, so the host maps
            -- it for the read and puts it back from the guest's own ph_blk_slot5 -- the byte that
            -- exists precisely because a client may hold something there [mmu_phase.s:63-72].
            -- ★★★ Host-side only: no guest byte changes and the arms cannot move.
            if os.getenv("P3B_OBJTRACE") and SYM.ph_blk_slot5 then
                local every = tonumber(os.getenv("P3B_OBJTRACE")) or 10
                if n % every == 0 then
                    local keep = prog:read_u8(SYM.ph_blk_slot5)
                    prog:write_u8(0xFFA5, keep)
                    local function fld(slot, off) return prog:read_u8(0xA000 + slot * 32 + off) end
                    local parts = {}
                    for _, s in ipairs({0, 1, 11, 12}) do
                        parts[#parts+1] = string.format(
                            "[%d] x=%3d y=%3d xs=%2d view=%3d l=%d c=%d fl=%02X%02X dir=%d ss=%d"
                            .. " ct=%d/%d mo=%d wander=%d",
                            s, fld(s,0), fld(s,1), fld(s,2), fld(s,4), fld(s,5), fld(s,6),
                            fld(s,10), fld(s,11), fld(s,12), fld(s,13), fld(s,17), fld(s,16),
                            fld(s,19), fld(s,22))
                    end
                    w("  [obj] cycle %3d objtop=$%04X", n,
                      SYM.vm_objtop and rd16(SYM.vm_objtop) or 0)
                    for _, p in ipairs(parts) do w("        %s", p) end
                end
            end
            if os.getenv("P3B_SCROLL_TRACE") and n % 5 == 0 then
                local rows = {}
                for crow = 0, 20 do
                    local hit = false
                    for pr = crow * 8, crow * 8 + 7 do
                        for c = 48, 95 do
                            local off = pr * 160 + c
                            if off < 26880 then
                                local sl, wi = off >> 13, off & 0x1FFF
                                prog:write_u8(0xFFA6, 2 + sl)          -- shadow
                                local s = prog:read_u8(0xC000 + wi)
                                prog:write_u8(0xFFA6, 40 + sl)         -- visible
                                if prog:read_u8(0xC000 + wi) ~= s then hit = true break end
                            end
                        end
                        if hit then break end
                    end
                    if hit then rows[#rows+1] = crow end
                end
                w("  [scroll] cycle %3d: credit rows = %s", n,
                  #rows > 0 and table.concat(rows, ",") or "(none)")
            end
            -- ═══════════════════════════════════════════════════════════════════════════
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
            -- ★★★★★ THE SWEEP, ONE PARK, BEFORE ANYTHING IS READ [T-P0-103 §4B]. The probe is
            -- host-driven and has no end of its own, so the end-of-run sweep is a MODE the host
            -- asks for rather than something the guest can decide to do. Mode 4 runs
            -- res_ck_sweep and clears itself; this fires once and then never again.
            -- ★★★ It must happen BEFORE the readout below, or the report shows the counters as
            -- they were before the sweep ran -- which is AD-131's adjudicator reading a previous
            -- run's outputs, one frame apart instead of one run apart.
            if SYM.rck_seen and not _G._swept then
                _G._swept = true
                prog:write_u8(MODE, 4)
                prog:write_u8(GO, 1)
                w("  ★ res-checksum sweep requested (mode 4)")
                return
            end
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
            -- ★★★★★ THE RESTORE, IN THE SUMMARY AND NOT IN A GATED DIAGNOSTIC [T-P0-114].
            -- The first version of this readout went beside the composite counters, which sit
            -- inside a diagnostic block that does not run on an ordinary sweep -- so the number
            -- existed in the guest, the reader existed in the host, and NOTHING EVER PRINTED IT.
            -- ★★★ Two tasks owed this figure and neither produced one; a counter whose readout is
            -- behind a flag nobody passes is not published, it is merely written down [§2W].
            if SYM.p3_restbytes then
                local rb = 0
                for k = 0, 3 do rb = rb * 256 + prog:read_u8(SYM.p3_restbytes + k) end
                w("    restore %d bytes over %d cycles = %.1f per cycle%s",
                  rb, NCYC, rb / NCYC,
                  SYM.p3_prevn and string.format("  (%d rect(s) live at exit)",
                                                 prog:read_u8(SYM.p3_prevn)) or "")
            end
            -- ★★★★★ THE TEXT AREA, COUNTED [T-P0-116 AC-5]. Jay: "the text area is white again."
            -- The visual plane is 160x168 = 26,880 B (rows 0-167); rows 168-199 are the TEXT AREA
            -- and live in the same four blocks, at offsets 26,880..31,999 -- which is slice 3,
            -- offsets 2,304..7,423. ★★★ p3_black_visible blacks all four slices at init, so a
            -- non-zero count here means something REPAINTED the text area after init, and before
            -- T-P0-116 that something was p3_present copying the picture clear's white across.
            -- ★★ Mapping slot 6 here is safe and is what the plane dump at the foot of this file
            -- already does: the DISPLAY follows VOFFSET, not slot 6, so remapping it shows nothing.
            do
                local BV = 40                       -- P3_BLK_VISIBLE
                prog:write_u8(SLOT6, BV + 3)        -- visible slice 3 -> $C000
                local nonzero, first, firstv = 0, nil, nil
                for off = 2304, 2304 + 5120 - 1 do
                    local v = prog:read_u8(FB_BASE + off)
                    if v ~= 0 then
                        nonzero = nonzero + 1
                        if not first then first, firstv = off - 2304, v end
                    end
                end
                w("    text area rows 168-199: %d of 5120 bytes non-black%s",
                  nonzero,
                  first and string.format("   first at +%d = $%02X", first, firstv) or "  ★ ALL BLACK")
            end
            -- ═══════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE SCROLL BAND [T-P0-122 §4C]. The title credits are drawn by display.v
            -- at CHARACTER ROWS 6-18, COLUMN 12 -- measured, not assumed [pic_order.py over 80
            -- cycles]. Those rows are INSIDE the 21-row picture, so a "non-black" census like
            -- the one above is meaningless here: the picture fills them with colour.
            -- ★★★★★ THE DISCRIMINATOR IS VISIBLE vs SHADOW. The shadow holds the picture exactly
            -- as pic_render_at drew it and is never written again after cycle 1 [draw.pic runs
            -- once -- measured]. **So every byte where visible differs from shadow is something
            -- drawn ON TOP: a glyph, or a sprite.** That is the same comparison the restore
            -- check makes, against the same two block numbers -- one producer [§2O.1].
            -- ★★★ PER CHARACTER ROW, because "how many" cannot tell a scrolling list from a
            -- sprite and a per-row profile can: the credits occupy one row each, at a fixed
            -- column, and a sprite is a compact block.
            -- ★★ Gated: it remaps slot 6 several thousand times and is a diagnostic, not a gate.
            if os.getenv("P3B_SCROLL") then
                local BLK_VIS, BLK_SHA = 40, 2
                local C0 = 12 * 4          -- column 12, TXT_VW = 4 bytes per character cell
                w("    scroll band, visible vs shadow (cols 12-39, = drawn ON TOP of the picture):")
                local total = 0
                for crow = 0, 20 do
                    local n, firstc = 0, nil
                    for pr = crow * 8, crow * 8 + 7 do
                        for c = C0, 159 do
                            local off = pr * 160 + c
                            if off < 26880 then
                                local sl, wi = off >> 13, off & 0x1FFF
                                prog:write_u8(0xFFA6, BLK_SHA + sl)
                                local s = prog:read_u8(0xC000 + wi)
                                prog:write_u8(0xFFA6, BLK_VIS + sl)
                                if prog:read_u8(0xC000 + wi) ~= s then
                                    n = n + 1
                                    if not firstc then firstc = c end
                                end
                            end
                        end
                    end
                    total = total + n
                    if n > 0 then
                        w("       char row %2d: %4d bytes differ   first at byte %d (col %d)",
                          crow, n, firstc, math.floor(firstc / 4))
                    end
                end
                w("       TOTAL %d bytes drawn over the picture in rows 0-20", total)
                if total == 0 then
                    w("       ★★★ NOTHING is drawn over the picture -- the glyphs were NEVER"
                      .. " WRITTEN, so the loss is on the WRITE path, not an overwrite")
                end
            end
            -- ★★★★★ THE EGO'S LOOP, AS A NUMBER [T-P0-115 §4C(2)]. "He faces the other way" is an
            -- eye-gate answer; this is the same fact as a loop index, and the oracle's own tables
            -- predict it exactly: loopTable4[3] = 0 (RIGHT) and loopTable4[7] = 1 (LEFT), and
            -- loopTable2 agrees on both [view.cpp:719-725]. ★★★ p3_spr is 6 bytes a row --
            -- x, y, prio, view, loop, cel -- and slot 0 is the ego.
            -- ★★★★★ EVERY STAGED SPRITE, NOT ONLY THE EGO [after Jay: "there was no alligators"].
            -- Room 1 stages four objects and the compositor is demonstrably running (250 B/cycle of
            -- restore traffic), so "no alligators" is not a drawing failure -- it is a question
            -- about WHICH objects are staged and what happens to their cels. The ego line below
            -- prints slot 0; this prints all of them, with the compositor's own verdict counters.
            -- ★★★ co_rejkey / co_rejpri are the two ways a cel can be drawn and invisible: every
            -- pixel transparent, or every pixel losing the priority test. **They separate "never
            -- queued" from "queued and rejected", which is the whole question here.**
            if os.getenv("P3B_SPRITES") and SYM.p3_spr and SYM.p3_nspr then
                local n = prog:read_u8(SYM.p3_nspr)
                w("    staged sprites: %d", n)
                for i = 0, math.min(n, 16) - 1 do
                    local b = SYM.p3_spr + i * 6
                    w("       [%d] x=%3d y=%3d prio=%2d view=%3d loop=%d cel=%d",
                      i, prog:read_u8(b), prog:read_u8(b+1), prog:read_u8(b+2),
                      prog:read_u8(b+3), prog:read_u8(b+4), prog:read_u8(b+5))
                end
                if SYM.co_tested then
                    w("    compositor: tested=%d written=%d rejected key=%d pri=%d  vc_err=%d",
                      rd32(SYM.co_tested), rd32(SYM.co_written), rd32(SYM.co_rejkey),
                      rd32(SYM.co_rejpri), SYM.vc_err and prog:read_u8(SYM.vc_err) or -1)
                end
            end
            if SYM.p3_spr and SYM.p3_nspr and prog:read_u8(SYM.p3_nspr) > 0 then
                local b = SYM.p3_spr
                w("    ego: x=%d y=%d view=%d LOOP=%d cel=%d%s",
                  prog:read_u8(b), prog:read_u8(b + 1), prog:read_u8(b + 3),
                  prog:read_u8(b + 4), prog:read_u8(b + 5),
                  SYM.p3_ndirs and string.format("   dir-keys accepted %d, last dir %d",
                                                 prog:read_u8(SYM.p3_ndirs),
                                                 SYM.p3_newdir and prog:read_u8(SYM.p3_newdir) or -1) or "")
            end
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
            -- ★★★★★ THE HALT, DECODED [T-P0-087 §4A]. vm_res_fail does `lda res_err / ora #$F0`
            -- (vm_run.s:114), so a vm_badop of $Fn means **the VM HALTED ON A RESOURCE BIND** and
            -- n is the RES_E_* code -- $F6 is RES_E_DEPTH, more than RES_MAXDEPTH (8) resources
            -- held at once. ★★★★ P6.30 read vm_quit=1 as proof that the instruction after print.v
            -- had executed; it is the HALT setting vm_quit, and the VM never reached print.
            -- ★★ Printed as a decoded line rather than a raw byte so the next reader does not have
            -- to re-derive it [§2W.3: a diagnostic that reports a number nobody can read is one
            -- step from a diagnostic nobody checks].
            if SYM.vm_badop then
                local bo = prog:read_u8(SYM.vm_badop)
                if bo >= 0xF0 and bo <= 0xF7 then
                    w("    ★★★ VM HALTED ON A RESOURCE BIND: vm_badop=$%02X -> res_err %d"
                      .. " (%s), logic %d, res_depth %d", bo, bo - 0xF0,
                      ({[1]="EMPTY",[2]="SIG",[3]="RANGE",[4]="BIG",[5]="FULL",[6]="DEPTH"})[bo-0xF0]
                        or "?",
                      SYM.vm_badlogic and prog:read_u8(SYM.vm_badlogic) or -1,
                      SYM.res_depth and prog:read_u8(SYM.res_depth) or -1)
                end
            end
            -- ★★★★★ vm_restart AND res_err, BOTH LIVE [T-P0-096 §4D]. P6.39 concluded restart.game
            -- had not run from vm_quit and vm_badop, which vm_probe.s says cannot answer it; and
            -- RES_E_BIG went six tasks unmentioned because only the sticky P3_ERR was published.
            -- **Two wrong readings from two unpublished bytes**, so both are on this line now.
            if SYM.vm_restart then
                w("    vm_restart=%d (restart.game executed) | res_err=%d (LIVE; P3_ERR is sticky)",
                  prog:read_u8(SYM.vm_restart), prog:read_u8(SYM.res_err or 0))
            end
            w("    var0=%d flag0=$%02X  vm_quit=%d vm_badop=$%02X vm_cycle=%d vm_tdelay=%d res_err=%d",
              prog:read_u8(0x0800), prog:read_u8(0x0900),
              prog:read_u8(SYM.vm_quit or 0), prog:read_u8(SYM.vm_badop or 0),
              rd16(SYM.vm_cycle or 0), prog:read_u8(SYM.vm_tdelay or 0),
              prog:read_u8(SYM.res_err or 0))
            w("    final room %d, sprites %d, err %d, status=$%02X",
              prog:read_u8(ROOM), prog:read_u8(NSPR), prog:read_u8(ERR), prog:read_u8(STATUS))
            -- ★★★★★ THE PICTURE OPCODES' RECEIPT [T-P0-121]. draw.pic sets p3_drew and clears
            -- p3_shown; show.pic sets p3_shown [op_cmd.cpp:1210,1218]. **drew=1 shown=1 means the
            -- GAME ordered both halves**; drew=1 shown=0 is the -DP3B_FAULT_SHOWPIC arm, where the
            -- room is rendered into the shadow and never revealed -- and it is the pair that makes
            -- that fault a byte result instead of only something to look at [§2W].
            -- ★★★ drew=0 is the loud one: the game issued no draw.pic at all, which after this
            -- task means a BLACK SCREEN rather than a picture arriving late.
            -- ★★ UNCONDITIONAL, matching the unconditional definition of both bytes.
            -- ★★★★★ THE VERDICT IS COMPUTED FROM THE BYTES, NOT PRINTED BESIDE THEM. The first
            -- version ended every line with "(1/1 = the game ordered both)" including the run
            -- where it was 1/0 -- **a label that cannot be wrong is not a reading** [§2W.3], and
            -- the fault arm's own red would have shipped wearing a green caption.
            -- ★★★★★ WHAT THE SCAN PUBLISHED INTO VAR 19 [T-P0-124 AC-1]. Read from the guest's
            -- sticky copy, not from VAR 19 itself: vm_post_cycle clears VAR 19 every cycle, so
            -- sampling the variable at the park reports zero however many keys were published.
            if SYM.p3_varkey and SYM.p3_nvarkey then
                local k, nk = prog:read_u8(SYM.p3_varkey), prog:read_u8(SYM.p3_nvarkey)
                w("    VAR 19 publishes: %d key(s), last $%02X%s", nk, k,
                  nk == 0 and "   ★★★ NONE -- have.key can never fire" or "")
            end
            if SYM.p3_drew and SYM.p3_shown then
                local drew, shown = prog:read_u8(SYM.p3_drew), prog:read_u8(SYM.p3_shown)
                local verdict
                if drew == 1 and shown == 1 then
                    verdict = "rendered AND revealed"
                elseif drew == 1 then
                    verdict = "★★★ RENDERED, NEVER REVEALED -- show.pic did not run"
                elseif shown == 1 then
                    verdict = "★★★ REVEALED WITHOUT A RENDER -- impossible ordering"
                else
                    verdict = "★★★ NO PICTURE ORDERED AT ALL -- the screen should be black"
                end
                w("    picture: draw.pic drew=%d  show.pic shown=%d   %s", drew, shown, verdict)
                -- ★★★★★ THE FETCH FAILURE'S CONTEXT [T-P0-121]. draw.pic runs INSIDE a running
                -- logic, so the picture must fit the arena ON TOP of whatever the VM is holding.
                -- res_depth at the failure is the number that says so.
                -- ★★★★ THE MARGIN, on every run. The arena is $3000-$6000 (12 KB); a picture
                -- needs room ABOVE whatever the VM is holding when draw.pic executes.
                if SYM.p3_drawtop then
                    local top = rd16(SYM.p3_drawtop)
                    local ccur = SYM.p3_drawccur and rd16(SYM.p3_drawccur) or 0
                    local nf = SYM.p3_nfall and rd16(SYM.p3_nfall) or 0
                    -- ★★★★★ FREE = res_ccur - res_top. The stack rises from RES_ARENA and the
                    -- cache descends toward it [res_core.s:281-285]; the arena's END bounds
                    -- NEITHER. The first version of this line measured against the end and
                    -- reported "0 bytes free" for an empty arena [§2W.3].
                    w("    arena at draw.pic: res_top=$%04X cache floor=$%04X depth=%d"
                      .. "  -> %d bytes free   deferred to depth 0: %d",
                      top, ccur, prog:read_u8(SYM.p3_drawdepth), ccur - top, nf)
                    -- ★★★★ A DEFERRED RENDER IS THE OLD ORDERING. Named here so a run that
                    -- recovered does not read as a run that never needed to [§2W].
                    if nf > 0 then
                        w("    ★★ %d room(s) rendered AFTER the logic returned -- the arena was"
                          .. " full at draw.pic, so those rooms have the PRE-TASK ordering", nf)
                    end
                end
                if SYM.p3_errpic then
                    local ep = prog:read_u8(SYM.p3_errpic)
                    if ep ~= 0xFF then
                        local et = rd16(SYM.p3_errtop)
                        local ec = SYM.p3_errccur and rd16(SYM.p3_errccur) or 0
                        w("    ★★★ picture %d was REFUSED at draw.pic: res_top=$%04X"
                          .. " cache floor=$%04X depth=%d -> %d bytes free",
                          ep, et, ec, prog:read_u8(SYM.p3_errdepth), ec - et)
                        w("        (the LOGIC CACHE had taken the arena; res_open may only evict"
                          .. " at depth 0 [res_core.s:309-314])")
                    end
                end
            end
            -- ★★★ THE TRAJECTORY AND THE ERRORS, PRINTED TOGETHER so a room change and a failed
            -- fetch on the same cycle are visible as one event rather than two lines apart.
            -- ★★★★ ONCE. This whole block re-runs on every frame of the hold, and the log already
            -- carries 49,877 copies of "final room" for that reason -- a fact this file warns about
            -- in two other places and which my first version of these two lines tripled.
            if not _G._traj_said then
                _G._traj_said = true
                if _G._rooms then
                    local t = {}
                    for _, e in ipairs(_G._rooms) do
                        t[#t + 1] = string.format("c%d->%d[logic %d,flag5=%d]",
                                                  e[1], e[2], e[3], e[4])
                    end
                    w("    rooms: %d transition(s)  %s", #_G._rooms, table.concat(t, "  "))
                end
                if _G._re and #_G._re > 0 then
                    for _, e in ipairs(_G._re) do
                        w("    res_err=%d written at PC $%04X, cycle %d, room %d",
                          e[1], e[2], e[3], e[4])
                    end
                elseif _G._retap then
                    w("    res_err: never written non-zero during the run")
                else
                    w("    res_err: NO TAP INSTALLED -- this run staged no vocabulary, so the "
                      .. "watch in stage() never ran")
                end
                -- ★★★★★ ARE THE DISPATCH TABLES STILL THE BYTES WE POKED? [T-P0-095 §4B/AC-4]
                if _G._tab then
                    local base, len, want = _G._tab[1], _G._tab[2], _G._tab[3]
                    local bad, first = 0, nil
                    for i = 0, len - 1 do
                        if prog:read_u8(base + i) ~= want:byte(i + 1) then
                            bad = bad + 1
                            if not first then first = base + i end
                        end
                    end
                    w("    vm_tables at $%04X..$%04X: %d of %d bytes differ from what was poked%s",
                      base, base + len - 1, bad, len,
                      bad == 0 and "  -- ★ intact"
                               or string.format("  -- ★★★ FIRST AT $%04X", first))
                end
                -- ★★★★★ THE CYCLE BODY, BRACKETED [T-P0-097 §4C]. Phase 2 is after the feed and
                -- before interpret; phase 4 is after vm_post_cycle.
                if _G._ph then
                    w("    cycle %d, phase by phase  (flag2 = ENTERED_CLI, bit 2 of flag byte 0)",
                      PHASETAP)
                    for _, e in ipairs(_G._ph) do
                        w("      P3_CYCLE=%d phase %d : flags0=$%02X flag2=%d  par_egon=%d "
                          .. "par_cli=%d  vm_restart=%d  var0=%d var88=%d",
                          e[8], e[1], e[2], (e[2] >> 2) & 1, e[3], e[4], e[5], e[6], e[7])
                    end
                end
                -- ★★★★★ THE said() ROWS [T-P0-098 §4B]. Four bytes each: ip (which said), result,
                -- and a packed byte carrying flag 4 AS READ ON ENTRY and flag 2.
                -- ★★★ flag 4 on entry is the guard that should reject every said() after the first
                -- match in a cycle [parser.s:474]. A row with result=1 and f4=1 would be that
                -- guard failing; a second result=1 in one cycle is the same thing one level up.
                if SYM.vm_sd_n and SYM.vm_sd_buf then
                    local n = prog:read_u8(SYM.vm_sd_n)
                    w("    said() rows for vm_cycle %d : %d", SAIDAT or -1, n)
                    -- ★★★★ FIVE BYTES A ROW SINCE T-P0-101: the fifth is vm_curlogic. P6.43's table
                    -- attributed rows to logics by their ip ORDER, and the run re-enters logic 0
                    -- after logic 102, so the ordering was an assumption this column replaces.
                    for i = 0, n - 1 do
                        local b = SYM.vm_sd_buf + i * 5
                        local ip = prog:read_u8(b) * 256 + prog:read_u8(b + 1)
                        local res = prog:read_u8(b + 2)
                        local fl = prog:read_u8(b + 3)
                        w("      said logic %-3d @ip $%04X  result=%d  flag4_on_entry=%d  flag2=%d",
                          prog:read_u8(b + 4), ip, res, fl & 1, (fl >> 1) & 1)
                    end
                end
                -- ★★★★★ EVERY `if` IN ONE LOGIC, IN ONE CYCLE [T-P0-101 §4A]. Six bytes a row: the
                -- expression's ip, flag byte 0 AS THE EXPRESSION SAW IT, the result, and where the
                -- branch left ip.
                -- ★★★★★ AN ABSENT ROW IS A RESULT. If the recorder is armed for logic 102 and no row
                -- carries the guard's ip, that guard was never evaluated -- which is one of the two
                -- stories P6.45 could not separate, and it is unreadable except against the list of
                -- the expressions that WERE evaluated.
                -- ★★★★★ DID THE COMPOSITOR ACTUALLY BLIT? [T-P0-105, after Jay saw no sprites]
                -- CP_BLITS has existed since the compositor was wired and **nothing has ever read
                -- it**. "sprites 4" is the STAGING count; this is the number of cels actually
                -- composited, and the two are different questions [§2W].
                do
                    local b = 0x0020 + 76       -- MAP_STATUS+76, CP_BLITS [p3b_probe.s:247]
                    w("    CP_BLITS (cels actually composited): %d%s",
                      prog:read_u8(b) * 256 + prog:read_u8(b + 1),
                      SYM.vc_err and string.format("   vc_err=%d  last cel %dx%d",
                        prog:read_u8(SYM.vc_err), prog:read_u8(SYM.vc_w or 0),
                        prog:read_u8(SYM.vc_h or 0)) or "")
                    -- ★★★★★ THE TRUNCATION BOUND AND THE POINTER IT REFUSED [T-P0-106 §4A].
                    -- vc_src < vc_srcend is the only test VC_E_TRUNC makes [view_cel.s:268].
                    if SYM.vc_srcend then
                        local function rd(s) return prog:read_u8(s) * 256 + prog:read_u8(s + 1) end
                        w("      vc_view=$%04X  vc_src=$%04X  vc_srcend=$%04X%s",
                          rd(SYM.vc_view), rd(SYM.vc_src), rd(SYM.vc_srcend),
                          rd(SYM.vc_srcend) == 0 and "   ★★★ NEVER SET -- every cel truncates on its first byte" or "")
                    end
                    -- ★★★★★ DID ANYTHING LAND OUTSIDE THE PLANE? [T-P0-107 AC-4]. The flat
                    -- compositor put row 100 at $FE80 and row 167 at $2860; the vector stubs and
                    -- the code region are the two places that proved it. **Checked, not assumed.**
                    do
                        local v = {}
                        for k = 0, 4 do v[#v + 1] = string.format("%02X", prog:read_u8(0xFEF7 + k)) end
                        w("      $FEF7 (the IRQ stub the flat walk reached at row 100): %s",
                          table.concat(v, " "))
                    end
                    -- ★★★★★ WHICH SPRITES ARE STAGED, so "2 of 4 composite" becomes named views
                    -- [T-P0-107, after Jay saw the flags animate and no ego]. p3_spr is 6 bytes a
                    -- row: x, y, prio, view, loop, cel.
                    if SYM.p3_spr and SYM.p3_nspr then
                        local n = prog:read_u8(SYM.p3_nspr)
                        w("      staged sprites: %d", n)
                        for s = 0, math.min(n, 8) - 1 do
                            local b = SYM.p3_spr + s * 6
                            w("        [%d] x=%-3d y=%-3d prio=%-2d view=%-3d loop=%d cel=%d",
                              s, prog:read_u8(b), prog:read_u8(b + 1), prog:read_u8(b + 2),
                              prog:read_u8(b + 3), prog:read_u8(b + 4), prog:read_u8(b + 5))
                        end
                    end
                    -- ★★★★★ WHICH SCREEN ROWS ACTUALLY GOT PIXELS [T-P0-108, after Jay reported
                    -- "missing every other row of pixels" on both sprites]. A per-row count over
                    -- the staged sprites' bounding boxes turns an impression into a pattern: if
                    -- the compositor's row advance were doubled, the populated rows alternate.
                    -- ★★★ Reads the visible plane through the window, one slice at a time, which
                    -- is the same idiom the box-rect check uses below.
                    if SYM.p3_spr and SYM.p3_nspr then
                        local BV = 40                       -- P3_BLK_VISIBLE
                        for s = 0, math.min(prog:read_u8(SYM.p3_nspr), 4) - 1 do
                            local b = SYM.p3_spr + s * 6
                            local sx, sy = prog:read_u8(b), prog:read_u8(b + 1)
                            -- ★★★★★ AND THE NIBBLES [T-P0-109 AC-5]. A plane byte must hold the
                            -- colour in BOTH halves -- pic_fill.s reads "either nibble; equal by
                            -- construction". A byte whose halves differ is a half-black pixel,
                            -- which is what Jay saw. **Counted, not inspected.**
                            local rows, eq, ne, sample = {}, 0, 0, nil
                            for r = math.max(0, sy - 20), math.min(167, sy) do
                                local n = 0
                                for c = sx, math.min(159, sx + 40) do
                                    local off = r * 160 + c
                                    prog:write_u8(0xFFA6, BV + (off >> 13))
                                    local v = prog:read_u8(0xC000 + (off & 0x1FFF))
                                    if v ~= 0 then
                                        n = n + 1
                                        if (v >> 4) == (v & 0x0F) then eq = eq + 1
                                        else ne = ne + 1; sample = sample or v end
                                    end
                                end
                                rows[#rows + 1] = (n > 0) and tostring(math.min(n, 9)) or "."
                            end
                            w("      sprite %d (view %d) at x=%d y=%d, rows %d..%d: %s",
                              s, prog:read_u8(b + 3), sx, sy,
                              math.max(0, sy - 20), sy, table.concat(rows))
                            w("        nibbles: %d equal, %d SPLIT%s", eq, ne,
                              sample and string.format("  (e.g. $%02X -- half black)", sample) or "")
                        end
                    end
                    -- ★★★★★ tested / rejected / WRITTEN. The priority band decides what is DRAWN,
                    -- not what is examined -- co_tested was the wrong counter to quote at
                    -- T-P0-107 and would have been the wrong one to claim a fix with here.
                    for _, c in ipairs({ { "tested ", SYM.co_tested }, { "rej_key", SYM.co_rejkey },
                                         { "rej_pri", SYM.co_rejpri }, { "WRITTEN", SYM.co_written } }) do
                        if c[2] then
                            local t = 0
                            for k = 0, 3 do t = t * 256 + prog:read_u8(c[2] + k) end
                            w("      co_%s : %d", c[1], t)
                        end
                    end
                    -- ★★★★★ THE RESTORE, COUNTED [T-P0-113, owed by T-P0-112's AC-3/AC-4].
                    -- p3_restbytes is bytes actually copied shadow -> live, both planes, summed
                    -- over the run; p3_prevn is how many rectangles the LAST frame left to put
                    -- back. ★★★ The pair is what distinguishes "the restore ran" from "the
                    -- restore ran and had something to do": a non-zero rect count with zero
                    -- bytes would be a walk that mapped and copied nothing, which is exactly the
                    -- shape a clamped span or a bad slice calc would produce.
                    -- ★★ Under -DP3B_FAULT_NORESTORE the symbols still exist and both read ZERO,
                    -- which is the fault arm's signature and is checked rather than assumed.
                    if SYM.p3_restbytes then
                        local rb = 0
                        for k = 0, 3 do rb = rb * 256 + prog:read_u8(SYM.p3_restbytes + k) end
                        local rn = SYM.p3_prevn and prog:read_u8(SYM.p3_prevn) or -1
                        w("      restore : %d bytes put back, %d rect(s) live from last frame", rb, rn)
                        if rb == 0 then
                            w("      ★★★ RESTORE COPIED NOTHING -- either the fault arm is linked "
                              .. "or the walk is not reaching the planes")
                        end
                    end
                end
                if _G._arena_hi then
                    local p = _G._arena_hi_parts
                    w("    arena peak (park-sampled, a LOWER BOUND): %d B of %d used"
                      .. "  -- stack %d + cache %d, at cycle %d;  %d B free",
                      _G._arena_hi, 0xA000 - 0x6000, p[1], p[2], p[3],
                      (0xA000 - 0x6000) - _G._arena_hi)
                end
                -- ★★★★★ THE RESOURCE CHECKSUM [T-P0-103]. rck_seen is printed FIRST and always:
                -- "0 mismatches" from a checker that performed 0 verifications is not a result,
                -- and this project has had that exact shape five times [§2W].
                if SYM.rck_seen and SYM.rck_bad then
                    local seen = prog:read_u8(SYM.rck_seen) * 256 + prog:read_u8(SYM.rck_seen + 1)
                    local noted = prog:read_u8(SYM.rck_noted) * 256 + prog:read_u8(SYM.rck_noted + 1)
                    local bad = prog:read_u8(SYM.rck_bad)
                    w("    res-checksum: %d baselined, %d verified, %d mismatch(es), "
                      .. "%d sweep skip(s)%s",
                      noted, seen, bad, prog:read_u8(SYM.rck_skipped),
                      prog:read_u8(SYM.rck_full) ~= 0 and "  ★★★ TABLE FULL -- coverage reduced" or "")
                    if seen == 0 then
                        w("      ★★★ ZERO VERIFICATIONS -- this run proves NOTHING about resource bytes")
                    end
                    -- ★★★★★ THE TABLE ITSELF, ALWAYS. A mismatch row is a claim ABOUT an entry,
                    -- and the first run of this instrument produced rows naming a 35,727-byte
                    -- LOGIC at an address inside the code region -- impossible on their face.
                    -- **Printing the table is what separates "the resource changed" from "the
                    -- bookkeeping is wrong"**, and without it the only way to tell them apart is
                    -- to read the assembly and guess [§2W.3].
                    -- ★★ RAW, NOT FORMATTED. A `for` loop building a seven-column line from seven
                    -- reads is one nil away from throwing INSIDE the frame callback, which this
                    -- file has been killed by three times and which presents as the output simply
                    -- stopping. Four hex rows cannot throw and say the same thing.
                    for _, r in ipairs({ { "type", SYM.rck_type }, { "idx ", SYM.rck_idx },
                                         { "live", SYM.rck_live }, { "base", SYM.rck_base },
                                         { "len ", SYM.rck_len },  { "sum ", SYM.rck_sum },
                                         { "rng0", SYM.rck_ring }, { "rng1", SYM.rck_ring + 16 },
                                         { "scal", SYM.rck_n } }) do
                        local h = {}
                        for k = 0, 15 do h[#h + 1] = string.format("%02X", prog:read_u8(r[2] + k)) end
                        w("      raw %s $%04X: %s", r[1], r[2], table.concat(h, " "))
                    end
                    local SITE = { [1] = "later bind", [2] = "before release", [3] = "sweep" }
                    for i = 0, bad - 1 do
                        local b = SYM.rck_ring + i * 14
                        local rtype = prog:read_u8(b)
                        local ridx  = prog:read_u8(b + 1)
                        local base  = prog:read_u8(b + 2) * 256 + prog:read_u8(b + 3)
                        local len   = prog:read_u8(b + 4) * 256 + prog:read_u8(b + 5)
                        local exp   = prog:read_u8(b + 6) * 256 + prog:read_u8(b + 7)
                        local act   = prog:read_u8(b + 8) * 256 + prog:read_u8(b + 9)
                        local site  = prog:read_u8(b + 10)
                        local cyc   = prog:read_u8(b + 11) * 256 + prog:read_u8(b + 12)
                        w("      ★★★ type %d index %-3d at $%04X len %-5d  expected $%04X got $%04X"
                          .. "  (%s, cycle %d)",
                          rtype, ridx, base, len, exp, act, SITE[site] or "?", cyc)
                        -- ★★ The BYTES are dumped in the park loop, at detection, not here: by the
                        -- time this report runs the arena has been reused and the address holds
                        -- something else entirely. See the park callback.
                    end
                end
                if SYM.vm_if_n and SYM.vm_if_buf then
                    local n = prog:read_u8(SYM.vm_if_n)
                    w("    `if` rows for logic %d in vm_cycle %d : %d",
                      IFLOGIC or -1, SAIDAT or -1, n)
                    -- ★★★★★ THE PORT'S OWN FIRST 64 BYTES of the logic, against which
                    -- `python harness/tools/logic_bytes.py <game> <n>` is the file's side.
                    if n > 0 and SYM.vm_if_snap and SYM.vm_if_code then
                        w("      copy at $%04X, vm_codelen %d",
                          prog:read_u8(SYM.vm_if_code) * 256 + prog:read_u8(SYM.vm_if_code + 1),
                          prog:read_u8(SYM.vm_if_clen) * 256 + prog:read_u8(SYM.vm_if_clen + 1))
                        for row = 0, 15 do
                            local h = {}
                            for k = 0, 15 do
                                h[#h + 1] = string.format("%02X", prog:read_u8(SYM.vm_if_snap + row * 16 + k))
                            end
                            w("      %04X  %s", row * 16, table.concat(h, " "))
                        end
                    end
                    for i = 0, n - 1 do
                        local b = SYM.vm_if_buf + i * 12
                        local ip = prog:read_u8(b) * 256 + prog:read_u8(b + 1)
                        local fl = prog:read_u8(b + 2)
                        local res = prog:read_u8(b + 3)
                        local ipa = prog:read_u8(b + 4) * 256 + prog:read_u8(b + 5)
                        -- ★★★★★ THE BYTES AT ip_after, FROM THE PORT'S OWN COPY of the logic.
                        -- Compare them against logic_bytes.py's dump of the same offset: the two
                        -- disagreeing is a resource defect, the two agreeing with a wrong jump is
                        -- an arithmetic one, and no other instrument separates those.
                        local raw = {}
                        for k = 0, 5 do raw[#raw + 1] = string.format("%02X", prog:read_u8(b + 6 + k)) end
                        -- ★★★ res 255 = the evaluator returned through exit_all and consumed no
                        -- branch word; ip_after is meaningless there and is labelled so.
                        local arm = (res == 255) and "exit_all"
                                    or ((res == 1) and "TAKEN (fell into the block)"
                                                   or "not taken (skipped the block)")
                        w("      if @expr $%04X  flags0=$%02X  flag2=%d flag4=%d  result=%s  ip_after=$%04X  [%s]  %s",
                          ip, fl, (fl >> 2) & 1, (fl >> 4) & 1,
                          (res == 255) and "--" or tostring(res), ipa,
                          table.concat(raw, " "), arm)
                    end
                end
                -- ★★★★★ EVERY WRITER OF VAR 0 IN THE TARGET CYCLE, WITH ITS CALLER. Four bytes a
                -- row: the value, the return address of the vm_setvar call, and the logic that was
                -- running. **The caller address is the answer** -- the build's .lst names it.
                if SYM.vm_v0_n and SYM.vm_v0_buf then
                    local n = prog:read_u8(SYM.vm_v0_n)
                    w("    var-%d writers in vm_cycle %d : %d", WATCHVAR, SAIDAT or -1, n)
                    for i = 0, n - 1 do
                        local b = SYM.vm_v0_buf + i * 8
                        local fl = prog:read_u8(b + 7)
                        -- ★★★ p0/p1 ARE THE OPERAND BYTES the handler was about to read. For
                        -- lindirect.v ($09) p0 names the variable holding the DESTINATION's
                        -- number, which is the value this row's filter already proves was
                        -- WATCHVAR -- so "var[p0] == WATCHVAR" is measured, not inferred.
                        w("      var%d <- %-3d  opcode $%02X  logic %-3d  p0=%-3d p1=%-3d  "
                          .. "flag2=%d flag4=%d  caller $%04X",
                          WATCHVAR, prog:read_u8(b), prog:read_u8(b + 4), prog:read_u8(b + 3),
                          prog:read_u8(b + 5), prog:read_u8(b + 6),
                          (fl >> 2) & 1, (fl >> 4) & 1,
                          prog:read_u8(b + 1) * 256 + prog:read_u8(b + 2))
                    end
                end
                if _G._v0 then
                    for _, e in ipairs(_G._v0) do
                        w("    var0 <- %d  by PC $%04X at cycle %d", e[1], e[2], e[3])
                    end
                end
            end
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE COMMAND LINE's VERDICT LINE [T-P0-092]. Printed on EVERY run that links
            -- the prompt, not only on typing runs, because "the prompt is enabled" and "nobody
            -- typed" are different facts and a row that conflates them cannot fail usefully.
            -- ★★★ The wording is what p3b_show.ps1 adjudicates on, so it is exact rather than
            -- descriptive: NO KEYS REACHED / NOT PARSED are the two failures.
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ AC-3's OBSERVABLE: INK ON ROW 22, COUNTED [T-P0-093]. The command line is at
            -- character row 22 -- pixel rows 176-183, byte offsets 28,160-29,439 of the visible
            -- plane. **That band lies in the FOURTH block of the plane**, which is precisely the
            -- one a three-slot window never mapped, so before this task every byte of it was
            -- untouched by the text engine and no instrument said so.
            -- ★★★★ READ THROUGH THE SAME WINDOW THE PLANE DUMP USES: map the block into slot 6 and
            -- read $C000. 28,160 >> 13 = block 3 of the plane, offset 3,584 within it.
            -- ★★★ §2P: a COUNT of non-background bytes, never the glyphs. A person reads the
            -- screen; this says whether anything was drawn there at all.
            -- ★★ Restored afterwards from the guest's own ph_blk_slot5/vol rather than a literal,
            -- and the run is over by here in any case.
            if SYM.txt_penab and SYM.ph_blk_fb then
                local keys = SYM.P3_NKEY and prog:read_u8(SYM.P3_NKEY) or 0
                local blk = prog:read_u8(SYM.ph_blk_fb) + 3
                prog:write_u8(SLOT6, blk)
                -- ★★★★★ THE REFERENCE IS THE ROW's LAST BYTE, NOT ITS FIRST, AND THE FIRST DRAFT
                -- USED THE FIRST. A four-character line starts at column 0, so byte 0 is INSIDE
                -- the first glyph -- the reference was part of what it was measuring, and the
                -- count came out 1,267 of 1,280 for four characters. The discrimination was still
                -- total, but the NUMBER meant nothing.
                -- ★★★★ Column 39's last byte is 156 bytes past a 40-column line's start and is
                -- background in every case this row sees. **A metric whose baseline is inside the
                -- signal is the shape §2W keeps finding** [the comparison that read one plane of
                -- two, AD-122].
                local ink = 0
                local bg = prog:read_u8(0xC000 + 3584 + 1279)
                for i = 0, 1279 do
                    if prog:read_u8(0xC000 + 3584 + i) ~= bg then ink = ink + 1 end
                end
                -- ★★★★ THE VERDICT ONLY WHERE A VERDICT IS POSSIBLE. A run where nothing was typed
                -- has a blank command line for the honest reason, and a row that alarms on every
                -- normal run is a row nobody reads [the same trap the mojibake allowlist exists
                -- for: a check that is permanently red gets switched off].
                local penab = prog:read_u8(SYM.txt_penab)
                -- ★★★★ THE ATTRIBUTE THE ROW WAS DRAWN WITH, because Jay's eye gate reported the
                -- command line "appearing on white which makes them inverted against the other
                -- white rows in that area". txt_blit treats BIT 3 of the background as INVERT, so
                -- whether the prompt is inverted is a property of one byte and is worth printing
                -- rather than inferring from a colour [§2W.3: name what you actually have].
                if SYM.txt_fg and SYM.txt_bg then
                    local fg, bgat = prog:read_u8(SYM.txt_fg), prog:read_u8(SYM.txt_bg)
                    w("    text attribute at the end: fg=%d bg=$%02X (bit 3 = INVERT, so %s)",
                      fg, bgat, (bgat & 0x08) ~= 0 and "INVERTED" or "normal")
                end
                -- ★★★★★ THE VERDICT NEEDS THE PROMPT STILL ENABLED, AND THE FIRST VERSION DID NOT
                -- CHECK. Jay's 400-cycle eye run looped back to the title screen, where
                -- prevent.input runs and the row is correctly cleared -- so eleven keys had
                -- reached the editor, the line had been drawn and answered, and the END state was
                -- a blank row. **It reported NOTHING IS DRAWN about a run that worked.**
                -- ★★★★ A measurement taken at the end of a run is a statement about the end of the
                -- run [§2W.3]. With the prompt disabled this row cannot know what happened
                -- earlier and now says so instead of guessing.
                w("    row 22: %d of 1280 bytes differ from $%02X (prompt enabled=%d, keys to the "
                  .. "editor %d)%s", ink, bg, penab, keys,
                  keys == 0 and "  -- nothing was typed, so blank is correct"
                            or (penab == 0
                                and "  -- the prompt is disabled now; this says nothing about"
                                    .. " what was drawn earlier"
                                or (ink > 0 and "  -- ★ the command line is DRAWN"
                                             or "  -- ★★★ NOTHING IS DRAWN ON ROW 22")))
            end
            if SYM.txt_penab then
                local nk   = SYM.P3_NKEY and prog:read_u8(SYM.P3_NKEY) or 0
                local lastk= SYM.P3_KEY  and prog:read_u8(SYM.P3_KEY)  or 0
                local ppos = prog:read_u8(SYM.txt_ppos or 0)
                local prow = SYM.txt_prow and prog:read_u8(SYM.txt_prow) or -1
                w("    prompt: enabled=%d row=%d  keys to the editor=%d (last $%02X)  buffer=%d"
                  .. "  (posts attempted %d)",
                  prog:read_u8(SYM.txt_penab), prow, nk, lastk, ppos, _G._type_posts or 0)
                if TYPE_TEXT then
                    if nk == 0 then
                        w("    ★★★ NO KEYS REACHED THE EDITOR -- the matrix or the poll guard "
                          .. "swallowed every posted character")
                    elseif not type_report then
                        w("    ★★★ TYPED LINE NOT PARSED -- %d key(s) arrived and no said() input "
                          .. "was produced", nk)
                    else
                        w("    ★ the typed line reached the parser")
                    end
                end
            end
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE BLOCKING BOX's OBSERVABLES [AC-4, AC-5, AC-7]. All three are properties,
            -- never text [§2P].
            -- ★★★★ var 21 reading 0 at the end is text.cpp:411's zeroing, which happens ONLY on the
            -- path that actually left the wait -- so a non-zero value here means the last armed box
            -- was never entered, and that is a different failure from a hang.
            -- ★★★ tx_wt_key distinguishes ESC from ENTER-or-timer. It is the port's
            -- _messageBoxCancelled and **nothing consumes it yet** [T-P0-085 §7.3]; it is read here
            -- so AC-7 is a measurement rather than an eye-only claim.
            -- ★★★★ THE STACK, AND WHETHER THE IRQ'S 12 BYTES FIT. $0800 base, $0500 floor.
            w("    stack low-water S=$%04X at frame %d -- %d bytes used of 768, %d free"
              .. " (an IRQ frame is 12) %s",
              s_low, s_low_frame, 0x0800 - s_low, s_low - 0x0500,
              s_low <= 0x0500 and "★★★ COLLIDED WITH THE SEED STACK"
                or (s_low - 0x0500 < 64 and "★★★ UNDER 64 BYTES -- too close" or "★ safe"))
            if SYM.hal_frame_hi then
                local f = rd16(SYM.hal_frame_hi)
                w("    hal_frame=%d -- %s", f,
                  f > 0 and "★ the VBL IRQ IS LIVE (P6.31 measured this frozen at 0)"
                        or "★★★ FROZEN: no VBL interrupt is being taken")
            end
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
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ §4A's DIFFERENTIAL TABLE [T-P0-087]. tx_msgptr is ONE routine with TWO
            -- callers: display substitutes correctly and print does not. The arithmetic is the
            -- same in both cases, so this prints the INPUTS side by side and lets the comparison
            -- be the finding.
            -- ★★★ Record: site, msgno, vm_code, vm_codelen, tx_msgpos, count byte read, curlogic,
            -- result, cycle low byte. 12 bytes; first 8 calls per site.
            -- ★★ §2P: addresses, numbers and a result flag. Nothing from the message itself.
            if SYM.P3_TXDIAG then
                -- ★★★★★ THE COUNTERS ARE AUTHORITATIVE, THE BUFFER IS NOT [§2W.3]. The first
                -- version of this dump decided a slot was empty by testing its site byte against
                -- 0, and unwritten MAP_INPUT holds $FF -- so it printed eight fabricated "print"
                -- rows of all-$FF and I nearly read them as data. **A diagnostic must not infer
                -- how much was recorded from the recording.** tx_diag_n1/n2 are incremented at the
                -- moment a record is written and are the only thing that knows.
                local n1 = SYM.tx_diag_n1 and prog:read_u8(SYM.tx_diag_n1) or -1
                local n2 = SYM.tx_diag_n2 and prog:read_u8(SYM.tx_diag_n2) or -1
                w("    ── tx_msgptr call sites: %d display record(s), %d print record(s) "
                  .. "(cap %d each) ──", n1, n2, 8)
                w("      %-8s %6s %7s %8s %8s %6s %8s %6s %6s",
                  "site", "msgno", "vm_code", "codelen", "msgpos", "count", "curlogic", "ok", "cyc")
                for site = 0, 1 do
                    local kept = (site == 0) and n1 or n2
                    for slot = 0, math.min(kept, 8) - 1 do
                        local a = SYM.P3_TXDIAG + (site * 8 + slot) * 12
                        local s = prog:read_u8(a)
                        if true then
                            w("      %-8s %6d  $%04X   %6d   $%04X %6d %8d %6d %6d",
                              s == 1 and "display" or "print",
                              prog:read_u8(a + 1), rd16(a + 2), rd16(a + 4), rd16(a + 6),
                              prog:read_u8(a + 8), prog:read_u8(a + 9),
                              prog:read_u8(a + 10), prog:read_u8(a + 11))
                        end
                    end
                end
            end
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ DID THE WINDOW RESTORE ACTUALLY COVER THE BOX? [Jay: "still saw remnants of
            -- the box and text in pixels"]. txt_close copies the box's rectangle back from the
            -- SHADOW plane to the VISIBLE plane, so after it runs those two planes must AGREE
            -- over that rectangle. Anything left on screen is either a byte the copy missed
            -- (inside the rect) or a byte drawn outside the rect the copy was sized for.
            -- ★★★★ THE TWO CASES NEED OPPOSITE FIXES -- a wrong copy versus a wrong rectangle --
            -- so this reports them separately: the rect itself, and a band above and below it.
            -- ★★★ The rect is read from the guest's own symbols, including txb_yoff, so this
            -- measures the rectangle the guest USED rather than one recomputed here [§2W.3].
            if SYM.txt_bgx and SYM.ph_blk_fb then
                local function rd16s(a)
                    local v = rd16(a); if v >= 0x8000 then v = v - 0x10000 end; return v
                end
                local bx = rd16s(SYM.txt_bgx)
                local by = rd16s(SYM.txt_bgy) + (SYM.txb_yoff and rd16s(SYM.txb_yoff) or 0)
                local bw = rd16(SYM.txt_bgw)
                local bh = rd16(SYM.txt_bgh)
                -- ★★★★★ P3B_RECT IS THE CONTROL, AND WITHOUT IT THIS COMPARISON PROVES NOTHING.
                -- The compositor draws sprites onto the VISIBLE plane, so visible and shadow
                -- differ wherever a sprite sits whether or not a box was ever drawn. Forcing the
                -- SAME rectangle in a run that draws NO box measures the sprite alone, and the
                -- difference between the two numbers is what the restore actually left behind.
                -- ★★★ Without this the instrument cannot tell "the copy missed 143 bytes" from
                -- "the copy is perfect and 143 bytes are a sprite" -- and it reported the first
                -- with some confidence [§2W: an instrument that cannot be wrong does not measure].
                local ov = os.getenv("P3B_RECT")
                if ov then
                    local a, b, c, d = ov:match("^(%-?%d+),(%-?%d+),(%d+),(%d+)$")
                    if a then bx, by, bw, bh = tonumber(a), tonumber(b), tonumber(c), tonumber(d) end
                end
                w("    box rect used by the restore: x=%d y=%d w=%d h=%d;  txt_winactive=%d txt_restore=$%04X", bx, by, bw, bh, SYM.txt_winactive and prog:read_u8(SYM.txt_winactive) or -1, SYM.txt_restore and rd16(SYM.txt_restore) or 0)
                local BLK_VIS, BLK_SHA = 40, 2      -- P3_BLK_VISIBLE / P3_BLK_SHADOW
                -- compare a row band, returning how many bytes differ
                -- ★★★★ WHERE, NOT JUST HOW MANY. A count alone cannot tell the box's frame from
                -- the room's sprite: the compositor draws sprites onto the VISIBLE plane every
                -- cycle, so visible and shadow legitimately differ wherever a sprite sits, and
                -- this comparison runs at the END of the run. **A differing-byte count is
                -- confounded by design; the POSITIONS and VALUES are not** -- box pixels are
                -- $FF (white fill) and $44 (red line), and they lie on the rectangle's edges.
                local samples = {}
                local function diffband(r0, r1)
                    local bad, boxlike = 0, 0
                    for r = math.max(0, r0), r1 - 1 do
                        for c = math.max(0, bx), bx + bw - 1 do
                            local off = r * 160 + c
                            if off >= 0 and off < 26880 then
                                local sl, wi = off >> 13, off & 0x1FFF
                                prog:write_u8(0xFFA6, BLK_SHA + sl)
                                local s = prog:read_u8(0xC000 + wi)
                                prog:write_u8(0xFFA6, BLK_VIS + sl)
                                local v = prog:read_u8(0xC000 + wi)
                                if s ~= v then
                                    bad = bad + 1
                                    if v == 0xFF or v == 0x44 then boxlike = boxlike + 1 end
                                    if #samples < 10 then
                                        samples[#samples+1] = string.format(
                                            "r%d c%+d vis=$%02X sha=$%02X", r, c - bx, v, s)
                                    end
                                end
                            end
                        end
                    end
                    return bad, boxlike
                end
                local inside, boxlike = diffband(by, by + bh)
                local above  = diffband(by - 8, by)
                local below  = diffband(by + bh, by + bh + 8)
                w("    visible vs shadow: INSIDE the rect %d bytes differ (%d of them are box"
                  .. " colours $FF/$44); 8 rows above %d; 8 rows below %d",
                  inside, boxlike, above, below)
                -- ★★★★ PER ROW, because the SHAPE names the cause and a total cannot. Only rows
                -- whose span crosses an 8,192-byte slice boundary use the straddle path; if the
                -- residue is confined to those, the split is wrong. If it is spread evenly the
                -- copy is not running for whole rows, and if it is a contiguous blob it is the
                -- compositor's sprite and not a restore failure at all.
                local rowtxt = {}
                for r = by, by + bh - 1 do
                    local n, straddle = 0, ""
                    for c = math.max(0, bx), bx + bw - 1 do
                        local off = r * 160 + c
                        if off >= 0 and off < 26880 then
                            local sl, wi = off >> 13, off & 0x1FFF
                            prog:write_u8(0xFFA6, BLK_SHA + sl)
                            local s = prog:read_u8(0xC000 + wi)
                            prog:write_u8(0xFFA6, BLK_VIS + sl)
                            if s ~= prog:read_u8(0xC000 + wi) then n = n + 1 end
                        end
                    end
                    if ((r * 160 + bx) & 0x1FFF) + bw > 8192 then straddle = " <- STRADDLES" end
                    rowtxt[#rowtxt+1] = string.format("r%d:%d%s", r, n, straddle)
                end
                w("       per row: %s", table.concat(rowtxt, "  "))
                -- ★★★★★ §4B(ii): WHAT THE COPY ACTUALLY DID, recorded by the guest per iteration.
                -- §4A ruled out source contamination, so the question is which of row, within or
                -- n is wrong -- and the host can recompute the arithmetic but cannot see what the
                -- routine executed. `want` is this side's independent computation of `within`;
                -- a mismatch names the arithmetic, a match moves the suspicion to the copy.
                if SYM.P3_RBTRACE and SYM.p3rb_tn then
                    local n = prog:read_u8(SYM.p3rb_tn)
                    w("       p3_restore_box trace, %d row(s) recorded:", n)
                    local t = {}
                    for i = 0, math.min(n, 24) - 1 do
                        local a = SYM.P3_RBTRACE + i * 4
                        local row = prog:read_u8(a)
                        local within = rd16(a + 1)
                        local cnt = prog:read_u8(a + 3)
                        local off = row * 160 + bx
                        local want = off & 0x1FFF
                        t[#t+1] = string.format("r%d:w%d/n%d%s", row, within, cnt,
                                                want ~= within and (" WANT" .. want) or "")
                    end
                    w("       %s", table.concat(t, "  "))
                end
                -- ★★★★★ COUNT THE RED, because the difference count UNDERCOUNTS and I read it as
                -- if it did not. The box background is $FF and this room's picture is largely $FF
                -- too, so an unrestored background byte MATCHES the shadow and scores zero. **The
                -- border colour $44 is the one value the picture cannot supply**, so surviving red
                -- is unambiguous residue and its absence is unambiguous success.
                local red = 0
                for r = by, by + bh - 1 do
                    for c = math.max(0, bx), bx + bw - 1 do
                        local off = r * 160 + c
                        if off >= 0 and off < 26880 then
                            prog:write_u8(0xFFA6, BLK_VIS + (off >> 13))
                            if prog:read_u8(0xC000 + (off & 0x1FFF)) == 0x44 then red = red + 1 end
                        end
                    end
                end
                w("       RED ($44) bytes still in the visible plane inside the rect: %d -- %s",
                  red, red > 0 and "★★★ the border SURVIVED the restore"
                                or "★ no border left; the frame was restored")
                for i = 1, #samples do w("       %s", samples[i]) end
                w("    %s", boxlike > 0
                    and "★★★ BOX PIXELS SURVIVE inside the rect -- the copy missed them"
                    or (inside > 0
                        and "★ differences inside the rect but NONE are box colours -- that is"
                         .. " the compositor's sprite, not a restore failure"
                        or "★ the rect matches the shadow exactly"))
            end
            if JUMP_ROOM > 0 then
                w("    room jump: asked %d, landed %s, dispatched %s, final room %d",
                  JUMP_ROOM, tostring(jumped), tostring(jump_seen_clear), prog:read_u8(ROOM))
            end
            if SYM.tx_wt_key then
                w("    var21 now %d (0 = a box was entered and left), tx_wt_key=%d (1 = ESC),"
                  .. " boxes waited on = %d",
                  prog:read_u8(VAR_AUTOCLOSE), prog:read_u8(SYM.tx_wt_key),
                  SYM.tx_wt_nwait and prog:read_u8(SYM.tx_wt_nwait) or -1)
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
                -- ★ SLOT5/SLOT6 come from the module scope now; this was their only home.
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
        -- ★★★★★ THE ROOM's TRAJECTORY, ONE SAMPLE PER PARK [T-P0-094 §4B(3)]. This cluster has had
        -- two endpoints -- "final room 83" and "final room 1" -- for six tasks and never a
        -- sequence, so "the game restarted" was an inference from where a run STOPPED. **A
        -- transition list is the observation that inference was standing in for.**
        -- ★★ Transitions only, not 400 samples: a room number repeated is not evidence, and this
        -- file already guards against printing 900 copies of one fact.
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★ ARM THE said() RECORDER ONE PARK EARLY, for the reason every other arming in this
        -- file is one park early: the guest runs the cycle this release starts, and vm_cycle reads
        -- the cycle it is ABOUT to run [T-P0-098].
        if SAIDAT and SYM.vm_sd_at and not _G._sd_armed then
            prog:write_u8(SYM.vm_sd_at, math.floor(SAIDAT / 256))
            prog:write_u8(SYM.vm_sd_at + 1, SAIDAT % 256)
            _G._sd_armed = true
            w("  ★ said() recorder armed for vm_cycle %d", SAIDAT)
        end
        if SAIDAT and SYM.vm_v0_at and not _G._v0_armed then
            prog:write_u8(SYM.vm_v0_at, math.floor(SAIDAT / 256))
            prog:write_u8(SYM.vm_v0_at + 1, SAIDAT % 256)
            -- ★★★ WHICH VARIABLE, from P3B_WATCHVAR. Defaults to 0 so an unset run reproduces
            -- P6.44 exactly; the point of the parameter is to re-point the same recorder at the
            -- variable that turns out to be lindirect.v's destination [T-P0-100 §1.3].
            if SYM.vm_v0_var then prog:write_u8(SYM.vm_v0_var, WATCHVAR) end
            _G._v0_armed = true
            w("  ★ var-%d writer recorder armed for vm_cycle %d", WATCHVAR, SAIDAT)
        end
        -- ★★★★★ THE `if` RECORDER [T-P0-101 §4A]. Armed on the same park and off the same cycle as
        -- the other two, so the three tables describe ONE cycle and can be read against each other.
        -- ★★★ The logic number is REQUIRED, not defaulted: a recorder pointed at logic 0 by accident
        -- would fill its 24 rows and report a table about the wrong module, which reads exactly like
        -- a table about the right one.
        if SAIDAT and IFLOGIC and SYM.vm_if_at and not _G._if_armed then
            prog:write_u8(SYM.vm_if_at, math.floor(SAIDAT / 256))
            prog:write_u8(SYM.vm_if_at + 1, SAIDAT % 256)
            if SYM.vm_if_logic then prog:write_u8(SYM.vm_if_logic, IFLOGIC) end
            _G._if_armed = true
            w("  ★ if-recorder armed for logic %d in vm_cycle %d", IFLOGIC, SAIDAT)
        end

        -- ★★★★★ SAMPLE THE WHOLE VM STATE BLOCK [T-P0-096 §4A]. Seven arms have asked which BUILD
        -- difference correlates with the restart. **None has asked what logic 0 actually READ.**
        -- It is the actor on both sides, with the same inputs and the same parse, and it decides
        -- differently -- so something it reads differs, and the state block is where that lives.
        -- ★★★★★ THE SAME 288 BYTES THE vm GATE COMPARES, in the same order: 32 packed flag bytes
        -- then 256 variables [vm_diff.py's own format; vm_sweep.lua:714-716 writes it]. **Reading
        -- it needs no change to the port** -- the addresses are in memmap.inc and the host reads
        -- memory freely, which is what makes this a measurement and not a code change.
        -- ★★★ P3B_STATEDUMP=98-102 selects the cycles. Absent, nothing is written and no gate row
        -- pays for it.
        if STATE_LO and n >= STATE_LO and n <= STATE_HI then
            local buf = {}
            for i = 0, 31 do buf[#buf + 1] = string.char(prog:read_u8(VM_FLAGS + i)) end
            for i = 0, 255 do buf[#buf + 1] = string.char(prog:read_u8(VM_VARS + i)) end
            local f = io.open(string.format("%s/state_%03d.bin", OUT, n), "wb")
            if f then f:write(table.concat(buf)); f:close() end
        end

        -- ★★★ vm_curlogic IS SAMPLED WITH THE ROOM, not separately: it is the logic that was
        -- interpreting when the change happened, and a transition without it is half an answer.
        do
            local room = prog:read_u8(VM_VARS + 0)
            _G._rooms = _G._rooms or {}
            local last = _G._rooms[#_G._rooms]
            if not last or last[2] ~= room then
                _G._rooms[#_G._rooms + 1] = { n, room,
                    SYM.vm_curlogic and prog:read_u8(SYM.vm_curlogic) or -1,
                    (prog:read_u8(VM_FLAGS + 0) & 0x20) ~= 0 and 1 or 0 }
            end
        end

        local feed = script[n + 1]
        if feed and words then
            if #feed >= INBUF_MAX then
                w("★★★ input for cycle %d is %d chars, past the oracle's %d-byte input line "
                  .. "[text.h:170] -- NOT fed", n + 1, #feed, INBUF_MAX)
            else
                for i = 1, #feed do prog:write_u8(SYM.P3_INBUF + i - 1, feed:byte(i)) end
                prog:write_u8(SYM.P3_INBUF + #feed, 0)
                prog:write_u8(SYM.P3_FEED, 1)
                _G._parse_due = n + 1
                w("  ★ COMMAND TYPED at cycle %d (%d chars) -- watch the screen", n + 1, #feed)
            end
        end

        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ AND READ BACK WHAT THE PARSE PRODUCED [T-P0-091]. Before this, a command was fed
        -- and NOTHING on the host ever looked at the result: the log said "COMMAND TYPED" and the
        -- next thing it said was the cycle count. **A windowed dictionary that maps the wrong
        -- block parses every word as unknown and produces exactly that log** -- which is why the
        -- window could not be gated by any row in the suite before this line existed.
        -- ★★★★ par_egon IS THE OBSERVABLE AND IT IS THE RIGHT ONE: par_find returns the word
        -- NUMBER and par_parse stores it, so a dictionary that is absent, unmapped or on top of
        -- the object table gives egon = 0 with par_notfound naming the first word. A parse
        -- against the real dictionary gives a non-zero count for any line built from its words.
        -- ★★★ §2P: word NUMBERS, never the text -- the same rule parser_gate.lua states for the
        -- byte gate. The line itself was the game's and is not echoed here.
        -- ★★ One cycle late, deliberately: the guest checks P3_FEED after vm_pace inside the
        -- cycle this arming released, so the result exists at the NEXT park and not before.
        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ AND par_cli IS **NOT** READ HERE, THOUGH THE FIRST VERSION PRINTED IT AND IT
        -- PRINTED 0 ON A HEALTHY PARSE. par_parse sets par_cli to 1 whenever it stored a word
        -- [parser.s:446-449] -- so the column looked like a contradiction with `1 word(s)` beside
        -- it. It is not: **vmtest_said reloads par_cli from VM flag 2 before every said()
        -- evaluation** [vm_tests.s], and vm_post_cycle clears that flag at the end of the cycle.
        -- By the next park the byte is the VM's, not the parse's.
        -- ★★★★ THAT IS §2W.3 EXACTLY -- a diagnostic labelling a side it does not have -- and it
        -- would have been read as a parser defect by whoever met it first. par_egon, par_ego and
        -- par_notfound have no second writer and survive the cycle, so those are what is printed.
        if _G._parse_due and n > _G._parse_due and SYM.par_egon then
            local egon = prog:read_u8(SYM.par_egon)
            local ids = {}
            for i = 0, math.min(egon, 8) - 1 do
                ids[#ids+1] = tostring(rd16(SYM.par_ego + i * 2))
            end
            w("  %s parse at cycle %d: %d word(s) [%s] notfound=%d %s",
              egon > 0 and "★" or "★★★", _G._parse_due, egon, table.concat(ids, ","),
              SYM.par_notfound and prog:read_u8(SYM.par_notfound) or -1,
              egon > 0 and "-- the dictionary was reachable"
                        or "★★★ NO WORDS MATCHED -- the vocabulary window is not holding WORDS.TOK")
            _G._parse_due = nil
        end

        -- ═══════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ TYPE IT. The post is one call; what follows is the ADJUDICATION, and it is the
        -- part that makes this a gate rather than a demonstration.
        -- ★★★★ THREE OBSERVABLES, EACH ANSWERING A DIFFERENT "did nothing happen":
        --   P3_NKEY   the matrix delivered keys to the editor        (0 = no keyboard)
        --   txt_ppos  the editor accumulated them, then ENTER cleared it
        --   par_egon  the parse those keys caused found words        (0 = no dictionary)
        -- **Without all three, a dead matrix, a dead editor and a dead dictionary look the same
        -- from the framebuffer** [§2W.3], and the framebuffer is all an eye gate can see.
        -- ★★★★★ ONE CHARACTER PER PARK, HANDSHAKEN ON P3_NKEY -- AND THE FIRST VERSION POSTED THE
        -- WHOLE LINE AT ONCE AND LOST THREE FIFTHS OF IT [T-P0-092].
        -- ★★★★★ THE CAUSE IS A REAL PROPERTY OF THE PORT, NOT OF THE TEST HARNESS. The oracle's
        -- key dispatch is fed from an event QUEUE [cycle.cpp:350]; HAL_key_scan reads the matrix
        -- STATE at one instant, once per cycle. **A character that goes down and up between two
        -- polls never existed as far as the guest is concerned**, and natkeyboard types far faster
        -- than a cycle. Posted whole, "look\r" delivered 2 of 5 keys and parsed an unknown word.
        -- ★★★★ SO THE HANDSHAKE IS THE HONEST TEST: post the next character only once the guest's
        -- own counter says it consumed the last. That exercises the matrix for EVERY character
        -- rather than papering over the loss with a slower rate that might still be lucky.
        -- ★★★ The loss itself is reported as a finding rather than fixed here -- a key queue is a
        -- HAL change and this task is the editor [§22.5].
        -- ★★★ ONE CHARACTER PER PARK, AND ONLY WHEN THE LATCH IS EMPTY -- the guest consumes at
        -- most one per cycle, so writing a second before it reads the first would silently drop
        -- one and the echo would be short by a character with nothing to say why.
        if INJECT and n >= INJECT_AT and inj_i < #INJECT and SYM.p3_keybuf then
            if prog:read_u8(SYM.p3_keybuf) == 0 then
                inj_i = inj_i + 1
                prog:write_u8(SYM.p3_keybuf, INJECT:byte(inj_i))
                if inj_i == 1 then
                    w("  ★ INJECTING %d character(s) from cycle %d at the editor's entry point "
                      .. "(the matrix is NOT exercised -- see the manifest row)", #INJECT, n)
                end
            end
        end

        if TYPE_TEXT and not typed and n >= TYPE_AT then
            local sent = _G._type_i or 0
            local nk = SYM.P3_NKEY and prog:read_u8(SYM.P3_NKEY) or 0
            -- ★★ ONCE, NOT EVERY PARK. The first version keyed the banner on `sent == 0`, which
            -- stays true for as long as nothing arrives -- so a run that delivered no keys printed
            -- the announcement 180 times and buried its own verdict [the same shape as the 900
            -- copies of "final room 22" this file already guards against].
            if not _G._type_said then
                _G._type_said = true
                local penab = SYM.txt_penab and prog:read_u8(SYM.txt_penab) or -1
                w("  ★ TYPING %d character(s) from cycle %d, one per cycle through the matrix "
                  .. "(prompt enabled=%d)", #TYPE_TEXT + 1, n, penab)
                -- ★★ Prompt disabled means the keys will be dropped by p3_poll_key's own guard,
                -- which is correct behaviour and a useless test. Say so when it is knowable.
                if penab == 0 then
                    w("  ★★★ the prompt is NOT enabled -- accept.input has not run, so these keys "
                      .. "will be discarded by the poll guard, not by the editor")
                end
            end
            -- ★★★★★ RE-POST UNTIL THE GUEST'S OWN COUNTER MOVES, and only while natkeyboard's queue
            -- is drained. A single post holds the key down for a frame or two; the guest looks once
            -- per CYCLE, which is ~9 frames here -- so one post has roughly a one-in-five chance of
            -- being seen. **Posting once and waiting delivered ZERO of five characters.**
            -- ★★★★ THE `empty` GUARD IS WHAT KEEPS THIS FROM BEING A FLOOD: without it every park
            -- queues another copy and the guest eventually sees the same character several times.
            -- With it there is at most one key in flight, and P3_NKEY says when it landed.
            if nk > sent then sent = nk; _G._type_i = nk end
            if sent > #TYPE_TEXT then
                typed = true
            elseif m.natkeyboard.empty then
                m.natkeyboard:post(sent < #TYPE_TEXT
                                   and TYPE_TEXT:sub(sent + 1, sent + 1) or "\r")
                _G._type_posts = (_G._type_posts or 0) + 1
            end
        end
        if typed and not type_report and SYM.P3_NKEY then
            local nk = prog:read_u8(SYM.P3_NKEY)
            local egon = SYM.par_egon and prog:read_u8(SYM.par_egon) or 0
            local ppos = SYM.txt_ppos and prog:read_u8(SYM.txt_ppos) or -1
            -- ★★★ REPORT ONCE, WHEN THE PARSE HAS HAPPENED -- ENTER is the last character posted
            -- and natkeyboard feeds over many frames, so a fixed cycle offset would read the
            -- buffer mid-line. egon > 0 with ppos back at 0 is "the line was submitted".
            if egon > 0 and ppos == 0 then
                local ids = {}
                for i = 0, math.min(egon, 8) - 1 do
                    ids[#ids+1] = tostring(rd16(SYM.par_ego + i * 2))
                end
                type_report = true
                w("  ★ TYPED LINE PARSED at cycle %d: %d key(s) reached the editor, "
                  .. "%d word(s) [%s], buffer empty", n, nk, egon, table.concat(ids, ","))
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

        -- ★★★★★ ZERO CP_BLITS BEFORE THE FIRST CYCLE. The guest never initialises it -- composite.s
        -- only ever INCREMENTS it, and p3b's status block is not cleared at startup -- so the value
        -- read at the end is a count plus whatever that RAM held. **Nothing had ever read this
        -- counter, so nobody had noticed it has no producer for its starting value** [§2W: an
        -- `inc` counter is only meaningful from a known start, which vm_state.s records once
        -- already about VM_TESTSEEN].
        if not _G._blits_zeroed then
            _G._blits_zeroed = true
            prog:write_u8(0x006C, 0)
            prog:write_u8(0x006D, 0)
        end
        -- ★★★★★ THE ARENA'S OCCUPANCY, WHICH NOTHING HAS EVER MEASURED [T-P0-104 §3(3)].
        -- res_top is exported and sampled, but only ever instantaneously; there is no high-water
        -- mark anywhere, so "how full does the arena actually get" has never had an answer -- the
        -- same shape as the stack reservation that turned out to hold 1,660 bytes of slack.
        -- ★★★★ BOTH ALLOCATORS, because they grow toward each other: the transient stack UP from
        -- RES_ARENA and the LOGIC cache DOWN from RES_ARENA_END. Occupancy is the sum, and either
        -- one alone understates it.
        -- ★★★ PARK-SAMPLED, SO IT IS A LOWER BOUND AND IS REPORTED AS ONE. The peak is mid-cycle,
        -- while a VIEW is open on top of the cached logics inside p3_composite_all; this sees the
        -- cycle boundary, where that frame has already been popped.
        if SYM.res_top and SYM.res_ccur then
            local top  = prog:read_u8(SYM.res_top) * 256 + prog:read_u8(SYM.res_top + 1)
            local ccur = prog:read_u8(SYM.res_ccur) * 256 + prog:read_u8(SYM.res_ccur + 1)
            local stack = top - 0x6000
            local cache = 0xA000 - ccur
            local used = stack + cache
            if used > (_G._arena_hi or -1) then
                _G._arena_hi = used
                _G._arena_hi_parts = { stack, cache, n }
            end
        end
        -- ★★★★★ DUMP AT DETECTION, NOT AT READOUT [T-P0-103]. The first version dumped the bytes
        -- when the report was written, and by then the arena had been reused: res_copy_diff.py
        -- diffed whatever now occupied that address and reported 3,549 of 3,817 bytes differing,
        -- which is a confident answer about the wrong memory. **A transient's bytes are only
        -- readable while it is resident**, so the host polls the ring every park and dumps the
        -- moment a row appears.
        if SYM.rck_bad then
            local nb = prog:read_u8(SYM.rck_bad)
            local had = _G._rck_rows or 0
            if nb > had then
                for i = had, nb - 1 do
                    local b = SYM.rck_ring + i * 14
                    local rtype, ridx = prog:read_u8(b), prog:read_u8(b + 1)
                    local base = prog:read_u8(b + 2) * 256 + prog:read_u8(b + 3)
                    local len  = prog:read_u8(b + 4) * 256 + prog:read_u8(b + 5)
                    if len > 0 then
                        local path = string.format("%s/rescheck_%d_%d.bin", OUT, rtype, ridx)
                        local fh = io.open(path, "wb")
                        if fh then
                            local t = {}
                            for k = 0, len - 1 do t[#t + 1] = string.char(prog:read_u8(base + k)) end
                            fh:write(table.concat(t))
                            fh:close()
                            w("  ★ res-checksum row %d dumped at detection -> %s", i, path)
                        end
                    end
                end
                _G._rck_rows = nb
            end
        end
        n = n + 1
        prog:write_u8(MODE, 1)
        prog:write_u8(GO, 1)
        return
    end
end)
