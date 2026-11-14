// The Wi-Fi page driven like a user would (app_wifi.zig over the fake tools, wifi_fake.zig):
// console > Wi-Fi..., Scan, pick, type the password, join; wifi.conf on the card after, and only
// after, a join that worked; Forget; a read-only card; the page's text.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const wc = @import("wifi_conf.zig");
const app_wifi = @import("app_wifi.zig");
const App = @import("app.zig").App;
const Rig = @import("test_rig.zig").Rig;
const Fake = @import("wifi_fake.zig").Fake;

const io = std.testing.io;

fn key(a: *App, code: u32) void {
    a.keyEvent(code | map.KEY_DOWN);
}

/// Wait for the job the last key started, then let tick() show its result.
fn settle(a: *App) void {
    while (a.wifi.busy()) {
        app_wifi.tick(a);
        std.Thread.yield() catch {};
    }
}

fn screen(a: *App) []const u8 {
    const S = struct {
        var text: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    };
    a.redraw();
    a.osd.dump(&S.text);
    return &S.text;
}

fn has(s: []const u8, part: []const u8) bool {
    return std.mem.indexOf(u8, s, part) != null;
}

/// The Wi-Fi page, opened from the shelf as a user would.
fn openPage(a: *App, f: *Fake) void {
    a.wifi.env = f.env();
    key(a, map.KEY_ARROW_RIGHT); // console
    for (0..6) |_| key(a, map.KEY_ARROW_DOWN); // Wi-Fi...
    key(a, map.KEY_ENTER);
    settle(a);
}

fn savedConf(r: *Rig, buf: []u8) ?[]const u8 {
    return r.tmp.dir.readFile(io, wc.FILE, buf) catch null;
}

test "scan, pick a secured network, type its password, join: saved to wifi.conf, hashed" {
    const r = try Rig.init();
    defer r.deinit();
    const f = try Fake.init("bin");
    defer f.deinit();
    var a = try r.app();
    defer a.deinit();
    openPage(&a, f);
    try std.testing.expect(has(screen(&a), "Status  not connected") and has(screen(&a), "Saved   none"));
    key(&a, map.KEY_ENTER); // Scan networks...
    settle(&a);
    const list = screen(&a);
    try std.testing.expect(has(list, "*#### Metaverse") and has(list, " ##    Cafe Libre "));
    key(&a, map.KEY_ENTER); // Metaverse: secured, so the password
    for ("pass word!") |c| key(&a, c);
    key(&a, map.KEY_BACKSPACE);
    try std.testing.expect(has(screen(&a), "*********_") and !has(screen(&a), "pass word"));
    key(&a, '!');
    f.link_out = "Connected to 11:22:33:44:55:77 (on wlan0)\n\tSSID: Metaverse\n";
    key(&a, map.KEY_ENTER);
    try std.testing.expectEqual(@as(u8, 0), a.menu.wifi.pass_len); // handed to the job, wiped here
    settle(&a);
    const home = screen(&a);
    try std.testing.expect(has(home, "Network Metaverse") and has(home, "Address 192.168.0.16") and has(home, "Saved   Metaverse"));
    try std.testing.expect(has(home, "joined, saved to wifi.conf"));
    var buf: [512]u8 = undefined;
    const conf = savedConf(r, &buf) orelse return error.TestUnexpectedResult;
    var pass = "pass word!".*;
    const want = try wc.psk("Metaverse", &pass);
    try std.testing.expect(has(conf, "ssid=\"Metaverse\"\n\tpsk=" ++ want) and !has(conf, "pass word"));
}

test "a wrong password saves nothing and asks again; Esc on the password goes back to the list" {
    const r = try Rig.init();
    defer r.deinit();
    const f = try Fake.init("bin");
    defer f.deinit();
    var a = try r.app();
    defer a.deinit();
    openPage(&a, f);
    key(&a, map.KEY_ENTER);
    settle(&a);
    key(&a, map.KEY_ENTER);
    for ("short") |c| key(&a, c);
    key(&a, map.KEY_ENTER); // 5 characters: refused on the page, no job
    try std.testing.expect(!a.wifi.busy() and has(screen(&a), "8 to 63 characters"));
    for ("long enough") |c| key(&a, c);
    f.log = "wlan0: CTRL-EVENT-SSID-TEMP-DISABLED id=0 reason=WRONG_KEY\n";
    key(&a, map.KEY_ENTER);
    settle(&a);
    try std.testing.expectEqual(@import("page_wifi.zig").Screen.password, a.menu.wifi.screen);
    try std.testing.expect(has(screen(&a), "wrong password"));
    var buf: [512]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), savedConf(r, &buf));
    key(&a, map.KEY_ESCAPE);
    try std.testing.expectEqual(@import("page_wifi.zig").Screen.list, a.menu.wifi.screen);
}

fn readOnly(_: bool) bool {
    return false;
}

test "a read-only card: joined but not saved, and Forget says it could not" {
    const r = try Rig.init();
    defer r.deinit();
    const f = try Fake.init("bin");
    defer f.deinit();
    var a = try r.app();
    defer a.deinit();
    a.sd_writable = readOnly;
    openPage(&a, f);
    key(&a, map.KEY_ENTER);
    settle(&a);
    key(&a, map.KEY_ARROW_DOWN); // Cafe Libre: open, joins at once
    key(&a, map.KEY_ENTER);
    settle(&a);
    try std.testing.expect(has(screen(&a), "joined; not saved: card read-on"));
    key(&a, map.KEY_ARROW_DOWN); // Forget saved network
    key(&a, map.KEY_ENTER);
    try std.testing.expect(has(screen(&a), "not forgotten: card read-only") and !a.wifi.busy());
}

test "Forget removes wifi.conf and leaves the network; no tools or no dongle is said on the page" {
    const r = try Rig.init();
    defer r.deinit();
    const f = try Fake.init("bin");
    defer f.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = wc.FILE, .data = "network={\n\tssid=\"Home Net\"\n\tpsk=00\n}\n" });
    var a = try r.app();
    defer a.deinit();
    openPage(&a, f);
    try std.testing.expect(has(screen(&a), "Saved   Home Net"));
    key(&a, map.KEY_ARROW_DOWN);
    key(&a, map.KEY_ENTER);
    settle(&a);
    var buf: [512]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), savedConf(r, &buf));
    try std.testing.expect(has(screen(&a), "Saved   none") and f.find("killall|-q|wpa_supplicant") != null);
    const bare = try Fake.init("");
    defer bare.deinit();
    a.wifi.env = bare.env();
    app_wifi.deinit(&a); // the next job builds its worker on the new tools
    key(&a, map.KEY_ESCAPE);
    key(&a, map.KEY_ENTER); // Wi-Fi... again
    settle(&a);
    try std.testing.expect(has(screen(&a), "Wi-Fi tools not found: iw"));
}
