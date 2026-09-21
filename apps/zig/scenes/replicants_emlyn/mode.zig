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
// --------------------------------------------------------------------------
const THETA_STEP = 0.02;
const RETURN_STEP = 8 * THETA_STEP;
const BEND_STEP: f64 = 1.0 / 20.0; // the same 20 frames
const PI = 3.141592653589793;
const TAU = 2 * PI;

pub const Mode = struct {
    theta: f64,
    bend: f64,
    zig: bool,

    pub fn init(self: *Mode) void {
        self.theta = 0;
        self.bend = 0;
        self.zig = false;
    }

    pub fn toggle(self: *Mode) void {
        self.zig = !self.zig;
    }

    pub fn update(self: *Mode) void {
        self.turnBars();
        self.bendText();
    }

    /// ZIG sweeps the angle; ORIGINAL turns it home whichever way is nearer.
    /// Still a turn, never a snap — but it starts on the frame the key arrives.
    fn turnBars(self: *Mode) void {
        if (self.zig) {
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
        if (self.zig) {
            self.bend = if (self.bend + BEND_STEP >= 1) 1 else self.bend + BEND_STEP;
        } else {
            self.bend = if (self.bend <= BEND_STEP) 0 else self.bend - BEND_STEP;
        }
    }
};
