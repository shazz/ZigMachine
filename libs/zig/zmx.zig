// --------------------------------------------------------------------------
// ZM-X v1: the SPEC of ZIGGY's custom integer ops, and their software twin.
// (fpga/review/KESTREL_NEXT_ISA.md 1.2-1.3; step 0 of its section 4.)
//
// Every function below is the exact integer semantics of one instruction.
// Today it is plain Zig (wasm in the browser, rv32im on the board); step 2
// swaps a body for the instruction and NOTHING else may change: the RTL, the
// C twin (zm_cart_rt) and rom.wasm's exports are tested against these bodies,
// bit for bit (zmx_test.zig pins them, exhaustively over the byte lanes).
//
// Encoding: R-type, opcode custom-0 (0x0B). Immediates are comptime here.
//
//   op       funct7                funct3  semantics (rs1 = a/lo/u, rs2 = b/hi/v)
//   mulsh    1                     0 / 1   rd = bits [47:16] / [46:15] of the SIGNED 64-bit
//                                          product sext(rs1) * sext(rs2): an arithmetic shift
//                                          (rounds toward -inf), truncating, no saturation
//   funnel   2                     k=1..3  rd = (rs1 >> 8k) | (rs2 << (32 - 8k)): the word at
//                                          byte offset k of the little-endian pair {rs2:rs1},
//                                          i.e. an unaligned word from two aligned loads
//   add8s    3                     0       per unsigned byte lane: min(a + b, 255)
//   sub8s    4                     0       per unsigned byte lane: max(a - b, 0)
//   avg8     5                     0       per unsigned byte lane: (a + b) >> 1, FLOOR (a
//                                          round-up average never decays to 0: the fire bug)
//   add8     6 (optional)          0       per byte lane: (a + b) mod 256, no carry across
//   tex2d    (logW-3)|(logH-3)<<3  7       rd = (((rs2 >> 16) & (H-1)) << logW)
//                                               | ((rs1 >> 16) & (W-1)),
//                                          LOGICAL shifts, W = 2^logW, H = 2^logH, 8..1024
//
// Lanes: byte i of a word is bits [8i+7:8i] (little-endian: byte i is pixel x+i of
// a row read with lw). No carry or borrow ever crosses a lane.
// Wasm imports (step 2, all i32): zmMulsh16, zmMulsh15, zmTex2d(u, v, dims) with
// dims = the tex2d funct7, zmFunnel1/2/3(lo, hi), zmAdd8s, zmSub8s, zmAvg8, zmAdd8.
//
// Not an instruction: rcp(), a 512-byte table + one Newton step in two mulsh,
// the perspective divide's replacement (36-cycle div -> ~10 instructions).
//
// No ZigOS import: zmx_test.zig runs it natively.
// --------------------------------------------------------------------------

const H8: u32 = 0x80808080; // the top bit of each lane
const L7: u32 = 0x7F7F7F7F; // the low 7 bits of each lane

/// bits [47:16] (shift 16) or [46:15] (shift 15) of sext(a) * sext(b).
pub inline fn mulsh(comptime shift: u5, a: i32, b: i32) i32 {
    comptime if (shift != 16 and shift != 15) @compileError("zm.mulsh: shift is 16 or 15");
    return @truncate((@as(i64, a) * b) >> shift);
}

/// Q16.16 multiply (zm.mulsh funct3 0).
pub inline fn mulsh16(a: i32, b: i32) i32 {
    return mulsh(16, a, b);
}

/// Q15 multiply (zm.mulsh funct3 1).
pub inline fn mulsh15(a: i32, b: i32) i32 {
    return mulsh(15, a, b);
}

/// tex2d's funct7 (and zmTex2d's `dims`) for a 2^logW x 2^logH texture.
pub fn texDims(comptime logW: u4, comptime logH: u4) u7 {
    comptime if (logW < 3 or logW > 10 or logH < 3 or logH > 10) @compileError("zm.tex2d: logW, logH in 3..10");
    return @as(u7, logW - 3) | (@as(u7, logH - 3) << 3);
}

