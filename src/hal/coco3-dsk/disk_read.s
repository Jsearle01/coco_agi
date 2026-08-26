* src/hal/coco3-dsk/disk_read.s
*
* HALT-based double-density single-sector READ primitive.
* Implements design docs/project/disk-read-primitive-design.md (011863c).
*
* SHARED SOURCE: `include`d by the disk-read sandbox harness (this build) and,
*   later, by the boot stage-1 loader and the resident game image, each linked
*   at its own load address (no PIC). This build is its FIRST client.
*
* Mechanism (branch b, settled a91d080): DSKREG b7=1 wires the WD1773 DRQ to the
*   6809 HALT line, so the data-register read blocks in hardware until each byte
*   is ready — no poll, no timing margin (the CPU cannot outrun the disk). INTRQ
*   (end-of-command) fires NMI AND auto-clears HALT b7 (Unravelled §FDC line 398).
*
* Interface (RAM params, set by caller before `jsr disk_read`):
*   dr_track  (1)  target track  0..34
*   dr_sector (1)  target sector 1..18
*   dr_dest   (2)  destination buffer pointer (256 bytes written)
* Returns:
*   dr_status (1)  final WD1773 status byte
*   CC.C           set on error (RNF b4 | CRC b3 | Lost-Data b2), clear on OK
*   dr_nmi_done    non-zero iff INTRQ->NMI reached our handler (mechanism proof)
* Clobbers: A, B, X, Y. Assumes caller masked IRQ/FIRQ (NMI stays enabled) and
*   called disk_read_init once (installs the NMI vector + handler).
*
* HS-2 design-refinements (flagged, not silent divergence):
*   (1) DSKREG b7 (HALT) is armed ONLY for the Type II Read transfer, NOT during
*       Type I Restore/Seek — Type I generates no DRQ, so b7=1 during positioning
*       would halt the CPU until INTRQ. Positioning uses b7=0 + Busy-poll (the
*       design's "wait Busy-clear" step).
*   (2) Transfer loop is count-bounded (256) — the design's named safety-bound
*       option — rather than purely NMI-terminated; robust because INTRQ clears
*       HALT to free the final store. NMI is retained as the completion SIGNAL
*       (handler sets dr_nmi_done) proving the mechanism engaged.
* ---------------------------------------------------------------

* --- WD1773 / DSKREG registers (addresses: DECB Unravelled; fn: WD1773 dsheet) ---
DSKREG      equ $FF40        ; control latch (write-only)
FDC_CMDST   equ $FF48        ; write=Command, read=Status
FDC_TRACK   equ $FF49
FDC_SECTOR  equ $FF4A
FDC_DATA    equ $FF4B

* --- DSKREG bit fields (Unravelled §$FF40) ---
DSK_DRV0    equ $01          ; drive select 0 (b0)
DSK_MOTOR   equ $08          ; motor enable  (b3)
DSK_DD      equ $20          ; density=double (b5)
DSK_HALT    equ $80          ; HALT enable   (b7)
DSK_POS     equ DSK_DRV0+DSK_MOTOR+DSK_DD          ; $29 positioning (no HALT)
DSK_XFER    equ DSK_DRV0+DSK_MOTOR+DSK_DD+DSK_HALT ; $A9 transfer (HALT armed)

* --- WD1773 commands (WD1773 datasheet Type I / Type II) ---
FDC_RESTORE equ $00          ; Restore, no verify, 6ms rate
FDC_SEEK    equ $10          ; Seek,    no verify, 6ms rate
FDC_READ    equ $80          ; Read Sector, single (m=0), side0, no side-compare
FDC_READ_M  equ $90          ; Read Sector, MULTIPLE (m=1, bit4) — whole-track
FDC_FORCEINT equ $D0         ; Force Interrupt (terminates a multiple-record read)
FDC_ERRMASK equ $1C          ; RNF(b4)|CRC(b3)|Lost-Data(b2) — single-sector read
FDC_ERRMASK_M equ $0C        ; CRC(b3)|Lost-Data(b2) only — whole-track m=1: the
                             ; trailing RNF (sector reg > track) is the EXPECTED
                             ; end-of-track terminator (datasheet), not an error
SECS_TRACK  equ 18           ; sectors per track (RSDOS DD)
MAX_TRACK   equ 35           ; valid tracks 0..34 (a standard 35-track disk); a
                             ; range Seek to track >= MAX_TRACK is off-end -> error

* --- caller-set parameters (primitive-owned scratch block) ---
* Relocated off $0170-$0176: that range is DECB/BASIC low-RAM (ROM writes there
* during boot — trace-confirmed in the $0100-verify). $2100 is DECB-clear in the
* sandbox's high working region (above the $01xx vector/BASIC-var page, above the
* $2000 buffer). A real client may re-point this block; the primitive owns it.
* Variable base is overridable (-D DR_VARBASE=...) so a client whose load region
* covers the default $2100 (e.g. the boot loader placing the game at $0100-$48FF)
* can relocate these 7 RAM bytes clear of its load. Default $2100 = the sandbox.
    ifndef DR_VARBASE
