// --------------------------------------------------------------------------
// Parts 3 and 6: the env-mapped chamfered cube ($14128) and pentagonal prism
// ($13F38), ported from the bit-exact model (re/envmap/envmap_ref.py).
//
//   $F27A  3x3 rotation from angles f, 2f, 3f (muls.w + asr.l #8 everywhere)
//   $F34A  vertices: R = M.v;  $EEF0: x = divs(Rx, Rz/256 + 800) + 63
//   $F38C  per-vertex normals -> sphere-map U, V (8.8, one 128x128 tile)
//   $EF22  back-face cull on a 16-bit cmp;  $F070 two-pass LSD radix sort,
//          reversed (far first);  $F3D0 the filler (envfill.zig)
//   $EB42  128x128 chunky -> planes 2,3 of one line parity, 2x2 ordered dither
//
// The object only rotates: no translation, no path. One render every 3 VBLs.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const fill = @import("envfill.zig");
const w16 = fill.w16;
const l32 = fill.l32;

pub const MAX_V = 24;
pub const MAX_F = 44;

pub const Object = struct { data: []const u8, nv: usize, nf: usize };

pub fn object(data: []const u8) Object {
    return .{ .data = data, .nv = A.be16(data, 0), .nf = A.be16(data, 1) };
}

inline fn word(o: Object, i: usize) i32 {
    return @as(i16, @bitCast(A.be16(o.data, i)));
}

/// The chunky buffer ($B791A) and the span table the filler patches.
pub var chunky: [fill.SIZE * fill.SIZE]u8 = undefined;
var span_table: [128]u16 = undefined;

fn matrix(f: u16, m: *[9]i32) void {
    const ff: u32 = f;
    const a = ((2 * ff) & 0x7FE) >> 1; // angle indices f, 2f, 3f
    const b = ((4 * ff) & 0x7FE) >> 1;
    const g = ((6 * ff) & 0x7FE) >> 1;
    const S = struct {
        fn s(i: u32) i64 {
            return A.sin(i);
        }
        fn c(i: u32) i64 { // cos = SIN[i + 256]
            return A.sin(i + 256);
        }
    };
    const sbcc = w16((S.s(b) * S.c(g)) >> 8);
    const sbsc = w16((S.s(b) * S.s(g)) >> 8);
    m[0] = w16((S.c(b) * S.c(g)) >> 8);
    m[1] = w16((S.c(b) * S.s(g)) >> 8);
    m[2] = w16(-S.s(b));
    m[3] = w16((S.s(a) * sbcc - S.s(g) * S.c(a)) >> 8);
    m[4] = w16((S.s(a) * sbsc + S.c(g) * S.c(a)) >> 8);
    m[5] = w16((S.s(a) * S.c(b)) >> 8);
    m[6] = w16((S.c(a) * sbcc + S.s(g) * S.s(a)) >> 8);
    m[7] = w16((S.c(a) * sbsc - S.c(g) * S.s(a)) >> 8);
    m[8] = w16((S.c(a) * S.c(b)) >> 8);
}

inline fn dot(m: *const [9]i32, row: usize, x: i32, y: i32, z: i32) i64 {
    return @as(i64, m[row * 3]) * x + @as(i64, m[row * 3 + 1]) * y + @as(i64, m[row * 3 + 2]) * z;
}

