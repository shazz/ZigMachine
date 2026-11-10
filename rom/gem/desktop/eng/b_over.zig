// --------------------------------------------------------------------------
// The overlays and the pointer, each a layer of its own above the windows:
//   - GEM's dotted gestures: a window's move / resize outline (Wm.ghost), a
//     dragged icon or file (its art box and label box, where it would land), the
//     rubber band, the zoom-box frame deskdraw.zig drew this frame;
//   - the dialog the old ZigGEM code painted this frame (an EXTERNAL layer: the
//     compositor never paints it, only keeps out of it);
//   - the arrow, last: the set's mouse form, its hot spot on the pointer.
// --------------------------------------------------------------------------
const eng = @import("../../engine/obj.zig");
const L = @import("../../engine/look.zig");
const rect = @import("../../engine/rect.zig");
const gui = @import("../../gui.zig");
const icon_mod = @import("../icon.zig");
const dirview = @import("../dirview.zig");
const desksel = @import("../desksel.zig");
const desk_icons = @import("../desk_icons.zig");
const deskarrow = @import("../deskarrow.zig");
const ctx_mod = @import("ctx.zig");
const Ctx = ctx_mod.Ctx;
const Tree = ctx_mod.Tree;
const Rect = rect.Rect;

pub const KEY_OVER: u16 = 200;
pub const KEY_DIALOG: u16 = 240;
pub const KEY_POINTER: u16 = 250;
const DOTS = eng.boxSpec(0, 0, eng.colorWord(L.BLACK, L.BLACK, false, 0, 0));

pub fn gestures(c: *Ctx) void {
    const d = c.d;
    var t = Tree.begin(c.pool, .{ .ty = eng.G_IBOX, .spec = ctx_mod.box(0, 1, L.WHITE, 0) });
    if (d.wm.ghost) |r| dots(&t, r);
    if (d.band) dots(&t, desksel.bandRect(d));
    if (d.grow_drawn) |r| dots(&t, r);
    if (d.file_drag >= 0 and d.file_moved) {
        if (desksel.rowGhost(d)) |r| dots(&t, r) else { // text view: the row's outline
            const bmp = dirview.fileBmp(d, @intCast(d.file_drag));
            ghost(&t, @intCast(@as(i32, d.g.px) - d.file_gx), @intCast(@as(i32, d.g.py) - d.file_gy), bmp);
        }
    }
    if (d.drag) |di| if (d.moved) {
        const p = desk_icons.ghostAt(d, &d.g);
        ghost(&t, p.x, p.y, d.items[di].bmp);
    };
    if (t.len > 1) c.layer(.{ .key = KEY_OVER, .tree = t.objects() });
}

fn dots(t: *Tree, r: gui.Rect) void {
    _ = t.add(0, .{ .ty = eng.G_DOTS, .spec = .{ .box = DOTS }, .x = r.x, .y = r.y, .w = r.w, .h = r.h });
}

// An icon's footprint where it would land: its art box and its label field.
fn ghost(t: *Tree, x: i16, y: i16, bmp: @import("../../iconset.zig").Icon) void {
    const a = icon_mod.artBox(bmp);
    const ax = x + a.x;
    const lx = ax + @divTrunc(a.w - icon_mod.LABEL_W, 2);
    dots(t, .{ .x = ax, .y = y + a.y, .w = a.w, .h = a.h + 1 });
    dots(t, .{ .x = lx, .y = y + a.y + a.h, .w = icon_mod.LABEL_W, .h = icon_mod.LABEL_H });
}

/// The dialog the old code painted into `painted` (empty: none this frame).
pub fn dialog(c: *Ctx, painted: gui.Rect) void {
    if (painted.w <= 0 or painted.h <= 0) return;
    const r: Rect = .{ .x = painted.x, .y = painted.y, .w = painted.w, .h = painted.h };
    c.layer(.{ .key = KEY_DIALOG, .external = true, .cover = .{ r, .{}, .{}, .{} }, .n_cover = 1 });
}

pub fn pointer(c: *Ctx, ib: *const eng.IconBlk) void {
    const d = c.d;
    const at = deskarrow.at(d.g.px, d.g.py, d.g.screen.w, d.g.screen.h);
    const t = Tree.begin(c.pool, .{ .ty = eng.G_ICON, .spec = .{ .icon = ib }, .x = @intCast(at[0] - c.set.arrow.hx), .y = @intCast(at[1] - c.set.arrow.hy), .w = 16, .h = 16 });
    c.layer(.{ .key = KEY_POINTER, .tree = t.objects() });
}
