// The Wi-Fi tools' output as the page reads it (wifi_parse.zig), from captured shapes of iw 6.x,
// busybox ip and wpa_supplicant 2.10.
const std = @import("std");
const wp = @import("wifi_parse.zig");

const SCAN =
    "BSS 11:22:33:44:55:66(on wlan0)\n" ++
    "\tlast seen: 120.000s [boottime]\n" ++
    "\tfreq: 2437\n" ++
    "\tcapability: ESS Privacy ShortSlotTime (0x0411)\n" ++
    "\tsignal: -71.00 dBm\n" ++
    "\tSSID: Metaverse\n" ++
    "\tRSN:\t * Version: 1\n" ++
    "\t\t * Group cipher: CCMP\n" ++
    "BSS 11:22:33:44:55:77(on wlan0) -- associated\n" ++
    "\tcapability: ESS Privacy (0x0411)\n" ++
    "\tsignal: -48.00 dBm\n" ++
    "\tSSID: Metaverse\n" ++
    "\tRSN:\t * Version: 1\n" ++
    "BSS aa:bb:cc:dd:ee:01(on wlan0)\n" ++
    "\tcapability: ESS ShortSlotTime (0x0401)\n" ++
    "\tsignal: -80.00 dBm\n" ++
    "\tSSID: \\x20Cafe Libre\\x20\n" ++
    "BSS aa:bb:cc:dd:ee:02(on wlan0)\n" ++
    "\tcapability: ESS Privacy (0x0411)\n" ++
    "\tsignal: -60.00 dBm\n" ++
    "\tSSID: Caf\\xc3\\xa9 \"Net\" \\x5c2\n" ++
    "\tWPA:\t * Version: 1\n" ++
    "BSS aa:bb:cc:dd:ee:03(on wlan0)\n" ++
    "\tcapability: ESS Privacy (0x0411)\n" ++
    "\tsignal: -30.00 dBm\n" ++
    "\tSSID: \\x00\\x00\\x00\\x00\n" ++
    "BSS aa:bb:cc:dd:ee:04(on wlan0)\n" ++
    "\tcapability: ESS Privacy (0x0411)\n" ++
    "\tsignal: -66.00 dBm\n" ++
    "\tSSID: \n" ++
    "BSS aa:bb:cc:dd:ee:05(on wlan0)\n" ++
    "\tcapability: ESS Privacy (0x0411)\n" ++
    "\tsignal: -90.00 dBm\n" ++
    "\tSSID: OldWep\n" ++
    "\n";

test "a scan lists each network once at its strongest, strongest first, hidden ones left out" {
    var nets: [wp.NETS_MAX]wp.Net = undefined;
    const n = wp.scan(SCAN, &nets);
    try std.testing.expectEqual(@as(usize, 4), n);
    try std.testing.expectEqualStrings("Metaverse", nets[0].ssid.slice());
    try std.testing.expectEqual(@as(i16, -48), nets[0].dbm);
    try std.testing.expect(nets[0].secured);
    try std.testing.expectEqualStrings("Café \"Net\" \\2", nets[1].ssid.slice()); // UTF-8 and the backslash undone
    try std.testing.expect(nets[1].secured); // WPA
    try std.testing.expectEqualStrings(" Cafe Libre ", nets[2].ssid.slice()); // the edge spaces iw escapes
    try std.testing.expect(!nets[2].secured); // no Privacy, no RSN: open
    try std.testing.expectEqualStrings("OldWep", nets[3].ssid.slice());
    try std.testing.expect(nets[3].secured); // Privacy alone (WEP): not open
}

test "an empty or failed scan lists nothing; a crowded one keeps the strongest" {
    var nets: [wp.NETS_MAX]wp.Net = undefined;
    try std.testing.expectEqual(@as(usize, 0), wp.scan("", &nets));
    try std.testing.expectEqual(@as(usize, 0), wp.scan("command failed: Device or resource busy (-16)\n", &nets));
    var many: std.ArrayList(u8) = .empty;
    defer many.deinit(std.testing.allocator);
    for (0..wp.NETS_MAX + 6) |i| try many.print(std.testing.allocator, "BSS 00:00:00:00:00:{d:0>2}(on wlan0)\n\tsignal: -{d}.00 dBm\n\tSSID: net{d}\n", .{ i, 90 - i, i });
    try std.testing.expectEqual(@as(usize, wp.NETS_MAX), wp.scan(many.items, &nets));
    try std.testing.expectEqualStrings("net29", nets[0].ssid.slice()); // -61, the strongest
    try std.testing.expectEqual(@as(i16, -84), nets[wp.NETS_MAX - 1].dbm); // net6: the 6 weakest dropped
}

