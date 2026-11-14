// zg.net: ZIGNIC's sockets for carts (docs/GEM_NET.md; the ABI: machine/sdk/net_abi.zig). The card does the
// networking (the host's own stack: glass on the board, the page's relay or scripted LAN); a cart opens up to 8
// sockets and polls them from its frame loop. Nothing here blocks: an op that would wait returns error.Again or 0.
//
//   const s = try zg.net.Socket.open(.tcp);
//   s.connect(zg.net.ip4(10, 77, 0, 1), 7) catch |e| if (e != error.Again) return e;
//   ... each frame: const st = s.poll(); if (st.state == .established) _ = try s.send("hi\r\n");
const std = @import("std");
const builtin = @import("builtin");
pub const abi = @import("hardware").net_abi;

pub const Mode = abi.Mode;
pub const State = abi.State;
pub const ip4 = abi.ip4;

pub const Error = error{ NoCard, BadSocket, Invalid, Again, Refused, Timeout, Unreachable, NotFound, Closed, NoSocket, Tls, Denied, Unknown };

extern "env" fn netOp(req: u32) i32;

/// The host call: env.netOp in a cart; a test swaps it for a fake card.
pub var transport: *const fn (*abi.Req) i32 = &wasmOp;

fn wasmOp(req: *abi.Req) i32 {
    if (builtin.target.cpu.arch != .wasm32) return @intFromEnum(abi.Err.no_card);
    return netOp(@intCast(@intFromPtr(req)));
}

pub fn errorOf(code: i32) Error {
    return switch (@as(abi.Err, @enumFromInt(code))) {
        .no_card => error.NoCard,
        .bad_socket => error.BadSocket,
        .invalid => error.Invalid,
        .again => error.Again,
        .refused => error.Refused,
        .timeout => error.Timeout,
        .unreachable_ => error.Unreachable,
        .not_found => error.NotFound,
        .closed => error.Closed,
        .no_socket => error.NoSocket,
        .tls => error.Tls,
        .denied => error.Denied,
        _ => error.Unknown,
    };
}

fn call(req: *abi.Req) Error!u32 {
    const r = transport(req);
    return if (r < 0) errorOf(r) else @intCast(r);
}

/// The card's address and flags, or null when this host has no card.
pub fn info() ?abi.Info {
    var out = abi.Info{};
    var req = abi.Req{ .op = @intFromEnum(abi.Op.info), .buf = addr(&out), .len = @sizeOf(abi.Info) };
    _ = call(&req) catch return null;
    return if (out.id == abi.ID_ZNIC) out else null;
}

fn addr(p: anytype) u32 {
    return @truncate(@intFromPtr(p));
}

pub const Status = struct { state: State, events: u32, err: ?Error, peer_ip: u32, peer_port: u16 };

pub const Socket = struct {
    n: u32,

    pub fn open(mode: Mode) Error!Socket {
        var req = abi.Req{ .op = @intFromEnum(abi.Op.open), .a0 = @intFromEnum(mode) };
        return .{ .n = try call(&req) };
    }

    fn mk(self: Socket, op: abi.Op) abi.Req {
        return .{ .op = @intFromEnum(op), .sock = self.n };
    }

    /// Starts the connection (error.Again: in progress, poll until .established or .failed).
    pub fn connect(self: Socket, ip: u32, port: u16) Error!void {
        var r = self.mk(.connect);
        r.a0 = ip;
        r.a1 = port;
        _ = try call(&r);
    }

    /// TLS: the card does the handshake and checks `name`'s certificate; the cart sees plaintext.
    pub fn connectTls(self: Socket, ip: u32, port: u16, name: []const u8) Error!void {
        var r = self.mk(.connect);
        r.a0 = ip;
        r.a1 = port;
        r.host = addr(name.ptr);
        r.host_len = @intCast(name.len);
        _ = try call(&r);
    }

    /// Starts a lookup on a Mode.resolve socket; poll until .resolved (peer_ip) or .failed.
    pub fn resolve(self: Socket, name: []const u8) Error!void {
        var r = self.mk(.resolve);
        r.host = addr(name.ptr);
        r.host_len = @intCast(name.len);
        _ = try call(&r);
    }

    /// The bytes the card took (0: try again later).
    pub fn send(self: Socket, bytes: []const u8) Error!usize {
        var r = self.mk(.send);
        r.buf = addr(bytes.ptr);
        r.len = @intCast(@min(bytes.len, abi.IO_MAX));
        return try call(&r);
    }

    pub fn sendTo(self: Socket, ip: u32, port: u16, bytes: []const u8) Error!usize {
        var r = self.mk(.sendto);
        r.a0 = ip;
        r.a1 = port;
        r.buf = addr(bytes.ptr);
        r.len = @intCast(@min(bytes.len, abi.IO_MAX));
        return try call(&r);
    }

    /// Bytes read into `buf` (0: nothing yet). UDP/ICMP: one datagram; its sender is in the next poll().
    pub fn recv(self: Socket, buf: []u8) Error!usize {
        var r = self.mk(.recv);
        r.buf = addr(buf.ptr);
        r.len = @intCast(@min(buf.len, abi.IO_MAX));
        return try call(&r);
    }

    pub fn listen(self: Socket, port: u16) Error!void {
        var r = self.mk(.listen);
        r.a1 = port;
        _ = try call(&r);
    }

    /// A waiting inbound connection's socket (error.Again: none yet).
    pub fn accept(self: Socket) Error!Socket {
        var r = self.mk(.accept);
        return .{ .n = try call(&r) };
    }

    /// The socket's state, its events since the last poll, its error and its peer.
    pub fn poll(self: Socket) Status {
        var r = self.mk(.poll);
        _ = transport(&r);
        const e: i32 = @bitCast(r.err);
        return .{
            .state = @enumFromInt(r.state),
            .events = r.events,
            .err = if (e < 0) errorOf(e) else null,
            .peer_ip = r.peer_ip,
            .peer_port = @truncate(r.peer_port),
        };
    }

    pub fn close(self: Socket) void {
        var r = self.mk(.close);
        _ = transport(&r);
    }
};

test "an Err maps to its error, and no card answers no_card" {
    try std.testing.expectEqual(error.Refused, errorOf(-5));
    try std.testing.expectEqual(error.Unknown, errorOf(-99));
    try std.testing.expect(info() == null); // native: no card
}

var fake_last: abi.Req = .{};
fn fakeCard(r: *abi.Req) i32 {
    fake_last = r.*;
    r.state = @intFromEnum(State.established);
    r.events = abi.EV_DATA;
    return if (r.op == @intFromEnum(abi.Op.open)) 3 else 0;
}

test "a Socket fills the Req the card reads" {
    transport = &fakeCard;
    defer transport = &wasmOp;
    const s = try Socket.open(.tcp);
    try std.testing.expectEqual(@as(u32, 3), s.n);
    try s.connect(ip4(10, 77, 0, 1), 7);
    try std.testing.expectEqual(@as(u32, @intFromEnum(abi.Op.connect)), fake_last.op);
    try std.testing.expectEqual(@as(u32, 0x0A4D0001), fake_last.a0);
    try std.testing.expectEqual(@as(u32, 7), fake_last.a1);
    const st = s.poll();
    try std.testing.expectEqual(State.established, st.state);
    try std.testing.expect(st.events & abi.EV_DATA != 0);
}
