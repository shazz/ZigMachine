// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig).
//
// RACER: the physics' 3-vectors on PICO-8's 16.16 numbers (fix.zig), written as the Lua
// functions are (make_v, v_dot, v_cross, v_add, v_lerp, v_len, v_normz): every product rounds
// the way the reference does, so the order of operations here is the original's.
// No ZigOS import.
// --------------------------------------------------------------------------
const fix = @import("fix.zig");

pub const V = [3]i32;

/// make_v(a, b): from a to b.
pub fn between(a: V, b: V) V {
    return .{ b[0] -% a[0], b[1] -% a[1], b[2] -% a[2] };
}

pub fn dot(a: V, b: V) i32 {
    return fix.mul(a[0], b[0]) +% fix.mul(a[1], b[1]) +% fix.mul(a[2], b[2]);
}

pub fn cross(a: V, b: V) V {
    return .{
        fix.mul(a[1], b[2]) -% fix.mul(a[2], b[1]),
        fix.mul(a[2], b[0]) -% fix.mul(a[0], b[2]),
        fix.mul(a[0], b[1]) -% fix.mul(a[1], b[0]),
    };
}

/// v_add(v, dv, scale): v + scale * dv.
pub fn add(v: V, dv: V, k: i32) V {
    return .{ v[0] +% fix.mul(k, dv[0]), v[1] +% fix.mul(k, dv[1]), v[2] +% fix.mul(k, dv[2]) };
}

pub fn scale(v: V, s: i32) V {
    return .{ fix.mul(v[0], s), fix.mul(v[1], s), fix.mul(v[2], s) };
}

pub fn lerp(a: V, b: V, t: i32) V {
    return .{ fix.lerp(a[0], b[0], t), fix.lerp(a[1], b[1], t), fix.lerp(a[2], b[2], t) };
}

/// The "safe" length: 0 under 0.001, else the largest component times the length of the rest.
pub fn len(v: V) i32 {
    const d = fix.max(fix.max(fix.abs(v[0]), fix.abs(v[1])), fix.abs(v[2]));
    if (d < comptime fix.lit(0.001)) return 0;
    const x = fix.div(v[0], d);
    const y = fix.div(v[1], d);
    const z = fix.div(v[2], d);
    return fix.mul(d, fix.sqrt(fix.mul(x, x) +% fix.mul(y, y) +% fix.mul(z, z)));
}

/// v_normz: unit length, or the vector itself when it is nearly zero.
pub fn normz(v: V) V {
    const d = fix.mul(v[0], v[0]) +% fix.mul(v[1], v[1]) +% fix.mul(v[2], v[2]);
    if (d <= comptime fix.lit(0.001)) return v;
    const r = fix.sqrt(d);
    return .{ fix.div(v[0], r), fix.div(v[1], r), fix.div(v[2], r) };
}

/// v2_ortho(a, 1): the x/z vector turned a quarter.
pub fn ortho(a: V) V {
    return .{ -a[2], 0, a[0] };
}
