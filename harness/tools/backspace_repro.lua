-- harness/tools/backspace_repro.lua -- reproduce P6.25 §7.1 headlessly, and bisect it. [P6.26]
--
-- ★★★★★ THE LINE THAT DIVERGED IS THE ONE LINE NO INSTRUMENT COULD PRODUCE. natkeyboard posts
-- CHARACTERS and the CoCo3's CLEAR key -- which is AGI's backspace -- has no character mapping, so
-- the only way to press it was a person's hands. This drives it by IOPORT FIELD ASSERTION instead
-- [idiom 41f; key_coverage.lua is the precedent], which makes the failing line scriptable.
--
-- ★★★★★ FOUR ARMS, NOT TWO, BECAUSE THE OBSERVATION HAS **TWO** UNCONTROLLED VARIABLES. P6.25's
-- divergent line contained backspaces AND was a REOPENED line -- the second line of the session --
-- and every story told about it so far has silently assumed the first was the cause.
--
--     1  no backspace   (first line)
--     2  backspace      (reopened)
--     3  no backspace   (reopened)      <-- the arm that separates them
--     4  backspace      (reopened)
--
-- ★★★★ If 1 and 3 agree and 2 and 4 agree, BACKSPACE is the variable. If 1 stands alone and 2, 3
-- and 4 agree, **REOPENING is the variable and backspace is innocent** -- and that is a different
-- defect in a different place. [L-73: name every variable a toggle moves, not only the intended
-- one. This subsystem has produced three self-consistent stories that pointed at the wrong layer.]
--
-- ★★★ IT DUMPS BUFFERS, NOT VERDICTS. "the buffer is identical" was a READING taken through a
-- helper that stops at the NUL, and the reading is exactly what is in question, so every byte of
-- IP_INBUF is printed -- past the terminator, to the end of the field -- for every arm.
--
-- ★★ Environment: IP_PROG, IP_MAP, IP_FONT, IP_VOCAB.  Driven by input_run.ps1 -Repro.
-- ★ §2P: prints the operator's own scripted input and word NUMBERS. No game text.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG  = os.getenv("IP_PROG")  or "build/input_probe.bin"
local MAP   = os.getenv("IP_MAP")   or "build/input_probe.map"
local FONT  = os.getenv("IP_FONT")  or "build/text_font.bin"
local VOCAB = os.getenv("IP_VOCAB") or ""

local IP_GO, IP_DONE, IP_NKEY = 0x0020, 0x0021, 0x0022
local IP_EGON, IP_LASTK       = 0x0023, 0x0024
local IP_FONT_A, IP_VOCAB_A   = 0x3400, 0x6000
local IP_INBUF, IP_EGOLOG     = 0x4200, 0x4600
local IP_CLNBUF               = 0x5F00
local INBUF_LEN               = 48        -- ★ past the 42-byte field, deliberately

