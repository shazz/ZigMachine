// --------------------------------------------------------------------------
// GEMTEST's commands and its two modals: a form_alert (the ROM's, its answer
// through aes.choice) and the ITEM SELECTOR, filled as a TOS program filled it
// from Fsfirst / Fsnext on the mask (KOS GEMDOS, A: and C:). One modal at a time;
// when it closes, the screen under it is repainted whole.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const aes = rom.aes;
const gemdos = @import("kos_gemdos");
const menu = @import("menu.zig");
const wins = @import("wins.zig");
const App = @import("../gemtest.zig").App;

pub const Modal = enum { none, alert, about, fsel };
pub const MASKS = [_][]const u8{ "A:\\*.*", "C:\\*.*", "C:\\*.TXT" };
pub const MAX_LIST = 32; // the ITEM SELECTOR's list (rom/gem/desktop/filesel_list.zig MAX_FILES)

pub const FileState = struct {
    mask: u8 = 0xFF,
    count: u16 = 0,
    first: i32 = 0, // Fsfirst's answer: 0 a name, -33 (EFILNF) none, else an error
    result: rom.Result = .none,
    name: [16]u8 = undefined,
    name_len: u8 = 0,
};

const ICON_NAMES = [_][]const u8{ "No icon", "Note", "Wait", "Stop" };
const BUTTONS = [_][]const u8{ "[ OK ]", "[Yes|No]", "[Yes|No|Cancel]" };
const SPECS = specs();
fn specs() [12][]const u8 {
    var out: [12][]const u8 = undefined;
    inline for (0..12) |k| {
        const icon = k / 3;
        out[k] = "[" ++ [_]u8{'0' + icon} ++ "][" ++ ICON_NAMES[icon] ++ ": form_alert icon " ++ [_]u8{'0' + icon} ++
            "|with " ++ [_]u8{'1' + k % 3} ++ " button(s), the first|is the default (Return)]" ++ BUTTONS[k % 3];
    }
    return out;
}

pub fn run(app: *App, cmd: menu.Cmd, by_key: bool) void {
    if (by_key and cmd != .none) app.shortcuts += 1;
    switch (cmd) {
        .none => {},
        .about => if (aes.formAlert(app.dialog, 1, "[1][GEMTEST 1.0|every GEM 5 component|on one disk, for the board][ OK ]")) {
            app.modal = .about;
        },
        .area => |a| app.showArea(a),
        .close_all => {
            app.wins.closeAll();
            wins.paintAll(app);
        },
        .quit => app.wants_quit = true,
        .probe => |k| probe(app, k),
        .alert => |k| alert(app, k),
        .mode => |m| app.setShadeMode(m),
    }
}

const PROBES = [_][]const u8{ "Plain item", "Checked item", "Second check", "Shortcut ^L" };
fn probe(app: *App, k: u8) void {
    app.picks += 1;
    app.last_pick = PROBES[k];
    if (k == 1) app.check1 = !app.check1;
    if (k == 2) app.check2 = !app.check2;
    app.syncMenu();
    if (app.wins.area == .menus) if (app.wins.topSlot()) |t| wins.paintContent(app, t);
}

/// form_alert number `k` (icon k / 3, k % 3 + 1 buttons); 12: a malformed string, which the ROM
/// must refuse (no alert opens).
pub fn alert(app: *App, k: u8) void {
    app.alert_last = k;
    app.alert_choice = 0;
    app.alert_ok = aes.formAlert(app.dialog, 1, if (k < 12) SPECS[k] else "[7][no such icon][OK");
    if (app.alert_ok) {
        app.modal = .alert;
    } else if (app.wins.area == .alerts) if (app.wins.topSlot()) |t| wins.paintContent(app, t);
}

/// The ITEM SELECTOR on mask `k`, its list from Fsfirst / Fsnext.
pub fn selector(app: *App, k: u8) void {
    const f = &app.fs;
    f.* = .{ .mask = k };
    app.fsel.show(MASKS[k]);
    const dos = gemdos.dos();
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    var r = dos.Fsfirst(MASKS[k], 0);
    f.first = r;
    while (r == 0 and f.count < MAX_LIST) : (r = dos.Fsnext()) {
        const len = std.mem.indexOfScalar(u8, &dta.name, 0) orelse dta.name.len;
        app.fsel.add(dta.name[0..@min(len, 13)]);
        f.count += 1;
    }
    aes.fileSelName(app.fsel, "");
    app.modal = .fsel;
}

/// The modal's answer, once it has one: recorded, then the whole screen again.
pub fn answered(app: *App, r: rom.Result) void {
    const m = app.modal;
    app.modal = .none;
    if (m == .alert) app.alert_choice = aes.choice(app.dialog);
    if (m == .fsel) {
        app.fs.result = r;
        var buf: [16]u8 = undefined;
        const name = app.fsel.chosen(&buf);
        @memcpy(app.fs.name[0..name.len], name);
        app.fs.name_len = @intCast(name.len);
    }
    app.repaint = true;
}
