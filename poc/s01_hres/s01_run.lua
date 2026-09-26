-- poc/s01_hres/s01_run.lua -- Spike S-01 rev B driver. Waits for DECB's OK prompt, pokes s01.bin,
-- sweeps the delay, and reports the BOUNDARY SCANLINE per delay value.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ MEASURED FROM THE HOST, NOT FROM A SCREENSHOT [§5]. The result of this spike is a table
-- of (delay -> boundary scanline), because "the boundary is steady" and "the boundary moves with
-- the delay" are numbers, and judging a picture cannot produce either. A snapshot is taken as well,
-- for Jay, because the mode difference is obvious to an eye and tedious to describe.
--
-- ★★★★★ THE SWEEP IS THE POINT. A single band in a plausible place could be an accident of the
-- emulator's frame compositing. **A boundary whose scanline is a monotone function of a delay the
-- host pokes cannot be.** So the pass condition is not "there is a band", it is "the band MOVES".
--
-- ★★★★★ AND THE LIVENESS WITNESS IS READ EVERY TIME [§2W]. A screen with no boundary and a guest
-- that crashed before its first flip are the same picture. s01_frames rises once per guest frame;
-- a flat screen with a rising counter is a real negative, a stalled counter is a broken spike.
--
-- ★★★ Symbols come from the assembler's MAP, parsed by name. P6.3's stall dump printed an offset
-- of 33,849 into a 34-byte string because three symbol addresses were hard-coded and had gone
-- stale by two bytes [§2W.3]; nothing here is hard-coded but $0400 (DECB's text screen) and
-- $A7D0-$A7E0 (its prompt poll), both of which belong to the ROM and not to this spike.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local BIN     = os.getenv("S01_BIN")    or "build/s01/s01.bin"
local MAP     = os.getenv("S01_MAP")    or "build/s01/s01.map"
local OUT     = os.getenv("S01_OUT")    or "build/s01"
local MODE    = tonumber(os.getenv("S01_MODE")   or "0")     -- 0 = palette control, 1 = HRES
local COL_A   = tonumber(os.getenv("S01_COLA")   or "63")    -- white
local COL_B   = tonumber(os.getenv("S01_COLB")   or "9")     -- a mid colour, NOT black
local SETTLE  = tonumber(os.getenv("S01_SETTLE") or "8")     -- frames to hold each delay
local SAMPLES = tonumber(os.getenv("S01_SAMPLES")or "4")     -- frames sampled per delay
local OK_TMO  = tonumber(os.getenv("S01_OK_FRAMES") or "1800")
local FILLM   = tonumber(os.getenv("S01_FILLM")  or "0")     -- 0 = constant byte, 1 = row number
local FILLB   = tonumber(os.getenv("S01_FILLB")  or "85")    -- $55 = flat index 1
local VREST   = tonumber(os.getenv("S01_VREST")  or "21")    -- $15 = 320x192x4
local VRESB   = tonumber(os.getenv("S01_VRESB")  or "13")    -- $0D = 160x192x4
-- ★★★★★ S01_EYE: HOLD ONE DELAY AND DO NOT SWEEP, SO A PERSON CAN WATCH IT [§2U.2 -- an eye gate
-- nobody can watch at 2000% is not an eye gate]. The run pokes the parameters, hands over, prints
-- the boundary once so the number and the picture are the same observation, and then leaves the
-- machine alone until the window is closed. No verdict is computed: the verdict of an eye run is
-- Jay's, and §3 forbids this file forming an opinion about what is on the screen.
local EYE     = (os.getenv("S01_EYE") or "") ~= ""
local VOFF    = tonumber(os.getenv("S01_VOFF") or "59392")   -- $E800
-- ★★★★★ S01_VSWEEP: sweep VOFFSET instead of the delay. The framebuffer readback proved the fill is
-- correct while the screen disagreed, so the display path is at fault and VOFFSET is the assumption
-- in it. With a constant fill in a static mode, the RIGHT value is the only one that makes every
-- sampled row patterned and equal -- so this finds it by measurement rather than by a third derivation.
local VSWEEP  = (os.getenv("S01_VSWEEP") or "") ~= ""
-- ★★★★★ S-02: the row-map run. Two phases in one session -- calibrate colour->index from a $1B fill,
-- then refill with the row-number pattern and read every scanline back. See the decode above.
local ROWMAP  = (os.getenv("S01_ROWMAP") or "") ~= ""
local DLY2    = tonumber(os.getenv("S01_DLY2") or "0")
local DLY3    = tonumber(os.getenv("S01_DLY3") or "0")
-- ★★★★★ S-03: the 16-colour buffer is 30,720 B and is filled through a moving MMU window, so all-RAM
-- is never entered and the vectors stay in ROM. See s01_fill16.
local BIG     = tonumber(os.getenv("S01_BIG") or "0")
-- ★★★★★ S-04 §4A(1): shift the row numbering. If the repeats move with it they are an artefact of
-- the byte VALUE; if they stay they are tied to a screen POSITION and are real.
local ROWBASE = tonumber(os.getenv("S01_ROWBASE") or "0")

-- ★★ The delay sweep. 8 CPU cycles per iteration; a frame is ~29,830 cycles at 1.79 MHz, of which
-- ~8,000 is vertical blank. So 0..3600 in steps covers blank plus the whole active field.
local SWEEP = {}
do
    local s = os.getenv("S01_SWEEP")
    if s then
        for v in s:gmatch("%d+") do SWEEP[#SWEEP+1] = tonumber(v) end
    else
        for v = 0, 3600, 200 do SWEEP[#SWEEP+1] = v end
    end
end

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens[":screen"]

local log = {}
local function w(fmt, ...)
    local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print(s); log[#log+1] = s
end

-- ── symbols ─────────────────────────────────────────────────────────────────────────────────
local SYM = {}
do
    local fh = io.open(MAP, "r")
    if not fh then print("★★★ no map at " .. MAP); m:exit(); return end
    for line in fh:lines() do
        local n, v = line:match("^Symbol:%s+(%S+)%s+%(.-%)%s+=%s+(%x+)$")
        if n then SYM[n] = tonumber(v, 16) end
    end
    fh:close()
end
for _, n in ipairs({"entry", "s01_mode", "s01_colA", "s01_colB", "s01_dly", "s01_frames",
                    "s01_fillm", "s01_fillb", "s01_vrest", "s01_vresb", "s01_refill",
                    "s01_col0", "s01_col1", "s01_col2", "s01_col3", "s01_palreg",
                    "s01_dly2", "s01_dly3", "s01_big", "s01_rowbase"}) do
    if not SYM[n] then print("★★★ map lacks " .. n); m:exit(); return end
end

local function rd16(a) return prog:read_u8(a) * 256 + prog:read_u8(a + 1) end
local function wr16(a, v) prog:write_u8(a, v // 256); prog:write_u8(a + 1, v % 256) end

-- ── the DECB readiness check, the established form ──────────────────────────────────────────
-- ★★★ "OK" at the START OF A ROW *and* the CPU parked in DECB's prompt poll, sustained three
-- frames. A pattern search over uninitialised RAM went green early once and that is the direction
-- that hides the problem [p3b_run.lua:874-901, and Jay: "you still are not getting to the basic
-- prompt"]. Reused rather than reinvented.
local ok_streak = 0
local function decb_ready()
    local seen = false
    for row = 0, 15 do
        local b = 0x0400 + row * 32
        if prog:read_u8(b) == 0x4F and prog:read_u8(b + 1) == 0x4B then seen = true; break end
    end
    local pc = cpu.state["PC"].value
    if seen and pc >= 0xA7D0 and pc <= 0xA7E0 then ok_streak = ok_streak + 1 else ok_streak = 0 end
    return ok_streak >= 3
end

-- ── the column sampler ──────────────────────────────────────────────────────────────────────
-- ★★★★ A COLUMN, not a lattice. The boundary is horizontal by construction, so one column at the
-- screen's midpoint carries the whole answer at full vertical resolution -- 160 lattice points
-- over 239 rows could not resolve a scanline, which is the quantity in dispute.
-- ★★ Transitions are returned as (y, from, to) so the three expected regions (border, top band,
-- bottom band) are distinguishable from the two that a same-colour bottom band would give.
local SW, SH = scr.width, scr.height

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ STAGE 1 NEEDS A DIFFERENT MEASUREMENT AND STAGE 0's WOULD HAVE REPORTED NOTHING. A
-- palette change alters COLOUR, which a column of pixels shows directly. **An HRES change alters
-- PIXEL WIDTH and leaves every colour alone**, so on a flat field it is invisible and even on a
-- patterned one a vertical column can pass straight through it.
-- ★★★★ THE OBSERVABLE IS THE HORIZONTAL PERIOD. With the framebuffer filled with $0F -- two pixels
-- of index 0 then two of index 3, at 2 bits per pixel -- the on-screen period is 8 raster columns
-- at 320 wide and 16 at 160 wide, because the GIME stretches 160 pixels across the same raster.
-- **So the transition count along a row should HALVE below the boundary: ~160 above, ~80 below.**
-- ★★★ A ratio near 2.0 is the pass. A ratio near 1.0 means the write was not honoured, whatever
-- else the screen does.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ ONE ATOMIC BITMAP READ, NOT 640 SEPARATE pixel() CALLS, AND THE REBUILD IS THE WHOLE
-- POINT [T-P0-157-adjacent; §2W]. The first sampler called scr:pixel(x, y) once per pixel, which
-- is 640 reads per row of a bitmap the emulator may rewrite between them. It produced results that
-- were NOT REPRODUCIBLE: the same binary, the same VOFFSET and the same $FF99 gave "all rows 159"
-- in one invocation and "72, 66, 66 then flat" in another, and rows 30/50/70 read IDENTICALLY
-- across all eight video modes -- a number that does not move when the mode changes is not
-- measuring the mode.
-- ★★★★ Two hypotheses were tested and BOTH WERE WRONG before this one: `-video none` (identical
-- with rendering enabled) and settling time (identical at 141 guest frames). **Recorded because a
-- hypothesis eliminated by measurement is worth as much as the one that lands.**
-- ★★★★★ scr:pixels() returns the entire frame as one string -- 640 x 239 x 4 = 611,840 bytes -- so
-- every pixel in a profile comes from THE SAME FRAME by construction. MAME 0.281.
-- ★★★ Pixels are compared as 4-byte substrings rather than decoded: the question is only whether
-- two pixels DIFFER, and not decoding removes a byte-order assumption that nothing would check.
local function grab()
    local s, w0, h0 = scr:pixels()
    return s, w0 or SW, h0 or SH
end

local function row_trans(buf, y)
    local n, prev = 0, nil
    local base = y * SW * 4 + 1
    for x = 0, SW - 1 do
        local o = base + x * 4
        local p = buf:sub(o, o + 3)
        if prev ~= nil and p ~= prev then n = n + 1 end
        prev = p
    end
    return n
end

-- ★★ A profile down the screen, so the boundary is located by the row count rather than assumed
-- from stage 0's delay-to-scanline mapping. Two instruments for one boundary [§2W].
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ THE RAW DATUM, RUN-LENGTH ENCODED, BECAUSE A TRANSITION COUNT IS A LOSSY SUMMARY AND I
-- HAVE BEEN DEBUGGING THE SUMMARY. A count of 66 is consistent with the stripe pattern, with the
-- DECB text screen, and with garbage; the actual pixel values distinguish them in one look.
-- **$0F at 2 bits per pixel is index 0,0,3,3 -- so at 320-wide on a 640 raster the run lengths must
-- be a perfectly regular 4,4,4,4,... and at 160-wide a regular 8,8,8,8,...** Anything else is not
-- this framebuffer, and the run lengths say which.
-- ★★★ §2W.3: a diagnostic that reports a derived number where it could report the raw observation
-- is a diagnostic that can only tell you that something is wrong, never what.
local function row_runs(buf, y, maxruns)
    local base = y * SW * 4 + 1
    local runs, cur, prev = {}, 0, nil
    for x = 0, SW - 1 do
        local o = base + x * 4
        local p = buf:sub(o, o + 3)
        if prev == nil then prev, cur = p, 1
        elseif p == prev then cur = cur + 1
        else runs[#runs+1] = cur; prev, cur = p, 1
              if #runs >= (maxruns or 24) then break end end
    end
    if #runs < (maxruns or 24) then runs[#runs+1] = cur end
    -- the distinct pixel values seen, so "flat" can be told from "two colours alternating"
    local seen, order = {}, {}
    for x = 0, math.min(SW, 160) - 1 do
        local o = base + x * 4
        local v = buf:sub(o, o + 3)
        if not seen[v] then
            seen[v] = true
            order[#order+1] = string.format("%02X%02X%02X%02X",
              v:byte(4) or 0, v:byte(3) or 0, v:byte(2) or 0, v:byte(1) or 0)
        end
    end
    return runs, order
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ S-02: DECODE THE ROW-NUMBER FILL BACK TO A SOURCE ROW.
-- `s01_fillm = 1` fills row N with byte value N, and at 2 bits per pixel that byte is four palette
-- indices: (N>>6)&3, (N>>4)&3, (N>>2)&3, N&3. So reading four pixels off a displayed row and mapping
-- each colour to its index reconstructs N -- **which source row arrived on this scanline.**
-- ★★★★ THE COLOUR->INDEX MAP IS MEASURED, NOT DERIVED. Predicting the RGB for a CoCo3 palette byte
-- would import an assumption about MAME's conversion that nothing checks; instead the guest is filled
-- with $1B (indices 0,1,2,3) and the four colours are read off the screen in the SAME session.
-- ★★★ BOTH PIXEL WIDTHS ARE DECODED AND BOTH PRINTED. A row's width is 2 raster columns per pixel at
-- 320-wide and 4 at 160-wide, and rather than assume where the boundary is, each row is decoded both
-- ways: above the switch the w=2 column reads as a clean sequence, below it the w=4 column does. The
-- table then shows the boundary rather than depending on knowing it [S-01 §7.3: do not build the
-- answer into the instrument].
local CAL = {}          -- colour (4-byte string) -> palette index 0..3
local CAL_N = 0

local function calibrate(buf, y)
    -- $1B = %00 01 10 11 -> pixels 0,1,2,3 at 320-wide, each 2 raster columns
    CAL, CAL_N = {}, 0
    local base = y * SW * 4 + 1
    local seen = {}
    for k = 0, 3 do
        local o = base + (k * 2) * 4
        local v = buf:sub(o, o + 3)
        if seen[v] then return false, k end      -- two indices rendering alike: unusable
        seen[v] = true
        CAL[v] = k
        CAL_N = CAL_N + 1
    end
    return CAL_N == 4
end

local function decode_row(buf, y, pxw)
    local base = y * SW * 4 + 1
    local b = 0
    for k = 0, 3 do
        local col = k * pxw + (pxw // 2)         -- the centre of pixel k
        local o = base + col * 4
        local idx = CAL[buf:sub(o, o + 3)]
        if idx == nil then return nil end         -- a colour outside the calibrated four
        b = b * 4 + idx
    end
    return b
end
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ S-03: THE COUNTER QUESTION, ANSWERED WITHOUT ANY PALETTE CALIBRATION.
-- At 16 colours a byte is TWO pixels, so decoding a row number to an absolute value needs a
-- colour->index map for all sixteen entries. **But the question is a STRIDE, not a value.**
-- ★★★★ With the row-number fill every byte of source row N holds N, so all that is needed is: how
-- many CONSECUTIVE DISPLAYED ROWS share the same content? Above the switch the stride is 160 B/row
-- = one source row per displayed row, so the answer must be 1. Below it the stride is 80 B/row, so
-- two displayed rows fall inside one source row and the answer must be 2.
-- ★★★★★ **"1 above, 2 below, with no discontinuity at the boundary" is case 1**, and it is readable
-- from raw pixels with no knowledge of the palette at all.
-- ★★★ The signature is the row's FIRST 16 RASTER COLUMNS. Consecutive source rows differ by 1, so
-- their low nibble differs, and the low nibble falls inside the first 16 columns in BOTH modes --
-- which a single sampled column does not, because the column that holds a given nibble MOVES when
-- the pixel width changes. ★★ That trap is why this reads a span and not a point.
local function row_sig(buf, y)
    local o = y * SW * 4 + 1
    return buf:sub(o, o + 63)          -- 16 raster columns x 4 bytes
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ S-04 §4A(2): A SECOND READING THAT CANNOT ALIAS THE WAY THE SIGNATURE CAN.
-- The signature compares 16 raster columns as an opaque blob. This reads the TWO PIXELS of the row's
-- first byte explicitly -- at 320-wide, pixel 0 is columns 0-1 and pixel 1 is columns 2-3 -- and
-- reports them as a pair. **Two readings of the same frame that cannot fail together is the point**
-- [§3(2): the signature is the suspect and must not be used to test itself].
-- ★★★ It is deliberately narrower than the signature: 2 pixels, at named positions, in the 320-wide
-- reading. So it is only valid ABOVE the boundary -- which is exactly where the repeat lives.
local function pixpair_runs(buf, y0, y1)
    local runs, prev, n = {}, nil, 0
    for y = y0, y1 do
        local o = y * SW * 4 + 1
        local a = buf:sub(o + 1 * 4, o + 1 * 4 + 3)   -- column 1 = pixel 0 (the high nibble)
        local b = buf:sub(o + 3 * 4, o + 3 * 4 + 3)   -- column 3 = pixel 1 (the low nibble)
        local s = a .. b
        if s == prev then n = n + 1
        else
            if prev ~= nil then runs[#runs+1] = n end
            prev, n = s, 1
        end
    end
    if prev ~= nil then runs[#runs+1] = n end
    return runs
end
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local function sig_runs(buf, y0, y1)
    local runs, prev, n = {}, nil, 0
    for y = y0, y1 do
        local s = row_sig(buf, y)
        if s == prev then n = n + 1
        else
            if prev ~= nil then runs[#runs+1] = n end
            prev, n = s, 1
        end
    end
    if prev ~= nil then runs[#runs+1] = n end
    return runs
end
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local PROFILE_ROWS = { 30, 50, 70, 90, 110, 130, 150, 170, 190, 210 }
local function row_profile(buf)
    local out = {}
    for _, y in ipairs(PROFILE_ROWS) do out[#out+1] = { y, row_trans(buf, y) } end
    return out
end

local function transitions(buf)
    local x = SW // 2
    local t, prev = {}, nil
    for y = 0, SH - 1 do
        local o = (y * SW + x) * 4 + 1
        local p = buf:sub(o, o + 3)
        if prev ~= nil and p ~= prev then t[#t+1] = { y, prev, p } end
        prev = p
    end
    return t
end

-- ── the run ─────────────────────────────────────────────────────────────────────────────────
local frame, state, step, si, held = 0, "wait_ok", 0, 1, {}
local results = {}
local s02_f0 = nil   -- s01_frames at the moment the refill was acknowledged

_G._s01 = emu.add_machine_frame_notifier(function()
    frame = frame + 1

    if state == "wait_ok" then
        if decb_ready() then
            -- ★ Poke the image and the parameters, then take the machine.
            local fh = io.open(BIN, "rb")
            if not fh then w("★★★ no binary at %s", BIN); m:exit(); return end
            local blob = fh:read("*a"); fh:close()
            for i = 1, #blob do prog:write_u8(SYM.entry + i - 1, blob:byte(i)) end
            prog:write_u8(SYM.s01_mode, MODE)
            prog:write_u8(SYM.s01_colA, COL_A)
            prog:write_u8(SYM.s01_colB, COL_B)
            prog:write_u8(SYM.s01_fillm, FILLM)
            prog:write_u8(SYM.s01_fillb, FILLB)
            prog:write_u8(SYM.s01_vrest, VREST)
            prog:write_u8(SYM.s01_vresb, VRESB)
            -- ★ In a VOFFSET sweep the sweep list IS the VOFFSET list and the delay stays put.
            if VSWEEP then wr16(SYM.s01_voff, SWEEP[1]); wr16(SYM.s01_dly, 0)
            else           wr16(SYM.s01_voff, VOFF);     wr16(SYM.s01_dly, SWEEP[1]) end
            -- ★★★★ §4C's two extra splits. Zero means one split, exactly as S-01 ran.
            prog:write_u8(SYM.s01_big, BIG)
            prog:write_u8(SYM.s01_rowbase, ROWBASE)
            wr16(SYM.s01_dly2, DLY2)
            wr16(SYM.s01_dly3, DLY3)
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ EVERY PARAMETER THE GUEST'S **INIT** READS MUST BE POKED BEFORE PC IS SET.
            -- The first cut poked the S-02 palette and fill AFTER the handover, so the init had
            -- already run the fill and written the palette from the DEFAULTS -- and the calibration
            -- read four black pixels, because the guest had filled with $55 and set index 1 to $3F
            -- while the host believed it had asked for $1B and four distinct colours.
            -- ★★★★ It is a race, not a typo: the guest starts executing the instant PC is set, and
            -- the host's next writes land some cycles into the init. **A poke after handover only
            -- works for values the LOOP re-reads** -- s01_dly, s01_voff, s01_refill -- and never for
            -- ones the init consumes once.
            if ROWMAP then
                prog:write_u8(SYM.s01_fillm, 0)
                prog:write_u8(SYM.s01_fillb, 0x1B)   -- indices 0,1,2,3 in one byte
                -- ★★★★★ FOUR DISTINCT DISPLAYED COLOURS, and the FLIP moved to an undisplayed entry.
                -- The screen only stays current while a palette value changes (measured: a changing
                -- $FF99 alone is NOT enough), but the decode needs the displayed four to hold still.
                -- $FFB8 is not rendered in 4-colour mode, so flipping it satisfies both.
                prog:write_u8(SYM.s01_col0, 0x00)    -- black
                prog:write_u8(SYM.s01_col1, 0x09)    -- blue
                prog:write_u8(SYM.s01_col2, 0x12)    -- green
                prog:write_u8(SYM.s01_col3, 0x3F)    -- white
                -- ═══════════════════════════════════════════════════════════════════════════
                -- ★★★★★ THE FLIP TARGETS THE BORDER ($FF9A), NOT A PALETTE INDEX, AND AT 16 COLOURS
                -- THAT IS NOT OPTIONAL. S-02 pointed it at $FFB8 because 4-colour mode displays only
                -- indices 0-3, so index 8 was invisible. **At 16 colours EVERY index is displayed** --
                -- so the flip was overwriting index 8 with $3F, which equals pal16[7], and two indices
                -- rendered alike. That collision IS the entire "16-colour row repeat".
                -- ★★★★ MAME records the border per scanline too -- `update_value(&m_scanlines[..]
                -- .m_border, border)` -- so flipping $FF9A keeps the bitmap current without touching
                -- any picture colour. **The border is outside the decoded area, so it cannot alias.**
                -- ★★★ This is why editing s01_pal16 changed nothing: the colliding entry was never a
                -- pal16 entry. **The table was innocent and the flip was the culprit.**
                local PALREG = (BIG ~= 0) and 0x9A or 0xB8
                prog:write_u8(SYM.s01_palreg, PALREG)
                prog:write_u8(SYM.s01_colA, 0x3F)
                prog:write_u8(SYM.s01_colB, 0x00)
            end
            -- ═══════════════════════════════════════════════════════════════════════════════
            cpu.state["PC"].value = SYM.entry
            w("S-01 rev B  stage %d (%s)  %d bytes at $%04X  screen %dx%d",
              MODE, MODE == 0 and "PALETTE -- the control" or "HRES", #blob, SYM.entry, SW, SH)
            w("  colA=$%02X colB=$%02X  sweep %d values  settle %d frames, sample %d",
              COL_A, COL_B, #SWEEP, SETTLE, SAMPLES)
            -- ★★★★★ ECHO EVERY PARAMETER AS RECEIVED. The same VOFFSET produced a clean profile when
            -- reached by a sweep and a broken one when set directly, which is impossible if both
            -- paths deliver the same value -- so the value each path actually delivers is printed
            -- rather than assumed. Two hypotheses about the SCREEN were already eliminated; this
            -- tests the boring one about the HOST that should have been checked first.
            w("  as received: vsweep=%s voff=$%04X vrest=$%02X vresb=$%02X fillm=%d fillb=$%02X"
              .. "  guest s01_voff now $%04X",
              tostring(VSWEEP), VOFF, VREST, VRESB, FILLM, FILLB, rd16(SYM.s01_voff))
            -- ★★★★★ READ THE PARAMETERS BACK OUT OF THE GUEST. Everything above is what the HOST
            -- believes it sent; this is what the guest will actually execute on. Stage 1 renders
            -- differently from stage 0 while doing a strict superset of stage 0's register writes,
            -- so the remaining suspect is the VALUE reaching $FF99 -- and a poke to a mis-resolved
            -- symbol would look exactly like this [§2W.3: resolve, do not assume].
            w("  guest holds: mode=%d vrest=$%02X vresb=$%02X colA=$%02X colB=$%02X fillm=%d fillb=$%02X",
              prog:read_u8(SYM.s01_mode), prog:read_u8(SYM.s01_vrest), prog:read_u8(SYM.s01_vresb),
              prog:read_u8(SYM.s01_colA), prog:read_u8(SYM.s01_colB),
              prog:read_u8(SYM.s01_fillm), prog:read_u8(SYM.s01_fillb))
            w("  DECB ready at frame %d, handed over to $%04X", frame, SYM.entry)
            if ROWMAP then
                w("  ★ S-02 ROW MAP: phase 1 = calibration fill $1B, phase 2 = row-number fill")
                w("    (palette and fill were poked BEFORE handover -- the init consumes them once)")
                if BIG then
                    -- ★★★★ 16 colours: the signature instrument needs no colour->index map, so the
                    -- calibration phase is skipped and the row-number fill goes straight in.
                    prog:write_u8(SYM.s01_fillm, 1)
                    prog:write_u8(SYM.s01_refill, 1)
                    state, step = "s02_wait_refill", 0
                else
                    state, step = "s02_cal", 0
                end
            elseif EYE then
                w("  ★ EYE RUN: holding dly=%d, no sweep, normal speed. Close the window when done.",
                  SWEEP[1])
                state, step = "eye", 0
            else
                state, step = "settle", 0
            end
        elseif frame > OK_TMO then
            w("★★★ no OK prompt after %d frames -- the machine never got to DECB", frame)
            m:exit()
        end
        return
    end

    step = step + 1

    -- ═══════════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ S-02: WHERE DOES THE DATA BELOW THE SWITCH COME FROM?
    -- Phase 1 fills with $1B and calibrates colour->index. Phase 2 pokes the row-number fill, waits
    -- for the guest to ACKNOWLEDGE the refill by clearing the flag, and reads every scanline back.
    -- ★★★★ The refill is acknowledged rather than assumed: a table decoded off the PREVIOUS fill is
    -- L-92's defect and would look like a perfectly ordinary answer.
    -- ═══════════════════════════════════════════════════════════════════════════════════════
    if state == "s02_cal" then
        if step < 45 then return end
        local buf = grab()
        local ok, dup = calibrate(buf, 40)
        -- ★★★ Print the four colours whether it passes or fails. The first failure said only
        -- "indices 1 render alike", which named the symptom and not the datum -- and the datum
        -- (two entries holding the same palette byte) is what identified the cause immediately.
        local shown = {}
        for k = 0, 3 do
            local o = 40 * SW * 4 + 1 + (k * 2) * 4
            local v = buf:sub(o, o + 3)
            shown[#shown+1] = string.format("px%d=%02X%02X%02X", k,
              v:byte(3) or 0, v:byte(2) or 0, v:byte(1) or 0)
        end
        w("  calibration (fill $1B at y=40): %s", table.concat(shown, " "))
        -- ★★★ The raw row and the framebuffer beside it, because "four black pixels" is a symptom
        -- shared by a wrong palette, a wrong fill, and a screen that is not showing the framebuffer.
        -- Printing all three separates them in one look instead of another round of hypotheses.
        do
            local runs, order = row_runs(buf, 40, 12)
            w("    y=40 runs %s | colours %s", table.concat(runs, ","), table.concat(order, " "))
            local fb = {}
            for i = 0, 5 do fb[#fb+1] = string.format("%02X", prog:read_u8(0x4000 + i)) end
            w("    framebuffer $4000.. = %s   (expect 1B 1B 1B ...)", table.concat(fb, " "))
            w("    guest palette bytes: col0=$%02X col1=$%02X col2=$%02X col3=$%02X palreg=$%02X",
              prog:read_u8(SYM.s01_col0), prog:read_u8(SYM.s01_col1), prog:read_u8(SYM.s01_col2),
              prog:read_u8(SYM.s01_col3), prog:read_u8(SYM.s01_palreg))
            w("    guest fillm=%d fillb=$%02X  frames=%d",
              prog:read_u8(SYM.s01_fillm), prog:read_u8(SYM.s01_fillb), rd16(SYM.s01_frames))
            -- ★★★★★ WHERE IS THE GUEST? `frames = 0` says the loop never completed an iteration, and
            -- that is consistent with a crash, a spin in the VBORD wait, and never reaching the loop
            -- at all. The PC distinguishes all three in one read, and guessing between them has
            -- already cost two rounds.
            w("    guest PC=$%04X S=$%04X   (loop $%04X, vb wait $%04X, do_fill $%04X, palwr $%04X)",
              cpu.state["PC"].value, cpu.state["S"].value,
              SYM.s01_loop or 0, SYM.s01_vb or 0, SYM.s01_do_fill or 0, SYM.s01_palwr or 0)
        end
        if not ok then
            w("★★★ CALIBRATION FAILED: pixel %s renders the same as an earlier one -- two palette",
              tostring(dup))
            w("    entries hold the same value, so the row-number decode cannot be unambiguous. STOP.")
            m:exit(); return
        end
        w("  -> 4 distinct colours mapped to indices 0..3")
        prog:write_u8(SYM.s01_fillm, 1)
        prog:write_u8(SYM.s01_refill, 1)
        state, step = "s02_wait_refill", 0
        return
    end

    -- ═══════════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ WAIT FOR THE GUEST TO COMPLETE LOOP ITERATIONS, NOT FOR A FRAME COUNT. The guest clears
    -- s01_refill BEFORE it starts filling, so the ack says "request received", not "fill finished" --
    -- and at 16 colours the fill is 30,720 bytes at ~40 cycles each, **about 41 frames**. A fixed
    -- 60-frame wait after the ack sampled a half-filled buffer and read `s01_frames = 0`, which is
    -- exactly what an unfinished fill looks like.
    -- ★★★★ `s01_frames` only ticks at the END of an iteration, so requiring it to RISE is a positive
    -- signal that the fill returned and the loop is running again. **That is an acknowledgement; a
    -- frame count is an assumption**, and this is the third time in the series that the difference
    -- has mattered.
    if state == "s02_wait_refill" then
        if prog:read_u8(SYM.s01_refill) ~= 0 then
            if step > 900 then
                w("★★★ the guest never acknowledged the refill -- STOP"); m:exit()
            end
            return
        end
        s02_f0 = s02_f0 or rd16(SYM.s01_frames)
        if rd16(SYM.s01_frames) < s02_f0 + 3 then
            if step > 1200 then
                w("★★★ the refill never completed: s01_frames stuck at %d -- STOP",
                  rd16(SYM.s01_frames)); m:exit()
            end
            return
        end
        w("  refill acknowledged and %d loop iterations completed since", 3)
        state, step = "s02_read", 0
        return
    end

    if state == "s02_read" then
        local buf = grab()
        w("")
        w("── §4A: which SOURCE ROW arrives on each displayed scanline ──")
        w("   fill: row N holds byte value N in all 80 of its bytes; decoded from 4 pixels/row")
        w("   w=2 is the 320-wide reading (2 raster columns per pixel); w=4 is the 160-wide reading")
        -- compress consecutive rows that decode to the same source row, per width
        for _, pw in ipairs({ 2, 4 }) do
            local parts, runstart, prev = {}, nil, nil
            for y = 25, 217 do
                local d = decode_row(buf, y, pw)
                if d ~= prev then
                    if prev ~= nil then
                        parts[#parts+1] = string.format("y%d-%d=%s", runstart, y - 1,
                          prev == nil and "?" or tostring(prev))
                    end
                    runstart, prev = y, d
                end
            end
            if prev ~= nil or runstart then
                parts[#parts+1] = string.format("y%d-%d=%s", runstart or 25, 217,
                  prev == nil and "?" or tostring(prev))
            end
            w("   w=%d: %s", pw, table.concat(parts, "  "))
        end
        -- ═══════════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ S-03's calibration-free reading: displayed rows per source row, as run lengths
        -- down the screen. 1 above the boundary, 2 below, and a clean transition between them is
        -- case 1. Works at any colour depth because it compares raw pixels to raw pixels.
        local runs = sig_runs(buf, 25, 217)
        local ones, twos, other, obad = 0, 0, 0, {}
        for _, n in ipairs(runs) do
            if n == 1 then ones = ones + 1
            elseif n == 2 then twos = twos + 1
            else other = other + 1; if #obad < 8 then obad[#obad+1] = n end end
        end
        w("   displayed rows per source row, top to bottom: %s",
          table.concat(runs, ","))
        w("   -> runs of 1: %d   runs of 2: %d   anything else: %d%s",
          ones, twos, other,
          other > 0 and ("  [" .. table.concat(obad, ",") .. "]") or "")
        -- ★★★★★ §4A(2): the SECOND, independent reading of the SAME frame. If it disagrees with the
        -- signature, neither is trusted (§6's first trigger) and the instrument needs work before the
        -- question can be asked at all.
        do
            local pruns = pixpair_runs(buf, 25, 217)
            local p1, p2, pother = 0, 0, 0
            for _, n in ipairs(pruns) do
                if n == 1 then p1 = p1 + 1 elseif n == 2 then p2 = p2 + 1 else pother = pother + 1 end
            end
            w("   §4A(2) pixel-pair reading (cols 1 and 3, the 320-wide reading):")
            w("      %s", table.concat(pruns, ","))
            w("      -> runs of 1: %d   runs of 2: %d   anything else: %d", p1, p2, pother)
            w("      %s", (p2 == twos and pother == other)
                 and "★ AGREES with the signature reading"
                 or  "★★★ DISAGREES with the signature reading -- neither may be trusted [§6]")
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE 16 RENDERED COLOURS, AND A DUPLICATE CHECK. The repeats track the byte value
            -- mod 16 -- low nibble 6 -- which is a property of the DATA, not of screen position. The
            -- only way two rows differing in the low nibble can look identical is if two PALETTE
            -- INDICES RENDER ALIKE. ★★★★ With the row-number fill, rows 0..15 have high nibble 0, so
            -- pixel 1 (column 3) of the first sixteen displayed rows IS index 0..15 in order.
            -- ★★★ This is the clinching datum: if there is a duplicate, the repeat is my palette and
            -- the display is clean. S-03 set 16 distinct palette BYTES and never checked that they
            -- render distinctly -- **distinct inputs are not distinct outputs.**
            local seen, dups = {}, {}
            local cols = {}
            for i = 0, 15 do
                local y = 25 + i
                local o = y * SW * 4 + 1 + 3 * 4       -- column 3 = pixel 1 = the low nibble
                local v = buf:sub(o, o + 3)
                local hex = string.format("%02X%02X%02X", v:byte(3) or 0, v:byte(2) or 0, v:byte(1) or 0)
                cols[#cols+1] = string.format("%d=%s", i, hex)
                if seen[v] ~= nil then dups[#dups+1] = string.format("%d==%d", seen[v], i) end
                seen[v] = i
            end
            w("   rendered palette (index=RRGGBB, read from rows 25..40 pixel 1):")
            w("      %s", table.concat(cols, " "))
            if #dups > 0 then
                w("   ★★★★★ DUPLICATE RENDERED COLOURS: %s", table.concat(dups, " "))
                w("      -> the 'row repeat' is MY PALETTE, not the display. Two indices render alike,")
                w("         so two source rows differing only in that nibble are indistinguishable.")
            else
                w("   ★ all 16 indices render distinctly -- a palette collision is NOT the explanation")
            end
        end
        -- ═══════════════════════════════════════════════════════════════════════════════════
        -- ★★★ and the transition profile of the SAME frame, to locate the boundary independently
        local pr = {}
        for _, e in ipairs(row_profile(buf)) do pr[#pr+1] = string.format("%d:%d", e[1], e[2]) end
        w("   transition profile (same frame): %s", table.concat(pr, "  "))
        -- ═══════════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ VERIFY THE BUFFER BEFORE BLAMING THE DISPLAY. The 16-colour run shows one source row
        -- repeated every 16 scanlines -- a 16/15 ratio -- and that is equally consistent with the FILL
        -- writing a value twice as with the display repeating a row. **They call for opposite fixes.**
        -- ★★★★ Row N should start at byte N*stride and hold the value N. Blocks $3A/$3B are mapped
        -- after the fill restores them, so rows 0..~100 are readable at logical $4000 + N*stride.
        -- ★★★ This is the same discipline as S-01's framebuffer readback, which is what proved the fill
        -- correct and sent the search to the display path instead of round in circles.
        do
            local stride = (BIG ~= 0) and 160 or 80
            local nmax = (0x8000 - 0x4000) // stride - 1
            local bad, shown = {}, {}
            for n = 0, math.min(nmax, 100) do
                local v = prog:read_u8(0x4000 + n * stride)
                if v ~= (n % 256) then
                    if #bad < 10 then bad[#bad+1] = string.format("row%d=$%02X", n, v) end
                end
                if n < 6 or (n >= 30 and n < 34) then
                    shown[#shown+1] = string.format("r%d=$%02X", n, v)
                end
            end
            w("   framebuffer rows (stride %d): %s", stride, table.concat(shown, " "))
            if #bad == 0 then
                w("   ★ FILL VERIFIED over rows 0..%d -- every row holds its own number, so any",
                  math.min(nmax, 100))
                w("     repeat on screen is the DISPLAY's, not the fill's")
            else
                w("   ★★★ FILL IS WRONG: %s -- the screen result says nothing about the GIME",
                  table.concat(bad, " "))
            end
        end
        -- ═══════════════════════════════════════════════════════════════════════════════════
        w("   guest frames %d", rd16(SYM.s01_frames))
        local fh = io.open(OUT .. "/s02_rowmap.txt", "w")
        if fh then fh:write(table.concat(log, "\n") .. "\n"); fh:close() end
        m:exit()
        return
    end

    -- ★★ The eye run reports the boundary ONCE, a second after handover, so the number Jay is
    -- looking at and the number in the log are the same observation -- then it stays out of the way.
    if state == "eye" then
        if step == 60 then
            local buf = grab()
            local t = transitions(buf)
            local ys = {}
            for _, e in ipairs(t) do ys[#ys+1] = tostring(e[1]) end
            w("  boundary sample at handover+60 frames: %d transitions at y=[%s]  guest frames %d",
              #t, table.concat(ys, ","), rd16(SYM.s01_frames))
            w("  (active display is y=25..217 = 192 lines, measured in the stage-0 sweep)")
            if MODE == 1 then
                local parts = {}
                for _, e in ipairs(row_profile(buf)) do
                    parts[#parts+1] = string.format("%d:%d", e[1], e[2])
                end
                w("  row transitions (halving = the resolution changed): %s",
                  table.concat(parts, "  "))
            end
            local fh = io.open(OUT .. "/s01_eye" .. MODE .. ".txt", "w")
            if fh then fh:write(table.concat(log, "\n") .. "\n"); fh:close() end
        end
        return
    end

    if state == "settle" then
        if step >= SETTLE then state, step, held = "sample", 0, {} end
        return
    end

    if state == "sample" then
        local buf = grab()
        held[#held+1] = { transitions(buf), rd16(SYM.s01_frames), buf }
        if step < SAMPLES then return end
        -- ★★★ Report every sampled frame's transition list, not a summary: "steady" is a claim
        -- about frames agreeing and it cannot be made from one of them.
        local dly = SWEEP[si]
        local rows = {}
        for _, h in ipairs(held) do
            local parts = {}
            for _, t in ipairs(h[1]) do parts[#parts+1] = tostring(t[1]) end
            rows[#rows+1] = { table.concat(parts, ","), #h[1], h[2] }
        end
        local same = true
        for i = 2, #rows do if rows[i][1] ~= rows[1][1] then same = false end end
        -- ★★★★★ LIVENESS IS MEASURED WITHIN ONE SAMPLE POINT, NOT ACROSS SWEEP ROWS, BECAUSE THE
        -- ACROSS-ROWS VERSION COULD NOT FAIL -- AND COULD NOT PASS -- ON A ONE-VALUE SWEEP [§2W].
        -- The first cut compared results[1].frames with results[#results].frames; with a single
        -- delay those are the SAME ROW, so the test read `x > x`, declared the guest STALLED and
        -- printed RESULT: VOID over a run whose counter had reached 20. **A liveness check that a
        -- live guest cannot pass is worse than none, because it voids real results.**
        -- ★★★ This compares the counter at the first and last frame of THIS delay's sample window,
        -- which rises for any running guest regardless of how many delays are swept.
        local rose = rows[#rows][3] > rows[1][3]
        results[#results+1] = { dly = dly, ys = rows[1][1], n = rows[1][2],
                                frames = rows[#rows][3], steady = same, rose = rose }
        w("  %s %5d  transitions %d at y=[%s]  guest frames %5d  %s",
          VSWEEP and "VOFF " or "dly  ",
          dly, rows[1][2], rows[1][1], rows[#rows][3],
          same and "steady across samples" or "★★★ JITTERING between samples")
        -- ★★★★★ THE RAW ROWS PRINT FOR EVERY MODE INCLUDING STAGE 0, because stage 0 is the one arm
        -- KNOWN GOOD -- Jay watched it -- and the only way to tell what is wrong with the others is
        -- to compare their raw pixels against a run that is known to be in graphics mode. A working
        -- reference is only useful if the same instrument is pointed at it.
        for _, y in ipairs({ 30, 110, 210 }) do
            local runs, order = row_runs(held[#held][3], y, 16)
            w("        y=%3d runs %s | colours %s", y,
              table.concat(runs, ","), table.concat(order, " "))
        end
        if MODE ~= 0 then
            local pr, parts = row_profile(held[#held][3]), {}
            local hi, lo = 0, 9999
            for _, e in ipairs(pr) do
                parts[#parts+1] = string.format("%d:%d", e[1], e[2])
                if e[2] > hi then hi = e[2] end
                if e[2] < lo and e[2] > 0 then lo = e[2] end
            end
            w("        row transitions  %s", table.concat(parts, "  "))
            w("        widest %d  narrowest %d  ratio %.2f  (2.00 = the resolution halved)",
              hi, lo, lo > 0 and hi / lo or 0)
            results[#results].ratio = lo > 0 and hi / lo or 0
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE BOUNDARY, FROM THE ROW PROFILE, BECAUSE THE COLUMN CANNOT SEE IT AND THE
            -- VERDICT WAS READING THE COLUMN. With a striped fill every pixel in a column is the
            -- same colour, so `transitions` is legitimately 0 -- and the verdict, which counts
            -- distinct COLUMN patterns, therefore printed "RESULT: NO SPLIT" over a row profile that
            -- showed 159,159,159,159,159,79,79,79,79,79 and a ratio of 2.01.
            -- ★★★★★ **An adjudicator reading the wrong artifact is AD-131's defect exactly**, and it
            -- would have reported the opposite of what the run measured. The boundary for an HRES
            -- split is the row where the transition count drops, and nothing else.
            local bnd = nil
            for i = 2, #pr do
                if pr[i - 1][2] > 0 and pr[i][2] > 0 and pr[i - 1][2] >= 1.5 * pr[i][2] then
                    bnd = pr[i][1]; break
                end
            end
            results[#results].bnd = bnd
            w("        HRES boundary: %s", bnd and ("first narrow row y=" .. bnd)
                                               or "none -- one resolution for the whole frame")
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ THE SELF-CHECK THAT WOULD HAVE CAUGHT THE BROKEN SPIKE ON ITS FIRST RUN, AND
            -- IT IS THE ONE I DID NOT WRITE. With a CONSTANT fill, every row of the framebuffer is
            -- byte-identical, so in a STATIC mode every sampled row MUST have the same non-zero
            -- transition count. A zero row, or rows that disagree, means the display is not showing
            -- this framebuffer -- and no statement about HRES can be made from it.
            -- ★★★★ It runs on mode 2 (static) with fillm=0, which is exactly the reference run, so
            -- the instrument is checked by the same pass that produces the baseline [§2W].
            -- ═══════════════════════════════════════════════════════════════════════════════
            -- ★★★★★ READ THE FRAMEBUFFER BACK. This is what separates the two hypotheses the
            -- broken self-check leaves open -- "the fill never happened" and "the display is
            -- pointed somewhere else" -- and they call for completely different fixes. A screen
            -- that disagrees with the buffer is a VOFFSET/MMU fault; a buffer that disagrees with
            -- itself is a fill fault. ★★★ Guessing between them is what §2H's first check forbids.
            do
                local probe, bad = {}, 0
                for _, a in ipairs({0x4000, 0x5000, 0x6000, 0x7000, 0x7BFF}) do
                    local v = prog:read_u8(a)
                    probe[#probe+1] = string.format("$%04X=$%02X", a, v)
                    if v ~= FILLB then bad = bad + 1 end
                end
                w("        framebuffer readback (expect $%02X): %s  -> %s",
                  FILLB, table.concat(probe, " "),
                  bad == 0 and "FILL IS CORRECT -- any screen mismatch is the DISPLAY path"
                           or string.format("★★★ %d of 5 WRONG -- the FILL is at fault", bad))
            end
            local zero, disagree = 0, false
            for _, e in ipairs(pr) do
                if e[2] == 0 then zero = zero + 1 end
                if math.abs(e[2] - pr[1][2]) > 8 then disagree = true end
            end
            if MODE == 2 and FILLM == 0 then
                if zero > 0 or disagree then
                    w("        ★★★★★ SPIKE BROKEN: a constant fill in a STATIC mode must render every")
                    w("              row alike, and %d of %d rows are blank%s. The display is NOT",
                      zero, #pr, disagree and " and the counts disagree" or "")
                    w("              showing this framebuffer -- VOFFSET, the MMU map or the fill is")
                    w("              wrong. NOTHING may be concluded about HRES from this run.")
                    results[#results].self_ok = false
                else
                    w("        ★ self-check: all %d sampled rows patterned and within tolerance --", #pr)
                    w("          the display IS showing this framebuffer (VOFFSET + MMU confirmed)")
                    results[#results].self_ok = true
                end
            end
        end
        si = si + 1
        if si > #SWEEP then
            state = "done"
        else
            -- ★ VOFFSET takes effect at the guest's next init only if written at init; it is read
            -- every frame here instead, so poking it mid-run is enough and no relaunch is needed.
            if VSWEEP then wr16(SYM.s01_voff, SWEEP[si]) else wr16(SYM.s01_dly, SWEEP[si]) end
            state, step = "settle", 0
        end
        return
    end

    if state == "done" then
        -- ═══════════════════════════════════════════════════════════════════════════════════
        -- ★★★★★ THE VERDICT, AND IT IS COMPUTED RATHER THAN EYEBALLED. Stage 0 passes only if the
        -- boundary MOVED as the delay swept. A fixed set of transitions across every delay means
        -- the register write is not being sampled during the scan, whatever the screen looks like.
        -- ═══════════════════════════════════════════════════════════════════════════════════
        local distinct, first = {}, nil
        -- ★ alive if the counter rose inside ANY sample window (see the note at `rose`).
        local alive = false
        for _, r in ipairs(results) do if r.rose then alive = true end end
        for _, r in ipairs(results) do
            distinct[r.ys] = (distinct[r.ys] or 0) + 1
            first = first or r.ys
        end
        local nd = 0; for _ in pairs(distinct) do nd = nd + 1 end
        w("")
        w("── verdict ──")
        w("  distinct transition patterns across %d delays: %d", #results, nd)
        w("  guest liveness: s01_frames %d -> %d  (%s)",
          results[1].frames, results[#results].frames,
          alive and "RUNNING" or "★★★ STALLED -- this spike is broken, not the GIME")
        if not alive then
            w("  ★★★★★ RESULT: VOID. The guest was not executing its loop, so the screen says")
            w("        nothing about whether MAME samples registers mid-frame.")
        -- ★★★★★ MODE 1 IS ADJUDICATED FIRST, BEFORE THE COLUMN-BASED BRANCHES. The `nd <= 1` test
        -- counts distinct COLUMN patterns, which for a striped fill are legitimately all empty -- so
        -- it fired first and printed "NO SPLIT" over a perfect 159->79 row profile. **Ordering was
        -- the defect, not the test**: the column branches belong to stage 0, where the boundary IS a
        -- colour change, and mode 1's evidence is the row profile.
        elseif MODE == 1 then
            local bnds, nmoved, ratio_ok = {}, 0, 0
            for _, r in ipairs(results) do
                if r.bnd then bnds[#bnds+1] = r.bnd end
                if (r.ratio or 0) >= 1.7 and (r.ratio or 0) <= 2.3 then ratio_ok = ratio_ok + 1 end
            end
            local distinct_b = {}
            for _, b in ipairs(bnds) do distinct_b[b] = true end
            for _ in pairs(distinct_b) do nmoved = nmoved + 1 end
            w("  HRES boundaries across the sweep: %s", table.concat(bnds, ", "))
            w("  distinct boundary positions %d of %d delays; ratio in [1.7,2.3] on %d",
              nmoved, #results, ratio_ok)
            if #bnds == 0 then
                w("  ★★★★★ RESULT: NO HRES SPLIT -- one resolution for the whole frame at every delay.")
            elseif nmoved >= 2 and ratio_ok == #results then
                w("  ★★★★★ RESULT: STAGE 1 PASSED. A mid-frame HRES change HOLDS: the horizontal")
                w("        resolution halves below the write (ratio ~2.0 at every delay) AND the")
                w("        boundary tracks the poked delay, so the register write is what places it.")
                w("        ★★ Still unproven on silicon: two GIME revisions exist, the later changed")
                w("        video timings, and MAME models one behaviour. 'Worth building on', never")
                w("        'proven'.")
            else
                w("  ★★★★★ RESULT: PARTIAL -- a boundary exists but %s.",
                  nmoved < 2 and "it does not move with the delay"
                             or "the width ratio is not ~2.0 everywhere")
            end
        elseif nd <= 1 then
            w("  ★★★★★ RESULT: NO SPLIT. The boundary did not move across the whole sweep.")
            if MODE == 0 then
                w("        STAGE 0 FAILED -> MAME renders from frame-start register state and")
                w("        CANNOT answer this class of question. 160-wide stays OPEN, pending")
                w("        hardware. This is NOT a close [§7].")
            else
                w("        STAGE 1 FAILED. Only meaningful if stage 0 PASSED.")
            end
        elseif MODE == 1 then
            -- ★★★★★ MODE 1's VERDICT IS BUILT FROM THE ROW PROFILE, NOT THE COLUMN COUNT. Two
            -- conditions, and both are required: the resolution must HALVE (ratio ~2.0, which says
            -- it is the resolution and not merely the data re-phasing) and the boundary must MOVE
            -- with the poked delay (which says the register write is what placed it).
            local bnds, nmoved, ratio_ok = {}, 0, 0
            for _, r in ipairs(results) do
                if r.bnd then bnds[#bnds+1] = r.bnd end
                if (r.ratio or 0) >= 1.7 and (r.ratio or 0) <= 2.3 then ratio_ok = ratio_ok + 1 end
            end
            local distinct_b = {}
            for _, b in ipairs(bnds) do distinct_b[b] = true end
            for _ in pairs(distinct_b) do nmoved = nmoved + 1 end
            w("  HRES boundaries across the sweep: %s", table.concat(bnds, ", "))
            w("  distinct boundary positions %d of %d delays; ratio in [1.7,2.3] on %d",
              nmoved, #results, ratio_ok)
            if #bnds == 0 then
                w("  ★★★★★ RESULT: NO HRES SPLIT -- one resolution for the whole frame at every delay.")
            elseif nmoved >= 2 and ratio_ok == #results then
                w("  ★★★★★ RESULT: STAGE 1 PASSED. A mid-frame HRES change HOLDS: the horizontal")
                w("        resolution halves below the write (ratio ~2.0 at every delay) AND the")
                w("        boundary tracks the poked delay, so the register write is what places it.")
                w("        ★★ Still unproven on silicon: two GIME revisions exist, the later changed")
                w("        video timings, and MAME models one behaviour. 'Worth building on', never")
                w("        'proven'.")
            else
                w("  ★★★★★ RESULT: PARTIAL -- a boundary exists but %s.",
                  nmoved < 2 and "it does not move with the delay"
                             or "the width ratio is not ~2.0 everywhere")
            end
        elseif false then
            -- ★★★★★ For HRES the moving boundary is NOT sufficient on its own: the byte-provenance
            -- shift below a switch changes the CONTENT and could move a colour boundary without the
            -- resolution changing at all. **The resolution claim rests on the width ratio.**
            local best = 0
            for _, r in ipairs(results) do if (r.ratio or 0) > best then best = r.ratio end end
            w("  best width ratio across the sweep: %.2f", best)
            if best >= 1.7 then
                w("  ★★★★★ RESULT: STAGE 1 PASSED. A mid-frame HRES change is honoured -- the")
                w("        boundary moves with the delay AND the horizontal period nearly doubles")
                w("        below it, which is the resolution and not merely the data.")
                w("        ★★ Still unproven on silicon: two GIME revisions exist, the later changed")
                w("        video timings, and MAME models one behaviour [§3.4]. 'Worth building on',")
                w("        never 'proven'.")
            else
                w("  ★★★★★ RESULT: A BOUNDARY MOVED BUT THE RESOLUTION DID NOT CHANGE (ratio %.2f).",
                  best)
                w("        That is a CONTENT shift, not an HRES change -- the address counter")
                w("        re-phasing below the write would do exactly this. Stage 1 FAILS on its")
                w("        own terms and the distinction is the whole point of measuring width.")
            end
        else
            w("  ★★★★★ RESULT: THE BOUNDARY MOVES with the poked delay (%d distinct patterns).", nd)
            if MODE == 0 then
                w("        STAGE 0 PASSED -> MAME samples video registers during the scan, so an")
                w("        HRES result from it is worth having. Proceed to stage 1.")
            else
                w("        STAGE 1: a mid-frame HRES change is honoured by the model. Still")
                w("        unproven on silicon -- two GIME revisions exist [§3.4].")
            end
        end
        -- a snapshot for Jay (§5); never interpreted here (§3)
        local ok = pcall(function() m.video:snapshot() end)
        w("  snapshot: %s", ok and "written to MAME's snap directory" or "unavailable")
        local fh = io.open(OUT .. "/s01_stage" .. MODE .. ".txt", "w")
        if fh then fh:write(table.concat(log, "\n") .. "\n"); fh:close() end
        m:exit()
    end
end)
