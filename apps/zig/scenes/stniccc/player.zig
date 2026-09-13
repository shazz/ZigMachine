// --------------------------------------------------------------------------
// STNICCC frame player: draws ANY frame of the stream, not only the next one,
// at any size. The stream is a chain of deltas (805 of its 1800 frames paint
// over the frame before), so frame n is rebuilt by replaying from the last
// frame at or before n that clears the screen. Each frame's offset, clear flag
// and palette are recorded the first time it is decoded, which is what makes
// seeking back (the rewind) cheap. Pure (no ZigOS); tested at the bottom.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("stream.zig");
const polyfill = @import("polyfill.zig");

pub const MAX_FRAMES: u32 = 1800;
pub const SRC_W: u32 = 256; // the stream's coordinate space
pub const SRC_H: u32 = 200;

/// Where a frame is drawn: the fill target, and the size 256x200 is scaled to.
/// Scaling the VERTICES (not the pixels) keeps the edges sharp at any size.
pub const View = struct { target: polyfill.Target, w: u32, h: u32 };

pub const Player = struct {
    stream: st.Stream,
    offsets: [MAX_FRAMES]u32,
    clears: [MAX_FRAMES]bool,
    palettes: [MAX_FRAMES][16]u16, // the palette in effect once that frame is drawn
    known: u32, // frames 0..known-1 are indexed
    next: u32, // stream offset of frame `known`
    total: u32, // frame count once $FD has been read, else 0
    shown: ?u32, // the frame on screen, or null when the screen was disturbed

    pub fn init(self: *Player, source: st.Source, buf: *[st.BLOCK]u8) void {
        self.stream = .{ .source = source, .buf = buf };
        self.known = 0;
        self.next = 0;
        self.total = 0;
        self.shown = null;
    }

    pub fn palette(self: *const Player, n: u32) *const [16]u16 {
        return &self.palettes[n];
    }

    /// Draw frame n. The next frame after the one on screen decodes just that
    /// frame; anything else replays from the last clear frame at or before n.
    pub fn show(self: *Player, n: u32, view: View) st.Error!void {
        try self.indexTo(n);
        const sequential = if (self.shown) |s| n == s + 1 else false;
        var f = if (sequential) n else self.lastClear(n);
        while (f <= n) : (f += 1) try self.draw(f, view);
        self.shown = n;
    }

    fn lastClear(self: *const Player, n: u32) u32 {
        var f = n;
        while (f > 0 and !self.clears[f]) f -= 1;
        return f;
    }

    // Decode frames up to n without drawing, recording where each one starts.
    fn indexTo(self: *Player, n: u32) st.Error!void {
        if (n >= MAX_FRAMES or (self.total != 0 and n >= self.total)) return error.Truncated;
        var pal: [16]u16 = if (self.known == 0) [_]u16{0} ** 16 else self.palettes[self.known - 1];
        var poly: st.Poly = undefined;
        while (self.known <= n) {
            const f = self.known;
            self.stream.seek(self.next);
            const flags = try self.stream.beginFrame(&pal);
            while (try self.stream.nextPoly(&poly)) {}
            self.offsets[f] = self.next;
            self.clears[f] = flags.clear;
            self.palettes[f] = pal;
            self.next = self.stream.pos;
            self.known = f + 1;
            if (self.stream.done) {
                self.total = self.known;
                if (self.known <= n) return error.Truncated;
            }
        }
    }

    fn draw(self: *Player, f: u32, view: View) st.Error!void {
        self.stream.seek(self.offsets[f]);
        var ignored: [16]u16 = undefined; // the recorded palette is authoritative
        const flags = try self.stream.beginFrame(&ignored);
        if (flags.clear) clear(view.target);
        var poly: st.Poly = undefined;
        var pts: [st.MAX_POLY_VERTS]polyfill.Point = undefined;
        while (try self.stream.nextPoly(&poly)) {
            for (poly.pts[0..poly.n], 0..) |p, i| pts[i] = scale(p, view);
            polyfill.fill(view.target, pts[0..poly.n], poly.color);
        }
    }
};

fn scale(p: st.Point, view: View) polyfill.Point {
    return .{
        .x = @intCast((@as(u32, p.x) * view.w + SRC_W / 2) / SRC_W),
        .y = @intCast((@as(u32, p.y) * view.h + SRC_H / 2) / SRC_H),
    };
}

fn clear(t: polyfill.Target) void {
    for (0..t.h) |y| @memset(t.px[y * t.stride + t.ox ..][0..t.w], 0);
}

comptime {
    // A decoded polygon is copied into a polyfill point list before filling.
    if (st.MAX_POLY_VERTS > polyfill.MAX_VERTS) @compileError("polyfill.MAX_VERTS too small");
}

