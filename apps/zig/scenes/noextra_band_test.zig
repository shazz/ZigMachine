// noextra_band.row computes the rainbow's colour instead of loading it: it must
// write exactly the bytes of the table loop it replaced (clamped raster.raw
// lookup, 4 px a word) for every row start the band can reach and beyond.
//
//     zig test apps/zig/scene_tests.zig --test-filter noextra
const std = @import("std");
const band = @import("noextra_band.zig");

const raster = @embedFile("../assets/screens/noextra/raster.raw");
const STEP: i32 = @intFromFloat(2.0 / 1.8 * 65536.0); // noextra.zig SRC_STEP_FX
const WORDS = 100; // 400 columns

// The loop noextra.zig ran before (bb4940ee), verbatim but for the names.
fn reference(words: []u32, start: i32) void {
    var u = start;
    for (words) |*wp| {
        var w: u32 = 0;
        inline for (0..4) |k| {
            const c: i32 = @min(@max(u >> 16, 0), @as(i32, raster.len) - 1);
            w |= @as(u32, raster[@intCast(c)]) << (8 * k);
            u += STEP;
        }
        wp.* = w;
    }
}

fn expectSame(start: i32) !void {
    var got: [WORDS]u32 = undefined;
    var want: [WORDS]u32 = undefined;
    band.row(&got, start, STEP, raster);
    reference(&want, start);
    try std.testing.expectEqualSlices(u32, &want, &got);
}

test "noextra band: computed ramp == table lookup, every reachable row start" {
    // The band's starts are 94.4 px -/+ 125 (two sine amplitudes, 75 + 50):
    // about -31..220 px. Sweep -300..1000 px every 1/64 px, both ends clamped.
    var u: i32 = -300 << 16;
    while (u < 1000 << 16) : (u += 1 << 10) try expectSame(u);
    // and every fractional position around the two edges, where the fast path hands over
    u = -(8 << 16);
    while (u < 8 << 16) : (u += 1) try expectSame(u);
    const right: i32 = (@as(i32, raster.len) << 16) - (WORDS * 4 - 1) * STEP;
    u = right - (8 << 16);
    while (u < right + (8 << 16)) : (u += 7) try expectSame(u);
}

test "noextra band: random row starts" {
    var rng = std.Random.DefaultPrng.init(198);
    for (0..200_000) |_| try expectSame(rng.random().intRangeAtMost(i32, -400 << 16, 1100 << 16));
}
