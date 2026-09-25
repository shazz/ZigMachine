// --------------------------------------------------------------------------
// $F3D0: the env-mapper's affine triangle filler, ported from the bit-exact
// model (re/envmap/envmap_ref.py). Constant gradients per triangle; the texture
// position is ONE packed long (V high word, U low word) stepped by one 32-bit
// add per line, so a carry out of U leaks into V -- kept. The per-pixel steps
// are baked into a 128-entry displacement table, which the original patched
// into an unrolled `move.b d16(a1),-(a4)` span; spans wider than the triangle's
// middle width read stale entries, also kept.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");

pub const SIZE = 128; // the chunky buffer is 128 x 128, stride 128
pub const Vert = struct { x: i32, y: i32, v: i32, u: i32 };

pub inline fn w16(x: i64) i32 {
    return @as(i16, @truncate(x));
}
pub inline fn l32(x: i64) i32 {
    return @truncate(x);
}
inline fn hiw(v: i32) i32 {
    return @as(i16, @truncate(v >> 16));
}
inline fn pack(hi: i32, lo: i32) i32 {
    return @bitCast((@as(u32, @as(u16, @truncate(@as(u32, @bitCast(hi))))) << 16) |
        @as(u16, @truncate(@as(u32, @bitCast(lo)))));
}

/// hiword(2 * num * RECIP[n]): a 16-bit gradient over n lines or pixels.
inline fn grad(num: i32, n: i32) i32 {
    return hiw(l32(2 * @as(i64, w16(num)) * A.recip[@as(u8, @truncate(@as(u32, @bitCast(n))))]));
}

/// $6F81A's 256x256 tiling of the 128x128 map, read at a flat offset; values
/// are the TEXT levels doubled ($C2DC).
inline fn tex256(addr: i32) u8 {
    const a: u32 = @as(u32, @bitCast(addr)) & 0xFFFF;
    return 2 * A.env_tex[((a >> 8) & 127) * 128 + (a & 127)];
}

/// $F61C: the span table for a triangle's width w and per-pixel dV, dU.
fn buildTable(table: *[128]u16, w: i32, dv: i32, du: i32) void {
    const d5: u32 = @bitCast(pack(w16(@as(i64, du) << 8), dv));
    const dui: i32 = w16(du) >> 8;
    var d6: u32 = 0;
    var d7: i32 = 0;
    const n: usize = @as(usize, @intCast(w & 0x7F)) + 1;
    for (table[0..n]) |*t| {
        t.* = @truncate((d6 & 0xFF00) | (@as(u32, @bitCast(d7)) & 0xFF));
        const s: u64 = @as(u64, d6) + d5;
        d6 = @truncate(s);
        d7 = (d7 + dui + @as(i32, @intCast(s >> 32))) & 0xFF;
    }
}

const Edge = struct { xl: i32, xr: i32, tex: i32 };

/// $F776: n lines from y0; xl/xr 16.16, tex the packed V:U long.
fn spans(buf: *[SIZE * SIZE]u8, table: *const [128]u16, y0: i32, n: i32, e0: Edge, sl: i32, sr: i32, dtex: i32) Edge {
    var e = e0;
    var j: i32 = 0;
    while (j < n) : (j += 1) {
        const a = hiw(e.xl);
        const wdt = w16(hiw(e.xr) - a);
        if (wdt > 0) {
            const t: u32 = @bitCast(e.tex);
            const base = w16((@as(u32, @bitCast(hiw(e.tex))) & 0xFF00) | ((t & 0xFFFF) >> 8));
            const row = (y0 + j) * SIZE + a;
            var k: i32 = 0;
            // Never taken by these objects (the model saw no stray reads or
            // writes); the guards only keep a bad frame inside the buffers.
            while (k < wdt and k < 128) : (k += 1) {
                const at = row + k;
                if (at < 0 or at >= SIZE * SIZE) continue;
                const d: i32 = @as(i16, @bitCast(table[@intCast(k)]));
                buf[@intCast(at)] = tex256(base + d);
            }
        }
        e.xl = l32(@as(i64, e.xl) + sl);
        e.xr = l32(@as(i64, e.xr) + sr);
        e.tex = l32(@as(i64, e.tex) + dtex);
    }
    return e;
}

