// f32 number back-end for the ray tracer: the same interface as fixed.zig, so
// the tracer source is shared and only this file changes. On the FPGA (no FPU)
// every operation here is a soft-float library call: that is the comparison.
pub const NAME = "FLOAT F32";
pub const T = f32;
pub const ONE: T = 1.0;

pub fn k(comptime v: f64) T {
    return @floatCast(v);
}

pub fn fromInt(i: i32) T {
    return @floatFromInt(i);
}

pub fn mul(a: T, b: T) T {
    return a * b;
}

pub fn div(a: T, b: T) T {
    return a / b;
}

pub fn len3(x: T, y: T, z: T) T {
    return @sqrt(x * x + y * y + z * z);
}

pub fn toInt(a: T) i32 {
    return @intFromFloat(@floor(a));
}

pub fn toQ8(a: T) u32 {
    const v = a * 256.0;
    if (!(v > 0)) return 0;
    if (v >= 256.0) return 256;
    return @intFromFloat(v);
}
