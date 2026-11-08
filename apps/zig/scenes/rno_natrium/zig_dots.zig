// --------------------------------------------------------------------------
// NATRIUM ZIG mode, part 1: the $D670 dot tunnel over the whole overscan
// window, under the original's curtains and logos: 2 CHISEL ops a frame.
//
// The original draws plane 0 only, one field a VBL, 320x100 from map rows
// 0..49 (2x2-pixel cells) and the bottom half as the same bytes turned 180
// degrees and INVERTED ($B771A). Here:
//   map      400x280 entries of the table's own formula (zig_math.dotEntry),
//            one a PIXEL, built at the first Z press. The (u, v) $C2DC reads
//            survive a half turn, so the bottom half is the formula's own; its
//            entries point at texture columns 16..31, the blob INVERTED: the
//            original's two-tone split, centred on the window (line 140).
//   texture  the 16x32 one-bit blob, its 32 rows held as 128 quarter-texel
//            rows, so the scroll (v + f) moves every host frame, not every VBL.
//   rest     planes 1..3 of the ST screen (curtains, RNO, NATRIUM, the erase
//            band) as pens with bit 0 clear in R.bg, at (40, 40), its edge
//            pixels carried out across the borders (left/right columns, lines
//            0/1 up, 198/199 down by parity), so the curtains close over the
//            whole window. Only the lines whose planes 1..3 changed are
//            expanded again (one or two a VBL: the sequencer's row ops).
// A frame: one blit of R.bg, then ONE MAP that ORs bit 0 in (MT_OR_BC): the
// pen of every pixel is the ST's, plane 0 the tunnel's, as on the ST.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const v2 = zg.chisel_v2;
const st = @import("st.zig");
const A = @import("assets.zig");
const M = @import("zig_math.zig");
const R = @import("zig_res.zig");

pub const TW: usize = 32; // 16 blob columns, then the same inverted
pub const TH: usize = 128; // 32 blob rows in quarter texels
const LINE_WORDS: usize = st.LINE / 4; // an ST line as u32 words
const PLANE0_OUT: u32 = std.mem.nativeToLittle(u32, 0xFFFF_0000); // bytes 2, 3 of a group's first word

pub var map: []u16 = &.{};
pub var tex: []u8 = &.{};
var cache: []u32 = &.{}; // planes 1..3 of each ST line as last expanded (plane 0 masked)

pub fn build() bool {
    map = zg.mem.alloc(u16, R.W * R.H) orelse return false;
    tex = zg.mem.alloc(u8, TW * TH) orelse return false;
    cache = zg.mem.alloc(u32, 200 * LINE_WORDS) orelse return false;
    // the top half computed, the bottom its half turn (exact: zig_math_test)
    for (0..R.H / 2) |y| for (0..R.W) |x| {
        const e = M.dotEntry(@as(i32, @intCast(2 * x + 1)) - @as(i32, R.W), @as(i32, @intCast(2 * y + 1)) - @as(i32, R.H));
        map[y * R.W + x] = e;
        map[(R.H - 1 - y) * R.W + R.W - 1 - x] = e + 16;
    };
    for (0..TH) |vq| for (0..TW) |u| {
        const bit = A.dot_tex[(vq / 4) * 16 + (u & 15)] & 1;
        tex[vq * TW + u] = if (u < 16) bit else bit ^ 1;
    };
    return true;
}

/// ST line r's planes 1..3 into R.bg (st.toChunky's spread tables, plane 0
/// left out), edges carried out to the side borders.
fn expandLine(s: *const st.Screen, r: usize) void {
    const out = R.bg[(R.OY + r) * R.W ..][0..R.W];
    const wp: [*]u32 = @ptrCast(@alignCast(out.ptr + R.OX));
    for (0..20) |g| {
        const w = s[r * st.LINE + g * 8 ..][0..8];
        inline for (0..2) |half| {
            wp[g * 4 + half * 2] = (st.spread_lo[w[2 + half]] << 1) | (st.spread_lo[w[4 + half]] << 2) | (st.spread_lo[w[6 + half]] << 3);
            wp[g * 4 + half * 2 + 1] = (st.spread_hi[w[2 + half]] << 1) | (st.spread_hi[w[4 + half]] << 2) | (st.spread_hi[w[6 + half]] << 3);
        }
    }
    @memset(out[0..R.OX], out[R.OX]);
    @memset(out[R.OX + 320 ..], out[R.OX + 319]);
}

/// Lines 0/1 go up the top border, 198/199 down the bottom one, by parity.
fn borders(r: usize) void {
    if (r >= 2 and r < 198) return;
    const src = R.bg[(R.OY + r) * R.W ..][0..R.W];
    var y: usize = if (r < 2) r else R.OY + r + 2;
    const end: usize = if (r < 2) R.OY else R.H;
    while (y < end) : (y += 2) @memcpy(R.bg[y * R.W ..][0..R.W], src);
}

/// Expand the lines whose planes 1..3 changed (`all`: every line). A group's
/// 8 bytes are two words: plane 0 is the first word's low half (bytes 0, 1).
pub fn sync(s: *const st.Screen, all: bool) void {
    const words: [*]const u32 = @ptrCast(@alignCast(s));
    for (0..200) |r| {
        const c = cache[r * LINE_WORDS ..][0..LINE_WORDS];
        const line = words[r * LINE_WORDS ..][0..LINE_WORDS];
        var diff: u32 = 0;
        for (c, line, 0..) |*k, w, i| {
            const v = if (i & 1 == 0) w & PLANE0_OUT else w;
            diff |= k.* ^ v;
            k.* = v;
        }
        if (all or diff != 0) {
            expandLine(s, r);
            borders(r);
        }
    }
}

/// The scroll at time t (Q10 VBLs): the original's f & 31, in quarter texels.
pub fn voffAt(t: u32) u16 {
    return @intCast((t >> 8) & (TH - 1));
}

/// `s`: the ST screen on show; `dirty`: it changed since the last frame.
pub fn draw(fb: *zg.LogicalFB, s: *const st.Screen, t: u32, dirty: bool) void {
    if (dirty) sync(s, false);
    R.restore(fb, 0, 0, R.W, R.H);
    const tx = v2.Texture{ .pixels = tex, .stride = TW, .umask = TW - 1, .vmask = TH - 1 };
    v2.map(fb, tx, 0, 0, R.W, R.H, map, R.W, 0, voffAt(t), .{ .mt = @intFromEnum(zg.Minterm.glenz) });
    R.ops += 1;
}
