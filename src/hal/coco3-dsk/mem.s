* src/hal/coco3-dsk/mem.s
*
* HAL Memory subsystem — STUB for P2.3a.3 production boot integration.
*
* STUB-P2.x: HAL_mem_size_detect is a minimal stub returning a
*   reasonable default (128K / D=$8000). Real implementation probes
*   GIME MMU to distinguish 128K from 512K.
*   [no-ref: GIME MMU probing for 128K vs 512K — resolve from CC3-TR
*    MMU section during memory subsystem port]
*
* HAL contract reference: src/hal.inc (HAL_mem_size_detect declaration)
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
        export  HAL_mem_size_detect
        endc

* ---------------------------------------------------------------
* HAL_mem_size_detect  [STUB-P2.x]
*
* Probe installed RAM. Stub: returns $0000 = 128K mode (A=0).
*
* Per hal.inc contract: Returns A = 0 if 128K, 1 if 512K.
*
* Args:    none
* Returns: A = 0 (128K assumed; probe not yet implemented)
*          CC.C clear (success)
* ---------------------------------------------------------------
HAL_mem_size_detect:
        clra                            ; A = 0 = 128K (stub; probe deferred)
        andcc   #$FE                    ; CC.C clear = success
        rts

* NOTE (HAL-sync flag 2): the `end boot` directive that used to terminate this file
* has been relocated to src/engine/entry.s. A HAL module must not name the ENGINE's
* entry symbol — it made the HAL unassemblable in any project without a `boot`
* (demonstrated when POP adopted it) and forced this file to be build-list-last.
* The program entry now lives in the engine/build layer, where it belongs.
                
                ifdef   OBJTARGET
                endsection
                endc
