-- harness/tools/mem_probe.lua -- can the HOST read what the GUEST wrote, per MMU slot?
--
-- ★★★ THIS EXISTS BECAUSE TWO INSTRUMENTS LIED. A trace buffer at $9400 and a coverage table at
-- $9300 both read back as plausible garbage -- near-uniform byte values that looked like
-- execution counts and like instruction pointers. Everything that read back CORRECTLY
-- (VM_VARS $7000, VM_FLAGS $7100, the object table's first entries at $7240) is below $8000.
--
-- ★★ So the question is not "is my VM wrong" but "is my instrument readable", and those have
-- opposite fixes. This writes a known pattern from the host into one address per MMU slot and
-- reads it straight back, after HAL_sys_init has installed the all-RAM map.
--
-- ★ L-56 in its sharpest form: the measurement apparatus is part of the system under test.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ★★★ CORRECTION, T-P0-027. THE CONCLUSION DRAWN FROM THIS PROBE WAS WRONG.
--
-- It reported $8900/$9300/$9400/$A900/$C900/$E900 NOT READABLE and everything below $8000 fine,
-- and that was read as "MAME's CPU program space does not follow the GIME MMU above $8000".
-- **The cause was ROM.** HAL_sys_init does not enable all-RAM mode -- sys.s:118-128 says so in
-- as many words: "$FF90 selects ROM MAPPING, and it has no all-RAM setting at all: $FFDE/$FFDF,
-- which THIS ROUTINE NEVER WRITES; HAL_gfx_init and HAL_gfx_set_mode write $FFDF as their final
-- step." mem_probe calls neither, so $8000-$FEFF was ROM and the HOST's writes did not stick
-- either -- exactly as the GUEST's did not.
--
-- ★★ The observation was right and the mechanism was wrong, and the two are not the same thing
-- (2). VM_OPSEEN and the trace buffer were relocated below $8000 on this reasoning; the moves
-- were harmless and the RECORDED REASON was not the reason.
--
-- ★ What settles it: vm_probe.s writes $FFDF and then runs a guest-side walking-pattern test
-- over the whole arena. With the write, the first bad address is none; without it, $8000.
-- **A host-side readback cannot distinguish "MAME cannot see it" from "it is not RAM"; a
-- guest-side write-and-read-back can, and that is the probe to reach for.**
-- ═══════════════════════════════════════════════════════════════════════════════════════════

local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local prog = cpu.spaces["program"]

local PROG = os.getenv("VM_PROG") or "build/vm_probe.bin"
local LOAD, GO = 0x0700, 0x0080

local function slurp(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("a"); f:close(); return d
end

local frame, state = 0, "load"
_G._n = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame < 4 then return end

    if state == "load" then
        local blob = slurp(PROG)
        if not blob then print("no program"); m:exit(); return end
        for i = 1, #blob do prog:write_u8(LOAD + i - 1, blob:byte(i)) end
        prog:write_u8(GO, 1)
        cpu.state["PC"].value = LOAD
        state = "boot"
        return
    end

    if state == "boot" then
        -- the guest clearing GO proves HAL_sys_init ran and the MMU map is installed
        if prog:read_u8(GO) ~= 0 then return end
        print("MMU slot readback -- host writes $A5/$5A, host reads back")
        print("  addr    slot  wrote  read  verdict")
        local addrs = { 0x0900, 0x2900, 0x3900, 0x4900, 0x6900,
                        0x7900, 0x8900, 0x9300, 0x9400, 0xA900, 0xC900, 0xE900 }
        for _, a in ipairs(addrs) do
            local slot = math.floor(a / 0x2000)
            prog:write_u8(a, 0xA5)
            local r1 = prog:read_u8(a)
            prog:write_u8(a, 0x5A)
            local r2 = prog:read_u8(a)
            local ok = (r1 == 0xA5 and r2 == 0x5A)
            print(string.format("  $%04X   %d     A5/5A  %02X/%02X  %s",
                  a, slot, r1, r2, ok and "OK" or "★★★ NOT READABLE"))
        end
        m:exit()
    end
end)
