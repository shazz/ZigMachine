// --------------------------------------------------------------------------
// The compositor and the one-pass colour bank ARE the reference: the Go's
// two-pass GlyphWindow, the 64 KB ribbon body redrawn every tick and the
// per-pixel shader of reference.zig run beside colorbank.build and
// compose.render (Soft backend) for 6000 ticks -- many trail pauses (every 320
// ticks) and velocity bounces, the message window many times over -- under a
// pseudo-random Batman volume stream. On EVERY tick the colour bank's 1600
// words and the shown picture must be identical.
//
//     zig test apps/zig/scene_tests.zig --test-filter larcociel5
// --------------------------------------------------------------------------
const std = @import("std");
const assets = @import("assets.zig");
const Clock = @import("clock.zig").Clock;
const colorbank = @import("colorbank.zig");
const compose = @import("compose.zig");
const ref = @import("reference.zig");
const gpu = @import("../chonchon/gpu.zig");

var soft: gpu.Soft = .{};
var bank: colorbank.Bank = .{};
var ref_bank: ref.RefBank = .{};
var body: [gpu.W * gpu.H]u8 = undefined;
var want: [gpu.W * gpu.H]u8 = undefined;

test "larcociel5 compositor + colour bank == reference on every tick, 6000 ticks" {
    var clock = Clock.init(assets.initial_motion, assets.initial_history);
    compose.initSurfaces(gpu.Soft, &soft);
    bank.clear();
    var seed: u32 = 3;
    var max_ops: usize = 0;
    var t: usize = 0;
    while (t < 6000) : (t += 1) {
        clock.step();
        var meters: [3]u8 = undefined;
        for (&meters) |*m| {
            seed = seed *% 1103515245 +% 12345;
            m.* = @max(1, @as(u8, @truncate(seed >> 16)) & 15);
        }
        bank.build(clock.tick);
        ref_bank.build(clock.tick);
        try std.testing.expectEqualSlices(u32, &ref_bank.colors, &bank.colors);

        soft.ops = 0;
        compose.render(gpu.Soft, &soft, &clock, meters);
        max_ops = @max(max_ops, soft.ops);
        ref.buildBody(&clock, &body);
        ref.present(&want, &body, meters, true);
        if (!std.mem.eql(u8, &want, &soft.surf[gpu.SHOWN])) {
            const i = std.mem.indexOfDiff(u8, &want, &soft.surf[gpu.SHOWN]).?;
            std.debug.print("tick {d}: pixel ({d},{d}) is {d}, reference {d}\n", .{ t, i % gpu.W, i / gpu.W, soft.surf[gpu.SHOWN][i], want[i] });
            return error.ChunkyDiverged;
        }
    }
    std.debug.print("larcociel5: 6000 ticks identical, {d} blits a frame\n", .{max_ops});
    try std.testing.expect(max_ops <= 2);
}

test "larcociel5 boot frame: the BG surface is the reference picture with no ribbon and no bat" {
    compose.initSurfaces(gpu.Soft, &soft);
    @memset(&body, 0);
    ref.present(&want, &body, .{ 1, 1, 1 }, false);
    try std.testing.expectEqualSlices(u8, &want, &soft.surf[gpu.BG]);
}
