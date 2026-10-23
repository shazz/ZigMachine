// --------------------------------------------------------------------------
// The chunky compositor IS the planar picture: the reference (Clock.step with
// its 32000-byte background copy, the Go's per-pixel meter loop, the
// per-pixel decode + logo of reference.zig) and the live cart's path
// (compose.tick's dirty restore + Clock.advance + the word-OR meter, then
// compose.render on the Soft backend) run side by side for 7000 ticks -- past
// the scroller wave's wrap (~1458 ticks), the logo path's (~3333) and the
// message loop many times -- under a pseudo-random YM volume stream. On EVERY
// tick the live planar screen must equal the reference's byte for byte, and
// on every rendered tick the shown surface must equal the reference picture.
// Every 7th tick is not rendered (a 60 Hz host frame that ran two 50 Hz
// ticks). The blits a frame are counted and held under a ceiling.
//
//     zig test apps/zig/scene_tests.zig --test-filter chonchon
// --------------------------------------------------------------------------
const std = @import("std");
const Clock = @import("clock.zig").Clock;
const ref = @import("reference.zig");
const meter = @import("meter.zig");
const dirty = @import("dirty.zig");
const compose = @import("compose.zig");
const gpu = @import("gpu.zig");

var ref_clock: Clock = undefined;
var live: Clock = undefined;
var soft: gpu.Soft = .{};
var want: [gpu.W * gpu.H]u8 = undefined;

/// 2 copies + up to 63 logo rows.
const MAX_OPS: usize = 65;

fn volumes(seed: *u32, regs: *[14]u8) void {
    for (0..3) |ch| {
        seed.* = seed.* *% 1103515245 +% 12345;
        const v: u8 = @truncate(seed.* >> 16);
        regs[8 + ch] = if (v & 0x30 == 0) 0 else v; // silence a quarter of the time
    }
}

test "chonchon chunky compositor == reference picture on every tick, 7000 ticks" {
    ref_clock = Clock.init();
    live = Clock.init();
    compose.initBackground(gpu.Soft, &soft);
    @memset(&soft.surf[gpu.SHOWN], 0);
    var regs = [_]u8{0} ** 14;
    var heights = [_]u8{ 0, 0, 0 };
    var seed: u32 = 1;
    var max_ops: usize = 0;
    var t: usize = 0;
    while (t < 7000) : (t += 1) {
        volumes(&seed, &regs);
        ref_clock.step();
        ref.meterApply(ref_clock.screen[0..], regs);
        compose.tick(&live, heights, regs, meter.apply);
        heights = dirty.meterHeights(regs);
        if (!std.mem.eql(u8, &ref_clock.screen, &live.screen)) {
            const i = std.mem.indexOfDiff(u8, &ref_clock.screen, &live.screen).?;
            std.debug.print("tick {d}: planar byte {d} is {d}, reference {d}\n", .{ t, i, live.screen[i], ref_clock.screen[i] });
            return error.PlanarDiverged;
        }
        if (t % 7 == 3) continue;
        soft.ops = 0;
        compose.render(gpu.Soft, &soft, &live, heights);
        max_ops = @max(max_ops, soft.ops);
        ref.present(&ref_clock, &want);
        if (!std.mem.eql(u8, &want, &soft.surf[gpu.SHOWN])) {
            const i = std.mem.indexOfDiff(u8, &want, &soft.surf[gpu.SHOWN]).?;
            std.debug.print("tick {d}: pixel ({d},{d}) is {d}, reference {d}\n", .{ t, i % gpu.W, i / gpu.W, soft.surf[gpu.SHOWN][i], want[i] });
            return error.ChunkyDiverged;
        }
    }
    std.debug.print("chonchon: 7000 ticks identical, at most {d} blits a frame\n", .{max_ops});
    try std.testing.expect(max_ops <= MAX_OPS);
}

test "chonchon word-OR meter == the Go's per-pixel meter for every volume" {
    for (0..16) |v| {
        var a: [32000]u8 = undefined;
        for (&a, 0..) |*b, i| b.* = @truncate(i *% 2654435761 >> 13);
        var b = a;
        var regs = [_]u8{0} ** 14;
        regs[8] = @intCast(v);
        regs[9] = @intCast(15 - v);
        regs[10] = @intCast((v * 7) % 16);
        meter.apply(&a, regs);
        ref.meterApply(&b, regs);
        try std.testing.expectEqualSlices(u8, &b, &a);
    }
}
