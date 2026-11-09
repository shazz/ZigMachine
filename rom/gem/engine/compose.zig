// --------------------------------------------------------------------------
// GEM 5 engine: painting the damage. Each layer, bottom to top, is drawn only
// inside (damage ∩ its bounds) minus what the layers above it cover — the AES's
// rectangle list walk (wind_get WF_FIRSTXYWH / WF_NEXTXYWH), done for every layer
// at once. The cut is an optimisation EXCEPT for an external layer (painted
// before composing), which must never be painted over. A list that cannot take
// an ordinary cut (rect.zig's fixed capacity) paints in the painter's order
// inside the damage, which is still exact; damage that overflowed, or that
// could not take the external cuts, is replaced by its bounding box for EVERY
// layer, which is also exact (more area, same order).
// --------------------------------------------------------------------------
const std = @import("std");
const rect = @import("rect.zig");
const draw = @import("draw.zig");
const scene_mod = @import("scene.zig");
const Canvas = @import("canvas.zig").Canvas;
const Look = @import("look.zig").Look;
const Rect = rect.Rect;
const RectList = rect.RectList;
const Scene = scene_mod.Scene;

pub const Stats = struct {
    rects: u32 = 0, // clip rectangles drawn (every layer's)
    area: u32 = 0, // the damage's area
};

pub fn compose(cv: *Canvas, look: *const Look, s: *const Scene, damage_in: *const RectList, stats: *Stats) void {
    var damage = damage_in.*;
    if (damage.overflow or !externalsFit(s, damage)) collapse(&damage);
    stats.area += damage.area();
    const saved = cv.clip;
    defer cv.clip = saved;
    for (s.layers[0..s.n], 0..) |*l, i| {
        if (l.external or l.tree.len == 0) continue;
        var vis = damage;
        vis.clipTo(l.bounds);
        if (!cutAbove(s, i, &vis)) continue;
        for (vis.slice()) |r| {
            cv.setClip(r);
            draw.draw(cv, look, l.tree, 0, draw.MAX_DEPTH);
            stats.rects += 1;
        }
    }
}

/// Take the covers of the layers above `i` out of `vis`: the external ones first
/// (they MUST go: false when one does not fit, and the layer is then not painted),
/// then the others, each skipped when it does not fit (painting it is only slower).
fn cutAbove(s: *const Scene, i: usize, vis: *RectList) bool {
    for (s.layers[i + 1 .. s.n]) |*u| {
        if (!u.external) continue;
        for (u.cover[0..u.n_cover]) |c| if (!vis.subtract(c)) return false;
    }
    for (s.layers[i + 1 .. s.n]) |*u| {
        if (u.external) continue;
        for (u.cover[0..u.n_cover]) |c| _ = vis.subtract(c);
    }
    return true;
}

/// Whether the whole damage can take every external cut (else it is collapsed to its
/// bounding box first, where the few external cuts always fit). Exact either way: a
/// larger damage is the same for every layer, so the painter's order still holds.
fn externalsFit(s: *const Scene, damage: RectList) bool {
    var d = damage;
    for (s.layers[0..s.n]) |*u| {
        if (!u.external) continue;
        for (u.cover[0..u.n_cover]) |c| if (!d.subtract(c)) return false;
    }
    return true;
}

fn collapse(l: *RectList) void {
    const b = l.bounds();
    l.* = .{};
    l.add(b);
}
