// A join (wifi_join.zig) against the fake tools (wifi_fake.zig): the order of the commands, the
// files it writes, what each failure says, and that the password never leaves the request.
const std = @import("std");
const job = @import("wifi_job.zig");
const wc = @import("wifi_conf.zig");
const wk = @import("wifi_worker.zig");
const Fake = @import("wifi_fake.zig").Fake;

const io = std.testing.io;
var scratch: [wk.SCRATCH]u8 = undefined;
const IEEE_PSK = "f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e";

fn joinAs(f: *Fake, ssid: []const u8, pass: ?[]const u8) !job.Result {
    const env = f.env();
    var req = job.Request{ .kind = .join, .ssid = wc.Ssid.of(ssid).?, .open = pass == null };
    if (pass) |p| {
        @memcpy(req.pass[0..p.len], p);
        req.pass_len = @intCast(p.len);
    }
    var res: job.Result = .{};
    job.perform(&env, &req, &res, &scratch);
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** req.pass.len, &req.pass); // zeroed, every path
    return res;
}

fn runFile(f: *Fake, name: []const u8, buf: []u8) ![]const u8 {
    var p: [256]u8 = undefined;
    return f.tmp.dir.readFile(io, try std.fmt.bufPrint(&p, "run/{s}", .{name}), buf);
}

test "a join stops the old supplicant, starts ours on a 0600 conf, waits, asks DHCP, and hands back the block" {
    const f = try Fake.init("bin");
    defer f.deinit();
    f.link_out = "Connected to 11:22:33:44:55:77 (on wlan0)\n\tSSID: IEEE\n";
    const res = try joinAs(f, "IEEE", "password");
    try std.testing.expectEqual(job.Fail.none, res.fail);
    try std.testing.expectEqualStrings("IEEE", res.connected.?.slice());
    try std.testing.expectEqualStrings("192.168.0.16", res.ip());
    try std.testing.expect(std.mem.indexOf(u8, res.conf(), "ssid=\"IEEE\"\n\tpsk=" ++ IEEE_PSK) != null);
    const order = [_][]const u8{ "killall|-q|wpa_supplicant", "ip|link|set|wlan0|up", "wpa_supplicant|-B|-i|wlan0|-c|", "udhcpc|-i|wlan0|-q|-n", "iw|dev|wlan0|link" };
    var last: usize = 0;
    for (order) |o| {
        const at = f.find(o) orelse return error.TestUnexpectedResult;
        try std.testing.expect(at >= last);
        last = at;
    }
    try std.testing.expect(f.saw("/run/osd.conf|-f|") and f.saw("/run/osd.log"));
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(res.conf(), try runFile(f, "osd.conf", &buf));
    const st = try f.tmp.dir.statFile(io, "run/osd.conf", .{});
    try std.testing.expectEqual(@as(u32, 0o600), @as(u32, @intCast(st.permissions.toMode() & 0o777)));
    try std.testing.expect(!f.saw("password") and !f.saw("IEEE")); // neither the key nor the SSID is ever an argument
}

test "an SSID with spaces, quotes and UTF-8 joins: written as hex, never an argument" {
    const f = try Fake.init("bin");
    defer f.deinit();
    const ssid = "Café \"Net\" 2";
    const res = try joinAs(f, ssid, "pa ss\"word");
    try std.testing.expectEqual(job.Fail.none, res.fail);
    try std.testing.expectEqualStrings(ssid, wc.parse(res.conf()).?.ssid.slice());
    try std.testing.expect(!f.saw("Caf") and !f.saw("pa ss"));
}

test "an open network joins with key_mgmt=NONE" {
    const f = try Fake.init("bin");
    defer f.deinit();
    const res = try joinAs(f, " Cafe Libre ", null);
    try std.testing.expectEqual(job.Fail.none, res.fail);
    try std.testing.expect(wc.parse(res.conf()).?.open);
}

test "a wrong password says so, keeps nothing, and the card's network comes back (CRs dropped)" {
    const f = try Fake.init("bin");
    defer f.deinit();
    try f.tmp.dir.writeFile(io, .{ .sub_path = "card/wifi.conf", .data = "network={\r\n\tssid=\"Home\"\r\n\tpsk=00\r\n}\r\n" });
    f.log = "wlan0: WPA: 4-Way Handshake failed - pre-shared key may be incorrect\n";
    const res = try joinAs(f, "IEEE", "wrongpass");
    try std.testing.expectEqual(job.Fail.wrong_key, res.fail);
    try std.testing.expectEqual(@as(usize, 0), res.conf_len);
    try std.testing.expectEqual(@as(?usize, null), f.find("udhcpc|-i|wlan0|-q")); // no DHCP for a failed join
    try std.testing.expect(f.saw("/run/wpa.conf|-f|") and f.find("udhcpc|-b|-i|wlan0") != null);
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings("network={\n\tssid=\"Home\"\n\tpsk=00\n}\n", try runFile(f, "wpa.conf", &buf));
}

test "no answer in time is a timeout, an absent network says not found; no saved network: stays off" {
    const f = try Fake.init("bin");
    defer f.deinit();
    f.log = "wlan0: SME: Trying to authenticate\n";
    try std.testing.expectEqual(job.Fail.timeout, (try joinAs(f, "IEEE", "password")).fail);
    f.log = "wlan0: CTRL-EVENT-NETWORK-NOT-FOUND\n";
    f.n = 0;
    try std.testing.expectEqual(job.Fail.not_found, (try joinAs(f, "IEEE", "password")).fail);
    try std.testing.expect(!f.saw("/run/wpa.conf")); // no wifi.conf on the card: nothing to rejoin
}

test "DHCP with no address, a supplicant that will not start, a short password" {
    const f = try Fake.init("bin");
    defer f.deinit();
    f.dhcp_ok = false;
    const no_ip = try joinAs(f, "IEEE", "password");
    try std.testing.expectEqual(job.Fail.no_address, no_ip.fail);
    try std.testing.expectEqual(@as(usize, 0), no_ip.conf_len);
    f.dhcp_ok = true;
    f.start_busy = 1; // the old supplicant still on the interface: the second start works
    try std.testing.expectEqual(job.Fail.none, (try joinAs(f, "IEEE", "password")).fail);
    f.start_ok = false;
    try std.testing.expectEqual(job.Fail.supplicant, (try joinAs(f, "IEEE", "password")).fail);
    f.n = 0;
    try std.testing.expectEqual(job.Fail.bad_pass, (try joinAs(f, "IEEE", "short")).fail);
    try std.testing.expectEqual(@as(?usize, null), f.find("killall")); // refused before touching anything
}
