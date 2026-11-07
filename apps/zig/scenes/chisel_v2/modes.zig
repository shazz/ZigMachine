// --------------------------------------------------------------------------
// CHISEL v2 test cart: one frame of each mode, every pixel drawn by CHISEL.
//   ROTOZOOM  AFFINE, a span a row, the matrix turning and breathing
//   MODE 7    AFFINE, a span a row below the horizon, perspective from a
//             per-row reciprocal table (the SNES's HDMA matrix, as spans)
//   TUNNEL    MAP over the whole plane, the offsets moving every frame; the
//             map is bigger than the plane, so the bend is a window into it
//   SPRITES   keyed bobs read in all four orientations, COLL_EN on: the corner
//             shows whether any landed on another
//   FILL      a pentagram's edges, one XORed pixel a row (the CPU), filled by one
//             in-place BLIT with IFE: odd-even, so the centre stays hollow
// The texture modes read their motion from play.zig (the keys); a texture of
// side 2^log is walked at 2^(log-7) the steps of the 128 one, so every size shows
// the same picture (only the detail changes).
// Integer only per frame: zg.fixtrig angles, Q16.16 steps.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const v2 = zg.chisel_v2;
const assets = @import("assets.zig");
const play = @import("play.zig");
const LogicalFB = zg.LogicalFB;

pub const W: i32 = 320;
pub const H: i32 = 200;
const HORIZON: i32 = 48;
pub const STAR_COL: u8 = 50;

/// The texture a mode reads and its side, 2^log.
pub const Tex = struct { t: v2.Texture, log: u4 };

pub const Modes = struct {
    spans: []v2.Span = &.{},
    recip: [200]i32 = undefined, // MODE 7: 65536 * height / (y - HORIZON)
    recip_h: i32 = 0, // the height `recip` was built for
    t: u32 = 0,

    pub fn init(m: *Modes) bool {
        m.spans = zg.mem.alloc(v2.Span, @intCast(H)) orelse return false;
        m.height(play.HEIGHT0);
        return true;
    }

    /// The per-row reciprocal for a camera height (only when the height changes: 151 divides).
    fn height(m: *Modes, h: i32) void {
        m.recip_h = h;
        for (&m.recip, 0..) |*r, y| {
            const d: i32 = @as(i32, @intCast(y)) - HORIZON;
            r.* = if (d > 0) @divTrunc(h << 16, d) else 0;
        }
    }

    pub fn rotozoom(m: *Modes, fb: *LogicalFB, tx: Tex, r: *const play.Roto) void {
        const zoom0: i64 = trig.ONE + @divTrunc(trig.sin(m.t *% (3 << 23)), 2); // 0.5 .. 1.5
        const zoom = @divTrunc(zoom0 * play.ZOOMS[r.zoom], 256);
        const du = side(@divTrunc(@as(i64, trig.cos(r.angle)) * zoom, trig.ONE), tx.log);
        const dv = side(@divTrunc(@as(i64, trig.sin(r.angle)) * zoom, trig.ONE), tx.log);
        const cu = side((64 << 16) + r.pan_u, tx.log);
        const cv = side((64 << 16) + r.pan_v, tx.log);
        for (m.spans, 0..) |*s, y| {
            const yy: i64 = @as(i64, @intCast(y)) - 100;
            const su = cu - 160 * du - yy * dv;
            const sv = cv - 160 * dv + yy * du;
            s.* = .{ .x0 = 0, .x1 = W, .y = @intCast(y), .u0 = wrap(su), .v0 = wrap(sv), .du = wrap(du), .dv = wrap(dv) };
        }
        v2.affine(fb, tx.t, m.spans, .{});
    }

    pub fn mode7(m: *Modes, fb: *LogicalFB, tx: Tex, f: *const play.Floor) void {
        if (f.height != m.recip_h) m.height(f.height);
        const c: i64 = trig.cos(f.heading);
        const sn: i64 = trig.sin(f.heading);
        var n: usize = 0;
        var y: i32 = HORIZON + 1;
        while (y < H) : (y += 1) {
            const scale: i64 = m.recip[@intCast(y)]; // texels a pixel, Q16
            const dist = scale * 80; // the row's distance in front of the camera, Q16
            const du = side(@divTrunc(c * scale, trig.ONE), tx.log);
            const dv = side(@divTrunc(-sn * scale, trig.ONE), tx.log);
            const cu = side(f.pos_u + @divTrunc(sn * dist, trig.ONE), tx.log);
            const cv = side(f.pos_v + @divTrunc(c * dist, trig.ONE), tx.log);
            m.spans[n] = .{ .x0 = 0, .x1 = W, .y = @intCast(y), .u0 = wrap(cu - 160 * du), .v0 = wrap(cv - 160 * dv), .du = wrap(du), .dv = wrap(dv) };
            n += 1;
        }
        fb.fillRect(0, 0, @intCast(W), @intCast(HORIZON + 1), 2); // the sky: a FILL
        v2.affine(fb, tx.t, m.spans[0..n], .{});
    }

    /// The plane is a window into the bigger map: its corner moves on a sine path when bent.
    pub fn tunnel(m: *Modes, fb: *LogicalFB, tx: Tex, a: *const assets.Assets, tb: *const play.Tube) void {
        const k: i32 = tb.bend; // 0 (straight, centred) .. 3
        const dx: i32 = @divTrunc(trig.sin(m.t *% (1 << 24)) * assets.BEND_X * k, 3 * trig.ONE);
        const dy: i32 = @divTrunc(trig.sin(m.t *% (3 << 22) +% (1 << 30)) * assets.BEND_Y * k, 3 * trig.ONE);
        const at: usize = @intCast((assets.BEND_Y + dy) * assets.MAP_W + assets.BEND_X + dx);
        v2.map(fb, tx.t, 0, 0, @intCast(W), @intCast(H), a.map[at..], assets.MAP_W, tb.u, tb.v, .{});
    }

    /// The four orientations of the arrow, drifting into each other; true when any collided.
    pub fn sprites(m: *Modes, fb: *LogicalFB, a: *const assets.Assets) bool {
        fb.fillRect(0, 0, @intCast(W), @intCast(H), 0);
        v2.clearCollision();
        const r: i32 = 20 + @divTrunc(trig.sin(m.t *% (1 << 26)) * 30, trig.ONE); // -10 .. 50 a 64-frame cycle: they meet
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

/// A step or position for the 128 texture, scaled to a side-2^log one (arithmetic shifts).
inline fn side(v: i64, log: u4) i64 {
    return if (log >= 7) v << @intCast(log - 7) else v >> @intCast(7 - log);
}

inline fn wrap(v: i64) u32 {
    return @truncate(@as(u64, @bitCast(v)));
}
