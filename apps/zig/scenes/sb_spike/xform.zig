// --------------------------------------------------------------------------
// SB SPIKE: vertices to the screen, integers only (one divide a vertex).
//
// The PSP's projection (TimelinePlayer.cpp: fovy 45, 16:9, near 1) on a 320x180
// view letterboxed in 320x200: screen = centre + p * F / depth with
// F = 90 / tan(22.5 deg) = 217.3 px, depth = -z_view. Screen x, y are Q4 (1/16 px:
// subpixel edges, so slow camera moves do not crawl). A vertex nearer than the
// near plane is flagged (depth 0) and its triangles are skipped (no clipping in the
// spike; counted). Env items take their texel from the view-space normal, the
// PSP's GU_ENVIRONMENT_MAP with Shiny.cpp's matrix: u = (1 + n.x) / 2,
// v = (1 - n.y) / 2 of the env map.
// No ZigOS import.
// --------------------------------------------------------------------------
const anim = @import("anim.zig");
const data = @import("data.zig");

pub const CX16: i32 = 160 * 16;
pub const CY16: i32 = 100 * 16;
const NEAR: i32 = 4096; // 1.0 Q12
const F16: i32 = 3476; // F in Q4: 217.27 * 16
/// Screen coordinates are kept inside +-2^15 Q4 (2048 px) so edge maths stays in i32.
const LIM: i32 = 32767;

/// A transformed vertex, 8 bytes so the frame's set stays dense in the 4 KB D$:
/// screen x, y Q4, texel u 8.8 and atlas row v 11.5 (data.Vert's own units).
pub const PV = extern struct { x: i16 align(4), y: i16, u: u16, v: u16 }; // word-aligned: copied as words

/// out[i], depth[i] for vs[i]: depth in 1/256 units (Q8), 0 = nearer than the near plane.
pub fn item(out: []PV, depth_out: []u16, vs: []const data.Vert, mv: *const anim.ModelView, it: data.layout.Item) void {
    const r = mv.r; // by value: the stores below cannot alias it, so it stays in registers
    const t = mv.t;
    for (vs, out[0..vs.len], depth_out[0..vs.len]) |s, *o, *dz| {
        const x: i32 = ((s.x * r[0][0] + s.y * r[1][0] + s.z * r[2][0]) >> 14) + t[0];
        const y: i32 = ((s.x * r[0][1] + s.y * r[1][1] + s.z * r[2][1]) >> 14) + t[1];
        const depth: i32 = -(((s.x * r[0][2] + s.y * r[1][2] + s.z * r[2][2]) >> 14) + t[2]);
        if (depth < NEAR) {
            dz.* = 0;
            continue;
        }
        const k: i32 = @divTrunc(F16 << 14, depth); // <= 13904
        o.* = .{ .x = clamp(CX16 + ((x * k) >> 14)), .y = clamp(CY16 - ((y * k) >> 14)), .u = s.u, .v = s.v };
        dz.* = @intCast(@min(depth >> 4, 0xFFFF));
    }
    if (it.env) envUV(out[0..vs.len], vs, &mv.r, it);
}

fn clamp(v: i32) i16 {
    return @intCast(@max(-LIM, @min(LIM, v)));
}

/// The env map's texel from the view-space normal (rotation only), the slot's
/// size x size texels at row0 of the atlas.
fn envUV(out: []PV, vs: []const data.Vert, r: *const anim.Mat, it: data.layout.Item) void {
    // texels in 16.16 as in the derivation, stored back as u 8.8 and v 11.5
    const half: i32 = @as(i32, it.size) << 15; // size / 2 texels, 16.16
    const top: u32 = @as(u32, it.row0) << 5;
    const lim: i32 = (@as(i32, it.size) << 16) - 1;
    const sh: u5 = @intCast(14 - @ctz(@as(u32, it.size)) + 1); // n Q14 -> size/2 texels 16.16
    for (vs, out) |s, *o| {
        const nx: i32 = (s.nx * r[0][0] + s.ny * r[1][0] + s.nz * r[2][0]) >> 14;
        const ny: i32 = (s.nx * r[0][1] + s.ny * r[1][1] + s.nz * r[2][1]) >> 14;
        o.u = @intCast(std.math.clamp(half + ((nx << 16) >> sh), 0, lim) >> 8);
        o.v = @intCast(top + @as(u32, @intCast(std.math.clamp(half - ((ny << 16) >> sh), 0, lim) >> 11)));
    }
}

const std = @import("std");
