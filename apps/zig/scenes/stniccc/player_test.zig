// --------------------------------------------------------------------------
// Tests of the STNICCC frame player (player.zig): any frame drawn out of order
// matches the same frame played in order, over a tiny hand-built stream.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("stream.zig");
const player_mod = @import("player.zig");

const Player = player_mod.Player;
const Index = player_mod.Index;
const View = player_mod.View;

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

fn testPlayer(p: *Player, src: *st.SliceSource, buf: *[st.BLOCK]u8, index: *Index) void {
    p.init(src.source(), buf, index);
}
fn testView(px: *[VW * VH]u8) View {
    return .{ .target = .{ .px = px, .stride = VW, .w = VW, .h = VH, .ox = 0 }, .w = VW, .h = VH };
}

test "any frame drawn out of order matches the same frame played in order" {
    var scene_buf: [128]u8 = undefined;
    var src = st.SliceSource{ .bytes = buildScene(&scene_buf) };
    var buf: [st.BLOCK]u8 = undefined;
    var index: Index = undefined;
    var p: Player = undefined;
    testPlayer(&p, &src, &buf, &index);
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
    var index: Index = undefined;
    var p: Player = undefined;
    testPlayer(&p, &src, &buf, &index);
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
    var index: Index = undefined;
    var p: Player = undefined;
    testPlayer(&p, &src, &buf, &index);
    var screen = [_]u8{0} ** (VW * VH);
    try std.testing.expectError(error.Truncated, p.show(4, testView(&screen)));
    var empty = st.SliceSource{ .bytes = &.{} };
    var q_index: Index = undefined;
    var q: Player = undefined;
    testPlayer(&q, &empty, &buf, &q_index);
    try std.testing.expectError(error.ReadFailed, q.show(0, testView(&screen)));
}
