// The network spike (docs/ROADMAP.md, "Wi-Fi ... TCP/IP for GEM 5"): a cart reaches the network
// through C:, with no new ABI. A program saves C:\NET\<NAME>.REQ: its first line is
// "<a.b.c.d> <port>", the rest is sent over TCP. glass (kos_file.zig, after the write) connects,
// sends, collects the reply until the peer closes or goes quiet, and writes it to C:\NET\<NAME>.ANS,
// which the program then reads as any file (the C: generation bump makes the ROM re-read the
// folder). A failure writes "ERR <why>" instead. Bounded: REQ_MAX in, ANS_MAX out, and the whole
// exchange inside the firmware's KOS_FILE_TIMEOUT_MS (10 s): CONNECT_MS + REPLY_MS + the write.
// IPv4 dotted addresses only (no DNS yet).
const std = @import("std");
const linux = std.os.linux;
const fs = @import("kos_fs.zig");

pub const FOLDER = "NET";
pub const REQ_MAX = 4096;
pub const ANS_MAX = 16384;
pub const CONNECT_MS = 3000;
pub const REPLY_MS = 4000; // the whole reply
pub const QUIET_MS = 800; // after the first reply bytes: this long with nothing more ends it

/// The request a .REQ file holds.
pub const Req = struct { addr: [4]u8, port: u16, payload: []const u8 };

/// True for C:\NET\<name>.REQ: the writes kos_file.zig hands to `serve`.
pub fn isRequest(parent: []const []const u8, name: []const u8) bool {
    return parent.len == 1 and std.mem.eql(u8, parent[0], FOLDER) and std.mem.endsWith(u8, name, ".REQ");
}

/// "a.b.c.d port\r?\n<payload>", or null.
pub fn parse(text: []const u8) ?Req {
    const nl = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    const head = std.mem.trimEnd(u8, text[0..nl], "\r ");
    const sp = std.mem.indexOfScalar(u8, head, ' ') orelse return null;
    var r = Req{ .addr = undefined, .port = 0, .payload = if (nl < text.len) text[nl + 1 ..] else "" };
    var it = std.mem.splitScalar(u8, head[0..sp], '.');
    var i: usize = 0;
    while (it.next()) |part| : (i += 1) {
        if (i == 4) return null;
        r.addr[i] = std.fmt.parseInt(u8, part, 10) catch return null;
    }
    if (i != 4) return null;
    r.port = std.fmt.parseInt(u16, std.mem.trim(u8, head[sp + 1 ..], " "), 10) catch return null;
    return if (r.port == 0) null else r;
}

/// Serve C:\NET\<name>.REQ (already on the card, `dir` = C:\NET): write <base>.ANS.
pub fn serve(dir: i32, name: []const u8) void {
    var req: [REQ_MAX]u8 = undefined;
    var ans: [ANS_MAX]u8 = undefined;
    const n = readAll(dir, name, &req) catch return answer(dir, name, "ERR cannot read the request\r\n");
    const r = parse(req[0..n]) orelse return answer(dir, name, "ERR first line must be: a.b.c.d port\r\n");
    const got = exchange(r, &ans) catch |e| {
        var b: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&b, "ERR {t}\r\n", .{e}) catch "ERR\r\n";
        return answer(dir, name, msg);
    };
    answer(dir, name, ans[0..got]);
}

fn answer(dir: i32, req_name: []const u8, data: []const u8) void {
    var b: [12]u8 = undefined;
    const base = req_name[0 .. req_name.len - 4];
    const name = std.fmt.bufPrint(&b, "{s}.ANS", .{base}) catch return;
    fs.writeAt(dir, name, true, 0, data) catch |e| std.log.warn("NET: {s}: {t}", .{ name, e });
}

fn readAll(dir: i32, name: []const u8, buf: []u8) !usize {
    var zb: [16]u8 = undefined;
    const rc = linux.openat(dir, fs.z(name, &zb), .{ .ACCMODE = .RDONLY, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return error.Open;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var n: usize = 0;
    while (n < buf.len) {
        const k = linux.read(fd, buf[n..].ptr, buf.len - n);
        if (linux.errno(k) != .SUCCESS) return error.Read;
        if (k == 0) break;
        n += k;
    }
    return n;
}

pub const NetError = error{ Socket, ConnectTimeout, ConnectRefused, SendFailed, ReceiveFailed };

/// Connect, send the payload, collect the reply into `out`: its length.
pub fn exchange(r: Req, out: []u8) NetError!usize {
    const rc = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(rc) != .SUCCESS) return error.Socket;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    try connect(fd, r);
    var sent: usize = 0;
    while (sent < r.payload.len) {
        if (!wait(fd, linux.POLL.OUT, CONNECT_MS)) return error.SendFailed;
        const k = linux.sendto(fd, r.payload[sent..].ptr, r.payload.len - sent, linux.MSG.NOSIGNAL, null, 0);
        if (linux.errno(k) != .SUCCESS) return error.SendFailed;
        sent += k;
    }
    return receive(fd, out);
}

fn connect(fd: i32, r: Req) NetError!void {
    const sa = linux.sockaddr.in{ .port = std.mem.nativeToBig(u16, r.port), .addr = @bitCast(r.addr) };
    const rc = linux.connect(fd, &sa, @sizeOf(linux.sockaddr.in));
    const e = linux.errno(rc);
    if (e != .SUCCESS and e != .INPROGRESS) return error.ConnectRefused;
    if (!wait(fd, linux.POLL.OUT, CONNECT_MS)) return error.ConnectTimeout;
    var err: u32 = 0;
    var len: linux.socklen_t = 4;
    _ = linux.getsockopt(fd, linux.SOL.SOCKET, linux.SO.ERROR, @ptrCast(&err), &len);
    if (err != 0) return error.ConnectRefused;
}

/// Until the peer closes, `out` is full, QUIET_MS pass with nothing new after some data, or REPLY_MS in all.
fn receive(fd: i32, out: []u8) NetError!usize {
    var n: usize = 0;
    var left: i32 = REPLY_MS;
    while (n < out.len and left > 0) {
        const step: i32 = if (n == 0) left else @min(left, QUIET_MS);
        const t0 = nowMs();
        if (!wait(fd, linux.POLL.IN, step)) break;
        left -= @intCast(@min(nowMs() - t0, REPLY_MS));
        const k = linux.recvfrom(fd, out[n..].ptr, out.len - n, 0, null, null);
        const e = linux.errno(k);
        if (e == .AGAIN) continue;
        if (e != .SUCCESS) return if (n > 0) n else error.ReceiveFailed;
        if (k == 0) break; // closed
        n += k;
    }
    return n;
}

fn wait(fd: i32, events: i16, ms: i32) bool {
    var p = [1]linux.pollfd{.{ .fd = fd, .events = events, .revents = 0 }};
    const rc = linux.poll(&p, 1, ms);
    return linux.errno(rc) == .SUCCESS and rc == 1;
}

fn nowMs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
}
