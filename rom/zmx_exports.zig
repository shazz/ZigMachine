// --------------------------------------------------------------------------
// ZM-X v1's twins as ROM exports (fpga/review/KESTREL_NEXT_ISA.md section 5).
//
// A cart that wants an op as ONE instruction on the board declares the import
// (rom/sdk/zmx.zig); the browser, node and the native host bind it here, to the
// spec itself (libs/zig/zmx.zig), so every host computes the same integers. On
// the board a cart image built with ZM_ZMX turns each import into the custom-0
// instruction (fpga/cycles/zmx_hw.h); without it the import calls this twin
// through the system table. fpga/tests/test_zmx.py proves RTL = zmx.zig = the C
// twin. Pure functions of their arguments: no state, nothing to validate (every
// u32 is a valid operand; tex2d's dims are taken mod 64, as the hardware's
// decoder only sees funct7's low six bits there).
// --------------------------------------------------------------------------
const zmx = @import("zmx");

export fn zmMulsh16(a: i32, b: i32) i32 {
    return zmx.mulsh16(a, b);
}

export fn zmMulsh15(a: i32, b: i32) i32 {
    return zmx.mulsh15(a, b);
}

export fn zmTex2d(u: u32, v: u32, dims: u32) u32 {
    return switch (@as(u6, @truncate(dims))) {
        inline else => |d| zmx.tex2d(@as(u4, d & 7) + 3, @as(u4, d >> 3) + 3, u, v),
    };
}

export fn zmFunnel1(lo: u32, hi: u32) u32 {
    return zmx.funnel(1, lo, hi);
}

export fn zmFunnel2(lo: u32, hi: u32) u32 {
    return zmx.funnel(2, lo, hi);
}

export fn zmFunnel3(lo: u32, hi: u32) u32 {
    return zmx.funnel(3, lo, hi);
}

export fn zmAdd8s(a: u32, b: u32) u32 {
    return zmx.add8s(a, b);
}

export fn zmSub8s(a: u32, b: u32) u32 {
    return zmx.sub8s(a, b);
}

export fn zmAvg8(a: u32, b: u32) u32 {
    return zmx.avg8(a, b);
}

export fn zmAdd8(a: u32, b: u32) u32 {
    return zmx.add8(a, b);
}
