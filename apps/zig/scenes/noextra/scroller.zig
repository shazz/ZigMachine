// --------------------------------------------------------------------------
// NOEXTRA's scroller, as $D3BA draws it: 20 columns of 16 px, each a word of
// bitplane 0 written down 16 lines at its own height (the wave table), with
// the 4 lines above and the 4 below cleared to colour 0 so last frame's letter
// leaves nothing behind. Plane 0 alone is colour 1 ($777) where a bit is set
// and colour 0 (the raster) where it is not.
//
// Here "colour 0" is the band's block index under that pixel (rasters.zig),
// so a column rewrites its 24 lines as the band pattern with the ink keyed in:
// 4 words a line, 96 a column, 1,920 a frame, the original's own count.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const T = @import("timeline.zig");
const R = @import("rasters.zig");

pub const COLUMNS = 20;
const CLEAR = 4; // lines cleared above and below

/// The band pattern under column c, 4 pixels a word, leftmost in the low byte.
const PATTERN = blk: {
    var t: [COLUMNS][4]u32 = undefined;
    for (&t, 0..) |*col, c| for (col, 0..) |*w, j| {
        const x = R.SX + 16 * c + 4 * j;
        w.* = 0;
        for (0..4) |i| w.* |= @as(u32, R.band_row[x + i]) << (8 * i);
    };
    break :blk t;
};

/// A nibble (MSB = leftmost pixel) as a byte mask.
const EXPAND = blk: {
    var t: [16]u32 = undefined;
    for (&t, 0..) |*m, n| {
        m.* = 0;
        for (0..4) |i| if (n & (8 >> i) != 0) {
            m.* |= @as(u32, 0xFF) << (8 * i);
        };
    }
    break :blk t;
};
const INK4: u32 = @as(u32, A.INK) * 0x0101_0101;

/// Call f's 20 columns into the band rows of `fb` (a PAD-offset ST screen).
pub fn draw(fb: *zg.LogicalFB, f: u32) void {
    const first: i32 = @as(i32, @intCast(f)) - 39;
    for (0..COLUMNS) |c| {
        const line = T.columnLine(f, @intCast(c));
        column(fb, c, line, first + 2 * @as(i32, @intCast(c)));
    }
}

fn column(fb: *zg.LogicalFB, c: usize, line: u32, b: i32) void {
    const stride: usize = fb.stride;
    const x = R.SX + 16 * c;
    var row: usize = R.PAD + line - CLEAR;
    for (0..16 + 2 * CLEAR) |n| {
        const bits: u32 = if (n < CLEAR or n >= 16 + CLEAR) 0 else glyphRow(b, @intCast(n - CLEAR));
        const words: [*]u32 = @ptrCast(@alignCast(fb.fb + row * stride + x));
        inline for (0..4) |j| {
            const m = EXPAND[(bits >> (12 - 4 * j)) & 0xF];
            words[j] = (PATTERN[c][j] & ~m) | (INK4 & m);
        }
        row += 1;
    }
}

/// 16 pixels of strip bytes b and b + 1, glyph row y.
fn glyphRow(b: i32, y: u32) u32 {
    return (@as(u32, T.stripByte(b, y)) << 8) | T.stripByte(b + 1, y);
}
