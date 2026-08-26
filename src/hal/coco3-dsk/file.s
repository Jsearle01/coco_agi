* src/hal/coco3-dsk/file.s
*
* HAL File subsystem — STUB for P2.3a.3 production boot integration.
*
* STUB-P2.x: HAL_file_init is a no-op stub. Real implementation
*   requires CoCo3 FDC (floppy disk controller) initialization.
*   [no-ref: CoCo3 FDC register addresses — resolve from CC3-TR during
*    disk subsystem port]
*
* HAL contract reference: src/hal.inc (HAL_file_* declarations)
* ---------------------------------------------------------------

        ifdef   OBJTARGET
        * setdp is NOT permitted for the object target — the fourth
        * object-incompatible directive class (P2.4; the recon found three).
        * The HAL uses explicit `<` direct-mode operands, so omitting the
        * declaration changes nothing it relies on.
        else
        setdp   0
        endc
        
        ifdef   OBJTARGET
        * Object/linked build (POP, P2.4). Guard OFF = the absolute build
        * (karateka today): not one byte of this file changes.
        section code
        export  HAL_file_init
        endc

* ---------------------------------------------------------------
* HAL_file_init  [STUB-P2.x]
*
* Initialize disk subsystem. Stub: returns success immediately.
*
* Args:    none
* Returns: CC.C clear (success)
* ---------------------------------------------------------------
HAL_file_init:
        andcc   #$FE                    ; CC.C clear = success (stub)
        rts
                
                ifdef   OBJTARGET
                endsection
                endc
