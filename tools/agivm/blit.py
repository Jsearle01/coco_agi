"""Compositing COST MODEL. Produces numbers, not a picture.

P2 owns pixel correctness (597/597 against the oracle). What P3 and the single-buffer decision
need from P5 is arithmetic: how much work the sprite composite is, and how much backing store an
erase would have to hold.

★★ THE INNER LOOP BEING COSTED, per the design decision this task carries:
      for each source pixel:  if source != transparent AND spritePriority >= priority[x >> 1]:
                                  write
    TWO TESTS PER PIXEL, and the priority lookup is x >> 1 because the priority screen stays
    160 wide while the visual screen is 320.

★ WHAT IS COUNTED AND WHAT IS NOT:

  tested       every source pixel of every drawn cel. Exact -- it is just cel area, and it is
               the figure the transparency test is paid on.
  opaque       source pixels that are not the clear key. Exact. This is the UPPER BOUND on
               writes: the priority test can only reject, never add.
  written      NOT COMPUTED, and not guessed. It needs the priority screen, which this VM does
               not build. Reporting `opaque` as "written" would overstate the write cost by
               however much priority rejects, so it is reported as a bound and named as one.

★ TRANSPARENCY VALUE. AGI cels carry a per-cel clear key; the CoCo3 design makes transparency
colour 0. The COUNTS here are invariant to which value denotes it -- the same set of pixels is
transparent either way -- so costing against the cel's own clearKey is faithful to both.

★★ peak_cel_area IS THE SAVE-UNDER BOUND. Single-buffered with save-under means an erase must
restore what was saved into that buffer, so the backing store must hold every simultaneously
drawn cel's footprint. That peak is the number the buffer decision rests on, which is why it is
tracked as a peak rather than an average.
"""


class BlitCost:
    def __init__(self):
        self.tested = 0             # source pixels examined (cel area)
        self.opaque = 0             # non-clear-key source pixels (upper bound on writes)
        self.composites = 0         # number of composite passes (one per cycle with objects)
        self.objects_blitted = 0    # cumulative object-blits

        self.peak_objects = 0       # most simultaneously drawn objects in one composite
        self.peak_cel_area = 0      # largest total drawn-cel area in one composite  ★ AC-6
        self.peak_object_area = 0   # largest single cel area seen

        self.peak_objects_cycle = -1
        self.peak_cel_area_cycle = -1

    def composite(self, vm, cycle_nr):
        """Cost one composite pass over the currently drawn objects. Changes no VM state."""
        from .optable import fDrawn

        st = vm.state
        n = 0
        area = 0

        for obj in st.screen_objs:
            if not (obj.flags & fDrawn):
                continue
            if obj.xSize == 0 or obj.ySize == 0:
                continue
            cel = vm.get_cel(obj)
            if cel is None:
                continue

            n += 1
            a = cel.width * cel.height
            area += a
            self.tested += a
            # count opaque pixels of this cel
            key = cel.clear_key
            self.opaque += sum(1 for px in cel.pixels if px != key)
            self.objects_blitted += 1
            if a > self.peak_object_area:
                self.peak_object_area = a

        if n:
            self.composites += 1
        if n > self.peak_objects:
            self.peak_objects = n
            self.peak_objects_cycle = cycle_nr
        if area > self.peak_cel_area:
            self.peak_cel_area = area
            self.peak_cel_area_cycle = cycle_nr

    def report(self):
        lines = []
        a = lines.append
        a("  composites (cycles with >=1 drawn object) : %d" % self.composites)
        a("  object-blits (cumulative)                 : %d" % self.objects_blitted)
        a("  source pixels TESTED                      : %d" % self.tested)
        a("  source pixels OPAQUE (upper bound on writes): %d" % self.opaque)
        if self.tested:
            a("  opaque fraction                           : %.1f%%"
              % (100.0 * self.opaque / self.tested))
        if self.composites:
            a("  mean tested per composite                 : %.1f"
              % (self.tested / self.composites))
        a("  peak simultaneous drawn objects           : %d  (cycle %d)"
          % (self.peak_objects, self.peak_objects_cycle))
        a("  peak single cel area                      : %d bytes" % self.peak_object_area)
        a("  ★ peak TOTAL cel area on screen           : %d bytes  (cycle %d)"
          % (self.peak_cel_area, self.peak_cel_area_cycle))
        a("      -- this is the save-under backing-store bound")
        a("  pixels WRITTEN                            : not computed (needs the priority")
        a("      screen; `opaque` above is the upper bound, priority can only reject)")
        return "\n".join(lines)
