* src/harness/vm_state.s -- the VM's state layout and the accessors every handler goes through.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ THE LAYOUT CHANGED FROM P4.3 AND THE REASON IS A MEASUREMENT, NOT A PREFERENCE.
*
* 1. P4.3 sized the object table at 16 entries. state.py says SCREENOBJECTS_MAX = 255 with the
*    comment "KQ3 uses o255". Sixteen entries would have let KQ3 write object 255 into the
*    LOGIC buffer and the diff would have reported a bytecode corruption whose cause is a
*    table bound. 255 entries it is.
*
* 2. ★★★ THE VM INTERPRETS DIRECTLY OUT OF P1.3's ARENA, and does not keep a LOGIC buffer of
*    its own. cmdCall does res_open(LOGIC, n), interprets at res_base, then res_close -- so
*    THE RESIDENCY STACK IS THE LOGIC CALL STACK. That is what P1.3's arena was measured for:
*    working set 4,679-8,537 bytes at call depth 2-3, against a 12 KB arena. Keeping a separate
*    10 KB VM_CODE buffer would have duplicated the arena and broken nesting, because a nested
*    call would have overwritten its caller's code.
*
* ★ Addresses avoid res_core.s's map: RES_DIRS $2000-$2FFF and RES_ARENA $3000-$5FFF are the
* resource layer's, so the VM starts above them.
*
* ═══════════════════════════════════════════════════════════════════════════════════════════
* ★★★ 3. THE STATE BLOCK MOVED DOWN TO $4000 SO THE ARENA COULD GROW, AND THE MEASUREMENT THAT
*    SIZED THE OLD ARENA WAS TAKEN ON A RUN THAT NEVER NESTED.
*
* "Working set 4,679-8,537 bytes at call depth 2-3, against a 12 KB arena" (point 2 above) was
* measured while vm_run_logic still had the arg-count clobber: logic 0 "returned" at ip 3893,
* three instructions before its `call`, so THE NESTED CALL NEVER EXECUTED and the depth-2
* figure came from somewhere shallower than the real thing. With the clobber fixed, KQ1 cycle 0
* holds logic 0 (an 8,999-byte RESOURCE, not its 3,904 bytes of bytecode) open across a call to
* logic 102 (3,817) = **12,816 bytes against 12,288**, and res_open returned RES_E_FULL.
*
* ★★ §2H in its own words: the first mechanism found was real and was not the governing one.
* ★ And the resource is not the bytecode -- a LOGIC resource carries its text section too, so
* sizing an arena from `len(bytecode)` under-counts logic 0 by 5,095 bytes.
*
* THE MAP, and why each thing is where it is:
*   $0700  code                           ★ ends $2A3B and GREW INTO THE TABLES -- see below
*   $3000  RES_DIRS      guest
*   $4000  VM_VARS/FLAGS/CTRL/OBJROOMS/VM_OBJ   host-read -- ends $6220
*   $6300  VM_TESTSEEN   host-read        \   AC-5, the TEST opcode space
*   $6400  VM_OPSEEN     host-read         |  AC-5, the COMMAND opcode space
*   $6500  vmtr_buf      host-read        /   384 x 4 bytes, trace builds only
*   $6B00  RES_ARENA     guest only       ★ 21 KB; resource bytes, which the host never reads
*   $C000  volume window guest            ★ res_core maps VOL blocks here; the arena stops short
*
* ★★★ THE TABLES MOVED OUT OF $2800-$2AFF BECAUSE THE CODE GREW INTO THEM. VM_OPSEEN sat at
* $2900 and vmtr_buf at $2A00, chosen when the image ended near $27C0; adding the test counter
* pushed it to $2A3B and **the interpreter was incrementing counters inside its own code image**.
* The tell was AC-5 reporting 247 distinct TEST opcodes when only 18 exist -- the table was
* reading code bytes.
* ★★ The layout assertion in vm_probe.s checked VM_CODE_END against RES_DIRS ($3000) and nothing
* else, so it was true and useless: the collision was 1.5 KB BELOW the boundary it guarded.
* **An assertion that names one of four neighbours reports conformance for the other three.**
* vm_probe.s now asserts every adjacency in this map.
* ★ They live above VM_OBJ rather than below the code because that space is bounded by the arena
* rather than by a binary that grows every task.
* ═══════════════════════════════════════════════════════════════════════════════════════════

