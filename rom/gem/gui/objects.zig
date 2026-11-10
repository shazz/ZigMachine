// --------------------------------------------------------------------------
// A PROGRAM's object trees on the GEM 5 engine (G20): the ROM half of objc_draw,
// objc_find, objc_change, form_button and objc_edit (rom/rom_app_obj.zig exports
// them). A call loads the tree from the program's memory (wire.zig: every address
// checked against the cart window), works on the engine's copy, and writes back
// only ob_state (form_button, objc_change) or te_ptext (objc_edit), the two
// things the AES itself writes into a program's tree.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const obj = @import("../engine/obj.zig");
const draw_mod = @import("../engine/draw.zig");
const find_mod = @import("../engine/find.zig");
const R = @import("../engine/rect.zig");
const wire = @import("wire.zig");
const objedit = @import("objedit.zig");
const proglook = @import("proglook.zig");
const clip = @import("clip.zig");
const Gui = @import("core.zig").Gui;

var store: wire.Store = undefined;
const BREAK_RADIO: u32 = 1 << 29; // deskSetEngine's mutant (gemtest_obj_check --break radio)

const wire_icon = @import("wire_icon.zig");
const BREAK_ICONS: u32 = 1 << 30; // deskSetEngine's mutant: the ROM's icons lost (gemtest_icon_check)
var sys: [6]wire_icon.Art = undefined; // the ROM's icons a program's G_ICON may name, by number
var sys_ok = false;

// The desktop's icon set (proglook's: the asset set's, else TOS 1.0's), once.
fn ensureSys(g: *const Gui) void {
    if (sys_ok) return;
    for (&sys, proglook.setOf(g).icons) |*s, a| s.* = .{ .w = a.w, .h = a.h, .bpr = a.bpr, .mask = a.mask, .data = a.data };
    sys_ok = true;
}

fn loadTree(addr: u32, n: u32) ?[]obj.Object {
    store.sys = if (!sys_ok or proglook.breaks & BREAK_ICONS != 0) &.{} else &sys;
    return wire.load(mem(), addr, n, &store);
}

/// WF_NEWDESK: the program's desktop tree (its root the desk, icons its children), 0 none.
pub var desk_addr: u32 = 0;
pub var desk_n: u32 = 0;

pub fn mem() wire.Mem {
    const p: [*]u8 = @ptrFromInt(hw.CART_RAM_BASE);
    return .{ .base = hw.CART_RAM_BASE, .bytes = p[0 .. hw.CART_RAM_TOP - hw.CART_RAM_BASE] };
}

/// objc_draw: `start` and `depth` levels, clipped to `within` (and the context's clip).
pub fn draw(g: *Gui, addr: u32, n: u32, start: i16, depth: u8, within: R.Rect) void {
    ensureSys(g);
    const tree = loadTree(addr, n) orelse return;
    if (!obj.valid(tree, start)) return;
    paint(g, tree, start, depth, within);
}

fn paint(g: *Gui, tree: []const obj.Object, start: i16, depth: u8, within: R.Rect) void {
    const lk = proglook.look(g);
    var cv = proglook.canvasOf(g);
    cv.clip = R.intersect(cv.clip, within);
    if (cv.clip.empty()) return;
    draw_mod.draw(&cv, &lk, tree, start, depth);
    clip.record(g, .{ .x = cv.clip.x, .y = cv.clip.y, .w = cv.clip.w, .h = cv.clip.h });
}

/// What an object can paint, on screen (its extent: outlines, 3D outsets, a long string).
fn extentOf(g: *const Gui, tree: []const obj.Object, i: i16) R.Rect {
    const lk = proglook.look(g);
    return draw_mod.extent(&lk, &tree[@intCast(i)], obj.offset(tree, i).?);
}

