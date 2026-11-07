// --------------------------------------------------------------------------
// NATRIUM ZIG mode, part 5: the $E094 chrome twister (the "marshmallow bar")
// over the whole overscan window, every host frame, drawn by ZIGGY.
//
// The original: 80 columns of 4 px, each from two sines (SIN[7f/2 + 2i],
// SIN[-2f + i]): an angle g (one 8-px slice of the 512x64 chrome strip) for
// its first two pixels and the neighbour g + pass - 3 for the other two,
// pass = SIN[7f/2 + 2i + 1] - SIN[7f/2 + 2i] + 3: the slope. A pixel shows
// the slice's own column x & 7. 64 lines, bobbing between lines 9 and 119
// (SIN[4f] * 55), greetings on lines 1..8 and 191..198, on colour 15.
// Here the window grows the twister as it grows the screen:
//   across  100 columns: the sines run on past both ends (i = -10..89), the
//           middle 80 are the original's
//   down    the strip's 64 rows stretched to 90 lines (x 1.4, 200 -> 280)
//           and the bob over lines 13..266 (the original's 13..186 margins),
//           the greetings on the window's own edge lines, 1..8 and 271..278
// It is not affine (the column map is per 2 px) and not a MAP (512 texels
// across): a column-offset table a frame (200 entries), then each line is 100
// u32 stores of two u16 texel pairs from one 512-byte strip row. The lines
// the bar left are put back to colour 15. f + the frame's fraction (Q10).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const zmx = @import("rom_sdk").zmx;
const A = @import("assets.zig");
const R = @import("zig_res.zig");

pub const SW: usize = 512; // the strip
pub const SH: usize = 64;
pub const BAR: i32 = 90; // lines
pub const CENTRE: i32 = 95; // the bar's top line, 13..177
pub const AMP: i32 = 82;
pub const GREET_X: usize = (R.W - 224) / 2;
pub const GREET_Y = [2]usize{ 1, R.H - 9 };
const COLS: usize = R.W / 4; // 100
const I0: i32 = -@as(i32, R.OX / 4); // column 0 is the original's i = -10
const IDX: u32 = 1 << 22; // a SIN index (1024 a turn) as a fixtrig angle
const BG: u8 = 15;

pub var strip: []u16 = &.{}; // 512x64 pens, read as pixel pairs
/// The bar's top line last frame (-1: none drawn) and the greeting slot shown.
pub var top: i32 = -1;
var slot: i32 = -1;

/// The chrome ILBM (a row: 4 planes of 64 bytes) as 512x64 pens.
pub fn build() bool {
    strip = zg.mem.alloc(u16, SW * SH / 2) orelse return false;
    const px: [*]u8 = @ptrCast(strip.ptr);
    for (0..SH) |r| for (0..SW) |x| {
        var pen: u8 = 0;
        for (0..4) |p| pen |= ((A.chrome[r * 256 + p * 64 + x / 8] >> @intCast(7 - x % 8)) & 1) << @intCast(p);
        px[r * SW + x] = pen;
    };
    return true;
}

/// Entering the part: the window colour 15, nothing drawn yet.
pub fn enter(fb: *zg.LogicalFB) void {
    R.bl.fill(fb, 0, 0, R.W, R.H, BG);
    R.ops += 1;
    top = -1;
    slot = -1;
}

/// The bar's top line at time t (Q10 VBLs): SIN[4f] over the larger range.
pub fn topAt(t: u32) i32 {
    return CENTRE + zmx.zmMulsh16(trig.sin(t *% (4 << 12)), AMP);
}

/// The 200 pixel pairs of a line at time t: each pair's u16 index in a strip row.
pub fn columns(t: u32, out: *[2 * COLS]u16) void {
    var a1: u32 = t *% (7 << 11) +% @as(u32, @bitCast(2 * I0)) *% IDX; // SIN[7f/2 + 2i]
    var a2: u32 = (0 -% t *% (2 << 12)) +% @as(u32, @bitCast(I0)) *% IDX; // SIN[-2f + i]
    for (0..COLS) |k| {
        const a = trig.sin(a1) >> 8;
        const b = trig.sin(a1 +% IDX) >> 8;
        const c = trig.sin(a2) >> 8;
        const g: u32 = @as(u32, @bitCast(a + c)) & 63;
        const pass: u32 = @as(u32, @bitCast(b - a + 3)) & 7;
        const g2 = (g + pass + 61) & 63;
        const x: u32 = @intCast(4 * k);
        out[2 * k] = @intCast((g * 8 + (x & 7)) / 2);
        out[2 * k + 1] = @intCast((g2 * 8 + ((x + 2) & 7)) / 2);
        a1 +%= 2 * IDX;
        a2 +%= IDX;
    }
}

fn line(fb: *zg.LogicalFB, y: i32) []u32 {
    const p: [*]u32 = @ptrCast(@alignCast(fb.fb));
    return p[@as(usize, @intCast(y)) * (fb.stride / 4) ..][0..COLS];
}

/// Lines [last, last + BAR) the new bar at `y` no longer covers go back to colour 15.
fn erase(fb: *zg.LogicalFB, y: i32) void {
    if (top < 0) return;
    var l = top;
    while (l < top + BAR) : (l += 1) {
        if (l < y or l >= y + BAR) @memset(line(fb, l), 0x0F0F0F0F);
    }
}

/// Greeting `n` (8 lines of 224 px, one bit a pixel: 1 colour 15, 0 colour 0).
fn greeting(fb: *zg.LogicalFB, n: usize) void {
    const y0 = GREET_Y[n & 1];
    for (0..8) |r| {
        const out = fb.fb[(y0 + r) * fb.stride + GREET_X ..][0..224];
        for (out, 0..) |*d, x| d.* = if ((A.greet[(n & 15) * 0xE0 + r * 28 + x / 8] >> @intCast(7 - x % 8)) & 1 != 0) BG else 0;
    }
}

/// The greetings for `counter`: slot (counter - $1200) / 96, the one before it
/// still on the other edge (nothing erases a name but the next).
fn greetings(fb: *zg.LogicalFB, counter: u32) void {
    const n: i32 = @intCast((counter -| 0x1200) / 0x60);
    if (n == slot) return;
    if (slot < 0 and n > 0) greeting(fb, @intCast(n - 1));
    greeting(fb, @intCast(n));
    slot = n;
}

pub fn draw(fb: *zg.LogicalFB, t: u32, counter: u32) void {
    const y = topAt(t);
    erase(fb, y);
    var cols: [2 * COLS]u16 = undefined;
    columns(t, &cols);
    for (0..@intCast(BAR)) |l| {
        const src = strip[(l * SH / @as(usize, BAR)) * (SW / 2) ..][0 .. SW / 2];
        const out = line(fb, y + @as(i32, @intCast(l)));
        for (out, 0..) |*d, k| d.* = @as(u32, src[cols[2 * k]]) | @as(u32, src[cols[2 * k + 1]]) << 16;
    }
    top = y;
    greetings(fb, counter);
}
