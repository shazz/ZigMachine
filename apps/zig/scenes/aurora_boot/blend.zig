// --------------------------------------------------------------------------
// AURORA BOOT: the aurora's playback onto the true-colour plane.
//
// The plane holds sky + aurora in RGB565. The baker stores, per stored row (every second row of the lit
// band), one palette index per pixel as the DIFFERENCE from the previous frame (mod 256), and each
// palette entry is a 565 level difference the baker proved never overflows a channel on either row it
// covers: so `sky + entry` is a plain 16-bit add (two pixels a 32-bit add would be the same).
// Only pixels whose delta is not zero are touched: a 32-bit word of four deltas that is 0 costs one
// load and a compare. Each stored row shows on `step` screen rows. The palette is one table shared by every
// row (`pal_stride` 0, A..E) or one 256-entry table per stored row (`pal_stride` 256, F).
// `Direct` (G) has no palette: the deltas are 16-bit pixel differences added to the plane (wrapping).
// No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const W: u32 = 320;

pub const Layer = struct {
    sky: [*]const u16, // the clean picture, H x W
    plane: [*]u16, // the displayed plane
    stride: u32, // plane row stride in pixels
    pal: [*]const u16, // 256 entries, or 256 per stored row
    pal_stride: u32 = 0, // 0: one shared table; 256: table `row` starts at row * 256
    state: []u8, // current palette index per stored pixel, rows x W
    y0: u32, // first screen row of the band
    step: u32, // screen rows per stored row
    rows: u32, // stored rows

    /// Apply frame deltas to stored rows [from, to): `delta` is the frame's rows x W bytes, 4-aligned.
    pub fn apply(self: *Layer, delta: []align(4) const u8, from: u32, to: u32) void {
        const words: [*]const u32 = @ptrCast(delta.ptr);
        var row = from;
        while (row < to) : (row += 1) {
            const base = row * W;
            var x: u32 = 0;
            while (x < W) : (x += 4) {
                const w = words[(base + x) / 4];
                if (w == 0) continue;
                inline for (0..4) |k| {
                    const d: u8 = @truncate(w >> (8 * k));
                    if (d != 0) self.set(row, x + @as(u32, k), d);
                }
            }
        }
    }

    fn set(self: *Layer, row: u32, x: u32, d: u8) void {
        const i = row * W + x;
        self.state[i] +%= d;
        const add = self.pal[row * self.pal_stride + self.state[i]];
        var s: u32 = 0;
        while (s < self.step) : (s += 1) {
            const y = self.y0 + row * self.step + s;
            self.plane[y * self.stride + x] = self.sky[y * W + x] + add;
        }
    }

    /// Back to the clean sky: the plane's band rows = the sky, the state = 0 (a replay).
    pub fn reset(self: *Layer) void {
        @memset(self.state, 0);
        const from = self.y0 * W;
        const to = (self.y0 + self.rows * self.step) * W;
        var i = from;
        while (i < to) : (i += 1) self.plane[(i / W) * self.stride + (i % W)] = self.sky[i];
    }
};

/// Variant G: 16-bit per-pixel deltas (the final 565 picture's change), every row, no palette, no state.
pub const Direct = struct {
    plane: [*]u16,
    stride: u32,
    y0: u32,
    rows: u32,

    /// Add deltas to rows [from, to): `delta` holds those rows only, (to - from) x W u16 (LE), 4-aligned.
    pub fn apply(self: *Direct, delta: []align(4) const u8, from: u32, to: u32) void {
        const words: [*]const u32 = @ptrCast(delta.ptr);
        var row = from;
        while (row < to) : (row += 1) {
            const line = self.plane + (self.y0 + row) * self.stride;
            const base = (row - from) * W / 2;
            var x: u32 = 0;
            while (x < W) : (x += 2) {
                const w = words[base + x / 2];
                if (w == 0) continue;
                line[x] +%= @truncate(w);
                line[x + 1] +%= @truncate(w >> 16);
            }
        }
    }
};

