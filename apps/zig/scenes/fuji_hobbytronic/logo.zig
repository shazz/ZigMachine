// --------------------------------------------------------------------------
// FUJI HOBBYTRONIC: the solid Fuji, transformed in fixed point and filled by
// the HARDWARE BLITTER, one TRIANGLE op per face.
//
// Per frame: rotate the vertices (Q14), project them (one divide each), rotate
// each triangle's normal, drop the ones turned away from the eye, sort the rest
// far to near on their summed depth, then hand each to the blitter. The sort is
// PER TRIANGLE (painter's algorithm): the traced fingers are concave and curved,
// so a whole cap or side strip has no single depth, but its small triangles do. Colour: the front cap is raster.FRONT and the back
// cap raster.BACK, both one index whose colour the HBL changes per line; the
// sides take a flat Lambert shade from the SIDE ramp.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const mesh = @import("mesh.zig");
const fx = @import("fixed.zig");
const raster = @import("raster.zig");

pub const SIDE: u8 = 6; // SIDE .. SIDE + SIDE_LEVELS - 1: the side faces' shades
pub const SIDE_LEVELS = 8;

const Visible = struct { key: i32, face: u16, ink: u8 };

var screen: [mesh.NV][2]i16 = undefined;
var rotated: [mesh.NV][3]i32 = undefined;
var visible: [mesh.NF]Visible = undefined;

/// The side ramp: a cool steel grey, ST-legal (nibble x 32).
pub fn sidePalette(fb: *zg.LogicalFB) void {
    for (0..SIDE_LEVELS) |k| {
        const n: u32 = @intCast(k);
        fb.palette[SIDE + k] = raster.st(n, n, @min(7, n + 1));
    }
}

/// Draw the Fuji turned by `yaw` then `pitch` (angle units), centred at (cx, cy).
/// Returns the number of triangles drawn.
pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, yaw: i32, pitch: i32, cx: i32, cy: i32) usize {
    const r = fx.Rot.init(yaw, pitch);
    for (mesh.MODEL.verts, 0..) |v, i| {
        rotated[i] = r.apply(.{ v[0], v[1], v[2] });
        screen[i] = fx.project(rotated[i], cx, cy);
    }
    const n = collect(r);
    sortFarToNear(visible[0..n]);
    for (visible[0..n]) |vf| {
        const t = mesh.MODEL.faces[vf.face].v;
        bl.triangle(fb, at(t[0]), at(t[1]), at(t[2]), vf.ink);
    }
    return n;
}

fn at(i: u8) zg.BlitVec2 {
    return .{ .x = screen[i][0], .y = screen[i][1] };
}

/// The faces the eye can see, each with its depth key and its ink.
fn collect(r: fx.Rot) usize {
    var n: usize = 0;
    for (mesh.MODEL.faces, 0..) |f, i| {
        var sum = [3]i32{ 0, 0, 0 };
        for (f.v) |vi| {
            for (0..3) |k| sum[k] += rotated[vi][k];
        }
        const nr = r.apply(.{ f.n[0], f.n[1], f.n[2] });
        if (!fx.facing(nr, sum)) continue;
        const ink: u8 = switch (f.kind) {
            .front => raster.FRONT,
            .back => raster.BACK,
            .side => SIDE + @as(u8, @intCast(fx.shade(nr, SIDE_LEVELS))),
        };
        visible[n] = .{ .key = sum[2], .face = @intCast(i), .ink = ink };
        n += 1;
    }
    return n;
}

/// Insertion sort, deepest first: about 120 triangles a frame.
fn sortFarToNear(list: []Visible) void {
    var i: usize = 1;
    while (i < list.len) : (i += 1) {
        const x = list[i];
        var j = i;
        while (j > 0 and list[j - 1].key < x.key) : (j -= 1) list[j] = list[j - 1];
        list[j] = x;
    }
}
