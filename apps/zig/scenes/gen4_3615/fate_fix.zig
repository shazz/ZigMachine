// --------------------------------------------------------------------------
// dancingFate()'s curves in fixed point: y and z of the 113 slices in Q32
// (fate_place.zig turns them into x, y and width). No float runs per frame.
//
// screen.js turns its angles in doubles; the f64 port cost ~0.4 Mc a frame of
// soft-float on ZIGGY. Here an angle is a u64 phase (2^64 = one turn) that
// fate.zig steps once a frame; its sine comes from a 1024-entry Q30 table and
// a Taylor step for the remainder (sincos, error ~2^-30). Each slice's rotor
// is that base rotor times a comptime cos/sin table of k * INC in Q30. Against
// the f64 placement y and z differ by ~1e-8 px, so the truncated x, y and
// width agree but where the f64 value sits right on an integer; there they may
// differ by 1 (fate_test.zig counts them).
// --------------------------------------------------------------------------
const std = @import("std");
const fate = @import("fate.zig");
const C = @import("fate_curve.zig");
const trig = @import("trig.zig");

const SLICES = C.SLICES;
pub const ONE: i64 = 1 << 32; // Q32

pub const R30 = trig.R30;

/// The rotors a waveform turns per slice: fate_curve.zig curve()'s starts.
pub const Base = struct { a: R30, b: R30 };

/// u32 angle (2^32 = one turn) of a u64 phase times m.
fn ang(p: u64, comptime m: u64) u32 {
    return trig.angle(p *% m);
}

pub fn base(f: *const fate.Fate) Base {
    const h = f.half;
    return switch (f.wave) {
        0, 4 => .{ .a = trig.sincos(ang(h, 2)), .b = undefined },
        1 => .{ .a = trig.sincos(ang(h, 3)), .b = trig.sincos(ang(h, 1)) },
        2 => .{ .a = trig.sincos(ang(f.third, 1)), .b = undefined },
        3 => .{ .a = trig.sincos(ang(h, 1)), .b = trig.sincos(ang(h, 1) -% THIRD_TURN) }, // a - 2 PI / 3
        else => .{ .a = trig.sincos(ang(h, 1)), .b = undefined },
    };
}
const THIRD_TURN: u32 = 0x5555_5555; // 2^32 / 3, rounded down: 2 PI / 3 to 1.5e-9 rad

/// Phase steps a frame (fateCtr / 2 and fateCtr / 1.5 in turns, times 2^64).
pub const HALF_STEP: u64 = trig.phase(C.SPEED / 2);
pub const THIRD_STEP: u64 = trig.phase(C.SPEED / 1.5);

fn q30(v: f64) i32 {
    return @intFromFloat(@round(v * (1 << 30)));
}

/// t[k] = (cos, sin)(k * inc), the rotor slice 112 - k turns its base by.
fn table(comptime inc: f64) [SLICES]R30 {
    @setEvalBranchQuota(20000);
    var t: [SLICES]R30 = undefined;
    for (&t, 0..) |*r, k| {
        const a = inc * @as(f64, @floatFromInt(k));
        r.* = .{ .c = q30(@cos(a)), .s = q30(@sin(a)) };
    }
    return t;
}
const T_INC = table(C.INC);
const T_INC2 = table(C.INC * 2);
const T_INC5 = table(C.INC * 5);
const T_INC_HALF = table(C.INC / 2);

/// i / 3 and (112 - i) / 10 in Q32, rounded.
const THIRDS = ratio(3, 0, 1);
const TENTHS = ratio(10, 112, -1);
fn ratio(comptime den: i64, comptime from: i64, comptime sign: i64) [SLICES]i64 {
    var t: [SLICES]i64 = undefined;
    for (&t, 0..) |*v, i| v.* = @divFloor((from + sign * @as(i64, i)) * ONE * 2 + den, 2 * den);
    return t;
}

/// Base turned by t, both components in Q32.
fn turn(b: R30, t: R30) [2]i64 {
    const bc: i64 = b.c;
    const bs: i64 = b.s;
    return .{ (bc * t.c - bs * t.s) >> 28, (bs * t.c + bc * t.s) >> 28 };
}

/// A slice's y and z in Q32.
pub const P = struct { y: i64, z: i64 };

/// fate_curve.zig's positions in Q32, pos[i] by index; img[i] is the slice's
/// source row pair (112 - i on the carpet).
pub fn positions(wave: u8, bs: Base, pos: *[SLICES]P, img: *[SLICES]u8) void {
    if (wave == 2) return flat(bs, pos, img);
    const a = bs.a;
    const b = bs.b;
    for (pos, img, 0..) |*p, *m, i| {
        const k = SLICES - 1 - i;
        m.* = @intCast(i);
        p.* = switch (wave) {
            0 => blk: { // ROLL
                const r = turn(a, T_INC[k]);
                break :blk .{ .y = 40 * ONE + 40 * r[0], .z = 10 * r[1] };
            },
            1 => .{ .y = @as(i64, @intCast(i)) * ONE, .z = 20 * ONE + 5 * turn(a, T_INC5[k])[0] + 12 * turn(b, T_INC_HALF[k])[0] },
            3 => .{ .y = 50 * ONE + 50 * turn(a, T_INC[k])[0], .z = 20 * ONE + 20 * turn(b, T_INC[k])[1] },
            4 => blk: { // FLIGHING CARPET
                m.* = @intCast(k);
                break :blk .{ .y = 70 * ONE + 20 * turn(a, T_INC2[k])[0] - THIRDS[i], .z = TENTHS[i] };
            },
            5 => .{ .y = 50 * ONE + 60 * turn(a, T_INC[k])[0], .z = TENTHS[i] },
            else => unreachable, // 2 is flat()
        };
    }
}

/// Waveform 2: from (50 + 30c, 20s) to (50 - 30c, -20s) in 112 equal steps,
/// stepped out from the middle slice, which sits at (50, 0) exactly. (The JS
/// steps from one end in doubles: its middle slice lands a rounding error
/// either side of x 243 and width 264, so its x and width flip by 1 px from
/// frame to frame; here they hold.)
fn flat(bs: Base, pos: *[SLICES]P, img: *[SLICES]u8) void {
    const c: i64 = @as(i64, bs.a.c) << 2;
    const s: i64 = @as(i64, bs.a.s) << 2;
    const iy = @divTrunc(30 * c, MID);
    const iz = @divTrunc(20 * s, MID);
    for (pos, img, 0..) |*p, *m, i| {
        m.* = @intCast(i);
        const k = MID - @as(i64, @intCast(i));
        p.* = .{ .y = 50 * ONE + k * iy, .z = k * iz };
    }
}
const MID = (SLICES - 1) / 2;
