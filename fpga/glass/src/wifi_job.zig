// What the Wi-Fi page asks for, done: read the state, scan, join, forget. Runs on its own thread
// (wifi_worker.zig): a scan takes seconds and a join up to JOIN_S, and glass's loop serves the
// cart and the OSD meanwhile. Every command goes through `Env.runner` (an argv, never a shell),
// so wifi_job_test.zig plays the board's tools from canned output.
//
// A join owns wpa_supplicant: the one S99wifi started (or none, with no wifi.conf on the card) is
// stopped, ours starts on /tmp/wifi/osd.conf (0600, the hashed key) and its log tells how it went.
// Only when it is associated AND has an address does the result carry the block for the card;
// app_wifi.zig writes it there (the main thread owns the card). A failed join stops ours and
// rejoins what the card names, as S99wifi would have, so a typo never leaves the board offline.
const std = @import("std");
const wc = @import("wifi_conf.zig");
const cmd = @import("wifi_cmd.zig");
const wp = @import("wifi_parse.zig");

pub const Ran = struct { ok: bool, out: []const u8 };
pub const Runner = struct {
    ctx: ?*anyopaque = null,
    /// Run `argv` to its end; stdout lands in `out` (cut to fit). `ram`: the tools came from /tmp/up.
    run: *const fn (ctx: ?*anyopaque, argv: []const []const u8, ram: bool, out: []u8) Ran,
};

pub const Env = struct {
    io: std.Io,
    runner: Runner,
    card_dir: []const u8, // where wifi.conf is (KESTREL/), for the rejoin after a failed join
    nap: *const fn (ms: u32) void,
    sys_root: []const u8 = "/",
    path_env: []const u8 = cmd.DEFAULT_PATH,
    ram_dir: []const u8 = cmd.RAM_DIR,
    run_dir: []const u8 = "/tmp/wifi", // S99wifi's: its wpa.conf and wpa.log are here too
    join_s: u32 = 20,
};

pub const Kind = enum { status, scan, join, forget };
pub const Fail = enum { none, no_tools, no_iface, scan_failed, bad_pass, conf_write, supplicant, wrong_key, not_found, timeout, no_address };

pub const Request = struct {
    kind: Kind,
    ssid: wc.Ssid = .{},
    open: bool = false,
    pass: [wc.PASS_MAX + 1]u8 = undefined,
    pass_len: u8 = 0,
};

pub const Result = struct {
    kind: Kind = .status,
    fail: Fail = .none,
    missing: ?cmd.Tool = null,
    connected: ?wc.Ssid = null,
    ip_buf: [15]u8 = undefined,
    ip_len: u8 = 0,
    nets: [wp.NETS_MAX]wp.Net = undefined,
    n_nets: usize = 0,
    conf_buf: [256]u8 = undefined, // a join's network block, for the card (no password in it)
    conf_len: usize = 0,

    pub fn ip(self: *const Result) []const u8 {
        return self.ip_buf[0..self.ip_len];
    }

    pub fn conf(self: *const Result) []const u8 {
        return self.conf_buf[0..self.conf_len];
    }
};

const Ctx = struct {
    env: *const Env,
    tools: *const cmd.Tools,
    ifn: []const u8,
    out: []u8,
    paths: [2][std.fs.max_path_bytes]u8 = undefined,

    pub fn run(c: *Ctx, k: cmd.Cmd) Ran {
        return c.runWith(k, "osd.conf", "osd.log");
    }

    pub fn runWith(c: *Ctx, k: cmd.Cmd, conf: []const u8, log: []const u8) Ran {
        const cp = c.file(0, conf) catch return .{ .ok = false, .out = "" };
        const lp = c.file(1, log) catch return .{ .ok = false, .out = "" };
        const a = cmd.argv(c.tools, k, c.ifn, cp, lp);
        return c.env.runner.run(c.env.runner.ctx, a.slice(), c.tools.ram, c.out);
    }

    fn file(c: *Ctx, slot: usize, name: []const u8) ![]const u8 {
        return std.fmt.bufPrint(&c.paths[slot], "{s}/{s}", .{ c.env.run_dir, name });
    }
};

/// Do `req`, then read the state it left; `scratch` holds a command's output (a scan's is the big one).
/// The passphrase in `req` is zeroed before this returns.
pub fn perform(env: *const Env, req: *Request, res: *Result, scratch: []u8) void {
    defer std.crypto.secureZero(u8, &req.pass);
    res.* = .{ .kind = req.kind };
    const tools = cmd.find(env.io, env.path_env, env.ram_dir);
    if (tools.missing()) |t| {
        res.fail = .no_tools;
        res.missing = t;
        return;
    }
    const ifc = cmd.iface(env.io, env.sys_root) orelse {
        res.fail = .no_iface;
        return;
    };
    var c = Ctx{ .env = env, .tools = &tools, .ifn = ifc.name(), .out = scratch };
    switch (req.kind) {
        .status => {},
        .scan => scan(&c, res),
        .join => @import("wifi_join.zig").join(&c, req, res),
        .forget => {
            _ = c.run(.stop);
            _ = c.run(.flush);
        },
    }
    state(&c, res);
}

fn scan(c: *Ctx, res: *Result) void {
    _ = c.run(.up);
    var r = c.run(.scan);
    if (!r.ok) { // "Device or resource busy": wpa_supplicant is scanning; once more after it
        c.env.nap(1500);
        r = c.run(.scan);
    }
    if (!r.ok) {
        res.fail = .scan_failed;
        return;
    }
    res.n_nets = wp.scan(r.out, &res.nets);
}

/// The network it is on and its address, whatever the job did.
fn state(c: *Ctx, res: *Result) void {
    const l = c.run(.link);
    res.connected = if (l.ok) wp.link(l.out) else null;
    const a = c.run(.addr);
    const got = if (a.ok) wp.addr(a.out) else null;
    if (got) |s| {
        @memcpy(res.ip_buf[0..s.len], s);
        res.ip_len = @intCast(s.len);
    }
}

pub const Context = Ctx;