DR_VARBASE  equ $2100
    endif
dr_track    equ DR_VARBASE+0 ; target track  0..34 (also: current track in a range)
dr_sector   equ DR_VARBASE+1 ; target sector 1..18
dr_dest     equ DR_VARBASE+2 ; destination pointer (2 bytes)
dr_status   equ DR_VARBASE+4 ; final WD1773 status byte
dr_r_track  equ DR_VARBASE+5 ; range: start track
dr_r_count  equ DR_VARBASE+6 ; range: sector count remaining (multiple of SECS_TRACK)

* --- NMI landing in the constant Vector Page ($FE00-$FEED, safe siting) ---
dr_nmi_done equ $FE00        ; completion flag (1 byte, below secondary vectors)
* --- DEVICE STATE (P3.76). The driver's first byte of "what is already true of the
* --- hardware", sited in the constant page beside dr_nmi_done for the same reason:
* --- MC3=1 pins $FE00-$FEFF, so it survives every MMU remap the caller performs.
* --- $FE01-$FE1F is free (handler at $FE20, vector at $FEFD).
dr_motor_on equ $FE01        ; 1 = the motor is already turning, no spin-up owed
DR_NMI_HDLR equ $FE20        ; our NMI handler (installed by disk_read_init)
DR_NMI_VEC  equ $FEFD        ; NMI secondary vector ($FFFC[ROM]->$FEFD->handler)

* ---------------------------------------------------------------
* OBJECT-TARGET WRAPPER (P3.4). INERT unless OBJTARGET is defined.
*
* This file was written as a plain `include` for an ABSOLUTE build -- karateka's
* bootloader.s pulls it in under `org $8000`. POP's kernel is a LINKED object
* (P2.4), so it needs the file to open `section code` and export its entry
* points. Both builds are served from one source by the same guard pattern
* HAL_gfx_set_mode uses: karateka does not define OBJTARGET here, so every
* directive below vanishes and its binary is byte-identical.
*
* Only the three ENTRY POINTS are exported. The dr_* parameters are absolute `equ`
* symbols, and lwasm's `export` carries labels, not absolutes -- linking against
* them fails with "External symbol dr_status not found". A client therefore
* derives them from DR_VARBASE exactly as this file does, and the build passes the
* SAME -DDR_VARBASE to both assemblies so the two cannot drift apart.
* ---------------------------------------------------------------
        ifdef   OBJTARGET
        section code
        export  disk_read_init
        export  disk_read
        export  disk_read_range
        export  disk_read_motor_off
        endc

* ---------------------------------------------------------------
* disk_read_init — install our NMI vector + handler in the constant page.
*   Call ONCE after the GIME is in MC3=1 (constant $FExx). M1 lesson: our own
*   vector, sited above the game load ($4823) and the framebuffer loader ($FBFF).
* ---------------------------------------------------------------
disk_read_init:
        * handler at $FE20:  INC dr_nmi_done ; RTI
        lda     #$7C                 ; INC (extended) opcode
        sta     DR_NMI_HDLR
        ldd     #dr_nmi_done
        std     DR_NMI_HDLR+1
        lda     #$3B                 ; RTI
        sta     DR_NMI_HDLR+3
        * vector at $FEFD:  JMP DR_NMI_HDLR
        lda     #$7E                 ; JMP (extended) opcode
        sta     DR_NMI_VEC
        ldd     #DR_NMI_HDLR
        std     DR_NMI_VEC+1
        clr     dr_nmi_done
        clr     dr_motor_on          ; the drive is stopped at init (P3.76)
        rts

