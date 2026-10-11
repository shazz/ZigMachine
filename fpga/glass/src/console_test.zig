// The console page driven like a user would (app_cart.zig): cold and warm
// reset, what each keeps, how each fails; the volume reaching AUDIO_VOL and
// glass.cfg; the debug page's live numbers.
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const keymap = @import("keymap.zig");
const pad = @import("pad.zig");
const osd = @import("osd.zig");
const config = @import("config.zig");
const test_rig = @import("test_rig.zig");
const Rig = test_rig.Rig;
const press = test_rig.press;

const io = std.testing.io;
const KEY_R = 19; // evdev
const KEY_W = 17;

fn has(s: []const u8, part: []const u8) bool {
    return std.mem.indexOf(u8, s, part) != null;
}

test "cold reset reloads the cart from the card and clears its memory" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    try std.testing.expect(has(a.menu.status.?, "no shelf.txt")); // said once, at start
    press(&a, keymap.KEY_ENTER);
    r.words[100] = 0xC0FFEE; // the cart wrote its memory
    press(&a, keymap.OSD_HOTKEY);
    press(&a, KEY_R);
    try std.testing.expectEqual(@as(u32, 0), r.words[100]);
    try std.testing.expectEqual(@as(?usize, null), try r.loaded());
    try std.testing.expectEqual(@as(u32, 2), a.stats.loads);
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0 and r.glass.ctrl & map.CTRL_OSD == 0);
}

test "warm reset restarts the cart over its memory" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    r.words[100] = 0xC0FFEE;
    press(&a, keymap.OSD_HOTKEY);
    press(&a, KEY_W);
    try std.testing.expectEqual(@as(u32, 0xC0FFEE), r.words[100]);
    try std.testing.expectEqual(@as(u32, 1), r.glass.warm_boots);
    try std.testing.expectEqual(map.CTRL_RUN, r.glass.ctrl); // OSD closed, WARM dropped
    try std.testing.expectEqual(@as(u32, 1), a.stats.loads); // not a load
}

test "a warm reset with no memory to keep says so, holds the CPU, and R recovers" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    r.glass.marked = false; // the cold boot never marked its memory
    press(&a, keymap.OSD_HOTKEY);
    press(&a, KEY_W);
    try std.testing.expect(has(a.menu.status.?, "memory lost"));
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0 and r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expectEqual(@as(?u32, map.TRAP_WARM_LOST), a.stats.last_trap);
    press(&a, KEY_R);
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0);
}

test "a reset with no cart, or with its disk gone from the card, says so" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, KEY_R);
    try std.testing.expect(has(a.menu.status.?, "no cart to reset"));
    press(&a, KEY_W);
    try std.testing.expect(has(a.menu.status.?, "no cart to reset"));
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0);
    press(&a, keymap.KEY_ENTER);
    try r.tmp.dir.deleteFile(io, "a.zmd");
    press(&a, keymap.OSD_HOTKEY);
    press(&a, KEY_R);
    try std.testing.expect(has(a.menu.status.?, "FileNotFound"));
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0); // refused before the CPU: the cart runs on
}

test "the volume reaches AUDIO_VOL at once, glass.cfg on leaving, and comes back at start" {
    const r = try Rig.init();
    defer r.deinit();
    {
        var a = try r.app();
        defer a.deinit();
        try std.testing.expectEqual(map.AUDIO_VOL_RESET, r.glass.audio_vol);
        press(&a, keymap.KEY_RIGHT); // the console page
        press(&a, keymap.KEY_DOWN);
        press(&a, keymap.KEY_DOWN); // Volume
        press(&a, keymap.KEY_LEFT);
        try std.testing.expectEqual(@as(u32, 239), r.glass.audio_vol);
        press(&a, keymap.KEY_ESC); // back to the shelf: saved
        try std.testing.expect(has(a.menu.status.?, "settings saved"));
    }
    r.glass.audio_vol = map.AUDIO_VOL_RESET; // a power cycle
    var b = try r.app();
    defer b.deinit();
    try std.testing.expectEqual(@as(u32, 239), r.glass.audio_vol);
    try std.testing.expectEqual(@as(u8, 239), b.menu.settings.volume);
}

fn readOnly(_: bool) bool {
    return false;
}

test "a bad glass.cfg is reported and a save the card refuses keeps the change pending" {
    const r = try Rig.init();
    defer r.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = config.FILE, .data = "volume=loud\nmute=1\n" });
    var a = try r.app();
    defer a.deinit();
    try std.testing.expect(has(a.menu.status.?, "bad line 1"));
    try std.testing.expectEqual(map.AUDIO_MUTE | map.AUDIO_VOL_RESET, r.glass.audio_vol); // mute=1 still applied
    a.sd_writable = readOnly;
    press(&a, keymap.KEY_RIGHT);
    for (0..3) |_| press(&a, keymap.KEY_DOWN); // Mute
    press(&a, keymap.KEY_ENTER);
    press(&a, keymap.KEY_ESC);
    try std.testing.expect(has(a.menu.status.?, "card read-only"));
    try std.testing.expect(a.settings_dirty);
    try std.testing.expectEqual(map.AUDIO_VOL_RESET, r.glass.audio_vol); // unmuted all the same
}

test "the debug page shows the live cart, the pad, and n/a for a board Linux lacks" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    a.sys_root = r.dir; // no /proc or /sys there
    press(&a, keymap.KEY_ENTER);
    a.padEvent(pad.EV_KEY, pad.BTN_SOUTH, 1, .{}, .{}, "8BitDo Pro 2");
    press(&a, keymap.OSD_HOTKEY);
    press(&a, keymap.KEY_RIGHT);
    for (0..4) |_| press(&a, keymap.KEY_DOWN);
    press(&a, keymap.KEY_ENTER);
    for (0..5) |_| a.tick(); // the page redraws itself while open
    var dump: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    a.osd.dump(&dump);
    for ([_][]const u8{ "glass 0.2.0", "PL    ZMGL 1.4.0", "fw    0.1.0", "cart  RUNNING", "loads 1", "pad   8BitDo Pro 2", "cpu   n/a", "mem   n/a" }) |want| {
        if (!has(&dump, want)) {
            std.debug.print("missing \"{s}\" in:\n{s}", .{ want, dump });
            return error.TestExpectedEqual;
        }
    }
}