test "a delta lights the pixel on every row it covers, and only that pixel" {
    var sky = [_]u16{0x0001} ** (W * 4);
    var plane = [_]u16{0x0001} ** (W * 4);
    var state = [_]u8{0} ** (W * 2);
    var pal = [_]u16{0} ** 256;
    pal[3] = 0x0820;
    var delta: [W * 2]u8 align(4) = [_]u8{0} ** (W * 2);
    delta[5] = 3;
    var l = Layer{ .sky = &sky, .plane = &plane, .stride = W, .pal = &pal, .state = &state, .y0 = 0, .step = 2, .rows = 2 };
    l.apply(&delta, 0, 1);
    try std.testing.expectEqual(@as(u16, 0x0821), plane[5]);
    try std.testing.expectEqual(@as(u16, 0x0821), plane[W + 5]);
    try std.testing.expectEqual(@as(u16, 0x0001), plane[6]);
    try std.testing.expectEqual(@as(u16, 0x0001), plane[2 * W + 5]); // row 1 not applied yet
}

test "deltas accumulate mod 256 and reset restores the sky" {
    var sky = [_]u16{0x0002} ** (W * 2);
    var plane = [_]u16{0x0002} ** (W * 2);
    var state = [_]u8{0} ** W;
    var pal = [_]u16{0} ** 256;
    pal[1] = 0x0001;
    pal[255] = 0x0100;
    var delta: [W]u8 align(4) = [_]u8{0} ** W;
    delta[0] = 1;
    var l = Layer{ .sky = &sky, .plane = &plane, .stride = W, .pal = &pal, .state = &state, .y0 = 0, .step = 2, .rows = 1 };
    l.apply(&delta, 0, 1);
    delta[0] = 254; // 1 + 254 = 255
    l.apply(&delta, 0, 1);
    try std.testing.expectEqual(@as(u16, 0x0102), plane[0]);
    l.reset();
    try std.testing.expectEqual(@as(u16, 0x0002), plane[0]);
    try std.testing.expectEqual(@as(u8, 0), state[0]);
}

test "a per-row palette reads the row's own table" {
    var sky = [_]u16{0} ** (W * 2);
    var plane = [_]u16{0} ** (W * 2);
    var state = [_]u8{0} ** (W * 2);
    var pal = [_]u16{0} ** 512;
    pal[2] = 0x0001;
    pal[256 + 2] = 0x0800;
    var delta: [W * 2]u8 align(4) = [_]u8{0} ** (W * 2);
    delta[0] = 2;
    delta[W] = 2;
    var l = Layer{ .sky = &sky, .plane = &plane, .stride = W, .pal = &pal, .pal_stride = 256, .state = &state, .y0 = 0, .step = 1, .rows = 2 };
    l.apply(&delta, 0, 2);
    try std.testing.expectEqual(@as(u16, 0x0001), plane[0]);
    try std.testing.expectEqual(@as(u16, 0x0800), plane[W]);
}

test "direct deltas add 16-bit, wrap, skip zero words, and a later half reads its own buffer" {
    var plane = [_]u16{0x1000} ** (W * 3);
    var delta: [W * 2]u8 align(4) = [_]u8{0} ** (W * 2);
    std.mem.writeInt(u16, delta[2..4], 0x0021, .little); // pixel 1 of stored row 0 = screen row 1
    var d = Direct{ .plane = &plane, .stride = W, .y0 = 1, .rows = 2 };
    d.apply(&delta, 0, 1);
    try std.testing.expectEqual(@as(u16, 0x1021), plane[W + 1]);
    try std.testing.expectEqual(@as(u16, 0x1000), plane[W]);
    std.mem.writeInt(u16, delta[2..4], 0x10000 - 0x0021, .little); // minus: back to the sky
    d.apply(&delta, 0, 1);
    try std.testing.expectEqual(@as(u16, 0x1000), plane[W + 1]);
    std.mem.writeInt(u16, delta[0..2], 0x0001, .little);
    d.apply(&delta, 1, 2); // stored row 1 (screen row 2) from the start of the buffer
    try std.testing.expectEqual(@as(u16, 0x1001), plane[2 * W]);
}
