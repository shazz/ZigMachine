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
    aes.fileSelDrivesSet(a.fsel, files.drives()); // the DRIVE: buttons (G21)
    a.fsel.show(lastSpec(a));
    fill(a, lastSpec(a));
    aes.fileSelName(a.fsel, if (m == .fsel_save) a.name[0..a.name_len] else "");
    a.modal = m;
}

// The selector's list for `s`: its folders, then its files (files.list).
fn fill(a: *App, s: []const u8) void {
    var names: [files.MAX_LIST][13]u8 = undefined;
    var lens: [files.MAX_LIST]u8 = undefined;
    const n = files.list(s, &names, &lens);
    for (0..n) |i| a.fsel.add(names[i][0..lens[i]]);
}

/// The ITEM SELECTOR moved to another folder or mask (`relist`): its list, read again.
pub fn relist(a: *App) void {
    var buf: [files.MAX_SPEC]u8 = undefined;
    fill(a, aes.fileSelSpecOf(a.fsel, &buf));
}

/// The last accepted path spec (the folder the name lives in, the mask the selector reopens with).
fn lastSpec(a: *const App) []const u8 {
    return if (a.spec_len == 0) files.MASK else a.spec[0..a.spec_len];
}

// The selector's spec kept as the file's folder (an OK); a spec without a folder keeps the old.
fn accept(a: *App) void {
    var buf: [files.MAX_SPEC]u8 = undefined;
    const s = aes.fileSelSpecOf(a.fsel, &buf);
    if (files.dirOf(s).len == 0) return;
    @memcpy(a.spec[0..s.len], s);
    a.spec_len = @intCast(s.len);
}

// The current name in its folder.
fn filePath(a: *const App, buf: []u8) []const u8 {
    return files.path(files.dirOf(lastSpec(a)), a.name[0..a.name_len], buf);
}

/// Save to the current name: false (and an alert) on a failure.
fn write(a: *App) bool {
    var pbuf: [files.MAX_SPEC + 16]u8 = undefined;
    const fail = files.save(filePath(a, &pbuf), a.io, &a.doc.text) orelse {
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
    accept(a);
    @memcpy(a.name[0..name.len], name);
    a.name_len = @intCast(name.len);
    return true;
}

fn open(a: *App) void {
    if (!chosen(a)) return;
    var pbuf: [files.MAX_SPEC + 16]u8 = undefined;
    if (files.load(filePath(a, &pbuf), a.io, &a.doc.text)) |f| {
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
