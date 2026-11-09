// --------------------------------------------------------------------------
// The menu bar and its open drop-down, as two layers, at the places
// gui/menu.zig hit-tests: titles one char cell in, each title box one cell
// wider each side; the drop-down under its title, 16 px of left margin (the
// tick's), one 8 px row an item. The open title and the item under the pointer
// are SELECTED (inverted), as MenuBar draws them; a separator is a disabled row
// of dashes, a disabled item grey.
// --------------------------------------------------------------------------
const eng = @import("../../engine/obj.zig");
const L = @import("../../engine/look.zig");
const gui = @import("../../gui.zig");
const types = @import("../../gui/types.zig");
const deskmenu = @import("../deskmenu.zig");
const ctx_mod = @import("ctx.zig");
const Ctx = ctx_mod.Ctx;
const Tree = ctx_mod.Tree;
const Rect = @import("../../engine/rect.zig").Rect;

pub const KEY_BAR: u16 = 230;
pub const KEY_DROP: u16 = 231;
const PAD: i16 = 8;
const MH: i16 = types.MENU_H;

pub fn build(c: *Ctx) void {
    var buf: deskmenu.MenuBuf = undefined;
    const menus = deskmenu.buildMenus(c.d, &buf);
    const w = c.d.g.screen.w;
    var t = Tree.begin(c.pool, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(0, 1, L.WHITE, 7), .w = w, .h = MH + 1 });
    _ = t.add(0, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(0, 1, L.BLACK, 7), .y = MH, .w = w, .h = 1 });
    var x: i16 = 8;
    var drop_x: i16 = 0;
    for (menus, 0..) |m, i| {
        const tw: i16 = @as(i16, @intCast(m.title.len)) * 8 + 2 * PAD;
        const open = c.d.menubar.open == @as(i16, @intCast(i));
        const label = c.pool.bytes(m.title.len + 1);
        if (label.len == m.title.len + 1) {
            label[0] = ' ';
            @memcpy(label[1..], m.title);
        }
        _ = t.add(0, .{ .ty = eng.G_TITLE, .state = if (open) eng.SELECTED else 0, .spec = .{ .str = label }, .x = x - PAD, .w = tw, .h = MH });
        if (open) drop_x = x - PAD;
        x += tw;
    }
    c.layer(.{ .key = KEY_BAR, .tree = t.objects(), .cover = .{ .{ .w = w, .h = MH + 1 }, .{}, .{}, .{} }, .n_cover = 1 });
    if (c.d.menubar.open >= 0 and c.d.menubar.open < menus.len) drop(c, menus[@intCast(c.d.menubar.open)], drop_x);
}

fn drop(c: *Ctx, m: gui.Menu, dx: i16) void {
    var widest: i16 = 0;
    for (m.items) |it| widest = @max(widest, @as(i16, @intCast(it.label.len)));
    const r: Rect = .{ .x = dx, .y = MH, .w = widest * 8 + 24, .h = @as(i16, @intCast(m.items.len)) * types.ITEM_H + 2 };
    var t = Tree.begin(c.pool, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(1, 1, L.WHITE, 7), .x = r.x, .y = r.y, .w = r.w, .h = r.h });
    for (m.items, 0..) |it, j| item(c, &t, r, it, j);
    c.layer(.{ .key = KEY_DROP, .tree = t.objects(), .cover = .{ r, .{}, .{}, .{} }, .n_cover = 1 });
}

fn item(c: *Ctx, t: *Tree, r: Rect, it: gui.MenuItem, j: usize) void {
    const row: Rect = .{ .x = 1, .y = 1 + @as(i16, @intCast(j)) * types.ITEM_H, .w = r.w - 2, .h = types.ITEM_H };
    const sep = gui.isSeparator(it);
    const hover = !sep and !it.disabled and gui.inRect(.{ .x = r.x + row.x, .y = r.y + row.y, .w = row.w, .h = row.h }, c.d.g.px, c.d.g.py);
    const state: u16 = (if (hover) eng.SELECTED else 0) | (if (sep or it.disabled) eng.DISABLED else 0);
    const bar = t.add(0, .{ .ty = eng.G_BOX, .state = state & eng.SELECTED, .spec = ctx_mod.box(0, 1, L.WHITE, 7), .x = row.x, .y = row.y, .w = row.w, .h = row.h });
    if (sep) {
        const n: usize = @intCast(@max(0, @divTrunc(row.w, 8)));
        const dashes = c.pool.bytes(n);
        @memset(dashes, '-');
        _ = t.add(bar, .{ .ty = eng.G_STRING, .state = eng.DISABLED, .spec = .{ .str = dashes }, .x = @divTrunc(row.w - @as(i16, @intCast(dashes.len)) * 8, 2), .w = row.w, .h = row.h });
        return;
    }
    if (it.tick) _ = t.add(bar, .{ .ty = eng.G_STRING, .state = state, .spec = .{ .str = "\x08" }, .x = 3, .w = 8, .h = row.h });
    _ = t.add(bar, .{ .ty = eng.G_STRING, .state = state, .spec = .{ .str = it.label }, .x = 15, .w = @as(i16, @intCast(it.label.len)) * 8, .h = row.h });
}
