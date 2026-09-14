// Tests for effects/ballfield.zig against codef_bobfield.js's arithmetic, with
// the TNT1 screen's field: 640x400, centre (320,200), speed 2, ratio 60, 17 tiles.
const std = @import("std");
const bf = @import("ballfield.zig");
const expectEqual = std.testing.expectEqual;

const TNT1 = bf.Params{ .w = 640, .h = 400, .centx = 320, .centy = 200, .speed = 2.0, .ratio = 60, .tiles = 17 };

test "spawn places a ball the way the constructor does" {
    const f = bf.Field.init(TNT1);
    const b = f.spawn(.{ 0.5, 0.25, 0.999 });
    try expectEqual(@as(f64, 0.5 * 640 * 2 - 640 + 10), b.x); // 10
    try expectEqual(@as(f64, 0.25 * 400 * 2 - 400 + 10), b.y); // -190
    try expectEqual(@as(f64, 519), b.z); // Math.round(0.999 * 520)
}

test "the first step never draws: the last projection is (0,0)" {
    const f = bf.Field.init(TNT1);
    var b = f.spawn(.{ 0.5, 0.5, 0.5 });
    try expectEqual(@as(?bf.Draw, null), f.step(&b));
    try expectEqual(@as(f64, 258), b.z);
    const x: f64 = 10; // f64 arithmetic, as the JS; a comptime_float would be f128
    const z: f64 = 258;
    try expectEqual(320 + (x / z) * 60, b.px);
}

test "the second step draws the first projection with the new depth's tile" {
    const f = bf.Field.init(TNT1);
    var b = f.spawn(.{ 0.5, 0.5, 0.5 });
    _ = f.step(&b);
    const px = b.px;
    const d = f.step(&b).?;
    try expectEqual(px, d.x);
    try expectEqual(@as(u32, 8), d.tile); // round(256 / (520/17)) = round(8.37)
}

test "z reaching exactly 0 still draws; its x/0 projection never does" {
    const f = bf.Field.init(TNT1);
    var b = f.spawn(.{ 0.5, 0.5, 0 });
    b.z = 2;
    b.px = 100;
    b.py = 100;
    const d = f.step(&b).?; // 0 is not < 0: no wrap
    try expectEqual(@as(f64, 100), d.x);
    try expectEqual(@as(u32, 0), d.tile);
    try expectEqual(@as(?bf.Draw, null), f.step(&b)); // wraps to 518, and last time was x/0
    try expectEqual(@as(f64, 518), b.z);
}

test "the far plane rounds to tile 17, one past a 17-tile sheet" {
    const f = bf.Field.init(TNT1);
    var b = f.spawn(.{ 0.5, 0.5, 0 });
    b.z = 522; // was spawned at most 520; 520 after the step is not > 520
    b.px = 10;
    b.py = 10;
    try expectEqual(@as(u32, 17), f.step(&b).?.tile);
}

test "a projection on the canvas edge is not drawn (strict edges)" {
    const f = bf.Field.init(TNT1);
    var b = f.spawn(.{ 0.5, 0.5, 0.5 });
    b.px = 640;
    b.py = 10;
    try expectEqual(@as(?bf.Draw, null), f.step(&b));
    b.px = 639.5;
    b.py = 0;
    try expectEqual(@as(?bf.Draw, null), f.step(&b));
    b.px = 639.5;
    b.py = 0.5;
    try expectEqual(@as(f64, 639.5), f.step(&b).?.x);
}

test "a ball leaving the side wraps and skips that step" {
    const f = bf.Field.init(TNT1);
    var b = f.spawn(.{ 0.5, 0.5, 0.5 });
    b.x = 641; // > 320 << 1
    b.px = 10;
    b.py = 10;
    try expectEqual(@as(?bf.Draw, null), f.step(&b));
    try expectEqual(@as(f64, 641 - 1280), b.x);
}

test "xorshift32 matches the JS stand-in's first values" {
    var r = bf.XorShift32.init(0x1d872b41);
    const first = r.next();
    try std.testing.expect(first >= 0 and first < 1);
    var s: u32 = 0x1d872b41;
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    try expectEqual(@as(f64, @floatFromInt(s)) / 4294967296.0, first);
}
