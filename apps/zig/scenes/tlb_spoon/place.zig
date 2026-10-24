// --------------------------------------------------------------------------
// THE LOST BOYS / TWIDDLE DEMO — where each scroller letter lands, in fixed
// point (screen.js:322-364; the geometry is described above NB_LETTERS in
// tlb_spoon.zig). The two rotations come from the Q30 rotors of trig.zig and
// a comptime table of the letter's small tilt: no float per frame on ZIGGY
// (the remake's doubles are not the original's maths).
// --------------------------------------------------------------------------
const std = @import("std");
const trig = @import("trig.zig");
const letter = @import("letter.zig");
const Letter = letter.Letter;
const Frame = letter.Frame;

const ONE: i32 = 1 << 16;

/// Before the first theta exists the letters go up 1:1 at (-40, 0).
pub const identity = Frame{ .ct = ONE, .st = 0, .cx = -40 << 16, .cy = 0, .sx = 0, .sy = 0, .ct30 = 1 << 30, .st30 = 0 };

/// translate(200,100); rotate(theta); translate(-200,-120), drawn at (-40,0).
pub fn shownThrough(th: trig.Rotor) Frame {
    return .{
        .ct = q30to16(th.c),
        .st = q30to16(th.s),
        .cx = 160 << 16,
        .cy = 100 << 16,
        .sx = 200 << 16,
        .sy = 120 << 16,
        .ct30 = th.c,
        .st30 = th.s,
    };
}

inline fn q30to16(v: i64) i32 {
    return @intCast((v + (1 << 13)) >> 14);
}

// The letter's own tilt is -25 deg * sin(phase) (screen.js: sin * -50 * 0.5
// degrees). sin(phase) in [-1, 1] -> 2049 steps of (cos, sin) Q30, built at
// comptime: a step is 2.1e-4 rad, under 3e-3 px at the glyph's far corner.
const TILT_STEPS = 1024;
const Tilt = struct { c: i32, s: i32 };
const TILT: [2 * TILT_STEPS + 1]Tilt = blk: {
    @setEvalBranchQuota(100_000);
    var t: [2 * TILT_STEPS + 1]Tilt = undefined;
    for (&t, 0..) |*e, i| {
        const v = (@as(f64, @floatFromInt(i)) - TILT_STEPS) / TILT_STEPS;
        const a = v * -50.0 * 0.5 * (std.math.pi / 180.0);
        e.* = .{ .c = trig.q30(@cos(a)), .s = trig.q30(@sin(a)) };
    }
    break :blk t;
};

/// Glyph `tile` at scroll-canvas (scx, 50 cos(phase) + 90), tilted by the
/// phase, seen through frame f.
pub fn place(tile: u16, scx: i32, phase: trig.Rotor, f: Frame) Letter {
    const scy: i64 = ((@as(i64, 50) * phase.c) >> 14) + (90 << 16);
    const ti = @min(2 * TILT_STEPS, @max(0, (@as(i64, phase.s) + (1 << 30) + (1 << 19)) >> 20));
    const la = &TILT[@intCast(ti)];
    const dx: i64 = (@as(i64, scx) << 16) - f.sx;
    const dy: i64 = scy - f.sy;
    const ct: i64 = f.ct30;
    const st: i64 = f.st30;
    const half: i64 = 1 << 29;
    return .{
        .tile = tile,
        .ox = f.cx + @as(i32, @intCast((ct * dx - st * dy + half) >> 30)),
        .oy = f.cy + @as(i32, @intCast((st * dx + ct * dy + half) >> 30)),
        .cb = q30to16((ct * la.c - st * la.s + half) >> 30),
        .sb = q30to16((st * la.c + ct * la.s + half) >> 30),
    };
}
