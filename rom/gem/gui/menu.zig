// --------------------------------------------------------------------------
// Menu bar — GEM-style pull-down menus. Click a title to drop it, click an item
// to pick it (returns {menu,item}), click away to close. Draw it LAST each frame
// so an open drop-down overlays the windows.
//
// GEM: the bar is gl_hbox = char height + 3 = 11 rows in low/medium res — 10
// white rows (text on row 1) closed by a black line on row MENU_H; the desktop
// work area starts at MENU_H + 1. Titles are laid out as " Desk  File " (one
// space each side), items are dense 8px char rows.
// --------------------------------------------------------------------------
const types = @import("types.zig");
const Gui = @import("core.zig").Gui;
const Rect = types.Rect;
const MENU_H = types.MENU_H;
const ITEM_H = types.ITEM_H;
const BLACK = types.BLACK;
const WHITE = types.WHITE;

const TITLE_X0: i16 = 8; // first title starts one char cell in
const PAD: i16 = 8; // one char cell each side of a title (its highlight box)
pub const Menu = struct { title: []const u8, items: []const []const u8 };
pub const MenuPick = struct { menu: u8, item: u8 };

// An item beginning with '-' is a GEM separator ("--------"): drawn, never picked.
pub fn isSeparator(item: []const u8) bool {
    return item.len > 0 and item[0] == '-';
}

pub const MenuBar = struct {
    open: i16 = -1, // index of the dropped menu, -1 = none

    fn titleBox(x: i16, m: Menu) Rect {
        return .{ .x = x - PAD, .y = 0, .w = @as(i16, @intCast(m.title.len)) * 8 + 2 * PAD, .h = MENU_H };
    }

    // GEM feel: a title drops as soon as the pointer moves over it (no click
    // needed), sliding along the bar switches menus, a click on an item picks
    // it, a click anywhere else closes the menu. Nothing drops while the button
    // is held from elsewhere (e.g. a window being dragged across the bar).
    pub fn process(self: *MenuBar, g: *Gui, menus: []const Menu, bar_w: i16, locked: bool) ?MenuPick {
        if (locked) self.open = -1; // a modal dialog owns input — bar is inert
        g.rect(.{ .x = 0, .y = 0, .w = bar_w, .h = MENU_H }, WHITE);
        g.blit.fill(g.fb, 0, MENU_H, @intCast(bar_w), 1, BLACK);

        var x: i16 = TITLE_X0;
        var pick: ?MenuPick = null;
        for (menus, 0..) |m, i| {
            const tb = titleBox(x, m);
            if (!locked and g.hit(tb) and (!g.down or g.edge)) self.open = @intCast(i);
            const hot = self.open == @as(i16, @intCast(i));
            if (hot) g.rect(tb, BLACK);
            g.text(m.title, x, 1, if (hot) WHITE else BLACK, if (hot) BLACK else WHITE);
            if (hot) pick = drop(g, m, i, tb.x);
            x += tb.w;
        }
        // a click outside the bar and the open drop-down closes it (or picks)
        if (g.edge and self.open >= 0 and g.py > MENU_H and !self.overDrop(g, menus)) self.open = -1;
        if (pick != null) self.open = -1;
        return pick;
    }

    fn dropWidth(m: Menu) i16 {
        var w: i16 = 0;
        for (m.items) |it| w = @max(w, @as(i16, @intCast(it.len)));
        return w * 8 + 2 * PAD;
    }
    fn dropRect(m: Menu, dx: i16) Rect {
        return .{ .x = dx, .y = MENU_H, .w = dropWidth(m), .h = @as(i16, @intCast(m.items.len)) * ITEM_H + 2 };
    }

    fn drop(g: *Gui, m: Menu, mi: usize, dx: i16) ?MenuPick {
        const d = dropRect(m, dx);
        g.rect(d, WHITE);
        g.frame(d, BLACK);
        var pick: ?MenuPick = null;
        for (m.items, 0..) |it, j| {
            const row = Rect{ .x = d.x + 1, .y = d.y + 1 + @as(i16, @intCast(j)) * ITEM_H, .w = d.w - 2, .h = ITEM_H };
            const hover = g.hit(row) and !isSeparator(it);
            if (hover) g.rect(row, BLACK);
            g.text(it, row.x + PAD - 1, row.y, if (hover) WHITE else BLACK, if (hover) BLACK else WHITE);
            if (g.edge and hover) pick = .{ .menu = @intCast(mi), .item = @intCast(j) };
        }
        return pick;
    }

    // Is the pointer over the currently-open drop-down (so a click shouldn't close)?
    fn overDrop(self: *MenuBar, g: *Gui, menus: []const Menu) bool {
        var x: i16 = TITLE_X0;
        for (menus, 0..) |m, i| {
            const tb = titleBox(x, m);
            if (self.open == @as(i16, @intCast(i))) return g.hit(dropRect(m, tb.x));
            x += tb.w;
        }
        return false;
    }
};
