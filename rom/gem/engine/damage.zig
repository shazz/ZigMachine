// --------------------------------------------------------------------------
// GEM 5 engine: the damage pass. A SNAPSHOT is what one buffer holds — the
// layers, their bounds, what lies above each, and every object's extent and
// hash as last drawn into it. Comparing this frame's scene with the snapshot of
// the buffer about to be drawn gives the rectangles to repaint:
//   - a layer that appeared or went away: its bounds;
//   - a layer whose bounds moved: old and new bounds;
//   - two layers that kept their bounds but swapped order (a window topped):
//     where they overlap;
//   - otherwise each object whose extent or hash changed: its old and new extent
//     (a layer whose object count changed: old and new bounds).
// Per BUFFER, not per frame: with two buffers the one drawn next holds the
// frame before last, so it is compared with what IT holds (deskflip.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const rect = @import("rect.zig");
const scene_mod = @import("scene.zig");
const Rect = rect.Rect;
const RectList = rect.RectList;
const Scene = scene_mod.Scene;

const LayerSnap = struct { key: u16, bounds: Rect, first: u16, n: u16, external: bool };

pub const Snap = struct {
    valid: bool = false, // false: the buffer holds something else (a whole repaint follows)
    layers: [scene_mod.MAX_LAYERS]LayerSnap = undefined,
    n: usize = 0,
    ext: [scene_mod.MAX_OBJS]Rect = undefined,
    hash: [scene_mod.MAX_OBJS]u32 = undefined,

    pub fn invalidate(self: *Snap) void {
        self.valid = false;
    }

    /// Remember `s` as what this buffer now holds.
    pub fn record(self: *Snap, s: *const Scene) void {
        self.valid = !s.overflow;
        self.n = s.n;
        for (s.layers[0..s.n], 0..) |*l, i| {
            self.layers[i] = .{ .key = l.key, .bounds = l.bounds, .first = l.first, .n = @intCast(l.tree.len), .external = l.external };
        }
        @memcpy(self.ext[0..s.n_obj], s.ext[0..s.n_obj]);
        @memcpy(self.hash[0..s.n_obj], s.hash[0..s.n_obj]);
    }

    fn find(self: *const Snap, key: u16) ?usize {
        for (self.layers[0..self.n], 0..) |l, i| if (l.key == key) return i;
        return null;
    }
};

/// The rectangles of `screen` that must be repainted to turn `snap`'s buffer into `s`.
pub fn diff(s: *const Scene, snap: *const Snap, screen: Rect, out: *RectList) void {
    if (!snap.valid or s.overflow) return out.add(screen);
    for (s.layers[0..s.n], 0..) |*l, i| {
        const old_i = snap.find(l.key) orelse {
            out.add(l.bounds);
            continue;
        };
        const old = snap.layers[old_i];
        if (!old.bounds.eql(l.bounds) or old.n != l.tree.len or old.external != l.external) {
            out.add(old.bounds);
            out.add(l.bounds);
            continue;
        }
        if (l.external) { // painted by the old code every drawn frame: always fresh
            out.add(l.bounds);
            continue;
        }
        const now = s.objs(i);
        for (0..l.tree.len) |k| {
            const oe = snap.ext[old.first + k];
            if (oe.eql(now.ext[k]) and snap.hash[old.first + k] == now.hash[k]) continue;
            out.add(oe);
            out.add(now.ext[k]);
        }
    }
    for (snap.layers[0..snap.n]) |old| {
        var gone = true;
        for (s.layers[0..s.n]) |*l| gone = gone and l.key != old.key;
        if (gone) out.add(old.bounds);
    }
    reordered(s, snap, out);
    out.clipTo(screen);
}

/// Two layers in both frames whose order flipped: where they overlap (now and then)
/// shows the other one on top. A layer that came, went or moved is damaged whole
/// already, which covers its overlaps.
fn reordered(s: *const Scene, snap: *const Snap, out: *RectList) void {
    for (s.layers[0..s.n], 0..) |*lo, i| {
        const oi = snap.find(lo.key) orelse continue;
        for (s.layers[i + 1 .. s.n]) |*hi| {
            const oj = snap.find(hi.key) orelse continue;
            if (oi < oj) continue; // still below it
            out.add(rect.intersect(lo.bounds, hi.bounds));
            out.add(rect.intersect(snap.layers[oi].bounds, snap.layers[oj].bounds));
        }
    }
}
