// The Wi-Fi jobs other than a join (wifi_job.zig), the tools and the interface they find
// (wifi_cmd.zig), and the thread and the board's runner (wifi_worker.zig).
const std = @import("std");
const job = @import("wifi_job.zig");
const cmd = @import("wifi_cmd.zig");
const wk = @import("wifi_worker.zig");
const Fake = @import("wifi_fake.zig").Fake;

var scratch: [wk.SCRATCH]u8 = undefined;

fn perform(f: *Fake, kind: job.Kind) job.Result {
    const env = f.env();
    var req = job.Request{ .kind = kind };
    var res: job.Result = .{};
    job.perform(&env, &req, &res, &scratch);
    return res;
}

test "no tools anywhere: the job names the first one missing and runs nothing" {
    const f = try Fake.init("");
    defer f.deinit();
    const res = perform(f, .scan);
    try std.testing.expectEqual(job.Fail.no_tools, res.fail);
    try std.testing.expectEqual(@as(?cmd.Tool, .iw), res.missing);
    try std.testing.expectEqual(@as(usize, 0), f.n);
}

test "the RAM copies in /tmp/up are found when PATH has none, and run with their libraries" {
    const f = try Fake.init("up");
    defer f.deinit();
    const t = cmd.find(std.testing.io, f.paths[0], f.paths[1]);
    try std.testing.expectEqual(@as(?cmd.Tool, null), t.missing());
    try std.testing.expect(t.ram and std.mem.endsWith(u8, t.path(.wpa_supplicant), "/up/wpa_supplicant"));
    _ = perform(f, .status);
    try std.testing.expect(f.ram_seen);
    const in_path = try Fake.init("bin");
    defer in_path.deinit();
    try std.testing.expect(!cmd.find(std.testing.io, in_path.paths[0], in_path.paths[1]).ram);
}

test "no Wi-Fi interface (no dongle, or no driver): said, nothing run" {
    const f = try Fake.init("bin");
    defer f.deinit();
    try f.tmp.dir.deleteTree(std.testing.io, "sys/class/net/wlan0");
    const res = perform(f, .scan);
    try std.testing.expectEqual(job.Fail.no_iface, res.fail);
    try std.testing.expectEqual(@as(usize, 0), f.n);
    try std.testing.expectEqual(@as(?cmd.Iface, null), cmd.iface(std.testing.io, "/no/such/root"));
}

test "status reads the network and the address, scan brings the interface up first" {
    const f = try Fake.init("bin");
    defer f.deinit();
    f.link_out = "Connected to 11:22:33:44:55:77 (on wlan0)\n\tSSID: Metaverse\n";
    f.addr_out = "3: wlan0    inet 10.0.0.7/24 scope global wlan0\n";
    const s = perform(f, .status);
    try std.testing.expectEqual(job.Fail.none, s.fail);
    try std.testing.expectEqualStrings("Metaverse", s.connected.?.slice());
    try std.testing.expectEqualStrings("10.0.0.7", s.ip());
    try std.testing.expect(f.find("iw|dev|wlan0|link") != null and f.find("ip|addr|show|dev|wlan0") != null);
    f.n = 0;
    const sc = perform(f, .scan);
    try std.testing.expectEqualStrings("ip|link|set|wlan0|up", f.call(0));
    try std.testing.expectEqualStrings("iw|dev|wlan0|scan", f.call(1));
    try std.testing.expectEqual(@as(usize, 2), sc.n_nets);
    try std.testing.expectEqualStrings(" Cafe Libre ", sc.nets[1].ssid.slice());
}

test "a busy scan is tried once more; twice busy is a failed scan; an empty one is no failure" {
    const f = try Fake.init("bin");
    defer f.deinit();
    f.scan_busy = 1;
    try std.testing.expectEqual(@as(usize, 2), perform(f, .scan).n_nets);
    f.scan_busy = 2;
    try std.testing.expectEqual(job.Fail.scan_failed, perform(f, .scan).fail);
    f.scan_out = "";
    const empty = perform(f, .scan);
    try std.testing.expect(empty.fail == .none and empty.n_nets == 0);
}

test "forget stops wpa_supplicant and drops the address" {
    const f = try Fake.init("bin");
    defer f.deinit();
    _ = perform(f, .forget);
    try std.testing.expectEqualStrings("killall|-q|wpa_supplicant", f.call(0));
    try std.testing.expectEqualStrings("ip|addr|flush|dev|wlan0", f.call(1));
}

test "the worker runs a job off the caller's thread, one at a time" {
    const f = try Fake.init("bin");
    defer f.deinit();
    var w = try std.testing.allocator.create(wk.Worker);
    defer std.testing.allocator.destroy(w);
    w.* = .{ .env = f.env() };
    defer w.deinit();
    try std.testing.expectEqual(@as(?*const job.Result, null), w.poll()); // none ran
    var req = job.Request{ .kind = .scan };
    try w.start(&req);
    var again = job.Request{ .kind = .status };
    const second = w.start(&again);
    const res = while (true) {
        if (w.poll()) |r| break r;
        std.Thread.yield() catch {};
    };
    if (second) |_| {} else |err| try std.testing.expectEqual(error.Busy, err); // unless the first was already done
    try std.testing.expectEqual(job.Kind.scan, res.kind);
    try std.testing.expect(!w.busy());
}

test "the board's runner: stdout kept, a non-zero exit or a missing tool is a failure" {
    var sp = wk.Spawn{ .gpa = std.testing.allocator, .io = std.testing.io };
    const r = sp.runner();
    var out: [64]u8 = undefined;
    const S = struct {
        fn go(rn: job.Runner, o: []u8, got: *job.Ran) void {
            got.* = rn.run(rn.ctx, &.{ "/bin/echo", "a b", "c" }, false, o);
        }
    };
    var got: job.Ran = undefined;
    const t = try std.Thread.spawn(.{}, S.go, .{ r, &out, &got }); // as the worker calls it
    t.join();
    try std.testing.expect(got.ok);
    try std.testing.expectEqualStrings("a b c\n", got.out);
    try std.testing.expect(!r.run(r.ctx, &.{"/bin/false"}, true, &out).ok);
    try std.testing.expect(!r.run(r.ctx, &.{"/no/such/tool"}, false, &out).ok);
}
