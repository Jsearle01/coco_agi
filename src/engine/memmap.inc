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
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ 768 B, NOT 1,024 -- THE MAP WAS STALE AGAINST THE PROBE BY A FULL TASK-SERIES [P6.13].
* This said 1,024 B / 512 entries. **pic_probe.s cut the stack to $0100-$0400 in P3.13** -- 768 B,
* 384 entries -- and the map was never brought along, so the engine reserved 256 bytes the
* renderer had already given back. A dispatch then budgeted from this line and computed "roughly
* 950 bytes idle" from a figure with no producer [AD-95's shape: a number in a comment].
*
* ★★★★★ THE SIZE IS EVIDENCE-BASED AND THE EVIDENCE IS RE-MEASURED, not inherited. Across the
* renderer gate's whole corpus the high-water mark is **74 bytes / 37 entries** (`sp_peak_bytes`
* in build/sweep/timing.csv, max over every picture; mean 15.2 B). That is the same figure P3.13
* sized against, re-taken on the corpus that runs today rather than cited from it.
* ★★★★ HEADROOM IS SIZED ON THE MODEL, NOT THE SAMPLE. The P2 fill study's offline prediction of
* worst-case demand is 102 entries / 204 bytes -- higher than any picture actually reaches. 384
* entries is 3.8x that prediction and 10.4x the measured peak, and pic_probe.s ASSERTS the
* resulting margin at assembly time rather than trusting it.
* ★★★ NOT CUT FURTHER, DELIBERATELY. A flood fill's demand is a property of pictures we have not
* rendered [AD-113 found a 71.5% divergence on a picture outside the gate corpus], the overflow
* path HALTS rather than wrapping, and **this region cannot relieve the pressure that motivated
* the cut**: the seed stack is in slot 0 at $0100 and the code region is slots 1-2 at $2000-$5300.
* Bytes freed here do not house a text engine.
MAP_SEEDSTACK   equ     $0100           ; picture flood-fill seed stack
MAP_SEEDSTACK_E equ     $0400           ; ★ 768 B = 384 entries of (x,y); peak measured at 37
* ★★ S STARTS AT $0800 AND GROWS DOWN into $0500-$07FF. pic_probe learned this the hard way:
* leaving S where DECB put it aimed the hardware stack into the fill stack, and a deep fill
* overwrote a return address [pic_probe.s:20-26]. 768 B against a MEASURED max depth of 3.
MAP_HWSTACK     equ     $0800           ; S initialises here; usable $0500-$07FF
MAP_VMSTATE     equ     $0800           ; VM state block, 2,048 B
MAP_VM_VARS     equ     $0800           ;   256 vars
MAP_VM_FLAGS    equ     $0900           ;   256 flags, 1 byte each (not packed -- see below)
MAP_VM_CTRL     equ     $0A00           ;   controller table
MAP_VM_OBJROOMS equ     $0A20           ;   256 inventory-item room numbers
MAP_VM_OBJ      equ     $0B20           ;   screen objects, 16 x 42 B  -> ends $0DC0
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ THE STRING TABLE AND THE INPUT LINE LIVE HERE, IN THE VM STATE BLOCK'S TAIL [P6.21].
*
* ★★★★ AND THE REASON IS OWNERSHIP, NOT SPACE. `strings[]` is written by set.string,
* word.to.string and get.string, and read by %s -- **it is VM state in exactly the way vars and
* flags are**, and it was only ever considered for MAP_RESERVED because that is where the text
* engine happens to live. Putting it here is right on its own merits; the 520 bytes it stops
* costing the parser/sound reservation are a consequence, not the argument.
*
* ★★★★★ THIRTEEN SLOTS, MEASURED, NOT THE ORACLE'S TWENTY-FIVE. agi.h declares
* `strings[MAX_STRINGS + 1][MAX_STRINGLEN]` = 25 x 40 = 1,000 B. harness/tools/string_census.py
* walks the bytecode of **889 logics across nine titles at 100% coverage**, recording every slot
* written by set.string / get.string / word.to.string and every slot read by %s<n>: the highest
* index any title touches is **12**, so 13 slots suffice. PoliceQuest1 and larry1 are the two that
* reach it; five titles never exceed slot 6.
* ★★★ THE RESIDUAL RISK IS STATED RATHER THAN HIDDEN: 13 is a corpus maximum, not a bound. A title
* outside the nine could use more, and the oracle's own bound is 25. MAP_STR_SLOTS is one constant
* and the assertion below moves with it.
*
* ★★ The tail is $0DC0-$1000 = 576 B and this uses 572 of it: 520 table + 42 input line + 10 of
* edit state. **Four bytes spare, and the assertion is what makes that safe to say.**
MAP_STR_SLOTS   equ     13              ; measured; agi.h's own bound is 25
MAP_STR_LEN     equ     40              ; agi.h MAX_STRINGLEN
MAP_STRINGS     equ     $0DC0           ;   13 x 40 = 520 B
MAP_INPUTSTR    equ     $0FC8           ;   _inputString[42], text.h at the pin
MAP_VMSTATE_END equ     $1000
* ★★★ THE TEN EDIT SCALARS ARE **NOT** HERE, AND THE FIRST DRAFT OF THIS BLOCK SAID THEY WERE.
* getstring.s keeps them inline with its code, as text.s keeps its own: reaching them through a
* MAP_ address costs indexed addressing on every touch to save ten bytes in a region that had 387.
* ★★ Declaring an address the engine does not use is a §2F violation with no symptom -- the map
* says one thing and the code does another, and nothing ever disagrees out loud. Removed rather
* than left as documentation of a decision that was not taken.
* ★ That leaves 14 bytes spare at $0FF2-$1000.
                ifgt    MAP_STRINGS+MAP_STR_SLOTS*MAP_STR_LEN-MAP_INPUTSTR
                error   "string table overruns the input line buffer -- MAP_STR_SLOTS too large"
                endc
                ifgt    MAP_INPUTSTR+42-MAP_VMSTATE_END
                error   "input line buffer overruns the DIR tables"
                endc
                ifgt    MAP_VM_OBJ+16*42-MAP_STRINGS
                error   "screen objects overrun the string table"
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════
MAP_DIRS        equ     $1000           ; the game's own DIR tables -- THE resource index
MAP_DIR_STRIDE  equ     $0400           ;   1 KB per type: 341 slots vs 216 present max
MAP_DIRS_END    equ     $2000           ;   4 types x 1 KB = 4,096 B
* ★★★ §2F.3: THE RESOURCE MAP IS THE GAME'S OWN DIR TABLES. There is no second index. The
* arena's occupancy is tracked in MAP_STATUS, not by building a parallel directory.

