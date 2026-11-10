// --------------------------------------------------------------------------
// GEMTEST's Dialogs area: the objects a GEM dialog is made of. The API has the
// ROM's buttons (guiButton: borders 1, 2, 3, selected or not) and boxes (guiBox);
// the radio group, the check boxes, the editable field and the slider below are
// the PROGRAM's, built from those and labelled so (no object trees, no form_do).
// A press is hit-tested by the pen against the same layout that drew it.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const Pen = @import("pen.zig").Pen;
const App = @import("../gemtest.zig").App;
const wins = @import("wins.zig");

pub const OK: u8 = 0;
const CANCEL: u8 = 1;
const PLAIN: u8 = 2;
const RADIO: u8 = 3; // 3, 4, 5
const CHECK: u8 = 6; // 6, 7
const FIELD: u8 = 8;
const SLIDER: u8 = 9; // 9 .. 19: the slider's eleven stops
const BUTTONS = [_][]const u8{ "OK", "Cancel", "Plain" };
const RADIOS = [_][]const u8{ "Low", "Medium", "High" };

pub const State = struct {
    last: u8 = 0xFF, // the last button pressed
    radio: u8 = 0,
    checks: [2]bool = .{ true, false },
    digits: [6]u8 = undefined,
    ndigits: u8 = 0,
    focus: bool = false,
    slider: u8 = 5,
};

pub fn draw(p: *Pen, app: *App) void {
    const st = &app.dlg;
    var b: [48]u8 = undefined;
    p.line("Buttons (guiButton): default, exit, plain");
    p.row(16);
    for (BUTTONS, 0..) |s, i| p.button(@intCast(i), s, false, @intCast(3 - i));
    p.endRow();
    p.line(std.fmt.bufPrint(&b, "Last pressed: {s} (Return: OK)", .{if (st.last < 3) BUTTONS[st.last] else "none"}) catch "");
    p.missing("a disabled button (DISABLED)");
    p.gap();
    p.line("Radio group, built by the program:");
    p.row(16);
    for (RADIOS, 0..) |s, i| p.button(RADIO + @as(u8, @intCast(i)), s, st.radio == i, 1);
    p.endRow();
    p.missing("radio buttons (RBUTTON)");
    p.gap();
    p.line("Check boxes, built by the program:");
    p.row(10);
    checkBox(p, CHECK, st.checks[0]);
    p.label("Sound");
    checkBox(p, CHECK + 1, st.checks[1]);
    p.label("Borders");
    p.endRow();
    p.missing("check boxes (SELECTABLE)");
    p.gap();
    lower(p, st);
}

fn lower(p: *Pen, st: *const State) void {
    p.line("Editable field, digits only, built by the program:");
    p.row(12);
    p.label("Date:");
    field(p, st);
    p.endRow();
    p.missing("editable text (G_FTEXT, form_do)");
    p.gap();
    p.line("Boxes and frames (guiBox, insets 1 2 3):");
    p.row(22);
    for (1..4) |k| p.box(p.cw * 9, @intCast(k), "inset");
    p.endRow();
    p.missing("the 3D look of TOS 4 objects");
    p.gap();
    p.line("Slider 0..10, built by the program:");
    p.row(10);
    for (0..11) |k| {
        if (p.own(SLIDER + @as(u8, @intCast(k)), p.cw)) |r| {
            p.g.frame(r, rom.BLACK);
            if (k == st.slider) p.g.rect(r, rom.BLACK);
        }
        p.x -= p.cw + 1; // the stops share a side: one track
    }
    var b: [8]u8 = undefined;
    p.x += p.cw;
    p.label(std.fmt.bufPrint(&b, "{d}", .{st.slider}) catch "");
    p.endRow();
    p.missing("a slider object");
    p.missing("popup menus (menu_popup)");
}

fn checkBox(p: *Pen, id: u8, on: bool) void {
    const r = p.own(id, 10) orelse return;
    p.g.frame(r, rom.BLACK);
    if (on) p.g.rect(.{ .x = r.x + 2, .y = r.y + 2, .w = r.w - 4, .h = r.h - 4 }, rom.BLACK);
}

// "__/__/__" with the digits typed so far, and the caret when the field has the focus.
fn field(p: *Pen, st: *const State) void {
    const r = p.own(FIELD, p.cw * 10) orelse return;
    p.g.frame(r, rom.BLACK);
    var t = "__/__/__".*;
    for (st.digits[0..st.ndigits], 0..) |d, i| t[i + i / 2] = d;
    p.g.text(&t, r.x + @as(i16, @intCast(p.cw)), r.y + 2, rom.BLACK, rom.WHITE);
    if (!st.focus) return;
    const at: i16 = @intCast(st.ndigits + st.ndigits / 2 + 1);
    p.g.fill(r.x + at * @as(i16, @intCast(p.cw)), r.y + 1, 2, @intCast(r.h - 2), rom.BLACK);
}

pub fn press(app: *App, id: u8) void {
    const st = &app.dlg;
    st.focus = id == FIELD;
    switch (id) {
        OK, CANCEL, PLAIN => st.last = id,
        RADIO...RADIO + 2 => st.radio = id - RADIO,
        CHECK, CHECK + 1 => st.checks[id - CHECK] = !st.checks[id - CHECK],
        SLIDER...SLIDER + 10 => st.slider = id - SLIDER,
        else => {},
    }
    repaint(app);
}

/// Keys while the Dialogs window is on top: Return fires the default button (OK); with the field
/// focused, digits type (8 rubs out).
pub fn key(app: *App, cp: u32) bool {
    const st = &app.dlg;
    if (cp == 13) {
        st.last = OK;
    } else if (!st.focus) {
        return false;
    } else if (cp == 8) {
        st.ndigits -|= 1;
    } else if (cp >= '0' and cp <= '9' and st.ndigits < st.digits.len) {
        st.digits[st.ndigits] = @intCast(cp);
        st.ndigits += 1;
    } else return false;
    repaint(app);
    return true;
}

fn repaint(app: *App) void {
    if (app.wins.topSlot()) |t| wins.paintContent(app, t);
}
