// --------------------------------------------------------------------------
// GEMTEST's Menus, Alerts, File selector, Icons and Screen modes areas: what the
// menu test picked, a button per form_alert (each icon with 1, 2 and 3 buttons),
// the ITEM SELECTOR on A: and C: with what it returned, the icons the API cannot
// draw, and Getrez with the three modes.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const aes = rom.aes;
const Pen = @import("pen.zig").Pen;
const App = @import("../gemtest.zig").App;
const Area = @import("areas.zig").Area;
const flow = @import("flow.zig");

pub fn menus(p: *Pen, app: *App) void {
    var b: [48]u8 = undefined;
    p.line("The Menus title: a plain item, a disabled one,");
    p.line("separators, two checks that toggle, ^L, and");
    p.line("a disabled ^U (it must do nothing).");
    p.gap();
    p.line(fmt(&b, "Checked item: {s}", .{onOff(app.check1)}));
    p.line(fmt(&b, "Second check: {s}", .{onOff(app.check2)}));
    p.line(fmt(&b, "Last pick: {s}", .{app.lastPick()}));
    p.line(fmt(&b, "Picks: {d}, shortcuts: {d}", .{ app.picks, app.shortcuts }));
    p.gap();
    p.missing("a shortcut field (the ^key is");
    p.missing("  part of the label: menu_keys)");
    p.missing("submenus, menu_tnormal");
}

const NUMS = [_][]const u8{ "1", "2", "3" };

pub fn alerts(p: *Pen, app: *App) void {
    var b: [48]u8 = undefined;
    const names = [_][]const u8{ "None ", "Note ", "Wait ", "Stop " };
    p.line("form_alert: icon 0 none, 1 note, 2 wait, 3 stop");
    for (names, 0..) |n, icon| {
        p.row(16);
        p.label(n);
        for (NUMS, 0..) |s, k| p.button(@intCast(icon * 3 + k), s, false, 1);
        p.endRow();
    }
    p.row(16);
    p.button(12, "Malformed alert (must open nothing)", false, 1);
    p.endRow();
    const last = app.alert_last;
    if (last == 0xFF) p.line("Last: none") else if (last == 12) p.line(if (app.alert_ok) "Last: malformed: an alert OPENED (wrong)" else "Last: malformed: nothing opened (right)") else p.line(fmt(&b, "Last: icon {d}, {d} buttons: chose {d}", .{ last / 3, last % 3 + 1, app.alert_choice }));
    p.missing("custom icons; form_error");
}

pub fn files(p: *Pen, app: *App) void {
    var b: [64]u8 = undefined;
    const f = &app.fs;
    p.line("fsel_input on a mask (the names: Fsfirst/Fsnext)");
    p.row(16);
    for (flow.MASKS, 0..) |m, i| p.button(@intCast(i), m, false, 1);
    p.endRow();
    if (f.mask == 0xFF) {
        p.line("Not opened yet.");
    } else {
        p.line(fmt(&b, "Mask {s}: {d} names", .{ flow.MASKS[f.mask], f.count }));
        p.line(fmt(&b, "Fsfirst answered {d} (0 found, -33 none)", .{f.first}));
        p.line(fmt(&b, "Button: {s}", .{if (f.result == .ok) "OK" else if (f.result == .cancel) "Cancel" else "-"}));
        p.line(fmt(&b, "Name: \"{s}\"", .{f.name[0..f.name_len]}));
    }
    p.gap();
    p.missing("the path (drive and folder)");
    p.missing("  the selector edits: the program");
    p.missing("  lists the names, Directory is");
    p.missing("  only the mask (fsel_exinput)");
}

pub fn icons(p: *Pen) void {
    p.line("The desktop's icons (drives, folders,");
    p.line("files, programs, the trash) are the");
    p.line("ROM's; a program cannot draw them:");
    p.gap();
    p.missing("an icon call (G_ICON, objc_draw)");
    p.missing("the desktop's icon table");
    p.gap();
    p.line("gemtest_shots.mjs shoots the desktop in");
    p.line("each mode for them (component 'desktop').");
}

pub fn modes(p: *Pen, app: *App) void {
    var b: [48]u8 = undefined;
    const names = [_][]const u8{ "low 320x200", "medium 640x200", "desk 640x480" };
    p.line(fmt(&b, "Getrez at launch: {s}", .{if (app.boot_mode) |m| names[@intFromEnum(m)] else "no desktop ran"}));
    p.line(fmt(&b, "Now: {s}", .{names[@intFromEnum(app.mode)]}));
    p.line(fmt(&b, "Desk mode on this machine: {s}", .{yesNo(app.desk_ok)}));
    p.row(16);
    p.button(0, "Low", app.mode == .low, 1);
    p.button(1, "Medium", app.mode == .medium, 1);
    p.button(2, "Desk", app.mode == .desk, 1);
    p.endRow();
    p.line("Keys 1 2 3 and the Mode menu switch too.");
    p.missing("Setscreen for a program (it");
    p.missing("  switches its own plane)");
}

pub fn press(app: *App, a: Area, id: u8) void {
    switch (a) {
        .alerts => flow.alert(app, id),
        .files => if (id < flow.MASKS.len) flow.selector(app, id),
        .modes => if (id < 3) app.setShadeMode(id),
        else => {},
    }
}

fn onOff(b: bool) []const u8 {
    return if (b) "on" else "off";
}
fn yesNo(b: bool) []const u8 {
    return if (b) "yes" else "no";
}
fn fmt(b: []u8, comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(b, f, args) catch b[0..0];
}
