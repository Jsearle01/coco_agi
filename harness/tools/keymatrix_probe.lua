-- harness/tools/keymatrix_probe.lua -- do Jay's control-scheme keys REACH THE GUEST, and where
-- do they sit in the 8x8 matrix? [T-P0-062 AC-5; §3's "check it early"]
--
-- ★★★★★ A FIELD NAME IS NOT A KEYPRESS, AND THE FIRST VERSION OF THIS PROBE ONLY CHECKED NAMES.
-- Worse, it matched them by SUBSTRING: "left" hit "rat mouse button 2 (left port)", "E" hit
-- "ENTER", and "C" hit "ad stick y 2". It then printed "★ every key in AD-134's scheme exists"
-- -- a true verdict resting on three garbage rows, and a matcher that loose could just as easily
-- have "found" a key that was absent. **A diagnostic that cannot be wrong does not measure, it
-- testifies** [§2W.3], and this one gates a §9 trigger-2 stop.
--
-- ★★★★ SO IT PRESSES THEM AND READS THE HARDWARE. The CoCo keyboard is an 8x8 matrix read
-- through PIA0: write a column strobe to $FF02, read $FF00, and a pressed key pulls its row bit
-- LOW. Holding one field and scanning all eight columns gives that key's (column,row) -- which
-- is a fact about the machine, not about MAME's naming.
--
-- ★★★ AND IT ANSWERS THE GHOSTING QUESTION, which §3 asks and which cannot be answered from a
-- key list. Ghosting needs THREE keys forming a rectangle in the matrix; any TWO keys are always
-- distinguishable. Jay's chords are CTRL + one letter -- two keys -- so they cannot ghost, and
-- the matrix positions below are what shows it rather than asserting it.
--
-- ★★ Names come from the driver's own port fields (§2A.5's exhaustive search) and are matched
-- EXACTLY, case-insensitively, against a list of candidate spellings.

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local out  = io.open("build/keymatrix.txt", "w")
local function w(f, ...) local s = string.format(f, ...); out:write(s .. "\n"); print(s) end

-- ── find a field by EXACT name, case-insensitively ──────────────────────────────────────
local byname = {}
for tag, port in pairs(m.ioport.ports) do
    for name, field in pairs(port.fields) do
        byname[name:lower()] = { field = field, tag = tag, name = name }
    end
end
local function find(cands)
    for _, c in ipairs(cands) do
        local e = byname[c:lower()]
        if e then return e end
    end
    return nil
end

-- ★ The real CoCo3 field names, read out of the driver's own list (see the dump this probe
-- wrote on its first run): arrows and letters carry both cases, "q  Q" style.
local SCHEME = {
    { "UP",    { "UP" } },      { "DOWN",  { "DOWN" } },
    { "LEFT",  { "LEFT" } },    { "RIGHT", { "RIGHT" } },
    { "CTRL",  { "CTRL" } },    { "ALT",   { "ALT" } },
    { "ENTER", { "ENTER" } },
    { "Q", { "q  Q" } }, { "E", { "e  E" } }, { "Z", { "z  Z" } }, { "C", { "c  C" } },
}

w("=== AD-134's keys: does the driver define them, EXACTLY? ===")
local missing = {}
for _, row in ipairs(SCHEME) do
    local e = find(row[2])
    w("  %-6s %s", row[1], e and string.format("%-10s [%s]", '"' .. e.name .. '"', e.tag)
                              or "★★★ NOT DEFINED BY THE DRIVER")
    if not e then missing[#missing + 1] = row[1] end
end

-- ── press each key and read the matrix ──────────────────────────────────────────────────
-- ★★ $FF02 is the column strobe (active LOW), $FF00 returns the row bits (pressed = LOW).
-- The DDRs must select input on PIA0-A; DECB has already configured them by the time this runs.
local function scan()      -- returns "col,row" for whatever single key is held, or nil
    for col = 0, 7 do
        prog:write_u8(0xFF02, (~(1 << col)) & 0xFF)
        local r = prog:read_u8(0xFF00)
        for bit = 0, 7 do
            if (r & (1 << bit)) == 0 then return col, bit end
        end
    end
    return nil
end

w("")
w("=== pressed, and read back through PIA0 ($FF02 strobe, $FF00 rows) ===")
local pos, unreachable = {}, {}
for _, row in ipairs(SCHEME) do
    local e = find(row[2])
    if e then
        e.field:set_value(1)
        emu.wait_next_frame(); emu.wait_next_frame()
        local col, bit = scan()
        e.field:set_value(0)
        emu.wait_next_frame()
        if col then
            pos[row[1]] = { col, bit }
            w("  %-6s column %d, row bit %d", row[1], col, bit)
        else
            unreachable[#unreachable + 1] = row[1]
            w("  %-6s ★★★ PRESSED BUT NOT SEEN IN THE MATRIX", row[1])
        end
    end
end

-- ★★★ GHOSTING: three keys ghost when two share a column, two share a row, and the fourth
-- corner is implied. Jay's chords are two keys, which cannot ghost -- this states the pair
-- positions so a reader can check that rather than take it on trust.
w("")
w("=== CTRL + letter chords: two keys each, so ghosting is structurally impossible ===")
local c = pos["CTRL"]
for _, k in ipairs({ "Q", "E", "Z", "C" }) do
    local p = pos[k]
    if c and p then
        w("  CTRL(%d,%d) + %s(%d,%d)%s", c[1], c[2], k, p[1], p[2],
          (c[1] == p[1] and "   ★ same column -- distinguishable, but note it" or ""))
    end
end

w("")
if #missing == 0 and #unreachable == 0 then
    w("★ every key in AD-134's scheme is defined AND reaches the guest.")
else
    w("★★★ not defined: %s", #missing == 0 and "-" or table.concat(missing, ", "))
    w("★★★ defined but unreachable: %s", #unreachable == 0 and "-" or table.concat(unreachable, ", "))
    w("    §9 trigger 2: report and stop. A substitution is Jay's ruling.")
end
out:close()
m:exit()