* ---------------------------------------------------------------
* disk_read — read dr_track/dr_sector (256 bytes) into (dr_dest) via HALT.
* ---------------------------------------------------------------
disk_read:
        * --- positioning config: drive0 + motor + DD, HALT OFF ---
        lda     #DSK_POS
        sta     DSKREG
        jsr     dr_spinup            ; motor spin-up settle (real HW ~0.5-1s)

        * --- Restore to track 0 ---
        lda     #FDC_RESTORE
        sta     FDC_CMDST
        jsr     dr_settle            ; let Busy assert before polling
        jsr     dr_wait_notbusy

        * --- Seek to target track ---
        lda     dr_track
        sta     FDC_DATA             ; desired track -> Data reg
        lda     #FDC_SEEK
        sta     FDC_CMDST
        jsr     dr_settle
        jsr     dr_wait_notbusy

        * --- select sector ---
        lda     dr_sector
        sta     FDC_SECTOR

        clr     dr_nmi_done          ; arm completion detector
        ldx     dr_dest              ; destination

        * --- issue Read Sector (HALT still OFF), THEN arm HALT ---
        lda     #FDC_READ
        sta     FDC_CMDST
        lda     #DSK_XFER            ; b7=1: DRQ now gates HALT
        sta     DSKREG

        * --- HALT-paced, count-bounded transfer (256 bytes) ---
        ldy     #256
dr_xfer:
        lda     FDC_DATA             ; HALT holds CPU here until DRQ (byte ready)
        sta     ,x+
        leay    -1,y
        bne     dr_xfer
        * INTRQ at end-of-sector cleared HALT b7 + fired NMI (dr_nmi_done set).

        * --- disarm HALT, read final status ---
        lda     #DSK_POS
        sta     DSKREG
        lda     FDC_CMDST
        sta     dr_status
        anda    #FDC_ERRMASK
        bne     dr_err
        andcc   #$FE                 ; C clear = OK
        rts
dr_err:
        orcc    #$01                 ; C set = error
        rts

