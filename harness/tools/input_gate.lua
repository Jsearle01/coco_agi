-- harness/tools/input_gate.lua -- type a command; check it reaches the parser. [P6.23 AC-4/AC-1]
--
-- ★★★★★ THE KEYS ARE REAL. natkeyboard:post drives MAME's own keyboard, which drives the CoCo3
-- PIA matrix, which is what HAL_key_scan reads -- so this exercises the decoder against the
-- emulated hardware rather than against a table of what the hardware ought to do.
--
-- ★★★★ TWO RECORDED GOTCHAS, both obeyed rather than rediscovered [mame-idioms §14b, §20d]:
--   14b  natkeyboard.in_use defaults to FALSE and arming it in the same frame as the first post
--        loses the post. It is armed AT SCRIPT LOAD, frames before anything is typed.
--   20d  MAME mis-delivers the SHIFTED DOUBLE QUOTE intermittently. No test string here uses one.
--
-- ★★★ IT RUNS THROTTLED WHEN TS_WATCH=1 (AC-1, a human is looking) and unthrottled otherwise
-- (AC-4, a byte check) -- §2U.2.
--
-- ★★ Environment: IP_PROG, IP_FONT, IP_VOCAB, IP_TEXT, IP_MAP, IP_WATCH.
-- ★ §2P: types a command and puts it on screen. Prints word NUMBERS and counts, never characters.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- ★★★★★ ARMED ONLY WHEN WE ARE GOING TO POST, AND THAT IS A CORRECTION. Idiom 14b is still true --
-- arming in the same frame as the first post silently drops the keys -- so a POSTING run arms at
-- script load, frames ahead.
-- ★★★★ BUT natural-keyboard mode is for POSTING CHARACTERS, and it is the wrong mode for a person
-- at the keys: it translates host keys by CHARACTER rather than driving the matrix position, and
-- Jay could not see what he typed. **A live keyboard wants MAME's ordinary key emulation**, which
-- maps each host key straight onto its matrix field -- the same fields key_coverage.lua asserts.
-- ★★★ So it is armed on the posting path and left alone on the interactive one.
if os.getenv("IP_NOPOST") ~= "1" then
    m.natkeyboard.in_use = true
end
local REBIND_BS = os.getenv("IP_NOPOST") == "1"

local PROG  = os.getenv("IP_PROG")  or "build/input_probe.bin"
local FONT  = os.getenv("IP_FONT")  or "build/text_font.bin"
local VOCAB = os.getenv("IP_VOCAB") or ""
local TEXT  = os.getenv("IP_TEXT")  or "look at the rock"
-- ★★★★★ AN EXPLICIT FLAG, BECAUSE AN EMPTY STRING IS NOT A SENTINEL HERE. The first version used
-- IP_TEXT="" to mean "the operator types it" -- and **PowerShell DELETES an environment variable
-- assigned the empty string**, so os.getenv returned nil, the `or` fell through to the default,
-- and the probe scripted a line into what was supposed to be a live keyboard.
-- ★★★★ It reproduced byte for byte across two sessions -- 17 keys, egon=2, words 2,37 -- which is
-- what gave it away: "look at the rock" is 16 characters plus Enter. **A human typing twice does
-- not produce identical counts**, and that mismatch is the only thing that distinguished a
-- scripted line from a typed one in the log.
local NOPOST = os.getenv("IP_NOPOST") == "1"
local MAP   = os.getenv("IP_MAP")   or "build/input_probe.map"
local WATCH = os.getenv("IP_WATCH") == "1"

local IP_GO, IP_DONE, IP_NKEY = 0x0020, 0x0021, 0x0022
local IP_EGON, IP_LASTK, IP_NRAW = 0x0023, 0x0024, 0x0025
local IP_FONT_A, IP_VOCAB_A, IP_EGOLOG = 0x3400, 0x6000, 0x4600
local IP_INBUF = 0x4200

