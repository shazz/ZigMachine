// --------------------------------------------------------------------------
// NOTEPAD's commands and the dialogs between them, as a TOS program sequenced
// them: New / Open / Quit on a modified text ask form_alert's "Save changes?"
// (Yes saves first, through Save As when it has no name; No goes on; Cancel
// stops), Open and Save As go through the ITEM SELECTOR, and every failed read
// or write is an alert with GEMDOS's error. One modal at a time (`App.modal`);
// `pending` is the command that runs once the save it waited for succeeded.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const aes = rom.aes;
const files = @import("files.zig");
const Cmd = @import("menu.zig").Cmd;
const App = @import("../notepad.zig").App;

pub const Modal = enum { none, info, ask_save, fsel_open, fsel_save, find };

pub fn run(a: *App, cmd: Cmd) void {
    switch (cmd) {
        .about => info(a, "[1][NOTEPAD 1.0|A GEM 5 program on KOS:|text files on C:\\, 64 KB][ OK ]"),
        .new, .open, .quit => if (a.doc.modified) ask(a, cmd) else go(a, cmd),
        .save => if (a.name_len == 0) saveAs(a, .none) else {
            _ = write(a);
        },
        .save_as => saveAs(a, .none),
        .cut => a.doc.cut(),
        .copy => a.doc.copy(),
        .paste => a.doc.paste() catch |e| full(a, e),
        .select_all => a.doc.selectAll(),
        .find => {
            a.find.open();
            a.modal = .find;
        },
        .none => {},
    }
}

/// The text hit a limit: say which (never a silent cut).
pub fn full(a: *App, e: anyerror) void {
    if (e == error.TooManyLines) info(a, "[1][The text has too many|lines (16384 at most).][ OK ]") else info(a, "[1][The text is full|(64 KB at most).][ OK ]");
}

fn info(a: *App, spec: []const u8) void {
    if (aes.formAlert(a.dialog, 1, spec)) a.modal = .info;
}

fn ask(a: *App, then: Cmd) void {
    var buf: [96]u8 = undefined;
    const spec = std.fmt.bufPrint(&buf, "[2][Save changes to|{s}?][Yes|No|Cancel]", .{a.title()}) catch return;
    if (!aes.formAlert(a.dialog, 1, spec)) return;
    a.pending = then;
    a.modal = .ask_save;
}

// The command itself, the text's fate decided.
fn go(a: *App, cmd: Cmd) void {
    a.pending = .none;
    switch (cmd) {
        .new => a.newText(),
        .open => selector(a, .fsel_open),
        .quit => a.wants_quit = true,
        else => {},
    }
}

fn saveAs(a: *App, then: Cmd) void {
    a.pending = then;
    selector(a, .fsel_save);
}

fn selector(a: *App, m: Modal) void {
    a.fsel.show(files.MASK);
    var names: [files.MAX_LIST][13]u8 = undefined;
    var lens: [files.MAX_LIST]u8 = undefined;
    const n = files.list(&names, &lens);
    for (0..n) |i| a.fsel.add(names[i][0..lens[i]]);
    aes.fileSelName(a.fsel, if (m == .fsel_save) a.name[0..a.name_len] else "");
    a.modal = m;
}

/// Save to the current name: false (and an alert) on a failure.
fn write(a: *App) bool {
    var pbuf: [24]u8 = undefined;
    const fail = files.save(files.path(a.name[0..a.name_len], &pbuf), a.io, &a.doc.text) orelse {
        a.doc.modified = false;
        return true;
    };
    failed(a, "Cannot save", fail);
    return false;
}

fn failed(a: *App, what: []const u8, f: files.Fail) void {
    var buf: [96]u8 = undefined;
    const spec = switch (f) {
        .dos => |code| std.fmt.bufPrint(&buf, "[3][{s}|{s}|(GEMDOS error {d})][ OK ]", .{ what, a.title(), code }),
        .too_big => std.fmt.bufPrint(&buf, "[3][{s}|{s}:|longer than 64 KB][ OK ]", .{ what, a.title() }),
        .too_many_lines => std.fmt.bufPrint(&buf, "[3][{s}|{s}:|more than 16384 lines][ OK ]", .{ what, a.title() }),
    } catch return;
    a.modal = .none;
    info(a, spec);
}

/// The modal's answer this frame, once it has one.
pub fn answered(a: *App, m: Modal, r: rom.Result) void {
    a.modal = .none;
    switch (m) {
        .ask_save => switch (aes.choice(a.dialog)) {
            1 => if (a.name_len == 0) saveAs(a, a.pending) else if (write(a)) go(a, a.pending),
            2 => go(a, a.pending),
            else => a.pending = .none,
        },
        .fsel_open => if (r == .ok) open(a),
        .fsel_save => if (r == .ok) saved(a) else {
            a.pending = .none;
        },
        else => {},
    }
}

fn chosen(a: *App) bool {
    var typed: [16]u8 = undefined;
    var nb: [13]u8 = undefined;
    const name = files.txtName(a.fsel.chosen(&typed), &nb);
    if (name.len == 0) return false;
    @memcpy(a.name[0..name.len], name);
    a.name_len = @intCast(name.len);
    return true;
}

fn open(a: *App) void {
    if (!chosen(a)) return;
    var pbuf: [24]u8 = undefined;
    if (files.load(files.path(a.name[0..a.name_len], &pbuf), a.io, &a.doc.text)) |f| {
        failed(a, "Cannot read", f); // names the file, then the half-read text goes
        a.newText();
        return;
    }
    a.doc.reset();
    a.view.top = 0;
    a.view.left = 0;
}

fn saved(a: *App) void {
    if (!chosen(a)) return;
    const then = a.pending;
    if (write(a)) go(a, then);
}
