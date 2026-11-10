// One ZIGNIC socket on Linux (net_card.zig, docs/GEM_NET.md N2): a non-blocking TCP or UDP socket, or a UDP socket
// asking DNS (Mode.resolve). Every call returns at once; `tick` (at each op on the socket) moves a connect or a
// lookup on and gathers the events. TLS and ICMP are not served yet (Err.invalid), and listening is denied (no
// port is forwarded until KESTREL/net.conf exists).
const std = @import("std");
const linux = std.os.linux;
const abi = @import("net_abi");
const dns = @import("net_dns.zig");

pub const CONNECT_MS: i64 = 10_000;
pub const RESOLVE_MS: i64 = 3_000;

pub fn code(e: abi.Err) i32 {
    return @intFromEnum(e);
}

fn errOf(e: linux.E) abi.Err {
    return switch (e) {
        .CONNREFUSED => .refused,
        .TIMEDOUT => .timeout,
        .NETUNREACH, .HOSTUNREACH => .unreachable_,
        .PIPE, .CONNRESET, .NOTCONN => .closed,
        else => .invalid,
    };
}

pub fn nowMs() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.nsec)), 1_000_000);
}

fn sockaddr(ip: u32, port: u16) linux.sockaddr.in {
    return .{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, ip) };
}

pub const Sock = struct {
    fd: i32,
    mode: abi.Mode,
    state: abi.State = .open,
    events: u32 = 0,
    err: i32 = 0,
    peer_ip: u32 = 0,
    peer_port: u16 = 0,
    local_port: u16 = 0,
    since: i64 = 0,
    dns_id: u16 = 0,

    pub fn open(mode: abi.Mode, port: u16) error{Invalid}!Sock {
        const typ: u32 = switch (mode) {
            .tcp => linux.SOCK.STREAM,
            .udp, .resolve => linux.SOCK.DGRAM,
            else => return error.Invalid,
        };
        const rc = linux.socket(linux.AF.INET, typ | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
        if (linux.errno(rc) != .SUCCESS) return error.Invalid;
        var s = Sock{ .fd = @intCast(rc), .mode = mode };
        if (port != 0) {
            const sa = sockaddr(0, port);
            if (linux.errno(linux.bind(s.fd, @ptrCast(&sa), @sizeOf(linux.sockaddr.in))) != .SUCCESS) {
                s.close();
                return error.Invalid;
            }
            s.local_port = port;
        }
        return s;
    }

    pub fn close(self: *Sock) void {
        _ = linux.close(self.fd);
    }

    fn fail(self: *Sock, e: abi.Err) void {
        self.state = .failed;
        self.err = code(e);
        self.events |= abi.EV_ERROR;
    }

    pub fn connect(self: *Sock, ip: u32, port: u16) i32 {
        if (self.mode != .tcp or self.state != .open) return code(.invalid);
        const sa = sockaddr(ip, port);
        const e = linux.errno(linux.connect(self.fd, @ptrCast(&sa), @sizeOf(linux.sockaddr.in)));
        self.peer_ip = ip;
        self.peer_port = port;
        self.since = nowMs();
        if (e == .SUCCESS) {
            self.state = .established;
            self.events |= abi.EV_CONNECTED | abi.EV_SENT;
            return 0;
        }
        if (e != .INPROGRESS) return code(errOf(e));
        self.state = .connecting;
        return code(.again);
    }

    pub fn resolve(self: *Sock, name: []const u8, nameserver: ?u32) i32 {
        if (self.mode != .resolve or self.state != .open) return code(.invalid);
        if (dns.dotted(name)) |ip| {
            self.peer_ip = ip;
            self.state = .resolved;
            self.events |= abi.EV_RESOLVED;
            return code(.again);
        }
        const ns = nameserver orelse return code(.not_found);
        var q: [300]u8 = undefined;
        self.dns_id = @truncate(@as(u64, @bitCast(nowMs())) *% 2654435761);
        const n = dns.query(self.dns_id, name, &q) orelse return code(.invalid);
        const sa = sockaddr(ns, dns.PORT);
        _ = linux.sendto(self.fd, &q, n, linux.MSG.NOSIGNAL, @ptrCast(&sa), @sizeOf(linux.sockaddr.in));
        self.state = .resolving;
        self.since = nowMs();
        return code(.again);
    }

    /// Moves a connect or a lookup on, and sets the data / closed events.
    pub fn tick(self: *Sock) void {
        switch (self.state) {
            .connecting => self.tickConnect(),
            .resolving => self.tickResolve(),
            else => {},
        }
        if (self.state == .established or self.state == .close_wait or (self.mode == .udp and self.state == .open)) {
            var p = [1]linux.pollfd{.{ .fd = self.fd, .events = linux.POLL.IN, .revents = 0 }};
            if (linux.poll(&p, 1, 0) == 1 and p[0].revents & linux.POLL.IN != 0) self.events |= abi.EV_DATA;
        }
    }

    fn tickConnect(self: *Sock) void {
        var p = [1]linux.pollfd{.{ .fd = self.fd, .events = linux.POLL.OUT, .revents = 0 }};
        if (linux.poll(&p, 1, 0) != 1) {
            if (nowMs() - self.since > CONNECT_MS) self.fail(.timeout);
            return;
        }
        var e: u32 = 0;
        var len: linux.socklen_t = 4;
        _ = linux.getsockopt(self.fd, linux.SOL.SOCKET, linux.SO.ERROR, @ptrCast(&e), &len);
        if (e != 0) return self.fail(errOf(@enumFromInt(e)));
        self.state = .established;
        self.events |= abi.EV_CONNECTED | abi.EV_SENT;
    }

    fn tickResolve(self: *Sock) void {
        var buf: [512]u8 = undefined;
        const rc = linux.recvfrom(self.fd, &buf, buf.len, linux.MSG.DONTWAIT, null, null);
        if (linux.errno(rc) == .SUCCESS) switch (dns.parse(self.dns_id, buf[0..rc])) {
            .ip => |ip| {
                self.peer_ip = ip;
                self.state = .resolved;
                self.events |= abi.EV_RESOLVED;
                return;
            },
            .not_found => return self.fail(.not_found),
            .wait => {},
        };
        if (nowMs() - self.since > RESOLVE_MS) self.fail(.timeout);
    }

    pub fn send(self: *Sock, bytes: []const u8) i32 {
        if (self.state == .connecting) return 0;
        if (self.state != .established) return code(.closed);
        const rc = linux.sendto(self.fd, bytes.ptr, bytes.len, linux.MSG.DONTWAIT | linux.MSG.NOSIGNAL, null, 0);
        const e = linux.errno(rc);
        if (e == .AGAIN) return 0;
        if (e != .SUCCESS) {
            self.fail(errOf(e));
            return code(errOf(e));
        }
        return @intCast(rc);
    }

    pub fn sendTo(self: *Sock, ip: u32, port: u16, bytes: []const u8) i32 {
        if (self.mode != .udp) return code(.invalid);
        const sa = sockaddr(ip, port);
        const rc = linux.sendto(self.fd, bytes.ptr, bytes.len, linux.MSG.DONTWAIT | linux.MSG.NOSIGNAL, @ptrCast(&sa), @sizeOf(linux.sockaddr.in));
        const e = linux.errno(rc);
        return if (e == .SUCCESS) @intCast(rc) else if (e == .AGAIN) 0 else code(errOf(e));
    }

    pub fn recv(self: *Sock, out: []u8) i32 {
        if (self.mode == .udp) return self.recvFrom(out);
        if (self.state != .established and self.state != .close_wait) return if (self.state == .failed) self.err else 0;
        const rc = linux.recvfrom(self.fd, out.ptr, out.len, linux.MSG.DONTWAIT, null, null);
        const e = linux.errno(rc);
        if (e == .AGAIN) return 0;
        if (e != .SUCCESS) {
            self.fail(errOf(e));
            return code(errOf(e));
        }
        if (rc == 0 and out.len > 0) { // the peer closed
            self.state = .close_wait;
            self.events |= abi.EV_CLOSED;
        }
        return @intCast(rc);
    }

    fn recvFrom(self: *Sock, out: []u8) i32 {
        var sa: linux.sockaddr.in = undefined;
        var len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
        const rc = linux.recvfrom(self.fd, out.ptr, out.len, linux.MSG.DONTWAIT, @ptrCast(&sa), &len);
        const e = linux.errno(rc);
        if (e == .AGAIN) return 0;
        if (e != .SUCCESS) return code(errOf(e));
        self.peer_ip = std.mem.bigToNative(u32, sa.addr);
        self.peer_port = std.mem.bigToNative(u16, sa.port);
        return @intCast(rc);
    }
};