-- ── the matrix, from hal_globals.s's own table (row-major, 8 cols x 7 rows) ──────
-- row0 @ A B C D E F G   row1 H I J K L M N O   row2 P Q R S T U V W
-- row3 X Y Z UP DN LF RT SPACE   row4 0..7   row5 8 9 : ; , - . /
-- row6 ENTER CLEAR BREAK ALT - - - -
local K = {
    L = {1,4}, O = {1,7}, K = {1,3}, A = {0,1}, T = {2,4}, R = {2,2}, C = {0,3},
    SP = {3,7}, ENTER = {6,0}, CLEAR = {6,1},
}
local function word(s)
    local out = {}
    for i = 1, #s do
        local ch = s:sub(i, i)
        out[#out + 1] = (ch == " ") and K.SP or K[ch:upper()]
    end
    return out
end
local function concat(...)
    local out = {}
    for _, t in ipairs({...}) do for _, v in ipairs(t) do out[#out + 1] = v end end
    return out
end

-- ★★★ "look at rockk" then CLEAR is the minimal backspace line whose FINAL buffer is byte-for-byte
-- the control's. Any richer edit would confound "backspace happened" with "a different string".
local LINE_PLAIN = concat(word("look at rock"), { K.ENTER })
local LINE_BS    = concat(word("look at rockk"), { K.CLEAR, K.ENTER })

-- ★★★★★ ARM 5 IS A FAULT INJECTION AND IT IS NOT OPTIONAL [§2W.1]. Arms 1-4 can only ever agree
-- or disagree with each other; if the whole chain were wedged -- vocabulary unstaged, egolog stale,
-- the adjudicator reading one arm's numbers four times -- they would agree, and agreement is the
-- result this run is most likely to report. **A comparison that has never been seen to say DIFFER
-- is not evidence that things are the same.**
-- ★★★★ So arm 5 types `look at rockk` and presses ENTER WITHOUT the CLEAR: the same keys as arm 2
-- minus the backspace, a line whose final buffer genuinely differs by one byte and whose last word
-- is not in KQ1's vocabulary. **It MUST parse differently from arm 1.** If it does not, this
-- instrument cannot see a divergence and nothing else it printed means anything.
local LINE_FAULT = concat(word("look at rockk"), { K.ENTER })

local ARMS = {
    { name = "1 plain  (first line)", keys = LINE_PLAIN, bs = false },
    { name = "2 backsp (reopened)  ", keys = LINE_BS,    bs = true  },
    { name = "3 plain  (reopened)  ", keys = LINE_PLAIN, bs = false },
    { name = "4 backsp (reopened)  ", keys = LINE_BS,    bs = true  },
    { name = "5 FAULT  (rockk, none)", keys = LINE_FAULT, bs = false, fault = true },
}

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
local function u8(n) return sym[n] and prog:read_u8(sym[n]) or -1 end

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end

-- ★★★★ THE DUMP IS THE EVIDENCE, so it shows bytes and glyphs side by side and marks the NUL.
-- A dump that renders unprintables as dots hides exactly the bytes this is looking for.
local function dump(addr, len)
    local bytes, glyphs = {}, {}
    for i = 0, len - 1 do
        local c = prog:read_u8(addr + i)
        bytes[#bytes + 1] = string.format("%02X", c)
        glyphs[#glyphs + 1] = (c >= 0x20 and c < 0x7F) and string.char(c)
                              or (c == 0 and "." or "?")
    end
    return table.concat(bytes, " "), table.concat(glyphs)
end

local fields = {}
local results = {}
local phase, arm, ki, expect_nk, held = "boot", 1, 1, 0, 0

local decb_ready = dofile("harness/tools/decb_ready.lua").new{ hold = 0 }

_G._bs = emu.add_machine_frame_notifier(function()
    if phase == "boot" then
        local st = decb_ready(m, cpu, prog)
        if st == "timeout" then m:exit(); return end
        if st ~= "go" then return end

        for tag, port in pairs(m.ioport.ports) do
            local r = tag:match("row(%d)")
            if r then
                for _, field in pairs(port.fields) do
                    fields[r .. "," .. field.mask] = field
                end
            end
        end

        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        poke(0x2000, blob)
        local font = slurp(FONT)
        if font and #font == 2048 then poke(IP_FONT_A, font) end
        if VOCAB ~= "" then
            local v = slurp(VOCAB)
            if v and #v <= 8192 then
                poke(IP_VOCAB_A, v)
                print(string.format("vocabulary staged: %d bytes from %s", #v, VOCAB))
            else
                print("★★★ vocabulary missing or too large: " .. VOCAB); m:exit(); return
            end
        else
            print("★★★ no IP_VOCAB set -- refusing to run [L-111]"); m:exit(); return
        end
        -- ★★★ A direct-page byte has no default: DECB was using this page moments ago.
        prog:write_u8(0x0027, 0)                 -- IP_ITER
        prog:write_u8(0x0029, 1)                 -- IP_LOOP: reopen after each Enter
        cpu.state["PC"].value = 0x2000
        prog:write_u8(IP_GO, 1)
        phase = "arm"
        return
    end

    -- ★★★ Keep raising GO: the guest clears it in its own init, and setting it once in the same
    -- frame as the PC left P6.23's probe spinning at ip_wait for a whole task.
    if phase == "arm" then
        if prog:read_u8(IP_GO) == 0 then prog:write_u8(IP_GO, 1); return end
        expect_nk = prog:read_u8(IP_NKEY)
        phase = "press"
        return
    end

    if phase == "press" then
        local rc = ARMS[arm].keys[ki]
        local f = fields[rc[1] .. "," .. (1 << rc[2])]
        if not f then
            print(string.format("★★★ no field at row%d bit %d", rc[1], rc[2]))
            m:exit(); return
        end
        f:set_value(1)
        held = 0
        phase = "watch"
        return
    end

    -- ★★★★ PROGRESS IS IP_NKEY, NOT IP_LASTK. Consecutive identical keys ("oo" in "look") leave
    -- LASTK unchanged, so a LASTK watch would hang on the second one and report a dead decoder.
    if phase == "watch" then
        held = held + 1
        if prog:read_u8(IP_NKEY) ~= expect_nk then
            local rc = ARMS[arm].keys[ki]
            fields[rc[1] .. "," .. (1 << rc[2])]:set_value(0)
            expect_nk = prog:read_u8(IP_NKEY)
            phase = "gap"
            held = 0
            return
        end
        if held > 60 then
            print(string.format("★★★ arm %d key %d never registered", arm, ki))
            m:exit()
        end
        return
    end

    -- ★★ A released-and-quiet interval, so the guest's debounce latch clears before the next
    -- press. Without it a repeated key is not a new event and the line comes out short.
    if phase == "gap" then
        held = held + 1
        if held < 3 then return end
        ki = ki + 1
        if ki > #ARMS[arm].keys then phase = "collect" else phase = "press" end
        return
    end

    if phase == "collect" then
        if prog:read_u8(IP_DONE) ~= 1 then
            held = held + 1
            if held > 240 then print(string.format("★★★ arm %d never submitted", arm)); m:exit() end
            return
        end
        local n = prog:read_u8(IP_EGON)
        local ids = {}
        for i = 0, n - 1 do
            ids[#ids + 1] = prog:read_u8(IP_EGOLOG + i * 2) * 256
                            + prog:read_u8(IP_EGOLOG + i * 2 + 1)
        end
        local ib, ig = dump(IP_INBUF, INBUF_LEN)
        local cb, cg = dump(IP_CLNBUF, INBUF_LEN)
        results[#results + 1] = {
            name = ARMS[arm].name, nkey = prog:read_u8(IP_NKEY),
            egon = n, ids = ids, inhex = ib, inglyph = ig, clhex = cb, clglyph = cg,
            curpos = u8("gs_curpos"), entered = u8("gs_entered"),
        }
        prog:write_u8(IP_DONE, 0)                -- release the guest to reopen
        arm = arm + 1
        ki = 1
        if arm > #ARMS then phase = "done" else phase = "arm" end
        held = 0
        return
    end

    if phase == "done" then
        print("")
        print("=== P6.26: four arms, CLEAR driven by field assertion ===")
        for _, r in ipairs(results) do
            print(string.format("%s  keys=%2d curpos=%d entered=%d  egon=%d  words=%s",
                                r.name, r.nkey, r.curpos, r.entered, r.egon,
                                #r.ids > 0 and table.concat(r.ids, ",") or "(none)"))
        end
        print("")
        print("=== IP_INBUF, every byte to $4200+" .. INBUF_LEN .. " ===")
        for _, r in ipairs(results) do
            print(string.format("%s |%s|", r.name, r.inglyph))
            print(string.format("                      %s", r.inhex))
        end
        print("")
        print("=== par_clean output at IP_CLNBUF ===")
        for _, r in ipairs(results) do
            print(string.format("%s |%s|", r.name, r.clglyph))
            print(string.format("                      %s", r.clhex))
        end
        print("")
        -- ★★★★★ THE ADJUDICATION IS A DIFF BETWEEN ARMS, and it names WHICH variable moved.
        -- An adjudicator that only said PASS/FAIL would leave the confound in place.
        local a, b, c, d, e = results[1], results[2], results[3], results[4], results[5]
        local function same(x, y) return x.egon == y.egon
                                      and table.concat(x.ids, ",") == table.concat(y.ids, ",") end

        -- ★★★★★ THE FAULT ARM IS ADJUDICATED FIRST, AND A BLIND INSTRUMENT REPORTS NOTHING ELSE.
        -- Printing four "same" lines and then discovering the comparison could not distinguish
        -- anything is the shape of AD-122 and AD-131; the order here makes that impossible.
        print("=== §2W: can this comparison say DIFFER? ===")
        local can_fail = not same(a, e)
        print(string.format("  fault arm 5 vs arm 1        : %s  (arm 5 egon=%d words=%s)",
                            can_fail and "DIFFER -- the instrument can go red"
                                     or "same -- ★★★ BLIND",
                            e.egon, #e.ids > 0 and table.concat(e.ids, ",") or "(none)"))
        print(string.format("  inbuf  arm 5 vs arm 1       : %s",
                            a.inhex ~= e.inhex and "DIFFER" or "same -- ★★★ BLIND"))
        if not can_fail then
            print("  ★★★ THIS RUN PROVES NOTHING. A line that must parse differently did not, so")
            print("      every 'same' below is unfalsified, not confirmed. Fix the harness first.")
            m:exit(); return
        end
        print("")
        print("=== which variable moved ===")
        print(string.format("  inbuf 1 vs 3 (both plain)   : %s",
                            a.inhex == c.inhex and "IDENTICAL" or "DIFFER"))
        print(string.format("  inbuf 1 vs 2 (plain vs bs)  : %s",
                            a.inhex == b.inhex and "IDENTICAL" or "DIFFER"))
        print(string.format("  parse 1 vs 3 (both plain)   : %s",
                            same(a, c) and "same" or "DIFFER"))
        print(string.format("  parse 2 vs 4 (both bs)      : %s",
                            same(b, d) and "same" or "DIFFER"))
        print(string.format("  parse 1 vs 2 (plain vs bs)  : %s",
                            same(a, b) and "same" or "DIFFER"))
        if same(a, c) and not same(a, b) and same(b, d) then
            print("  ★ BACKSPACE is the variable: plain arms agree, backspace arms agree, they differ")
        elseif not same(a, c) and same(b, c) then
            print("  ★★★ REOPENING is the variable, NOT backspace: arm 3 is plain and follows arm 2")
        elseif same(a, b) and same(a, c) and same(a, d) then
            print("  ★★★ NO DIVERGENCE REPRODUCED -- all four arms parse alike [trigger 1: stop]")
        else
            print("  ★★★ neither pattern -- report the table, do not summarise it")
        end
        m:exit()
    end
end)
