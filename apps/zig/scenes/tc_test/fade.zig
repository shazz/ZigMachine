// --------------------------------------------------------------------------
// TC TEST's FADE view (key 8, HW 1.16.0): the hues picture faded and flashed by the plane's fade
// registers alone (LogicalFB.setTruecolorFade / setTruecolorOffset): four register bytes a frame,
// no pixel rewritten. On a Falcon the same fade rewrote all 112,000 words every frame.
// A 256-frame cycle (t = frames since the view was shown, mod 256):
//     0..63    a warm FLASH: +126 red, +63 green, -63 blue, decaying to none
//    64..127   to full black and back (coef 0 -> 31 -> 0, one step every two frames)
//   128..191   to full white and back
//   192..255   the picture as it is
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const PERIOD: u32 = 256;

pub const State = struct { coef: u5 = 0, dir: zg.tc.Dir = .black, r: i8 = 0, g: i8 = 0, b: i8 = 0 };

fn tri(u: u32) u5 { // 0..63 -> 0..31..0
    return @intCast(if (u < 32) u else 63 - u);
}

pub fn at(t: u32) State {
    const u = t % PERIOD;
    if (u < 64) {
        const k: i8 = @intCast(63 - u);
        return .{ .r = 2 * k, .g = k, .b = -k };
    }
    if (u < 128) return .{ .coef = tri(u - 64) };
    if (u < 192) return .{ .coef = tri(u - 128), .dir = .white };
    return .{};
}

pub const STEP: i8 = 2; // + / - in TC TEST: 16 presses from the picture to full black or white

// The manual fade (+ / -): below 0 toward black, above 0 toward white.
pub fn manual(level: i8) State {
    const c: u5 = @intCast(@abs(level));
    return .{ .coef = c, .dir = if (level < 0) .black else .white };
}

pub fn apply(plane: *zg.LogicalFB, s: State) void {
    plane.setTruecolorFade(s.coef, s.dir);
    plane.setTruecolorOffset(s.r, s.g, s.b);
}
