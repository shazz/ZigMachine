// --------------------------------------------------------------------------
// cyd's channel filter (cydflt.c): a four-pole resonant ladder in Q11, low-,
// high- or band-pass. Upstream's int arithmetic, wrapping where an int product
// could (as the x86/RISC-V code upstream compiles to does), truncating divides.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");

pub fn setCoeff(f: *c.Filter, frequency: u16, resonance: u16) void {
    const fr: i32 = frequency;
    const q: i32 = 2048 - fr;
    f.p = fr + @divTrunc(@divTrunc(1638 * fr, 2048) * q, 2048); // (Sint32)(0.8f * 2048.0f) = 1638
    f.f = f.p + f.p - 2048;
    f.q = resonance;
}

fn mulq(a: i32, b: i32) i32 {
    return @divTrunc(a *% b, 2048);
}

pub fn cycle(f: *c.Filter, in: i32) void {
    const input = in -% mulq(f.q, f.b4); // feedback
    var t1 = f.b1;
    f.b1 = mulq(input +% f.b0, f.p) -% mulq(f.b1, f.f);
    const t2 = f.b2;
    f.b2 = mulq(f.b1 +% t1, f.p) -% mulq(f.b2, f.f);
    t1 = f.b3;
    f.b3 = mulq(f.b2 +% t2, f.p) -% mulq(f.b3, f.f);
    f.b4 = mulq(f.b3 +% t1, f.p) -% mulq(f.b4, f.f);
    f.b4 = @min(32767, @max(-32768, f.b4)); // clipping
    f.b0 = input;
}

pub fn output(f: *const c.Filter, kind: u8) i32 {
    return switch (kind) {
        c.FLT_HP => f.b0 -% f.b4,
        c.FLT_BP => 3 *% (f.b3 -% f.b4),
        else => f.b4,
    };
}
