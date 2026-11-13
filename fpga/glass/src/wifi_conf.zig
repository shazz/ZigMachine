// KESTREL/wifi.conf: the network the board joins at boot (S99wifi, fpga/docs/PREREQUISITES.md "Wi-Fi"),
// in wpa_supplicant's own format, which S99wifi copies to /tmp/wifi/wpa.conf unchanged. The OSD's Wi-Fi
// page (page_wifi.zig) writes it after a join worked, and reads back which network it names.
//
// The password never reaches the card, an argv or a log: the key stored is the WPA2 PSK, as
// wpa_passphrase prints it (PBKDF2-HMAC-SHA1 of the passphrase, salted with the SSID, 4096 rounds,
// 32 bytes), computed here, and the passphrase buffer is zeroed as soon as it is hashed.
//
// The SSID is written `ssid="..."` when every byte is printable ASCII (wpa_supplicant takes the text
// between the first and the LAST quote, so a quote inside is fine), else as hex (`ssid=436166c3a9`:
// UTF-8, control bytes), both standard forms; nothing is ever escaped, so nothing can be escaped wrong.
const std = @import("std");

pub const FILE = "wifi.conf";
pub const SSID_MAX = 32; // 802.11's limit
pub const PASS_MIN = 8; // WPA2-Personal's passphrase: 8..63 printable ASCII characters
pub const PASS_MAX = 63;
pub const PSK_HEX = 64;
pub const MAX_BYTES = 4096; // a hand-written file with several networks still fits

pub const Ssid = struct {
    buf: [SSID_MAX]u8 = undefined,
    len: u8 = 0,

    pub fn of(s: []const u8) ?Ssid {
        if (s.len == 0 or s.len > SSID_MAX) return null;
        var out = Ssid{ .len = @intCast(s.len) };
        @memcpy(out.buf[0..s.len], s);
        return out;
    }

    pub fn slice(self: *const Ssid) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn eql(self: *const Ssid, other: *const Ssid) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }
};

pub const Psk = [PSK_HEX]u8;

/// A passphrase WPA2 accepts: 8..63 printable ASCII characters (wpa_passphrase refuses others).
pub fn validPass(pass: []const u8) bool {
    if (pass.len < PASS_MIN or pass.len > PASS_MAX) return false;
    for (pass) |c| if (c < 0x20 or c > 0x7E) return false;
    return true;
}

/// The PSK as 64 lower-case hex digits; `pass` is zeroed whatever happens.
pub fn psk(ssid: []const u8, pass: []u8) error{BadPassphrase}!Psk {
    defer std.crypto.secureZero(u8, pass);
    if (!validPass(pass) or ssid.len == 0 or ssid.len > SSID_MAX) return error.BadPassphrase;
    var key: [32]u8 = undefined;
    defer std.crypto.secureZero(u8, &key);
    std.crypto.pwhash.pbkdf2(&key, pass, ssid, 4096, std.crypto.auth.hmac.HmacSha1) catch return error.BadPassphrase;
    return std.fmt.bytesToHex(key, .lower);
}

fn printable(s: []const u8) bool {
    for (s) |c| if (c < 0x20 or c > 0x7E) return false;
    return true;
}

/// One network block: secured with `key` (a PSK), or open (key_mgmt=NONE) when null.
pub fn format(buf: []u8, ssid: []const u8, key: ?*const Psk) error{WriteFailed}![]const u8 {
    var w = std.Io.Writer.fixed(buf);
    try w.writeAll("# KESTREL Wi-Fi (glass OSD). psk is the hashed key: the passphrase is never stored.\nnetwork={\n\tssid=");
    if (printable(ssid)) try w.print("\"{s}\"\n", .{ssid}) else try w.print("{x}\n", .{ssid});
    if (key) |k| try w.print("\tpsk={s}\n", .{k}) else try w.writeAll("\tkey_mgmt=NONE\n");
    try w.writeAll("}\n");
    return w.buffered();
}

/// What a wifi.conf names: its first network's SSID, and whether that one is open.
pub const Saved = struct { ssid: Ssid, open: bool };

/// The first `network={...}` block's ssid (quoted, hex, or P"..." left out); null if none is readable.
pub fn parse(text: []const u8) ?Saved {
    var in_block = false;
    var got: ?Ssid = null;
    var open = false;
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |raw| {
        const l = std.mem.trim(u8, raw, " \t");
        if (l.len == 0 or l[0] == '#') continue;
        if (!in_block) {
            in_block = std.mem.startsWith(u8, l, "network={");
            continue;
        }
        if (l[0] == '}') return if (got) |s| .{ .ssid = s, .open = open } else null;
        if (std.mem.startsWith(u8, l, "ssid=")) got = ssidValue(l["ssid=".len..]);
        if (std.mem.eql(u8, l, "key_mgmt=NONE")) open = true;
    }
    return null;
}

fn ssidValue(v: []const u8) ?Ssid {
    if (v.len >= 2 and v[0] == '"') {
        const end = std.mem.lastIndexOfScalar(u8, v, '"') orelse return null;
        return if (end == 0) null else Ssid.of(v[1..end]);
    }
    if (v.len % 2 != 0 or v.len > 2 * SSID_MAX) return null;
    var bytes: [SSID_MAX]u8 = undefined;
    const got = std.fmt.hexToBytes(&bytes, v) catch return null;
    return Ssid.of(got);
}

/// The card's wifi.conf, or null when there is none (or it cannot be read).
pub fn load(io: std.Io, dir: []const u8, buf: *[MAX_BYTES]u8) ?Saved {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir, FILE }) catch return null;
    const text = std.Io.Dir.cwd().readFile(io, path, buf) catch return null;
    return parse(text);
}

/// Written beside it and renamed over it (config.save's way): a cut mid-write keeps the old file.
pub fn save(io: std.Io, dir: []const u8, text: []const u8) !void {
    var d = try std.Io.Dir.cwd().openDir(io, dir, .{});
    defer d.close(io);
    try d.writeFile(io, .{ .sub_path = FILE ++ ".new", .data = text });
    try d.rename(FILE ++ ".new", d, FILE, io);
}

/// The saved network gone; none there already is not an error.
pub fn remove(io: std.Io, dir: []const u8) !void {
    var d = try std.Io.Dir.cwd().openDir(io, dir, .{});
    defer d.close(io);
    d.deleteFile(io, FILE) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}
