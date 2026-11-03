// --------------------------------------------------------------------------
// NATRIUM ZIG mode, parts 3 and 6: the env-mapped chamfered cube and prism,
// a new frame EVERY host frame (the original: one render every 3 VBLs, into a
// 128x128 chunky buffer, shown as 2x2 dithered cells over two fields).
//
// The original's object, matrix and sphere map ($F27A, $F34A, $F38C, envmap.zig)
// in Q16 with ZM-X mulsh16: angles f, 2f, 3f (fixtrig, 1024 steps a turn as
// SIN), x = 2 Rx / (Rz + 800) at ONE pixel a sample -- the size the 2x2 cells
// gave it -- and U, V = the rotated normal, the 128x128 map's 8.8 texels. Its
// back-face test is the original's; both objects are convex, so the faces
// left never overlap and need no sort. Every face goes into ONE span list and
// ONE CHISEL AFFINE op draws them (obj/texmap.zig sets the spans up), from
// env_tex at levels 16..28: true colours, no dither (zig_mode.zig's palette).
// The object is not clipped to the original's 80x80 window. Before it, one
// blit restores the picture under the last frame's box.
// f: the original shows render(f - 3) as the newest of its two fields; this
// draws f - 3 + the frame's fraction (Q10 VBLs), a third of the original's
// step a VBL, at the same pace.
// No envmap.zig state is touched: its chunky buffer and span table stay the
// original's, so Z back gives its very frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const v2 = zg.chisel_v2;
const zmx = @import("rom_sdk").zmx;
const texmap = @import("../obj/texmap.zig");
const A = @import("assets.zig");
const envmap = @import("envmap.zig");
const R = @import("zig_res.zig");

const MAX_SPANS = 2048;
/// The object's centre in the window: chunky 63 is ST x 2 * (63 - 24).
const CX: i32 = @as(i32, R.OX) + 78;
const CY: i32 = @as(i32, R.OY) + 78;

fn mulsh16(a: i32, b: i32) i32 {
    return zmx.zmMulsh16(a, b);
}
const Spans = texmap.Spans(v2.Span, mulsh16);

var spans: []v2.Span = &.{};
/// The box drawn last frame: x0, y0, x1, y1 (empty when x1 <= x0).
pub var box: [4]i32 = .{ 0, 0, 0, 0 };
/// Spans the last frame drew (zig_api).
pub var nspans: usize = 0;

pub fn build() bool {
    spans = zg.mem.alloc(v2.Span, MAX_SPANS) orelse return false;
    return true;
}

/// Entering the part: the picture is on the plane, nothing to restore.
pub fn reset() void {
    box = .{ 0, 0, 0, 0 };
}

inline fn word(o: envmap.Object, i: usize) i32 {
    return @as(i16, @bitCast(A.be16(o.data, i)));
}

/// $F27A in Q16 at time t (Q10 VBLs): angles f, 2f, 3f.
pub fn matrix(t: u32, m: *[9]i32) void {
    const a = t *% (1 << 12);
    const sa = trig.sin(a);
    const ca = trig.cos(a);
    const sb = trig.sin(2 *% a);
    const cb = trig.cos(2 *% a);
    const sg = trig.sin(3 *% a);
    const cg = trig.cos(3 *% a);
    const sbcc = mulsh16(sb, cg);
    const sbsc = mulsh16(sb, sg);
    m.* = .{
        mulsh16(cb, cg),                       mulsh16(cb, sg),                       -sb,
        mulsh16(sa, sbcc) - mulsh16(sg, ca),   mulsh16(sa, sbsc) + mulsh16(cg, ca),   mulsh16(sa, cb),
        mulsh16(ca, sbcc) + mulsh16(sg, sa),   mulsh16(ca, sbsc) - mulsh16(cg, sa),   mulsh16(ca, cb),
    };
}

inline fn dot(m: *const [9]i32, row: usize, x: i32, y: i32, z: i32) i32 {
    return m[row * 3] * x + m[row * 3 + 1] * y + m[row * 3 + 2] * z;
}

pub fn draw(fb: *zg.LogicalFB, o: envmap.Object, t: u32) void {
    var m: [9]i32 = undefined;
    matrix(t, &m);
    var p: [envmap.MAX_V]texmap.P = undefined;
    var uv: [envmap.MAX_V]texmap.UV = undefined;
    const faces = 8 + 3 * o.nv;
    const normals = faces + 3 * o.nf;
    var nb = [4]i32{ R.W, R.H, 0, 0 };
    for (0..o.nv) |i| {
        const x = word(o, 8 + 3 * i);
        const y = word(o, 9 + 3 * i);
        const z = word(o, 10 + 3 * i);
        const d = (dot(&m, 2, x, y, z) >> 16) + 800; // > 0: envmap.zig proves it
        const sx = CX + @divFloor(dot(&m, 0, x, y, z), 128 * d); // 2 Rx / d, Rx = Q16 / 256... in pixels
        const sy = CY + @divFloor(dot(&m, 1, x, y, z), 128 * d);
        p[i] = .{ @intCast(sx), @intCast(sy) };
        nb = .{ @min(nb[0], sx), @min(nb[1], sy), @max(nb[2], sx + 1), @max(nb[3], sy + 1) };
        const nx = word(o, normals + 3 * i) << 14;
        const ny = word(o, normals + 3 * i + 1) << 14;
        const nz = word(o, normals + 3 * i + 2) << 14;
        // U = (m0 . n) / 4 + $4000 in 8.8, so 16.16 = Q16 m0 . n / 4 + $400000
        const u = mulsh16(m[0], nx) +% mulsh16(m[1], ny) +% mulsh16(m[2], nz);
        const v = mulsh16(m[3], nx) +% mulsh16(m[4], ny) +% mulsh16(m[5], nz);
        uv[i] = .{ @as(u32, @bitCast(u)) +% 0x400000, @as(u32, @bitCast(v)) +% 0x400000 };
    }
    R.restore(fb, box[0], box[1], box[2] - box[0], box[3] - box[1]);
    box = nb;
    var s = Spans{ .out = spans, .w = R.W, .h = R.H };
    for (0..o.nf) |f| {
        var k: [3]usize = undefined;
        for (&k, 0..) |*e, n| e.* = @as(usize, @intCast(word(o, faces + 3 * f + n))) >> 1;
        const a = p[k[0]];
        const b = p[k[1]];
        const c = p[k[2]];
        const d2 = (@as(i32, a[1]) - b[1]) * (@as(i32, a[0]) - c[0]);
        const d1 = (@as(i32, a[1]) - c[1]) * (@as(i32, a[0]) - b[0]);
        if (d2 <= d1) continue; // $EF22: facing away
        s.tri(.{ a, b, c }, .{ uv[k[0]], uv[k[1]], uv[k[2]] });
    }
    nspans = s.n;
    const tex = v2.Texture{ .pixels = R.env, .stride = R.TEX, .umask = R.TEX - 1, .vmask = R.TEX - 1 };
    v2.affine(fb, tex, spans[0..s.n], .{});
    R.ops += 1;
}
