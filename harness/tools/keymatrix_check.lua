-- harness/tools/keymatrix_check.lua -- what does MAME's coco3 keyboard actually look like, and
-- which delivery mechanism reaches $FF00? [P6.24 AC-3]
--
-- ★★★★★ THIS ANSWERS "WHY", NOT "DOES IT WORK NOW". P6.23 established that natkeyboard accepts a
-- post, the guest strobes, and $FF00 reads all-high -- three observations consistent with several
-- causes. **$FF00 is downstream of MAME's input path, the ioport layer, the PIA and the strobe**
-- [L-103: a derived field cannot classify the stage that produced it], so this walks UP the chain
-- one layer at a time and reports where the signal first appears.
--
-- ★★★★ THE HOST DOES THE SCANNING, so the guest is not a variable. It asserts CRA/CRB data mode,
-- drives one column low on $FF02 and reads $FF00 -- the same two instructions HAL_key_scan uses,
-- with no 6809 involved. If a key shows up here and not to the guest, the guest is the problem;
-- if it shows up in neither, the guest never was.
--
-- ★★★ IT ALSO ENUMERATES THE PORTS, which is an independent check on the matrix table in
-- hal_globals.s: dist/mame-cfg/rgb/coco3.cfg records BREAK at `:row6` mask 0x0004 and CTRL at
-- mask 0x0010, and the table says PA6/PB2 and PA6/PB4. **Row = port tag, mask bit = column.**
--
-- usage:  mame coco3 -autoboot_script harness/tools/keymatrix_check.lua -seconds_to_run 12

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- ★★★★★ ARMED AT SCRIPT LOAD [idiom 14b], and at frame ZERO rather than at frame 3000 [41f's own
-- process lesson: an instrument armed after the window closes records nothing].
m.natkeyboard.in_use = true

local WANT = os.getenv("KM_KEYS") or "A,ENTER,CTRL,ALT,UP,DOWN,LEFT,RIGHT,Q,E,Z,C,SPACE,0,9"

local fields = {}
local function enumerate()
    local n = 0
    for tag, port in pairs(m.ioport.ports) do
        for fname, field in pairs(port.fields) do
            fields[fname:upper()] = { f = field, tag = tag, mask = field.mask }
            n = n + 1
        end
    end
    return n
end

-- ★★ The same read HAL_key_scan performs: assert data mode, drive one column low, read the rows.
local function scan_column(col)
    local cra = prog:read_u8(0xFF01)
    prog:write_u8(0xFF01, (cra & 0xFC) | 0x04)
    local crb = prog:read_u8(0xFF03)
    prog:write_u8(0xFF03, (crb & 0xFC) | 0x04)
    prog:write_u8(0xFF02, (~(1 << col)) & 0xFF)
    local rows = prog:read_u8(0xFF00)
    prog:write_u8(0xFF02, 0xFF)
    return (~rows) & 0x7F            -- a SET bit = pressed
end

local function scan_all()
    local hits = {}
    for col = 0, 7 do
        local r = scan_column(col)
        if r ~= 0 then
            for row = 0, 6 do
                if (r & (1 << row)) ~= 0 then
                    hits[#hits + 1] = string.format("row%d/col%d", row, col)
                end
            end
        end
    end
    return hits
end

local phase, t0, idx, held = "boot", 0, 1, 0
local keys = {}
for k in WANT:gmatch("[^,]+") do keys[#keys + 1] = k:upper() end
local results = {}

_G._km = emu.add_machine_frame_notifier(function()
    if phase == "boot" then
        if m.time:as_double() < 0.5 then return end
        local n = enumerate()
        print(string.format("=== ioport: %d fields across %d ports ===", n,
                            (function() local c = 0
                                for _ in pairs(m.ioport.ports) do c = c + 1 end
                                return c end)()))
        for _, k in ipairs(keys) do
            local e = fields[k]
            if e then
                print(string.format("  %-8s tag=%-10s mask=0x%04X", k, e.tag, e.mask))
            else
                print(string.format("  %-8s ★★★ NOT AN IOPORT FIELD", k))
            end
        end
        -- ★★★ Baseline: with nothing pressed the matrix must read clean. If it does not, every
        -- later reading is against a floor nobody established.
        local base = scan_all()
        print(string.format("=== baseline (no key): %d row/col hits ===", #base))
        if #base > 0 then print("     " .. table.concat(base, " ")) end
        phase = "post"
        t0 = m.time:as_double()
        return
    end

    -- ── layer 1: natkeyboard:post, the mechanism P6.23 used ──
    if phase == "post" then
        if m.time:as_double() - t0 < 0.2 then return end
        m.natkeyboard:post("a")
        print(string.format("=== natkeyboard:post('a') -- empty now %s ===",
                            tostring(m.natkeyboard.empty)))
        phase = "post_watch"
        t0 = m.time:as_double()
        held = 0
        return
    end
    if phase == "post_watch" then
        local hits = scan_all()
        if #hits > 0 then
            print(string.format("  ★ post REACHED the matrix after %.3f s: %s",
                                m.time:as_double() - t0, table.concat(hits, " ")))
            phase = "field"
            t0 = m.time:as_double()
            return
        end
        held = held + 1
        if held > 120 then
            print(string.format("  ★★★ post did NOT reach the matrix in %d frames "
                                .. "(natkeyboard.empty=%s)", held, tostring(m.natkeyboard.empty)))
            phase = "field"
            t0 = m.time:as_double()
        end
        return
    end

    -- ── layer 2: assert the ioport field directly, idiom 41f's measured technique ──
    if phase == "field" then
        local k = keys[idx]
        local e = fields[k]
        if not e then
            results[#results + 1] = { k = k, ok = false, why = "no such field" }
            idx = idx + 1
            if idx > #keys then phase = "done" end
            return
        end
        e.f:set_value(1)
        held = 1
        phase = "field_watch"
        return
    end
    if phase == "field_watch" then
        local k = keys[idx]
        local e = fields[k]
        local hits = scan_all()
        held = held + 1
        if #hits > 0 then
            results[#results + 1] = { k = k, ok = true, where = table.concat(hits, " ") }
            e.f:set_value(0)
            idx = idx + 1
            phase = (idx > #keys) and "done" or "field"
            return
        end
        if held > 8 then
            results[#results + 1] = { k = k, ok = false, why = "asserted, matrix silent" }
            e.f:set_value(0)
            idx = idx + 1
            phase = (idx > #keys) and "done" or "field"
        end
        return
    end

    if phase == "done" then
        print("=== field assertion -> matrix ===")
        local good = 0
        for _, r in ipairs(results) do
            if r.ok then
                good = good + 1
                print(string.format("  %-8s ★ %s", r.k, r.where))
            else
                print(string.format("  %-8s ★★★ %s", r.k, r.why))
            end
        end
        print(string.format("=== %d of %d keys reached $FF00 by field assertion ===",
                            good, #results))
        m:exit()
    end
end)
