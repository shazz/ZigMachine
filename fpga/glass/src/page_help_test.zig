// The help page's table replayed against the real key handling (page_help.zig): every key it
// lists must do something on the page its group names, so the help cannot drift from the code.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const pad = @import("pad.zig");
const shelf = @import("shelf.zig");
const zmd = @import("zmd.zig");
const keymap = @import("keymap.zig");
const menu = @import("menu.zig");
const help = @import("page_help.zig");
const drive = @import("app_drive.zig");
const App = @import("app.zig").App;
const test_rig = @import("test_rig.zig");
const press = test_rig.press;

/// Everything a menu key can change, to tell "handled" from "ignored".
const Seen = struct { action: std.meta.Tag(menu.Action), page: menu.Page, cursor: usize, top: usize, item: usize, volume: u8, mute: bool, help_top: usize };

fn seen(m: *const menu.Menu, a: menu.Action) Seen {
    return .{ .action = a, .page = m.page, .cursor = m.list.cursor, .top = m.list.top, .item = m.console.cursor, .volume = m.settings.volume, .mute = m.settings.mute, .help_top = m.help_top };
}

/// The menu on `page` in a few starting states (a cursor mid-list, the volume mid-way), so a
/// key that only acts on some item still shows; true if `code` changed anything in any of them.
fn handled(page: menu.Page, code: u32, disks: []const shelf.Disk) bool {
    for ([_]usize{ 0, 2 }) |item| {
        var m = menu.Menu{ .disks = disks, .page = page, .help_top = 3 };
        m.list = .{ .cursor = 5, .top = 2 };
        m.console.cursor = item;
        m.settings.volume = 128;
        const before = seen(&m, .none);
        const a = m.key(code | map.KEY_DOWN);
        if (!std.meta.eql(before, seen(&m, a))) return true;
    }
    return false;
}

fn pageOf(g: help.Group) menu.Page {
    return switch (g) {
        .global => unreachable, // global keys are App.key's, checked on an App
        .shelf => .shelf,
        .console => .console,
        .debug => .debug,
        .help => .help,
        .budget => .budget,
    };
}

test "every menu key the help lists is handled by the page it names" {
    var disks: [20]shelf.Disk = undefined;
    for (&disks) |*d| d.* = .{ .file = "x.zmd", .title = "x" };
    for (help.table) |e| switch (e.check) {
        .menu => |codes| for (codes) |code| {
            if (!handled(pageOf(e.group), code, &disks)) {
                std.debug.print("help: {s} ({X}) does nothing on the {t} page\n", .{ e.keys, code, e.group });
                return error.TestUnexpectedResult;
            }
        },
        else => {},
    };
}

test "every global key, pad bit and Shift-at-reset the help lists does what it says" {
    const r = try test_rig.Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    for (help.table) |e| switch (e.check) {
        .menu => {},
        .evdev => |k| try expectHotkey(r, &a, k.code, k.shift),
        .pad => |bit| try expectPad(&a, bit),
        .shift_reset => {
            const with_post = drive.flags(&a, false);
            a.mods.shift_l = true;
            defer a.mods.shift_l = false;
            try std.testing.expect(drive.flags(&a, false) != with_post);
        },
    };
}

fn expectHotkey(r: *test_rig.Rig, a: *App, code: u16, shift: bool) !void {
    a.menu.page = .shelf;
    if (shift) a.key(keymap.KEY_LEFTSHIFT, 1);
    defer if (shift) a.key(keymap.KEY_LEFTSHIFT, 0);
    if (code == keymap.OSD_HOTKEY and shift) { // the shelf read again: a new disk shows
        const disk = try zmd.testDisk(std.testing.allocator, "New Disk", &.{});
        defer std.testing.allocator.free(disk);
        try r.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "c.zmd", .data = disk });
        const n = a.disks.disks.len;
        press(a, code);
        return std.testing.expectEqual(n + 1, a.disks.disks.len);
    }
    if (code == keymap.OSD_HOTKEY) {
        const open = a.open;
        press(a, code);
        return std.testing.expect(a.open != open);
    }
    if (shift) { // Shift+F11: the budget page
        press(a, code);
        return std.testing.expectEqual(menu.Page.budget, a.menu.page);
    }
    if (a.open) press(a, keymap.OSD_HOTKEY); // F11 acts with the menu closed
    const fps = a.menu.settings.fps;
    press(a, code);
    try std.testing.expect(a.menu.settings.fps != fps or !a.pl_stats);
}

fn expectPad(a: *App, bit: u32) !void {
    if (!a.open) press(a, keymap.OSD_HOTKEY);
    a.menu.page = .console;
    a.menu.console.cursor = 4; // Debug...: fire opens the debug page, Down moves to Back
    const ev: [2]u16 = switch (bit) {
        map.JOY_DOWN => .{ pad.EV_ABS, pad.ABS_HAT0Y },
        map.JOY_FIRE => .{ pad.EV_KEY, pad.BTN_SOUTH },
        else => return error.TestUnexpectedResult, // a pad bit this test cannot send
    };
    a.padEvent(ev[0], ev[1], 1, .{}, .{}, "pad");
    a.padEvent(ev[0], ev[1], 0, .{}, .{}, "pad");
    try std.testing.expect(a.menu.page != .console or a.menu.console.cursor != 4);
}

test "the help page fits the strip's layout and scrolls within its lines" {
    try std.testing.expect(help.lines.len > help.SHOWN); // it does not fit: it scrolls
    var m = menu.Menu{ .disks = &.{}, .page = .help };
    for (0..help.lines.len + 3) |_| _ = m.key(map.KEY_ARROW_DOWN | map.KEY_DOWN);
    try std.testing.expectEqual(help.MAX_TOP, m.help_top); // stops on the last screenful
    _ = m.key(map.KEY_PAGE_UP | map.KEY_DOWN);
    try std.testing.expectEqual(help.MAX_TOP - help.SHOWN, m.help_top);
    m.help_top = 0;
    var o = osd.Osd{};
    m.draw(&o, &.{}, &.{});
    var dump: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    o.dump(&dump);
    try std.testing.expect(std.mem.indexOf(u8, &dump, "\n  GLOBAL ---") != null); // strip, gap, heading
    try std.testing.expect(std.mem.indexOf(u8, &dump, "\nH F12        open/close the OSD") != null);
    try std.testing.expect(std.mem.indexOf(u8, &dump, " ZIGMACHINE  HELP   1-14/32  >") != null);
    try std.testing.expectEqual(menu.Action.none, m.key(map.KEY_ARROW_RIGHT | map.KEY_DOWN));
    try std.testing.expectEqual(menu.Page.budget, m.page);
}
