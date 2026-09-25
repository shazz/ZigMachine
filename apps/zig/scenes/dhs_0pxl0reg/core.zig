// --------------------------------------------------------------------------
// State every part shares: colour 0 as the VBL/main hooks leave it, the sine
// table ($2268C), the global one-component fader ($22554) and the queue of work
// a main-loop hook finishes AFTER the kernel preempted it (model.Demo.after).
// --------------------------------------------------------------------------
const std = @import("std");

/// Colour 0 when the kernel starts: what the lines above it show.
pub var colour: u16 = 0;

/// $2268C: 1024 entries (+256 wrap copy), amplitude 16384, a Minsky circle with
/// integer divides. The demo's own table, error <= 32 against a true sine.
pub var sine: [1280]i16 = undefined;

pub fn buildSine() void {
    var t: [1280]u16 = undefined;
    var d0: u16 = 11;
    var d1: u16 = 0x4000;
    for (0..256) |k| {
        d0 +%= d1 / 163;
        d1 -%= d0 / 163;
        t[256 + k] = d1;
        t[256 - k] = d1;
        t[768 + k] = 0 -% d1;
        t[768 - k] = 0 -% d1;
    }
    t[0] = 0;
    t[512] = 0;
    for (0..1024) |i| sine[i] = @bitCast(t[i]);
    for (0..256) |i| sine[1024 + i] = sine[i];
}

/// sine[i] * k >> 15, the 68000's muls + asr pair (floor, as the model).
pub inline fn sinMul(i: usize, k: i32) i32 {
    return (@as(i32, sine[i]) * k) >> 15;
}

/// $22554 steps ONE colour component per call, B then G then R, and the
/// rotation is counted across every fade call in the whole demo. Getting the
/// count right is what keeps later parts' colours exact.
pub var fade_calls: u32 = 0;

/// `cur` is a pointer to an array and `tgt` one of the same length: a
/// mismatched target is a compile error, not an overread in ReleaseSmall.
pub fn step1(cur: anytype, tgt: *const @TypeOf(cur.*)) void {
    const k = fade_calls % 3;
    fade_calls += 1;
    const sh: u4 = @intCast(4 * k);
    const mask: u16 = @as(u16, 7) << sh;
    for (cur, tgt) |*c, t| {
        var a = (c.* & mask) >> sh;
        const b = (t & mask) >> sh;
        if (b < a) a -= 1 else if (b > a) a += 1;
        c.* = (c.* & ~mask) | ((a << sh) & mask);
    }
}

/// $224EE: all three components one step towards the target at once.
pub fn step3(out: anytype, cur: *const @TypeOf(out.*), tgt: *const @TypeOf(out.*)) void {
    for (out, cur, tgt) |*o, c, t| {
        var r: u16 = 0;
        inline for (.{ 0x700, 0x070, 0x007 }, .{ 0x100, 0x010, 0x001 }) |mask, one| {
            var a: u16 = c & mask;
            const b: u16 = t & mask;
            if (b < a) a -= one else if (b > a) a += one;
            r |= a;
        }
        o.* = r;
    }
}

/// A chain of 13-word palette sets: zeros, then single-component fades
/// towards each target for its step count (P11, P13, P16).
pub const Link = struct { tgt: *const [13]u16, n: u32 };

/// The chain must fill `sets` exactly (1 + the steps); checked at compile time.
pub fn palSets(comptime N: usize, sets: *[N][13]u16, comptime chain: []const Link) void {
    comptime {
        var total: usize = 1;
        for (chain) |link| total += link.n;
        if (total != N) @compileError("palSets: the chain does not fill the sets");
    }
    var p = [_]u16{0} ** 13;
    sets[0] = p;
    var n: usize = 1;
    inline for (chain) |link| {
        for (0..link.n) |_| {
            step1(&p, link.tgt);
            sets[n] = p;
            n += 1;
        }
    }
}

/// Work a main-loop hook does after the kernel (model.Demo.after), in order.
pub const After = enum { p7_rest, p7_reveal, p7_m18756b, p7_m187a4b, p9_swap, p16_show, p16_m92b, p16_m93b, p16_m95b };
pub const Job = struct { what: After, arg: u32 };
pub var after: [16]Job = undefined;
pub var after_n: usize = 0;

pub fn later(what: After, arg: u32) void {
    after[after_n] = .{ .what = what, .arg = arg };
    after_n += 1;
}

/// Little-endian word `i` of an embedded blob.
pub inline fn le16(b: []const u8, i: usize) u16 {
    return std.mem.readInt(u16, b[2 * i ..][0..2], .little);
}

/// Big-endian word at byte offset `o` (tables left as the 68000 stored them).
pub inline fn be16(b: []const u8, o: usize) u16 {
    return std.mem.readInt(u16, b[o..][0..2], .big);
}

/// The 16-bit value as the 68000's signed word.
pub inline fn sw(v: u32) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(v))));
}

pub fn reset() void {
    colour = 0;
    fade_calls = 0;
    after_n = 0;
    buildSine();
}
