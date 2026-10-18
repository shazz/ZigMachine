// --------------------------------------------------------------------------
// Union intro — the WAB part's turned-tile blit (wab.zig), in Q32 fixed point.
//
// The tile's texture coordinates (u,v) are linear in the plane pixel, so they
// step by a constant per pixel and per row: two i64 adds a pixel on the board's
// rv32 instead of six soft-float f64 operations and two floors (the f64 version
// cost tens of Mc a frame on KESTREL, which has no f64 unit).
//
// Pixel-exact with the f64 version it replaces: every decision the blit makes
// (inside the tile, which texel) changes only where u or v crosses an INTEGER,
// and the stepped values are within ~1e-8 of the true ones. So where u and v are
// both at least EPS from an integer the integer answer is the f64 answer; on the
// rare pixel closer than that, the f64 expression is evaluated exactly as before.
// Per tile the setup (cos/sin, the span) stays f64, as in the remake.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

pub const TILE: f64 = 33;
pub const HALF_TILE: f64 = TILE / 2;
pub const LOGO: usize = 132; // wab.raw is 132x132
const LOGO_F: f64 = LOGO;
const TILE_I: i64 = 33;
const ONE: f64 = 4294967296.0; // Q32
const EPS: u32 = 1 << 12; // ~1e-6: far above the stepping error, rare enough to cost nothing

pub const Tile = struct {
    tx: f64, // the tile's column and row in the logo grid
    ty: f64,
    cx: f64, // its centre on the canvas
    cy: f64,
    cs: f64, // its turn
    sn: f64,
};

pub const Span = struct { x0: i32, x1: i32, y0: i32, y1: i32, ox: f64, oy: f64 };

/// The f64 blit's arithmetic for one pixel, unchanged: the reference the fast path
/// falls back on near an integer. Returns the texel index into wab.raw, or null.
fn texelF64(t: Tile, sp: Span, px: i32, py: i32) ?usize {
    const qy = 2 * (@as(f64, @floatFromInt(py)) - sp.oy) + 1 - t.cy;
    const qx = 2 * (@as(f64, @floatFromInt(px)) - sp.ox) + 1 - t.cx;
    const u = t.cs * qx + t.sn * qy + HALF_TILE;
    const v = -t.sn * qx + t.cs * qy + HALF_TILE;
    if (u <= -1 or u >= TILE + 1 or v <= -1 or v >= TILE + 1) return null;
    const sx = @floor((t.tx * TILE + u) / 2);
    const sy = @floor((t.ty * TILE + v) / 2);
    if (sx < 0 or sx >= LOGO_F or sy < 0 or sy >= LOGO_F) return null;
    return @as(usize, @intFromFloat(sy)) * LOGO + @as(usize, @intFromFloat(sx));
}

/// The texel for a fixed-point (u,v) at least EPS from any integer, as texelF64
/// would find it: u <= -1 is floor(u) <= -2, floor((33tx+u)/2) is (33tx+floor(u))>>1.
inline fn texelFixed(tx: i64, ty: i64, u: i64, v: i64) ?usize {
    const ui = u >> 32;
    const vi = v >> 32;
    if (ui < -1 or ui > TILE_I or vi < -1 or vi > TILE_I) return null;
    const sx = (tx * TILE_I + ui) >> 1;
    const sy = (ty * TILE_I + vi) >> 1;
    if (sx < 0 or sx >= LOGO or sy < 0 or sy >= LOGO) return null;
    return @as(usize, @intCast(sy)) * LOGO + @as(usize, @intCast(sx));
}

inline fn nearInt(q: i64) bool {
    const frac: u32 = @truncate(@as(u64, @bitCast(q)));
    return frac +% EPS < 2 * EPS;
}

fn q32(x: f64) i64 {
    return @intFromFloat(@round(x * ONE));
}

/// Draw tile `t` over `sp` into `fb`: texels of wab_raw, 0 transparent, through `shade`.
pub fn blitTurned(fb: *LogicalFB, t: Tile, sp: Span, wab_raw: []const u8, shade: ?*const [256]u8) void {
    if (sp.x0 >= sp.x1 or sp.y0 >= sp.y1) return;
    // (u,v) at the span's first pixel, and its steps: qx and qy grow by 2 a pixel.
    const qx0 = 2 * (@as(f64, @floatFromInt(sp.x0)) - sp.ox) + 1 - t.cx;
    const qy0 = 2 * (@as(f64, @floatFromInt(sp.y0)) - sp.oy) + 1 - t.cy;
    var u_row = q32(t.cs * qx0 + t.sn * qy0 + HALF_TILE);
    var v_row = q32(-t.sn * qx0 + t.cs * qy0 + HALF_TILE);
    const du_x = q32(2 * t.cs);
    const dv_x = q32(-2 * t.sn);
    const du_y = q32(2 * t.sn);
    const dv_y = q32(2 * t.cs);
    const tx: i64 = @intFromFloat(t.tx);
    const ty: i64 = @intFromFloat(t.ty);
    var py = sp.y0;
    while (py < sp.y1) : (py += 1) {
        const row = @as(usize, @intCast(py)) * @as(usize, fb.stride);
        var u = u_row;
        var v = v_row;
        var px = sp.x0;
        while (px < sp.x1) : (px += 1) {
            const texel = if (nearInt(u) or nearInt(v)) texelF64(t, sp, px, py) else texelFixed(tx, ty, u, v);
            u += du_x;
            v += dv_x;
            const at = texel orelse continue;
            const idx = wab_raw[at];
            if (idx == 0) continue;
            fb.fb[row + @as(usize, @intCast(px))] = if (shade) |s| s[idx] else idx;
        }
        u_row += du_y;
        v_row += dv_y;
    }
}
