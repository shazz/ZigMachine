// ZIGNIC's board card (net_card.zig) driven as cycles/bnet.c drives it: request blocks written into a window,
// answered once each. A TCP connect to a loopback echo server (non-blocking: again, then established), send and
// recv through the cart's memory, a dotted resolve, no socket left, a bad socket, a half-written block ignored,
// a buffer past the cart's memory refused, and listen denied.
const std = @import("std");
const linux = std.os.linux;
const mc = @import("map_cart.zig");
const abi = @import("net_abi");
const nc = @import("net_card.zig");
const t = std.testing;

var win = [_]u32{0} ** (16 * 1024); // 64 KiB window: the top 4 KiB is the blocks', the cart below
var card = nc.Card{ .words = &win };
var seq: u32 = 0;

const Out = struct { done: i32, state: u32, events: u32, err: i32, peer: u32 };

fn ask(op: abi.Op, sock: u32, a0: u32, a1: u32, buf: u32, len: u32, host: u32, host_len: u32) Out {
    const w = win[(win.len * 4 - mc.NET_FROM_TOP) / 4 ..][0..mc.NET_WORDS];
    seq += 1;
    const f = [_]u32{ @intFromEnum(op), sock, a0, a1, buf, len, host, host_len };
    var check: u32 = mc.NET_MAGIC ^ seq;
    for (f, 0..) |x, i| {
        w[mc.NB_OP + i] = x;
        check ^= x;
    }
    w[mc.NB_SEQ] = seq;
    w[mc.NB_CHECK] = ~check;
    w[mc.NB_MAGIC] = mc.NET_MAGIC;
    std.debug.assert(card.poll());
    std.debug.assert(!card.poll()); // answered once
    return .{ .done = @bitCast(w[mc.NB_DONE]), .state = w[mc.NB_OUT], .events = w[mc.NB_OUT + 1], .err = @bitCast(w[mc.NB_OUT + 2]), .peer = w[mc.NB_OUT + 3] };
}

fn put(off: usize, s: []const u8) u32 {
    @memcpy(std.mem.sliceAsBytes(&win)[off..][0..s.len], s);
    return @intCast(s.len);
}

fn echoServer() !struct { fd: i32, port: u16 } {
    const fd: i32 = @intCast(linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0));
    var sa = linux.sockaddr.in{ .port = 0, .addr = std.mem.nativeToBig(u32, 0x7F000001) };
    try t.expectEqual(linux.E.SUCCESS, linux.errno(linux.bind(fd, @ptrCast(&sa), @sizeOf(linux.sockaddr.in))));
    _ = linux.listen(fd, 1);
    var len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    _ = linux.getsockname(fd, @ptrCast(&sa), &len);
    return .{ .fd = fd, .port = std.mem.bigToNative(u16, sa.port) };
}

fn echoOnce(fd: i32) void {
    const c: i32 = @intCast(linux.accept(fd, null, null));
    defer _ = linux.close(c);
    var b: [64]u8 = undefined;
    const k = linux.recvfrom(c, &b, b.len, 0, null, null);
    if (linux.errno(k) == .SUCCESS and k > 0) _ = linux.sendto(c, &b, k, linux.MSG.NOSIGNAL, null, 0);
    _ = linux.recvfrom(c, &b, b.len, 0, null, null); // until the card closes
}

fn waitState(sock: u32, want: abi.State) Out {
    var o: Out = undefined;
    for (0..200) |_| {
        o = ask(.poll, sock, 0, 0, 0, 0, 0, 0);
        if (o.state == @intFromEnum(want)) return o;
        _ = linux.nanosleep(&.{ .sec = 0, .nsec = 1_000_000 }, null);
    }
    return o;
}

