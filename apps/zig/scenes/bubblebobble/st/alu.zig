// --------------------------------------------------------------------------
// The 68000's arithmetic and its condition codes (X N Z V C), for the sizes
// the instruction names (T = u8 / u16 / u32). Each helper sets the flags the
// way the Programmer's Reference Manual tables them for that instruction.
// --------------------------------------------------------------------------
const k = @import("cpu.zig");

inline fn msb(comptime T: type, v: T) bool {
    return v >> (@bitSizeOf(T) - 1) != 0;
}

/// move, tst, clr, and/or/eor, ext, mulu: N and Z from the result, V = C = 0.
pub inline fn logic(comptime T: type, v: T) void {
    k.fneg = msb(T, v);
    k.fz = v == 0;
    k.fv = false;
    k.fc = false;
}

/// dst + src, all five flags.
pub inline fn add(comptime T: type, s: T, dst: T) T {
    const r = @addWithOverflow(dst, s);
    k.fc = r[1] != 0;
    k.fx = k.fc;
    k.fneg = msb(T, r[0]);
    k.fz = r[0] == 0;
    k.fv = msb(T, ~(s ^ dst) & (s ^ r[0]));
    return r[0];
}

/// dst - src, all five flags.
pub inline fn sub(comptime T: type, s: T, dst: T) T {
    const r = dst -% s;
    k.fc = s > dst;
    k.fx = k.fc;
    k.fneg = msb(T, r);
    k.fz = r == 0;
    k.fv = msb(T, (s ^ dst) & (dst ^ r));
    return r;
}

/// dst - src for the flags only: X is kept.
pub inline fn cmp(comptime T: type, s: T, dst: T) void {
    const r = dst -% s;
    k.fc = s > dst;
    k.fneg = msb(T, r);
    k.fz = r == 0;
    k.fv = msb(T, (s ^ dst) & (dst ^ r));
}

/// dst + src + X: Z is only cleared (a multi-precision sum's zero test).
pub inline fn addx(comptime T: type, s: T, dst: T) T {
    const W = @import("std").meta.Int(.unsigned, @bitSizeOf(T) + 1);
    const wide = @as(W, dst) + s + @intFromBool(k.fx);
    const r: T = @truncate(wide);
    k.fc = wide >> @bitSizeOf(T) != 0;
    k.fx = k.fc;
    k.fneg = msb(T, r);
    if (r != 0) k.fz = false;
    k.fv = msb(T, ~(s ^ dst) & (s ^ r));
    return r;
}

/// divu.w: Dn.l / src.w; on overflow V is set and Dn kept. (The game never divides by 0.)
pub fn divu(n: u3, s: u16) void {
    if (s == 0) return;
    const q = k.d[n] / s;
    k.fc = false;
    if (q > 0xFFFF) {
        k.fv = true;
        return;
    }
    const r = k.d[n] % s;
    k.d[n] = (r << 16) | q;
    k.fv = false;
    k.fz = q == 0;
    k.fneg = q & 0x8000 != 0;
}

// ---- bits: the number taken modulo the size (8 in memory, 32 in a register) --------
inline fn bit(comptime T: type, n: u32) T {
    return @as(T, 1) << @intCast(n & (@bitSizeOf(T) - 1));
}
pub inline fn btst(comptime T: type, v: T, n: u32) void {
    k.fz = v & bit(T, n) == 0;
}
pub inline fn bset(comptime T: type, v: T, n: u32) T {
    btst(T, v, n);
    return v | bit(T, n);
}
pub inline fn bclr(comptime T: type, v: T, n: u32) T {
    btst(T, v, n);
    return v & ~bit(T, n);
}
pub inline fn bchg(comptime T: type, v: T, n: u32) T {
    btst(T, v, n);
    return v ^ bit(T, n);
}

// ---- shifts and rotates: count 0..63; a count of 0 clears C and keeps X ----------------
fn shiftFlags(comptime T: type, r: T, n: u32, out: bool) void {
    k.fneg = msb(T, r);
    k.fz = r == 0;
    if (n == 0) {
        k.fc = false;
    } else {
        k.fc = out;
        k.fx = out;
    }
}

pub fn lsl(comptime T: type, v: T, n: u32) T {
    var r = v;
    var out = false;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        out = msb(T, r);
        r <<= 1;
    }
    shiftFlags(T, r, n, out);
    k.fv = false;
    return r;
}
pub fn asl(comptime T: type, v: T, n: u32) T {
    var r = v;
    var out = false;
    var changed = false;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        out = msb(T, r);
        r <<= 1;
        if (msb(T, r) != out) changed = true;
    }
    shiftFlags(T, r, n, out);
    k.fv = changed;
    return r;
}
pub fn lsr(comptime T: type, v: T, n: u32) T {
    var r = v;
    var out = false;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        out = r & 1 != 0;
        r >>= 1;
    }
    shiftFlags(T, r, n, out);
    k.fv = false;
    return r;
}
pub fn asr(comptime T: type, v: T, n: u32) T {
    const top = v & (@as(T, 1) << (@bitSizeOf(T) - 1));
    var r = v;
    var out = false;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        out = r & 1 != 0;
        r = (r >> 1) | top;
    }
    shiftFlags(T, r, n, out);
    k.fv = false;
    return r;
}
pub fn roxl(comptime T: type, v: T, n: u32) T {
    var r = v;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const out = msb(T, r);
        r = (r << 1) | @intFromBool(k.fx);
        k.fx = out;
    }
    k.fneg = msb(T, r);
    k.fz = r == 0;
    k.fv = false;
    k.fc = k.fx;
    return r;
}
pub fn roxr(comptime T: type, v: T, n: u32) T {
    var r = v;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const out = r & 1 != 0;
        r = (r >> 1) | (@as(T, @intFromBool(k.fx)) << (@bitSizeOf(T) - 1));
        k.fx = out;
    }
    k.fneg = msb(T, r);
    k.fz = r == 0;
    k.fv = false;
    k.fc = k.fx;
    return r;
}
