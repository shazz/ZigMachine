// --------------------------------------------------------------------------
// ORIGINAL or ZIG, and how far between them we are, in INTEGERS: the default
// cart's Mode. mode_f32.zig is the same machine on f32 and explains the numbers
// (a sweep of 0.02 rad a frame, home the short way at 0.16, the scrolltext's
// bend grown and flattened over the same 20 frames).
//
// The angle is a fixtrig Angle, so a full turn wraps exactly at 2^32 — the
// float version has to test and subtract TAU — and "home" is exactly 0, never
// a float that merely approaches it. The bend is a frame count 0..20.
// --------------------------------------------------------------------------
const trig = @import("zigos").fixtrig;
const Switches = @import("switches.zig").Switches;

const THETA_STEP = trig.angle(0.02);
const RETURN_STEP = trig.angle(8 * 0.02);
const HALF_TURN: trig.Angle = 1 << 31;
pub const BEND_FRAMES = 20;

pub const Mode = struct {
    theta: trig.Angle,
    bend: u8, // 0 = dead flat .. BEND_FRAMES = the full 484 curve
    sw: Switches, // ZIG or not, and its two styles (switches.zig)

    pub fn init(self: *Mode) void {
        self.theta = 0;
        self.bend = 0;
        self.sw.init();
    }

    pub fn flat(self: *const Mode) bool {
        return self.bend == 0;
    }

    /// The top and bottom borders carry the rasters: in ZIG, and on the way
    /// home until the bars are horizontal again, so no tilted bar is cut.
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

    fn turnBars(self: *Mode) void {
        if (self.sw.sweeps()) {
            self.theta +%= THETA_STEP;
            return;
        }
        if (self.theta == 0) return;
        const back = self.theta <= HALF_TURN; // nearer home going backwards
        const left = if (back) self.theta else 0 -% self.theta;
        if (left <= RETURN_STEP) {
            self.theta = 0;
            return;
        }
        self.theta = if (back) self.theta - RETURN_STEP else self.theta + RETURN_STEP;
    }

    fn bendText(self: *Mode) void {
        if (self.sw.bends()) {
            if (self.bend < BEND_FRAMES) self.bend += 1;
        } else if (self.bend > 0) self.bend -= 1;
    }
};
