// --------------------------------------------------------------------------
// TCB #2's three precalculated preshift sets, as its set-up builds them:
// the big scroller's glyphs ($10752), the TCB logo ($B440) and AN COOL
// ($9948 / $949A). Each is the 68000's own shift loop, so the carries between
// 16-pixel groups land exactly where the original's did.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb2.zig");

const Ram = st.Ram;

/// $10752: the 50 big glyphs (32x25, $190 each at $1226C) in four preshifts
/// of 48x25 (4, 8, 12 and 16 pixels right) at $1908C.
pub fn glyphs(r: *const Ram) void {
    var src: u32 = 0x1226C;
    var dst: u32 = T.GLYPHS;
    for (0..50) |_| {
        var d1: i32 = 12;
        while (d1 >= 0) : (d1 -= 4) {
            const d4: u5 = @intCast(16 - d1);
            const half: u32 = if (d4 == 16) 0 else @as(u32, 0xFFFF) >> d4; // lsr.w: 16 empties it
            const mask = half << 16 | half;
            var a2 = src;
            for (0..25) |_| {
                for ([_]u32{ 0, 4 }) |p| {
                    const g0 = r.l(a2 + p);
                    const g1 = r.l(a2 + 8 + p);
                    r.sl(dst + p, (g0 >> d4) & mask);
                    r.sl(dst + 8 + p, ((g0 << @intCast(d1)) & ~mask) | ((g1 >> d4) & mask));
                    r.sl(dst + 16 + p, (g1 << @intCast(d1)) & ~mask);
                }
                a2 += 16;
                dst += 24;
            }
        }
        src += 0x190;
    }
}

/// $B440: the yellow TCB logo (96x25 at $B4EC) in 16 1-pixel preshifts of
/// 112x25 at $52600, $578 apart.
pub fn tcbLogo(r: *const Ram) void {
    var dst: u32 = T.LOGO_SHIFTS;
    for (0..16) |s| {
        var src: u32 = 0xB4EC;
        for (0..25) |_| {
            var carry = [4]u16{ 0, 0, 0, 0 };
            for (0..6) |_| {
                for (0..4) |p| {
                    const v: u32 = r.w(src);
                    src += 2;
                    r.sw(dst, @as(u16, @truncate(v >> @intCast(s))) | carry[p]);
                    dst += 2;
                    carry[p] = @truncate((v << 16) >> @intCast(s));
                }
            }
            for (carry) |c| {
                r.sw(dst, c);
                dst += 2;
            }
        }
    }
}

/// $9948 + $949A: the AN COOL line ring, and the image's 16 preshifts at $57D80.
pub fn anCool(r: *const Ram) void {
    for (0..50) |i| {
        const a = T.ANCOOL_RING + 8 * @as(u32, @intCast(i));
        r.sl(a, 0x57DFE);
        r.sl(a + 4, 8);
    }
    for (0..25) |row| r.zero(T.ANCOOL + 0xE4 * @as(u32, @intCast(row)), 0x8A);
    var src: u32 = 0x1177C;
    for (0..25) |row| {
        var dst = T.ANCOOL + 0xE4 * @as(u32, @intCast(row)) + 0x8A;
        for (0..14) |_| {
            r.cp(dst, src, 6);
            src += 8;
            dst += 6;
        }
        r.zero(dst, 6);
    }
    var dst: u32 = T.ANCOOL + 0x1644;
    for (1..16) |s| {
        r.sw(0xA706, @intCast(s));
        var src2: u32 = T.ANCOOL;
        for (0..0x3B6) |_| {
            for (0..3) |p| {
                const v: u32 = @as(u32, r.w(src2 + 2 * @as(u32, @intCast(p)))) << 16;
                const sh = v >> @intCast(s);
                r.sw(dst + 6 + 2 * @as(u32, @intCast(p)), @truncate(sh));
            }
            for (0..3) |p| {
                const v: u32 = @as(u32, r.w(src2 + 2 * @as(u32, @intCast(p)))) << 16;
                const a = dst + 2 * @as(u32, @intCast(p));
                r.sw(a, r.w(a) | @as(u16, @truncate((v >> @intCast(s)) >> 16)));
            }
            src2 += 6;
            dst += 6;
        }
    }
}
