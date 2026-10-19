// --------------------------------------------------------------------------
// The six engines (and the two title slides), checked against the REAL
// machine. The Go production's TestNativeDisplayCheckpoints holds its clock's
// screen memory at seven named ticks against gzipped RAM snapshots of the
// original 68000 routines (internal/source/testdata/); the same seven sha256s
// hold this transcription, run natively through apps/zig/scene_tests.zig:
//
//     zig test apps/zig/scene_tests.zig --test-filter lockbuster2
//
// The clocks' zg.mem ring is lent here as static arrays, the way
// rno_natrium/verify_test.zig lends the natrium screens.
// --------------------------------------------------------------------------
const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;

// The cart takes these from zg.mem; a native test has no arena, so it lends
// the scene its own before a test that reaches them.
var test_buffers: [2][engine_mod.BUFFER_BYTES]u8 = .{ [_]u8{0} ** engine_mod.BUFFER_BYTES, [_]u8{0} ** engine_mod.BUFFER_BYTES };
var test_headers: [2][engine_mod.HEADER_BYTES]u8 = .{ [_]u8{0} ** engine_mod.HEADER_BYTES, [_]u8{0} ** engine_mod.HEADER_BYTES };
var test_compiled: [engine_mod.COMPILED_BYTES]u8 = undefined;

var test_engine: Engine = undefined;

// The Go tree's checkpoints.json, quoted (header + all six copy-maps).
const CHECKPOINTS = [_]struct { name: []const u8, tick: usize, want: [64]u8 }{
    .{ .name = "header", .tick = 610, .want = "0c92bddb4e96f3ea9ec9f0f64a668255a6c15527ac09f6f119cafde60c7c4a39".* },
    .{ .name = "map-0", .tick = 809, .want = "bffe73a61077850d27a9e2202cb7a4ca04036bd9b58a8c6e814f6461d360d838".* },
    .{ .name = "map-1", .tick = 1525, .want = "3a7c93b1b1b76ba24fe6a84c6838e97c2787c99d907c118b6de1aac86012b5b1".* },
    .{ .name = "map-2", .tick = 2245, .want = "a234eca35233a90c4529e0f903dbb9c8e79b2c9162a59022fcc9c8f400d4146f".* },
    .{ .name = "map-3", .tick = 3041, .want = "96f568f44fe73da24eb69b3b302bb56d5d4edd1017b9e39949995d7f56f5b4ae".* },
    .{ .name = "map-4", .tick = 3725, .want = "6f7e1d4fa5c216465779457999fc1bdf6e797844e81b95d68fc322111920ca6d".* },
    .{ .name = "map-5", .tick = 5077, .want = "ae6ff009393e70804bee29083950ac7f748675ecd4389845204fcef1ada9c76c".* },
};

const hexDigits = "0123456789abcdef";

fn sha256(b: []const u8) [64]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(b, &out, .{});
    var text: [64]u8 = undefined;
    for (out, 0..) |v, i| {
        text[i * 2] = hexDigits[v >> 4];
        text[i * 2 + 1] = hexDigits[v & 15];
    }
    return text;
}

test "lockbuster2 engines: the seven RAM checkpoints of the original machine" {
    test_engine.init(.{ &test_buffers[0], &test_buffers[1] }, .{ &test_headers[0], &test_headers[1] }, &test_compiled);
    var held: usize = 0;
    while (held < CHECKPOINTS.len) {
        test_engine.step();
        if (test_engine.tick == CHECKPOINTS[held].tick) {
            const cp = CHECKPOINTS[held];
            const got = sha256(test_engine.screen());
            try std.testing.expectEqualStrings(&cp.want, &got);
            held += 1;
        }
    }
}

test "lockbuster2 engines: one full sequence and a restart (Go's regression)" {
    test_engine.init(.{ &test_buffers[0], &test_buffers[1] }, .{ &test_headers[0], &test_headers[1] }, &test_compiled);
    while (test_engine.tick < 22000) test_engine.step();
    // Go's TestCompleteSequenceAndRestart: after 22000 ticks the header is
    // done (header_tick stands at 610) and the phase is still in 0..7, with
    // the flags the phases set all reachable (gold is on from bank 1 on).
    try std.testing.expectEqual(@as(usize, 22000), test_engine.tick);
    try std.testing.expectEqual(@as(usize, 610), test_engine.header_tick);
    try std.testing.expect(test_engine.phase >= 0 and test_engine.phase < engine_mod.MAX_PHASES);
    try std.testing.expectEqual(@as(bool, true), test_engine.gold); // the slides and phases 1/3/5 turned it on last
}
