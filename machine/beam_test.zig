// Tests for machine/beam.zig, the BEAM span painter: the bus grid, the 8 px
// spacing, increasing order, the 64-write cap, drop counting and colour 0
// keeping its value into the next line.
const std = @import("std");
const beam = @import("beam.zig");
const expectEqual = std.testing.expectEqual;

const BG: u32 = 0xFF00_0000; // opaque black
var row: [beam.W]u64 = undefined;

fn e(x: u16, colour: u16) u32 {
    return (@as(u32, x) << 16) | colour;
}
// The RGBA a low-res pixel shows (both halves of its double-pixel must agree).
fn px(x: usize) u32 {
    const lo: u32 = @truncate(row[x]);
    std.debug.assert(lo == @as(u32, @truncate(row[x] >> 32)));
    return lo;
}

test "ST colour words land on the nibble*32 grid, STE half-steps 16 above" {
    try expectEqual(@as(u32, 0xFF00_0000), beam.stToRgba(0x000));
    try expectEqual(@as(u32, 0xFFE0_E0E0), beam.stToRgba(0x777));
    try expectEqual(@as(u32, 0xFF00_00E0), beam.stToRgba(0x700)); // red is the LOW byte (RGBA)
    try expectEqual(@as(u32, 0xFFF0_F0F0), beam.stToRgba(0xFFF));
    try expectEqual(@as(u32, 0xFF00_0010), beam.stToRgba(0x800)); // STE LSB alone
    try expectEqual(beam.stToRgba(0x123), beam.stToRgba(0xF123)); // high nibble ignored
}

test "no writes: the whole line is the background" {
    const l = beam.paintLine(&row, BG, &.{}, 0);
    try expectEqual(BG, l.bg);
    try expectEqual(@as(u32, 0), l.dropped);
    for (0..beam.W) |x| try expectEqual(BG, px(x));
}

test "spans switch at each x, and the last colour carries into the next line" {
    const t = [_]u32{ e(8, 0x700), e(40, 0x070), e(392, 0x007) };
    const l = beam.paintLine(&row, BG, &t, t.len);
    try expectEqual(@as(u32, 0), l.dropped);
    try expectEqual(BG, px(7));
    try expectEqual(beam.stToRgba(0x700), px(8));
    try expectEqual(beam.stToRgba(0x700), px(39));
    try expectEqual(beam.stToRgba(0x070), px(40));
    try expectEqual(beam.stToRgba(0x007), px(399));
    try expectEqual(beam.stToRgba(0x007), l.bg);
    // The next line starts in that colour until its first write.
    const t2 = [_]u32{e(100, 0x000)};
    _ = beam.paintLine(&row, l.bg, &t2, t2.len);
    try expectEqual(beam.stToRgba(0x007), px(0));
    try expectEqual(BG, px(100));
}

test "x snaps DOWN to the 4-cycle bus grid" {
    const t = [_]u32{e(11, 0x777)};
    _ = beam.paintLine(&row, BG, &t, t.len);
    try expectEqual(BG, px(7));
    try expectEqual(beam.stToRgba(0x777), px(8));
}

test "writes 8 px apart are accepted, 4 px apart are dropped" {
    const ok = [_]u32{ e(0, 0x111), e(8, 0x222), e(16, 0x333) };
    try expectEqual(@as(u32, 0), beam.paintLine(&row, BG, &ok, ok.len).dropped);
    const close = [_]u32{ e(0, 0x111), e(4, 0x222), e(8, 0x333) };
    const l = beam.paintLine(&row, BG, &close, close.len);
    try expectEqual(@as(u32, 1), l.dropped);
    try expectEqual(beam.stToRgba(0x111), px(4)); // the 4 px write never happened
    try expectEqual(beam.stToRgba(0x333), px(8));
    // Snapping counts: 13 snaps to 12, only 4 after the write at 8.
    const snapped = [_]u32{ e(8, 0x111), e(13, 0x222) };
    try expectEqual(@as(u32, 1), beam.paintLine(&row, BG, &snapped, snapped.len).dropped);
}

test "x must increase, and must be on the line" {
    const t = [_]u32{ e(100, 0x111), e(50, 0x222), e(100, 0x333), e(400, 0x444), e(0xFFFF, 0x555) };
    const l = beam.paintLine(&row, BG, &t, t.len);
    try expectEqual(@as(u32, 4), l.dropped);
    try expectEqual(BG, px(50));
    try expectEqual(beam.stToRgba(0x111), px(399));
    try expectEqual(beam.stToRgba(0x111), l.bg); // a dropped write leaves colour 0 alone
}

test "64 writes a line: the rest are counted as drops" {
    // 8 px apart, only 50 writes fit a 400 px line (x 0..392), so the table's 64
    // slots are never the tighter limit on screen; the cap still counts.
    var t: [64]u32 = undefined;
    for (&t, 0..) |*s, i| s.* = e(@intCast(i * 8), @intCast(i & 7));
    try expectEqual(@as(u32, 14), beam.paintLine(&row, BG, &t, 64).dropped);
    try expectEqual(beam.stToRgba(49 & 7), px(399));
    // COUNT says 70: only 64 slots exist, so 6 more never reached the table.
    try expectEqual(@as(u32, 20), beam.paintLine(&row, BG, &t, 70).dropped);
    try expectEqual(@as(u32, 0), beam.paintLine(&row, BG, t[0..50], 50).dropped);
}