fn slope(a: Vert, b: Vert) i32 {
    return l32(2 * @as(i64, w16(b.x - a.x)) * A.recip[@as(u8, @truncate(@as(u32, @bitCast(b.y - a.y))))]);
}

fn gradient(a: Vert, b: Vert) i32 {
    const dy = b.y - a.y;
    return pack(grad(b.v - a.v, dy), grad(b.u - a.u, dy));
}

pub fn triangle(buf: *[SIZE * SIZE]u8, table: *[128]u16, in: [3]Vert) void {
    var v = in;
    if (v[0].y > v[1].y) std.mem.swap(Vert, &v[0], &v[1]);
    if (v[1].y > v[2].y) std.mem.swap(Vert, &v[1], &v[2]);
    if (v[0].y > v[1].y) std.mem.swap(Vert, &v[0], &v[1]);
    const X0 = v[0].x << 16;
    const X1 = v[1].x << 16;
    const s01 = slope(v[0], v[1]);
    const s12 = slope(v[1], v[2]);
    const s02 = slope(v[0], v[2]);
    const g01 = gradient(v[0], v[1]);
    const g12 = gradient(v[1], v[2]);
    const g02 = gradient(v[0], v[2]);
    const t0 = pack(v[0].v, v[0].u);
    const t1 = pack(v[1].v, v[1].u);
    if (v[1].y - v[0].y > 0) {
        const dy = v[1].y - v[0].y;
        const xm = l32((@as(i64, w16(s02 >> 8)) * dy << 8) + X0);
        const vm = w16(@as(i64, hiw(g02)) * dy + v[0].v);
        const um = w16(@as(i64, w16(g02)) * dy + v[0].u);
        const left01 = s01 < s02;
        var wx: i32 = if (left01) hiw(l32(@as(i64, xm) - X1)) else hiw(l32(@as(i64, X1) - xm));
        if (wx == 0) wx = 1;
        const dv = if (left01) grad(vm - v[1].v, wx) else grad(v[1].v - vm, wx);
        const du = if (left01) grad(um - v[1].u, wx) else grad(v[1].u - um, wx);
        buildTable(table, wx, dv, du);
        const gl = if (left01) g01 else g02;
        const sl = if (left01) s01 else s02;
        const sr = if (left01) s02 else s01;
        const e = spans(buf, table, v[0].y, dy, .{ .xl = X0, .xr = X0, .tex = t0 }, sl, sr, gl);
        const n2 = v[2].y - v[1].y;
        if (n2 > 0) {
            if (left01) {
                _ = spans(buf, table, v[1].y, n2, .{ .xl = X1, .xr = e.xr, .tex = t1 }, s12, sr, g12);
            } else {
                _ = spans(buf, table, v[1].y, n2, .{ .xl = e.xl, .xr = X1, .tex = e.tex }, sl, s12, gl);
            }
        }
        return;
    }
    // Flat top: the edges are 0->2 and 1->2.
    const n = v[2].y - v[0].y;
    if (n == 0) return;
    var l = Edge{ .xl = X0, .xr = X1, .tex = t0 };
    var tr = t1;
    var gl = g02;
    var sl = s02;
    var sr = s12;
    if (X1 < X0) {
        l = .{ .xl = X1, .xr = X0, .tex = t1 };
        tr = t0;
        gl = g12;
        sl = s12;
        sr = s02;
    }
    var wx = w16(hiw(l.xr) - hiw(l.xl));
    if (wx == 0) wx = 1;
    buildTable(table, wx, grad(hiw(tr) - hiw(l.tex), wx), grad(w16(tr) - w16(l.tex), wx));
    _ = spans(buf, table, v[0].y, n, l, sl, sr, gl);
}
