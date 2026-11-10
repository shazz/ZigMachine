// --------------------------------------------------------------------------
// GEMTEST's Dialogs area: the objects a GEM dialog is made of, as a REAL object
// tree since GEM 5 S4 (G20; dlg_tree.zig): buttons (default, exit, plain, a
// DISABLED one), a radio group (RBUTTON), check boxes (SELECTABLE), an editable
// G_FBOXTEXT (template __/__/__, digits only, objc_edit's caret) and a slider (a
// TOUCHEXIT track and its knob). The ROM draws them (objc_draw, the program look:
// TOS 4's 3D rules where the desk's engine has them), finds the one pressed
// (objc_find) and applies the click (form_button); the pen lays out the captions.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const O = rom.aes.obj;
const Pen = @import("pen.zig").Pen;
const App = @import("../gemtest.zig").App;
const wins = @import("wins.zig");
const T = @import("dlg_tree.zig");

const NAMES = [_][]const u8{ "none", "OK", "Cancel", "Plain" };

pub const State = struct {
    dlg: T.Dlg = .{},
    ready: bool = false,
    last: u8 = 0, // the last button: 1 OK, 2 Cancel, 3 Plain
    radio: u8 = 0,
    focus: bool = false,
    caret: u32 = 0,
    slider: u8 = 5,
};

pub fn draw(p: *Pen, app: *App) void {
    const st = &app.dlg;
    if (!st.ready) {
        st.dlg.init();
        st.ready = true;
    }
    layout(p, st);
    const tr = st.dlg.tree(app.g);
    if (!p.drawing) {
        if (tr.find(T.ROOT, p.hx, p.hy)) |i| if (i != T.ROOT) {
            p.hit = @intCast(i);
        };
        return;
    }
    tr.draw(T.ROOT, 8, p.work);
    if (st.focus) _ = tr.edit(T.FIELD, O.ED_INIT, 0, st.caret);
}

fn layout(p: *Pen, st: *State) void {
    var b: [48]u8 = undefined;
    const d = &st.dlg;
    d.objs[T.ROOT].x = @intCast(p.ox);
    d.objs[T.ROOT].y = @intCast(p.oy);
    p.line("Buttons: default, exit, plain, disabled");
    p.row(14);
    inline for (.{ T.OK, T.CANCEL, T.PLAIN, T.DISABLED_BTN }, .{ 4, 8, 7, 10 }) |i, cells| d.place(i, p.at(cells * p.cw), cells * p.cw, 14);
    p.endRow();
    p.line(std.fmt.bufPrint(&b, "Last pressed: {s} (Return: OK)", .{NAMES[st.last]}) catch "");
    p.gap();
    p.line("Radio group (RBUTTON):");
    p.row(14);
    const g0 = p.at(0);
    p.x -= p.cw;
    inline for (.{ 0, 1, 2 }, .{ 5, 8, 6 }) |k, cells| {
        const xy = p.at(cells * p.cw);
        d.place(T.RADIO0 + k, .{ xy[0] - g0[0], 0 }, cells * p.cw, 14);
    }
    d.place(T.RADIOS, g0, p.x - g0[0], 14);
    p.endRow();
    p.gap();
    p.line("Check boxes (SELECTABLE):");
    p.row(10);
    d.place(T.CHECK0, p.at(10), 10, 10);
    d.place(T.CHECK0 + 1, p.at(5 * p.cw), 5 * p.cw, 10);
    d.place(T.CHECK0 + 2, p.at(10), 10, 10);
    d.place(T.CHECK0 + 3, p.at(7 * p.cw), 7 * p.cw, 10);
    p.endRow();
    lower(p, st);
}

fn lower(p: *Pen, st: *State) void {
    const d = &st.dlg;
    p.gap();
    p.line("Editable G_FBOXTEXT, digits only (objc_edit):");
    p.row(12);
    p.label("Date:");
    d.place(T.FIELD, p.at(10 * p.cw), 10 * p.cw, 12);
    p.endRow();
    p.gap();
    p.line("Slider 0..10 (a TOUCHEXIT track, its knob):");
    p.row(10);
    d.place(T.TRACK, p.at(T.STOPS * T.STOP_W), T.STOPS * T.STOP_W, 10);
    d.place(T.KNOB, .{ @as(i32, st.slider) * T.STOP_W, 0 }, T.STOP_W, 10);
    var b: [8]u8 = undefined;
    p.label(std.fmt.bufPrint(&b, "{d}", .{st.slider}) catch "");
    p.endRow();
    p.missing("popup menus (menu_popup)");
}

/// A press on object `id` (the tree's, found by objc_find): form_button, then what it means.
pub fn press(app: *App, id: u8) void {
    const st = &app.dlg;
    const tr = st.dlg.tree(app.g);
    const r = tr.button(id);
    st.focus = id == T.FIELD;
    if (st.focus) st.caret = fieldLen(st);
    switch (id) {
        T.OK, T.CANCEL => {
            st.last = id;
            tr.change(id, st.dlg.objs[id].state & ~O.SELECTED, false); // an exit button pops back up
        },
        T.PLAIN => st.last = id,
        T.RADIO0...T.RADIO0 + 2 => st.radio = id - T.RADIO0,
        T.TRACK => {
            const x0 = st.dlg.objs[T.ROOT].x + st.dlg.objs[T.TRACK].x;
            st.slider = @intCast(std.math.clamp(@divTrunc(app.px - x0, T.STOP_W), 0, T.STOPS - 1));
        },
        else => {},
    }
    _ = r;
    repaint(app);
}

fn fieldLen(st: *const State) u32 {
    const t = st.dlg.text;
    if (t[0] == '@') return 0;
    return @intCast(std.mem.indexOfScalar(u8, &t, 0) orelse t.len);
}

/// Keys while the Dialogs window is on top: Return fires the default button (OK); with the field
/// focused, objc_edit types the key (digits only, by the field's validation).
pub fn key(app: *App, cp: u32) bool {
    const st = &app.dlg;
    if (cp == 13) {
        st.last = T.OK;
        repaint(app);
        return true;
    }
    if (!st.focus or cp > 127) return false;
    st.caret = st.dlg.tree(app.g).edit(T.FIELD, O.ED_CHAR, cp, st.caret);
    return true;
}

fn repaint(app: *App) void {
    if (app.wins.topSlot()) |t| wins.paintContent(app, t);
}
