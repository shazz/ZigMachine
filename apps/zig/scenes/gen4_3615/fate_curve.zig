// --------------------------------------------------------------------------
// dancingFate()'s maths in f64, exactly as the JS numbers (screen.js 242-338):
// the six curves, then the perspective. The cart does not run it: it is the
// reference fate_test.zig holds the fixed-point placement (fate_fix.zig,
// fate_place.zig) to, and fate_place.zig's compile-time tables use it.
// --------------------------------------------------------------------------
const std = @import("std");

pub const SLICES = 113; // i = 0..112
pub const SPEED: f64 = 0.095; // fateSpeed
pub const INC: f64 = 0.018; // fateInc
const PERSP: f64 = 200; // fatePersp
pub const TOP = 286; // drawImage(..., ~~x, 286 + ~~y, ~~l, 2)
// Math.PI as a JS number, typed f64 so it rounds as the JS does.
const PI: f64 = std.math.pi;

/// A unit vector turned by constant angles. Every waveform's angle is the
/// frame counter plus a constant per slice, so the frame needs no sin/cos:
/// the persistent rotors below are turned once a frame and each slice turns
/// a copy by INC. The errors (~1e-15 a slice, ~1e-12 over a lap of the demo)
/// sit below the JavaScript's own rounding; the gate replays 30000 frames.
pub const Rot = struct {
    c: f64,
    s: f64,

    pub fn of(a: f64) Rot {
        return .{ .c = @cos(a), .s = @sin(a) }; // comptime constants only
    }

    pub fn turn(r: Rot, by: Rot) Rot {
        return .{ .c = r.c * by.c - r.s * by.s, .s = r.s * by.c + r.c * by.s };
    }

    pub fn double(r: Rot) Rot {
        return .{ .c = r.c * r.c - r.s * r.s, .s = 2 * r.s * r.c };
    }
};
pub const INC_ROT = Rot.of(INC);
pub const INC2_ROT = Rot.of(INC * 2);
pub const INC5_ROT = Rot.of(INC * 5);
pub const INC_HALF_ROT = Rot.of(INC / 2);
pub const HALF_ROT = Rot.of(SPEED / 2); // ctr / 2 per frame
pub const THIRD_ROT = Rot.of(SPEED / 1.5); // ctr / 1.5 per frame
pub const SIN_120 = @sin(2 * PI / 3);
pub const COS_120 = @cos(2 * PI / 3);

/// One slice as drawImage places it, in canvas pixels.
pub const Slice = struct { i: u8, x: i32, y: i32, l: i32 };
pub const Pos = struct { i: u8, y: f64, z: f64 };

/// Where drawImage puts the slice at p: x, y and width (screen.js 330-336).
pub fn sliceOf(p: Pos) Slice {
    return .{
        .i = p.i,
        .x = trunc(600 * PERSP / (p.z + PERSP) - 357),
        .y = TOP + trunc(p.y * PERSP / (p.z + PERSP)),
        .l = trunc(264 + 5.6 * p.z),
    };
}

/// How many walk steps reach pos[i].
pub fn walkStep(wave: u8, i: usize) usize {
    return if (wave == 2) i else SLICES - 1 - i;
}

pub fn trunc(v: f64) i32 {
    return @intFromFloat(@trunc(v));
}

/// The six waveforms (screen.js 248-323), filling pos[i] by index. `half` and
/// `third` are the rotors of fateCtr / 2 and fateCtr / 1.5. Each walks one
/// rotor (or sum) slice to slice; only its first `steps` slices are filled
/// (walk order: i = 112 down, i = 0 up on the flat one, see `walkStep`).
pub fn curve(wave: u8, half: Rot, third: Rot, pos: *[SLICES]Pos, steps: usize) void {
    const end = SLICES - steps; // the walks downwards stop above it
    switch (wave) {
        0 => { // ROLL
            var a = half.double();
            var i: usize = SLICES;
            while (i > end) : (a = a.turn(INC_ROT)) {
                i -= 1;
                pos[i] = .{ .i = @intCast(i), .y = 40 + 40 * a.c, .z = 10 * a.s };
            }
        },
        1 => {
            var a = half.double().turn(half); // ctr * 1.5
            var b = half;
            var i: usize = SLICES;
            while (i > end) : ({
                a = a.turn(INC5_ROT);
                b = b.turn(INC_HALF_ROT);
            }) {
                i -= 1;
                pos[i] = .{ .i = @intCast(i), .y = @floatFromInt(i), .z = 20 + 5 * a.c + 12 * b.c };
            }
        },
        2 => rotatingFlat(third, pos[0..steps]),
        3 => { // BIG WAVE
            var a = half;
            var i: usize = SLICES;
            while (i > end) : (a = a.turn(INC_ROT)) {
                i -= 1;
                const shifted = a.s * COS_120 - a.c * SIN_120; // sin(a - 2 PI / 3)
                pos[i] = .{ .i = @intCast(i), .y = 50 + 50 * a.c, .z = 20 + 20 * shifted };
            }
        },
        4 => { // FLIGHING CARPET
            var a = half.double();
            var i: usize = SLICES;
            while (i > end) : (a = a.turn(INC2_ROT)) {
                i -= 1;
                const fi: f64 = @floatFromInt(i);
                pos[i] = .{ .i = @intCast(112 - i), .y = 70 + 20 * a.c - fi / 3, .z = (112 - fi) / 10 };
            }
        },
        else => { // 5, SIMPLE SINE
            var a = half;
            var i: usize = SLICES;
            while (i > end) : (a = a.turn(INC_ROT)) {
                i -= 1;
                const fi: f64 = @floatFromInt(i);
                pos[i] = .{ .i = @intCast(i), .y = 50 + 60 * a.c, .z = (112 - fi) / 10 };
            }
        },
    }
}

/// Waveform 2: a flat logo rotating, the slices stepped from one end to the other.
/// cos(a + PI) = -cos(a), sin(a + PI) = -sin(a).
fn rotatingFlat(third: Rot, pos: []Pos) void {
    var py = 50 + 30 * third.c;
    var pz = 20 * third.s;
    const iy = ((50 - 30 * third.c) - py) / 112;
    const iz = ((-20 * third.s) - pz) / 112;
    for (pos, 0..) |*p, i| {
        p.* = .{ .i = @intCast(i), .y = py, .z = pz };
        py += iy;
        pz += iz;
    }
}