VM_VARS         equ     $4000           ; 256 bytes -- HALF THE DIFF
VM_FLAGS        equ     $4100           ; 32 bytes, packed LSB-first -- THE OTHER HALF
VM_CTRL         equ     $4120           ; 32 bytes, packed: controller_occurred
VM_OBJROOMS     equ     $4140           ; 256 bytes: the OBJECT file's object -> room table
VM_OBJ          equ     $4240           ; 255 entries x 32 bytes
VM_OBJ_MAX      equ     255
VM_OBJ_END      equ     VM_OBJ+VM_OBJ_MAX*32            ; $6220 -- 255 x 32 from $4240

* ★★ AC-5 COVERAGE: one byte per command opcode, incremented on dispatch. Above VM_OBJ, which
* ends at $9220 -- NOT $9200, an arithmetic slip that cost a debugging session when a trace
* buffer was placed there and the object table wrote through it.
VM_OPSEEN       equ     $6400           ; 256 bytes: executions per COMMAND opcode
* ★ The TEST opcode space is separate and needs its own table -- see vm_core.s. $2800 is free:
* the code image ends below $2800 and VM_OPSEEN starts at $2900.
VM_TESTSEEN     equ     $6300           ; 256 bytes: executions per TEST opcode
*
* ★★ IT LIVES BELOW $8000, AND THE REASON RECORDED HERE WAS WRONG FOR TWO TASKS.
*
* The original text said: "MAME's CPU program space does not reflect the GIME MMU above $8000 --
* a host write of $A5 to $9300 reads back as a fixed unrelated byte". The READBACK was real; the
* MECHANISM was not. **$8000-$FEFF was still ROM**, because HAL_sys_init does not enable all-RAM
* mode -- sys.s:118-128 says so explicitly, and vm_probe.s now writes $FFDF itself. Nobody's
* write stuck up there, host or guest.
*
* ★★★ WHAT ACTUALLY CONSTRAINS THE LAYOUT NOW: everything the HOST reads per cycle -- VM_VARS,
* VM_FLAGS, and the object table the watch reads -- sits below the arena for locality, and the
* arena takes the rest. That is a choice, not a limit. ★ A coverage table at $9300 did read back
* as near-uniform values in the 237-255 range and did imply a 175x runaway that was not
* happening; the false conclusion drawn from a true observation is the part worth remembering.
* ★ The instrument that settles this class is guest-side: vm_probe.s's arena self-test writes a
* walking pattern and reads it back ITSELF. A host readback cannot tell "MAME cannot see it"
* from "it is not RAM".

