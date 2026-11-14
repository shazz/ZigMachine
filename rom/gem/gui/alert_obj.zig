// --------------------------------------------------------------------------
// A program's form_alert drawn by the GEM 5 engine (G19): alert_tree.zig builds
// TOS 4's tree, this draws it into the context's plane in the program look
// (proglook.zig: flat TOS 1 or 3D TOS 4, the set's NOTE / QUES / STOP art).
//
// The input is the old path's (dialog.zig): a button fires on the frame the press
// STARTS over it, Return fires the default one, the pressed button is drawn
// SELECTED while the pointer button is held over it. Drawn whole each frame the
// program calls dialogProcess, clipped and recorded as every Gui primitive is
// (clip.zig), so the desk's GEM 5 frame could host it as it hosts the old one.
// --------------------------------------------------------------------------
const obj = @import("../engine/obj.zig");
const draw = @import("../engine/draw.zig");
const L = @import("../engine/look.zig");
const tree_mod = @import("alert_tree.zig");
const proglook = @import("proglook.zig");
const clip = @import("clip.zig");
const Gui = @import("core.zig").Gui;

/// A frame of the alert: built, drawn, and the button chosen this frame (0-based), or null.
pub fn frame(g: *Gui, s: tree_mod.Spec) ?u8 {
    var t: tree_mod.Tree = .{};
    const lk = proglook.look(g);
    tree_mod.build(&t, s, &lk, artOf(g, s.icon), g.screen.w, g.screen.h);
    var fired: ?u8 = null;
    for (0..t.nbtn) |k| {
        const r = t.buttonBox(k);
        const over = r.contains(g.px, g.py);
        if (over and g.down) t.objs[@as(usize, @intCast(t.first_btn)) + k].state |= obj.SELECTED;
        if (over and g.edge) fired = @intCast(k);
    }
    if (fired == null and g.enter and s.default > 0 and s.default <= t.nbtn) fired = s.default - 1;
    if (fired) |k| t.objs[@as(usize, @intCast(t.first_btn)) + k].state |= obj.SELECTED; // the answer flashes, as on TOS
    var cv = proglook.canvasOf(g);
    const tree = t.objs[0..t.n];
    draw.draw(&cv, &lk, tree, 0, draw.MAX_DEPTH);
    const e = draw.extent(&lk, &tree[0], obj.offset(tree, 0).?);
    clip.record(g, .{ .x = e.x, .y = e.y, .w = e.w, .h = e.h });
    return fired;
}

/// The icon art for form_alert's icon 1..3 from the program look's set; null for 0.
fn artOf(g: *const Gui, icon: u8) ?obj.BitBlk {
    if (icon < 1 or icon > 3) return null;
    const a = proglook.setOf(g).alerts[icon - 1];
    const blank = proglook.breaks & proglook.BREAK_NOICON != 0; // the mutant: the art lost, the layout kept
    return .{ .data = if (blank) &.{} else a.data, .w = a.w, .h = a.h, .bpr = a.bpr, .color = L.BLACK };
}
