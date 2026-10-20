// --------------------------------------------------------------------------
// The chunky engine IS the planar one: engine.zig (pinned by the original
// machine's seven RAM checkpoints, engine_test.zig) and chunky.zig run side by
// side for 22000 ticks -- both title slides and every phase 0..7, twice over
// (one full text cycle is 10714 ticks) -- and on EVERY tick the chunky front
// surface must equal expand(planar screen) byte for byte, the shown surface
// must equal it after present(), and the clocks and flags must agree.
//
//     zig test apps/zig/scene_tests.zig --test-filter lockbuster2
// --------------------------------------------------------------------------
const std = @import("std");
const ref = @import("engine.zig");
const chunky = @import("chunky.zig");
const tab = @import("chunky_tables.zig");
const Soft = @import("soft_gpu.zig").Soft;

var bufs: [2][ref.BUFFER_BYTES]u8 = undefined;
var hdrs: [2][ref.HEADER_BYTES]u8 = undefined;
var compiled: [ref.COMPILED_BYTES]u8 = undefined;
var planar: ref.Engine = undefined;
var soft: Soft = .{};
var eng: chunky.Engine(Soft) = undefined;
var want: [tab.W * tab.H]u8 = undefined;

fn expectSame(tick: usize) !void {
    tab.expand(planar.screen(), &want);
    const got = &soft.surf[eng.frontSurface()];
    if (!std.mem.eql(u8, &want, got)) {
        const i = std.mem.indexOfDiff(u8, &want, got).?;
        std.debug.print("tick {d} phase {d}: pixel ({d},{d}) is {d}, planar says {d}\n", .{ tick, planar.phase, i % tab.W, i / tab.W, got[i], want[i] });
        return error.ChunkyDiverged;
    }
}

test "lockbuster2 chunky engine == expand(planar engine) on every tick, 22000 ticks" {
    planar.init(.{ &bufs[0], &bufs[1] }, .{ &hdrs[0], &hdrs[1] }, &compiled);
    eng.init(&soft);
    var max_ops = [_]usize{0} ** 7; // per engine mode, [6] = the title slides
    var phases_seen: u8 = 0;
    while (planar.tick < 22000) {
        const mode: usize = if (planar.header_tick < ref.TITLE_TICKS) 6 else ref.mode_of_phase[@intCast(@mod(planar.phase + @intFromBool(planar.remaining == 0), ref.MAX_PHASES))];
        planar.step();
        soft.ops = 0;
        eng.step();
        eng.present();
        max_ops[mode] = @max(max_ops[mode], soft.ops);
        try expectSame(planar.tick);
        try std.testing.expectEqualSlices(u8, &want, &soft.surf[chunky.DISPLAY]);
        try std.testing.expectEqual(planar.tick, eng.tick);
        try std.testing.expectEqual(planar.phase, eng.phase);
        try std.testing.expectEqual(planar.offset, eng.offset);
        try std.testing.expectEqual(planar.header_tick, eng.header_tick);
        try std.testing.expectEqual(planar.gold, eng.gold);
        try std.testing.expectEqual(planar.color_text, eng.color_text);
        try std.testing.expectEqual(planar.new_raster, eng.new_raster);
        if (planar.phase >= 0) phases_seen |= @as(u8, 1) << @intCast(planar.phase);
    }
    try std.testing.expectEqual(@as(u8, 0xFF), phases_seen);
    // The blits a tick costs (present() included), so a regression shows here.
    std.debug.print("lockbuster2 chunky: max ops/tick per engine 0..5 + slides: {any}\n", .{max_ops});
    for (max_ops) |n| try std.testing.expect(n <= 80);
}

test "lockbuster2 chunky tables: the title banks and the font are engine.zig's bytes" {
    var h: [ref.HEADER_BYTES]u8 = undefined;
    var row: [tab.W]u8 = undefined;
    for (0..2) |bank| {
        ref.Engine.renderHeader(bank, &h);
        for (0..106) |r| {
            tab.expand(h[r * 160 ..][0..160], &row);
            try std.testing.expectEqualSlices(u8, &row, tab.headers[bank][r * tab.W ..][0..tab.W]);
        }
    }
    var g32: [32]u8 = undefined;
    for (0..ref.GLYPH_COUNT) |g| for (0..25) |y| {
        tab.expand(ref.font_bin[g * ref.GLYPH_BYTES + y * 16 ..][0..16], &g32);
        try std.testing.expectEqualSlices(u8, &g32, tab.font[y * tab.FONT_W + g * 32 ..][0..32]);
    };
}
