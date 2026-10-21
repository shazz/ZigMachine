// --------------------------------------------------------------------------
// The keys, in one place both Modes share (mode.zig, mode_f32.zig):
//
//   Space  ORIGINAL <-> ZIG
//   1      ZIG only: the scrolltext, CODEF 484's curve <-> the original's flat
//   2      ZIG only: the bars, turning <-> the original's horizontal ones
//   3      ZIG only: the ramp, the movem-sized gradient (up to 88 changes a
//          line) <-> one held to 16 changes a line (rasters.zig: CAP16)
//
// These are the two scrollers, raster styles and ramps the screen has, so
// each key toggles. Entering ZIG always starts on the ZIG styles and the full
// gradient, so Space shows what the boot note promises; in ORIGINAL, 1, 2
// and 3 do nothing at all. The styles only say where theta and the bend are
// HEADING: both still turn or grow over the frames Mode gives them.
// --------------------------------------------------------------------------
pub const Switches = struct {
    zig: bool, // ZIG mode: the top and bottom borders carry the rasters too
    spin: bool, // ZIG's bars turn (else they head home to horizontal)
    bent: bool, // ZIG's scrolltext rides the curve (else it flattens)
    cap16: bool, // ZIG's ramp is held to 16 palette changes a line

    pub fn init(self: *Switches) void {
        self.* = .{ .zig = false, .spin = true, .bent = true, .cap16 = false };
    }

    pub fn toggle(self: *Switches) void {
        self.zig = !self.zig;
        if (self.zig) {
            self.spin = true;
            self.bent = true;
            self.cap16 = false;
        }
    }

    pub fn cycleScroller(self: *Switches) void {
        if (self.zig) self.bent = !self.bent;
    }

    pub fn cycleRasters(self: *Switches) void {
        if (self.zig) self.spin = !self.spin;
    }

    pub fn cycleColours(self: *Switches) void {
        if (self.zig) self.cap16 = !self.cap16;
    }

    /// The 16-a-line ramp, in ZIG only: ORIGINAL, and the way home from ZIG,
    /// keep the gradient, so ORIGINAL never changes.
    pub fn capped(self: Switches) bool {
        return self.zig and self.cap16;
    }

    pub fn sweeps(self: Switches) bool {
        return self.zig and self.spin;
    }

    pub fn bends(self: Switches) bool {
        return self.zig and self.bent;
    }
};
