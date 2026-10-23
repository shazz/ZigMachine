// --------------------------------------------------------------------------
// Union intro — the WAB part's turned-tile blit (wab.zig), integers only.
//
// The tile's texture coordinates (u,v) are linear in the plane pixel: Q24, two
// i32 adds a pixel, from a wab_table.zig entry (its corner value and steps were
// worked out at compile time in f64). The f64 blit this replaces fell back on f64
// within 2^-18 of an integer; wab_table_test.zig proves that over every entry of
// the table and every pixel of its span the integer texel is the f64 one, so
// there is no fallback left and no float in the frame.
//
// A pixel draws when floor(u) and floor(v) each fall in an interval (the tile,
// cut to the logo: Box). u and v are linear in the column, so on a row the
// pixels that draw are ONE run, and the run's first column moves little from row
// to row. blit() therefore walks to each row's first column from the row above's
// (exactly: every step is the texel test, nothing is solved or rounded) and then
// draws the run with two unsigned compares a pixel, instead of testing all of the
// entry's span (~2.3 tests a drawn pixel, 35 cycles each, was 0.75 Mc a frame).
// --------------------------------------------------------------------------
const Entry = @import("wab_table.zig").Entry;

pub const LOGO: usize = 132; // wab.raw is 132x132
const TILE_I: i32 = 33;
const FRAC = 24;

/// The texel for a Q24 (u,v), or null outside the tile (u <= -1 or u >= 34 is
/// floor(u) <= -2 or >= 34) or the logo. floor((33tx+u)/2) is (33tx+floor(u))>>1.
/// blit() runs the same test as two intervals (Axis); wab_table_test.zig's
/// reference blit runs this one, and proves the two draw the same pixels.
pub inline fn texel(tx: i32, ty: i32, u: i32, v: i32) ?usize {
    const ui = u >> FRAC;
    const vi = v >> FRAC;
    if (ui < -1 or ui > TILE_I or vi < -1 or vi > TILE_I) return null;
    const sx = (tx * TILE_I + ui) >> 1;
    const sy = (ty * TILE_I + vi) >> 1;
    if (sx < 0 or sx >= LOGO or sy < 0 or sy >= LOGO) return null;
    return @as(usize, @intCast(sy)) * LOGO + @as(usize, @intCast(sx));
}

/// texel()'s test as Q24 intervals: floor(u) in [-1, 33] and 0 <= 33tx+floor(u)
/// <= 263 (sx in the logo) is u in [lo, lo + span). Same for v with ty.
const Axis = struct {
    lo: i32,
    span: u32,

    fn of(t: i32) Axis {
        const lo = @max(-1, -TILE_I * t);
        const hi = @min(TILE_I, 2 * @as(i32, LOGO) - 1 - TILE_I * t);
        return .{ .lo = lo << FRAC, .span = @as(u32, @intCast(hi + 1 - lo)) << FRAC };
    }

    inline fn in(a: Axis, q: i32) bool {
        return @as(u32, @bitCast(q -% a.lo)) < a.span;
    }

    /// Which way along the row q moves into the interval: 0 inside, +-1, or
    /// null when it never does (q is outside and does not move).
    inline fn toward(a: Axis, q: i32, d: i32) ?i32 {
        if (a.in(q)) return 0;
        if (d == 0) return null;
        const up: i32 = if (d > 0) 1 else -1;
        return if (q < a.lo) up else -up;
    }
};

/// The row's first drawing column from `hint`, or null when no column of
/// [0, w) draws. Exact: each step tests the pixel it lands on.
fn first(ax: Axis, ay: Axis, u_row: i32, v_row: i32, du: i32, dv: i32, w: i32, hint: i32) ?i32 {
    var x = @min(@max(hint, 0), w - 1);
    var u = u_row +% x *% du;
    var v = v_row +% x *% dv;
    var was: i32 = 0; // the last step's direction
    while (true) {
        const su = ax.toward(u, du) orelse return null;
        const sv = ay.toward(v, dv) orelse return null;
        if (su == 0 and sv == 0) break;
        if (su != 0 and sv != 0 and su != sv) return null; // the two pull apart
        const s = if (su != 0) su else sv;
        // u and v are monotone along the row, so a non-empty run lies all one
        // way: turning back means the u run and the v run do not meet
        if (s == -was) return null;
        was = s;
        x += s;
        if (x < 0 or x >= w) return null;
        u +%= s * du;
        v +%= s * dv;
    }
    while (x > 0 and ax.in(u -% du) and ay.in(v -% dv)) { // the run may reach further left
        x -= 1;
        u -%= du;
        v -%= dv;
    }
    return x;
}

/// Draw entry `e` into `fb` (a plane, `stride` bytes a row): texels of `raw`, 0
/// transparent, through `shade` (null at full alpha).
pub fn blit(fb: [*]u8, stride: usize, e: Entry, raw: []const u8, shade: ?*const [256]u8) void {
    const tx: i32 = e.tile % 8;
    const ty: i32 = e.tile / 8;
    const ax = Axis.of(tx);
    const ay = Axis.of(ty);
    const bx = tx * TILE_I; // texel column = (bx + floor(u)) >> 1
    const by = ty * TILE_I;
    const map = shade orelse &IDENTITY;
    const w: i32 = e.w;
    var u_row = e.u0;
    var v_row = e.v0;
    var row: [*]u8 = fb + @as(usize, @intCast(e.y0)) * stride + @as(usize, @intCast(e.x0));
    var hint: i32 = 0;
    for (0..e.h) |_| {
        if (first(ax, ay, u_row, v_row, e.du, e.dv, w, hint)) |x0| {
            hint = x0;
            var u = u_row +% x0 *% e.du;
            var v = v_row +% x0 *% e.dv;
            var x = x0;
            while (x < w and ax.in(u) and ay.in(v)) : (x += 1) {
                const sx: usize = @intCast((bx + (u >> FRAC)) >> 1);
                const sy: usize = @intCast((by + (v >> FRAC)) >> 1);
                const idx = raw[sy * LOGO + sx];
                if (idx != 0) row[@intCast(x)] = map[idx];
                u +%= e.du;
                v +%= e.dv;
            }
        }
        u_row -%= e.dv; // du_y = q24(2 sin) = -dv
        v_row +%= e.du; // dv_y = q24(2 cos) = du
        row += stride;
    }
}

const IDENTITY: [256]u8 = blk: {
    var t: [256]u8 = undefined;
    for (&t, 0..) |*p, i| p.* = i;
    break :blk t;
};
