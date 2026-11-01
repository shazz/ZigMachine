// --------------------------------------------------------------------------
// CHISEL v2 test cart: one frame of each mode, every pixel drawn by CHISEL.
//   ROTOZOOM  AFFINE, a span a row, the matrix turning and breathing
//   MODE 7    AFFINE, a span a row below the horizon, perspective from a
//             per-row reciprocal table (the SNES's HDMA matrix, as spans)
//   TUNNEL    MAP over the whole plane, the offsets moving every frame
//   SPRITES   keyed bobs read in all four orientations, COLL_EN on: the corner
//             shows whether any landed on another
//   FILL      a pentagram's edges, one XORed pixel a row (the CPU), filled by one
//             in-place BLIT with IFE: odd-even, so the centre stays hollow
// Integer only per frame: zg.fixtrig angles, Q16.16 steps.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const trig = zg.fixtrig;
const v2 = zg.chisel_v2;
const assets = @import("assets.zig");
const LogicalFB = zg.LogicalFB;

pub const W: i32 = 320;
pub const H: i32 = 200;
const HORIZON: i32 = 48;
pub const STAR_COL: u8 = 50;

pub const Modes = struct {
    spans: []v2.Span = &.{},
    recip: [200]i32 = undefined, // MODE 7: 65536 * 64 / (y - HORIZON)
    t: u32 = 0,

    pub fn init(m: *Modes) bool {
        m.spans = zg.mem.alloc(v2.Span, @intCast(H)) orelse return false;
        for (&m.recip, 0..) |*r, y| {
            const d: i32 = @as(i32, @intCast(y)) - HORIZON;
            r.* = if (d > 0) @divTrunc(64 << 16, d) else 0;
        }
        return true;
    }

    fn tex(a: *const assets.Assets) v2.Texture {
        return .{ .pixels = a.tex, .stride = assets.TEX, .umask = assets.TEX - 1, .vmask = assets.TEX - 1 };
    }

    pub fn rotozoom(m: *Modes, fb: *LogicalFB, a: *const assets.Assets) void {
        const ang: trig.Angle = m.t *% (1 << 24);
        const zoom: i64 = trig.ONE + @divTrunc(trig.sin(m.t *% (3 << 23)), 2); // 0.5 .. 1.5
        const du: i64 = @divTrunc(@as(i64, trig.cos(ang)) * zoom, trig.ONE);
        const dv: i64 = @divTrunc(@as(i64, trig.sin(ang)) * zoom, trig.ONE);
        for (m.spans, 0..) |*s, y| {
            const yy: i64 = @as(i64, @intCast(y)) - 100;
            const u0 = (64 << 16) - 160 * du - yy * dv;
            const v0 = (64 << 16) - 160 * dv + yy * du;
            s.* = .{ .x0 = 0, .x1 = W, .y = @intCast(y), .u0 = wrap(u0), .v0 = wrap(v0), .du = wrap(du), .dv = wrap(dv) };
        }
        v2.affine(fb, tex(a), m.spans, .{});
    }

    pub fn mode7(m: *Modes, fb: *LogicalFB, a: *const assets.Assets) void {
        const ang: trig.Angle = m.t *% (1 << 23);
        const c: i64 = trig.cos(ang);
        const sn: i64 = trig.sin(ang);
        const cam_u: i64 = @as(i64, m.t) * (3 << 15); // forward motion
        var n: usize = 0;
        var y: i32 = HORIZON + 1;
        while (y < H) : (y += 1) {
            const scale: i64 = m.recip[@intCast(y)]; // texels a pixel, Q16
            const dist = scale * 80; // the row's distance in front of the camera, Q16
            const du = @divTrunc(c * scale, trig.ONE);
            const dv = @divTrunc(-sn * scale, trig.ONE);
            const cu = cam_u + @divTrunc(sn * dist, trig.ONE);
            const cv = @divTrunc(c * dist, trig.ONE);
            m.spans[n] = .{ .x0 = 0, .x1 = W, .y = @intCast(y), .u0 = wrap(cu - 160 * du), .v0 = wrap(cv - 160 * dv), .du = wrap(du), .dv = wrap(dv) };
            n += 1;
        }
        fb.fillRect(0, 0, @intCast(W), @intCast(HORIZON + 1), 2); // the sky: a FILL
        v2.affine(fb, tex(a), m.spans[0..n], .{});
    }

    pub fn tunnel(m: *Modes, fb: *LogicalFB, a: *const assets.Assets) void {
        v2.map(fb, tex(a), 0, 0, @intCast(W), @intCast(H), a.map, assets.MAP_W, @truncate(m.t), @truncate(m.t * 3), .{});
    }

    /// The four orientations of the arrow, drifting into each other; true when any collided.
    pub fn sprites(m: *Modes, fb: *LogicalFB, a: *const assets.Assets) bool {
        fb.fillRect(0, 0, @intCast(W), @intCast(H), 0);
        v2.clearCollision();
        const r: i32 = 20 + @divTrunc(trig.sin(m.t *% (1 << 24)) * 30, trig.ONE); // radius, 0 .. 50: they meet
        const xs = [4]i32{ 160 - r - 16, 160 + r, 160 - r - 16, 160 + r };
        const ys = [4]i32{ 100 - r - 16, 100 - r - 16, 100 + r, 100 + r };
        for (0..4) |k| {
            v2.bobFlip(fb, @intCast(xs[k]), @intCast(ys[k]), a.spr, assets.SPR, assets.SPR, assets.SPR, 0, k & 1 != 0, k & 2 != 0, true);
        }
        return v2.collided();
    }

    pub fn star(m: *Modes, fb: *LogicalFB) void {
        fb.fillRect(0, 0, @intCast(W), @intCast(H), 0);
        const ang0: trig.Angle = m.t *% (1 << 23);
        var px: [5]i32 = undefined;
        var py: [5]i32 = undefined;
        for (0..5) |k| {
            const a: trig.Angle = ang0 +% @as(u32, @intCast(k)) *% 858993459; // a fifth of a turn
            px[k] = 160 + @divTrunc(trig.cos(a) * 80, trig.ONE);
            py[k] = 100 + @divTrunc(trig.sin(a) * 80, trig.ONE);
        }
        for (0..5) |k| edge(fb, px[k], py[k], px[(k + 2) % 5], py[(k + 2) % 5]); // the pentagram
        v2.areaFill(fb, 60, 0, 200, @intCast(H), .inclusive, false);
    }
};

/// The Amiga's fill edge: ONE pixel a row, XORed, over the half-open rows [top, bottom), so two
/// edges meeting at a vertex toggle it once (the CPU's per-row work; CHISEL fills the rows).
fn edge(fb: *LogicalFB, x0: i32, y0: i32, x1: i32, y1: i32) void {
    if (y0 == y1) return;
    const ax, const ay, const bx, const by = if (y0 < y1) .{ x0, y0, x1, y1 } else .{ x1, y1, x0, y0 };
    var y = ay;
    while (y < by) : (y += 1) {
        const x = ax + @divFloor((bx - ax) * (y - ay), by - ay);
        const i = @as(usize, @intCast(y)) * fb.stride + @as(usize, @intCast(x));
        fb.fb[i] ^= STAR_COL;
    }
}

inline fn wrap(v: i64) u32 {
    return @truncate(@as(u64, @bitCast(v)));
}
