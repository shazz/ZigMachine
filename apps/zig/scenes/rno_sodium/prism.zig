// --------------------------------------------------------------------------
// The textured rotating prism, $119A (part 5), and its pre-built blocks $1388.
//
// A square-section box turning about the screen's horizontal axis: four edges
// 90 degrees apart, only the long faces drawn. Each edge has a "nearness" X
// (1..33) and a screen line Y. A face is visible when its lower edge is below
// its upper one (the back-face cull; exactly two always are), and down it the
// nearness and the texture row are interpolated in 8.8 fixed point, straight
// out of divs.w / divu.w.
//
// The texturing is all precalc: block n (1..33) is the 64-row texture scaled
// to 128+2(n-1) pixels wide, centred in 192, and shaded through row n-1 of the
// shade table (far = fogged to white, near = the texture's own 0..7). Block 0
// is solid colour 7. A line of the face is then one 96-byte copy.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");
const st = @import("st.zig");

const BLOCKS: usize = 34;
const BLOCK_ROWS: usize = 64;
const W: usize = 192; // the strip, px 128..319
const ROW_BYTES: usize = st.STRIP_BYTES; // 96
const BLOCK_BYTES: usize = BLOCK_ROWS * ROW_BYTES; // 6144

/// $280E4: 34 blocks x 64 rows x 96 bytes of ST 4-plane. Built once at init,
/// as $1388 built it; module scope, as it is this cart's alone.
var blocks: [BLOCKS * BLOCK_BYTES]u8 = undefined;

/// $1388: block 0 solid 7, then 33 scaled, shaded copies of the texture.
pub fn buildBlocks() void {
    const solid = [8]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0 };
    for (0..BLOCK_BYTES / 8) |g| blocks[g * 8 ..][0..8].* = solid;
    // The chunky buffer is filled with 7 once and never cleared: the spans
    // only grow, so every block overwrites the last one's texels.
    var chunky: [BLOCK_ROWS][W]u8 = undefined;
    for (&chunky) |*r| @memset(r, 7);
    for (0..BLOCKS - 1) |i| {
        const x0 = 32 - i;
        const w = 128 + 2 * i;
        const step: u16 = @intCast(0x4000 / w);
        const shade = A.prism_shade[i * 8 ..][0..8];
        for (&chunky, 0..) |*line, r| {
            var d6: u16 = 0;
            for (line[x0 .. x0 + w]) |*px| {
                px.* = shade[A.prism_tex[r * 64 + (d6 >> 8)] & 7];
                d6 +%= step;
            }
        }
        c2p(&chunky, blocks[(i + 1) * BLOCK_BYTES ..][0..BLOCK_BYTES]);
    }
}

/// Chunky 0..7 to ST planar: bit p of a pixel to plane p, pixel 0 = MSB.
fn c2p(chunky: *const [BLOCK_ROWS][W]u8, out: []u8) void {
    for (chunky, 0..) |*line, r| {
        for (0..W / 16) |g| {
            var planes = [4]u16{ 0, 0, 0, 0 };
            for (line[g * 16 ..][0..16]) |v| {
                for (&planes, 0..) |*p, b| p.* = (p.* << 1) | ((v >> @intCast(b)) & 1);
            }
            for (planes, 0..) |p, b| std.mem.writeInt(u16, out[r * ROW_BYTES + g * 8 + b * 2 ..][0..2], p, .big);
        }
    }
}

/// One frame into `scr` (the back buffer the flip just handed over).
pub fn frame(scr: *[st.BYTES]u8, f: u16) void {
    var x: [4]i32 = undefined;
    var y: [4]i32 = undefined;
    edges(f, &x, &y);
    // The original clears and fills these 200 LONGS over the same $6BDE4 the
    // other effects share as words. Nothing reads that before part 6's $04A0
    // clears it again, so the long list is kept apart from st.Machine.list.
    var list: [st.LINES]u32 = @splat(0); // lines off the faces: block 0
    for (0..4) |k| {
        const n = (k + 1) & 3;
        const h = y[n] - y[k];
        if (h > 0) face(&list, x[k], x[n], y[k], h);
    }
    for (list, 0..) |off, line| {
        @memcpy(scr[line * st.LINE + st.STRIP ..][0..ROW_BYTES], blocks[off..][0..ROW_BYTES]);
    }
}

/// The four edges: theta swings with sw(f*4)*6, then +90 degrees an edge.
fn edges(f: u16, x: *[4]i32, y: *[4]i32) void {
    const e = (@as(u32, f) << 2) & 0x7FE;
    var a: u32 = @as(u32, @bitCast(A.sw(e) * 6)) & 0x7FE;
    for (0..4) |k| {
        // asl.w #4 then asr.w #8: the 16-bit shift, then the arithmetic one.
        const s16: i16 = @truncate(A.sw(a) << 4);
        x[k] = (@as(i32, s16) >> 8) + 17;
        // $099A is cos; muls.w #92 then asr.w #8 on the low word.
        const c16: i16 = @truncate(A.sineEntry((a >> 1) + 256) * 92);
        y[k] = 100 - (@as(i32, c16) >> 8);
        a = (a + 0x200) & 0x7FE;
    }
}

/// $1334: one face, h > 0 lines from y0, nearness xa -> xb.
fn face(list: *[st.LINES]u32, xa: i32, xb: i32, y0: i32, h: i32) void {
    var d3: u16 = @truncate(@as(u32, @bitCast(xa << 8)));
    const d4: u16 = @truncate(@as(u32, @bitCast(@divTrunc((xb - xa) * 256, h)))); // divs.w
    const d7: u16 = @intCast(@divTrunc(0x4000, h)); // divu.w
    var d6: u16 = 0;
    for (0..@intCast(h)) |j| {
        const blk: u32 = ((d3 +% 0x80) & 0x3F00) >> 8;
        const v: u32 = (d6 >> 8) & 63;
        list[@as(usize, @intCast(y0)) + j] = blk * BLOCK_BYTES + v * ROW_BYTES;
        d3 +%= d4;
        d6 +%= d7;
    }
}
