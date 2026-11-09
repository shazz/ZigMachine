// The network spike (kos_net.zig): the request line, an exchange with a loopback echo server, the
// failures a cart can cause (nobody listening, a malformed first line), and the whole path through a
// C: write (kos_file.run) leaving the .ANS beside the .REQ.
const std = @import("std");
const linux = std.os.linux;
const net = @import("kos_net.zig");
const kf = @import("kos_file.zig");
const t = std.testing;

test "the request line: address, port, payload" {
    const r = net.parse("192.168.0.14 5555\r\nhello\r\n").?;
    try t.expectEqual([4]u8{ 192, 168, 0, 14 }, r.addr);
    try t.expectEqual(@as(u16, 5555), r.port);
    try t.expectEqualStrings("hello\r\n", r.payload);
    try t.expectEqualStrings("", net.parse("1.2.3.4 80").?.payload);
}

test "a malformed request line is refused" {
    for ([_][]const u8{ "", "1.2.3 80\n", "1.2.3.4.5 80\n", "1.2.3.400 80\n", "1.2.3.4 0\n", "1.2.3.4 70000\n", "host 80\n", "1.2.3.4\n" }) |s|
        try t.expect(net.parse(s) == null);
}

test "only C:\\NET\\*.REQ is a request" {
    try t.expect(net.isRequest(&.{"NET"}, "ECHO.REQ"));
    try t.expect(!net.isRequest(&.{"NET"}, "ECHO.TXT"));
    try t.expect(!net.isRequest(&.{}, "ECHO.REQ"));
    try t.expect(!net.isRequest(&.{ "A", "NET" }, "ECHO.REQ"));
}

/// A loopback listener on an ephemeral port: its fd and port.
fn listen() !struct { fd: i32, port: u16 } {
    const fd: i32 = @intCast(linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0));
    var sa = linux.sockaddr.in{ .port = 0, .addr = @bitCast([4]u8{ 127, 0, 0, 1 }) };
    try t.expectEqual(linux.E.SUCCESS, linux.errno(linux.bind(fd, @ptrCast(&sa), @sizeOf(linux.sockaddr.in))));
    try t.expectEqual(linux.E.SUCCESS, linux.errno(linux.listen(fd, 1)));
    var len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    _ = linux.getsockname(fd, @ptrCast(&sa), &len);
    return .{ .fd = fd, .port = std.mem.bigToNative(u16, sa.port) };
}

/// Accept one client and echo what it sends until it goes quiet, then close.
fn echoOnce(fd: i32) void {
    const c: i32 = @intCast(linux.accept(fd, null, null));
    defer _ = linux.close(c);
    var buf: [256]u8 = undefined;
    const k = linux.recvfrom(c, &buf, buf.len, 0, null, null);
    if (linux.errno(k) == .SUCCESS and k > 0) _ = linux.sendto(c, &buf, k, linux.MSG.NOSIGNAL, null, 0);
}

test "an exchange with an echo server returns the payload" {
    const l = try listen();
    defer _ = linux.close(l.fd);
    const th = try std.Thread.spawn(.{}, echoOnce, .{l.fd});
    defer th.join();
    var out: [64]u8 = undefined;
    const n = try net.exchange(.{ .addr = .{ 127, 0, 0, 1 }, .port = l.port, .payload = "hello KESTREL\r\n" }, &out);
    try t.expectEqualStrings("hello KESTREL\r\n", out[0..n]);
}

test "nobody listening is ConnectRefused, not a hang" {
    const l = try listen();
    _ = linux.close(l.fd); // the port is free again: nothing answers
    var out: [8]u8 = undefined;
    try t.expectError(error.ConnectRefused, net.exchange(.{ .addr = .{ 127, 0, 0, 1 }, .port = l.port, .payload = "x" }, &out));
}

fn get(dir: i32, name: [*:0]const u8, buf: []u8) []const u8 {
    const fd: i32 = @intCast(linux.openat(dir, name, .{ .ACCMODE = .RDONLY }, 0));
    defer _ = linux.close(fd);
    const k = linux.read(fd, buf.ptr, buf.len);
    return buf[0..k];
}

test "a C: write of NET\\ECHO.REQ leaves the reply in NET\\ECHO.ANS" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const hd = tmp.dir.handle;
    _ = linux.mkdirat(hd, "NET", 0o755);
    const l = try listen();
    defer _ = linux.close(l.fd);
    const th = try std.Thread.spawn(.{}, echoOnce, .{l.fd});
    defer th.join();
    var line: [64]u8 = undefined;
    const body = try std.fmt.bufPrint(&line, "127.0.0.1 {d}\r\nping\r\n", .{l.port});
    const r = kf.Req{ .op = .write, .flags = 3, .slot = 0, .attr = 0, .offset = 0, .path = "NET\\ECHO.REQ", .path2 = "", .data = body };
    try t.expectEqual(@as(i32, 0), try kf.run(hd, &r));
    const net_dir: i32 = @intCast(linux.openat(hd, "NET", .{ .DIRECTORY = true }, 0));
    defer _ = linux.close(net_dir);
    var b: [64]u8 = undefined;
    try t.expectEqualStrings("ping\r\n", get(net_dir, "ECHO.ANS", &b));
}

test "a malformed request leaves an ERR answer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const hd = tmp.dir.handle;
    _ = linux.mkdirat(hd, "NET", 0o755);
    const r = kf.Req{ .op = .write, .flags = 3, .slot = 1, .attr = 0, .offset = 0, .path = "NET\\BAD.REQ", .path2 = "", .data = "nonsense\r\n" };
    try t.expectEqual(@as(i32, 0), try kf.run(hd, &r));
    const net_dir: i32 = @intCast(linux.openat(hd, "NET", .{ .DIRECTORY = true }, 0));
    defer _ = linux.close(net_dir);
    var b: [64]u8 = undefined;
    try t.expect(std.mem.startsWith(u8, get(net_dir, "BAD.ANS", &b), "ERR "));
}
