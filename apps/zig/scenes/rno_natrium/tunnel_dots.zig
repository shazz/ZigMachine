// --------------------------------------------------------------------------
// Part 1 (counter $C0..$5A4): the plane-0 dot tunnel ($D670 -> generated code
// at $C391A) and the row operations the sequencer runs between passes.
//
// The tunnel is a lookup-table tunnel: map entry (u, v) samples a 16x32 one-bit
// blob texture with v scrolled by the VBL counter, one texel = 2 pixels. Each
// pass refreshes ONE line parity: the top half from map rows 0..49, and the
// bottom half as the same word turned 180 degrees and INVERTED ($B771A) -- the
// two-tone split at line 100 is that inversion, not a raster. The original
// unrolled the loop into 1000 generated 48-byte blocks; this is the loop.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const Screen = st.Screen;

/// $AF81A entry i as $C2DC derives it from the $144C8 source word:
/// u = low nibble, v = 5 bits that the octant term twists into a spiral.
inline fn mapUV(i: usize) struct { u: u32, v: u32 } {
    const w: u32 = A.be16(A.tunnel_map, i);
    const d1: u32 = ((w & 0xFF) << 8) | (w >> 8);
    const d3 = ((d1 >> 1) + ((d1 & 0x70) << 6)) & 0xF80;
    return .{ .u = d1 & 0xF, .v = d3 >> 7 };
}

/// One pass: F = $144A0 & 31, `par` the field. Writes plane 0 only.
pub fn pass(s: *Screen, f: u16, par: u1) void {
    const phase: u32 = f & 31;
    const base: usize = @as(usize, par) * st.LINE;
    var i: usize = 0;
    for (0..50) |j| {
        for (0..20) |x| {
            var n: u8 = 0;
            for (0..8) |k| {
                const m = mapUV(i);
                i += 1;
                const texel = A.dot_tex[((m.v + phase) & 31) * 16 + m.u] & 1;
                n |= @as(u8, texel) << @intCast(7 - k);
            }
            st.setW(s, base + j * 0x140 + x * 8, A.pix_double[n]);
            st.setW(s, base + 0x7C58 - j * 0x140 - x * 8, A.pix_mirror[n]);
        }
    }
}

/// The plane-1 curtains ($ABEC wipe with $FFFF, $B0B8 clear with 0): step n
/// writes row 2n (top curtain, going down) and row 199-2n (bottom, going up).
pub fn curtainPlane1(s: *Screen, n: u16, value: u16) void {
    const top = @as(usize, n) * 0x140;
    const bottom = 0x7C60 - top;
    for (0..20) |x| {
        st.setW(s, top + x * 8 + 2, value);
        st.setW(s, bottom + x * 8 + 2, value);
    }
}

/// $ACC2: RNO logo row 72+n, planes 1..3 from the ILBM body (plane 0 is the tunnel's).
pub fn revealRno(s: *Screen, n: u16) void {
    const src = A.rno_rows[@as(usize, n) * st.LINE ..][0..st.LINE];
    const out = (A.LOGO_TOP + @as(usize, n)) * st.LINE;
    for (0..20) |x| {
        for (1..4) |p| {
            s[out + x * 8 + 2 * p] = src[p * 40 + 2 * x];
            s[out + x * 8 + 2 * p + 1] = src[p * 40 + 2 * x + 1];
        }
    }
}

/// $AEA8: NATRIUM row 127-n, planes 1..3 copied from the back buffer, bottom-up.
pub fn revealFromBack(s: *Screen, back: *const Screen, n: u16) void {
    const out = (0x7F - @as(usize, n)) * st.LINE;
    for (0..20) |x| {
        const g = out + x * 8;
        @memcpy(s[g + 2 .. g + 8], back[g + 2 .. g + 8]);
    }
}

/// $AFAC: row 72+n: plane 1 = $FFFF, planes 2 and 3 = 0.
pub fn eraseRow(s: *Screen, n: u16) void {
    const out = (A.LOGO_TOP + @as(usize, n)) * st.LINE;
    for (0..20) |x| {
        st.setW(s, out + x * 8 + 2, 0xFFFF);
        st.setW(s, out + x * 8 + 4, 0);
        st.setW(s, out + x * 8 + 6, 0);
    }
}