/// $EE5A: clear the visible 80x80 window to 8 (level 4) and render frame f.
pub fn render(o: Object, f: u16) void {
    for (24..104) |y| @memset(chunky[y * fill.SIZE + 24 ..][0..80], 8);
    @memset(&span_table, 0);
    var m: [9]i32 = undefined;
    matrix(f, &m);
    var pv: [MAX_V]fill.Vert = undefined;
    var zk: [MAX_V]u32 = undefined;
    const faces = 8 + 3 * o.nv;
    const normals = faces + 3 * o.nf;
    for (0..o.nv) |i| {
        const x = word(o, 8 + 3 * i);
        const y = word(o, 9 + 3 * i);
        const z = word(o, 10 + 3 * i);
        const rx = l32(dot(&m, 0, x, y, z));
        const ry = l32(dot(&m, 1, x, y, z));
        const z8 = l32(dot(&m, 2, x, y, z)) >> 8;
        zk[i] = @as(u32, @bitCast(z8 +% 0x8000)) & 0xFFFF;
        // |z8| <= 170 for these objects, so d is never 0.
        const d = w16(@as(i64, z8) + 800);
        const nx = word(o, normals + 3 * i);
        const ny = word(o, normals + 3 * i + 1);
        const nz = word(o, normals + 3 * i + 2);
        pv[i] = .{
            .x = w16(@as(i64, w16(@divTrunc(rx, d))) + 63), // divs.w: truncated, a word
            .y = w16(@as(i64, w16(@divTrunc(ry, d))) + 63),
            .u = w16((dot(&m, 0, nx, ny, nz) >> 2) + 0x4000),
            .v = w16((dot(&m, 1, nx, ny, nz) >> 2) + 0x4000),
        };
    }
    var vis: [MAX_F]u8 = undefined;
    var key: [MAX_F]u16 = undefined;
    var nvis: usize = 0;
    for (0..o.nf) |i| {
        const a = pv[@as(usize, @intCast(word(o, faces + 3 * i))) >> 1];
        const b = pv[@as(usize, @intCast(word(o, faces + 3 * i + 1))) >> 1];
        const c = pv[@as(usize, @intCast(word(o, faces + 3 * i + 2))) >> 1];
        const d2 = w16(@as(i64, a.y - b.y) * (a.x - c.x));
        const d1 = w16(@as(i64, a.y - c.y) * (a.x - b.x));
        if (d2 > d1) {
            vis[nvis] = @intCast(i);
            var k: u32 = 0;
            for (0..3) |n| k += zk[@as(usize, @intCast(word(o, faces + 3 * i + n))) >> 1];
            key[i] = @truncate(k);
            nvis += 1;
        }
    }
    var order: [MAX_F]u8 = undefined;
    radixSort(vis[0..nvis], &key, order[0..nvis]);
    var r = nvis;
    while (r > 0) { // reversed: largest key (farthest) first
        r -= 1;
        const i: usize = order[r];
        var tri: [3]fill.Vert = undefined;
        for (&tri, 0..) |*t, n| t.* = pv[@as(usize, @intCast(word(o, faces + 3 * i + n))) >> 1];
        fill.triangle(&chunky, &span_table, tri);
    }
}

/// $F070: stable LSD radix sort on the 16-bit key, low byte then high byte.
fn radixSort(in: []const u8, key: *const [MAX_F]u16, out: []u8) void {
    var tmp: [MAX_F]u8 = undefined;
    stablePass(in, key, tmp[0..in.len], 0);
    stablePass(tmp[0..in.len], key, out, 8);
}

fn stablePass(in: []const u8, key: *const [MAX_F]u16, out: []u8, comptime shift: u4) void {
    var count = [_]usize{0} ** 257;
    for (in) |i| count[((key[i] >> shift) & 0xFF) + 1] += 1;
    for (1..257) |b| count[b] += count[b - 1];
    for (in) |i| {
        const b = (key[i] >> shift) & 0xFF;
        out[count[b]] = i;
        count[b] += 1;
    }
}

/// $EB42: chunky rows 24..103 -> planes 2,3 of lines 2j + parity, x from 0.
/// Rows 72..79 of the window convert only 72 columns: x144..159 of the last
/// 16 lines is never written.
pub fn c2p(s: *st.Screen, parity: u1) void {
    for (0..80) |j| {
        const groups: usize = if (j < 72) 10 else 9;
        const line = 2 * j + parity;
        const src = chunky[(24 + j) * fill.SIZE + 24 ..];
        for (0..groups) |g| {
            var p2: u16 = 0;
            var p3: u16 = 0;
            for (0..8) |k| {
                const c: usize = (src[g * 8 + k] >> 1) & 15;
                const sh: u4 = @intCast(14 - 2 * k);
                p2 |= @as(u16, A.dither[c * 4 + parity]) << sh; // 2 bits, bit 1 = left pixel
                p3 |= @as(u16, A.dither[c * 4 + 2 + parity]) << sh;
            }
            const o = line * st.LINE + g * 8;
            st.setW(s, o + 4, p2);
            st.setW(s, o + 6, p3);
        }
    }
}
