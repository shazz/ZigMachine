// --------------------------------------------------------------------------
// The keys, in one place both Modes share (mode.zig, mode_f32.zig):
//
//   Space  ORIGINAL <-> ZIG
//   1      ZIG only: the scrolltext, CODEF 484's curve <-> the original's flat
//   2      ZIG only: the bars, turning <-> the original's horizontal ones
//
// These are the two scrollers and the two raster styles the screen has, so
// each key toggles. Entering ZIG always starts on both ZIG styles, so Space
// shows what the boot note promises; in ORIGINAL, 1 and 2 do nothing at all.
// The styles only say where theta and the bend are HEADING: both still turn
// or grow over the frames Mode gives them, never snap.
// --------------------------------------------------------------------------
pub const Switches = struct {
    zig: bool, // ZIG mode: the top and bottom borders carry the rasters too
    spin: bool, // ZIG's bars turn (else they head home to horizontal)
    bent: bool, // ZIG's scrolltext rides the curve (else it flattens)

    pub fn init(self: *Switches) void {
        self.* = .{ .zig = false, .spin = true, .bent = true };
    }

    pub fn toggle(self: *Switches) void {
        self.zig = !self.zig;
        if (self.zig) {
            self.spin = true;
            self.bent = true;
        }
    }

    pub fn cycleScroller(self: *Switches) void {
        if (self.zig) self.bent = !self.bent;
    }

    pub fn cycleRasters(self: *Switches) void {
        if (self.zig) self.spin = !self.spin;
    }

    pub fn sweeps(self: Switches) bool {
        return self.zig and self.spin;
    }

    pub fn bends(self: Switches) bool {
        return self.zig and self.bent;
    }
};
