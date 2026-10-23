// --------------------------------------------------------------------------
// STCS STARGOOSE — ZIG MODE, switched by Z at any moment (stcs.zig key()).
// ORIGINAL is the default and is the cart as it was, frame for frame
// (apps/stcs_headless.mjs). ZIG adds three effects, each with its own key so
// its cost can be read off the board's fps on its own:
//
//   1  BORDERS  the scrolltext runs on through the LEFT and RIGHT borders:
//               the plane's HBL flickers the resolution on every visible line
//               (stcs_hbl.zig), the strips and the copies widen to 400 px
//               (stcs_scratch.zig, stcs_strip.zig Opts.wide)
//   2  FADE     the logo fades in, holds, fades out, holds black, and loops:
//               its 15 palette entries, written only when the level changes
//   3  STARS    stars scroll right to left behind the logo and the letters
//               (stcs_stars.zig)
//
// Entering ZIG turns all three on; 1, 2, 3 do nothing in ORIGINAL; leaving
// ZIG turns all three off and puts back what they changed.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hbl = @import("stcs_hbl.zig");
const logo = @import("stcs_logo.zig");

pub const Fx = struct { borders: bool = false, fade: bool = false, stars: bool = false };

/// What the keys asked for (key() runs between frames); live is what render
/// applied, so a change is acted on once, at the top of a frame.
pub var wanted: Fx = .{};
pub var live: Fx = .{};
var zig = false;

pub fn reset() void {
    wanted = .{};
    live = .{};
    zig = false;
    fade_clock = 0;
    fade_shown = LEVELS - 1;
}

/// A key: true if ZIG MODE used it.
pub fn key(cp: u32) bool {
    switch (cp) {
        'Z', 'z' => {
            zig = !zig;
            wanted = if (zig) .{ .borders = true, .fade = true, .stars = true } else .{};
        },
        '1' => if (zig) {
            wanted.borders = !wanted.borders;
        },
        '2' => if (zig) {
            wanted.fade = !wanted.fade;
        },
        '3' => if (zig) {
            wanted.stars = !wanted.stars;
        },
        else => return false,
    }
    return true;
}

// ---- 2: the logo fade ----------------------------------------------------
// 8 levels, each channel scaled by level / 7 (level 7 is logo_pal itself), as
// an ST fade steps its 3-bit colours. One loop is 256 frames: in over 32 (a
// level every 4), hold 160, out over 32, black for 32.
const LEVELS = 8;
const faded: [LEVELS][logo.COLORS]u32 = blk: {
    @setEvalBranchQuota(10_000);
    var t: [LEVELS][logo.COLORS]u32 = undefined;
    for (0..LEVELS) |l| {
        for (0..logo.COLORS) |i| {
            const c = hbl.logo_pal[i];
            t[l][i] = (zg.Color{ .r = scale(c.r, l), .g = scale(c.g, l), .b = scale(c.b, l), .a = c.a }).toRGBA();
        }
    }
    break :blk t;
};
fn scale(v: u8, l: usize) u8 {
    return @intCast(@as(usize, v) * l / (LEVELS - 1));
}

var fade_clock: u8 = 0;
var fade_shown: usize = LEVELS - 1; // what entries 17..31 hold (init writes logo_pal)

fn fadeLevel(t: u8) usize {
    return switch (t) {
        0...31 => t >> 2,
        32...191 => LEVELS - 1,
        192...223 => LEVELS - 1 - ((t - 192) >> 2),
        else => 0,
    };
}

/// Once a frame: the level the fade wants (full when it is off), written only
/// where it differs from what the palette holds.
pub fn fade(fb: *zg.LogicalFB) void {
    var want: usize = LEVELS - 1;
    if (live.fade) {
        want = fadeLevel(fade_clock);
        fade_clock +%= 1;
    } else fade_clock = 0;
    if (want == fade_shown) return;
    for (1..logo.COLORS) |i| {
        if (faded[want][i] != faded[fade_shown][i]) fb.palette[logo.BASE + i] = faded[want][i];
    }
    fade_shown = want;
}

comptime {
    for (1..logo.COLORS) |i| {
        if (faded[LEVELS - 1][i] != hbl.logo_pal[i].toRGBA()) @compileError("fade level 7 is not logo_pal");
    }
}
