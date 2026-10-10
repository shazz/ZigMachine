// The F11 frame-rate overlay driven like a user would (app_stats.zig): the
// toggle, the menu taking the window back, the text, glass.cfg, an older PL.
const std = @import("std");
const map = @import("map.zig");
const keymap = @import("keymap.zig");
const config = @import("config.zig");
const overlay = @import("app_stats.zig");
const App = @import("app.zig").App;
const test_rig = @import("test_rig.zig");
const Rig = test_rig.Rig;
const press = test_rig.press;

const OVERLAY = map.CTRL_OSD | map.CTRL_OSD_STATS;
var now_ms: i64 = 0;

fn clock() i64 {
    return now_ms;
}

/// A rig with a.zmd loaded and running, the menu closed.
fn running(r: *Rig) !App {
    var a = try r.app();
    a.clock = clock;
    press(&a, keymap.KEY_ENTER);
    try std.testing.expectEqual(@as(?usize, 0), a.current);
    return a;
}

fn row(r: *const Rig, n: usize) [map.OSD_COLS]u8 {
    var out: [map.OSD_COLS]u8 = undefined;
    for (&out, r.glass.text[n * map.OSD_COLS ..][0..map.OSD_COLS]) |*c, w| c.* = @truncate(w);
    return out;
}

fn expectRow0(r: *const Rig, want: []const u8) !void {
    const got = row(r, 0);
    try std.testing.expectEqualStrings(want, got[0..want.len]);
    for (got[want.len..]) |c| try std.testing.expectEqual(@as(u8, ' '), c);
}

test "F11 shows the frame rate in the corner over a running cart, and F11 again hides it" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    try std.testing.expect(r.glass.ctrl & OVERLAY == 0);
    const keys = r.glass.key_len;
    press(&a, keymap.STATS_HOTKEY);
    try std.testing.expectEqual(OVERLAY, r.glass.ctrl & OVERLAY);
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0); // the cart keeps running
    try std.testing.expectEqual(overlay.CORNER, r.glass.osd_pos);
    try expectRow0(r, "FPS --.-"); // no whole second measured yet
    for (1..map.OSD_ROWS) |n| try std.testing.expectEqualStrings(&([_]u8{' '} ** map.OSD_COLS), &row(r, n));
    for (r.glass.text) |w| try std.testing.expect(w & map.OSD_INVERSE == 0); // nothing opaque but the text
    try std.testing.expectEqual(keys, r.glass.key_len); // F11 never reaches the cart
    now_ms = 1000;
    a.tick(); // the first sample starts a window
    r.glass.cart_beat += 381; // the tick's own poll counts one more frame: 382 in 10 s
    now_ms = 11_000;
    a.tick();
    try expectRow0(r, "FPS 38.2");
    press(&a, keymap.STATS_HOTKEY);
    try std.testing.expect(r.glass.ctrl & OVERLAY == 0);
    try std.testing.expectEqual(map.OSD_POS_RESET, r.glass.osd_pos);
}

test "the menu takes the window back centred and opaque, and gives the overlay back on close" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try running(r);
    defer a.deinit();
    press(&a, keymap.STATS_HOTKEY);
    press(&a, keymap.OSD_HOTKEY); // F12: the menu
    try std.testing.expectEqual(map.CTRL_OSD, r.glass.ctrl & OVERLAY);
    try std.testing.expectEqual(map.OSD_POS_RESET, r.glass.osd_pos);
    try std.testing.expectEqual(@as(u32, map.OSD_INVERSE | ' '), r.glass.text[0]); // the title bar
    press(&a, keymap.STATS_HOTKEY); // F11 in the menu: nothing
    try std.testing.expect(a.menu.settings.fps);
    try std.testing.expectEqual(map.CTRL_OSD, r.glass.ctrl & OVERLAY);
    a.tick(); // the overlay does not draw over the menu
    try std.testing.expectEqual(@as(u32, map.OSD_INVERSE | ' '), r.glass.text[0]);
    press(&a, keymap.OSD_HOTKEY); // closed again: the overlay is back
    try std.testing.expectEqual(OVERLAY, r.glass.ctrl & OVERLAY);
    try std.testing.expectEqual(overlay.CORNER, r.glass.osd_pos);
    try expectRow0(r, "FPS --.-");
}

test "the overlay is a glass.cfg setting: the next start brings it back" {
    const r = try Rig.init();
    defer r.deinit();
    {
        var a = try running(r);
        defer a.deinit();
        press(&a, keymap.STATS_HOTKEY);
    }
    try std.testing.expect(config.load(std.testing.io, r.dir).settings.fps);
    r.glass.ctrl = 0; // a fresh PL: nothing left over from the first run
    r.glass.osd_pos = map.OSD_POS_RESET;
    var b = try running(r);
    defer b.deinit();
    try std.testing.expectEqual(OVERLAY, r.glass.ctrl & OVERLAY);
    try expectRow0(r, "FPS --.-");
}

test "a PL before 1.4.0 has no overlay: F11 does nothing, and nothing else changes" {
    const r = try Rig.init();
    defer r.deinit();
    r.glass.version = 0x0001_0300;
    // The card was last used with a newer bitstream, overlay on.
    try r.tmp.dir.writeFile(std.testing.io, .{ .sub_path = config.FILE, .data = "fps=1\n" });
    var a = try running(r);
    defer a.deinit();
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0); // no blank window mid-screen
    press(&a, keymap.STATS_HOTKEY);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0);
    try std.testing.expect(a.menu.settings.fps); // kept for the next newer PL
    try std.testing.expectEqual(@as(u32, 0), r.glass.osd_pos_writes);
    press(&a, keymap.OSD_HOTKEY);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0); // the menu as ever
    try std.testing.expectEqual(@as(u32, 0), r.glass.osd_pos_writes);
}

test "the overlay's text" {
    var buf: [overlay.TEXT_MAX]u8 = undefined;
    try std.testing.expectEqualStrings("FPS --.-", overlay.text(null, &buf));
    try std.testing.expectEqualStrings("FPS 0.0", overlay.text(0, &buf));
    try std.testing.expectEqualStrings("FPS 50.0", overlay.text(500, &buf));
    try std.testing.expectEqualStrings("FPS 38.2", overlay.text(382, &buf));
    try std.testing.expectEqualStrings("FPS 9999.0", overlay.text(1_000_000, &buf)); // clamped, never clipped
}