test "iw's escapes: \\xNN undone, a bad or overlong one refused" {
    try std.testing.expectEqualStrings("a b", wp.unescape("a b").?.slice());
    try std.testing.expectEqualStrings("\\", wp.unescape("\\x5c").?.slice());
    try std.testing.expectEqual(@as(?@import("wifi_conf.zig").Ssid, null), wp.unescape("\\xZZ"));
    try std.testing.expectEqual(@as(?@import("wifi_conf.zig").Ssid, null), wp.unescape("x" ** 33));
}

test "signal bars" {
    try std.testing.expectEqual(@as(u8, 4), wp.bars(-40));
    try std.testing.expectEqual(@as(u8, 3), wp.bars(-60));
    try std.testing.expectEqual(@as(u8, 2), wp.bars(-75));
    try std.testing.expectEqual(@as(u8, 1), wp.bars(-85));
    try std.testing.expectEqual(@as(u8, 0), wp.bars(-100));
}

test "iw link names the network it is on, or none" {
    const on = "Connected to 11:22:33:44:55:77 (on wlan0)\n\tSSID: My Net\n\tfreq: 2437\n\tsignal: -48 dBm\n";
    try std.testing.expectEqualStrings("My Net", wp.link(on).?.slice());
    try std.testing.expectEqual(@as(?@import("wifi_conf.zig").Ssid, null), wp.link("Not connected.\n"));
    try std.testing.expectEqual(@as(?@import("wifi_conf.zig").Ssid, null), wp.link(""));
}

test "ip addr gives the address, or none before DHCP" {
    const busybox = "3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq qlen 1000\n    link/ether b8:27:eb:00:00:01 brd ff:ff:ff:ff:ff:ff\n    inet 192.168.0.16/24 brd 192.168.0.255 scope global wlan0\n    inet6 fe80::1/64 scope link\n";
    try std.testing.expectEqualStrings("192.168.0.16", wp.addr(busybox).?);
    try std.testing.expectEqual(@as(?[]const u8, null), wp.addr("3: wlan0: <UP> mtu 1500\n    inet6 fe80::1/64 scope link\n"));
    const one = "3: wlan0    inet 192.168.0.16/24 brd 192.168.0.255 scope global wlan0\\       valid_lft forever preferred_lft forever\n";
    try std.testing.expectEqualStrings("192.168.0.16", wp.addr(one).?);
    try std.testing.expectEqual(@as(?[]const u8, null), wp.addr(""));
    try std.testing.expectEqual(@as(?[]const u8, null), wp.addr("Device \"wlan0\" does not exist.\n"));
}

test "a join's outcome from wpa_supplicant's log" {
    try std.testing.expectEqual(wp.Outcome.pending, wp.outcome("Successfully initialized wpa_supplicant\nwlan0: SME: Trying to authenticate with 11:22:33:44:55:77\n"));
    try std.testing.expectEqual(wp.Outcome.connected, wp.outcome("wlan0: CTRL-EVENT-CONNECTED - Connection to 11:22:33:44:55:77 completed [id=0 id_str=]\n"));
    try std.testing.expectEqual(wp.Outcome.wrong_key, wp.outcome("wlan0: WPA: 4-Way Handshake failed - pre-shared key may be incorrect\n"));
    try std.testing.expectEqual(wp.Outcome.wrong_key, wp.outcome("wlan0: CTRL-EVENT-SSID-TEMP-DISABLED id=0 ssid=\"x\" auth_failures=1 duration=10 reason=WRONG_KEY\n"));
    try std.testing.expectEqual(wp.Outcome.not_found, wp.outcome("wlan0: CTRL-EVENT-NETWORK-NOT-FOUND\n"));
}
