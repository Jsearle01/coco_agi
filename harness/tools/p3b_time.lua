-- harness/tools/p3b_time.lua -- T1, T2 and T3 on the glass, from an UNMODIFIED p3b binary.
-- [T-P0-063 AC-3/AC-4/AC-5]
--
-- ★★★★★ ZERO GUEST BYTES, AND THAT IS NOT A CONVENIENCE. p3b's code region has **3 bytes free**
-- (P3_CODE_END $52FD against MAP_CODE_END $5300), so the four marker pairs this breakdown wants
-- -- 40 bytes -- cannot be added. ★★★★ More importantly they should not be: a timing run that
-- adds instrumentation measures the instrumented program, and this one measures **the binary the
-- gates passed**, byte for byte.
-- ★★★ 6809 READ-TAPS FIRE ON THE OPCODE FETCH, which is this project's recorded technique
-- [idioms §10 and its line 54: "read-tap each routine's entry address"]. Tapping a routine's
-- entry address timestamps every call to it without the guest knowing.
--
-- ★★★★ THE BREAKDOWN COMES FROM ENTRY TIMES ALONE, because p3_room_check's calls are strictly
-- sequential [p3b_probe.s]:
--        res_open -> p3_clear_planes -> pic_render_at -> p3_present -> res_close
-- so each stage's duration is the gap to the NEXT stage's entry. No exit taps, no pairing to get
-- wrong, and the arithmetic is subtraction.
--
-- ★★★★★ AND IT IS CROSS-CHECKED AGAINST AN INDEPENDENT INSTRUMENT [L-61]. p3b_run.lua already
-- brackets the whole of roomcheck with its own PHASE markers 7/8. **The four parts measured here
-- must sum to that bracket.** Two instruments, two mechanisms (a PC tap and a guest store), one
-- quantity -- and if they disagree the breakdown is wrong, which is the only way to find that out.
--
-- ★★ It installs its taps and then `dofile`s p3b_run.lua, which is p3b_room.lua's pattern: this
-- file changes nothing in the driver it observes.
--
-- usage:  P3B_* as p3b_run.lua, plus P3B_TIME_OUT.  Symbols from build/p3b_probe_pk.map.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local MAPF = os.getenv("P3B_MAP") or "build/p3b_probe_pk.map"
local TOUT = os.getenv("P3B_TIME_OUT") or "build/p3b_time.txt"

-- ★★★ Symbols from the assembler's own map, never a literal -- P6.3 §3.F.2 cost hours to three
-- hard-coded addresses that had gone stale by two bytes. A missing symbol is fatal here.
local sym = {}
do
    local f = io.open(MAPF, "r")
    if not f then print("★★★ no map at " .. MAPF); m:exit(); return end
    for line in f:lines() do
        local n, v = line:match("^Symbol:%s+(%S+)%s+%b()%s+=%s+(%x+)")
        if n then sym[n] = tonumber(v, 16) end
    end
    f:close()
end

-- ★ The stages, in the order p3_room_check calls them. `res_close` is the terminator: it is not
-- a stage we report, it is what ends `present`.
local STAGES = { "res_open", "p3_clear_planes", "pic_render_at", "p3_present", "res_close" }
local EXTRA  = { "vm_interpret_cycle", "cp_composite" }

for _, n in ipairs(STAGES) do
    if not sym[n] then print(string.format("★★★ %s lacks symbol '%s'", MAPF, n)); m:exit(); return end
end

-- ★★★★ EVENTS ARE RECORDED, NOT LOGGED. A tap fires on the hot path; writing to a file from
-- inside one ended a T-P0-060 run at cycle 8 with no output at all, which reads as "the tap never
-- fired" -- the most misleading answer available [idiom 43c].
_G._p3t = { ev = {}, t0 = nil }
local EV = _G._p3t.ev

local function tap(name)
    local a = sym[name]
    if not a then return end
    _G["_p3t_" .. name] = prog:install_read_tap(a, a, "t_" .. name, function()
        if #EV < 20000 then EV[#EV + 1] = { name, m.time:as_double() } end
    end)
end
for _, n in ipairs(STAGES) do tap(n) end
for _, n in ipairs(EXTRA) do tap(n) end