* ── slots 1-2: engine code, always resident ──────────────────────────────────────
MAP_CODE        equ     $2000
* ★★★★ BOUNDARY MOVED $5000 -> $5100 BY T-P0-034, AND THE REASON IS RECORDED BECAUSE IT COSTS
* THE PARSER/SOUND RESERVATION 256 BYTES. The packed span walk (pic_fill.s's FC_PRIORITY loop)
* made the P3b image **12,299 bytes against a 12,288 region -- over by ELEVEN.** One page moves
* it: code 12,544 with 245 spare, reservation 4,096 -> 3,840.
* ★★★ P6.1 §7.4 flagged the 4 KB as "a residual, not a requirement... to be CHECKED against the
* parser and sound when they exist", so spending 256 of it is sanctioned rather than silent --
* **but it is a reservation AC-3 required, and shrinking one is exactly the kind of change that
* should never happen inside another task's diff without being said out loud.**
* ★ Both slots stay in slot 2; the PHASE total is unchanged, so AC-2's fit figure does not move.
* ★★★★ SECOND REDUCTION IN THREE TASKS, AND THE TREND IS THE FINDING RATHER THAN THIS BYTE COUNT.
*     P6.1      reserved 4,096 for parser + sound
*     T-P0-034  packed span walk      -> $5100, reservation 3,840   (-256)
*     T-P0-036  LOGIC cache, +352 B   -> $5200, reservation 3,584   (-256)
* ★★★ Each step was individually small, individually justified, and made by a task that was not
* about the parser. **Nothing in the map objects to this happening again**, and the reservation
* has now lost 12.5% without the parser existing to argue for itself.
* ★★ P6.1 §7.4 called the 4 KB "a residual, not a requirement... to be CHECKED against the parser
* and sound when they exist" -- which sanctions the spending and is exactly why the trend needs
* a reader, not just a changelog line.
* ★★★★ THIRD REDUCTION, AND THIS ONE COMES WITH THE FLOOR THE LAST REPORT ASKED FOR.
*     P6.1      reserved                                   4,096
*     T-P0-034  packed span walk,  over by  11  -> $5100   3,840
*     T-P0-036  LOGIC cache,       over by 107  -> $5200   3,584
*     T-P0-037  the P3b cycle glue,over by 225  -> $5300   3,328
* ★★★ T-P0-036 §8.4 recommended "a stated floor and an owner before it is reduced a third
* time". This is the third time, so the floor lands with it rather than after it.
* ★★★★ A FOURTH REDUCTION WAS TAKEN AND THEN GIVEN BACK. Adding halt detection needed 7 more
* bytes; the floor assertion refused the build, I moved the boundary to $5400 deliberately, and
* the resulting run was worse in every respect (stack wild, status block scribbled). **So the
* 7 bytes bought nothing and the reservation was restored.**
* ★★★ Recorded because the useful part is that the floor worked: it turned a slide into a
* decision, and the decision was reversible because it had been made explicitly rather than
* absorbed. The reservation stands at 3,328 with 256 bytes above the floor.
* ★★★ 13,056 B. The P3b glue measured 12,782 at T-P0-042 (windowed, PRI_PACKED), leaving 274.
* ★★★★ THE COMMENT HERE SAID "13,041" AND WAS STALE BY 61 BYTES [AD-95] -- p3b_probe.s had not
* assembled for some time and the figure it quoted was from a build nobody could reproduce. **A
* number in a comment has no producer**, which is the same defect class as the cel gate's 6,782
* and gates.manifest's flag set. ★★ It is kept here only as orientation; **the check that matters
* is p3b_probe.s's own `ifgt P3_CODE_END-MAP_CODE_END`, which fires at assembly time** and is
* what caught the overrun [AD-78's precedent: an assertion, not a table a human reads].
MAP_CODE_END    equ     $5300
MAP_RESERVED    equ     $5300
MAP_RESERVED_END equ    $6000           ; 3,328 B, parser + sound (floor 3,072)
* ★★★★ THE FLOOR IS DELIBERATELY ARBITRARY AND THAT IS ITS VALUE. Nobody has estimated the
* parser or sound, so any number here would be invented -- **the point is not to model them but
* to make the next reduction impossible to take silently.** A fourth bite now fails the build
* and forces someone to either raise a real estimate or lower this line on purpose.
* ★★ Without it the only check is that the regions do not overlap, which stays true as the
* boundary slides -- which is exactly how 12.5% went in three tasks with every step justified.
MAP_RESERVED_MIN equ    3072            ; 3 KB. See above: a tripwire, not an estimate.
                ifgt    MAP_RESERVED_MIN-(MAP_RESERVED_END-MAP_RESERVED)
                error   "parser/sound reservation is below MAP_RESERVED_MIN -- raise a real estimate or lower the floor DELIBERATELY, do not slide the boundary again"
                endc

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

* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★★★ AND IN THE VM PHASE THIS SLOT HOLDS THE VOCABULARY [T-P0-060 AC-6].
*
* ★★★★ THE MEASUREMENT DECIDES IT, AND IT IS SETTLED: the largest WORDS.TOK in the twelve-title
* corpus is **SpaceQuest-2 at 6,828 bytes** [T-P0-059 §3.E, re-measured independently], with
* PQ1 6,737, larry1 6,597, GoldRush 6,110, KQ3 5,657, SQ1 4,793, KQ2 3,516, KQ1 3,144 and four
* under 300. **All twelve fit one 8,192 B window with 1,364 B of headroom on the largest.**
* Unlike AD-78's arena, where the largest LOGIC exceeded a window and forced two slots, this
* needs ONE -- and the slot is the one the phase table above already leaves idle.
*
* ★★★★★ WHY SLOT 5 AND NOT SLOT 6. Slot 6 is the volume window in the VM phase, and a resource
* FETCH happens in the VM phase -- so a vocabulary there would collide with the thing it shares
* the phase with. Slot 5 is "-- nothing mapped --" for the whole VM phase (see the table at the
* head of this file) and becomes the priority slice only in a DRAW phase. §3.4's disjointness is
* exactly what makes this legal, and it is the second place in this map where that property is
* load-bearing rather than incidental.
*
* ★★★★ ONLY par_parse NEEDS IT MAPPED, NOT par_said, AND THAT IS A REAL NARROWING. par_said
* reads par_ego, par_egon and the operand stream; it never touches par_vocab [src/engine/
* parser.s]. So the window is required only while a line is being TOKENISED -- once per typed
* command -- and not on any of the said() evaluations that follow it. A game evaluating fifteen
* said() patterns a cycle needs the vocabulary mapped for none of them.
*
* ★★★ THE PARSER'S CODE AND STATE ARE NOT HERE. They are 954 B in MAP_RESERVED (870 code+state
* plus two 42-byte input buffers); this is the RESOURCE, and §2P/§2V.2 put a resource in a
* window rather than in the image.
* ★★ THE HARNESS DOES NOT USE THIS ADDRESS AND MUST NOT BE READ AS DOING SO. p3b_probe.s stages
* its vocabulary at $E3BA because slot 5 is that probe's PRIORITY slice, live in every draw
* phase, and vm_probe.s uses $E000 for its own map's reasons. Per this file's header the harness
* keeps its own addresses; **this line is the ENGINE's decision and the probes are evidence for
* it, not instances of it.**
MAP_VOCAB       equ     MAP_PRI_SLICE   ; VM phase only: WORDS.TOK, read in place
MAP_VOCAB_E     equ     MAP_PRI_SLICE_E ; 8,192 B >= 6,828 (SpaceQuest-2, the corpus max)
                ifgt    6828-(MAP_VOCAB_E-MAP_VOCAB)
                error   "the vocabulary window is smaller than the largest corpus WORDS.TOK (6,828 B)"
                endc

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
* ★★★★★ 768, AND THE ASSERTION IS WHY THE SIZE CHANGE WAS SAFE TO MAKE [P6.13]. Resizing the
* region above without this line would have been a silent edit; instead p3b_probe.s refused to
* assemble and named the constant. **That is the mechanism working exactly as its header claims**
* -- and it caught the change within a minute of my making it, where P6.11's code-region overrun
* went a whole task unnoticed because nobody ran the build that asserts.
* ★★★ The bound is the MEASURED peak with headroom, not a round number: 37 entries / 74 bytes is
* the high-water mark across the renderer gate's 45 pictures, the P2 fill study's offline
* prediction of worst-case demand is 102 entries / 204 bytes, and 384 entries is 3.8x that model
* and 10.4x the sample. pic_probe.s asserts its own margin separately.
                ifgt    MAP_SEEDSTACK+768-MAP_SEEDSTACK_E
                error   "seed stack is not 768 B -- see the sizing note at MAP_SEEDSTACK"
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
* ★★★★★ AC-2: REACHING, NOT FITTING [L-69]. Every assertion above is about SPACE -- do the
* regions overlap, does the plane fit the block budget. **None of them asks whether the plane
* can be ADDRESSED**, and that is the defect this task exists to close:
*
*     visual    26,880 B into an 8,192 B window: $C000 + 26,879 = $128FF, wrapping to $28FF,
*               inside the code region $2000-$5300 -- the renderer overwrites its own code
*     priority  13,440 B into an 8,192 B slice: $A000 + 13,439 = $D47F, running THROUGH $C000,
*               which is the framebuffer slice
*
* ★★★★ The visual overrun is in the dispatch. **The priority one is not, and it is quieter**:
* it does not wrap into code, it writes priority bytes over the framebuffer, so it presents as a
* wrong picture rather than a crash.
*
* ★★★ THE ASSERTION IS THE DELIVERABLE, NOT THE ARITHMETIC. A build that addresses a plane
* FLAT must have a plane that fits its window, or it does not assemble. A build that defines
* PLANE_WINDOWED reaches every byte through plane_vis / plane_pri, which mask the offset to
* PLANE_SLICE_MSK -- so being inside the window is STRUCTURAL there, guaranteed by the mask
* rather than checked by a sum. **That is why this asserts on the flat case only: the windowed
* case cannot violate it.**
* ★★ Precedent AD-78: an overlap claim checked by a human reading a table is the state these
* assertions exist to end -- four probes each had a coherent table and two of them overlapped.
                ifndef  PLANE_WINDOWED
                ifgt    MAP_VIS_BYTES-(MAP_PHASE_WIN_E-MAP_PHASE_WIN)
                error   "visual plane cannot be REACHED flat: it exceeds MAP_PHASE_WIN. Define PLANE_WINDOWED."
                endc
                ifgt    MAP_PRI_BYTES-(MAP_PRI_SLICE_E-MAP_PRI_SLICE)
                error   "priority plane cannot be REACHED flat: it exceeds MAP_PRI_SLICE. Define PLANE_WINDOWED."
                endc
                endc
* ═══════════════════════════════════════════════════════════════════════════════════════════

                endc