/// The texel index of Q16.16 (u, v) in a 2^logW x 2^logH texture, both axes wrapping.
pub inline fn tex2d(comptime logW: u4, comptime logH: u4, u: u32, v: u32) u32 {
    _ = comptime texDims(logW, logH);
    const wm: u32 = (1 << logW) - 1;
    const hm: u32 = (1 << logH) - 1;
    return (((v >> 16) & hm) << logW) | ((u >> 16) & wm);
}

/// The word at byte offset k (1..3) of the little-endian pair {hi:lo}.
pub inline fn funnel(comptime k: u2, lo: u32, hi: u32) u32 {
    comptime if (k == 0) @compileError("zm.funnel: k in 1..3");
    const r: u5 = 8 * @as(u5, k);
    const l: u5 = @intCast(32 - 8 * @as(u6, k));
    return (lo >> r) | (hi << l);
}

/// Per lane (a + b) mod 256.
pub inline fn add8(a: u32, b: u32) u32 {
    return ((a & L7) +% (b & L7)) ^ ((a ^ b) & H8);
}

/// 0xFF in every lane whose bit 7 is set in `top` (top holds only lane top bits).
inline fn spread(top: u32) u32 {
    return (top >> 7) *% 0xFF;
}

/// Per lane min(a + b, 255).
pub inline fn add8s(a: u32, b: u32) u32 {
    const s = add8(a, b);
    const carry = ((a & b) | ((a | b) & ~s)) & H8;
    return s | spread(carry);
}

/// Per lane max(a - b, 0).
pub inline fn sub8s(a: u32, b: u32) u32 {
    const d = ((a | H8) -% (b & L7)) ^ ((a ^ ~b) & H8);
    const borrow = ((~a & b) | ((~a | b) & d)) & H8;
    return d & ~spread(borrow);
}

/// Per lane floor((a + b) / 2).
pub inline fn avg8(a: u32, b: u32) u32 {
    return (a & b) +% (((a ^ b) >> 1) & L7);
}

/// A byte in every lane: the decay or bias operand of the lane ops.
pub inline fn splat8(b: u8) u32 {
    return @as(u32, b) *% 0x01010101;
}

// ---- rcp: the reciprocal without a divide ---------------------------------

/// RCP[i] = round(2^16 / (1 + (i + 0.5) / 256)): Q16 of 1/m at the middle of
/// the mantissa bucket i, m in [1, 2). 256 x u16 = 512 bytes, D$-resident.
pub const RCP: [256]u16 = blk: {
    var t: [256]u16 = undefined;
    for (&t, 0..) |*e, i| {
        const den = 512 + 2 * i + 1; // 2^16 / ((512 + 2i + 1) / 512), rounded
        e.* = @intCast((2 * (1 << 25) + den) / (2 * den));
    }
    break :blk t;
};

/// ~2^32 / d for d >= 2 (2^32/d of a Q16 z is 1/z in Q16), 14+ bits good:
/// |rcp(d) - 2^32/d| < 2^32/d * 2^-14 + 1 (zmx_test.zig).
/// d < 2 saturates to 0xFFFFFFFF. Normalise, look up, one Newton step
/// y1 = y0 * (2 - m * y0) in two mulsh16, denormalise.
pub fn rcp(d: u32) u32 {
    if (d < 2) return 0xFFFF_FFFF;
    const n: u5 = @intCast(@clz(d));
    const m = d << n; // bit 31 set
    const y0: i32 = RCP[(m >> 23) & 255];
    const m16: i32 = @intCast(m >> 15); // Q16 in [1, 2)
    const t = mulsh16(m16, y0); // ~1.0
    const y1: u32 = @intCast(mulsh16(y0, (2 << 16) - t)); // Q16 of 1/m, <= 65536
    // 2^32 / d = (1/m) * 2^(n + 1), and y1 is (1/m) * 2^16
    const r = (@as(u64, y1) << (@as(u6, n) + 1)) >> 16;
    return @intCast(@min(r, 0xFFFF_FFFF));
}
