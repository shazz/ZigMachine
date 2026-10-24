// --------------------------------------------------------------------------
// The fixed-point FATE placement (fate_fix.zig, fate_place.zig) against the
// f64 one (fate_curve.zig, screen.js's doubles) on every frame of every
// waveform. They differ only where an f64 value sits right on an integer, by
// 1 px at most: the test says how often, and fails on anything bigger.
// --------------------------------------------------------------------------
const std = @import("std");
const fate = @import("fate.zig");
const C = @import("fate_curve.zig");
const fix = @import("fate_fix.zig");
const zorder = @import("zorder.zig");
const trig = @import("trig.zig");

const FRAMES = 40_000; // a waveform runs ~600 frames in the demo; this is every angle many times

const Diff = struct { frames: usize = 0, values: usize = 0, order: usize = 0, max: i32 = 0 };

/// The f64 slices the old cart drew, from rotors turned in f64 as screen.js turns its angles.
fn reference(wave: u8, half: C.Rot, third: C.Rot, out: *[fate.SLICES]fate.Slice) void {
    var pos: [fate.SLICES]C.Pos = undefined;
    C.curve(wave, half, third, &pos, fate.SLICES);
    var order: [fate.SLICES]u8 = undefined;
    zorder.sort(fate.SLICES, &pos, &order);
    for (out, order) |*s, k| s.* = C.sliceOf(pos[k]);
}

fn run(wave: u8) !Diff {
    var f: fate.Fate = undefined;
    f.init();
    f.logoFate();
    for (0..wave) |_| f.logoWaveform();
    var half = C.Rot{ .c = 1, .s = 0 };
    var third = C.Rot{ .c = 1, .s = 0 };
    var d = Diff{};
    for (0..FRAMES) |_| {
        var want: [fate.SLICES]fate.Slice = undefined;
        reference(f.wave, half, third, &want);
        f.step();
        half = half.turn(C.HALF_ROT);
        third = third.turn(C.THIRD_ROT);
        var by_img: [fate.SLICES]fate.Slice = undefined; // the f64 slices by source row
        for (want) |s| by_img[s.i] = s;
        var differs = false;
        for (f.slices, want) |got, w| {
            const r = by_img[got.i];
            const m = @max(@abs(got.x - r.x), @abs(got.y - r.y), @abs(got.l - r.l));
            d.max = @max(d.max, @as(i32, @intCast(m)));
            if (m != 0) d.values += 1;
            if (got.i != w.i) d.order += 1;
            differs = differs or m != 0 or got.i != w.i;
        }
        if (differs) d.frames += 1;
    }
    return d;
}

test "fixed-point slices are the f64 slices, or 1 px off, on every frame of all six waveforms" {
    for (0..6) |w| {
        const d = try run(@intCast(w));
        std.debug.print("wave {d}: {d} of {d} frames differ; {d} slice values off by <= {d}, {d} draw slots reordered\n", .{ w, d.frames, FRAMES, d.values, d.max, d.order });
        try std.testing.expect(d.max <= 1);
        // the flat logo's middle slice is at z = 0 in the maths: the JS's
        // doubles put it a rounding error either side, x 243 or 242 by the
        // frame; the fixed point holds it at 243 (fate_fix.zig flat())
        if (w != 2) try std.testing.expect(d.frames * 100 < FRAMES); // under 1 % of frames
    }
}

const TOL: f64 = 1.0 / 268435456.0; // 2^-28

test "sincos is the sine and cosine to 2^-28" {
    var a: u32 = 0;
    for (0..200_000) |_| {
        const r = trig.sincos(a);
        const x = @as(f64, @floatFromInt(a)) / 4294967296.0 * 2 * std.math.pi;
        try std.testing.expect(@abs(@as(f64, @floatFromInt(r.c)) / (1 << 30) - @cos(x)) < TOL);
        try std.testing.expect(@abs(@as(f64, @floatFromInt(r.s)) / (1 << 30) - @sin(x)) < TOL);
        a +%= 2_147_483_647 / 100_000 * 3 + 12_345;
    }
}

test "the VU meter's integer levels are the f64 meter's, or 1 off" {
    const vu = @import("vu.zig");
    var m: vu.Meter = undefined;
    m.init();
    var levels: [3]i32 = @splat(0);
    var last: [3]f64 = @splat(0); // the old cart's maths (screen.js 351-365)
    var want: [3]i32 = @splat(0);
    var regs: [16]u8 = @splat(0);
    var seed: u32 = 1;
    var off: usize = 0;
    for (0..100_000) |n| {
        for (regs[8..11]) |*r| {
            seed = seed *% 1_103_515_245 +% 12_345;
            r.* = if (n % 7 < 3) @intCast(seed >> 28) else 0; // bursts, then decay
        }
        m.step(&regs, .{ 2, 1, 0 }, &levels);
        for (&last, regs[8..11]) |*l, reg| l.* = @max(@as(f64, @floatFromInt(reg & 0xf)) * 100 / 0xf, l.* * 0.9);
        for (&want, [3]usize{ 2, 1, 0 }) |*w, voice| {
            const v: i32 = @intFromFloat(@trunc(last[voice] * 1.8));
            w.* = if (w.* < v) v else @max(w.* - 6, 0);
        }
        for (levels, want) |a, b| {
            try std.testing.expect(@abs(a - b) <= 1);
            if (a != b) off += 1;
        }
    }
    std.debug.print("VU: {d} of 300000 levels 1 off\n", .{off});
}
