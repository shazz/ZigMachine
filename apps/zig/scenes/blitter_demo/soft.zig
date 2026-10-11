// --------------------------------------------------------------------------
// Blitter demo — ZIGGY's blitter: the same FILL / TRIANGLE / keyed BLIT the
// sealed blitter runs (machine/blitter.zig execute(), the model CHISEL matches),
// done by the CPU, pixel for pixel. Key B swaps it in (gfx.zig), so the frame
// rate shows what the blitter buys. Written the way a CPU coder would: clip
// once per op, then whole spans (@memset / @memcpy), a per-pixel loop only
// where the op needs one (colour key, OR, halftone).
//
// The rules copied from the machine, which keep the pixels equal:
//  - clip = [0, stride) x [0, h): the destination's own bounds (no CLIP rect);
//  - TRIANGLE: per scanline y the min/max x where an edge crosses, half-open
//    [ay, by), x = ax + floor((bx-ax)(y-ay)/(by-ay)), both ends inclusive;
//  - a halftone is on while any of its 16 rows is non-zero (the machine sniffs);
//    a set bit (x mod 16 of row y mod 16) draws COLOR, a clear one BG_COLOR.
// std only, so `zig test` runs it natively (build.sh NATIVE_TESTS).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Surface = struct {
    px: [*]u8,
    stride: u16,
    h: u16, // the machine's stride -> height rule (gfx.zig)
};

pub const Vec2 = struct { x: i16, y: i16 };

// The minterm bytes CHISEL takes (machine/sdk/memmap.zig MT_*), the three used here.
pub const MT_COPY: u8 = 0xCC; // D = B
pub const MT_XOR: u8 = 0x66; // D = B ^ C
pub const MT_OR: u8 = 0xEE; // D = B | C

pub const Soft = struct {
    halftone: [16]u16 = .{0} ** 16,
    ht_on: bool = false,
    bg: u8 = 0, // BG_COLOR as the last triangle left it: a halftone FILL reads it too

    pub fn setHalftone(self: *Soft, pattern: [16]u16) void {
        self.halftone = pattern;
        self.ht_on = false;
        for (pattern) |row| self.ht_on = self.ht_on or row != 0;
    }

    pub fn fill(self: *Soft, d: Surface, x: i16, y: i16, w: u16, h: u16, color: u8) void {
        const x0 = @max(@as(i32, x), 0);
        const x1 = @min(@as(i32, x) + w, d.stride);
        const y0 = @max(@as(i32, y), 0);
        const y1 = @min(@as(i32, y) + h, d.h);
        if (x1 <= x0) return;
        var py = y0;
        while (py < y1) : (py += 1) self.span(d, py, x0, x1 - 1, color, self.bg, MT_COPY);
    }

    pub fn triangle(self: *Soft, d: Surface, v: [3]Vec2, fg: u8, bg: u8, mt: u8) void {
        self.bg = bg;
        const ymin = @max(@min(v[0].y, @min(v[1].y, v[2].y)), 0);
        const ymax = @min(@max(v[0].y, @max(v[1].y, v[2].y)), @as(i32, d.h) - 1);
        var y: i32 = ymin;
        while (y <= ymax) : (y += 1) {
            var xl: i32 = std.math.maxInt(i32);
            var xr: i32 = std.math.minInt(i32);
            for (0..3) |e| crossEdge(v[e], v[(e + 1) % 3], y, &xl, &xr);
            if (xr < xl) continue;
            self.span(d, y, @max(xl, 0), @min(xr, @as(i32, d.stride) - 1), fg, bg, mt);
        }
    }

    // One clipped row [xa, xb] of a fill or triangle, combined through `mt`.
    fn span(self: *Soft, d: Surface, y: i32, xa: i32, xb: i32, fg: u8, bg: u8, mt: u8) void {
        if (xb < xa) return;
        const row = d.px + @as(usize, @intCast(y)) * d.stride;
        const lo: usize = @intCast(xa);
        const hi: usize = @intCast(xb + 1);
        if (!self.ht_on and mt == MT_COPY) return @memset(row[lo..hi], fg);
        const pat = self.halftone[@as(usize, @intCast(y)) & 15];
        for (row[lo..hi], lo..) |*p, x| {
            const src = if (!self.ht_on or (pat >> @intCast(x & 15)) & 1 != 0) fg else bg;
            p.* = combine(src, p.*, mt);
        }
    }

    // Keyed (key != null) or plain copy of a w x h block of `s` at (sx, sy) onto
    // `d` at (dx, dy). Like the machine, only the clipped part of the source is read.
    pub fn blit(self: *Soft, d: Surface, dx: i16, dy: i16, s: Surface, sx: i16, sy: i16, w: u16, h: u16, key: ?u8) void {
        _ = self;
        const c0: i32 = @max(0, -@as(i32, dx));
        const c1: i32 = @min(@as(i32, w), @as(i32, d.stride) - dx);
        const r0: i32 = @max(0, -@as(i32, dy));
        const r1: i32 = @min(@as(i32, h), @as(i32, d.h) - dy);
        if (c1 <= c0) return;
        const n: usize = @intCast(c1 - c0);
        var j = r0;
        while (j < r1) : (j += 1) {
            const src = s.px + @as(usize, @intCast(sy + j)) * s.stride + @as(usize, @intCast(sx + c0));
            const dst = d.px + @as(usize, @intCast(dy + j)) * d.stride + @as(usize, @intCast(dx + c0));
            if (key) |k| {
                for (src[0..n], dst[0..n]) |b, *o| {
                    if (b != k) o.* = b;
                }
            } else @memcpy(dst[0..n], src[0..n]);
        }
    }
};

