//! zigdemo curves: the animation tracks a part samples at its local time.
//!
//! Three kinds, all integer. `linear` and `step` are sparse (t_ms, value) keys:
//! `linear` for fades and UV scrolls, `step` for visibility. `baked` is a
//! fixed-rate array of samples, as TBL bakes its clips at 30 Hz. Interpolation
//! is Q16 on a u64 intermediate, so a key span cannot overflow. Outside the
//! keys the curve holds its end values. Quaternion (TRS) curves are the Trs stub.

const std = @import("std");

pub const Key = struct { t_ms: u32, v: i32 };

pub const Baked = struct { rate_hz: u32, samples: []const i16 };

pub const Curve = union(enum) {
    linear: []const Key,
    step: []const Key,
    baked: Baked,
};

pub const KeyError = error{ Empty, NotIncreasing };

/// Sparse keys must be non-empty and strictly increasing in time. A duplicate
/// time would make the interpolation divide by zero.
pub fn checkKeys(keys: []const Key) KeyError!void {
    if (keys.len == 0) return error.Empty;
    for (keys[1..], keys[0 .. keys.len - 1]) |b, a| {
        if (b.t_ms <= a.t_ms) return error.NotIncreasing;
    }
}

pub fn sample(curve: Curve, t: u32) i32 {
    return switch (curve) {
        .linear => |keys| linear(keys, t),
        .step => |keys| step(keys, t),
        .baked => |b| baked(b, t),
    };
}

fn linear(keys: []const Key, t: u32) i32 {
    std.debug.assert(keys.len > 0);
    const first = keys[0];
    const last = keys[keys.len - 1];
    if (t <= first.t_ms) return first.v;
    if (t >= last.t_ms) return last.v;
    const i = lastAtOrBefore(keys, t);
    const a = keys[i];
    const b = keys[i + 1];
    return lerp(a.v, b.v, fraction(t - a.t_ms, b.t_ms - a.t_ms));
}

/// Holds the last key's value: a visible/hidden flip lands exactly on its key.
/// Before the first key it holds the first key's value.
fn step(keys: []const Key, t: u32) i32 {
    std.debug.assert(keys.len > 0);
    if (t < keys[0].t_ms) return keys[0].v;
    return keys[lastAtOrBefore(keys, t)].v;
}

fn baked(b: Baked, t: u32) i32 {
    const n = b.samples.len;
    std.debug.assert(n > 0);
    // The position in samples, Q16: t ms * rate / 1000.
    const pos: u64 = ((@as(u64, t) * b.rate_hz) << 16) / 1000;
    const i: usize = @intCast(pos >> 16);
    if (i + 1 >= n) return b.samples[n - 1];
    return lerp(b.samples[i], b.samples[i + 1], @intCast(pos & 0xFFFF));
}

/// The index of the last key at or before `t`. Needs keys[0].t_ms <= t.
/// A binary search: the keys of a fade are few, but a scroll can have hundreds.
fn lastAtOrBefore(keys: []const Key, t: u32) usize {
    var base: usize = 0;
    var n = keys.len;
    while (n > 1) {
        const half = n / 2;
        if (keys[base + half].t_ms <= t) base += half;
        n -= half;
    }
    return base;
}

/// The Q16 position of `d` within `span`, with d < span.
fn fraction(d: u32, span: u32) u32 {
    std.debug.assert(span > 0);
    return @intCast((@as(u64, d) << 16) / span);
}

/// a + (b - a) * q16 / 65536, rounded down. q16 = 0 returns `a` exactly.
fn lerp(a: i32, b: i32, q16: u32) i32 {
    const d: i64 = @as(i64, b) - a;
    const off: i64 = (d * @as(i64, q16)) >> 16;
    return @intCast(@as(i64, a) + off);
}

/// MOCK: quaternion / TRS curves. Not built yet. The real one is a Q14 nlerp of
/// unit quaternions plus a linear vec3, sampled from the same baked clips as
/// `baked` (prototypes/suicide_barbie_re/ANALYSIS.md §7 (3), the curve.zig row).
/// Calling it is a compile error, so a cart cannot ship an identity pose by accident.
pub const Trs = struct {
    pub fn sample(_: Trs, _: u32) [4]i16 {
        @compileError("zigdemo: TRS curves are a mock; see prototypes/suicide_barbie_re/ANALYSIS.md §7 (3)");
    }
};
