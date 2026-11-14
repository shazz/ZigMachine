// ZIGNIC's name lookups (net_card.zig, docs/GEM_NET.md N2): a DNS A query sent over a UDP socket to the board's
// nameserver (/etc/resolv.conf, written by udhcpc), the answer's first A record parsed when it arrives. Never
// blocks: the query goes out at RESOLVE, the reply is read at a later poll. No libc resolver in a static glass.
const std = @import("std");
const linux = std.os.linux;

pub const PORT: u16 = 53;

/// "a.b.c.d" -> 0xAABBCCDD, else null.
pub fn dotted(s: []const u8) ?u32 {
    var it = std.mem.splitScalar(u8, s, '.');
    var v: u32 = 0;
    var n: usize = 0;
    while (it.next()) |part| : (n += 1) {
        if (n == 4) return null;
        v = v << 8 | (std.fmt.parseInt(u8, part, 10) catch return null);
    }
    return if (n == 4) v else null;
}

/// The first `nameserver a.b.c.d` of resolv.conf's text, else null.
pub fn nameserver(conf: []const u8) ?u32 {
    var lines = std.mem.splitScalar(u8, conf, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "nameserver")) continue;
        var f = std.mem.tokenizeAny(u8, line["nameserver".len..], " \t#");
        if (f.next()) |a| if (dotted(a)) |ip| return ip;
    }
    return null;
}

/// A query for `name`'s A record into `out`: its length, or null (a label too long, the name too long).
pub fn query(id: u16, name: []const u8, out: []u8) ?usize {
    if (name.len == 0 or name.len > 253 or out.len < name.len + 18) return null;
    std.mem.writeInt(u16, out[0..2], id, .big);
    @memcpy(out[2..12], &[_]u8{ 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0 }); // RD, 1 question
    var at: usize = 12;
    var labels = std.mem.splitScalar(u8, std.mem.trimEnd(u8, name, "."), '.');
    while (labels.next()) |l| {
        if (l.len == 0 or l.len > 63) return null;
        out[at] = @intCast(l.len);
        @memcpy(out[at + 1 ..][0..l.len], l);
        at += 1 + l.len;
    }
    @memcpy(out[at..][0..5], &[_]u8{ 0, 0, 1, 0, 1 }); // root, QTYPE A, QCLASS IN
    return at + 5;
}

pub const Answer = union(enum) { ip: u32, not_found, wait };

/// The reply `msg` to query `id`: its first A record, not_found (an error code or no A), or wait (not ours).
pub fn parse(id: u16, msg: []const u8) Answer {
    if (msg.len < 12 or std.mem.readInt(u16, msg[0..2], .big) != id or msg[2] & 0x80 == 0) return .wait;
    if (msg[3] & 0x0F != 0) return .not_found;
    const qd = std.mem.readInt(u16, msg[4..6], .big);
    const an = std.mem.readInt(u16, msg[6..8], .big);
    var at: usize = 12;
    for (0..qd) |_| at = (skipName(msg, at) orelse return .not_found) + 4;
    for (0..an) |_| {
        at = skipName(msg, at) orelse return .not_found;
        if (at + 10 > msg.len) return .not_found;
        const typ = std.mem.readInt(u16, msg[at..][0..2], .big);
        const len = std.mem.readInt(u16, msg[at + 8 ..][0..2], .big);
        at += 10;
        if (at + len > msg.len) return .not_found;
        if (typ == 1 and len == 4) return .{ .ip = std.mem.readInt(u32, msg[at..][0..4], .big) };
        at += len;
    }
    return .not_found;
}

fn skipName(msg: []const u8, start: usize) ?usize {
    var at = start;
    while (at < msg.len) {
        const l = msg[at];
        if (l == 0) return at + 1;
        if (l & 0xC0 == 0xC0) return if (at + 2 <= msg.len) at + 2 else null; // a pointer ends the name
        at += 1 + l;
    }
    return null;
}

test "a query, and the answer's A record" {
    var q: [64]u8 = undefined;
    const n = query(0x1234, "bbs.zig", &q).?;
    try std.testing.expectEqualSlices(u8, &[_]u8{ 3, 'b', 'b', 's', 3, 'z', 'i', 'g', 0, 0, 1, 0, 1 }, q[12..n]);
    var r: [64]u8 = undefined;
    @memcpy(r[0..n], q[0..n]);
    r[2] = 0x81;
    r[3] = 0x80;
    r[7] = 1; // one answer
    const ans = [_]u8{ 0xC0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184, 216, 34 };
    @memcpy(r[n..][0..ans.len], &ans);
    try std.testing.expectEqual(Answer{ .ip = 0x5DB8D822 }, parse(0x1234, r[0 .. n + ans.len]));
    r[3] = 0x83; // NXDOMAIN
    try std.testing.expectEqual(Answer.not_found, parse(0x1234, r[0 .. n + ans.len]));
    try std.testing.expectEqual(Answer.wait, parse(0x9999, r[0 .. n + ans.len]));
}

test "dotted addresses and resolv.conf" {
    try std.testing.expectEqual(@as(?u32, 0x0A4D0001), dotted("10.77.0.1"));
    try std.testing.expectEqual(@as(?u32, null), dotted("10.77.0"));
    try std.testing.expectEqual(@as(?u32, null), dotted("bbs.zig"));
    try std.testing.expectEqual(@as(?u32, 0x18C9F54D), nameserver("search home # wlan0\nnameserver 24.201.245.77 # wlan0\n"));
}
