// --------------------------------------------------------------------------
// The NMOS 6502's arithmetic: pure functions of (A, operand, P), so they are
// testable alone. Binary mode is the textbook one. Decimal mode is the NMOS
// chip's, from Bruce Clark's "Decimal Mode" tutorial (6502.org): ADC sets N and
// V from the intermediate sum and Z from the BINARY sum; SBC sets every flag
// from the binary difference; ARR's decimal fixup is from "No More Secrets"
// (the NMOS 6510 unintended opcodes, groepaz). Checked against SingleStepTests
// (cpu6502_test.zig).
// --------------------------------------------------------------------------

pub const C: u8 = 0x01;
pub const Z: u8 = 0x02;
pub const I: u8 = 0x04;
pub const D: u8 = 0x08;
pub const B: u8 = 0x10;
pub const U: u8 = 0x20;
pub const V: u8 = 0x40;
pub const N: u8 = 0x80;

pub const Result = struct { a: u8, p: u8 };

/// N and Z from `v`, the rest of `p` kept.
pub fn nz(p: u8, v: u8) u8 {
    return (p & ~(N | Z)) | (v & N) | (if (v == 0) Z else 0);
}

fn set(p: u8, flag: u8, on: bool) u8 {
    return if (on) p | flag else p & ~flag;
}

pub fn adc(a: u8, b: u8, p: u8) Result {
    const c: u16 = p & C;
    const bin: u16 = @as(u16, a) + b + c;
    if (p & D == 0) {
        const r: u8 = @truncate(bin);
        var q = nz(p, r);
        q = set(q, C, bin > 0xFF);
        q = set(q, V, (~(a ^ b) & (a ^ r) & 0x80) != 0);
        return .{ .a = r, .p = q };
    }
    var lo: i16 = @as(i16, a & 0x0F) + (b & 0x0F) + @as(i16, @intCast(c));
    if (lo >= 0x0A) lo = ((lo + 0x06) & 0x0F) + 0x10;
    var sum: i16 = @as(i16, a & 0xF0) + (b & 0xF0) + lo; // before the high fixup: N and V
    const signed: i16 = @as(i16, @as(i8, @bitCast(a & 0xF0))) + @as(i8, @bitCast(b & 0xF0)) + lo;
    var q = set(p, N, signed & 0x80 != 0);
    q = set(q, V, signed < -128 or signed > 127);
    q = set(q, Z, @as(u8, @truncate(bin)) == 0);
    if (sum >= 0xA0) sum += 0x60;
    q = set(q, C, sum >= 0x100);
    return .{ .a = @truncate(@as(u16, @bitCast(sum))), .p = q };
}

pub fn sbc(a: u8, b: u8, p: u8) Result {
    const borrow: i16 = 1 - @as(i16, p & C);
    const bin = binSbc(a, b, p);
    if (p & D == 0) return bin;
    var lo: i16 = @as(i16, a & 0x0F) - (b & 0x0F) - borrow;
    if (lo < 0) lo = ((lo - 0x06) & 0x0F) - 0x10;
    var r: i16 = @as(i16, a & 0xF0) - (b & 0xF0) + lo;
    if (r < 0) r -= 0x60;
    return .{ .a = @truncate(@as(u16, @bitCast(r))), .p = bin.p };
}

fn binSbc(a: u8, b: u8, p: u8) Result {
    const r = adc(a, ~b, p & ~D);
    return .{ .a = r.a, .p = (r.p & ~D) | (p & D) };
}

/// CMP / CPX / CPY: C = no borrow, N Z from the difference.
pub fn cmp(p: u8, reg: u8, b: u8) u8 {
    return set(nz(p, reg -% b), C, reg >= b);
}

/// ARR (#$6B): AND, then ROR through carry; the flags are the odd part.
pub fn arr(a: u8, imm: u8, p: u8) Result {
    const t = a & imm;
    const r: u8 = (t >> 1) | ((p & C) << 7);
    if (p & D == 0) {
        var q = nz(p, r);
        q = set(q, C, r & 0x40 != 0);
        q = set(q, V, ((r >> 6) ^ (r >> 5)) & 1 != 0);
        return .{ .a = r, .p = q };
    }
    var q = set(p, N, p & C != 0);
    q = set(q, Z, r == 0);
    q = set(q, V, (t ^ r) & 0x40 != 0);
    var out = r;
    const lo = t & 0x0F;
    const hi = t >> 4;
    if (lo + (lo & 1) > 5) out = (out & 0xF0) | ((out +% 6) & 0x0F);
    if (@as(u16, hi) + (hi & 1) > 5) {
        q |= C;
        out +%= 0x60;
    } else q &= ~C;
    return .{ .a = out, .p = q };
}
