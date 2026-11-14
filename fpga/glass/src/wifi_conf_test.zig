// wifi.conf (wifi_conf.zig): the PSK is wpa_passphrase's, the file reads back what was written for any
// SSID (spaces, quotes, UTF-8), a hand-written file still names its network, and the password is gone.
const std = @import("std");
const wc = @import("wifi_conf.zig");

const io = std.testing.io;

fn hashed(ssid: []const u8, pass: []const u8) !wc.Psk {
    var buf: [wc.PASS_MAX + 1]u8 = undefined;
    @memcpy(buf[0..pass.len], pass);
    return wc.psk(ssid, buf[0..pass.len]);
}

test "the PSK is wpa_passphrase's for the 802.11i vectors and a UTF-8 SSID" {
    // IEEE 802.11i-2004 H.4.1, and `wpa_passphrase 'Café "Net" 2' 'pa ss"word'` (wpa_supplicant 2.10).
    try std.testing.expectEqualStrings("f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e", &try hashed("IEEE", "password"));
    try std.testing.expectEqualStrings("0dc0d6eb90555ed6419756b9a15ec3e3209b63df707dd508d14581f8982721af", &try hashed("ThisIsASSID", "ThisIsAPassword"));
    try std.testing.expectEqualStrings("f6f8363ecee1bb5588f59f81ac639c2cb21cdf2ba02e2fc58b2e9921738a1709", &try hashed("Café \"Net\" 2", "pa ss\"word"));
}

test "the passphrase buffer is zeroed after hashing, and when it is refused" {
    var pass = "password".*;
    _ = try wc.psk("IEEE", &pass);
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** 8, &pass);
    var short = "seven77".*; // 7 characters: WPA2 wants 8..63
    try std.testing.expectError(error.BadPassphrase, wc.psk("IEEE", &short));
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** 7, &short);
    try std.testing.expectError(error.BadPassphrase, hashed("IEEE", "x" ** 64));
    try std.testing.expectError(error.BadPassphrase, hashed("IEEE", "pass\x01word"));
    try std.testing.expectError(error.BadPassphrase, hashed("", "password"));
}

test "a secured network is written as wpa_passphrase's block, without the password" {
    var buf: [512]u8 = undefined;
    const key = try hashed("IEEE", "password");
    const text = try wc.format(&buf, "IEEE", &key);
    try std.testing.expect(std.mem.indexOf(u8, text, "network={\n\tssid=\"IEEE\"\n\tpsk=f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e\n}\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "password") == null and std.mem.indexOf(u8, text, "#psk") == null);
    const open = try wc.format(&buf, "Cafe Libre", null);
    try std.testing.expect(std.mem.indexOf(u8, open, "\tssid=\"Cafe Libre\"\n\tkey_mgmt=NONE\n}") != null);
}

test "any SSID round-trips: spaces and quotes quoted, UTF-8 and control bytes as hex" {
    const cases = [_]struct { ssid: []const u8, line: []const u8 }{
        .{ .ssid = " lead and trail ", .line = "ssid=\" lead and trail \"" },
        .{ .ssid = "say \"hi\"", .line = "ssid=\"say \"hi\"\"" },
        .{ .ssid = "back\\slash", .line = "ssid=\"back\\slash\"" },
        .{ .ssid = "Café", .line = "ssid=436166c3a9" },
        .{ .ssid = "tab\there", .line = "ssid=7461620968657265" },
        .{ .ssid = "x" ** 32, .line = "ssid=\"" ++ "x" ** 32 ++ "\"" },
    };
    var buf: [512]u8 = undefined;
    const key = try hashed("IEEE", "password");
    for (cases) |c| {
        const text = try wc.format(&buf, c.ssid, if (c.ssid.len % 2 == 0) &key else null);
        try std.testing.expect(std.mem.indexOf(u8, text, c.line) != null);
        const back = wc.parse(text) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(c.ssid, back.ssid.slice());
        try std.testing.expectEqual(c.ssid.len % 2 != 0, back.open);
    }
}

test "a hand-written wifi.conf (CRLF, comments, several networks) names its first network" {
    const text = "# home\r\nctrl_interface=/var/run/wpa_supplicant\r\nnetwork={\r\n    ssid=\"Metaverse\"\r\n    #psk=\"x\"\r\n    psk=00\r\n}\r\nnetwork={\r\n ssid=\"Other\"\r\n}\r\n";
    const s = wc.parse(text) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Metaverse", s.ssid.slice());
    try std.testing.expect(!s.open);
}

test "a wifi.conf with no readable network is none" {
    for ([_][]const u8{ "", "network={\n}\n", "network={\n ssid=\"\"\n}", "network={\n ssid=abc\n}", "network={\n ssid=\"x\"\n", "ssid=\"loose\"\n", "network={\n ssid=" ++ "41" ** 33 ++ "\n}" })
        |t| try std.testing.expectEqual(@as(?wc.Saved, null), wc.parse(t));
}

test "saved, loaded and forgotten on a directory; no file and no directory are told apart" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [128]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var file: [wc.MAX_BYTES]u8 = undefined;
    try std.testing.expectEqual(@as(?wc.Saved, null), wc.load(io, dir, &file));
    try wc.remove(io, dir); // nothing to forget: fine
    var buf: [512]u8 = undefined;
    try wc.save(io, dir, try wc.format(&buf, "my net", null));
    try std.testing.expectEqualStrings("my net", wc.load(io, dir, &file).?.ssid.slice());
    try wc.remove(io, dir);
    try std.testing.expectEqual(@as(?wc.Saved, null), wc.load(io, dir, &file));
    try std.testing.expectError(error.FileNotFound, wc.save(io, ".zig-cache/tmp/no/such/dir", "x"));
}
