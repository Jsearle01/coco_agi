-- harness/tools/mode2_probe.lua -- AC-6 runtime read for the mode-2 descriptor.
--
-- Pokes build/mode2_probe.bin into RAM at $2000, sets PC there, lets it run, then reads the
-- probe's result block at $7F00 and writes it to a file.
--
-- ★ NO RENDERING and NO VISUAL GATE. Dispatch §12 puts pixels in T-P0-011. This only asks
-- whether HAL_gfx_set_mode could REACH descriptor row 2 -- a stale GFX_MODE_MAX would silently
-- clamp mode 2 to mode 0, and the emitted table bytes cannot detect that.
--
-- ★ Idioms honoured (mame-idioms-coco3-port.md §10):
--   * output via io.open, NOT print() -- the console is not captured headless
--   * the frame notifier is kept in _G or it is GC'd and silently stops firing
--   * -seconds_to_run is EMULATED seconds

local OUT   = os.getenv("MODE2_OUT") or "build/mode2_probe.out"
local IMG   = os.getenv("MODE2_IMG") or "build/mode2_probe.bin"
local LOAD  = 0x2000
local RESULT = 0x7F00

local function log(fmt, ...)
    local f = io.open(OUT, "a")
    if f then f:write(string.format(fmt, ...) .. "\n"); f:close() end
end

-- fresh file each run
local f0 = io.open(OUT, "w"); if f0 then f0:close() end

local cpu  = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]

-- load the raw image
local fh = io.open(IMG, "rb")
if not fh then log("FAIL: cannot open %s", IMG); return end
local blob = fh:read("*all"); fh:close()
log("image %s: %d bytes -> $%04X", IMG, #blob, LOAD)

_G._mode2_done = false
_G._mode2_frames = 0

-- ★ kept in _G deliberately: a notifier that is garbage-collected stops firing SILENTLY,
-- which reads as "the probe never completed" and is the wrong conclusion.
_G._mode2_notifier = emu.add_machine_frame_notifier(function()
    _G._mode2_frames = _G._mode2_frames + 1

    -- ★ SETTLE FIRST. Poking at frame 2 failed: DECB is still initialising and the PC set
    -- does not stick -- the probe stayed resident at $2000 but the CPU wandered off in ROM
    -- ($1BC8, $03F9, $086D observed). POP's shift_bench.lua waits for frame 240 with the
    -- comment "let the machine settle"; that is the proven idiom and this now matches it.
    if _G._mode2_frames == 240 then
        -- poke the image, then vector the CPU at it
        for i = 1, #blob do
            prog:write_u8(LOAD + i - 1, string.byte(blob, i))
        end
        -- clear the result block so a stale value cannot be mistaken for a fresh one
        for a = RESULT, RESULT + 7 do prog:write_u8(a, 0) end
        cpu.state["PC"].value = LOAD
        log("poked and PC set to $%04X at frame %d", LOAD, _G._mode2_frames)
        return
    end

    -- diagnostic: where is the CPU, and is the probe code still resident?
    if _G._mode2_frames == 242 or _G._mode2_frames == 260 or _G._mode2_frames == 400 then
        local ok, pc = pcall(function() return cpu.state["PC"].value end)
        log("  frame %3d: PC=%s  [$2000]=%02X %02X %02X  [$7F00..05]=%02X %02X %02X %02X %02X %02X",
            _G._mode2_frames, ok and string.format("$%04X", pc) or "?",
            prog:read_u8(0x2000), prog:read_u8(0x2001), prog:read_u8(0x2002),
            prog:read_u8(0x7F00), prog:read_u8(0x7F01), prog:read_u8(0x7F02),
            prog:read_u8(0x7F03), prog:read_u8(0x7F04), prog:read_u8(0x7F05))
    end

    if _G._mode2_frames > 241 and not _G._mode2_done then
        local sentinel = prog:read_u8(RESULT + 5)
        if sentinel == 0xA5 then
            local mode   = prog:read_u8(RESULT + 0)
            local vres   = prog:read_u8(RESULT + 1)
            local stride = prog:read_u8(RESULT + 2)
            local words  = prog:read_u8(RESULT + 3) * 256 + prog:read_u8(RESULT + 4)
            log("RESULT sentinel=$A5 (probe ran to completion)")
            log("  HAL_gfx_cur_mode   = %d", mode)
            log("  HAL_gfx_cur_vres   = $%02X", vres)
            log("  HAL_gfx_cur_stride = %d", stride)
            log("  HAL_gfx_cur_words  = %d ($%04X)", words, words)
            log("VERDICT: %s", (mode == 2 and words == 16000 and vres == 0x3E
                                and stride == 160) and "PASS" or "FAIL")
            _G._mode2_done = true
            manager.machine:exit()
        elseif _G._mode2_frames > 700 then
            log("FAIL: sentinel never written after %d frames (probe did not complete)",
                _G._mode2_frames)
            _G._mode2_done = true
            manager.machine:exit()
        end
    end
end)
