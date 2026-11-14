// --------------------------------------------------------------------------
// KESTRAMP: what a press at a window position hits, from the geometry in
// layout.zig: a transport button, a toggle, or a row of the open list.
// --------------------------------------------------------------------------
const L = @import("layout.zig");
const Btn = @import("panel.zig").Btn;

pub const Hit = union(enum) { btn: Btn, toggle: u1, row: usize };

pub fn hitTest(x: i32, y: i32, list_open: bool, n: usize, top: usize) ?Hit {
    for (0..6) |i| {
        if (inRect(x, y, L.btnX(i), L.BTN_Y, L.BTN_W, L.BTN_H)) return .{ .btn = @enumFromInt(i) };
    }
    for (L.TOG_X, 0..) |tx, i| {
        if (inRect(x, y, tx, L.TOG_Y, L.TOG_W, L.TOG_H)) return .{ .toggle = @intCast(i) };
    }
    if (list_open and inRect(x, y, L.LIST_X, L.LIST_Y, L.LIST_W, L.LIST_H)) {
        const i = top + @as(usize, @intCast(y - L.LIST_Y)) / L.ROW_H;
        if (i < n) return .{ .row = i };
    }
    return null;
}

fn inRect(x: i32, y: i32, rx: i32, ry: i32, w: usize, h: usize) bool {
    return x >= rx and x < rx + @as(i32, @intCast(w)) and y >= ry and y < ry + @as(i32, @intCast(h));
}
