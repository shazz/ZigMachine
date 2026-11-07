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
const zg = @import("zigos");
const v2 = zg.chisel_v2;
const st = @import("st.zig");
const A = @import("assets.zig");
const M = @import("zig_math.zig");
const R = @import("zig_res.zig");

pub const TW: usize = 32; // 16 blob columns, then the same inverted
pub const TH: usize = 128; // 32 blob rows in quarter texels
const LINE_WORDS: usize = 20 * 3; // planes 1..3 of an ST line

pub var map: []u16 = &.{};
pub var tex: []u8 = &.{};
var cache: []u16 = &.{}; // planes 1..3 of each ST line as last expanded

pub fn build() bool {
    map = zg.mem.alloc(u16, R.W * R.H) orelse return false;
    tex = zg.mem.alloc(u8, TW * TH) orelse return false;
    cache = zg.mem.alloc(u16, 200 * LINE_WORDS) orelse return false;
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

/// ST line r's planes 1..3 into R.bg, edges carried out to the side borders.
fn expandLine(s: *const st.Screen, r: usize) void {
    const out = R.bg[(R.OY + r) * R.W ..][0..R.W];
    for (0..20) |g| {
        const o = r * st.LINE + g * 8;
        const p1 = st.getW(s, o + 2);
        const p2 = st.getW(s, o + 4);
        const p3 = st.getW(s, o + 6);
        for (0..16) |b| {
            const k: u4 = @intCast(15 - b);
            const pen = ((p1 >> k) & 1) << 1 | ((p2 >> k) & 1) << 2 | ((p3 >> k) & 1) << 3;
            out[R.OX + g * 16 + b] = @intCast(pen);
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

/// Expand the lines whose planes 1..3 changed (`all`: every line).
pub fn sync(s: *const st.Screen, all: bool) void {
    for (0..200) |r| {
        const c = cache[r * LINE_WORDS ..][0..LINE_WORDS];
        var changed = all;
        for (0..20) |g| for (0..3) |p| {
            const w = st.getW(s, r * st.LINE + g * 8 + 2 + 2 * p);
            if (c[g * 3 + p] != w) {
                c[g * 3 + p] = w;
                changed = true;
            }
        };
        if (changed) {
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
