// --------------------------------------------------------------------------
// GEM 5 engine: objc_draw, our way. Draws `start` and up to `depth` levels of its
// children, parents before children and siblings in chain order (so later ones
// are on top), skipping HIDETREE subtrees, everything clipped to the canvas's
// clip. The compositor (compose.zig) calls it once per exposed rectangle.
//
// extent() is how far an object's paint can reach beyond its box (outlines,
// shadows, the TOS 4 3D outset, a string longer than its box): the damage pass
// (damage.zig) uses it, so it must cover everything paint() writes.
// --------------------------------------------------------------------------
const std = @import("std");
const rect = @import("rect.zig");
const obj = @import("obj.zig");
const look_mod = @import("look.zig");
const paint_mod = @import("paint.zig");
const Canvas = @import("canvas.zig").Canvas;
const Rect = rect.Rect;
const Object = obj.Object;
const Look = look_mod.Look;

pub const MAX_DEPTH: u8 = 8;

pub fn draw(cv: *Canvas, look: *const Look, tree: []const Object, start: i16, depth: u8) void {
    const at = obj.offset(tree, start) orelse return;
    const o = tree[@intCast(start)];
    drawAt(cv, look, tree, start, @min(depth, MAX_DEPTH), at.x - o.x, at.y - o.y);
}

fn drawAt(cv: *Canvas, look: *const Look, tree: []const Object, i: i16, depth: u8, ox: i32, oy: i32) void {
    const o = &tree[@intCast(i)];
    if (o.flags & obj.HIDETREE != 0) return;
    const r: Rect = .{ .x = @intCast(ox + o.x), .y = @intCast(oy + o.y), .w = o.w, .h = o.h };
    if (!rect.intersect(extent(look, o, r), cv.clip).empty()) paint_mod.paint(cv, look, o, r);
    if (depth == 0 or o.head == obj.NIL) return;
    const saved = cv.clip;
    defer cv.clip = saved;
    if (o.flags & obj.CLIPKIDS != 0) {
        cv.clip = rect.intersect(saved, r);
        if (cv.clip.empty()) return;
    }
    var it = obj.children(tree, i);
    while (it.next()) |c| drawAt(cv, look, tree, c, depth - 1, r.x, r.y);
}

/// Everything paint() may write for `o` at `r`.
pub fn extent(look: *const Look, o: *const Object, r: Rect) Rect {
    var e = r;
    switch (o.ty) {
        obj.G_STRING, obj.G_TITLE => e.w = @max(e.w, textW(look.font, o.spec)),
        obj.G_TEXT, obj.G_FTEXT => e = rect.unite(e, tedBox(look, o, r)),
        obj.G_ICON, obj.G_CICON => e = rect.unite(e, iconBox(o, r)),
        else => {},
    }
    var out: i16 = 0;
    if (look.three_d and o.flags & obj.FL3DMASK != 0 and o.flags & obj.FL3DMASK != obj.FL3DBAK) out = look_mod.ADJ3D;
    out += switch (o.spec) {
        .box => |s| @max(0, -@as(i16, obj.boxThickness(s))),
        .ted => |t| @max(0, -@as(i16, t.thickness)),
        else => 0,
    };
    if (o.ty == obj.G_BUTTON) out += 3;
    if (o.state & obj.OUTLINED != 0) out = @max(out, 3);
    e = e.grow(out);
    if (o.state & obj.SHADOWED != 0) {
        e.w += paint_mod.SHADOW + out;
        e.h += paint_mod.SHADOW + out;
    }
    if (o.state & obj.CHECKED != 0) e = rect.unite(e, .{ .x = r.x, .y = r.y, .w = look.font.w, .h = @max(r.h, look.font.h) });
    return e;
}

fn textW(f: *const look_mod.Font, spec: obj.Spec) i16 {
    return switch (spec) {
        .str => |s| @intCast(@min(s.len * f.w, 4000)),
        else => 0,
    };
}

fn tedBox(look: *const Look, o: *const Object, r: Rect) Rect {
    const t = switch (o.spec) {
        .ted => |t| t,
        else => return r,
    };
    const f = if (t.font == obj.FONT_SMALL) look.small else look.font;
    const w: i16 = @intCast(@min(t.text.len * f.w, 4000));
    return .{ .x = r.x - @max(0, w - r.w), .y = r.y, .w = @max(r.w, w) * 2, .h = @max(r.h, f.h) };
}

fn iconBox(o: *const Object, r: Rect) Rect {
    const ib = switch (o.spec) {
        .icon => |i| i,
        .cicon => |c| &c.mono,
        else => return r,
    };
    const img: Rect = .{ .x = r.x + ib.ix, .y = r.y + ib.iy, .w = ib.w, .h = ib.h };
    const lab: Rect = .{ .x = r.x + ib.tx, .y = r.y + ib.ty, .w = ib.tw, .h = ib.th };
    return rect.unite(img, lab);
}