// The machine's crossSpan for one edge: [ay, by) half-open, floor division.
fn crossEdge(a: Vec2, b: Vec2, y: i32, xl: *i32, xr: *i32) void {
    if (a.y == b.y) return;
    const lo = if (a.y < b.y) a else b;
    const hi = if (a.y < b.y) b else a;
    if (y < lo.y or y >= hi.y) return;
    const x = @as(i32, lo.x) + @divFloor((@as(i32, hi.x) - lo.x) * (y - lo.y), @as(i32, hi.y) - lo.y);
    xl.* = @min(xl.*, x);
    xr.* = @max(xr.*, x);
}

// D = LF(0, src, D) for the minterms in use; anything else bit by bit, as the machine.
fn combine(src: u8, dst: u8, mt: u8) u8 {
    return switch (mt) {
        MT_COPY => src,
        MT_OR => src | dst,
        MT_XOR => src ^ dst,
        else => blk: {
            var out: u8 = 0;
            for (0..8) |bit| {
                const idx: u3 = @intCast((((src >> @intCast(bit)) & 1) << 1) | ((dst >> @intCast(bit)) & 1));
                out |= @as(u8, @intCast((mt >> idx) & 1)) << @intCast(bit);
            }
            break :blk out;
        },
    };
}

test "a triangle is the machine's spans: half-open rows, floor edges" {
    var buf = [_]u8{0} ** (8 * 8);
    var s = Soft{};
    s.triangle(.{ .px = &buf, .stride = 8, .h = 8 }, .{ .{ .x = 1, .y = 1 }, .{ .x = 6, .y = 1 }, .{ .x = 1, .y = 6 } }, 7, 0, MT_COPY);
    // row 1: edges (1,1)-(1,6) and (6,1)-(1,6) both start there -> x 1..6; row 6 is excluded.
    try std.testing.expectEqualSlices(u8, &.{ 0, 7, 7, 7, 7, 7, 7, 0 }, buf[8..16]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 7, 7, 7, 0, 0, 0, 0 }, buf[32..40]); // y 4: x = 6 + floor(-5*3/5) = 3
    try std.testing.expectEqual(@as(u8, 0), buf[6 * 8 + 1]);
}

test "OR, halftone and a keyed blit clipped at the left edge" {
    var buf = [_]u8{1} ** 16;
    var s = Soft{};
    var pat = [_]u16{0} ** 16;
    pat[0] = 0b0101;
    s.setHalftone(pat);
    s.fill(.{ .px = &buf, .stride = 16, .h = 1 }, 0, 0, 4, 1, 9); // a halftone fill: 9 on set bits, BG 0 elsewhere
    try std.testing.expectEqualSlices(u8, &.{ 9, 0, 9, 0 }, buf[0..4]);
    s.setHalftone(.{0} ** 16);
    try std.testing.expect(!s.ht_on);
    var src = [_]u8{ 5, 0, 6, 0 };
    s.blit(.{ .px = &buf, .stride = 16, .h = 1 }, -1, 0, .{ .px = &src, .stride = 4, .h = 1 }, 0, 0, 4, 1, 0);
    try std.testing.expectEqualSlices(u8, &.{ 9, 6, 9, 0 }, buf[0..4]); // src 1..3 lands at x 0..2; 0 is the key
}
