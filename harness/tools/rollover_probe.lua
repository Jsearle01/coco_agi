-- harness/tools/rollover_probe.lua -- rollover, and the parse boundary. [P6.27]
--
-- ★★★★★ THE ONE NAMED DIFFERENCE LEFT. P6.26 eliminated backspace and line-reopening as causes of
-- the P6.25 divergence, and left exactly one uncontrolled difference between the line a person typed
-- and the line an instrument typed: **a human holds the next key before releasing the last, and
-- HAL_key_scan resolves exactly one key.**
--
-- ★★★★★ AND IT HAS A SIGNATURE TO HIT, NOT MERELY AN EFFECT TO LOOK FOR. P6.26 arm 5 measured that
-- an unknown word yields word 0 and ignore words drop: `look at rockk` -> egon=2, words 2,0. The
-- divergent reading was **egon=1, words=0** -- ONE group, unknown -- which no arm produces from
-- `LOOK AT ROCK`. So the hypothesis is falsifiable: **par_parse saw a buffer the host's read does
-- not show.** IP_SNAP is the guest's own copy of IP_INBUF taken immediately before `jsr par_parse`
-- [input_probe.s], and comparing it against the host's later read is the whole test. Every previous
-- buffer reading in this project was taken by the host, frames later, on the far side of the thing
-- in doubt.
--
-- ★★★★ THREE VARIABLES, NAMED, AND EACH ARM SAYS WHICH IT MOVES [AC-5, L-114]:
--     V1 rollover       -- is a second key down while the first still is?
--     V2 timing offset  -- how many frames separate the two edges?
--     V3 enter boundary -- does a character key overlap the ENTER that submits the line?
-- ★★★ P6.26 was scoped around one variable when the observation carried two [X-77]. The table in
-- the output prints `moves` for every arm so that shape cannot repeat silently here.
--
-- ★★ Environment: IP_PROG, IP_MAP, IP_FONT, IP_VOCAB.  Driven by input_run.ps1 -Rollover.
-- ★ §2P: the operator's own scripted input and word NUMBERS. No game text.

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
local IP_SNAP                 = 0x4700
local INBUF_LEN               = 48

-- row0 @ A B C D E F G   row1 H I J K L M N O   row2 P Q R S T U V W
-- row3 X Y Z UP DN LF RT SPACE   row4 0..7   row5 8 9 : ; , - . /
-- row6 ENTER CLEAR BREAK ALT - - - -
local K = {
    A={0,1}, B={0,2}, C={0,3}, D={0,4}, E={0,5}, F={0,6}, G={0,7},
    H={1,0}, I={1,1}, J={1,2}, K={1,3}, L={1,4}, M={1,5}, N={1,6}, O={1,7},
    P={2,0}, Q={2,1}, R={2,2}, S={2,3}, T={2,4}, U={2,5}, V={2,6}, W={2,7},
    SP={3,7}, ENTER={6,0}, CLEAR={6,1},
}

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ONE step list, ONE state machine. An earlier draft ran the line arms and the pair tests through
-- two parallel machines with duplicated wait/probe phases; merging them removes the class of bug
-- where the two drift apart.
local function press(k)      return { op="press",   k=k } end
-- ★★★★★ ONE STEP RUNS PER FRAME, so two `press` steps are two FRAMES apart and the arm named "same
-- frame" was not. B2's buffer read `LOOK AT ROCKK` because K was alone for one frame, registered as
-- an ordinary keystroke, and only then did ENTER arrive -- a sequential case wearing a simultaneous
-- label. This closes both fields in a single frame, which is the edge the arm was for.
local function pressn(ks)    return { op="pressn",  ks=ks } end
local function release(k)    return { op="release", k=k } end
local function wait(n)       return { op="wait",    n=n } end
local function clearlast()   return { op="clearlast" } end
local function probe(l, n)   return { op="probe", lbl=l, n=n } end
local function submit(l)     return { op="submit", lbl=l } end
local function pokefault()   return { op="pokefault" } end
-- ★★★★★ WAIT UNTIL THE GUEST COUNTED IT, DO NOT WAIT A FIXED NUMBER OF FRAMES. The first draft
-- held each key for 4 frames and moved on; the very first line came out as `OOK AT ROCK` because
-- the opening `L` landed before the guest had finished opening its input line, and a fixed hold
-- has no way to notice. **backspace_repro.lua got this right and this file regressed it** -- it
-- watches IP_NKEY, which is the only signal that says the keystroke became an event.
local function waitkey(n)    return { op="waitkey", n=n or 90 } end
-- ★★★ Release every field this file knows about. Arms leak into each other otherwise: B3 holds K
-- across its ENTER, and once ENTER lifts the still-closed K is a NEW event that lands in the NEXT
-- arm's line -- which is where S1's stray leading `K` came from.
local function allup()       return { op="allup" } end

