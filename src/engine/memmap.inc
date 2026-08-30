* src/engine/memmap.inc -- THE 64 KB MAP. One home for every address (CLAUDE.md §2F).
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THIS FILE IS THE MAP. Before it existed, four probes each assumed the whole 64 KB to
* itself and two of them already overlapped: pic_probe's priority plane spans $1700-$7FFF and
* res_probe's arena sits inside it at $3000-$6000. They coexisted only because they had never
* run together. **Every address below is owned by exactly one subsystem and nothing overlaps.**
*
* ★★ THE HARNESS IS NOT CHANGED BY THIS FILE AND MUST NOT BE. src/harness/ keeps its own
* addresses and its four gates keep running unmodified [T-P0-031 §5C]. The engine is built
* ALONGSIDE the harness, not by moving it -- a map that silently rewrote the probes would
* invalidate every gate result in the same commit that claimed to preserve them.
*
* ─────────────────────────────────────────────────────────────────────────────────────────
* ★★★ THE MMU IS THE WHOLE DESIGN. 512 KB is 64 blocks of 8 KB; the CPU sees eight of them at
* once through slots $FFA0-$FFA7. So "the map" is really TWO facts: which slot each region
* occupies, and which blocks get mapped there in which PHASE (§3.4).
*
*   slot  window        VM phase                    picture-draw / sprite-composite
*   ----  ------------  --------------------------  --------------------------------
*    0    $0000-$1FFF   system + VM state + DIRs    (unchanged -- always resident)
*    1    $2000-$3FFF   engine code                 (unchanged)
*    2    $4000-$5FFF   engine code + reserved      (unchanged)
*    3    $6000-$7FFF   ARENA window lo             (unchanged -- the resource is being read)
*    4    $8000-$9FFF   ARENA window hi             (unchanged)
*    5    $A000-$BFFF   -- nothing mapped --        ★ PRIORITY slice
*    6    $C000-$DFFF   VOLUME window               ★ FRAMEBUFFER slice
*    7    $E000-$FEFF   resident tables             (unchanged)
*
* ★★★ THE PHASES ARE DISJOINT AND THAT IS THE POINT (§3.4). The VM runs with NO plane mapped;
* slot 5 is idle and slot 6 holds the volume window. Entering a draw phase remaps EXACTLY TWO
* slots. A resource fetch never happens while drawing, so slot 6's two uses never collide.
* ★★ TWO REMAPS PER PHASE TRANSITION, NOT PER SCANLINE -- the failure §3.4 exists to prevent.
* At 160 B/row an 8 KB slice covers 51 rows, so a full-screen pass costs 3 further remaps.
* ═══════════════════════════════════════════════════════════════════════════════════════════

                ifndef  AGI_MEMMAP_INC
AGI_MEMMAP_INC  equ     1

* ── slot 0: system, always resident ──────────────────────────────────────────────
* ★ $0000-$001F is the HAL's direct page and is NOT ours [pic_probe.s:75].
MAP_STATUS      equ     $0020           ; interpreter status/scratch, 224 B
MAP_SEEDSTACK   equ     $0100           ; picture flood-fill seed stack
MAP_SEEDSTACK_E equ     $0500           ; ★ 1,024 B = 512 entries of (x,y)
* ★★ S STARTS AT $0800 AND GROWS DOWN into $0500-$07FF. pic_probe learned this the hard way:
* leaving S where DECB put it aimed the hardware stack into the fill stack, and a deep fill
* overwrote a return address [pic_probe.s:20-26]. 768 B against a MEASURED max depth of 3.
MAP_HWSTACK     equ     $0800           ; S initialises here; usable $0500-$07FF
MAP_VMSTATE     equ     $0800           ; VM state block, 2,048 B
MAP_VM_VARS     equ     $0800           ;   256 vars
MAP_VM_FLAGS    equ     $0900           ;   256 flags, 1 byte each (not packed -- see below)
MAP_VM_CTRL     equ     $0A00           ;   controller table
MAP_VM_OBJROOMS equ     $0A20           ;   256 inventory-item room numbers
MAP_VM_OBJ      equ     $0B20           ;   screen objects, 16 x 42 B
MAP_DIRS        equ     $1000           ; the game's own DIR tables -- THE resource index
MAP_DIR_STRIDE  equ     $0400           ;   1 KB per type: 341 slots vs 216 present max
MAP_DIRS_END    equ     $2000           ;   4 types x 1 KB = 4,096 B
* ★★★ §2F.3: THE RESOURCE MAP IS THE GAME'S OWN DIR TABLES. There is no second index. The
* arena's occupancy is tracked in MAP_STATUS, not by building a parallel directory.