// --- tests ------------------------------------------------------------------
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

// Four frames on a coarse grid (the view is 32x25, so coordinates scale by 1/8):
//   0: clear, palette, a big square in colour 1
//   1: no clear, a smaller square in colour 2 painted over it
//   2: clear, a square in colour 3
//   3: no clear, colour 3 changes, a square in colour 4; end of stream
fn square(out: []u8, color: u8, x0: u8, y0: u8, x1: u8, y1: u8) usize {
    const bytes = [_]u8{ (color << 4) | 4, x0, y0, x1, y0, x1, y1, x0, y1 };
    @memcpy(out[0..bytes.len], &bytes);
    return bytes.len;
}
fn buildScene(out: []u8) []u8 {
    var n: usize = 0;
    for ([_]u8{ 0x03, 0x40, 0x00, 0x07, 0x77 }) |b| { // clear+palette: colour 1 = $777
        out[n] = b;
        n += 1;
    }
    n += square(out[n..], 1, 0, 0, 128, 104);
    out[n] = 0xFF;
    n += 1;
    out[n] = 0x00;
    n += 1;
    n += square(out[n..], 2, 64, 48, 128, 104);
    out[n] = 0xFF;
    n += 1;
    out[n] = 0x01;
    n += 1;
    n += square(out[n..], 3, 8, 8, 64, 56);
    out[n] = 0xFF;
    n += 1;
    for ([_]u8{ 0x02, 0x10, 0x00, 0x07, 0x00 }) |b| { // palette: colour 3 = $700
        out[n] = b;
        n += 1;
    }
    n += square(out[n..], 4, 16, 16, 40, 40);
    out[n] = 0xFD;
    n += 1;
    return out[0..n];
}

const VW = 32;
const VH = 25;

fn testPlayer(p: *Player, src: *st.SliceSource, buf: *[st.BLOCK]u8) void {
    p.init(src.source(), buf);
}
fn testView(px: *[VW * VH]u8) View {
    return .{ .target = .{ .px = px, .stride = VW, .w = VW, .h = VH, .ox = 0 }, .w = VW, .h = VH };
}

test "any frame drawn out of order matches the same frame played in order" {
    var scene_buf: [128]u8 = undefined;
    var src = st.SliceSource{ .bytes = buildScene(&scene_buf) };
    var buf: [st.BLOCK]u8 = undefined;
    var p: Player = undefined;
    testPlayer(&p, &src, &buf);
    var screen = [_]u8{0} ** (VW * VH);
    var snaps: [4][VW * VH]u8 = undefined;
    for (0..4) |f| {
        try p.show(@intCast(f), testView(&screen));
        snaps[f] = screen;
    }
    try expectEqual(@as(u32, 4), p.total);
    for ([_]u32{ 1, 3, 0, 2, 1 }) |f| {
        try p.show(f, testView(&screen)); // seeks back and forth over the recorded index
        try expectEqualSlices(u8, &snaps[f], &screen);
    }
    try expectEqual(@as(u16, 0x0700), p.palette(3)[3]);
    try expectEqual(@as(u16, 0x0777), p.palette(0)[1]);
}

test "frame 1 keeps frame 0 underneath; frame 2 clears it" {
    var scene_buf: [128]u8 = undefined;
    var src = st.SliceSource{ .bytes = buildScene(&scene_buf) };
    var buf: [st.BLOCK]u8 = undefined;
    var p: Player = undefined;
    testPlayer(&p, &src, &buf);
    var screen = [_]u8{0} ** (VW * VH);
    try p.show(1, testView(&screen)); // straight to frame 1: replays 0 then 1
    try expectEqual(@as(u8, 1), screen[1 * VW + 1]); // frame 0's square, not cleared
    try expectEqual(@as(u8, 2), screen[10 * VW + 12]); // frame 1's square on top
    try p.show(2, testView(&screen));
    try expectEqual(@as(u8, 0), screen[10 * VW + 12]); // cleared
}

test "a frame past the end, or a stream that cannot be read, is an error" {
    var scene_buf: [128]u8 = undefined;
    var src = st.SliceSource{ .bytes = buildScene(&scene_buf) };
    var buf: [st.BLOCK]u8 = undefined;
    var p: Player = undefined;
    testPlayer(&p, &src, &buf);
    var screen = [_]u8{0} ** (VW * VH);
    try std.testing.expectError(error.Truncated, p.show(4, testView(&screen)));
    var empty = st.SliceSource{ .bytes = &.{} };
    var q: Player = undefined;
    testPlayer(&q, &empty, &buf);
    try std.testing.expectError(error.ReadFailed, q.show(0, testView(&screen)));
}
