// --------------------------------------------------------------------------
// OBJ demo: Gouraud on the CPU. The rows are the flat rule's (raster.walkRows,
// the same pixels CHISEL's TRIANGLE covers); across them the light level is
// the plane through the three vertex levels, as two Q12 gradients found once
// a triangle (one divide each), so a pixel costs an add, a clamp and a byte.
// Pixels are packed four to a u32 store where the row allows (board stores
// cost the same for a byte and a word).
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const raster = @import("raster.zig");
const Target = raster.Target;
const P = raster.P;

pub const FRAC = 12; // vertex levels are Q12

const Ctx = struct {
    t: Target,
    gx: i32,
    gy: i32,
    x0: i32,
    y0: i32,
    l0: i32,
    base: u8,
    top: i32, // highest level, in whole steps
};

inline fn pix(c: *const Ctx, lv: i32) u8 {
    return c.base + @as(u8, @intCast(@min(@max(lv >> FRAC, 0), c.top)));
}

fn span(c: Ctx, y: i32, xl: i32, xr: i32) void {
    const l = @max(xl, 0);
    const r = @min(xr, c.t.w - 1);
    if (r < l) return;
    const row = c.t.px + @as(usize, @intCast(y)) * c.t.stride;
    var lv = c.l0 + c.gx * (l - c.x0) + c.gy * (y - c.y0);
    var x: usize = @intCast(l);
    const end: usize = @intCast(r + 1);
    const aligned = @intFromPtr(row) & 3 == 0;
    while (x < end and (x & 3 != 0 or !aligned)) : (x += 1) {
        row[x] = pix(&c, lv);
        lv += c.gx;
    }
    while (x + 4 <= end) : (x += 4) {
        var w: u32 = 0;
        inline for (0..4) |k| {
            w |= @as(u32, pix(&c, lv)) << (8 * k);
            lv += c.gx;
        }
        @as(*u32, @ptrCast(@alignCast(row + x))).* = w;
    }
    while (x < end) : (x += 1) {
        row[x] = pix(&c, lv);
        lv += c.gx;
    }
}

/// `lev` are the vertices' light levels in Q12; a pixel is base + level,
/// clamped to 0..top.
pub fn triangle(t: Target, v: [3]P, lev: [3]i32, base: u8, top: i32) void {
    const x1: i32 = @as(i32, v[1][0]) - v[0][0];
    const y1: i32 = @as(i32, v[1][1]) - v[0][1];
    const x2: i32 = @as(i32, v[2][0]) - v[0][0];
    const y2: i32 = @as(i32, v[2][1]) - v[0][1];
    const area = x1 * y2 - x2 * y1;
    if (area == 0) { // a sliver: CHISEL still fills its rows, so do the same in one level
        raster.flat(t, v, base + @as(u8, @intCast(@min(@max(lev[0] >> FRAC, 0), top))));
        return;
    }
    const d1 = lev[1] - lev[0];
    const d2 = lev[2] - lev[0];
    const c = Ctx{
        .t = t,
        .gx = @divTrunc(d1 * y2 - d2 * y1, area),
        .gy = @divTrunc(d2 * x1 - d1 * x2, area),
        .x0 = v[0][0],
        .y0 = v[0][1],
        .l0 = lev[0],
        .base = base,
        .top = top,
    };
    raster.walkRows(t, v, c, span);
}