* ── slots 1-2: engine code, always resident ──────────────────────────────────────
MAP_CODE        equ     $2000
MAP_CODE_END    equ     $5000           ; ★ 12,288 B, against vm_probe.bin's MEASURED 9,089
* ★★★ RESERVED FOR THE PARSER AND SOUND, WHICH ARE NOT BUILT. Named here so the map does not
* have to move when they arrive [T-P0-031 AC-3]. 4 KB is not a guess dressed as a measurement:
* it is what is left in slot 2 once the code region is sized, and it is stated as an
* allocation to be CHECKED against the parser and sound when they exist, not as a prediction.
MAP_RESERVED    equ     $5000
MAP_RESERVED_END equ    $6000           ; 4,096 B, parser + sound

* ── slots 3-4: the residency arena's WINDOW ──────────────────────────────────────
* ★★★★ SIXTEEN KB, AND THE SIZE IS FORCED BY A MEASUREMENT, NOT CHOSEN. The largest single
* resource in the v2 corpus is a **10,964-byte LOGIC** (larry1; SpaceQuest-1 10,651, KQ3
* 10,428, and every title exceeds 8,192). **A one-slot window could not address the largest
* LOGIC in seven of seven titles.** So the window is two contiguous slots.
* ★★ THE WINDOW IS NOT THE ARENA. The arena is 3 blocks (24 KB) of the ~46 free, and this is
* the aperture onto it -- so the arena can GROW without any address here moving.
MAP_ARENA_WIN   equ     $6000
MAP_ARENA_WIN_E equ     $A000           ; 16,384 B >= 10,964 max resource

* ── slot 5: the priority slice, draw phases only ─────────────────────────────────
* ★★★ PACKED 4 BITS PER PIXEL, AND THIS IS A REAL DIVERGENCE FROM THE HARNESS. Design §3.2
* budgets **2 blocks** for priority. 160 x 168 at ONE BYTE per pixel is 26,880 B = 3.28 blocks
* and DOES NOT FIT. At 4 bits it is 13,440 B = 1.64 blocks and fits exactly. AGI priority
* values are 0-15, so 4 bits is lossless.
* ★★ The probes deliberately use one byte per pixel -- "the SAME shape as the oracle's. No
* transform, no place for a transform error to hide" [pic_probe.s:39-41] -- which is right for
* a GATE and wrong for the shipped plane. **The pack/unpack is a transform at the seam and it
* is a cost: the composite's priority read becomes a nibble extract on every pixel** (T-P0-030
* measured the priority test at 2.7% and the transparency test at 70.9%, so this lands on the
* cheap path, but it is not free and it is not yet measured).
MAP_PRI_SLICE   equ     $A000
MAP_PRI_SLICE_E equ     $C000           ; 8,192 B aperture; plane is 13,440 B = 2 slices

* ── slot 6: the phase-switched window ────────────────────────────────────────────
* ★★ ONE SLOT, TWO USES, NEVER AT THE SAME TIME. The volume window is live only while a
* resource is being fetched, which happens in the VM phase; the framebuffer slice is live only
* while drawing. §3.4's disjointness is what makes this legal, and it is the single place in
* the map where that property is load-bearing rather than incidental.
MAP_PHASE_WIN   equ     $C000
MAP_PHASE_WIN_E equ     $E000           ; 8,192 B
MAP_VOL_WINDOW  equ     MAP_PHASE_WIN   ;   VM phase:   one 8 KB VOL block
MAP_FB_SLICE    equ     MAP_PHASE_WIN   ;   draw phase: one 8 KB framebuffer slice

