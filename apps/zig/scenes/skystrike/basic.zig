// --------------------------------------------------------------------------
// STOS BASIC's arithmetic, as the compiled program does it:
//   comparisons give -1 (true) or 0, AND / OR are bitwise on those, and
//   AND binds tighter than OR (the compiled line 267 ANDs its last two tests
//   before ORing them in);
//   integer / truncates toward zero (divs), MOD keeps the dividend's sign;
//   a float stored into an integer is truncated toward zero (the float
//   library's FFP -> int, trap #6 function 13, shifts the mantissa right).
// An array index out of its DIM is counted, not trusted (checked 0).
// --------------------------------------------------------------------------
pub var bad_index: u32 = 0;
/// Divisions by zero the original would have stopped on (checked 0).
pub var div_zero: u32 = 0;

/// The program's float constants, as their FFP values (24-bit mantissa).
pub const F0_14: f64 = 0.14000000059604645;
pub const F0_1: f64 = 0.10000000149011612;
pub const F0_15: f64 = 0.14999999105930328;
pub const F0_01: f64 = 0.009999999776482582;
pub const F0_03: f64 = 0.029999999329447746;
pub const F0_4: f64 = 0.4000000059604645;
pub const F0_3: f64 = 0.30000001192092896;
pub const F0_2: f64 = 0.20000000298023224;

pub inline fn fl(i: i32) f64 {
    return @floatFromInt(i);
}

pub inline fn t(b: bool) i32 {
    return if (b) -1 else 0;
}

pub inline fn tf(b: bool) f64 {
    return if (b) -1.0 else 0.0;
}

pub fn div(a: i32, b: i32) i32 {
    if (b == 0) {
        div_zero += 1;
        return 0;
    }
    return @divTrunc(a, b);
}

pub fn mod(a: i32, b: i32) i32 {
    if (b == 0) {
        div_zero += 1;
        return 0;
    }
    return @rem(a, b);
}

pub fn sgn(a: i32) i32 {
    return if (a > 0) 1 else if (a < 0) -1 else 0;
}

pub fn sgnf(a: f64) i32 {
    return if (a > 0) 1 else if (a < 0) -1 else 0;
}

pub fn abs(a: i32) i32 {
    return if (a < 0) -a else a;
}

/// A float into an integer variable.
pub fn ftoi(f: f64) i32 {
    if (f != f) return 0;
    if (f >= 2147483647.0) return 2147483647;
    if (f <= -2147483648.0) return -2147483648;
    return @intFromFloat(@trunc(f));
}

pub fn ipow(a: i32, n: i32) i32 {
    var r: i32 = 1;
    var i: i32 = 0;
    while (i < n) : (i += 1) r *%= a;
    return r;
}

/// A checked index into an array of `len` entries.
pub fn ix(len: usize, i: i32) usize {
    if (i < 0 or i >= len) {
        bad_index += 1;
        return if (i < 0) 0 else len - 1;
    }
    return @intCast(i);
}

pub fn reset() void {
    bad_index = 0;
    div_zero = 0;
}