-- ★★★ t0 IS THE GUEST'S FIRST INSTRUCTION, and where that is matters for what T1 MEANS.
-- p3b_run.lua waits for DECB's OK prompt, pokes the image and sets PC; the boot before that is
-- the HARNESS reaching a machine, not the product starting. A real LOADER.BIN load off a floppy
-- is NOT measured here and is out of this task's scope -- so T1/T2 are "from the port's first
-- instruction", stated rather than implied [§8 trigger 5].
-- ★★ MAP_CODE is the entry; tapping it gives the first instruction without asking the driver.
if sym.MAP_CODE or true then
    local entry = 0x2000
    _G._p3t_entry = prog:install_read_tap(entry, entry, "t_entry", function()
        if not _G._p3t.t0 then _G._p3t.t0 = m.time:as_double() end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★ The report is written at exit, from the recorded events. p3b_run.lua calls m:exit() when it
-- is done, so this hooks the stop notifier rather than racing it.
local function fmt(x) return string.format("%.4f", x) end

_G._p3t_stop = emu.add_machine_stop_notifier(function()
    local f = io.open(TOUT, "w")
    if not f then return end
    local function w(s, ...) f:write(string.format(s, ...) .. "\n") end

    local t0 = _G._p3t.t0
    w("=== T-P0-063: p3b on the glass, from an unmodified binary ===")
    w("events recorded : %d", #EV)

    -- ═══════════════════════════════════════════════════════════════════════════════════
    -- ★★★★★ THE TAP FIRES MORE THAN ONCE PER CALL, AND THIS IS WHERE THAT IS ESTABLISHED.
    -- The first version of this file reported 238 vm_interpret_cycle events for a 120-cycle run
    -- and a steady state of 17.77 cycles/s. p3b_run.lua -- an INDEPENDENT instrument, a guest
    -- store rather than a PC tap -- measured 120 cycles at 11.98/s over the same run. **My
    -- number was 48% high and entirely plausible.** [L-61 is why it was caught at all.]
    -- ★★★★ SO THE MULTIPLICITY IS MEASURED, NOT ASSUMED, AND IT IS PRINTED. A 6809 opcode fetch
    -- is not the only read of an instruction's address -- the core performs dummy/VMA reads --
    -- so a read tap counts accesses, not calls. The histogram below is what says how many, and
    -- the dedup window is derived from the gap distribution rather than picked.
    do
        local per, gaps = {}, {}
        for _, e in ipairs(EV) do per[e[1]] = (per[e[1]] or 0) + 1 end
        local prev = {}
        for _, e in ipairs(EV) do
            local p = prev[e[1]]
            if p then gaps[#gaps + 1] = { e[1], e[2] - p } end
            prev[e[1]] = e[2]
        end
        w("")
        w("=== tap multiplicity: raw fires per symbol (NOT calls) ===")
        for k, v in pairs(per) do w("   %-20s %d", k, v) end
        table.sort(gaps, function(a, b) return a[2] < b[2] end)
        w("   smallest consecutive same-symbol gaps (s): %s %s %s %s",
          gaps[1] and fmt(gaps[1][2]) or "-", gaps[2] and fmt(gaps[2][2]) or "-",
          gaps[3] and fmt(gaps[3][2]) or "-", gaps[4] and fmt(gaps[4][2]) or "-")
        local n6 = 0
        for _, g in ipairs(gaps) do if g[2] < 1e-4 then n6 = n6 + 1 end end
        w("   gaps under 100us: %d of %d  <- these are one call counted twice", n6, #gaps)
    end
    if not t0 then w("★★★ the entry tap never fired -- t0 unknown, every T is unmeasurable"); f:close(); return end
    w("t0 (guest's first instruction) : %s s emulated", fmt(t0))
    w("")

    -- ── walk the timeline, splitting it into room-check episodes ────────────────────────
    -- ★★ An episode is res_open..res_close. Anything between episodes is VM + compositing.
    w("=== room-check episodes: fetch / clear / render / present, by subtraction ===")
    w("%-4s %10s %10s %10s %10s %10s %10s", "#", "at(s)", "fetch", "clear", "render", "present", "TOTAL")
    local ep, n = {}, 0
    local i = 1
    while i <= #EV do
        if EV[i][1] == "res_open" then
            -- collect the following stage entries in order
            local t = { res_open = EV[i][2] }
            local j, order = i + 1, { "p3_clear_planes", "pic_render_at", "p3_present", "res_close" }
            local k = 1
            while j <= #EV and k <= #order do
                if EV[j][1] == order[k] then t[order[k]] = EV[j][2]; k = k + 1 end
                j = j + 1
            end
            if t.res_close then
                n = n + 1
                local fetch   = t.p3_clear_planes - t.res_open
                local clear   = t.pic_render_at   - t.p3_clear_planes
                local render  = t.p3_present      - t.pic_render_at
                local present = t.res_close       - t.p3_present
                local total   = t.res_close       - t.res_open
                ep[n] = { at = t.res_open, fetch = fetch, clear = clear, render = render,
                          present = present, total = total, presented = t.res_close }
                w("%-4d %10s %10s %10s %10s %10s %10s", n, fmt(t.res_open - t0), fmt(fetch),
                  fmt(clear), fmt(render), fmt(present), fmt(total))
            end
            i = j
        else
            i = i + 1
        end
    end
    w("")
    -- ★★★★ "ON THE GLASS" IS WHEN p3_present HAS FINISHED, not when the render has. The shadow
    -- buffer means the room is invisible until the blit completes [design §3.6a], so the moment a
    -- player sees it is p3_present's RETURN -- which is res_close's entry, the next call.
    if ep[1] then
        w("T1  start -> FIRST room presented   : %s s   (episode 1)", fmt(ep[1].presented - t0))
    end
    if ep[2] then
        w("T2  start -> SECOND room presented  : %s s   (episode 2)", fmt(ep[2].presented - t0))
    end
    w("★ which episode is the title screen and which is the first room is a ROOM NUMBER question;")
    w("  p3b_run.lua's own log names the room per cycle and the report pairs them up.")
    w("")

    -- ── steady state: cycles with no room change ────────────────────────────────────────
    -- ★★★ THE FRAME RATE IS THE STEADY-STATE ONE, and mixing the room-change cycles into it is
    -- how a stall gets averaged into a rate until neither number means anything [§4].
    local cyc, last = {}, nil
    for _, e in ipairs(EV) do
        if e[1] == "vm_interpret_cycle" then
            if last then cyc[#cyc + 1] = { last, e[2] - last } end
            last = e[2]
        end
    end
    local steady, stall = {}, {}
    for _, c in ipairs(cyc) do
        local inroom = false
        for _, x in ipairs(ep) do
            if c[1] >= x.at - 0.001 and c[1] <= x.presented + 0.001 then inroom = true break end
        end
        if inroom then stall[#stall + 1] = c[2] else steady[#steady + 1] = c[2] end
    end
    local function stats(t, label)
        if #t == 0 then w("%-28s (none)", label); return end
        table.sort(t)
        local sum = 0; for _, v in ipairs(t) do sum = sum + v end
        local med = t[math.floor(#t / 2) + 1]
        w("%-28s n=%-4d median %s s/cycle = %6.2f cycles/s   mean %s",
          label, #t, fmt(med), 1 / med, fmt(sum / #t))
    end
    w("=== per-cycle, split ===")
    stats(steady, "T3 steady state (no room)")
    stats(stall,  "   room-change cycles")
    -- ★ composite calls per cycle: the sprite work actually done, not the count staged.
    local nc = 0
    for _, e in ipairs(EV) do if e[1] == "cp_composite" then nc = nc + 1 end end
    w("cp_composite calls          : %d over %d cycles", nc, #cyc + 1)
    f:close()
    print("★ timing written to " .. TOUT)
end)

-- ★★★ T3 MUST BE MEASURED WITH SPRITES LIVE, so when P3B_ROOM is set this composes with
-- p3b_room.lua's jump rather than duplicating it -- that file already knows the room-change
-- mechanism is two host writes at $0800/$0900, and it records why those are not $4000/$4100.
-- ★★ Kingquest1 never leaves room 83 on its own [p3b_room.lua:5-6, measured at 300 cycles], so
-- without the jump the sprite count is ZERO and T3 would be the very case the dispatch excludes.
if os.getenv("P3B_ROOM") then
    dofile("harness/tools/p3b_room.lua")
else
    dofile("harness/tools/p3b_run.lua")
end
