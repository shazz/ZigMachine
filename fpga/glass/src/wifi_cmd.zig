// The Wi-Fi page's commands (wifi_job.zig runs them): where each tool is, which interface is the
// Wi-Fi one, and every command line as a list of arguments. Nothing goes through a shell, so an
// SSID can hold any byte; the SSID and the key never appear in an argv at all (they go in a
// 0600 conf file, wifi_conf.zig).
//
// The tools: the image's own (feat/board-wifi's Buildroot: wpa_supplicant + iw; busybox's ip,
// udhcpc and killall), or, until that image is installed, the copies pushed to RAM in /tmp/up
// (they need LD_LIBRARY_PATH=/tmp/up for their libnl).
const std = @import("std");

pub const RAM_DIR = "/tmp/up";
pub const DEFAULT_PATH = "/usr/sbin:/usr/bin:/sbin:/bin";

pub const Tool = enum { iw, wpa_supplicant, udhcpc, ip, killall };
const TOOLS = std.enums.values(Tool);
const PATH_MAX = 96;

pub const Tools = struct {
    buf: [TOOLS.len][PATH_MAX]u8 = undefined,
    len: [TOOLS.len]u8 = .{0} ** TOOLS.len,
    /// A tool came from RAM_DIR: run them all with LD_LIBRARY_PATH=RAM_DIR.
    ram: bool = false,

    pub fn path(self: *const Tools, t: Tool) []const u8 {
        const i = @intFromEnum(t);
        return self.buf[i][0..self.len[i]];
    }

    /// The first tool not found, or null when every one is there.
    pub fn missing(self: *const Tools) ?Tool {
        for (TOOLS) |t| if (self.len[@intFromEnum(t)] == 0) return t;
        return null;
    }
};

fn exists(io: std.Io, p: []const u8) bool {
    std.Io.Dir.cwd().access(io, p, .{}) catch return false;
    return true;
}

/// Each tool from the first directory of `path_env` that has it, then `ram_dir`.
pub fn find(io: std.Io, path_env: []const u8, ram_dir: []const u8) Tools {
    var out = Tools{};
    for (TOOLS) |t| {
        const i = @intFromEnum(t);
        var dirs = std.mem.tokenizeScalar(u8, path_env, ':');
        const ram = while (dirs.next()) |d| {
            if (place(io, &out.buf[i], &out.len[i], d, @tagName(t))) break false;
        } else place(io, &out.buf[i], &out.len[i], ram_dir, @tagName(t));
        out.ram = out.ram or (ram and out.len[i] != 0);
    }
    return out;
}

fn place(io: std.Io, buf: *[PATH_MAX]u8, len: *u8, dir: []const u8, name: []const u8) bool {
    const p = std.fmt.bufPrint(buf, "{s}/{s}", .{ dir, name }) catch return false;
    if (!exists(io, p)) return false;
    len.* = @intCast(p.len);
    return true;
}

pub const IFACE_MAX = 15; // IFNAMSIZ - 1

pub const Iface = struct {
    buf: [IFACE_MAX]u8 = undefined,
    len: u8 = 0,

    pub fn name(self: *const Iface) []const u8 {
        return self.buf[0..self.len];
    }
};

/// The first network interface with a `wireless` directory under `sys_root`/sys/class/net
/// (the BCM43143 dongle's is wlan0); null: no Wi-Fi dongle, or its driver did not bind.
pub fn iface(io: std.Io, sys_root: []const u8) ?Iface {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const net = std.fmt.bufPrint(&buf, "{s}/sys/class/net", .{std.mem.trimEnd(u8, sys_root, "/")}) catch return null;
    var dir = std.Io.Dir.cwd().openDir(io, net, .{ .iterate = true }) catch return null;
    defer dir.close(io);
    var best: ?Iface = null;
    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if (e.name.len > IFACE_MAX) continue;
        var sub: [IFACE_MAX + 16]u8 = undefined;
        const w = std.fmt.bufPrint(&sub, "{s}/wireless", .{e.name}) catch continue;
        dir.access(io, w, .{}) catch continue;
        var f = Iface{ .len = @intCast(e.name.len) };
        @memcpy(f.buf[0..e.name.len], e.name);
        // Directory order is the file system's: take the smallest name, so wlan0 before wlan1.
        if (best == null or std.mem.order(u8, f.name(), best.?.name()) == .lt) best = f;
    }
    return best;
}

/// A command line: at most ARGS arguments, each a slice the caller keeps alive.
pub const ARGS = 10;
pub const Argv = struct {
    args: [ARGS][]const u8 = undefined,
    n: usize = 0,

    pub fn of(parts: []const []const u8) Argv {
        var a = Argv{ .n = parts.len };
        @memcpy(a.args[0..parts.len], parts);
        return a;
    }

    pub fn slice(self: *const Argv) []const []const u8 {
        return self.args[0..self.n];
    }
};

pub const Cmd = enum { up, scan, link, addr, stop, start, dhcp, dhcp_bg, flush };

/// The command `c` on interface `ifn`; `conf` and `log` are start's files.
pub fn argv(t: *const Tools, c: Cmd, ifn: []const u8, conf: []const u8, log: []const u8) Argv {
    return switch (c) {
        .up => Argv.of(&.{ t.path(.ip), "link", "set", ifn, "up" }),
        .scan => Argv.of(&.{ t.path(.iw), "dev", ifn, "scan" }),
        .link => Argv.of(&.{ t.path(.iw), "dev", ifn, "link" }),
        .addr => Argv.of(&.{ t.path(.ip), "addr", "show", "dev", ifn }), // busybox's: no -4/-o needed
        .stop => Argv.of(&.{ t.path(.killall), "-q", "wpa_supplicant" }),
        .start => Argv.of(&.{ t.path(.wpa_supplicant), "-B", "-i", ifn, "-c", conf, "-f", log }),
        // At most 5 tries 2 s apart, then give up (-n) or quit with the lease (-q): bounded.
        .dhcp => Argv.of(&.{ t.path(.udhcpc), "-i", ifn, "-q", "-n", "-t", "5", "-T", "2" }),
        .dhcp_bg => Argv.of(&.{ t.path(.udhcpc), "-b", "-i", ifn }), // S99wifi's: renews in the background
        .flush => Argv.of(&.{ t.path(.ip), "addr", "flush", "dev", ifn }),
    };
}