test "a TCP echo through the card: non-blocking connect, send and recv in the cart's memory" {
    const srv = try echoServer();
    defer _ = linux.close(srv.fd);
    const th = try std.Thread.spawn(.{}, echoOnce, .{srv.fd});
    defer th.join();
    const s = ask(.open, 0, @intFromEnum(abi.Mode.tcp), 0, 0, 0, 0, 0).done;
    try t.expect(s >= 0);
    const c = ask(.connect, @intCast(s), 0x7F000001, srv.port, 0, 0, 0, 0);
    try t.expect(c.done == @intFromEnum(abi.Err.again) or c.done == 0);
    try t.expectEqual(@as(u32, @intFromEnum(abi.State.established)), waitState(@intCast(s), .established).state);
    const n = put(0x100, "hello card\r\n");
    try t.expectEqual(@as(i32, @intCast(n)), ask(.send, @intCast(s), 0, 0, 0x100, n, 0, 0).done);
    var got: i32 = 0;
    for (0..200) |_| {
        got = ask(.recv, @intCast(s), 0, 0, 0x200, 64, 0, 0).done;
        if (got != 0) break;
        _ = linux.nanosleep(&.{ .sec = 0, .nsec = 1_000_000 }, null);
    }
    try t.expectEqualStrings("hello card\r\n", std.mem.sliceAsBytes(&win)[0x200..][0..@intCast(got)]);
    try t.expectEqual(@as(i32, 0), ask(.close, @intCast(s), 0, 0, 0, 0, 0, 0).done);
}

test "resolve a dotted name, listen denied, refusals" {
    const r = ask(.open, 0, @intFromEnum(abi.Mode.resolve), 0, 0, 0, 0, 0).done;
    const hl = put(0x300, "10.77.0.1");
    _ = ask(.resolve, @intCast(r), 0, 0, 0, 0, 0x300, hl);
    const o = ask(.poll, @intCast(r), 0, 0, 0, 0, 0, 0);
    try t.expectEqual(@as(u32, @intFromEnum(abi.State.resolved)), o.state);
    try t.expectEqual(@as(u32, 0x0A4D0001), o.peer);
    _ = ask(.close, @intCast(r), 0, 0, 0, 0, 0, 0);
    const l = ask(.open, 0, @intFromEnum(abi.Mode.tcp), 0, 0, 0, 0, 0).done;
    try t.expectEqual(@as(i32, @intFromEnum(abi.Err.denied)), ask(.listen, @intCast(l), 0, 2323, 0, 0, 0, 0).done);
    const past: u32 = @intCast(win.len * 4 - 0x800);
    try t.expectEqual(@as(i32, @intFromEnum(abi.Err.invalid)), ask(.send, @intCast(l), 0, 0, past, 64, 0, 0).done);
    _ = ask(.close, @intCast(l), 0, 0, 0, 0, 0, 0);
    try t.expectEqual(@as(i32, @intFromEnum(abi.Err.bad_socket)), ask(.poll, 7, 0, 0, 0, 0, 0, 0).done);
    try t.expectEqual(@as(i32, @intFromEnum(abi.Err.invalid)), ask(.open, 0, @intFromEnum(abi.Mode.tls), 0, 0, 0, 0, 0).done);
}

test "all 8 sockets, then no_socket; a half-written block is not served" {
    var s: [abi.SOCKETS]i32 = undefined;
    for (&s) |*x| x.* = ask(.open, 0, @intFromEnum(abi.Mode.udp), 0, 0, 0, 0, 0).done;
    try t.expectEqual(@as(i32, @intFromEnum(abi.Err.no_socket)), ask(.open, 0, @intFromEnum(abi.Mode.udp), 0, 0, 0, 0, 0).done);
    for (s) |x| _ = ask(.close, @intCast(x), 0, 0, 0, 0, 0, 0);
    const w = win[(win.len * 4 - mc.NET_FROM_TOP) / 4 ..][0..mc.NET_WORDS];
    w[mc.NB_SEQ] = 999;
    w[mc.NB_CHECK] = 0; // wrong
    w[mc.NB_MAGIC] = mc.NET_MAGIC;
    try t.expect(!card.poll());
    w[mc.NB_MAGIC] = 0;
}
