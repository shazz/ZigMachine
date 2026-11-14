// ZIGNIC on the board (docs/GEM_NET.md N2): glass is the network card. ZIGGY's firmware (cycles/bnet.c) writes one
// request at window end - NET_FROM_TOP (map_cart.zig NET_*); the C: thread polls it (kos_drive.zig) beside C:'s
// blocks. A whole, checked, unanswered block is COPIED out first (the cart may rewrite the window meanwhile), then
// served on Linux's sockets (net_sock.zig: never blocking), its bytes moved in place in the cart's memory (send
// reads them, recv writes them), and the answer written: NB_OUT.., NB_DONE, then NB_ACK = the sequence last.
const std = @import("std");
const linux = std.os.linux;
const mc = @import("map_cart.zig");
const abi = @import("net_abi");
const dns = @import("net_dns.zig");
const ns = @import("net_sock.zig");

const code = ns.code;
const WINDOW_TOP_FREE = 0x1000; // the cart's memory ends below the window's top 4 KiB

pub const Card = struct {
    words: []volatile u32, // the cart window, index 0 = CART_CPU_BASE
    socks: [abi.SOCKETS]?ns.Sock = .{null} ** abi.SOCKETS,
    nameserver: ?u32 = null,
    served: u32 = 0,
    io: [abi.IO_MAX]u8 = undefined,

    fn block(self: *Card) []volatile u32 {
        return self.words[(self.words.len * 4 - mc.NET_FROM_TOP) / 4 ..][0..mc.NET_WORDS];
    }

    /// One look at the block: a whole request not yet answered is served. True if one was.
    pub fn poll(self: *Card) bool {
        const w = self.block();
        if (w[mc.NB_MAGIC] != mc.NET_MAGIC) return false;
        var s: [mc.NET_WORDS]u32 = undefined;
        for (&s, 0..) |*x, i| x.* = w[i];
        if (s[mc.NB_SEQ] == 0 or s[mc.NB_ACK] == s[mc.NB_SEQ]) return false;
        var check: u32 = mc.NET_MAGIC ^ s[mc.NB_SEQ];
        for (s[mc.NB_OP .. mc.NB_HOST_LEN + 1]) |x| check ^= x;
        if (s[mc.NB_CHECK] != ~check) return false; // half-written
        w[mc.NB_TAKEN] = s[mc.NB_SEQ];
        var req = abi.Req{ .op = s[2], .sock = s[3], .a0 = s[4], .a1 = s[5], .buf = s[6], .len = s[7], .host = s[8], .host_len = s[9] };
        const done = self.serve(&req);
        const out = [mc.NB_OUT_WORDS]u32{ req.state, req.events, req.err, req.peer_ip, req.peer_port, req.local_port };
        for (out, 0..) |x, i| w[mc.NB_OUT + i] = x;
        w[mc.NB_DONE] = @bitCast(done);
        w[mc.NB_ACK] = s[mc.NB_SEQ];
        self.served +%= 1;
        return true;
    }

    /// The op on the request (buf and host are WINDOW offsets here); the socket's words written back into `r`.
    pub fn serve(self: *Card, r: *abi.Req) i32 {
        const op: abi.Op = @enumFromInt(r.op);
        if (op == .info) return self.info(r);
        if (op == .open) return self.open(r);
        if (r.sock >= abi.SOCKETS or self.socks[r.sock] == null) return code(.bad_socket);
        const s = &self.socks[r.sock].?;
        s.tick();
        const done = self.dispatch(op, r, s);
        if (self.socks[r.sock]) |*left| writeBack(r, left);
        return done;
    }

    fn dispatch(self: *Card, op: abi.Op, r: *abi.Req, s: *ns.Sock) i32 {
        return switch (op) {
            .poll => @intCast(@intFromEnum(s.state)),
            .close => blk: {
                s.close();
                self.socks[r.sock] = null;
                break :blk 0;
            },
            .connect => s.connect(r.a0, @truncate(r.a1)),
            .resolve => s.resolve(self.bytes(r.host, r.host_len) orelse return code(.invalid), self.nameserverIp()),
            .send => self.send(r, s),
            .recv => self.recv(r, s),
            .sendto => s.sendTo(r.a0, @truncate(r.a1), self.copyIn(r) orelse return code(.invalid)),
            .listen => if (s.mode == .tcp) code(.denied) else code(.invalid),
            .accept => code(.invalid),
            else => code(.invalid),
        };
    }

    fn writeBack(r: *abi.Req, s: *ns.Sock) void {
        r.state = @intFromEnum(s.state);
        r.events = s.events;
        r.err = @bitCast(s.err);
        r.peer_ip = s.peer_ip;
        r.peer_port = s.peer_port;
        r.local_port = s.local_port;
        s.events = 0;
    }

    fn open(self: *Card, r: *abi.Req) i32 {
        const n = for (self.socks, 0..) |s, i| {
            if (s == null) break i;
        } else return code(.no_socket);
        self.socks[n] = ns.Sock.open(@enumFromInt(r.a0), @truncate(r.a1)) catch return code(.invalid);
        writeBack(r, &self.socks[n].?);
        return @intCast(n);
    }

    fn info(self: *Card, r: *abi.Req) i32 {
        if (r.len < @sizeOf(abi.Info)) return code(.invalid);
        const out = abi.Info{ .id = abi.ID_ZNIC, .ip = localIp(), .dns = self.nameserverIp() orelse 0, .flags = abi.INFO_LINK };
        const b = std.mem.asBytes(&out);
        if (!self.inWindow(r.buf, b.len)) return code(.invalid);
        for (b, 0..) |x, i| self.byteAt(r.buf + i).* = x;
        return 1;
    }

    fn send(self: *Card, r: *abi.Req, s: *ns.Sock) i32 {
        const b = self.copyIn(r) orelse return code(.invalid);
        return s.send(b);
    }

    fn recv(self: *Card, r: *abi.Req, s: *ns.Sock) i32 {
        const n = @min(r.len, abi.IO_MAX);
        if (!self.inWindow(r.buf, n)) return code(.invalid);
        const got = s.recv(self.io[0..n]);
        if (got > 0) for (self.io[0..@intCast(got)], 0..) |x, i| {
            self.byteAt(r.buf + i).* = x;
        };
        return got;
    }

    fn copyIn(self: *Card, r: *abi.Req) ?[]const u8 {
        const n = @min(r.len, abi.IO_MAX);
        if (!self.inWindow(r.buf, n)) return null;
        for (self.io[0..n], 0..) |*x, i| x.* = self.byteAt(r.buf + i).*;
        return self.io[0..n];
    }

    var name_buf: [abi.HOST_MAX]u8 = undefined;
    fn bytes(self: *Card, off: u32, n: u32) ?[]const u8 {
        if (n == 0 or n > abi.HOST_MAX or !self.inWindow(off, n)) return null;
        for (name_buf[0..n], 0..) |*x, i| x.* = self.byteAt(off + i).*;
        return name_buf[0..n];
    }

    fn inWindow(self: *Card, off: u32, n: usize) bool {
        return @as(u64, off) + n <= self.words.len * 4 - WINDOW_TOP_FREE;
    }

    fn byteAt(self: *Card, off: usize) *volatile u8 {
        const base: [*]volatile u8 = @ptrCast(self.words.ptr);
        return &base[off];
    }

    fn nameserverIp(self: *Card) ?u32 {
        if (self.nameserver == null) self.nameserver = readNameserver();
        return self.nameserver;
    }
};

fn readNameserver() ?u32 {
    const rc = linux.open("/etc/resolv.conf", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var buf: [1024]u8 = undefined;
    const n = linux.read(fd, &buf, buf.len);
    if (linux.errno(n) != .SUCCESS) return null;
    return dns.nameserver(buf[0..n]);
}

/// The board's own address: the source a UDP socket would use towards the internet (no packet is sent).
fn localIp() u32 {
    const rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(rc) != .SUCCESS) return 0;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    const to = linux.sockaddr.in{ .port = std.mem.nativeToBig(u16, 53), .addr = std.mem.nativeToBig(u32, 0x01010101) };
    if (linux.errno(linux.connect(fd, @ptrCast(&to), @sizeOf(linux.sockaddr.in))) != .SUCCESS) return 0;
    var me: linux.sockaddr.in = undefined;
    var len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    _ = linux.getsockname(fd, @ptrCast(&me), &len);
    return std.mem.bigToNative(u32, me.addr);
}
