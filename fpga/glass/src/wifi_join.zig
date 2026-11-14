// A join (wifi_job.zig): hash the key, start our wpa_supplicant on it, wait for its log to say
// how it went, ask DHCP for an address; on any failure put back the network the card names.
const std = @import("std");
const wc = @import("wifi_conf.zig");
const wp = @import("wifi_parse.zig");
const job = @import("wifi_job.zig");

const Ctx = job.Context;
const POLL_MS = 500;

pub fn join(c: *Ctx, req: *job.Request, res: *job.Result) void {
    res.fail = attempt(c, req, res);
    if (res.fail == .none) return;
    std.crypto.secureZero(u8, &res.conf_buf); // not saved: nothing of the key stays
    res.conf_len = 0;
    if (res.fail == .bad_pass or res.fail == .conf_write) return; // nothing was stopped
    _ = c.run(.stop);
    rejoinSaved(c);
}

fn attempt(c: *Ctx, req: *job.Request, res: *job.Result) job.Fail {
    var key: wc.Psk = undefined;
    defer std.crypto.secureZero(u8, &key);
    if (!req.open) key = wc.psk(req.ssid.slice(), req.pass[0..req.pass_len]) catch return .bad_pass;
    const block = wc.format(&res.conf_buf, req.ssid.slice(), if (req.open) null else &key) catch return .conf_write;
    res.conf_len = block.len;
    writeRun(c, "osd.conf", block) catch return .conf_write;
    deleteRun(c, "osd.log");
    _ = c.run(.stop); // S99wifi's, or the one a previous join started
    c.env.nap(POLL_MS); // let it let go of the interface
    _ = c.run(.up);
    if (!c.run(.start).ok) { // the old one may still be letting go: once more, a second later
        c.env.nap(1000);
        if (!c.run(.start).ok) return .supplicant;
    }
    const how = wait(c);
    if (how != .none) return how;
    if (!c.run(.dhcp).ok) return .no_address;
    return .none;
}

/// Polls our log until it says connected or wrong key, or the time is up.
fn wait(c: *Ctx) job.Fail {
    var last: wp.Outcome = .pending;
    var waited: u32 = 0;
    while (waited < c.env.join_s * 1000) : (waited += POLL_MS) {
        c.env.nap(POLL_MS);
        last = wp.outcome(readRun(c, "osd.log"));
        switch (last) {
            .connected => return .none,
            .wrong_key => return .wrong_key,
            .pending, .not_found => {},
        }
    }
    return if (last == .not_found) .not_found else .timeout;
}

/// What S99wifi does at boot, from the card's wifi.conf (its CRs dropped); none there: stay off.
fn rejoinSaved(c: *Ctx) void {
    var path: [std.fs.max_path_bytes]u8 = undefined;
    const p = std.fmt.bufPrint(&path, "{s}/{s}", .{ c.env.card_dir, wc.FILE }) catch return;
    var buf: [wc.MAX_BYTES]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(c.env.io, p, &buf) catch return;
    var clean: [wc.MAX_BYTES]u8 = undefined;
    var n: usize = 0;
    for (text) |ch| if (ch != '\r') {
        clean[n] = ch;
        n += 1;
    };
    writeRun(c, "wpa.conf", clean[0..n]) catch return;
    std.crypto.secureZero(u8, &clean);
    if (c.runWith(.start, "wpa.conf", "wpa.log").ok) _ = c.run(.dhcp_bg);
}

/// A file in run_dir (made 0700, as S99wifi makes it), written 0600: it holds a key.
fn writeRun(c: *Ctx, name: []const u8, data: []const u8) !void {
    const io = c.env.io;
    std.Io.Dir.cwd().createDir(io, c.env.run_dir, .fromMode(0o700)) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var d = try std.Io.Dir.cwd().openDir(io, c.env.run_dir, .{});
    defer d.close(io);
    d.deleteFile(io, name) catch {}; // created fresh, so the mode below is the one it gets
    try d.writeFile(io, .{ .sub_path = name, .data = data, .flags = .{ .permissions = .fromMode(0o600) } });
}

fn deleteRun(c: *Ctx, name: []const u8) void {
    var d = std.Io.Dir.cwd().openDir(c.env.io, c.env.run_dir, .{}) catch return;
    defer d.close(c.env.io);
    d.deleteFile(c.env.io, name) catch {};
}

/// The log's first LOG_TAIL bytes (in Ctx.out, free between commands): a fresh log per join, and
/// at info level 20 s of retries stay far below it.
const LOG_TAIL = 16 * 1024;
fn readRun(c: *Ctx, name: []const u8) []const u8 {
    var path: [std.fs.max_path_bytes]u8 = undefined;
    const p = std.fmt.bufPrint(&path, "{s}/{s}", .{ c.env.run_dir, name }) catch return "";
    const buf = c.out[0..@min(c.out.len, LOG_TAIL)];
    return std.Io.Dir.cwd().readFile(c.env.io, p, buf) catch "";
}