-- ★★★★★ READ BACK WHAT THE DECODER RESOLVED, NOT JUST HOW MANY KEYS IT SAW. The first version
-- logged counts and word numbers only -- so when Jay asked "what keys did you get?" the answer was
-- that I had not captured them. **I asked him to judge letterforms on a screen while recording
-- nothing that could be compared against what he typed.**
-- ★★★★ This is the one comparison that separates "the blitter drew the wrong shape" from "the
-- decoder resolved the wrong character": if the buffer says `look at rock` and the screen showed
-- something else, the fault is the blitter; if the buffer is wrong too, it is the decoder.
-- ★★ §2P does not bite here: this is the operator's own typing, not game text.
local function read_line()
    local s = {}
    for i = 0, 41 do
        local c = prog:read_u8(IP_INBUF + i)
        if c == 0 then break end
        s[#s + 1] = (c >= 0x20 and c < 0x7F) and string.char(c)
                    or string.format("<%02X>", c)
    end
    return table.concat(s)
end

local sym = {}
do
    local f = io.open(MAP, "r")
    if f then
        for line in f:lines() do
            local n, v = line:match("^Symbol:%s+(%S+)%s+%b()%s+=%s+(%x+)")
            if n then sym[n] = tonumber(v, 16) end
        end
        f:close()
    end
end

-- ★★ File scope and BELOW `sym`, because two readers need it -- the matrix trace and the per-line
-- report -- and a closure written above `local sym` captures the nil global instead of the table.
-- ★ Returning -1 for a missing symbol rather than throwing is deliberate: it names the gap without
-- killing a session a person is typing into.
local function u8(n) return sym[n] and prog:read_u8(sym[n]) or -1 end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ HOST BINDING, NOT PORT BEHAVIOUR, AND THE DISTINCTION IS THE WHOLE POINT. The CoCo3 has
-- no Backspace key; AGI's backspace is CLEAR, and hal_globals.s maps CLEAR to $08 already. But
-- MAME binds the PC's Backspace to the CoCo3 LEFT ARROW -- the platform convention, since that is
-- what BASIC backspaces with -- so an operator pressing Backspace presses LEFT, the input line
-- correctly discards it as a movement key, and **a working backspace looks broken**.
-- ★★★★ LEFT CANNOT SIMPLY BECOME BACKSPACE: AGI walks ego with the arrow keys while the input
-- line is up, so that key is spoken for. The fix belongs on the host side.
-- ★★★ Backspace is MOVED, not shared: leaving it on both would close two matrix positions at once
-- and the guest would see LEFT and CLEAR pressed together.
-- ★★ Interactive runs only -- the posting arm drives the matrix through natkeyboard and must see
-- the machine's stock bindings.
local function bind_backspace_to_clear()
    local moved, cleared = false, false
    for tag, port in pairs(m.ioport.ports) do
        if tag:match("row6") or tag:match("row3") then
            for _, f in pairs(port.fields) do
                local want = tag:match("row6") and f.mask == 0x02 and "KEYCODE_HOME OR KEYCODE_BACKSPACE"
                          or tag:match("row3") and f.mask == 0x20 and "KEYCODE_LEFT"
                if want then
                    local ok = pcall(function()
                        f:set_input_seq("standard", m.input:seq_from_tokens(want))
                    end)
                    if ok and f.mask == 0x02 then moved = true end
                    if ok and f.mask == 0x20 then cleared = true end
                end
            end
        end
    end
    -- ★★★★ SAY WHETHER IT TOOK. A rebind that silently failed would send the operator back to a
    -- key that still does nothing, and the log would read exactly as it does on success [§2W].
    if moved and cleared then
        print("★ Backspace rebound to CoCo3 CLEAR (AGI's backspace); arrows stay movement keys")
    else
        print(string.format("★★★ backspace rebind FAILED (clear=%s left=%s) -- press Home instead",
                            tostring(moved), tostring(cleared)))
    end
end

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

-- ★★★★★ THE HOST BLANKS; THE GUEST OWNS THE DISPLAY. An earlier version set the mode, the MMU and
-- VOFFSET here and none of it survived: HAL_sys_init reprograms all eight MMU slots to $38-$3F a
-- few instructions into the guest [sys.s step 4], and until the guest clears COCO in $FF90 the
-- GIME ignores $FF98/$FF99 entirely -- which is why the screen stayed in VDG text mode showing a
-- page of '@'. **input_probe.s now does all of it, after HAL_sys_init, where the ordering holds.**
-- ★★★ What is left here is the BLANK, and it is Jay's display ruling: black as soon as possible
-- AFTER the load, so the operator sees the boot and then a clean hand-over rather than garbage.
local function blank_display()
    for i = 0, 15 do prog:write_u8(0xFFB0 + i, 0x00) end
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★★★ WAIT FOR DECB'S "OK" PROMPT, NOT A FIXED DELAY. [Jay's standing rule, T-P0-060 and again
-- here.] This file poked at 0.4 emulated seconds -- **a guess at when the machine became ready
-- rather than a reading of whether it had** -- and took the machine over mid-boot. Jay, watching:
-- "i don't [see] your waiting for the basic 'ok' prompt and its crashing the system."
-- ★★★★ TWO INDEPENDENT SIGNALS, SUSTAINED THREE FRAMES, copied from p3b_run.lua rather than
-- re-derived: "OK" as screen codes $4F,$4B at the START OF A ROW of the 32x16 VDG screen at
-- $0400 (idiom 14f: uppercase is stored as-is), AND the CPU parked in DECB's prompt poll at
-- PC $A7D0-$A7E0.
-- ★★★ NOT a scan of all 512 screen bytes for any adjacent $4F,$4B: that matches uninitialised RAM
-- and passes at frame 28, before the banner is even on screen at ~60. **It fails EARLY, the
-- direction that hides the problem** [§2W], and Jay caught that version twice.
-- ★★ Bounded and reported: a machine that never prints OK is a broken launch and must say so
-- rather than hanging silently -- a wait that cannot fail is not a wait.
local OK_TIMEOUT = tonumber(os.getenv("IP_OK_FRAMES") or "1800")
-- ★ Hold the prompt so a person can SEE the machine was ready before it is taken over [Jay's
-- display ruling]. A wait that is only in the log proves it to the log.
local OK_HOLD = tonumber(os.getenv("IP_OK_HOLD") or "120")
local frame, ok_streak, okframe = 0, 0, nil

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

