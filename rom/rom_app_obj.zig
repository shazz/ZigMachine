// --------------------------------------------------------------------------
// GEM 5's program API, object trees (G20, system table 1.23; the app half is
// rom/sdk/aes_obj.zig, the work is rom/gem/gui/objects.zig): objc_draw, objc_find,
// objc_change, form_button and objc_edit on an AES tree in the program's memory.
// `tree` is its address, `n` its objects (at most 64); a tree outside the cart
// window, a bad handle or an index outside the tree does nothing.
// --------------------------------------------------------------------------
const main = @import("rom_main.zig");
const objects = @import("rom").gui.objects;

fn idx(v: u32) i16 {
    return @intCast(@min(v, 0x7FFF));
}
fn depthOf(v: u32) u8 {
    return @intCast(@min(v, 8));
}

/// objc_draw(tree, start, depth, clip): w or h <= 0 is the whole screen.
export fn objcDraw(h: u32, tree: u32, n: u32, start: u32, depth: u32, cx: i32, cy: i32, cw: i32, ch: i32) void {
    const g = main.guiAt(h) orelse return;
    const all = cw <= 0 or ch <= 0;
    const r = main.rectOf(if (all) 0 else cx, if (all) 0 else cy, if (all) g.screen.w else cw, if (all) g.screen.h else ch);
    objects.draw(g, tree, n, idx(start), depthOf(depth), .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h });
}
/// objc_find: the object under (x, y) at or below `start`, -1 none.
export fn objcFind(h: u32, tree: u32, n: u32, start: u32, depth: u32, x: i32, y: i32) i32 {
    _ = main.guiAt(h) orelse return -1;
    return objects.find(tree, n, idx(start), depthOf(depth), x, y);
}
/// objc_change: `state` into the object, redrawn when `redraw` is 1.
export fn objcChange(h: u32, tree: u32, n: u32, obj: u32, state: u32, redraw: u32) void {
    const g = main.guiAt(h) orelse return;
    objects.change(g, tree, n, idx(obj), @truncate(state), redraw != 0);
}
/// form_button: a click on `obj` (radio groups, toggles, DISABLED); bit 0 exit, bit 1 changed.
export fn formButton(h: u32, tree: u32, n: u32, obj: u32) u32 {
    _ = main.guiAt(h) orelse return 0;
    return objects.button(tree, n, idx(obj));
}
/// objc_edit: `kind` 1 ED_INIT, 2 ED_CHAR (`key`), 3 ED_END, the caret at `idx`; its new index.
export fn objcEdit(h: u32, tree: u32, n: u32, obj: u32, kind: u32, key: u32, at: u32) i32 {
    const g = main.guiAt(h) orelse return -1;
    return objects.edit(g, tree, n, idx(obj), kind, key, at);
}
