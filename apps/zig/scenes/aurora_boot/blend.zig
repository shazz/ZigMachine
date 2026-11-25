// --------------------------------------------------------------------------
// AURORA BOOT: the aurora's playback onto the true-colour plane.
//
// The plane holds sky + aurora in RGB565. The baker stores, per stored row (every second row of the lit
// band), one palette index per pixel as the DIFFERENCE from the previous frame (mod 256), and each
// palette entry is a 565 level difference the baker proved never overflows a channel on either row it
// covers: so `sky + entry` is a plain 16-bit add (two pixels a 32-bit add would be the same).
// Only pixels whose delta is not zero are touched: a 32-bit word of four deltas that is 0 costs one
// load and a compare. Each stored row shows on `step` screen rows.
// No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const W: u32 = 320;

pub const Layer = struct {
    sky: [*]const u16, // the clean picture, H x W
    plane: [*]u16, // the displayed plane
    stride: u32, // plane row stride in pixels
    pal: *const [256]u16,
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
        const add = self.pal[self.state[i]];
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