local booted, posted, waited = false, false, 0

_G._ip = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if not booted then
        if not decb_ready() then
            if frame > OK_TIMEOUT then
                print(string.format("★★★ no OK prompt on the $0400 text screen after %d frames "
                                    .. "-- the machine never finished booting. NOT poking.",
                                    OK_TIMEOUT))
                m:exit()
            end
            return
        end
        if okframe == nil then
            okframe = frame
            print(string.format("DECB is at its OK prompt (frame %d, PC=$%04X, 'OK' at a row "
                                .. "start, 3 frames) -- holding %d frames so it can be seen",
                                frame, cpu.state["PC"].value, OK_HOLD))
            return
        end
        if frame - okframe < OK_HOLD then return end
        booted = true
        print(string.format("taking the machine over at frame %d", frame))
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        poke(0x2000, blob)
        local font = slurp(FONT)
        if font and #font == 2048 then poke(IP_FONT_A, font) end
        if VOCAB ~= "" then
            local v = slurp(VOCAB)
            if v and #v <= 8192 then poke(IP_VOCAB_A, v) end
        end
        -- ★★★ IP_ITER explicitly zero: a direct-page byte has no default, and a leftover here
        -- sends the probe to its timing loop instead of its input line [see key_coverage.lua].
        prog:write_u8(0x0027, 0)                 -- IP_ITER
        -- ★★ IP_LOOP: reopen the line after each Enter when a person is watching. Off for the
        -- headless gate, which wants one line and a verdict.
        prog:write_u8(0x0029, WATCH and 1 or 0)
        -- ★★★★★ NOW, with DECB's boot finished and the guest about to run. See assert_display's
        -- note: at script load these writes are erased by the machine's own initialisation.
        blank_display()
        cpu.state["PC"].value = 0x2000
        prog:write_u8(IP_GO, 1)
        -- ★★★ SAY WHICH RUN THIS IS. "typing 16 characters" printed on a run that posts nothing is
        -- a diagnostic asserting something that did not happen, and this harness has already been
        -- fooled once by a log that could not tell a scripted line from a typed one [§2W.3].
        print(string.format("staged: program %d B; %s", #blob,
                            NOPOST and "posting NOTHING -- the keyboard is the operator's"
                                   or string.format("typing %d characters", #TEXT)))
        if REBIND_BS then bind_backspace_to_clear() end
        return
    end

    -- ★★★★★ KEEP RAISING GO UNTIL THE GUEST MOVES, and this is the whole of P6.23's blockage.
    -- input_probe.s does `clr IP_GO` in its own initialisation -- correctly, because $0020 is in
    -- the direct page and DECB was there a moment ago [parser_probe.s's recorded lesson]. The host
    -- set GO in the SAME frame it set the PC, so the guest erased it and spun at ip_wait forever.
    -- ★★★★ EVERY SYMPTOM FOLLOWED FROM THAT: NRAW=0, NKEY=0, and every byte of HAL_key_scan's
    -- state still at its assembler initialiser. **The decoder was never reached and key delivery
    -- was never at fault** -- P6.23 read `$FF02=$EF` as "the guest is strobing" when it was a value
    -- DECB left behind [L-97: a reading consistent with several causes is not a diagnosis].
    -- ★★★ text_cost.lua hit this exact race in P6.19 and its fix is copied here rather than
    -- re-derived.
    if prog:read_u8(IP_GO) == 0 and prog:read_u8(IP_DONE) == 0 and (_G._ip_nk or 0) == 0 then
        prog:write_u8(IP_GO, 1)
    end

    -- ★★★★★ A HOST-SIDE SCAN OF THE SAME MATRIX, ONCE, so guest and host are compared on the same
    -- frame rather than across two runs. keymatrix_check.lua proved delivery reaches $FF00; if the
    -- host sees a key here and the guest's NRAW stays 0, the guest is the variable [L-103].
    if posted and (_G._ip_hs or 0) < 4 then
        local cra = prog:read_u8(0xFF01)
        prog:write_u8(0xFF01, (cra & 0xFC) | 0x04)
        local crb = prog:read_u8(0xFF03)
        prog:write_u8(0xFF03, (crb & 0xFC) | 0x04)
        local seen = {}
        for col = 0, 7 do
            prog:write_u8(0xFF02, (~(1 << col)) & 0xFF)
            local r = (~prog:read_u8(0xFF00)) & 0x7F
            if r ~= 0 then seen[#seen + 1] = string.format("col%d=%02X", col, r) end
        end
        prog:write_u8(0xFF02, 0xFF)
        if #seen > 0 then
            _G._ip_hs = (_G._ip_hs or 0) + 1
            -- ★★★★★ AND THE GUEST'S OWN SCAN STATE, because IP_NRAW TURNED OUT NOT TO
            -- DISCRIMINATE: it is incremented after HAL_key_scan RETURNS A KEY, so zero is equally
            -- consistent with "the matrix was silent" and "the matrix spoke and the decode
            -- resolved 0". **The counter I built to separate two causes sat downstream of both**
            -- [§2W: an instrument must be able to fail; this one could not tell the cases apart].
            -- hal_kb_rows is the mask the guest last read, hal_kb_idx the position it resolved.
            print(string.format("  HOST sees %s | guest NRAW=%d NKEY=%d "
                                .. "rows=$%02X idx=$%02X mod=$%02X col=%d | CRA=$%02X CRB=$%02X",
                                table.concat(seen, " "), prog:read_u8(IP_NRAW),
                                prog:read_u8(IP_NKEY), u8("hal_kb_rows"), u8("hal_kb_idx"),
                                u8("hal_kb_mod"), u8("hal_kb_col"),
                                prog:read_u8(0xFF01), prog:read_u8(0xFF03)))
        end
    end

    -- ★★★★★ INTERACTIVE MODE: report each line, then release the guest to open another. Without
    -- this the probe parses one line and halts, which is a gate rather than something a person can
    -- type into [Jay, T-P0-081: "i thought i was going to be able to enter input"].
    if WATCH and prog:read_u8(IP_DONE) == 1 then
        local n = prog:read_u8(IP_EGON)
        local ids = {}
        for i = 0, n - 1 do
            ids[#ids + 1] = prog:read_u8(IP_EGOLOG + i * 2) * 256
                            + prog:read_u8(IP_EGOLOG + i * 2 + 1)
        end
        -- ★★★ NAME THE LAST KEY. A phantom empty line says "something submitted it" and the count
        -- says "one key did" -- neither says WHICH, and I have guessed wrong about that twice.
        -- ★★★★ NAME THE LAST KEY. An empty line says "something submitted it" and the count says
        -- "one key did" -- neither says WHICH, and that one byte is what finally separated a real
        -- second Enter from an invented one.
        print(string.format(
            "★ line %d: %d keys, last=$%02X -> decoded [%s] -> egon=%d  words = %s",
            (_G._ip_lines or 0) + 1, prog:read_u8(IP_NKEY),
            prog:read_u8(IP_LASTK), read_line(), n,
            n > 0 and table.concat(ids, ",") or "(none matched)"))
        _G._ip_lines = (_G._ip_lines or 0) + 1
        prog:write_u8(IP_DONE, 0)                -- release the guest to reopen the line
        return
    end

    if not posted then
        -- ★★ A few frames after GO, so the guest is in its poll loop before the first key lands.
        waited = waited + 1
        if waited < 12 then return end
        posted = true
        -- ★★★ IP_NOPOST=1 means "type it yourself" -- the probe is live and the operator owns the
        -- keyboard. Otherwise IP_TEXT is posted once and the line stays open for more.
        if NOPOST then
            print("★ the input line is LIVE and nothing was posted -- type, and press Enter")
            return
        end
        -- ★★★★ REPORT WHETHER THE POST WAS ACCEPTED. `empty` false immediately after a post means
        -- natkeyboard took the characters and is feeding them; still true means it took nothing,
        -- and that distinguishes "the keyboard is not delivering" from "the decoder is not
        -- decoding" without touching the guest.
        local before = m.natkeyboard.empty
        m.natkeyboard:post(TEXT .. "\r")
        print(string.format("natkeyboard: in_use=%s empty before=%s after=%s",
                            tostring(m.natkeyboard.in_use), tostring(before),
                            tostring(m.natkeyboard.empty)))
        return
    end

    -- ★★ Once a frame while keys are in flight, sample the COLUMN STROBE the guest is writing.
    -- $FF02 is an output register, so reading it from the host does not race the guest's own
    -- reads of $FF00 and shows whether the scan loop is running at all.
    if not m.natkeyboard.empty and (_G._ip_seen or 0) < 3 then
        _G._ip_seen = (_G._ip_seen or 0) + 1
        print(string.format("  scan check: $FF02=$%02X  NRAW=%d  keys pending",
                            prog:read_u8(0xFF02), prog:read_u8(IP_NRAW)))
    end

    if prog:read_u8(IP_DONE) == 1 then
        -- ★★ REPORT ONCE. With IP_WATCH the notifier keeps running so the operator can look at the
        -- screen, and the first version printed the result on every frame -- 3,019 lines for one
        -- entered line. Harmless to the run and useless to a reader.
        if _G._ip_said then return end
        _G._ip_said = true
        local n = prog:read_u8(IP_EGON)
        local ids = {}
        for i = 0, n - 1 do
            ids[#ids + 1] = prog:read_u8(IP_EGOLOG + i * 2) * 256
                            + prog:read_u8(IP_EGOLOG + i * 2 + 1)
        end
        print(string.format("★ line entered: %d key events, %d raw scans, last key $%02X, "
                            .. "decoded [%s]",
                            prog:read_u8(IP_NKEY), prog:read_u8(IP_NRAW),
                            prog:read_u8(IP_LASTK), read_line()))
        print(string.format("★ parser: egon=%d  word numbers = %s",
                            n, table.concat(ids, ",")))
        if not WATCH then m:exit() end
        return
    end

    -- ★★★★★ NO WATCHDOG WHEN A PERSON IS AT THE KEYS. An 8-second progress budget is right for a
    -- byte gate and wrong for an operator: thinking about what to type is not a stall, and this
    -- timer was closing sessions out from under Jay mid-line. The interactive run ends when the
    -- operator closes the window, which is the only signal that means "done" here.
    if WATCH and NOPOST then return end

    -- ★★★ A budget against PROGRESS, not against the run: a probe that is still decoding keys is
    -- not stalled [parser_gate.lua's own lesson]. NKEY advancing resets the clock.
    local nk = prog:read_u8(IP_NKEY)
    if _G._ip_nk ~= nk then _G._ip_nk, _G._ip_t = nk, m.time:as_double() end
    if not _G._ip_t then _G._ip_t = m.time:as_double() end
    if m.time:as_double() - _G._ip_t > 8 then
        print(string.format("★★★ no progress: DONE=%d NKEY=%d NRAW=%d LASTK=$%02X PC=$%04X",
                            prog:read_u8(IP_DONE), nk, prog:read_u8(IP_NRAW),
                            prog:read_u8(IP_LASTK), cpu.state["PC"].value))
        if sym["gs_curpos"] then
            print(string.format("     curpos=%d done=%d",
                                prog:read_u8(sym["gs_curpos"]), prog:read_u8(sym["gs_done"])))
        end
        -- ★★★★ NRAW is the discriminator: zero means the MATRIX never saw a key (a natkeyboard
        -- problem), non-zero with NKEY zero means the DECODER saw pressure and resolved nothing
        -- (a table problem). **Without it the two look identical from here.**
        m:exit()
    end
end)