* ── slot 7: resident tables ──────────────────────────────────────────────────────
MAP_TABLES      equ     $E000
MAP_PRI_BANDS   equ     $E000           ; ★ §2F.4: 168-byte LOOKUP, never a computation
MAP_PALETTE     equ     $E0A8           ; ★ §2F.1: 16-byte table, loaded at init. NEVER inline
MAP_FONT        equ     $E0B8           ; the authored 8x8 40-column font, 2,048 B (§2B)
MAP_TABLES_END  equ     $FF00           ; ★ $FF00-$FFFF is the I/O page and is not ours

* ── the framebuffer and priority planes, as BLOCKS not addresses ─────────────────
* ★ Sizes, for the block budget (AC-7). These are not CPU-window addresses: the planes live in
* blocks and are reached a slice at a time through the slots above.
MAP_VIS_BYTES   equ     26880           ; 160 x 168, 1 B per AGI pixel = mode 2's 160 B stride
MAP_PRI_BYTES   equ     13440           ; 160 x 168 at 4 bpp -- see MAP_PRI_SLICE
MAP_ARENA_BYTES equ     24576           ; ★ 3 blocks, CHOSEN FROM THE EVICTION CURVE (AC-2)

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ EVERY ADJACENCY, ASSERTED AT ASSEMBLY TIME, IN MAP ORDER.
* AC-3 requires "no overlaps". **An overlap claim that is checked by a human reading a table is
* the state this task exists to end** -- four probes each had a coherent table and two of them
* overlapped. These assert on every build that includes this file, so the map cannot silently
* drift the way pic_probe's $1700-$7FFF and res_probe's $3000-$6000 did.
* ★★ comp_probe.s does exactly this for its five regions and it is why that probe's map has
* never been wrong; this is the same mechanism applied to the shipped map.
                ifgt    MAP_SEEDSTACK-MAP_STATUS-224
                error   "status block overruns the seed stack"
                endc
                ifgt    MAP_SEEDSTACK+1024-MAP_SEEDSTACK_E
                error   "seed stack is not 1024 B"
                endc
                ifgt    MAP_SEEDSTACK_E-MAP_HWSTACK
                error   "seed stack overruns the hardware stack region"
                endc
                ifgt    MAP_VMSTATE+2048-MAP_DIRS
                error   "VM state overruns the DIR tables"
                endc
                ifgt    MAP_DIRS+4*MAP_DIR_STRIDE-MAP_DIRS_END
                error   "DIR tables overrun their region"
                endc
                ifgt    MAP_DIRS_END-MAP_CODE
                error   "DIR tables overrun the code region"
                endc
                ifgt    MAP_CODE_END-MAP_RESERVED
                error   "engine code overruns the parser/sound reservation"
                endc
                ifgt    MAP_RESERVED_END-MAP_ARENA_WIN
                error   "parser/sound reservation overruns the arena window"
                endc
                ifgt    MAP_ARENA_WIN_E-MAP_PRI_SLICE
                error   "arena window overruns the priority slice"
                endc
                ifgt    MAP_PRI_SLICE_E-MAP_PHASE_WIN
                error   "priority slice overruns the phase window"
                endc
                ifgt    MAP_PHASE_WIN_E-MAP_TABLES
                error   "phase window overruns the resident tables"
                endc
                ifgt    MAP_TABLES_END-$FF00
                error   "resident tables run into the $FF00 I/O page"
                endc
* ★★★ THE ONE THAT IS NOT AN ADJACENCY, AND IT IS THE ONE THAT WAS MEASURED. The arena window
* must address the largest single resource in the corpus -- a 10,964-byte LOGIC (larry1). A
* one-slot window fails this on SEVEN of seven v2 titles.
                ifgt    10964-(MAP_ARENA_WIN_E-MAP_ARENA_WIN)
                error   "arena window smaller than the largest corpus resource (10,964 B)"
                endc
* ★★ The priority plane must fit design §3.2's two-block budget. 1 B/px would be 26,880 and
* fails this; 4 bpp is 13,440 and passes. **The assertion is what keeps the packing decision
* from being quietly reverted to match the harness's representation.**
                ifgt    MAP_PRI_BYTES-16384
                error   "priority plane exceeds design 3.2's 2-block budget"
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

                endc
