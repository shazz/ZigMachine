// --------------------------------------------------------------------------
// 68000 arithmetic on the reference model's unbounded values: every value in
// the transcriptions is an i64 (the model's Python int), masked where the
// model masks and nowhere else. These are the model's helpers (s16, setw,
// divu, rorl ...), with Python's semantics for the shifts.
// --------------------------------------------------------------------------
const M32: i64 = 0xFFFFFFFF;
const M16: i64 = 0xFFFF;

pub fn s8(v: i64) i64 {
    const x = v & 0xFF;
    return if (x & 0x80 != 0) x - 0x100 else x;
}
pub fn s16(v: i64) i64 {
    const x = v & 0xFFFF;
    return if (x & 0x8000 != 0) x - 0x10000 else x;
}
pub fn s32(v: i64) i64 {
    const x = v & M32;
    return if (x & 0x80000000 != 0) x - 0x100000000 else x;
}
pub fn setw(r: i64, v: i64) i64 {
    return (r & 0xFFFF0000) | (v & 0xFFFF);
}
pub fn setb(r: i64, v: i64) i64 {
    return (r & 0xFFFFFF00) | (v & 0xFF);
}
pub fn swap(v: i64) i64 {
    const x = v & M32;
    return ((x << 16) | (x >> 16)) & M32;
}
/// divu.w: 32/16 -> remainder:quotient; on overflow the register is unchanged.
pub fn divu(d: i64, sv: i64) i64 {
    const x = d & M32;
    const dv = sv & M16;
    if (dv == 0) return x; // the model would raise: never reached on a real path
    const q = @divFloor(x, dv);
    const r = @mod(x, dv);
    if (q > M16) return x;
    return (r << 16) | q;
}
pub fn rorl(v: i64, n: i64) i64 {
    const x = v & M32;
    const k: u6 = @intCast(@mod(n & 63, 32));
    if (k == 0) return x;
    const kk: u6 = @intCast(32 - @as(i64, k));
    return ((x >> k) | (x << kk)) & M32;
}
/// lsr.l by a register: counts of 32..63 empty it.
pub fn lsrl(v: i64, n: i64) i64 {
    const k = n & 63;
    if (k >= 32) return 0;
    return (v & M32) >> @intCast(k);
}
/// Python's `v >> n` for n >= 0. Every caller passes a masked byte or count;
/// a negative n (Python would raise) is taken as 0 rather than reaching the
/// u6 cast, which is unchecked in ReleaseSmall.
pub fn shr(v: i64, n: i64) i64 {
    if (n >= 63) return if (v < 0) -1 else 0;
    if (n <= 0) return v;
    return v >> @intCast(n);
}
pub fn bit(v: i64, n: i64) bool {
    return (shr(v, n) & 1) != 0;
}
