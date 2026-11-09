// --------------------------------------------------------------------------
// GEM 5 engine: a SCENE is the screen as a stack of LAYERS, bottom to top — the
// desktop, each window, the overlays, the menu bar, an open drop-down, a dialog,
// the pointer. Each layer is one object tree drawn from its root, with:
//   bounds  all it can paint (the union of its objects' extents),
//   cover   up to four rectangles it paints opaquely (what it hides below it),
//   external  its pixels are painted by someone else before composing (the old
//           ZigGEM dialog code, in this step): the compositor never paints it,
//           but it still hides what is below it.
// measure() walks a tree the way draw.zig paints it (HIDETREE skipped, CLIPKIDS
// clipping the children) and gives every object its screen extent and a hash
// of what it shows and where (the extent is clipped, so it alone misses an
// object that moved under its clip), which the damage pass compares frame to frame.
// --------------------------------------------------------------------------
const std = @import("std");
const rect = @import("rect.zig");
const obj = @import("obj.zig");
const draw = @import("draw.zig");
const Look = @import("look.zig").Look;
const Rect = rect.Rect;
const Object = obj.Object;

pub const MAX_LAYERS = 24;
pub const MAX_OBJS = 768; // every layer's objects together

pub const Layer = struct {
    key: u16, // stable identity: the same window is the same key frame after frame
    tree: []const Object = &.{},
    cover: [4]Rect = [_]Rect{.{}} ** 4,
    n_cover: u8 = 0,
    external: bool = false,
    bounds: Rect = .{}, // set by measure()
    first: u16 = 0, // its objects' slots in the measure arrays
};

pub const Scene = struct {
    layers: [MAX_LAYERS]Layer = undefined,
    n: usize = 0,
    ext: [MAX_OBJS]Rect = undefined, // per object, in layer order
    hash: [MAX_OBJS]u32 = undefined,
    n_obj: usize = 0,
    overflow: bool = false, // a layer did not fit: the scene is incomplete
    no_pos: bool = false, // the --break hashpos mutant: hashes blind to where an object is

    pub fn add(self: *Scene, l: Layer) void {
        if (self.n == MAX_LAYERS or self.n_obj + l.tree.len > MAX_OBJS) {
            self.overflow = true;
            return;
        }
        self.layers[self.n] = l;
        self.layers[self.n].first = @intCast(self.n_obj);
        self.n_obj += l.tree.len;
        self.n += 1;
    }

    pub fn objs(self: *const Scene, i: usize) struct { ext: []const Rect, hash: []const u32 } {
        const l = &self.layers[i];
        return .{ .ext = self.ext[l.first..][0..l.tree.len], .hash = self.hash[l.first..][0..l.tree.len] };
    }

    /// Extents, hashes and bounds of every layer (after the last add()).
    pub fn measure(self: *Scene, look: *const Look) void {
        for (self.layers[0..self.n]) |*l| {
            const ext = self.ext[l.first..][0..l.tree.len];
            const hs = self.hash[l.first..][0..l.tree.len];
            @memset(ext, Rect{});
            for (l.tree, 0..) |*o, i| hs[i] = hashOf(o);
            const out: Out = .{ .ext = ext, .pos = if (self.no_pos) null else hs };
            if (l.tree.len > 0) walk(look, l.tree, 0, 0, 0, Rect{ .x = -32000, .y = -32000, .w = 32767, .h = 32767 }, out, 0);
            l.bounds = .{};
            for (ext) |e| l.bounds = rect.unite(l.bounds, e);
            for (l.cover[0..l.n_cover]) |c| l.bounds = rect.unite(l.bounds, c);
        }
    }
};

// Where walk() writes: each object's clipped extent and, unless null (the mutant), its hash
// with its screen position mixed in.
const Out = struct { ext: []Rect, pos: ?[]u32 };

fn walk(look: *const Look, tree: []const Object, i: i16, ox: i32, oy: i32, clip: Rect, out: Out, depth: u8) void {
    const o = &tree[@intCast(i)];
    if (o.flags & obj.HIDETREE != 0) return;
    const r: Rect = .{ .x = @intCast(ox + o.x), .y = @intCast(oy + o.y), .w = o.w, .h = o.h };
    out.ext[@intCast(i)] = rect.intersect(draw.extent(look, o, r), clip);
    // The extent is CLIPPED: a text row wider than its window that scrolled sideways keeps the same
    // clipped extent, and the same hash, while every pixel of it moved. Its position is part of
    // what it shows (Matt on the board, 9 Nov: text view scrolled sideways left rows unrepainted).
    if (out.pos) |hs| hs[@intCast(i)] = mix(hs[@intCast(i)], std.mem.asBytes(&[_]i16{ r.x, r.y }));
    if (depth >= draw.MAX_DEPTH) return;
    const kids = if (o.flags & obj.CLIPKIDS != 0) rect.intersect(clip, r) else clip;
    var it = obj.children(tree, i);
    while (it.next()) |c| walk(look, tree, c, r.x, r.y, kids, out, depth + 1);
}

/// What an object shows, as a 32-bit FNV-1a: its type, flags, state, size and the
/// contents its spec points at (text bytes; image identity by address).
pub fn hashOf(o: *const Object) u32 {
    var h: u32 = 2166136261;
    h = mix(h, std.mem.asBytes(&[_]u16{ o.ty, o.flags, o.state, @bitCast(o.w), @bitCast(o.h) }));
    switch (o.spec) {
        .none => {},
        .box => |b| h = mix(h, std.mem.asBytes(&b)),
        .str => |s| h = mix(h, s),
        .ted => |t| {
            h = mix(h, t.text);
            h = mix(h, std.mem.asBytes(&[_]u16{ t.font, t.just, t.color, @as(u8, @bitCast(t.thickness)) }));
        },
        .icon => |ib| h = iconHash(h, ib),
        .cicon => |ci| h = mix(iconHash(h, &ci.mono), std.mem.asBytes(&@intFromPtr(ci.col.ptr))),
        .image => |b| h = mix(h, std.mem.asBytes(&[_]usize{ @intFromPtr(b.data.ptr), b.color })),
    }
    return h;
}

fn iconHash(h0: u32, ib: *const obj.IconBlk) u32 {
    var h = mix(h0, ib.text);
    h = mix(h, std.mem.asBytes(&@intFromPtr(ib.data.ptr)));
    return mix(h, std.mem.asBytes(&[_]i16{ ib.ix, ib.iy, ib.tx, ib.ty, ib.tw, ib.th, @bitCast(ib.color) }));
}

fn mix(h0: u32, bytes: []const u8) u32 {
    var h = h0;
    for (bytes) |b| h = (h ^ b) *% 16777619;
    return h;
}
