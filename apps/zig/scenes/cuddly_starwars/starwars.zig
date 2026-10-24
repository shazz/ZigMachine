// --------------------------------------------------------------------------
// CUDDLY STARWARS — the starwars scroller's perspective: the text canvas (swtext.zig)
// pushed through the perspective table (motion.zig) onto screen rows 100..199 as
// white coverage over what is there (only stars reach these rows).
//
// Each screen row takes at most two draws (a draw is under a row tall, so it straddles
// two rows). The original accumulates them 'source-over' into an alpha band, then blends
// the band onto the screen; here both draws of a row walk the row TOGETHER and the
// accumulated alpha goes straight onto the screen pixel: same sums in the same order,
// no band buffer, no second pass.
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const motion = @import("motion.zig");
const fixed = @import("fixed.zig");
const text = @import("swtext.zig");
const Stepper = @import("swstep.zig").Stepper;
const assert = std.debug.assert;

const W: usize = zg.WIDTH;
const BAND_Y: usize = 100;
const ONE = fixed.ONE;
pub const LINES = text.LINES;
pub const PITCH_Y = text.PITCH_Y;

const NONE = std.math.maxInt(u16);
/// The draws of each band row, in the table's (the original's) order; NONE: no draw.
const band_draws: [motion.BAND_ROWS][2]u16 = blk: {
    var t = [_][2]u16{.{ NONE, NONE }} ** motion.BAND_ROWS;
    for (motion.perspective, 0..) |p, k| {
        const d = &t[p.band_row];
        if (d[0] == NONE) {
            d[0] = k;
        } else {
            assert(d[1] == NONE); // never a third draw on one row
            d[1] = k;
        }
    }
    break :blk t;
};

pub fn init() void {
    text.init();
}

pub fn draw(screen: []u8, sw_line: usize, sw_offset: i32) void {
    text.layout(sw_line, sw_offset);
    for (band_draws, 0..) |d, r| {
        const row = screen[(BAND_Y + r) * W ..][0..W];
        var a: Stepper = undefined;
        var b: Stepper = undefined;
        const has_a = d[0] != NONE and a.init(motion.perspective[d[0]]);
        const has_b = d[1] != NONE and b.init(motion.perspective[d[1]]);
        if (has_a and has_b) {
            drawTwo(row, &a, &b);
        } else if (has_a) {
            drawOne(row, &a);
        } else if (has_b) {
            drawOne(row, &b);
        }
    }
}

fn drawOne(row: *[W]u8, s: *Stepper) void {
    for (s.start..s.end) |x| {
        const v = s.next();
        if (v != 0) put(&row[x], v);
    }
}

/// `a` is drawn first, `b` over it: band = a, then band = b + band * (1 - b).
fn drawTwo(row: *[W]u8, a: *Stepper, b: *Stepper) void {
    for (@min(a.start, b.start)..@max(a.end, b.end)) |x| {
        var v: u32 = if (x >= a.start and x < a.end) a.next() else 0;
        if (x >= b.start and x < b.end) {
            const vb = b.next();
            if (vb > 0) v = vb + ((v * (ONE - vb)) >> 16);
        }
        if (v != 0) put(&row[x], v);
    }
}

/// White at alpha v (Q16) over the grey already there.
inline fn put(d: *u8, v: u32) void {
    d.* = fixed.greyIndex(255 * v + @as(u32, fixed.grey_lut[d.*]) * (ONE - v));
}
