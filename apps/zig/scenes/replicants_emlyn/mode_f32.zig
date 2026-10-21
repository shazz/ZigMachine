// --------------------------------------------------------------------------
// ORIGINAL or ZIG, and the two numbers that say how far between them we are.
// Space switches (the scene's input(), via the host's Fire), and both numbers
// move over the same 20 frames so the bars and the scrolltext never disagree.
//
//   theta  the raster bars' angle. ZIG sweeps it; ORIGINAL brings it home.
//   bend   0 = the scrolltext is dead flat, 1 = the full 484 curve.
//
// Neither number is the original's — screen 17 has no bar angle and passes its
// scrolltext no sinparam. THETA_STEP is half the group's own 0.04 and the same
// number the logo's sine steps by, so a full turn takes 2*pi / 0.02 = 314
// frames (5.2 s), the logo's bob period. Coming BACK answers a keypress, so it
// has to read as immediate: eight times the sweep, the SHORT way round, at most
// pi / 0.16 = 20 frames. Both land exactly on their end value rather than
// drifting near it — a float accumulator that merely approaches 0 would leave
// the screen on the ZIG code path for ever, drawing the same pixels by a
// different route.
//
// This is replicants_emlyn_f32's Mode, on f32 for the FPU test. The default
// cart's (mode.zig) is the same machine on an integer angle and a frame count.
// --------------------------------------------------------------------------
const Switches = @import("switches.zig").Switches;
const THETA_STEP = 0.02;
const RETURN_STEP = 8 * THETA_STEP;
const BEND_STEP: f32 = 1.0 / 20.0; // the same 20 frames
const PI = 3.141592653589793;
const TAU = 2 * PI;

pub const Mode = struct {
    theta: f32,
    bend: f32,
    sw: Switches, // ZIG or not, and its two styles (switches.zig)

    pub fn init(self: *Mode) void {
        self.theta = 0;
        self.bend = 0;
        self.sw.init();
    }

    /// The scrolltext is dead flat: draw it with the original's plain blit.
    pub fn flat(self: *const Mode) bool {
        return self.bend <= 0;
    }

    /// mode.zig's: ZIG, or bars not yet home.
    pub fn bordersOpen(self: *const Mode) bool {
        return self.sw.zig or self.theta != 0;
    }

    pub fn toggle(self: *Mode) void {
        self.sw.toggle();
    }

    pub fn update(self: *Mode) void {
        self.turnBars();
        self.bendText();
    }

    /// ZIG sweeps the angle; ORIGINAL turns it home whichever way is nearer.
    /// Still a turn, never a snap — but it starts on the frame the key arrives.
    fn turnBars(self: *Mode) void {
        if (self.sw.sweeps()) {
            self.theta += THETA_STEP;
            if (self.theta >= TAU) self.theta -= TAU;
            return;
        }
        if (self.theta == 0) return;
        const left = if (self.theta <= PI) self.theta else TAU - self.theta;
        if (left <= RETURN_STEP) {
            self.theta = 0;
            return;
        }
        self.theta += if (self.theta <= PI) -RETURN_STEP else RETURN_STEP;
    }

    fn bendText(self: *Mode) void {
        if (self.sw.bends()) {
            self.bend = if (self.bend + BEND_STEP >= 1) 1 else self.bend + BEND_STEP;
        } else {
            self.bend = if (self.bend <= BEND_STEP) 0 else self.bend - BEND_STEP;
        }
    }
};
