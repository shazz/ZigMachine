// The board's Wi-Fi tools played from canned output, for the Wi-Fi tests (wifi_job_test.zig,
// wifi_join_test.zig, app_wifi_test.zig): a directory with the tools' names in bin/ (or up/, the
// RAM copies), a /sys with wlan0, a card directory, and a runner that answers each argv and
// remembers it. wpa_supplicant "writes" `log` to its -f file, as the real one would.
const std = @import("std");
const job = @import("wifi_job.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;

pub const SCAN = "BSS 11:22:33:44:55:77(on wlan0)\n\tcapability: ESS Privacy (0x0411)\n\tsignal: -48.00 dBm\n\tSSID: Metaverse\n\tRSN:\t * Version: 1\n" ++
    "BSS aa:bb:cc:dd:ee:01(on wlan0)\n\tcapability: ESS (0x0401)\n\tsignal: -70.00 dBm\n\tSSID: \\x20Cafe Libre\\x20\n";
pub const CONNECTED = "wlan0: CTRL-EVENT-CONNECTED - Connection to 11:22:33:44:55:77 completed\n";

pub const Fake = struct {
    tmp: std.testing.TmpDir,
    root: []u8, // .zig-cache/tmp/<x>: bin/, up/, sys/, card/, run/
    paths: [5][]u8 = undefined, // bin, up, sys root, card, run
    calls: [40][200]u8 = undefined,
    lens: [40]usize = undefined,
    n: usize = 0,
    ram_seen: bool = false,
    scan_out: []const u8 = SCAN,
    scan_busy: u32 = 0, // the next N scans fail ("Device or resource busy")
    link_out: []const u8 = "Not connected.\n",
    addr_out: []const u8 = "",
    start_ok: bool = true,
    start_busy: u32 = 0, // the next N starts fail (the old one still holds the interface)
    log: []const u8 = CONNECTED,
    dhcp_ok: bool = true,

    /// `tools_in`: "bin", "up" (the RAM copies), or "" (none).
    pub fn init(tools_in: []const u8) !*Fake {
        const f = try gpa.create(Fake);
        f.* = .{ .tmp = std.testing.tmpDir(.{}), .root = undefined };
        f.root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{f.tmp.sub_path});
        for ([_][]const u8{ "bin", "up", "", "card", "run" }, &f.paths) |sub, *p| p.* = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ f.root, sub });
        for ([_][]const u8{ "bin", "up", "card", "sys/class/net/wlan0/wireless", "sys/class/net/eth0" }) |d| try f.tmp.dir.createDirPath(io, d);
        if (tools_in.len != 0) for ([_][]const u8{ "iw", "wpa_supplicant", "udhcpc", "ip", "killall" }) |t| {
            var b: [64]u8 = undefined;
            try f.tmp.dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&b, "{s}/{s}", .{ tools_in, t }), .data = "" });
        };
        return f;
    }

    pub fn deinit(f: *Fake) void {
        f.tmp.cleanup();
        for (f.paths) |p| gpa.free(p);
        gpa.free(f.root);
        gpa.destroy(f);
    }

    pub fn env(f: *Fake) job.Env {
        return .{ .io = io, .runner = .{ .ctx = f, .run = run }, .card_dir = f.paths[3], .nap = noNap, .sys_root = f.paths[2], .path_env = f.paths[0], .ram_dir = f.paths[1], .run_dir = f.paths[4], .join_s = 2 };
    }

    pub fn call(f: *const Fake, i: usize) []const u8 {
        return f.calls[i][0..f.lens[i]];
    }

    /// The call that starts with `prefix` (tool name, then its arguments, '|' between), or null.
    pub fn find(f: *const Fake, prefix: []const u8) ?usize {
        for (0..f.n) |i| if (std.mem.startsWith(u8, f.call(i), prefix)) return i;
        return null;
    }

    /// Any argument of any call that contains `s`.
    pub fn saw(f: *const Fake, s: []const u8) bool {
        for (0..f.n) |i| if (std.mem.indexOf(u8, f.call(i), s) != null) return true;
        return false;
    }

    fn run(ctx: ?*anyopaque, argv: []const []const u8, ram: bool, out: []u8) job.Ran {
        const f: *Fake = @ptrCast(@alignCast(ctx.?));
        f.record(argv);
        f.ram_seen = f.ram_seen or ram;
        const tool = std.fs.path.basename(argv[0]);
        const eql = std.mem.eql;
        if (eql(u8, tool, "iw") and eql(u8, argv[3], "scan")) {
            if (f.scan_busy > 0) f.scan_busy -= 1 else return give(out, true, f.scan_out);
            return give(out, false, "");
        }
        if (eql(u8, tool, "iw")) return give(out, true, f.link_out);
        if (eql(u8, tool, "ip") and eql(u8, argv[1], "addr") and eql(u8, argv[2], "show")) return give(out, true, f.addr_out);
        if (eql(u8, tool, "wpa_supplicant")) {
            if (f.start_busy > 0) {
                f.start_busy -= 1;
                return give(out, false, "");
            }
            if (f.start_ok) std.Io.Dir.cwd().writeFile(io, .{ .sub_path = argv[7], .data = f.log }) catch return give(out, false, "");
            return give(out, f.start_ok, "");
        }
        if (eql(u8, tool, "udhcpc") and eql(u8, argv[3], "-q")) {
            if (f.dhcp_ok) f.addr_out = "3: wlan0    inet 192.168.0.16/24 brd 192.168.0.255 scope global wlan0\n";
            return give(out, f.dhcp_ok, "");
        }
        return give(out, true, "");
    }

    fn record(f: *Fake, argv: []const []const u8) void {
        if (f.n == f.calls.len) @panic("wifi_fake: more calls than a job makes");
        var w = std.Io.Writer.fixed(&f.calls[f.n]);
        w.writeAll(std.fs.path.basename(argv[0])) catch {};
        for (argv[1..]) |a| w.print("|{s}", .{a}) catch {};
        f.lens[f.n] = w.buffered().len;
        f.n += 1;
    }
};

fn give(out: []u8, ok: bool, s: []const u8) job.Ran {
    @memcpy(out[0..s.len], s);
    return .{ .ok = ok, .out = out[0..s.len] };
}

fn noNap(_: u32) void {}
