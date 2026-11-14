// --------------------------------------------------------------------------
// ZIGNIC, the network card (docs/GEM_NET.md): a socket-offload card like the WIZnet W5500 a retro machine
// plugs in, or the ESP32 of a FujiNet / WiC64 — the TCP/IP stack is in the card, the cart drives 8 sockets.
// On KESTREL "the card" is the host: glass on the board (Linux's sockets), the page (a WebSocket relay or a
// scripted peer), the native host. The cart never runs a protocol: no TCP state, no checksums, no DNS, no TLS.
//
// One import, `env.netOp(req) i32`: the cart fills a Req in its own memory and passes its address. Every op
// returns at once (nothing blocks: GEM 5 is cooperative, a program polls in its event loop): >= 0 the op's
// value, < 0 an Err. The host also writes the socket's state back into the Req (state, events, peer).
// This file is the ONE definition: docs/net-host.js, fpga/glass (net_card.zig, N2) and libs/zig/net.zig
// follow its numbers; the tests pin them.
// --------------------------------------------------------------------------
pub const SOCKETS: u32 = 8;
pub const IO_MAX: u32 = 16 * 1024; // the most bytes one send/recv moves
pub const HOST_MAX: u32 = 255; // a host name (resolve, TLS SNI)

pub const Op = enum(u32) {
    info = 0, // the card: Info (6 words) into buf; returns 1 if a card is there
    open = 1, // a0 = Mode, a1 = local port (0: any) -> the socket number
    connect = 2, // a0 = IPv4 (big-endian bytes a.b.c.d as 0xAABBCCDD), a1 = port; TLS: host = the name (SNI)
    listen = 3, // a1 = port (TCP); the host may refuse (Err.denied) unless the port is allowed
    send = 4, // buf/len -> bytes taken (0: would block)
    recv = 5, // buf/len -> bytes given (0: nothing yet); UDP: peer_ip/peer_port = the datagram's sender
    sendto = 6, // UDP: a0 = IPv4, a1 = port, buf/len -> bytes sent
    poll = 7, // nothing: the state, events and peer written back; returns the state
    close = 8, // the socket is free again
    resolve = 9, // host/host_len: starts a lookup on the socket (Mode.resolve); poll until State.resolved: peer_ip
    accept = 10, // a LISTEN socket: -> a new socket number for the waiting connection (Err.again: none yet)
    _,
};

pub const Mode = enum(u32) { tcp = 1, udp = 2, icmp = 3, tls = 4, resolve = 5, _ };

pub const State = enum(u32) {
    closed = 0,
    open = 1, // opened, not connected (UDP: ready)
    connecting = 2,
    established = 3,
    listen = 4,
    close_wait = 5, // the peer closed: what it sent may still be read
    resolving = 6,
    resolved = 7, // peer_ip holds the answer
    failed = 8, // err holds why
    _,
};

/// Events: sticky bits, cleared by the poll that returns them.
pub const EV_CONNECTED: u32 = 1 << 0;
pub const EV_DATA: u32 = 1 << 1; // bytes (or a datagram) waiting
pub const EV_SENT: u32 = 1 << 2; // room to send again
pub const EV_CLOSED: u32 = 1 << 3; // the peer closed / reset
pub const EV_RESOLVED: u32 = 1 << 4;
pub const EV_ACCEPT: u32 = 1 << 5; // a connection waits on a LISTEN socket
pub const EV_ERROR: u32 = 1 << 6;

pub const Err = enum(i32) {
    no_card = -1, // no network card on this host (the page without ?net=)
    bad_socket = -2,
    invalid = -3, // a bad op, mode, address or buffer
    again = -4, // would block: try later (connect in progress, nothing to accept)
    refused = -5,
    timeout = -6,
    unreachable_ = -7,
    not_found = -8, // the name does not resolve
    closed = -9, // the socket is closed / the peer is gone
    no_socket = -10, // all 8 in use
    tls = -11, // the TLS handshake or the certificate failed
    denied = -12, // the host does not allow it (a listener on a port not forwarded)
    _,
};

/// What the cart writes at the address it passes (every field a little-endian u32: wasm32).
pub const Req = extern struct {
    op: u32 = 0,
    sock: u32 = 0,
    a0: u32 = 0,
    a1: u32 = 0,
    buf: u32 = 0, // the cart's address of the data (send/recv/info)
    len: u32 = 0,
    host: u32 = 0, // the cart's address of a host name (resolve, TLS), host_len bytes
    host_len: u32 = 0,
    // Written back by the host:
    state: u32 = 0,
    events: u32 = 0,
    err: u32 = 0, // the socket's last Err (as u32), 0 if none
    peer_ip: u32 = 0,
    peer_port: u32 = 0,
    local_port: u32 = 0,
    _r0: u32 = 0,
    _r1: u32 = 0,
};

pub const REQ_BYTES = @sizeOf(Req);

/// Op.info's answer in buf (6 words).
pub const Info = extern struct {
    id: u32 = 0, // ID_ZNIC when a card answers
    ip: u32 = 0,
    mask: u32 = 0,
    gw: u32 = 0,
    dns: u32 = 0,
    flags: u32 = 0, // bit 0 link up, bit 1 TLS available, bit 2 listen allowed
};
pub const ID_ZNIC: u32 = 0x5A4E_4943; // "ZNIC"
pub const INFO_LINK: u32 = 1 << 0;
pub const INFO_TLS: u32 = 1 << 1;
pub const INFO_LISTEN: u32 = 1 << 2;

/// a.b.c.d -> the u32 the card takes (0xAABBCCDD).
pub fn ip4(a: u8, b: u8, c: u8, d: u8) u32 {
    return @as(u32, a) << 24 | @as(u32, b) << 16 | @as(u32, c) << 8 | d;
}

comptime {
    if (REQ_BYTES != 64) @compileError("net Req is 16 words: docs/net-host.js and the firmware read it so");
    if (@sizeOf(Info) != 24) @compileError("net Info is 6 words");
}

test "the Req's words are where the hosts read them" {
    const std = @import("std");
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Req, "op"));
    try std.testing.expectEqual(@as(usize, 4 * 8), @offsetOf(Req, "state"));
    try std.testing.expectEqual(@as(usize, 4 * 11), @offsetOf(Req, "peer_ip"));
    try std.testing.expectEqual(@as(u32, 0x0A4D0001), ip4(10, 77, 0, 1));
    try std.testing.expectEqual(@as(i32, -4), @intFromEnum(Err.again));
}
