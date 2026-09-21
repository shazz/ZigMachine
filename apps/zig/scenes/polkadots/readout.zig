// --------------------------------------------------------------------------
// The bench's readout: the mode's number and name, the blitter OPERATIONS it
// issued this frame, and the PIXELS the blitter reported touching (BLIT_CYCLES,
// summed over the frame). The cost is half of the comparison, so it is on
// screen next to the name rather than only in the harness.
//
// It also writes a 24-pixel BINARY TAP into the last row: mode, then the op
// count, one bit per pixel, in an ink that is (0,0,1) — black on any monitor,
// but a value apps/polkadots_headless.mjs can read back. That is how the
// harness proves the number the label claims is the number of blits the cart
// actually issued, for every mode, without re-deriving it from the picture.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const dots = @import("dots.zig");

pub const TAP_X: u16 = zg.WIDTH - 24;
pub const TAP_Y: u16 = zg.HEIGHT - 1;
pub const LABEL_Y: i16 = zg.HEIGHT - 8;

/// Write `v` as decimal at `at` in `buf` and return the next free index.
fn decimal(buf: []u8, at: usize, v: u32) usize {
    var digits: [10]u8 = undefined;
    var n: usize = 0;
    var rest = v;
    while (true) {
        digits[n] = '0' + @as(u8, @intCast(rest % 10));
        n += 1;
        rest /= 10;
        if (rest == 0) break;
    }
    var i = at;
    while (n > 0) : (i += 1) {
        n -= 1;
        buf[i] = digits[n];
    }
    return i;
}

fn word(buf: []u8, at: usize, s: []const u8) usize {
    for (s, 0..) |c, i| buf[at + i] = c;
    return at + s.len;
}

/// "2 HALFTONE 84 OPS 39K PX" along the bottom of the screen.
pub fn label(zigos: *zg.ZigOS, fb: *zg.LogicalFB, mode: u8, name: []const u8, ops: u32, px: u32) void {
    var buf: [40]u8 = undefined;
    var i = decimal(&buf, 0, mode + 1);
    i = word(&buf, i, " ");
    i = word(&buf, i, name);
    i = word(&buf, i, " ");
    i = decimal(&buf, i, ops);
    i = word(&buf, i, " OPS ");
    i = decimal(&buf, i, px / 1000);
    i = word(&buf, i, "K PX");
    zigos.printText(fb, buf[0..i], 1, LABEL_Y, dots.LABEL_INK, 0);
}

/// 8 bits of mode then 16 bits of op count, LSB first, in the last row.
pub fn tap(fb: *zg.LogicalFB, mode: u8, ops: u32) void {
    // @min NARROWS the result type to u16 here (its value cannot exceed
    // 0xFFFF), and a u16 shifted left by 8 drops its top byte — so the cap is
    // widened back to u32 before the shift.
    const capped: u32 = @min(ops, 0xFFFF);
    const bits: u32 = @as(u32, mode) | (capped << 8);
    for (0..24) |b| {
        const on = (bits >> @intCast(b)) & 1 != 0;
        fb.setPixelValue(TAP_X + @as(u16, @intCast(b)), TAP_Y, if (on) dots.TAP_INK else 0);
    }
}
