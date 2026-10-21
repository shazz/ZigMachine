// --------------------------------------------------------------------------
// Union intro — the WAB part's turned-tile blit (wab.zig), integers only.
//
// The tile's texture coordinates (u,v) are linear in the plane pixel: Q24, two
// i32 adds a pixel, from a wab_table.zig entry (its corner value and steps were
// worked out at compile time in f64). The f64 blit this replaces fell back on f64
// within 2^-18 of an integer; wab_table_test.zig proves that over every entry of
// the table and every pixel of its span the integer texel is the f64 one, so
// there is no fallback left and no float in the frame.
// --------------------------------------------------------------------------
const Entry = @import("wab_table.zig").Entry;

pub const LOGO: usize = 132; // wab.raw is 132x132
const TILE_I: i32 = 33;
const FRAC = 24;

/// The texel for a Q24 (u,v), or null outside the tile (u <= -1 or u >= 34 is
/// floor(u) <= -2 or >= 34) or the logo. floor((33tx+u)/2) is (33tx+floor(u))>>1.
pub inline fn texel(tx: i32, ty: i32, u: i32, v: i32) ?usize {
    const ui = u >> FRAC;
    const vi = v >> FRAC;
    if (ui < -1 or ui > TILE_I or vi < -1 or vi > TILE_I) return null;
    const sx = (tx * TILE_I + ui) >> 1;
    const sy = (ty * TILE_I + vi) >> 1;
    if (sx < 0 or sx >= LOGO or sy < 0 or sy >= LOGO) return null;
    return @as(usize, @intCast(sy)) * LOGO + @as(usize, @intCast(sx));
}

/// Draw entry `e` into `fb` (a plane, `stride` bytes a row): texels of `raw`, 0
/// transparent, through `shade` (null at full alpha).
pub fn blit(fb: [*]u8, stride: usize, e: Entry, raw: []const u8, shade: ?*const [256]u8) void {
    const tx: i32 = e.tile % 8;
    const ty: i32 = e.tile / 8;
    var u_row = e.u0;
    var v_row = e.v0;
    const x0: usize = @intCast(e.x0);
    var row = @as(usize, @intCast(e.y0)) * stride + x0;
    for (0..e.h) |_| {
        var u = u_row;
        var v = v_row;
        var inside = false; // the tile is convex: once a row has left it, the rest of the row is outside
        for (0..e.w) |dx| {
            const t = texel(tx, ty, u, v);
            u += e.du;
            v += e.dv;
            const at = t orelse {
                if (inside) break;
                continue;
            };
            inside = true;
            const idx = raw[at];
            if (idx == 0) continue;
            fb[row + dx] = if (shade) |s| s[idx] else idx;
        }
        u_row -= e.dv; // du_y = q24(2 sin) = -dv
        v_row += e.du; // dv_y = q24(2 cos) = du
        row += stride;
    }
}