local function keyof(ch)
    if ch == " " then return K.SP end
    return K[ch:upper()]
end

-- ★★★ ONE KEY AT A TIME WITH A QUIET GAP -- P6.26's shape exactly, so an arm using it for the body
-- of the line differs from P6.26 only where it is meant to.
local function typed(str)
    local out = {}
    for i = 1, #str do
        local k = keyof(str:sub(i, i))
        out[#out+1] = press(k);   out[#out+1] = waitkey()
        out[#out+1] = release(k); out[#out+1] = wait(3)
    end
    return out
end

-- ★★★★ ROLLOVER: the next key goes DOWN before the last comes UP, which is what a person does and
-- what no instrument in this project has done before. At any instant up to two keys are closed.
--
-- ★★★★★ A DOUBLED LETTER MUST BREAK THE OVERLAP, and the first draft did not. `set_value(1)` on an
-- already-closed field is a no-op, so pressing O while O is still down is not a second keystroke --
-- `look` came out `lok` and the missing character read as rollover losing input when it was the
-- driver never sending it. **A repeated key is exactly where a rollover typist's fingers separate**,
-- so releasing first is also the faithful behaviour, not merely the workable one.
-- ★★★★★ waitkey GOES **AFTER** THE PREVIOUS KEY LIFTS, AND PUTTING IT BEFORE WAS A MEASUREMENT
-- ERROR THAT LOOKED LIKE A PORT DEFECT. While two keys are closed HAL_key_scan reports ONE, chosen
-- by scan order, so a newly-pressed key whose column sorts LATER than the held key's is suppressed
-- until the held key lifts. Waiting for it to register while the previous key is still down
-- therefore always times out: the first version reported **6 of 12 keystrokes "dropped"** on this
-- arm while the line came out perfectly correct -- a contradiction that is the tell.
-- ★★★★ The keystroke is not lost, it is DEFERRED, which is the same fact AC-1's `R+L` row shows
-- from the other side: L appears the instant R is released. Overlap is preserved -- both keys are
-- genuinely closed for a frame -- and only the point at which the driver waits has moved.
local function typed_rollover(str)
    local out, prev = {}, nil
    for i = 1, #str do
        local k = keyof(str:sub(i, i))
        -- ★★★ A doubled letter must break the overlap: set_value(1) on an already-closed field is
        -- a no-op, so `look` came out `lok` and read as rollover losing input when it was the
        -- driver never sending it. It is also where a real typist's fingers separate.
        if prev and prev == k then
            out[#out+1] = release(prev); out[#out+1] = wait(3)
            prev = nil
        end
        out[#out+1] = press(k)
        out[#out+1] = wait(2)                       -- the overlap: both keys closed
        if prev then out[#out+1] = release(prev) end
        out[#out+1] = waitkey()                     -- now it can register
        out[#out+1] = wait(1)
        prev = k
    end
    if prev then out[#out+1] = release(prev); out[#out+1] = wait(3) end
    return out
end

local function cat(...)
    local out = {}
    for _, t in ipairs({...}) do for _, v in ipairs(t) do out[#out+1] = v end end
    return out
end
local function plain_submit(lbl)
    return { press(K.ENTER), wait(2), submit(lbl), allup(), wait(4) }
end
-- ★★ Every arm opens by lifting everything and letting the guest see a quiet scan, so no arm can
-- inherit a closed field from the one before it.
local function fresh() return { allup(), wait(4) } end

local LINE = "look at rock"

local ARMS = {}

-- ★★★★★ THE FAULT ARM MOVES NONE OF THE THREE VARIABLES. It types a plain line and then, after the
-- guest has snapshotted and parsed, has the HOST poke a byte into IP_INBUF before reading it. The
-- snapshot and the after-read MUST then differ. If they do not, the comparison every other arm
-- rests on cannot see a buffer that was changed on purpose, and nothing this run prints means
-- anything [L-113, §2W.1]. Its verdict is printed FIRST, ahead of the arms it validates.
ARMS[#ARMS+1] = { name = "F  FAULT  host pokes buffer post-parse", kind = "fault",
                  moves = "nothing -- it perturbs the COMPARISON, not the guest",
                  steps = cat(fresh(), typed(LINE), { press(K.ENTER), wait(2), pokefault(),
                                                      submit("F"), allup(), wait(4) }) }

ARMS[#ARMS+1] = { name = "B1 ENTER alone (control)", kind = "line",
                  moves = "V3 = no overlap; V1 = none",
                  steps = cat(fresh(), typed(LINE), plain_submit("B1")) }

-- ★★★★ B2/B3 END WITH allup(), NOT WITH TWO SEPARATE RELEASES, AND THAT IS A CORRECTION. B3 first
-- released ENTER and then, two frames later, K -- so K was briefly the only key down, became a NEW
-- event, and was typed into the line the NEXT arm had just opened. S1's buffer read `KLOK AT ROCK`
-- and the stray `K` looked like rollover corrupting input. **Both fields must lift on the same
-- frame** or the tail of one arm is the head of the next.
ARMS[#ARMS+1] = { name = "B2 K one frame before ENTER", kind = "line",
                  moves = "V3 = character lands 1 frame before ENTER; V2 = 1 frame",
                  steps = cat(fresh(), typed(LINE),
                              { press(K.K), press(K.ENTER), wait(2), submit("B2"),
                                allup(), wait(4) }) }

ARMS[#ARMS+1] = { name = "B4 K and ENTER closed in ONE frame", kind = "line",
                  moves = "V3 = character and ENTER close simultaneously; V2 = 0 exactly",
                  steps = cat(fresh(), typed(LINE),
                              { pressn({K.K, K.ENTER}), wait(2), submit("B4"),
                                allup(), wait(4) }) }

ARMS[#ARMS+1] = { name = "B3 K held right across ENTER", kind = "line",
                  moves = "V3 = character held through the whole submit; V2 = 3 frames",
                  steps = cat(fresh(), typed(LINE),
                              { press(K.K), wait(3), press(K.ENTER), wait(2), submit("B3"),
                                allup(), wait(4) }) }

ARMS[#ARMS+1] = { name = "S1 rollover across the whole line", kind = "line",
                  moves = "V1 on every keystroke; V3 fixed (no ENTER overlap)",
                  steps = cat(fresh(), typed_rollover(LINE), plain_submit("S1")) }

-- ── AC-1: two fields at once. V3 held fixed (no ENTER) except the last, which is last for the
-- reason key_coverage.lua records: ENTER ends the line, so anything after it tests a stopped probe.
local PAIRS = {
    { "same row  L+K", K.L, K.K,     0 },
    { "same row  O+N", K.O, K.N,     0 },
    { "same col  L+D", K.L, K.D,     0 },
    { "diff both L+R", K.L, K.R,     0 },
    { "diff both R+L", K.R, K.L,     0 },
    { "stagger   L>K", K.L, K.K,     3 },
    { "with CLEAR K+C", K.K, K.CLEAR, 0 },
    { "with ENTER K+E", K.K, K.ENTER, 0 },
}
for _, p in ipairs(PAIRS) do
    local s = { allup(), wait(3), clearlast(), press(p[2]) }
    if p[4] > 0 then s[#s+1] = wait(p[4]) end
    s[#s+1] = press(p[3])
    s[#s+1] = probe(p[1] .. " (both down)", 10)
    s[#s+1] = release(p[2])
    -- ★★ A second window AFTER the first key lifts: "which key wins while both are down" and "does
    -- the other one arrive when the first lets go" are different questions, and only the pair of
    -- readings distinguishes a priority rule from a suppression.
    s[#s+1] = probe(p[1] .. " (A released)", 8)
    s[#s+1] = release(p[3])
    s[#s+1] = wait(5)
    if p[3] == K.ENTER then
        s[#s+1] = submit("P-ENTER")
        s[#s+1] = wait(4)
    end
    ARMS[#ARMS+1] = { name = "P  " .. p[1], kind = "pair",
                      moves = string.format("V1 = 2 keys; V2 = %d frames", p[4]), steps = s }
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
local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end
local function pokeb(addr, data)
    for i = 1, #data do prog:write_u8(addr + i - 1, data:byte(i)) end
end
local function dump(addr, len)
    local b, g = {}, {}
    for i = 0, len - 1 do
        local c = prog:read_u8(addr + i)
        b[#b+1] = string.format("%02X", c)
        g[#g+1] = (c >= 0x20 and c < 0x7F) and string.char(c) or (c == 0 and "." or "?")
    end
    return table.concat(b, " "), table.concat(g)
end
local function readline_at(addr)
    local s = {}
    for i = 0, 41 do
        local c = prog:read_u8(addr + i)
        if c == 0 then break end
        s[#s+1] = (c >= 0x20 and c < 0x7F) and string.char(c) or string.format("<%02X>", c)
    end
    return table.concat(s)
end

local fields = {}
local function field(k) return fields[k[1] .. "," .. (1 << k[2])] end

local lines, pairres, dropped = {}, {}, {}
local arm, si, held, waitn = 1, 1, 0, 0
local phase = "boot"
local pseen, plbl, pnk0, slbl, nkbase

local decb_ready = dofile("harness/tools/decb_ready.lua").new{ hold = 0 }

_G._ro = emu.add_machine_frame_notifier(function()
    if phase == "boot" then
        local st = decb_ready(m, cpu, prog)
        if st == "timeout" then m:exit(); return end
        if st ~= "go" then return end
        for tag, port in pairs(m.ioport.ports) do
            local r = tag:match("row(%d)")
            if r then for _, f in pairs(port.fields) do fields[r .. "," .. f.mask] = f end end
        end
        local blob = slurp(PROG)
        if not blob then print("★★★ no program at " .. PROG); m:exit(); return end
        pokeb(0x2000, blob)
        local font = slurp(FONT)
        if font and #font == 2048 then pokeb(IP_FONT_A, font) end
        if VOCAB == "" then print("★★★ no IP_VOCAB set -- refusing to run [L-111]"); m:exit(); return end
        local v = slurp(VOCAB)
        if not v or #v > 8192 then print("★★★ vocabulary bad: " .. VOCAB); m:exit(); return end
        pokeb(IP_VOCAB_A, v)
        print(string.format("vocabulary staged: %d bytes from %s", #v, VOCAB))
        -- ★★★ REFUSE A STALE PROBE. IP_SNAP is the whole instrument; a binary built before it
        -- exists would dump 48 bytes of whatever $4700 happens to hold and compare them happily.
        if not sym["IP_SNAP"] then
            print("★★★ no IP_SNAP in " .. MAP .. " -- probe is stale, rebuild it"); m:exit(); return
        end
        print(string.format("IP_SNAP at $%04X, probe %d B", sym["IP_SNAP"], #blob))
        prog:write_u8(0x0027, 0)      -- IP_ITER: a direct-page byte has no default
        prog:write_u8(0x0029, 1)      -- IP_LOOP
        cpu.state["PC"].value = 0x2000
        prog:write_u8(IP_GO, 1)
        phase = "arm"
        return
    end

    -- ★★★ Keep raising GO: the guest clears it in its own init, and setting it once in the same
    -- frame as the PC left P6.23's probe spinning at ip_wait for a whole task.
    if phase == "arm" then
        if prog:read_u8(IP_GO) == 0 then prog:write_u8(IP_GO, 1); return end
        phase = "step"
        return
    end

    if phase == "wait" then
        waitn = waitn - 1
        if waitn <= 0 then phase = "step" end
        return
    end

    -- ★★★★ The keystroke is not delivered when the field closes; it is delivered when the guest
    -- COUNTS it. A timeout here is reported rather than swallowed -- a dropped key that passes
    -- silently is how the first run produced `OOK AT ROCK` and looked like a port defect.
    if phase == "waitkey" then
        held = held + 1
        if prog:read_u8(IP_NKEY) ~= pnk0 then phase = "step"; return end
        if held >= waitn then
            dropped[#dropped+1] = string.format("%s step %d", ARMS[arm].name, si - 1)
            phase = "step"
        end
        return
    end

    -- ★★★★ Record EVERY distinct code resolved during the window, and how many key EVENTS were
    -- counted. "which key wins" and "how many keys did it see" are different questions and one
    -- reading answers neither alone.
    if phase == "probe" then
        held = held + 1
        local k = prog:read_u8(IP_LASTK)
        if k ~= 0 and pseen[#pseen] ~= k then pseen[#pseen+1] = k end
        if held >= waitn then
            pairres[#pairres+1] = { name = plbl, seen = pseen,
                                    nk = prog:read_u8(IP_NKEY) - pnk0 }
            phase = "step"
        end
        return
    end

    if phase == "submit" then
        if prog:read_u8(IP_DONE) ~= 1 then
            held = held + 1
            if held > 400 then print("★★★ " .. tostring(slbl) .. " never submitted"); m:exit() end
            return
        end
        local sh, sg = dump(IP_SNAP, INBUF_LEN)
        local ah, ag = dump(IP_INBUF, INBUF_LEN)
        local n = prog:read_u8(IP_EGON)
        local ids = {}
        for i = 0, n - 1 do
            ids[#ids+1] = prog:read_u8(IP_EGOLOG + i*2) * 256 + prog:read_u8(IP_EGOLOG + i*2 + 1)
        end
        lines[#lines+1] = { name = ARMS[arm].name, moves = ARMS[arm].moves, kind = ARMS[arm].kind,
                            lbl = slbl, snaphex = sh, snapg = sg, afterhex = ah, afterg = ag,
                            readback = readline_at(IP_INBUF), snapback = readline_at(IP_SNAP),
                            egon = n, ids = ids, nkey = prog:read_u8(IP_NKEY) }
        prog:write_u8(IP_DONE, 0)
        phase = "step"
        return
    end

    if phase == "step" then
        local a = ARMS[arm]
        if not a then phase = "done"; return end
        local st = a.steps[si]
        if not st then
            arm = arm + 1; si = 1
            return
        end
        si = si + 1
        if st.op == "press" then
            local f = field(st.k)
            if not f then print("★★★ no ioport field for a key in " .. a.name); m:exit(); return end
            -- ★★★★★ THE BASELINE IS TAKEN AT THE PRESS, NOT AT THE waitkey. A key whose column
            -- sorts before the held key's registers IMMEDIATELY, during the overlap -- so by the
            -- time a later waitkey step sampled IP_NKEY the event was already counted, and it then
            -- waited for a SECOND increment that was never coming. That timed out on 6 of 12
            -- keystrokes while the line came out perfectly correct: **the driver was reporting
            -- drops for the keys that worked fastest.**
            nkbase = prog:read_u8(IP_NKEY)
            f:set_value(1)
        elseif st.op == "pressn" then
            nkbase = prog:read_u8(IP_NKEY)
            for _, k in ipairs(st.ks) do
                local f = field(k)
                if not f then print("★★★ no ioport field in " .. a.name); m:exit(); return end
                f:set_value(1)
            end
        elseif st.op == "release" then
            local f = field(st.k); if f then f:set_value(0) end
        elseif st.op == "wait" then
            waitn = st.n; phase = "wait"
        elseif st.op == "clearlast" then
            prog:write_u8(IP_LASTK, 0)
        elseif st.op == "waitkey" then
            pnk0 = nkbase          -- ★ set at the press; see the note there
            waitn, held = st.n, 0
            phase = "waitkey"
        elseif st.op == "allup" then
            for _, f in pairs(fields) do f:set_value(0) end
        elseif st.op == "probe" then
            pseen, plbl, pnk0 = {}, st.lbl, prog:read_u8(IP_NKEY)
            waitn, held = st.n, 0
            phase = "probe"
        elseif st.op == "pokefault" then
            -- ★★ The ONLY host write to IP_INBUF in this file, and it happens after the guest has
            -- already taken its snapshot -- so the two must disagree.
            prog:write_u8(IP_INBUF + 2, 0x5A)
        elseif st.op == "submit" then
            slbl = st.lbl; held = 0; phase = "submit"
        end
        return
    end

    if phase == "done" then
        local function codes(t)
            if #t == 0 then return "(none)" end
            local o = {}
            for _, c in ipairs(t) do
                o[#o+1] = string.format("$%02X%s", c,
                    (c >= 0x20 and c < 0x7F) and "'" .. string.char(c) .. "'" or "")
            end
            return table.concat(o, " ")
        end

        local F
        for _, l in ipairs(lines) do if l.kind == "fault" then F = l end end

        print("")
        print("=== §2W: can the snapshot-vs-after comparison say DIFFER? [adjudicated first] ===")
        local can_fail = F and (F.snaphex ~= F.afterhex)
        print(string.format("  FAULT arm -- host poked $5A into IP_INBUF+2 after the parse: %s",
                            can_fail and "DIFFER -- the comparison can go red"
                                     or "same -- ★★★ BLIND"))
        if not can_fail then
            print("  ★★★ THIS RUN PROVES NOTHING. The one comparison every other arm rests on could")
            print("      not see a buffer that was changed on purpose. Fix the harness first.")
            m:exit(); return
        end

        -- ★★★★ DROPPED KEYS ARE REPORTED, NOT SWALLOWED. The first run's opening `L` never became
        -- an event and the line read `OOK AT ROCK`; with nothing announcing the drop it read as the
        -- port losing a character. **A driver that can silently fail to type is not a control.**
        print("")
        if #dropped > 0 then
            print(string.format("★★★ %d keystroke(s) never became an event -- the DRIVER dropped them:",
                                #dropped))
            for _, d in ipairs(dropped) do print("      " .. d) end
            print("    ★★ Every line below is suspect; fix the driver before reading them.")
        else
            print("★ driver: every scripted keystroke became a counted event (none dropped)")
        end

        print("")
        print("=== AC-1: two fields asserted at once -- what HAL_key_scan resolved ===")
        print("  window                          events  codes resolved")
        for _, r in ipairs(pairres) do
            print(string.format("  %-30s %4d    %s", r.name, r.nk, codes(r.seen)))
        end

        print("")
        print("=== AC-2: IP_SNAP (guest, at `jsr par_parse`) vs IP_INBUF (host, after) ===")
        local anydiff = false
        for _, l in ipairs(lines) do
            print(string.format("%s   [%s]", l.name, l.moves))
            print(string.format("   snap  |%s|", l.snapg))
            print(string.format("         %s", l.snaphex))
            print(string.format("   after |%s|", l.afterg))
            print(string.format("         %s", l.afterhex))
            local d = (l.snaphex ~= l.afterhex)
            if d and l.kind ~= "fault" then anydiff = true end
            print("   " .. (d and "★★★ SNAPSHOT DIFFERS FROM AFTER-READ"
                              or "★ snapshot == after-read"))
        end

        print("")
        print("=== AC-3: the signature -- egon=1, words=0 from a readback of LOOK AT ROCK ===")
        local sigfound = false
        for _, l in ipairs(lines) do
            local sig = (l.egon == 1 and #l.ids == 1 and l.ids[1] == 0
                         and l.readback == "LOOK AT ROCK")
            if sig then sigfound = true end
            print(string.format("  %-40s keys=%2d readback=[%s] egon=%d words=%s %s",
                                l.name, l.nkey, l.readback, l.egon,
                                #l.ids > 0 and table.concat(l.ids, ",") or "(none)",
                                sig and "★★★ SIGNATURE" or ""))
        end
        print("")
        if sigfound then
            print("  ★★★ SIGNATURE PRODUCED [trigger 2: stop]")
        elseif anydiff then
            print("  ★★★ NO SIGNATURE, BUT A NON-FAULT ARM'S SNAPSHOT DIFFERS [trigger 1: stop]")
        else
            print("  ★ signature NOT produced and every snapshot matches its after-read")
            print("    -- a clean negative, not a failure [trigger 3]")
        end
        m:exit()
    end
end)
