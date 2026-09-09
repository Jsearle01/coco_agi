-- harness/tools/key_bindings.lua -- which HOST key drives which CoCo3 matrix position.
--
-- ★★★★★ THE QUESTION THIS ANSWERS IS NOT "does the decoder work". key_coverage.lua already
-- asserts matrix fields directly and gets 10/10, so the guest side is proven. What that gate
-- CANNOT see is the step before it: **a person presses a key on a PC keyboard, and MAME decides
-- which CoCo3 key that is.** A decoder can be perfect and the operator still unable to reach it.
--
-- ★★★★ It exists because backspace looked broken and was not: the table maps CLEAR to $08
-- [hal_globals.s], and pressing the PC's Backspace does not press CLEAR.
--
-- ★★ Prints every keyboard field with its row/mask and the host sequence bound to it, so the
-- answer is read off MAME rather than assumed from a layout diagram.
-- ★ §2P: no game data involved.

local m = manager.machine

local function seq_of(field)
    local ok, s = pcall(function()
        return m.input:seq_name(field:input_seq("standard"))
    end)
    if ok and s and s ~= "" then return s end
    local ok2, s2 = pcall(function() return m.input:seq_name(field.defseq) end)
    if ok2 and s2 and s2 ~= "" then return s2 end
    return "?"
end

print("=== CoCo3 keyboard: matrix position -> host key ===")
for tag, port in pairs(m.ioport.ports) do
    if tag:match("row%d") then
        local rows = {}
        for _, field in pairs(port.fields) do
            rows[#rows + 1] = { mask = field.mask, name = field.name, seq = seq_of(field) }
        end
        table.sort(rows, function(a, b) return a.mask < b.mask end)
        for _, r in ipairs(rows) do
            -- ★★ mask is the COLUMN bit; log2 it so the printed pair matches the (row, col) the
            -- HAL's 56-byte table is indexed by -- row*8 + col.
            local col = -1
            for i = 0, 7 do if r.mask == (1 << i) then col = i end end
            print(string.format("  %-6s mask=$%02X col=%d  %-14s <- %s",
                                tag:gsub(":", ""), r.mask, col, r.name, r.seq))
        end
    end
end
m:exit()
