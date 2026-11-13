// The Wi-Fi page's state machine and drawing (page_wifi.zig, page_wifi_draw.zig), without jobs:
// which key does what on each screen, the list's scrolling, the password's masking and limits,
// an SSID the OSD cannot show.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const wc = @import("wifi_conf.zig");
const wp = @import("wifi_parse.zig");
const pw = @import("page_wifi.zig");
const draw = @import("page_wifi_draw.zig");

fn net(ssid: []const u8, dbm: i16, secured: bool) wp.Net {
    return .{ .ssid = wc.Ssid.of(ssid).?, .dbm = dbm, .secured = secured };
}

fn listed(n: usize) pw.State {
    var s = pw.State{ .screen = .list, .n_nets = n };
    for (0..n) |i| s.nets[i] = net("net", -50, i % 2 == 0);
    return s;
}

fn dump(s: *const pw.State) []const u8 {
    const S = struct {
        var text: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    };
    var o = osd.Osd{};
    draw.draw(s, &o);
    o.dump(&S.text);
    return &S.text;
}

fn has(s: []const u8, part: []const u8) bool {
    return std.mem.indexOf(u8, s, part) != null;
}

test "home: Up/Down pick an item, Enter does it, Esc/Left/Backspace leave" {
    var s = pw.State{};
    try std.testing.expectEqual(pw.Key.scan, s.key(map.KEY_ENTER));
    s.cursor = 0;
    try std.testing.expectEqual(pw.Key.none, s.key(map.KEY_ARROW_UP));
    _ = s.key(map.KEY_ARROW_DOWN);
    try std.testing.expectEqual(pw.Key.forget, s.key(' '));
    for (0..5) |_| _ = s.key(map.KEY_ARROW_DOWN);
    try std.testing.expectEqual(pw.Key.back, s.key(map.KEY_ENTER)); // the last item: Back
    for ([_]u32{ map.KEY_ESCAPE, map.KEY_ARROW_LEFT, map.KEY_BACKSPACE }) |k| try std.testing.expectEqual(pw.Key.back, s.key(k));
}

test "list: the cursor scrolls the networks, Enter asks a secured one's password, joins an open one" {
    var s = listed(20);
    for (0..pw.SHOWN) |_| _ = s.key(map.KEY_ARROW_DOWN);
    try std.testing.expectEqual(@as(usize, pw.SHOWN), s.pick);
    try std.testing.expectEqual(@as(usize, 1), s.top);
    _ = s.key(map.KEY_PAGE_DOWN);
    try std.testing.expectEqual(@as(usize, 19), s.pick); // the last, not past it
    _ = s.key(map.KEY_PAGE_UP);
    _ = s.key(map.KEY_PAGE_UP);
    try std.testing.expectEqual(@as(usize, 0), s.pick);
    try std.testing.expectEqual(@as(usize, 0), s.top);
    _ = s.key(map.KEY_ARROW_DOWN); // net 1: open
    try std.testing.expectEqual(pw.Key.join, s.key(map.KEY_ENTER));
    _ = s.key(map.KEY_ARROW_UP); // net 0: secured
    try std.testing.expectEqual(pw.Key.none, s.key(map.KEY_ENTER));
    try std.testing.expectEqual(pw.Screen.password, s.screen);
    var three = listed(3);
    try std.testing.expectEqual(pw.Key.scan, three.key('r'));
    var empty = listed(0);
    try std.testing.expectEqual(pw.Key.none, empty.key(map.KEY_ENTER));
    try std.testing.expect(has(dump(&empty), "No networks found"));
    _ = empty.key(map.KEY_ESCAPE);
    try std.testing.expectEqual(pw.Screen.home, empty.screen);
}

test "password: every printable key types, shown masked; 8..63 to join; Esc wipes it" {
    var s = listed(1);
    _ = s.key(map.KEY_ENTER);
    for ("rR fFeE") |c| try std.testing.expectEqual(pw.Key.none, s.key(c)); // no letter is a shortcut here
    try std.testing.expectEqual(pw.Key.none, s.key(map.KEY_ENTER)); // 7: too short
    try std.testing.expect(has(dump(&s), "8 to 63 characters") and has(dump(&s), "*******_") and !has(dump(&s), "rR f"));
    _ = s.key('!');
    try std.testing.expectEqual(pw.Key.join, s.key(map.KEY_ENTER));
    try std.testing.expectEqualStrings("rR fFeE!", s.passText());
    for (0..80) |_| _ = s.key('x');
    try std.testing.expectEqual(@as(u8, wc.PASS_MAX), s.pass_len); // stops at 63
    try std.testing.expect(has(dump(&s), "Password (63)"));
    _ = s.key(map.KEY_BACKSPACE);
    try std.testing.expectEqual(@as(u8, wc.PASS_MAX - 1), s.pass_len);
    _ = s.key(map.KEY_ARROW_UP); // not a character: ignored
    try std.testing.expectEqual(@as(u8, wc.PASS_MAX - 1), s.pass_len);
    _ = s.key(map.KEY_ESCAPE);
    try std.testing.expectEqual(pw.Screen.list, s.screen);
    try std.testing.expectEqual(@as(u8, 0), s.pass_len);
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** s.pass.len, &s.pass);
}

test "an SSID the OSD cannot show: UTF-8 as '?', a long one cut with '~'" {
    var s = pw.State{ .screen = .list, .n_nets = 2 };
    s.nets[0] = net("Café \"Net\"", -40, true);
    s.nets[1] = net("x" ** 32, -90, false);
    const t = dump(&s);
    try std.testing.expect(has(t, "*#### Caf?? \"Net\""));
    try std.testing.expect(has(t, "      " ++ "x" ** 23 ++ "~"));
    s.info = .{ .known = true, .connected = wc.Ssid.of("Café"), .saved = .{ .ssid = wc.Ssid.of("Home").?, .open = false } };
    s.screen = .home;
    try std.testing.expect(has(dump(&s), "Network Caf??") and has(dump(&s), "Address none (DHCP)") and has(dump(&s), "Saved   Home"));
}

test "busy: a spinner and what runs; Esc leaves, nothing else does" {
    var s = listed(1);
    s.wait(.join);
    try std.testing.expect(has(dump(&s), "| Joining") and has(dump(&s), "  net"));
    s.phase = 1;
    try std.testing.expect(has(dump(&s), "/ Joining"));
    try std.testing.expectEqual(pw.Key.none, s.key(map.KEY_ENTER));
    try std.testing.expectEqual(pw.Key.back, s.key(map.KEY_ESCAPE));
    try std.testing.expectEqualStrings("working...  Esc leave", draw.hint(&s));
}