/// objc_find: the object under (x, y), -1 for none (or a bad tree).
pub fn find(addr: u32, n: u32, start: i16, depth: u8, x: i32, y: i32) i32 {
    const tree = loadTree(addr, n) orelse return -1;
    if (!obj.valid(tree, start)) return -1;
    return find_mod.find(tree, start, depth, x, y);
}

/// objc_change: the state written into the program's tree, the object redrawn over its root.
pub fn change(g: *Gui, addr: u32, n: u32, i: i16, state: u16, redraw: bool) void {
    const w = mem().objs(addr, n) orelse return;
    if (i < 0 or i >= w.len) return;
    w[@intCast(i)].state = state;
    if (redraw) redrawObj(g, addr, n, i);
}

/// An object repainted where it can paint, the tree from its root (what is under it first).
pub fn redrawObj(g: *Gui, addr: u32, n: u32, i: i16) void {
    ensureSys(g);
    const tree = loadTree(addr, n) orelse return;
    if (!obj.valid(tree, i)) return;
    paint(g, tree, 0, draw_mod.MAX_DEPTH, extentOf(g, tree, i));
}

/// form_button: bit 0 an EXIT / TOUCHEXIT object, bit 1 some state changed (redraw the tree).
pub fn button(addr: u32, n: u32, i: i16) u32 {
    const tree = loadTree(addr, n) orelse return 0;
    const w = mem().objs(addr, n).?;
    if (proglook.breaks & BREAK_RADIO != 0) for (tree) |*o| { // the mutant: radio groups forgotten
        o.flags &= ~obj.RBUTTON;
    };
    const c = find_mod.button(tree, i);
    for (tree, 0..) |o, k| w[k].state = o.state;
    return @as(u32, @intFromBool(c.exit)) | @as(u32, @intFromBool(c.changed)) << 1;
}

/// objc_edit on the G_FTEXT / G_FBOXTEXT `i`: ED_INIT (1) shows the caret at `idx`, ED_CHAR (2)
/// types `key` there, ED_END (3) hides it. The caret's index, -1 for an object that is not one.
pub fn edit(g: *Gui, addr: u32, n: u32, i: i16, kind: u32, key: u32, idx: u32) i32 {
    const m = mem();
    const w = m.objs(addr, n) orelse return -1;
    if (i < 0 or i >= w.len) return -1;
    const o = w[@intCast(i)];
    if (o.ty != obj.G_FTEXT and o.ty != obj.G_FBOXTEXT) return -1;
    const t = m.ted(o.spec) orelse return -1;
    const buf = m.slice(t.text, @intCast(@max(1, t.txtlen))) orelse return -1;
    const tmplt = m.str(t.tmplt);
    var at: usize = idx;
    if (kind == 2) at = objedit.edit(buf, tmplt, m.str(t.valid), idx, @truncate(key)).idx;
    redrawObj(g, addr, n, i);
    if (kind != 3) caret(g, addr, n, i, wire.caretCol(tmplt, at));
    return @intCast(at);
}

// The caret: two pixels wide, a cell high, before template column `col` of the shown text.
fn caret(g: *Gui, addr: u32, n: u32, i: i16, col: usize) void {
    const tree = loadTree(addr, n) orelse return;
    const r = obj.offset(tree, i).?;
    const lk = proglook.look(g);
    const t = switch (tree[@intCast(i)].spec) {
        .ted => |t| t,
        else => return,
    };
    const tw: i32 = @intCast(t.text.len * lk.font.w);
    const x0: i32 = if (t.just == obj.JUST_CENTRE) r.x + @divTrunc(r.w - tw + 1, 2) else if (t.just == obj.JUST_RIGHT) r.x + r.w - tw else r.x;
    var cv = proglook.canvasOf(g);
    const y = r.y + @divTrunc(r.h - @as(i32, lk.font.h) + 1, 2);
    cv.fill(.{ .x = @intCast(x0 + @as(i32, @intCast(col)) * lk.font.w), .y = @intCast(y - 1), .w = 2, .h = @intCast(lk.font.h + 2) }, lk.ink(1));
}
