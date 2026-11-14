// Reading what the Wi-Fi tools print (wifi_cmd.zig runs them): `iw dev wlan0 scan` and `link`,
// `ip -4 -o addr show`, and wpa_supplicant's log for how a join ended. Pure: wifi_parse_test.zig
// feeds it captured output.
const std = @import("std");
const wc = @import("wifi_conf.zig");

pub const Net = struct {
    ssid: wc.Ssid,
    dbm: i16, // the strongest of its access points
    secured: bool, // WPA/WPA2 (RSN) or WEP's Privacy bit: the page asks for a password
};

pub const NETS_MAX = 24;

/// iw's print_ssid_escaped: printable bytes as they are, others (and a space at either end, and
/// the backslash) as \xNN. Undone here, so the SSID is the network's own bytes.
pub fn unescape(s: []const u8) ?wc.Ssid {
    var out: [wc.SSID_MAX]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (n += 1) {
        if (n == out.len) return null;
        if (s[i] == '\\' and i + 4 <= s.len and s[i + 1] == 'x') {
            out[n] = std.fmt.parseInt(u8, s[i + 2 .. i + 4], 16) catch return null;
            i += 4;
        } else {
            out[n] = s[i];
            i += 1;
        }
    }
    return wc.Ssid.of(out[0..n]);
}

/// The networks `iw dev <if> scan` saw, one per SSID (its strongest signal), strongest first.
/// Hidden networks (no SSID) are left out: there is no name to show or to join.
pub fn scan(out: []const u8, nets: *[NETS_MAX]Net) usize {
    var n: usize = 0;
    var cur: ?Net = null;
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "BSS ")) {
            if (cur) |c| n = add(nets, n, c);
            cur = .{ .ssid = .{}, .dbm = -100, .secured = false };
            continue;
        }
        const c = if (cur) |*c| c else continue;
        const l = std.mem.trimStart(u8, line, "\t ");
        if (std.mem.startsWith(u8, line, "\tSSID: ")) {
            c.ssid = unescape(line["\tSSID: ".len..]) orelse .{};
        } else if (std.mem.startsWith(u8, l, "signal: ")) {
            c.dbm = dbm(l["signal: ".len..]);
        } else if (std.mem.startsWith(u8, line, "\tRSN:") or std.mem.startsWith(u8, line, "\tWPA:")) {
            c.secured = true;
        } else if (std.mem.startsWith(u8, l, "capability: ") and std.mem.indexOf(u8, l, " Privacy") != null) {
            c.secured = true;
        }
    }
    if (cur) |c| n = add(nets, n, c);
    std.mem.sort(Net, nets[0..n], {}, stronger);
    return n;
}

fn stronger(_: void, a: Net, b: Net) bool {
    return a.dbm > b.dbm;
}

fn dbm(s: []const u8) i16 {
    const end = std.mem.indexOfScalar(u8, s, '.') orelse std.mem.indexOfScalar(u8, s, ' ') orelse s.len;
    return std.fmt.parseInt(i16, s[0..end], 10) catch -100;
}

fn add(nets: *[NETS_MAX]Net, n: usize, c: Net) usize {
    if (std.mem.allEqual(u8, c.ssid.slice(), 0)) return n; // hidden: no SSID, or iw's \x00 padding
    for (nets[0..n]) |*have| if (have.ssid.eql(&c.ssid)) {
        have.dbm = @max(have.dbm, c.dbm);
        have.secured = have.secured or c.secured;
        return n;
    };
    if (n == NETS_MAX) { // full: a stronger one replaces the weakest
        const weakest = std.mem.indexOfMin(i16, &dbms(nets));
        if (nets[weakest].dbm < c.dbm) nets[weakest] = c;
        return n;
    }
    nets[n] = c;
    return n + 1;
}

fn dbms(nets: *const [NETS_MAX]Net) [NETS_MAX]i16 {
    var out: [NETS_MAX]i16 = undefined;
    for (nets, &out) |x, *d| d.* = x.dbm;
    return out;
}

/// 0..4 bars from a signal in dBm (-50 and up is full).
pub fn bars(d: i16) u8 {
    if (d >= -55) return 4;
    if (d >= -65) return 3;
    if (d >= -75) return 2;
    if (d >= -85) return 1;
    return 0;
}

/// `iw dev <if> link`: the SSID it is associated with, or null ("Not connected.").
pub fn link(out: []const u8) ?wc.Ssid {
    if (!std.mem.startsWith(u8, out, "Connected to ")) return null;
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "\tSSID: ")) return unescape(line["\tSSID: ".len..]);
    }
    return null;
}

/// `ip addr show dev <if>` (or its -o one-line form): the first IPv4 address ("192.168.0.16"),
/// or null when it has none.
pub fn addr(out: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, out, " inet ") orelse return null;
    const rest = out[at + " inet ".len ..];
    const end = std.mem.indexOfAny(u8, rest, "/ \n") orelse rest.len;
    return if (end == 0 or end > 15) null else rest[0..end];
}

pub const Outcome = enum { pending, connected, wrong_key, not_found };

/// How a join stands, from wpa_supplicant's log (-f, info level: it never prints a key).
/// A wrong key wins over a later retry; "not found" only says why a timeout happened.
pub fn outcome(log: []const u8) Outcome {
    const has = struct {
        fn f(s: []const u8, part: []const u8) bool {
            return std.mem.indexOf(u8, s, part) != null;
        }
    }.f;
    if (has(log, "CTRL-EVENT-CONNECTED")) return .connected;
    if (has(log, "reason=WRONG_KEY") or has(log, "pre-shared key may be incorrect")) return .wrong_key;
    if (has(log, "CTRL-EVENT-NETWORK-NOT-FOUND")) return .not_found;
    return .pending;
}