* ---------------------------------------------------------------
* disk_read_range — read dr_r_count sectors (whole tracks) starting at
*   dr_r_track / sector 1, into (dr_dest), using m=1 per track + Seek-advance.
*   dr_r_count must be a multiple of SECS_TRACK (whole-track-aligned; a
*   partial-track tail is a DEFERRED capability — streaming may need it).
*   Build #1's single-sector disk_read is left untouched (regression preserved).
* Output: dr_status (last track's status); CC.C set on error.
* ---------------------------------------------------------------
disk_read_range:
        lda     #DSK_POS
        sta     DSKREG
        jsr     dr_spinup
        lda     #FDC_RESTORE         ; Restore to track 0 (once)
        sta     FDC_CMDST
        jsr     dr_settle
        jsr     dr_wait_notbusy
        lda     dr_r_track
        sta     dr_track             ; current track
rr_track:
        lda     dr_track             ; --- off-end guard (BEFORE seeking) ---
        cmpa    #MAX_TRACK           ; track >= MAX_TRACK is past the last valid track
        bhs     rr_err               ; -> error (carry set), never seek off the end.
        *                              Closes Build #2's silent-zeros gap; deterministic,
        *                              MAME-edge-independent (we never reach the edge).
        sta     FDC_DATA             ; --- Seek to the current track (A = dr_track) ---
        lda     #FDC_SEEK
        sta     FDC_CMDST
        jsr     dr_settle
        jsr     dr_wait_notbusy
        jsr     dr_read_track_m1     ; 18 sectors via m=1 -> (dr_dest), advances it
        bcs     rr_err
        inc     dr_track             ; --- advance to the next track ---
        lda     dr_r_count
        suba    #SECS_TRACK
        sta     dr_r_count
        bne     rr_track             ; more whole tracks to read
        andcc   #$FE                 ; C clear = OK
        rts
rr_err:
        orcc    #$01                 ; C set = error
        rts

* ---------------------------------------------------------------
* dr_read_track_m1 — read one whole track (sectors 1..SECS_TRACK) via m=1 into
*   (dr_dest), HALT-paced, terminated by Force Interrupt (avoids the 5-rev RNF
*   stall the natural sector-overrun would cost). Advances dr_dest. CC.C on error.
* ---------------------------------------------------------------
dr_read_track_m1:
        lda     #1
        sta     FDC_SECTOR           ; whole track starts at sector 1
        clr     dr_nmi_done
        ldx     dr_dest
        lda     #FDC_READ_M          ; Read Sector, m=1 (multiple record)
        sta     FDC_CMDST
        lda     #DSK_XFER            ; arm HALT (b7): DRQ paces the whole-track xfer
        sta     DSKREG
        ldy     #SECS_TRACK*256      ; 18*256 = 4608 bytes, HALT-paced
rt_xfer:
        lda     FDC_DATA             ; HALT holds until each DRQ (spans all 18 sectors)
        sta     ,x+
        leay    -1,y
        bne     rt_xfer
        * whole track read; the FDC is now searching sector 19 (m=1 continues).
        lda     #DSK_POS             ; disarm HALT (b7=0) — latch write, not HALT-gated
        sta     DSKREG
        lda     FDC_CMDST            ; Type II read status BEFORE Force-Int
        sta     dr_status
        lda     #FDC_FORCEINT        ; terminate the m=1 search (no 5-rev RNF stall)
        sta     FDC_CMDST
        stx     dr_dest              ; save advanced destination pointer
        jsr     dr_settle            ; let Force-Int complete + Busy clear before...
        jsr     dr_wait_notbusy      ; ...the next Seek (command reg ignored while Busy)
        lda     dr_status
        anda    #FDC_ERRMASK_M       ; CRC/Lost-Data only (RNF = benign end-of-track)
        bne     rt_err
        andcc   #$FE
        rts
rt_err:
        orcc    #$01
        rts

* --- dr_wait_notbusy: poll Status b0 (Busy) until clear, with a timeout ---
dr_wait_notbusy:
        ldy     #$8000               ; timeout guard (never hang the sandbox)
dr_wnb:
        lda     FDC_CMDST
        bita    #$01                 ; Busy?
        beq     dr_wnb_ok
        leay    -1,y
        bne     dr_wnb
dr_wnb_ok:
        rts

* --- dr_settle: short delay so the FDC asserts Busy / updates status ---
dr_settle:
        ldb     #$20
dr_st1:
        exg     a,a                  ; ~8 cy delay each (DECB-style status-valid wait)
        decb
        bne     dr_st1
        rts

* --- dr_spinup: coarse motor spin-up delay (~real HW needs it; MAME tolerant) ---
*
* CONDITIONAL SINCE P3.76, and the reason is that the delay was never about elapsed
* time -- it is about a STOPPED motor reaching speed. Run unconditionally it charged
* every read for a spin-up the drive had already done: POP measured a second read,
* issued moments after the first with the drive still turning, paying the full
* 36 frames (0.60 s) for nothing. Three startup reads cost 1.80 s of a 9.27 s startup.
*
* THE COLD PATH IS UNCHANGED -- flag clear, full delay, same FDC sequence after it.
* Only the warm path is new, and on the warm path the delay was buying nothing.
*
* THE INVARIANT THIS INTRODUCES: nobody clears DSKREG behind the HAL's back. Callers
* release the drive through disk_read_motor_off, which clears both. Checked before it
* was written -- karateka has NO direct DSKREG writer, and POP's two
* (cutscene_room.s, intro_seq.s) are updated with this change. A violation would skip
* the spin-up on a stopped motor, which is a REAL-HARDWARE-ONLY fault: this delay's
* own header records that MAME is tolerant of its absence, so no emulated test can
* catch it. That is why the flag is the driver's and not the caller's.
dr_spinup:
        lda     dr_motor_on
        bne     dr_su_done           ; already turning -- the delay is not owed
        pshs    x
        ldx     #$C000
dr_su1:
        leax    -1,x
        bne     dr_su1
        puls    x
        lda     #1
        sta     dr_motor_on
dr_su_done:
        rts

* --- disk_read_motor_off: release the drive, and forget that it was turning -------
* The counterpart the flag needs. A caller that pokes DSKREG itself leaves the flag
* claiming a motor that has stopped, so releasing the drive is now the HAL's to do.
* A is clobbered; that matches the other entries here.
disk_read_motor_off:
        clr     DSKREG               ; motor off, no drive selected
        clr     dr_motor_on
        rts

        ifdef   OBJTARGET
        endsection
        endc