* ── per-object fields ─────────────────────────────────────────────────────────────
* ★ Every field state.py's ScreenObj carries that any EXECUTED opcode reads or writes.
* ★★ flags is 16 BITS: fAdjEgoXY is bit 15. An 8-bit flags field would silently drop
* fOnWater/fIgnoreObjects/fUpdatePos/fOnLand/fDontUpdate/fFixLoop and half the handlers.
VMO_X           equ     0
VMO_Y           equ     1
VMO_XSIZE       equ     2
VMO_YSIZE       equ     3
VMO_VIEW        equ     4
VMO_LOOP        equ     5
VMO_CEL         equ     6
VMO_NUMLOOPS    equ     7
VMO_NUMCELS     equ     8
VMO_PRIORITY    equ     9
VMO_FLAGS       equ     10              ; 2 bytes, big-endian in memory
VMO_DIR         equ     12
VMO_STEPSIZE    equ     13
VMO_STEPTIME    equ     14
VMO_STEPTIMECNT equ     15
VMO_CYCLETIME   equ     16
VMO_CYCLETIMECNT equ    17
VMO_CYCLE       equ     18
VMO_MOTION      equ     19
VMO_LOOPFLAG    equ     20
VMO_IGNLOOPFLAG equ     21
VMO_WANDERCNT   equ     22
VMO_FOLLOWCNT   equ     23
VMO_FOLLOWSTEP  equ     24
VMO_FOLLOWFLAG  equ     25
VMO_MOVEX       equ     26
VMO_MOVEY       equ     27
VMO_MOVESTEP    equ     28
VMO_MOVEFLAG    equ     29
VMO_SIZE        equ     32
* ── constants: ALIASES ONLY. The values live in the GENERATED vm_tables.s ────────
*
* ★★★ THEY WERE TYPED HERE AND TWO WERE WRONG. VAR_MAX_INPUT_CHARS was 53 (it is 24) and
* kAgiSoundPC was 0 (it is 1). Neither raises -- they write the wrong variable, and the state
* diff reported it as "var 24 oracle=38 guest=0; var 53 oracle=0 guest=38" at cycle 0.
* ★★ state.py records the SAME failure one layer up: "the first draft typed them from memory and
* got four VM_VAR/VM_FLAG names or values wrong and the ENTIRE ViewFlags bit assignment wrong."
* L-29 twice in one project, so gen_vm_tables.py now emits every one of them from optable.py
* and this file only shortens the names.
*
* ★ ViewFlag bits, kCycle*, kMotion*, VM_VAR_* and VM_FLAG_* are all generated; nothing below
* introduces a value.
VAR_CURRENT_ROOM        equ     VM_VAR_CURRENT_ROOM
VAR_PREVIOUS_ROOM       equ     VM_VAR_PREVIOUS_ROOM
VAR_BORDER_TOUCH_EGO    equ     VM_VAR_BORDER_TOUCH_EGO
VAR_BORDER_CODE         equ     VM_VAR_BORDER_CODE
VAR_BORDER_TOUCH_OBJECT equ     VM_VAR_BORDER_TOUCH_OBJECT
VAR_EGO_DIRECTION       equ     VM_VAR_EGO_DIRECTION
VAR_FREE_PAGES          equ     VM_VAR_FREE_PAGES
VAR_WORD_NOT_FOUND      equ     VM_VAR_WORD_NOT_FOUND
VAR_TIME_DELAY          equ     VM_VAR_TIME_DELAY
VAR_SECONDS             equ     VM_VAR_SECONDS
VAR_MINUTES             equ     VM_VAR_MINUTES
VAR_HOURS               equ     VM_VAR_HOURS
VAR_DAYS                equ     VM_VAR_DAYS
VAR_EGO_VIEW_RESOURCE   equ     VM_VAR_EGO_VIEW_RESOURCE
VAR_KEY                 equ     VM_VAR_KEY
VAR_COMPUTER            equ     VM_VAR_COMPUTER
VAR_SOUNDGENERATOR      equ     VM_VAR_SOUNDGENERATOR
VAR_MONITOR             equ     VM_VAR_MONITOR
VAR_MAX_INPUT_CHARS     equ     VM_VAR_MAX_INPUT_CHARACTERS

FLAG_ENTERED_CLI        equ     VM_FLAG_ENTERED_CLI
FLAG_SAID_ACCEPTED      equ     VM_FLAG_SAID_ACCEPTED_INPUT
FLAG_NEW_ROOM_EXEC      equ     VM_FLAG_NEW_ROOM_EXEC
FLAG_RESTART_GAME       equ     VM_FLAG_RESTART_GAME
FLAG_SOUND_ON           equ     VM_FLAG_SOUND_ON
FLAG_LOGIC_ZERO_FIRST   equ     VM_FLAG_LOGIC_ZERO_FIRST_TIME
FLAG_RESTORE_JUST_RAN   equ     VM_FLAG_RESTORE_JUST_RAN

* ★★ HIGH-BYTE ALIASES. fUpdatePos, fDontUpdate and fFixLoop live above bit 7, so `bitb` on the
* low byte cannot see them. These are DERIVED from the generated masks, not retyped.
fUpdatePos_H    equ     fUpdatePos/256
fDontUpdate_H   equ     fDontUpdate/256
fFixLoop_H      equ     fFixLoop/256
fDidntMove_H    equ     fDidntMove/256          ; ★ $4000 -> $40; motion_wander and follow.ego test it


* ═══════════════════════════════════════════════════════════════════════════════════════════
* ── accessors ──────────────────────────────────────────────────────────────────────
* ★★ EVERY handler goes through these. The alternative -- inline `ldx #VM_VARS; lda a,x` at
* sixty sites -- is sixty places for the layout to be wrong, and P1.3's stale-symbol incident
* is the same shape of defect one layer up.
* ═══════════════════════════════════════════════════════════════════════════════════════════

