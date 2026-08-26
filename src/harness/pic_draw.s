* src/harness/pic_draw.s  — draw_Line, transcribed for the 6809.
*
* ★★ TRANSCRIBED, NOT REPLACED WITH BRESENHAM. The oracle's draw_Line is its own line walker
* and its rounding differs from a textbook Bresenham at ties. tools/picrender/draw.py carries
* the same warning and was proven 597/597 against the oracle by keeping the algorithm rather
* than improving it. The same discipline applies here: a "better" line is a different picture.
*
* ★ THE ERROR ACCUMULATORS ARE 16-BIT AND THAT IS NOT DEFENSIVE. The invariant is
* error < detdelta before each add, so after `error += delta` the value can reach
* detdelta + delta = 167 + 167 = 334. In 8 bits that wraps and the line bends. Measured from
* the algorithm, not guessed.
*
* in:  ln_x1, ln_y1, ln_x2, ln_y2   (bytes)
* uses cur_x / cur_y as the pen position, so put_pixel needs no arguments.

* ★★★ draw_line USES cur_x/cur_y AS ITS PLOTTING CURSOR, because put_pixel reads them -- but
* the CALLERS use the same two bytes as the persistent PEN position. Without the save/restore
* below, a line leaves the pen wherever the walk ended, and the VERTICAL/HORIZONTAL branches
* SWAP their endpoints first, so the walk ends at the OTHER end from the one the caller set.
*
* Measured: a synthetic picture of 23 stacked (dx=0, dy=-7) rel_line steps entered the vertical
* branch 23 times and wrote 185 pixels -- but only EIGHT distinct pixels existed, rows 160-167,
* drawn 23 times over. 23 x 8 + 1 = 185 exactly. Each step recomputed from a pen the previous
* line had left at the swapped end, so every segment redrew the first one.
*
* ★ This is the defect that made the whole picture wrong, and it is invisible in the algorithm:
* the Python transcription passes x1,y1,x2,y2 as PARAMETERS and keeps the caller's pen in
* separate locals, so it cannot express the bug. Sharing the two bytes was an assembly-level
* decision, and this is what it cost.
draw_line:
                lda     cur_x                   ; ★ the caller's pen -- restored on every exit
                pshs    a
                lda     cur_y
                pshs    a
* --- clip both endpoints to the picture, as the oracle does before walking ---
                lda     ln_x1
                cmpa    #PIC_W
                blo     dl_x1ok
                lda     #PIC_W-1
                sta     ln_x1
dl_x1ok:        lda     ln_x2
                cmpa    #PIC_W
                blo     dl_x2ok
                lda     #PIC_W-1
                sta     ln_x2
dl_x2ok:        lda     ln_y1
                cmpa    #PIC_H
                blo     dl_y1ok
                lda     #PIC_H-1
                sta     ln_y1
dl_y1ok:        lda     ln_y2
                cmpa    #PIC_H
                blo     dl_y2ok
                lda     #PIC_H-1
                sta     ln_y2
dl_y2ok:

* --- vertical ---------------------------------------------------
                lda     ln_x1
                cmpa    ln_x2
                bne     dl_nvert
                sta     cur_x
                pshs    d
                ldd     CNT_VERT
                addd    #1
                std     CNT_VERT
                puls    d
                lda     ln_y1
                cmpa    ln_y2
                bls     dl_vord
                lda     ln_y2                   ; swap so y1 <= y2
                ldb     ln_y1
                sta     ln_y1
                stb     ln_y2
dl_vord:        lda     ln_y1
dl_vlp:         sta     cur_y
                pshs    a
                jsr     put_pixel
                puls    a
                cmpa    ln_y2
                bhs     dl_done
                inca
                bra     dl_vlp

* --- horizontal -------------------------------------------------
dl_nvert:       lda     ln_y1
                cmpa    ln_y2
                bne     dl_diag
                sta     cur_y
                pshs    d
                ldd     CNT_HORIZ
                addd    #1
                std     CNT_HORIZ
                puls    d
                lda     ln_x1
                cmpa    ln_x2
                bls     dl_hord
                lda     ln_x2
                ldb     ln_x1
                sta     ln_x1
                stb     ln_x2
dl_hord:        lda     ln_x1
dl_hlp:         sta     cur_x
                pshs    a
                jsr     put_pixel
                puls    a
                cmpa    ln_x2
                bhs     dl_done
                inca
                bra     dl_hlp
dl_done:        puls    a
                sta     cur_y
                puls    a
                sta     cur_x
                rts

* --- the general case -------------------------------------------
dl_diag:
                pshs    d
                ldd     CNT_DIAG
                addd    #1
                std     CNT_DIAG
                puls    d
                lda     #1
                sta     dl_stepx
                lda     ln_x2
                suba    ln_x1
                bpl     dl_dxpos
                nega
                ldb     #$FF
                stb     dl_stepx
dl_dxpos:       sta     dl_dx

                lda     #1
                sta     dl_stepy
                lda     ln_y2
                suba    ln_y1
                bpl     dl_dypos
                nega
                ldb     #$FF
                stb     dl_stepy
dl_dypos:       sta     dl_dy

                lda     dl_dy
                cmpa    dl_dx
                bls     dl_xmajor
* delta_y > delta_x : detdelta = i = dy ; error_x = dy/2 ; error_y = 0
                sta     dl_det
                sta     dl_i
                clra
                ldb     dl_dy
                lsrb
                std     dl_ex                   ; D = 0:(dy>>1)
                ldd     #0
                std     dl_ey
                bra     dl_walk
dl_xmajor:
* delta_x >= delta_y : detdelta = i = dx ; error_x = 0 ; error_y = dx/2
                lda     dl_dx
                sta     dl_det
                sta     dl_i
                ldd     #0
                std     dl_ex
                clra
                ldb     dl_dx
                lsrb
                std     dl_ey                   ; D = 0:(dx>>1)
dl_walk:
                lda     ln_x1
                sta     cur_x
                lda     ln_y1
                sta     cur_y
                jsr     put_pixel

dl_lp:
* error_y += delta_y ; if error_y >= detdelta: error_y -= detdelta ; y += step_y
                ldb     dl_dy
                clra
                addd    dl_ey
                std     dl_ey
                ldb     dl_det
                clra
                cmpd    dl_ey
                bhi     dl_noy                  ; detdelta > error_y -> no step
                ldd     dl_ey
                subb    dl_det
                sbca    #0
                std     dl_ey
                lda     cur_y
                adda    dl_stepy
                sta     cur_y
dl_noy:
* error_x += delta_x ; if error_x >= detdelta: error_x -= detdelta ; x += step_x
                ldb     dl_dx
                clra
                addd    dl_ex
                std     dl_ex
                ldb     dl_det
                clra
                cmpd    dl_ex
                bhi     dl_nox
                ldd     dl_ex
                subb    dl_det
                sbca    #0
                std     dl_ex
                lda     cur_x
                adda    dl_stepx
                sta     cur_x
dl_nox:
                jsr     put_pixel
                dec     dl_i
                beq     dl_end
                lda     dl_i
                bpl     dl_lp
dl_end:         puls    a
                sta     cur_y
                puls    a
                sta     cur_x
                rts

ln_x1           fcb     0
ln_y1           fcb     0
ln_x2           fcb     0
ln_y2           fcb     0
dl_dx           fcb     0
dl_dy           fcb     0
dl_stepx        fcb     0
dl_stepy        fcb     0
dl_det          fcb     0
dl_i            fcb     0
dl_ex           fdb     0
dl_ey           fdb     0
