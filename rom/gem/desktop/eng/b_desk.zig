// --------------------------------------------------------------------------
// The desktop layer: the work area as one G_BOX in the desktop colour (Set
// Preferences' palette entry) with the drive and trash icons as its G_ICON
// children. An icon object sits where ZigGEM's own icon is (icon.zig: the same
// cell, the same label box), so every hit-test the desktop logic does still
// lands on what is drawn; a set's icon art is centred on the built-in art's box,
// its bottom on the same line.
// --------------------------------------------------------------------------
const eng = @import("../../engine/obj.zig");
const icons = @import("../../gem_icons.zig");
const icon_mod = @import("../icon.zig");
const desk_icons = @import("../desk_icons.zig");
const ctx_mod = @import("ctx.zig");
const assets = @import("assets.zig");
const Ctx = ctx_mod.Ctx;
const Object = eng.Object;

pub const KEY: u16 = 1;

pub fn build(c: *Ctx) void {
    const d = c.d;
    const s = d.g.screen;
    const desk = eng.boxSpec(0, 0, eng.colorWord(1, 1, true, 7, 3)); // solid GEM green = the desktop colour
    var t = ctx_mod.Tree.begin(c.pool, .{ .ty = eng.G_BOX, .spec = .{ .box = desk }, .w = s.w, .h = s.h });
    for (&d.items, 0..) |*it, i| {
        if (!desk_icons.shown(d, i)) continue;
        const hot = i == desk_icons.IC_TRASH and d.file_drag >= 0 and it.hitAt(@intCast(d.g.px), @intCast(d.g.py));
        const sel = d.sel_icon == @as(i16, @intCast(i)) or hot;
        _ = t.add(0, iconObject(c, it, s.w, sel, 0, 0));
    }
    c.layer(.{ .key = KEY, .tree = t.objects() });
}

/// The object for ZigGEM icon `it`, its position relative to (ox, oy).
pub fn iconObject(c: *Ctx, it: *const icon_mod.Icon, screen_w: i16, sel: bool, ox: i16, oy: i16) Object {
    const a = c.set.icons[@intFromEnum(idOf(it.bmp))];
    const old = it.artRect();
    const lab = it.labelBox(screen_w);
    // The set's art centred on the built-in art's box, bottoms aligned; the built-in art at the bitmap's own place.
    const builtin = a.data.ptr == it.bmp.ink.ptr;
    const ix: i16 = if (builtin) it.x else old.x + @divTrunc(old.w - a.w, 2);
    const iy: i16 = if (builtin) it.y else old.y + old.h - a.h;
    const x0 = @min(ix, lab.x);
    const y0 = @min(iy, lab.y);
    const ib = c.pool.icon(.{
        .mask = a.mask, .data = a.data, .w = a.w, .h = a.h, .bpr = a.bpr, .text = it.label,
        .ix = ix - x0, .iy = iy - y0, .tx = lab.x - x0, .ty = lab.y - y0, .tw = lab.w, .th = lab.h,
    });
    const w = @max(ix + a.w, lab.x + lab.w) - x0;
    const h = @max(iy + a.h, lab.y + lab.h) - y0;
    const spec: eng.Spec = if (a.col) |col| .{ .cicon = c.cicon(ib, col) } else .{ .icon = ib };
    return .{ .ty = if (a.col != null) eng.G_CICON else eng.G_ICON, .state = if (sel) eng.SELECTED else 0, .spec = spec, .x = x0 - ox, .y = y0 - oy, .w = w, .h = h };
}

pub fn idOf(bmp: icons.Icon) assets.Id {
    if (bmp.ink.ptr == icons.FLOPPY.ink.ptr) return .floppy;
    if (bmp.ink.ptr == icons.HARD.ink.ptr) return .hard;
    if (bmp.ink.ptr == icons.TRASH.ink.ptr) return .trash;
    if (bmp.ink.ptr == icons.FOLDER.ink.ptr) return .folder;
    if (bmp.ink.ptr == icons.PROGRAM.ink.ptr) return .program;
    return .document;
}