* vm_getvar: A = var number -> A = value.  ★ NO timer side effect here; see vm_get_timer_var.
vm_getvar:
                ldx     #VM_VARS
                pshs    b
                tfr     a,b
                clra
                leax    d,x                     ; ★ UNSIGNED; vars 128-255 are half
                lda     ,x                      ;   the array the AC-2 diff compares
                puls    b,pc

* vm_setvar: A = var number, B = value
vm_setvar:
                ldx     #VM_VARS
                pshs    b
                tfr     a,b
                clra
                leax    d,x                     ; ★ UNSIGNED
                puls    b
                stb     ,x
                rts

* ★★ get_var on a TIMER variable ticks the clock in the reference [cycle.py get_var]. The
* interpreter's own reads of vars 11-14 must therefore go through vm_get_timer_var, and the
* handlers' reads must NOT -- because cycle.py's get_var is called from both and the timer
* update is idempotent within a cycle. Reproduced by calling timer_update once per outer
* iteration (vm_run.s) rather than per read, which is equivalent because virtual_ms only
* advances there.

* vm_getflag: A = flag number -> A = 0 or 1, Z set when clear
vm_getflag:
                pshs    b
                tfr     a,b
                andb    #7
                lsra
                lsra
                lsra
                ldx     #VM_FLAGS
                lda     a,x
                pshs    a
                lda     #1
vm_gf_sh:       tstb
                beq     vm_gf_got
                asla
                decb
                bra     vm_gf_sh
vm_gf_got:      anda    ,s+
                beq     vm_gf_out
                lda     #1
vm_gf_out:      tsta
                puls    b,pc

* vm_setflag: A = flag number, B = 0 (clear) or non-zero (set)
vm_setflag:
                pshs    a,b
                tfr     a,b
                andb    #7
                lsra
                lsra
                lsra
                ldx     #VM_FLAGS
                leax    a,x                     ; X -> the byte
                lda     #1
vm_sf_sh:       tstb
                beq     vm_sf_got
                asla
                decb
                bra     vm_sf_sh
vm_sf_got:      ldb     1,s                     ; the requested value
                bne     vm_sf_set
                coma
                anda    ,x
                sta     ,x
                puls    a,b,pc
vm_sf_set:      ora     ,x
                sta     ,x
                puls    a,b,pc

* vm_ctrl_get: A = controller number -> A = 0 or 1  (same packing as flags)
vm_ctrl_get:
                pshs    b
                tfr     a,b
                andb    #7
                lsra
                lsra
                lsra
                ldx     #VM_CTRL
                lda     a,x
                pshs    a
                lda     #1
vm_cg_sh:       tstb
                beq     vm_cg_got
                asla
                decb
                bra     vm_cg_sh
vm_cg_got:      anda    ,s+
                beq     vm_cg_out
                lda     #1
vm_cg_out:      tsta
                puls    b,pc

* vm_obj: A = object number -> X = its record.  ★ CLAMPED, not wrapped: an out-of-range object
* number is a desynchronised stream, and wrapping would write a real object's fields.
* ★ DESTROYS D. Callers that still need the object number keep their own copy.
vm_obj:
                cmpa    #VM_OBJ_MAX
                blo     vm_obj_ok
                lda     #VM_OBJ_MAX-1
vm_obj_ok:
                tfr     a,b
                clra                            ; D = object number, zero-extended
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola                            ; D = objnum * 32  (VMO_SIZE)
                ldx     #VM_OBJ
                leax    d,x
                rts

* vm_objflags_set / _clr: X -> object, D = mask
vm_objflags_set:
                pshs    d
                ldd     VMO_FLAGS,x
                ora     ,s
                orb     1,s
                std     VMO_FLAGS,x
                puls    d,pc
vm_objflags_clr:
                pshs    d
                lda     ,s
                coma
                ldb     1,s
                comb
                anda    VMO_FLAGS,x
                andb    VMO_FLAGS+1,x
                std     VMO_FLAGS,x
                puls    d,pc
