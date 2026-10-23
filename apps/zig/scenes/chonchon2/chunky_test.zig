// --------------------------------------------------------------------------
// The chunky compositor IS the planar picture: the reference (the planar
// Clock -- the Go's Step into a 32000-byte ST screen -- then meter.apply, the
// 4-plane decode and the sprite rows of reference.zig) and the live cart's
// path (the Live clock's ring ribbon, compose.render on the Soft backend) run
// side by side for 8000 ticks -- past the 506-frame raster program, the
// sliding panels' 34-entry script and the message loop several times, and
// through sprite-b's 192-row wrap -- under a pseudo-random YM volume stream.
// On EVERY tick the clocks' words, the ribbon line and the picture must be
// identical. The blits a frame are counted and held under a ceiling.
//
//     zig test apps/zig/scene_tests.zig --test-filter chonchon2
// --------------------------------------------------------------------------
const std = @import("std");
const clockmod = @import("clock.zig");
const ref = @import("reference.zig");
const compose = @import("compose.zig");
const gpu = @import("../chonchon/gpu.zig");

var ref_clock: clockmod.Clock = undefined;
var live: clockmod.Live = undefined;
var soft: gpu.Soft = .{};
var want: [gpu.W * gpu.H]u8 = undefined;

/// 2 copies + 1 ribbon + 2 panels + 6 meter fills + 1 sprite-a + <=4 sprite-b runs.
const MAX_OPS: usize = 16;

fn sameMotion(t: usize) !void {
    const a = ref_clock;
    const b = &live;
    const same = a.tick == b.tick and a.profile_cursor == b.profile_cursor and
        a.message_cursor == b.message_cursor and a.glyph_column == b.glyph_column and
        a.glyph_counter == b.glyph_counter and a.scroll_y == b.scroll_y and a.old_y == b.old_y and
        a.caption_cursor == b.caption_cursor and a.caption_hold == b.caption_hold and
        a.caption_wait == b.caption_wait and a.caption_shift == b.caption_shift and
        std.meta.eql(a.poses, b.poses) and std.meta.eql(a.sprite_cursor, b.sprite_cursor) and
        std.mem.eql(u8, &a.glyph, &b.glyph);
    if (!same) {
        std.debug.print("tick {d}: the live clock's words left the reference's\n", .{t});
        return error.MotionDiverged;
    }
    for (0..23) |row| for (0..320) |x| {
        if (a.ribbonByte(row, x) != b.ribbonByte(row, x)) {
            std.debug.print("tick {d}: ribbon[{d}][{d}] {d} != {d}\n", .{ t, row, x, b.ribbonByte(row, x), a.ribbonByte(row, x) });
            return error.RibbonDiverged;
        }
    };
}

test "chonchon2 chunky compositor == reference picture on every tick, 8000 ticks" {
    ref_clock = clockmod.Clock.init();
    live = clockmod.Live.init();
    compose.initSurfaces(gpu.Soft, &soft);
    var regs = [_]u8{0} ** 14;
    var seed: u32 = 7;
    var max_ops: usize = 0;
    var t: usize = 0;
    while (t < 8000) : (t += 1) {
        for (0..3) |ch| {
            seed = seed *% 1103515245 +% 12345;
            regs[8 + ch] = @truncate(seed >> 16);
        }
        ref_clock.step();
        live.step();
        try sameMotion(t);
        soft.ops = 0;
        compose.render(gpu.Soft, &soft, &live, regs);
        max_ops = @max(max_ops, soft.ops);
        ref.present(&ref_clock, regs, &want);
        if (!std.mem.eql(u8, &want, &soft.surf[gpu.SHOWN])) {
            const i = std.mem.indexOfDiff(u8, &want, &soft.surf[gpu.SHOWN]).?;
            std.debug.print("tick {d}: pixel ({d},{d}) is {d}, reference {d}\n", .{ t, i % gpu.W, i / gpu.W, soft.surf[gpu.SHOWN][i], want[i] });
            return error.ChunkyDiverged;
        }
    }
    std.debug.print("chonchon2: 8000 ticks identical, at most {d} blits a frame\n", .{max_ops});
    try std.testing.expect(max_ops <= MAX_OPS);
}
